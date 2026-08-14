#!/usr/bin/env python3
"""bootimage_fixture.py — craft a valid synthetic ZynqMP boot image for tests.

Builds an in-memory image with a boot header + IHT + a linked Partition Header
Table, with correct bootgen word-checksums, so both the offline parser
(tools/parse-bootimage.py) and the live JTAG walk (enumerate.tcl `::BH_ADDR`,
exercised via a mock that reads this image) can be tested with NO hardware.

Layout (file offsets, base 0):
  0x000  boot header
  0x100  Image Header Table (IHT)
  0x140  Partition Header 0  (PS, encrypted + authenticated  -> secure)
  0x180  Partition Header 1  (PL, authenticated, NOT encrypted -> auth-only)

Run directly to write a .bin:  tests/bootimage_fixture.py out.bin
"""
from __future__ import annotations

import struct
import sys

IHT_OFF = 0x100
PH0_OFF = 0x140
PH1_OFF = 0x180
IMG_LEN = 0x200


def _checksum(buf: bytearray, off: int, nwords: int) -> int:
    s = 0
    for i in range(nwords):
        s = (s + struct.unpack_from("<I", buf, off + 4 * i)[0]) & 0xFFFFFFFF
    return s ^ 0xFFFFFFFF


def build_image(eks: int = 0x00000000,
                fsbl_attr: int = (3 << 14),   # BH_RSA=3 => authenticated, unencrypted boot
                pl_encrypted: bool = False,
                pl_authenticated: bool = True) -> bytes:
    """Return a valid boot image. Defaults model an authenticated-but-unencrypted
    boot with a secure PS partition and an auth-only PL bitstream partition."""
    buf = bytearray(IMG_LEN)

    # ---- boot header ----
    struct.pack_into("<I", buf, 0x20, 0xAA995566)        # WIDTH_DETECTION
    struct.pack_into("<I", buf, 0x24, 0x584C4E58)        # "XLNX"
    struct.pack_into("<I", buf, 0x28, eks)               # encryptionKeySource
    struct.pack_into("<I", buf, 0x44, fsbl_attr)         # fsblAttributes
    struct.pack_into("<I", buf, 0x98, IHT_OFF)           # imageHeaderByteOffset
    struct.pack_into("<I", buf, 0x9C, PH0_OFF)           # partitionHeaderByteOffset
    struct.pack_into("<I", buf, 0x48, _checksum(buf, 0x20, 10))  # headerChecksum

    # ---- IHT ----
    struct.pack_into("<I", buf, IHT_OFF + 0x04, 2)               # partitionTotalCount
    struct.pack_into("<I", buf, IHT_OFF + 0x08, PH0_OFF // 4)    # firstPartitionHeaderWordOffset
    struct.pack_into("<I", buf, IHT_OFF + 0x10, 0x80)           # headerAuthCertificateWordOffset (!=0)
    struct.pack_into("<I", buf, IHT_OFF + 0x14, 0)              # bootDevice
    struct.pack_into("<I", buf, IHT_OFF + 0x3C, _checksum(buf, IHT_OFF, 15))

    # ---- PH0: PS, encrypted + authenticated (secure) ----
    attr0 = (1 << 4) | (1 << 7) | (1 << 15)   # DEST=PS, ENCRYPT=1, AC_FLAG=1
    struct.pack_into("<I", buf, PH0_OFF + 0x0C, PH1_OFF // 4)   # nextPartitionHeaderOffset
    struct.pack_into("<I", buf, PH0_OFF + 0x24, attr0)
    struct.pack_into("<I", buf, PH0_OFF + 0x34, 0x100)         # authCertificateOffset (!=0)
    struct.pack_into("<I", buf, PH0_OFF + 0x38, 0)            # partitionNumber
    struct.pack_into("<I", buf, PH0_OFF + 0x3C, _checksum(buf, PH0_OFF, 15))

    # ---- PH1: PL bitstream, auth-only (authenticated, NOT encrypted) ----
    attr1 = (2 << 4) | ((1 if pl_encrypted else 0) << 7) | ((1 if pl_authenticated else 0) << 15)
    struct.pack_into("<I", buf, PH1_OFF + 0x0C, 0)            # next = 0 (end of list)
    struct.pack_into("<I", buf, PH1_OFF + 0x24, attr1)
    struct.pack_into("<I", buf, PH1_OFF + 0x34, 0x200 if pl_authenticated else 0)
    struct.pack_into("<I", buf, PH1_OFF + 0x38, 1)            # partitionNumber
    struct.pack_into("<I", buf, PH1_OFF + 0x3C, _checksum(buf, PH1_OFF, 15))

    return bytes(buf)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "boot-fixture.bin"
    with open(out, "wb") as f:
        f.write(build_image())
    print(f"wrote {out}")
