#!/usr/bin/env python3
"""
JTAGx GUI spike — PySide6 / Qt version of the v2 main screen.

Purpose: feel native Qt for this tool. Reproduces the v2 layout (icon rail,
target hero + stat tiles, chain tree, posture QTableView, capabilities,
streaming console) using stock Qt widgets + a QSS dark theme.

The dashboard body is factored into a reusable `Dashboard(QWidget)` so the unified
app skeleton (gui-spike/jtagx_app.py) can embed it beside the UnlockPanel under one rail.

Run:   pip install PySide6   &&   python3 qt_spike.py
"""
import glob
import json
import os
import sys
import time
from PySide6.QtCore import Qt, QThread, Signal, QObject

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton,
    QVBoxLayout, QHBoxLayout, QGridLayout, QTabWidget, QTreeWidget,
    QTreeWidgetItem, QTableWidget, QTableWidgetItem, QPlainTextEdit,
    QHeaderView, QSizePolicy,
)

# ------------------------------------------------------------------ data
POSTURE = [
    ("Secure Boot policy", "CSU_MULTI_BOOT", "JTAG · unsigned", "open"),
    ("JTAG DAP gate", "JTAG_SEC", "0x00000000", "open"),
    ("DAP secure access", "JTAG_DAP_CFG", "NS permitted", "open"),
    ("AES boot key", "BBRAM / eFuse", "zeroed", "open"),
    ("PUF enrollment", "EFUSE_PUF", "not enrolled", "open"),
    ("eFuse write locks", "EFUSE_SEC_CTRL", "0x00000000", "open"),
    ("PPK0/1 hash", "EFUSE_PPK", "unprogrammed", "open"),
    ("Anti-tamper", "CSU_TAMPER", "disabled", "open"),
    ("SoC debug auth", "CoreSight AUTH", "DBGEN·NIDEN·SPIDEN", "open"),
    ("TrustZone (XMPU/XPPU)", "XMPU", "0 regions", "open"),
    ("PMU firmware auth", "PMU_GLOBAL", "no FW", "na"),
]
CAPS = [
    ("ok", "Enumerate posture", "§1–16 sweep → raw JSON"),
    ("ok", "Dump DDR / OCM", "AXI mem-AP · live regions"),
    ("ok", "Break & capture", "HW bp → regs + deref args"),
    ("ok", "Live-patch VA→PA", "kernel string / function"),
    ("warn", "Dump BootROM", "AXI read-filter · R5/CSUDMA only"),
    ("warn", "Dump PMU ROM", "needs 3-TAP BSCAN unlock"),
    ("off", "Core code-exec", "wedges DAP → use reflash"),
]
LOG_LINES = [
    ('t', "14:02:17 › source openocd/enumerate.tcl"),
    ('i', "Info : JTAG tap: zynqmp.tap  0x14738093 (mfg 0x049, part 0x4738)"),
    ('i', "Info : DAP 0x5ba00477 — ARM CoreSight SoC-400 · 2 APs"),
    ('g', "§4  JTAG_SEC (0xFFCA0038) ......... 0x00000000  → all debug gates enabled"),
    ('w', "§9  AES key (BBRAM/eFuse) ......... zeroed       → not provisioned"),
    ('w', "§16 XMPU/XPPU regions ............. 0            → TrustZone not enforced"),
    ('g', "Info : wrote reports/raw-20260814-140233.json (656 registers)"),
    ('g', "14:02:33 ✓ enumeration complete — 13 open/dev · 0 hardened"),
]

