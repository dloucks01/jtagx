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
import re
import sys
from datetime import datetime
from PySide6.QtCore import Qt, Signal, QObject, QRect, QSize, QPoint
from PySide6.QtGui import QFont, QColor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)                                          # repo root (for `import jtagx`)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # gui-spike/ (for proc_runner)
from proc_runner import ProcRunner
from console_bus import BUS                          # app-wide console feed (commands + output)
try:
    from jtagx import paths as jtagx_paths          # writable data-dir resolver (P4)
    ROOT = jtagx_paths.repo_root()
except Exception:
    jtagx_paths = None
try:
    from jtagx.transport import make_transport, detect_adapters   # backend-agnostic transport (P2/P3)
except Exception:
    make_transport = detect_adapters = None
try:
    from jtagx.unlock import security_model as _security_model     # board-generic lock model (posture tab)
except Exception:
    _security_model = None
try:
    from jtagx import attackgraph as _attackgraph                  # kill-chain planner (Kill Chain tab)
    from jtagx.extraction import extraction_plan as _extraction_plan
except Exception:
    _attackgraph = None
    _extraction_plan = None

# capabilities that are OpenOCD-Tcl-specific (no xsdb/hw_server equivalent wired) — gated by backend
OPENOCD_ONLY_CAPS = {"Break & capture", "Live-patch VA→PA", "Dump BootROM", "Dump PMU ROM"}
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton,
    QVBoxLayout, QHBoxLayout, QGridLayout, QTabWidget, QTreeWidget,
    QTreeWidgetItem, QTableWidget, QTableWidgetItem, QPlainTextEdit,
    QHeaderView, QSizePolicy, QMessageBox, QLineEdit, QScrollArea,
    QButtonGroup, QFileDialog, QMenu, QLayout, QSplitter,
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
QFrame#consolePanel { background: #10151d; border: 1px solid #232c39; border-radius: 14px; }
QLabel[cls~="panelHdrInline"] { color: #98a6b8; font-size: 11px; font-weight: 700; letter-spacing: 1px; }
QPushButton[cls~="cfilter"] { background: #141922; color: #98a6b8; border: 1px solid #232c39;
    border-radius: 7px; padding: 3px 10px; font-size: 11px; }
QPushButton[cls~="cfilter"]:hover { border-color: #2c3644; }
QPushButton[cls~="cfilter"]:checked { background: #1e2735; color: #fff; border-color: #3b6ff0; }
QPushButton[cls~="cbtn"] { background: #141922; color: #98a6b8; border: 1px solid #232c39;
    border-radius: 7px; padding: 3px 10px; font-size: 11px; }
QPushButton[cls~="cbtn"]:hover { border-color: #2c3644; color: #cdd7e4; }
QLineEdit[cls~="csearch"] { background: #0b0e14; color: #e7ecf3; border: 1px solid #232c39;
    border-radius: 7px; padding: 3px 8px; font-size: 11px; }
QLineEdit[cls~="csearch"]:focus { border-color: #3b6ff0; }
QLabel[cls~="cprompt"] { color: #3ecf8e; font-family: "DejaVu Sans Mono",monospace; font-weight: 700; }
QLineEdit[cls~="cinput"] { background: #0b0e14; color: #e7ecf3; border: 1px solid #232c39;
    border-radius: 8px; padding: 5px 9px; font-family: "DejaVu Sans Mono",monospace; font-size: 12px; }
QLineEdit[cls~="cinput"]:focus { border-color: #3ecf8e; }
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


def load_registers(root):
    """Newest raw-*.json -> [(block, name, address, value, fields)] sorted by block then address, or [].
    `fields` is the register's decoded bit-fields dict ({name: {bits, value}}) for click-to-decode."""
    try:
        if root not in sys.path:
            sys.path.insert(0, root)
        from jtagx.posture import newest_capture
        p = newest_capture(root)
        if not p:
            return []
        regs = json.load(open(p)).get("registers", {})
        rows = [(r.get("block", ""), r.get("name", ""), r.get("address", addr), r.get("value", ""),
                 r.get("fields", {}))
                for addr, r in regs.items() if isinstance(r, dict)]
        return sorted(rows, key=lambda x: (x[0], x[2]))
    except Exception:
        return []


def _dumps_dir():
    if jtagx_paths is not None:
        try:
            return jtagx_paths.dumps_dir()
        except Exception:
            pass
    return os.path.join(ROOT, "dumps")


def count_dumps():
    """Number of *.bin artifacts currently in the writable dumps dir."""
    try:
        return len(glob.glob(os.path.join(_dumps_dir(), "*.bin")))
    except Exception:
        return 0


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


# ------------------------------------------------------------------ console
LINE_COLOR = {"t": "#4d6b7f", "i": "#5bb6f0", "g": "#3ecf8e", "w": "#e7b04b", "d": "#566270"}

# console slash-commands → a one-line description (the interpreter expands them to real invocations)
SLASH_HELP = [
    ("/help", "list these commands"),
    ("/enumerate", "run the §1–16 enumeration sweep (OpenOCD)"),
    ("/scan", "scan the JTAG chain via the active backend"),
    ("/targets", "xsdb debug-target tree (hw_server backend)"),
    ("/verify", "re-read the access verdict (OPEN / LOCKED)"),
    ("/unlock", "run reopen-debug.tcl (re-open the debug gates)"),
    ("/dump", "/dump <addr> <size> [out] — mem dump via the active backend"),
    ("/posture", "interpret the newest capture → posture summary"),
    ("/report", "generate the engagement report"),
    ("/adapters", "list detected JTAG adapters"),
    ("/backend", "/backend [auto|openocd|hw_server] — show or set the transport"),
    ("/clear", "clear the console"),
]
# backend-aware primitives typed bare (no slash): routed through the selected transport
PRIMITIVES = {"mrd", "mdw", "mww", "mwr", "halt", "run", "scan"}
_SEC_RE = re.compile(r"^#\s+(\d+)\.\s+(.*)")   # enumerate.tcl say_h1 → "# 4. Security State ..."


class _CmdLine(QLineEdit):
    """QLineEdit with ↑/↓ command-history recall for the interactive console."""
    def __init__(self, console):
        super().__init__()
        self._c = console

    def event(self, e):
        # Tab is normally eaten by focus navigation — intercept it here for completion
        from PySide6.QtCore import QEvent
        if e.type() == QEvent.KeyPress and e.key() == Qt.Key_Tab:
            self._c._complete(); return True
        return super().event(e)

    def keyPressEvent(self, e):
        if e.key() == Qt.Key_Up:
            self._c._history_step(-1); return
        if e.key() == Qt.Key_Down:
            self._c._history_step(1); return
        super().keyPressEvent(e)


class FlowLayout(QLayout):
    """A left-to-right layout that WRAPS to the next row when it runs out of width — so the enumerate
    §-section chips stack into a few readable rows instead of one long horizontally-scrolling line."""
    def __init__(self, parent=None, margin=0, spacing=6):
        super().__init__(parent)
        if parent is not None:
            self.setContentsMargins(margin, margin, margin, margin)
        self.setSpacing(spacing)
        self._items = []

    def addItem(self, item):
        self._items.append(item)

    def count(self):
        return len(self._items)

    def itemAt(self, i):
        return self._items[i] if 0 <= i < len(self._items) else None

    def takeAt(self, i):
        return self._items.pop(i) if 0 <= i < len(self._items) else None

    def expandingDirections(self):
        return Qt.Orientations(Qt.Orientation(0))

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        return self._do(QRect(0, 0, width, 0), test=True)

    def setGeometry(self, rect):
        super().setGeometry(rect)
        self._do(rect, test=False)

    def sizeHint(self):
        return self.minimumSize()

    def minimumSize(self):
        s = QSize()
        for it in self._items:
            s = s.expandedTo(it.minimumSize())
        m = self.contentsMargins()
        return s + QSize(m.left() + m.right(), m.top() + m.bottom())

    def _do(self, rect, test):
        x, y, line_h = rect.x(), rect.y(), 0
        sp = self.spacing()
        for it in self._items:
            hint = it.sizeHint()
            nx = x + hint.width() + sp
            if nx - sp > rect.right() and line_h > 0:
                x = rect.x(); y += line_h + sp
                nx = x + hint.width() + sp; line_h = 0
            if not test:
                it.setGeometry(QRect(QPoint(x, y), hint))
            x = nx; line_h = max(line_h, hint.height())
        return y + line_h - rect.y()


class ConsolePanel(QFrame):
    """The app's single interactive console — every tab feeds it via console_bus (commands + output),
    and the operator can type a command/script to run manually. Deepened: kind+text filtering,
    save-to-file, a live §-section summary strip (each `# N. Title` header → a clickable chip), and
    ↑/↓ command history. Owned by the shell (jtagx_app) and always visible below the pages."""

    def __init__(self):
        super().__init__()
        self.setObjectName("consolePanel")
        self._log = []            # [(kind, text, sec_idx)] — full history, filter-independent
        self._sections = []       # [(num, title)]
        self._cur_sec = -1
        self._sec_warn = {}       # sec_idx -> saw a warning line
        self._sec_chip = {}       # sec_idx -> QPushButton
        self._filter_kind = "all"
        self._filter_text = ""
        self._sec_filter = None   # None = all sections; else only this sec_idx

        v = QVBoxLayout(self); v.setContentsMargins(8, 6, 8, 8); v.setSpacing(6)

        # header: collapse toggle + filter chips + search + save/clear
        hdr = QHBoxLayout(); hdr.setSpacing(6)
        self.collapse_btn = QPushButton("▾"); self.collapse_btn.setProperty("cls", "cbtn")
        self.collapse_btn.setFixedWidth(26); self.collapse_btn.setCursor(Qt.PointingHandCursor)
        self.collapse_btn.setToolTip("Collapse / expand the console")
        self.collapse_btn.clicked.connect(self._toggle_collapse)
        hdr.addWidget(self.collapse_btn)
        hdr.addWidget(tag("CONSOLE", cls="panelHdrInline"))
        self._kind_group = QButtonGroup(self); self._kind_group.setExclusive(True)
        for key, label in (("all", "All"), ("info", "Info"), ("warn", "Warn/Err"), ("sections", "§")):
            b = QPushButton(label); b.setCheckable(True); b.setProperty("cls", "cfilter")
            b.setCursor(Qt.PointingHandCursor); b.setChecked(key == "all")
            b.clicked.connect(lambda _=False, k=key: self._set_kind(k))
            self._kind_group.addButton(b); hdr.addWidget(b)
        self.search = QLineEdit(); self.search.setPlaceholderText("filter…"); self.search.setFixedWidth(150)
        self.search.setProperty("cls", "csearch")
        self.search.textChanged.connect(self._set_text)
        hdr.addWidget(self.search)
        hdr.addStretch(1)
        for label, tip, cb in (("⇩ Save", "Save the full log to a file", self._save),
                               ("Clear", "Clear the console", self.clear)):
            b = QPushButton(label); b.setProperty("cls", "cbtn"); b.setCursor(Qt.PointingHandCursor)
            b.setToolTip(tip); b.clicked.connect(cb); hdr.addWidget(b)
        v.addLayout(hdr)

        # the text stream
        self.text = QPlainTextEdit(); self.text.setObjectName("console"); self.text.setReadOnly(True)
        self.text.setMinimumHeight(110)     # a floor; the stream grows when the console is dragged taller
        self.text.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.text.setPlainText("›  ready — every tab feeds this console; type a command below to run it")
        v.addWidget(self.text)

        # live §-section summary strip — chips WRAP into rows (flow layout) instead of one long
        # horizontally-scrolling line; the area grows to ~3 rows then scrolls vertically.
        self.sec_scroll = QScrollArea(); self.sec_scroll.setWidgetResizable(True)
        self.sec_scroll.setMinimumHeight(30); self.sec_scroll.setMaximumHeight(96)
        self.sec_scroll.setFrameShape(QFrame.NoFrame)
        self.sec_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.sec_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.sec_host = QWidget(); self.sec_row = FlowLayout(self.sec_host, margin=2, spacing=5)
        self._sec_hint = tag("§ sections appear here as they stream…", cls="capSub")
        self.sec_row.addWidget(self._sec_hint)
        self.sec_scroll.setWidget(self.sec_host)
        v.addWidget(self.sec_scroll)

        # interactive input row — type a shell command / script and run it (streams back here)
        self.cwd = ROOT
        self._history = []; self._hist_i = 0
        # command-surface config: slash-commands + backend-aware primitives (mrd/halt/scan/…)
        self.soc = "zynqmp"
        self.cfg = "openocd/zcu102.cfg"
        self.backend_getter = lambda: "openocd"     # shell overrides → dash._effective_backend
        self.hooks = {}                              # shell registers: enumerate/report/set_backend/navigate
        self._oc = os.environ.get("OPENOCD", "openocd")   # honor a custom openocd binary path ($OPENOCD)
        irow = QHBoxLayout(); irow.setSpacing(6)
        self._prompt = tag("$", cls="cprompt"); irow.addWidget(self._prompt)
        self.input = _CmdLine(self)
        self.input.setPlaceholderText("/help for commands · mrd/halt/scan route to the backend · or any shell command")
        self.input.setProperty("cls", "cinput")
        self.input.returnPressed.connect(self._run_input)
        irow.addWidget(self.input, 1)
        runb = QPushButton("Run"); runb.setProperty("cls", "cbtn"); runb.setCursor(Qt.PointingHandCursor)
        runb.clicked.connect(self._run_input); irow.addWidget(runb)
        stopb = QPushButton("Stop"); stopb.setProperty("cls", "cbtn"); stopb.setCursor(Qt.PointingHandCursor)
        stopb.setToolTip("Kill the running command"); stopb.clicked.connect(self._stop_input)
        irow.addWidget(stopb)
        v.addLayout(irow)

        # own runner for typed commands; page output arrives via the bus
        self.runner = ProcRunner(self)
        self.runner.line.connect(lambda t: self.append("d", t))
        self.runner.done.connect(lambda c: self.append("g" if c == 0 else "w", f"— exited ({c})"))
        try:
            from console_bus import BUS
            BUS.line.connect(self.append)
            BUS.command.connect(self.echo_cmd)
            BUS.mark.connect(self.mark)
        except Exception:
            pass

    # ---- public API used by the Dashboard ----
    def append(self, kind, text):
        m = _SEC_RE.match(text.strip())
        if m:
            self._start_section(int(m.group(1)), m.group(2).strip())
        sec = self._cur_sec
        self._log.append((kind, text, sec))
        if kind == "w" and sec >= 0 and not self._sec_warn.get(sec):
            self._sec_warn[sec] = True
            self._recolor_chip(sec)
        if self._passes(kind, text, sec):
            self._emit(kind, text)

    def clear(self):
        self._log.clear(); self._sections.clear(); self._sec_warn.clear(); self._sec_chip.clear()
        self._cur_sec = -1; self._sec_filter = None
        self.text.clear()
        while self.sec_row.count():
            it = self.sec_row.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        self._sec_hint = tag("§ sections appear here as they stream…", cls="capSub")
        self.sec_row.addWidget(self._sec_hint)

    def _toggle_collapse(self):
        vis = self.text.isVisible()
        self.text.setVisible(not vis)
        self.sec_scroll.setVisible(not vis)
        self.collapse_btn.setText("▸" if vis else "▾")

    # ---- interactive input + cross-tab feed ----
    def echo_cmd(self, source, cmd):
        """Show a command a page is about to run: 'Unlock $ <cmd>' (as a highlighted line)."""
        self.append("t", f"{source} $ {cmd}" if source else f"$ {cmd}")

    def mark(self, text):
        """A divider line — the shell emits one on every tab switch so the log stays legible."""
        self.append("t", f"────────  {text}")

    def _run_input(self):
        raw = self.input.text().strip()
        if not raw:
            return
        self._history.append(raw); self._hist_i = len(self._history)
        self.input.clear()
        expanded, note = self._interpret(raw)
        if expanded is None:            # handled inline (help / clear / hook / error)
            return
        if self.runner.busy():
            self.append("w", "busy — a command is already running (Stop to cancel)"); return
        if jtagx_paths is not None:
            expanded = jtagx_paths.localize(expanded)     # outputs → writable data-dir when packaged
        if note:
            self.append("i", note)
        self.echo_cmd("you", expanded)
        self.runner.run_shell(expanded, cwd=self.cwd)

    # ---- command interpreter: slash-commands + backend-aware primitives + raw shell ----
    def _interpret(self, cmd):
        """Return (command_to_run, note) or (None, None) if handled inline."""
        head = cmd.split()[0]
        if head.startswith("/"):
            if head.lower() in {s for s, _ in SLASH_HELP}:
                return self._slash(cmd)
            return cmd, None            # an absolute path (e.g. /usr/bin/foo) → raw shell, not a slash-cmd
        if head in PRIMITIVES:
            return self._primitive(cmd)
        return cmd, None                # anything else → raw shell command

    def _transport(self):
        be = "openocd"
        try:
            be = self.backend_getter() or "openocd"
        except Exception:
            pass
        from jtagx.transport import make_transport
        tgt = "a53-0" if be == "hw_server" else ""
        return make_transport(be, cfg=self.cfg, soc=self.soc, target=tgt)

    def _primitive(self, cmd):
        toks = cmd.split()
        head, args = toks[0], toks[1:]
        try:
            t = self._transport()
            if head in ("mrd", "mdw"):
                addr = int(args[0], 0); n = int(args[1], 0) if len(args) > 1 else 1
                c = t.read_words(addr, n)
            elif head in ("mww", "mwr"):
                addr = int(args[0], 0); val = int(args[1], 0)
                c = t.mem_write(addr, val)
            elif head == "halt":
                c = t.halt()
            elif head == "run":
                c = t.run()
            elif head == "scan":
                c = t.scan()
            else:
                return cmd, None
        except (IndexError, ValueError):
            self.append("w", f"usage: {head} <addr> [n]   (numbers accept 0x…)"); return None, None
        sh = c.as_shell()
        if not sh:
            self.append("w", f"{head}: not supported by the {t.backend} backend"); return None, None
        return sh, f"[{t.backend}] {c.desc}"

    def _slash(self, cmd):
        toks = cmd.split()
        name, args = toks[0].lower(), toks[1:]
        if name == "/help":
            self.append("i", "commands:")
            for s, d in SLASH_HELP:
                self.append("t", f"  {s:<11} {d}")
            self.append("t", f"  {'mrd/halt/…':<11} backend primitives (routed to the active transport)")
            self.append("t", f"  {'<anything>':<11} runs as a shell command")
            return None, None
        if name == "/clear":
            self.clear(); return None, None
        if name == "/backend":
            if args and "set_backend" in self.hooks:
                self.hooks["set_backend"](args[0]); self.append("i", f"transport backend → {args[0]}")
            else:
                self.append("i", f"active backend: {self.backend_getter()}"
                                 + (f"  (usage: /backend auto|openocd|hw_server)" if not args else ""))
            return None, None
        if name in ("/enumerate", "/report") and name[1:] in self.hooks:
            self.hooks[name[1:]]()            # use the integrated app flow (refreshes posture/reports)
            return None, None
        # commands that expand to a runnable invocation
        if name == "/enumerate":
            return f'{self._oc} -f {self.cfg} -c "init; source openocd/enumerate.tcl; shutdown"', "enumeration sweep"
        if name == "/scan":
            return self._transport().scan().as_shell(), "chain scan"
        if name == "/targets":
            return (f'python3 tools/transport-probe.py --profile {self.soc} --backend hw_server --targets',
                    "xsdb debug-target tree")
        if name == "/verify":
            return f'{self._oc} -f {self.cfg} -c "init; source openocd/jtag-access-check.tcl; shutdown"', "access verdict"
        if name == "/unlock":
            return f'{self._oc} -f {self.cfg} -c "init; source openocd/reopen-debug.tcl; shutdown"', "reopen debug gates"
        if name == "/dump":
            if len(args) < 2:
                self.append("w", "usage: /dump <addr> <size> [out]"); return None, None
            addr, size = int(args[0], 0), int(args[1], 0)
            out = args[2] if len(args) > 2 else "dumps/console-dump.bin"
            return self._transport().mem_read(addr, size, out).as_shell(), f"dump {size}B @ {hex(addr)} → {out}"
        if name == "/posture":
            return ('python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O', "interpret newest capture")
        if name == "/report":
            return ('python3 tools/engagement-report.py --soc zynqmp --target ZCU102 --jtag-open '
                    '--dumps dumps -o reports/engagement.md', "engagement report")
        if name == "/adapters":
            return "python3 tools/transport-probe.py --list-adapters", "detect adapters"
        self.append("w", f"unknown command {name} — try /help"); return None, None

    def _stop_input(self):
        if self.runner.busy():
            self.runner.stop(); self.append("w", "^C — killed")

    def _history_step(self, d):
        if not self._history:
            return
        self._hist_i = max(0, min(len(self._history), self._hist_i + d))
        self.input.setText(self._history[self._hist_i] if self._hist_i < len(self._history) else "")

    def _complete(self):
        """Tab-complete: the leading word → slash-commands / primitives; a later word → a file path."""
        txt = self.input.text()
        if not txt:
            return
        if " " not in txt:                 # first token: command / primitive completion
            pool = [s for s, _ in SLASH_HELP] if txt.startswith("/") else sorted(PRIMITIVES)
            self._apply_completion("", txt, [p for p in pool if p.startswith(txt)])
        else:                              # later token: filesystem path completion
            head, _, frag = txt.rpartition(" ")
            self._apply_completion(head + " ", frag, self._path_matches(frag))

    def _path_matches(self, frag):
        expo = os.path.expanduser(frag)
        base = expo if (frag.startswith(("/", "~", "."))) else os.path.join(self.cwd, expo)
        out = []
        for m in sorted(glob.glob(base + "*")):
            rel = m if os.path.isabs(frag) or frag.startswith(("~", ".")) else os.path.relpath(m, self.cwd)
            out.append(rel + ("/" if os.path.isdir(m) else ""))
        return out

    def _apply_completion(self, prefix, frag, matches):
        if not matches:
            return
        if len(matches) == 1:
            self.input.setText(prefix + matches[0] + ("" if matches[0].endswith("/") else " "))
        else:
            cp = os.path.commonprefix(matches)
            if cp and cp != frag:
                self.input.setText(prefix + cp)
            self.append("t", "  " + "   ".join(os.path.basename(m.rstrip("/")) or m for m in matches[:16]))

    # ---- sections ----
    def _start_section(self, num, title):
        if self._sec_hint is not None:
            self._sec_hint.setParent(None); self._sec_hint = None
        idx = len(self._sections)
        self._sections.append((num, title))
        self._cur_sec = idx
        short = title[:16].rstrip(" (,-")
        if len(title) > len(short):
            short += "…"
        label = f"§{num} {short}".replace("&", "&&")   # && so Qt doesn't eat & as a mnemonic
        chip = QPushButton(label); chip.setCheckable(True)
        chip.setProperty("cls", "secchip"); chip.setCursor(Qt.PointingHandCursor)
        chip.setToolTip(title)
        chip.clicked.connect(lambda _=False, i=idx: self._toggle_section(i))
        self._sec_chip[idx] = chip
        self.sec_row.addWidget(chip)               # flow layout wraps to the next row as needed
        self._recolor_chip(idx)
        # de-emphasize previous chips (mark them "done")
        for i in range(idx):
            self._recolor_chip(i)
        # keep the newest chip visible (chips wrap downward now)
        self.sec_scroll.verticalScrollBar().setValue(self.sec_scroll.verticalScrollBar().maximum())

    def _recolor_chip(self, idx):
        chip = self._sec_chip.get(idx)
        if not chip:
            return
        current = (idx == self._cur_sec)
        if self._sec_warn.get(idx):
            fg, bg, bd = "#e7b04b", "rgba(231,176,75,0.12)", "rgba(231,176,75,0.4)"
        elif current:
            fg, bg, bd = "#5bb6f0", "rgba(91,182,240,0.14)", "rgba(91,182,240,0.5)"
        else:
            fg, bg, bd = "#8fd39a", "rgba(62,207,142,0.10)", "rgba(62,207,142,0.3)"
        ring = "2px" if chip.isChecked() else "1px"
        chip.setStyleSheet(f"QPushButton{{color:{fg}; background:{bg}; border:{ring} solid {bd};"
                           f"border-radius:9px; padding:2px 9px; font-size:11px; font-weight:600;}}")

    def _toggle_section(self, idx):
        self._sec_filter = None if self._sec_filter == idx else idx
        for i, chip in self._sec_chip.items():
            chip.setChecked(i == self._sec_filter)
            self._recolor_chip(i)
        self._rerender()

    # ---- filtering ----
    def _set_kind(self, k):
        self._filter_kind = k; self._rerender()

    def _set_text(self, t):
        self._filter_text = t.strip().lower(); self._rerender()

    def _passes(self, kind, text, sec):
        if self._sec_filter is not None and sec != self._sec_filter:
            return False
        if self._filter_kind == "info" and kind not in ("i", "g", "t"):
            return False
        if self._filter_kind == "warn" and kind != "w":
            return False
        if self._filter_kind == "sections" and not text.strip().startswith("#"):
            return False
        if self._filter_text and self._filter_text not in text.lower():
            return False
        return True

    def _emit(self, kind, text):
        import html
        color = LINE_COLOR.get(kind, "#aeb9c7")
        self.text.appendHtml(f'<span style="color:{color}">{html.escape(text)}</span>')

    def _rerender(self):
        self.text.clear()
        shown = 0
        for kind, text, sec in self._log:
            if self._passes(kind, text, sec):
                self._emit(kind, text); shown += 1
        if not shown:
            self.text.appendHtml('<span style="color:#566270">— no lines match the current filter —</span>')

    def _save(self):
        if not self._log:
            return
        try:
            default_dir = jtagx_paths.reports_dir() if jtagx_paths else os.path.join(ROOT, "reports")
        except Exception:
            default_dir = ROOT
        default = os.path.join(default_dir, f"console-{datetime.now():%Y%m%d-%H%M%S}.log")
        path, _ = QFileDialog.getSaveFileName(self, "Save console log", default, "Log files (*.log *.txt)")
        if not path:
            return
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(t for _, t, _ in self._log))
        self.append("g", f"— saved {len(self._log)} lines → {path}")


# ------------------------------------------------------------------ posture ring
class RingMeter(QWidget):
    """A small donut showing the hardened-vs-open ratio of the security posture, at a glance.
    All-open dev board → full red ring (0 hardened); a provisioned board fills green."""
    def __init__(self, total=0, hardened=0, size=68):
        super().__init__()
        self._total = total
        self._hardened = hardened
        self.setFixedSize(size, size)

    def set_values(self, total, hardened):
        self._total, self._hardened = total, hardened
        self.update()

    def paintEvent(self, _e):
        from PySide6.QtGui import QPainter, QPen, QColor
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = self.rect().adjusted(7, 7, -7, -7)
        w = 8
        # track
        p.setPen(QPen(QColor("#1c242f"), w))
        p.drawArc(rect, 0, 360 * 16)
        total = max(1, self._total)
        frac = self._hardened / total
        span = int(360 * 16 * frac)
        pen_h = QPen(QColor("#3ecf8e"), w); pen_h.setCapStyle(Qt.RoundCap)
        pen_o = QPen(QColor("#f2685f"), w); pen_o.setCapStyle(Qt.RoundCap)
        # hardened arc from 12 o'clock, clockwise; open arc fills the rest
        if span > 0:
            p.setPen(pen_h); p.drawArc(rect, 90 * 16, -span)
        if span < 360 * 16:
            p.setPen(pen_o); p.drawArc(rect, 90 * 16 - span, -(360 * 16 - span))
        # center: hardened count
        p.setPen(QColor("#e7ecf3"))
        f = self.font(); f.setPointSize(15); f.setBold(True); p.setFont(f)
        p.drawText(rect, Qt.AlignCenter, str(self._hardened))


# ------------------------------------------------------------------ dashboard
class Dashboard(QWidget):
    """The engagement main screen body: target hero + chain/posture/capabilities + streaming console.
    Reusable — both Main (standalone) and jtagx_app embed this under a shared icon rail. The Enumerate
    button lives in the shell's top bar; wire it via set_enum_button()."""

    navigate = Signal(int)          # ask the shell to switch to stack page <idx> (cross-page flow)
    run_in_console = Signal(str)    # ask the shell to put a command in the console input (ready to run)

    def __init__(self):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        self._enum_btn = None
        self._ptable = None
        self._tiles = {}            # label -> the QLabel showing its number (for live updates)
        self._last_cap = None       # title of the last capability run (for the post-run prompt)
        self.backend = "auto"       # transport backend for capability commands (auto/openocd/hw_server)
        self.runner = ProcRunner(self)          # runs real OpenOCD/tools, streams stdout live
        self.runner.line.connect(self._proc_line)
        self.runner.done.connect(self._on_done)
        v = QVBoxLayout(self); v.setContentsMargins(16, 14, 16, 14); v.setSpacing(14)
        v.addLayout(self._hero())
        v.addLayout(self._content(), 1)

    def set_enum_button(self, b):
        self._enum_btn = b
        b.clicked.connect(self.start_enumerate)

    def _hero(self):
        h = QHBoxLayout(); h.setSpacing(12)
        idc = QFrame(); idc.setObjectName("idcard"); idc.setMinimumWidth(250)
        iv = QVBoxLayout(idc); iv.setContentsMargins(16, 14, 16, 14); iv.setSpacing(4)
        iv.addWidget(tag("TARGET", cls="tileLabel"))
        self._hero_board = tag("Zynq UltraScale+", "board"); iv.addWidget(self._hero_board)
        self._hero_chip = tag("XCZU9EG · MPSoC", "chip"); iv.addWidget(self._hero_chip)
        self._hero_access = tag("⛨ Access: OPEN · unprovisioned", "vbadge"); iv.addWidget(self._hero_access)
        self._hero_note = tag("", cls="tileSub"); self._hero_note.setWordWrap(True)
        self._hero_note.setStyleSheet("color:#e7b04b; font-size:10px;"); self._hero_note.hide()
        iv.addWidget(self._hero_note)
        h.addWidget(idc)
        # tiles that navigate somewhere when clicked (dashboard as launchpad)
        tile_go = {"CHAIN": lambda: self.navigate.emit(2),
                   "POSTURE": self._show_posture_tab,
                   "ARTIFACTS": lambda: self.navigate.emit(3)}
        for label, num, sub, color in self._tile_data():
            act = tile_go.get(label)
            c = ClickFrame(act) if act else QFrame()
            c.setProperty("cls", "card")
            if act:
                c.setCursor(Qt.PointingHandCursor)
                c.setToolTip({"CHAIN": "Open the Chain & Transport page",
                              "POSTURE": "Show the posture table",
                              "ARTIFACTS": "Open the Memory / Hex page"}[label])
            cv = QVBoxLayout(c); cv.setContentsMargins(14, 13, 14, 13); cv.setSpacing(5)
            cv.addWidget(tag(label, cls="tileLabel"))
            n = tag(num, cls="tileNum"); n.setStyleSheet(f"color:{color};")
            cv.addWidget(n)
            sub_lbl = tag(sub, cls="tileSub")
            cv.addWidget(sub_lbl)
            self._tiles[label] = (n, sub_lbl)
            h.addWidget(c, 1)
        return h

    def _show_posture_tab(self):
        if getattr(self, "_center_tabs", None) is not None:
            self._center_tabs.setCurrentIndex(0)

    def _rebuild_registers_tab(self):
        """Replace the Registers tab (index 1) with a fresh decode of the newest capture — called after a
        live enumerate so the §1–16 sweep's registers actually appear (the tab is built once at startup)."""
        if getattr(self, "_center_tabs", None) is None:
            return
        regs = load_registers(ROOT)
        w = self._registers_tab(regs)
        self._center_tabs.removeTab(1)
        self._center_tabs.insertTab(1, w, f"▦  Registers ({len(regs)})" if regs else "▦  Registers")

    def _tile_data(self):
        """(label, number, sub, color) for the four hero tiles — computed from real state where we have it.
        For a non-home board (no live ZynqMP capture), the CHAIN/POSTURE tiles read UNKNOWN honestly and
        CAPABILITIES reflects the board's modeled lock mechanisms instead of the ZynqMP capability list."""
        soc = getattr(self, "_board_soc", "zynqmp")
        if soc != "zynqmp":
            locks = len(_security_model(soc)) if _security_model else 0
            return [("CHAIN", "?", "scan to enumerate", "#5b8cff"),
                    ("POSTURE", "?", "UNKNOWN — access-check", "#e7b04b"),
                    ("CAPABILITIES", str(locks), "lock mechanism(s)", "#e7b04b" if locks else "#3ecf8e"),
                    ("ARTIFACTS", str(count_dumps()), "dumps captured", "#98a6b8")]
        rows = load_real_posture(ROOT) or POSTURE
        opens = sum(1 for r in rows if r[3] == "open")
        caps_on = sum(1 for k, *_ in CAPS if k != "off")
        return [("CHAIN", "2", "TAPs · 6 cores", "#5b8cff"),
                ("POSTURE", str(opens), f"open / dev of {len(rows)}", "#f2685f"),
                ("CAPABILITIES", str(caps_on), "available now", "#3ecf8e"),
                ("ARTIFACTS", str(count_dumps()), "dumps captured", "#98a6b8")]

    def refresh_hero(self):
        """Update the hero tile numbers/subs/colour from current state (after enumerate / a dump / a
        board switch)."""
        for label, num, sub, color in self._tile_data():
            if label in self._tiles:
                n, s = self._tiles[label]
                n.setText(num); s.setText(sub); n.setStyleSheet(f"color:{color};")

    def _content(self):
        h = QHBoxLayout(); h.setSpacing(14)
        h.addWidget(self._chain_panel(), 0)
        h.addWidget(self._center_panel(), 1)
        h.addWidget(self._caps_panel(), 0)
        return h

    def _chain_panel(self):
        p = QFrame(); p.setProperty("cls", "panel"); p.setFixedWidth(230)
        self._chain_v = QVBoxLayout(p); self._chain_v.setContentsMargins(0, 0, 0, 8); self._chain_v.setSpacing(0)
        self._fill_chain_panel(getattr(self, "_board_soc", "zynqmp"))
        return p

    def _fill_chain_panel(self, soc):
        """Populate the Dashboard's left chain summary for the active board. ZynqMP shows the real
        2-TAP / 6-core tree (right-click → backend command); other boards redirect to the Chain tab
        (which builds their real per-profile chain) instead of showing the ZynqMP cores."""
        while self._chain_v.count():
            it = self._chain_v.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        self._chain_v.addWidget(tag("⛓  CHAIN & TRANSPORT", cls="panelHdr"))
        if soc != "zynqmp":
            note = QLabel("This board's JTAG chain, access verdict, target tree and adapter × op "
                          "capability matrix are on the Chain tab.")
            note.setWordWrap(True)
            note.setStyleSheet("color:#98a6b8; font-size:11px; padding:12px 12px;")
            self._chain_v.addWidget(note)
            btn = QPushButton("Open Chain tab →"); btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet("QPushButton{background:#141922; color:#98a6b8; border:1px solid #232c39;"
                              "border-radius:8px; padding:6px 10px; margin:0 12px;} "
                              "QPushButton:hover{border-color:#2c3644;}")
            btn.clicked.connect(lambda: self.navigate.emit(2))
            self._chain_v.addWidget(btn)
            self._chain_v.addStretch(1)
            return
        tree = QTreeWidget(); tree.setHeaderHidden(True); tree.setRootIsDecorated(True)
        tree.setToolTip("right-click a core → halt/resume/read via the active backend → console")
        t0 = QTreeWidgetItem(["TAP0 · ARM DAP · 0x5BA00477"]); tree.addTopLevelItem(t0)
        # (label, transport target) — cores carry a target so right-click builds a backend-scoped cmd
        for name, tgt in [("A53 #0  ▸ HALT", "a53-0"), ("A53 #1  ▸ RUN", "a53-1"),
                          ("A53 #2  ▸ RUN", "a53-2"), ("A53 #3  ▸ RUN", "a53-3"),
                          ("R5 #0/#1  ▸ OFF", "r5-0")]:
            it = QTreeWidgetItem([name]); it.setData(0, Qt.UserRole, tgt); t0.addChild(it)
        t0.setExpanded(True)
        t1 = QTreeWidgetItem(["TAP1 · PS TAP · 0x24738093"]); tree.addTopLevelItem(t1)
        for name, tgt in [("PMU MicroBlaze  ▸ BSCAN", "pmu"), ("CSU  0xFFCA0000", "csu")]:
            it = QTreeWidgetItem([name]); it.setData(0, Qt.UserRole, tgt); t1.addChild(it)
        t1.setExpanded(True)
        tree.setContextMenuPolicy(Qt.CustomContextMenu)
        tree.customContextMenuRequested.connect(lambda pos: self._core_menu(tree, pos))
        self._chain_v.addWidget(tree, 1)

    def _core_menu(self, tree, pos):
        it = tree.itemAt(pos)
        tgt = it.data(0, Qt.UserRole) if it else None
        if not tgt:
            return
        m = QMenu(self)
        if tgt == "csu":
            m.addAction("Read IDCODE  (mdw 0xFFCA0040)", lambda: self.run_in_console.emit("mdw 0xFFCA0040 1"))
            m.addAction("Read CSU_STATUS  (mdw 0xFFCA0000)", lambda: self.run_in_console.emit("mdw 0xFFCA0000 1"))
        else:
            m.addAction(f"Halt  ({tgt})", lambda: self._core_cmd(tgt, "halt"))
            m.addAction(f"Resume  ({tgt})", lambda: self._core_cmd(tgt, "run"))
            base = 0xFFD00000 if tgt == "pmu" else 0x00100000
            m.addAction(f"Read  (mdw {hex(base)})", lambda b=base: self._core_cmd(tgt, "read", b))
        m.exec(tree.viewport().mapToGlobal(pos))

    def _core_cmd(self, target, op, addr=0):
        """Build a backend-scoped command for a core and drop it in the console (ready to run)."""
        if make_transport is None:
            return
        be = self._effective_backend()
        t = make_transport(be, cfg="openocd/zcu102.cfg", soc="zynqmp", target=target)
        cmd = {"halt": t.halt, "run": t.run,
               "read": lambda: t.read_words(addr, 4)}.get(op, lambda: None)()
        if cmd and cmd.as_shell():
            self.run_in_console.emit(cmd.as_shell())

    def _center_panel(self):
        p = QFrame(); p.setProperty("cls", "panel")
        v = QVBoxLayout(p); v.setContentsMargins(8, 8, 8, 8); v.setSpacing(6)
        regs = load_registers(ROOT)
        tabs = QTabWidget()
        self._center_tabs = tabs
        tabs.addTab(self._posture_tab(), "⛨  Posture")
        tabs.addTab(self._registers_tab(regs), f"▦  Registers ({len(regs)})" if regs else "▦  Registers")
        tabs.addTab(self._launcher("▤  Memory / Hex viewer",
                    "Browse a DDR/OCM/flash dump byte-for-byte in the virtualized hex view.",
                    "Open Memory page →", 3), "▤  Memory")
        tabs.addTab(self._launcher("🗎  Engagement reports",
                    "Rendered Markdown deliverables (engagement, VxWorks, DRAM secrets, captures).",
                    "Open Reports page →", 4), "🗎  Report")
        tabs.addTab(self._killchain_tab(), "⛓  Kill Chain")            # jtagx.attackgraph planner
        tabs.addTab(self._attack_surface_tab(), "⚗  Attack Surface")   # jtagx.weakness misuse layer
        v.addWidget(tabs)
        return p

    _CLS_CLR = {"design-primitive": "#5aa9e6", "trust-assumption": "#e7b04b", "alternate-master": "#b07de7",
                "asymmetric-protection": "#e7b04b", "volatile-secret": "#e07b53", "thesis": "#3ecf8e"}

    def _misuse_posture(self):
        """Derive the posture dict (jtag_open/secure_boot/aes/efuse) from the real capture rows — honest,
        so the Attack-Surface layer reflects the ACTUAL board, not a hardcoded baseline."""
        P = {}
        real = load_real_posture(ROOT)
        for _impl, _loc, val, state in (real or POSTURE):
            v = val.lower()
            if "dbgen" in v:        P["jtag_open"] = (state == "open")
            elif "jtag_dis" in v:   P["efuse_jtag_dis"] = (state == "hardened")
            elif "rsa_en" in v:     P["secure_boot"] = (state == "hardened")
            elif "boot_enc" in v:   P["aes_encrypt"] = (state == "hardened")
        if real:                    P["_source"] = "capture"   # posture READ from silicon → findings CONFIRMED
        return P

    def _attack_surface_tab(self):
        """The implementation-review misuse layer (jtagx.weakness) for the board + REAL posture: hypotheses
        grouped/badged by class, each with a ▶ probe button that drops its investigation command in the
        console. Not CVEs — where reading the design says it COULD be misused."""
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(8, 8, 8, 8); v.setSpacing(6)
        self._as_hdr = QLabel("ATTACK SURFACE — implementation-review misuse (research, NOT a CVE)")
        self._as_hdr.setStyleSheet("color:#98a6b8; font-size:11px; font-weight:700;")
        self._as_hdr.setWordWrap(True)
        v.addWidget(self._as_hdr)
        # class filter chips
        fbar = QHBoxLayout(); fbar.setSpacing(6)
        self._as_group = QButtonGroup(self); self._as_group.setExclusive(True)
        for key, label in (("all", "All"), ("design-primitive", "primitive"), ("trust-assumption", "trust"),
                           ("alternate-master", "alt-master"), ("volatile-secret", "secret")):
            b = QPushButton(label); b.setCheckable(True); b.setProperty("cls", "cfilter")
            b.setCursor(Qt.PointingHandCursor); b.setChecked(key == "all")
            b.clicked.connect(lambda _=False, k=key: self._filter_attack_surface(k))
            self._as_group.addButton(b); fbar.addWidget(b)
        fbar.addStretch(1)
        self._as_count = QLabel(""); self._as_count.setStyleSheet("color:#5e6b7c; font-size:11px;")
        fbar.addWidget(self._as_count)
        v.addLayout(fbar)
        self._as_scroll = QScrollArea(); self._as_scroll.setWidgetResizable(True); self._as_scroll.setFrameShape(QFrame.NoFrame)
        self._as_host = QWidget(); self._as_v = QVBoxLayout(self._as_host)
        self._as_v.setContentsMargins(2, 2, 2, 8); self._as_v.setSpacing(8)
        self._as_scroll.setWidget(self._as_host); v.addWidget(self._as_scroll, 1)
        foot = QLabel("grows as more silicon is reviewed (jtagx/weakness.py) · ▶ probe sends the investigation "
                      "command to the console · distinct from the CVE matcher")
        foot.setStyleSheet("color:#5e6b7c; font-size:10px;"); foot.setWordWrap(True); v.addWidget(foot)
        self._as_filter = "all"
        self.refresh_attack_surface()
        return w

    def set_board_identity(self, soc, name, paradigm=""):
        """Make the hero identity AND the Posture/Registers tabs follow the selected board (closes the
        board-identity gap: other boards no longer show the ZCU102 capture)."""
        self._board_soc = soc
        if soc == "zynqmp":
            self._hero_board.setText("Zynq UltraScale+")
            self._hero_chip.setText("XCZU9EG · MPSoC")
            self._hero_access.setText("⛨ Access: OPEN · unprovisioned")
            self._hero_note.hide()
        else:
            self._hero_board.setText(name.split("(")[0].split("—")[0].strip() or soc)
            self._hero_chip.setText(f"{soc}" + (f" · Paradigm {paradigm}" if paradigm else ""))
            self._hero_access.setText("⛨ Access: UNKNOWN · run access-check")
            self._hero_note.setText(f"{soc} posture is UNKNOWN until you run access-check (Chain tab). "
                                    "Below is the board's security MODEL + extraction path.")
            self._hero_note.show()
        self._retarget_center_tabs(soc, name, paradigm)
        if hasattr(self, "_chain_v"):
            self._fill_chain_panel(soc)
        if hasattr(self, "_caps_v"):
            self._fill_caps_panel(soc)
        self.refresh_hero()

    def _retarget_center_tabs(self, soc, name, paradigm=""):
        """Swap the Posture (index 0) + Registers (index 1) tabs to match the active board: the real
        ZCU102 capture for zynqmp, or a board-generic security-model view for any other chip."""
        if getattr(self, "_center_tabs", None) is None:
            return
        if soc == "zynqmp":
            posture = self._posture_tab()
            regs = load_registers(ROOT)
            registers = self._registers_tab(regs)
            reg_label = f"▦  Registers ({len(regs)})" if regs else "▦  Registers"
        else:
            posture = self._posture_tab_generic(soc, name, paradigm)
            registers = self._registers_tab_generic(soc, name)
            reg_label = "▦  Registers"
        self._center_tabs.removeTab(0); self._center_tabs.insertTab(0, posture, "⛨  Posture")
        self._center_tabs.removeTab(1); self._center_tabs.insertTab(1, registers, reg_label)
        self._center_tabs.setCurrentIndex(0)

    def _posture_tab_generic(self, soc, name, paradigm=""):
        """Board-generic Posture: the security MODEL (lock mechanisms this silicon can present, from the
        unlock engine) + honest 'posture UNKNOWN' banner, when there's no live capture for this board."""
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(12, 10, 12, 10); v.setSpacing(8)
        head = QLabel(f"SECURITY MODEL — {name}")
        head.setStyleSheet("color:#e7ecf3; font-size:13px; font-weight:700;"); head.setWordWrap(True)
        v.addWidget(head)
        banner = QLabel(f"Posture UNKNOWN — no live capture for {soc}. Run access-check (Chain tab) to read "
                        "the real state. The §1–16 register enumeration is ZynqMP-specific; for other boards "
                        "the lock model below + the Chain capability matrix are the posture view.")
        banner.setWordWrap(True)
        banner.setStyleSheet("color:#0d1017; background:#e7b04b; border-radius:8px; padding:7px 10px; font-size:11px;")
        v.addWidget(banner)
        locks = _security_model(soc) if _security_model else []
        if not locks:
            none = QLabel("No lock mechanism modeled for this part yet — it is treated as open-debug "
                          "(scan + halt + dump once a debugger is attached). See the Chain capability matrix.")
            none.setWordWrap(True); none.setStyleSheet("color:#98a6b8; font-size:12px; padding:6px 2px;")
            v.addWidget(none)
        for L in locks:
            v.addWidget(self._lock_card(L))
        foot = QLabel("→ Unlock tab: the ranked defeat plan (guided reopen→verify)   ·   "
                      "→ Chain tab: adapter × op capability matrix + extraction path   ·   "
                      "→ Attack Surface tab: implementation-review misuse")
        foot.setWordWrap(True); foot.setStyleSheet("color:#5e6b7c; font-size:10px; padding-top:4px;")
        v.addWidget(foot); v.addStretch(1)
        return w

    def _lock_card(self, L):
        """One security-model mechanism: name · enforcement (reversible vs sealed) · runnable-lever badge."""
        card = QFrame(); card.setProperty("cls", "cap")
        cv = QVBoxLayout(card); cv.setContentsMargins(11, 9, 11, 9); cv.setSpacing(3)
        top = QHBoxLayout()
        top.addWidget(tag(L["name"], cls="capTitle"))
        enf = L.get("enforcement", "")
        reversible = any(s.get("cmd") for s in L.get("strategies", []))
        # colour the enforcement by how hard it is to defeat
        low = enf.lower()
        if "efuse" in low or "sealed" in low or "permanent" in low or "hardware" in low:
            ecol = "#f2685f"
        elif "reversible" in low or "register" in low or "downgrad" in low or "glitch" in low:
            ecol = "#e7b04b"
        else:
            ecol = "#98a6b8"
        top.addStretch(1)
        if reversible:
            b = QLabel("runnable lever"); b.setStyleSheet(
                "color:#0d1017; background:#3ecf8e; border-radius:6px; padding:2px 8px; "
                "font-size:10px; font-weight:700;")
            top.addWidget(b)
        cv.addLayout(top)
        e = QLabel(f"enforcement: {enf}"); e.setWordWrap(True)
        e.setStyleSheet(f"color:{ecol}; font-size:11px;")
        cv.addWidget(e)
        # the top-ranked strategy, as the headline defeat move
        strats = L.get("strategies", [])
        if strats:
            s0 = strats[0]
            d = "  ⚠ destructive" if s0.get("destructive") else ""
            hint = QLabel(f"first move: {s0['title']}{d}"); hint.setWordWrap(True)
            hint.setStyleSheet("color:#98a6b8; font-size:11px;")
            cv.addWidget(hint)
        return card

    def _registers_tab_generic(self, soc, name):
        """Non-ZynqMP boards have no §1–16 sweep — say so honestly and point at the real views, instead
        of showing stale ZynqMP registers."""
        body = (f"No register sweep for {name}.\n\n"
                "The §1–16 enumeration (JTAG_SEC / SEC_CTRL / CSU / eFuse …) is ZynqMP-specific — those "
                f"registers don't exist on {soc}. For this board the posture comes from:\n\n"
                "  •  Chain tab — silicon identity, access verdict, and the adapter × op capability matrix\n"
                "  •  Posture tab — the security model (lock mechanisms + enforcement)\n"
                "  •  Unlock tab — the ranked lock-defeat plan\n"
                "  •  Attack Surface tab — implementation-review misuse hypotheses\n\n"
                "Once a debugger is attached and access reads OPEN, use the capability matrix to pick the "
                "extraction path (mem-read / flash dump).")
        return self._launcher(f"▦  Registers — {soc}", body, "Open Chain tab →", 2)

    def set_board_posture(self, soc, P):
        """Retarget the Attack-Surface layer to the active board + its observed posture (from the shell/
        Unlock panel). Makes the misuse layer board-aware, not ZynqMP-only."""
        self._as_soc = soc
        self._as_posture = dict(P or {})
        self.refresh_attack_surface()
        self.refresh_killchain()

    _KC_STATE = {"ACHIEVED": ("#3ecf8e", "✓"), "AVAILABLE": ("#5bb6f0", "▶"),
                 "BLOCKED": ("#f2685f", "✗"), "GATED": ("#7c8898", "…"), "N/A": ("#5e6b7c", "·")}

    def _load_profile(self, soc):
        """Load profiles/<soc>.json (JSONC) so the kill-chain's capability-matrix nodes resolve. Cached."""
        cache = getattr(self, "_prof_cache", None)
        if cache is None:
            cache = self._prof_cache = {}
        if soc in cache:
            return cache[soc]
        import json
        p = os.path.join(ROOT, "profiles", f"{soc}.json")
        prof = None
        try:
            prof = json.loads("".join(ln for ln in open(p, encoding="utf-8")
                                      if not ln.lstrip().startswith(("//", "#"))))
        except Exception:
            prof = None
        cache[soc] = prof
        return prof

    def _killchain_tab(self):
        """The kill-chain planner (jtagx.attackgraph): the ordered objective ladder for the active board +
        posture, each node's state, and its exact next command (▶ runs it in the console)."""
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(8, 8, 8, 8); v.setSpacing(6)
        self._kc_hdr = QLabel("KILL CHAIN — the ordered path for this board + posture")
        self._kc_hdr.setStyleSheet("color:#98a6b8; font-size:11px; font-weight:700;")
        self._kc_hdr.setWordWrap(True)
        v.addWidget(self._kc_hdr)
        self._kc_reach = QLabel(""); self._kc_reach.setWordWrap(True)
        self._kc_reach.setStyleSheet("color:#cdd6e2; font-size:12px;")
        v.addWidget(self._kc_reach)
        self._kc_scroll = QScrollArea(); self._kc_scroll.setWidgetResizable(True)
        self._kc_scroll.setFrameShape(QFrame.NoFrame)
        self._kc_host = QWidget(); self._kc_v = QVBoxLayout(self._kc_host)
        self._kc_v.setContentsMargins(2, 2, 2, 8); self._kc_v.setSpacing(7)
        self._kc_scroll.setWidget(self._kc_host); v.addWidget(self._kc_scroll, 1)
        foot = QLabel("fuses the unlock engine + capability matrix + findings (jtagx.attackgraph) · ▶ runs "
                      "the node's next command in the console · ✗ BLOCKED = only a physical rig continues")
        foot.setStyleSheet("color:#5e6b7c; font-size:10px;"); foot.setWordWrap(True); v.addWidget(foot)
        self.refresh_killchain()
        return w

    def refresh_killchain(self):
        """(Re)build the kill-chain nodes for the active board + posture."""
        if not hasattr(self, "_kc_v") or _attackgraph is None:
            return
        while self._kc_v.count():
            it = self._kc_v.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        soc = getattr(self, "_as_soc", "zynqmp")
        P = getattr(self, "_as_posture", None)
        if P is None:                       # derived from the live capture (zynqmp) → CONFIRMED source
            P = self._misuse_posture() if soc == "zynqmp" else {}
            source = "capture" if (soc == "zynqmp" and getattr(self, "_posture_is_real", False)) else "asserted"
        else:                               # operator-toggled posture (Unlock panel) → ASSERTED
            source = "asserted"
        try:
            g = _attackgraph.plan(soc, P, self._load_profile(soc), source)
        except Exception as e:
            self._kc_reach.setText(f"attack-graph unavailable: {e}")
            return
        _src = "posture CONFIRMED from capture" if g.get("source") == "capture" else "posture ASSERTED (verify on HW)"
        self._kc_reach.setText(f"Reach: {g['depth']}/5 — {g['depth_label']}  ·  {_src}  (non-physical; "
                               "glitch/side-channel/physical deferred)")
        for i, n in enumerate(g["nodes"]):
            col, glyph = self._KC_STATE.get(n["state"], ("#7c8898", "·"))
            card = QFrame(); card.setProperty("cls", "cap")
            cv = QVBoxLayout(card); cv.setContentsMargins(11, 8, 11, 8); cv.setSpacing(3)
            head = QHBoxLayout()
            spine = "↳ branch" if n["id"] == "secure-boot" else f"{i + 1}"
            num = QLabel(spine); num.setStyleSheet("color:#5e6b7c; font:600 11px monospace;")
            num.setFixedWidth(52); head.addWidget(num)
            head.addWidget(tag(n["title"], cls="capTitle"))
            head.addStretch(1)
            st = QLabel(f"{glyph} {n['state']}")
            st.setStyleSheet(f"color:{col}; font-weight:700; font-size:11px;")
            head.addWidget(st)
            if n["state"] == "AVAILABLE" and n.get("action") and not n["action"].lstrip().startswith("#"):
                pb = QPushButton("▶ run"); pb.setProperty("cls", "cbtn"); pb.setCursor(Qt.PointingHandCursor)
                pb.setToolTip(n["action"])
                pb.clicked.connect(lambda _=False, c=n["action"]: self.run_in_console.emit(c))
                head.addWidget(pb)
            cv.addLayout(head)
            if n.get("why"):
                why = QLabel(n["why"]); why.setWordWrap(True)
                why.setStyleSheet("color:#98a6b8; font-size:11px;")
                cv.addWidget(why)
            self._kc_v.addWidget(card)
        # extraction avenues — every real way to get memory/flash off this board, with runnable commands
        if _extraction_plan is not None:
            try:
                ex = _extraction_plan(soc, P, self._load_profile(soc))
            except Exception:
                ex = []
            if ex:
                lbl = QLabel("EXTRACTION AVENUES  ·  best-first  ·  ▶ drops the command in the console")
                lbl.setStyleSheet("color:#98a6b8; font-size:11px; font-weight:700; padding-top:8px;")
                self._kc_v.addWidget(lbl)
                for m in ex:
                    row = QFrame(); row.setProperty("cls", "cap")
                    rv = QVBoxLayout(row); rv.setContentsMargins(11, 7, 11, 7); rv.setSpacing(2)
                    top = QHBoxLayout()
                    gate = m["access"] if m["access"] != "jtag" else "debug-port"
                    top.addWidget(tag(m["method"], cls="capTitle"))
                    gcol = {"jtag": "#5bb6f0", "rom-loader": "#3ecf8e", "readback": "#e7b04b",
                            "chip-off": "#f2685f"}.get(m["access"], "#8a97a8")
                    gl = QLabel(gate + ("  ⚠" if not m["non_destructive"] else ""))
                    gl.setStyleSheet(f"color:{gcol}; font-weight:700; font-size:10px;")
                    top.addStretch(1); top.addWidget(gl)
                    if m.get("cmd") and not m["cmd"].lstrip().startswith("#"):
                        pb = QPushButton("▶ run"); pb.setProperty("cls", "cbtn"); pb.setCursor(Qt.PointingHandCursor)
                        pb.setToolTip(m["cmd"])
                        pb.clicked.connect(lambda _=False, c=m["cmd"]: self.run_in_console.emit(c))
                        top.addWidget(pb)
                    rv.addLayout(top)
                    hy = QLabel(m["how"]); hy.setWordWrap(True); hy.setStyleSheet("color:#98a6b8; font-size:10.5px;")
                    rv.addWidget(hy)
                    self._kc_v.addWidget(row)
        self._kc_v.addStretch(1)
        if hasattr(self, "_kc_hdr"):
            self._kc_hdr.setText(f"KILL CHAIN · {soc.upper()} — the ordered objective ladder for this "
                                 "board + observed posture")

    def refresh_attack_surface(self):
        """(Re)build the cards for the active board (default zynqmp) from its posture — the real capture
        posture for zynqmp, or the shell-supplied observed posture for another board."""
        if not hasattr(self, "_as_v"):
            return
        while self._as_v.count():
            it = self._as_v.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        soc = getattr(self, "_as_soc", "zynqmp")
        P = getattr(self, "_as_posture", None)
        if P is None:
            P = self._misuse_posture() if soc == "zynqmp" else {}
        try:
            from jtagx.weakness import misuse_findings, finding_states
            findings = misuse_findings(soc, P)
            states = finding_states(soc, P)   # honors P["_source"]=="capture" → confirmed
        except Exception:
            findings, states = [], {}
        self._as_findings = findings
        shown = 0
        for cls, sev, txt, hid, probe in findings:
            if self._as_filter != "all" and cls != self._as_filter:
                continue
            shown += 1
            card = QFrame(); card.setProperty("cls", "cap")
            cv = QVBoxLayout(card); cv.setContentsMargins(11, 9, 11, 9); cv.setSpacing(3)
            head = QHBoxLayout()
            badge = QLabel(cls); badge.setStyleSheet(
                f"color:#0d1017; background:{self._CLS_CLR.get(cls,'#7c8898')}; border-radius:6px; "
                "padding:2px 8px; font-size:10px; font-weight:700;")
            head.addWidget(badge)
            head.addWidget(tag(hid, cls="capTitle"))
            sv = QLabel(sev); sv.setStyleSheet(
                f"color:{'#f2685f' if sev == 'HIGH' else '#e7b04b'}; font-weight:700; font-size:11px;")
            head.addWidget(sv)
            confirmed = states.get(hid, {}).get("state") == "confirmed"
            stp = QLabel("confirmed" if confirmed else "asserted")
            stp.setToolTip("posture READ from a live capture" if confirmed
                           else "predicted from the supplied/derived posture — verify on hardware")
            stp.setStyleSheet(
                ("color:#0d1017; background:#5cc98f;" if confirmed else "color:#8fa0b4; border:1px solid #33404f;")
                + " border-radius:6px; padding:1px 7px; font-size:9px; font-weight:700; margin-left:5px;")
            head.addWidget(stp); head.addStretch(1)
            if probe:
                pb = QPushButton("▶ probe"); pb.setProperty("cls", "cbtn"); pb.setCursor(Qt.PointingHandCursor)
                pb.setToolTip(probe); pb.clicked.connect(lambda _=False, c=probe: self.run_in_console.emit(c))
                head.addWidget(pb)
            cv.addLayout(head)
            body = QLabel(txt); body.setWordWrap(True); body.setStyleSheet("color:#98a6b8; font-size:11px;")
            cv.addWidget(body)
            self._as_v.addWidget(card)
        self._as_v.addStretch(1)
        self._as_count.setText(f"{soc} · {shown} / {len(findings)} hypotheses")
        if hasattr(self, "_as_hdr"):
            self._as_hdr.setText(f"ATTACK SURFACE · {soc.upper()} — only hypotheses that apply to this "
                                 "chip + its observed posture (research, NOT a CVE)")
        if not findings and hasattr(self, "_as_v"):
            empty = QLabel(f"No implementation-review hypotheses fire for {soc} at its current posture — "
                           "a locked/provisioned board closes most of this surface.")
            empty.setWordWrap(True); empty.setStyleSheet("color:#5e6b7c; font-size:11px; padding:8px;")
            self._as_v.insertWidget(0, empty)

    def _filter_attack_surface(self, cls):
        self._as_filter = cls
        self.refresh_attack_surface()

    # security-relevant register blocks (for the "security only" quick-filter)
    _SEC_BLOCKS = {"CSU", "EFUSE", "BBRAM", "PMU_GLOBAL"}

    def _registers_tab(self, regs):
        if not regs:
            return self._launcher("▦  Register sweep",
                "No capture yet. Run Enumerate to sweep §1–16 into a raw JSON, then the decoded "
                "registers (block · name · address · value) appear here.", "Run Enumerate", None,
                on_click=self.start_enumerate)
        self._regs = regs
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(2, 4, 2, 2); v.setSpacing(6)
        # search + security filter
        bar = QHBoxLayout(); bar.setSpacing(8)
        self._reg_search = QLineEdit(); self._reg_search.setPlaceholderText("filter registers — name / block / address / value…")
        self._reg_search.setProperty("cls", "csearch")
        self._reg_search.textChanged.connect(self._filter_registers)
        bar.addWidget(self._reg_search, 1)
        self._reg_sec = QPushButton("🔒 security only"); self._reg_sec.setCheckable(True)
        self._reg_sec.setProperty("cls", "cfilter"); self._reg_sec.setCursor(Qt.PointingHandCursor)
        self._reg_sec.toggled.connect(self._filter_registers)
        bar.addWidget(self._reg_sec)
        self._reg_count = tag("", cls="capSub"); bar.addWidget(self._reg_count)
        v.addLayout(bar)

        t = QTableWidget(len(regs), 4)
        t.setHorizontalHeaderLabels(["Block", "Register", "Address", "Value"])
        t.verticalHeader().setVisible(False); t.setShowGrid(False)
        t.setSelectionBehavior(QTableWidget.SelectRows); t.setEditTriggers(QTableWidget.NoEditTriggers)
        hdr = t.horizontalHeader()
        hdr.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        hdr.setSectionResizeMode(1, QHeaderView.Stretch)
        hdr.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        hdr.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        mono = QFont("DejaVu Sans Mono", 9)
        for r, (block, name, addr, val, _flds) in enumerate(regs):
            bi = QTableWidgetItem(block); bi.setForeground(Qt.gray)
            t.setItem(r, 0, bi)
            t.setItem(r, 1, QTableWidgetItem(name))
            ai = QTableWidgetItem(addr); ai.setForeground(QColor("#7c8898")); ai.setFont(mono)
            t.setItem(r, 2, ai)
            vi = QTableWidgetItem(val); vi.setFont(mono); vi.setForeground(QColor("#33d6c4"))
            t.setItem(r, 3, vi)
        t.currentCellChanged.connect(lambda cr, *_: self._show_reg_fields(cr))
        t.setContextMenuPolicy(Qt.CustomContextMenu)
        t.customContextMenuRequested.connect(self._reg_context_menu)
        self._reg_table = t
        v.addWidget(t, 1)

        # field-decode detail for the selected register
        self._reg_detail = QLabel("select a register to decode its bit-fields")
        self._reg_detail.setWordWrap(True)
        self._reg_detail.setStyleSheet("color:#98a6b8; font-size:11px; background:#0e131b;"
                                       "border:1px solid #232c39; border-radius:8px; padding:8px 10px;")
        self._reg_detail.setTextInteractionFlags(Qt.TextSelectableByMouse)
        v.addWidget(self._reg_detail)
        self._filter_registers()
        return w

    def _filter_registers(self, *_):
        q = self._reg_search.text().strip().lower()
        sec = self._reg_sec.isChecked()
        shown = 0
        for r, (block, name, addr, val, _flds) in enumerate(self._regs):
            hay = f"{block} {name} {addr} {val}".lower()
            ok = (not q or q in hay) and (not sec or block in self._SEC_BLOCKS)
            self._reg_table.setRowHidden(r, not ok)
            shown += ok
        self._reg_count.setText(f"{shown} / {len(self._regs)}")

    def _reg_context_menu(self, pos):
        row = self._reg_table.rowAt(pos.y())
        if row < 0 or row >= len(self._regs):
            return
        block, name, addr, val, _flds = self._regs[row]
        m = QMenu(self)
        cp = lambda s: (lambda: QApplication.clipboard().setText(s))
        m.addAction(f"Copy  {block}.{name}", cp(f"{block}.{name}"))
        m.addAction(f"Copy address  {addr}", cp(str(addr)))
        m.addAction(f"Copy value  {val}", cp(str(val)))
        m.addAction(f"Copy  {name} = {val}", cp(f"{name} = {val}"))
        m.addAction(f"Copy  #define {name} {addr}", cp(f"#define {name} {addr}"))
        m.addSeparator()
        m.addAction(f"Send  mrd {addr}  to console", lambda: self.run_in_console.emit(f"mrd {addr} 1"))
        m.exec(self._reg_table.viewport().mapToGlobal(pos))

    def _show_reg_fields(self, row):
        if row is None or row < 0 or row >= len(self._regs):
            return
        block, name, addr, val, flds = self._regs[row]
        head = f"<b>{block}.{name}</b>  <span style='color:#7c8898'>{addr}</span> = <span style='color:#33d6c4'>{val}</span>"
        if not flds:
            self._reg_detail.setText(head + "  <span style='color:#5e6b7c'>(no decoded fields)</span>")
            return
        parts = []
        for fname, fd in flds.items():
            bits = fd.get("bits", "?") if isinstance(fd, dict) else "?"
            fv = fd.get("value", fd) if isinstance(fd, dict) else fd
            parts.append(f"<span style='color:#cdd7e4'>{fname}</span>"
                         f"<span style='color:#5e6b7c'>[{bits}]</span>=<span style='color:#e7b04b'>{fv}</span>")
        self._reg_detail.setText(head + "<br>" + " &nbsp; ".join(parts))

    def _launcher(self, title, body, btn_text, page_idx, on_click=None):
        """A friendly panel with a call-to-action — fills a tab that would otherwise be blank and
        routes the operator to the full page (cross-page flow) or runs an action."""
        w = QWidget(); lay = QVBoxLayout(w); lay.setContentsMargins(24, 22, 24, 22); lay.setSpacing(10)
        lay.addStretch(1)
        lay.addWidget(tag(title, cls="capTitle"))
        b = QLabel(body); b.setWordWrap(True); b.setStyleSheet("color:#98a6b8; font-size:12px;")
        lay.addWidget(b)
        btn = QPushButton(btn_text); btn.setObjectName("ghost"); btn.setCursor(Qt.PointingHandCursor)
        btn.setFixedWidth(220)
        btn.clicked.connect(on_click if on_click else (lambda: self.navigate.emit(page_idx)))
        lay.addWidget(btn)
        lay.addStretch(1)
        return w

    def _posture_tab(self):
        """Posture table + an at-a-glance hardened/open ring summary above it."""
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(4, 6, 4, 4); v.setSpacing(6)
        row = QHBoxLayout(); row.setContentsMargins(8, 0, 8, 0); row.setSpacing(14)
        self._ring = RingMeter()
        row.addWidget(self._ring)
        leg = QVBoxLayout(); leg.setSpacing(2)
        self._ring_head = tag("", cls="capTitle")
        self._ring_sub = tag("", cls="capSub")
        leg.addWidget(self._ring_head); leg.addWidget(self._ring_sub)
        row.addLayout(leg); row.addStretch(1)
        v.addLayout(row)
        v.addWidget(self._posture_table(), 1)
        self._update_ring(load_real_posture(ROOT) or POSTURE)
        return w

    def _update_ring(self, rows):
        hardened = sum(1 for r in rows if r[3] == "hardened")
        opens = sum(1 for r in rows if r[3] == "open")
        total = hardened + opens
        if getattr(self, "_ring", None) is not None:
            self._ring.set_values(total, hardened)
            self._ring_head.setText(f"{hardened} hardened / {total} security implementations")
            real = getattr(self, "_posture_is_real", False)
            if not real:
                self._ring_sub.setText("demo baseline — run Enumerate to read live posture")
            else:
                self._ring_sub.setText(f"{opens} open · dev-unprovisioned"
                                       + ("  —  wide open" if hardened == 0 else ""))

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
        hdr.setSectionResizeMode(3, QHeaderView.Fixed); t.setColumnWidth(3, 108)
        t.cellClicked.connect(self._posture_to_register)   # click a posture row → its register decode
        self._ptable = t
        self._fill_posture(t, rows)
        return t

    def _posture_to_register(self, row, _col):
        """Jump from a posture row to that register in the Registers tab (with its fields decoded)."""
        if not getattr(self, "_posture_is_real", False) or not getattr(self, "_reg_table", None):
            return
        it = self._ptable.item(row, 1)          # the Location column = register name
        if it is None:
            return
        loc = it.text().strip()
        idx = next((i for i, r in enumerate(self._regs) if r[1] == loc), None)
        if idx is None:
            return
        self._center_tabs.setCurrentIndex(1)    # Registers tab
        self._reg_sec.setChecked(False)
        self._reg_search.setText(loc)           # filter to it
        self._reg_table.setCurrentCell(idx, 0)  # select → triggers the field decode

    def _fill_posture(self, t, rows):
        t.setRowCount(len(rows))
        for r, (impl, loc, val, state) in enumerate(rows):
            t.setItem(r, 0, QTableWidgetItem(impl))
            it_loc = QTableWidgetItem(loc); it_loc.setForeground(Qt.gray)
            t.setItem(r, 1, it_loc)
            t.setItem(r, 2, QTableWidgetItem(val))
            txt, fg, bg, br = PILL.get(state, PILL["open"])
            pill = QLabel(txt); pill.setAlignment(Qt.AlignCenter)
            pill.setMinimumWidth(84)        # keep "● hardened" from truncating to "● harden"
            pill.setStyleSheet(
                f"color:{fg}; background:{bg}; border:1px solid {br};"
                f"border-radius:11px; padding:2px 9px; font-weight:600; font-size:11px;")
            wrap = QWidget(); wl = QHBoxLayout(wrap)
            wl.setContentsMargins(6, 3, 6, 3); wl.addWidget(pill); wl.addStretch(1)
            t.setCellWidget(r, 3, wrap)
        if t.rowCount():
            t.setRowHeight(0, 34)

    def refresh_posture(self):
        """re-read the newest capture into the posture table (called after a live enumerate finishes)."""
        if self._ptable is not None:
            real = load_real_posture(ROOT)
            rows = real or POSTURE
            self._posture_is_real = real is not None
            self._fill_posture(self._ptable, rows)
            self._update_ring(rows)
            self.refresh_attack_surface()   # the misuse layer follows the live posture
            self.refresh_killchain()        # and so does the kill-chain planner

    def _caps_panel(self):
        p = QFrame(); p.setProperty("cls", "panel"); p.setFixedWidth(240)
        self._caps_v = QVBoxLayout(p); self._caps_v.setContentsMargins(8, 0, 8, 8); self._caps_v.setSpacing(8)
        self._fill_caps_panel(getattr(self, "_board_soc", "zynqmp"))
        return p

    def _fill_caps_panel(self, soc):
        """The ZynqMP capability cards (Enumerate/Dump/Break/Patch/…) are ZynqMP-specific flows. For
        another board, show its extraction path from the security model + point at the capability matrix,
        rather than offering ZynqMP-only actions that wouldn't run."""
        while self._caps_v.count():
            it = self._caps_v.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        self._caps_v.addWidget(tag("⚡  CAPABILITIES", cls="panelHdr"))
        if soc != "zynqmp":
            locks = _security_model(soc) if _security_model else []
            reversible = sum(1 for L in locks if any(s.get("cmd") for s in L.get("strategies", [])))
            msg = QLabel(
                (f"{len(locks)} lock mechanism(s) modeled for {soc}"
                 + (f", {reversible} with a runnable reopen lever.\n\n" if locks else ".\n\n"))
                + "Capabilities here are board-specific:\n"
                  "  •  Unlock tab — run the guided reopen→verify lock-defeat\n"
                  "  •  Chain tab — the adapter × op capability matrix picks the extraction path\n"
                  "  •  Attack Surface tab — implementation-review misuse")
            msg.setWordWrap(True); msg.setStyleSheet("color:#98a6b8; font-size:11px; padding:10px 6px;")
            self._caps_v.addWidget(msg)
            for label, idx in (("Open Unlock tab →", 1), ("Open Chain tab →", 2)):
                b = QPushButton(label); b.setCursor(Qt.PointingHandCursor)
                b.setStyleSheet("QPushButton{background:#141922; color:#98a6b8; border:1px solid #232c39;"
                                "border-radius:8px; padding:6px 10px;} QPushButton:hover{border-color:#2c3644;}")
                b.clicked.connect(lambda _=False, i=idx: self.navigate.emit(i))
                self._caps_v.addWidget(b)
            self._caps_v.addStretch(1)
            return
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
            self._caps_v.addWidget(c)
        self._caps_v.addStretch(1)


    # -- streaming: run the real OpenOCD/tool via QProcess, stream stdout live, refresh from the result
    def start_enumerate(self):
        if self.runner.busy():
            return
        self.navigate.emit(0)           # bring the operator to the Dashboard to watch the live stream
        if self._enum_btn:
            self._enum_btn.setEnabled(False)
        cmd = "init; source openocd/enumerate.tcl; shutdown"
        self._last_was_enum = True
        BUS.mark.emit("enumerate")
        BUS.command.emit("Dashboard", f'openocd -f openocd/zcu102.cfg -c "{cmd}"')
        self.runner.run(["openocd", "-f", "openocd/zcu102.cfg", "-c", cmd], cwd=ROOT)

    def _on_done(self, code=0):
        if self._enum_btn:
            self._enum_btn.setEnabled(True)
        self.append_line("g" if code == 0 else "w", f"— process exited ({code})")
        self.refresh_posture()          # reflect any fresh capture in the posture table
        self.refresh_hero()             # update the hero counters (posture opens, artifacts)
        # cross-page flow: an enumerate decoded a fresh capture — land the operator on the results
        if code == 0 and getattr(self, "_last_was_enum", False):
            self._rebuild_registers_tab()   # the §1–16 sweep populated the Registers tab
            self._show_posture_tab()        # switch the center tabs to the decoded Posture
            self.append_line("g", "✓ Enumeration decoded → Posture & Registers tabs (this panel); "
                                  "full §1–16 report on the Reports page.")
        self._last_was_enum = False
        # cross-page flow: a successful dump produced a new artifact — offer to open it in Memory
        if code == 0 and self._last_cap and self._last_cap.startswith("Dump"):
            cap = self._last_cap
            if QMessageBox.question(self, "Dump complete",
                                    f"“{cap}” finished. Open the new artifact in the Memory / Hex view?",
                                    QMessageBox.StandardButton.Open | QMessageBox.StandardButton.Cancel,
                                    QMessageBox.StandardButton.Open) == QMessageBox.StandardButton.Open:
                self.navigate.emit(3)
        self._last_cap = None

    def _proc_line(self, text):
        low = text.lower()
        kind = "w" if ("error" in low or "fail" in low) else ("i" if text.startswith("Info") else "d")
        self.append_line(kind, text)

    def append_line(self, kind, text):
        BUS.line.emit(kind, text)           # → the shell-level console (console_bus)

    # -- transport backend selection (P2/P3): route capability commands through the chosen backend --
    def set_backend(self, name):
        self.backend = name       # "auto" | "openocd" | "hw_server"

    def _effective_backend(self):
        """Resolve 'auto' to a concrete backend from what's plugged in (prefers OpenOCD)."""
        if self.backend != "auto":
            return self.backend
        if detect_adapters:
            try:
                backends = {c["backend"] for c in detect_adapters()}
            except Exception:
                backends = set()
            if "openocd" in backends:
                return "openocd"
            if "hw_server" in backends:
                return "hw_server"
        return "openocd"

    def _resolve_cap_cmd(self, title):
        """(cmd, blocked_reason) for a capability under the active backend.
        Dump DDR/OCM maps to a transport mem-read (xsdb on hw_server); OpenOCD-Tcl-only caps are
        gated when a non-OpenOCD backend is active (the SmartLynq2 engagement reality)."""
        be = self._effective_backend()
        if title == "Dump DDR / OCM" and be == "hw_server" and make_transport is not None:
            cfg = "openocd/zcu102.cfg"
            t = make_transport("hw_server", cfg=cfg, soc="zynqmp", target="a53-0")
            return t.mem_read(0x00100000, 0x01000000, "dumps/os-live.bin").as_shell(), None
        if title in OPENOCD_ONLY_CAPS and be != "openocd":
            return None, (f"{title} uses an OpenOCD Tcl script; active transport is “{be}”. "
                          "Bridge the adapter to OpenOCD (Chain ▸ XVC) or set Transport = OpenOCD.")
        return CAP_CMDS.get(title, ""), None

    def _cap_action(self, title, kind):
        # capability card clicked → RUN the real command (operator-driven), or copy if it needs a VA/symbol
        if title == "Enumerate posture":
            be = self._effective_backend()
            if be != "openocd":
                self.append_line("w", f"✕ Enumerate needs the OpenOCD backend (enumerate.tcl); active "
                                 f"transport is “{be}”. Bridge via XVC (Chain page) or set Transport = OpenOCD.")
                return
            self.start_enumerate(); return
        if kind == "off":
            self.append_line("w", f"✕ {title} — not available on this target"); return
        cmd, blocked = self._resolve_cap_cmd(title)
        if blocked:
            self.append_line("w", f"✕ {blocked}"); return
        if not cmd or "<" in cmd:        # placeholder (needs a VA/fn) → copy, don't run blind
            QApplication.clipboard().setText(cmd or "")
            self.append_line("i", f"⧉ copied (fill in the VA/symbol, then run): {cmd}"); return
        # confirm gate for ops that halt the running OS or otherwise disrupt the live target
        WARN = {
            "Dump DDR / OCM": "This HALTS the running OS on the target (DUMP_HALT=1) to read DRAM "
                              "coherently. The board will stop executing until the dump finishes.",
        }
        if title in WARN:
            r = QMessageBox.warning(self, f"Confirm — {title}",
                                    WARN[title] + "\n\nProceed?",
                                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                                    QMessageBox.StandardButton.Cancel)
            if r != QMessageBox.StandardButton.Yes:
                self.append_line("w", f"✕ cancelled: {title}"); return
        if self.runner.busy():
            self.append_line("w", "busy — a process is already running"); return
        if jtagx_paths is not None:
            cmd = jtagx_paths.localize(cmd)     # outputs -> writable data-dir when packaged (no-op in dev)
        self._last_cap = title                 # remembered for the post-run "open in Memory?" prompt
        BUS.command.emit("Dashboard", cmd)
        self.runner.run_shell(cmd, cwd=ROOT)

    def stop(self):
        self.runner.stop()


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
