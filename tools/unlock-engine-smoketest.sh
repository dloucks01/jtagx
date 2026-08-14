#!/usr/bin/env bash
# unlock-engine-smoketest.sh — offline assertions for tools/unlock-engine.py (the Phase-2b unlock
# engine). Guards the core behaviour: enforcement CLASSIFICATION (the same closed DAP must produce a
# software-lever plan when register-gated vs a hardware-only plan when eFuse-sealed), the ranked
# strategy output, valid --json, and --from-capture derivation. Offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

UE="python3 tools/unlock-engine.py"
fail() { echo "FAIL(unlock-engine): $1"; exit 1; }

python3 -m py_compile tools/unlock-engine.py || fail "does not compile"

# 1. OPEN baseline -> nothing to unlock
$UE --soc zynqmp --jtag-open | grep -q "No engaged locks" || fail "open baseline should report no locks"

# 2. LOCKED but register-gated -> enforcement REVERSIBLE + an AUTO software lever (the misconfig win)
OUT=$($UE --soc zynqmp --jtag-locked --no-efuse-jtag-dis)
echo "$OUT" | grep -q "REVERSIBLE"  || fail "register-gated should classify enforcement REVERSIBLE"
echo "$OUT" | grep -q '\[AUTO'      || fail "register-gated should offer an AUTO software lever"

# 3. LOCKED + eFuse-sealed -> HARDWARE enforcement + ZERO auto levers (opposite plan, same closed DAP)
OUT=$($UE --soc zynqmp --jtag-locked --efuse-jtag-dis)
echo "$OUT" | grep -q "eFuse-sealed (HARDWARE"        || fail "eFuse case should classify HARDWARE"
echo "$OUT" | grep -q "0 auto-tryable software lever" || fail "eFuse case should have 0 auto levers"

# 4. multi-lock hardened -> secure-boot + AES sections present
OUT=$($UE --soc zynqmp --jtag-locked --secure-boot on --aes-encrypt)
echo "$OUT" | grep -q "Secure boot"         || fail "hardened plan should include secure-boot"
echo "$OUT" | grep -q "Boot AES encryption" || fail "hardened plan should include AES"

# 5. --json emits valid JSON
$UE --soc zynqmp --jtag-locked --secure-boot on --json | python3 -c "import json,sys; json.load(sys.stdin)" \
    || fail "--json output is not valid JSON"

# 6. --from-capture derives without crashing (uses the golden capture if present)
GOLD="tests/golden/zcu102-jtag-idle/raw.json"
if [ -f "$GOLD" ]; then
    $UE --from-capture "$GOLD" >/dev/null 2>&1 || fail "--from-capture on the golden raw.json errored"
fi

# --- bsdl-scan (boundary-scan alt-path — the DAP-shut unlock avenue) ---
BS="python3 tools/bsdl-scan.py tests/fixtures/fake1149.bsdl"
python3 -m py_compile tools/bsdl-scan.py || fail "bsdl-scan does not compile"
$BS               | grep -q "0x10002013"  || fail "bsdl summary should show IDCODE 0x10002013"
$BS               | grep -q "readable pins" || fail "bsdl summary should list readable pins"
$BS --decode 0x2a | grep -qE "RESETN[[:space:]]+input[[:space:]]+= 1"   || fail "decode 0x2a: RESETN should be 1"
$BS --decode 0x2a | grep -qE "BOOTMODE[[:space:]]+input[[:space:]]+= 0" || fail "decode 0x2a: BOOTMODE should be 0"
$BS --pin RESETN  | grep -q "boundary bit 1" || fail "pin RESETN should be boundary bit 1"
$BS --sample-plan | grep -q "irscan"          || fail "sample-plan should emit an irscan sequence"

# --- oe-key-extract (crypto-break: AES key-schedule recovery) ---
python3 -m py_compile tools/oe-key-extract.py || fail "oe-key-extract does not compile"
python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('o','tools/oe-key-extract.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
assert m._expand(bytes.fromhex('000102030405060708090a0b0c0d0e0f'))[16:20].hex()=='d6aa74fd'   # FIPS-197
" || fail "oe-key-extract AES key-expansion != FIPS-197"
python3 - <<'PYEOF' > /tmp/oke-smoke.bin
import importlib.util, struct, sys
s=importlib.util.spec_from_file_location('o','tools/oe-key-extract.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
sys.stdout.buffer.write(struct.pack('<I',0x120)+b'\x00'*12+m._expand(bytes(range(16))))
PYEOF
python3 tools/oe-key-extract.py /tmp/oke-smoke.bin | grep -q "000102030405060708090a0b0c0d0e0f" \
    || fail "oe-key-extract should recover the planted AES-128 key from a stored schedule"

echo "PASS: unlock-engine (+ bsdl-scan + oe-key-extract) — unlock plan/BSDL parse+decode/AES-key recovery"
