#!/usr/bin/env bash
# cortexm-posture-smoketest.sh — regression-guards jtagx/cortexm_posture.py (parses
# openocd/cortexm-protect.tcl's live text output into structured rows + an OPEN/LOCKED/UNKNOWN
# verdict; feeds the GUI's board-generic Posture/Registers tabs, see tools/gui-smoketest.sh #26c).
#
# Two passes:
#  1. REAL cortexm-protect.tcl, run under tclsh with minimal read_memory/halt/echo stubs (no OpenOCD,
#     no board) — proves the parser matches the ACTUAL script's output format, not a hand-typed
#     approximation of it. Covers stm32-rdp (open+locked) and nrf-approtect (locked).
#  2. tools/mock-openocd.py's cortexm_protect_mock — the same matrix the GUI drives $OPENOCD through —
#     for every CFG_FAMILY entry, in both mock states, asserting family+verdict.
set -uo pipefail
cd "$(dirname "$0")/.."

FAILS=0
fail() { echo "FAIL(cortexm-posture): $1"; FAILS=$((FAILS+1)); }

if ! command -v tclsh >/dev/null 2>&1; then
    echo "SKIP: cortexm-posture-smoketest (needs tclsh)"; exit 0
fi

CM="$(mktemp -d)"
trap 'rm -rf "$CM"' EXIT

# ---- pass 1: the REAL .tcl, under a minimal stub ----
run_real() {   # run_real <CM_PROT_KIND> <addr=val ...>
    local kind="$1"; shift
    {
        echo "array set MEM {}"
        for kv in "$@"; do
            addr="${kv%%=*}"; val="${kv#*=}"
            echo "array set MEM [list $addr $val]"
        done
        cat <<'STUB'
proc read_memory {addr width nwords {args ""}} {
    global MEM
    set a [format 0x%X $addr]
    if {[info exists MEM($a)]} { return [list $MEM($a)] }
    return [list 0]
}
proc halt {args} { return 0 }
proc echo {line} { puts $line }
STUB
        echo "set CM_PROT_KIND $kind"
        echo "source openocd/cortexm-protect.tcl"
    } > "$CM/stub.tcl"
    tclsh "$CM/stub.tcl" 2>&1
}

# FLASH_OPTCR: RDP occupies bits 15:8 ($opt >> 8 & 0xff), so 0xAA/0x55 must sit in the SECOND byte.
STM_OPEN=$(run_real stm32-rdp 0xE0042000=0x10000413 0x40023C14=0x0000AA00)
STM_LOCKED=$(run_real stm32-rdp 0xE0042000=0x10000413 0x40023C14=0x00005500)
# FICR.INFO.PART: the family check is (part>>16 & 0xffff)==0x5 — 0x52840/0x53xxx style values all have
# that upper halfword, since the "52"/"53" is itself in the low half (0x00052840, not 0x00520000-ish).
NRF_LOCKED=$(run_real nrf-approtect 0x10000100=0x00052840 0x10001208=0x0000FF00)

python3 - "$STM_OPEN" "$STM_LOCKED" "$NRF_LOCKED" <<'PYEOF'
import sys
sys.path.insert(0, ".")
from jtagx.cortexm_posture import parse_cortexm_protect

stm_open, stm_locked, nrf_locked = sys.argv[1], sys.argv[2], sys.argv[3]
fails = []

r = parse_cortexm_protect(stm_open)
if r["family"] != "stm32-rdp" or r["verdict"] != "OPEN":
    fails.append(f"real stm32-rdp OPEN: got family={r['family']} verdict={r['verdict']}")
if not any(t["title"] == "IDENTITY" for t in r["sections"]):
    fails.append("real stm32-rdp OPEN: missing IDENTITY section")

r2 = parse_cortexm_protect(stm_locked)
if r2["verdict"] != "LOCKED":
    fails.append(f"real stm32-rdp LOCKED: got verdict={r2['verdict']}")

r3 = parse_cortexm_protect(nrf_locked)
if r3["family"] != "nrf-approtect" or r3["verdict"] != "LOCKED":
    fails.append(f"real nrf-approtect LOCKED: got family={r3['family']} verdict={r3['verdict']}")

for f in fails:
    print(f"FAIL(cortexm-posture-py): {f}")
sys.exit(1 if fails else 0)
PYEOF
if [ "$?" -ne 0 ]; then fail "python parser assertions against the REAL .tcl output failed (see above)"; fi

# ---- pass 2: tools/mock-openocd.py — every CFG_FAMILY entry, both mock states ----
python3 - <<'PYEOF'
import os, subprocess, sys, tempfile
sys.path.insert(0, ".")
from jtagx.cortexm_posture import parse_cortexm_protect

CFGS = {
    "openocd/cortexm-stm32f4.cfg": "stm32-rdp", "openocd/cortexm-stm32h7.cfg": "stm32-rdp",
    "openocd/cortexm-gd32.cfg": "stm32-rdp", "openocd/cortexm-stm32l4.cfg": "stm32l4",
    "openocd/cortexm-stm32f1.cfg": "stm32f1", "openocd/cortexm-nrf52.cfg": "nrf-approtect",
    "openocd/cortexm-nrf53.cfg": "nrf-approtect", "openocd/cortexm-samd5x.cfg": "sam-dsu",
    "openocd/cortexm-kinetis.cfg": "kinetis-fsec", "openocd/cortexm-rp2040.cfg": "none",
    "openocd/cortexm-lpc.cfg": "none", "openocd/cortexm-nrf54.cfg": "none",
}
fails = []
statefile = tempfile.mktemp()
env = dict(os.environ)
env["JTAGX_MOCK_STATE"] = statefile
for cfg, expect_family in CFGS.items():
    for state, expect_verdict in (("locked", "LOCKED"), ("open", "OPEN")):
        with open(statefile, "w") as f:
            f.write(state)
        out = subprocess.run(
            ["python3", "tools/mock-openocd.py", "-f", cfg,
             "-c", "init; source openocd/cortexm-protect.tcl; shutdown"],
            capture_output=True, text=True, env=env).stdout
        r = parse_cortexm_protect(out)
        if r["family"] != expect_family:
            fails.append(f"{cfg} ({state}): expected family={expect_family}, got {r['family']}")
        # rp2040/lpc/nrf54 (CM_PROT_KIND=none) have no protection fuse modeled -> always OPEN regardless
        # of the mock lock state (matches the real .tcl: "none" means no register drives a verdict).
        want = "OPEN" if expect_family == "none" else expect_verdict
        if r["verdict"] != want:
            fails.append(f"{cfg} ({state}): expected verdict={want}, got {r['verdict']}")
os.remove(statefile) if os.path.exists(statefile) else None
for f in fails:
    print(f"FAIL(mock-cortexm-protect): {f}")
sys.exit(1 if fails else 0)
PYEOF
if [ "$?" -ne 0 ]; then fail "mock-openocd.py cortexm_protect_mock matrix failed (see above)"; fi

if [ "$FAILS" -eq 0 ]; then
    echo "PASS: cortexm-posture (real .tcl round-trip + mock matrix, 12 cfgs x 2 states)"
    exit 0
else
    echo "FAIL: cortexm-posture ($FAILS check(s) failed)"
    exit 1
fi
