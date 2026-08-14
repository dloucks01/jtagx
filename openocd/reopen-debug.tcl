# reopen-debug.tcl — re-open a SOFTWARE-hardened ZynqMP's debug gates by writing them back to the
# all-open state via the AXI-AP, with read-back confirmation. The workflow for a hardened (no-eFuse)
# target: psu_init/FSBL closes CSU.JTAG_SEC + CSU.JTAG_DAP_CFG at boot, but if those bits aren't
# eFuse-locked they're just mutable register state — write them back open and debug is restored.
#
# This is also a DIAGNOSTIC — the read-back tells you which kind of hardening you're facing:
#   write sticks   -> software-closed, RE-OPENED          (reversible — the common no-eFuse case)
#   write ignored  -> eFuse-locked / write-protected      (NOT reversible via register write)
#   write faults   -> no AXI-AP write path                (use a code-exec path: EL3/EL1 write)
#
# Gates written:
#   CSU.JTAG_SEC      (0xFFCA0038): SSSS_DAP_SEC (bits 2-0) / PLTAP_SEC (bits 5-3) /
#                                   PMU_SEC (bits 8-6) -> 0b111 each
#   CSU.JTAG_DAP_CFG  (0xFFCA003C): APU+RPU DBGEN/NIDEN/SPIDEN/SPNIDEN -> all enabled (0xFF)
# (DAP_SEC re-links the ARM DAP; APU_DBGEN re-enables A53 invasive debug — halt/inspect/inject.)
#
# Requires the AXI-AP reachable (the mem-AP is frequently up even when *core debug* is gated). If
# the AXI-AP itself is closed, the fallback is code execution on the running OS writing these same
# CSU registers from EL3/EL1.
#
# Run: openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-debug.tcl; shutdown"
# Non-destructive on an already-open dev board; a power-cycle restores the boot-time gate state
# regardless. On a target, this is the intended unlocking action.

# CSU addresses are universal across all ZynqMP (UltraScale+) parts. The target/DAP object NAMES are
# board-cfg-specific — board-profile.tcl auto-detects them (and loads any boards/<soc>.env), so this
# script is not tied to the ZCU102 cfg. Override via env AXI_TARGET / DAP_NAME if ever needed.
source [file join [file dirname [info script]] board-profile.tcl]

set JTAG_SEC      0xFFCA0038
set JTAG_DAP_CFG  0xFFCA003C
set SEC_OPEN      0x1FF   ;# DAP_SEC|PLTAP_SEC|PMU_SEC all 0b111
set DAP_OPEN      0xFF    ;# APU+RPU DBGEN/NIDEN/SPIDEN/SPNIDEN

proc clr {} { for {set i 0} {$i < 3} {incr i} { catch { $::DAP_NAME dpreg 0 0x1e } _ ; after 5 } }
proc rd {a} { if {[catch {read_memory $a 32 1} v]} { clr; return "ERR" } ; return [lindex $v 0] }
proc wr {a v} { if {[catch {write_memory $a 32 [list $v]} e]} { clr; return "ERR" } ; return "ok" }
proc hx {v} { if {$v eq "ERR"} { return "ERR" } ; return [format "0x%08X" $v] }
proc okstr {v} { if {$v == 1} { return "OPEN" } elseif {$v eq "na"} { return "n/a" } else { return "LOCKED" } }

catch { targets $AXI_TARGET } _
catch { $AXI_TARGET arp_examine } _

puts ""
puts "================================================================"
puts " RE-OPEN DEBUG GATES  (software-hardened-target workflow)"
puts "================================================================"

# ---- JTAG_SEC (DAP / PLTAP / PMU security gates) ----
# JTAG_SEC is three independent 3-bit fields. They are read-back-checked PER FIELD, not as one
# all-or-nothing 0x1FF mask: an eFuse-locked PMU_SEC (the common case, and this rig's case) must
# NOT mask a DAP_SEC that actually opened. sec_ok tracks DAP_SEC specifically — the field that
# (re)links the ARM DAP and so gates A53/R5 core debug. PLTAP_SEC/PMU_SEC are reported separately
# (they gate the PL TAP and the PMU BSCAN/PMU-ROM path, which are rarely on the critical path).
set sec0 [rd $JTAG_SEC]
puts ""
puts "JTAG_SEC          (0xFFCA0038) before = [hx $sec0]"
set sec_ok   "na"   ;# DAP_SEC  — ARM DAP link (the one that matters for core debug)
set pltap_ok "na"   ;# PLTAP_SEC — PL TAP
set pmu_ok   "na"   ;# PMU_SEC  — PMU BSCAN / PMU ROM path (commonly eFuse-locked)
if {$sec0 eq "ERR"} {
    puts "    -> unreadable: no AXI-AP path. Re-open these via a code-exec path (EL3/EL1) instead."
} else {
    puts "    before:  DAP_SEC=[format 0x%X [expr {$sec0 & 0x7}]]  PLTAP_SEC=[format 0x%X [expr {($sec0 >> 3) & 0x7}]]  PMU_SEC=[format 0x%X [expr {($sec0 >> 6) & 0x7}]]   (0x7 = open per field)"
    set sec_new [expr {$sec0 | $SEC_OPEN}]
    puts ">> writing JTAG_SEC = [format 0x%08X $sec_new]"
    if {[wr $JTAG_SEC $sec_new] eq "ERR"} {
        set sec_ok 0; set pltap_ok 0; set pmu_ok 0
        puts "    -> write FAULTED (no AXI-AP write path)"
    } else {
        set sec1 [rd $JTAG_SEC]
        puts "JTAG_SEC          after  = [hx $sec1]"
        if {$sec1 eq "ERR"} {
            set sec_ok 0; set pltap_ok 0; set pmu_ok 0
            puts "    -> unreadable after write"
        } else {
            # each 3-bit field must reach 0x7 on its own to count as open
            if {($sec1 & 0x7)        == 0x7} { set sec_ok 1 }   else { set sec_ok 0 }
            if {(($sec1 >> 3) & 0x7) == 0x7} { set pltap_ok 1 } else { set pltap_ok 0 }
            if {(($sec1 >> 6) & 0x7) == 0x7} { set pmu_ok 1 }   else { set pmu_ok 0 }
            puts [format "    DAP_SEC   %-6s  (ARM DAP link — gates A53/R5 core debug)"      [okstr $sec_ok]]
            puts [format "    PLTAP_SEC %-6s  (PL TAP)"                                       [okstr $pltap_ok]]
            puts [format "    PMU_SEC   %-6s  (PMU BSCAN / PMU ROM — commonly eFuse-locked)" [okstr $pmu_ok]]
            if {$sec_ok == 1 && $pltap_ok == 1 && $pmu_ok == 1} {
                puts "    -> all JTAG_SEC gates now OPEN"
            } elseif {$sec_ok == 1} {
                puts "    -> DAP_SEC opened (core debug reachable); the locked field(s) are eFuse — usually fine"
            } else {
                puts "    -> DAP_SEC did NOT stick: eFuse-locked / write-protected (not reversible here)"
            }
        }
    }
}

