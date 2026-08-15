"""
jtagx.unlock — the Phase-2b unlock-engine CORE: the lock knowledge base + strategy ranking.

Moved here (from tools/unlock-engine.py) so both the CLI (`tools/unlock-engine.py`, now a thin
wrapper) and the GUI ("Reopen / Unlock" panel) import the same logic. Given a chip + a posture dict,
`build_plan(soc, P)` classifies each engaged lock's enforcement and returns ranked defeat strategies.

Ranking (cheapest/safest/most-reliable first):
  software-lever → misconfig → alternate-path → physical-offline → firmware-attack → fault-injection → side-channel
"""
import os

# the openocd binary the generated lever/verify commands invoke — overridable ($OPENOCD) so a mock
# (tools/mock-openocd-locked.py) can stand in and the whole reopen→verify loop is rehearsable offline.
_OPENOCD = os.environ.get("OPENOCD", "openocd")

# Cortex-M boards reachable by a standard probe → their per-family OpenOCD cfg (real files in openocd/).
# Drives the board-aware verify command (cortexm-access-check.tcl) and the runnable recovery levers.
_CM_CFG = {
    "nrf52": "cortexm-nrf52.cfg",
    "stm32f4": "cortexm-stm32f4.cfg",
    "stm32f1": "cortexm-stm32f1.cfg",
    "stm32l4": "cortexm-stm32l4.cfg",
    "kinetis": "cortexm-kinetis.cfg",
    "samd5x": "cortexm-samd5x.cfg",
    "smartfusion2": "cortexm.cfg",
}

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


def strat(kind, title, how, confidence="med", destructive=False, prereq="", ref="", cmd="", verify=""):
    # cmd (optional): a directly-runnable command for AUTO levers (the GUI can execute it).
    # verify (optional): how to confirm the lever WORKED — "access-check" re-runs the DAP verdict
    # after the lever so the guided workflow can mark the lock DEFEATED / RESISTED (not just "ran").
    return dict(kind=kind, title=title, how=how, confidence=confidence,
                destructive=destructive, prereq=prereq, ref=ref, cmd=cmd, verify=verify)


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
        _cfg = {"zynqmp": "zcu102.cfg", "zynq7000": "zynq7000.cfg"}.get(soc)
        _scr = {"zynqmp": "reopen-debug.tcl", "zynq7000": "zynq7000-reopen-debug.tcl"}.get(soc)
        _cmd = (f'{_OPENOCD} -f openocd/{_cfg} -c "init; source openocd/{_scr}; shutdown"'
                if _cfg and _scr else "")
        S.append(strat("software-lever", "Write the debug-enable gate open",
            "openocd/reopen-debug.tcl (ZynqMP CSU JTAG_SEC / JTAG_DAP_CFG / debug-enable; Zynq-7000: "
            "devcfg.CTRL DAP_EN+DBGEN) then read back. Works UNLESS an eFuse froze it.",
            confidence="high" if efuse is False else "med", destructive=False,
            prereq="gate is register-writable (SEC_CTRL.jtag_dis == 0)", cmd=_cmd,
            verify="access-check" if _cmd else ""))
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
    _cmd = (f'{_OPENOCD} -f openocd/cortexm-nrf52.cfg '
            f'-c "init; source openocd/nrf52-recover.tcl; shutdown"')
    return dict(name="nRF52 APPROTECT (AHB-AP blocked)", state="LOCKED", enforcement="UICR (flash) — glitchable",
                strategies=[
                    strat("misconfig", "CTRL-AP mass-erase (recovers debug, WIPES flash)",
                        "if you only need debug (not the current flash): CTRL-AP ERASEALL clears APPROTECT and "
                        "re-opens the AHB-AP. Runnable + verified here (the guided loop re-reads the debug "
                        "verdict after). Secure-APPROTECT (nRF52840 ACL) can still block this.",
                        confidence="high", destructive=True, cmd=_cmd, verify="access-check"),
                    strat("fault-injection", "Single voltage glitch at boot re-enables debug",
                        "the classic nRF52 APPROTECT bypass: one well-timed VCC glitch during the boot "
                        "APPROTECT read → AHB-AP open → dump flash WITHOUT erasing. (ChipWhisperer.)",
                        confidence="high", destructive=False, ref="LimitedResults 2020")])


