#!/usr/bin/env bash
# mock-fidelity-smoketest.sh — validates the mock backends' fidelity: per-region memory content
# (DRAM/OCM/PMU/ROM) and real captured register values. These are the OFFLINE test mocks used by the
# transport/console smoketests — they are NOT wired into the GUI. Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(mock-fidelity): $1"; exit 1; }
python3 -m py_compile tools/mock_common.py || fail "compile"
M="$PWD/tools/mock-openocd.py"

# 1. region classification + per-region dump content
python3 - <<'PY' || exit 1
import sys; sys.path.insert(0, "tools")
from mock_common import region_of, mem_bytes, load_regs
def bad(m): print("FAIL(mock-fidelity):", m); sys.exit(1)
for addr, name in [(0x0, "DRAM"), (0xFFFC0000, "OCM"), (0xFFD00000, "PMU_ROM"),
                   (0xFFDC0000, "PMU_RAM"), (0xFF5E0000, "MMIO")]:
    if region_of(addr) != name: bad(f"region_of({addr:#x}) should be {name}, got {region_of(addr)}")
regs = load_regs()
if b"VxWorks" not in mem_bytes(regs, 0x0, 0x400): bad("DRAM dump should carry the VxWorks banner")
if b"FSBL" not in mem_bytes(regs, 0xFFFC0000, 0x800): bad("OCM dump should carry the FSBL banner")
if b"BootROM" not in mem_bytes(regs, 0xFFD00000, 0x40): bad("PMU_ROM dump should carry the ROM marker")
print("  region fidelity OK (DRAM/OCM/PMU_ROM/PMU_RAM + MMIO)")
PY

# 2. mdw returns a real captured register value when a capture exists (else the anchor IDCODE)
OUT=$("$M" -c "init; mdw 0xFFCA0040 1; shutdown")
echo "$OUT" | grep -qi "24738093" || fail "mdw 0xFFCA0040 should return the real IDCODE"

echo "PASS: mock-fidelity (per-region memory + captured register values)"
