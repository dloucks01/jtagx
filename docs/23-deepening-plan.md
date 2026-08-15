# docs/23 — Deepening Plan: Spec / Board / Adapter Coverage

**Status:** proposed (2026-08-15). Research-backed; not yet implemented.
**Scope order (per operator):** ① Zynq + Cortex/CoreSight depth → ② adapters/transport
(the engagement blocker) → ③ everything else (board families).
**Raw research + citations:** `reports/research/raw-findings.md`.
**Explicitly out of scope:** fault injection / glitching and side-channel (physical rig).
FI *bypasses* are still **named** as strategies (e.g. nRF52 CVE-2020-27211) but no rig work.

Ground truth confirmed this round (concrete addresses, not guesses):

| What | Confirmed fact | Source |
|---|---|---|
| ZynqMP JTAG gates | `CSU_JTAG_SEC` 0xFFCA0038, `CSU_JTAG_DAP_CFG` 0xFFCA003C, `CSU_JTAG_CHAIN_CFG` 0xFFCA0030, `CSU_PCAP_PROG_REG` 0xFFCA3000 | AMD wiki AR68391 / UG1087 |  <!-- verify-addresses:skip (multi-pair prose row; canonical enforced in code) -->
| ZynqMP LPD debug | `CRL_APB_DBG_LPD_CTRL` 0xFF5E00B0, `CRL_APB_RST_LPD_DBG` 0xFF5E0240 | AMD wiki |  <!-- verify-addresses:skip -->
| — LPD debug detail | `DBG_LPD_CTRL` 0xFF5E00B0 clocks the debug fabric; `RST_LPD_DBG` 0xFF5E0240 resets it | AMD wiki |  <!-- verify-addresses:skip -->
| ZynqMP eFuse gates | ENC_ONLY, JTAG_DIS, DFT_DIS, RSA_EN, PPK0/1 + revoke, AES_RD_LOCK, SEC_LOCK, PUF | XAPP1319 v2.1 / xilskey_epl.h |
| A53 debug-auth | `DBGAUTHSTATUS_EL1` (SNID/SID/NSNID/NSID pairs), `EDPRSR` (EDAD/OSLK/powered), `EDSCR`, `OSLAR/OSLSR_EL1` | Arm DDI0487 / DDI0601 |
| CoreSight discovery | CIDR1[7:4] class 0x1=ROM table / 0x9=component; PIDR0-7 + CIDR0-3 at 0xFC0–0xFFC; MEM-AP BASE → root ROM table; ADIv6 base-pointer | Arm IHI0029 / CSAL |
| FlashPro blocker | FTDI silicon **under proprietary firmware**; stock OpenOCD can't drive it — needs Microsemi's **patched** OpenOCD + `ftdi_sio` unbind (+ fpServer on Win) | Microsemi SoftConsole docs |
| RISC-V extract | `DMSTATUS.authenticated/authbusy` = debug-auth gate; **SBA** (sbcs/sbaddress/sbdata) = mem dump with no hart | riscv-debug 0.13/1.0 |
| Kinetis lever | `kinetis mdm mass_erase` (MDM-AP, no halt); MDM-AP Status bit2 = secured; FSEC[KEYEN] backdoor | OpenOCD kinetis.c / AN4507 |
| i.MX extract | SDP USB-HID BootROM loader (imx_usb/uuu) — no debug port; SJC challenge-response JTAG gate | Quarkslab / u-boot SDP |
| ESP32 posture | eFuses SPI_BOOT_CRYPT_CNT / SECURE_BOOT_EN / DISABLE_DL_ENCRYPT — flash-enc defeats naive read | ESP-IDF security docs |

---

## Phase 1 — ZynqMP posture depth  *(mission-core; all read-only)*

The current detector reads a handful of security regs + a single DBGEN-style gate. Deepen it
to the **full** ZynqMP debug/JTAG/eFuse surface with correct addresses.

