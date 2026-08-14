# enumerate.tcl — The ZynqMP JTAG Enumeration Tool

This document is the operating manual for the project's primary
artifact. Read it once front-to-back before running the tool on
unfamiliar hardware. Use it as a reference when reading reports.

## Why this tool exists

JTAG is the most privileged debug interface on a modern SoC. On an
unhardened device it gives you read/write access to every memory
location, every peripheral register, every CPU's state — bypassing
the operating system, the hypervisor, even TrustZone if secure debug
is enabled.

For security research, the first question on any new device is:
*how locked-down is it?* That requires answering, in concrete bits:

- Has the vendor blown the JTAG-disable fuse?
- Is RSA-signed-boot enforced?
- Can debug enter TrustZone (SPIDEN)?
- Which peripherals are active right now?
- Is the device in factory state or has a boot image already executed?
- Which keys are in BBRAM / eFUSE?

`enumerate.tcl` answers all of these in one ~10-second run, on any
Zynq UltraScale+ board, with no vendor toolchain required. It is
designed to be re-runnable across boards so two reports can be diffed
to surface security-relevant differences.

Without this tool you would be reading and decoding ~50 registers by
hand for every board, every time. Worse, every hand-decoded bit field
is a chance to misread the datasheet — a class of bugs that has bitten
this project repeatedly (see the "Architecture" section).

## How it produces value

The script doesn't just dump registers — it **interprets them**. Each
of its 12 sections emits a "Findings" table with three columns:

| Observation | Observed value | Implication for research |
|---|---|---|

The Observation column names what was checked. Observed is the
literal value (or a derived summary). Implication is the
research-relevant interpretation: *what does this number mean for
attack surface, hardening posture, or follow-up investigation?*

This is what makes the report useful months later or to another
researcher — the values are decoded, but the **meaning** is
preserved alongside them.

## Quick start

From the project root:

```
cd /home/kali/Desktop/research/JTAG
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl"
```

Optionally, confirm the JTAG chain matches expectation first:

```
openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"
```

Runtime: ~10 seconds.

**Optional — boot-header scan (`::BH_ADDR`).** §4 includes an operator-gated boot-header
scan that captures `encryptionKeySource` (off 0x28) and `fsblAttributes` (off 0x44). The
boot header is not memory-mapped in JTAG-idle, so it is skipped unless you point
`::BH_ADDR` at the boot-image base — e.g. on a target booting from QSPI in linear mode, or
any address where the boot image is readable:

```
openocd -f openocd/zcu102.cfg -c "init; set ::BH_ADDR 0xC0000000; source openocd/enumerate.tcl"
```

The read self-validates against the boot-header magic words (`0xAA995566` at +0x20,
`0x584C4E58`/"XLNX" at +0x24), so a wrong `::BH_ADDR` captures **nothing** rather than a
false reading. When a valid header is found it also **walks the Image Header Table →
Partition Header Table** and captures each partition's encrypt/auth attributes
(`PHT.PART<n>_*`, each PH gated by its own word-checksum, capped at 32). Then
`rule_auth_only_without_encryption` and `rule_pl_bitstream_unprotected` flag
authenticated-but-unencrypted images and PL-bitstream partitions (the JustSTART /
auth-downgrade class — see `docs/15-prior-research.md` §2-4 and `docs/11`).

**Offline boot-image parser (`tools/parse-bootimage.py`).** The live walk only works when
the whole image is resident (QSPI-linear or RAM-loaded). For an SD/QSPI image dump, parse
it offline instead — fully robust, no residency caveat, and it runs the **same rule
engine** so verdicts match the live path:

```
tools/parse-bootimage.py BOOT.bin            # structural dump + posture findings
tools/parse-bootimage.py BOOT.bin --json out.json   # also emit a capture-style JSON
```

It validates all three bootgen word-checksums (boot header, IHT, each PH), decodes
`encryptionKeySource` + every partition's DEST_DEVICE/ENCRYPT/AC_FLAG, and prints the
fired findings.

**Preconditions:**
- Board powered (ZCU102: SW1 ON, SW6 = JTAG idle for cleanest baseline)
- JTAG USB cable connected, passed through to Kali if in VMware
- No other OpenOCD instance bound to the FT232H (`pgrep openocd` is empty)

**Self-healing:** The script's cleanup re-asserts A53 reset at the end
of every run. Consecutive runs on the same boot session work without
power cycling. Only when a prior run crashed mid-cleanup do you need a
power cycle (SW1 off / 5 s / on).

## Outputs

A single run produces three outputs:

| Output | Where | Use |
|---|---|---|
| Raw markdown report | `reports/enumerate-<YYYY-MM-DD-HHMMSS>.md` | What you'd hand a reviewer to show "here's what the silicon returned" — addresses + values + per-bit decode |
| Raw JSON capture | `reports/raw-<YYYY-MM-DD-HHMMSS>.json` | Structured input for `tools/interpret.py`. Schema includes `registers`, `variant`, `a53`, `boot_state`, `memory_probes`, `coresight`, `metadata`, `notes`. |
| Terminal stream | stdout | Live feedback during the run; includes raw OpenOCD startup log |

The interpreted findings report is produced by the second-stage tool:

```
python3 tools/interpret.py reports/raw-<ts>.json -O          # compact (~1000 lines)
python3 tools/interpret.py reports/raw-<ts>.json --full -O   # verbose (~1800 lines, archival)
```

Writes `reports/interpreted-<ts>.md` containing: silicon identity table,
fired rules with severity glyphs and offensive implications, and a
per-register dump where every field is paired with its curated annotation
("**Label** — meaning") when one exists.

## Capture vs interpret pipeline

The enumeration tool is split into two halves so that **interpretation
can evolve independently of capture** — adding a new annotation or rule
doesn't touch the Tcl that talks to silicon.

