# dump-bootrom.tcl — CSU BootROM extraction, four methods in one script.
#
# By default runs all four methods in least-invasive-first order and writes
# per-method artifacts to dumps/. To run a single method (debugging or retry),
# set ::BOOTROM_METHOD before sourcing:
#
#   openocd -f openocd/zcu102.cfg \
#       -c "init; set ::BOOTROM_METHOD csudma; source openocd/dump-bootrom.tcl; shutdown"
#
# Valid method names: baseline, csudma, a53, loader, r5, aes, all (default).
#
# ---------------------------------------------------------------------------
# The four methods
# ---------------------------------------------------------------------------
#
# baseline — JTAG mem-AP direct read of 0xFFFFC000..0xFFFFFFFF.
#            No A53 release, no DMA programming. Whatever the AXI mem-AP
#            sees from the JTAG-DAP side is what you get. Also captures:
#              - CSU.CSU_ROM_DIGEST_0..11 (vendor-measured BootROM hash)
#              - CSU + EFUSE security state (CTRL, TAMPER, SEC_CTRL)
#              - Adjacent-region survey (is the gating BootROM-specific
#                or wider?)
#
# csudma   — Programs CSU DMA loopback (SSS DMA_SSS=5) to copy 0xFFFFC000
#            -> 0xFFFE0000 inside the CSU, then JTAG-reads the OCM
#            destination. Most likely of the four to actually retrieve
#            bytes because the CSU is the entity that originally has
#            BootROM access. Retries once on transient timeout.
#
# a53      — Releases A53 core 0, loads payloads/bootrom-dump.bin to
#            OCM at 0xFFFC0100, sets A53 PC there, resumes, halts,
#            reads dump destination. Polls the completion marker
#            (not a blind sleep) and captures ESR/FAR/ELR_EL3 on abort.
#
# loader   — Same as a53 but uses payloads/bootrom-dump-clean.bin which
#            clears SCTLR_EL3.C (D-cache off). Payload snapshots
#            SCTLR_EL3 before/after so we can verify the disable was
#            honored.
#
# ---------------------------------------------------------------------------
# Output files (per method, written to dumps/)
# ---------------------------------------------------------------------------
#
#   dumps/bootrom-<method>-<ts>.bin        16 KB raw little-endian dump
#   dumps/bootrom-<method>-<ts>.json       sidecar metadata
#   dumps/dump-bootrom-<ts>.log            full stdout transcript
#
# For the baseline method, prefix is bare "bootrom" (no -<method> suffix)
# to preserve compatibility with existing analyze tooling that picks up
# bootrom-<ts>.bin as the canonical "first try" capture.
#
# After all methods run, the script attempts to shell out to
# tools/bootrom.py to render reports/bootrom-summary-<ts>.md.


# ---------------------------------------------------------------------------
# Setup — script directory, timestamps, dirs, log file
# ---------------------------------------------------------------------------

set _script_dir [file dirname [info script]]
set _repo_root  [file normalize [file join $_script_dir ..]]

set _ts [clock format [clock seconds] -format "%Y-%m-%d-%H%M%S"]
if {[info exists ::TS_OVERRIDE]} { set _ts $::TS_OVERRIDE }

set _dumps_dir "dumps"
if {[info exists ::DUMPS_DIR_OVERRIDE]} { set _dumps_dir $::DUMPS_DIR_OVERRIDE }
file mkdir $_dumps_dir

set _which "all"
if {[info exists ::BOOTROM_METHOD]} { set _which $::BOOTROM_METHOD }

# Optional log capture of all `say` output (O4).
set _log_path "$_dumps_dir/dump-bootrom-$_ts.log"
if {![info exists ::REPORT_FH] || $::REPORT_FH eq ""} {
    set ::REPORT_FH [open $_log_path w]
}

source [file join $_script_dir lib enum-helpers.tcl]
source [file join $_script_dir lib dump-memory.tcl]
source [file join $_script_dir lib release-recipes.tcl]
source [file join $_script_dir lib board-baselines.tcl]


# ---------------------------------------------------------------------------
# Named register constants (Q1)
#
# Authoritative offsets per Xilinx embeddedsw lib/sw_apps/zynqmp_pmufw/src/csu.h
# and arch/arm/include/asm/arch-zynqmp/hardware.h (u-boot). All previously
# inlined as magic numbers — hoisting surfaces register-address mistakes by
# making them grep-able and reviewable in one place. (Originally written as
# 0xFFCA0048; corrected to 0xFFCA0050 after live data showed two leading
# zero "digest" words that were actually reserved registers.)
# ---------------------------------------------------------------------------

# CSU control block @ 0xFFCA0000
set ::REG_CSU_STATUS            0xFFCA0000
set ::REG_CSU_CTRL              0xFFCA0004
set ::REG_CSU_SSS_CFG           0xFFCA0008
set ::REG_CSU_DMA_RESET         0xFFCA000C
set ::REG_CSU_MULTI_BOOT        0xFFCA0010
set ::REG_CSU_TAMPER_TRIG       0xFFCA0014
set ::REG_CSU_TAMPER_STATUS     0xFFCA5000   ;# was wrong: 0xFFCA005C is CSU_ROM_DIGEST_3 ;# verify-addresses:skip
set ::REG_CSU_JTAG_CHAIN_STATUS 0xFFCA0034
set ::REG_CSU_JTAG_SEC          0xFFCA0038   ;# fixed audit C1 (no longer swapped with DAP_CFG)
set ::REG_CSU_JTAG_DAP_CFG      0xFFCA003C   ;# fixed audit C1 ;# verify-addresses:skip
set ::REG_CSU_ROM_DIGEST_0      0xFFCA0050   ;# 12 × 32-bit words
set ::REG_CSU_ROM_DIGEST_COUNT  12

# CSU DMA channels (separate AXI window from the CSU control block)
set ::REG_CSU_DMA_SRC_BASE      0xFFC80000
set ::REG_CSU_DMA_DST_BASE      0xFFC80800
# Per-channel offsets inside SRC or DST window:
set ::OFF_DMA_ADDR    0x000   ;# source/dest address
set ::OFF_DMA_SIZE    0x004   ;# size bytes | LAST_WORD bit
set ::OFF_DMA_STS     0x008   ;# status (bit 0 = BUSY)
set ::OFF_DMA_CTRL    0x00C
set ::OFF_DMA_CRC     0x010
set ::OFF_DMA_I_STS   0x014   ;# interrupt status (8 bits per xcsudma_hw.h)
set ::OFF_DMA_I_EN    0x018
set ::OFF_DMA_I_DIS   0x01C
set ::OFF_DMA_I_MASK  0x020
set ::OFF_DMA_CTRL2   0x028

# CRF_APB - A53 reset
set ::REG_RST_FPD_APU           0xFD1A0104
set ::BIT_RST_ACPU0_RESET       0   ;# bit 0
set ::BIT_RST_ACPU0_PWRON_RESET 8   ;# bit 8
set ::BIT_RST_APU_L2_RESET      10  ;# bit 10  (active-low? actually combined L2/SoC reset)

# APU - reset vector
set ::REG_APU_RVBAR_L_0         0xFD5C0040
set ::REG_APU_RVBAR_H_0         0xFD5C0044

# EFUSE - security control
set ::REG_EFUSE_SEC_CTRL        0xFFCC1058

# BootROM region + A53 payload layout
set ::ADDR_BOOTROM              0xFFFFC000
set ::ADDR_BOOTROM_SIZE         0x4000        ;# 16 KB
set ::ADDR_SAFE_LANDING         0xFFFC0000    ;# "b ." landing pad
set ::ADDR_PAYLOAD              0xFFFC0100
set ::ADDR_DUMP_DST             0xFFFE0000
set ::ADDR_DONE_MARKER          0xFFFE7000
set ::ADDR_SCTLR_BEFORE         0xFFFE7010    ;# M2 payload writes here
set ::ADDR_SCTLR_AFTER          0xFFFE7018    ;# M2 payload writes here
set ::ADDR_ESR_EL3_SAVE         0xFFFE7030    ;# M1+M2 payloads write here
set ::ADDR_FAR_EL3_SAVE         0xFFFE7038
set ::ADDR_ELR_EL3_SAVE         0xFFFE7040
set ::ADDR_SPSR_EL3_SAVE        0xFFFE7048
set ::ADDR_STAGE_START          0xFFFE7080    ;# M2 stage-0 marker (pre-MRS) - MUST match payloads/bootrom-dump-clean.S STAGE_START_ADDR
set ::STAGE_START_VAL           0xC0DEBA5E    ;# expected stage-0 value - MUST match payloads/bootrom-dump-clean.S STAGE_START_VAL
set ::DONE_MARKER_LO            0x0000C0DE
set ::DONE_MARKER_HI            0xCAFEBABE


# ---------------------------------------------------------------------------
# File-scope helpers
# ---------------------------------------------------------------------------

# Decode CSU DMA interrupt status register (per Xilinx xcsudma_hw.h).
proc _decode_dma_intr {v} {
    set names {
        INVALID_APB TIMEOUT_MEM TIMEOUT_STRM AXI_BRESP_ERR
        FIFO_OVERFLOW INVALID_APB_RD THRESH_HIT MEM_DONE
    }
    set out {}
    for {set i 0} {$i < 8} {incr i} {
        if {$v & (1 << $i)} { lappend out [lindex $names $i] }
    }
    if {[llength $out] == 0} { return "(none)" }
    return [join $out ","]
}

