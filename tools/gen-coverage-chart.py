#!/usr/bin/env python3
"""
gen-coverage-chart.py — GENERATE the board coverage/confidence chart from live data, so it can never
drift from the code. Reads profiles/*.json + the capability matrix + the unlock engine + the weakness
layer, assigns each board a confidence tier by a rubric, and emits a self-contained HTML page (the same
one previously hand-authored).

    tools/gen-coverage-chart.py -o board-coverage.html      # write the chart
    tools/gen-coverage-chart.py --counts                    # just print the tier tally (for CI)

The tier rubric (only ZynqMP is silicon-proven; everything else is honest about being mock-only):
  proven    = the home board (zynqmp), validated on real silicon
  ready     = a runnable unlock lever exists (mock-rehearsed), or a curated full-model board (zynq7000/SF2)
  scaffold  = OpenOCD reaches exploitation but no modeled lever
  vendor    = no CPU debug path (mem BLOCKED) and no readback lever
"""
import argparse
import glob
import json
import os
import sys
import html as _html

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jtagx.transport import capability_matrix, route_op  # noqa: E402
from jtagx.unlock import security_model, _ENGAGE_POSTURE  # noqa: E402
from jtagx.weakness import misuse_findings  # noqa: E402
from jtagx.extraction import extraction_plan  # noqa: E402

PROFILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "profiles")
CURATED_READY = {"zynq7000", "smartfusion2"}
REACH_LABEL = {"a": "IDCODE", "b": "BSCAN", "c": "mem-AP", "d": "run-ctl", "e": "EXPLOIT"}
TIER = {"proven": ("Live-proven on silicon", "t-proven"),
        "ready": ("Bench-ready — modeled & rehearsed", "t-ready"),
        "scaffold": ("Scaffolded — standard path", "t-scaffold"),
        "vendor": ("Vendor / identify-only", "t-stub")}


def jsonc(p):
    return json.loads("".join(l for l in open(p, encoding="utf-8")
                              if not l.lstrip().startswith(("//", "#"))))


def gather(soc, prof):
    sm = security_model(soc)
    has_lever = any(s.get("cmd") for L in sm for s in L.get("strategies", []))
    readback = any("readback" in s.get("title", "").lower() for L in sm for s in L.get("strategies", []))
    mat = capability_matrix(prof)
    reach = max((r["max_tier"] for r in mat), default="a")
    tier = ("proven" if soc == "zynqmp" else
            "ready" if (has_lever or soc in CURATED_READY) else
            "scaffold" if reach == "e" else "vendor")
    # extraction (deepened): a cable path (mem-AP dump or a vendor ROM loader) → yes; readback-only
    # (fabric) → partial; only chip-off left → no.
    ex = extraction_plan(soc, {}, prof)
    has_cable = any(m["access"] in ("jtag", "rom-loader") for m in ex)
    has_readback = any(m["access"] == "readback" for m in ex)
    return {
        "soc": soc, "name": prof.get("name", soc), "para": prof.get("paradigm", ""), "tier": tier,
        "identify": "yes", "enumerate": "yes" if prof.get("enumerate") else "no",
        "extract": "yes" if has_cable else ("part" if has_readback else "no"),
        "unlock": "yes" if has_lever else ("part" if sm else "no"),
        "persist": "yes" if prof.get("reflash") else "no",
        "attack": len(misuse_findings(soc, _ENGAGE_POSTURE.get(soc, {}))),
        "reach": REACH_LABEL.get(reach, reach),
        "note": _note(soc, sm, tier),
    }


def _note(soc, sm, tier):
    if soc == "zynqmp":
        return "Live on ZCU102: captures, VxWorks bring-up, breakpoint capture, reopen→verify."
    if sm:
        L = sm[0]
        lev = next((s for s in L["strategies"] if s.get("cmd")), None)
        if lev:
            d = " (destructive)" if lev.get("destructive") else ""
            return f"{lev['title']}{d} — reopen→verify mock-rehearsed."
        return f"{L['name']}: {L['enforcement'][:70]}"
    return "OpenOCD scan/dump on an OPEN port; lock-defeat not modeled."


def all_boards():
    out = []
    for p in sorted(glob.glob(os.path.join(PROFILES, "*.json"))):
        if os.path.basename(p).startswith("_"):
            continue
        try:
            d = jsonc(p)
        except Exception:
            continue
        if d.get("soc"):
            out.append(gather(d["soc"], d))
    # proven, then ready, scaffold, vendor; alpha within tier
    order = {"proven": 0, "ready": 1, "scaffold": 2, "vendor": 3}
    out.sort(key=lambda b: (order[b["tier"]], b["name"].lower()))
    return out


