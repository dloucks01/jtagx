#!/usr/bin/env python3
"""bootrom-fuzz-gen.py — generate a CURATED corpus of malformed ZynqMP boot images to
black-box fuzz the CSU BootROM's boot-image parser (Boot Header -> Image Header Table ->
Partition Header Table).

WHY (the checkm8 model — see docs/20): the CSU BootROM runs on the CSU security processor and
parses these structures off the boot device BEFORE/around secure-boot enforcement. The CSU
processor is the ONE agent that can read the CSU ROM. A memory-corruption bug in this parser
(a length/offset/count/pointer field that drives a copy or pointer without bounds-checking)
could yield a copy/exec primitive in the CSU context -> coerce it into copying the 128 KB ROM to
OCM (0xFFFC0000, which IS JTAG-readable) -> dump it. Non-destructive, no glitching.

Field offsets are authoritative per bootgen zynqmp/include/{bootheader,imageheadertable,
partitionheadertable}-zynqmp.h. The bootgen word-checksum (sum of N LE words ^ 0xFFFFFFFF) for
the mutated structure is recomputed so the mutated field is actually CONSUMED by the parser —
unless the mutation is tagged cksum-test (which leaves the checksum broken to probe whether the
BootROM even enforces it; a broken-checksum image that still parses is itself a finding).

Manual loop (flashing is hands-on): for each image -> flash to SD/QSPI -> power-cycle ->
capture the BootROM reaction with openocd/bootrom-fuzz-observe.tcl -> triage with
bootrom-fuzz-triage.py. Start with 0000-baseline.bin to record the normal-boot fingerprint.

Usage: python3 tools/bootrom-fuzz-gen.py BOOT.bin -o fuzz-corpus/
"""
import argparse, json, os, struct, sys

# --- bootgen structure offsets (authoritative) -----------------------------------------
BH_FSBL_EXEC      = 0x2C   # fsblExecAddress      (pointer: where FSBL runs)
BH_SOURCE_OFF     = 0x30   # sourceOffset         (offset of FSBL data in image)
BH_PMUFW_LEN      = 0x34   # pmuFwLength
BH_TOT_PMUFW_LEN  = 0x38   # totalPmuFwLength
BH_FSBL_LEN       = 0x3C   # fsblLength           (drives the FSBL copy to OCM)
BH_TOT_FSBL_LEN   = 0x40   # totalFsblLength
BH_CKSUM          = 0x48   # = wordsum(0x20,10) ^ 0xFFFFFFFF
BH_IHT_OFF        = 0x98   # imageHeaderByteOffset (byte)
BH_PHT_OFF        = 0x9C   # partitionHeaderByteOffset (byte)
BH_CKSUM_START    = 0x20
BH_CKSUM_NWORDS   = 10

IHT_PART_COUNT    = 0x04   # partitionTotalCount   (loop bound)
IHT_FIRST_PH      = 0x08   # firstPartitionHeaderWordOffset
IHT_HDR_AC_OFF    = 0x10   # headerAuthCertificateWordOffset
IHT_CKSUM         = 0x3C
IHT_CKSUM_NWORDS  = 15

PH_ENC_LEN        = 0x00   # encryptedPartitionLength
PH_UNENC_LEN      = 0x04   # unencryptedPartitionLength
PH_TOTAL_LEN      = 0x08   # totalPartitionLength
PH_NEXT_OFF       = 0x0C   # nextPartitionHeaderOffset (word)
PH_EXEC_ADDR      = 0x10   # destinationExecAddress (64-bit)
PH_LOAD_ADDR      = 0x18   # destinationLoadAddress (64-bit: where partition data is copied)
PH_DATA_SEC_CNT   = 0x28   # dataSectionCount
PH_AC_OFF         = 0x34   # authCertificateOffset
PH_CKSUM          = 0x3C
PH_CKSUM_NWORDS   = 15


