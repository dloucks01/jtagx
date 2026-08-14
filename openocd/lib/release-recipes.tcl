# release-recipes.tcl — JTAG-side recipes for releasing CPUs from reset.
#
# Sourced by deep-probe tools that need to run a payload on a specific
# core. Each release recipe is paired with a reset (re-assert) recipe so
# callers can leave the board in idle after they're done.
#
# Conventions:
#   - All procs use the existing safe_rd / safe_wr / clear_dp_sticky from
#     enum-helpers.tcl, so source that first.
#   - All procs require the AXI mem-AP target ("uscale.axi") to be the
#     active target on entry. They DO switch targets internally but leave
#     the AXI target active on return.
#   - All procs are best-effort: failures are logged via `say` but don't
#     raise — caller decides whether to abort.
#
# Currently implemented:
#   release_a53_core0  / reset_a53_core0   — APU Cortex-A53 core 0
#   release_r5_core0   / reset_r5_core0    — RPU Cortex-R5 core 0
#
# Future:
#   release_pmu        / reset_pmu         — PMU MicroBlaze (deferred)

# ---------------------------------------------------------------------------
# Register addresses (also defined in dump-bootrom.tcl; kept here so this
# file is self-contained for other tools that don't source dump-bootrom).
# ---------------------------------------------------------------------------

# APU (A53)
if {![info exists ::REG_RST_FPD_APU]}    { set ::REG_RST_FPD_APU    0xFD1A0104 }
if {![info exists ::REG_APU_RVBAR_L_0]}  { set ::REG_APU_RVBAR_L_0  0xFD5C0040 }
if {![info exists ::REG_APU_RVBAR_H_0]}  { set ::REG_APU_RVBAR_H_0  0xFD5C0044 }
if {![info exists ::ADDR_SAFE_LANDING]}  { set ::ADDR_SAFE_LANDING  0xFFFC0000 }
if {![info exists ::BIT_RST_ACPU0_RESET]}       { set ::BIT_RST_ACPU0_RESET       0  }
if {![info exists ::BIT_RST_ACPU0_PWRON_RESET]} { set ::BIT_RST_ACPU0_PWRON_RESET 8  }
if {![info exists ::BIT_RST_APU_L2_RESET]}      { set ::BIT_RST_APU_L2_RESET      10 }

# CRL_APB (RPU/LPD reset control)
if {![info exists ::REG_CRL_RST_LPD_TOP]} { set ::REG_CRL_RST_LPD_TOP 0xFF5E023C }
# Bits in RST_LPD_TOP:
if {![info exists ::BIT_RPU_R50_RESET]}   { set ::BIT_RPU_R50_RESET   0 }
if {![info exists ::BIT_RPU_R51_RESET]}   { set ::BIT_RPU_R51_RESET   1 }
if {![info exists ::BIT_RPU_AMBA_RESET]}  { set ::BIT_RPU_AMBA_RESET  2 }
if {![info exists ::BIT_RPU_PGE_RESET]}   { set ::BIT_RPU_PGE_RESET   3 }

# RPU control block @ 0xFF9A0000
if {![info exists ::REG_RPU_GLBL_CNTL]}   { set ::REG_RPU_GLBL_CNTL   0xFF9A0000 }
if {![info exists ::REG_RPU_GLBL_STATUS]} { set ::REG_RPU_GLBL_STATUS 0xFF9A0004 }
if {![info exists ::REG_RPU_0_CFG]}       { set ::REG_RPU_0_CFG       0xFF9A0100 }
if {![info exists ::REG_RPU_0_VECTABLE]}  { set ::REG_RPU_0_VECTABLE  0xFF9A0110 }
if {![info exists ::REG_RPU_0_PWRDWN]}    { set ::REG_RPU_0_PWRDWN    0xFF9A0108 }

# Bits in RPU_GLBL_CNTL:
if {![info exists ::BIT_RPU_SLSPLIT]}     { set ::BIT_RPU_SLSPLIT     3 }   ;# 0=lockstep 1=split
if {![info exists ::BIT_RPU_TCM_COMB]}    { set ::BIT_RPU_TCM_COMB    6 }   ;# 0=split A/B 1=combined 64KB
# Bits in RPU_0_CFG:
if {![info exists ::BIT_RPU_VINITHI]}     { set ::BIT_RPU_VINITHI     2 }   ;# 0=lo vec 1=hi vec
if {![info exists ::BIT_RPU_NCPUHALT]}    { set ::BIT_RPU_NCPUHALT    0 }   ;# 0=halt 1=run

