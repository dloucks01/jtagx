# Enumerated Attributes — ZynqMP Reference

This is the canonical catalog of **every attribute the JTAG enumeration surfaces
that matters** — what each one is, **where it lives** (`BLOCK.REGISTER[.FIELD]` +
AXI address), its value on this board, and how to read it. It is the data
dictionary behind `enumerate.tcl`, the decoders in
`docs/annotations/zynqmp_{security,general}.py`, and the **Security Posture
Summary** emitted by `tools/interpret.py`.

The reference board is the ZCU102 (XCZU9EG, S/N 210308BD8D4D): factory silicon with
**no security provisioned**, enumerated in JTAG-idle. That makes its values the
**baseline** — for the security gates (Part B) it's the all-open reference; for the
platform/state attributes (Part A) it's the clean post-BootROM, pre-FSBL state. On
another board the deviations from this baseline are what you read off.

This document has three parts: **Part A** platform & state attributes, **Part B**
the security & trust posture (the controls that matter most), and **Part C** an
annotated register hexdump — the raw captured bytes with each attribute mapped onto
its address, generated from a real capture.

Conventions:
- **Location** is `BLOCK.REGISTER[.FIELD] · 0xADDRESS [· bits]`. Bit layouts come
  from the Xilinx QEMU register model (`openocd/lib/zynqmp-regs-qemu.tcl`, the single
  source of truth) and UG1085 — no hand-invented bit fields.
- **This board** = the value observed on this unprovisioned ZCU102 in JTAG-idle.

---

# Part A — Platform & state attributes

What the chip *is* and what state it's in. Not security gates, but they bound what
every other attack/read can reach, and they're the first thing to establish on any
board.

## A1. Silicon identity

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| Device part / family | `CSU.IDCODE · 0xFFCA0040` | `0x24738093` (XCZU9EG) | Die + revision; the variant table (`openocd/lib/zynqmp-variants.tcl`) names capabilities (A53 count, GPU/VCU/RF, GEMs). |
| Silicon revision | `CSU.VERSION · 0xFFCA0044` (PS_VERSION) | `3` (production) | `0`/`1` = ES1/ES2 engineering samples (different errata). |
| Per-chip unique ID | `EFUSE.DNA_0..2 · 0xFFCC100C–1014` | `0x40000000_0170CFA7_44804345` | 96-bit fingerprint; may be read-gated on a hardened part. |

## A2. Compute elements (APU / RPU)

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| APU cores | quad Cortex-A53 (per variant) | 4 cores, all in reset at idle | The main application CPUs (EL0–EL3). |
| A53 release state | `RST_FPD_APU · 0xFD1A0104` + `APU.RVBARADDR0L · 0xFD5C0040` | core 0 releasable → halts at `0xFFFC0000`, CPSR `0x000003cd` (EL3H) | Whether/where a core can be brought up over JTAG (the release primitive). |
| A53 EL3 system regs | per-core debug regs (when halted) | EL3-Secure, MMU off after release | Security state of a halted core (SCR_EL3, SCTLR, etc.). |
| Invasive debug gate (halt) | live `halt` attempt via DAP → `a53.invasive_debug` | `open` (DAP halts the core) | Whether the DAP can actually halt the APU. `open` on a bare board; flips to **`gated`** once secure firmware (ATF/bl31) restricts invasive debug — a posture signal that depends on the *running firmware*, not just eFuses/SPIDEN. `unreachable` if the core won't examine. |
| Non-invasive PC sampling (EDPCSR) | `DBGBASE+0xA0` per core (APB-AP, AP1) → `a53.pc_sampling` / `live_pc` | `off` at idle (no code running) | Reads a *running* core's PC without halting — works even when halt is gated. Reveals whether code is executing (an OS/firmware) and where. DBGBASE: core0 `0x80410000`, +`0x100000`/core. EDPRSR `+0x314`, EDSCR `+0x088`. |
| RPU cores | dual Cortex-R5 (`RPU.* · 0xFF9A0000`) | lockstep vs split per `RPU_GLBL_CNTL` | Real-time cores + TCM; RPU island is PMU-gated from JTAG-idle. |

