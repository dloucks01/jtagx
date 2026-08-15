"""
jtagx.benchvalidate — turn "bench-ready (predicted)" into a CONFIRMABLE protocol.

Generates a structured, ordered validation checklist for a board FROM THE TOOLKIT'S OWN MODELS (the
same identity/access/unlock/extraction the rest of the code uses), so when hardware finally arrives the
operator walks the list, and `classify_result` grades each step against what the mock predicted. All
PASS ⇒ the board graduates bench-ready → bench-VALIDATED, with the mock-vs-real delta recorded.

    from jtagx.benchvalidate import spec, classify_result, render_md, verdict
    checks = spec("kinetis", profile)     # the ordered checklist (each: cmd + expected + tier it proves)
    print(render_md("kinetis", checks))
    v = verdict(checks, {"access-open": "...OPEN...", ...})   # ingest real outputs → per-check PASS/FAIL
"""
from .unlock import (build_plan, workflow_steps, verify_cmd, _ENGAGE_POSTURE,
                     parse_access_verdict, parse_reopen_result, classify_reopen)

PASS, FAIL, UNKNOWN, OPERATOR = "PASS", "FAIL", "UNKNOWN", "NEEDS-OPERATOR"


def _slug(s):
    return "".join(c if c.isalnum() else "-" for c in s.lower()).strip("-")[:28]


def _check(id, desc, cmd, expect, validates, tier, kind, destructive=False):
    return dict(id=id, desc=desc, cmd=cmd, expect=expect, validates=validates, tier=tier,
                kind=kind, destructive=destructive)


def spec(soc, profile=None):
    """The ordered bench-validation checks for `soc`, generated from the models. `kind` drives grading:
    identity | access | unlock | extract."""
    profile = profile or {}
    checks = []

    # 1. identity — the chain answers what the profile expects
    m = profile.get("match", {})
    exp = f"family={m.get('family', '?')}, >= {m.get('min_taps', '?')} TAP(s)"
    if m.get("part_ids"):
        exp += ", IDCODE in {" + ", ".join(hex(p) if isinstance(p, int) else str(p)
                                            for p in m["part_ids"]) + "}"
    checks.append(_check("identity", "JTAG chain answers the expected IDCODE / family",
                         'openocd -f openocd/<cfg> -c "init; source openocd/discover.tcl; shutdown"',
                         exp, "chain/identity model", "a", "identity"))

    # 2. access — the access-check reads the modeled verdict (OPEN on a dev/unprovisioned board)
    vc = verify_cmd(soc)
    if vc:
        checks.append(_check("access-open", "access-check reads OPEN on an unprovisioned/dev board",
                             vc, "ACCESS VERDICT: OPEN", "access-check model", "b", "access"))

    # 3. unlock — every modeled lock with a runnable lever: reopen -> verify -> DEFEATED
    for s in workflow_steps(soc, build_plan(soc, _ENGAGE_POSTURE.get(soc, {}))):
        lev = s.get("lever")
        if lev and lev.get("cmd"):
            d = "  (DESTRUCTIVE — mass-erase)" if lev.get("destructive") else ""
            checks.append(_check(
                f"unlock-{_slug(s['lock'])}",
                f"lever '{lev['title']}'{d}, then verify",
                lev["cmd"] + "   # then run: " + (s.get("verify_cmd") or "the access-check"),
                "reopen->verify classifies DEFEATED", f"unlock model: {s['lock']}", "d", "unlock",
                destructive=lev.get("destructive", False)))

    # 4. extraction — a dump of the modeled memory is non-empty and structured
    dump = profile.get("dump") or {}
    which = "flash" if dump.get("flash") else ("dram" if dump.get("dram") else None)
    if which:
        script = (dump.get(which) or {}).get("script", f"# the profile's dump.{which}")
        checks.append(_check("extract", f"dump {which} -> non-empty + recognizable structure",
                             f"{script}  then: python3 tools/dump-triage.py <dump>",
                             "dump size > 0 and triage identifies real structure", "extraction model",
                             "c", "extract"))
    return checks


def classify_result(check, output):
    """Grade one check against the operator's captured output. Returns PASS / FAIL / NEEDS-OPERATOR."""
    o = output or ""
    kind = check["kind"]
    if kind == "access":
        return PASS if parse_access_verdict(o) == "OPEN" else FAIL
    if kind == "unlock":
        # the output should contain BOTH the lever run and the post-lever verify
        outcome = parse_reopen_result(o)
        verdict_after = parse_access_verdict(o)
        status = classify_reopen(outcome, verdict_after)[0]
        return PASS if status in ("DEFEATED", "PARTIAL") else (FAIL if status == "RESISTED" else UNKNOWN)
    if kind == "extract":
        lo = o.lower()
        if "0 byte" in lo or "empty" in lo or "unreadable" in lo:
            return FAIL
        return PASS if "size" in lo or "structure" in lo else OPERATOR
    if kind == "identity":
        # any 0x........ idcode-looking token counts as an operator-confirmable hit
        import re
        return PASS if re.search(r"0x[0-9A-Fa-f]{6,8}", o) else OPERATOR
    return UNKNOWN


def verdict(checks, results):
    """Ingest {check_id: output} → {results:[{id,grade}], validated: bool, delta:[...]}. `validated`
    is True only if every gradable check PASSes (no FAIL, no UNKNOWN)."""
    rows, any_fail, any_unknown = [], False, False
    for c in checks:
        out = results.get(c["id"])
        grade = classify_result(c, out) if out is not None else OPERATOR
        rows.append({"id": c["id"], "grade": grade, "validates": c["validates"]})
        if grade == FAIL:
            any_fail = True
        elif grade in (UNKNOWN, OPERATOR):
            any_unknown = True
    delta = [r for r in rows if r["grade"] == FAIL]
    return {"results": rows, "validated": not any_fail and not any_unknown,
            "any_fail": any_fail, "delta": delta,
            "tier": "bench-VALIDATED" if (not any_fail and not any_unknown) else
                    ("REGRESSED (mock≠real)" if any_fail else "bench-ready (unconfirmed steps remain)")}


def render_md(soc, checks, results=None):
    L = [f"# Bench-validation protocol — {soc}", "",
         "Run each step on the real board; the tool grades it against what the mock predicted. All PASS "
         "⇒ this board graduates **bench-ready → bench-VALIDATED**.", ""]
    v = verdict(checks, results or {}) if results is not None else None
    if v:
        L.append(f"**Verdict: {v['tier']}**" + (f"  ·  delta: {[d['id'] for d in v['delta']]}"
                                                if v["delta"] else "") + "\n")
    for i, c in enumerate(checks, 1):
        g = ""
        if results is not None:
            g = "  —  **" + classify_result(c, results.get(c["id"])) + "**" if c["id"] in results \
                else "  —  _not run_"
        dz = "  ⚠DESTRUCTIVE" if c.get("destructive") else ""
        L.append(f"### {i}. {c['desc']}{dz}{g}")
        L.append(f"- validates: {c['validates']}  (tier {c['tier']})")
        L.append(f"- run: `{c['cmd']}`")
        L.append(f"- PASS if: {c['expect']}")
        L.append("")
    return "\n".join(L)
