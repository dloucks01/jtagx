# 19 — Script Walkthrough

A phase-by-phase walkthrough of the toolkit's scripts. **Phases A–B** are the core pipeline that
takes a board from "just connected" to a characterized security posture; **Phase C** covers the
capability, dump, and support tools around it. Each entry documents *what the script does, what it
reads, what it produces, and where it stops* — and Phase C carries a **verification status** (ran
offline ✅ / hardware-validated ⚙ / unverified ⚠). For the runbook framing (physical setup, stages,
troubleshooting) see `docs/18-new-board-bringup.md`; this doc is the per-script reference behind it.

## The two phases

The pipeline is deliberately split so discovery is decoupled from the expensive characterization:

```
PHASE A — probe (read-only, automated)        PHASE B — characterize (separate, deliberate)
  unknown board                                  ready cfg
     │ adapter detect                               │ enumerate.tcl   (capture)
     │ chain scan                                   │ interpret.py    (interpret)
     │ identify SoC                                 ▼
     │ access verdict                            Security Posture Summary
     ▼
  ready-to-enumerate cfg  ───────────────────────▶ (you run Phase B against it)
```

`probe-board.sh` orchestrates Phase A end-to-end and **stops at a ready cfg + verdict** — it does
not enumerate. Phase B is a command you run yourself against the cfg Phase A produced.

---

## Phase A

### `probe-board.sh` — orchestrator (unknown board → ready-to-enumerate cfg)

Strictly **read-only** (chain scan + register reads only; no reset, halt, or writes), operator-
launched, no prompts. Halts with a clear verdict at the first gate that fails.

| Phase | What it does | Stop / gate |
|---|---|---|
| **Setup** | Parse flags (`--name`, `--adapter`, `--speeds`, `--target`, `--force`) — all optional. Print the read-only banner. | — |
| **Adapter resolve** | Use `--adapter` if given, else call `gen-board-cfg.py --detect-adapter` (USB enumeration → interface cfg). | aborts if no adapter resolves |
| **Stage 1 — chain scan** | For each speed in the ladder (`200 1000` kHz, ascending), run `board-template.cfg` with `init; shutdown` and grep IDCODEs from the output. The first speed that yields any IDCODE wins (lowest = safest for an unknown board). | **NO-CHAIN** → stop (physical: voltage/pinout/wiring/eFuse) |
| **Stage 2 — identify + generate** | Pipe the winning scan log to `gen-board-cfg.py`, which decodes the IDCODE, names the cfg after the SoC die, and writes it. Capture the written path. | **not-ZynqMP** → stop (wrong toolset) |
| **Stage 3 — access verdict** | Run the generated cfg through `jtag-access-check.tcl`; parse the verdict; **append it to the cfg** so the handoff carries the access decision. | **verdict ≠ OPEN** → record + stop |
| **Handoff** | On OPEN: print `READY`, the exact separate `enumerate` command, and a note that the cfg's speed is the lowest that scanned (raise it for faster enumeration). | — |

Flags worth knowing: `--name` overrides the SoC-derived name; `--speeds "1000"` pins a known-good
speed; `--target` for a non-default target cfg; `--force` to proceed past a non-ZynqMP IDCODE
(chain access only). `OPENOCD=/path` overrides the binary (used to test the script offline).

### `gen-board-cfg.py` — config generator (two modes)

**`--detect-adapter` mode:** runs `lsusb`, matches each device against a curated `ADAPTER_DB`
(VID:PID → interface cfg), and prints the single matching interface cfg — or errors on *none*
(asks for `--adapter`) or *multiple* (asks you to choose). VID:PID matching is a heuristic
(FTDI VIDs are shared by clones), so it's a suggestion you confirm.

