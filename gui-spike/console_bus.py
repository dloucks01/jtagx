#!/usr/bin/env python3
"""
console_bus.py — a tiny app-wide signal bus so every page routes its commands + output to the ONE
shell-level console (app_console/ConsolePanel), instead of each page owning its own log.

Any page does:  from console_bus import BUS
    BUS.command.emit("Unlock", cmd)     # → console shows "Unlock $ <cmd>"
    BUS.line.emit("d", text)            # → a streamed output line (kind: i/g/w/d/t)
    BUS.mark.emit("── Chain ──")        # → a divider (the shell emits this on tab switch)

The shell's console connects these to its append/echo/mark. Decouples producers (pages) from the
single consumer (the console), so the console "follows" whichever tab is active without the pages
needing a direct reference to it.
"""
from PySide6.QtCore import QObject, Signal


class ConsoleBus(QObject):
    line = Signal(str, str)      # (kind, text) — one output line; kind ∈ i/g/w/d/t
    command = Signal(str, str)   # (source_tag, command) — echoed as "<tag> $ <command>"
    mark = Signal(str)           # a divider line (tab switch / section boundary)
    run_done = Signal(int)       # a console-run command finished (exit code) — any page can react
                                  # (e.g. Dashboard refreshing the ARTIFACTS tile / a new-dumps banner)
                                  # without owning a reference to the console's runner.


BUS = ConsoleBus()
