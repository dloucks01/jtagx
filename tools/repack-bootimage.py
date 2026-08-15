#!/usr/bin/env python3
"""
repack-bootimage.py — patch a ZynqMP boot image and rebuild it VALID for reflash (the persistence path).

Closes the loop: dump BOOT.bin (qspi-jtag dmadump) -> parse-bootimage to find a partition -> patch its
code here -> reflash (qspi-jtag write, or write the SD card). Applies a same-size byte patch (or replaces a
partition's data), recomputes the bootgen header word-checksums (BH / IHT / every PHT) so the image stays
self-consistent, and re-validates. Reuses parse-bootimage.py's offsets + checksum (single source of truth).

WHAT IT CANNOT DEFEAT (it tells you):
  * An AUTHENTICATED partition (RSA, PH.authCertificateOffset != 0) — you can't re-sign without the private
    key. The patched image fails secure boot. That's the auth doing its job (a finding, not a tool gap).
  * An ENCRYPTED partition (AES) — you can't re-encrypt without the key; the patch lands in ciphertext.
  * A partition with a DATA-integrity checksum (PH attr bits 12-14 != none) — a code patch breaks it; this
    tool recomputes the bootgen HEADER checksums but NOT a partition data hash (warns instead).
So this is the persistence path on a NON-secure / unprotected boot image (the all-open dev baseline, or a
board whose secure boot isn't provisioned). On a hardened board it tells you exactly what stops you.

Usage:
    python3 tools/repack-bootimage.py BOOT.bin --patch 0x1A20=1f2003d5 -o BOOT-patched.bin   # NOP @0x1A20
    python3 tools/repack-bootimage.py BOOT.bin --patch-file 0x80000 payload.bin -o out.bin   # same-size blob
    python3 tools/repack-bootimage.py BOOT.bin --replace-partition 3 newkernel.bin -o out.bin
    python3 tools/repack-bootimage.py BOOT.bin --inspect          # list partitions + what's patchable
"""
import argparse, importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("parse_bootimage", os.path.join(HERE, "parse-bootimage.py"))
pb = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(pb)   # reuse its constants + checksum


def _w32le(buf, off, val):
    buf[off:off + 4] = (val & 0xFFFFFFFF).to_bytes(4, "little")


def partitions(data):
    """Walk the PHT -> list of dicts {idx, ph_off, data_off, data_len, total_len, encrypted, authed, cksum_type}."""
    iht = pb._u32(data, pb.BH_IHT_OFF)
    pht = pb._u32(data, pb.BH_PHT_OFF)
    if iht is None or pht is None:
        return []
    count = pb._u32(data, iht + pb.IHT_PART_COUNT) or 0
    out = []
    for i in range(min(count, 64)):
        ph = pht + i * pb.PH_SIZE
        attr = pb._u32(data, ph + pb.PH_ATTR) or 0
        ac = pb._u32(data, ph + pb.PH_AC_OFF) or 0
        unenc = (pb._u32(data, ph + pb.PH_UNENC_LEN) or 0) * 4
        total = (pb._u32(data, ph + pb.PH_TOTAL_LEN) or 0) * 4
        out.append({
            "idx": i, "ph_off": ph,
            "data_off": (pb._u32(data, ph + pb.PH_DATA_WORDOFF) or 0) * 4,
            "data_len": unenc or total, "total_len": total,
            "encrypted": bool((attr >> pb.PH_ENCRYPT_SHIFT) & pb.PH_ENCRYPT_MASK),
            "authed": ac != 0 or bool((attr >> pb.PH_AC_FLAG_SHIFT) & pb.PH_AC_FLAG_MASK),
            "cksum_type": (attr >> pb.PH_CHECKSUM_SHIFT) & pb.PH_CHECKSUM_MASK,
        })
    return out


def which_partition(parts, off, length):
    for p in parts:
        if p["data_off"] <= off and (off + length) <= (p["data_off"] + max(p["total_len"], p["data_len"], 4)):
            return p
    return None


def warn_protections(p, where):
    if p is None:
        print(f"  note: patch at {where} is outside any partition's data (header/padding) — recomputed checksums cover it.")
        return
    msgs = []
    if p["authed"]:    msgs.append("AUTHENTICATED (RSA) — patched image WILL FAIL secure boot (can't re-sign)")
    if p["encrypted"]: msgs.append("ENCRYPTED (AES) — patch lands in ciphertext (can't re-encrypt)")
    if p["cksum_type"] != 0: msgs.append(f"has a partition DATA checksum (type {p['cksum_type']}) — recompute not automated")
    if msgs:
        print(f"  *** WARNING: partition {p['idx']} is " + "; ".join(msgs))
    else:
        print(f"  ok: partition {p['idx']} is plain (no auth/encrypt/data-checksum) — the patch is reflash-valid.")


