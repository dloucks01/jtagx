# 18 — New-Board JTAG Bring-Up Runbook (Engagement)

How to take an **unfamiliar production / tactical board** from "box on the bench" to a
characterized security posture over JTAG, using this toolkit. This rebuilds the role of the
earlier unknown-board docs (06/07/08) that were pruned when the project narrowed to the
known ZCU102 dev board — re-oriented for an **authorized engagement** against silicon whose
security may actually be provisioned.

> **Authorization.** Only run this against a board you are explicitly authorized to test.
> Record scope, board S/N, and authorization before touching the target. JTAG bypasses every
> OS-level control; treat it accordingly.

> **Mindset shift from the dev board.** Everything in this repo was built and validated on an
> all-open dev ZCU102 where every gate reads OFF. A production board is the opposite case:
> expect JTAG to be locked or restricted, secure boot enforced, eFuses burned, and the
> capability primitives (A53/R5 release, inject, dump) to be *refused*. On a hardened board a
> refusal is not a failure — **it is the finding.** The job is to characterize what is and
> isn't gated, not to make the dev-board demos work.

---

## The dependency chain (where a production board fails differently)

Each stage gates the next. A hardened board can stop you at any of them; knowing *which* is
itself the result.

```
0 Recon        what SoC is it really? datasheet, JTAG header, voltages
1 Physical     adapter, pinout, level-shift, Vref, GND, lead length
2 Transport    electrical contact — does anything clock out at all?
3 Chain ID     IDCODEs -> is it ZynqMP? which die? (discover.tcl)
4 Access       is the DAP open, or locked/restricted? (jtag-access-check.tcl)
5 Enumerate    read the full security posture           (enumerate.tcl -> interpret.py)
· Profile      harvest per-board vars (media, names...)  (harvest-profile.tcl -> boards/<soc>.env)
6 Capability   reopen-debug / dump OS+flash / inject     (scripts auto-source the profile)
7 Boot image   dump QSPI/SD, analyze auth/encrypt posture (parse-bootimage.py)
```

---

## One-shot automation (Stages 3-4): unknown board → ready-to-enumerate cfg

Once the board is **physically** connected (Stages 0-2 done — adapter wired, voltage/pinout
correct), `tools/probe-board.sh` runs the *logical* path to a **ready-to-enumerate config + access
verdict**, halting with a verdict at the first gate that fails:

```bash
# operator-launched; strictly read-only (no reset/halt/writes); authorized boards only
tools/probe-board.sh                  # zero flags: auto-detect adapter, speed-ladder, identify, verdict
```

With no `--name` it names the config after the detected SoC (e.g. `openocd/zynqmp-zu9.cfg`).

It chains: adapter (`lsusb`) → speed-ladder chain scan → decode IDCODE → *(ZynqMP?)*
`gen-board-cfg.py` → access verdict (`jtag-access-check.tcl`), **recorded into the cfg**. It stops
cleanly at `NO-CHAIN` (physical — see Stages 1-2), `not-ZynqMP` (wrong toolset), or a DAP verdict
short of `OPEN` (the access controls are working — a result).

**It does NOT enumerate** — that's a separate, deliberate step (Stage 5) you run against the cfg
it produced, so the expensive characterization is decoupled from discovery and you can re-run it
freely:

```bash
openocd -f openocd/zynqmp-zu9.cfg -c "init; source openocd/enumerate.tcl; shutdown"
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
```

The cfg's adapter speed is the **lowest** speed that scanned the chain (safe for an unknown board);
since enumeration does far more reads, raise `adapter speed` in the cfg once it proves stable.

