#!/usr/bin/env bash
# console-mock-smoketest.sh — rehearses the GUI console COMMAND SURFACE end-to-end against the
# high-fidelity mocks, under BOTH backends: openocd primitives (mock-openocd.py) and hw_server/xsdb
# (mock-xsdb.py). Proves that a typed `mrd`/`/scan`/`/dump`/`/verify`/`/unlock` actually executes and
# routes to the right backend. SKIPs without PySide6. Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! python3 -c "import PySide6.QtWidgets" 2>/dev/null; then
    echo "SKIP: console-mock-smoketest (PySide6 not installed)"; exit 0
fi

export OPENOCD="$PWD/tools/mock-openocd.py"
export JTAGX_XSDB="$PWD/tools/mock-xsdb.py"
export JTAGX_MOCK_STATE="$(mktemp)"; rm -f "$JTAGX_MOCK_STATE"
export JTAGX_MOCK_LOCK="register-gated"
export JTAGX_MOCK_MAXBYTES="8192"
export JTAGX_DATA="$(mktemp -d)"; export JTAGX_PACKAGED=1
trap 'rm -f "$JTAGX_MOCK_STATE"; rm -rf "$JTAGX_DATA"' EXIT

QT_QPA_PLATFORM=offscreen python3 - <<'PY' || exit 1
import sys, os, time
sys.path.insert(0, "gui-spike")
from PySide6.QtWidgets import QApplication
app = QApplication([])
import qt_spike, unlock_panel, jtagx_app
app.setStyleSheet(qt_spike.QSS + unlock_panel.QSS)
def bad(m): print("FAIL(console-mock):", m); sys.exit(1)

w = jtagx_app.App(); w.show(); app.processEvents()
c = w.console

def run(cmd, timeout=15):
    c.clear()
    c.input.setText(cmd); c._run_input()
    t0 = time.time()
    while c.runner.busy() and time.time() - t0 < timeout:
        app.processEvents(); time.sleep(0.02)
    app.processEvents()
    return c.text.toPlainText()

# ---- OpenOCD backend ----
w._console_set_backend("openocd")
if "24738093" not in run("mrd 0xFFCA0040 1"): bad("openocd mrd should read the IDCODE via mock mdw")
if "zynqmp.tap" not in run("/scan"): bad("openocd /scan should show the mock chain")
if "VERDICT: LOCKED" not in run("/verify"): bad("mock board should read LOCKED before the lever")
run("/unlock")                                   # flips the mock state to open
if "VERDICT: OPEN" not in run("/verify"): bad("/unlock then /verify should read OPEN")
out = run("/dump 0x0 0x1000 dumps/console-openocd.bin")
p = os.path.join(os.environ["JTAGX_DATA"], "dumps", "console-openocd.bin")
if not os.path.exists(p) or os.path.getsize(p) != 4096: bad("openocd /dump should write a 4096-byte file")
# richer fidelity: a DRAM dump carries recognizable structure (banner) the analysis tools can find
if b"VxWorks" not in open(p, "rb").read(): bad("mock DRAM dump should carry the VxWorks banner (fidelity)")

# ---- hw_server (xsdb) backend ----
w._console_set_backend("hw_server")
if "24738093" not in run("mrd 0xFFCA0040 1"): bad("hw_server mrd should read the IDCODE via mock xsdb")
out = run("/dump 0x100000 0x1000 dumps/console-xsdb.bin")
p2 = os.path.join(os.environ["JTAGX_DATA"], "dumps", "console-xsdb.bin")
if not os.path.exists(p2) or os.path.getsize(p2) != 4096: bad("hw_server /dump should write a 4096-byte file")

# ---- adapters (real offline tool) — must RUN and report, whether or not one is plugged in ----
_a = run("/adapters")
if "Detected JTAG adapters" not in _a: bad("/adapters should run the adapter detection")

print("  console command surface OK under openocd + hw_server mocks (mrd/scan/verify/unlock/dump)")
w.dash.stop()
PY

echo "PASS: console-mock (command surface rehearsed under both backend mocks)"
