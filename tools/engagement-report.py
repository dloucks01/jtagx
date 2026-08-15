#!/usr/bin/env python3
"""
engagement-report.py — consolidate an engagement into ONE markdown report: identity, posture, the dumps
captured (size + md5), the secrets/triage findings, the matched CVEs/known-attacks, and the realised
capabilities + recommended next steps. The single deliverable you hand to the client / put in the wrap-up.

It pulls together what the other tools produced (board-runner plan, dram-secrets, dump-triage, cve-match)
rather than re-deriving it. Point it at the chip you identified + the posture you read + the dumps dir.

Usage:
    python3 tools/engagement-report.py --soc zynqmp --jtag-open --secure-boot off --dumps dumps -o reports/engagement.md
    python3 tools/engagement-report.py --soc stm32f4 --rdp 0 --deep   # also run dram-secrets/dump-triage on the dumps
Offline. --deep runs the analyzers on each dump (slower) and embeds a summary.
"""
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _imp(name, fn):
    s = importlib.util.spec_from_file_location(name, os.path.join(HERE, fn))
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m

cm = _imp("cve_match", "cve-match.py")       # reuse the CVE DB + matcher
ue = _imp("unlock_engine", "unlock-engine.py")  # reuse the Phase-2b unlock engine


def load_profile(soc):
    p = os.path.join(ROOT, "profiles", f"{soc}.json")
    if not os.path.exists(p):
        return None
    keep = [l for l in open(p) if not l.lstrip().startswith(("//", "#"))]
    return json.loads("".join(keep))


def md5(path, cap=1 << 26):
    h = hashlib.md5()
    with open(path, "rb") as f:
        n = 0
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk); n += len(chunk)
            if n >= cap:
                return h.hexdigest() + f" (first {cap >> 20}MB)"
    return h.hexdigest()


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout
    except Exception as e:
        return f"(failed: {e})"