# TCM at globally addressable view (R5 sees this as 0x00000000):
if {![info exists ::ADDR_RPU0_ATCM]}      { set ::ADDR_RPU0_ATCM      0xFFE00000 }
if {![info exists ::ADDR_RPU0_BTCM]}      { set ::ADDR_RPU0_BTCM      0xFFE20000 }


# ---------------------------------------------------------------------------
# A53 core 0
# ---------------------------------------------------------------------------

# Release A53 core 0 from reset, with reset vector pointing at landing_addr
# (defaults to 0xFFFC0000 — the OCM safe-landing pad). After this, A53 is
# running but un-halted. Caller should `arp_examine` and `halt` to take
# control.
proc release_a53_core0 {{landing_addr 0}} {
    if {$landing_addr == 0} { set landing_addr $::ADDR_SAFE_LANDING }
    clear_dp_sticky
    catch { targets uscale.axi } _

    # Write "b ." (0x14000000 — branch-to-self) at the landing pad so the
    # A53 hangs in a known location if no payload is set up.
    if {[catch {write_memory $landing_addr 32 [list 0x14000000]} err]} {
        say "  release_a53: WARN landing-pad write failed at [hex32 $landing_addr] ($err)"
    } else {
        say "  release_a53: landing pad [hex32 $landing_addr] <- 0x14000000 (b .)"
    }

    # Reset vector low/high
    safe_wr $::REG_APU_RVBAR_L_0 $landing_addr
    safe_wr $::REG_APU_RVBAR_H_0 0x00000000
    say "  release_a53: RVBAR_L_0 <- [hex32 $landing_addr]  RVBAR_H_0 <- 0x00000000"

    # Clear A53 core 0 + power-on + L2 reset bits
    set rst [safe_rd $::REG_RST_FPD_APU]
    if {$rst eq "ERR"} {
        say "  release_a53: WARN couldn't read RST_FPD_APU - release skipped"
        return 0
    }
    set clear_mask [expr {(1 << $::BIT_RST_ACPU0_RESET)        | \
                          (1 << $::BIT_RST_ACPU0_PWRON_RESET)  | \
                          (1 << $::BIT_RST_APU_L2_RESET)}]
    set rst_new [expr {int($rst) & ~$clear_mask}]
    safe_wr $::REG_RST_FPD_APU $rst_new
    catch { uscale.dap dpreg 0 0x1e } _
    after 50
    # Read back so we can verify the release actually took. ZynqMP requires
    # the LPD power-on-reset bits to be deasserted before A53 will actually
    # come out of reset; if a prior reset_a53 left a side-effect bit set we
    # need to know.
    set rv [safe_rd $::REG_RST_FPD_APU]
    if {$rv eq "ERR"} {
        say "  release_a53: WARN couldn't read back RST_FPD_APU - release state unknown"
        return 0
    }
    set still_set [expr {int($rv) & $clear_mask}]
    if {$still_set != 0} {
        say "  release_a53: WARN bits 0x[format %x $still_set] still set in RST_FPD_APU"
        say "               (wrote [hex32 $rst_new] read back [hex32 $rv]) - release incomplete"
        return 0
    }
    say "  release_a53: RST_FPD_APU [hex32 $rst] -> [hex32 $rv] (A53.0 + L2 released)"
    return 1
}

