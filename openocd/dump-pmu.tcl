# dump-pmu.tcl — ZynqMP PMU memory extraction via JTAG mem-AP.
#
# Targets the PMU's two private memory regions:
#   PMU ROM     0xFFD00000  size  0x8000  (32 KB) — immutable boot code
#   PMU LMB RAM 0xFFDC0000  size 0x20000 (128 KB) — user FW load region
#
# Unlike the CSU BootROM, PMU memory is documented as readable via the
# JTAG AXI mem-AP without disabling any security gate. From the existing
# enumeration annotation on CSU.JTAG_SEC.SSSS_PMU_SEC: "PMU still readable
# via AXI mem-AP, just not directly controllable." So this v1 only does
# a baseline AXI read — no payload, no A53 release, no security-gate
# manipulation. If M0 returns real bytes (not 0xDEADBEEF), we have the
# 32KB PMU ROM in hand.
#
# Per-method artifacts written to dumps/:
#   pmu-rom-<ts>.bin      raw 32 KB
#   pmu-rom-<ts>.json     sidecar (CSU + PMU_GLOBAL state, chunks, timing)
#   pmu-lmb-<ts>.bin      raw 128 KB
#   pmu-lmb-<ts>.json     sidecar
#   dump-pmu-<ts>.log     full stdout transcript
#
# Usage (default — runs both regions):
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-pmu.tcl; shutdown"
#
# Single region (debugging):
#   openocd -f openocd/zcu102.cfg \
#       -c "init; set ::PMU_REGION rom; source openocd/dump-pmu.tcl; shutdown"
#
# Valid regions: rom, lmb, rom-unlocked, all (default).
#
# - rom          : read 0xFFD00000 (32 KB) at current CSU.JTAG_SEC.  ;# verify-addresses:skip
#                  In default JTAG-idle (SSSS_PMU_SEC=0) this returns
#                  0xDEADBEEF — the gate covers reads too.
# - lmb          : read 0xFFDC0000 (128 KB) PMU LMB RAM. Readable
#                  without gate change. Usually empty (FW_IS_PRESENT=0).
# - rom-unlocked : write CSU.JTAG_SEC |= 0x1C0 (sets SSSS_PMU_SEC[8:6]
#                  = 0b111), then re-dump PMU ROM. Gate stays open
#                  for the rest of the session AND across openocd
#                  reconnects (sticky until power-cycle).
# - all          : runs rom, lmb, then rom-unlocked. The pair (rom,
#                  rom-unlocked) is the evidence-of-cause pair —
#                  identical setup, gate flip is the only diff.
#
# See memory/reference_pmu_internals.md for the source-of-truth references
# (Xilinx QEMU device tree, UG1085 Chapter 6, AMD wiki).


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
if {[info exists ::PMU_REGION]} { set _which $::PMU_REGION }

set _log_path "$_dumps_dir/dump-pmu-$_ts.log"
if {![info exists ::REPORT_FH] || $::REPORT_FH eq ""} {
    set ::REPORT_FH [open $_log_path w]
}

source [file join $_script_dir lib enum-helpers.tcl]
source [file join $_script_dir lib dump-memory.tcl]


# ---------------------------------------------------------------------------
# Register addresses (canonical — source: memory/reference_pmu_internals.md)
# ---------------------------------------------------------------------------

# PMU memory regions
set ::ADDR_PMU_ROM         0xFFD00000   ;# 32 KB immutable PMU boot code
set ::ADDR_PMU_ROM_SIZE    0x00008000
set ::ADDR_PMU_LMB         0xFFDC0000   ;# LMB RAM (user FW load region)
# Device tree says 0x20000 (128 KB) but live silicon only has 124 KB readable
# via AXI mem-AP. The last 4 KB chunk (0xFFDDF000–0xFFDDFFFF) consistently
# triggers a JTAG-DP sticky error which wedges the DAP for all subsequent
# operations. Likely the high 4 KB is LMB MMIO control space or power-
# gated — either way, do NOT read it from our dump tool. If you ever
# need that region, probe it as a one-shot AFTER a power-cycle so the
# wedge can't cascade.
set ::ADDR_PMU_LMB_SIZE    0x0001F000