```
                                           +-- docs/annotations/zynqmp_security.py
                                           |   docs/annotations/zynqmp_general.py
                                           |   (205 field annotations + 15 register-level)
openocd/enumerate.tcl --> reports/raw-*.json --> tools/interpret.py --> reports/interpreted-*.md
        |                                  |
        |                                  +-- docs/findings/zynqmp_rules.py
        |                                      (11 cross-register rules: e.g. "SPIDEN
        |                                       set + JTAG_DIS clear = max debug exposure")
        +-- reports/enumerate-*.md (raw markdown)
```

- **Capture** (`enumerate.tcl`): hits silicon, decodes bits using QEMU-
  sourced layouts in `openocd/lib/zynqmp-regs-qemu.tcl`, writes raw md +
  raw JSON. No interpretation, no security judgement.
- **Interpret** (`interpret.py`): reads raw JSON. Each register's fields
  get a "what we got + what this means" line via the annotation lookup.
  Cross-register rules fire on combinations (e.g. SPIDEN=1 → CRITICAL
  "secure-world TrustZone debug enabled").

Annotation types:
- `Annotation` — per-field, value-specific (e.g. `JTAG_DAP_CFG.SSSS_APU_SPIDEN`
  value 1 → "**Secure-world debug ENABLED** — JTAG can halt the EL3 monitor.")
- `Annotation(register="*")` — wildcard, matches the same field name across
  every register that has it (e.g. `CLKACT`, `BYPASS`, `RESET`, `*_LOCK`).
  Specific entries win over wildcards via `find_annotation` precedence.
- `RegisterAnnotation` — for fieldless registers (e.g. `XPPU.BASE_64KB`,
  `CSU.CSU_MULTI_BOOT`); optional `interpret(value)` callable computes a
  derived meaning from the raw value.

## How to read a report

Reports have this fixed structure (so diffs work cleanly):

```
# Header (timestamp, tool, report path)
# §1  JTAG Chain
# §2  Silicon Identity
# §3  Boot State
# §4  Security State (research focus)   <-- the most important section
# §5  Power State (PMU_GLOBAL)
# §6  Clocks: PLLs and Reference Clocks
# §7  Reset State
# §8  A53 Release + System Registers (EL3)
# §9  Code Execution Discovery
# §10 CoreSight DAP Topology (per-AP enumeration via dap info)
# §11 ZynqMP Memory Map Reference
# §12 Memory Map Probe
# §13 XPPU (Xilinx Peripheral Protection Unit)
# §14 RPU Configuration (Cortex-R5 cluster)
# §15 IPI (Inter-Processor Interrupt) — APU agent window
# §16 XMPU (Xilinx Memory Protection Unit) — DDR0..5 / FPD / OCM TrustZone
# §17 PL TAP + PCAP Configuration Status
# §18 SLCR Security Controls (LPD / FPD / IOU_SECURE / LPD_SECURE)
# Cleanup
```

Each section in the **raw** report has:

1. **Raw register dumps** — `0xADDR = 0xVALUE` with per-bit field decode.

The **interpreted** report renders the same data plus:

1. A fired-rules summary at the top (CRITICAL/MAJOR/MINOR/INFO).
2. Per-register, each field gets a curated annotation line where available.

A useful reading flow for a fresh report:

1. Skim §2 to confirm what chip you're on.
2. Skim §3 to see what state it booted into (JTAG-idle vs SD/QSPI/etc.).
3. **Read §4 carefully — this is where the hardening posture lives.**
4. Glance at §8 to see if A53 release succeeded.
5. Skim §9 to see if any boot artifacts (FSBL, U-Boot, kernel) are
   detectable in OCM/DDR.

Sections §5, §6, §7 are usually only interesting when something is
wrong (PLL not locked, peripheral unexpectedly powered, etc.).

## Hardening posture: what to look for in §4

This is the security researcher's punch list. Read every row.

> **Start with the Security Posture Summary.** `interpret.py` distills the §4
> security reads into a single **Security Posture Summary** table
> (`rule_security_posture_summary`) — one row per security implementation with
> an `OFF/dev → ON/provisioned` verdict. It's the at-a-glance artifact to read
> first on any new board. Every attribute it covers — location, dev value,
> hardened meaning, and why it matters — is cataloged in
> [`11-enumerated-attributes.md`](11-enumerated-attributes.md).
>
> §4 now reads the full security surface: secure-boot policy (`SEC_CTRL`,
> `ENC_ONLY`, `RSA_EN`), the complete PPK0/PPK1 hash words, key state
> (`AES_STATUS`, `EFUSE_AES_CRC`, `AES_RDLK/WRLK`), eFuse provisioning/locks
> (`WR_LOCK`, `ISR`, `PGM_LOCK`), CSU core/boot integrity
> (`CSU_STATUS/CTRL/SSS_CFG/MULTI_BOOT/FT_STATUS`), and the full anti-tamper
> policy block (`TAMPER_STATUS` + `CSU_TAMPER_0..12`). Memory TrustZone
> (DDR/FPD/OCM XMPU) is in §16.

### `CSU.JTAG_SEC` (0xFFCA0038)

Three 3-bit fields gating the CSU Secure Stream Switch:

| Field | Bits | What it gates |
|---|---|---|
| `SSSS_DAP_SEC` | [2:0] | Secure JTAG path to ARM DAP (APU/RPU debug) |
| `SSSS_PLTAP_SEC` | [5:3] | Secure JTAG path to PL TAP (FPGA) |
| `SSSS_PMU_SEC` | [8:6] | Secure JTAG path to PMU |

Each 3-bit field requires a magic unlock value (`0b111`) — a single
bit flip can't open the gate (anti-glitch defense).

**Reading:**
- All three fields = `0b111` (raw value `0x1FF`) — fully unlocked, maximum dev access
- All three fields = `0b000` (raw value `0x000`) — production-hardened
- Mixed values — partial gating; document which paths are open

### `CSU.JTAG_DAP_CFG` (0xFFCA003C)

Six 1-bit gates for APU and RPU debug. Despite what older script
versions claimed, these are **cluster-wide gates, not per-core**:

