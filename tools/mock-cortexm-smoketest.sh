#!/usr/bin/env bash
# mock-cortexm-smoketest.sh — rehearses the SmartFusion2 Cortex-M3 extraction path against the cortexm
# mock: with debug OPEN the M3 mem-AP dumps eNVM (and dram-secrets finds a planted secret); with the M3
# debug security-LOCKED the DAP faults and nothing dumps (→ FlashPro/DPA fallback per the unlock plan).
# Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(mock-cortexm): $1"; exit 1; }
M="$PWD/tools/mock-cortexm.py"
python3 -m py_compile tools/mock-cortexm.py || fail "mock does not compile"
[ -x "$M" ] || chmod +x "$M"

# 1. UNLOCKED: eNVM dump succeeds and carries a recognizable secret
OUT="$(mktemp)"
JTAGX_MOCK_MAXBYTES=8192 SF2_OUT="$OUT" "$M" -c "init; halt; source openocd/cortexm-dump.tcl; resume; shutdown" >/dev/null
[ -s "$OUT" ] || fail "unlocked M3 should dump eNVM to a file"
[ "$(stat -c%s "$OUT")" -eq 8192 ] || fail "eNVM dump should be the capped size (8192)"
O=$((python3 tools/dram-secrets.py "$OUT" --base 0x60000000 2>/dev/null) 2>/dev/null); grep -qi "aeskey" <<<"$O" \
    || fail "the eNVM dump should carry a recognizable secret (dram-secrets)"
rm -f "$OUT"

# 2. eNVM mdw returns eNVM content (region model), and region_of classifies it
python3 - <<'PY' || exit 1
import sys; sys.path.insert(0, "tools")
from mock_common import region_of
def bad(m): print("FAIL(mock-cortexm):", m); sys.exit(1)
if region_of(0x60000000) != "eNVM": bad("0x60000000 should classify as eNVM")
if region_of(0x20000000) != "eSRAM": bad("0x20000000 should classify as eSRAM")
print("  region model OK (eNVM/eSRAM)")
PY

# 3. LOCKED: M3 debug security-locked → the DAP faults, no dump, nonzero exit
LOUT="$(mktemp)"; rm -f "$LOUT"
set +e
LTEXT=$(JTAGX_MOCK_LOCK=debug-locked SF2_OUT="$LOUT" "$M" -c "init; halt; source openocd/cortexm-dump.tcl; shutdown" 2>&1)
LRC=$?
set -e
echo "$LTEXT" | grep -qi "security-locked" || fail "locked M3 should report the DAP fault"
[ "$LRC" -ne 0 ] || fail "locked M3 dump should exit nonzero"
[ -e "$LOUT" ] && fail "locked M3 should NOT produce a dump file" || true

echo "PASS: mock-cortexm (SmartFusion2 M3: open→eNVM dump+secret, locked→DAP fault/no dump)"
