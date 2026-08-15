"""
firstcontact.py — the "wrong adapter / no chain blocked me" solver.

A structured knowledge base of every way first contact with an unknown board can
dead-end, each with: the SYMPTOM the operator observes, the likely CAUSES, how to
DETECT which one it is, and the concrete FIX. Plus diagnose() — feed it what you
see ("no idcode", "sticky error", "flashpro") and it ranks the candidate blockers.

This is the codified version of the field lesson that motivated Phase 3: on a real
engagement a FlashPro4 and another adapter blocked the operator outright because
the toolkit only spoke OpenOCD and gave no path forward. Every blocker here names
the way OUT, not just the failure.

Pure/offline: no USB traffic, no hardware. The GUI/CLI render it; preflight cites it.
Stages roughly follow the order you hit them bringing up an unknown board.
"""
from __future__ import annotations

import re

# Stage ordering — the sequence in which these blockers are normally encountered.
STAGES = [
    "adapter",      # is an adapter even present + usable by our backends
    "wiring",       # physical: connector, Vref, power, TRST/SRST
    "chain",        # JTAG scan: IDCODE / IR length / multi-TAP
    "dap",          # DAP/AP responds (power-up acks, sticky errors)
    "target",       # target state: held in reset, re-locks, boot straps
    "policy",       # security policy: JTAG disabled by eFuse
]

