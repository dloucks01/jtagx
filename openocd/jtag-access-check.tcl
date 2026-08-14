# jtag-access-check.tcl — ENGAGEMENT FIRST QUESTION: is the JTAG/DAP actually OPEN on this
# board, or has the production security configuration locked or restricted it?
#
# This is the gate before enumerate.tcl. On the all-open dev board everything reads; on a
# hardened/tactical board you may find the DAP powered-down, secure-debug gating reads, or
# JTAG fused off entirely. This script answers that NON-DESTRUCTIVELY — it only reads:
#   1. the JTAG chain (TAP count)            -> is anything even responding?
#   2. each DAP's DP CTRL/STAT               -> is the debug domain powered + un-faulted?
#   3. each DAP's access ports (AP IDRs)     -> what memory/debug APs are exposed?
#   4. two benign always-mapped registers    -> can we actually read through it, or is it gated?
# and prints an ACCESS VERDICT + the recommended next command.
#
# Run after a board config has set up interface+transport+target, e.g.:
#   JTAG_IFACE=interface/jlink.cfg JTAG_SPEED=1000 \
#     openocd -f openocd/board-template.cfg \
#       -c "init; source openocd/jtag-access-check.tcl; shutdown"
#
# For the full TAP/AP dump use discover.tcl. For the security posture (only meaningful once
# this reports OPEN) use enumerate.tcl. See docs/18-new-board-bringup.md.

source [file dirname [info script]]/lib/idcode-lookup.tcl

proc ac {s} { puts $s }
proc ac_hdr {s} { puts ""; puts "================================================================"; puts " $s"; puts "================================================================" }

# Find the first DAP object, if the target config created one (works on unknown boards).
proc ac_first_dap {} {
    if {[catch {dap names} d]} { return "" }
    return [lindex $d 0]
}

# Clear DP sticky-error state on the given DAP so a faulted read doesn't poison the next.
proc ac_clear_sticky {dap} {
    if {$dap eq ""} { return }
    for {set i 0} {$i < 3} {incr i} { catch { $dap dpreg 0 0x1e } _ ; after 5 }
}

# Try to read a 32-bit word at addr via the AXI/active target. Returns value or "ERR".
proc ac_rd {addr dap} {
    if {[catch {read_memory $addr 32 1} v]} {
        ac_clear_sticky $dap
        return "ERR"
    }
    return [lindex $v 0]
}

ac_hdr "JTAG / DAP ACCESS CHECK (non-destructive)"
ac ""
ac "IDCODEs were printed by OpenOCD init above. Decode any of them with:"
ac "    describe_idcode 0x<value>"

# --- 1. chain present? ------------------------------------------------------------------
set taps {}
catch { set taps [jtag names] }
ac ""
ac "--- JTAG chain ---"
ac "  TAPs visible: [llength $taps]"
foreach t $taps { ac "    - $t" }

set verdict   "UNKNOWN"
set verdict_why ""
set next_cmd  ""

if {[llength $taps] == 0} {
    set verdict "NO-CHAIN"
    set verdict_why "No TAPs responded. Either JTAG is electrically dead (wiring/voltage/level-shift),\n  held in reset, or the chain is disabled by eFuse (JTAG_DIS / secure-debug)."
    set next_cmd "Recheck physical: pinout, Vref, GND, lead length; drop JTAG_SPEED to 200; verify SRST.\n  Then re-run. If IDCODEs still never appear on a powered board, suspect JTAG-disable eFuses."
}

# --- 2. DAP power + fault state ---------------------------------------------------------
set dap [ac_first_dap]
set dap_alive 0
if {[llength $taps] > 0} {
    ac ""
    ac "--- DAP DP CTRL/STAT (power + sticky-fault state) ---"
    if {$dap eq ""} {
        ac "  No DAP object created by the target config."
        ac "  -> non-Arm silicon, or a vendor PS-TAP with no Arm CoreSight DAP exposed."
        if {$verdict eq "UNKNOWN"} {
            set verdict "NO-DAP"
            set verdict_why "A JTAG chain exists but no Arm DAP is reachable. Could be a Xilinx PS-TAP\n  with the DAP gated, or non-ZynqMP silicon."
            set next_cmd "Run discover.tcl for the full TAP/AP picture and decode the IDCODE to identify the SoC."
        }
    } else {
        ac_clear_sticky $dap
        set ctrlstat "ERR"
        catch { set ctrlstat [$dap dpreg 0x4] }
        if {$ctrlstat eq "ERR" || ![string is integer -strict $ctrlstat]} {
            ac "  DP CTRL/STAT: unreadable ($ctrlstat) — DAP not answering DP reads."
            if {$verdict eq "UNKNOWN"} {
                set verdict "LOCKED"
                set verdict_why "JTAG chain present but the DAP will not answer even a DP read.\n  Consistent with a disabled/secured DAP."
                set next_cmd "Decode IDCODE (describe_idcode). If ZynqMP, this points at DAP-disable / secure-debug eFuses."
            }
        } else {
            set dap_alive 1
            # ADIv5 DP CTRL/STAT power-ack bits (active-high when the domain is up).
            set csyspwrupack [expr {($ctrlstat >> 31) & 1}]
            set cdbgpwrupack [expr {($ctrlstat >> 29) & 1}]
            set stickyerr    [expr {($ctrlstat >> 5)  & 1}]
            set stickyorun   [expr {($ctrlstat >> 1)  & 1}]
            ac [format "  DP CTRL/STAT = 0x%08x" $ctrlstat]
            ac "    CDBGPWRUPACK (debug power up,  bit 29) = $cdbgpwrupack"
            ac "    CSYSPWRUPACK (system power up, bit 31) = $csyspwrupack"
            ac "    STICKYERR (bit 5) = $stickyerr   STICKYORUN (bit 1) = $stickyorun"
            if {$cdbgpwrupack == 0} {
                ac "  NOTE: debug power-up not acknowledged — debug domain held down."
            }
        }
    }
}

