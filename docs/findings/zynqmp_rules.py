"""
zynqmp_rules.py — declarative cross-register findings rules.

Each rule is a function that takes a `Capture` and returns a `Finding`
when its conditions match, or None otherwise. Rules are collected in
ALL_RULES at the bottom of this module.

Helpers (`_factory_dev_state`, `_secure_world_accessible`, etc.) live
above the rules so that cross-cutting predicates can be shared.

Conventions:
  - Rule function names start with `rule_`
  - Helper function names start with `_`
  - Each rule has a docstring explaining the condition (used as
    description if Finding.description not explicitly set)
  - Severities: CRITICAL > MAJOR > INFO
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow importing interpret_lib from sibling tools/ directory
_THIS = Path(__file__).resolve()
sys.path.insert(0, str(_THIS.parent.parent.parent / "tools"))

from interpret_lib import Capture, Finding  # noqa: E402


# =============================================================================
# Cross-cutting helpers shared by multiple rules
# =============================================================================

def _is_factory_dev_state(c: Capture) -> bool:
    """True when no hardening fuses have been blown."""
    return (c.field("EFUSE.SEC_CTRL.SEC_LOCK") == 0 and
            c.field("EFUSE.SEC_CTRL.JTAG_DIS") == 0)


def _secure_debug_open(c: Capture) -> bool:
    """True when SPIDEN or SPNIDEN is set (any secure-world JTAG access)."""
    return (c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN") == 1 or
            c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPNIDEN") == 1)


def _any_xppu_violation(c: Capture) -> list[str]:
    """Return list of XPPU ISR violation field names that are set."""
    triggered = []
    for fname in ("INV_APB", "MID_MISS", "MID_RO", "MID_PARITY",
                  "APER_PERM", "APER_TZ", "APER_PARITY"):
        if c.field(f"XPPU.ISR.{fname}") == 1:
            triggered.append(fname)
    return triggered


# =============================================================================
# Rules — each returns Finding when conditions match, else None
# =============================================================================

def rule_max_debug_exposure(c: Capture) -> Finding | None:
    """Every security gate the silicon provides is open."""
    if (c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN") == 1 and
            c.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN") == 1 and
            _is_factory_dev_state(c)):
        return Finding(
            name="Maximum debug exposure (factory dev-kit baseline)",
            severity="INFO",
            description=(
                "Every security gate the silicon provides is open. Both "
                "non-secure AND secure-world debug allowed. eFUSE policy "
                "untouched."
            ),
            conclusion=(
                "Device is in factory / dev-kit state. No security hardening "
                "has been applied at the eFUSE level. Every JTAG attack "
                "primitive is available: secure-world debug, TrustZone memory "
                "read, boot image substitution (no RSA enforcement), AES key "
                "extraction (if a key is loaded into BBRAM or eFUSE), PL "
                "bitstream read/write. This is expected on a research dev kit "
                "but would be a finding on a fielded production device. Use as "
                "the diff baseline against any hardened device you can acquire."
            ),
            offensive_implications=[
                "Halt A53 in EL3 → read every secret the secure world holds",
                "Inject code at EL3 → install TrustZone rootkit",
                "Substitute boot image (no RSA enforcement) → load attacker firmware",
                "Read AES key from eFUSE shadow if loaded (AES_RDLK=0)",
                "Extract running firmware from DDR / OCM for offline analysis",
                "Modify PL bitstream via PL JTAG path (if PLTAP_SEC unlocked)",
            ],
        )
    return None


def rule_spiden_critical(c: Capture) -> Finding | None:
    """SPIDEN set on its own is a CRITICAL finding on any production device."""
    if c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN") == 1:
        return Finding(
            name="Secure-world TrustZone debug enabled",
            severity="CRITICAL",
            description=(
                "SPIDEN bit is set — JTAG can halt and inspect the EL3 monitor "
                "/ TrustZone secure world."
            ),
            conclusion=(
                "Secure-world debug is the single most consequential JTAG "
                "security signal on ZynqMP. With SPIDEN=1, an attacker with "
                "physical JTAG access can halt the A53 in EL3 (highest ARMv8 "
                "privilege), inspect every secure-protected register and memory "
                "region, and modify the EL3 monitor in place. Expected on dev "
                "kits (ZCU102 in JTAG-idle confirms 1). On a fielded production "
                "device this means TrustZone provides no protection against a "
                "JTAG-attached adversary — equivalent to having no secure world."
            ),
            offensive_implications=[
                "Direct read of AES decryption keys from secure-world memory",
                "Direct read of attestation/identity material protected by TrustZone OS",
                "Halt and modify the EL3 monitor — TrustZone rootkit primitive",
                "Snapshot every secure-world memory region for offline reverse engineering",
                "No fault-injection equipment required",
            ],
        )
    return None


def rule_encrypted_boot_not_enforced(c: Capture) -> Finding | None:
    """ENC_ONLY fuse is clear — BootROM will accept unencrypted boot images."""
    if c.field("EFUSE.SEC_CTRL.ENC_ONLY") == 0:
        return Finding(
            name="Encrypted boot not enforced",
            severity="INFO",
            description="ENC_ONLY fuse is clear.",
            conclusion=(
                "The BootROM accepts plaintext boot images. On a dev device this "
                "is expected. On a production device that's supposed to enforce "
                "confidentiality of its firmware, this is a misconfiguration — "
                "an attacker who replaces the boot media with their own "
                "(unsigned, unencrypted) image will see it boot."
            ),
            offensive_implications=[
                "Boot image substitution feasible (with no RSA enforcement)",
                "Attacker firmware can replace FSBL/ATF/U-Boot/kernel via SD/QSPI rewrite",
            ],
        )
    return None


def rule_cve_2019_5478_encrypt_only_bypass(c: Capture) -> Finding | None:
    """Encrypt-Only secure boot enabled WITHOUT Hardware Root of Trust (RSA).

    CVE-2019-5478 (F-Secure/Inverse Path, advisory FSC-HWSEC-VR2019-0001):
    in 'Encrypt-Only' boot mode the ZU+ BootROM does not authenticate the
    boot-header fields (incl. the FSBL execution address), and the FSBL does
    not authenticate partition-header destination addresses. An attacker who
    can rewrite the boot device can redirect execution -> arbitrary code
    execution, fully defeating secure boot (confidentiality without integrity).

    Trigger condition: ENC_ONLY=1 (encrypted boot enforced) AND RSA_EN=0
    (no RSA authentication, i.e. not HWRoT). Both fuses must be captured and
    definite — if either read is missing the rule stays silent rather than guess.

    The BootROM flaw is unpatchable (mask ROM); the only remediation is to use
    Hardware Root of Trust mode (RSA_EN), which authenticates boot + partition
    headers. See docs/15-prior-research.md §1 and docs/11 (ENC_ONLY / RSA_EN).
    """
    enc = c.field("EFUSE.SEC_CTRL.ENC_ONLY")
    rsa = c.field("EFUSE.SEC_CTRL.RSA_EN")
    if enc == 1 and rsa == 0:
        return Finding(
            name="Encrypt-Only secure boot without HWRoT — exposed to CVE-2019-5478",
            severity="CRITICAL",
            description=(
                "ENC_ONLY=1 with RSA_EN=0: the device enforces encrypted boot "
                "but does NOT authenticate boot/partition headers (no Hardware "
                "Root of Trust). This is the exact configuration vulnerable to "
                "CVE-2019-5478."
            ),
            conclusion=(
                "The board boots in 'Encrypt-Only' mode without RSA "
                "authentication, matching CVE-2019-5478 (F-Secure / Inverse "
                "Path, FSC-HWSEC-VR2019-0001). In this mode the ZU+ BootROM "
                "does not authenticate the boot header — including the FSBL "
                "execution/start address — and the FSBL does not authenticate "
                "partition-header destination addresses. An attacker who can "
                "rewrite the boot media (SD/QSPI) can tamper the unauthenticated "
                "headers to redirect execution (e.g. ROP into a modified header) "
                "and achieve arbitrary code execution, defeating secure boot "
                "entirely. The BootROM half of the flaw is UNPATCHABLE (mask "
                "ROM) — only a new silicon revision fixes it; the documented "
                "remediation is to switch to Hardware Root of Trust (set RSA_EN), "
                "which authenticates the boot and partition headers. This is a "
                "real, exploitable misconfiguration on a fielded device — not a "
                "dev-board artifact. See docs/15-prior-research.md §1."
            ),
            offensive_implications=[
                "Rewrite boot media; tamper unauthenticated boot/partition headers",
                "Redirect FSBL execution address -> arbitrary code execution (ROP)",
                "Point a partition destination at the (modified) header itself to land payload",
                "Full secure-boot bypass: load attacker firmware while 'encrypted boot' appears enforced",
            ],
        )
    return None


# encryptionKeySource (boot-header off 0x28) magic -> human label.
# Source of truth: bootgen common/include/bootheader.h:64-70 (+ 0 = None).
_ENC_KEY_SRC = {
    0x00000000: "None (unencrypted)",
    0xA5C3C5A3: "eFuse RED key",
    0x3A5C3C5A: "BBRAM RED key",
    0xA5C3C5A5: "eFuse black/obfuscated key",
    0xA35C7C53: "boot-header black key",
    0xA5C3C5A7: "eFuse grey key",
    0xA35C7CA5: "boot-header grey key",
    0xA3A5C3C5: "boot-header KUP key",
}


def rule_auth_only_without_encryption(c: Capture) -> Finding | None:
    """Boot image authenticated but NOT encrypted — exposed to the auth-only /
    authentication-downgrade bypass class.

    Authentication without encryption means the boot image (or PL bitstream)
    is integrity-protected by RSA but its contents are plaintext. This is the
    configuration the Bochum/CASA results target: JustSTART (CVE-2023-20570)
    bypasses RSA authentication on the UltraScale(+) config engine entirely,
    and the 'Cautionary Note' authentication-downgrade attacks defeat the
    GHASH/auth path — both are mitigated only when bitstream encryption AND
    authentication are enabled together. See docs/15-prior-research.md §2-3.

    Two independent signals, either of which fires the rule:
      - REGISTER: CSU_STATUS reports the boot the ROM actually performed was
        authenticated (BOOT_AUTH=1) but not encrypted (BOOT_ENC=0). Always
        available on a booted target; reads 0/0 in JTAG-idle (rule abstains).
      - BOOT HEADER (only if ::BH_ADDR scan captured one): encryptionKeySource
        is None (unencrypted) while authentication is asserted (BH_RSA magic,
        AUTH_ONLY, or the eFuse RSA_EN policy). Self-validated by magic, so this
        signal only exists when a real boot header was found.
    """
    boot_auth = c.field("CSU.CSU_STATUS.BOOT_AUTH")
    boot_enc = c.field("CSU.CSU_STATUS.BOOT_ENC")
    eks = c.reg("BOOTHDR.ENC_KEY_SRC")
    auth_only = c.field("BOOTHDR.FSBL_ATTR.AUTH_ONLY")
    bh_rsa = c.field("BOOTHDR.FSBL_ATTR.BH_RSA")
    rsa_en = c.field("EFUSE.SEC_CTRL.RSA_EN")

    # Signal 1 — the boot the CSU actually performed (register).
    reg_signal = (boot_auth == 1 and boot_enc == 0)

    # Signal 2 — what the scanned boot header declares.
    bh_present = eks is not None
    bh_unencrypted = (eks == 0x00000000)
    bh_authenticated = (auth_only == 3 or bh_rsa == 3 or rsa_en == 1)
    bh_signal = bh_present and bh_unencrypted and bh_authenticated

    if not (reg_signal or bh_signal):
        return None

    evidence = []
    if reg_signal:
        evidence.append("CSU_STATUS: BOOT_AUTH=1, BOOT_ENC=0 (this boot was "
                        "authenticated but not encrypted)")
    if bh_signal:
        src = _ENC_KEY_SRC.get(eks, f"unknown (0x{eks:08X})")
        why = []
        if auth_only == 3:
            why.append("fsblAttributes.AUTH_ONLY=3")
        if bh_rsa == 3:
            why.append("fsblAttributes.BH_RSA=3 (boot-header RSA)")
        if rsa_en == 1:
            why.append("eFuse RSA_EN set")
        evidence.append(
            f"Boot header: encryptionKeySource=0x{eks:08X} -> {src}; "
            f"authentication asserted via {', '.join(why)}")

    return Finding(
        name="Authentication without encryption — auth-only boot/image (downgrade-bypass class)",
        severity="MAJOR",
        description=(
            "The boot image is authenticated (RSA) but its payload is not "
            "encrypted. Auth-only configurations are the target of the "
            "UltraScale(+) authentication-bypass / downgrade research."
        ),
        conclusion=(
            "This device boots an authenticated-but-unencrypted image — "
            + "; ".join(evidence) + ". Authentication-only protects integrity "
            "but leaks confidentiality, and is exactly the configuration the "
            "Bochum/CASA results break: JustSTART (CVE-2023-20570) bypasses RSA "
            "authentication on the UltraScale(+) configuration engine outright "
            "(load a trojanized bitstream), and the 'Cautionary Note' "
            "authentication-downgrade attacks defeat the GHASH/auth path. Both "
            "are documented as mitigated ONLY when bitstream encryption AND "
            "authentication are enabled together — auth-only is not sufficient. "
            "The signal here is the boot image / FSBL (CSU_STATUS + boot header); "
            "the same principle applies to PL bitstream partitions, whose "
            "per-partition encrypt/auth flags live in the partition header table "
            "(not read by this enumeration). Recommendation: enable bitstream "
            "encryption in addition to RSA authentication. See "
            "docs/15-prior-research.md §2-3."
        ),
        offensive_implications=[
            "Read plaintext firmware/IP directly from the (unencrypted) boot image",
            "Apply the JustSTART RSA-auth bypass to load a trojanized bitstream/image",
            "Apply an authentication-downgrade attack to defeat the integrity check",
            "No confidentiality protection — recover all IP for offline analysis",
        ],
    )


# Partition-header DEST_DEVICE enum (bootgen bootgenenum.h:375).
_DEST_DEVICE = {0: "NONE", 1: "PS", 2: "PL", 3: "PMU", 4: "XIP"}
_DEST_DEV_PL = 2
# Max partitions to consider (matches the live-walk cap in enumerate.tcl).
_PHT_MAX = 32


def rule_pl_bitstream_unprotected(c: Capture) -> Finding | None:
    """Per-partition encrypt/auth posture from a walked Partition Header Table.

    Consumes the synthetic PHT.PART<n>_ATTR registers produced by the boot-image
    walk (live `::BH_ADDR` scan in enumerate.tcl, or tools/parse-bootimage.py).
    Each partition's attributes word (off 0x24) decodes DEST_DEVICE (bits 6-4),
    ENCRYPT (bit 7) and AC_FLAG (bit 15); authentication is also asserted by a
    non-zero authCertificateOffset (PART<n>_ACOFF, off 0x34).

    Focus is the PL bitstream partition (DEST_DEVICE==2) — the actual target of
    JustSTART (CVE-2023-20570) and the 'Cautionary Note' attacks:
      - not encrypted AND not authenticated -> CRITICAL (fabric fully exposed)
      - authenticated but not encrypted      -> MAJOR (auth-only = the bypass class)
      - encrypted but not authenticated       -> MAJOR (GCM malleability / Starbleed lineage)
    Non-PL partitions in the same state are reported too (lower emphasis) since
    the same integrity/confidentiality gap applies. Abstains entirely when no
    PHT was walked (JTAG-idle / no boot image). See docs/15-prior-research.md §2-3.
    """
    findings = []  # (severity_rank, dest_name, partnum, enc, auth, text)
    any_partition = False
    for i in range(_PHT_MAX):
        attr_present = c.reg(f"PHT.PART{i}_ATTR")
        dest = c.field(f"PHT.PART{i}_ATTR.DEST_DEVICE")
        if attr_present is None and dest is None:
            continue
        any_partition = True
        enc = c.field(f"PHT.PART{i}_ATTR.ENCRYPT")
        ac_flag = c.field(f"PHT.PART{i}_ATTR.AC_FLAG")
        acoff = c.reg(f"PHT.PART{i}_ACOFF")
        partnum = c.reg(f"PHT.PART{i}_NUM")
        encrypted = (enc == 1)
        authenticated = (ac_flag == 1) or (acoff is not None and acoff != 0)
        dest_name = _DEST_DEVICE.get(dest, f"0x{dest:X}" if dest is not None else "?")
        is_pl = (dest == _DEST_DEV_PL)
        pn = partnum if partnum is not None else i

        if not encrypted and not authenticated:
            sev, label = ("CRITICAL" if is_pl else "MAJOR"), "unprotected (no encryption, no authentication)"
        elif authenticated and not encrypted:
            sev, label = "MAJOR", "auth-only (authenticated, NOT encrypted) — JustSTART / downgrade-bypass class"
        elif encrypted and not authenticated:
            sev, label = "MAJOR", "encrypted but NOT authenticated — GCM-malleability / Starbleed lineage"
        else:
            continue  # encrypted + authenticated = the secure configuration
        findings.append((sev, dest_name, pn, encrypted, authenticated, label))

    if not any_partition or not findings:
        return None

    # Overall severity = worst among partition findings; CRITICAL only from PL.
    rank = {"CRITICAL": 3, "MAJOR": 2, "MINOR": 1, "INFO": 0}
    severity = max((f[0] for f in findings), key=lambda s: rank[s])
    lines = []
    for sev, dest, pn, enc, auth, label in findings:
        lines.append(
            f"- partition {pn} (DEST_DEVICE={dest}): encrypted={enc} authenticated={auth} "
            f"-> {label}")
    body = "\n".join(lines)
    pl_hits = [f for f in findings if f[1] == "PL"]

    return Finding(
        name="PL bitstream / partition protection gap (per-partition encrypt/auth)",
        severity=severity,
        description=(
            "One or more boot-image partitions are not protected by both "
            "encryption and authentication. PL-bitstream partitions in this "
            "state are the direct target of the UltraScale(+) auth-bypass research."
        ),
        conclusion=(
            "Walked the Partition Header Table and decoded per-partition "
            "encrypt/auth attributes:\n" + body + "\n\n"
            + (f"{len(pl_hits)} PL-bitstream partition(s) are exposed. "
               if pl_hits else "")
            + "Authentication-only (or no protection) is exactly the "
            "configuration the Bochum/CASA results break: JustSTART "
            "(CVE-2023-20570) bypasses RSA authentication on the UltraScale(+) "
            "configuration engine to load a trojanized bitstream, and the "
            "'Cautionary Note' attacks defeat the GHASH/authentication path — "
            "both documented as mitigated only when bitstream encryption AND "
            "authentication are enabled together. Encryption-without-auth is "
            "separately vulnerable to GCM ciphertext malleability (Starbleed "
            "lineage). Recommendation: protect every PL bitstream partition with "
            "encryption AND authentication. See docs/15-prior-research.md §2-3."
        ),
        offensive_implications=[
            "Read plaintext PL IP from any unencrypted bitstream partition (IP cloning)",
            "Apply the JustSTART RSA-auth bypass to load a trojanized bitstream into the fabric",
            "Apply a GCM-malleability/downgrade attack against encrypt-only-without-auth partitions",
            "FPGA-resident covert-channel / hardware-Trojan insertion via the PL config path",
        ],
    )


def rule_aes_key_readable(c: Capture) -> Finding | None:
    """AES_RDLK clear — if an AES key is stored in eFUSE, it can be read from JTAG."""
    if c.field("EFUSE.SEC_CTRL.AES_RDLK") == 0:
        return Finding(
            name="AES key readable from eFUSE shadow",
            severity="INFO",
            description=(
                "AES_RDLK is clear — if an AES key is stored in eFUSE, it can "
                "be read from JTAG."
            ),
            conclusion=(
                "The AES_RDLK fuse has not been blown, so the AES key region in "
                "eFUSE shadow is readable via JTAG access. If the device uses "
                "encrypted boot and stores its AES key in eFUSE (vs BBRAM), "
                "this exposes the key. On a dev kit with no AES key loaded, "
                "this is harmless. On a production device with encrypted-boot "
                "enabled but AES_RDLK unset, the secure-boot chain's "
                "confidentiality is broken."
            ),
            offensive_implications=[
                "Read AES key directly from eFUSE shadow (if loaded)",
                "Decrypt all encrypted boot images for this device offline",
            ],
        )
    return None


def rule_sec_lock_mutable(c: Capture) -> Finding | None:
    """SEC_LOCK clear — SEC_CTRL register can still be modified."""
    if c.field("EFUSE.SEC_CTRL.SEC_LOCK") == 0:
        return Finding(
            name="SEC_CTRL still mutable — partial hardening or dev state",
            severity="INFO",
            description="SEC_LOCK is clear.",
            conclusion=(
                "SEC_CTRL is not write-locked. On a production device this would "
                "be a process gap — manufacturing should blow SEC_LOCK as the "
                "final hardening step. On a dev kit, this is expected and "
                "indicates the device can still have its security policy modified."
            ),
            offensive_implications=[
                "Attacker with physical access can blow additional fuses",
                "Or selectively un-invalidate keys via PPK_INVLD field manipulation",
            ],
        )
    return None


def rule_jtag_dis_clear(c: Capture) -> Finding | None:
    """JTAG_DIS fuse not blown — JTAG remains accessible at the hardware level."""
    if c.field("EFUSE.SEC_CTRL.JTAG_DIS") == 0:
        return Finding(
            name="JTAG hardware disable NOT set",
            severity="INFO",
            description="JTAG_DIS one-way fuse has not been blown.",
            conclusion=(
                "JTAG remains accessible at the hardware level. Expected on any "
                "device where JTAG is intentionally available (dev kits, fielded "
                "devices that need RMA debug). On the most hardened production "
                "posture, this fuse would be blown, making JTAG permanently "
                "inaccessible."
            ),
        )
    return None


def rule_rpu_debug_enabled(c: Capture) -> Finding | None:
    """RPU debug authorization is on."""
    if c.field("CSU.JTAG_DAP_CFG.SSSS_RPU_DBGEN") == 1:
        return Finding(
            name="RPU debug enabled",
            severity="INFO",
            description="R5 real-time cluster is debuggable via JTAG.",
            conclusion=(
                "The Cortex-R5 cluster (real-time processing unit) can be "
                "halted, stepped, and inspected via JTAG. Useful for targeting "
                "real-time firmware like FreeRTOS, VxWorks, or custom safety "
                "code running on R5. On a hardened device with R5 running "
                "attested firmware (PMU, safety controllers), this would "
                "typically be gated."
            ),
        )
    return None


def rule_pltap_path_unlocked(c: Capture) -> Finding | None:
    """PL TAP path fully open — PL JTAG reachable."""
    if c.field("CSU.JTAG_SEC.SSSS_PLTAP_SEC") == 7:
        return Finding(
            name="PL TAP path unlocked — FPGA-side JTAG reachable",
            severity="INFO",
            description="CSU Secure Stream Switch PL TAP path is open (0b111).",
            conclusion=(
                "PL JTAG fully reachable through the chain. Can read FPGA "
                "configuration memory, extract loaded bitstream, write custom "
                "bitstream. On a device with sensitive PL IP (signal processing, "
                "crypto accelerators, custom logic), this enables IP extraction "
                "and FPGA-resident covert channel insertion."
            ),
            offensive_implications=[
                "Bitstream extraction — recover any IP loaded into PL",
                "Bitstream substitution — load attacker FPGA design",
                "FPGA-resident covert channel insertion",
            ],
        )
    return None


# =========================================================================
# XPPU rules
# =========================================================================

def rule_xppu_disabled(c: Capture) -> Finding | None:
    """XPPU master enable is clear — no peripheral isolation enforced."""
    if c.field("XPPU.CTRL.ENABLE") == 0:
        return Finding(
            name="XPPU disabled — no peripheral isolation enforced",
            severity="INFO",
            description=(
                "The XPPU master enable bit is clear, so all AXI masters can "
                "reach all peripherals without restriction."
            ),
            conclusion=(
                "Peripheral protection is currently inactive. Every master on "
                "the LPD AXI fabric (APU, RPU, PMU, DMA engines, PL masters) "
                "can access every LPD peripheral aperture without checks. "
                "Expected in JTAG-idle — PMU firmware activates XPPU during "
                "boot. A finding on a booted production device."
            ),
        )
    return None


def rule_xppu_parity_disabled(c: Capture) -> Finding | None:
    """Both XPPU parity checks off — no detection of bit flips in tables."""
    if (c.field("XPPU.CTRL.MID_PARITY_EN") == 0 and
            c.field("XPPU.CTRL.APER_PARITY_EN") == 0):
        return Finding(
            name="XPPU parity protection disabled",
            severity="INFO",
            description=(
                "Both MID and aperture parity checks are off — no detection of "
                "bit flips in the XPPU tables."
            ),
            conclusion=(
                "XPPU's hardware parity checks are disabled. A transient bit "
                "flip in the master ID or aperture permission tables (from "
                "radiation, fault injection, or silicon defect) would go "
                "undetected. Dev-kit default; hardened production typically "
                "enables both parity checks."
            ),
        )
    return None


def rule_xppu_violations_latched(c: Capture) -> Finding | None:
    """One or more XPPU ISR violation bits are set — significant signal."""
    triggered = _any_xppu_violation(c)
    if triggered:
        return Finding(
            name=f"XPPU protection violations latched ({', '.join(triggered)})",
            severity="MAJOR",
            description=(
                "One or more protection-violation interrupt status bits are set "
                "in XPPU's ISR."
            ),
            conclusion=(
                "XPPU has latched at least one protection violation: "
                f"{', '.join(triggered)}. Cross-reference ERR_STATUS1 / "
                "ERR_STATUS2 in the XPPU register dump for the offending AXI "
                "address and master ID. Cross-reference UG1085 §27 master ID "
                "table to identify the source. On a properly configured "
                "production device this should be zero — any latched bit "
                "indicates either a real attempted violation or a configuration "
                "issue worth investigating."
            ),
        )
    return None


def rule_security_posture_summary(c: Capture) -> Finding | None:
    """Always-on consolidated security-posture checklist.

    One row per security implementation: where it lives, its current value, and
    an OFF/dev -> ON/provisioned verdict. On factory/dev silicon every row reads
    OFF/unprovisioned (the all-open baseline); pointed at a hardened part the
    same rows flip to show exactly what has been switched on. Registers not in
    the capture render as 'n/a (not captured)'.
    """
    rows = []

    def row(impl, loc, value, verdict):
        rows.append(f"| {impl} | `{loc}` | {value} | {verdict} |")

    def hexv(v):
        return "n/a" if v is None else f"0x{v:X}"

    def na(v):
        return v is None

    # ---- Secure boot / authentication ----
    rsa = c.field("EFUSE.SEC_CTRL.RSA_EN")
    row("RSA boot authentication", "SEC_CTRL.RSA_EN", hexv(rsa),
        "n/a (not captured)" if na(rsa)
        else ("**ON — signed boot enforced**" if rsa else "OFF — unsigned boot accepted (dev)"))

    enc = c.field("EFUSE.SEC_CTRL.ENC_ONLY")
    row("Encrypt-only boot", "SEC_CTRL.ENC_ONLY", hexv(enc),
        "n/a (not captured)" if na(enc)
        else ("**ON — encrypted boot enforced**" if enc else "OFF — plaintext boot accepted (dev)"))

    for idx in (0, 1):
        words = [c.reg(f"EFUSE.PPK{idx}_{i}") for i in range(12)]
        if all(w is None for w in words):
            val, verdict = "n/a", "n/a (not captured)"
        else:
            nz = any(w for w in words if w)
            val = "non-zero" if nz else "all-zero"
            verdict = ("**provisioned — RSA root of trust present**" if nz
                       else "unprovisioned (no PPK hash burned)")
        row(f"PPK{idx} public-key hash", f"EFUSE.PPK{idx}_0..11", val, verdict)

    for idx in (0, 1):
        inv = c.field(f"EFUSE.SEC_CTRL.PPK{idx}_INVLD")
        row(f"PPK{idx} revoked", f"SEC_CTRL.PPK{idx}_INVLD", hexv(inv),
            "n/a (not captured)" if na(inv) else ("REVOKED" if inv else "not revoked"))

    # ---- AES / key confidentiality ----
    crc = c.reg("EFUSE.EFUSE_AES_CRC")
    row("eFuse AES key present", "EFUSE.EFUSE_AES_CRC", hexv(crc),
        "n/a (not captured)" if na(crc)
        else "indeterminate — AES_CRC is a write-to-verify register (reads 0 regardless); "
             "eFuse AES-key presence is NOT passively readable via JTAG")

    rdlk = c.field("EFUSE.SEC_CTRL.AES_RDLK")
    row("AES key read-lock", "SEC_CTRL.AES_RDLK", hexv(rdlk),
        "n/a (not captured)" if na(rdlk)
        else ("**ON — eFuse AES key not readable**" if rdlk else "OFF — eFuse AES key readable if present (dev)"))
    wrlk = c.field("EFUSE.SEC_CTRL.AES_WRLK")
    row("AES key write-lock", "SEC_CTRL.AES_WRLK", hexv(wrlk),
        "n/a (not captured)" if na(wrlk)
        else ("ON — eFuse AES key immutable" if wrlk else "OFF — eFuse AES key writable (dev)"))

    aes = c.reg("CSU.AES_STATUS")
    if na(aes):
        row("AES key slots loaded", "CSU.AES_STATUS", "n/a", "n/a (not captured)")
    else:
        allzero = (aes & 0xF00) == 0xF00
        row("AES key slots loaded", "CSU.AES_STATUS", f"0x{aes:X}",
            "OFF — all key slots read zero (dev)" if allzero else "**a key slot holds a non-zero key**")

    # ---- JTAG / debug authorization ----
    jdis = c.field("EFUSE.SEC_CTRL.JTAG_DIS")
    row("JTAG disable fuse", "SEC_CTRL.JTAG_DIS", hexv(jdis),
        "n/a (not captured)" if na(jdis)
        else ("**ON — JTAG hardware-disabled**" if jdis else "OFF — JTAG enabled (dev / debug-open)"))
    dft = c.field("EFUSE.SEC_CTRL.DFT_DIS")
    row("DFT disable fuse", "SEC_CTRL.DFT_DIS", hexv(dft),
        "n/a (not captured)" if na(dft)
        else ("ON — DFT JTAG disabled" if dft else "OFF — DFT paths enabled"))

    spiden = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN")
    spniden = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPNIDEN")
    if na(spiden) and na(spniden):
        row("APU secure debug", "JTAG_DAP_CFG.SSSS_APU_SP*IDEN", "n/a", "n/a (not captured)")
    else:
        sd = bool(spiden) or bool(spniden)
        row("APU secure debug (SPIDEN/SPNIDEN)", "JTAG_DAP_CFG.SSSS_APU_SP*IDEN",
            f"SPIDEN={spiden} SPNIDEN={spniden}",
            "**OPEN — secure-world JTAG allowed (dev)**" if sd else "gated — secure debug denied")

    dbgen = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN")
    row("APU non-secure debug", "JTAG_DAP_CFG.SSSS_APU_DBGEN", hexv(dbgen),
        "n/a (not captured)" if na(dbgen)
        else ("OPEN — APU debug enabled (dev)" if dbgen else "gated"))

    # ---- Live debug-gate observation (from the §8 EDPCSR + halt probe) ----
    # These come from raw["a53"] (the live debug probe), not the register block.
    # The eFuse/CSU rows above say whether debug is *authorized*; these say what
    # the DAP could *actually do* against the running core right now.
    a53 = c.raw.get("a53", {}) if isinstance(c.raw, dict) else {}
    inv = a53.get("invasive_debug")
    # Per-core breakdown from the all-4-cores §8 sweep (e.g. "c0=open c1=wedged ...").
    csum = a53.get("cores_summary")
    if isinstance(csum, (list, tuple)):
        csum = " ".join(str(x) for x in csum)
    per_core = f" [per core: {csum}]" if csum else ""
    if inv is None:
        row("Invasive JTAG debug (halt)", "a53.invasive_debug", "n/a", "n/a (not captured)")
    elif inv == "open":
        row("Invasive JTAG debug (halt)", "a53.invasive_debug", "open",
            "OPEN — DAP halted at least one A53 core (dev / no firmware debug-gate)" + per_core)
    elif inv == "gated":
        row("Invasive JTAG debug (halt)", "a53.invasive_debug", "gated",
            "**GATED — a core is running but halt refused (firmware debug-auth)**" + per_core)
    elif inv == "wedged":
        row("Invasive JTAG debug (halt)", "a53.invasive_debug", "wedged",
            f"WEDGED — a core stalled on a hung access (PC pinned); halt can't recover it, "
            f"only EDPCSR can read it{per_core}")
    else:
        row("Invasive JTAG debug (halt)", "a53.invasive_debug", str(inv),
            "no A53 core examinable via the DAP (all in reset)" + per_core)

    pcs = a53.get("pc_sampling")
    livepc = a53.get("live_pc")
    if pcs is None:
        row("Non-invasive PC sampling (EDPCSR)", "a53.pc_sampling", "n/a", "n/a (not captured)")
    elif pcs in (True, "true"):
        row("Non-invasive PC sampling (EDPCSR)", "a53.pc_sampling", "available",
            f"available — live PC `{livepc}` (works even when halt is gated)")
    else:
        row("Non-invasive PC sampling (EDPCSR)", "a53.pc_sampling", "off",
            "prohibited / core not running")

    # ---- Anti-tamper ----
    tvals = [c.reg(f"CSU.CSU_TAMPER_{i}") for i in range(13)]
    if all(v is None for v in tvals):
        row("Anti-tamper response policy", "CSU.CSU_TAMPER_0..12", "n/a", "n/a (not captured)")
    else:
        armed = any(v for v in tvals if v)
        row("Anti-tamper response policy", "CSU.CSU_TAMPER_0..12",
            "armed" if armed else "all-zero",
            "**ARMED — tamper sources wired to a response**" if armed
            else "OFF — no tamper response armed (dev)")
    tstat = c.reg("CSU.TAMPER_STATUS")
    row("Tamper events latched", "CSU.TAMPER_STATUS", hexv(tstat),
        "n/a (not captured)" if na(tstat)
        else ("**LATCHED — tamper fired**" if tstat else "none latched"))

    # ---- Lockdown ----
    seclk = c.field("EFUSE.SEC_CTRL.SEC_LOCK")
    row("Secure lockdown fuse", "SEC_CTRL.SEC_LOCK", hexv(seclk),
        "n/a (not captured)" if na(seclk)
        else ("ON — further fuse programming locked" if seclk else "OFF — fuses still programmable (dev)"))

    # ---- Memory TrustZone (DDR/OCM XMPU) ----
    for inst in ("DDR_XMPU0", "OCM_XMPU"):
        ctrl = c.reg(f"{inst}.CTRL")
        row(f"{inst} memory protection", f"{inst}.CTRL", hexv(ctrl),
            "n/a (not captured)" if na(ctrl)
            else (f"configured (0x{ctrl:X})" if ctrl else "OFF — default-open (dev)"))

    table = ("\n\n| Security implementation | Location | Value | State |\n"
             "|---|---|---|---|\n" + "\n".join(rows) + "\n")
    return Finding(
        name="Security Posture Summary",
        severity="INFO",
        conclusion=(
            "Consolidated security-implementation checklist. On factory/dev silicon "
            "every row reads OFF/unprovisioned (the all-open baseline); run the same "
            "enumeration on a hardened part and the rows flip to show exactly what "
            "has been switched on. **Bold** states are the ones that, when ON, "
            "materially change the attack surface." + table),
        description="At-a-glance OFF/dev -> ON/provisioned map of every security gate.",
    )


def rule_engagement_triage(c: Capture) -> Finding | None:
    """Always-on top-line verdict: what STATE is this board in, what's OPEN, and which tools to
    run next — derived from the same posture fields as the Security Posture Summary. Turns the
    22-row checklist into a one-glance decision: classify (ALL-OPEN / PARTIALLY PROVISIONED /
    HARDENED) and recommend the next tools, gated on what's actually open."""

    def on(v):
        return None if v is None else bool(v)

    rsa   = c.field("EFUSE.SEC_CTRL.RSA_EN")
    enc   = c.field("EFUSE.SEC_CTRL.ENC_ONLY")
    jdis  = c.field("EFUSE.SEC_CTRL.JTAG_DIS")
    seclk = c.field("EFUSE.SEC_CTRL.SEC_LOCK")
    dbgen = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN")
    spiden  = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN")
    spniden = c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPNIDEN")

    ppk_words = [c.reg(f"EFUSE.PPK{idx}_{i}") for idx in (0, 1) for i in range(12)]
    ppk_sig = None if all(w is None for w in ppk_words) else any(w for w in ppk_words if w)
    tamper_vals = [c.reg(f"CSU.CSU_TAMPER_{i}") for i in range(13)]
    tamper_sig = None if all(v is None for v in tamper_vals) else any(v for v in tamper_vals if v)
    sd_known = not (spiden is None and spniden is None)
    sd_gated = None if not sd_known else (not (bool(spiden) or bool(spniden)))

    a53 = c.raw.get("a53", {}) if isinstance(c.raw, dict) else {}
    invasive = a53.get("invasive_debug")
    ddr_xmpu = c.reg("DDR_XMPU0.CTRL")
    ocm_xmpu = c.reg("OCM_XMPU.CTRL")

    # Each hardening signal: True = enabled (a step toward a locked part), None = not captured.
    sig = {
        "signed boot (RSA_EN)":          on(rsa),
        "encrypt-only boot (ENC_ONLY)":  on(enc),
        "JTAG-disable fuse (JTAG_DIS)":  on(jdis),
        "secure lockdown (SEC_LOCK)":    on(seclk),
        "PPK RSA root provisioned":      ppk_sig,
        "anti-tamper armed":             tamper_sig,
        "secure-world debug gated":      sd_gated,
    }
    known = {k: v for k, v in sig.items() if v is not None}
    on_count = sum(1 for v in known.values() if v)
    enforced = [k for k, v in known.items() if v]
    openish  = [k for k, v in known.items() if not v]

    if not known:
        verdict = "UNKNOWN — security fuses not captured"
        headline = "The capture lacks the SEC_CTRL/eFuse rows needed to classify the board; re-run §4."
    elif on_count == 0:
        verdict = "ALL-OPEN — factory/dev, unprovisioned baseline"
        headline = ("No hardening controls are enabled. The open JTAG DAP is the trust boundary — "
                    "you already have full read/write; the work is to demonstrate what that allows.")
    elif rsa == 1 and jdis == 1:
        verdict = "HARDENED"
        headline = "Signed boot and the JTAG-disable fuse are both set — the two pillars of a locked part."
    else:
        verdict = f"PARTIALLY PROVISIONED — {on_count} of {len(known)} controls enabled"
        headline = "Some controls are on, some off — the engagement is to hunt the gaps."

    dap_open = (jdis != 1) and (bool(dbgen) or bool(spiden) or bool(spniden) or invasive == "open")

    steps = []
    if verdict == "HARDENED":
        steps.append("JTAG/secure-boot enforced — expect the capability tools to be **refused** "
                     "(a refusal is the finding). Confirm the access verdict with `jtag-access-check.tcl`.")
        steps.append("Pivot to boot-image analysis if you can dump QSPI/SD (`parse-bootimage.py`), "
                     "and map the config against `docs/15` (known ZU+/ZynqMP CVEs).")
        steps.append("Consider side-channel / physical avenues — `docs/13` tiers 2-3.")
    else:
        if dap_open:
            steps.append("**DAP is open → full memory read/write.** Demonstrate impact: `inject.tcl` "
                         "(COLD-mode code exec), `jtag-ddr-boot.tcl` (boot an arbitrary OS over JTAG). "
                         "Snapshot chip values (Device DNA, eFuse cache, PUF helper data, ROM/PMU hashes).")
        if rsa != 1:
            steps.append("**Boot chain unauthenticated** → dump the boot device (QSPI/SD) and run "
                         "`parse-bootimage.py`; unsigned/modified images will be accepted. Cross-check "
                         "`docs/15` (CVE-2023-20570 JustSTART, CVE-2019-5478 encrypt-only).")
        if (ddr_xmpu == 0) or (ocm_xmpu == 0):
            steps.append("Memory isolation (XMPU) is default-open → any AXI master reaches all of DDR/OCM.")
        steps.append("Map the CSU/crypto surface non-destructively: `probe-csu-surface.tcl` / "
                     "`probe-csu-fullmap.tcl`.")
    steps.append("_Out of scope here:_ the CSU BootROM is not AXI-mapped (not dumpable) and the "
                 "family/gray key is hardware-only — don't pursue `dump-bootrom` for the ROM/key (`docs/12`).")

    parts = [f"**Board state: {verdict}.** {headline}"]
    if enforced:
        parts.append("**Enforced:** " + ", ".join(enforced) + ".")
    if openish:
        parts.append("**Open:** " + ", ".join(openish) + ".")
    parts.append("**Recommended next steps (gated on this state):**")
    parts.append("\n".join(f"- {s}" for s in steps))

    return Finding(
        name="Engagement Triage — Board State & Next Steps",
        severity="INFO",
        conclusion="\n\n".join(parts),
        description="One-line board-state verdict + which tools to run next, derived from the posture.",
    )


# =============================================================================
# Registry — interpret.py imports this list
# =============================================================================

ALL_RULES = [
    rule_engagement_triage,
    rule_security_posture_summary,
    rule_max_debug_exposure,
    rule_spiden_critical,
    rule_cve_2019_5478_encrypt_only_bypass,
    rule_auth_only_without_encryption,
    rule_pl_bitstream_unprotected,
    rule_encrypted_boot_not_enforced,
    rule_aes_key_readable,
    rule_sec_lock_mutable,
    rule_jtag_dis_clear,
    rule_rpu_debug_enabled,
    rule_pltap_path_unlocked,
    rule_xppu_disabled,
    rule_xppu_parity_disabled,
    rule_xppu_violations_latched,
]