CSS = """
:root{--ground:#eef1f5;--panel:#fff;--panel-2:#f6f8fb;--ink:#111821;--ink-dim:#5a6673;--ink-faint:#8996a4;
--line:#dde3ea;--line-soft:#e7ecf1;--accent:#0e7c8b;--proven:#0e9f6e;--ready:#0b83c9;--scaffold:#b5730a;--stub:#d1522f;}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){--ground:#0a0e13;--panel:#121a24;--panel-2:#0e151d;
--ink:#e6edf5;--ink-dim:#8a97a6;--ink-faint:#5d6a79;--line:#1d2733;--line-soft:#161f29;--accent:#35d6c4;
--proven:#34d399;--ready:#45b6f0;--scaffold:#f0b429;--stub:#f2765f;}}
:root[data-theme=dark]{--ground:#0a0e13;--panel:#121a24;--panel-2:#0e151d;--ink:#e6edf5;--ink-dim:#8a97a6;
--ink-faint:#5d6a79;--line:#1d2733;--line-soft:#161f29;--accent:#35d6c4;--proven:#34d399;--ready:#45b6f0;--scaffold:#f0b429;--stub:#f2765f;}
*{box-sizing:border-box}body{background:var(--ground);color:var(--ink);margin:0;font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;line-height:1.5}
.wrap{max-width:1180px;margin:0 auto;padding:44px 28px 72px}
.eyebrow{font:600 11px/1 ui-monospace,monospace;letter-spacing:.22em;text-transform:uppercase;color:var(--accent);margin:0 0 14px}
h1{font-size:clamp(30px,5vw,44px);line-height:1.04;margin:0 0 12px;font-weight:750;letter-spacing:-.02em}
.lede{color:var(--ink-dim);max-width:66ch;font-size:15px;margin:0}.lede b{color:var(--ink);font-weight:650}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:var(--line);border:1px solid var(--line);border-radius:12px;overflow:hidden;margin:26px 0 4px}
.stat{background:var(--panel);padding:16px 18px}.stat .n{font:700 30px/1 ui-monospace,monospace;font-variant-numeric:tabular-nums}.stat .l{font-size:12px;color:var(--ink-dim);margin-top:6px}
.s-proven .n{color:var(--proven)}.s-ready .n{color:var(--ready)}.s-scaffold .n{color:var(--scaffold)}
.tier-label{display:flex;align-items:center;gap:11px;margin:34px 0 12px}.tier-label .bar{width:4px;height:18px;border-radius:2px}
.tier-label h2{font-size:14px;margin:0;font-weight:700}.tier-label .count{font:600 12px/1 ui-monospace,monospace;color:var(--ink-faint)}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--panel)}
table{border-collapse:collapse;width:100%;min-width:820px}
thead th{text-align:center;font:600 10.5px/1.3 ui-monospace,monospace;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-faint);padding:13px 8px;border-bottom:1px solid var(--line);background:var(--panel-2)}
thead th.l{text-align:left;padding-left:18px}
tbody td{padding:12px 8px;border-bottom:1px solid var(--line-soft);text-align:center;font-size:13px;vertical-align:middle}
td.board{text-align:left;padding-left:15px;border-left:3px solid transparent}.bname{font-weight:650;font-size:13.5px}
.bmeta{font:500 11px/1.3 ui-monospace,monospace;color:var(--ink-faint);margin-top:2px}
.yes{color:var(--accent);font-size:15px}.part{color:var(--scaffold);font-size:15px}.no{color:var(--ink-faint);opacity:.5}
.as{font:600 13px/1 ui-monospace,monospace}.reach{font:600 11px/1 ui-monospace,monospace;padding:3px 7px;border-radius:5px;background:var(--panel-2);border:1px solid var(--line);color:var(--ink-dim)}
.note{font-size:11.5px;color:var(--ink-dim);text-align:left;padding-left:15px;max-width:36ch}
tr.t-proven td.board{border-left-color:var(--proven)}tr.t-ready td.board{border-left-color:var(--ready)}
tr.t-scaffold td.board{border-left-color:var(--scaffold)}tr.t-stub td.board{border-left-color:var(--stub)}
footer{margin-top:40px;padding-top:22px;border-top:1px solid var(--line);color:var(--ink-dim);font-size:12.5px;max-width:80ch}
footer b{color:var(--ink)}footer code{font-family:ui-monospace,monospace;color:var(--accent);background:var(--panel-2);padding:1px 5px;border-radius:4px;font-size:11.5px}
"""

