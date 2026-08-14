# mock-openocd.tcl — deterministic stubs for OpenOCD commands used by
# enumerate.tcl. Lets the full enumerate flow run under plain tclsh with
# bit-stable output.
#
# Usage (typically from tools/run-enumerate-mock.sh):
#   1. Generate seed file from a golden raw JSON:
#        python3 tools/generate-mock-seed.py <raw.json> -o /tmp/seed.tcl
#   2. tclsh with:
#        source /tmp/seed.tcl                  ;# populates ::MOCK_*
#        source openocd/lib/mock-openocd.tcl   ;# stubs OpenOCD commands
#        source openocd/enumerate.tcl          ;# the real script
#
# Stubs every OpenOCD-specific command enumerate.tcl uses. Address-based
# reads look up the seed; everything else returns sane defaults.

# Default-zero behaviour for unseeded addresses. Set to 1 if you want the
# mock to abort on any unknown address read (useful for finding gaps).
if {![info exists ::MOCK_STRICT]} {
    set ::MOCK_STRICT 0
}


# Look up a register value from the seed. Returns a HEX STRING that
# matches the shape of real OpenOCD's read_memory output. For unseeded
# addresses: in strict mode, raise an error (so test runs surface gaps
# instead of papering over them with 0); in permissive mode (default),
# return "0x00000000" as the convention used elsewhere by safe_rd.
proc _mock_lookup_addr {addr} {
    set addr_int [expr {int($addr)}]
    set addr_hex [format "0x%08X" $addr_int]
    if {[dict exists $::MOCK_REGS $addr_hex]} {
        set v [dict get $::MOCK_REGS $addr_hex]
        return [format "0x%08X" $v]
    }
    if {$::MOCK_STRICT} {
        error "mock: unseeded address $addr_hex (set ::MOCK_STRICT 0 to allow default-fill)"
    }
    # Unseeded default: OpenOCD's AXI mem-AP returns 0xDEADBEEF when reading
    # unmapped regions on ZynqMP (OCM holes, gated peripherals). Match that
    # so the mock's behaviour for unknown addresses lines up with live silicon.
    return "0xDEADBEEF"
}


# Stubs the script's safe_rd helper (defined in enum-helpers.tcl).
# Since enum-helpers is sourced from enumerate.tcl AFTER mock-openocd
# is sourced, safe_rd will be re-defined to the helper version unless
# we redefine again later. The trick: replace `read_memory` instead,
# which both safe_rd and dump_block use under the hood.
proc read_memory {addr width nwords {args ""}} {
    # Return values as HEX STRINGS to match real OpenOCD's read_memory output
    # on this build. This is what bit it us in dump_reg_qemu — the regex-based
    # type check failed silently when OpenOCD handed back "0x..." strings.
    # Keeping the mock honest forces enumerate.tcl + helpers to handle hex.
    set addr_int [expr {int($addr)}]
    set addr_hex [format "0x%08X" $addr_int]
    if {[dict exists $::MOCK_MEM $addr_hex]} {
        set block [dict get $::MOCK_MEM $addr_hex]
        set have [llength $block]
        # Normalize seeded values to hex strings.
        set result [list]
        foreach v $block {
            if {[string match "0x*" $v] || [string match "0X*" $v]} {
                lappend result $v
            } else {
                lappend result [format "0x%08X" [expr {int($v)}]]
            }
        }
        if {$have >= $nwords} {
            return [lrange $result 0 [expr {$nwords - 1}]]
        }
        for {set i $have} {$i < $nwords} {incr i} {
            set wa [expr {$addr_int + $i * 4}]
            lappend result [_mock_lookup_addr $wa]
        }
        return $result
    }
    # No block seeded — return nwords entries, each looked up per-address.
    set result [list]
    for {set i 0} {$i < $nwords} {incr i} {
        set wa [expr {$addr_int + $i * 4}]
        lappend result [_mock_lookup_addr $wa]
    }
    return $result
}


# write_memory: track writes but don't validate (returns success).
# Some scripts read-back after writing — for those, we update ::MOCK_REGS
# so subsequent reads see the value just written.
proc write_memory {addr width values {args ""}} {
    set addr_int [expr {int($addr)}]
    set i 0
    foreach v $values {
        set wa [expr {$addr_int + $i * 4}]
        set wa_hex [format "0x%08X" $wa]
        dict set ::MOCK_REGS $wa_hex [expr {int($v)}]
        incr i
    }
    return ""
}


# OpenOCD's `capture` runs a body and returns its stdout output. Our
# stub just evaluates the body and returns its result. Used for capturing
# `dap info N` output — handled by the dap stub below.
proc capture {body} {
    return [uplevel 1 $body]
}


