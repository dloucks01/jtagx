---
toc: false
---

# JTAG Enumeration for Security Research on the Zynq UltraScale+ MPSoC

## Volume 3 — What Enumeration Reveals (and How to Use It)

Enumeration over JTAG is a **security-configuration assessment**: read the
registers where ZynqMP's security controls live, and their values tell you which
controls are on. This volume is the field guide. Each indicator category lists the
exact attributes and **where to find them in a register dump** (block · address ·
bits), how the dev-board baseline compares to a hardened part, and what the
observed state enables.

The reference target is the ZCU102 (XCZU9EG, S/N 210308BD8D4D): factory silicon
with **no security provisioned** — the **all-open baseline**, where every control
reads OFF/unprovisioned. The payoff is comparison: point the same enumeration at
another (hardened) board and the deviations from this baseline are the story. The
exhaustive flat catalog of every attribute is
[`../11-enumerated-attributes.md`](../11-enumerated-attributes.md); this volume is the
interpretive companion to it.

---

## 1. How to read this volume

Every category has the same two parts:

- **Attributes & locations** — a table of *what* each attribute is, *where* it
  lives (`BLOCK.REGISTER · 0xADDRESS · bits`), its value on this dev board, and
  what a hardened part shows instead. The address+bits column is what lets you
  locate the attribute in a raw register dump.
- **What it enables** — the concrete techniques the observed state allows, with
  prerequisites and limits.

Read every value against the **hardening continuum** — a reading that's
unremarkable on a dev kit is significant on a production device, and vice-versa:

```
Factory ──► Dev kit ──► Partial hardening ──► Production hardened
unblown      blown but   blown + partial       all gates closed,
fuses        mutable     locking               keys baked, JTAG off
```

**Scope.** This assumes the debug threat model — JTAG/DAP is reachable. On hardened
silicon that access is itself closed (`JTAG_DIS` or debug authentication), so "JTAG
can read X" only applies where JTAG is open by design or by misconfiguration. No
fault injection, side-channel, or supply-chain pre-positioning.

The fastest read on a new board is the **Security Posture Summary** (§10) — a
one-row-per-control checklist that flips OFF/dev → ON/provisioned.

---

## 2. Silicon identity

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| Device part / family | `CSU.IDCODE · 0xFFCA0040` | `0x24738093` (XCZU9EG) | identifies die + revision |
| Silicon revision | `CSU.VERSION · 0xFFCA0044` (PS_VERSION) | `3` (production) | `0`/`1` = ES1/ES2 sample |
| Per-chip unique ID | `EFUSE.DNA_0..2 · 0xFFCC100C–1014` | `0x40000000_0170CFA7_44804345` | may be read-gated |

**What it enables**

- *Pre-engagement recon.* Exact die + revision tells you which errata apply, which
  boot-image format the BootROM expects, and what prior exploit work exists.
- *Engineering-sample detection.* An ES revision in a shipped product is worth
  escalating — ES silicon often carries security errata fixed in production steppings.
- *Fleet fingerprinting.* DNA is unique per chip and readable from the eFuse shadow;
  across a fleet it builds a DNA→identity table. DNA readable on a part that should
  lock it is itself a finding.
- *Variant inference.* If the variant table claims a subsystem (e.g. VCU) but its
  base address times out — or vice-versa — the package bond differs from the catalog.

---

## 3. Secure-debug exposure (the most consequential indicator)

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| **APU secure invasive debug** | `CSU.JTAG_DAP_CFG · 0xFFCA003C · bit 2` (SPIDEN) | `1` (open) | `0` |
| **APU secure trace** | `0xFFCA003C · bit 3` (SPNIDEN) | `1` (open) | `0` |
| APU non-secure debug | `0xFFCA003C · bit 0` (DBGEN) | `1` | `0` or `1` |
| APU non-secure trace | `0xFFCA003C · bit 1` (NIDEN) | `1` | `0` |
| RPU debug / trace | `0xFFCA003C · bits 4,5` (RPU DBGEN/NIDEN) | `1` | `0` |
| DAP JTAG path | `CSU.JTAG_SEC · 0xFFCA0038 · bits [2:0]` (DAP_SEC) | `0b111` (open) | not `0b111` |
| PL-TAP JTAG path | `0xFFCA0038 · bits [5:3]` (PLTAP_SEC) | `0b111` (open) | not `0b111` |
| PMU JTAG path | `0xFFCA0038 · bits [8:6]` (PMU_SEC) | `0b000` (gated) | gated |