1.1 **JTAG/DAP gate cluster (new §):** add + decode `CSU_JTAG_SEC` (0xFFCA0038),
   `CSU_JTAG_DAP_CFG` (0xFFCA003C), `CSU_JTAG_CHAIN_CFG` (0xFFCA0030),  <!-- verify-addresses:skip -->
   `CSU_PCAP_PROG_REG` (0xFFCA3000), `CRL_APB_DBG_LPD_CTRL` (0xFF5E00B0),  <!-- verify-addresses:skip -->
   `CRL_APB_RST_LPD_DBG` (0xFF5E0240). For each: dev(open) vs hardened(gated) decode +
   which TAP/AP it gates (PS TAP / PL TAP / PMU MDM / ARM DAP). Verify each address against
   `zynqmp-regs-qemu.tcl` with `verify-addresses.py` (the JTAG_SEC/DAP_CFG swap-bug guard).
1.2 **eFuse SEC_CTRL cache decode:** read the eFuse *cache* mirrors (readable even when key
   values are locked) and decode JTAG_DIS / DFT_DIS / RSA_EN / ENC_ONLY / AES_RD_LOCK /
   SEC_LOCK / PPK revoke. Canonical bit names from `xilskey_epl.h`. This is the "is this the
   dev baseline or a provisioned part?" tell. Add to `docs/11-enumerated-attributes.md`.
1.3 **Per-A53 Armv8 debug-auth read (bridges into Phase 2):** for each A53, read
   `EDPRSR` first (core powered? OS-locked? external-debug-disabled?), then
   `DBGAUTHSTATUS_EL1` decoded into the 4 signal pairs (secure/non-secure × invasive/
   non-invasive), replacing the single-bit DBGEN summary. New annotation module.
1.4 **New cross-register rules** in `zynqmp_rules.py`: (a) "JTAG open but eFuse RSA_EN set"
   = misconfig/observation; (b) "secure-world debug (SID/SNID) enabled" = HIGH posture note;
   (c) "OS double-lock vs external-debug-disable" consistency check.

**Files:** `openocd/enumerate.tcl` (§debug/§jtag), `openocd/lib/zynqmp-regs-extension.tcl`,
`docs/annotations/*`, `docs/findings/zynqmp_rules.py`, `docs/11-enumerated-attributes.md`.
**Verify:** `verify-addresses.py`; a new posture-golden fixture (open baseline + a synthetic
hardened part); `tcl-smoketest.sh` stays green.

---

## Phase 2 — CoreSight / Cortex debug depth  *(cross-arch; read-only + ROM-walk)*  — ✅ DONE 2026-08-15

Turn "read one debug gate" into "discover the debug topology and its authentication state" —
applies to ZynqMP A53/R5 **and** every Cortex-M/A board.

2.1 **ADIv5/v6 ROM-table walker** (`jtagx/coresight.py`, new): given a MEM-AP, read `BASE`,
   walk the ROM table (entry present-bit + signed [31:12] offset), identify each component
   via CIDR class (0x1 ROM / 0x9 component) + PIDR (JEP106 designer + part no), recurse nested
   tables. Emits a component map (DWT/FPB/ITM/ETM/CTI/TPIU/funnel/core debug). Handle ADIv6
   (base-pointer, larger address). Drive it through OpenOCD `dap info` where possible; parse.
2.2 **Debug-auth signal model** (`jtagx/debugauth.py`, new): a cross-arch decoder for the
   authentication matrix — Armv8-A `DBGAUTHSTATUS_EL1`, Cortex-M `DHCSR`/`DEMCR` + vendor
   lock bits, RISC-V `DMSTATUS.authenticated`. Output the 3-state classification the weakness
   layer already expects: OPEN / GATED(on-off, reopenable) / AUTHENTICATED(challenge-response).
2.3 **PIDR part-number table** (`references/coresight-parts.json`): JEP106 + part-no → human
   name for common Arm IP (Cortex-M0/3/4/7/33 debug, A53/A72, CTI, ETM, CoreSight funnels),
   so the topology map is readable, not hex.
