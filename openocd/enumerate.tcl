# ZCU102 / Zynq UltraScale+ MPSoC comprehensive JTAG enumeration.
#
# Produces a baseline report of silicon identity, security state, power,
# clocks, A53 system registers, and CoreSight topology — without needing
# any vendor toolchain.
#
# Reproduce on any ZynqMP-based board to compare against this baseline.
#
# Usage:
#   cd /home/kali/Desktop/research/JTAG
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl"
#
# Report is written to BOTH stdout AND reports/enumerate-<timestamp>.md.

source openocd/lib/enum-helpers.tcl
source openocd/lib/zynqmp-variants.tcl
source openocd/lib/json-emit.tcl
source openocd/lib/zynqmp-regs-qemu.tcl
source openocd/lib/zynqmp-regs-extension.tcl

# Open report file. Honor ::TS_OVERRIDE and ::REPORT_DIR_OVERRIDE so the
# mock-based golden-test driver can pin filenames and directories for a
# deterministic roundtrip diff.
if {[info exists ::TS_OVERRIDE]} {
    set ts $::TS_OVERRIDE
} else {
    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H%M%S"]
}
set _report_dir "reports"
if {[info exists ::REPORT_DIR_OVERRIDE]} {
    set _report_dir $::REPORT_DIR_OVERRIDE
}
set REPORT_PATH "$_report_dir/enumerate-$ts.md"
set RAW_PATH    "$_report_dir/raw-$ts.json"
set REPORT_FH [open $REPORT_PATH w]

# Seed the JSON capture's metadata block. Per-register data will be
# populated by dump_reg_qemu calls as they execute.
dict set ::CAPTURED metadata timestamp $ts
dict set ::CAPTURED metadata board "ZCU102"
dict set ::CAPTURED metadata tool "enumerate.tcl"
dict set ::CAPTURED metadata tool_version "1.0"
dict set ::CAPTURED metadata raw_path $RAW_PATH
dict set ::CAPTURED metadata report_path $REPORT_PATH

say "# ZCU102 / ZynqMP Enumeration Report"
say ""
say "- Generated: $ts"
say "- Tool: OpenOCD via on-board Digilent SMT2 / FT232H"
say "- Report file: $REPORT_PATH"
say "- Raw JSON capture: $RAW_PATH"

# ---------------------------------------------------------------------------
say_h1 "1. JTAG Chain"
# ---------------------------------------------------------------------------
say ""
say "TAPs discovered during init (see OpenOCD startup log for IDCODEs):"
say ""
say "| TAP | IRLen | Expected role |"
say "|-----|-------|---------------|"
say "| \`uscale.ps\` | 12 | Xilinx Zynq UltraScale+ PS-TAP |"
say "| \`uscale.tap\` | 4 | ARM CoreSight DAP |"
say ""
say "(Captured IDCODEs are in the OpenOCD log above this section.)"

# ------------------------------------------------------------------
# DAP recovery: clear sticky errors from failed A53 init-examination,
# then examine the AXI mem-AP explicitly.
# ------------------------------------------------------------------
catch { uscale.dap dpreg 0 0x1e } _
catch { uscale.axi arp_examine } _
targets uscale.axi

# Sanity-check that reads work. If not, abort with power-cycle advice.
set _probe [safe_rd 0xFFCA0040]
if {$_probe eq "ERR"} {
    say ""
    say "**FATAL: AXI mem-AP not reachable.**"
    say ""
    say "Almost certainly caused by: A53 core 0 already released from a prior session,"
    say "which leaves the DP in a state OpenOCD's recovery can't clear cleanly."
    say ""
    say "**Recovery: power-cycle the board.**"
    say "1. Flip SW1 OFF, count to 5, flip back ON."
    say "2. In VMware, re-click Connect on FT232H if it disappeared."
    say "3. Re-run this script."
    say ""
    say "The script's end-of-run cleanup re-asserts A53 reset to avoid this on"
    say "subsequent runs."
    say ""
    close $REPORT_FH
    exit
}
say ""
say "_(AXI mem-AP examined and verified responsive — proceeding with enumeration.)_"

# ---------------------------------------------------------------------------
say_h1 "2. Silicon Identity"
# ---------------------------------------------------------------------------
set _idcode [safe_rd 0xFFCA0040]
# IDCODE field layout is IEEE 1149.1 standard (not Xilinx-specific), so
# QEMU's REG32 has no FIELDs for it. dump_reg_qemu emits the raw value;
# the IEEE 1149.1 field decode (CONST_1/MANUF_ID/PART_ID/REVISION) is
# captured in the variant block of the JSON instead.
dump_reg_qemu 0xFFCA0040 "CSU.IDCODE"
# Manually record the IEEE 1149.1 fields into the JSON capture for
# interpretive use by interpret.py (which sees these via ::CAPTURED.registers
# rather than reparsing).
if {$_idcode ne "ERR" && [info commands capture_register] ne ""} {
    set _idfields [dict create]
    dict set _idfields CONST_1   [dict create bits "0"     value [expr {$_idcode & 1}]]
    dict set _idfields MANUF_ID  [dict create bits "11:1"  value [expr {($_idcode >> 1) & 0x7FF}]]
    dict set _idfields PART_ID   [dict create bits "27:12" value [expr {($_idcode >> 12) & 0xFFFF}]]
    dict set _idfields REVISION  [dict create bits "31:28" value [expr {($_idcode >> 28) & 0xF}]]
    capture_register 0xFFCA0040 IDCODE CSU $_idcode $_idfields
}
set _version [safe_rd 0xFFCA0044]
# Was: PMU_ROM_VER [15:4]. Correct per QEMU: PS_VERSION [3:0], PLATFORM [15:12].
dump_reg_qemu 0xFFCA0044 "CSU_VERSION"

say ""
say "**eFUSE Device DNA** (unique per chip, 96 bits; controller @ 0xFFCC0000):"
# Per Xilinx xilskey_eps_zynqmp_hw.h: DNA at eFUSE shadow offsets 0x100C/0x1010/0x1014.
# (Prior versions of this script had 0x10C0/0xC4/0xC8 which is wrong — that's PPK0 area.)
set dna0 [safe_rd 0xFFCC100C]
set dna1 [safe_rd 0xFFCC1010]
set dna2 [safe_rd 0xFFCC1014]
say_kv "DNA\[31:0\]"   [hex32 $dna0]
say_kv "DNA\[63:32\]"  [hex32 $dna1]
say_kv "DNA\[95:64\]"  [hex32 $dna2]

# Stash identity + variant profile + DNA in ::CAPTURED. interpret.py renders
# the silicon identity table and any rules that need part_id / silicon_rev
# / device DNA / variant capabilities.
set ::VARIANT_PROFILE ""
if {$_idcode ne "ERR"} {
    set _part [expr {($_idcode >> 12) & 0xFFFF}]
    set _rev  [expr {($_idcode >> 28) & 0xF}]
    set _part_hex [format "0x%04x" $_part]
    set ::VARIANT_PROFILE [variant_lookup_by_idcode $_idcode]
    dict set ::CAPTURED variant part_id     $_part_hex
    dict set ::CAPTURED variant silicon_rev $_rev
    dict set ::CAPTURED variant idcode_raw  [format "0x%08X" [expr {int($_idcode)}]]
    dict for {_vk _vv} $::VARIANT_PROFILE {
        dict set ::CAPTURED variant $_vk $_vv
    }
    dict set ::CAPTURED variant device_dna_0 [hex32 $dna0]
    dict set ::CAPTURED variant device_dna_1 [hex32 $dna1]
    dict set ::CAPTURED variant device_dna_2 [hex32 $dna2]
}

# ---------------------------------------------------------------------------
say_h1 "3. Boot State"
# ---------------------------------------------------------------------------
set _boot_mode_reg [safe_rd 0xFF5E0200]
# Was: USE_ALT [4], ALT_BOOT_MODE [11:8]. Correct: USE_ALT [8], ALT_BOOT_MODE [15:12].
dump_reg_qemu 0xFF5E0200
# BOOT_MODE_POR has THREE 4-bit fields (BOOT_MODE0/1/2), not one. Script was
# reading only the first 4 bits and calling them "BOOT_MODE_LATCHED_AT_POR".
dump_reg_qemu 0xFF5E0204
dump_reg_qemu 0xFFCA0010 "CSU_MULTI_BOOT"
set _reset_reason [safe_rd 0xFF5E0220]
# Was: ERR_POR/SRST/DBG_RST/SLC_RST/SWDT0/SWDT1/EXT_POR/INT_POR (fabricated).
# Correct per QEMU: EXTERNAL_POR/INTERNAL_POR/PMU_SYS_RESET/PSONLY_RESET_REQ
# /SRST/SOFT/DEBUG_SYS at bits 0-6. Every prior "reset reason" finding was
# misclassifying the reset source.
dump_reg_qemu 0xFF5E0220
dump_reg_qemu 0xFFCA0000 "CSU_STATUS"

# Capture boot mode + reset reason summary into ::CAPTURED.boot_state.
# interpret.py rules derive boot mode name and reset-classification text
# from the raw register field values.
if {$_boot_mode_reg ne "ERR"} {
    dict set ::CAPTURED boot_state boot_mode_value [expr {$_boot_mode_reg & 0xF}]
}
if {$_reset_reason ne "ERR"} {
    dict set ::CAPTURED boot_state reset_reason_raw [format "0x%08X" $_reset_reason]
}

