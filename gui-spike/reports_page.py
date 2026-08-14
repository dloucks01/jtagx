#!/usr/bin/env python3
"""
reports_page.py — the app's "Reports" page (gui-spike/jtagx_app.py rail item).

A file list (left) + a Markdown renderer (right). Reads the engagement's reports/*.md
(engagement, vxworks-analysis, dram-secrets, sym-crypto, interpreted captures, …) and renders the
selected one with Qt's native Markdown support (GitHub dialect — tables included). Real deliverables,
in-app.
"""
import glob, os
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QVBoxLayout, QLabel, QListWidget, QListWidgetItem, QTextBrowser,
)

# preferred ordering (the headline deliverables first); everything else follows by mtime (newest first)
PREFERRED = ["engagement.md", "vxworks-analysis.md", "dram-secrets.md", "sym-crypto.md", "triage.md"]

BROWSER_CSS = """
QTextBrowser { background:#0e131b; color:#cdd6e2; border:1px solid #232c39; border-radius:10px;
    padding:10px 14px; font-size:13px; }
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
        h = QHBoxLayout(self); h.setContentsMargins(16, 14, 16, 14); h.setSpacing(14)

        left = QVBoxLayout(); left.setSpacing(6)
        hdr = QLabel("REPORTS"); hdr.setStyleSheet("color:#98a6b8; font-size:11px; font-weight:600;")
        left.addWidget(hdr)
        self.list = QListWidget(); self.list.setFixedWidth(250); self.list.setStyleSheet(LIST_CSS)
        self.list.currentItemChanged.connect(self._on_select)
        left.addWidget(self.list, 1)
        h.addLayout(left)

        self.browser = QTextBrowser(); self.browser.setStyleSheet(BROWSER_CSS)
        self.browser.setOpenExternalLinks(False)
        h.addWidget(self.browser, 1)

        self._populate()

    def _files(self):
        found = {os.path.basename(p): p for p in glob.glob(os.path.join(self.dir, "*.md"))}
        ordered = [found.pop(n) for n in PREFERRED if n in found]
        rest = sorted(found.values(), key=os.path.getmtime, reverse=True)
        return ordered + rest

    def _populate(self):
        self.list.clear()
        files = self._files()
        for p in files:
            it = QListWidgetItem(os.path.basename(p)); it.setData(Qt.UserRole, p)
            self.list.addItem(it)
        if files:
            self.list.setCurrentRow(0)
        else:
            self.browser.setMarkdown("_No reports yet — run the engagement steps "
                                     "(enumerate / dump / analyze / engagement-report)._")

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