def lock_stm(soc, P):
    if soc not in ("stm32f4", "stm32f1", "stm32l4") or P.get("rdp_level") in (None, 0):
        return None
    lvl = P.get("rdp_level")
    _cfg = _CM_CFG.get(soc)
    _cmd = (f'{_OPENOCD} -f openocd/{_cfg} -c "init; source openocd/stm32-rdp-downgrade.tcl; shutdown"'
            if _cfg else "")
    S = []
    if lvl == 1:
        S += [strat("misconfig", "RDP1→0 downgrade (mass-erase, WIPES flash)",
                  "recovers debug + write, destroys current flash — only if you don't need the contents. "
                  "Runnable + verified here: writes RDP=0 to the option bytes, the chip mass-erases, and the "
                  "guided loop re-reads the debug verdict to confirm the DAP re-opened.",
                  confidence="high", destructive=True, cmd=_cmd, verify="access-check"),
              strat("fault-injection", "RDP1 read-out bypass by glitch / cold-boot (keeps flash)",
                  "family-dependent FI (e.g. glitch the RDP check on a flash read) to read protected flash "
                  "without the RDP1→0 mass-erase.", confidence="med", ref="Obermaier/Tatschner; Johnson")]
    if lvl == 2:
        S.append(strat("fault-injection", "RDP2 is FI-only",
            "RDP2 permanently disables debug + boundary options; published attacks are all fault-injection.",
            confidence="low"))
    return dict(name=f"STM32 RDP level {lvl}", state="LOCKED",
                enforcement="option bytes (RDP1 downgradable; RDP2 sealed)", strategies=S)


def lock_kinetis(soc, P):
    # NXP Kinetis FTFE flash security: FSEC.SEC gates the debug port; the MDM-AP mass-erase command
    # clears it (destructive) — a debug-mailbox recovery, NOT a glitch. Unless FSEC.MEEN disables it.
    if soc != "kinetis" or not P.get("flash_secured"):
        return None
    meen_off = P.get("meen_disabled")
    _cmd = (f'{_OPENOCD} -f openocd/cortexm-kinetis.cfg '
            f'-c "init; source openocd/kinetis-recover.tcl; shutdown"')
    S = []
    if not meen_off:
        S.append(strat("misconfig", "MDM-AP mass-erase (recovers debug, WIPES flash)",
            "FTFE flash-security (FSEC.SEC) blocks the SWD/JTAG debug port, but the Kinetis MDM-AP "
            "mass-erase command clears the security bit and re-opens debug — no glitch. Runnable + verified "
            "here (the guided loop re-reads the debug verdict). Only when FSEC.MEEN doesn't disable it.",
            confidence="high", destructive=True, cmd=_cmd, verify="access-check",
            ref="K64 RM FTFE_FSEC + MDM-AP mass-erase"))
    else:
        S.append(strat("physical-offline", "Mass-erase DISABLED (FSEC.MEEN) — permanently locked",
            "FSEC.MEEN=0b10 disables the MDM-AP mass-erase, so there is no destructive OR non-destructive "
            "debug recovery over JTAG. Escalate: chip-off, or fault-injection on the security check (deferred).",
            confidence="low", destructive=False, prereq="chip-off / FI rig"))
    S.append(strat("physical-offline", "Dump external boot flash directly (bypass JTAG)",
        "SOIC clip + flashrom on any EXTERNAL flash; on-die secured flash still needs erase/FI.",
        confidence="med", destructive=False, prereq="external flash present"))
    return dict(name="Kinetis FTFE flash security (FSEC)", state="LOCKED",
        enforcement=("flash-security register — MDM-AP mass-erase recovers debug (destructive)"
                     if not meen_off else
                     "flash-security + FSEC.MEEN mass-erase-disable (PERMANENT — no JTAG recovery)"),
        strategies=S)


