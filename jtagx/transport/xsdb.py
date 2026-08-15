#!/usr/bin/env python3
"""
jtagx.transport.xsdb — the AMD hw_server / xsdb backend.

This is the backend that unblocks the adapter which FAILED the real engagement: the AMD
SmartLynq2 (and Platform Cable USB II) have no OpenOCD driver, but hw_server speaks to them
natively and xsdb (Xilinx System Debugger, a Tcl shell) drives the ZynqMP DAP through it.
Validated on this box: xsdb reads ZynqMP registers matching OpenOCD (BOOT_MODE_USER=0x2,
CRL_APB=0x01010800).

hw_server model: `hw_server` runs (default TCP 3121) and owns the USB/Ethernet adapter; xsdb
`connect`s to it, `targets` selects a core, then `mrd`/`mwr`/`stop`/`con` are the primitives.
Each verb here emits `xsdb -eval "<tcl>"`. The vendor tools ship in Vitis
(~/Downloads/2026.1/Vitis/bin/xsdb, .../hw_server) — needs_vendor_sw is True.

Alternative (kept as a note): bridge hw_server's XVC server to OpenOCD's `xvc` driver so the
existing OpenOCD Tcl keeps working over a SmartLynq2 — see xvc_bridge_hint().
"""
from __future__ import annotations
import os
from .base import Transport, Command, Capabilities
from . import targets as T


class XsdbTransport(Transport):
    backend = "hw_server"

    def __init__(self, *, xsdb=None, hw_server_port=3121, **kw):
        super().__init__(**kw)
        # $JTAGX_XSDB overrides the xsdb binary (point it at tools/mock-xsdb.py to rehearse offline,
        # the same way $OPENOCD is overridable) — falls back to "xsdb" on PATH.
        self.xsdb = xsdb or os.environ.get("JTAGX_XSDB", "xsdb")
        self.port = self.port or hw_server_port
        # target selector: a friendly role ("a53-0"/"rpu"/"pmu"), an xsdb target id, or a raw filter.
        # default to APU core 0 (the usual DRAM/OS view on ZynqMP).
        self._tsel = self.target or self.extra.get("target_filter") or "a53-0"

    def select(self, sel):
        """Bind this transport to a debug target (role name / id / filter). Chainable."""
        self._tsel = sel
        return self

    # ---- helpers ----------------------------------------------------------------
    def _connect(self) -> str:
        # connect to a (possibly remote) hw_server that owns the SmartLynq2
        return f"connect -host {self.host} -port {self.port}"

    def _select(self) -> str:
        # resolve a friendly role / id / raw filter into the xsdb `targets ...` command
        return T.resolve_selector(self._tsel)

    def _xsdb(self, body: str, desc: str, select=True) -> Command:
        parts = [self._connect()]
        if select:
            parts.append(self._select())
        parts.append(body)
        tcl = "; ".join(parts)
        shell = f'{self.xsdb} -eval {_dq(tcl)}'
        return Command(desc=desc, shell=shell, needs_vendor_sw=True,
                       note="requires hw_server + xsdb (Vitis); hw_server owns the SmartLynq2/Platform-Cable")

    # ---- interface --------------------------------------------------------------
    def capabilities(self) -> Capabilities:
        return Capabilities(scan=True, boundary_scan=True, mem_read=True, mem_write=True, halt=True, run=True,
                            max_tier="e", needs_vendor_sw=True,
                            notes="Native SmartLynq2 / Platform-Cable path via hw_server; full DAP access on an open board.")

    def scan(self) -> Command:
        # `targets` lists the whole debug-target tree hw_server sees (the xsdb analogue of scan_chain)
        return self._xsdb("targets", "xsdb target-tree scan (hw_server)", select=False)

    def mem_read(self, addr: int, size: int, out: str) -> Command:
        words = (size + 3) // 4
        body = f"stop; mrd -bin -file {out} {hex(addr)} {words}; con"
        return self._xsdb(body, f"xsdb mem-read {size}B ({words} words) @ {hex(addr)} -> {out}")

    def mem_write(self, addr: int, data) -> Command:
        if isinstance(data, int):
            return self._xsdb(f"mwr {hex(addr)} {hex(data)}",
                              f"xsdb write word {hex(data)} @ {hex(addr)}")
        # a binary file: mwr -bin -file
        return self._xsdb(f"mwr -bin -file {data} {hex(addr)}",
                          f"xsdb load binary {data} @ {hex(addr)}")

    def read_words(self, addr: int, count: int = 1) -> Command:
        return self._xsdb(f"mrd {hex(addr)} {count}", f"xsdb read {count} word(s) @ {hex(addr)}")

    def halt(self) -> Command:
        return self._xsdb("stop", "xsdb halt (stop) core")

    def run(self) -> Command:
        return self._xsdb("con", "xsdb resume (con) core")

    # ---- debug-target tree (P3) -------------------------------------------------
    def target_tree(self, live_output: str = None):
        """Parsed debug-target forest. Pass live `targets` output to parse it; otherwise return the
        reference ZynqMP tree so the GUI/CLI can show the expected cores before hw_server is present."""
        if live_output is not None:
            return T.parse_targets(live_output)
        if (self.soc or "").startswith("zynqmp"):
            return T.zynqmp_reference()
        return []

    def target_for(self, role, index=None):
        """Resolve a role (+optional core index) against a parsed/reference tree -> a bound copy."""
        roots = self.target_tree()
        node = T.find(roots, role=role, index=index)
        sel = node.tid if node else (f"{role}-{index}" if index is not None else role)
        return XsdbTransport(cfg=self.cfg, soc=self.soc, host=self.host, port=self.port,
                             target=sel, xsdb=self.xsdb)

    # ---- the OpenOCD-preserving alternative -------------------------------------
    def xvc_bridge_hint(self) -> Command:
        """Bridge hw_server's XVC server to OpenOCD's `xvc` driver — keeps the existing Tcl working
        over a SmartLynq2 without xsdb. hw_server exposes XVC; point OpenOCD at it."""
        shell = ('# 1) hw_server -e "set jtag-port-filter ..."   # or default; note its XVC url\n'
                 '# 2) openocd -c "adapter driver xvc; xvc_host 127.0.0.1; xvc_port 2542" \\\n'
                 f'#      -f {self.cfg or "openocd/zcu102.cfg"}   # then the existing enumerate.tcl runs as-is')
        return Command(desc="Bridge SmartLynq2 -> OpenOCD via hw_server XVC (keeps existing Tcl)",
                       shell=shell, needs_vendor_sw=True,
                       note="use when you want the OpenOCD Tcl toolchain but only a SmartLynq2 is available")


def _dq(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
