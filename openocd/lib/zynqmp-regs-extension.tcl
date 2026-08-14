# zynqmp-regs-extension.tcl — hand-verified register layouts for registers
# that Xilinx QEMU does not model.
#
# Sourced AFTER lib/zynqmp-regs-qemu.tcl so it extends the same ::QEMU_REGS
# dict. Use sparingly — every entry here is a maintenance liability because
# it doesn't auto-regenerate. Each entry MUST cite its source.
#
# Workflow when adding an entry here:
#   1. Search QEMU first (regenerate-qemu-regs.py covers everything QEMU
#      models). If it's there, the auto-generated file already has it.
#   2. If not in QEMU, search u-boot-xlnx (arch/arm/mach-zynqmp/include/),
#      embeddedsw FSBL (lib/sw_apps/zynqmp_fsbl/src/xfsbl_hw.h),
#      embeddedsw xilskey (lib/sw_services/xilskey/src/xilskey_eps_zynqmp_hw.h),
#      and the Versal/MPSoC TRMs (UG1085/UG1087) if you have them.
#   3. Add the entry below with a "source:" line citing exactly where you
#      verified each field. If the register is truly reserved, mark it
#      with an empty fields list and a "reserved: true" attribute in the
#      notes — and consider removing the dump_reg_qemu call from
#      enumerate.tcl entirely.

# CSU.JTAG_CHAIN_CFG at 0xFFCA0030 (corrected 2026-06-10; was mislabeled JTAG_CHAIN_STATUS_WR
# with an opaque SETUP[1:0]). Authoritative: zynqmp_pmufw/src/csu.h:754-764 — this is the JTAG
# chain-link CONFIG register: SSSS_LINK_ARM_DAP (bit 1) and SSSS_LINK_PL_TAP (bit 0) link the ARM
# DAP / PL TAP into the physical scan chain (relevant to the PMU-BSCAN-TAP unlock path).
dict set ::QEMU_REGS [expr {int(0xFFCA0030)}] [dict create \
    name    JTAG_CHAIN_CFG \
    block   CSU \
    fields  [list \
        [list SSSS_LINK_ARM_DAP 1 1] \
        [list SSSS_LINK_PL_TAP 0 0] \
    ]]


# ---------------------------------------------------------------------------
# LPD_SLCR — Low-Power Domain System-Level Control Registers, base 0xFF410000.
#
# Source: github.com/Xilinx/embeddedsw lib/sw_apps/zynqmp_pmufw/src/lpd_slcr.h
# Defines LPD_SLCR_BASEADDR=0xFF410000, WPROT0@+0x0, CTRL@+0x4 with
# SLVERR_ENABLE [bit 0], ISR@+0x8 with ADDR_DECODE_ERR [bit 0], IMR@+0xC.
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFF410000)}] [dict create \
    name    WPROT0 \
    block   LPD_SLCR \
    fields  [list \
        [list ACTIVE 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFF410004)}] [dict create \
    name    CTRL \
    block   LPD_SLCR \
    fields  [list \
        [list SLVERR_ENABLE 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFF410008)}] [dict create \
    name    ISR \
    block   LPD_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFF41000C)}] [dict create \
    name    IMR \
    block   LPD_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]


# ---------------------------------------------------------------------------
# FPD_SLCR — Full-Power Domain SLCR, base 0xFD610000.
#
# Source: UG1085 (ZynqMP TRM) Chapter 36 documents FPD_SLCR at 0xFD610000
# with the same WPROT0/CTRL/ISR/IMR layout as LPD_SLCR. Xilinx PMU FW source
# doesn't expose an fpd_slcr.h because PMU FW (which lives in LPD) doesn't
# touch FPD SLCR directly — coordination is via IPI to the APU. Layout here
# is by analogy with LPD_SLCR per UG1085.
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFD610000)}] [dict create \
    name    WPROT0 \
    block   FPD_SLCR \
    fields  [list \
        [list ACTIVE 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFD610004)}] [dict create \
    name    CTRL \
    block   FPD_SLCR \
    fields  [list \
        [list SLVERR_ENABLE 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFD610008)}] [dict create \
    name    ISR \
    block   FPD_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFD61000C)}] [dict create \
    name    IMR \
    block   FPD_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]


# ---------------------------------------------------------------------------
# IOU_SECURE_SLCR — IOU Secure SLCR, base 0xFF240000.
# Controls per-peripheral AXI protection levels (AWPROT / ARPROT) for GEM and
# SD masters — i.e. whether the peripheral master issues secure or non-secure
# AXI transactions. Important security signal: configures whether peripheral
# DMA traffic is allowed through XPPU/XMPU.
#
# Source: github.com/Xilinx/embeddedsw lib/sw_apps/zynqmp_pmufw/src/iou_secure_slcr.h
# Confirms base + bit positions for GEM0..3 and SD0/1 AXI protection fields.
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFF240000)}] [dict create \
    name    IOU_AXI_WPRTCN \
    block   IOU_SECURE_SLCR \
    fields  [list \
        [list SD1_AXI_AWPROT 21 19] \
        [list SD0_AXI_AWPROT 18 16] \
        [list GEM3_AXI_AWPROT 11 9] \
        [list GEM2_AXI_AWPROT 8 6] \
        [list GEM1_AXI_AWPROT 5 3] \
        [list GEM0_AXI_AWPROT 2 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFF240004)}] [dict create \
    name    IOU_AXI_RPRTCN \
    block   IOU_SECURE_SLCR \
    fields  [list \
        [list SD1_AXI_ARPROT 21 19] \
        [list SD0_AXI_ARPROT 18 16] \
        [list GEM3_AXI_ARPROT 11 9] \
        [list GEM2_AXI_ARPROT 8 6] \
        [list GEM1_AXI_ARPROT 5 3] \
        [list GEM0_AXI_ARPROT 2 0] \
    ]]


