# zynq7000-regs.tcl — Zynq-7000 register-address table (the nascent register KB; single source of
# address truth for the Zynq-7000 scripts, the analog of lib/zynqmp-regs-qemu.tcl).
#
# SOURCING / CONFIDENCE:
#   * Register ADDRESSES are high-confidence (u-boot zynq, Linux xilinx_zynq, xdevcfg/xqspips drivers).
#   * BIT-LEVEL fields below are now transcribed from UG585 v1.12.2 Appendix B (devcfg CTRL/LOCK @ PDF
#     p.1146-1149) + Ch.6 Table 6-4 boot-mode straps (PDF p.166) — references/pdf/ug585-zynq7000-trm.pdf.
#
# This file only DEFINES globals (::Z7_*). Sourced by zynq7000-enumerate.tcl / zynq7000-reopen-debug.tcl
# / zynq7000-flash.tcl. It touches no hardware.

# --- SLCR : System Level Control Registers (base 0xF8000000) ---
set ::Z7_SLCR_BASE      0xF8000000
set ::Z7_SLCR_LOCK      0xF8000004   ;# write 0x767B to lock SLCR writes
set ::Z7_SLCR_UNLOCK    0xF8000008   ;# write 0xDF0D to unlock SLCR writes
set ::Z7_SLCR_LOCKSTA   0xF800000C   ;# bit0: 1 = SLCR is write-protected (confident)
set ::Z7_SLCR_BOOT_MODE 0xF800025C   ;# [2:0] boot device, [3] JTAG chain routing, [4] PLL bypass (UG585 Table 6-4)
# slcr.BOOT_MODE[2:0] device encoding (UG585 v1.12.2 Table 6-4, PDF p.166):
#   0x0=JTAG  0x1=Quad-SPI  0x2=NOR  0x4=NAND  0x5=SD Card   (0x3/0x6/0x7 reserved)
#   [3] JTAG chain routing: 0=cascade, 1=independent.   [4] 0=PLL enabled, 1=PLL bypassed.

# --- devcfg : Device Configuration Interface / PCAP (base 0xF8007000; xdevcfg offsets) ---
set ::Z7_DEVCFG_BASE    0xF8007000
set ::Z7_DEVCFG_CTRL    0xF8007000   ;# Control Register (reset 0x0C006000) — debug/DAP/security enables
set ::Z7_DEVCFG_LOCK    0xF8007004   ;# write-once locks for CTRL fields (reset 0x0; cleared only by POR)
set ::Z7_DEVCFG_CFG     0xF8007008
set ::Z7_DEVCFG_INT_STS 0xF800700C
set ::Z7_DEVCFG_STATUS  0xF8007014   ;# config/efuse status (raw; not decoded here)
set ::Z7_DEVCFG_MCTRL   0xF8007080   ;# misc control / PCAP loopback (raw; not decoded here)

# devcfg.CTRL bit fields (UG585 v1.12.2 Appendix B, PDF p.1146-1149). Masks for the posture read + reopen.
set ::Z7_CTRL_DAP_EN     0x00000007  ;# [2:0]  111 = ARM DAP enabled; any other value = DAP BYPASSED
set ::Z7_CTRL_DBGEN      0x00000008  ;# [3]    invasive debug enable
set ::Z7_CTRL_NIDEN      0x00000010  ;# [4]    non-invasive debug enable
set ::Z7_CTRL_SPIDEN     0x00000020  ;# [5]    secure invasive debug enable
set ::Z7_CTRL_SPNIDEN    0x00000040  ;# [6]    secure non-invasive debug enable
set ::Z7_CTRL_DEBUG_ALL  0x0000007F  ;# [6:0]  DAP_EN(111)+all debug enables — the "open everything" value
set ::Z7_CTRL_SEC_EN     0x00000080  ;# [7]    RO: 1 = PS was booted SECURELY (secure boot active)
set ::Z7_CTRL_SEU_EN     0x00000100  ;# [8]    1 = SEU -> secure lockdown
set ::Z7_CTRL_AES_EN     0x00000E00  ;# [11:9] 111 = PL AES engine enabled; 000 = disabled (else lockdown)
set ::Z7_CTRL_AES_FUSE   0x00001000  ;# [12]   AES key source: 0 = BBRAM, 1 = eFuse
set ::Z7_CTRL_MULTIBOOT  0x01000000  ;# [24]   multiboot enable
set ::Z7_CTRL_JTAG_CHDIS 0x00800000  ;# [23]   1 = JTAG scan chain DISABLED (PS DAP + PL TAP)
set ::Z7_CTRL_FORCE_RST  0x80000000  ;# [31]   force PS into secure lockdown