# PMU control registers — for state snapshot
set ::REG_PMU_GLOBAL_CNTRL 0xFFD80000
set ::REG_PMU_GLOBAL_PWR   0xFFD80100
set ::REG_PMU_LOCAL_RESET  0xFFD80608   ;# PMU_GLOBAL.MB_RESET (1 = held in reset)

# CSU security gate that controls PMU JTAG-TAP visibility (NOT memory reads
# from AXI mem-AP; that's separately governed). Reported for diagnostic.
set ::REG_CSU_JTAG_SEC     0xFFCA0038   ;# CSU.JTAG_SEC (SSSS_PMU_SEC bits 8:6); NOT 0xFFCA003C which is JTAG_DAP_CFG


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Format a value that may be "ERR" (from safe_rd) as a hex32 string. If
# the value is "ERR", returns "0xDEADBEEF" as a sentinel. Same pattern as
# dump-bootrom.tcl's _safe_hex32.
proc _safe_hex32 {val} {
    if {$val eq "ERR"} { return "0xDEADBEEF" }
    return [format "0x%08X" [expr {int($val)}]]
}

proc _fmt_ms {ms} {
    if {$ms < 1000} { return "${ms} ms" }
    return [format "%.2f s" [expr {$ms / 1000.0}]]
}

# Light-weight DAP recovery between methods. If a prior region read hit
# an unmapped/MMIO address, the DAP can latch a sticky error that makes
# every subsequent read return failure. Clear that before each new method.
# Simpler than dump-bootrom.tcl's _inter_method_recovery — PMU dump
# doesn't release A53 so we don't need the A53 escalation paths.
proc _pmu_dap_recovery {} {
    for {set i 0} {$i < 5} {incr i} {
        catch { uscale.dap dpreg 0 0x1e } _
        after 5
    }
    catch { targets uscale.axi } _
    # Probe: a CSU register read that should always succeed if the DAP
    # is healthy. If it still returns ERR, the recovery didn't take.
    set probe [safe_rd 0xFFCA0000]
    if {$probe eq "ERR"} {
        catch { uscale.axi arp_examine } _
        for {set i 0} {$i < 5} {incr i} {
            catch { uscale.dap dpreg 0 0x1e } _
            after 5
        }
        set probe [safe_rd 0xFFCA0000]
    }
    if {$probe eq "ERR"} {
        say "  WARN: DAP recovery failed — subsequent reads may be unreliable"
        return 0
    }
    return 1
}

# Snapshot PMU control + JTAG security state. Captured into every dump's
# sidecar so we know what the PMU was doing when the bytes were read.
proc _snapshot_pmu_state {} {
    catch { targets uscale.axi } _
    set out [dict create]
    dict set out pmu_global_cntrl [_safe_hex32 [safe_rd $::REG_PMU_GLOBAL_CNTRL]]
    dict set out pmu_global_pwr   [_safe_hex32 [safe_rd $::REG_PMU_GLOBAL_PWR]]
    dict set out csu_jtag_sec     [_safe_hex32 [safe_rd $::REG_CSU_JTAG_SEC]]
    return $out
}


