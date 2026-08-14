"""
zynqmp_security.py — per-field annotations for security-relevant registers.

Annotations describe the human meaning of individual bit fields. Used by
tools/interpret.py to pair each captured field value with its security-
research interpretation.

Each entry is an `Annotation` dataclass instance. Fields are annotated only
when interpretation isn't obvious from the field name alone. Fields that
are pure data (DNA, counts, capacities, free-form values) are not annotated
— the raw value carries the meaning.

Sources for the semantics here:
  - Xilinx UG1085 (ZynqMP Technical Reference Manual)
  - Xilinx QEMU register models (the bit positions themselves)
  - github.com/Xilinx/u-boot-xlnx
  - github.com/Xilinx/embeddedsw
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow importing interpret_lib from sibling tools/ directory
_THIS = Path(__file__).resolve()
sys.path.insert(0, str(_THIS.parent.parent.parent / "tools"))

from interpret_lib import Annotation, RegisterAnnotation  # noqa: E402


# Convenience for value-specific entries — keep entries consistent.
def _v(label: str, meaning: str, expected_state: str = "",
       offensive_use: list | None = None) -> dict:
    d = {"label": label, "meaning": meaning}
    if expected_state:
        d["expected_state"] = expected_state
    if offensive_use:
        d["offensive_use"] = offensive_use
    return d


ANNOTATIONS: list[Annotation] = [

    # =========================================================================
    # CSU.JTAG_DAP_CFG  — APU and RPU debug authorization gates
    # =========================================================================

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_APU_DBGEN",
        description=(
            "Enables APU (Cortex-A53) invasive non-secure debug. "
            "Cluster-wide gate (not per-core, despite older script versions "
            "claiming otherwise)."
        ),
        values={
            0: _v(
                label="APU non-secure debug gated",
                meaning=(
                    "JTAG cannot halt, step, or set breakpoints on A53 cores "
                    "running in EL0/EL1/EL2. Production firmware typically "
                    "clears this for fielded devices unless live debug is needed."
                ),
                expected_state="hardened-production",
            ),
            1: _v(
                label="APU non-secure debug enabled",
                meaning=(
                    "JTAG can halt, single-step, and breakpoint A53 cores at "
                    "EL0/EL1/EL2. Standard for dev kits; on a production device "
                    "this means the OS running on the A53 is fully debuggable. "
                    "Useful for kernel-level attacks and runtime modification, "
                    "though TrustZone secure world is still protected (see "
                    "SPIDEN separately)."
                ),
                expected_state="dev | partial-hardening",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_APU_NIDEN",
        description=(
            "Enables APU non-invasive trace (CoreSight ETM output) without "
            "requiring a halt. Lower-impact than DBGEN — trace doesn't pause "
            "execution."
        ),
        values={
            0: _v(
                label="APU non-secure trace gated",
                meaning="ETM traces from non-secure-world A53 execution are blocked.",
                expected_state="hardened-production",
            ),
            1: _v(
                label="APU non-secure trace enabled",
                meaning=(
                    "ETM trace allowed — observer can watch instruction flow + "
                    "memory accesses in real time without halting the CPU. "
                    "Useful for side-channel timing analysis and exploit "
                    "instrumentation."
                ),
                expected_state="dev",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_APU_SPIDEN",
        description=(
            "**The single most consequential security bit on ZynqMP.** Enables "
            "invasive debug into the APU's secure world (EL3 / TrustZone). On "
            "a properly hardened device this is gated."
        ),
        values={
            0: _v(
                label="Secure debug gated",
                meaning=(
                    "TrustZone secure-world execution (EL3 monitor, TrustZone OS) "
                    "is protected from JTAG halt/inspect. Attacker cannot directly "
                    "read secure-world memory or install rogue EL3 handlers via JTAG."
                ),
                expected_state="hardened-production",
            ),
            1: _v(
                label="Secure debug WIDE OPEN",
                meaning=(
                    "JTAG can halt the A53 in EL3, inspect every secret the "
                    "secure world holds (AES keys, attestation material, "
                    "anti-rollback counters), modify the EL3 monitor in place, "
                    "and install a TrustZone rootkit. Direct attack primitive — "
                    "no fault injection required. Every encrypted-boot key the "
                    "device uses becomes readable. Expected only on dev kits / "
                    "engineering samples; production should clear this."
                ),
                expected_state="factory-dev",
                offensive_use=[
                    "Direct AES key extraction from secure-world memory or eFUSE shadow",
                    "EL3 handler injection (TrustZone rootkit)",
                    "Secure-world memory dump for offline analysis",
                    "Removes need for fault-injection attacks against secure boot",
                ],
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_APU_SPNIDEN",
        description=(
            "Enables non-invasive trace of secure-world A53 execution. Pairs "
            "with SPIDEN — when SPIDEN is gated but SPNIDEN is set, you can "
            "observe secure world without halting it."
        ),
        values={
            0: _v(
                label="Secure trace gated",
                meaning="Cannot observe TrustZone secure-world execution via JTAG trace.",
                expected_state="hardened-production",
            ),
            1: _v(
                label="Secure trace enabled",
                meaning=(
                    "Secure-world execution traces are visible to JTAG. Enables "
                    "passive observation of EL3 monitor activity — when AES keys "
                    "are loaded, what syscalls the TrustZone OS handles, timing of "
                    "secure operations. Timing side-channel attacks become trivial."
                ),
                expected_state="dev",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_RPU_DBGEN",
        description="Enables RPU (Cortex-R5) invasive debug. Cluster-wide for both R5 cores.",
        values={
            0: _v(
                label="RPU debug gated",
                meaning="Cannot halt or step the R5 real-time cluster from JTAG.",
                expected_state="hardened-production",
            ),
            1: _v(
                label="RPU debug enabled",
                meaning=(
                    "R5 cluster fully debuggable from JTAG. Useful when targeting "
                    "real-time firmware like FreeRTOS, VxWorks, or custom safety "
                    "code running on R5."
                ),
                expected_state="dev",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_DAP_CFG",
        field="SSSS_RPU_NIDEN",
        description="Enables RPU non-invasive trace.",
        values={
            0: _v(
                label="RPU trace gated",
                meaning="R5 cluster trace not visible via JTAG.",
                expected_state="hardened-production",
            ),
            1: _v(
                label="RPU trace enabled",
                meaning="R5 ETM trace visible to JTAG observer.",
                expected_state="dev",
            ),
        },
    ),

    # =========================================================================
    # CSU.JTAG_SEC  — Secure Stream Switch path gates (3-bit magic fields)
    # =========================================================================

    Annotation(
        register="CSU.JTAG_SEC",
        field="SSSS_DAP_SEC",
        description=(
            "Gates the CSU Secure Stream Switch path from JTAG to the ARM DAP. "
            "A 3-bit magic field — requires the value 0b111 (decimal 7) to "
            "unlock. Anti-glitch defense: single-bit fault injection cannot "
            "open the gate."
        ),
        values={
            7: _v(
                label="DAP path UNLOCKED",
                meaning=(
                    "Full debug-access-port primitives reachable. All ARM "
                    "DAP-side functionality (APU/RPU debug per JTAG_DAP_CFG, "
                    "MEM-AP reads, CoreSight access) gated through this path."
                ),
                expected_state="factory-dev",
            ),
            0: _v(
                label="DAP path gated",
                meaning=(
                    "All-zero — secure stream switch refuses traffic. JTAG cannot "
                    "reach the DAP. Production hardening end state."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_SEC",
        field="SSSS_PLTAP_SEC",
        description=(
            "Gates the CSU SSS path to the PL JTAG TAP (FPGA fabric debug "
            "TAP). Same anti-glitch 3-bit-magic-value scheme."
        ),
        values={
            7: _v(
                label="PL TAP path UNLOCKED",
                meaning=(
                    "PL JTAG fully reachable. Can read FPGA configuration "
                    "memory, extract bitstreams, load custom bitstreams. On a "
                    "hardened device with PL programmed, this would expose IP."
                ),
                expected_state="factory-dev",
            ),
            0: _v(
                label="PL TAP path gated",
                meaning="FPGA-side JTAG attacks blocked at the SSS.",
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="CSU.JTAG_SEC",
        field="SSSS_PMU_SEC",
        description=(
            "Gates the CSU SSS path to the PMU (Platform Management Unit) "
            "firmware execution control."
        ),
        values={
            7: _v(
                label="PMU path UNLOCKED",
                meaning=(
                    "Direct JTAG access to PMU execution — could halt/inspect "
                    "PMU firmware. Note: PMU LMB memory reads via AXI work "
                    "without this, but live execution control requires it."
                ),
                expected_state="factory-dev",
            ),
            0: _v(
                label="PMU path gated",
                meaning=(
                    "Cannot directly control PMU execution from JTAG. Default "
                    "ZCU102 state — PMU still readable via AXI mem-AP, just not "
                    "directly controllable."
                ),
                expected_state="dev | hardened-production",
            ),
        },
    ),

    # =========================================================================
    # EFUSE.SEC_CTRL  — secure-boot policy fuses (one-way)
    # =========================================================================

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="AES_RDLK",
        description=(
            "One-way fuse: when set, the AES decryption key in eFUSE shadow "
            "cannot be read. Single-bit field; safe to interpret directly."
        ),
        values={
            0: _v(
                label="AES key readable",
                meaning=(
                    "The AES key stored in eFUSE shadow can be read from JTAG "
                    "(if other gates allow). If the device uses encrypted boot, "
                    "this is a key-extraction primitive."
                ),
                expected_state="dev | partial-hardening",
            ),
            1: _v(
                label="AES key locked from read",
                meaning=(
                    "Permanent one-way fuse blown. AES key cannot be extracted "
                    "from eFUSE shadow even with JTAG. Production hardening."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="AES_WRLK",
        description="One-way fuse: when set, AES key in eFUSE cannot be written.",
        values={
            0: _v(
                label="AES key writable",
                meaning="AES key location is still mutable. Dev configuration.",
                expected_state="dev",
            ),
            1: _v(
                label="AES key write-locked",
                meaning="AES key cannot be rewritten after this fuse is blown.",
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="ENC_ONLY",
        description="Forces BootROM to only accept encrypted boot images.",
        values={
            0: _v(
                label="Unencrypted boot allowed",
                meaning="BootROM accepts plain boot images. Dev convenience.",
                expected_state="dev",
            ),
            1: _v(
                label="Encrypted-only boot enforced",
                meaning=(
                    "BootROM rejects unencrypted images. Combined with RSA_EN, "
                    "this is the secure-boot enforcement chain. Production target."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="RSA_EN",
        description=(
            "RSA boot authentication enable — a 15-bit eFuse field (bits 25:11, mask 0x03FFF800; "
            "xilskey RSA_EN_SHIFT=11/WIDTH=15). Multi-bit for redundancy: the BootROM treats RSA "
            "authentication as ENFORCED once the field is programmed (non-zero), requiring every "
            "boot image to be signed."
        ),
        values={
            0: _v(
                label="RSA auth NOT enforced",
                meaning="Unsigned boot images accepted (field unprogrammed). Dev default.",
                expected_state="dev",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="BBRAM_DIS",
        description="Disables BBRAM as a key source.",
        values={
            0: _v(
                label="BBRAM enabled",
                meaning=(
                    "BBRAM is available for AES key storage. If used, the key is "
                    "in battery-backed RAM (lost when battery dies)."
                ),
                expected_state="dev",
            ),
            1: _v(
                label="BBRAM disabled",
                meaning=(
                    "AES key must come from eFUSE only. Removes the BBRAM attack "
                    "vector (key extraction via JTAG read of BBRAM region)."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="JTAG_DIS",
        description=(
            "One-way hardware JTAG disable. Once this fuse is blown, JTAG is "
            "permanently inoperable on this chip. No recovery possible."
        ),
        values={
            0: _v(
                label="JTAG enabled",
                meaning=(
                    "Hardware JTAG access available — research workflow proceeds. "
                    "Combined with absence of SSS gates, all JTAG primitives "
                    "reachable."
                ),
                expected_state="dev | partial-hardening",
            ),
            1: _v(
                label="JTAG hardware-disabled",
                meaning=(
                    "eFUSE blown to permanently disable JTAG. Observing this from "
                    "a live JTAG session is paradoxical — if the fuse was blown "
                    "before power-on, this register would be unreachable. Possible "
                    "interpretations: (1) fuse was blown DURING this session "
                    "(unlikely), (2) physical override jumper present, (3) silicon "
                    "bug or eFUSE shadow misread. Investigate."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="DFT_DIS",
        description="Disables Design-for-Test JTAG access.",
        values={
            0: _v(
                label="DFT JTAG accessible",
                meaning="Manufacturing test JTAG paths still available.",
                expected_state="dev",
            ),
            1: _v(
                label="DFT JTAG disabled",
                meaning="Manufacturing test JTAG closed. Production hardening.",
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="EFUSE.SEC_CTRL",
        field="SEC_LOCK",
        description=(
            "Master lock on the SEC_CTRL register itself. Once set, no further "
            "SEC_CTRL fuses can be blown. The final-state hardening fuse."
        ),
        values={
            0: _v(
                label="SEC_CTRL mutable",
                meaning=(
                    "Additional fuses (RSA_EN, ENC_ONLY, JTAG_DIS, etc.) can still "
                    "be set. Production manufacturing flow blows the policy fuses "
                    "first, then sets SEC_LOCK as the final step."
                ),
                expected_state="dev | partial-hardening",
            ),
            1: _v(
                label="SEC_CTRL locked",
                meaning=(
                    "No further changes to the policy. Indicates a device has "
                    "completed the production-hardening flow. To bypass the "
                    "established policy, an attacker needs either physical-hardware "
                    "attacks (decap, glitch) or a flaw in the locked policy itself."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    # =========================================================================
    # XPPU.CTRL  — peripheral protection master enable + parity
    # =========================================================================

    Annotation(
        register="XPPU.CTRL",
        field="ENABLE",
        description=(
            "Master enable for XPPU enforcement. When 0, the XPPU passes all "
            "AXI transactions without checking permissions — no master/"
            "peripheral isolation. When 1, every master access is validated "
            "against the permission tables."
        ),
        values={
            0: _v(
                label="XPPU enforcement DISABLED",
                meaning=(
                    "Every AXI master can access every peripheral in the LPD "
                    "aperture region. No hardware-level isolation. Expected on "
                    "dev kits in JTAG-idle (PMU firmware enables XPPU during "
                    "boot). A finding on a booted production device — means PMU "
                    "firmware did NOT activate peripheral protection."
                ),
                expected_state="dev-idle | misconfigured-production",
            ),
            1: _v(
                label="XPPU enforcement ACTIVE",
                meaning=(
                    "Master→peripheral access checks are happening. Per-aperture "
                    "permission tables determine actual gating. Need to "
                    "cross-reference the aperture permission entries (RAM tables) "
                    "to know which master can reach which peripheral."
                ),
                expected_state="booted-properly-configured",
            ),
        },
    ),

    Annotation(
        register="XPPU.CTRL",
        field="MID_PARITY_EN",
        description="Hardware parity checking on master ID table entries.",
        values={
            0: _v(
                label="MID parity disabled",
                meaning="No parity check on master ID lookups — bit flips undetected.",
                expected_state="dev",
            ),
            1: _v(
                label="MID parity enabled",
                meaning=(
                    "Master ID table entries protected by parity. Transient bit "
                    "flips (from fault injection or radiation) detectable. "
                    "Hardening signal."
                ),
                expected_state="hardened-production",
            ),
        },
    ),

    Annotation(
        register="XPPU.CTRL",
        field="APER_PARITY_EN",
        description="Hardware parity checking on aperture permission table entries.",
        values={
            0: _v(
                label="Aperture parity disabled",
                meaning="No parity check on aperture entries.",
                expected_state="dev",
            ),
            1: _v(
                label="Aperture parity enabled",
                meaning="Aperture entries protected by parity. Hardening signal.",
                expected_state="hardened-production",
            ),
        },
    ),

    # =========================================================================
    # XPPU.ISR  — protection violation latches
    # =========================================================================

    Annotation(
        register="XPPU.ISR",
        field="INV_APB",
        description="Latches when an APB-side access was rejected by XPPU.",
        values={
            0: _v(label="No invalid-APB violation latched",
                  meaning="No APB-side rejection has occurred since last ISR clear."),
            1: _v(
                label="Invalid APB transaction latched",
                meaning=(
                    "An APB-side access was rejected by XPPU. Cross-reference "
                    "ERR_STATUS1/2 for offender."
                ),
            ),
        },
    ),

    Annotation(
        register="XPPU.ISR",
        field="MID_MISS",
        description="Latches when an AXI master ID isn't found in the configured table.",
        values={
            0: _v(label="No master-ID-miss violation latched",
                  meaning="No unrecognized AXI master has hit XPPU since last ISR clear."),
            1: _v(
                label="Master ID lookup miss latched",
                meaning=(
                    "An AXI master sent a transaction with a Master ID that "
                    "doesn't match any configured slot in the master ID table. "
                    "Significant security signal — either an unknown master is on "
                    "the bus or the table is incomplete."
                ),
            ),
        },
    ),

    Annotation(
        register="XPPU.ISR",
        field="APER_PERM",
        description="Latches when a known master attempted an aperture it's not permitted to reach.",
        values={
            0: _v(label="No aperture-permission violation latched",
                  meaning="No master has been blocked from a forbidden aperture since last ISR clear."),
            1: _v(
                label="Aperture permission violation latched",
                meaning=(
                    "A known master attempted to access an aperture it's not "
                    "permitted to reach. Indicates either: (a) attempted privilege "
                    "escalation, (b) misconfigured permission table, or (c) "
                    "software bug."
                ),
            ),
        },
    ),

    Annotation(
        register="XPPU.ISR",
        field="APER_TZ",
        description="Latches when a non-secure master attempted a TZ-secured aperture.",
        values={
            0: _v(label="No TrustZone-aperture violation latched",
                  meaning="No non-secure master has been blocked from a TZ-secured aperture since last ISR clear."),
            1: _v(
                label="Aperture TrustZone violation latched",
                meaning=(
                    "A non-secure master attempted to access a TZ-secured "
                    "aperture. Critical security signal."
                ),
            ),
        },
    ),

    # The three XPPU.ISR fields below are referenced by rule_xppu_violations_latched
    # in docs/findings/zynqmp_rules.py — must stay in sync if QEMU adds/removes them.
    Annotation(
        register="XPPU.ISR", field="MID_RO",
        description="Latches when a master attempted a write while flagged read-only in its MASTER_ID slot.",
        values={
            0: _v(label="No read-only violation latched",
                  meaning="No RO-flagged master has been blocked from writing since last ISR clear."),
            1: _v(label="Master-RO write violation LATCHED",
                  meaning="A master with the RO bit set in its MASTER_ID slot attempted to "
                          "write through XPPU. Indicates a master misbehaving against its "
                          "declared role, OR an attacker probe."),
        },
    ),
    Annotation(
        register="XPPU.ISR", field="MID_PARITY",
        description="Latches when an XPPU MASTER_ID slot read back with bad parity.",
        values={
            0: _v(label="No master-ID parity error latched",
                  meaning="No XPPU MASTER_ID-table parity error since last ISR clear."),
            1: _v(label="Master-ID parity ERROR latched",
                  meaning="Parity mismatch reading an XPPU MASTER_ID slot. Indicates either a "
                          "bit flip in the protection table (SEU / fault injection) or table "
                          "corruption. Reliability + tamper signal."),
        },
    ),
    Annotation(
        register="XPPU.ISR", field="APER_PARITY",
        description="Latches when an XPPU aperture permission entry read back with bad parity.",
        values={
            0: _v(label="No aperture parity error latched",
                  meaning="No XPPU aperture-table parity error since last ISR clear."),
            1: _v(label="Aperture parity ERROR latched",
                  meaning="Parity mismatch reading an aperture permission entry. Indicates a "
                          "bit flip in the protection table or table corruption. "
                          "Reliability + tamper signal."),
        },
    ),

    # =========================================================================
    # XMPU — memory-range protection (mirror of XPPU for memory rather than
    # peripheral apertures). 8 instances on ZynqMP: 5 DDR + FPD + OCM + others.
    # Wildcard register entries match the same field name across every XMPU
    # instance (the layout is identical per QEMU's xlnx-xmpu.h).
    # =========================================================================

    # ---- CTRL — global enable / default-deny settings ----
    Annotation(
        register="*",
        field="DEFRDALLOWED",
        description=(
            "Default read-allow when no region descriptor matches. Set means "
            "reads to unmatched ranges succeed; clear means deny-by-default."
        ),
        values={
            0: _v(label="Default DENY reads",
                  meaning="Reads to memory addresses not covered by any region descriptor "
                          "are denied (return poisoned data or AXI error). Hardened state."),
            1: _v(label="Default ALLOW reads",
                  meaning="Reads to unmatched addresses succeed. Permissive default; XMPU "
                          "only enforces deny on regions explicitly marked. Common dev "
                          "default; finding on a hardened production device."),
        },
    ),
    Annotation(
        register="*",
        field="DEFWRALLOWED",
        description=(
            "Default write-allow when no region descriptor matches. Set means "
            "writes to unmatched ranges succeed; clear means deny-by-default."
        ),
        values={
            0: _v(label="Default DENY writes",
                  meaning="Writes to unmatched addresses are silently dropped or AXI-error. "
                          "Hardened state."),
            1: _v(label="Default ALLOW writes",
                  meaning="Writes to unmatched addresses succeed. Permissive default. "
                          "Combined with DEFRDALLOWED=1, XMPU is effectively pass-through "
                          "unless specific deny regions are configured."),
        },
    ),
    Annotation(
        register="*",
        field="HIDEALLOWED",
        description="Whether denied accesses are silently dropped (hidden) or surface as AXI errors.",
        values={
            0: _v(label="Denied accesses raise AXI error",
                  meaning="Master attempting a forbidden access gets SLVERR/DECERR back. "
                          "Software can detect the violation via fault handlers."),
            1: _v(label="Denied accesses silently dropped",
                  meaning="Denied reads return poisoned data; denied writes silently "
                          "complete. No SLVERR generated. Harder to detect — bug-hiding "
                          "behavior. Usually a finding on a debug-friendly system."),
        },
    ),
    Annotation(
        register="*",
        field="ALIGNCFG",
        description="Region alignment enforcement mode (UG1085 Table 16-5: 1=1MB, 0=4KB).",
        values={
            0: _v(label="4 KB alignment",
                  meaning="Region START/END can be 4 KB-aligned. Finer granularity; "
                          "needed to protect page-sized ranges (e.g. secure-world stack)."),
            1: _v(label="1 MB alignment",
                  meaning="Region START/END addresses must be 1 MB-aligned. Coarser "
                          "granularity; covers more memory per region descriptor."),
        },
    ),

    # ---- ISR — latched protection violations ----
    Annotation(
        register="*",
        field="SECURITYVIO",
        description="Latches when a master with mismatched security-state attempted access.",
        values={
            0: _v(label="No XMPU security violation latched",
                  meaning="No master has attempted a security-tier-mismatched access since "
                          "last ISR clear."),
            1: _v(label="XMPU security violation LATCHED",
                  meaning="A non-secure master attempted to access a TZ-secured region (or "
                          "vice versa). Critical security signal — cross-reference "
                          "ERR_STATUS1/2 for the offending AXI ID and address."),
        },
    ),
    Annotation(
        register="*",
        field="WRPERMVIO",
        description="Latches when a write was denied by XMPU.",
        values={
            0: _v(label="No write-permission violation latched",
                  meaning="No master has been denied a write since last ISR clear."),
            1: _v(label="Write violation LATCHED",
                  meaning="A master attempted to write to a region they don't have "
                          "WRALLOWED for. Either an attacker probe or a misconfigured "
                          "master."),
        },
    ),
    Annotation(
        register="*",
        field="RDPERMVIO",
        description="Latches when a read was denied by XMPU.",
        values={
            0: _v(label="No read-permission violation latched",
                  meaning="No master has been denied a read since last ISR clear."),
            1: _v(label="Read violation LATCHED",
                  meaning="A master attempted to read from a region they don't have "
                          "RDALLOWED for. Possible memory enumeration attempt."),
        },
    ),

    # INV_APB — already annotated via XPPU.ISR.INV_APB (different register but
    # same field name + semantically equivalent). Add explicit XMPU annotation
    # to avoid the wildcard wrongly matching XPPU's semantics.

    # ---- LOCK — write-lock for the entire XMPU instance ----
    Annotation(
        register="*",
        field="REGWRDIS",
        description=(
            "XMPU register write-disable. Once set, no further writes to ANY "
            "XMPU register (including region descriptors) are accepted. One-way "
            "during a power cycle — only POR clears it. Production hardening "
            "end-state."
        ),
        values={
            0: _v(label="XMPU writable",
                  meaning="XMPU configuration can still be modified. Dev/bring-up state. "
                          "On a production device this means whoever owns the PMU/APU can "
                          "reconfigure memory protection at runtime."),
            1: _v(label="XMPU WRITE-LOCKED",
                  meaning="XMPU configuration is frozen until next POR. Production-grade "
                          "hardening — even a fully-compromised PMU can't relax memory "
                          "protection without a power cycle."),
        },
    ),

    # =========================================================================
    # PCAP / PL configuration status — CSU.PCAP_STATUS at 0xFFCA3010.
    # Tells us whether the FPGA fabric is configured and what configuration
    # housekeeping signals are active.
    # =========================================================================

    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_DONE",
        description="PL configuration done — set when bitstream load + EOS completed successfully.",
        values={
            0: _v(label="PL NOT configured",
                  meaning="No bitstream has been loaded into the PL, OR a load was attempted "
                          "and didn't complete. The fabric is unprogrammed — any PL-side "
                          "peripherals/IP do not exist. Common state in JTAG-idle on dev kits."),
            1: _v(label="PL configured",
                  meaning="A bitstream has been loaded and reached end-of-startup. The fabric "
                          "is active. Any PL-side IP (custom logic, soft processors, signal "
                          "processing) is now reachable from the PS via AXI bridges."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_INIT",
        description="PL is in initialization phase (active during bitstream load).",
        values={
            0: _v(label="PL not initializing",
                  meaning="The PL is either fully configured (PL_DONE=1), held in reset "
                          "(PCAP_PROG.PCFG_PROG_B=0), or unconfigured and idle."),
            1: _v(label="PL initializing",
                  meaning="A configuration load is in progress. INIT_B is high — fabric is "
                          "ready to accept configuration data via PCAP or PL JTAG."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_EOS",
        description="End-of-Startup — PL has completed its post-config startup sequence.",
        values={
            0: _v(label="EOS not asserted",
                  meaning="Either no bitstream loaded, or one is loaded but startup not "
                          "yet complete. PL user logic may not yet have clocks released."),
            1: _v(label="EOS asserted",
                  meaning="PL has finished startup. User clocks released, I/O active, "
                          "GHIGH/GWE/GSR/GTS lifted per startup sequence."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_FST_CFG",
        description="First-configuration flag — set the first time the PL is configured after POR.",
        values={
            0: _v(label="PL not yet configured since POR",
                  meaning="No PL configuration has happened since the last POR. PL is empty."),
            1: _v(label="PL configured at least once since POR",
                  meaning="At least one PL configuration has happened. Re-loads after this "
                          "keep FST_CFG asserted."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_SEU_ERROR",
        description="Single-Event-Upset (SEU) error detected in PL configuration memory.",
        values={
            0: _v(label="No SEU error",
                  meaning="No SEU has been flagged in PL config memory."),
            1: _v(label="PL SEU ERROR latched",
                  meaning="A radiation- or fault-injection-induced bit flip has been detected "
                          "in the PL configuration bitstream. Security/reliability signal — "
                          "in space/aerospace use this would trigger a scrub; on a research "
                          "device it likely indicates active fault injection."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PL_CFG_RESET_B",
        description="Inverse of PL configuration reset (1 = not in config reset).",
        values={
            0: _v(label="PL in config reset",
                  meaning="The PL configuration is held in reset (PCAP_PROG.PCFG_PROG_B "
                          "asserted)."),
            1: _v(label="PL config reset released",
                  meaning="PL configuration is not in reset; can be loaded or is already loaded."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PCAP_RD_IDLE",
        description="PCAP read channel idle indicator.",
        values={
            0: _v(label="PCAP read busy", meaning="A PCAP read is in flight."),
            1: _v(label="PCAP read idle", meaning="PCAP read channel is idle and ready."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PCAP_WR_IDLE",
        description="PCAP write channel idle indicator.",
        values={
            0: _v(label="PCAP write busy", meaning="A PCAP write (bitstream load) is in flight."),
            1: _v(label="PCAP write idle", meaning="PCAP write channel is idle and ready."),
        },
    ),
    Annotation(
        register="CSU.PCAP_STATUS",
        field="PCFG_MCAP_MODE",
        description="MCAP (alternate config interface, PCIe-based) mode select.",
        values={
            0: _v(label="PCAP mode",
                  meaning="Standard PCAP is the active config interface."),
            1: _v(label="MCAP mode (PCIe-driven config)",
                  meaning="MCAP is the active config interface — PL configuration data "
                          "flows in via PCIe instead of CSU PCAP. Used in datacenter FPGAs."),
        },
    ),

    # ---- PCAP_PROG: PCFG_PROG_B = the PL config reset pin ----

    Annotation(
        register="CSU.PCAP_PROG",
        field="PCFG_PROG_B",
        description="PL programming reset (active-low). Driving low erases PL configuration.",
        values={
            0: _v(label="PL config RESET asserted",
                  meaning="PROG_B is driven low — the PL configuration is being erased / held "
                          "empty. PL is unconfigured while this is 0."),
            1: _v(label="PL config reset released",
                  meaning="PROG_B is high — PL is not in config reset. Can hold a configuration."),
        },
    ),

    # ---- PCAP_CTRL: PCAP master enable + housekeeping ----

    Annotation(
        register="CSU.PCAP_CTRL",
        field="PCAP_PR",
        description="PCAP partial reconfiguration enable.",
        values={
            0: _v(label="Full-config mode", meaning="PCAP loads full bitstreams (not partial)."),
            1: _v(label="Partial reconfig enabled",
                  meaning="PCAP is set up for partial reconfiguration — bitstreams target "
                          "regions of the fabric without clearing other regions. Used for "
                          "dynamic IP swap."),
        },
    ),
    Annotation(
        register="CSU.PCAP_CTRL",
        field="PCFG_GSR",
        description="Global Set/Reset signal control to PL.",
        values={
            0: _v(label="GSR inactive", meaning="GSR de-asserted — PL flops/RAMs not being reset."),
            1: _v(label="GSR asserted",
                  meaning="Global Set/Reset is being driven to PL — resets all user flops / RAMs."),
        },
    ),

    # =========================================================================
    # SLCR security state (§18) — LPD_SLCR, FPD_SLCR, IOU_SECURE_SLCR,
    # LPD_SLCR_SECURE. Hand-verified addresses from Xilinx PMU FW headers
    # plus UG1085 §36 for FPD_SLCR (see zynqmp-regs-extension.tcl).
    # =========================================================================

    # ---- SLVERR_ENABLE wildcard (covers LPD_SLCR.CTRL + FPD_SLCR.CTRL) ----
    Annotation(
        register="*",
        field="SLVERR_ENABLE",
        description="When set, illegal register accesses raise an AXI SLVERR. When clear, bad accesses silently complete (returns ignored / writes dropped).",
        values={
            0: _v(label="SLVERR responses disabled",
                  meaning="Bad register accesses silently complete. Default state. "
                          "Software bugs go undetected; harder to debug but more "
                          "forgiving during bring-up."),
            1: _v(label="SLVERR responses ENABLED",
                  meaning="Bad register accesses raise AXI SLVERR back to the master. "
                          "Software can detect via fault handlers. Production-grade "
                          "configuration; usually set after bring-up completes."),
        },
    ),

    # ---- ADDR_DECODE_ERR wildcard (covers LPD/FPD_SLCR.ISR + .IMR) ----
    Annotation(
        register="*",
        field="ADDR_DECODE_ERR",
        description="Latched address-decode error count for this SLCR block.",
        values={
            0: _v(label="No address-decode errors latched",
                  meaning="No software has attempted to access an invalid offset in "
                          "this SLCR since last ISR clear."),
            1: _v(label="Address-decode error LATCHED",
                  meaning="Software has attempted to access an invalid offset within "
                          "this SLCR. Indicates a buggy driver, attempted probe, or "
                          "stale address. Investigate by inspecting recent traffic."),
        },
    ),

    # ---- WPROT0.ACTIVE wildcard (LPD_SLCR + FPD_SLCR write protection) ----
    Annotation(
        register="*",
        field="ACTIVE",
        description="SLCR write protection. When set, register writes to this SLCR block are silently ignored.",
        values={
            0: _v(label="SLCR writes ALLOWED",
                  meaning="Software can modify this SLCR. Default state, allows "
                          "runtime reconfiguration of clocks, MIO, etc."),
            1: _v(label="SLCR WRITE-LOCKED",
                  meaning="Writes to this SLCR are silently dropped until ACTIVE is "
                          "cleared (which itself requires a write that succeeds). "
                          "Used during specific reconfiguration windows; rare in "
                          "steady-state."),
        },
    ),

    # ---- TZ_USB3_0 / TZ_USB3_1 — USB TrustZone gating ----
    Annotation(
        register="LPD_SLCR_SECURE.SLCR_USB",
        field="TZ_USB3_0",
        description="USB0 controller TrustZone state — drives the AXI security tier of USB0's DMA traffic.",
        values={
            0: _v(label="USB0 NON-SECURE",
                  meaning="USB0 controller emits AXI transactions with AxPROT[1]=1 "
                          "(non-secure). XPPU/XMPU will deny access to any secure-marked "
                          "memory or peripheral aperture. Default state on most devices."),
            1: _v(label="USB0 SECURE",
                  meaning="USB0 controller emits AXI transactions with AxPROT[1]=0 "
                          "(secure). Can reach secure memory regions. Should only be "
                          "set on devices that explicitly need USB0 to act as a secure "
                          "master (rare)."),
        },
    ),
    Annotation(
        register="LPD_SLCR_SECURE.SLCR_USB",
        field="TZ_USB3_1",
        description="USB1 controller TrustZone state — same semantics as TZ_USB3_0 but for USB1.",
        values={
            0: _v(label="USB1 NON-SECURE",
                  meaning="USB1 controller emits non-secure AXI traffic. Default."),
            1: _v(label="USB1 SECURE",
                  meaning="USB1 controller emits secure AXI traffic. Rare; only when "
                          "USB1 is provisioned as a secure master."),
        },
    ),
]


# ---------------------------------------------------------------------------
# REGISTER_ANNOTATIONS — register-level meaning for fieldless registers.
#
# Used when the whole 32-bit word is the value (boot offsets, base
# addresses, counts) and there are no sub-fields to decode. interpret.py
# shows the `description` under the register's heading and, if `interpret`
# is provided, calls it with the raw integer to produce a derived line.
# ---------------------------------------------------------------------------

def _aes_status_decode(v: int) -> str:
    """CSU AES_STATUS — decode the well-established key-presence bits.
    bit4 KEY_INIT_DONE; bit8 AES_KEY_ZERO (device key slot all-zero);
    bit9 KUP_ZEROED; bit10 BOOT_KEY_ZERO; bit11 OKR_ZERO. Baseline on an
    unprovisioned part is 0x00000F00 (all four *_ZERO set)."""
    init = ("KEY_INIT_DONE set (a key-load completed)" if v & (1 << 4)
            else "KEY_INIT_DONE clear (no key-load completed)")
    zero = {8: "device key", 9: "KUP key", 10: "boot key", 11: "operational(OKR) key"}
    z = [lbl for b, lbl in zero.items() if v & (1 << b)]
    if len(z) == 4:
        slots = "ALL key slots read all-zero (unprovisioned — dev baseline)"
    elif z:
        slots = ("zeroed (empty) slots: " + ", ".join(z)
                 + "; the remaining slot(s) hold a NON-ZERO key — provisioned")
    else:
        slots = "NO slot reads zero — a real key is loaded in every slot"
    return f"raw 0x{v:08X}; {init}; {slots}."


def _tamper_resp_decode(v: int, n: int) -> str:
    """CSU_TAMPER_<n> per-source tamper response config. Non-zero ⇒ armed.
    Exact response-bit encoding is per UG1085 (system interrupt / secure
    lockdown / BBRAM+key zeroize / system reset) — not asserted bit-by-bit."""
    if v == 0:
        return f"Tamper source {n}: no response armed (disabled on this part)."
    return (f"Tamper source {n}: response config 0x{v:08X} ARMED — selects one or "
            f"more tamper responses (system interrupt / secure lockdown / "
            f"BBRAM+key zeroize / system reset; see UG1085 tamper response).")


REGISTER_ANNOTATIONS = [
    RegisterAnnotation(
        register="CSU.CSU_MULTI_BOOT",
        description=(
            "Boot image search offset. The CSU BootROM looks for the next "
            "boot image at (32 KB * MULTI_BOOT) from the start of the boot "
            "device. Used to chain-load alternate images (golden vs upgrade) "
            "and to recover from a failed primary image."
        ),
        interpret=lambda v: (
            f"Search offset = {v} * 32 KB = 0x{v * 0x8000:X} bytes from start of boot device. "
            + ("(Value 0 = primary image at base address.)" if v == 0
               else f"Skipping past {v * 32} KB to look for next boot header.")
        ),
    ),
    RegisterAnnotation(
        register="XPPU.ERR_STATUS1",
        description=(
            "Latched address of the most recent XPPU violation. Holds the "
            "AXI address that triggered an MID_MISS, MID_RO, MID_PARITY, "
            "or APER_PERM error. Cleared by writing the ISR bit."
        ),
        interpret=lambda v: (
            "No violation latched." if v == 0
            else f"Last violation at AXI address 0x{v:08X}."
        ),
    ),
    RegisterAnnotation(
        register="XPPU.M_MASTER_IDS",
        description=(
            "Number of master-ID slots implemented in this XPPU instance. "
            "The LPD XPPU has 20 slots, each at MASTER_ID_NN (0xFF980100 "
            "stride 4)."
        ),
        interpret=lambda v: f"{v} master-ID slots available for AXI master classification.",
    ),
    RegisterAnnotation(
        register="XPPU.M_APERTURE_64KB",
        description=(
            "Number of 64KB apertures implemented. The LPD XPPU has 256 "
            "such apertures starting at BASE_64KB."
        ),
        interpret=lambda v: f"{v} apertures of 64 KB each (total = {v * 64} KB = 0x{v * 0x10000:X} bytes).",
    ),
    RegisterAnnotation(
        register="XPPU.M_APERTURE_1MB",
        description=(
            "Number of 1MB apertures implemented. Covers the 1MB-stride "
            "address range starting at BASE_1MB."
        ),
        interpret=lambda v: f"{v} apertures of 1 MB each (total = {v} MB).",
    ),
    RegisterAnnotation(
        register="XPPU.M_APERTURE_512MB",
        description=(
            "Number of 512MB apertures implemented. Typically 1 — covers the "
            "PL / DDR / PCIe upper aperture starting at BASE_512MB."
        ),
        interpret=lambda v: f"{v} apertures of 512 MB each.",
    ),
    RegisterAnnotation(
        register="XPPU.BASE_64KB",
        description="Base AXI address of the 64KB-aperture peripheral region.",
        interpret=lambda v: f"64KB apertures start at AXI 0x{v:08X}.",
    ),
    RegisterAnnotation(
        register="XPPU.BASE_1MB",
        description="Base AXI address of the 1MB-aperture region.",
        interpret=lambda v: f"1MB apertures start at AXI 0x{v:08X}.",
    ),
    RegisterAnnotation(
        register="XPPU.BASE_512MB",
        description="Base AXI address of the 512MB-aperture region.",
        interpret=lambda v: f"512MB apertures start at AXI 0x{v:08X}.",
    ),

    # =====================================================================
    # Security-posture reads added 2026-06-08 (enumerate.tcl Section 4).
    # These QEMU registers carry no field-defs, so bit meaning is decoded
    # here from UG1085. Bit-level claims are made only where the layout is
    # well-established (AES_STATUS key-zero bits, WR_LOCK); registers whose
    # exact bit encoding isn't pinned down report the raw value + an honest
    # register-level meaning rather than inventing bit names.
    # =====================================================================
    RegisterAnnotation(
        register="CSU.AES_STATUS",
        description=(
            "CSU AES engine status. Per-slot *_ZERO bits report whether each "
            "AES key slot holds all-zeros (unprovisioned) vs a real key — a "
            "strong key-provisioning tell that flips on a board with a "
            "device/boot/KUP key loaded."
        ),
        interpret=_aes_status_decode,
    ),
    RegisterAnnotation(
        register="EFUSE.WR_LOCK",
        description="eFuse array write/program lock (bit0).",
        interpret=lambda v: (
            "eFuse array WRITE-LOCKED (bit0=1): programming disabled until next "
            "POR — normal runtime state." if v & 1
            else "eFuse array write-unlocked (bit0=0): programming possible."),
    ),
    RegisterAnnotation(
        register="EFUSE.EFUSE_AES_CRC",
        description=(
            "eFuse AES-key CRC *check* register (xilskey AES_CRC offset 0x48, RSTVAL 0). "
            "Software WRITES the expected CRC here to trigger a hardware verify against the "
            "burned key, then polls EFUSE_STATUS AES_CRC_DONE/PASS. It is write-to-verify — "
            "NOT a read-back of the key or its CRC (xilskey_eps_zynqmp.c:1785)."
        ),
        interpret=lambda v: (
            "0 — reset/idle. This register reads 0 whether or not an eFuse AES key is "
            "programmed (the key is secret; nothing mirrors it), so a read here CANNOT "
            "determine key presence." if v == 0
            else f"0x{v:08X} — a CRC value is latched (software mid-verify); still not a "
                 "reliable key-presence indicator."),
    ),
    RegisterAnnotation(
        register="EFUSE.EFUSE_ISR",
        description="eFuse controller interrupt/status flags.",
        interpret=lambda v: (
            "No eFuse controller interrupt/status flags set." if v == 0
            else f"eFuse ISR flags 0x{v:08X} set (programming-done / error "
                 "flags — see UG1085 eFuse ISR)."),
    ),
    RegisterAnnotation(
        register="EFUSE.EFUSE_PGM_LOCK",
        description="eFuse programming lock (SPK_ID / revocation rows).",
        interpret=lambda v: (
            "eFuse programming lock not engaged (0)." if v == 0
            else f"eFuse programming lock engaged (0x{v:08X}) — SPK_ID / "
                 "revocation row programming is locked."),
    ),
    RegisterAnnotation(
        register="CSU.CSU_STATUS",
        description="CSU operational status (boot/auth/decrypt state machine).",
        interpret=lambda v: f"raw 0x{v:08X} (CSU state flags — see UG1085 CSU_STATUS).",
    ),
    RegisterAnnotation(
        register="CSU.CSU_CTRL",
        description="CSU control register (SLVERR enable + CSU-internal control).",
        interpret=lambda v: f"raw 0x{v:08X}.",
    ),
    RegisterAnnotation(
        register="CSU.CSU_SSS_CFG",
        description=(
            "Secure Stream Switch configuration: four 4-bit routing nibbles wire "
            "the secure sinks (PCAP/DMA/AES/SHA) to sources. Part of the "
            "secure-boot dataflow; 0 = a sink is not routed."
        ),
        interpret=lambda v: (
            f"raw 0x{v:08X}; routing nibbles "
            f"[0]=0x{v & 0xF:X} [1]=0x{(v >> 4) & 0xF:X} "
            f"[2]=0x{(v >> 8) & 0xF:X} [3]=0x{(v >> 12) & 0xF:X}."),
    ),
    RegisterAnnotation(
        register="CSU.CSU_FT_STATUS",
        description="CSU fault-tolerance (triple-modular-redundancy / SEU) status.",
        interpret=lambda v: (
            "No CSU FT/SEU faults reported." if v == 0
            else f"CSU FT/SEU fault status 0x{v:08X}."),
    ),
    RegisterAnnotation(
        register="CSU.CSU_TAMPER_TRIG",
        description="Software-initiated tamper trigger.",
        interpret=lambda v: (
            "No software-initiated tamper trigger active." if v == 0
            else f"Software tamper trigger ACTIVE (0x{v:08X})."),
    ),
    RegisterAnnotation(
        register="CSU.TAMPER_STATUS",
        description="Latched tamper-event status across all tamper sources.",
        interpret=lambda v: (
            "No tamper events latched." if v == 0
            else f"Tamper event(s) LATCHED: 0x{v:08X} — one or more sources "
                 "fired since last clear."),
    ),
]

# 13 per-source tamper response-config registers (CSU_TAMPER_0..12). Generated
# rather than hand-listed; default-bind _n so each lambda captures its index.
for _n in range(13):
    REGISTER_ANNOTATIONS.append(RegisterAnnotation(
        register=f"CSU.CSU_TAMPER_{_n}",
        description=f"Tamper source {_n} response configuration (0 = disarmed).",
        interpret=(lambda v, _i=_n: _tamper_resp_decode(v, _i)),
    ))
