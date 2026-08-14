"""
zynqmp_general.py — non-security per-field annotations.

Covers clocks (CRL_APB/CRF_APB peripheral REF_CTRLs, ACPU/DBG/GDMA clocks),
PLLs (APLL/DPLL/VPLL/IOPLL/RPLL CTRL+STATUS), power-state (PMU_GLOBAL.PWR_STATE
per-domain bits), and reset state (RST_FPD_APU, RST_FPD_TOP, RST_LPD_TOP,
RST_LPD_IOU0/2, RST_DDR_SS per-block bits).

These fields have well-known meanings even when they're not security-
critical — knowing which CPU cores are powered, which peripherals are in
reset, and which PLLs are locked makes the captured state actually
interpretable.

Wildcard register entries (register="*") match the same field name across
every register that has it — used heavily here because CLKACT, BYPASS,
RESET, LOCK, etc. mean the same thing wherever they appear.

Sources for the semantics here:
  - Xilinx UG1085 Chapter 25 (Clocking) and Chapter 26 (Reset System)
  - Xilinx QEMU register models in /opt/xilinx/qemu/hw/misc/
  - Xilinx PMU power-management documentation
"""

from __future__ import annotations

import sys
from pathlib import Path

_THIS = Path(__file__).resolve()
sys.path.insert(0, str(_THIS.parent.parent.parent / "tools"))

from interpret_lib import Annotation, RegisterAnnotation  # noqa: E402


def _v(label: str, meaning: str) -> dict:
    return {"label": label, "meaning": meaning}


# ---------------------------------------------------------------------------
# Builders for the highly repetitive per-bit fields (PWR_STATE, RST_*).
# ---------------------------------------------------------------------------

def _power_bit(register: str, field: str, what: str) -> Annotation:
    """1 = powered up; 0 = powered down (or never powered, depending on bit).

    Meanings are asymmetric: the 'powered up' case is self-explanatory from
    the label (no meaning), but 'powered down' carries operational info worth
    keeping (bus behavior + how to recover).
    """
    return Annotation(
        register=register,
        field=field,
        description=f"Power state of {what} (1=on, 0=off).",
        values={
            1: _v(label=f"{what} powered up", meaning=""),
            0: _v(label=f"{what} powered down",
                  meaning="Reads to this domain's address space typically return all-1s "
                          "or AXI-timeout. Must be brought up via PMU REQ_PWRUP before use."),
        },
    )


def _reset_bit(register: str, field: str, what: str) -> Annotation:
    """1 = held in reset; 0 = released. ZynqMP reset polarity is active-high.

    Meanings are asymmetric: 'released' is self-explanatory (label sufficient);
    'held in reset' carries operational info (register accessibility, AXI risk).
    """
    return Annotation(
        register=register,
        field=field,
        description=f"Reset state of {what} (1=held in reset, 0=released).",
        values={
            1: _v(label=f"{what} HELD IN RESET",
                  meaning="Functionality inhibited. Register reads may return zeros or "
                          "wedge the AXI bus depending on the block."),
            0: _v(label=f"{what} released", meaning=""),
        },
    )


# ---------------------------------------------------------------------------
# ANNOTATIONS — flat list of Annotation instances.
# ---------------------------------------------------------------------------

