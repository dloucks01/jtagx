# JTAG Platform-Characterization Toolkit — AMD Zynq UltraScale+ MPSoC (ZCU102)

A reproducible, OpenOCD-driven toolkit that **enumerates and characterizes the silicon and
security state** of the AMD ZCU102 evaluation kit (XCZU9EG) over raw JTAG — no vendor
toolchain (Vitis/Vivado) required. Everything talks to silicon through open-source tooling
on Kali Linux.

> **Scope (2026-06-08):** the project premise is **platform characterization, not
> vulnerability finding.** An earlier disclosure track (4 findings to AMD PSIRT) was
> **retracted** — AMD closed the case as expected behavior on a factory/dev board with no
> security bits provisioned (the open JTAG DAP *is* the trust boundary on this part). The
> PUF/AES/hash *observations* remain factually correct; they were never vulnerabilities.
> `submission-build/` is kept as historical record only.

## What it does

`enumerate.tcl` reads every location where a ZynqMP security implementation *would* live
(secure-boot policy, key state, JTAG/debug gates, anti-tamper, eFuse locks, TrustZone), and
the Python interpreter emits a **Security Posture Summary** — an `OFF/dev → ON/provisioned`
checklist per implementation. This dev board is the **all-open baseline** (everything reads
OFF); the same script lights up a hardened board. The toolkit also drives capability
experiments: BootROM/PMU dump attempts, A53/R5 bring-up, PMU IPI, JTAG-only DDR bring-up,
and a from-scratch VxWorks 7 boot image build.

## Repository map

| Path | What's in it |
|------|--------------|
| `openocd/`        | OpenOCD Tcl scripts. **`enumerate.tcl`** is the centerpiece; plus `discover`, `jtag-access-check` (DAP open/locked verdict), `dump-bootrom`, `dump-pmu`, `inject`, `probe-*`, and the DDR/U-Boot bring-up scripts (`jtag-ddr-boot`, `psu-init-replay`, `jtag-load-uboot`). `lib/` holds the register knowledge base + mock harness. Board configs: `zcu102.cfg`, `zcu102-3tap.cfg`, `board-template.cfg` (adapter-agnostic). |
| `tools/`          | Python + shell. `interpret.py` (raw JSON → annotated report), `parse-bootimage.py`, `verify-addresses.py`, `regenerate-qemu-regs.py`, and the offline test/smoketest runners. |
| `payloads/`       | Bare-metal code injected over JTAG (`.S` → `.bin`, two toolchains). Built via `make -C payloads`. |
| `docs/`           | Working reference (numbered `04`–`17`) + `whitepaper/` (narrative deliverable) + `annotations/` (per-field register meaning) + `findings/` (rule engine). Start at `docs/README.md`. |
| `tests/`          | Golden tests + unit tests, all offline (replay frozen captures through the mock harness). |
| `references/`     | Vendor PDFs (UG1085 TRM, UG1283 bootgen, …) + sparse Xilinx source. Index: `references/README.md`. |
| `build-vxboot/`   | VxWorks 7 boot-image build. `build_vxworks_zcu102.py` reproduces the images; `vxworks-BOOT-v5p.bin` (SD) and `vxworks-BOOT-v5pg3.bin` (QSPI) are the validated outputs. |
| `dumps/`          | Captured artifacts (SD boot-file extract, BootROM/PMU/OCM dumps, disassembly). |
| `reports/`        | Latest enumeration capture set (`enumerate`/`interpreted`/`raw`). Disposable history. |
| `submission-build/` | Retracted AMD PSIRT package — historical record only. |
| `_archive/`       | Superseded scripts, intermediate build artifacts, and old captures. Nothing live; see `_archive/README.md`. |

This `README.md` is the human entry point / directory map; `docs/` holds the full
architecture, command reference, and doc index.

## Quick start

```bash
# Offline test suite — run before changing enumerate.tcl / helpers / annotations
tools/tcl-smoketest.sh

# Live capture (the operator runs these on the board)
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"

# Interpret the newest raw capture (offline, safe)
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O

# Build all bare-metal payloads
make -C payloads
```

## Hardware model

The **operator drives all live JTAG/OpenOCD commands** — this toolkit writes the Tcl scripts
and payloads and hands them off; offline work (tests, payload builds, analysis) runs directly.
Target board S/N `210308BD8D4D`. ZCU102 serial map: `ttyUSB0`=PS UART0, `ttyUSB3`=System
Controller, `ttyUSB4`=JTAG.

## New / unfamiliar board?

For an engagement against a board that *isn't* the known ZCU102 (different adapter, possibly
hardened silicon), start with **`docs/18-new-board-bringup.md`** — the stage-by-stage runbook
(physical → transport → chain ID → access verdict → enumeration → capability tests). It uses
`openocd/board-template.cfg` (adapter-agnostic) and `openocd/jtag-access-check.tcl` (is the DAP
open or locked?) rather than the ZCU102-hardwired config.

For the **full end-to-end engagement playbook** — connect → understand → open → extract the firmware →
own the live system, with every command — see **`docs/21-engagement-walkthrough.md`** (chains
`probe-board.sh` → `enumerate`/`interpret` → `reopen-debug` → `harvest-profile` → `qspi-jtag` flash dump
→ `parse-bootimage --extract` → `ghidra-loadspec`/`vxworks-symtab` → Ghidra → `probe-phys-patch`
live-kernel patch).

See the **`docs/`** directory (start at `docs/README.md`) for the full architecture,
command reference, Tcl gotchas, and doc index.