# Convert a `safe_rd`-style return ("0x..." hex string OR "ERR") to a Tcl
# integer. Returns the supplied default if conversion fails. Replaces the
# pattern:
#     set foo_i 0
#     catch { set foo_i [expr {int($foo)}] }
# that recurs 40+ times in this file. Use as:
#     set foo_i [_safe_int $foo]
proc _safe_int {val {default 0}} {
    if {$val eq "ERR"} { return $default }
    if {[catch {expr {int($val)}} result]} { return $default }
    return $result
}


# Decode SCTLR_EL3 bits we care about for the "did D-cache disable take?" check.
proc _decode_sctlr_el3 {v} {
    set m [expr {$v & 1}]
    set c [expr {($v >> 2) & 1}]
    set i [expr {($v >> 12) & 1}]
    return "M=$m C=$c I=$i"
}

# Warn if payload .bin is older than its .S source (R1).
# Uses `file rootname` so we don't assume the extension is exactly ".bin"
# (the prior `string range end-4` silently constructs wrong paths if a
# caller ever passes e.g. .elf or a name without extension).
proc _check_payload_staleness {payload_bin} {
    set s_path "[file rootname $payload_bin].S"
    if {![file exists $s_path]} { return }
    if {[file mtime $s_path] > [file mtime $payload_bin]} {
        say "  WARN: $payload_bin is OLDER than $s_path"
        say "        Source has been edited but binary not rebuilt - results may be wrong."
        say "        Run: cd payloads && make"
    }
}

# Read N words from a CSU DMA channel base+offset.
proc _dma_rd {ch off} {
    return [safe_rd [expr {$ch + $off}]]
}
proc _dma_wr {ch off val} {
    safe_wr [expr {$ch + $off}] $val
}

# Snapshot a small set of CSU security registers (H3 / O3).
# Returns a Tcl dict keyed by short name.
proc _snapshot_csu_security {} {
    set keys {
        csu_status         REG_CSU_STATUS
        csu_ctrl           REG_CSU_CTRL
        csu_sss_cfg        REG_CSU_SSS_CFG
        csu_tamper_trig    REG_CSU_TAMPER_TRIG
        csu_tamper_status  REG_CSU_TAMPER_STATUS
        csu_jtag_chain_sts REG_CSU_JTAG_CHAIN_STATUS
        csu_jtag_dap_cfg   REG_CSU_JTAG_DAP_CFG
        csu_jtag_sec       REG_CSU_JTAG_SEC
        efuse_sec_ctrl     REG_EFUSE_SEC_CTRL
    }
    set out [dict create]
    foreach {name var} $keys {
        set v [safe_rd [set ::$var]]
        if {$v eq "ERR"} {
            dict set out $name "READ_FAILED"
        } else {
            dict set out $name [format "0x%08X" [expr {int($v)}]]
        }
    }
    return $out
}

# Probe N bytes at each waypoint and classify result (H4).
# Returns dict: addr -> {status hex_first_word}
proc _adjacent_region_survey {waypoints} {
    set out [list]
    foreach {addr label} $waypoints {
        clear_dp_sticky
        set v [safe_rd $addr]
        if {$v eq "ERR"} {
            lappend out [dict create \
                addr [format "0x%08X" $addr] \
                label $label \
                status "READ_FAILED" \
                first_word "ERR"]
        } else {
            set vi [expr {int($v)}]
            set status "ok"
            if {$vi == 0xDEADBEEF} {
                set status "DEADBEEF (AXI-gated or unmapped)"
            } elseif {$vi == 0} {
                set status "0x00000000 (uninit or zero data)"
            }
            lappend out [dict create \
                addr [format "0x%08X" $addr] \
                label $label \
                status $status \
                first_word [format "0x%08X" $vi]]
        }
    }
    return $out
}

# Format an elapsed millisecond count for log lines.
proc _fmt_ms {ms} {
    if {$ms < 1000} { return "${ms} ms" }
    return [format "%.2f s" [expr {$ms / 1000.0}]]
}

# Format a value that may be "ERR" (from safe_rd) as a hex32 string. If the
# value is "ERR", returns "0xDEADBEEF" as a sentinel (matches the convention
# the AXI mem-AP uses for failed reads). Avoids the `expr { ... ? hex : int($s) }`
# coercion footgun (see feedback_tcl_ternary_hex_coercion).
proc _safe_hex32 {val} {
    if {$val eq "ERR"} { return "0xDEADBEEF" }
    return [format "0x%08X" [expr {int($val)}]]
}

# Zero the A53-payload OCM marker region — done marker (8B), SCTLR
# snapshot pair (16B), four EL3 sysreg slots (32B), stage-0 marker (8B).
# Two 32-bit zero writes per 64-bit slot. Centralized so the address
# list stays in one place (TCL constants are the source of truth; the
# .S files must match).
proc _zero_a53_marker_region {} {
    foreach addr [list \
            $::ADDR_DONE_MARKER     [expr {$::ADDR_DONE_MARKER + 4}] \
            $::ADDR_SCTLR_BEFORE    [expr {$::ADDR_SCTLR_BEFORE + 4}] \
            $::ADDR_SCTLR_AFTER     [expr {$::ADDR_SCTLR_AFTER + 4}] \
            $::ADDR_ESR_EL3_SAVE    [expr {$::ADDR_ESR_EL3_SAVE + 4}] \
            $::ADDR_FAR_EL3_SAVE    [expr {$::ADDR_FAR_EL3_SAVE + 4}] \
            $::ADDR_ELR_EL3_SAVE    [expr {$::ADDR_ELR_EL3_SAVE + 4}] \
            $::ADDR_SPSR_EL3_SAVE   [expr {$::ADDR_SPSR_EL3_SAVE + 4}] \
            $::ADDR_STAGE_START     [expr {$::ADDR_STAGE_START + 4}]] {
        safe_wr $addr 0
    }
}

# (C) Inter-method DAP recovery. Called at the start of every method to keep
# a wedge in one method from poisoning the next, and to recover from a
# session-start wedge where init's auto-examine failed. Steps escalate:
#   1. Clear DP sticky errors (5x)
#   2. Re-target uscale.axi, try a probe
#   3. If probe fails, try to re-examine uscale.axi (recovers from
#      "Target not examined yet" left by a botched init)
#   4. If still failing, halt examined targets + repeat probe
#   5. Final probe; return 1 if responsive, 0 if wedged beyond recovery
proc _inter_method_recovery {} {
    for {set i 0} {$i < 5} {incr i} {
        catch { uscale.dap dpreg 0 0x1e } _
        after 5
    }
    catch { targets uscale.axi } _
    set p [safe_rd $::REG_CSU_STATUS]
    if {$p ne "ERR"} { return 1 }

    # The most common cause of probe-fail at session start: init couldn't
    # examine uscale.axi because of a sticky error left by the previous run.
    # Re-examine the AXI target explicitly.
    say "  recovery: probe failed; re-examining uscale.axi"
    for {set i 0} {$i < 5} {incr i} {
        catch { uscale.dap dpreg 0 0x1e } _
        after 5
    }
    if {[catch {uscale.axi arp_examine} err] == 0} {
        say "  recovery: uscale.axi arp_examine ok"
        set p [safe_rd $::REG_CSU_STATUS]
        if {$p ne "ERR"} {
            say "  recovery: DAP back online after re-examine"
            return 1
        }
    } else {
        say "  recovery: uscale.axi arp_examine still failing ($err)"
    }

    # Last-resort escalation: force A53 back into reset (most common cause
    # of DAP wedge between methods is A53 stuck in a fault loop holding the
    # AXI bus). Then halt any examined A53 + retry.
    #
    # NOTE: the next method's release procedure sets RVBAR + clears RST
    # bits, so A53 PC IS effectively reset to the new RVBAR address — it's
    # not the case that "without PMU FW the A53 stays wherever it was."
    # The historical "RST_FPD_APU bits don't reset PC" claim was confused
    # with the symptoms of truncated payloads (see UTF-8 byte-count bug,
    # fixed 2026-05-28). Multi-release per power-cycle works fine now.
    # If DAP is still wedged after this escalation (rare), power-cycle is
    # the fix for true AXI deadlock from earlier in the run.
    say "  recovery: escalating - forcing A53 reset + halting examined targets"
    catch { reset_a53_core0 } _
    after 50
    foreach t {uscale.a53.0 uscale.a53.1 uscale.a53.2 uscale.a53.3} {
        if {[catch {$t was_examined} ex] == 0 && $ex} {
            catch { targets $t } _
            catch { halt } _
        }
    }
    catch { targets uscale.axi } _
    for {set i 0} {$i < 10} {incr i} {
        catch { uscale.dap dpreg 0 0x1e } _
        after 10
    }
    catch { uscale.axi arp_examine } _
    set p2 [safe_rd $::REG_CSU_STATUS]
    if {$p2 ne "ERR"} {
        say "  recovery: DAP back online after escalation"
        return 1
    }
    say "  recovery: DAP STILL wedged - this method's results will be unreliable"
    say "  HINT: power-cycle the board if every method shows READ_FAILED"
    return 0
}

