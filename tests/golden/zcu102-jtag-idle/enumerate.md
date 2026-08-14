# ZCU102 / ZynqMP Enumeration Report

- Generated: GOLDEN-FROZEN-TIMESTAMP
- Tool: OpenOCD via on-board Digilent SMT2 / FT232H
- Report file: /tmp/tmp.GQ2G5piA7m/reports/enumerate-GOLDEN-FROZEN-TIMESTAMP.md
- Raw JSON capture: /tmp/tmp.GQ2G5piA7m/reports/raw-GOLDEN-FROZEN-TIMESTAMP.json

# 1. JTAG Chain

TAPs discovered during init (see OpenOCD startup log for IDCODEs):

| TAP | IRLen | Expected role |
|-----|-------|---------------|
| `uscale.ps` | 12 | Xilinx Zynq UltraScale+ PS-TAP |
| `uscale.tap` | 4 | ARM CoreSight DAP |

(Captured IDCODEs are in the OpenOCD log above this section.)

_(AXI mem-AP examined and verified responsive — proceeding with enumeration.)_

# 2. Silicon Identity
- **CSU.IDCODE**: `0xffca0040 = 0x24738093`
- **CSU_VERSION**: `0xffca0044 = 0x00000513`
    [15:12] PLATFORM                       = 0x0 
    [ 3: 0] PS_VERSION                     = 0x3 

**eFUSE Device DNA** (unique per chip, 96 bits; controller @ 0xFFCC0000):
- **DNA[31:0]**: `0x44804345`
- **DNA[63:32]**: `0x0170cfa7`
- **DNA[95:64]**: `0x40000000`

# 3. Boot State
- **CRL_APB.BOOT_MODE_USER**: `0xff5e0200 = 0x00000000`
    [15:12] ALT_BOOT_MODE                  = 0x0 
    [ 8]     USE_ALT                        = 0 
    [ 3: 0] BOOT_MODE                      = 0x0 
- **CRL_APB.BOOT_MODE_POR**: `0xff5e0204 = 0x00000000`
    [11: 8] BOOT_MODE2                     = 0x0 
    [ 7: 4] BOOT_MODE1                     = 0x0 
    [ 3: 0] BOOT_MODE0                     = 0x0 
- **CSU_MULTI_BOOT**: `0xffca0010 = 0x00000000`
- **CRL_APB.RESET_REASON**: `0xff5e0220 = 0x00000001`
    [15]     MIMIC                          = 0 
    [ 6]     DEBUG_SYS                      = 0 
    [ 5]     SOFT                           = 0 
    [ 4]     SRST                           = 0 
    [ 3]     PSONLY_RESET_REQ               = 0 
    [ 2]     PMU_SYS_RESET                  = 0 
    [ 1]     INTERNAL_POR                   = 0 
    [ 0]     EXTERNAL_POR                   = 1 
- **CSU_STATUS**: `0xffca0000 = 0x00000000`
    [ 1]     BOOT_ENC                       = 0 
    [ 0]     BOOT_AUTH                      = 0 

# 4. Security State (research focus)

These are the most security-research-relevant registers. Cross-reference
decoded fields against UG1085 §10 (CSU) and UG1087 register descriptions.
- **CSU.JTAG_SEC**: `0xffca0038 = 0x0000003f`
    [ 8: 6] SSSS_PMU_SEC                   = 0x0 
    [ 5: 3] SSSS_PLTAP_SEC                 = 0x7 
    [ 2: 0] SSSS_DAP_SEC                   = 0x7 
- **CSU.JTAG_DAP_CFG**: `0xffca003c = 0x000000ff`
    [ 7]     SSSS_RPU_SPNIDEN               = 1 
    [ 6]     SSSS_RPU_SPIDEN                = 1 
    [ 5]     SSSS_RPU_NIDEN                 = 1 
    [ 4]     SSSS_RPU_DBGEN                 = 1 
    [ 3]     SSSS_APU_SPNIDEN               = 1 
    [ 2]     SSSS_APU_SPIDEN                = 1 
    [ 1]     SSSS_APU_NIDEN                 = 1 
    [ 0]     SSSS_APU_DBGEN                 = 1 
- **CSU.JTAG_CHAIN_STATUS**: `0xffca0034 = 0x00000003`
    [ 1]     ARM_DAP                        = 1 
    [ 0]     PL_TAP                         = 1 
- **CSU.JTAG_CHAIN_CFG**: `0xffca0030 = 0x00000000`
    [ 1]     SSSS_LINK_ARM_DAP              = 0 
    [ 0]     SSSS_LINK_PL_TAP               = 0 

**eFUSE secure boot policy** (LPD eFUSE controller at 0xFFCC0000):
- **EFUSE.STATUS**: `0xffcc0008 = 0x00000027`
    [ 7]     AES_CRC_PASS                   = 0 
    [ 6]     AES_CRC_DONE                   = 0 
    [ 5]     CACHE_DONE                     = 1 
    [ 4]     CACHE_LOAD                     = 0 
    [ 2]     EFUSE_3_TBIT                   = 1 
    [ 1]     EFUSE_2_TBIT                   = 1 
    [ 0]     EFUSE_0_TBIT                   = 1 
- **EFUSE.SEC_CTRL**: `0xffcc1058 = 0x00000000`
    [31:30] PPK1_INVLD                     = 0x0 
    [29]     PPK1_WRLK                      = 0 
    [28:27] PPK0_INVLD                     = 0x0 
    [26]     PPK0_WRLK                      = 0 
    [25:11] RSA_EN                         = 0x0 
    [10]     SEC_LOCK                       = 0 
    [ 9]     PROG_GATE_2                    = 0 
    [ 8]     PROG_GATE_1                    = 0 
    [ 7]     PROG_GATE_0                    = 0 
    [ 6]     DFT_DIS                        = 0 
    [ 5]     JTAG_DIS                       = 0 
    [ 4]     ERROR_DIS                      = 0 
    [ 3]     BBRAM_DIS                      = 0 
    [ 2]     ENC_ONLY                       = 0 
    [ 1]     AES_WRLK                       = 0 
    [ 0]     AES_RDLK                       = 0 

**Boot-header scan** (operator-gated). The ZynqMP boot header is not
memory-mapped in JTAG-idle; on a booted target or with QSPI in linear mode,
point ::BH_ADDR at the boot-image base (e.g. -c {set ::BH_ADDR 0xC0000000})
to capture encryptionKeySource (off 0x28) and fsblAttributes (off 0x44).
Self-validated by the boot-header magic words (WIDTH_DETECTION 0xAA995566 at
off 0x20, identification XLNX 0x584C4E58 at off 0x24) so a wrong address
cannot yield a false reading — nothing is captured unless both magics match.
  ::BH_ADDR not set — boot-header scan skipped (expected in JTAG-idle).

**Additional eFUSE shadow registers** (per Xilinx xilskey defines):
- **EFUSE.MISC_USER_CTRL @ 0xffcc1040**: `0x00000100`
- **EFUSE.PUF_CHASH @ 0xffcc1050**: `0x00000000`
- **EFUSE.PUF_MISC @ 0xffcc1054**: `0x10000000`
- **EFUSE.SPK_ID @ 0xffcc105c**: `0x00000000`
- **EFUSE.USER0 @ 0xffcc1020**: `0x00000000`
- **EFUSE.USER1 @ 0xffcc1024**: `0x00000000`

**eFUSE provisioning + programming locks** (all-zero/clear ⇒ unprovisioned dev
silicon; non-zero ⇒ keys/fuses burned or programming locked on this part):
- **EFUSE.WR_LOCK**: `0xffcc0000 = 0x00000001`
    [15: 0] LOCK                           = 0x1 
- **EFUSE.EFUSE_ISR**: `0xffcc0030 = 0x00000000`
    [31]     APB_SLVERR                     = 0 
    [ 4]     CACHE_ERROR                    = 0 
    [ 3]     RD_ERROR                       = 0 
    [ 2]     RD_DONE                        = 0 
    [ 1]     PGM_ERROR                      = 0 
    [ 0]     PGM_DONE                       = 0 
- **EFUSE.EFUSE_PGM_LOCK**: `0xffcc0044 = 0x00000000`
    [ 0]     SPK_ID_LOCK                    = 0 
- **EFUSE.EFUSE_AES_CRC**: `0xffcc0048 = 0x00000000`

**CSU core + secure stream switch + boot integrity** (CSU state, SSS routing,
multiboot/golden-image counter, fault-tolerance status):
- **CSU.CSU_STATUS**: `0xffca0000 = 0x00000000`
    [ 1]     BOOT_ENC                       = 0 
    [ 0]     BOOT_AUTH                      = 0 
