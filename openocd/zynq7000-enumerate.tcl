# zynq7000-enumerate.tcl — Zynq-7000 comprehensive SECURITY POSTURE (the Zynq-7000 analog of enumerate.tcl).
#
# Reads the full Zynq-7000 security surface over the AHB-AP and decodes it into an OFF/dev -> ON/provisioned
# posture, sectioned like the ZynqMP enumerator: Identity, Boot, Secure-boot & eFuse, Debug/DAP, Crypto,
# Config-lock & TrustZone, Lock bits. Every field is traced to UG585 v1.12.2 Appendix B (devcfg PDF
# p.1146-1162, slcr PDF p.1620-1626) — masks live in lib/zynq7000-regs.tcl. See docs/24 for the catalog.
#
# STATUS: HW-UNVALIDATED (no Zynq-7000 board on the bench). Read-only.
# Usage:  openocd -f openocd/zynq7000.cfg -c "init; source openocd/zynq7000-enumerate.tcl; shutdown"

set _d [file dirname [info script]]
source [file join $_d lib zynq7000-regs.tcl]
source [file join $_d board-profile.tcl]      ;# ::AXI_TARGET

catch { targets $::AXI_TARGET } _
catch { $::AXI_TARGET arp_examine } _

proc _rd {addr} { if {[catch {read_memory $addr 32 1} v]} { return "" } ; return [lindex $v 0] }
proc _onoff {cond on off} { if {$cond} { return $on } ; return $off }
proc _p {label verdict} { echo [format "   %-24s %s" $label $verdict] }
proc _bit {v mask} { if {$v eq ""} { return 0 } ; return [expr {($v & $mask) != 0}] }
proc _bad {v} { return [expr {$v eq "" || $v == 0 || $v == 0xFFFFFFFF}] }

# --- SANITY GATE: confirm this really is a Zynq-7000 before trusting any posture bit (runtime self-check
# against a doc-known invariant — no test set needed; catches wrong mem-AP / wrong board / dead bus live).
set idc [_rd $::Z7_SLCR_PSS_IDCODE]
if {[_bad $idc]} {
    echo " SANITY ABORT: PSS_IDCODE ($::Z7_SLCR_PSS_IDCODE) read '$idc' — DAP down / wrong mem-AP / not mapped."
    return
}
if {[expr {($idc >> 21) & 0x7f}] != 0x1b || [expr {($idc >> 1) & 0x7ff}] != 0x49} {
    echo [format " SANITY ABORT: PSS_IDCODE=0x%08x — FAMILY!=0x1B or MFG!=0x49 (not a Xilinx Zynq-7000). Wrong board/cfg." $idc]
    return
}

set ctrl   [_rd $::Z7_DEVCFG_CTRL]
set lock   [_rd $::Z7_DEVCFG_LOCK]
set status [_rd $::Z7_DEVCFG_STATUS]
set mctrl  [_rd $::Z7_DEVCFG_MCTRL]
set bootm  [_rd $::Z7_SLCR_BOOT_MODE]
set locksta [_rd $::Z7_SLCR_LOCKSTA]
set reboot [_rd $::Z7_SLCR_REBOOT_STS]
set apuctl [_rd $::Z7_SLCR_APU_CTRL]
set tzdma  [_rd $::Z7_SLCR_TZ_DMA_NS]
set tzper  [_rd $::Z7_SLCR_TZ_DMA_PER]

echo ""
echo "================================================================"
echo " ZYNQ-7000 SECURITY POSTURE   (UG585 v1.12.2 Appendix B)"
echo " mem-AP: $::AXI_TARGET"
echo "================================================================"
if {$ctrl eq ""} {
    echo " ERROR: cannot read devcfg.CTRL via $::AXI_TARGET — the ARM DAP may be BYPASSED (DAP_EN!=111)"
    echo "   so the AHB-AP can't reach the PS, or the verdict is not OPEN. (See zynq7000-reopen-debug.tcl.)"
    return
}
echo [format " devcfg: CTRL=0x%08x LOCK=0x%08x STATUS=0x%08x MCTRL=0x%08x" \
        $ctrl [expr {$lock eq "" ? 0 : $lock}] [expr {$status eq "" ? 0 : $status}] [expr {$mctrl eq "" ? 0 : $mctrl}]]

