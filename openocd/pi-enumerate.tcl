# pi-enumerate.tcl — Raspberry Pi ARM-side security posture (honestly thin).
#
# A Pi's secure boot / OTP / chip identity live in the closed VideoCore GPU, NOT on the ARM JTAG — so
# there is no vendor security-register surface to enumerate the way ZynqMP/Zynq-7000 have. The ONE
# security-relevant thing readable over the ARM DAP is the **CoreSight debug-authentication status**
# (AUTHSTATUS) at the core's debug base: whether invasive / non-invasive / secure debug is enabled.
# That's it — this script reads it and is honest about the rest.
#
# PI_DBGBASE: core-0 debug base (set by rpi.cfg). bcm2837 (Pi3)=0x80010000, bcm2711 (Pi4)=0x80410000.
# Reachable via the AHB-AP (the stock target attaches the cores at ap-num 0 / dbgbase).
# STATUS: HW-UNVALIDATED (no Pi on the bench). Read-only.
# Usage:  openocd -f openocd/rpi.cfg -c "init; source openocd/pi-enumerate.tcl; shutdown"

set _d [file dirname [info script]]
source [file join $_d board-profile.tcl]      ;# ::AXI_TARGET
proc _cm {glob env def} {
    if {[info exists ::env($env)]} { return $::env($env) }
    if {[info exists ::$glob]}     { return [set ::$glob] }
    return $def
}
proc _rd {a} { if {[catch {read_memory $a 32 1} v]} { return "" } ; return [lindex $v 0] }
# decode a 2-bit AUTHSTATUS field: 00=not implemented, 10=disabled, 11=enabled
proc _auth {field} {
    switch -- $field { 0 {return "not implemented"} 2 {return "DISABLED"} 3 {return "enabled"} default {return "?"} }
}

set DBGBASE [_cm PI_DBGBASE PI_DBGBASE 0x80010000]
catch { targets $::AXI_TARGET } _
catch { $::AXI_TARGET arp_examine } _

echo ""
echo "================================================================"
echo " RASPBERRY PI — ARM-side posture (CoreSight debug authentication)"
echo " mem-AP: $::AXI_TARGET   debug base: $DBGBASE"
echo "================================================================"

set auth [_rd [expr {$DBGBASE + 0xFB8}]]   ;# CoreSight AUTHSTATUS
if {$auth eq ""} {
    echo " AUTHSTATUS unreadable at [format 0x%x [expr {$DBGBASE + 0xFB8}]] — wrong PI_DBGBASE for this model,"
    echo "   or the DAP is not up. Pi3=0x80010000, Pi4=0x80410000 (core 0)."
} else {
    echo [format " AUTHSTATUS = 0x%08x" $auth]
    echo [format "   Non-secure invasive (NSID)      %s" [_auth [expr {$auth & 0x3}]]]
    echo [format "   Non-secure non-invasive (NSNID) %s" [_auth [expr {($auth >> 2) & 0x3}]]]
    echo [format "   Secure invasive (SID)           %s" [_auth [expr {($auth >> 4) & 0x3}]]]
    echo [format "   Secure non-invasive (SNID)      %s" [_auth [expr {($auth >> 6) & 0x3}]]]
}
echo "----------------------------------------------------------------"
echo " NOT on the ARM JTAG (owned by the VideoCore GPU, honestly):"
echo "   - secure boot / signed-boot policy (Pi4/5/CM4 OTP)"
echo "   - chip identity / OTP / fuses        (read via the VC mailbox, not the DAP)"
echo "   - boot flash (SD / SPI-EEPROM)        (VideoCore-owned)"
echo " So the Pi's JTAG value is RAM dump + live patch, not posture enumeration."
echo "================================================================"