# ---------------------------------------------------------------------------
say_h1 "4. Security State (research focus)"
# ---------------------------------------------------------------------------
say ""
say "These are the most security-research-relevant registers. Cross-reference"
say "decoded fields against UG1085 §10 (CSU) and UG1087 register descriptions."

# NOTE: Offsets verified 2026-05-26 against Xilinx u-boot-xlnx csu_regs
# struct (arch/arm/mach-zynqmp/include/mach/hardware.h). Prior versions of
# this script had INCORRECT offsets (0x4C/0x50/0x54) which were reading
# uncharacterized registers — findings interpretation was misleading.
# JTAG_SEC and JTAG_DAP_CFG are the security registers. Both had completely
# fabricated bit decodings in earlier versions of this script — the field
# names did not exist in the actual register. Now sourced from Xilinx QEMU.
#
# JTAG_SEC actual layout: three 3-bit fields (DAP_SEC, PLTAP_SEC, PMU_SEC).
# Each field uses a magic 3-bit unlock value, not single open/closed bits.
#
# JTAG_DAP_CFG actual layout: six 1-bit APU/RPU debug enables (NOT per-core).
# Older script invented per-core bits (APU0_DBG, APU0_SPIDEN, etc.) that
# do not exist in the hardware.
set _jtag_sec [safe_rd 0xFFCA0038]
dump_reg_qemu 0xFFCA0038
set _dap_cfg [safe_rd 0xFFCA003C]
dump_reg_qemu 0xFFCA003C
dump_reg_qemu 0xFFCA0034 "CSU.JTAG_CHAIN_STATUS"
dump_reg_qemu 0xFFCA0030 "CSU.JTAG_CHAIN_CFG"

# Security state interpretation is now in interpret.py rules. Raw register
# fields for JTAG_DAP_CFG, JTAG_SEC, etc. are already in ::CAPTURED via
# the dump_reg_qemu calls above.

say ""
say "**eFUSE secure boot policy** (LPD eFUSE controller at 0xFFCC0000):"
dump_reg_qemu 0xFFCC0008 "EFUSE.STATUS"
# Was: single-bit RSA_EN at bit 11, PPK0_INVLD [14:12], PPK1_INVLD [16:15].
# Correct per QEMU: RSA_EN is a 15-bit field [25:11] (Xilinx anti-glitch
# defense — a single bit flip can't enable RSA bypass, magic value required).
# PPK0_INVLD is [28:27], PPK1_INVLD is [31:30]. PPK0_WRLK at [26], PPK1_WRLK at [29].
dump_reg_qemu 0xFFCC1058 "EFUSE.SEC_CTRL"

say ""
say "**Boot-header scan** (operator-gated). The ZynqMP boot header is not"
say "memory-mapped in JTAG-idle; on a booted target or with QSPI in linear mode,"
say "point ::BH_ADDR at the boot-image base (e.g. -c {set ::BH_ADDR 0xC0000000})"
say "to capture encryptionKeySource (off 0x28) and fsblAttributes (off 0x44)."
say "Self-validated by the boot-header magic words (WIDTH_DETECTION 0xAA995566 at"
say "off 0x20, identification XLNX 0x584C4E58 at off 0x24) so a wrong address"
say "cannot yield a false reading — nothing is captured unless both magics match."
if {[info exists ::BH_ADDR]} {
    set _bh $::BH_ADDR
    set _bh_wdw [safe_rd [expr {$_bh + 0x20}]]
    set _bh_idw [safe_rd [expr {$_bh + 0x24}]]
    set _bh_valid 0
    if {$_bh_wdw ne "ERR" && $_bh_idw ne "ERR"} {
        if {[expr {$_bh_wdw == 0xAA995566}] && [expr {$_bh_idw == 0x584C4E58}]} {
            set _bh_valid 1
        }
    }
    if {$_bh_valid} {
        set _bh_eks [safe_rd [expr {$_bh + 0x28}]]
        set _bh_att [safe_rd [expr {$_bh + 0x44}]]
        capture_register [expr {$_bh + 0x20}] "WIDTH_DET"   "BOOTHDR" $_bh_wdw
        capture_register [expr {$_bh + 0x24}] "HEADER_ID"   "BOOTHDR" $_bh_idw
        capture_register [expr {$_bh + 0x28}] "ENC_KEY_SRC" "BOOTHDR" $_bh_eks
        if {$_bh_att ne "ERR"} {
            set _bh_auth_only [expr {($_bh_att >> 4) & 0x3}]
            set _bh_rsa       [expr {($_bh_att >> 14) & 0x3}]
            set _bh_fields [dict create]
            dict set _bh_fields AUTH_ONLY [dict create bits 5 value $_bh_auth_only]
            dict set _bh_fields BH_RSA    [dict create bits 15 value $_bh_rsa]
            capture_register [expr {$_bh + 0x44}] "FSBL_ATTR" "BOOTHDR" $_bh_att $_bh_fields
            say_kv "Boot header @ [hex32 $_bh]" "VALID (XLNX)  encryptionKeySource=$_bh_eks  fsblAttributes=$_bh_att (AUTH_ONLY=$_bh_auth_only BH_RSA=$_bh_rsa)"
        } else {
            say_kv "Boot header @ [hex32 $_bh]" "VALID (XLNX)  encryptionKeySource=$_bh_eks  fsblAttributes=READ FAILED"
        }
        # ---- Walk IHT -> PHT for per-partition encrypt/auth (PL bitstream) ----
        # imageHeaderByteOffset (0x98) -> IHT; partition headers are a linked list
        # (nextPartitionHeaderOffset, word *4) relative to the image base (::BH_ADDR).
        # Each PH is self-validated by its word-checksum (sum of 15 words ^0xFFFFFFFF)
        # before we trust its flags, so a walk into non-resident/garbage memory is
        # rejected, not reported. Capped at 32 partitions.
        set _iht_off [safe_rd [expr {$_bh + 0x98}]]
        if {$_iht_off ne "ERR" && $_iht_off > 0} {
            set _iht [expr {$_bh + $_iht_off}]
            set _pcount  [safe_rd [expr {$_iht + 0x04}]]
            set _firstph [safe_rd [expr {$_iht + 0x08}]]
            set _hdrac   [safe_rd [expr {$_iht + 0x10}]]
            if {$_pcount ne "ERR" && $_firstph ne "ERR"} {
                capture_register [expr {$_iht + 0x04}] "PART_COUNT" "PHT" $_pcount
                if {$_hdrac ne "ERR"} {
                    capture_register [expr {$_iht + 0x10}] "HDR_AC" "PHT" $_hdrac
                }
                set _cap $_pcount
                if {$_cap > 32} { set _cap 32 }
                set _ph [expr {$_bh + (4 * $_firstph)}]
                set _i 0
                while {$_i < $_cap} {
                    set _words [list]
                    set _ok 1
                    set _w 0
                    while {$_w < 16} {
                        set _v [safe_rd [expr {$_ph + (4 * $_w)}]]
                        if {$_v eq "ERR"} { set _ok 0; break }
                        lappend _words $_v
                        incr _w
                    }
                    if {$_ok == 0} {
                        say_kv "  PHT partition $_i" "read failed at [hex32 $_ph] — stopping walk"
                        break
                    }
                    set _sum 0
                    set _k 0
                    while {$_k < 15} {
                        set _sum [expr {($_sum + [lindex $_words $_k]) & 0xFFFFFFFF}]
                        incr _k
                    }
                    set _calc   [expr {$_sum ^ 0xFFFFFFFF}]
                    set _stored [expr {[lindex $_words 15] & 0xFFFFFFFF}]
                    if {$_calc != $_stored} {
                        say_kv "  PHT partition $_i" "checksum mismatch at [hex32 $_ph] — walked into non-PH data, stopping"
                        break
                    }
                    set _attr  [lindex $_words 9]
                    set _next  [lindex $_words 3]
                    set _acoff [lindex $_words 13]
                    set _pnum  [lindex $_words 14]
                    set _dest [expr {($_attr >> 4) & 0x7}]
                    set _enc  [expr {($_attr >> 7) & 0x1}]
                    set _acf  [expr {($_attr >> 15) & 0x1}]
                    set _pf [dict create]
                    dict set _pf DEST_DEVICE [dict create bits 6 value $_dest]
                    dict set _pf ENCRYPT     [dict create bits 7 value $_enc]
                    dict set _pf AC_FLAG     [dict create bits 15 value $_acf]
                    capture_register [expr {$_ph + 0x24}] "PART${_i}_ATTR"  "PHT" $_attr $_pf
                    capture_register [expr {$_ph + 0x34}] "PART${_i}_ACOFF" "PHT" $_acoff
                    capture_register [expr {$_ph + 0x38}] "PART${_i}_NUM"   "PHT" $_pnum
                    say_kv "  PHT partition $_i" "dest=$_dest encrypt=$_enc ac_flag=$_acf acOff=$_acoff (attr=[hex32 $_attr])"
                    if {$_next == 0} { break }
                    set _ph [expr {$_bh + (4 * $_next)}]
                    incr _i
                }
            } else {
                say_kv "  IHT @ [hex32 $_iht]" "read failed — partition walk skipped"
            }
        }
    } else {
        say_kv "Boot header @ [hex32 $_bh]" "no valid boot header (magic mismatch) — nothing captured"
    }
} else {
    say "  ::BH_ADDR not set — boot-header scan skipped (expected in JTAG-idle)."
}

