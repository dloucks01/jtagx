#!/usr/bin/env python3
"""
break-secrets.py — AUTOMATIC secret-in-flight capture. Post-process openocd/break-capture.tcl output:
for every dereferenced argument pointer (`xN -> PA 0x… / hex: …`), run the dram-secrets scanner over
the pointed-to bytes, so a breakpoint on an auth/crypto function reports the password / key / token it
caught IN FLIGHT — not just a raw register+memory dump. This is the payoff of break-capture's deref.

    BC_ADDR=0x<vAuthCheck> BC_DEREF="0 1" openocd ... source openocd/break-capture.tcl | tee cap.txt
    tools/break-secrets.py cap.txt          # → "[vxAuthCheck] x1 -> caught CRIT boot user/password: ..."

Offline, read-only; it only interprets a capture you already took (hands-on model). Reuses the
dram-secrets pattern engine (bootline creds, PEM/SSH keys, tokens, AES key schedules, high-entropy).
"""
import argparse
import binascii
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("dram_secrets", os.path.join(HERE, "dram-secrets.py"))
ds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ds)

HIT_RE = re.compile(r"#\s*\d+\s+(\S+)\s+@\s+(0x[0-9a-fA-F]+)")
DEREF_RE = re.compile(r"\b(x\d+|sp|lr)\s+->\s+PA\s+(0x[0-9a-fA-F]+)")
HEX_RE = re.compile(r"hex:\s*([0-9a-fA-F ]+)")


def parse(text):
    """Yield (who, reg, pa, bytes) for each deref block in a break-capture transcript."""
    who = "?"
    reg = pa = None
    for line in (text or "").splitlines():
        h = HIT_RE.search(line)
        if h:
            who = h.group(1)
            continue
        d = DEREF_RE.search(line)
        if d:
            reg, pa = d.group(1), int(d.group(2), 16)
            continue
        hx = HEX_RE.search(line)
        if hx and reg is not None:
            try:
                b = binascii.unhexlify("".join(hx.group(1).split()))
            except Exception:
                b = b""
            if b:
                yield (who, reg, pa, b)
            reg = pa = None


def main():
    ap = argparse.ArgumentParser(description="Scan break-capture deref'd pointers for secrets in flight.")
    ap.add_argument("capture", nargs="?", default="-", help="break-capture output file (- = stdin)")
    ap.add_argument("--min-sev", choices=["LOW", "MED", "HIGH", "CRIT"], default="LOW")
    a = ap.parse_args()
    try:
        text = sys.stdin.read() if a.capture == "-" else \
            open(a.capture, encoding="utf-8", errors="replace").read()
    except OSError as e:
        sys.exit(f"error: cannot read {a.capture}: {e.strerror}")
    rank = {"LOW": 0, "MED": 1, "HIGH": 2, "CRIT": 3}
    floor = rank[a.min_sev]

    print("# secrets caught in flight (break-capture deref → dram-secrets)")
    n = 0
    for who, reg, pa, b in parse(text):
        for sev, cat, off, label, detail in ds.scan(b, pa, aes=True):
            if rank.get(sev, 0) < floor:
                continue
            n += 1
            print(f"  [{who}] {reg} -> PA 0x{pa:08x}  {sev}  {cat}: {label}")
            if detail:
                print(f"        {str(detail)[:160]}")
    if not n:
        print("  (no secrets matched in the dereferenced pointers — try more BC_DEREF indices / BC_DEREF_LEN, "
              "or the arg isn't a pointer-to-secret at this breakpoint)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