# (D) Write a zeroed buffer to memory and verify by reading back one word.
# Returns 1 on success, 0 on failure. Logs failure so caller can record it.
proc _write_zero_verified {addr nbytes label} {
    set nwords [expr {$nbytes / 4}]
    set zw [list]
    for {set i 0} {$i < $nwords} {incr i} { lappend zw 0 }
    if {[catch {write_memory $addr 32 $zw} err]} {
        say "  WARN: pre-zero of $label at [hex32 $addr] FAILED ($err)"
        return 0
    }
    # Verify: read one word, check it's zero
    set rv [safe_rd $addr]
    if {$rv eq "ERR"} {
        say "  WARN: pre-zero of $label - couldn't read back to verify"
        return 0
    }
    if {[expr {int($rv) & 0xFFFFFFFF}] != 0} {
        say "  WARN: pre-zero of $label at [hex32 $addr] DID NOT TAKE EFFECT (readback = [hex32 $rv])"
        return 0
    }
    return 1
}

# (A) Force-halt the A53 core 0 with retries. Use before reading sysregs
# in the fault-syndrome path. Returns 1 if halted, 0 if A53 unreachable.
proc _force_halt_a53 {} {
    set last_err ""
    for {set attempt 1} {$attempt <= 3} {incr attempt} {
        # If target was de-examined by upstream recovery, curstate may
        # raise. Check was_examined first; re-examine before checking state.
        set examined 0
        catch { set examined [uscale.a53.0 was_examined] }
        if {!$examined} {
            catch { uscale.a53.0 arp_examine } last_err
            catch { uscale.dap dpreg 0 0x1e } _
            continue
        }
        catch { targets uscale.a53.0 } _
        catch { halt } _
        after 200
        set s "unknown"
        catch { set s [uscale.a53.0 curstate] }
        if {$s eq "halted"} { return 1 }
        catch { uscale.a53.0 arp_examine } last_err
        catch { uscale.dap dpreg 0 0x1e } _
    }
    if {$last_err ne ""} {
        say "  _force_halt_a53: A53 unreachable after 3 attempts (last err: $last_err)"
    }
    return 0
}


# ---------------------------------------------------------------------------
# Method: baseline (JTAG mem-AP direct read)
# ---------------------------------------------------------------------------
proc method_baseline {ts dumps_dir} {
    set bin "$dumps_dir/bootrom-$ts.bin"
    set meta "$dumps_dir/bootrom-$ts.json"
    set t_start [clock milliseconds]

    say ""
    say "============================================================"
    say "  Method 0: Baseline (JTAG mem-AP direct read)"
    say "============================================================"

    _inter_method_recovery

    # ---- Snapshot CSU + EFUSE security state (H3) ----
    say "  Snapshotting CSU + EFUSE security state ..."
    set sec [_snapshot_csu_security]
    dict for {k v} $sec {
        say [format "    %-22s = %s" $k $v]
    }

    # ---- Snapshot CSU_ROM_DIGEST_0..11 (B1: fixed base 0xFFCA0050) ----
    set digest_words [list]
    for {set i 0} {$i < $::REG_CSU_ROM_DIGEST_COUNT} {incr i} {
        set addr [expr {$::REG_CSU_ROM_DIGEST_0 + ($i * 4)}]
        set w [safe_rd $addr]
        if {$w eq "ERR"} {
            lappend digest_words "0xDEADBEEF"
        } else {
            lappend digest_words [format "0x%08X" [expr {int($w)}]]
        }
    }
    say "  Captured CSU.CSU_ROM_DIGEST_0..[expr {$::REG_CSU_ROM_DIGEST_COUNT - 1}] (vendor hash):"
    for {set i 0} {$i < $::REG_CSU_ROM_DIGEST_COUNT} {incr i} {
        say [format "    DIGEST_%-2d = %s" $i [lindex $digest_words $i]]
    }

    # ---- Adjacent-region survey (H4): how wide is the gating? ----
    say "  Adjacent-region survey (one-word probe at each waypoint) ..."
    set waypoints [list \
        0xFFFE0000 "OCM bank 2 (dump dest, should be readable)" \
        0xFFFC0000 "OCM bank 0 (payload area, should be readable)" \
        0xFFFB0000 "OCM bank 0 low (uninit OCM)" \
        0xFFFA0000 "FPD/OCM controller registers" \
        0xFFCA0000 "CSU control (CSU_STATUS)" \
        0xFFC80000 "CSU DMA SRC channel" \
        0xFFFE7000 "OCM done-marker location (post-payload)" \
        0xFFFFB000 "Region just below BootROM (4 KB earlier)" \
        $::ADDR_BOOTROM "BootROM start (subject of dump)" \
        0xFFFFD000 "BootROM + 4 KB" \
        0xFFFFE000 "BootROM + 8 KB" \
        0xFFFFF000 "BootROM + 12 KB" \
    ]
    set survey [_adjacent_region_survey $waypoints]
    foreach entry $survey {
        say [format "    %s  %s  %s  // %s" \
                [dict get $entry addr] \
                [dict get $entry first_word] \
                [dict get $entry status] \
                [dict get $entry label]]
    }

    # ---- The actual BootROM dump ----
    set result [dump_memory $::ADDR_BOOTROM $::ADDR_BOOTROM_SIZE 1024 $bin "CSU BootROM region"]

    # Flatten survey to JSON-friendly list of strings (one entry per waypoint).
    set survey_flat [list]
    foreach entry $survey {
        lappend survey_flat [format "%s|%s|%s|%s" \
            [dict get $entry addr] \
            [dict get $entry first_word] \
            [dict get $entry status] \
            [dict get $entry label]]
    }

    set t_total [expr {[clock milliseconds] - $t_start}]
    set m [dict create \
        schema_version 1 method "0-baseline" timestamp $ts \
        source_address "0xFFFFC000" \
        size_bytes     [dict get $result bytes_written] \
        chunks_total   [dict get $result chunks_total] \
        chunks_ok      [dict get $result chunks_ok] \
        chunks_failed  [dict get $result chunks_failed] \
        dump_total_ms  [dict get $result total_ms] \
        dump_max_chunk_ms [dict get $result max_chunk_ms] \
        method_total_ms $t_total \
        csu_rom_digest $digest_words \
        csu_status         [dict get $sec csu_status] \
        csu_ctrl           [dict get $sec csu_ctrl] \
        csu_sss_cfg        [dict get $sec csu_sss_cfg] \
        csu_tamper_trig    [dict get $sec csu_tamper_trig] \
        csu_tamper_status  [dict get $sec csu_tamper_status] \
        csu_jtag_chain_sts [dict get $sec csu_jtag_chain_sts] \
        csu_jtag_dap_cfg   [dict get $sec csu_jtag_dap_cfg] \
        csu_jtag_sec       [dict get $sec csu_jtag_sec] \
        efuse_sec_ctrl     [dict get $sec efuse_sec_ctrl] \
        adjacent_survey    $survey_flat \
        binary_path        $bin]
    # array_fields explicitly listed so multi-word survey entries don't get split
    write_dump_metadata $meta $m {csu_rom_digest adjacent_survey}
    say "  Method 0 wall-clock: [_fmt_ms $t_total]"
}


