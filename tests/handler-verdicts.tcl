# handler-verdicts.tcl — unit tests for dump-bootrom.tcl handler verdict logic.
#
# These tests exercise the post-payload Tcl logic that translates OCM
# readback into VERDICT strings. They stub the chip-facing primitives
# (safe_rd, safe_wr, halt, etc.) with table-driven canned values and
# assert that the verdict text matches expectation.
#
# This catches regressions in:
#   - threshold comparisons (e.g., target_i == bypass_val)
#   - per-stage branch coverage (stage_marker = 0/1/2/0xFF)
#   - integer-conversion / hex-vs-int handling
#   - baseline lookup against board-baselines.tcl
#
# Run via: tools/handler-verdict-tests.sh

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------
set ::TESTS_RUN 0
set ::TESTS_PASSED 0
set ::TESTS_FAILED 0
set ::OUTPUT_BUF ""

# Stub the say command to capture output instead of writing to console/log.
proc say {args} {
    if {[llength $args] == 0} {
        append ::OUTPUT_BUF "\n"
    } else {
        append ::OUTPUT_BUF "[lindex $args 0]\n"
    }
}

# Table-driven safe_rd stub. Tests set up ::MOCK_READS dict before invoking.
set ::MOCK_READS [dict create]
proc safe_rd {addr} {
    set key [format "0x%08X" [expr {$addr & 0xFFFFFFFF}]]
    if {[dict exists $::MOCK_READS $key]} {
        return [dict get $::MOCK_READS $key]
    }
    return "ERR"
}
proc safe_wr {args} { return 0 }
proc targets {args} { return "" }
proc after {args} { return 0 }
proc halt {args} { return 0 }
proc reset_a53_core0 {args} { return 0 }
proc release_a53_core0 {args} { return 1 }
proc clear_dp_sticky {args} { return 0 }
proc uscale.a53.0 {args} { return "halted" }
proc uscale.axi {args} { return 0 }
proc uscale.dap {args} { return 0 }
proc write_memory {args} { return 0 }
proc read_memory {args} { return [list 0 0 0 0 0 0 0 0] }
proc reg {args} { return "0x12345678" }
proc _read_reg_hex {args} { return "0x12345678" }
proc clock {args} { return 0 }
proc hex32 {v} { return [format "0x%08X" [expr {$v & 0xFFFFFFFF}]] }
proc _fmt_ms {ms} { return "${ms}ms" }
proc _check_payload_staleness {args} {}
proc _inter_method_recovery {} { return 1 }
proc _method_a53_common {args} { return 0 }
proc write_dump_metadata {args} { return 0 }
proc _zero_a53_marker_region {} { return 0 }
proc _write_zero_verified {args} { return 1 }
proc _poll_done_marker {ms} { return [dict create met 1 ms 100] }
proc dump_memory {args} { return [dict create bytes_written 16384 chunks_total 4 chunks_ok 4 chunks_failed 0 total_ms 100] }
proc _safe_hex32 {v} { return [format "0x%08X" [expr {[catch {expr {int($v)}} r] ? 0 : $r}]] }
proc _snapshot_csu_security {} { return [dict create csu_status "0x0" csu_ctrl "0x0"] }

proc expect_in_output {needle test_name} {
    incr ::TESTS_RUN
    if {[string first $needle $::OUTPUT_BUF] >= 0} {
        incr ::TESTS_PASSED
        puts "  PASS: $test_name"
    } else {
        incr ::TESTS_FAILED
        puts "  FAIL: $test_name"
        puts "    expected to contain: $needle"
        puts "    actual output (first 500 chars):"
        puts "      [string range $::OUTPUT_BUF 0 500]"
    }
}

proc reset_test_state {} {
    set ::OUTPUT_BUF ""
    set ::MOCK_READS [dict create]
}

# ---------------------------------------------------------------------------
# Load library under test (relative to repo root)
# ---------------------------------------------------------------------------
set _here [file dirname [info script]]
set _repo_root [file dirname $_here]
set ::_repo_root $_repo_root

source [file join $_repo_root openocd lib board-baselines.tcl]

# Stub out logging-related globals so dump-bootrom.tcl doesn't try to
# open a log file or run python tools when sourced.
set ::REPORT_FH ""