# Each blocker: id, stage, symptom, causes[], detect[], fix[], severity.
BLOCKERS = [
    # --- Stage: adapter -----------------------------------------------------
    {
        "id": "no-adapter",
        "stage": "adapter",
        "symptom": "No JTAG/SWD adapter detected at all (lsusb shows nothing relevant).",
        "causes": ["adapter not plugged", "VM did not pass the USB device through",
                   "missing udev rule / no libusb permission", "kernel grabbed the FTDI as a serial port"],
        "detect": ["`lsusb` — is the VID:PID there?",
                   "in VMware: VM > Removable Devices — is the adapter attached to the guest?",
                   "`dmesg | tail` after plugging — did it enumerate?"],
        "fix": ["VMware/VirtualBox: attach the USB device to the GUEST (the #1 Kali-in-VM blocker)",
                "install a udev rule granting your user access (plugdev), then replug",
                "if it appears as ttyUSBx and OpenOCD can't claim it, unbind ftdi_sio (see ftdi-sio-conflict)"],
        "severity": "block",
    },
    {
        "id": "proprietary-adapter",
        "stage": "adapter",
        "symptom": "Adapter is present but OpenOCD can't drive it (FlashPro / SmartLynq / Platform Cable).",
        "causes": ["adapter is a vendor-proprietary programmer, not a generic JTAG cable",
                   "FlashPro (FP3/4/5) is FTDI silicon wrapped in proprietary Microsemi firmware",
                   "SmartLynq / Platform Cable USB II speak the Xilinx hw_server protocol, not OpenOCD"],
        "detect": ["match the USB VID:PID (jtagx.transport.detect): 1514:* = FlashPro, 03fd:* = Xilinx",
                   "OpenOCD errors with 'unable to open ftdi device' or wrong IDCODEs despite a good cable"],
        "fix": ["FlashPro → use the Microsemi/Microchip backend: FlashPro Express (program/verify) or the "
                "SoftConsole-bundled PATCHED OpenOCD; on Linux unbind ftdi_sio first (see ftdi-sio-conflict)",
                "SmartLynq / Platform Cable → use the AMD hw_server + xsdb backend (Vitis), not OpenOCD",
                "if you only need enumeration, borrow a generic FTDI/CMSIS-DAP/J-Link cable and wire it to "
                "the target's JTAG header directly — the proprietary cable is only needed for its vendor flow"],
        "severity": "block",
    },
    {
        "id": "ftdi-sio-conflict",
        "stage": "adapter",
        "symptom": "FTDI adapter enumerates as /dev/ttyUSBx and OpenOCD reports it busy / cannot claim it.",
        "causes": ["the kernel ftdi_sio serial driver bound all channels of the FT2232H/FT4232H"],
        "detect": ["`ls /dev/ttyUSB*` shows the adapter's channels", "`lsmod | grep ftdi_sio`"],
        "fix": ["unbind the JTAG channel: `echo <bus>-<port>:1.0 > /sys/bus/usb/drivers/ftdi_sio/unbind`",
                "or add a udev rule that stops ftdi_sio binding interface 0 (PRODUCT/interface match)",
                "this is the SAME fix that lets a FlashPro's FTDI silicon be driven by a patched OpenOCD"],
        "severity": "block",
    },
    # --- Stage: wiring ------------------------------------------------------
    {
        "id": "no-vref",
        "stage": "wiring",
        "symptom": "Adapter drives, but the target never responds; TCK/TMS look dead on a scope.",
        "causes": ["no target reference voltage (VTREF) — level shifters see no target rail",
                   "wrong I/O voltage (1.8 V target vs 3.3 V adapter)",
                   "target not powered / in a low-power state"],
        "detect": ["measure VTREF pin on the header (should equal the target I/O rail: 1.8 / 2.5 / 3.3 V)",
                   "adapters that DON'T sense Vref (cheap FT2232 modules) happily drive 3.3 V into a 1.8 V part"],
        "fix": ["power the target; confirm VTREF is present and matches the target I/O voltage",
                "use a Vref-sensing adapter or a level shifter for 1.8 V parts",
                "NEVER drive 3.3 V JTAG into a 1.8 V-only target — it can damage the pin"],
        "severity": "block",
    },
    {
        "id": "wrong-connector",
        "stage": "wiring",
        "symptom": "Cannot find/identify the debug header, or the cable physically doesn't fit.",
        "causes": ["unknown/nonstandard header pinout",
                   "Arm 20-pin (0.1\") vs Cortex 10-pin (0.05\" 1.27mm) vs Xilinx 14-pin PL vs TI 14/20-pin"],
        "detect": ["count pins + pitch; look for a keyed/ground pattern; check the board silkscreen/schematic",
                   "beep out TCK/TMS/TDI/TDO/GND/VTREF with a multimeter to a known test point"],
        "fix": ["map the pinout: Arm 20-pin (0.1\"), Arm Cortex 10/20-pin (1.27mm SWD+JTAG), "
                "Xilinx 14-pin PL JTAG, TI 14/20-pin — use the right adapter cable/adapter board",
                "for a bare/unlabeled header, identify GND (continuity to shield) and VTREF first, "
                "then TCK/TMS/TDI/TDO by boundary-scan or a logic analyzer"],
        "severity": "block",
    },
    # --- Stage: chain -------------------------------------------------------
    {
        "id": "no-idcode",
        "stage": "chain",
        "symptom": "JTAG scan returns all-ones or all-zeros — no IDCODE, no chain.",
        "causes": ["wiring (see no-vref / wrong-connector)", "TRST held asserted (chain in reset)",
                   "clock too fast for the trace (see clock-too-high)", "TDI/TDO swapped"],
        "detect": ["`openocd ... -c 'scan_chain'` / discover.tcl — 0x00000000 or 0xFFFFFFFF = no device",
                   "swap-test: try TDI<->TDO; try a much slower adapter speed"],
        "fix": ["drop adapter speed to 100–500 kHz and rescan (see clock-too-high)",
                "check TRST/SRST wiring and reset_config; try `reset_config none` first",
                "verify TDI/TDO orientation and GND/VTREF (wiring stage)"],
        "severity": "block",
    },
    {
        "id": "clock-too-high",
        "stage": "chain",
        "symptom": "Intermittent/garbage IDCODEs; works at low speed, fails when sped up.",
        "causes": ["adapter clock exceeds what the trace/target can follow (RC of long jumpers)"],
        "detect": ["it scans clean at 100–500 kHz but corrupts at MHz speeds"],
        "fix": ["start at `adapter speed 100`, confirm a stable chain, then raise gradually",
                "shorten jumper wires; use adaptive clocking (RTCK) if the target supports it",
                "once stable, the cfg's `adapter speed` can be raised for faster enumeration"],
        "severity": "degraded",
    },
    {
        "id": "unexpected-chain",
        "stage": "chain",
        "symptom": "A chain is seen but the IDCODEs / IR lengths don't match expectation.",
        "causes": ["multi-TAP daisy chain (extra TAPs: PL TAP, PMU BSCAN, a second device)",
                   "wrong IR length in the cfg", "a different silicon revision / part than assumed"],
        "detect": ["compare scanned IDCODEs to the expected profile (board-runner --idcodes / discover.tcl)",
                   "ZynqMP: only the PS TAP is visible until the CSU finishes boot; PMU TAP appears only "
                   "when its eFuse policy allows"],
        "fix": ["declare EVERY TAP in the chain with correct IR lengths (position matters)",
                "use board-runner.py to fingerprint the chain and pick the right profile",
                "if a TAP is expected but missing, its gate may be closed (policy stage)"],
        "severity": "degraded",
    },
    # --- Stage: dap ---------------------------------------------------------
    {
        "id": "dap-powered-down",
        "stage": "dap",
        "symptom": "Chain/IDCODE OK, but AP access errors or the DAP won't power up.",
        "causes": ["debug power domain down (CDBGPWRUPREQ/ack not completing)",
                   "sticky error latched in the DP CTRL/STAT", "debug clock/reset gated (see ZynqMP DBG_LPD_CTRL)"],
        "detect": ["DP CTRL/STAT: CDBGPWRUPACK / CSYSPWRUPACK not set", "OpenOCD 'JTAG-DP STICKY ERROR'"],
        "fix": ["request debug power (OpenOCD does this on init; a manual `dap dpreg 0x4 0x50000000` sets the req bits)",
                "clear sticky errors (ABORT / read RDBUFF) and retry",
                "on ZynqMP confirm the LPD debug clock/reset gates (DBG_LPD_CTRL.CLKACT / RST_LPD_DBG)"],
        "severity": "block",
    },
    # --- Stage: target ------------------------------------------------------
    {
        "id": "target-wedges",
        "stage": "target",
        "symptom": "Debug attaches, but the moment firmware runs the CPU/DAP wedges or re-locks.",
        "causes": ["firmware re-asserts readout protection / disables debug at boot",
                   "the part re-locks each power cycle (nRF52 rev3+, some STM32)",
                   "boot-mode straps run code that hangs the bus"],
        "detect": ["debug works right after reset but dies once code executes",
                   "power-cycle returns it to locked"],
        "fix": ["connect-under-reset: hold SRST, TRST the TAPs, halt at the reset vector BEFORE instruction 1 "
                "(`reset_config srst_only connect_assert_srst`) — the canonical way in for parts that wedge",
                "change boot-mode straps to a non-booting / prompt mode so no firmware runs",
                "for re-locking parts, keep the session attached; re-attach requires the under-reset entry again"],
        "severity": "block",
    },
    {
        "id": "reset-polarity",
        "stage": "target",
        "symptom": "SRST/TRST behave inverted, or reset never releases / never asserts.",
        "causes": ["nSRST polarity or open-drain vs push-pull mismatch (the classic 'NRST looks inverted' bug)",
                   "SRST gates JTAG on this target but reset_config says otherwise"],
        "detect": ["scope nSRST during `reset`; compare to reset_config", "target resets when it shouldn't (or won't)"],
        "fix": ["set `reset_config` correctly: `srst_open_drain` vs `srst_push_pull`, `srst_gates_jtag` vs `srst_nogate`",
                "if only SRST is wired, `reset_config srst_only`; if neither, `reset_config none` and rely on TAP reset"],
        "severity": "degraded",
    },
    # --- Stage: policy ------------------------------------------------------
    {
        "id": "jtag-disabled",
        "stage": "policy",
        "symptom": "No DAP / no debug despite perfect wiring — the part's JTAG is disabled by policy.",
        "causes": ["eFuse JTAG-disable blown (ZynqMP JTAG_DIS / DFT_DIS; vendor equivalents)",
                   "secure-boot policy gates the DAP until an authenticated image runs"],
        "detect": ["chain may still show the PS TAP but the DAP/AP is dead and cannot be powered",
                   "matches a hardened-part posture, not a wiring fault"],
        "fix": ["if eFuse-disabled, JTAG is permanently off — no software lever (the unlock engine will say so)",
                "if policy-gated, debug may open only after an authenticated boot / via a debug-auth certificate",
                "fall back to non-debug extraction: vendor ROM loader (SDP/SAM-BA/esptool) or boundary-scan"],
        "severity": "block",
    },
]