# ------------------------------------------------------------------ theme
QSS = """
* { color: #e7ecf3; font-family: "Inter","Segoe UI","Noto Sans",sans-serif; font-size: 13px; }
QMainWindow, QWidget#root { background: #0d1017; }
QFrame#topbar { background: #0f141c; border-bottom: 1px solid #1c242f; }
QLabel#brand { font-size: 15px; font-weight: 700; }
QLabel#brandDim { color: #5e6b7c; }
QFrame#crumb { background: #141922; border: 1px solid #232c39; border-radius: 8px; }
QLabel#crumbTxt { color: #98a6b8; }
QLabel#live { color: #3ecf8e; background: rgba(62,207,142,0.08);
    border: 1px solid rgba(62,207,142,0.25); border-radius: 8px; padding: 5px 10px; font-weight: 600; }
QPushButton#enumerate { background: #3b6ff0; color: white; border: 0; border-radius: 8px;
    padding: 6px 14px; font-weight: 600; }
QPushButton#enumerate:hover { background: #4d82ff; }
QPushButton#ghost { background: #141922; color: #98a6b8; border: 1px solid #232c39;
    border-radius: 8px; padding: 6px 12px; }

QFrame#rail { background: #0c1016; border-right: 1px solid #1c242f; }
QPushButton[cls~="railbtn"] { background: transparent; border: 0; border-radius: 11px; color: #5e6b7c;
    font-size: 17px; padding: 10px; }
QPushButton[cls~="railbtn"]:hover { background: #141922; color: #98a6b8; }
QPushButton[cls~="railbtn"]:checked { background: #1a212c; color: white; }

QFrame[cls~="card"] { background: #171e29; border: 1px solid #232c39; border-radius: 14px; }
QFrame#idcard { background: #131a24; border: 1px solid #232c39; border-radius: 14px; }
QLabel[cls~="tileLabel"] { color: #5e6b7c; font-size: 10px; font-weight: 600; letter-spacing: 1px; }
QLabel[cls~="tileNum"] { font-size: 24px; font-weight: 800; font-family: "DejaVu Sans Mono",monospace; }
QLabel[cls~="tileSub"] { color: #98a6b8; font-size: 11px; }
QLabel#board { font-size: 18px; font-weight: 700; }
QLabel#chip { color: #33d6c4; font-family: "DejaVu Sans Mono",monospace; font-size: 12px; }
QLabel#vbadge { color: #3ecf8e; background: rgba(62,207,142,0.10);
    border: 1px solid rgba(62,207,142,0.30); border-radius: 20px; padding: 4px 10px; font-weight: 600; font-size: 11px; }

QFrame[cls~="panel"] { background: #10151d; border: 1px solid #232c39; border-radius: 14px; }
QLabel[cls~="panelHdr"] { color: #98a6b8; font-size: 11px; font-weight: 700; letter-spacing: 1px; padding: 12px 14px; }

QTreeWidget, QTableWidget { background: transparent; border: 0; outline: 0; }
QTreeWidget::item, QTableWidget::item { padding: 5px 4px; }
QTreeWidget::item:selected, QTableWidget::item:selected {
    background: rgba(91,140,255,0.16); color: #eaf1ff; }
QHeaderView::section { background: #0f151d; color: #5e6b7c; border: 0;
    border-bottom: 1px solid #232c39; padding: 8px 10px; font-size: 10px; font-weight: 700; }
QTableWidget { gridline-color: #1c242f; }

QTabWidget::pane { border: 0; }
QTabBar::tab { background: transparent; color: #98a6b8; padding: 8px 14px; margin-right: 4px;
    border-top-left-radius: 9px; border-top-right-radius: 9px; }
QTabBar::tab:selected { background: #1a212c; color: white; }

QFrame[cls~="cap"] { background: #141922; border: 1px solid #232c39; border-radius: 11px; }
QLabel[cls~="capTitle"] { font-weight: 600; }
QLabel[cls~="capTitleOff"] { color: #5e6b7c; font-weight: 600; }
QLabel[cls~="capSub"] { color: #5e6b7c; font-size: 10px; }

QPlainTextEdit#console { background: #090c11; border: 1px solid #232c39; border-radius: 14px;
    color: #aeb9c7; font-family: "DejaVu Sans Mono",monospace; font-size: 12px; padding: 8px; }
QFrame#statusbar { background: #0b0f15; border-top: 1px solid #1c242f; }
QLabel#statusTxt { color: #98a6b8; font-size: 11px; }

QScrollBar:vertical { background: transparent; width: 10px; margin: 2px; }
QScrollBar::handle:vertical { background: #2c3644; border-radius: 5px; min-height: 24px; }
QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
"""

