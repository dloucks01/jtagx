#!/usr/bin/env python3
"""
report-html.py — render a raw enumeration capture into a STYLIZED, operator-first
HTML report (vs the dense markdown from interpret.py).

It runs the same rule engine (docs/findings/zynqmp_rules.py) over the capture, then
leads with the four things an operator acts on:
  1. Posture verdicts  — the at-a-glance colored status strip (debug-auth, secure-boot,
     JTAG gates, key state, tamper).
  2. Critical findings — severity-ranked cards, each with the concrete next action.
  3. What to do next    — extraction avenues (best-first), kill-chain reach, unlock levers.
  4. Anomalies          — mismatches / unexpected state (debug-auth cross-check, latched violations).
The raw 656-register dump is de-emphasized into collapsible per-block <details>.

    python3 tools/report-html.py reports/raw-<ts>.json -o reports/report-<ts>.html
    python3 tools/report-html.py "$(ls -t reports/raw-*.json | head -1)"     # newest, auto-named

Self-contained, theme-aware HTML (no external assets) — publishable as an artifact.
"""
import argparse
import html
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)

from interpret_lib import Capture  # noqa: E402
import interpret as _interp        # noqa: E402  (reuse load_json / load_rules / RULES_MODULE)

try:
    from jtagx import debugauth as _dbgauth
except Exception:
    _dbgauth = None
try:
    from jtagx.extraction import extraction_plan as _explan
except Exception:
    _explan = None
try:
    from jtagx import attackgraph as _agraph
except Exception:
    _agraph = None

# Severity → (tone class, glyph, rank). Tone maps to a semantic color token.
_SEV = {
    "CRITICAL": ("crit", "◉", 0),
    "MAJOR":    ("major", "◈", 1),
    "HIGH":     ("major", "◈", 1),
    "MINOR":    ("minor", "○", 2),
    "MED":      ("minor", "○", 2),
    "INFO":     ("info", "●", 3),
}


def _e(s):
    return html.escape(str(s), quote=True)


def _sev(f):
    return _SEV.get((f.severity or "INFO").upper(), ("info", "●", 3))


# ---------------------------------------------------------------------------
# Posture derivation — the capture → flags an operator reads at a glance.
# ---------------------------------------------------------------------------
def derive_posture(cap: Capture) -> dict:
    """Flags used by the status strip + the extraction/attack-graph next-actions."""
    P = {"_source": "capture"}
    dbgen = cap.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN")
    spiden = cap.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN")
    rsa = cap.field("EFUSE.SEC_CTRL.RSA_EN")
    enc = cap.field("EFUSE.SEC_CTRL.ENC_ONLY")
    jtagdis = cap.field("EFUSE.SEC_CTRL.JTAG_DIS")
    P["jtag_open"] = bool(dbgen) if dbgen is not None else True
    P["secure_boot"] = bool(rsa)
    P["aes_encrypt"] = bool(enc)
    if jtagdis:
        P["efuse_jtag_dis"] = True
    return P


def status_chips(cap: Capture) -> list:
    """(label, value, tone) chips — tone: good | warn | crit | info | neutral."""
    chips = []
    spiden = cap.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN")
    dbgen = cap.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN")
    # debug-auth verdict via the cross-arch model, from the per-core DBGAUTHSTATUS if present.
    da_val = None
    a53 = cap.raw.get("a53", {}) if isinstance(cap.raw, dict) else {}
    for n in range(4):
        v = a53.get(f"core{n}_dbgauth")
        if v:
            try:
                da_val = int(str(v), 16)
                break
            except (ValueError, TypeError):
                pass
    if _dbgauth and da_val is not None:
        verdict = _dbgauth.classify("armv8a", {"dbgauthstatus": da_val})["verdict"]
        tone = {"OPEN": "crit", "GATED": "warn", "AUTHENTICATED": "info",
                "LOCKED": "good"}.get(verdict, "neutral")
        chips.append(("debug-auth", verdict, tone))
    elif spiden is not None:
        if spiden:
            chips.append(("debug-auth", "OPEN (secure)", "crit"))
        elif dbgen:
            chips.append(("debug-auth", "OPEN (ns)", "warn"))
        else:
            chips.append(("debug-auth", "gated", "good"))
    # secure boot
    rsa = cap.field("EFUSE.SEC_CTRL.RSA_EN")
    chips.append(("secure-boot", "ENFORCED" if rsa else "OFF (dev)", "good" if rsa else "crit"))
    # encrypted-only boot
    enc = cap.field("EFUSE.SEC_CTRL.ENC_ONLY")
    chips.append(("boot-encrypt", "required" if enc else "off", "good" if enc else "warn"))
    # JTAG hardware disable fuse
    jd = cap.field("EFUSE.SEC_CTRL.JTAG_DIS")
    chips.append(("JTAG fuse", "DISABLED" if jd else "enabled", "good" if jd else "warn"))
    # AES key state (from AES_STATUS zero bits — all-zero = unprovisioned)
    aes = cap.reg("CSU.AES_STATUS")
    if aes is not None:
        allzero = (aes & 0xF00) == 0xF00
        chips.append(("AES key", "empty (dev)" if allzero else "PROVISIONED",
                      "warn" if allzero else "good"))
    # tamper latch
    tamp = cap.reg("CSU.TAMPER_STATUS")
    if tamp is not None:
        chips.append(("tamper", "LATCHED" if tamp else "clear", "crit" if tamp else "good"))
    # SEC_CTRL master lock
    seclock = cap.field("EFUSE.SEC_CTRL.SEC_LOCK")
    chips.append(("policy lock", "SEALED" if seclock else "mutable", "good" if seclock else "warn"))
    return chips


