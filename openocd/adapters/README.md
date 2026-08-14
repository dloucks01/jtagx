# openocd/adapters/ — ready-to-use JTAG adapter interface stanzas

Drop-in interface configs for `board-template.cfg`'s `JTAG_IFACE`. These set only the adapter
(driver, VID:PID, pin layout) — **transport and clock speed are set by `board-template.cfg`**, so
these stay composable. Set `vid_pid` to match your actual device (`lsusb`, or let
`tools/gen-board-cfg.py` detect it).

| File | Adapter | When to use |
|------|---------|-------------|
| `ft2232h-generic.cfg` | FTDI FT2232H (ch. A) | Hand-wired FT2232H mini-module/breakout to a JTAG header. Explicit MPSSE pin layout you can edit. |
| `ft232h-generic.cfg`  | FTDI FT232H | Adafruit FT232H breakout; generic single-channel FTDI. |

For these common adapters the **stock OpenOCD configs** are already correct — use them directly
as `JTAG_IFACE` (no copy needed):

| Adapter | Stock cfg |
|---------|-----------|
| Digilent JTAG-SMT2 (ZCU10x on-board) | `interface/ftdi/digilent_jtag_smt2_nc.cfg` |
| SEGGER J-Link | `interface/jlink.cfg` |
| Olimex ARM-USB-OCD-H | `interface/ftdi/olimex-arm-usb-ocd-h.cfg` |
| ARM CMSIS-DAP | `interface/cmsis-dap.cfg` |

List everything installed: `ls /usr/share/openocd/scripts/interface/ /usr/share/openocd/scripts/interface/ftdi/`

## Reality check

Selecting the right interface stanza is necessary but **not sufficient** — it gets the host
talking to the *adapter*, not the adapter talking to the *board*. You still own the physical
layer the software can't see: **I/O voltage / Vref (ZynqMP PS-JTAG is 1.8 V), level-shifting,
the JTAG pinout/connector, lead length, and a slow-enough clock.** Start at `JTAG_SPEED=300` and
raise only once IDCODEs read cleanly. See `docs/18-new-board-bringup.md` Stages 1-2.