# ---------------------------------------------------------------------------
# Method: csudma (CSU DMA loopback copy)
# ---------------------------------------------------------------------------
proc _method_csudma_attempt {attempt_idx} {
    # Returns dict of attempt results. Caller decides whether to retry.
    set t0 [clock milliseconds]
    set SRC_CH $::REG_CSU_DMA_SRC_BASE
    set DST_CH $::REG_CSU_DMA_DST_BASE

    # 1. Soft-reset CSU DMA
    safe_wr $::REG_CSU_DMA_RESET 0x01; after 5
    safe_wr $::REG_CSU_DMA_RESET 0x00; after 5

    # 2. SSS routing: DMA_SSS bits 7-4 = 0x5 (DMA -> DMA loopback)
    set sss_orig [safe_rd $::REG_CSU_SSS_CFG]
    set sss_orig_i 0
    catch { set sss_orig_i [expr {int($sss_orig)}] }
    set sss_new [expr {($sss_orig_i & ~0xF0) | 0x50}]
    safe_wr $::REG_CSU_SSS_CFG $sss_new
    say "  attempt $attempt_idx: CSU_SSS_CFG [hex32 $sss_orig] -> [hex32 $sss_new]"

    # Program DST first, then SRC (writing SRC.SIZE triggers transfer)
    # (Pre-zero of the dest is done once by method_csudma before any attempts.)
    set size_val [expr {$::ADDR_BOOTROM_SIZE | 0x1}]   ;# bytes | LAST_WORD
    _dma_wr $DST_CH $::OFF_DMA_CTRL2 0
    _dma_wr $DST_CH $::OFF_DMA_ADDR  $::ADDR_DUMP_DST
    _dma_wr $DST_CH $::OFF_DMA_SIZE  $size_val
    _dma_wr $SRC_CH $::OFF_DMA_CTRL2 0
    _dma_wr $SRC_CH $::OFF_DMA_ADDR  $::ADDR_BOOTROM
    _dma_wr $SRC_CH $::OFF_DMA_SIZE  $size_val
    say "  attempt $attempt_idx: kicked off DMA (size [hex32 $size_val])"

    # 5. Poll BUSY (~1s)
    set polls 0
    set src_busy 1
    set dst_busy 1
    while {$polls < 100} {
        set sb 0; set db 0
        catch { set sb [expr {int([_dma_rd $SRC_CH $::OFF_DMA_STS]) & 0x1}] }
        catch { set db [expr {int([_dma_rd $DST_CH $::OFF_DMA_STS]) & 0x1}] }
        set src_busy $sb; set dst_busy $db
        if {$sb == 0 && $db == 0} { break }
        after 10
        incr polls
    }
    set t_poll [expr {[clock milliseconds] - $t0}]

    # 6. Capture interrupt status (survives BUSY clear)
    set src_intr [safe_rd [expr {$SRC_CH + $::OFF_DMA_I_STS}]]
    set dst_intr [safe_rd [expr {$DST_CH + $::OFF_DMA_I_STS}]]
    set src_intr_i 0; set dst_intr_i 0
    catch { set src_intr_i [expr {int($src_intr)}] }
    catch { set dst_intr_i [expr {int($dst_intr)}] }
    set src_intr_dec [_decode_dma_intr $src_intr_i]
    set dst_intr_dec [_decode_dma_intr $dst_intr_i]

    say "  attempt $attempt_idx: polled $polls iters in [_fmt_ms $t_poll]"
    say "    final SRC.BUSY=$src_busy DST.BUSY=$dst_busy"
    say "    SRC I_STS=[hex32 $src_intr] ($src_intr_dec)"
    say "    DST I_STS=[hex32 $dst_intr] ($dst_intr_dec)"

    set ok [expr {$src_busy == 0 && $dst_busy == 0}]
    return [dict create \
        ok               $ok \
        sss_orig         $sss_orig_i \
        sss_new          $sss_new \
        poll_iters       $polls \
        poll_ms          $t_poll \
        src_busy_final   $src_busy \
        dst_busy_final   $dst_busy \
        src_intr_sts     $src_intr_i \
        dst_intr_sts     $dst_intr_i \
        src_intr_decoded $src_intr_dec \
        dst_intr_decoded $dst_intr_dec]
}

proc method_csudma {ts dumps_dir} {
    set bin "$dumps_dir/bootrom-via-csudma-$ts.bin"
    set meta "$dumps_dir/bootrom-via-csudma-$ts.json"
    set t_start [clock milliseconds]

    say ""
    say "============================================================"
    say "  Method 3: CSU DMA loopback (SRC -> CSU SSS -> DST)"
    say "============================================================"

    _inter_method_recovery

    # O3: pre-snapshot CSU state
    set csu_pre [_snapshot_csu_security]

    # (D) Pre-zero dump destination once, before any DMA attempts
    set zero_ok [_write_zero_verified $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE "DMA dump dest"]

    # First attempt
    set a1 [_method_csudma_attempt 1]
    set final_attempt $a1
    set attempts_used 1

    # R4: one retry on timeout (only if DMA didn't complete cleanly)
    if {![dict get $a1 ok]} {
        say "  First attempt failed - retrying once"
        _inter_method_recovery
        set a2 [_method_csudma_attempt 2]
        set final_attempt $a2
        set attempts_used 2
    }

    # O3: post-snapshot CSU state
    set csu_post [_snapshot_csu_security]

    # Read the destination
    set result [dump_memory $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE 1024 $bin "CSU-DMA-copied BootROM"]

    set t_total [expr {[clock milliseconds] - $t_start}]
    set m [dict create \
        schema_version 1 method "3-csu-dma-loopback" timestamp $ts \
        source_address [format "0x%08X" $::ADDR_BOOTROM] \
        dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
        size_bytes     [dict get $result bytes_written] \
        chunks_total   [dict get $result chunks_total] \
        chunks_ok      [dict get $result chunks_ok] \
        chunks_failed  [dict get $result chunks_failed] \
        dump_total_ms  [dict get $result total_ms] \
        method_total_ms $t_total \
        attempts_used    $attempts_used \
        sss_cfg_orig     [format "0x%08X" [dict get $final_attempt sss_orig]] \
        sss_cfg_used     [format "0x%08X" [dict get $final_attempt sss_new]] \
        poll_iters       [dict get $final_attempt poll_iters] \
        poll_ms          [dict get $final_attempt poll_ms] \
        src_busy_final   [dict get $final_attempt src_busy_final] \
        dst_busy_final   [dict get $final_attempt dst_busy_final] \
        src_intr_sts     [format "0x%08X" [dict get $final_attempt src_intr_sts]] \
        dst_intr_sts     [format "0x%08X" [dict get $final_attempt dst_intr_sts]] \
        src_intr_decoded [dict get $final_attempt src_intr_decoded] \
        dst_intr_decoded [dict get $final_attempt dst_intr_decoded] \
        csu_status_pre   [dict get $csu_pre csu_status] \
        csu_status_post  [dict get $csu_post csu_status] \
        csu_ctrl_pre     [dict get $csu_pre csu_ctrl] \
        csu_ctrl_post    [dict get $csu_post csu_ctrl] \
        pre_zero_ok      $zero_ok \
        binary_path      $bin]
    write_dump_metadata $meta $m

    # Restore SSS_CFG
    safe_wr $::REG_CSU_SSS_CFG [dict get $final_attempt sss_orig]
    say "  Method 3 wall-clock: [_fmt_ms $t_total]"
}


# ---------------------------------------------------------------------------
# Method 1 + 2 common
# ---------------------------------------------------------------------------

# (A) Read a 64-bit value from OCM, where the payload stored an MRS result.
# Returns hex string "0xHHHHHHHHHHHHHHHH" or "(unavailable)" on failure.
# The payload writes via `str x10, [x12]` (single 64-bit store), so on
# little-endian AArch64 the low 32 bits live at addr+0 and high at addr+4.
proc _read_ocm_u64 {addr} {
    set lo [safe_rd $addr]
    set hi [safe_rd [expr {$addr + 4}]]
    if {$lo eq "ERR" || $hi eq "ERR"} { return "(unavailable)" }
    set lo_i 0; set hi_i 0
    catch { set lo_i [expr {int($lo) & 0xFFFFFFFF}] }
    catch { set hi_i [expr {int($hi) & 0xFFFFFFFF}] }
    return [format "0x%08X%08X" $hi_i $lo_i]
}

# (A/H2) Capture A53 EL3 sysreg snapshot from OCM. NAMING NOTE: these are
# NOT exception/fault syndrome values — our payload does not take an
# exception (LDP from gated AXI memory returns 0xDEADBEEF as DATA, not as
# a fault). The values are RESIDUAL — whatever BootROM left in ESR/FAR/
# ELR/SPSR_EL3 before handoff. Useful only if those residual values
# themselves are diagnostically interesting.
#
# Captured from OCM (not OpenOCD `reg`) because the payload itself does
# `MRS xN, esr_el3; STR xN, [addr]` at EL3, so OCM holds the real sysreg
# values. JTAG-mem-AP just reads OCM — works whether A53 is halted or
# running, and whether OpenOCD knows the sysreg name or not.
#
# Values are valid only after the payload has run (post-marker). Before
# that they're zero (we pre-zero the marker area).
proc _capture_a53_el3_sysregs {} {
    catch { targets uscale.axi } _
    return [dict create \
        esr_el3   [_read_ocm_u64 $::ADDR_ESR_EL3_SAVE] \
        far_el3   [_read_ocm_u64 $::ADDR_FAR_EL3_SAVE] \
        elr_el3   [_read_ocm_u64 $::ADDR_ELR_EL3_SAVE] \
        spsr_el3  [_read_ocm_u64 $::ADDR_SPSR_EL3_SAVE]]
}

# Extract just the hex value from `reg <name>` output.
proc _read_reg_hex {name} {
    if {[catch {reg $name} raw]} { return "(unavailable)" }
    if {[regexp {0x[0-9a-fA-F]+} $raw m]} { return $m }
    return [string trim $raw]
}

# Poll the JTAG-side completion marker (H5). Returns dict:
#   met: 1 if marker matched magic, 0 if timed out
#   ms:  wall-clock spent polling
proc _poll_done_marker {timeout_ms {interval_ms 25}} {
    catch { targets uscale.axi } _
    set t0 [clock milliseconds]
    while {1} {
        set lo [safe_rd $::ADDR_DONE_MARKER]
        set hi [safe_rd [expr {$::ADDR_DONE_MARKER + 4}]]
        set lo_i 0; set hi_i 0
        catch { set lo_i [expr {int($lo)}] }
        catch { set hi_i [expr {int($hi)}] }
        if {$lo_i == $::DONE_MARKER_LO && $hi_i == $::DONE_MARKER_HI} {
            return [dict create met 1 ms [expr {[clock milliseconds] - $t0}] \
                                lo [format "0x%08X" $lo_i] \
                                hi [format "0x%08X" $hi_i]]
        }
        if {[clock milliseconds] - $t0 >= $timeout_ms} {
            return [dict create met 0 ms [expr {[clock milliseconds] - $t0}] \
                                lo [format "0x%08X" $lo_i] \
                                hi [format "0x%08X" $hi_i]]
        }
        after $interval_ms
    }
}

