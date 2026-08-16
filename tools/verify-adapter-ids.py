#!/usr/bin/env python3
"""
verify-adapter-ids.py — adapter VID:PID consistency checker

Two files independently know about vendor-backend (hw_server/libero) adapters:
  - jtagx/transport/detect.py's KNOWN table (usb_id -> backend, used to pick
    a transport backend at runtime)
  - openocd/adapters/99-jtagx-kit.rules Section 2 (usb_id -> udev uaccess rule,
    used to grant USB permissions)

There's no shared source of truth between them. A PID added or corrected in
one file and not the other silently breaks either USB permissions (device
present, backend picked, but LIBUSB_ERROR_ACCESS) or backend classification
(device accessible, but detect.py doesn't know which backend drives it) --
the same silent-propagation failure mode verify-addresses.py exists to catch
for register addresses, applied here to adapter identification.

This only cross-checks adapters detect.py tags with a vendor backend
(hw_server/libero) -- those are the ones where the two files must agree.
Section 2 entries with no vendor-backend comment (Atmel-ICE, WCH-Link,
RP2040 Debug Probe) are uaccess-only grants with no detect.py counterpart to
drift against, so they're intentionally not checked here.

Exit codes:
  0 — all vendor-backend adapters agree between the two files
  1 — at least one mismatch (details printed)
  2 — internal error (either source unparseable)

Usage:
  tools/verify-adapter-ids.py            # validate everything
  tools/verify-adapter-ids.py --quiet    # only print mismatches (good for CI)
"""

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DETECT_PY = REPO_ROOT / "jtagx" / "transport" / "detect.py"
RULES_FILE = REPO_ROOT / "openocd" / "adapters" / "99-jtagx-kit.rules"

VENDOR_BACKENDS = {"hw_server", "libero"}

KNOWN_ENTRY_RE = re.compile(
    r'"([0-9a-fA-F]{4}:[0-9a-fA-F]{4})"\s*:\s*\('
    r'\s*"[^"]*"\s*,\s*"([^"]*)"'
)
ATTRS_RE = re.compile(
    r'ATTRS\{idVendor\}=="([0-9a-fA-F]{4})",\s*ATTRS\{idProduct\}=="([0-9a-fA-F]{4})"'
)


def parse_known(text: str) -> dict:
    """{usb_id (lowercase 'vvvv:pppp'): backend} for every detect.py KNOWN entry."""
    out = {}
    for m in KNOWN_ENTRY_RE.finditer(text):
        usb_id, backend = m.group(1).lower(), m.group(2)
        out[usb_id] = backend
    return out


def parse_rules_section2(text: str) -> dict:
    """{usb_id (lowercase 'vvvv:pppp'): backend_hint or None} for Section 2 entries.

    backend_hint is inferred from the nearest preceding (non-blank-separated)
    comment block mentioning hw_server or libero.
    """
    lines = text.splitlines()
    try:
        start = next(i for i, ln in enumerate(lines) if "Section 2" in ln)
    except StopIteration:
        raise ValueError("couldn't find 'Section 2' marker in rules file")
    try:
        end = next(i for i, ln in enumerate(lines) if 'LABEL="jtagx_kit_rules_end"' in ln)
    except StopIteration:
        end = len(lines)

    out = {}
    comment_buf = []
    for ln in lines[start:end]:
        stripped = ln.strip()
        if not stripped:
            comment_buf = []
            continue
        if stripped.startswith("#"):
            comment_buf.append(stripped)
            continue
        m = ATTRS_RE.search(ln)
        if not m:
            continue
        usb_id = f"{m.group(1).lower()}:{m.group(2).lower()}"
        comment_text = " ".join(comment_buf).lower()
        hint = None
        for backend in VENDOR_BACKENDS:
            if backend in comment_text:
                hint = backend
                break
        out[usb_id] = hint
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quiet", action="store_true", help="only print mismatches")
    args = ap.parse_args()

    if not DETECT_PY.exists():
        print(f"error: {DETECT_PY} not found", file=sys.stderr)
        return 2
    if not RULES_FILE.exists():
        print(f"error: {RULES_FILE} not found", file=sys.stderr)
        return 2

    try:
        known = parse_known(DETECT_PY.read_text())
        rules = parse_rules_section2(RULES_FILE.read_text())
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    mismatches = []

    for usb_id, backend in known.items():
        if backend not in VENDOR_BACKENDS:
            continue
        if usb_id not in rules:
            mismatches.append(
                f"{usb_id}: detect.py KNOWN lists backend={backend!r}, but no matching "
                f"udev rule exists in {RULES_FILE.relative_to(REPO_ROOT)} Section 2 -- "
                f"the device would pick this backend but hit LIBUSB_ERROR_ACCESS"
            )
        elif rules[usb_id] != backend:
            mismatches.append(
                f"{usb_id}: detect.py KNOWN says backend={backend!r}, but the udev rule's "
                f"comment implies backend={rules[usb_id]!r} -- classification disagreement"
            )

    for usb_id, hint in rules.items():
        if hint is None:
            continue
        if usb_id not in known:
            mismatches.append(
                f"{usb_id}: udev rule comment implies backend={hint!r}, but detect.py's "
                f"KNOWN table has no entry for this VID:PID -- backend would never be selected"
            )

    if mismatches:
        print(f"FAIL: {len(mismatches)} adapter-ID mismatch(es) between detect.py and 99-jtagx-kit.rules:")
        for m in sorted(mismatches):
            print(f"  - {m}")
        return 1

    if not args.quiet:
        print(f"OK: {sum(1 for b in known.values() if b in VENDOR_BACKENDS)} vendor-backend "
              f"adapter(s) agree between detect.py and 99-jtagx-kit.rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