def lock_samd(soc, P):
    # Microchip SAM D5x/E5x: the NVMCTRL security bit sets DSU.STATUSB.PROT, gating debug; the DSU
    # chip-erase (CE) command clears it (destructive). Debug-mailbox recovery, NOT a glitch.
    if soc != "samd5x" or not P.get("debug_protected"):
        return None
    _cmd = (f'{_OPENOCD} -f openocd/cortexm-samd5x.cfg '
            f'-c "init; source openocd/samd-recover.tcl; shutdown"')
    return dict(name="SAM D5x/E5x DSU debug protection (NVMCTRL security)", state="LOCKED",
        enforcement="NVMCTRL security bit (DSU.STATUSB.PROT) — DSU chip-erase recovers debug (destructive)",
        strategies=[
            strat("misconfig", "DSU chip-erase (recovers debug, WIPES flash)",
                "the NVMCTRL security bit gates the debug port (DSU.STATUSB.PROT=1), but the DSU chip-erase "
                "(CE) command clears it and re-opens SWD — no glitch. Runnable + verified here.",
                confidence="high", destructive=True, cmd=_cmd, verify="access-check",
                ref="SAM D5x/E5x DS — DSU/NVMCTRL"),
            strat("physical-offline", "Chip-off (decap + microprobe)",
                "SAMD5x flash is on-die; chip-off is slow, high-skill, destructive to the package.",
                confidence="low", destructive=True)])


def lock_esp(soc, P):
    if soc != "esp32" or not (P.get("secure_boot") or P.get("flash_encrypted")):
        return None
    return dict(name="ESP32 secure-boot / flash-encryption", state="ENABLED", enforcement="eFuse (glitchable v1)",
                strategies=[strat("fault-injection", "CVE-2019-15894 — FI bypass via UART download mode",
                    "fault-inject the secure-boot/flash-enc check (UART DL mode) to run/read unencrypted. "
                    "Check the mode first with espefuse.py summary.",
                    confidence="med", ref="LimitedResults / Espressif")])


def lock_sf2_debug(soc, P):
    if soc != "smartfusion2" or not P.get("debug_locked"):
        return None
    return dict(name="SmartFusion2 M3 debug lock (security policy)", state="LOCKED",
        enforcement="security-policy flash-cell set at programming — NOT runtime-reopenable "
                    "(re-program via FlashPro, or permanent if one-time-locked)",
        strategies=[
            strat("alternate-path", "Boundary-scan the pins (DAP shut ≠ 1149.1 shut)",
                "the M3 CoreSight DAP is gated but IEEE-1149.1 boundary-scan/IDCODE usually still answer — parse "
                "the part BSDL (`tools/bsdl-scan.py`) to read straps/pins/bus. Maps the surface; won't dump eNVM.",
                confidence="low", ref="tools/bsdl-scan.py"),
            strat("physical-offline", "FlashPro 'Inspect Device' for the security state",
                "FlashPro Express → Inspect Device reads the device security status (what's locked / readback "
                "gating). Confirms whether DPA or chip-off is the required next lever.",
                confidence="med", prereq="FlashPro + physical access"),
            strat("side-channel", "DPA pass-key recovery (Skorobogatov/Woods) → authorized readback",
                "the classic Actel/Microsemi result: differential power analysis of the JTAG security check "
                "recovers the FlashLock/AES pass-key; FlashPro readback of eNVM is then authorized. SCA rig.",
                confidence="med", ref="Skorobogatov & Woods, CHES 2012"),
            strat("fault-injection", "Glitch the System-Controller security decision at boot",
                "voltage/EM glitch the SC security-policy check so the M3 DAP re-enables — SmartFusion2 SC boot "
                "is the target. Hardware; not integrated.", confidence="low", ref="docs/13"),
            strat("firmware-attack", "Re-program a policy that leaves M3 debug open (needs FlashPro)",
                "if re-programmable (not permanently locked), write a security policy with M3 debug enabled — "
                "erases the current image.", confidence="high", destructive=True,
                prereq="FlashPro + policy not permanently locked")])


