#!/usr/bin/env bash
# capability-matrix-smoketest.sh — offline assertions for jtagx.transport.matrix + the CLI: the
# adapter × backend × op grid and the op router. The point is the HONEST BLOCKED verdict — a
# fabric-only part (IGLOO2, no CPU) must NOT be credited with mem/run-control just because its
# adapter's backend is OpenOCD. Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(capability-matrix): $1"; exit 1; }

python3 - <<'PY' || exit 1
import json, glob, os, sys
sys.path.insert(0, ".")
from jtagx.transport import capability_matrix, route_op, routing_plan, OPS

def bad(m): print("FAIL(capability-matrix):", m); sys.exit(1)

def prof(soc):
    for p in sorted(glob.glob("profiles/*.json")):
        if os.path.basename(p).startswith("_"): continue
        d = json.loads("".join(l for l in open(p) if not l.lstrip().startswith(("//","#"))))
        if d.get("soc") == soc: return d
    bad(f"no profile {soc}")

# 1. ZynqMP: a plain FTDI (OpenOCD, tier e) does every op; the router picks a non-vendor path.
z = capability_matrix(prof("zynqmp"))
if not z or not all(z[0]["ops"][o] for o in OPS): bad("zynqmp top adapter should support every op")
row, why = route_op(prof("zynqmp"), "mem_read")
if row is None or row["backend"] != "openocd" or row["vendor_sw"]:
    bad(f"zynqmp mem_read should route to a non-vendor OpenOCD adapter (got {why})")

# 2. SmartFusion2: mem/run-control route to the M3 CoreSight adapter (J-Link, tier e), NOT FlashPro.
sf = prof("smartfusion2")
row, why = route_op(sf, "halt")
if row is None or row["backend"] != "openocd": bad(f"SF2 halt should route to the M3 CoreSight probe (got {why})")
# FlashPro (libero) in the same matrix is scan-only (boundary-scan tier b)
fp = next((r for r in capability_matrix(sf) if r["backend"] == "libero"), None)
if fp is None or fp["ops"]["mem_read"] or fp["ops"]["halt"] or not fp["ops"]["scan"]:
    bad("SF2 FlashPro row should be scan-only (no mem/halt)")

# 3. IGLOO2 (fabric-only, NO CPU): scan works, but mem/halt/run are HONESTLY BLOCKED for every adapter.
ig = prof("igloo2")
plan = routing_plan(ig)
if plan["scan"][0] is None: bad("igloo2 scan should be routable (boundary-scan)")
for op in ("mem_read", "mem_write", "halt", "run"):
    r, why = plan[op]
    if r is not None: bad(f"igloo2 {op} must be BLOCKED (no CPU/mem bus), got {r['adapter']}")
    if "BLOCK" in why.upper() or "needs" in why:  # reason must be explanatory
        pass
    else:
        bad(f"igloo2 {op} blocked reason should explain why: {why!r}")
# and no adapter row should claim a mem/run op on igloo2
for r in capability_matrix(ig):
    if r["ops"]["mem_read"] or r["ops"]["halt"]:
        bad(f"igloo2 adapter {r['adapter']} wrongly credited with mem/run-control")
# ...but boundary-scan (tier b) IS igloo2's real capability — the DAP-gated fallback
if plan["boundary_scan"][0] is None:
    bad("igloo2 boundary-scan should be routable (tier-b, the fabric part's real capability)")
if not all(r["ops"]["boundary_scan"] for r in capability_matrix(ig)):
    bad("every igloo2 adapter should support boundary-scan (all reach tier b)")

print("  matrix OK (zynqmp full, SF2 M3-vs-FlashPro split, IGLOO2 mem/run honestly BLOCKED)")
PY

# 4. the CLI renders + supports --list
O=$((python3 tools/capability-matrix.py --profile zynqmp) 2>/dev/null); grep -q "Capability matrix" <<<"$O" \
    || fail "CLI should render the matrix"
O=$((python3 tools/capability-matrix.py --profile igloo2) 2>/dev/null); grep -q "BLOCKED" <<<"$O" \
    || fail "CLI should show BLOCKED ops for igloo2"
O=$(python3 tools/capability-matrix.py --list 2>/dev/null); grep -q "zynqmp" <<<"$O" || fail "CLI --list should list profiles"
echo "PASS: capability-matrix (adapter × backend × op grid + honest op routing)"
