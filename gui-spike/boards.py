#!/usr/bin/env python3
"""
boards.py — load the board profile registry (profiles/*.json) for the GUI's board selector.

Mirrors tools/board-runner.py's JSONC loader (full-line // or # comments stripped). Each board dict
exposes what the GUI needs to retarget: soc slug, display name, openocd cfg, adapter allowlist, status.
"""
import glob
import json
import os


def _strip_jsonc(text):
    return "".join(ln for ln in text.splitlines(keepends=True)
                   if not ln.lstrip().startswith(("//", "#")))


def load_boards(root):
    """Sorted [{soc,name,cfg,adapters,paradigm,status}] from profiles/*.json (skips _-prefixed)."""
    out = []
    for p in sorted(glob.glob(os.path.join(root, "profiles", "*.json"))):
        if os.path.basename(p).startswith("_"):
            continue
        try:
            prof = json.loads(_strip_jsonc(open(p, encoding="utf-8").read()))
        except Exception:
            continue
        soc = prof.get("soc", "")
        if not soc:
            continue
        out.append({
            "soc": soc,
            "name": prof.get("name", soc),
            "cfg": prof.get("openocd_cfg", f"openocd/{soc}.cfg"),
            "adapters": prof.get("adapters", []),
            "paradigm": prof.get("paradigm", ""),
            "status": prof.get("status", ""),
        })
    # ZynqMP (the home board) first, then by name
    out.sort(key=lambda b: (b["soc"] != "zynqmp", b["name"].lower()))
    return out