ANNOTATIONS: list[Annotation] = [

    # =========================================================================
    # CLOCK CONTROLS — wildcard fields that appear in every *_REF_CTRL and
    # *_CTRL register in CRF_APB and CRL_APB.
    # =========================================================================

    Annotation(
        register="*",
        field="CLKACT",
        description="Clock-gate enable (1=clock active, 0=gated off).",
        values={
            1: _v(label="Clock active",
                  meaning="Reference clock is being driven to the peripheral."),
            0: _v(label="Clock gated",
                  meaning="Clock is gated off at the source. Peripheral cannot run; "
                          "register access from JTAG may still succeed if the block's "
                          "APB clock is separately enabled."),
        },
    ),

    Annotation(
        register="*",
        field="CLKACT_FULL",
        description="Full-rate clock gate (typically for ACPU clock to A53 cluster).",
        values={
            1: _v(label="Full-rate clock active",
                  meaning="A53 cluster receives full-frequency clock."),
            0: _v(label="Full-rate clock gated", meaning="Full-rate clock to cluster is off."),
        },
    ),

    Annotation(
        register="*",
        field="CLKACT_HALF",
        description="Half-rate clock gate (companion to CLKACT_FULL for ACPU).",
        values={
            1: _v(label="Half-rate clock active", meaning="Half-rate path enabled."),
            0: _v(label="Half-rate clock gated", meaning="Half-rate path disabled."),
        },
    ),

    Annotation(
        register="*",
        field="RX_CLKACT",
        description="Receive-side clock gate (GEM Ethernet MAC RX clock).",
        values={
            1: _v(label="RX clock active", meaning="GEM RX path is clocked — link can receive frames."),
            0: _v(label="RX clock gated",
                  meaning="GEM RX clock off. Link cannot receive. Either PHY hasn't been brought up "
                          "yet, or the interface is intentionally disabled."),
        },
    ),

    Annotation(
        register="*",
        field="DIVISOR0",
        description=(
            "First-stage clock divider (6-bit). Output frequency = PLL_OUT / DIVISOR0 / DIVISOR1. "
            "A value of 0 is reserved (treated as 1 by the divider). Common values: 0x18=24 for "
            "UART at 100 MHz LPD_LSBUS, 0x5=5 for 200 MHz I2C ref, 0xC=12 for 100 MHz USB."
        ),
        values={},
    ),

    Annotation(
        register="*",
        field="DIVISOR1",
        description=(
            "Second-stage clock divider (6-bit), cascaded after DIVISOR0. "
            "Typically 0 or 1 for single-stage; >1 for very-low-frequency outputs like GEM 2.5 MHz."
        ),
        values={},
    ),

    Annotation(
        register="*",
        field="SRCSEL",
        description=(
            "PLL source selector. LPD clocks (CRL_APB) typically use: 0=IOPLL, 2=RPLL, 3=DPLL_TO_LPD. "
            "FPD clocks (CRF_APB) typically use: 0=APLL, 2=DPLL, 3=VPLL. Per-register exceptions exist "
            "(e.g. LPD_LSBUS_CTRL uses RPLL=2). See UG1085 Table 38-3."
        ),
        values={
            0: _v(label="IOPLL (LPD) or APLL (FPD)",
                  meaning="Most common source. For LPD peripherals, IOPLL (~1.5 GHz typical). "
                          "For FPD peripherals, APLL (~1.2 GHz typical). Reset default."),
            2: _v(label="RPLL (LPD) or DPLL (FPD)",
                  meaning="Alternate PLL. RPLL is the LPD secondary PLL; DPLL is the DDR PLL "
                          "(also used for some FPD peripherals)."),
            3: _v(label="DPLL→LPD (LPD) or VPLL (FPD)",
                  meaning="Cross-domain or video PLL. DPLL routed to LPD; or VPLL for video pipeline."),
        },
    ),

    # =========================================================================
    # PLL CONTROLS — APLL/DPLL/VPLL (CRF_APB) and IOPLL/RPLL (CRL_APB) all
    # share *_CTRL and *_STATUS layouts.
    # =========================================================================

    Annotation(
        register="*",
        field="FBDIV",
        description=(
            "PLL feedback divider (7-bit). VCO frequency = Fref * FBDIV (typically Fref=33.333 MHz on ZCU102). "
            "Common values: 0x2C=44 → ~1466 MHz VCO, 0x32=50 → ~1666 MHz VCO, 0x28=40 → ~1333 MHz VCO."
        ),
        values={},
    ),

    Annotation(
        register="*",
        field="DIV2",
        description="Post-VCO divide-by-2 enable. When set, PLL output = VCO / 2.",
        values={
            1: _v(label="VCO/2 active",
                  meaning="PLL output is VCO divided by 2. Almost always set on ZynqMP."),
            0: _v(label="VCO direct",
                  meaning="PLL output is the raw VCO frequency. Unusual."),
        },
    ),

    Annotation(
        register="*",
        field="CLKOUTDIV",
        description="Output stage divider select (in addition to DIV2).",
        values={
            0: _v(label="Standard output divider", meaning="Default output divider stage."),
            1: _v(label="Alternate output divider", meaning="Alternate output divider stage."),
        },
    ),

    Annotation(
        register="*",
        field="BYPASS",
        description="PLL bypass — route reference clock directly to output, skipping the PLL.",
        values={
            1: _v(label="PLL BYPASSED",
                  meaning="Output clock is the raw reference (typically 33.333 MHz). PLL is not "
                          "providing frequency multiplication. Common during bring-up; in steady-"
                          "state operation this means the PLL is unused or never came up."),
            0: _v(label="PLL in circuit",
                  meaning="Output is driven by PLL VCO/dividers. Normal operating state."),
        },
    ),

    # NOTE: This wildcard is targeted at *PLL_CTRL.RESET. ZynqMP also has
    # bare `RESET` fields in non-PLL register paths (CSU.CSU_DMA_RESET.RESET,
    # CSU.AES_RESET.RESET, CSU.SHA_RESET.RESET, CSU.PCAP_RESET.RESET) — those
    # are block-level resets, not PLL controls. The four specific annotations
    # below (CSU.<block>_RESET.RESET) win via find_annotation precedence
    # (specific BLOCK.REGISTER > wildcard "*"), so they aren't mis-labeled.
    Annotation(
        register="*",
        field="RESET",
        description="PLL hold-in-reset control. ZynqMP PLLs are active-high reset.",
        values={
            1: _v(label="PLL HELD IN RESET",
                  meaning="PLL is not running. Output is undefined or comes from BYPASS. "
                          "Either bring-up incomplete or PLL is intentionally disabled."),
            0: _v(label="PLL running",
                  meaning="PLL is released from reset. Will lock if FBDIV/CFG are valid."),
        },
    ),

    # CSU block-reset registers (not PLLs) — these win over the wildcard above.
    Annotation(
        register="CSU.CSU_DMA_RESET", field="RESET",
        description="CSU DMA engine soft-reset.",
        values={
            1: _v(label="CSU DMA in soft-reset", meaning="CSU DMA engine is held in reset."),
            0: _v(label="CSU DMA active", meaning="CSU DMA engine is released and operational."),
        },
    ),
    Annotation(
        register="CSU.AES_RESET", field="RESET",
        description="CSU AES hardware engine soft-reset.",
        values={
            1: _v(label="AES engine in soft-reset",
                  meaning="CSU AES crypto block held in reset. Decrypt operations will fail."),
            0: _v(label="AES engine active",
                  meaning="CSU AES engine is released and can perform crypto operations."),
        },
    ),
    Annotation(
        register="CSU.SHA_RESET", field="RESET",
        description="CSU SHA hardware engine soft-reset.",
        values={
            1: _v(label="SHA engine in soft-reset",
                  meaning="CSU SHA hash block held in reset. Hash operations will fail."),
            0: _v(label="SHA engine active",
                  meaning="CSU SHA engine is released and can perform hash operations."),
        },
    ),
    Annotation(
        register="CSU.PCAP_RESET", field="RESET",
        description="PCAP (Programmable Configuration Access Port) soft-reset.",
        values={
            1: _v(label="PCAP in soft-reset",
                  meaning="PCAP block held in reset. PL bitstream loads via PCAP will fail."),
            0: _v(label="PCAP active",
                  meaning="PCAP block released and ready for bitstream operations."),
        },
    ),

    Annotation(
        register="*",
        field="PRE_SRC",
        description="Pre-divider reference source select (3-bit). Typically 0=PS_REF_CLK.",
        values={
            0: _v(label="PS_REF_CLK",
                  meaning="Use the external PS reference clock (33.333 MHz on ZCU102)."),
        },
    ),

    Annotation(
        register="*",
        field="POST_SRC",
        description="Post-divider source select (3-bit). Typically 0=PS_REF_CLK.",
        values={
            0: _v(label="PS_REF_CLK",
                  meaning="Post-divider sourced from the external PS reference clock."),
        },
    ),

    # PLL_STATUS — wildcards because identical fields exist for APLL/DPLL/VPLL/IOPLL/RPLL.

    Annotation(
        register="*",
        field="APLL_LOCK",
        description="APLL phase-lock detector (1=locked).",
        values={
            1: _v(label="APLL LOCKED", meaning="APLL has achieved phase lock — output is stable."),
            0: _v(label="APLL not locked",
                  meaning="APLL has not achieved lock. Either in BYPASS/RESET, or recently programmed and "
                          "still settling, or feedback divider out of valid range."),
        },
    ),
    Annotation(register="*", field="DPLL_LOCK",
               description="DPLL phase-lock detector (1=locked).",
               values={1: _v(label="DPLL LOCKED", meaning="DPLL is locked and stable."),
                       0: _v(label="DPLL not locked",
                             meaning="DPLL not locked. May be in BYPASS/RESET, or DDR controller "
                                     "init never reached PLL programming step.")}),
    Annotation(register="*", field="VPLL_LOCK",
               description="VPLL phase-lock detector (1=locked).",
               values={1: _v(label="VPLL LOCKED", meaning="VPLL is locked."),
                       0: _v(label="VPLL not locked",
                             meaning="VPLL not locked. Video pipeline likely unused.")}),
    Annotation(register="*", field="IOPLL_LOCK",
               description="IOPLL phase-lock detector (1=locked).",
               values={1: _v(label="IOPLL LOCKED",
                             meaning="IOPLL is locked. Most LPD peripherals derive their reference from here."),
                       0: _v(label="IOPLL not locked",
                             meaning="IOPLL not locked. Most LPD peripherals will be running on bypass "
                                     "or have no usable clock.")}),
    Annotation(register="*", field="RPLL_LOCK",
               description="RPLL phase-lock detector (1=locked).",
               values={1: _v(label="RPLL LOCKED", meaning="RPLL is locked."),
                       0: _v(label="RPLL not locked",
                             meaning="RPLL not locked. May be unused depending on which clocks "
                                     "are routed through it.")}),

    Annotation(register="*", field="APLL_STABLE",
               description="APLL output stable indicator (asserts after LOCK + stabilization period).",
               values={1: _v(label="APLL output stable", meaning="Safe for downstream consumers."),
                       0: _v(label="APLL output not stable", meaning="Still in lock-acquisition window or not running.")}),
    Annotation(register="*", field="DPLL_STABLE",
               description="DPLL output stable indicator.",
               values={1: _v(label="DPLL stable", meaning="DPLL output safe for downstream consumers."),
                       0: _v(label="DPLL not stable", meaning="DPLL output not yet stable.")}),
    Annotation(register="*", field="VPLL_STABLE",
               description="VPLL output stable indicator.",
               values={1: _v(label="VPLL stable", meaning="VPLL output stable."),
                       0: _v(label="VPLL not stable", meaning="VPLL output not stable.")}),
    Annotation(register="*", field="IOPLL_STABLE",
               description="IOPLL output stable indicator.",
               values={1: _v(label="IOPLL stable", meaning="IOPLL output stable."),
                       0: _v(label="IOPLL not stable", meaning="IOPLL output not stable.")}),
    Annotation(register="*", field="RPLL_STABLE",
               description="RPLL output stable indicator.",
               values={1: _v(label="RPLL stable", meaning="RPLL output stable."),
                       0: _v(label="RPLL not stable", meaning="RPLL output not stable.")}),

    # =========================================================================
    # POWER STATE — PMU_GLOBAL.PWR_STATE per-domain bits.
    # =========================================================================

    _power_bit("PMU_GLOBAL.PWR_STATE", "ACPU0", "A53 core 0"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "ACPU1", "A53 core 1"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "ACPU2", "A53 core 2"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "ACPU3", "A53 core 3"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "R5_0", "Cortex-R5 core 0 (RPU lock-step master)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "R5_1", "Cortex-R5 core 1 (RPU split-mode only)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "TCM0A", "R5_0 TCM bank A (32 KB)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "TCM0B", "R5_0 TCM bank B (32 KB)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "TCM1A", "R5_1 TCM bank A (32 KB, split mode only)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "TCM1B", "R5_1 TCM bank B (32 KB, split mode only)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "OCM_BANK0", "OCM bank 0 (64 KB at 0xFFFC0000)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "OCM_BANK1", "OCM bank 1 (64 KB at 0xFFFD0000)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "OCM_BANK2", "OCM bank 2 (64 KB at 0xFFFE0000)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "OCM_BANK3", "OCM bank 3 (64 KB at 0xFFFF0000, ATF region)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "USB0", "USB0 controller power island"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "USB1", "USB1 controller power island"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "PP0", "GPU Mali-400 pixel processor 0"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "PP1", "GPU Mali-400 pixel processor 1"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "L2_BANK0", "APU L2 cache bank 0"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "FP", "Full-power domain (FPD)"),
    _power_bit("PMU_GLOBAL.PWR_STATE", "PL", "Programmable Logic (FPGA fabric)"),

    # PMU_GLOBAL.REQ_PWR{UP,DOWN}_STATUS expose latched-request state. Same
    # FIELD names also appear on the INT_MASK/INT_EN/INT_DIS/TRIG mirrors,
    # where the semantics differ — those are NOT "request pending" but
    # "interrupt masking" / write-only enables / write-only triggers. The
    # annotations below are scoped to the two STATUS registers explicitly
    # (no wildcard) so the mirror registers fall back to the field-name-only
    # display, which is the honest behaviour.

    Annotation(register="PMU_GLOBAL.REQ_PWRUP_STATUS", field="RPU",
               description="RPU power-up request latched at the PMU.",
               values={
                   1: _v(label="RPU power-up request pending",
                         meaning="A power-up request for the RPU domain has been latched. "
                                 "Cleared when PMU completes the action."),
                   0: _v(label="No RPU power-up request pending",
                         meaning="No pending RPU power-up transition."),
               }),
    Annotation(register="PMU_GLOBAL.REQ_PWRDWN_STATUS", field="RPU",
               description="RPU power-down request latched at the PMU.",
               values={
                   1: _v(label="RPU power-down request pending",
                         meaning="A power-down request for the RPU domain has been latched. "
                                 "Cleared when PMU completes the action."),
                   0: _v(label="No RPU power-down request pending",
                         meaning="No pending RPU power-down transition."),
               }),

    # =========================================================================
    # PMU_GLOBAL.GLOBAL_CTRL (a.k.a. GLOBAL_CNTRL) — PMU configuration bits.
    # =========================================================================

    Annotation(
        register="PMU_GLOBAL.GLOBAL_CNTRL",
        field="FW_IS_PRESENT",
        description="Set by PMU firmware once it has finished init. Lets APU/RPU detect PMU FW.",
        values={
            1: _v(label="PMU firmware loaded",
                  meaning="PMU firmware (PMU_FW) has come up and signed in. APU can request power "
                          "management services via IPI."),
            0: _v(label="PMU firmware NOT loaded",
                  meaning="No PMU firmware running. ZynqMP is in PMU-ROM-only mode (JTAG-idle or "
                          "very early boot). PM API calls from APU will not respond."),
        },
    ),

    Annotation(
        register="PMU_GLOBAL.GLOBAL_CNTRL",
        field="MB_SLEEP",
        description="MicroBlaze sleep state — set when PMU MB core is in WFI / low-power idle.",
        values={
            1: _v(label="PMU MicroBlaze sleeping",
                  meaning="PMU MB core is in WFI. Will wake on IPI, PIT timer, or interrupt."),
            0: _v(label="PMU MicroBlaze active",
                  meaning="PMU MB is executing instructions."),
        },
    ),

    Annotation(
        register="PMU_GLOBAL.GLOBAL_CNTRL",
        field="DONT_SLEEP",
        description="Prevents PMU MB from entering sleep (typically clear in production).",
        values={
            1: _v(label="Sleep inhibited",
                  meaning="PMU MB will not enter sleep. Burns power but reduces wake latency."),
            0: _v(label="Sleep allowed",
                  meaning="PMU MB may enter sleep when idle. Normal production setting."),
        },
    ),

    Annotation(
        register="PMU_GLOBAL.GLOBAL_CNTRL",
        field="SLVERR_ENABLE",
        description="Generate SLVERR responses on bad PMU register accesses.",
        values={
            1: _v(label="SLVERR enabled",
                  meaning="Bad PMU register accesses generate AXI SLVERR."),
            0: _v(label="SLVERR disabled",
                  meaning="Bad accesses return data without error. Default — masks bugs but easier to bring up."),
        },
    ),

    Annotation(
        register="PMU_GLOBAL.GLOBAL_CNTRL",
        field="COHERENT",
        description="Marks PMU accesses as coherent for the CCI (Cache Coherent Interconnect).",
        values={
            1: _v(label="PMU accesses coherent",
                  meaning="PMU AXI traffic participates in CCI coherency."),
            0: _v(label="PMU accesses non-coherent",
                  meaning="PMU AXI traffic does not participate in coherency."),
        },
    ),

    # =========================================================================
    # RESET — APU cluster reset bits (CRF_APB.RST_FPD_APU).
    # =========================================================================

    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU0_RESET",       "A53 core 0 functional reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU1_RESET",       "A53 core 1 functional reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU2_RESET",       "A53 core 2 functional reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU3_RESET",       "A53 core 3 functional reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU0_PWRON_RESET", "A53 core 0 power-on reset (deeper than functional)"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU1_PWRON_RESET", "A53 core 1 power-on reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU2_PWRON_RESET", "A53 core 2 power-on reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "ACPU3_PWRON_RESET", "A53 core 3 power-on reset"),
    _reset_bit("CRF_APB.RST_FPD_APU", "APU_L2_RESET",      "APU L2 cache controller"),

    # =========================================================================
    # RESET — FPD top-level peripherals (CRF_APB.RST_FPD_TOP).
    # =========================================================================

    _reset_bit("CRF_APB.RST_FPD_TOP", "PCIE_CFG_RESET",    "PCIe config/CSR block"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "PCIE_BRIDGE_RESET", "PCIe AXI bridge"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "PCIE_CTRL_RESET",   "PCIe controller core"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "DP_RESET",          "DisplayPort controller"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "SWDT_RESET",        "FPD system watchdog timer"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM0_RESET",     "AFI FPD-PL master 0"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM1_RESET",     "AFI FPD-PL master 1"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM2_RESET",     "AFI FPD-PL master 2"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM3_RESET",     "AFI FPD-PL master 3"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM4_RESET",     "AFI FPD-PL master 4"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "AFI_FM5_RESET",     "AFI FPD-PL master 5"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "GDMA_RESET",        "FPD GDMA (general-purpose DMA)"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "GPU_RESET",         "GPU Mali-400 cluster"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "GPU_PP0_RESET",     "GPU pixel processor 0"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "GPU_PP1_RESET",     "GPU pixel processor 1"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "GT_RESET",          "Gigabit transceiver (SERDES)"),
    _reset_bit("CRF_APB.RST_FPD_TOP", "SATA_RESET",        "SATA host controller"),

    # =========================================================================
    # RESET — DDR subsystem (CRF_APB.RST_DDR_SS).
    # =========================================================================

    _reset_bit("CRF_APB.RST_DDR_SS", "DDR_RESET", "DDR controller"),
    _reset_bit("CRF_APB.RST_DDR_SS", "APM_RESET", "DDR AXI Performance Monitor"),

    # =========================================================================
    # RESET — LPD IOU group 0 (GEM Ethernet, CRL_APB.RST_LPD_IOU0).
    # =========================================================================

    _reset_bit("CRL_APB.RST_LPD_IOU0", "GEM0_RESET", "GEM0 Ethernet MAC"),
    _reset_bit("CRL_APB.RST_LPD_IOU0", "GEM1_RESET", "GEM1 Ethernet MAC"),
    _reset_bit("CRL_APB.RST_LPD_IOU0", "GEM2_RESET", "GEM2 Ethernet MAC"),
    _reset_bit("CRL_APB.RST_LPD_IOU0", "GEM3_RESET", "GEM3 Ethernet MAC"),

    # =========================================================================
    # RESET — LPD IOU group 2 (CRL_APB.RST_LPD_IOU2). Largest reset register.
    # =========================================================================

    _reset_bit("CRL_APB.RST_LPD_IOU2", "QSPI_RESET",       "QSPI flash controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "UART0_RESET",      "PS UART0 (APU console on ZCU102)"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "UART1_RESET",      "PS UART1"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "SPI0_RESET",       "SPI0 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "SPI1_RESET",       "SPI1 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "SDIO0_RESET",      "SD/eMMC controller 0"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "SDIO1_RESET",      "SD/eMMC controller 1"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "CAN0_RESET",       "CAN0 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "CAN1_RESET",       "CAN1 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "I2C0_RESET",       "I2C0 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "I2C1_RESET",       "I2C1 controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "TTC0_RESET",       "Triple-timer counter 0"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "TTC1_RESET",       "Triple-timer counter 1"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "TTC2_RESET",       "Triple-timer counter 2"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "TTC3_RESET",       "Triple-timer counter 3"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "SWDT_RESET",       "LPD system watchdog timer"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "NAND_RESET",       "NAND flash controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "ADMA_RESET",       "LPD ADMA (advanced DMA)"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "GPIO_RESET",       "MIO/EMIO GPIO controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "IOU_CC_RESET",     "IOU clock controller"),
    _reset_bit("CRL_APB.RST_LPD_IOU2", "TIMESTAMP_RESET",  "Global timestamp generator"),

    # =========================================================================
    # RESET — LPD top-level (CRL_APB.RST_LPD_TOP). RPU cores live here.
    # =========================================================================

    _reset_bit("CRL_APB.RST_LPD_TOP", "RPU_R50_RESET",   "Cortex-R5 core 0"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "RPU_R51_RESET",   "Cortex-R5 core 1"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "RPU_AMBA_RESET",  "RPU AMBA/AXI fabric"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "RPU_PGE_RESET",   "RPU PGE (program-generation engine)"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "OCM_RESET",       "OCM (on-chip SRAM) controller"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB0_CORERESET",  "USB0 core reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB1_CORERESET",  "USB1 core reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB0_HIBERRESET", "USB0 hibernation block reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB1_HIBERRESET", "USB1 hibernation block reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB0_APB_RESET",  "USB0 APB register interface reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "USB1_APB_RESET",  "USB1 APB register interface reset"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "IPI_RESET",       "Inter-Processor Interrupt block"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "APM_RESET",       "LPD AXI Performance Monitor"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "RTC_RESET",       "Real-time clock"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "SYSMON_RESET",    "System monitor (SYSMON)"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "AFI_FM6_RESET",   "AFI LPD-PL master 6"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "LPD_SWDT_RESET",  "LPD watchdog timer"),
    _reset_bit("CRL_APB.RST_LPD_TOP", "FPD_RESET",       "FPD (full-power domain) global reset"),

    # =========================================================================
    # RESET REASON — CRL_APB.RESET_REASON.
    # =========================================================================

    Annotation(
        register="CRL_APB.RESET_REASON",
        field="EXTERNAL_POR",
        description="External power-on reset (PS_POR_B pin asserted).",
        values={
            1: _v(label="External POR occurred",
                  meaning="Last reset was an external power-on (PS_POR_B pin). Expected on first boot."),
            0: _v(label="No external POR", meaning="Last reset was not an external POR."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="INTERNAL_POR",
        description="Internal power-on reset (e.g. PMU-initiated cold reset).",
        values={
            1: _v(label="Internal POR occurred",
                  meaning="PMU initiated a cold reset of the entire PS."),
            0: _v(label="No internal POR", meaning="No internal POR."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="PMU_SYS_RESET",
        description="System reset requested by PMU firmware.",
        values={
            1: _v(label="PMU SYS_RESET occurred",
                  meaning="PMU firmware initiated a system-level reset (warm reset, not POR)."),
            0: _v(label="No PMU SYS_RESET", meaning="No PMU-driven system reset."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="PSONLY_RESET_REQ",
        description="PS-only reset (PL untouched).",
        values={
            1: _v(label="PS-only reset occurred",
                  meaning="The PS was reset but the PL configuration was preserved. Common during dev."),
            0: _v(label="No PS-only reset", meaning="No PS-only reset event."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="SRST",
        description="System reset (SRST_B pin or equivalent).",
        values={
            1: _v(label="SRST occurred", meaning="Soft system reset via SRST_B pin."),
            0: _v(label="No SRST", meaning="No SRST event."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="SOFT",
        description="Software-initiated reset.",
        values={
            1: _v(label="Software reset occurred",
                  meaning="Reset was driven by a software write to a reset register."),
            0: _v(label="No software reset", meaning="No software reset."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="DEBUG_SYS",
        description="Debugger-initiated system reset.",
        values={
            1: _v(label="Debug-system reset occurred",
                  meaning="Reset was initiated by the debug subsystem (typically via JTAG)."),
            0: _v(label="No debug-system reset", meaning="No debug-initiated reset."),
        },
    ),
    Annotation(
        register="CRL_APB.RESET_REASON",
        field="MIMIC",
        description="MIMIC reset (rare — internal Xilinx debug feature).",
        values={
            1: _v(label="MIMIC reset",
                  meaning="MIMIC-class reset — internal debug feature, rarely seen in the field."),
            0: _v(label="No MIMIC reset", meaning="No MIMIC reset."),
        },
    ),

    # =========================================================================
    # CSU.IDCODE — IEEE 1149.1 fields (well-defined, not Xilinx-specific).
    # =========================================================================

    Annotation(
        register="CSU.IDCODE",
        field="MANUF_ID",
        description="JEDEC manufacturer ID (11 bits). Xilinx = 0x49 (decimal 73).",
        values={73: _v(label="Xilinx (JEDEC 0x49)",
                       meaning="Standard Xilinx manufacturer code. Confirms this is a Xilinx device.")},
    ),
    Annotation(
        register="CSU.IDCODE",
        field="CONST_1",
        description="IEEE 1149.1 constant — always 1 by spec.",
        values={1: _v(label="OK (always 1 by IEEE 1149.1)",
                      meaning="Mandatory constant bit. Any other value would indicate a fundamentally broken IDCODE.")},
    ),
    Annotation(
        register="CSU.IDCODE",
        field="REVISION",
        description="Silicon revision (4 bits). 0=engineering sample; 1+=production stepping.",
        values={
            0: _v(label="Engineering sample / first silicon",
                  meaning="REV0 — engineering sample. Unusual in the field; most production parts are REV2+."),
            1: _v(label="Production revision 1", meaning="First production stepping."),
            2: _v(label="Production revision 2", meaning="Common production stepping for ZU+ (mid-2010s parts)."),
            3: _v(label="Production revision 3", meaning="Later production stepping."),
        },
    ),
    Annotation(
        register="CSU.IDCODE",
        field="PART_ID",
        description="Xilinx part identifier (16 bits). Used to determine die/family via the variant lookup table.",
        values={},  # Too many; description is enough — variant lookup section covers part decoding.
    ),

    # =========================================================================
    # RPU — Cortex-R5 cluster configuration (0xFF9A0000).
    # =========================================================================

    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="SLSPLIT",
        description="R5 cluster mode select — lockstep vs split.",
        values={
            0: _v(label="LOCKSTEP mode",
                  meaning="Both R5 cores execute the same instruction stream in cycle-step "
                          "lockstep. R5_1 is clamped to R5_0. Used for safety-critical "
                          "code (automotive, industrial). Standalone R5_1 is unreachable "
                          "in this mode."),
            1: _v(label="SPLIT mode",
                  meaning="R5_0 and R5_1 run independently as two separate cores. Standard "
                          "for asymmetric workloads. R5_1 has its own TCM (TCM1A/TCM1B), "
                          "VBAR, and execution state."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="SLCLAMP",
        description="Lockstep clamp — forces R5_1 to follow R5_0 (companion to SLSPLIT).",
        values={
            0: _v(label="Clamp inactive",
                  meaning="R5_1 is not clamped. Combined with SLSPLIT=1 means true split mode."),
            1: _v(label="R5_1 CLAMPED to R5_0",
                  meaning="R5_1 outputs are tied to R5_0 — used during lockstep mode "
                          "transition or when lockstep is fully active."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="TEINIT",
        description="Initial Thumb-mode state on reset (T bit of CPSR at reset).",
        values={
            0: _v(label="ARM mode at reset",
                  meaning="R5 boots in ARM (32-bit instruction) mode. Standard for most "
                          "ZynqMP firmware (FSBL stage, FreeRTOS, baremetal)."),
            1: _v(label="Thumb mode at reset",
                  meaning="R5 boots in Thumb (16-bit) mode. Unusual."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="TCM_COMB",
        description="TCM combine mode — concatenate R5_0 and R5_1 TCMs into one block.",
        values={
            0: _v(label="TCMs separate",
                  meaning="Each R5 has its own TCM (32+32 KB each). Standard split-mode layout."),
            1: _v(label="TCMs COMBINED",
                  meaning="R5_0 sees a 128 KB TCM (its own + R5_1's). Used in lockstep mode "
                          "to give the single active core access to all TCM."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="DBGNOCLKSTOP",
        description="Prevent clock-stop while debugger is attached.",
        values={
            0: _v(label="Clock stop allowed in debug",
                  meaning="RPU clocks can be gated even with debugger attached. May cause "
                          "debugger to lose connection during low-power states."),
            1: _v(label="Clock stop INHIBITED for debug",
                  meaning="RPU clocks remain active while debugger is attached — keeps "
                          "JTAG link reliable across power-management events."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="GIC_AXPROT",
        description="AXI protection level for the R5 GIC interface.",
        values={
            0: _v(label="Non-secure GIC accesses",
                  meaning="R5 GIC AXI traffic uses non-secure AXPROT."),
            1: _v(label="Secure GIC accesses",
                  meaning="R5 GIC AXI traffic uses secure AXPROT. Lets R5 talk to "
                          "TZ-secured GIC distributor entries."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="CFGIE",
        description="Initial IRQ enable state after reset (CPSR.I bit complement at reset).",
        values={
            0: _v(label="IRQ disabled at reset",
                  meaning="R5 boots with IRQs masked. Boot code must explicitly enable."),
            1: _v(label="IRQ enabled at reset",
                  meaning="R5 boots with IRQs enabled. Boot code must be ready to handle interrupts immediately."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_CNTL",
        field="CFGEE",
        description="Initial endian-state for exception entries (CPSR.E bit at reset).",
        values={
            0: _v(label="Little-endian at reset",
                  meaning="R5 boots in little-endian mode. Standard for ZynqMP."),
            1: _v(label="Big-endian at reset",
                  meaning="R5 boots in big-endian mode. Very unusual."),
        },
    ),
    Annotation(
        register="RPU.RPU_GLBL_STATUS",
        field="DBGNOPWRDWN",
        description="Mirror of debug power-down inhibit — debugger is currently keeping power up.",
        values={
            0: _v(label="No debug power hold",
                  meaning="No debugger requesting power. RPU may be powered down by PMU."),
            1: _v(label="Debug holding power up",
                  meaning="Debugger has requested power stay on. RPU is held powered while connected."),
        },
    ),

    # ---- RPU_0_CFG (R5_0 per-core config) ----

    Annotation(
        register="RPU.RPU_0_CFG",
        field="NCPUHALT",
        description="R5_0 halt control. Inverted: 1=released, 0=halted (note the N prefix).",
        values={
            0: _v(label="R5_0 HELD (halted)",
                  meaning="R5_0 is halted — does not fetch instructions. Default state until "
                          "FSBL or JTAG releases it. JTAG-equivalent halt."),
            1: _v(label="R5_0 released (running)",
                  meaning="R5_0 is released and fetching instructions. Whether it actually "
                          "executes depends on reset state (RST_LPD_TOP.RPU_R50_RESET) and "
                          "power state (PWR_STATE.R5_0)."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_CFG",
        field="VINITHI",
        description="R5_0 vector base address selector — low (0x0) vs high (0xFFFF0000).",
        values={
            0: _v(label="Vectors at 0x00000000",
                  meaning="R5_0 fetches exception vectors from low memory (start of TCM or "
                          "wherever 0x0 is mapped)."),
            1: _v(label="Vectors at 0xFFFF0000 (HIVECS)",
                  meaning="R5_0 fetches exception vectors from high memory (0xFFFF0000). "
                          "Standard for VxWorks and most RTOS that expect HIVECS layout. "
                          "Whoever controls 0xFFFF0000+ controls R5_0's exception handlers."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_CFG",
        field="COHERENT",
        description="R5_0 AXI snoop-coherency participation.",
        values={
            0: _v(label="R5_0 non-coherent",
                  meaning="R5_0 AXI traffic does not snoop other masters. Standard for "
                          "ZynqMP — R5 typically uses TCM for hot data, no need for coherency."),
            1: _v(label="R5_0 SNOOP-COHERENT",
                  meaning="R5_0 participates in cache coherency with other masters via CCI. "
                          "Unusual; only used for tight RPU↔APU shared-data workloads."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_CFG",
        field="CFGNMFI0",
        description="R5_0 non-maskable FIQ enable at reset.",
        values={
            0: _v(label="FIQ maskable", meaning="R5_0 FIQs can be masked by CPSR.F."),
            1: _v(label="FIQ NON-MASKABLE",
                  meaning="R5_0 FIQs cannot be masked. Used for safety-critical interrupts "
                          "(watchdog, voltage monitor) that must always be serviced."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_STATUS",
        field="NVALRESET",
        description="R5_0 valid-reset indicator (inverted: 1=valid, 0=in-reset).",
        values={
            0: _v(label="R5_0 in reset", meaning="R5_0 is currently in reset state."),
            1: _v(label="R5_0 out of reset", meaning="R5_0 has been released from reset."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_STATUS",
        field="NVALIRQ",
        description="R5_0 IRQ line active (inverted polarity).",
        values={
            0: _v(label="R5_0 IRQ pending", meaning="An IRQ is currently asserted to R5_0."),
            1: _v(label="R5_0 IRQ idle", meaning="No IRQ pending to R5_0 right now."),
        },
    ),
    Annotation(
        register="RPU.RPU_0_STATUS",
        field="NVALFIQ",
        description="R5_0 FIQ line active (inverted polarity).",
        values={
            0: _v(label="R5_0 FIQ pending", meaning="An FIQ is currently asserted to R5_0."),
            1: _v(label="R5_0 FIQ idle", meaning="No FIQ pending to R5_0 right now."),
        },
    ),

    # ---- RPU_1_CFG / STATUS — same fields as R5_0, name-suffixed where needed ----

    Annotation(
        register="RPU.RPU_1_CFG",
        field="NCPUHALT",
        description="R5_1 halt control. Inverted: 1=released, 0=halted.",
        values={
            0: _v(label="R5_1 HELD (halted)",
                  meaning="R5_1 is halted. In lockstep mode (SLSPLIT=0) this bit is irrelevant — "
                          "R5_1 follows R5_0. Meaningful only in split mode."),
            1: _v(label="R5_1 released (running)",
                  meaning="R5_1 is released. Only effective in split mode and with R5_1 powered + out of reset."),
        },
    ),
    Annotation(
        register="RPU.RPU_1_CFG",
        field="VINITHI",
        description="R5_1 vector base address selector — low (0x0) vs high (0xFFFF0000).",
        values={
            0: _v(label="Vectors at 0x00000000",
                  meaning="R5_1 fetches exception vectors from low memory."),
            1: _v(label="Vectors at 0xFFFF0000 (HIVECS)",
                  meaning="R5_1 fetches exception vectors from high memory."),
        },
    ),
    Annotation(
        register="RPU.RPU_1_CFG",
        field="COHERENT",
        description="R5_1 AXI snoop-coherency participation.",
        values={
            0: _v(label="R5_1 non-coherent", meaning="R5_1 AXI traffic does not snoop other masters."),
            1: _v(label="R5_1 SNOOP-COHERENT", meaning="R5_1 participates in CCI coherency."),
        },
    ),

    Annotation(
        register="RPU.RPU_1_STATUS",
        field="NVALRESET",
        description="R5_1 valid-reset indicator (inverted: 1=valid, 0=in-reset).",
        values={
            0: _v(label="R5_1 in reset", meaning="R5_1 is currently in reset state."),
            1: _v(label="R5_1 out of reset", meaning="R5_1 has been released from reset."),
        },
    ),
]


# ---------------------------------------------------------------------------
# REGISTER_ANNOTATIONS — non-security fieldless registers worth a note.
# ---------------------------------------------------------------------------

REGISTER_ANNOTATIONS = [
    # RPU_0_SLV_BASE / RPU_1_SLV_BASE expose where the per-core TCM is
    # visible to other masters on the LPD bus. QEMU models a single ADDR
    # field at bits [7:0] — that's actually the upper byte of the base
    # address (the lower 24 bits are fixed at zero in the slave window).
    # Defaults per UG1085: 0xFFE00000 for R5_0, 0xFFE20000 for R5_1.
    RegisterAnnotation(
        register="RPU.RPU_0_SLV_BASE",
        description=(
            "R5_0 slave-port base address on the LPD bus. The ADDR field "
            "(bits 7:0) supplies the upper byte; lower 24 bits are zero. "
            "Default 0xFF — slave window starts at 0xFF000000 + offset, with "
            "the TCM aliased at 0xFFE00000. A non-default value indicates the "
            "slave window has been relocated."
        ),
        interpret=lambda v: (
            f"Slave window upper byte = 0x{v & 0xFF:02X}; "
            f"resolves to AXI base 0x{(v & 0xFF) << 24:08X}."
        ),
    ),
    RegisterAnnotation(
        register="RPU.RPU_1_SLV_BASE",
        description=(
            "R5_1 slave-port base address on the LPD bus. Default upper-byte "
            "value places the window at 0xFF000000 + offset (TCM aliased at "
            "0xFFE20000). Meaningful only when R5_1 is active (SLSPLIT=1)."
        ),
        interpret=lambda v: (
            f"Slave window upper byte = 0x{v & 0xFF:02X}; "
            f"resolves to AXI base 0x{(v & 0xFF) << 24:08X}."
        ),
    ),

    # =========================================================================
    # IPI — per-register meaning. The bit fields (APU/RPU_x/PMU_x/PL_x) are
    # self-explanatory once you know what the register itself represents;
    # the meaning lives at the register level.
    # =========================================================================

    RegisterAnnotation(
        register="IPI.IPI_TRIG",
        description=(
            "IPI trigger register. Write a 1 to a bit to fire an interrupt to "
            "that destination agent from THIS agent's perspective. Reads return "
            "0; the act of writing is the trigger. Non-zero values seen here "
            "during enumeration are unusual (writes don't persist) and likely "
            "indicate a transient state of the bus."
        ),
        interpret=lambda v: (
            "No triggers currently asserted." if v == 0
            else f"Active trigger bits = 0x{v:08X}. Bits 0=APU, 8/9=RPU_0/1, "
                 f"16-19=PMU_0..3, 24-27=PL_0..3."
        ),
    ),

    RegisterAnnotation(
        register="IPI.IPI_OBS",
        description=(
            "IPI observation register — SENDER-side (UG1085 ch.13). Each bit is 1 while a "
            "message THIS agent triggered (via IPI_TRIG) is still pending in the DESTINATION's "
            "status register, i.e. NOT yet acked by the receiver. Lets the sender ask 'has the "
            "message I sent been consumed yet?' — poll until the bit clears. It is NOT an inbound "
            "'is anyone trying to talk to me' indicator (that is IPI_ISR)."
        ),
        interpret=lambda v: (
            "No outstanding IPIs that APU sent are still pending in a receiver." if v == 0
            else f"APU-sent IPIs still unacked by their receivers: 0x{v:08X}. "
                 f"Bits 0=APU, 8/9=RPU_0/1, 16-19=PMU_0..3, 24-27=PL_0..3 (the DESTINATION)."
        ),
    ),

    RegisterAnnotation(
        register="IPI.IPI_ISR",
        description=(
            "IPI interrupt status register. Each bit latches when an IPI "
            "arrives from the corresponding source agent and not yet cleared. "
            "Cleared by writing 1. Snapshot here shows which inter-processor "
            "interrupts are currently waiting for APU to service."
        ),
        interpret=lambda v: (
            "No latched IPI interrupts at APU." if v == 0
            else f"Latched IPI sources at APU: 0x{v:08X}. APU has received "
                 f"and not yet acknowledged IPIs from the bits set above."
        ),
    ),

    RegisterAnnotation(
        register="IPI.IPI_IMR",
        description=(
            "IPI interrupt mask register. Each bit, when set, masks (blocks) "
            "IPIs from that source agent from generating an interrupt to APU. "
            "Read-only — set via IEN/IDS write-only registers. Reset default "
            "is all-ones (everything masked) until firmware enables specific "
            "channels."
        ),
        interpret=lambda v: (
            "All IPI sources unmasked — APU receives interrupts from every agent." if v == 0
            else (f"All IPI sources masked at APU (firmware hasn't enabled any IPI channel)."
                  if v == 0x0F0F0301
                  else f"IPI mask = 0x{v:08X}. Bits set = source masked.")
        ),
    ),
]

