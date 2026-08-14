#!/usr/bin/env python3
"""
chain_page.py — the app's "Chain & Transport" page (gui-spike/jtagx_app.py rail item).

Shows the JTAG transport surface: the discovered chain (TAPs with decoded IDCODEs + the DAP's APs),
the access verdict, and — the data-driven part — the **per-board adapter allowlist read straight from
profiles/<soc>.json** (the transport-abstraction data), with each adapter's backend, transports, and
reachable access tier. This closes the loop with the adapter-catalog/transport work.
"""
import json, os
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGridLayout, QLabel, QFrame,
    QTreeWidget, QTreeWidgetItem, QTableWidget, QTableWidgetItem, QHeaderView,
)

# the real chain we discovered on the ZCU102 (openocd discover.tcl)
CHAIN = [("TAP1 · PS TAP (ZynqMP)", 0x24738093), ("TAP0 · ARM DAP (CoreSight)", 0x5BA00477)]
APS = [("AP0", "0x34770004", "AXI MEM-AP — memory access (DDR/OCM)"),
       ("AP1", "0x44770002", "APB MEM-AP — debug registers"),
       ("AP2", "0x24760010", "JTAG-AP — PL/PMU")]
MFG = {0x049: "Xilinx/AMD", 0x23b: "ARM Ltd"}
TIER_COLOR = {"a": "#5e6b7c", "b": "#e7b04b", "c": "#4bb5c9", "d": "#3ecf8e", "e": "#3ecf8e"}


def decode_idcode(idc):
    ver = (idc >> 28) & 0xF
    part = (idc >> 12) & 0xFFFF
    mfg = (idc >> 1) & 0x7FF
    return f"ver {ver:#x} · part 0x{part:04x} · mfg 0x{mfg:03x} ({MFG.get(mfg, '?')})"


def load_profile(root, soc):
    p = os.path.join(root, "profiles", f"{soc}.json")
    if not os.path.exists(p):
        return None
    keep = [l for l in open(p) if not l.lstrip().startswith(("//", "#"))]
    try:
        return json.loads("".join(keep))
    except Exception:
        return None


def _lbl(text, color=None, size=None, bold=False):
    x = QLabel(text)
    s = ""
    if color: s += f"color:{color};"
    if size: s += f"font-size:{size}px;"
    if bold: s += "font-weight:600;"
    if s: x.setStyleSheet(s)
    return x


class ChainPage(QWidget):
    def __init__(self, soc="zynqmp"):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        prof = load_profile(root, soc) or {}
        v = QVBoxLayout(self); v.setContentsMargins(16, 14, 16, 14); v.setSpacing(14)

        # --- transport / verdict card ---
        card = QFrame(); card.setProperty("cls", "panel")
        g = QGridLayout(card); g.setContentsMargins(16, 12, 16, 12); g.setHorizontalSpacing(28); g.setVerticalSpacing(6)
        g.addWidget(_lbl("⛓  TRANSPORT & VERDICT", "#98a6b8", 11, True), 0, 0, 1, 4)
        kv = [("Adapter", "FT2232H (onboard, 0403:6014)"), ("Backend", "openocd 0.12"),
              ("Transport", "JTAG · 10 MHz"), ("Target", prof.get("name", soc))]
        for i, (k, val) in enumerate(kv):
            g.addWidget(_lbl(k, "#5e6b7c"), 1 + i // 2, (i % 2) * 2)
            g.addWidget(_lbl(val, "#e7ecf3"), 1 + i // 2, (i % 2) * 2 + 1)
        verdict = QLabel("● Access verdict: OPEN")
        verdict.setStyleSheet("color:#3ecf8e; background:rgba(62,207,142,0.10);"
                              "border:1px solid rgba(62,207,142,0.30); border-radius:8px; padding:5px 12px; font-weight:600;")
        g.addWidget(verdict, 3, 0, 1, 4)
        v.addWidget(card)

        # --- chain tree (TAPs + IDCODE decode + APs) ---
        cf = QFrame(); cf.setProperty("cls", "panel")
        cv = QVBoxLayout(cf); cv.setContentsMargins(8, 8, 8, 8); cv.setSpacing(4)
        cv.addWidget(_lbl("  JTAG CHAIN  ·  2 TAPs", "#98a6b8", 11, True))
        tree = QTreeWidget(); tree.setHeaderHidden(True); tree.setRootIsDecorated(True)
        for name, idc in CHAIN:
            it = QTreeWidgetItem([f"{name}    0x{idc:08X}    {decode_idcode(idc)}"])
            tree.addTopLevelItem(it); it.setExpanded(True)
            if idc == 0x5BA00477:
                for ap, idr, desc in APS:
                    it.addChild(QTreeWidgetItem([f"{ap}   IDR {idr}   {desc}"]))
        cv.addWidget(tree)
        v.addWidget(cf, 1)

        # --- adapter allowlist (from profiles/<soc>.json) ---
        af = QFrame(); af.setProperty("cls", "panel")
        av = QVBoxLayout(af); av.setContentsMargins(8, 8, 8, 8); av.setSpacing(6)
        adapters = prof.get("adapters", [])
        av.addWidget(_lbl(f"  ADAPTERS FOR THIS BOARD  ·  {len(adapters)} (from profiles/{soc}.json)",
                          "#98a6b8", 11, True))
        t = QTableWidget(len(adapters), 5)
        t.setHorizontalHeaderLabels(["Adapter", "Backend", "Transports", "Tier", "Vendor SW"])
        t.verticalHeader().setVisible(False); t.setShowGrid(False)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        hh = t.horizontalHeader()
        hh.setSectionResizeMode(0, QHeaderView.Stretch)
        for c in range(1, 5):
            hh.setSectionResizeMode(c, QHeaderView.ResizeToContents)
        for r, a in enumerate(adapters):
            t.setItem(r, 0, QTableWidgetItem(a.get("name", a.get("id", "?"))))
            bk = QTableWidgetItem(a.get("backend", ""));
            if a.get("backend") != "openocd":
                bk.setForeground(Qt.yellow)
            t.setItem(r, 1, bk)
            t.setItem(r, 2, QTableWidgetItem(", ".join(a.get("transports", []))))
            tier = a.get("tier", "?")
            ti = QTableWidgetItem(f"tier {tier}")
            ti.setForeground(Qt.gray)
            t.setItem(r, 3, ti)
            pill = QLabel("vendor" if a.get("vendor_sw") else "open")
            pill.setAlignment(Qt.AlignCenter)
            col = "#e7b04b" if a.get("vendor_sw") else "#3ecf8e"
            pill.setStyleSheet(f"color:{col}; font-weight:600; font-size:11px;")
            # tier color badge via a styled cell widget
            tw = QLabel(f"  {tier.upper()}  "); tw.setAlignment(Qt.AlignCenter)
            tw.setStyleSheet(f"color:#0d1017; background:{TIER_COLOR.get(tier,'#5e6b7c')};"
                             "border-radius:8px; font-weight:700; font-size:11px;")
            t.setCellWidget(r, 3, tw)
            t.setCellWidget(r, 4, pill)
        av.addWidget(t)
        v.addWidget(af, 1)


if __name__ == "__main__":
    import sys
    from PySide6.QtWidgets import QApplication
    app = QApplication(sys.argv)
    w = ChainPage(sys.argv[1] if len(sys.argv) > 1 else "zynqmp")
    w.resize(900, 720); w.setStyleSheet("background:#0d1017; color:#e7ecf3;")
    w.setWindowTitle("Chain & Transport"); w.show()
    sys.exit(app.exec())
