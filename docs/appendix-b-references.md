# Appendix B: Reference Documents

The authoritative sources for everything in this project. **Trust these
over my docs.** Where I cite "per UG1085 §X", that's where to verify.

## AMD / Xilinx documents

| Document | What it covers | When to consult |
|----------|---------------|-----------------|
| **UG1085** | Zynq UltraScale+ MPSoC Technical Reference Manual. Every register, every clock, every peripheral. ~1700 pages. **The bible.** | Anytime you need to understand a specific register's bit fields or how a peripheral works. |
| **UG1087** | Zynq UltraScale+ MPSoC Register Reference. Just the registers, in detail. | Bit-by-bit decoding of any register you don't recognize. |
| **UG1182** | ZCU102 Evaluation Board User Guide. Physical board layout, switches, connectors, schematics. | Board-level questions (which pin, which switch, what's connected to what). |
| **UG1137** | Zynq UltraScale+ MPSoC Software Developer Guide. Boot flow, FSBL, PMU firmware, ATF. | Understanding the official boot sequence; comparing what we do via raw JTAG against what FSBL does. |
| **UG1209** | ZynqMP Embedded Design Tutorial. Vendor walkthroughs for Linux/bare-metal. | Reference workflow when you eventually use Vitis. |
| **UG1283** | libmetal and OpenAMP. | Relevant if you start working with RPU coprocessor messaging. |
| **AR75361** | Xilinx Answer Record on Zynq UltraScale+ Secure Boot. | When working on secure-boot enforcement / bypass research. |

All available from https://docs.amd.com (search by doc number).

## ARM documents

| Document | What it covers |
|----------|---------------|
| **ARM Cortex-A53 MPCore Technical Reference Manual** | A53 architecture, debug registers, system register encodings |
| **ARM Architecture Reference Manual ARMv8 (DDI 0487)** | The ARMv8-A architecture itself. System register definitions, exception levels, MMU/TLB, TrustZone. Massive (~8000 pages). |
| **ARM CoreSight Architecture Specification** | The CoreSight debug fabric — DAP, APs, debug units, CTI, trace components |

Available from https://developer.arm.com.

## OpenOCD documentation

- Main docs: https://openocd.org/doc/html/
- User's Guide: https://openocd.org/doc-release/openocd.html
- Local: `man openocd`, plus the source in `/usr/share/openocd/scripts/`
  (read the .cfg files — they're well-commented)

Worth reading specifically:
- The OpenOCD User's Guide sections on `dap` commands, `target` commands,
  `read_memory`/`write_memory`
- `/usr/share/openocd/scripts/target/xilinx_zynqmp.cfg` — the file we
  source. Shows how the DAP TAP setup-event works.

## AArch64 toolchain references

- ARM Architecture Reference Manual (above) for instruction encoding
- GNU `binutils` documentation: https://sourceware.org/binutils/docs/
  for `aarch64-linux-gnu-as` syntax
- ARM ABI documentation for AArch64 calling conventions (relevant if
  you start writing payloads that interact with FSBL/U-Boot)

## Standards / specifications

- **JEP106** (JEDEC manufacturer ID standard) — the `0x49 = Xilinx`,
  `0x23B = ARM Ltd` IDs come from here.
- **IEEE 1149.1** — the JTAG specification.
- **ARM Debug Interface Architecture Specification (ADI v5/v6)** — the
  DAP/AP protocol.

## Useful Xilinx GitHub repos

- https://github.com/Xilinx/embeddedsw — FSBL, PMU firmware, drivers
  source code. **Reading the FSBL source is the best way to understand
  what magic numbers go where during boot.** Look at
  `lib/sw_apps/zynqmp_fsbl/src/` for the FSBL.
- https://github.com/Xilinx/u-boot-xlnx — Xilinx fork of U-Boot. Has
  the ZynqMP-specific driver code.
- https://github.com/Xilinx/linux-xlnx — Xilinx fork of Linux kernel.
  The PS UART driver (`drivers/tty/serial/xilinx_uartps.c`) is
  particularly useful for understanding the UART register layout.

## Things I cited that you should be skeptical of

| In my docs | Trust against |
|------------|---------------|
| SW6 mode table | The silkscreen on YOUR board (revisions vary) and UG1182 |
| Register bit-field assignments | UG1085 / UG1087 |
| MIO pin mux values | UG1085 §28 (MIO Pin Mappings) and Xilinx FSBL source |
| Part identification table in enumerate.tcl | UG1085 Table 39-1 |

## When to use Vitis (eventually)

For production work with FSBL, PetaLinux, or VxWorks, you'll eventually
need AMD Vitis installed:

- Generates hardware platform `.xsa` from Vivado designs
- Includes `psu_init.tcl` with all the magic init numbers (clocks, MIO,
  DDR) for a given hardware platform
- Builds FSBL, ATF, U-Boot, PetaLinux
- Includes XSCT/XSDB (alternative to OpenOCD with full AMD support)

Free download (requires AMD account):
https://www.amd.com/en/developer/vitis.html

Recommended version: **Vitis 2024.2** (recent + mature; avoid the
absolute bleeding-edge `.0` releases until a `.1` patch ships).

Install size: ~75 GB.
