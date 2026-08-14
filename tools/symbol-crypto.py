#!/usr/bin/env python3
"""
symbol-crypto.py — SYMBOL-GUIDED crypto/secret extraction from a live-OS DRAM dump.

Instead of entropy-guessing across all of RAM, this targets exactly where keys live: named global
buffers. It reads a VxWorks symbol map (vxworks-symtab.py --out-map: "0xADDR name" lines), keeps the
crypto/credential-named symbols (key, secret, ssl, tls, aes, rsa, cert, hmac, iv, nonce, token, …),
maps each symbol's link VA to its offset in the dump, reads the bytes, and CLASSIFIES them — flagging
VALIDATED AES keys (key-schedule math, ~zero false positives), printable secrets/strings, and
high-entropy (likely key) material. The address math is the only board-specific part (defaults below
are the validated ZCU102/VxWorks values).

Usage:
    # symbols carved from the flash image (Cap 1.5) + the live DRAM dump (Cap 1.2):
    python3 tools/symbol-crypto.py dumps/os-live.bin --syms dumps/symbols.txt -o reports/sym-crypto.md

    # if the dump starts at PA 0x0 (a full-DDR sparse capture), tell it: --dump-base 0x0
    python3 tools/symbol-crypto.py dumps/ddr-full.bin --syms dumps/symbols.txt --dump-base 0x0

Offset math:  file_offset = (VA - va_base) + (load_pa - dump_base)
  va_base   = kernel link VA        (default 0xFFFFFFFF80100000)
  load_pa   = kernel load phys addr (default 0x100000)
  dump_base = phys addr of dump byte 0 = the DUMP_ADDR you used (default 0x100000)
With the os-live defaults (load_pa == dump_base) this reduces to VA - va_base. Read-only / offline.
"""
import argparse, importlib.util, os, re, sys
from collections import Counter

# reuse the VALIDATED AES key finder + entropy from dram-secrets.py (same dir)
_ds = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dram-secrets.py')
_spec = importlib.util.spec_from_file_location('dram_secrets', _ds)
_m = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_m)
find_aes_keys, shannon = _m.find_aes_keys, _m.shannon

CRYPTO = re.compile(r'(?i)(?:'
    r'priv(?:ate)?[_-]?key|pub(?:lic)?[_-]?key|secret|passw(?:or)?d|passphrase|'
    r'\bkey\b|_key|key_|keys|keystore|keyring|kek|dek|master[_-]?secret|session[_-]?key|'
    r'cert|x509|ssl|tls|dtls|wolfssl|mbedtls|openssl|libcrypto|'
    r'\baes\b|3des|\bdes\b|\brc4\b|\brsa\b|\bdsa\b|ecdsa|\becc\b|ecdh|curve25519|ed25519|'
    r'hmac|sha1|sha256|sha512|\bsha\b|\bmd5\b|cipher|crypt|encrypt|decrypt|'
    r'\biv\b|nonce|\bsalt\b|\bseed\b|prng|\brng\b|random|entropy|'
    r'cred(?:ential)?|token|\bauth\b'
    r')')
EXCLUDE = re.compile(r'(?i)monkey|donkey|keyboard|keyword|hockey|turnkey|whiskey|jockey|lackey|authority')

RANK = {'aes': 0, 'entropy': 1, 'string': 2, 'data': 3, 'oob': 4, 'zero': 5}
FLAG = {'aes': '**[AES KEY]**', 'entropy': '**[HIGH-ENTROPY]**', 'string': '[string]',
        'data': '[data]', 'oob': '[out-of-range]', 'zero': '[zero]'}

# split camelCase + letter/digit runs so "wlanAesKey"/"aes256key" tokenize -> the \b patterns match
_SPLIT = re.compile(r'(?<=[a-z])(?=[A-Z])|(?<=[a-zA-Z])(?=[0-9])|(?<=[0-9])(?=[a-zA-Z])')
def is_crypto(name):
    n = _SPLIT.sub(' ', name)
    return bool(CRYPTO.search(n)) and not EXCLUDE.search(n)

