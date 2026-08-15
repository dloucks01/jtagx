#!/usr/bin/env python3
"""
jtagx.transport.base — the backend-agnostic transport interface.

Why this exists: on a real engagement OpenOCD would not drive the AMD SmartLynq2 or the
Microsemi FlashPro4 (both are vendor-proprietary adapters with no OpenOCD driver), so the
whole enumeration/exploitation flow stalled at "can't even talk to the chip". The fix is to
stop hard-coding OpenOCD: model each JTAG primitive (scan / mem-read / mem-write / halt / run)
as something a *backend* knows how to drive, and let the backend be OpenOCD, AMD hw_server
(xsdb), or Microsemi Libero/FlashPro depending on which adapter is in the operator's hand.

Design fits the hands-on-JTAG model (memory feedback_hands_on_jtag): a Transport does NOT open
USB or touch silicon itself — it *emits a runnable Command* (argv or a shell string) that the
operator, the CLI, or the GUI's ProcRunner executes. So the abstraction is pure/offline-testable
and every backend is uniform: same five verbs, different generated command.
"""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Command:
    """One runnable step. Prefer argv (exec directly); shell is the fallback for env/pipes."""
    desc: str
    argv: Optional[list] = None
    shell: Optional[str] = None
    needs_vendor_sw: bool = False   # requires xsdb / Libero on PATH (not a plain OpenOCD box)
    note: str = ""

    def as_shell(self) -> str:
        """A single shell string for ProcRunner.run_shell / copy-to-clipboard."""
        if self.shell is not None:
            return self.shell
        if self.argv is not None:
            return " ".join(_q(str(a)) for a in self.argv)
        return ""


def _q(s: str) -> str:
    return s if s and all(c.isalnum() or c in "-_=/.:@%+" for c in s) else "'" + s.replace("'", "'\\''") + "'"


@dataclass
class Capabilities:
    """What a (backend, target) pair can actually do, and how far up the access ladder it reaches."""
    scan: bool = False
    mem_read: bool = False
    mem_write: bool = False
    halt: bool = False
    run: bool = False
    max_tier: str = "a"     # a=IDCODE b=bscan c=mem-AP d=run-control e=exploitation
    needs_vendor_sw: bool = False
    notes: str = ""


class Transport(ABC):
    """A driver that turns JTAG primitives into runnable Commands for one backend.

    Construct with the board context it needs (an OpenOCD cfg, or a target SoC, or a hw_server
    host/port). Subclasses implement the five verbs + capabilities(). None of them execute —
    they return Command objects.
    """
    backend: str = "?"

    def __init__(self, *, cfg: str = "", soc: str = "", host: str = "127.0.0.1",
                 port: Optional[int] = None, target: str = "", extra: Optional[dict] = None):
        self.cfg = cfg
        self.soc = soc
        self.host = host
        self.port = port
        self.target = target          # backend target selector (xsdb targets index / filter)
        self.extra = extra or {}

    @abstractmethod
    def capabilities(self) -> Capabilities: ...

    @abstractmethod
    def scan(self) -> Command:
        """Enumerate the JTAG chain (IDCODEs / target list)."""

    @abstractmethod
    def mem_read(self, addr: int, size: int, out: str) -> Command:
        """Read `size` bytes at `addr` into file `out`."""

    @abstractmethod
    def mem_write(self, addr: int, data) -> Command:
        """Write bytes (or a single word int) at `addr`."""

    def read_words(self, addr: int, count: int = 1) -> Command:
        """Read `count` 32-bit words at `addr` to stdout (an interactive peek, not a file dump).
        Default: unsupported — backends that can (openocd mdw / xsdb mrd) override this."""
        return Command(desc="read_words not supported by this backend", shell="")

    @abstractmethod
    def halt(self) -> Command:
        """Halt the current core."""

    @abstractmethod
    def run(self) -> Command:
        """Resume the current core."""

    # convenience for the GUI/CLI: the whole verb set as {name: Command|None}
    def plan(self, *, read=(0x0, 0x1000, "dumps/scan.bin")) -> dict:
        caps = self.capabilities()
        out = {"backend": self.backend, "capabilities": caps, "scan": self.scan()}
        out["halt"] = self.halt() if caps.halt else None
        out["run"] = self.run() if caps.run else None
        out["mem_read"] = self.mem_read(*read) if caps.mem_read else None
        return out