- **CSU.CSU_CTRL**: `0xffca0004 = 0x00000000`
    [ 4]     SLVERR_ENABLE                  = 0 
    [ 0]     CSU_CLK_SEL                    = 0 
- **CSU.CSU_SSS_CFG**: `0xffca0008 = 0x00000050`
    [19:16] PSTP_SSS                       = 0x0 
    [15:12] SHA_SSS                        = 0x0 
    [11: 8] AES_SSS                        = 0x0 
    [ 7: 4] DMA_SSS                        = 0x5 
    [ 3: 0] PCAP_SSS                       = 0x0 
- **CSU.CSU_MULTI_BOOT**: `0xffca0010 = 0x00000000`
- **CSU.CSU_FT_STATUS**: `0xffca0018 = 0x00000000`
    [31]     R_UE                           = 0 
    [30]     R_VOTER_ERROR                  = 0 
    [29]     R_COMP_ERR_23                  = 0 
    [28]     R_COMP_ERR_13                  = 0 
    [27]     R_COMP_ERR_12                  = 0 
    [26]     R_MISMATCH_23_A                = 0 
    [25]     R_MISMATCH_13_A                = 0 
    [24]     R_MISMATCH_12_A                = 0 
    [23]     R_FT_ST_MISMATCH               = 0 
    [22]     R_CPU_ID_MISMATCH              = 0 
    [19]     R_SLEEP_RESET                  = 0 
    [18]     R_MISMATCH_23_B                = 0 
    [17]     R_MISMATCH_13_B                = 0 
    [16]     R_MISMATCH_12_B                = 0 
    [15]     N_UE                           = 0 
    [14]     N_VOTER_ERROR                  = 0 
    [13]     N_COMP_ERR_23                  = 0 
    [12]     N_COMP_ERR_13                  = 0 
    [11]     N_COMP_ERR_12                  = 0 
    [10]     N_MISMATCH_23_A                = 0 
    [ 9]     N_MISMATCH_13_A                = 0 
    [ 8]     N_MISMATCH_12_A                = 0 
    [ 7]     N_FT_ST_MISMATCH               = 0 
    [ 6]     N_CPU_ID_MISMATCH              = 0 
    [ 3]     N_SLEEP_RESET                  = 0 
    [ 2]     N_MISMATCH_23_B                = 0 
    [ 1]     N_MISMATCH_13_B                = 0 
    [ 0]     N_MISMATCH_12_B                = 0 

**Anti-tamper response policy** (TAMPER_STATUS + 13 TAMPER response-config regs:
all-zero ⇒ no tamper sources armed; non-zero ⇒ an active tamper policy — sources
wired to system reset / secure lockdown / key-zeroize on a hardened part):
- **CSU.TAMPER_STATUS**: `0xffca5000 = 0x00000000`
    [13]     TAMPER_13                      = 0 
    [12]     TAMPER_12                      = 0 
    [11]     TAMPER_11                      = 0 
    [10]     TAMPER_10                      = 0 
    [ 9]     TAMPER_9                       = 0 
    [ 8]     TAMPER_8                       = 0 
    [ 7]     TAMPER_7                       = 0 
    [ 6]     TAMPER_6                       = 0 
    [ 5]     TAMPER_5                       = 0 
    [ 4]     TAMPER_4                       = 0 
    [ 3]     TAMPER_3                       = 0 
    [ 2]     TAMPER_2                       = 0 
    [ 1]     TAMPER_1                       = 0 
    [ 0]     TAMPER_0                       = 0 
- **CSU.CSU_TAMPER_TRIG**: `0xffca0014 = 0x00000000`
    [ 0]     TAMPER                         = 0 
- **CSU.CSU_TAMPER_0**: `0xffca5004 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_1**: `0xffca5008 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_2**: `0xffca500c = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_3**: `0xffca5010 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_4**: `0xffca5014 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_5**: `0xffca5018 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_6**: `0xffca501c = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_7**: `0xffca5020 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_8**: `0xffca5024 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_9**: `0xffca5028 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_10**: `0xffca502c = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_11**: `0xffca5030 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 
- **CSU.CSU_TAMPER_12**: `0xffca5034 = 0x00000000`
    [ 4]     BBRAM_ERASE                    = 0 
    [ 3]     SEC_LOCKDOWN_1                 = 0 
    [ 2]     SEC_LOCKDOWN_0                 = 0 
    [ 1]     SYS_RESET                      = 0 
    [ 0]     SYS_INTERRUPT                  = 0 

**CSU AES engine key-presence** (STATUS key-zero bits: SET ⇒ that key slot is
all-zero/unprovisioned; CLEAR ⇒ a real key is loaded — a strong provisioning tell):
- **CSU.AES_STATUS**: `0xffca1000 = 0x00000f00`
    [11]     OKR_ZEROED                     = 1 
    [10]     BOOT_ZEROED                    = 1 
    [ 9]     KUP_ZEROED                     = 1 
    [ 8]     AES_KEY_ZEROED                 = 1 
    [ 5]     BLACK_KEY_DONE                 = 0 
    [ 4]     KEY_INIT_DONE                  = 0 
    [ 3]     GCM_TAG_PASS                   = 0 
    [ 2]     DONE                           = 0 
    [ 1]     READY                          = 0 
    [ 0]     BUSY                           = 0 

**RSA root-of-trust (PPK0 / PPK1 SHA3 hashes, 12 words each)** — all-zero ⇒ no
primary/secondary public-key hash provisioned (no RSA root of trust); any non-zero
word ⇒ an RSA PPK is burned (pair with SEC_CTRL.RSA_EN to know if it is enforced):
- **EFUSE.PPK0_0**: `0xffcc10a0 = 0x00000000`
- **EFUSE.PPK0_1**: `0xffcc10a4 = 0x00000000`
- **EFUSE.PPK0_2**: `0xffcc10a8 = 0x00000000`
- **EFUSE.PPK0_3**: `0xffcc10ac = 0x00000000`
- **EFUSE.PPK0_4**: `0xffcc10b0 = 0x00000000`
- **EFUSE.PPK0_5**: `0xffcc10b4 = 0x00000000`
- **EFUSE.PPK0_6**: `0xffcc10b8 = 0x00000000`
- **EFUSE.PPK0_7**: `0xffcc10bc = 0x00000000`
- **EFUSE.PPK0_8**: `0xffcc10c0 = 0x00000000`
- **EFUSE.PPK0_9**: `0xffcc10c4 = 0x00000000`
- **EFUSE.PPK0_10**: `0xffcc10c8 = 0x00000000`
- **EFUSE.PPK0_11**: `0xffcc10cc = 0x00000000`
- **EFUSE.PPK1_0**: `0xffcc10d0 = 0x00000000`
- **EFUSE.PPK1_1**: `0xffcc10d4 = 0x00000000`
- **EFUSE.PPK1_2**: `0xffcc10d8 = 0x00000000`
- **EFUSE.PPK1_3**: `0xffcc10dc = 0x00000000`
- **EFUSE.PPK1_4**: `0xffcc10e0 = 0x00000000`
- **EFUSE.PPK1_5**: `0xffcc10e4 = 0x00000000`
- **EFUSE.PPK1_6**: `0xffcc10e8 = 0x00000000`
- **EFUSE.PPK1_7**: `0xffcc10ec = 0x00000000`
- **EFUSE.PPK1_8**: `0xffcc10f0 = 0x00000000`
- **EFUSE.PPK1_9**: `0xffcc10f4 = 0x00000000`
- **EFUSE.PPK1_10**: `0xffcc10f8 = 0x00000000`
- **EFUSE.PPK1_11**: `0xffcc10fc = 0x00000000`

# 5. Power State (PMU_GLOBAL)
- **PMU_GLOBAL.GLOBAL_CTRL**: `0xffd80000 = 0x00018800`
    [16]     MB_SLEEP                       = 1 
    [15:12] WRITE_QOS                      = 0x8 
    [11: 8] READ_QOS                       = 0x8 
    [ 4]     FW_IS_PRESENT                  = 0 
    [ 2]     COHERENT                       = 0 
    [ 1]     SLVERR_ENABLE                  = 0 
    [ 0]     DONT_SLEEP                     = 0 
