#!/usr/bin/env bash
# mock-xsdb-smoketest.sh — validates the hw_server/xsdb path end-to-end against the HIGH-FIDELITY
# mock (tools/mock-xsdb.py), so the SmartLynq2 flow is exercised offline before the G3 bench.
# Checks: mock `targets` output round-trips through our parser to the reference tree; the IDCODE
# cross-check returns 0x24738093; and the exact command XsdbTransport EMITS actually produces a dump
# when xsdb is the mock. Pure/offline; no hardware, no Vitis.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(mock-xsdb): $1"; exit 1; }
MOCK="$PWD/tools/mock-xsdb.py"

python3 -m py_compile tools/mock-xsdb.py || fail "mock does not compile"
[ -x "$MOCK" ] || chmod +x "$MOCK"

# 1. `targets` round-trips through parse_targets to the canonical reference tree
"$MOCK" -eval "connect -host 127.0.0.1 -port 3121; targets" > /tmp/mock-targets.$$ 2>&1
python3 - <<PY || exit 1
import sys
from jtagx.transport import parse_targets, find_target, zynqmp_reference, flatten_targets
def bad(m): print("FAIL(mock-xsdb):", m); sys.exit(1)
mock = parse_targets(open("/tmp/mock-targets.$$").read())
ref  = zynqmp_reference()
if [(n.tid,n.role,n.index) for n in flatten_targets(mock)] != \
   [(n.tid,n.role,n.index) for n in flatten_targets(ref)]:
    bad("mock targets output does not round-trip to the reference tree")
a = find_target(mock, role="a53", index=0)
if not a or a.tid != 9 or a.state != "Running":
    bad("A53#0 should parse as id 9, state 'Running' (the '*' selected marker)")
print("  targets round-trip OK (12 nodes; A53#0=id9)")
PY
rm -f /tmp/mock-targets.$$

# 2. IDCODE cross-check: mrd of 0xFFCA0040 returns the real XCZU9EG value
OUT=$("$MOCK" -eval 'targets -set -filter {name =~ "*A53*#0"}; mrd 0xFFCA0040 1')
echo "$OUT" | grep -qi "24738093" || fail "mrd 0xFFCA0040 should return 0x24738093 (IDCODE)"

# 3. the exact command XsdbTransport EMITS produces a dump when xsdb is the mock
python3 - <<PY || exit 1
import os, sys
os.environ["JTAGX_XSDB"] = "$MOCK"
os.environ["JTAGX_MOCK_MAXBYTES"] = "8192"
from jtagx.transport import make_transport
def bad(m): print("FAIL(mock-xsdb):", m); sys.exit(1)
t = make_transport("hw_server", cfg="openocd/zcu102.cfg", soc="zynqmp", target="a53-0")
cmd = t.mem_read(0x00100000, 0x01000000, "/tmp/mock-os-live.$$.bin").as_shell()
if "mrd -bin -file" not in cmd: bad("emitted command is not an xsdb mem-read")
rc = os.system(cmd + " >/dev/null 2>&1")
if rc != 0: bad(f"emitted xsdb command failed (rc={rc})")
p = "/tmp/mock-os-live.$$.bin"
if not os.path.exists(p) or os.path.getsize(p) != 8192:
    bad(f"dump should be 8192 bytes (capped), got {os.path.getsize(p) if os.path.exists(p) else 'missing'}")
os.remove(p)
print("  transport-emitted xsdb dump command produced an 8192-byte file")
PY

echo "PASS: mock-xsdb (targets round-trip + IDCODE cross-check + transport dump via mock)"