say ""
say "**Additional eFUSE shadow registers** (per Xilinx xilskey defines):"
foreach {name addr} {
    "EFUSE.MISC_USER_CTRL"     0xFFCC1040
    "EFUSE.PUF_CHASH"          0xFFCC1050
    "EFUSE.PUF_MISC"           0xFFCC1054
    "EFUSE.SPK_ID"             0xFFCC105C
    "EFUSE.USER0"              0xFFCC1020
    "EFUSE.USER1"              0xFFCC1024
} {
    set v [safe_rd $addr]
    # Use if/else not ternary expr — `expr {... ? "0x10000000" : ...}` coerces
    # the hex string to decimal because expr's ternary forces numeric context.
    if {$v eq "ERR"} {
        say_kv "$name @ [hex32 $addr]" "BLOCKED"
    } else {
        say_kv "$name @ [hex32 $addr]" [hex32 $v]
    }
}

say ""
say "**eFUSE provisioning + programming locks** (all-zero/clear ⇒ unprovisioned dev"
say "silicon; non-zero ⇒ keys/fuses burned or programming locked on this part):"
# All decoded from the QEMU register model (no hand-authored bit fields).
dump_reg_qemu 0xFFCC0000   ;# EFUSE_CTRL.WR_LOCK / cfg lock
dump_reg_qemu 0xFFCC0030   ;# EFUSE ISR — programming-error / done flags
dump_reg_qemu 0xFFCC0044   ;# EFUSE PGM_LOCK — SPK-revoke / row programming lock
dump_reg_qemu 0xFFCC0048   ;# EFUSE AES_CRC — WRITE-to-verify reg (reads 0 regardless); key presence NOT passively readable

say ""
say "**CSU core + secure stream switch + boot integrity** (CSU state, SSS routing,"
say "multiboot/golden-image counter, fault-tolerance status):"
dump_reg_qemu 0xFFCA0000   ;# CSU_STATUS
dump_reg_qemu 0xFFCA0004   ;# CSU_CTRL
dump_reg_qemu 0xFFCA0008   ;# CSU_SSS_CFG — secure stream switch routing
dump_reg_qemu 0xFFCA0010   ;# CSU_MULTI_BOOT — boot-attempt / golden-image search counter
dump_reg_qemu 0xFFCA0018   ;# CSU_FT_STATUS — CSU triple-redundancy / SEU status

say ""
say "**Anti-tamper response policy** (TAMPER_STATUS + 13 TAMPER response-config regs:"
say "all-zero ⇒ no tamper sources armed; non-zero ⇒ an active tamper policy — sources"
say "wired to system reset / secure lockdown / key-zeroize on a hardened part):"
dump_reg_qemu 0xFFCA5000   ;# CSU TAMPER_STATUS (latched tamper events)
dump_reg_qemu 0xFFCA0014   ;# CSU_TAMPER_TRIG (manual tamper trigger)
foreach addr {
    0xFFCA5004 0xFFCA5008 0xFFCA500C 0xFFCA5010 0xFFCA5014 0xFFCA5018
    0xFFCA501C 0xFFCA5020 0xFFCA5024 0xFFCA5028 0xFFCA502C 0xFFCA5030 0xFFCA5034
} {
    dump_reg_qemu $addr     ;# CSU_TAMPER_0..12 — per-source tamper response config
}

say ""
say "**CSU AES engine key-presence** (STATUS key-zero bits: SET ⇒ that key slot is"
say "all-zero/unprovisioned; CLEAR ⇒ a real key is loaded — a strong provisioning tell):"
dump_reg_qemu 0xFFCA1000   ;# CSU AES_STATUS (KEY_INIT_DONE + per-slot *_ZERO bits)

say ""
say "**RSA root-of-trust (PPK0 / PPK1 SHA3 hashes, 12 words each)** — all-zero ⇒ no"
say "primary/secondary public-key hash provisioned (no RSA root of trust); any non-zero"
say "word ⇒ an RSA PPK is burned (pair with SEC_CTRL.RSA_EN to know if it is enforced):"
foreach addr {
    0xFFCC10A0 0xFFCC10A4 0xFFCC10A8 0xFFCC10AC 0xFFCC10B0 0xFFCC10B4
    0xFFCC10B8 0xFFCC10BC 0xFFCC10C0 0xFFCC10C4 0xFFCC10C8 0xFFCC10CC
} {
    dump_reg_qemu $addr     ;# EFUSE.PPK0_0..11
}
foreach addr {
    0xFFCC10D0 0xFFCC10D4 0xFFCC10D8 0xFFCC10DC 0xFFCC10E0 0xFFCC10E4
    0xFFCC10E8 0xFFCC10EC 0xFFCC10F0 0xFFCC10F4 0xFFCC10F8 0xFFCC10FC
} {
    dump_reg_qemu $addr     ;# EFUSE.PPK1_0..11
}

# EFUSE.SEC_CTRL interpretation is in interpret.py rules + annotations.
# Raw field values are already captured via dump_reg_qemu above.

# ---------------------------------------------------------------------------
say_h1 "5. Power State (PMU_GLOBAL)"
# ---------------------------------------------------------------------------
dump_reg_qemu 0xFFD80000 "PMU_GLOBAL.GLOBAL_CTRL"
# Was: FP[4], USB0[5], USB1[6], RPU[7], OCM_BANK_0[20], OCM_BANK_1[21],
# L2_BANK0[22], GEM0-3[24-27]. ALL WRONG. Correct per QEMU:
# ACPU0-3[3:0], PP0[4], PP1[5], L2_BANK0[7], R5_0/1[10:11], TCM[15:12],
# OCM_BANK0-3[19:16], USB0/1[21:20], FP[22], PL[23]. GEM bits don't exist.
dump_reg_qemu 0xFFD80100 "PMU_GLOBAL.PWR_STATE"
dump_reg_qemu 0xFFD80110 "PMU_GLOBAL.REQ_PWRUP_STATUS"
# Wrong address! Script had 0xFFD80118 (= REQ_PWRUP_INT_EN). Real
# REQ_PWRDWN_STATUS is at 0xFFD80210.
dump_reg_qemu 0xFFD80210 "PMU_GLOBAL.REQ_PWRDWN_STATUS"
dump_reg_qemu 0xFFD80530 "PMU_GLOBAL.ERROR_STATUS_1"
dump_reg_qemu 0xFFD80540 "PMU_GLOBAL.ERROR_STATUS_2"

# Power state interpretation is in interpret.py rules + annotations.
# PWR_STATE field values are already captured via dump_reg_qemu above.

# ---------------------------------------------------------------------------
say_h1 "6. Clocks: PLLs and Reference Clocks"
# ---------------------------------------------------------------------------

say_h2 "FPD PLLs (CRF_APB)"
# PLL CTRL register layout per QEMU: RESET=bit 0, BYPASS=bit 3, FBDIV=[14:8],
# DIV2=bit 16, CLKOUTDIV=bit 17, PRE_SRC=[22:20], POST_SRC=[26:24].
# Previous versions had BYPASS at bit 16, RESET at bit 17, and a fictitious
# "PRESRC" at bits [2:0] — none of those positions matched the hardware.
dump_reg_qemu 0xFD1A0020 "APLL_CTRL"
dump_reg_qemu 0xFD1A0024 "APLL_CFG"
dump_reg_qemu 0xFD1A002C "DPLL_CTRL"
dump_reg_qemu 0xFD1A0030 "DPLL_CFG"
dump_reg_qemu 0xFD1A0038 "VPLL_CTRL"
dump_reg_qemu 0xFD1A003C "VPLL_CFG"
dump_reg_qemu 0xFD1A0044 "PLL_STATUS (FPD)"

say_h2 "LPD PLLs (CRL_APB)"
dump_reg_qemu 0xFF5E0020 "IOPLL_CTRL"
dump_reg_qemu 0xFF5E0024 "IOPLL_CFG"
dump_reg_qemu 0xFF5E0030 "RPLL_CTRL"
dump_reg_qemu 0xFF5E0034 "RPLL_CFG"
dump_reg_qemu 0xFF5E0040 "PLL_STATUS (LPD)"

say_h2 "Per-peripheral reference clocks"
# Was: shared {SRCSEL,DIVISOR0,DIVISOR1,CLKACT@24} decode for all REF_CTRLs.
# That's correct for UART/SPI/I2C/USB/SDIO/QSPI but WRONG for GEM (whose
# CLKACT is bit 25, with extra RX_CLKACT at bit 26). Now per-register from
# QEMU to get each one right.
foreach addr {
    0xFF5E0074
    0xFF5E0078
    0xFF5E007C
    0xFF5E0080
    0xFF5E0120
    0xFF5E0124
    0xFF5E0060
    0xFF5E0064
    0xFF5E0050
    0xFF5E0054
    0xFF5E0058
    0xFF5E005C
    0xFF5E006C
    0xFF5E0070
    0xFF5E0068
    0xFF5E00AC
} {
    dump_reg_qemu $addr
}

