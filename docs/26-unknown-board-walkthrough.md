# 26 — Unknown-Board Walkthrough (connect → identify → own)

A hand-holding, command-by-command walkthrough for an engagement board you **don't recognize** — the
multi-board analog of `docs/21` (which walks the known ZCU102 in the same detail). Every step shows the
exact command, the **expected output**, and **what to do when it fails**. The terse reference version is
`docs/23`; the *what-can-this-board-yield* planning card is `docs/22`.

**The arc:** physical contact → a stable JTAG chain → identify the silicon → get a tiered plan → run it.
You never guess: the engine looks up a profile when it recognizes the chip, falls back to probe-based
generic capabilities when it doesn't, and stops-and-reports when there's nothing safe to do.

**Before you start (offline laptop):** OpenOCD with the targets you might meet, the register KBs, both ARM
toolchains, Ghidra, the vendor tools (FlashPro for IGLOO2), and our analyzers — see `docs/22` → pre-stage
checklist. Assume zero network at the site.

---

## Step 0 — Physical hookup

1. Find the JTAG/SWD header (20-pin ARM, 10-pin Cortex, or loose pads). Identify TCK/TMS/TDI/TDO/TRST (JTAG)
   or SWCLK/SWDIO (SWD), GND, and **Vref**.
2. **Match the I/O voltage** off Vref (ZynqMP PS-JTAG = 1.8 V; most MCUs 3.3 V; some 1.2 V). A level mismatch
   reads garbage or nothing. Use an adapter with Vref sensing or a level shifter.
3. Power the board from its own supply; share GND with the adapter.
4. **A Raspberry Pi needs JTAG enabled** (`enable_jtag_gpio=1` in `config.txt`) and the alt-function pins
   wired — it's off by default. An MCU may be **SWD-only** (2-wire).

> Failure here is physical and software can't fix it — wrong voltage, pinout, or a dead wire ⇒ Step 1 sees
> nothing. Re-check the header pinout against the board's schematic before blaming the tooling.

---

## Step 1 — First contact: scan the chain at the lowest working speed

The goal is the **IDCODEs** — the chain's fingerprint. Let the operator-launched, read-only probe do it:

```bash
tools/probe-board.sh 2>&1 | tee firstcontact.log
```

**Expected (success):**
```
 Stage 1 — chain scan (find IDCODEs at the lowest working speed)
 >> init at 200 kHz ...
    IDCODEs seen: 0x14738093 0x5ba00477
```
…or, doing it by hand with an explicit adapter + a slow clock:
```bash
JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
  openocd -f openocd/board-template.cfg \
    -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee firstcontact.log
# -> Info : JTAG tap: ... tap/device found: 0x14738093 (mfr: 0x049 (Xilinx), part: 0x4738 ...)
```

**Failure modes:**
| Symptom | Cause | Fix |
|---|---|---|
| `NO-CHAIN` / no IDCODEs at any speed | physical (Vref, pinout, GND, dead lead, JTAG fused off) | re-check Step 0; software can't sweep past it |
| IDCODEs only at very low speed | long/ribbon leads | keep the low speed for now; raise later once stable |
| `unexpected idcode` errors | chain length / extra TAP (a CPLD) | capture the raw IDCODEs anyway — Step 2 still decodes them |
| All-`0x00000000` or all-`0xFFFFFFFF` | TDO floating / not driven | wiring; check TDO and Vref |

You now have **`firstcontact.log`** (or the IDCODEs off the screen).

---

## Step 2 — Identify the silicon and get a plan

Feed the log to the engine. It decodes the chain, picks a **tier**, and prints an ordered plan.

```bash
python3 tools/board-runner.py --from-log firstcontact.log
```

**Expected (a recognized chip — real ZCU102 example):**
```
 Chain fingerprint:
   0x5ba00477  arm      Arm CoreSight DAP (part 0xba00)
   0x24738093  zynqmp   Xilinx ZynqMP/RFSoC (part 0x4738, rev 2)

 TIER 1: Zynq UltraScale+ (ZynqMP)   [Paradigm A]
   why: exact profile match (zynqmp.json)

 PLAN (run [LIVE] yourself; [OFFLINE] is safe now; [VENDOR] needs a vendor tool):
    1. [LIVE]    Access verdict ...
    2. [LIVE]    Reopen debug (if LOCKED) ...
    3. [LIVE]    Enumerate security posture ...
    ...
```

