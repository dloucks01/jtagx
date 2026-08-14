#!/usr/bin/env python3
"""
oe-key-extract.py — turn a break-capture blob into the OE/AES key. The turnkey back-half of the
crypto-break: run the break-capture recipe (docs: reports/vxworks-analysis.md) on OE_Encryptor_Create,
save the dereferenced config bytes, then feed them here.

It finds keys two ways:
  1. AES key-SCHEDULE detection — if the app stored an EXPANDED round-key schedule (common for speed),
     we detect it and RECOVER the original key (AES-128/192/256). This is a positive identification.
  2. High-entropy window scan — flags 16/24/32-byte runs that look like raw key material (verify).

Usage:
    # save the config deref from break-capture to a file, then:
    python3 tools/oe-key-extract.py oe-config.bin
    python3 tools/oe-key-extract.py oe-config.bin --base 0x...   # label offsets as VAs
Offline. Pairs with openocd/break-capture.tcl (BC_ADDR=OE_Encryptor_Create, BC_DEREF).
"""
import argparse, math, sys

SBOX = bytes.fromhex(
    "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0"
    "b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275"
    "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf"
    "d0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2"
    "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb"
    "e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08"
    "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e"
    "e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16")
RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36, 0x6C, 0xD8, 0xAB, 0x4D]


def _expand(key):
    """AES key expansion → the full round-key schedule bytes (176/208/240 for 128/192/256)."""
    Nk = len(key) // 4
    Nr = {4: 10, 6: 12, 8: 14}[Nk]
    words = [list(key[4 * i:4 * i + 4]) for i in range(Nk)]
    for i in range(Nk, 4 * (Nr + 1)):
        t = list(words[i - 1])
        if i % Nk == 0:
            t = t[1:] + t[:1]                       # RotWord
            t = [SBOX[b] for b in t]                # SubWord
            t[0] ^= RCON[i // Nk - 1]
        elif Nk > 6 and i % Nk == 4:
            t = [SBOX[b] for b in t]
        words.append([words[i - Nk][j] ^ t[j] for j in range(4)])
    return bytes(b for w in words for b in w)


def find_schedules(data):
    """Detect stored AES key schedules; return [(offset, keylen, key_hex)]."""
    hits = []
    for klen, sched in ((16, 176), (24, 208), (32, 240)):
        off = 0
        while off + sched <= len(data):
            key = data[off:off + klen]
            if len(set(key)) > 4 and data[off:off + sched] == _expand(key):
                hits.append((off, klen, key.hex()))
                off += sched
            else:
                off += 4
    return hits


def entropy(b):
    if not b:
        return 0.0
    counts = [0] * 256
    for x in b:
        counts[x] += 1
    return -sum((c / len(b)) * math.log2(c / len(b)) for c in counts if c)


def high_entropy_windows(data, win=32, thr=4.3, step=8):
    out = []
    i = 0
    while i + win <= len(data):
        h = entropy(data[i:i + win])
        if h >= thr and len(set(data[i:i + win])) > win // 2:
            out.append((i, round(h, 2), data[i:i + 16].hex()))
            i += win
        else:
            i += step
    return out


def main():
    ap = argparse.ArgumentParser(description="Extract an OE/AES key from a break-capture config blob.")
    ap.add_argument("blob", help="binary file: the deref'd config/registers from break-capture")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0, help="VA of byte 0 (label offsets)")
    a = ap.parse_args()
    data = open(a.blob, "rb").read()
    print(f"# oe-key-extract: {a.blob} ({len(data)} bytes)")

    scheds = find_schedules(data)
    print(f"\n## AES key schedules (POSITIVE — recovered key) : {len(scheds)}")
    for off, klen, kh in scheds:
        print(f"  [KEY] AES-{klen*8}  @ 0x{a.base+off:08x}  key = {kh}")
    if not scheds:
        print("  (none — the app may keep only the raw key, or no OE encryptor was captured)")

    win = high_entropy_windows(data)
    print(f"\n## high-entropy candidates (verify) : {len(win)}")
    for off, h, head in win[:16]:
        print(f"  [cand] @ 0x{a.base+off:08x}  H={h}/8  {head}…")
    if len(win) > 16:
        print(f"  …and {len(win)-16} more")


if __name__ == "__main__":
    main()
