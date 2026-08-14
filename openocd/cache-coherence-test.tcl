# cache-coherence-test.tcl — empirically prove, on live silicon, that (1) an AXI-AP code write executes,
# (2) the A53 I-cache goes STALE after that code runs (the "patch landed but isn't behavioral" gap), and
# (3) the cache-flush.bin payload makes a fresh AXI code write coherent again (the fix for the gap).
#
# It touches NO VxWorks function. It uses a cold kernel-.text scratch (armWarmReboot — a reboot handler that
# never runs, so it is mapped-executable but absent from the I-cache) and runs only OUR OWN tiny stubs there,
# saving/restoring every byte + the borrowed core's full context. The whole A53 cluster is halted for the
# window (like watch-access.tcl) so no other core can deadlock on a lock core 0 might hold.
#
#   stub-A = mov x0,#0xAAAA ; brk      stub-B = mov x0,#0xBBBB ; brk      cache-flush.bin = DC CIVAC/IC IVAU
#
#   1. write A to scratch1, run -> x0 should be 0xAAAA      (AXI-written code executes)
#   2. overwrite scratch1 with B (DRAM=B, I-cache still=A), run -> x0 STILL 0xAAAA   (I-cache STALE = the gap)
#   3. run cache-flush over scratch1's line, run B again -> x0 should be 0xBBBB        (flush = coherent fix)
#
# Run: openocd -f openocd/zcu102.cfg -c "init; source openocd/cache-coherence-test.tcl; shutdown"
#
# !!! EMPIRICAL RESULT (ZCU102, VxWorks, OpenOCD 0.12, 2026-06-12) !!!
# This WEDGES the DAP ("Invalid ACK (0)" cascade) the moment it hijacks a live core's PC to run the stub —
# reproduced with both single-core and whole-cluster resume. The wedge is NON-FATAL: a fresh `openocd init`
# clears it and the cores resume (VxWorks survives; the scratch .text writes fail so nothing is corrupted).
# CONCLUSION: running arbitrary code on a LIVE core over JTAG is not viable on this ZynqMP/OpenOCD 0.12 (the
# same "live code injection blocked" limitation noted across the project). Therefore an in-place behavioral
# patch over JTAG is NOT achievable live here — the guaranteed behavioral-patch path is Cap-3: patch the boot
# image + reflash (coherence is moot — the bytes are in flash before any cache exists). cache-flush.S is
# retained as a correct primitive for contexts where core code-exec IS available (COLD inject / owned core /
# better tooling). Kept as a documented, reproducible probe — do not run it expecting a clean pass on HW.

set CORE   uscale.a53.0
set AXI    uscale.axi
# cold scratch in kernel .text (armWarmReboot @ VA ..0019C, next sym vxMmuEarlyEnable @ ..002C8 -> 300B room)
set S1_VA  0xFFFFFFFF8010019C        ;# test stub (its own 64B line is 0x...180)
set S1_PA  0x0010019C
set S2_VA  0xFFFFFFFF801001C0        ;# cache-flush payload (separate 64B line 0x...1C0)
set S2_PA  0x001001C0
set STUB_A {0xd2955540 0xd4200000}   ;# mov x0,#0xAAAA ; brk #0
set STUB_B {0xd2977760 0xd4200000}   ;# mov x0,#0xBBBB ; brk #0
set FLUSH  {0x927ae403 0xaa0303e4 0xd50b7e23 0x91010063 0xeb01007f 0x54ffffa3 0xd5033b9f 0xaa0403e3 0xd50b7523 0x91010063 0xeb01007f 0x54ffffa3 0xd5033b9f 0xd5033fdf 0xd4200000}

proc _regval {name} {
    if {![catch { get_reg $name } d]} {
        if {[catch { dict get $d $name } v]} { set v $d }
        if {[regexp {0x[0-9a-fA-F]+} $v m]} { return $m }
    }
    if {![catch { reg $name } o] && [regexp {0x[0-9a-fA-F]+} $o m]} { return $m }
    return ""
}
proc _smp_siblings {core} {
    set base [regsub {\.[0-9]+$} $core ""]
    set out {}
    foreach t [target names] { if {[string match "$base.*" $t] || $t eq $core} { lappend out $t } }
    if {[llength $out] == 0} { set out [list $core] }
    return $out
}

echo ""
echo "================================================================"
echo " CACHE-COHERENCE TEST  (AXI code write vs A53 I-cache; flush fix)"
echo "================================================================"

set SIBS [_smp_siblings $CORE]
echo " freezing cluster: $SIBS"
foreach t $SIBS { catch { $t arp_examine } _ ; catch { targets $t ; halt } _ }
catch { targets $CORE } _
if {[catch { $CORE curstate } st] || $st ne "halted"} {
    echo " ERROR: $CORE did not halt (state=$st)."
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}

