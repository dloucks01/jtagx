# cortexm-access-check.tcl — Cortex-M sibling of jtag-access-check.tcl: is the AHB-AP actually
# reachable on this MCU, or is debug gated (nRF APPROTECT / STM32 RDP / SF2 debug-lock)?
#
# The gate before dumping and the VERIFY step of the guided reopen→verify loop (jtagx.unlock): a
# lever runs (nrf52-recover.tcl / stm32-rdp-downgrade.tcl), then THIS re-reads the verdict so the
# engine can mark the lock DEFEATED / RESISTED. Non-destructive — only reads.
#
# Run after a per-family cfg has set up interface+transport+target, e.g.:
#   openocd -f openocd/cortexm-nrf52.cfg -c "init; source openocd/cortexm-access-check.tcl; shutdown"
#
# Verdict logic: a locked M-class debug port answers IDCODE/DPACC but the AHB-AP (MEM-AP) either
# reads 0 for its IDR or faults every memory access. We probe the AHB-AP IDR + try one benign
# memory read; both must succeed for OPEN.

proc cm {s} { puts $s }
proc cm_hdr {s} { puts ""; puts "================================================================"; puts " $s"; puts "================================================================" }

proc cm_first_dap {} {
    if {[catch {dap names} d]} { return "" }
    return [lindex $d 0]
}

# AHB-AP is AP 0 on all these parts. Read its IDR (bank 0xF, reg 0x0C -> apreg 0 0xFC). Nonzero = present.
proc cm_ahb_idr {dap} {
    if {$dap eq ""} { return 0 }
    if {[catch {$dap apreg 0 0xFC} v]} { return 0 }
    return $v
}

# Try one benign 32-bit read (the ARMv6/7-M ROM table base, always 0xE00FF000). OK => mem-AP live.
proc cm_can_read {} {
    if {[catch {read_memory 0xE00FF000 32 1} v]} { return 0 }
    return 1
}

cm_hdr "CORTEX-M ACCESS CHECK"
set dap [cm_first_dap]
set idr [cm_ahb_idr $dap]
set canread [cm_can_read]
set halted 0
if {![catch {halt} _]} { set halted 1 ; catch {resume} _ }

set opened [expr {($idr != 0 && $canread) ? 1 : 0}]
cm [format "  AHB-AP IDR       = 0x%08X" $idr]
cm "  ROM-table read   = [expr {$canread ? {OK} : {DENIED}}]"
cm "  core halt        = [expr {$halted ? {OK} : {refused}}]"
cm_hdr [format " ACCESS VERDICT: %s" [expr {$opened ? {OPEN} : {LOCKED}}]]
if {$opened} {
    cm "  Cortex-M AHB-AP responds — halt + eNVM/eSRAM/flash memory reads are available."
    cm "  next: cortexm-dump.tcl (or the profile's dump.flash) to extract."
} else {
    cm "  DAP answers but the AHB-AP is gated (APPROTECT / RDP>0 / SF2 debug-lock)."
    cm "  next: run the recovery lever (nrf52-recover.tcl / stm32-rdp-downgrade.tcl), then re-check."
}
