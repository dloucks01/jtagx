#!/usr/bin/env python3
"""
reports_page.py — the app's "Reports" page (gui-spike/jtagx_app.py rail item).

A file list (left) + a Markdown renderer (right). Reads the engagement's reports/*.md
(engagement, vxworks-analysis, dram-secrets, sym-crypto, interpreted captures, …) and renders the
selected one with Qt's native Markdown support (GitHub dialect — tables included). Real deliverables,
in-app.
"""
import glob, os, shlex, sys
from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QLabel, QListWidget, QListWidgetItem, QTextBrowser,
    QPushButton,
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root (for jtagx)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))                   # gui-spike (proc_runner)
from proc_runner import ProcRunner
try:
    from console_bus import BUS
except Exception:
    BUS = None
try:
    from jtagx import paths as _paths
except Exception:
    _paths = None

# preferred ordering (the headline deliverables first); everything else follows by mtime (newest first)
PREFERRED = ["engagement.md", "vxworks-analysis.md", "dram-secrets.md", "sym-crypto.md", "triage.md"]

BROWSER_CSS = """
QTextBrowser { background:#0e131b; color:#cdd6e2; border:1px solid #232c39; border-radius:10px;
    padding:6px 16px; font-size:13px; }
"""

# document stylesheet — styles the RENDERED markdown (QTextDocument HTML elements), not the widget frame
DOC_CSS = """
h1 { color:#e7ecf3; font-size:22px; font-weight:800; border-bottom:2px solid #2a3646; padding-bottom:6px; }
h2 { color:#5bb6f0; font-size:16px; font-weight:700; padding-top:10px; }
h3 { color:#8fd39a; font-size:14px; font-weight:700; }
h4 { color:#98a6b8; font-size:12.5px; font-weight:700; }
p  { color:#cdd6e2; line-height:150%; }
li { color:#cdd6e2; line-height:150%; }
a  { color:#5b8cff; }
strong { color:#eaf1ff; }
em { color:#b7c2d0; }
code { background:#0b0e14; color:#33d6c4; font-family:"DejaVu Sans Mono",monospace; padding:1px 4px; }
pre  { background:#0b0e14; color:#aeb9c7; font-family:"DejaVu Sans Mono",monospace;
       border:1px solid #232c39; padding:8px 10px; }
blockquote { color:#98a6b8; border-left:3px solid #3b6ff0; padding-left:12px; margin-left:2px; }
table { border:1px solid #2a3646; }
th { background:#141c27; color:#98a6b8; border:1px solid #2a3646; padding:5px 9px; font-weight:700; }
td { border:1px solid #232c39; padding:4px 9px; color:#cdd6e2; }
hr { border:1px solid #1c242f; }
"""
LIST_CSS = """
QListWidget { background:#0f141c; color:#b7c2d0; border:1px solid #232c39; border-radius:10px;
    padding:4px; font-size:12px; outline:0; }
QListWidget::item { padding:6px 8px; border-radius:6px; }
QListWidget::item:selected { background:#1e2735; color:#fff; }
"""


