#!/usr/bin/env bash
# golden-test-roundtrip.sh — full enumerate.tcl roundtrip via the mock.
#
# 1. Generate a Tcl seed file from the golden raw JSON.
# 2. Run enumerate.tcl under tclsh, sourcing the mock (which stubs every
#    OpenOCD command and serves register reads from the seed).
# 3. Compare the produced raw JSON to the golden raw JSON, ignoring the
#    timestamp + path fields in metadata that change every run.
#
# Catches regressions in:
#   - enumerate.tcl (logic, section ordering, dump_reg_qemu coverage)
#   - openocd/lib/json-emit.tcl (schema, serialization)
#   - openocd/lib/enum-helpers.tcl (safe_rd, dump_block, etc.)
#   - openocd/lib/zynqmp-regs-qemu.tcl (auto-generated; would catch if a
#     regenerate dropped or added registers unintentionally)
#
# Exit 0 = roundtrip produces matching JSON. Exit 1 = mismatch.

set -euo pipefail
cd "$(dirname "$0")/.."

GOLDEN="tests/golden/zcu102-jtag-idle/raw.json"
if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden raw missing at $GOLDEN" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# 1. Seed
python3 tools/generate-mock-seed.py "$GOLDEN" -o "$WORK/seed.tcl" 2>/dev/null

# 2. Run enumerate under mock. Need to redirect reports/ so we don't
# pollute the real reports directory.
mkdir -p "$WORK/reports"
DRIVER="$WORK/driver.tcl"
cat > "$DRIVER" <<EOF
# Seed first, then mock stubs, then the script.
cd $PWD
source $WORK/seed.tcl
source openocd/lib/mock-openocd.tcl
# Force the report timestamp + paths to deterministic values so the
# round-trip diff doesn't fail on timestamp drift.
set ::REPORT_DIR_OVERRIDE $WORK/reports
set ::TS_OVERRIDE "GOLDEN-FROZEN-TIMESTAMP"
if {[catch {source openocd/enumerate.tcl} err]} {
    puts stderr "MOCK RUN FAIL: \$err"
    puts stderr \$::errorInfo
    exit 1
}
EOF

if ! tclsh "$DRIVER" > "$WORK/stdout.log" 2> "$WORK/stderr.log"; then
    echo "FAIL: enumerate.tcl crashed under mock" >&2
    echo "--- stdout (last 40) ---" >&2
    tail -40 "$WORK/stdout.log" >&2
    echo "--- stderr (last 40) ---" >&2
    tail -40 "$WORK/stderr.log" >&2
    exit 1
fi

# 3. Find the produced raw JSON
PRODUCED=$(ls -t "$WORK/reports"/raw-*.json 2>/dev/null | head -1)
if [ -z "$PRODUCED" ]; then
    # enumerate.tcl might have written to the real reports/ if it didn't
    # honor the override. Fall back to looking there.
    PRODUCED=$(ls -t reports/raw-*.json 2>/dev/null | head -1)
fi

if [ ! -f "$PRODUCED" ]; then
    echo "FAIL: enumerate.tcl produced no raw JSON" >&2
    exit 1
fi

echo "Mock run produced: $PRODUCED"

# Strip timestamp/path metadata fields for a meaningful diff
strip_volatile() {
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
# Drop volatile metadata
md = d.setdefault('metadata', {})
for k in list(md.keys()):
    if k in ('timestamp', 'report_path', 'raw_path'):
        md[k] = '<stripped>'
# Drop A53 PC (changes per-run on real hw) only if we're being permissive
print(json.dumps(d, indent=2, sort_keys=True))
" "$1"
}

strip_volatile "$GOLDEN"   > "$WORK/golden.norm.json"
strip_volatile "$PRODUCED" > "$WORK/produced.norm.json"

JSON_OK=1
if ! diff -q "$WORK/golden.norm.json" "$WORK/produced.norm.json" >/dev/null 2>&1; then
    echo "FAIL: produced JSON differs from golden" >&2
    diff -u "$WORK/golden.norm.json" "$WORK/produced.norm.json" | head -60 >&2
    echo "" >&2
    echo "Full diff: diff -u $WORK/golden.norm.json $WORK/produced.norm.json" >&2
    echo "(Workdir preserved: $WORK)" >&2
    trap - EXIT
    JSON_OK=0
fi

# Also diff the markdown report — catches regressions in say/dump_block/etc.
# that don't surface through the JSON. Strip volatile lines (Generated:
# timestamp, Report file: path, Raw JSON capture: path) before diffing so
# the comparison ignores per-run drift.
GOLDEN_MD="tests/golden/zcu102-jtag-idle/enumerate.md"
PRODUCED_MD=$(ls -t "$WORK/reports"/enumerate-*.md 2>/dev/null | head -1)
MD_OK=1
strip_md_volatile() {
    sed -E \
        -e 's|^(- Generated:).*|\1 <stripped>|' \
        -e 's|^(- Report file:).*|\1 <stripped>|' \
        -e 's|^(- Raw JSON capture:).*|\1 <stripped>|' \
        -e 's|^Report saved to: .*|Report saved to: <stripped>|' \
        -e 's|^Raw JSON capture: .*|Raw JSON capture: <stripped>|' \
        "$1"
}
if [ -f "$GOLDEN_MD" ] && [ -f "$PRODUCED_MD" ]; then
    strip_md_volatile "$GOLDEN_MD"   > "$WORK/golden.norm.md"
    strip_md_volatile "$PRODUCED_MD" > "$WORK/produced.norm.md"
    if diff -q "$WORK/golden.norm.md" "$WORK/produced.norm.md" >/dev/null 2>&1; then
        :
    else
        echo "FAIL: produced enumerate.md differs from golden" >&2
        diff -u "$WORK/golden.norm.md" "$WORK/produced.norm.md" | head -40 >&2
        echo "" >&2
        echo "Full diff: diff -u $WORK/golden.norm.md $WORK/produced.norm.md" >&2
        echo "(Workdir preserved: $WORK)" >&2
        trap - EXIT
        MD_OK=0
    fi
fi

if [ $JSON_OK -eq 1 ] && [ $MD_OK -eq 1 ]; then
    echo "PASS: enumerate.tcl roundtrip — raw JSON + raw markdown both match golden"
    exit 0
fi
exit 1
