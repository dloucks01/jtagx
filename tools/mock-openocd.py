#!/usr/bin/env python3
"""
mock-openocd.py — a drop-in mock of the `openocd` binary, so the WHOLE OpenOCD-backend command
surface can be rehearsed offline (the GUI console's `mdw`/`halt`/`scan`/`/dump`, the transport
layer's OpenOCD commands, and the locked-board reopen→verify loop). Point $OPENOCD at it:

    OPENOCD=$PWD/tools/mock-openocd.py python3 tools/transport-probe.py ...
    OPENOCD=$PWD/tools/mock-openocd.py   (in the GUI) → console `mdw 0x…`, `/dump`, `/verify`, `/unlock` run

It parses `openocd -f <cfg> -c "init; <cmds>; shutdown"` and emulates the command subset we emit:
  scan_chain · mdw <a> [n] · mww <a> <v> · halt · resume · dump_image <f> <a> <size>
  source openocd/<script>   → jtag-access-check.tcl / reopen-debug.tcl (STATEFUL: LOCKED→OPEN after
                              the lever) / enumerate.tcl (minimal) — the locked-board scenarios.

Scenarios via $JTAGX_MOCK_LOCK (default register-gated): register-gated→lever opens; efuse-sealed /
no-write-path→lever resists. State in $JTAGX_MOCK_STATE (default /tmp/jtagx-mock-lock.state; delete
to reset to LOCKED). Dumps capped at $JTAGX_MOCK_MAXBYTES (default 2 MiB) with a truncation banner.
REHEARSAL tool — real validation is G1/G2/G3 against silicon. Supersedes the old mock-openocd-locked.py.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_common import load_regs, reg_word, mem_bytes

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_GOLDEN_RAW = os.path.join(_REPO_ROOT, "tests", "golden", "zcu102-jtag-idle", "raw.json")

STATE = os.environ.get("JTAGX_MOCK_STATE", "/tmp/jtagx-mock-lock.state")
SCENARIO = os.environ.get("JTAGX_MOCK_LOCK", "register-gated")
MAXBYTES = int(os.environ.get("JTAGX_MOCK_MAXBYTES", str(2 * 1024 * 1024)))
REGS = load_regs()          # the newest capture's 153 real registers (faithful mdw/mrd)


def _state():
    try:
        return open(STATE).read().strip()
    except OSError:
        return "locked"


def _set(s):
    with open(STATE, "w") as f:
        f.write(s)


# ---- primitives ----
def scan_chain(out):
    out.append("   TapName             Enabled  IdCode     Expected   IrLen IrCap IrMask")
    out.append(" 0 zynqmp.tap             Y   0x24738093 0x14738093     12 0x01  0x03")
    out.append(" 1 zynqmp.dap             Y   0x5ba00477 0x5ba00477      4 0x01  0x0f")


def mdw(out, args):
    addr = int(args[0], 16) if args else 0
    n = int(args[1]) if len(args) > 1 else 1
    # openocd groups 4 words per line; values come from the real capture where known
    vals = [reg_word(REGS, addr + 4 * k) for k in range(n)]
    for i in range(0, n, 4):
        row = vals[i:i + 4]
        out.append(f"0x{addr + 4 * i:08x}: " + " ".join(f"{v:08x}" for v in row))


def enumerate_mock(out):
    """Emulate `source openocd/enumerate.tcl`: write a FRESH reports/raw-<ts>.json so anything
    downstream of a real enumerate (the GUI's post-decode cross-page flow, tools/interpret.py, the
    HTML report) has genuinely new data to react to — not just a no-op that leaves the exit code as
    the only observable signal. Content is the frozen golden capture (known-good, already validated
    by golden-test.sh) with a fresh timestamp; this is a REHEARSAL of the button/pipeline wiring, not
    a fidelity claim about the register values — real posture always comes from actual silicon."""
    out.append("# [mock-openocd] enumerate.tcl — writing a mock capture (rehearsal; not real silicon)")
    try:
        with open(_GOLDEN_RAW, encoding="utf-8") as fh:
            cap = json.load(fh)
    except OSError as e:
        out.append(f"# [mock-openocd] enumerate.tcl mock FAILED to read the golden fixture: {e}")
        return
    ts = time.strftime("%Y-%m-%d-%H%M%S")
    cap.setdefault("metadata", {})["timestamp"] = ts
    out_path = os.path.join("reports", f"raw-{ts}.json")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(cap, fh, indent=2)
    out.append(f"Raw JSON capture: {out_path}")
    out.append(f"# [mock-openocd] wrote {out_path} ({len(cap.get('registers', {}))} registers)")


def dump_image(out, args):
    path, addr = args[0], int(args[1], 16)
    size = int(args[2], 0)
    n = min(size, MAXBYTES)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(mem_bytes(REGS, addr, n))
    if n < size:
        out.append(f"# [mock-openocd] dumped {n} of {size} bytes to {path} "
                   f"(capped by JTAGX_MOCK_MAXBYTES={MAXBYTES}); real openocd writes the full range")
    else:
        out.append(f"dumped {n} bytes in 0.01s ({n} bytes/s)")


# ---- sourced scripts (locked-board scenarios) ----
def access_check(out):
    opened = _state() == "open"
    out.append("================================================================")
    out.append(f" ACCESS VERDICT: {'OPEN' if opened else 'LOCKED'}")
    out.append("================================================================")
    out.append("  DAP is powered, MEM-APs respond, and non-secure registers read back."
               if opened else
               "  JTAG chain present but the DAP will not answer even a DP read.")


def reopen_debug(out):
    out.append(" RE-OPEN DEBUG GATES  (software-hardened-target workflow)")
    out.append("JTAG_SEC          (0xFFCA0038) before = 0x00000000")
    if SCENARIO == "no-write-path":
        out.append(">> writing JTAG_SEC = 0x000001FF")
        out.append("    -> write FAULTED (no AXI-AP write path)")
        return
    out.append(">> writing JTAG_SEC = 0x000001FF")
    out.append("JTAG_SEC          after  = 0x000001FF")
    if SCENARIO == "efuse-sealed":
        out.append("    DAP_SEC   LOCKED  (ARM DAP link — gates A53/R5 core debug)")
        out.append("    -> DAP_SEC did NOT stick: eFuse-locked / write-protected (not reversible here)")
        return
    out.append("    DAP_SEC   OPEN    (ARM DAP link — gates A53/R5 core debug)")
    out.append("    -> all JTAG_SEC gates now OPEN")
    out.append("JTAG_DAP_CFG      (0xFFCA003C) after  = 0x000000FF")
    _set("open")


# cfg basename -> CM_PROT_KIND, mirroring each openocd/cortexm-<board>.cfg's `set CM_PROT_KIND ...`
CFG_FAMILY = {
    "cortexm-stm32f4.cfg": "stm32-rdp", "cortexm-stm32h7.cfg": "stm32-rdp", "cortexm-gd32.cfg": "stm32-rdp",
    "cortexm-stm32l4.cfg": "stm32l4", "cortexm-stm32f1.cfg": "stm32f1",
    "cortexm-nrf52.cfg": "nrf-approtect", "cortexm-nrf53.cfg": "nrf-approtect",
    "cortexm-samd5x.cfg": "sam-dsu", "cortexm-kinetis.cfg": "kinetis-fsec",
    "cortexm-rp2040.cfg": "none", "cortexm-lpc.cfg": "none", "cortexm-nrf54.cfg": "none",
}


def cortexm_protect_mock(out, cfg):
    """Emulate openocd/cortexm-protect.tcl's decoded output (jtagx.cortexm_posture parses this exact
    `"   %-22s %s"` / `" (N) TITLE"` format — same shape the real .tcl's `_p`/section echoes produce),
    so the GUI's board-generic Enumerate → measured-posture path is rehearsable with no MCU on the bench."""
    kind = CFG_FAMILY.get(os.path.basename(cfg or ""), "none")
    opened = _state() == "open"

    def sec(n, title):
        out.append(f" ({n}) {title}")

    def p(label, value):
        out.append(f"   {label:<22} {value}")

    out.append("")
    out.append("================================================================")
    out.append(f" CORTEX-M SECURITY POSTURE  (family: {kind})")
    out.append("================================================================")
    if kind in ("stm32-rdp", "stm32l4", "stm32f1"):
        sec(1, "IDENTITY")
        p("DBGMCU_IDCODE", "DEV_ID=0x413 (STM32F405/407/415/417)  REV_ID=0x1001")
        p("Unique device ID", "aabbccdd-11223344-55667788")
        p("Flash size", "1024 KB")
        sec(2, "READOUT PROTECTION")
        if kind == "stm32f1":
            p("RDPRT (FLASH_OBR bit 1)", "0 -> not protected, flash readable (dev)" if opened else
              "1 -> READ-PROTECTED (unlock = mass-erase WIPE)")
        else:
            label = "RDP" if kind == "stm32-rdp" else "RDP (FLASH_OPTR 7-0)"
            p(label, "0xaa -> LEVEL 0 — no protection, flash fully readable (dev)" if opened else
              "0x55 -> LEVEL 1 — flash blocked from the debugger; unlock = mass-erase (WIPES flash)")
    elif kind == "nrf-approtect":
        sec(1, "IDENTITY (FICR)")
        p("INFO.PART", "0x00052840 (e.g. 0x52840)")
        p("RAM / FLASH", "256 KB / 1024 KB")
        sec(2, "READOUT PROTECTION (UICR.APPROTECT @0x10001208)")
        p("APPROTECT", "0xffffffff -> OPEN (HwDisabled / factory) — AHB-AP unrestricted, flash dumpable"
          if opened else "0x0000ff00 -> ENABLED is the configured intent — a reset re-locks; only "
                          "re-open is a CTRL-AP mass-erase (WIPE)")
        sec(3, "DEBUG / OUTPUT")
        p("DEBUGCTRL", "0xffffffff (CPUNIDEN/CPUFPBEN; 0xFFFFFFFF = all debug allowed)")
    elif kind == "sam-dsu":
        sec(1, "IDENTITY")
        p("DSU.DID", "0x60060003 (FAMILY=0xc SERIES=0x0 DIE=0x0 REV=0x0 DEVSEL=0x03)")
        sec(2, "READOUT PROTECTION (DSU.STATUSB.PROT)")
        p("PROT", "0 -> open, debug + flash accessible (dev)" if opened else
          "1 -> DEBUG-ACCESS PROTECTED (NVMCTRL security bit set; only chip-erase removes it = WIPE)")
    elif kind == "kinetis-fsec":
        sec(1, "IDENTITY")
        p("SIM_SDID", "0x00000000 (FAMILYID=0x0 SUBFAMID=0x0 SERIESID=0x0 PINID=0x0 REVID=0x0)")
        sec(2, "FLASH SECURITY (FTFE_FSEC)")
        p("SEC (bits 1-0)", "0x2 -> UNSECURED (0b10) — flash readable (dev)" if opened else
          "0x3 -> SECURED (debug-port access limited; unlock = mass-erase WIPE)")
    else:   # none (rp2040 / lpc / nrf54 — CM_PROT_KIND=none, no fuse-based protection modeled)
        sec(1, "IDENTITY (SYSINFO)")
        p("CHIP_ID", "0x00000001  (PART=0x0000 REV=0x0 MANUF=0x000)")
        sec(2, "READOUT PROTECTION")
        p("On-chip protection", "NONE — no internal-flash readout-protection fuse modeled for this part.")
    out.append("================================================================")
    out.append(" NOTE: reading any of the above proves the AHB-AP is OPEN -> internal flash is dumpable now.")
    out.append("================================================================")


