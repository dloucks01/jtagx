# JTAG chain discovery — for an unknown board.
#
# Enumerates whatever TAPs the loaded target config knows about, reads
# the DAP's access ports (APs), decodes their types, and suggests next
# steps based on TAP naming patterns. For the FULL CoreSight fabric map
# (every AP's ROM table + the components behind it — CTI/ETM/per-core
# debug), use openocd/coresight-topology.tcl.
#
# IDCODEs themselves are reported by OpenOCD's init in stderr lines like:
#   "Info : JTAG tap: NAME tap/device found: 0x24738093"
# Read those above the discovery output.
#
# For manual IDCODE decoding from the Tcl shell, the proc
# `describe_idcode 0x...` is loaded by this script — call it interactively.
#
# Usage examples are in openocd/discover.cfg.

source [file dirname [info script]]/lib/idcode-lookup.tcl

puts ""
puts "================================================================"
puts " JTAG CHAIN DISCOVERY"
puts "================================================================"
puts ""
puts "IDCODEs were printed by OpenOCD init above this output. Look for"
puts "lines like:"
puts "    Info : JTAG tap: NAME tap/device found: 0x........"
puts ""
puts "To decode any IDCODE interactively, run from this Tcl shell:"
puts "    describe_idcode 0x<value>"
puts ""

# --- Step 1: list all TAPs the OpenOCD config knows about ---
set tap_names [jtag names]
puts "----------------------------------------------------------------"
puts " TAPs defined in current OpenOCD target config"
puts "----------------------------------------------------------------"
puts ""
puts "Count: [llength $tap_names]"
foreach name $tap_names {
    puts "  - $name"
}
puts ""

# --- Step 2: enumerate APs visible via DAP (if a DAP TAP exists) ---
puts "----------------------------------------------------------------"
puts " ACCESS PORTS (APs) visible on each DAP"
puts "----------------------------------------------------------------"

# Find DAP objects
set dap_names {}
if {![catch {dap names} explicit_daps]} {
    set dap_names $explicit_daps
}

if {[llength $dap_names] == 0} {
    puts ""
    puts "No DAP objects found. Either:"
    puts "  - The target config didn't create one (e.g., plain Xilinx PS-TAP only)"
    puts "  - You're on non-ARM silicon (MIPS, RISC-V)"
    puts ""
} else {
    foreach d $dap_names {
        puts ""
        puts "DAP: $d"
        catch { $d dpreg 0 0x1e } _   ;# clear any sticky errors first
        set found_any 0
        for {set ap 0} {$ap < 8} {incr ap} {
            set idr_raw ""
            if {[catch {$d apreg $ap 0xFC} idr_raw]} { continue }
            set idr [string trim $idr_raw]
            if {![string is integer -strict $idr] || $idr == 0} { continue }
            set found_any 1
            # Decode AP type from IDR
            set ap_class [expr {($idr >> 13) & 0xF}]
            set ap_type  [expr {$idr & 0xF}]
            set ap_designer [expr {($idr >> 17) & 0x7FF}]
            set class_name "unknown"
            set type_name "unknown"
            switch -- $ap_class {
                8  { set class_name "MEM-AP" }
                0  { set class_name "JTAG-AP" }
            }
            if {$ap_class == 8} {
                switch -- $ap_type {
                    1 { set type_name "AHB3 (memory access)" }
                    2 { set type_name "APB2 or APB3 (debug-register access)" }
                    4 { set type_name "AXI3/AXI4 (memory access)" }
                    5 { set type_name "AHB5" }
                    6 { set type_name "APB4 or APB5" }
                    7 { set type_name "AXI5" }
                }
            }
            puts [format "  AP %d: IDR = 0x%08x  designer=0x%03x  class %d = %s  type %d = %s" \
                    $ap $idr $ap_designer $ap_class $class_name $ap_type $type_name]
        }
        if {!$found_any} {
            puts "  (no APs responded — DAP may be in sticky-error state; check DP CTRL/STAT)"
        }
    }
}

