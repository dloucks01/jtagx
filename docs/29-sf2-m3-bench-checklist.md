# 29 — G-class Bench Checklist: SmartFusion2 Cortex-M3 extraction

**Goal.** Validate the SmartFusion2 (M2S) **Cortex-M3 MSS** extraction path on real silicon: reach the
M3 CoreSight DAP with a *standard* probe (J-Link / CMSIS-DAP) via OpenOCD `cortex_m`, and dump
**eNVM + eSRAM** with **no FlashPro** — the whole point of the "IGLOO2-with-M3" engagement. Everything
here is command-correct today but **HW-UNVALIDATED**; this is the session that closes that.

Related: `profiles/smartfusion2.json`, `jtagx.unlock` (lock_sf2_*), `jtagx.cve` (Actel backdoor),
`project_adapter_transport_gap` (memory). Offline rehearsal: `bash tools/mock-cortexm-smoketest.sh`.

---

## 0. Preconditions

- [ ] SmartFusion2 board powered; **SWD or JTAG** header wired to a **J-Link or CMSIS-DAP** (a generic
      FTDI works over JTAG; SWD on FTDI needs MPSSE-SWD).
- [ ] OpenOCD with a `cortex_m` target for the part (adapt `openocd/cortexm.cfg`: `transport select swd`
      or `jtag`, `set CHIPNAME sf2`, `cortex_m` target). Confirm `openocd --version`.
- [ ] Scratch dir + keep outputs OFF the repo dumps: `export JTAGX_DATA=/tmp/sf2 && mkdir -p $JTAGX_DATA`.

> **Rehearse offline first** so you know the expected shapes:
> `OPENOCD=$PWD/tools/mock-cortexm.py bash tools/mock-cortexm-smoketest.sh` (open dumps eNVM + a decoy
> secret; `JTAGX_MOCK_LOCK=debug-locked` faults). Also: `python3 tools/unlock-engine.py --soc smartfusion2
> --debug-locked --flashlock` shows the plan when debug IS locked.

## 1. Reach the DAP (is M3 debug open?)

```bash
openocd -f openocd/cortexm.cfg -c "init; dap info; halt; reg; resume; shutdown"
```
- [ ] **PASS** if OpenOCD attaches, `dap info` lists the AHB-AP, and `halt` stops the M3 (a `reg` dump
      of r0–pc appears). **FAIL / "DAP did not answer"** → M3 debug is **security-locked**: skip to §4.

## 2. IDCODE / part sanity

```bash
openocd -f openocd/cortexm.cfg -c "init; scan_chain; shutdown"    # JTAG; SWD reads the DPIDR instead
```
- [ ] **PASS** if a Microsemi/ARM IDCODE appears. Record it (there's no confirmed public decoder — this
      board is `auto_match:false`, selected explicitly as `--profile smartfusion2`).

## 3. Dump eNVM + eSRAM (the extraction)

```bash
# eNVM (embedded flash) — adjust base/size to the part (M2S090 ≈ 256 KiB eNVM @ 0x60000000):
openocd -f openocd/cortexm.cfg -c "init; halt; dump_image $JTAGX_DATA/sf2-envm.bin 0x60000000 0x40000; resume; shutdown"
# eSRAM:
openocd -f openocd/cortexm.cfg -c "init; halt; dump_image $JTAGX_DATA/sf2-esram.bin 0x20000000 0x10000; resume; shutdown"
python3 tools/dump-triage.py $JTAGX_DATA/sf2-envm.bin
python3 tools/dram-secrets.py $JTAGX_DATA/sf2-envm.bin --base 0x60000000
```
- [ ] **PASS** if the dumps are the expected size and triage shows real structure (M3 vector table at
      the start of eNVM: initial SP then reset-handler; strings/keys via dram-secrets). **This is the
      extraction win — eNVM/eSRAM off the board with no FlashPro.**

## 4. If M3 debug is LOCKED (the hard path)

The security policy (set at programming time) can disable M3 debug — **not runtime-reopenable**. The
ranked plan (`unlock-engine --soc smartfusion2 --debug-locked --flashlock`):
- [ ] **Boundary-scan** the pins even with the DAP shut: parse the BSDL (`tools/bsdl-scan.py part.bsdl
      --sample-plan`), run SAMPLE, `--decode` — maps straps/pins, won't dump eNVM.
- [ ] **FlashPro Express → Inspect Device** for the security status (what's locked / readback gating).
- [ ] **DPA pass-key recovery** (Skorobogatov & Woods, CHES 2012) → authorized FlashPro/Libero eNVM
      readback. Hardware SCA rig.
- [ ] **Glitch** the System-Controller security decision at boot (voltage/EM) to re-enable M3 debug.
- [ ] **Re-program** a policy with M3 debug open (DESTRUCTIVE; needs FlashPro; fails if permanently locked).
- [ ] **Chip-off eNVM** (decap + microprobe) as the last resort.

## 5. Record

- [ ] Update memory `project_adapter_transport_gap`: SF2 extraction validated (or the exact eNVM/eSRAM
      base/size + debug-lock behaviour observed). Drop a real IDCODE/`scan_chain` into `tests/fixtures/`.
- [ ] If the cfg needed changes for the real part, commit `openocd/cortexm.cfg` and re-run
      `tools/tcl-smoketest.sh` (mock-cortexm must stay green).

## Pass summary (fill in at the bench)

| Step | What | Result |
|---|---|---|
| 1 | M3 DAP reachable / debug open | ☐ |
| 2 | IDCODE recorded | ☐ |
| 3 | eNVM + eSRAM dumped (no FlashPro) | ☐ |
| 4 | (locked) FlashPro/DPA/glitch path | ☐ |