- **PMU_GLOBAL.PWR_STATE**: `0xffd80100 = 0x00fffcbf`
    [23]     PL                             = 1 
    [22]     FP                             = 1 
    [21]     USB1                           = 1 
    [20]     USB0                           = 1 
    [19]     OCM_BANK3                      = 1 
    [18]     OCM_BANK2                      = 1 
    [17]     OCM_BANK1                      = 1 
    [16]     OCM_BANK0                      = 1 
    [15]     TCM1B                          = 1 
    [14]     TCM1A                          = 1 
    [13]     TCM0B                          = 1 
    [12]     TCM0A                          = 1 
    [11]     R5_1                           = 1 
    [10]     R5_0                           = 1 
    [ 7]     L2_BANK0                       = 1 
    [ 5]     PP1                            = 1 
    [ 4]     PP0                            = 1 
    [ 3]     ACPU3                          = 1 
    [ 2]     ACPU2                          = 1 
    [ 1]     ACPU1                          = 1 
    [ 0]     ACPU0                          = 1 
- **PMU_GLOBAL.REQ_PWRUP_STATUS**: `0xffd80110 = 0x00000000`
    [23]     PL                             = 0 
    [22]     FP                             = 0 
    [21]     USB1                           = 0 
    [20]     USB0                           = 0 
    [19]     OCM_BANK3                      = 0 
    [18]     OCM_BANK2                      = 0 
    [17]     OCM_BANK1                      = 0 
    [16]     OCM_BANK0                      = 0 
    [15]     TCM1B                          = 0 
    [14]     TCM1A                          = 0 
    [13]     TCM0B                          = 0 
    [12]     TCM0A                          = 0 
    [10]     RPU                            = 0 
    [ 7]     L2_BANK0                       = 0 
    [ 5]     PP1                            = 0 
    [ 4]     PP0                            = 0 
    [ 3]     ACPU3                          = 0 
    [ 2]     ACPU2                          = 0 
    [ 1]     ACPU1                          = 0 
    [ 0]     ACPU0                          = 0 
- **PMU_GLOBAL.REQ_PWRDWN_STATUS**: `0xffd80210 = 0x00000000`
    [23]     PL                             = 0 
    [22]     FP                             = 0 
    [21]     USB1                           = 0 
    [20]     USB0                           = 0 
    [19]     OCM_BANK3                      = 0 
    [18]     OCM_BANK2                      = 0 
    [17]     OCM_BANK1                      = 0 
    [16]     OCM_BANK0                      = 0 
    [15]     TCM1B                          = 0 
    [14]     TCM1A                          = 0 
    [13]     TCM0B                          = 0 
    [12]     TCM0A                          = 0 
    [10]     RPU                            = 0 
    [ 7]     L2_BANK0                       = 0 
    [ 5]     PP1                            = 0 
    [ 4]     PP0                            = 0 
    [ 3]     ACPU3                          = 0 
    [ 2]     ACPU2                          = 0 
    [ 1]     ACPU1                          = 0 
    [ 0]     ACPU0                          = 0 
- **PMU_GLOBAL.ERROR_STATUS_1**: `0xffd80530 = 0x00000000`
    [31]     AUX3                           = 0 
    [30]     AUX2                           = 0 
    [29]     AUX1                           = 0 
    [28]     AUX0                           = 0 
    [27]     CSU_SWDT                       = 0 
    [26]     CLK_MON                        = 0 
    [25:24] XMPU                           = 0x0 
    [23:16] PWR_SUPPLY                     = 0x0 
    [13]     FPD_SWDT                       = 0 
    [12]     LPD_SWDT                       = 0 
    [ 9]     RPU_CCF                        = 0 
    [ 7: 6] RPU_LS                         = 0x0 
    [ 5]     FPD_TEMP                       = 0 
    [ 4]     LPD_TEMP                       = 0 
    [ 3]     RPU1                           = 0 
    [ 2]     RPU0                           = 0 
    [ 1]     OCM_ECC                        = 0 
    [ 0]     DDR_ECC                        = 0 
- **PMU_GLOBAL.ERROR_STATUS_2**: `0xffd80540 = 0x00000000`
    [26]     CSU_ROM                        = 0 
    [25]     PMU_PB                         = 0 
    [24]     PMU_SERVICE                    = 0 
    [21:18] PMU_FW                         = 0x0 
    [17]     PMU_UC                         = 0 
    [16]     CSU                            = 0 
    [12: 8] PLL_LOCK                       = 0x0 
    [ 5: 2] PL                             = 0x0 
    [ 1: 0] TO                             = 0x0 

# 6. Clocks: PLLs and Reference Clocks

## FPD PLLs (CRF_APB)
- **APLL_CTRL**: `0xfd1a0020 = 0x00012c09`
    [26:24] POST_SRC                       = 0x0 
    [22:20] PRE_SRC                        = 0x0 
    [17]     CLKOUTDIV                      = 0 
    [16]     DIV2                           = 1 
    [14: 8] FBDIV                          = 0x2c 
    [ 3]     BYPASS                         = 1 
    [ 0]     RESET                          = 1 
- **APLL_CFG**: `0xfd1a0024 = 0x00000000`
    [31:25] LOCK_DLY                       = 0x0 
    [22:13] LOCK_CNT                       = 0x0 
    [11:10] LFHF                           = 0x0 
    [ 8: 5] CP                             = 0x0 
    [ 3: 0] RES                            = 0x0 
- **DPLL_CTRL**: `0xfd1a002c = 0x00013200`
    [26:24] POST_SRC                       = 0x0 
    [22:20] PRE_SRC                        = 0x0 
    [17]     CLKOUTDIV                      = 0 
    [16]     DIV2                           = 1 
    [14: 8] FBDIV                          = 0x32 
    [ 3]     BYPASS                         = 0 
    [ 0]     RESET                          = 0 
- **DPLL_CFG**: `0xfd1a0030 = 0x7e5dcc6c`
    [31:25] LOCK_DLY                       = 0x3f 
    [22:13] LOCK_CNT                       = 0x2ee 
    [11:10] LFHF                           = 0x3 
    [ 8: 5] CP                             = 0x3 
    [ 3: 0] RES                            = 0xc 
- **VPLL_CTRL**: `0xfd1a0038 = 0x00012809`
    [26:24] POST_SRC                       = 0x0 
    [22:20] PRE_SRC                        = 0x0 
    [17]     CLKOUTDIV                      = 0 
    [16]     DIV2                           = 1 
    [14: 8] FBDIV                          = 0x28 
    [ 3]     BYPASS                         = 1 
    [ 0]     RESET                          = 1 
- **VPLL_CFG**: `0xfd1a003c = 0x00000000`
    [31:25] LOCK_DLY                       = 0x0 
    [22:13] LOCK_CNT                       = 0x0 
    [11:10] LFHF                           = 0x0 
    [ 8: 5] CP                             = 0x0 
    [ 3: 0] RES                            = 0x0 
- **PLL_STATUS (FPD)**: `0xfd1a0044 = 0x0000003a`
    [ 5]     VPLL_STABLE                    = 1 
    [ 4]     DPLL_STABLE                    = 1 
    [ 3]     APLL_STABLE                    = 1 
    [ 2]     VPLL_LOCK                      = 0 
    [ 1]     DPLL_LOCK                      = 1 
    [ 0]     APLL_LOCK                      = 0 

## LPD PLLs (CRL_APB)
- **IOPLL_CTRL**: `0xff5e0020 = 0x00013200`
    [26:24] POST_SRC                       = 0x0 
    [22:20] PRE_SRC                        = 0x0 
    [17]     CLKOUTDIV                      = 0 
    [16]     DIV2                           = 1 
    [14: 8] FBDIV                          = 0x32 
    [ 3]     BYPASS                         = 0 
    [ 0]     RESET                          = 0 
- **IOPLL_CFG**: `0xff5e0024 = 0x7e5dcc6c`
    [31:25] LOCK_DLY                       = 0x3f 
    [22:13] LOCK_CNT                       = 0x2ee 
    [11:10] LFHF                           = 0x3 
    [ 8: 5] CP                             = 0x3 
    [ 3: 0] RES                            = 0xc 
- **RPLL_CTRL**: `0xff5e0030 = 0x00012c09`
    [26:24] POST_SRC                       = 0x0 
    [22:20] PRE_SRC                        = 0x0 
    [17]     CLKOUTDIV                      = 0 
    [16]     DIV2                           = 1 
    [14: 8] FBDIV                          = 0x2c 
    [ 3]     BYPASS                         = 1 
    [ 0]     RESET                          = 1 
- **RPLL_CFG**: `0xff5e0034 = 0x00000000`
    [31:25] LOCK_DLY                       = 0x0 
    [22:13] LOCK_CNT                       = 0x0 
    [11:10] LFHF                           = 0x0 
    [ 8: 5] CP                             = 0x0 
    [ 3: 0] RES                            = 0x0 
