#!/usr/bin/env python3
"""
symbolize.py — map VAs to "symbol + offset" using a vxworks-symtab address map. Reusable for break-capture
backtraces, captured PCs, watch-access PCs, anything that prints kernel VAs. Reads addresses from args or
stdin (it scans any 0x… hex tokens), so you can pipe a whole break-capture log through it.

Usage:
  tools/symbolize.py 0xffffffff803fbe40 0xffffffff803ed870
  openocd ... source openocd/break-capture.tcl ... | tools/symbolize.py        # annotate a backtrace log
  tools/symbolize.py --syms dumps/symbols.txt --annotate < /tmp/bc.out
"""
import sys, re, bisect, argparse

def load(path):
    syms = []
    for ln in open(path):
        p = ln.split()
        if len(p) >= 2 and p[0].startswith("0x"):
            try:
                syms.append((int(p[0], 16), p[1]))
            except ValueError:
                pass
    syms.sort()
    return [a for a, _ in syms], syms

def look(addrs, syms, va):
    i = bisect.bisect_right(addrs, va) - 1
    if i < 0:
        return None
    a, n = syms[i]
    return f"{n}+0x{va-a:x}" if va != a else n

def main():
    ap = argparse.ArgumentParser(description="VA -> symbol+offset via a vxworks-symtab map.")
    ap.add_argument("addrs", nargs="*", help="hex VAs (or pipe text via stdin)")
    ap.add_argument("--syms", default="dumps/symbols.txt", help="addr name map (default dumps/symbols.txt)")
    ap.add_argument("--annotate", action="store_true",
                    help="echo stdin lines, appending the symbol after each hex VA found")
    a = ap.parse_args()
    try:
        addrs, syms = load(a.syms)
    except OSError as e:
        sys.exit(f"error: cannot read the symbol map {a.syms!r}: {e}\n"
                 f"  generate one first: python3 tools/vxworks-symtab.py <kernel.bin> --out-map {a.syms}")
    if not syms:
        sys.exit(f"no symbols loaded from {a.syms}")

    hexrx = re.compile(r"0x[0-9a-fA-F]{6,}")
    if a.addrs:
        for tok in a.addrs:
            for m in hexrx.findall(tok) or [tok]:
                try:
                    va = int(m, 16)
                except ValueError:
                    continue
                print(f"{m}  {look(addrs, syms, va) or '(no symbol below)'}")
    else:
        for ln in sys.stdin:
            line = ln.rstrip("\n")
            if a.annotate:
                hits = hexrx.findall(line)
                anns = [look(addrs, syms, int(m, 16)) for m in hits]
                anns = [x for x in anns if x]
                print(line + (f"   => {', '.join(anns)}" if anns else ""))
            else:
                for m in hexrx.findall(line):
                    print(f"{m}  {look(addrs, syms, int(m, 16)) or '(no symbol below)'}")

if __name__ == "__main__":
    main()
