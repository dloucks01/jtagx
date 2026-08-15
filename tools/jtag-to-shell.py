#!/usr/bin/env python3
"""
jtag-to-shell.py -- CLI for the "get a shell / take control via JTAG" planner
(jtagx.jtagtoshell). Turns a board's current state into an ordered, copy-pasteable
runbook: which of the four paths (live-patch / catch-in-flight / cold-boot / persist)
applies, and the exact commands, in order.

Does NOT touch hardware -- it only reads a capture or explicit flags and emits Tcl/
Python commands for the OPERATOR to run (per the project's hands-on-JTAG model).

    # from the newest capture (reads a53.firmware_running / invasive_debug)
    python3 tools/jtag-to-shell.py --from-capture "$(ls -t reports/raw-*.json | head -1)"

    # explicit state (no capture yet, or a different board)
    python3 tools/jtag-to-shell.py --firmware-running --goal shell
    python3 tools/jtag-to-shell.py --idle --goal persist --soc zynqmp

    # want the real secret, not just access
    python3 tools/jtag-to-shell.py --from-capture reports/raw-latest.json --goal secret

    -o report.md   # write the runbook to a file instead of stdout
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.jtagtoshell import plan, from_capture, render_md  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Plan the path from JTAG access to a shell / OS control.")
    ap.add_argument("--from-capture", help="raw-<ts>.json enumeration capture (reads a53 state)")
    grp = ap.add_mutually_exclusive_group()
    grp.add_argument("--firmware-running", action="store_true", help="an OS is already running")
    grp.add_argument("--idle", action="store_true", help="nothing is running (JTAG-idle board)")
    ap.add_argument("--invasive-debug", choices=["open", "gated", "wedged", "unreachable"], default="open")
    ap.add_argument("--goal", choices=["shell", "secret", "persist"], default="shell",
                    help="shell=get in; secret=catch a real credential; persist=survive reboot")
    ap.add_argument("--soc", default="zynqmp")
    ap.add_argument("--have-dump", action="store_true", help="you already have dumps/os-live.bin")
    ap.add_argument("-o", "--out", help="write the runbook markdown to a file instead of stdout")
    a = ap.parse_args()

    if a.from_capture:
        try:
            with open(a.from_capture, encoding="utf-8") as fh:
                raw = json.load(fh)
        except OSError as e:
            sys.exit(f"error: cannot read {a.from_capture}: {e}")
        except json.JSONDecodeError as e:
            sys.exit(f"error: {a.from_capture} is not valid JSON: {e}")
        result = from_capture(raw, goal=a.goal, soc=a.soc)
    else:
        state = {
            "firmware_running": bool(a.firmware_running) and not a.idle,
            "invasive_debug": a.invasive_debug,
            "goal": a.goal,
            "have_dump": a.have_dump,
        }
        result = plan(state, soc=a.soc)

    md = render_md(result)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(md + "\n")
        print(f"wrote {a.out}")
    else:
        print(md)


if __name__ == "__main__":
    main()