- **PLL_STATUS (LPD)**: `0xff5e0040 = 0x00000019`
    [ 4]     RPLL_STABLE                    = 1 
    [ 3]     IOPLL_STABLE                   = 1 
    [ 1]     RPLL_LOCK                      = 0 
    [ 0]     IOPLL_LOCK                     = 1 

## Per-peripheral reference clocks
- **CRL_APB.UART0_REF_CTRL**: `0xff5e0074 = 0x01001800`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.UART1_REF_CTRL**: `0xff5e0078 = 0x01001800`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.SPI0_REF_CTRL**: `0xff5e007c = 0x01001800`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.SPI1_REF_CTRL**: `0xff5e0080 = 0x01001800`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.I2C0_REF_CTRL**: `0xff5e0120 = 0x01000500`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x5 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.I2C1_REF_CTRL**: `0xff5e0124 = 0x01000500`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x5 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.USB0_BUS_REF_CTRL**: `0xff5e0060 = 0x02010c00`
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0xc 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.USB1_BUS_REF_CTRL**: `0xff5e0064 = 0x02010c00`
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0xc 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.GEM0_REF_CTRL**: `0xff5e0050 = 0x02011800`
    [26]     RX_CLKACT                      = 0 
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.GEM1_REF_CTRL**: `0xff5e0054 = 0x02011800`
    [26]     RX_CLKACT                      = 0 
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.GEM2_REF_CTRL**: `0xff5e0058 = 0x02011800`
    [26]     RX_CLKACT                      = 0 
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.GEM3_REF_CTRL**: `0xff5e005c = 0x02011800`
    [26]     RX_CLKACT                      = 0 
    [25]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x1 
    [13: 8] DIVISOR0                       = 0x18 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.SDIO0_REF_CTRL**: `0xff5e006c = 0x01000f00`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0xf 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.SDIO1_REF_CTRL**: `0xff5e0070 = 0x01000f00`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0xf 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.QSPI_REF_CTRL**: `0xff5e0068 = 0x01000800`
    [24]     CLKACT                         = 1 
    [21:16] DIVISOR1                       = 0x0 
    [13: 8] DIVISOR0                       = 0x8 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRL_APB.LPD_LSBUS_CTRL**: `0xff5e00ac = 0x01001202`
    [24]     CLKACT                         = 1 
    [13: 8] DIVISOR0                       = 0x12 
    [ 2: 0] SRCSEL                         = 0x2 

## FPD bus and APU clock
- **CRF_APB.ACPU_CTRL**: `0xfd1a0060 = 0x03000302`
    [25]     CLKACT_HALF                    = 1 
    [24]     CLKACT_FULL                    = 1 
    [13: 8] DIVISOR0                       = 0x3 
    [ 2: 0] SRCSEL                         = 0x2 
- **CRF_APB.DBG_TRACE_CTRL**: `0xfd1a0064 = 0x00002500`
    [24]     CLKACT                         = 0 
    [13: 8] DIVISOR0                       = 0x25 
    [ 2: 0] SRCSEL                         = 0x0 
- **CRF_APB.DBG_FPD_CTRL**: `0xfd1a0068 = 0x01000c02`
    [24]     CLKACT                         = 1 
    [13: 8] DIVISOR0                       = 0xc 
    [ 2: 0] SRCSEL                         = 0x2 
- **CRF_APB.GDMA_REF_CTRL**: `0xfd1a00b8 = 0x01000503`
    [24]     CLKACT                         = 1 
    [13: 8] DIVISOR0                       = 0x5 
    [ 2: 0] SRCSEL                         = 0x3 

# 7. Reset State
- **CRF_APB.RST_FPD_APU**: `0xfd1a0104 = 0x00003d0f`
    [13]     ACPU3_PWRON_RESET              = 1 
    [12]     ACPU2_PWRON_RESET              = 1 
    [11]     ACPU1_PWRON_RESET              = 1 
    [10]     ACPU0_PWRON_RESET              = 1 
    [ 8]     APU_L2_RESET                   = 1 
    [ 3]     ACPU3_RESET                    = 1 
    [ 2]     ACPU2_RESET                    = 1 
    [ 1]     ACPU1_RESET                    = 1 
    [ 0]     ACPU0_RESET                    = 1 
- **CRF_APB.RST_FPD_TOP**: `0xfd1a0100 = 0x000f9ffe`
    [19]     PCIE_CFG_RESET                 = 1 
    [18]     PCIE_BRIDGE_RESET              = 1 
    [17]     PCIE_CTRL_RESET                = 1 
    [16]     DP_RESET                       = 1 
    [15]     SWDT_RESET                     = 1 
    [12]     AFI_FM5_RESET                  = 1 
    [11]     AFI_FM4_RESET                  = 1 
    [10]     AFI_FM3_RESET                  = 1 
    [ 9]     AFI_FM2_RESET                  = 1 
    [ 8]     AFI_FM1_RESET                  = 1 
    [ 7]     AFI_FM0_RESET                  = 1 
    [ 6]     GDMA_RESET                     = 1 
    [ 5]     GPU_PP1_RESET                  = 1 
    [ 4]     GPU_PP0_RESET                  = 1 
    [ 3]     GPU_RESET                      = 1 
    [ 2]     GT_RESET                       = 1 
    [ 1]     SATA_RESET                     = 1 
- **CRF_APB.RST_DDR_SS**: `0xfd1a0108 = 0x0000000f`
    [ 3]     DDR_RESET                      = 1 
    [ 2]     APM_RESET                      = 1 
- **CRL_APB.RST_LPD_IOU0**: `0xff5e0230 = 0x0000000f`
    [ 3]     GEM3_RESET                     = 1 
    [ 2]     GEM2_RESET                     = 1 
    [ 1]     GEM1_RESET                     = 1 
    [ 0]     GEM0_RESET                     = 1 
- **CRL_APB.RST_LPD_IOU2**: `0xff5e0238 = 0x0017ffff`
    [20]     TIMESTAMP_RESET                = 1 
    [19]     IOU_CC_RESET                   = 0 
    [18]     GPIO_RESET                     = 1 
    [17]     ADMA_RESET                     = 1 
    [16]     NAND_RESET                     = 1 
    [15]     SWDT_RESET                     = 1 
    [14]     TTC3_RESET                     = 1 
    [13]     TTC2_RESET                     = 1 
    [12]     TTC1_RESET                     = 1 
    [11]     TTC0_RESET                     = 1 
    [10]     I2C1_RESET                     = 1 
    [ 9]     I2C0_RESET                     = 1 
    [ 8]     CAN1_RESET                     = 1 
    [ 7]     CAN0_RESET                     = 1 
    [ 6]     SDIO1_RESET                    = 1 
    [ 5]     SDIO0_RESET                    = 1 
    [ 4]     SPI1_RESET                     = 1 
    [ 3]     SPI0_RESET                     = 1 
    [ 2]     UART1_RESET                    = 1 
    [ 1]     UART0_RESET                    = 1 
    [ 0]     QSPI_RESET                     = 1 
- **CRL_APB.RST_LPD_TOP**: `0xff5e023c = 0x00188fd7`
    [23]     FPD_RESET                      = 0 
    [20]     LPD_SWDT_RESET                 = 1 
    [19]     AFI_FM6_RESET                  = 1 
    [17]     SYSMON_RESET                   = 0 
    [16]     RTC_RESET                      = 0 
    [15]     APM_RESET                      = 1 
    [14]     IPI_RESET                      = 0 
    [11]     USB1_APB_RESET                 = 1 
    [10]     USB0_APB_RESET                 = 1 
    [ 9]     USB1_HIBERRESET                = 1 
    [ 8]     USB0_HIBERRESET                = 1 
    [ 7]     USB1_CORERESET                 = 1 
    [ 6]     USB0_CORERESET                 = 1 
    [ 4]     RPU_PGE_RESET                  = 1 
    [ 3]     OCM_RESET                      = 0 
    [ 2]     RPU_AMBA_RESET                 = 1 
    [ 1]     RPU_R51_RESET                  = 1 
    [ 0]     RPU_R50_RESET                  = 1 

# 8. A53 Debug Gate + EDPCSR + Release (EL3)

Two posture questions about the APU debug surface:

1. **Is invasive debug (halt) open?** On a bare/idle board the open DAP can
   halt the A53 at will. Once secure firmware (e.g. ATF/bl31) configures the
   debug-authentication signals, the *same* DAP's halt request is refused — so
   whether halt succeeds is a posture signal that depends on the running firmware.
2. **Is non-invasive PC sampling (EDPCSR) available?** The A53 debug block can
   report a running core's PC via EDPCSR (DBGBASE+0xA0) WITHOUT halting; this
   works even when invasive debug is gated, and reveals whether code is running.