## A3. Clocks (PLLs and reference clocks)

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| FPD PLLs | `CRF_APB` PLL_CTRL/STATUS (`0xFD1A0020+`, status `0xFD1A0044`) | APLL/DPLL/VPLL up after BootROM | Full-power-domain clock sources (APU, DDR, video). |
| LPD PLLs | `CRL_APB` PLL_CTRL/STATUS (status `0xFF5E0040`) | IOPLL/RPLL up | Low-power-domain clock sources. |
| Peripheral ref clocks | per-peripheral `*_REF_CTRL` (`0xFF5E0050+`, `0xFD1A0064/68`) | most gated in idle | Which peripherals are clocked (pair with reset state for "usable now"). |
| APU clock | `ACPU_CTRL · 0xFD1A0060` | source + divisor + CLKACT | A53 operating clock. |

## A4. Power domains

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| Power-island state | `PMU_GLOBAL.PWR_STATE · 0xFFD80100` | only BootROM-era domains up | Which islands (APU cores, R5, TCM, OCM banks, FP, PL, USB) are powered. |
| PMU global control | `PMU_GLOBAL.GLOBAL_CNTRL · 0xFFD80000` | hardware-locked from software | PMU master control; not writable from JTAG-idle (any master). |

## A5. Reset state

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| FPD/APU resets | `RST_FPD_APU · 0xFD1A0104` | cores in reset (≈`0x00003d0f`) | ACPU0–3 / L2 / power-on resets — the A53 release knobs. |
| LPD peripheral resets | `RST_LPD_IOU2 · 0xFF5E0238` | most peripherals held in reset | Per-peripheral reset bits (QSPI/UART/SPI/SDIO/I2C/…). |
| LPD/DDR top resets | `RST_LPD_TOP · 0xFF5E023C`, `RST_DDR_SS · 0xFD1A0108` | held in idle | Subsystem-level resets. |

## A6. Memory map (what's reachable)

| Region | Location | This board | What it tells you |
|---|---|---|---|
| OCM SRAM | `0xFFFC0000` (256 KB, 4 banks) | readable/writable; FSBL/ATF land here when booted | On-chip RAM — the JTAG code-injection landing zone. |
| DDR | `0x00000000+` | uninitialized in JTAG-idle (probing it wedges AXI) | Main memory; live only after FSBL brings up the controller. |
| TCM (R5) | `0xFFE00000 / 0xFFE20000` | gated in JTAG-idle (RPU island down) | R5 tightly-coupled memory. |
| PMU RAM / ROM | `0xFFDC0000` (LMB RAM) / `0xFFD00000` (ROM) | RAM writable from A53-EL3; ROM eFuse-locked | PMU firmware/ROM space. |

## A7. Debug topology (CoreSight / DAP)

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| JTAG chain (TAPs) | scan chain | `uscale.tap` (DAP, IRLen 4) + `uscale.ps` (PS, IRLen 12) | Which TAPs are present (PMU TAP appears only when its eFuse policy allows). |
| Access Ports | DAP AP enumeration (`discover.tcl`) | AP0/AP1 = APB debug (`0x44770002`), AP2 = AXI mem (`0x24770004`) | Which debug/memory access paths respond — itself a posture datum on a hardened part. |
| CoreSight components | per-AP ROM-table walk | Debug Units / CTIs / ETMs / funnels / ETB | The trace/debug fabric available. |

## A8. IPI fabric

| Attribute | Location | This board | What it tells you |
|---|---|---|---|
| APU IPI window | `IPI` APU agent at `0xFF300000` (TRIG/OBS/ISR/IMR) | idle | The APU↔PMU↔RPU↔PL mailbox channels (the APU→PMU PM-API path in booted state). |

---

# Part B — Security & trust posture

The security controls. On this dev board every one reads OFF/unprovisioned (the
all-open baseline); on a hardened part they flip to show what's switched on. These
are the rows the **Security Posture Summary** distills.

