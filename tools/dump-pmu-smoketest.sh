#!/usr/bin/env bash
# dump-pmu-smoketest.sh — fast offline check that dump-pmu.tcl parses
# and runs end-to-end under stubs, exercising every region dispatcher
# branch (rom, lmb, all, default-no-override).
#
# Mirrors tools/dump-bootrom-smoketest.sh — same stub philosophy, just
# for the PMU dump path. Run before commits touching openocd/dump-pmu.tcl
# or lib/* it sources.
#
# Exits 0 on clean run, 1 if any dispatcher branch fails.

set -euo pipefail

cd "$(dirname "$0")/.."

STUB_TCL=$(mktemp /tmp/dump-pmu-stubs.XXXXXX.tcl)
trap "rm -f $STUB_TCL" EXIT

cat > "$STUB_TCL" <<'STUB_EOF'
proc exec {args} { return "" }
proc echo {line} { puts $line }
proc init {} {}
proc shutdown {} {}
proc targets {args} { return "" }
proc write_memory {addr width data} { return "" }
proc read_memory {addr width nwords {args ""}} {
    set out [list]
    for {set i 0} {$i < $nwords} {incr i} { lappend out 0xDEADBEEF }
    return $out
}
proc uscale.axi {args} { return "" }
proc uscale.dap {args} { return "" }

set ::tmpdir /tmp/dump-pmu-smoketest-dumps
file mkdir $::tmpdir

set ::passed 0
set ::failed 0
foreach _t_region {rom lmb rom-unlocked all default-noregion-override} {
    puts ""
    puts "##### region: $_t_region #####"
    if {[catch {
        foreach v [list ::REPORT_FH ::_ts ::_dumps_dir ::_log_path \
                        ::_script_dir ::_repo_root ::_which \
                        ::_t_script_start ::PMU_REGION] {
            if {[info exists $v]} { unset $v }
        }
        if {$_t_region ne "default-noregion-override"} {
            set ::PMU_REGION $_t_region
        }
        set ::DUMPS_DIR_OVERRIDE $::tmpdir
        set ::TS_OVERRIDE "TEST-$_t_region"
        source openocd/dump-pmu.tcl
        puts ">>> $_t_region: OK"
        incr ::passed
    } err]} {
        puts ">>> $_t_region: FAIL - $err"
        puts $::errorInfo
        incr ::failed
    }
}

puts ""
puts "============================================================"
puts "dump-pmu.tcl smoketest: $::passed/5 regions OK, $::failed failed"
puts "============================================================"
exit $::failed
STUB_EOF

echo "=== dump-pmu.tcl region smoketest ==="
if ! /usr/bin/tclsh "$STUB_TCL" 2>&1 | grep -E "^>>>|^##### region:|smoketest:|^FAIL"; then
    echo "FAIL: tcl smoketest exited non-zero"
    exit 1
fi

rm -rf /tmp/dump-pmu-smoketest-dumps

echo ""
echo "PASS: dump-pmu.tcl all green"
exit 0
