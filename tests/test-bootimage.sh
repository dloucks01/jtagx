#!/usr/bin/env bash
# test-bootimage.sh — offline parser + live PHT-walk regression test.
#
# Builds a synthetic boot image (tests/bootimage_fixture.py) with a secure PS
# partition and an auth-only PL bitstream partition, then checks:
#   1. tools/parse-bootimage.py parses it and flags the PL auth-only partition.
#   2. enumerate.tcl's ::BH_ADDR walk (driven by a file-backed read_memory mock)
#      captures the same PHT.PART* registers and the rule fires.
# No hardware. Exits 0 on success, 1 on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
IMG="$WORK/boot-fixture.bin"

python3 tests/bootimage_fixture.py "$IMG" >/dev/null

# --- 1. Offline parser ------------------------------------------------------
OUT=$(python3 tools/parse-bootimage.py "$IMG")
echo "$OUT" | grep -q "magic            : OK" \
    || { echo "FAIL: parser didn't validate boot-header magic"; exit 1; }
echo "$OUT" | grep -q "checksum=OK" \
    || { echo "FAIL: parser PH checksum validation missing"; exit 1; }
echo "$OUT" | grep -qE "partition 1 .DEST_DEVICE=PL.: encrypted=False authenticated=True" \
    || { echo "FAIL: parser didn't flag PL auth-only partition"; echo "$OUT"; exit 1; }
echo "PASS: offline parser flags PL auth-only partition"

# --- 2. Live walk via file-backed read_memory mock --------------------------
STUB="$WORK/stub.tcl"
cat > "$STUB" <<EOF
proc targets {args} { return "" }
set ::BH_ADDR 0xC0000000
set ::IMGFILE "$IMG"
# Serve 32-bit LE words from the fixture for addresses in [BH, BH+0x200); else 0.
proc read_memory {addr width count} {
    set off [expr {\$addr - 0xC0000000}]
    if {\$off < 0 || \$off >= 0x200} { return [list 0] }
    set fh [open \$::IMGFILE rb]
    seek \$fh \$off
    set data [read \$fh 4]
    close \$fh
    if {[string length \$data] < 4} { return [list 0] }
    binary scan \$data iu word
    return [list \$word]
}
proc safe_wr {args} { return 0 }
proc reg {args} { return "0x12345678" }
proc halt {args} { return 0 }
proc uscale.dap {args} { return 0 }
proc uscale.axi {args} { return 0 }
proc uscale.a53.0 {args} { return "halted" }
proc jtag {args} { return "" }
proc after {args} { return 0 }
proc sleep {args} { return 0 }
proc echo {args} { return 0 }
proc exit {args} { return 0 }
set ::REPORT_DIR_OVERRIDE $WORK
source openocd/enumerate.tcl
EOF

tclsh "$STUB" >/dev/null 2>&1 || { echo "FAIL: enumerate crashed under BH walk mock"; exit 1; }
RAW=$(ls -t "$WORK"/raw-*.json 2>/dev/null | head -1)
[ -z "$RAW" ] && RAW=$(ls -t reports/raw-*.json | head -1)

python3 - "$RAW" <<'PY'
import json, sys
sys.path.insert(0, "tools"); sys.path.insert(0, "docs/findings")
from interpret_lib import Capture
from zynqmp_rules import rule_pl_bitstream_unprotected
d = json.load(open(sys.argv[1]))
c = Capture(d)
# PL partition (index 1) should be DEST_DEVICE=2, ENCRYPT=0, AC_FLAG=1
assert c.field("PHT.PART1_ATTR.DEST_DEVICE") == 2, "PART1 DEST_DEVICE != PL"
assert c.field("PHT.PART1_ATTR.ENCRYPT") == 0, "PART1 ENCRYPT != 0"
assert c.field("PHT.PART1_ATTR.AC_FLAG") == 1, "PART1 AC_FLAG != 1"
# Secure PS partition (index 0) must exist and be enc+auth
assert c.field("PHT.PART0_ATTR.ENCRYPT") == 1 and c.field("PHT.PART0_ATTR.AC_FLAG") == 1
f = rule_pl_bitstream_unprotected(c)
assert f is not None and f.severity == "MAJOR", f"rule didn't fire MAJOR: {f}"
print("PASS: live PHT walk captured partitions + rule fired MAJOR")
PY
# Clean any stray raw written to real reports/ during fallback
find reports -name 'raw-*.json' -mmin -1 -delete 2>/dev/null || true

# --- 3. Real-board golden: actual ZCU102 BOOT.BIN header region ----------------
# (provenance: tests/golden/zcu102-bootimage/README.md)
GOLD_DIR="tests/golden/zcu102-bootimage"
GOLD_BIN="$GOLD_DIR/boot-partial-64k.bin"
GOLD_STRUCT="$GOLD_DIR/parse-structural.golden"
if [ -f "$GOLD_BIN" ] && [ -f "$GOLD_STRUCT" ]; then
    REAL_OUT=$(python3 tools/parse-bootimage.py "$GOLD_BIN")
    # 3a. structural section (deterministic parsed facts) must match the golden
    if ! diff <(printf '%s\n' "$REAL_OUT" | sed '/== Posture findings ==/,$d') "$GOLD_STRUCT" >/dev/null; then
        echo "FAIL: parse-bootimage.py structural output drifted from real-board golden"
        diff <(printf '%s\n' "$REAL_OUT" | sed '/== Posture findings ==/,$d') "$GOLD_STRUCT" || true
        echo "(if the parser change is intentional, regenerate per $GOLD_DIR/README.md)"
        exit 1
    fi
    # 3b. the unprotected-PL finding must still fire on the real image
    echo "$REAL_OUT" | grep -q "\[CRITICAL\] PL bitstream" \
        || { echo "FAIL: real-board golden no longer flags the unprotected PL bitstream"; exit 1; }
    echo "PASS: real-board BOOT.BIN golden (structural match + CRITICAL PL finding)"
else
    echo "SKIP: real-board boot-image golden not present ($GOLD_BIN)"
fi
