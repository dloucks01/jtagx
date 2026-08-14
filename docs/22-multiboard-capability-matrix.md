# 22 — Multi-Board Capability Matrix (engagement scope card)

**Purpose.** Before you ever touch an adapter, this card tells you — for the boards you might meet —
*which debug paradigm it is, what you can actually pull off it, what blocks you, which of our tools
already do it vs what we'd have to build, and the honest outcome you can put in the report.*

**The boards named below are EXAMPLES, not a fixed list.** Any engagement may bring a chip we've never
seen. The architecture is built for exactly that: the runner is fixed and the chips are open-ended data.

**The one idea that drives everything:** you don't have N boards, you have **~5 paradigms**. A paradigm
decides the *capabilities*; the individual chip is just a **profile** (a data fact-sheet: addresses +
parameters) that plugs into the paradigm's runner. Identify the paradigm first; the rest follows — and
critically, **the paradigm can be identified by *behavior* even when the exact chip is unknown** (see
the identification ladder below), so an unfamiliar board is a degraded-capability case, not a dead stop.

> Honesty rules used here (project convention): **vendor-documented** vs **empirical** are kept
> separate; exact IDCODEs are marked *verify on first contact* unless they're the well-known generic
> value. "HAVE" = a smoke-tested tool exists in this repo today. Anything else is work.

---

## Paradigm legend — read this first

| | Paradigm | Defining trait | Dump model | Live-patch model |
|---|---|---|---|---|
| **A** | ARM Cortex-A + MMU + external DRAM (Linux/RTOS) | CoreSight DAP with a **memory-AP** onto the real AXI bus | physical DRAM dump over the mem-AP; flash via the SoC's flash controller | **AXI-AP physical write bypasses the MMU's RO** (our Cap 2) |
| **B** | ARM Cortex-M MCU, internal flash, **no MMU** | SWD (or JTAG), flat internal memory | read internal flash + SRAM **directly** | direct write — no MMU to bypass; trivial if unlocked |
| **C** | Non-ARM MCU, vendor debug | debugWIRE / UPDI / SBW / ICSP / Xtensa-JTAG | flash + EEPROM via the **programming protocol**; Harvard (separate spaces) | rarely meaningful |
| **D** | FPGA programming TAP, **no CPU** | IEEE-1149.1 config TAP, no memory bus | bitstream / eNVM via **vendor protocol** only | none |
| **E** | RISC-V | RISC-V Debug Module | behaves like **A** or **B** by whether it has MMU+DRAM | as A or B |

**The gate that decides OPEN vs LOCKED** differs by paradigm: A = debug-enable / secure-boot eFuses;
B = a readout-protection bit (RDP / APPROTECT / GPNVM / FSEC); C = lock/fuse bits; D = the bitstream
security key. *Reopen only works when the gate is mutable register state — eFuse/OTP-blown = stuck.*

---

## Identification ladder — what happens when the board ISN'T one we know

An unknown chip is the *expected* case, not a failure. The runner degrades through three tiers; it
takes the best one that matches and runs those capabilities. It never fabricates chip-specific
knowledge (a flash driver, a reopen register) for a part it can't positively identify — but it *does*
run every **probe-based, chip-agnostic** capability that the live silicon proves is available.

| Tier | Match condition | What you get | What you DON'T get |
|---|---|---|---|
| **1 — Exact profile** | whole-chain fingerprint matches a registry profile | everything: security-posture enumeration, chip-specific flash driver, reopen levers, validated load addresses | — |
| **2 — Paradigm-generic** | no profile, but live probing proves the paradigm (e.g. an ADIv5 DAP with a working mem-AP onto DRAM = Paradigm A) | the **probe-based** capabilities: access verdict, **DRAM dump by walking the address space**, offline analysis (Ghidra, `dram-secrets`), generic mem-AP live patch (with `virt2phys`) | named-register posture, chip-specific flash, reopen levers (we don't know the gate's address) |
| **3 — Identify-only** | chain scans but no usable AP / it's a vendor FPGA TAP / locked-down | IDCODE(s), chain map, access verdict, paradigm guess → **report** | any dump |

