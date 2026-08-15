"""
jtagx.weakness — the IMPLEMENTATION-REVIEW / misuse-hypothesis layer.

Separate from jtagx.cve (published CVEs / named attacks). This is the project's own research output:
observations from reading the *implementation* (register semantics, the trust model, which master can
reach what) and reasoning about where a design decision COULD be misused — even with no CVE attached.
That is the project's founding move (the open-DAP-is-the-trust-boundary finding was ours, not a CVE).

Each hypothesis records: the CLASS of weakness, what you OBSERVE (a predicate on the posture/impl),
WHY it is misusable, and the PRIMITIVE it grants. `misuse_findings(soc, P)` fires the ones whose
observation holds. Add to HYPOTHESES as you review more silicon — this is meant to grow.

Classes:
  design-primitive     — the vendor exposed a reconfiguration primitive an attacker can reach
  trust-assumption     — the implementation trusts something an attacker controls
  asymmetric-protection— one path is guarded, an equivalent path isn't
  volatile-secret      — a key/secret is stored somewhere clearable/attackable
  alternate-master     — a second bus master / hidden TAP reaches what the primary can't
  thesis               — the project's stance on the posture
"""

_ALL = None   # socs=None ⇒ applies to any chip


def _h(id, cls, socs, observe, title, misuse, sev, ref="", probe=""):
    # probe (optional): a command/script to INVESTIGATE the hypothesis on a live target.
    return dict(id=id, cls=cls, socs=socs, observe=observe, title=title, misuse=misuse, sev=sev,
                ref=ref, probe=probe)


