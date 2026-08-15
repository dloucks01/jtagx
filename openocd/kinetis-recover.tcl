# kinetis-recover.tcl — NXP Kinetis flash-security recovery: MDM-AP mass-erase clears FTFE flash
# security (FSEC.SEC) and RE-OPENS the SWD/JTAG debug port. This is a DEBUG-MAILBOX recovery, NOT a
# glitch — the MDM-AP is reachable even when the AHB-AP is gated by flash security.
#
# ⚠ DESTRUCTIVE: mass-erase wipes all internal flash. You get DEBUG ACCESS + a blank part, NOT the
#   protected firmware. For the contents you need a fault-injection read-out bypass (deferred).
#
# Refuses when FSEC.MEEN disables mass-erase (permanently locked — no JTAG recovery).
#
# Mechanism (Kinetis MDM-AP, AP index 1):
#   MDM-AP Status  (apreg 1 0x00): bit0 Flash-Mass-Erase-Ack, bit1 Flash-Ready, bit5 Mass-Erase-Enable,
#                                  bit2 System-Security
#   MDM-AP Control (apreg 1 0x04): bit0 Flash-Mass-Erase-in-progress (write 1 to start)
#
#   openocd -f openocd/cortexm-kinetis.cfg -c "init; source openocd/kinetis-recover.tcl; shutdown"

proc kr {s} { puts $s }
proc kr_dap {} { if {[catch {dap names} d]} { return "" } ; return [lindex $d 0] }

kr ""
kr " Kinetis MDM-AP mass-erase recovery (clears FTFE flash security)"
set dap [kr_dap]
if {$dap eq ""} { kr "    -> mass-erase FAILED: no DAP object (check interface/transport)"; return }

# Read MDM-AP status; bit5 = Mass-Erase-Enable. If clear, FSEC.MEEN has locked it out permanently.
set status 0
if {![catch {$dap apreg 1 0x00} v]} { set status $v }
kr [format "    MDM-AP status = 0x%08X" $status]
if {!($status & 0x20)} {
    kr "    -> mass-erase DISABLED (MDM status Mass-Erase-Enable=0 / FSEC.MEEN): debug still locked (permanent)"
    return
}

# Start the mass-erase, then poll for completion (bit0 self-clears when done).
if {[catch {$dap apreg 1 0x04 0x01} _]} {
    kr "    -> mass-erase FAILED: MDM-AP control write faulted (debug still locked)"
    return
}
kr ">> MDM-AP Flash-Mass-Erase = 1 ... polling"
set done 0
for {set i 0} {$i < 200} {incr i} {
    after 10
    if {[catch {$dap apreg 1 0x04} c]} { break }
    if {!($c & 0x01)} { set done 1 ; break }
}
if {!$done} { kr "    -> mass-erase FAILED: never completed (debug still locked)"; return }
catch { reset init } _
kr "    Kinetis MDM-AP mass-erase complete — flash security cleared, debug re-enabled (FLASH ERASED)"
kr "    verify with: cortexm-access-check.tcl  (should now read OPEN)"