| Field | Bit | Effect |
|---|---|---|
| `SSSS_APU_DBGEN` | 0 | APU halt/step/breakpoint allowed |
| `SSSS_APU_NIDEN` | 1 | APU ETM/trace output allowed |
| `SSSS_APU_SPIDEN` | 2 | **APU secure-world (EL3/TrustZone) debug allowed** |
| `SSSS_APU_SPNIDEN` | 3 | APU secure-world trace allowed |
| `SSSS_RPU_DBGEN` | 4 | RPU (R5) debug allowed |
| `SSSS_RPU_NIDEN` | 5 | RPU trace allowed |

**SPIDEN is the bit that defines whether the device's secure-world is
attackable via JTAG.** On a properly hardened production device,
SPIDEN should be 0 (and the corresponding eFUSE bits should make
re-enabling it impossible).

On a ZCU102 dev kit, all 6 bits are typically set (`0xFF` or `0x3F`)
— factory state. The whole TrustZone is exposed to JTAG.

### `EFUSE.SEC_CTRL` (0xFFCC1058)

Per-bit secure-boot policy fuses. Each is **one-way** — once blown,
cannot be unblown without re-fabrication.

| Bit(s) | Field | Effect when set |
|---|---|---|
| 0 | `AES_RDLK` | AES key in eFUSE can't be read |
| 1 | `AES_WRLK` | AES key in eFUSE can't be written |
| 2 | `ENC_ONLY` | Boot image MUST be encrypted |
| 3 | `BBRAM_DIS` | BBRAM disabled as key source (use eFUSE AES key only) |
| 4 | `ERROR_DIS` | Error-injection JTAG disable |
| 5 | `JTAG_DIS` | **HARDWARE JTAG DISABLE — one-way.** No JTAG of any kind. |
| 6 | `DFT_DIS` | Design-for-Test JTAG disabled |
| 7-9 | `PROG_GATE_0/1/2` | PL programming gates |
| 10 | `SEC_LOCK` | **Lock SEC_CTRL itself — no further fuses settable.** |
| [25:11] | `RSA_EN` | 15-bit magic field. When containing the magic value, RSA-signed boot is required. |
| 26 | `PPK0_WRLK` | Primary Public Key 0 write lock |
| [28:27] | `PPK0_INVLD` | Invalidate PPK0 |
| 29 | `PPK1_WRLK` | PPK1 write lock |
| [31:30] | `PPK1_INVLD` | Invalidate PPK1 |

**Two width oddities worth knowing:** `RSA_EN` is a 15-bit field
(not a single bit). `PPK0_INVLD`/`PPK1_INVLD` are 2-bit fields. Both
are anti-glitch defenses: a single bit flip from a fault-injection
attack can't enable RSA bypass or invalidate a PPK.

**Production-hardened baseline (what to look for):**
- `RSA_EN` = magic value (any non-zero in the 15-bit field is suspicious)
- `SEC_LOCK` = 1
- Often `JTAG_DIS` = 1 (but not always — debugging hardened devices is its own art)

