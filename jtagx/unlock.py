"""
jtagx.unlock — the Phase-2b unlock-engine CORE: the lock knowledge base + strategy ranking.

Moved here (from tools/unlock-engine.py) so both the CLI (`tools/unlock-engine.py`, now a thin
wrapper) and the GUI ("Reopen / Unlock" panel) import the same logic. Given a chip + a posture dict,
`build_plan(soc, P)` classifies each engaged lock's enforcement and returns ranked defeat strategies.

Ranking (cheapest/safest/most-reliable first):
  software-lever → misconfig → alternate-path → physical-offline → firmware-attack → fault-injection → side-channel
"""

# strategy kinds, ranked (lower = try first). Drives ordering + the GUI's "auto-try then guide" flow.
KIND_RANK = {
    "software-lever": 0,   # write a register to reopen — AUTO, non-destructive, the free win
    "misconfig":      1,   # exploit a partial-lock gap already present
    "alternate-path": 2,   # reach via PMU / BSCAN / boundary-scan when the DAP is shut
    "physical-offline": 3, # direct flash read / chip-off — no JTAG needed
    "firmware-attack": 4,  # JustSTART / Starbleed / downgrade against a captured image
    "fault-injection": 5,  # glitch the security check — hardware
    "side-channel":   6,   # SCA/DPA key recovery — hardware
}
KIND_TAG = {
    "software-lever": "AUTO",   "misconfig": "AUTO",     "alternate-path": "SCRIPT",
    "physical-offline": "MANUAL", "firmware-attack": "OFFLINE", "fault-injection": "HARDWARE",
    "side-channel": "HARDWARE",
}


def strat(kind, title, how, confidence="med", destructive=False, prereq="", ref=""):
    return dict(kind=kind, title=title, how=how, confidence=confidence,
                destructive=destructive, prereq=prereq, ref=ref)


# ---- lock knowledge base: each function returns a Lock dict (or None if not engaged / N/A) ----------
def lock_dap(soc, P):
    if soc not in ("zynqmp", "zynq7000", "bcm", "imx6", "am335x", "sama5"):
        return None
    st = P.get("jtag_open")
    if st is True:
        return dict(name="JTAG / DAP debug gate", state="OPEN", enforcement="n/a", strategies=[],
                    note="DAP already open — no unlock needed (this is the easy baseline).")
    if st is None and "jtag_locked" not in P:
        return None  # nothing said about the DAP
    efuse = P.get("efuse_jtag_dis")   # True=sealed, False=register-gated, None=unknown
    S = []
    if efuse is not True:
        S.append(strat("software-lever", "Write the debug-enable gate open",
            "openocd/reopen-debug.tcl (ZynqMP CSU JTAG_SEC / JTAG_DAP_CFG / debug-enable; Zynq-7000: "
            "devcfg.CTRL DAP_EN+DBGEN) then read back. Works UNLESS an eFuse froze it.",
            confidence="high" if efuse is False else "med", destructive=False,
            prereq="gate is register-writable (SEC_CTRL.jtag_dis == 0)"))
    S.append(strat("alternate-path", "Reach the PMU via its BSCAN TAP (alternate master)",
        "openocd/open-pmu-tap.tcl opens JTAG_SEC.SSSS_PMU_SEC (writable ⇒ unsealed); pair zcu102-3tap.cfg "
        "to insert the MicroBlaze BSCAN TAP → a master that reaches ROM/bus the DAP can't.",
        confidence="med", destructive=False, prereq="PMU_SEC gate not eFuse-sealed", ref="open-pmu-tap.tcl"))
    S.append(strat("alternate-path", "Boundary-scan the pins (EXTEST/SAMPLE)",
        "Even a gated debug DAP often leaves IEEE-1149.1 boundary-scan alive. Parse the part's BSDL: "
        "`tools/bsdl-scan.py part.bsdl --sample-plan` -> run the SAMPLE capture -> `--decode 0x<cap>` "
        "for per-pin states (read straps/mode/bus pins; EXTEST to drive). Works when the DAP is fully shut.",
        confidence="low", destructive=False, prereq="BSDL for the part", ref="tools/bsdl-scan.py"))
    S.append(strat("physical-offline", "Dump the external boot flash directly (bypass JTAG)",
        "SOIC-8 clip + flashrom on the QSPI/eMMC boot chip → get the image with no JTAG at all, then "
        "attack it offline. Frequently the fastest win on a locked board.",
        confidence="high", destructive=False, prereq="physical access to the boot-flash chip"))
    if efuse is not False:
        S.append(strat("fault-injection", "Glitch the CSU eFuse-read / secure-boot decision at boot",
            "voltage/EM/clock glitch (ChipWhisperer / PicoEMP) on the CSU security check to skip the "
            "eFuse JTAG-disable — checkm8-model. NOT yet integrated (needs glitcher + trigger).",
            confidence="low", destructive=False, prereq="glitch rig; eFuse-sealed JTAG", ref="docs/13"))
    enf = ("eFuse-sealed (HARDWARE — not software-reversible)" if efuse is True
           else "software-register (REVERSIBLE — try the lever first)" if efuse is False
           else "UNKNOWN — read SEC_CTRL.jtag_dis/dft_dis to classify (this decides everything)")
    return dict(name="JTAG / DAP debug gate", state="LOCKED", enforcement=enf, strategies=S)