proc _method_a53_common {ts dumps_dir payload_bin method_id method_label out_suffix} {
    set bin "$dumps_dir/bootrom-via-${out_suffix}-${ts}.bin"
    set meta "$dumps_dir/bootrom-via-${out_suffix}-${ts}.json"
    set t_start [clock milliseconds]

    say ""
    say "============================================================"
    say "  $method_label"
    say "============================================================"

    if {![file exists $payload_bin]} {
        say "  ERR: payload $payload_bin not found - skipping"
        say "  Build with: cd payloads && make"
        return
    }
    _check_payload_staleness $payload_bin

    # (C) Inter-method recovery before any other DAP ops
    _inter_method_recovery

    # ---- Release recipe (lib/release-recipes.tcl) ----
    # Booted state (FSBL/PMU FW/U-Boot/Linux running): core 0 is already out
    # of reset, so a plain deassert is a no-op. Do a full reset cycle to get
    # a clean EL3 core. Enable with: -c "set ::BOOTED_STATE 1".
    if {[info exists ::BOOTED_STATE] && $::BOOTED_STATE} {
        say "  BOOTED_STATE=1 -> reset-cycle core 0 to EL3 (freeze secondaries)"
        set release_ok [reset_release_a53_core0 $::ADDR_SAFE_LANDING]
    } else {
        set release_ok [release_a53_core0 $::ADDR_SAFE_LANDING]
    }
    if {!$release_ok} {
        say "  ERR: A53 release reported failure - skipping (would have run"
        say "       against a target that may not have actually come out of reset)"
        reset_a53_core0
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 method $method_id timestamp $ts \
            source_address "0xFFFFC000" \
            size_bytes     0 \
            chunks_total   0 chunks_ok 0 chunks_failed 0 \
            method_total_ms $t_total \
            error          "release_a53_core0 failed - A53 not released cleanly" \
            binary_path    "(no dump - release failed)"]
        write_dump_metadata $meta $m
        return
    }

    # ---- Examine + halt A53 ----
    # Retry arp_examine - on a fresh release the A53 sometimes needs an
    # extra cycle before the DAP A53 AP sees it as a valid target.
    set examine_ok 0
    for {set i 0} {$i < 3} {incr i} {
        if {[catch {uscale.a53.0 arp_examine} err] == 0} {
            set examine_ok 1
            if {$i > 0} { say "  A53 examine succeeded on attempt [expr {$i+1}]" }
            break
        }
        if {$i == 0} { say "  A53 examine attempt 1 failed: $err - retrying" }
        after 50
    }
    if {!$examine_ok} {
        say "  ERR: A53 examine failed after 3 attempts ($err) - skipping"
        reset_a53_core0
        return
    }
    catch { targets uscale.a53.0 } _
    catch { halt } _
    after 100
    set state [uscale.a53.0 curstate]
    if {$state ne "halted"} {
        say "  ERR: A53 didn't halt (state=$state) - skipping"
        reset_a53_core0
        return
    }

    # ---- Load payload to OCM ----
    # CRITICAL: OpenOCD's Tcl does UTF-8 character counting on the file
    # bytes. For binaries containing UTF-8-valid multi-byte sequences
    # (common in aarch64 instruction encodings), [string length] returns
    # CHAR COUNT not BYTE COUNT — truncating the payload load. Symptom:
    # last instructions missing, A53 falls off end of payload and faults.
    # Use `file size` for actual byte count and `binary scan c*` to
    # extract bytes correctly.
    catch { targets uscale.axi } _
    set nbytes [file size $payload_bin]
    set fh [open $payload_bin rb]
    fconfigure $fh -translation binary
    set bytes [read $fh $nbytes]
    close $fh
    # Extract bytes as a list of signed int8 — bypasses UTF-8 entirely
    binary scan $bytes c* byte_list
    # Build little-endian 32-bit words from byte_list. Pad final partial
    # word with NUL bytes if file size isn't a multiple of 4.
    set wordlist [list]
    set bl_len [llength $byte_list]
    for {set i 0} {$i < $bl_len} {incr i 4} {
        set b0 [lindex $byte_list $i]
        set b1 [expr {$i + 1 < $bl_len ? [lindex $byte_list [expr {$i + 1}]] : 0}]
        set b2 [expr {$i + 2 < $bl_len ? [lindex $byte_list [expr {$i + 2}]] : 0}]
        set b3 [expr {$i + 3 < $bl_len ? [lindex $byte_list [expr {$i + 3}]] : 0}]
        set w [expr {(($b0 & 0xFF)      ) | \
                     (($b1 & 0xFF) << 8 ) | \
                     (($b2 & 0xFF) << 16) | \
                     (($b3 & 0xFF) << 24)}]
        lappend wordlist $w
    }
    if {[catch {write_memory $::ADDR_PAYLOAD 32 $wordlist} err]} {
        say "  ERR: write_memory failed: $err - skipping"
        reset_a53_core0
        return
    }
    say "  Loaded $nbytes-byte payload to [hex32 $::ADDR_PAYLOAD]"

    # ---- Clear marker region + dump destination ----
    _zero_a53_marker_region
    set zero_ok [_write_zero_verified $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE "A53 dump dest"]

    # ---- Set PC, resume ----
    # M1: reg pc + resume works reliably on a freshly-released A53.
    # M2: reg pc + resume does NOT propagate to A53 hardware on this
    #     platform. Workaround: write the M2 payload directly at the
    #     A53's current PC (overwriting the landing-pad "b ."). A53
    #     resumes at its current PC and falls straight into the payload
    #     entry. No reg pc, no branch override, no addressing tricks.
    catch { targets uscale.a53.0 } _
    # M2 BRANCH (loader / D-cache off): writes payload at A53's current PC
    # instead of using `reg pc` to set PC to ADDR_PAYLOAD. Gives us two
    # independent load paths (M1 = reg pc to ADDR_PAYLOAD; M2 = write at pre_pc).
    if {$method_id eq "2-loader-cache-off"} {
        set pre_pc_str [_read_reg_hex pc]
        set pre_pc [_safe_int $pre_pc_str]
        say "  M2: PC=[hex32 $pre_pc_str] (writing payload at pre_pc, attempting reg pc)"
        if {$pre_pc >= 0xFFFC0000 && $pre_pc < 0xFFFC1000} {
            catch { targets uscale.axi } _
            if {[catch {write_memory $pre_pc 32 $wordlist} werr]} {
                say "  M2: WARN write at [hex32 $pre_pc] FAILED: $werr"
            }
            catch { targets uscale.a53.0 } _
            catch { reg pc $pre_pc } _
        } else {
            say "  M2: PC [hex32 $pre_pc_str] outside OCM - falling back to reg pc"
            if {[catch {reg pc $::ADDR_PAYLOAD} err]} {
                say "  ERR: setting PC failed: $err - skipping"
                reset_a53_core0
                return
            }
        }
    } else {
        # M1 path — proven working
        if {[catch {reg pc $::ADDR_PAYLOAD} err]} {
            say "  ERR: setting PC failed: $err - skipping"
            reset_a53_core0
            return
        }
        # The read-back appears to act as a needed sync; removing it
        # empirically breaks M1.
        set _pc_after_reg [_read_reg_hex pc]
        say "  reg pc reports [hex32 $_pc_after_reg] (cached read, may not match HW)"
    }
    catch { resume } _

    # ---- H5: poll the JTAG-side marker (no blind sleep) ----
    set poll_timeout_ms 2000
    set poll [_poll_done_marker $poll_timeout_ms]
    set marker_met [dict get $poll met]
    set marker_ms  [dict get $poll ms]
    if {$marker_met} {
        say "  Done marker observed after [_fmt_ms $marker_ms] (lo=[dict get $poll lo] hi=[dict get $poll hi])"
    } else {
        say "  Done marker NOT observed within [_fmt_ms $poll_timeout_ms] (lo=[dict get $poll lo] hi=[dict get $poll hi])"
    }

    # ---- Halt A53 and read post-halt state ----
    catch { targets uscale.a53.0 } _
    catch { halt } _
    after 100
    set state_after [uscale.a53.0 curstate]
    # (A) If still running, try aggressive force-halt before reading sysregs
    if {$state_after ne "halted"} {
        say "  A53 still running after first halt - attempting force-halt for sysreg capture"
        if {[_force_halt_a53]} {
            set state_after [uscale.a53.0 curstate]
            say "  Force-halt succeeded, A53 state: $state_after"
        } else {
            say "  Force-halt failed - sysreg capture may be incomplete"
        }
    }
    set pc_final [_read_reg_hex pc]
    say "  A53 state after run: $state_after; PC: $pc_final"

    # ---- H2: capture EL3 sysreg residual snapshot (best-effort; needs halt) ----
    # NOTE: Our payload does NOT take an exception (LDP from gated memory
    # returns 0xDEADBEEF as DATA, not as a fault). These registers contain
    # whatever was in them when BootROM handed control to JTAG-idle - they
    # are RESIDUAL, not a snapshot of a fault our payload triggered. A
    # real fault from our payload would clobber these AND change PC away
    # from the WFE spin loop.
    set fault [_capture_a53_el3_sysregs]
    say "  A53 EL3 sysregs (residual - no exception taken by payload):"
    say "    ESR_EL3  = [dict get $fault esr_el3]"
    say "    FAR_EL3  = [dict get $fault far_el3]"
    say "    ELR_EL3  = [dict get $fault elr_el3]"
    say "    SPSR_EL3 = [dict get $fault spsr_el3]"

    # ---- Read SCTLR before/after snapshots from OCM (M2 payload writes
    # these; M1 leaves them as 0). ----
    catch { targets uscale.axi } _
    set sctlr_before [safe_rd $::ADDR_SCTLR_BEFORE]
    set sctlr_after  [safe_rd $::ADDR_SCTLR_AFTER]
    set sctlr_before_i 0; set sctlr_after_i 0
    catch { set sctlr_before_i [expr {int($sctlr_before)}] }
    catch { set sctlr_after_i  [expr {int($sctlr_after)}] }
    set sctlr_before_dec [_decode_sctlr_el3 $sctlr_before_i]
    set sctlr_after_dec  [_decode_sctlr_el3 $sctlr_after_i]
    if {$sctlr_before_i != 0 || $sctlr_after_i != 0} {
        say "  SCTLR_EL3 before payload: [hex32 $sctlr_before] ($sctlr_before_dec)"
        say "  SCTLR_EL3 after  payload: [hex32 $sctlr_after]  ($sctlr_after_dec)"
        if {$sctlr_before_i == $sctlr_after_i && $sctlr_before_i != 0} {
            say "  WARN: SCTLR_EL3 unchanged - D-cache disable MSR may have been ignored"
        }
    }

    # ---- Verify completion ----
    set mlo [safe_rd $::ADDR_DONE_MARKER]
    set mhi [safe_rd [expr {$::ADDR_DONE_MARKER + 4}]]
    set mlo_i 0; set mhi_i 0
    catch { set mlo_i [expr {int($mlo)}] }
    catch { set mhi_i [expr {int($mhi)}] }
    set marker_ok 0
    if {$mlo_i == $::DONE_MARKER_LO && $mhi_i == $::DONE_MARKER_HI} {
        set marker_ok 1
    }

    # ---- Stage-0 marker (M2 only — written before any MRS) ----
    # Lets us tell "A53 never executed our code" (stage_start == 0) apart
    # from "A53 executed our code but MRS sctlr_el3 faulted" (stage_start
    # set, SCTLR_BEFORE == 0). M1 payload doesn't write this; expect 0.
    set stage_rd [safe_rd $::ADDR_STAGE_START]
    set stage_i 0
    catch { set stage_i [expr {int($stage_rd)}] }
    if {$method_id eq "2-loader-cache-off"} {
        if {$stage_i == $::STAGE_START_VAL} {
            say "  Stage-0 marker SET (0x[format %X $stage_i]) - A53 executed our payload"
            if {$sctlr_before_i == 0} {
                say "  DIAG: stage_start set but SCTLR_BEFORE=0 - MRS sctlr_el3 was a no-op"
                say "        (likely benign: SCTLR_EL3.C already 0 in JTAG-idle, so MRS"
                say "         read same value back; not a fault)"
            }
        } elseif {$stage_i == 0} {
            say "  Stage-0 marker UNSET - A53 never executed our payload code"
            say "        (release succeeded but PC didn't reach 0x[format %X $::ADDR_PAYLOAD],"
            say "         OR OCM write of payload bytes didn't actually land)"
        } else {
            say "  Stage-0 marker has unexpected value 0x[format %X $stage_i] - corruption?"
        }
    }

    # ---- Abort case: halt-after-resume did not return halted, OR marker
    # never set ----
    if {$state_after ne "halted"} {
        say "  ERR: A53 did not halt after run window - aborting (no dump read)"
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 method $method_id timestamp $ts \
            source_address "0xFFFFC000" \
            dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
            payload_addr   [format "0x%08X" $::ADDR_PAYLOAD] \
            payload_bytes  $nbytes \
            size_bytes     0 \
            chunks_total   0 chunks_ok 0 chunks_failed 0 \
            a53_state      $state_after \
            a53_pc_final   $pc_final \
            esr_el3        [dict get $fault esr_el3] \
            far_el3        [dict get $fault far_el3] \
            elr_el3        [dict get $fault elr_el3] \
            spsr_el3       [dict get $fault spsr_el3] \
            done_marker_ok 0 \
            done_marker_lo [format "0x%08X" $mlo_i] \
            done_marker_hi [format "0x%08X" $mhi_i] \
            marker_poll_ms $marker_ms \
            marker_polled  $marker_met \
            sctlr_before   [format "0x%08X" $sctlr_before_i] \
            sctlr_after    [format "0x%08X" $sctlr_after_i] \
            stage_start    [format "0x%08X" $stage_i] \
            stage_start_m1m2_expected [format "0x%08X" $::STAGE_START_VAL] \
            pre_zero_ok    $zero_ok \
            method_total_ms $t_total \
            error          "A53 did not halt after payload run window" \
            binary_path    "(no dump - payload did not complete)"]
        write_dump_metadata $meta $m
        reset_a53_core0
        return
    }

    # ---- Read dest ----
    set result [dump_memory $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE 1024 $bin "A53-extracted BootROM"]

    set t_total [expr {[clock milliseconds] - $t_start}]
    set m [dict create \
        schema_version 1 method $method_id timestamp $ts \
        source_address "0xFFFFC000" \
        dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
        payload_addr   [format "0x%08X" $::ADDR_PAYLOAD] \
        payload_bytes  $nbytes \
        size_bytes     [dict get $result bytes_written] \
        chunks_total   [dict get $result chunks_total] \
        chunks_ok      [dict get $result chunks_ok] \
        chunks_failed  [dict get $result chunks_failed] \
        dump_total_ms  [dict get $result total_ms] \
        a53_state      $state_after \
        a53_pc_final   $pc_final \
        esr_el3        [dict get $fault esr_el3] \
        far_el3        [dict get $fault far_el3] \
        elr_el3        [dict get $fault elr_el3] \
        spsr_el3       [dict get $fault spsr_el3] \
        done_marker_ok $marker_ok \
        done_marker_lo [format "0x%08X" $mlo_i] \
        done_marker_hi [format "0x%08X" $mhi_i] \
        marker_poll_ms $marker_ms \
        marker_polled  $marker_met \
        sctlr_before   [format "0x%08X" $sctlr_before_i] \
        sctlr_after    [format "0x%08X" $sctlr_after_i] \
        sctlr_before_decoded $sctlr_before_dec \
        sctlr_after_decoded  $sctlr_after_dec \
        stage_start    [format "0x%08X" $stage_i] \
        stage_start_m1m2_expected [format "0x%08X" $::STAGE_START_VAL] \
        pre_zero_ok    $zero_ok \
        method_total_ms $t_total \
        binary_path    $bin]
    write_dump_metadata $meta $m
    reset_a53_core0
    say "  Method wall-clock: [_fmt_ms $t_total]"
}