**The three tiers — what each means for you:**
| Tier | When | Plan gives you |
|---|---|---|
| **1** | a profile matched the fingerprint | the full capability set for that chip |
| **2** | no profile, but an ARM DAP responded | generic: verdict + DRAM dump + analysis + virt2phys patch |
| **3** | FPGA TAP / no usable AP | identify + `[VENDOR]` handoff, no memory |

**The board can't be fingerprinted?** A **Raspberry Pi**, any **MCU on SWD**, and **IGLOO2** present only a
generic TAP. If you *know* what it is (silkscreen/BOM), assert it:
```bash
python3 tools/board-runner.py --list                 # what's selectable
python3 tools/board-runner.py --profile stm32f4      # an STM32F4
python3 tools/board-runner.py --profile bcm          # a Raspberry Pi
python3 tools/board-runner.py --profile igloo2       # IGLOO2 -> FlashPro handoff
```

**Failure modes:**
| Symptom | Meaning | Next |
|---|---|---|
| `TIER 2 … unknown Paradigm-A/B board` | chip not in the registry | run the generic plan; if the DRAM probe finds nothing it's likely an MCU → `--profile <mcu>` |
| `TIER 3 … [VENDOR]` | FPGA programming TAP (no CPU) | hand off to FlashPro/Diamond; that's the honest ceiling |
| only the Arm DAP `0x4ba00477` decoded | shared DAP IDCODE (ZynqMP/Zynq-7000/Pi all share it) | you *must* assert with `--profile`, or use the full chain to disambiguate |
| wrong/garbled IDCODE | Step 1 was unstable | re-scan slower |

---

## Step 3 — Is the DAP actually open?

Run the verdict step the plan printed (you run all `[LIVE]` steps):
```bash
openocd -f <cfg> -c "init; source openocd/jtag-access-check.tcl; shutdown"
# -> ACCESS VERDICT: OPEN
```
- **OPEN** → green light, continue.
- **LOCKED but mutable** (software-hardened, no eFuses) → run the profile's reopen lever, then re-check:
  ```bash
  openocd -f <cfg> -c "init; source openocd/reopen-debug.tcl; shutdown"   # ZynqMP
  # Zynq-7000: zynq7000-reopen-debug.tcl  (writes devcfg.CTRL |= 0x7F)
  ```
- **LOCKED and fused** (eFuse/OTP, or an MCU RDP-2/APPROTECT) → the write-back is ignored. **That's a result,
  not a failure** — document it and move on. For an MCU the only "unlock" is a flash-WIPING mass-erase.

---

## Step 4 — Enumerate the security posture

Read the chip's security surface (the plan's "Enumerate" step). Output is sectioned OFF/dev → ON/provisioned.

**Example — Zynq-7000 (real decode shape):**
```
 (1) IDENTITY     PSS_IDCODE: Zynq-7000 device=7z020  Silicon 2.0
 (3) SECURE BOOT  SEC_EN: no · eFuse SECURE_EN/JTAG_DIS: not blown · lockdown clear
 (4) DEBUG/DAP    DAP_EN: ENABLED(111) · DBGEN/SPIDEN: enabled · DBG-lock: open
 VERDICT: ALL-OPEN dev baseline
```
Per chip: ZynqMP `enumerate.tcl` (+ `interpret.py`), Zynq-7000 `zynq7000-enumerate.tcl` (docs/24), Cortex-M
`cortexm-protect.tcl` (RDP/APPROTECT/FSEC/DSU + identity, docs/25), Pi `pi-enumerate.tcl` (debug-auth only —
the rest is VideoCore's). **Tier-2 unknown boards skip this** (no register KB) — that's expected.

**Reading it:** every line is a posture bit. On a dev board they all read "open/dev"; on a provisioned board
they light up — that flip is the whole point. A `LOCKED`/`BLOWN`/`SECURED` line tells you what stopped you.

---

## Step 5 — Dump flash and RAM

Run the plan's dump steps. The commands are pre-filled with the chip's addresses from the profile/cfg:
```bash
# DRAM (Paradigm A) — sparse, only used RAM hits disk:
DUMP_SPARSE=1 DUMP_ADDR=0x0 DUMP_SIZE=0x80000000 DUMP_OUT=dumps/os-live.bin \
  openocd -f <cfg> -c "init; source openocd/dump-os-ddr.tcl; shutdown"
# Boot flash — ZynqMP GQSPI (DMA), Zynq-7000 LQSPI window, or Cortex-M internal flash:
openocd -f <cfg> -c "init; source openocd/<flash-script>; shutdown"
```
**Failure modes:** a dump that returns all-`0xFF`/all-`0x00` means LQSPI/QSPI isn't mapped (board didn't boot
from flash), or you over-read past the used region. A bus error mid-dump usually means the AXI/AHB-AP hit a
gated region (XMPU/TrustZone) — note the address and continue past it.

