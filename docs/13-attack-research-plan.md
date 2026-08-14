# Offensive Research Plan — BootROM dump & family/gray-key extraction

The two hard targets, the candidate primitives for each, and what it takes to
attempt them. Grounded in `docs/12-secureboot-internals.md` (the cited
secure-boot reference) and the project's validated JTAG primitives. Non-destructive
(no eFuse burns) unless explicitly escalated.

## The targets

1. **Dump the CSU BootROM** — the 128 KB ROM internal to the CSU Security
   Processor Block. **Not AXI-mapped** (confirmed): no address reads it; `0xFFFC0000`
   is OCM/FSBL. So a memory read is out — we need code-exec-on-CSU, a routing/DMA
   leak, a debug path into the CSU, or a fault primitive.
2. **Extract the family / gray key** — the family key is baked into the device
   metal layers (family-wide, AMD-only) and its *value* is unreadable by design.
   "Extraction" therefore means either (a) an **oracle**: abuse the CSU's
   obfuscated-key decrypt path to recover red keys from arbitrary gray keys without
   learning the family key; or (b) the **value** via side-channel (DPA) / fault.

## What we already have (assets)

- DAP-NS direct access to the CSU register space (AES/SHA/PUF/control) — proven.
- A53-EL3 code execution (reset-release recipe); R5 wake+execute (different bus
  master); A53→PMU PM-API over IPI (Phase 7).
- This board's **FSBL binary + disassembly** (`dumps/fsbl-freshboot.disasm`) — the
  legitimate CSU/eFuse register sequences (JTAG-config routine, eFuse-policy read,
  CSU init); crypto-engine code is compiled in but dormant (secure boot off here).

## Known walls (from prior work + the research)