PILL = {
    "open":     ("● open", "#f79087", "rgba(242,104,95,0.10)", "rgba(242,104,95,0.25)"),
    "hardened": ("● hardened", "#8fd39a", "rgba(62,207,142,0.10)", "rgba(62,207,142,0.30)"),
    "na":       ("n/a",    "#98a6b8", "#232c39",               "#2c3644"),
}

def load_real_posture(root):
    """Delegate to the shared core jtagx.posture: newest raw-*.json -> posture table rows (or None)."""
    try:
        if root not in sys.path:
            sys.path.insert(0, root)   # repo root — for `import jtagx`
        from jtagx.posture import newest_capture, load_capture, posture_rows
        p = newest_capture(root)
        return posture_rows(load_capture(p)) if p else None
    except Exception:
        return None
CAPIC = {"ok": ("✓", "#3ecf8e"), "warn": ("!", "#e7b04b"), "off": ("✕", "#5e6b7c")}

# the real command each capability runs (logged to the console on click; hands-on model — no auto-run)
CAP_CMDS = {
    "Dump DDR / OCM": 'DUMP_ADDR=0x00100000 DUMP_SIZE=0x01000000 DUMP_HALT=1 DUMP_OUT=dumps/os-live.bin '
                      'openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"',
    "Break & capture": 'BC_ADDR=0x<funcVA> BC_DEREF="0 1" '
                       'openocd -f openocd/zcu102.cfg -c "init; source openocd/break-capture.tcl; shutdown"',
    "Live-patch VA→PA": 'python3 tools/patch-recipe.py --arch aarch64 --behavior ret0 --func <fn> --syms dumps/symbols.txt',
    "Dump BootROM": 'openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-bootrom.tcl; shutdown"   # low odds; R5/CSUDMA',
    "Dump PMU ROM": 'openocd -f openocd/zcu102-3tap.cfg -c "init; source openocd/open-pmu-tap.tcl; shutdown"',
}


# ------------------------------------------------------------- streaming worker
class LogWorker(QObject):
    line = Signal(str, str)   # (kind, text)
    done = Signal()

    def run(self):
        for kind, text in LOG_LINES:
            time.sleep(0.28)      # worker thread; blocking here is fine
            self.line.emit(kind, text)
        self.done.emit()


def tag(text, obj=None, cls=None):
    lbl = QLabel(text)
    if obj:
        lbl.setObjectName(obj)
    if cls:
        lbl.setProperty("cls", cls)
    return lbl


class ClickFrame(QFrame):
    """A QFrame that fires a callback when clicked (for the capability cards)."""
    def __init__(self, on_click):
        super().__init__()
        self._cb = on_click

    def mousePressEvent(self, e):
        self._cb()
        super().mousePressEvent(e)


