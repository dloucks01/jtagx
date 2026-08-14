# 25 — Cortex-M MCU + Raspberry Pi Enumerated Attributes (catalog)

The attribute catalog for the Paradigm-B MCUs (`openocd/cortexm-protect.tcl`) and the Raspberry Pi
(`openocd/pi-enumerate.tcl`) — location, dev/open value, hardened meaning, why we care. Companion to
`docs/24` (Zynq-7000) and `docs/11` (ZynqMP). Every address is cited to the vendor doc now in
`references/pdf/`: **RM0090** (STM32F4), **nRF52840 PS v1.1** (Nordic), **RP2040 datasheet**, **DS60001507** (SAM D5x/E5x), **K64 RM** (Kinetis).

> Honest scope: all HW-UNVALIDATED (no MCU/Pi on the bench). Addresses are from the vendor docs (one
> bug the audit caught: the nRF52840 PS *overview* Table 10 has a typo — the authoritative *detail*
> section §4.5.1.5 (+ the Nordic SDK) put **APPROTECT at UICR `0x208`**, and `0x204` is `PSELRESET[1]`.
> Two more off-by-one byte errors were caught and fixed: SAM `DSU.STATUSB` is `0x...02` (not `0x...01` =
> STATUSA), and Kinetis `FTFE_FSEC` is `0x...02` (not `0x...01` = FCNFG).
> **Universal Paradigm-B truth:** if you can *read* any of these registers, the AHB-AP is open and
> internal flash is dumpable now; the values tell you configured intent + whether the only unlock is a
> destructive mass-erase.

---

## STMicro STM32F4 (RM0090)

| Attribute | Location | Dev value | Hardened / other | Why we care |
|---|---|---|---|---|
| Part + revision | `DBGMCU_IDCODE` `0xE0042000` (DEV_ID 11:0, REV_ID 31:16) | 0x413=F405/407/415/417, 0x419=F427/429… | — | Exact part → flash/RAM map |
| Unique device ID | `0x1FFF7A10` (96-bit, 3 words) | per-die | — | Device fingerprint / key-derivation seed |
| Flash size | `0x1FFF7A22` (16-bit, KB) | e.g. 1024 | — | Sizes the flash dump |
| **RDP** | `FLASH_OPTCR` `0x40023C14` bits 15:8 | 0xAA = **Level 0** (no protection) | 0xCC = L2 (debug dead); else **L1** (flash blocked; unlock = mass-erase WIPE) | THE flash-readout gate |
| Write-protect | `FLASH_OPTCR` bits 27:16 (nWRP) | all 1 (unprotected) | bit=0 → that sector write-protected | Which sectors resist programming |
| BOR level | `FLASH_OPTCR` bits 3:2 | — | brown-out reset threshold | Config completeness |

## Nordic nRF52840 (PS v1.1, FICR base `0x10000000`, UICR base `0x10001000`)

| Attribute | Location | Dev value | Hardened / other | Why we care |
|---|---|---|---|---|
| Part / variant | `FICR.INFO.PART` `0x10000100` / `.VARIANT` `0x104` | 0x52840 / ASCII build | — | Exact part + HW rev |
| RAM / Flash | `FICR.INFO.RAM` `0x1000010C` / `.FLASH` `0x110` (KB) | 256 / 1024 | — | Sizes the dump |
| Device ID | `FICR.DEVICEID[0/1]` `0x10000060/64` | per-die | — | Device fingerprint |
| **APPROTECT** | `UICR.APPROTECT` **`0x10001208`** | 0xFFFFFFFF = **open** (HwDisabled) | else = enabled (reset re-locks; unlock = CTRL-AP mass-erase WIPE) | THE access-port gate |
| Debug control | `UICR.DEBUGCTRL` `0x10001210` | 0xFFFFFFFF = all debug allowed | restricts CPU non-invasive / FPB | Fine debug gating |
| REGOUT0 (VOUT) | `UICR.REGOUT0` `0x10001304` | per-board | — | Regulator config (bricking risk if wrong) |

## RP2040 (datasheet, SYSINFO base `0x40000000`)

| Attribute | Location | Dev value | Why we care |
|---|---|---|---|
| Chip ID | `SYSINFO.CHIP_ID` `0x40000000` (PART 27:12, REV 31:28, MANUF 11:0) | per-die | Part + revision |
| Platform | `SYSINFO.PLATFORM` `0x40000004` | bit1 = ASIC | silicon vs FPGA/sim |
| Git ref | `SYSINFO.GITREF_RP2040` `0x40000040` | bootrom build | Provenance |
| Readout protection | — | **none** | No on-chip fuse — the **external QSPI flash (XIP `0x10000000`)** is the only gate; readable unless QSPI disabled |

## STMicro STM32L4 (RM0351) — RDP in a different place than F4

| Attribute | Location | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| Part + rev | `DBGMCU_IDCODE` `0xE0042000` | 0x415=L4x6, 0x435=L43/44, 0x470=L4R/S… | — | Exact part |
| Unique ID / flash size | `0x1FFF7590` (96-bit) / `0x1FFF75E0` (KB) | per-die | — | Fingerprint / dump size |
| **RDP** | `FLASH_OPTR` `0x40022020` **bits 7:0** | 0xAA = Level 0 | 0xCC = L2; else L1 (mass-erase to unlock) | THE gate (note: L4 RDP is bits 7:0, F4 is 15:8) |

## STMicro STM32F1 (RM0008) — single-bit RDP

| Attribute | Location | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| Part + rev | `DBGMCU_IDCODE` `0xE0042000` | 0x410=F103 med, 0x414=high, 0x418=conn | — | Exact part |
| Unique ID / flash size | `0x1FFFF7E8` / `0x1FFFF7E0` (KB) | per-die | — | Fingerprint / size |
| **RDPRT** | `FLASH_OBR` `0x4002201C` **bit 1** | 0 = not protected | 1 = read-protected (mass-erase to unlock) | THE gate (a single bit, not a level) |

## Microchip SAM D5x/E5x (DS60001507) — DSU debug-access protection

| Attribute | Location | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| Device ID | `DSU.DID` `0x41002018` (FAMILY/SERIES/DIE/REV/DEVSEL) | per-die | — | Exact part |
| **Debug protection** | `DSU.STATUSB` `0x41002002` bit 0 (PROT) | 0 = open | 1 = protected — only **chip-erase** (WIPE) removes the NVMCTRL security bit | THE gate |

## NXP Kinetis K64 (K64P144M120SF5RM) — FSEC / mass-erase model

| Attribute | Location | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| Device ID | `SIM_SDID` `0x40048024` (FAMID/SUBFAMID/SERIESID/PINID/REVID) | per-die | — | Exact part |
| **Flash security** | `FTFE_FSEC` `0x40020002` bits 1:0 (SEC) | 0b10 = **unsecured** | else secured — unlock = MDM-AP **mass-erase** (WIPE) | THE gate |
| Mass-erase enable | `FTFE_FSEC` bits 5:4 (MEEN) | not 0b10 | **0b10 = mass-erase disabled → secured + no recovery (permanently locked)** | The worst case: even the wipe is gone |

## Raspberry Pi (BCM2xxx) — ARM-side only

The Pi's secure boot / OTP / chip identity live in the **closed VideoCore GPU**, not on the ARM JTAG.
The one ARM-readable security attribute is the CoreSight debug authentication:

| Attribute | Location | Dev value | Why we care |
|---|---|---|---|
| Debug auth | CoreSight `AUTHSTATUS` at core-0 dbgbase `+0xFB8` (Pi3 0x80010000 / Pi4 0x80410000) | all "enabled" (NSID/NSNID/SID/SNID) | Whether invasive / secure debug is permitted |
| secure boot / OTP / identity / boot flash | **VideoCore-owned** | — | **Not on the ARM JTAG** — read via the VC mailbox, not the DAP |

So the Pi's JTAG value is **RAM dump + live patch**, not posture enumeration — the catalog is honestly
short by design.
