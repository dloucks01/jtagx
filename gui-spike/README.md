# GUI spike — Qt vs pywebview

Two throwaway skeletons of the same v2 main screen, so we can *feel* the two
frameworks before committing. Not production code — a decision aid.

## Run them

**Qt (PySide6):**
```bash
pip install PySide6
python3 gui-spike/qt_spike.py
```

**pywebview (web-tech in the OS webview):**
```bash
pip install pywebview
# Linux GTK backend (small; uses system WebKitGTK). On Kali/Debian also:
sudo apt install python3-gi gir1.2-webkit2-4.1 gir1.2-gtk-3.0
# ...or force the heavier Qt/Chromium backend instead:  pip install "pywebview[qt]"
python3 gui-spike/web_spike.py
```

Both open a ~1180×760 window. Click **Enumerate** (top-right) in each — it streams
fake OpenOCD lines into the bottom console.

## What to compare

| Feel this | Qt spike | pywebview spike |
|---|---|---|
| **Look / finish** | good, but flatter — no glow, no soft shadow, the posture "ring" is a plain number, no hover animation | the full v2: gradient glow, soft shadows, conic ring, hover/pulse animations |
| **Dense data** | the Posture tab is a real table widget — resize columns, scroll; imagine 656 registers / a hex view here | DOM table; fine at this size, needs a virtual-list lib for huge dumps |
| **Streaming** | background `QThread` → Qt signal → console (native; real app swaps in `QProcess` stdout) | JS calls `Api.run_enumerate()` over the bridge → Python thread → `evaluate_js("appendLog…")` (plumbing you build) |
| **Startup / memory** | fast, light, native | webview init slightly heavier |
| **Ports** | none | none (in-process bridge — no TCP) |

## What each file is
- `qt_spike.py` — single-file PySide6 app (QSS dark theme, QTableWidget, QThread stream).
- `web_spike.py` — pywebview host + the `Api` bridge class that streams into the page.
- `web/index.html` — the actual UI (identical v2 design); this *is* the web frontend.

## The takeaway to judge
The web version looks better with less effort and stays small, but the UI lives in
HTML/CSS/JS with a bridge. The Qt version is pure-Python with native, virtualized
data widgets and native subprocess streaming, but the last ~20% of visual finish is
extra work and the binary is bigger. Pick the trade you'd rather live with.
