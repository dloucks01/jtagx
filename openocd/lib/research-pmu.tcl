# research-pmu.tcl — PMU chain probes (wake, IPI).
#
# Loaded by openocd/dump-bootrom.tcl after the helpers it depends on:
#   - safe_rd / safe_wr / hex32 (lib/enum-helpers.tcl)
#   - _method_a53_common (dump-bootrom.tcl)
#   - _safe_int (dump-bootrom.tcl)
#
# Probes exported:
#   pmu-wake-probe — Test A53 EL3 writability of PMU_GLOBAL.GLOBAL_CNTRL
#   pmu-ipi        — A53 EL3 → IPI → PMU PM_GET_API_VERSION
#   pmu-mmio-write — A53 EL3 → IPI → PMU PM_MMIO_WRITE to reopen the debug gates

# Research method: pmu-wake-probe — test if A53 EL3 can write
# PMU_GLOBAL.GLOBAL_CNTRL (prerequisite for any actual PMU wake attempt).
# Probes reserved bit 31 (no functional effect). If writable, follow-on
# probe can attempt actual wake by clearing MB_SLEEP bit 11.
proc method_pmu_wake_probe {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-wake-probe.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-wake-probe" "Method: A53 EL3 writability test on PMU_GLOBAL.GLOBAL_CNTRL" "pmu-wake-probe"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- PMU WAKE PROBE results ---"
    say "  Stage marker = $stage  (1..5 = phase completed)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"

    if {$stage eq "ERR" || $done eq "ERR"} {
        say ""
        say "  *** HARNESS FAILURE — DAP/chip wedged ***"
        return
    }

    set base [safe_rd 0xFFFE0000]
    set post [safe_rd 0xFFFE0004]
    set rest [safe_rd 0xFFFE0008]
    set pwr_state [safe_rd 0xFFFE0010]
    set gpi1 [safe_rd 0xFFFE0014]
    set gpo1 [safe_rd 0xFFFE0018]

    set bi 0; set pi 0; set ri 0
    catch { set bi [expr {int($base)}] }
    catch { set pi [expr {int($post)}] }
    catch { set ri [expr {int($rest)}] }
    set expected [expr {($bi | 0x80000000) & 0xFFFFFFFF}]

    say ""
    say "  GLOBAL_CNTRL writability test:"
    say [format "    Baseline                  = 0x%08X" [expr {$bi & 0xFFFFFFFF}]]
    say [format "    After write of bit-31-set = 0x%08X  (expected 0x%08X if accepted)" \
        [expr {$pi & 0xFFFFFFFF}] $expected]
    say [format "    After restore             = 0x%08X" [expr {$ri & 0xFFFFFFFF}]]
    say ""
    say "  Context (sibling PMU_GLOBAL regs):"
    say "    PMU_GLOBAL.PWR_STATE  = $pwr_state"
    say "    PMU_GLOBAL.GPI1       = $gpi1   (signals into PMU)"
    say "    PMU_GLOBAL.GPO1       = $gpo1   (signals from PMU)"
    say ""

    # Verdict
    say "  --- VERDICT ---"
    if {$pi == $expected} {
        say "  WRITE-TOOK — A53 EL3 CAN write PMU_GLOBAL.GLOBAL_CNTRL."
        say "  >>> Next step: attempt actual PMU wake by clearing MB_SLEEP"
        say "      (bit 11). Will be a follow-on probe with the wake + IPI"
        say "      retry combined."
    } elseif {$pi == $bi} {
        say "  WRITE-REJECTED — A53 EL3 cannot write PMU_GLOBAL.GLOBAL_CNTRL."
        say "  >>> PMU wake attempt blocked. PMU is unwakeable from A53 EL3."
        say "  >>> The IPI chain (and any chained-with-LMB primitive) is"
        say "      blocked at the wake step. PMU FW must be loaded via the"
        say "      proper boot flow (Phase 7) for IPI to function."
    } else {
        say [format "  PARTIAL/UNEXPECTED — got 0x%08X" [expr {$pi & 0xFFFFFFFF}]]
        say "  Some bits may be writable, others not. Investigate per-bit."
    }
    say ""
    say "  Live JTAG re-read:"
    say "    GLOBAL_CNTRL = [safe_rd 0xFFD80000]"
    say "    PWR_STATE    = [safe_rd 0xFFD80100]"
    say "    TAMPER_STATUS= [safe_rd 0xFFCA5000]"
}