2.4 **Wire it in:** `interpret.py` shows the CoreSight map + debug-auth class; GUI Registers/
   Chain tab renders the topology; `engagement-report.py` gets a "## Debug topology" section.
2.5 **SDC-600 / authenticated-debug presence** as a posture attribute (present-but-unprovisioned
   = same failure mode as unprovisioned FlashLock) — extends existing `weakness.py` auth-debug
   hypotheses to be driven by the real `DBGAUTHSTATUS`/`DMSTATUS` reads instead of a flag.

**Files:** `jtagx/coresight.py`, `jtagx/debugauth.py`, `references/coresight-parts.json`,
`tools/interpret.py`, `jtagx/weakness.py`, `openocd/coresight-topology.tcl` (exists — extend),
GUI chain page. **Verify:** a mock ROM-table fixture round-trips to the right component list in
a new smoketest; debug-auth decoder golden test for the 4-signal matrix.

---

## Phase 3 — Adapters & transport  *(THE engagement blocker — highest practical value)*  — ✅ DONE 2026-08-15

Root cause from the field: the toolkit only speaks OpenOCD, and FlashPro (and some vendor
cables) are **not OpenOCD-drivable**. Fix = an honest multi-backend abstraction + a preflight
that catches every first-contact blocker *before* the operator is stuck.

3.1 **Backend capability matrix → adapter reality** (`jtagx/transport/matrix.py` extend):
   add an **adapter → backend → reachable-targets → OpenOCD-drivable?** table:
   - FTDI (FT2232H/FT232H/FT4232H, Olimex, Digilent HS2/HS3) → openocd `ftdi` ✓
   - CMSIS-DAP (v1 HID / v2 bulk, DAPLink) → openocd `cmsis-dap` ✓
   - J-Link (+clones) → openocd `jlink` ✓ (note licensing)
   - ST-Link v2/v3 → openocd `hla`/`dapdirect` ✓ (SWD, STM-centric)
   - Xilinx SmartLynq / Platform Cable USB II → **hw_server/XSDB** backend (OpenOCD weak) ✗
   - **FlashPro FP3/4/5 → Microsemi patched-OpenOCD / FlashPro Express** ✗ (stock OpenOCD)
   - openFPGALoader / pyftdi → alt FTDI backends for FPGA/edge cases
3.2 **FlashPro workaround, codified** (`openocd/adapters/flashpro-notes.md` + a backend entry):
   document that FlashPro is FTDI-under-proprietary-firmware; the Linux recipe = unbind
   `ftdi_sio` (udev rule) + use Microsemi's bundled OpenOCD, OR fall back to FlashPro Express
   for program/verify. The tool should **detect a FlashPro by USB VID/PID and route the
   operator to this path instead of silently failing.**
3.3 **Preflight, deepened** (`jtagx/preflight.py` + `tools/preflight.py`): add checks for the
   full blocker checklist (each: how to DETECT + how to WORK AROUND):
   - proprietary adapter (FlashPro/SmartLynq) plugged → wrong backend
   - connector/pinout mismatch (Arm 20-pin vs Cortex 10-pin 1.27mm vs Xilinx 14-pin PL vs TI)
   - Vref/target-voltage absent or wrong (1.8 vs 3.3) — adapters that don't sense Vref
   - clock too high (speed-ladder), missing SRST/TRST, reset polarity (the "NRST inverted" bug)
   - target held in reset / needs `connect_under_reset` (locked parts, boot-mode straps)
   - DAP powered down (CDBGPWRUPREQ/ack), unexpected multi-TAP IR lengths, eFuse-disabled JTAG
   - host: udev/libusb perms, VMware USB passthrough (Kali-in-VM), `ftdi_sio` conflict
3.4 **First-contact decision tree** (`docs/24-first-contact-troubleshooting.md` + a
   `tools/first-contact.py` that walks it): symptom → likely cause → concrete fix, so an
   engagement never dead-ends on "adapter didn't work."
