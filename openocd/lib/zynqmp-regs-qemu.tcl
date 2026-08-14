# zynqmp-regs-qemu.tcl — AUTO-GENERATED. DO NOT EDIT BY HAND.
#
# Single source of truth for ZynqMP register layouts, extracted
# from Xilinx QEMU register-model headers.
#
# Regenerate with: python3 tools/regenerate-qemu-regs.py
#
# Sources:
#   /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_crf.c
#   /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_crl.c
#   /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_pmu_global.c
#   /opt/xilinx/qemu/hw/misc/csu_core.c
#   /opt/xilinx/qemu/hw/nvram/xlnx-zynqmp-efuse.c
#   /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_apu_ctrl.c
#   /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_rpu_ctrl.c
#   /opt/xilinx/qemu/hw/misc/zynqmp-iou-slcr.c
#   /opt/xilinx/qemu/include/hw/misc/xlnx-xppu.h
#   /opt/xilinx/qemu/hw/intc/xlnx-zynqmp-ipi.c
#   /opt/xilinx/qemu/include/hw/misc/xlnx-xmpu.h
#   /opt/xilinx/qemu/include/hw/misc/xlnx-xmpu.h

# Schema: dict ::QEMU_REGS keyed by absolute address (decimal int).
# Each value is a dict:
#   name    QEMU REG32 name (no block prefix)
#   block   block this register belongs to
#   fields  list of {field_name msb lsb} tuples (MSB-first order)

set ::QEMU_REGS [dict create]

# APU.ERR_CTRL
dict set ::QEMU_REGS 4250664960 [dict create \
    name    ERR_CTRL \
    block   APU \
    fields  [list \
        [list PSLVERR 0 0] \
    ]]

# APU.ISR
dict set ::QEMU_REGS 4250664976 [dict create \
    name    ISR \
    block   APU \
    fields  [list \
        [list INV_APB 0 0] \
    ]]

# APU.IMR
dict set ::QEMU_REGS 4250664980 [dict create \
    name    IMR \
    block   APU \
    fields  [list \
        [list INV_APB 0 0] \
    ]]

# APU.IEN
dict set ::QEMU_REGS 4250664984 [dict create \
    name    IEN \
    block   APU \
    fields  [list \
        [list INV_APB 0 0] \
    ]]

# APU.IDS
dict set ::QEMU_REGS 4250664988 [dict create \
    name    IDS \
    block   APU \
    fields  [list \
        [list INV_APB 0 0] \
    ]]

# APU.CONFIG_0
dict set ::QEMU_REGS 4250664992 [dict create \
    name    CONFIG_0 \
    block   APU \
    fields  [list \
        [list CFGTE 27 24] \
        [list CFGEND 19 16] \
        [list VINITHI 11 8] \
        [list AA64NAA32 3 0] \
    ]]

# APU.CONFIG_1
dict set ::QEMU_REGS 4250664996 [dict create \
    name    CONFIG_1 \
    block   APU \
    fields  [list \
        [list L2RSTDISABLE 29 29] \
        [list L1RSTDISABLE 28 28] \
        [list CP15DISABLE 3 0] \
    ]]

# APU.RVBARADDR0L
dict set ::QEMU_REGS 4250665024 [dict create \
    name    RVBARADDR0L \
    block   APU \
    fields  [list \
        [list ADDR 31 2] \
    ]]