def lock_dap_ns(soc, P):
    if soc not in ("zynqmp", "zynq7000") or not P.get("dap_ns_locked"):
        return None
    return dict(name="DAP non-secure (NS) access", state="LOCKED",
                enforcement="software-register unless SEC_CTRL-locked",
                strategies=[strat("software-lever", "Re-enable NS DAP access",
                    "write JTAG_DAP_CFG to permit non-secure access, then re-probe the AP. If secure-only "
                    "debug is set but not eFuse-frozen, this reopens the mem-AP.",
                    confidence="med", destructive=False, prereq="not eFuse-locked")])


def lock_secureboot(soc, P):
    sb = P.get("secure_boot")
    if soc not in ("zynqmp", "zynq7000") or sb in (False, None):
        return None
    S = [
        strat("physical-offline", "Dump the (possibly encrypted) boot flash directly",
            "SOIC clip + flashrom → the image; encryption/auth is then an OFFLINE problem, not a live gate.",
            confidence="high", destructive=False, prereq="physical flash access"),
    ]
    if sb == "encrypt-only" and soc == "zynqmp":
        S.append(strat("firmware-attack", "CVE-2019-5478 — encrypt-only boot-header bypass",
            "modify the UNAUTHENTICATED boot header of the encrypted image to redirect execution.",
            confidence="med", destructive=False, ref="docs/15; XSA"))
    if sb is True and soc == "zynqmp":
        S.append(strat("firmware-attack", "JustSTART (CVE-2023-20570) — RSA-auth bypass",
            "bypass RSA authentication on the UltraScale(+) config engine to boot a forged image "
            "(unpatchable in silicon). Repack a trojanized BOOT.bin.",
            confidence="med", destructive=False, ref="docs/15; AMD-SB-1056"))
    S.append(strat("fault-injection", "Glitch the RSA/HMAC auth decision in the CSU BootROM",
        "FI on the authenticate/decrypt branch to force accept of an unsigned image. Hardware; not integrated.",
        confidence="low", destructive=False, prereq="glitch rig", ref="docs/13"))
    return dict(name=f"Secure boot ({'RSA-auth' if sb is True else sb})", state="ENABLED",
                enforcement="BootROM + eFuse (hardware root of trust)", strategies=S)


def lock_aes(soc, P):
    if not P.get("aes_encrypt") or soc not in ("zynqmp", "zynq7000"):
        return None
    S = []
    if soc == "zynq7000":
        S.append(strat("firmware-attack", "Starbleed — 7-series bitstream AES-CBC malleability",
            "decrypt the encrypted PL bitstream via the config engine's CBC malleability.",
            confidence="med", destructive=False, ref="Ender/Moradi 2020; docs/15"))
    if soc == "zynqmp":
        S.append(strat("firmware-attack", "Cautionary-Note / GHASH weakness on the boot AES-GCM",
            "IV/GHASH reuse class issue against the boot AES; defeats the auth path when encrypt-only.",
            confidence="low", destructive=False, ref="docs/15"))
    S.append(strat("side-channel", "EM/power side-channel on the boot AES key (recover the key)",
        "ZU+ EM-SCA: capture traces during boot decryption, DPA to recover the AES key → decrypt offline. "
        "Hardware (EM probe + scope); not integrated.",
        confidence="low", destructive=False, prereq="EM probe + oscilloscope", ref="docs/15"))
    return dict(name="Boot AES encryption", state="ENABLED",
                enforcement="eFuse/BBRAM key (hardware)", strategies=S)


def lock_pmu(soc, P):
    if soc != "zynqmp" or not P.get("pmu_sec_locked"):
        return None
    writable = P.get("pmu_sec_writable")
    S = [strat("alternate-path", "Open the PMU BSCAN TAP",
        "openocd/open-pmu-tap.tcl writes JTAG_SEC.SSSS_PMU_SEC (0b111); read-back reports writable "
        "(unsealed) vs sealed. If writable, zcu102-3tap.cfg inserts the MicroBlaze BSCAN TAP.",
        confidence="high" if writable else "med", destructive=False,
        prereq="PMU_SEC not eFuse-sealed", ref="open-pmu-tap.tcl")]
    return dict(name="PMU security gate (PMU_SEC)", state="LOCKED",
                enforcement="software-register" if writable else "eFuse-sealed" if writable is False else "UNKNOWN",
                strategies=S)


def lock_runtime(soc, P):
    if not P.get("runtime_lock"):
        return None
    return dict(name="Runtime JTAG lock (firmware disables JTAG post-boot)", state="LOCKED",
                enforcement="runtime (software, per-boot)",
                strategies=[
                    strat("alternate-path", "Reach the PMU before firmware locks JTAG",
                        "the PMU/CSU path may stay open; or a debug lever applied in the pre-lock window.",
                        confidence="low", destructive=False),
                    strat("fault-injection", "Glitch/race the lock instruction",
                        "FI or a timing race to skip the firmware's JTAG-disable write. Hardware.",
                        confidence="low", destructive=False, prereq="glitch rig / tight timing")])