HYPOTHESES = [
    _h("reconfigurable-debug-gate", "design-primitive", ["zynqmp", "zynq7000"],
       lambda P: P.get("efuse_jtag_dis") is False or (P.get("jtag_locked") and not P.get("efuse_jtag_dis")),
       "The debug-enable gate (CSU JTAG_SEC / JTAG_DAP_CFG) is a MUTABLE register, not an eFuse.",
       "any AXI master — including an open DAP — can rewrite it OPEN at runtime (reopen-debug.tcl). "
       "The vendor exposed a reconfiguration primitive that ONLY an eFuse actually freezes.", "HIGH"),

    _h("axi-master-trust", "trust-assumption", ["zynqmp"],
       lambda P: P.get("jtag_open"),
       "The CSU debug-security registers are reachable from the AXI interconnect — the design trusts "
       "every AXI master, and the DAP is an AXI master.",
       "an open DAP inherits full trust over the security configuration; the real trust boundary is "
       "'is the DAP shut?', not the CSU registers behind it.", "HIGH"),

    _h("alt-master-rom", "alternate-master", ["zynqmp"],
       lambda P: True,
       "The AXI read-filter blocks DAP reads of the PMU/CSU ROM, but the CSUDMA (an alternate AXI "
       "master) and the MicroBlaze BSCAN TAP are not equivalently filtered.",
       "route the read through the unfiltered alternate master to reach ROM the DAP can't "
       "(probe-csu-dma-rom.tcl / open-pmu-tap.tcl) — asymmetric protection.", "MED",
       probe='openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-csu-dma-rom.tcl; shutdown"'),

    _h("boundary-scan-surface", "asymmetric-protection", _ALL,
       lambda P: P.get("jtag_locked") or P.get("debug_locked"),
       "A gated debug DAP does NOT gate the IEEE-1149.1 boundary-scan layer — EXTEST/SAMPLE usually "
       "still answer.",
       "read straps/mode/bus pins (and drive them) via boundary-scan even when the DAP is shut "
       "(tools/bsdl-scan.py) — a separate, often-forgotten surface.", "LOW",
       probe="python3 tools/bsdl-scan.py <part>.bsdl --sample-plan"),

    _h("bbram-volatile-key", "volatile-secret", ["zynqmp", "zynq7000"],
       lambda P: P.get("aes_encrypt"),
       "The boot AES key can live in BBRAM (battery-backed RAM), not an eFuse — it is volatile.",
       "a power/battery attack clears the key (denial-of-boot); and BBRAM is not immutable like an "
       "eFuse, widening the window for read/fault attacks on the key path.", "MED"),

    _h("sf2-security-policy-flash", "design-primitive", ["smartfusion2"],
       lambda P: P.get("debug_locked"),
       "SmartFusion2 M3 debug-disable is a SECURITY-POLICY flash cell, not a fuse — set by the "
       "programming flow.",
       "if the policy isn't permanently locked, re-programming (FlashPro) can write it back OPEN; and "
       "the System-Controller boot decision that reads it is a glitch target.", "MED"),

    _h("csu-aes-oracle", "alternate-master", ["zynqmp"],
       lambda P: P.get("aes_encrypt"),
       "The CSU AES engine + the Secure-Stream-Switch (SSS) are MEMORY-MAPPED at 0xFFCA0000 and driven "
       "by software; the device/black-key ('DEV') source is routed by the BootROM, but the engine and "
       "SSS_CFG (0xFFCA0008) sit on the AXI bus.",
       "if an open DAP can drive CSUDMA + SSS + the AES engine while a DEV key is loaded, the hardware "
       "AES becomes a DECRYPTION ORACLE (the Path-A family/device-key vector) — confidentiality rests "
       "entirely on the SSS routing, not on the key being unreadable.", "HIGH", "docs/14 §3; AES_KEY_SRC 0xFFCA1004"),

    _h("multiboot-redirect", "design-primitive", ["zynqmp"],
       lambda P: P.get("jtag_open"),
       "CSU_MULTI_BOOT (0xFFCA0010) — the golden-image search offset — is a WRITABLE register, and the "
       "FSBL fallback path writes it then soft-resets via CRL_APB_RESET_CTRL to re-search the boot device.",
       "an AXI master (open DAP) can write CSU_MULTI_BOOT + trigger a soft reset to force the BootROM to "
       "boot from an ATTACKER-CHOSEN offset — the golden-image mechanism turned against the device.",
       "MED", "docs/14 §2; xfsbl_main.c:497-550", probe="mdw 0xFFCA0010 1"),

    _h("xmpu-runtime-reconfig", "design-primitive", ["zynqmp"],
       lambda P: P.get("jtag_open"),
       "Memory/peripheral isolation (XMPU 0xFD000000.., XPPU 0xFF980000) is SOFTWARE configuration held "
       "in writable registers, set by the FSBL — and default-permit until then (a boot-time window).",
       "a privileged/AXI master can RECONFIGURE OR DISABLE XMPU/XPPU at runtime to reach protected DRAM/"
       "peripherals; and pre-FSBL there is no isolation at all.", "MED", "docs/11; docs/14 §9"),

    _h("puf-kek-unverified", "trust-assumption", ["zynqmp"],
       lambda P: P.get("aes_encrypt"),
       "The black-key confidentiality rests on the PUF-derived KEK NEVER being SW/JTAG-exposed — a claim "
       "the project's own review flagged as UNRESOLVED (1-2 vote, docs/12:75), not confirmed.",
       "an open research question worth probing: if any KEK/PUF path is observable over JTAG/AXI, the "
       "black key falls. This is a hypothesis to TEST, not a settled fact — exactly the research posture.",
       "MED", "docs/12:75 (unresolved)"),

    _h("pmu-ipi-pm-api", "alternate-master", ["zynqmp"],
       lambda P: P.get("jtag_open"),
       "The APU↔PMU IPI channel (0xFF3x) is a message interface to the PMU — the power/reset/security "
       "manager. The PMU acts on EEMI 'PM API' requests from the APU.",
       "an APU-side attacker (or an open DAP driving the APU) can issue PM API calls: power domains "
       "on/off, core resets, and PMU-mediated security/isolation ops — a second, software channel into "
       "the security manager that isn't the DAP.", "MED", "docs/14 §8 (PMU FW / PM API / IPI)"),

    _h("tamper-response-optional", "design-primitive", ["zynqmp"],
       lambda P: not P.get("secure_boot"),
       "Tamper detection + response (CSU_TAMPER_TRIG 0xFFCA0014) and image anti-rollback are SOFTWARE-"
       "configured and often unprovisioned on a dev/field board.",
       "with no tamper response, physical/glitch/decap attacks trigger no key-wipe or lockdown; with no "
       "anti-rollback, an attacker can DOWNGRADE to an older, vulnerable signed image.", "MED",
       "docs/14 §3 (CSU_TAMPER_TRIG)", probe="mdw 0xFFCA0014 1"),

    _h("sss-route-misconfig", "design-primitive", ["zynqmp"],
       lambda P: P.get("aes_encrypt"),
       "The Secure-Stream-Switch crossbar (CSU_SSS_CFG 0xFFCA0008) is the SOLE barrier preventing "
       "plaintext/key taps between the AES/SHA/RSA/PCAP engines and the CSU DMA — and it is a WRITABLE "
       "config register.",
       "a misconfigured or attacker-set SSS route could steer decrypted output to a readable sink "
       "(a Starbleed-class idea generalised); confidentiality reduces to 'is SSS_CFG trustworthy?'.",
       "MED", "docs/14 §3 (CSU_SSS_CFG 0xFFCA0008)", probe="mdw 0xFFCA0008 1"),

    _h("bootheader-preauth-parse", "trust-assumption", ["zynqmp", "zynq7000"],
       lambda P: P.get("secure_boot") in ("encrypt-only", False),
       "The boot header (including the key/IV SOURCE fields, enc-key-src 0x28, grey/black key 0x4C) is "
       "PARSED by the BootROM/FSBL BEFORE authentication; in encrypt-only mode it is never authenticated.",
       "attacker-controlled boot parameters before the trust check — the root cause of CVE-2019-5478 "
       "(encrypt-only header bypass). The header is an unauthenticated input to the boot decision.",
       "HIGH", "docs/12:123; CVE-2019-5478"),

    _h("rpu-r5-alt-debug", "alternate-master", ["zynqmp"],
       lambda P: P.get("jtag_open"),
       "The RPU (Cortex-R5 lockstep pair) has its OWN CoreSight debug path, separate from the APU A53s — "
       "and lockstep can be split to run the R5s independently.",
       "if hardening focuses on the APU, the R5 debug is a second core-debug entry (halt/dump/patch the "
       "real-time domain); breaking lockstep lets you run attacker code on one R5 while the other holds.",
       "MED", "docs/14 §7 (RPU config)"),

    _h("efuse-shadow-glitch", "trust-assumption", ["zynqmp"],
       lambda P: True,
       "The security policy (EFUSE_SEC_CTRL) is loaded from the eFuse array into a SHADOW/cache at boot; "
       "downstream checks read the shadow, not the fuse directly.",
       "the eFuse-shadow LOAD is a fault-injection target — a glitch during the boot-time cache load can "
       "make the policy read as 0 (RSA/JTAG-dis/enc-only all off) even on a provisioned part. Test it.",
       "MED", "docs/14 §6; xilskey eFuse-shadow load"),

    _h("pcap-pl-reconfig", "alternate-master", ["zynqmp", "zynq7000"],
       lambda P: P.get("jtag_open"),
       "The PCAP (Processor Config Access Port) lets software (re)configure the PL fabric at RUNTIME "
       "from the PS side.",
       "an open DAP driving PCAP can load an ARBITRARY bitstream into the PL — the fabric then becomes an "
       "attacker-controlled AXI master that can bridge to DDR/OCM/secure peripherals (a hardware implant "
       "reachable purely over JTAG).", "HIGH", "docs/14 §3 (PCAP)"),

    _h("peripheral-dma-master", "alternate-master", ["zynqmp"],
       lambda P: P.get("jtag_open") or (P.get("jtag_locked") and not P.get("efuse_jtag_dis")),
       "GEM (Ethernet) / USB / SD / QSPI DMA engines are full AXI MASTERS; XMPU/XPPU are default-permit "
       "until the FSBL constrains them.",
       "a compromised or DAP-driven peripheral DMA can read/write protected DRAM/OCM without the CPU or "
       "the DAP mem-AP — a non-obvious master that bypasses core-centric protections.", "MED",
       "docs/14 §9 (XMPU/XPPU + AXI masters)"),

    _h("xmpu-boot-window-race", "asymmetric-protection", ["zynqmp"],
       lambda P: True,
       "Between reset and the FSBL configuring XMPU/XPPU there is a WINDOW where isolation is off "
       "(default-permit); DDR/OCM may also retain prior-boot data across a warm reset (remanence).",
       "a fast attacker or a well-timed warm reset can read DDR/OCM (incl. leftover keys/plaintext) in "
       "the pre-isolation window — the protection is temporal, not absolute.", "MED",
       "docs/14 §9 (boot-window) + DDR remanence"),

    _h("efuse-unprovisioned-takeover", "design-primitive", ["zynqmp", "zynq7000"],
       lambda P: not P.get("secure_boot") and not P.get("efuse_jtag_dis"),
       "On an UNPROVISIONED part the PPK/SPK/AES key eFuses and the RSA-enforce / JTAG-disable fuses are "
       "all blank — the root of trust is empty.",
       "an attacker with JTAG/programming access can BLOW THEIR OWN keys + enforce RSA → take OWNERSHIP "
       "of the secure-boot root of trust (a persistent, un-removable implant), or brick the part by "
       "blowing fuses. The window is 'device not yet provisioned by the vendor'.", "HIGH",
       "docs/12 (key hierarchy) / docs/14 §6 (eFuse)"),

    _h("tamper-dos-zeroize", "design-primitive", ["zynqmp"],
       lambda P: P.get("aes_encrypt"),
       "The anti-tamper response can ZEROIZE the BBRAM boot key on a detected tamper event.",
       "inducing a tamper event (voltage/temp/JTAG source) is a DENIAL-OF-BOOT / key-destruction DoS — "
       "the very mechanism meant to protect the key is a lever to destroy it.", "LOW",
       "docs/14 §3 (CSU_TAMPER_TRIG + BBRAM zeroize)"),

    _h("psu-init-unauth", "trust-assumption", ["zynqmp"],
       lambda P: P.get("secure_boot") is False,
       "DDR/PLL/clock bring-up (Vitis-generated `psu_init`) runs inside FSBL STAGE1 — a large MMIO write "
       "sequence that executes BEFORE any partition authentication.",
       "if the FSBL is replaced (secure boot off), psu_init is fully attacker-controlled: mis-train DDR, "
       "under-volt/over-clock the PS (a glitch primitive), or map memory adversarially — a big "
       "unauthenticated init surface ahead of the trust check.", "MED", "docs/14 STAGE1 (psu_init)"),

    _h("crypto-engine-residual", "asymmetric-protection", ["zynqmp"],
       lambda P: P.get("aes_encrypt"),
       "The FSBL EXPLICITLY resets the CSU AES/SHA engines at STAGE1 (init.c:294-295) because the "
       "BootROM 'may have left them active' — i.e. they can carry residual state across the boot stages.",
       "there is a window (BootROM→FSBL-reset) where the crypto engines may be usable with residual key/"
       "state; a fast attacker could drive the engine before the FSBL scrubs it.", "LOW",
       "docs/14 STAGE1 (init.c:294-295)"),

    # ---- board-broadening sweep (2026-08-14): the same implementation-review lens applied to the
    # non-ZynqMP families, so the Attack-Surface layer is not ZynqMP-only. Each grounded in the part's
    # documented security model (readout vs take-over asymmetry, alternate boot/access masters). ----
    _h("stm32-erase-takeover", "design-primitive", ["stm32f4", "stm32f1", "stm32l4"],
       lambda P: P.get("rdp_level") != 2,
       "STM32 RDP protects flash READ-OUT, but the RDP1→0 option-byte downgrade (a mass-erase) is an "
       "operator-reachable primitive that leaves a BLANK, fully-programmable device.",
       "RDP guards confidentiality, not integrity: a supply-chain or field attacker mass-erases and "
       "reflashes a trojaned image — the part takes the implant even though the original was 'protected'.",
       "MED", probe='openocd -f openocd/cortexm-stm32f4.cfg -c "init; source openocd/cortexm-access-check.tcl; shutdown"'),

    _h("nrf-ctrlap-takeover", "design-primitive", ["nrf52"],
       lambda P: True,
       "nRF52 CTRL-AP ERASEALL stays reachable even when APPROTECT blocks the AHB-AP — the recovery "
       "primitive is unauthenticated.",
       "APPROTECT protects secrecy, not authenticity: the always-available ERASEALL wipes + unlocks the "
       "device, so an attacker can take it over (blank + reflash a trojan) with no key.", "MED",
       probe='openocd -f openocd/cortexm-nrf52.cfg -c "init; source openocd/cortexm-access-check.tcl; shutdown"'),

    _h("esp32-dl-mode-oracle", "alternate-master", ["esp32"],
       lambda P: (P.get("flash_encrypted") or P.get("secure_boot")) and not P.get("secure_download"),
       "ESP32 UART download (DL) mode is an alternate access master to the flash-encryption engine; unless "
       "Secure Download Mode is fused, DL mode can still read/write flash through the device key.",
       "flash encryption assumes the key never leaves — but DL mode re-encrypts/decrypts with that key, "
       "an on-chip oracle reachable over UART that bypasses the 'can't read the plaintext' assumption.",
       "MED", ref="Espressif secure-download-mode advisory", probe="espefuse.py summary  # check DL-mode / FLASH_CRYPT_CNT"),

    _h("microsemi-preprovision-open", "asymmetric-protection", ["smartfusion2", "igloo2"],
       lambda P: not P.get("flashlock"),
       "Microsemi security (FlashLock pass-key / AES) is OPT-IN at programming time; before it is "
       "provisioned the standard JTAG programming TAP accepts unauthenticated eNVM/fabric read + write.",
       "an unprovisioned field device is fully open through the ordinary programming interface — no "
       "attack needed, the protection was simply never turned on (the common real-world state).", "MED",
       probe="# FlashPro Express → Inspect Device (IDCODE + security status: is FlashLock provisioned?)"),

    _h("riscv-dm-unauth", "design-primitive", ["riscv"],
       lambda P: not P.get("debug_authenticated"),
       "The RISC-V Debug Module (DM) has NO authentication in the base spec — `authenticated` is an "
       "optional feature many SoCs leave unimplemented (authbusy=0, authenticated=1 always).",
       "if the vendor didn't add an authentication module, a present DM is an unauthenticated full "
       "halt/mem/reg take-over primitive — debug security depends on an omitted optional block.", "MED",
       ref="RISC-V Debug Spec §3.12 (authentication optional)"),

    _h("stm32-clone-rdp-gap", "asymmetric-protection", ["gd32", "gd32f1", "gd32f4", "apm32", "ch32"],
       lambda P: True,
       "STM32-compatible clones (GD32, APM32, CH32) copy the RDP option-byte INTERFACE but not the "
       "genuine part's read-out hardening.",
       "the clone's readout protection has repeatedly fallen to reset-timing / partial-access quirks the "
       "authentic STM32 resists (protected flash dumped without the RDP1→0 mass-erase). Treat clone RDP as "
       "weaker than the datasheet's STM32-equivalent claim.", "HIGH", ref="PT SWARM 2024 (GD32)"),

    _h("jtag-idcode-recon", "asymmetric-protection", _ALL,
       lambda P: True,
       "Even a fully LOCKED chip answers IDCODE / BYPASS on the JTAG chain — the TAP state machine is "
       "below the debug-security gate.",
       "free reconnaissance: exact silicon + revision (and often the lock state) leak with zero access, "
       "so an attacker triages and picks the right lever before spending any effort. No posture removes "
       "this short of blowing the JTAG-disable fuse entirely.", "LOW",
       probe='openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"'),

    # ---- the authenticated-debug frontier (2026): hardened parts move from an on/off debug GATE to
    # challenge-response AUTHENTICATION (ARM CoreSight SDC-600 / RISC-V External Debug Security, ratified
    # 2025). posture key `debug_auth` ∈ {none (on/off gate), present (capable, cert NOT provisioned),
    # provisioned (cert/key enforced)}. These model the new trust boundary above "is the DAP shut?". ----
    _h("auth-debug-unprovisioned", "design-primitive", _ALL,
       lambda P: P.get("debug_auth") == "present",
       "The device implements authenticated debug (ARM SDC-600 secure debug channel / RISC-V debug-auth) "
       "but the debug certificate/key is NOT provisioned — authentication is opt-in and left off.",
       "an unprovisioned authenticated-debug device grants full invasive debug to anyone who connects — "
       "the exact failure mode as an unprovisioned FlashLock. The gate is decorative until a cert is "
       "actually enrolled.", "HIGH", ref="ARM SDC-600; RISC-V Ext Debug Security (ratified 2025)"),

    _h("debug-cert-trust", "trust-assumption", _ALL,
       lambda P: P.get("debug_auth") == "provisioned",
       "Authenticated debug (SDC-600 / debug certificates) trusts a debug credential signed by a vendor/"
       "fleet key.",
       "possession or leak of the debug signing key re-opens invasive debug across EVERY device that "
       "trusts it — security collapses to debug-key management, a fleet-wide single point of failure "
       "(and an insider/HSM-compromise target).", "MED", ref="ARM SDC-600 authenticated debug"),

    _h("secure-debug-noninvasive-leak", "asymmetric-protection", _ALL,
       lambda P: P.get("debug_auth") in ("present", "provisioned"),
       "Authenticated debug gates INVASIVE debug, but IDCODE / boundary-scan and often non-invasive debug "
       "(NIDEN / trace) remain answerable below the authenticated channel.",
       "recon (exact part + lock state) and trace/non-invasive leakage survive SDC-600 — the authenticated "
       "gate is not a full blackout, so fingerprinting and some observation continue unauthenticated.",
       "LOW", ref="ADIv6 / SDC-600 scope"),

    _h("open-dap-thesis", "thesis", _ALL,
       lambda P: P.get("jtag_open") and not P.get("efuse_jtag_dis"),
       "Project thesis: on an unprovisioned board the OPEN DAP *is* the trust boundary.",
       "every downstream 'security' register is attacker-controlled — halt/dump/patch a running auth "
       "check (Cap-1/2/3). The posture reduces to 'is the DAP shut?'.", "HIGH"),
]