# ---- JTAG_DAP_CFG (debug authorization enables) ----
set dap0 [rd $JTAG_DAP_CFG]
puts ""
puts "JTAG_DAP_CFG      (0xFFCA003C) before = [hx $dap0]"
set dap_ok "na"
if {$dap0 eq "ERR"} {
    puts "    -> unreadable: no AXI-AP path."
} else {
    puts "    APU_DBGEN=[expr {$dap0 & 1}]  APU_SPIDEN=[expr {($dap0 >> 2) & 1}]  RPU_DBGEN=[expr {($dap0 >> 4) & 1}]   (1 = debug authorized)"
    puts ">> writing JTAG_DAP_CFG = [format 0x%08X $DAP_OPEN]"
    if {[wr $JTAG_DAP_CFG $DAP_OPEN] eq "ERR"} {
        set dap_ok 0; puts "    -> write FAULTED"
    } else {
        set dap1 [rd $JTAG_DAP_CFG]
        puts "JTAG_DAP_CFG      after  = [hx $dap1]"
        if {$dap1 ne "ERR" && ($dap1 & $DAP_OPEN) == $DAP_OPEN} {
            set dap_ok 1; puts "    -> APU+RPU invasive/secure debug now ENABLED"
        } else {
            set dap_ok 0; puts "    -> did NOT stick: eFuse-locked / write-protected"
        }
    }
}

# ---- verdict ----
puts ""
puts "================================================================"
if {$sec_ok eq "na" && $dap_ok eq "na"} {
    puts " VERDICT: NO AXI-AP WRITE PATH — the debug-register interface isn't reachable."
    puts "   Re-open via a code-exec path: run EL3/EL1 code that writes JTAG_SEC=0x1FF and"
    puts "   JTAG_DAP_CFG=0xFF (e.g. a kernel module, or inject.tcl once a core is releasable)."
} elseif {$sec_ok == 1 && $dap_ok == 1} {
    # DAP_SEC + APU/RPU debug-enable both open = ARM core debug fully restored, REGARDLESS of
    # whether PLTAP_SEC/PMU_SEC stuck (those gate the PL TAP / PMU paths, not ARM core debug).
    if {$pltap_ok == 1 && $pmu_ok == 1} {
        puts " VERDICT: DEBUG RE-OPENED (all gates). The hardening was software register state."
    } else {
        puts " VERDICT: DEBUG RE-OPENED (ARM core debug). DAP_SEC + APU/RPU debug are open;"
        puts "   PLTAP_SEC=[okstr $pltap_ok] PMU_SEC=[okstr $pmu_ok] (eFuse-locked — gate PL/PMU only, usually irrelevant)."
    }
    puts "   The ARM DAP is re-linked and APU/RPU debug is authorized — you can now halt cores,"
    puts "   inspect/inject (probe-phys-patch, inject.tcl), and enumerate the full posture."
} elseif {$sec_ok == 0 && $dap_ok == 0} {
    puts " VERDICT: LOCKED. DAP_SEC + the APU/RPU debug-enables are eFuse-protected — writes don't stick."
    puts "   Not reversible by software. Only fault injection / invasive attacks remain (out of"
    puts "   pure-JTAG scope). See docs/15 for the hardware-tier avenues."
    puts "   NOTE: the AXI-AP mem path may still be up — re-check enumerate / qspi-jtag / dump-os-ddr,"
    puts "   which need only the mem-AP, not core debug."
} else {
    puts " VERDICT: PARTIAL — DAP_SEC reopened=[okstr $sec_ok]  JTAG_DAP_CFG(APU/RPU) reopened=[okstr $dap_ok]."
    puts "   One gate is mutable software state, the other eFuse-locked. Work with what opened —"
    puts "   the AXI-AP mem path often still gives full memory R/W even without core debug, which is"
    puts "   enough for enumerate, qspi-jtag flash dump, dump-os-ddr, and AXI-AP physical patching"
    puts "   (compute the target PA offline from the dumped image instead of live virt2phys)."
}
puts "================================================================"
puts ""
