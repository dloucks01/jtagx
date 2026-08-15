#!/usr/bin/env bash
# secureboot-analyze-smoketest.sh — offline assertions for tools/secureboot-analyze.py: the generic
# cross-arch secure-boot container analyzer recognizes MCUboot/wolfBoot/FIT/Android, decodes the auth
# structure, and flags unsigned images HIGH + points at the sig-verify FI target. Pure/offline.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(secureboot-analyze): $1"; exit 1; }
python3 -m py_compile tools/secureboot-analyze.py || fail "does not compile"

python3 - <<'PY' || exit 1
import struct, subprocess, tempfile, os, sys
def bad(m): print("FAIL(secureboot-analyze):", m); sys.exit(1)
def run(b):
    p=tempfile.mktemp(suffix=".bin"); open(p,"wb").write(b)
    out=subprocess.run(["python3","tools/secureboot-analyze.py",p],capture_output=True,text=True).stdout
    os.unlink(p); return out

hdr = struct.pack("<IIHHII", 0x96F3B83D, 0, 32, 0, 64, 0) + bytes(8)
img = bytes(64)
# MCUboot SIGNED (RSA2048 TLV 0x22) -> format MCUboot, signed, sig-verify-target finding
sig = struct.pack("<HH", 0x6907, 12) + struct.pack("<BBH", 0x22, 0, 4) + bytes(4)
o = run(hdr+img+sig)
if "format: MCUboot" not in o: bad("MCUboot magic not recognized")
if "sig-verify-target" not in o: bad("signed MCUboot should flag the sig-verify FI target")
# MCUboot UNSIGNED (only SHA256 0x20) -> HIGH unsigned-image
uns = struct.pack("<HH", 0x6907, 36) + struct.pack("<BBH", 0x20, 0, 32) + bytes(32)
o = run(hdr+img+uns)
if "[HIGH] unsigned-image" not in o: bad("unsigned MCUboot should be flagged HIGH unsigned-image")
# wolfBoot SIGNED (HDR_SIGNATURE tag 0x20)
wb = struct.pack("<II", 0x464C4F57, 100) + struct.pack("<HH", 0x0020, 8) + bytes(8) + struct.pack("<HH",0,0)
o = run(wb)
if "format: wolfBoot" not in o or "sig-verify-target" not in o: bad("wolfBoot signed not analyzed")
# Xilinx bootgen -> defer to parse-bootimage.py
o = run(b"XLNX"+bytes(60))
if "parse-bootimage.py" not in o: bad("Xilinx image should defer to parse-bootimage.py")
# unknown blob -> honest 'unknown / run dump-triage first'
o = run(bytes(64))
if "dump-triage" not in o: bad("unknown blob should point at dump-triage.py")
print("  secure-boot analyzer OK (MCUboot signed/unsigned, wolfBoot, Xilinx-defer, unknown)")
PY

echo "PASS: secureboot-analyze (generic auth-structure analysis + weak-pattern findings)"