# ------------------------------------------------------------------ dashboard
class Dashboard(QWidget):
    """The engagement main screen body: target hero + chain/posture/capabilities + streaming console.
    Reusable — both Main (standalone) and jtagx_app embed this under a shared icon rail. The Enumerate
    button lives in the shell's top bar; wire it via set_enum_button()."""

    def __init__(self):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        self._enum_btn = None
        self.thread_ = None
        v = QVBoxLayout(self); v.setContentsMargins(16, 14, 16, 14); v.setSpacing(14)
        v.addLayout(self._hero())
        v.addLayout(self._content(), 1)
        v.addWidget(self._console_panel())

    def set_enum_button(self, b):
        self._enum_btn = b
        b.clicked.connect(self.start_enumerate)

    def _hero(self):
        h = QHBoxLayout(); h.setSpacing(12)
        idc = QFrame(); idc.setObjectName("idcard"); idc.setMinimumWidth(250)
        iv = QVBoxLayout(idc); iv.setContentsMargins(16, 14, 16, 14); iv.setSpacing(4)
        iv.addWidget(tag("TARGET", cls="tileLabel"))
        iv.addWidget(tag("Zynq UltraScale+", "board"))
        iv.addWidget(tag("XCZU9EG · MPSoC", "chip"))
        iv.addWidget(tag("⛨ Access: OPEN · unprovisioned", "vbadge"))
        h.addWidget(idc)
        tiles = [("CHAIN", "2", "TAPs · 6 cores", "#5b8cff"),
                 ("POSTURE", "13", "open / dev of 14", "#f2685f"),
                 ("CAPABILITIES", "4", "available now", "#3ecf8e"),
                 ("ARTIFACTS", "7", "dumps captured", "#98a6b8")]
        for label, num, sub, color in tiles:
            c = QFrame(); c.setProperty("cls", "card")
            cv = QVBoxLayout(c); cv.setContentsMargins(14, 13, 14, 13); cv.setSpacing(5)
            cv.addWidget(tag(label, cls="tileLabel"))
            n = tag(num, cls="tileNum"); n.setStyleSheet(f"color:{color};")
            cv.addWidget(n)
            cv.addWidget(tag(sub, cls="tileSub"))
            h.addWidget(c, 1)
        return h

    def _content(self):
        h = QHBoxLayout(); h.setSpacing(14)
        h.addWidget(self._chain_panel(), 0)
        h.addWidget(self._center_panel(), 1)
        h.addWidget(self._caps_panel(), 0)
        return h

    def _chain_panel(self):
        p = QFrame(); p.setProperty("cls", "panel"); p.setFixedWidth(230)
        v = QVBoxLayout(p); v.setContentsMargins(0, 0, 0, 8); v.setSpacing(0)
        v.addWidget(tag("⛓  CHAIN & TRANSPORT", cls="panelHdr"))
        tree = QTreeWidget(); tree.setHeaderHidden(True); tree.setRootIsDecorated(True)
        t0 = QTreeWidgetItem(["TAP0 · ARM DAP · 0x5BA00477"]); tree.addTopLevelItem(t0)
        for name in ["A53 #0  ▸ HALT", "A53 #1  ▸ RUN", "A53 #2  ▸ RUN",
                     "A53 #3  ▸ RUN", "R5 #0/#1  ▸ OFF"]:
            t0.addChild(QTreeWidgetItem([name]))
        t0.setExpanded(True)
        t1 = QTreeWidgetItem(["TAP1 · PS TAP · 0x14738093"]); tree.addTopLevelItem(t1)
        t1.addChild(QTreeWidgetItem(["PMU MicroBlaze  ▸ BSCAN"]))
        t1.addChild(QTreeWidgetItem(["CSU  0xFFCA0000"]))
        t1.setExpanded(True)
        v.addWidget(tree, 1)
        return p

    def _center_panel(self):
        p = QFrame(); p.setProperty("cls", "panel")
        v = QVBoxLayout(p); v.setContentsMargins(8, 8, 8, 8); v.setSpacing(6)
        tabs = QTabWidget()
        tabs.addTab(self._posture_table(), "⛨  Posture")
        tabs.addTab(QWidget(), "▦  Registers (656)")
        tabs.addTab(QWidget(), "▤  Memory")
        tabs.addTab(QWidget(), "🗎  Report")
        v.addWidget(tabs)
        return p

    def _posture_table(self):
        rows = load_real_posture(ROOT) or POSTURE   # real capture if present, else the canned demo rows
        self._posture_is_real = load_real_posture(ROOT) is not None
        t = QTableWidget(len(rows), 4)
        t.setHorizontalHeaderLabels(["Implementation", "Location", "Value", "State"])
        t.verticalHeader().setVisible(False)
        t.setShowGrid(False)
        t.setSelectionBehavior(QTableWidget.SelectRows)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        hdr = t.horizontalHeader()
        hdr.setSectionResizeMode(0, QHeaderView.Stretch)
        hdr.setSectionResizeMode(1, QHeaderView.ResizeToContents)
        hdr.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        hdr.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        for r, (impl, loc, val, state) in enumerate(rows):
            t.setItem(r, 0, QTableWidgetItem(impl))
            it_loc = QTableWidgetItem(loc); it_loc.setForeground(Qt.gray)
            t.setItem(r, 1, it_loc)
            t.setItem(r, 2, QTableWidgetItem(val))
            txt, fg, bg, br = PILL.get(state, PILL["open"])
            pill = QLabel(txt)
            pill.setAlignment(Qt.AlignCenter)
            pill.setStyleSheet(
                f"color:{fg}; background:{bg}; border:1px solid {br};"
                f"border-radius:11px; padding:2px 9px; font-weight:600; font-size:11px;")
            wrap = QWidget(); wl = QHBoxLayout(wrap)
            wl.setContentsMargins(6, 3, 6, 3); wl.addWidget(pill); wl.addStretch(1)
            t.setCellWidget(r, 3, wrap)
        t.setRowHeight(0, 34)
        return t

    def _caps_panel(self):
        p = QFrame(); p.setProperty("cls", "panel"); p.setFixedWidth(240)
        v = QVBoxLayout(p); v.setContentsMargins(8, 0, 8, 8); v.setSpacing(8)
        v.addWidget(tag("⚡  CAPABILITIES", cls="panelHdr"))
        for kind, title, sub in CAPS:
            c = ClickFrame(lambda t=title, k=kind: self._cap_action(t, k))
            c.setProperty("cls", "cap")
            if kind != "off":
                c.setCursor(Qt.PointingHandCursor)
            ch = QHBoxLayout(c); ch.setContentsMargins(11, 9, 11, 9); ch.setSpacing(10)
            glyph, color = CAPIC[kind]
            ic = QLabel(glyph); ic.setFixedSize(28, 28); ic.setAlignment(Qt.AlignCenter)
            ic.setStyleSheet(f"color:{color}; background:#1a212c; border-radius:9px; font-weight:700;")
            ch.addWidget(ic)
            col = QVBoxLayout(); col.setSpacing(2)
            col.addWidget(tag(title, cls="capTitleOff" if kind == "off" else "capTitle"))
            col.addWidget(tag(sub, cls="capSub"))
            ch.addLayout(col, 1)
            v.addWidget(c)
        v.addStretch(1)
        return p

    def _console_panel(self):
        self.console = QPlainTextEdit(); self.console.setObjectName("console")
        self.console.setReadOnly(True); self.console.setFixedHeight(150)
        self.console.setPlainText("›  ready — click Enumerate to stream OpenOCD I/O")
        return self.console

    # -- streaming (mirrors live OpenOCD stdout via QProcess in the real app)
    def start_enumerate(self):
        if self._enum_btn:
            self._enum_btn.setEnabled(False)
        self.console.clear()
        self.thread_ = QThread(self)
        self.worker = LogWorker()
        self.worker.moveToThread(self.thread_)
        self.thread_.started.connect(self.worker.run)
        self.worker.line.connect(self.append_line)
        self.worker.done.connect(self.thread_.quit)
        self.worker.done.connect(self._on_done)
        self.thread_.start()

    def _on_done(self):
        if self._enum_btn:
            self._enum_btn.setEnabled(True)

    def append_line(self, kind, text):
        color = {"t": "#4d6b7f", "i": "#5bb6f0", "g": "#3ecf8e",
                 "w": "#e7b04b", "d": "#566270"}.get(kind, "#aeb9c7")
        self.console.appendHtml(f'<span style="color:{color}">{text}</span>')

    def _cap_action(self, title, kind):
        # capability card clicked → log the real command to the console (hands-on: no auto-run on the board)
        if title == "Enumerate posture":
            self.start_enumerate(); return
        if kind == "off":
            self.console.appendHtml(f'<span style="color:#e7b04b">✕ {title} — not available on this target</span>')
            return
        cmd = CAP_CMDS.get(title, "(no command wired)")
        self.console.appendHtml(f'<span style="color:#5bb6f0">▶ {title}</span>  '
                                f'<span style="color:#8a97a8">{cmd}</span>')

    def stop(self):
        # stop a streaming worker cleanly so closing mid-stream never crashes
        t = self.thread_
        if t is not None and t.isRunning():
            t.quit()
            t.wait(2000)