# ---------------------------------------------------------------------------
# LPD_SLCR_SECURE — LPD Secure SLCR, base 0xFF4B0000.
# Hosts TrustZone gating bits for select LPD peripherals.
#
# Source: github.com/Xilinx/embeddedsw lib/sw_apps/zynqmp_pmufw/src/lpd_slcr_secure.h
# Confirms base + SLCR_USB @ +0x34 with TZ_USB3_0 [bit 0], TZ_USB3_1 [bit 1].
# When set, that USB controller issues SECURE AXI transactions; when clear,
# NON-SECURE. Drives XPPU/XMPU permission decisions for USB DMA traffic.
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFF4B0034)}] [dict create \
    name    SLCR_USB \
    block   LPD_SLCR_SECURE \
    fields  [list \
        [list TZ_USB3_1 1 1] \
        [list TZ_USB3_0 0 0] \
    ]]


# ---------------------------------------------------------------------------
# CSU PUF (Physically Unclonable Function) controller
# 
# Identified 2026-05-28 via Xilinx xilskey header (xilskey_eps_zynqmp_hw.h).
# 11 registers occupying 0xFFCA4000-0xFFCA4814 (normal at +0x000-+0x018,
# trim/test-mode at +0x800-+0x814). All registers freely writable from
# DAP NS — no master-aware filter.
#
# Source: github.com/Xilinx/embeddedsw/lib/sw_services/xilskey/src/xilskey_eps_zynqmp_hw.h
# Field semantics: deduced from xilskey_eps_zynqmp_puf.c usage patterns +
# UG1085 PUF chapter. Field bits not exhaustively verified — annotate
# carefully if you rely on them.
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFFCA4000)}] [dict create \
    name    CSU_PUF_CMD \
    block   CSU_PUF \
    fields  [list \
        [list REGENERATION 2 2] \
        [list REGISTRATION 0 0] \
    ]]
# CSU_PUF_CMD is a command-opcode register (corrected 2026-06-10; was bogus SHUT/RESET/REGISTER/
# REGEN bits). xilskey: REGISTRATION=opcode 1 (bit 0), REGENERATION=opcode 4 (bit 2)
# (xilskey_eps_zynqmp_puf.h:63-64, written at puf.c:670/776). The shutter is a SEPARATE register
# (CSU_PUF_SHUT @0xFFCA400C); there is no SHUT/RESET/REGISTER bit in CMD.

dict set ::QEMU_REGS [expr {int(0xFFCA4004)}] [dict create \
    name    CSU_PUF_CFG0 \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA4008)}] [dict create \
    name    CSU_PUF_CFG1 \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA400C)}] [dict create \
    name    CSU_PUF_SHUT \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA4010)}] [dict create \
    name    CSU_PUF_STATUS \
    block   CSU_PUF \
    fields  [list \
        [list OVERFLOW 29 28] \
        [list AUX 27 4] \
        [list KEY_RDY 3 3] \
        [list SYN_WRD_RDY 0 0] \
    ]]
# CSU_PUF_STATUS corrected 2026-06-10 (was bogus OPERATION_DONE[1]/BUSY[0]). xilskey masks:
# SYN_WRD_RDY=0x1 (bit0, syndrome-word-ready — active-high, NOT "busy"), KEY_RDY=0x8 (bit3),
# AUX=0x0FFFFFF0 (bits 4-27), OVERFLOW=0x30000000 (bits 28-29) (xilskey_eps_zynqmp_hw.h:1228-1231).

dict set ::QEMU_REGS [expr {int(0xFFCA4018)}] [dict create \
    name    CSU_PUF_WORD \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA4804)}] [dict create \
    name    CSU_PUF_TM_STATUS \
    block   CSU_PUF \
    fields  [list \
        [list DN 0 0] \
    ]]

dict set ::QEMU_REGS [expr {int(0xFFCA4808)}] [dict create \
    name    CSU_PUF_TM_UL \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA480C)}] [dict create \
    name    CSU_PUF_TM_LL \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA4810)}] [dict create \
    name    CSU_PUF_TM_SW \
    block   CSU_PUF \
    fields  [list]]

dict set ::QEMU_REGS [expr {int(0xFFCA4814)}] [dict create \
    name    CSU_PUF_TM_TR \
    block   CSU_PUF \
    fields  [list]]


# ---------------------------------------------------------------------------
# CSU_TAMPER_14 — the 15th tamper-source configuration register
#
# Identified 2026-05-28 via Xilinx csu.h (zynqmp_pmufw/src/csu.h). xilskey
# lists CSU_TAMPER_0..CSU_TAMPER_14; QEMU regs file only has CSU_TAMPER_0.
# Each tamper register has the same bit-field layout (response bits).
# ---------------------------------------------------------------------------

dict set ::QEMU_REGS [expr {int(0xFFCA503C)}] [dict create \
    name    CSU_TAMPER_14 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]