def word_checksum(buf, off, nwords):
    s = 0
    for i in range(nwords):
        s = (s + struct.unpack_from("<I", buf, off + i * 4)[0]) & 0xFFFFFFFF
    return s ^ 0xFFFFFFFF


def u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


# Value sets keyed by field role.
LEN_VALUES  = [("max", 0xFFFFFFFF), ("hi", 0x80000000), ("big256m", 0x10000000), ("zero", 0)]
OFF_VALUES  = [("max", 0xFFFFFFFF), ("zero", 0), ("backref", 0xFFFFFFF0)]
CNT_VALUES  = [("max", 0xFFFFFFFF), ("big", 0x00010000), ("zero", 0)]
# Addresses aimed at where a copy could clobber CSU/OCM state or land the ROM somewhere readable.
ADDR_VALUES = [("ocm", 0xFFFC0000), ("ocm_hi", 0xFFFE0000), ("csu_regs", 0xFFCA0000),
               ("null", 0x00000000), ("wrap", 0xFFFFFFF0)]


def build_catalog(buf):
    iht = u32(buf, BH_IHT_OFF)
    pht = u32(buf, BH_PHT_OFF)
    cat = []
    def add(region, field, abs_off, width, values, ckoff, cknw, hyp):
        cat.append(dict(region=region, field=field, off=abs_off, width=width,
                        values=values, ck_off=ckoff, ck_nw=cknw, hyp=hyp))
    # --- Boot Header (checksum at 0x48 over 10 words from 0x20) ---
    add("BH", "fsblLength",      BH_FSBL_LEN,     4, LEN_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "oversized FSBL length -> overflow the OCM copy at 0xFFFC0000")
    add("BH", "totalFsblLength", BH_TOT_FSBL_LEN, 4, LEN_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "total vs fsbl length mismatch -> copy-size confusion")
    add("BH", "fsblExecAddress", BH_FSBL_EXEC,    4, ADDR_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "redirect post-load execution pointer")
    add("BH", "sourceOffset",    BH_SOURCE_OFF,   4, OFF_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "FSBL data source offset out of range -> OOB read of the image")
    add("BH", "totalPmuFwLength",BH_TOT_PMUFW_LEN,4, LEN_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "oversized PMUFW length -> overflow the PMU-RAM/OCM copy")
    add("BH", "imageHeaderByteOffset", BH_IHT_OFF, 4, OFF_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "IHT pointer out of range -> parser dereferences attacker offset")
    add("BH", "partitionHeaderByteOffset", BH_PHT_OFF, 4, OFF_VALUES, BH_CKSUM, BH_CKSUM_NWORDS,
        "PHT pointer out of range")
    # --- Image Header Table (checksum at iht+0x3C over 15 words) ---
    if 0 < iht < len(buf) - 0x40:
        add("IHT", "partitionTotalCount", iht + IHT_PART_COUNT, 4, CNT_VALUES,
            iht + IHT_CKSUM, IHT_CKSUM_NWORDS, "huge partition count -> over-iterate the PH loop")
        add("IHT", "firstPartitionHeaderWordOffset", iht + IHT_FIRST_PH, 4, OFF_VALUES,
            iht + IHT_CKSUM, IHT_CKSUM_NWORDS, "first-PH offset out of range")
        add("IHT", "headerAuthCertificateWordOffset", iht + IHT_HDR_AC_OFF, 4, OFF_VALUES,
            iht + IHT_CKSUM, IHT_CKSUM_NWORDS, "header AC offset out of range")
    # --- Partition Header 0 (checksum at pht+0x3C over 15 words) — richest target ---
    if 0 < pht < len(buf) - 0x40:
        add("PHT", "encryptedPartitionLength",   pht + PH_ENC_LEN,   4, LEN_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "oversized encrypted length")
        add("PHT", "unencryptedPartitionLength", pht + PH_UNENC_LEN, 4, LEN_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "oversized unencrypted length")
        add("PHT", "totalPartitionLength",       pht + PH_TOTAL_LEN, 4, LEN_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "total vs enc/unenc length mismatch -> copy confusion")
        add("PHT", "destinationLoadAddress",     pht + PH_LOAD_ADDR, 4, ADDR_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "PRIME: load partition data over OCM/CSU/regs")
        add("PHT", "destinationExecAddress",     pht + PH_EXEC_ADDR, 4, ADDR_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "redirect partition exec pointer")
        add("PHT", "nextPartitionHeaderOffset",  pht + PH_NEXT_OFF,  4, OFF_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "PH-chain walk into attacker offset")
        add("PHT", "dataSectionCount",           pht + PH_DATA_SEC_CNT, 4, CNT_VALUES,
            pht + PH_CKSUM, PH_CKSUM_NWORDS, "huge section count -> over-iterate")
    return cat, iht, pht