**What it cannot do** (the boundary; same as the manual stages): it does not fix physical faults
(wrong voltage/pinout/dead wire → `NO-CHAIN`, full stop — software can't sweep past physics), and
it cannot bring up a **non-standard scan chain** (extra CPLD / odd IRLEN fails `init` before
identification — it captures the raw IDCODEs and stops for manual `jtag newtap` work). It
automates the logical sweep, not the bench work. Prefer it for a fast first pass; fall back to the
manual stages below when it stops, or when you need finer control.

---

## Stage 0 — Recon

- Identify the SoC from silkscreen / FCC ID / BOM if available. **Confirm it is ZynqMP**
  (XCZU\*). If it's **Zynq-7000, Versal, or non-Xilinx**, `enumerate.tcl` and the register KB
  do **not** apply — see "Not ZynqMP?" below. The IDCODE in Stage 3 is the authoritative check.
- Locate the **JTAG header** and pinout (TCK/TMS/TDI/TDO/TRST/SRST/Vref/GND). Tactical boards
  often use non-0.1" connectors (ARM 10/20-pin Cortex, Samtec, or a custom test pad field).
- Note the **I/O voltage** (typically 1.8 V on ZynqMP PS JTAG) — you will need a level-shifting
  adapter or correct Vref. Wrong voltage = no chain or damaged pins.

## Stage 1 — Physical + adapter

- Pick an adapter OpenOCD supports (FT2232H, J-Link, FT232H, …) and wire it: TCK/TMS/TDI/TDO,
  **GND**, and **Vref** to the board's JTAG I/O rail. Keep leads short.
- Power the board in a **JTAG-permitting boot mode** if it has mode straps (on ZCU102 that's
  SW6 = all-ON / JTAG mode 0x0). A production board may have no such option — note that.

## Stage 2 — Transport + first electrical contact

Use the adapter-agnostic config rather than editing `zcu102.cfg`. Point `JTAG_IFACE` at your
adapter — a stock OpenOCD cfg, or one of the ready stanzas in `openocd/adapters/` (generic
FT2232H/FT232H with an explicit, editable pin layout for hand-wired adapters; see
`openocd/adapters/README.md`):

```bash
# Start SLOW. ls /usr/share/openocd/scripts/interface/ftdi/  +  ls openocd/adapters/
JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
  openocd -f openocd/board-template.cfg -c "init; shutdown"
```

Watch the OpenOCD init log for `JTAG tap: ... tap/device found: 0x........`. If **nothing**
clocks out: drop `JTAG_SPEED` to 200, recheck Vref/GND/pinout and SRST, and confirm the board
is actually powered. Persistent silence on a powered board with correct wiring points at
**JTAG-disable eFuses** (a finding in itself).

## Stage 3 — Chain identification

```bash
JTAG_IFACE=interface/jlink.cfg JTAG_SPEED=1000 \
  openocd -f openocd/board-template.cfg \
    -c "init; source openocd/discover.tcl; shutdown"
```

`discover.tcl` lists every TAP, enumerates the DAP's access ports, and suggests next steps by
TAP naming. Decode any IDCODE interactively with `describe_idcode 0x...` — this maps the part
ID against `lib/zynqmp-variants.tcl` and tells you the die (XCZU9/7/…) **or** flags Zynq-7000 /
Versal / non-Xilinx. If `discover.tcl` reports the PMU BSCAN TAP, switch to the 3-TAP target
(`openocd/zcu102-3tap.cfg` recipe) via `JTAG_TARGET`.

## Stage 4 — Access determination (the key engagement question)

```bash
JTAG_IFACE=interface/jlink.cfg JTAG_SPEED=1000 \
  openocd -f openocd/board-template.cfg \
    -c "init; source openocd/jtag-access-check.tcl; shutdown"
```

`jtag-access-check.tcl` is **non-destructive** (reads only) and prints an **ACCESS VERDICT**:

| Verdict | Meaning | What it tells the engagement |
|---|---|---|
| **OPEN** | DAP powered, MEM-APs respond, non-secure regs read | Proceed to Stage 5 — full posture enumeration is possible. |
| **RESTRICTED** | DAP up but a basic register read faults | Access gated (XPPU / TrustZone / secure-debug) — **note which reads fault**; that map is a finding. |
| **LOCKED** | Chain present, DAP won't even answer a DP read | DAP disabled / secured. Decode IDCODE; on ZynqMP this points at DAP-disable / secure-debug eFuses. |
| **NO-DAP** | TAPs exist, no Arm DAP reachable | PS-TAP with DAP gated, or non-ZynqMP silicon. |
| **NO-CHAIN** | No TAPs at all | Electrical, reset, or JTAG-disable eFuses. Back to Stage 1/2. |

It also reports the DP CTRL/STAT power-up acks (CDBGPWRUPACK/CSYSPWRUPACK) and sticky-fault
bits — a debug domain held un-powered is a gating signal even before any read is attempted.

**Capture a repeatable config (two-pass).** A config cannot be auto-divined from JTAG discovery
— discovery only runs once a config already works (the **bootstrap paradox**: adapter choice is
a USB fact not a JTAG fact; clock stability, transport, voltage and pinout are all chosen/known
*before* init, and a non-standard chain fails init *before* discovery can describe it). So the
honest loop is: do the loose first contact above with `board-template.cfg`, tee the log, then
codify it:

```bash
JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
  openocd -f openocd/board-template.cfg \
    -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee firstcontact.log
python3 tools/gen-board-cfg.py --name <board> --from-discovery firstcontact.log --speed 1000
#   -> openocd/<board>.cfg, with the discovered IDCODEs pinned + a confidence report
```

`gen-board-cfg.py` determines only what's knowable — the adapter interface (from `lsusb` or
`--adapter`) and the SoC family (by decoding the log's IDCODEs) — and **refuses** to emit a
ZynqMP config if the IDCODE says the part is Zynq-7000 / Versal / non-Xilinx. It prints the
caveats it *cannot* verify (voltage, pinout, speed stability, transport) rather than pretending
the config is guaranteed to work.

## Stage 5 — Enumerate the security posture

Only meaningful once Stage 4 is **OPEN** (or partially OPEN). Capture on-site, interpret
offline (limited board time → capture once, analyze repeatedly):

```bash
openocd -f openocd/board-template.cfg \
  -c "init; source openocd/enumerate.tcl; shutdown"          # -> reports/raw-<ts>.json (+ md)
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O   # -> Security Posture Summary
```

The **Security Posture Summary** is your characterization deliverable. On a dev board it reads
all `OFF/dev`; on a hardened board it should read mostly `ON/provisioned` — secure-boot policy,
JTAG/debug gates, eFuse locks, key state, anti-tamper, TrustZone. `docs/11-enumerated-attributes.md`
is the catalog of every attribute (dev value vs hardened meaning vs why it matters). Whatever
reads faulted in Stage 4 will show as unreachable here — record it.

## Board profile — harvest once, the capability scripts adapt everywhere

Before the capability scripts, harvest a **board profile** so nothing downstream is hardcoded to a
specific board. One read-only pass on the (running) target writes `boards/<soc>.env`:

```bash
BOARD_SOC=<soc-name> openocd -f openocd/<board>.cfg \
  -c "init; source openocd/harvest-profile.tcl; shutdown"      # -> boards/<soc>.env
```

It reads what genuinely varies per board and is discoverable from a running part: **target/DAP object
names** (auto-detected — the stock `xilinx_zynqmp.cfg` names them `uscale.axi`/`uscale.dap` on every
ZynqMP, but a custom chipname is detected too), **boot media** (from the `BOOT_MODE` register, 0xFF5E0200
— not assumed) and the matching flash-read command (`sf` vs `mmc`), and `DDR_BASE`. CSU/OCM addresses
are *universal* across UltraScale+ and stay in the scripts; `psu_init`/U-Boot are never needed because a
running board already has DDR up (read it directly).

The capability scripts — `reopen-debug.tcl`, `dump-os-ddr.tcl`, `dump-boot-flash.tcl` — **source
`board-profile.tcl`**, which resolves every per-board variable with precedence
`env > boards/<soc>.env > runtime-detect > default`. Net effect: **the live commands are byte-identical
on any UltraScale+ board** — only the generated cfg + harvested profile differ, and both are produced by
the tooling, not hand-edited. (Multiple boards: the newest `boards/*.env` is auto-loaded; pin one with
`BOARD_PROFILE=boards/<soc>.env`.)

## Stage 6 — Capability tests (gating-aware)

Attempt these only with the posture summary in hand, and **expect refusals** on a hardened
board — each refusal is a positive result that the corresponding control is enforcing. The first
three auto-source the board profile, so they run unchanged across boards.

| Capability | Script | Likely on a hardened board |
|---|---|---|
| **Debug Lockdown Bypass** (re-open closed debug gates) | `openocd/reopen-debug.tcl` | Works if the lockdown is software register state; **refused (write doesn't stick) if eFuse-locked** — and the read-back tells you which |
| **Dump live OS from DRAM** | `openocd/dump-os-ddr.tcl` | Works wherever the AXI-AP reads DRAM; gated ranges come back `0xDEADBEEF` |
| **Dump boot flash, strap-free** (reflashable image) | `openocd/qspi-jtag.tcl` | **JTAG-native** GQSPI reader (AXI-AP MMIO) — reads QSPI from a live board with no U-Boot / no DDR / no boot-strap change; the engagement-grade flash dump. `dump-boot-flash.tcl` is the U-Boot-staging fallback. |
| Halt/release A53 / R5 | `lib/release-recipes.tcl` | Blocked if invasive debug gated (enumerate §8 tells you first) |
| Inject + run a payload | `openocd/inject.tcl` | Blocked if core release / memory write is gated |
| Memory / ROM / PMU dump | `dump-bootrom.tcl`, `dump-pmu.tcl` | SLVERR / zeros behind XPPU / TrustZone |
| DDR bring-up over JTAG | `jtag-ddr-boot.tcl` | Works only if MMIO writes aren't gated |

## Stage 7 — Boot-image posture

If you can dump the boot device (QSPI/SD) — over JTAG, a flash programmer, or a UART pull —
analyze it offline:

```bash
python3 tools/parse-bootimage.py BOOT.bin     # BH -> IHT -> PHT, per-partition encrypt/auth + rules
```

`rule_pl_bitstream_unprotected` flags an auth-only / unprotected PL bitstream (the JustSTART /
CVE-2023-20570 target). Cross-reference findings with `docs/15-prior-research.md`, which maps
the published ZU+/ZynqMP attacks (CVE-2019-5478 encrypt-only, JustSTART, Starbleed, SCA) to
posture-detector checks — **these need an enforcing board, which a production target finally is.**

---

## Not ZynqMP? (Stage 3 said otherwise)

- **Zynq-7000** (XC7Z\*): different SLCR/register map (UG585). `enumerate.tcl` does not apply;
  the chain/access scripts still work for Stages 2-4.
- **Versal** (ACAP): PMC replaces PMU, A72 cores, CDO boot — fundamentally different (AM011).
  Needs `xilinx_versal.cfg` and a from-scratch enumeration.
- **Non-Xilinx Arm**: `discover.tcl` + `dap info <ap>` walk the CoreSight ROM table to find
  debug components without a vendor config. The access-check's power/AP logic still applies.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| No IDCODEs on a powered board | speed too high, Vref/GND, reset held, JTAG-disable eFuse | drop to 200 kHz; recheck wiring/SRST; if clean wiring → suspect eFuse |
| IDCODE reads but DAP won't answer | DAP gated / secure-debug | `describe_idcode`; treat as LOCKED finding |
| Reads return all-zero or SLVERR | XPPU/TrustZone/secure-debug gating, or DP sticky-error | note the gated ranges; access-check clears sticky between reads |
| DAP "wedges" after a read burst | known failure mode | see memory `reference_dap_wedge`; power-cycle, slow down, smaller bursts |
| Chain unstable / intermittent | lead length, speed, signal integrity | shorten leads, lower `JTAG_SPEED`, add Vref decoupling |

## Artifacts introduced for this workflow

- `openocd/board-template.cfg` — adapter-agnostic config (env-driven: `JTAG_IFACE`,
  `JTAG_SPEED`, `JTAG_TARGET`).
- `openocd/jtag-access-check.tcl` — non-destructive OPEN/RESTRICTED/LOCKED/NO-DAP/NO-CHAIN verdict.
- `openocd/adapters/` — ready-to-use interface stanzas (generic FT2232H/FT232H, explicit pin
  layout) + a README mapping common adapters to stock cfgs.
- `tools/gen-board-cfg.py` — writes a filled-in `<board>.cfg` from `lsusb` + a discovery log;
  honest about the bootstrap paradox; refuses non-ZynqMP targets.
- `tools/probe-board.sh` — one-shot orchestrator (adapter → chain scan → identify → cfg →
  access verdict, recorded into the cfg); read-only, operator-launched, gated; zero-flag,
  SoC-named config. Stops at a ready-to-enumerate cfg; does NOT enumerate (Stage 5 is separate).
- `openocd/harvest-profile.tcl` — one read-only discovery pass on a running board → `boards/<soc>.env`
  (target/DAP names, boot media + flash command from `BOOT_MODE`, `DDR_BASE`).
- `openocd/board-profile.tcl` — the de-hardcoding layer the capability scripts source; resolves every
  per-board variable `env > boards/<soc>.env > runtime-detect > default`, so they run unchanged on any
  UltraScale+ board.
- `openocd/{reopen-debug,dump-os-ddr,dump-boot-flash}.tcl` — board-general capability scripts
  (Debug Lockdown Bypass; live-OS-from-DRAM dump; boot-image flash dump), all profile-driven.
- `openocd/qspi-jtag.tcl` — **JTAG-native QSPI flash reader** (drives the GQSPI Generic-FIFO over the
  AXI-AP; built from UG1085 Ch.24). Reads the boot image strap-free from a live board — no U-Boot, no
  DDR bring-up, no boot-mode change. `QSPI_OP=id` (JEDEC self-test) / `read` (validate) / `dump` (→file).
  Handles dual-parallel flash by per-die read + interleave. (DMA-accel mode is built but parked — see
  memory `project_qspi_jtag_reader`.)
- Existing: `openocd/discover.tcl`, `lib/{idcode-lookup,zynqmp-variants}.tcl`, `enumerate.tcl`,
  `tools/{interpret,parse-bootimage}.py`, `docs/{11,15}`.
