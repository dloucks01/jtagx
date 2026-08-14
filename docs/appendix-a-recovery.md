# Appendix A: Recovery Procedures

When something gets wedged, this is how you recover.

## Power-cycle the board

The nuclear option that fixes nearly everything. Required when the DAP
is stuck in a sticky-error state that no software recovery can clear.

1. Verify SW6 is still set to JTAG idle (`0000`, all four ON). If
   you've been experimenting with boot modes, set it back.
2. **Flip SW1 to OFF.** The fan stops, status LEDs go out.
3. **Wait 5 seconds.** Some rails persist briefly on the board's
   bulk capacitance.
4. **Flip SW1 to ON.** Fan spins back up, LEDs return.
5. **Re-check USB passthrough in VMware** (if using a VM) — the FT232H
   re-enumerates as a new USB device and may need re-clicking in
   `VM → Removable Devices → Future Technology Devices FT232H →
   Connect`.
6. Verify USB came back in Kali:
   ```bash
   lsusb | grep -iE "10c4|0403"
   ls /dev/ttyUSB*
   ```
   Should show both devices and five `/dev/ttyUSB*` nodes.

If `/dev/ttyUSB4` is missing but lsusb shows the FT232H, the kernel
`ftdi_sio` driver didn't auto-bind. Usually a non-issue — OpenOCD uses
libusb and doesn't need the kernel driver. If you specifically need
`/dev/ttyUSB4`:

```bash
sudo modprobe -r ftdi_sio
sudo modprobe ftdi_sio
```

## DAP wedge during enumeration

**Symptom:** `enumerate.tcl` exits early with a "FATAL: AXI mem-AP not
reachable" message.

**Cause:** A53 was released in a previous run and the cleanup didn't
get to re-assert reset. When you re-run, init's auto-examination of the
already-released A53 triggers sticky errors that block AXI-AP access.

**Fix:** Power-cycle the board (above procedure). After a fresh POR,
A53 is back in reset, AXI-AP examines cleanly, and the script runs.

The script's cleanup section at the end re-asserts A53 reset
automatically on a clean run, so this only happens when something
crashed mid-script.

## A53 won't examine

**Symptom:** After running the A53 release recipe,
`uscale.a53.0 arp_examine` still fails with `JTAG-DP STICKY ERROR`.

**Likely causes:**

1. **Forgot to clear bit 8 (APU_L2_RESET)**. Without L2 cache out of
   reset, A53 can't fetch instructions. Verify your write to
   `RST_FPD_APU` includes clearing bit 8.

2. **OCM not powered.** Should be on by default in JTAG idle, but
   verify via `PMU_GLOBAL.PWR_STATE` bit 20/21 (OCM banks).

3. **DAP sticky from prior failed operation**. Issue
   `uscale.dap dpreg 0 0x1e` before retrying examine.

4. **RVBAR points somewhere that traps immediately**. Verify
   `RVBARADDR0L` points at OCM containing valid code (your safe
   landing). Default is `0xFFFF0000` which is in OCM bank 3 — that's
   also poisoned, so A53 will trap there if you didn't override.

## OpenOCD hangs (Ctrl-C doesn't work)

**Symptom:** OpenOCD seems frozen. Ctrl-C in the terminal doesn't kill
it cleanly.

**Cause:** OpenOCD is waiting on an AXI bus transaction that will
never complete (peripheral held in reset, unmapped address, or wedged
DAP).

**Fix:**

```bash
# In another terminal
pkill -9 openocd
```

Then power-cycle the board (DAP may be wedged from the hung
transaction).

## VMware USB passthrough fails

**Symptom:** Plug in USB cable, `VM → Removable Devices` shows the
device, you click Connect, but `lsusb` in Kali doesn't show it.

**Common causes:**

| Cause | Fix |
|-------|-----|
| VM USB controller set to USB 1.1 | VM Settings → USB → set to USB 2.0 or 3.1, reboot VM |
| Host OS has device claimed | On macOS, eject any IOKit driver claiming the FTDI/CP210x device. On Windows, may need to disable the FTDI driver service. On Linux host, `modprobe -r ftdi_sio` then re-passthrough. |
| Cable is charge-only | Try a different micro-USB cable (this is surprisingly common) |
| USB 3 port + VMware unstable | Plug into a USB 2 port on the host machine |

## Recovering from a partial UART setup attempt

If you've been experimenting with UART register pokes and want to
reset the board state without changing SW6:

```bash
# Inside OpenOCD:
# Re-assert all peripheral resets
mww 0xFF5E0238 0x0017FFFF   ;# RST_LPD_IOU2 = default
mww 0xFF5E023C 0x00188FD7   ;# RST_LPD_TOP = default

# Restore default MIO routing (all GPIO mode)
mww 0xFF180048 0x0           ;# MIO_PIN_18 = GPIO
mww 0xFF18004C 0x0           ;# MIO_PIN_19 = GPIO

# Restore tri-state defaults
mww 0xFF180204 0xFFFFFFFF    ;# MIO_MST_TRI0 = all tri-stated
```

Or just power-cycle — much faster.

## Killing background processes

If you've set up a UART listener:

```bash
pkill -f "cat /dev/ttyUSB"
```

Not `pkill subshell-PID` — that leaves orphaned `cat` children.

## "Device or resource busy" from OpenOCD

The kernel `ftdi_sio` driver is holding the FT232H. Modern OpenOCD
auto-detaches via libusb, but if that fails:

```bash
# Find the binding
ls /sys/bus/usb/drivers/ftdi_sio/
# (looks like 1-2:1.0 or similar)

echo "1-2:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind
```

Then retry OpenOCD.