def overall_verdict(chips: list, fired: list) -> tuple:
    """A one-word headline verdict + tone from the worst signal."""
    crit = sum(1 for f in fired if (f.severity or "").upper() == "CRITICAL")
    if any(t == "crit" for _l, _v, t in chips) or crit:
        return ("WIDE OPEN", "crit",
                "Dev/factory baseline — every JTAG attack primitive is available.")
    if any(t == "warn" for _l, _v, t in chips):
        return ("PARTIALLY HARDENED", "warn", "Some gates set; verify the rest against a hardened target.")
    return ("HARDENED", "good", "Security policy is provisioned.")


def _load_profile(soc: str) -> dict:
    """Load profiles/<soc>.json (JSONC — strip // and # comment lines)."""
    import json
    p = os.path.join(ROOT, "profiles", f"{soc}.json")
    if not os.path.exists(p):
        return {}
    try:
        with open(p, encoding="utf-8") as fh:
            body = "".join(ln for ln in fh if not ln.lstrip().startswith(("//", "#")))
        return json.loads(body)
    except (OSError, ValueError):
        return {}


def next_actions(soc: str, P: dict) -> dict:
    out = {"extraction": [], "reach": None, "reach_label": ""}
    prof = _load_profile(soc)
    if _explan:
        try:
            for m in _explan(soc, P, prof)[:5]:
                out["extraction"].append({
                    "method": m["method"], "access": m["access"],
                    "needs_debug": m.get("needs_debug"), "cmd": m.get("cmd", "")})
        except Exception:
            pass
    if _agraph:
        try:
            g = _agraph.plan(soc, P, prof, "capture")
            out["reach"] = g.get("depth")
            out["reach_label"] = g.get("depth_label", "")
        except Exception:
            pass
    return out


def anomalies(fired: list) -> list:
    """Findings that represent a mismatch / unexpected state (not just 'open')."""
    keys = ("mismatch", "disagree", "latched", "violation", "paradox", "unexpected", "anomal")
    out = []
    for f in fired:
        blob = (f.name + " " + (f.conclusion or "")).lower()
        if any(k in blob for k in keys):
            out.append(f)
    return out