# ---- Cortex-M locked-board scenarios (nRF52 APPROTECT, STM32 RDP) — same state-file machine ----
def cm_access_check(out):
    opened = _state() == "open"
    out.append("================================================================")
    out.append(f" ACCESS VERDICT: {'OPEN' if opened else 'LOCKED'}")
    out.append("================================================================")
    out.append("  Cortex-M AHB-AP responds — halt + memory reads available."
               if opened else
               "  DAP answers but the AHB-AP is gated (APPROTECT / RDP>0 / debug-lock).")


def nrf_recover(out):
    out.append(" nRF52 CTRL-AP recovery (APPROTECT clear via ERASEALL)")
    if SCENARIO == "approtect-sealed":
        out.append(">> CTRL-AP ERASEALL = 1 ...")
        out.append("    -> erase FAILED: secure-APPROTECT / ACL blocks CTRL-AP (debug still locked)")
        return
    out.append(">> CTRL-AP ERASEALL = 1 ... polling ERASEALLSTATUS")
    out.append("    ERASEALL complete — APPROTECT cleared, debug re-enabled (FLASH ERASED)")
    _set("open")


def stm_rdp_downgrade(out):
    out.append(" STM32 RDP downgrade (option-byte RDP -> level 0, mass-erase)")
    if SCENARIO == "rdp2-sealed":
        out.append(">> reading option bytes ...")
        out.append("    -> RDP2 is permanent: cannot downgrade, debug still locked (FI-only)")
        return
    out.append(">> programming option bytes: RDP = 0xAA (level 0) ... mass-erase triggered")
    out.append("    RDP downgraded to level 0 — mass-erase complete, debug re-enabled (FLASH ERASED)")
    _set("open")


