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
import json
import struct
import sys

MCUBOOT_MAGIC = 0x96F3B83D          # MCUboot image_header.ih_magic (LE u32 @0)
MCUBOOT_TLV_INFO = 0x6907           # IMAGE_TLV_INFO_MAGIC (unprotected TLV area)
MCUBOOT_TLV_PROT = 0x6908           # protected TLV area
MCUBOOT_SIG_TLVS = {0x20: "SHA256", 0x22: "RSA2048/PKCS1.5", 0x23: "ECDSA-P256",
                    0x24: "ED25519", 0x25: "ENCEC256", 0x26: "ENCX25519", 0x10: "KEYHASH"}
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
    # TLV area follows header+image; scan for the TLV info magic and enumerate signature TLVs
    sigs = []
    tlv_off = _find(d, struct.pack("<H", MCUBOOT_TLV_INFO))
    if tlv_off < 0:
        tlv_off = _find(d, struct.pack("<H", MCUBOOT_TLV_PROT))
    if tlv_off >= 0:
        total = u16le(d, tlv_off + 2) or 0
        o = tlv_off + 4
        end = min(tlv_off + total, len(d))
        while o + 4 <= end:
            t = d[o]; ln = u16le(d, o + 2) or 0
            if t in MCUBOOT_SIG_TLVS:
                sigs.append(MCUBOOT_SIG_TLVS[t])
            o += 4 + ln
    facts["signature_tlvs"] = sigs
    signed = any(s in ("RSA2048/PKCS1.5", "ECDSA-P256", "ED25519") for s in sigs)
    facts["signed"] = signed
    F = []
    if not signed:
        F.append(("HIGH", "unsigned-image",
                  "no signature TLV (RSA/ECDSA/ED25519) found — the image is NOT authenticated; a modified "
                  "image boots. If the bootloader is configured to require a signature this may be a "
                  "truncated/unsigned build, but as-is nothing verifies it."))
    else:
        F.append(("INFO", "sig-verify-target",
                  f"signed ({', '.join(sigs)}). MCUboot verifies with a single accept/reject branch in "
                  "boot_image_validate() -> an instruction-skip fault at that call forges acceptance "
                  "(TCHES 2025). Static finding: this call is the deferred fault-injection target."))
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


def main():
    ap = argparse.ArgumentParser(description="Generic secure-boot image analyzer (static, offline).")
    ap.add_argument("image")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    d = open(a.image, "rb").read()
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