def lock_sf2_flashlock(soc, P):
    if soc != "smartfusion2" or not P.get("flashlock"):
        return None
    return dict(name="SmartFusion2 FlashLock / eNVM readback protection", state="ENABLED",
        enforcement="pass-key + optional AES (flash security)",
        strategies=[
            strat("alternate-path", "M3 mem-AP dump — IF debug is not locked",
                "if the M3 debug lock is NOT set, the Cortex-M mem-AP reads eNVM/eSRAM directly (openocd cortex_m) "
                "with a standard probe — no FlashPro, no pass-key. Check the debug lock first.",
                confidence="high", prereq="M3 debug not locked", ref="openocd/cortexm-dump.tcl"),
            strat("side-channel", "DPA pass-key recovery → authorized eNVM readback",
                "same DPA lever — recover the pass-key, then FlashPro/Libero eNVM readback is authorized.",
                confidence="med", ref="Skorobogatov & Woods, CHES 2012"),
            strat("physical-offline", "Chip-off eNVM (decap + microprobe)",
                "when readback is fully gated, physically extract eNVM. Slow, high skill, destructive to package.",
                confidence="low", destructive=True)])


def lock_igloo2(soc, P):
    # IGLOO2 = SmartFusion2's FABRIC-ONLY sibling: a Microsemi programming TAP, NO Cortex-M, so there is
    # NO mem-AP dump shortcut — readback is vendor-tool (FlashPro/Libero) gated by FlashLock.
    if soc != "igloo2" or not P.get("flashlock"):
        return None
    _rbcmd = (f'{_OPENOCD} -f openocd/microsemi-fpga.cfg '
              f'-c "init; source openocd/microsemi-readback.tcl; shutdown"')
    return dict(name="IGLOO2 FlashLock / eNVM+fabric readback protection", state="ENABLED",
        enforcement="pass-key + optional AES (flash security); NO Cortex-M — programming-TAP readback",
        strategies=[
            strat("misconfig", "SVF/DirectC readback of an UNPROVISIONED device (no FlashPro)",
                "if FlashLock/pass-key/AES was never provisioned, the standard programming TAP reads eNVM "
                "+ fabric bitstream via SVF/DirectC over a plain FTDI — no FlashPro, no pass-key. The guided "
                "flow checks provisioning (microsemi-access-check) then reads back if OPEN. This is the "
                "common real-world state: security is opt-in and frequently left off.",
                confidence="high", destructive=False, cmd=_rbcmd, verify="access-check",
                ref="openocd/microsemi-readback.tcl"),
            strat("physical-offline", "FlashPro 'Inspect Device' for the security state",
                "FlashPro Express → Inspect Device reads IDCODE + device/security status. If FlashLock/"
                "pass-key/AES is NOT provisioned, eNVM + fabric bitstream readback may be possible here.",
                confidence="high", prereq="FlashPro / Libero"),
            strat("side-channel", "DPA pass-key recovery (Skorobogatov/Woods) → authorized readback",
                "the classic Actel/Microsemi result: DPA of the JTAG security check recovers the FlashLock/"
                "AES pass-key; FlashPro/Libero readback of eNVM/bitstream is then authorized. SCA rig.",
                confidence="med", ref="Skorobogatov & Woods, CHES 2012"),
            strat("firmware-attack", "Re-program a device with security open (DESTRUCTIVE, FlashPro)",
                "if re-programmable (not permanently locked), program a bitstream/eNVM with security off — "
                "destroys the current image; only useful if you don't need the contents.",
                confidence="med", destructive=True, prereq="FlashPro; policy not permanently locked"),
            strat("alternate-path", "Boundary-scan the pins (SVF/STAPL + BSDL over generic FTDI)",
                "no CPU/mem bus, but IEEE-1149.1 EXTEST/SAMPLE over a raw FTDI reads/drives pins; play "
                "Microsemi SVF/STAPL to (re)program. `tools/bsdl-scan.py`.",
                confidence="low", ref="tools/bsdl-scan.py"),
            strat("physical-offline", "Chip-off eNVM (decap + microprobe)",
                "when readback is fully gated, physically extract eNVM. Slow, high skill, destructive.",
                confidence="low", destructive=True)])


LOCK_FUNCS = [lock_dap, lock_dap_ns, lock_secureboot, lock_aes, lock_pmu, lock_runtime,
              lock_nrf, lock_stm, lock_kinetis, lock_samd, lock_esp,
              lock_sf2_debug, lock_sf2_flashlock, lock_igloo2]


