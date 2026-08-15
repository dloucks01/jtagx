#!/usr/bin/env bash
# extract-plan-smoketest.sh — jtagx.extraction: every board's real extraction avenues, incl. the vendor
# ROM loaders (i.MX SDP, SAM-BA, TI RBL, esptool, RP2040 BOOTROM) that extract WITHOUT the debug port,
# and the honest chip-off fallback. Pure/offline.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(extract-plan): $1"; exit 1; }
python3 -m py_compile tools/extract-plan.py jtagx/extraction.py || fail "does not compile"

python3 - <<'PY' || exit 1
import sys, json, glob, os
sys.path.insert(0, ".")
from jtagx.extraction import extraction_plan, best_cable
def bad(m): print("FAIL(extract-plan):", m); sys.exit(1)
def prof(soc):
    for p in sorted(glob.glob("profiles/*.json")):
        if os.path.basename(p).startswith("_"): continue
        d=json.loads("".join(l for l in open(p) if not l.lstrip().startswith(("//","#"))))
        if d.get("soc")==soc: return d
    return {}

# every board has at least the external-flash fallback (nothing is truly un-extractable)
for soc in ("zynqmp","imx6","esp32","rp2040","sama5","igloo2","riscv","bcm"):
    pl = extraction_plan(soc, {}, prof(soc))
    if not any(m["access"]=="chip-off" for m in pl): bad(f"{soc}: external-flash fallback missing")

# vendor ROM loaders are modeled as NO-debug-needed avenues
for soc, key in (("imx6","SDP"),("sama5","SAM-BA"),("esp32","esptool"),("rp2040","BOOTROM"),("am335x","RBL")):
    pl = extraction_plan(soc, {}, prof(soc))
    rl = [m for m in pl if m["access"]=="rom-loader"]
    if not rl: bad(f"{soc}: no ROM-loader extraction path")
    if rl[0]["needs_debug"]: bad(f"{soc}: ROM loader must NOT need the debug port")
    if key.lower() not in (rl[0]["method"]+rl[0]["how"]).lower(): bad(f"{soc}: ROM loader should mention {key}")
    if not rl[0].get("cmd"): bad(f"{soc}: ROM loader should carry a runnable command")
# the runnable command is a real vendor-tool invocation (esptool / picotool / sam-ba / uuu)
if "read_flash" not in [m["cmd"] for m in extraction_plan("esp32",{},prof("esp32")) if m["access"]=="rom-loader"][0]:
    bad("esp32 ROM-loader command should be an esptool read_flash")

# Phase-4: RISC-V System Bus Access is a debug-port mem dump (needs the DM authenticated).
for soc in ("riscv","esp32c3"):
    sba = [m for m in extraction_plan(soc,{"jtag_open":True},prof(soc)) if "SBA" in m["method"]]
    if not sba: bad(f"{soc}: RISC-V SBA extraction path missing")
    if sba[0]["access"]!="jtag": bad(f"{soc}: SBA should be a jtag/debug-port avenue")
    if "sbcs" not in sba[0]["how"] and "System Bus" not in sba[0]["method"]: bad(f"{soc}: SBA should describe the DM system bus")
    if "riscv-sba-dump.tcl" not in sba[0].get("cmd",""): bad(f"{soc}: SBA should carry the runnable dump command")
# a non-RISC-V board must NOT sprout an SBA path
if any("SBA" in m["method"] for m in extraction_plan("zynqmp",{"jtag_open":True},prof("zynqmp"))):
    bad("zynqmp (Arm) must not offer a RISC-V SBA path")
# Phase-4: LPC ISP serial bootloader is a no-debug ROM-loader avenue
lpc_rl = [m for m in extraction_plan("lpc",{},prof("lpc")) if m["access"]=="rom-loader"]
if not lpc_rl or "ISP" not in lpc_rl[0]["method"]: bad("lpc: ISP serial-bootloader extraction path missing")
if lpc_rl[0]["needs_debug"]: bad("lpc: ISP loader must NOT need the debug port")

# best_cable: when debug is CLOSED, a ROM-loader board still has a cable path (SDP); zynqmp (no loader) doesn't
if best_cable(extraction_plan("imx6",{},prof("imx6")), debug_open=False) is None:
    bad("imx6 should have a cable extraction path (SDP) even with debug closed")
if best_cable(extraction_plan("zynqmp",{},prof("zynqmp")), debug_open=False) is not None:
    bad("zynqmp with debug closed + no ROM loader should have NO cable path (only chip-off)")
# with debug OPEN, the mem-AP dump is the best path
b = best_cable(extraction_plan("zynqmp",{},prof("zynqmp")), debug_open=True)
if b is None or b["access"]!="jtag": bad("zynqmp debug-open best path should be the mem-AP dump")

print("  extraction OK (ROM loaders no-debug, chip-off fallback everywhere, best_cable gating)")
PY

python3 tools/extract-plan.py --soc imx6 | grep -q "SDP" || fail "CLI should render the i.MX SDP path"
python3 tools/extract-plan.py --list | grep -q "esp32" || fail "--list should show boards"

echo "PASS: extract-plan (per-board extraction: mem-AP + vendor ROM loaders + chip-off)"
