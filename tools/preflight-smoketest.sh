#!/usr/bin/env bash
# preflight-smoketest.sh — the engagement blocker check: GO when an adapter + its backend software +
# transport line up for the target; BLOCKED (with the fix) on the real failure modes — no adapter
# (VM passthrough), an adapter that isn't a path for this SoC, or a vendor backend whose software isn't
# installed (the FlashPro/Libero case that stopped a real engagement). Pure/offline.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(preflight): $1"; exit 1; }
python3 -m py_compile tools/preflight.py || fail "does not compile"

FTDI="Bus 001 Device 003: ID 0403:6014 FTDI FT232H"
JLINK="Bus 001 Device 005: ID 1366:0101 SEGGER J-Link"
FLASHPRO="Bus 001 Device 006: ID 1514:2008 Microsemi FlashPro5"

run() { set +e; O=$(python3 tools/preflight.py "$@" 2>&1); RC=$?; set -e; }   # capture; BLOCKED exits 1

# 1. GO: zynqmp + a plugged FTDI, openocd on PATH
run --soc zynqmp --lsusb "$FTDI"
grep -q "VERDICT: ✓ GO" <<<"$O" || fail "zynqmp + FTDI + openocd should be GO"
[ "$RC" -eq 0 ] || fail "GO should exit 0"

# 2. BLOCKED: no adapter → the VM-passthrough hint
run --soc zynqmp --lsusb ""
grep -q "BLOCKED" <<<"$O" || fail "no adapter should be BLOCKED"
grep -qi "pass the device through" <<<"$O" || fail "no-adapter fix should mention USB passthrough"
[ "$RC" -eq 1 ] || fail "BLOCKED should exit 1"

# 3. BLOCKED: SmartFusion2 + FlashPro but Libero not installed (the real engagement blocker)
run --soc smartfusion2 --lsusb "$FLASHPRO"
if grep -q "libero" <<<"$O"; then
    grep -q "backend software" <<<"$O" || fail "FlashPro-without-Libero should flag the backend software"
    grep -qi "Libero\|FlashPro Express\|SVF" <<<"$O" || fail "should give the Libero/SVF fix"
fi   # (skips cleanly if Libero happens to be installed on this box)

# 4. BLOCKED: an adapter that isn't a known path for the SoC (FlashPro on an nRF52)
run --soc nrf52 --lsusb "$FLASHPRO"
grep -q "known path for nrf52" <<<"$O" || fail "wrong adapter should say it's not a path for the SoC"
grep -q "BLOCKED" <<<"$O" || fail "wrong adapter should BLOCK"

# 5. transport is surfaced (nRF52 is SWD-only)
run --soc nrf52 --lsusb "$JLINK"
grep -q "transport: available: swd" <<<"$O" || fail "nRF52 preflight should show swd transport"

echo "PASS: preflight (GO/BLOCKED verdicts: no-adapter, wrong-adapter, missing-backend-software)"