# --- 3. access ports --------------------------------------------------------------------
set mem_aps 0
if {$dap_alive} {
    ac ""
    ac "--- Access ports on DAP $dap ---"
    ac_clear_sticky $dap
    for {set ap 0} {$ap < 8} {incr ap} {
        set idr ""
        if {[catch {$dap apreg $ap 0xFC} idr]} { continue }
        set idr [string trim $idr]
        if {![string is integer -strict $idr] || $idr == 0} { continue }
        set apclass [expr {($idr >> 13) & 0xF}]
        set cname "other"
        if {$apclass == 8} { set cname "MEM-AP" ; incr mem_aps }
        if {$apclass == 0} { set cname "JTAG-AP" }
        ac [format "  AP %d: IDR = 0x%08x  class %d (%s)" $ap $idr $apclass $cname]
    }
    if {$mem_aps == 0} { ac "  (no MEM-AP responded — memory access is unavailable through this DAP)" }
}

# --- 4. benign read probe (can we actually read non-secure registers?) ------------------
# Two always-mapped, non-secret ZynqMP registers. On a different SoC these will simply ERR
# and the verdict falls through to RESTRICTED/identify-the-part.
if {$dap_alive && $mem_aps > 0} {
    ac ""
    ac "--- Benign read probe (ZynqMP non-secure registers) ---"
    # Prefer the AXI mem-AP target if the config made one.
    if {![catch {targets uscale.axi} _]} { catch { uscale.axi arp_examine } _ }
    set bootmode [ac_rd 0xFF5E0200 $dap]   ;# CRL_APB BOOT_MODE_USER
    set crl_ver  [ac_rd 0xFF5E0070 $dap]   ;# CRL_APB reset/version area (benign)
    if {$bootmode ne "ERR"} {
        ac [format "  BOOT_MODE_USER (0xFF5E0200) = 0x%08x   (boot-mode pins = 0x%x)" $bootmode [expr {$bootmode & 0xF}]]
    } else {
        ac "  BOOT_MODE_USER (0xFF5E0200) = ERR (read faulted)"
    }
    if {$crl_ver ne "ERR"} {
        ac [format "  CRL_APB (0xFF5E0070)        = 0x%08x" $crl_ver]
    } else {
        ac "  CRL_APB (0xFF5E0070)        = ERR (read faulted)"
    }
    if {$bootmode ne "ERR" && $verdict eq "UNKNOWN"} {
        set verdict "OPEN"
        set verdict_why "DAP is powered, MEM-APs respond, and non-secure registers read back.\n  Full enumeration of the security posture is possible."
        set next_cmd "Run the enumeration:\n    openocd -f <board>.cfg -c \"init; source openocd/enumerate.tcl; shutdown\"\n  then interpret offline:\n    python3 tools/interpret.py \"\$(ls -t reports/raw-*.json | head -1)\" -O"
    } elseif {$bootmode eq "ERR" && $verdict eq "UNKNOWN"} {
        set verdict "RESTRICTED"
        set verdict_why "DAP and MEM-APs are present, but a basic non-secure register read faults.\n  Access is gated (XPPU/TrustZone/secure-debug) or this is not ZynqMP silicon."
        set next_cmd "Decode the IDCODE (describe_idcode) to confirm the SoC. If ZynqMP, the gating itself\n  is a finding — note WHICH reads fault. discover.tcl + 'dap info' map the reachable APs."
    }
}

# --- verdict ----------------------------------------------------------------------------
ac_hdr "ACCESS VERDICT: $verdict"
if {$verdict_why ne ""} { ac ""; ac "  $verdict_why" }
if {$next_cmd ne ""}    { ac ""; ac "  NEXT:"; ac "    $next_cmd" }
ac ""
ac "Reminder: on a production board, a verdict short of OPEN is itself a result — it means"
ac "the JTAG/debug access controls are doing their job. Document what faulted and why."
ac ""
