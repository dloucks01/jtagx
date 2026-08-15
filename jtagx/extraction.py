"""
jtagx.extraction — the per-board EXTRACTION method model.

The capability matrix answers "can this adapter run a mem-AP read?"; this answers the fuller question
"what are ALL the real ways to get memory/flash OFF this board, ranked, and what does each need?". It
adds the paths the mem-AP model misses: dumping the external boot flash off-board, and the vendor
BootROM loaders (i.MX SDP, Atmel SAM-BA, TI RBL, Espressif esptool/download-mode, RP2040 BOOTROM) that
extract WITHOUT the debug port — a second, non-glitch avenue when the DAP is gated or absent.

    from jtagx.extraction import extraction_plan, render_md
    for m in extraction_plan("imx6", {"jtag_open": True}, profile): ...

All methods here are NON-physical-rig (JTAG, a vendor loader over USB/UART, or a SOIC clip); glitch /
side-channel stay in jtagx.unlock as ranked strategies and are deferred.
"""

# per-family vendor BootROM loader — a documented extraction/inject path independent of the debug DAP.
# (name, how, prereq, non_destructive, cmd) — cmd is a representative RUNNABLE command (operator edits
# the device path / size / applet for the exact part).
ROM_LOADER = {
    "imx6":   ("i.MX Serial Download Protocol (SDP)",
               "hold BOOT_MODE=serial → the BootROM enumerates as USB HID; imx_usb/uuu load a small U-Boot "
               "over USB, then dump eMMC/NAND/QSPI from the U-Boot prompt. Reads/writes DRAM directly.",
               "BOOT_MODE straps to serial-download; USB", True,
               "uuu -b spl u-boot.imx   # then at the U-Boot prompt: sf probe; sf read 0x82000000 0 0x400000; "
               "then dump DDR via SDP  (or: imx_usb u-boot.imx)"),
    "am335x": ("TI ROM peripheral boot (UART/USB RBL)",
               "strap to UART/USB boot → the ROM Boot Loader accepts an SPL over xmodem/RNDIS; load a "
               "dumper SPL to read eMMC/NAND/SPI.",
               "sysboot straps to peripheral boot", True,
               "# strap UART boot; sx <dumper-spl.bin> over /dev/ttyUSB0 (xmodem), or usb-rndis + tftp"),
    "sama5":  ("Microchip SAM-BA monitor",
               "the on-chip ROM SAM-BA monitor (USB/UART) reads and writes any memory directly; dump "
               "SRAM/DDR and drive the external NAND/QSPI.",
               "SAM-BA monitor enabled (no valid boot / erase the boot flash)", True,
               "sam-ba -p serial -d sama5d2 -a serialflash -c read:flash.bin:0:0x100000"),
    "esp32":  ("Espressif UART download mode (esptool)",
               "hold GPIO0 low → download mode; esptool read_flash dumps SPI flash. Plaintext if "
               "flash-encryption is OFF; if ON, DL mode reads ciphertext (device re-encrypts/decrypts with "
               "its key unless Secure-Download-Mode is fused).",
               "download-mode strap; Secure-Download-Mode NOT fused for plaintext", True,
               "esptool.py -p /dev/ttyUSB0 -b 460800 read_flash 0 0x400000 flash.bin"),
    "rp2040": ("RP2040 BOOTROM (BOOTSEL / PICOBOOT)",
               "hold BOOTSEL → USB mass-storage/PICOBOOT; picotool dumps the external QSPI flash. No "
               "on-die readout protection to defeat.",
               "BOOTSEL strap; USB", True,
               "picotool save -a flash.bin"),
    "bcm":    ("Broadcom bootloader / SD image",
               "Pi-class parts boot from SD/eMMC — pull the card or dump eMMC directly; the VPU boot "
               "chain has no readout gate on the application flash.",
               "physical access to SD/eMMC", True,
               "dd if=/dev/mmcblk0 of=sd.img bs=4M   # (card in a reader), or usbboot for eMMC"),
}


def _cfg(profile):
    return (profile or {}).get("openocd_cfg") or "openocd/<cfg>.cfg"