# Research method: pmu-ipi — A53 EL3 SECURE → IPI → PMU PM API probe.
# Tests if A53 EL3 can communicate with PMU ROM via documented IPI path.
# Initial command: PM_GET_API_VERSION (simplest, lowest-risk query).
# If PMU responds, opens further probes (PM_MMIO_READ, PM_GET_NODE_STATUS)
# and chained-with-LMB-writability paths.
proc method_pmu_ipi {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-ipi.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-ipi" "Method: A53 EL3 → IPI → PMU PM_GET_API_VERSION probe" "pmu-ipi"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- PMU IPI results ---"
    say "  Stage marker = $stage  (1..9 = phase completed)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"

    if {$stage eq "ERR" || $done eq "ERR"} {
        say ""
        say "  *** HARNESS FAILURE — DAP/chip wedged ***"
        return
    }

    # Pre-state snapshot
    set pre_trig [safe_rd 0xFFFE0000]
    set pre_obs  [safe_rd 0xFFFE0004]
    set pre_isr  [safe_rd 0xFFFE0008]
    set pre_pmu_isr [safe_rd 0xFFFE000C]
    set pre_req_w0 [safe_rd 0xFFFE0010]
    set pre_req_w1 [safe_rd 0xFFFE0014]
    set pre_rsp_w0 [safe_rd 0xFFFE0018]
    set pre_rsp_w1 [safe_rd 0xFFFE001C]
    set post_trig_obs [safe_rd 0xFFFE0020]
    set post_poll_obs [safe_rd 0xFFFE0024]
    set post_poll_isr [safe_rd 0xFFFE0028]
    set iters         [safe_rd 0xFFFE002C]

    say ""
    say "  IPI state machine:"
    say "    pre-trigger  APU.TRIG    = $pre_trig"
    say "    pre-trigger  APU.OBS     = $pre_obs"
    say "    pre-trigger  APU.ISR     = $pre_isr"
    say "    pre-trigger  PMU0.ISR    = $pre_pmu_isr"
    say "    post-trigger APU.OBS     = $post_trig_obs  (bit 16 SET = req outstanding)"
    say "    post-poll    APU.OBS     = $post_poll_obs  (bit 16 CLEAR = PMU ACKed receipt)"
    say "    post-poll    APU.ISR     = $post_poll_isr  (bit 16 SET = PMU signaled back)"
    say "    poll iters used          = $iters"

    say ""
    say "  Pre-buffer state (residual, pre-our-write):"
    say "    request  buf(0) = $pre_req_w0"
    say "    request  buf(1) = $pre_req_w1"
    say "    response buf(0) = $pre_rsp_w0"
    say "    response buf(1) = $pre_rsp_w1"

    # Response buffer (8 words)
    say ""
    say "  PMU response buffer (PM_GET_API_VERSION expected to return"
    say "  word(0)=status (0=SUCCESS), word(1)=version):"
    for {set i 0} {$i < 8} {incr i} {
        set a [expr {0xFFFE0030 + ($i * 4)}]
        set v [safe_rd $a]
        say [format "    response(%d) = %s" $i $v]
    }
    set rsp_status [safe_rd 0xFFFE0030]
    set rsp_value  [safe_rd 0xFFFE0034]
    set rsp_st_i 0; set rsp_v_i 0
    catch { set rsp_st_i [expr {int($rsp_status)}] }
    catch { set rsp_v_i  [expr {int($rsp_value)}] }

    # Verdict
    say ""
    say "  --- VERDICT ---"
    set iters_i 0
    catch { set iters_i [expr {int($iters)}] }
    # Blocking PM protocol: completion is signaled by APU.OBS target bit
    # CLEARING (PMU clears its ISR -> our OBS clears), NOT by APU.ISR setting.
    set post_trig_obs_i 0
    catch { set post_trig_obs_i [expr {int($post_trig_obs)}] }
    set post_poll_obs_i 0
    catch { set post_poll_obs_i [expr {int($post_poll_obs)}] }
    set trig_reached  [expr {($post_trig_obs_i & 0x10000) != 0}]
    set pmu_completed [expr {$trig_reached && (($post_poll_obs_i & 0x10000) == 0)}]

    if {!$trig_reached} {
        say "  FILTERED — APU.OBS bit16 did NOT set after trigger."
        say "  The IPI trigger write from A53 EL3 never reached the IPI block"
        say "  (master-aware filtering, or wrong channel). pre/post OBS identical."
    } elseif {!$pmu_completed} {
        say "  TIMEOUT — trigger delivered (OBS bit16 SET) but PMU never"
        say "  cleared OBS within 100,000 iters. PMU got the doorbell but did"
        say "  not complete the transaction (handler stalled / request rejected)."
    } elseif {$rsp_st_i == 0} {
        say "  *** SUCCESS — PMU completed PM_GET_API_VERSION (OBS cleared) ***"
        set major [expr {($rsp_v_i >> 16) & 0xFFFF}]
        set minor [expr {$rsp_v_i & 0xFFFF}]
        say [format "  PM API version = %d.%d  (status=0, version=0x%08X)" \
            $major $minor [expr {$rsp_v_i & 0xFFFFFFFF}]]
        say "  >>> IPI path open from A53 EL3. Can now probe further commands"
        say "  >>> (PM_GET_CHIPID, PM_MMIO_READ, PM_GET_NODE_STATUS, etc)"
    } else {
        say "  PMU COMPLETED (OBS cleared) but status word is non-zero."
        say [format "  response(0) status = 0x%08X" [expr {$rsp_st_i & 0xFFFFFFFF}]]
        say "  If status = 0xFFFF, PMU acked the doorbell but wrote no response"
        say "  to 0xFF9905E0 (wrong buffer/format). Otherwise decode vs pm_defs.h:"
        say "  XST_INVALID_VERSION=2, XST_PM_NOT_SUPPORTED=4, XST_PM_NO_ACCESS=2002."
        say "  Either way, OBS-clear proves the A53-EL3 -> PMU IPI path works."
    }

    # Live JTAG cross-check
    say ""
    say "  Live JTAG re-read (chip state after A53 reset):"
    say "    APU.OBS   (0xFF300004) = [safe_rd 0xFF300004]"
    say "    APU.ISR   (0xFF300010) = [safe_rd 0xFF300010]"
    say "    response buf(0) (0xFF9905E0) = [safe_rd 0xFF9905E0]"
    say "    response buf(1) (0xFF9905E4) = [safe_rd 0xFF9905E4]"
    say "    TAMPER_STATUS         = [safe_rd 0xFFCA5000]"
}

