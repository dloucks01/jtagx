#!/usr/bin/env python3
"""
attack-graph.py — the kill-chain planner CLI. Given a board + posture, print the ordered, prerequisite-
aware attack path (jtag-up → debug-open → mem-read → secrets → persistence, plus the secure-boot branch),
each node's state, and the exact next command. Honest: BLOCKED where the only way on is a physical rig.

    tools/attack-graph.py --soc zynqmp --jtag-open
    tools/attack-graph.py --soc nrf52 --approtect-locked        # locked → the lever is the next move
    tools/attack-graph.py --soc igloo2 --flashlock              # fabric → mem BLOCKED, readback branch
    tools/attack-graph.py --from-capture reports/raw-*.json     # derive posture from a live capture

Offline; reasons over the chip + posture (not a live scanner). Reuses the same posture flags as
unlock-engine.py / cve-match.py.
"""
import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # repo root (jtagx)
sys.path.insert(0, HERE)                     # tools/ (interpret_lib)
from jtagx.attackgraph import plan, render_md  # noqa: E402
try:
    from jtagx.posture import derive_flags
    from interpret_lib import Capture
except Exception:
    derive_flags = Capture = None

PROFILES = os.path.join(os.path.dirname(HERE), "profiles")


def load_jsonc(path):
    return json.loads("".join(l for l in open(path, encoding="utf-8")
                              if not l.lstrip().startswith(("//", "#"))))


def find_profile(soc):
    for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
        if os.path.basename(p).startswith("_"):
            continue
        try:
            d = load_jsonc(p)
        except Exception:
            continue
        if d.get("soc") == soc:
            return d
    return None


def main():
    ap = argparse.ArgumentParser(description="Kill-chain planner: ordered attack path for a board+posture.")
    ap.add_argument("--soc", help="profile slug (zynqmp, nrf52, igloo2, ...)")
    ap.add_argument("--from-capture", metavar="RAW_JSON",
                    help="derive posture from an enumeration capture (reports/raw-*.json) — states are "
                         "then CONFIRMED, not asserted (ZynqMP)")
    ap.add_argument("--jtag-open", action="store_true")
    ap.add_argument("--jtag-locked", action="store_true")
    ap.add_argument("--no-chain", action="store_true", help="no TAP responded")
    ap.add_argument("--secure-boot", choices=["on", "off", "encrypt-only"])
    ap.add_argument("--aes-encrypt", action="store_true")
    ap.add_argument("--efuse-jtag-dis", action="store_true", help="JTAG-disable eFuse blown (seals the lever)")
    ap.add_argument("--approtect-locked", action="store_true")
    ap.add_argument("--rdp", type=int)
    ap.add_argument("--flash-secured", action="store_true")
    ap.add_argument("--debug-protected", action="store_true")
    ap.add_argument("--flashlock", action="store_true")
    ap.add_argument("--debug-locked", action="store_true")
    ap.add_argument("--dumped", action="store_true", help="a dump already exists (mem-read ACHIEVED)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    P, source = {}, "asserted"
    if args.from_capture:
        if Capture is None or derive_flags is None:
            sys.exit("error: capture derivation unavailable (run from the repo so tools/ is importable)")
        try:
            raw = json.load(open(args.from_capture))
        except (OSError, json.JSONDecodeError) as e:
            sys.exit(f"error: cannot read capture {args.from_capture}: {e}")
        P.update(derive_flags(Capture(raw)))
        source = "capture"
        if not args.soc:
            args.soc = "zynqmp"     # capture derivation is ZynqMP-specific
    if not args.soc:
        ap.error("supply --soc <slug> (or --from-capture)")
    if args.jtag_open: P["jtag_open"] = True
    if args.jtag_locked: P["jtag_open"] = False; P["jtag_locked"] = True
    if args.no_chain: P["no_chain"] = True
    if args.efuse_jtag_dis: P["efuse_jtag_dis"] = True
    if args.secure_boot == "on": P["secure_boot"] = True
    elif args.secure_boot == "off": P["secure_boot"] = False
    elif args.secure_boot == "encrypt-only": P["secure_boot"] = "encrypt-only"
    if args.aes_encrypt: P["aes_encrypt"] = True
    if args.approtect_locked: P["approtect_locked"] = True
    if args.rdp is not None: P["rdp_level"] = args.rdp
    if args.flash_secured: P["flash_secured"] = True
    if args.debug_protected: P["debug_protected"] = True
    if args.flashlock: P["flashlock"] = True
    if args.debug_locked: P["debug_locked"] = True
    if args.dumped: P["dumped"] = True

    g = plan(args.soc, P, find_profile(args.soc), source)
    if args.json:
        print(json.dumps(g, indent=2))
    else:
        print(render_md(g))
    return 0


if __name__ == "__main__":
    sys.exit(main())