## B1. Secure-debug exposure (most consequential)

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| **APU secure invasive debug** | `CSU.JTAG_DAP_CFG · 0xFFCA003C · bit 2` (SPIDEN) | `1` (open) | `0` |
| **APU secure trace** | `0xFFCA003C · bit 3` (SPNIDEN) | `1` | `0` |
| APU / RPU non-secure debug+trace | `0xFFCA003C · bits 0,1,4,5` | `1` | `0` or `1` |
| DAP / PL-TAP / PMU JTAG paths | `CSU.JTAG_SEC · 0xFFCA0038 · [2:0]/[5:3]/[8:6]` | `0x3F` (DAP+PLTAP open, PMU gated) | not `0b111` |

## B2. Secure-boot policy

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| RSA boot authentication | `EFUSE.SEC_CTRL · 0xFFCC1058 · [25:11]` (RSA_EN) | `0` | 15-bit magic = enforced |
| Encrypt-only boot | `0xFFCC1058 · bit 2` (ENC_ONLY) | `0` | `1` |
| Secure lockdown | `0xFFCC1058 · bit 10` (SEC_LOCK) | `0` | `1` |
| PPK0 / PPK1 public-key hash | `EFUSE.PPK0_0..11 · 0xFFCC10A0–10CC` / `PPK1_0..11 · 0xFFCC10D0–10FC` | all-zero | non-zero (root of trust) |
| PPK0 / PPK1 revoked | `0xFFCC1058 · [28:27] / [31:30]` | `0` | 2-bit magic = revoked |
| SPK ID / revocation | `EFUSE.SPK_ID · 0xFFCC105C` | `0` | partition-key revocation id |

> **⚠️ CVE-2019-5478 — Encrypt-Only without HWRoT.** The pair `ENC_ONLY=1` **and**
> `RSA_EN=0` is the exact configuration vulnerable to CVE-2019-5478: encrypted boot is
> enforced but the boot/partition headers are *not authenticated*, so an attacker who
> rewrites the boot media can tamper the FSBL/partition execution addresses → arbitrary
> code execution (full secure-boot bypass; the BootROM half is unpatchable). The
> `rule_cve_2019_5478_encrypt_only_bypass` rule flags this combination as **CRITICAL**.
> Remediation is Hardware Root of Trust (`RSA_EN`). See `docs/15-prior-research.md` §1.
> This board reads `ENC_ONLY=0, RSA_EN=0` (not in Encrypt-Only mode → not exposed).

### Boot-header scan (`encryptionKeySource`, operator-gated)

The boot header is **not memory-mapped in JTAG-idle**, so these are captured only when
the operator points `::BH_ADDR` at the boot-image base on a booted/QSPI-linear target
(`-c "set ::BH_ADDR 0xC0000000"`). The read self-validates against the boot-header magic
words, so a wrong address captures nothing rather than producing a false reading.

| Attribute | Location (boot-header offset) | Meaning |
|---|---|---|
| Boot-header magic | `+0x20` WIDTH_DETECTION = `0xAA995566`, `+0x24` ID = `0x584C4E58` ("XLNX") | validity gate — both must match |
| `encryptionKeySource` | `+0x28` | magic enum: `0x00000000`=None/unencrypted, `0xA5C3C5A3`=eFuse RED, `0x3A5C3C5A`=BBRAM RED, `0xA5C3C5A5`=eFuse black, `0xA35C7C53`=BH black, `0xA5C3C5A7`=eFuse grey, `0xA35C7CA5`=BH grey, `0xA3A5C3C5`=BH KUP (bootgen `bootheader.h:64-70`) |
| `fsblAttributes.AUTH_ONLY` | `+0x44` bits 5-4 (==3 ⇒ true) | authenticate-only |
| `fsblAttributes.BH_RSA` | `+0x44` bits 15-14 (==3 ⇒ true) | boot-header RSA (dev-mode auth) |

