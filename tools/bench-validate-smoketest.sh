#!/usr/bin/env bash
# bench-validate-smoketest.sh — offline assertions for jtagx.benchvalidate: the per-board validation
# protocol is generated from the models (identity/access/unlock/extract checks), grades captured outputs
# against the mock's prediction, and graduates bench-ready → bench-VALIDATED only when every step PASSes
# — flagging the mock-vs-real delta otherwise. Pure/offline.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(bench-validate): $1"; exit 1; }
python3 -m py_compile tools/bench-validate.py jtagx/benchvalidate.py || fail "does not compile"

python3 - <<'PY' || exit 1
import json, sys
sys.path.insert(0, ".")
from jtagx.benchvalidate import spec, verdict, classify_result
def bad(m): print("FAIL(bench-validate):", m); sys.exit(1)
def prof(soc):
    import glob, os
    for p in sorted(glob.glob("profiles/*.json")):
        if os.path.basename(p).startswith("_"): continue
        d = json.loads("".join(l for l in open(p) if not l.lstrip().startswith(("//","#"))))
        if d.get("soc") == soc: return d
    bad(f"no profile {soc}")

# 1. spec is generated from the models: kinetis has identity + access + unlock(lever) + extract
ck = spec("kinetis", prof("kinetis"))
kinds = {c["kind"] for c in ck}
if not {"identity","access","unlock","extract"} <= kinds: bad(f"kinetis spec missing kinds: {kinds}")
if not any(c["kind"]=="unlock" and c["destructive"] for c in ck): bad("kinetis unlock check should be destructive")

# 2. clean pass on every step → bench-VALIDATED
def defeated(): return "Kinetis MDM-AP mass-erase complete (FLASH ERASED)\n== ACCESS VERDICT: OPEN =="
results_ok = {}
for c in ck:
    results_ok[c["id"]] = {"identity":"TAP0 0x0BC11477","access":"== ACCESS VERDICT: OPEN ==",
                           "unlock":defeated(),"extract":"dump size 4096 bytes; structure found"}[c["kind"]]
v = verdict(ck, results_ok)
if not v["validated"] or v["tier"] != "bench-VALIDATED": bad(f"all-PASS should validate (got {v['tier']})")

# 3. a mock≠real mismatch on ONE step → REGRESSED, delta names it
results_bad = dict(results_ok)
acc = next(c["id"] for c in ck if c["kind"]=="access")
results_bad[acc] = "== ACCESS VERDICT: LOCKED =="    # real board didn't read OPEN as the mock predicted
v2 = verdict(ck, results_bad)
if v2["validated"]: bad("a LOCKED access read must not validate")
if acc not in [d["id"] for d in v2["delta"]]: bad("the failing access step should be in the delta")

# 4. an unrun step keeps it unconfirmed (not validated), honestly
v3 = verdict(ck, {})
if v3["validated"]: bad("no results should not validate")

# 5. classify grades unlock RESISTED as FAIL (the lever didn't defeat on real HW)
resisted = "-> DAP_SEC did NOT stick: eFuse\n== ACCESS VERDICT: LOCKED =="
uc = next(c for c in ck if c["kind"]=="unlock")
if classify_result(uc, resisted) != "FAIL": bad("a RESISTED unlock on real HW should grade FAIL")

print("  bench-validate OK (model-generated spec, all-PASS→VALIDATED, mismatch→REGRESSED+delta)")
PY

# CLI renders + lists
O=$(python3 tools/bench-validate.py --soc zynqmp 2>/dev/null); grep -q "Bench-validation protocol" <<<"$O" || fail "CLI should render"
O=$(python3 tools/bench-validate.py --list 2>/dev/null); grep -q "kinetis" <<<"$O" || fail "--list should show boards"
echo "PASS: bench-validate (per-board protocol: generate + grade → bench-VALIDATED / REGRESSED)"
