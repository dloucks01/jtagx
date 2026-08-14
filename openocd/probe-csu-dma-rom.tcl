# probe-csu-dma-rom.tcl — non-destructive CSU-DMA "alternate bus master" ROM probe.
#
# HYPOTHESIS: the DAP cannot read the on-chip ROMs (the CSU BootROM is not
# AXI-mapped at all; the PMU ROM at 0xFFD00000 is reachable in principle but is
# blocked by a master-aware AXI filter — see project_pmu_rom_efuse_locked).
# The CSU DMA engine (CSUDMA, the engine the BootROM itself uses) is a DIFFERENT
# AXI master. This probe asks: can CSUDMA, driven from JTAG/DAP-NS, read a ROM
# region the DAP can't, by doing a memory-to-memory copy (SSS DMA loopback) from
# the ROM into OCM, which we then read back over the DAP?
#
# Realistic ROM target = the PMU ROM (0xFFD00000): a *documented* 32 KB ROM that
# is DAP-blocked. The CSU BootROM has no AXI address, so it cannot be a DMA
# source either; PMU ROM is the clean, grounded experiment. Honest odds: LOW —
# if the master-aware filter also covers CSUDMA, this confirms a negative.
#
# NON-DESTRUCTIVE: only writes CSUDMA config regs + two OCM scratch buffers
# (free in JTAG-idle). Tiny 8-word transfers. safe-rd recovery between steps.
# RISK: a wedged/illegal DMA *could* stick the DAP; if reads start returning ERR
# en masse, power-cycle (SW1 off / 5 s / on). Run at JTAG-idle.
#
# Usage:
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-csu-dma-rom.tcl; shutdown"
# Output: reports/csu-dma-rom-<ts>.md (raw values; interpretation inline).
#
# Register layout traced to: csudma.h (pmufw), xsecure_sss.c/.h (xilsecure).
# SSS DMA0-loopback value 0x50 derived from XSecure_SssLookupTable[DMA0][DMA0]=0x05
# << (4*DMA0=4). SIZE field is at bit 2 => write (nwords<<2)|last_word.

catch { targets uscale.axi } _
catch { uscale.dap dpreg 0 0x1e } _

# --- CSUDMA + SSS register map (grounded) ---
set SRC_ADDR 0xFFC80000
set SRC_SIZE 0xFFC80004
set SRC_STS  0xFFC80008
set DST_ADDR 0xFFC80800
set DST_SIZE 0xFFC80804
set DST_STS  0xFFC80808
set SSS_CFG  0xFFCA0008
set SSS_DMA_LOOPBACK 0x50

# --- OCM scratch buffers (free in JTAG-idle) ---
set OCM_SRC 0xFFFC0100
set OCM_DST 0xFFFC0200
set NWORDS  8

set ts [clock format [clock seconds] -format %Y-%m-%d-%H%M%S]
file mkdir reports
set out "reports/csu-dma-rom-$ts.md"
set fh [open $out w]
proc emit {s} { global fh; puts $fh $s; echo $s }

proc rdi {addr} {
    if {[catch {read_memory $addr 32 1} r]} {
        catch { uscale.dap dpreg 0 0x1e } _
        return -1
    }
    return [expr {[lindex $r 0] & 0xFFFFFFFF}]
}
proc rdhex {addr} {
    set v [rdi $addr]
    if {$v < 0} { return "ERR" }
    return [format "0x%08X" $v]
}
proc wr {addr val} { catch { write_memory $addr 32 [list $val] } }

# Drive one CSUDMA mem-to-mem copy of $nwords words from $src to $dst via SSS
# loopback. Returns "done", "timeout", or "blocked". Non-destructive config only.
proc dma_copy {src dst nwords} {
    global SRC_ADDR SRC_SIZE SRC_STS DST_ADDR DST_SIZE DST_STS SSS_CFG SSS_DMA_LOOPBACK
    set szreg [expr {($nwords << 2) | 1}]
    wr $SSS_CFG $SSS_DMA_LOOPBACK
    wr $DST_ADDR $dst
    wr $DST_SIZE $szreg
    wr $SRC_ADDR $src
    wr $SRC_SIZE $szreg
    set i 0
    while {$i < 200} {
        set st [rdi $DST_STS]
        if {$st < 0} { return "blocked" }
        if {($st & 0x1) == 0} { return "done" }
        incr i
    }
    return "timeout"
}

proc dump_words {addr nwords} {
    set parts [list]
    set i 0
    while {$i < $nwords} {
        lappend parts [rdhex [expr {$addr + (4 * $i)}]]
        incr i
    }
    return [join $parts " "]
}

