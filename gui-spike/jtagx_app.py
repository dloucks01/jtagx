#!/usr/bin/env python3
"""
jtagx_app.py — unified app skeleton.

One QMainWindow, one icon rail switching a QStackedWidget across five REAL pages:
  0. Dashboard      — engagement main screen (qt_spike.Dashboard): hero, posture, registers, caps, console
  1. Reopen/Unlock  — the Phase-2b locked-board panel (unlock_panel.UnlockPanel)
  2. Chain          — chain + adapter detection + xsdb target tree (chain_page.ChainPage)
  3. Memory         — virtualized hex over any dump, with a dump selector (hex_view.HexView)
  4. Reports        — rendered Markdown deliverables (reports_page.ReportsPage)

The pages talk to each other: the Dashboard emits `navigate` to jump the shell to Memory/Reports,
capability/enumerate runs refresh the posture/hero, and the status bar reflects live USB detection.
Run:  python3 gui-spike/jtagx_app.py
"""
import glob, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root (for jtagx)
try:
    from jtagx import paths as dpaths          # writable data-dir resolver (P4)
except Exception:
    dpaths = None
try:
    from jtagx.transport import detect_adapters
except Exception:
    detect_adapters = None
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PySide6.QtCore import Qt
from PySide6.QtGui import QShortcut, QKeySequence
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton, QComboBox,
    QVBoxLayout, QHBoxLayout, QStackedWidget, QMessageBox, QFileDialog, QSplitter,
)
import qt_spike
import unlock_panel
from console_bus import BUS
from qt_spike import Dashboard, tag, ConsolePanel
from unlock_panel import UnlockPanel
from hex_view import HexView
from chain_page import ChainPage
from reports_page import ReportsPage
from help_page import HelpPage
from boards import load_boards

# (glyph, label) — the icon rail, one entry per stacked page
NAV = [("▦", "Dashboard"), ("🔓", "Unlock"), ("⛓", "Chain"), ("▤", "Memory"),
       ("🗎", "Reports"), ("❔", "Help")]