# APU.RVBARADDR0H
dict set ::QEMU_REGS 4250665028 [dict create \
    name    RVBARADDR0H \
    block   APU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# APU.RVBARADDR1L
dict set ::QEMU_REGS 4250665032 [dict create \
    name    RVBARADDR1L \
    block   APU \
    fields  [list \
        [list ADDR 31 2] \
    ]]

# APU.RVBARADDR1H
dict set ::QEMU_REGS 4250665036 [dict create \
    name    RVBARADDR1H \
    block   APU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# APU.RVBARADDR2L
dict set ::QEMU_REGS 4250665040 [dict create \
    name    RVBARADDR2L \
    block   APU \
    fields  [list \
        [list ADDR 31 2] \
    ]]

# APU.RVBARADDR2H
dict set ::QEMU_REGS 4250665044 [dict create \
    name    RVBARADDR2H \
    block   APU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# APU.RVBARADDR3L
dict set ::QEMU_REGS 4250665048 [dict create \
    name    RVBARADDR3L \
    block   APU \
    fields  [list \
        [list ADDR 31 2] \
    ]]

# APU.RVBARADDR3H
dict set ::QEMU_REGS 4250665052 [dict create \
    name    RVBARADDR3H \
    block   APU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# APU.ACE_CTRL
dict set ::QEMU_REGS 4250665056 [dict create \
    name    ACE_CTRL \
    block   APU \
    fields  [list \
        [list AWQOS 19 16] \
        [list ARQOS 3 0] \
    ]]

# APU.SNOOP_CTRL
dict set ::QEMU_REGS 4250665088 [dict create \
    name    SNOOP_CTRL \
    block   APU \
    fields  [list \
        [list ACE_INACT 4 4] \
        [list ACP_INACT 0 0] \
    ]]

# APU.PWRCTL
dict set ::QEMU_REGS 4250665104 [dict create \
    name    PWRCTL \
    block   APU \
    fields  [list \
        [list CLREXMONREQ 17 17] \
        [list L2FLUSHREQ 16 16] \
        [list CPUPWRDWNREQ 3 0] \
    ]]

# APU.PWRSTAT
dict set ::QEMU_REGS 4250665108 [dict create \
    name    PWRSTAT \
    block   APU \
    fields  [list \
        [list CLREXMONACK 17 17] \
        [list L2FLUSHDONE 16 16] \
        [list DBGNOPWRDWN 3 0] \
    ]]

# CRF_APB.ERR_CTRL
dict set ::QEMU_REGS 4246339584 [dict create \
    name    ERR_CTRL \
    block   CRF_APB \
    fields  [list \
        [list SLVERR_ENABLE 0 0] \
    ]]

# CRF_APB.IR_STATUS
dict set ::QEMU_REGS 4246339588 [dict create \
    name    IR_STATUS \
    block   CRF_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRF_APB.IR_MASK
dict set ::QEMU_REGS 4246339592 [dict create \
    name    IR_MASK \
    block   CRF_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRF_APB.IR_ENABLE
dict set ::QEMU_REGS 4246339596 [dict create \
    name    IR_ENABLE \
    block   CRF_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRF_APB.IR_DISABLE
dict set ::QEMU_REGS 4246339600 [dict create \
    name    IR_DISABLE \
    block   CRF_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRF_APB.CRF_WPROT
dict set ::QEMU_REGS 4246339612 [dict create \
    name    CRF_WPROT \
    block   CRF_APB \
    fields  [list \
        [list ACTIVE 0 0] \
    ]]

# CRF_APB.APLL_CTRL
dict set ::QEMU_REGS 4246339616 [dict create \
    name    APLL_CTRL \
    block   CRF_APB \
    fields  [list \
        [list POST_SRC 26 24] \
        [list PRE_SRC 22 20] \
        [list CLKOUTDIV 17 17] \
        [list DIV2 16 16] \
        [list FBDIV 14 8] \
        [list BYPASS 3 3] \
        [list RESET 0 0] \
    ]]

# CRF_APB.APLL_CFG
dict set ::QEMU_REGS 4246339620 [dict create \
    name    APLL_CFG \
    block   CRF_APB \
    fields  [list \
        [list LOCK_DLY 31 25] \
        [list LOCK_CNT 22 13] \
        [list LFHF 11 10] \
        [list CP 8 5] \
        [list RES 3 0] \
    ]]

# CRF_APB.APLL_FRAC_CFG
dict set ::QEMU_REGS 4246339624 [dict create \
    name    APLL_FRAC_CFG \
    block   CRF_APB \
    fields  [list \
        [list ENABLED 31 31] \
        [list SEED 24 22] \
        [list ALGRTHM 19 19] \
        [list ORDER 18 18] \
        [list DATA 15 0] \
    ]]

# CRF_APB.DPLL_CTRL
dict set ::QEMU_REGS 4246339628 [dict create \
    name    DPLL_CTRL \
    block   CRF_APB \
    fields  [list \
        [list POST_SRC 26 24] \
        [list PRE_SRC 22 20] \
        [list CLKOUTDIV 17 17] \
        [list DIV2 16 16] \
        [list FBDIV 14 8] \
        [list BYPASS 3 3] \
        [list RESET 0 0] \
    ]]

# CRF_APB.DPLL_CFG
dict set ::QEMU_REGS 4246339632 [dict create \
    name    DPLL_CFG \
    block   CRF_APB \
    fields  [list \
        [list LOCK_DLY 31 25] \
        [list LOCK_CNT 22 13] \
        [list LFHF 11 10] \
        [list CP 8 5] \
        [list RES 3 0] \
    ]]

# CRF_APB.DPLL_FRAC_CFG
dict set ::QEMU_REGS 4246339636 [dict create \
    name    DPLL_FRAC_CFG \
    block   CRF_APB \
    fields  [list \
        [list ENABLED 31 31] \
        [list SEED 24 22] \
        [list ALGRTHM 19 19] \
        [list ORDER 18 18] \
        [list DATA 15 0] \
    ]]

# CRF_APB.VPLL_CTRL
dict set ::QEMU_REGS 4246339640 [dict create \
    name    VPLL_CTRL \
    block   CRF_APB \
    fields  [list \
        [list POST_SRC 26 24] \
        [list PRE_SRC 22 20] \
        [list CLKOUTDIV 17 17] \
        [list DIV2 16 16] \
        [list FBDIV 14 8] \
        [list BYPASS 3 3] \
        [list RESET 0 0] \
    ]]

# CRF_APB.VPLL_CFG
dict set ::QEMU_REGS 4246339644 [dict create \
    name    VPLL_CFG \
    block   CRF_APB \
    fields  [list \
        [list LOCK_DLY 31 25] \
        [list LOCK_CNT 22 13] \
        [list LFHF 11 10] \
        [list CP 8 5] \
        [list RES 3 0] \
    ]]

# CRF_APB.VPLL_FRAC_CFG
dict set ::QEMU_REGS 4246339648 [dict create \
    name    VPLL_FRAC_CFG \
    block   CRF_APB \
    fields  [list \
        [list ENABLED 31 31] \
        [list SEED 24 22] \
        [list ALGRTHM 19 19] \
        [list ORDER 18 18] \
        [list DATA 15 0] \
    ]]

# CRF_APB.PLL_STATUS
dict set ::QEMU_REGS 4246339652 [dict create \
    name    PLL_STATUS \
    block   CRF_APB \
    fields  [list \
        [list VPLL_STABLE 5 5] \
        [list DPLL_STABLE 4 4] \
        [list APLL_STABLE 3 3] \
        [list VPLL_LOCK 2 2] \
        [list DPLL_LOCK 1 1] \
        [list APLL_LOCK 0 0] \
    ]]

# CRF_APB.APLL_TO_LPD_CTRL
dict set ::QEMU_REGS 4246339656 [dict create \
    name    APLL_TO_LPD_CTRL \
    block   CRF_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
    ]]

# CRF_APB.DPLL_TO_LPD_CTRL
dict set ::QEMU_REGS 4246339660 [dict create \
    name    DPLL_TO_LPD_CTRL \
    block   CRF_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
    ]]

# CRF_APB.VPLL_TO_LPD_CTRL
dict set ::QEMU_REGS 4246339664 [dict create \
    name    VPLL_TO_LPD_CTRL \
    block   CRF_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
    ]]

# CRF_APB.ACPU_CTRL
dict set ::QEMU_REGS 4246339680 [dict create \
    name    ACPU_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT_HALF 25 25] \
        [list CLKACT_FULL 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DBG_TRACE_CTRL
dict set ::QEMU_REGS 4246339684 [dict create \
    name    DBG_TRACE_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DBG_FPD_CTRL
dict set ::QEMU_REGS 4246339688 [dict create \
    name    DBG_FPD_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DP_VIDEO_REF_CTRL
dict set ::QEMU_REGS 4246339696 [dict create \
    name    DP_VIDEO_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DP_AUDIO_REF_CTRL
dict set ::QEMU_REGS 4246339700 [dict create \
    name    DP_AUDIO_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DP_STC_REF_CTRL
dict set ::QEMU_REGS 4246339708 [dict create \
    name    DP_STC_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DDR_CTRL
dict set ::QEMU_REGS 4246339712 [dict create \
    name    DDR_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.GPU_REF_CTRL
dict set ::QEMU_REGS 4246339716 [dict create \
    name    GPU_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list PP1_CLKACT 26 26] \
        [list PP0_CLKACT 25 25] \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.SATA_REF_CTRL
dict set ::QEMU_REGS 4246339744 [dict create \
    name    SATA_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.PCIE_REF_CTRL
dict set ::QEMU_REGS 4246339764 [dict create \
    name    PCIE_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.GDMA_REF_CTRL
dict set ::QEMU_REGS 4246339768 [dict create \
    name    GDMA_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DPDMA_REF_CTRL
dict set ::QEMU_REGS 4246339772 [dict create \
    name    DPDMA_REF_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.TOPSW_MAIN_CTRL
dict set ::QEMU_REGS 4246339776 [dict create \
    name    TOPSW_MAIN_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.TOPSW_LSBUS_CTRL
dict set ::QEMU_REGS 4246339780 [dict create \
    name    TOPSW_LSBUS_CTRL \
    block   CRF_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.DBG_TSTMP_CTRL
dict set ::QEMU_REGS 4246339832 [dict create \
    name    DBG_TSTMP_CTRL \
    block   CRF_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRF_APB.RST_FPD_TOP
dict set ::QEMU_REGS 4246339840 [dict create \
    name    RST_FPD_TOP \
    block   CRF_APB \
    fields  [list \
        [list PCIE_CFG_RESET 19 19] \
        [list PCIE_BRIDGE_RESET 18 18] \
        [list PCIE_CTRL_RESET 17 17] \
        [list DP_RESET 16 16] \
        [list SWDT_RESET 15 15] \
        [list AFI_FM5_RESET 12 12] \
        [list AFI_FM4_RESET 11 11] \
        [list AFI_FM3_RESET 10 10] \
        [list AFI_FM2_RESET 9 9] \
        [list AFI_FM1_RESET 8 8] \
        [list AFI_FM0_RESET 7 7] \
        [list GDMA_RESET 6 6] \
        [list GPU_PP1_RESET 5 5] \
        [list GPU_PP0_RESET 4 4] \
        [list GPU_RESET 3 3] \
        [list GT_RESET 2 2] \
        [list SATA_RESET 1 1] \
    ]]

# CRF_APB.RST_FPD_APU
dict set ::QEMU_REGS 4246339844 [dict create \
    name    RST_FPD_APU \
    block   CRF_APB \
    fields  [list \
        [list ACPU3_PWRON_RESET 13 13] \
        [list ACPU2_PWRON_RESET 12 12] \
        [list ACPU1_PWRON_RESET 11 11] \
        [list ACPU0_PWRON_RESET 10 10] \
        [list APU_L2_RESET 8 8] \
        [list ACPU3_RESET 3 3] \
        [list ACPU2_RESET 2 2] \
        [list ACPU1_RESET 1 1] \
        [list ACPU0_RESET 0 0] \
    ]]

# CRF_APB.RST_DDR_SS
dict set ::QEMU_REGS 4246339848 [dict create \
    name    RST_DDR_SS \
    block   CRF_APB \
    fields  [list \
        [list DDR_RESET 3 3] \
        [list APM_RESET 2 2] \
    ]]

# CRL_APB.ERR_CTRL
dict set ::QEMU_REGS 4284350464 [dict create \
    name    ERR_CTRL \
    block   CRL_APB \
    fields  [list \
        [list SLVERR_ENABLE 0 0] \
    ]]

# CRL_APB.IR_STATUS
dict set ::QEMU_REGS 4284350468 [dict create \
    name    IR_STATUS \
    block   CRL_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRL_APB.IR_MASK
dict set ::QEMU_REGS 4284350472 [dict create \
    name    IR_MASK \
    block   CRL_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRL_APB.IR_ENABLE
dict set ::QEMU_REGS 4284350476 [dict create \
    name    IR_ENABLE \
    block   CRL_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRL_APB.IR_DISABLE
dict set ::QEMU_REGS 4284350480 [dict create \
    name    IR_DISABLE \
    block   CRL_APB \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# CRL_APB.CRL_WPROT
dict set ::QEMU_REGS 4284350492 [dict create \
    name    CRL_WPROT \
    block   CRL_APB \
    fields  [list \
        [list ACTIVE 0 0] \
    ]]

# CRL_APB.IOPLL_CTRL
dict set ::QEMU_REGS 4284350496 [dict create \
    name    IOPLL_CTRL \
    block   CRL_APB \
    fields  [list \
        [list POST_SRC 26 24] \
        [list PRE_SRC 22 20] \
        [list CLKOUTDIV 17 17] \
        [list DIV2 16 16] \
        [list FBDIV 14 8] \
        [list BYPASS 3 3] \
        [list RESET 0 0] \
    ]]

# CRL_APB.IOPLL_CFG
dict set ::QEMU_REGS 4284350500 [dict create \
    name    IOPLL_CFG \
    block   CRL_APB \
    fields  [list \
        [list LOCK_DLY 31 25] \
        [list LOCK_CNT 22 13] \
        [list LFHF 11 10] \
        [list CP 8 5] \
        [list RES 3 0] \
    ]]

# CRL_APB.IOPLL_FRAC_CFG
dict set ::QEMU_REGS 4284350504 [dict create \
    name    IOPLL_FRAC_CFG \
    block   CRL_APB \
    fields  [list \
        [list ENABLED 31 31] \
        [list SEED 24 22] \
        [list ALGRTHM 19 19] \
        [list ORDER 18 18] \
        [list DATA 15 0] \
    ]]

# CRL_APB.RPLL_CTRL
dict set ::QEMU_REGS 4284350512 [dict create \
    name    RPLL_CTRL \
    block   CRL_APB \
    fields  [list \
        [list POST_SRC 26 24] \
        [list PRE_SRC 22 20] \
        [list CLKOUTDIV 17 17] \
        [list DIV2 16 16] \
        [list FBDIV 14 8] \
        [list BYPASS 3 3] \
        [list RESET 0 0] \
    ]]

# CRL_APB.RPLL_CFG
dict set ::QEMU_REGS 4284350516 [dict create \
    name    RPLL_CFG \
    block   CRL_APB \
    fields  [list \
        [list LOCK_DLY 31 25] \
        [list LOCK_CNT 22 13] \
        [list LFHF 11 10] \
        [list CP 8 5] \
        [list RES 3 0] \
    ]]

# CRL_APB.RPLL_FRAC_CFG
dict set ::QEMU_REGS 4284350520 [dict create \
    name    RPLL_FRAC_CFG \
    block   CRL_APB \
    fields  [list \
        [list ENABLED 31 31] \
        [list SEED 24 22] \
        [list ALGRTHM 19 19] \
        [list ORDER 18 18] \
        [list DATA 15 0] \
    ]]

# CRL_APB.PLL_STATUS
dict set ::QEMU_REGS 4284350528 [dict create \
    name    PLL_STATUS \
    block   CRL_APB \
    fields  [list \
        [list RPLL_STABLE 4 4] \
        [list IOPLL_STABLE 3 3] \
        [list RPLL_LOCK 1 1] \
        [list IOPLL_LOCK 0 0] \
    ]]

# CRL_APB.IOPLL_TO_FPD_CTRL
dict set ::QEMU_REGS 4284350532 [dict create \
    name    IOPLL_TO_FPD_CTRL \
    block   CRL_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
    ]]

# CRL_APB.RPLL_TO_FPD_CTRL
dict set ::QEMU_REGS 4284350536 [dict create \
    name    RPLL_TO_FPD_CTRL \
    block   CRL_APB \
    fields  [list \
        [list DIVISOR0 13 8] \
    ]]

# CRL_APB.USB3_DUAL_REF_CTRL
dict set ::QEMU_REGS 4284350540 [dict create \
    name    USB3_DUAL_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.GEM0_REF_CTRL
dict set ::QEMU_REGS 4284350544 [dict create \
    name    GEM0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list RX_CLKACT 26 26] \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.GEM1_REF_CTRL
dict set ::QEMU_REGS 4284350548 [dict create \
    name    GEM1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list RX_CLKACT 26 26] \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.GEM2_REF_CTRL
dict set ::QEMU_REGS 4284350552 [dict create \
    name    GEM2_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list RX_CLKACT 26 26] \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.GEM3_REF_CTRL
dict set ::QEMU_REGS 4284350556 [dict create \
    name    GEM3_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list RX_CLKACT 26 26] \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.USB0_BUS_REF_CTRL
dict set ::QEMU_REGS 4284350560 [dict create \
    name    USB0_BUS_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.USB1_BUS_REF_CTRL
dict set ::QEMU_REGS 4284350564 [dict create \
    name    USB1_BUS_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 25 25] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.QSPI_REF_CTRL
dict set ::QEMU_REGS 4284350568 [dict create \
    name    QSPI_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.SDIO0_REF_CTRL
dict set ::QEMU_REGS 4284350572 [dict create \
    name    SDIO0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.SDIO1_REF_CTRL
dict set ::QEMU_REGS 4284350576 [dict create \
    name    SDIO1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.UART0_REF_CTRL
dict set ::QEMU_REGS 4284350580 [dict create \
    name    UART0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.UART1_REF_CTRL
dict set ::QEMU_REGS 4284350584 [dict create \
    name    UART1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.SPI0_REF_CTRL
dict set ::QEMU_REGS 4284350588 [dict create \
    name    SPI0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.SPI1_REF_CTRL
dict set ::QEMU_REGS 4284350592 [dict create \
    name    SPI1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.CAN0_REF_CTRL
dict set ::QEMU_REGS 4284350596 [dict create \
    name    CAN0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.CAN1_REF_CTRL
dict set ::QEMU_REGS 4284350600 [dict create \
    name    CAN1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.CPU_R5_CTRL
dict set ::QEMU_REGS 4284350608 [dict create \
    name    CPU_R5_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT_CORE 25 25] \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.IOU_SWITCH_CTRL
dict set ::QEMU_REGS 4284350620 [dict create \
    name    IOU_SWITCH_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.CSU_PLL_CTRL
dict set ::QEMU_REGS 4284350624 [dict create \
    name    CSU_PLL_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PCAP_CTRL
dict set ::QEMU_REGS 4284350628 [dict create \
    name    PCAP_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.LPD_SWITCH_CTRL
dict set ::QEMU_REGS 4284350632 [dict create \
    name    LPD_SWITCH_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.LPD_LSBUS_CTRL
dict set ::QEMU_REGS 4284350636 [dict create \
    name    LPD_LSBUS_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.DBG_LPD_CTRL
dict set ::QEMU_REGS 4284350640 [dict create \
    name    DBG_LPD_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.NAND_REF_CTRL
dict set ::QEMU_REGS 4284350644 [dict create \
    name    NAND_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.ADMA_REF_CTRL
dict set ::QEMU_REGS 4284350648 [dict create \
    name    ADMA_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PL0_REF_CTRL
dict set ::QEMU_REGS 4284350656 [dict create \
    name    PL0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PL1_REF_CTRL
dict set ::QEMU_REGS 4284350660 [dict create \
    name    PL1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PL2_REF_CTRL
dict set ::QEMU_REGS 4284350664 [dict create \
    name    PL2_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PL3_REF_CTRL
dict set ::QEMU_REGS 4284350668 [dict create \
    name    PL3_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.PL0_THR_CTRL
dict set ::QEMU_REGS 4284350672 [dict create \
    name    PL0_THR_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CURR_VAL 31 16] \
        [list RUNNING 15 15] \
        [list CPU_START 1 1] \
        [list CNT_RST 0 0] \
    ]]

# CRL_APB.PL0_THR_CNT
dict set ::QEMU_REGS 4284350676 [dict create \
    name    PL0_THR_CNT \
    block   CRL_APB \
    fields  [list \
        [list LAST_CNT 15 0] \
    ]]

# CRL_APB.PL1_THR_CTRL
dict set ::QEMU_REGS 4284350680 [dict create \
    name    PL1_THR_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CURR_VAL 31 16] \
        [list RUNNING 15 15] \
        [list CPU_START 1 1] \
        [list CNT_RST 0 0] \
    ]]

# CRL_APB.PL1_THR_CNT
dict set ::QEMU_REGS 4284350684 [dict create \
    name    PL1_THR_CNT \
    block   CRL_APB \
    fields  [list \
        [list LAST_CNT 15 0] \
    ]]

# CRL_APB.PL2_THR_CTRL
dict set ::QEMU_REGS 4284350688 [dict create \
    name    PL2_THR_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CURR_VAL 31 16] \
        [list RUNNING 15 15] \
        [list CPU_START 1 1] \
        [list CNT_RST 0 0] \
    ]]

# CRL_APB.PL2_THR_CNT
dict set ::QEMU_REGS 4284350692 [dict create \
    name    PL2_THR_CNT \
    block   CRL_APB \
    fields  [list \
        [list LAST_CNT 15 0] \
    ]]

# CRL_APB.PL3_THR_CTRL
dict set ::QEMU_REGS 4284350696 [dict create \
    name    PL3_THR_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CURR_VAL 31 16] \
        [list RUNNING 15 15] \
        [list CPU_START 1 1] \
        [list CNT_RST 0 0] \
    ]]

# CRL_APB.PL3_THR_CNT
dict set ::QEMU_REGS 4284350716 [dict create \
    name    PL3_THR_CNT \
    block   CRL_APB \
    fields  [list \
        [list LAST_CNT 15 0] \
    ]]

# CRL_APB.GEM_TSU_REF_CTRL
dict set ::QEMU_REGS 4284350720 [dict create \
    name    GEM_TSU_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.DLL_REF_CTRL
dict set ::QEMU_REGS 4284350724 [dict create \
    name    DLL_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.AMS_REF_CTRL
dict set ::QEMU_REGS 4284350728 [dict create \
    name    AMS_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.I2C0_REF_CTRL
dict set ::QEMU_REGS 4284350752 [dict create \
    name    I2C0_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.I2C1_REF_CTRL
dict set ::QEMU_REGS 4284350756 [dict create \
    name    I2C1_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR1 21 16] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.TIMESTAMP_REF_CTRL
dict set ::QEMU_REGS 4284350760 [dict create \
    name    TIMESTAMP_REF_CTRL \
    block   CRL_APB \
    fields  [list \
        [list CLKACT 24 24] \
        [list DIVISOR0 13 8] \
        [list SRCSEL 2 0] \
    ]]

# CRL_APB.SAFTEY_CHK
dict set ::QEMU_REGS 4284350768 [dict create \
    name    SAFTEY_CHK \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CLKMON_STATUS
dict set ::QEMU_REGS 4284350784 [dict create \
    name    CLKMON_STATUS \
    block   CRL_APB \
    fields  [list \
        [list CNTA7_OVER_ERR 15 15] \
        [list MON7_ERR 14 14] \
        [list CNTA6_OVER_ERR 13 13] \
        [list MON6_ERR 12 12] \
        [list CNTA5_OVER_ERR 11 11] \
        [list MON5_ERR 10 10] \
        [list CNTA4_OVER_ERR 9 9] \
        [list MON4_ERR 8 8] \
        [list CNTA3_OVER_ERR 7 7] \
        [list MON3_ERR 6 6] \
        [list CNTA2_OVER_ERR 5 5] \
        [list MON2_ERR 4 4] \
        [list CNTA1_OVER_ERR 3 3] \
        [list MON1_ERR 2 2] \
        [list CNTA0_OVER_ERR 1 1] \
        [list MON0_ERR 0 0] \
    ]]

# CRL_APB.CLKMON_MASK
dict set ::QEMU_REGS 4284350788 [dict create \
    name    CLKMON_MASK \
    block   CRL_APB \
    fields  [list \
        [list CNTA7_OVER_ERR 15 15] \
        [list MON7_ERR 14 14] \
        [list CNTA6_OVER_ERR 13 13] \
        [list MON6_ERR 12 12] \
        [list CNTA5_OVER_ERR 11 11] \
        [list MON5_ERR 10 10] \
        [list CNTA4_OVER_ERR 9 9] \
        [list MON4_ERR 8 8] \
        [list CNTA3_OVER_ERR 7 7] \
        [list MON3_ERR 6 6] \
        [list CNTA2_OVER_ERR 5 5] \
        [list MON2_ERR 4 4] \
        [list CNTA1_OVER_ERR 3 3] \
        [list MON1_ERR 2 2] \
        [list CNTA0_OVER_ERR 1 1] \
        [list MON0_ERR 0 0] \
    ]]

# CRL_APB.CLKMON_ENABLE
dict set ::QEMU_REGS 4284350792 [dict create \
    name    CLKMON_ENABLE \
    block   CRL_APB \
    fields  [list \
        [list CNTA7_OVER_ERR 15 15] \
        [list MON7_ERR 14 14] \
        [list CNTA6_OVER_ERR 13 13] \
        [list MON6_ERR 12 12] \
        [list CNTA5_OVER_ERR 11 11] \
        [list MON5_ERR 10 10] \
        [list CNTA4_OVER_ERR 9 9] \
        [list MON4_ERR 8 8] \
        [list CNTA3_OVER_ERR 7 7] \
        [list MON3_ERR 6 6] \
        [list CNTA2_OVER_ERR 5 5] \
        [list MON2_ERR 4 4] \
        [list CNTA1_OVER_ERR 3 3] \
        [list MON1_ERR 2 2] \
        [list CNTA0_OVER_ERR 1 1] \
        [list MON0_ERR 0 0] \
    ]]

# CRL_APB.CLKMON_DISABLE
dict set ::QEMU_REGS 4284350796 [dict create \
    name    CLKMON_DISABLE \
    block   CRL_APB \
    fields  [list \
        [list CNTA7_OVER_ERR 15 15] \
        [list MON7_ERR 14 14] \
        [list CNTA6_OVER_ERR 13 13] \
        [list MON6_ERR 12 12] \
        [list CNTA5_OVER_ERR 11 11] \
        [list MON5_ERR 10 10] \
        [list CNTA4_OVER_ERR 9 9] \
        [list MON4_ERR 8 8] \
        [list CNTA3_OVER_ERR 7 7] \
        [list MON3_ERR 6 6] \
        [list CNTA2_OVER_ERR 5 5] \
        [list MON2_ERR 4 4] \
        [list CNTA1_OVER_ERR 3 3] \
        [list MON1_ERR 2 2] \
        [list CNTA0_OVER_ERR 1 1] \
        [list MON0_ERR 0 0] \
    ]]

# CRL_APB.CLKMON_TRIGGER
dict set ::QEMU_REGS 4284350800 [dict create \
    name    CLKMON_TRIGGER \
    block   CRL_APB \
    fields  [list \
        [list CNTA7_OVER_ERR 15 15] \
        [list MON7_ERR 14 14] \
        [list CNTA6_OVER_ERR 13 13] \
        [list MON6_ERR 12 12] \
        [list CNTA5_OVER_ERR 11 11] \
        [list MON5_ERR 10 10] \
        [list CNTA4_OVER_ERR 9 9] \
        [list MON4_ERR 8 8] \
        [list CNTA3_OVER_ERR 7 7] \
        [list MON3_ERR 6 6] \
        [list CNTA2_OVER_ERR 5 5] \
        [list MON2_ERR 4 4] \
        [list CNTA1_OVER_ERR 3 3] \
        [list MON1_ERR 2 2] \
        [list CNTA0_OVER_ERR 1 1] \
        [list MON0_ERR 0 0] \
    ]]

# CRL_APB.CHKR0_CLKA_UPPER
dict set ::QEMU_REGS 4284350816 [dict create \
    name    CHKR0_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR0_CLKA_LOWER
dict set ::QEMU_REGS 4284350820 [dict create \
    name    CHKR0_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR0_CLKB_CNT
dict set ::QEMU_REGS 4284350824 [dict create \
    name    CHKR0_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR0_CTRL
dict set ::QEMU_REGS 4284350828 [dict create \
    name    CHKR0_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR1_CLKA_UPPER
dict set ::QEMU_REGS 4284350832 [dict create \
    name    CHKR1_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR1_CLKA_LOWER
dict set ::QEMU_REGS 4284350836 [dict create \
    name    CHKR1_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR1_CLKB_CNT
dict set ::QEMU_REGS 4284350840 [dict create \
    name    CHKR1_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR1_CTRL
dict set ::QEMU_REGS 4284350844 [dict create \
    name    CHKR1_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR2_CLKA_UPPER
dict set ::QEMU_REGS 4284350848 [dict create \
    name    CHKR2_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR2_CLKA_LOWER
dict set ::QEMU_REGS 4284350852 [dict create \
    name    CHKR2_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR2_CLKB_CNT
dict set ::QEMU_REGS 4284350856 [dict create \
    name    CHKR2_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR2_CTRL
dict set ::QEMU_REGS 4284350860 [dict create \
    name    CHKR2_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR3_CLKA_UPPER
dict set ::QEMU_REGS 4284350864 [dict create \
    name    CHKR3_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR3_CLKA_LOWER
dict set ::QEMU_REGS 4284350868 [dict create \
    name    CHKR3_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR3_CLKB_CNT
dict set ::QEMU_REGS 4284350872 [dict create \
    name    CHKR3_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR3_CTRL
dict set ::QEMU_REGS 4284350876 [dict create \
    name    CHKR3_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR4_CLKA_UPPER
dict set ::QEMU_REGS 4284350880 [dict create \
    name    CHKR4_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR4_CLKA_LOWER
dict set ::QEMU_REGS 4284350884 [dict create \
    name    CHKR4_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR4_CLKB_CNT
dict set ::QEMU_REGS 4284350888 [dict create \
    name    CHKR4_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR4_CTRL
dict set ::QEMU_REGS 4284350892 [dict create \
    name    CHKR4_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR5_CLKA_UPPER
dict set ::QEMU_REGS 4284350896 [dict create \
    name    CHKR5_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR5_CLKA_LOWER
dict set ::QEMU_REGS 4284350900 [dict create \
    name    CHKR5_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR5_CLKB_CNT
dict set ::QEMU_REGS 4284350904 [dict create \
    name    CHKR5_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR5_CTRL
dict set ::QEMU_REGS 4284350908 [dict create \
    name    CHKR5_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR6_CLKA_UPPER
dict set ::QEMU_REGS 4284350912 [dict create \
    name    CHKR6_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR6_CLKA_LOWER
dict set ::QEMU_REGS 4284350916 [dict create \
    name    CHKR6_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR6_CLKB_CNT
dict set ::QEMU_REGS 4284350920 [dict create \
    name    CHKR6_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR6_CTRL
dict set ::QEMU_REGS 4284350924 [dict create \
    name    CHKR6_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.CHKR7_CLKA_UPPER
dict set ::QEMU_REGS 4284350928 [dict create \
    name    CHKR7_CLKA_UPPER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR7_CLKA_LOWER
dict set ::QEMU_REGS 4284350932 [dict create \
    name    CHKR7_CLKA_LOWER \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR7_CLKB_CNT
dict set ::QEMU_REGS 4284350936 [dict create \
    name    CHKR7_CLKB_CNT \
    block   CRL_APB \
    fields  [list \
    ]]

# CRL_APB.CHKR7_CTRL
dict set ::QEMU_REGS 4284350940 [dict create \
    name    CHKR7_CTRL \
    block   CRL_APB \
    fields  [list \
        [list START_SINGLE 8 8] \
        [list START_CONTINUOUS 7 7] \
        [list CLKB_MUX_CTRL 5 5] \
        [list CLKA_MUX_CTRL 3 1] \
        [list ENABLE 0 0] \
    ]]

# CRL_APB.BOOT_MODE_USER
dict set ::QEMU_REGS 4284350976 [dict create \
    name    BOOT_MODE_USER \
    block   CRL_APB \
    fields  [list \
        [list ALT_BOOT_MODE 15 12] \
        [list USE_ALT 8 8] \
        [list BOOT_MODE 3 0] \
    ]]

# CRL_APB.BOOT_MODE_POR
dict set ::QEMU_REGS 4284350980 [dict create \
    name    BOOT_MODE_POR \
    block   CRL_APB \
    fields  [list \
        [list BOOT_MODE2 11 8] \
        [list BOOT_MODE1 7 4] \
        [list BOOT_MODE0 3 0] \
    ]]

# CRL_APB.RESET_CTRL
dict set ::QEMU_REGS 4284351000 [dict create \
    name    RESET_CTRL \
    block   CRL_APB \
    fields  [list \
        [list SOFT_RESET 4 4] \
        [list SRST_DIS 0 0] \
    ]]

# CRL_APB.BLOCKONLY_RST
dict set ::QEMU_REGS 4284351004 [dict create \
    name    BLOCKONLY_RST \
    block   CRL_APB \
    fields  [list \
        [list MIMIC 3 3] \
        [list DEBUG_ONLY 0 0] \
    ]]

# CRL_APB.RESET_REASON
dict set ::QEMU_REGS 4284351008 [dict create \
    name    RESET_REASON \
    block   CRL_APB \
    fields  [list \
        [list MIMIC 15 15] \
        [list DEBUG_SYS 6 6] \
        [list SOFT 5 5] \
        [list SRST 4 4] \
        [list PSONLY_RESET_REQ 3 3] \
        [list PMU_SYS_RESET 2 2] \
        [list INTERNAL_POR 1 1] \
        [list EXTERNAL_POR 0 0] \
    ]]

# CRL_APB.RST_LPD_IOU0
dict set ::QEMU_REGS 4284351024 [dict create \
    name    RST_LPD_IOU0 \
    block   CRL_APB \
    fields  [list \
        [list GEM3_RESET 3 3] \
        [list GEM2_RESET 2 2] \
        [list GEM1_RESET 1 1] \
        [list GEM0_RESET 0 0] \
    ]]

# CRL_APB.RST_LPD_IOU2
dict set ::QEMU_REGS 4284351032 [dict create \
    name    RST_LPD_IOU2 \
    block   CRL_APB \
    fields  [list \
        [list TIMESTAMP_RESET 20 20] \
        [list IOU_CC_RESET 19 19] \
        [list GPIO_RESET 18 18] \
        [list ADMA_RESET 17 17] \
        [list NAND_RESET 16 16] \
        [list SWDT_RESET 15 15] \
        [list TTC3_RESET 14 14] \
        [list TTC2_RESET 13 13] \
        [list TTC1_RESET 12 12] \
        [list TTC0_RESET 11 11] \
        [list I2C1_RESET 10 10] \
        [list I2C0_RESET 9 9] \
        [list CAN1_RESET 8 8] \
        [list CAN0_RESET 7 7] \
        [list SDIO1_RESET 6 6] \
        [list SDIO0_RESET 5 5] \
        [list SPI1_RESET 4 4] \
        [list SPI0_RESET 3 3] \
        [list UART1_RESET 2 2] \
        [list UART0_RESET 1 1] \
        [list QSPI_RESET 0 0] \
    ]]

# CRL_APB.RST_LPD_TOP
dict set ::QEMU_REGS 4284351036 [dict create \
    name    RST_LPD_TOP \
    block   CRL_APB \
    fields  [list \
        [list FPD_RESET 23 23] \
        [list LPD_SWDT_RESET 20 20] \
        [list AFI_FM6_RESET 19 19] \
        [list SYSMON_RESET 17 17] \
        [list RTC_RESET 16 16] \
        [list APM_RESET 15 15] \
        [list IPI_RESET 14 14] \
        [list USB1_APB_RESET 11 11] \
        [list USB0_APB_RESET 10 10] \
        [list USB1_HIBERRESET 9 9] \
        [list USB0_HIBERRESET 8 8] \
        [list USB1_CORERESET 7 7] \
        [list USB0_CORERESET 6 6] \
        [list RPU_PGE_RESET 4 4] \
        [list OCM_RESET 3 3] \
        [list RPU_AMBA_RESET 2 2] \
        [list RPU_R51_RESET 1 1] \
        [list RPU_R50_RESET 0 0] \
    ]]

# CRL_APB.RST_LPD_DBG
dict set ::QEMU_REGS 4284351040 [dict create \
    name    RST_LPD_DBG \
    block   CRL_APB \
    fields  [list \
        [list DBG_ACK 15 15] \
        [list RPU_DBG1_RESET 5 5] \
        [list RPU_DBG0_RESET 4 4] \
        [list DBG_LPD_RESET 1 1] \
        [list DBG_FPD_RESET 0 0] \
    ]]

# CRL_APB.BANK3_CTRL0
dict set ::QEMU_REGS 4284351088 [dict create \
    name    BANK3_CTRL0 \
    block   CRL_APB \
    fields  [list \
        [list DRIVE0 9 0] \
    ]]

# CRL_APB.BANK3_CTRL1
dict set ::QEMU_REGS 4284351092 [dict create \
    name    BANK3_CTRL1 \
    block   CRL_APB \
    fields  [list \
        [list DRIVE1 9 0] \
    ]]

# CRL_APB.BANK3_CTRL2
dict set ::QEMU_REGS 4284351096 [dict create \
    name    BANK3_CTRL2 \
    block   CRL_APB \
    fields  [list \
        [list SCHMITT_CMOS_N 9 0] \
    ]]

# CRL_APB.BANK3_CTRL3
dict set ::QEMU_REGS 4284351100 [dict create \
    name    BANK3_CTRL3 \
    block   CRL_APB \
    fields  [list \
        [list PULL_HIGH_LOW_N 9 0] \
    ]]

# CRL_APB.BANK3_CTRL4
dict set ::QEMU_REGS 4284351104 [dict create \
    name    BANK3_CTRL4 \
    block   CRL_APB \
    fields  [list \
        [list PULL_ENABLE 9 0] \
    ]]

# CRL_APB.BANK3_CTRL5
dict set ::QEMU_REGS 4284351108 [dict create \
    name    BANK3_CTRL5 \
    block   CRL_APB \
    fields  [list \
        [list SLOW_FAST_SLEW_N 9 0] \
    ]]

# CRL_APB.BANK3_STATUS
dict set ::QEMU_REGS 4284351112 [dict create \
    name    BANK3_STATUS \
    block   CRL_APB \
    fields  [list \
        [list VMODE_1P8_3P3_N 0 0] \
    ]]

# CSU.CSU_STATUS
dict set ::QEMU_REGS 4291428352 [dict create \
    name    CSU_STATUS \
    block   CSU \
    fields  [list \
        [list BOOT_ENC 1 1] \
        [list BOOT_AUTH 0 0] \
    ]]

# CSU.CSU_CTRL
dict set ::QEMU_REGS 4291428356 [dict create \
    name    CSU_CTRL \
    block   CSU \
    fields  [list \
        [list SLVERR_ENABLE 4 4] \
        [list CSU_CLK_SEL 0 0] \
    ]]

# CSU.CSU_SSS_CFG
dict set ::QEMU_REGS 4291428360 [dict create \
    name    CSU_SSS_CFG \
    block   CSU \
    fields  [list \
        [list PSTP_SSS 19 16] \
        [list SHA_SSS 15 12] \
        [list AES_SSS 11 8] \
        [list DMA_SSS 7 4] \
        [list PCAP_SSS 3 0] \
    ]]

# CSU.CSU_DMA_RESET
dict set ::QEMU_REGS 4291428364 [dict create \
    name    CSU_DMA_RESET \
    block   CSU \
    fields  [list \
        [list RESET 0 0] \
    ]]

# CSU.CSU_MULTI_BOOT
dict set ::QEMU_REGS 4291428368 [dict create \
    name    CSU_MULTI_BOOT \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_TAMPER_TRIG
dict set ::QEMU_REGS 4291428372 [dict create \
    name    CSU_TAMPER_TRIG \
    block   CSU \
    fields  [list \
        [list TAMPER 0 0] \
    ]]

# CSU.CSU_FT_STATUS
dict set ::QEMU_REGS 4291428376 [dict create \
    name    CSU_FT_STATUS \
    block   CSU \
    fields  [list \
        [list R_UE 31 31] \
        [list R_VOTER_ERROR 30 30] \
        [list R_COMP_ERR_23 29 29] \
        [list R_COMP_ERR_13 28 28] \
        [list R_COMP_ERR_12 27 27] \
        [list R_MISMATCH_23_A 26 26] \
        [list R_MISMATCH_13_A 25 25] \
        [list R_MISMATCH_12_A 24 24] \
        [list R_FT_ST_MISMATCH 23 23] \
        [list R_CPU_ID_MISMATCH 22 22] \
        [list R_SLEEP_RESET 19 19] \
        [list R_MISMATCH_23_B 18 18] \
        [list R_MISMATCH_13_B 17 17] \
        [list R_MISMATCH_12_B 16 16] \
        [list N_UE 15 15] \
        [list N_VOTER_ERROR 14 14] \
        [list N_COMP_ERR_23 13 13] \
        [list N_COMP_ERR_13 12 12] \
        [list N_COMP_ERR_12 11 11] \
        [list N_MISMATCH_23_A 10 10] \
        [list N_MISMATCH_13_A 9 9] \
        [list N_MISMATCH_12_A 8 8] \
        [list N_FT_ST_MISMATCH 7 7] \
        [list N_CPU_ID_MISMATCH 6 6] \
        [list N_SLEEP_RESET 3 3] \
        [list N_MISMATCH_23_B 2 2] \
        [list N_MISMATCH_13_B 1 1] \
        [list N_MISMATCH_12_B 0 0] \
    ]]

# CSU.CSU_ISR
dict set ::QEMU_REGS 4291428384 [dict create \
    name    CSU_ISR \
    block   CSU \
    fields  [list \
        [list CSU_PL_ISO 15 15] \
        [list CSU_RAM_ECC_ERROR 14 14] \
        [list TAMPER 13 13] \
        [list PUF_ACC_ERROR 12 12] \
        [list APB_SLVERR 11 11] \
        [list TMR_FATAL 10 10] \
        [list PL_SEU_ERROR 9 9] \
        [list AES_ERROR 8 8] \
        [list PCAP_WR_OVERFLOW 7 7] \
        [list PCAP_RD_OVERFLOW 6 6] \
        [list PL_POR_B 5 5] \
        [list PL_INIT 4 4] \
        [list PL_DONE 3 3] \
        [list SHA_DONE 2 2] \
        [list RSA_DONE 1 1] \
        [list AES_DONE 0 0] \
    ]]

# CSU.CSU_IMR
dict set ::QEMU_REGS 4291428388 [dict create \
    name    CSU_IMR \
    block   CSU \
    fields  [list \
        [list CSU_PL_ISO 15 15] \
        [list CSU_RAM_ECC_ERROR 14 14] \
        [list TAMPER 13 13] \
        [list PUF_ACC_ERROR 12 12] \
        [list APB_SLVERR 11 11] \
        [list TMR_FATAL 10 10] \
        [list PL_SEU_ERROR 9 9] \
        [list AES_ERROR 8 8] \
        [list PCAP_WR_OVERFLOW 7 7] \
        [list PCAP_RD_OVERFLOW 6 6] \
        [list PL_POR_B 5 5] \
        [list PL_INIT 4 4] \
        [list PL_DONE 3 3] \
        [list SHA_DONE 2 2] \
        [list RSA_DONE 1 1] \
        [list AES_DONE 0 0] \
    ]]

# CSU.CSU_IER
dict set ::QEMU_REGS 4291428392 [dict create \
    name    CSU_IER \
    block   CSU \
    fields  [list \
        [list CSU_PL_ISO 15 15] \
        [list CSU_RAM_ECC_ERROR 14 14] \
        [list TAMPER 13 13] \
        [list PUF_ACC_ERROR 12 12] \
        [list APB_SLVERR 11 11] \
        [list TMR_FATAL 10 10] \
        [list PL_SEU_ERROR 9 9] \
        [list AES_ERROR 8 8] \
        [list PCAP_WR_OVERFLOW 7 7] \
        [list PCAP_RD_OVERFLOW 6 6] \
        [list PL_POR_B 5 5] \
        [list PL_INIT 4 4] \
        [list PL_DONE 3 3] \
        [list SHA_DONE 2 2] \
        [list RSA_DONE 1 1] \
        [list AES_DONE 0 0] \
    ]]

# CSU.CSU_IDR
dict set ::QEMU_REGS 4291428396 [dict create \
    name    CSU_IDR \
    block   CSU \
    fields  [list \
        [list CSU_PL_ISO 15 15] \
        [list CSU_RAM_ECC_ERROR 14 14] \
        [list TAMPER 13 13] \
        [list PUF_ACC_ERROR 12 12] \
        [list APB_SLVERR 11 11] \
        [list TMR_FATAL 10 10] \
        [list PL_SEU_ERROR 9 9] \
        [list AES_ERROR 8 8] \
        [list PCAP_WR_OVERFLOW 7 7] \
        [list PCAP_RD_OVERFLOW 6 6] \
        [list PL_POR_B 5 5] \
        [list PL_INIT 4 4] \
        [list PL_DONE 3 3] \
        [list SHA_DONE 2 2] \
        [list RSA_DONE 1 1] \
        [list AES_DONE 0 0] \
    ]]

# CSU.JTAG_CHAIN_STATUS
dict set ::QEMU_REGS 4291428404 [dict create \
    name    JTAG_CHAIN_STATUS \
    block   CSU \
    fields  [list \
        [list ARM_DAP 1 1] \
        [list PL_TAP 0 0] \
    ]]

# CSU.JTAG_SEC
dict set ::QEMU_REGS 4291428408 [dict create \
    name    JTAG_SEC \
    block   CSU \
    fields  [list \
        [list SSSS_PMU_SEC 8 6] \
        [list SSSS_PLTAP_SEC 5 3] \
        [list SSSS_DAP_SEC 2 0] \
    ]]

# CSU.JTAG_DAP_CFG
dict set ::QEMU_REGS 4291428412 [dict create \
    name    JTAG_DAP_CFG \
    block   CSU \
    fields  [list \
        [list SSSS_RPU_SPNIDEN 7 7] \
        [list SSSS_RPU_SPIDEN 6 6] \
        [list SSSS_RPU_NIDEN 5 5] \
        [list SSSS_RPU_DBGEN 4 4] \
        [list SSSS_APU_SPNIDEN 3 3] \
        [list SSSS_APU_SPIDEN 2 2] \
        [list SSSS_APU_NIDEN 1 1] \
        [list SSSS_APU_DBGEN 0 0] \
    ]]

# CSU.IDCODE
dict set ::QEMU_REGS 4291428416 [dict create \
    name    IDCODE \
    block   CSU \
    fields  [list \
    ]]

# CSU.VERSION
dict set ::QEMU_REGS 4291428420 [dict create \
    name    VERSION \
    block   CSU \
    fields  [list \
        [list PLATFORM 15 12] \
        [list PS_VERSION 3 0] \
    ]]

# CSU.CSU_ROM_DIGEST_0
dict set ::QEMU_REGS 4291428432 [dict create \
    name    CSU_ROM_DIGEST_0 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_1
dict set ::QEMU_REGS 4291428436 [dict create \
    name    CSU_ROM_DIGEST_1 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_2
dict set ::QEMU_REGS 4291428440 [dict create \
    name    CSU_ROM_DIGEST_2 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_3
dict set ::QEMU_REGS 4291428444 [dict create \
    name    CSU_ROM_DIGEST_3 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_4
dict set ::QEMU_REGS 4291428448 [dict create \
    name    CSU_ROM_DIGEST_4 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_5
dict set ::QEMU_REGS 4291428452 [dict create \
    name    CSU_ROM_DIGEST_5 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_6
dict set ::QEMU_REGS 4291428456 [dict create \
    name    CSU_ROM_DIGEST_6 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_7
dict set ::QEMU_REGS 4291428460 [dict create \
    name    CSU_ROM_DIGEST_7 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_8
dict set ::QEMU_REGS 4291428464 [dict create \
    name    CSU_ROM_DIGEST_8 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_9
dict set ::QEMU_REGS 4291428468 [dict create \
    name    CSU_ROM_DIGEST_9 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_10
dict set ::QEMU_REGS 4291428472 [dict create \
    name    CSU_ROM_DIGEST_10 \
    block   CSU \
    fields  [list \
    ]]

# CSU.CSU_ROM_DIGEST_11
dict set ::QEMU_REGS 4291428476 [dict create \
    name    CSU_ROM_DIGEST_11 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_STATUS
dict set ::QEMU_REGS 4291432448 [dict create \
    name    AES_STATUS \
    block   CSU \
    fields  [list \
        [list OKR_ZEROED 11 11] \
        [list BOOT_ZEROED 10 10] \
        [list KUP_ZEROED 9 9] \
        [list AES_KEY_ZEROED 8 8] \
        [list BLACK_KEY_DONE 5 5] \
        [list KEY_INIT_DONE 4 4] \
        [list GCM_TAG_PASS 3 3] \
        [list DONE 2 2] \
        [list READY 1 1] \
        [list BUSY 0 0] \
    ]]

# CSU.AES_KEY_SRC
dict set ::QEMU_REGS 4291432452 [dict create \
    name    AES_KEY_SRC \
    block   CSU \
    fields  [list \
        [list KEY_SRC 3 0] \
    ]]

# CSU.AES_KEY_LOAD
dict set ::QEMU_REGS 4291432456 [dict create \
    name    AES_KEY_LOAD \
    block   CSU \
    fields  [list \
        [list KEY_LOAD 0 0] \
    ]]

# CSU.AES_START_MSG
dict set ::QEMU_REGS 4291432460 [dict create \
    name    AES_START_MSG \
    block   CSU \
    fields  [list \
        [list START_MSG 0 0] \
    ]]

# CSU.AES_RESET
dict set ::QEMU_REGS 4291432464 [dict create \
    name    AES_RESET \
    block   CSU \
    fields  [list \
        [list RESET 0 0] \
    ]]

# CSU.AES_KEY_CLEAR
dict set ::QEMU_REGS 4291432468 [dict create \
    name    AES_KEY_CLEAR \
    block   CSU \
    fields  [list \
        [list AES_OKR_ZERO 3 3] \
        [list AES_BOOT_ZERO 2 2] \
        [list AES_KUP_ZERO 1 1] \
        [list AES_KEY_ZERO 0 0] \
    ]]

# CSU.AES_KUP_WR
dict set ::QEMU_REGS 4291432476 [dict create \
    name    AES_KUP_WR \
    block   CSU \
    fields  [list \
        [list IV_WRITE 1 1] \
        [list KUP_WRITE 0 0] \
    ]]

# CSU.AES_KUP_0
dict set ::QEMU_REGS 4291432480 [dict create \
    name    AES_KUP_0 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_1
dict set ::QEMU_REGS 4291432484 [dict create \
    name    AES_KUP_1 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_2
dict set ::QEMU_REGS 4291432488 [dict create \
    name    AES_KUP_2 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_3
dict set ::QEMU_REGS 4291432492 [dict create \
    name    AES_KUP_3 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_4
dict set ::QEMU_REGS 4291432496 [dict create \
    name    AES_KUP_4 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_5
dict set ::QEMU_REGS 4291432500 [dict create \
    name    AES_KUP_5 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_6
dict set ::QEMU_REGS 4291432504 [dict create \
    name    AES_KUP_6 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_KUP_7
dict set ::QEMU_REGS 4291432508 [dict create \
    name    AES_KUP_7 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_IV_0
dict set ::QEMU_REGS 4291432512 [dict create \
    name    AES_IV_0 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_IV_1
dict set ::QEMU_REGS 4291432516 [dict create \
    name    AES_IV_1 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_IV_2
dict set ::QEMU_REGS 4291432520 [dict create \
    name    AES_IV_2 \
    block   CSU \
    fields  [list \
    ]]

# CSU.AES_IV_3
dict set ::QEMU_REGS 4291432524 [dict create \
    name    AES_IV_3 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_START
dict set ::QEMU_REGS 4291436544 [dict create \
    name    SHA_START \
    block   CSU \
    fields  [list \
        [list START_MSG 0 0] \
    ]]

# CSU.SHA_RESET
dict set ::QEMU_REGS 4291436548 [dict create \
    name    SHA_RESET \
    block   CSU \
    fields  [list \
        [list RESET 0 0] \
    ]]

# CSU.SHA_DONE
dict set ::QEMU_REGS 4291436552 [dict create \
    name    SHA_DONE \
    block   CSU \
    fields  [list \
        [list SHA_DONE 0 0] \
    ]]

# CSU.SHA_DIGEST_0
dict set ::QEMU_REGS 4291436560 [dict create \
    name    SHA_DIGEST_0 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_1
dict set ::QEMU_REGS 4291436564 [dict create \
    name    SHA_DIGEST_1 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_2
dict set ::QEMU_REGS 4291436568 [dict create \
    name    SHA_DIGEST_2 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_3
dict set ::QEMU_REGS 4291436572 [dict create \
    name    SHA_DIGEST_3 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_4
dict set ::QEMU_REGS 4291436576 [dict create \
    name    SHA_DIGEST_4 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_5
dict set ::QEMU_REGS 4291436580 [dict create \
    name    SHA_DIGEST_5 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_6
dict set ::QEMU_REGS 4291436584 [dict create \
    name    SHA_DIGEST_6 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_7
dict set ::QEMU_REGS 4291436588 [dict create \
    name    SHA_DIGEST_7 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_8
dict set ::QEMU_REGS 4291436592 [dict create \
    name    SHA_DIGEST_8 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_9
dict set ::QEMU_REGS 4291436596 [dict create \
    name    SHA_DIGEST_9 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_10
dict set ::QEMU_REGS 4291436600 [dict create \
    name    SHA_DIGEST_10 \
    block   CSU \
    fields  [list \
    ]]

# CSU.SHA_DIGEST_11
dict set ::QEMU_REGS 4291436604 [dict create \
    name    SHA_DIGEST_11 \
    block   CSU \
    fields  [list \
    ]]

# CSU.PCAP_PROG
dict set ::QEMU_REGS 4291440640 [dict create \
    name    PCAP_PROG \
    block   CSU \
    fields  [list \
        [list PCFG_PROG_B 0 0] \
    ]]

# CSU.PCAP_RDWR
dict set ::QEMU_REGS 4291440644 [dict create \
    name    PCAP_RDWR \
    block   CSU \
    fields  [list \
        [list PCAP_RDWR_B 0 0] \
    ]]

# CSU.PCAP_CTRL
dict set ::QEMU_REGS 4291440648 [dict create \
    name    PCAP_CTRL \
    block   CSU \
    fields  [list \
        [list PCFG_GSR 3 3] \
        [list PCFG_GTS 2 2] \
        [list PCFG_POR_CNT_4K 1 1] \
        [list PCAP_PR 0 0] \
    ]]

# CSU.PCAP_RESET
dict set ::QEMU_REGS 4291440652 [dict create \
    name    PCAP_RESET \
    block   CSU \
    fields  [list \
        [list RESET 0 0] \
    ]]

# CSU.PCAP_STATUS
dict set ::QEMU_REGS 4291440656 [dict create \
    name    PCAP_STATUS \
    block   CSU \
    fields  [list \
        [list PCFG_GWE 13 13] \
        [list PCFG_MCAP_MODE 12 12] \
        [list PL_GTS_USR_B 11 11] \
        [list PL_GTS_CFG_B 10 10] \
        [list PL_GPWRDWN_B 9 9] \
        [list PL_GHIGH_B 8 8] \
        [list PL_FST_CFG 7 7] \
        [list PL_CFG_RESET_B 6 6] \
        [list PL_SEU_ERROR 5 5] \
        [list PL_EOS 4 4] \
        [list PL_DONE 3 3] \
        [list PL_INIT 2 2] \
        [list PCAP_RD_IDLE 1 1] \
        [list PCAP_WR_IDLE 0 0] \
    ]]

# CSU.TAMPER_STATUS
dict set ::QEMU_REGS 4291448832 [dict create \
    name    TAMPER_STATUS \
    block   CSU \
    fields  [list \
        [list TAMPER_13 13 13] \
        [list TAMPER_12 12 12] \
        [list TAMPER_11 11 11] \
        [list TAMPER_10 10 10] \
        [list TAMPER_9 9 9] \
        [list TAMPER_8 8 8] \
        [list TAMPER_7 7 7] \
        [list TAMPER_6 6 6] \
        [list TAMPER_5 5 5] \
        [list TAMPER_4 4 4] \
        [list TAMPER_3 3 3] \
        [list TAMPER_2 2 2] \
        [list TAMPER_1 1 1] \
        [list TAMPER_0 0 0] \
    ]]

# CSU.CSU_TAMPER_0
dict set ::QEMU_REGS 4291448836 [dict create \
    name    CSU_TAMPER_0 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_1
dict set ::QEMU_REGS 4291448840 [dict create \
    name    CSU_TAMPER_1 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_2
dict set ::QEMU_REGS 4291448844 [dict create \
    name    CSU_TAMPER_2 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_3
dict set ::QEMU_REGS 4291448848 [dict create \
    name    CSU_TAMPER_3 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_4
dict set ::QEMU_REGS 4291448852 [dict create \
    name    CSU_TAMPER_4 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_5
dict set ::QEMU_REGS 4291448856 [dict create \
    name    CSU_TAMPER_5 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_6
dict set ::QEMU_REGS 4291448860 [dict create \
    name    CSU_TAMPER_6 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_7
dict set ::QEMU_REGS 4291448864 [dict create \
    name    CSU_TAMPER_7 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_8
dict set ::QEMU_REGS 4291448868 [dict create \
    name    CSU_TAMPER_8 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_9
dict set ::QEMU_REGS 4291448872 [dict create \
    name    CSU_TAMPER_9 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_10
dict set ::QEMU_REGS 4291448876 [dict create \
    name    CSU_TAMPER_10 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_11
dict set ::QEMU_REGS 4291448880 [dict create \
    name    CSU_TAMPER_11 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# CSU.CSU_TAMPER_12
dict set ::QEMU_REGS 4291448884 [dict create \
    name    CSU_TAMPER_12 \
    block   CSU \
    fields  [list \
        [list BBRAM_ERASE 4 4] \
        [list SEC_LOCKDOWN_1 3 3] \
        [list SEC_LOCKDOWN_0 2 2] \
        [list SYS_RESET 1 1] \
        [list SYS_INTERRUPT 0 0] \
    ]]

# DDR_XMPU0.CTRL
dict set ::QEMU_REGS 4244635648 [dict create \
    name    CTRL \
    block   DDR_XMPU0 \
    fields  [list \
        [list ALIGNCFG 3 3] \
        [list HIDEALLOWED 2 2] \
        [list DEFWRALLOWED 1 1] \
        [list DEFRDALLOWED 0 0] \
    ]]

# DDR_XMPU0.ISR
dict set ::QEMU_REGS 4244635664 [dict create \
    name    ISR \
    block   DDR_XMPU0 \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# DDR_XMPU0.IMR
dict set ::QEMU_REGS 4244635668 [dict create \
    name    IMR \
    block   DDR_XMPU0 \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# DDR_XMPU0.IEN
dict set ::QEMU_REGS 4244635672 [dict create \
    name    IEN \
    block   DDR_XMPU0 \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# DDR_XMPU0.IDS
dict set ::QEMU_REGS 4244635676 [dict create \
    name    IDS \
    block   DDR_XMPU0 \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# DDR_XMPU0.LOCK
dict set ::QEMU_REGS 4244635680 [dict create \
    name    LOCK \
    block   DDR_XMPU0 \
    fields  [list \
        [list REGWRDIS 0 0] \
    ]]

# DDR_XMPU0.ECO
dict set ::QEMU_REGS 4244635900 [dict create \
    name    ECO \
    block   DDR_XMPU0 \
    fields  [list \
    ]]

# EFUSE.WR_LOCK
dict set ::QEMU_REGS 4291559424 [dict create \
    name    WR_LOCK \
    block   EFUSE \
    fields  [list \
        [list LOCK 15 0] \
    ]]

# EFUSE.CFG
dict set ::QEMU_REGS 4291559428 [dict create \
    name    CFG \
    block   EFUSE \
    fields  [list \
        [list SLVERR_ENABLE 5 5] \
        [list MARGIN_RD 3 2] \
        [list PGM_EN 1 1] \
        [list EFUSE_CLK_SEL 0 0] \
    ]]

# EFUSE.STATUS
dict set ::QEMU_REGS 4291559432 [dict create \
    name    STATUS \
    block   EFUSE \
    fields  [list \
        [list AES_CRC_PASS 7 7] \
        [list AES_CRC_DONE 6 6] \
        [list CACHE_DONE 5 5] \
        [list CACHE_LOAD 4 4] \
        [list EFUSE_3_TBIT 2 2] \
        [list EFUSE_2_TBIT 1 1] \
        [list EFUSE_0_TBIT 0 0] \
    ]]

# EFUSE.EFUSE_PGM_ADDR
dict set ::QEMU_REGS 4291559436 [dict create \
    name    EFUSE_PGM_ADDR \
    block   EFUSE \
    fields  [list \
        [list EFUSE 12 11] \
        [list ROW 10 5] \
        [list COLUMN 4 0] \
    ]]

# EFUSE.EFUSE_RD_ADDR
dict set ::QEMU_REGS 4291559440 [dict create \
    name    EFUSE_RD_ADDR \
    block   EFUSE \
    fields  [list \
        [list EFUSE 12 11] \
        [list ROW 10 5] \
    ]]

# EFUSE.EFUSE_RD_DATA
dict set ::QEMU_REGS 4291559444 [dict create \
    name    EFUSE_RD_DATA \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.TPGM
dict set ::QEMU_REGS 4291559448 [dict create \
    name    TPGM \
    block   EFUSE \
    fields  [list \
        [list VALUE 15 0] \
    ]]

# EFUSE.TRD
dict set ::QEMU_REGS 4291559452 [dict create \
    name    TRD \
    block   EFUSE \
    fields  [list \
        [list VALUE 7 0] \
    ]]

# EFUSE.TSU_H_PS
dict set ::QEMU_REGS 4291559456 [dict create \
    name    TSU_H_PS \
    block   EFUSE \
    fields  [list \
        [list VALUE 7 0] \
    ]]

# EFUSE.TSU_H_PS_CS
dict set ::QEMU_REGS 4291559460 [dict create \
    name    TSU_H_PS_CS \
    block   EFUSE \
    fields  [list \
        [list VALUE 7 0] \
    ]]

# EFUSE.TSU_H_CS
dict set ::QEMU_REGS 4291559468 [dict create \
    name    TSU_H_CS \
    block   EFUSE \
    fields  [list \
        [list VALUE 3 0] \
    ]]

# EFUSE.EFUSE_ISR
dict set ::QEMU_REGS 4291559472 [dict create \
    name    EFUSE_ISR \
    block   EFUSE \
    fields  [list \
        [list APB_SLVERR 31 31] \
        [list CACHE_ERROR 4 4] \
        [list RD_ERROR 3 3] \
        [list RD_DONE 2 2] \
        [list PGM_ERROR 1 1] \
        [list PGM_DONE 0 0] \
    ]]

# EFUSE.EFUSE_IMR
dict set ::QEMU_REGS 4291559476 [dict create \
    name    EFUSE_IMR \
    block   EFUSE \
    fields  [list \
        [list APB_SLVERR 31 31] \
        [list CACHE_ERROR 4 4] \
        [list RD_ERROR 3 3] \
        [list RD_DONE 2 2] \
        [list PGM_ERROR 1 1] \
        [list PGM_DONE 0 0] \
    ]]

# EFUSE.EFUSE_IER
dict set ::QEMU_REGS 4291559480 [dict create \
    name    EFUSE_IER \
    block   EFUSE \
    fields  [list \
        [list APB_SLVERR 31 31] \
        [list CACHE_ERROR 4 4] \
        [list RD_ERROR 3 3] \
        [list RD_DONE 2 2] \
        [list PGM_ERROR 1 1] \
        [list PGM_DONE 0 0] \
    ]]

# EFUSE.EFUSE_IDR
dict set ::QEMU_REGS 4291559484 [dict create \
    name    EFUSE_IDR \
    block   EFUSE \
    fields  [list \
        [list APB_SLVERR 31 31] \
        [list CACHE_ERROR 4 4] \
        [list RD_ERROR 3 3] \
        [list RD_DONE 2 2] \
        [list PGM_ERROR 1 1] \
        [list PGM_DONE 0 0] \
    ]]

# EFUSE.EFUSE_CACHE_LOAD
dict set ::QEMU_REGS 4291559488 [dict create \
    name    EFUSE_CACHE_LOAD \
    block   EFUSE \
    fields  [list \
        [list LOAD 0 0] \
    ]]

# EFUSE.EFUSE_PGM_LOCK
dict set ::QEMU_REGS 4291559492 [dict create \
    name    EFUSE_PGM_LOCK \
    block   EFUSE \
    fields  [list \
        [list SPK_ID_LOCK 0 0] \
    ]]

# EFUSE.EFUSE_AES_CRC
dict set ::QEMU_REGS 4291559496 [dict create \
    name    EFUSE_AES_CRC \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.EFUSE_TBITS_PRGRMG_EN
dict set ::QEMU_REGS 4291559680 [dict create \
    name    EFUSE_TBITS_PRGRMG_EN \
    block   EFUSE \
    fields  [list \
        [list TBITS_PRGRMG_EN 3 3] \
    ]]

# EFUSE.DNA_0
dict set ::QEMU_REGS 4291563532 [dict create \
    name    DNA_0 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.DNA_1
dict set ::QEMU_REGS 4291563536 [dict create \
    name    DNA_1 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.DNA_2
dict set ::QEMU_REGS 4291563540 [dict create \
    name    DNA_2 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.IPDISABLE
dict set ::QEMU_REGS 4291563544 [dict create \
    name    IPDISABLE \
    block   EFUSE \
    fields  [list \
        [list VCU_DIS 8 8] \
        [list GPU_DIS 5 5] \
        [list APU3_DIS 3 3] \
        [list APU2_DIS 2 2] \
        [list APU1_DIS 1 1] \
        [list APU0_DIS 0 0] \
    ]]

# EFUSE.SYSOSC_CTRL
dict set ::QEMU_REGS 4291563548 [dict create \
    name    SYSOSC_CTRL \
    block   EFUSE \
    fields  [list \
        [list SYSOSC_EN 0 0] \
    ]]

# EFUSE.USER_0
dict set ::QEMU_REGS 4291563552 [dict create \
    name    USER_0 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_1
dict set ::QEMU_REGS 4291563556 [dict create \
    name    USER_1 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_2
dict set ::QEMU_REGS 4291563560 [dict create \
    name    USER_2 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_3
dict set ::QEMU_REGS 4291563564 [dict create \
    name    USER_3 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_4
dict set ::QEMU_REGS 4291563568 [dict create \
    name    USER_4 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_5
dict set ::QEMU_REGS 4291563572 [dict create \
    name    USER_5 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_6
dict set ::QEMU_REGS 4291563576 [dict create \
    name    USER_6 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.USER_7
dict set ::QEMU_REGS 4291563580 [dict create \
    name    USER_7 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.MISC_USER_CTRL
dict set ::QEMU_REGS 4291563584 [dict create \
    name    MISC_USER_CTRL \
    block   EFUSE \
    fields  [list \
        [list FPD_SC_EN_0 16 14] \
        [list LPD_SC_EN_0 13 11] \
        [list LBIST_EN 10 10] \
        [list USR_WRLK_7 7 7] \
        [list USR_WRLK_6 6 6] \
        [list USR_WRLK_5 5 5] \
        [list USR_WRLK_4 4 4] \
        [list USR_WRLK_3 3 3] \
        [list USR_WRLK_2 2 2] \
        [list USR_WRLK_1 1 1] \
        [list USR_WRLK_0 0 0] \
    ]]

# EFUSE.ROM_RSVD
dict set ::QEMU_REGS 4291563588 [dict create \
    name    ROM_RSVD \
    block   EFUSE \
    fields  [list \
        [list PBR_BOOT_ERROR 2 0] \
    ]]

# EFUSE.PUF_CHASH
dict set ::QEMU_REGS 4291563600 [dict create \
    name    PUF_CHASH \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PUF_MISC
dict set ::QEMU_REGS 4291563604 [dict create \
    name    PUF_MISC \
    block   EFUSE \
    fields  [list \
        [list REGISTER_DIS 31 31] \
        [list SYN_WRLK 30 30] \
        [list SYN_INVLD 29 29] \
        [list TEST2_DIS 28 28] \
        [list UNUSED27 27 27] \
        [list UNUSED26 26 26] \
        [list UNUSED25 25 25] \
        [list UNUSED24 24 24] \
        [list AUX 23 0] \
    ]]

# EFUSE.SEC_CTRL
dict set ::QEMU_REGS 4291563608 [dict create \
    name    SEC_CTRL \
    block   EFUSE \
    fields  [list \
        [list PPK1_INVLD 31 30] \
        [list PPK1_WRLK 29 29] \
        [list PPK0_INVLD 28 27] \
        [list PPK0_WRLK 26 26] \
        [list RSA_EN 25 11] \
        [list SEC_LOCK 10 10] \
        [list PROG_GATE_2 9 9] \
        [list PROG_GATE_1 8 8] \
        [list PROG_GATE_0 7 7] \
        [list DFT_DIS 6 6] \
        [list JTAG_DIS 5 5] \
        [list ERROR_DIS 4 4] \
        [list BBRAM_DIS 3 3] \
        [list ENC_ONLY 2 2] \
        [list AES_WRLK 1 1] \
        [list AES_RDLK 0 0] \
    ]]

# EFUSE.SPK_ID
dict set ::QEMU_REGS 4291563612 [dict create \
    name    SPK_ID \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_0
dict set ::QEMU_REGS 4291563680 [dict create \
    name    PPK0_0 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_1
dict set ::QEMU_REGS 4291563684 [dict create \
    name    PPK0_1 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_2
dict set ::QEMU_REGS 4291563688 [dict create \
    name    PPK0_2 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_3
dict set ::QEMU_REGS 4291563692 [dict create \
    name    PPK0_3 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_4
dict set ::QEMU_REGS 4291563696 [dict create \
    name    PPK0_4 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_5
dict set ::QEMU_REGS 4291563700 [dict create \
    name    PPK0_5 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_6
dict set ::QEMU_REGS 4291563704 [dict create \
    name    PPK0_6 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_7
dict set ::QEMU_REGS 4291563708 [dict create \
    name    PPK0_7 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_8
dict set ::QEMU_REGS 4291563712 [dict create \
    name    PPK0_8 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_9
dict set ::QEMU_REGS 4291563716 [dict create \
    name    PPK0_9 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_10
dict set ::QEMU_REGS 4291563720 [dict create \
    name    PPK0_10 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK0_11
dict set ::QEMU_REGS 4291563724 [dict create \
    name    PPK0_11 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_0
dict set ::QEMU_REGS 4291563728 [dict create \
    name    PPK1_0 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_1
dict set ::QEMU_REGS 4291563732 [dict create \
    name    PPK1_1 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_2
dict set ::QEMU_REGS 4291563736 [dict create \
    name    PPK1_2 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_3
dict set ::QEMU_REGS 4291563740 [dict create \
    name    PPK1_3 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_4
dict set ::QEMU_REGS 4291563744 [dict create \
    name    PPK1_4 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_5
dict set ::QEMU_REGS 4291563748 [dict create \
    name    PPK1_5 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_6
dict set ::QEMU_REGS 4291563752 [dict create \
    name    PPK1_6 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_7
dict set ::QEMU_REGS 4291563756 [dict create \
    name    PPK1_7 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_8
dict set ::QEMU_REGS 4291563760 [dict create \
    name    PPK1_8 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_9
dict set ::QEMU_REGS 4291563764 [dict create \
    name    PPK1_9 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_10
dict set ::QEMU_REGS 4291563768 [dict create \
    name    PPK1_10 \
    block   EFUSE \
    fields  [list \
    ]]

# EFUSE.PPK1_11
dict set ::QEMU_REGS 4291563772 [dict create \
    name    PPK1_11 \
    block   EFUSE \
    fields  [list \
    ]]

# IOU_SLCR.MIO_PIN_0
dict set ::QEMU_REGS 4279762944 [dict create \
    name    MIO_PIN_0 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_1
dict set ::QEMU_REGS 4279762948 [dict create \
    name    MIO_PIN_1 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_2
dict set ::QEMU_REGS 4279762952 [dict create \
    name    MIO_PIN_2 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_3
dict set ::QEMU_REGS 4279762956 [dict create \
    name    MIO_PIN_3 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_4
dict set ::QEMU_REGS 4279762960 [dict create \
    name    MIO_PIN_4 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_5
dict set ::QEMU_REGS 4279762964 [dict create \
    name    MIO_PIN_5 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_6
dict set ::QEMU_REGS 4279762968 [dict create \
    name    MIO_PIN_6 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_7
dict set ::QEMU_REGS 4279762972 [dict create \
    name    MIO_PIN_7 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_8
dict set ::QEMU_REGS 4279762976 [dict create \
    name    MIO_PIN_8 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_9
dict set ::QEMU_REGS 4279762980 [dict create \
    name    MIO_PIN_9 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_10
dict set ::QEMU_REGS 4279762984 [dict create \
    name    MIO_PIN_10 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_11
dict set ::QEMU_REGS 4279762988 [dict create \
    name    MIO_PIN_11 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_12
dict set ::QEMU_REGS 4279762992 [dict create \
    name    MIO_PIN_12 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_13
dict set ::QEMU_REGS 4279762996 [dict create \
    name    MIO_PIN_13 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_14
dict set ::QEMU_REGS 4279763000 [dict create \
    name    MIO_PIN_14 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_15
dict set ::QEMU_REGS 4279763004 [dict create \
    name    MIO_PIN_15 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_16
dict set ::QEMU_REGS 4279763008 [dict create \
    name    MIO_PIN_16 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_17
dict set ::QEMU_REGS 4279763012 [dict create \
    name    MIO_PIN_17 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_18
dict set ::QEMU_REGS 4279763016 [dict create \
    name    MIO_PIN_18 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_19
dict set ::QEMU_REGS 4279763020 [dict create \
    name    MIO_PIN_19 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_20
dict set ::QEMU_REGS 4279763024 [dict create \
    name    MIO_PIN_20 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_21
dict set ::QEMU_REGS 4279763028 [dict create \
    name    MIO_PIN_21 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_22
dict set ::QEMU_REGS 4279763032 [dict create \
    name    MIO_PIN_22 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_23
dict set ::QEMU_REGS 4279763036 [dict create \
    name    MIO_PIN_23 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_24
dict set ::QEMU_REGS 4279763040 [dict create \
    name    MIO_PIN_24 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_25
dict set ::QEMU_REGS 4279763044 [dict create \
    name    MIO_PIN_25 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_26
dict set ::QEMU_REGS 4279763048 [dict create \
    name    MIO_PIN_26 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_27
dict set ::QEMU_REGS 4279763052 [dict create \
    name    MIO_PIN_27 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_28
dict set ::QEMU_REGS 4279763056 [dict create \
    name    MIO_PIN_28 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_29
dict set ::QEMU_REGS 4279763060 [dict create \
    name    MIO_PIN_29 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_30
dict set ::QEMU_REGS 4279763064 [dict create \
    name    MIO_PIN_30 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_31
dict set ::QEMU_REGS 4279763068 [dict create \
    name    MIO_PIN_31 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_32
dict set ::QEMU_REGS 4279763072 [dict create \
    name    MIO_PIN_32 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_33
dict set ::QEMU_REGS 4279763076 [dict create \
    name    MIO_PIN_33 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_34
dict set ::QEMU_REGS 4279763080 [dict create \
    name    MIO_PIN_34 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_35
dict set ::QEMU_REGS 4279763084 [dict create \
    name    MIO_PIN_35 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_36
dict set ::QEMU_REGS 4279763088 [dict create \
    name    MIO_PIN_36 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_37
dict set ::QEMU_REGS 4279763092 [dict create \
    name    MIO_PIN_37 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_38
dict set ::QEMU_REGS 4279763096 [dict create \
    name    MIO_PIN_38 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_39
dict set ::QEMU_REGS 4279763100 [dict create \
    name    MIO_PIN_39 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_40
dict set ::QEMU_REGS 4279763104 [dict create \
    name    MIO_PIN_40 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_41
dict set ::QEMU_REGS 4279763108 [dict create \
    name    MIO_PIN_41 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_42
dict set ::QEMU_REGS 4279763112 [dict create \
    name    MIO_PIN_42 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_43
dict set ::QEMU_REGS 4279763116 [dict create \
    name    MIO_PIN_43 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_44
dict set ::QEMU_REGS 4279763120 [dict create \
    name    MIO_PIN_44 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_45
dict set ::QEMU_REGS 4279763124 [dict create \
    name    MIO_PIN_45 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_46
dict set ::QEMU_REGS 4279763128 [dict create \
    name    MIO_PIN_46 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_47
dict set ::QEMU_REGS 4279763132 [dict create \
    name    MIO_PIN_47 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_48
dict set ::QEMU_REGS 4279763136 [dict create \
    name    MIO_PIN_48 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_49
dict set ::QEMU_REGS 4279763140 [dict create \
    name    MIO_PIN_49 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_50
dict set ::QEMU_REGS 4279763144 [dict create \
    name    MIO_PIN_50 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_51
dict set ::QEMU_REGS 4279763148 [dict create \
    name    MIO_PIN_51 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_52
dict set ::QEMU_REGS 4279763152 [dict create \
    name    MIO_PIN_52 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_53
dict set ::QEMU_REGS 4279763156 [dict create \
    name    MIO_PIN_53 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_54
dict set ::QEMU_REGS 4279763160 [dict create \
    name    MIO_PIN_54 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_55
dict set ::QEMU_REGS 4279763164 [dict create \
    name    MIO_PIN_55 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_56
dict set ::QEMU_REGS 4279763168 [dict create \
    name    MIO_PIN_56 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_57
dict set ::QEMU_REGS 4279763172 [dict create \
    name    MIO_PIN_57 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_58
dict set ::QEMU_REGS 4279763176 [dict create \
    name    MIO_PIN_58 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_59
dict set ::QEMU_REGS 4279763180 [dict create \
    name    MIO_PIN_59 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_60
dict set ::QEMU_REGS 4279763184 [dict create \
    name    MIO_PIN_60 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_61
dict set ::QEMU_REGS 4279763188 [dict create \
    name    MIO_PIN_61 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_62
dict set ::QEMU_REGS 4279763192 [dict create \
    name    MIO_PIN_62 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_63
dict set ::QEMU_REGS 4279763196 [dict create \
    name    MIO_PIN_63 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_64
dict set ::QEMU_REGS 4279763200 [dict create \
    name    MIO_PIN_64 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_65
dict set ::QEMU_REGS 4279763204 [dict create \
    name    MIO_PIN_65 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_66
dict set ::QEMU_REGS 4279763208 [dict create \
    name    MIO_PIN_66 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_67
dict set ::QEMU_REGS 4279763212 [dict create \
    name    MIO_PIN_67 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_68
dict set ::QEMU_REGS 4279763216 [dict create \
    name    MIO_PIN_68 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_69
dict set ::QEMU_REGS 4279763220 [dict create \
    name    MIO_PIN_69 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_70
dict set ::QEMU_REGS 4279763224 [dict create \
    name    MIO_PIN_70 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_71
dict set ::QEMU_REGS 4279763228 [dict create \
    name    MIO_PIN_71 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_72
dict set ::QEMU_REGS 4279763232 [dict create \
    name    MIO_PIN_72 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_73
dict set ::QEMU_REGS 4279763236 [dict create \
    name    MIO_PIN_73 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_74
dict set ::QEMU_REGS 4279763240 [dict create \
    name    MIO_PIN_74 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_75
dict set ::QEMU_REGS 4279763244 [dict create \
    name    MIO_PIN_75 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_76
dict set ::QEMU_REGS 4279763248 [dict create \
    name    MIO_PIN_76 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.MIO_PIN_77
dict set ::QEMU_REGS 4279763252 [dict create \
    name    MIO_PIN_77 \
    block   IOU_SLCR \
    fields  [list \
        [list L3_SEL 7 5] \
        [list L2_SEL 4 3] \
        [list L1_SEL 2 2] \
        [list L0_SEL 1 1] \
    ]]

# IOU_SLCR.BANK0_CTRL0
dict set ::QEMU_REGS 4279763256 [dict create \
    name    BANK0_CTRL0 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE0 25 0] \
    ]]

# IOU_SLCR.BANK0_CTRL1
dict set ::QEMU_REGS 4279763260 [dict create \
    name    BANK0_CTRL1 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE1 25 0] \
    ]]

# IOU_SLCR.BANK0_CTRL3
dict set ::QEMU_REGS 4279763264 [dict create \
    name    BANK0_CTRL3 \
    block   IOU_SLCR \
    fields  [list \
        [list SCHMITT_CMOS_N 25 0] \
    ]]

# IOU_SLCR.BANK0_CTRL4
dict set ::QEMU_REGS 4279763268 [dict create \
    name    BANK0_CTRL4 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_HIGH_LOW_N 25 0] \
    ]]

# IOU_SLCR.BANK0_CTRL5
dict set ::QEMU_REGS 4279763272 [dict create \
    name    BANK0_CTRL5 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_ENABLE 25 0] \
    ]]

# IOU_SLCR.BANK0_CTRL6
dict set ::QEMU_REGS 4279763276 [dict create \
    name    BANK0_CTRL6 \
    block   IOU_SLCR \
    fields  [list \
        [list SLOW_FAST_SLEW_N 25 0] \
    ]]

# IOU_SLCR.BANK0_STATUS
dict set ::QEMU_REGS 4279763280 [dict create \
    name    BANK0_STATUS \
    block   IOU_SLCR \
    fields  [list \
        [list VOLTAGE_MODE 0 0] \
    ]]

# IOU_SLCR.BANK1_CTRL0
dict set ::QEMU_REGS 4279763284 [dict create \
    name    BANK1_CTRL0 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE0 25 0] \
    ]]

# IOU_SLCR.BANK1_CTRL1
dict set ::QEMU_REGS 4279763288 [dict create \
    name    BANK1_CTRL1 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE1 25 0] \
    ]]

# IOU_SLCR.BANK1_CTRL3
dict set ::QEMU_REGS 4279763292 [dict create \
    name    BANK1_CTRL3 \
    block   IOU_SLCR \
    fields  [list \
        [list SCHMITT_CMOS_N 25 0] \
    ]]

# IOU_SLCR.BANK1_CTRL4
dict set ::QEMU_REGS 4279763296 [dict create \
    name    BANK1_CTRL4 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_HIGH_LOW_N 25 0] \
    ]]

# IOU_SLCR.BANK1_CTRL5
dict set ::QEMU_REGS 4279763300 [dict create \
    name    BANK1_CTRL5 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_ENABLE_13_TO_0 25 12] \
        [list PULL_ENABLE_25_TO_14 11 0] \
    ]]

# IOU_SLCR.BANK1_CTRL6
dict set ::QEMU_REGS 4279763304 [dict create \
    name    BANK1_CTRL6 \
    block   IOU_SLCR \
    fields  [list \
        [list SLOW_FAST_SLEW_N 25 0] \
    ]]

# IOU_SLCR.BANK1_STATUS
dict set ::QEMU_REGS 4279763308 [dict create \
    name    BANK1_STATUS \
    block   IOU_SLCR \
    fields  [list \
        [list VOLTAGE_MODE 0 0] \
    ]]

# IOU_SLCR.BANK2_CTRL0
dict set ::QEMU_REGS 4279763312 [dict create \
    name    BANK2_CTRL0 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE0 25 0] \
    ]]

# IOU_SLCR.BANK2_CTRL1
dict set ::QEMU_REGS 4279763316 [dict create \
    name    BANK2_CTRL1 \
    block   IOU_SLCR \
    fields  [list \
        [list DRIVE1 25 0] \
    ]]

# IOU_SLCR.BANK2_CTRL3
dict set ::QEMU_REGS 4279763320 [dict create \
    name    BANK2_CTRL3 \
    block   IOU_SLCR \
    fields  [list \
        [list SCHMITT_CMOS_N 25 0] \
    ]]

# IOU_SLCR.BANK2_CTRL4
dict set ::QEMU_REGS 4279763324 [dict create \
    name    BANK2_CTRL4 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_HIGH_LOW_N 25 0] \
    ]]

# IOU_SLCR.BANK2_CTRL5
dict set ::QEMU_REGS 4279763328 [dict create \
    name    BANK2_CTRL5 \
    block   IOU_SLCR \
    fields  [list \
        [list PULL_ENABLE 25 0] \
    ]]

# IOU_SLCR.BANK2_CTRL6
dict set ::QEMU_REGS 4279763332 [dict create \
    name    BANK2_CTRL6 \
    block   IOU_SLCR \
    fields  [list \
        [list SLOW_FAST_SLEW_N 25 0] \
    ]]

# IOU_SLCR.BANK2_STATUS
dict set ::QEMU_REGS 4279763336 [dict create \
    name    BANK2_STATUS \
    block   IOU_SLCR \
    fields  [list \
        [list VOLTAGE_MODE 0 0] \
    ]]

# IOU_SLCR.MIO_LOOPBACK
dict set ::QEMU_REGS 4279763456 [dict create \
    name    MIO_LOOPBACK \
    block   IOU_SLCR \
    fields  [list \
        [list I2C0_LOOP_I2C1 3 3] \
        [list CAN0_LOOP_CAN1 2 2] \
        [list UA0_LOOP_UA1 1 1] \
        [list SPI0_LOOP_SPI1 0 0] \
    ]]

# IOU_SLCR.MIO_MST_TRI0
dict set ::QEMU_REGS 4279763460 [dict create \
    name    MIO_MST_TRI0 \
    block   IOU_SLCR \
    fields  [list \
        [list PIN_31_TRI 31 31] \
        [list PIN_30_TRI 30 30] \
        [list PIN_29_TRI 29 29] \
        [list PIN_28_TRI 28 28] \
        [list PIN_27_TRI 27 27] \
        [list PIN_26_TRI 26 26] \
        [list PIN_25_TRI 25 25] \
        [list PIN_24_TRI 24 24] \
        [list PIN_23_TRI 23 23] \
        [list PIN_22_TRI 22 22] \
        [list PIN_21_TRI 21 21] \
        [list PIN_20_TRI 20 20] \
        [list PIN_19_TRI 19 19] \
        [list PIN_18_TRI 18 18] \
        [list PIN_17_TRI 17 17] \
        [list PIN_16_TRI 16 16] \
        [list PIN_15_TRI 15 15] \
        [list PIN_14_TRI 14 14] \
        [list PIN_13_TRI 13 13] \
        [list PIN_12_TRI 12 12] \
        [list PIN_11_TRI 11 11] \
        [list PIN_10_TRI 10 10] \
        [list PIN_09_TRI 9 9] \
        [list PIN_08_TRI 8 8] \
        [list PIN_07_TRI 7 7] \
        [list PIN_06_TRI 6 6] \
        [list PIN_05_TRI 5 5] \
        [list PIN_04_TRI 4 4] \
        [list PIN_03_TRI 3 3] \
        [list PIN_02_TRI 2 2] \
        [list PIN_01_TRI 1 1] \
        [list PIN_00_TRI 0 0] \
    ]]

# IOU_SLCR.MIO_MST_TRI1
dict set ::QEMU_REGS 4279763464 [dict create \
    name    MIO_MST_TRI1 \
    block   IOU_SLCR \
    fields  [list \
        [list PIN_63_TRI 31 31] \
        [list PIN_62_TRI 30 30] \
        [list PIN_61_TRI 29 29] \
        [list PIN_60_TRI 28 28] \
        [list PIN_59_TRI 27 27] \
        [list PIN_58_TRI 26 26] \
        [list PIN_57_TRI 25 25] \
        [list PIN_56_TRI 24 24] \
        [list PIN_55_TRI 23 23] \
        [list PIN_54_TRI 22 22] \
        [list PIN_53_TRI 21 21] \
        [list PIN_52_TRI 20 20] \
        [list PIN_51_TRI 19 19] \
        [list PIN_50_TRI 18 18] \
        [list PIN_49_TRI 17 17] \
        [list PIN_48_TRI 16 16] \
        [list PIN_47_TRI 15 15] \
        [list PIN_46_TRI 14 14] \
        [list PIN_45_TRI 13 13] \
        [list PIN_44_TRI 12 12] \
        [list PIN_43_TRI 11 11] \
        [list PIN_42_TRI 10 10] \
        [list PIN_41_TRI 9 9] \
        [list PIN_40_TRI 8 8] \
        [list PIN_39_TRI 7 7] \
        [list PIN_38_TRI 6 6] \
        [list PIN_37_TRI 5 5] \
        [list PIN_36_TRI 4 4] \
        [list PIN_35_TRI 3 3] \
        [list PIN_34_TRI 2 2] \
        [list PIN_33_TRI 1 1] \
        [list PIN_32_TRI 0 0] \
    ]]

# IOU_SLCR.MIO_MST_TRI2
dict set ::QEMU_REGS 4279763468 [dict create \
    name    MIO_MST_TRI2 \
    block   IOU_SLCR \
    fields  [list \
        [list PIN_77_TRI 13 13] \
        [list PIN_76_TRI 12 12] \
        [list PIN_75_TRI 11 11] \
        [list PIN_74_TRI 10 10] \
        [list PIN_73_TRI 9 9] \
        [list PIN_72_TRI 8 8] \
        [list PIN_71_TRI 7 7] \
        [list PIN_70_TRI 6 6] \
        [list PIN_69_TRI 5 5] \
        [list PIN_68_TRI 4 4] \
        [list PIN_67_TRI 3 3] \
        [list PIN_66_TRI 2 2] \
        [list PIN_65_TRI 1 1] \
        [list PIN_64_TRI 0 0] \
    ]]

# IOU_SLCR.WDT_CLK_SEL
dict set ::QEMU_REGS 4279763712 [dict create \
    name    WDT_CLK_SEL \
    block   IOU_SLCR \
    fields  [list \
        [list SELECT 0 0] \
    ]]

# IOU_SLCR.CAN_MIO_CTRL
dict set ::QEMU_REGS 4279763716 [dict create \
    name    CAN_MIO_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list CAN1_RXIN_REG 23 23] \
        [list CAN1_REF_SEL 22 22] \
        [list CAN1_MUX 21 15] \
        [list CAN0_RXIN_REG 8 8] \
        [list CAN0_REF_SEL 7 7] \
        [list CAN0_MUX 6 0] \
    ]]

# IOU_SLCR.GEM_CLK_CTRL
dict set ::QEMU_REGS 4279763720 [dict create \
    name    GEM_CLK_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list TSU_CLK_LB_SEL 22 22] \
        [list TSU_CLK_SEL 21 20] \
        [list GEM3_FIFO_CLK_SEL 18 18] \
        [list GEM3_SGMII_MODE 17 17] \
        [list GEM3_REF_SRC_SEL 16 16] \
        [list GEM3_RX_SRC_SEL 15 15] \
        [list GEM2_FIFO_CLK_SEL 13 13] \
        [list GEM2_SGMII_MODE 12 12] \
        [list GEM2_REF_SRC_SEL 11 11] \
        [list GEM2_RX_SRC_SEL 10 10] \
        [list GEM1_FIFO_CLK_SEL 8 8] \
        [list GEM1_SGMII_MODE 7 7] \
        [list GEM1_REF_SRC_SEL 6 6] \
        [list GEM1_RX_SRC_SEL 5 5] \
        [list GEM0_FIFO_CLK_SEL 3 3] \
        [list GEM0_SGMII_MODE 2 2] \
        [list GEM0_REF_SRC_SEL 1 1] \
        [list GEM0_RX_SRC_SEL 0 0] \
    ]]

# IOU_SLCR.SDIO_CLK_CTRL
dict set ::QEMU_REGS 4279763724 [dict create \
    name    SDIO_CLK_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list SDIO1_FBCLK_SEL 18 18] \
        [list SDIO1_RX_SRC_SEL 17 17] \
        [list SDIO0_FBCLK_SEL 2 2] \
        [list SDIO0_RX_SRC_SEL 1 0] \
    ]]

# IOU_SLCR.CTRL_REG_SD
dict set ::QEMU_REGS 4279763728 [dict create \
    name    CTRL_REG_SD \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_EMMC_SEL 15 15] \
        [list SD0_EMMC_SEL 0 0] \
    ]]

# IOU_SLCR.SD_ITAPDLY
dict set ::QEMU_REGS 4279763732 [dict create \
    name    SD_ITAPDLY \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_ITAPCHGWIN 25 25] \
        [list SD1_ITAPDLYENA 24 24] \
        [list SD1_ITAPDLYSEL 23 16] \
        [list SD0_ITAPCHGWIN 9 9] \
        [list SD0_ITAPDLYENA 8 8] \
        [list SD0_ITAPDLYSEL 7 0] \
    ]]

# IOU_SLCR.SD_OTAPDLYSEL
dict set ::QEMU_REGS 4279763736 [dict create \
    name    SD_OTAPDLYSEL \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_OTAPDLYENA 22 22] \
        [list SD1_OTAPDLYSEL 21 16] \
        [list SD0_OTAPDLYENA 6 6] \
        [list SD0_OTAPDLYSEL 5 0] \
    ]]

# IOU_SLCR.SD_CONFIG_REG1
dict set ::QEMU_REGS 4279763740 [dict create \
    name    SD_CONFIG_REG1 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_BASECLK 30 23] \
        [list SD1_TUNIGCOUNT 22 17] \
        [list SD1_ASYNCWKPENA 16 16] \
        [list SD0_BASECLK 14 7] \
        [list SD0_TUNIGCOUNT 6 1] \
        [list SD0_ASYNCWKPENA 0 0] \
    ]]

# IOU_SLCR.SD_CONFIG_REG2
dict set ::QEMU_REGS 4279763744 [dict create \
    name    SD_CONFIG_REG2 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_SLOTTYPE 29 28] \
        [list SD1_ASYCINTR 27 27] \
        [list SD1_64BIT 26 26] \
        [list SD1_1P8V 25 25] \
        [list SD1_3P0V 24 24] \
        [list SD1_3P3V 23 23] \
        [list SD1_SUSPRES 22 22] \
        [list SD1_SDMA 21 21] \
        [list SD1_HIGHSPEED 20 20] \
        [list SD1_ADMA2 19 19] \
        [list SD1_8BIT 18 18] \
        [list SD1_MAXBLK 17 16] \
        [list SD0_SLOTTYPE 13 12] \
        [list SD0_ASYCINTR 11 11] \
        [list SD0_64BIT 10 10] \
        [list SD0_1P8V 9 9] \
        [list SD0_3P0V 8 8] \
        [list SD0_3P3V 7 7] \
        [list SD0_SUSPRES 6 6] \
        [list SD0_SDMA 5 5] \
        [list SD0_HIGHSPEED 4 4] \
        [list SD0_ADMA2 3 3] \
        [list SD0_8BIT 2 2] \
        [list SD0_MAXBLK 1 0] \
    ]]

# IOU_SLCR.SD_CONFIG_REG3
dict set ::QEMU_REGS 4279763748 [dict create \
    name    SD_CONFIG_REG3 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_TUNINGSDR50 26 26] \
        [list SD1_RETUNETMR 25 22] \
        [list SD1_DDRIVER 21 21] \
        [list SD1_CDRIVER 20 20] \
        [list SD1_ADRIVER 19 19] \
        [list SD1_DDR50 18 18] \
        [list SD1_SDR104 17 17] \
        [list SD1_SDR50 16 16] \
        [list SD0_TUNINGSDR50 10 10] \
        [list SD0_RETUNETMR 9 6] \
        [list SD0_DDRIVER 5 5] \
        [list SD0_CDRIVER 4 4] \
        [list SD0_ADRIVER 3 3] \
        [list SD0_DDR50 2 2] \
        [list SD0_SDR104 1 1] \
        [list SD0_SDR50 0 0] \
    ]]

# IOU_SLCR.SD_INITPRESET
dict set ::QEMU_REGS 4279763752 [dict create \
    name    SD_INITPRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_INITPRESET 28 16] \
        [list SD0_INITPRESET 12 0] \
    ]]

# IOU_SLCR.SD_DSPPRESET
dict set ::QEMU_REGS 4279763756 [dict create \
    name    SD_DSPPRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_DSPPRESET 28 16] \
        [list SD0_DSPPRESET 12 0] \
    ]]

# IOU_SLCR.SD_HSPDPRESET
dict set ::QEMU_REGS 4279763760 [dict create \
    name    SD_HSPDPRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_HSPDPRESET 28 16] \
        [list SD0_HSPDPRESET 12 0] \
    ]]

# IOU_SLCR.SD_SDR12PRESET
dict set ::QEMU_REGS 4279763764 [dict create \
    name    SD_SDR12PRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_SDR12PRESET 28 16] \
        [list SD0_SDR12PRESET 12 0] \
    ]]

# IOU_SLCR.SD_SDR25PRESET
dict set ::QEMU_REGS 4279763768 [dict create \
    name    SD_SDR25PRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_SDR25PRESET 28 16] \
        [list SD0_SDR25PRESET 12 0] \
    ]]

# IOU_SLCR.SD_SDR50PRSET
dict set ::QEMU_REGS 4279763772 [dict create \
    name    SD_SDR50PRSET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_SDR50PRESET 28 16] \
        [list SD0_SDR50PRESET 12 0] \
    ]]

# IOU_SLCR.SD_SDR104PRST
dict set ::QEMU_REGS 4279763776 [dict create \
    name    SD_SDR104PRST \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_SDR104PRESET 28 16] \
        [list SD0_SDR104PRESET 12 0] \
    ]]

# IOU_SLCR.SD_DDR50PRESET
dict set ::QEMU_REGS 4279763780 [dict create \
    name    SD_DDR50PRESET \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_DDR50PRESET 28 16] \
        [list SD0_DDR50PRESET 12 0] \
    ]]

# IOU_SLCR.SD_MAXCUR1P8
dict set ::QEMU_REGS 4279763788 [dict create \
    name    SD_MAXCUR1P8 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_MAXCUR1P8 23 16] \
        [list SD0_MAXCUR1P8 7 0] \
    ]]

# IOU_SLCR.SD_MAXCUR3P0
dict set ::QEMU_REGS 4279763792 [dict create \
    name    SD_MAXCUR3P0 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_MAXCUR3P0 23 16] \
        [list SD0_MAXCUR3P0 7 0] \
    ]]

# IOU_SLCR.SD_MAXCUR3P3
dict set ::QEMU_REGS 4279763796 [dict create \
    name    SD_MAXCUR3P3 \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_MAXCUR3P3 23 16] \
        [list SD0_MAXCUR3P3 7 0] \
    ]]

# IOU_SLCR.SD_DLL_CTRL
dict set ::QEMU_REGS 4279763800 [dict create \
    name    SD_DLL_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_DLL_RST 18 18] \
        [list SD1_DLL_TESTMODE 17 17] \
        [list SD1_DLL_LOCK 16 16] \
        [list SD0_DLL_RST 2 2] \
        [list SD0_DLL_TESTMODE 1 1] \
        [list SD0_DLL_LOCK 0 0] \
    ]]

# IOU_SLCR.SD_CDN_CTRL
dict set ::QEMU_REGS 4279763804 [dict create \
    name    SD_CDN_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list SD1_CDN_CTRL 16 16] \
        [list SD0_CDN_CTRL 0 0] \
    ]]

# IOU_SLCR.GEM_CTRL
dict set ::QEMU_REGS 4279763808 [dict create \
    name    GEM_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list GEM3_SGMII_SD 7 6] \
        [list GEM2_SGMII_SD 5 4] \
        [list GEM1_SGMII_SD 3 2] \
        [list GEM0_SGMII_SD 1 0] \
    ]]

# IOU_SLCR.IOU_TTC_APB_CLK
dict set ::QEMU_REGS 4279763840 [dict create \
    name    IOU_TTC_APB_CLK \
    block   IOU_SLCR \
    fields  [list \
        [list TTC3_SEL 7 6] \
        [list TTC2_SEL 5 4] \
        [list TTC1_SEL 3 2] \
        [list TTC0_SEL 1 0] \
    ]]

# IOU_SLCR.IOU_TAPDLY_BYPASS
dict set ::QEMU_REGS 4279763856 [dict create \
    name    IOU_TAPDLY_BYPASS \
    block   IOU_SLCR \
    fields  [list \
        [list LQSPI_RX 2 2] \
        [list NAND_DQS_OUT 1 1] \
        [list NAND_DQS_IN 0 0] \
    ]]

# IOU_SLCR.IOU_COHERENT_CTRL
dict set ::QEMU_REGS 4279763968 [dict create \
    name    IOU_COHERENT_CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list QSPI_AXI_COH 31 28] \
        [list NAND_AXI_COH 27 24] \
        [list SD1_AXI_COH 23 20] \
        [list SD0_AXI_COH 19 16] \
        [list GEM3_AXI_COH 15 12] \
        [list GEM2_AXI_COH 11 8] \
        [list GEM1_AXI_COH 7 4] \
        [list GEM0_AXI_COH 3 0] \
    ]]

# IOU_SLCR.VIDEO_PSS_CLK_SEL
dict set ::QEMU_REGS 4279763972 [dict create \
    name    VIDEO_PSS_CLK_SEL \
    block   IOU_SLCR \
    fields  [list \
        [list PSS_ALT_CLK 1 1] \
        [list VIDEO_CLK 0 0] \
    ]]

# IOU_SLCR.IOU_INTERCONNECT_ROUTE
dict set ::QEMU_REGS 4279763976 [dict create \
    name    IOU_INTERCONNECT_ROUTE \
    block   IOU_SLCR \
    fields  [list \
        [list NAND 7 7] \
        [list QSPI 6 6] \
        [list SD1 5 5] \
        [list SD0 4 4] \
        [list GEM3 3 3] \
        [list GEM2 2 2] \
        [list GEM1 1 1] \
        [list GEM0 0 0] \
    ]]

# IOU_SLCR.IOU_RAM_GEM0
dict set ::QEMU_REGS 4279764224 [dict create \
    name    IOU_RAM_GEM0 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_GEM1
dict set ::QEMU_REGS 4279764228 [dict create \
    name    IOU_RAM_GEM1 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_GEM2
dict set ::QEMU_REGS 4279764232 [dict create \
    name    IOU_RAM_GEM2 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_GEM3
dict set ::QEMU_REGS 4279764236 [dict create \
    name    IOU_RAM_GEM3 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_SD0
dict set ::QEMU_REGS 4279764240 [dict create \
    name    IOU_RAM_SD0 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_SD1
dict set ::QEMU_REGS 4279764244 [dict create \
    name    IOU_RAM_SD1 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_CAN0
dict set ::QEMU_REGS 4279764248 [dict create \
    name    IOU_RAM_CAN0 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA2 22 22] \
        [list EMAB2 21 19] \
        [list EMAA2 18 16] \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_CAN1
dict set ::QEMU_REGS 4279764252 [dict create \
    name    IOU_RAM_CAN1 \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA2 22 22] \
        [list EMAB2 21 19] \
        [list EMAA2 18 16] \
        [list EMASA1 14 14] \
        [list EMAB1 13 11] \
        [list EMAA1 10 8] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_LQSPI
dict set ::QEMU_REGS 4279764256 [dict create \
    name    IOU_RAM_LQSPI \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA1 13 13] \
        [list EMAB1 12 10] \
        [list EMAA1 9 7] \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.IOU_RAM_NAND
dict set ::QEMU_REGS 4279764260 [dict create \
    name    IOU_RAM_NAND \
    block   IOU_SLCR \
    fields  [list \
        [list EMASA0 6 6] \
        [list EMAB0 5 3] \
        [list EMAA0 2 0] \
    ]]

# IOU_SLCR.CTRL
dict set ::QEMU_REGS 4279764480 [dict create \
    name    CTRL \
    block   IOU_SLCR \
    fields  [list \
        [list SLVERR_ENABLE 0 0] \
    ]]

# IOU_SLCR.ISR
dict set ::QEMU_REGS 4279764736 [dict create \
    name    ISR \
    block   IOU_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# IOU_SLCR.IMR
dict set ::QEMU_REGS 4279764740 [dict create \
    name    IMR \
    block   IOU_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# IOU_SLCR.IER
dict set ::QEMU_REGS 4279764744 [dict create \
    name    IER \
    block   IOU_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# IOU_SLCR.IDR
dict set ::QEMU_REGS 4279764748 [dict create \
    name    IDR \
    block   IOU_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# IOU_SLCR.ITR
dict set ::QEMU_REGS 4279764752 [dict create \
    name    ITR \
    block   IOU_SLCR \
    fields  [list \
        [list ADDR_DECODE_ERR 0 0] \
    ]]

# IPI.IPI_TRIG
dict set ::QEMU_REGS 4281335808 [dict create \
    name    IPI_TRIG \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# IPI.IPI_OBS
dict set ::QEMU_REGS 4281335812 [dict create \
    name    IPI_OBS \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# IPI.IPI_ISR
dict set ::QEMU_REGS 4281335824 [dict create \
    name    IPI_ISR \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# IPI.IPI_IMR
dict set ::QEMU_REGS 4281335828 [dict create \
    name    IPI_IMR \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# IPI.IPI_IER
dict set ::QEMU_REGS 4281335832 [dict create \
    name    IPI_IER \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# IPI.IPI_IDR
dict set ::QEMU_REGS 4281335836 [dict create \
    name    IPI_IDR \
    block   IPI \
    fields  [list \
        [list PL_3 27 27] \
        [list PL_2 26 26] \
        [list PL_1 25 25] \
        [list PL_0 24 24] \
        [list PMU_3 19 19] \
        [list PMU_2 18 18] \
        [list PMU_1 17 17] \
        [list PMU_0 16 16] \
        [list RPU_1 9 9] \
        [list RPU_0 8 8] \
        [list APU 0 0] \
    ]]

# OCM_XMPU.CTRL
dict set ::QEMU_REGS 4289134592 [dict create \
    name    CTRL \
    block   OCM_XMPU \
    fields  [list \
        [list ALIGNCFG 3 3] \
        [list HIDEALLOWED 2 2] \
        [list DEFWRALLOWED 1 1] \
        [list DEFRDALLOWED 0 0] \
    ]]

# OCM_XMPU.ISR
dict set ::QEMU_REGS 4289134608 [dict create \
    name    ISR \
    block   OCM_XMPU \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# OCM_XMPU.IMR
dict set ::QEMU_REGS 4289134612 [dict create \
    name    IMR \
    block   OCM_XMPU \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# OCM_XMPU.IEN
dict set ::QEMU_REGS 4289134616 [dict create \
    name    IEN \
    block   OCM_XMPU \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# OCM_XMPU.IDS
dict set ::QEMU_REGS 4289134620 [dict create \
    name    IDS \
    block   OCM_XMPU \
    fields  [list \
        [list SECURITYVIO 3 3] \
        [list WRPERMVIO 2 2] \
        [list RDPERMVIO 1 1] \
        [list INV_APB 0 0] \
    ]]

# OCM_XMPU.LOCK
dict set ::QEMU_REGS 4289134624 [dict create \
    name    LOCK \
    block   OCM_XMPU \
    fields  [list \
        [list REGWRDIS 0 0] \
    ]]

# OCM_XMPU.ECO
dict set ::QEMU_REGS 4289134844 [dict create \
    name    ECO \
    block   OCM_XMPU \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_CNTRL
dict set ::QEMU_REGS 4292345856 [dict create \
    name    GLOBAL_CNTRL \
    block   PMU_GLOBAL \
    fields  [list \
        [list MB_SLEEP 16 16] \
        [list WRITE_QOS 15 12] \
        [list READ_QOS 11 8] \
        [list FW_IS_PRESENT 4 4] \
        [list COHERENT 2 2] \
        [list SLVERR_ENABLE 1 1] \
        [list DONT_SLEEP 0 0] \
    ]]

# PMU_GLOBAL.PS_CNTRL
dict set ::QEMU_REGS 4292345860 [dict create \
    name    PS_CNTRL \
    block   PMU_GLOBAL \
    fields  [list \
        [list PROG_GATE_STATUS 16 16] \
        [list PROG_ENABLE 1 1] \
        [list PROG_GATE 0 0] \
    ]]

# PMU_GLOBAL.APU_PWR_STATUS_INIT
dict set ::QEMU_REGS 4292345864 [dict create \
    name    APU_PWR_STATUS_INIT \
    block   PMU_GLOBAL \
    fields  [list \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.ADDR_ERROR_STATUS
dict set ::QEMU_REGS 4292345872 [dict create \
    name    ADDR_ERROR_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list STATUS 0 0] \
    ]]

# PMU_GLOBAL.ADDR_ERROR_INT_MASK
dict set ::QEMU_REGS 4292345876 [dict create \
    name    ADDR_ERROR_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list MASK 0 0] \
    ]]

# PMU_GLOBAL.ADDR_ERROR_INT_EN
dict set ::QEMU_REGS 4292345880 [dict create \
    name    ADDR_ERROR_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list ENABLE 0 0] \
    ]]

# PMU_GLOBAL.ADDR_ERROR_INT_DIS
dict set ::QEMU_REGS 4292345884 [dict create \
    name    ADDR_ERROR_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list DISABLE 0 0] \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE0
dict set ::QEMU_REGS 4292345904 [dict create \
    name    GLOBAL_GEN_STORAGE0 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE1
dict set ::QEMU_REGS 4292345908 [dict create \
    name    GLOBAL_GEN_STORAGE1 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE2
dict set ::QEMU_REGS 4292345912 [dict create \
    name    GLOBAL_GEN_STORAGE2 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE3
dict set ::QEMU_REGS 4292345916 [dict create \
    name    GLOBAL_GEN_STORAGE3 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE4
dict set ::QEMU_REGS 4292345920 [dict create \
    name    GLOBAL_GEN_STORAGE4 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE5
dict set ::QEMU_REGS 4292345924 [dict create \
    name    GLOBAL_GEN_STORAGE5 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.GLOBAL_GEN_STORAGE6
dict set ::QEMU_REGS 4292345928 [dict create \
    name    GLOBAL_GEN_STORAGE6 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE0
dict set ::QEMU_REGS 4292345936 [dict create \
    name    PERS_GLOB_GEN_STORAGE0 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE1
dict set ::QEMU_REGS 4292345940 [dict create \
    name    PERS_GLOB_GEN_STORAGE1 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE2
dict set ::QEMU_REGS 4292345944 [dict create \
    name    PERS_GLOB_GEN_STORAGE2 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE3
dict set ::QEMU_REGS 4292345948 [dict create \
    name    PERS_GLOB_GEN_STORAGE3 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE4
dict set ::QEMU_REGS 4292345952 [dict create \
    name    PERS_GLOB_GEN_STORAGE4 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE5
dict set ::QEMU_REGS 4292345956 [dict create \
    name    PERS_GLOB_GEN_STORAGE5 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE6
dict set ::QEMU_REGS 4292345960 [dict create \
    name    PERS_GLOB_GEN_STORAGE6 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.PERS_GLOB_GEN_STORAGE7
dict set ::QEMU_REGS 4292345964 [dict create \
    name    PERS_GLOB_GEN_STORAGE7 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.DDR_CNTRL
dict set ::QEMU_REGS 4292345968 [dict create \
    name    DDR_CNTRL \
    block   PMU_GLOBAL \
    fields  [list \
        [list RET 0 0] \
    ]]

# PMU_GLOBAL.PWR_STATE
dict set ::QEMU_REGS 4292346112 [dict create \
    name    PWR_STATE \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list R5_1 11 11] \
        [list R5_0 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.AUX_PWR_STATE
dict set ::QEMU_REGS 4292346116 [dict create \
    name    AUX_PWR_STATE \
    block   PMU_GLOBAL \
    fields  [list \
        [list ACPU3_EMULATION 31 31] \
        [list ACPU2_EMULATION 30 30] \
        [list ACPU1_EMULATION 29 29] \
        [list ACPU0_EMULATION 28 28] \
        [list RPU_EMULATION 27 27] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list L2_BANK0 7 7] \
    ]]

# PMU_GLOBAL.RAM_RET_CNTRL
dict set ::QEMU_REGS 4292346120 [dict create \
    name    RAM_RET_CNTRL \
    block   PMU_GLOBAL \
    fields  [list \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list L2_BANK0 7 7] \
    ]]

# PMU_GLOBAL.PWR_SUPPLY_STATUS
dict set ::QEMU_REGS 4292346124 [dict create \
    name    PWR_SUPPLY_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list VCC_PSAUX 2 2] \
        [list VCC_INT 1 1] \
        [list VCC_PSINTFP 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRUP_STATUS
dict set ::QEMU_REGS 4292346128 [dict create \
    name    REQ_PWRUP_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRUP_INT_MASK
dict set ::QEMU_REGS 4292346132 [dict create \
    name    REQ_PWRUP_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRUP_INT_EN
dict set ::QEMU_REGS 4292346136 [dict create \
    name    REQ_PWRUP_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRUP_INT_DIS
dict set ::QEMU_REGS 4292346140 [dict create \
    name    REQ_PWRUP_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRUP_TRIG
dict set ::QEMU_REGS 4292346144 [dict create \
    name    REQ_PWRUP_TRIG \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRDWN_STATUS
dict set ::QEMU_REGS 4292346384 [dict create \
    name    REQ_PWRDWN_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRDWN_INT_MASK
dict set ::QEMU_REGS 4292346388 [dict create \
    name    REQ_PWRDWN_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRDWN_INT_EN
dict set ::QEMU_REGS 4292346392 [dict create \
    name    REQ_PWRDWN_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRDWN_INT_DIS
dict set ::QEMU_REGS 4292346396 [dict create \
    name    REQ_PWRDWN_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_PWRDWN_TRIG
dict set ::QEMU_REGS 4292346400 [dict create \
    name    REQ_PWRDWN_TRIG \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 23 23] \
        [list FP 22 22] \
        [list USB1 21 21] \
        [list USB0 20 20] \
        [list OCM_BANK3 19 19] \
        [list OCM_BANK2 18 18] \
        [list OCM_BANK1 17 17] \
        [list OCM_BANK0 16 16] \
        [list TCM1B 15 15] \
        [list TCM1A 14 14] \
        [list TCM0B 13 13] \
        [list TCM0A 12 12] \
        [list RPU 10 10] \
        [list L2_BANK0 7 7] \
        [list PP1 5 5] \
        [list PP0 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_ISO_STATUS
dict set ::QEMU_REGS 4292346640 [dict create \
    name    REQ_ISO_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP_LOCKED 4 4] \
        [list PL_NONPCAP 2 2] \
        [list PL 1 1] \
        [list FP 0 0] \
    ]]

# PMU_GLOBAL.REQ_ISO_INT_MASK
dict set ::QEMU_REGS 4292346644 [dict create \
    name    REQ_ISO_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP_LOCKED 4 4] \
        [list PL_NONPCAP 2 2] \
        [list PL 1 1] \
        [list FP 0 0] \
    ]]

# PMU_GLOBAL.REQ_ISO_INT_EN
dict set ::QEMU_REGS 4292346648 [dict create \
    name    REQ_ISO_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP_LOCKED 4 4] \
        [list PL_NONPCAP 2 2] \
        [list PL 1 1] \
        [list FP 0 0] \
    ]]

# PMU_GLOBAL.REQ_ISO_INT_DIS
dict set ::QEMU_REGS 4292346652 [dict create \
    name    REQ_ISO_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP_LOCKED 4 4] \
        [list PL_NONPCAP 2 2] \
        [list PL 1 1] \
        [list FP 0 0] \
    ]]

# PMU_GLOBAL.REQ_ISO_TRIG
dict set ::QEMU_REGS 4292346656 [dict create \
    name    REQ_ISO_TRIG \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP_LOCKED 4 4] \
        [list PL_NONPCAP 2 2] \
        [list PL 1 1] \
        [list FP 0 0] \
    ]]

# PMU_GLOBAL.REQ_SWRST_STATUS
dict set ::QEMU_REGS 4292346896 [dict create \
    name    REQ_SWRST_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 31 31] \
        [list FP 30 30] \
        [list LP 29 29] \
        [list PS_ONLY 28 28] \
        [list IOU 27 27] \
        [list USB1 25 25] \
        [list USB0 24 24] \
        [list GEM3 23 23] \
        [list GEM2 22 22] \
        [list GEM1 21 21] \
        [list GEM0 20 20] \
        [list RPU 18 18] \
        [list R5_1 17 17] \
        [list R5_0 16 16] \
        [list DISPLAY_PORT 12 12] \
        [list SATA 10 10] \
        [list PCIE 9 9] \
        [list GPU 8 8] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list APU 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_SWRST_INT_MASK
dict set ::QEMU_REGS 4292346900 [dict create \
    name    REQ_SWRST_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 31 31] \
        [list FP 30 30] \
        [list LP 29 29] \
        [list PS_ONLY 28 28] \
        [list IOU 27 27] \
        [list USB1 25 25] \
        [list USB0 24 24] \
        [list GEM3 23 23] \
        [list GEM2 22 22] \
        [list GEM1 21 21] \
        [list GEM0 20 20] \
        [list LS_R5 18 18] \
        [list R5_1 17 17] \
        [list R5_0 16 16] \
        [list DISPLAY_PORT 12 12] \
        [list SATA 10 10] \
        [list PCIE 9 9] \
        [list GPU 8 8] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list APU 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_SWRST_INT_EN
dict set ::QEMU_REGS 4292346904 [dict create \
    name    REQ_SWRST_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 31 31] \
        [list FP 30 30] \
        [list LP 29 29] \
        [list PS_ONLY 28 28] \
        [list IOU 27 27] \
        [list USB1 25 25] \
        [list USB0 24 24] \
        [list GEM3 23 23] \
        [list GEM2 22 22] \
        [list GEM1 21 21] \
        [list GEM0 20 20] \
        [list LS_R5 18 18] \
        [list R5_1 17 17] \
        [list R5_0 16 16] \
        [list DISPLAY_PORT 12 12] \
        [list SATA 10 10] \
        [list PCIE 9 9] \
        [list GPU 8 8] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list APU 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_SWRST_INT_DIS
dict set ::QEMU_REGS 4292346908 [dict create \
    name    REQ_SWRST_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 31 31] \
        [list FP 30 30] \
        [list LP 29 29] \
        [list PS_ONLY 28 28] \
        [list IOU 27 27] \
        [list USB1 25 25] \
        [list USB0 24 24] \
        [list GEM3 23 23] \
        [list GEM2 22 22] \
        [list GEM1 21 21] \
        [list GEM0 20 20] \
        [list LS_R5 18 18] \
        [list R5_1 17 17] \
        [list R5_0 16 16] \
        [list DISPLAY_PORT 12 12] \
        [list SATA 10 10] \
        [list PCIE 9 9] \
        [list GPU 8 8] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list APU 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_SWRST_TRIG
dict set ::QEMU_REGS 4292346912 [dict create \
    name    REQ_SWRST_TRIG \
    block   PMU_GLOBAL \
    fields  [list \
        [list PL 31 31] \
        [list FP 30 30] \
        [list LP 29 29] \
        [list PS_ONLY 28 28] \
        [list IOU 27 27] \
        [list USB1 25 25] \
        [list USB0 24 24] \
        [list GEM3 23 23] \
        [list GEM2 22 22] \
        [list GEM1 21 21] \
        [list GEM0 20 20] \
        [list LS_R5 18 18] \
        [list R5_1 17 17] \
        [list R5_0 16 16] \
        [list DISPLAY_PORT 12 12] \
        [list SATA 10 10] \
        [list PCIE 9 9] \
        [list GPU 8 8] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list APU 4 4] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.REQ_AUX_STATUS
dict set ::QEMU_REGS 4292347152 [dict create \
    name    REQ_AUX_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list SERV_REQ_10 17 17] \
        [list SERV_REQ_9 16 16] \
        [list SERV_REQ_8 13 13] \
        [list SERV_REQ_7 12 12] \
        [list SERV_REQ_6 10 10] \
        [list SERV_REQ_5 7 7] \
        [list SERV_REQ_4 6 6] \
        [list SERV_REQ_3 3 3] \
        [list SERV_REQ_2 2 2] \
        [list SERV_REQ_1 1 1] \
        [list SERV_REQ_0 0 0] \
    ]]

# PMU_GLOBAL.REQ_AUX_INT_MASK
dict set ::QEMU_REGS 4292347156 [dict create \
    name    REQ_AUX_INT_MASK \
    block   PMU_GLOBAL \
    fields  [list \
        [list SERV_REQ_10 17 17] \
        [list SERV_REQ_9 16 16] \
        [list SERV_REQ_8 13 13] \
        [list SERV_REQ_7 12 12] \
        [list SERV_REQ_6 10 10] \
        [list SERV_REQ_5 7 7] \
        [list SERV_REQ_4 6 6] \
        [list SERV_REQ_3 3 3] \
        [list SERV_REQ_2 2 2] \
        [list SERV_REQ_1 1 1] \
        [list SERV_REQ_0 0 0] \
    ]]

# PMU_GLOBAL.REQ_AUX_INT_EN
dict set ::QEMU_REGS 4292347160 [dict create \
    name    REQ_AUX_INT_EN \
    block   PMU_GLOBAL \
    fields  [list \
        [list SERV_REQ_10 17 17] \
        [list SERV_REQ_9 16 16] \
        [list SERV_REQ_8 13 13] \
        [list SERV_REQ_7 12 12] \
        [list SERV_REQ_6 10 10] \
        [list SERV_REQ_5 7 7] \
        [list SERV_REQ_4 6 6] \
        [list SERV_REQ_3 3 3] \
        [list SERV_REQ_2 2 2] \
        [list SERV_REQ_1 1 1] \
        [list SERV_REQ_0 0 0] \
    ]]

# PMU_GLOBAL.REQ_AUX_INT_DIS
dict set ::QEMU_REGS 4292347164 [dict create \
    name    REQ_AUX_INT_DIS \
    block   PMU_GLOBAL \
    fields  [list \
        [list SERV_REQ_10 17 17] \
        [list SERV_REQ_9 16 16] \
        [list SERV_REQ_8 13 13] \
        [list SERV_REQ_7 12 12] \
        [list SERV_REQ_6 10 10] \
        [list SERV_REQ_5 7 7] \
        [list SERV_REQ_4 6 6] \
        [list SERV_REQ_3 3 3] \
        [list SERV_REQ_2 2 2] \
        [list SERV_REQ_1 1 1] \
        [list SERV_REQ_0 0 0] \
    ]]

# PMU_GLOBAL.REQ_AUX_TRIG
dict set ::QEMU_REGS 4292347168 [dict create \
    name    REQ_AUX_TRIG \
    block   PMU_GLOBAL \
    fields  [list \
        [list SERV_REQ_10 17 17] \
        [list SERV_REQ_9 16 16] \
        [list SERV_REQ_8 13 13] \
        [list SERV_REQ_7 12 12] \
        [list SERV_REQ_6 10 10] \
        [list SERV_REQ_5 7 7] \
        [list SERV_REQ_4 6 6] \
        [list SERV_REQ_3 3 3] \
        [list SERV_REQ_2 2 2] \
        [list SERV_REQ_1 1 1] \
        [list SERV_REQ_0 0 0] \
    ]]

# PMU_GLOBAL.LOGCLR_STATUS
dict set ::QEMU_REGS 4292347172 [dict create \
    name    LOGCLR_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list FP 17 17] \
        [list LP 16 16] \
        [list USB1 13 13] \
        [list USB0 12 12] \
        [list RPU 10 10] \
        [list PP1 7 7] \
        [list PP0 6 6] \
        [list ACPU3 3 3] \
        [list ACPU2 2 2] \
        [list ACPU1 1 1] \
        [list ACPU0 0 0] \
    ]]

# PMU_GLOBAL.CSU_BR_ERROR
dict set ::QEMU_REGS 4292347176 [dict create \
    name    CSU_BR_ERROR \
    block   PMU_GLOBAL \
    fields  [list \
        [list BR_ERROR 31 31] \
        [list ERR_TYPE 15 0] \
    ]]

# PMU_GLOBAL.MB_FAULT_STATUS
dict set ::QEMU_REGS 4292347180 [dict create \
    name    MB_FAULT_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list R_FFAIL 31 24] \
        [list R_SLEEP_RST 19 19] \
        [list R_LSFAIL 18 16] \
        [list N_FFAIL 15 8] \
        [list N_SLEEP_RST 3 3] \
        [list N_LSFAIL 2 0] \
    ]]

# PMU_GLOBAL.ERROR_STATUS_1
dict set ::QEMU_REGS 4292347184 [dict create \
    name    ERROR_STATUS_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_MASK_1
dict set ::QEMU_REGS 4292347188 [dict create \
    name    ERROR_INT_MASK_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_EN_1
dict set ::QEMU_REGS 4292347192 [dict create \
    name    ERROR_INT_EN_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_DIS_1
dict set ::QEMU_REGS 4292347196 [dict create \
    name    ERROR_INT_DIS_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_STATUS_2
dict set ::QEMU_REGS 4292347200 [dict create \
    name    ERROR_STATUS_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_MASK_2
dict set ::QEMU_REGS 4292347204 [dict create \
    name    ERROR_INT_MASK_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_EN_2
dict set ::QEMU_REGS 4292347208 [dict create \
    name    ERROR_INT_EN_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_INT_DIS_2
dict set ::QEMU_REGS 4292347212 [dict create \
    name    ERROR_INT_DIS_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_MASK_1
dict set ::QEMU_REGS 4292347216 [dict create \
    name    ERROR_POR_MASK_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_EN_1
dict set ::QEMU_REGS 4292347220 [dict create \
    name    ERROR_POR_EN_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_DIS_1
dict set ::QEMU_REGS 4292347224 [dict create \
    name    ERROR_POR_DIS_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_MASK_2
dict set ::QEMU_REGS 4292347228 [dict create \
    name    ERROR_POR_MASK_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_EN_2
dict set ::QEMU_REGS 4292347232 [dict create \
    name    ERROR_POR_EN_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_POR_DIS_2
dict set ::QEMU_REGS 4292347236 [dict create \
    name    ERROR_POR_DIS_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_MASK_1
dict set ::QEMU_REGS 4292347240 [dict create \
    name    ERROR_SRST_MASK_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_EN_1
dict set ::QEMU_REGS 4292347244 [dict create \
    name    ERROR_SRST_EN_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_DIS_1
dict set ::QEMU_REGS 4292347248 [dict create \
    name    ERROR_SRST_DIS_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_MASK_2
dict set ::QEMU_REGS 4292347252 [dict create \
    name    ERROR_SRST_MASK_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_EN_2
dict set ::QEMU_REGS 4292347256 [dict create \
    name    ERROR_SRST_EN_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SRST_DIS_2
dict set ::QEMU_REGS 4292347260 [dict create \
    name    ERROR_SRST_DIS_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_MASK_1
dict set ::QEMU_REGS 4292347264 [dict create \
    name    ERROR_SIG_MASK_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_EN_1
dict set ::QEMU_REGS 4292347268 [dict create \
    name    ERROR_SIG_EN_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_DIS_1
dict set ::QEMU_REGS 4292347272 [dict create \
    name    ERROR_SIG_DIS_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_MASK_2
dict set ::QEMU_REGS 4292347276 [dict create \
    name    ERROR_SIG_MASK_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_EN_2
dict set ::QEMU_REGS 4292347280 [dict create \
    name    ERROR_SIG_EN_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_SIG_DIS_2
dict set ::QEMU_REGS 4292347284 [dict create \
    name    ERROR_SIG_DIS_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.ERROR_EN_1
dict set ::QEMU_REGS 4292347296 [dict create \
    name    ERROR_EN_1 \
    block   PMU_GLOBAL \
    fields  [list \
        [list AUX3 31 31] \
        [list AUX2 30 30] \
        [list AUX1 29 29] \
        [list AUX0 28 28] \
        [list CSU_SWDT 27 27] \
        [list CLK_MON 26 26] \
        [list XMPU 25 24] \
        [list PWR_SUPPLY 23 16] \
        [list FPD_SWDT 13 13] \
        [list LPD_SWDT 12 12] \
        [list RPU_CCF 9 9] \
        [list RPU_LS 7 6] \
        [list FPD_TEMP 5 5] \
        [list LPD_TEMP 4 4] \
        [list RPU1 3 3] \
        [list RPU0 2 2] \
        [list OCM_ECC 1 1] \
        [list DDR_ECC 0 0] \
    ]]

# PMU_GLOBAL.ERROR_EN_2
dict set ::QEMU_REGS 4292347300 [dict create \
    name    ERROR_EN_2 \
    block   PMU_GLOBAL \
    fields  [list \
        [list CSU_ROM 26 26] \
        [list PMU_PB 25 25] \
        [list PMU_SERVICE 24 24] \
        [list PMU_FW 21 18] \
        [list PMU_UC 17 17] \
        [list CSU 16 16] \
        [list PLL_LOCK 12 8] \
        [list PL 5 2] \
        [list TO 1 0] \
    ]]

# PMU_GLOBAL.AIB_CNTRL
dict set ::QEMU_REGS 4292347392 [dict create \
    name    AIB_CNTRL \
    block   PMU_GLOBAL \
    fields  [list \
        [list FPD_AFI_FS 3 3] \
        [list FPD_AFI_FM 2 2] \
        [list LPD_AFI_FS 1 1] \
        [list LPD_AFI_FM 0 0] \
    ]]

# PMU_GLOBAL.AIB_STATUS
dict set ::QEMU_REGS 4292347396 [dict create \
    name    AIB_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list FPD_AFI_FS 3 3] \
        [list FPD_AFI_FM 2 2] \
        [list LPD_AFI_FS 1 1] \
        [list LPD_AFI_FM 0 0] \
    ]]

# PMU_GLOBAL.GLOBAL_RESET
dict set ::QEMU_REGS 4292347400 [dict create \
    name    GLOBAL_RESET \
    block   PMU_GLOBAL \
    fields  [list \
        [list PS_ONLY_RST 10 10] \
        [list FPD_RST 9 9] \
        [list RPU_LS_RST 8 8] \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_STATUS
dict set ::QEMU_REGS 4292347408 [dict create \
    name    ROM_VALIDATION_STATUS \
    block   PMU_GLOBAL \
    fields  [list \
        [list PASS 1 1] \
        [list DONE 0 0] \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_0
dict set ::QEMU_REGS 4292347412 [dict create \
    name    ROM_VALIDATION_DIGEST_0 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_1
dict set ::QEMU_REGS 4292347416 [dict create \
    name    ROM_VALIDATION_DIGEST_1 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_2
dict set ::QEMU_REGS 4292347420 [dict create \
    name    ROM_VALIDATION_DIGEST_2 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_3
dict set ::QEMU_REGS 4292347424 [dict create \
    name    ROM_VALIDATION_DIGEST_3 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_4
dict set ::QEMU_REGS 4292347428 [dict create \
    name    ROM_VALIDATION_DIGEST_4 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_5
dict set ::QEMU_REGS 4292347432 [dict create \
    name    ROM_VALIDATION_DIGEST_5 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_6
dict set ::QEMU_REGS 4292347436 [dict create \
    name    ROM_VALIDATION_DIGEST_6 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_7
dict set ::QEMU_REGS 4292347440 [dict create \
    name    ROM_VALIDATION_DIGEST_7 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_8
dict set ::QEMU_REGS 4292347444 [dict create \
    name    ROM_VALIDATION_DIGEST_8 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_9
dict set ::QEMU_REGS 4292347448 [dict create \
    name    ROM_VALIDATION_DIGEST_9 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_10
dict set ::QEMU_REGS 4292347452 [dict create \
    name    ROM_VALIDATION_DIGEST_10 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.ROM_VALIDATION_DIGEST_11
dict set ::QEMU_REGS 4292347456 [dict create \
    name    ROM_VALIDATION_DIGEST_11 \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.SAFETY_GATE
dict set ::QEMU_REGS 4292347472 [dict create \
    name    SAFETY_GATE \
    block   PMU_GLOBAL \
    fields  [list \
        [list PMU_LOGCLR_ENABLE 2 2] \
        [list LBIST_ENABLE 1 1] \
        [list SCAN_ENABLE 0 0] \
    ]]

# PMU_GLOBAL.MBIST_RST
dict set ::QEMU_REGS 4292347648 [dict create \
    name    MBIST_RST \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.MBIST_PG_EN
dict set ::QEMU_REGS 4292347652 [dict create \
    name    MBIST_PG_EN \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.MBIST_SETUP
dict set ::QEMU_REGS 4292347656 [dict create \
    name    MBIST_SETUP \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.MBIST_DONE
dict set ::QEMU_REGS 4292347664 [dict create \
    name    MBIST_DONE \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.MBIST_GOOD
dict set ::QEMU_REGS 4292347668 [dict create \
    name    MBIST_GOOD \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# PMU_GLOBAL.SAFETY_CHK
dict set ::QEMU_REGS 4292347904 [dict create \
    name    SAFETY_CHK \
    block   PMU_GLOBAL \
    fields  [list \
    ]]

# RPU.RPU_GLBL_CNTL
dict set ::QEMU_REGS 4288282624 [dict create \
    name    RPU_GLBL_CNTL \
    block   RPU \
    fields  [list \
        [list GIC_AXPROT 10 10] \
        [list TCM_CLK_CNTL 8 8] \
        [list TCM_WAIT 7 7] \
        [list TCM_COMB 6 6] \
        [list TEINIT 5 5] \
        [list SLCLAMP 4 4] \
        [list SLSPLIT 3 3] \
        [list DBGNOCLKSTOP 2 2] \
        [list CFGIE 1 1] \
        [list CFGEE 0 0] \
    ]]

# RPU.RPU_GLBL_STATUS
dict set ::QEMU_REGS 4288282628 [dict create \
    name    RPU_GLBL_STATUS \
    block   RPU \
    fields  [list \
        [list DBGNOPWRDWN 0 0] \
    ]]

# RPU.RPU_ERR_CNTL
dict set ::QEMU_REGS 4288282632 [dict create \
    name    RPU_ERR_CNTL \
    block   RPU \
    fields  [list \
        [list APB_ERR_RES 0 0] \
    ]]

# RPU.RPU_RAM
dict set ::QEMU_REGS 4288282636 [dict create \
    name    RPU_RAM \
    block   RPU \
    fields  [list \
        [list RAMCONTROL1 15 8] \
        [list RAMCONTROL0 7 0] \
    ]]

# RPU.RPU_ERR_INJ
dict set ::QEMU_REGS 4288282656 [dict create \
    name    RPU_ERR_INJ \
    block   RPU \
    fields  [list \
        [list DCCMINP2 15 8] \
        [list DCCMINP 7 0] \
    ]]

# RPU.RPU_CCF_MASK
dict set ::QEMU_REGS 4288282660 [dict create \
    name    RPU_CCF_MASK \
    block   RPU \
    fields  [list \
        [list TEST_MBIST_MODE 7 7] \
        [list TEST_SCAN_MODE_LP 6 6] \
        [list TEST_SCAN_MODE 5 5] \
        [list ISO 4 4] \
        [list PGE 3 3] \
        [list R50_DBG_RST 2 2] \
        [list R50_RST 1 1] \
        [list PGE_RST 0 0] \
    ]]

# RPU.RPU_INTR_0
dict set ::QEMU_REGS 4288282664 [dict create \
    name    RPU_INTR_0 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_1
dict set ::QEMU_REGS 4288282668 [dict create \
    name    RPU_INTR_1 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_2
dict set ::QEMU_REGS 4288282672 [dict create \
    name    RPU_INTR_2 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_3
dict set ::QEMU_REGS 4288282676 [dict create \
    name    RPU_INTR_3 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_4
dict set ::QEMU_REGS 4288282680 [dict create \
    name    RPU_INTR_4 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_MASK_0
dict set ::QEMU_REGS 4288282688 [dict create \
    name    RPU_INTR_MASK_0 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_MASK_1
dict set ::QEMU_REGS 4288282692 [dict create \
    name    RPU_INTR_MASK_1 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_MASK_2
dict set ::QEMU_REGS 4288282696 [dict create \
    name    RPU_INTR_MASK_2 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_MASK_3
dict set ::QEMU_REGS 4288282700 [dict create \
    name    RPU_INTR_MASK_3 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_INTR_MASK_4
dict set ::QEMU_REGS 4288282704 [dict create \
    name    RPU_INTR_MASK_4 \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_CCF_VAL
dict set ::QEMU_REGS 4288282708 [dict create \
    name    RPU_CCF_VAL \
    block   RPU \
    fields  [list \
        [list TEST_MBIST_MODE 7 7] \
        [list TEST_SCAN_MODE_LP 6 6] \
        [list TEST_SCAN_MODE 5 5] \
        [list ISO 4 4] \
        [list PGE 3 3] \
        [list R50_DBG_RST 2 2] \
        [list R50_RST 1 1] \
        [list PGE_RST 0 0] \
    ]]

# RPU.RPU_SAFETY_CHK
dict set ::QEMU_REGS 4288282864 [dict create \
    name    RPU_SAFETY_CHK \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU
dict set ::QEMU_REGS 4288282868 [dict create \
    name    RPU \
    block   RPU \
    fields  [list \
    ]]

# RPU.RPU_0_CFG
dict set ::QEMU_REGS 4288282880 [dict create \
    name    RPU_0_CFG \
    block   RPU \
    fields  [list \
        [list CFGNMFI0 3 3] \
        [list VINITHI 2 2] \
        [list COHERENT 1 1] \
        [list NCPUHALT 0 0] \
    ]]

# RPU.RPU_0_STATUS
dict set ::QEMU_REGS 4288282884 [dict create \
    name    RPU_0_STATUS \
    block   RPU \
    fields  [list \
        [list NVALRESET 5 5] \
        [list NVALIRQ 4 4] \
        [list NVALFIQ 3 3] \
        [list NWFIPIPESTOPPED 2 2] \
        [list NWFEPIPESTOPPED 1 1] \
        [list NCLKSTOPPED 0 0] \
    ]]

# RPU.RPU_0_PWRDWN
dict set ::QEMU_REGS 4288282888 [dict create \
    name    RPU_0_PWRDWN \
    block   RPU \
    fields  [list \
        [list EN 0 0] \
    ]]

# RPU.RPU_0_ISR
dict set ::QEMU_REGS 4288282900 [dict create \
    name    RPU_0_ISR \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_0_IMR
dict set ::QEMU_REGS 4288282904 [dict create \
    name    RPU_0_IMR \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_0_IEN
dict set ::QEMU_REGS 4288282908 [dict create \
    name    RPU_0_IEN \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_0_IDS
dict set ::QEMU_REGS 4288282912 [dict create \
    name    RPU_0_IDS \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_0_SLV_BASE
dict set ::QEMU_REGS 4288282916 [dict create \
    name    RPU_0_SLV_BASE \
    block   RPU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# RPU.RPU_0_AXI_OVER
dict set ::QEMU_REGS 4288282920 [dict create \
    name    RPU_0_AXI_OVER \
    block   RPU \
    fields  [list \
        [list AWCACHE 9 6] \
        [list ARCACHE 5 2] \
        [list AWCACHE_EN 1 1] \
        [list ARCACHE_EN 0 0] \
    ]]

# RPU.RPU_1_CFG
dict set ::QEMU_REGS 4288283136 [dict create \
    name    RPU_1_CFG \
    block   RPU \
    fields  [list \
        [list CFGNMFI1 3 3] \
        [list VINITHI 2 2] \
        [list COHERENT 1 1] \
        [list NCPUHALT 0 0] \
    ]]

# RPU.RPU_1_STATUS
dict set ::QEMU_REGS 4288283140 [dict create \
    name    RPU_1_STATUS \
    block   RPU \
    fields  [list \
        [list NVALRESET 5 5] \
        [list NVALIRQ 4 4] \
        [list NVALFIQ 3 3] \
        [list NWFIPIPESTOPPED 2 2] \
        [list NWFEPIPESTOPPED 1 1] \
        [list NCLKSTOPPED 0 0] \
    ]]

# RPU.RPU_1_PWRDWN
dict set ::QEMU_REGS 4288283144 [dict create \
    name    RPU_1_PWRDWN \
    block   RPU \
    fields  [list \
        [list EN 0 0] \
    ]]

# RPU.RPU_1_ISR
dict set ::QEMU_REGS 4288283156 [dict create \
    name    RPU_1_ISR \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_1_IMR
dict set ::QEMU_REGS 4288283160 [dict create \
    name    RPU_1_IMR \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_1_IEN
dict set ::QEMU_REGS 4288283164 [dict create \
    name    RPU_1_IEN \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_1_IDS
dict set ::QEMU_REGS 4288283168 [dict create \
    name    RPU_1_IDS \
    block   RPU \
    fields  [list \
        [list FPUFC 24 24] \
        [list FPOFC 23 23] \
        [list FPIXC 22 22] \
        [list FPIOC 21 21] \
        [list FPIDC 20 20] \
        [list FPDZC 19 19] \
        [list TCM_ASLV_CE 18 18] \
        [list TCM_ASLV_FAT 17 17] \
        [list TCM_LST_CE 16 16] \
        [list TCM_PREFETCH_CE 15 15] \
        [list B1TCM_CE 14 14] \
        [list B0TCM_CE 13 13] \
        [list ATCM_CE 12 12] \
        [list B1TCM_UE 11 11] \
        [list B0TCM_UE 10 10] \
        [list ATCM_UE 9 9] \
        [list DTAG_DIRTY_FAT 8 8] \
        [list DDATA_FAT 7 7] \
        [list TCM_LST_FAT 6 6] \
        [list TCM_PREFETCH_FAT 5 5] \
        [list DDATA_CE 4 4] \
        [list DTAG_DIRTY_CE 3 3] \
        [list IDATA_CE 2 2] \
        [list ITAG_CE 1 1] \
        [list APB_ERR 0 0] \
    ]]

# RPU.RPU_1_SLV_BASE
dict set ::QEMU_REGS 4288283172 [dict create \
    name    RPU_1_SLV_BASE \
    block   RPU \
    fields  [list \
        [list ADDR 7 0] \
    ]]

# RPU.RPU_1_AXI_OVER
dict set ::QEMU_REGS 4288283176 [dict create \
    name    RPU_1_AXI_OVER \
    block   RPU \
    fields  [list \
        [list AWCACHE 9 6] \
        [list ARCACHE 5 2] \
        [list AWCACHE_EN 1 1] \
        [list ARCACHE_EN 0 0] \
    ]]

# XPPU.CTRL
dict set ::QEMU_REGS 4288151552 [dict create \
    name    CTRL \
    block   XPPU \
    fields  [list \
        [list APER_PARITY_EN 2 2] \
        [list MID_PARITY_EN 1 1] \
        [list ENABLE 0 0] \
    ]]

# XPPU.ERR_STATUS1
dict set ::QEMU_REGS 4288151556 [dict create \
    name    ERR_STATUS1 \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.ERR_STATUS2
dict set ::QEMU_REGS 4288151560 [dict create \
    name    ERR_STATUS2 \
    block   XPPU \
    fields  [list \
        [list AXI_ID 9 0] \
    ]]

# XPPU.ISR
dict set ::QEMU_REGS 4288151568 [dict create \
    name    ISR \
    block   XPPU \
    fields  [list \
        [list APER_PARITY 7 7] \
        [list APER_TZ 6 6] \
        [list APER_PERM 5 5] \
        [list MID_PARITY 3 3] \
        [list MID_RO 2 2] \
        [list MID_MISS 1 1] \
        [list INV_APB 0 0] \
    ]]

# XPPU.IMR
dict set ::QEMU_REGS 4288151572 [dict create \
    name    IMR \
    block   XPPU \
    fields  [list \
        [list APER_PARITY 7 7] \
        [list APER_TZ 6 6] \
        [list APER_PERM 5 5] \
        [list MID_PARITY 3 3] \
        [list MID_RO 2 2] \
        [list MID_MISS 1 1] \
        [list INV_APB 0 0] \
    ]]

# XPPU.IEN
dict set ::QEMU_REGS 4288151576 [dict create \
    name    IEN \
    block   XPPU \
    fields  [list \
        [list APER_PARITY 7 7] \
        [list APER_TZ 6 6] \
        [list APER_PERM 5 5] \
        [list MID_PARITY 3 3] \
        [list MID_RO 2 2] \
        [list MID_MISS 1 1] \
        [list INV_APB 0 0] \
    ]]

# XPPU.IDS
dict set ::QEMU_REGS 4288151580 [dict create \
    name    IDS \
    block   XPPU \
    fields  [list \
        [list APER_PARITY 7 7] \
        [list APER_TZ 6 6] \
        [list APER_PERM 5 5] \
        [list MID_PARITY 3 3] \
        [list MID_RO 2 2] \
        [list MID_MISS 1 1] \
        [list INV_APB 0 0] \
    ]]

# XPPU.M_MASTER_IDS
dict set ::QEMU_REGS 4288151612 [dict create \
    name    M_MASTER_IDS \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.M_APERTURE_64KB
dict set ::QEMU_REGS 4288151620 [dict create \
    name    M_APERTURE_64KB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.M_APERTURE_1MB
dict set ::QEMU_REGS 4288151624 [dict create \
    name    M_APERTURE_1MB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.M_APERTURE_512MB
dict set ::QEMU_REGS 4288151628 [dict create \
    name    M_APERTURE_512MB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.BASE_64KB
dict set ::QEMU_REGS 4288151636 [dict create \
    name    BASE_64KB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.BASE_1MB
dict set ::QEMU_REGS 4288151640 [dict create \
    name    BASE_1MB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.BASE_512MB
dict set ::QEMU_REGS 4288151644 [dict create \
    name    BASE_512MB \
    block   XPPU \
    fields  [list \
    ]]

# XPPU.MASTER_ID00
dict set ::QEMU_REGS 4288151808 [dict create \
    name    MASTER_ID00 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID01
dict set ::QEMU_REGS 4288151812 [dict create \
    name    MASTER_ID01 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID02
dict set ::QEMU_REGS 4288151816 [dict create \
    name    MASTER_ID02 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID03
dict set ::QEMU_REGS 4288151820 [dict create \
    name    MASTER_ID03 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID04
dict set ::QEMU_REGS 4288151824 [dict create \
    name    MASTER_ID04 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID05
dict set ::QEMU_REGS 4288151828 [dict create \
    name    MASTER_ID05 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID06
dict set ::QEMU_REGS 4288151832 [dict create \
    name    MASTER_ID06 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID07
dict set ::QEMU_REGS 4288151836 [dict create \
    name    MASTER_ID07 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID08
dict set ::QEMU_REGS 4288151840 [dict create \
    name    MASTER_ID08 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID09
dict set ::QEMU_REGS 4288151844 [dict create \
    name    MASTER_ID09 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID10
dict set ::QEMU_REGS 4288151848 [dict create \
    name    MASTER_ID10 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID11
dict set ::QEMU_REGS 4288151852 [dict create \
    name    MASTER_ID11 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID12
dict set ::QEMU_REGS 4288151856 [dict create \
    name    MASTER_ID12 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID13
dict set ::QEMU_REGS 4288151860 [dict create \
    name    MASTER_ID13 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID14
dict set ::QEMU_REGS 4288151864 [dict create \
    name    MASTER_ID14 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID15
dict set ::QEMU_REGS 4288151868 [dict create \
    name    MASTER_ID15 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID16
dict set ::QEMU_REGS 4288151872 [dict create \
    name    MASTER_ID16 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID17
dict set ::QEMU_REGS 4288151876 [dict create \
    name    MASTER_ID17 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID18
dict set ::QEMU_REGS 4288151880 [dict create \
    name    MASTER_ID18 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# XPPU.MASTER_ID19
dict set ::QEMU_REGS 4288151884 [dict create \
    name    MASTER_ID19 \
    block   XPPU \
    fields  [list \
        [list MIDP 31 31] \
        [list MIDR 30 30] \
        [list MIDM 25 16] \
        [list MID 9 0] \
    ]]

# ---------------------------------------------------------------------------
# Helper procs
# ---------------------------------------------------------------------------

# Returns the QEMU register dict for an absolute address, or empty string
# if the address isn't covered.
#
# Tcl dict keys are strings, so "0xFD1A0020" and "4255842336" are
# distinct keys even though they're the same integer. We normalize the
# caller's input to decimal via [expr] so hex literals work.
proc qemu_reg_lookup {addr} {
    set k [expr {int($addr)}]
    if {[dict exists $::QEMU_REGS $k]} {
        return [dict get $::QEMU_REGS $k]
    }
    return ""
}

# dump_reg variant that pulls bit fields from the QEMU dict.
# Usage:
#   dump_reg_qemu 0xFD1A0020              ;# label = CRF_APB.APLL_CTRL
#   dump_reg_qemu 0xFD1A0020 "APLL CTRL" ;# custom label
#
# Falls back to a plain hex dump (no bit decoding) when the address
# isn't in QEMU's coverage, with a one-line warning to the report.
proc dump_reg_qemu {addr {label ""}} {
    set info [qemu_reg_lookup $addr]
    if {$info eq ""} {
        if {$label eq ""} {
            set label [format "reg @ 0x%08X" $addr]
        }
        dump_reg $label $addr
        say "  _(no QEMU register model for this address — bit fields unverified)_"
        return
    }
    set qname  [dict get $info name]
    set qblock [dict get $info block]
    if {$label eq ""} {
        set label "${qblock}.${qname}"
    }
    # Convert QEMU field format {name msb lsb} → dump_reg's {msb lsb name}
    set bit_decode [list]
    foreach f [dict get $info fields] {
        set fname [lindex $f 0]
        set fmsb  [lindex $f 1]
        set flsb  [lindex $f 2]
        lappend bit_decode [list $fmsb $flsb $fname]
    }
    set _v [dump_reg $label $addr $bit_decode]
    # JSON capture: record into ::CAPTURED if json-emit.tcl was sourced.
    # Builds a fields dict mapping field-name -> { bits, value }.
    if {[info commands capture_register] ne ""} {
        set _fields [dict create]
        # Accept both decimal ('1299') and hex ('0x00000513') forms
        # because OpenOCD's read_memory returns hex strings on some builds.
        # `expr int(...)` parses both; catch rejects ERR/empty cleanly.
        if {[catch {expr {int($_v)}} _vint] == 0} {
            foreach f [dict get $info fields] {
                set fname [lindex $f 0]
                set fmsb  [lindex $f 1]
                set flsb  [lindex $f 2]
                set fwidth [expr {$fmsb - $flsb + 1}]
                set fmask  [expr {(1 << $fwidth) - 1}]
                set fval   [expr {($_vint >> $flsb) & $fmask}]
                set bitstr [expr {$fmsb == $flsb ? "$flsb" : "$fmsb:$flsb"}]
                dict set _fields $fname [dict create bits $bitstr value $fval]
            }
        }
        capture_register $addr $qname $qblock $_v $_fields
    }
}
