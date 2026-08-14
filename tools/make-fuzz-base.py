#!/usr/bin/env python3
"""make-fuzz-base.py — build a MINIMAL valid ZynqMP boot image (FSBL-only) to use as the base for
BootROM boot-header fuzzing (tools/bootrom-fuzz-gen.py).

Why minimal: the fuzzer mutates the BH/IHT/PHT headers; the FSBL *payload* size is irrelevant to
the parser paths. A full PetaLinux BOOT.bin is ~8.9 MB → 64 mutants = ~548 MB and minutes-per-flash.
An FSBL-only image is ~150 KB → ~9 MB corpus and seconds-per-flash, making a real campaign feasible.

Extracts the FSBL from a PetaLinux BOOT.bin (partition0 = [PMUFW][FSBL]), wraps it to an ELF, and
runs mkbootimage to produce a one-partition boot image the BootROM accepts. Needs antmicro
mkbootimage (default /tmp/zynq-mkbootimage/mkbootimage; see docs/17 / reference_vxworks_build_toolchain).

Usage: python3 tools/make-fuzz-base.py [PetaLinux-BOOT.bin] [-o out.bin]
"""
import argparse, os, struct, subprocess, sys, tempfile

P0_DATA_OFF = 0xa00 * 4      # PetaLinux partition0 data start
PMU_LEN     = 0x1fae0        # PMUFW is first in partition0
FSBL_LEN    = 0x23f48        # FSBL is second
FSBL_LOAD   = 0xfffc0000


def wrap_elf(data, outp, load, entry):
    shstr = b"\x00.text\x00.shstrtab\x00"
    eh = 64; she = 64; toff = eh; soff = toff + len(data); shoff = (soff + len(shstr) + 7) & ~7
    ident = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\x00" * 8
    ehdr = struct.pack("<16sHHIQQQIHHHHHH", ident, 2, 183, 1, entry, 0, shoff, 0, eh, 0, 0, she, 3, 2)
    def sh(n, t, f, a, o, s, l, i, al, e): return struct.pack("<IIQQQQIIQQ", n, t, f, a, o, s, l, i, al, e)
    out = bytearray(ehdr); out += data; out += shstr; out += b"\x00" * (shoff - (soff + len(shstr)))
    out += (sh(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            + sh(1, 1, 0x6, load, toff, len(data), 0, 0, 4, 0)
            + sh(7, 3, 0, 0, soff, len(shstr), 0, 0, 1, 0))
    open(outp, "wb").write(out)


def main():
    ap = argparse.ArgumentParser(description="Build a minimal FSBL-only ZynqMP boot image for fuzzing.")
    ap.add_argument("peta", nargs="?", default="build-vxboot/sd-staging/BOOT.petalinux.bin",
                    help="a PetaLinux BOOT.bin to extract the FSBL from")
    ap.add_argument("-o", "--out", default="dumps/fuzz-base-min.bin")
    ap.add_argument("--mkbootimage", default="/tmp/zynq-mkbootimage/mkbootimage")
    args = ap.parse_args()

    if not os.path.exists(args.mkbootimage):
        sys.exit(f"mkbootimage not found at {args.mkbootimage} (see reference_vxworks_build_toolchain)")
    peta = open(args.peta, "rb").read()
    fsbl = peta[P0_DATA_OFF + PMU_LEN: P0_DATA_OFF + PMU_LEN + FSBL_LEN]
    if b"First Stage Boot Loader" not in fsbl:
        sys.exit("FSBL split sanity check failed — is this a PetaLinux [PMUFW][FSBL] image?")

    with tempfile.TemporaryDirectory() as w:
        wrap_elf(fsbl, os.path.join(w, "fsbl.elf"), FSBL_LOAD, FSBL_LOAD)
        bif = os.path.join(w, "min.bif")
        open(bif, "w").write("the_ROM_image:\n{\n\t[bootloader, destination_cpu=a53-0] %s/fsbl.elf\n}\n" % w)
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        subprocess.check_call([args.mkbootimage, "-u", bif, args.out], stdout=subprocess.DEVNULL)
    print(f"Wrote {args.out} ({os.path.getsize(args.out)} bytes). Validate: python3 tools/parse-bootimage.py {args.out}")
    print(f"Then: python3 tools/bootrom-fuzz-gen.py {args.out} -o fuzz-corpus/")


if __name__ == "__main__":
    main()
