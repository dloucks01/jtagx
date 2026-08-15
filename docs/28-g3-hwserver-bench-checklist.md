# 28 — G3 Bench Checklist: SmartLynq2 / hw_server / xsdb validation

**Goal.** Prove the `hw_server` transport backend (P2/P3) works against real silicon over the
adapter that FAILED the original engagement (AMD SmartLynq2 / Platform Cable), and confirm our
`targets` PARSER matches real xsdb output. Everything below is command-correct today but **unvalidated
against a real hw_server** — this is the session that closes that gap.

Related: `project_adapter_transport_gap` (memory), `docs/22` (multi-board), `jtagx/transport/`.

---

## 0. Preconditions (do before touching the board)

- [ ] ZCU102 powered; SmartLynq2 (or Platform Cable USB II) cabled to the PS JTAG header.
- [ ] Vitis installed — `xsdb` and `hw_server` on PATH (this rig: `~/Downloads/2026.1/Vitis/bin`).
      `export PATH="$HOME/Downloads/2026.1/Vitis/bin:$PATH"; which xsdb hw_server`
- [ ] VMware USB passthrough: the SmartLynq2 shows in `lsusb` inside Kali
      (`03fd:0100` SmartLynq / `03fd:0008` Platform Cable). If absent → fix passthrough first.
- [ ] **DAP not wedged**: if a prior session left the DAP in the garbage-IDCODE / Invalid-ACK state,
      power-cycle the board before starting.
- [ ] Scratch dir for artifacts: `mkdir -p /tmp/g3 && cd <repo>`

> **Rehearse first (offline).** Every parser/dump step below can be dry-run right now against the
> high-fidelity mock, so you arrive knowing the expected shapes:
> `bash tools/mock-xsdb-smoketest.sh` — and for the transport commands,
> `JTAGX_XSDB=$PWD/tools/mock-xsdb.py python3 tools/transport-probe.py --profile zynqmp --backend hw_server --targets`.

---

## 1. Bring up hw_server and confirm it owns the adapter

```bash
hw_server            # foreground; leave running in its own terminal
```
- [ ] **PASS** if it prints a listening line (`... TCP:...:3121`) and, on connect (next step), enumerates
      the SmartLynq2. **FAIL** → adapter/passthrough/driver problem; do not proceed.

## 2. Capture the REAL `targets` tree (the parser-validation artifact)

```bash
xsdb -eval "connect; targets" | tee /tmp/g3/targets.txt
```
- [ ] **PASS** if it lists PS TAP / PMU / PL / PSU / RPU→R5×2 / APU→A53×4 with ids + `(state)`.
- [ ] Keep `/tmp/g3/targets.txt` — it is the ground-truth artifact for step 3.

## 3. Validate our parser against the real output

```bash
python3 tools/transport-probe.py --profile zynqmp --backend hw_server --targets-file /tmp/g3/targets.txt
```
- [ ] **PASS** if the rendered tree shows the cores with correct roles (A53×4, R5×2, PMU, PL) and
      A53 #0 resolves. Compare against `jtagx/transport/targets.ZYNQMP_TARGETS_REF`.