**Generation mode** (the phases, in order):
1. **Resolve adapter** — from `--adapter` or USB auto-detect.
2. **Parse discovery** — extract *actual-device* IDCODEs from the log. Matches only genuine
   device-report formats (`tap/device found`, `UNEXPECTED idcode`, discover's `IDCODE 0x…:`) and
   **skips the target cfg's `expected …` wish-lines**, so a chain mismatch isn't mis-identified.
3. **Decode + decide family** — first non-DAP IDCODE sets the SoC family. **Refuses to emit a
   ZynqMP cfg if the part is Zynq-7000 / Versal / non-Xilinx** (override with `--force`).
4. **Name** — `--name` if given, else derived from the die via the `PART_DIE` table
   (e.g. part `0x4738` → `zynqmp-zu9`). The IDCODE fixes the die, not the EG/CG/EV package suffix.
   Auto-named configs overwrite freely (idempotent on the same board).
5. **Emit** — write the cfg: provenance header (adapter, speed, target, observed IDCODEs),
   the caveats it *cannot* verify (voltage/Vref, pinout, speed stability, transport), and the
   `source`/`adapter speed`/`target` lines. Repo-local adapter cfgs get a plain `source`; stock
   cfgs get `source [find …]`.
6. **Confidence report** — print *determined* (adapter, clock, SoC family) vs *you-must-verify*.

### `board-template.cfg` — adapter-agnostic parametric runner

The env-driven OpenOCD config `probe-board.sh` runs for the chain scan, and the model
`gen-board-cfg.py` emits a filled-in copy of. Phases:

1. Require `JTAG_IFACE` (error + `shutdown` if unset) → `source [find $JTAG_IFACE]`.
2. `transport select jtag`.
3. `adapter speed` from `JTAG_SPEED` (default 1000; kept low for unknown boards).
4. `source` the target — `JTAG_TARGET` or `target/xilinx_zynqmp.cfg`.
5. `catch { target create uscale.dbg mem_ap … -ap-num 1 }` — the APB-debug mem-AP that
   `enumerate.tcl §8` and `jtag-access-check.tcl` use (must be created at config time on OpenOCD 0.12).

### `jtag-access-check.tcl` — the access verdict (non-destructive)

Reads only. Answers "is the DAP usable, or are the access controls enforcing?"

| Phase | Reads | Decides |
|---|---|---|
| 1. Chain present? | `jtag names` → TAP count | **NO-CHAIN** if zero |
| 2. DAP power / fault | DP CTRL/STAT — CDBGPWRUPACK (bit 29), CSYSPWRUPACK (bit 31), STICKYERR/STICKYORUN | **LOCKED** if the DP won't answer; **NO-DAP** if no DAP object exists |
| 3. Access ports | each AP's IDR → class (MEM-AP / JTAG-AP) | counts reachable MEM-APs |
| 4. Benign reads | `BOOT_MODE_USER` (0xFF5E0200), CRL_APB (0xFF5E0070) | **OPEN** if they read back; **RESTRICTED** if a read faults |
| Verdict | — | prints `ACCESS VERDICT: <X>` + the recommended next command |

A verdict short of OPEN on a production board is itself a result — the controls are working.

### `discover.tcl` — chain sanity check (optional, family-agnostic)

Lists every TAP the target cfg knows, enumerates the DAP's access ports (decoding AP class/type),
and suggests next steps from TAP-naming heuristics (ZynqMP / Zynq-7000 / Versal / generic Arm).
`describe_idcode 0x…` decodes any IDCODE against `lib/zynqmp-variants.tcl`. Use it for a fuller
TAP/AP picture than the access check's summary.

---

## Phase B — characterization (the separate, deliberate step)

Run against the cfg Phase A produced. This is where the actual security posture comes from.

> **In one line:** the enumeration script is a **read-only security X-ray of the chip over JTAG** —
> it reads every place a security feature *would* be configured and reports whether each is on.

**What it is.** The enumeration script is the toolkit's centerpiece. Sourced into an OpenOCD
session, it walks the SoC's entire security surface over JTAG and records the raw values, then
`interpret.py` translates them into a plain **Security Posture Summary** — for each feature, a
verdict of `OFF/dev` (unprovisioned) or `ON/provisioned` (hardened). It **changes nothing**: no
resets, halts, or writes. On this dev board everything reads `OFF` (the all-open baseline); the
same script, unchanged, lights up whatever a production board actually enforces.

**Mental model:** *"Everything a hardened board is supposed to have locked down — this tells you
whether it actually is."* It answers "what is the security state of this silicon?" — it does not
attack, modify, or bypass anything.

**What it reads** (the checklist behind the summary):
- **Secure boot** — is authentication/encryption required, or is unsigned/plaintext boot allowed?
- **Key state** — are device keys (PPK/SPK hashes, BBRAM, PUF) provisioned, or zero?
- **JTAG / debug gates** — is debug access locked, or wide open (as it is now)?
- **Anti-tamper & eFuse locks** — are the one-time fuses that disable debug/JTAG burned?
- **Memory isolation** — are TrustZone / XMPU / XPPU regions enforcing, or all-permissive?

### `enumerate.tcl` — capture
Sourced into an OpenOCD session, it reads every location where a ZynqMP security implementation
*would* live — §4 secure-boot policy / key state / JTAG & debug gates / anti-tamper / eFuse locks,
§8 invasive-debug gate + EDPCSR PC-sampling, §16 memory TrustZone — building a `::CAPTURED` dict.
It emits **both** a human markdown report (`reports/enumerate-<ts>.md`) and a machine-readable raw
JSON (`reports/raw-<ts>.json`).

```bash
openocd -f openocd/<name>.cfg -c "init; source openocd/enumerate.tcl; shutdown"
```

### `interpret.py` — interpret
Loads the raw JSON plus the annotation modules (`docs/annotations/*.py`) and rule engine
(`docs/findings/zynqmp_rules.py`), and produces the **Security Posture Summary** — a flat
`OFF/dev → ON/provisioned` checklist per implementation — plus cross-register findings. Because
it works from the saved JSON, interpretation can be re-run and improved offline without re-touching
hardware.

```bash
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
```

On the dev ZCU102 the summary reads all `OFF/dev` (the all-open baseline); on a hardened board the
same script lights up `ON/provisioned`. `docs/11-enumerated-attributes.md` is the catalog of every
attribute (location, dev value, hardened meaning, why it matters).

**Top-line verdict + next steps.** `interpret.py` leads the report with an **Engagement Triage**
banner (promoted above all findings, BLUF-style) —
the one-glance answer to "what state is this board in, and what do I run next?" It classifies the
board (`ALL-OPEN` / `PARTIALLY PROVISIONED` / `HARDENED`) from the same posture fields, lists what's
**open** vs **enforced**, and prints **recommended next tools gated on the actual state** — e.g. on
an all-open board: *DAP open → `inject.tcl` / `jtag-ddr-boot.tcl`; boot unauthenticated → dump QSPI/SD
and run `parse-bootimage.py`; check `docs/15` CVEs* — while honestly marking what's out of scope
(BootROM not dumpable, family key hardware-only). On a hardened board it instead says "expect the
capability tools to be refused — that refusal is the finding — pivot to boot-image / CVE / physical."
This is the bridge from enumeration to the rest of the engagement (`docs/18` Phase C tools).

---

## At a glance — execution order

```
lsusb ─▶ probe-board.sh ─┬─ gen-board-cfg.py --detect-adapter   (adapter)
                         ├─ board-template.cfg (Stage 1 scan)   (IDCODEs)
                         ├─ gen-board-cfg.py --from-discovery    (Stage 2: identify + write cfg)
                         └─ jtag-access-check.tcl                (Stage 3: verdict, recorded in cfg)
                                    │
                                    ▼  openocd/<soc>.cfg  (ready, verdict recorded)
                         enumerate.tcl ─▶ raw-<ts>.json ─▶ interpret.py ─▶ Security Posture Summary
```

---

## Phase C — capability, dump & support tools (beyond the core pipeline)

The tools below sit outside the probe→enumerate spine: post-enumeration capability/dump scripts,
offline analysis, and the build/test harness. Each row carries a **verification status** as of
2026-06-10:

- **✅ verified offline** — ran this session against a real input and produced a result.
- **⚙ hardware-validated** — live JTAG only (can't run without the board); evidenced by a
  produced artifact on disk + prior on-silicon validation.
- **⚠ unverified** — parses and is non-destructive, but has produced no captured result; do not
  present as result-producing.

### C1 — Capability & dump tools (live JTAG)

| Script | What it does / produces | Status & evidence |
|---|---|---|
| `dump-bootrom.tcl` | BootROM extraction — multiple methods + the R5-dump frontier; a method dispatcher (`baseline/csudma/a53/loader/r5/aes` + the `pmu-*` methods in `research-pmu.tcl`). | ⚙ offline smoketest validates the dispatcher logic; produced `dumps/bootrom-via-pmu-r5-bootrom-*.bin` |
| `dump-pmu.tcl` | PMU LMB-RAM / ROM memory dump over JTAG. | ⚙ offline smoketest; the PMU-ROM-eFuse-locked finding came from it |
| `inject.tcl` | Load any `.bin` to any address, run it on a core, verify by read-back. | ⚙ COLD mode hardware-validated (OCM+DDR); LIVE mode blocked by OpenOCD 0.12 (no SCTLR_EL1) |
| `probe-csu-surface.tcl` | Non-destructive CSU/AES/SSS/DMA surface map (BootROM-dump / family-key vectors). | ⚙ produced `_archive/reports/csu-surface-*.md` |
| `probe-csu-dma-rom.tcl` | Can CSUDMA (alternate AXI master) read a ROM the DAP can't? SSS DMA-loopback, with an OCM→OCM calibration baseline. | ⚙ produced `csu-dma-rom-*.md` (negative result — surface exhausted) |
| `probe-csu-fullmap.tcl` | Complete per-word CSU register map with sticky-error recovery. | ⚙ produced `csu-fullmap-*.md` |
| `jtag-ddr-boot.tcl` + `psu-init-replay.tcl` + `jtag-load-uboot.tcl` | Bring up DDR over pure JTAG by replaying `psu_init` as MMIO (A53 halted → no FSBL wedge), then load + run U-Boot. | ⚙ DDR-over-JTAG validated on silicon (memory `project_jtag_ddr_bringup`); see `docs/16` |
| `dump-fdt.tcl` | Dump a live FDT in small chunks (avoids the bulk-read wedge). | ⚙ produced `dumps/npmain-dt` during the VxWorks bring-up |
| `qspi-jtag.tcl` | **JTAG-native QSPI flash reader** — drives the GQSPI Generic-FIFO over the AXI-AP (built from UG1085 Ch.24). Dumps the boot image **strap-free from a live board**: no U-Boot, no DDR bring-up, no boot-mode change. `QSPI_OP=id`/`read`/`dump`; dual-parallel handled by per-die read + interleave. | ✅ **HW-validated 2026-06-10** — JEDEC ID = Micron MT25QU512; 64 KB dump **MD5-identical** to the known boot image. (DMA-accel mode parked.) |

### C2 — Offline analysis & build tools (✅ all ran this session)

| Tool | What it does / produces | Verified by |
|---|---|---|
| `parse-bootimage.py` | Offline boot-image parser: BH → IHT → PHT, per-partition encrypt/auth + rule engine. | parsed real `dumps/sd-extract/BOOT.BIN` (6 partitions, unencrypted, `AUTH_ONLY=0`) + golden |
| `hexdump-attributes.py` | Annotated register hexdump (addr · LE bytes · fields) from a capture. | ran on the live `raw-2026-06-10` capture |
| `bootrom.py` | Analyze / summarize BootROM dumps produced by `dump-bootrom.tcl`. | ran on real `dumps/bootrom-via-pmu-r5-bootrom-*.bin` |
| `generate-mock-seed.py` | Turn a real raw JSON into a Tcl seed for the offline mock harness. | ran on the real capture |
| `psu-init-to-jtag.py` | Turn `psu_init_gpl.c` into the JTAG MMIO replay (`psu-init-replay.tcl`). | regenerated from real `references/.../psu_init_gpl.c` |
| `regenerate-qemu-regs.py` | Regenerate `lib/zynqmp-regs-qemu.tcl` from the Xilinx QEMU register model. | enumerated registers from the QEMU source tree |
| `build-vxboot/build_vxworks_zcu102.py` | Build the VxWorks boot images (`--no-net` reproduces v5p). | reproduces v5p/v5pg3 byte-identical (smoketest) |
| `payloads/` (Makefile + `.S`) | Bare-metal payloads, two toolchains (AArch64 + ARMv7-R). | `make` built 13 `.bin`; `make check` clean |
| `verify-addresses.py`, `check-annotations.py` | Register-address + annotation consistency self-tests. | full runs OK (also in the smoketest) |
| `tcl-smoketest.sh` + `golden-test*.sh` + `test-bootimage.sh` + `*-smoketest.sh` | The offline test harness. | 9 PASS |

### C3 — Libraries (`openocd/lib/`, `tools/interpret_lib.py`)

Not standalone-runnable; validated through their consumers. `zynqmp-regs-qemu/-extension`,
`zynqmp-variants`, `idcode-lookup` → proven by `verify-addresses` + the enumerate roundtrip + the
probe-board run. `enum-helpers`, `json-emit`, `mock-openocd` → proven by the roundtrip golden.
`dump-memory`, `release-recipes`, `research-pmu`, `board-baselines` → exercised by the dump
smoketests. `interpret_lib.py` → proven by the interpret golden.

### C4 — Live-kernel patch demos

| Script | Status |
|---|---|
| `probe-phys-patch.tcl` | ✅ **hardware-validated 2026-06-10** — on a running VxWorks SMP kernel: halted core-0, read `pc` (`0xffffffff803ed870`, EL1/MMU-on), `virt2phys`→PA `0x003ed870`, then **physically wrote a NOP via the AXI-AP and it took (`PHYS_WRITE_BYPASS=1`)**, defeating the MMU stage-1 RO `.text` permission; original instruction (`0xb4ffffe8`) restored. Proves arbitrary live-kernel code patching over the open DAP. (Fixed during validation: the script no longer reads through the core — a core-mediated VA read faults at EL1 and wedges the A53 DTR; it now uses the AXI-AP physical path only, which is the actual proof.) |
| `probe-va-write.tcl` | ⚠ unverified — its sibling; reads/writes through the **core (VA) path**, which we found *faults at EL1* (`DSCR.ERR`) on a running OS. The physical-write bypass is proven by `probe-phys-patch`; the VA-path variant is superseded for that purpose. |

### C5 — Hardened-target debug re-open (the unlock workflow)

The offensive counterpart to the posture detector: where the detector reports *which* debug gates
are closed, this **re-opens whatever isn't eFuse-locked** and tells you which kind of hardening you
face.

| Script | Status |
|---|---|
| `reopen-debug.tcl` | ✅ **hardware-validated 2026-06-10** — reads `CSU.JTAG_SEC` (`0xFFCA0038`) + `JTAG_DAP_CFG` (`0xFFCA003C`), writes them back to the all-open state (`JTAG_SEC.*_SEC→0b111`, `JTAG_DAP_CFG→0xFF`) via the **AXI-AP**, and **reads back to confirm the write stuck**. On the dev board: `JTAG_SEC 0x3F→0x1FF` (PMU_SEC `0→7`, held), `JTAG_DAP_CFG 0xFF→0xFF` → **VERDICT: DEBUG RE-OPENED**. The read-back is also a **diagnostic** — write-sticks ⇒ software-hardened (reversible, the common no-eFuse case); write-ignored ⇒ eFuse-locked (not reversible by register write); write-faults ⇒ no AXI-AP path (fall back to a code-exec write from EL3/EL1, e.g. `inject.tcl`). **The intended workflow on a software-hardened target whose `psu_init`/FSBL closed these gates at boot.** Opening `JTAG_SEC.PMU_SEC` re-links the gate register but does *not* unlock the eFuse-locked PMU ROM behind it (per `project_pmu_bscan_tap_attempt`) — the distinction the verdict preserves. |