# --- Step 3: suggest next steps based on TAP naming heuristics ---
puts ""
puts "================================================================"
puts " SUGGESTED NEXT STEPS"
puts "================================================================"

set is_zynqmp 0
set is_zynq7  0
set is_versal 0
set has_dap   0
foreach name $tap_names {
    if {[string match "*uscale*" $name] || [string match "*zynqmp*" $name]} {
        set is_zynqmp 1
    }
    if {[string match "*zynq7*" $name] || [string match "*z7*" $name]} {
        set is_zynq7 1
    }
    if {[string match "*versal*" $name] || [string match "*pmc*" $name]} {
        set is_versal 1
    }
    if {[string match "*dap*" $name] || [string match "*tap*" $name]} {
        set has_dap 1
    }
}

if {$is_zynqmp} {
    puts ""
    puts "▸ Detected ZynqMP target config (TAPs named uscale.*)"
    puts ""
    puts "  Cross-reference the PS-TAP IDCODE from the init log with:"
    puts "      describe_idcode 0x........"
    puts ""
    puts "  Run the full enumeration:"
    puts "      openocd -f openocd/zcu102.cfg \\"
    puts "              -c \"init; source openocd/enumerate.tcl\""
    puts ""
    puts "  enumerate.tcl works for any ZynqMP-based board (ZCU10x,"
    puts "  Ultra96, custom, RFSoC) — SoC register map is identical."
} elseif {$is_zynq7} {
    puts ""
    puts "▸ Detected Zynq-7000 target config"
    puts ""
    puts "  enumerate.tcl does NOT work as-is — ZynqMP and Zynq-7000"
    puts "  have completely different SLCR / register addresses."
    puts ""
    puts "  Reference: UG585 (Zynq-7000 SoC TRM)."
    puts "  SLCR base 0xF8000000 (vs ZynqMP's 0xFF... range)."
    puts ""
    puts "  To adapt enumerate.tcl for Zynq-7000:"
    puts "    1. Copy enumerate.tcl"
    puts "    2. Replace all addresses with their Zynq-7000 equivalents per UG585"
    puts "    3. Update the part-ID lookup table for XC7Z* parts"
} elseif {$is_versal} {
    puts ""
    puts "▸ Detected Versal target config"
    puts ""
    puts "  Versal is fundamentally different from ZynqMP:"
    puts "    - PMC (Platform Management Controller) replaces PMU"
    puts "    - APU is Cortex-A72 (was A53)"
    puts "    - CDO boot format replaces FSBL"
    puts "    - New register map throughout"
    puts ""
    puts "  Reference: AM011 (Versal TRM)."
    puts "  enumerate.tcl is not portable — needs from-scratch rewrite."
} elseif {$has_dap} {
    puts ""
    puts "▸ Detected ARM CoreSight DAP but no recognized vendor TAP."
    puts ""
    puts "  This is a non-Xilinx ARM chip (NXP, ST, TI, Marvell, etc.)."
    puts "  The DAP itself follows standard ARM CoreSight architecture."
    puts "  AP enumeration above shows what's accessible."
    puts ""
    puts "  Look in /usr/share/openocd/scripts/target/ for vendor configs."
    puts "  Walk the CoreSight ROM table via 'dap info N' for each AP"
    puts "  to discover debug components without knowing the vendor."
} else {
    puts ""
    puts "▸ Unrecognized TAP layout."
    puts ""
    puts "  The init log above shows what TAPs responded. Cross-reference"
    puts "  their IDCODEs against:"
    puts "    - lib/idcode-lookup.tcl  (Xilinx + ARM common parts)"
    puts "    - JEP106 manufacturer list (for the mfg bits 11-1)"
    puts "    - Vendor-specific docs (look at part's IDCODE register)"
}
puts ""
puts "================================================================"
puts ""
