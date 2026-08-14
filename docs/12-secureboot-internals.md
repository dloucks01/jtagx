# ZynqMP Secure-Boot Internals — Reference (BootROM · keys · PUF · bootgen)

Source-cited reference compiled 2026-06-08 from AMD docs (UG1085 TRM, UG1137 SW
Dev Guide, UG1283 Bootgen), the Xilinx GitHub repos (embeddedsw/xilskey, bootgen,
zynqmp_fsbl), the AMD/Xilinx Security-Features wiki, and academic papers
(JustSTART arXiv:2402.09845, ePrint 2017/625). Each item notes confidence and
sources. Built to ground the project's BootROM-dump / key-extraction work.

---

## 0. The headline — is the BootROM dumpable? (the project's blocker)

**No — not by a memory read, and almost certainly not by the non-destructive
JTAG/software path at all.** Definitive (3-0 verified):

- **`0xFFFC0000` is OCM RAM, not a ROM.** OCM is 256 KB mapped at
  `0xFFFC0000–0xFFFFFFFF`. UG1137 verbatim: *"BootROM always copies First Stage
  Boot Loader (FSBL) from 0xFFFC0000 and it is not configurable… the CSU bootROM
  (CBR)… merely copies the FSBL code at a fixed OCM memory location (0xfffc0000)."*
  So everything the project read at `0xFFFC0000`/`0xFFFFC000` was **OCM**, and the
  `0xDEADBEEF`/zero we saw was OCM-region gated/unmapped fill — **not a protected
  ROM.** The long-running "A53 BootROM dump → DEADBEEF = gated ROM" interpretation
  was reading the wrong thing.
- **The CSU BootROM is internal to the CSU Security Processor Block** — a 128 KB
  ROM (CSU firmware, SHA-3 integrity-checked, tied to the triple-redundant
  MicroBlaze) plus 32 KB private CSU RAM. It is **not presented in the AXI address
  space.** There is no address you can read to get it.
- **The A53 runs no BootROM of its own.** At reset: PMU executes **PMU ROM** →
  releases the CSU → the CSU/BootROM authenticates+decrypts+copies the **FSBL into
  OCM `0xFFFC0000`** → the A53/R5 begins executing **FSBL**. "Dumping the A53
  BootROM" was never a coherent target.
- **PMU ROM** is a distinct **32 KB ROM at `0xFFD00000`** (eFuse-locked from
  software on this board — see `project_pmu_rom_efuse_locked`).

**What this means for us:** what lives at `0xFFFC0000` is the **FSBL** (the first
user-controlled boot code), not the ROM. Dumping it is still useful (real boot
code), but it is *not* the CSU BootROM. The CSU BootROM is out of reach for a
memory-read/JTAG approach.

> **Open question (the research could NOT close):** is the internal 128 KB CSU ROM
> reachable by *any* path — CSU DMA/SHA pass-through, IPI proxy, or fault/glitch?
> The verified claims only rule out the naive `0xFFFC0000` read. No path is
> confirmed; fault injection is out of scope (non-destructive). Treat CSU-ROM
> extraction as **effectively infeasible** for this project unless a new primitive
> appears.

Sources: UG1137 (xilinx2022_2 ug1137); Security-Features wiki (atlassian 18841708);
UG1085 OCM/SPB sections; EDT 2022.2 boot-and-configuration.

---

## 1. Boot flow & ROM/RAM map

| Element | Where | Readable? |
|---|---|---|
| OCM (holds FSBL post-boot) | `0xFFFC0000–0xFFFFFFFF` (256 KB) | Yes — RAM |
| PMU ROM | `0xFFD00000` (32 KB) | eFuse-locked from SW on this board |
| PMU RAM (LMB) | `0xFFDC0000` (128 KB) | Yes (writable from A53-EL3) |
| CSU BootROM | internal to CSU SPB (128 KB), **not AXI-mapped** | No |
| CSU private RAM | internal to CSU SPB (32 KB) | No |

Reset order: PMU ROM → PMU FW (in PMU RAM) ∥ CSU loads FSBL → FSBL on APU/RPU.
(UG1137; EDT 2022.x; UG1085 ch.11.)

---

## 2. Key hierarchy

| Key | What it is | Storage | SW/JTAG-readable? |
|---|---|---|---|
| **Family key** | Fixed AES key baked into the device **metal layers**, identical across the whole ZynqMP family, known only to AMD/Xilinx (request via secure.solutions@xilinx.com; not shipped with tools). Encrypts the red key → obfuscated key. | Hardware (metal) | **No — never exposed** |
| **Obfuscated / gray key** | Red AES key encrypted with the family key. | eFUSE or boot header | ciphertext only |
| **Black key** | Red AES key encrypted with the **PUF-derived KEK**. Modes: eFUSE-PUF (`efuse_blk_key`) or BH-PUF (`bh_blk_key`). Needs shutter `0x0100005E` + KEK IV in BIF. | eFUSE or boot header | ciphertext only |
| **Red (user) AES key** | The actual AES-256 boot-decryption key. | eFUSE (enc/unenc), **BBRAM (red only)**, ext NVM/BH (enc only) | see below |
| **PUF KEK** | PUF-derived key-encryption key for the black key. | derived at boot from PUF | **unresolved** — the claim that it's "never SW/JTAG-exposed" was *not* confirmed (1-2 vote) |