> **⚠️ Authentication without encryption (downgrade-bypass class).** When a boot is
> authenticated but not encrypted — observed either via `CSU_STATUS` (`BOOT_AUTH=1`,
> `BOOT_ENC=0`, `0xFFCA0000`) or via the boot header (`encryptionKeySource`=None while
> `BH_RSA`/`AUTH_ONLY` set or `RSA_EN` enforced) — the image is integrity-protected but
> plaintext. This is the configuration the UltraScale(+) auth-bypass research targets:
> **JustSTART (CVE-2023-20570)** bypasses RSA authentication on the config engine, and the
> *Cautionary-Note* authentication-downgrade attacks defeat the GHASH/auth path; both are
> mitigated only with encryption **and** authentication enabled together. The
> `rule_auth_only_without_encryption` rule flags this as **MAJOR**. See
> `docs/15-prior-research.md` §2-3.

### Partition Header Table (per-partition PL-bitstream encrypt/auth)

When `::BH_ADDR` finds a valid boot header, the scan walks
`imageHeaderByteOffset` (BH +0x98) → Image Header Table → the **Partition Header
Table** (linked list via `nextPartitionHeaderOffset`, word-offset ×4, relative to
the image base). Each 64-byte partition header is **self-validated by its
word-checksum** (sum of 15 words `^0xFFFFFFFF` at +0x3C) before its flags are
trusted, so a walk into non-resident/garbage memory is rejected, not reported.
The walk is capped at 32 partitions. The same structures are parsed offline by
`tools/parse-bootimage.py` from a boot-image dump.

| Attribute | Location | Meaning |
|---|---|---|
| IHT partition count | IHT +0x04 | number of partitions |
| Headers authenticated | IHT +0x10 (headerAuthCertificateWordOffset) | ≠0 ⇒ image/partition headers are RSA-authenticated |
| `partitionAttributes` | PH +0x24 | per-partition attribute word (decoded below) |
| · DEST_DEVICE | bits 6-4 | `0`=NONE `1`=PS **`2`=PL (bitstream)** `3`=PMU `4`=XIP |
| · ENCRYPT | bit 7 | partition payload encrypted |
| · AC_FLAG | bit 15 | partition has an authentication certificate |
| authCertificateOffset | PH +0x34 | ≠0 ⇒ partition authenticated (corroborates AC_FLAG) |

> **⚠️ PL-bitstream protection gap.** For each **PL** partition (DEST_DEVICE=2):
> not-encrypted **and** not-authenticated → **CRITICAL** (fabric fully exposed —
> IP cloning + arbitrary bitstream load); authenticated-but-not-encrypted →
> **MAJOR** (the direct JustSTART/CVE-2023-20570 + Cautionary-Note target);
> encrypted-but-not-authenticated → **MAJOR** (GCM ciphertext malleability,
> Starbleed lineage). The `rule_pl_bitstream_unprotected` rule emits these.
> All source offsets/constants trace to bootgen (`partitionheadertable-zynqmp.h`,
> `bootgenenum.h`); see `docs/14` §6.3 and `docs/15` §2-4.

## B3. Key material & confidentiality

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| AES key-slot population | `CSU.AES_STATUS · 0xFFCA1000 · bits 8–11` (*_ZERO) | `0xF00` (all empty) | a slot's bit clear = key loaded |
| eFuse AES key present | `EFUSE.EFUSE_AES_CRC · 0xFFCC0048` | `0` (absent) | non-zero (key burned) |
| AES key read / write lock | `0xFFCC1058 · bit 0 / bit 1` (AES_RDLK/WRLK) | `0` | `1` |
| PUF provisioned | `EFUSE.PUF_CHASH · 0xFFCC1050`, `PUF_MISC · 0xFFCC1054` | `0` / `0x10000000` | non-zero CHASH |

## B4. Anti-tamper

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| Tamper response policy | `CSU.CSU_TAMPER_0..12 · 0xFFCA5004–5034` | all-zero (disarmed) | non-zero per armed source |
| Tamper events latched | `CSU.TAMPER_STATUS · 0xFFCA5000` | `0` | non-zero = fired |
| Software tamper trigger | `CSU.CSU_TAMPER_TRIG · 0xFFCA0014` | `0` | — |

