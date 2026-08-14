# zynq7000-flash.tcl — dump the Zynq-7000 boot flash (QSPI) over JTAG via the LQSPI LINEAR WINDOW.
#
# WHY THIS IS THE EASY PATH on Zynq-7000 (unlike ZynqMP's GQSPI generic-FIFO):
#   When the QSPI controller is in Linear Quad-SPI (LQSPI) mode, the flash is memory-mapped read-only
#   at 0xFC000000 (UG585 Ch.12). A board that BOOTED from QSPI has LQSPI already configured by the
#   BootROM/FSBL — so dumping flash is just a mem-AP read of 0xFC000000.. through the AHB-AP. No
#   controller programming, no DMA. We reuse the generic dump_memory().
#
# LIMITS (honest): the linear window is the lower 32 MB only. Flash larger than 32 MB needs either
#   IO-mode (generic FIFO, not implemented here) or LQSPI upper-bank switching. If the board did NOT
#   boot from QSPI, LQSPI may be unconfigured and 0xFC000000 reads 0xFFFFFFFF / bus-errors — this
#   script detects that and tells you.
#
# Env:
#   FLASH_SIZE   bytes to dump (default 0x2000000 = 32 MB, the full linear window)
#   FLASH_OUT    output path (default dumps/zynq7000-flash.bin)
#   FLASH_CHUNK  words per read burst (default 2048)
#
# Usage:
#   FLASH_SIZE=0x1000000 openocd -f openocd/zynq7000.cfg \
#     -c "init; source openocd/zynq7000-flash.tcl; shutdown"
#
# STATUS: HW-UNVALIDATED (developed without a Zynq-7000 board on the bench). The path is sound and
# reuses validated dump_memory(); confirm on first contact via the sanity check below.

set _d [file dirname [info script]]
if {[info commands say] eq ""} { proc say {l} { echo $l } }   ;# dump-memory.tcl logs via say
source [file join $_d lib zynq7000-regs.tcl]
source [file join $_d lib dump-memory.tcl]
source [file join $_d board-profile.tcl]      ;# resolves ::AXI_TARGET (auto-detects zynq.axi)

proc _envd {name def} { if {[info exists ::env($name)]} { return $::env($name) } ; return $def }
set SIZE  [_envd FLASH_SIZE  0x2000000]
set OUT   [_envd FLASH_OUT   dumps/zynq7000-flash.bin]
set CHUNK [_envd FLASH_CHUNK 2048]
set BASE  $::Z7_QSPI_LINEAR

# select the memory mem-AP (AHB-AP, named zynq.axi by zynq7000.cfg)
catch { targets $::AXI_TARGET } _
catch { $::AXI_TARGET arp_examine } _

echo ""
echo "================================================================"
echo " ZYNQ-7000 QSPI FLASH DUMP — LQSPI linear window @ $BASE"
echo "================================================================"

# --- sanity check: is the linear window actually serving flash? ---
set head ""
if {[catch {read_memory $BASE 32 8} head]} {
    echo " ERROR: cannot read $BASE via $::AXI_TARGET ($head)."
    echo "   The AHB-AP may be gated, or LQSPI is not mapped. Verify the access verdict is OPEN."
    return
}
set w0 [lindex $head 0]
set allff 1 ; foreach w $head { if {$w != 0xffffffff} { set allff 0 ; break } }
set allzero 1 ; foreach w $head { if {$w != 0} { set allzero 0 ; break } }
echo [format " first words: %08x %08x %08x %08x ..." \
        [lindex $head 0] [lindex $head 1] [lindex $head 2] [lindex $head 3]]
# Zynq-7000 boot image header carries the "XLNX" image-identification tag near the start (UG585 boot
# header). We don't hard-require it (an encrypted/odd image may differ) — just advise.
if {$allff} {
    echo " WARNING: window reads all-0xFF — LQSPI is likely UNCONFIGURED (board didn't boot from QSPI),"
    echo "   or the flash is blank. Configure LQSPI (boot from QSPI) or use IO-mode. Dumping anyway."
} elseif {$allzero} {
    echo " WARNING: window reads all-zero — unusual; the AHB-AP read may be returning a dead bus."
} else {
    echo " window returns data (not blank) — looks like a live LQSPI flash map. Proceeding."
}

echo " dumping [format 0x%X $SIZE] bytes  ->  $OUT"
set res [dump_memory $BASE $SIZE $CHUNK $OUT "zynq7000-qspi"]
echo "================================================================"
echo " done: $OUT"
echo " (linear window is 32 MB; for larger flash, switch LQSPI banks or use IO-mode — not yet automated)"
echo "================================================================"
