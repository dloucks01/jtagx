#!/usr/bin/env python3
"""
jtagx.transport.openocd — the OpenOCD backend.

Drives generic/open adapters (FTDI/Digilent, J-Link, CMSIS-DAP) through an OpenOCD board cfg.
This is the path that already works on the ZCU102 (DAP open). Each verb becomes an
`openocd -f <cfg> -c "init; <tcl>; shutdown"` invocation.
"""
from __future__ import annotations
import os
from .base import Transport, Command, Capabilities


class OpenOCDTransport(Transport):
    backend = "openocd"

    def __init__(self, *, openocd=None, **kw):
        super().__init__(**kw)
        # $OPENOCD overrides the binary (point it at tools/mock-openocd.py to rehearse offline).
        self.openocd = openocd or os.environ.get("OPENOCD", "openocd")
        if not self.cfg:
            raise ValueError("OpenOCDTransport needs a board cfg (e.g. openocd/zcu102.cfg)")

    def _oc(self, tcl: str, desc: str, env: str = "") -> Command:
        inner = f'init; {tcl}; shutdown'
        shell = f'{env + " " if env else ""}{self.openocd} -f {self.cfg} -c "{inner}"'
        return Command(desc=desc, shell=shell, needs_vendor_sw=False)

    def capabilities(self) -> Capabilities:
        # On an OPEN DAP this reaches exploitation; on a locked board OpenOCD still scans (tier a/b).
        return Capabilities(scan=True, mem_read=True, mem_write=True, halt=True, run=True,
                            max_tier="e", needs_vendor_sw=False,
                            notes="Full mem-AP + run-control when the DAP is open; scan/bscan only when locked.")

    def scan(self) -> Command:
        return self._oc("scan_chain", "OpenOCD JTAG chain scan (IDCODEs)")

    def mem_read(self, addr: int, size: int, out: str) -> Command:
        # dump_image writes raw bytes; size in bytes.
        return self._oc(f"halt; dump_image {out} {hex(addr)} {size}; resume",
                        f"OpenOCD mem-read {size}B @ {hex(addr)} -> {out}")

    def mem_write(self, addr: int, data) -> Command:
        if isinstance(data, int):
            return self._oc(f"mww {hex(addr)} {hex(data)}",
                            f"OpenOCD write word {hex(data)} @ {hex(addr)}")
        # bytes -> write via a temp image file the caller supplies as a path in `data`
        return self._oc(f"load_image {data} {hex(addr)} bin",
                        f"OpenOCD load image {data} @ {hex(addr)}")

    def read_words(self, addr: int, count: int = 1) -> Command:
        return self._oc(f"mdw {hex(addr)} {count}", f"OpenOCD read {count} word(s) @ {hex(addr)}")

    def halt(self) -> Command:
        return self._oc("halt", "OpenOCD halt core")

    def run(self) -> Command:
        return self._oc("resume", "OpenOCD resume core")
