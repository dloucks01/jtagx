#!/usr/bin/env bash
# mock-board-smoketest.sh — validates the PARAMETRIC per-board mock (tools/mock-board.py): each board's
# scan_chain IDCODE, a family-correct flash dump carrying a decoy secret, and the locked (readout-
# protection) fault path. Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(mock-board): $1"; exit 1; }
M="$PWD/tools/mock-board.py"
python3 -m py_compile tools/mock-board.py || fail "compile"
[ -x "$M" ] || chmod +x "$M"

# 1. every profile soc scans a distinct-looking IDCODE
for soc in zynqmp zynq7000 stm32f4 nrf52 rp2040 esp32 smartfusion2 igloo2; do
    OUT=$(JTAGX_MOCK_BOARD=$soc "$M" -c "init; scan_chain; shutdown")
    echo "$OUT" | grep -q "$soc.tap" || fail "$soc scan_chain should name the tap"
    echo "$OUT" | grep -qiE "0x[0-9a-f]{8}" || fail "$soc scan_chain should print an IDCODE"
done

# 2. a Cortex-M flash dump carries a family-appropriate decoy the analysis tools find
tmp=$(mktemp)
JTAGX_MOCK_BOARD=stm32f4 JTAGX_MOCK_MAXBYTES=4096 "$M" -c "init; halt; dump_image $tmp 0x08000000 0x1000; resume; shutdown" >/dev/null
[ "$(stat -c%s "$tmp")" -eq 4096 ] || fail "stm32f4 flash dump should be the capped size"
python3 tools/dram-secrets.py "$tmp" --base 0x08000000 2>/dev/null | grep -qi "key=" \
    || fail "the flash dump should carry a recognizable secret"
rm -f "$tmp"

# 3. LOCKED (readout protection) → the mock faults and does not dump
set +e
LT=$(JTAGX_MOCK_BOARD=nrf52 JTAGX_MOCK_LOCK=locked "$M" -c "init; halt; dump_image /tmp/nope.$$ 0x0 0x1000; shutdown" 2>&1); RC=$?
set -e
echo "$LT" | grep -qi "readout protection" || fail "locked nrf52 should report readout protection"
[ "$RC" -ne 0 ] || fail "locked dump should exit nonzero"
[ -e "/tmp/nope.$$" ] && fail "locked board should not produce a dump" || true

# 4. fabric-only board (igloo2) has NO memory bus — mdw/dump fault by design, scan_chain still works
set +e
FT=$(JTAGX_MOCK_BOARD=igloo2 "$M" -c "init; halt; mdw 0x0 1; shutdown" 2>&1); FRC=$?
set -e
echo "$FT" | grep -qi "no memory bus" || fail "igloo2 should report no memory bus"
[ "$FRC" -ne 0 ] || fail "igloo2 mem access should exit nonzero"

echo "PASS: mock-board (per-board IDCODE + family flash dump + locked fault + fabric no-mem-bus)"
