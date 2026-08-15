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
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_common import load_regs, reg_word, mem_bytes

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


def run_source(out, script):
    if "jtag-access-check.tcl" in script:
        access_check(out)
    elif "microsemi-access-check.tcl" in script:
        ms_access_check(out)
    elif "microsemi-readback.tcl" in script:
        ms_readback(out)
    elif "cortexm-access-check.tcl" in script:
        cm_access_check(out)
    elif "nrf52-recover.tcl" in script:
        nrf_recover(out)
    elif "stm32-rdp-downgrade.tcl" in script:
        stm_rdp_downgrade(out)
    elif "reopen-debug.tcl" in script:
        reopen_debug(out)
    elif "enumerate.tcl" in script:
        out.append("# [mock-openocd] enumerate.tcl — (mock no-op; use the real board for a capture)")
    else:
        out.append(f"# [mock-openocd] sourced {script} (no-op)")


def run_c(out, body):
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
            run_source(out, toks[1] if len(toks) > 1 else "")
        else:
            out.append(f"# [mock-openocd] (ignored) {c}")


def main():
    argv = sys.argv[1:]
    out = []
    if "-c" in argv:
        # collect all -c bodies (openocd allows several)
        i = 0
        while i < len(argv):
            if argv[i] == "-c" and i + 1 < len(argv):
                run_c(out, argv[i + 1]); i += 2
            else:
                i += 1
    print("\n".join(out))


if __name__ == "__main__":
    main()