def applies(h, soc):
    return h["socs"] is None or soc in h["socs"]


def finding_states(soc, P=None, source="asserted"):
    """{hid: {"state": "confirmed"|"asserted", "probe": bool}} for the hypotheses that FIRE for (soc, P).

    The verification honesty layer: `state` = 'confirmed' when the posture came from a LIVE capture
    (source='capture', or P carries _source='capture') — the silicon actually reads this way — vs
    'asserted' when it's a prediction from operator-supplied flags (verify on hardware). `probe` flags
    the hypotheses that carry a runnable investigation command to gather more evidence."""
    P = P or {}
    src = "confirmed" if (source == "capture" or P.get("_source") == "capture") else "asserted"
    out = {}
    for h in HYPOTHESES:
        if not applies(h, soc):
            continue
        try:
            fired = bool(h["observe"](P))
        except Exception:
            fired = False
        if fired:
            out[h["id"]] = {"state": src, "probe": bool(h.get("probe"))}
    return out


def misuse_findings(soc, P):
    """[(cls, sev, text, id, probe)] — implementation-review misuse hypotheses that fire for (soc, P).
    `probe` (may be '') is a command/script to investigate the hypothesis on a live target."""
    out = []
    P = P or {}
    for h in HYPOTHESES:
        if not applies(h, soc):
            continue
        try:
            fired = bool(h["observe"](P))
        except Exception:
            fired = False
        if fired:
            txt = f"{h['title']}  → misuse: {h['misuse']}"
            if h.get("ref"):
                txt += f"  [{h['ref']}]"
            out.append((h["cls"], h["sev"], txt, h["id"], h.get("probe", "")))
    return out