def main():
    ap = argparse.ArgumentParser(description="Generate a malformed-boot-image corpus for BootROM parser fuzzing.")
    ap.add_argument("base", help="a VALID base BOOT.bin (e.g. dumps/sd-extract/BOOT.BIN)")
    ap.add_argument("-o", "--outdir", default="fuzz-corpus", help="output directory")
    ap.add_argument("--cksum-test", action="store_true",
                    help="ALSO emit broken-checksum variants (probe whether the BootROM enforces the checksum)")
    args = ap.parse_args()

    base = bytearray(open(args.base, "rb").read())
    if u32(base, 0x24) != 0x584C4E58:   # identification word (matches parse-bootimage HEADER_ID_XLNX)
        sys.exit(f"base image identification word @0x24 is 0x{u32(base,0x24):08X}, not 0x584C4E58 — not a ZynqMP boot image?")
    os.makedirs(args.outdir, exist_ok=True)
    catalog, iht, pht = build_catalog(base)

    manifest = []
    # 0000 = pristine baseline (record the normal-boot fingerprint against this)
    open(os.path.join(args.outdir, "0000-baseline.bin"), "wb").write(base)
    manifest.append(dict(id=0, name="0000-baseline.bin", region="-", field="(pristine)",
                         off=0, orig=None, new=None, cksum_fixed=True, hyp="baseline / normal-boot reference"))

    idx = 1
    def emit(region, field, off, orig, newval, fixck, ck_off, ck_nw, hyp, tag):
        nonlocal idx
        img = bytearray(base)
        struct.pack_into("<I", img, off, newval & 0xFFFFFFFF)
        if fixck:
            struct.pack_into("<I", img, ck_off, word_checksum(img, ck_off - (ck_nw * 4), ck_nw))
        name = f"{idx:04d}-{region}-{field}-{tag}{'-badck' if not fixck else ''}.bin"
        open(os.path.join(args.outdir, name), "wb").write(img)
        manifest.append(dict(id=idx, name=name, region=region, field=field, off=off,
                             orig=f"0x{orig:08X}", new=f"0x{newval & 0xFFFFFFFF:08X}",
                             cksum_fixed=fixck, hyp=hyp))
        idx += 1

    for m in catalog:
        orig = u32(base, m["off"])
        for tag, val in m["values"]:
            emit(m["region"], m["field"], m["off"], orig, val, True, m["ck_off"], m["ck_nw"], m["hyp"], tag)
            if args.cksum_test:
                emit(m["region"], m["field"], m["off"], orig, val, False, m["ck_off"], m["ck_nw"],
                     m["hyp"] + " [checksum left BROKEN — tests enforcement]", tag)

    json.dump(manifest, open(os.path.join(args.outdir, "manifest.json"), "w"), indent=2)
    print(f"Base: {args.base}  (IHT@0x{iht:X}, PHT@0x{pht:X})")
    print(f"Wrote {len(manifest)} images to {args.outdir}/ (incl. 0000-baseline.bin) + manifest.json")
    print("Next: flash each -> power-cycle -> openocd ... bootrom-fuzz-observe.tcl -> bootrom-fuzz-triage.py")


if __name__ == "__main__":
    main()
