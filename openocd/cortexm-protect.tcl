# cortexm-protect.tcl — Cortex-M MCU SECURITY POSTURE (the Paradigm-B analog of enumerate.tcl).
#
# Reads the full per-family identity + readout-protection + debug surface and decodes it. The family is
# selected by CM_PROT_KIND (set by the per-family cfg): none | stm32-rdp | nrf-approtect. Register
# addresses are family-constants, cited inline to the vendor doc:
#   stm32-rdp      -> RM0090 (STM32F4)            references/pdf/rm0090-stm32f4.pdf
#   nrf-approtect  -> nRF52840 Product Spec v1.1  references/pdf/nrf52840-ps.pdf  (UICR/FICR overview p.43-44)
#   none (rp2040)  -> RP2040 datasheet            references/pdf/rp2040-datasheet.pdf (SYSINFO)
#
# KEY HONEST POINT: if you can read these registers AT ALL, the AHB-AP is open and flash is dumpable now —
# a truly locked part blocks the AP. The value tells you the CONFIGURED intent (would a reset re-lock it)
# and whether the only "unlock" is a destructive mass-erase. STATUS: HW-UNVALIDATED (no MCU on the bench).
#
# Usage:  openocd -f openocd/cortexm-stm32f4.cfg -c "init; source openocd/cortexm-protect.tcl; shutdown"

proc _cm {glob env def} {
    if {[info exists ::env($env)]} { return $::env($env) }
    if {[info exists ::$glob]}     { return [set ::$glob] }
    return $def
}
proc _rd  {a} { if {[catch {read_memory $a 32 1} v]} { return "" } ; return [lindex $v 0] }
proc _rd16 {a} { if {[catch {read_memory $a 16 1} v]} { return "" } ; return [lindex $v 0] }
proc _rd8  {a} { if {[catch {read_memory $a 8 1} v]}  { return "" } ; return [lindex $v 0] }
proc _p {label val} { echo [format "   %-22s %s" $label $val] }
# runtime self-check helpers: validate the IDENTITY read against a doc-known invariant before trusting the
# rest. No test set needed — they confirm correctness against the live silicon (catch dead bus / wrong
# address / wrong chip). _gate is the universal check (readable, not 0/0xFFFFFFFF); call `if {[_gate ...]} return`.
proc _bad {v} { return [expr {$v eq "" || $v == 0 || $v == 0xFFFFFFFF}] }
proc _gate {reg val name} {
    if {![_bad $val]} { return 0 }
    echo " SANITY ABORT: identity reg $reg read '$val' — DAP down / wrong address / not a $name."
    return 1
}

set KIND [_cm CM_PROT_KIND PROT_KIND none]
catch { halt } _

echo ""
echo "================================================================"
echo " CORTEX-M SECURITY POSTURE  (family: $KIND)"
echo "================================================================"