say_h2 "FPD bus and APU clock"
# Was: CLKACT_HALF=24, CLKACT_FULL=25. CORRECTLY SWAPPED per QEMU:
# CLKACT_FULL=24, CLKACT_HALF=25. The script's "CLKACT=both" interpretation
# in findings was meaningful only because both bits were set.
dump_reg_qemu 0xFD1A0060 "CRF_APB.ACPU_CTRL"
# WRONG ADDRESSES below — script had 0x70, 0x78, 0x80. Correct per QEMU:
# DBG_TRACE_CTRL @ 0xFD1A0064, DBG_FPD_CTRL @ 0xFD1A0068, GDMA_REF_CTRL @ 0xFD1A00B8.
dump_reg_qemu 0xFD1A0064 "CRF_APB.DBG_TRACE_CTRL"
dump_reg_qemu 0xFD1A0068 "CRF_APB.DBG_FPD_CTRL"
dump_reg_qemu 0xFD1A00B8 "CRF_APB.GDMA_REF_CTRL"

# Clock interpretation (PLL lock state, ACPU source, peripheral REF_CTRLs)
# is in interpret.py rules + annotations. Raw fields are already captured.

# ---------------------------------------------------------------------------
say_h1 "7. Reset State"
# ---------------------------------------------------------------------------
dump_reg_qemu 0xFD1A0104 "CRF_APB.RST_FPD_APU"
dump_reg_qemu 0xFD1A0100 "CRF_APB.RST_FPD_TOP"
dump_reg_qemu 0xFD1A0108 "CRF_APB.RST_DDR_SS"
dump_reg_qemu 0xFF5E0230 "CRL_APB.RST_LPD_IOU0"
# RST_LPD_IOU1 @ 0xFF5E0234 is reserved per all Xilinx sources we have:
# QEMU defines 0x230 (IOU0) and 0x238 (IOU2) but explicitly skips 0x234;
# u-boot-xlnx hardware.h omits it; embeddedsw FSBL xfsbl_hw.h omits it.
# Reading reserved registers wastes JTAG cycles and risks AXI errors.
# Was: GPIO_RESET at bit 0 — actually QSPI_RESET. Real GPIO_RESET is at bit 18.
dump_reg_qemu 0xFF5E0238 "CRL_APB.RST_LPD_IOU2"
dump_reg_qemu 0xFF5E023C "CRL_APB.RST_LPD_TOP"

# Reset state interpretation is in interpret.py rules + annotations.
# Raw RST_FPD_APU, RST_LPD_IOU2, etc. fields are captured via dump_reg_qemu.

# ---------------------------------------------------------------------------
say_h1 "8. A53 Debug Gate + EDPCSR + Release (EL3)"
# ---------------------------------------------------------------------------
say ""
say "Two posture questions about the APU debug surface:"
say ""
say "1. **Is invasive debug (halt) open?** On a bare/idle board the open DAP can"
say "   halt the A53 at will. Once secure firmware (e.g. ATF/bl31) configures the"
say "   debug-authentication signals, the *same* DAP's halt request is refused — so"
say "   whether halt succeeds is a posture signal that depends on the running firmware."
say "2. **Is non-invasive PC sampling (EDPCSR) available?** The A53 debug block can"
say "   report a running core's PC via EDPCSR (DBGBASE+0xA0) WITHOUT halting; this"
say "   works even when invasive debug is gated, and reveals whether code is running."
say ""

# --- Phase A: non-invasive EDPCSR sweep of ALL 4 A53 cores (no state change).
# A wedged / running / gated core can be ANY core, so sample them all. This also
# detects whether firmware is executing; if so we must NOT apply the destructive
# release recipe (it overwrites OCM/RVBAR/RST and would crash a running OS).
say "**EDPCSR sweep — non-invasive PC sample of all 4 A53 cores:**"
say "\`\`\`"
set _core_pc  [dict create]
set _core_pin [dict create]
set _fw_running 0
set _first_live_pc "0xffffffff"
foreach _c {0 1 2 3} {
    set _ep  [edpcsr_probe $_c 4]
    set _pwr [dict get $_ep powered]
    set _ok  [dict get $_ep sampling_ok]
    set _pc  [dict get $_ep pc_lo]
    set _pr  [dict get $_ep edprsr]
    set _valid [list]
    foreach _s [dict get $_ep samples] {
        if {$_s ne "ERR" && $_s ne "0xffffffff"} { lappend _valid $_s }
    }
    # PC "pinned" = >=2 valid samples all identical → stalled on a non-completing
    # access (note: an idle core in WFI is also pinned — halt, below, tells them apart).
    set _pin 0
    if {[llength $_valid] >= 2} {
        set _pin 1
        set _f0 [lindex $_valid 0]
        foreach _s $_valid { if {$_s ne $_f0} { set _pin 0; break } }
    }
    dict set _core_pc  $_c $_pc
    dict set _core_pin $_c $_pin
    if {$_ok} {
        set _fw_running 1
        if {$_first_live_pc eq "0xffffffff"} { set _first_live_pc $_pc }
        if {$_pin} { set _pintxt "pinned" } else { set _pintxt "moving" }
        say [format "  core %d: PC=%s  EDPRSR=%s  powered=%s  (%s)" $_c $_pc [hex32 $_pr] $_pwr $_pintxt]
    } else {
        say [format "  core %d: PC=(no sample)  EDPRSR=%s  powered=%s" $_c [hex32 $_pr] $_pwr]
    }
}
say "\`\`\`"
say ""

# --- Phase B: release recipe — only if nothing is running (else don't disturb it).
if {$_fw_running} {
    say "_Detected a **running** A53 (live PC via EDPCSR) — skipping the release recipe so we"
    say "don't disturb the running firmware/OS._"
} else {
    say "**Releasing A53 core 0 from reset** (cores appear idle; idempotent):"
    safe_wr 0xFFFC0000 0x14000000               ;# safe landing 'b .'
    safe_wr 0xFD5C0040 0xFFFC0000               ;# RVBARADDR0L
    safe_wr 0xFD5C0044 0x00000000               ;# RVBARADDR0H
    set rst [safe_rd 0xFD1A0104]
    if {$rst ne "ERR"} {
        set rst_new [expr {$rst & ~((1 << 0) | (1 << 8) | (1 << 10))}]
        safe_wr 0xFD1A0104 $rst_new
    }
    catch { uscale.dap dpreg 0 0x1e } _
    sleep 50
}
say ""

# --- Phase C: halt-test sweep — classify invasive debug per core.
# open=halt enters debug; wedged=halt refused + PC pinned (stuck on a hung bus
# access); gated=halt refused + PC moving (firmware debug-auth); unreachable=core
# not examinable (off/in reset). On a live OS we RESUME any core we halt.
say "**Invasive debug (halt) per core:**"
say "\`\`\`"
set _summary [list]
set _core0_open 0
foreach _c {0 1 2 3} {
    set _inv "unreachable"
    if {![catch {uscale.a53.$_c arp_examine} _e]} {
        targets uscale.a53.$_c
        catch { halt } _
        sleep 80
        set _st [uscale.a53.$_c curstate]
        if {$_st eq "halted"} {
            set _inv "open"
            if {$_c == 0} { set _core0_open 1 }
            if {$_fw_running} { catch { resume } _ }   ;# don't leave a live OS paused
        } elseif {[dict get $_core_pin $_c]} {
            set _inv "wedged"
        } else {
            set _inv "gated"
        }
    }
    dict set ::CAPTURED a53 "core${_c}_invasive" $_inv
    dict set ::CAPTURED a53 "core${_c}_pc" [dict get $_core_pc $_c]
    if {[dict get $_core_pin $_c]} {
        dict set ::CAPTURED a53 "core${_c}_pinned" true
    } else {
        dict set ::CAPTURED a53 "core${_c}_pinned" false
    }
    if {$_inv eq "wedged"} {
        say [format "  core %d: %s  (PC pinned @ %s)" $_c $_inv [dict get $_core_pc $_c]]
    } else {
        say [format "  core %d: %s" $_c $_inv]
    }
    lappend _summary "c$_c=$_inv"
}
say "\`\`\`"

# Aggregate verdict: most-notable among examinable cores (wedged>gated>open);
# "unreachable" only if every core is unreachable (e.g. all in reset).
set _any_examinable 0
foreach _c {0 1 2 3} {
    if {[dict get $::CAPTURED a53 "core${_c}_invasive"] ne "unreachable"} { set _any_examinable 1 }
}
set _agg "unreachable"
if {$_any_examinable} {
    set _agg "open"
    foreach _c {0 1 2 3} {
        set _i [dict get $::CAPTURED a53 "core${_c}_invasive"]
        if {$_i eq "gated" && $_agg eq "open"} { set _agg "gated" }
        if {$_i eq "wedged"} { set _agg "wedged" }
    }
}

# Record summary keys for interpret.py.
if {$_fw_running} {
    dict set ::CAPTURED a53 release_attempted false
    dict set ::CAPTURED a53 firmware_running  true
    dict set ::CAPTURED a53 pc_sampling       true
} else {
    dict set ::CAPTURED a53 release_attempted true
    dict set ::CAPTURED a53 firmware_running  false
    dict set ::CAPTURED a53 pc_sampling       false
}
dict set ::CAPTURED a53 invasive_debug $_agg
dict set ::CAPTURED a53 cores_summary  [join $_summary " "]
dict set ::CAPTURED a53 live_pc        $_first_live_pc

