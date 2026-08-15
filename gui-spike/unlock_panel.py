#!/usr/bin/env python3
"""
unlock_panel.py — GUI spike: the flagship "Reopen / Unlock" panel (Phase-2b).

Renders tools/unlock-engine.py's --json plan as enforcement-classified lock cards with a ranked,
tagged strategy list. This is the operator-facing surface for the locked-board workflow (the core
mission): verdict + posture in → "here's what's locked, how it's enforced, and the ordered ways to
defeat it," AUTO software levers first.

Run:  pip install PySide6  &&  python3 gui-spike/unlock_panel.py
It shells `python3 tools/unlock-engine.py --from-capture <newest raw-*.json> --json` (the GUI drives
the real tool) and renders the plan for the LIVE board's posture. AUTO software levers run for real —
they execute reopen-debug.tcl and re-read the access verdict (the guided reopen→verify workflow),
marking each lock defeated / resisted. Live JTAG stays operator-driven.
"""
import json, os, subprocess, sys
from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QFrame, QPushButton, QVBoxLayout,
    QHBoxLayout, QScrollArea, QPlainTextEdit, QSizePolicy, QMessageBox,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UE = os.path.join(ROOT, "tools", "unlock-engine.py")
sys.path.insert(0, ROOT)                                          # repo root (for jtagx)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # gui-spike/ (for proc_runner)
from proc_runner import ProcRunner
from console_bus import BUS
try:
    from jtagx.paths import reports_dir as _reports_dir          # writable captures dir (P4)
except Exception:
    _reports_dir = lambda: os.path.join(ROOT, "reports")
try:
    from jtagx.unlock import (verify_cmd, parse_access_verdict, parse_reopen_result,
                              classify_reopen, WF_STATUS)                # guided reopen→verify workflow
except Exception:
    verify_cmd = parse_access_verdict = parse_reopen_result = classify_reopen = None
    WF_STATUS = {}

KIND_TAG = {"software-lever": "AUTO", "misconfig": "AUTO", "alternate-path": "SCRIPT",
            "physical-offline": "MANUAL", "firmware-attack": "OFFLINE",
            "fault-injection": "HARDWARE", "side-channel": "HARDWARE"}
TAG_COLOR = {"AUTO": "#3ecf8e", "SCRIPT": "#5b8cff", "MANUAL": "#e7b04b",
             "OFFLINE": "#b58bff", "HARDWARE": "#f2685f"}
ACTION = {"software-lever": "▶ Run", "misconfig": "▶ Run", "alternate-path": "⧉ Copy",
          "firmware-attack": "⧉ Copy", "physical-offline": "≡ Guide",
          "fault-injection": "≡ Guide", "side-channel": "≡ Guide"}

