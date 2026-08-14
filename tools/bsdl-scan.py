#!/usr/bin/env python3
"""
bsdl-scan.py — CLI for the BSDL parser + boundary-scan planner/decoder. Thin wrapper: the parser core
now lives in **jtagx.bsdl** (shared with the GUI / other consumers).

The last non-hardware unlock avenue: when the debug DAP is gated (Phase-2b, eFuse-sealed case),
IEEE-1149.1 boundary scan is often still alive. With the part's BSDL you can SAMPLE the pin states
(read straps/bus/mode pins) and EXTEST to drive pins — pin-level visibility without the debug port.

Usage:
    python3 tools/bsdl-scan.py part.bsdl                       # summary
    python3 tools/bsdl-scan.py part.bsdl --sample-plan         # emit the SAMPLE capture sequence
    python3 tools/bsdl-scan.py part.bsdl --decode 0x2a         # decode a captured boundary register
    python3 tools/bsdl-scan.py part.bsdl --pin RESETN          # which boundary bit(s) a pin uses
Offline; it plans + decodes. The operator runs the JTAG (OpenOCD/UrJTAG) per the hands-on rule.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))   # repo root — for jtagx
from jtagx.bsdl import parse_bsdl, summary, sample_plan, decode, pin_lookup


def main():
    ap = argparse.ArgumentParser(description="Parse a BSDL + plan/decode boundary scan (Phase-2b alt-path).")
    ap.add_argument("bsdl")
    ap.add_argument("--sample-plan", action="store_true", help="emit the SAMPLE capture JTAG sequence")
    ap.add_argument("--decode", metavar="HEX", help="decode a captured boundary-register value into pin states")
    ap.add_argument("--pin", metavar="NAME", help="show which boundary bit(s) a named pin uses")
    ap.add_argument("--tap", default="tap0", help="TAP name for the emitted plan (default tap0)")
    a = ap.parse_args()
    try:
        d = parse_bsdl(open(a.bsdl, encoding="utf-8", errors="replace").read())
    except Exception as e:
        sys.exit(f"error: cannot parse {a.bsdl}: {e}")

    if a.decode:
        print(decode(d, int(a.decode, 0)))
    elif a.sample_plan:
        print(sample_plan(d, a.tap))
    elif a.pin:
        print(pin_lookup(d, a.pin))
    else:
        print(summary(d))


if __name__ == "__main__":
    main()