emit "# CSU-DMA alternate-bus-master ROM probe — $ts"
emit ""
emit "Tests whether CSUDMA can read a ROM region the DAP cannot. See header of"
emit "openocd/probe-csu-dma-rom.tcl and docs/13-attack-research-plan.md."
emit ""

# ---------------------------------------------------------------------------
emit "## 0. CSUDMA reachability"
# ---------------------------------------------------------------------------
emit "SRC_STS = [rdhex $SRC_STS]   DST_STS = [rdhex $DST_STS]   SSS_CFG(before) = [rdhex $SSS_CFG]"
emit "(ERR here => CSUDMA/CSU not DAP-NS accessible in this state; rest is moot.)"
emit ""

# ---------------------------------------------------------------------------
emit "## 1. Baseline: OCM -> OCM loopback (proves DMA works + calibrates SIZE)"
# ---------------------------------------------------------------------------
set _w 0
while {$_w < $NWORDS} {
    wr [expr {$OCM_SRC + (4 * $_w)}] [expr {0xC0DE0000 | $_w}]
    wr [expr {$OCM_DST + (4 * $_w)}] 0x00000000
    incr _w
}
emit "src buffer @ [format 0x%08X $OCM_SRC] = [dump_words $OCM_SRC $NWORDS]"
emit "dst buffer @ [format 0x%08X $OCM_DST] (pre)  = [dump_words $OCM_DST $NWORDS]"
set _r [dma_copy $OCM_SRC $OCM_DST $NWORDS]
emit "dma_copy result: $_r"
emit "dst buffer @ [format 0x%08X $OCM_DST] (post) = [dump_words $OCM_DST $NWORDS]"
set _base_ok 1
set _w 0
while {$_w < $NWORDS} {
    set _exp [expr {0xC0DE0000 | $_w}]
    set _got [rdi [expr {$OCM_DST + (4 * $_w)}]]
    if {$_got != $_exp} { set _base_ok 0 }
    incr _w
}
if {$_base_ok} {
    emit "**BASELINE PASS** — CSUDMA mem-to-mem works from JTAG; SIZE encoding correct."
} else {
    emit "**BASELINE FAIL** — DMA didn't copy OCM->OCM. Either CSUDMA is gated from"
    emit "DAP-NS, the SIZE encoding is wrong, or SSS loopback != 0x50 on this part."
    emit "ROM results below are NOT trustworthy until the baseline passes."
}
catch { uscale.dap dpreg 0 0x1e } _
emit ""

# ---------------------------------------------------------------------------
emit "## 2. PMU ROM via CSUDMA vs via DAP (the real experiment)"
# ---------------------------------------------------------------------------
emit "PMU ROM is documented at 0xFFD00000 (32 KB) and is DAP-blocked (eFuse"
emit "SSSS_PMU_SEC). If CSUDMA reaches it, dst gets real ROM words the direct"
emit "DAP read cannot return."
emit ""
emit "DAP-direct read 0xFFD00000 (x8): [dump_words 0xFFD00000 $NWORDS]"
set _w 0
while {$_w < $NWORDS} { wr [expr {$OCM_DST + (4 * $_w)}] 0x00000000; incr _w }
set _r [dma_copy 0xFFD00000 $OCM_DST $NWORDS]
emit "CSUDMA copy 0xFFD00000 -> OCM result: $_r"
emit "OCM dst after CSUDMA copy:        [dump_words $OCM_DST $NWORDS]"
emit ""
emit "INTERPRETATION: if the OCM dst now holds non-zero, code-like words that the"
emit "DAP-direct read did NOT return, CSUDMA reached the PMU ROM (a finding). If"
emit "dst is all-zero / unchanged, or the copy reported timeout/blocked, the"
emit "master-aware filter also covers CSUDMA (the expected negative)."
catch { uscale.dap dpreg 0 0x1e } _
emit ""

# ---------------------------------------------------------------------------
emit "## 3. Speculative ROM-alias candidates (low confidence, labelled)"
# ---------------------------------------------------------------------------
emit "No documented AXI base exists for the CSU BootROM; these are reset-vector /"
emit "low-alias guesses only. Treat any hit skeptically (could be OCM/DDR alias)."
foreach cand {0x00000000 0xFFFF0000} {
    set _w 0
    while {$_w < $NWORDS} { wr [expr {$OCM_DST + (4 * $_w)}] 0x00000000; incr _w }
    set _r [dma_copy $cand $OCM_DST $NWORDS]
    emit "cand [format 0x%08X $cand]: DAP-direct=[dump_words $cand 2] | dma=$_r dst=[dump_words $OCM_DST $NWORDS]"
    catch { uscale.dap dpreg 0 0x1e } _
}
emit ""
emit "## Done. Restoring SSS_CFG to 0 (idle)."
wr $SSS_CFG 0x00000000
close $fh
echo "Wrote $out"