# operator-asserted posture toggles per board (the GUI equivalent of unlock-engine's CLI flags — these
# are OBSERVED facts the operator read on the board, not synthetic scenarios). Each = (arg-fragment, label).
POSTURE_OPTIONS = {
    "zynqmp":       [("--jtag-locked --no-efuse-jtag-dis", "DAP locked (reg)"),
                     ("--jtag-locked --efuse-jtag-dis", "eFuse-sealed"),
                     ("--secure-boot on", "Secure boot"), ("--aes-encrypt", "AES boot")],
    "zynq7000":     [("--jtag-locked --no-efuse-jtag-dis", "DAP locked"),
                     ("--secure-boot on", "Secure boot"), ("--aes-encrypt", "AES")],
    "smartfusion2": [("--debug-locked", "M3 debug locked"), ("--flashlock", "FlashLock")],
    "igloo2":       [("--flashlock", "FlashLock")],
    "nrf52":        [("--approtect-locked", "APPROTECT")],
    "stm32f4":      [("--rdp 1", "RDP1"), ("--rdp 2", "RDP2")],
    "stm32f1":      [("--rdp 1", "RDP1")],
    "stm32l4":      [("--rdp 1", "RDP1"), ("--rdp 2", "RDP2")],
    "kinetis":      [("--flash-secured", "FSEC secured"),
                     ("--flash-secured --meen-disabled", "FSEC + MEEN-off (permanent)")],
    "samd5x":       [("--debug-protected", "DSU protected")],
    "esp32":        [("--flash-encrypted", "Flash encrypted")],
}


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
        self.lock = lock
        self.status_key = None          # guided-workflow outcome: DEFEATED/PARTIAL/RESISTED/…
        self.setProperty("cls", "card")
        v = QVBoxLayout(self); v.setContentsMargins(14, 12, 14, 12); v.setSpacing(8)
        head = QHBoxLayout(); head.setSpacing(10)
        head.addWidget(_lbl(lock["name"], cls="lockname"))
        pill = _lbl(lock["state"], cls="statepill")
        pcol = "#f2685f" if lock["state"] in ("LOCKED", "ENABLED") else "#3ecf8e"
        pill.setStyleSheet(f"color:#0d1017; background:{pcol}; border-radius:10px; padding:2px 9px; font-weight:700;")
        head.addWidget(pill)
        # guided-workflow status pill (engaged → defeated/partial/resisted after Try & Verify)
        self.wf_pill = _lbl("", cls="statepill"); self.wf_pill.hide()
        head.addWidget(self.wf_pill)
        head.addStretch(1)
        v.addLayout(head)
        v.addWidget(_lbl(f"enforcement:  {lock['enforcement']}", cls="enf", color=enf_color(lock["enforcement"])))
        for s in lock["strategies"]:
            v.addWidget(StrategyRow(s, lambda st, lk=lock: on_action(st, lk)))

    def set_status(self, status_key):
        self.status_key = status_key
        label, color, _ = WF_STATUS.get(status_key, (status_key.lower(), "#98a6b8", ""))
        self.wf_pill.setText(f"▸ {label}")
        self.wf_pill.setStyleSheet(f"color:#0d1017; background:{color}; border-radius:10px; "
                                   "padding:2px 9px; font-weight:700;")
        self.wf_pill.show()


