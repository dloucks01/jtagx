#!/usr/bin/env python3
"""
find-patch-target.py — find good PRINTABLE-STRING targets for the Capability-2 live-patch demo.

Scans the kernel image (a partition from parse-bootimage --extract, or dumps/sd-extract/vxWorks.bin,
or a live DRAM dump) for printable strings, maps each to its RUNTIME virtual address, and ranks by how
VISIBLE + SAFE a demo target it is — banners / prompts / version & log messages (which the OS prints,
so a patch is observable) over symbol names, paths, and code. Patching a .rodata string can't crash
anything: it just changes displayed text. Feed the winner to probe-phys-patch.tcl as PATCH_VA.

Usage:
    python3 tools/find-patch-target.py dumps/parts/part*_kernel-or-app_*.bin
    python3 tools/find-patch-target.py dumps/sd-extract/vxWorks.bin
    # a full-DDR dump (byte0 = PA 0x0) puts the kernel at file offset 0x100000:  --img-base 0x100000

VA mapping:  VA = (file_offset - img_base) + va_base
  va_base  = kernel link VA (default 0xFFFFFFFF80100000) ; img_base = file offset of kernel byte 0 (0).
Read-only / offline. Then patch with an EQUAL-OR-SHORTER replacement:
  PATCH_VA=<VA> PATCH_STR='...' PATCH_RESTORE=0 \   # single-quote PATCH_STR in zsh (a '!' in "..." hangs at dquote>)
    openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
"""
import argparse, re, sys

GOOD = re.compile(r'(?i)vxworks|wind river|shell|version|copyright|welcome|ready|logged|login|'
                  r'banner|prompt|hello|kernel|system|started|initializ|firmware|console|'
                  r'error|warning|failed|unable|invalid|enabled|disabled|->\s')
SYMBOLISH = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')     # one identifier (symbol name)
PATHISH   = re.compile(r'^[/~][\w./-]*$|\.\w{1,4}$')    # a path or filename

def strings(data, minlen):
    cur = bytearray(); start = 0; term = 0
    for i, ch in enumerate(data):
        if 0x20 <= ch < 0x7f:
            if not cur: start = i
            cur.append(ch)
        else:
            if len(cur) >= minlen:
                yield start, cur.decode('ascii'), (ch == 0)   # null-terminated = a real C string
            cur = bytearray()
    if len(cur) >= minlen:
        yield start, cur.decode('ascii'), False

def score(s, nullterm):
    n = len(s); sc = 0
    if GOOD.search(s): sc += 50
    if ' ' in s: sc += 15                                  # a phrase/message, not an identifier
    sc += int(sum(c.isalpha() or c == ' ' for c in s) / max(n, 1) * 20)   # readable-English ratio
    if 8 <= n <= 48: sc += 15
    elif n < 6: sc -= 20
    elif n > 96: sc -= 15
    if nullterm: sc += 8
    if '%' in s: sc -= 12                                  # format string — specifiers are risky to alter
    if SYMBOLISH.match(s): sc -= 35
    if PATHISH.match(s): sc -= 20
    if s.count('/') >= 2 or s.count('_') >= 3: sc -= 12
    return sc

def main():
    ap = argparse.ArgumentParser(description="Find printable-string targets for the Cap-2 live-patch demo.")
    ap.add_argument("image", help="kernel image / partition / DRAM dump to scan")
    ap.add_argument("--va-base", default="0xFFFFFFFF80100000", help="kernel link VA base")
    ap.add_argument("--img-base", default="0", help="file offset where the kernel image starts (0; 0x100000 for full-DDR dump)")
    ap.add_argument("--minlen", type=int, default=6)
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--cfg", default="openocd/zcu102.cfg")
    a = ap.parse_args()
    try:
        data = open(a.image, 'rb').read()
    except OSError as e:
        sys.exit(f"cannot read {a.image}: {e}")
    va_base = int(a.va_base, 0); img_base = int(a.img_base, 0)

    cands = []; seen = set()
    for off, s, nt in strings(data, a.minlen):
        if s in seen or off < img_base: continue
        seen.add(s)
        sc = score(s, nt)
        if sc > 0:
            cands.append((sc, off, s))
    cands.sort(reverse=True)

    print(f"# printable-string patch targets in {a.image}")
    print(f"# VA = (offset - 0x{img_base:x}) + 0x{va_base:x};  {len(cands)} candidates, top {a.top}.")
    print(f"# Patch with an EQUAL-OR-SHORTER replacement so you don't overrun the field.\n")
    for sc, off, s in cands[:a.top]:
        va = (off - img_base) + va_base
        repl = ("PWNED-BY-JTAG " * 8)[:len(s)].rstrip()     # a same-length-ish demo replacement
        disp = s if len(s) <= 60 else s[:57] + "..."
        print(f"VA=0x{va:016x}  len={len(s):<3} score={sc:<3}  {disp!r}")
    if cands:
        sc, off, s = cands[0]
        va = (off - img_base) + va_base
        repl = ("PWNED-BY-JTAG " * 8)[:len(s)].rstrip()
        print(f"\n# top pick — ready to run (LEAVES the change; verify with `d 0x{va:x}` in the VxWorks shell):")
        print(f"PATCH_VA=0x{va:016x} PATCH_STR={repl!r} PATCH_RESTORE=0 \\")
        print(f"  openocd -f {a.cfg} -c \"init; source openocd/probe-phys-patch.tcl; shutdown\"")
    else:
        print("no good string targets found — lower --minlen or check the image base.")

if __name__ == "__main__":
    main()