---

## Step 6 — Analyze (all offline, safe)

Triage first, then dig:
```bash
python3 tools/dump-triage.py   dumps/<image>.bin     # FIRST: what IS this? entropy map + signatures
python3 tools/dram-secrets.py  dumps/os-live.bin --base 0x0   # keys/creds/certs/tokens/AES schedules
python3 tools/ghidra-loadspec.py dumps/<image>.bin   # exact Ghidra Language + Base (any ISA)
```
`dump-triage` tells you whether to disassemble (plaintext code), carve (`binwalk` a filesystem), or stop
(encrypted blob / mostly-blank). Then load into Ghidra with the language/base it printed. `parse-bootimage.py`
applies to **ZynqMP boot images only**; `vxworks-symtab.py`/`symbol-crypto.py` when the image is VxWorks.

---

## Two end-to-end runs

**Recognized board (ZynqMP), fully automatic:**
```bash
tools/probe-board.sh | tee fc.log
python3 tools/board-runner.py --from-log fc.log          # -> Tier 1 ZynqMP, full plan
# then walk the plan: verdict -> enumerate -> dump DRAM + QSPI -> triage/secrets/Ghidra -> Cap-2 patch
```

**Unfamiliar MCU (operator-asserted):**
```bash
python3 tools/board-runner.py --profile stm32f4          # you read "STM32F407" off the chip
# 1 [LIVE] cortexm-protect.tcl  -> RDP level + part + unique ID
# 2 [LIVE] cortexm-dump.tcl     -> internal flash + SRAM
# 3 [OFFLINE] dump-triage + dram-secrets + ghidra-loadspec (Thumb)
```

---

## Master troubleshooting table

| Stage | Symptom | Likely cause | Action |
|---|---|---|---|
| 1 | no IDCODEs anywhere | physical (Vref/pinout/GND/fused) | re-check Step 0; try 200 kHz |
| 1 | IDCODEs flaky | long leads / fast clock | drop the speed |
| 2 | Tier 2 (unknown) | chip not profiled | generic plan; or `--profile` if you know it |
| 2 | Tier 3 / NO-DAP | FPGA TAP, no CPU | vendor tool; no memory path |
| 3 | verdict not OPEN | locked DAP | reopen lever; if fused, it's a result |
| 3 | DTR wedge / segfault after a core op | EL1 core-path read | power-cycle; use the AXI-AP/`PATCH_HALT=0` path |
| 4 | enumerate can't read regs | DAP bypassed / not OPEN | back to Step 3 |
| 5 | dump all-0xFF / all-0x00 | flash not mapped / over-read | check boot mode; trim the range |
| 5 | bus error mid-dump | XMPU/TrustZone-gated region | note the address, read around it |
| 6 | triage says "encrypted/compressed" | secure-boot image / packed FW | look for a compression/FS signature; else suspect encryption |

**The honest reminder:** every profile except ZynqMP is HW-unvalidated — the addresses/decode are
doc-sourced and cited, but real silicon is the final word. Treat a first run on new silicon as a bring-up:
confirm the verdict and a sanity read before the bulk dump.
