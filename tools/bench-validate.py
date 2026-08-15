#!/usr/bin/env python3
"""
bench-validate.py — the per-board BENCH-VALIDATION protocol. Generates the ordered checklist that turns
"bench-ready (predicted by the mock)" into confirmable hardware steps, and grades the operator's real
outputs against the mock's prediction. All PASS ⇒ the board graduates bench-ready → bench-VALIDATED.

    tools/bench-validate.py --soc kinetis                 # print the checklist to run on the board
    tools/bench-validate.py --soc kinetis --ingest r.json # grade captured outputs {check_id: output}
    tools/bench-validate.py --list                        # boards with a modeled protocol

Offline; it generates + grades. The operator runs the JTAG steps (hands-on model).
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.benchvalidate import spec, render_md, verdict  # noqa: E402

PROFILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "profiles")


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
    ap = argparse.ArgumentParser(description="Generate + grade a per-board bench-validation protocol.")
    ap.add_argument("--soc")
    ap.add_argument("--ingest", metavar="JSON", help='{"check_id": "captured output", ...} to grade')
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if a.list:
        for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
            if os.path.basename(p).startswith("_"):
                continue
            try:
                d = load_jsonc(p)
            except Exception:
                continue
            n = len(spec(d.get("soc", ""), d))
            print(f"  {d.get('soc', '?'):16s} {n} checks   {d.get('name', '')[:44]}")
        return 0

    if not a.soc:
        ap.error("supply --soc <slug> (or --list)")
    checks = spec(a.soc, find_profile(a.soc))
    try:
        results = json.load(open(a.ingest)) if a.ingest else None
    except (OSError, json.JSONDecodeError) as e:
        sys.exit(f"error: cannot read --ingest {a.ingest}: {e}")
    if a.json:
        out = {"soc": a.soc, "checks": checks}
        if results is not None:
            out["verdict"] = verdict(checks, results)
        print(json.dumps(out, indent=2))
    else:
        print(render_md(a.soc, checks, results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