3.5 **Reset/transport levers in the cfgs:** template `reset_config` options + a documented
   `connect_under_reset` path for parts that wedge the DAP once firmware runs (STM32, and the
   ZynqMP "core code-exec wedges the DAP" note we already have).

**Files:** `jtagx/transport/matrix.py`, `jtagx/preflight.py`, `tools/preflight.py`,
`tools/first-contact.py` (new), `openocd/adapters/*`, `docs/24-*.md`, GUI Chain preflight panel.
**Verify:** `preflight` smoketest gains FlashPro-detected + Vref-missing + wrong-connector
scenarios (all offline, mocked USB tables); capability-matrix smoketest asserts the
OpenOCD-drivable ✗ rows route to the right backend.

---

## Phase 4 — Board-family unlock/extraction depth  *(the "rest"; reuses our lever pattern)*

Promote thin families with **real** register-level levers (destructive mass-erase = debug, not
the image — the honest gating we already do). One consolidated pass; the board-families research
agent was killed by the safeguard, so this uses the direct-research facts above + existing depth.

- **Kinetis:** real lever = MDM-AP `mass_erase` (Status bit2 secured; no halt); note FSEC[KEYEN]
  backdoor. `unlock.py` `lock_kinetis` + `openocd/kinetis-recover.tcl` (exist — verify against
  OpenOCD `kinetis mdm mass_erase`).
- **i.MX 6/7/8:** extraction avenue = **SDP** (imx_usb/uuu) — ROM loader, no debug port; posture
  = HAB open/closed + SJC JTAG mode. Add SDP to `extraction.py` ROM_LOADER with runnable cmd;
  add SJC gate to posture; cve-match entry for Quarkslab HAB bypass.
- **ESP32/C3:** posture from eFuses (SPI_BOOT_CRYPT_CNT / SECURE_BOOT_EN / DISABLE_DL_*);
  extraction caveat = flash-enc defeats naive `esptool read_flash`; C3 adds RISC-V DM + USB-JTAG.
- **RISC-V vendors (SiFive/ESP32-C3/CH32V/Bouffalo/Kendryte):** extraction = **SBA**
  (sbcs/sbaddress/sbdata) mem dump; posture = `DMSTATUS.authenticated`. New
  `openocd/riscv-sba-dump.tcl` + extraction entry.
- **nRF52/53:** keep CTRL-AP `ERASEALL` as the non-glitch lever; **name** CVE-2020-27211 glitch
  as a (deferred) FI strategy only; note nRF52-rev3/nRF53 re-lock-per-power-cycle behavior.
- **LPC (optional new profile):** CRP levels 1/2/3 + ISP mass-erase lever; CRP1 partial-bypass
  research as a cve-match note.

**Files:** `jtagx/unlock.py`, `jtagx/extraction.py`, `jtagx/cve.py`, `profiles/*.json`,
`openocd/{kinetis-recover,riscv-sba-dump}.tcl`, `tools/mock-openocd.py` scenarios.
**Verify:** `unlock-engine-smoketest.sh` + `board-runner --validate`; coverage chart regenerates
(more families → bench-ready); each lever mock-rehearses reopen→verify.

---

## Cross-cutting

- **Every address verified** through `zynqmp-regs-qemu.tcl` + `verify-addresses.py` before use
  (this is the discipline that caught the JTAG_SEC/DAP_CFG swap once already).
- **HW-UNVALIDATED tags** on all new levers until a bench pass (operator drives live JTAG).
- **`tcl-smoketest.sh` stays exit 0** (26 sub-suites now; each phase adds its own).
- **Docs are living** — reconcile `docs/11`/`14`/whitepaper on an explicit pass, not per-commit.
- **Coverage chart + engagement-report** regenerate from live data at the end of each phase.

## Suggested sequencing
Phase 1 → Phase 2 (they share the debug-auth read) → Phase 3 (independent, highest field value,
can run in parallel) → Phase 4 (breadth). Recommend **1+2 first** (deepens the flagship ZynqMP +
Cortex story), then **3** before the next engagement, then **4** as ongoing breadth.
