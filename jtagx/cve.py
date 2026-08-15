"""
jtagx.cve — the CVE / published-attack knowledge base + posture matcher.

Moved here (from tools/cve-match.py) so the CLI, engagement-report, and any GUI can share it.
Each DB entry says WHEN it applies (posture conditions); `cond_ok` returns True/False/None (unknown).
`posture_findings` is the project's own open-DAP thesis (posture → compromise) expressed as findings.
Posture keys: jtag_open, secure_boot, rdp_level, approtect_open, aes_encrypt, efuse_jtag_dis.
"""

DB = [
    # --- ZynqMP / Zynq-7000 (Xilinx/AMD) — docs/15 ---
    dict(id="CVE-2019-5478", chips=["zynqmp"], when={"secure_boot": "encrypt-only"}, sev="HIGH",
         title="ZynqMP encrypt-only secure-boot bypass (modify the unauthenticated boot header)",
         ref="Xilinx XSA / docs/15"),
    dict(id="CVE-2023-20570", chips=["zynqmp"], when={"secure_boot": True}, sev="HIGH",
         title="JustSTART — RSA-auth secure-boot bypass (unpatchable in silicon); boot a forged image",
         ref="docs/15; AMD-SB-1056"),
    dict(id="Starbleed", chips=["zynq7000"], when={"aes_encrypt": True}, sev="HIGH",
         title="Starbleed — 7-series PL bitstream AES-CBC malleability → decrypt the encrypted bitstream",
         ref="Ender/Moradi 2020; docs/15"),
    dict(id="Cautionary-GHASH", chips=["zynqmp"], when={"aes_encrypt": True}, sev="MED",
         title="AES-GCM IV/GHASH weakness in the boot AES (a cautionary-note class issue)", ref="docs/15"),
    dict(id="ZU+EM-SCA", chips=["zynqmp"], when={}, sev="MED",
         title="ZynqMP electromagnetic side-channel on the boot AES key (physical access)", ref="docs/15"),
    # --- Cortex-M MCUs — readout-protection bypasses (very real, widely published) ---
    dict(id="nRF52-APPROTECT-glitch", chips=["nrf52"], when={"approtect_open": False}, sev="HIGH",
         title="nRF52 APPROTECT bypass by a single voltage glitch at boot → re-enable debug, dump flash",
         ref="LimitedResults 2020"),
    dict(id="STM32-RDP1-downgrade", chips=["stm32f4", "stm32f1", "stm32l4"], when={"rdp_level": 1}, sev="HIGH",
         title="STM32 RDP-1→0 downgrade / cold-boot & glitch attacks to read protected flash (family-dependent)",
         ref="Obermaier/Tatschner; Johnson"),
    dict(id="Kinetis-MDM-erase", chips=["kinetis"], when={}, sev="MED",
         title="Kinetis MDM-AP secured-part recovery is a mass-erase; FSEC mis-config can leave debug open",
         ref="NXP AN; docs/15"),
    dict(id="SAMD-DSU-erase", chips=["samd5x"], when={}, sev="MED",
         title="SAM D5x/E5x DSU chip-erase clears NVMCTRL debug protection (mass-erase recovery over SWD)",
         ref="SAM D5x/E5x DS (DSU)"),
    # --- newer targets (2024–2026 published research) ---
    dict(id="GD32-RDP-bypass", chips=["gd32", "gd32f1", "gd32f4"], when={}, sev="HIGH",
         title="GigaDevice GD32 readout-protection bypass — STM32-clone RDP defeated by reset-timing / "
               "partial-access quirks the genuine STM32 isn't (dump protected flash)",
         ref="PT SWARM 2024 'GigaVulnerability'"),
    dict(id="nRF54-EMFI", chips=["nrf54", "nrf54l", "nrf54l15"], when={}, sev="HIGH",
         title="nRF54L15 electromagnetic fault injection — EMFI defeats the APPROTECT-successor debug gate",
         ref="SySS 2025"),
    # --- Microsemi/Microchip SmartFusion2 / IGLOO2 (Actel lineage) ---
    dict(id="Actel-JTAG-backdoor", chips=["smartfusion2", "igloo2"], when={}, sev="HIGH",
         title="Actel/Microsemi silicon JTAG backdoor + DPA pass-key extraction — recover FlashLock/AES key, "
               "then authorized readback (applies to the ProASIC3/SmartFusion lineage)",
         ref="Skorobogatov & Woods, 'Breakthrough silicon scanning' CHES 2012"),
    dict(id="SF2-M3-open-dump", chips=["smartfusion2"], when={"debug_locked": False}, sev="HIGH",
         title="SmartFusion2 Cortex-M3 debug NOT security-locked → OpenOCD cortex_m mem-AP dumps eNVM/eSRAM "
               "with a standard probe (J-Link/CMSIS-DAP), no FlashPro",
         ref="profiles/smartfusion2.json; openocd cortex_m"),
    # --- ESP32 — flash-encryption / secure-boot fault injection ---
    dict(id="CVE-2019-15894", chips=["esp32"], when={}, sev="HIGH",
         title="ESP32 fault-injection bypass of secure boot + flash encryption (UART DL mode)",
         ref="LimitedResults / Espressif advisory"),
    dict(id="ESP32-eFuse-glitch", chips=["esp32"], when={}, sev="MED",
         title="ESP32 eFuse / secure-boot-v1 glitch attacks; check flash-encryption mode with espefuse.py",
         ref="docs/15"),
]


def posture_findings(soc, P):
    """The project's own thesis: the open-DAP baseline = full compromise, expressed as findings."""
    out = []
    if P.get("jtag_open") and not P.get("efuse_jtag_dis"):
        out.append(("POSTURE", "HIGH", "JTAG/DAP is OPEN and not eFuse-disabled — full debug compromise: halt, "
                    "dump RAM/flash, patch a running auth check (Cap-1/2/3). The DAP *is* the trust boundary."))
    if soc in ("zynqmp", "zynq7000") and P.get("secure_boot") is False:
        out.append(("POSTURE", "HIGH", "Secure boot is OFF — the BootROM accepts an unsigned/unencrypted image. "
                    "repack-bootimage.py a patched BOOT.bin and reflash for a persistent implant."))
    if P.get("rdp_level") == 0:
        out.append(("POSTURE", "HIGH", "RDP level 0 — internal flash is fully readable AND writable. Dump the "
                    "firmware and reflash a patched image (cortexm-flash.tcl)."))
    if P.get("approtect_open"):
        out.append(("POSTURE", "HIGH", "APPROTECT is open — the AHB-AP is unrestricted: dump + reflash the nRF flash."))
    if soc in ("bcm",) and P.get("jtag_open"):
        out.append(("POSTURE", "MED", "Pi ARM-side debug open — RAM dump + live patch; secure-boot/OTP is VideoCore's."))
    return out


def applies(entry, soc):
    return soc in entry["chips"]


def cond_ok(entry, P):
    """True if every posture condition in entry['when'] holds; None if a needed fact is unknown."""
    if not entry["when"]:
        return True
    unknown = False
    for k, v in entry["when"].items():
        if k not in P:
            unknown = True
        elif P[k] != v:
            return False
    return None if unknown else True
