#!/usr/bin/env python3
"""
JTAGx GUI spike — pywebview version of the v2 main screen.

Purpose: feel the web-tech route. The UI is web/index.html (the exact v2 design,
rendered in the OS webview); this file is the Python side + the JS<->Python bridge.

Run:
    pip install pywebview
    # Linux GTK backend (small, uses system WebKitGTK) also needs, e.g. on Kali:
    #   sudo apt install python3-gi gir1.2-webkit2-4.1 gir1.2-gtk-3.0
    # OR force the Qt/Chromium backend instead:  pip install "pywebview[qt]"
    python3 web_spike.py

What to look at:
  - identical look to the HTML mockup, animations/glow/ring included — for "free."
  - click "Enumerate" (top right): JS calls Api.run_enumerate() over the bridge;
    Python spawns a thread and pushes each line back into the page via
    window.evaluate_js("appendLog(...)"). This is the bridge + streaming plumbing
    you build by hand (vs Qt's native QProcess/signals). In the real app this
    worker would read a subprocess (OpenOCD) stdout instead of a canned list.
  - note: no TCP port is opened — the JS<->Python link is in-process.
"""
import json
import socketserver
import sys
import threading
import time
import webview   # pip install pywebview

# pywebview 6.x serves the page + JS bridge over a local Bottle HTTP server.
# When the webview drops a keep-alive connection (e.g. on reload/close) the
# server thread raises ConnectionResetError/BrokenPipeError and dumps a scary
# (but harmless) traceback. Swallow just those so the console stays clean.
_orig_handle_error = socketserver.BaseServer.handle_error
def _quiet_handle_error(self, request, client_address):
    if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError)):
        return
    return _orig_handle_error(self, request, client_address)
socketserver.BaseServer.handle_error = _quiet_handle_error

LOG_LINES = [
    ('t', "14:02:17 › source openocd/enumerate.tcl"),
    ('i', "Info : JTAG tap: zynqmp.tap  0x14738093 (mfg 0x049, part 0x4738)"),
    ('i', "Info : DAP 0x5ba00477 — ARM CoreSight SoC-400 · 2 APs"),
    ('g', "§4  JTAG_SEC (0xFFCA0038) ......... 0x00000000  → all debug gates enabled"),
    ('w', "§9  AES key (BBRAM/eFuse) ......... zeroed       → not provisioned"),
    ('w', "§16 XMPU/XPPU regions ............. 0            → TrustZone not enforced"),
    ('g', "Info : wrote reports/raw-20260814-140233.json (656 registers)"),
    ('g', "14:02:33 ✓ enumeration complete — 13 open/dev · 0 hardened"),
]

window = None   # set after create_window


class Api:
    """Methods here are callable from JS as window.pywebview.api.<name>()."""

    def run_enumerate(self):
        def worker():
            for kind, text in LOG_LINES:
                time.sleep(0.28)
                # marshal an update into the page. json.dumps handles escaping.
                window.evaluate_js(f"appendLog({json.dumps(kind)}, {json.dumps(text)})")
        threading.Thread(target=worker, daemon=True).start()
        return "started"


if __name__ == "__main__":
    import os
    html_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web", "index.html")
    window = webview.create_window(
        "JTAGx — ZCU102 · XCZU9EG",
        url=html_path,
        js_api=Api(),
        width=1180, height=760,
        background_color="#0d1017",
    )
    webview.start()   # add debug=True for webview devtools
