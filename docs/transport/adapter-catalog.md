# Adapter Catalog — JTAG/SWD transport backends

Running log of hardware debug adapters the tool must be able to drive. Feeds the
**transport abstraction** (a driver interface with pluggable backends) and the GUI's
"Adapter & Target" panel. See `project_adapter_transport_gap` / `project_gui_direction`.

**Model:** an adapter maps to a **backend** (the host software that drives it) and a
set of **transports**; the reachable **access tier** on a given target is mostly a
function of (backend, silicon-class). Keep this catalog board-independent; per-board
allowlists live in `profiles/<soc>.json`.

**Access-tier ladder** (what "talk out" means):
`a` detect chain / IDCODE → `b` boundary-scan (EXTEST/SAMPLE) → `c` debug arch
(DAP mem-AP: memory/regs) → `d` run-control (halt/resume/breakpoints) →
`e` exploitation (dump ROM/flash, patch, key/secret extraction).

Legend for **Open-source?**: ✓ native OpenOCD/OSS · ~ partial/works-with-caveats ·
✗ needs vendor software.

---

## In scope — our kit (confirmed)

| Adapter | Vendor | Backend / host driver | Transports | Target families | USB VID:PID | OSS? | Notes |
|---|---|---|---|---|---|---|---|
| **SmartLynq2** | AMD/Xilinx | **hw_server + xsdb (XSCT)** | JTAG | Xilinx: ZynqMP, Zynq-7000, Versal, UltraScale(+) FPGA | USB-C / Ethernet | ✗ | Successor to SmartLynq. **No native OpenOCD driver** — vendor `hw_server` required (accepted dependency). xsdb is Tcl-scriptable, native to ZynqMP (`mrd`/`mwr`, halt/resume, APU/RPU/PMU). |
| **FlashPro4** | Microsemi/Microchip | **Libero / FlashPro Express** | JTAG | Microsemi flash FPGA: ProASIC3, IGLOO/IGLOO2, SmartFusion/**SmartFusion2** | ~0x1514 (Actel) | ✗ | Proprietary protocol, **not MPSSE** → no OpenOCD. Program/verify + security + eNVM/fabric readback (readback gated by FlashLock/pass-key). |
| **SEGGER J-Link** | SEGGER | OpenOCD `jlink` (or J-Link tools) | JTAG, SWD, cJTAG | ARM Cortex-M/A/R (incl. **SmartFusion2 M3**), some RISC-V | 0x1366:xxxx | ~ | Broad ARM support; firmware proprietary but OpenOCD drives it. **Best route to the SF2 Cortex-M3 over SWD — full run-control, no FlashPro needed** (if debug not locked). |
| **Generic FTDI / Digilent** (HS2/HS3/SMT2, FT2232H, FT232H) | FTDI / Digilent | OpenOCD `ftdi` | JTAG (SWD on some via MPSSE) | Any standard JTAG (Xilinx, ARM, …) | 0x0403:0x6010 / 0x6014; Digilent | ✓ | The default open path. ZCU102 onboard debug is an FT2232. Pin layout must match (`openocd/adapters/*.cfg`). |
| **JTAGulator** | Grand Idea Studio (Joe Grand) | its own serial CLI | — (pin **discovery**) | Unknown boards — finds JTAG/UART pinout | (FT232 USB-serial) | ✓ (open hw) | **Not a debug adapter** — brute-forces the JTAG/UART pinout on an unknown header; then you attach a real adapter. Belongs to the first-contact/discovery step. |

---

## Found via research

<!-- Populated from the online adapter sweep (background research agent, 2026-08-14).
     Merge the returned rows here, grouped by backend/ecosystem. -->

Online sweep 2026-08-14 (web research). **Key finding:** OpenOCD has an **`xvc`**
driver (Xilinx Virtual Cable over TCP) plus `xlnx_pcie_xvc`. Since AMD `hw_server`
can expose an **XVC server**, the SmartLynq2/Platform Cable can potentially be driven
*through OpenOCD via XVC* — keeping the existing OpenOCD-Tcl enumerate/dump scripts
instead of a full xsdb rewrite. hw_server is still required, but this is a much smaller
lift than re-homing everything on xsdb. Worth prototyping first.

### OpenOCD-native — ARM/general debug probes (the easy majority)

| Adapter | Vendor | OpenOCD driver | Transports | Targets | USB VID:PID | OSS? | Notes |
|---|---|---|---|---|---|---|---|
| ST-Link v2/v2.1/v3 | ST | `stlink` | SWD (+JTAG on v2) | ST + any Cortex-M | 0x0483:0x374x | ✓ | Cheap, ubiquitous; clones abound. |
| CMSIS-DAP / DAPLink / MCU-Link | ARM/NXP/many | `cmsis-dap` | JTAG, SWD | ARM Cortex | 0x0d28:0x0204 & many | ✓ | Open standard; SWD multi-drop. |
| **Atmel-ICE** | Microchip | `cmsis-dap` | JTAG, SWD (+PDI/TPI/UPDI/debugWIRE) | SAM Cortex-M, AVR | 0x03eb:0x2141 | ✓ | Vendor debugger that *is* OpenOCD-drivable via CMSIS-DAP. |
| **SAM-ICE** | Microchip (SEGGER OEM) | `jlink` | JTAG, SWD, SWV | SAM ARM | 0x1366:xxxx | ~ | Rebadged J-Link. |
| Raspberry Pi Debug Probe | Raspberry Pi | `cmsis-dap` | SWD (JTAG-capable HW) | ARM Cortex-M | 0x2e8a:0x000c | ✓ | RP2040-based CMSIS-DAP. |
| Keil **ULINK2 / ULINKplus/pro** | ARM/Keil | `ulink` (ULINK1 only) | JTAG, SWD | ARM | 0xc251:xxxx | ~ | Only original ULINK has an OpenOCD driver; ULINK2+ are µVision-oriented. |
| WCH-Link / WCH-LinkE | WCH | `cmsis-dap` (RV mode via WCH fork) | SWD, JTAG, RISC-V 1-wire | CH32 (RISC-V/ARM) | 0x1a86:0x8010/0x8012 | ~ | RISC-V mode needs WCH's OpenOCD fork. |

### OpenOCD-native — FTDI, FPGA cables, bit-bang, discovery

| Adapter | Vendor | OpenOCD driver | Transports | Targets | USB VID:PID | OSS? | Notes |
|---|---|---|---|---|---|---|---|
| Tigard | Securing Hardware / Crowd Supply | `ftdi` | JTAG, SWD, UART, SPI, I2C | generic | 0x0403:0x6010 | ✓ | Purpose-built HW-hacking FT2232H breakout. |
| TUMPA / Flyswatter2 / Bus Blaster / JTAG-lock-pick | TIAO / etc. | `ftdi` | JTAG (SWD some) | generic | 0x0403:0x6010 | ✓ | Classic FT2232H boards. |
| Adafruit FT232H | Adafruit | `ftdi` | JTAG, SWD | generic | 0x0403:0x6014 | ✓ | Single-channel MPSSE. |
| **Altera/Intel USB-Blaster** | Intel/Altera | `usb_blaster` (ublast) | JTAG | Intel FPGA + generic | 0x09fb:0x6001 | ✓ | Also drives non-Altera JTAG. |
| **Altera/Intel USB-Blaster II** | Intel/Altera | `usb_blaster` (ublast2) | JTAG | Intel FPGA + generic | 0x09fb:0x6010/0x6810 | ✓ | Needs a firmware blob at load. |
| Bus Pirate v3/v4 (v5/v6 newer) | Dangerous Prototypes | `buspirate` | JTAG, SWD (slow) | generic / discovery | 0x04d8:0xfb00 | ✓ | Jack-of-all-trades; slow but handy for first contact. |
| Raspberry Pi GPIO / any Linux SBC | — | `bcm2835gpio` / `linuxgpiod` / `sysfsgpio` | JTAG, SWD | generic | n/a | ✓ | Bit-bang; no dedicated HW needed. |
| Linux SPI (`linuxspidev`) | — | `linuxspidev` | SWD | ARM Cortex-M | n/a | ✓ | SWD over an SBC SPI port. |

### OpenOCD-native — Espressif & bridges

| Adapter | Vendor | OpenOCD driver | Transports | Targets | USB VID:PID | OSS? | Notes |
|---|---|---|---|---|---|---|---|
| ESP-Prog / ESP built-in USB-JTAG | Espressif | `ftdi` / `esp_usb_jtag` | JTAG | ESP32(-S/C) | 0x303a:0x1001 | ✓ | Built into many ESP32 variants. |
| **XVC bridge** (any XVC server, incl. hw_server) | — | `xvc` (TCP) / `xlnx_pcie_xvc` | JTAG | whatever the server exposes | n/a (network) | ✓ | **The OpenOCD path to SmartLynq2/Platform Cable** via hw_server's XVC server. |

### Open but NOT OpenOCD (own stack)

| Adapter | Vendor | Backend | Transports | Targets | USB VID:PID | OSS? | Notes |
|---|---|---|---|---|---|---|---|
| Black Magic Probe / ORBTrace | 1BitSquared | its own **GDB server** (BMDA) | JTAG, SWD | ARM Cortex-M/A, RISC-V | 0x1d50:0x6017/0x6018 | ✓ | No OpenOCD needed — talks GDB directly; BMDA app also drives FTDI/CMSIS-DAP/STLink/JLink. |

---

## Proprietary / needs vendor software (the important gaps)

Cannot be driven by OpenOCD directly — these force non-OpenOCD backends (or an XVC bridge):

- **AMD/Xilinx SmartLynq2 / SmartLynq / Platform Cable USB II** → `hw_server` + xsdb.
  *Escape hatch:* hw_server's **XVC server → OpenOCD `xvc` driver** (see key finding above).
- **Microchip/Microsemi FlashPro4 / FlashPro3** → Libero / FlashPro Express (proprietary USB, Actel VID ~0x1514).
- **FlashPro5 / FlashPro6** → Libero / FlashPro Express. FlashPro5 is FTDI(FT4232H)-based, so a raw-FTDI OpenOCD path *might* exist but is unverified.
- **Keil ULINK2 / ULINKplus / ULINKpro** → µVision (ULINK1 excepted — has `ulink` driver).
- **Lauterbach TRACE32**, **iSystem iC5000**, **PLS UDE** → high-end vendor software only.
- **Microchip MPLAB PICkit4 / ICD4 / SNAP** → primarily MPLAB (limited/vendor-locked modes).

## Open questions / to verify on hardware
- SmartLynq2 via XVC-through-OpenOCD: does hw_server's XVC server expose enough for our
  mem-AP reads and core halt, or do we still need xsdb for the ZynqMP-specific bits?
- FlashPro5 raw-FTDI feasibility (would give an OpenOCD path to Microsemi parts).
- Per-board **allowlists** (`profiles/<soc>.json` `adapters` block) now written for all
  17 profiles (2026-08-14). Refine tiers / USB VID:PIDs as hardware confirms them.

Sources: [OpenOCD Debug-Adapter-Configuration](https://openocd.org/doc/html/Debug-Adapter-Configuration.html) ·
[OpenOCD adapter drivers (DeepWiki)](https://deepwiki.com/openocd-org/openocd/3-jtag-and-debug-transport-layer) ·
[AMD SmartLynq / Platform Cable USB II](https://www.xilinx.com/products/boards-and-kits/hw-usb-ii-g.html) ·
[Altera USB-Blaster II cfg](https://github.com/arduino/OpenOCD/blob/master/tcl/interface/altera-usb-blaster2.cfg) ·
[Atmel-ICE](https://developerhelp.microchip.com/xwiki/bin/view/software-tools/programmers-and-debuggers/atmel-ice/) ·
[Black Magic Debug](https://black-magic.org/hardware.html) ·
[SWD probes compared](https://swdprobe.com/probes-compared.html)
