# 23 — Multi-Board Engagement Runbook

**What this is.** You've walked up to a board you may or may not recognize, on an offline laptop, and
you need to take it from *cables* to *flash/RAM in hand*. This is the operational sequence. It drives the
**`tools/board-runner.py`** engine (the fixed state machine) and the per-paradigm scripts.

**How it relates to the other docs:**
- **`docs/21`** — the ZCU102 deep walkthrough: one board, every capability, fully worked. Read it once to
  understand what a capability *is*.
- **`docs/22`** — the capability matrix: *which* paradigm a board is, *what* it can yield, *what* blocks
  you. The planning/scope card. Read it to set expectations before you connect.
- **`docs/23`** (this) — the *do-this-then-that* runbook that ties them together for an arbitrary board.

**The whole loop in one line:**
```
connect ──> identify ──> board-runner (emit a plan) ──> run the plan ([LIVE]/[OFFLINE]/[VENDOR]) ──> analyze
```

The runner never invents chip knowledge: it LOOKS UP a profile (`profiles/*.json`) when it recognizes the
chip, FALLS BACK to probe-based generic capabilities when it doesn't, and STOPS-and-reports when there's
nothing it can safely do. Every step it emits is tagged **[LIVE]** (you run it on the board), **[OFFLINE]**
(safe to run now, no board), or **[VENDOR]** (needs a vendor tool, e.g. FlashPro).

---

## Phase 0 — Physical first contact

Goal: a stable JTAG/SWD chain and the IDCODEs. Software can't sweep past a physical fault — get this right
first. (Full detail: `docs/18-new-board-bringup.md`.)

1. **Wire + power.** Adapter to the JTAG/SWD header; confirm Vref/voltage (ZynqMP PS-JTAG = 1.8 V; many
   MCUs = 3.3 V), GND, and that JTAG is actually exposed (a **Raspberry Pi needs `enable_jtag_gpio=1`**;
   an MCU may be SWD-only).
2. **Auto first-contact (preferred):**
   ```bash
   tools/probe-board.sh                      # adapter -> speed-ladder chain scan -> IDCODE decode -> verdict
   ```
   It STOPS at the first failed gate (NO-CHAIN / not-ZynqMP-cfg / not-OPEN) and is strictly read-only.
   *(probe-board emits a ZynqMP cfg only; for other SoCs you use the cfg the runner names — see Phase 1.)*
3. **Or manual:** pick an adapter stanza and scan the chain, capturing the log:
   ```bash
   JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
     openocd -f openocd/board-template.cfg \
       -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee firstcontact.log
   ```
   The IDCODEs appear as `tap/device found: 0x...` lines (init succeeds) or `unexpected idcode` (chain
   mismatch). Either way they're in the log.

You now have **either a log** (`firstcontact.log`) **or the IDCODEs** typed off the screen.

---

## Phase 1 — Identify & get a plan (`board-runner`)

Two entry paths. Use whichever fits what Phase 0 gave you.

### Path A — auto-fingerprint (the board has a recognizable chain)
```bash
python3 tools/board-runner.py --from-log firstcontact.log        # parse IDCODEs out of the log
# or, typing them directly:
python3 tools/board-runner.py --idcodes 0x24738093 0x5ba00477
```
The runner decodes the chain and picks a **tier**:

| Tier | When | What the plan gives you |
|---|---|---|
| **1** | a profile matches the fingerprint | the full capability set for that chip |
| **2** | no profile, but an ARM DAP is present | generic: access verdict + DRAM dump + analysis + virt2phys patch |
| **3** | FPGA TAP / no usable AP | identify + `[VENDOR]` handoff, no memory |

### Path B — operator-asserted (the board can't be fingerprinted)
A **Raspberry Pi**, an **MCU on SWD**, and **IGLOO2** all present only a generic TAP — you can't tell them
apart by IDCODE. If you *know* what it is (silkscreen / BOM), assert it:
```bash
python3 tools/board-runner.py --list                  # see selectable profiles
python3 tools/board-runner.py --profile bcm           # Raspberry Pi
python3 tools/board-runner.py --profile stm32f4       # STM32F4 MCU
python3 tools/board-runner.py --profile igloo2        # IGLOO2 FPGA -> FlashPro handoff
```

Either path prints a numbered plan. Optionally save a machine copy: `--out-json reports/plan.json`.

---

## Phase 2 — Run the plan

Walk the numbered steps. The tag tells you who runs it:

- **[OFFLINE]** — run now, no board (analysis, Ghidra settings). Safe.
- **[LIVE]** — you run this `openocd …` against the board. **The operator drives all live JTAG** — the
  runner plans, it does not touch silicon.
- **[VENDOR]** — switch to the vendor tool (FlashPro Express / Libero for IGLOO2).

The universal branch inside every [LIVE] sequence:
```
access verdict ──OPEN──> dump (flash + RAM)
       │
       └──LOCKED──> run the reopen lever ──> re-check the verdict
                     still locked (eFuse/OTP) ──> "identified, locked, no capability" (a real result)
```
- **OPEN** is the green light. Proceed to enumerate/dump.
- **LOCKED but mutable** (software-hardened, no blown eFuses) — the reopen lever re-opens it (ZynqMP
  `reopen-debug.tcl`, Zynq-7000 `devcfg.CTRL |= 0x7F`). Re-run the verdict.