# ---------------------------------------------------------------------------
# HTML rendering
# ---------------------------------------------------------------------------
_CSS = """
:root{
  --ground:#eef1f5;--panel:#ffffff;--panel-2:#f5f8fb;--ink:#111821;--ink-dim:#54606d;--ink-faint:#8492a1;
  --line:#dde3ea;--line-soft:#e7ecf1;--accent:#0e7c8b;
  --crit:#d1372b;--crit-bg:#fbeae8;--major:#b5730a;--major-bg:#faf0dd;--minor:#8a7b12;--minor-bg:#f7f4dd;
  --info:#1668b8;--info-bg:#e7f0fb;--good:#0e8a53;--good-bg:#e3f4ea;--neutral:#66727f;--neutral-bg:#eef1f5;
}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){
  --ground:#0a0e13;--panel:#111a24;--panel-2:#0d141d;--ink:#e7edf4;--ink-dim:#93a1b1;--ink-faint:#5c6a79;
  --line:#1d2732;--line-soft:#161f29;--accent:#37cbd8;
  --crit:#f0685c;--crit-bg:#2a1512;--major:#e8a13a;--major-bg:#26190a;--minor:#d6c64a;--minor-bg:#211f0d;
  --info:#4ea3ec;--info-bg:#0e1c2c;--good:#3fbe7f;--good-bg:#0c1f16;--neutral:#7a8795;--neutral-bg:#141c25;
}}
:root[data-theme=dark]{
  --ground:#0a0e13;--panel:#111a24;--panel-2:#0d141d;--ink:#e7edf4;--ink-dim:#93a1b1;--ink-faint:#5c6a79;
  --line:#1d2732;--line-soft:#161f29;--accent:#37cbd8;
  --crit:#f0685c;--crit-bg:#2a1512;--major:#e8a13a;--major-bg:#26190a;--minor:#d6c64a;--minor-bg:#211f0d;
  --info:#4ea3ec;--info-bg:#0e1c2c;--good:#3fbe7f;--good-bg:#0c1f16;--neutral:#7a8795;--neutral-bg:#141c25;
}
*{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);margin:0;line-height:1.5;
  font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1120px;margin:0 auto;padding:40px 24px 80px}
.eyebrow{font:600 11px/1 ui-monospace,monospace;letter-spacing:.22em;text-transform:uppercase;color:var(--accent);margin:0 0 12px}
h1{font-size:clamp(27px,4.5vw,40px);line-height:1.05;margin:0 0 8px;font-weight:750;letter-spacing:-.02em}
.sub{color:var(--ink-dim);font:500 13px/1.5 ui-monospace,monospace;margin:0}
.verdict{display:inline-flex;align-items:center;gap:10px;margin:20px 0 4px;padding:10px 16px;border-radius:11px;
  border:1px solid var(--line);font-weight:750;font-size:15px;letter-spacing:-.01em}
.verdict .dot{width:10px;height:10px;border-radius:50%}
.verdict small{font-weight:500;font-size:12.5px;color:var(--ink-dim);letter-spacing:0}
.t-crit{color:var(--crit)}.b-crit{background:var(--crit-bg)}.d-crit{background:var(--crit)}
.t-major,.t-warn{color:var(--major)}.b-major,.b-warn{background:var(--major-bg)}.d-major,.d-warn{background:var(--major)}
.t-minor{color:var(--minor)}.b-minor{background:var(--minor-bg)}.d-minor{background:var(--minor)}
.t-info{color:var(--info)}.b-info{background:var(--info-bg)}.d-info{background:var(--info)}
.t-good{color:var(--good)}.b-good{background:var(--good-bg)}.d-good{background:var(--good)}
.t-neutral{color:var(--neutral)}.b-neutral{background:var(--neutral-bg)}.d-neutral{background:var(--neutral)}
section{margin-top:38px}
h2.sec{font-size:13px;letter-spacing:.04em;text-transform:uppercase;color:var(--ink-faint);
  margin:0 0 14px;font-weight:700;display:flex;align-items:center;gap:10px}
h2.sec::after{content:"";flex:1;height:1px;background:var(--line)}
.strip{display:flex;flex-wrap:wrap;gap:9px}
.chip{display:inline-flex;flex-direction:column;gap:3px;padding:9px 13px;border-radius:9px;border:1px solid var(--line);
  background:var(--panel);min-width:118px}
.chip .k{font:600 10px/1 ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-faint)}
.chip .v{font:700 14px/1.1 ui-monospace,monospace}
.card{border:1px solid var(--line);border-left-width:4px;border-radius:11px;background:var(--panel);
  padding:15px 17px;margin-bottom:11px}
.card h3{margin:0 0 3px;font-size:15.5px;font-weight:700;letter-spacing:-.01em;display:flex;align-items:center;gap:9px}
.card .glyph{font-size:13px}
.badge{font:700 10px/1 ui-monospace,monospace;letter-spacing:.06em;padding:3px 7px;border-radius:5px;text-transform:uppercase}
.card p{margin:7px 0 0;color:var(--ink-dim);font-size:13.5px}
.actions{margin:11px 0 0;padding:0;list-style:none;display:flex;flex-direction:column;gap:5px}
.actions li{font-size:13px;padding-left:20px;position:relative;color:var(--ink)}
.actions li::before{content:"\\2192";position:absolute;left:0;color:var(--accent);font-weight:700}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(268px,1fr));gap:11px}
.av{border:1px solid var(--line);border-radius:10px;background:var(--panel);padding:13px 15px}
.av .m{font-weight:650;font-size:13.5px;margin-bottom:5px}
.av .tag{font:600 10px/1 ui-monospace,monospace;padding:2px 6px;border-radius:5px;text-transform:uppercase;letter-spacing:.05em}
.av code{display:block;margin-top:8px;font:500 11px/1.5 ui-monospace,monospace;color:var(--ink-dim);
  background:var(--panel-2);border:1px solid var(--line-soft);border-radius:6px;padding:7px 9px;overflow-x:auto;white-space:pre}
.reachbar{display:flex;gap:5px;margin-top:4px}
.reachbar .seg{flex:1;height:9px;border-radius:3px;background:var(--neutral-bg);border:1px solid var(--line)}
.reachbar .seg.on{background:var(--accent);border-color:var(--accent)}
.reachcap{font:600 12px/1 ui-monospace,monospace;color:var(--ink-dim);margin-top:8px}
details.block{border:1px solid var(--line);border-radius:9px;background:var(--panel);margin-bottom:8px;overflow:hidden}
details.block>summary{cursor:pointer;padding:11px 15px;font:650 13px/1 ui-sans-serif,system-ui;list-style:none;
  display:flex;align-items:center;justify-content:space-between}
details.block>summary::-webkit-details-marker{display:none}
details.block>summary .cnt{font:600 11px/1 ui-monospace,monospace;color:var(--ink-faint)}
details.block[open]>summary{border-bottom:1px solid var(--line)}
.regtable{width:100%;border-collapse:collapse;font:500 12px/1.4 ui-monospace,monospace}
.regtable td{padding:6px 15px;border-bottom:1px solid var(--line-soft);vertical-align:top}
.regtable tr:last-child td{border-bottom:none}
.regtable .addr{color:var(--ink-faint);white-space:nowrap}.regtable .name{color:var(--ink)}
.regtable .val{color:var(--accent);text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
.empty{color:var(--ink-faint);font-size:13px;font-style:italic}
footer{margin-top:52px;padding-top:22px;border-top:1px solid var(--line);color:var(--ink-dim);font-size:12px;max-width:78ch}
footer code{font-family:ui-monospace,monospace;color:var(--accent)}
"""