def kinetis_recover(out):
    out.append(" Kinetis MDM-AP mass-erase recovery (clears FTFE flash security)")
    if SCENARIO == "meen-disabled":
        out.append("    MDM-AP status = 0x00000004")
        out.append("    -> mass-erase DISABLED (FSEC.MEEN): debug still locked (permanent)")
        return
    out.append("    MDM-AP status = 0x00000024")
    out.append(">> MDM-AP Flash-Mass-Erase = 1 ... polling")
    out.append("    Kinetis MDM-AP mass-erase complete — flash security cleared, debug re-enabled (FLASH ERASED)")
    _set("open")


def samd_recover(out):
    out.append(" SAM D5x/E5x DSU chip-erase recovery (clears NVMCTRL debug protection)")
    if SCENARIO == "dsu-sealed":
        out.append("    -> chip-erase FAILED: DSU did not complete (debug still locked)")
        return
    out.append("    DSU.STATUSB.PROT (before) = 1")
    out.append("    SAMD DSU chip-erase complete — NVMCTRL security cleared, debug re-enabled (FLASH ERASED)")
    _set("open")


# ---- Microsemi fabric scenarios (IGLOO2): provisioning check + unprovisioned SVF readback ----
def ms_access_check(out):
    prov = SCENARIO == "provisioned"
    out.append("================================================================")
    out.append(f" ACCESS VERDICT: {'LOCKED' if prov else 'OPEN'}")
    out.append("================================================================")
    out.append("  FlashLock / pass-key provisioned — readback gated (DPA / FlashPro)."
               if prov else
               "  Unprovisioned — SVF/DirectC readback of eNVM + fabric bitstream works over this FTDI.")


