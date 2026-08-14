# 20 — BootROM Boot-Header Fuzzing (the checkm8-model ROM-dump path)

A black-box fuzzing harness for the ZynqMP **CSU BootROM's boot-image parser** — the only
non-destructive, JTAG-observable avenue left to extract the 128 KB CSU BootROM after every
*direct* read path was empirically closed (AXI, CSUDMA, R5, PMU-BSCAN; see `docs/12`,
`project_bootrom_dumpability_resolved`, `project_pmu_bscan_tap_attempt`).

## The idea (don't read it — exploit it into dumping itself)

The CSU BootROM runs on the CSU security processor — the **one agent that can read the CSU ROM**
(it's on that processor's private instruction bus). That processor also **parses attacker-supplied
input**: the boot image off the SD/QSPI device, which we fully control. If a length/offset/count/
pointer field drives a copy or pointer **without bounds-checking**, a malformed boot image could
corrupt the BootROM's memory and yield a copy/exec primitive *in the CSU context* → coerce it into
copying the ROM to **OCM (`0xFFFC0000`, which IS JTAG-readable)** → dump it via JTAG.

This is the **checkm8 model** (Apple SecureROM was dumped via a bootrom USB-parser bug, no
glitching). It fits every constraint: non-destructive, no fault injection, JTAG-only observation.

**Honest odds: low.** There is no public ZynqMP BootROM RCE (CVE-2023-20570/JustSTART proves the
BootROM has exploitable *logic* bugs, but it's an auth bypass, not code-exec). A memory-safety bug
may not exist or may be hardened. This is original research — but it's the *right* methodology, and
the result is clean either way (a crash signature is a finding; silence rules the field out).

## Why fuzzing breaks the chicken-and-egg

"You need the ROM to find a bug in the ROM" — no: **black-box** it. Malform a boot-image field,
flash, boot, and watch the BootROM's reaction *over JTAG*. Crashes and anomalous control flow are
observable without the ROM bytes (`FT_STATUS`, `MULTI_BOOT`, OCM content, DAP state). `ROM_DIGEST`
+ behavioral probing also lets you reverse the parser logic without the binary.

## The harness (3 parts)

| Tool | Role |
|------|------|
| `tools/bootrom-fuzz-gen.py` | Generate a **curated** corpus of malformed images from a valid base BOOT.bin. Targets the bug-prone fields (BH `fsblLength`/`totalFsblLength`/`fsblExecAddress`/`sourceOffset`; IHT `partitionTotalCount`/offsets; PHT `*PartitionLength`/`destinationLoadAddress`/`destinationExecAddress`/`nextPartitionHeaderOffset`/`dataSectionCount`) with overflow/wrap/zero/pointer-into-CSU values. **Recomputes the bootgen word-checksum** so the field is actually *consumed* (`--cksum-test` also emits broken-checksum variants to probe enforcement). Writes `0000-baseline.bin` + `NNNN-*.bin` + `manifest.json`. |
| `openocd/bootrom-fuzz-observe.tcl` | After a boot, capture the **reaction fingerprint** (read-only via AXI-AP): `CSU_STATUS`, `MULTI_BOOT`, `FT_STATUS`, `BOOT_MODE`, a 32 KB OCM window sum + sample words, DAP responsiveness → one `FUZZ_FP` line, appended to `reports/bootrom-fuzz.log`. |
| `tools/bootrom-fuzz-triage.py` | Diff every trial vs the `id=0` baseline, classify + rank: **JACKPOT** (OCM changed + CSU fault/wedge), **HIGH** (FT_STATUS/DAP/OCM), **INFO** (MULTIBOOT changed = field validated/rejected cleanly), normal. Joins `manifest.json` for field labels + hypotheses. |

## The campaign loop (operator-driven — flashing is hands-on)

```bash
# 0a. Build a MINIMAL FSBL-only base (~150 KB) so the corpus is ~9 MB and each image flashes in
#     seconds (a full PetaLinux BOOT.bin makes 64 mutants = ~548 MB and minutes-per-flash):
python3 tools/make-fuzz-base.py            # -> dumps/fuzz-base-min.bin (valid 1-partition image)
# 0b. Generate the corpus from it:
python3 tools/bootrom-fuzz-gen.py dumps/fuzz-base-min.bin -o fuzz-corpus/

# 1. Record the BASELINE: flash 0000-baseline.bin, SW6=SD/QSPI, power-cycle, then:
openocd -f openocd/zcu102.cfg -c "init; set ::FUZZ_ID 0; source openocd/bootrom-fuzz-observe.tcl; shutdown"

# 2. For each NNNN-*.bin: flash -> power-cycle -> observe with set ::FUZZ_ID <NNNN>
#    (all FUZZ_FP lines accumulate in reports/bootrom-fuzz.log)

# 3. Triage:
python3 tools/bootrom-fuzz-triage.py reports/bootrom-fuzz.log fuzz-corpus/manifest.json
```

Because flashing is manual, the corpus is **curated and prioritized** (~30–60 high-value mutants),
not millions of random cases. Start with the PHT `destinationLoadAddress` and BH `fsblLength`
rows — they drive the actual copies.

## What the signals mean / what success looks like

- **MULTIBOOT incremented** → the BootROM caught the bad field and searched for a golden image:
  the field *is* validated (a clean reject — lower interest, but maps which fields are checked).
- **FT_STATUS changed / DAP wedge** → the CSU may have **crashed** mid-parse (HIGH — a memory-safety
  bug candidate).
- **OCM content changed unexpectedly** → an attacker-influenced copy landed at `0xFFFC0000`. If this
  coincides with a fault, that's the **JACKPOT**: re-flash, full-dump OCM
  (`dump-memory 0xFFFC0000 0x20000`), and check it for ROM content — **a SHA-3-384 over a
  128 KB-aligned region matching `ROM_DIGEST` (0xFFCA0050) is the win.**

## Hardened-board note
On a provisioned board the BootROM enforces RSA/auth on the image before deep parsing, shrinking
the reachable surface — but the *structural* header parse (BH/IHT) happens early and may still be
reachable. The harness reports cleanly either way; a board that rejects every mutant at MULTIBOOT
with no FT/DAP/OCM movement is itself a (negative) characterization result.