- **LOCKED and fused** — the lever's write-back is ignored. That's the access controls doing their job;
  document it and move on. Don't force it.

---

## Phase 3 — Offline analysis (always safe)

Once you have a dump, the [OFFLINE] steps the plan listed:
```bash
python3 tools/dump-triage.py   dumps/<image>.bin               # FIRST LOOK: what IS this? entropy map +
                                                               #   filesystems / boot-images / certs / compression
python3 tools/dram-secrets.py  dumps/os-live.bin --base 0x0    # keys, creds, certs, tokens, AES schedules
python3 tools/ghidra-loadspec.py dumps/<image>.bin             # exact Ghidra Language + Base (any ISA)
```
**Run `dump-triage.py` first** — it tells you whether you're looking at plaintext code (disassemble),
an encrypted/compressed blob (the secure-boot path engaged), a packed filesystem (carve with `binwalk`),
or mostly-blank over-read. That decides which of the next tools is even worth running.
Plus, **only when applicable**:
- `parse-bootimage.py` — **ZynqMP bootgen images only** (it would misread a Zynq-7000 image despite the
  shared header magic — the runner deliberately omits it from non-ZynqMP profiles).
- `vxworks-symtab.py` / `symbol-crypto.py` — when the image is VxWorks (see `docs/21`).

Then load the image into Ghidra with the language/base `ghidra-loadspec` printed, and reverse as usual.

---

## Worked examples (one per paradigm)

**Cortex-A, auto-fingerprinted — ZynqMP (the reference):**
```bash
python3 tools/board-runner.py --from-log tests/fixtures/zcu102-firstcontact.log
# -> TIER 1 Zynq UltraScale+; plan: verdict -> reopen? -> enumerate -> DRAM dump -> QSPI dump -> analyze -> patch
```

**Cortex-A, partial profile — Zynq-7000:**
```bash
python3 tools/board-runner.py --idcodes 0x13727093 0x4ba00477
# -> TIER 1 Zynq-7000 (partial): posture (devcfg.CTRL/LOCK) -> DRAM dump -> LQSPI flash dump -> reopen lever
```

**Cortex-A, operator-asserted — Raspberry Pi:**
```bash
python3 tools/board-runner.py --profile bcm
# -> DRAM dump + dram-secrets + Ghidra + Linux virt2phys patch. (No flash/posture: VideoCore owns those.)
```

**Cortex-M MCU — STM32 / nRF52 / RP2040:**
```bash
python3 tools/board-runner.py --profile stm32f4
# -> readout-protection check (RDP) -> internal flash + SRAM dump -> dram-secrets -> Ghidra (Thumb) -> SRAM patch
```

**FPGA, no CPU — IGLOO2:**
```bash
python3 tools/board-runner.py --profile igloo2
# -> identify + [VENDOR] FlashPro Express runbook. No memory bus over JTAG; readback only if unprovisioned.
```

---

## When the board is unknown (Tier 2 / Tier 3)

A no-profile board is the *expected* case, not a failure:

- **Tier 2 (an ARM DAP responded).** The plan runs the **probe-based** capabilities — they don't need a
  profile because they probe instead of look up: access verdict → walk the address space for DRAM → dump
  what's there → analyze → generic virt2phys patch. **If the mem-AP probe finds no DRAM, it's likely a
  Cortex-M MCU** (Paradigm B): re-run with `--profile <the MCU>` to read its internal flash instead.
- **Tier 3 (FPGA TAP / no usable AP).** Identify, record the IDCODE/chain/verdict, hand off to the vendor
  tool. That's the honest ceiling for that target.

**Promoting an unknown to a profile (Tier 2 → Tier 1).** If you'll see this chip again, write one data
file — `profiles/<soc>.json` per `profiles/_schema.md` — and it becomes a full Tier-1 target. **No engine
change.** Validate it offline before trusting it:
```bash
python3 tools/board-runner.py --validate          # schema + referenced-path check (also in tcl-smoketest.sh)
```

---

## Honest limits (read before you over-promise in a report)

- **Profiles other than ZynqMP are HW-unvalidated.** The addresses/logic are sourced and cited (Zynq-7000
  from UG585; MCU registers from vendor docs), but nothing but the ZCU102 has touched real silicon. Treat
  a first run on new silicon as a bring-up, not a guarantee — confirm the access verdict + a sanity read
  before the bulk dump.
- **Locked is a result.** A fused-off DAP, RDP level 2, enabled APPROTECT, or a provisioned FlashPro key
  means *no dump* — and that's a finding, not a tooling failure.
- **The reopen levers only work on software-hardened, no-eFuse targets.** If the lock is in eFuse/OTP, the
  register write-back is ignored (the read-back diagnoses which case you're in).
- **MCU "unlock" is destructive.** STM32 RDP-1 / nRF APPROTECT only clear via a **mass-erase** that wipes
  the flash you wanted. There is no non-destructive reopen for those — the runner does not offer one.
- **IGLOO2 and other FPGA TAPs have no memory bus.** Best case is identify + (maybe) bitstream/eNVM
  readback via the vendor tool, only if security isn't provisioned.

---

## Pre-stage checklist (offline laptop)

See **`docs/22` → "Pre-stage checklist"** for the full list: OpenOCD with the needed targets, the register
KBs, both ARM cross-toolchains, Ghidra + loaders, the vendor tools (FlashPro for IGLOO2), our offline
analyzers, and the USB-reset recovery path. Assume zero network at the site.
