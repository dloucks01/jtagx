#!/usr/bin/env python3
"""
proc_runner.py — a QProcess wrapper that runs a real command (OpenOCD, a tool) and streams its stdout
line-by-line into the GUI. This is what turns the app from a canned demo into an engagement DRIVER:
clicking Enumerate / a capability actually launches the process and shows live output, exactly like the
terminal would (QProcess.readyReadStandardOutput is the real-app analogue of the earlier canned QThread).

Operator-driven by design — the user clicks; nothing runs on its own.
"""
from PySide6.QtCore import QObject, QProcess, Signal


class ProcRunner(QObject):
    line = Signal(str)     # one line of merged stdout/stderr
    done = Signal(int)     # exit code (or -1 on failure to start)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.proc = None
        self._buf = ""

    def busy(self):
        return self.proc is not None and self.proc.state() != QProcess.NotRunning

    def run(self, argv, cwd=None):
        """Start argv (a list). Returns False if already running or argv empty."""
        if self.busy() or not argv:
            return False
        self._buf = ""
        self.proc = QProcess(self)
        self.proc.setProcessChannelMode(QProcess.MergedChannels)
        if cwd:
            self.proc.setWorkingDirectory(cwd)
        self.proc.readyReadStandardOutput.connect(self._read)
        self.proc.finished.connect(self._finished)
        self.proc.errorOccurred.connect(self._error)
        self.proc.start(argv[0], [str(a) for a in argv[1:]])
        return True

    def run_shell(self, cmd, cwd=None):
        """Run a shell command string (for the tool recipes that carry env vars / pipes)."""
        return self.run(["bash", "-lc", cmd], cwd=cwd)

    def _read(self):
        self._buf += bytes(self.proc.readAllStandardOutput()).decode("utf-8", "replace")
        *lines, self._buf = self._buf.split("\n")
        for ln in lines:
            self.line.emit(ln)

    def _finished(self, code, _status):
        if self._buf:
            self.line.emit(self._buf); self._buf = ""
        self.done.emit(int(code))

    def _error(self, _err):
        if self.proc and self.proc.state() == QProcess.NotRunning:
            self.line.emit(f"[proc] failed to start: {self.proc.program()}")
            self.done.emit(-1)

    def stop(self):
        if self.busy():
            self.proc.kill()
            self.proc.waitForFinished(2000)