**EDPCSR sweep — non-invasive PC sample of all 4 A53 cores:**
```
  core 0: PC=(no sample)  EDPRSR=0x00000000  powered=false
  core 1: PC=(no sample)  EDPRSR=0x00000000  powered=false
  core 2: PC=(no sample)  EDPRSR=0x00000000  powered=false
  core 3: PC=(no sample)  EDPRSR=0x00000000  powered=false
```

**Releasing A53 core 0 from reset** (cores appear idle; idempotent):

**Invasive debug (halt) per core:**
```
  core 0: open
  core 1: unreachable
  core 2: unreachable
  core 3: unreachable
```

**Aggregate invasive-debug verdict: open** (c0=open c1=unreachable c2=unreachable c3=unreachable).
The DAP can halt at least one A53 core — invasive debug is open (dev baseline).

**Core 0 general-purpose / control registers (named, from OpenOCD cache):**
```
  pc           = 0x00000000fffc0000
  sp_el0       = register sp_el0 not found in current target
  sp_el1       = register sp_el1 not found in current target
  sp_el2       = register sp_el2 not found in current target
  sp_el3       = register sp_el3 not found in current target
  elr_el1      = register elr_el1 not found in current target
  elr_el2      = register elr_el2 not found in current target
  elr_el3      = register elr_el3 not found in current target
  cpsr         = 0x000003cd
```

**ARM system registers** are deferred to a stage-2 payload approach — OpenOCD 0.12's
aarch64 target doesn't expose them as named cache registers.

# 9. Code Execution Discovery

Probes OCM (and conditionally DDR) for boot-artifact signatures. Raw
results are captured to JSON; interpret.py applies findings rules.
- **OCM @ 0xfffc0000**: `first word = 0x14000000`
- **OCM @ 0xfffe0000**: `first word = 0xDEADBEEF`

DDR scan SKIPPED — boot mode is JTAG idle; DDR controller not initialized.
- **CSU_ROM_DIGEST_ADDR**: `0x26042731`

# 10. CoreSight DAP Topology (per-AP enumeration)

Walks every Access Port (AP) the DAP exposes, reads each AP's ID register
to identify its type, and for MEM-APs walks the ROM table to enumerate
every CoreSight component (DAP, ETM, ETB, CTI, ITM, DWT, etc.). ROM-table
entries each carry a Component Class + Peripheral ID that identifies the
block; OpenOCD's 'dap info N' command performs the full walk for us.

We capture the raw output verbatim for each AP rather than parse it —
ROM-table layout is complex enough that re-parsing it in Tcl risks
missing components. The verbatim text is structured enough for offline
analysis (you can grep for component classes, base addresses, PIDs).


## AP 0
```
AP # 0x0
		AP ID register 0x34770004
		Type is MEM-AP AXI3 or AXI4
MEM-AP BASE 0xfeff0002
		No ROM table present

```

## AP 1
```
JTAG-DP STICKY ERROR

```

## AP 2
```
AP # 0x2
		AP ID register 0x24760010
		Type is JTAG-AP

```

## AP 3
```
ERR: AP # 0x3
		AP ID register 0x00000000
		No AP found at this AP#0x3

```

# 11. ZynqMP Memory Map Reference

Quick reference for where things live on the ZynqMP SoC. These addresses
are SoC-level (identical across ZCU10x / Ultra96 / RFSoC / custom
ZynqMP boards). The Memory Map Probe below uses these addresses to
actually verify access.


| Address range | Block | Notes |
|---|---|---|
| `0x00000000 - 0x7FFFFFFF` | DDR (lower 2 GB) | Main system DRAM. Only accessible after DDR controller init by FSBL. |
| `0xC0000000 - 0xFCFFFFFF` | PL aperture / PCIe | Programmable Logic and PCIe BARs. Empty if PL unconfigured. |
| `0xFD000000 - 0xFD0FFFFF` | DDR controller | DDR controller registers @ 0xFD070000. |
| `0xFD1A0000 - 0xFD1AFFFF` | CRF_APB | Full-power domain Clock/Reset (APLL/DPLL/VPLL, RST_FPD_*). |
| `0xFD400000 - 0xFD4FFFFF` | SERDES | Gigabit transceivers (PCIe/SATA/USB3/DisplayPort). |
| `0xFD5C0000 - 0xFD5CFFFF` | APU registers | RVBARADDR0-3 reset vectors at +0x40,48,50,58. APU power/reset. |
| `0xFD610000 - 0xFD61FFFF` | FPD_SLCR | Full-power domain System Level Control Registers. |
| `0xFD800000 - 0xFD9FFFFF` | GPU (Mali-400) | Graphics processor registers. |
| `0xFE000000 - 0xFE00FFFF` | GIC distributor | Generic Interrupt Controller (v2). |
| `0xFE100000 - 0xFE1FFFFF` | VCU (video codec) | Video Codec Unit registers. |
| `0xFF000000 - 0xFF00FFFF` | PS UART0 | Main APU console UART. |
| `0xFF010000 - 0xFF01FFFF` | PS UART1 | Secondary UART. |
| `0xFF020000 - 0xFF02FFFF` | I2C0/1 | I2C controllers. |
| `0xFF040000 - 0xFF06FFFF` | SPI0/1, CAN0/1 | SPI and CAN controllers. |
| `0xFF0A0000 - 0xFF0AFFFF` | GPIO | MIO/EMIO GPIO controller. |
| `0xFF0F0000 - 0xFF0FFFFF` | QSPI controller | Quad-SPI flash controller. |
| `0xFF160000 - 0xFF17FFFF` | SDIO0/1 | SD/eMMC controllers. |
| `0xFF180000 - 0xFF18FFFF` | IOU_SLCR | MIO pin mux, tri-state, drive strength. |
| `0xFF300000 - 0xFF33FFFF` | IPI (Inter-Proc Interrupt) | PMU↔APU↔RPU communication. |
| `0xFF410000 - 0xFF41FFFF` | LPD_SLCR | Low-power domain System Level Control. |
| `0xFF5E0000 - 0xFF5EFFFF` | CRL_APB | Low-power domain Clock/Reset (IOPLL/RPLL, BOOT_MODE, RST_LPD_*, peripheral REF_CTRLs). |
| `0xFF9A0000 - 0xFF9AFFFF` | RPU configuration | Cortex-R5 cluster control. |
| `0xFFC80000 - 0xFFCBFFFF` | CSUDMA + CSU | CSU at 0xFFCA0000 (security unit), CSU DMA at 0xFFC80000. |
| `0xFFCC0000 - 0xFFCCFFFF` | eFUSE controller | eFUSE shadow registers at +0x1000 (DNA, SEC_CTRL, PPK hashes). |
| `0xFFCD0000 - 0xFFCDFFFF` | BBRAM | Battery-Backed RAM — stores AES key when used. |
| `0xFFCE0000 - 0xFFCEFFFF` | RSA core | Hardware RSA-2048/4096 accelerator. |
| `0xFFD80000 - 0xFFD8FFFF` | PMU_GLOBAL | PMU state, power/reset of every domain. |
| `0xFFDC0000 - 0xFFDDFFFF` | PMU RAM (LMB) | Where PMU firmware runs. Triple-redundant MicroBlaze code. |
| `0xFFE00000 - 0xFFE3FFFF` | RPU TCM | Tightly-Coupled Memory for R5 cores (0xFFE00000=R5_0, 0xFFE20000=R5_1). |
| `0xFFFC0000 - 0xFFFFFFFF` | OCM (4×64 KB SRAM) | On-chip SRAM. Default FSBL/ATF load region. Always-on (LPD power). |


**Important register-level addresses** (subset of above with specific use):

