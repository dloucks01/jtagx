---
title: Operator Quick Reference — ZCU102 JTAG Enumeration
subtitle: Plug-and-go field guide
---

# Operator Quick Reference

This is what you actually need to *do* at the bench. Internals, theory, and the
full whitepaper live elsewhere; this guide assumes you just want to plug in,
run the tool, see results, and know what to do next.

For background on what each attribute means, see the attribute catalog
[`../11-enumerated-attributes.md`](../11-enumerated-attributes.md) and whitepaper
Volume 3 [`../whitepaper/03-enumeration-reveals.md`](../whitepaper/03-enumeration-reveals.md).

---

## What you need

| Item | Notes |
|---|---|
| ZCU102 board | Powered down for now |
| USB cable to the JTAG bridge (mini-USB on J37/Digilent SMT2) | Plugs into your VM/laptop |
| Kali Linux VM with this repo | Path used here: `/home/kali/Desktop/research/JTAG` |
| OpenOCD installed | `sudo apt install openocd` if missing |
| Python 3 | Pre-installed on Kali |

**Boot mode:** confirm SW6 (the boot-mode DIP block) is **all OFF** — that's
JTAG boot. The factory default ships in that state.

---

## Setup checklist (do once per session)

1. **Power up the board.** Slide SW1 to ON. The fan should start, the
   power LEDs should light up.
2. **Plug the USB cable** from the SMT2 bridge into the host. If you're in a
   VM, attach the device via the VM's USB menu — the SMT2 enumerates as a
   composite device with 4 channels.
3. **Verify the USB enumerated:**

   ```
   ls /dev/ttyUSB*
   ```

   You should see `ttyUSB0` through `ttyUSB3`. If not, disconnect and
   re-attach from the VM's USB menu.
4. **Pick the right port to watch the serial console:** `ttyUSB0` is the
   APU console UART. (Not needed in JTAG-idle mode but worth knowing.)

---

## The run procedure (3 commands)

From the repo root (`cd /home/kali/Desktop/research/JTAG`):

### Step 1 — capture

```
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"
```

This produces two files:

| File | What it is |
|---|---|
| `reports/enumerate-<timestamp>.md` | Raw markdown — addresses + values + bit decode |
| `reports/raw-<timestamp>.json` | Structured capture for step 2 |

You'll see the OpenOCD startup banner, then ~18 section headings stream past.
The whole thing takes ~30-60 seconds.

### Step 2 — interpret

```
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
```

Produces `reports/interpreted-<timestamp>.md` — the report with annotations
and security findings. This is the file you actually read.

### Step 3 — open the interpreted report

```
less reports/interpreted-<timestamp>.md
```

Or open it in any markdown viewer.

---

## What to look at — in order of importance

Skim sections in this order. Stop when you've answered the question that
brought you here.

### 1. Findings section (top of report)

Look for `## Findings (rules fired)` near the top. This is the summary —
each fired rule gets a coloured glyph, a name, a one-line description, and a
"what this means" prose explanation, plus offensive implications.

**Severity glyphs:**

| Glyph | Severity | Action |
|---|---|---|
| 🔴 | **CRITICAL** | Security gate is wide open — investigate immediately |
| 🟠 | **MAJOR** | Significant weakness, usually fixable |
| 🟡 | **MINOR** | Minor concern or expected dev-state oddity |
| 🔵 | **INFO** | Notable but not actionable on its own |

On a stock ZCU102 in JTAG-idle, expect ~10 findings, most INFO with one
CRITICAL (SPIDEN — secure-world debug enabled). That's the dev-kit baseline.

### 2. Silicon identity (just below findings)

Confirms which chip you're actually looking at. Verify:

- `die` should be `XCZU9` for a ZCU102
- `marketed_as` should include `EG` or `CG`
- `device_dna_0/1/2` is the per-chip unique ID — **write this down**, it's
  how you tell two physical boards apart

### 3. CSU.JTAG_SEC + CSU.JTAG_DAP_CFG (section §4)

Search the report for `CSU.JTAG_SEC` and `CSU.JTAG_DAP_CFG`. These are the
master JTAG security gates. On a wide-open dev kit you'll see all bits set
(`0x3F` and `0xFF`). On a hardened production device you'd see most or all
bits clear.

### 4. EFUSE.SEC_CTRL (also section §4)

Search for `EFUSE.SEC_CTRL`. These are the eFUSE-blown security settings.
On a fresh dev kit it's `0x00000000` (factory state — no fuses blown). Any
non-zero value here means somebody has hardened this specific chip.

### 5. PCAP_STATUS.PL_DONE (section §17)

Tells you whether the FPGA fabric has a bitstream loaded. `PL_DONE=1` means
yes; `=0` means the PL is empty.

---

## Things to write down

Per board / per session, capture these to a notebook (paper or digital):

```
Board ID:           ___________________  (e.g. ZCU102 #1)
Physical S/N:       ___________________  (sticker on the board)
Date / time:        ___________________
Boot mode:          JTAG-idle / SD / QSPI / other

Silicon DNA:        DNA_0 = _______________
                    DNA_1 = _______________
                    DNA_2 = _______________
Silicon REV:        ___
PART_ID:            0x____

Findings count:     ___ CRITICAL, ___ MAJOR, ___ MINOR, ___ INFO

Key bits:
  CSU.JTAG_SEC                   = 0x________
  CSU.JTAG_DAP_CFG               = 0x________
  EFUSE.SEC_CTRL                 = 0x________
  PCAP_STATUS.PL_DONE            = ___
  PWR_STATE                      = 0x________

Anything that diverges from the previous run? _____________________

Report filename:    reports/interpreted-_______________.md
```

