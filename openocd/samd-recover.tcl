# samd-recover.tcl — Microchip SAM D5x/E5x debug-protection recovery: DSU chip-erase (CE) clears the
# NVMCTRL security bit (DSU.STATUSB.PROT) and RE-OPENS the SWD debug port. Debug-mailbox recovery via
# the DSU, NOT a glitch — the DSU is reachable even when the AHB-AP is gated.
#
# ⚠ DESTRUCTIVE: chip-erase wipes all flash. You get DEBUG ACCESS + a blank part, NOT the protected
#   firmware. For the contents you need a fault-injection read-out bypass (deferred).
#
# Mechanism (SAM D5x/E5x DSU @0x41002000, external address space):
#   DSU.CTRL   (0x41002000, 8-bit): bit4 CE = Chip-Erase (write 1 to start)
#   DSU.STATUSA(0x41002001, 8-bit): bit0 DONE
#   DSU.STATUSB(0x41002002, 8-bit): bit0 PROT (1 = debug protected)
# The OpenOCD atsame5 driver exposes `atsame5 chip-erase`; we prefer it and fall back to a raw CE write.
#
#   openocd -f openocd/cortexm-samd5x.cfg -c "init; source openocd/samd-recover.tcl; shutdown"

proc sr {s} { puts $s }
proc sr_rd8 {a} { if {[catch {read_memory $a 8 1} v]} { return -1 } ; return [lindex $v 0] }

sr ""
sr " SAM D5x/E5x DSU chip-erase recovery (clears NVMCTRL debug protection)"

set prot [sr_rd8 0x41002002]
if {$prot >= 0} { sr [format "    DSU.STATUSB.PROT (before) = %d" [expr {$prot & 1}]] }

set ok 0
# Preferred: the driver command (handles the DSU handshake + reset).
if {![catch {atsame5 chip-erase} _]} {
    set ok 1
} else {
    # Fallback: raw DSU.CTRL.CE, then poll DSU.STATUSA.DONE.
    if {![catch {mww 0x41002000 0x10} _]} {
        for {set i 0} {$i < 200} {incr i} {
            after 10
            set sa [sr_rd8 0x41002001]
            if {$sa >= 0 && ($sa & 0x01)} { set ok 1 ; break }
        }
    }
}
if {!$ok} { sr "    -> chip-erase FAILED: DSU did not complete (debug still locked)"; return }

catch { reset init } _
set prot2 [sr_rd8 0x41002002]
if {$prot2 >= 0 && ($prot2 & 1)} {
    sr "    -> chip-erase completed but DSU.STATUSB.PROT still set: debug still locked (unexpected)"
    return
}
sr "    SAMD DSU chip-erase complete — NVMCTRL security cleared, debug re-enabled (FLASH ERASED)"
sr "    verify with: cortexm-access-check.tcl  (should now read OPEN)"
