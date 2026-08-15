#!/usr/bin/env python3
"""
mock-board.py — a PARAMETRIC high-fidelity `openocd` mock for EACH board in the profile registry, so
the multi-board flows (scan_chain / mdw / dump_image / halt) are rehearsable offline for any target.
Select the board with $JTAGX_MOCK_BOARD=<soc> and point $OPENOCD at this file.

Per-board model (BOARDS): a representative IDCODE, the correct per-FAMILY memory map (flash/SRAM bases
are the well-documented ones), and the lock flavour. A dump from the flash base carries a family-
appropriate firmware image — a Cortex-M vector table (initial SP + reset handler) where applicable,
a banner, and a decoy secret — so /dump → dump-triage / dram-secrets rehearses realistically per board.

$JTAGX_MOCK_LOCK=locked → the board's readout protection is engaged (RDP/APPROTECT/debug-lock/FlashLock):
memory access FAULTS (exit 1, no dump), which is exactly when you switch to the glitch/erase/vendor path.
Fabric-only boards (igloo2) have NO memory bus: scan_chain works, mdw/dump fault by design.
Dumps capped by $JTAGX_MOCK_MAXBYTES. REHEARSAL tool — real validation is the per-board bench.
"""
import os
import re
import struct
import sys

MAXBYTES = int(os.environ.get("JTAGX_MOCK_MAXBYTES", str(2 * 1024 * 1024)))
LOCKED = os.environ.get("JTAGX_MOCK_LOCK", "open") in ("locked", "debug-locked", "rdp", "approtect")
SOC = os.environ.get("JTAGX_MOCK_BOARD", "generic")

# soc -> model. arch: m=Cortex-M, a=Cortex-A, xtensa, riscv, fabric(no CPU). flash/sram = (base, size).
BOARDS = {
    "zynqmp":       {"idcode": "0x24738093", "arch": "a",      "flash": (0x00000000, 0x80000000), "sram": (0xFFFC0000, 0x40000),  "lock": "efuse"},
    "zynq7000":     {"idcode": "0x23731093", "arch": "a",      "flash": (0x00000000, 0x40000000), "sram": (0x00000000, 0x40000),  "lock": "efuse"},
    "imx6":         {"idcode": "0x0891c01d", "arch": "a",      "flash": (0x10000000, 0x40000000), "sram": (0x00900000, 0x40000),  "lock": "srk"},
    "am335x":       {"idcode": "0x0b94402f", "arch": "a",      "flash": (0x80000000, 0x40000000), "sram": (0x402f0400, 0x10000),  "lock": "efuse"},
    "sama5":        {"idcode": "0x05b3f03f", "arch": "a",      "flash": (0x20000000, 0x20000000), "sram": (0x00200000, 0x20000),  "lock": "secumod"},
    "bcm":          {"idcode": "0x4ba00477", "arch": "a",      "flash": (0x00000000, 0x40000000), "sram": (0x00000000, 0x10000),  "lock": "none"},
    "stm32f4":      {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x08000000, 0x100000),   "sram": (0x20000000, 0x30000),  "lock": "rdp"},
    "stm32f1":      {"idcode": "0x1ba01477", "arch": "m",      "flash": (0x08000000, 0x80000),    "sram": (0x20000000, 0x10000),  "lock": "rdp"},
    "stm32l4":      {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x08000000, 0x100000),   "sram": (0x20000000, 0x18000),  "lock": "rdp"},
    "nrf52":        {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x00000000, 0x80000),    "sram": (0x20000000, 0x10000),  "lock": "approtect"},
    "rp2040":       {"idcode": "0x0bc12477", "arch": "m",      "flash": (0x10000000, 0x200000),   "sram": (0x20000000, 0x42000),  "lock": "none"},
    "samd5x":       {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x00000000, 0x100000),   "sram": (0x20000000, 0x40000),  "lock": "nvmctrl"},
    "kinetis":      {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x00000000, 0x80000),    "sram": (0x1fff0000, 0x20000),  "lock": "fsec"},
    "smartfusion2": {"idcode": "0x2ba01477", "arch": "m",      "flash": (0x60000000, 0x80000),    "sram": (0x20000000, 0x20000),  "lock": "debug-lock"},
    "esp32":        {"idcode": "0x120034e5", "arch": "xtensa", "flash": (0x400c0000, 0x400000),   "sram": (0x3ffae000, 0x50000),  "lock": "flash-enc"},
    "riscv":        {"idcode": "0x20000913", "arch": "riscv",  "flash": (0x20000000, 0x20000000), "sram": (0x80000000, 0x20000),  "lock": "none"},
    "igloo2":       {"idcode": "0x0f8071cf", "arch": "fabric", "flash": None,                     "sram": None,                   "lock": "flashlock"},
    "generic":      {"idcode": "0x4ba00477", "arch": "m",      "flash": (0x00000000, 0x100000),   "sram": (0x20000000, 0x20000),  "lock": "none"},
}