def _m(method, how, needs, access, needs_debug, non_destructive=True, cmd=""):
    # access: jtag (cable) | rom-loader (cable+strap) | readback (vendor TAP) | chip-off (physical)
    return dict(method=method, how=how, needs=needs, access=access,
                needs_debug=needs_debug, non_destructive=non_destructive, cmd=cmd)


def extraction_plan(soc, P=None, profile=None):
    """Ordered method dicts — the real extraction avenues for this board, best-first. `access` says how
    reachable each is (jtag/rom-loader/readback = a cable; chip-off = physical); `needs_debug` gates the
    debug-port ones. The ROM-loader / readback / chip-off paths do NOT need the debug DAP."""
    profile = profile or {}
    m = []

    # 1. mem-AP / CPU dump over the debug port — richest when debug is OPEN (or openable).
    try:
        from .transport.matrix import route_op
        row, reason = route_op(profile, "mem_read")
    except Exception:
        row, reason = (None, "capability matrix unavailable")
    if row is not None:
        m.append(_m("mem-AP dump (debug port)",
                    f"{reason}; or the profile's dump.dram/flash → tools/dump-triage.py",
                    "debug OPEN (reopen it first if locked)", "jtag", True))

    # 2. profile-declared dump scripts (dram/flash) — the wired, board-specific dumpers.
    dump = profile.get("dump") or {}
    for which in ("dram", "flash"):
        d = dump.get(which)
        if d and d.get("script"):
            m.append(_m(f"{which} dump ({d.get('script')})", d.get("note", "profile dump script"),
                        "debug OPEN", "jtag", True,
                        cmd=f"openocd -f {profile.get('openocd_cfg','<cfg>')} -c \"init; source "
                            f"{d.get('script')}; shutdown\""))

    # 3. vendor BootROM loader — extracts WITHOUT the debug DAP (the second avenue).
    if soc in ROM_LOADER:
        name, how, prereq, nd, cmd = ROM_LOADER[soc]
        m.append(_m(name, how, prereq, "rom-loader", False, nd, cmd=cmd))

    # 4. fabric/CPU-less readback (Microsemi) — SVF/DirectC or FlashPro.
    if soc in ("igloo2", "smartfusion2"):
        m.append(_m("Microsemi programming-TAP readback",
                    "unprovisioned: SVF/DirectC over a plain FTDI (openocd/microsemi-readback.tcl); "
                    "provisioned: FlashPro/Libero readback or DPA pass-key first.",
                    "security not provisioned (else DPA/FlashPro)", "readback",
                    needs_debug=True,   # gated on the access being open (unprovisioned), like debug
                    cmd='openocd -f openocd/microsemi-fpga.cfg -c "init; source openocd/microsemi-readback.tcl; shutdown"'))

    # 5. external boot-flash off-board — always available with physical access, bypasses everything.
    m.append(_m("external boot-flash off-board",
                "SOIC-8 clip + flashrom on the QSPI/SPI-NOR, or an eMMC/NAND reader; get the image with "
                "no JTAG at all, then analyze offline (parse-bootimage / secureboot-analyze / firmware-id).",
                "physical access to the flash chip", "chip-off", False))

    for i, d in enumerate(m):
        d["rank"] = i + 1
    return m


def best_cable(plan, debug_open):
    """The top method reachable over a CABLE right now (no chip-off): a debug-port dump if debug is open,
    else a ROM-loader / readback path. Returns the method dict, or None (only chip-off remains)."""
    for d in plan:
        if d["access"] == "chip-off":
            continue
        if d["needs_debug"] and not debug_open:
            continue
        return d
    return None


def render_md(soc, plan):
    L = [f"# Extraction plan — {soc}", "",
         "Every real way to get memory/flash off this board, best-first. ROM-loader / readback / "
         "chip-off paths do NOT need the debug port (a second avenue when the DAP is gated).", ""]
    for d in plan:
        tags = [d["access"]]
        if not d["non_destructive"]:
            tags.append("⚠destructive")
        L.append(f"{d['rank']}. **{d['method']}**  ({', '.join(tags)})")
        L.append(f"   - {d['how']}")
        L.append(f"   - needs: {d['needs']}")
        if d.get("cmd"):
            L.append(f"   - run: `{d['cmd']}`")
    return "\n".join(L)
