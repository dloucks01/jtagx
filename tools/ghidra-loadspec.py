#!/usr/bin/env python3
"""
ghidra-loadspec.py — given a raw firmware/kernel blob, determine what to type into Ghidra:
the LANGUAGE (architecture + endianness + bitness) and the BASE ADDRESS. Both are derived from
the bytes, not assumed — so this works on an unfamiliar blob from any board.

How it decides:
  * Architecture/endianness — trial-disassembles the start of the image under several candidate
    ISAs (capstone) and scores each by how much decodes as valid, contiguous instructions. The
    winner's disassembly preview is printed so you can eyeball that it's real code.
  * Base address — scans the blob for absolute self-pointers (the symbol table, jump tables,
    string pointers) and finds the base at which the most of them resolve to in-image targets
    (printable strings / aligned code). A wrong base resolves ~nothing; the right one resolves
    thousands. Handles high-canonical kernel VAs (0xFFFF............).

Usage:
    python3 tools/ghidra-loadspec.py dumps/sd-extract/vxWorks.bin
    python3 tools/ghidra-loadspec.py blob.bin --window 65536

Output ends with the exact Ghidra load settings (Language id + Base Address).
Caveats it can't see: a base it reports is the LINK base; if the blob has no absolute self-pointers
(pure PIC, or all-relative) base detection abstains and you fall back to the loader's load address.
"""
import argparse
import struct
import sys
from pathlib import Path

try:
    import capstone as cs
except ImportError:
    cs = None

# (label, ghidra_language, cs_arch, cs_mode, bits)
ARCH_CANDIDATES = lambda: [
    ("AArch64 LE",   "AARCH64:LE:64",        cs.CS_ARCH_ARM64, cs.CS_MODE_LITTLE_ENDIAN, 64),
    ("AArch64 BE",   "AARCH64:BE:64",        cs.CS_ARCH_ARM64, cs.CS_MODE_BIG_ENDIAN,    64),
    ("ARM LE",       "ARM:LE:32:v8",         cs.CS_ARCH_ARM,   cs.CS_MODE_ARM,           32),
    ("ARM BE",       "ARM:BE:32:v8",         cs.CS_ARCH_ARM,   cs.CS_MODE_ARM | cs.CS_MODE_BIG_ENDIAN, 32),
    ("Thumb LE",     "ARM:LE:32:v8T",        cs.CS_ARCH_ARM,   cs.CS_MODE_THUMB,         32),
    ("x86-64",       "x86:LE:64:default",    cs.CS_ARCH_X86,   cs.CS_MODE_64,            64),
    ("x86-32",       "x86:LE:32:default",    cs.CS_ARCH_X86,   cs.CS_MODE_32,            32),
    ("MIPS32 LE",    "MIPS:LE:32:default",   cs.CS_ARCH_MIPS,  cs.CS_MODE_MIPS32 | cs.CS_MODE_LITTLE_ENDIAN, 32),
    ("MIPS32 BE",    "MIPS:BE:32:default",   cs.CS_ARCH_MIPS,  cs.CS_MODE_MIPS32 | cs.CS_MODE_BIG_ENDIAN,    32),
    ("PPC32 BE",     "PowerPC:BE:32:default", cs.CS_ARCH_PPC,  cs.CS_MODE_32 | cs.CS_MODE_BIG_ENDIAN,        32),
]


def score_arch(data, arch, mode, window):
    """Linear-sweep coverage: fraction of the window covered by valid contiguous instructions."""
    buf = data[:window]
    try:
        md = cs.Cs(arch, mode)
    except Exception:
        return 0.0, 0
    md.detail = False
    min_step = 2 if (mode & cs.CS_MODE_THUMB or arch == cs.CS_ARCH_X86) else 4
    covered = 0
    count = 0
    pos = 0
    n = len(buf)
    while pos < n:
        got = False
        for insn in md.disasm(buf[pos:pos + 64], 0):
            covered += insn.size
            count += 1
            pos += insn.size
            got = True
            break  # one at a time so an invalid byte only skips one step
        if not got:
            pos += min_step
    return covered / max(1, n), count


def detect_arch(data, window):
    # x86's variable-length decoder "decodes" almost any byte stream, so its coverage is
    # inflated and false-positives on RISC code. Penalize CISC coverage for RANKING only
    # (display the raw number) so a fixed-width RISC wins a genuine tie. Firmware is RISC-heavy.
    results = []
    for label, lang, arch, mode, bits in ARCH_CANDIDATES():
        cov, cnt = score_arch(data, arch, mode, window)
        # Dense variable-length decoders (x86 CISC, Thumb-16) "decode" almost any bytes, inflating
        # coverage and false-positiving on other ISAs. Penalize them for ranking; fixed-width RISC
        # (AArch64/ARM/MIPS/PPC) scoring high is trustworthy. Genuine x86/Thumb still wins its own
        # code easily (the alternatives score far lower there).
        permissive = (arch == cs.CS_ARCH_X86) or bool(mode & cs.CS_MODE_THUMB)
        rank = cov * (0.88 if permissive else 1.0)
        results.append((rank, cov, cnt, label, lang, arch, mode, bits))
    results.sort(reverse=True)
    return results