# --- general Cortex-M / ESP unlock levers (breadth, mirroring cve-match) ---
def lock_nrf(soc, P):
    if soc != "nrf52" or not P.get("approtect_locked"):
        return None
    return dict(name="nRF52 APPROTECT (AHB-AP blocked)", state="LOCKED", enforcement="UICR (flash) — glitchable",
                strategies=[
                    strat("fault-injection", "Single voltage glitch at boot re-enables debug",
                        "the classic nRF52 APPROTECT bypass: one well-timed VCC glitch during the boot "
                        "APPROTECT read → AHB-AP open → dump flash. (ChipWhisperer.)",
                        confidence="high", destructive=False, ref="LimitedResults 2020"),
                    strat("misconfig", "CTRL-AP mass-erase (recovers debug, WIPES flash)",
                        "if you only need debug (not the current flash): CTRL-AP ERASEALL clears APPROTECT.",
                        confidence="high", destructive=True)])


def lock_stm(soc, P):
    if soc not in ("stm32f4", "stm32f1", "stm32l4") or P.get("rdp_level") in (None, 0):
        return None
    lvl = P.get("rdp_level")
    S = []
    if lvl == 1:
        S += [strat("fault-injection", "RDP1 read-out bypass by glitch / cold-boot",
                  "family-dependent FI (e.g. glitch the RDP check on a flash read) to read protected flash "
                  "without the RDP1→0 mass-erase.", confidence="med", ref="Obermaier/Tatschner; Johnson"),
              strat("misconfig", "RDP1→0 downgrade (mass-erase, WIPES flash)",
                  "recovers debug + write, destroys current flash — only if you don't need the contents.",
                  confidence="high", destructive=True)]
    if lvl == 2:
        S.append(strat("fault-injection", "RDP2 is FI-only",
            "RDP2 permanently disables debug + boundary options; published attacks are all fault-injection.",
            confidence="low"))
    return dict(name=f"STM32 RDP level {lvl}", state="LOCKED",
                enforcement="option bytes (RDP1 downgradable; RDP2 sealed)", strategies=S)


def lock_esp(soc, P):
    if soc != "esp32" or not (P.get("secure_boot") or P.get("flash_encrypted")):
        return None
    return dict(name="ESP32 secure-boot / flash-encryption", state="ENABLED", enforcement="eFuse (glitchable v1)",
                strategies=[strat("fault-injection", "CVE-2019-15894 — FI bypass via UART download mode",
                    "fault-inject the secure-boot/flash-enc check (UART DL mode) to run/read unencrypted. "
                    "Check the mode first with espefuse.py summary.",
                    confidence="med", ref="LimitedResults / Espressif")])


LOCK_FUNCS = [lock_dap, lock_dap_ns, lock_secureboot, lock_aes, lock_pmu, lock_runtime,
              lock_nrf, lock_stm, lock_esp]


def build_plan(soc, P):
    locks = []
    for f in LOCK_FUNCS:
        L = f(soc, P)
        if L:
            L["strategies"] = sorted(L.get("strategies", []), key=lambda s: KIND_RANK.get(s["kind"], 9))
            locks.append(L)
    return locks


def render_md(soc, P, locks):
    engaged = [L for L in locks if L["state"] in ("LOCKED", "ENABLED")]
    auto = sum(1 for L in engaged for s in L["strategies"] if s["kind"] in ("software-lever", "misconfig"))
    out = [f"# Unlock plan — {soc}", ""]
    out.append(f"posture: {P or '(none given)'}")
    if not engaged:
        out.append("\n**No engaged locks in the given posture** — either the board is OPEN (baseline) or "
                   "you haven't fed the lock facts yet. Feed `--jtag-locked` / `--secure-boot on` etc.")
        return "\n".join(out)
    out.append(f"\n**Objective: UNLOCK.** {len(engaged)} mechanism(s) engaged; "
               f"{auto} auto-tryable software lever(s) — try those FIRST.\n")
    for L in engaged:
        out.append(f"## {L['name']} — {L['state']}")
        out.append(f"- **enforcement:** {L['enforcement']}")
        if not L["strategies"]:
            out.append("- (no strategy — see note)")
        for s in L["strategies"]:
            d = "  ⚠DESTRUCTIVE" if s["destructive"] else ""
            pq = f"  · prereq: {s['prereq']}" if s["prereq"] else ""
            rf = f"  · ref: {s['ref']}" if s["ref"] else ""
            out.append(f"- **[{KIND_TAG.get(s['kind'],'?'):8}]** ({s['confidence']}){d}  {s['title']}")
            out.append(f"      {s['how']}{pq}{rf}")
        out.append("")
    out.append("---\nRanking: software-lever → misconfig → alternate-path → physical-offline → "
               "firmware-attack → fault-injection → side-channel (cheapest/safest first).")
    return "\n".join(out)