# ------------------------------------------------------------------ standalone window
class Main(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("JTAGx — ZCU102 · XCZU9EG")
        self.resize(1180, 760)
        root = QWidget(); root.setObjectName("root")
        root.setAttribute(Qt.WA_StyledBackground, True)   # paint QSS bg on a bare QWidget
        self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(0, 0, 0, 0); outer.setSpacing(0)
        self.dash = Dashboard()

        outer.addWidget(self._topbar())
        body = QHBoxLayout(); body.setContentsMargins(0, 0, 0, 0); body.setSpacing(0)
        body.addWidget(self._rail())
        body.addWidget(self.dash, 1)
        bw = QWidget(); bw.setLayout(body)
        outer.addWidget(bw, 1)
        outer.addWidget(self._statusbar())

    def _topbar(self):
        f = QFrame(); f.setObjectName("topbar"); f.setFixedHeight(52)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(10)
        h.addWidget(tag("◈", "brand"))
        h.addWidget(tag("JTAGx", "brand"))
        h.addWidget(tag("engagement", "brandDim"))
        crumb = QFrame(); crumb.setObjectName("crumb")
        ch = QHBoxLayout(crumb); ch.setContentsMargins(11, 5, 11, 5)
        ch.addWidget(tag("⊕ ZCU102 · XCZU9EG  ·  210308BD8D4D", "crumbTxt"))
        h.addWidget(crumb)
        h.addStretch(1)
        enum = QPushButton("⛨  Enumerate"); enum.setObjectName("enumerate")
        self.dash.set_enum_button(enum)
        dump = QPushButton("⭳ Dump"); dump.setObjectName("ghost")
        h.addWidget(dump)
        h.addWidget(enum)
        h.addWidget(tag("● DAP OPEN", "live"))
        return f

    def _rail(self):
        f = QFrame(); f.setObjectName("rail"); f.setFixedWidth(60)
        v = QVBoxLayout(f); v.setContentsMargins(9, 12, 9, 12); v.setSpacing(6)
        for i, gl in enumerate("▦ ⛓ ⛨ ▤ ⚡ 🗎".split()):
            b = QPushButton(gl); b.setProperty("cls", "railbtn"); b.setCheckable(True)
            b.setChecked(i == 0)
            v.addWidget(b)
        v.addStretch(1)
        g = QPushButton("⚙"); g.setProperty("cls", "railbtn"); v.addWidget(g)
        return f

    def _statusbar(self):
        f = QFrame(); f.setObjectName("statusbar"); f.setFixedHeight(26)
        h = QHBoxLayout(f); h.setContentsMargins(14, 0, 14, 0); h.setSpacing(16)
        for s in ["● Connected", "FT2232H · JTAG · 10 MHz", "chain 2 TAPs",
                  "A53#0 halted @0xFFFF0000"]:
            h.addWidget(tag(s, "statusTxt"))
        h.addStretch(1)
        h.addWidget(tag("raw-20260814-140233.json", "statusTxt"))
        return f

    def closeEvent(self, event):
        self.dash.stop()
        super().closeEvent(event)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyleSheet(QSS)
    w = Main(); w.show()
    sys.exit(app.exec())
