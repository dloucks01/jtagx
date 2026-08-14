#!/usr/bin/env python3
"""
unlock_panel.py — GUI spike: the flagship "Reopen / Unlock" panel (Phase-2b).

Renders tools/unlock-engine.py's --json plan as enforcement-classified lock cards with a ranked,
tagged strategy list. This is the operator-facing surface for the locked-board workflow (the core
mission): verdict + posture in → "here's what's locked, how it's enforced, and the ordered ways to
defeat it," AUTO software levers first.

Run:  pip install PySide6  &&  python3 gui-spike/unlock_panel.py
It shells `python3 tools/unlock-engine.py <args> --json` (the GUI drives the real tool). The scenario
buttons across the top swap the posture so you can see the same closed DAP produce a software-lever
plan (register-gated) vs a hardware-only plan (eFuse-sealed). "Run"/"Copy"/"Guide" are demo actions —
in the real app the AUTO levers execute reopen-debug.tcl and re-read the access verdict.

Note: live JTAG actions stay operator-driven — "Run" here logs the exact command rather than touching
the board (matches the project's hands-on model).
"""
import json, os, subprocess, sys
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton, QVBoxLayout,
    QHBoxLayout, QScrollArea, QPlainTextEdit, QSizePolicy,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UE = os.path.join(ROOT, "tools", "unlock-engine.py")

KIND_TAG = {"software-lever": "AUTO", "misconfig": "AUTO", "alternate-path": "SCRIPT",
            "physical-offline": "MANUAL", "firmware-attack": "OFFLINE",
            "fault-injection": "HARDWARE", "side-channel": "HARDWARE"}
TAG_COLOR = {"AUTO": "#3ecf8e", "SCRIPT": "#5b8cff", "MANUAL": "#e7b04b",
             "OFFLINE": "#b58bff", "HARDWARE": "#f2685f"}
ACTION = {"software-lever": "▶ Run", "misconfig": "▶ Run", "alternate-path": "⧉ Copy",
          "firmware-attack": "⧉ Copy", "physical-offline": "≡ Guide",
          "fault-injection": "≡ Guide", "side-channel": "≡ Guide"}

SCENARIOS = [  # (label, unlock-engine args)
    ("Open (from capture)", None),   # filled at runtime with the newest raw-*.json
    ("Register-gated", ["--soc", "zynqmp", "--jtag-locked", "--no-efuse-jtag-dis"]),
    ("eFuse-sealed", ["--soc", "zynqmp", "--jtag-locked", "--efuse-jtag-dis"]),
    ("Hardened", ["--soc", "zynqmp", "--jtag-locked", "--efuse-jtag-dis",
                  "--secure-boot", "on", "--aes-encrypt", "--dap-ns-locked"]),
    ("nRF52 APPROTECT", ["--soc", "nrf52", "--approtect-locked"]),
]


def enf_color(enf):
    e = (enf or "").lower()
    if "reversible" in e:
        return "#3ecf8e"      # green — easy win
    if "unknown" in e:
        return "#e7b04b"      # amber — read SEC_CTRL to classify
    if "hardware" in e or "efuse" in e or "bbram" in e or "bootrom" in e:
        return "#f2685f"      # red — hard
    return "#98a6b8"


def run_unlock(args):
    try:
        r = subprocess.run([sys.executable, UE, *args, "--json"],
                           capture_output=True, text=True, timeout=30)
        return json.loads(r.stdout or "{}")
    except Exception as e:
        return {"error": str(e), "soc": "?", "posture": {}, "locks": []}


