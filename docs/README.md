# JTAG Research on AMD Zynq UltraScale+ MPSoC (ZCU102)

This documentation covers a JTAG research rig for the AMD ZCU102 evaluation
kit (XCZU9EG SoC), built with open-source tools on Kali Linux. The workflow
enumerates and characterizes the platform's silicon/security state over raw
JTAG (no vendor toolchain), and drives capability experiments (BootROM/PMU
dumps, A53/R5 bring-up, PMU IPI) on a known board.

> **Status note (2026-06-08):** an earlier disclosure track (4 findings to AMD
> PSIRT) was **retracted** — AMD closed the case as expected behavior on a
> factory/dev board with no security bits provisioned (the open JTAG DAP *is*
> the trust boundary). The project premise is now **platform characterization,
> not vulnerability finding.** `../submission-build/` is kept as historical
> record only.

## Why JTAG

JTAG is the most powerful debug interface on a modern SoC — it bypasses the OS,
reaches every CPU at the hardware level, and can read/write any address the SoC
can. On evaluation kits and unprovisioned silicon it is open by design (for
validation and bring-up). On hardened production silicon it is closed via the
`JTAG_DIS` eFuse or gated by debug authentication. This rig characterizes, in
concrete register-level terms, exactly what an open DAP exposes on a dev board.

## Document layout

These docs are the **lean working reference**. The narrative — platform/ZynqMP
background, methodology walkthrough, and lab/hardware setup — lives in the
[whitepaper series](whitepaper/README.md) (Volume 1 Foundation, Volume 2 Workflow,
Volume 3 What Enumeration Reveals, and the lab-setup companion).

