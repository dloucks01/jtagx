#!/usr/bin/env python3
"""
secureboot-analyze.py — GENERIC secure-boot image analyzer (cross-arch, offline, static).

The complement to parse-bootimage.py (which is ZynqMP-bootgen-specific): recognize the common
open/embedded secure-boot container formats from a dump, decode their AUTHENTICATION structure, and
emit static findings — "is this image signed/encrypted, and where is the verification an attacker
would target?". No glitch, no hardware — this is what a JTAG-extracted firmware image feeds into.

Formats: MCUboot, wolfBoot, U-Boot FIT (signed), Android boot; detects-and-defers Xilinx bootgen
(-> parse-bootimage.py) and raw ELF/Linux.

    python3 tools/secureboot-analyze.py firmware.bin
    python3 tools/secureboot-analyze.py firmware.bin --json

Cardinal rule (same as parse-bootimage.py): nothing invented — a structure that fails its magic is
reported as absent, not guessed. Findings tie the CHES-2025 instruction-skip class to the *location*
of the check (the deferred fault-injection target), without claiming to run any attack.
"""
import argparse
import base64
import hashlib
import json
import os
import struct
import sys

MCUBOOT_MAGIC = 0x96F3B83D          # MCUboot image_header.ih_magic (LE u32 @0)
MCUBOOT_TLV_INFO = 0x6907           # IMAGE_TLV_INFO_MAGIC (unprotected TLV area)
MCUBOOT_TLV_PROT = 0x6908           # protected TLV area
# real MCUboot IMAGE_TLV_* values (bootutil/image.h) — corrected from the Phase-4 stub.
MCUBOOT_TLV = {0x01: "KEYHASH", 0x02: "PUBKEY", 0x10: "SHA256", 0x11: "SHA384",
               0x20: "RSA2048-PSS", 0x21: "ECDSA224", 0x22: "ECDSA-P256", 0x23: "RSA3072-PSS",
               0x24: "ED25519", 0x30: "ENC-RSA2048", 0x31: "ENC-KW", 0x32: "ENC-EC256",
               0x33: "ENC-X25519", 0x40: "DEPENDENCY", 0x50: "SEC_CNT"}
# which TLVs are an actual authentication signature, and each one's strength verdict
MCUBOOT_SIG_STRENGTH = {0x20: ("RSA2048-PSS", "ok"), 0x21: ("ECDSA-P224", "WEAK (224-bit)"),
                        0x22: ("ECDSA-P256", "ok"), 0x23: ("RSA3072-PSS", "strong"),
                        0x24: ("ED25519", "strong")}
MCUBOOT_TLV_KEYHASH, MCUBOOT_TLV_PUBKEY, MCUBOOT_TLV_SEC_CNT = 0x01, 0x02, 0x50
MCUBOOT_FLAG_ENCRYPTED = 0x04 | 0x08 | 0x10   # ENCRYPTED_AES128 / AES256 / (any enc flag)
WOLFBOOT_MAGIC = 0x464C4F57         # 'WOLF' — wolfBoot image header magic (LE u32 @0)
WOLFBOOT_TAG_SIGNATURE = 0x0020     # HDR_SIGNATURE
WOLFBOOT_TAG_SHA256 = 0x0003        # HDR_SHA256
FDT_MAGIC = 0xD00DFEED               # FIT/DTB (BE)


def u32le(d, o):
    return struct.unpack_from("<I", d, o)[0] if o + 4 <= len(d) else None


def u16le(d, o):
    return struct.unpack_from("<H", d, o)[0] if o + 2 <= len(d) else None


def _find(d, needle, start=0):
    i = d.find(needle, start)
    return i


_KNOWN_KEYS = None


def _known_key(sha256_hex):
    """Look up a signing-key SHA256 against references/known-keys/*.json — a {hash: description} DB of
    KNOWN/DEFAULT/TEST public keys (e.g. the MCUboot/wolfBoot repo test keys, or leaked vendor keys).
    Returns the description or None. The DB ships EMPTY (no fabricated hashes) — populate it from the
    real vendor repos; a match means the image is signed with a publicly-available key = forgeable."""
    global _KNOWN_KEYS
    if _KNOWN_KEYS is None:
        _KNOWN_KEYS = {}
        kd = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "references", "known-keys")
        try:
            for fn in os.listdir(kd):
                if fn.endswith(".json"):
                    for k, v in json.load(open(os.path.join(kd, fn))).items():
                        _KNOWN_KEYS[k.lower()] = v
        except Exception:
            pass
    return _KNOWN_KEYS.get((sha256_hex or "").lower())