The key distinction: **Tier-2 capabilities don't need a profile because they *probe* instead of
*look up*.** "Is there a mem-AP? Read CTRL/STAT. Walk the address space, dump the non-zero regions."
None of that depends on knowing the chip — only on standard CoreSight behavior. That's why an unknown
ARM-A board still goes home with a RAM dump + RE, and only the chip-*specific* extras (posture, flash,
reopen) wait for someone to author a profile. **Authoring a profile = promoting a board from Tier 2 to
Tier 1**, and is a pure data add.

---

## The engagement: 4 boards at a glance (illustrative)

| Board | Paradigm | Core(s) | RAM dump | Flash dump | Live patch | Tool status | One-line honest outcome |
|---|---|---|---|---|---|---|---|
| **Zynq UltraScale+** (ZynqMP, e.g. ZU9EG) | **A** | A53×4 + R5×2 + PMU + FPGA | ✅ | ✅ QSPI/DRAM | ✅ | **HAVE (complete)** | Full enumerate → dump → analyze → patch; this is the reference board |
| **Zynq-7000** (XC7Z) | **A** | A9×2 + FPGA | ✅ | ✅ QSPI/NOR | ✅ | **BUILD** (new register KB + flash driver) | Same paradigm as ZynqMP but 32-bit & different reg map — needs its own profile |
| **Raspberry Pi** (BCM2xxx) | **A** | Cortex-A, Linux | ✅ | ⚠️ VideoCore-owned | ✅ (PA-math tweak) | **BUILD-lite** (cfg + Linux PA math) | DRAM dump + secrets + Ghidra + patch; flash is the GPU's, not ours |
| **IGLOO2** (M2GL) | **D** | **none** (fabric + System Controller) | ❌ | ⚠️ eNVM/bitstream via FlashPro only | ❌ | **VENDOR TOOL** (FlashPro, not OpenOCD) | Identify + posture; readback only if security not provisioned. No memory capability |

**Read that last row carefully.** IGLOO2 is the board where the answer is structurally *"identified,
fabric posture noted, no RAM/flash dump path over JTAG."* It is not a CoreSight target — don't burn
engagement time trying to make the DAP tooling fit it.

---

## Per-board detail cards

### ▸ Zynq UltraScale+ (ZynqMP) — Paradigm A — **HAVE**
- **Transport:** standard 2-TAP chain — PS-TAP + ARM DAP (`0x4ba00477`); optional PMU MicroBlaze BSCAN TAP.
- **Identify by:** full chain fingerprint (PS-TAP IDCODE is device-specific — *verify from `discover.tcl`*).
- **Dump:** DRAM via mem-AP (`dump-os-ddr.tcl` + sparse); QSPI via `qspi-jtag.tcl` (DMA, byte-exact).
- **OPEN →** enumerate (`enumerate.tcl` posture) → dump → `parse-bootimage` → Ghidra → Cap 2 patch.
- **LOCKED →** `reopen-debug.tcl` + 3 Tier-1 levers (EL3 write / PMU MMIO / CSUDMA). Works **only** on
  software-hardened, no-eFuse targets.
- **Outcome:** the complete chain. This is the validated reference.

### ▸ Zynq-7000 (XC7Z) — Paradigm A — **BUILD**
- **Transport:** 2-TAP — ARM DAP (`0x4ba00477`) + PS/PL TAP (family `0x_372_093`, device-specific — *verify*).
- **Differences that force a new profile (not a copy of ZynqMP):**
  - 32-bit **ARMv7-A** (Cortex-A9), not 64-bit ARMv8 → different patch PA-math, different Ghidra language.
  - Register map is **UG585**, not the ZynqMP QEMU model: SLCR `0xF8000000`, devcfg `0xF8007000`,
    OCM 256 KB `@0xFFFC0000`, DDR base `0x00000000`. *(vendor-documented; addresses to be transcribed
    into a Zynq-7000 register KB.)*
  - Flash: QSPI via a **different controller** (and NOR via the SMC/PL353) → new flash-dump driver.
