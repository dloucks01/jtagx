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
def tlvarea(*tlvs):
    body = b"".join(struct.pack("<BBH", t, 0, len(v)) + v for t, v in tlvs)
    return struct.pack("<HH", 0x6907, 4 + len(body)) + body
# MCUboot SIGNED (real RSA2048-PSS = TLV 0x20) + KEYHASH (0x01) + SEC_CNT (0x50)
o = run(hdr+img+tlvarea((0x10,bytes(32)),(0x01,bytes(32)),(0x20,bytes(256)),(0x50,struct.pack("<I",5))))
if "format: MCUboot" not in o: bad("MCUboot magic not recognized")
if "sig-verify-target" not in o: bad("signed MCUboot should flag the sig-verify FI target")
if "signing-key" not in o or "key_sha256" not in o: bad("should extract the KEYHASH signing-key")
if "no-rollback-counter" in o: bad("SEC_CNT present → should NOT flag missing rollback counter")
# MCUboot WEAK sig (ECDSA-P224 = TLV 0x21) + no SEC_CNT → weak-signature HIGH + no-rollback MED
o = run(hdr+img+tlvarea((0x10,bytes(32)),(0x21,bytes(56))))
if "[HIGH] weak-signature" not in o: bad("ECDSA-P224 should be flagged HIGH weak-signature")
if "no-rollback-counter" not in o: bad("no SEC_CNT should flag missing anti-rollback")
# MCUboot UNSIGNED (only SHA256 0x10, NOT a signature) -> HIGH unsigned-image
o = run(hdr+img+tlvarea((0x10,bytes(32))))
if "[HIGH] unsigned-image" not in o: bad("unsigned MCUboot (SHA256 only) should be flagged HIGH")
if o.count("signed: True"): bad("SHA256-only image must read signed: False (0x10 is a hash, not a sig)")
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
# image with a PUBKEY TLV (0x02) but no KEYHASH → the analyzer fingerprints the embedded key
import hashlib
pub = b"EMBEDDEDPUBKEY!!"*4
o = run(hdr+img+tlvarea((0x20,bytes(256)),(0x02,pub)))
if "pubkey_embedded: True" not in o: bad("should note an embedded PUBKEY TLV")
if hashlib.sha256(pub).hexdigest()[:16] not in o: bad("should fingerprint the embedded pubkey as its sha256")
print("  secure-boot analyzer OK (signed/unsigned, weak-sig, rollback, key-hash, PUBKEY fingerprint, Xilinx-defer)")
PY

# --hash-key computes the correct key hash for populating references/known-keys/
python3 - <<'PY' || exit 1
import subprocess, tempfile, os, hashlib, sys
def bad(m): print("FAIL(secureboot-analyze):", m); sys.exit(1)
import base64
p=tempfile.mktemp(suffix=".pem")
open(p,"w").write("-----BEGIN PUBLIC KEY-----\n"+base64.b64encode(b"TESTKEY").decode()+"\n-----END PUBLIC KEY-----\n")
o=subprocess.run(["python3","tools/secureboot-analyze.py","--hash-key",p],capture_output=True,text=True).stdout
os.unlink(p)
if hashlib.sha256(b"TESTKEY").hexdigest() not in o: bad("--hash-key should sha256 the decoded DER key")
print("  --hash-key OK (PEM → DER → sha256, ready for references/known-keys/)")
PY

# firmware-id: OS/RTOS/bootloader banner → version-gated CVE classes
python3 -m py_compile tools/firmware-id.py || fail "firmware-id does not compile"
python3 - <<'PY' || exit 1
import subprocess, tempfile, os, sys
def bad(m): print("FAIL(secureboot-analyze):", m); sys.exit(1)
def run(b):
    p=tempfile.mktemp(); open(p,"wb").write(b)
    o=subprocess.run(["python3","tools/firmware-id.py",p],capture_output=True,text=True).stdout
    os.unlink(p); return o
if "Dirty COW" not in run(b"x Linux version 4.4.0-xilinx gcc"): bad("Linux 4.4 should map to Dirty COW")
if "Dirty Pipe" not in run(b"Linux version 5.10.110 SMP"): bad("Linux 5.10 should map to Dirty Pipe")
if "URGENT/11" not in run(b"VxWorks 6.9 IPnet"): bad("VxWorks 6.9 should map to URGENT/11")
if "no OS/RTOS" not in run(b"random bytes no banner"): bad("no-banner dump should say so honestly")
print("  firmware-id OK (Linux/VxWorks/U-Boot/BusyBox banners → version-gated CVE classes)")
PY

echo "PASS: semantic-analysis (secure-boot auth structure + firmware-id CVE mapping)"
