# watch-access.tcl — set a HW watchpoint on an address, run the target, and report the PC that TOUCHED it.
#
# Finds the CODE that reads/writes a secret: point it at where a key/flag/token lives (from dram-secrets.py
# or symbol-crypto.py) and it tells you the instruction that accesses it — the routine to reverse or patch.
# This is the dynamic counterpart to the static dumps.
#
# INVASIVE: halts the core to arm the watchpoint, resumes, and halts again on the hit. On a live OS the
# resume/halt cycle can disturb it; the project's lesson holds — avoid core-path memory ops, this only uses
# the core's debug watchpoint logic + reads the PC. Read-only w.r.t. memory.
#
# Env:
#   WA_CORE     core target to watch (default uscale.a53.0; Zynq-7000 zynq.cpu0; Cortex-M <chip>.cpu)
#   WA_ADDR     the address to watch (required)
#   WA_LEN      bytes (default 4)
#   WA_ACCESS   r | w | a  (read / write / any — default a)
#   WA_TIMEOUT  ms to wait for a hit (default 10000)
#
# Usage:  WA_ADDR=0x100a3f00 WA_ACCESS=r \
#           openocd -f openocd/zcu102.cfg -c "init; source openocd/watch-access.tcl; shutdown"

proc _envd {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
set CORE [_envd WA_CORE uscale.a53.0]
set ADDR [_envd WA_ADDR ""]
set LEN  [_envd WA_LEN 4]
set ACC  [_envd WA_ACCESS a]
set TMO  [_envd WA_TIMEOUT 10000]

echo ""
echo "================================================================"
echo " WATCHPOINT-ON-ACCESS  (core: $CORE)"
echo "================================================================"
if {$ADDR eq ""} { echo " ERROR: set WA_ADDR=<address to watch>."; return }
echo [format " watching %s  (%d bytes, access=%s) for up to %d ms" $ADDR $LEN $ACC $TMO]

# SMP-aware: ZynqMP A53s (and most Cortex-A clusters) form an SMP group, and OpenOCD requires EVERY core in
# the group halted before it will add a watchpoint (it programs the same DBGWCR on all cores). Halting only
# WA_CORE fails with "can't add ... target running". So halt all sibling cores sharing the base name, and
# resume them together. On a single-core target this collapses to just $CORE.
proc _smp_siblings {core} {
    set base [regsub {\.[0-9]+$} $core ""]
    set out {}
    foreach t [target names] { if {[string match "$base.*" $t] || $t eq $core} { lappend out $t } }
    if {[llength $out] == 0} { set out [list $core] }
    return $out
}
set SIBS [_smp_siblings $CORE]
echo " SMP cores to halt: $SIBS"
# The ZynqMP cfg only examines a53.0 at init; OpenOCD refuses to program a group watchpoint on an
# un-examined core ("Target not examined yet"). Examine each sibling first, then halt the whole group.
foreach t $SIBS { catch { $t arp_examine } _ ; catch { targets $t ; halt } _ }
catch { targets $CORE } _
if {[catch { $CORE curstate } st] || $st ne "halted"} {
    echo " ERROR: $CORE did not halt (state=$st). Core unreachable / running?"
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}

if {[catch { wp $ADDR $LEN $ACC } e]} {
    echo " ERROR: could not set the watchpoint ($e). Out of HW watchpoints, unsupported access type,"
    echo "        or not all SMP cores halted (cores: $SIBS)."
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}
echo " watchpoint armed — resuming the SMP group ..."
foreach t $SIBS { catch { targets $t ; resume } _ }
catch { targets $CORE } _

# poll for the watchpoint hit (the core halts on access)
set waited 0 ; set hit 0
while {$waited < $TMO} {
    if {![catch { $CORE curstate } st] && $st eq "halted"} { set hit 1 ; break }
    after 100 ; incr waited 100
}

echo "----------------------------------------------------------------"
if {$hit} {
    echo " HIT — the SMP group halted on access to $ADDR."
    echo "   Per-core PC (the core whose PC is in the accessing routine is the one that touched the memory):"
    foreach t $SIBS {
        catch { targets $t } _
        set cs "?" ; catch { $t curstate } cs
        set pc "?"
        if {![catch { reg pc } o] && [regexp {0x[0-9a-fA-F]+} $o m]} { set pc $m }
        echo [format "     %-16s state=%-8s pc=%s" $t $cs $pc]
    }
    catch { targets $CORE } _
    echo "   Disassemble around the accessing PC (Ghidra, load base from the vxworks-symtab map) to find the"
    echo "   routine that uses the secret. (Cap-2/patch-recipe can then NOP/neuter it.)"
} else {
    echo " no access within $TMO ms — nothing touched $ADDR in the window (raise WA_TIMEOUT, or it's idle)."
    foreach t $SIBS { catch { targets $t ; halt } _ }
}
catch { targets $CORE } _
catch { rwp $ADDR } _    ;# remove the watchpoint
foreach t $SIBS { catch { targets $t ; resume } _ }    ;# leave the whole group running
echo "================================================================"