def main():
    ap = argparse.ArgumentParser(description="Consolidate an engagement into one markdown report.")
    ap.add_argument("--soc", required=True)
    ap.add_argument("--target", default="", help="board/asset label for the report header")
    ap.add_argument("--date", default="", help="engagement date (free text; not auto-filled)")
    ap.add_argument("--dumps", default="dumps", help="directory of captured dumps")
    ap.add_argument("--deep", action="store_true", help="run dram-secrets + dump-triage on each dump and embed a summary")
    # posture flags (same vocabulary as cve-match)
    ap.add_argument("--from-capture", metavar="RAW_JSON",
                    help="auto-derive posture from an enumeration capture (reports/raw-*.json); flags override")
    ap.add_argument("--jtag-open", action="store_true"); ap.add_argument("--jtag-locked", action="store_true")
    ap.add_argument("--efuse-jtag-dis", action="store_true")
    ap.add_argument("--secure-boot", choices=["on", "off", "encrypt-only"]); ap.add_argument("--aes-encrypt", action="store_true")
    ap.add_argument("--rdp", type=int); ap.add_argument("--approtect-open", action="store_true")
    ap.add_argument("--debug-locked", action="store_true", help="SmartFusion2: M3 debug security-locked")
    ap.add_argument("--flashlock", action="store_true", help="SmartFusion2: FlashLock/eNVM readback on")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()

    P = {}
    if a.from_capture and ue.Capture is not None:
        try:
            P.update(ue.derive_posture(ue.Capture(json.load(open(a.from_capture)))))
        except Exception as e:
            print(f"warning: could not derive posture from {a.from_capture}: {e}", file=sys.stderr)
    if a.jtag_open: P["jtag_open"] = True; P.pop("jtag_locked", None)
    if a.jtag_locked: P["jtag_open"] = False; P["jtag_locked"] = True
    if a.efuse_jtag_dis: P["efuse_jtag_dis"] = True
    if a.secure_boot == "on": P["secure_boot"] = True
    elif a.secure_boot == "off": P["secure_boot"] = False
    elif a.secure_boot == "encrypt-only": P["secure_boot"] = "encrypt-only"
    if a.aes_encrypt: P["aes_encrypt"] = True
    if a.rdp is not None: P["rdp_level"] = a.rdp
    if a.approtect_open: P["approtect_open"] = True
    if a.debug_locked: P["debug_locked"] = True
    if a.flashlock: P["flashlock"] = True

    prof = load_profile(a.soc)
    L = []
    L.append(f"# JTAG Engagement Report — {a.target or a.soc}")
    L.append("")
    L.append(f"- target: **{a.target or '(unspecified)'}**   chip: **{a.soc}**" +
             (f" — {prof['name']} (Paradigm {prof['paradigm']})" if prof else ""))
    if a.date: L.append(f"- date: {a.date}")
    L.append(f"- posture (enumerated): {P or '(not supplied — run the enumerate step)'}")
    L.append("")

    # --- 1. Capabilities available on this target (from the profile) ---
    L.append("## 1. Capabilities on this target")
    if prof:
        caps = []
        if (prof.get("dump") or {}).get("dram"): caps.append("Cap-1: DRAM/RAM dump")
        if (prof.get("dump") or {}).get("flash"): caps.append("Cap-1: flash dump")
        if prof.get("enumerate"): caps.append("posture enumeration")
        if prof.get("reopen"): caps.append("debug reopen (software-hardened only)")
        if prof.get("patch"): caps.append("Cap-2: live memory/function patch")
        if prof.get("reflash"): caps.append("Cap-3: reflash / persistence")
        L.append("  - " + "\n  - ".join(caps) if caps else "  (profile defines no live capabilities)")
        for k, why in (prof.get("absent") or {}).items():
            L.append(f"  - *not available — {k}: {why}*")
    else:
        L.append(f"  (no profile for '{a.soc}' — generic Paradigm-A capabilities only)")
    L.append("")

    # --- 1b. Kill chain (attack-graph) + extraction avenues (the ordered plan) ---
    try:
        from jtagx.attackgraph import plan as _agplan
        g = _agplan(a.soc, P, prof, source=("capture" if a.from_capture else "asserted"))
        L.append(f"## 1b. Kill chain — reach {g['depth']}/5 ({g['depth_label']})")
        L.append(f"_{'posture confirmed from capture' if g.get('source') == 'capture' else 'posture asserted — verify on HW'}. "
                 "glitch/side-channel/physical deferred._\n")
        L.append("| # | objective | state | next move |")
        L.append("|--|--|--|--|")
        from jtagx.attackgraph import SPINE
        for n in g["nodes"]:
            tag = str(SPINE.index(n["id"]) + 1) if n["id"] in SPINE else "↳"
            act = (n.get("action", "")[:64] + "…") if len(n.get("action", "")) > 65 else n.get("action", "")
            L.append(f"| {tag} | {n['title']} | {n['state']} | {act or '—'} |")
        L.append("")
    except Exception as e:
        L.append(f"## 1b. Kill chain\n_(attack-graph unavailable: {e})_\n")

    try:
        from jtagx.extraction import extraction_plan as _explan
        L.append("## 1c. Extraction avenues (best-first)")
        L.append("_ROM-loader / readback / chip-off paths do NOT need the debug port._\n")
        for m in _explan(a.soc, P, prof):
            gate = m["access"] if m["access"] != "jtag" else "debug-port"
            L.append(f"- **{m['method']}** ({gate}{'; ⚠destructive' if not m['non_destructive'] else ''}) — needs: {m['needs']}")
        L.append("")
    except Exception as e:
        L.append(f"## 1c. Extraction avenues\n_(extraction layer unavailable: {e})_\n")

    # --- 2. Dumps captured ---
    L.append("## 2. Dumps captured")
    ddir = os.path.join(ROOT, a.dumps) if not os.path.isabs(a.dumps) else a.dumps
    bins = sorted(f for f in (os.listdir(ddir) if os.path.isdir(ddir) else []) if f.endswith(".bin"))
    if bins:
        L.append("| file | size | md5 |")
        L.append("|---|---:|---|")
        for f in bins:
            p = os.path.join(ddir, f); sz = os.path.getsize(p)
            L.append(f"| `{f}` | {sz:,} | `{md5(p)}` |")
    else:
        L.append(f"  (no .bin dumps in {a.dumps}/ — run the dump steps)")
    L.append("")

    # --- 3. Findings (deep: run the analyzers) ---
    if a.deep and bins:
        L.append("## 3. Analysis (dump-triage + secure-boot + dram-secrets)")
        for f in bins[:6]:
            p = os.path.join(ddir, f)
            L.append(f"### {f}")
            tri = run(["python3", os.path.join(HERE, "dump-triage.py"), p])
            verdict = [ln.strip() for ln in tri.splitlines() if "->" in ln or "verdict" in ln.lower()][:4]
            L.append("```\n" + ("\n".join(verdict) or "(triage produced no verdict)") + "\n```")
            # secure-boot structure: is this a signed/unsigned boot container, and where's the auth check?
            sb = run(["python3", os.path.join(HERE, "secureboot-analyze.py"), p])
            sbl = [ln.rstrip() for ln in sb.splitlines()
                   if ln.startswith("format:") or re.search(r"\[(CRIT|HIGH|MED|INFO|LOW)\s*\]", ln)][:6]
            if sbl and "UNRECOGNIZED" not in sbl[0]:
                L.append("secure-boot:\n```\n" + "\n".join(sbl) + "\n```")
            # firmware id: what OS/RTOS is this + its version-gated CVE classes
            fid = run(["python3", os.path.join(HERE, "firmware-id.py"), p])
            fidl = [ln.rstrip() for ln in fid.splitlines()
                    if re.search(r"\b(Linux kernel|VxWorks|U-Boot|FreeRTOS|Zephyr|ThreadX|BusyBox)\b", ln)
                    or "CVE" in ln][:6]
            if fidl:
                L.append("firmware id:\n```\n" + "\n".join(fidl) + "\n```")
            sec = run(["python3", os.path.join(HERE, "dram-secrets.py"), p])
            hits = [ln for ln in sec.splitlines() if re.search(r"CRIT|HIGH|aes-key|pw=|PRIVATE KEY|token", ln)][:8]
            if hits:
                L.append("secrets:\n```\n" + "\n".join(hits) + "\n```")
        L.append("")

    # --- 4. Known issues (CVE / posture) ---
    L.append("## 4. Known issues — CVEs / published attacks / posture")
    for e in cm.DB:
        if a.soc not in e["chips"]:
            continue
        st = cm.cond_ok(e, P)
        if st is False:
            continue
        tag = "APPLIES" if st is True else "verify"
        L.append(f"- **[{tag}]** {e['sev']} `{e['id']}` — {e['title']}  *(ref: {e['ref']})*")
    for kind, sev, msg in cm.posture_findings(a.soc, P):
        L.append(f"- **[posture]** {sev} — {msg}")
    L.append("")

    # implementation-review misuse (NOT CVEs — the project's own research layer)
    try:
        from jtagx.weakness import misuse_findings
        mf = misuse_findings(a.soc, P)
    except Exception:
        mf = []
    if mf:
        L.append("### Implementation-review misuse (research — not a CVE)")
        L.append("_Where the implementation could be misused, from reading the design (not a published CVE)._")
        for cls, sev, msg, hid, _probe in mf:
            L.append(f"- **[{cls}]** {sev} `{hid}` — {msg}")
        L.append("")

    # --- 5. Unlock plan (Phase-2b) — how to defeat the locks that are engaged ---
    L.append("## 5. Unlock plan — defeating the locks (Phase-2b)")
    locks = ue.build_plan(a.soc, P)
    engaged = [x for x in locks if x["state"] in ("LOCKED", "ENABLED")]
    if not engaged:
        L.append("  Board is OPEN (or no lock facts supplied) — nothing to unlock; proceed straight to "
                 "extraction (§1 capabilities). On a real target this section is the main effort.")
    else:
        auto = sum(1 for x in engaged for s in x["strategies"] if s["kind"] in ("software-lever", "misconfig"))
        L.append(f"  **{len(engaged)} lock(s) engaged; {auto} auto-tryable software lever(s) — try those first.** "
                 "Ranked cheapest/safest first (software-lever → misconfig → alternate-path → physical → "
                 "firmware → fault-injection → side-channel).")
        for x in engaged:
            L.append(f"\n**{x['name']} — {x['state']}**  ·  enforcement: *{x['enforcement']}*")
            for s in x["strategies"]:
                d = "  ⚠DESTRUCTIVE" if s["destructive"] else ""
                pq = f"  · prereq: {s['prereq']}" if s["prereq"] else ""
                L.append(f"  - **[{ue.KIND_TAG.get(s['kind'], '?')}]** ({s['confidence']}){d} {s['title']} — {s['how']}{pq}")
    L.append("")

    # --- 6. Recommended next steps ---
    L.append("## 6. Recommended next steps")
    L.append("- Run `tools/board-runner.py --profile " + a.soc + "` for the full step-by-step plan.")
    if prof and prof.get("patch"):
        L.append("- Defeat an auth/license check: `patch-recipe.py` → `probe-phys-patch.tcl` (Cap-2).")
    if prof and prof.get("reflash"):
        L.append("- For persistence: patch + `repack-bootimage.py` → reflash (Cap-3, DESTRUCTIVE).")
    L.append("- Confirm any **[verify]** issue above by reading the relevant posture register (enumerate step).")
    L.append("")
    L.append("> All findings here are from the chip + posture supplied; profiles other than ZynqMP are "
             "HW-unvalidated (vendor-doc-cited + audited). Confirm on the live target.")

    report = "\n".join(L)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(report + "\n")
        print(f"wrote {a.out} ({len(report)} bytes)")
    else:
        print(report)


if __name__ == "__main__":
    main()
