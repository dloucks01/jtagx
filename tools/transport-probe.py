#!/usr/bin/env python3
"""
transport-probe.py — thin CLI over jtagx.transport.

"Which adapter is plugged in, which backend drives it for THIS board, and what's the exact
command for each JTAG primitive?" — the answer that would have unblocked the SmartLynq2/FlashPro4
engagement. Detects adapters by USB VID:PID, intersects with a board profile's adapter allowlist,
and prints the runnable scan/read/halt/run commands for the selected (or forced) backend.

Examples:
    tools/transport-probe.py --list-adapters                 # what's plugged in
    tools/transport-probe.py --profile zynqmp                # auto-pick backend + show commands
    tools/transport-probe.py --profile zynqmp --backend hw_server   # force the SmartLynq2 path
    tools/transport-probe.py --profile zynqmp --lsusb-file fixture   # offline (CI/tests)
"""
import argparse, importlib.util, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from jtagx.transport import (detect_adapters, match_profile, for_profile, make_transport,
                             BACKENDS)


def _load_jsonc(path):
    spec = importlib.util.spec_from_file_location("br", os.path.join(ROOT, "tools", "board-runner.py"))
    br = importlib.util.module_from_spec(spec); spec.loader.exec_module(br)
    return br.load_jsonc(path)


def _profile_path(name):
    if os.path.isfile(name):
        return name
    p = os.path.join(ROOT, "profiles", name if name.endswith(".json") else name + ".json")
    if not os.path.isfile(p):
        sys.exit(f"no such profile: {name} ({p})")
    return p


def main():
    ap = argparse.ArgumentParser(description="jtagx transport probe — adapter detect + per-backend command plan")
    ap.add_argument("--profile", help="board profile name or path (e.g. zynqmp)")
    ap.add_argument("--backend", choices=sorted(BACKENDS), help="force a backend instead of auto-select")
    ap.add_argument("--list-adapters", action="store_true", help="just list detected JTAG adapters")
    ap.add_argument("--lsusb-file", help="read lsusb output from a file instead of running lsusb (offline)")
    ap.add_argument("--read", metavar="ADDR:SIZE:OUT", default="0x100000:0x1000:dumps/probe.bin",
                    help="mem-read example to render (default 0x100000:0x1000:dumps/probe.bin)")
    ap.add_argument("--targets", action="store_true",
                    help="(hw_server) print the xsdb debug-target tree (reference, or --targets-file live)")
    ap.add_argument("--targets-file", help="parse a live `xsdb targets` output file instead of the reference tree")
    ap.add_argument("--target", help="(hw_server) bind commands to a debug target: role (a53-0/rpu/pmu), id, or filter")
    args = ap.parse_args()

    lsusb_text = None
    if args.lsusb_file:
        with open(args.lsusb_file) as f:
            lsusb_text = f.read()
    present = detect_adapters(lsusb_text)

    print("Detected JTAG adapters:")
    if not present:
        print("  (none recognized)")
    for c in present:
        vend = " [vendor-sw]" if c["vendor_sw"] else ""
        print(f"  {c['usb_id']}  {c['name']}  → backend={c['backend']}{vend}")
    if args.list_adapters or not args.profile:
        return

    prof = _load_jsonc(_profile_path(args.profile))
    adapters = prof.get("adapters") or []
    if present:
        m = match_profile(adapters, present)
        if m["usable"]:
            print("\nUsable for this board (allowlisted AND present):")
            for c in m["usable"]:
                print(f"  {c['usb_id']}  {c['name']}  (matched by {c['matched_by']})")
        if m["present_unlisted"]:
            print("\nPresent but NOT on this board's allowlist:")
            for c in m["present_unlisted"]:
                print(f"  {c['usb_id']}  {c['name']}")

    t = for_profile(prof, present if present else None, prefer=args.backend)

    # (hw_server) debug-target tree + optional core binding
    if getattr(t, "target_tree", None):
        if args.targets or args.target or args.targets_file:
            live = None
            if args.targets_file:
                with open(args.targets_file) as f:
                    live = f.read()
            roots = t.target_tree(live)
            if args.targets or args.targets_file:
                from jtagx.transport import render_targets
                print("\nxsdb debug-target tree" + (" (live)" if live else " (reference)") + ":")
                print(render_targets(roots) or "  (none)")
            if args.target:
                t = t.select(args.target)
                print(f"\nbound to target: {args.target}")

    caps = t.capabilities()
    print(f"\nSelected backend: {t.backend}"
          f"  (max tier {caps.max_tier}"
          f"{', needs vendor sw' if caps.needs_vendor_sw else ''})")
    print(f"  {caps.notes}")

    addr, size, out = args.read.split(":")
    addr, size = int(addr, 0), int(size, 0)
    print("\nCommands:")
    for name, cmd in (("scan", t.scan()),
                      ("halt", t.halt() if caps.halt else None),
                      ("mem_read", t.mem_read(addr, size, out) if caps.mem_read else None),
                      ("run", t.run() if caps.run else None)):
        if cmd is None:
            print(f"  {name:9s}: (not supported by {t.backend})")
            continue
        print(f"  {name:9s}: {cmd.as_shell()}")


if __name__ == "__main__":
    main()