| Address | Symbol | Use |
|---|---|---|
| `0xFFCA0040` | CSU.IDCODE | Silicon ID + part code |
| `0xFFCA0044` | CSU.VERSION | Silicon revision + PMU BootROM version |
| `0xFFCA0038` | CSU.JTAG_SEC | Secure JTAG gates |
| `0xFFCA003C` | CSU.JTAG_DAP_CFG | Per-core debug authorization |
| `0xFFCA0010` | CSU.MULTI_BOOT | Boot image search offset |
| `0xFFCC1058` | EFUSE.SEC_CTRL | Secure boot policy fuses |
| `0xFFCC100C` | EFUSE.DNA_0 | Per-chip unique ID (low) |
| `0xFFD80100` | PMU_GLOBAL.PWR_STATE | Per-domain power state |
| `0xFD1A0044` | CRF_APB.PLL_STATUS | APLL/DPLL/VPLL lock status |
| `0xFF5E0040` | CRL_APB.PLL_STATUS | IOPLL/RPLL lock status |
| `0xFF5E0200` | CRL_APB.BOOT_MODE_USER | Boot mode pin readout |
| `0xFD1A0104` | CRF_APB.RST_FPD_APU | A53 core reset bits |
| `0xFD5C0040` | APU.RVBARADDR0L | A53 core 0 reset vector (low 32 bits) |
| `0xFD5C0044` | APU.RVBARADDR0H | A53 core 0 reset vector (high 32 bits) |
| `0xFFFC0000` | OCM Bank 0 start | Common FSBL load address |
| `0xFFFEA000` | OCM Bank 3 (ATF area) | ARM Trusted Firmware default load |
| `0x00080000` | DDR + 512 KB | Linux kernel Image (older PetaLinux) |
| `0x00100000` | DDR + 1 MB | Device tree (DTB) per PetaLinux default |
| `0x00200000` | DDR + 2 MB | Linux kernel Image (PetaLinux 2020.2+) |
| `0x04000000` | DDR + 64 MB | initramfs / rootfs.cpio (PetaLinux) |
| `0x08000000` | DDR + 128 MB | U-Boot proper (canonical load address) |


# 12. Memory Map Probe

Reading representative addresses to see what's responsive at the AXI level.

## OCM (on-chip SRAM, 4 banks of 64 KB)

**OCM Bank 0 start (0xFFFC0000)** (0xfffc0000, 8 words):
```
  0xfffc0000:  14000000 deadbeef deadbeef deadbeef
  0xfffc0010:  deadbeef deadbeef deadbeef deadbeef
```

**OCM Bank 0 mid** (0xfffc8000, 8 words):
```
  0xfffc8000:  deadbeef deadbeef deadbeef deadbeef
  0xfffc8010:  deadbeef deadbeef deadbeef deadbeef
```

**OCM Bank 1 start** (0xfffd0000, 8 words):
```
  0xfffd0000:  deadbeef deadbeef deadbeef deadbeef
  0xfffd0010:  deadbeef deadbeef deadbeef deadbeef
```

**OCM Bank 2 start** (0xfffe0000, 8 words):
```
  0xfffe0000:  deadbeef deadbeef deadbeef deadbeef
  0xfffe0010:  deadbeef deadbeef deadbeef deadbeef
```

**OCM Bank 3 start** (0xffff0000, 8 words):
```
  0xffff0000:  deadbeef deadbeef deadbeef deadbeef
  0xffff0010:  deadbeef deadbeef deadbeef deadbeef
```

**BootROM region @ 0xFFFFC000 (CSU ROM may be mapped here)** (0xffffc000, 8 words):
```
  0xffffc000:  deadbeef deadbeef deadbeef deadbeef
  0xffffc010:  deadbeef deadbeef deadbeef deadbeef
```

## Known-accessible blocks (CSU, EFUSE, IOU_SLCR)

_(Other peripheral bases like I2C0/SPI/GEM/SDIO/USB are held in reset per §7's
RST_LPD_IOU2 dump. Probing them in JTAG idle causes AXI timeouts that wedge the_
_DAP. Use a separate script to probe them after the relevant resets are cleared.)_

- **CSU @ 0xffca0000**: `0x00000000`
- **EFUSE @ 0xffcc0000**: `0x00000001`
- **BBRAM @ 0xffcd0000**: `0x00000000`
- **IOU_SLCR @ 0xff180000**: `0x00000000`
- **CRL_APB @ 0xff5e0000**: `0x00000000`
- **CRF_APB @ 0xfd1a0000**: `0x00000000`
- **PMU_GLOBAL @ 0xffd80000**: `0x00018800`

## Variant-specific blocks (informational — see §2 variant capabilities)

Based on the variant lookup, this die's variant-conditional blocks:

- **Mali-400 GPU**: `expected @ 0xFD4B0000 (linux-xlnx zynqmp.dtsi). NOT probed in baseline — needs GPU clock enable first (deferred to deep-probe phase).`
- **VCU (H.264/H.265)**: `not present on this die (per variant table).`
- **GEM Ethernet controllers**: `4 expected per variant table. State already shown in §6 CRL_APB.GEM[0-3]_REF_CTRL dumps.`

## DDR access (informational — DDR controller not initialized in JTAG idle)

_(Skipped — reading uninitialized DDR causes AXI timeouts that wedge the DP._
_Run with a DDR-initialized hardware platform to actually probe DDR.)_

# 13. XPPU (Xilinx Peripheral Protection Unit)

XPPU gates which AXI masters (APU, RPU, PMU, DMA engines, PL masters,
etc.) can access which peripheral apertures in the LPD. On a properly
hardened device it enforces hardware-level master/peripheral isolation;
on a misconfigured device any master can talk to any peripheral. The
LPD XPPU is at 0xFF980000 (UG1085 §16).

Bit layouts sourced from Xilinx QEMU model (include/hw/misc/xlnx-xppu.h).
- **XPPU.CTRL**: `0xff980000 = 0x00000000`
    [ 2]     APER_PARITY_EN                 = 0 
    [ 1]     MID_PARITY_EN                  = 0 
    [ 0]     ENABLE                         = 0 
- **XPPU.ERR_STATUS1**: `0xff980004 = 0x00000000`
- **XPPU.ERR_STATUS2**: `0xff980008 = 0x00000000`
    [ 9: 0] AXI_ID                         = 0x0 
- **XPPU.POISON**: `0xff98000c = 0x000ff9c0`
  _(no QEMU register model for this address — bit fields unverified)_
- **XPPU.ISR**: `0xff980010 = 0x00000000`
    [ 7]     APER_PARITY                    = 0 
    [ 6]     APER_TZ                        = 0 
    [ 5]     APER_PERM                      = 0 
    [ 3]     MID_PARITY                     = 0 
    [ 2]     MID_RO                         = 0 
    [ 1]     MID_MISS                       = 0 
    [ 0]     INV_APB                        = 0 
- **XPPU.IMR**: `0xff980014 = 0x000000ef`
    [ 7]     APER_PARITY                    = 1 
    [ 6]     APER_TZ                        = 1 
    [ 5]     APER_PERM                      = 1 
    [ 3]     MID_PARITY                     = 1 
    [ 2]     MID_RO                         = 1 
    [ 1]     MID_MISS                       = 1 
    [ 0]     INV_APB                        = 1 
- **XPPU.M_MASTER_IDS**: `0xff98003c = 0x00000014`
- **XPPU.M_APERTURE_64KB**: `0xff980044 = 0x00000100`
- **XPPU.M_APERTURE_1MB**: `0xff980048 = 0x00000010`
- **XPPU.M_APERTURE_512MB**: `0xff98004c = 0x00000001`
- **XPPU.BASE_64KB**: `0xff980054 = 0xff000000`
- **XPPU.BASE_1MB**: `0xff980058 = 0xfe000000`
- **XPPU.BASE_512MB**: `0xff98005c = 0xc0000000`

**Master ID slots** (first 8 of 20 — full set at 0xFF980100..0xFF98014C):
- **MASTER_ID @ 0xFF980100**: `raw=0x83FF0040 (MID=0x040 mask=0x3FF RO=0 parity=1)`
- **MASTER_ID @ 0xFF980104**: `raw=0x03F00000 (MID=0x000 mask=0x3F0 RO=0 parity=0)`
- **MASTER_ID @ 0xFF980108**: `raw=0x83F00010 (MID=0x010 mask=0x3F0 RO=0 parity=1)`
- **MASTER_ID @ 0xFF98010C**: `raw=0x83C00080 (MID=0x080 mask=0x3C0 RO=0 parity=1)`
- **MASTER_ID @ 0xFF980110**: `raw=0x83C30080 (MID=0x080 mask=0x3C3 RO=0 parity=1)`
- **MASTER_ID @ 0xFF980114**: `raw=0x03C30081 (MID=0x081 mask=0x3C3 RO=0 parity=0)`
- **MASTER_ID @ 0xFF980118**: `raw=0x03C30082 (MID=0x082 mask=0x3C3 RO=0 parity=0)`
- **MASTER_ID @ 0xFF98011C**: `raw=0x83C30083 (MID=0x083 mask=0x3C3 RO=0 parity=1)`

# 14. RPU Configuration (Cortex-R5 cluster)

RPU at 0xFF9A0000 controls the Cortex-R5 cluster: lockstep vs split
mode, per-core configuration (vector base, halt state, coherency),
and the per-core slave-port base addresses that determine where TCM
is visible to other masters.

