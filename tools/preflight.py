#!/usr/bin/env python3
"""
preflight.py — the ENGAGEMENT BLOCKER CHECK. Run it BEFORE you touch the board: it looks at what you
actually have (plugged adapters, installed backend/vendor software) against what the target needs, and
gives a GO / BLOCKED verdict with the exact fix — so the "wrong adapter completely blocked me" surprise
happens in triage, not mid-engagement.

    tools/preflight.py --soc zynqmp                 # check against a known target
    tools/preflight.py --soc smartfusion2 --lsusb "$(lsusb)"
    tools/preflight.py --soc esp32 --detect         # auto-detect adapters here

Checks: (1) an adapter is plugged (USB passthrough!), (2) it's a known path for this SoC, (3) the
backend software the adapter needs is installed, (4) the transport matches, (5) the vendor ROM-loader
tools for the alternate extraction path. Offline, read-only.
"""
import argparse
import glob
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.transport import detect_adapters, match_profile  # noqa: E402
try:
    from jtagx.extraction import ROM_LOADER
except Exception:
    ROM_LOADER = {}

PROFILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "profiles")

# backend → the software that must be on PATH to drive it (any one satisfies it)
BACKEND_TOOLS = {
    "openocd": ["openocd"],
    "hw_server": ["xsdb", "hw_server"],           # AMD/Xilinx Vitis/Vivado
    "libero": ["FPExpress", "fpexpress", "libero", "FlashProExpress"],   # Microchip/Microsemi
}
BACKEND_FIX = {
    "hw_server": "install AMD Vivado/Vitis (provides xsdb + hw_server), or bridge the adapter to OpenOCD "
                 "via XVC (Chain ▸ XVC)",
    "libero": "install Microchip Libero SoC / FlashPro Express, or use the OpenOCD SVF/boundary-scan path "
              "for an unprovisioned part",
    "openocd": "install openocd (apt install openocd), or use the bundled engagement kit on an air-gapped box",
}
# soc → vendor ROM-loader extraction tool(s) that make the no-debug avenue usable (informational)
LOADER_TOOLS = {
    "imx6": ["imx_usb", "uuu"], "sama5": ["sam-ba", "bossac"], "esp32": ["esptool.py", "esptool"],
    "rp2040": ["picotool"], "am335x": [], "bcm": [],
}

GO, BLOCK, WARN, INFO = "GO", "BLOCKED", "WARN", "info"


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


def _have(tools):
    return next((t for t in tools if shutil.which(t)), None)


def preflight(prof, present):
    """Return (verdict, [checks]) where each check is (status, title, detail)."""
    soc = prof.get("soc", "?")
    adapters = prof.get("adapters", [])
    checks = []
    m = match_profile(adapters, present) if present else {"usable": [], "present_unlisted": present or [],
                                                          "listed_absent": adapters}

    # 1. an adapter is plugged at all
    if not present:
        checks.append((BLOCK, "adapter plugged",
                       "no USB JTAG/SWD adapter detected. If you're in a VM, PASS THE DEVICE THROUGH "
                       "(VMware: VM ▸ Removable Devices ▸ your FTDI/J-Link). Then re-run."))
        return BLOCK, checks
    checks.append((GO, "adapter plugged", f"{len(present)} detected: " +
                   ", ".join(a["name"] for a in present)))

    # 2. at least one plugged adapter is a known path for THIS SoC
    usable = m["usable"]
    if not usable:
        want = ", ".join(sorted({t for a in adapters for t in a.get("transports", [])})) or "?"
        names = ", ".join(a.get("name", a.get("id", "?")) for a in adapters)
        checks.append((BLOCK, "adapter matches target",
                       f"none of your adapters are a known path for {soc}. It expects one of: {names} "
                       f"(transports: {want}). A generic FTDI may work — verify the cfg/pinout."))
        return BLOCK, checks
    checks.append((GO, "adapter matches target",
                   "usable: " + ", ".join(f"{a['name']} → {a['backend']}" for a in usable)))

    # 3. the backend software for a usable adapter is installed (any usable path counts)
    go_paths, missing = [], []
    for a in usable:
        be = a.get("backend", "openocd")
        tool = _have(BACKEND_TOOLS.get(be, [be]))
        if tool:
            go_paths.append((a, be, tool))
        else:
            missing.append((a, be))
    if go_paths:
        a, be, tool = go_paths[0]
        checks.append((GO, "backend software", f"{be} present ({tool}) for {a['name']}"))
    else:
        a, be = missing[0]
        checks.append((BLOCK, "backend software",
                       f"{a['name']} needs the '{be}' backend, and none of {BACKEND_TOOLS.get(be, [be])} "
                       f"is on PATH. Fix: {BACKEND_FIX.get(be, 'install the vendor software')}."))
        return BLOCK, checks

    # 4. transport sanity — pull the transports from the PROFILE adapter (detected dicts don't carry them),
    # matching the usable adapter back to its allowlist entry by id/usb_id.
    def _prof_transports(ua):
        for pa in adapters:
            if pa.get("id") == ua.get("id") or ua.get("usb_id", "").lower() in \
                    [u.lower() for u in pa.get("usb_ids", [])]:
                return pa.get("transports", [])
        return []
    tset = sorted({t for a, _, _ in go_paths for t in _prof_transports(a)})
    checks.append((INFO, "transport", f"available: {', '.join(tset) or 'jtag/swd (per cfg)'}"))

    # 5. vendor ROM-loader extraction tool (the no-debug avenue) — informational, not a blocker
    if soc in ROM_LOADER:
        tools = LOADER_TOOLS.get(soc, [])
        have = _have(tools) if tools else None
        loader = ROM_LOADER[soc][0]
        if tools and not have:
            checks.append((WARN, "ROM-loader extraction",
                           f"the no-debug avenue ({loader}) needs {tools} — not on PATH. Install it if the "
                           "debug port turns out to be locked."))
        else:
            checks.append((INFO, "ROM-loader extraction",
                           f"{loader} available" + (f" ({have})" if have else "") + " as a no-debug fallback."))

    return GO, checks


def main():
    ap = argparse.ArgumentParser(description="Engagement pre-flight: can you actually reach this board?")
    ap.add_argument("--soc", required=True)
    ap.add_argument("--lsusb", help="paste `lsusb` output (else --detect or offline)")
    ap.add_argument("--detect", action="store_true", help="auto-detect plugged adapters here")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    prof = find_profile(a.soc)
    if prof is None:
        sys.exit(f"error: no profile with soc={a.soc!r}")
    present = detect_adapters(a.lsusb) if a.lsusb is not None else (detect_adapters() if a.detect else [])
    verdict, checks = preflight(prof, present)
    if a.json:
        print(json.dumps({"soc": a.soc, "verdict": verdict,
                          "checks": [{"status": s, "check": t, "detail": d} for s, t, d in checks]}, indent=2))
        return 0 if verdict == GO else 1
    icon = {"GO": "✓", "BLOCKED": "✗", "WARN": "⚠", "info": "·"}
    print(f"# pre-flight — {a.soc}\n")
    for s, t, d in checks:
        print(f"  [{icon.get(s, '?')}] {t}: {d}")
    print(f"\nVERDICT: {'✓ GO' if verdict == GO else '✗ BLOCKED — fix the ✗ above before you start'}")
    return 0 if verdict == GO else 1


if __name__ == "__main__":
    sys.exit(main())
