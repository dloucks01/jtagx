#!/usr/bin/env python3
"""
dump-triage.py — first-look triage of an unknown firmware / flash / RAM dump.

"What IS this blob?" — the structural overview that complements the other offline analyzers:
  * dram-secrets.py   -> the SECRETS inside (keys/creds/certs)
  * ghidra-loadspec.py-> the ARCHITECTURE + load base (what ISA / where it maps)
  * dump-triage.py    -> the STRUCTURE: an entropy region-map (blank / code-data / compressed-encrypted)
                         + embedded-artifact signatures (filesystems, boot images, compressed blobs, certs)

Use it the moment you have a dump (docs/23 Phase 3) to decide what you're even looking at: is it
plaintext code (disassemble it), an encrypted blob (the secure-boot path took over), a packed
filesystem (carve it), or mostly blank (you over-read). Offline, read-only, stdlib only.

Usage:
    python3 tools/dump-triage.py dumps/boot.bin
    python3 tools/dump-triage.py dumps/os-live.bin --block 0x1000 -o reports/triage.md
"""
import argparse, hashlib, math, os, sys
from collections import Counter


def shannon(b):
    if not b:
        return 0.0
    n = len(b)
    return -sum((c / n) * math.log2(c / n) for c in Counter(b).values())


# Embedded-artifact magic signatures: (name, magic-bytes, kind, heuristic?). Heuristic ones are short/
# common and hard-capped + flagged, so they inform without drowning the report in false hits.
SIGS = [
    ("gzip",            b"\x1f\x8b\x08",          "compressed",  False),
    ("xz",              b"\xfd7zXZ\x00",          "compressed",  False),
    ("bzip2",           b"BZh",                   "compressed",  False),
    ("lz4",             b"\x04\x22\x4d\x18",      "compressed",  False),
    ("zstd",            b"\x28\xb5\x2f\xfd",      "compressed",  False),
    ("zip/jar/apk",     b"PK\x03\x04",            "archive",     False),
    ("ELF",             b"\x7fELF",               "executable",  False),
    ("U-Boot uImage",   b"\x27\x05\x19\x56",      "boot-image",  False),
    ("FDT / DTB",       b"\xd0\x0d\xfe\xed",      "device-tree", False),
    ("SquashFS (le)",   b"hsqs",                  "filesystem",  False),
    ("SquashFS (be)",   b"sqsh",                  "filesystem",  False),
    ("JFFS2",           b"\x85\x19",              "filesystem",  True),
    ("UBI",             b"UBI#",                  "filesystem",  False),
    ("UBIFS",           b"\x31\x18\x10\x06",      "filesystem",  False),
    ("cramfs",          b"\x45\x3d\xcd\x28",      "filesystem",  False),
    ("ext2/3/4 (sb)",   b"\x53\xef",              "filesystem",  True),
    ("Android boot",    b"ANDROID!",              "boot-image",  False),
    ("Xilinx boot",     b"XLNX",                  "boot-image",  False),
    ("Xilinx sync",     b"\x66\x55\x99\xaa",      "fpga-bitstream", True),
    ("PEM key/cert",    b"-----BEGIN ",           "crypto",      False),
    ("X.509 DER (seq)", b"\x30\x82",              "crypto",      True),
    ("Linux banner",    b"Linux version ",        "os-string",   False),
    ("VxWorks",         b"VxWorks",               "os-string",   False),
    ("U-Boot banner",   b"U-Boot ",               "bootloader-string", False),
    ("FreeRTOS",        b"FreeRTOS",              "rtos-string", False),
]
HEUR_CAP = 8       # max occurrences to report for a heuristic sig
STRONG_CAP = 64    # max for a strong sig


def find_all(data, magic, cap):
    offs, start = [], 0
    while len(offs) < cap:
        i = data.find(magic, start)
        if i < 0:
            break
        offs.append(i)
        start = i + 1
    return offs


def classify(ent, distinct, blank_byte):
    if blank_byte is not None:
        return "blank/padding"
    if ent < 1.0:
        return "near-constant"
    if ent >= 7.2:
        return "encrypted/compressed"
    if ent >= 6.0:
        return "packed/mixed"
    return "code/data"


def block_scan(data, bs):
    """Per-block entropy + class; returns list of (offset, len, ent, cls)."""
    out = []
    for off in range(0, len(data), bs):
        blk = data[off:off + bs]
        cnt = Counter(blk)
        blank = None
        if len(cnt) == 1:
            blank = next(iter(cnt))                       # all one byte (0x00 / 0xFF padding)
        elif len(cnt) <= 2 and (blk.count(0x00) + blk.count(0xFF)) / len(blk) > 0.98:
            blank = 0xFF if blk.count(0xFF) >= blk.count(0x00) else 0x00
        ent = shannon(blk)
        out.append((off, len(blk), ent, classify(ent, len(cnt), blank)))
    return out