def build_plan(soc, P):
    locks = []
    for f in LOCK_FUNCS:
        L = f(soc, P)
        if L:
            L["strategies"] = sorted(L.get("strategies", []), key=lambda s: KIND_RANK.get(s["kind"], 9))
            locks.append(L)
    return locks


# A representative "everything provisioned" posture per SoC — used to enumerate the lock mechanisms a
# silicon CAN present (its security MODEL) when we have no live capture yet (e.g. a board just selected
# in the GUI, posture still UNKNOWN). This is NOT a claim the board is locked — it answers "what stands
# between an attacker and extraction on this part, and is each mechanism reversible or hardware-sealed?".
_ENGAGE_POSTURE = {
    "zynqmp":       {"jtag_locked": True, "secure_boot": True, "aes_encrypt": True, "pmu_sec_locked": True},
    "zynq7000":     {"jtag_locked": True, "secure_boot": True, "aes_encrypt": True},
    "smartfusion2": {"debug_locked": True, "flashlock": True},
    "igloo2":       {"flashlock": True},
    "nrf52":        {"approtect_locked": True},
    "stm32f4":      {"rdp_level": 1},
    "stm32f1":      {"rdp_level": 1},
    "stm32l4":      {"rdp_level": 1},
    "kinetis":      {"flash_secured": True},
    "samd5x":       {"debug_protected": True},
    "esp32":        {"secure_boot": True, "flash_encrypted": True},
}


def security_model(soc):
    """The lock mechanisms this silicon CAN present (posture-independent), each with its enforcement
    class + ranked defeat strategies. Empty for parts we haven't modeled a lock for (open-debug SoCs).
    Feeds the GUI's board-generic Posture view when there is no live capture yet."""
    return build_plan(soc, _ENGAGE_POSTURE.get(soc, {}))


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


# ============================================================================================
# Guided-workflow engine: run a lever → VERIFY it worked → mark the lock defeated / resisted.
# The lever writes registers; the verify RE-READS the access verdict. These parsers + the
# classifier turn "the command ran" into "the lock is actually open", which is the whole point
# of a locked-board engagement. Pure functions — the GUI/CLI run the commands, this reads results.
# ============================================================================================
import re as _re

_VERDICT_RE = _re.compile(r"ACCESS VERDICT:\s*([A-Z][A-Z-]*)")
# reopen-debug.tcl outcome markers, most-specific first
_REOPEN_MARKERS = [
    (r"all JTAG_SEC gates now OPEN", "REOPENED"),
    (r"DAP_SEC opened", "PARTIAL-EFUSE"),      # core debug back; PMU field eFuse-locked (usually fine)
    (r"DAP_SEC did NOT stick", "SEALED"),      # eFuse / write-protected — not reversible by register write
    (r"write FAULTED|no AXI-AP", "NO-WRITE-PATH"),
    # Cortex-M mass-erase recoveries (nRF CTRL-AP ERASEALL, STM32 RDP1→0, Kinetis MDM-AP mass-erase,
    # SAMD DSU chip-erase): debug re-opened, flash WIPED.
    (r"APPROTECT cleared|ERASEALL complete|RDP downgraded to level 0|mass-erase complete|chip-erase complete",
     "ERASED-OPEN"),
    # Microsemi fabric (IGLOO2) readback of an unprovisioned device — eNVM/bitstream extractable.
    (r"fabric readback complete|readback path is OPEN|fabric readback available", "READBACK-OPEN"),
    (r"readback FAILED|erase FAILED|RDP2 is permanent|debug still (locked|disabled)", "SEALED"),
]


def parse_access_verdict(text):
    """Extract the ACCESS VERDICT (OPEN/RESTRICTED/LOCKED/NO-DAP/NO-CHAIN/UNKNOWN) from access-check output."""
    m = _VERDICT_RE.search(text or "")
    return m.group(1) if m else "UNKNOWN"


def parse_reopen_result(text):
    """Classify reopen-debug.tcl output: REOPENED / PARTIAL-EFUSE / SEALED / NO-WRITE-PATH / UNKNOWN."""
    t = text or ""
    for pat, outcome in _REOPEN_MARKERS:
        if _re.search(pat, t):
            return outcome
    return "UNKNOWN"


