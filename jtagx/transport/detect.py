#!/usr/bin/env python3
"""
jtagx.transport.detect — physical-adapter detection by USB VID:PID.

Answers "which JTAG adapter is actually plugged in, and which backend drives it?" so the GUI/CLI
can auto-select a transport instead of assuming OpenOCD (the assumption that broke the engagement).
Pure/offline-testable: parse_lsusb() takes lsusb text (inject a fixture in tests); detect_adapters()
shells `lsusb` for the live case.
"""
from __future__ import annotations
import re
import subprocess

# Known JTAG-capable adapters keyed by USB VID:PID -> (name, backend, driver, vendor_sw).
# backend matches profiles' adapter allowlist (openocd / hw_server / libero).
KNOWN = {
    "0403:6010": ("FTDI FT2232H (Digilent HS2/SMT2, onboard ZCU102)", "openocd", "ftdi", False),
    "0403:6011": ("FTDI FT4232H (quad; ZCU102 onboard bridge)",        "openocd", "ftdi", False),
    "0403:6014": ("FTDI FT232H (Digilent HS3)",                        "openocd", "ftdi", False),
    "0403:6015": ("FTDI FT-X",                                         "openocd", "ftdi", False),
    "15ba:002a": ("Olimex ARM-USB-OCD-H",                              "openocd", "ftdi", False),
    "1366:0101": ("SEGGER J-Link",                                     "openocd", "jlink", False),
    "1366:0105": ("SEGGER J-Link",                                     "openocd", "jlink", False),
    "1366:1015": ("SEGGER J-Link (newer)",                             "openocd", "jlink", False),
    "0d28:0204": ("ARM CMSIS-DAP / DAPLink",                           "openocd", "cmsis-dap", False),
    "1cbe:00fd": ("TI XDS110 / Tiva CMSIS-DAP",                        "openocd", "cmsis-dap", False),
    "03fd:0008": ("AMD/Xilinx Platform Cable USB II",                  "hw_server", None, True),
    "03fd:0015": ("AMD/Xilinx Platform Cable USB II (alt)",            "hw_server", None, True),
    "03fd:0100": ("AMD/Xilinx SmartLynq / SmartLynq2 (USB)",           "hw_server", None, True),
    "1514:2008": ("Microsemi FlashPro5",                               "libero", None, True),
    "1514:2005": ("Microsemi FlashPro4",                               "libero", None, True),
    "0403:8a98": ("Tigard (FT2232H multi-protocol)",                   "openocd", "ftdi", False),
}

_LSUSB = re.compile(r"ID\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s*(.*)")


def parse_lsusb(text: str) -> list:
    """[(usb_id, raw_description)] from lsusb output. Lowercased ids."""
    out = []
    for ln in text.splitlines():
        m = _LSUSB.search(ln)
        if m:
            out.append((m.group(1).lower(), m.group(2).strip()))
    return out


def classify(usb_id: str, raw_desc: str = "") -> dict:
    """Map a USB id to a known JTAG adapter, or mark it unknown."""
    k = KNOWN.get(usb_id.lower())
    if k:
        name, backend, driver, vendor_sw = k
        return dict(usb_id=usb_id.lower(), name=name, backend=backend, driver=driver,
                    vendor_sw=vendor_sw, known=True, desc=raw_desc)
    return dict(usb_id=usb_id.lower(), name=raw_desc or "unknown device", backend=None,
                driver=None, vendor_sw=None, known=False, desc=raw_desc)


def detect_adapters(lsusb_text: str = None) -> list:
    """Detected JTAG-capable adapters. Pass lsusb_text to stay offline; else shells `lsusb`.
    Returns only entries we recognize as JTAG adapters (known==True)."""
    if lsusb_text is None:
        try:
            lsusb_text = subprocess.run(["lsusb"], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            lsusb_text = ""
    seen = []
    for usb_id, desc in parse_lsusb(lsusb_text):
        c = classify(usb_id, desc)
        if c["known"]:
            seen.append(c)
    return seen


def match_profile(profile_adapters: list, present: list) -> dict:
    """Cross the board's adapter allowlist with what's physically present.

    Returns {"usable": [...], "present_unlisted": [...], "listed_absent": [...]} where `usable`
    is the intersection (allowlisted AND plugged in) — the adapters to actually offer the operator.
    """
    present_ids = {c["usb_id"] for c in present}
    listed_ids = set()
    for ad in profile_adapters or []:
        for uid in ad.get("usb_ids", []) or []:
            listed_ids.add(uid.lower())

    usable, present_unlisted = [], []
    for c in present:
        # allowlisted by explicit usb_id, OR by matching backend when the profile lists no ids
        by_id = c["usb_id"] in listed_ids
        by_backend = any((ad.get("backend") == c["backend"]) for ad in (profile_adapters or []))
        (usable if (by_id or by_backend) else present_unlisted).append({**c, "matched_by": "id" if by_id else ("backend" if by_backend else None)})

    listed_absent = [ad for ad in (profile_adapters or [])
                     if ad.get("usb_ids") and not (set(u.lower() for u in ad["usb_ids"]) & present_ids)]
    return dict(usable=usable, present_unlisted=present_unlisted, listed_absent=listed_absent)