| Doc | Covers |
|-----|--------|
| **[05-enumeration-tool.md](05-enumeration-tool.md)** | The `enumerate.tcl` + `interpret.py` capture/interpret pipeline, the security-posture reads, and how to read the report. The stylized operator-first HTML view is `tools/report-html.py`. |
| **[11-enumerated-attributes.md](11-enumerated-attributes.md)** | **Catalog of every enumerated attribute** — location, dev value, hardened meaning, why we care. The data dictionary behind the Security Posture Summary. |
| **[12-secureboot-internals.md](12-secureboot-internals.md)** | Cited reference on ZynqMP secure-boot internals: BootROM (not dumpable — it's internal to the CSU; 0xFFFC0000 is OCM/FSBL), key hierarchy, PUF, bootgen. |
| **[13-attack-research-plan.md](13-attack-research-plan.md)** | Offensive research plan: vectors to dump the CSU BootROM + extract the family/gray key, by feasibility tier; the Tier-1 `probe-csu-surface.tcl`. |
| **[14-zynqmp-internals.md](14-zynqmp-internals.md)** | **Comprehensive secure-boot internals reference** — 10 subsystems (boot flow, CSU+crypto, FSBL, PMU/PM-API, PUF, key hierarchy, bootgen, eFuse/BBRAM, XMPU/XPPU, JTAG/debug) synthesized from the local `references/` corpus + our findings. Separates vendor-documented vs empirically-established, with cross-section contradictions flagged. |
| **[15-prior-research.md](15-prior-research.md)** | **Survey of published ZU+/ZynqMP & JTAG security research and CVEs** (CVE-2019-5478 Encrypt-Only bypass, CVE-2023-20570 JustSTART RSA bypass, Cautionary-Note GHASH attacks, Starbleed, ZU+ EM side-channel, AMD-SB-8017). Each mapped to applicability + what it means for our posture detector. The "outside view." |
| **[09-discover-tool.md](09-discover-tool.md)** | `discover.tcl` — optional JTAG-chain sanity check (confirm IDCODEs before trusting enumerate output) |
| **[04-jtag-research-techniques.md](04-jtag-research-techniques.md)** | Passive AXI reads, releasing the A53 over raw JTAG, payload execution |
| **[16-jtag-ddr-bringup.md](16-jtag-ddr-bringup.md)** | Bringing up DDR over pure JTAG by replaying psu_init as MMIO (sidesteps the FSBL-execution DAP wedge); U-Boot-over-JTAG |
| **[17-vxworks-zcu102-bringup.md](17-vxworks-zcu102-bringup.md)** | From-scratch VxWorks 7 boot-image build for the stock ZCU102 (`build-vxboot/`), with the reproducible recipe |
| **[18-new-board-bringup.md](18-new-board-bringup.md)** | **New-board engagement runbook** — taking an unfamiliar production/tactical board from bench to characterized posture (physical → access verdict → enumeration → capability tests). Uses `board-template.cfg` + `jtag-access-check.tcl`. |
| **[19-script-walkthrough.md](19-script-walkthrough.md)** | **Phase-by-phase reference** for the whole toolkit — what each script does, reads, produces, and where it stops. Phase A–B = the probe→enumerate pipeline; Phase C = capability/dump/support tools, each with a verification status (ran offline / hardware-validated / unverified demo). |
| **[20-bootrom-fuzzing.md](20-bootrom-fuzzing.md)** | **BootROM boot-header fuzzing harness** (the checkm8-model ROM-dump path) — black-box fuzz the CSU BootROM's BH/IHT/PHT parser via malformed boot images, observe the reaction over JTAG, triage for memory-corruption signatures. `bootrom-fuzz-gen.py` + `bootrom-fuzz-observe.tcl` + `bootrom-fuzz-triage.py`. |
| **[21-engagement-walkthrough.md](21-engagement-walkthrough.md)** | **The end-to-end engagement runbook** — Phase 0–3 (connect → enumerate → reopen → profile) then Cap-1 (extract/analyze), Cap-2 (live memory R/W), **Cap-2.5 (dynamic analysis: args/backtrace/watchpoints)**, **Cap-3 (persist: reflash the boot image over JTAG)**. The day-to-day driver. |
| **[22](22-multiboard-capability-matrix.md)–[26](26-unknown-board-walkthrough.md)** | Multi-board engine: capability matrix, engagement runbook, per-chip attribute catalogs (Zynq-7000, Cortex-M/Pi), unknown-board walkthrough. |
| **[28](28-g3-hwserver-bench-checklist.md)–[29](29-sf2-m3-bench-checklist.md)** | Bench-validation checklists (hw_server bring-up, SmartFusion2 M3). |
| **[30-authenticated-debug.md](30-authenticated-debug.md)** | The authenticated-debug posture class (ARM SDC-600 / RISC-V debug-auth). Modeled cross-arch by `jtagx/debugauth.py` (OPEN/GATED/AUTHENTICATED/LOCKED). |
| **[31-deepening-plan.md](31-deepening-plan.md)** | **The spec/board/adapter deepening plan (Phases 1–5, all ✅)** — ZynqMP posture depth, cross-arch CoreSight + debug-auth, adapters/transport, board-family unlock/extraction, breadth. Research-backed with cited addresses. |
| **[32-first-contact-troubleshooting.md](32-first-contact-troubleshooting.md)** | **First-contact decision tree** — symptom→cause→fix for every way an adapter / no-chain dead-ends first contact (the FlashPro engagement blocker codified). Generated from `jtagx/firstcontact.py`; run `tools/first-contact.py "<symptom>"`. |
| **[27-roadmap.md](27-roadmap.md)** | **Capability roadmap** — what's done / next / blocked across the find→understand→observe→modify→persist→report pipeline; phase status; structural limits; board-handling lessons. Start here for "where is the project." |
| **[guides/operator-quick-reference.md](guides/operator-quick-reference.md)** | One-page operator cheat-sheet |
| **[guides/gui-quick-reference.md](guides/gui-quick-reference.md)** | One-page GUI operator reference (pages, console, cross-links, shortcuts) |

Appendices:

| Doc | Covers |
|-----|--------|
| **[appendix-a-recovery.md](appendix-a-recovery.md)** | DAP-wedge recovery, USB passthrough fixes, board power-cycle |
| **[appendix-b-references.md](appendix-b-references.md)** | AMD docs (UG1085/1087/1182/1137), OpenOCD references |

*(Consolidated 2026-06-08: the former `01-project-overview`, `02-hardware-bringup`,
`03-openocd-setup`, and `guides/jtag-enumeration-explainer` duplicated the whitepaper
and were removed — that material now has a single home in the whitepaper. The
unknown-board docs `06/07/08/10` were removed earlier with their tooling.)*

## Project directory layout

```
JTAG/
├── docs/                                  # this documentation
│   ├── annotations/{zynqmp_security,zynqmp_general}.py   # field annotations (interpret.py deps)
│   ├── findings/zynqmp_rules.py           # cross-register rules (interpret.py dep)
│   └── whitepaper/                        # narrative whitepaper (md+pdf+docx) — partly stale
├── tools/
│   ├── interpret.py / interpret_lib.py    # raw JSON → annotated report
│   ├── bootrom.py                         # analyze/summarize BootROM dumps
│   ├── regenerate-qemu-regs.py            # regenerate lib/zynqmp-regs-qemu.tcl
│   ├── generate-mock-seed.py              # raw JSON → Tcl seed for mock harness
│   ├── check-annotations.py / verify-addresses.py        # offline validators
│   └── tcl-smoketest.sh / golden-test*.sh / dump-*-smoketest.sh   # test suite
├── openocd/
│   ├── zcu102.cfg                         # board config (2-TAP)
│   ├── zcu102-3tap.cfg                    # board config (PMU BSCAN TAP variant)
│   ├── enumerate.tcl                      # THE enumeration script (17 sections)
│   ├── discover.tcl                       # optional JTAG-chain sanity check
│   ├── dump-bootrom.tcl / dump-pmu.tcl    # capability: BootROM / PMU memory extraction
│   ├── inject.tcl                         # capability: generic binary injector
│   ├── probe-{phys-patch,va-write}.tcl    # capability: kernel-patch demos
│   └── lib/                               # enum-helpers, json-emit, mock-openocd,
│                                          #   zynqmp-regs-qemu/-extension, zynqmp-variants,
│                                          #   release-recipes, dump-memory, board-baselines,
│                                          #   idcode-lookup, research-pmu (Phase-7 methods)
├── payloads/                              # bare-metal payloads (A53 AArch64 + R5 ARMv7-R)
├── reports/                               # enumeration outputs (per-run timestamped)
├── tests/golden/zcu102-jtag-idle/         # frozen capture + expected reports
└── dumps/ , logs/                         # dump artifacts, serial captures
```

## Quick start (known board)

The enumeration is two phases — capture (Tcl, talks to silicon) and interpret
(Python, applies annotations + rules):

```
cd /home/kali/Desktop/research/JTAG

# Optional: confirm the JTAG chain matches expectation before trusting output
openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"

# 1. Capture → reports/enumerate-<ts>.md + reports/raw-<ts>.json
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"

# 2. Interpret → reports/interpreted-<ts>.md
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
#   add --full for the archival-verbose layout
```

See **[05-enumeration-tool.md](05-enumeration-tool.md)** for the capture/interpret
architecture and how to read the report.
