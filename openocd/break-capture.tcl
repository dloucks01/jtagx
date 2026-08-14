# break-capture.tcl — set a HW breakpoint on a function/VA, resume the target, and on the hit DUMP the
# CPU register file (x0-x30, sp, pc, pstate) + optionally DEREFERENCE the argument-register pointers.
#
# This catches a secret IN FLIGHT — the password being compared, the AES key in x1, the buffer x0 points
# at — which the static scanners (mem-search / dram-secrets / symbol-crypto) can never see because it only
# exists in registers/stack at the moment the function runs. It is the dynamic complement to those tools and
# to watch-access.tcl (which gives only the PC that touched a data address; this gives the live arguments).
#
# SMP-aware: like watch-access.tcl, the ZynqMP A53s are an SMP group, so OpenOCD needs EVERY core in the
# cluster examined + halted before it will program the breakpoint. We examine+halt the whole cluster, arm,
# resume the group, and on the hit identify the core whose PC == the breakpoint and dump ITS context.
#
# INVASIVE: halts/resumes the cluster around each hit (the debug logic only — no memory ops through the core;
# deref reads go via the AXI mem-AP). On a live OS the brief halt is normally transparent.
#
# Env:
#   BC_CORE      a core in the target cluster (default uscale.a53.0; the SMP siblings are auto-detected)
#   BC_ADDR      VA(s) to break on (required) — ONE or MORE function entries, space/comma separated (max 6
#                HW breakpoints). Multiple addresses arm a tracer across the set. CAVEAT: OpenOCD's SMP
#                step-over disables all HW bps during the over-step and re-arms only the one at the halt PC,
#                so when two armed bps sit in a tight caller/callee chain the inner one can be missed and the
#                trace favors the first — reliable for tracing INDEPENDENT functions, less so for a tight pair.
#   BC_TRACE     1 = compact one-line-per-hit trace (which fn + x0-x3) instead of a full register dump
#   BC_COND      filter "xN ==|!= VAL" — only capture hits where it holds (e.g. BC_COND="x0 == 0x1"); with a
#                filter the loop keeps going (up to BC_MAXHITS cycles) until BC_COUNT hits PASS it
#   BC_TIMEOUT   ms to wait for each hit (default 15000)
#   BC_COUNT     number of hits to capture before removing the breakpoint (default 1)
#   BC_DEREF     arg-register indices to dereference as pointers, e.g. "0 1 2" (default "0 1 2 3");
#                empty/"none" = don't dereference. AAPCS64: x0..x7 are the first 8 integer args.
#   BC_DEREF_LEN bytes to read at each pointer (default 64)
#   BC_AXI       mem-AP target for the deref reads (default uscale.axi; Zynq-7000: zynq.axi)
#   BC_KVA_LO    linear-map base for VA->PA on deref (default 0x80000000; PA = (VA & 0xFFFFFFFF) - this).
#                Only kernel-linear-mapped pointers deref cleanly; a stack/heap VA outside that range is
#                shown but not read (set BC_KVA_LO to match, or read it another way).
#
# Usage:
#   BC_ADDR=0xffffffff8023ce14 BC_DEREF="0 1" \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/break-capture.tcl; shutdown"
#   # decode any captured PC/pointer with the symbol map: tools/vxworks-symtab.py / Ghidra.