## B5. Lockdown & fuse-programming policy

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| eFuse write-lock | `EFUSE.WR_LOCK · 0xFFCC0000` | `0x1` (locked until POR) | `0x1` |
| eFuse program-lock | `EFUSE.EFUSE_PGM_LOCK · 0xFFCC0044` | `0` | non-zero |
| eFuse ISR | `EFUSE.EFUSE_ISR · 0xFFCC0030` | `0` | programming-done/error flags |
| Program gates / BBRAM / error dis | `0xFFCC1058 · [7:9] / bit 3 / bit 4` | `0` | set per policy |

## B6. JTAG disable fuses

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| JTAG disable | `EFUSE.SEC_CTRL · 0xFFCC1058 · bit 5` (JTAG_DIS) | `0` (JTAG on) | `1` (TAPs silent) |
| DFT disable | `0xFFCC1058 · bit 6` (DFT_DIS) | `0` | `1` |

## B7. Memory & peripheral TrustZone

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| DDR TrustZone (ch. 0–5) | `DDR_XMPU0..5.CTRL/LOCK · 0xFD000000…0xFD050000` | default-region permit | regions configured + LOCK |
| FPD / OCM TrustZone | `FPD_XMPU · 0xFD5D0000` / `OCM_XMPU · 0xFFA70000` | OCM CTRL `0x3` | regions configured |
| Peripheral protection | `XPPU.CTRL/ISR · 0xFF980000` | enabled, no violations | apertures locked down |

## B8. Boot & runtime integrity

| Attribute | Location | This board | Hardened part |
|---|---|---|---|
| Boot mode | `BOOT_MODE_USER · 0xFF5E0200 · [3:0]` | `0` (JTAG idle) | SD/QSPI/eMMC/USB |
| Multiboot search offset | `CSU.CSU_MULTI_BOOT · 0xFFCA0010` | `0` | image-chaining offset |
| Auth / encrypt status | `CSU.CSU_STATUS · 0xFFCA0000` (BOOT_AUTH/BOOT_ENC) | `0` | set after authenticated boot |
| BootROM / PMU ROM hash | `CSU.SHA_DIGEST_0..11 · 0xFFCA2010+` / `PMU_GLOBAL.ROM_VALIDATION_DIGEST_0/1 · 0xFFD80614/618` | fixed per silicon revision | identifies ROM image (fingerprint) |

---

---

# Part C — Annotated register hexdump (where attributes reside)

Parts A/B give each attribute's location; this is the **raw view** — the captured
bytes at each address with the attribute fields decoded on top, so you can see
exactly where in a register dump each attribute sits. Bytes are little-endian (as a
memory dump shows them); ★ marks a security control.

This is **generated from a real capture** by `tools/hexdump-attributes.py` (no
hand-typed values). Regenerate it — and get the full dump including the platform
blocks (clocks/power/reset/XMPU/XPPU/IPI/RPU) — with:

```
python3 tools/hexdump-attributes.py                 # all blocks, latest capture (else golden)
python3 tools/hexdump-attributes.py --security      # security blocks only
python3 tools/hexdump-attributes.py -o out.md       # write markdown to a file
```

> The excerpt below is from the frozen JTAG-idle golden capture. The §4 security
> reads added 2026-06-08 — `AES_STATUS`, the `CSU_TAMPER_*` block, eFuse `WR_LOCK`/
> `EFUSE_ISR`/`PGM_LOCK`/`EFUSE_AES_CRC`, and the full `PPK0/PPK1` words — appear here
> once a fresh JTAG-idle capture re-freezes the baseline; re-run the tool then.

### ★ CSU (base 0xFFCA0000)