Bit layouts sourced from Xilinx QEMU model (xilinx_zynqmp_rpu_ctrl.c).
- **RPU.RPU_GLBL_CNTL**: `0xff9a0000 = 0x00000050`
    [10]     GIC_AXPROT                     = 0 
    [ 8]     TCM_CLK_CNTL                   = 0 
    [ 7]     TCM_WAIT                       = 0 
    [ 6]     TCM_COMB                       = 1 
    [ 5]     TEINIT                         = 0 
    [ 4]     SLCLAMP                        = 1 
    [ 3]     SLSPLIT                        = 0 
    [ 2]     DBGNOCLKSTOP                   = 0 
    [ 1]     CFGIE                          = 0 
    [ 0]     CFGEE                          = 0 
- **RPU.RPU_GLBL_STATUS**: `0xff9a0004 = 0x00000000`
    [ 0]     DBGNOPWRDWN                    = 0 
- **RPU.RPU_ERR_CNTL**: `0xff9a0008 = 0x00000000`
    [ 0]     APB_ERR_RES                    = 0 
- **RPU.RPU_0_CFG**: `0xff9a0100 = 0x00000005`
    [ 3]     CFGNMFI0                       = 0 
    [ 2]     VINITHI                        = 1 
    [ 1]     COHERENT                       = 0 
    [ 0]     NCPUHALT                       = 1 
- **RPU.RPU_0_STATUS**: `0xff9a0104 = 0x0000003f`
    [ 5]     NVALRESET                      = 1 
    [ 4]     NVALIRQ                        = 1 
    [ 3]     NVALFIQ                        = 1 
    [ 2]     NWFIPIPESTOPPED                = 1 
    [ 1]     NWFEPIPESTOPPED                = 1 
    [ 0]     NCLKSTOPPED                    = 1 
- **RPU.RPU_0_SLV_BASE**: `0xff9a0124 = 0x00000000`
    [ 7: 0] ADDR                           = 0x0 
- **RPU.RPU_1_CFG**: `0xff9a0200 = 0x00000005`
    [ 3]     CFGNMFI1                       = 0 
    [ 2]     VINITHI                        = 1 
    [ 1]     COHERENT                       = 0 
    [ 0]     NCPUHALT                       = 1 
- **RPU.RPU_1_STATUS**: `0xff9a0204 = 0x0000003f`
    [ 5]     NVALRESET                      = 1 
    [ 4]     NVALIRQ                        = 1 
    [ 3]     NVALFIQ                        = 1 
    [ 2]     NWFIPIPESTOPPED                = 1 
    [ 1]     NWFEPIPESTOPPED                = 1 
    [ 0]     NCLKSTOPPED                    = 1 
- **RPU.RPU_1_SLV_BASE**: `0xff9a0224 = 0x00000000`
    [ 7: 0] ADDR                           = 0x0 

# 15. IPI (Inter-Processor Interrupt) — APU agent window

IPI lets the four processor classes (APU, RPU, PMU, PL) signal each
other via dedicated 1-bit channels per source/destination pair. Each
agent has its own window — APU at 0xFF300000, RPU_0 at 0xFF310000,
RPU_1 at 0xFF320000, PMU_0..3 at 0xFF330000..0xFF360000.

We read APU's window — reveals which agents have signaled APU and
which the APU is masking/handling. The bit-per-agent layout in each
register is the same: APU=[0], RPU_0=[8], RPU_1=[9], PMU_0..3=[16-19],
PL_0..3=[24-27].

Bit layouts sourced from Xilinx QEMU model (xlnx-zynqmp-ipi.c).
- **IPI.IPI_TRIG**: `0xff300000 = 0x00000000`
    [27]     PL_3                           = 0 
    [26]     PL_2                           = 0 
    [25]     PL_1                           = 0 
    [24]     PL_0                           = 0 
    [19]     PMU_3                          = 0 
    [18]     PMU_2                          = 0 
    [17]     PMU_1                          = 0 
    [16]     PMU_0                          = 0 
    [ 9]     RPU_1                          = 0 
    [ 8]     RPU_0                          = 0 
    [ 0]     APU                            = 0 
- **IPI.IPI_OBS**: `0xff300004 = 0x00000000`
    [27]     PL_3                           = 0 
    [26]     PL_2                           = 0 
    [25]     PL_1                           = 0 
    [24]     PL_0                           = 0 
    [19]     PMU_3                          = 0 
    [18]     PMU_2                          = 0 
    [17]     PMU_1                          = 0 
    [16]     PMU_0                          = 0 
    [ 9]     RPU_1                          = 0 
    [ 8]     RPU_0                          = 0 
    [ 0]     APU                            = 0 
- **IPI.IPI_ISR**: `0xff300010 = 0x00000000`
    [27]     PL_3                           = 0 
    [26]     PL_2                           = 0 
    [25]     PL_1                           = 0 
    [24]     PL_0                           = 0 
    [19]     PMU_3                          = 0 
    [18]     PMU_2                          = 0 
    [17]     PMU_1                          = 0 
    [16]     PMU_0                          = 0 
    [ 9]     RPU_1                          = 0 
    [ 8]     RPU_0                          = 0 
    [ 0]     APU                            = 0 
- **IPI.IPI_IMR**: `0xff300014 = 0x0f0f0301`
    [27]     PL_3                           = 1 
    [26]     PL_2                           = 1 
    [25]     PL_1                           = 1 
    [24]     PL_0                           = 1 
    [19]     PMU_3                          = 1 
    [18]     PMU_2                          = 1 
    [17]     PMU_1                          = 1 
    [16]     PMU_0                          = 1 
    [ 9]     RPU_1                          = 1 
    [ 8]     RPU_0                          = 1 
    [ 0]     APU                            = 1 

# 16. XMPU (Xilinx Memory Protection Unit) — selected instances

XMPU gates which AXI masters can read/write which memory regions. It's
the memory-range counterpart to XPPU (which gates peripheral apertures).
ZynqMP has 8 XMPU instances per UG1085 section 16:

- DDR_XMPU0..5: 0xFD000000, 0xFD010000, 0xFD020000, 0xFD030000,
  0xFD040000, 0xFD050000 — one per DDR controller channel/partition
- FPD_XMPU: 0xFD5D0000 — FPD master bus
- OCM_XMPU: 0xFFA70000 — OCM (on-chip SRAM) protection

Each instance has identical register layout — CTRL, ISR, IMR, IEN, IDS,
LOCK, ECO at fixed offsets, plus 16 region descriptors (R00..R15) at
0x100+. This section reads only CTRL/ISR/IMR/LOCK for the two most-
confident instance bases (OCM_XMPU + DDR_XMPU0). Other instances skipped
to avoid risk of DAP-wedging on unverified addresses; expand once
u-boot-xlnx is cloned for authoritative XMPU base addresses.

Bit layouts sourced from Xilinx QEMU model (include/hw/misc/xlnx-xmpu.h).

## OCM_XMPU (0xFFA70000) — protection for OCM SRAM banks
- **OCM_XMPU.CTRL**: `0xffa70000 = 0x00000003`
    [ 3]     ALIGNCFG                       = 0 
    [ 2]     HIDEALLOWED                    = 0 
    [ 1]     DEFWRALLOWED                   = 1 
    [ 0]     DEFRDALLOWED                   = 1 
- **OCM_XMPU.ISR**: `0xffa70010 = 0x00000000`
    [ 3]     SECURITYVIO                    = 0 
    [ 2]     WRPERMVIO                      = 0 
    [ 1]     RDPERMVIO                      = 0 
    [ 0]     INV_APB                        = 0 
- **OCM_XMPU.IMR**: `0xffa70014 = 0x0000000f`
    [ 3]     SECURITYVIO                    = 1 
    [ 2]     WRPERMVIO                      = 1 
    [ 1]     RDPERMVIO                      = 1 
    [ 0]     INV_APB                        = 1 
- **OCM_XMPU.LOCK**: `0xffa70020 = 0x00000000`
    [ 0]     REGWRDIS                       = 0 

## DDR_XMPU0 (0xFD000000) — protection for DDR controller channel 0
- **DDR_XMPU0.CTRL**: `0xfd000000 = 0x0000000b`
    [ 3]     ALIGNCFG                       = 1 
    [ 2]     HIDEALLOWED                    = 0 
    [ 1]     DEFWRALLOWED                   = 1 
    [ 0]     DEFRDALLOWED                   = 1 
- **DDR_XMPU0.ISR**: `0xfd000010 = 0x00000000`
    [ 3]     SECURITYVIO                    = 0 
    [ 2]     WRPERMVIO                      = 0 
    [ 1]     RDPERMVIO                      = 0 
    [ 0]     INV_APB                        = 0 