say ""
say "**Aggregate invasive-debug verdict: $_agg** ([join $_summary { }])."
if {$_agg eq "open"} {
    say "The DAP can halt at least one A53 core — invasive debug is open (dev baseline)."
} elseif {$_agg eq "wedged"} {
    say "At least one core is **wedged** (stuck on a non-completing bus access): halt cannot"
    say "recover it, but EDPCSR read its frozen PC non-invasively — the one read primitive"
    say "that survives a wedge."
} elseif {$_agg eq "gated"} {
    say "At least one core refuses halt while still running — invasive debug gated by firmware."
}

# --- Phase D: register dump (idle-board case only — core 0 released + halted).
if {!$_fw_running && $_core0_open} {
    catch { targets uscale.a53.0 }
    catch { halt } _
    sleep 50
    say ""
    say "**Core 0 general-purpose / control registers (named, from OpenOCD cache):**"
    say "\`\`\`"
    foreach r {pc sp_el0 sp_el1 sp_el2 sp_el3 elr_el1 elr_el2 elr_el3 cpsr} {
        if {[catch {reg $r} v]} {
            say [format "  %-12s = (not available)" $r]
        } else {
            set v [string trim $v]
            regexp {0x[0-9a-fA-F]+} $v hexv
            if {[info exists hexv]} {
                say [format "  %-12s = %s" $r $hexv]
                if {$r eq "pc" || $r eq "cpsr"} { dict set ::CAPTURED a53 $r $hexv }
                unset hexv
            } else {
                say [format "  %-12s = %s" $r $v]
            }
        }
    }
    say "\`\`\`"
    say ""
    say "**ARM system registers** are deferred to a stage-2 payload approach — OpenOCD 0.12's"
    say "aarch64 target doesn't expose them as named cache registers."
}

# ---------------------------------------------------------------------------
say_h1 "9. Code Execution Discovery"
# ---------------------------------------------------------------------------
say ""
say "Probes OCM (and conditionally DDR) for boot-artifact signatures. Raw"
say "results are captured to JSON; interpret.py applies findings rules."

targets uscale.axi
clear_dp_sticky

# --- OCM probe: first word at known FSBL load addresses ---
foreach {label addr} {
    ocm_bank0_first 0xFFFC0000
    ocm_alt_first   0xFFFE0000
} {
    set _w [safe_read_block $addr 8]
    if {$_w ne "ERR"} {
        set _first [lindex $_w 0]
        dict set ::CAPTURED memory_probes $label \
            [dict create address [format "0x%08X" $addr] \
                        first_word [format "0x%08X" $_first]]
        say_kv "OCM @ [hex32 $addr]" \
            [format "first word = 0x%08X" $_first]
    } else {
        say_kv "OCM @ [hex32 $addr]" "ERR"
    }
}

# --- DDR signature scan, conditional on boot mode ---
set _boot_mode_now [safe_rd 0xFF5E0200]
set _is_jtag_idle [expr {$_boot_mode_now ne "ERR" && ($_boot_mode_now & 0xF) == 0}]

if {$_is_jtag_idle} {
    dict set ::CAPTURED memory_probes ddr_scan_skipped true
    dict set ::CAPTURED memory_probes ddr_scan_reason "boot_mode == JTAG_idle"
    say ""
    say "DDR scan SKIPPED — boot mode is JTAG idle; DDR controller not initialized."
} else {
    dict set ::CAPTURED memory_probes ddr_scan_skipped false
    set _ddr_probe [safe_rd 0x00000000]
    if {$_ddr_probe eq "ERR"} {
        say "DDR read at 0x0 failed — DDR not initialized."
        dict set ::CAPTURED memory_probes ddr_responsive false
    } else {
        dict set ::CAPTURED memory_probes ddr_responsive true
        # PetaLinux default load addresses + magic patterns
        set _signatures {
            {0x00080000   65536  "ARM\x64"            kernel_image_legacy}
            {0x00200000   65536  "ARM\x64"            kernel_image_modern}
            {0x00100000   8192   "\xD0\x0D\xFE\xED"   dtb_magic}
            {0x04000000   65536  "070701"             initramfs_cpio}
            {0x08000000   65536  "U-Boot"             uboot_proper}
            {0x08000000   65536  "Booting Linux"      uboot_kernel_banner}
        }
        foreach sig $_signatures {
            set _addr [lindex $sig 0]
            set _pat  [lindex $sig 2]
            set _name [lindex $sig 3]
            set _found [find_signature_string $_addr [lindex $sig 1] $_pat]
            if {$_found ne ""} {
                dict set ::CAPTURED memory_probes "ddr_${_name}" \
                    [format "0x%08X" $_found]
                say_kv "DDR $_name" [format "match at 0x%08X" $_found]
            }
        }
    }
}

# --- BootROM digest indicator ---
set _rom_digest [safe_rd 0xFFCA0050]    ;# CSU_ROM_DIGEST_0 (audit C1: was 0xFFCA0048 which is reserved)
if {$_rom_digest ne "ERR"} {
    dict set ::CAPTURED memory_probes csu_rom_digest_addr [hex32 $_rom_digest]
    say_kv "CSU_ROM_DIGEST_ADDR" [hex32 $_rom_digest]
}

# ---------------------------------------------------------------------------
say_h1 "10. CoreSight DAP Topology (per-AP enumeration)"
# ---------------------------------------------------------------------------
say ""
say "Walks every Access Port (AP) the DAP exposes, reads each AP's ID register"
say "to identify its type, and for MEM-APs walks the ROM table to enumerate"
say "every CoreSight component (DAP, ETM, ETB, CTI, ITM, DWT, etc.). ROM-table"
say "entries each carry a Component Class + Peripheral ID that identifies the"
say "block; OpenOCD's 'dap info N' command performs the full walk for us."
say ""
say "We capture the raw output verbatim for each AP rather than parse it —"
say "ROM-table layout is complex enough that re-parsing it in Tcl risks"
say "missing components. The verbatim text is structured enough for offline"
say "analysis (you can grep for component classes, base addresses, PIDs)."
say ""

# Capture dap info output for each of the 4 ZynqMP APs.
# Per UG1085 §39: AP0 = APU-DAP, AP1 = APB-AP, AP2 = AHB-AP (RPU), AP3 = JTAG-AP.
# 'capture' is the OpenOCD command that returns whatever a command wrote to log/stdout.
# Use double-quoted string so $_ap substitutes; capture then evaluates that string.
set ::_dap_info_text [dict create]
foreach _ap {0 1 2 3} {
    set _cmd "uscale.dap info $_ap"
    if {[catch { capture $_cmd } _txt]} {
        # Fallback for OpenOCD builds without 'capture' or where the AP errors.
        # Try calling directly (output goes to log only).
        if {[catch { eval $_cmd } _e]} {
            set _txt "ERR: $_e"
        } else {
            set _txt "(no capture available; see OpenOCD stdout above this report)"
        }
    }
    dict set ::_dap_info_text $_ap $_txt
    say ""
    say "## AP $_ap"
    say "\`\`\`"
    say $_txt
    say "\`\`\`"
}

# Store in ::CAPTURED for interpret.py.
if {[info exists ::CAPTURED]} {
    dict set ::CAPTURED coresight ap_info $::_dap_info_text
}

# ---------------------------------------------------------------------------
say_h1 "11. ZynqMP Memory Map Reference"
# ---------------------------------------------------------------------------
say ""
say "Quick reference for where things live on the ZynqMP SoC. These addresses"
say "are SoC-level (identical across ZCU10x / Ultra96 / RFSoC / custom"
say "ZynqMP boards). The Memory Map Probe below uses these addresses to"
say "actually verify access."
say ""

