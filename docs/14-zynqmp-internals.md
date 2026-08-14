# ZynqMP Secure-Boot Internals — Comprehensive Reference

This document is a single, consolidated technical reference for the AMD/Xilinx Zynq UltraScale+ MPSoC (ZynqMP) secure-boot stack — the BootROM/PMU/CSU root of trust, the FSBL software trust chain, the crypto engines, the key hierarchy, the boot-image format, the non-volatile key/policy stores (eFuse/BBRAM), the runtime memory/peripheral isolation fabric (XMPU/XPPU), the PMU power-management API, and the JTAG/debug security gates that ultimately enclose all of it. It merges the official vendor documentation and source (UG1085/UG1137/UG1283/UG1087, the `embeddedsw` FSBL/PMUFW/xilskey/xilsecure libraries, the bootgen tool, and the project's QEMU register model) with this project's own empirical, JTAG-only, non-destructive measurements on a single physical part.

## How to read this / scope

- **Two voices, kept distinct.** Statements are either (a) **vendor-documented / source-traced** (citations to AMD headers, source, QEMU model, or AMD user guides) or (b) **empirically observed on board 210308BD8D4D** (an XCZU9EG ZCU102 dev part, captured 2026-05/06). Empirical findings are always labeled and tied to a capture file. The closing summary separates the two explicitly.
- **The board is unprovisioned dev silicon.** `SEC_CTRL = 0`: no RSA enforcement, no encryption-only, no JTAG disable, no keys, no PPK digests, no PUF helper data. Consequently the *enforcement* machinery described below is almost entirely **dormant** on this part — it is described from source, and the board demonstrates only the *open baseline*.
- **Method constraints.** Everything empirical here was obtained over JTAG (OpenOCD) via the DAP, mostly in "JTAG-idle" (no boot image; part waiting in JTAG boot mode) and in some cases on a booted SD/PetaLinux system. The work is **non-destructive** (no eFuse burns, no BBRAM zeroize) and uses **no side-channel hardware** (no DPA/EM/fault injection). Claims about secure-path behavior are therefore source-derived, not reproduced on hardware.
- **Address discipline (cardinal rule).** No address is asserted from memory alone. Where the QEMU register model does not cover a block, that is flagged and the alternative provenance (vendor header / UG / capture) is named. Where two captures or two sources disagree, the contradiction is **flagged in-line** rather than silently resolved.

---

## Table of contents

1. [Boot flow & BootROM (reset → PMU ROM → CSU BootROM → FSBL)](#1-boot-flow--bootrom)
2. [FSBL (First Stage Boot Loader)](#2-fsbl-first-stage-boot-loader)
3. [CSU & crypto engines (AES-GCM, SHA-3, RSA, PCAP, SSS, control page)](#3-csu--crypto-engines)
4. [PUF (Physically Unclonable Function)](#4-puf-physically-unclonable-function)
5. [Key hierarchy (family, obfuscated/gray, black, red, PUF KEK)](#5-key-hierarchy)
6. [Bootgen & boot-image format (boot header, IHT/PHT, AC)](#6-bootgen--boot-image-format)
7. [eFuse & BBRAM (non-volatile key & policy store)](#7-efuse--bbram)
8. [PMU firmware, the PM API, and the APU↔PMU IPI channel](#8-pmu-firmware-pm-api--ipi)
9. [Memory & peripheral TrustZone (XMPU / XPPU)](#9-memory--peripheral-trustzone-xmpu--xppu)
10. [JTAG & debug security (the open DAP is the trust boundary)](#10-jtag--debug-security)
- [Consolidated sources](#consolidated-sources)
- [Empirical vs vendor-documented summary](#empirical-vs-vendor-documented)
- [Cross-section contradictions flagged](#cross-section-contradictions-flagged)

---

## 1. Boot flow & BootROM

### 1.1 What it is and its role in secure boot

On ZynqMP (XCZU9EG) there is **no single "the BootROM."** Boot is split across three stages, and confusingly two of the three are *not* the thing you can read at `0xFFFC0000`:

1. **PMU ROM** — the very first code to run after POR. A 32 KB mask ROM on the PMU's triple-redundant MicroBlaze. It does power-on self-test, applies the power-up sequence, samples the boot-mode pins, then releases the CSU. Mapped at **`0xFFD00000`** (PMU instruction ROM), with PMU RAM/LMB at **`0xFFDC0000`** (128 KB).
2. **CSU BootROM (CBR)** — the secure-boot engine, running on the CSU's own triple-redundant MicroBlaze inside the **CSU Security Processor Block (SPB)**. It reads the boot device, parses the boot header, authenticates (RSA-4096 + SHA-3/384) and/or decrypts (AES-256-GCM) the FSBL partition, and **copies the plaintext FSBL into OCM at the fixed address `0xFFFC0000`**. This ROM is **internal to the CSU SPB (≈128 KB ROM + ≈32 KB private CSU RAM) and is NOT presented in the AXI address space** — there is no AXI address that returns its contents.
3. **FSBL** — first *user-controlled* boot code. After the CBR validates and copies it, the CBR releases the selected APU/RPU core, which begins executing FSBL **from OCM `0xFFFC0000`**. Vendor source: `embeddedsw/.../zynqmp_fsbl/`. This is the only stage with readable source and live-readable code.

Reset order (UG1085 ch.11; UG1137; docs/12 §0-1): **PMU ROM → (PMU FW in PMU RAM ∥ CSU/CBR loads FSBL into OCM) → FSBL on APU/RPU**. The A53 application cores run **no BootROM of their own** — at release they fetch FSBL from OCM. "Dump the A53 BootROM" was never a coherent target (docs/12:29-31; memory `project_bootrom_dumpability_resolved.md`).

### 1.2 The headline correction (RESOLVED 2026-06-08)

The long-running mission framing "dump the BootROM at `0xFFFC0000`/`0xFFFFC000`" was **reading the wrong region**:

- **`0xFFFC0000` is OCM RAM, not ROM.** OCM = 256 KB at `0xFFFC0000–0xFFFFFFFF`. UG1137 verbatim: the CSU BootROM *"merely copies the FSBL code at a fixed OCM memory location (0xfffc0000)."* Whatever is read there is **FSBL or stale OCM fill**, never a protected ROM (docs/12:11-38).
- **`0xFFFFC000` (the old `ADDR_BOOTROM`) is top-of-OCM**, not the CSU ROM. All-`0xDEADBEEF` results historically read as "gated BootROM" were the chip's **gated/unmapped-AXI fill** plus the dump harness's own `safe_rd` ERR→`0xDEADBEEF` sentinel — an empty OCM-top region, not a locked ROM (memory `project_r5_bootrom_dump_result.md`).
- **The CSU BootROM is internal to the CSU SPB and not AXI-mapped** — infeasible to extract via any non-destructive JTAG/software path. The only open (unconfirmed, out-of-scope) exotic paths are CSU DMA/SHA pass-through, IPI proxy, or fault injection (memory `project_bootrom_dumpability_resolved.md`).

What *is* reachable: the FSBL in OCM (real code), the PMU ROM **digest/version** (not the ROM bytes), and the CSU **ROM_DIGEST** register (a SHA-3-384 of the CSU ROM, see §3).

### 1.3 Key registers / addresses (boot-flow view)

| Register | Address | Source | Role in boot |
|---|---|---|---|
| OCM (FSBL landing) | `0xFFFC0000–0xFFFFFFFF` (256 KB) | UG1137; docs/12:17 | CBR copies plaintext FSBL here; APU/RPU starts here |
| PMU instruction ROM | `0xFFD00000` (32 KB) | docs/12:32,57; mem `reference_pmu_internals` | First-boot PMU code (mask ROM) |
| PMU RAM (LMB) | `0xFFDC0000` (128 KB) | docs/12:58 | PMU FW load target |
| `CSU_BASEADDR` | `0xFFCA0000` | xfsbl_hw.h:71 | CSU register block base |
| `CSU.IDCODE` | `0xFFCA0040` | xfsbl_hw.h:168; qemu:1985 | Silicon ID / part code |
| `CSU.VERSION` | `0xFFCA0044` | xfsbl_hw.h:118 | Silicon rev + PMU BootROM version; `PLATFORM` = bits 12-15 |
| `CSU.CSU_MULTI_BOOT` | `0xFFCA0010` | xfsbl_hw.h:125; qemu:1811 | Golden-image / fallback search offset |
| `CSU.CSU_ROM_DIGEST_0..11` | `0xFFCA0050–0xFFCA007C` (12×32b) | xfsbl_hw.h:130-134; qemu:2001-2048 | SHA-3-384 digest of CSU ROM (see §3) |
| `CSU.AES_RESET` | `0xFFCA1010` | xfsbl_hw.h:91 | FSBL holds AES engine in reset early (init.c:294,360) |
| `CSU.SHA_RESET` | `0xFFCA2004` | xfsbl_hw.h:139 | FSBL holds SHA-3 engine in reset early (init.c:295,362) |
| `CRL_APB.BOOT_MODE_USER` | `0xFF5E0200`, mask `0xF` | xfsbl_hw.h:272-273 | Boot-mode pin readout (`BOOT_MODE` bits 0-3) |
| `CRL_APB.BOOT_MODE_POR` | `0xFF5E0204` | qemu:1599 | Latched POR boot mode |
| `CRL_APB.RESET_REASON` | `0xFF5E0220` | xfsbl_hw.h:288 | PMU_SYS_RESET (bit 2 / `0x4`), PSONLY (bit 3 / `0x8`) |
| `CRL_APB.RESET_CTRL` | (CRL_APB base + offset) | xfsbl_main.c:548-550 | `SOFT_RESET` for FSBL fallback |

Boot-mode encodings the FSBL switches on (xfsbl_initialization.c:939-972, xfsbl_main.c:443-449): `XFSBL_JTAG_BOOT_MODE` (goes straight to handoff, no partition load), `QSPI24`, `QSPI32`, `NAND`, `SD0`, `EMMC`, `SD1`, `SD1_LS`, `USB`. On board 210308BD8D4D the pins read `BOOT_MODE=0x0` (JTAG mode, §1.6).

### 1.4 Boot-time behavior (FSBL 4-stage machine, BootROM-facing parts)

The FSBL is a 4-stage state machine in `xfsbl_main.c:101-338` (full FSBL detail in §2):

- **STAGE1 — `XFsbl_Initialize`**. First action: place AES and SHA engines in reset (`CSU_AES_RESET`/`CSU_SHA_RESET`, init.c:294-295) — the CBR may have left them active. `XFsbl_GetResetReason()` reads `CRL_APB_RESET_REASON` (init.c:240); PSONLY bit is read-then-cleared by writing it back (init.c:242-245). System config (`XFsbl_SystemInit`, psu_init) runs unless master-only reset (init.c:316-321). WDT init is **skipped in JTAG boot mode** (init.c:341-354). The **FSBL banner** prints `MultiBootOffset` from `CSU_CSU_MULTI_BOOT` and platform from `CSU_VERSION.PLATFORM` (xfsbl_main.c:367-398).
- **STAGE2 — `XFsbl_BootDeviceInitAndValidate`**. For **JTAG boot mode it returns `XFSBL_STATUS_JTAG`** (init.c:970): both RPU cores marked usable (`XFSBL_R5_USAGE_STATUS_REG`, main.c:162-165) and the loop **jumps straight to STAGE4 (handoff), skipping all partition loading** (main.c:156-170). For real boot devices it sets `PartitionNum=1` (partition 0 is the FSBL itself) and proceeds to STAGE3.
- **STAGE3 — `XFsbl_PartitionLoad`** (loop). Per-partition copy + authenticate + decrypt into DDR/TCM/PL.
- **STAGE4 — `XFsbl_Handoff`**. Releases target cores to entry points (ATF/U-Boot/bare-metal).

**Fallback / MultiBoot:** on any stage error, `XFsbl_ErrorLockDown` (main.c:417) writes the error to `XFSBL_ERROR_STATUS_REGISTER_OFFSET` (main.c:431) and, for fallback-capable modes (QSPI/NAND/SD/eMMC, main.c:443-449), calls `XFsbl_FallBack` → `XFsbl_UpdateMultiBoot(MultiBoot+1)` (main.c:497-501), writing `CSU_CSU_MULTI_BOOT` (main.c:526) and triggering a **System Soft Reset** via `CRL_APB_RESET_CTRL` (main.c:548-550). This re-enters the CBR, which re-searches the boot device at the incremented offset — the golden-image mechanism. JTAG boot mode is **not** fallback-capable; it spins (main.c:452-462).

### 1.5 Security properties & gates (boot-flow view)

- **CSU ROM integrity:** the CBR self-checks its ROM with SHA-3-384; the 384-bit result is exposed in `CSU.CSU_ROM_DIGEST_0..11` (`0xFFCA0050–7C`). This is a **digest, persistent and DAP-NS readable**, but *not* the ROM bytes (memory `project_control_bits_findings`).
- **Family key:** the AES family key is baked into device metal layers, family-wide, AMD-only, and **never SW/JTAG-readable** (docs/12:71). See §5.
- **Authentication:** CBR enforces RSA-4096 + SHA-3/384 against the eFUSE PPK digest in production; dev-mode boot-header auth bypasses the eFUSE PPK check (docs/12:114-119; see §6 `BH_RSA`).
- **PMU ROM read gate:** AXI mem-AP reads of the PMU instruction ROM (region base `0xFFD00000`) are blocked by a master-aware AXI filter that operates independently of the security-gate field `CSU.JTAG_SEC.SSSS_PMU_SEC` — writing `0x1FF`/`0b111` to `0xFFCA0038` (opening PMU_SEC) succeeds but does **not** grant DAP AXI access to the ROM; the read still wedges the DAP (memory `project_pmu_rom_efuse_locked.md`, N1 re-test 2026-05-28). See also §10 (eFuse-locked JTAG_SEC upper bits) and §8 (PMU IPI proxy ACL).

### 1.6 Empirical findings (board 210308BD8D4D)

**Boot-mode / reset state (JTAG-idle golden capture, tests/golden/zcu102-jtag-idle/enumerate.md):**
- `CRL_APB.BOOT_MODE_USER (0xFF5E0200) = 0x00000000` → `BOOT_MODE=0x0` = **JTAG boot mode**. The CBR found no boot image; the part waits for JTAG, OCM unpopulated.
- `CRL_APB.BOOT_MODE_POR (0xFF5E0204) = 0x00000000`.
- `CRL_APB.RESET_REASON (0xFF5E0220) = 0x00000001`.
- `CSU.IDCODE (0xFFCA0040) = 0x24738093` (XCZU9EG).
- `CSU.VERSION (0xFFCA0044) = 0x00000513`.
- `CSU.CSU_MULTI_BOOT (0xFFCA0010) = 0x00000000` (no fallback has occurred).
- `CSU.CSU_ROM_DIGEST_0..11 (0xFFCA0050–7C)` non-zero: `0x26042731 0x0B5A3BDB 0x7FBEE59B 0x8327B4E3 0xF172C94B 0x5ECF6519 0xDC443F4C 0xA8FC2D0E 0xCF5E3889 0xDDCE3F4F 0xCDE7B664 0x2937CB90` (reports/csu-fullmap-2026-06-08-134631.md). The live SHA-3-384 of *this* part's CSU ROM — a forensic fingerprint, not the ROM contents.

**OCM `0xFFFC0000` — the decisive demonstration that it is RAM, not ROM:**
- **JTAG-idle (no FSBL):** reports/enumerate-2026-06-08-134143.md reads `0xfffc0000: 14000000 deadbeef deadbeef deadbeef`, same `0xDEADBEEF` fill across `0xFFFC8000`, `0xFFFD0000`, `0xFFFE0000`, `0xFFFF0000`, `0xFFFFC000`. OCM empty/gated → `0xDEADBEEF` (safe-read/unmapped-AXI sentinel).
- **Fresh-boot (FSBL present):** dumps/ocm-0xFFFC0000-128k-freshboot-2026-06-08-125258.bin is 131072 B, **entropy 5.68 bits/byte, 0 `0xDEADBEEF` words**, first word `0x1400024e` = `b 0xfffc0938` (vector-table branch). Disassembly (dumps/fsbl-freshboot.disasm) shows a real ARM64 exception-vector table at `0xFFFC0000/0200/0280/0300/0380` and exception-handler code (`mrs x0, esr_el3` / `mrs x1, cptr_el3` at `0xFFFC03B0+`) — genuine FSBL/runtime code.
- Same address, two states, two contents ⇒ **`0xFFFC0000` is writable RAM (OCM)**, conclusively not a ROM. Falsifies the old "DEADBEEF = gated BootROM" reading.

**R5 capstone dump (dumps/bootrom-via-pmu-r5-bootrom-2026-06-08-113330.bin):** the R5 wake→execute→dump pipeline works end-to-end (PMU IPI REQUEST_NODE/WAKEUP RPU_0 succeeded, R5 ran the copy stub, JTAG read back 16 KB), but the dump of `0xFFFFC000` was ~52% zeros then ~45% `0xDEADBEEF` (entropy 2.15) — R5 sees top-of-OCM as zero-fill where DAP sees `0xDEADBEEF`; **neither reads real ROM**. Delivery vehicle proven; *target address was wrong* (memory `project_r5_bootrom_dump_result.md`). The R5-wake primitive itself is detailed in §8.

### 1.7 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

**Reachable:** FSBL in OCM (`0xFFFC0000`, 256 KB) on a booted board — full real boot code, dumpable/disassemblable (useful for FSBL TOCTOU/logic bugs; contains no embedded secret keys). CSU/CRL boot-state registers (`BOOT_MODE`, `RESET_REASON`, `MULTI_BOOT`, `IDCODE`, `VERSION`, full `ROM_DIGEST`), all DAP-NS readable. Fallback/MultiBoot manipulation in principle (write `CSU_CSU_MULTI_BOOT` + soft-reset), meaningful only with a real boot image present.

**Blocked / infeasible (by design):** CSU BootROM bytes (internal to SPB, not AXI-mapped; no memory-read/DMA/DAP path; effectively unreachable without fault injection). PMU ROM bytes at `0xFFD00000` (master-aware AXI filter, blocked even after PMU_SEC opened). Family/obfuscated keys (hardware-only, never exposed). **Honest caveat:** no positive primitive for CSU-ROM or PMU-ROM extraction was found; the negative result is well-supported (two-state OCM proof + master-filter wedge) but "no exotic path exists" is *not proven* — CSU DMA/SHA pass-through and IPI-proxy paths remain untested, and fault injection is excluded by the project's non-destructive constraint.

---

## 2. FSBL (First Stage Boot Loader)

### 2.1 What it is and its role in secure boot

The FSBL is the first user-controllable code in the chain. The CSU BootROM authenticates/decrypts the FSBL partition and copies it into OCM at the **fixed, non-configurable address `0xFFFC0000`**, then releases a PS CPU (A53 or R5) to execute it (docs/12:17-30). The FSBL is then the *root of the software trust chain*: it (a) does PS/PLL/DDR/clock init via the Vitis-generated `psu_init`, (b) reads boot/image/partition headers, (c) **authenticates (RSA-4096 over SHA-3-384) and decrypts (AES-256-GCM) every subsequent partition** (ATF/BL31, U-Boot, PMUFW updates, the PL bitstream, ultimately the OS — VxWorks in this project), and (d) hands off.

**Key architectural fact:** the FSBL is **not** what programs the JTAG/DAP security gates — those are written by the `psu_init` register table invoked during stage-1 init. The FSBL *application* source (`zynqmp_fsbl/src/`) contains no write to `CSU.JTAG_SEC`/`CSU.JTAG_DAP_CFG`; grepping the captured 2025.1 FSBL OCM image (`dumps/fsbl-freshboot.disasm`) for those addresses returns nothing. The observed JTAG-gate state is therefore the *BootROM default* (untouched by `psu_init` on a non-secure design), not an FSBL action (see §2.6, §10).

The captured image is a real 2025.1 FSBL: the OCM dump contains the banner `"Zynq MP First Stage Boot Loader"` / `"Release %d.%d ..."` (`XFsbl_PrintFsblBanner`, xfsbl_main.c:362-365) and links xilsecure 2025.1 server objects (`xsecure_aes.c`, `xsecure_rsa_core.c`, `xsecure_sha.c`).

### 2.2 The stage machine (xfsbl_main.c)

`main()` is an explicit 4-stage state machine (xfsbl_main.c:101-338) — see §1.4 for the BootROM-facing summary. Key points:

- **STAGE1** `XFsbl_Initialize()` — system init incl. `psu_init`, reset-reason, boot-mode latch.
- **STAGE2** `XFsbl_BootDeviceInitAndValidate()` — picks primary/secondary boot device, reads headers. **JTAG boot mode special-cased**: `XFSBL_STATUS_JTAG` → mark both R5 cores usable in `XFSBL_R5_USAGE_STATUS_REG`, jump straight to STAGE4, *load zero partitions* (xfsbl_main.c:148-170). No image, no auth, no decrypt.
- **STAGE3** `XFsbl_PartitionLoad()` — per-partition load + validate loop (partitions `1..N-1`; partition 0 is the FSBL itself) (xfsbl_main.c:194-263).
- **STAGE4** `XFsbl_Handoff()` — jump to ATF/applications.
- **STAGE_ERR** `XFsbl_ErrorLockDown()` — on failure writes error code, and for fallback-capable modes increments `CSU_CSU_MULTI_BOOT` + soft-reset; for non-fallback modes (incl. JTAG) spins (xfsbl_main.c:417-566).

### 2.3 Authentication flow (xfsbl_authentication.c)

Standard ZynqMP two-tier RSA chain (PPK → SPK → partition), all SHA-3-384 (`HashLen = XFSBL_HASH_TYPE_SHA3`, 48 bytes):

1. **Boot-header / PPK** — `XFsbl_BhAuthentication()` (:579-698). If eFUSE `RSA_EN` blown, calls `XFsbl_PpkVer()`: reads the 384-bit eFUSE PPK hash (PPK0 from `EFUSE_PPK0`, PPK1 from `EFUSE_PPK1`, 12 words each, `XFsbl_ReadPpkHash` :433-451), SHA-3-hashes the in-image PPK, and `XFsbl_CompareHashs()` word-compares them (:548-561). PPK0/PPK1 revocation enforced via `EFUSE_SEC_CTRL_PPK0_RVK_MASK`/`PPK1_RVK_MASK` (:481-498). The verified PPK is cached in `EfusePpkKey[]` (:614-615).
2. **SPK** — `XFsbl_SpkVer()` (:84-233): SHA-3 over the SPK+auth-header, `XSecure_RsaPublicEncrypt()` of the SPK signature with the PPK, then `XSecure_RsaSignVerification()`. If `RSA_EN` set, SPK revocation checked against `EFUSE_SPKID` (SPK-ID-fuse mode) or a per-bit user-eFUSE at `XFSBL_USER_EFUSE_ADDR` (user-eFUSE-revocation mode) (:183-229).
3. **Partition** — `XFsbl_PartitionSignVer()` (:248-375): SHA-3 over `PartitionLen - XFSBL_AUTH_CERT_MIN_SIZE` plus the AC-minus-signature; RSA-verify with the trusted SPK. DDR-less bitstream loads stream chunk-by-chunk through OCM via `XFsbl_ShaUpdate_DdrLess()` (:717-780). All RSA is `XSECURE_RSA_4096_KEY_SIZE`.

**Downgrade guard:** boot-header authentication (bh_auth) is **rejected when eFUSE RSA is blown** — `XFSBL_ERROR_BH_AUTH_IS_NOTALLOWED` (xfsbl_initialization.c:1259-1266). This prevents a boot-header-controlling attacker from substituting their own PPK once the device is RSA-provisioned.

### 2.4 Secure / non-secure decision and decryption

Per-partition decision in `XFsbl_PartitionValidation()` (xfsbl_partition_load.c:1141-1238):

- **Encryption** on if partition-header encryption attribute == `XIH_PH_ATTRB_ENCRYPTION` (:1189-1209). If requested but FSBL built without `XFSBL_SECURE` → `XFSBL_ERROR_SECURE_NOT_ENABLED`.
- **Authentication** on only if `FsblInstancePtr->AuthEnabled == TRUE` *and* the partition carries an RSA signature (:1230-1238). `AuthEnabled` is set in init when **either** eFUSE `RSA_EN` is blown **or** the boot-header RSA attribute is set (xfsbl_initialization.c:1268-1272).
- **eFUSE ENC_ONLY** (`EFUSE_SEC_CTRL_ENC_ONLY_MASK`, bit 2) forces every image to be treated as encrypted (xfsbl_initialization.c:1234-1242, recorded into `PMU_GLOBAL_GLOB_GEN_STORAGE5`).

Decryption setup: `XSecure_AesInitialize(&SecureAes, &CsuDma, XSECURE_CSU_AES_KEY_SRC_DEV, FsblIv, NULL)` (xfsbl_partition_load.c:1300-1301). Key source `_DEV` = the **device key** (BBRAM-or-eFUSE AES-256 selected by the BootROM per the boot-header key-source field); the FSBL never sees the raw key, it only commands the CSU AES engine (see §3, §5). The IV comes from the boot header (`Iv[]` copied at xfsbl_initialization.c:1214 from `ReadBuffer + XIH_BH_IV_OFFSET`), per-partition-adjusted by the low byte of `PartitionHeader->Iv` (:1196-1199). Actual decrypt is `XSecure_AesDecrypt()` over CSU-DMA (:1489, :1556, :1577). All of this is `#ifdef XFSBL_SECURE`; if off, crypto paths are compiled out entirely.

### 2.5 Key registers/addresses the FSBL touches (from xfsbl_hw.h)

| Symbol | Address | Role |
|---|---|---|
| `CSU_BASEADDR` | `0xFFCA0000` | CSU base (xfsbl_hw.h:71) |
| `CSU_CSU_SSS_CFG` | `0xFFCA0008` | Secure-stream-switch source select; FSBL writes `0x5000` to route SHA (:76-80, used xfsbl_initialization.c:2085) |
| `CSU_CSU_MULTI_BOOT` | `0xFFCA0010` | Multiboot offset; incremented on fallback (:125, xfsbl_main.c:497,526) |
| `CSU_IDCODE` | `0xFFCA0040` | Silicon/part ID (:168) |
| `CSU_VERSION` | `0xFFCA0044` | PS version (:118) |
| `CSU_ROM_DIGEST_ADDR_0..11` | `0xFFCA0050–0x7C` | BootROM SHA-3-384 digest (:130-134) |
| `CSU_SHA_*` | `0xFFCA2000–0x2010+` | SHA-3 engine start/reset/done/digest (:139-157) |
| `CSU_PCAP_*` | `0xFFCA3000–0x3010` | PL config interface (:97-164) |
| `EFUSE_SEC_CTRL` | `0xFFCC1058` | Secure-boot policy; masks: `ENC_ONLY=0x4`, `RSA_EN=0x03FFF800`, `PPK0_RVK=0x18000000`, `PPK1_RVK=0xC0000000` (:189-193) |
| `EFUSE_PPK0 / PPK1` | `0xFFCC10A0 / 0xFFCC10D0` | eFUSE PPK hashes (:204-207) |
| `EFUSE_SPKID` | `0xFFCC105C` | SPK-ID revocation (:210) |

`EFUSE_SEC_CTRL` is `EFUSE_BASEADDR(0xFFCC0000)+0x1058` = **`0xFFCC1058`**, matching the board capture and correcting an earlier wrong-address claim in project memory (see §7).

The **JTAG_SEC (`0xFFCA0038`)** and **JTAG_DAP_CFG (`0xFFCA003C`)** registers are *not referenced anywhere in the FSBL app source* — owned by `psu_init`/BootROM. Full field layout in §10.

### 2.6 Security properties and gates (FSBL view)

- Trust is rooted in immutable eFUSEs (PPK hash + `RSA_EN`) and the BootROM; the FSBL inherits and extends it to downstream partitions.
- Downgrade resistance: bh_auth disallowed once `RSA_EN` blown; per-key revocation via PPK_RVK/SPK-ID/user-eFUSE.
- Crypto offloaded to CSU hardware (SHA-3, RSA-4096 modexp, AES-256-GCM via CSU-DMA); the device AES key is never software-visible.
- All security behavior is *conditional on eFUSE/boot-header bits*. On an unprovisioned chip (`RSA_EN=0`, `ENC_ONLY=0`) the FSBL loads partitions **plaintext and unauthenticated** — `AuthEnabled` FALSE, `IsEncryptionEnabled` FALSE.

### 2.7 Empirical findings (board 210308BD8D4D)

The board is an **open / non-secure** dev part; the FSBL takes the no-crypto path:

- **eFUSE SEC_CTRL = `0x00000000`** (reports/enumerate-2026-06-08-134143.md:83, read at the correct `0xFFCC1058`): `RSA_EN=0`, `ENC_ONLY=0`, `JTAG_DIS=0`, `SEC_LOCK=0`, both PPK invalidate/revoke fields `0`. → FSBL sets `AuthEnabled=FALSE`; every partition loads unauthenticated/plaintext.
- **JTAG gates wide open**: `CSU.JTAG_SEC = 0x0000003F` (DAP_SEC=0x7, PLTAP_SEC=0x7) and `CSU.JTAG_DAP_CFG = 0x000000FF` (all APU+RPU debug-auth bits set) (reports/csu-fullmap-2026-06-08-134631.md; decoded in enumerate-2026-06-08-134143.md:59-69). BootROM default, untouched — consistent with FSBL source never writing these (full decode §10).
- **Live FSBL image captured**: `dumps/ocm-...-freshboot...bin` (128 KB from `0xFFFC0000`) is the running 2025.1 FSBL (banner + xilsecure objects); `dumps/fsbl-freshboot.disasm` is its AArch64 disassembly (vector table at `0xFFFC0000`, EL3 exception handlers). Contains **no JTAG_SEC/DAP_CFG access** — corroborating that gate-programming is psu_init/BootROM, not the FSBL.
- **CSU crypto engines idle/unused**: `CSU_SSS_CFG` (see §3 contradiction note), `AES_STATUS=0x0F00` (KEY_LOAD/KUP/KEY_CLR all zero), `SHA_START=0`, `PCAP` showing a configured PL — no in-progress secure load (reports/csu-surface-2026-06-08-131838.md). BootROM did populate `CSU_ROM_DIGEST` and the SHA digest mirror.

### 2.8 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Reachable now:** secure boot is off and DAP/APU debug fully enabled → JTAG can halt the A53/R5 and read/modify the FSBL in OCM at `0xFFFC0000` directly (no integrity check after the BootROM copy). Already dumped. Can single-step/patch the stage machine or skip auth/decrypt branches on this open part. (This is attacking *our own unprovisioned board*, not a break of the secure design.)
- **What the FSBL does NOT give us:** never exposes the device AES key (CSU-internal). On a *provisioned* part, `RSA_EN`/`ENC_ONLY` would force auth+decrypt with JTAG gates closed by `psu_init`, putting the FSBL out of JTAG reach during secure boot. The hardening primitives (closing JTAG_SEC/DAP_CFG, blowing RSA_EN) live in psu_init/eFUSE, not the FSBL app — the FSBL itself is not the lever for a secure-boot bypass.
- **Honest gap:** the secure path was not exercised (no signed/encrypted image built yet), so auth/decrypt claims are source-derived. The downgrade guard (`XFSBL_ERROR_BH_AUTH_IS_NOTALLOWED`) and PPK-revocation logic are read from source only.

---

## 3. CSU & crypto engines

### 3.1 What it is and its role in secure boot

The **Configuration Security Unit (CSU)** is ZynqMP's hardware root-of-trust block. It contains the triple-redundant "CSU processor" running the (internal, non-AXI-mapped) 128 KB CSU BootROM, plus memory-mapped crypto engines that the BootROM, FSBL, and PMU/XilSecure software drive to **authenticate (RSA-4096 + SHA-3/384), decrypt (AES-256-GCM), and configure the PL (PCAP)** during boot. Data is routed between engines and the CSU DMA by the **Secure Stream Switch (SSS)**, a crossbar that prevents arbitrary plaintext/key taps. All engines hang off the CSU window beginning at `XSECURE_CSU_REG_BASE_ADDR = 0xFFCA0000` (xsecure_sss.h:47).

### 3.2 Address map

(Traces to vendor headers, the QEMU model, or captures.)

| Block | Base | Source |
|---|---|---|
| CSU control page (STATUS/CTRL/SSS/multiboot/JTAG gates/IDCODE/ROM-digest) | `0xFFCA0000` | xsecure_sss.h:47; qemu 1772–2036 |
| Secure Stream Switch config (`CSU_SSS_CFG`) | `0xFFCA0008` | xsecure_sss.h:49 (`XSECURE_SSS_ADDRESS`) |
| **AES-GCM engine** | `0xFFCA1000` | xsecure_aes_hw.h:41 (`XSECURE_CSU_AES_BASE`) |
| **SHA-3/384 engine** | `0xFFCA2000` | xsecure_sha_hw.h:38 (`XSECURE_CSU_SHA3_BASE`) |
| **PCAP** PL-config interface; `PCAP_STATUS` | `0xFFCA3010` | block base `0xFFCA3000`; xsecure_aes_hw.h:43 |
| **PUF** controller | `0xFFCA4000` | docs/12 §3; xilskey (see §4) |
| **Tamper** block | `0xFFCA5000` | qemu 2397–2466 (TAMPER_STATUS/CSU_TAMPER_0..13) |
| **RSA core** (NOT in the 0xFFCAxxxx window) | `0xFFCE0000` | xsecure_rsa_hw.h:33 (`XSECURE_CSU_RSA_BASE`) |
| **CSU DMA** (CSUDMA): SRC ch +0x00, DST ch +0x80 | `0xFFC80000` | probe csu-surface §4 |

Cardinal-rule note: the RSA core is documented by the vendor header at **`0xFFCE0000`**, a full 0x40000 above the CSU crypto window. Our probes did not characterize `0xFFCE0000`, so all RSA statements here are source-derived, not empirically confirmed on this board.

### 3.3 AES-256-GCM engine (0xFFCA1000)

Offsets (xsecure_aes_hw.h:52–74): `AES_STS 0x00`, `KEY_SRC 0x04`, `KEY_LOAD 0x08`, `START_MSG 0x0C`, `RESET 0x10`, `KEY_CLR 0x14`, `CFG 0x18` (0=decrypt, 1=encrypt — aes.h:147–148), `KUP_WR 0x1C`, `KUP_0..7 0x20–0x3C` (256-bit User Key), `IV_0..3 0x40–0x4C`.

Key-source select (`KEY_SRC`): `XSECURE_CSU_AES_KEY_SRC_KUP = 0x0`, `XSECURE_CSU_AES_KEY_SRC_DEV = 0x1` (aes.h:119–120). Only these two are valid to the driver (asserted aes.c:160–161). "DEV" = hardware-managed device key (eFUSE/BBRAM/black-key path); KUP = software-loaded key in KUP_0..7. The boot/family/PUF key sources are *not* selectable by software — routed internally by the BootROM (the central confidentiality property). The selection register is **`CSU.AES_KEY_SRC` at `0xFFCA1004`**, `KEY_SRC[3:0]` (qemu 2099–2105); key load is `CSU.AES_KEY_LOAD` at `0xFFCA1008` bit 0.

`AES_STS` bit decode (aes.h:103–116): bit0 `AES_BUSY`, bit1 `AES_READY`, bit2 `AES_DONE`, **bit3 `GCM_TAG_OK`**, bit4 `KEY_INIT_DONE`, **bit8 `AES_KEY_ZERO`**, **bit9 `KUP_ZEROED`**, **bit10 `BOOT_KEY_ZERO`**, **bit11 `OKR_ZERO`**.

Boot-time flow (source): `XSecure_AesDecryptInit` resets AES (aes.c:223), clears KEY_CLR (226–227), for KUP keys writes 8 big-endian words to KUP_0.. (aes.c:230–237), calls `XSecure_AesKeySelNLoad` which writes `KEY_SRC` then pulses `KEY_LOAD` (aes.c:936–951), sets `CFG`, writes `START_MSG`, configures CSU-DMA endianness swap, DMAs the 16-byte IV (aes.c:259–261), then streams ciphertext+GCM-tag through SSS→AES→DMA. GCM tag checked via `AES_STS & GCM_TAG_OK`. `XSecure_AesKeyZero` (aes.c:882–907) sets `KEY_ZERO|KUP_ZERO` in KEY_CLR and spins on STS bits 8/9. **Crypto export-control gate** runs first: `XSecure_CryptoCheck()` (aes.c:151) reads eFUSE `0xFFCC0000 + 0x1018`, fails if bit `0x8000` set (xsecure_cryptochk.c:31–62) — if burned, AES/RSA are disabled.

### 3.4 SHA-3/384 engine (0xFFCA2000)

Offsets (xsecure_sha_hw.h:45–51): `START 0x00`, `RESET 0x04`, `DONE 0x08`, `DIGEST_0..11 0x10–0x3C` (12×32 = 384-bit). Padding (sha.c:78–81): NIST start `0x06`/end `0x80` (default, sha.c:155) or Keccak start `0x01`/end `0x80`. Flow: `XSecure_Sha3Start` clears RESET, writes START (sha.c:303–308); data fed via `XSecure_SssSha`→CSU-DMA (sha.c:540); `Sha3Finish` pads, waits DONE, reads DIGEST_0..11 word-by-word (sha.c:512–513). SHA-3 hashes the PPK (vs eFUSE PPK digest) and partitions during RSA auth. The engine has no key, so its digest is not secret per se — but it is the value an attacker must control to forge an image.

### 3.5 RSA core (0xFFCE0000) — authentication

Offsets (xsecure_rsa_hw.h:41–78): `WRITE_DATA 0x00`, `WRITE_ADDR 0x04`, `READ_DATA 0x08`, `READ_ADDR 0x0C`, `CONTROL 0x10`, `STATUS 0x14`, `MINV0..3 0x18–0x24`, RD/WR_DATA banks, `WR_ADDR 0x44`, `RD_ADDR 0x60`. RSA RAM region index: EXPO=0, MOD=1, DIGEST=2, RES_Y=4, RES_Q=5 (rsa_core.h:90–95). CONTROL length codes: 4096 = `0xC0`; opcodes EXP=`0x01`, EXP_PRE (R·R mod M pre-comp)=`0x05` (rsa_core.h:120–125). STATUS: DONE=`0x1`, ERROR=`0x4` (rsa_core.h:134–136). `XSecure_RsaOperation` (rsa_core.c:122) loads modulus/exponent/digest, computes Montgomery inverse, writes `RsaType + opcode` to CONTROL, polls STATUS (rsa_core.c:213–235). Default 4096 with SHA-3 T-padding (two silicon-rev pad tables, rsa_core.c:54–61). RSA also passes through `XSecure_CryptoCheck` via `RsaCfgInitialize` (rsa_core.c:96). Whether RSA is *enforced* at boot is the eFUSE `SEC_CTRL.RSA_EN` check (xsecure.c:1149–1150) — on this board RSA_EN=0 (§7).

### 3.6 Secure Stream Switch (SSS, CSU_SSS_CFG @ 0xFFCA0008)

A 4-bit-per-resource crossbar. Field layout (qemu 1792–1798): `SHA_SSS [15:12]`, `AES_SSS [11:8]`, `DMA_SSS [7:4]`, `PCAP_SSS [3:0]` (4 nibbles, `XSECURE_SSS_CFG_LEN_IN_BITS = 4`, xsecure_sss.h:46). The driver's lookup table (xsecure_sss.c:34–45) permits only a small set of routings — DMA→AES = `0x0A`, DMA→SHA/PCAP = `0x05`, DMA self-loopback. Crucially the SSS *cannot* route an engine's internal key out to DMA: there is no "AES-key → DMA" path, which structurally stops a JTAG attacker from streaming the device key into RAM by reconfiguring the switch.

### 3.7 CSU control page (0xFFCA0000) — boot-state, integrity, interrupts

`CSU_STATUS 0x00` bits BOOT_ENC[1]/BOOT_AUTH[0] report whether the current boot was encrypted/authenticated (golden: both 0). `CSU_SSS_CFG 0x08`. `CSU_MULTI_BOOT 0x10`. `CSU_TAMPER_TRIG 0x14` (TAMPER bit0, qemu 1818–1821). `CSU_FT_STATUS 0x18` (triple-redundancy fault flags). `CSU_ISR/IMR/IER/IDR 0x20–0x2C`: `AES_DONE[0]`, `RSA_DONE[1]`, `SHA_DONE[2]`, `PCAP_*`, `AES_ERROR[8]`, `PUF_ACC_ERROR[12]`, `TAMPER[13]`, `CSU_RAM_ECC_ERROR[14]` (qemu 1861–1879). `IDCODE 0x40`, `VERSION 0x44`, and the digest array `CSU_ROM_DIGEST_0..11` spanning `0xFFCA0050..0xFFCA007C` (SHA-3/384 of the CSU BootROM). Note: `CSU_ISR` sits at `0xFFCA0020` (qemu 1860); `PUF_ACC_ERROR` = bit 12.

### 3.8 Empirical findings (board 210308BD8D4D, JTAG-idle, A53 EL3 via DAP)

From reports/csu-fullmap-2026-06-08-134631.md and csu-surface-2026-06-08-131838.md:

- **The entire CSU crypto window is readable from JTAG-idle with zero SLVERR/unmapped faults** for AES, SHA, PCAP, PUF, tamper (`-- N non-zero, 0 faulting` each). The crypto engines are reachable from the DAP-NS/EL3 path with no DAP wedge — a notable filtering gap.
- **AES idle `AES_STS = 0x00000F00`** = bits 8|9|10|11 = `AES_KEY_ZERO | KUP_ZEROED | BOOT_KEY_ZERO | OKR_ZERO` — all key registers report zeroed/clean at idle. After releasing `AES_RESET` and pulsing `KEY_LOAD`, STS went to `0x00000F10` (added bit4 `KEY_INIT_DONE`) for **every** KEY_SRC 0–7 (csu-surface §8). Interpretation: the engine fakes `KEY_INIT_DONE` regardless of source, but **no `*_ZERO` bit ever cleared** → no real key loaded from any source in JTAG-idle; no usable runtime key-injection/extraction path. Corroborates memory note "AES_KEY_LOAD=1 fakes KEY_INIT_DONE."
- **`AES_KEY_SRC` latches values 0–7** (masks 0xFFFFFFFF→0x0F) → field is 4 bits wide and freely writable, but cosmetic in idle — no key materializes.
- **SSS_CFG partially writable**: writing 0xFFFFFFFF reads back `0x000FFFFF` (csu-surface §5) → 20-bit-wide register (5 sources × 4 bits in HW, though the driver uses only 4 nibbles). **Contradiction flagged:** idle `CSU_SSS_CFG` read `0x00005000` in the surface probe but `0x00008834`/`0x00000050` in the fullmap and golden captures — golden `0x00000050` decodes to DMA_SSS=5 (DMA-loopback-ish). The live value depends on boot/idle timing; **do not treat any single SSS idle value as canonical.** (§2.7 cites `0x00005000` from the surface probe specifically.)
- **SHA digest registers at idle mirror the ROM digest**: `SHA_DONE` (bit in `0xFFCA2008`) is set and the digest words at `0xFFCA2010..0xFFCA203C` read `0x26042731…0x2937CB90`, identical to `CSU_ROM_DIGEST_0..11` at `0xFFCA0050..0xFFCA007C`. At idle the SHA engine still holds the BootROM's own SHA-3/384 self-check digest — a readable forensic artifact (the project's "ROM_DIGEST = BootROM SHA-3-384" finding).
- **PCAP**: `0xFFCA3010 = 0xA0000A46` (PCAP_STATUS); idle config bits at `0xFFCA3000/8/C = 1`.
- **Tamper**: `TAMPER_STATUS (0xFFCA5000) = 0` in golden, `0xFFCA503C = 0x0000000C` in fullmap — **no tamper sources armed** on dev silicon; tamper-driven key-zeroize defenses are inert here.
- **Control-page hazard**: a per-word sweep of `0xFFCA0000–0x00FC` shows `0xFFCA001C`, `0x0030`, `0x0048`, `0x004C`, and the whole `0x80–0xFC` tail **wedge the DP on read** (FAULT, recovered via sticky clear; csu-surface §7). These are reserved/secured apertures inside the control page — reading them is the dominant CSU failure mode and must be avoided. (Note `0xFFCA0030`/`0x0034`/`0x0038`/`0x003C` JTAG registers *are* safely readable per §10; the wedging `0x0030` entry here refers to a different sweep context — see §10 contradiction note.)
- **Authentication OFF on this board** (golden enumerate.md): `SEC_CTRL.RSA_EN [25:11] = 0x0`, `PUF_CHASH=0`, AES_WRLK/RDLK=0, CSU_STATUS BOOT_AUTH/BOOT_ENC=0. BootROM accepts unsigned/unencrypted images — no RSA forgery needed to boot custom code.
- The **crypto export-control eFUSE** (`0xFFCC0000+0x1018` bit 0x8000) is not reported burned, consistent with AES/RSA functionally enabled.

### 3.9 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Reachable:** the full CSU crypto register window is readable/writable from the DAP without faulting. Can read the BootROM SHA-3/384 digest (ROM_DIGEST and the SHA engine copy), drive SHA-3 over chosen data, configure the SSS within its lookup-constrained routes, and program/pulse AES/RSA as software primitives.
- **Blocked (the important part):** **no JTAG-idle path to the device/boot/PUF/family key.** `AES_KEY_SRC` only exposes KUP/DEV; the SSS table has no engine-key→DMA route; the wake-and-load sweep showed every source leaves the `*_ZERO` STS bits set. The internal 128 KB CSU BootROM is not AXI-mapped. RSA at `0xFFCE0000` is untested; even if drivable, forging a signed image needs the private key whose PPK SHA-3-384 matches the eFUSE digest — infeasible. Realistic CSU attack value on this board is **forensic readout** (ROM digest, boot-mode flags, security-eFUSE state) and using the engines as scratch crypto, not key exfiltration. Confidentiality of the device key rests on the SSS routing constraint and the KEY_SRC restriction, both of which held under probing.

**Honest gaps:** RSA core (`0xFFCE0000`) never probed on this board (source-only). PCAP `0xA0000A46` status bits not fully decoded against a TRM field table (only PCAP_WR_IDLE bit0 is sourced). SSS idle value varies across captures (above). Whether AES `KEY_LOAD` ever loads a real device key requires a booted/authenticated context not reproduced in idle; the "no key loads" conclusion is specific to JTAG-idle.

---

## 4. PUF (Physically Unclonable Function)

### 4.1 What it is and its role in secure boot

The ZynqMP PUF is a **ring-oscillator PUF** in the CSU. Its job is to derive a silicon-unique, never-stored **Key Encryption Key (KEK)** that unwraps an AES-256 "**black key**" into the "**red key**" used by the CSU AES-GCM engine to decrypt boot partitions (see §5). The PUF response is not stored; only *helper data* (syndrome + CHASH + AUX) is persisted, and on each boot the controller re-derives the same KEK from the live cells using helper data for error correction.

Two operations (xilskey_eps_zynqmp_puf.h:63-64):
- **`PUF_REGISTRATION = 1U`** — one-time provisioning; samples cells, emits 4K-mode syndrome/helper data + a 32-bit CHASH and 24-bit AUX. Normally factory; output burned to eFUSE or placed in the boot header.
- **`PUF_REGENERATION = 4U`** — boot-time; replays helper data, regenerates the KEK directly into the AES engine (response *not* exposed via a register on this path).

**Naming trap** (memory `project_puf_extractable_via_jtag.md`): the command IDs are **enum values, not bit flags** — early probes mislabeled REGISTRATION(1) as "REGEN" and REGENERATION(4) as "RESET."

### 4.2 Key registers / addresses

**CSU PUF aperture** — base `CSU_BASEADDR = 0xFFCA0000`, PUF sub-block at `0xFFCA4000`. Source of truth: xilskey xilskey_eps_zynqmp_hw.h:1218-1268. **Caveat:** these PUF-aperture registers are **NOT in the QEMU model** — `zynqmp-regs-qemu.tcl` models only `CSU_ISR @ 0xFFCA0020`, not `0xFFCA4xxx`. The layout below traces to the xilskey header + UG1085 + live captures.

| Reg | Addr | Source | Notes |
|---|---|---|---|
| `PUF_CMD` | `0xFFCA4000` | hw.h:1220 | write 1=REGISTRATION, 4=REGENERATION |
| `PUF_CFG0` | `0xFFCA4004` | hw.h:1221 | init `0x2` (`PUF_CFG0_INIT_VAL`) |
| `PUF_CFG1` | `0xFFCA4008` | hw.h:1222 | 4K-mode init `0x0c230090` (`PUF_CFG1_INIT_VAL_4K`) |
| `PUF_SHUT` | `0xFFCA400C` | hw.h:1223 | shutter, fixed `0x0100005E` |
| `PUF_STATUS` | `0xFFCA4010` | hw.h:1224 | status bits below |
| `PUF_WORD` | `0xFFCA4018` | hw.h:1233 | syndrome/helper-data read port |
| `CSU_ISR` | `0xFFCA0020` | hw.h:1225, qemu 1860 | PUF errors land here, **not** in PUF_STATUS |

**PUF_STATUS bit-fields** (hw.h:1227-1231): `SYN_WRD_RDY = bit 0 (0x1)`; `KEY_RDY = bit 3 (0x8)`; `AUX = bits 27..4 (mask 0x0FFFFFF0)`; `OVERFLOW = bits 29..28 (mask 0x30000000)`. **`CSU_ISR.PUF_ACC_ERROR = bit 12 (0x1000)`** (hw.h:1227; qemu 1867). AUX extracted as `(PUF_STATUS & 0x0FFFFFF0) >> 4` (puf.c:705-706).

**PUF trim-mode registers** (hw.h:1241-1268): `PUF_TM_STATUS 0xFFCA4804`, `PUF_TM_UL 0xFFCA4808`, `PUF_TM_LL 0xFFCA480C`, `PUF_TM_SW 0xFFCA4810`, `PUF_TM_TR 0xFFCA4814`.

**eFUSE helper-data store** — base `EFUSEPS_BASEADDR = 0xFFCC0000` (hw.h:48):
- **`PUF_CHASH @ 0xFFCC1050`** (hw.h:715; 32-bit). **Confirmed in QEMU** at `0xFFCC1050` (regs line 2951).
- **`PUF_MISC @ 0xFFCC1054`** (hw.h:729). QEMU fields (line 2958): `REGISTER_DIS bit31`, `SYN_WRLK bit30`, `SYN_INVLD bit29`, `TEST2_DIS/RESERVED bit28`, `AUX bits23..0`. xilskey masks agree: `REG_DIS 0x80000000`, `SYN_WRLK 0x40000000`, `SYN_INVLD 0x20000000`, `RESERVED 0x10000000`, `AUX 0x00ffffff`. Secure-bit enum (puf.h:84-89): `RESERVED=28, SYN_INVALID=29, SYN_LOCK=30, REG_DIS=31`. `REG_DIS` permanently disables future registration; `SYN_WRLK` write-locks syndrome; `SYN_INVALID` marks helper data invalid.

### 4.3 Boot-time / vendor-source behavior

**REGISTRATION** (`XilSKey_Puf_Registration`, puf.c:623-731): forces shutter `0x0100005E` (637), validates access rules (639), writes `PUF_CFG0=2` (647), `PUF_CFG1=0x0c230090` for the only supported `PUF_MODE4K` (651-652, else error 656), writes `PUF_SHUT` (663), then `PUF_CMD=1` which "triggers an interrupt to CSUROM" (667-671). Loops: `XilSKey_WaitForPufStatus` polls `PUF_STATUS.SYN_WRD_RDY` with a 500 ms timeout (585-604), reads one syndrome word from `PUF_WORD` per iteration (690), terminates when `KEY_RDY` (bit 3) sets — the *last* `PUF_WORD` read is the **CHASH**, AUX taken from status (704-712). `MaxSyndromeSizeInWords = XSK_ZYNQMP_MAX_RAW_4K_PUF_SYN_LEN = 140` words. The `XilSKey_Puf` struct (puf.h:106-125) carries `SyndromeData[386]`, `Chash`, `Aux`, plus `RedKey`, `BlackKeyIV[12]`, `BlackKey[32+16]` — modeling PUF-KEK black-key wrapping (red key + 12-byte IV + 16-byte GCM tag).

**REGENERATION** (`XilSKey_Puf_Regeneration`, puf.c:745-790): **refuses if `PUF_CHASH == 0` in the eFUSE cache** (760-765, `PUF_INVALID_REQUEST`) — regeneration requires provisioned helper data. Writes `PUF_CFG0=2`, `PUF_SHUT=0x0100005E`, `PUF_CMD=4` (768-777), waits 6 ms (780), checks **`CSU_ISR & 0x1000` (PUF_ACC_ERROR)** for failure (782-786). KEK goes straight to the AES engine; **no `PUF_WORD` read** — the response is never SW-visible during regeneration.

**Access-rule gate** (`XilSkey_Puf_Validate_Access_Rules`, puf.c:1095-1165): registration blocked if `PUF_MISC.REG_DIS` set; re-registration (CHASH or AUX already non-zero) additionally requires `SEC_CTRL.RSAEnable` (1136-1150). This is *firmware* policy, not a hardware filter on the controller.

**Bootgen** drives the manufacturing side via BIF keywords: `puf_file` (cmdoptions.l:258), `PUF4KMODE`, `PUFROSWAP`, `SHUTTER=...` (bif.y:141,449,451), `PUFHD_LOC` to place helper data **in the boot header** (bif.y:266-267 → `PufHdLoc::PUFinBH`), and the KEK-IV family `BH_KEK_IV / EFUSE_KEK_IV` (bif.y:143,595-598). This is the docs/12 distinction: **eFUSE-PUF mode** (`efuse_blk_key`) burns CHASH/AUX to eFUSE; **BH-PUF mode** (`bh_blk_key`) keeps helper data in the boot header — in which case `PUF_CHASH @ 0xFFCC1050` and `PUF_MISC.AUX` stay **zero even though PUF is in use** (docs/12 §3:100-102). **Zero CHASH does NOT prove PUF was never provisioned.**

### 4.4 Empirical findings — board 210308BD8D4D

**Idle-state captures (2026-06-08 csu-fullmap / csu-surface):**
- CSU PUF aperture is **fully readable from DAP-NS in JTAG-idle, zero faulting** (csu-fullmap:54-59): `PUF_CFG0=0x2`, `PUF_CFG1=0x00080080`, `PUF_SHUT=0x01000020`, `PUF_STATUS=0x2`, `PUF_CMD` reads `0x0`. (`PUF_STATUS=0x2` has SYN_WRD_RDY clear; bit 1 set — undocumented in the xilskey mask set, possibly an idle/done indicator.)
- `PUF_TM_SW @ 0xFFCA4810 = 0x01000020` (fullmap:62) — trim register present and readable.
- **eFUSE cache:** `PUF_CHASH @ 0xFFCC1050 = 0x00000000`; `PUF_MISC @ 0xFFCC1054 = 0x10000000` (golden enumerate.md:105-106). PUF_MISC bit 28 set = **RESERVED/TEST2_DIS**; AUX (bits 23-0) = 0, REG_DIS/SYN_WRLK/SYN_INVLD all clear. So **this dev board has NO PUF helper data provisioned** (CHASH=0, AUX=0); registration is *not* disabled (REG_DIS=0).
- **AES KEY_SRC=4 (PUF) wake test** (csu-surface:145): with AES_RESET released and KEY_LOAD pulsed for KEY_SRC=PUF, `AES_STATUS=0x00000F10` — identical to every other source. `*_ZERO` bits stayed set → **no usable PUF-derived key is loadable at runtime on this board**, consistent with CHASH=0 (regeneration self-aborts per puf.c:760).

**Extraction probe (2026-05-28, memory `project_puf_extractable_via_jtag.md`):** issuing REGISTRATION (CFG0=2 → SHUT=0x0100005E → CMD=1) from DAP-NS and polling `SYN_WRD_RDY`, then reading `PUF_WORD`, streamed real syndrome/helper-data words (e.g. `0x28EC162B…`, plus CHASH/AUX) — **with no security gate on the controller**. Across a hard power-cycle the syndrome words differed (expected: each registration is a fresh noisy snapshot) while a few low bits and one word (`0x933DF2AA`) matched, consistent with PUF behavior. Refined disposition: the controller and REGISTRATION are genuinely **ungated from DAP-NS**, but a *naive* delayed-read does not cleanly serialize the response; a protocol-correct read (poll SYN_WRD_RDY, read 140 words to KEY_RDY) yields the full helper-data block. eFUSE was **not** written because `EFUSE.WR_LOCK=0x1` by default, and REGISTRATION only generates data — burning it is a separate, lock-gated step (§7).

**KEK-reconstruction theory (memory `reference_pufky_construction.md`):** the 140-word (4480-bit) captured helper data is consistent with a **2×PUFKY (Maes, CHES 2012)** construction: REP(7,1,3) inner + BCH(318,174,17) outer, scaled to a 256-bit KEK; UG1085's "4060-bit syndrome + 24-bit AUX + 32-bit CHASH" math-checks against this. Offline KEK recovery would follow Delvaux 2015 helper-data-manipulation, requiring an SD-boot decryption oracle — **not** achievable from JTAG-idle alone.

### 4.5 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

**Reachable:** the CSU PUF aperture (`0xFFCA4000`) is readable **and** writable from DAP-NS with no master-aware filter — confirmed across multiple sessions. REGISTRATION can be triggered and helper-data words streamed out. This contradicts the "PUF cannot be reached" assumption: `JTAG_SEC` gates *DAP debug enable*, not PUF register access, so any chip with JTAG live exposes the controller. `PUF_CHASH`/`PUF_MISC` eFUSE cache is freely readable. Trim register `PUF_TM_SW` is writable — a *potential* (untested-impact) fault-injection knob during a live operation.

**Blocked / not exploitable here:** this board has **no provisioned PUF** (CHASH=0/AUX=0/BBRAM=0/SEC_CTRL=0), so there is **nothing to unwrap** — REGENERATION self-aborts (puf.c:760), and the AES PUF key path returns the empty-key status (`0xF10`). Even on a *provisioned* chip, the *clean* KEK is never exposed by REGENERATION (response goes silicon→AES internally; no `PUF_WORD`). Recovering the KEK from extracted helper data requires off-chip ECC analysis **plus a boot-decryption oracle** — outside JTAG-idle, no side-channel HW. eFUSE writes (accidental provisioning, REG_DIS lockout) are gated by `EFUSE.WR_LOCK=0x1`; a probe that opens WR_LOCK then runs REGISTRATION write-back **could** permanently program PUF eFUSE — deliberately avoided.

**Honest bottom line:** the genuinely novel, disclosure-relevant finding is the **absence of any hardware security gate on the CSU PUF controller from DAP-NS** (helper-data extraction is mechanically possible on JTAG-live silicon). Turning that into key-recovery on a production chip still needs (a) provisioned helper data, (b) protocol-correct word streaming, and (c) an offline KEK-reconstruction pipeline with a decryption oracle — none satisfied on this board today.

---

## 5. Key hierarchy

### 5.1 What it is and its role in secure boot

Boot-image confidentiality rests on a single symmetric secret — the **red (user) AES-256 key** — that decrypts the encrypted FSBL/partitions in the CSU AES-GCM engine (§3). The "key hierarchy" is the set of *wrapping schemes* so the red key never sits in the clear inside the device or the image:

- **Obfuscated / "gray" key** = red key AES-GCM-encrypted under the **family key** (a fixed, AMD-only, per-family metal-mask secret).
- **Black key** = red key encrypted under a **PUF-derived KEK** (silicon-unique, §4).

Both are stored as ciphertext (eFUSE or boot header); the CSU/BootROM unwraps them at boot, loads the red key into the AES engine, decrypts the image. The hierarchy defends against *NVM/image disclosure*: reading the QSPI/SD/eFUSE storage yields only the wrapped form, useless without the family key or that specific die's PUF.

### 5.2 The five key types

The bootgen `KeySource::Type` enum is the authoritative list (bootgenenum.h:53-82): `BbramRedKey, EfuseRedKey, EfuseBlkKey, BhBlkKey, EfuseGryKey, BhGryKey, BhKupKey, BbramBlkKey, BbramGryKey, …`. The BIF lexer maps keywords (bif.l:284-308).

| Key | What it is | Where stored | Derivation / wrapping | SW/JTAG-readable? |
|---|---|---|---|---|
| **Family key** | AES key baked into the device **metal layers**, family-wide, held only by AMD. Encrypts red→gray. | Hardware (metal mask), in the CSU | none (it *is* a root) | **No — never exposed by any documented path.** Obtained only via AMD under NDA. |
| **Obfuscated / gray** | Red key AES-GCM-encrypted under the family key. | eFUSE (`efuse_gry_key`) or BH (`bh_gry_key`) | family-key wrap | ciphertext only |
| **Black** | Red key AES-GCM-encrypted under the **PUF KEK**. | eFUSE (`efuse_blk_key`) or BH (`bh_blk_key`) | PUF-KEK wrap; requires shutter + KEK IV | ciphertext only |
| **Red (user) AES** | The actual AES-256 boot key. | eFUSE (red), **BBRAM (red only)**, or BH (encrypted forms only) | user-chosen | **No** — read-lock/CRC-only, see §5.4 |
| **PUF KEK** | PUF-derived key-encryption key, wraps/unwraps the black key. | derived at boot from the on-die PUF + helper data | PUF regeneration (§4) | **No** (KEK internal); but the PUF *controller* is reachable (§4.5) |

### 5.3 The boot-header `encryptionKeySource` field — magic constants

The chosen key source is recorded at boot-header offset **`0x28`** (bootheader-zynqmp.h:64). bootgen translates `KeySource::Type` to a 32-bit magic word in `SetEncryptionKeySource()` (bootheader-zynqmp.cpp:272-313), constants in bootheader.h:64-70:

| Source | BH value |
|---|---|
| `EFUSE_RED_KEY` | `0xA5C3C5A3` |
| `BBRAM_RED_KEY` | `0x3A5C3C5A` |
| `EFUSE_BLK_KEY` | `0xA5C3C5A5` |
| `BH_BLACK_KEY` | `0xA35C7C53` |
| `EFUSE_GRY_KEY` | `0xA5C3C5A7` |
| `BH_GRY_KEY` | `0xA35C7CA5` |
| `BH_KUP_KEY` | `0xA3A5C3C5` |

Structural rule: for `EfuseBlkKey`, `BhBlkKey`, `EfuseGryKey`, `BhGryKey`, bootgen sets `keyIvMust = true` (bootheader-zynqmp.cpp:287,292,297,302) — wrapped sources **require** a separate KEK IV in the BIF (the wrap is a real AES-GCM operation). Red-key sources do not. Black/gray key bytes and their IV live in the boot header at `greyOrBlackKey[8]` offset **`0x4C`** and `greyOrBlackIV[3]` offset **`0xAC`** (bootheader-zynqmp.h:73,79), populated via `SetGreyOrBlackKey()`/`SetGreyOrBlackKekIV()` (bootheader-zynqmp.cpp:121-122). See §6 for the full boot-header map.

### 5.4 Family-key wrap (gray key) — how bootgen drives it; and the read-lock guarantee

The gray key is *generated by bootgen offline*. `ZynqMpEncryptionContext::GenerateGreyKey()` (encryption-zynqmp.cpp:1226-1251) reads the red key from the `.nky`, reads the BH IV (`ReadBhIv`, **requires `[bh_key_iv]`**, line 1269), then calls the family-key wrapper:

```cpp
obfs key(redKey.get(), bhIv.get(), metalFile.c_str(), filename.c_str());
obfsk((void*)&key);
```

`metalFile` is the **family key file** from BIF `[familykey]` (bifoptions.cpp:904-914; help.h:2980-2999, "Specify Family Key", `fpga, zynqmp` only). The wrapping routine `obfsk()`/`obfs`/`i0` struct is **deliberately source-obfuscated** in obfskutil.h (token-salad `#define`s; a single opaque `void obfsk(void *)`). The algorithm body is *not present as readable C in the open-source tree* — the one piece AMD does not disclose, consistent with the family key being a guarded root. The path is gated behind `#ifdef ENABLE_OBFUSCATED_KEY` (encryption-zynqmp.cpp:1228), so a stock open-source build does not even compile gray-key generation.

**The red/device key is non-readable by design, two ways:**
- **eFUSE AES key never read back** — after burning, xilskey verifies only by CRC: `XilSKey_ZynqMp_EfusePs_CheckAesKeyCrc()` (xilskey_eps_zynqmp.c:1767, called at 354). Read-lock fuse `SEC_CTRL.AES_RDLK` (xilskey_eps_zynqmp_hw.h:846-849, mask `0x1`) plus `AES_WRLK` (mask `0x2`).
- **BBRAM AES key never read back** — `XilSKey_ZynqMp_Bbram_Program()` (xilskey_bbramps_zynqmp.c:80) writes, verifies **CRC32 only** (`XilSKey_ZynqMp_Bbram_CrcCalc`, 284; checks `AES_CRC_DONE`/`AES_CRC_PASS`, 118-133). No read path. **BBRAM holds red keys only** — cannot store gray/black.

After verification the BootROM **zeroizes all key material**: capture shows `CSU.AES_STATUS = 0xFFCA1000 = 0x00000F00` with `AES_KEY_ZEROED[8]`, `KUP_ZEROED[9]`, `BOOT_ZEROED[10]`, `OKR_ZEROED[11]` all set. The xilsecure software view of key selection is just `XSECURE_CSU_AES_KEY_SRC_KUP (0x0)` vs `XSECURE_CSU_AES_KEY_SRC_DEV (0x1)` (xsecure_aes.h:119-120) — user key or "the device key" whose bytes "will be ignored and device key will be used" (header comment 31-34).

### 5.5 Empirical findings (board 210308BD8D4D)

Clean, unprovisioned dev silicon — the *ciphertext* side is empty and the *enforcement* side wide open:
- **BBRAM red-key slot all zero** — `BBRAM.KEY_0..7` (`0xFFCD0000–0xFFCD001C`) = 0; `BBRAM.CTL/STATUS/LOCK` (`0xFFCD0020/24/28`) = 0. With `JTAG_SEC` DAP open, all-zero almost certainly means *no key*, not read-protected. (Note: §7 places BBRAM key words at `0xFFCD0010–0030`; see contradiction note at the end.)
- **eFUSE AES key CRC = 0** — `EFUSE.AES_CRC` (`0xFFCC0048`) = 0; no eFUSE red key burned.
- **SEC_CTRL = 0** (`0xFFCC1058`) — neither `AES_RDLK` nor `AES_WRLK` blown.
- **PUF unprovisioned** — `EFUSE.PUF_CHASH` (`0xFFCC1050`) = 0; black-key path dormant. `PUF_MISC` `0xFFCC1054 = 0x10000000`.
- **No wrapped keys anywhere** — PPK hashes, SPK_ID, USER fuses all zero; the device boots **unsigned, unencrypted**.
- **CSU AES engine parked & key-zeroed** — `AES_STATUS = 0x00000F00` (all four *_ZEROED).
- **PUF controller reachable but inert** — block at `0xFFCA4000` freely writable from DAP-NS; a 26-witness fuzz showed writes latch but produce no observable downstream state change on this unprovisioned die.

### 5.6 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Family key: out of reach, full stop.** Metal-mask root inside the CSU, no AXI address, wrapping algorithm not in open source. Recovery needs DPA/EM side-channel on the AES family-unwrap or invasive die attack — out of scope. Gray-key images are unforgeable/un-decryptable by us.
- **Red key: never SW/JTAG-readable on any board.** eFUSE and BBRAM are CRC-verify-only with optional read-lock; BootROM zeroizes live AES registers post-boot. No register yields red-key bytes.
- **PUF KEK / black key: KEK never exposed**, but the PUF *controller's* ungated DAP-NS writability (`0xFFCA4000`) is the one genuinely interesting surface — on a **PUF-provisioned production** die an attacker could issue PUF commands and read `PUF_WORD` (§4.5). Disclosure-class for production silicon, but **dormant here** (CHASH=0).
- **Bottom line:** the *enforcement primitives* (read-lock fuses, CRC-only verify, BootROM zeroize) are intact and unbypassed by a memory-read approach; on this board they are simply unengaged because it is dev silicon booting in the clear. No key in the hierarchy is extractable via the non-destructive JTAG path. The only forward-looking lever is the ungated PUF controller, against PUF-keyed production parts.

**Honesty note:** "PUF KEK never exposed" was previously a contested vote in the project synthesis (docs/12 §2); what *is* source-proven is that family/red keys have no read path. The KEK is internal, but the PUF controller feeding it is not gated — treat "KEK unreachable" as likely-but-not-formally-closed.

---

## 6. Bootgen & boot-image format

### 6.1 What it is and its role in secure boot

Bootgen is AMD's host-side tool that assembles a `.bin`/`.mcs` boot image from a BIF + partitions. On ZynqMP it is the **producer** of every structure the CSU BootROM and FSBL later **consume**: the boot header (key sources, IVs, FSBL geometry), the image/partition header tables, and — for authenticated images — one RSA-4096 + SHA-3/384 Authentication Certificate (AC) per signed partition. The C++ structs in `references/src/bootgen/zynqmp/` are byte-exact mirrors of what silicon parses; the FSBL header (`xfsbl_authentication.h`) repeats the same offsets, confirming producer↔consumer agreement. **None of this lives in OCM at boot** — the BootROM copies only the FSBL **code body** to OCM `0xFFFC0000`; the boot header/IHT/PHT/AC stay on the boot device (see §6.6).

### 6.2 Boot header layout (from `ZynqMpBootHeaderStructure`)

Offsets verbatim from bootheader-zynqmp.h:59-80:

| Off | Field | Size | Notes |
|---|---|---|---|
| 0x000 | `bootVectors[8]` | 32 B | `MAX_BOOT_VECTORS=8` |
| 0x020 | `widthDetectionWord` | 4 B | `WIDTH_DETECTION = 0xAA995566` |
| 0x024 | `identificationWord` | 4 B | `HEADER_ID_WORD = 0x584C4E58` ("XLNX") |
| **0x028** | **`encryptionKeySource`** | 4 B | magic-coded enum (§5.3) |
| 0x02C | `fsblExecAddress` | 4 B | |
| 0x030 | `sourceOffset` | 4 B | byte offset of FSBL on boot device |
| 0x034 | `pmuFwLength` | 4 B | `PMU_MAX_SIZE = 0x20000` (128 KB) |
| 0x038 | `totalPmuFwLength` | 4 B | |
| 0x03C | `fsblLength` | 4 B | `FSBL_MAX_SIZE = 0x3E800` (250 KB) |
| 0x040 | `totalFsblLength` | 4 B | includes AC if authenticated |
| 0x044 | `fsblAttributes` | 4 B | bit-packed (below) |
| 0x048 | `headerChecksum` | 4 B | word-sum, non-cryptographic |
| **0x04C** | **`greyOrBlackKey[8]`** | 32 B | `BLK_GRY_KEY_LENGTH=8` words; 0x4C–0x68 |
| 0x06C | `shutterValue` | 4 B | PUF shutter (e.g. `0x0100005E`) |
| 0x070 | `udf[10]` | 40 B | `UDF_BH_SIZE_ZYNQMP=10`; 0x70–0x94 |
| 0x098 | `imageHeaderByteOffset` | 4 B | → Image Header Table |
| 0x09C | `partitionHeaderByteOffset` | 4 B | → Partition Header Table |
| **0x0A0** | **`secureHdrIv[3]`** | 12 B | FSBL secure-header (GCM) IV; 0xA0–0xA8 |
| **0x0AC** | **`greyOrBlackIV[3]`** | 12 B | grey/black KEK IV; 0xAC–0xB4 |

Double-confirmed by readimage-zynqmp.cpp:346-363 (`DisplayBootHeader`), which prints each field with its hex offset (`encryption_keystore (0x28)`, `grey/black_key (0x4c)`, `fsbl_sec_hdr_iv (0xa0)`, `grey/black_iv (0xac)`).

**`headerChecksum` (0x48)** is a 32-bit word-sum over 40 bytes (10 words) from `widthDetectionWord` (0x20) through `fsblAttributes` (0x44): bootheader-zynqmp.cpp:434-440 (`ComputeWordChecksum(&widthDetectionWord, 40)`). Integrity-only, trivially recomputable.

**`encryptionKeySource` (0x28)** magic enumeration: see §5.3. Adds `0x00000000`=None (unencrypted). `keyIvMust` true for the four wrapped sources, forcing `SetGreyOrBlackKekIV` to error if no `bh_key_iv` (cpp:530-533). Grey/black key at 0x4C from a 32-byte hex file (cpp:443-456); IV at 0xAC from a 12-byte hex file (cpp:515-535).

**`fsblAttributes` (0x44) bit-packing** (bootheader-zynqmp.cpp:416-423; shifts bootheader.h:73-80):

| Bits | Field | Meaning |
|---|---|---|
| [3:2] | OPT_KEY | operational key enable (==3) |
| [5:4] | AUTH_ONLY | authenticate-only |
| [7:6] | PUF_HD | PUF helper-data location (==3 ⇒ PUF-in-BH) |
| [9:8] | BI_HASH | boot-image checksum type |
| [11:10] | CORE | FSBL target core |
| [13:12] | AUTH_HASH | SHA2 vs SHA3 |
| [15:14] | BH_RSA | boot-header RSA (dev-mode auth, bypasses eFUSE PPK) |
| [17:16] | BH_PUF_MODE | PUF 4K vs 12K mode |

If `PUF_HD == 0x3`, an extra 1544-byte PUF helper-data block (`PUF_DATA_LENGTH=1544`) is appended after the boot header + register-init table (`SetPufData`, cpp:540-558). On-flash counterpart of the helper data the project extracts live via the CSU PUF aperture (§4).

### 6.3 Image Header Table / Partition Header Table

The BH points (0x98/0x9C) to IHT and PHT. IHT fields (readimage-zynqmp.cpp:376-379): `version (0x00)`, `partitionTotalCount (0x04)`, `firstPartitionHeaderWordOffset (0x08)`, `firstImageHeaderWordOffset (0x0c)`, `headerAuthCertificateWordOffset (0x10)`, `bootDevice (0x14)`, `ihtChecksum (0x3c)`. Per-partition PHT (readimage-zynqmp.cpp:415-422): `encryptedPartitionLength (0x00)`, `unencryptedPartitionLength (0x04)`, `totalPartitionLength (0x08)`, `destinationExecAddress (0x10, 64-bit)`, `destinationLoadAddress (0x18, 64-bit)`, `partitionWordOffset (0x20)`, `partitionAttributes (0x24)`, `authCertificateOffset (0x34)`, `pHChecksum (0x3c)`. Offsets are word-based (×4 on display).

### 6.4 Authentication Certificate (RSA-4096 + SHA-3/384)

The AC is `AuthCertificate4096Structure` (authentication-zynqmp.h:49-59), one per signed partition, `sizeof == certSize`:

| Off | Field | Type / size | Notes |
|---|---|---|---|
| 0x000 | `acHeader` | u32 | base `AUTH_HDR_ZYNQMP=0x115` |
| 0x004 | `spkId` | u32 | SPK id / revocation |
| 0x008 | `acUdf` | 56 B | `UDF_DATA_SIZE=56` |
| **0x040** | `acPpk` | `ACKey4096` (1088 B) | Primary Public Key |
| **0x480** | `acSpk` | `ACKey4096` (1088 B) | Secondary Public Key |
| **0x8C0** | `acSpkSignature` | `ACSignature4096` (512 B) | SPK signed by PSK |
| **0xAC0** | `acBhSignature` | `ACSignature4096` (512 B) | boot-header sig (used by BootROM) |
| **0xCC0** | `acPartitionSignature` | `ACSignature4096` (512 B) | partition sig |

`ACKey4096` (authkeys.h:122-128) = `N[512] + N_extension[512] + E[4] + Padding[60]` = **1088 bytes** (the 512-byte Montgomery `N_extension` is precomputed by Bootgen). 0x40 + 1088 = 0x480; 0x480 + 1088 = 0x8C0. `ACSignature4096` = `Signature[512]` (`RSA_SIGN_LENGTH_ZYNQMP=512`). readimage-zynqmp.cpp:456-469 re-derives sub-layout (`ppk_mod 0x40`, `ppk_mod_ext 0x240`, `ppk_exponent 0x440`, `spk_mod 0x480`, … `part_signature 0xcc0`). FSBL consumer header agrees: `XFSBL_AUTH_CERT_PPK_OFFSET 0x40`, `_SPK_OFFSET 0x480`, `_SPK_SIG_OFFSET 0x8C0` (xfsbl_authentication.h:85-87), `XFSBL_PPK_MOD_SIZE=512`, `XFSBL_HASH_TYPE_SHA3=48`.

`acHeader` packing (authentication-zynqmp.cpp:450-453): base `0x115` | `ppkSelect << 16` | `spkSelect << 18` | `(SHA2?1:0) << 2`. PPK select bits [17:16], SPK select bits [19:18], SHA-2/3 select bit [2].

**Hash/sign chain.** Default `hashType = Sha3` (SHA-3/384, cpp:130), RSA-4096. Padding is **PKCS#1 v1.5** built by hand (`CreatePadding`, cpp:284-360): `0x00 0x01 || 0xFF…(fill) || 0x00 || tPad || hash`, with SHA-3 ASN.1 T-pad `tPadSha3new = {30 41 30 0D 06 09 60 86 48 01 65 03 04 02 09 05 00 04 30}` (or pre-2016.1 `tPadSha3` if `-zynqmpes1`). Roles:
- **BH hash always Keccak** (BootROM verifies it): `GenerateBHHash` hashes the whole BH section (cpp:557-565), signs with SSK → `acBhSignature`.
- **SPK hash** over `acHdr || spkId || SPK`, signed by PSK → `acSpkSignature` (cpp:568-608).
- **PPK hash** (`GeneratePPKHash`, cpp:633-661) = SHA-3/384 over the full 1088-byte PPK — the digest burned into eFUSE as the root of trust.
- **Partition hash** NIST-SHA3 over partition‖AC-minus-final-sig, signed by SSK → `acPartitionSignature`.

### 6.5 AES-256-GCM encryption + .nky

Encryption is AES-256-GCM (`AesGcmEncryptionContext`, encryption-zynqmp.cpp:48,58). Constants (encryptutils.h:49-54): `AES_GCM_KEY_SZ=32` (256-bit), `AES_GCM_IV_SZ=12` (96-bit), `AES_GCM_TAG_SZ=16`, `SECURE_HDR_SZ=48`, `WORDS_PER_AES_KEY=8`. Keys/IVs from a `.nky` (Key0/IV0, optional seed-derived key rolling, optional `Key Opt` operational key). Per-partition IV incremented by partition number (cpp:750-753). Each block carries the rolled next key+IV in a GCM-protected "secure header" (cpp:761-784); the FSBL secure-header IV is the BH field at 0xA0. **The GCM tag (16 B) is the only integrity check on encrypted partitions** when authentication is off.

### 6.6 What an attacker must forge (on an *enforcing* device)

- **Authenticated path:** a PPK whose SHA-3/384 (over 1088-byte `ACKey4096`) matches the eFUSE PPK digest, AND valid RSA-4096 PKCS#1-v1.5 signatures over the boot header (Keccak), SPK, and each partition (NIST-SHA3). Without the private PSK/SSK this is infeasible (JustSTART / CVE-2023-20570 target area). The `headerChecksum` and IHT/PHT checksums are *not* cryptographic and recomputable — they protect nothing on their own.
- **Encrypted path:** the AES-256 red key (or ciphertext+valid GCM tags under the device key). Grey-key adds the family key (metal-baked, never exposed); black-key adds the PUF KEK (§5).
- **Dev-mode shortcut:** if `BH_RSA` (fsblAttributes [15:14]) selects boot-header authentication, the BootROM trusts the PPK *in the boot header* rather than the eFUSE digest — relevant if an attacker can set boot mode and the eFUSE PPK is unburned.

### 6.7 Empirical findings (board 210308BD8D4D)

**None of the forgery is required — secure boot is not enforced**, and live readback proves the root of trust is empty:
- **`EFUSE.SEC_CTRL @ 0xFFCC1058 = 0x00000000`** (enumerate-2026-06-08-134143.md:85-99): `RSA_EN[25:11]=0`, `ENC_ONLY[2]=0`, `SEC_LOCK[10]=0`, all PPK invalidate+writelock bits 0. BootROM accepts unsigned, unencrypted images.
- **PPK0 and PPK1 eFUSE digests all-zero** (:285-295 — `PPK0_0..PPK0_10` at `0xFFCC10A0…0xFFCC10C8` = 0). No root key committed.
- **`EFUSE.SPK_ID @ 0xFFCC105C = 0`** (:107); no SPK revocation.
- **No AES key**: CSU AES `STATUS.AES_KEY_ZEROED[8]=1` (:269-275).
- **PUF (BH-PUF style)**: `EFUSE.PUF_CHASH @ 0xFFCC1050 = 0` but `EFUSE.PUF_MISC @ 0xFFCC1054 = 0x10000000` (:105-106), and CSU PUF aperture `0xFFCA4000` shows live config (`0xFFCA400C=0x01000020`, `0xFFCA4010=0x00000002`). (Note: the bootgen-section narrative calls this "PUF is registered (BH-PUF style)" while §4/§5/§7 conclude **PUF unprovisioned** — see contradiction note. The reconciling fact: BH-PUF mode leaves CHASH=0 even when PUF is in use, so a zero CHASH alone cannot distinguish "unprovisioned" from "BH-PUF in use." On this dev board the surrounding zero state (SEC_CTRL=0, no AES key) makes "unprovisioned" the supported reading.)
- **The boot header is NOT in OCM.** Fresh-boot OCM capture `dumps/ocm-...freshboot...bin` begins with `4E 02 00 14` at `0xFFFC0000` — an AArch64 branch (`0x14000…`, FSBL entry), **not** the BH width-detection word `0xAA995566`. Confirms docs/12 §0: the BootROM copies only the FSBL code body; the BH/IHT/PHT/AC stay on the boot device and are consumed in place. A JTAG OCM read cannot see/forge the boot header.
- **DNA available** (:27-30): `0x44804345 / 0x0170CFA7 / 0x40000000` — input to PUF/black-key, not directly to image forgery.

### 6.8 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **On THIS board, image forgery is moot** — secure boot disabled (`SEC_CTRL=0`, zero PPK, no AES key). An attacker who controls the boot device can boot arbitrary unsigned/unencrypted FSBLs with only the public, recomputable checksums correct. Consistent with the project's validated COLD-mode injection work.
- **Defeating an *enforcing* device is out of reach by the constraints** — requires the private RSA keys (infeasible) or the AES/PUF-KEK/family secrets (PUF helper data is extractable live per §4, but the derived KEK/red key is not, and the family key is metal-baked). The bootgen layout tells us precisely *what* must be forged; it provides no bypass.
- **`BH_RSA` dev-mode auth** worth flagging on any target whose eFUSE PPK is unburned but `RSA_EN` is set — on this board `RSA_EN=0`, irrelevant.
- **Honest limit:** the on-flash structures are not in the AXI/OCM space we can JTAG-read at idle; verifying a real on-device boot header requires reading the QSPI/SD medium (Phase-7 boot-medium track).

**Uncertainties:** `acHeader` SPK-select width [19:18] is inferred, not pinned to a TRM bit-range. `EFUSE_GREY` vs `EFUSE_GRY` and the CBR's runtime decode order of `encryptionKeySource` is not closed from source (only the Bootgen *encode* side is confirmed).

---

## 7. eFuse & BBRAM

### 7.1 What it is and its role in secure boot

The root-of-trust is anchored in two non-volatile stores in the Low-Power Domain (LPD):

- **eFuse (PS eFuse controller)** — OTP polysilicon fuses holding *immutable* security policy and key/identity material: secure-boot enable bits (`SEC_CTRL`), RSA public-key hashes (PPK0/PPK1), the 256-bit AES boot key (optional eFuse variant), the SPK-ID revocation word, USER fuses, the chip-unique 96-bit Device DNA, and the PUF helper-data fingerprint (CHASH/AUX). Programming is destructive and irreversible; bits go 0→1 only.
- **BBRAM (Battery-Backed RAM)** — a 256-bit *volatile, battery-retained* AES key store. Holds **only a red (plaintext) AES-256 key**. Re-keyable and zeroizable (unlike eFuse), but its key cannot be read back over any interface — programming is verified by CRC32 alone.

At boot the BootROM/CSU consults eFuse `SEC_CTRL` to decide RSA enforcement, encryption, which PPK to trust, and which AES key source to use. The FSBL re-reads the same fuses to enforce policy on subsequent partitions (§2). On board 210308BD8D4D every policy fuse reads **zero** — a clean unprovisioned dev part — so none of this enforcement is active.

### 7.2 Exact register map

Sources: xilskey_eps_zynqmp_hw.h / xilskey_bbramps_zynqmp_hw.h (authoritative), corroborated by the QEMU model and captures.

**eFuse controller — base `0xFFCC0000`** (hw.h:48):

| Reg | Addr | Reset | Notes |
|---|---|---|---|
| `WR_LOCK` | `0xFFCC0000` | `0x1` | unlock by writing magic `0xDF0D` |
| `CFG` | `0xFFCC0004` | `0x0` | PGM_EN[1], CLK_SEL[0], MARGIN_RD[3:2] |
| `STATUS` | `0xFFCC0008` | — | AES_CRC_PASS[7], AES_CRC_DONE[6], CACHE_DONE[5], CACHE_LOAD[4], TBIT[2:0] |
| `PGM_ADDR` | `0xFFCC000C` | row/col packing for burn |
| `RD_ADDR`/`RD_DATA` | `0xFFCC0010`/`0x14` | raw fuse read path |
| `TPGM/TRD/TSU_*` | `0xFFCC0018–002C` | program/read timing |
| `ISR/IMR/IER/IDR` | `0xFFCC0030–003C` | APB_SLVERR[31], CACHE_ERR[4], RD/PGM done/err |
| `CACHE_LOAD` | `0xFFCC0040` | bit0 triggers cache reload |
| `PGM_LOCK` | `0xFFCC0044` | SPK_ID_LOCK[0] field (program-lock for the SPK-ID fuse) |
| `AES_CRC` | `0xFFCC0048` | write-only CRC of AES key to verify a burn |

**eFuse cache (shadow read view) — base `0xFFCC1000`:**

| Field | Addr | Width |
|---|---|---|
| `DNA_0/1/2` | `0xFFCC100C/1010/1014` | 96-bit chip-unique ID |
| `USER_0..7` | `0xFFCC1020–103C` | 8×32-bit |
| `MISC_USER_CTRL` | `0xFFCC1040` | USR_WRLK[7:0], LBIST_EN[10], LPD_SC_EN[13:11], FPD_SC_EN[16:14] |
| `PBR_BOOT_ERR` | `0xFFCC1044` | [2:0] |
| `PUF_CHASH` | `0xFFCC1050` | 32-bit (§4) |
| `PUF_MISC` | `0xFFCC1054` | AUX[23:0], SYN_INVLD[29], SYN_WRLK[30], REG_DIS[31] (§4) |
| **`SEC_CTRL`** | **`0xFFCC1058`** | whole security policy (below) |
| `SPK_ID` | `0xFFCC105C` | SPK revocation id |
| `PPK0_0..11` | `0xFFCC10A0–10CC` | 12×32 = 384-bit SHA-3-384 hash of PPK0 |
| `PPK1_0..11` | `0xFFCC10D0–10FC` | 12×32 = PPK1 hash |

**`SEC_CTRL` @ `0xFFCC1058` — the cardinal policy register** (xilskey_eps_zynqmp_hw.h:763–849; decode in xilskey_eps_zynqmp.c:624–682):

| Bits | Name | Mask | Effect when set |
|---|---|---|---|
| `[0]` | AES_RDLK | `0x00000001` | AES eFuse key read-locked |
| `[1]` | AES_WRLK | `0x00000002` | AES eFuse key write-locked |
| `[2]` | ENC_ONLY | `0x00000004` | encrypt-only boot forced |
| `[3]` | BBRAM_DIS | `0x00000008` | BBRAM key source disabled |
| `[4]` | ERR_DIS | `0x00000010` | error-out behaviour disabled |
| `[5]` | JTAG_DIS | `0x00000020` | **disables all JTAG TAPs** |
| `[6]` | DFT_DIS | `0x00000040` | disables DFT/scan access |
| `[7:9]` | PROG_GATE_0/1/2 | `0x00000380` | PMU programming-interface gates |
| `[10]` | SEC_LOCK (LOCK) | `0x00000400` | locks further SEC_CTRL writes |
| `[25:11]` | RSA_EN | `0x03FFF800` | 15-bit magic enabling RSA auth (≥ silicon v3.0; for v1/v2 it is bits [25:14]) |
| `[26]` | PPK0_WRLK | `0x04000000` | PPK0 hash write-lock |
| `[28:27]` | PPK0_INVLD | `0x18000000` | PPK0 revoked |
| `[29]` | PPK1_WRLK | `0x20000000` | PPK1 hash write-lock |
| `[31:30]` | PPK1_INVLD | `0xC0000000` | PPK1 revoked |

These widths/positions are from the header and correct any earlier loose summaries. The silicon-version branch (xilskey_eps_zynqmp.c:658–669) is why the RSA_EN shift differs across revisions. The QEMU model corroborates `JTAG_DIS bit5`, `DFT_DIS bit6` (qemu 2987–2988). This is the same `EFUSE_SEC_CTRL` the FSBL reads (§2.5) and the same address the JTAG-gate eFuses live in (§10).

**BBRAM controller — base `0xFFCD0000`** (xilskey_bbramps_zynqmp_hw.h:47) — a *separate* block from the eFuse cache, **not** `0xFFCC1000`:

| Reg | Addr | Notes |
|---|---|---|
| `BBRAM_STS` | `0xFFCD0000` | AES_CRC_PASS[9], AES_CRC_DONE[8], ZEROIZED[4], PGM_MODE[0] |
| `BBRAM_CTRL` | `0xFFCD0004` | ZEROIZE[0] |
| `BBRAM_PGM_MODE` | `0xFFCD0008` | write magic `0x757BDF0D` to enter program mode |
| `BBRAM_AES_CRC` | `0xFFCD000C` | write CRC to trigger verify |
| `BBRAM_0..8` | `0xFFCD0010–0030` | 9×32-bit (256-bit key + CRC row) |
| `BBRAM_SLVERR/ISR/IMR/IER/IDR` | `0xFFCD0034–0044` | slave-error/interrupt |

(Note: §5.5 referenced a `BBRAM.CTL/STATUS/LOCK` triple at `0xFFCD0020/24/28`; this authoritative xilskey map puts STS/CTRL/PGM_MODE/AES_CRC at `0xFFCD0000–000C` and the key words at `0xFFCD0010–0030`. See contradiction note.)

### 7.3 Boot-time behavior & vendor read/program flow

- **Cache load**: at POR the controller copies the fuse array into the `0xFFCC1xxx` shadow cache; software can force a reload by writing bit0 of `CACHE_LOAD` (`0xFFCC0040`) and polling `STATUS.CACHE_DONE` (`XilSKey_ZynqMp_EfusePs_CacheLoad`, xilskey_eps_zynqmp.c:1121–1166). This is why captured `STATUS=0x27` has `CACHE_DONE=1`.
- **Unlock-to-program**: writing fuses or forcing a cache reload first requires clearing `WR_LOCK` via the `0xDF0D` magic (`CtrlrUnLock`, c:1128). `WR_LOCK=1` at idle is the *normal locked default*, not provisioning.
- **FSBL policy enforcement** (boot-time gates): ENC_ONLY (`xfsbl_image_header.c:625–630`, `xfsbl_initialization.c:1237`); RSA_EN (`xfsbl_authentication.c:98,183`, `xfsbl_initialization.c:1259–1295`); PPK revocation (`xfsbl_authentication.c:440–446,481–492`). See §2.
- **BBRAM program flow** (xilskey_bbramps_zynqmp.c): enter program mode (magic `0x757BDF0D`) after a forced zeroize (207–259), write 8 key words to `BBRAM_0..7` (101–106), write computed CRC to `BBRAM_AES_CRC` (111), poll `STS.AES_CRC_DONE` then check `STS.AES_CRC_PASS` (114–135). **No read path** — verification CRC-only. `Zeroise` (150–195) wipes the key, sets `STS.ZEROIZED`. As of xilskey 6.9 BBRAM programming is disabled after AES-key programming.

### 7.4 Empirical findings (board 210308BD8D4D, JTAG-idle, DAP-NS)

Read non-destructively over JTAG; cross-referenced against enumerate-2026-06-08-134143.md, memory `project_correct_addresses_findings.md`, `reference_hashes_keys_security.md`.

- **`SEC_CTRL @ 0xFFCC1058 = 0x00000000`** — the entire policy is *unblown*: RSA_EN=0, ENC_ONLY=0, JTAG_DIS=0, DFT_DIS=0, SEC_LOCK=0, AES_RDLK=0, AES_WRLK=0, BBRAM_DIS=0, PROG_GATE=0, PPK0/1 not write-locked or revoked. **This corrects the obsolete "=0x07" reading**, which came from the wrong address `0xFFCC002C` (memory `project_sec_ctrl_correction.md`, itself retracted).
- **`STATUS @ 0xFFCC0008 = 0x00000027`** — CACHE_DONE=1, TBIT 0/2/3 set (standard dev-silicon trim signature).
- **`WR_LOCK @ 0xFFCC0000 = 0x1`** — locked default (expected).
- **`PGM_LOCK @ 0xFFCC0044 = 0`, `AES_CRC @ 0xFFCC0048 = 0`** — no AES eFuse key burned.
- **Device DNA** (`0xFFCC100C/1010/1014`) = `0x44804345 / 0x0170CFA7 / 0x40000000` → 96-bit `0x40000000_0170CFA7_44804345`. Permanent, chip-unique, freely readable — the canonical fingerprint for this part.
- **PPK0 hash** (`0xFFCC10A0–10CC`) and **PPK1 hash** (`0xFFCC10D0–10FC`) = **all-zero** → no RSA root of trust.
- **`SPK_ID @ 0xFFCC105C = 0`**, **USER_0..7 = 0** → no SPK revocation, no user fuses.
- **`MISC_USER_CTRL @ 0xFFCC1040 = 0x00000100`** (bit 8; reserved/test region, not USR_WRLK/SC_EN), **`PUF_CHASH @ 0xFFCC1050 = 0`**, **`PUF_MISC @ 0xFFCC1054 = 0x10000000`** (bit 28; PUF unprovisioned, §4).
- **BBRAM** (`0xFFCD0000`+): all key words `0xFFCD0010–002C = 0`, `BBRAM_STS = 0` — no red key present, not zeroized-flagged. Because `JTAG_SEC=0x3F` (DAP open) and `SEC_CTRL.BBRAM_DIS=0`, all-zero almost certainly means *no key* rather than read-protected. This board likely has no coin-cell, so BBRAM would clear regardless.
- **No SLVERR/unmapped faults** reading the eFuse-cache aperture in the full CSU/LPD map sweep — the eFuse cache is fully readable from DAP-NS on this part.

### 7.5 Security properties, gates, and what a hardened board would show

- eFuse is **OTP and append-only**; once `SEC_LOCK` (bit 10) is blown, `SEC_CTRL` can no longer change. `WR_LOCK` gates *all* programming until the `0xDF0D` magic is written.
- The **AES eFuse key is the only key with a read-lock** (`AES_RDLK` bit 0); when blown the cache words read as zero. **BBRAM has no read path by design.**
- A **production / hardened** board would typically show: `SEC_CTRL.RSA_EN` = the 15-bit enable magic, **non-zero PPK0 (and possibly PPK1) hashes**, `ENC_ONLY=1` if encrypt-only, `AES_WRLK=1`/`AES_RDLK=1`, `SEC_LOCK=1`, plausibly **`JTAG_DIS=1`** and/or `DFT_DIS=1`. With `JTAG_DIS=1` the DAP/PL/PMU TAPs go silent — none of the JTAG-idle reads here would be possible. `PUF_CHASH`/`PUF_MISC.AUX` non-zero on a PUF-provisioned part. `BBRAM_DIS=1` would forbid the BBRAM key source.

### 7.6 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Readable now (high value, low effort):** the entire eFuse cache and BBRAM key window are exposed over DAP-NS with no gate on *this* part — the full security posture in one shot (`SEC_CTRL`), the chip-unique DNA, confirmation no RSA/AES/PUF root-of-trust exists, and a definitive "BBRAM empty" reading. Safe to run on any board.
- **Genuinely blocked:** cannot read back a BBRAM red key on *any* board (no read path); cannot read an AES eFuse key once `AES_RDLK` is blown (caches as zero); on a hardened board with `JTAG_DIS=1` the entire read surface vanishes.
- **Destructive/declined here:** `SEC_CTRL`/fuse array *can* be burned via `0xDF0D` unlock + `PGM`, and BBRAM *can* be zeroized (single write of `CTRL.ZEROIZE`) — a one-write DoS that destroys a provisioned BBRAM key. Neither exercised (irreversible/destructive, violating the non-destructive constraint). The DoS is catalogued as attack-chain "BBRAM zeroize" but deliberately not executed.
- **Bottom line for this board:** because `SEC_CTRL=0`, eFuse/BBRAM impose *no* obstacle — but they also hold *no* secret worth stealing (no keys, no PPK). The only durable secret extractable here is the Device DNA. The subsystem's real attack surface (read-locked AES key, BBRAM zeroize-DoS, RSA/ENC bypass) only becomes meaningful on a *provisioned* part, where most of it is then re-gated by `JTAG_DIS`/`AES_RDLK`/the BBRAM no-read design.

---

## 8. PMU firmware, PM API & IPI

### 8.1 What it is and its role in secure boot

The Platform Management Unit (PMU) is a triple-redundant MicroBlaze that is the **first thing alive** on ZynqMP and the only master that stays in control of every power domain, reset, and isolation gate for the life of the system. At cold reset the PMU runs **PMU ROM** (32 KB at `0xFFD00000`), which loads and jumps into **PMU firmware** running out of **PMU LMB RAM at `0xFFDC0000` (128 KB)** (docs/12:57-62; docs/11:83). After bring-up the PMU FW is a permanently resident service: the APU (ATF at EL3-Secure) and the RPU R5s issue **PM API** calls over the **IPI** (Inter-Processor Interrupt) mailbox to power-gate cores/peripherals, assert/deassert resets, set clocks, and — on secure parts — proxy crypto/MMIO operations. In secure boot the PMU owns the *power and reset* half of the chain-of-trust.

For an attacker the PMU FW is a **deputy with more privilege than its callers**: it can touch CSU/AES/RSA/SHA/eFuse-adjacent registers a normal master cannot, and it accepts commands over a mailbox whose only notion of "who is calling" is *which IPI hardware channel raised the interrupt* — there is no cryptographic caller authentication (§8.5).

### 8.2 Key registers, addresses and regions

IPI block (one 256-byte agent window per master, plus a shared `0xFF990000` message-buffer region):

| Element | Address | Source |
|---|---|---|
| IPI agent register block (TRIG/OBS/ISR/IMR/IER/IDR) — APU agent | `0xFF300000` | qemu `IPI_TRIG` (zynqmp-regs-qemu.tcl:4832-4848); enumerate.md:796 |
| `IPI_TRIG` (doorbell) | `+0x00`: APU=bit0, RPU_0=bit8, RPU_1=bit9, PMU_0=bit16…PMU_3=bit19, PL_0..3=bit24..27 | qemu 4836-4848 |
| `IPI_OBS` (observation/pending) | `+0x04`, same bit layout | qemu 4850-4866 |
| `IPI_ISR` | `+0x10`, same bit layout | qemu 4868-4884 |
| `IPI_IMR` | `+0x14` | qemu 4886- |
| APU→PMU0 **request** message buffer | `0xFF9905C0` = APU_BASE(0xFF990400)+TARGET_PMU(0x1C0)+REQ(0x0) | mem `project_phase7_ipi_validated.md:53` |
| APU→PMU0 **response** buffer | `0xFF9905E0` (+RESP 0x20) | mem :54 |
| PMU-initiated remote req/resp (NOT used by an APU caller) | `0xFF990E80` / `0xFF990EA0` | mem :56 |

> Caveat: the `0xFF990400`/`0x1C0`/`0x20` decomposition comes from this project's reconstruction of the TF-A `IPI_BUFFER` layout / `zynqmp.dtsi`, not from the QEMU dict (which models the IPI *control* block at `0xFF300000`, not the message-buffer RAM at `0xFF990000`). The **endpoint addresses `0xFF9905C0`/`0xFF9905E0` are empirically validated** (a real PMU response landed there); the internal arithmetic is the documented derivation.

Per-master IPI masks (`IPI_PMU_0_IER_*_MASK`) are BSP-generated `XPAR_XIPIPS_TARGET_*_CH0_MASK` (xpfw_ipi_manager.h:26-40); on standard ZynqMP: APU CH0 = bit 0, RPU0 CH0 = bit 8, RPU1 CH0 = bit 9 — matching the `IPI_TRIG` map.

PMU memory/state regions (enumerate.md:311-341; docs/11:65-66,83):

- PMU instruction ROM — `0xFFD00000` (32 KB)
- PMU LMB RAM — `0xFFDC0000` (128 KB)
- `PMU_GLOBAL` base — `0xFFD80000`
- `GLOBAL_CNTRL` — `0xFFD80000`
- `PWR_STATE` — `0xFFD80100`
- `REQ_PWRUP_STATUS` — `0xFFD80110`

PM-API error codes: `XST_PM_NO_ACCESS = 2002 = 0x7D2`, `XST_PM_INVALID_NODE = 2003`, `XST_PM_DOUBLE_REQ = 2004 = 0x7D4` (pm_defs.h:226-228).

### 8.3 Boot-time behavior and the IPI/PM-API control flow

`XPfw_PmInit()` runs once at PMU FW startup: on `PM_COLD_BOOT` builds the master table (`PmMasterDefaultConfig()`) and node graph (`PmNodeConstruct()`), snapshots `CSU_MULTI_BOOT`, and — under `ENABLE_SECURE_FLAG` — calls `initApiPermissions()` from `defaultApiPermissions[]` (pm_binding.c:347-373).

Every PM request arrives as an IPI interrupt:
1. `XPfw_PmCheckIpiRequest()` reads payload word[0], accepts only if `(apiId & 0xFF)` strictly between `PM_API_MIN` and `PM_API_MAX` (pm_binding.c:499-522).
2. `XPfw_PmIpiHandler()` resolves the caller via `PmGetMasterByIpiMask(IsrMask)`, dispatches `PmProcessRequest(master, Payload)` (pm_binding.c:391-407).
3. `PmProcessRequest()` (pm_core.c:2468-2578): `PmApiApprovalCheck`; under `ENABLE_SECURE_FLAG`, range-validate the API id, extract the TF-A secure flag from **bit 24** of word[0] (`extractSecureFlagTfa`, pm_binding.c:332-339), read the **TrustZone bit** for the caller's channel from APERPERM (`readTrustzoneBit`, base `0xFF9810C0` + channel*4, bit 27 → pm_binding.c:80-83,191-225), gate via `isApiAllowed`; then a big `switch(apiId)`.

Request word layout (ZynqMP, *not* Versal — no module header): word[0] = bare API id (optional secure flag bit 24), word[1..n] = args. Blocking completion protocol for an APU caller: write the PMU0 doorbell bit (`IPI_TRIG` bit 16), **poll `IPI_OBS` bit 16 to clear** (PMU consumed/responded), then read the response buffer.

Key handlers:
- `PM_MMIO_READ` → `PmMmioRead()` (pm_core.c:851-868): gate on `PmGetMmioAccessRead`, else `XST_PM_NO_ACCESS`; on pass, `value = XPfw_Read32(address)` via `IPI_RESPONSE2`.
- `PM_MMIO_WRITE` → `PmMmioWrite()` (pm_core.c:820-841): gate on `PmGetMmioAccessWrite`; on pass, `XPfw_RMW32(address, mask, value)`.
- `PM_REQUEST_NODE` → `PmRequestNode()` (pm_core.c:619-670): slaves only; rejects unknown master/slave pairs `XST_PM_NO_ACCESS`, already-requested `XST_PM_DOUBLE_REQ`.
- `PM_REQUEST_WAKEUP` → `PmRequestWakeup()` (pm_core.c:501-559): processor nodes; checks `PmMasterCanRequestWake`, optionally saves resume address (`pload[2]` bit 0 = set-address flag), on RPU calls `PmProbeRpuState()` then `PmMasterWakeProc()` — the primitive that powers and starts the R5.

### 8.4 The MMIO access ACL (`pm_mmio_access.c`) — the core gate

`PmGetMmioAccess()` (pm_mmio_access.c:1053-1082) scans the static `pmAccessTable[]` (:178-1001); for each entry bracketing the target address it tests `access & mask`, where `mask = master->ipiMask` for reads, `master->ipiMask << 16` for writes (`WRITE_PERM_SHIFT=16`). Encoding: `MMIO_ACCESS_RO(m)=m`, `MMIO_ACCESS_WO(m)=m<<16`, `MMIO_ACCESS_RW(m)=m|(m<<16)` (:22-25). Read and write are independent bitfields in one word, keyed per master IPI mask.

Allowlisted (selected): CRF_APB/CRL_APB clock & reset sub-ranges (RW to APU+RPU0+RPU1); `PMU_GLOBAL_PWR_STATE` (RW APU only) + gen-storage scratch; IOU_SLCR ranges; boot-pin reg `CRL_APB+0x250`; SW FPD/LPD reset regs; a large **RO** CSU status surface (`CSU_BASEADDR`, IDCODE..VERSION, `CSU_ROM_DIGEST_0..11`, `CSU_AES_STATUS`, `CSU_PCAP_STATUS`, `CSU_JTAG_CHAIN_STATUS`, `CSU_FT_STATUS`, `CSU_MULTI_BOOT` RW, `CSU_TAMPER_TRIG` WO); and a very large CSU/AES/RSA/SHA/CSUDMA RW+WO surface — but **only inside `#ifdef SECURE_ACCESS`** (:524-990). That guard is the difference between a hardened production PMU FW and a "secure-services" build; without `SECURE_ACCESS`, those CSU/AES/RSA registers are absent from the table → no master can reach them via the PM proxy.

Critically, **`pmAccessTable[]` contains no entry for eFuse cache (`0xFFCC1058`), PMU ROM (`0xFFD00000`), or arbitrary OCM/DDR**, so a `PM_MMIO_READ` of those falls through the scan → `XST_PM_NO_ACCESS`. (`ENABLE_MEM_RANGE`/`addressTable[]` at :32-161 is a *separate*, optional length-checked allowlist used by self-suspend/wakeup/crypto-image paths, mostly DDR; it defaults to "allow any" if empty — `PmIsValidAddressRange` :1016-1041 — itself a soft default worth noting.)

### 8.5 Security properties and gates

1. **Caller identity = IPI hardware channel, not crypto.** `PmGetMasterByIpiMask()` (pm_master.c:411-423) maps the ISR mask to a `PmMaster` purely by channel bit. Anyone who can drive the APU's IPI doorbell *is* the APU to the PMU FW. By design (the IPI fabric is the trust boundary) — but an attacker with EL3 on an APU core inherits the APU's full PM-API rights.
2. **Per-API allow/deny** via `apiPermissionBitmap` (2 bits/API: secure, non-secure). The shipped `defaultApiPermissions[]` grants `PMU_API_FULL_ACCESS` to essentially everything (incl. `PM_MMIO_READ/WRITE`, `PM_REQUEST_WAKEUP/NODE`); the only `PMU_API_NO_ACCESS` default is `PM_CLOCK_SETRATE` (pm_binding.c:142). The API-level gate is essentially open by default; the real MMIO filtering is the address ACL.
3. **TrustZone gating** (only with `ENABLE_SECURE_FLAG`): effective secure flag = `secureChannel && secureFlag` — both the channel's APERPERM TZ bit (`0xFF9810C0`+ch*4, bit 27) and payload bit 24 must indicate secure.
4. **MMIO address ACL** (§8.4) — the load-bearing gate that keeps secrets out of the proxy.
5. **Node-graph requirements** gate `PM_REQUEST_NODE`/`PM_REQUEST_WAKEUP`: only statically-declared master/slave pairs accepted; processors can't be "requested" as nodes (they must be woken).

### 8.6 Empirical findings (board 210308BD8D4D)

**JTAG-idle (no PMU FW running):** the chain is *closed*. With the PMU in `MB_SLEEP` and no PM handler, an A53-EL3 IPI to PMU0 produced no response — CONFIRMED-CLOSED; PMU ROM is additionally eFuse-locked (`SSSS_PMU_SEC` gated; enumerate.md:60; docs/12:32-33; see §10).

**Booted (SD-boot PetaLinux 2025.1: FSBL+PMU FW+ATF+U-Boot+Linux 6.12.10):** the chain is *open and validated*. Using the `reset_release_a53_core0` "BOOTED_STATE" primitive (halt secondaries → assert `RST_FPD_APU=0x501` at `0xFD1A0104` → set RVBAR + deassert → core 0 re-enters at landing pad `0xFFFC0000` at EL3H, MMU off), a JTAG-driven A53 impersonating the APU drove the live PM API (mem `project_phase7_ipi_validated.md:29-47`):

- `PM_GET_API_VERSION` → status 0, version `0x00010001` (PM API v1.1), cross-checked vs Linux `/sys/.../zynqmp-firmware/pm`.
- `PM_GET_CHIPID` → IDCODE `0x24738093` (XCZU9EG), version `0x20000513`.
- `PM_MMIO_READ 0xFF5E0020` (CRL clk, allowlisted) → SUCCESS `0x2d00`; `PM_MMIO_READ 0xFD1A0020` (CRF clk) → SUCCESS `0x14800`.
- `PM_MMIO_READ 0xFFCC1058` (eFuse SEC_CTRL cache) → **`XST_PM_NO_ACCESS 0x7D2`**; `PM_MMIO_READ 0xFFD00000` (PMU ROM) → **`0x7D2`**. Both negatives match the ACL exactly (neither in `pmAccessTable[]`). **Chain 4 (use PMU FW as exfil proxy for eFuse/PMU-ROM) is CLOSED** — clean negative finding, not a vuln.
- **RPU/TCM wake — Chain 2 capstone (positive):** `PM_REQUEST_NODE(NODE_TCM_0_A=0xF)` / `(NODE_TCM_0_B=0x10)` → status 0 (or `XST_PM_DOUBLE_REQ 0x7D4` if already requested = still effective); TCM at `0xFFE00000`/`0xFFE20000` went from ERR (gated) to live writable RAM. `PM_REQUEST_NODE(NODE_RPU_0=7)` → `0xF` rejected (processors aren't powered via REQUEST_NODE), but `PM_REQUEST_WAKEUP(NODE_RPU_0=7, encAddr=0x1, hi=0, ack=BLOCK)` → status 0: the R5 powered up and executed a 7-instruction stub from TCM low-vector, writing marker `0x600D5A11` to `0xFFE01000`, confirmed via JTAG read. Pack format: word0=10, word1=node, word2=encAddr_lo (bit0 = set-address flag), word3=encAddr_hi, word4=ack — matches `PmRequestWakeup`'s `setAddress = pload[2] & 0x1` decode (pm_core.c:2527-2532).

Net: on a booted board a JTAG/EL3 attacker can, through the PM API, **power on and start the RPU running arbitrary code** and power otherwise-gated slave nodes (TCM) — a demonstrated capability that unblocks the R5 BootROM-dump path (R5 has a different bus-master ID than A53; relevant to §1.6, §9, §10).

### 8.7 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Reachable / proven:** with JTAG + EL3 on an APU core in booted state, the full PM-API surface granted to the APU is reachable because identity is channel-based, not authenticated — RPU power-on + arbitrary R5 code start, TCM power, allowlisted clock/reset MMIO, CHIPID/API-version, and (on a `SECURE_ACCESS` build) potentially the CSU/AES/RSA proxy surface. Within the debug threat model (JTAG enabled) but a real privilege/lateral-movement primitive.
- **Blocked / honest negatives:** the PM proxy is **not** a secret-exfil shortcut. eFuse cache (`0xFFCC1058`), PMU ROM (`0xFFD00000`), and arbitrary OCM/DDR are absent from `pmAccessTable[]` → `XST_PM_NO_ACCESS` (verified on hardware). The ACL is enforced exactly as written; not disclosure-worthy as a vulnerability.
- **In JTAG-idle (no FW), nothing here is reachable** — the PMU isn't servicing IPIs. The entire capability is contingent on PMU FW running.
- **Unverified-on-this-board:** the `SECURE_ACCESS`-guarded CSU/AES/RSA proxy entries — whether the shipped PetaLinux PMU FW was built with `SECURE_ACCESS` was not confirmed; the probes above only exercise unconditional table entries and the absence-of-entry path. Open, falsifiable next probe.

---

## 9. Memory & peripheral TrustZone (XMPU / XPPU)

### 9.1 What it is and its role in secure boot

ZynqMP does **not** use an ARM TZASC/TZMA for memory partitioning. Xilinx built two custom protection-unit families:

- **XMPU (Xilinx Memory Protection Unit)** — gates which AXI master may **read/write a memory *range***. Eight instances guard memory: six **DDR_XMPU0..5**, one **FPD_XMPU** on the full-power-domain master bus, one **OCM_XMPU** for on-chip SRAM. Each instance has 16 region descriptors (R00..R15) carrying START/END, allowed MasterID + mask, and a CONFIG word (read/write-allow, NS/secure, region-enable).
- **XPPU (Xilinx Peripheral Protection Unit)** — gates which AXI master may access which **LPD peripheral *aperture*** (64 KB / 1 MB / 512 MB banks). One instance in the LPD covers UART/I2C/SPI/CAN/GEM/QSPI/SD/TTC/SWDT/GPIO/IPI/etc.

In the secure-boot model these are the *runtime* memory/peripheral isolation layer: after CSU+FSBL authenticate and place ATF/TEE in secure OCM/DDR, the XMPU/XPPU keep a non-secure/untrusted master (PL master, DAP, rogue DMA, Linux EL1) from reading the TEE's secure DRAM or touching a secure peripheral. They are configured (or deliberately bypassed) by FSBL/`psu_init`, locked, and policed by the PMU's Error Manager (§8).

### 9.2 Key registers, addresses, and regions

Instance bases from the PMU firmware driver `xpfw_xpu.c:11-20` (authoritative), cross-checked against the QEMU model and golden capture:

| Block | Base | Source |
|---|---|---|
| DDR_XMPU0 | `0xFD000000` | xpfw_xpu.c:11; qemu DDR_XMPU0.* |
| DDR_XMPU1 | `0xFD010000` | xpfw_xpu.c:12 |
| DDR_XMPU2 | `0xFD020000` | xpfw_xpu.c:13 |
| DDR_XMPU3 | `0xFD030000` | xpfw_xpu.c:14 |
| DDR_XMPU4 | `0xFD040000` | xpfw_xpu.c:15 |
| DDR_XMPU5 | `0xFD050000` | xpfw_xpu.c:16 |
| FPD_XMPU | `0xFD5D0000` | xpfw_xpu.c:17 |
| OCM_XMPU | `0xFFA70000` | xpfw_xpu.c:18 |
| XPPU | `0xFF980000` | xpfw_xpu.c:19 |
| XPPU poison sink | `0xFF9CFF00` | xpfw_xpu.c:20 |

**XMPU instance register layout** (control page — verified against QEMU for OCM_XMPU @ `0xFFA70000` and DDR_XMPU0 @ `0xFD000000`):
- `+0x00 CTRL` — `[3]ALIGNCFG [2]HIDEALLOWED [1]DEFWRALLOWED [0]DEFRDALLOWED`
- `+0x10 ISR`, `+0x14 IMR`, `+0x18 IEN`, `+0x1C IDS` — each `[3]SECURITYVIO [2]WRPERMVIO [1]RDPERMVIO [0]INV_APB`
- `+0x20 LOCK` — `[0]REGWRDIS` (once set, region/CTRL registers read-only until POR)
- `+0xDC ECO`

The 16 **region descriptors live at `0x100+`** as R00..R15 each with START/END/MASTER/CONFIG words (UG1085 §16 / UG1087 "XMPU_OCM"/"XMPU_DDR"). **Caveat:** the QEMU tcl models only the control-page registers — not the per-region START/END/MASTER/CONFIG offsets — so no exact region-stride byte offset is pinned from our source-of-truth; the descriptor block at `0x100+` is from UG1085, not from capture. The PMU driver fixes the XPU status-page offsets it polls: `ISR +0x10`, `IER +0x18`, `ERR_STATUS_1 +0x04`, `ERR_STATUS_2 +0x08`, `POISON +0x0C` (xpfw_xpu.c:23-27).

**XPPU register layout** (golden capture §13 + QEMU `xlnx-xppu.h`):
- `0xFF980000 CTRL` — `[2]APER_PARITY_EN [1]MID_PARITY_EN [0]ENABLE`
- `0xFF980004 ERR_STATUS1` (poisoned address upper bits), `0xFF980008 ERR_STATUS2` — `[9:0]AXI_ID` (offending MasterID)
- `0xFF98000C POISON` (no QEMU model; bit fields unverified)
- `0xFF980010 ISR` / `0xFF980014 IMR` — `[7]APER_PARITY [6]APER_TZ [5]APER_PERM [3]MID_PARITY [2]MID_RO [1]MID_MISS [0]INV_APB`
- aperture geometry: `M_APERTURE_64KB 0xFF980044`, `M_APERTURE_1MB 0xFF980048`, `M_APERTURE_512MB 0xFF98004C`; `BASE_64KB 0xFF980054`, `BASE_1MB 0xFF980058`, `BASE_512MB 0xFF98005C`
- **MasterID permission table**: 20 slots at `0xFF980100..0xFF98014C`, each `[31]parity [30]read-only [29:20]MID-mask [9:0]MID`; the 1 KB aperture permission RAM follows per UG1085.

**The MasterID encoding** (authoritative LUT, xpfw_xpu.c:52-85) — security-critical for cross-master reasoning:
`RPU0=0x00-0x0F, RPU1=0x10-0x1F, PMU-MB=0x40, CSU-MB=0x50, CSU-DMA=0x51, USB0/1=0x60/0x61, DAP=0x62, ADMA=0x68-0x6F, SD0/1=0x70/0x71, NAND=0x72, QSPI=0x73, GEM0-3=0x74-0x77, APU=0x80-0xBF, SATA=0xC0-0xC3, GPU=0xC4, CoreSight=0xC5, PCIe=0xD0, DPDMA=0xE0-0xE7, GDMA=0xE8-0xEF, AFI-FM0-5=0x200-0x37F, AFI-FM-LPD=0x380-0x3BF`. **The JTAG debugger's AXI mem-AP issues transactions as MasterID 0x62 (DAP)** — the single most relevant fact for the attack surface.

### 9.3 Boot-time behavior — how the vendor source drives it

**On the default ZCU102 flow, XMPU/XPPU are mostly *bypassed*, not configured.** Two layers:

1. **FSBL handoff** (xfsbl_handoff.c:1183-1206): the comment states *"FSBL shall bypass XPPU and FPD XMPU configuration BY DEFAULT… for the hardware, isolation will only be limited to just OCM."* With `XFSBL_PROT_BYPASS` it calls only `psu_apply_master_tz()` + `psu_ocm_protection()`; otherwise `psu_protection()` then `psu_protection_lock()`. Even in non-bypass the *content* comes from `psu_init`.
2. **The ZCU102 `psu_init` protection bodies are empty stubs.** In `misc/zcu102/psu_init.c`, `psu_lpd_xppu_data()` (17009), `psu_ddr_xmpu0_data()` (18340) … `psu_ddr_xmpu5_data()`, `psu_protection_lock_data()` (18404) are all **comment-only and `return 1;`** — no `PSU_Mask_Write` to any `0xFD0x0000`/`0xFFA70000`/`0xFF980000` register. `psu_protection()` (23922) just chains `psu_apply_master_tz()` + `psu_ocm_protection()`. The only protection actually written is the **master-TrustZone classification** in `psu_apply_master_tz()` (FPD/LPD `*_SLCR_SECURE` TZ bits, e.g. `FPD_SLCR_SECURE_SLCR_DPDMA @ 0xFD690040 = 1`, in `psu_init_gpl.c`), plus the single OCM region `psu_ocm_protection()` sets.
3. **PMU role** (xpfw_xpu.c): the PMU does **not** program region permissions — it only **arms interrupts** (`XPfw_XpuIntrInit` writes `MaskAll` to each `BASE+IER`; `MaskAll=0xF` for XMPU, `0xEF` for XPPU, xpfw_xpu.c:99-141,155) and **acks/logs** violations. A violation "poisons" the transaction and raises a PMU error; with debug-print off (production), the handler simply acks/clears.

So the secure-boot intent: **the isolation tables come from the Vivado/HDF "isolation configuration"** baked into `psu_init` at design time; the reference ZCU102 design ships them empty, leaving everything default-allow except OCM and the master-TZ bits.

### 9.4 Security properties and gates

- **XMPU default-region policy** (`CTRL[1:0]` = DEFWRALLOWED/DEFRDALLOWED): when set, addresses not matching any region are *allowed*; secure-by-default requires clearing these and defining explicit regions.
- **XPPU TrustZone gate** is `ISR/IMR[6] APER_TZ` — a non-secure master hitting a secure aperture poisons and raises `XPPU_TRUSTZONE_VIOLATION` (0x40, xpfw_xpu.c:41,285).
- **LOCK[0]=REGWRDIS** freezes config until POR — the FSBL `psu_protection_lock()` step makes isolation tamper-resistant at runtime. Empty on the default design ⇒ nothing locked.
- Parity protection on MasterID table and aperture RAM detects table corruption.

### 9.5 Empirical findings (board 210308BD8D4D, JTAG-idle)

From golden enumerate.md §13/§16, re-confirmed in enumerate-2026-06-08-134143.md:

- **XPPU is DISABLED.** `XPPU.CTRL @ 0xFF980000 = 0x00000000` → `ENABLE=0`, `MID_PARITY_EN=0`, `APER_PARITY_EN=0`. No peripheral isolation in JTAG-idle. `ISR=0`, `IMR=0xEF` (all sources masked — the un-armed reset state, since PMUFW hasn't run to call `XPfw_XpuIntrInit`).
- **XPPU MasterID table is *populated at reset*** even with the unit disabled: `0xFF980100 = 0x83FF0040` (MID=0x040=PMU-MB, mask=0x3FF, parity=1), `0xFF980108 = 0x83F00010` (RPU1 range), `0xFF98010C..11C` = APU range (MID 0x080-0x083). ROM/reset defaults, not a booted policy. `M_APERTURE_*`/`BASE_*` show the standard 64KB@0xFF000000 / 1MB@0xFE000000 / 512MB@0xC0000000 geometry.
- **XPPU.POISON @ 0xFF98000C = 0x000FF9C0** — matches the high bits of the poison-sink `0xFF9CFF00` family; flagged "no QEMU model, bit fields unverified."
- **OCM_XMPU is ENABLED in default-allow.** `OCM_XMPU.CTRL @ 0xFFA70000 = 0x00000003` → `DEFRDALLOWED=1, DEFWRALLOWED=1`, `ALIGNCFG=0`. `ISR=0`, `IMR=0xF`, `LOCK @ 0xFFA70020 = 0` → **not locked**. Exactly the "isolation limited to just OCM, default-permit" state the FSBL comment describes — and why our OCM code-injection (`0xFFFC0000`) is freely readable/writable over JTAG.
- **DDR_XMPU0 = 0x0000000B** → `ALIGNCFG=1, DEFWRALLOWED=1, DEFRDALLOWED=1`, `LOCK=0`. Default-permit; DDR isn't powered/initialized in JTAG-idle anyway.
- **DDR_XMPU1..5 and FPD_XMPU NOT reliably read** — the enumerate deliberately skips them: §16 prints the *address echoed as the value* (`reg @ 0xFD010000 = 0xfd010000`), the tool's sentinel for "not confidently mapped / skipped to avoid DAP-wedge," "no QEMU register model … bit fields unverified." So **confident reads only for OCM_XMPU and DDR_XMPU0**; the other six instance bases are unverified on this board.
- **PMU view:** `PMU_GLOBAL.ERROR_STATUS_1 @ 0xFFD80530 [25:24] XMPU = 0x0` (no XMPU error latched).
- The CSU full-register map does not cover XMPU/XPPU; no writability probe of the XMPU/XPPU control registers from A53-EL3 has been run — an untested gap, distinct from the CSU-register writability survey (memory `project_csu_bypass_confirmed.md`).

### 9.6 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **In JTAG-idle the protection fabric is effectively wide open and irrelevant to us:** XPPU disabled, OCM/DDR XMPU default-permit, nothing locked. The DAP mem-AP (MasterID 0x62) reads/writes OCM and any responsive LPD peripheral with no XMPU/XPPU obstruction — consistent with confirmed OCM read/write and the per-peripheral reset-gating (not protection-gating) actually hit.
- **The interesting case is a *booted, hardened* target.** If a design programmed and `LOCK`-ed the XMPU/XPPU to fence a secure-DDR TEE region marked secure-only, then **the DAP master (0x62) would be subject to those region/MasterID checks** — a JTAG read of secure DRAM would poison and raise `SECURITYVIO`/`APER_TZ`. Whether the DAP is treated as secure or non-secure depends on `JTAG_DAP_CFG` SPIDEN (this board = open, `0xFFCA003C=0xFF`, §10) and how the design tagged the DAP MasterID — concrete to test on a provisioned part.
- **Reachable-but-untested primitive:** because OCM_XMPU/DDR_XMPU0 `LOCK=0` and DEF*ALLOWED=1, a halted A53 at EL3 (which we *can* produce, §8) could in principle **rewrite XMPU region descriptors or set DEFRD/WRALLOWED on DDR** before a payload runs — neuter memory isolation from the inside. Not yet exercised; given the CSU-register survey showed most "security" registers reject EL3 writes per-bit, this should be tested, not assumed.
- **Genuinely blocked even here:** XMPU/XPPU give no path to keys or ROM — they are *address filters*, not crypto. And the PMU MasterID (0x40) / CSU (0x50/0x51) protected regions — if a hardened design fences PMU RAM/CSU behind XPPU — would poison a DAP (0x62) access, the mechanism that *would* stop the kind of PMU/CSU reach exploited on this unprovisioned board. On 210308BD8D4D none of that is armed.

**Honest limits:** exact XMPU per-region descriptor offsets are not in our source-of-truth (only UG1085/UG1087); six of eight XMPU instances unverified on this board; XPPU.POISON bit fields unverified; XMPU/XPPU register writability not empirically tested from any master.

---

## 10. JTAG & debug security

### 10.1 What it is and its role in secure boot — the open DAP *is* the trust boundary

On ZynqMP the entire JTAG/debug fabric is gated by a small bank of CSU registers (and the eFuses that drive their reset values). There is no separate "secure JTAG" peripheral — the trust decision is: (1) which TAPs are *linked into the scan chain* (`JTAG_CHAIN_*`), (2) which TAPs are *security-enabled* (`JTAG_SEC`), and (3) for enabled TAPs, which *debug-authorization signals* (ARM `DBGEN`/`NIDEN`/`SPIDEN`/`SPNIDEN`) are asserted (`JTAG_DAP_CFG`). The reset/locked state is governed by `JTAG_DIS`/`DFT_DIS` eFuses in `SEC_CTRL` (§7).

The critical conceptual point (memory `project_findings_retracted.md`): **the open DAP is not something you bypass *to* — it is the thing that, when open, grants the access.** On unprovisioned silicon JTAG is wide open *by design*; on production silicon it is closed by `JTAG_DIS` or gated by debug authentication, so the DAP-NS path simply does not exist for an attacker. Everything else in this reference (PUF helper-data reads, AES STATUS, ROM digests) is reachable *because* this subsystem is open, not because any engine was independently broken.

### 10.2 Key registers, addresses, and exact bit fields

Addresses/fields trace to the PMUFW header `csu.h` (the vendor's `CSU_*` defines) and the QEMU register model. CSU base = `0xFFCA0000`.

| Register | Addr | Fields (source-cited) |
|---|---|---|
| `CSU_JTAG_CHAIN_CFG` | `0xFFCA0030` | `SSSS_LINK_ARM_DAP` bit 1, `SSSS_LINK_PL_TAP` bit 0 (csu.h:756–764). Write-side: links a TAP into the physical scan chain. The project's `enumerate.md` mislabels this addr "JTAG_CHAIN_STATUS_WR / SETUP[1:0]"; csu.h is authoritative that it is the *chain link config* register. |
| `CSU_JTAG_CHAIN_STATUS` | `0xFFCA0034` | `ARM_DAP` bit 1, `PL_TAP` bit 0 (csu.h:769–777; qemu `JTAG_CHAIN_STATUS` @ `0xFFCA0034`). Read-only status of which TAPs are linked. |
| `CSU_JTAG_SEC` | `0xFFCA0038` | csu.h:782–802 documents **five** 3-bit "magic" fields: `SSSS_DAP_SEC[2:0]` (`0x7`), `SSSS_PLTAP_SEC[5:3]` (`0x38`), `SSSS_PMU_SEC[8:6]` (`0x1C0`), `SSSS_PLTAP_EN[11:9]` (`0xE00`), `SSSS_DDRPHY_SEC[14:12]` (`0x7000`). The QEMU model (qemu:1960–1968) models only the lower three (`DAP_SEC`, `PLTAP_SEC`, `PMU_SEC`) — csu.h is the more complete map for `PLTAP_EN`/`DDRPHY_SEC`. Each field is a 3-bit value (`0b111` = enabled/open), which is why DAP+PLTAP enabled reads as `0x3F`, not `0x3`. |
| `CSU_JTAG_DAP_CFG` | `0xFFCA003C` | csu.h:809–838 documents **eight** single-bit fields: `SSSS_APU_DBGEN` 0, `APU_NIDEN` 1, `APU_SPIDEN` 2, `APU_SPNIDEN` 3, `RPU_DBGEN` 4, `RPU_NIDEN` 5, `RPU_SPIDEN` 6, `RPU_SPNIDEN` 7. The QEMU model (qemu:1970–1981) models only bits 0–5 (APU four + RPU DBGEN/NIDEN), so **bits 6–7 = `SSSS_RPU_SPIDEN`/`SSSS_RPU_SPNIDEN`** per csu.h — resolving the long-standing "undocumented bits 6–11" question. |
| `EFUSE.SEC_CTRL` | `0xFFCC1058` | `JTAG_DIS` bit 5, `DFT_DIS` bit 6 (qemu:2987–2988). When `JTAG_DIS=1` the TAPs go silent; `DFT_DIS=1` kills the DFT/scan path. Same register holds `RSA_EN[25:11]`, `SEC_LOCK` bit 10, `AES_RDLK`/`AES_WRLK` bits 0/1 (§7). |

`SSSS_*` = "Secure-State Slave Select." `DBGEN` = invasive debug enable, `NIDEN` = non-invasive (trace), `SPIDEN`/`SPNIDEN` = the *secure-world* (EL3/secure-EL1) variants. The secure pair is consequential: with `SPIDEN=1` a debugger can halt and inspect secure-EL3 state.

### 10.3 Boot-time behavior — how the vendor source drives it

The CSU BootROM samples the JTAG/DFT eFuses at POR and programs `JTAG_SEC`/`JTAG_DAP_CFG` before releasing the FSBL. The PMUFW then *protects* these registers at runtime via its MMIO ACL (§8):

- `pm_mmio_access.c:425–432` — `CSU_JTAG_CHAIN_STATUS` exposed **read-only** to APU/RPU IPI requestors. Even a booted A53 asking the PMU can only *read* chain status by default.
- `pm_mmio_access.c:570–577` — the `CSU_JTAG_SEC … CSU_JTAG_DAP_CFG` range exposed **read-write** but only inside `#ifdef SECURE_ACCESS` (line 524). On a stock PMUFW build *without* `SECURE_ACCESS`, the PMU refuses IPI-proxied writes to these registers — the vendor's intended gate on re-opening debug from software.
- The FSBL contains no direct `JTAG_SEC`/`JTAG_DAP_CFG` programming — secure-debug posture is fixed by the BootROM from eFuses before FSBL runs; FSBL only branches on *boot-policy* eFuses (xfsbl_initialization.c:1263–1273). JTAG gating is upstream of FSBL (§2).
- The xilskey library *burns* the controlling eFuses (`JTAG_DIS`/`DFT_DIS` and PPK/RSA bits) — xilskey_eps_zynqmp.c + _hw.h define the `SEC_CTRL` field layout that becomes the reset state of these CSU registers. Burning `JTAG_DIS` is the one-way action that converts "open DAP by design" into "no DAP."

### 10.4 Empirical findings (board 210308BD8D4D)

A factory/dev ZCU102 (XCZU9EG) with **no security eFuses provisioned** (`SEC_CTRL @ 0xFFCC1058 = 0`, `JTAG_DIS=0`, `DFT_DIS=0`). The captured debug-gate state is the **all-open baseline**:

- `CSU.JTAG_SEC @ 0xFFCA0038 = 0x0000003F` (golden enumerate.md:59–62; csu-surface:11; csu-fullmap:9). Decoded: `SSSS_DAP_SEC=0x7` (ARM DAP **open**), `SSSS_PLTAP_SEC=0x7` (PL-TAP **open**), `SSSS_PMU_SEC=0x0` (**PMU TAP gated**), `SSSS_PLTAP_EN=0`, `SSSS_DDRPHY_SEC=0`. The PMU SEC field being `0` (not `0b111`) is why the PMU TAP never appears in the scan chain on this board.
- `CSU.JTAG_DAP_CFG @ 0xFFCA003C = 0x000000FF` (golden enumerate.md:63–69; both reports). Decoded against csu.h: all eight bits set — APU `DBGEN/NIDEN/SPIDEN/SPNIDEN` = 1 **and** RPU `DBGEN/NIDEN/SPIDEN/SPNIDEN` = 1. **Secure-world invasive debug of both APU and RPU is fully authorized** — the single most consequential posture bit, wide open here.
- `CSU.JTAG_CHAIN_STATUS @ 0xFFCA0034 = 0x00000003`: `ARM_DAP=1`, `PL_TAP=1` — both linked; matches the two TAPs the OpenOCD scan finds (`uscale.tap` DAP IRLen 4 + `uscale.ps` PS-TAP IRLen 12).
- `JTAG_CHAIN_CFG @ 0xFFCA0030 = 0x00000000`.

> **Contradiction flagged:** §3.8 lists `0xFFCA0030` among addresses that **wedge the DP on read** in the per-word control-page sweep, while §10 reports it as cleanly read `0x00000000`. The reconciling note: the golden `enumerate.md` reads these four JTAG registers safely (they are explicitly enumerated), whereas the csu-surface *brute per-word sweep* of `0xFFCA0000–0x00FC` recorded a FAULT at `0x0030` in its automated pass. The safe path is the targeted reads in §10; the sweep's fault is most likely a sticky-bit artifact of reading adjacent secured apertures in sequence. Treat `0xFFCA0030/0034/0038/003C` as safely readable individually.

**Writability probes (the "undocumented bits 6–11" investigation):**
- `JTAG_SEC` upper bits are **eFuse-locked**: writes to bits 8/9/10/11 all *rejected*, readback unchanged (memory `project_pmu_enumeration_findings.md` H2). `SSSS_PMU_SEC` cannot be opened from software; the gate is enforced in the AXI fabric, not just the JTAG path (H1: a CSU-DMA read of PMU ROM `0xFFD00000` failed with `AXI_RDERR`, `I_STS=0x3D`). The DAP-wedge reference records "write to `JTAG_SEC` bit 8 silently rejected, DAP stays OK." This is the same master-aware PMU-ROM filter described in §1.5 and the same closed PM proxy in §8.6.
- `JTAG_DAP_CFG` bits 6–11 **accept writes** (H5: e.g. `0x7F`, `0xBF`, … `0x83F`), unlike eFuse-locked `JTAG_SEC`. The original hypothesis (bits 6–7 = hidden `SSSS_PMU_DBGEN/NIDEN` unlock) is **falsified twice**: (H5b) setting any bit 6–11 did *not* open the PMU-ROM AXI gate (`0xFFD00000` still `ERR`); (H7) writing `0xFFF` exposed **no new DAP APs** — AP0=`0x34770004`, AP1=`0x44770002` (APB-debug), AP2=`0x24760010` (AXI-mem) identical before/after, AP3–7 stayed `0`. Re-tested from A53-EL3-SECURE master (2026-05-28): same. **Reconciliation with csu.h:** bits 6–7 are simply `SSSS_RPU_SPIDEN/SPNIDEN` (already effectively on for RPU debug), and 8–11 reserved-writable with no effect on *this* config — consistent with "writable but inert." The "PMU debug unlock via DAP_CFG" lead is dead.

**Net:** with JTAG-idle, board 210308BD8D4D presents AP0/AP1 (APB debug) + AP2 (AXI mem) and authorizes full secure debug of APU+RPU. The PMU TAP (`SSSS_PMU_SEC=0`) and PMU ROM AXI aperture are the one hard boundary, enforced by eFuse + fabric, not openable from any software master tested.

### 10.5 Attack-relevance (JTAG-only, non-destructive, no side-channel HW)

- **Reachable on dev silicon:** everything the open DAP grants — halt/inspect/modify APU and RPU in any EL including EL3-secure (because `JTAG_DAP_CFG=0xFF`), read/write OCM and (post-FSBL) DDR, read the CSU PUF/AES/SHA apertures, read the ROM digests. The platform working as designed, not an exploit — "characterization," not "vulnerability" (the PSIRT submission was closed on exactly this basis — memory `project_findings_retracted.md`).
- **Blocked / out of reach:** (1) the PMU TAP and PMU ROM — eFuse-locked `SSSS_PMU_SEC` + AXI-fabric gate, no software path from any master; (2) re-opening `JTAG_SEC` upper fields — eFuse-locked, writes silently rejected; (3) on a *production* part with `JTAG_DIS=1` or `SPIDEN/SPNIDEN` cleared, the entire DAP-NS premise vanishes. There is no JTAG-only primitive that escalates from a *closed* debug posture to an *open* one; that transition is owned by the eFuses, which are one-way and were never burned on this board.
- **Honest gap:** csu.h documents `SSSS_PLTAP_EN[11:9]` and `SSSS_DDRPHY_SEC[14:12]` in `JTAG_SEC` not separately exercised (both read `0` here, no PL design loaded); their writability/effect is uncharacterized. The `JTAG_CHAIN_CFG` (`0xFFCA0030`) write-side that links/unlinks TAPs has not been actively driven — only read as `0`.

---

## Consolidated sources

### Vendor source — `embeddedsw` (FSBL / PMUFW / xilskey / xilsecure)

- FSBL: `xfsbl_main.c` (101-338, 148-170, 367-398, 417-566), `xfsbl_initialization.c` (240-245, 294-362, 935-972, 1214, 1234-1308, 1259-1273), `xfsbl_authentication.c` (84-233, 248-375, 385-446, 481-561, 579-698, 717-780), `xfsbl_partition_load.c` (1141-1238, 1297-1314, 1480-1577), `xfsbl_image_header.c` (625-630), `xfsbl_handoff.c` (1183-1206), `xfsbl_hw.h` (71-290), `xfsbl_authentication.h` (54-87), `misc/zcu102/psu_init.c` (17009, 18340-18404, 23904-23926) + `psu_init_gpl.c` (FPD_SLCR_SECURE_SLCR_DPDMA @ 0xFD690040).
- PMUFW: `csu.h` (754-839), `pm_mmio_access.c` (22-25, 32-161, 178-1001, 1016-1092), `pm_core.c` (501-670, 820-868, 2468-2578), `pm_binding.c` (80-83, 104-373, 391-522), `pm_master.c` (411-423), `pm_common.h` (90-138), `pm_defs.h` (224-228), `xpfw_ipi_manager.h` (26-40), `xpfw_xpu.c` (11-158, 285).
- xilsecure: `xsecure_aes_hw.h` (41-74), `xsecure_aes.h` (31-127, 147-148), `xsecure_aes.c` (151, 223-261, 882-951), `xsecure_sha_hw.h` (38, 45-51), `xsecure_sha.c` (78-81, 155, 303-308, 512-513, 540), `xsecure_rsa_hw.h` (33, 41-78), `xsecure_rsa_core.c` (96, 122, 213-235), `xsecure_rsa_core.h` (90-95, 120-136), `xsecure_sss.h` (46-49), `xsecure_sss.c` (34-45, 246-294), `xsecure_cryptochk.c` (31-65), `xsecure.c` (1149-1150).
- xilskey: `xilskey_eps_zynqmp_puf.c` (585-604, 623-790, 1095-1165), `xilskey_eps_zynqmp_puf.h` (57-125), `xilskey_eps_zynqmp_hw.h` (48, 55-138, 429-463, 480-515, 634-755, 763-1199, 1218-1268), `xilskey_eps_zynqmp.c` (354, 578-688, 1121-1166, 1767), `xilskey_bbramps_zynqmp_hw.h` (47, 53-169), `xilskey_bbramps_zynqmp.c` (80-302).

### Vendor source — bootgen

`bootgenenum.h` (53-82), `bif.l` (284-308), `cmdoptions.l` (258), `bif.y` (141-143, 266-267, 449-451, 595-598), `bootheader.h` (50-80), `bootheader-zynqmp.h` (40-80), `bootheader-zynqmp.cpp` (118-313, 416-558, 628-661), `authentication-zynqmp.h` (36-59), `authentication-zynqmp.cpp` (126-145, 284-360, 450-477, 507-661), `authkeys.h` (46-134), `authentication.h` (70), `readimage-zynqmp.cpp` (340-469), `encryption-zynqmp.cpp` (48-133, 650-784, 1226-1269), `encryptutils.h` (49-54), `obfskutil.h` (40-120), `bifoptions.cpp` (904-914, 1970), `help.h` (2980-2999).

### Project source-of-truth and AMD user guides

- QEMU register model: `openocd/lib/zynqmp-regs-qemu.tcl` (1587-1627, 1772-2048, 1792-1798, 1818-1879, 1951-1981, 1960-1981, 2099-2113, 2397-2466, 2574-2642, 2644-2798, 2950-2994, 4832-4884, 4940-5008).
- Project docs: `docs/11-enumerated-attributes.md` (41, 50-166, 221-243), `docs/12-secureboot-internals.md` (0-63, 67-133).
- AMD user guides (external, not in captured source-of-truth): **UG1085** ZynqMP TRM (ch.11 boot/SPB; §16 XMPU/XPPU), **UG1137** ZynqMP SW Dev Guide (CBR copies FSBL to fixed OCM 0xfffc0000), **UG1283** Bootgen, **UG1087** Register Reference (XMPU_OCM/XMPU_DDR R00..R15 modules — https://docs.amd.com/r/en-US/ug1087-zynq-ultrascale-registers).

### Empirical captures (board 210308BD8D4D)

- `tests/golden/zcu102-jtag-idle/enumerate.md` (TAP scan, JTAG gates, boot-mode, eFuse/PUF/BBRAM, XMPU/XPPU §13/§16, IPI/PMU regions §796).
- `reports/enumerate-2026-06-08-134143.md`, `reports/csu-fullmap-2026-06-08-134631.md`, `reports/csu-surface-2026-06-08-131838.md`.
- `dumps/ocm-0xFFFC0000-128k-freshboot-2026-06-08-125258.bin` (131072 B, entropy 5.68, first word `0x1400024e`/`4E 02 00 14`), `dumps/fsbl-freshboot.disasm`, `dumps/bootrom-via-pmu-r5-bootrom-2026-06-08-113330.bin` (16 KB, entropy 2.15).

### Project memory notes

`project_bootrom_dumpability_resolved.md`, `project_r5_bootrom_dump_result.md`, `project_pmu_rom_efuse_locked.md`, `project_control_bits_findings.md`, `project_phase7_ipi_validated.md`, `project_puf_extractable_via_jtag.md`, `reference_pufky_construction.md`, `project_correct_addresses_findings.md`, `project_sec_ctrl_correction.md` (retracted), `reference_hashes_keys_security.md`, `reference_chip_values_inventory.md`, `project_pmu_enumeration_findings.md`, `project_findings_retracted.md`, `reference_dap_wedge.md`, `project_csu_bypass_confirmed.md`, `reference_pmu_internals.md`.

### External academic references

Maes et al., "PUFKY" (CHES 2012); Delvaux et al. helper-data manipulation (2013/2015). CVE-2023-20570 / "JustSTART" (boot-image authentication target area).

---

## Empirical vs vendor-documented

**Vendor-documented / source-traced (not independently re-verified on hardware here):**
- The CSU BootROM and PMU ROM are immutable code; the CSU ROM is internal to the SPB and not AXI-mapped (UG1085/UG1137 + project resolution).
- The full FSBL 4-stage machine, two-tier RSA (PPK→SPK→partition) authentication, AES-256-GCM decryption flow, and the `XFSBL_ERROR_BH_AUTH_IS_NOTALLOWED` downgrade guard — read from source, **not** exercised on a secure/provisioned part.
- The complete boot-header / IHT / PHT / Authentication-Certificate byte layout, magic constants, checksum algorithm, PKCS#1-v1.5 SHA-3 padding, and the family-key wrap path (`obfsk`, deliberately closed source) — bootgen source.
- The crypto-engine register maps (AES `0xFFCA1000`, SHA `0xFFCA2000`, RSA `0xFFCE0000`, SSS `0xFFCA0008`), the SSS routing constraint, and the AES KEY_SRC restriction — headers + QEMU. **RSA core `0xFFCE0000` was never probed on this board.**
- The eFuse/BBRAM register maps, `SEC_CTRL` bit-field, CRC-only key verification, and the no-read-path guarantee for BBRAM/AES eFuse keys — xilskey headers.
- The PMU PM-API dispatch, channel-based caller identity, TrustZone gating, and the `pmAccessTable[]` ACL (including the `SECURE_ACCESS` guard) — PMUFW source.
- The XMPU/XPPU architecture, MasterID LUT (DAP=0x62), default-bypass FSBL behavior, and empty ZCU102 `psu_init` protection stubs — PMUFW/FSBL source + UG1085/UG1087.
- The JTAG_SEC / JTAG_DAP_CFG / JTAG_CHAIN field layouts (incl. csu.h's `PLTAP_EN`/`DDRPHY_SEC`/`RPU_SPIDEN/SPNIDEN`) and the eFuse drive of their reset state — csu.h + QEMU.

**Established empirically on board 210308BD8D4D (JTAG-only, non-destructive):**
- The part is unprovisioned dev silicon: `SEC_CTRL=0` (RSA_EN/ENC_ONLY/JTAG_DIS/DFT_DIS/SEC_LOCK/AES_RDLK/AES_WRLK all 0), PPK0/PPK1 digests all-zero, SPK_ID/USER fuses zero, eFuse AES_CRC=0, BBRAM key words zero, PUF_CHASH=0. No root of trust committed.
- Device DNA = `0x40000000_0170CFA7_44804345` (chip-unique, freely DAP-NS readable — the only durable secret extractable here).
- `0xFFFC0000` is **OCM RAM, not ROM**: proven by two-state comparison (JTAG-idle `0xDEADBEEF` fill vs fresh-boot real FSBL, entropy 5.68, AArch64 vector table + EL3 handlers). Falsifies the historical "DEADBEEF = gated BootROM" reading.
- The live CSU ROM SHA-3-384 digest (`CSU_ROM_DIGEST_0..11` = `0x26042731…0x2937CB90`), mirrored in the SHA engine at idle — a per-part forensic fingerprint, persistent and DAP-NS readable.
- The **entire CSU crypto window** (AES/SHA/PCAP/PUF/tamper) is readable from DAP-NS in JTAG-idle with zero faults; AES idle `STATUS=0x0F00` (all `*_ZERO` bits set), and a wake-and-load sweep across all 8 KEY_SRC values produced no real key (only the cosmetic `KEY_INIT_DONE` bit) — **no JTAG-idle key-injection/extraction path.**
- The **CSU PUF controller is ungated from DAP-NS** — REGISTRATION can be triggered and helper-data words streamed out, with no hardware security gate (the genuinely disclosure-relevant finding; dormant on this die since CHASH=0).
- JTAG gates wide open: `JTAG_SEC=0x3F`, `JTAG_DAP_CFG=0xFF` (full secure-world APU+RPU debug). `JTAG_SEC` upper bits eFuse-locked (writes rejected); `JTAG_DAP_CFG` bits 6–11 writable-but-inert (no new DAP APs, no PMU-ROM unlock).
- PMU ROM (`0xFFD00000`) and the PMU TAP are the **one hard boundary** — a master-aware AXI filter blocks DAP/CSU-DMA reads even after `SSSS_PMU_SEC` is opened.
- On a **booted** SD/PetaLinux system, a JTAG-driven A53 at EL3 can drive the live PM API (channel-based identity), confirmed: `PM_GET_API_VERSION`→v1.1, `PM_GET_CHIPID`→`0x24738093`, allowlisted MMIO reads succeed, and **RPU power-on + arbitrary R5 code execution + TCM power** validated. The PM proxy `PM_MMIO_READ` of eFuse cache (`0xFFCC1058`) and PMU ROM (`0xFFD00000`) both returned `XST_PM_NO_ACCESS 0x7D2` — the ACL holds exactly as written (clean negative).
- XPPU **disabled** (`CTRL=0`), OCM_XMPU/DDR_XMPU0 **default-permit and unlocked** (`0x3`/`0xB`, LOCK=0) — the DAP (MasterID 0x62) reads/writes OCM with no isolation friction. Six of eight XMPU instances unverified (skipped to avoid DAP-wedge).

---

## Cross-section contradictions flagged

1. **`CSU_SSS_CFG` idle value.** §2.7 cites `0x00005000` (csu-surface probe); §3.8 records `0x00005000`, `0x00008834`, and `0x00000050` across captures. Resolution: the value depends on boot/idle timing; **no single idle value is canonical** (§3.8). The register is 20 bits wide (writes of `0xFFFFFFFF` read back `0x000FFFFF`).
2. **`0xFFCA0030` readability.** §3.8 lists it among per-word-sweep DP-wedge addresses; §10.4 reads it cleanly as `0x00000000`. Resolution: targeted reads in the golden enumerate are safe; the sweep's fault is a sticky-bit artifact from reading adjacent secured apertures. Treat `0xFFCA0030/34/38/3C` as safely readable individually (§10.4 note).
3. **PUF provisioning state.** §6.7 narrates "PUF is registered (BH-PUF style)" while §4/§5/§7 conclude **PUF unprovisioned**. Resolution: BH-PUF mode leaves `PUF_CHASH=0` even when PUF is in use, so a zero CHASH alone cannot distinguish the two; given the surrounding all-zero security state (SEC_CTRL=0, no AES key), **"unprovisioned" is the supported reading** for this board (§6.7 note).
4. **BBRAM register offsets.** §5.5 referenced a `BBRAM.CTL/STATUS/LOCK` triple at `0xFFCD0020/24/28`; the authoritative xilskey map (§7.2) places `STS/CTRL/PGM_MODE/AES_CRC` at `0xFFCD0000–000C` and key words at `0xFFCD0010–0030`, with `SLVERR/ISR/IMR/IER/IDR` at `0xFFCD0034–0044`. **Use the §7.2 xilskey-header map as authoritative**; the §5.5 offsets appear to be a looser earlier labeling.
5. **`encryptionKeySource` decode order (open).** Only the bootgen *encode* side is source-confirmed; the CBR's runtime *decode* order, and `EFUSE_GREY` vs `EFUSE_GRY` naming, are not closed from source (§6.8).