def coalesce(blocks):
    """Merge adjacent same-class blocks into regions: (start, end, mean_ent, cls)."""
    regions = []
    for off, ln, ent, cls in blocks:
        if regions and regions[-1][3] == cls:
            s, e, ents, c = regions[-1]
            regions[-1] = (s, off + ln, ents + [ent], c)
        else:
            regions.append((off, off + ln, [ent], cls))
    return [(s, e, sum(es) / len(es), c) for s, e, es, c in regions]


SPARK = " .:-=+*#%@"   # low -> high entropy


def sparkline(blocks, width=64):
    if not blocks:
        return ""
    step = max(1, len(blocks) // width)
    out = []
    for i in range(0, len(blocks), step):
        chunk = blocks[i:i + step]
        ent = sum(b[2] for b in chunk) / len(chunk)
        out.append(SPARK[min(len(SPARK) - 1, int(ent / 8 * len(SPARK)))])
    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description="Structural triage of an unknown firmware/flash/RAM dump.")
    ap.add_argument("image")
    ap.add_argument("--block", default="0x1000", help="entropy block size (default 0x1000 = 4 KB)")
    ap.add_argument("--base", default="0x0", help="base address for displayed offsets (cosmetic)")
    ap.add_argument("-o", "--out", help="write the report (markdown) to this path too")
    a = ap.parse_args()
    try:
        data = open(a.image, "rb").read()
    except OSError as e:
        sys.exit(f"cannot read {a.image}: {e}")
    if not data:
        sys.exit("empty file")
    bs = int(a.block, 0)
    base = int(a.base, 0)

    blocks = block_scan(data, bs)
    regions = coalesce(blocks)
    overall_ent = shannon(data[:1 << 20] if len(data) > (1 << 20) else data)
    printable = sum(1 for x in data[:1 << 20] if 0x20 <= x < 0x7f) / min(len(data), 1 << 20)

    L = []
    L.append(f"# dump-triage: {a.image}")
    L.append("")
    L.append(f"- size: {len(data):,} bytes ({len(data)/1024:.1f} KB)")
    L.append(f"- md5:  {hashlib.md5(data).hexdigest()}")
    L.append(f"- overall entropy: {overall_ent:.2f} / 8.0   printable: {printable*100:.0f}%")
    L.append(f"- block size: {bs} ({len(blocks)} blocks)")
    L.append("")
    L.append("## entropy sparkline (low ` ` .:-=+*#% @ high)")
    L.append("```")
    L.append(sparkline(blocks))
    L.append("```")

    # region map
    L.append("")
    L.append("## region map")
    L.append("```")
    L.append(f"{'start':>12} {'end':>12} {'size':>10}  ent   class")
    for s, e, ent, cls in regions:
        L.append(f"{base+s:>#12x} {base+e:>#12x} {e-s:>10,}  {ent:>4.1f}  {cls}")
    L.append("```")

    # signatures
    L.append("")
    L.append("## embedded signatures")
    hits = []
    for name, magic, kind, heur in SIGS:
        cap = HEUR_CAP if heur else STRONG_CAP
        offs = find_all(data, magic, cap)
        # PEM/banner strings can appear mid-word; that's fine. Skip a heuristic hit only at offset 0
        # unless it's a real container.
        if offs:
            hits.append((name, kind, heur, offs))
    if not hits:
        L.append("(none of the known magics found)")
    else:
        for name, kind, heur, offs in hits:
            tag = " (heuristic)" if heur else ""
            shown = ", ".join(f"0x{base+o:x}" for o in offs[:6])
            more = f" … (+{len(offs)-6} more)" if len(offs) > 6 else ""
            L.append(f"- **{name}** [{kind}]{tag}: {len(offs)}x @ {shown}{more}")

    # verdict hints
    L.append("")
    L.append("## first-look verdict")
    enc = sum(e - s for s, e, _, c in regions if c == "encrypted/compressed")
    blank = sum(e - s for s, e, _, c in regions if c == "blank/padding")
    code = sum(e - s for s, e, _, c in regions if c == "code/data")
    frac = lambda x: f"{x/len(data)*100:.0f}%"
    L.append(f"- encrypted/compressed: {frac(enc)}   code/data: {frac(code)}   blank: {frac(blank)}")
    if enc / len(data) > 0.7:
        L.append("- → mostly HIGH-ENTROPY: likely encrypted or compressed (secure-boot image, packed FW, or a "
                 "filesystem). Look for a compression/FS signature above; if none, suspect encryption.")
    elif code / len(data) > 0.4:
        L.append("- → substantial LOW-ENTROPY code/data: disassemble it (run ghidra-loadspec.py for the ISA+base).")
    if blank / len(data) > 0.5:
        L.append("- → mostly BLANK: you likely over-read past the used region, or the part is largely unprogrammed.")
    strong = [h for h in hits if not h[2]]   # non-heuristic signature hits
    if strong:
        kinds = sorted({k for _, k, _, _ in strong})
        L.append(f"- → strong container signatures present ({', '.join(kinds)}) — carve/extract those first.")
    L.append("")
    L.append("Next: dram-secrets.py (secrets) · ghidra-loadspec.py (ISA+base) · binwalk -e to carve any filesystem.")

    report = "\n".join(L)
    print(report)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(report + "\n")
        print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