proc _envd {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
set CORE    [_envd BC_CORE uscale.a53.0]
set ADDR    [_envd BC_ADDR ""]
set TMO     [_envd BC_TIMEOUT 15000]
set COUNT   [_envd BC_COUNT 1]
set DEREF   [_envd BC_DEREF "0 1 2 3"]
set DLEN    [_envd BC_DEREF_LEN 64]
set AXI     [_envd BC_AXI uscale.axi]
set KVA_LO  [_envd BC_KVA_LO 0x80000000]
set BT      [_envd BC_BT 0]            ;# 1 = walk the AArch64 frame-pointer chain -> caller backtrace
set BTDEPTH [_envd BC_BTDEPTH 16]      ;# max frames to unwind
set TRACE   [_envd BC_TRACE 0]         ;# 1 = compact one-line-per-hit trace (x0-x3) instead of a full dump
set COND    [_envd BC_COND ""]         ;# filter "xN ==|!= VAL" -> only capture hits where it holds
set MAXHITS [_envd BC_MAXHITS 200]     ;# with a filter, max resume cycles before giving up

echo ""
echo "================================================================"
echo " BREAKPOINT + REGISTER CAPTURE  (core cluster: $CORE)"
echo "================================================================"
if {$ADDR eq ""} { echo " ERROR: set BC_ADDR=<VA to break on> (a function entry)."; return }

# --- SMP cluster: examine + halt every sibling (see watch-access.tcl for why) ---
proc _smp_siblings {core} {
    set base [regsub {\.[0-9]+$} $core ""]
    set out {}
    foreach t [target names] { if {[string match "$base.*" $t] || $t eq $core} { lappend out $t } }
    if {[llength $out] == 0} { set out [list $core] }
    return $out
}
set SIBS [_smp_siblings $CORE]
echo " SMP cores: $SIBS"
foreach t $SIBS { catch { $t arp_examine } _ ; catch { targets $t ; halt } _ }
catch { targets $CORE } _
if {[catch { $CORE curstate } st] || $st ne "halted"} {
    echo " ERROR: $CORE did not halt (state=$st)."
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}

# --- arm a hardware breakpoint on each requested VA (BC_ADDR may be a space/comma list; max 6 on the A53) ---
regsub -all {,} $ADDR " " ADDR
set ADDRS {} ; foreach a $ADDR { if {$a ne ""} { lappend ADDRS $a } }
set armed {}
foreach a $ADDRS {
    if {[catch { bp $a 4 hw } e]} {
        echo " WARN: could not arm breakpoint at $a ($e). Out of HW breakpoints (6 max), or bad address?"
    } else { lappend armed $a }
}
if {[llength $armed] == 0} {
    echo " ERROR: no breakpoints armed."
    foreach t $SIBS { catch { targets $t ; resume } _ } ; return
}
set _cmsg "" ; if {$COND ne ""} { set _cmsg "  filter: $COND" }
echo [format " %d HW breakpoint(s) armed: %s" [llength $armed] $armed]
echo [format " capturing up to %d hit(s), %d ms each.%s" $COUNT $TMO $_cmsg]

# read one register value as an integer; "" on failure. MUST use `reg <name>` (it FORCES a target read of
# that single register) — get_reg returns OpenOCD's lazily-cached value, which on aarch64 is an unfetched 0
# for everything except x0/x1/pc/cpsr after a halt (the bug that made sp/x29/x30 read 0 and broke unwinding).
proc _regval {name} {
    if {![catch { reg $name } o] && [regexp {0x[0-9a-fA-F]+} $o m]} { return $m }
    if {![catch { get_reg $name } d]} {
        if {[catch { dict get $d $name } v]} { set v $d }
        if {[regexp {0x[0-9a-fA-F]+} $v m]} { return $m }
    }
    return ""
}

# which sibling halted AT the breakpoint (PC == ADDR)? falls back to the first halted core.
proc _hitter {sibs addr} {
    set anyhalt ""
    foreach t $sibs {
        catch { targets $t } _
        set cs "?" ; catch { $t curstate } cs
        if {$cs ne "halted"} { continue }
        if {$anyhalt eq ""} { set anyhalt $t }
        set pc [_regval pc]
        if {$pc ne "" && [expr {$pc & 0xFFFFFFFFFFFFFFFF}] == [expr {$addr & 0xFFFFFFFFFFFFFFFF}]} { return $t }
    }
    return $anyhalt
}

# Walk the AArch64 frame-pointer chain from a function-ENTRY breakpoint -> the caller return-address chain.
# At entry: pc=func, x30(lr)=return into the immediate caller, x29(fp)=the caller's frame record. Each AAPCS64
# frame record is [saved_fp, saved_lr] at [fp, fp+8]. Read via AXI using the linear map. Stacks grow DOWN, so
# each saved_fp must be > the current fp (loop/corruption guard). CAVEAT: a just-halted core's freshest stack
# frames can sit in the D-cache and read stale over AXI — deeper frames are usually flushed; sanity-check the
# symbolized names. Symbolize the printed VAs with tools/vxworks-symtab.py / the addr->name map.
proc _backtrace {core fp lr pc depth} {
    echo " --- backtrace (caller chain; symbolize the VAs with the vxworks-symtab map) ---"
    if {$pc ne "" && $pc ne "?"} { echo [format "   #00  %s   (breakpoint)" $pc] }
    if {$lr ne "" && $lr ne "?"} { echo [format "   #01  %s   (lr = return into immediate caller)" $lr] }
    if {$fp eq "" || $fp eq "?"} { echo "   (x29/fp unavailable; cannot unwind further)" ; return }
    # Read the saved-FP/LR records THROUGH the halted core (cache-coherent) at the full VA — NOT via AXI,
    # which sees stale DRAM for the freshly-written stack frames. The core uses its MMU, so no PA conversion.
    catch { targets $core } _
    set cur [expr {$fp & 0xFFFFFFFFFFFFFFFF}]
    set n 2
    for {set d 0} {$d < $depth} {incr d} {
        if {[catch { read_memory $cur 32 4 } w]} { echo "   (stack read failed; stop)" ; break }
        set sfp [expr {([lindex $w 0] & 0xFFFFFFFF) | (([lindex $w 1] & 0xFFFFFFFF) << 32)}]
        set slr [expr {([lindex $w 2] & 0xFFFFFFFF) | (([lindex $w 3] & 0xFFFFFFFF) << 32)}]
        if {$slr == 0} { echo "   (saved lr = 0; top of stack)" ; break }
        echo [format "   #%02d  0x%016x" $n $slr]
        incr n
        if {$sfp <= $cur} { echo "   (fp chain not ascending; stop)" ; break }
        set cur $sfp
    }
}

# dump the integer register file of the current target + deref the requested arg pointers
proc _dump_ctx {axi kva_lo deref dlen} {
    set names {x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17 x18 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29 x30 sp pc pstate}
    array set V {}
    foreach n $names { set V($n) [_regval $n] }
    if {$V(pstate) eq ""} { set V(pstate) [_regval cpsr] }   ;# OpenOCD aarch64 may expose it as cpsr
    # registers, 4 per line
    set line "" ; set i 0
    foreach n {x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17 x18 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29 x30} {
        set v $V($n) ; if {$v eq ""} { set v "?" }
        append line [format "  %-4s=%-18s" $n $v]
        incr i ; if {$i % 4 == 0} { echo $line ; set line "" }
    }
    if {$line ne ""} { echo $line }
    set spv $V(sp) ; set pcv $V(pc) ; set psv $V(pstate)
    if {$spv eq ""} {set spv "?"} ; if {$pcv eq ""} {set pcv "?"} ; if {$psv eq ""} {set psv "?"}
    echo [format "  sp  =%-18s  pc  =%-18s  pstate=%s" $spv $pcv $psv]

    if {$::BT} { _backtrace $::CORE $V(x29) $V(x30) $V(pc) $::BTDEPTH }

    if {$deref eq "" || $deref eq "none"} { return }
    echo " --- argument dereference (x0..xN as pointers, via AXI) ---"
    regsub -all {,} $deref " " deref
    foreach idx $deref {
        if {![string is integer -strict $idx]} { continue }
        set rn "x$idx" ; set va $V($rn)
        if {$va eq ""} { echo [format "  %-4s = ?" $rn] ; continue }
        set vlo [expr {$va & 0xFFFFFFFF}]
        set pa [expr {$vlo - $kva_lo}]
        if {$pa < 0 || $vlo < $kva_lo} {
            echo [format "  %-4s = %s   (not in the linear map (>= 0x%x); not dereferenced)" $rn $va $kva_lo]
            continue
        }
        catch { targets $axi } _
        set nw [expr {($dlen + 3) / 4}]
        if {[catch { read_memory $pa 32 $nw } words]} {
            echo [format "  %-4s -> PA 0x%08x : (unreadable)" $rn $pa] ; continue
        }
        # words(32-bit) -> bytes -> hex + ascii  (ZynqMP mem-AP rejects 64-bit access width)
        set bytes {}
        foreach w $words { for {set b 0} {$b < 4} {incr b} { lappend bytes [expr {($w >> ($b*8)) & 0xFF}] } }
        set hex "" ; set asc ""
        foreach by $bytes {
            append hex [format "%02x " $by]
            if {$by >= 0x20 && $by < 0x7f} { append asc [format %c $by] } else { append asc "." }
        }
        echo [format "  %-4s -> PA 0x%08x" $rn $pa]
        echo "        hex: [string trimright $hex]"
        echo "        str: $asc"
    }
}

# which sibling halted, and at WHICH armed address? returns {core addr} (addr "" if PC matched none).
proc _which_hit {sibs addrs} {
    set anyhalt ""
    foreach t $sibs {
        catch { targets $t } _
        set cs "?" ; catch { $t curstate } cs
        if {$cs ne "halted"} { continue }
        if {$anyhalt eq ""} { set anyhalt [list $t ""] }
        set pc [_regval pc]
        if {$pc eq ""} { continue }
        foreach a $addrs {
            if {[expr {$pc & 0xFFFFFFFFFFFFFFFF}] == [expr {$a & 0xFFFFFFFFFFFFFFFF}]} { return [list $t $a] }
        }
    }
    return $anyhalt
}
# evaluate BC_COND "xN ==|!= VAL" against the current (halted) core. 1 = pass / no filter.
proc _cond_ok {cond} {
    if {$cond eq ""} { return 1 }
    if {![regexp {^\s*(x[0-9]+|sp|lr|pc)\s*(==|!=)\s*(0[xX][0-9a-fA-F]+|[0-9]+)\s*$} $cond -> reg op val]} {
        echo "   (BC_COND '$cond' unparseable — expected 'xN ==|!= VAL'; ignoring)" ; return 1
    }
    set rv [_regval $reg]
    if {$rv eq ""} { return 0 }
    set a [expr {$rv & 0xFFFFFFFFFFFFFFFF}] ; set b [expr {$val & 0xFFFFFFFFFFFFFFFF}]
    if {$op eq "=="} { return [expr {$a == $b}] }
    return [expr {$a != $b}]
}

# --- capture loop: resume the cluster, catch a hit, (optionally) filter, then trace-line or full-dump.
# Without a filter it stops after COUNT hits; with BC_COND it keeps going (up to MAXHITS cycles) until COUNT
# hits PASS the filter. Multiple armed breakpoints make it a call tracer across all of them. ---
set captured 0 ; set cyc 0 ; set seen 0
set MAXCYC [expr {$COND eq "" ? $COUNT : $MAXHITS}]
while {$captured < $COUNT && $cyc < $MAXCYC} {
    incr cyc
    foreach t $SIBS { catch { targets $t ; resume } _ }
    set waited 0 ; set hit 0
    while {$waited < $TMO} {
        catch { targets $CORE } _
        if {![catch { $CORE curstate } st] && $st eq "halted"} { set hit 1 ; break }
        after 50 ; incr waited 50
    }
    if {!$hit} {
        echo "----------------------------------------------------------------"
        echo " TIMEOUT — no armed breakpoint reached in $TMO ms (seen $seen hit(s), captured $captured)."
        break
    }
    incr seen
    set wh [_which_hit $SIBS $armed]
    set who [lindex $wh 0] ; set haddr [lindex $wh 1]
    if {$who eq ""} { echo " a core halted but none reported a readable state." ; break }
    catch { targets $who } _
    if {![_cond_ok $COND]} { continue }   ;# filtered out — keep going, don't count/print
    incr captured
    if {$TRACE} {
        set a0 [_regval x0] ; set a1 [_regval x1] ; set a2 [_regval x2] ; set a3 [_regval x3]
        if {$a0 eq ""} {set a0 "?"} ; if {$a1 eq ""} {set a1 "?"} ; if {$a2 eq ""} {set a2 "?"} ; if {$a3 eq ""} {set a3 "?"}
        echo [format " #%-3d %-14s @ %s  x0=%s x1=%s x2=%s x3=%s" $captured $who $haddr $a0 $a1 $a2 $a3]
    } else {
        echo "----------------------------------------------------------------"
        echo " HIT $captured on $who  (PC == $haddr):"
        _dump_ctx $AXI $KVA_LO $DEREF $DLEN
    }
}

# --- cleanup: remove every breakpoint, resume the whole cluster ---
catch { targets $CORE } _
foreach a $armed { catch { rbp $a } _ }
foreach t $SIBS { catch { targets $t ; resume } _ }
echo "----------------------------------------------------------------"
echo [format " captured %d hit(s) over %d cycle(s); breakpoints removed; cluster resumed." $captured $cyc]
echo "================================================================"