_BY_ID = {b["id"]: b for b in BLOCKERS}

# Keyword → blocker-id hints for diagnose().
_KEYWORDS = {
    "no-adapter": ["no adapter", "not detected", "nothing detected", "lsusb", "passthrough",
                   "not plugged", "removable devices"],
    "proprietary-adapter": ["flashpro", "smartlynq", "platform cable", "libero", "microsemi",
                            "microchip", "proprietary", "vendor cable", "hw_server"],
    "ftdi-sio-conflict": ["ttyusb", "ftdi_sio", "busy", "cannot claim", "in use", "serial"],
    "no-vref": ["vref", "vtref", "no voltage", "1.8", "3.3", "dead", "no response", "level shift"],
    "wrong-connector": ["connector", "header", "pinout", "pins", "doesn't fit", "pitch", "10-pin", "20-pin"],
    "no-idcode": ["no idcode", "all ones", "all zeros", "0xffffffff", "0x00000000", "no chain", "scan"],
    "clock-too-high": ["clock", "speed", "intermittent", "garbage", "corrupt", "khz", "mhz", "rtck"],
    "unexpected-chain": ["ir length", "multi-tap", "daisy", "wrong idcode", "extra tap", "unexpected"],
    "dap-powered-down": ["sticky", "powerup", "cdbgpwrup", "ap error", "dap", "power domain"],
    "target-wedges": ["wedge", "re-lock", "relock", "hangs", "halts on run", "connect under reset", "reset vector"],
    "reset-polarity": ["srst", "trst", "nrst", "inverted", "reset", "polarity", "open drain"],
    "jtag-disabled": ["disabled", "efuse", "jtag_dis", "locked", "secure boot", "no dap", "permanently"],
}


