# nrf52-recover.tcl — nRF52 APPROTECT recovery lever: CTRL-AP ERASEALL clears the read-back
# protection and RE-OPENS the AHB-AP so the core is debuggable again.
#
# ⚠ DESTRUCTIVE: ERASEALL wipes all flash + UICR. You get DEBUG ACCESS, not the original firmware.
#   Use this when the objective is control of the part (or a blank re-provision), NOT when you need
#   to read the existing image — for that you need the fault-injection bypass (keeps flash), see
#   jtagx.unlock lock_nrf. This is the guided loop's runnable "misconfig" lever.
#
# Mechanism (Nordic CTRL-AP, AP index 1):
#   ERASEALL       = apreg 1 0x04   ; write 1 to start
#   ERASEALLSTATUS = apreg 1 0x08   ; reads 1 while busy, 0 when done
#   APPROTECTSTATUS= apreg 1 0x0C   ; 0 = protected, 1 = unprotected (after erase)
# Then a debug reset re-selects the AHB-AP. Secure-APPROTECT (nRF52840 w/ ACL) can refuse ERASEALL.
#
#   openocd -f openocd/cortexm-nrf52.cfg -c "init; source openocd/nrf52-recover.tcl; shutdown"

proc nr {s} { puts $s }
proc nr_dap {} { if {[catch {dap names} d]} { return "" } ; return [lindex $d 0] }

nr ""
nr " nRF52 CTRL-AP recovery (APPROTECT clear via ERASEALL)"
set dap [nr_dap]
if {$dap eq ""} { nr "    -> erase FAILED: no DAP object (check interface/transport)"; return }

# Kick ERASEALL.
if {[catch {$dap apreg 1 0x04 0x01} _]} {
    nr "    -> erase FAILED: CTRL-AP ERASEALL write faulted (secure-APPROTECT / ACL blocks CTRL-AP; debug still locked)"
    return
}
nr ">> CTRL-AP ERASEALL = 1 ... polling ERASEALLSTATUS"

# Poll ERASEALLSTATUS (max ~1s); it self-clears when the chip-erase completes.
set done 0
for {set i 0} {$i < 100} {incr i} {
    after 10
    if {[catch {$dap apreg 1 0x08} st]} { break }
    if {$st == 0} { set done 1 ; break }
}
if {!$done} {
    nr "    -> erase FAILED: ERASEALLSTATUS never cleared (debug still locked)"
    return
}

# Confirm APPROTECT is now open.
set unprot 1
if {![catch {$dap apreg 1 0x0C} ap]} { set unprot [expr {$ap & 0x1}] }
if {!$unprot} {
    nr "    -> erase FAILED: APPROTECTSTATUS still protected (secure-APPROTECT; debug still locked)"
    return
}
catch { reset init } _
nr "    ERASEALL complete — APPROTECT cleared, debug re-enabled (FLASH ERASED)"
nr "    verify with: cortexm-access-check.tcl  (should now read OPEN)"