**Dev-kit baseline (what you'll see on ZCU102):**
- Entire register = `0x00000000`. No fuses blown.

## Section-by-section reference

### §1 — JTAG Chain

What's probed: TAPs discovered by OpenOCD during init, with their
IRLen and expected role.

Why it matters: confirms the JTAG hardware path is intact. A
2-TAP chain on a ZynqMP board (PS-TAP + DAP) is the healthy
configuration. Fewer TAPs (or extra unknown TAPs) indicates either
a board config mismatch or unusual silicon.

IDCODEs themselves appear in the OpenOCD startup log above this
section (different output channel — not in the report file).

### §2 — Silicon Identity

What's probed:
- `CSU_IDCODE` (0xFFCA0040) — same IDCODE as JTAG (sanity check via two paths)
- `CSU_VERSION` (0xFFCA0044) — silicon revision + platform
- eFUSE Device DNA (96 bits, three 32-bit words at `0xFFCC100C/1010/1014`)

Why it matters: confirms which UltraScale+ variant (ZU2/3/4/5/6/7/9/11/15/17/19
or RFSoC ZU21-67DR) you're on. Variant determines memory map specifics
(VCU presence, GPU, RF tiles, A53 core count). The variant lookup table
in `lib/zynqmp-variants.tcl` translates the IDCODE's PART_ID field into
the die name and capability profile.

Device DNA is a per-chip unique identifier — useful for fingerprinting
when comparing multiple supposedly-identical boards. Zero DNA suggests
factory-blank silicon or eFUSE access locked.

### §3 — Boot State

What's probed:
- `CRL_APB.BOOT_MODE_USER` (0xFF5E0200) — current boot mode pins
- `CRL_APB.BOOT_MODE_POR` (0xFF5E0204) — boot mode latched at PS_POR_B
- `CSU_MULTI_BOOT` (0xFFCA0010) — offset for next boot image search
- `CRL_APB.RESET_REASON` (0xFF5E0220) — what caused the last reset
- `CSU_STATUS` (0xFFCA0000) — CSU state

Why it matters: determines whether the device is in a clean baseline
(JTAG idle, only BootROM has executed) or in a post-boot state
(FSBL/U-Boot/Linux has run and modified state). Many subsequent
sections only make sense if you know which.

`RESET_REASON` decoding was historically wrong in this script
(fabricated field names) — now sourced from Xilinx QEMU. Real bit
labels: `EXTERNAL_POR` (bit 0), `INTERNAL_POR` (bit 1), `PMU_SYS_RESET`,
`PSONLY_RESET_REQ`, `SRST`, `SOFT`, `DEBUG_SYS`, `MIMIC` (bit 15).

### §4 — Security State (research focus)

The most important section. See the "Hardening posture" guide above
for what each register means and what to look for.

What's probed:
- `CSU.JTAG_SEC` (0xFFCA0038) — secure-JTAG SSS gates
- `CSU.JTAG_DAP_CFG` (0xFFCA003C) — APU/RPU debug authorization
- `CSU.JTAG_CHAIN_STATUS` (0xFFCA0034)
- `CSU.JTAG_CHAIN_CFG` (0xFFCA0030) — *not in QEMU coverage*
- `EFUSE.STATUS` (0xFFCC0008) — eFUSE controller state
- `EFUSE.SEC_CTRL` (0xFFCC1058) — secure-boot policy fuses
- Additional shadow registers: `MISC_USER_CTRL`, `PUF_CHASH`, `PUF_MISC`,
  `SPK_ID`, `PPK0_HASH[0/1]`, `PPK1_HASH[0]`, `USER0/1`

The findings table interprets each in the context of "is this a
hardened device or a dev kit?"

### §5 — Power State (PMU_GLOBAL)

What's probed: `PMU_GLOBAL.PWR_STATE` (0xFFD80100) bit-by-bit
plus PWRUP/PWRDWN status and PMU error registers.

Why it matters: tells you which subsystems are powered up *right now*.
Affects what you can probe — peripherals in power-off domains will
AXI-timeout if you read their registers, potentially wedging the DAP.

Correct PWR_STATE layout (per QEMU):

| Bits | Meaning |
|---|---|
| [3:0] | ACPU0-3 (each A53 core) |
| [4-5] | PP0/PP1 (PMU processor pools) |
| [7] | L2_BANK0 |
| [10-11] | R5_0/R5_1 (RPU cores) |
| [12-15] | TCM0A/B, TCM1A/B (RPU tightly-coupled memory) |
| [16-19] | OCM_BANK0-3 |
| [20-21] | USB0/USB1 |
| [22] | FP (Full-Power Domain) |
| [23] | PL (Programmable Logic / FPGA) |

GEM (Ethernet) power state is **not** in PWR_STATE — earlier script
versions claimed it was at bits 24-27, but those are unused. To check
GEM, read `CRL_APB.GEM0_REF_CTRL` (CLKACT bit 25) and the relevant
reset bits in `RST_LPD_IOU0`.

### §6 — Clocks: PLLs and Reference Clocks

What's probed:
- All 5 PLL CTRL/CFG registers (APLL/DPLL/VPLL in FPD; IOPLL/RPLL in LPD)
- Two `PLL_STATUS` registers (one per domain) showing lock + stable bits
- Every peripheral `REF_CTRL` (UART/SPI/I2C/USB/GEM/SDIO/QSPI/LPD_LSBUS)
- `ACPU_CTRL`, `DBG_TRACE_CTRL`, `DBG_FPD_CTRL`, `GDMA_REF_CTRL`

Why it matters: PLLs that aren't locked cause downstream peripherals
to malfunction. Each peripheral's `CLKACT` bit determines whether it's
clocked. Combined with §7 reset state, this answers "is this peripheral
actually usable?"

**Important caveat about PLL_STATUS:** earlier versions of this script
had the bit layout wrong (interleaved STABLE/LOCK pairs). The real
layout per Xilinx QEMU has all LOCK bits first (bits 0-2 for FPD or
0-1 for LPD), then all STABLE bits (bits 3-5 for FPD or 3-4 for LPD).

A PLL with `LOCK=0` but `STABLE=1` is almost always in BYPASS mode
(check the CTRL.BYPASS bit) — the system clock comes from the bypass
path, not the PLL output. This is normal on ZCU102 in JTAG-idle for
APLL and VPLL.

### §7 — Reset State

What's probed:
- `CRF_APB.RST_FPD_APU` (0xFD1A0104) — ACPU0-3 + L2 + power-on resets
- `CRF_APB.RST_FPD_TOP` (0xFD1A0100)
- `CRF_APB.RST_DDR_SS` (0xFD1A0108)
- `CRL_APB.RST_LPD_IOU0` (0xFF5E0230) — GEM resets
- `CRL_APB.RST_LPD_IOU1` (0xFF5E0234) — *not in QEMU coverage*
- `CRL_APB.RST_LPD_IOU2` (0xFF5E0238) — most LPD peripherals
- `CRL_APB.RST_LPD_TOP` (0xFF5E023C)

Why it matters: confirms why A53 examine fails (cores held in reset
in JTAG-idle) and which peripherals can be safely probed. **A
peripheral held in reset will AXI-timeout on register read, potentially
wedging the DAP.** The script gates §12 memory-map probe on this.

**Correction note:** RST_LPD_IOU2 bit 0 is `QSPI_RESET`, not
`GPIO_RESET`. Real GPIO_RESET is at bit 18. Old report findings text
that said "GPIO held in reset" was actually observing QSPI's reset bit.

### §8 — A53 Release + System Registers (EL3)

What it does: applies the four-step JTAG-only A53 release recipe (see
`docs/04-jtag-research-techniques.md` for the full theory), halts core 0
in EL3 handler mode (EL3H, PSTATE.M = 0xD), dumps general-purpose
registers.

Why it matters: EL3H is the highest ARMv8 privilege level — above any
OS, hypervisor, or TrustZone monitor. From here you can read/write any
memory and any system register, install rogue EL3 handlers, observe
secure-world execution.

The release is idempotent (safe to re-run) and the cleanup section at
the end re-asserts A53 reset so subsequent runs start clean.

**Known gap:** ARM system registers (`MIDR_EL1`, `SCR_EL3`,
`CNTFRQ_EL0`, `ID_AA64*_EL1`) are not exposed by name in OpenOCD
0.12's aarch64 target on this build. Capturing them requires a
stage-2 payload (`mrs xN, sysreg; str xN, [addr]`) that lands results
in memory. This is the planned `openocd/sysreg-dump.tcl`.

### §9 — Code Execution Discovery

What it does:
- Reports the PC of each released A53 core, categorizes its region
- Spot-checks OCM at `0xFFFC0000` and `0xFFFE0000` for FSBL signatures
  or our safe-landing `b .` instruction or DEADBEEF poison
- **Conditionally** scans DDR for boot artifacts — only if boot mode ≠ JTAG-idle,
  otherwise DDR controller isn't initialized and a probe would wedge
  the AXI bus

DDR signatures looked for at PetaLinux default addresses:

| Address | Pattern | What it identifies |
|---|---|---|
| `0x00080000` | `ARM\x64` magic | Linux AArch64 kernel Image header (older PetaLinux) |
| `0x00200000` | `ARM\x64` magic | Linux kernel Image (PetaLinux 2020.2+) |
| `0x00100000` | `0xD00DFEED` | Device tree blob (DTB) — Xilinx convention |
| `0x04000000` | `070701` | initramfs cpio magic |
| `0x08000000` | `U-Boot` | U-Boot proper at canonical 128 MB load |
| `0x08000000` | `Booting Linux` | U-Boot pre-kernel banner |

**Custom boot configurations** (VxWorks, FreeRTOS, custom U-Boot env)
will have different addresses — these are only PetaLinux defaults.
A board with no matches in DDR scan isn't necessarily empty; it may
just use different load addresses.

Also reads `CSU_ROM_DIGEST_ADDR` (0xFFCA0048) — non-zero means BootROM
authenticated a boot image. Zero = JTAG idle.

### §10 — CoreSight DAP Topology

Calls `uscale.dap info 1` which enumerates every CoreSight component
visible through the APB-AP: per-core Debug Units, CTIs, PMUs, ETMs;
system-level Trace Funnels, TMCs, TPIU, STM.

Output goes to **OpenOCD stdout, not the report file** — it's ~150
lines per board, large enough to be unwieldy in a markdown report.
Save your terminal output (`| tee logs/foo.log`) if you want to diff
CoreSight topology across boards.

This is where CTI cross-trigger bugs, ETM misconfigurations, and
other CoreSight-related attack surface would show up.

### §11 — Memory Map Reference

Not a probe — a static reference table of where each major SoC block
lives. Used by §12 (Memory Map Probe) to know what to test and by
researchers to quickly cross-reference addresses.

Address ranges shown are **identical across all UltraScale+ variants**.
The variant table in §2 tells you which features (VCU, GPU, RF) the
specific chip exposes within those addresses.

### §12 — Memory Map Probe

What it does: reads a representative address from each major block
to confirm the AXI bus path responds.

What it deliberately skips:
- Peripherals held in reset (would AXI-timeout)
- DDR (controller not initialized in JTAG-idle)
- PL aperture (FPGA not configured)

For exhaustive per-peripheral probing, write a separate script that
first clears the relevant reset bit (`RST_LPD_IOU2` etc.) and enables
the clock (`*_REF_CTRL.CLKACT`), then probes.

### Cleanup

Re-asserts A53 reset bits in `RST_FPD_APU` (0x380E → 0x3D0F) so the
next run starts clean. Without this, the auto-init in OpenOCD's
ZynqMP target config touches an already-released A53 and wedges the
DP with sticky errors.

## Architecture: how the script stays honest

This is the part that prior versions of this manual didn't cover, and
that turned out to matter a lot.

### The problem: hand-typed bit fields drift from reality

The original `enumerate.tcl` had bit-field decodings hand-typed from
datasheets. An audit in May 2026 found **89 discrepancies across 39
registers** — including the most security-critical ones:

- `CSU.JTAG_DAP_CFG` claimed 20 per-core debug bits; really 6 cluster-wide bits
- `CSU.JTAG_SEC` claimed 6 single-bit gates; really 3 magic-3-bit fields
- `PMU_GLOBAL.PWR_STATE` had FP, USB0/1, OCM bank bits all wrong
- `CRL_APB.RESET_REASON` had every field name fabricated
- `EFUSE.SEC_CTRL`'s RSA_EN claimed at bit 11; really a 15-bit field [25:11]
- Three registers were dumped from wrong addresses entirely
  (DBG_TRACE_CTRL, DBG_FPD_CTRL, GDMA_REF_CTRL, REQ_PWRDWN_STATUS)

Every "Findings" interpretation was built on those bit positions.
Reports were producing confident-sounding text backed by fiction.

### The fix: QEMU as single source of truth

`/opt/xilinx/qemu` (the Xilinx fork of QEMU) contains C-language
register models for the ZynqMP SoC. These are "as-implemented" —
they describe how the silicon actually responds, not how the
datasheet describes it.

The new architecture:

```
+-----------------------------+        +-------------------------+
| /opt/xilinx/qemu/hw/misc/   |        |                         |
|   xilinx_zynqmp_crf.c       | -----> | regenerate-qemu-regs.py |
|   xilinx_zynqmp_crl.c       |        |                         |
|   csu_core.c                |        +------------+------------+
|   ... 8 more files          |                     |
+-----------------------------+                     v
                                       +-----------------------------+
                                       | openocd/lib/                |
                                       |   zynqmp-regs-qemu.tcl      |
                                       |   (auto-generated,          |
                                       |    602 registers)           |
                                       +--------------+--------------+
                                                      |
                                                      v
                                       +-----------------------------+
                                       | openocd/enumerate.tcl       |
                                       |                             |
                                       | dump_reg_qemu 0xFFCA003C    |
                                       |   -> looks up layout in     |
                                       |      ::QEMU_REGS dict       |
                                       +-----------------------------+
```

Bit fields are no longer hand-typed in `enumerate.tcl`. The script
calls `dump_reg_qemu 0xADDR` and the layout comes from the
auto-generated Tcl dict. There is **no way for the script to drift
from QEMU's model** — the field positions are derived, not authored.

### The supporting tools

| Tool | Purpose |
|---|---|
| `tools/regenerate-qemu-regs.py` | Parse Xilinx QEMU C sources, emit `lib/zynqmp-regs-qemu.tcl` with 656 ZynqMP register layouts |
| `tools/interpret.py` | Read a raw enumeration JSON, apply annotations + rules, write the interpreted findings markdown |
| `tools/interpret_lib.py` | `Capture` / `Annotation` / `RegisterAnnotation` / `Finding` dataclasses |
| `tools/generate-mock-seed.py` | Read a raw JSON capture, emit a Tcl seed file for the mock harness |
| `tools/check-annotations.py` | Annotation-module self-test (typos, dead wildcards, duplicates, unknown registers) |
| `tools/golden-test.sh` | Diff interpret.py output against the frozen golden interpreted markdown |
| `tools/golden-test-roundtrip.sh` | Run enumerate.tcl under the mock, diff produced raw JSON + markdown against goldens |
| `tools/tcl-smoketest.sh` | One-command full smoke: static parse + Tcl-stub run + annotation sanity + interpret-golden + roundtrip-golden |
| `openocd/lib/mock-openocd.tcl` | Stubs every OpenOCD command enumerate.tcl uses, backed by a seeded register dict |

The smoke runner walks all four test layers; any regression in
`interpret.py`, annotations, rules, enumerate.tcl, json-emit.tcl, or the
generator surfaces with a unified diff against `tests/golden/zcu102-jtag-idle/`.

After the May 2026 audit + cleanup:
- 0 bit-layout discrepancies (everything goes through `dump_reg_qemu`
  whose fields come directly from QEMU — drift is structurally impossible)
- 205 field annotations + 15 register-level annotations, all references
  resolved against `zynqmp-regs-qemu.tcl`
- 4 test layers passing on `./tools/tcl-smoketest.sh`

### Adding coverage for a new block

To extend the lookup to a new SoC block:

1. Find the QEMU file for the block under `/opt/xilinx/qemu/hw/`
2. Add it to `BLOCKS` in `tools/regenerate-qemu-regs.py` with its
   base address
3. Re-run the generator: `python3 tools/regenerate-qemu-regs.py`
4. In `enumerate.tcl`, call `dump_reg_qemu 0xADDR` for any register
   in that block
5. Optionally add annotations under `docs/annotations/zynqmp_*.py`
   for fields whose value-specific meaning isn't obvious from the
   field name alone
6. Re-run `./tools/tcl-smoketest.sh`; update goldens with
   `bash tools/golden-test.sh --update` if the change is intentional

No hand-typed bit fields. No drift possible.

## Diffing reports across boards

Reports have stable structure so `diff` works cleanly:

```
diff -u reports/enumerate-OLD.md reports/enumerate-NEW.md | less
```

Notable diffs to look for when comparing dev kit vs production:

| Field | Dev kit | Production |
|---|---|---|
| `EFUSE.SEC_CTRL` | `0x00000000` | non-zero (specific bits blown) |
| `CSU.JTAG_DAP_CFG` SPIDEN | 1 | 0 |
| `CSU.JTAG_SEC` | `0x00000000` or `0x000001FF` | typically `0x00000000` |
| Boot mode | 0 (JTAG idle) | non-zero (SD/QSPI/eMMC) |
| Device DNA | unique value | unique value |
| `CSU_ROM_DIGEST_ADDR` | 0 | non-zero (BootROM authenticated) |
| A53 core 0 PC | `0xFFFC0000` (our safe landing) | DDR address (real firmware) |

## Limitations and known gaps

**The QEMU model isn't the silicon itself.** If a Xilinx errata
documents a hardware behavior not in QEMU's model, the script could
be subtly wrong about that one bit on real hardware. UG1085 / UG1087
are the ultimate authority — we don't have local PDFs of these. When
findings disagree with observed reality, suspect the model before the
hardware.

**Three registers are unverifiable** via QEMU at present (fall back
to plain hex dump with no bit decode):
- `CSU.JTAG_CHAIN_CFG` (0xFFCA0030)
- `CRF_APB.DBG_FPD_CTRL` (0xFD1A0068)
- `CRL_APB.RST_LPD_IOU1` (0xFF5E0234)

These need hand verification against UG1087 (scheduled work).

**System registers not captured.** Section 8 explains why
(OpenOCD output channel issue) and lists the deferred plan
(`openocd/sysreg-dump.tcl`).

**DDR not probed in JTAG-idle.** DDR controller isn't initialized
until FSBL runs. Probing in JTAG-idle wedges the AXI bus. Boot from
SD/QSPI first if you want DDR analysis.

**PL bitstream contents not analyzed.** Section 9 reports whether PL
is powered, but doesn't read the configuration memory or analyze the
bitstream. That's a separate research direction.

**Custom boot artifact addresses not detected.** §9 DDR scan looks
only at PetaLinux defaults. A board running VxWorks, FreeRTOS, custom
U-Boot environment, or any non-PetaLinux Linux distribution will not
match the signature patterns. Absence of matches doesn't mean absence
of code.

**XPPU/XMPU/IPI/SMMU not enumerated.** These are critical for modern
attack surface (peripheral protection, memory protection, inter-processor
messaging, IOMMU). Scheduled work — they'll arrive as new baseline
sections following the same QEMU-sourced pattern.

## Quick-reference: research questions answered by the report

| Question | Where to look |
|---|---|
| What chip is this? | §2 findings table, "Chip identity" row |
| Is this production silicon or engineering sample? | §2 findings, "Silicon variant" row |
| Is this a fresh power-on or post-boot? | §3 findings, "Reset reason" row |
| What did the board boot from? | §3 findings, "Boot mode" row |
| Is JTAG hardware-disabled (production)? | §4 findings, EFUSE.SEC_CTRL row, `JTAG_DIS` |
| Can I debug TrustZone secure world? | §4 findings, SPIDEN row |
| Is RSA-signed boot enforced? | §4 findings, EFUSE.SEC_CTRL row, `RSA_EN` |
| Can I read the AES key? | §4 findings, EFUSE.SEC_CTRL row, `AES_RDLK` |
| Are the security fuses locked? | §4 findings, `SEC_LOCK` |
| Did BootROM authenticate a boot image? | §9 findings, `CSU_ROM_DIGEST_ADDR` row |
| Is the FPGA (PL) configured? | §5 findings, `PL` row + bitstream inspection |
| Where is firmware running right now? | §9 findings, "A53 core 0 PC" row |
| Are PLLs healthy / clocks coming up? | §6 findings table |
| Which peripherals are usable right now? | §6 (clocks) + §7 (resets) cross-referenced |

## Appendix: every register the script reads

Flat reference for "what does this tool actually touch?" Grouped by
SoC block, in script execution order within each block. All bit field
decodings come from the QEMU-sourced library
(`openocd/lib/zynqmp-regs-qemu.tcl`) unless noted.

### CSU — Configuration and Security Unit (base `0xFFCA0000`)

| Address | Register | Section | What it tells you |
|---|---|---|---|
| `0xFFCA0000` | `CSU.STATUS` | §3 | CSU controller status |
| `0xFFCA0010` | `CSU.MULTI_BOOT` | §3 | Boot image search offset |
| `0xFFCA0030` | `CSU.JTAG_CHAIN_CFG` | §4 | JTAG chain write-side setup (hand-verified, not in QEMU) |
| `0xFFCA0034` | `CSU.JTAG_CHAIN_STATUS` | §4 | Which TAPs are visible in the chain (PL_TAP, ARM_DAP) |
| `0xFFCA0038` | `CSU.JTAG_SEC` | §4 | **Secure JTAG gates** — three 3-bit magic fields (DAP, PLTAP, PMU paths) |
| `0xFFCA003C` | `CSU.JTAG_DAP_CFG` | §4 | **APU + RPU debug enable** including secure-world (SPIDEN) |
| `0xFFCA0040` | `CSU.IDCODE` | §2 | Silicon ID (manufacturer, part, revision) per IEEE 1149.1 |
| `0xFFCA0044` | `CSU.VERSION` | §2 | Silicon revision + platform field |
| `0xFFCA0048` | `CSU.ROM_DIGEST_ADDR` | §9 | Non-zero means BootROM authenticated a boot image |

### eFUSE — secure-boot policy fuses (base `0xFFCC0000`)

| Address | Register | Section | What it tells you |
|---|---|---|---|
| `0xFFCC0008` | `EFUSE.STATUS` | §4 | eFUSE controller state |
| `0xFFCC100C` | `EFUSE.DNA_0` | §2 | Device DNA bits [31:0] — unique per chip |
| `0xFFCC1010` | `EFUSE.DNA_1` | §2 | Device DNA bits [63:32] |
| `0xFFCC1014` | `EFUSE.DNA_2` | §2 | Device DNA bits [95:64] |
| `0xFFCC1058` | `EFUSE.SEC_CTRL` | §4 | **Secure-boot policy fuses** — RSA_EN, JTAG_DIS, SEC_LOCK, PPK invalidation |
| also dumped: `MISC_USER_CTRL`, `PUF_CHASH`, `PUF_MISC`, `SPK_ID`, `PPK0_HASH[0/1]`, `PPK1_HASH[0]`, `USER0`, `USER1` | | §4 | additional shadow registers for fingerprinting |

### PMU_GLOBAL — Platform Management Unit state (base `0xFFD80000`)

| Address | Register | Section | What it tells you |
|---|---|---|---|
| `0xFFD80000` | `PMU_GLOBAL.GLOBAL_CNTRL` | §5 | Overall PMU control state |
| `0xFFD80100` | `PMU_GLOBAL.PWR_STATE` | §5 | **Which power domains are alive**: ACPU0-3, R5_0/1, TCM, OCM banks 0-3, USB0/1, FP, PL, L2, PP0/1 |
| `0xFFD80110` | `PMU_GLOBAL.REQ_PWRUP_STATUS` | §5 | Pending power-up requests |
| `0xFFD80210` | `PMU_GLOBAL.REQ_PWRDWN_STATUS` | §5 | Pending power-down requests |
| `0xFFD80530` | `PMU_GLOBAL.ERROR_STATUS_1` | §5 | PMU error history (bank 1) |
| `0xFFD80540` | `PMU_GLOBAL.ERROR_STATUS_2` | §5 | PMU error history (bank 2) |

### CRF_APB — Full Power Domain clocks and resets (base `0xFD1A0000`)

| Address | Register | Section | What it tells you |
|---|---|---|---|
| `0xFD1A0020` | `APLL_CTRL` | §6 | APU PLL config (BYPASS, RESET, FBDIV, PRE_SRC, POST_SRC) |
| `0xFD1A0024` | `APLL_CFG` | §6 | APLL loop filter / lock parameters |
| `0xFD1A002C` | `DPLL_CTRL` | §6 | DDR PLL config |
| `0xFD1A0030` | `DPLL_CFG` | §6 | DPLL parameters |
| `0xFD1A0038` | `VPLL_CTRL` | §6 | Video PLL config |
| `0xFD1A003C` | `VPLL_CFG` | §6 | VPLL parameters |
| `0xFD1A0044` | `PLL_STATUS (FPD)` | §6 | APLL/DPLL/VPLL LOCK + STABLE bits |
| `0xFD1A0060` | `ACPU_CTRL` | §6 | A53 cluster clock source + divisor + CLKACT |
| `0xFD1A0064` | `DBG_TRACE_CTRL` | §6 | CoreSight trace clock |
| `0xFD1A0068` | `DBG_FPD_CTRL` | §6 | Full-power-domain debug clock |
| `0xFD1A00B8` | `GDMA_REF_CTRL` | §6 | General DMA reference clock |
| `0xFD1A0100` | `RST_FPD_TOP` | §7 | Top-level FPD reset state |
| `0xFD1A0104` | `RST_FPD_APU` | §7 | **A53 per-core reset + L2 + power-on resets** — the script writes here in §8 to release the A53 |
| `0xFD1A0108` | `RST_DDR_SS` | §7 | DDR subsystem reset |

### CRL_APB — Low Power Domain clocks and resets (base `0xFF5E0000`)

| Address | Register | Section | What it tells you |
|---|---|---|---|
| `0xFF5E0020` | `IOPLL_CTRL` | §6 | I/O PLL config |
| `0xFF5E0024` | `IOPLL_CFG` | §6 | IOPLL parameters |
| `0xFF5E0030` | `RPLL_CTRL` | §6 | RPU PLL config |
| `0xFF5E0034` | `RPLL_CFG` | §6 | RPLL parameters |
| `0xFF5E0040` | `PLL_STATUS (LPD)` | §6 | IOPLL/RPLL LOCK + STABLE bits |
| `0xFF5E0050-005C` | `GEM0/1/2/3_REF_CTRL` | §6 | Ethernet GEM clocks (CLKACT at bit 25, RX_CLKACT at bit 26) |
| `0xFF5E0060/0064` | `USB0/1_BUS_REF_CTRL` | §6 | USB bus reference clocks |
| `0xFF5E0068` | `QSPI_REF_CTRL` | §6 | QSPI reference clock |
| `0xFF5E006C/0070` | `SDIO0/1_REF_CTRL` | §6 | SD/eMMC reference clocks |
| `0xFF5E0074/0078` | `UART0/1_REF_CTRL` | §6 | UART reference clocks (CLKACT at bit 24) |
| `0xFF5E007C/0080` | `SPI0/1_REF_CTRL` | §6 | SPI reference clocks |
| `0xFF5E00AC` | `LPD_LSBUS_CTRL` | §6 | LPD low-speed bus clock |
| `0xFF5E0120/0124` | `I2C0/1_REF_CTRL` | §6 | I2C reference clocks |
| `0xFF5E0200` | `BOOT_MODE_USER` | §3 | **Boot mode pins** — what the SW6 DIP switches selected |
| `0xFF5E0204` | `BOOT_MODE_POR` | §3 | Boot mode latched at PS_POR_B (cannot be changed after) |
| `0xFF5E0220` | `RESET_REASON` | §3 | **Why did the last reset happen?** EXTERNAL_POR, INTERNAL_POR, SRST, SOFT, DEBUG_SYS, etc. |
| `0xFF5E0230` | `RST_LPD_IOU0` | §7 | GEM0-3 reset bits |
| `0xFF5E0238` | `RST_LPD_IOU2` | §7 | **Most LPD peripheral resets**: QSPI, UART0/1, SPI0/1, SDIO0/1, CAN0/1, I2C0/1, TTC0-3, SWDT, NAND, ADMA, GPIO, IOU_CC, TIMESTAMP |
| `0xFF5E023C` | `RST_LPD_TOP` | §7 | LPD top-level reset state |

### APU registers (base `0xFD5C0000`) — written by §8 A53 release

| Address | Register | Notes |
|---|---|---|
| `0xFD5C0040` | `APU.RVBARADDR0L` | A53 core 0 reset vector low 32 bits — written to `0xFFFC0000` during release |
| `0xFD5C0044` | `APU.RVBARADDR0H` | A53 core 0 reset vector high 32 bits — written to `0x00000000` |

### Memory regions probed (§12 — read-only sanity checks)

| Region | Address(es) | What we look for |
|---|---|---|
| OCM Bank 0-3 + ATF | `0xFFFC0000`, `0xFFFC8000`, `0xFFFD0000`, `0xFFFE0000`, `0xFFFF0000` | DEADBEEF poison = no FSBL; `b .` (`0x14000000`) = our safe landing; anything else = real code |
| OCM BootROM region | `0xFFFFC000` | CSU ROM mapping |
| DDR (only if boot mode ≠ JTAG-idle) | `0x00080000`, `0x00100000`, `0x00200000`, `0x04000000`, `0x08000000` | Linux kernel header, DTB magic, initramfs cpio magic, U-Boot string |
| First-word probe of each major block | CSU, EFUSE, BBRAM, IOU_SLCR, CRL_APB, CRF_APB, PMU_GLOBAL | Confirm AXI bus path responds |

### Total

Approximately **50 unique register reads** per run, plus ~10 memory region probes, plus the A53 system register dump in §8.

Compared to `discover.tcl` which reads **only AP IDR registers** (no SoC registers), `enumerate.tcl` is the deep-inspection tool.

## Maintenance

If you change `enumerate.tcl`, `interpret.py`, or any annotation/rule module:

```
./tools/tcl-smoketest.sh
```

This runs the full 4-layer test suite. If a golden diff is intentional
(e.g. you added an annotation that changes interpreted output), update
the goldens:

```
bash tools/golden-test.sh --update    # rewrite tests/golden/.../interpreted-*.md
# (the roundtrip script uses the same goldens via the mock — re-run
#  ./tools/tcl-smoketest.sh to confirm everything passes)
```

If you upgrade Xilinx QEMU, regenerate the register library:

```
python3 tools/regenerate-qemu-regs.py
./tools/tcl-smoketest.sh     # confirm nothing broke
```

If you add a new enumeration section, add it as `sectionN-NAME` after §12
(or insert at the correct position and renumber consistently across the
report, this manual, and `docs/README.md`).

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `FATAL: AXI mem-AP not reachable` at script start | A53 was released in prior run, cleanup didn't complete | Power-cycle (SW1 off 5 s / on) |
| Many `ERR` or `BLOCKED` in later sections | Cascading sticky errors from a bad address read | Likely script bug; capture full OpenOCD log and note which section first failed |
| Script hangs | OpenOCD waiting on AXI timeout from a probe of in-reset peripheral | Ctrl-C, power-cycle. The hung address needs gating |
| Report ends partway through | Tcl syntax error in script or helpers | Check stdout — OpenOCD logs Tcl errors above the partial report |
| Findings table values don't match raw register decode | Stale bit-extraction code in findings section | Re-run audit tool; if clean, check the findings interpretation logic for hardcoded bit positions |

For board-state recovery procedures (USB passthrough, power cycle,
etc.), see [`appendix-a-recovery.md`](appendix-a-recovery.md).

## See also

- [`04-jtag-research-techniques.md`](04-jtag-research-techniques.md) — passive AXI reads, A53 release recipe, the primitives the script builds on
- [`09-discover-tool.md`](09-discover-tool.md) — `discover.tcl`, the optional chain sanity check
- [`appendix-b-references.md`](appendix-b-references.md) — Xilinx documents to consult
- `tests/audit-report.md` — current state of the bit-layout audit
- `openocd/lib/zynqmp-regs-qemu.tcl` — the auto-generated register library (don't edit; regenerate)