# Source the helper procs from dump-bootrom.tcl without triggering the main
# dispatch. We do this by reading the file up to but not including the
# "Main dispatch" section.
set bootrom_path [file join $_repo_root openocd dump-bootrom.tcl]
set fh [open $bootrom_path r]
set body [read $fh]
close $fh
# Cut off at the "Main dispatch" comment header
set cutoff [string first "# Main dispatch" $body]
if {$cutoff < 0} {
    puts stderr "ERROR: couldn't find '# Main dispatch' marker"
    exit 2
}
set procs_only [string range $body 0 $cutoff]
# Strip the auto-source lines (lib enum-helpers, dump-memory, etc.)
# since they reference $_script_dir which isn't set in test context.
set procs_only [regsub -all -line {^source \[file join.*$} $procs_only "# (source removed for testing)"]
# Eval the procs into our test interpreter
if {[catch {eval $procs_only} err]} {
    puts stderr "ERROR sourcing handler procs: $err"
    puts stderr $::errorInfo
    exit 2
}

# Source the research lib files (handlers moved out of dump-bootrom.tcl
# during audit B5 split). These need to be sourced AFTER the helper
# procs (which are in dump-bootrom.tcl proper) are defined.
foreach lib {research-pmu} {
    set lib_path [file join $_repo_root openocd lib ${lib}.tcl]
    if {[file exists $lib_path]} {
        if {[catch {source $lib_path} lib_err]} {
            puts stderr "ERROR sourcing $lib: $lib_err"
            exit 2
        }
    }
}

# Override helpers AFTER sourcing — the file defines real ones that we
# need to replace with no-ops since they try to execute payloads.
proc _method_a53_common {args} { return 0 }
proc _inter_method_recovery {} { return 1 }
proc _check_payload_staleness {args} {}
proc _read_reg_hex {args} { return "0x12345678" }
proc _zero_a53_marker_region {} { return 0 }
proc _write_zero_verified {args} { return 1 }
proc _poll_done_marker {ms} { return [dict create met 1 ms 100] }
proc release_a53_core0 {args} { return 1 }
proc reset_a53_core0 {args} { return 0 }
proc write_dump_metadata {args} { return 0 }
proc dump_memory {args} { return [dict create bytes_written 16384 chunks_total 4 chunks_ok 4 chunks_failed 0 total_ms 100] }
proc _snapshot_csu_security {} { return [dict create csu_status "0x0" csu_ctrl "0x0"] }

puts "Running handler-verdict tests..."

# NOTE: the csu-probe verdict tests (formerly tests 1-5) were removed
# 2026-06-08 along with research-csu.tcl (retracted-findings probe method).
# The baseline-lookup and _safe_int helper tests below remain — they cover
# generic dump-bootrom helpers still used by the live methods.

# ---------------------------------------------------------------------------
# Test: baseline lookup helpers
# ---------------------------------------------------------------------------
incr ::TESTS_RUN
if {[::baseline::get FFCAF000] == 0x02DDB2CB} {
    incr ::TESTS_PASSED
    puts "  PASS: baseline::get returns 0x02DDB2CB for FFCAF000"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: baseline::get FFCAF000 returned [::baseline::get FFCAF000]"
}

incr ::TESTS_RUN
if {[::baseline::get 0xFFCA0038] == 0x0000003F} {
    incr ::TESTS_PASSED
    puts "  PASS: baseline::get accepts 0x prefix + returns 0x3F for JTAG_SEC"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: baseline::get 0xFFCA0038 returned [::baseline::get 0xFFCA0038]"
}

incr ::TESTS_RUN
if {[::baseline::get FFCA003C] == 0x000000FF} {
    incr ::TESTS_PASSED
    puts "  PASS: baseline::get returns 0xFF for JTAG_DAP_CFG (post-C1 layout)"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: baseline::get FFCA003C returned [::baseline::get FFCA003C]"
}

# ---------------------------------------------------------------------------
# Test 7: _safe_int helper
# ---------------------------------------------------------------------------
incr ::TESTS_RUN
if {[_safe_int "0xDEADBEEF"] == 0xDEADBEEF} {
    incr ::TESTS_PASSED
    puts "  PASS: _safe_int parses hex string"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: _safe_int 0xDEADBEEF returned [_safe_int 0xDEADBEEF]"
}

incr ::TESTS_RUN
if {[_safe_int "ERR"] == 0} {
    incr ::TESTS_PASSED
    puts "  PASS: _safe_int returns default 0 for ERR"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: _safe_int ERR returned [_safe_int ERR]"
}

incr ::TESTS_RUN
if {[_safe_int "ERR" -1] == -1} {
    incr ::TESTS_PASSED
    puts "  PASS: _safe_int returns supplied default for ERR"
} else {
    incr ::TESTS_FAILED
    puts "  FAIL: _safe_int ERR -1 returned [_safe_int ERR -1]"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts ""
puts "Tests run:    $::TESTS_RUN"
puts "Tests passed: $::TESTS_PASSED"
puts "Tests failed: $::TESTS_FAILED"

if {$::TESTS_FAILED > 0} {
    exit 1
}
exit 0
