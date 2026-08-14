# inject.tcl — standalone JTAG binary injector for ZynqMP (ZCU102).
#
# Decoupled from the dump-bootrom research harness. Loads an arbitrary raw
# .bin to any address, runs it on a chosen core, optionally verifies the load
# (read-back compare) and reads back a result region.
#
# USAGE (note the leading `init;` — required so DAP ops run after init):
#   openocd -f openocd/zcu102.cfg -c "init; \
#       set ::INJECT_BIN payloads/inject-demo.bin; \
#       set ::INJECT_ADDR 0xFFFC0100; \
#       set ::INJECT_MODE cold; \
#       set ::INJECT_DONE_ADDR 0xFFFC0900; set ::INJECT_DONE_VAL 0x1A7EC0DE; \
#       set ::INJECT_RESULT_ADDR 0xFFFC0900; set ::INJECT_RESULT_LEN 4; \
#       source openocd/inject.tcl; shutdown"
#
# PARAMETERS (globals; all optional except INJECT_BIN):
#   INJECT_BIN          path to raw .bin to inject                (required)
#   INJECT_ADDR         load address          (default 0xFFFC0100 = OCM)
#   INJECT_ENTRY        entry PC              (default = INJECT_ADDR)
#   INJECT_CORE         a53.0..a53.3          (default a53.0)
#   INJECT_MODE         cold | live           (default cold)
#   INJECT_VERIFY       1=read-back compare after load (default 1)
#   INJECT_DONE_ADDR    poll this addr for completion (default "" = just wait)
#   INJECT_DONE_VAL     completion value to match     (default 0xCAFEC0DE)
#   INJECT_RESULT_ADDR  read back N words here after run (default "" = none)
#   INJECT_RESULT_LEN   N words to read back          (default 8)
#   INJECT_TIMEOUT_MS   completion poll timeout       (default 3000)
#
# MODES:
#   cold — reset the target core into EL3-Secure at a clean landing pad
#          (BOOTED_STATE reset cycle: freezes the OS). Payload runs at EL3
#          with MMU OFF, so any physical address (OCM/DDR/TCM) works as both
#          load and entry. Best for privileged payloads; abandons the OS.
#   live — halt the RUNNING core in place, save its full context, disable the
#          MMU (SCTLR_EL1.M/C/I) so physical addressing works, inject + run,
#          then restore memory + context + MMU and RESUME the OS. EXPERIMENTAL:
#          a misbehaving payload or a sysreg-access gap can crash the OS.

set _script_dir [file dirname [info script]]
source [file join $_script_dir lib enum-helpers.tcl]
source [file join $_script_dir lib release-recipes.tcl]

proc _ig {name dflt} { if {[info exists ::$name]} { return [set ::$name] } else { return $dflt } }

# Read one OpenOCD register by name -> hex string, or "ERR".
proc _rdreg {name} {
    if {[catch {reg $name} out]} { return "ERR" }
    if {[regexp {0x[0-9a-fA-F]+} $out m]} { return $m }
    return "ERR"
}
proc _wrreg {name val} { catch { reg $name $val } _ ; }

# UTF-8-safe raw-binary loader (file size + binary scan c*; see
# reference_tcl_binary_read_bug). Optional read-back verify. Returns nbytes/-1.
proc inject_load {addr path verify} {
    if {![file exists $path]} { say "  ERROR: bin not found: $path"; return -1 }
    catch { targets uscale.axi } _
    set n [file size $path]
    set fh [open $path rb]
    fconfigure $fh -translation binary
    set bytes [read $fh $n]
    close $fh
    binary scan $bytes c* bl
    set L [llength $bl]
    set words {}
    for {set i 0} {$i < $L} {incr i 4} {
        set b0 [lindex $bl $i]
        set b1 [expr {$i+1 < $L ? [lindex $bl [expr {$i+1}]] : 0}]
        set b2 [expr {$i+2 < $L ? [lindex $bl [expr {$i+2}]] : 0}]
        set b3 [expr {$i+3 < $L ? [lindex $bl [expr {$i+3}]] : 0}]
        lappend words [expr {($b0 & 0xFF) | (($b1 & 0xFF) << 8) | (($b2 & 0xFF) << 16) | (($b3 & 0xFF) << 24)}]
    }
    if {[catch {write_memory $addr 32 $words} e]} { say "  ERROR: write_memory failed: $e"; return -1 }
    say "  loaded $n bytes ([llength $words] words) -> [hex32 $addr]"
    if {$verify} {
        if {[catch {read_memory $addr 32 [llength $words]} rb]} { say "  VERIFY: read-back failed: $rb"; return -1 }
        for {set i 0} {$i < [llength $words]} {incr i} {
            if {[lindex $rb $i] != [lindex $words $i]} {
                say "  VERIFY MISMATCH word $i: wrote [hex32 [lindex $words $i]] read [hex32 [lindex $rb $i]]"
                return -1
            }
        }
        say "  verify OK — [llength $words] words read back identical"
    }
    return $n
}