# ---- per-format analyzers: each returns (fmt, dict-of-facts, [findings]) or None if magic absent ----
def analyze_mcuboot(d):
    if u32le(d, 0) != MCUBOOT_MAGIC:
        return None
    hdr_size = u16le(d, 8)
    img_size = u32le(d, 12)
    flags = u32le(d, 16) or 0
    ver = tuple(d[20:24]) if len(d) >= 24 else ()
    facts = {"header_size": hdr_size, "image_size": img_size, "flags": hex(flags),
             "version": ".".join(str(x) for x in ver[:3]) if ver else "?",
             "encrypted": bool(flags & MCUBOOT_FLAG_ENCRYPTED)}
    # TLV area follows header+image; enumerate ALL TLVs (semantic: sigs, key-hash, rollback counter)
    sigs, sig_types, keyhash, pubkey, sec_cnt, all_tlvs = [], [], None, None, None, []
    tlv_off = _find(d, struct.pack("<H", MCUBOOT_TLV_INFO))
    if tlv_off < 0:
        tlv_off = _find(d, struct.pack("<H", MCUBOOT_TLV_PROT))
    if tlv_off >= 0:
        total = u16le(d, tlv_off + 2) or 0
        o = tlv_off + 4
        end = min(tlv_off + total, len(d))
        while o + 4 <= end:
            t = d[o]; ln = u16le(d, o + 2) or 0
            val = d[o + 4:o + 4 + ln]
            all_tlvs.append(MCUBOOT_TLV.get(t, hex(t)))
            if t in MCUBOOT_SIG_STRENGTH:
                sigs.append(MCUBOOT_SIG_STRENGTH[t][0]); sig_types.append(t)
            elif t == MCUBOOT_TLV_KEYHASH:
                keyhash = val.hex()
            elif t == MCUBOOT_TLV_PUBKEY:
                pubkey = val
            elif t == MCUBOOT_TLV_SEC_CNT and len(val) >= 4:
                sec_cnt = struct.unpack_from("<I", val, 0)[0]
            o += 4 + ln
    # if the image EMBEDS the public key (PUBKEY TLV) but no KEYHASH, fingerprint it ourselves
    if pubkey and not keyhash:
        keyhash = hashlib.sha256(pubkey).hexdigest()
    signed = bool(sig_types)
    facts.update(signature=", ".join(sigs) or "(none)", signed=signed, key_sha256=keyhash,
                 pubkey_embedded=bool(pubkey), security_counter=sec_cnt, tlvs=all_tlvs)
    F = []
    if not signed:
        F.append(("HIGH", "unsigned-image",
                  "no signature TLV (RSA/ECDSA/ED25519) in the image — it is NOT authenticated; a modified "
                  "image boots on any MCUboot built without mandatory verification."))
    else:
        weak = [MCUBOOT_SIG_STRENGTH[t] for t in sig_types if MCUBOOT_SIG_STRENGTH[t][1].startswith("WEAK")]
        if weak:
            F.append(("HIGH", "weak-signature",
                      f"signature algorithm is weak: {', '.join(a for a, _ in weak)} — below current "
                      "strength; forgeable/collision-prone relative to RSA3072/ED25519."))
        F.append(("INFO", "sig-verify-target",
                  f"signed ({', '.join(sigs)}). MCUboot verifies in a single boot_image_validate() "
                  "accept/reject branch → an instruction-skip fault there forges acceptance (TCHES 2025). "
                  "This call is the deferred fault-injection target."))
    if keyhash:
        kv = _known_key(keyhash)
        if kv:
            F.append(("CRIT", "default-signing-key",
                      f"the signing key SHA256 {keyhash[:16]}… matches a KNOWN key: {kv}. Anyone with that "
                      "(public) key repo can FORGE a valid signature — authentication is void."))
        else:
            F.append(("INFO", "signing-key",
                      f"signing key SHA256 = {keyhash} (KEYHASH TLV). Cross-ref against vendor/test-key "
                      "hashes in references/known-keys/ (add the MCUboot/wolfBoot repo test keys there)."))
    if signed and sec_cnt is None:
        F.append(("MED", "no-rollback-counter",
                  "no SEC_CNT (security-counter) TLV — no hardware anti-rollback binding; an attacker can "
                  "DOWNGRADE to an older validly-signed image with a known vulnerability."))
    if not facts["encrypted"]:
        F.append(("LOW", "plaintext-image",
                  "image is not encrypted — extractable in the clear once dumped (confidentiality relies "
                  "on read-out protection, not the image)."))
    return ("MCUboot", facts, F)


def analyze_wolfboot(d):
    if u32le(d, 0) != WOLFBOOT_MAGIC:
        return None
    img_size = u32le(d, 4)
    # TLV tags start at offset 8: (tag u16, len u16, value...)
    tags = {}
    o = 8
    while o + 4 <= min(len(d), 4096):
        tag = u16le(d, o); ln = u16le(d, o + 2) or 0
        if tag in (0, 0xFFFF):
            break
        tags[tag] = ln
        o += 4 + ln
    signed = WOLFBOOT_TAG_SIGNATURE in tags
    facts = {"image_size": img_size, "signed": signed, "has_sha256": WOLFBOOT_TAG_SHA256 in tags,
             "tags": sorted(hex(t) for t in tags)}
    F = []
    if not signed:
        F.append(("HIGH", "unsigned-image",
                  "no HDR_SIGNATURE tag (0x20) — the wolfBoot image carries no signature; it is not "
                  "authenticated."))
    else:
        F.append(("INFO", "sig-verify-target",
                  "signed (HDR_SIGNATURE present). wolfBoot authenticates in a single wolfBoot_verify_*"
                  "() branch -> the deferred instruction-skip fault-injection target (TCHES 2025)."))
    return ("wolfBoot", facts, F)


