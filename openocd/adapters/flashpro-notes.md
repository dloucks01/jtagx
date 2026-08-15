# FlashPro (FP3/FP4/FP5) — why OpenOCD can't drive it, and the way out

**The engagement blocker, codified.** On a real engagement a FlashPro4 (and another
vendor cable) blocked first contact because the toolkit only spoke OpenOCD. Here is
exactly why, and the concrete path forward. The tool detects a FlashPro by USB
VID:PID (`1514:2005` FP4, `1514:2008` FP5 — see `jtagx/transport/detect.py`) and
routes to the `libero` backend / this note instead of failing silently.

## What a FlashPro actually is
- It is **FTDI silicon** (an FT2232-class device) **wrapped in proprietary Microsemi/
  Microchip firmware + a management layer** (`fpServer` on Windows). It is *not* a
  generic MPSSE JTAG cable.
- Stock OpenOCD's `ftdi` driver **cannot** drive it: the proprietary firmware/protocol
  sits between the FTDI channels and the JTAG pins. Pointing `openocd -f ...ftdi...`
  at it yields "unable to open ftdi device" or garbage IDCODEs even with good wiring.
- It only programs/debugs **Microsemi/Microchip** parts: PolarFire, PolarFire SoC,
  SmartFusion2, IGLOO2, RTG4, IGLOO, ProASIC3, Fusion.

## The ways out (in order of preference)

1. **FlashPro Express** (free, Microchip) — program/verify/erase only, no live debug.
   Enough for reflash / bitstream / eNVM programming flows.
2. **SoftConsole's bundled PATCHED OpenOCD** — Microchip ships a *modified* OpenOCD
   (with a FlashPro driver) inside SoftConsole, driven via `board/microsemi-*.cfg`.
   This is the only OpenOCD that talks to a FlashPro. Treat it as a distinct backend,
   not "our" OpenOCD.
3. **Linux `ftdi_sio` conflict** — the kernel serial driver often grabs the FlashPro's
   FTDI channels as `/dev/ttyUSB*`, so even the patched OpenOCD can't claim it. Unbind:
   ```
   # find the interface, then:
   echo <bus>-<port>:1.0 | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind
   ```
   or add a udev rule that stops `ftdi_sio` binding interface 0. (Same fix as any
   FT2232H JTAG channel — see `first-contact.py` blocker `ftdi-sio-conflict`.)
4. **Borrow a generic cable for enumeration** — if you only need to *read* posture
   (not the Microchip programming flow), wire a generic FTDI / CMSIS-DAP / J-Link to
   the target's JTAG header and drive it with stock OpenOCD. The FlashPro is only
   required for the vendor program/verify flow, not for a JTAG scan/enumerate.

## What NOT to do
- Don't keep retrying `openocd -f openocd/<board>.cfg` with the FlashPro plugged and
  expect it to work — it never will with stock OpenOCD. That is the exact dead-end
  this note exists to break.

See also: `docs/32-first-contact-troubleshooting.md` (the full decision tree),
`jtagx/transport/matrix.py` (backend routing: FlashPro → `libero`, "program/verify
engine, not a debugger"), and `jtagx/firstcontact.py` blocker `proprietary-adapter`.