# workflow status for a lock after a lever+verify attempt
WF_STATUS = {
    "ENGAGED":  ("engaged",   "#e7b04b", "not tried yet"),
    "DEFEATED": ("defeated",  "#3ecf8e", "gate re-opened — access restored"),
    "PARTIAL":  ("partial",   "#5aa9e6", "core debug re-opened; a PMU/eFuse field stayed locked (usually fine)"),
    "RESISTED": ("resisted",  "#f2685f", "eFuse-sealed / no write path — escalate (glitch / offline / code-exec)"),
    "MANUAL":   ("manual",    "#b58bff", "no auto lever — follow the ranked strategies"),
}


def classify_reopen(reopen_outcome, verdict_after):
    """(status, message) from a lever's reopen-outcome + the post-lever access verdict.
    The authoritative signal is the verdict; the reopen-outcome adds the 'why'."""
    if reopen_outcome == "ERASED-OPEN":
        return "DEFEATED", ("debug re-enabled via mass-erase (flash CONTENTS ERASED — you have debug "
                            "access, not the original image)")
    if reopen_outcome == "READBACK-OPEN":
        return "DEFEATED", ("unprovisioned fabric — eNVM + bitstream read back via SVF/DirectC over a "
                            "plain FTDI (no FlashPro, no pass-key)")
    if verdict_after == "OPEN":
        return "DEFEATED", "access verdict flipped to OPEN — lock defeated"
    if reopen_outcome == "REOPENED":
        return "DEFEATED", "all JTAG_SEC gates report OPEN (re-run enumerate to confirm)"
    if reopen_outcome == "PARTIAL-EFUSE":
        return "PARTIAL", WF_STATUS["PARTIAL"][2]
    if reopen_outcome in ("SEALED", "NO-WRITE-PATH"):
        return "RESISTED", WF_STATUS["RESISTED"][2]
    if verdict_after in ("LOCKED", "RESTRICTED", "NO-DAP"):
        return "RESISTED", f"verdict still {verdict_after} after the lever — escalate"
    return "ENGAGED", "inconclusive — re-read the verdict"


def verify_cmd(soc, openocd=None):
    """The command that RE-READS the access verdict after a lever (for verify='access-check' strats).
    ZynqMP/Zynq-7000 use jtag-access-check.tcl; Cortex-M boards (nRF/STM32/SF2) use the generic
    cortexm-access-check.tcl (AHB-AP reachable? → OPEN/LOCKED). Board-aware so the guided reopen→verify
    loop works for every board with a runnable lever, not just ZynqMP."""
    oc = openocd or _OPENOCD
    cfg = {"zynqmp": "zcu102.cfg", "zynq7000": "zynq7000.cfg"}.get(soc)
    if cfg:
        return f'{oc} -f openocd/{cfg} -c "init; source openocd/jtag-access-check.tcl; shutdown"'
    cmcfg = _CM_CFG.get(soc)
    if cmcfg:
        return f'{oc} -f openocd/{cmcfg} -c "init; source openocd/cortexm-access-check.tcl; shutdown"'
    if soc == "igloo2":     # fabric part: "access" = is the eNVM/bitstream readback path open (unprovisioned)?
        return f'{oc} -f openocd/microsemi-fpga.cfg -c "init; source openocd/microsemi-access-check.tcl; shutdown"'
    return ""


def workflow_steps(soc, locks):
    """Turn a plan into an ORDERED guided workflow: engaged locks (cheapest-first), each with its
    primary auto lever (if any), a verify command, and the fallback strategies. The GUI walks this."""
    steps = []
    engaged = [L for L in locks if L["state"] in ("LOCKED", "ENABLED")]
    for L in engaged:
        strats = L.get("strategies", [])
        auto = next((s for s in strats if s.get("cmd")), None)
        vcmd = verify_cmd(soc) if (auto and auto.get("verify") == "access-check") else ""
        steps.append({
            "lock": L["name"],
            "enforcement": L["enforcement"],
            "status": "ENGAGED" if auto else "MANUAL",
            "lever": auto,                       # the runnable strategy (or None → MANUAL)
            "verify_cmd": vcmd,
            "fallbacks": [s for s in strats if s is not auto],
        })
    return steps