def blocker(bid: str) -> dict | None:
    return _BY_ID.get(bid)


def by_stage(stage: str = None) -> list:
    """All blockers, or those for one stage, in encounter order."""
    if stage is None:
        return list(BLOCKERS)
    return [b for b in BLOCKERS if b["stage"] == stage]


def diagnose(symptom: str, limit: int = 3) -> list:
    """Rank blockers by keyword overlap with a free-text symptom. Returns the top
    `limit` as (score, blocker) — highest first. Empty symptom → the full ordered
    tree (score 0)."""
    s = (symptom or "").lower()
    if not s.strip():
        return [(0, b) for b in BLOCKERS]
    scored = []
    for bid, kws in _KEYWORDS.items():
        # score = curated-keyword hits. Keywords are distinctive multi-char phrases,
        # so no id-word bonus is needed (it over-matched generic words like 'adapter').
        score = sum(1 for kw in kws if kw in s)
        if score:
            scored.append((score, _BY_ID[bid]))
    scored.sort(key=lambda x: (-x[0], STAGES.index(x[1]["stage"])))
    return scored[:limit]


def render_md(blockers: list = None, title: str = "First-contact troubleshooting") -> str:
    """Render a blocker list (default: all, stage-ordered) as a markdown decision tree."""
    if blockers is None:
        blockers = BLOCKERS
    lines = [f"# {title}", "",
             "Symptom → likely cause → how to confirm → the way out. Ordered by the stage "
             "you hit it during first contact with an unknown board.", ""]
    cur_stage = None
    for b in sorted(blockers, key=lambda x: STAGES.index(x["stage"])):
        if b["stage"] != cur_stage:
            cur_stage = b["stage"]
            lines += ["", f"## Stage: {cur_stage}", ""]
        sev = "🛑 BLOCK" if b["severity"] == "block" else "⚠ degraded"
        lines += [f"### {b['id']} — {sev}",
                  f"**Symptom:** {b['symptom']}", "",
                  "**Likely causes:** " + "; ".join(b["causes"]), "",
                  "**Detect:**"] + [f"- {d}" for d in b["detect"]] + \
                 ["", "**Fix:**"] + [f"- {f}" for f in b["fix"]] + [""]
    return "\n".join(lines)