- **OPEN →** DRAM dump (generic mem-AP, new base) → Ghidra (ARM:LE:32) → live patch (ARMv7 PA math).
- **LOCKED →** devcfg/SLCR unlock + secure-boot posture (AES-256 + RSA via BootROM) — *to be characterized*.
- **Biggest single lift in this engagement:** the register KB + the SMC/QSPI flash driver.

### ▸ Raspberry Pi (BCM2xxx) — Paradigm A — **BUILD-lite**
- **Transport:** ARM CoreSight DAP — **but JTAG is OFF by default** (`enable_jtag_gpio=1` in `config.txt`
  + header wiring on the alt-function pins). If you can set that, you already had filesystem access.
- **Identify by:** DAP IDCODE is the generic `0x4ba00477` — **shared with ZynqMP and Zynq-7000**, so you
  *cannot* tell them apart from the DAP TAP alone. Disambiguate by the **whole chain** + a SoC-ID read
  once an AP is up. (See the IDCODE-ambiguity gotcha below.)
- **Dump:** DRAM via mem-AP (generic, base `0x0`) — **our strongest carry-over**. Flash is SD/eMMC/SPI-EEPROM
  owned by the closed **VideoCore** GPU → not ours to pull over ARM JTAG.
- **OPEN →** DRAM dump → `dram-secrets.py` (Linux `/etc/shadow`, SSH host keys, PEM, tokens — *more*
  useful than on VxWorks) → Ghidra (AArch64) → Cap 2 patch with **Linux page-offset PA math or
  `PATCH_USE_V2P=1`** (the VxWorks linear-map arithmetic is wrong here).
- **No vendor posture register set** to enumerate; Pi4/5/CM4 secure boot lives in OTP + the VPU bootloader,
  invisible to the ARM DAP.
- **Outcome:** recon (RAM + secrets + RE) and the live-patch capability. Not "enumerate security posture."

### ▸ IGLOO2 (M2GL) — Paradigm D — **VENDOR TOOL**
- **Transport:** IEEE-1149.1 **FPGA programming TAP** — *not* a CoreSight DAP. No ARM core, no AXI bus,
  no DRAM-over-JTAG. The hardened **System Controller** runs Microsemi firmware (not a user CPU).
- **What JTAG can reach:** the fabric configuration + **eNVM** — and only via Microsemi's proprietary
  **secure-programming protocol** (FlashPro Express / DirectC). **OpenOCD does not speak it.**
- **Gate:** FlashLock / user pass-key + optional AES-256 bitstream encryption. If security is provisioned,
  **readback/verify is disabled** → you get IDCODE + device status and nothing more.
