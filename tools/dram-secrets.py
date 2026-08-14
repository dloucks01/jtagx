#!/usr/bin/env python3
"""
dram-secrets.py — secret / credential / key extractor for a LIVE-OS DRAM dump.

This targets exactly the material a static flash boot image does NOT contain — things that only exist
in RAM at runtime: the VxWorks boot line (network-boot user/password), decrypted keys, login/credential
tables, in-memory certs and private keys, session tokens, connection strings, and high-entropy key
candidates. It is the analysis pass for Capability 1.2 (dump-os-ddr.tcl -> dumps/os-live.bin) in
docs/21; the flash boot image goes through parse-bootimage / Ghidra instead.

Usage:
    python3 tools/dram-secrets.py dumps/os-live.bin                  # full scan, ranked report
    python3 tools/dram-secrets.py dumps/os-live.bin --base 0x100000  # report physical addrs (DUMP_ADDR)
    python3 tools/dram-secrets.py dumps/os-live.bin --all            # don't cap per-category output
    python3 tools/dram-secrets.py dumps/os-live.bin -o report.md     # write a markdown report

Read-only / offline. Findings are heuristic — verify before acting. Authorized testing only.
"""
import argparse, math, re, sys
from collections import Counter

# ---------------------------------------------------------------------------------------------------
def shannon(b):
    if not b:
        return 0.0
    c = Counter(b); n = len(b)
    return -sum((v/n) * math.log2(v/n) for v in c.values())

_STR_RX = {}
def strings(data, minlen=5):
    """Yield (offset, text) for printable ASCII runs (incl. tab) >= minlen.
    Regex-driven (C-level) — ~8.5x faster than a Python byte loop, byte-identical output."""
    rx = _STR_RX.get(minlen)
    if rx is None:
        rx = _STR_RX[minlen] = re.compile(rb'[\x20-\x7e\x09]{%d,}' % minlen)
    for m in rx.finditer(data):
        yield m.start(), m.group(0).decode('ascii', 'replace')

# --- AES key-schedule finder (the aeskeyfind technique) ----------------------------------------------
# A real, in-use AES key is EXPANDED into a key schedule (176/208/240 B for AES-128/192/256) whose
# round keys satisfy a deterministic relationship (RotWord/SubWord/Rcon). Verifying that relationship
# is a near-certain key detector (random data passes with prob ~2^-128) — so this finds ACTUAL keys
# with essentially no false positives, unlike entropy. The first 16/24/32 B of a valid schedule = key.
_AES_SBOX = bytes.fromhex(
 "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0"
 "b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275"
 "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf"
 "d0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2"
 "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb"
 "e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08"
 "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e"
 "e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6428441992d0fb054bb16")
_SBOX_T = bytes.maketrans(bytes(range(256)), _AES_SBOX)
_RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d]

