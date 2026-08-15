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
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.transport import detect_adapters  # noqa: E402
from jtagx.preflight import preflight, GO   # noqa: E402  (shared core)

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