proc method_a53 {ts dumps_dir} {
    set p [file join $::_repo_root payloads bootrom-dump.bin]
    _method_a53_common $ts $dumps_dir $p \
        "1-a53-el3" "Method 1: A53 EL3 dump (default payload)" "a53"
}

proc method_loader {ts dumps_dir} {
    set p [file join $::_repo_root payloads bootrom-dump-clean.bin]
    _method_a53_common $ts $dumps_dir $p \
        "2-loader-cache-off" "Method 2: A53 loader (D-cache off, SCTLR snapshots)" "loader"
}

# ---------------------------------------------------------------------------
# Method: r5 (Cortex-R5 RPU payload-driven dump)
# ---------------------------------------------------------------------------
#
# R5 has a different master ID on the LPD AXI fabric than A53. If BootROM
# gating is keyed on master ID and R5 isn't blocked, this method could
# succeed where M1/M2 (A53 paths) returned all-DEADBEEF.
#
# The R5 payload lives in ATCM at global address 0xFFE00000 (R5-local 0x0).
# R5 boots from local 0x0 (VINITHI=0), runs the payload, copies BootROM to
# OCM bank 2, writes the same completion marker (0xCAFEBABE0000C0DE @
# 0xFFFE7000) that M1/M2 use so the polling logic is identical.
#
# We don't have an OpenOCD R5 target in our config so we can't halt R5 via
# `halt` or read its registers. We rely on the JTAG-side marker poll to
# tell us "payload completed". If marker never sets, we don't know whether
# R5 hung, faulted, or was never released - the diagnostic is sparser than
# the A53 methods.
proc method_r5 {ts dumps_dir} {
    set bin "$dumps_dir/bootrom-via-r5-$ts.bin"
    set meta "$dumps_dir/bootrom-via-r5-$ts.json"
    set t_start [clock milliseconds]
    set payload_bin [file join $::_repo_root payloads bootrom-dump-r5.bin]

    say ""
    say "============================================================"
    say "  Method 4: R5 RPU dump (Cortex-R5 ATCM payload)"
    say "============================================================"

    if {![file exists $payload_bin]} {
        say "  ERR: payload $payload_bin not found - skipping"
        say "  Build with: cd payloads && make"
        return
    }
    _check_payload_staleness $payload_bin

    # (C) Recovery + (B) partial RPU release for TCM access
    if {![_inter_method_recovery]} {
        say "  ERR: DAP wedged from prior method - aborting M4 (would compound"
        say "       the wedge by attempting LPD register writes)"
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 method "4-r5-rpu" timestamp $ts \
            source_address "0xFFFFC000" \
            size_bytes     0 \
            chunks_total   0 chunks_ok 0 chunks_failed 0 \
            method_total_ms $t_total \
            error          "DAP wedged before M4 - skipped to avoid compounding the wedge" \
            binary_path    "(no dump - DAP wedged)"]
        write_dump_metadata $meta $m
        return
    }

    # B: Bring the RPU AMBA bus + PGE out of reset BEFORE probing TCM. TCM
    # at 0xFFE00000 is only AXI-reachable when the RPU AMBA reset is
    # released. Also clear R5_0 PWRDWN.EN in case PMU/handoff left it set.
    # We leave R5_0_RESET asserted - cores stay in reset until full release.
    set rst_initial [safe_rd $::REG_CRL_RST_LPD_TOP]
    if {$rst_initial ne "ERR"} {
        set partial_clear [expr {(1 << $::BIT_RPU_AMBA_RESET) | (1 << $::BIT_RPU_PGE_RESET)}]
        set rst_partial [expr {int($rst_initial) & ~$partial_clear}]
        safe_wr $::REG_CRL_RST_LPD_TOP $rst_partial
        say "  M4 prep: CRL_RST_LPD_TOP [hex32 $rst_initial] -> [hex32 $rst_partial] (AMBA+PGE released)"
    }
    # Clear R5_0 power-down enable (best-effort - bit 0 of RPU_0_PWRDWN)
    set pwrdwn [safe_rd $::REG_RPU_0_PWRDWN]
    if {$pwrdwn ne "ERR" && [expr {int($pwrdwn) & 0x1}]} {
        set pwrdwn_new [expr {int($pwrdwn) & ~0x1}]
        safe_wr $::REG_RPU_0_PWRDWN $pwrdwn_new
        say "  M4 prep: RPU_0_PWRDWN.EN [hex32 $pwrdwn] -> [hex32 $pwrdwn_new] (cleared)"
    }
    after 20

    # Pre-flight: probe that TCM is readable/writable.
    set tcm_probe_addr $::ADDR_RPU0_ATCM
    safe_wr $tcm_probe_addr 0xA5A5A5A5
    set rb [safe_rd $tcm_probe_addr]
    if {$rb eq "ERR" || [expr {int($rb) & 0xFFFFFFFF}] != 0xA5A5A5A5} {
        say "  ERR: TCM at [hex32 $tcm_probe_addr] not readable/writable (got [hex32 $rb])"
        say "       Even after AMBA release - RPU island may be power-gated by PMU."
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 method "4-r5-rpu" timestamp $ts \
            source_address "0xFFFFC000" \
            dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
            payload_addr   [format "0x%08X" $tcm_probe_addr] \
            method_total_ms $t_total \
            error          "RPU TCM not accessible - PMU power-gated or XMPU blocking" \
            tcm_probe_readback [_safe_hex32 $rb] \
            crl_rst_lpd_top   [_safe_hex32 $rst_initial] \
            rpu_0_pwrdwn      [_safe_hex32 $pwrdwn] \
            binary_path    "(no dump - TCM unreachable)"]
        write_dump_metadata $meta $m
        return
    }
    say "  TCM probe OK at [hex32 $tcm_probe_addr]"

    # Snapshot CSU state for diagnostic
    set csu_pre [_snapshot_csu_security]

    # Load R5 payload into TCM at 0xFFE00000 (R5 sees this as 0x0).
    # See _method_a53_common note about UTF-8 byte-count bug — same fix.
    set nbytes [file size $payload_bin]
    set fh [open $payload_bin rb]
    fconfigure $fh -translation binary
    set bytes [read $fh $nbytes]
    close $fh
    binary scan $bytes c* byte_list
    set wordlist [list]
    set bl_len [llength $byte_list]
    for {set i 0} {$i < $bl_len} {incr i 4} {
        set b0 [lindex $byte_list $i]
        set b1 [expr {$i + 1 < $bl_len ? [lindex $byte_list [expr {$i + 1}]] : 0}]
        set b2 [expr {$i + 2 < $bl_len ? [lindex $byte_list [expr {$i + 2}]] : 0}]
        set b3 [expr {$i + 3 < $bl_len ? [lindex $byte_list [expr {$i + 3}]] : 0}]
        set w [expr {(($b0 & 0xFF)      ) | \
                     (($b1 & 0xFF) << 8 ) | \
                     (($b2 & 0xFF) << 16) | \
                     (($b3 & 0xFF) << 24)}]
        lappend wordlist $w
    }
    if {[catch {write_memory $::ADDR_RPU0_ATCM 32 $wordlist} err]} {
        say "  ERR: write payload to TCM failed: $err"
        return
    }
    say "  Loaded $nbytes-byte R5 payload to [hex32 $::ADDR_RPU0_ATCM]"

    # Clear OCM marker + dest before R5 runs (D: verified)
    safe_wr $::ADDR_DONE_MARKER 0
    safe_wr [expr {$::ADDR_DONE_MARKER + 4}] 0
    set zero_ok [_write_zero_verified $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE "R5 dump dest"]

    # Release R5
    if {![release_r5_core0]} {
        say "  ERR: release_r5_core0 failed - aborting"
        reset_r5_core0
        return
    }

    # Poll the marker. R5 should complete the 16KB copy in microseconds.
    set poll_timeout_ms 2000
    set poll [_poll_done_marker $poll_timeout_ms]
    set marker_met [dict get $poll met]
    set marker_ms  [dict get $poll ms]
    if {$marker_met} {
        say "  Done marker observed after [_fmt_ms $marker_ms] (R5 payload completed)"
    } else {
        say "  Done marker NOT observed within [_fmt_ms $poll_timeout_ms] - R5 may have"
        say "       hung or never released; reading destination anyway for diagnosis"
    }

    # Verify marker
    catch { targets uscale.axi } _
    set mlo [safe_rd $::ADDR_DONE_MARKER]
    set mhi [safe_rd [expr {$::ADDR_DONE_MARKER + 4}]]
    set mlo_i 0; set mhi_i 0
    catch { set mlo_i [expr {int($mlo)}] }
    catch { set mhi_i [expr {int($mhi)}] }
    set marker_ok 0
    if {$mlo_i == $::DONE_MARKER_LO && $mhi_i == $::DONE_MARKER_HI} {
        set marker_ok 1
    }

    # Read OCM destination (whatever R5 wrote, or zeros if it didn't)
    set csu_post [_snapshot_csu_security]
    set result [dump_memory $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE 1024 $bin "R5-extracted BootROM"]

    # Re-reset R5 (caller-recoverable)
    reset_r5_core0

    set t_total [expr {[clock milliseconds] - $t_start}]
    set m [dict create \
        schema_version 1 method "4-r5-rpu" timestamp $ts \
        source_address "0xFFFFC000" \
        dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
        payload_addr   [format "0x%08X" $::ADDR_RPU0_ATCM] \
        payload_bytes  $nbytes \
        size_bytes     [dict get $result bytes_written] \
        chunks_total   [dict get $result chunks_total] \
        chunks_ok      [dict get $result chunks_ok] \
        chunks_failed  [dict get $result chunks_failed] \
        dump_total_ms  [dict get $result total_ms] \
        done_marker_ok $marker_ok \
        done_marker_lo [format "0x%08X" $mlo_i] \
        done_marker_hi [format "0x%08X" $mhi_i] \
        marker_polled  $marker_met \
        marker_poll_ms $marker_ms \
        csu_status_pre  [dict get $csu_pre csu_status] \
        csu_status_post [dict get $csu_post csu_status] \
        pre_zero_ok     $zero_ok \
        method_total_ms $t_total \
        binary_path    $bin]
    write_dump_metadata $meta $m
    say "  Method 4 wall-clock: [_fmt_ms $t_total]"
}


