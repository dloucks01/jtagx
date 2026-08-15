#!/usr/bin/env bash
# unlock-workflow-smoketest.sh — validates the guided locked-board reopen→VERIFY workflow (the core
# mission): the engine parsers/classifier, and the full lever→verify loop rehearsed against the
# stateful locked-board mock (tools/mock-openocd.py). Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(unlock-workflow): $1"; exit 1; }
MOCK="$PWD/tools/mock-openocd.py"
python3 -m py_compile tools/mock-openocd.py || fail "mock does not compile"
[ -x "$MOCK" ] || chmod +x "$MOCK"

# 1. engine: parsers + classifier + workflow_steps (no hardware)
python3 - <<'PY' || exit 1
import sys
from jtagx.unlock import (build_plan, workflow_steps, parse_access_verdict, parse_reopen_result,
                          classify_reopen, verify_cmd)
def bad(m): print("FAIL(unlock-workflow):", m); sys.exit(1)
if parse_access_verdict("== ACCESS VERDICT: OPEN ==") != "OPEN": bad("verdict parse")
if parse_reopen_result("-> all JTAG_SEC gates now OPEN") != "REOPENED": bad("reopen parse REOPENED")
if parse_reopen_result("-> DAP_SEC did NOT stick: eFuse") != "SEALED": bad("reopen parse SEALED")
if classify_reopen("REOPENED", "OPEN")[0] != "DEFEATED": bad("classify DEFEATED")
if classify_reopen("SEALED", "LOCKED")[0] != "RESISTED": bad("classify RESISTED")
if classify_reopen("PARTIAL-EFUSE", "RESTRICTED")[0] != "PARTIAL": bad("classify PARTIAL")
steps = workflow_steps("zynqmp", build_plan("zynqmp", {"jtag_open": False, "efuse_jtag_dis": False}))
if not steps or steps[0]["status"] != "ENGAGED" or not steps[0]["lever"] or not steps[0]["verify_cmd"]:
    bad("register-gated DAP should yield an ENGAGED step with a lever + verify command")
print("  engine OK (parsers + classifier + workflow_steps)")
PY

# 2. full loop via the stateful mock — register-gated DEFEATS, efuse-sealed RESISTS
run_scenario() {
  local scen="$1" expect="$2"
  local st; st=$(mktemp)
  OPENOCD="$MOCK" JTAGX_MOCK_STATE="$st" JTAGX_MOCK_LOCK="$scen" python3 - "$expect" "$scen" <<'PY' || exit 1
import subprocess, sys
from jtagx.unlock import build_plan, workflow_steps, parse_access_verdict, parse_reopen_result, classify_reopen
expect, scen = sys.argv[1], sys.argv[2]
def bad(m): print("FAIL(unlock-workflow):", m); sys.exit(1)
step = workflow_steps("zynqmp", build_plan("zynqmp", {"jtag_open": False, "efuse_jtag_dis": False}))[0]
run = lambda c: subprocess.run(["bash", "-lc", c], capture_output=True, text=True).stdout
before = parse_access_verdict(run(step["verify_cmd"]))
if before != "LOCKED": bad(f"{scen}: board should read LOCKED before the lever (got {before})")
outcome = parse_reopen_result(run(step["lever"]["cmd"]))
after = parse_access_verdict(run(step["verify_cmd"]))
status = classify_reopen(outcome, after)[0]
if status != expect: bad(f"{scen}: expected {expect}, got {status} (outcome={outcome}, verdict={after})")
print(f"  {scen}: LOCKED → lever({outcome}) → {after} → {status}  ✓")
PY
  rm -f "$st"
}
run_scenario register-gated DEFEATED
run_scenario efuse-sealed   RESISTED
run_scenario no-write-path  RESISTED