# Memory map as a markdown table to the report and a vertical list to terminal.
# Built from authoritative Xilinx sources: u-boot-xlnx hardware.h, FSBL hw.h,
# xilskey eFUSE defines.
set _memmap [list \
    [list "0x00000000 - 0x7FFFFFFF" "DDR (lower 2 GB)"          "Main system DRAM. Only accessible after DDR controller init by FSBL."] \
    [list "0xC0000000 - 0xFCFFFFFF" "PL aperture / PCIe"        "Programmable Logic and PCIe BARs. Empty if PL unconfigured."] \
    [list "0xFD000000 - 0xFD0FFFFF" "DDR controller"            "DDR controller registers @ 0xFD070000."] \
    [list "0xFD1A0000 - 0xFD1AFFFF" "CRF_APB"                   "Full-power domain Clock/Reset (APLL/DPLL/VPLL, RST_FPD_*)."] \
    [list "0xFD400000 - 0xFD4FFFFF" "SERDES"                    "Gigabit transceivers (PCIe/SATA/USB3/DisplayPort)."] \
    [list "0xFD5C0000 - 0xFD5CFFFF" "APU registers"             "RVBARADDR0-3 reset vectors at +0x40,48,50,58. APU power/reset."] \
    [list "0xFD610000 - 0xFD61FFFF" "FPD_SLCR"                  "Full-power domain System Level Control Registers."] \
    [list "0xFD800000 - 0xFD9FFFFF" "GPU (Mali-400)"            "Graphics processor registers."] \
    [list "0xFE000000 - 0xFE00FFFF" "GIC distributor"           "Generic Interrupt Controller (v2)."] \
    [list "0xFE100000 - 0xFE1FFFFF" "VCU (video codec)"         "Video Codec Unit registers."] \
    [list "0xFF000000 - 0xFF00FFFF" "PS UART0"                  "Main APU console UART."] \
    [list "0xFF010000 - 0xFF01FFFF" "PS UART1"                  "Secondary UART."] \
    [list "0xFF020000 - 0xFF02FFFF" "I2C0/1"                    "I2C controllers."] \
    [list "0xFF040000 - 0xFF06FFFF" "SPI0/1, CAN0/1"            "SPI and CAN controllers."] \
    [list "0xFF0A0000 - 0xFF0AFFFF" "GPIO"                      "MIO/EMIO GPIO controller."] \
    [list "0xFF0F0000 - 0xFF0FFFFF" "QSPI controller"           "Quad-SPI flash controller."] \
    [list "0xFF160000 - 0xFF17FFFF" "SDIO0/1"                   "SD/eMMC controllers."] \
    [list "0xFF180000 - 0xFF18FFFF" "IOU_SLCR"                  "MIO pin mux, tri-state, drive strength."] \
    [list "0xFF300000 - 0xFF33FFFF" "IPI (Inter-Proc Interrupt)" "PMU↔APU↔RPU communication."] \
    [list "0xFF410000 - 0xFF41FFFF" "LPD_SLCR"                  "Low-power domain System Level Control."] \
    [list "0xFF5E0000 - 0xFF5EFFFF" "CRL_APB"                   "Low-power domain Clock/Reset (IOPLL/RPLL, BOOT_MODE, RST_LPD_*, peripheral REF_CTRLs)."] \
    [list "0xFF9A0000 - 0xFF9AFFFF" "RPU configuration"         "Cortex-R5 cluster control."] \
    [list "0xFFC80000 - 0xFFCBFFFF" "CSUDMA + CSU"              "CSU at 0xFFCA0000 (security unit), CSU DMA at 0xFFC80000."] \
    [list "0xFFCC0000 - 0xFFCCFFFF" "eFUSE controller"          "eFUSE shadow registers at +0x1000 (DNA, SEC_CTRL, PPK hashes)."] \
    [list "0xFFCD0000 - 0xFFCDFFFF" "BBRAM"                     "Battery-Backed RAM — stores AES key when used."] \
    [list "0xFFCE0000 - 0xFFCEFFFF" "RSA core"                  "Hardware RSA-2048/4096 accelerator."] \
    [list "0xFFD80000 - 0xFFD8FFFF" "PMU_GLOBAL"                "PMU state, power/reset of every domain."] \
    [list "0xFFDC0000 - 0xFFDDFFFF" "PMU RAM (LMB)"             "Where PMU firmware runs. Triple-redundant MicroBlaze code."] \
    [list "0xFFE00000 - 0xFFE3FFFF" "RPU TCM"                   "Tightly-Coupled Memory for R5 cores (0xFFE00000=R5_0, 0xFFE20000=R5_1)."] \
    [list "0xFFFC0000 - 0xFFFFFFFF" "OCM (4×64 KB SRAM)"        "On-chip SRAM. Default FSBL/ATF load region. Always-on (LPD power)."] \
]

# Markdown table to report
global REPORT_FH
if {[info exists REPORT_FH]} {
    puts $REPORT_FH ""
    puts $REPORT_FH "| Address range | Block | Notes |"
    puts $REPORT_FH "|---|---|---|"
    foreach row $_memmap {
        puts $REPORT_FH "| `[lindex $row 0]` | [lindex $row 1] | [lindex $row 2] |"
    }
    puts $REPORT_FH ""
    flush $REPORT_FH
}

# Plain readable to terminal
echo ""
echo "  ┌─ ZynqMP memory map (always identical across boards) ─"
foreach row $_memmap {
    echo "  │ [lindex $row 0]  →  [lindex $row 1]"
    echo "  │     [lindex $row 2]"
}
echo "  └──"
echo ""

say ""
say "**Important register-level addresses** (subset of above with specific use):"
say ""
set _key_regs [list \
    [list "0xFFCA0040" "CSU.IDCODE"                "Silicon ID + part code"] \
    [list "0xFFCA0044" "CSU.VERSION"               "Silicon revision + PMU BootROM version"] \
    [list "0xFFCA0038" "CSU.JTAG_SEC"              "Secure JTAG gates"] \
    [list "0xFFCA003C" "CSU.JTAG_DAP_CFG"          "Per-core debug authorization"] \
    [list "0xFFCA0010" "CSU.MULTI_BOOT"            "Boot image search offset"] \
    [list "0xFFCC1058" "EFUSE.SEC_CTRL"            "Secure boot policy fuses"] \
    [list "0xFFCC100C" "EFUSE.DNA_0"               "Per-chip unique ID (low)"] \
    [list "0xFFD80100" "PMU_GLOBAL.PWR_STATE"      "Per-domain power state"] \
    [list "0xFD1A0044" "CRF_APB.PLL_STATUS"        "APLL/DPLL/VPLL lock status"] \
    [list "0xFF5E0040" "CRL_APB.PLL_STATUS"        "IOPLL/RPLL lock status"] \
    [list "0xFF5E0200" "CRL_APB.BOOT_MODE_USER"    "Boot mode pin readout"] \
    [list "0xFD1A0104" "CRF_APB.RST_FPD_APU"       "A53 core reset bits"] \
    [list "0xFD5C0040" "APU.RVBARADDR0L"           "A53 core 0 reset vector (low 32 bits)"] \
    [list "0xFD5C0044" "APU.RVBARADDR0H"           "A53 core 0 reset vector (high 32 bits)"] \
    [list "0xFFFC0000" "OCM Bank 0 start"          "Common FSBL load address"] \
    [list "0xFFFEA000" "OCM Bank 3 (ATF area)"     "ARM Trusted Firmware default load"] \
    [list "0x00080000" "DDR + 512 KB"              "Linux kernel Image (older PetaLinux)"] \
    [list "0x00100000" "DDR + 1 MB"                "Device tree (DTB) per PetaLinux default"] \
    [list "0x00200000" "DDR + 2 MB"                "Linux kernel Image (PetaLinux 2020.2+)"] \
    [list "0x04000000" "DDR + 64 MB"               "initramfs / rootfs.cpio (PetaLinux)"] \
    [list "0x08000000" "DDR + 128 MB"              "U-Boot proper (canonical load address)"] \
]
if {[info exists REPORT_FH]} {
    puts $REPORT_FH "| Address | Symbol | Use |"
    puts $REPORT_FH "|---|---|---|"
    foreach row $_key_regs {
        puts $REPORT_FH "| `[lindex $row 0]` | [lindex $row 1] | [lindex $row 2] |"
    }
    puts $REPORT_FH ""
}
echo "  ┌─ Key register and load addresses ─"
foreach row $_key_regs {
    echo "  │ [lindex $row 0]  →  [lindex $row 1]"
    echo "  │     [lindex $row 2]"
}
echo "  └──"
echo ""

# ---------------------------------------------------------------------------
say_h1 "12. Memory Map Probe"
# ---------------------------------------------------------------------------
targets uscale.axi
clear_dp_sticky
say ""
say "Reading representative addresses to see what's responsive at the AXI level."
say ""
say "## OCM (on-chip SRAM, 4 banks of 64 KB)"
dump_block "OCM Bank 0 start (0xFFFC0000)" 0xFFFC0000 8
dump_block "OCM Bank 0 mid"                0xFFFC8000 8
dump_block "OCM Bank 1 start"              0xFFFD0000 8
dump_block "OCM Bank 2 start"              0xFFFE0000 8
dump_block "OCM Bank 3 start"              0xFFFF0000 8
dump_block "BootROM region @ 0xFFFFC000 (CSU ROM may be mapped here)" 0xFFFFC000 8

clear_dp_sticky
say ""
say "## Known-accessible blocks (CSU, EFUSE, IOU_SLCR)"
say ""
say "_(Other peripheral bases like I2C0/SPI/GEM/SDIO/USB are held in reset per §7's"
say "RST_LPD_IOU2 dump. Probing them in JTAG idle causes AXI timeouts that wedge the_"
say "_DAP. Use a separate script to probe them after the relevant resets are cleared.)_"
say ""
foreach {name addr} {
    CSU            0xFFCA0000
    EFUSE          0xFFCC0000
    BBRAM          0xFFCD0000
    IOU_SLCR       0xFF180000
    CRL_APB        0xFF5E0000
    CRF_APB        0xFD1A0000
    PMU_GLOBAL     0xFFD80000
} {
    set v [safe_rd $addr]
    # if/else not ternary expr — ternary forces numeric context which
    # coerces hex-string returns from safe_rd to decimal. See §4 eFUSE loop.
    if {$v eq "ERR"} {
        say_kv "$name @ [hex32 $addr]" "ERR (DP sticky?)"
    } else {
        say_kv "$name @ [hex32 $addr]" [hex32 $v]
    }
    clear_dp_sticky
}

