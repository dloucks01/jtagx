#!/usr/bin/env bash
# break-secrets-smoketest.sh — offline assertions for tools/break-secrets.py: automatic secret-in-flight
# capture. Given a break-capture transcript (breakpoint hit + dereferenced arg pointers as hex), it runs
# the dram-secrets engine over the pointed-to bytes and reports the secret caught IN FLIGHT, attributed
# to the function + register. Pure/offline (interprets a capture; no hardware).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(break-secrets): $1"; exit 1; }
python3 -m py_compile tools/break-secrets.py || fail "does not compile"

python3 - <<'PY' || exit 1
import subprocess, sys
def bad(m): print("FAIL(break-secrets):", m); sys.exit(1)
def cap(who, reg, pa, payload):
    hexb = " ".join(f"{x:02x}" for x in payload.ljust(64, b"\x00"))
    return (f" #0   {who} @ 0xffffffff8023ce14  x0=0x1 {reg}=0x{pa:x} x2=0x0\n"
            " --- argument dereference (x0..xN as pointers, via AXI) ---\n"
            f"  {reg}  -> PA 0x{pa:08x}\n        hex: {hexb}\n")
def run(text, *args):
    return subprocess.run(["python3","tools/break-secrets.py","-",*args],
                          input=text, capture_output=True, text=True).stdout

# 1. a VxWorks boot-line password in x1 at an auth function → caught CRIT, attributed to the fn + reg
o = run(cap("vxAuthCheck","x1",0x08000000, b"gei(0,0)host:/img u=target pw=S3cr3tPass f=0x0"))
if "vxAuthCheck" not in o or "x1" not in o: bad("should attribute the catch to the function + register")
if "pw=S3cr3tPass" not in o: bad("should recover the boot-line password from the dereferenced pointer")
if "CRIT" not in o: bad("a password in flight should be CRIT")

# 2. a PEM private key in x0 → caught
pem = b"-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA" + b"A"*20
o = run(cap("keyLoad","x0",0x100a0000, pem))
if "x0" not in o or "BEGIN" not in o.upper() and "key" not in o.lower(): bad("should catch a PEM key in flight")

# 3. --min-sev filters
o = run(cap("f","x1",0x08000000, b"nothing secret here just text padding padding"), "--min-sev","CRIT")
if "no secrets matched" not in o and "CRIT" in o: bad("min-sev CRIT should filter out non-CRIT noise")

# 4. no deref / empty capture → honest "nothing"
if "no secrets matched" not in run(" #0 f @ 0x0 x0=0x1\n"): bad("a capture with no deref should report nothing honestly")

print("  break-secrets OK (boot-line pw + PEM key caught in flight, attributed, sev-filtered)")
PY

echo "PASS: break-secrets (automatic secret-in-flight capture from break-capture derefs)"