- [ ] **On mismatch** (different indentation width, extra columns, different state strings, a `*`
      placement we don't handle): note the exact diffs and update `parse_targets()` /
      `ZYNQMP_TARGETS_REF` in `jtagx/transport/targets.py`; re-run `bash tools/transport-smoketest.sh`.
      *This is the single most likely thing to need a fix — real xsdb formatting is the unknown.*

## 4. IDCODE cross-check (adapter actually reaches the DAP)

```bash
xsdb -eval "connect; targets -set -filter {name =~ \"*A53*#0\"}; mrd 0xFFCA0040 1"
```
- [ ] **PASS** if it returns `0x24738093` (XCZU9EG rev2 IDCODE) — the same value OpenOCD/enumerate
      reports. Confirms the SmartLynq2 path reaches the CSU over the DAP.

## 5. Memory dump via the exact command the transport EMITS

Get the command our code generates, then run it:
```bash
python3 tools/transport-probe.py --profile zynqmp --backend hw_server \
  --target a53-0 --read 0x00100000:0x00100000:/tmp/g3/ddr.bin | sed -n '/mem_read/p'
# copy the printed `xsdb -eval "..."` line and run it, OR run directly:
xsdb -eval "connect; targets -set -filter {name =~ \"*A53*#0\"}; stop; mrd -bin -file /tmp/g3/ddr.bin 0x100000 262144; con"
python3 tools/dump-triage.py /tmp/g3/ddr.bin -o /tmp/g3/triage.md   # structural sanity
```
- [ ] **PASS** if `/tmp/g3/ddr.bin` is the expected size (words×4) and triage shows real structure
      (not all-zero / not all-0xFF). **FAIL** → the core wasn't halted, wrong target, or a filter miss.

## 6. GUI end-to-end over hw_server

```bash
export JTAGX_XSDB=xsdb                 # real xsdb (mock only for rehearsal)
export JTAGX_DATA=/tmp/g3              # keep GUI outputs OFF the repo dumps/ (see caveat below)
python3 gui-spike/jtagx_app.py
```
- [ ] Top bar → **Transport = hw_server (xsdb)**; status bar shows `backend: hw_server (pinned)`.
- [ ] Dashboard → **Dump DDR / OCM** → confirm the halt dialog → console streams the `xsdb ... mrd`
      command → on completion the "open in Memory?" prompt → Memory page shows the dump.
- [ ] Chain page → click **A53 #0** in the xsdb target tree → the copied command matches step 5.
- [ ] **PASS** if the dump lands under `/tmp/g3/dumps/` and renders. OpenOCD-only caps (Break&capture,
      Live-patch, BootROM, PMU) should be **gated** with the XVC-bridge message — that's correct.

> **⚠ Data-safety caveat (learned the hard way).** Always set `JTAGX_DATA=/tmp/g3` (or another scratch
> dir) for hw_server runs so a dump can't overwrite a real capture in the repo `dumps/`
> (e.g. `os-live.bin`). In dev mode the GUI writes into the repo tree by default.

## 7. (Optional) XVC bridge — keep the OpenOCD Tcl toolchain over the SmartLynq2

If you want `enumerate.tcl` and the OpenOCD-only capabilities over a SmartLynq2 without porting them to
xsdb: bridge hw_server's XVC server to OpenOCD's `xvc` driver (see `XsdbTransport.xvc_bridge_hint()`):
```bash
# hw_server exposes XVC; point OpenOCD at it, then run the existing Tcl unchanged
openocd -c "adapter driver xvc; xvc_host 127.0.0.1; xvc_port 2542" -f openocd/zcu102.cfg \
        -c "init; source openocd/enumerate.tcl; shutdown"
```
- [ ] **PASS** if `enumerate.tcl` produces a `reports/raw-*.json` over the SmartLynq2. This is the
      fastest way to get the OpenOCD-only caps working on a vendor adapter.

---

## 8. Record the results

- [ ] Update memory `project_adapter_transport_gap`: mark G3 done, note any `parse_targets` fixes and
      the real `targets` formatting.
- [ ] If real xsdb output differed from `ZYNQMP_TARGETS_REF`, commit the updated reference + parser and
      re-run `tools/tcl-smoketest.sh` (mock-xsdb + transport smoketests must stay green).
- [ ] Drop the real `targets.txt` into `tests/fixtures/` as a regression fixture for the parser.

## Pass summary (fill in at the bench)

| Step | What | Result |
|---|---|---|
| 1 | hw_server owns adapter | ☐ |
| 2 | real `targets` captured | ☐ |
| 3 | parser matches real output | ☐ |
| 4 | IDCODE 0x24738093 via xsdb | ☐ |
| 5 | mem dump byte-plausible | ☐ |
| 6 | GUI hw_server dump end-to-end | ☐ |
| 7 | XVC bridge (optional) | ☐ |