def ms_readback(out):
    out.append(" Microsemi fabric readback (eNVM + bitstream via SVF/DirectC over FTDI)")
    if SCENARIO == "provisioned":
        out.append("    -> readback FAILED: FlashLock / pass-key provisioned (device still locked)")
        return
    out.append(">> device is UNPROVISIONED — readback path is OPEN.")
    out.append("    fabric readback available — export a VERIFY/READ SVF from Libero and re-run with MSS_SVF=<file>")


def run_source(out, script, cfg=""):
    if "jtag-access-check.tcl" in script:
        access_check(out)
    elif "microsemi-access-check.tcl" in script:
        ms_access_check(out)
    elif "microsemi-readback.tcl" in script:
        ms_readback(out)
    elif "cortexm-protect.tcl" in script:
        cortexm_protect_mock(out, cfg)
    elif "cortexm-access-check.tcl" in script:
        cm_access_check(out)
    elif "nrf52-recover.tcl" in script:
        nrf_recover(out)
    elif "stm32-rdp-downgrade.tcl" in script:
        stm_rdp_downgrade(out)
    elif "kinetis-recover.tcl" in script:
        kinetis_recover(out)
    elif "samd-recover.tcl" in script:
        samd_recover(out)
    elif "reopen-debug.tcl" in script:
        reopen_debug(out)
    elif "enumerate.tcl" in script:
        enumerate_mock(out)
    else:
        out.append(f"# [mock-openocd] sourced {script} (no-op)")


def run_c(out, body, cfg=""):
    for raw in re.split(r";|\n", body):
        c = raw.strip()
        if not c:
            continue
        toks = c.split()
        head = toks[0]
        if head in ("init", "shutdown", "reset", "resume"):
            if head == "resume":
                out.append("# [mock-openocd] resumed")
        elif head == "halt":
            out.append("# [mock-openocd] halted")
        elif head == "scan_chain":
            scan_chain(out)
        elif head == "mdw":
            mdw(out, toks[1:])
        elif head == "mww":
            out.append(f"# [mock-openocd] wrote {toks[2] if len(toks) > 2 else '?'} @ {toks[1] if len(toks) > 1 else '?'}")
        elif head == "dump_image":
            dump_image(out, toks[1:])
        elif head == "source":
            run_source(out, toks[1] if len(toks) > 1 else "", cfg)
        else:
            out.append(f"# [mock-openocd] (ignored) {c}")


def main():
    argv = sys.argv[1:]
    out = []
    cfg = argv[argv.index("-f") + 1] if "-f" in argv and argv.index("-f") + 1 < len(argv) else ""
    if "-c" in argv:
        # collect all -c bodies (openocd allows several)
        i = 0
        while i < len(argv):
            if argv[i] == "-c" and i + 1 < len(argv):
                run_c(out, argv[i + 1], cfg); i += 2
            else:
                i += 1
    print("\n".join(out))


if __name__ == "__main__":
    main()