say ""
say "## Variant-specific blocks (informational — see §2 variant capabilities)"
say ""
if {$::VARIANT_PROFILE ne ""} {
    set _vp $::VARIANT_PROFILE
    say "Based on the variant lookup, this die's variant-conditional blocks:"
    say ""
    # Mali-400 GPU is at 0xFD4B0000 per linux-xlnx zynqmp.dtsi (gpu@fd4b0000)
    # — verified via the device tree, NOT probed in baseline because its
    # clock may be gated in JTAG-idle and a probe would risk AXI timeout.
    if {[dict get $_vp has_gpu]} {
        say_kv "Mali-400 GPU"  "expected @ 0xFD4B0000 (linux-xlnx zynqmp.dtsi). NOT probed in baseline — needs GPU clock enable first (deferred to deep-probe phase)."
    }
    # VCU on EV-bonded ZynqMP parts is accessed through the PL fabric; it
    # has no fixed PS-side base address. Without a PL bitstream loaded
    # configuring its AXI mapping, JTAG cannot reach it.
    if {[dict get $_vp may_have_vcu]} {
        say_kv "VCU (H.264/H.265)" "may be present on EV-bonded packages of this die. Accessed through PL fabric — no fixed PS-side base. Requires PL bitstream load to be probeable. Not probed in baseline."
    } else {
        say_kv "VCU (H.264/H.265)" "not present on this die (per variant table)."
    }
    # RFSoC RF tiles likewise require PL-side AXI mapping.
    if {[dict get $_vp has_rf]} {
        say_kv "RFSoC RF tiles" "present on this die (DR-package). Accessed through PL fabric — no fixed PS-side base. Requires PL bitstream load to be probeable. Not probed in baseline."
    }
    # GEM controllers — we have their REF_CTRL state from §6; cross-reference here.
    set _gemc [dict get $_vp gem_count]
    say_kv "GEM Ethernet controllers" "$_gemc expected per variant table. State already shown in §6 CRL_APB.GEM\[0-3\]_REF_CTRL dumps."
}

say ""
say "## DDR access (informational — DDR controller not initialized in JTAG idle)"
say ""
say "_(Skipped — reading uninitialized DDR causes AXI timeouts that wedge the DP._"
say "_Run with a DDR-initialized hardware platform to actually probe DDR.)_"

# ---------------------------------------------------------------------------
say_h1 "13. XPPU (Xilinx Peripheral Protection Unit)"
# ---------------------------------------------------------------------------
say ""
say "XPPU gates which AXI masters (APU, RPU, PMU, DMA engines, PL masters,"
say "etc.) can access which peripheral apertures in the LPD. On a properly"
say "hardened device it enforces hardware-level master/peripheral isolation;"
say "on a misconfigured device any master can talk to any peripheral. The"
say "LPD XPPU is at 0xFF980000 (UG1085 §16)."
say ""
say "Bit layouts sourced from Xilinx QEMU model (include/hw/misc/xlnx-xppu.h)."

clear_dp_sticky
targets uscale.axi

dump_reg_qemu 0xFF980000 "XPPU.CTRL"
dump_reg_qemu 0xFF980004 "XPPU.ERR_STATUS1"
dump_reg_qemu 0xFF980008 "XPPU.ERR_STATUS2"
dump_reg_qemu 0xFF98000C "XPPU.POISON"
dump_reg_qemu 0xFF980010 "XPPU.ISR"
dump_reg_qemu 0xFF980014 "XPPU.IMR"
dump_reg_qemu 0xFF98003C "XPPU.M_MASTER_IDS"
dump_reg_qemu 0xFF980044 "XPPU.M_APERTURE_64KB"
dump_reg_qemu 0xFF980048 "XPPU.M_APERTURE_1MB"
dump_reg_qemu 0xFF98004C "XPPU.M_APERTURE_512MB"
dump_reg_qemu 0xFF980054 "XPPU.BASE_64KB"
dump_reg_qemu 0xFF980058 "XPPU.BASE_1MB"
dump_reg_qemu 0xFF98005C "XPPU.BASE_512MB"

say ""
say "**Master ID slots** (first 8 of 20 — full set at 0xFF980100..0xFF98014C):"
foreach addr {0xFF980100 0xFF980104 0xFF980108 0xFF98010C
              0xFF980110 0xFF980114 0xFF980118 0xFF98011C} {
    set _v [safe_rd $addr]
    if {$_v ne "ERR" && $_v != 0} {
        # Non-zero master ID slot — decode the field
        set _mid   [expr {$_v & 0x3FF}]
        set _midm  [expr {($_v >> 16) & 0x3FF}]
        set _midr  [expr {($_v >> 30) & 1}]
        set _midp  [expr {($_v >> 31) & 1}]
        say_kv [format "MASTER_ID @ 0x%08X" $addr] \
            [format "raw=0x%08X (MID=0x%03X mask=0x%03X RO=%d parity=%d)" \
                    $_v $_mid $_midm $_midr $_midp]
    } else {
        # if/else not ternary expr — see §4 eFUSE loop comment.
        if {$_v eq "ERR"} {
            say_kv [format "MASTER_ID @ 0x%08X" $addr] "ERR"
        } else {
            say_kv [format "MASTER_ID @ 0x%08X" $addr] "unconfigured (0x00000000)"
        }
    }
}

# XPPU interpretation is in interpret.py rules + annotations.
# Raw XPPU.CTRL, ISR, ERR_STATUS1/2, M_MASTER_IDS already captured via dump_reg_qemu above.

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "14. RPU Configuration (Cortex-R5 cluster)"
# ---------------------------------------------------------------------------
say ""
say "RPU at 0xFF9A0000 controls the Cortex-R5 cluster: lockstep vs split"
say "mode, per-core configuration (vector base, halt state, coherency),"
say "and the per-core slave-port base addresses that determine where TCM"
say "is visible to other masters."
say ""
say "Bit layouts sourced from Xilinx QEMU model (xilinx_zynqmp_rpu_ctrl.c)."

# Cluster-wide controls
dump_reg_qemu 0xFF9A0000          ;# RPU.RPU_GLBL_CNTL
dump_reg_qemu 0xFF9A0004          ;# RPU.RPU_GLBL_STATUS
dump_reg_qemu 0xFF9A0008          ;# RPU.RPU_ERR_CNTL

# R5_0 per-core state
dump_reg_qemu 0xFF9A0100          ;# RPU.RPU_0_CFG
dump_reg_qemu 0xFF9A0104          ;# RPU.RPU_0_STATUS
dump_reg_qemu 0xFF9A0124          ;# RPU.RPU_0_SLV_BASE

# R5_1 per-core state (only meaningful when SLSPLIT=1; in lockstep mode
# R5_1 is clamped to R5_0 and these registers may read as default values).
dump_reg_qemu 0xFF9A0200          ;# RPU.RPU_1_CFG
dump_reg_qemu 0xFF9A0204          ;# RPU.RPU_1_STATUS
dump_reg_qemu 0xFF9A0224          ;# RPU.RPU_1_SLV_BASE

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "15. IPI (Inter-Processor Interrupt) — APU agent window"
# ---------------------------------------------------------------------------
say ""
say "IPI lets the four processor classes (APU, RPU, PMU, PL) signal each"
say "other via dedicated 1-bit channels per source/destination pair. Each"
say "agent has its own window — APU at 0xFF300000, RPU_0 at 0xFF310000,"
say "RPU_1 at 0xFF320000, PMU_0..3 at 0xFF330000..0xFF360000."
say ""
say "We read APU's window — reveals which agents have signaled APU and"
say "which the APU is masking/handling. The bit-per-agent layout in each"
say "register is the same: APU=\[0], RPU_0=\[8], RPU_1=\[9], PMU_0..3=\[16-19],"
say "PL_0..3=\[24-27]."
say ""
say "Bit layouts sourced from Xilinx QEMU model (xlnx-zynqmp-ipi.c)."

# APU's view of the IPI fabric
dump_reg_qemu 0xFF300000          ;# IPI.IPI_TRIG  — channels APU has triggered (write-1)
dump_reg_qemu 0xFF300004          ;# IPI.IPI_OBS   — pending channels visible to APU
dump_reg_qemu 0xFF300010          ;# IPI.IPI_ISR   — channels with latched interrupt at APU
dump_reg_qemu 0xFF300014          ;# IPI.IPI_IMR   — channels currently masked at APU

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "16. XMPU (Xilinx Memory Protection Unit) — selected instances"
# ---------------------------------------------------------------------------
say ""
say "XMPU gates which AXI masters can read/write which memory regions. It's"
say "the memory-range counterpart to XPPU (which gates peripheral apertures)."
say "ZynqMP has 8 XMPU instances per UG1085 section 16:"
say ""
say "- DDR_XMPU0..5: 0xFD000000, 0xFD010000, 0xFD020000, 0xFD030000,"
say "  0xFD040000, 0xFD050000 — one per DDR controller channel/partition"
say "- FPD_XMPU: 0xFD5D0000 — FPD master bus"
say "- OCM_XMPU: 0xFFA70000 — OCM (on-chip SRAM) protection"
say ""
say "Each instance has identical register layout — CTRL, ISR, IMR, IEN, IDS,"
say "LOCK, ECO at fixed offsets, plus 16 region descriptors (R00..R15) at"
say "0x100+. This section reads only CTRL/ISR/IMR/LOCK for the two most-"
say "confident instance bases (OCM_XMPU + DDR_XMPU0). Other instances skipped"
say "to avoid risk of DAP-wedging on unverified addresses; expand once"
say "u-boot-xlnx is cloned for authoritative XMPU base addresses."
say ""
say "Bit layouts sourced from Xilinx QEMU model (include/hw/misc/xlnx-xmpu.h)."

# --- OCM_XMPU ---
say ""
say "## OCM_XMPU (0xFFA70000) — protection for OCM SRAM banks"
dump_reg_qemu 0xFFA70000          ;# OCM_XMPU.CTRL
dump_reg_qemu 0xFFA70010          ;# OCM_XMPU.ISR
dump_reg_qemu 0xFFA70014          ;# OCM_XMPU.IMR
dump_reg_qemu 0xFFA70020          ;# OCM_XMPU.LOCK

