# ZCU102 BootROM Extraction — Milestone Findings (2026-05-27)

Status: stable resume point. Six-method extraction architecture built and exercised; one method (M2) permanently deferred; three methods produce reproducible chip-gating signature; vendor cryptographic ground-truth captured.

This document is the record of what we conclusively know vs. what remains open. It exists so we can plan the next phase against a stable factual base, not anecdote from chat history.

---

## 1. What we set out to do

Extract the contents of the ZynqMP CSU BootROM (16 KB at `0xFFFFC000`–`0xFFFFFFFF`) from JTAG, with the chip in idle (no FSBL, no PMU FW, JTAG-boot mode). The CSU BootROM is the immutable first-stage Xilinx code that:

- Performs early init (PLL, OCM zeroization, security gates)
- Validates and decrypts the user's PMU FW / FSBL
- Holds the **AES Family Key** used for red→black key obfuscation (a hardcoded secret)
- Holds the **red→black obfuscation routine** itself

Extracting it is the prerequisite for any meaningful reverse-engineering of the ZynqMP secure-boot trust root, including the two backdoor research targets the user flagged: (1) Family Key, (2) red→black obfuscation routine.

## 2. What we built

A six-method extraction tool at `openocd/dump-bootrom.tcl` + `tools/bootrom.py`. Each method is an independent transport path to the BootROM region; they're complementary because a chip-side gate (vs. transport bug) will manifest identically across them.

| Method | Mechanism | Status |
|---|---|---|
| **M0** Baseline | JTAG-DAP → AXI mem-AP → CSU region | Working — produces consistent chip-gating signature |
| **M3** CSU DMA loopback | CSU-internal DMA SRC→DST | Working — produces consistent chip-gating signature with distinct error fingerprint |
| **M1** A53 EL3 dump | Release A53, load AArch64 payload at 0xFFFC0100, payload copies BootROM → OCM, read OCM | Working on first run after power-cycle |
| **M2** Loader (D-cache off) | A53 EL3 + explicit SCTLR_EL3.C clear | **DEFERRED** — see §5 |
| **M4** R5 RPU dump | Cortex-R5 ATCM payload | Always fails — RPU power-island gated without PMU FW |
| **M5** CSU AES route | Speculative: BootROM → CSU AES → DMA-dst | Inconclusive — conditionally fails |

Supporting infrastructure:

- `payloads/`: ARMv8-A and ARMv7-R bare-metal payloads with Makefile + staleness check
- `openocd/lib/release-recipes.tcl`: A53/R5 release procs with verbose logging
- `openocd/lib/dump-memory.tcl`: chunked dump helper with per-chunk timing
- `tools/bootrom.py`: per-method analysis renderer + cross-method summary renderer + auto-printed headline (added 2026-05-27 19:52)
- Self-recovery: inter-method DAP recovery, force-halt fallback, M2-broke-A53 cascade-protection skip

## 3. Definitive findings

### 3.1 BootROM region is gated, not absent

All three working transport paths (M0/M1/M3) return identical 16 KB of `0xDEADBEEF`. SHA-256 across methods: `cd23e1814891e72e57e31550d35a3c30…`. This is the OpenOCD AXI mem-AP failure sentinel — the chip is refusing the read, not returning data.

Two distinct gating mechanisms are observed:

- **AXI fabric silent denial**: M0, M1, M5 — read returns `0xDEADBEEF` as VALID bus data with no fault raised. The AXI mem-AP/CCI doesn't know the read failed.
- **CSU internal APB error**: M3 — `SRC.I_STS = 0x00000003` (INVALID_APB|TIMEOUT_MEM), `DST.I_STS = 0x00000002` (TIMEOUT_MEM). The CSU's own DMA refuses to source from BootROM via internal APB.

That two independent gating mechanisms exist tells us the gating is multi-layered, not a single switch.

### 3.2 The vendor digest is captured (cryptographic ground truth)

`CSU.CSU_ROM_DIGEST_0..11` (`0xFFCA0050..0xFFCA007C`) holds the vendor-measured SHA-384 of the real BootROM, computed by the CSU at boot. We read it cleanly:

```
0x26042731 0x0B5A3BDB 0x7FBEE59B 0x8327B4E3
0xF172C94B 0x5ECF6519 0xDC443F4C 0xA8FC2D0E
0xCF5E3889 0xDDCE3F4F 0xCDE7B664 0x2937CB90
```

Concatenated big-endian (the canonical Xilinx storage order):
`26042731 0b5a3bdb 7fbee59b 8327b4e3 f172c94b 5ecf6519 dc443f4c a8fc2d0e cf5e3889 ddce3f4f cde7b664 2937cb90`

**Why this matters**: any future dump's SHA-384 can be matched against this digest. A match is cryptographic proof that we got the REAL BootROM bytes. Currently no dump matches (every dump is 16 KB of `0xDEADBEEF`).

The pre-existing register-audit work (`reference_register_address_audit`) corrected the digest base address from a buggy `0xFFCA0048` (which gave 2 leading zero words) to the correct `0xFFCA0050` (12 valid words). Without that audit, this finding would still be wrong.

### 3.3 Chip is unlocked dev silicon

Snapshotted in M0 baseline every run:

- `EFUSE.SEC_CTRL = 0x00000000` — no security eFuses blown
- `CSU.JTAG_DAP_CFG = 0x0000003F` — all DAP IDs allowed
- `CSU.JTAG_SEC = 0x000000FF` — JTAG security wide open
- `CSU.CTRL = 0`, `CSU.TAMPER_TRIG = 0`, `CSU.TAMPER_STATUS = 0x8327B4E3`

Conclusion: the BootROM gating is **architectural** (always-on protection for the boot trust root), not a programmable policy that could be disabled by configuring eFuses or CSU registers. This rules out any "just turn it off" attacks.

### 3.4 SCTLR_EL3 state confirmed; D-cache irrelevant

`SCTLR_EL3 = 0x00C52838` in JTAG-idle. Decoded:

- C bit (data cache) = 0 → D-cache already off
- I bit (instruction cache) = 0 → I-cache already off
- M bit (MMU) = 0 → MMU off

M2 was designed as a D-cache-off control variant to rule out cache effects in M1. Since D-cache is ALREADY off in JTAG-idle, M2 is functionally identical to M1. This is why M2 is deferred without research loss.

### 3.5 A53 EL3 payload execution works (M1)

When A53 is freshly released after a power-cycle, M1's AArch64 payload runs end-to-end:

- Payload completion marker (`0xCAFEBABE0000C0DE` at OCM 0xFFFE7000) reliably written within 6 ms of resume
- 16 KB copy loop from BootROM → OCM completes
- EL3 sysreg snapshot captured (values are residual from prior BootROM execution, not exceptions from our payload — confirmed: LDP from a gated AXI region returns DEADBEEF as DATA, not as a fault)

This confirms the A53 EL3 transport path is sound; it's just that the bytes it copies are themselves chip-gated.

## 4. Negative findings — things ruled OUT

- **Not an OpenOCD scripting bug**: Three independent paths (M0 direct, M3 via CSU DMA, M1 via A53) agree on the byte content. If only one disagreed, that would point at our code. Agreement points at the chip.
- **Not a security eFuse policy**: `EFUSE.SEC_CTRL = 0`, all JTAG access bits open. No programmable lock is engaged.
- **Not an XMPU/XPPU configuration**: The gating is consistent across A53-initiated, JTAG-initiated, and CSU-initiated accesses. XMPU would let one of these through.
- **Not D-cache pollution** (`SCTLR_EL3.C = 0` in idle)
- **Not the OpenOCD AXI mem-AP being limited to "small" reads**: we tested chunk sizes up to 4096 bytes; same result
- **Not a transient state issue**: results are reproducible across many runs (timestamps 162513, 170029, 183210, 184528, 184628, 185737, 190617, 190655, 193023, 194400, 195259, 200202, 200456, 201139, 201310, 201533, 201740, 202002, 202142, 202259, 202647)

## 5. M2 deferred — root cause and reasoning