QSS = """
* { color:#e7ecf3; font-family:"Inter","Segoe UI","Noto Sans",sans-serif; font-size:13px; }
QWidget#root, QScrollArea, QScrollArea > QWidget > QWidget { background:#0d1017; }
QFrame#topbar { background:#0f141c; border-bottom:1px solid #1c242f; }
QLabel#title { font-size:15px; font-weight:700; }
QLabel#sub { color:#98a6b8; }
QPushButton[cls~="scn"] { background:#141922; color:#ccd6e2; border:1px solid #232c39;
    border-radius:8px; padding:6px 12px; }
QPushButton[cls~="scn"]:hover { border-color:#2c3644; }
QPushButton[cls~="scn"]:checked { background:#1e2735; color:#fff; border-color:#3b6ff0; }
QLabel#summary { font-size:13px; padding:10px 16px; }
QFrame[cls~="card"] { background:#141922; border:1px solid #232c39; border-radius:12px; }
QLabel[cls~="lockname"] { font-size:14px; font-weight:600; }
QLabel[cls~="statepill"] { border-radius:10px; padding:2px 9px; font-size:11px; font-weight:700; }
QLabel[cls~="enf"] { font-size:11.5px; }
QFrame[cls~="srow"] { background:#0f141c; border:1px solid #1c242f; border-radius:9px; }
QLabel[cls~="tag"] { border-radius:6px; padding:2px 7px; font-size:10px; font-weight:800; }
QLabel[cls~="stitle"] { font-weight:600; }
QLabel[cls~="show"] { color:#8a97a8; font-size:11px; }
QLabel[cls~="conf"] { color:#6f7c8c; font-size:10.5px; }
QLabel[cls~="destr"] { color:#f2685f; font-size:10px; font-weight:700; }
QPushButton[cls~="act"] { background:#1a2230; color:#cdd7e4; border:1px solid #2c3644;
    border-radius:7px; padding:5px 12px; }
QPushButton[cls~="act"]:hover { background:#222d3d; }
QPlainTextEdit#log { background:#090c11; border:1px solid #232c39; border-radius:10px;
    color:#aeb9c7; font-family:"DejaVu Sans Mono",monospace; font-size:11.5px; padding:6px; }
QScrollBar:vertical { background:transparent; width:10px; margin:2px; }
QScrollBar::handle:vertical { background:#2c3644; border-radius:5px; min-height:24px; }
QScrollBar::add-line, QScrollBar::sub-line { height:0; }
"""


def _lbl(text, cls=None, obj=None, color=None):
    x = QLabel(text)
    if cls: x.setProperty("cls", cls)
    if obj: x.setObjectName(obj)
    if color: x.setStyleSheet(f"color:{color};")
    return x


class StrategyRow(QFrame):
    def __init__(self, strat, on_action):
        super().__init__()
        self.setProperty("cls", "srow")
        self.strat = strat
        tag = KIND_TAG.get(strat["kind"], "?")
        h = QHBoxLayout(self); h.setContentsMargins(10, 8, 10, 8); h.setSpacing(10)
        tg = _lbl(tag, cls="tag")
        c = TAG_COLOR.get(tag, "#98a6b8")
        tg.setStyleSheet(f"color:#0d1017; background:{c}; border-radius:6px; padding:2px 7px; font-weight:800;")
        tg.setAlignment(Qt.AlignCenter); tg.setFixedWidth(72)
        h.addWidget(tg, 0, Qt.AlignTop)
        col = QVBoxLayout(); col.setSpacing(2)
        top = QHBoxLayout(); top.setSpacing(8)
        top.addWidget(_lbl(strat["title"], cls="stitle"))
        top.addWidget(_lbl(f"· {strat['confidence']} confidence", cls="conf"))
        if strat.get("destructive"):
            top.addWidget(_lbl("⚠ DESTRUCTIVE", cls="destr"))
        top.addStretch(1)
        col.addLayout(top)
        how = _lbl(strat["how"], cls="show"); how.setWordWrap(True)
        col.addWidget(how)
        if strat.get("prereq"):
            col.addWidget(_lbl(f"prereq: {strat['prereq']}", cls="conf"))
        h.addLayout(col, 1)
        btn = QPushButton(ACTION.get(strat["kind"], "…")); btn.setProperty("cls", "act")
        btn.clicked.connect(lambda: on_action(strat))
        h.addWidget(btn, 0, Qt.AlignTop)


class LockCard(QFrame):
    def __init__(self, lock, on_action):
        super().__init__()
        self.setProperty("cls", "card")
        v = QVBoxLayout(self); v.setContentsMargins(14, 12, 14, 12); v.setSpacing(8)
        head = QHBoxLayout(); head.setSpacing(10)
        head.addWidget(_lbl(lock["name"], cls="lockname"))
        pill = _lbl(lock["state"], cls="statepill")
        pcol = "#f2685f" if lock["state"] in ("LOCKED", "ENABLED") else "#3ecf8e"
        pill.setStyleSheet(f"color:#0d1017; background:{pcol}; border-radius:10px; padding:2px 9px; font-weight:700;")
        head.addWidget(pill); head.addStretch(1)
        v.addLayout(head)
        v.addWidget(_lbl(f"enforcement:  {lock['enforcement']}", cls="enf", color=enf_color(lock["enforcement"])))
        for s in lock["strategies"]:
            v.addWidget(StrategyRow(s, on_action))


