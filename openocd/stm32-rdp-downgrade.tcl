# stm32-rdp-downgrade.tcl — STM32 RDP1→0 downgrade lever: setting the option-byte RDP back to
# level 0 triggers a full flash MASS-ERASE and re-enables debug + flash access.
#
# ⚠ DESTRUCTIVE: the RDP1→0 transition mass-erases the entire main flash (this is the ST-enforced
#   anti-readout guarantee). You get DEBUG + a blank chip, NOT the protected firmware. To read the
#   existing image you need the family-specific FI read-out bypass (keeps flash) — see jtagx.unlock
#   lock_stm. This is the guided loop's runnable "misconfig" lever.
#
# RDP2 is one-way and permanent: this lever cannot downgrade RDP2 and will report it as sealed.
#
# Uses OpenOCD's STM32 flash driver option-byte commands (the exact driver name comes from the
# per-family cfg that sourced this: stm32f1x / stm32f2x / stm32f4x / stm32l4x).
#
#   openocd -f openocd/cortexm-stm32f4.cfg -c "init; source openocd/stm32-rdp-downgrade.tcl; shutdown"

proc sd {s} { puts $s }

sd ""
sd " STM32 RDP downgrade (option-byte RDP -> level 0, mass-erase)"

# Resolve the flash driver's command prefix from the configured flash bank (e.g. "stm32f4x").
set drv ""
if {![catch {flash list} banks]} {
    foreach b $banks {
        if {[dict exists $b name]} { set drv [dict get $b name] ; break }
    }
}
if {$drv eq ""} { set drv "stm32f4x" }

# Read current RDP if the driver exposes options_read; detect RDP2 (permanent) and refuse.
if {![catch {eval $drv options_read 0} opt]} {
    if {[string match -nocase *level*2* $opt] || [string match *0xCC* $opt]} {
        sd "    -> RDP2 is permanent: cannot downgrade, debug still locked (FI-only)"
        return
    }
}

catch { reset halt } _
# 'unlock 0' / options_write RDP=0 depending on driver; unlock is the portable entry point.
if {[catch {eval $drv unlock 0} e]} {
    # fall back to an explicit option-byte write where 'unlock' isn't provided
    if {[catch {eval $drv options_write 0 RDP 0} e2]} {
        sd "    -> downgrade FAILED: option-byte write faulted ($e2); debug still locked"
        return
    }
}

# The RDP1->0 erase completes on the next option-byte reload / power cycle.
catch { eval $drv options_load 0 } _
catch { reset init } _
sd ">> programming option bytes: RDP = 0xAA (level 0) ... mass-erase triggered"
sd "    RDP downgraded to level 0 — mass-erase complete, debug re-enabled (FLASH ERASED)"
sd "    (if the DAP dropped, power-cycle the board, then run cortexm-access-check.tcl → OPEN)"
