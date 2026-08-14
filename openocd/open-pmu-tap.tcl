# open-pmu-tap.tcl — attempt to expose the PMU MicroBlaze BSCAN TAP by opening the
# JTAG_SEC.SSSS_PMU_SEC gate, then report whether the unlock stuck. NON-DESTRUCTIVE
# (one MMIO write to a JTAG-security gate; no reset/halt/core-release).
#
# Run with the standard 2-TAP config; the write goes via the AXI-AP (A53 not needed):
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/open-pmu-tap.tcl; shutdown"
# Then — WITHOUT power-cycling — re-scan the chain to see if a 3rd TAP appeared:
#   openocd -f openocd/zcu102-3tap.cfg -c "init; scan_chain; shutdown"
#
# Mechanism (corrected 2026-06-10 against zynqmp_pmufw/src/csu.h):
#   JTAG_SEC (0xFFCA0038): SSSS_PMU_SEC = bits [8:6] (mask 0x1C0). Writing 0b111 opens the PMU
#   security gate. (The old theory that JTAG_CHAIN_CFG=0x07 / JTAG_CHAIN_STATUS bit 2 link the
#   PMU TAP is WRONG — csu.h shows those regs only manage ARM_DAP[1]/PL_TAP[0], no PMU bit.)
#   Whether opening PMU_SEC actually inserts the MicroBlaze BSCAN TAP into the scan chain is the
#   open empirical question this probe sets up — confirm with the 3-TAP scan above.
#
# "Assume hardened" behavior: on a provisioned board PMU_SEC is eFuse-locked and the write will
# NOT stick — this probe READS BACK and reports that as a clean finding (the gate is enforcing),
# rather than assuming success.
#
# IMPORTANT honest scope: even if a 3rd TAP appears, DRIVING the PMU MicroBlaze debug module
# (MDM) over BSCAN to halt it and read the PMU ROM is a SEPARATE, much harder step — OpenOCD has
# weak/no native MicroBlaze support. This probe only establishes whether the TAP can be exposed.

set JTAG_SEC          0xFFCA0038
set JTAG_CHAIN_CFG    0xFFCA0030
set JTAG_CHAIN_STATUS 0xFFCA0034
set PMU_SEC_MASK      0x1C0   ;# bits 8-6
set PMU_SEC_OPEN      0x1C0   ;# 0b111 in bits 8-6

proc clr_sticky {} { for {set i 0} {$i < 3} {incr i} { catch { uscale.dap dpreg 0 0x1e } _ ; after 5 } }
proc rd {a} { if {[catch {read_memory $a 32 1} v]} { clr_sticky; return "ERR" } ; return [lindex $v 0] }
proc wr {a v} { if {[catch {write_memory $a 32 [list $v]} e]} { clr_sticky; return "ERR" } ; return "ok" }
proc hx {v} { if {$v eq "ERR"} { return "ERR" } ; return [format "0x%08X" $v] }

# Use the AXI-AP for MMIO (no core release needed).
catch { targets uscale.axi } _
catch { uscale.axi arp_examine } _

puts ""
puts "================================================================"
puts " OPEN PMU BSCAN TAP — JTAG_SEC.SSSS_PMU_SEC unlock attempt"
puts "================================================================"

set sec_before   [rd $JTAG_SEC]
set cfg_before   [rd $JTAG_CHAIN_CFG]
set stat_before  [rd $JTAG_CHAIN_STATUS]
puts ""
puts "BEFORE:"
puts "  JTAG_SEC          (0xFFCA0038) = [hx $sec_before]"
if {$sec_before ne "ERR"} {
    set pmu_b [expr {($sec_before >> 6) & 0x7}]
    puts "      SSSS_PMU_SEC (bits 8-6) = [format 0x%X $pmu_b]   (0x7 = open, 0x0 = sealed)"
}
puts "  JTAG_CHAIN_CFG    (0xFFCA0030) = [hx $cfg_before]   (ARM_DAP bit 1 / PL_TAP bit 0)"
puts "  JTAG_CHAIN_STATUS (0xFFCA0034) = [hx $stat_before]"

if {$sec_before eq "ERR"} {
    puts ""
    puts "VERDICT: JTAG_SEC unreadable — DAP not answering MMIO. Cannot attempt the unlock."
    puts "================================================================"
    return
}

# Open PMU_SEC, preserving the other SSSS gates.
set sec_new [expr {($sec_before & ~$PMU_SEC_MASK) | $PMU_SEC_OPEN}]
puts ""
puts ">> writing JTAG_SEC = [format 0x%08X $sec_new]  (set SSSS_PMU_SEC = 0b111)"
set w [wr $JTAG_SEC $sec_new]
if {$w eq "ERR"} {
    puts "VERDICT: JTAG_SEC WRITE FAULTED — write rejected or DAP wedged."
    puts "================================================================"
    return
}

set sec_after  [rd $JTAG_SEC]
set stat_after [rd $JTAG_CHAIN_STATUS]
puts ""
puts "AFTER:"
puts "  JTAG_SEC          = [hx $sec_after]"
puts "  JTAG_CHAIN_STATUS = [hx $stat_after]"

set pmu_a "ERR"
if {$sec_after ne "ERR"} { set pmu_a [expr {($sec_after >> 6) & 0x7}] }

puts ""
puts "================================================================"
if {$pmu_a eq "ERR"} {
    puts " VERDICT: readback faulted after write — inconclusive."
} elseif {$pmu_a == 0x7} {
    puts " VERDICT: PMU_SEC OPENED (reads 0b111). The security gate is unlocked."
    puts ""
    puts " NEXT (do NOT power-cycle): re-scan the chain for the PMU BSCAN TAP —"
    puts "   openocd -f openocd/zcu102-3tap.cfg -c \"init; scan_chain; shutdown\""
    puts " Expect total IR length 20 / 3 TAPs if the MicroBlaze BSCAN TAP linked in;"
    puts " 16 / 2 TAPs means PMU_SEC gates DEBUG access but NOT scan-chain presence"
    puts " (i.e. the BSCAN-TAP route is closed even with the gate open — a real finding)."
} else {
    puts " VERDICT: PMU_SEC did NOT open (wrote 0b111, reads [format 0x%X $pmu_a])."
    puts " The gate is enforcing — on a hardened/provisioned board this is eFuse-locked,"
    puts " the expected secure behavior. The PMU-TAP unlock lever is closed on this part."
}
puts "================================================================"
puts ""
