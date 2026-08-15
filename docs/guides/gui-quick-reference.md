# GUI Quick Reference — JTAGx

The one-screen operator guide to the PySide6 app (`gui-spike/jtagx_app.py`). The GUI is a *driver*:
it builds and streams the real commands; **you drive all live JTAG** (nothing runs on its own except
what you click/type). Everything it shows is the **real** captured posture, detected adapters, and
dumps — no synthetic/demo data.

## Launch

```bash
python3 gui-spike/jtagx_app.py          # needs python3-pyside6.qtwidgets/.qtgui/.qtcore
```
Custom binary paths (optional): `OPENOCD=/path/to/openocd`, `JTAGX_XSDB=/path/to/xsdb`.
Packaged builds write outputs to `~/.local/share/jtagx` (override with `JTAGX_DATA`).

## Layout

- **Top bar**: target crumb · **Transport** selector (Auto / OpenOCD / hw_server-xsdb) · **Enumerate** · DAP badge.
- **Icon rail** (left): the 6 pages. **Console** (bottom): always visible, follows the active tab.
- **Status bar**: connection · detected adapter · effective backend · chain · verdict.

## Pages (Ctrl+1..6)

| # | Page | What you do |
|---|------|-------------|
| 1 | **Dashboard** | Hero tiles (click CHAIN→Chain, POSTURE→posture tab, ARTIFACTS→Memory) · posture ring + table · **Registers** (search / security-only / click-to-decode / right-click copy or *send mrd to console*) · **Attack Surface** (implementation-review misuse hypotheses — where the design could be MISUSED, distinct from CVEs; **▶ probe** sends the investigation command to the console; grows via `jtagx/weakness.py`) · **Capabilities** (click to run the real command) · chain panel (**right-click a core** → halt/resume/read → console) |
| 2 | **Unlock** | The locked-board plan derived from the newest **real capture**. Click **▶ Run** on an AUTO lever → it runs reopen-debug **and** re-reads the access verdict → marks the lock ✓defeated / ◐partial / ✗resisted. ↻ Refresh re-derives. |
| 3 | **Chain** | Detected adapters + backend · JTAG chain (IDCODE decode + APs) · **xsdb debug-target tree** (click a core → copy its xsdb command) · per-board adapter allowlist with "● detected". ↻ Refresh re-scans USB. |
| 4 | **Memory** | Virtualized hex over any dump (dropdown selects the dump; ↻ rescans). **Find** hex bytes (`de ad be ef`) or ASCII (`'text`) → jumps + green-highlights the match. Go-to offset. |
| 5 | **Reports** | Rendered Markdown deliverables. **＋ Generate** runs engagement-report.py from the live capture; ↻ Refresh. |
| 6 | **Help** | This guide, rendered in-app. |

## Console (the command line)

Always docked at the bottom; **every tab feeds it** (commands + output) and you can type your own.
`▾` collapses it. Filter chips (All/Info/Warn/§) + search; **Save** the log; **Clear**.

- **Slash-commands** (Tab-completes): `/help /enumerate /scan /targets /verify /unlock`
  `/dump <addr> <size> [out] /posture /report /adapters /backend [x] /clear`.
- **Backend-aware primitives** (routed through the Transport selector): `mrd`/`mdw <addr> [n]`,
  `mww`/`mwr <addr> <val>`, `halt`, `run`, `scan`. The same `mrd 0x…` becomes an OpenOCD `mdw` or an
  xsdb `mrd` depending on the selected backend. OpenOCD-only capabilities are gated (with the XVC hint)
  when a non-OpenOCD backend is active.
- **Anything else** runs as a raw shell command (from the repo root). **Tab** completes commands and
  file paths; **↑/↓** recall history.

## Cross-links (the dashboard is connected)

- **Posture row → register**: click a posture row → jumps to that register in the Registers tab with
  its bit-fields decoded (why the verdict reads open/hardened).
- **Register → console**: right-click a register → *Send `mrd 0xADDR` to console* → run → the live
  read-back appears (backend-routed), matching the captured value.
- **Chain core → console**: right-click A53/R5/PMU → Halt / Resume / Read → a backend-scoped command
  in the console (hw_server targets the specific core; OpenOCD halts the configured target).
- **Dump done → Memory**: a successful Dump offers to open the artifact in the hex view.
- **Enumerate → Dashboard**: streams into the console and refreshes posture/hero on completion.

## Shortcuts

`Ctrl+1..6` pages · `Ctrl+E` Enumerate · `Ctrl+R` refresh the current page · `Tab` complete · `↑/↓` history.

## Notes

- Live JTAG is operator-driven; destructive/OS-halting ops (e.g. Dump DDR halts the OS) confirm first.
- Backend = **Auto** picks the plugged-in adapter (prefers OpenOCD); pin OpenOCD or hw_server explicitly
  for a specific engagement (e.g. a SmartLynq2 → hw_server/xsdb).
- Offline rehearsal (no board): point `$OPENOCD`/`$JTAGX_XSDB` at `tools/mock-openocd.py`/`mock-xsdb.py`
  — a *test* aid, not part of the GUI. See the mock smoketests.