DOT = {"yes": '<span class="yes">●</span>', "part": '<span class="part">◐</span>',
       "no": '<span class="no">—</span>'}
TIER_COLOR = {"proven": "var(--proven)", "ready": "var(--ready)", "scaffold": "var(--scaffold)",
              "vendor": "var(--stub)"}


def _row(b):
    e = _html.escape
    cells = "".join(f"<td>{DOT[b[k]]}</td>" for k in ("identify", "enumerate", "extract", "unlock", "persist"))
    return (f'<tr class="{TIER[b["tier"]][1]}">'
            f'<td class="board"><div class="bname">{e(b["name"])}</div>'
            f'<div class="bmeta">{e(b["soc"])} · Par {e(b["para"] or "?")}</div></td>'
            f'{cells}<td class="as">{b["attack"]}</td>'
            f'<td><span class="reach">{e(b["reach"])}</span></td>'
            f'<td class="note">{e(b["note"])}</td></tr>')


def render(boards):
    counts = {t: sum(1 for b in boards if b["tier"] == t) for t in TIER}
    head = ("Board", "Identify", "Enumerate", "Extract", "Unlock", "Persist", "Attack surf.", "Reach", "Notes")
    thead = "<tr>" + "".join(f'<th class="l">{h}</th>' if h in ("Board", "Notes") else f"<th>{h}</th>"
                             for h in head) + "</tr>"
    sections = []
    for t in ("proven", "ready", "scaffold", "vendor"):
        rows = [b for b in boards if b["tier"] == t]
        if not rows:
            continue
        label, _ = TIER[t]
        sections.append(
            f'<div class="tier-label"><span class="bar" style="background:{TIER_COLOR[t]}"></span>'
            f'<h2>{label}</h2><span class="count">{len(rows)}</span></div>'
            f'<div class="tablewrap"><table><thead>{thead}</thead><tbody>'
            + "".join(_row(b) for b in rows) + "</tbody></table></div>")
    return f"""<title>Board Coverage Matrix</title>
<style>{CSS}</style>
<div class="wrap">
<p class="eyebrow">JTAGx · Platform Coverage</p>
<h1>Board Coverage &amp; Confidence Matrix</h1>
<p class="lede">{len(boards)} SoC families are modeled. <b>One is proven on real silicon</b> (ZCU102);
the rest are code-complete at varying depth and <b>unvalidated on hardware</b>. Generated from
<code>profiles/*.json</code> + the live capability matrix, unlock engine, and weakness layer — so it
cannot drift from the code.</p>
<div class="stats">
<div class="stat s-proven"><div class="n">{counts['proven']}</div><div class="l">Live-proven on silicon</div></div>
<div class="stat s-ready"><div class="n">{counts['ready']}</div><div class="l">Bench-ready (modeled + rehearsed)</div></div>
<div class="stat s-scaffold"><div class="n">{counts['scaffold']}</div><div class="l">Scaffolded (standard path)</div></div>
<div class="stat"><div class="n">{len(boards)}</div><div class="l">Families total</div></div>
</div>
{''.join(sections)}
<footer><p><b>How to read it.</b> <span class="yes">●</span> supported ·
<span class="part">◐</span> partial/vendor · <span class="no">—</span> not available. <b>Attack surf.</b>
= implementation-review misuse hypotheses that fire (<code>jtagx.weakness</code>). Only the ZynqMP row
has touched silicon; "bench-ready" is a mock-backed prediction, not a guarantee. Regenerate with
<code>tools/gen-coverage-chart.py</code>.</p></footer>
</div>
"""


def main():
    ap = argparse.ArgumentParser(description="Generate the board coverage chart from live data.")
    ap.add_argument("-o", "--out", help="write HTML here (default: stdout)")
    ap.add_argument("--counts", action="store_true", help="print the tier tally and exit")
    a = ap.parse_args()
    boards = all_boards()
    if a.counts:
        for t in ("proven", "ready", "scaffold", "vendor"):
            print(f"  {t:9s} {sum(1 for b in boards if b['tier'] == t)}")
        print(f"  total     {len(boards)}")
        return 0
    out = render(boards)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(out)
        print(f"wrote {a.out} ({len(boards)} boards)")
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