**AES key-source rules** (3-0): eFUSE = encrypted or unencrypted; **BBRAM =
unencrypted (red) only — cannot hold obfuscated/black keys**; external NVM/boot
header = encrypted only. **BBRAM key cannot be read back** — programming is
verified by **CRC32 only** (xilskey `XilSKey_Bbram_Program`; no read path).

Sources: Security-Features wiki (18841708); UG1283 Gray/Obfuscated-Keys; EDT 2022.1
secure-boot; embeddedsw xilskey `xilskey_bbramps_zynqmp.c`, `xilskey_bbram_example.c`.

---

## 3. PUF (matches our prior PUF-extraction finding)

- Ring-oscillator PUF, driven via CSU (`CSU_BASEADDR = 0xFFCA0000`; PUF aperture
  base `0xFFCA4000`).
- Commands: **`PUF_CMD=1` REGISTRATION**, **`PUF_CMD=4` REGENERATION**
  (xilskey `XSK_ZYNQMP_PUF_REGISTRATION (1U)` / `_REGENERATION (4U)`).
- **Shutter fixed at `0x0100005E`** (`XSK_ZYNQMP_PUF_SHUTTER_VALUE`), written in
  both paths.
- Syndrome/helper data read **word-by-word** from `PUF_WORD` (`0xFFCA4018`), gated
  by `SYN_WRD_RDY` (status bit 0). Helper struct: `u32 Chash; u32 Aux;` +
  `SyndromeData[386]` (CHASH at `[SYN_LEN-2]`, AUX at `[SYN_LEN-1]`).
- **AUX = 24 bits**, extracted as `(PUF_STATUS & 0x0FFFFFF0) >> 4`. **CHASH = 32
  bits**.
- On-device, eFUSE-PUF mode exposes the CHASH at `0xFFCC1050` and the AUX value
  in `PUF_MISC` at `0xFFCC1054`, both in the eFUSE cache (non-zero ⇒ eFUSE-PUF
  registered; **BH-PUF leaves them zero**, so zero does *not* prove PUF was never used).
- The MMIO path is proven by xilskey source; our own separately-validated finding
  shows the CSU PUF aperture is reachable from **DAP-NS** too. (The "140-byte
  formatted MODE4K syndrome" figure was **refuted** — don't cite it.)

Sources: embeddedsw `xilskey_eps_zynqmp_puf.{c,h}`, `..._hw.h`; UG1085 eFUSE map;
EDT 2022.1.

---

## 4. bootgen — what an attacker must forge

- **Authentication: RSA-4096 + SHA-3/384** (default). CSU computes SHA-3/384 of the
  PPK from external memory and compares to the **PPK digest burned in eFUSE**;
  then RSA-4096 signature checks. To forge a signed image you need a PPK whose
  SHA-3-384 hash matches the eFUSE digest **and** valid RSA-4096 signatures —
  infeasible without the private key (this is the JustSTART CVE-2023-20570 target).
  *Dev-mode boot-header auth bypasses the eFUSE PPK check (not production).*
- **Authentication Certificate (RSA-4096), fixed layout:** AC header `0x000`,
  SPK ID `0x004`, UDF `0x008` (56 B), **PPK `0x040`**, **SPK `0x480`**, SPK sig
  `0x8C0`, **BH sig `0xAC0`**, **partition sig `0xCC0`** (each modulus/sig 512 B).
- **Boot-header key/IV fields:** enc key source `0x28`, **grey/black key `0x4C`**,
  FSBL secure-header IV `0xA0`, **grey/black IV `0xAC`**.
- **Encryption: AES-256-GCM**, `.nky` key files, operational key option.

**On THIS board it doesn't matter** — `SEC_CTRL.RSA_EN=0` and PPK hashes are zero,
so the BootROM accepts **unsigned, unencrypted** images. No forgery needed; secure
boot simply isn't enforced.

Sources: Security-Features wiki; bootgen `authentication-zynqmp.{cpp,h}`,
`readimage-zynqmp.cpp`, `bootheader-zynqmp.cpp`; UG1283; zynqmp_fsbl
`xfsbl_authentication.c`.

---

## Open questions (carried from the research)
1. Is the internal CSU 128 KB BootROM reachable by **any** path (CSU DMA/SHA
   pass-through, IPI, fault)? Only the naive OCM read is ruled out.
2. Exact eFUSE/boot-header **bit** packing of PUF CHASH/AUX vs the in-memory struct.
3. Does PUF REGISTRATION stay unfiltered from JTAG on **production** silicon with
   security eFUSEs burned?
4. Full `encryptionKeySource` (BH `0x28`) enumeration + the CBR's key-source decode.

## See also
- `docs/11-enumerated-attributes.md` — on-chip attribute catalog (the live readback side).
- memory `project_r5_bootrom_dump_result` (why 0xFFFC0000 isn't ROM), `project_pmu_rom_efuse_locked`, `project_puf_extractable_via_jtag`, `project_mission`.