# ---------------------------------------------------------------------------
# Method: aes (CSU AES route attempt - speculative)
# ---------------------------------------------------------------------------
#
# Routes BootROM source through the CSU AES engine to the DMA destination
# without explicitly starting an encryption operation. The AES SSS field
# selects what feeds the AES engine; the DMA_SSS field selects what feeds
# DMA-dst. We set:
#   AES_SSS = 0x5  -> AES input from DMA source
#   DMA_SSS = 0xA  -> DMA dest from AES output
#
# Then kick off CSU DMA reading from BootROM. The bytes flow through
# the AES input FIFO and (without an active AES key/start) they MAY just
# relay to the output FIFO unencrypted. If yes, we get plaintext BootROM.
# If no, we get garbage or hang.
#
# This is a long shot - AES has no documented passthrough mode. Documenting
# the negative result is useful even if it fails.
proc method_aes {ts dumps_dir} {
    set bin "$dumps_dir/bootrom-via-aes-$ts.bin"
    set meta "$dumps_dir/bootrom-via-aes-$ts.json"
    set t_start [clock milliseconds]
    set SRC_CH $::REG_CSU_DMA_SRC_BASE
    set DST_CH $::REG_CSU_DMA_DST_BASE

    say ""
    say "============================================================"
    say "  Method 5: CSU AES route (speculative - BootROM -> AES -> DMA)"
    say "============================================================"

    if {![_inter_method_recovery]} {
        say "  ERR: DAP wedged from prior method - aborting M5 (results would be"
        say "       indistinguishable from a transport failure)"
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 method "5-csu-aes-route" timestamp $ts \
            source_address [format "0x%08X" $::ADDR_BOOTROM] \
            size_bytes     0 \
            chunks_total   0 chunks_ok 0 chunks_failed 0 \
            method_total_ms $t_total \
            error          "DAP wedged before M5 - skipped to avoid noise dump" \
            binary_path    "(no dump - DAP wedged)"]
        write_dump_metadata $meta $m
        return
    }

    # Snapshot CSU before
    set csu_pre [_snapshot_csu_security]

    # 1. Soft-reset CSU DMA
    safe_wr $::REG_CSU_DMA_RESET 0x01; after 5
    safe_wr $::REG_CSU_DMA_RESET 0x00; after 5

    # 2. SSS routing: AES input from DMA src (bits 11-8 = 0x5),
    #                  DMA dst from AES output (bits 7-4 = 0xA)
    set sss_orig [safe_rd $::REG_CSU_SSS_CFG]
    set sss_orig_i 0
    catch { set sss_orig_i [expr {int($sss_orig)}] }
    set sss_new [expr {($sss_orig_i & ~0xFF0) | 0x5A0}]
    safe_wr $::REG_CSU_SSS_CFG $sss_new
    say "  CSU_SSS_CFG [hex32 $sss_orig] -> [hex32 $sss_new] (AES_SSS=5 DMA_SSS=0xA)"

    # 3. Zero destination (D: verified)
    set zero_ok [_write_zero_verified $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE "AES dump dest"]

    # 4. Kick off DMA SRC=BootROM, DST=OCM
    set size_val [expr {$::ADDR_BOOTROM_SIZE | 0x1}]
    safe_wr [expr {$DST_CH + $::OFF_DMA_CTRL2}] 0
    safe_wr [expr {$DST_CH + $::OFF_DMA_ADDR}]  $::ADDR_DUMP_DST
    safe_wr [expr {$DST_CH + $::OFF_DMA_SIZE}]  $size_val
    safe_wr [expr {$SRC_CH + $::OFF_DMA_CTRL2}] 0
    safe_wr [expr {$SRC_CH + $::OFF_DMA_ADDR}]  $::ADDR_BOOTROM
    safe_wr [expr {$SRC_CH + $::OFF_DMA_SIZE}]  $size_val
    say "  Kicked off BootROM -> AES -> DMA-dst transfer"

    # 5. Poll BUSY
    set polls 0
    set src_busy 1
    set dst_busy 1
    while {$polls < 100} {
        set sb 0; set db 0
        catch { set sb [expr {int([safe_rd [expr {$SRC_CH + $::OFF_DMA_STS}]]) & 0x1}] }
        catch { set db [expr {int([safe_rd [expr {$DST_CH + $::OFF_DMA_STS}]]) & 0x1}] }
        set src_busy $sb; set dst_busy $db
        if {$sb == 0 && $db == 0} { break }
        after 10
        incr polls
    }
    set t_poll [expr {[clock milliseconds] - $t_start}]

    set src_intr [safe_rd [expr {$SRC_CH + $::OFF_DMA_I_STS}]]
    set dst_intr [safe_rd [expr {$DST_CH + $::OFF_DMA_I_STS}]]
    set src_intr_i 0; set dst_intr_i 0
    catch { set src_intr_i [expr {int($src_intr)}] }
    catch { set dst_intr_i [expr {int($dst_intr)}] }
    set src_intr_dec [_decode_dma_intr $src_intr_i]
    set dst_intr_dec [_decode_dma_intr $dst_intr_i]

    say "  Polled $polls iters; SRC.BUSY=$src_busy DST.BUSY=$dst_busy"
    say "  SRC I_STS=[hex32 $src_intr] ($src_intr_dec)"
    say "  DST I_STS=[hex32 $dst_intr] ($dst_intr_dec)"

    # Snapshot CSU after
    set csu_post [_snapshot_csu_security]

    # Read dest
    set result [dump_memory $::ADDR_DUMP_DST $::ADDR_BOOTROM_SIZE 1024 $bin "CSU-AES-routed BootROM"]

    # Restore SSS
    safe_wr $::REG_CSU_SSS_CFG $sss_orig_i

    set t_total [expr {[clock milliseconds] - $t_start}]
    set m [dict create \
        schema_version 1 method "5-csu-aes-route" timestamp $ts \
        source_address [format "0x%08X" $::ADDR_BOOTROM] \
        dump_dst_addr  [format "0x%08X" $::ADDR_DUMP_DST] \
        size_bytes     [dict get $result bytes_written] \
        chunks_total   [dict get $result chunks_total] \
        chunks_ok      [dict get $result chunks_ok] \
        chunks_failed  [dict get $result chunks_failed] \
        dump_total_ms  [dict get $result total_ms] \
        sss_cfg_orig   [format "0x%08X" $sss_orig_i] \
        sss_cfg_used   [format "0x%08X" $sss_new] \
        poll_iters     $polls \
        poll_ms        $t_poll \
        src_busy_final $src_busy \
        dst_busy_final $dst_busy \
        src_intr_sts   [format "0x%08X" $src_intr_i] \
        dst_intr_sts   [format "0x%08X" $dst_intr_i] \
        src_intr_decoded $src_intr_dec \
        dst_intr_decoded $dst_intr_dec \
        csu_status_pre  [dict get $csu_pre csu_status] \
        csu_status_post [dict get $csu_post csu_status] \
        pre_zero_ok     $zero_ok \
        method_total_ms $t_total \
        binary_path    $bin]
    write_dump_metadata $meta $m
    say "  Method 5 wall-clock: [_fmt_ms $t_total]"
}


