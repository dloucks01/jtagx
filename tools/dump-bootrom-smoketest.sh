#!/usr/bin/env bash
# dump-bootrom-smoketest.sh — fast offline check that dump-bootrom.tcl
# parses and runs end-to-end under stubs, exercising every dispatcher
# branch (baseline, csudma, a53, loader, r5, aes, all).
#
# Catches:
#   - Tcl syntax errors in dump-bootrom.tcl or lib/* it sources
#   - Undefined-variable references that only fire in specific method paths
#   - Refactor breakage that the `info complete` static check can't catch
#   - The new helpers (_safe_hex32, _zero_a53_marker_region, etc.)
#
# Does NOT catch (delegated to live hardware run):
#   - Real DAP timing, AXI behavior, A53 register-write side effects
#   - The actual M1/M2/M4 payload execution semantics
#
# Run before every commit that touches openocd/dump-bootrom.tcl or its
# helpers (lib/release-recipes.tcl, lib/dump-memory.tcl, etc.). Exits 0
# on clean run, 1 if any dispatcher branch fails.
#
# Also exercises tools/bootrom.py against every historical timestamp in
# dumps/, so renderer changes that crash on edge-case sidecars get caught.

set -euo pipefail

cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------------
# Part 1: tclsh smoketest — source dump-bootrom.tcl under stubs, exercise
#          every method dispatcher branch.
# ---------------------------------------------------------------------------

STUB_TCL=$(mktemp /tmp/dump-bootrom-stubs.XXXXXX.tcl)
trap "rm -f $STUB_TCL" EXIT

cat > "$STUB_TCL" <<'STUB_EOF'
# Minimal OpenOCD stubs for end-to-end dump-bootrom.tcl smoketest.
# `echo` is a real OpenOCD command; lib/enum-helpers.tcl's say uses it.

proc exec {args} { return "" }
proc echo {line} { puts $line }
proc init {} {}
proc shutdown {} {}
proc halt {} {}
proc resume {} {}
proc reg {args} {
    if {[llength $args] == 1} { return "pc (/64): 0xfffc0000" }
    return ""
}
proc targets {args} { return "" }
proc write_memory {addr width data} { return "" }
proc read_memory {addr width nwords {args ""}} {
    set out [list]
    for {set i 0} {$i < $nwords} {incr i} { lappend out 0xDEADBEEF }
    return $out
}
# Target proxies: respond to the curstate/was_examined/arp_examine calls
# dump-bootrom.tcl makes during release/halt sequences.
proc uscale.a53.0 {args} {
    if {[lindex $args 0] eq "curstate"} { return "halted" }
    if {[lindex $args 0] eq "was_examined"} { return 1 }
    return ""
}
proc uscale.axi {args} { return "" }
proc uscale.a53.1 {args} { return "" }
proc uscale.a53.2 {args} { return "" }
proc uscale.a53.3 {args} { return "" }
proc uscale.dap {args} { return "" }

set ::methods [list baseline csudma a53 loader r5 aes all]
set ::tmpdir /tmp/dump-bootrom-smoketest-dumps
file mkdir $::tmpdir

set ::passed 0
set ::failed 0
foreach m $::methods {
    puts "##### method: $m #####"
    if {[catch {
        # Clear per-source state so re-source is clean
        foreach v [list ::REPORT_FH ::_ts ::_dumps_dir ::_log_path \
                        ::_script_dir ::_repo_root ::_which \
                        ::_t_script_start] {
            if {[info exists $v]} { unset $v }
        }
        set ::BOOTROM_METHOD $m
        set ::DUMPS_DIR_OVERRIDE $::tmpdir
        set ::TS_OVERRIDE "TEST-$m"
        source openocd/dump-bootrom.tcl
        puts ">>> $m: OK"
        incr ::passed
    } err]} {
        puts ">>> $m: FAIL - $err"
        puts $::errorInfo
        incr ::failed
    }
}

# Direct exercise of the new TCL helpers (would be silent passes during
# normal source runs; explicit tests here so a regression in the helpers
# is loud).
puts ""
puts "##### helper checks #####"
set ok 1
if {[_safe_hex32 ERR] ne "0xDEADBEEF"} { puts "FAIL: _safe_hex32 ERR"; set ok 0 }
if {[_safe_hex32 0x42] ne "0x00000042"} { puts "FAIL: _safe_hex32 0x42"; set ok 0 }
if {[_safe_hex32 100] ne "0x00000064"} { puts "FAIL: _safe_hex32 100"; set ok 0 }
if {[catch { _zero_a53_marker_region } e]} { puts "FAIL: _zero_a53_marker_region - $e"; set ok 0 }
if {$ok} { puts ">>> helpers: OK" } else { incr ::failed }

puts ""
puts "============================================================"
puts "dump-bootrom.tcl smoketest: $::passed/[llength $::methods] dispatcher OK, $::failed failed"
puts "============================================================"
exit $::failed
STUB_EOF

echo "=== Part 1: dump-bootrom.tcl dispatcher smoketest ==="
if ! /usr/bin/tclsh "$STUB_TCL" 2>&1 | grep -E "^>>>|^##### method:|smoketest:|^FAIL"; then
    echo "FAIL: tcl smoketest exited non-zero"
    exit 1
fi

# Clean up the stub-run artifacts
rm -rf /tmp/dump-bootrom-smoketest-dumps

# ---------------------------------------------------------------------------
# Part 2: bootrom.py renderer smoketest — run analyzer against every
#          historical timestamp in dumps/ to catch renderer regressions.
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 2: bootrom.py renderer against all historical timestamps ==="
if ! ls dumps/bootrom-*.json >/dev/null 2>&1; then
    echo "  no historical artifacts in dumps/ — skipping"
    exit 0
fi

py_pass=0
py_fail=0
# Only iterate timestamps that have a genuine BootROM *extraction* artifact
# (methods csudma/a53/loader/r5/aes, or a bare bootrom-<ts> dump). The
# dump-bootrom.tcl dispatcher is also reused as a generic payload runner for
# Phase-7 PMU-IPI probes (bootrom-via-pmu-ipi-*, -r5-wakeup-*, etc.) whose
# .bin is not an analyzable ROM image — bootrom.py rightly rejects those, so
# they must not be fed to the renderer regression check.
ts_re='[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}'
for ts in $(ls dumps/bootrom-*.json \
        | grep -E "bootrom-via-(csudma|a53|loader|r5|aes)-${ts_re}\.json$|/bootrom-${ts_re}\.json$" \
        | grep -oE "$ts_re" | sort -u); do
    if python3 tools/bootrom.py --timestamp "$ts" >/dev/null 2>&1; then
        py_pass=$((py_pass+1))
    else
        py_fail=$((py_fail+1))
        echo "  FAIL: $ts"
    fi
done
echo "  $py_pass passed, $py_fail failed"

if [ $py_fail -ne 0 ]; then
    echo "FAIL: bootrom.py crashed on $py_fail historical timestamp(s)"
    exit 1
fi

echo ""
echo "PASS: dump-bootrom.tcl + bootrom.py all green"
exit 0