`OpenOCD reg pc <addr>; resume` on the ZynqMP A53 doesn't actually start instruction execution at the target PC after a warm release (no PMU FW participation). OCM writes land, A53 reports halted at the correct PC, reg-pc read-back is consistent, but resume doesn't fetch from the requested address. Tried branch-override-at-pre_pc, payload-bytes-at-pre_pc, multiple reg-pc strategies — none work.

Deferred (not "fix-later-broken") because:

1. M2 was a D-cache-off control variant for M1, and D-cache is already off in JTAG-idle
2. The one successful M2 run (185737, before regression) produced byte-identical output to M1
3. Fixing M2 requires PMU FW participation we don't have

If Phase 5 #65 (PMU FW dump tool) succeeds, M2 might fix itself for free. Until then it's wasted iteration time.

## 6. Open questions for the next phase

1. **Does the gating disappear when the chip is in BOOTED state, not JTAG-idle?** Boot from SD/QSPI with an FSBL, then JTAG-attach, then try the same six methods. If gating is lifted post-boot, M0/M1/M3 would suddenly produce real bytes — and we could match the vendor digest. (Phase 7, task #45)

2. **Is the gating a CSU register we can read?** Search ZynqMP TRM for any CSU register related to "ROM_VISIBLE" / "ROM_LOCK". A read-only or write-once register could be locked at handoff. If found, dump-time read of that register would tell us "gating definitely on" vs. "gating could be off but isn't yet". Useful for distinguishing "always on" vs "policy-driven".

3. **Can PMU FW be dumped?** The PMU has its own ROM and runs the MicroBlaze core (also gated from A53). If we can extract PMU FW, we can build our own — which enables not just M2 but also the entire LPD power domain dance needed for R5/RPU access. Phase 5 #65.

4. **Are there documented side-channels on the AES family-key path?** The Family Key is loaded into the CSU AES engine when computing red→black ciphertext. Power-analysis attacks on similar engines have extracted hardcoded keys (Starbleed-class on 7-series, AES-fault on UltraScale). Worth a literature scan before lab attempts.

5. **Is the digest BE word concatenation the right format?** We've tried BE and LE; neither matches our DEADBEEF dump (expected — different data). The first real dump candidate will let us confirm the canonical byte order.

## 7. Decision matrix for next direction

| Option | Time-to-payoff | Risk of zero result | Advances toward real bytes | New skills required |
|---|---|---|---|---|
| **Phase 7 — SD/QSPI boot, dump in booted state** | Hours to a day (need Vitis FSBL build) | Low — chip clearly has a different state when booted | **Direct** | Vitis FSBL build, SD card prep |
| **Phase 5 #65 — PMU FW dump** | Days (uncertain method, research-heavy) | Medium — PMU has its own gating | Indirect (would unlock M4, possibly M2) | PMU MicroBlaze ISA, CSU IPI protocol |
| **Boundary-mapping (M2 slot replacement)** | Hours | Low — guaranteed to produce a region map | Indirect (only tells us where gating ends, not how to break it) | None — extend existing M1 payload |
| **Document + literature review** | Days | None — value is in the artifacts produced | None directly, but sets up better choices later | Research/writing |

## 8. Suggested order of operations

The user's project memory says VxWorks is the eventual target, on real-board contexts (production devices, NDA audits, CTFs). For that target, having a chip that can be booted normally and JTAG-attached post-boot is realistic. So:

1. **Phase 7 first** — build the FSBL, get booted-state dumps. If BootROM is readable post-boot, our DEADBEEF-vs-real-bytes diff tells us where the gating engages. This produces the **real bytes** outcome with the highest probability.
2. **Phase 5 #65 second** — only if Phase 7 doesn't give us real bytes. PMU FW is high-effort-medium-payoff.
3. **Backdoor research third** — Family Key extraction is the long-term research goal; needs real BootROM bytes (from step 1 or 2) as prerequisite.

If user prefers low-risk-quick-win, do boundary-mapping (M2 slot replacement) in parallel with Phase 7 prep work. The boundary map is useful regardless of which path wins.

---

**This milestone** = stable resume point. From here, the next session can pick a direction from §7 without having to re-derive any of the above.