class ReportsPage(QWidget):
    def __init__(self, root):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        self.dir = os.path.join(root, "reports")
        self._soc = "zynqmp"; self._target = "ZCU102"    # board the Generate button targets (set_board)
        outer = QVBoxLayout(self); outer.setContentsMargins(16, 14, 16, 14); outer.setSpacing(10)

        # header: title + live count + reports dir + refresh
        top = QHBoxLayout()
        title = QLabel("REPORTS"); title.setStyleSheet("color:#e7ecf3; font-size:13px; font-weight:700;")
        top.addWidget(title)
        self.count_lbl = QLabel(""); self.count_lbl.setStyleSheet("color:#5e6b7c; font-size:11px;")
        top.addWidget(self.count_lbl)
        top.addStretch(1)
        dirlbl = QLabel(self.dir); dirlbl.setStyleSheet("color:#3a4553; font-size:10px;")
        dirlbl.setToolTip(self.dir); top.addWidget(dirlbl)
        _bs = ("QPushButton{background:#141922; color:#98a6b8; border:1px solid #232c39;"
               "border-radius:8px; padding:5px 12px;} QPushButton:hover{border-color:#2c3644;}")
        self.gen_btn = QPushButton("＋  Generate"); self.gen_btn.setCursor(Qt.PointingHandCursor)
        self.gen_btn.setStyleSheet(_bs)
        self.gen_btn.setToolTip("Run engagement-report.py (auto-derives posture from the newest capture)")
        self.gen_btn.clicked.connect(self._generate)
        top.addWidget(self.gen_btn)
        self.html_btn = QPushButton("⚡  Stylized HTML"); self.html_btn.setCursor(Qt.PointingHandCursor)
        self.html_btn.setStyleSheet(_bs)
        self.html_btn.setToolTip("Run tools/report-html.py on the newest capture — operator-first: "
                                 "verdict, posture chips, critical findings+actions, next-steps, "
                                 "anomalies. Opens in your browser.")
        self.html_btn.clicked.connect(self._generate_html)
        top.addWidget(self.html_btn)
        btn = QPushButton("↻  Refresh"); btn.setCursor(Qt.PointingHandCursor)
        btn.setStyleSheet(_bs)
        btn.clicked.connect(self._populate)
        top.addWidget(btn)
        outer.addLayout(top)

        # runner for the one-click report generator (offline tool; no hardware)
        self._code_root = _paths.repo_root() if _paths else os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))
        self.runner = ProcRunner(self)
        self.runner.done.connect(self._on_generated)
        if BUS is not None:
            self.runner.line.connect(lambda t: BUS.line.emit("d", t))   # stream into the shell console

        # separate runner for the HTML report (independent of the markdown engagement-report flow above)
        self._html_out = None
        self.html_runner = ProcRunner(self)
        self.html_runner.done.connect(self._on_html_generated)
        if BUS is not None:
            self.html_runner.line.connect(lambda t: BUS.line.emit("d", t))

        h = QHBoxLayout(); h.setSpacing(14)
        left = QVBoxLayout(); left.setSpacing(6)
        self.list = QListWidget(); self.list.setFixedWidth(250); self.list.setStyleSheet(LIST_CSS)
        self.list.currentItemChanged.connect(self._on_select)
        left.addWidget(self.list, 1)
        h.addLayout(left)

        self.browser = QTextBrowser(); self.browser.setStyleSheet(BROWSER_CSS)
        self.browser.setOpenExternalLinks(False)
        self.browser.document().setDefaultStyleSheet(DOC_CSS)   # style the rendered markdown
        h.addWidget(self.browser, 1)
        outer.addLayout(h, 1)

        self._populate()

    def _files(self):
        found = {os.path.basename(p): p for p in glob.glob(os.path.join(self.dir, "*.md"))}
        ordered = [found.pop(n) for n in PREFERRED if n in found]
        rest = sorted(found.values(), key=os.path.getmtime, reverse=True)
        return ordered + rest

    def _populate(self):
        prev = self.list.currentItem().data(Qt.UserRole) if self.list.currentItem() else None
        self.list.blockSignals(True)
        self.list.clear()
        files = self._files()
        for p in files:
            it = QListWidgetItem(os.path.basename(p)); it.setData(Qt.UserRole, p)
            self.list.addItem(it)
        self.list.blockSignals(False)
        self.count_lbl.setText(f"· {len(files)} file(s)")
        if files:
            # keep the previously-open report selected across a refresh, else show the first
            row = next((i for i in range(self.list.count())
                        if self.list.item(i).data(Qt.UserRole) == prev), 0)
            self.list.setCurrentRow(row)
        else:
            self.browser.setMarkdown("_No reports yet — run the engagement steps "
                                     "(enumerate / dump / analyze / engagement-report)._")

    def _generate(self):
        """One-click: run engagement-report.py, auto-deriving posture from the newest capture."""
        if self.runner.busy():
            return
        dumps = _paths.dumps_dir() if _paths else os.path.join(self._code_root, "dumps")
        # a from-capture posture only applies to the home ZynqMP board (that's whose §1–16 raw JSON is
        # in reports/); other boards have no capture yet, so generate from the jtag-open baseline.
        if self._soc == "zynqmp":
            caps = sorted(glob.glob(os.path.join(self.dir, "raw-*.json")), key=os.path.getmtime)
            src = ["--from-capture", caps[-1]] if caps else ["--jtag-open"]
            out = "reports/engagement.md"
        else:
            src = ["--jtag-open"]
            out = f"reports/engagement-{self._soc}.md"       # don't clobber the home engagement.md
        argv = ["python3", "tools/engagement-report.py", "--soc", self._soc, "--target", self._target,
                *src, "--dumps", dumps, "-o", out]
        if _paths is not None:
            argv = [_paths.localize(a) for a in argv]   # -> writable reports/ when packaged (no-op in dev)
        # run() (argv, no shell) rather than run_shell(" ".join(argv)): --target carries the board's
        # display name (e.g. "Zynq UltraScale+ (ZynqMP)"), and shell-joining an unquoted string with
        # spaces/parens breaks (found 2026-08-15 via gui-smoketest's Reports-Generate check — bash choked
        # on the bare "(" the moment the board selector was exercised before Generate).
        cmd = shlex.join(argv)                          # for the operator-visible preview only
        self.gen_btn.setText("Generating…"); self.gen_btn.setEnabled(False)
        self.browser.setMarkdown(f"_Generating engagement report…_\n\n`{cmd}`")
        if BUS is not None:
            BUS.command.emit("Reports", cmd)
        self.runner.run(argv, cwd=self._code_root)

    def _on_generated(self, code):
        self.gen_btn.setText("＋  Generate"); self.gen_btn.setEnabled(True)
        self._populate()
        # select the file we just generated (engagement.md for the home board, else engagement-<soc>.md)
        want = "engagement.md" if self._soc == "zynqmp" else f"engagement-{self._soc}.md"
        for i in range(self.list.count()):
            if os.path.basename(self.list.item(i).data(Qt.UserRole)) == want:
                self.list.setCurrentRow(i); break
        if code != 0:
            self.browser.setMarkdown(f"_engagement-report.py exited with code {code}._")

    def _generate_html(self):
        """One-click: run tools/report-html.py on the newest raw-<ts>.json capture, then open the
        result in the default browser (the stylized HTML doesn't render inside QTextBrowser — no CSS
        variables/media queries — so this opens it externally rather than trying to embed it)."""
        if self.html_runner.busy():
            return
        caps = sorted(glob.glob(os.path.join(self.dir, "raw-*.json")), key=os.path.getmtime)
        if not caps:
            self.browser.setMarkdown("_No raw capture yet — run enumerate.tcl first "
                                     "(the HTML report needs a raw-*.json)._")
            return
        raw = caps[-1]
        stem = os.path.splitext(os.path.basename(raw))[0].replace("raw-", "")
        self._html_out = os.path.join(self.dir, f"report-{stem}.html")
        argv = ["python3", "tools/report-html.py", raw, "-o", self._html_out]
        if _paths is not None:
            argv = [_paths.localize(a) for a in argv]
        cmd = shlex.join(argv)                          # for the operator-visible preview only
        self.html_btn.setText("Generating…"); self.html_btn.setEnabled(False)
        if BUS is not None:
            BUS.command.emit("Reports", cmd)
        self.html_runner.run(argv, cwd=self._code_root)

    def _on_html_generated(self, code):
        self.html_btn.setText("⚡  Stylized HTML"); self.html_btn.setEnabled(True)
        if code == 0 and self._html_out and os.path.exists(self._html_out):
            QDesktopServices.openUrl(QUrl.fromLocalFile(self._html_out))
        else:
            self.browser.setMarkdown(f"_report-html.py exited with code {code}._")

    def set_board(self, soc, target=""):
        """Point the one-click Generate button at the active board (soc + display target)."""
        self._soc = soc or "zynqmp"
        self._target = target or soc or "ZCU102"

    def _on_select(self, cur, _prev):
        if not cur:
            return
        path = cur.data(Qt.UserRole)
        try:
            self.browser.setMarkdown(open(path, encoding="utf-8", errors="replace").read())
        except Exception as e:
            self.browser.setPlainText(f"error reading {path}: {e}")
        self.browser.verticalScrollBar().setValue(0)


if __name__ == "__main__":
    import sys
    from PySide6.QtWidgets import QApplication
    app = QApplication(sys.argv)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    w = ReportsPage(root); w.resize(1000, 720); w.setStyleSheet("background:#0d1017;")
    w.setWindowTitle("Reports"); w.show()
    sys.exit(app.exec())