- **OPEN (unprovisioned) →** IDCODE + device/security status; eNVM/bitstream readback *if* the security
  config permits (often it doesn't, by design).
- **LOCKED →** identify + report posture; **no dump path**. This is an expected, honest dead-end.
- **Tooling:** **Microchip FlashPro Express must be pre-staged on the laptop.** Treat as a separate track.
- *(Note: SmartFusion2 — IGLOO2's Cortex-M3 sibling — *would* give a DAP and drop into Paradigm B. Plain
  IGLOO2 does not.)*

---

## Atmel (now Microchip) — splits across 3 paradigms

"Atmel" is not one target. It lands in three different paradigms depending on the part:

| Atmel family | Paradigm | Core | Dump path | Gate (lock) | Tool status |
|---|---|---|---|---|---|
| **SAMA5** (D2/D3/D4) | **A** | Cortex-A5, DDR, Linux | mem-AP DRAM dump (generic) | debug-enable; SAMA5D2 TrustZone secure boot | **BUILD-lite** (new profile in the A runner) |
| **SAM3 / SAM4** | **B** | Cortex-M3 / M4, internal flash | read internal flash + SRAM directly (SWD/JTAG) | **GPNVM security bit** → blocks JTAG read until a full chip-erase | **BUILD** (the B runner) |
| **SAMD / SAME / SAML** | **B** | Cortex-M0+/M4/M7 (M23 on L11) | internal flash/SRAM directly | DSU debug-access protection / NVMCTRL security bit | **BUILD** (same B runner) |
| **AVR** (ATmega/ATtiny) | **C** | 8-bit AVR (Harvard) | flash+EEPROM via JTAG/debugWIRE/UPDI | **lock bits LB1/LB2** + fuse bits | **NEW** (low ROI — build only if named) |
| **AVR32** (AT32UC3) | **C** | 32-bit AVR32 | JTAG/aWire, vendor protocol | security bit | **NEW** (niche/deprecated) |

**Leverage point:** building the **Paradigm-B runner once** (Cortex-M: read internal flash + SRAM,
detect the readout-protection bit) covers SAM3/4/D/E **and** STM32, Nordic, Kinetis, RP2040 — thousands
of parts, one module. That's the highest-value thing to build after the Cortex-A line. The 8-bit AVR /
AVR32 (Paradigm C) is a genuine long tail — only build the specific part an engagement names.

---

## Other common boards you may meet (so the registry isn't surprised)

| Chip / board | Paradigm | Dump model | Gate | Tool reuse |
|---|---|---|---|---|
| **STM32** (F/L/H/G) | B | internal flash + SRAM | **RDP level 0/1/2** (L2 = permanent lock) | B runner |
| **Nordic nRF52 / nRF53** | B | internal flash + SRAM | **APPROTECT** (erase-on-unlock) | B runner |
| **NXP Kinetis / LPC** | B | internal flash + SRAM | **FSEC / MDM-AP** (Kinetis mass-erase-on-unlock) | B runner |
| **NXP i.MX 6/7/8** | A | DRAM via mem-AP; flash via boot ROM | HAB secure boot (eFuse) | A runner, new profile |
| **TI Sitara AM335x** (BeagleBone) | A | DRAM via mem-AP | debug-enable / secure-dev eFuse | A runner, new profile |
| **TI MSP430** | C | flash via Spy-Bi-Wire (2-wire JTAG) | JTAG-lock fuse (blown = dead) | NEW |
| **Espressif ESP32** (Xtensa) | C | external SPI flash; SRAM | flash-encryption + secure-boot eFuses | NEW (OpenOCD fork — friendliest C) |
| **Intel Cyclone V SoC / Arria** | A | A9×2 + fabric, DRAM via mem-AP | like Zynq | A runner (≈ Zynq-7000 profile) |
| **Lattice ECP5 / iCE40** | D | bitstream via vendor tool; external SPI config flash | bitstream security | VENDOR TOOL (Diamond / open tools) |
| **SiFive / generic RISC-V** | E | as A or B | debug-auth | E layer over A/B |
| **Rockchip / Allwinner SBCs** | A | DRAM via mem-AP | often wide open; sometimes locked | A runner, new profile |

---

## The universal flow (one runner, every Paradigm-A/B/E board)

```
1. IDENTIFY    scan chain at a speed-ladder → collect ALL IDCODEs + chain length
2. FINGERPRINT exact-chip match a PROFILE? ── yes → Tier 1 (full)
                                            ── no  → probe for a paradigm (mem-AP? = Tier 2 generic)
                                                     ── none → Tier 3 identify-only, report & exit
3. VERDICT     jtag-access-check → OPEN / RESTRICTED / LOCKED      (universal, ADIv5)
4. BRANCH      OPEN  → DUMP   (Tier 1: profile's flash+DRAM drivers; Tier 2: probe-walk DRAM)
               LOCKED→ REOPEN (Tier 1 only — needs the profile's levers) → re-run step 3
                        still locked (eFuse/OTP) → report "identified, locked, no capability"
5. ANALYZE     offline: parse → symbolize → Ghidra → dram-secrets → (optional) Cap-2 patch
```

Paradigm **D** (IGLOO2/Lattice) shortcuts to: *identify → FlashPro/vendor status → report*. No steps 3–5.

---

## What you actually take home (outcome matrix)

| Board | If OPEN | If LOCKED (mutable) | If LOCKED (eFuse/OTP) |
|---|---|---|---|
| ZynqMP | full chain: posture + flash + RAM + RE + live patch | reopen → full chain | posture + "locked" verdict |
| Zynq-7000 | flash + RAM + RE + live patch | devcfg unlock → as OPEN | posture + "locked" |
| Pi | RAM + secrets + RE + live patch | (n/a — config.txt, not register) | RAM only if JTAG was enabled |
| IGLOO2 | IDCODE + status + maybe eNVM readback | — | IDCODE + status only |
| SAM Cortex-M / STM32 / nRF | internal flash + SRAM + RE | (RDP/APPROTECT often erase-on-unlock) | identify only |
| AVR / MSP430 / ESP32 | flash + EEPROM via programmer | — | identify only (fuse-locked) |

---

## Pre-stage checklist for the offline laptop (no network at the site)

- [ ] **OpenOCD** built with: ZynqMP, Zynq-7000, BCM, generic Cortex-A/-M, RISC-V targets.
- [ ] **Register KBs:** ZynqMP (have) + **Zynq-7000 (build)** + BCM-minimal.
- [ ] **Cross-toolchains:** `aarch64-linux-gnu-*` (ZynqMP/Pi/SAMA5), `arm-none-eabi-*` (R5 + **A9 ARMv7** +
      all Cortex-M), nothing for AVR unless named.
- [ ] **Vendor tools (separate tracks):** **Microchip FlashPro Express** (IGLOO2), Lattice Diamond/open
      tools (if Lattice in scope), Espressif OpenOCD fork (if ESP32 in scope).
- [ ] **Ghidra** + the AArch64/ARM loaders and our import scripts.
- [ ] **Our offline analyzers:** `parse-bootimage.py`, `vxworks-symtab.py`, `dram-secrets.py`,
      `symbol-crypto.py`, `find-patch-target.py`, `interpret.py`.
- [ ] **USB-reset recovery** path (the FTDI/VMware wedge fix) — assume the adapter will wedge.
- [ ] **Adapter stanzas** (`adapters/`) for whatever physical interfaces you're carrying.

---

## Build priority (locks scope for what comes next)

1. ~~**Profile schema + the state-machine runner skeleton**~~ — ✅ **DONE (2026-06-11).** `profiles/_schema.md`
   (JSONC schema), `profiles/zynqmp.json` (complete Tier-1 reference) + `profiles/zynq7000.json` (partial,
   the worked "profile-in-progress" example), and **`tools/board-runner.py`** — the fixed engine that turns
   a chain fingerprint into an ordered, tagged plan ([LIVE]/[OFFLINE]/[VENDOR]) via the 3-tier ladder, with
   `--validate`, `--from-log`, `--out-json`. All three tiers + the generic Paradigm-A fallback are
   offline-tested in `tools/board-runner-smoketest.sh` (wired into `tcl-smoketest.sh`). Run it:
   `python3 tools/board-runner.py --idcodes 0x14738093 0x5ba00477`.
2. **Zynq-7000 profile** — 🟢 **FEATURE-COMPLETE, HW-UNVALIDATED (2026-06-11).** From **UG585 v1.12.2**
   (now in `references/pdf/ug585-zynq7000-trm.pdf`, Wayback-recovered): `openocd/zynq7000.cfg` (pinned,
   AHB mem-AP `zynq.axi`); `openocd/lib/zynq7000-regs.tcl` (address KB **+ devcfg CTRL/LOCK bit-fields +
   boot-mode Table 6-4**, all cited); `openocd/zynq7000-flash.tcl` (QSPI dump via the **LQSPI linear
   window @0xFC000000**, reuses `dump_memory`); `openocd/zynq7000-enumerate.tcl` (**real OFF/dev→ON
   posture checklist**: SEC_EN, DAP_EN, DBGEN/SPIDEN/NIDEN/SPNIDEN, JTAG_CHAIN_DIS, AES, the LOCK bits,
   boot device); `openocd/zynq7000-reopen-debug.tcl` (**reopen lever** = `devcfg.CTRL |= 0x7F`, gated by
   `LOCK[0]` exactly like the ZynqMP story); `probe-phys-patch.tcl` parameterized for the A9. **Remaining
   for "complete":** (a) **validation on a real Zynq-7000 board** (kept `status:"partial"` until then);
   (b) >32 MB / IO-mode flash. The reopen-lever discovery: Zynq-7000 debug/DAP enables are mutable `rw`
   bits unless `devcfg.LOCK[0]` (DBG lock) froze them (POR-only) — same software-vs-eFuse model as ZynqMP.
3. **Pi profile** — ✅ **DONE (2026-06-11), HW-UNVALIDATED.** `openocd/rpi.cfg` (builds on stock
   `target/bcm2837.cfg`; adds the `rpi.axi` mem-AP alias), `profiles/bcm.json` (DRAM dump + `dram-secrets`
   + Ghidra + Linux **virt2phys** Cap-2 with A53 target names; no posture/flash/reopen — VideoCore owns
   those). **A Pi can't be fingerprinted** (only the generic ARM DAP `0x4ba00477`), so it's
   `auto_match:false` and selected via **`board-runner --profile bcm`** — this drove the new `--profile`
   override + `auto_match` flag in the engine.
4. **IGLOO2 track** — ✅ **DONE (2026-06-11).** Engine now renders **Paradigm-D** profiles as *identify →
   `[VENDOR]` handoff → "no memory capability"* (no dump/patch on a programming TAP). `profiles/igloo2.json`
   carries the **FlashPro Express / Libero** runbook; `--profile igloo2`. (A recognized FPGA *manufacturer*
   like Lattice already auto-lands in Tier-3's generic-D handoff; IGLOO2 has no shipped IDCODE decoder, so
   it's `auto_match:false` — not fabricated.)
5. **Paradigm-B Cortex-M module** — ✅ **DONE (2026-06-11), HW-UNVALIDATED.** A Cortex-M dump is a flat
   mem-AP read, so it **reuses the Paradigm-A plan path** — no new plan function. New: `openocd/cortexm.cfg`
   (shared, SWD by default) + per-family wrappers `cortexm-{stm32f4,nrf52,rp2040}.cfg` (carry the chip
   constants as globals: flash/SRAM base+size, protection reg/kind, ID reg); `openocd/cortexm-dump.tcl`
   (flash + SRAM via `dump_memory`); `openocd/cortexm-protect.tcl` (**readout-protection decode**:
   STM32 RDP 0xAA/0xCC/L1, nRF52 APPROTECT, none). Profiles `stm32f4` / `nrf52` / `rp2040` (paradigm B,
   `auto_match:false` → `--profile`, since an MCU on SWD shows only a generic ARM DP). The pattern extends
   to SAM3/4/D/E, Kinetis, more STM32 families by adding a wrapper cfg + profile (data only). Cap-2 on an
   MCU = no-MMU direct write (PA=VA), target SRAM. **Remaining:** HW validation; more families as needed.

**Out of scope unless a target names them:** AVR/AVR32, MSP430, PIC, ESP32, Lattice, bare-FPGA readback.

## Registry status (7 profiles, 2026-06-11)

| soc | paradigm | status | auto-match | notes |
|---|---|---|---|---|
| `zynqmp` | A | complete | yes | the validated reference |
| `zynq7000` | A | partial | yes | feature-complete (UG585), HW-unvalidated |
| `bcm` | A | partial | no (`--profile`) | Pi; can't be fingerprinted |
| `stm32f4` / `nrf52` / `rp2040` | B | partial | no (`--profile`) | Cortex-M; HW-unvalidated |
| `igloo2` | D | stub | no (`--profile`) | FPGA TAP → FlashPro handoff |
