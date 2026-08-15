#!/usr/bin/env python3
"""
jtagx.transport.libero — the Microsemi/Microchip Libero + FlashPro backend (SmartFusion2 / IGLOO2).

STUB, honestly scoped. The FlashPro4/5 is a vendor-proprietary adapter with no OpenOCD driver;
it is driven by FlashPro Express / the Libero `fpgenprog`/`FlashPro` Tcl engine, which is a
programming-and-verify flow (bitstream, eNVM, security), NOT an arbitrary mem-read/run-control
debugger like xsdb. The SmartFusion2's Cortex-M3, by contrast, IS reachable for run-control — but
via a *separate* debug path (its CoreSight DAP over the same JTAG chain), which OpenOCD/J-Link can
drive once the chain is understood.

So this backend does two honest things:
  1. emits the FlashPro Tcl actions we CAN drive (IDCODE/device check, read eNVM/status where the
     security policy allows) as runnable `fp` Tcl snippets;
  2. for M3 run-control and RAM read/write, it POINTS AT the OpenOCD/xsdb path rather than pretending
     FlashPro can do it — capabilities() reports mem_read/halt/run as backend-limited.

The goal for these boards (per the engagement) is extraction + exploitation; the realistic first
step is device/security-state readout via FlashPro, then M3 debug over a CoreSight-capable adapter.
"""
from __future__ import annotations
from .base import Transport, Command, Capabilities


class LiberoTransport(Transport):
    backend = "libero"

    def __init__(self, *, flashpro="FPExpress", **kw):
        super().__init__(**kw)
        self.flashpro = flashpro

    def capabilities(self) -> Capabilities:
        # FlashPro reaches device-ID + security/eNVM readout (policy permitting), NOT general run-control.
        return Capabilities(scan=True, boundary_scan=True, mem_read=False, mem_write=False, halt=False, run=False,
                            max_tier="b", needs_vendor_sw=True,
                            notes="FlashPro = program/verify/security-status engine, not a debugger. "
                                  "For SmartFusion2 M3 run-control + RAM, use a CoreSight adapter "
                                  "(OpenOCD/J-Link) on the same chain — see m3_debug_hint().")

    def scan(self) -> Command:
        # FlashPro device check / IDCODE via a FlashPro Express Tcl action
        tcl = ('set_programming_action -name check_device\\n'
               'run_selected_actions')
        return Command(desc="FlashPro device/IDCODE check (SmartFusion2/IGLOO2)",
                       shell=f'# {self.flashpro} <<EOF\\n{tcl}\\nEOF',
                       needs_vendor_sw=True,
                       note="stub: FlashPro Express Tcl; confirms part + reads device security state")

    def mem_read(self, addr: int, size: int, out: str) -> Command:
        return Command(desc="eNVM/flash read via FlashPro (policy permitting) — else use M3 debug path",
                       shell=('# FlashPro can read eNVM/status only if the security policy allows;\\n'
                              '# for arbitrary RAM/flash use the CoreSight M3 path (see m3_debug_hint)'),
                       needs_vendor_sw=True, note="stub — vendor security policy gates this")

    def mem_write(self, addr: int, data) -> Command:
        return Command(desc="Program via FlashPro (bitstream/eNVM) — destructive, out of scope for this stub",
                       shell="# use FlashPro Express program flow deliberately; not wired here",
                       needs_vendor_sw=True, note="stub")

    def halt(self) -> Command:
        return self.m3_debug_hint()

    def run(self) -> Command:
        return self.m3_debug_hint()

    def m3_debug_hint(self) -> Command:
        """SmartFusion2 Cortex-M3 run-control is a CoreSight-DAP job — drive it with OpenOCD/J-Link,
        not FlashPro. This routes the operator to the right backend for tier c..e."""
        return Command(
            desc="SmartFusion2 M3 run-control -> use OpenOCD/J-Link (CoreSight), not FlashPro",
            shell=('openocd -f interface/jlink.cfg -f target/smartfusion2.cfg '
                   '-c "init; halt; dump_image dumps/m3.bin 0x20000000 0x10000; resume; shutdown"'),
            needs_vendor_sw=False,
            note="the M3 CoreSight DAP is a separate debug path on the same JTAG chain")