# devcfg.LOCK bit fields (write-once; 1 = the corresponding CTRL field is FROZEN until PS_POR_B).
set ::Z7_LOCK_DBG        0x00000001  ;# [0] locks CTRL[6:0] (SPNIDEN,SPIDEN,NIDEN,DBGEN,DAP_EN) -> reopen blocked
set ::Z7_LOCK_SEC        0x00000002  ;# [1] locks SEC_EN
set ::Z7_LOCK_SEU        0x00000004  ;# [2] locks SEU_EN
set ::Z7_LOCK_AES_EN     0x00000008  ;# [3] locks AES_EN
set ::Z7_LOCK_AES_FUSE   0x00000010  ;# [4] locks AES_FUSE

# devcfg.STATUS bit fields (UG585 App.B, PDF p.1157) — the eFuse / secure-boot state, READABLE:
set ::Z7_STAT_SECURE_RST   0x00000080 ;# [7] 1 = device is in SECURE LOCKDOWN (cleared only by PS_POR_B)
set ::Z7_STAT_ILLEGAL_APB  0x00000040 ;# [6] 1 = DEVCI UNLOCK word wrong -> secure boot + DAP + DEVCI disabled
set ::Z7_STAT_PCFG_INIT    0x00000010 ;# [4] 1 = PL init done (housecleaning complete)
set ::Z7_STAT_EFUSE_SWRES  0x00000008 ;# [3] eFuse blown: BBRAM AES key DISABLED (eFuse key must be used)
set ::Z7_STAT_EFUSE_SEC_EN 0x00000004 ;# [2] eFuse blown: device MUST boot securely w/ eFuse AES key (HARDENED)
set ::Z7_STAT_EFUSE_JTAGDIS 0x00000002;# [1] eFuse blown: ARM DAP PERMANENTLY in bypass (JTAG dead)

# devcfg.MCTRL (UG585 App.B, PDF p.1162): [31:28] PS_VERSION (silicon rev: 0=1.0 1=2.0 2=3.0 3=3.1)
set ::Z7_MCTRL_PSVER_SH  28

# --- SLCR security/identity registers (UG585 App.B, PDF p.1620-1625) ---
set ::Z7_SLCR_REBOOT_STS 0xF8000258  ;# persistent reset reason: [15:0] BOOTROM_ERROR_CODE, [22]POR..[16]SWDT
set ::Z7_SLCR_APU_CTRL   0xF8000300  ;# [2] CFGSDISABLE (lock sys-ctrl+GIC writes), [1:0] CP15SDISABLE (per-core)
set ::Z7_SLCR_TZ_DMA_NS  0xF8000440  ;# [0] DMAC_NS: 1 = DMAC operates non-secure
set ::Z7_SLCR_TZ_DMA_IRQ 0xF8000444  ;# [15:0] DMA_IRQ_NS
set ::Z7_SLCR_TZ_DMA_PER 0xF8000448  ;# [3:0] DMAC_PERIPH_NS
set ::Z7_SLCR_PSS_IDCODE 0xF8000530  ;# device identity: [31:28]REV [27:21]FAMILY(0x1B) [20:17]SUBFAM(9)
                                     ;#                  [16:12]DEVICE [11:1]MFG(0x49 Xilinx)
set ::Z7_APU_CFGSDISABLE 0x00000004  ;# APU_CTRL[2]
set ::Z7_APU_CP15SDIS    0x00000003  ;# APU_CTRL[1:0]
# PSS_IDCODE DEVICE-code (bits 16:12) -> 7-series die  (UG585 PSS_IDCODE table, PDF p.1625-1626)
array set ::Z7_DEVICE_NAME {0x02 7z010 0x1b 7z015 0x07 7z020 0x0c 7z030 0x11 7z045}

# --- memory regions ---
set ::Z7_DDR_BASE       0x00000000   ;# external DDR low alias
set ::Z7_OCM_HIGH       0xFFFC0000   ;# 256 KB OCM (high-mapped)

# --- boot flash access ---
set ::Z7_QSPI_LINEAR    0xFC000000   ;# QSPI flash memory-mapped (read-only) when controller is in
                                     ;# Linear Quad-SPI (LQSPI) mode — lower 32 MB. THE flash-dump path.
set ::Z7_QSPI_CTRL_BASE 0xE000D000   ;# QSPI controller registers (LQSPI_CFG etc.) — for IO-mode / >32MB
set ::Z7_SMC_BASE       0xE000E000   ;# PL353 static memory controller (NAND @0xE1000000 / NOR @0xE2000000)