class UnlockPanel(QWidget):
    def __init__(self):
        super().__init__()
        self.setObjectName("root")
        outer = QVBoxLayout(self); outer.setContentsMargins(0, 0, 0, 0); outer.setSpacing(0)
        # top bar with scenario switcher
        bar = QFrame(); bar.setObjectName("topbar")
        bh = QVBoxLayout(bar); bh.setContentsMargins(16, 12, 16, 12); bh.setSpacing(8)
        t = QHBoxLayout()
        t.addWidget(_lbl("🔓 Reopen / Unlock", obj="title"))
        t.addWidget(_lbl("— Phase-2b: defeat the locks to regain access", obj="sub"))
        t.addStretch(1)
        bh.addLayout(t)
        scn = QHBoxLayout(); scn.setSpacing(6)
        self._btns = []
        for i, (label, _) in enumerate(SCENARIOS):
            b = QPushButton(label); b.setProperty("cls", "scn"); b.setCheckable(True)
            b.clicked.connect(lambda _, idx=i: self.load(idx))
            scn.addWidget(b); self._btns.append(b)
        scn.addStretch(1)
        bh.addLayout(scn)
        outer.addWidget(bar)
        self.summary = _lbl("", obj="summary"); self.summary.setWordWrap(True)
        outer.addWidget(self.summary)
        # scroll area of cards
        self.scroll = QScrollArea(); self.scroll.setWidgetResizable(True); self.scroll.setFrameShape(QFrame.NoFrame)
        self.host = QWidget(); self.cards = QVBoxLayout(self.host)
        self.cards.setContentsMargins(16, 4, 16, 12); self.cards.setSpacing(12); self.cards.addStretch(1)
        self.scroll.setWidget(self.host)
        outer.addWidget(self.scroll, 1)
        # action log
        self.log = QPlainTextEdit(); self.log.setObjectName("log"); self.log.setReadOnly(True)
        self.log.setFixedHeight(96)
        self.log.setPlainText("›  pick a scenario above to render its unlock plan")
        wrap = QWidget(); wl = QVBoxLayout(wrap); wl.setContentsMargins(16, 0, 16, 14)
        wl.addWidget(self.log)
        outer.addWidget(wrap)
        self.load(1)  # start on the register-gated case (the interesting one)

    def load(self, idx):
        for i, b in enumerate(self._btns):
            b.setChecked(i == idx)
        label, args = SCENARIOS[idx]
        if args is None:  # "from capture" — newest raw-*.json
            import glob
            caps = sorted(glob.glob(os.path.join(ROOT, "reports", "raw-*.json")), key=os.path.getmtime)
            if not caps:
                self._clear(); self.summary.setText("No reports/raw-*.json capture found — run enumerate first.")
                return
            args = ["--from-capture", caps[-1]]
        plan = run_unlock(args)
        self._render(plan, label)

    def _clear(self):
        while self.cards.count() > 1:
            it = self.cards.takeAt(0)
            w = it.widget()
            if w:
                w.setParent(None)   # detach synchronously so it's gone now, not next event loop
                w.deleteLater()

    def _render(self, plan, label):
        self._clear()
        if plan.get("error"):
            self.summary.setText(f"error: {plan['error']}"); return
        engaged = [L for L in plan.get("locks", []) if L["state"] in ("LOCKED", "ENABLED")]
        auto = sum(1 for L in engaged for s in L["strategies"] if s["kind"] in ("software-lever", "misconfig"))
        if not engaged:
            self.summary.setText(f"<b>{label}:</b> board is OPEN — nothing to unlock. Proceed to extraction. "
                                 "<i>(On a real target this panel is where the work is.)</i>")
        else:
            self.summary.setText(
                f"<b>{label}:</b> {len(engaged)} lock(s) engaged &nbsp;·&nbsp; "
                f"<span style='color:#3ecf8e'>{auto} AUTO software lever(s)</span> — try first. "
                "Ranked cheapest/safest → hardest.")
        for L in engaged:
            self.cards.insertWidget(self.cards.count() - 1, LockCard(L, self._action))

    def _action(self, strat):
        tag = KIND_TAG.get(strat["kind"], "?")
        if tag == "AUTO":
            msg = (f"▶ EXECUTE (software lever): {strat['title']}\n   {strat['how']}\n"
                   "   (real app: runs the reopen-debug lever, then re-reads the access verdict)")
        elif ACTION.get(strat["kind"], "").startswith("⧉"):
            QApplication.clipboard().setText(strat["how"])
            msg = f"⧉ copied to clipboard: {strat['title']}"
        else:
            msg = f"≡ GUIDE: {strat['title']}\n   {strat['how']}"
        self.log.appendPlainText(msg)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyleSheet(QSS)
    w = QMainWindow(); w.setWindowTitle("JTAGx — Reopen / Unlock")
    w.resize(1080, 760)
    w.setCentralWidget(UnlockPanel())
    w.show()
    sys.exit(app.exec())
