#!/usr/bin/env python3
"""
hexdump-attributes.py — annotated register hexdump from an enumeration capture.

Turns a raw enumeration capture (reports/raw-<ts>.json, or the frozen golden) into
an annotated hexdump: grouped by block, sorted by address, each captured register
shown as its little-endian bytes + 32-bit word + the decoded attribute fields. The
point is to see the raw values AND exactly where in the dump each attribute resides.

This is generated from a real capture — no hand-typed values. Re-run it after a
fresh capture to refresh; the security registers added to enumerate.tcl §4 appear
once the capture includes them.

Usage:
  tools/hexdump-attributes.py [capture.json]      # default: latest reports/raw-*.json, else golden
  tools/hexdump-attributes.py --security          # only security-relevant blocks
  tools/hexdump-attributes.py -o out.md           # write markdown to a file
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

# Blocks whose registers carry a security control (flagged ★ / "matters").
SECURITY_BLOCKS = {
    "CSU", "EFUSE", "XPPU",
    "DDR_XMPU0", "DDR_XMPU1", "DDR_XMPU2", "DDR_XMPU3", "DDR_XMPU4", "DDR_XMPU5",
    "FPD_XMPU", "OCM_XMPU",
    "IOU_SECURE_SLCR", "LPD_SLCR_SECURE",
}
# Individual registers worth calling out as "the ones that matter most".
KEY_REGISTERS = {
    "JTAG_SEC", "JTAG_DAP_CFG", "SEC_CTRL", "AES_STATUS", "EFUSE_AES_CRC",
    "TAMPER_STATUS", "WR_LOCK", "PUF_CHASH",
}


def _find_default_capture() -> str:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    raws = sorted(glob.glob(os.path.join(here, "reports", "raw-*.json")),
                  key=os.path.getmtime, reverse=True)
    if raws:
        return raws[0]
    return os.path.join(here, "tests", "golden", "zcu102-jtag-idle", "raw.json")


def _le_bytes(v: int) -> str:
    """Little-endian byte view of a 32-bit word, as a chip dump shows it."""
    return " ".join(f"{(v >> (8 * i)) & 0xFF:02X}" for i in range(4))


def _fields_str(reg: dict, limit: int = 8) -> str:
    out = []
    for name, fd in reg.get("fields", {}).items():
        out.append(f"{name}={fd.get('value')}")
    s = " ".join(out[:limit])
    if len(out) > limit:
        s += " …"
    return s


def render(capture: dict, security_only: bool = False, src_path: str = "") -> str:
    regs = capture.get("registers", {})
    meta = capture.get("metadata", {})
    lines = []
    lines.append("Annotated register hexdump — where each enumerated attribute resides.")
    lines.append("")
    lines.append(f"Source capture: {src_path or meta.get('raw_path', '(unknown)')}  ·  "
                 f"timestamp {meta.get('timestamp', '?')}  ·  {len(regs)} registers")
    lines.append("Bytes are little-endian (as a memory dump shows them). "
                 "★ = security control. Fields are decoded attribute=value.")
    lines.append("")

    # group by block, base-address sorted
    by_block: dict[str, list] = {}
    for addr, reg in regs.items():
        a = int(reg.get("address", addr), 16)
        by_block.setdefault(reg.get("block", "?"), []).append((a, reg))

    def block_base(items):
        return min(a for a, _ in items)

    for block in sorted(by_block, key=lambda b: block_base(by_block[b])):
        if security_only and block not in SECURITY_BLOCKS:
            continue
        items = sorted(by_block[block])
        sec = "★ " if block in SECURITY_BLOCKS else ""
        lines.append(f"### {sec}{block}  (base 0x{block_base(items):08X})")
        lines.append("")
        lines.append("```")
        lines.append("address     +0 +1 +2 +3   word         register            attribute fields")
        for a, reg in items:
            try:
                v = int(reg.get("value_int", int(str(reg.get("value", "0")), 16)))
            except (ValueError, TypeError):
                v = 0
            star = "★" if (reg.get("name") in KEY_REGISTERS or block in SECURITY_BLOCKS) else " "
            lines.append(
                f"0x{a:08X}  {_le_bytes(v)}   0x{v & 0xFFFFFFFF:08X}  {star} "
                f"{reg.get('name',''):<18} {_fields_str(reg)}".rstrip()
            )
        lines.append("```")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("capture", nargs="?", default=None, help="raw capture JSON")
    ap.add_argument("--security", action="store_true", help="only security-relevant blocks")
    ap.add_argument("-o", "--out", default=None, help="write markdown to this file")
    args = ap.parse_args()

    path = args.capture or _find_default_capture()
    if not os.path.exists(path):
        print(f"capture not found: {path}", file=sys.stderr)
        return 2
    try:
        with open(path) as f:
            capture = json.load(f)
    except json.JSONDecodeError as e:
        print(f"{path} is not valid JSON: {e}", file=sys.stderr)
        return 2

    md = render(capture, security_only=args.security, src_path=path)
    if args.out:
        with open(args.out, "w") as f:
            f.write(md + "\n")
        print(f"wrote {args.out}")
    else:
        print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