switch -- $KIND {
  stm32-rdp {
    # ---- STM32F4 (RM0090) ----
    echo " (1) IDENTITY"
    set idc [_rd 0xE0042000]   ;# DBGMCU_IDCODE
    if {[_gate 0xE0042000 $idc "STM32 (DBGMCU_IDCODE)"]} return
    if {1} {
        set devid [format 0x%03x [expr {$idc & 0xfff}]]   ;# hex string so the switch patterns match
        set revid [expr {($idc >> 16) & 0xffff}]
        switch -- $devid {
            0x413 {set part "F405/407/415/417"} 0x419 {set part "F427/437/429/439"}
            0x423 {set part "F401xB/C"} 0x433 {set part "F401xD/E"} 0x431 {set part "F411"}
            0x441 {set part "F412"} 0x421 {set part "F446"} 0x434 {set part "F469/479"}
            default {set part "unknown"}
        }
        _p "DBGMCU_IDCODE" [format "DEV_ID=%s (STM32%s)  REV_ID=0x%04x" $devid $part $revid]
    }
    set u0 [_rd 0x1FFF7A10]; set u1 [_rd 0x1FFF7A14]; set u2 [_rd 0x1FFF7A18]   ;# 96-bit unique ID
    if {$u0 ne ""} { _p "Unique device ID" [format "%08x-%08x-%08x" $u2 $u1 $u0] }
    set fs [_rd16 0x1FFF7A22]   ;# flash size in KB
    if {$fs ne ""} { _p "Flash size" [format "%d KB" $fs] }
    echo " (2) READOUT PROTECTION"
    set opt [_rd 0x40023C14]   ;# FLASH_OPTCR
    if {$opt ne ""} {
        set rdp [expr {($opt >> 8) & 0xff}]
        set nwrp [expr {($opt >> 16) & 0xfff}]   ;# 1 = sector unprotected, 0 = write-protected
        if {$rdp == 0xAA} { set rv "LEVEL 0 — no protection, flash fully readable (dev)" } \
        elseif {$rdp == 0xCC} { set rv "LEVEL 2 — MAX (debug perm. disabled; you wouldn't read this)" } \
        else { set rv "LEVEL 1 — flash blocked from the debugger; unlock = mass-erase (WIPES flash)" }
        _p "RDP" [format "0x%02x -> %s" $rdp $rv]
        _p "Write-protect (nWRP)" [format "0x%03x  (bit=0 -> that sector write-protected)" $nwrp]
        _p "BOR level (BOR_LEV)" [format "0x%x" [expr {($opt >> 2) & 0x3}]]
    }
  }
  nrf-approtect {
    # ---- Nordic nRF52840 (PS v1.1). FICR base 0x10000000, UICR base 0x10001000 ----
    echo " (1) IDENTITY (FICR)"
    set part [_rd 0x10000100]
    if {[_gate 0x10000100 $part "nRF5x (FICR.INFO.PART)"]} return
    if {(($part >> 16) & 0xffff) != 0x5} {
        echo [format " SANITY ABORT: FICR.INFO.PART=0x%08x is not nRF52/53 (expected 0x52xxx/0x53xxx). Wrong board/base." $part]
        return
    }
    set var [_rd 0x10000104]; set pkg [_rd 0x10000108]
    set ram [_rd 0x1000010C]; set fl [_rd 0x10000110]
    if {$part ne ""} { _p "INFO.PART" [format "0x%08x (e.g. 0x52840)" $part] }
    if {$var ne ""}  { _p "INFO.VARIANT" [format "0x%08x (ASCII build code)" $var] }
    if {$ram ne ""}  { _p "RAM / FLASH" [format "%d KB / %d KB" $ram $fl] }
    set d0 [_rd 0x10000060]; set d1 [_rd 0x10000064]
    if {$d0 ne ""} { _p "DEVICEID" [format "%08x%08x" $d1 $d0] }
    echo " (2) READOUT PROTECTION (UICR.APPROTECT @0x10001208)"
    set ap [_rd 0x10001208]   ;# nRF52840 PS v1.1 §4.5.1.5 (the overview Table 10 has a typo; detail = 0x208)
    if {$ap ne ""} {
        if {$ap == 0xFFFFFFFF} { set av "OPEN (HwDisabled / factory) — AHB-AP unrestricted, flash dumpable" } \
        elseif {[expr {$ap & 0xff}] == 0x5A} { set av "SwDisabled via 0x5A (register-protect open this session)" } \
        else { set av "ENABLED is the configured intent — a reset re-locks; only re-open is a CTRL-AP mass-erase (WIPE)" }
        _p "APPROTECT" [format "0x%08x -> %s" $ap $av]
    }
    echo " (3) DEBUG / OUTPUT"
    set dbg [_rd 0x10001210]   ;# UICR.DEBUGCTRL
    if {$dbg ne ""} { _p "DEBUGCTRL" [format "0x%08x (CPUNIDEN/CPUFPBEN; 0xFFFFFFFF = all debug allowed)" $dbg] }
    set reg [_rd 0x10001304]   ;# UICR.REGOUT0
    if {$reg ne ""} { _p "REGOUT0 (VOUT)" [format "0x%08x" $reg] }
  }
  none {
    # ---- RP2040 (datasheet). SYSINFO base 0x40000000 ----
    echo " (1) IDENTITY (SYSINFO)"
    set cid [_rd 0x40000000]   ;# CHIP_ID
    if {[_gate 0x40000000 $cid "RP2040 (SYSINFO.CHIP_ID)"]} return
    if {1} {
        _p "CHIP_ID" [format "0x%08x  (PART=0x%04x REV=0x%x MANUF=0x%03x)" $cid \
            [expr {($cid >> 12) & 0xffff}] [expr {($cid >> 28) & 0xf}] [expr {$cid & 0xfff}]]
    }
    set plat [_rd 0x40000004]   ;# PLATFORM (bit1 ASIC, bit0 FPGA)
    if {$plat ne ""} {
        if {[expr {$plat & 0x2}]} { set ps ASIC } else { set ps FPGA/sim }
        _p "PLATFORM" [format "0x%08x (%s)" $plat $ps]
    }
    set git [_rd 0x40000040]    ;# GITREF_RP2040
    if {$git ne ""} { _p "GITREF" [format "0x%08x" $git] }
    echo " (2) READOUT PROTECTION"
    _p "On-chip protection" "NONE — RP2040 has no internal flash + no readout-protection fuse."
    _p "Real gate" "the EXTERNAL QSPI flash (XIP @0x10000000) — readable unless QSPI is disabled."
  }
  stm32l4 {
    # ---- STM32L4 (RM0351). FLASH_OPTR @0x40022020 (RDP bits 7:0), unique ID @0x1FFF7590 ----
    echo " (1) IDENTITY"
    set idc [_rd 0xE0042000]
    if {[_gate 0xE0042000 $idc "STM32 (DBGMCU_IDCODE)"]} return
    if {1} {
        set devid [format 0x%03x [expr {$idc & 0xfff}]]
        switch -- $devid {
            0x415 {set part "L4x6"} 0x435 {set part "L43x/44x"} 0x462 {set part "L45x/46x"}
            0x464 {set part "L41x/42x"} 0x470 {set part "L4Rx/4Sx"} 0x461 {set part "L496/4A6"}
            default {set part "unknown"}
        }
        _p "DBGMCU_IDCODE" [format "DEV_ID=%s (STM32%s)  REV_ID=0x%04x" $devid $part [expr {($idc >> 16) & 0xffff}]]
    }
    set u0 [_rd 0x1FFF7590]; set u1 [_rd 0x1FFF7594]; set u2 [_rd 0x1FFF7598]
    if {$u0 ne ""} { _p "Unique device ID" [format "%08x-%08x-%08x" $u2 $u1 $u0] }
    set fs [_rd16 0x1FFF75E0]
    if {$fs ne ""} { _p "Flash size" [format "%d KB" $fs] }
    echo " (2) READOUT PROTECTION"
    set opt [_rd 0x40022020]   ;# FLASH_OPTR
    if {$opt ne ""} {
        set rdp [expr {$opt & 0xff}]
        if {$rdp == 0xAA} { set rv "LEVEL 0 — no protection (dev)" } \
        elseif {$rdp == 0xCC} { set rv "LEVEL 2 — MAX (debug perm. disabled)" } \
        else { set rv "LEVEL 1 — flash blocked; unlock = mass-erase (WIPE)" }
        _p "RDP (FLASH_OPTR 7-0)" [format "0x%02x -> %s" $rdp $rv]
    }
  }
  stm32f1 {
    # ---- STM32F1 (RM0008). FLASH_OBR @0x4002201C (RDPRT bit 1), unique ID @0x1FFFF7E8 ----
    echo " (1) IDENTITY"
    set idc [_rd 0xE0042000]
    if {[_gate 0xE0042000 $idc "STM32 (DBGMCU_IDCODE)"]} return
    if {1} {
        set devid [format 0x%03x [expr {$idc & 0xfff}]]
        switch -- $devid {
            0x410 {set part "F101/102/103 medium-density"} 0x412 {set part "low-density"}
            0x414 {set part "high-density"} 0x430 {set part "XL-density"} 0x418 {set part "connectivity"}
            default {set part "unknown"}
        }
        _p "DBGMCU_IDCODE" [format "DEV_ID=%s (STM32%s)  REV_ID=0x%04x" $devid $part [expr {($idc >> 16) & 0xffff}]]
    }
    set u0 [_rd 0x1FFFF7E8]; set u1 [_rd 0x1FFFF7EC]; set u2 [_rd 0x1FFFF7F0]
    if {$u0 ne ""} { _p "Unique device ID" [format "%08x-%08x-%08x" $u2 $u1 $u0] }
    set fs [_rd16 0x1FFFF7E0]
    if {$fs ne ""} { _p "Flash size" [format "%d KB" $fs] }
    echo " (2) READOUT PROTECTION"
    set obr [_rd 0x4002201C]   ;# FLASH_OBR
    if {$obr ne ""} {
        if {[expr {($obr >> 1) & 1}]} {
            _p "RDPRT (FLASH_OBR bit 1)" "1 -> READ-PROTECTED (unlock = mass-erase WIPE)"
        } else {
            _p "RDPRT (FLASH_OBR bit 1)" "0 -> not protected, flash readable (dev)"
        }
    }
  }
  sam-dsu {
    # ---- Atmel/Microchip SAM D5x/E5x (DS60001507). DSU @0x41002000 ----
    echo " (1) IDENTITY"
    set did [_rd 0x41002018]   ;# DSU.DID
    if {[_gate 0x41002018 $did "SAM D5x/E5x (DSU.DID)"]} return
    if {1} {
        _p "DSU.DID" [format "0x%08x (FAMILY=0x%x SERIES=0x%x DIE=0x%x REV=0x%x DEVSEL=0x%02x)" $did \
            [expr {($did >> 23) & 0x1f}] [expr {($did >> 16) & 0x3f}] [expr {($did >> 12) & 0xf}] \
            [expr {($did >> 8) & 0xf}] [expr {$did & 0xff}]]
    }
    echo " (2) READOUT PROTECTION (DSU.STATUSB.PROT)"
    set sb [_rd8 0x41002002]   ;# DSU.STATUSB
    if {$sb ne ""} {
        if {[expr {$sb & 0x1}]} {
            _p "PROT" "1 -> DEBUG-ACCESS PROTECTED (NVMCTRL security bit set; only chip-erase removes it = WIPE)"
        } else {
            _p "PROT" "0 -> open, debug + flash accessible (dev)"
        }
    }
  }
  kinetis-fsec {
    # ---- NXP Kinetis K64 (K64P144M120SF5RM). SIM_SDID @0x40048024, FTFE_FSEC @0x40020002 ----
    echo " (1) IDENTITY"
    set sdid [_rd 0x40048024]   ;# SIM_SDID
    if {[_gate 0x40048024 $sdid "Kinetis (SIM_SDID)"]} return
    if {1} {
        _p "SIM_SDID" [format "0x%08x (FAMILYID=0x%x SUBFAMID=0x%x SERIESID=0x%x PINID=0x%x REVID=0x%x)" $sdid \
            [expr {($sdid >> 28) & 0xf}] [expr {($sdid >> 24) & 0xf}] [expr {($sdid >> 20) & 0xf}] \
            [expr {$sdid & 0xf}] [expr {($sdid >> 12) & 0xf}]]
    }
    echo " (2) FLASH SECURITY (FTFE_FSEC)"
    set fsec [_rd8 0x40020002]
    if {$fsec ne ""} {
        set sec [expr {$fsec & 0x3}]; set meen [expr {($fsec >> 4) & 0x3}]
        if {$sec == 0x2} { set sv "UNSECURED (0b10) — flash readable (dev)" } \
        else { set sv "SECURED (debug-port access limited; unlock = mass-erase WIPE)" }
        _p "SEC (bits 1-0)" [format "0x%x -> %s" $sec $sv]
        if {$meen == 0x2} {
            _p "MEEN (bits 5-4)" "0b10 -> MASS-ERASE DISABLED — secured + no recovery (PERMANENTLY locked)"
        } else {
            _p "MEEN (bits 5-4)" [format "0x%x -> mass-erase available" $meen]
        }
    }
  }
  default { echo " unknown CM_PROT_KIND '$KIND'." }
}
echo "================================================================"
echo " NOTE: reading any of the above proves the AHB-AP is OPEN -> internal flash is dumpable now."
echo "================================================================"