def classify(b):
    keys = find_aes_keys(b)                 # validated AES key schedule anywhere in the global
    if keys:
        o, ks, hx = keys[0]
        return ('aes', f'VALIDATED AES-{ks*8} KEY @+0x{o:x} = {hx}')
    bt = b.rstrip(b'\x00')                   # a global is content-then-zero-padding; judge the content
    if not bt:
        return ('zero', 'all-zero (uninitialized / not in use)')
    printable = sum(1 for c in bt if 0x20 <= c < 0x7f or c in (9, 10, 13))
    if len(bt) >= 4 and printable >= len(bt) * 0.85:
        s = ''.join(chr(c) if 0x20 <= c < 0x7f else ' ' for c in bt).strip()
        return ('string', f'string: {s[:140]!r}')
    e = max(shannon(bt[:16]), shannon(bt[:32]), shannon(bt[:48]))   # key-sized windows, not diluted
    if e >= 4.3:
        return ('entropy', f'high-entropy (H={e:.2f}/8 over a key-sized window) — likely key/secret material')
    return ('data', f'mixed data (H={e:.2f}/8)')

def main():
    ap = argparse.ArgumentParser(description="Symbol-guided crypto/secret extraction from a DRAM dump.")
    ap.add_argument("dump")
    ap.add_argument("--syms", required=True, help="symbol map (vxworks-symtab.py --out-map): '0xADDR name'")
    ap.add_argument("--va-base", default="0xFFFFFFFF80100000", help="kernel link VA base")
    ap.add_argument("--load-pa", default="0x100000", help="kernel load physical address")
    ap.add_argument("--dump-base", default="0x100000", help="physical addr of dump byte 0 (= your DUMP_ADDR)")
    ap.add_argument("--size", type=int, default=256, help="bytes to read & classify per symbol (default 256)")
    ap.add_argument("--show-zero", action="store_true", help="also list zero/uninitialized globals")
    ap.add_argument("-o", "--out", help="write a markdown report instead of stdout")
    a = ap.parse_args()
    try:
        data = open(a.dump, 'rb').read()
    except OSError as e:
        sys.exit(f"cannot read {a.dump}: {e}")
    try:
        lines = open(a.syms).read().splitlines()
    except OSError as e:
        sys.exit(f"cannot read symbol map {a.syms}: {e}  (generate it: tools/vxworks-symtab.py … --out-map {a.syms})")
    delta = int(a.load_pa, 0) - int(a.dump_base, 0)
    va_base = int(a.va_base, 0)

    syms = []
    for ln in lines:
        ln = ln.strip()
        if not ln or ln.startswith('#'):
            continue
        p = ln.split(None, 1)
        if len(p) != 2:
            continue
        try:
            va = int(p[0], 0)
        except ValueError:
            continue
        name = p[1]
        if is_crypto(name):
            syms.append((va, name))

    findings = []
    for va, name in syms:
        off = (va - va_base) + delta
        if off < 0 or off >= len(data):
            findings.append(('oob', va, name, off, '(maps outside the dump range)', ''))
            continue
        b = data[off:off + a.size]
        kind, desc = classify(b)
        findings.append((kind, va, name, off, desc, b[:32].hex(' ')))
    findings.sort(key=lambda f: (RANK[f[0]], f[3]))

    cats = Counter(f[0] for f in findings)
    L = [f"# Symbol-guided crypto scan — {len(syms)} crypto/credential-named globals "
         f"({len(data)} byte dump, base mapping VA-0x{va_base:x}{'+0x%x'%delta if delta else ''})\n"]
    L.append("Each crypto-named global read at its mapped address. **AES keys are validated** "
             "(key-schedule math); high-entropy = likely key material; verify before acting.\n")
    L.append("summary: " + ", ".join(f"{cats[k]} {k}" for k in RANK if cats.get(k)) + "\n")
    for kind, va, name, off, desc, hx in findings:
        if kind == 'zero' and not a.show_zero:
            continue
        L.append(f"- {FLAG[kind]} `{name}`  VA=0x{va:016x}  off=0x{off:x}\n    {desc}"
                 + (f"\n    `{hx}`" if hx else ""))
    nz = len(syms) - cats.get('zero', 0)
    L.append(f"\n_{nz} of {len(syms)} crypto-named globals held non-zero data"
             + (f"; {cats.get('aes',0)} validated AES key(s)." if cats.get('aes') else "; no validated AES keys.") + "_")
    text = "\n".join(L) + "\n"
    if a.out:
        open(a.out, 'w').write(text); print(f"wrote {a.out} ({len(syms)} crypto symbols, {cats.get('aes',0)} AES keys)")
    else:
        print(text)

if __name__ == "__main__":
    main()