def _printable(b):
    return len(b) >= 1 and all(0x20 <= c < 0x7F for c in b)


def _plausible_ptr(w, ptr_size):
    if w & 3:
        return False
    if ptr_size == 8:
        return (0x1000 <= w < 0x0001_0000_0000_0000) or (0xFFFF_0000_0000_0000 <= w <= 0xFFFF_FFFF_FFFF_FFFF)
    return 0x1000 <= w < 0xFFFF_F000


def detect_base(data, ptr_size):
    """Find the link base by maximizing self-pointer resolution to in-image strings."""
    n = len(data)
    fmt = "<Q" if ptr_size == 8 else "<I"
    ptrs = []
    for off in range(0, n - ptr_size, 4):
        w = struct.unpack_from(fmt, data, off)[0]
        if _plausible_ptr(w, ptr_size):
            ptrs.append(w)
    if len(ptrs) < 8:
        return None
    ptrs.sort()
    # densest window of width n (the image footprint) over the sorted pointer values
    best_count, best_lo, lo_i = 0, ptrs[0], 0
    for hi_i in range(len(ptrs)):
        while ptrs[hi_i] - ptrs[lo_i] >= n:
            lo_i += 1
        if hi_i - lo_i + 1 > best_count:
            best_count = hi_i - lo_i + 1
            best_lo = ptrs[lo_i]
    # candidate bases: best_lo aligned down to several boundaries; validate by string resolution
    cands = {best_lo - (best_lo % a) for a in (0x1000, 0x10000, 0x100000, 0x1000000)}
    best = None
    for b in sorted(cands):
        hits = 0
        for p in ptrs:
            o = p - b
            if 0 <= o < n:
                z = data.find(b"\x00", o, min(o + 48, n))
                if z - o >= 4 and _printable(data[o:z]):
                    hits += 1
        if best is None or hits > best[1]:
            best = (b, hits)
    return best[0], best[1], len(ptrs)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Detect Ghidra language + base address for a raw blob")
    ap.add_argument("image")
    ap.add_argument("--window", type=int, default=0x10000, help="bytes to disassemble for arch scoring")
    args = ap.parse_args(argv)
    try:
        data = Path(args.image).read_bytes()
    except OSError as e:
        print(f"error: cannot read {args.image!r}: {e}", file=sys.stderr)
        return 1

    if cs is None:
        print("capstone not installed (pip install capstone) — cannot detect architecture.", file=sys.stderr)
        return 2

    print(f"image: {args.image}  ({len(data)} bytes)\n")
    archs = detect_arch(data, args.window)
    print("== architecture (trial disassembly, by coverage) ==")
    for rank, cov, cnt, label, lang, *_ in archs[:5]:
        print(f"  {cov*100:5.1f}%  {label:12} -> {lang}   ({cnt} insns)")
    top_rank, top_cov, _, top_label, top_lang, top_arch, top_mode, top_bits = archs[0]
    confident_arch = top_rank >= 0.90 and (archs[0][0] - archs[1][0]) >= 0.05

    base = detect_base(data, 8 if top_bits == 64 else 4)

    print("\n== base address (self-pointer clustering) ==")
    if base is None:
        print("  no absolute self-pointers found — base undetermined.")
        print("  fall back to the loader's load address (partition destinationLoadAddress).")
        base_addr = None
    else:
        base_addr, hits, total = base
        print(f"  base 0x{base_addr:016X}  ({hits}/{total} pointers resolve to in-image strings)")
        if hits < 16:
            print("  (low confidence — few pointers resolved; treat as a hint)")

    # disassembly preview at the winning arch so the user can eyeball sanity
    print(f"\n== disassembly preview ({top_label}) ==")
    try:
        md = cs.Cs(top_arch, top_mode)
        shown = 0
        start_va = base_addr if base_addr is not None else 0
        for insn in md.disasm(data[:64], start_va):
            print(f"  0x{insn.address:08X}:  {insn.mnemonic:8} {insn.op_str}")
            shown += 1
            if shown >= 12:
                break
    except Exception as e:
        print(f"  (preview failed: {e})")

    print("\n== Ghidra load settings ==")
    print(f"  Format        : Raw Binary")
    print(f"  Language      : {top_lang}" + ("" if confident_arch else "   (LOW confidence — verify the preview is real code)"))
    if base_addr is not None:
        print(f"  Base Address  : 0x{base_addr:X}")
    else:
        print(f"  Base Address  : <loader load address — not derivable from this blob>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
