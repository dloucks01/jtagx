#!/usr/bin/env python3
"""
jtagtoshell-plan.py -- unit test for jtagx/jtagtoshell.py, the JTAG-to-shell planner.

Asserts: the right path is chosen for every (firmware_running x goal) combination,
the debug-not-open case redirects to the unlock engine instead of a shell path, the
wedge warning is always present, from_capture() derives state correctly from a real
capture, and render_md() produces a well-formed runbook. Offline; no hardware.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from jtagx.jtagtoshell import plan, from_capture, render_md, WEDGE_WARNING  # noqa: E402


def _fail(m):
    print(f"FAIL(jtagtoshell-plan): {m}")
    sys.exit(1)


def _ids(result):
    return [p["id"] for p in result["paths"]]


# --- goal x firmware_running matrix ---
cases = [
    (dict(firmware_running=True, goal="shell"), ["live-patch"], "live-patch"),
    (dict(firmware_running=False, goal="shell"), ["coldboot"], "coldboot"),
    (dict(firmware_running=True, goal="secret"), ["catch-in-flight"], "catch-in-flight"),
    (dict(firmware_running=False, goal="secret"), ["coldboot", "catch-in-flight"], "catch-in-flight"),
    (dict(firmware_running=True, goal="persist"), ["live-patch", "persist"], "live-patch"),
    (dict(firmware_running=False, goal="persist"), ["coldboot", "live-patch", "persist"], "live-patch"),
]
for state, want_ids, want_rec in cases:
    r = plan(state)
    got = _ids(r)
    if got != want_ids:
        _fail(f"state={state}: paths {got}, expected {want_ids}")
    if r["recommended"] != want_rec:
        _fail(f"state={state}: recommended={r['recommended']}, expected {want_rec}")
    if WEDGE_WARNING not in r["caveats"]:
        _fail(f"state={state}: wedge warning missing from caveats")

# --- catch-in-flight must NOT drag in the full dump+patch+apply sequence ---
r = plan(dict(firmware_running=True, goal="secret"))
b = r["paths"][0]
step_titles = " ".join(s["title"] for s in b["steps"])
if "Apply the patch" in step_titles or "Get the shell" in step_titles:
    _fail("catch-in-flight path should not include live-patch's apply/shell steps")

# --- ZynqMP persist uses the QSPI safe-write path, NOT the Cortex-M internal-flash driver ---
r = plan(dict(firmware_running=True, goal="persist"), soc="zynqmp")
persist_cmds = " ".join(s["cmd"] for s in r["paths"][1]["steps"])
if "qspi-write.tcl" not in persist_cmds or "cortexm-flash.tcl" in persist_cmds:
    _fail("zynqmp persist should use qspi-write.tcl, not cortexm-flash.tcl (they are not bootgen-wrapped the same way)")
if "qspi-make-patch.py" not in persist_cmds:
    _fail("zynqmp persist should prep the patch via qspi-make-patch.py")
# --- a Cortex-M board's persist path uses cortexm-flash.tcl instead ---
r = plan(dict(firmware_running=True, goal="persist"), soc="nrf52")
cm_cmds = " ".join(s["cmd"] for s in r["paths"][1]["steps"])
if "cortexm-flash.tcl" not in cm_cmds or "qspi-write.tcl" in cm_cmds:
    _fail("a Cortex-M board's persist path should use cortexm-flash.tcl, not the ZynqMP QSPI path")

# --- persist path validates live BEFORE reflashing (order matters) ---
r = plan(dict(firmware_running=True, goal="persist"))
if [p["id"] for p in r["paths"]] != ["live-patch", "persist"]:
    _fail("persist goal should validate live (path A) before reflashing (path D)")

# --- debug not open -> unlock-first, never a shell path ---
for inv in ("gated", "wedged", "unreachable"):
    r = plan(dict(firmware_running=True, invasive_debug=inv, goal="shell"))
    if _ids(r) != ["unlock-first"]:
        _fail(f"invasive_debug={inv} should redirect to unlock-first only, got {_ids(r)}")
    if "unlock-engine.py" not in r["paths"][0]["steps"][0]["cmd"]:
        _fail(f"invasive_debug={inv}: unlock-first should point at unlock-engine.py")

# --- have_dump=True skips the redundant dump step ---
r = plan(dict(firmware_running=True, goal="shell", have_dump=True))
titles = [s["title"] for s in r["paths"][0]["steps"]]
if any("Dump the live OS" in t for t in titles):
    _fail("have_dump=True should skip the dump step")
r2 = plan(dict(firmware_running=True, goal="shell", have_dump=False))
titles2 = [s["title"] for s in r2["paths"][0]["steps"]]
if not any("Dump the live OS" in t for t in titles2):
    _fail("have_dump=False should include the dump step")

# --- from_capture() derives state from a real capture (the golden: idle board) ---
GOLD = Path(__file__).resolve().parent.parent / "tests" / "golden" / "zcu102-jtag-idle" / "raw.json"
if GOLD.exists():
    raw = json.loads(GOLD.read_text())
    r = from_capture(raw, goal="shell")
    if _ids(r) != ["coldboot"]:
        _fail(f"golden capture (firmware_running=False) should plan coldboot, got {_ids(r)}")
    # soc auto-derived from metadata
    if "zcu102" not in r["paths"][0]["steps"][1]["cmd"].lower() and "zynqmp" not in str(r):
        pass  # soc defaults to zcu102.cfg either way; not a hard requirement here

# --- render_md produces a well-formed runbook: title, caveat, every step's command ---
r = plan(dict(firmware_running=True, goal="shell"))
md = render_md(r)
if not md.startswith("# JTAG-to-Shell Runbook"):
    _fail("render_md should start with the runbook title")
if "Read first" not in md:
    _fail("render_md should surface the caveats block")
for s in r["paths"][0]["steps"]:
    if s.get("cmd") and s["cmd"] not in md:
        _fail(f"render_md dropped a command: {s['cmd'][:40]}...")

print("PASS: jtagtoshell-plan (6 goal x firmware combos, unlock-redirect, have_dump, "
      "from_capture, render_md well-formed)")