# Target / DAP stubs. The real script uses `uscale.dap`, `uscale.axi`,
# `uscale.a53.0`, `uscale.ps`, `uscale.tap`. We map all the dap subcommand
# variants to a single dispatcher that returns the seeded AP info when
# the subcommand is `info N`.
proc uscale.dap {args} {
    if {[llength $args] >= 2 && [lindex $args 0] eq "info"} {
        set ap_num [lindex $args 1]
        if {[info exists ::MOCK_AP_INFO] && [dict exists $::MOCK_AP_INFO $ap_num]} {
            return [dict get $::MOCK_AP_INFO $ap_num]
        }
        return "(mock: no AP $ap_num seed)"
    }
    if {[llength $args] >= 1 && [lindex $args 0] eq "dpreg"} {
        # DP register read/write — return 0; used for sticky-error clearing
        return 0
    }
    return ""
}

proc uscale.axi {args} { return 0 }
proc uscale.a53.0 {args} {
    if {[info exists ::MOCK_A53] && [llength $args] >= 1} {
        set sub [lindex $args 0]
        if {$sub eq "curstate" && [dict exists $::MOCK_A53 state]} {
            return [dict get $::MOCK_A53 state]
        }
    }
    return "halted"
}
# Cores 1-3: on the idle baseline only core 0 is released; the rest stay in
# reset, so the DAP can't examine them. Model that — arp_examine raises, which
# enumerate.tcl §8 classifies as invasive_debug=unreachable for those cores.
proc _mock_a53_off {args} {
    if {[llength $args] >= 1 && [lindex $args 0] eq "arp_examine"} {
        error "mock: core in reset (not examinable)"
    }
    if {[llength $args] >= 1 && [lindex $args 0] eq "curstate"} { return "unknown" }
    return ""
}
proc uscale.a53.1 {args} { return [_mock_a53_off {*}$args] }
proc uscale.a53.2 {args} { return [_mock_a53_off {*}$args] }
proc uscale.a53.3 {args} { return [_mock_a53_off {*}$args] }
proc uscale.ps {args} { return "" }
proc uscale.tap {args} { return "" }

# APB-debug mem-AP (AP1) used by the EDPCSR / debug-gate probe. The probe reads
# via `uscale.dbg read_memory ADDR 32 1`. Offsets are DBGBASE-relative (& 0xFFF).
# Defaults represent the idle baseline: EDPCSR=0xFFFFFFFF (no PC sampling / no
# firmware running), EDPRSR=powered. Override per-register via ::MOCK_DBG.
proc uscale.dbg {args} {
    if {[llength $args] >= 2 && [lindex $args 0] eq "read_memory"} {
        set off [expr {[lindex $args 1] & 0xFFF}]
        if {[info exists ::MOCK_DBG] && [dict exists $::MOCK_DBG $off]} {
            return [list [dict get $::MOCK_DBG $off]]
        }
        if {$off == 0x0A0 || $off == 0x0AC} { return [list 0xFFFFFFFF] }
        if {$off == 0x314} { return [list 0] }
        return [list 0]
    }
    return 0
}

# Generic OpenOCD command stubs (target enumeration, JTAG ops, etc.)
# `target create ...` is a no-op here (uscale.dbg is pre-defined above, so
# dbg_ap_init never calls it; stub anyway for safety).
proc target {args} { return "" }
proc targets {args} { return "" }
proc halt {args} { return 0 }
proc resume {args} { return 0 }
# `echo` is an OpenOCD-provided builtin used by the script's `say` helper
# to mirror lines to stdout. Plain tclsh doesn't have it.
if {[info commands echo] eq ""} {
    proc echo {args} {
        puts [join $args " "]
    }
}
proc reg {args} {
    # Used in §8 for A53 register dump. Real OpenOCD does NOT raise an error
    # for unknown register names — it returns a literal "register NAME not
    # found in current target" string, which the script's regex then fails
    # to match for hex (correctly displaying the raw line). Match that here
    # so the produced markdown is byte-stable against a live capture.
    if {[llength $args] >= 1} {
        set name [lindex $args 0]
        if {[info exists ::MOCK_A53] && [dict exists $::MOCK_A53 $name]} {
            return "$name (: [dict get $::MOCK_A53 $name])"
        }
        return "register $name not found in current target"
    }
    return ""
}
proc jtag {args} { return "" }
proc after {args} { return 0 }
proc sleep {args} { return 0 }
proc shutdown {args} { return 0 }


# Helper so callers can quickly verify the seed is loaded.
proc mock_summary {} {
    set n_regs 0
    if {[info exists ::MOCK_REGS]} { set n_regs [dict size $::MOCK_REGS] }
    set n_ap 0
    if {[info exists ::MOCK_AP_INFO]} { set n_ap [dict size $::MOCK_AP_INFO] }
    return "mock loaded: $n_regs registers, $n_ap AP-info entries"
}
