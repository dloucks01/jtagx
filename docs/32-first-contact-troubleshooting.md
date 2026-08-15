# First-contact troubleshooting

Symptom → likely cause → how to confirm → the way out. Ordered by the stage you hit it during first contact with an unknown board.


## Stage: adapter

### no-adapter — 🛑 BLOCK
**Symptom:** No JTAG/SWD adapter detected at all (lsusb shows nothing relevant).

**Likely causes:** adapter not plugged; VM did not pass the USB device through; missing udev rule / no libusb permission; kernel grabbed the FTDI as a serial port

**Detect:**
- `lsusb` — is the VID:PID there?
- in VMware: VM > Removable Devices — is the adapter attached to the guest?
- `dmesg | tail` after plugging — did it enumerate?

**Fix:**
- VMware/VirtualBox: attach the USB device to the GUEST (the #1 Kali-in-VM blocker)
- install a udev rule granting your user access (plugdev), then replug
- if it appears as ttyUSBx and OpenOCD can't claim it, unbind ftdi_sio (see ftdi-sio-conflict)

### proprietary-adapter — 🛑 BLOCK
**Symptom:** Adapter is present but OpenOCD can't drive it (FlashPro / SmartLynq / Platform Cable).

**Likely causes:** adapter is a vendor-proprietary programmer, not a generic JTAG cable; FlashPro (FP3/4/5) is FTDI silicon wrapped in proprietary Microsemi firmware; SmartLynq / Platform Cable USB II speak the Xilinx hw_server protocol, not OpenOCD

**Detect:**
- match the USB VID:PID (jtagx.transport.detect): 1514:* = FlashPro, 03fd:* = Xilinx
- OpenOCD errors with 'unable to open ftdi device' or wrong IDCODEs despite a good cable

**Fix:**
- FlashPro → use the Microsemi/Microchip backend: FlashPro Express (program/verify) or the SoftConsole-bundled PATCHED OpenOCD; on Linux unbind ftdi_sio first (see ftdi-sio-conflict)
- SmartLynq / Platform Cable → use the AMD hw_server + xsdb backend (Vitis), not OpenOCD
- if you only need enumeration, borrow a generic FTDI/CMSIS-DAP/J-Link cable and wire it to the target's JTAG header directly — the proprietary cable is only needed for its vendor flow

### ftdi-sio-conflict — 🛑 BLOCK
**Symptom:** FTDI adapter enumerates as /dev/ttyUSBx and OpenOCD reports it busy / cannot claim it.

**Likely causes:** the kernel ftdi_sio serial driver bound all channels of the FT2232H/FT4232H

**Detect:**
- `ls /dev/ttyUSB*` shows the adapter's channels
- `lsmod | grep ftdi_sio`

**Fix:**
- unbind the JTAG channel: `echo <bus>-<port>:1.0 > /sys/bus/usb/drivers/ftdi_sio/unbind`
- or add a udev rule that stops ftdi_sio binding interface 0 (PRODUCT/interface match)
- this is the SAME fix that lets a FlashPro's FTDI silicon be driven by a patched OpenOCD


## Stage: wiring

### no-vref — 🛑 BLOCK
**Symptom:** Adapter drives, but the target never responds; TCK/TMS look dead on a scope.

**Likely causes:** no target reference voltage (VTREF) — level shifters see no target rail; wrong I/O voltage (1.8 V target vs 3.3 V adapter); target not powered / in a low-power state

**Detect:**
- measure VTREF pin on the header (should equal the target I/O rail: 1.8 / 2.5 / 3.3 V)
- adapters that DON'T sense Vref (cheap FT2232 modules) happily drive 3.3 V into a 1.8 V part

**Fix:**
- power the target; confirm VTREF is present and matches the target I/O voltage
- use a Vref-sensing adapter or a level shifter for 1.8 V parts
- NEVER drive 3.3 V JTAG into a 1.8 V-only target — it can damage the pin

### wrong-connector — 🛑 BLOCK
**Symptom:** Cannot find/identify the debug header, or the cable physically doesn't fit.

**Likely causes:** unknown/nonstandard header pinout; Arm 20-pin (0.1") vs Cortex 10-pin (0.05" 1.27mm) vs Xilinx 14-pin PL vs TI 14/20-pin

**Detect:**
- count pins + pitch; look for a keyed/ground pattern; check the board silkscreen/schematic
- beep out TCK/TMS/TDI/TDO/GND/VTREF with a multimeter to a known test point

**Fix:**
- map the pinout: Arm 20-pin (0.1"), Arm Cortex 10/20-pin (1.27mm SWD+JTAG), Xilinx 14-pin PL JTAG, TI 14/20-pin — use the right adapter cable/adapter board
- for a bare/unlabeled header, identify GND (continuity to shield) and VTREF first, then TCK/TMS/TDI/TDO by boundary-scan or a logic analyzer


## Stage: chain

### no-idcode — 🛑 BLOCK
**Symptom:** JTAG scan returns all-ones or all-zeros — no IDCODE, no chain.

**Likely causes:** wiring (see no-vref / wrong-connector); TRST held asserted (chain in reset); clock too fast for the trace (see clock-too-high); TDI/TDO swapped

**Detect:**
- `openocd ... -c 'scan_chain'` / discover.tcl — 0x00000000 or 0xFFFFFFFF = no device
- swap-test: try TDI<->TDO; try a much slower adapter speed

**Fix:**
- drop adapter speed to 100–500 kHz and rescan (see clock-too-high)
- check TRST/SRST wiring and reset_config; try `reset_config none` first
- verify TDI/TDO orientation and GND/VTREF (wiring stage)

### clock-too-high — ⚠ degraded
**Symptom:** Intermittent/garbage IDCODEs; works at low speed, fails when sped up.

**Likely causes:** adapter clock exceeds what the trace/target can follow (RC of long jumpers)

**Detect:**
- it scans clean at 100–500 kHz but corrupts at MHz speeds

**Fix:**
- start at `adapter speed 100`, confirm a stable chain, then raise gradually
- shorten jumper wires; use adaptive clocking (RTCK) if the target supports it
- once stable, the cfg's `adapter speed` can be raised for faster enumeration

### unexpected-chain — ⚠ degraded
**Symptom:** A chain is seen but the IDCODEs / IR lengths don't match expectation.

**Likely causes:** multi-TAP daisy chain (extra TAPs: PL TAP, PMU BSCAN, a second device); wrong IR length in the cfg; a different silicon revision / part than assumed

**Detect:**
- compare scanned IDCODEs to the expected profile (board-runner --idcodes / discover.tcl)
- ZynqMP: only the PS TAP is visible until the CSU finishes boot; PMU TAP appears only when its eFuse policy allows

**Fix:**
- declare EVERY TAP in the chain with correct IR lengths (position matters)
- use board-runner.py to fingerprint the chain and pick the right profile
- if a TAP is expected but missing, its gate may be closed (policy stage)


## Stage: dap

### dap-powered-down — 🛑 BLOCK
**Symptom:** Chain/IDCODE OK, but AP access errors or the DAP won't power up.

**Likely causes:** debug power domain down (CDBGPWRUPREQ/ack not completing); sticky error latched in the DP CTRL/STAT; debug clock/reset gated (see ZynqMP DBG_LPD_CTRL)

**Detect:**
- DP CTRL/STAT: CDBGPWRUPACK / CSYSPWRUPACK not set
- OpenOCD 'JTAG-DP STICKY ERROR'

**Fix:**
- request debug power (OpenOCD does this on init; a manual `dap dpreg 0x4 0x50000000` sets the req bits)
- clear sticky errors (ABORT / read RDBUFF) and retry
- on ZynqMP confirm the LPD debug clock/reset gates (DBG_LPD_CTRL.CLKACT / RST_LPD_DBG)


## Stage: target

### target-wedges — 🛑 BLOCK
**Symptom:** Debug attaches, but the moment firmware runs the CPU/DAP wedges or re-locks.

**Likely causes:** firmware re-asserts readout protection / disables debug at boot; the part re-locks each power cycle (nRF52 rev3+, some STM32); boot-mode straps run code that hangs the bus

**Detect:**
- debug works right after reset but dies once code executes
- power-cycle returns it to locked

**Fix:**
- connect-under-reset: hold SRST, TRST the TAPs, halt at the reset vector BEFORE instruction 1 (`reset_config srst_only connect_assert_srst`) — the canonical way in for parts that wedge
- change boot-mode straps to a non-booting / prompt mode so no firmware runs
- for re-locking parts, keep the session attached; re-attach requires the under-reset entry again

### reset-polarity — ⚠ degraded
**Symptom:** SRST/TRST behave inverted, or reset never releases / never asserts.

**Likely causes:** nSRST polarity or open-drain vs push-pull mismatch (the classic 'NRST looks inverted' bug); SRST gates JTAG on this target but reset_config says otherwise

**Detect:**
- scope nSRST during `reset`; compare to reset_config
- target resets when it shouldn't (or won't)

**Fix:**
- set `reset_config` correctly: `srst_open_drain` vs `srst_push_pull`, `srst_gates_jtag` vs `srst_nogate`
- if only SRST is wired, `reset_config srst_only`; if neither, `reset_config none` and rely on TAP reset


## Stage: policy

### jtag-disabled — 🛑 BLOCK
**Symptom:** No DAP / no debug despite perfect wiring — the part's JTAG is disabled by policy.

**Likely causes:** eFuse JTAG-disable blown (ZynqMP JTAG_DIS / DFT_DIS; vendor equivalents); secure-boot policy gates the DAP until an authenticated image runs

**Detect:**
- chain may still show the PS TAP but the DAP/AP is dead and cannot be powered
- matches a hardened-part posture, not a wiring fault

**Fix:**
- if eFuse-disabled, JTAG is permanently off — no software lever (the unlock engine will say so)
- if policy-gated, debug may open only after an authenticated boot / via a debug-auth certificate
- fall back to non-debug extraction: vendor ROM loader (SDP/SAM-BA/esptool) or boundary-scan