# Set PC, resume, poll a done marker (via AXI-AP so reads work while running),
# then halt. Returns 1 if completion seen, 0 on timeout.
proc inject_run {core entry doneaddr doneval timeout} {
    catch { targets uscale.$core } _
    _wrreg pc $entry
    say "  pc <- [hex32 $entry]; resuming $core"
    catch { resume } _
    set seen 0
    if {$doneaddr ne ""} {
        set elapsed 0
        while {$elapsed < $timeout} {
            catch { targets uscale.axi } _
            set v [safe_rd $doneaddr]
            if {$v ne "ERR" && [expr {int($v)}] == [expr {int($doneval)}]} { set seen 1; break }
            after 25
            incr elapsed 25
        }
        if {$seen} {
            say "  completion: [hex32 $doneaddr] == [hex32 $doneval] seen (~${elapsed}ms)"
        } else {
            say "  TIMEOUT: [hex32 $doneaddr] never reached [hex32 $doneval] (last=[safe_rd $doneaddr])"
        }
    } else {
        after $timeout
        say "  (no done-addr; waited ${timeout}ms)"
    }
    catch { targets uscale.$core } _
    catch { halt } _
    after 30
    return $seen
}

proc inject_result {resaddr reslen} {
    if {$resaddr eq ""} return
    catch { targets uscale.axi } _
    say "  --- result region [hex32 $resaddr] (${reslen} words) ---"
    for {set i 0} {$i < $reslen} {incr i} {
        set a [expr {$resaddr + $i*4}]
        say [format "    +0x%02x  %s = %s" [expr {$i*4}] [hex32 $a] [hex32 [safe_rd $a]]]
    }
}

# ---- COLD: reset core to EL3, load, run ----
proc inject_cold {bin addr entry core verify doneaddr doneval resaddr reslen timeout} {
    say "## INJECT cold-mode  core=$core addr=[hex32 $addr] entry=[hex32 $entry]"
    if {$core ne "a53.0"} { say "  NOTE: cold reset-cycle supports a53.0 only; forcing a53.0"; set core a53.0 }
    if {![reset_release_a53_core0 $::ADDR_SAFE_LANDING]} { say "  reset_release failed — aborting"; return }
    set ex 0
    for {set i 0} {$i < 3} {incr i} { if {[catch {uscale.a53.0 arp_examine} e] == 0} { set ex 1; break }; after 50 }
    if {!$ex} { say "  a53.0 examine failed — aborting"; return }
    catch { targets uscale.a53.0 } _
    catch { halt } _
    after 50
    if {[uscale.a53.0 curstate] ne "halted"} { say "  a53.0 not halted — aborting"; return }
    say "  a53.0 halted at EL3 landing pad"
    if {[inject_load $addr $bin $verify] < 0} { return }
    inject_run a53.0 $entry $doneaddr $doneval $timeout
    inject_result $resaddr $reslen
    say "## cold-mode done (OS frozen; power-cycle to recover)"
}

# ---- LIVE: halt running core, save ctx, MMU off, inject, run, restore, resume ----
proc inject_live {bin addr entry core verify doneaddr doneval resaddr reslen timeout} {
    say "## INJECT live-mode (EXPERIMENTAL)  core=$core addr=[hex32 $addr] entry=[hex32 $entry]"
    catch { targets uscale.$core } _
    catch { uscale.$core arp_examine } _
    catch { halt } _
    after 50
    if {[uscale.$core curstate] ne "halted"} { say "  $core not halted — aborting"; return }

    set save_pc   [_rdreg pc]
    set save_cpsr [_rdreg cpsr]
    set save_sp   [_rdreg sp]
    set saved {}
    for {set i 0} {$i <= 30} {incr i} { lappend saved [_rdreg x$i] }
    say "  saved OS ctx: pc=$save_pc cpsr=$save_cpsr sp=$save_sp"

    set sctlr [_rdreg SCTLR_EL1]
    if {$sctlr eq "ERR"} {
        say "  CANNOT read SCTLR_EL1 (no sysreg access via this OpenOCD build)."
        say "  live mode needs MMU-off; aborting and resuming OS untouched."
        catch { resume } _
        return
    }
    set sctlr_off [expr {int($sctlr) & ~0x1005}]   ;# clear M(0) C(2) I(12)
    say "  SCTLR_EL1 = $sctlr -> [hex32 $sctlr_off] (MMU/cache off for injection)"

    # Save original memory so we can restore it after.
    set nwords [expr {([file size $bin] + 3) / 4}]
    catch { targets uscale.axi } _
    set orig {}
    if {[catch {read_memory $addr 32 $nwords} orig]} { say "  cannot snapshot target mem — aborting"; catch { resume } _; return }

    _wrreg SCTLR_EL1 $sctlr_off
    if {[inject_load $addr $bin $verify] < 0} {
        _wrreg SCTLR_EL1 $sctlr
        catch { resume } _
        return
    }
    set ok [inject_run $core $entry $doneaddr $doneval $timeout]
    inject_result $resaddr $reslen

    # ---- restore everything ----
    say "  restoring OS context..."
    catch { targets uscale.axi } _
    catch { write_memory $addr 32 $orig } _
    catch { targets uscale.$core } _
    _wrreg SCTLR_EL1 $sctlr
    for {set i 0} {$i <= 30} {incr i} { _wrreg x$i [lindex $saved $i] }
    _wrreg sp $save_sp
    _wrreg cpsr $save_cpsr
    _wrreg pc $save_pc
    catch { resume } _
    say "## live-mode done — OS context restored and resumed (verify the console is alive)"
}