The whole `JTAG_DAP_CFG` reads `0xFF` and `JTAG_SEC` reads `0x3F` on this board —
maximum debug exposure. Each `JTAG_SEC` field needs the magic `0b111` to unlock
(anti-glitch: a single-bit flip can't open it).

**What it enables**

- *TrustZone inspection (SPIDEN=1).* Halt the A53 in EL3 and read everything the
  secure world holds — keys in OCM/DDR, the EL3 monitor, attestation material.
- *Secure-world key extraction.* Keys the BootROM/ATF stage into secure RAM are
  directly readable; eFuse-shadow keys too, if not separately gated.
- *EL3 implant.* Write a secure region, redirect the secure vector table into it,
  resume — the EL3 monitor then runs attacker code on every SMC.
- *Secure trace (SPNIDEN=1, SPIDEN=0).* Watch secure execution live without halt
  control — map the SMC surface, see when/where keys load.
- *Non-secure debug (DBGEN=1, SPIDEN=0).* Halt and patch the kernel/RTOS, disable
  checks, escalate privilege.
- *Pre-attack confirmation.* SPIDEN=1 makes expensive attack development (fault
  injection, supply-chain) unnecessary — confirm the easy path first.

---

## 4. eFuse secure-boot policy

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| RSA boot authentication | `EFUSE.SEC_CTRL · 0xFFCC1058 · bits [25:11]` (RSA_EN) | `0` (off) | 15-bit magic = enforced |
| Encrypt-only boot | `0xFFCC1058 · bit 2` (ENC_ONLY) | `0` | `1` |
| JTAG disable | `0xFFCC1058 · bit 5` (JTAG_DIS) | `0` | `1` |
| Secure lockdown | `0xFFCC1058 · bit 10` (SEC_LOCK) | `0` | `1` |
| PPK0 public-key hash | `EFUSE.PPK0_0..11 · 0xFFCC10A0–10CC` | all-zero | non-zero (root of trust) |
| PPK1 public-key hash | `EFUSE.PPK1_0..11 · 0xFFCC10D0–10FC` | all-zero | non-zero |
| PPK0 / PPK1 revoked | `0xFFCC1058 · [28:27] / [31:30]` (PPK_INVLD) | `0` | 2-bit magic = revoked |

Field widths are anti-glitch defenses (`RSA_EN` is 15 bits, each `PPK_INVLD` 2
bits) — a single-bit fault can't enable a bypass or revoke a key, so a *partial*
magic pattern is a red flag.

**What it enables**

- *Boot-chain enforcement profile.* `SEC_CTRL = 0` ⇒ unsigned/unencrypted boot
  accepted (full boot-chain control). RSA magic only ⇒ signature required. RSA +
  ENC_ONLY ⇒ signed-encrypted only.
- *Image substitution.* On a low/partial-enforcement target, swap in attacker
  firmware. A partial profile (`RSA_EN` set, `SEC_LOCK` clear) is still mutable.
- *AES key-extraction feasibility.* `AES_RDLK = 0` means the eFuse AES key is
  readable — recover it and all "encrypted" images decrypt offline (see §5).
- *PPK-revocation bypass.* A partial `PPK_INVLD` pattern can mean an incomplete key
  rotation — the BootROM may still trust a key meant to be revoked.
- *Fleet outlier hunting.* Inventory `SEC_CTRL` across a product line; the
  less-hardened units are the higher-value targets.

---

## 5. Key material and confidentiality

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| AES key-slot population | `CSU.AES_STATUS · 0xFFCA1000 · bits 8–11` (per-slot *_ZERO) | `0xF00` (all slots empty) | a slot's bit clear = key loaded |
| eFuse AES key present | `EFUSE.EFUSE_AES_CRC · 0xFFCC0048` | `0` (absent) | non-zero (key burned) |
| AES key read-lock | `EFUSE.SEC_CTRL · 0xFFCC1058 · bit 0` (AES_RDLK) | `0` (readable) | `1` |
| AES key write-lock | `0xFFCC1058 · bit 1` (AES_WRLK) | `0` | `1` |
| PUF provisioned | `EFUSE.PUF_CHASH · 0xFFCC1050` | `0` (unprovisioned) | non-zero |

**What it enables**

- *Key-model determination.* The combination says whether the device decrypts boot
  with an eFuse AES key, a BBRAM key, or a PUF-derived key — which decides the
  extraction approach.
- *Direct key disclosure.* "Key present (`AES_CRC` ≠ 0) + `AES_RDLK = 0`" is the
  flag: the boot-decryption key is unprotected from a debug read. Recover it →
  decrypt every encrypted image for that device, or forge new ones.
- *PUF parts.* A PUF-provisioned part derives the key at boot rather than storing
  it; extraction shifts to helper-data handling, but the enumeration still tells you
  which class of attack applies.

---

## 6. Anti-tamper

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| Tamper response policy | `CSU.CSU_TAMPER_0..12 · 0xFFCA5004–5034` | all-zero (disarmed) | non-zero per armed source |
| Tamper events latched | `CSU.TAMPER_STATUS · 0xFFCA5000` | `0` (none) | non-zero = a source fired |
| Software tamper trigger | `CSU.CSU_TAMPER_TRIG · 0xFFCA0014` | `0` | — |

Each `CSU_TAMPER_n` register wires one tamper source to a response (system reset /
secure lockdown / BBRAM + key zeroize).

**What it enables**

- *Tamper-aware operation.* The config registers show which physical / voltage /
  temperature / JTAG-activity events are armed — i.e. what *not* to trip on a live
  target, since a response may zeroize keys or lock the device down.
- *Response-gap hunting.* A device that arms some sources but leaves the
  consequential ones (key zeroize) unconfigured is a softer target.
- *Forensics.* Latched `TAMPER_STATUS` bits on a fielded unit are evidence a source
  already fired.

---

## 7. Memory and peripheral TrustZone

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| DDR TrustZone (ch. 0–5) | `DDR_XMPU0..5.CTRL/LOCK · 0xFD000000…0xFD050000` | default-region permit | regions configured + LOCK set |
| FPD TrustZone | `FPD_XMPU.CTRL/LOCK · 0xFD5D0000` | — | configured |
| OCM TrustZone | `OCM_XMPU.CTRL · 0xFFA70000` | `0x3` | regions configured |
| Peripheral protection | `XPPU.CTRL/ISR · 0xFF980000` | enabled, no violations | apertures locked down |

ZynqMP enforces memory/peripheral TrustZone with XMPU (ranges) and XPPU
(apertures) — there is no single TZASC.

**What it enables**

- *Cross-master reachability.* XMPU/XPPU config tells you whether a foothold on one
  master (PCIe, USB, a released R5) can reach secure DDR/OCM. Default/open XMPU means
  a compromised master can read secure memory.
- *Misconfiguration as a path.* A permissive region — or one with `LOCK` clear, so
  reconfigurable — is a direct route into protected memory.
- *PL-TAP exposure.* With `PLTAP_SEC = 0b111` (§3) the FPGA JTAG TAP is reachable —
  read/modify configuration memory, extract or load bitstreams.

---

## 8. Boot and runtime state

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| Boot mode | `BOOT_MODE_USER · 0xFF5E0200 · bits [3:0]` | `0` (JTAG idle) | SD/QSPI/eMMC/USB |
| Multiboot search offset | `CSU.CSU_MULTI_BOOT · 0xFFCA0010` | `0` | image-chaining offset |
| Auth / encrypt status | `CSU.CSU_STATUS · 0xFFCA0000` (BOOT_AUTH/BOOT_ENC) | `0` | set after authenticated boot |
| Boot artifacts (when booted) | OCM `0xFFFC0000` (FSBL), DDR `0x08000000` (U-Boot), `0x00200000` (kernel), … | n/a in JTAG-idle | present + dumpable |

**What it enables**

- *Strategy by state.* JTAG-idle is a clean slate (only BootROM ran). A booted
  device has FSBL/U-Boot/kernel up and secrets in DDR — larger but state-dependent.
- *Live firmware extraction.* Once an artifact is located, JTAG reads it straight
  from physical memory, bypassing software read-protection
  (`dump_image uboot.bin 0x08000000 0x100000`). Version strings in the dump drive
  version-specific targeting.
- *ATF/BL31 patch.* If ATF is at `0xFFFEA000` (OCM) or in DDR, the EL3 monitor is
  readable and — with SPIDEN + write access — patchable.
- *MULTI_BOOT image switching.* Writing `CSU_MULTI_BOOT` + reset changes which image
  the BootROM loads, given boot-media write access.

---

## 9. Power, clock, reset

**Attributes & locations**

| Attribute | Where (block · address · bits) | This board | Hardened part |
|---|---|---|---|
| Powered domains | `PMU_GLOBAL.PWR_STATE · 0xFFD80100` | only BootROM-era domains up | per running stack |
| Peripheral clocks | per-peripheral `*_REF_CTRL` (e.g. `0xFF5E0050+`) | most gated in idle | per running stack |
| Reset state | `RST_FPD_APU · 0xFD1A0104`, `RST_LPD_IOU2 · 0xFF5E0238`, … | cores/peripherals in reset | cleared per running stack |
| A53 reset-vector | `APU.RVBARADDR0L · 0xFD5C0040` | — | (used by the release recipe) |

**What it enables**

- *The A53 release primitive.* Release A53 core 0 over raw JTAG with no FSBL: set
  the landing pad in `RVBARADDR0L`, clear the `RST_FPD_APU` reset bits (ACPU0 / L2 /
  PWRON), halt — the core lands in EL3. From there: load code, read any memory,
  modify the EL3 monitor.
- *Peripheral bring-up.* Clear a peripheral's reset bit + configure its `*_REF_CTRL`
  to bring it online (e.g. UART for console capture, or to drive a device).
- *Live attack-surface map.* A peripheral both clocked and out-of-reset (UART, GEM,
  USB) is directly targetable — GEM with a live stack means network reach.
- *Selective denial.* Asserting resets or powering down domains (PL, GEMs, OCM, APU)
  is a denial primitive — useful when the defender's response runs on the same SoC.

---

## 10. The Security Posture Summary

`tools/interpret.py` distills §2–§7 into a single **Security Posture Summary**
(`rule_security_posture_summary`): one row per control, each with its location,
current value, and an `OFF/dev → ON/provisioned` verdict. Rows shown in **bold** are
the ones that most change exposure when ON — RSA enforcement, encrypt-only,
`JTAG_DIS`, AES read-lock, PPK provisioned, secure debug, tamper armed.

Read it first on any new board: all rows OFF means an all-open part; any deviation
is the lead to pursue. The exhaustive per-attribute detail behind each row is in
[`../11-enumerated-attributes.md`](../11-enumerated-attributes.md).

---

## 11. Future work

- **Hardened-device comparison (the unblocking step).** The payoff is diffing this
  all-open baseline against a known-hardened ZynqMP — which controls read differently
  and which capabilities survive each hardening fuse. Acquiring such a part is the
  highest-value next move.
- **Live per-core debug-authentication read.** The posture currently *synthesizes*
  debug authorization from `JTAG_DIS`/`DFT_DIS` + `SPIDEN`/`SPNIDEN` + `DBGEN`. A
  booted-state read of each core's CoreSight `DBGAUTHSTATUS` would confirm the live
  signal (needs core examination, so it stays out of the JTAG-idle baseline to avoid
  DAP-wedge risk).
- **AP-topology capture.** Fold `discover.tcl`'s AP enumeration into the report —
  which APs respond is itself a posture datum (a hardened part may gate the AXI
  mem-AP while leaving the APB debug AP open).
- **R5 BootROM dump.** Wake the R5 in booted state and dump from a different
  bus-master ID than the A53 (the A53-EL3 path is chip-filtered).

---

## 12. References

**AMD / Xilinx documentation**

- **UG1085** — Zynq UltraScale+ Device TRM (memory map, security model, boot flow, CSU/PMU/eFuse).
- **UG1087** — Register Reference (per-register bit decode).
- **UG1182** — ZCU102 Evaluation Board User Guide (switches, connectors, USB IDs).
- **UG1137** — MPSoC Software Developer Guide (boot chain, FSBL, ATF).

**Open-source code (authoritative bit layouts)**

- `github.com/Xilinx/qemu` — the `REG32`/`FIELD` register models that are the source
  of truth for `openocd/lib/zynqmp-regs-qemu.tcl` (`hw/misc/csu_core.c`,
  `xilinx_zynqmp_crf.c`/`crl.c`/`pmu_global.c`, `hw/nvram/xlnx-zynqmp-efuse.c`).
- `github.com/Xilinx/u-boot-xlnx` — `arch/arm/mach-zynqmp/include/mach/hardware.h` register structs.
- `github.com/Xilinx/embeddedsw` — FSBL / xilskey / xilsecure address + key-handling definitions.

**ARM**

- CoreSight Architecture Specification (DAP, APs, DBGEN/NIDEN/SPIDEN/SPNIDEN semantics).
- ARMv8-A Architecture Reference Manual (exception levels, secure-world system registers).

**Tooling**

- OpenOCD 0.12+ (`openocd.org`); JEP106 (JEDEC manufacturer IDs for IDCODE decode).

### Internal references

- `docs/11-enumerated-attributes.md` — the per-attribute catalog behind this volume.
- `docs/05-enumeration-tool.md` — the `enumerate.tcl` (18 sections) + `interpret.py` pipeline.
- `openocd/lib/zynqmp-regs-qemu.tcl` — verified register/address/bit source of truth.
- `docs/annotations/zynqmp_security.py`, `docs/findings/zynqmp_rules.py` — decoders + posture rules.

---

*End of Volume 3.*
