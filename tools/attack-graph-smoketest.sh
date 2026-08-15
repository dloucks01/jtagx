#!/usr/bin/env bash
# attack-graph-smoketest.sh — offline assertions for jtagx.attackgraph + the CLI: the kill-chain planner
# fuses unlock/matrix/findings into an ordered path with honest per-node states and a non-physical reach
# depth. The point is that it STALLS honestly (BLOCKED) where only a physical rig would continue.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(attack-graph): $1"; exit 1; }
python3 -m py_compile tools/attack-graph.py jtagx/attackgraph.py || fail "does not compile"

python3 - <<'PY' || exit 1
import json, subprocess, sys
def bad(m): print("FAIL(attack-graph):", m); sys.exit(1)
def g(*args):
    out = subprocess.run(["python3","tools/attack-graph.py",*args,"--json"],
                         capture_output=True,text=True)
    if out.returncode: bad(f"CLI failed: {out.stderr}")
    return json.loads(out.stdout)
def node(gr, nid): return next(n for n in gr["nodes"] if n["id"] == nid)

# 1. ZynqMP OPEN → full non-physical reach (5/5), debug already ACHIEVED
z = g("--soc","zynqmp","--jtag-open")
if z["depth"] != 5: bad(f"zynqmp open should reach 5/5 (got {z['depth']})")
if node(z,"debug-open")["state"] != "ACHIEVED": bad("zynqmp open: debug-open should be ACHIEVED")

# 2. nRF52 LOCKED → still 5/5, but debug-open is AVAILABLE via a lever (the pivot), NOT ACHIEVED
n = g("--soc","nrf52","--approtect-locked")
if node(n,"debug-open")["state"] != "AVAILABLE": bad("nrf52 locked: debug-open should be AVAILABLE (lever)")
if "nrf52-recover" not in node(n,"debug-open")["action"]: bad("nrf52 debug-open action should be the recovery lever")

# 3. eFuse-SEALED ZynqMP → NO software lever → debug-open BLOCKED, reach stalls at 1/5
s = g("--soc","zynqmp","--jtag-locked","--efuse-jtag-dis")
if node(s,"debug-open")["state"] != "BLOCKED": bad("efuse-sealed: debug-open must be BLOCKED (no lever)")
if s["depth"] != 1: bad(f"efuse-sealed should stall at 1/5 (got {s['depth']})")
if "glitch" not in node(s,"debug-open")["why"]: bad("blocked debug-open should point at the deferred physical path")

# 4. IGLOO2 (fabric, no CPU) → extraction is the Microsemi readback path (not a CPU dump), reach 4/5
i = g("--soc","igloo2","--flashlock")
if node(i,"mem-read")["state"] != "AVAILABLE": bad("igloo2 mem-read should be AVAILABLE via readback")
if "readback" not in node(i,"mem-read")["action"].lower(): bad("igloo2 extraction should name the readback path")
if node(i,"secrets")["state"] != "AVAILABLE": bad("igloo2 secrets should be AVAILABLE once readable")
if i["depth"] != 4: bad(f"igloo2 should reach 4/5 (got {i['depth']})")

# 4b. EXTRACTION DEEPENING: i.MX6 with JTAG FUSED OFF still reaches secrets via the SDP ROM loader
# (extraction no longer strictly needs the debug port). debug-open BLOCKED but mem-read AVAILABLE.
mx = g("--soc","imx6","--jtag-locked","--efuse-jtag-dis")
if node(mx,"debug-open")["state"] != "BLOCKED": bad("imx6 fused: debug-open should be BLOCKED")
if node(mx,"mem-read")["state"] != "AVAILABLE": bad("imx6 fused: mem-read should be AVAILABLE via SDP (no debug)")
if "SDP" not in node(mx,"mem-read")["action"]: bad("imx6 extraction should be the SDP ROM loader")
if not node(mx,"mem-read")["needs"] == []: bad("SDP extraction should NOT need debug-open")
if mx["depth"] != 4: bad(f"imx6 fused should still reach 4/5 via SDP (got {mx['depth']})")

# 5. secure-boot branch fires when the posture asserts it
sb = g("--soc","zynqmp","--jtag-open","--secure-boot","on")
if node(sb,"secure-boot")["state"] != "AVAILABLE": bad("secure-boot ON should make the branch AVAILABLE")
if "JustSTART" not in node(sb,"secure-boot")["action"]: bad("zynqmp secure-boot branch should offer JustSTART")

# 6. no-chain → nothing below is reachable (reach 0)
nc = g("--soc","stm32f4","--no-chain")
if nc["depth"] != 0: bad(f"no-chain should reach 0 (got {nc['depth']})")

print("  attack-graph OK (reach depth, lever-pivot, eFuse-stall, fabric-BLOCKED, secure-boot branch)")
PY

echo "PASS: attack-graph (kill-chain planner: ordered path + honest BLOCKED stalls)"
