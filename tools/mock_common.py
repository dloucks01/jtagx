#!/usr/bin/env python3
"""
mock_common.py — a shared, high-fidelity silicon model for the mock backends (mock-openocd.py,
mock-xsdb.py). Instead of returning pure filler, the mocks answer register reads with the ACTUAL
values captured from the ZCU102 (newest reports/raw-*.json — 153 real registers), and memory dumps
carry a bit of recognizable structure (a VxWorks-ish banner + a fake bootline) so a rehearsal of
/dump → dump-triage / dram-secrets actually finds something.

Faithful where it matters (register-space reads match the real capture), deterministic filler
elsewhere. A REHEARSAL model — not real silicon.
"""
import glob
import json
import os
import struct

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# always-present anchors (in case there's no capture on disk)
_ANCHORS = {
    0xFFCA0040: 0x24738093,   # CSU IDCODE (XCZU9EG rev2)
    0xFFCA0038: 0x00000000,   # JTAG_SEC — open on this dev board
    0xFFCA003C: 0x000000FF,   # JTAG_DAP_CFG
}


def _newest_capture():
    caps = sorted(glob.glob(os.path.join(_ROOT, "reports", "raw-*.json")), key=os.path.getmtime)
    return caps[-1] if caps else None


def load_regs():
    """{addr_int -> value_int} from the newest capture, merged over the anchors."""
    regs = dict(_ANCHORS)
    p = _newest_capture()
    if p:
        try:
            d = json.load(open(p))
            for addr, r in d.get("registers", {}).items():
                if not isinstance(r, dict):
                    continue
                try:
                    regs[int(str(addr), 16)] = int(str(r.get("value", "0")), 16)
                except ValueError:
                    pass
        except Exception:
            pass
    return regs


def reg_word(regs, addr):
    """A 32-bit word for `addr`: the captured value if known, else deterministic filler."""
    if addr in regs:
        return regs[addr]
    return (addr ^ 0xA5A50000) & 0xFFFFFFFF


# per-region recognizable content, keyed by (offset-into-dump -> bytes). Each region makes a dump of
# that address space look plausible so /dump → dump-triage / dram-secrets rehearses realistically.
_DRAM_OVERLAY = {
    0x40:  b"VxWorks SMP 7.0 (ARMv8) : ZynqMP\x00",
    0x100: b"bootline: fsbl(0,0)host:vxWorks h=10.0.0.1 e=10.0.0.20 u=admin pw=jtagx123\x00",
    0x200: b"-----BEGIN OPENSSH PRIVATE KEY-----\x00",   # a decoy for dram-secrets rehearsal
}
_OCM_OVERLAY = {
    0x0:   bytes.fromhex("14000014" * 4),                # AArch64 branch-ish vector table start
    0x40:  b"Xilinx First Stage Boot Loader (FSBL)\x00",
    0x400: b"NOTICE:  BL31: v2.6  ATF running on ZynqMP\x00",   # ARM Trusted Firmware banner
}
_PMU_RAM_OVERLAY = {
    0x0:   b"PMU Firmware 2020.2  (MicroBlaze)\x00",
    0x80:  b"pmufw: power-management ready\x00",
}
_ROM_OVERLAY = {
    0x0:   b"ZynqMP BootROM\x00",                        # the ROM-dump marker
}
# SmartFusion2 (Cortex-M3) memory map: eNVM (embedded flash) + eSRAM
_ENVM_OVERLAY = {
    0x0:   bytes.fromhex("00040020" + "0d000000"),       # M3 vector table: initial SP + reset handler
    0x80:  b"SmartFusion2 MSS firmware  (Cortex-M3)\x00",
    0x120: b"cfg: user=root pass=m2s090 aeskey=0011223344556677\x00",   # decoy secret for extraction rehearsal
}
_ESRAM_OVERLAY = {
    0x0:   b"eSRAM runtime\x00",
}

# (lo, hi, name, overlay) — most-specific first; `mem_bytes` picks the region containing `addr`
_REGIONS = [
    (0xFFC00000, 0xFFC20000, "CSU_ROM", _ROM_OVERLAY),
    (0xFFD00000, 0xFFD20000, "PMU_ROM", _ROM_OVERLAY),
    (0xFFDC0000, 0xFFDE0000, "PMU_RAM", _PMU_RAM_OVERLAY),
    (0xFFFC0000, 0x100000000, "OCM",    _OCM_OVERLAY),
    (0x60000000, 0x60100000,  "eNVM",   _ENVM_OVERLAY),      # SmartFusion2 embedded flash
    (0x20000000, 0x20020000,  "eSRAM",  _ESRAM_OVERLAY),     # SmartFusion2 SRAM
    (0x00000000, 0x80000000,  "DRAM",   _DRAM_OVERLAY),
]


def region_of(addr):
    """The named region containing `addr` ('DRAM'/'OCM'/'PMU_ROM'/…), or 'MMIO'."""
    for lo, hi, name, _ in _REGIONS:
        if lo <= addr < hi:
            return name
    return "MMIO"


def mem_bytes(regs, addr, n):
    """`n` bytes at `addr`: register words in MMIO space, or a region image (DRAM/OCM/PMU/ROM) with a
    plausible banner/structure so a /dump rehearsal looks like the real address space."""
    buf = bytearray()
    a = addr
    while len(buf) < n:
        buf += struct.pack("<I", reg_word(regs, a))
        a += 4
    buf = bytearray(buf[:n])
    for lo, hi, _name, overlay in _REGIONS:
        if lo <= addr < hi:
            for off, s in overlay.items():
                if off + len(s) <= len(buf):
                    buf[off:off + len(s)] = s
            break
    return bytes(buf)