class UnlockPanel(QWidget):
    posture_changed = Signal(str, dict)   # (soc, observed posture P) — feeds the Attack-Surface layer

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
        self.src_note = _lbl("", obj="sub"); t.addWidget(self.src_note)
        self.btn_refresh = QPushButton("↻  Refresh"); self.btn_refresh.setProperty("cls", "scn")
        self.btn_refresh.setToolTip("Re-derive the unlock plan from the newest capture")
        self.btn_refresh.setCursor(Qt.PointingHandCursor)
        self.btn_refresh.clicked.connect(self.reload)
        t.addWidget(self.btn_refresh)
        bh.addLayout(t)
        # operator-asserted posture toggles for the active board (populated by set_board)
        self._posture_row = QHBoxLayout(); self._posture_row.setSpacing(6)
        self._posture_hint = _lbl("observed posture:", obj="sub")
        self._posture_row.addWidget(self._posture_hint)
        self._posture_btns = []
        self._posture_row.addStretch(1)
        bh.addLayout(self._posture_row)
        outer.addWidget(bar)
        self.summary = _lbl("", obj="summary"); self.summary.setWordWrap(True)
        outer.addWidget(self.summary)
        # scroll area of cards
        self.scroll = QScrollArea(); self.scroll.setWidgetResizable(True); self.scroll.setFrameShape(QFrame.NoFrame)
        self.host = QWidget(); self.cards = QVBoxLayout(self.host)
        self.cards.setContentsMargins(16, 4, 16, 12); self.cards.setSpacing(12); self.cards.addStretch(1)
        self.scroll.setWidget(self.host)
        outer.addWidget(self.scroll, 1)
        # levers + verify stream to the ONE shell console (console_bus), not a local log
        self.runner = ProcRunner(self)
        self.runner.line.connect(self._on_line)
        self.runner.done.connect(self._on_done)
        self._soc = "zynqmp"
        self._cards = {}                      # lock name -> LockCard (for status updates)
        self._wf = None                       # active guided reopen→verify flow, or None
        self.set_board("zynqmp")

    def set_board(self, soc):
        """Retarget to a board: rebuild its observed-posture toggles + derive the plan."""
        self._soc = soc
        # clear old toggles
        for b in self._posture_btns:
            b.setParent(None)
        self._posture_btns = []
        for frag, label in POSTURE_OPTIONS.get(soc, []):
            b = QPushButton(label); b.setProperty("cls", "scn"); b.setCheckable(True)
            b.setCursor(Qt.PointingHandCursor); b._frag = frag
            b.toggled.connect(self._derive)
            self._posture_row.insertWidget(self._posture_row.count() - 1, b)   # before the stretch
            self._posture_btns.append(b)
        self._posture_hint.setText("observed posture:" if self._posture_btns else "")
        self._derive()

    def load(self):
        self._derive()

    def reload(self):
        self._derive()

    def _derive(self, *_):
        """Derive the plan for the active board: from a real capture (zynqmp, no toggles) or from the
        operator-asserted posture toggles (observed facts) → the real unlock engine."""
        import glob
        flags = [f for b in self._posture_btns if b.isChecked() for f in b._frag.split()]
        if not flags:
            # no asserted posture → for a board WITH a capture, derive from it; else show the open state
            caps = sorted(glob.glob(os.path.join(_reports_dir(), "raw-*.json")),
                          key=os.path.getmtime) if self._soc == "zynqmp" else []
            if caps:
                self.src_note.setText(f"↳ {os.path.basename(caps[-1])}")
                self._render(run_unlock(["--from-capture", caps[-1]]), "From capture")
                return
            self.src_note.setText(f"↳ {self._soc}")
            self._render(run_unlock(["--soc", self._soc]), self._soc)
            return
        self.src_note.setText(f"↳ {self._soc}  (asserted)")
        self._render(run_unlock(["--soc", self._soc, *flags]), f"{self._soc} (observed)")

    def _clear(self):
        while self.cards.count() > 1:
            it = self.cards.takeAt(0)
            w = it.widget()
            if w:
                w.setParent(None)   # detach synchronously so it's gone now, not next event loop
                w.deleteLater()

    def _render(self, plan, label):
        self._clear()
        self._cards = {}
        self._wf = None
        self._soc = plan.get("soc", "zynqmp")
        self._label = label
        self.posture_changed.emit(self._soc, plan.get("posture", {}) or {})   # → Attack-Surface layer
        if plan.get("error"):
            self.summary.setText(f"error: {plan['error']}"); return
        engaged = [L for L in plan.get("locks", []) if L["state"] in ("LOCKED", "ENABLED")]
        self._engaged_total = len(engaged)
        if not engaged:
            self.summary.setText(f"<b>{label}:</b> board is OPEN — nothing to unlock. Proceed to extraction. "
                                 "<i>(On a real target this panel is where the work is.)</i>")
        else:
            self._update_progress()
        for L in engaged:
            card = LockCard(L, self._action)
            self._cards[L["name"]] = card
            self.cards.insertWidget(self.cards.count() - 1, card)

    def _update_progress(self):
        """Summary banner: how many locks are defeated so far (drives the LOCKED → OPEN story)."""
        total = getattr(self, "_engaged_total", 0)
        if not total:
            return
        done = sum(1 for c in self._cards.values() if c.status_key in ("DEFEATED", "PARTIAL"))
        auto = sum(1 for c in self._cards.values() if any(s.get("cmd") for s in c.lock["strategies"]))
        tail = (" — <span style='color:#3ecf8e'>all defeated ✓</span>" if done == total and total
                else f" — <span style='color:#3ecf8e'>{done}/{total} defeated</span>")
        self.summary.setText(
            f"<b>{getattr(self, '_label', '')}:</b> {total} lock(s) engaged &nbsp;·&nbsp; "
            f"{auto} AUTO lever(s) — click <b>▶ Run</b> to try &amp; verify each.{tail}")

    # -- guided reopen→verify flow (the locked-board core loop) --------------------------------
    def _run_guided(self, lock, strat):
        if self.runner.busy():
            self._log("busy — a lever is already running"); return
        vcmd = verify_cmd(self._soc) if verify_cmd else ""
        self._wf = {"lock": lock, "strat": strat, "phase": "lever", "buf": "", "outcome": None, "vcmd": vcmd}
        if lock["name"] in self._cards:
            self._cards[lock["name"]].set_status("ENGAGED")
        self._log(f"▶ [1/2] LEVER: {strat['title']}\n   $ {strat['cmd']}")
        self.runner.run_shell(strat["cmd"], cwd=ROOT)

    def _log(self, text, kind="d"):
        """Emit to the ONE shell console (multi-line safe)."""
        for ln in str(text).split("\n"):
            BUS.line.emit(kind, ln)

    def _on_line(self, t):
        self._log(t)
        if self._wf is not None:
            self._wf["buf"] += t + "\n"

    def _on_done(self, code):
        wf = self._wf
        if wf is None:                          # a plain (non-guided) lever/copy run
            self._log(f"— exited ({code})"); return
        if wf["phase"] == "lever":
            wf["outcome"] = parse_reopen_result(wf["buf"]) if parse_reopen_result else "UNKNOWN"
            self._log(f"   ↳ lever outcome: {wf['outcome']}")
            if wf["vcmd"]:
                wf["phase"] = "verify"; wf["buf"] = ""
                self._log(f"▶ [2/2] VERIFY: re-reading the access verdict\n   $ {wf['vcmd']}")
                self.runner.run_shell(wf["vcmd"], cwd=ROOT); return
            self._finish_guided(classify_reopen(wf["outcome"], "UNKNOWN"))
        else:                                   # verify phase
            verdict = parse_access_verdict(wf["buf"]) if parse_access_verdict else "UNKNOWN"
            self._log(f"   ↳ access verdict: {verdict}")
            self._finish_guided(classify_reopen(wf["outcome"], verdict))

    def _finish_guided(self, result):
        status, msg = result
        wf = self._wf
        icon = {"DEFEATED": "✓", "PARTIAL": "◐", "RESISTED": "✗"}.get(status, "•")
        self._log(f"   {icon} {status}: {msg}")
        if wf and wf["lock"]["name"] in self._cards:
            self._cards[wf["lock"]["name"]].set_status(status)
        self._wf = None
        self._update_progress()

    def _action(self, strat, lock=None):
        tag = KIND_TAG.get(strat["kind"], "?")
        cmd = strat.get("cmd", "")
        # DESTRUCTIVE levers (nRF52 ERASEALL, STM32 RDP1→0) re-open debug by MASS-ERASING flash.
        # Never auto-run one — confirm first, and make the consequence explicit.
        if cmd and strat.get("destructive"):
            r = QMessageBox.warning(
                self, "Destructive lever — mass-erase",
                f"“{strat['title']}” re-opens debug by ERASING all flash.\n\n"
                "You will get DEBUG ACCESS but LOSE the current firmware image. This cannot be undone.\n\n"
                "Proceed with the mass-erase?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel)
            if r != QMessageBox.StandardButton.Yes:
                self._log(f"✗ cancelled destructive lever: {strat['title']}"); return
        # AUTO lever with a verify → run the guided two-phase reopen→verify flow (marks the lock)
        if tag == "AUTO" and cmd and strat.get("verify") == "access-check" and lock and classify_reopen:
            self._run_guided(lock, strat); return
        if tag == "AUTO" and cmd:
            if self.runner.busy():
                self._log("busy — a lever is already running"); return
            self._log(f"▶ RUN (software lever): {strat['title']}\n   $ {cmd}")
            self.runner.run_shell(cmd, cwd=ROOT)       # operator-driven; streams into the log
        elif tag == "AUTO":
            self._log(f"▶ {strat['title']} — no direct command wired; apply manually:\n   {strat['how']}")
        elif ACTION.get(strat["kind"], "").startswith("⧉"):
            QApplication.clipboard().setText(strat["how"])
            self._log(f"⧉ copied to clipboard: {strat['title']}")
        else:
            self._log(f"≡ GUIDE: {strat['title']}\n   {strat['how']}")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyleSheet(QSS)
    w = QMainWindow(); w.setWindowTitle("JTAGx — Reopen / Unlock")
    w.resize(1080, 760)
    w.setCentralWidget(UnlockPanel())
    w.show()
    sys.exit(app.exec())
