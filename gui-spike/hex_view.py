#!/usr/bin/env python3
"""
hex_view.py — a virtualized hex viewer (QTableView + QAbstractTableModel).

Demonstrates Qt's dense-data strength: opens a multi-MB dump and scrolls its million-plus rows
smoothly because the model is virtualized (only visible rows are fetched). This is the concrete
reason the project picked Qt over web for the data-heavy views.

Offset column + 16 hex bytes + ASCII gutter, with a go-to-offset box. Embedded as the app's
"Memory / Hex" page (gui-spike/jtagx_app.py).
"""
import os, sys
from PySide6.QtCore import Qt, QAbstractTableModel, QModelIndex
from PySide6.QtGui import QFont, QColor
from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QTableView,
    QLineEdit, QPushButton, QHeaderView, QAbstractItemView,
)


class HexModel(QAbstractTableModel):
    def __init__(self, data=b""):
        super().__init__()
        self._d = b""
        self._rows = 0
        self.set_data(data)

    def set_data(self, data):
        self.beginResetModel()
        self._d = data
        self._rows = (len(data) + 15) // 16
        self.endResetModel()

    def rowCount(self, parent=QModelIndex()):
        return self._rows

    def columnCount(self, parent=QModelIndex()):
        return 17  # 16 hex byte columns + 1 ASCII column

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None
        r, c = index.row(), index.column()
        base = r * 16
        if role == Qt.DisplayRole:
            if c < 16:
                i = base + c
                return f"{self._d[i]:02X}" if i < len(self._d) else ""
            chunk = self._d[base:base + 16]
            return "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        if role == Qt.TextAlignmentRole and c < 16:
            return int(Qt.AlignCenter)
        if role == Qt.ForegroundRole and c < 16:
            i = base + c
            if i < len(self._d) and self._d[i] == 0:
                return QColor("#3a4453")   # dim the zeros so real data stands out
        return None

    def headerData(self, section, orientation, role=Qt.DisplayRole):
        if role != Qt.DisplayRole:
            return None
        if orientation == Qt.Horizontal:
            return "ASCII" if section == 16 else f"{section:X}"
        return f"{section * 16:08X}"   # row header = byte offset


class HexView(QWidget):
    def __init__(self, path=None, base=0):
        super().__init__()
        self.setAttribute(Qt.WA_StyledBackground, True)
        self._base = base
        v = QVBoxLayout(self); v.setContentsMargins(14, 12, 14, 12); v.setSpacing(8)
        bar = QHBoxLayout()
        self.file_lbl = QLabel("(no file loaded)")
        self.file_lbl.setStyleSheet("color:#98a6b8; font-size:12px;")
        bar.addWidget(self.file_lbl); bar.addStretch(1)
        lo = QLabel("go to offset:"); lo.setStyleSheet("color:#98a6b8;")
        bar.addWidget(lo)
        self.goto = QLineEdit(); self.goto.setFixedWidth(130); self.goto.setPlaceholderText("0x1000")
        self.goto.setStyleSheet("background:#141922; color:#e7ecf3; border:1px solid #232c39;"
                                "border-radius:7px; padding:4px 8px;")
        self.goto.returnPressed.connect(self._goto); bar.addWidget(self.goto)
        gob = QPushButton("Go"); gob.clicked.connect(self._goto)
        gob.setStyleSheet("background:#1a2230; color:#cdd7e4; border:1px solid #2c3644;"
                          "border-radius:7px; padding:4px 12px;")
        bar.addWidget(gob)
        v.addLayout(bar)

        self.model = HexModel()
        self.table = QTableView()
        self.table.setModel(self.model)
        self.table.setFont(QFont("DejaVu Sans Mono", 10))
        self.table.setShowGrid(False)
        self.table.setSelectionBehavior(QAbstractItemView.SelectItems)
        self.table.setStyleSheet(
            "QTableView{background:#0b0e14; color:#c7cfdb; border:1px solid #232c39; border-radius:10px;"
            " gridline-color:#161b23; selection-background-color:#2a4a7a;}"
            "QHeaderView::section{background:#10151d; color:#5e6b7c; border:0;"
            " border-bottom:1px solid #232c39; padding:3px 6px; font-size:10px;}")
        vh = self.table.verticalHeader(); vh.setDefaultSectionSize(20)
        vh.setSectionResizeMode(QHeaderView.Fixed)
        hh = self.table.horizontalHeader()
        for c in range(16):
            self.table.setColumnWidth(c, 30)
        hh.setSectionResizeMode(16, QHeaderView.Stretch)
        v.addWidget(self.table, 1)
        if path:
            self.load(path)

    def load(self, path):
        try:
            data = open(path, "rb").read()
        except Exception as e:
            self.file_lbl.setText(f"error: {e}")
            return
        self.model.set_data(data)
        self.file_lbl.setText(
            f"📄 {os.path.basename(path)}   ·   {len(data):,} bytes   ·   "
            f"{self.model.rowCount():,} rows  (virtualized)")

    def _goto(self):
        t = self.goto.text().strip()
        if not t:
            return
        try:
            off = int(t, 0)
        except ValueError:
            return
        off = max(0, off - self._base)
        row = off // 16
        idx = self.model.index(row, 0)
        self.table.scrollTo(idx, QAbstractItemView.PositionAtTop)
        self.table.selectRow(row)


if __name__ == "__main__":   # standalone: python3 hex_view.py <file>
    app = QApplication(sys.argv)
    path = sys.argv[1] if len(sys.argv) > 1 else None
    w = HexView(path); w.resize(760, 640); w.setStyleSheet("background:#0d1017;")
    w.setWindowTitle("hex view"); w.show()
    sys.exit(app.exec())