# Re-assert A53 core 0 reset and verify the write took effect.
#
# NOTE: on ZynqMP without PMU FW participation, writing these RST_FPD_APU
# bits does NOT actually reset the A53 core (PC and architectural state
# are preserved). The bits get set in the register and read back, but the
# A53 keeps executing whatever it was doing. The write is useful for its
# DAP-side side effects (AP queue flush, sticky-bit drain) and for the
# next release_a53_core0 call to see a "clean" register state — but it
# should NOT be relied on to interrupt a running A53 fault loop.
proc reset_a53_core0 {} {
    catch { targets uscale.axi } _
    set rn [safe_rd $::REG_RST_FPD_APU]
    if {$rn eq "ERR"} {
        say "  reset_a53: WARN couldn't read RST_FPD_APU - reset state unknown"
        return 0
    }
    set want_mask [expr {(1 << $::BIT_RST_ACPU0_RESET)        | \
                         (1 << $::BIT_RST_ACPU0_PWRON_RESET)  | \
                         (1 << $::BIT_RST_APU_L2_RESET)}]
    set rb [expr {int($rn) | $want_mask}]
    safe_wr $::REG_RST_FPD_APU $rb
    after 5
    set rv [safe_rd $::REG_RST_FPD_APU]
    if {$rv eq "ERR"} {
        say "  reset_a53: WARN couldn't read back RST_FPD_APU"
        return 0
    }
    set actual [expr {int($rv) & $want_mask}]
    if {$actual == $want_mask} {
        say "  A53 reset re-asserted (RST_FPD_APU = [hex32 $rv])"
        return 1
    } else {
        say "  WARN: A53 reset partially applied (RST_FPD_APU = [hex32 $rv]; wanted [hex32 $want_mask])"
        return 0
    }
}

# ---------------------------------------------------------------------------
# reset_release_a53_core0 — BOOTED-STATE variant.
#
# When the board has already booted (FSBL/PMU FW/ATF/U-Boot/Linux running),
# core 0 is OUT of reset and executing at EL2-NS (U-Boot) or EL1 (Linux).
# A plain release_a53_core0 only DEASSERTS the reset bits — but they are
# already clear, so it is a no-op and the core never re-enters at RVBAR;
# the payload would then run at the live (non-EL3) exception level, and a
# `reg pc` redirect of a running core does not stick.
#
# To obtain a clean EL3 core we must do a full reset CYCLE:
#   1. Halt the secondary cores (a53.1/2/3) so Linux's PM activity stops
#      racing the APU<->PMU0 IPI channel while our payload runs.
#   2. ASSERT core-0 reset (reset_a53_core0: ACPU0 + PWRON + L2).
#   3. DEASSERT + set RVBAR (release_a53_core0) so core 0 re-enters at the
#      landing pad at EL3 (reset always enters at the highest implemented EL).
#
# Requires RST_FPD_APU to be writable in booted state — confirmed on this
# board (cleanup re-assert of 0x501 succeeds). Returns 1 on clean release.
proc reset_release_a53_core0 {{landing_addr 0}} {
    if {$landing_addr == 0} { set landing_addr $::ADDR_SAFE_LANDING }
    clear_dp_sticky
    catch { targets uscale.axi } _

    # 1. Freeze the secondary cores (best-effort; ignore per-core failures).
    foreach c {uscale.a53.1 uscale.a53.2 uscale.a53.3} {
        catch { $c arp_examine } _
        catch { $c arp_halt } _
    }
    say "  reset_release: secondary cores a53.1/2/3 halt-requested (freeze Linux)"

    # 2. Assert core-0 reset.
    if {![reset_a53_core0]} {
        say "  reset_release: WARN reset-assert failed - aborting booted-state release"
        return 0
    }
    after 10

    # 3. Deassert + set RVBAR -> core 0 re-enters at landing pad at EL3.
    catch { targets uscale.axi } _
    return [release_a53_core0 $landing_addr]
}


# ---------------------------------------------------------------------------
# R5 core 0 (RPU)
# ---------------------------------------------------------------------------

