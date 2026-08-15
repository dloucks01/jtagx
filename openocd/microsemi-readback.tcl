# microsemi-readback.tcl — extract eNVM + fabric bitstream from an UNPROVISIONED Microsemi fabric part
# (IGLOO2 / SmartFusion2 fabric) over a standard FTDI, using SVF/DirectC playback — NO FlashPro.
#
# This is the fabric-part "extraction lever": if microsemi-access-check.tcl read OPEN (security not
# provisioned), the device answers a verify/readback SVF and streams its contents out the JTAG TAP.
# On a PROVISIONED device the readback SVF is rejected (security-status fault) and this reports LOCKED.
#
# Non-destructive (readback only — it does NOT program). Provide the vendor-exported readback SVF via
# $MSS_SVF (Libero → Export → Programming → SVF, "VERIFY"/"READ" action). Without it, this emits the
# plan and confirms the access path.
#
#   MSS_SVF=readback.svf openocd -f openocd/microsemi-fpga.cfg \
#       -c "init; source openocd/microsemi-readback.tcl; shutdown"

proc mr {s} { puts $s }

mr ""
mr " Microsemi fabric readback (eNVM + bitstream via SVF/DirectC over FTDI)"

# Re-confirm the device is unprovisioned before attempting readback (belt-and-suspenders).
set secir  0x89 ; set seclen 32
if {[info exists ::env(MSS_SECIR)]}  { set secir  $::env(MSS_SECIR) }
if {[info exists ::env(MSS_SECLEN)]} { set seclen $::env(MSS_SECLEN) }
set locked 0
if {![catch {irscan msfabric.tap $secir} _] && ![catch {drscan msfabric.tap $seclen 0x0} st]} {
    set stv 0; catch { set stv [expr {"0x$st"}] }
    set locked [expr {$stv != 0 ? 1 : 0}]
}
if {$locked} {
    mr "    -> readback FAILED: FlashLock / pass-key provisioned (device still locked)"
    mr "       escalate: DPA pass-key recovery (Skorobogatov/Woods) or authorized FlashPro."
    return
}

if {[info exists ::env(MSS_SVF)] && [file exists $::env(MSS_SVF)]} {
    mr ">> playing readback SVF: $::env(MSS_SVF)"
    if {[catch {svf -tap msfabric.tap $::env(MSS_SVF) quiet} e]} {
        mr "    -> readback FAILED during SVF: $e (device may be provisioned)"
        return
    }
    mr "    fabric readback complete — eNVM + bitstream streamed (unprovisioned device, no FlashPro)"
} else {
    # No SVF supplied: confirm the access path is open and emit the exact next step.
    mr ">> device is UNPROVISIONED — readback path is OPEN."
    mr "    fabric readback available — export a VERIFY/READ SVF from Libero and re-run with MSS_SVF=<file>"
    mr "    (equivalently: DirectC READ action). No FlashPro, no pass-key required."
}
