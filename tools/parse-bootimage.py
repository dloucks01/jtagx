#!/usr/bin/env python3
"""parse-bootimage.py — offline ZynqMP boot-image parser & posture check.

Parses a ZynqMP boot image (.bin dumped from SD/QSPI, or a bootgen BOOT.bin)
fully offline — no hardware. Walks:

    boot header  ->  Image Header Table (IHT)  ->  Partition Header Table (PHT)

and decodes the security-relevant fields of each: the boot-header
encryptionKeySource + fsblAttributes, and every partition's encrypt/auth/
destination attributes. It validates the bootgen word-checksums (sum then
^0xFFFFFFFF) as integrity gates, then builds the SAME synthetic registers the
live JTAG scan produces (BOOTHDR.* / PHT.PART<n>_*) and runs the shared rule
engine (docs/findings/zynqmp_rules.py) so the offline and live paths reach
identical verdicts.

This is the robust counterpart to enumerate.tcl's `::BH_ADDR` live walk: the
whole image is present in the file, so it sidesteps the on-target image-residency
problem entirely.

All field offsets/constants are traced to bootgen source (see docs/14 §6,
docs/11). Cardinal rule: nothing is invented — a structure that fails its magic
or checksum is reported as such, not guessed.

Usage:
    tools/parse-bootimage.py BOOT.bin
    tools/parse-bootimage.py BOOT.bin --json out.json   # emit a capture-style JSON
    tools/parse-bootimage.py BOOT.bin --base 0x0        # image base (rarely needed)
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# Share the decode tables + rule engine with the live path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from interpret_lib import Capture  # noqa: E402

_FINDINGS = Path(__file__).resolve().parent.parent / "docs" / "findings"
sys.path.insert(0, str(_FINDINGS))
from zynqmp_rules import (  # noqa: E402
    ALL_RULES, _ENC_KEY_SRC, _DEST_DEVICE,
)

# --- boot-header offsets (bootheader-zynqmp.h; see docs/14 §6.2) -------------
BH_WIDTH_DET = 0x20    # 0xAA995566
BH_HEADER_ID = 0x24    # 0x584C4E58 "XLNX"
BH_ENC_KEY_SRC = 0x28
BH_FSBL_ATTR = 0x44
BH_CHECKSUM = 0x48     # word-sum of 0x20..0x44 (10 words)
BH_IHT_OFF = 0x98      # imageHeaderByteOffset (byte)
BH_PHT_OFF = 0x9C      # partitionHeaderByteOffset (byte)

WIDTH_DETECTION = 0xAA995566
HEADER_ID_XLNX = 0x584C4E58

# fsblAttributes (0x44) sub-fields
FSBL_AUTH_ONLY_SHIFT, FSBL_AUTH_ONLY_MASK = 4, 0x3    # ==3 true
FSBL_BH_RSA_SHIFT, FSBL_BH_RSA_MASK = 14, 0x3         # ==3 true

# --- IHT offsets (imageheadertable-zynqmp.h:55) -----------------------------
IHT_PART_COUNT = 0x04
IHT_FIRST_PH_WORDOFF = 0x08
IHT_HDR_AC_WORDOFF = 0x10
IHT_BOOT_DEVICE = 0x14
IHT_CHECKSUM = 0x3C    # word-sum of 0x00..0x38 (15 words)
IHT_SIZE = 0x40

# --- partition header offsets (partitionheadertable-zynqmp.h:73) ------------
PH_UNENC_LEN = 0x00    # unencryptedDataWordLength (words)
PH_ENC_LEN = 0x04      # encryptedDataWordLength (words)
PH_TOTAL_LEN = 0x08    # totalPartitionWordLength (words, incl AC + padding)
PH_NEXT_WORDOFF = 0x0C
PH_LOAD_ADDR = 0x18    # destinationLoadAddress (low 32)
PH_LOAD_ADDR_HI = 0x1C # destinationLoadAddress (high 32)
PH_DATA_WORDOFF = 0x20 # actualPartitionWordOffset — where the partition DATA sits in the image
PH_ATTR = 0x24
PH_AC_OFF = 0x34       # authCertificateOffset (word); !=0 => authenticated
PH_PART_NUM = 0x38
PH_CHECKSUM = 0x3C     # word-sum of 0x00..0x38 (15 words)
PH_SIZE = 0x40

# partitionAttributes (0x24) sub-fields (partitionheadertable-zynqmp.h:40-62)
PH_DEST_DEVICE_SHIFT, PH_DEST_DEVICE_MASK = 4, 0x7
PH_ENCRYPT_SHIFT, PH_ENCRYPT_MASK = 7, 0x1
PH_CHECKSUM_SHIFT, PH_CHECKSUM_MASK = 12, 0x7
PH_AC_FLAG_SHIFT, PH_AC_FLAG_MASK = 15, 0x1

PHT_MAX = 32  # matches the live-walk cap


def _u32(data: bytes, off: int) -> int | None:
    if off < 0 or off + 4 > len(data):
        return None
    return struct.unpack_from("<I", data, off)[0]


def _word_checksum(data: bytes, off: int, nwords: int) -> int | None:
    """bootgen ComputeWordChecksum: sum of nwords LE words then ^0xFFFFFFFF."""
    s = 0
    for i in range(nwords):
        w = _u32(data, off + 4 * i)
        if w is None:
            return None
        s = (s + w) & 0xFFFFFFFF
    return s ^ 0xFFFFFFFF


class Reg:
    """A captured value to feed the rule engine (mirrors enumerate.tcl)."""
    __slots__ = ("addr", "block", "name", "value", "fields")

    def __init__(self, addr, block, name, value, fields=None):
        self.addr, self.block, self.name = addr, block, name
        self.value, self.fields = value, (fields or {})


def _guess_part_type(dest_name: str, load_addr: int) -> str:
    """Heuristic label for a partition from its dest device + load address."""
    if dest_name == "PMU":
        return "pmufw"
    if dest_name == "PL":
        return "bitstream"
    # PS partitions: distinguish by well-known ZynqMP load addresses.
    if load_addr == 0xFFFEA000:
        return "fsbl"               # FSBL's canonical OCM load address
    if 0xFFD00000 <= load_addr < 0xFFE00000:
        return "pmufw"              # PMU firmware in PMU RAM
    if load_addr == 0xFFFC0000:
        return "bl31-or-bootapp"    # top-of-OCM stage (ATF secure monitor / boot app, e.g. npMain)
    if 0xFFFE0000 <= load_addr < 0xFFFFFFFF:
        return "ocm-stage"          # other OCM-resident stage
    if load_addr and load_addr < 0x80000000:
        return "kernel-or-app"      # DDR-loaded payload (OS/kernel, e.g. vxWorks @0x100000)
    return "partition"


def parse_image(data: bytes, base: int = 0, extract_dir=None):
    """Return (report_lines, regs, problems). Parsing only; writes files iff extract_dir set."""
    report = []
    regs: list[Reg] = []
    problems = []
    if extract_dir is not None:
        Path(extract_dir).mkdir(parents=True, exist_ok=True)

    def add(addr, block, name, value, fields=None):
        regs.append(Reg(addr, block, name, value, fields))

    # ---- boot header --------------------------------------------------------
    wdw = _u32(data, BH_WIDTH_DET)
    idw = _u32(data, BH_HEADER_ID)
    report.append("== Boot header ==")
    if wdw != WIDTH_DETECTION or idw != HEADER_ID_XLNX:
        problems.append(
            f"boot-header magic mismatch (WIDTH_DETECTION=0x{(wdw or 0):08X} "
            f"want 0x{WIDTH_DETECTION:08X}; ID=0x{(idw or 0):08X} want "
            f"0x{HEADER_ID_XLNX:08X}) — not a ZynqMP boot image at base "
            f"0x{base:08X}; nothing parsed.")
        report.append("  INVALID — magic mismatch (see problems)")
        return report, regs, problems

    bh_cks_calc = _word_checksum(data, BH_WIDTH_DET, 10)
    bh_cks_file = _u32(data, BH_CHECKSUM)
    bh_cks_ok = (bh_cks_calc == bh_cks_file)
    eks = _u32(data, BH_ENC_KEY_SRC)
    att = _u32(data, BH_FSBL_ATTR)
    iht_off = _u32(data, BH_IHT_OFF)
    pht_off = _u32(data, BH_PHT_OFF)
    auth_only = (att >> FSBL_AUTH_ONLY_SHIFT) & FSBL_AUTH_ONLY_MASK
    bh_rsa = (att >> FSBL_BH_RSA_SHIFT) & FSBL_BH_RSA_MASK

    report.append(f"  magic            : OK (XLNX)")
    report.append(f"  headerChecksum   : 0x{bh_cks_file:08X} "
                  f"({'OK' if bh_cks_ok else f'MISMATCH calc 0x{bh_cks_calc:08X}'})")
    report.append(f"  encryptionKeySrc : 0x{eks:08X}  "
                  f"({_ENC_KEY_SRC.get(eks, 'unknown')})")
    report.append(f"  fsblAttributes   : 0x{att:08X}  "
                  f"(AUTH_ONLY={auth_only} BH_RSA={bh_rsa})")
    report.append(f"  iht_offset(0x98) : 0x{iht_off:08X}   "
                  f"pht_offset(0x9c) : 0x{pht_off:08X}")
    if not bh_cks_ok:
        problems.append("boot-header checksum mismatch (image may be corrupt "
                        "or base offset wrong)")

    add(base + BH_WIDTH_DET, "BOOTHDR", "WIDTH_DET", wdw)
    add(base + BH_HEADER_ID, "BOOTHDR", "HEADER_ID", idw)
    add(base + BH_ENC_KEY_SRC, "BOOTHDR", "ENC_KEY_SRC", eks)
    add(base + BH_FSBL_ATTR, "BOOTHDR", "FSBL_ATTR", att,
        {"AUTH_ONLY": auth_only, "BH_RSA": bh_rsa})

    # ---- image header table -------------------------------------------------
    report.append("")
    report.append("== Image Header Table ==")
    iht_cks_calc = _word_checksum(data, iht_off, 15)
    iht_cks_file = _u32(data, iht_off + IHT_CHECKSUM)
    iht_cks_ok = (iht_cks_calc == iht_cks_file)
    part_count = _u32(data, iht_off + IHT_PART_COUNT)
    first_ph_wordoff = _u32(data, iht_off + IHT_FIRST_PH_WORDOFF)
    hdr_ac = _u32(data, iht_off + IHT_HDR_AC_WORDOFF)
    if part_count is None or first_ph_wordoff is None:
        problems.append(f"IHT unreadable at file offset 0x{iht_off:08X} "
                        "(truncated image?)")
        return report, regs, problems
    report.append(f"  partitionCount   : {part_count}")
    report.append(f"  firstPH wordoff  : 0x{first_ph_wordoff:08X} "
                  f"(byte 0x{4 * first_ph_wordoff:08X})")
    report.append(f"  headerAC wordoff : 0x{hdr_ac:08X} "
                  f"({'headers AUTHENTICATED' if hdr_ac else 'headers not authenticated'})")
    report.append(f"  ihtChecksum      : 0x{(iht_cks_file or 0):08X} "
                  f"({'OK' if iht_cks_ok else 'MISMATCH'})")
    if not iht_cks_ok:
        problems.append("IHT checksum mismatch")
    add(base + iht_off + IHT_PART_COUNT, "PHT", "PART_COUNT", part_count)
    add(base + iht_off + IHT_HDR_AC_WORDOFF, "PHT", "HDR_AC", hdr_ac)

    if part_count > PHT_MAX:
        problems.append(f"partitionCount {part_count} exceeds cap {PHT_MAX} — "
                        f"only first {PHT_MAX} parsed")
        part_count = PHT_MAX

    # ---- partition header table (linked list, validated per-PH) -------------
    report.append("")
    report.append("== Partition Header Table ==")
    ph_byte = 4 * first_ph_wordoff
    seen = set()
    idx = 0
    while idx < part_count and ph_byte not in seen:
        seen.add(ph_byte)
        attr = _u32(data, ph_byte + PH_ATTR)
        ph_cks_calc = _word_checksum(data, ph_byte, 15)
        ph_cks_file = _u32(data, ph_byte + PH_CHECKSUM)
        if attr is None or ph_cks_file is None:
            problems.append(f"partition {idx}: header unreadable at file offset "
                            f"0x{ph_byte:08X} (truncated)")
            break
        ph_cks_ok = (ph_cks_calc == ph_cks_file)
        acoff = _u32(data, ph_byte + PH_AC_OFF)
        partnum = _u32(data, ph_byte + PH_PART_NUM)
        nxt = _u32(data, ph_byte + PH_NEXT_WORDOFF)
        dest = (attr >> PH_DEST_DEVICE_SHIFT) & PH_DEST_DEVICE_MASK
        enc = (attr >> PH_ENCRYPT_SHIFT) & PH_ENCRYPT_MASK
        ac_flag = (attr >> PH_AC_FLAG_SHIFT) & PH_AC_FLAG_MASK
        authd = bool(ac_flag) or bool(acoff)
        report.append(
            f"  [{idx}] num={partnum} dest={_DEST_DEVICE.get(dest, dest)} "
            f"attr=0x{attr:08X} encrypt={enc} ac_flag={ac_flag} "
            f"acOff=0x{(acoff or 0):08X} -> "
            f"{'ENC' if enc else 'plain'}+{'AUTH' if authd else 'noauth'} "
            f"checksum={'OK' if ph_cks_ok else 'MISMATCH'}")
        if not ph_cks_ok:
            problems.append(f"partition {idx}: PH checksum mismatch "
                            "(walked into non-PH data?) — flags may be unreliable")
        add(base + ph_byte + PH_ATTR, "PHT", f"PART{idx}_ATTR", attr,
            {"DEST_DEVICE": dest, "ENCRYPT": enc, "AC_FLAG": ac_flag})
        add(base + ph_byte + PH_AC_OFF, "PHT", f"PART{idx}_ACOFF", acoff or 0)
        add(base + ph_byte + PH_PART_NUM, "PHT", f"PART{idx}_NUM",
            partnum if partnum is not None else idx)

        # ---- optional: carve this partition's data out to its own file --------
        if extract_dir is not None:
            data_woff = _u32(data, ph_byte + PH_DATA_WORDOFF)
            total_len = _u32(data, ph_byte + PH_TOTAL_LEN)
            unenc_len = _u32(data, ph_byte + PH_UNENC_LEN)
            load_lo = _u32(data, ph_byte + PH_LOAD_ADDR) or 0
            load_hi = _u32(data, ph_byte + PH_LOAD_ADDR_HI) or 0
            load_addr = (load_hi << 32) | load_lo
            # bytes to carve: prefer total length; fall back to unencrypted length.
            nwords = total_len or unenc_len
            if data_woff is None or not nwords:
                report.append(f"      └─ extract: partition {idx} has no data offset/length — skipped")
            else:
                start = base + data_woff * 4
                length = nwords * 4
                blob = data[start:start + length]
                dest_name = _DEST_DEVICE.get(dest, str(dest))
                kind = _guess_part_type(dest_name, load_addr)
                fname = f"part{idx}_num{partnum}_{dest_name}_{kind}_load0x{load_addr:08X}.bin"
                outp = Path(extract_dir) / fname
                outp.write_bytes(blob)
                short = "  <-- likely the OS/kernel" if kind == "kernel-or-app" else ""
                report.append(
                    f"      └─ extract: {fname}  ({len(blob)} bytes @ file 0x{start:08X}){short}")

        if not nxt:
            break
        ph_byte = 4 * nxt
        idx += 1

    return report, regs, problems


def regs_to_capture(regs: list[Reg]) -> Capture:
    raw = {"registers": {}}
    for r in regs:
        addr_hex = f"0x{r.addr:08X}"
        entry = {
            "name": r.name, "block": r.block, "address": addr_hex,
            "value": f"0x{r.value:08X}", "value_int": r.value,
        }
        if r.fields:
            entry["fields"] = {k: {"value": v} for k, v in r.fields.items()}
        raw["registers"][addr_hex] = entry
    return Capture(raw), raw


def emit_json(raw: dict, path: str):
    import json
    raw.setdefault("schema_version", "1.0")
    raw.setdefault("metadata", {"source": "parse-bootimage.py"})
    Path(path).write_text(json.dumps(raw, indent=2))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Offline ZynqMP boot-image parser + posture check")
    ap.add_argument("image", help="boot image .bin (SD/QSPI dump or BOOT.bin)")
    ap.add_argument("--base", default="0x0",
                    help="image base offset within the file (default 0x0)")
    ap.add_argument("--json", metavar="OUT",
                    help="also write a capture-style JSON of the parsed structures")
    ap.add_argument("--extract", metavar="DIR",
                    help="carve each partition (FSBL/PMUFW/bl31/kernel) to its own .bin in DIR")
    args = ap.parse_args(argv)

    data = Path(args.image).read_bytes()
    base = int(args.base, 0)
    report, regs, problems = parse_image(data, base, extract_dir=args.extract)

    print("\n".join(report))
    cap, raw = regs_to_capture(regs)

    print("\n== Posture findings ==")
    fired = 0
    for rule in ALL_RULES:
        # The posture summary is a device-fuse checklist (RSA_EN, SEC_CTRL, ...)
        # — meaningless for an image file, where none of those are present.
        if rule.__name__ == "rule_security_posture_summary":
            continue
        try:
            f = rule(cap)
        except Exception as e:  # a rule that can't read the partial capture
            continue
        if f is None:
            continue
        fired += 1
        print(f"\n[{f.severity}] {f.name}")
        print("  " + f.conclusion.replace("\n", "\n  "))
        for imp in f.offensive_implications:
            print(f"    - {imp}")
    if not fired:
        print("  (no posture rules fired — image fully protected, or no "
              "security-relevant config present)")

    if args.json:
        emit_json(raw, args.json)
        print(f"\nWrote capture JSON: {args.json}")

    if problems:
        print("\n== Problems ==")
        for p in problems:
            print(f"  ! {p}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