def model():
    return BOARDS.get(SOC, BOARDS["generic"])


def _fw_image(m, addr, n):
    """Family-appropriate content at the flash base: (M-vector table) + banner + a decoy secret."""
    buf = bytearray()
    a = addr
    while len(buf) < n:
        buf += struct.pack("<I", (a ^ 0xA5A50000) & 0xFFFFFFFF)
        a += 4
    buf = bytearray(buf[:n])
    fb = m["flash"][0] if m["flash"] else None
    if fb is not None and addr == fb:
        over = {}
        if m["arch"] == "m":
            over[0x0] = struct.pack("<II", 0x20010000, fb | 0xC1)   # initial SP + Thumb reset handler
        over[0x40] = f"{SOC} firmware  (mock)\x00".encode()
        over[0x80] = b"cfg: user=admin pass=" + SOC.encode() + b"123 key=00112233445566778899aabbccddeeff\x00"
        for off, s in over.items():
            if off + len(s) <= len(buf):
                buf[off:off + len(s)] = s
    return bytes(buf)


def _reg_word(addr):
    return (addr ^ 0xA5A50000) & 0xFFFFFFFF


def fault(out, why):
    out.append(f"Error: memory access failed — {why}")
    out.append("Error: could not access the target")


def run_c(out, body):
    m = model()
    for raw in re.split(r";|\n", body):
        c = raw.strip()
        if not c:
            continue
        toks = c.split(); head = toks[0]
        if head in ("init", "shutdown", "reset"):
            continue
        if head == "scan_chain":
            out.append("   TapName            Enabled  IdCode     Expected   IrLen")
            out.append(f" 0 {SOC}.tap             Y   {m['idcode']} {m['idcode']}     " +
                       ("4" if m["arch"] in ("m",) else "5"))
            continue
        if m["arch"] == "fabric" and head in ("halt", "mdw", "dump_image", "resume", "reg"):
            fault(out, "fabric-only programming TAP — no memory bus (use FlashPro/Libero)")
            return False
        if LOCKED and head in ("halt", "mdw", "dump_image", "mww", "resume", "reg"):
            fault(out, f"readout protection engaged ({m['lock']}) — DAP/mem gated")
            return False
        if head == "halt":
            out.append(f"# [mock-board:{SOC}] halted ({m['arch']})")
        elif head == "resume":
            out.append(f"# [mock-board:{SOC}] resumed")
        elif head == "mdw":
            addr = int(toks[1], 16) if len(toks) > 1 else 0
            k = int(toks[2]) if len(toks) > 2 else 1
            img = _fw_image(m, addr, k * 4)
            for i in range(k):
                w = struct.unpack_from("<I", img, i * 4)[0]
                out.append(f"0x{addr + 4 * i:08x}: {w:08x}")
        elif head == "dump_image":
            path, addr, size = toks[1], int(toks[2], 16), int(toks[3], 0)
            n = min(size, MAXBYTES)
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            with open(path, "wb") as f:
                f.write(_fw_image(m, addr, n))
            note = f"(capped {MAXBYTES})" if n < size else ""
            out.append(f"# [mock-board:{SOC}] dumped {n} B @ {hex(addr)} to {path} {note}")
        else:
            out.append(f"# [mock-board:{SOC}] (ignored) {c}")
    return True


def main():
    argv = sys.argv[1:]; out = []; ok = True; i = 0
    while i < len(argv):
        if argv[i] == "-c" and i + 1 < len(argv):
            ok = run_c(out, argv[i + 1])
            if not ok:
                break
            i += 2
        else:
            i += 1
    print("\n".join(out))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
