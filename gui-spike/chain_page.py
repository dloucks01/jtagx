#!/usr/bin/env python3
"""
chain_page.py — the app's "Chain & Transport" page (gui-spike/jtagx_app.py rail item).

Shows the JTAG transport surface: the discovered chain (TAPs with decoded IDCODEs + the DAP's APs),
the access verdict, the **per-board adapter allowlist read straight from profiles/<soc>.json** (with
each adapter's backend/transports/tier and a live "Present ● detected" column), and the **xsdb
debug-target tree** the hw_server backend would enumerate.

P4: a live **↻ Refresh** button re-runs USB adapter detection and rebuilds the dynamic panels
without restarting the app — plug in a SmartLynq2 and click to see it light up.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root (for jtagx)
try:
    from jtagx.transport import (detect_adapters, match_profile, for_profile,
                                 zynqmp_reference, flatten_targets, make_transport,
                                 capability_matrix, routing_plan, join_present, OPS, OP_LABEL)
except Exception:       # transport layer optional at import time
    detect_adapters = match_profile = for_profile = zynqmp_reference = flatten_targets = None
    make_transport = capability_matrix = routing_plan = join_present = None
    OPS = []; OP_LABEL = {}
try:
    from jtagx.preflight import preflight as _preflight
except Exception:
    _preflight = None
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGridLayout, QLabel, QFrame, QPushButton,
    QTreeWidget, QTreeWidgetItem, QTableWidget, QTableWidgetItem, QHeaderView, QApplication,
    QLineEdit, QScrollArea,
)
try:
    from jtagx import firstcontact as _firstcontact
except Exception:
    _firstcontact = None

# the real chain we discovered on the ZCU102 (openocd discover.tcl)
CHAIN = [("TAP1 · PS TAP (ZynqMP)", 0x24738093), ("TAP0 · ARM DAP (CoreSight)", 0x5BA00477)]
APS = [("AP0", "0x34770004", "AXI MEM-AP — memory access (DDR/OCM)"),
       ("AP1", "0x44770002", "APB MEM-AP — debug registers"),
       ("AP2", "0x24760010", "JTAG-AP — PL/PMU")]
MFG = {0x049: "Xilinx/AMD", 0x23b: "ARM Ltd"}
TIER_COLOR = {"a": "#5e6b7c", "b": "#e7b04b", "c": "#4bb5c9", "d": "#3ecf8e", "e": "#3ecf8e"}
ROLE_COL = {"a53": "#3ecf8e", "r5": "#5aa9e6", "pmu": "#e7b04b", "pl": "#b07de7",
            "apu": "#7c8898", "rpu": "#7c8898", "psu": "#7c8898", "tap": "#5e6b7c"}


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
        self.soc = soc
        self.root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.prof = load_profile(self.root, soc) or {}

        outer = QVBoxLayout(self); outer.setContentsMargins(16, 14, 16, 14); outer.setSpacing(12)

        # header: title + live refresh
        hdr = QHBoxLayout()
        hdr.addWidget(_lbl("CHAIN & TRANSPORT", "#e7ecf3", 13, True))
        hdr.addStretch(1)
        self.refresh_note = _lbl("", "#5e6b7c", 11)
        hdr.addWidget(self.refresh_note)
        self.btn_refresh = QPushButton("↻  Refresh")
        self.btn_refresh.setToolTip("Re-scan USB adapters and rebuild the transport view")
        self.btn_refresh.setCursor(Qt.PointingHandCursor)
        self.btn_refresh.clicked.connect(self.refresh)
        hdr.addWidget(self.btn_refresh)
        outer.addLayout(hdr)

        # first-contact troubleshooting search: symptom -> ranked blocker + fix (jtagx.firstcontact).
        # A PERSISTENT panel (not inside self.body / refresh()'s rebuild) so typed text + results survive
        # a Refresh click. Empty until the operator searches — doesn't compete with the preflight checklist.
        if _firstcontact is not None:
            tf = QFrame(); tf.setProperty("cls", "panel")
            tv = QVBoxLayout(tf); tv.setContentsMargins(12, 10, 12, 10); tv.setSpacing(6)
            trow = QHBoxLayout()
            trow.addWidget(_lbl("🛟  STUCK AT FIRST CONTACT?", "#98a6b8", 11, True))
            trow.addStretch(1)
            tv.addLayout(trow)
            srow = QHBoxLayout()
            self._tc_input = QLineEdit()
            self._tc_input.setPlaceholderText('describe the symptom — e.g. "flashpro won\'t work", "no idcode", "ttyUSB busy"')
            self._tc_input.returnPressed.connect(self._run_troubleshoot)
            srow.addWidget(self._tc_input, 1)
            tbtn = QPushButton("Diagnose"); tbtn.setCursor(Qt.PointingHandCursor)
            tbtn.clicked.connect(self._run_troubleshoot)
            srow.addWidget(tbtn)
            tv.addLayout(srow)
            self._tc_results = QVBoxLayout(); self._tc_results.setSpacing(6)
            tv.addLayout(self._tc_results)
            outer.addWidget(tf)

        # a container the refresh() rebuilds. This page has more natural content (preflight, transport
        # card, chain tree, xsdb target tree, adapter table, capability matrix) than fits in one viewport
        # — without a scroll area, a plain QVBoxLayout has nowhere to put the overflow but to compress
        # every "expanding" child below its natural size (found 2026-08-15: the capability matrix table
        # was squeezed to ~100px against a 178px need, clipping its last row right where the routing-
        # summary text started, reading as a visual overlap). Same QScrollArea pattern already used for
        # Dashboard's Kill Chain / Attack Surface / Shell tabs and the Unlock panel.
        scroll = QScrollArea(); scroll.setWidgetResizable(True); scroll.setFrameShape(QFrame.NoFrame)
        bw = QWidget()
        self.body = QVBoxLayout(bw); self.body.setContentsMargins(0, 0, 0, 8); self.body.setSpacing(12)
        scroll.setWidget(bw)
        outer.addWidget(scroll, 1)

        self.refresh()

    def _run_troubleshoot(self):
        """Diagnose the typed symptom via jtagx.firstcontact and render the ranked blocker cards."""
        while self._tc_results.count():
            it = self._tc_results.takeAt(0)
            if it.widget():
                it.widget().setParent(None)
        symptom = self._tc_input.text().strip()
        if not symptom or _firstcontact is None:
            return
        hits = _firstcontact.diagnose(symptom, limit=3)
        if not hits or hits[0][0] == 0:
            none = _lbl("No strong match — try different words, or see docs/32-first-contact-troubleshooting.md.",
                       "#5e6b7c", 11)
            none.setWordWrap(True)
            self._tc_results.addWidget(none)
            return
        for score, b in hits:
            card = QFrame(); card.setProperty("cls", "cap")
            cv = QVBoxLayout(card); cv.setContentsMargins(10, 8, 10, 8); cv.setSpacing(3)
            sev_col = "#f2685f" if b["severity"] == "block" else "#e7b04b"
            head = QHBoxLayout()
            head.addWidget(_lbl(f"[{b['stage']}] {b['id']}", "#e7ecf3", 11, True))
            head.addStretch(1)
            head.addWidget(_lbl(b["severity"].upper(), sev_col, 10, True))
            cv.addLayout(head)
            sym = _lbl(b["symptom"], "#98a6b8", 10.5); sym.setWordWrap(True)
            cv.addWidget(sym)
            for f in b["fix"]:
                fl = _lbl(f"→ {f}", "#3ecf8e", 10.5); fl.setWordWrap(True)
                cv.addWidget(fl)
            self._tc_results.addWidget(card)

    # ------------------------------------------------------------------ refresh
    def refresh(self):
        # detect adapters live, then rebuild every dynamic panel
        present, present_ids, sel_backend = [], set(), None
        adapter_line = "no adapter — showing profile defaults"
        if detect_adapters is not None:
            try:
                present = detect_adapters()          # live lsusb; [] offline/none plugged
            except Exception:
                present = []
            present_ids = {c["usb_id"] for c in present}
            if present:
                usable = match_profile(self.prof.get("adapters", []), present)["usable"] if match_profile else []
                first = (usable or present)[0]
                adapter_line = f"{first['name']} ({first['usb_id']})"
                try:
                    sel_backend = for_profile(self.prof, present).backend
                except Exception:
                    sel_backend = first.get("backend")

        self._clear(self.body)
        pf = self._preflight_panel(present)
        if pf is not None:
            self.body.addWidget(pf)
        self.body.addWidget(self._transport_card(present, sel_backend, adapter_line))
        self.body.addWidget(self._chain_tree(), 1)
        tt = self._target_tree(sel_backend)
        if tt is not None:
            self.body.addWidget(tt, 1)
        self.body.addWidget(self._adapter_table(present_ids), 1)
        cm = self._capability_matrix_panel(present)
        if cm is not None:
            self.body.addWidget(cm, 1)

        n = len(present)
        self.refresh_note.setText(f"{n} adapter(s) detected" if n else "no adapter detected (offline)")

    def _clear(self, layout):
        while layout.count():
            it = layout.takeAt(0)
            w = it.widget()
            if w is not None:
                w.setParent(None)

    # ------------------------------------------------------------------ panels
    def _preflight_panel(self, present):
        """The go/no-go screen: can we actually REACH this board with what's plugged in + installed?
        GO / BLOCKED + the fix (adapters, backend software, transport) — jtagx.preflight."""
        if _preflight is None or not self.prof:
            return None
        try:
            verdict, checks = _preflight(self.prof, present)
        except Exception:
            return None
        pf = QFrame(); pf.setProperty("cls", "panel")
        v = QVBoxLayout(pf); v.setContentsMargins(12, 10, 12, 10); v.setSpacing(5)
        vcol = "#3ecf8e" if verdict == "GO" else "#f2685f"
        vtxt = "✓ GO — you can reach this board" if verdict == "GO" else "✗ BLOCKED — fix the ✗ below before you start"
        hdr = QLabel(f"⛑  PRE-FLIGHT:  {vtxt}")
        hdr.setStyleSheet(f"color:{vcol}; font-size:12px; font-weight:700;"); hdr.setWordWrap(True)
        v.addWidget(hdr)
        icon = {"GO": ("✓", "#3ecf8e"), "BLOCKED": ("✗", "#f2685f"), "WARN": ("⚠", "#e7b04b"),
                "info": ("·", "#8a97a8")}
        for s, t, d in checks:
            gl, col = icon.get(s, ("·", "#8a97a8"))
            row = QLabel(f"{gl}  {t}: {d}"); row.setWordWrap(True)
            row.setStyleSheet(f"color:{col if s in ('BLOCKED','WARN') else '#98a6b8'}; font-size:11px;")
            v.addWidget(row)
        return pf

    def _transport_card(self, present, sel_backend, adapter_line):
        card = QFrame(); card.setProperty("cls", "panel")
        g = QGridLayout(card); g.setContentsMargins(16, 12, 16, 12); g.setHorizontalSpacing(28); g.setVerticalSpacing(6)
        det = f"  ·  {len(present)} adapter(s) detected" if present else "  ·  no adapter detected (offline)"
        g.addWidget(_lbl("⛓  TRANSPORT & VERDICT" + det, "#98a6b8", 11, True), 0, 0, 1, 4)
        backend = sel_backend or "openocd"
        backend_val = backend + (" 0.12" if backend == "openocd" else " (vendor)")
        kv = [("Adapter", adapter_line), ("Backend", backend_val),
              ("Transport", "JTAG · 10 MHz"), ("Target", self.prof.get("name", self.soc))]
        for i, (k, val) in enumerate(kv):
            g.addWidget(_lbl(k, "#5e6b7c"), 1 + i // 2, (i % 2) * 2)
            g.addWidget(_lbl(val, "#e7ecf3"), 1 + i // 2, (i % 2) * 2 + 1)
        # Only the home ZCU102 is a KNOWN-open baseline; every other board's verdict is UNKNOWN until
        # jtag-access-check.tcl / cortexm-access-check.tcl is actually run against it.
        if self.soc == "zynqmp":
            vtext, vcol = "● Access verdict: OPEN", ("#3ecf8e", "62,207,142")
        else:
            vtext, vcol = "◌ Access verdict: UNKNOWN — run access-check", ("#e7b04b", "231,176,75")
        verdict = QLabel(vtext)
        verdict.setStyleSheet(f"color:{vcol[0]}; background:rgba({vcol[1]},0.10);"
                              f"border:1px solid rgba({vcol[1]},0.30); border-radius:8px; padding:5px 12px; font-weight:600;")
        g.addWidget(verdict, 3, 0, 1, 4)
        return card

    def _chain_tree(self):
        cf = QFrame(); cf.setProperty("cls", "panel")
        cv = QVBoxLayout(cf); cv.setContentsMargins(8, 8, 8, 8); cv.setSpacing(4)
        # ZynqMP is the home board with a known reference chain; other boards haven't been scanned yet,
        # so show what the profile EXPECTS + how to read the live chain, not the ZynqMP TAPs.
        if self.soc != "zynqmp":
            m = (self.prof or {}).get("match", {})
            fam = m.get("family", "?"); mt = m.get("min_taps")
            pids = m.get("part_ids", [])
            cv.addWidget(_lbl("  JTAG CHAIN  ·  not scanned", "#98a6b8", 11, True))
            exp = f"expected: {fam} family" + (f", ≥{mt} TAP(s)" if mt else "")
            if pids:
                exp += "  ·  IDCODEs " + ", ".join(f"0x{p:08X}" if isinstance(p, int) else str(p) for p in pids)
            note = _lbl(exp + ".\nRun discover.tcl (or tools/probe-board.sh) to read the live chain, then "
                        "access-check for the verdict.", "#8a97a8", 11)
            note.setWordWrap(True); cv.addWidget(note)
            return cf
        cv.addWidget(_lbl("  JTAG CHAIN  ·  2 TAPs", "#98a6b8", 11, True))
        tree = QTreeWidget(); tree.setHeaderHidden(True); tree.setRootIsDecorated(True)
        for name, idc in CHAIN:
            it = QTreeWidgetItem([f"{name}    0x{idc:08X}    {decode_idcode(idc)}"])
            tree.addTopLevelItem(it); it.setExpanded(True)
            if idc == 0x5BA00477:
                for ap, idr, desc in APS:
                    it.addChild(QTreeWidgetItem([f"{ap}   IDR {idr}   {desc}"]))
        cv.addWidget(tree)
        return cf

    def _target_tree(self, sel_backend):
        # what `xsdb targets` enumerates over a SmartLynq2 — the cores you select before mrd/stop.
        if zynqmp_reference is None or not self.soc.startswith("zynqmp"):
            return None
        roots = zynqmp_reference()
        live = (sel_backend == "hw_server")
        tf = QFrame(); tf.setProperty("cls", "panel")
        tv = QVBoxLayout(tf); tv.setContentsMargins(8, 8, 8, 8); tv.setSpacing(4)
        src = "hw_server (selected backend)" if live else "reference — install hw_server/xsdb to enumerate live"
        tv.addWidget(_lbl(f"  ⌗ xsdb DEBUG TARGETS  ·  {src}  —  click a core to copy its xsdb command",
                          "#98a6b8", 11, True))
        ttree = QTreeWidget(); ttree.setHeaderHidden(True); ttree.setRootIsDecorated(True)
        stack = []   # (level, QTreeWidgetItem)
        for n in flatten_targets(roots):
            st = f"   ({n.state})" if n.state else ""
            item = QTreeWidgetItem([f"[{n.tid:>2}] {n.name}{st}   <{n.role}>"])
            item.setForeground(0, QColor(ROLE_COL.get(n.role, "#e7ecf3")))
            sel = self._selector_for(n)
            if sel:
                item.setData(0, Qt.UserRole, sel)
                item.setToolTip(0, f"click → copy the xsdb command to read {sel}")
            while stack and stack[-1][0] >= n.level:
                stack.pop()
            (stack[-1][1].addChild if stack else ttree.addTopLevelItem)(item)
            item.setExpanded(True)
            stack.append((n.level, item))
        ttree.itemClicked.connect(self._on_target_click)
        tv.addWidget(ttree)
        self.tgt_note = _lbl("", "#5e6b7c", 11); tv.addWidget(self.tgt_note)
        return tf

    @staticmethod
    def _selector_for(n):
        """Friendly xsdb selector for a debug-target node (only the addressable cores)."""
        if n.role in ("a53", "r5") and n.index is not None:
            return f"{n.role}-{n.index}"
        if n.role in ("pmu", "pl"):
            return n.role
        return None   # structural node (APU/RPU/PSU/TAP) — not a selectable core

    def _on_target_click(self, item, _col):
        sel = item.data(0, Qt.UserRole)
        if not sel or make_transport is None:
            return
        cfg = self.prof.get("openocd_cfg", "openocd/zcu102.cfg")
        t = make_transport("hw_server", cfg=cfg, soc=self.soc, target=sel)
        cmd = t.mem_read(0x0, 0x1000, f"dumps/{sel}.bin").as_shell()
        QApplication.clipboard().setText(cmd)
        self.tgt_note.setText(f"⧉ copied ({sel}):  {cmd[:88]}…")
        try:
            from console_bus import BUS
            BUS.line.emit("i", f"⧉ copied {sel} xsdb command → clipboard")
            BUS.line.emit("t", cmd)
        except Exception:
            pass

    def _adapter_table(self, present_ids):
        af = QFrame(); af.setProperty("cls", "panel")
        av = QVBoxLayout(af); av.setContentsMargins(8, 8, 8, 8); av.setSpacing(6)
        adapters = self.prof.get("adapters", [])
        av.addWidget(_lbl(f"  ADAPTERS FOR THIS BOARD  ·  {len(adapters)} (from profiles/{self.soc}.json)",
                          "#98a6b8", 11, True))
        t = QTableWidget(len(adapters), 6)
        t.setHorizontalHeaderLabels(["Adapter", "Backend", "Transports", "Tier", "Vendor SW", "Present"])
        t.verticalHeader().setVisible(False); t.setShowGrid(False)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        hh = t.horizontalHeader()
        hh.setSectionResizeMode(0, QHeaderView.Stretch)
        for c in range(1, 6):
            hh.setSectionResizeMode(c, QHeaderView.ResizeToContents)
        for r, a in enumerate(adapters):
            t.setItem(r, 0, QTableWidgetItem(a.get("name", a.get("id", "?"))))
            bk = QTableWidgetItem(a.get("backend", ""))
            if a.get("backend") != "openocd":
                bk.setForeground(Qt.yellow)
            t.setItem(r, 1, bk)
            t.setItem(r, 2, QTableWidgetItem(", ".join(a.get("transports", []))))
            tier = a.get("tier", "?")
            ti = QTableWidgetItem(f"tier {tier}"); ti.setForeground(Qt.gray)
            t.setItem(r, 3, ti)
            pill = QLabel("vendor" if a.get("vendor_sw") else "open")
            pill.setAlignment(Qt.AlignCenter)
            col = "#e7b04b" if a.get("vendor_sw") else "#3ecf8e"
            pill.setStyleSheet(f"color:{col}; font-weight:600; font-size:11px;")
            tw = QLabel(f"  {tier.upper()}  "); tw.setAlignment(Qt.AlignCenter)
            tw.setStyleSheet(f"color:#0d1017; background:{TIER_COLOR.get(tier,'#5e6b7c')};"
                             "border-radius:8px; font-weight:700; font-size:11px;")
            t.setCellWidget(r, 3, tw)
            t.setCellWidget(r, 4, pill)
            # Present: ● if any of this adapter's usb_ids is currently plugged in
            here = bool(set(u.lower() for u in a.get("usb_ids", [])) & present_ids)
            pr = QLabel("● detected" if here else "—"); pr.setAlignment(Qt.AlignCenter)
            pr.setStyleSheet(f"color:{'#3ecf8e' if here else '#5e6b7c'}; font-weight:600; font-size:11px;")
            t.setCellWidget(r, 5, pr)
        av.addWidget(t)
        return af

    def _capability_matrix_panel(self, present):
        """The adapter × op capability grid + per-op routing — which adapter runs each JTAG primitive
        on THIS board, and which ops are honestly BLOCKED (fabric-only parts, vendor-tool-only paths)."""
        if capability_matrix is None:
            return None
        rows = capability_matrix(self.prof)
        if not rows:
            return None
        if present and join_present is not None:
            join_present(rows, present)
        cf = QFrame(); cf.setProperty("cls", "panel")
        cv = QVBoxLayout(cf); cv.setContentsMargins(8, 8, 8, 8); cv.setSpacing(6)
        cv.addWidget(_lbl("  CAPABILITY MATRIX  ·  adapter × op  —  what runs where, what's BLOCKED",
                          "#98a6b8", 11, True))
        cols = ["Adapter", "Backend", "Reach"] + [OP_LABEL[o] for o in OPS]
        t = QTableWidget(len(rows), len(cols))
        t.setHorizontalHeaderLabels(cols)
        t.verticalHeader().setVisible(False); t.setShowGrid(False)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        hh = t.horizontalHeader(); hh.setSectionResizeMode(0, QHeaderView.Stretch)
        for c in range(1, len(cols)):
            hh.setSectionResizeMode(c, QHeaderView.ResizeToContents)
        for r, row in enumerate(rows):
            name = ("● " if row.get("present") else "") + row["adapter"]
            t.setItem(r, 0, QTableWidgetItem(name))
            bk = QTableWidgetItem(row["backend"])
            if row["backend"] != "openocd":
                bk.setForeground(Qt.yellow)
            t.setItem(r, 1, bk)
            t.setItem(r, 2, QTableWidgetItem(row["max_tier"]))
            for i, op in enumerate(OPS):
                ok = row["ops"].get(op)
                cell = QLabel("✓" if ok else "·"); cell.setAlignment(Qt.AlignCenter)
                cell.setStyleSheet(f"color:{'#3ecf8e' if ok else '#5e6b7c'}; font-weight:700;")
                t.setCellWidget(r, 3 + i, cell)
        # Cap the table's height at exactly enough for its header + rows, so it displays in full without
        # its own internal scrollbar. Must MEASURE the real row height rather than guess a constant: a
        # guessed "26px/row" (found 2026-08-15, one row too short vs the actual styled 30px) silently
        # clips the last row behind a scrollbar, which then visually runs into the routing-summary text
        # added right after it in the layout — looks like an overlap bug, but the cause is just an
        # undersized budget.
        t.setMaximumHeight(t.horizontalHeader().height() + t.rowHeight(0) * len(rows) + 6)
        cv.addWidget(t)
        # op routing summary — the actionable line: best adapter per op, or BLOCKED + why
        if routing_plan is not None:
            plan = routing_plan(self.prof, present if present else None)
            for op, (chosen, reason) in plan.items():
                ok = chosen is not None
                lbl = _lbl(("→ " if ok else "✗ ") + f"{OP_LABEL[op]}: {reason}",
                           "#8fd39a" if ok else "#f2685f", 10)
                lbl.setWordWrap(True)
                cv.addWidget(lbl)
        return cf


if __name__ == "__main__":
    from PySide6.QtWidgets import QApplication
    app = QApplication(sys.argv)
    w = ChainPage(sys.argv[1] if len(sys.argv) > 1 else "zynqmp")
    w.resize(900, 760); w.setStyleSheet("background:#0d1017; color:#e7ecf3;")
    w.setWindowTitle("Chain & Transport"); w.show()
    sys.exit(app.exec())