# ---------------------------------------------------------------------------
# method_pmu_pm_probe — multi-command PM API probe (csu-pmu-pm-probe.S).
# Issues PM_GET_API_VERSION, PM_GET_CHIPID, and 4x PM_MMIO_READ, then decodes
# the per-command result slots (0xFFFE0000 + i*0x40). Requires BOOTED_STATE.
# ---------------------------------------------------------------------------
proc method_pmu_pm_probe {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-pm-probe.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-pm-probe" "Method: A53 EL3 -> PMU multi-command PM API probe" "pmu-pm-probe"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- PM probe results ---"
    say "  Stage marker = $stage  (commands completed; expect 0x6)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"
    if {$stage eq "ERR" || $done eq "ERR"} {
        say "  *** HARNESS FAILURE - DAP/chip wedged ***"
        return
    }

    # API ID -> name
    array set apinames {1 PM_GET_API_VERSION 24 PM_GET_CHIPID 20 PM_MMIO_READ}

    for {set i 0} {$i < 6} {incr i} {
        set base [expr {0xFFFE0000 + $i * 0x40}]
        set api   [safe_rd [format 0x%08X [expr {$base + 0x20}]]]
        set arg1  [safe_rd [format 0x%08X [expr {$base + 0x30}]]]
        set ptrig [safe_rd [format 0x%08X [expr {$base + 0x24}]]]
        set ppoll [safe_rd [format 0x%08X [expr {$base + 0x28}]]]
        set iters [safe_rd [format 0x%08X [expr {$base + 0x2C}]]]
        set st    [safe_rd [format 0x%08X $base]]
        set r1    [safe_rd [format 0x%08X [expr {$base + 0x04}]]]
        set r2    [safe_rd [format 0x%08X [expr {$base + 0x08}]]]

        set api_i 0; catch { set api_i [expr {int($api)}] }
        set pt 0;    catch { set pt [expr {int($ptrig)}] }
        set pp 0;    catch { set pp [expr {int($ppoll)}] }
        set sti 0;   catch { set sti [expr {int($st)}] }
        set name "API 0x[format %x $api_i]"
        if {[info exists apinames($api_i)]} { set name $apinames($api_i) }
        set completed [expr {(($pt & 0x10000) != 0) && (($pp & 0x10000) == 0)}]

        say ""
        say "  \[cmd $i\] $name  arg1=$arg1"
        say "    OBS trig=$ptrig poll=$ppoll  iters=$iters  -> [expr {$completed ? {COMPLETED} : {NO-COMPLETE}}]"
        say "    status(0)=$st  ret(1)=$r1  ret(2)=$r2"
        if {!$completed} {
            say "    >> PMU did not complete (doorbell not acked / filtered trigger)"
            continue
        }
        if {$sti == 0} {
            if {$api_i == 1} {
                set v 0; catch { set v [expr {int($r1)}] }
                say [format "    >> SUCCESS  PM API version = %d.%d" [expr {($v>>16)&0xFFFF}] [expr {$v & 0xFFFF}]]
            } elseif {$api_i == 24} {
                say "    >> SUCCESS  IDCODE=$r1  version=$r2"
            } elseif {$api_i == 20} {
                say "    >> SUCCESS  PMU proxy-read returned value=$r1  (address is WHITELISTED for APU)"
            } else {
                say "    >> SUCCESS  status=0"
            }
        } elseif {$sti == 2002} {
            say "    >> XST_PM_NO_ACCESS (0x7D2) - address NOT in PMU FW read allowlist (filter holds)"
        } else {
            say [format "    >> non-zero status 0x%X - decode vs pm_defs.h XST_*" $sti]
        }
    }

    say ""
    say "  --- Interpretation ---"
    say "  cmd2/cmd3 (CRL/CRF clock regs) SUCCESS  = PMU proxy-read works for whitelisted addrs."
    say "  cmd4/cmd5 (eFuse cache / PMU ROM) NO_ACCESS = PMU read filter blocks secure regions."
    say "  A SUCCESS on cmd4 or cmd5 would be a finding (PMU leaks a region we can't otherwise read)."
}