def analyze_fit(d):
    # FIT is a DTB (BE magic). A SIGNED FIT carries 'signature' nodes + 'fit,...' / 'algo' props.
    if len(d) < 4 or struct.unpack_from(">I", d, 0)[0] != FDT_MAGIC:
        return None
    signed = _find(d, b"signature") >= 0 and (_find(d, b"algo") >= 0 or _find(d, b"fit,") >= 0)
    facts = {"signed": signed,
             "has_config_sig": _find(d, b"conf-") >= 0 or _find(d, b"configurations") >= 0}
    F = []
    if not signed:
        F.append(("HIGH", "unsigned-fit",
                  "U-Boot FIT with no signature node — U-Boot with CONFIG_FIT_SIGNATURE will reject it, but "
                  "an image built without it is unauthenticated (and a non-verifying U-Boot boots anything)."))
    else:
        F.append(("INFO", "sig-verify-target",
                  "signed FIT (signature node present). U-Boot verifies in fit_config_verify() / "
                  "fit_image_verify() -> the deferred instruction-skip fault-injection target."))
    return ("U-Boot FIT", facts, F)


def analyze_android(d):
    if d[:8] != b"ANDROID!":
        return None
    # header v0-v2: page_size @36; the real auth is external (AVB/vbmeta). Just flag it.
    return ("Android boot", {"note": "auth is external (AVB/vbmeta) — analyze the vbmeta partition"},
            [("INFO", "external-auth",
              "Android boot image; authentication is AVB/vbmeta (separate partition). Dump + analyze "
              "vbmeta to see whether verified boot is enforced and whether it is in a permissive state.")])


def detect_defer(d):
    """Formats we already have a dedicated tool for, or that carry no secure-boot structure."""
    if d[:4] == b"XLNX" or u32le(d, 0) == 0xAA995566 or _find(d, b"XLNX", 0) in (0, 4):
        return ("Xilinx bootgen", "use tools/parse-bootimage.py (ZynqMP boot-header -> IHT -> PHT + rules)")
    if d[:4] == b"\x7fELF":
        return ("ELF", "raw executable — no boot container; load into Ghidra / dump-triage.py")
    return None


ANALYZERS = [analyze_mcuboot, analyze_wolfboot, analyze_fit, analyze_android]


def analyze(d):
    for fn in ANALYZERS:
        try:
            r = fn(d)
        except Exception:
            r = None
        if r:
            return r
    dfr = detect_defer(d)
    if dfr:
        return (dfr[0], {"defer": dfr[1]}, [("INFO", "defer", dfr[1])])
    return (None, {}, [("INFO", "unknown",
                        "no recognized secure-boot container magic (MCUboot/wolfBoot/FIT/Android/Xilinx). "
                        "Run tools/dump-triage.py to identify the blob first.")])


def hash_pubkey(path):
    """SHA256 of a public key, matching how MCUboot computes KEYHASH (over the DER-encoded key). Accepts
    a raw DER (binary) or a PEM (-----BEGIN ...-----) file. Returns the hex digest."""
    raw = open(path, "rb").read()
    if b"-----BEGIN" in raw:
        body = b"".join(ln for ln in raw.splitlines() if b"-----" not in ln)
        try:
            raw = base64.b64decode(body)
        except Exception:
            pass
    return hashlib.sha256(raw).hexdigest()


def main():
    ap = argparse.ArgumentParser(description="Generic secure-boot image analyzer (static, offline).")
    ap.add_argument("image", nargs="?")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--hash-key", metavar="KEYFILE",
                    help="print SHA256 of a DER/PEM public key (the value to add to references/known-keys/)")
    a = ap.parse_args()
    if a.hash_key:
        try:
            h = hash_pubkey(a.hash_key)
        except OSError as e:
            sys.exit(f"error: cannot read {a.hash_key}: {e.strerror}")
        print(f'"{h}": "<describe this key — e.g. vendor default / repo test key>"')
        print(f"# add the line above to a references/known-keys/*.json for {a.hash_key}", file=sys.stderr)
        return 0
    if not a.image:
        ap.error("supply an image (or --hash-key KEYFILE)")
    try:
        d = open(a.image, "rb").read()
    except OSError as e:
        sys.exit(f"error: cannot read {a.image}: {e.strerror}")
    fmt, facts, findings = analyze(d)
    if a.json:
        print(json.dumps({"format": fmt, "facts": facts,
                          "findings": [{"sev": s, "id": i, "text": t} for s, i, t in findings]}, indent=2))
        return 0
    print(f"# secure-boot analysis — {a.image}")
    print(f"format: {fmt or 'UNRECOGNIZED'}")
    for k, v in facts.items():
        print(f"  {k}: {v}")
    print("\nfindings (static — the auth structure + where an attacker would target it):")
    for sev, fid, text in findings:
        print(f"  [{sev:4}] {fid}\n         {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