# Release R5 core 0 from reset. R5 boots from its low vector (0x00000000)
# which maps to global address 0xFFE00000 (ATCM). Caller is responsible
# for having written a valid ARMv7-R payload at 0xFFE00000 before calling
# this. Returns 1 on success.
#
# Configuration applied:
#   - RPU lockstep mode (SLSPLIT=0). Lockstep is safer for our use case
#     because we only need R5_0; split mode would require also configuring
#     R5_1. ZCU102 powers up in lockstep by default.
#   - VINITHI=0 (low vector — R5 boots from 0x0)
#   - TCM split mode (TCM_COMB=0). We only use ATCM (R5-relative 0x0).
#   - Clear R5_0 + RPU_AMBA + RPU_PGE reset bits in CRL_APB.RST_LPD_TOP.
#     (R5_1 stays in reset since we're in lockstep.)
#
# Important: TCM at 0xFFE00000 is only accessible to JTAG mem-AP when
# RPU_0_PWRDWN.EN=0 (R5 powered up). This proc now clears PWRDWN.EN as
# its first step so callers don't need to remember; in practice the
# PMU also needs to honor it (without PMU FW the bit clears but the
# power island may stay off — see M4 in dump-bootrom.tcl).
proc release_r5_core0 {} {
    clear_dp_sticky
    catch { targets uscale.axi } _

    # 0. Clear RPU_0 PWRDWN.EN (bit 0). On a healthy boot the PMU will
    #    bring the island up; without PMU FW the write still takes but
    #    the island may remain off. Either way, do it first so callers
    #    don't have to.
    set pwr [safe_rd $::REG_RPU_0_PWRDWN]
    if {$pwr ne "ERR"} {
        set pwr_new [expr {int($pwr) & ~0x1}]
        safe_wr $::REG_RPU_0_PWRDWN $pwr_new
        say "  release_r5: RPU_0_PWRDWN [hex32 $pwr] -> [hex32 $pwr_new] (EN=0)"
    }

    # 1. RPU GLBL_CNTL: lockstep + split TCM
    set gc [safe_rd $::REG_RPU_GLBL_CNTL]
    if {$gc ne "ERR"} {
        set gc_new [expr {int($gc) & ~((1 << $::BIT_RPU_SLSPLIT) | (1 << $::BIT_RPU_TCM_COMB))}]
        safe_wr $::REG_RPU_GLBL_CNTL $gc_new
        say "  release_r5: RPU_GLBL_CNTL [hex32 $gc] -> [hex32 $gc_new] (lockstep, split TCM)"
    }

    # 2. RPU_0_CFG: VINITHI=0 (low vector), NCPUHALT=1 (running on release)
    set rcfg [safe_rd $::REG_RPU_0_CFG]
    if {$rcfg ne "ERR"} {
        set rcfg_new [expr {(int($rcfg) & ~(1 << $::BIT_RPU_VINITHI)) | (1 << $::BIT_RPU_NCPUHALT)}]
        safe_wr $::REG_RPU_0_CFG $rcfg_new
        say "  release_r5: RPU_0_CFG  [hex32 $rcfg] -> [hex32 $rcfg_new] (VINITHI=0 NCPUHALT=1)"
    }

    # 3. Clear R5_0, AMBA, PGE reset bits (leave R5_1 reset in place)
    set rst [safe_rd $::REG_CRL_RST_LPD_TOP]
    if {$rst eq "ERR"} {
        say "  release_r5: WARN couldn't read CRL_RST_LPD_TOP"
        return 0
    }
    set clear_mask [expr {(1 << $::BIT_RPU_R50_RESET)  | \
                          (1 << $::BIT_RPU_AMBA_RESET) | \
                          (1 << $::BIT_RPU_PGE_RESET)}]
    set rst_new [expr {int($rst) & ~$clear_mask}]
    safe_wr $::REG_CRL_RST_LPD_TOP $rst_new
    say "  release_r5: CRL_RST_LPD_TOP [hex32 $rst] -> [hex32 $rst_new]"
    catch { uscale.dap dpreg 0 0x1e } _
    after 50
    return 1
}

# Re-assert R5 core 0 reset.
proc reset_r5_core0 {} {
    catch { targets uscale.axi } _
    set rn [safe_rd $::REG_CRL_RST_LPD_TOP]
    if {$rn eq "ERR"} {
        say "  reset_r5: WARN couldn't read CRL_RST_LPD_TOP - reset state unknown"
        return 0
    }
    set want_mask [expr {(1 << $::BIT_RPU_R50_RESET)  | \
                         (1 << $::BIT_RPU_AMBA_RESET) | \
                         (1 << $::BIT_RPU_PGE_RESET)}]
    set rb [expr {int($rn) | $want_mask}]
    safe_wr $::REG_CRL_RST_LPD_TOP $rb
    after 5
    set rv [safe_rd $::REG_CRL_RST_LPD_TOP]
    if {$rv ne "ERR" && (int($rv) & $want_mask) == $want_mask} {
        say "  R5 reset re-asserted (CRL_RST_LPD_TOP = [hex32 $rv])"
        return 1
    }
    say "  WARN: R5 reset partially applied (CRL_RST_LPD_TOP = [hex32 $rv])"
    return 0
}