def _chip(label, value, tone):
    return (f'<div class="chip"><span class="k">{_e(label)}</span>'
            f'<span class="v t-{tone}">{_e(value)}</span></div>')


def _finding_card(f):
    tone, glyph, _r = _sev(f)
    acts = ""
    impl = getattr(f, "offensive_implications", None) or []
    if impl:
        acts = ('<ul class="actions">'
                + "".join(f"<li>{_e(a)}</li>" for a in impl[:5]) + "</ul>")
    desc = f'<p>{_e(f.description)}</p>' if getattr(f, "description", "") else ""
    # first sentence of conclusion as the "what it means" line if no description
    if not desc and getattr(f, "conclusion", ""):
        first = f.conclusion.strip().split(". ")[0]
        desc = f'<p>{_e(first)}.</p>'
    return (f'<div class="card b-{tone}" style="border-left-color:var(--{tone})">'
            f'<h3><span class="glyph t-{tone}">{glyph}</span>{_e(f.name)}'
            f'<span class="badge b-{tone} t-{tone}">{_e(f.severity)}</span></h3>'
            f'{desc}{acts}</div>')


def _av_card(a):
    tone = {"jtag": "info", "rom-loader": "good", "readback": "major", "chip-off": "neutral"}.get(a["access"], "neutral")
    cmd = f'<code>{_e(a["cmd"])}</code>' if a.get("cmd") else ""
    return (f'<div class="av"><div class="m">{_e(a["method"])}</div>'
            f'<span class="tag b-{tone} t-{tone}">{_e(a["access"])}</span>'
            f'{cmd}</div>')