# ---------------------------------------------------------------------------
# Research method handlers — sourced from lib/ for organization
# ---------------------------------------------------------------------------
# research-pmu holds the live Phase-7 methods. It depends on
# _method_a53_common, _safe_int, ::baseline, safe_rd/safe_wr, hex32 — all
# defined above. (research-csu/sha/trust removed 2026-06-08 — those were the
# retracted-findings probe methods.)
source [file join $_script_dir lib research-pmu.tcl]


# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

puts ""
puts "============================================================"
puts "  BootROM extraction"
puts "  Timestamp:   $_ts"
puts "  Output dir:  $_dumps_dir/"
puts "  Log file:    $_log_path"
puts "  Methods:     $_which"
puts "============================================================"

set _t_script_start [clock milliseconds]

switch -- $_which {
    baseline  { method_baseline  $_ts $_dumps_dir }
    csudma    { method_csudma    $_ts $_dumps_dir }
    a53       { method_a53       $_ts $_dumps_dir }
    loader    { method_loader    $_ts $_dumps_dir }
    r5        { method_r5        $_ts $_dumps_dir }
    aes       { method_aes       $_ts $_dumps_dir }
    pmu-ipi { method_pmu_ipi $_ts $_dumps_dir }
    pmu-pm-probe { method_pmu_pm_probe $_ts $_dumps_dir }
    pmu-mmio-write { method_pmu_mmio_write $_ts $_dumps_dir }
    pmu-rpu-wake { method_pmu_rpu_wake $_ts $_dumps_dir }
    pmu-r5-wakeup { method_pmu_r5_wakeup $_ts $_dumps_dir }
    pmu-r5-bootrom { method_pmu_r5_bootrom $_ts $_dumps_dir }
    hello-uart { method_hello_uart $_ts $_dumps_dir }
    pmu-wake-probe { method_pmu_wake_probe $_ts $_dumps_dir }
    all      {
        method_baseline $_ts $_dumps_dir
        method_csudma   $_ts $_dumps_dir
        method_a53      $_ts $_dumps_dir
        method_loader   $_ts $_dumps_dir
        method_r5       $_ts $_dumps_dir
        method_aes      $_ts $_dumps_dir
    }
    default  {
        puts "ERR: unknown method '$_which' (valid: baseline, csudma, a53, loader, r5, aes, all)"
        return
    }
}

set _t_script_total [expr {[clock milliseconds] - $_t_script_start}]

puts ""
puts "============================================================"
puts "  Done. Wall-clock: [_fmt_ms $_t_script_total]"
puts "  Artifacts in $_dumps_dir/"
puts "============================================================"
puts ""
puts "Generate analysis + summary:"
puts "  python3 tools/bootrom.py                  # auto-detect most recent set"
puts "  python3 tools/bootrom.py --timestamp $_ts"
puts ""

# Close the log file so the python analyzer can read it if needed
if {[info exists ::REPORT_FH] && $::REPORT_FH ne ""} {
    catch { close $::REPORT_FH }
    set ::REPORT_FH ""
}

# Try to auto-run from inside OpenOCD
if {[catch {exec python3 [file join $::_repo_root tools bootrom.py] --timestamp $_ts 2>@1} _out]} {
    puts "(Auto-run from OpenOCD failed: $_out)"
    puts "(Run the python command above yourself.)"
} else {
    puts $_out
}