# ---------------------------------------------------------------------------
# Method: dump a PMU memory region
# ---------------------------------------------------------------------------
#
# region_id    short label for filenames ("rom" or "lmb")
# addr         base address (e.g. 0xFFD00000)
# size_bytes   bytes to read (e.g. 0x8000)
# region_name  human-readable label for the log
#
proc method_pmu_region {ts dumps_dir region_id addr size_bytes region_name} {
    set bin  "$dumps_dir/pmu-${region_id}-${ts}.bin"
    set meta "$dumps_dir/pmu-${region_id}-${ts}.json"
    set t_start [clock milliseconds]

    say ""
    say "============================================================"
    say "  PMU region '$region_id': $region_name"
    say "  source [hex32 $addr] for $size_bytes bytes ([expr {$size_bytes / 1024}] KB)"
    say "============================================================"

    if {![_pmu_dap_recovery]} {
        say "  ERR: DAP wedged; aborting region '$region_id' (would produce tool-fill data)"
        set t_total [expr {[clock milliseconds] - $t_start}]
        set m [dict create \
            schema_version 1 \
            method "pmu-${region_id}" \
            timestamp $ts \
            source_address [format "0x%08X" $addr] \
            size_bytes 0 \
            chunks_total 0 chunks_ok 0 chunks_failed 0 \
            method_total_ms $t_total \
            error "DAP wedged before this region — needs board power-cycle" \
            binary_path "(no dump - DAP wedged)"]
        write_dump_metadata $meta $m
        return
    }
    set state_pre [_snapshot_pmu_state]
    say "  PMU state snapshot (pre):"
    say "    PMU_GLOBAL.CNTRL = [dict get $state_pre pmu_global_cntrl]"
    say "    PMU_GLOBAL.PWR   = [dict get $state_pre pmu_global_pwr]"
    say "    CSU.JTAG_SEC     = [dict get $state_pre csu_jtag_sec]"

    # Chunked read via JTAG AXI mem-AP. 1024-word chunks match dump-bootrom.tcl
    # convention (4 KB per chunk, amortizes USB latency).
    set result [dump_memory $addr $size_bytes 1024 $bin "PMU $region_id"]

    set state_post [_snapshot_pmu_state]

    set t_total [expr {[clock milliseconds] - $t_start}]

    set m [dict create \
        schema_version 1 \
        method "pmu-${region_id}" \
        timestamp $ts \
        source_address [format "0x%08X" $addr] \
        size_bytes [dict get $result bytes_written] \
        chunks_total [dict get $result chunks_total] \
        chunks_ok    [dict get $result chunks_ok] \
        chunks_failed [dict get $result chunks_failed] \
        dump_total_ms [dict get $result total_ms] \
        method_total_ms $t_total \
        pmu_global_cntrl_pre  [dict get $state_pre  pmu_global_cntrl] \
        pmu_global_pwr_pre    [dict get $state_pre  pmu_global_pwr] \
        csu_jtag_sec_pre      [dict get $state_pre  csu_jtag_sec] \
        pmu_global_cntrl_post [dict get $state_post pmu_global_cntrl] \
        pmu_global_pwr_post   [dict get $state_post pmu_global_pwr] \
        csu_jtag_sec_post     [dict get $state_post csu_jtag_sec] \
        binary_path $bin]
    write_dump_metadata $meta $m

    say "  Method wall-clock: [_fmt_ms $t_total]"
}


proc method_pmu_rom {ts dumps_dir} {
    method_pmu_region $ts $dumps_dir "rom" $::ADDR_PMU_ROM $::ADDR_PMU_ROM_SIZE \
        "PMU ROM (immutable boot code)"
}

proc method_pmu_lmb {ts dumps_dir} {
    method_pmu_region $ts $dumps_dir "lmb" $::ADDR_PMU_LMB $::ADDR_PMU_LMB_SIZE \
        "PMU LMB RAM (user FW load region)"
}