clear_dp_sticky

# --- DDR_XMPU0 ---
say ""
say "## DDR_XMPU0 (0xFD000000) — protection for DDR controller channel 0"
dump_reg_qemu 0xFD000000          ;# DDR_XMPU0.CTRL
dump_reg_qemu 0xFD000010          ;# DDR_XMPU0.ISR
dump_reg_qemu 0xFD000014          ;# DDR_XMPU0.IMR
dump_reg_qemu 0xFD000020          ;# DDR_XMPU0.LOCK

clear_dp_sticky

# --- DDR_XMPU1..5 + FPD_XMPU (the rest of the DDR/FPD TrustZone enforcement;
#     addresses verified against the QEMU register model). CTRL+LOCK each is
#     enough for posture: CTRL bit0 = enable, LOCK = config frozen. ---
say ""
say "## DDR_XMPU1..5 + FPD_XMPU — remaining DDR/FPD TrustZone partitions"
say "(CTRL = enable + default-region permit; LOCK = region config frozen)"
foreach {base label} {
    0xFD010000 "DDR_XMPU1"
    0xFD020000 "DDR_XMPU2"
    0xFD030000 "DDR_XMPU3"
    0xFD040000 "DDR_XMPU4"
    0xFD050000 "DDR_XMPU5"
    0xFD5D0000 "FPD_XMPU"
} {
    dump_reg_qemu [expr {$base + 0x00}]   ;# <inst>.CTRL
    dump_reg_qemu [expr {$base + 0x20}]   ;# <inst>.LOCK
}

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "17. PL TAP + PCAP Configuration Status"
# ---------------------------------------------------------------------------
say ""
say "The PL (FPGA fabric) is configured via PCAP (Processor Configuration"
say "Access Port) by the PMU/CSU during boot, or via the PL JTAG TAP for"
say "external bitstream loading. PCAP_STATUS at 0xFFCA3010 reveals the PL's"
say "current configuration state: is a bitstream loaded (PL_DONE), did"
say "end-of-startup finish (PL_EOS), is the fabric in init (PL_INIT),"
say "PL housekeeping signals (PCFG_GWE / PL_GHIGH_B / PL_GTS_*), and tamper-"
say "related SEU error status."
say ""
say "We also read PCAP_CTRL (whether PCAP is the active config interface"
say "vs ICAP), PCAP_PROG (PROG_B pin state — clears PL config when low),"
say "PCAP_RDWR (read vs write direction), and PCAP_RESET (PCAP block reset)."
say ""
say "Bit layouts sourced from Xilinx QEMU model (csu_core.c)."

# PCAP block — all CSU-relative at 0xFFCA3000+
dump_reg_qemu 0xFFCA3000          ;# CSU.PCAP_PROG
dump_reg_qemu 0xFFCA3004          ;# CSU.PCAP_RDWR
dump_reg_qemu 0xFFCA3008          ;# CSU.PCAP_CTRL
dump_reg_qemu 0xFFCA300C          ;# CSU.PCAP_RESET
dump_reg_qemu 0xFFCA3010          ;# CSU.PCAP_STATUS

# The PL TAP itself is enumerated via JTAG chain info (§1) and CSU.JTAG_*
# (§4) — there are no SoC-side AXI registers for the PL TAP per se beyond
# what the secure-stream-switch (SSS) exposes. The actual bitstream IDCODE
# / fuse-state / configuration register access happens through the PL TAP
# in JTAG-side ops, not memory-mapped. Documented here for clarity.

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "18. SLCR Security Controls (LPD / FPD / IOU_SECURE / LPD_SECURE)"
# ---------------------------------------------------------------------------
say ""
say "ZynqMP doesn't have a classical WPROT lock register the way Zynq-7000"
say "did. SLCR security state is split across:"
say ""
say "- LPD_SLCR (0xFF410000) / FPD_SLCR (0xFD610000): CTRL.SLVERR_ENABLE"
say "  (do bad register accesses raise AXI SLVERR or silently complete?)"
say "  + ISR.ADDR_DECODE_ERR (latched bad-access count) + IMR mask + WPROT0"
say "- IOU_SECURE_SLCR (0xFF240000): per-peripheral AXI AWPROT/ARPROT —"
say "  determines whether GEM0..3 and SD0/1 emit secure or non-secure AXI"
say "  traffic. Bad value here makes peripheral DMA fail at XPPU/XMPU."
say "- LPD_SLCR_SECURE (0xFF4B0000): TrustZone gating for USB controllers."
say ""
say "Register layouts hand-verified from Xilinx PMU-FW headers (lpd_slcr.h,"
say "iou_secure_slcr.h, lpd_slcr_secure.h) plus UG1085 §36 for FPD_SLCR."
say ""

# --- LPD_SLCR ---
say_h2 "LPD_SLCR (0xFF410000)"
dump_reg_qemu 0xFF410000          ;# LPD_SLCR.WPROT0
dump_reg_qemu 0xFF410004          ;# LPD_SLCR.CTRL
dump_reg_qemu 0xFF410008          ;# LPD_SLCR.ISR
dump_reg_qemu 0xFF41000C          ;# LPD_SLCR.IMR

clear_dp_sticky

# --- FPD_SLCR ---
say ""
say_h2 "FPD_SLCR (0xFD610000)"
dump_reg_qemu 0xFD610000          ;# FPD_SLCR.WPROT0
dump_reg_qemu 0xFD610004          ;# FPD_SLCR.CTRL
dump_reg_qemu 0xFD610008          ;# FPD_SLCR.ISR
dump_reg_qemu 0xFD61000C          ;# FPD_SLCR.IMR

clear_dp_sticky

# --- IOU_SECURE_SLCR (per-peripheral AXI protection) ---
say ""
say_h2 "IOU_SECURE_SLCR (0xFF240000) — per-peripheral AXI protection"
dump_reg_qemu 0xFF240000          ;# IOU_SECURE_SLCR.IOU_AXI_WPRTCN
dump_reg_qemu 0xFF240004          ;# IOU_SECURE_SLCR.IOU_AXI_RPRTCN

clear_dp_sticky

# --- LPD_SLCR_SECURE (USB TrustZone gates) ---
say ""
say_h2 "LPD_SLCR_SECURE (0xFF4B0000) — USB TrustZone gating"
dump_reg_qemu 0xFF4B0034          ;# LPD_SLCR_SECURE.SLCR_USB

clear_dp_sticky

# ---------------------------------------------------------------------------
say_h1 "Cleanup: re-assert A53 reset for next run"
# ---------------------------------------------------------------------------
say ""
say "Re-asserting ACPU0_RESET (bit 0) and ACPU0_PWRON_RESET (bit 10) and"
say "APU_L2_RESET (bit 8) of RST_FPD_APU. This puts A53 core 0 back in reset"
say "so the next run of this script doesn't hit the DAP-wedge issue."
say ""

# Deeper recovery sequence for cleanup: jtag arp_init + multiple sticky clears.
catch { jtag arp_init } _
after 50
clear_dp_sticky
catch { uscale.axi arp_examine } _
targets uscale.axi
clear_dp_sticky

if {[info exists _fw_running] && $_fw_running} {
    say ""
    say "_Firmware is running on the A53 (live PC via EDPCSR in §8) — **skipping the"
    say "reset re-assert** so we don't crash the running OS. Power-cycle to return to idle._"
} else {
    set rst [safe_rd 0xFD1A0104]
    if {$rst ne "ERR"} {
        set rst_assert [expr {$rst | (1 << 0) | (1 << 8) | (1 << 10)}]
        safe_wr 0xFD1A0104 $rst_assert
        clear_dp_sticky
        set verify [safe_rd 0xFD1A0104]
        say_kv "RST_FPD_APU before" [hex32 $rst]
        say_kv "RST_FPD_APU after"  [hex32 $verify]
        if {$verify ne "ERR" && [expr {$verify & 0x1}] == 1} {
            say ""
            say "_(A53 core 0 is now back in reset. Re-run of this script will start clean.)_"
        } else {
            say ""
            say "_(Reset write may not have taken; subsequent run might need power-cycle.)_"
        }
    } else {
        say ""
        say "WARNING: RST_FPD_APU unreadable. **Next run will need a power-cycle.**"
        say "(This happens if the DP was wedged before cleanup ran.)"
    }
}

# ---------------------------------------------------------------------------
say_h1 "Done"
# ---------------------------------------------------------------------------
say ""
say "Report saved to: \`$REPORT_PATH\`"
say "Raw JSON capture: \`$RAW_PATH\`"

# Write the structured JSON capture. The interpret.py tool reads this and
# combines it with annotations (docs/annotations/zynqmp-security.yaml) and
# findings rules (docs/findings/zynqmp.yaml) to produce richer markdown.
if {[catch {capture_write_json $RAW_PATH} err]} {
    say ""
    say "_(WARNING: JSON capture write failed: $err)_"
} else {
    echo ""
    echo "=== JSON capture written: $RAW_PATH ==="
}

close $REPORT_FH
echo ""
echo "=== Enumeration complete. ==="
echo "    Markdown report: $REPORT_PATH"
echo "    Raw JSON:        $RAW_PATH"
echo ""
echo "To produce richer findings from the raw capture:"
echo "    python3 tools/interpret.py $RAW_PATH"
exit
