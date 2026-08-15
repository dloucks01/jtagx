#!/usr/bin/env bash
# transport-smoketest.sh — offline assertions for the jtagx.transport backend-agnostic layer
# (the fix for the SmartLynq2/FlashPro4 engagement gap: never assume the adapter speaks OpenOCD).
# Guards: USB VID:PID detection, profile allowlist matching, per-backend command generation for
# each primitive, and the honest Libero stub. Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(transport): $1"; exit 1; }

python3 -m py_compile jtagx/transport/*.py tools/transport-probe.py || fail "package does not compile"

# a fixture lsusb with the two engagement adapters + onboard FTDI present
FIX="$(mktemp)"; trap 'rm -f "$FIX"' EXIT
cat > "$FIX" <<'EOF'
Bus 001 Device 002: ID 0403:6011 Future Technology Devices International FT4232H
Bus 001 Device 005: ID 03fd:0100 Xilinx SmartLynq
Bus 001 Device 004: ID 1514:2005 Microsemi FlashPro4
EOF

# 1. detection recognizes all three adapters and classifies backends
OUT=$(python3 tools/transport-probe.py --list-adapters --lsusb-file "$FIX")
echo "$OUT" | grep -q "backend=openocd"   || fail "FTDI should classify as openocd"
echo "$OUT" | grep -q "backend=hw_server" || fail "SmartLynq2 should classify as hw_server"
echo "$OUT" | grep -q "backend=libero"    || fail "FlashPro4 should classify as libero"

# 2. auto-select for zynqmp prefers the non-vendor OpenOCD path and emits an openocd scan
OUT=$(python3 tools/transport-probe.py --profile zynqmp --lsusb-file "$FIX")
echo "$OUT" | grep -q "Selected backend: openocd"         || fail "auto-select should pick openocd on an open board"
echo "$OUT" | grep -qE "scan .*openocd -f openocd/zcu102" || fail "openocd scan command missing"
# FlashPro4 is present but NOT on the zynqmp allowlist -> must be flagged, not offered
echo "$OUT" | grep -q "NOT on this board" || fail "FlashPro4 should be flagged as not-allowlisted for zynqmp"

# 3. forcing hw_server yields the xsdb SmartLynq2 path (the adapter that failed the engagement)
OUT=$(python3 tools/transport-probe.py --profile zynqmp --backend hw_server --lsusb-file "$FIX")
echo "$OUT" | grep -q "Selected backend: hw_server"   || fail "forced backend should be hw_server"
echo "$OUT" | grep -q "xsdb -eval"                    || fail "hw_server should drive via xsdb"
echo "$OUT" | grep -q "mrd -bin -file"                || fail "xsdb mem_read should use mrd -bin"

# 4. python-level invariants (five verbs, capability model, libero stub honesty)
python3 - <<'PY' || exit 1
import importlib.util, os, sys
sys.path.insert(0, ".")
spec = importlib.util.spec_from_file_location("br", "tools/board-runner.py")
br = importlib.util.module_from_spec(spec); spec.loader.exec_module(br)
from jtagx.transport import for_profile, make_transport, BACKENDS

def bad(m): print("FAIL(transport):", m); sys.exit(1)

# every backend implements all five verbs and a capabilities()
for name in BACKENDS:
    t = make_transport(name, cfg="openocd/zcu102.cfg", soc="zynqmp")
    for verb in ("scan", "halt", "run"):
        if getattr(t, verb)().as_shell() == "" and name != "libero":
            bad(f"{name}.{verb} produced empty command")
    c = t.capabilities()
    if c.max_tier not in "abcde": bad(f"{name} bad max_tier {c.max_tier}")

# libero is honestly limited: no general mem_read/run-control, routes M3 to CoreSight
lib = make_transport("libero", soc="smartfusion2")
lc = lib.capabilities()
if lc.mem_read or lc.halt: bad("libero stub must NOT claim mem_read/halt")
if "OpenOCD" not in lib.halt().desc and "CoreSight" not in lib.halt().desc:
    bad("libero halt should route M3 run-control to the CoreSight/OpenOCD path")

# xsdb offers the XVC bridge that keeps OpenOCD Tcl working over a SmartLynq2
xs = make_transport("hw_server", cfg="openocd/zcu102.cfg", soc="zynqmp")
if "XVC" not in xs.xvc_bridge_hint().desc: bad("xsdb should expose the XVC bridge hint")

# for_profile: --backend/prefer is a HARD override, honored even when that adapter isn't present
from jtagx.transport import for_profile
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("br2", "tools/board-runner.py")
_br = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_br)
_prof = _br.load_jsonc("profiles/zynqmp.json")
only_ftdi = [{"usb_id": "0403:6010", "name": "FTDI", "backend": "openocd", "driver": "ftdi",
             "vendor_sw": False, "known": True, "desc": ""}]
if for_profile(_prof, only_ftdi).backend != "openocd": bad("auto should pick openocd when only FTDI present")
if for_profile(_prof, only_ftdi, prefer="hw_server").backend != "hw_server":
    bad("prefer=hw_server must be a HARD override even when only FTDI is present")

# --- P3: debug-target tree ---
from jtagx.transport import zynqmp_reference, resolve_selector, find_target, parse_targets
roots = zynqmp_reference()
a53_0 = find_target(roots, role="a53", index=0)
if a53_0 is None or a53_0.tid != 9: bad("reference tree: A53 #0 should be target id 9")
pmu = find_target(roots, role="pmu")
if pmu is None or pmu.tid != 2: bad("reference tree: PMU should be target id 2")
if len([n for n in __import__('jtagx.transport', fromlist=['flatten_targets']).flatten_targets(roots) if n.role=='a53']) != 4:
    bad("reference tree should have 4 A53 cores")
# role selector resolves to the right xsdb filter
if '#1' not in resolve_selector("r5-1"): bad("r5-1 selector should target R5 #1")
if not resolve_selector(9).endswith("targets 9"): bad("numeric selector should be `targets 9`")
# binding the transport to a core changes the emitted select
xs2 = xs.select("r5-0")
if 'R5*#0' not in xs2.mem_read(0x0, 0x10, "x.bin").as_shell(): bad("select('r5-0') should bind mem_read to R5#0")
# target_for resolves a role to a concrete tree id
pt = xs.target_for("pmu")
if 'targets 2' not in pt.halt().as_shell(): bad("target_for('pmu') should resolve to concrete id 2")
# live-output parsing (with the '*' selected marker) works
live = parse_targets("  1 PSU\n     2 APU\n       *3 Cortex-A53 #0 (Running)\n")
if find_target(live, role="a53", index=0).tid != 3: bad("live parse should handle the '*' selected marker")
print("  python invariants OK (incl. P3 target tree)")
PY

# 5. writable data-dir resolver (P4): dev no-op, packaged rewrite, code paths preserved
python3 - <<'PY' || exit 1
import os, importlib, sys
sys.path.insert(0, ".")
from jtagx import paths
def bad(m): print("FAIL(transport):", m); sys.exit(1)

# dev: data_dir == repo_root, localize is a no-op
cmd = 'DUMP_OUT=dumps/os-live.bin openocd -f openocd/zcu102.cfg; python3 tools/interpret.py reports/raw.json'
if not paths.is_packaged():
    if paths.localize(cmd) != cmd: bad("dev localize should be a no-op")
    if os.path.abspath(paths.data_dir()) != os.path.abspath(paths.repo_root()): bad("dev data_dir should be repo root")

# packaged: JTAGX_DATA elsewhere -> dumps//reports/ rewritten, openocd//tools/ untouched
os.environ["JTAGX_PACKAGED"] = "1"; os.environ["JTAGX_DATA"] = "/tmp/jtagx-smoke"
importlib.reload(paths)
out = paths.localize(cmd)
if "/tmp/jtagx-smoke/dumps/os-live.bin" not in out: bad("packaged localize should rewrite dumps/")
if "/tmp/jtagx-smoke/reports/raw.json" not in out: bad("packaged localize should rewrite reports/")
if "openocd/zcu102.cfg" not in out or "tools/interpret.py" not in out: bad("localize must NOT touch code paths")
if paths.dumps_dir() != "/tmp/jtagx-smoke/dumps": bad("packaged dumps_dir wrong")
del os.environ["JTAGX_PACKAGED"], os.environ["JTAGX_DATA"]
print("  paths resolver OK (dev no-op + packaged rewrite)")
PY

echo "PASS: transport (detect + allowlist match + per-backend commands + libero stub + data-dir paths)"