# ---------------------------------------------------------------------------
# method_pmu_mmio_write — re-open the debug gates via the PMU PM_MMIO_WRITE API
# (csu-pmu-mmio-write.S). Issues PM_MMIO_WRITE(JTAG_SEC,0x1FF,0x1FF) + read-back,
# then PM_MMIO_WRITE(JTAG_DAP_CFG,0xFF,0xFF) + read-back over the APU<->PMU0 IPI
# channel, then DAP-reads the live gates as ground truth. Characterizes whether
# the PMU FW MMIO write-allowlist (pm_mmio_access.c) permits the CSU debug regs.
# Requires BOOTED_STATE (running PMU FW to answer the IPI).
# ---------------------------------------------------------------------------
proc method_pmu_mmio_write {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-mmio-write.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-mmio-write" "Method: A53 EL3 -> PMU PM_MMIO_WRITE debug-gate reopen" "pmu-mmio-write"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- PM_MMIO_WRITE reopen results ---"
    say "  Stage marker = $stage  (commands completed; expect 0x4)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"
    if {$stage eq "ERR" || $done eq "ERR"} {
        say "  *** HARNESS FAILURE - DAP/chip wedged ***"
        return
    }

    array set apinames {19 PM_MMIO_WRITE 20 PM_MMIO_READ}
    array set cmdlabel {
        0 "WRITE JTAG_SEC     |= 0x1FF"
        1 "READ  JTAG_SEC     (back)"
        2 "WRITE JTAG_DAP_CFG |= 0xFF"
        3 "READ  JTAG_DAP_CFG (back)"
    }

    for {set i 0} {$i < 4} {incr i} {
        set base [expr {0xFFFE0000 + $i * 0x40}]
        set api   [safe_rd [format 0x%08X [expr {$base + 0x20}]]]
        set addr  [safe_rd [format 0x%08X [expr {$base + 0x30}]]]
        set mask  [safe_rd [format 0x%08X [expr {$base + 0x34}]]]
        set val   [safe_rd [format 0x%08X [expr {$base + 0x38}]]]
        set ptrig [safe_rd [format 0x%08X [expr {$base + 0x24}]]]
        set ppoll [safe_rd [format 0x%08X [expr {$base + 0x28}]]]
        set iters [safe_rd [format 0x%08X [expr {$base + 0x2C}]]]
        set st    [safe_rd [format 0x%08X $base]]
        set r1    [safe_rd [format 0x%08X [expr {$base + 0x04}]]]

        set api_i 0; catch { set api_i [expr {int($api)}] }
        set pt 0;    catch { set pt [expr {int($ptrig)}] }
        set pp 0;    catch { set pp [expr {int($ppoll)}] }
        set sti 0;   catch { set sti [expr {int($st)}] }
        set name "API 0x[format %x $api_i]"
        if {[info exists apinames($api_i)]} { set name $apinames($api_i) }
        set label "cmd $i"
        if {[info exists cmdlabel($i)]} { set label $cmdlabel($i) }
        set completed [expr {(($pt & 0x10000) != 0) && (($pp & 0x10000) == 0)}]

        say ""
        say "  \[cmd $i\] $label   ($name addr=$addr mask=$mask val=$val)"
        if {$completed} {
            say "    OBS trig=$ptrig poll=$ppoll iters=$iters  -> COMPLETED"
        } else {
            say "    OBS trig=$ptrig poll=$ppoll iters=$iters  -> NO-COMPLETE"
        }
        say "    status(0)=$st  ret(1)=$r1"
        if {!$completed} {
            say "    >> PMU did not complete (doorbell not acked / filtered trigger)"
            continue
        }
        if {$sti == 0} {
            if {$api_i == 20} {
                say "    >> SUCCESS  read-back value = $r1"
            } else {
                say "    >> SUCCESS  PMU performed the write (gate bits set via PM_MMIO_WRITE)"
            }
        } elseif {$sti == 2002} {
            say "    >> XST_PM_NO_ACCESS (0x7D2) - address NOT in the PMU FW MMIO allowlist"
            say "       (the PMU write-filter blocks the CSU debug regs; expected on stock FW)"
        } else {
            say [format "    >> non-zero status 0x%X - decode vs pm_defs.h XST_*" $sti]
        }
    }

    # ---- verdict via an independent DAP read-back of the live gates ----
    say ""
    say "  --- DAP read-back of the gates (ground truth, after the PMU writes) ---"
    set sec  [safe_rd 0xFFCA0038]
    set dap  [safe_rd 0xFFCA003C]
    say "    JTAG_SEC     (0xFFCA0038) = $sec"
    say "    JTAG_DAP_CFG (0xFFCA003C) = $dap"
    set sec_i 0; catch { set sec_i [expr {int($sec)}] }
    set dap_i 0; catch { set dap_i [expr {int($dap)}] }
    set dap_sec_open [expr {($sec_i & 0x7) == 0x7}]
    set apu_dbg_open [expr {($dap_i & 0xFF) == 0xFF}]
    say ""
    say "  --- VERDICT ---"
    if {$dap_sec_open && $apu_dbg_open} {
        say "  REOPENED via PMU — DAP_SEC + APU/RPU debug now read OPEN. The PMU MMIO"
        say "  write-allowlist permits the CSU debug regs (or no eFuse lock); debug restored."
    } elseif {$dap_sec_open || $apu_dbg_open} {
        say "  PARTIAL — one gate opened via the PMU, the other did not (allowlist or eFuse)."
    } else {
        say "  NOT REOPENED — the gates still read closed. Either the PMU write-allowlist"
        say "  blocks these addresses (NO_ACCESS above) or the bits are eFuse-locked."
    }
}

