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

- **Top bar**: target crumb · **board** selector (switches the whole app to another profile —
  Chain/Console/Dashboard/Reports all retarget) · **Transport** selector (Auto / OpenOCD /
  hw_server-xsdb) · **Enumerate** · DAP badge.
- **Icon rail** (left): the 6 pages. **Console** (bottom): always visible, follows the active tab.
- **Status bar**: connection · detected adapter · effective backend · chain · verdict.

## Pages (Ctrl+1..6)

| # | Page | What you do |
|---|------|-------------|
| 1 | **Dashboard** | Hero tiles (click CHAIN→Chain, POSTURE→posture tab, ARTIFACTS→Memory) · 7 center tabs (below) · **Capabilities** (click to run the real command) · chain panel (**right-click a core** → halt/resume/read → console) |
| 2 | **Unlock** | The locked-board plan derived from the newest **real capture**. Click **▶ Run** on an AUTO lever → it runs reopen-debug **and** re-reads the access verdict → marks the lock ✓defeated / ◐partial / ✗resisted. Posture-toggle chips assert a hypothetical lock state per board. ↻ Refresh re-derives. |
| 3 | **Chain** | **🛟 Stuck at first contact?** search box (type a symptom — "flashpro won't work", "no idcode" — get the ranked blocker + concrete fix, `jtagx.firstcontact`) · **pre-flight** GO/BLOCKED verdict (adapter/backend/transport/physical checklist, `jtagx.preflight`) · detected adapters + backend · JTAG chain (IDCODE decode + APs) · **xsdb debug-target tree** (click a core → copy its xsdb command) · per-board adapter allowlist with "● detected" · capability matrix (adapter × op). ↻ Refresh re-scans USB. |
| 4 | **Memory** | Virtualized hex over any dump (dropdown selects the dump; ↻ rescans). **Find** hex bytes (`de ad be ef`) or ASCII (`'text`) → jumps + green-highlights the match. Go-to offset. |
| 5 | **Reports** | Rendered Markdown deliverables. **＋ Generate** runs engagement-report.py from the live capture. **⚡ Stylized HTML** runs `tools/report-html.py` (operator-first: verdict → posture chips → critical findings+actions → next-steps → anomalies) and opens it in your browser. ↻ Refresh. |
| 6 | **Help** | This guide, rendered in-app. |

## Dashboard center tabs

| Tab | What you see |
|---|---|
| **Posture** | Ring (N hardened / M total) + the security-implementation table, derived from the real capture. |
| **Registers** | The §1–16 sweep — search / security-only filter / click-to-decode / right-click *send mrd to console*. A **🧬 Debug topology (CoreSight)** panel sits above the table: components identified from the captured `dap info` text (`jtagx.coresight`) — base address, class, name, part. Honest-empty with an explanation when the capture's DAP exposes no walkable ROM table. |
| **Memory / Report** | Launchers that jump to the full Memory / Reports pages. |
| **Kill Chain** | The ordered objective ladder (jtag-up → debug-open → mem-read → secrets → persistence) for the active board + posture, plus **EXTRACTION AVENUES** (best-first, incl. no-debug ROM loaders) — **▶ run** drops each node's command in the console. `jtagx.attackgraph` + `jtagx.extraction`. |
| **Attack Surface** | Implementation-review misuse hypotheses — where the design could be MISUSED, distinct from CVEs; class-filter chips; **▶ probe** sends the investigation command to the console. Grows via `jtagx/weakness.py`. |
| **→] Shell** | **The capstone.** Goal chips (Get a shell / Catch a credential / Persist) pick the path from `jtagx.jtagtoshell`, auto-detecting board state (firmware running? debug open?) from the newest capture. Each numbered step has a **▶ run** button; the OpenOCD-0.12 code-injection wedge warning is always shown above the steps. |

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