# Open SSSS_PMU_SEC field (CSU.JTAG_SEC bits 8:6) and dump PMU ROM again.
# Empirically, with SSSS_PMU_SEC=0 the AXI mem-AP returns 0xDEADBEEF for
# every chunk in the PMU ROM region — even though existing enumeration
# annotation claimed PMU was "still readable via AXI mem-AP". The
# annotation was wrong; the gate covers reads too.
#
# Side effects of opening this gate:
#   - PMU MicroBlaze TAP appears on the JTAG target chain (we don't use
#     it yet, but it's now reachable for halt/step in subsequent work)
#   - CSU.JTAG_SEC stays sticky in this state until power-cycle
#   - Other SSSS_PMU_SEC-gated paths (PMU memory, PMU IPI buffers) also
#     unlock — including any side-channel surface PMU FW would expose
#
# References:
#   - https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/2587197506
#     ("Zynq UltraScale+ MPSoC JTAG Enable in U-Boot") uses the same
#     write pattern, though against a different register offset on
#     production silicon. We use REG_CSU_JTAG_SEC (0xFFCA0038) which
#     matches the project's register-address audit.
proc method_pmu_rom_unlocked {ts dumps_dir} {
    say ""
    say "============================================================"
    say "  PMU ROM (with SSSS_PMU_SEC gate opened)"
    say "============================================================"

    if {![_pmu_dap_recovery]} {
        say "  ERR: DAP wedged; aborting rom-unlocked (gate write would fail anyway)"
        set t_start [clock milliseconds]
        set m [dict create \
            schema_version 1 \
            method "pmu-rom-unlocked" \
            timestamp $ts \
            source_address [format "0x%08X" $::ADDR_PMU_ROM] \
            size_bytes 0 \
            chunks_total 0 chunks_ok 0 chunks_failed 0 \
            method_total_ms [expr {[clock milliseconds] - $t_start}] \
            error "DAP wedged before gate-write — needs board power-cycle" \
            binary_path "(no dump - DAP wedged)"]
        write_dump_metadata "$dumps_dir/pmu-rom-unlocked-${ts}.json" $m
        return
    }
    catch { targets uscale.axi } _
    set jtag_sec_pre [safe_rd $::REG_CSU_JTAG_SEC]
    set pre_i 0
    catch { set pre_i [expr {int($jtag_sec_pre)}] }
    # Set bits 8:6 (SSSS_PMU_SEC field — open all 3 PMU access paths)
    set unlock_mask 0x1C0
    set new_i [expr {$pre_i | $unlock_mask}]
    say "  CSU.JTAG_SEC pre  = [_safe_hex32 $jtag_sec_pre]"
    say "  writing            [format 0x%08X $new_i] (OR with $unlock_mask)"
    safe_wr $::REG_CSU_JTAG_SEC $new_i
    after 10
    set jtag_sec_post [safe_rd $::REG_CSU_JTAG_SEC]
    set post_i 0
    catch { set post_i [expr {int($jtag_sec_post)}] }
    say "  CSU.JTAG_SEC post = [_safe_hex32 $jtag_sec_post]"

    if {($post_i & $unlock_mask) != $unlock_mask} {
        set still_off [format 0x%03X [expr {$unlock_mask & ~($post_i & $unlock_mask)}]]
        say "  WARN: SSSS_PMU_SEC bits did NOT all take. Still off: $still_off"
        say "        Likely cause: an eFuse policy is locking the gate. Without"
        say "        eFuse changes (irreversible), PMU ROM stays gated."
    } else {
        say "  OK: SSSS_PMU_SEC bits 8:6 all set; PMU ROM should now be readable"
    }

    method_pmu_region $ts $dumps_dir "rom-unlocked" \
        $::ADDR_PMU_ROM $::ADDR_PMU_ROM_SIZE \
        "PMU ROM (after SSSS_PMU_SEC unlock)"
}


# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

puts ""
puts "============================================================"
puts "  PMU extraction"
puts "  Timestamp:   $_ts"
puts "  Output dir:  $_dumps_dir/"
puts "  Log file:    $_log_path"
puts "  Regions:     $_which"
puts "============================================================"

set _t_script_start [clock milliseconds]

switch -- $_which {
    rom          { method_pmu_rom $_ts $_dumps_dir }
    lmb          { method_pmu_lmb $_ts $_dumps_dir }
    rom-unlocked { method_pmu_rom_unlocked $_ts $_dumps_dir }
    all {
        # Order matters: dump gated ROM first (proves the gate is up),
        # then LMB (works either way), then unlock the gate and re-dump
        # ROM. The before/after pair is the evidence the gate flip
        # caused the change.
        method_pmu_rom          $_ts $_dumps_dir
        method_pmu_lmb          $_ts $_dumps_dir
        method_pmu_rom_unlocked $_ts $_dumps_dir
    }
    default {
        puts "ERR: unknown region '$_which' (valid: rom, lmb, rom-unlocked, all)"
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
puts "Generate per-bin analysis:"
puts "  python3 tools/bootrom.py analyze dumps/pmu-rom-$_ts.bin"
puts "  python3 tools/bootrom.py analyze dumps/pmu-lmb-$_ts.bin"
puts ""

if {[info exists ::REPORT_FH] && $::REPORT_FH ne ""} {
    catch { close $::REPORT_FH }
    set ::REPORT_FH ""
}

# Auto-run per-region analyzer. Using a private loop variable name so the
# variable doesn't leak into callers that source this file.
set _bootrom_py [file join $::_repo_root tools bootrom.py]
foreach _pmu_analyzer_region {rom lmb rom-unlocked} {
    set _binp "$_dumps_dir/pmu-${_pmu_analyzer_region}-${_ts}.bin"
    if {[file exists $_binp]} {
        if {[catch {exec python3 $_bootrom_py analyze $_binp 2>@1} _out]} {
            puts "(analyzer for pmu-${_pmu_analyzer_region} failed: $_out)"
        } else {
            puts $_out
        }
    }
}
unset _pmu_analyzer_region