- **DDR_XMPU0.IMR**: `0xfd000014 = 0x0000000f`
    [ 3]     SECURITYVIO                    = 1 
    [ 2]     WRPERMVIO                      = 1 
    [ 1]     RDPERMVIO                      = 1 
    [ 0]     INV_APB                        = 1 
- **DDR_XMPU0.LOCK**: `0xfd000020 = 0x00000000`
    [ 0]     REGWRDIS                       = 0 

## DDR_XMPU1..5 + FPD_XMPU — remaining DDR/FPD TrustZone partitions
(CTRL = enable + default-region permit; LOCK = region config frozen)
- **reg @ 0xFD010000**: `0xfd010000 = 0xfd010000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD010020**: `0xfd010020 = 0xfd010020`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD020000**: `0xfd020000 = 0xfd020000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD020020**: `0xfd020020 = 0xfd020020`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD030000**: `0xfd030000 = 0xfd030000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD030020**: `0xfd030020 = 0xfd030020`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD040000**: `0xfd040000 = 0xfd040000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD040020**: `0xfd040020 = 0xfd040020`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD050000**: `0xfd050000 = 0xfd050000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD050020**: `0xfd050020 = 0xfd050020`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD5D0000**: `0xfd5d0000 = 0xfd5d0000`
  _(no QEMU register model for this address — bit fields unverified)_
- **reg @ 0xFD5D0020**: `0xfd5d0020 = 0xfd5d0020`
  _(no QEMU register model for this address — bit fields unverified)_

# 17. PL TAP + PCAP Configuration Status

The PL (FPGA fabric) is configured via PCAP (Processor Configuration
Access Port) by the PMU/CSU during boot, or via the PL JTAG TAP for
external bitstream loading. PCAP_STATUS at 0xFFCA3010 reveals the PL's
current configuration state: is a bitstream loaded (PL_DONE), did
end-of-startup finish (PL_EOS), is the fabric in init (PL_INIT),
PL housekeeping signals (PCFG_GWE / PL_GHIGH_B / PL_GTS_*), and tamper-
related SEU error status.

We also read PCAP_CTRL (whether PCAP is the active config interface
vs ICAP), PCAP_PROG (PROG_B pin state — clears PL config when low),
PCAP_RDWR (read vs write direction), and PCAP_RESET (PCAP block reset).

Bit layouts sourced from Xilinx QEMU model (csu_core.c).
- **CSU.PCAP_PROG**: `0xffca3000 = 0x00000001`
    [ 0]     PCFG_PROG_B                    = 1 
- **CSU.PCAP_RDWR**: `0xffca3004 = 0x00000000`
    [ 0]     PCAP_RDWR_B                    = 0 
- **CSU.PCAP_CTRL**: `0xffca3008 = 0x00000001`
    [ 3]     PCFG_GSR                       = 0 
    [ 2]     PCFG_GTS                       = 0 
    [ 1]     PCFG_POR_CNT_4K                = 0 
    [ 0]     PCAP_PR                        = 1 
- **CSU.PCAP_RESET**: `0xffca300c = 0x00000001`
    [ 0]     RESET                          = 1 
- **CSU.PCAP_STATUS**: `0xffca3010 = 0xa0000a46`
    [13]     PCFG_GWE                       = 0 
    [12]     PCFG_MCAP_MODE                 = 0 
    [11]     PL_GTS_USR_B                   = 1 
    [10]     PL_GTS_CFG_B                   = 0 
    [ 9]     PL_GPWRDWN_B                   = 1 
    [ 8]     PL_GHIGH_B                     = 0 
    [ 7]     PL_FST_CFG                     = 0 
    [ 6]     PL_CFG_RESET_B                 = 1 
    [ 5]     PL_SEU_ERROR                   = 0 
    [ 4]     PL_EOS                         = 0 
    [ 3]     PL_DONE                        = 0 
    [ 2]     PL_INIT                        = 1 
    [ 1]     PCAP_RD_IDLE                   = 1 
    [ 0]     PCAP_WR_IDLE                   = 0 

# 18. SLCR Security Controls (LPD / FPD / IOU_SECURE / LPD_SECURE)

ZynqMP doesn't have a classical WPROT lock register the way Zynq-7000
did. SLCR security state is split across:

- LPD_SLCR (0xFF410000) / FPD_SLCR (0xFD610000): CTRL.SLVERR_ENABLE
  (do bad register accesses raise AXI SLVERR or silently complete?)
  + ISR.ADDR_DECODE_ERR (latched bad-access count) + IMR mask + WPROT0
- IOU_SECURE_SLCR (0xFF240000): per-peripheral AXI AWPROT/ARPROT —
  determines whether GEM0..3 and SD0/1 emit secure or non-secure AXI
  traffic. Bad value here makes peripheral DMA fail at XPPU/XMPU.
- LPD_SLCR_SECURE (0xFF4B0000): TrustZone gating for USB controllers.

Register layouts hand-verified from Xilinx PMU-FW headers (lpd_slcr.h,
iou_secure_slcr.h, lpd_slcr_secure.h) plus UG1085 §36 for FPD_SLCR.


## LPD_SLCR (0xFF410000)
- **LPD_SLCR.WPROT0**: `0xff410000 = 0x00000001`
    [ 0]     ACTIVE                         = 1 
- **LPD_SLCR.CTRL**: `0xff410004 = 0x00000000`
    [ 0]     SLVERR_ENABLE                  = 0 
- **LPD_SLCR.ISR**: `0xff410008 = 0x00000000`
    [ 0]     ADDR_DECODE_ERR                = 0 
- **LPD_SLCR.IMR**: `0xff41000c = 0x00000001`
    [ 0]     ADDR_DECODE_ERR                = 1 


## FPD_SLCR (0xFD610000)
- **FPD_SLCR.WPROT0**: `0xfd610000 = 0x00000001`
    [ 0]     ACTIVE                         = 1 
- **FPD_SLCR.CTRL**: `0xfd610004 = 0x00000000`
    [ 0]     SLVERR_ENABLE                  = 0 
- **FPD_SLCR.ISR**: `0xfd610008 = 0x00000000`
    [ 0]     ADDR_DECODE_ERR                = 0 
- **FPD_SLCR.IMR**: `0xfd61000c = 0x00000001`
    [ 0]     ADDR_DECODE_ERR                = 1 


## IOU_SECURE_SLCR (0xFF240000) — per-peripheral AXI protection
- **IOU_SECURE_SLCR.IOU_AXI_WPRTCN**: `0xff240000 = 0x00000000`
    [21:19] SD1_AXI_AWPROT                 = 0x0 
    [18:16] SD0_AXI_AWPROT                 = 0x0 
    [11: 9] GEM3_AXI_AWPROT                = 0x0 
    [ 8: 6] GEM2_AXI_AWPROT                = 0x0 
    [ 5: 3] GEM1_AXI_AWPROT                = 0x0 
    [ 2: 0] GEM0_AXI_AWPROT                = 0x0 
- **IOU_SECURE_SLCR.IOU_AXI_RPRTCN**: `0xff240004 = 0x00000000`
    [21:19] SD1_AXI_ARPROT                 = 0x0 
    [18:16] SD0_AXI_ARPROT                 = 0x0 
    [11: 9] GEM3_AXI_ARPROT                = 0x0 
    [ 8: 6] GEM2_AXI_ARPROT                = 0x0 
    [ 5: 3] GEM1_AXI_ARPROT                = 0x0 
    [ 2: 0] GEM0_AXI_ARPROT                = 0x0 


## LPD_SLCR_SECURE (0xFF4B0000) — USB TrustZone gating
- **LPD_SLCR_SECURE.SLCR_USB**: `0xff4b0034 = 0x00000003`
    [ 1]     TZ_USB3_1                      = 1 
    [ 0]     TZ_USB3_0                      = 1 

# Cleanup: re-assert A53 reset for next run

Re-asserting ACPU0_RESET (bit 0) and ACPU0_PWRON_RESET (bit 10) and
APU_L2_RESET (bit 8) of RST_FPD_APU. This puts A53 core 0 back in reset
so the next run of this script doesn't hit the DAP-wedge issue.

- **RST_FPD_APU before**: `0x0000380e`
- **RST_FPD_APU after**: `0x00003d0f`

_(A53 core 0 is now back in reset. Re-run of this script will start clean.)_

# Done

Report saved to: `/tmp/tmp.GQ2G5piA7m/reports/enumerate-GOLDEN-FROZEN-TIMESTAMP.md`
Raw JSON capture: `/tmp/tmp.GQ2G5piA7m/reports/raw-GOLDEN-FROZEN-TIMESTAMP.json`
