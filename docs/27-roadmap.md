# 27 — Capability Roadmap

The canonical "what's done / next / blocked" for the toolkit. The offensive story is a pipeline —
**find → understand → observe → modify → persist → report**, across **many boards**, against **real
(hardened) targets**. This tracks each phase's status. (Supersedes the stale `project_research_roadmap`
memory; the per-engagement runbook is `docs/21`, the multi-board matrix is `docs/22`.)

## Capability map (current)

| Capability | Tooling | Status |
|---|---|---|
| Identify / first contact | `probe-board.sh`, `gen-board-cfg.py`, `jtag-access-check.tcl` | ✅ |
| Posture enumeration (detector) | `enumerate.tcl` → `interpret.py` (Security Posture Summary) | ✅ live-validated baseline + offline goldens |
| Debug-gate reopen | `reopen-debug.tcl` + Tier-1 levers | ✅ HW-validated (DAP-side harden caveat documented) |
| Cap-1 Dump (DRAM / QSPI / boot image) | `dump-os-ddr.tcl`, `qspi-jtag.tcl` (PIO + DMA), `dump-boot-flash.tcl` | ✅ ~7× faster (15 MHz / 16 KB chunks) |
| Cap-1 Analyze | `parse-bootimage.py`, `ghidra-loadspec.py`, `vxworks-symtab.py`, `dram-secrets.py`, `dump-triage.py`, `symbol-crypto.py` | ✅ (`dram-secrets` 2.5× faster) |
| Cap-2 Live patch (memory R/W) | `probe-phys-patch.tcl` (+ `PATCH_HEX`), `patch-recipe.py` | ✅ HW-validated (write); behavioral in-place blocked by I-cache |
| Cap-2.5 Dynamic analysis | `break-capture.tcl` (+ backtrace), `watch-access.tcl`, `mem-search.tcl`, `symbolize.py` | ✅ HW-validated |
| Cap-3 Persist (reflash over JTAG) | `repack-bootimage.py`, `qspi-make-patch.py`, `qspi-write.tcl` (erase/program/verify) | ✅ proven end-to-end through power-cycle |
| Multi-board (16 profiles, 5 paradigms) | `board-runner.py`, `profiles/*.json` | ✅ ZynqMP HW-validated; others doc-cited |
| Intel & reporting | `cve-match.py`, `engagement-report.py` | ✅ |
| Standalone air-gapped kit | `make-standalone-package.sh` → `dist/jtag-engagement-kit.tar.gz` | ✅ self-sufficient |

## Phases

- **Phase 1 — Persistence loop · ✅ DONE.** dump → map VA→bootimage offset → patch+repack (offline) →
  JTAG-native QSPI erase/program/verify → power-cycle → patched image boots. Proven on the ZCU102: `ret0`
  into a VxWorks auth function survived a full power-off (`project_qspi_jtag_writer`). Built the QSPI **writer**
  (was the deferred Phase 4) safe-first.
- **Phase 2 — Dynamic-analysis depth · ✅ DONE.** Backtrace (FP-chain unwind via coherent core reads) +
  `symbolize.py` + a register-read bugfix (`reg` not `get_reg`); multi-breakpoint tracer (BC_ADDR list, up to
  6 HW bps, `BC_TRACE`) + conditional capture (`BC_COND="xN ==|!= VAL"`). Caveat: multi-bp interleaving across
  a tight caller/callee pair is limited by OpenOCD's SMP step-over (re-arms only the halt-PC bp) — reliable
  for independent functions + single-fn capture/backtrace/conditional.
- **Phase 3 — Hardened-target validation · ✅ DONE (as far as this board allows).** Posture detector validated
  on live silicon at the all-open baseline (every register read correct). Findings: DAP-side gate harden
  self-locks (POR-only recovery); `SEC_CTRL` is read-only eFuse reflection. A *live hardened* enumeration
  isn't achievable on a no-eFuse dev board (software harden self-locks or is POR-volatile; eFuses are
  irreversible) → hardened path stays covered by the offline golden fixtures (`project_phase3_hardening_finding`).
- **Phase 4 — JTAG QSPI writer · ✅ DONE** (pulled into Phase 1).
- **Phase 5 — Coverage & consolidation · ◑ IN PROGRESS.** This doc + the `docs/21` Cap-2.5/Cap-3 sections are
  the consolidation. Remaining: second-paradigm HW validation (needs a Zynq-7000 / Pi / STM32 board);
  expand `cve-match` DB.

## Known structural limits (not tool gaps)

- **No real hardened board** — the all-open dev board can't hold a persistent hardened posture JTAG can still
  read without blowing eFuses (irreversible). Hardened decode is covered by offline fixtures.
- **Live coherent in-place patch** — needs cache maintenance on a borrowed core, which wedges the DAP on
  ZynqMP/OpenOCD 0.12. Cap-3 reflash is the behavioral-patch path.
- **CSU/PMU BootROM + family key** — resolved infeasible over JTAG (internal to the CSU SPB, not AXI-mapped).
- **Fault-injection attacks** (nRF/ESP32 glitch in `cve-match`) — need glitch gear; out of pure-JTAG scope.

## Process lessons (the board-handling rules)

- Never `kill -9` openocd mid-MPSSE → wedges the FT232H at USB level; in-guest resets don't work under VMware
  passthrough (host-level Disconnect/Connect only). Use SIGTERM / `timeout`.
- DAP wedge (`Invalid ACK`) clears on fresh `init`; the JTAG_DAP_CFG=0 self-lock needs POR.
- AXI mem-AP reads DRAM, not the A53 write-back cache — hot/freshly-written data reads stale; use the core
  (halted) for coherent reads, registers/watchpoints for live values.