def _aes_schedule_valid(buf, nk):
    nr = {4:10, 6:12, 8:14}[nk]; total = 4*(nr+1)
    if len(buf) < total*4: return False
    W = [buf[k*4:k*4+4] for k in range(total)]
    for i in range(nk, total):
        t = W[i-1]
        if i % nk == 0:
            sw = (t[1:]+t[:1]).translate(_SBOX_T)
            t = bytes((sw[0]^_RCON[i//nk-1], sw[1], sw[2], sw[3]))
        elif nk > 6 and i % nk == 4:
            t = t.translate(_SBOX_T)
        if bytes(a^b for a, b in zip(W[i-nk], t)) != W[i]:
            return False
    return True

def find_aes_keys(data):
    """Return [(offset, keysize_bytes, key_hex)] for validated AES key schedules. Skips zero blocks
    (fast on sparse dumps); ~word-aligned scan with a cheap first-derived-word filter before full verify."""
    out = []; n = len(data); BLK = 1 << 16
    for bs in range(0, n, BLK):
        blk = data[bs:bs+BLK+240]
        if not any(blk): continue                       # all-zero region -> no keys, skip fast
        L = len(blk)
        for j in range(0, L-176, 4):
            w0 = blk[j:j+4]
            # AES-128 cheap filter: W4 == W0 ^ SubWord(RotWord(W3)) ^ Rcon1
            w3 = blk[j+12:j+16]; sw = (w3[1:]+w3[:1]).translate(_SBOX_T)
            if (blk[j+16]==(w0[0]^sw[0]^1) and blk[j+17]==(w0[1]^sw[1])
                    and blk[j+18]==(w0[2]^sw[2]) and blk[j+19]==(w0[3]^sw[3])):
                if _aes_schedule_valid(blk[j:j+176], 4): out.append((bs+j, 16, blk[j:j+16].hex()))
            # AES-256 cheap filter: W8 == W0 ^ SubWord(RotWord(W7)) ^ Rcon1
            if j+240 <= L:
                w7 = blk[j+28:j+32]; sw2 = (w7[1:]+w7[:1]).translate(_SBOX_T)
                if (blk[j+32]==(w0[0]^sw2[0]^1) and blk[j+33]==(w0[1]^sw2[1])
                        and blk[j+34]==(w0[2]^sw2[2]) and blk[j+35]==(w0[3]^sw2[3])):
                    if _aes_schedule_valid(blk[j:j+240], 8): out.append((bs+j, 32, blk[j:j+32].hex()))
    return out

def ctx(data, off, before=24, after=48):
    s = data[max(0, off-before):off+after]
    return ''.join(chr(c) if 0x20 <= c < 0x7f else '.' for c in s)

# ---------------------------------------------------------------------------------------------------
# Findings: list of (severity, category, addr, label, detail). severity: CRIT > HIGH > MED > INFO.
SEV = {'CRIT': 0, 'HIGH': 1, 'MED': 2, 'INFO': 3}

def scan(data, base, aes=True):
    F = []
    def add(sev, cat, off, label, detail): F.append((sev, cat, base+off, label, detail))
    text_all = list(strings(data, 5))

    # --- 0) VALIDATED AES keys (key-schedule math — near-zero false positives, unlike entropy) -------
    if aes:
        for off, ks, hx in find_aes_keys(data):
            add('CRIT', 'aes-key', off, f'AES-{ks*8} key (valid key schedule)', hx)

    # --- 1) VxWorks boot line — carries network-boot host + USER (u=) + PASSWORD (pw=) ---------------
    # Format e.g.:  gei(0,0)host:/img h=10.0.0.1 e=10.0.0.2 u=target pw=secret f=0x0 tn=board s=...
    bl = re.compile(rb'[a-zA-Z][a-zA-Z0-9]{1,8}\(\d+,\d+\)[^\s]{0,40}:[^\x00\n]{0,200}')
    seen_bl = set()
    for m in bl.finditer(data):
        s = m.group(0).decode('latin1', 'replace')
        if ('h=' in s or 'e=' in s or 'u=' in s or 'pw=' in s) and s not in seen_bl:
            seen_bl.add(s)
            sev = 'CRIT' if 'pw=' in s else 'HIGH'
            add(sev, 'vxworks-bootline', m.start(), 'VxWorks boot line', s[:200])
    # also a bare "u=.. pw=.." pair anywhere
    for m in re.finditer(rb'\bu=([!-~]{1,32})\s+pw=([!-~]{1,32})', data):
        add('CRIT', 'vxworks-bootline', m.start(), 'boot user/password',
            f"u={m.group(1).decode('latin1')}  pw={m.group(2).decode('latin1')}")

    # --- 2) PEM blocks (private keys, certs) --------------------------------------------------------
    for m in re.finditer(rb'-----BEGIN ([A-Z0-9 ]+)-----.{0,8000}?-----END \1-----', data, re.S):
        kind = m.group(1).decode('latin1')
        sev = 'CRIT' if 'PRIVATE' in kind else ('HIGH' if 'KEY' in kind else 'MED')
        add(sev, 'pem', m.start(), f'PEM {kind}', f'{len(m.group(0))} bytes')

    # --- 3) SSH keys (authorized_keys / known_hosts style) ------------------------------------------
    for m in re.finditer(rb'\b(ssh-(?:rsa|ed25519|dss)|ecdsa-sha2-\w+)\s+[A-Za-z0-9+/]{40,}={0,3}', data):
        add('HIGH', 'ssh-key', m.start(), m.group(1).decode(), ctx(data, m.start()))

    # --- 4) Unix / crypt password hashes ($1$ md5, $5$ sha256, $6$ sha512, $2y$ bcrypt, $y$ yescrypt) -
    for m in re.finditer(rb'\$(1|2[abxy]?|5|6|y|gy|7|sha1)\$[./A-Za-z0-9$]{12,}', data):
        add('HIGH', 'pw-hash', m.start(), 'crypt() hash', m.group(0)[:80].decode('latin1'))
    # classic /etc/passwd or shadow-ish "user:hash:" line
    for m in re.finditer(rb'[a-zA-Z_][a-zA-Z0-9_-]{0,31}:\$[0-9a-z]{1,3}\$[./A-Za-z0-9$]{12,}', data):
        add('HIGH', 'pw-hash', m.start(), 'shadow-style line', m.group(0)[:100].decode('latin1'))

    # --- 5) Tokens: JWT, AWS, bearer, generic api keys ----------------------------------------------
    for m in re.finditer(rb'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}', data):
        add('HIGH', 'token', m.start(), 'JWT', m.group(0)[:96].decode('latin1') + '…')
    for m in re.finditer(rb'\b(AKIA|ASIA)[0-9A-Z]{16}\b', data):
        add('HIGH', 'token', m.start(), 'AWS access key id', m.group(0).decode())
    for m in re.finditer(rb'(?i)\b(bearer)\s+[A-Za-z0-9._\-]{16,}', data):
        add('MED', 'token', m.start(), 'Bearer token', ctx(data, m.start()))
    for m in re.finditer(rb'(?i)(api[_-]?key|secret[_-]?key|access[_-]?token|client[_-]?secret)'
                         rb'["\']?\s*[:=]\s*["\']?([!-~]{8,80})', data):
        add('HIGH', 'token', m.start(), m.group(1).decode().lower(), ctx(data, m.start()))

    # --- 6) Credential keyword strings (password=, passwd, secret, connection strings) --------------
    kw = re.compile(r'(?i)\b(pass(?:word|wd|phrase)?|secret|credential|private[ _-]?key|'
                    r'wpa[_-]?psk|psk|pre[_-]?shared|community)\b')
    cred_re = re.compile(r'(?i)(password|passwd|pwd|secret|psk|token|key)\s*[:=]\s*(\S{3,80})')
    for off, s in text_all:
        if len(s) > 400:  # skip giant blobs for the keyword pass
            s = s[:400]
        cm = cred_re.search(s)
        if cm:
            add('HIGH', 'cred-string', off, cm.group(1).lower() + '=…',
                s.strip()[:120])
        elif kw.search(s) and any(c in s for c in ':=') is False:
            add('MED', 'cred-keyword', off, 'keyword', s.strip()[:120])

    # connection strings  proto://user:pass@host
    for m in re.finditer(rb'\b[a-z][a-z0-9+.\-]{1,15}://[!-~]{1,40}:[!-~]{1,60}@[!-~]{1,80}', data):
        add('CRIT', 'conn-string', m.start(), 'URL with credentials', m.group(0)[:120].decode('latin1'))

    # --- 7) X.509 DER certs / DER keys in binary (SEQUENCE-of-SEQUENCE) ------------------------------
    for m in re.finditer(rb'\x30\x82(..)\x30\x82', data, re.S):
        ln = int.from_bytes(m.group(1), 'big')
        if 256 <= ln <= 8000:
            add('MED', 'der', m.start(), 'DER structure (cert/key?)', f'~{ln+4} bytes')

    # --- 8) Crypto anchors — locate AES S-box & SHA-256 constants (keys/IVs live nearby) ------------
    AES_SBOX = bytes.fromhex('637c777bf26b6fc53001672bfed7ab76')      # first 16 of the AES S-box
    SHA256_K = bytes.fromhex('428a2f9871374491b5c0fbcfe9b5dba5')      # first 16 SHA-256 round constants
    for anchor, name in ((AES_SBOX, 'AES S-box'), (SHA256_K, 'SHA-256 constants')):
        i = data.find(anchor)
        while i != -1:
            add('INFO', 'crypto-anchor', i, name, 'crypto code/context — scan nearby for keys/IVs')
            i = data.find(anchor, i+1)

    # --- 9) High-entropy 32-byte key candidates — ISOLATED only -------------------------------------
    # A real symmetric key is a short high-entropy blob bordered by STRUCTURE (zeros, pointers, ASCII) —
    # e.g. a key field inside a C struct. Compressed/packed/encrypted *sections* are also high-entropy
    # but run for KB with high-entropy neighbours; flagging their interior is noise. So: keep a window
    # only if at least one 48-byte neighbour is low-entropy/zeroy (a boundary), which drops compression.
    def structured(b):    # a real border: lots of zeros (padding/alignment) or genuinely low entropy
        return b.count(0) >= 12 or (len(b) >= 16 and shannon(b) < 2.5)
    W, STRIDE = 32, 16
    n = len(data)
    hits = []                                     # (offset, entropy) of qualifying windows
    for i in range(0, n - W, STRIDE):
        w = data[i:i+W]
        if len(set(w)) < 22:                      # too repetitive to be a key
            continue
        e = shannon(w)
        if e < 4.7:                               # ~near-max for 32 bytes (5.0 = all distinct)
            continue
        # a real key is a SHORT high-entropy field bounded by structure on BOTH sides; a compressed/
        # packed section is high-entropy on at least one side, so require both -> kills that noise.
        if not (structured(data[max(0,i-48):i]) and structured(data[i+W:i+W+48])):
            continue
        hits.append((i, e))
    # MERGE overlapping/adjacent windows into ONE region per finding (the 16-byte stride otherwise
    # reports the same high-entropy blob 3-4x). A region is [start, end); report it once.
    regions = []
    for i, e in hits:
        if regions and i <= regions[-1][1] + 64:
            if i + W > regions[-1][1]: regions[-1][1] = i + W
            if e > regions[-1][2]: regions[-1][2] = e
        else:
            regions.append([i, i + W, e])
    for s, en, e in sorted(regions, key=lambda r: r[2], reverse=True):
        sz = en - s
        snip = data[s:s+32].hex() + ('…' if sz > 32 else '')
        add('MED', 'key-candidate', s, f'isolated high-entropy region {sz}B (H={e:.2f})', snip)

    return F

# ---------------------------------------------------------------------------------------------------
def report(F, total, base, cap, out):
    F.sort(key=lambda x: (SEV[x[0]], x[1], x[2]))
    cats = Counter(f[1] for f in F)
    sevs = Counter(f[0] for f in F)
    L = []
    L.append(f"# DRAM secrets scan — {total} bytes (base 0x{base:08x})\n")
    L.append(f"**{len(F)} findings** — "
             + ", ".join(f"{sevs[s]} {s}" for s in ('CRIT','HIGH','MED','INFO') if sevs[s]) + "\n")
    L.append("Heuristic — verify each before acting. CRIT/HIGH first.\n")
    order = ['aes-key','vxworks-bootline','conn-string','pem','pw-hash','ssh-key','token','cred-string',
             'cred-keyword','der','key-candidate','crypto-anchor']
    # high-value categories are precise -> show all (in a file) or 8 (stdout). The heuristic categories
    # are inherently noisy on real firmware (every hash/nonce/packed-boundary looks high-entropy), so
    # they get a HARD top-N cap even in a file — they're a triage list, not an exhaustive one.
    NOISY = {'key-candidate': 40, 'cred-keyword': 25, 'crypto-anchor': 25, 'der': 40}
    by = {}
    for f in F: by.setdefault(f[1], []).append(f)
    for cat in order + [c for c in by if c not in order]:
        items = by.get(cat)
        if not items: continue
        hardcap = NOISY.get(cat)
        eff = hardcap if hardcap is not None else cap          # noisy: always cap; else honor cap (None=all)
        L.append(f"\n## {cat}  ({len(items)})")
        shown = items if eff is None else items[:eff]
        for sev, _c, addr, label, detail in shown:
            L.append(f"- **[{sev}]** `0x{addr:08x}`  {label}: `{detail}`")
        if eff is not None and len(items) > eff:
            extra = f" (heuristic noise — top {eff} by rank shown)" if hardcap else " (use --all)"
            L.append(f"  …and {len(items)-eff} more{extra}")
    text = "\n".join(L) + "\n"
    if out:
        open(out, 'w').write(text); print(f"wrote {out} ({len(F)} findings)")
    else:
        print(text)

def main():
    ap = argparse.ArgumentParser(description="Extract secrets/keys/creds from a live-OS DRAM dump.")
    ap.add_argument("dump", help="memory dump file (e.g. dumps/os-live.bin)")
    ap.add_argument("--base", default="0", help="base address added to offsets (e.g. 0x100000 = DUMP_ADDR)")
    ap.add_argument("--all", action="store_true", help="show every finding on stdout (no per-category cap)")
    ap.add_argument("--no-aes", action="store_true", help="skip the AES key-schedule scan (faster; it's ~1-2 min on a busy 32 MB)")
    ap.add_argument("-o", "--out", help="write a FULL markdown report to this file (never capped)")
    a = ap.parse_args()
    try:
        data = open(a.dump, 'rb').read()
    except OSError as e:
        sys.exit(f"cannot read {a.dump}: {e}")
    if not data:
        sys.exit("empty dump")
    base = int(a.base, 0)
    F = scan(data, base, aes=not a.no_aes)
    cap = None if (a.all or a.out) else 8     # a file report is always complete; stdout caps unless --all
    report(F, len(data), base, cap, a.out)

if __name__ == "__main__":
    main()