# --- save the borrowed core's VxWorks context (everything our stubs/flush touch) ---
array set SV {}
foreach r {pc x0 x1 x2 x3 x4} { set SV($r) [_regval $r] }
echo " saved core0 ctx: pc=$SV(pc) x0=$SV(x0) x1=$SV(x1)"

# --- save original scratch bytes ---
catch { targets $AXI } _
if {[catch { read_memory $S1_PA 32 2 } ORIG1] || [catch { read_memory $S2_PA 32 15 } ORIG2]} {
    echo " ERROR: could not read scratch ($S1_PA / $S2_PA). Aborting without changes."
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}
echo " saved scratch: S1(2w)=$ORIG1  S2(15w)=[lrange $ORIG2 0 2]..."

# --- borrow core0 to run code at a VA; returns x0 after it BRKs (or "" on timeout). Resumes the WHOLE
# cluster (single-core resume of an SMP "multi core" unit wedges the DAP via the CTI); core0's BRK
# cross-halts the group, exactly like break-capture.tcl's proven resume-group + HW-breakpoint flow. ---
proc _run {core va {x0 ""} {x1 ""}} {
    global SIBS
    catch { targets $core } _
    catch { reg pc $va } _
    if {$x0 ne ""} { catch { reg x0 $x0 } _ }
    if {$x1 ne ""} { catch { reg x1 $x1 } _ }
    foreach t $SIBS { catch { targets $t ; resume } _ }
    catch { targets $core } _
    set waited 0
    while {$waited < 3000} {
        if {![catch { $core curstate } s] && $s eq "halted"} { break }
        after 20 ; incr waited 20
    }
    if {[catch { $core curstate } s] || $s ne "halted"} { return "" }
    return [_regval x0]
}

proc _wax {axi pa words} { catch { targets $axi } _ ; catch { write_memory $pa 32 $words } _ }

# preload the flush payload into scratch2 (its line is cold -> executes from DRAM cleanly)
_wax $AXI $S2_PA $FLUSH

set R_A "" ; set R_STALE "" ; set R_FIXED ""

# step 1: A -> run
_wax $AXI $S1_PA $STUB_A
set R_A [_run $CORE $S1_VA]

# step 2: overwrite with B (no flush) -> run  (I-cache should still hold A)
_wax $AXI $S1_PA $STUB_B
set R_STALE [_run $CORE $S1_VA]

# step 3: flush scratch1's line, then run B again
set s1_end [format 0x%x [expr {$S1_PA + 8}]]
_run $CORE $S2_VA $S1_PA $s1_end
set R_FIXED [_run $CORE $S1_VA]

# --- restore scratch + core context, resume cluster ---
_wax $AXI $S1_PA $ORIG1
_wax $AXI $S2_PA $ORIG2
catch { targets $CORE } _
foreach r {pc x0 x1 x2 x3 x4} { if {$SV($r) ne ""} { catch { reg $r $SV($r) } _ } }
foreach t $SIBS { catch { targets $t ; resume } _ }

# --- verdict ---
proc _eq {v want} { if {$v eq ""} { return 0 } ; return [expr {($v & 0xFFFF) == $want}] }
echo "----------------------------------------------------------------"
echo [format " step 1  AXI-write A, run      -> x0 = %-18s  (want 0xAAAA: AXI code executes)" $R_A]
echo [format " step 2  AXI-write B, NO flush -> x0 = %-18s  (0xAAAA => I-cache STALE = the gap)" $R_STALE]
echo [format " step 3  cache-flush, run B    -> x0 = %-18s  (want 0xBBBB: flush made it coherent)" $R_FIXED]
echo "----------------------------------------------------------------"
if {[_eq $R_A 0xAAAA] && [_eq $R_STALE 0xAAAA] && [_eq $R_FIXED 0xBBBB]} {
    echo " VERDICT: PROVEN end-to-end — an AXI code write is NOT coherent with the I-cache (step 2 stale),"
    echo "   and cache-flush.bin FIXES it (step 3 sees the new code). Cap-2 in-place patches are behavioral"
    echo "   ONLY when followed by this flush (or baked in via Cap-3 reflash)."
} elseif {[_eq $R_A 0xAAAA] && [_eq $R_STALE 0xBBBB]} {
    echo " VERDICT: this scratch line was already coherent (step 2 saw B without a flush) — the I-cache did"
    echo "   not retain the stale line here. The flush is still correct/needed for lines that DO stick."
} else {
    echo " VERDICT: INCONCLUSIVE — see the x0 values above (a run may have timed out: empty = no BRK hit)."
}
echo " core context + scratch .text restored; cluster resumed."
echo "================================================================"
