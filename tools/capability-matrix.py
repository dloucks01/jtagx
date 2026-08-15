#!/usr/bin/env python3
"""
capability-matrix.py — print the adapter × backend × op capability matrix + op-routing for a board.

The operator-facing view of jtagx.transport.matrix. Answers the question the failed engagement
posed (memory project_adapter_transport_gap): "with this board and the adapters I have, which
primitive runs on which adapter — and what's simply BLOCKED without a vendor tool / different probe?"

    tools/capability-matrix.py --profile zynqmp          # the board's adapter allowlist × ops grid
    tools/capability-matrix.py --profile smartfusion2    # M3 CoreSight vs FlashPro split
    tools/capability-matrix.py --profile igloo2          # fabric-only → mem ops BLOCKED (honest)
    tools/capability-matrix.py --profile zynqmp --lsusb "$(lsusb)"   # join what's plugged in
    tools/capability-matrix.py --list

Pure/offline — reads profiles/*.json + backend capabilities; emits no USB traffic.
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.transport import matrix_markdown, detect_adapters  # noqa: E402

PROFILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "profiles")


def load_jsonc(path):
    keep = [ln for ln in open(path, encoding="utf-8")
            if not ln.lstrip().startswith(("//", "#"))]
    return json.loads("".join(keep))


def find_profile(soc):
    for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
        if os.path.basename(p).startswith("_"):
            continue
        try:
            prof = load_jsonc(p)
        except Exception:
            continue
        if prof.get("soc") == soc:
            return prof
    return None


def main():
    ap = argparse.ArgumentParser(description="Adapter × backend × op capability matrix for a board.")
    ap.add_argument("--profile", help="board 'soc' slug (e.g. zynqmp, smartfusion2, igloo2, nrf52)")
    ap.add_argument("--lsusb", help="paste `lsusb` output to mark which allowlisted adapters are plugged in")
    ap.add_argument("--detect", action="store_true", help="auto-detect plugged adapters (runs lsusb here)")
    ap.add_argument("--list", action="store_true", help="list available board profiles and exit")
    args = ap.parse_args()

    if args.list:
        socs = []
        for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
            if os.path.basename(p).startswith("_"):
                continue
            try:
                prof = load_jsonc(p)
            except Exception:
                continue
            socs.append((prof.get("soc", "?"), prof.get("name", "")))
        for soc, name in sorted(socs):
            print(f"  {soc:16s} {name}")
        return 0

    if not args.profile:
        ap.error("supply --profile <soc> (or --list)")
    prof = find_profile(args.profile)
    if prof is None:
        ap.error(f"no profile with soc={args.profile!r}; try --list")

    present = None
    if args.detect:
        present = detect_adapters()
    elif args.lsusb is not None:
        present = detect_adapters(args.lsusb)

    print(matrix_markdown(prof, present))
    return 0


if __name__ == "__main__":
    sys.exit(main())
