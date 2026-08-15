#!/usr/bin/env python3
"""
first-contact.py — CLI for the first-contact troubleshooting decision tree
(jtagx.firstcontact). Turns "the adapter blocked me" into a ranked way-out.

    python3 tools/first-contact.py                       # full stage-ordered tree
    python3 tools/first-contact.py --stage adapter       # one stage
    python3 tools/first-contact.py "flashpro won't work" # diagnose a symptom
    python3 tools/first-contact.py --md -o docs/32-first-contact-troubleshooting.md  # render markdown

Offline. Knowledge base only — emits no USB traffic.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx import firstcontact as fc  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="First-contact JTAG troubleshooting decision tree.")
    ap.add_argument("symptom", nargs="*", help="free-text symptom to diagnose (e.g. 'no idcode')")
    ap.add_argument("--stage", choices=fc.STAGES, help="show only one stage")
    ap.add_argument("--md", action="store_true", help="render the full markdown tree")
    ap.add_argument("-o", "--out", help="write markdown to a file")
    ap.add_argument("-n", type=int, default=3, help="diagnose: number of candidates (default 3)")
    a = ap.parse_args()

    if a.md or a.out:
        blockers = fc.by_stage(a.stage) if a.stage else None
        md = fc.render_md(blockers)
        if a.out:
            with open(a.out, "w", encoding="utf-8") as fh:
                fh.write(md + "\n")
            print(f"wrote {a.out}")
        else:
            print(md)
        return

    symptom = " ".join(a.symptom).strip()
    if symptom:
        print(f"# diagnose: \"{symptom}\"\n")
        hits = fc.diagnose(symptom, limit=a.n)
        if not hits or hits[0][0] == 0:
            print("No strong match — showing the full tree may help. Try `--md`.")
            return
        for score, b in hits:
            sev = "BLOCK" if b["severity"] == "block" else "degraded"
            print(f"## [{b['stage']}] {b['id']}  ({sev})   match={score}")
            print(f"   symptom: {b['symptom']}")
            print(f"   fix:")
            for f in b["fix"]:
                print(f"     - {f}")
            print()
        return

    # No args → the whole tree, compact.
    for stage in fc.STAGES:
        bs = fc.by_stage(stage)
        if not bs:
            continue
        print(f"\n=== stage: {stage} ===")
        for b in bs:
            sev = "BLOCK" if b["severity"] == "block" else "degraded"
            print(f"  [{sev:8}] {b['id']:22} — {b['symptom']}")
    print("\n(diagnose a symptom: first-contact.py \"no idcode\"  ·  full detail: --md)")


if __name__ == "__main__":
    main()