The DNA + a snapshot of the key bits is your "is this the same chip in the
same state" reference. If you run the script tomorrow and any of these
changed, something happened between runs.

---

## If you see X — decision table

| You see... | What it means | What to do |
|---|---|---|
| `CSU.JTAG_SEC = 0x3F` and `JTAG_DAP_CFG = 0xFF` | All JTAG security gates open — dev-kit factory state | Expected on ZCU102 fresh-out-of-box. Continue. |
| `JTAG_SEC` has any of the three 3-bit fields = 0 (`0x07`, `0x38`, `0x1C0`) | Some JTAG path is locked at the SSS — DAP, PMU, or PL TAP is gated | Note which one. You may not be able to halt the A53 or talk to the PL via JTAG. |
| `EFUSE.SEC_CTRL` ≠ `0x00000000` | Someone has blown one or more security fuses on this die | **Stop and read the EFUSE.SEC_CTRL field decode carefully.** Some bits are *one-way* — programming JTAG_DIS, ENC_ONLY, or SEC_LOCK permanently changes the device. |
| `EFUSE.SEC_CTRL.JTAG_DIS = 1` | JTAG hardware-disable fuse has been blown | This board's JTAG is permanently dead. You're enumerating something that shouldn't work — investigate. |
| `EFUSE.SEC_CTRL.SEC_LOCK = 1` | SEC_CTRL is write-locked | The security policy is frozen. Can't be relaxed without a die replacement. |
| Findings include "Maximum debug exposure" | All security gates are wide open | Expected on a dev kit; would be a critical finding on a production device. |
| `PCAP_STATUS.PL_DONE = 1` | FPGA bitstream IS loaded | Add to your notes: PL is configured. You can probe PL-side IP. Bitstream extraction is possible via PCAP. |
| `PCAP_STATUS.PL_DONE = 0` | FPGA fabric is empty | Whatever you were going to do to PL-side IP is moot. The fabric has nothing in it. |
| Rule "XPPU disabled" fires | LPD peripheral protection is off | Expected in JTAG-idle; PMU firmware turns it on during a normal boot. If you see this on a *booted* device, that's a finding. |
| Rule "XPPU protection violations latched" fires | Some master has been blocked from a peripheral | **Investigate.** This means someone or something tried to access a forbidden region and got caught. |
| `A53.0 state` ≠ `halted` | A53 release didn't work | Power cycle the board (SW1 off, 5 sec, on) and re-run. If still failing, see `docs/appendix-a-recovery.md`. |
| Report has many `READ FAILED` lines | DAP wedged — likely tried to read a power-gated or held-in-reset block | Power cycle + re-run. If a specific section consistently fails, the script may need a guard for that variant. |
| Two consecutive runs produce different `device_dna_*` | You're looking at two different chips, OR the DAP is returning garbage | Re-seat USB, power cycle, re-run. DNA never changes for a given die. |

---

## Suggested next steps menu

After you've reviewed an interpreted report, pick one based on what you
want to do next:

| Goal | Read | Run |
|---|---|---|
| Assess a board's security posture at a glance | The **Security Posture Summary** table in the interpreted report; detail in [`../11-enumerated-attributes.md`](../11-enumerated-attributes.md) | (in the interpreted report) |
| Just understand what each attribute means | [`../11-enumerated-attributes.md`](../11-enumerated-attributes.md) | — |
| Compare two boards | (No tool yet — diff the two interpreted reports in your editor) | `diff reports/interpreted-A.md reports/interpreted-B.md` |
| Diff the current run against the frozen golden baseline | `tests/golden/zcu102-jtag-idle/interpreted-compact.md` is the reference | `diff reports/interpreted-<ts>.md tests/golden/zcu102-jtag-idle/interpreted-compact.md` |
| Confirm the JTAG chain before enumerating | `docs/09-discover-tool.md` | `openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"` |
| Boot the device from SD / QSPI and re-enumerate | Phase 7 (validated — see memory `project_phase7_ipi_validated`) | Same sequence with a non-JTAG boot mode set on SW6 |
| Dump the BootROM / PMU firmware for offline analysis | `openocd/dump-bootrom.tcl` / `dump-pmu.tcl` (+ `tools/bootrom.py`) | `openocd -f openocd/zcu102.cfg -c "init; set ::BOOTROM_METHOD <m>; source openocd/dump-bootrom.tcl; shutdown"` |
| Read deeper context on why an attribute matters | whitepaper Volume 3 `docs/whitepaper/03-enumeration-reveals.{md,pdf}` | — |

---

## When things go wrong

| Symptom | First thing to try |
|---|---|
| OpenOCD: `Error: Couldn't find /dev/ttyUSBX` | Re-attach USB in the VM USB menu |
| OpenOCD: `Error: JTAG scan chain interrogation failed` | Power cycle the board |
| OpenOCD hangs forever on a specific section | `Ctrl+C`, note which section, power cycle |
| `interpret.py: KeyError` or `AttributeError` | Re-run capture; if persistent, the JSON schema may have changed — re-run goldens or check `tools/check-annotations.py` output |
| Findings report says "0 rules fired" but you expected findings | Capture was probably broken — open the raw JSON and confirm `registers` has entries with non-empty `fields` dicts |

For anything stickier: `docs/appendix-a-recovery.md` covers DAP wedge,
USB passthrough, full power-cycle procedure.

---

## Cleanup after your session

The script's cleanup block re-asserts A53 core 0 reset at the end of every
run, so the board is in a known state for the next run without a power
cycle. You only need to power-cycle if a run crashed mid-cleanup.

To physically pack up:

1. Unplug USB
2. Slide SW1 to OFF
3. Optionally export your interpreted reports to wherever you keep notes
