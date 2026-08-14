# ZynqMP reference library

Local copy of the authoritative AMD/Xilinx documentation and source for the Zynq
UltraScale+ MPSoC, pulled 2026-06-08 for offline study of the secure-boot stack
(bootgen · bootrom · csu · fsbl · pmu · puf · keys). Synthesis of the key facts is
in [`../docs/12-secureboot-internals.md`](../docs/12-secureboot-internals.md);
this directory is the raw corpus behind it.

## PDFs (`pdf/`)

| File | Doc | Covers |
|---|---|---|
| `ug1085-zynqmp-trm.pdf` (19M) | **UG1085 — ZynqMP TRM** | The authoritative reference. Ch.11 boot & security (CSU, PMU, secure boot), Ch.12 PUF, memory map, every subsystem. |
| `ug1283-bootgen.pdf` (2.4M) | **UG1283 — Bootgen User Guide** | Boot-image format, authentication (PPK/SPK/RSA), encryption (AES-GCM, .nky), gray/black/family keys. |
| `ug1137-mpsoc-sw-dev.pdf` (4.4M) | **UG1137 — SW Developer Guide** | Boot flow (PMU ROM → CSU → FSBL → ATF), FSBL, key handling, the "FSBL copied from 0xFFFC0000" ground truth. |
| `ug1144-petalinux.pdf` (5.7M) | **UG1144 — PetaLinux Tools** | Building boot images / FSBL / the SD-boot path. |
| `ug1182-zcu102.pdf` (229K) | **UG1182 — ZCU102 Board UG** | SW6 boot-mode switch, connectors, USB IDs. |
| `ug585-zynq7000-trm.pdf` (20M) | **UG585 — Zynq-7000 SoC TRM** (v1.12.2) | The **Zynq-7000** (XC7Z, dual A9 + FPGA) reference, for the multi-board profile (docs/22, build #2; enumeration docs/24). Ch.6 Boot & Config (boot-mode straps Table 6-4 / PDF p.166), Ch.27 JTAG & DAP Subsystem, Ch.32 Device Secure Boot, **Appendix B** register details — devcfg @PDF p.1145-1162 (CTRL/LOCK/STATUS/MCTRL), slcr security @p.1620-1626 (PSS_IDCODE/REBOOT_STATUS/APU_CTRL/TZ_DMA). Wayback-recovered 2026-06-11 (AMD portal no longer serves a direct PDF). |
| `rm0090-stm32f4.pdf` (28M) | **RM0090 — STM32F4 Reference Manual** | STM32F405/407/415/417/427/429 etc. For the Cortex-M (Paradigm-B) enumeration (docs/25): FLASH_OPTCR (RDP/nWRP/BOR), DBGMCU_IDCODE, 96-bit unique ID @0x1FFF7A10, flash size @0x1FFF7A22. Wayback-recovered 2026-06-11. |
| `nrf52840-ps.pdf` (18M) | **nRF52840 Product Spec** (v1.1) | Nordic nRF52840 BLE SoC. For docs/25: FICR (INFO.PART/RAM/FLASH/DEVICEID) + UICR (APPROTECT @0x204, DEBUGCTRL, REGOUT0) — register overview p.43-44. Wayback-recovered 2026-06-11. |
| `rp2040-datasheet.pdf` (5M) | **RP2040 datasheet** | Raspberry Pi RP2040 (dual M0+). For docs/25: SYSINFO (CHIP_ID/PLATFORM/GITREF); no on-chip readout protection (external QSPI flash is the gate). From datasheets.raspberrypi.com 2026-06-11. |
| `samd5x-e5x-ds.pdf` (14M) | **SAM D5x/E5x Family Data Sheet** (DS60001507E) | Microchip SAM D5x/E5x (Cortex-M4). For docs/25: DSU @0x41002000 — DID (identity) + STATUSB.PROT (debug-access protection / NVMCTRL security bit). Wayback-recovered 2026-06-11. |
| `kinetis-k64-rm.pdf` (9M) | **Kinetis K64 Sub-Family RM** (K64P144M120SF5RM) | NXP Kinetis K64 (Cortex-M4). For docs/25: SIM_SDID @0x40048024 (identity) + FTFE_FSEC @0x40020001 (SEC/MEEN flash security; MEEN=10 = no mass-erase recovery). Wayback-recovered 2026-06-11. |

**Not auto-pulled** (behind the AMD JS doc viewer — grab via browser if needed):
- **UG1087** Register Reference → `docs.amd.com` (equivalent: `openocd/lib/zynqmp-regs-qemu.tcl` + TRM register chapters).
- **UG1209 / EDT** → web-based at `xilinx.github.io/Embedded-Design-Tutorials`.
- **XAPP1319** (secure-key provisioning), **XAPP1267** (eFuse program) → `docs.amd.com` application notes.

## Source (`src/`) — implementation ground truth

| Tree | Repo | What it is |
|---|---|---|
| `src/bootgen/` | github.com/Xilinx/bootgen | Boot-image generator. `authentication-zynqmp.*` (RSA-4096/SHA-3 AC layout), `bootheader-zynqmp.*` (key/IV fields), `readimage-zynqmp.*`. |
| `src/embeddedsw/lib/sw_services/xilsecure/` | github.com/Xilinx/embeddedsw (sparse) | CSU **AES-GCM / SHA-3 / RSA** driver — the engine command sequences. |
| `src/embeddedsw/lib/sw_services/xilskey/` | ″ | **eFuse / PUF / BBRAM** programming + read. `xilskey_eps_zynqmp_puf.*` (PUF REGISTRATION/REGEN, shutter, syndrome/CHASH/AUX), BBRAM CRC-verify. |
| `src/embeddedsw/lib/sw_apps/zynqmp_fsbl/` | ″ | **FSBL** source — boot, partition load, authentication/decryption, `xfsbl_hw.h` addresses. (Compare against our dumped FSBL: `../dumps/fsbl-freshboot.disasm`.) |
| `src/embeddedsw/lib/sw_apps/zynqmp_pmufw/` | ″ | **PMU firmware** — PM API, IPI handlers, `pm_mmio_access.c` (the MMIO allowlist), power management. |

(These are vendored shallow/sparse clones with their own `.git`; upstream URLs above. If this tree is ever git-init'd, `.gitignore` `references/`.)

## Topic → where to look

| Topic | Primary sources |
|---|---|
| **BootROM** (internal, not dumpable) | UG1137 (FSBL@0xFFFC0000); TRM Ch.11; `docs/12` §0. CSU ROM is internal to the CSU SPB — no source/dump. |
| **CSU** | TRM Ch.11; `xilsecure/` (AES/SHA/RSA); our `reports/csu-fullmap-*.md` (live register map). |
| **FSBL** | `zynqmp_fsbl/` source + `dumps/fsbl-freshboot.disasm` (this board's actual FSBL). |
| **PMU** | `zynqmp_pmufw/` (esp. `pm_mmio_access.c`); TRM Ch.6/11; PMU ROM @0xFFD00000 (eFuse-locked). |
| **PUF** | TRM Ch.12; `xilskey_eps_zynqmp_puf.*`; `docs/12` §3. |
| **Keys** (family/gray/black/KEK) | UG1283 + `bootgen/`; `xilsecure/`; `docs/12` §2; family key = metal-layer, unreadable. |
| **bootgen / boot image** | UG1283 + `src/bootgen/`. |
