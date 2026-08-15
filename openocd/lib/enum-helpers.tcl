# Helpers for the enumeration script. Sourced from enumerate.tcl.

# Global output channel; opened by enumerate.tcl
# All "say" output goes to BOTH stdout and the report file.
proc say {line} {
    global REPORT_FH
    echo $line
    if {[info exists REPORT_FH]} {
        puts $REPORT_FH $line
        flush $REPORT_FH
    }
}

proc say_h1 {t} { say ""; say "# $t" }
proc say_h2 {t} { say ""; say "## $t" }
proc say_kv {key value {comment ""}} {
    if {$comment ne ""} {
        say [format "- **%s**: \`%s\`  _(%s)_" $key $value $comment]
    } else {
        say [format "- **%s**: \`%s\`" $key $value]
    }
}

proc hex32 {v} {
    # Tolerate non-integer (e.g. "ERR") inputs so callers don't crash
    if {![string is integer -strict $v]} { return $v }
    return [format "0x%08x" $v]
}

# Count set bits in an integer. Returns 0 for non-integer (e.g. "ERR").
proc popcount {v} {
    if {![string is integer -strict $v]} { return 0 }
    set n 0
    while {$v != 0} {
        incr n [expr {$v & 1}]
        set v [expr {$v >> 1}]
    }
    return $n
}

# Aggressively clear DP sticky errors. Call this between major sections
# to keep one bad address (DDR not init, blocked peripheral) from
# poisoning later reads.
proc clear_dp_sticky {} {
    for {set _i 0} {$_i < 3} {incr _i} {
        catch { uscale.dap dpreg 0 0x1e } _
        after 10
    }
}

# Read a contiguous block as a list of 32-bit words. Returns word list
# or "ERR" on failure. Clears DP sticky on failure.
proc safe_read_block {addr nwords} {
    if {[catch {read_memory $addr 32 $nwords} v]} {
        catch { uscale.dap dpreg 0 0x1e } _
        return "ERR"
    }
    return $v
}

# Convert a list of 32-bit words to a byte string (little-endian).
# Useful for searching for ASCII / magic patterns.
proc bytes_from_words {words} {
    set b ""
    foreach w $words {
        # Tcl integers may be large; mask each byte separately
        set b0 [expr {$w & 0xFF}]
        set b1 [expr {($w >> 8) & 0xFF}]
        set b2 [expr {($w >> 16) & 0xFF}]
        set b3 [expr {($w >> 24) & 0xFF}]
        append b [format "%c%c%c%c" $b0 $b1 $b2 $b3]
    }
    return $b
}

# Search a memory range for a literal string. Returns the absolute
# address where the match starts, or "" if not found / read failed.
proc find_signature_string {start size_bytes pattern} {
    set nwords [expr {($size_bytes + 3) / 4}]
    set words [safe_read_block $start $nwords]
    if {$words eq "ERR"} { return "" }
    set bytes [bytes_from_words $words]
    set idx [string first $pattern $bytes]
    if {$idx >= 0} {
        return [expr {$start + $idx}]
    }
    return ""
}

# Memory read via active target. Returns single 32-bit value or "ERR".
# Clears DP sticky errors after a failed read so subsequent reads aren't poisoned.
proc safe_rd {addr} {
    if {[catch {read_memory $addr 32 1} v]} {
        # Clear DP sticky-error state so the next read can succeed
        catch { uscale.dap dpreg 0 0x1e } _
        return "ERR"
    }
    return [lindex $v 0]
}

# Memory write via active target.
proc safe_wr {addr val} {
    if {[catch {write_memory $addr 32 [list $val]} e]} {
        return "ERR: $e"
    }
    return "ok"
}

# ---------------------------------------------------------------------------
# Non-invasive APU debug primitives (EDPCSR PC-sampling + debug-gate check).
#
# The A53 external-debug block is reachable over the DAP's APB-AP (AP1) at a
# per-core DBGBASE. EDPCSR (DBGBASE+0xA0) returns a *running* core's PC without
# halting it — so it works even when invasive debug (halt) is gated by secure
# firmware. We use it to (a) detect whether code is executing and (b) sample
# the live PC for characterization.
# ---------------------------------------------------------------------------

# DBGBASE (APB-AP address) for A53 core N. Per Xilinx xilinx_zynqmp.cfg:
# core0=0x80410000, core1=0x80510000, core2=0x80610000, core3=0x80710000.
proc a53_dbgbase {core} {
    return [expr {0x80410000 + $core * 0x100000}]
}

# Ensure the APB-debug mem-AP target (uscale.dbg, AP1) exists. Real OpenOCD
# creates it with `target create`; the offline mock pre-defines uscale.dbg.
# Returns 1 if uscale.dbg is usable, else 0.
proc dbg_ap_init {} {
    if {[llength [info commands uscale.dbg]] > 0} { return 1 }
    catch { target create uscale.dbg mem_ap -dap uscale.dap -ap-num 1 } _
    return [expr {[llength [info commands uscale.dbg]] > 0 ? 1 : 0}]
}

