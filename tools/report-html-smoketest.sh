#!/usr/bin/env bash
# report-html-smoketest.sh — tools/report-html.py generates a valid, self-contained, operator-first
# HTML report from the golden capture. Offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(report-html): $1"; exit 1; }
python3 -m py_compile tools/report-html.py || fail "does not compile"

GOLD="tests/golden/zcu102-jtag-idle/raw.json"
[ -f "$GOLD" ] || { echo "SKIP(report-html): no golden capture"; exit 0; }

OUT=$(mktemp --suffix=.html)
trap 'rm -f "$OUT"' EXIT
python3 tools/report-html.py "$GOLD" -o "$OUT" >/dev/null 2>&1 || fail "generation errored"

H=$(cat "$OUT")
# the four operator-first sections lead the page, in order
for sec in "Posture at a glance" "Findings that matter" "What to do next" "Captured registers"; do
    grep -qF "$sec" <<<"$H" || fail "missing section: $sec"
done
# leads with the operant verdict + posture chips
grep -qE "debug-auth" <<<"$H" || fail "posture strip should include the debug-auth chip"
grep -qE "class=\"verdict" <<<"$H" || fail "should render an overall verdict badge"
# the ZCU102 dev baseline surfaces the CRITICAL secure-world-debug finding
grep -qi "secure-world" <<<"$H" || fail "CRITICAL secure-world debug finding should appear"
# next-actions shows a real extraction avenue + a kill-chain reach (profile loaded)
grep -qi "mem-AP dump" <<<"$H" || fail "extraction avenues should include the mem-AP dump (profile loaded)"
grep -qE "kill-chain reach [0-9]/5" <<<"$H" || fail "should render the kill-chain reach bar"
# registers de-emphasized into collapsible <details>
grep -qE "<details class=\"block\"" <<<"$H" || fail "register blocks should be collapsible <details>"
# SELF-CONTAINED: no external http(s) asset references (CSP-safe / artifact-publishable)
if grep -oE "https?://[^\"' ]+\.(css|js|woff2?|png|svg|jpg)" <<<"$H" | grep -q .; then
    fail "report must be self-contained (found an external asset reference)"
fi
# theme-aware: defines dark-mode tokens
grep -qE "prefers-color-scheme:dark" <<<"$H" || fail "report should be theme-aware (dark tokens)"

echo "PASS: report-html (operator-first sections, verdict+chips, findings, next-actions, self-contained, theme-aware)"