# ---------------------------------------------------------------------------
# method_pmu_rpu_wake — wake RPU island + TCM banks via PM_REQUEST_NODE, then
# verify TCM is reachable from JTAG (was hard-blocked in JTAG-idle). Chain 2.
# Requires BOOTED_STATE.
# ---------------------------------------------------------------------------
proc method_pmu_rpu_wake {ts dumps_dir} {
    # ---- TCM baseline BEFORE wake (RPU/TCM expected OFF on a bare boot) ----
    catch { targets uscale.axi } _
    set tcma_before [safe_rd 0xFFE00000]
    set tcmb_before [safe_rd 0xFFE20000]
    say ""
    say "  --- TCM baseline (before wake, core still in Linux) ---"
    say "    TCM_A 0xFFE00000 = $tcma_before"
    say "    TCM_B 0xFFE20000 = $tcmb_before"

    set p [file join $::_repo_root payloads csu-pmu-rpu-wake.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-rpu-wake" "Method: A53 EL3 -> PMU wake RPU island + TCM banks" "pmu-rpu-wake"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- RPU/TCM wake results ---"
    say "  Stage marker = $stage  (commands completed; expect 0x5)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"
    if {$stage eq "ERR" || $done eq "ERR"} {
        say "  *** HARNESS FAILURE - DAP/chip wedged ***"
        return
    }

    array set apinames {3 PM_GET_NODE_STATUS 13 PM_REQUEST_NODE}
    array set nodenames {7 NODE_RPU_0 15 NODE_TCM_0_A 16 NODE_TCM_0_B}

    for {set i 0} {$i < 5} {incr i} {
        set base [expr {0xFFFE0000 + $i * 0x40}]
        set api  [safe_rd [format 0x%08X [expr {$base + 0x20}]]]
        set node [safe_rd [format 0x%08X [expr {$base + 0x30}]]]
        set ptr  [safe_rd [format 0x%08X [expr {$base + 0x24}]]]
        set ppl  [safe_rd [format 0x%08X [expr {$base + 0x28}]]]
        set st   [safe_rd [format 0x%08X $base]]
        set r1   [safe_rd [format 0x%08X [expr {$base + 0x04}]]]
        set r2   [safe_rd [format 0x%08X [expr {$base + 0x08}]]]
        set r3   [safe_rd [format 0x%08X [expr {$base + 0x0C}]]]

        set api_i 0;  catch { set api_i [expr {int($api)}] }
        set node_i 0; catch { set node_i [expr {int($node)}] }
        set pt 0;     catch { set pt [expr {int($ptr)}] }
        set pp 0;     catch { set pp [expr {int($ppl)}] }
        set sti 0;    catch { set sti [expr {int($st)}] }
        set aname "0x[format %x $api_i]"; if {[info exists apinames($api_i)]} { set aname $apinames($api_i) }
        set nname "0x[format %x $node_i]"; if {[info exists nodenames($node_i)]} { set nname $nodenames($node_i) }
        set completed [expr {(($pt & 0x10000) != 0) && (($pp & 0x10000) == 0)}]

        say ""
        say "  \[cmd $i\] $aname  node=$nname"
        say "    completed=[expr {$completed ? {yes} : {NO}}]  status(0)=$st"
        if {!$completed} { say "    >> no completion (doorbell not acked)"; continue }
        if {$api_i == 3} {
            say "    >> NODE STATUS: currState=$r1  requirement=$r2  usage=$r3"
        } elseif {$sti == 0} {
            say "    >> REQUEST_NODE SUCCESS (node powered/requested)"
        } elseif {$sti == 2002} {
            say "    >> XST_PM_NO_ACCESS (0x7D2) - APU not permitted to request this node"
        } else {
            say [format "    >> status 0x%X (decode vs pm_defs.h; non-zero = not granted)" $sti]
        }
    }

    # ---- TCM AFTER wake: read + write/read-back to prove it is live RAM ----
    say ""
    say "  --- TCM after wake ---"
    set tcma_after [safe_rd 0xFFE00000]
    set tcmb_after [safe_rd 0xFFE20000]
    say "    TCM_A 0xFFE00000 = $tcma_after   (before: $tcma_before)"
    say "    TCM_B 0xFFE20000 = $tcmb_after   (before: $tcmb_before)"

    say "    write/read-back test @ 0xFFE00000 <- 0xC0DECAFE:"
    catch { write_memory 0xFFE00000 32 [list 0xC0DECAFE] } werr
    after 20
    set rb [safe_rd 0xFFE00000]
    say "      read-back = $rb"
    set rb_i 0; catch { set rb_i [expr {int($rb)}] }

    say ""
    say "  --- VERDICT ---"
    if {$rb_i == 0xC0DECAFE} {
        say "  *** SUCCESS — TCM is LIVE and writable from JTAG after PM_REQUEST_NODE ***"
        say "  RPU island/TCM was powered on via the EL3->PMU PM API. TCM dump (task"
        say "  #66) is now unblocked; M4 R5 dump prerequisite (powered island) is met."
    } else {
        say "  TCM write/read-back did NOT stick (read-back=$rb)."
        say "  Either TCM still gated (REQUEST_NODE rejected — check per-cmd status),"
        say "  or TCM needs the RPU released from reset before its RAM is mapped."
        say "  Compare TCM before/after reads above for any change."
    }
}

# ---------------------------------------------------------------------------
# method_pmu_r5_wakeup — capstone: power TCM, stage R5 stub, wake R5 via
# PM_REQUEST_WAKEUP, confirm the R5 core executed by reading its marker.
# Requires BOOTED_STATE.
# ---------------------------------------------------------------------------
proc method_pmu_r5_wakeup {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-r5-wakeup.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-r5-wakeup" "Method: A53 EL3 -> PMU power TCM + wake R5 core" "pmu-r5-wakeup"

    catch { targets uscale.axi } _
    after 100

    set stage [safe_rd 0xFFFE7080]
    set done  [safe_rd 0xFFFE7000]
    say ""
    say "  --- R5 wakeup results ---"
    say "  Stage marker = $stage  (12 = full sequence done; 10=copying, 11=delay)"
    say "  Done marker  = $done   (expect 0xCAFEC0DE)"
    if {$stage eq "ERR" || $done eq "ERR"} {
        say "  *** HARNESS FAILURE - DAP/chip wedged ***"
        return
    }

    array set lbl {0 "REQUEST_NODE(TCM_0_A)" 1 "REQUEST_NODE(TCM_0_B)" 2 "REQUEST_WAKEUP(RPU_0)"}
    for {set i 0} {$i < 3} {incr i} {
        set base [expr {0xFFFE0000 + $i * 0x40}]
        set ptr [safe_rd [format 0x%08X [expr {$base + 0x24}]]]
        set ppl [safe_rd [format 0x%08X [expr {$base + 0x28}]]]
        set st  [safe_rd [format 0x%08X $base]]
        set pt 0; catch { set pt [expr {int($ptr)}] }
        set pp 0; catch { set pp [expr {int($ppl)}] }
        set sti 0; catch { set sti [expr {int($st)}] }
        set completed [expr {(($pt & 0x10000) != 0) && (($pp & 0x10000) == 0)}]
        set verdict "status=$st"
        if {!$completed} {
            set verdict "NO-COMPLETE"
        } elseif {$sti == 0} {
            set verdict "SUCCESS (status 0)"
        } elseif {$sti == 2002} {
            set verdict "XST_PM_NO_ACCESS (0x7D2)"
        } elseif {$sti == 2004} {
            set verdict "XST_PM_DOUBLE_REQ (0x7D4) - node already powered/requested (OK)"
        }
        say "  \[cmd $i\] $lbl($i)  -> $verdict"
    }

    # Confirm the stub was actually staged in TCM, then check the R5 marker.
    say ""
    set tcm0 [safe_rd 0xFFE00000]
    set mark [safe_rd 0xFFE01000]
    say "  TCM word0 0xFFE00000 = $tcm0   (expect 0xe3011000 = staged R5 stub word0)"
    say "  R5 marker 0xFFE01000 = $mark   (expect 0x600D5A11 if R5 executed)"
    set mark_i 0; catch { set mark_i [expr {int($mark)}] }

    say ""
    say "  --- VERDICT ---"
    if {$mark_i == 0x600D5A11} {
        say "  *** SUCCESS — R5 CORE EXECUTED OUR CODE ***"
        say "  PM_REQUEST_WAKEUP powered + started the R5_0 core, which ran the staged"
        say "  stub from TCM and wrote its liveness marker. The RPU is now under our"
        say "  control via the EL3->PMU PM API. M4 R5 BootROM dump is fully unblocked:"
        say "  swap the stub for the bootrom-dump-r5 payload to dump via the R5 master."
    } else {
        say "  R5 did NOT write the marker (got $mark)."
        say "  Triage: cmd0/cmd1 SUCCESS or DOUBLE_REQ (TCM powered) and TCM word0 must equal"
        say "  0xe3011000 (stub staged). If WAKEUP cmd2 status != 0, the APU subsystem"
        say "  may not be permitted to wake RPU_0, or the R5 needs split/lockstep config"
        say "  set before wake (RPU_GLBL_CNTL). If stub staged but no marker, R5 powered"
        say "  but didn't run from 0x0 — try encAddr with the TCM global addr instead."
    }
}

# ---------------------------------------------------------------------------
# method_pmu_r5_bootrom — M4 capstone: power TCM, stage the FULL
# bootrom-dump-r5 extractor, wake R5, and let the R5 core dump BootROM
# (0xFFFFC000 -> 0xFFFE0000) via its own bus-master ID. The R5 sets the
# canonical done marker (0xFFFE7000 = 0x0000C0DE/0xCAFEBABE), so the
# _method_a53_common poll + 16 KB readback runs unchanged, driven by R5.
# This payload's own A53 markers/slots are relocated (0xFFFE5000/6000/6080)
# so they never alias the R5 dump dest or the R5 marker. Requires BOOTED_STATE.
#
# Falsifiable verdict on the dumped bytes:
#   all 0xDEADBEEF  -> R5 ALSO filtered (BootROM gate is NOT master-keyed; clean negative)
#   all 0x00000000  -> dest untouched (R5 never ran — check cmd2 + R5 marker)
#   varied non-sentinel -> *** R5 READ REAL BootROM where A53/DAP could not ***
# ---------------------------------------------------------------------------
proc method_pmu_r5_bootrom {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-pmu-r5-bootrom.bin]
    _method_a53_common $ts $dumps_dir $p \
        "pmu-r5-bootrom" "Method: A53 EL3 -> PMU wake R5 -> R5 dumps BootROM (M4)" "pmu-r5-bootrom"

    catch { targets uscale.axi } _
    after 100

    # A53 driver markers (relocated; the R5 owns 0xFFFE7000).
    set a53_stage [safe_rd 0xFFFE6080]
    set a53_done  [safe_rd 0xFFFE6000]
    say ""
    say "  --- R5 BootROM dump results ---"
    say "  A53 stage marker 0xFFFE6080 = $a53_stage  (12 = A53 powered TCM, staged R5, issued wake)"
    say "  A53 done  marker 0xFFFE6000 = $a53_done   (expect 0xCAFEC0DE)"
    if {$a53_stage eq "ERR" || $a53_done eq "ERR"} {
        say "  *** HARNESS FAILURE - DAP/chip wedged ***"
        return
    }

    # Per-command IPI verdicts (slots at RESULTS_BASE 0xFFFE5000, stride 0x40).
    array set lbl {0 "REQUEST_NODE(TCM_0_A)" 1 "REQUEST_NODE(TCM_0_B)" 2 "REQUEST_WAKEUP(RPU_0)"}
    set wake_ok 0
    for {set i 0} {$i < 3} {incr i} {
        set base [expr {0xFFFE5000 + $i * 0x40}]
        set ptr [safe_rd [format 0x%08X [expr {$base + 0x24}]]]
        set ppl [safe_rd [format 0x%08X [expr {$base + 0x28}]]]
        set st  [safe_rd [format 0x%08X $base]]
        set pt 0; catch { set pt [expr {int($ptr)}] }
        set pp 0; catch { set pp [expr {int($ppl)}] }
        set sti 0; catch { set sti [expr {int($st)}] }
        set completed [expr {(($pt & 0x10000) != 0) && (($pp & 0x10000) == 0)}]
        set verdict "status=$st"
        if {!$completed} {
            set verdict "NO-COMPLETE (doorbell not acked)"
        } elseif {$sti == 0} {
            set verdict "SUCCESS (status 0)"
            if {$i == 2} { set wake_ok 1 }
        } elseif {$sti == 2002} {
            set verdict "XST_PM_NO_ACCESS (0x7D2) - APU not permitted"
        } elseif {$sti == 2004} {
            set verdict "XST_PM_DOUBLE_REQ (0x7D4) - already powered/requested (OK)"
        }
        say "  \[cmd $i\] $lbl($i)  -> $verdict"
    }

    # R5 marker = R5 actually finished the dump (it writes this LAST).
    set r5_lo [safe_rd 0xFFFE7000]
    set r5_hi [safe_rd 0xFFFE7004]
    set tcm0  [safe_rd 0xFFE00000]
    set lo_i 0; catch { set lo_i [expr {int($r5_lo)}] }
    set hi_i 0; catch { set hi_i [expr {int($r5_hi)}] }
    set r5_ran [expr {$lo_i == 0x0000C0DE && $hi_i == 0xCAFEBABE}]
    say ""
    say "  TCM word0 0xFFE00000 = $tcm0   (expect 0xe30c0000 = staged bootrom-dump-r5 word0: movw r0,#0xC000)"
    say "  R5 done marker 0xFFFE7000/04 = $r5_lo / $r5_hi   (expect 0x0000C0DE / 0xCAFEBABE)"

    # Sample the dumped region and classify (filtered sentinel vs real bytes).
    set n_deadbeef 0; set n_zero 0; set n_other 0; set sample ""
    for {set i 0} {$i < 16} {incr i} {
        set w [safe_rd [format 0x%08X [expr {0xFFFE0000 + $i * 4}]]]
        set wi 0; set ok 0
        catch { set wi [expr {int($w)}]; set ok 1 }
        if {$i < 8} { append sample "[format %08X $wi] " }
        if {!$ok} { continue }
        if {$wi == 0xDEADBEEF} { incr n_deadbeef } \
        elseif {$wi == 0}      { incr n_zero } \
        else                   { incr n_other }
    }
    say "  Dump sample (first 8 words @ 0xFFFE0000): $sample"
    say "  Classify (16 words): 0xDEADBEEF=$n_deadbeef  zero=$n_zero  other=$n_other"

    say ""
    say "  --- VERDICT ---"
    if {!$wake_ok && !$r5_ran} {
        say "  R5 WAKE did not succeed (cmd2 not SUCCESS and no R5 marker)."
        say "  Triage: confirm cmd0/cmd1 powered TCM (SUCCESS/DOUBLE_REQ) and TCM word0 ="
        say "  0xe3001000 (R5 extractor staged). If WAKEUP status != 0, APU may not be"
        say "  permitted to wake RPU_0, or RPU needs split/lockstep cfg (RPU_GLBL_CNTL)"
        say "  before wake. No conclusion about the BootROM gate can be drawn yet."
    } elseif {$n_other > 0 && $n_deadbeef == 0} {
        say "  *** SUCCESS — R5 READ REAL BootROM bytes ($n_other/16 varied, 0 sentinel) ***"
        say "  The CSU BootROM gate is master-keyed and does NOT block the RPU: R5 read"
        say "  0xFFFFC000 where A53-EL3 and DAP-NS got all-0xDEADBEEF. This is the M4"
        say "  hypothesis CONFIRMED — a new master-confused BootROM read primitive."
        say "  Full dump in bootrom-via-pmu-r5-bootrom-${ts}.bin — run tools/bootrom.py on it."
    } elseif {$n_deadbeef > 0} {
        say "  R5 ALSO filtered: dumped region is the 0xDEADBEEF sentinel ($n_deadbeef/16)."
        say "  Clean NEGATIVE finding — the BootROM gate is NOT keyed on master ID (R5 is"
        say "  blocked just like A53/DAP). Documents that this avenue is properly closed."
    } elseif {$r5_ran && $n_zero >= 15} {
        say "  R5 marker set but dump is all-zero — R5 ran but its reads returned 0 (a"
        say "  different gating behavior than the 0xDEADBEEF A53 path). Worth noting."
    } else {
        say "  Inconclusive — wake_ok=$wake_ok r5_ran=$r5_ran. Inspect the .bin and slots."
    }
}

# ---------------------------------------------------------------------------
# method_hello_uart — A53 EL3 hello-world over UART0 on a booted board.
# UART0 is already configured by FSBL; payload only writes the TX FIFO.
# Watch ttyUSB0 for the message. Requires BOOTED_STATE.
# ---------------------------------------------------------------------------
proc method_hello_uart {ts dumps_dir} {
    set p [file join $::_repo_root payloads csu-hello-uart.bin]
    _method_a53_common $ts $dumps_dir $p \
        "hello-uart" "Method: A53 EL3 hello-world over PS UART0 (booted)" "hello-uart"
    catch { targets uscale.axi } _
    after 100
    say ""
    say "  --- Hello UART ---"
    say "  Stage marker 0xFFFE7080 = [safe_rd 0xFFFE7080]  (2 = message fully sent)"
    say "  Done  marker 0xFFFE7000 = [safe_rd 0xFFFE7000]  (expect 0xCAFEC0DE)"
    say "  >> The greeting should have printed on ttyUSB0 (PS UART0 console)."
    say "     (The BootROM-dump output above is the harness boilerplate; ignore it.)"
}