def render(raw: dict, rules) -> str:
    cap = Capture(raw)
    meta = raw.get("metadata", {})
    board = meta.get("board") or "ZynqMP target"
    soc = (meta.get("soc") or "zynqmp").lower()

    fired = []
    for rf in rules:
        try:
            r = rf(cap)
        except Exception:
            r = None
        if r:
            fired.append(r)
    fired.sort(key=lambda f: _sev(f)[2])

    chips = status_chips(cap)
    v_txt, v_tone, v_sub = overall_verdict(chips, fired)
    P = derive_posture(cap)
    nxt = next_actions(soc, P)
    anom = anomalies(fired)
    crit_major = [f for f in fired if _sev(f)[2] <= 1]

    H = ['<title>Security Posture Report</title>', f'<style>{_CSS}</style>', '<div class="wrap">']
    H.append('<p class="eyebrow">JTAGx · Enumeration Report</p>')
    H.append(f'<h1>{_e(board)} — Security Posture</h1>')
    H.append(f'<p class="sub">chip {_e(soc)} · captured {_e(meta.get("timestamp", "?"))} · '
             f'{len(fired)} findings · {len(raw.get("registers", {}))} registers read</p>')
    H.append(f'<div class="verdict b-{v_tone} t-{v_tone}"><span class="dot d-{v_tone}"></span>'
             f'{_e(v_txt)}<small>{_e(v_sub)}</small></div>')

    # 1. Posture strip
    H.append('<section><h2 class="sec">Posture at a glance</h2>')
    H.append('<div class="strip">' + "".join(_chip(*c) for c in chips) + '</div></section>')

    # 2. Critical findings + next action
    H.append('<section><h2 class="sec">Findings that matter</h2>')
    if crit_major:
        H.append("".join(_finding_card(f) for f in crit_major))
    else:
        H.append('<p class="empty">No critical/major findings — posture reads hardened or the '
                 'capture is limited.</p>')
    H.append('</section>')

    # 3. What to do next
    H.append('<section><h2 class="sec">What to do next</h2>')
    if nxt["reach"] is not None:
        segs = "".join(f'<div class="seg{" on" if i < nxt["reach"] else ""}"></div>' for i in range(5))
        H.append(f'<div class="reachbar">{segs}</div>'
                 f'<div class="reachcap">kill-chain reach {nxt["reach"]}/5 — {_e(nxt["reach_label"])}</div>')
    if nxt["extraction"]:
        H.append('<div class="grid" style="margin-top:12px">'
                 + "".join(_av_card(a) for a in nxt["extraction"]) + '</div>')
    else:
        H.append('<p class="empty">Extraction planner unavailable.</p>')
    H.append('</section>')

    # 4. Anomalies
    if anom:
        H.append('<section><h2 class="sec">Anomalies &amp; mismatches</h2>')
        H.append("".join(_finding_card(f) for f in anom))
        H.append('</section>')

    # Lower-severity findings (info/minor) — kept but below the fold
    rest = [f for f in fired if _sev(f)[2] >= 2 and f not in anom]
    if rest:
        H.append('<section><h2 class="sec">Other findings</h2>')
        H.append('<details class="block"><summary>'
                 f'<span>{len(rest)} informational / minor findings</span>'
                 '<span class="cnt">expand</span></summary><div style="padding:12px 15px">')
        H.append("".join(_finding_card(f) for f in rest))
        H.append('</div></details></section>')

    # Registers — de-emphasized, collapsible per block.
    regs = raw.get("registers", {})
    by_block = {}
    for addr, reg in regs.items():
        by_block.setdefault(reg.get("block", "misc"), []).append((addr, reg))
    if by_block:
        H.append('<section><h2 class="sec">Captured registers</h2>')
        for block in sorted(by_block):
            rows = sorted(by_block[block], key=lambda x: str(x[0]))
            trs = []
            for addr, reg in rows:
                val = reg.get("value")
                vtxt = f"0x{val:08X}" if isinstance(val, int) else _e(val)
                trs.append(f'<tr><td class="addr">{_e(addr)}</td>'
                           f'<td class="name">{_e(reg.get("name", ""))}</td>'
                           f'<td class="val">{vtxt}</td></tr>')
            H.append('<details class="block"><summary>'
                     f'<span>{_e(block)}</span><span class="cnt">{len(rows)} regs</span></summary>'
                     f'<table class="regtable">{"".join(trs)}</table></details>')
        H.append('</section>')

    H.append('<footer>Generated by <code>tools/report-html.py</code> from the raw enumeration capture. '
             'Findings come from the same rule engine as <code>tools/interpret.py</code> '
             '(<code>docs/findings/zynqmp_rules.py</code>); posture verdicts and next-actions from '
             '<code>jtagx.debugauth</code> / <code>jtagx.extraction</code> / <code>jtagx.attackgraph</code>. '
             'Colors encode severity (critical→red, major→amber, good/hardened→green), not decoration.</footer>')
    H.append('</div>')
    return "\n".join(H)


def main():
    ap = argparse.ArgumentParser(description="Render a raw enumeration capture into a stylized HTML report.")
    ap.add_argument("raw", help="raw-<ts>.json capture from enumerate.tcl")
    ap.add_argument("-o", "--out", help="output HTML path (default: reports/report-<stem>.html)")
    a = ap.parse_args()

    try:
        raw = _interp.load_json(a.raw)
    except OSError as e:
        sys.exit(f"error: cannot read {a.raw}: {e}")
    rules = _interp.load_rules(_interp.RULES_MODULE)

    out = a.out
    if not out:
        stem = os.path.splitext(os.path.basename(a.raw))[0].replace("raw-", "")
        out = os.path.join(ROOT, "reports", f"report-{stem}.html")
    html_doc = render(raw, rules)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(html_doc)
    print(f"wrote {out}  ({len(html_doc)} bytes)")


if __name__ == "__main__":
    main()