# 3. Cortex-M boards (nRF52 APPROTECT, STM32 RDP1) — the mass-erase lever DEFEATS (destructive);
#    secure-APPROTECT / RDP2 variants RESIST. Proves the guided loop is board-aware, not ZynqMP-only.
run_cm() {
  local soc="$1" posture="$2" scen="$3" expect="$4"
  local st; st=$(mktemp); rm -f "$st"
  OPENOCD="$MOCK" JTAGX_MOCK_STATE="$st" JTAGX_MOCK_LOCK="$scen" \
    python3 - "$soc" "$posture" "$scen" "$expect" <<'PY' || exit 1
import subprocess, sys, json
from jtagx.unlock import (build_plan, workflow_steps, parse_access_verdict,
                          parse_reopen_result, classify_reopen)
soc, posture, scen, expect = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3], sys.argv[4]
def bad(m): print("FAIL(unlock-workflow):", m); sys.exit(1)
steps = workflow_steps(soc, build_plan(soc, posture))
step = next((s for s in steps if s["lever"] and s["lever"].get("cmd")), None)
if not step: bad(f"{soc}: expected an ENGAGED step with a runnable lever")
if not step["verify_cmd"]: bad(f"{soc}: lever should carry a board-aware verify command")
run = lambda c: subprocess.run(["bash","-lc",c], capture_output=True, text=True).stdout
before = parse_access_verdict(run(step["verify_cmd"]))
if before != "LOCKED": bad(f"{soc}/{scen}: should read LOCKED before the lever (got {before})")
outcome = parse_reopen_result(run(step["lever"]["cmd"]))
after = parse_access_verdict(run(step["verify_cmd"]))
status = classify_reopen(outcome, after)[0]
if status != expect: bad(f"{soc}/{scen}: expected {expect}, got {status} (outcome={outcome}, after={after})")
if not step["lever"]["destructive"]: bad(f"{soc}: the mass-erase lever must be flagged destructive")
print(f"  {soc}: LOCKED → lever({outcome}) → {after} → {status}  ✓")
PY
  rm -f "$st"
}
run_cm nrf52   '{"approtect_locked": true}' register-gated   DEFEATED
run_cm nrf52   '{"approtect_locked": true}' approtect-sealed RESISTED
run_cm stm32f4 '{"rdp_level": 1}'           register-gated   DEFEATED
run_cm stm32f4 '{"rdp_level": 1}'           rdp2-sealed      RESISTED
run_cm stm32l4 '{"rdp_level": 1}'           register-gated   DEFEATED
# Kinetis MDM-AP mass-erase + SAMD DSU chip-erase — debug-mailbox recoveries (NOT glitch), destructive.
run_cm kinetis '{"flash_secured": true}'    register-gated   DEFEATED
run_cm kinetis '{"flash_secured": true}'    meen-disabled    RESISTED
run_cm samd5x  '{"debug_protected": true}'  register-gated   DEFEATED
run_cm samd5x  '{"debug_protected": true}'  dsu-sealed       RESISTED

# 4. IGLOO2 (fabric, NO CPU): the "access" verdict is provisioning state, not a reopenable debug port.
#    An UNPROVISIONED device reads OPEN and the SVF readback lever extracts it (DEFEATED, non-destructive);
#    a PROVISIONED device reads LOCKED and readback RESISTS. This is fabric-part bench-readiness.
run_ms() {
  local scen="$1" expect="$2" want_verdict="$3"
  local st; st=$(mktemp); rm -f "$st"
  OPENOCD="$MOCK" JTAGX_MOCK_STATE="$st" JTAGX_MOCK_LOCK="$scen" \
    python3 - "$scen" "$expect" "$want_verdict" <<'PY' || exit 1
import subprocess, sys
from jtagx.unlock import (build_plan, workflow_steps, parse_access_verdict,
                          parse_reopen_result, classify_reopen)
scen, expect, want_verdict = sys.argv[1], sys.argv[2], sys.argv[3]
def bad(m): print("FAIL(unlock-workflow):", m); sys.exit(1)
step = next((s for s in workflow_steps("igloo2", build_plan("igloo2", {"flashlock": True}))
             if s["lever"] and s["lever"].get("cmd")), None)
if not step: bad("igloo2 should offer a runnable SVF-readback lever")
if step["lever"]["destructive"]: bad("igloo2 SVF readback must be NON-destructive (readback only)")
run = lambda c: subprocess.run(["bash","-lc",c], capture_output=True, text=True).stdout
before = parse_access_verdict(run(step["verify_cmd"]))
if before != want_verdict: bad(f"igloo2/{scen}: expected verdict {want_verdict}, got {before}")
outcome = parse_reopen_result(run(step["lever"]["cmd"]))
after = parse_access_verdict(run(step["verify_cmd"]))
status = classify_reopen(outcome, after)[0]
if status != expect: bad(f"igloo2/{scen}: expected {expect}, got {status} (outcome={outcome})")
print(f"  igloo2: verdict({before}) → readback({outcome}) → {status}  ✓")
PY
  rm -f "$st"
}
run_ms unprovisioned DEFEATED OPEN
run_ms provisioned   RESISTED LOCKED

echo "PASS: unlock-workflow (engine + reopen→verify loop rehearsed via the locked-board mock)"
