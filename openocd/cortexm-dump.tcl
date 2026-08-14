# cortexm-dump.tcl — dump a Cortex-M MCU's internal flash + SRAM over SWD/JTAG (Paradigm B).
#
# No MMU: memory is FLAT and memory-mapped, so a "dump" is a direct mem-AP read through the cortex_m
# target (reuses dump_memory). Internal flash is the prize; SRAM holds live state. Chip constants come
# from the per-family cfg globals (CM_FLASH_BASE/SIZE, CM_SRAM_BASE/SIZE) with env override + defaults.
#
# Env override:  FLASH_BASE FLASH_SIZE FLASH_OUT  SRAM_BASE SRAM_SIZE SRAM_OUT  DUMP_HALT(=1)
# Usage:  openocd -f openocd/cortexm-stm32f4.cfg -c "init; source openocd/cortexm-dump.tcl; shutdown"
# STATUS: HW-UNVALIDATED (no MCU on the bench); the path reuses the validated dump_memory.

set _d [file dirname [info script]]
if {[info commands say] eq ""} { proc say {l} { echo $l } }
source [file join $_d lib dump-memory.tcl]

# value precedence: env > per-family cfg global (::CM_*) > default
proc _cm {glob env def} {
    if {[info exists ::env($env)]} { return $::env($env) }
    if {[info exists ::$glob]}     { return [set ::$glob] }
    return $def
}
set FB [_cm CM_FLASH_BASE FLASH_BASE 0x08000000]
set FS [_cm CM_FLASH_SIZE FLASH_SIZE 0x100000]
set FO [_cm CM_FLASH_OUT  FLASH_OUT  dumps/cortexm-flash.bin]
set SB [_cm CM_SRAM_BASE  SRAM_BASE  0x20000000]
set SS [_cm CM_SRAM_SIZE  SRAM_SIZE  0x20000]
set SO [_cm CM_SRAM_OUT   SRAM_OUT   dumps/cortexm-sram.bin]
set HALT [_cm CM_DUMP_HALT DUMP_HALT 1]

if {$HALT ne "0"} { catch { halt } _ }

echo ""
echo "================================================================"
echo " CORTEX-M DUMP — internal flash + SRAM (flat memory, mem-AP read)"
echo "================================================================"
echo [format " flash %s  size %s  -> %s" $FB $FS $FO]
dump_memory $FB $FS 2048 $FO "cortexm-flash"
if {$SS ne "0" && $SS ne "0x0"} {
    echo [format " sram  %s  size %s  -> %s" $SB $SS $SO]
    dump_memory $SB $SS 2048 $SO "cortexm-sram"
}
echo "================================================================"
echo " done. Analyze the flash with dram-secrets.py + ghidra-loadspec.py (Thumb)."
echo "================================================================"