# ---- 1. IDENTITY ----
echo "----------------------------------------------------------------"
echo " (1) IDENTITY"
if {$idc ne ""} {
    set dev [format 0x%02x [expr {($idc >> 12) & 0x1f}]]
    set rev [expr {($idc >> 28) & 0xf}]
    set fam [expr {($idc >> 21) & 0x7f}]
    set name "unknown-die"
    if {[info exists ::Z7_DEVICE_NAME($dev)]} { set name $::Z7_DEVICE_NAME($dev) }
    set famok [_onoff [expr {$fam == 0x1b}] "Zynq-7000" [format "family 0x%x" $fam]]
    _p "PSS_IDCODE" [format "%s  device=%s (code %s)  IDCODE rev=%d" $famok $name $dev $rev]
}
if {$mctrl ne ""} {
    set psver [expr {($mctrl >> $::Z7_MCTRL_PSVER_SH) & 0xf}]
    switch -- $psver {0 {set s 1.0} 1 {set s 2.0} 2 {set s 3.0} 3 {set s 3.1} default {set s "?"}}
    _p "Silicon version (PS_VERSION)" "$s (code $psver)"
}

# ---- 2. BOOT ----
echo " (2) BOOT"
if {$bootm ne ""} {
    set d [expr {$bootm & 0x7}]
    switch -- $d {0 {set dn JTAG} 1 {set dn Quad-SPI} 2 {set dn NOR} 4 {set dn NAND} 5 {set dn "SD Card"} default {set dn reserved}}
    _p "Boot device (BOOT_MODE)" [format "%s (0x%x); PLL %s; JTAG chain %s" $dn $d \
        [_onoff [_bit $bootm 0x10] bypassed enabled] [_onoff [_bit $bootm 0x8] independent cascade]]
}
if {$reboot ne ""} {
    set err [expr {$reboot & 0xffff}]
    set causes {}
    if {[_bit $reboot 0x400000]} { lappend causes POR }
    if {[_bit $reboot 0x200000]} { lappend causes SRST_B }
    if {[_bit $reboot 0x100000]} { lappend causes DBG_RST }
    if {[_bit $reboot 0x080000]} { lappend causes SLC_RST }
    if {[_bit $reboot 0x010000]} { lappend causes SWDT }
    if {[llength $causes] == 0} { set causes {(none) } }
    _p "Last reset cause" [join $causes ", "]
    _p "BootROM error code" [_onoff [expr {$err != 0}] [format "0x%04x  <- NON-ZERO (boot fault / lockdown)" $err] "0x0000 (clean boot)"]
}

# ---- 3. SECURE BOOT & eFUSE (the crown jewels — devcfg.STATUS reflects the eFuse state) ----
echo " (3) SECURE BOOT & eFUSE"
set sec [_bit $ctrl $::Z7_CTRL_SEC_EN]
_p "Booted securely (SEC_EN)" [_onoff $sec "YES — this boot was authenticated/encrypted" "no — non-secure boot (dev/default)"]
if {$status ne ""} {
    _p "eFuse SECURE_EN" [_onoff [_bit $status $::Z7_STAT_EFUSE_SEC_EN] "BLOWN — secure boot is ENFORCED in hardware (HARDENED)" "not blown — non-secure boot permitted (dev)"]
    _p "eFuse JTAG_DIS"  [_onoff [_bit $status $::Z7_STAT_EFUSE_JTAGDIS] "BLOWN — ARM DAP permanently bypassed (JTAG fused off)" "not blown — JTAG/DAP allowed"]
    _p "eFuse SW_RESERVE" [_onoff [_bit $status $::Z7_STAT_EFUSE_SWRES] "BLOWN — BBRAM AES key disabled (eFuse key forced)" "not blown — BBRAM key usable"]
    _p "Secure lockdown"  [_onoff [_bit $status $::Z7_STAT_SECURE_RST] "ACTIVE (SECURE_RST=1) — device is in lockdown" "clear"]
    _p "DEVCI illegal-access" [_onoff [_bit $status $::Z7_STAT_ILLEGAL_APB] "SET — DEVCI locked out (wrong UNLOCK word)" "clear"]
}