# Read one 32-bit APB-debug register via the AP. Returns value or "ERR".
proc dbg_rd {addr} {
    if {[catch { uscale.dbg read_memory $addr 32 1 } v]} {
        catch { uscale.dap dpreg 0 0x1e } _
        return "ERR"
    }
    return [lindex $v 0]
}

# Non-invasively probe an A53 core's debug status + sample its PC via EDPCSR.
# Returns a dict: powered(true/false/ERR) edprsr edscr dbgauth pc_lo pc_hi
# samples(list) sampling_ok(0/1). Does NOT halt the core.
#
# dbgauth = DBGAUTHSTATUS_EL1 (external view at DBGBASE+0xFB8, Arm DDI0487):
# the CORE's own read-back of the four debug-authentication signals
# (NSID/NSNID/SID/SNID = DBGEN/NIDEN/SPIDEN/SPNIDEN). This corroborates the
# CSU-side JTAG_DAP_CFG gate from the core's perspective — if the two disagree,
# something between the CSU and the core is overriding the gate.
proc edpcsr_probe {core {nsamples 6}} {
    set base [a53_dbgbase $core]
    set res [dict create powered ERR edprsr ERR edscr ERR dbgauth ERR \
                 pc_lo ERR pc_hi ERR samples [list] sampling_ok 0]
    if {![dbg_ap_init]} { return $res }
    set edprsr  [dbg_rd [expr {$base + 0x314}]]
    set edscr   [dbg_rd [expr {$base + 0x088}]]
    set dbgauth [dbg_rd [expr {$base + 0xFB8}]]
    dict set res edprsr  $edprsr
    dict set res edscr   $edscr
    dict set res dbgauth $dbgauth
    if {$edprsr ne "ERR"} {
        if {[expr {$edprsr & 1}]} { dict set res powered true } else { dict set res powered false }
    }
    set samples [list]
    set ok 0
    for {set i 0} {$i < $nsamples} {incr i} {
        set lo [dbg_rd [expr {$base + 0x0A0}]]
        lappend samples [hex32 $lo]
        if {$lo ne "ERR" && $lo != 0xFFFFFFFF} { set ok 1 }
        after 20
    }
    dict set res samples $samples
    dict set res pc_lo [lindex $samples end]
    dict set res pc_hi [hex32 [dbg_rd [expr {$base + 0x0AC}]]]
    dict set res sampling_ok $ok
    return $res
}

# Read a 32-bit register and report it with a label and optional bit decode.
# bit_decode is a list of {bit_high bit_low name [meaning]} or {bit name [meaning]} entries.
proc dump_reg {label addr {bit_decode {}}} {
    set v [safe_rd $addr]
    if {$v eq "ERR"} {
        say_kv $label "[hex32 $addr] -> READ FAILED"
        return
    }
    say_kv $label "[hex32 $addr] = [hex32 $v]"
    if {[llength $bit_decode] > 0} {
        foreach entry $bit_decode {
            set len [llength $entry]
            if {$len >= 3 && [string is integer [lindex $entry 0]] && [string is integer [lindex $entry 1]]} {
                # {hi lo name [meaning]}
                set hi [lindex $entry 0]
                set lo [lindex $entry 1]
                set name [lindex $entry 2]
                set meaning [expr {$len >= 4 ? [lindex $entry 3] : ""}]
                set width [expr {$hi - $lo + 1}]
                set mask [expr {(1 << $width) - 1}]
                set field [expr {($v >> $lo) & $mask}]
                if {$width == 1} {
                    say [format "    \[%2d\]     %-30s = %d %s" $lo $name $field [expr {$meaning ne "" ? "($meaning)" : ""}]]
                } else {
                    say [format "    \[%2d:%2d\] %-30s = 0x%x %s" $hi $lo $name $field [expr {$meaning ne "" ? "($meaning)" : ""}]]
                }
            } elseif {$len >= 2 && [string is integer [lindex $entry 0]]} {
                # {bit name [meaning]}
                set bit [lindex $entry 0]
                set name [lindex $entry 1]
                set meaning [expr {$len >= 3 ? [lindex $entry 2] : ""}]
                set f [expr {($v >> $bit) & 1}]
                say [format "    \[%2d\]     %-30s = %d %s" $bit $name $f [expr {$meaning ne "" ? "($meaning)" : ""}]]
            }
        }
    }
    return $v
}

# Read a contiguous block as a list. Each row prints 4 words.
proc dump_block {label addr nwords} {
    say ""
    say "**$label** ([hex32 $addr], $nwords words):"
    say "\`\`\`"
    if {[catch {read_memory $addr 32 $nwords} vals]} {
        say "  READ FAILED: $vals"
        say "\`\`\`"
        return
    }
    set i 0
    set line ""
    foreach v $vals {
        if {[expr {$i % 4}] == 0} {
            if {$line ne ""} { say $line }
            set line [format "  %s: " [hex32 [expr {$addr + $i*4}]]]
        }
        append line [format " %08x" $v]
        incr i
    }
    if {$line ne ""} { say $line }
    say "\`\`\`"
}

