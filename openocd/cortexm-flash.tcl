# cortexm-flash.tcl — WRITE / reflash a Cortex-M MCU's internal flash over SWD/JTAG (Paradigm-B persistence).
#
# Uses OpenOCD's BUILT-IN flash driver (the per-family cfg's `flash bank`, e.g. stm32f2x / nrf5 / atsame5 /
# kinetis), so the erase/program/verify sequences are handled and validated by OpenOCD — robust. This is the
# WRITE counterpart to cortexm-dump.tcl: dump -> patch the firmware offline -> reflash here -> reset.
#
# *** DESTRUCTIVE — modifies flash. *** Requires the part UNLOCKED (RDP level 0 / APPROTECT disabled). Run
# cortexm-protect.tcl FIRST: a locked part rejects the write (and on some parts a forced unlock mass-erases).
#
# Env:
#   CMF_OP    write (default — erase+program+verify) | verify | erase
#   CMF_FILE  the image to write/verify (raw binary, starts at CMF_ADDR)
#   CMF_ADDR  flash address (default = the cfg's CM_FLASH_BASE, e.g. 0x08000000 for STM32)
#   CMF_RESET 1 (default) = reset+run after a successful write; 0 = leave halted
#
# Usage:  CMF_FILE=patched.bin openocd -f openocd/cortexm-stm32f4.cfg \
#           -c "init; source openocd/cortexm-flash.tcl; shutdown"
# STATUS: HW-UNVALIDATED (no MCU on the bench); the flash driver path is OpenOCD's own and well-trodden.

proc _env {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
proc _g   {g d} { if {[info exists ::$g]} { return [set ::$g] } ; return $d }
set OP    [_env CMF_OP    write]
set FILE  [_env CMF_FILE  ""]
set ADDR  [_env CMF_ADDR  [_g CM_FLASH_BASE 0x08000000]]
set RESET [_env CMF_RESET 1]

echo ""
echo "================================================================"
echo " CORTEX-M FLASH WRITE  (op=$OP  addr=$ADDR)  *** DESTRUCTIVE ***"
echo "================================================================"
echo " Reminder: the part must be UNLOCKED (RDP-0 / APPROTECT off). Check with cortexm-protect.tcl first."

if {[catch { reset halt } e]} { echo " warn: 'reset halt' failed ($e) — trying plain halt"; catch { halt } _ }
if {[catch { flash probe 0 } e]} {
    echo " ERROR: 'flash probe 0' failed ($e). No flash bank for this target? (the per-family cfg must define one)."
    return
}

switch -- $OP {
    write {
        if {$FILE eq ""} { echo " ERROR: set CMF_FILE=<image>"; return }
        echo " erasing + programming $FILE at $ADDR ..."
        if {[catch { flash write_image erase $FILE $ADDR } e]} {
            echo " WRITE FAILED: $e"
            echo "   common causes: flash is read-out protected (RDP/APPROTECT), write-protected sectors,"
            echo "   or the image overruns the bank. Re-run cortexm-protect.tcl to read the lock state."
            return
        }
        echo " verifying ..."
        if {[catch { verify_image $FILE $ADDR } e]} { echo " VERIFY FAILED: $e"; return }
        echo " VERIFIED — flash now holds the new image."
        if {$RESET ne "0"} { catch { reset run } _ ; echo " reset+run (the patched firmware is executing)." } \
        else { echo " left halted (CMF_RESET=0)." }
    }
    verify {
        if {$FILE eq ""} { echo " ERROR: set CMF_FILE=<image>"; return }
        if {[catch { verify_image $FILE $ADDR } e]} { echo " VERIFY MISMATCH: $e" } else { echo " VERIFIED — flash matches $FILE." }
    }
    erase {
        echo " mass-erasing bank 0 (all sectors) ..."
        if {[catch { flash erase_sector 0 0 last } e]} { echo " ERASE FAILED: $e (try the driver's mass_erase, or it's protected)." } \
        else { echo " ERASED." }
    }
    default { echo " unknown CMF_OP '$OP' (write|verify|erase)." }
}
echo "================================================================"