class App(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("JTAGx")
        self.resize(1200, 800)
        root = QWidget(); root.setObjectName("root")
        root.setAttribute(Qt.WA_StyledBackground, True)
        self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(0, 0, 0, 0); outer.setSpacing(0)

        # board profile registry + the active board (defaults to ZynqMP / ZCU102, the home board)
        _root = dpaths.repo_root() if dpaths else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.boards = load_boards(_root) or [{"soc": "zynqmp", "name": "Zynq UltraScale+",
                                              "cfg": "openocd/zcu102.cfg", "adapters": []}]
        self.board = self.boards[0]
        self.dash = Dashboard()
        self.dash.navigate.connect(self._go)            # cross-page flow (dump done → open Memory, etc.)
        self.dash.run_in_console.connect(self._console_input)   # register → console command
        self.chain = ChainPage(self.board["soc"])
        self.chain.btn_refresh.clicked.connect(self.refresh_status)   # rescan updates the shell too
        reports_root = dpaths.data_dir() if dpaths else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.reports = ReportsPage(reports_root)
        self.stack = QStackedWidget()
        self.stack.addWidget(self.dash)                 # 0 Dashboard
        _unlock = UnlockPanel()
        _unlock.posture_changed.connect(self.dash.set_board_posture)   # Attack-Surface follows the board
        self.stack.addWidget(_unlock)                   # 1 Reopen / Unlock
        self.stack.addWidget(self.chain)                # 2 Chain & Transport
        self.stack.addWidget(self._memory_page())       # 3 Memory / Hex (dump selector + viewer)
        self.stack.addWidget(self.reports)              # 4 Reports (renders reports/*.md)
        help_root = dpaths.repo_root() if dpaths else os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))
        self.stack.addWidget(HelpPage(help_root))       # 5 Help (renders the operator guide)

        outer.addWidget(self._topbar())
        body = QHBoxLayout(); body.setContentsMargins(0, 0, 0, 0); body.setSpacing(0)
        body.addWidget(self._rail())
        body.addWidget(self.stack, 1)
        bw = QWidget(); bw.setLayout(body)
        # the ONE interactive console — always visible, fed by every tab via console_bus
        self.console = ConsolePanel()
        self.console.cwd = dpaths.repo_root() if dpaths else os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))
        self.console.soc = self.board["soc"]; self.console.cfg = self.board["cfg"] or self.console.cfg
        self.console.backend_getter = self.dash._effective_backend   # /dump, mrd, scan use the live backend
        self.console.hooks = {                                       # slash-commands use the integrated flows
            "enumerate": self.dash.start_enumerate,
            "report": self.reports._generate,
            "set_backend": self._console_set_backend,
            "navigate": self._go,
        }
        # vertical splitter: drag the handle to grow the console (or the work area) to taste
        split = QSplitter(Qt.Vertical)
        split.setObjectName("mainsplit")
        split.addWidget(bw)
        split.addWidget(self.console)
        split.setStretchFactor(0, 1)          # the work area absorbs window resizes first
        split.setStretchFactor(1, 0)
        split.setCollapsible(0, False)
        split.setCollapsible(1, False)
        split.setSizes([620, 190])            # sensible initial split (work area : console)
        split.setHandleWidth(6)
        split.setStyleSheet("QSplitter#mainsplit::handle{background:#161c26;} "
                            "QSplitter#mainsplit::handle:hover{background:#2c3644;}")
        self._split = split
        outer.addWidget(split, 1)
        outer.addWidget(self._statusbar())
        self._install_shortcuts()
        self._update_crumb()
        BUS.mark.emit("Dashboard")          # opening context line

    def _install_shortcuts(self):
        # Ctrl+1..6 switch pages · Ctrl+E enumerate · Ctrl+R refresh the current page
        for i in range(len(NAV)):
            QShortcut(QKeySequence(f"Ctrl+{i+1}"), self, activated=lambda idx=i: self._go(idx))
        QShortcut(QKeySequence("Ctrl+E"), self, activated=self.dash.start_enumerate)
        QShortcut(QKeySequence("Ctrl+R"), self, activated=self._refresh_current)

    def _refresh_current(self):
        idx = self.stack.currentIndex()
        if idx == 1 and hasattr(self.stack.widget(1), "reload"):
            self.stack.widget(1).reload()
        elif idx == 2:
            self.chain.refresh()
        elif idx == 3:
            self._refresh_memory()
        elif idx == 4:
            self.reports._populate()
        self.refresh_status()

    def _topbar(self):
        f = QFrame(); f.setObjectName("topbar"); f.setFixedHeight(52)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(10)
        h.addWidget(tag("◈", "brand")); h.addWidget(tag("JTAGx", "brand"))
        h.addWidget(tag("engagement", "brandDim"))
        crumb = QFrame(); crumb.setObjectName("crumb")
        ch = QHBoxLayout(crumb); ch.setContentsMargins(11, 5, 11, 5)
        self._crumb = tag("", "crumbTxt"); ch.addWidget(self._crumb)
        h.addWidget(crumb)
        # board profile selector — retargets the Chain page + console + transport to the chosen board
        h.addWidget(tag("board", "brandDim"))
        self.board_sel = QComboBox()
        for b in self.boards:
            self.board_sel.addItem(f"{b['name']}", b["soc"])
        self.board_sel.setToolTip("Target board profile (drives the Chain page, adapters, and console soc/cfg)")
        self.board_sel.setStyleSheet(
            "QComboBox{background:#141922; color:#cdd7e4; border:1px solid #232c39;"
            "border-radius:8px; padding:4px 8px; font-size:12px;}")
        self.board_sel.currentIndexChanged.connect(self._set_board)
        h.addWidget(self.board_sel)
        h.addStretch(1)
        # transport backend selector — routes capability commands through OpenOCD / hw_server (P2/P3)
        h.addWidget(tag("transport", "brandDim"))
        self.backend_sel = QComboBox()
        self.backend_sel.addItem("Auto", "auto")
        self.backend_sel.addItem("OpenOCD", "openocd")
        self.backend_sel.addItem("hw_server (xsdb)", "hw_server")
        self.backend_sel.setToolTip("Which backend drives capability commands (Auto detects the plugged-in adapter)")
        self.backend_sel.setStyleSheet(
            "QComboBox{background:#141922; color:#cdd7e4; border:1px solid #232c39;"
            "border-radius:8px; padding:4px 8px; font-size:12px;}")
        self.backend_sel.currentIndexChanged.connect(self._set_backend)
        h.addWidget(self.backend_sel)
        enum = QPushButton("⛨  Enumerate"); enum.setObjectName("enumerate")
        enum.setToolTip("Run the enumeration sweep (Ctrl+E)")
        self.dash.set_enum_button(enum)   # streams into the Dashboard page's console
        h.addWidget(enum)
        self._dap_badge = tag("● DAP OPEN", "live")   # board-aware (updated by _refresh_board_status)
        h.addWidget(self._dap_badge)
        return f

    def _rail(self):
        f = QFrame(); f.setObjectName("rail"); f.setFixedWidth(60)
        v = QVBoxLayout(f); v.setContentsMargins(9, 12, 9, 12); v.setSpacing(6)
        self._navbtns = []
        for i, (glyph, label) in enumerate(NAV):
            b = QPushButton(glyph); b.setProperty("cls", "railbtn"); b.setCheckable(True)
            b.setToolTip(f"{label}  (Ctrl+{i+1})"); b.setChecked(i == 0)
            b.clicked.connect(lambda _, idx=i: self._go(idx))
            v.addWidget(b); self._navbtns.append(b)
        v.addStretch(1)
        g = QPushButton("⚙"); g.setProperty("cls", "railbtn")
        g.setToolTip("About / paths"); g.setCursor(Qt.PointingHandCursor)
        g.clicked.connect(self._about)
        v.addWidget(g)
        return f

    def _update_crumb(self):
        b = self.board
        extra = "  ·  210308BD8D4D" if b["soc"] == "zynqmp" else f"  ·  {b['soc']}"
        self._crumb.setText(f"⊕ {b['name']}{extra}")

    def _set_board(self, _i):
        soc = self.board_sel.currentData()
        b = next((x for x in self.boards if x["soc"] == soc), None)
        if not b or b["soc"] == self.board["soc"]:
            return
        self.board = b
        self._update_crumb()
        self.dash.set_board_identity(b["soc"], b["name"], b.get("paradigm", ""))
        self.console.soc = b["soc"]
        self.console.cfg = b["cfg"] or self.console.cfg
        # rebuild the Chain page for the new board (adapters/target-tree are per-profile)
        old = self.chain
        idx = self.stack.indexOf(old)
        self.chain = ChainPage(b["soc"])
        self.chain.btn_refresh.clicked.connect(self.refresh_status)
        self.stack.insertWidget(idx, self.chain)
        self.stack.removeWidget(old); old.deleteLater()
        up = self.stack.widget(1)                     # retarget the Unlock panel to this board
        if hasattr(up, "set_board"):
            up.set_board(b["soc"])
        BUS.mark.emit(f"board → {b['name']}  (soc={b['soc']}, cfg={b['cfg']})")
        self._go(2)              # land on the board-relevant Chain page
        self.refresh_status()
        self._refresh_board_status()
        if hasattr(self, "reports") and hasattr(self.reports, "set_board"):
            self.reports.set_board(b["soc"], b["name"])

    def _console_input(self, cmd):
        """Populate the console input with a command (ready for the operator to press Enter)."""
        self.console.input.setText(cmd)
        self.console.input.setFocus()

    def _console_set_backend(self, name):
        idx = {"auto": 0, "openocd": 1, "hw_server": 2}.get(name)
        if idx is not None:
            self.backend_sel.setCurrentIndex(idx)

    def _set_backend(self, _i):
        key = self.backend_sel.currentData()
        self.dash.set_backend(key)
        eff = self.dash._effective_backend()
        self.dash.append_line("i", f"› transport backend = {key}"
                              + (f" (→ {eff})" if key == "auto" else ""))
        self.refresh_status()

    def _go(self, idx):
        for i, b in enumerate(self._navbtns):
            b.setChecked(i == idx)
        self.stack.setCurrentIndex(idx)
        BUS.mark.emit(NAV[idx][1])          # console follows the active tab
        if hasattr(self, "console"):
            self.console.input.setToolTip(f"running from {self.console.cwd} · active tab: {NAV[idx][1]}")
        # keep the page current with any artifacts produced since it was last shown
        if idx == 3:
            self._refresh_memory()
        elif idx == 4 and hasattr(self.reports, "_populate"):
            self.reports._populate()
        self.refresh_status()

    def _about(self):
        code = dpaths.repo_root() if dpaths else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        data = dpaths.data_dir() if dpaths else code
        packaged = dpaths.is_packaged() if dpaths else False
        n = len(detect_adapters()) if detect_adapters else 0
        QMessageBox.information(
            self, "JTAGx",
            "JTAGx — JTAG enumeration & exploitation\n\n"
            f"code root : {code}\n"
            f"data dir  : {data}\n"
            f"packaged  : {packaged}\n"
            f"adapters  : {n} detected\n\n"
            "Backends: OpenOCD · AMD hw_server/xsdb · Microsemi Libero (stub).\n"
            "The operator drives all live JTAG; the app builds and streams the commands.")

    def _dumps_dir(self):
        return dpaths.dumps_dir() if dpaths else os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "dumps")

    def _memory_page(self):
        """A dump selector + the virtualized hex viewer. Newly-created dumps appear on entry/refresh."""
        page = QWidget(); page.setAttribute(Qt.WA_StyledBackground, True)
        v = QVBoxLayout(page); v.setContentsMargins(14, 12, 14, 8); v.setSpacing(8)
        bar = QHBoxLayout()
        lbl = QLabel("DUMP"); lbl.setStyleSheet("color:#98a6b8; font-size:11px; font-weight:600;")
        bar.addWidget(lbl)
        self.dumpsel = QComboBox(); self.dumpsel.setMinimumWidth(320)
        self.dumpsel.setStyleSheet("QComboBox{background:#141922; color:#e7ecf3; border:1px solid #232c39;"
                                   "border-radius:7px; padding:4px 8px;}")
        self.dumpsel.currentIndexChanged.connect(self._on_dump_pick)
        bar.addWidget(self.dumpsel)
        rb = QPushButton("↻"); rb.setToolTip("Rescan dumps"); rb.setObjectName("ghost")
        rb.setFixedWidth(36); rb.setCursor(Qt.PointingHandCursor)
        rb.clicked.connect(self._refresh_memory)
        bar.addWidget(rb)
        self.dl_btn = QPushButton("⬇  Save…"); self.dl_btn.setObjectName("ghost")
        self.dl_btn.setCursor(Qt.PointingHandCursor)
        self.dl_btn.setToolTip("Export a copy of the selected dump to a location you choose")
        self.dl_btn.clicked.connect(self._save_dump)
        bar.addWidget(self.dl_btn); bar.addStretch(1)
        v.addLayout(bar)
        self.hexview = HexView()
        v.addWidget(self.hexview, 1)
        self._refresh_memory()
        return page

    def _refresh_memory(self):
        """Repopulate the dump dropdown from the writable dumps dir, preserving the current selection."""
        if not hasattr(self, "dumpsel"):
            return
        cur = self.dumpsel.currentData()
        bins = sorted(glob.glob(os.path.join(self._dumps_dir(), "*.bin")),
                      key=os.path.getmtime, reverse=True)
        self.dumpsel.blockSignals(True)
        self.dumpsel.clear()
        for p in bins:
            self.dumpsel.addItem(f"{os.path.basename(p)}   ·   {os.path.getsize(p):,} B", p)
        self.dumpsel.blockSignals(False)
        if not bins:
            self.hexview.file_lbl.setText("no dumps yet — run a Dump capability on the Dashboard")
            self.hexview.model.set_data(b"")
            return
        # restore prior selection if still present, else pick the newest
        idx = next((i for i in range(self.dumpsel.count()) if self.dumpsel.itemData(i) == cur), 0)
        self.dumpsel.setCurrentIndex(idx)
        self._on_dump_pick(idx)

    def _on_dump_pick(self, idx):
        p = self.dumpsel.itemData(idx)
        if hasattr(self, "dl_btn"):
            self.dl_btn.setEnabled(bool(p))
        if p:
            base = 0x100000 if os.path.basename(p) == "os-live.bin" else 0
            self.hexview._base = base
            self.hexview.load(p)

    def _save_dump(self):
        """Export a copy of the selected dump to a user-chosen path (desktop 'download')."""
        src = self.dumpsel.currentData()
        if not src or not os.path.exists(src):
            QMessageBox.warning(self, "No dump", "Select a dump to save first.")
            return
        dest, _ = QFileDialog.getSaveFileName(
            self, "Save dump as…", os.path.join(os.path.expanduser("~"), os.path.basename(src)),
            "Binary dumps (*.bin);;All files (*)")
        if not dest:
            return
        try:
            shutil.copy2(src, dest)
        except OSError as e:
            QMessageBox.critical(self, "Save failed", f"Could not write {dest}:\n{e}")
            return
        sz = os.path.getsize(dest)
        if hasattr(self, "_st_note"):
            self._st_note.setText(f"saved {os.path.basename(dest)} ({sz:,} B)")

    def _statusbar(self):
        f = QFrame(); f.setObjectName("statusbar"); f.setFixedHeight(26)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(16)
        self._st_conn = tag("", "statusTxt")
        self._st_adapter = tag("", "statusTxt")
        h.addWidget(self._st_conn); h.addWidget(self._st_adapter)
        self._st_chain = tag("", "statusTxt")       # board-aware chain summary
        self._st_verdict = tag("", "statusTxt")     # board-aware access verdict
        h.addWidget(self._st_chain); h.addWidget(self._st_verdict)
        h.addStretch(1)
        self._st_note = tag("", "statusTxt")       # transient feedback (e.g. dump saved)
        h.addWidget(self._st_note)
        h.addWidget(tag("unlock-engine ready", "statusTxt"))
        self.refresh_status()
        self._refresh_board_status()
        return f

    def _refresh_board_status(self):
        """Make the topbar DAP badge + the statusbar chain/verdict follow the active board. Only the
        home ZCU102 is a known-OPEN baseline; every other board reads UNKNOWN until access-check."""
        soc = self.board.get("soc", "") if getattr(self, "board", None) else ""
        home = soc == "zynqmp"
        if hasattr(self, "_dap_badge"):
            self._dap_badge.setText("● DAP OPEN" if home else "◌ DAP UNKNOWN")
            self._dap_badge.setStyleSheet(
                "color:#3ecf8e; font-size:12px; font-weight:600;" if home
                else "color:#e7b04b; font-size:12px; font-weight:600;")
        if hasattr(self, "_st_chain"):
            self._st_chain.setText("chain 2 TAPs" if home else "chain: run scan")
        if hasattr(self, "_st_verdict"):
            self._st_verdict.setText("verdict: OPEN" if home else "verdict: run access-check")

    def refresh_status(self):
        """Reflect live USB adapter detection in the status bar (called on nav + Chain refresh)."""
        if not hasattr(self, "_st_conn"):
            return
        present = []
        if detect_adapters:
            try:
                present = detect_adapters()
            except Exception:
                present = []
        be = self.dash._effective_backend() if hasattr(self, "dash") else "openocd"
        sel = self.dash.backend if hasattr(self, "dash") else "auto"
        be_txt = f"backend: {be}" + ("  (auto)" if sel == "auto" else "  (pinned)")
        if present:
            self._st_conn.setText("● Connected")
            self._st_conn.setStyleSheet("color:#3ecf8e; font-size:11px;")
            first = present[0]
            self._st_adapter.setText(f"{first['name']}  ·  {be_txt}")
        else:
            self._st_conn.setText("○ No adapter")
            self._st_conn.setStyleSheet("color:#e7b04b; font-size:11px;")
            self._st_adapter.setText(be_txt)

    def closeEvent(self, event):
        self.dash.stop()
        super().closeEvent(event)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    # combine both spikes' stylesheets so the Dashboard and the UnlockPanel are both themed
    app.setStyleSheet(qt_spike.QSS + unlock_panel.QSS)
    w = App(); w.show()
    sys.exit(app.exec())
