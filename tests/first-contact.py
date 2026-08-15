#!/usr/bin/env python3
"""
first-contact.py (test) — unit test for jtagx/firstcontact.py (Phase 3 §3.4).

Asserts the blocker KB is well-formed, diagnose() routes the field symptoms to
the right blocker (FlashPro → proprietary-adapter, 'no idcode' → no-idcode,
ttyUSB busy → ftdi-sio-conflict, 1.8V dead → no-vref, wedges-on-run →
target-wedges), and render_md produces a stage-ordered tree. Offline.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from jtagx import firstcontact as fc  # noqa: E402


def _fail(m):
    print(f"FAIL(first-contact): {m}")
    sys.exit(1)


# 1. KB well-formed: every blocker has the required fields + a valid stage + non-empty fix.
req = {"id", "stage", "symptom", "causes", "detect", "fix", "severity"}
ids = set()
for b in fc.BLOCKERS:
    missing = req - set(b)
    if missing:
        _fail(f"blocker {b.get('id')} missing fields {missing}")
    if b["stage"] not in fc.STAGES:
        _fail(f"blocker {b['id']} has unknown stage {b['stage']}")
    if not b["fix"]:
        _fail(f"blocker {b['id']} has no fix (every blocker must name a way out)")
    if b["severity"] not in ("block", "degraded"):
        _fail(f"blocker {b['id']} bad severity {b['severity']}")
    ids.add(b["id"])
if len(ids) != len(fc.BLOCKERS):
    _fail("duplicate blocker ids")

# 2. diagnose() routes the field symptoms correctly (top hit).
cases = {
    "flashpro won't work with openocd": "proprietary-adapter",
    "smartlynq cable not driving": "proprietary-adapter",
    "scan returns all ones no idcode": "no-idcode",
    "adapter shows up as ttyUSB0 and openocd says busy": "ftdi-sio-conflict",
    "1.8v target totally dead no response": "no-vref",
    "debug works then wedges when firmware runs": "target-wedges",
    "nRF52 re-locks every power cycle": "target-wedges",
    "nrst looks inverted": "reset-polarity",
    "jtag disabled by efuse": "jtag-disabled",
    "sticky error powerup ack": "dap-powered-down",
}
for symptom, want in cases.items():
    hits = fc.diagnose(symptom, limit=3)
    if not hits:
        _fail(f"'{symptom}' → no diagnosis")
    top_ids = [b["id"] for _s, b in hits]
    if want not in top_ids:
        _fail(f"'{symptom}' → top-3 {top_ids}, expected {want} present")
    if top_ids[0] != want:
        _fail(f"'{symptom}' → top hit {top_ids[0]}, expected {want}")

# 3. empty symptom → full ordered tree.
allhits = fc.diagnose("")
if len(allhits) != len(fc.BLOCKERS):
    _fail("empty symptom should return the whole tree")

# 4. by_stage filters.
if not fc.by_stage("adapter"):
    _fail("adapter stage should have blockers")
if any(b["stage"] != "wiring" for b in fc.by_stage("wiring")):
    _fail("by_stage('wiring') leaked another stage")

# 5. the FlashPro blocker names the concrete way out (patched OpenOCD / FlashPro Express / ftdi_sio).
pa = fc.blocker("proprietary-adapter")
joined = " ".join(pa["fix"]).lower()
if "flashpro express" not in joined or "ftdi_sio" not in joined:
    _fail("proprietary-adapter fix must name FlashPro Express + the ftdi_sio unbind path")

# 6. render_md is stage-ordered and non-empty.
md = fc.render_md()
if "## Stage: adapter" not in md or "## Stage: policy" not in md:
    _fail("render_md should be stage-ordered")
if md.index("## Stage: adapter") > md.index("## Stage: wiring"):
    _fail("stages should render in encounter order (adapter before wiring)")

print(f"PASS: first-contact ({len(fc.BLOCKERS)} blockers, {len(cases)} symptom routes, stage-ordered render)")