- PMU TAP eFuse-gated (`SSSS_PMU_SEC`); PMU ROM (`0xFFD00000`) eFuse-locked.
- CSU DMA SRC.ADDR write **rejected from A53-EL3 SECURE**; DAP-NS *can* program CSU
  DMA (asymmetric trust) — but only to copy *addressable* memory (ROM isn't).
- "Only the CSU BootROM can unlock the device key" (AMD) — the family/obfuscated
  decrypt is a CSU-BootROM-internal step, not a runtime AES `KEY_SRC` in normal use.

---

## Target 1 — CSU BootROM dump: candidate vectors

| # | Vector | Idea | Tier |
|---|---|---|---|
| 1.1 | **SSS routing leak** | Can the CSU Secure Stream Switch (`CSU_SSS_CFG 0xFFCA0008`) route a source that aliases/exposes ROM into a DMA/SHA sink we can read? Map every source-select code. | **1 (JTAG now)** |
| 1.2 | **CSU DMA source sweep** | Program CSU DMA (via DAP-NS, which is permitted) with source addresses across candidate ROM apertures; see if any returns non-OCM/non-fill data. | **1** |
| 1.3 | **Reserved CSU register sweep** | Walk undocumented CSU control-page offsets for a register that returns ROM words or a "dump ROM" command. | **1** |
| 1.4 | **CSU / PMU processor debug** | Find a debug/halt path into the CSU (or PMU MicroBlaze) to read its instruction memory. PMU TAP eFuse-gated here; re-probe CSU debug + `JTAG_SEC` magic. | **1–2** |
| 1.5 | **SHA pass-through** | Feed ROM through the SHA engine — yields only a hash, not bytes. | low value |
| 1.6 | **Boot-time fault/glitch** | Glitch the CSU during the ROM-protected phase to expose/skip the hide. | **3 (glitcher)** |

## Target 2 — family / gray key: candidate vectors

| # | Vector | Idea | Tier |
|---|---|---|---|
| 2.1 | **AES `KEY_SRC` runtime probe** | Map which `AES_KEY_SRC (0xFFCA1004)` values the engine accepts at runtime — is an obfuscated/family or device-key source selectable outside BootROM? If so, an oracle may be reachable without SD boot. | **1 (JTAG now)** |
| 2.2 | **Family-key decrypt oracle (gray-boot)** | Craft an obfuscated-key (gray) boot image; let the BootROM decrypt a *chosen* gray key with the family key → load red key → use the AES engine to decrypt/encrypt known data = an oracle that breaks any gray key. | **2 (SD-boot infra)** |
| 2.3 | **DPA side-channel** | Power analysis on the CSU AES while it uses the family key — the canonical, proven method for hardware AES keys. Recovers the *value*. | **3 (ChipWhisperer/scope)** |
| 2.4 | **Fault injection** | Glitch the obfuscated-key decrypt to leak intermediate state. | **3 (glitcher)** |

---

## Feasibility tiers

- **Tier 1 — JTAG, non-destructive, now.** Vectors 1.1–1.4, 2.1. Map the CSU
  command / SSS / DMA / AES-`KEY_SRC` surface for a leak or oracle opening. Costs
  nothing; either finds a crack or cleanly bounds the walls. **← start here.**
- **Tier 2 — needs SD-boot infra.** Vector 2.2 (gray-boot oracle). Requires building
  a bootable SD image (Vitis/bootgen) — see `project_phase7_prep`.
- **Tier 3 — needs side-channel/fault hardware.** Vectors 1.6, 2.3, 2.4. For the
  family-key *value*, this is the path with real academic precedent; pure JTAG
  likely cannot get the value, only (maybe) an oracle. **Requires a ChipWhisperer /
  glitch + power-analysis rig — a hardware-budget decision.**

## Honest assessment

These are genuinely hard, novel targets — no public ZynqMP *CSU* BootROM dump exists
to our knowledge, and the family key is engineered to resist software extraction. A
real primitive here would be disclosure-worthy (unlike the retracted dev-board
findings). Expect Tier 1 to most likely **bound the walls** (confirm internal/locked)
and surface, at best, an oracle lead; the strongest family-key path (DPA) needs hardware.

## Tier-1 probe (this iteration)

`openocd/probe-csu-surface.tcl` — non-destructive characterization:
- Read-map the CSU control page, AES/SHA/PUF engine regs, and CSU-DMA channels.
- Characterize `CSU_SSS_CFG` source-select semantics (write field values, read back
  which latch; restore) → vector 1.1.
- Characterize `AES_KEY_SRC` accepted values (write + read back; restore) → vector 2.1.
- Sweep reserved CSU control-page offsets for non-zero/undocumented behavior → 1.3.
- Emits a report to `reports/`; raw values shown (no summaries).

Output feeds the decision: which Tier-1 vector (if any) has an opening worth a
follow-up driver probe, vs. escalate to Tier 2/3.

### Tier-1 probe — CSU-DMA "alternate bus master" ROM read

`openocd/probe-csu-dma-rom.tcl` — non-destructive test of the one remaining
JTAG-reachable dump surface. The DAP cannot read the on-chip ROMs (CSU BootROM
not AXI-mapped; PMU ROM `0xFFD00000` blocked by a master-aware AXI filter). The
**CSUDMA** engine is a *different* AXI master. The probe drives a CSUDMA
mem-to-mem copy (SSS DMA-loopback, `SSS_CFG=0x50`) from a ROM region into OCM,
then reads OCM back over the DAP:
- §1 baseline OCM→OCM copy (proves CSUDMA works from JTAG-NS + calibrates the
  SIZE encoding `(nwords<<2)|last`) — must PASS before ROM results are trusted.
- §2 the real experiment: PMU ROM `0xFFD00000` via CSUDMA vs via the DAP. A hit
  = CSUDMA reached a ROM the DAP can't (a finding); all-zero/timeout = the filter
  also covers CSUDMA (the expected negative).
- §3 speculative ROM-alias candidates (labelled low-confidence).

Honest odds: LOW — the ROM almost certainly isn't on the CSUDMA source map
either. This probe exists to *exhaust* the non-destructive surface and record the
result, not because a hit is expected. Register layout traced to `csudma.h`
(pmufw) + `xsecure_sss.c/.h` (xilsecure).

**RESULT (ran 2026-06-08, board 210308BD8D4D) — NEGATIVE, surface exhausted.**
§1 baseline PASSed (CSUDMA OCM→OCM works from JTAG — a confirmed mem-to-mem
primitive). §2: DAP-direct PMU-ROM read = SLVERR; CSUDMA copy of `0xFFD00000`→OCM
returned `done` but **all-zeros** → CSUDMA cannot read the PMU ROM either; the
master-aware AXI filter covers the CSU DMA master. §3 aliases timed-out/blocked.
The ROM is unreachable from JTAG via any master we can drive — empirically
confirms `project-bootrom-dumpability-resolved` from a new angle.

## References
- `docs/12-secureboot-internals.md` — BootROM/key/PUF/bootgen ground truth.
- `docs/11-enumerated-attributes.md` — live register map.
- memory: `project-bootrom-dumpability-resolved`, `project-mission`, `project-phase7-prep`.
