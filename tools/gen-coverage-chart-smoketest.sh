#!/usr/bin/env bash
# gen-coverage-chart-smoketest.sh — the coverage chart is GENERATED from live data, so it can't drift.
# Assert the tier tally, that every profile appears, and that the tier rubric agrees with the unlock
# engine (a board with a runnable lever is bench-ready). Pure/offline.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(gen-coverage-chart): $1"; exit 1; }
python3 -m py_compile tools/gen-coverage-chart.py || fail "does not compile"

python3 - <<'PY' || exit 1
import subprocess, sys, glob, os, json
sys.path.insert(0, ".")
import importlib.util
spec = importlib.util.spec_from_file_location("gcc", "tools/gen-coverage-chart.py")
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
def bad(m): print("FAIL(gen-coverage-chart):", m); sys.exit(1)

boards = g.all_boards()
nprofiles = len([p for p in glob.glob("profiles/*.json") if not os.path.basename(p).startswith("_")])
if len(boards) != nprofiles: bad(f"every profile should appear ({len(boards)} != {nprofiles})")
counts = {t: sum(1 for b in boards if b["tier"] == t) for t in ("proven","ready","scaffold","vendor")}
if counts["proven"] != 1: bad(f"exactly one proven board (zynqmp), got {counts['proven']}")
if not any(b["soc"]=="zynqmp" and b["tier"]=="proven" for b in boards): bad("zynqmp must be proven")

# rubric consistency: a board whose security_model has a runnable lever must be tier 'ready' (or proven)
from jtagx.unlock import security_model
for b in boards:
    has_lever = any(s.get("cmd") for L in security_model(b["soc"]) for s in L.get("strategies", []))
    if has_lever and b["tier"] not in ("ready","proven"):
        bad(f"{b['soc']} has a runnable lever but tier={b['tier']} (rubric drift)")
    # every board is identifiable + has an attack-surface count
    if b["identify"] != "yes": bad(f"{b['soc']} should be identifiable")

# the HTML renders with one row per board and matching stat counts
h = g.render(boards)
if h.count('class="board"') != len(boards): bad("HTML row count != board count")
if f'class="stat s-ready"><div class="n">{counts["ready"]}<' not in h: bad("ready stat mismatch")
print(f"  gen-coverage-chart OK ({len(boards)} boards; {counts['proven']} proven / "
      f"{counts['ready']} ready / {counts['scaffold']} scaffold; rubric consistent with unlock engine)")
PY

# CLI --counts + -o
O=$(python3 tools/gen-coverage-chart.py --counts); grep -q "total" <<<"$O" || fail "--counts should print a tally"
T=$(mktemp); python3 tools/gen-coverage-chart.py -o "$T" >/dev/null; grep -q "Board Coverage" "$T" || fail "-o should write the chart"; rm -f "$T"

echo "PASS: gen-coverage-chart (generated from live data — no drift; rubric matches the unlock engine)"