def recompute_headers(buf):
    """Recompute BH + IHT + every PHT word-checksum so a header-region patch stays valid (no-op if untouched)."""
    _w32le(buf, pb.BH_CHECKSUM, pb._word_checksum(bytes(buf), pb.BH_WIDTH_DET, 10))
    iht = pb._u32(bytes(buf), pb.BH_IHT_OFF)
    if iht is not None:
        _w32le(buf, iht + pb.IHT_CHECKSUM, pb._word_checksum(bytes(buf), iht, 15))
    for p in partitions(bytes(buf)):
        _w32le(buf, p["ph_off"] + pb.PH_CHECKSUM, pb._word_checksum(bytes(buf), p["ph_off"], 15))


def main():
    ap = argparse.ArgumentParser(description="Patch + repack a ZynqMP boot image for reflash.")
    ap.add_argument("image")
    ap.add_argument("--patch", action="append", default=[], metavar="OFF=HEX", help="write HEX bytes at OFF (same length)")
    ap.add_argument("--patch-file", nargs=2, action="append", default=[], metavar=("OFF", "FILE"), help="write FILE's bytes at OFF")
    ap.add_argument("--replace-partition", nargs=2, action="append", default=[], metavar=("N", "FILE"), help="replace partition N data with FILE (same size)")
    ap.add_argument("--inspect", action="store_true", help="list partitions + patchability, then exit")
    ap.add_argument("-o", "--out", help="output image path")
    a = ap.parse_args()
    try:
        buf = bytearray(open(a.image, "rb").read())
    except OSError as e:
        sys.exit(f"cannot read {a.image}: {e}")
    _wd = pb._u32(buf, pb.BH_WIDTH_DET)
    if _wd != 0xAA995566:
        got = f"0x{_wd:08x}" if _wd is not None else "(truncated — buffer too short)"
        sys.exit(f"not a Zynq(MP) boot image — width-detect @0x20 is not 0xAA995566 (got {got}). "
                 "repack only handles bootgen images.")
    parts = partitions(buf)

    print(f"# repack-bootimage: {a.image}  ({len(buf):,} bytes, {len(parts)} partitions)")
    for p in parts:
        flags = []
        if p["authed"]: flags.append("AUTH")
        if p["encrypted"]: flags.append("ENC")
        if p["cksum_type"]: flags.append(f"cksum{p['cksum_type']}")
        print(f"  part {p['idx']}: data @0x{p['data_off']:x} len 0x{p['data_len']:x} (total 0x{p['total_len']:x})  "
              f"{'/'.join(flags) if flags else 'plain (patchable)'}")
    if a.inspect:
        return

    edits = []  # (off, bytes)
    for spec in a.patch:
        off_s, hexs = spec.split("=", 1)
        edits.append((int(off_s, 0), bytes.fromhex(hexs)))
    for off_s, fn in a.patch_file:
        edits.append((int(off_s, 0), open(fn, "rb").read()))
    for n_s, fn in a.replace_partition:
        p = parts[int(n_s)]
        blob = open(fn, "rb").read()
        if len(blob) > max(p["total_len"], p["data_len"]):
            sys.exit(f"replacement ({len(blob)}B) is larger than partition {n_s} data region "
                     f"(0x{max(p['total_len'], p['data_len']):x}B) — would relayout the image (not supported).")
        edits.append((p["data_off"], blob))

    if not edits:
        sys.exit("nothing to do — give --patch / --patch-file / --replace-partition (or --inspect).")
    if not a.out:
        sys.exit("specify -o OUTPUT")

    print("\napplying patches:")
    for off, blob in edits:
        if off + len(blob) > len(buf):
            sys.exit(f"patch at 0x{off:x} (+{len(blob)}B) runs past EOF")
        warn_protections(which_partition(parts, off, len(blob)), f"0x{off:x}")
        buf[off:off + len(blob)] = blob
        print(f"  wrote {len(blob)} bytes @ 0x{off:x}")

    recompute_headers(buf)
    # self-check: the stored header checksums now equal a fresh recompute (they must, by construction)
    bh_ok = pb._u32(buf, pb.BH_CHECKSUM) == pb._word_checksum(bytes(buf), pb.BH_WIDTH_DET, 10)
    iht = pb._u32(buf, pb.BH_IHT_OFF)
    iht_ok = iht is None or pb._u32(buf, iht + pb.IHT_CHECKSUM) == pb._word_checksum(bytes(buf), iht, 15)
    pht_ok = all(pb._u32(buf, p["ph_off"] + pb.PH_CHECKSUM) == pb._word_checksum(bytes(buf), p["ph_off"], 15)
                 for p in partitions(bytes(buf)))
    print(f"recomputed BH/IHT/PHT header checksums (consistent: BH={bh_ok} IHT={iht_ok} PHT={pht_ok}).")
    open(a.out, "wb").write(buf)
    print(f"\nwrote {a.out} ({len(buf):,} bytes).")
    print("Reflash: qspi-jtag.tcl QSPI_OP=write (boot flash), or write it to the SD card's BOOT partition.")


if __name__ == "__main__":
    main()
