#!/usr/bin/env python3
"""
extract-plan.py — the per-board EXTRACTION plan: every real way to get memory/flash off the board,
best-first, including the vendor BootROM loaders (i.MX SDP, SAM-BA, TI RBL, esptool, RP2040 BOOTROM)
that extract WITHOUT the debug port. Complements the capability matrix's mem-AP routing.

    tools/extract-plan.py --soc imx6              # the ordered extraction avenues
    tools/extract-plan.py --soc esp32 --json
    tools/extract-plan.py --list

Offline; it plans. The operator runs the extraction (hands-on model). Glitch/side-channel stay in the
unlock engine and are deferred.
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.extraction import extraction_plan, render_md  # noqa: E402

PROFILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "profiles")


def jsonc(p):
    return json.loads("".join(l for l in open(p, encoding="utf-8")
                              if not l.lstrip().startswith(("//", "#"))))


def find_profile(soc):
    for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
        if not os.path.basename(p).startswith("_"):
            try:
                d = jsonc(p)
            except Exception:
                continue
            if d.get("soc") == soc:
                return d
    return None


def main():
    ap = argparse.ArgumentParser(description="Per-board extraction plan (mem-AP + ROM loaders + flash-off).")
    ap.add_argument("--soc")
    ap.add_argument("--jtag-open", action="store_true", help="debug is open (ranks the mem-AP dump first)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
            if os.path.basename(p).startswith("_"):
                continue
            try:
                d = jsonc(p)
            except Exception:
                continue
            n = len(extraction_plan(d.get("soc", ""), {}, d))
            print(f"  {d.get('soc', '?'):16s} {n} method(s)")
        return 0
    if not a.soc:
        ap.error("supply --soc <slug> (or --list)")
    P = {"jtag_open": True} if a.jtag_open else {}
    plan = extraction_plan(a.soc, P, find_profile(a.soc))
    if a.json:
        print(json.dumps(plan, indent=2))
    else:
        print(render_md(a.soc, plan))
    return 0


if __name__ == "__main__":
    sys.exit(main())