# ---- 4. DEBUG / DAP ----
echo " (4) DEBUG / DAP"
_p "ARM DAP (DAP_EN)" [_onoff [expr {($ctrl & $::Z7_CTRL_DAP_EN) == $::Z7_CTRL_DAP_EN}] "ENABLED (111)" "BYPASSED — DAP off"]
_p "Invasive (DBGEN)"     [_onoff [_bit $ctrl $::Z7_CTRL_DBGEN]   enabled disabled]
_p "Non-invasive (NIDEN)" [_onoff [_bit $ctrl $::Z7_CTRL_NIDEN]   enabled disabled]
_p "Secure-inv (SPIDEN)"  [_onoff [_bit $ctrl $::Z7_CTRL_SPIDEN]  enabled disabled]
_p "Secure-non-inv (SPNIDEN)" [_onoff [_bit $ctrl $::Z7_CTRL_SPNIDEN] enabled disabled]
_p "JTAG scan chain"      [_onoff [_bit $ctrl $::Z7_CTRL_JTAG_CHDIS] "DISABLED (CTRL.JTAG_CHAIN_DIS=1)" enabled]
if {$lock ne ""} {
    _p "Debug lock (LOCK.DBG)" [_onoff [_bit $lock $::Z7_LOCK_DBG] "LOCKED — CTRL(debug) frozen until POR (no register reopen)" "open — debug enables WRITABLE (reopen possible)"]
}

# ---- 5. CRYPTO / AES ----
echo " (5) CRYPTO"
_p "PL AES engine (AES_EN)" [_onoff [expr {($ctrl & $::Z7_CTRL_AES_EN) == $::Z7_CTRL_AES_EN}] "ON (111)" "off (000 / dev)"]
_p "AES key source (FUSE)"  [_onoff [_bit $ctrl $::Z7_CTRL_AES_FUSE] "eFuse key" "BBRAM key"]
_p "SEU lockdown (SEU_EN)"   [_onoff [_bit $ctrl $::Z7_CTRL_SEU_EN] armed off]

# ---- 6. CONFIG LOCK & TRUSTZONE ----
echo " (6) CONFIG LOCK & TRUSTZONE"
if {$locksta ne ""} { _p "SLCR write-protect" [_onoff [_bit $locksta 0x1] "LOCKED" "unlocked (sys-ctrl regs writable)"] }
if {$apuctl ne ""} {
    _p "APU CFGSDISABLE"  [_onoff [_bit $apuctl $::Z7_APU_CFGSDISABLE] "SET — sys-ctrl + GIC writes locked (POR-clear)" "clear"]
    _p "APU CP15SDISABLE" [_onoff [expr {($apuctl & $::Z7_APU_CP15SDIS) != 0}] "SET — CP15 writes locked per-core (POR-clear)" "clear"]
}
if {$tzdma ne ""} { _p "DMAC TrustZone (TZ_DMA_NS)" [_onoff [_bit $tzdma 0x1] "NON-SECURE" "secure"] }
if {$tzper ne ""} { _p "DMAC peripheral TZ" [format "TZ_DMA_PERIPH_NS = 0x%x (per-channel NS bits)" [expr {$tzper & 0xf}]] }

# ---- VERDICT ----
echo "----------------------------------------------------------------"
set hardened 0
if {$sec} { set hardened 1 }
if {$status ne "" && ([_bit $status $::Z7_STAT_EFUSE_SEC_EN] || [_bit $status $::Z7_STAT_EFUSE_JTAGDIS])} { set hardened 1 }
if {[expr {($ctrl & $::Z7_CTRL_DAP_EN) != $::Z7_CTRL_DAP_EN}]} { set hardened 1 }
if {$lock ne "" && [_bit $lock $::Z7_LOCK_DBG]} { set hardened 1 }
echo " VERDICT: [_onoff $hardened {HARDENING PRESENT — see the ON/BLOWN/LOCKED lines + the reopen lever} {ALL-OPEN dev baseline — DAP+debug on, non-secure boot, no eFuse hardening}]"
echo "================================================================"
