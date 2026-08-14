#!/usr/bin/env python3
"""
jtagx_app.py — unified app skeleton.

One QMainWindow, one icon rail switching a QStackedWidget between the two flagship spikes:
  0. Dashboard      — the engagement main screen (qt_spike.Dashboard)
  1. Reopen/Unlock  — the Phase-2b locked-board panel (unlock_panel.UnlockPanel)
  + stub pages (Chain / Memory / Reports) as placeholders.

This is the consolidation the GUI has been building toward: the dashboard and the unlock engine
in a single shell. Run:  python3 gui-spike/jtagx_app.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton,
    QVBoxLayout, QHBoxLayout, QStackedWidget,
)
import qt_spike
import unlock_panel
from qt_spike import Dashboard, tag
from unlock_panel import UnlockPanel
from hex_view import HexView
from chain_page import ChainPage
from reports_page import ReportsPage

# (glyph, label) — first two are live pages; the rest are stubs
NAV = [("▦", "Dashboard"), ("🔓", "Unlock"), ("⛓", "Chain"), ("▤", "Memory"), ("🗎", "Reports")]


class App(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("JTAGx")
        self.resize(1200, 800)
        root = QWidget(); root.setObjectName("root")
        root.setAttribute(Qt.WA_StyledBackground, True)
        self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(0, 0, 0, 0); outer.setSpacing(0)

        self.dash = Dashboard()
        self.stack = QStackedWidget()
        self.stack.addWidget(self.dash)                 # 0 Dashboard
        self.stack.addWidget(UnlockPanel())             # 1 Reopen / Unlock
        self.stack.addWidget(ChainPage("zynqmp"))       # 2 Chain & Transport (chain + adapter allowlist)
        self.stack.addWidget(self._memory_page())      # 3 Memory / Hex (real, over a dump)
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.stack.addWidget(ReportsPage(root))         # 4 Reports (renders reports/*.md)

        outer.addWidget(self._topbar())
        body = QHBoxLayout(); body.setContentsMargins(0, 0, 0, 0); body.setSpacing(0)
        body.addWidget(self._rail())
        body.addWidget(self.stack, 1)
        bw = QWidget(); bw.setLayout(body)
        outer.addWidget(bw, 1)
        outer.addWidget(self._statusbar())

    def _topbar(self):
        f = QFrame(); f.setObjectName("topbar"); f.setFixedHeight(52)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(10)
        h.addWidget(tag("◈", "brand")); h.addWidget(tag("JTAGx", "brand"))
        h.addWidget(tag("engagement", "brandDim"))
        crumb = QFrame(); crumb.setObjectName("crumb")
        ch = QHBoxLayout(crumb); ch.setContentsMargins(11, 5, 11, 5)
        ch.addWidget(tag("⊕ ZCU102 · XCZU9EG  ·  210308BD8D4D", "crumbTxt"))
        h.addWidget(crumb); h.addStretch(1)
        enum = QPushButton("⛨  Enumerate"); enum.setObjectName("enumerate")
        self.dash.set_enum_button(enum)   # streams into the Dashboard page's console
        h.addWidget(enum)
        h.addWidget(tag("● DAP OPEN", "live"))
        return f

    def _rail(self):
        f = QFrame(); f.setObjectName("rail"); f.setFixedWidth(60)
        v = QVBoxLayout(f); v.setContentsMargins(9, 12, 9, 12); v.setSpacing(6)
        self._navbtns = []
        for i, (glyph, label) in enumerate(NAV):
            b = QPushButton(glyph); b.setProperty("cls", "railbtn"); b.setCheckable(True)
            b.setToolTip(label); b.setChecked(i == 0)
            b.clicked.connect(lambda _, idx=i: self._go(idx))
            v.addWidget(b); self._navbtns.append(b)
        v.addStretch(1)
        g = QPushButton("⚙"); g.setProperty("cls", "railbtn"); v.addWidget(g)
        return f

    def _go(self, idx):
        for i, b in enumerate(self._navbtns):
            b.setChecked(i == idx)
        self.stack.setCurrentIndex(idx)

    def _memory_page(self):
        import glob
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        oslive = os.path.join(root, "dumps", "os-live.bin")
        if os.path.exists(oslive):
            return HexView(oslive, base=0x100000)   # the live DDR dump, VAs based at 0x100000
        bins = sorted(glob.glob(os.path.join(root, "dumps", "*.bin")), key=os.path.getsize)
        return HexView(bins[-1]) if bins else self._stub("Memory / Hex — no dumps yet")

    def _stub(self, text):
        w = QWidget(); w.setAttribute(Qt.WA_StyledBackground, True)
        lay = QVBoxLayout(w); lay.addStretch(1)
        lbl = QLabel(text); lbl.setAlignment(Qt.AlignCenter)
        lbl.setStyleSheet("color:#5e6b7c; font-size:15px;")
        lay.addWidget(lbl); lay.addStretch(1)
        return w

    def _statusbar(self):
        f = QFrame(); f.setObjectName("statusbar"); f.setFixedHeight(26)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(16)
        for s in ["● Connected", "FT2232H · JTAG · 10 MHz", "chain 2 TAPs", "verdict: OPEN"]:
            h.addWidget(tag(s, "statusTxt"))
        h.addStretch(1)
        h.addWidget(tag("unlock-engine ready", "statusTxt"))
        return f

    def closeEvent(self, event):
        self.dash.stop()
        super().closeEvent(event)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    # combine both spikes' stylesheets so the Dashboard and the UnlockPanel are both themed
    app.setStyleSheet(qt_spike.QSS + unlock_panel.QSS)
    w = App(); w.show()
    sys.exit(app.exec())