```
address     +0 +1 +2 +3   word         register            attribute fields
0xFFCA0000  00 00 00 00   0x00000000  ★ CSU_STATUS         BOOT_ENC=0 BOOT_AUTH=0
0xFFCA0010  00 00 00 00   0x00000000  ★ CSU_MULTI_BOOT
0xFFCA0034  03 00 00 00   0x00000003  ★ JTAG_CHAIN_STATUS  ARM_DAP=1 PL_TAP=1
0xFFCA0038  3F 00 00 00   0x0000003F  ★ JTAG_SEC           SSSS_PMU_SEC=0 SSSS_PLTAP_SEC=7 SSSS_DAP_SEC=7
0xFFCA003C  FF 00 00 00   0x000000FF  ★ JTAG_DAP_CFG       SSSS_RPU_NIDEN=1 SSSS_RPU_DBGEN=1 SSSS_APU_SPNIDEN=1 SSSS_APU_SPIDEN=1 SSSS_APU_NIDEN=1 SSSS_APU_DBGEN=1
0xFFCA0040  93 80 73 24   0x24738093  ★ IDCODE             CONST_1=1 MANUF_ID=73 PART_ID=18232 REVISION=2
0xFFCA0044  13 05 00 00   0x00000513  ★ VERSION            PLATFORM=0 PS_VERSION=3
```

Read it as: at `0xFFCA0038` the dump holds bytes `3F 00 00 00` = `0x0000003F` =
`JTAG_SEC`, whose `SSSS_DAP_SEC`/`SSSS_PLTAP_SEC` fields are `7` (open) and
`SSSS_PMU_SEC` is `0` (gated). At `0xFFCA003C`, `FF 00 00 00` = `JTAG_DAP_CFG` with
every debug-enable bit set, including `SPIDEN`/`SPNIDEN` (secure-world debug open).

### ★ EFUSE (base 0xFFCC0008)

```
address     +0 +1 +2 +3   word         register            attribute fields
0xFFCC0008  27 00 00 00   0x00000027  ★ STATUS             AES_CRC_PASS=0 AES_CRC_DONE=0 CACHE_DONE=1 EFUSE_3_TBIT=1 EFUSE_2_TBIT=1 EFUSE_0_TBIT=1
0xFFCC1058  00 00 00 00   0x00000000  ★ SEC_CTRL           RSA_EN=0 ENC_ONLY=0 JTAG_DIS=0 SEC_LOCK=0 AES_RDLK=0 AES_WRLK=0 PPK0_INVLD=0 PPK1_INVLD=0
```

`SEC_CTRL` reading all-zero is the whole security-boot policy at once: no RSA, no
encrypt-only, JTAG enabled, nothing locked — the all-open baseline.

The complete annotated hexdump (all 106 captured registers across every block) is
what `tools/hexdump-attributes.py` prints without `--security`.

---

## Reading the Security Posture Summary

`tools/interpret.py` distills Part B into a single **Security Posture Summary** table
(`rule_security_posture_summary`) — one row per control with an
`OFF/dev → ON/provisioned` verdict. Rows shown in **bold** are the ones that most
change a device's exposure when ON (RSA enforce, encrypt-only, JTAG_DIS, AES
read-lock, PPK provisioned, secure debug, tamper armed). Read it first on any new
board; this document is the detail behind each row, plus the Part A platform context.

## PDF (shareable)

A landscape PDF of this document is at `docs/11-enumerated-attributes.pdf`.
Regenerate after edits:

```
cd docs && pandoc --defaults=pandoc-attributes.yaml -o 11-enumerated-attributes.pdf 11-enumerated-attributes.md
```

(The defaults use landscape + line-wrapping so the wide attribute tables and hexdump
rows fit; needs `pandoc` + `xelatex` + DejaVu fonts, same toolchain as the whitepaper.)

## See also
- `tools/hexdump-attributes.py` — generates the Part C annotated hexdump from any capture.
- [`05-enumeration-tool.md`](05-enumeration-tool.md) — the enumerate/interpret pipeline that produces these reads.
- [`whitepaper/03-enumeration-reveals.md`](whitepaper/03-enumeration-reveals.md) — the narrative companion (what each category enables).
- `docs/annotations/zynqmp_{security,general}.py` — the per-field/per-register decoders.
- `docs/findings/zynqmp_rules.py` — `rule_security_posture_summary` and the other rules.
- `openocd/lib/zynqmp-regs-qemu.tcl` — verified register/address/bit source of truth.