# ---- LIVE-MEM: read/patch live-kernel memory via VA->PA + physical AXI-AP ----
# Bypasses W^X RO (physical writes don't check stage-1 perms). Freezes all cores
# for the operation. Proven 2026-05-28 (probe-phys-patch.tcl). NOTE: a patch left
# in DRAM is seen by the running core only after its cache line refills — reliable
# *code* execution still needs cache maintenance (see [[reference-jtag-injector]]).
proc _resume_all {} { foreach c {uscale.a53.0 uscale.a53.1 uscale.a53.2 uscale.a53.3} { catch { targets $c; resume } _ } }

proc inject_live_mem {va words patchval restore} {
    say "## INJECT live-mem  (VA->PA + physical AXI; bypasses W^X RO)"
    foreach c {uscale.a53.0 uscale.a53.1 uscale.a53.2 uscale.a53.3} { catch { $c arp_examine } _; catch { targets $c; halt } _ }
    catch { targets uscale.a53.0 } _
    after 30
    if {$va eq ""} {
        if {[catch {reg pc} o]} { say "  no INJECT_LIVE_VA and cannot read pc — aborting"; _resume_all; return }
        regexp {0x[0-9a-fA-F]+} $o va
        say "  (no INJECT_LIVE_VA; using current core0 pc $va)"
    }
    set pa 0
    if {![catch {virt2phys $va} o] && [regexp {0x[0-9a-fA-F]+} $o m]} { set pa $m }
    if {$pa == 0} { say "  virt2phys failed for $va (unmapped?) — aborting"; _resume_all; return }
    say "  VA $va -> PA $pa"
    catch { targets uscale.axi } _
    say "  --- live kernel memory (physical read) ---"
    for {set i 0} {$i < $words} {incr i} {
        set a [expr {$pa + $i*4}]
        say [format "    +0x%02x  %s = %s" [expr {$i*4}] [hex32 $a] [hex32 [safe_rd $a]]]
    }
    if {$patchval ne ""} {
        set orig [safe_rd $pa]
        say "  patch: [hex32 $pa]  $orig -> [hex32 $patchval]  (physical write)"
        catch { write_memory $pa 32 [list [expr {int($patchval)}]] } _
        set rb [safe_rd $pa]
        set took 0
        if {$rb ne "ERR" && [expr {int($rb)}] == [expr {int($patchval)}]} { set took 1 }
        say "  read-back: $rb  -> [expr {$took ? {WRITE TOOK — W^X RO bypassed} : {write did NOT take}}]"
        if {$restore && $orig ne "ERR"} {
            catch { write_memory $pa 32 [list [expr {int($orig)}]] } _
            say "  restored: [safe_rd $pa]"
        } elseif {!$restore} {
            say "  NOTE: patch LEFT in DRAM (INJECT_LIVE_RESTORE=0). Running core sees it"
            say "        only after its cache line refills (cache-coherency caveat)."
        }
    }
    _resume_all
    say "## live-mem done — cores resumed"
}

# ---- dispatch ----
set _bin   [_ig INJECT_BIN ""]
set _addr  [_ig INJECT_ADDR 0xFFFC0100]
set _entry [_ig INJECT_ENTRY $_addr]
set _core  [_ig INJECT_CORE a53.0]
set _mode  [_ig INJECT_MODE cold]
set _ver   [_ig INJECT_VERIFY 1]
set _da    [_ig INJECT_DONE_ADDR ""]
set _dv    [_ig INJECT_DONE_VAL 0xCAFEC0DE]
set _ra    [_ig INJECT_RESULT_ADDR ""]
set _rl    [_ig INJECT_RESULT_LEN 8]
set _to    [_ig INJECT_TIMEOUT_MS 3000]
set _lva   [_ig INJECT_LIVE_VA ""]
set _lw    [_ig INJECT_LIVE_WORDS 4]
set _lp    [_ig INJECT_LIVE_PATCH ""]
set _lr    [_ig INJECT_LIVE_RESTORE 1]

say ""
say "============================================================"
say "  JTAG binary injector"
say "============================================================"
if {$_bin eq "" && $_mode ne "live-mem"} {
    say "  ERROR: set ::INJECT_BIN to a .bin path (not needed for live-mem mode)"
} else {
    clear_dp_sticky
    switch -- $_mode {
        cold { inject_cold $_bin $_addr $_entry $_core $_ver $_da $_dv $_ra $_rl $_to }
        live { inject_live $_bin $_addr $_entry $_core $_ver $_da $_dv $_ra $_rl $_to }
        live-mem { inject_live_mem $_lva $_lw $_lp $_lr }
        default { say "  ERROR: unknown INJECT_MODE '$_mode' (use cold|live|live-mem)" }
    }
}
say "============================================================"
