#!/usr/bin/env python3
"""
help_page.py — the in-app Help / User Guide (gui-spike/jtagx_app.py rail item).

Renders the operator quick-reference (docs/guides/gui-quick-reference.md) inside the app with Qt's
native Markdown so the guide travels with the tool. Falls back to a short embedded summary if the
doc file isn't present (e.g. a packaged build that didn't bundle docs/).
"""
import os
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QWidget, QVBoxLayout, QLabel, QTextBrowser

DOC_REL = os.path.join("docs", "guides", "gui-quick-reference.md")

FALLBACK = """# JTAGx — Quick Help

The GUI is a **driver**: it builds and streams the real commands; **you drive all live JTAG**.
Everything shown is the real captured posture, detected adapters, and dumps.

## Pages (Ctrl+1..6)
- **Dashboard** — hero tiles + 7 center tabs: Posture, Registers (search / decode / right-click /
  CoreSight topology), Memory/Report launchers, Kill Chain (objective ladder + extraction avenues),
  Attack Surface (implementation-review misuse hypotheses), **→] Shell** (the get-a-shell planner:
  live-patch / catch-a-credential / cold-boot / persist). Capabilities panel (click to run), chain
  panel (right-click a core → halt/resume/read → console).
- **Unlock** — the locked-board plan from the newest capture; ▶ Run a lever → reopen + verify.
- **Chain** — first-contact troubleshooting search (symptom → blocker + fix), pre-flight GO/BLOCKED,
  adapters, JTAG chain, xsdb target tree; ↻ re-scans USB.
- **Memory** — virtualized hex over any dump; Find hex bytes or 'ASCII.
- **Reports** — rendered Markdown; ＋ Generate an engagement report, ⚡ Stylized HTML report.
- **Help** — this page.

## Console (bottom, always visible)
Type a command / script and run it. Slash-commands (`/help /enumerate /scan /verify /unlock
/dump /report /adapters /backend`), backend primitives (`mrd/mdw/halt/run/scan` — routed through
the Transport selector), or any shell command. Tab completes; ↑/↓ history.

## Shortcuts
Ctrl+1..6 pages · Ctrl+E Enumerate · Ctrl+R refresh page · Tab complete · ↑/↓ history.

_(Full guide: docs/guides/gui-quick-reference.md)_
"""

BROWSER_CSS = """
QTextBrowser { background:#f3f5f8; color:#2f3947; border:1px solid #dfe4ea; border-radius:10px;
    padding:12px 18px; font-size:13px; }
"""


class HelpPage(QWidget):
    def __init__(self, root):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        self._root = root
        v = QVBoxLayout(self); v.setContentsMargins(16, 14, 16, 14); v.setSpacing(10)
        hdr = QLabel("❔  HELP / USER GUIDE")
        hdr.setStyleSheet("color:#151b26; font-size:13px; font-weight:700;")
        v.addWidget(hdr)
        self.browser = QTextBrowser(); self.browser.setStyleSheet(BROWSER_CSS)
        self.browser.setOpenExternalLinks(False)
        self.browser.setMarkdown(self._load())
        v.addWidget(self.browser, 1)

    def _load(self):
        p = os.path.join(self._root, DOC_REL)
        try:
            if os.path.exists(p):
                return open(p, encoding="utf-8", errors="replace").read()
        except Exception:
            pass
        return FALLBACK


if __name__ == "__main__":
    import sys
    from PySide6.QtWidgets import QApplication
    app = QApplication(sys.argv)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    w = HelpPage(root); w.resize(900, 720); w.setStyleSheet("background:#f4f6f9;")
    w.setWindowTitle("Help"); w.show()
    sys.exit(app.exec())
