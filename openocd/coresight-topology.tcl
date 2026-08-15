# coresight-topology.tcl — enumerate the FULL CoreSight debug topology of the DAP: every Access Port,
# its ROM table, and the components behind it (cores, CTI cross-triggers, ETM/ETB trace, funnels, the
# per-core debug/PMU units). Depth beyond "the A53s halt" — it maps the whole debug fabric, which is
# where alternate debug entry points (RPU/CTI/trace) and cross-trigger implants live.
#
# Non-destructive: reads AP IDRs + ROM-table component-ID/peripheral-ID registers only.
#
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/coresight-topology.tcl; shutdown"
#
# CS_MAXAP  highest AP index to probe (default 8 — ZynqMP uses AP0 APB-AP, AP1 AHB-AP(AXI), AP2 JTAG-AP)

proc cs {s} { puts $s }
proc cs_hdr {s} { puts ""; puts "================================================================"; puts " $s"; puts "================================================================" }

proc cs_dap {} { if {[catch {dap names} d]} { return "" } ; return [lindex $d 0] }

set MAXAP 8
if {[info exists ::env(CS_MAXAP)]} { set MAXAP $::env(CS_MAXAP) }

set dap [cs_dap]
if {$dap eq ""} { cs "no DAP object (check the target cfg)"; return }

cs_hdr "CORESIGHT TOPOLOGY"

# AP class from the IDR: bits [16:13] TYPE, bit [0] class(1=MEM-AP). Decode the common ones.
proc cs_ap_kind {idr} {
    set cls [expr {($idr >> 13) & 0xf}]
    switch -- $cls {
        1 { return "AHB-AP (system memory / AXI)" }
        2 { return "APB-AP (debug APB — cores/CTI/ETM)" }
        4 { return "AXI-AP" }
        default { if {($idr & 0x1) == 0} { return "JTAG-AP / non-MEM" } ; return "MEM-AP (type $cls)" }
    }
}

set found 0
for {set ap 0} {$ap <= $MAXAP} {incr ap} {
    # AP IDR is bank 0xF reg 0xC -> apreg <ap> 0xFC
    if {[catch { $dap apreg $ap 0xFC } idr]} { continue }
    if {$idr == 0 || $idr eq ""} { continue }
    incr found
    cs [format " AP%-2d  IDR=0x%08X   %s" $ap $idr [cs_ap_kind $idr]]
    # For a MEM-AP, read its BASE (bank 0xF reg 0x8 -> apreg <ap> 0xF8) = the ROM table / first component.
    if {[catch { $dap apreg $ap 0xF8 } basev]} { continue }
    if {$basev ne "" && $basev != 0 && $basev != 0xFFFFFFFF} {
        set romb [expr {$basev & 0xFFFFF000}]
        cs [format "        ROM/base = 0x%08X" $romb]
        # let OpenOCD walk the ROM table for the richest decode (component + peripheral IDs, part names)
        cs "        --- dap info (ROM-table walk) ---"
        if {[catch { dap info $ap } info]} {
            cs "        (dap info $ap not available on this build)"
        } else {
            foreach ln [split $info "\n"] { if {[string trim $ln] ne ""} { cs "        $ln" } }
        }
    }
}
if {!$found} { cs " (no APs responded — DAP powered down or gated?)" }
cs ""
cs " topology map complete. Look for: per-core debug/PMU/CTI (APB-AP), the AXI mem-AP (dumps), a JTAG-AP"
cs " (PL/PMU alt path), and any ETM/ETB trace or extra CTI (cross-trigger = an alternate halt/exec lever)."
