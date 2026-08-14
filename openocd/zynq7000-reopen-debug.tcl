# zynq7000-reopen-debug.tcl — re-open a SOFTWARE-hardened Zynq-7000's debug gates over JTAG.
#
# THE LEVER (UG585 v1.12.2 Appendix B, devcfg, PDF p.1146-1149):
#   The ARM DAP + all four debug-enable bits live in devcfg.CTRL (0xF8007000), low 7 bits:
#     [2:0] DAP_EN (111 = ARM DAP enabled), [3] DBGEN, [4] NIDEN, [5] SPIDEN, [6] SPNIDEN.
#   They are ordinary rw bits, so writing CTRL |= 0x7F re-enables DAP + invasive/non-invasive +
#   secure debug — UNLESS devcfg.LOCK[0] (DBG lock) is set, which freezes CTRL[6:0] until a
#   power-on-reset (PS_POR_B). This is the Zynq-7000 equivalent of the ZynqMP reopen-debug story:
#   a software-hardened, lock-clear board is reopenable; a board that set the DBG lock is not
#   (POR required) — the read-back DIAGNOSES which case you're in.
#
# HONEST SCOPE (the chicken-and-egg): if DAP_EN is currently NOT 111, the ARM DAP is bypassed and
# the AHB-AP this script writes through is itself unreachable — you can't reopen the DAP over JTAG
# once it's truly bypassed. So this lever applies when the DAP is reachable but the DEBUG enables
# (DBGEN/SPIDEN/...) are cleared, or via an alternate bus master. If CTRL can't be read at all, the
# DAP is bypassed -> reopen over JTAG is not possible (power-cycle / code-exec path only).
#
# STATUS: HW-UNVALIDATED (no Zynq-7000 board on the bench). Writes ONE register (CTRL), read-back only.
# Usage:  openocd -f openocd/zynq7000.cfg -c "init; source openocd/zynq7000-reopen-debug.tcl; shutdown"

set _d [file dirname [info script]]
source [file join $_d lib zynq7000-regs.tcl]
source [file join $_d board-profile.tcl]      ;# ::AXI_TARGET

catch { targets $::AXI_TARGET } _
catch { $::AXI_TARGET arp_examine } _
proc _rd {addr} { if {[catch {read_memory $addr 32 1} v]} { return "" } ; return [lindex $v 0] }

echo ""
echo "================================================================"
echo " ZYNQ-7000 DEBUG RE-OPEN  (devcfg.CTRL |= 0x7F : DAP_EN=111 + all debug)"
echo "================================================================"

set ctrl [_rd $::Z7_DEVCFG_CTRL]
if {$ctrl eq ""} {
    echo " ERROR: cannot read devcfg.CTRL via $::AXI_TARGET."
    echo " => the ARM DAP is BYPASSED (or no AHB path). Reopen over JTAG is NOT possible from here —"
    echo "    the lever lives behind the very gate that's closed. Options: power-cycle, or an alternate"
    echo "    bus master / code-exec path. (Same diagnosis class as the ZynqMP no-AXI-path case.)"
    return
}
set lock [_rd $::Z7_DEVCFG_LOCK]
echo [format " before:  CTRL = 0x%08x   LOCK = 0x%08x" $ctrl [expr {$lock eq "" ? 0 : $lock}]]

if {$lock ne "" && ($lock & $::Z7_LOCK_DBG)} {
    echo " DBG LOCK is SET (LOCK bit 0 = 1): CTRL bits 6-0 are frozen until PS_POR_B. The write below will not"
    echo " stick. This is an eFuse-equivalent hard lock — POWER-CYCLE the board to clear it."
}

set want [expr {$ctrl | $::Z7_CTRL_DEBUG_ALL}]
echo [format " writing: CTRL <- 0x%08x  (set DAP_EN=111, DBGEN/NIDEN/SPIDEN/SPNIDEN=1)" $want]
if {[catch {write_memory $::Z7_DEVCFG_CTRL 32 [list $want]} werr]} {
    echo "   write_memory error: $werr"
}
set after [_rd $::Z7_DEVCFG_CTRL]
echo [format " after:   CTRL = 0x%08x" [expr {$after eq "" ? 0 : $after}]]

echo "----------------------------------------------------------------"
if {$after ne "" && ($after & $::Z7_CTRL_DEBUG_ALL) == $::Z7_CTRL_DEBUG_ALL} {
    echo " VERDICT: DEBUG RE-OPENED.  DAP_EN=111 + all debug enables now set (software gate, LOCK clear)."
} else {
    echo " VERDICT: write did NOT take.  Either LOCK bit 0 = 1 (DBG locked -> POR required) or the bits are"
    echo "   eFuse/strap-forced. Re-run zynq7000-enumerate.tcl to read the lock state."
}
echo "================================================================"
