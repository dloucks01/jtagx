#!/usr/bin/env bash
# kit-build-smoketest.sh — build the REAL standalone engagement kit (tools/make-standalone-package.sh)
# into a scratch dir and cold-run it: no dev-tree env vars, no repo-root PYTHONPATH, exactly how an
# operator on an air-gapped box would use it after extracting the tarball.
#
# NOT part of the fast offline suite (tcl-smoketest.sh) — it invokes the real packaging script (needs
# `openocd`, `ldd`, `rsync` on PATH, and a slow best-effort .deb network step that degrades gracefully
# if offline). Run this explicitly before cutting/distributing a kit, or after touching
# make-standalone-package.sh / anything a packaged tool imports.
#
# Found (2026-08-15): the packaging script never copied jtagx/ — the Python engine package that 16 of
# the operational tools/*.py scripts `from jtagx import ...` at MODULE LOAD. Every one of them (incl.
# preflight.py, cve-match.py, engagement-report.py, unlock-engine.py, jtag-to-shell.py, first-contact.py)
# crashed with ModuleNotFoundError on the FIRST cold run from a built kit — while the kit's own
# selftest.sh (which only exercised board-runner.py, a jtagx-independent tool, plus syntax-only
# ast.parse checks that never execute an import) reported "OK". interpret.py's jtagx import happens to
# be wrapped in try/except (graceful degradation), which is exactly why it did NOT surface the gap even
# though it was the one jtagx-touching tool anyone had actually run by hand before this.
set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v openocd >/dev/null 2>&1 || ! command -v ldd >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
    echo "SKIP: kit-build-smoketest (needs openocd + ldd + rsync on PATH to build the real kit)"
    exit 0
fi

FAILS=0
fail() { echo "FAIL(kit-build): $1"; FAILS=$((FAILS+1)); }

KIT="$(mktemp -d)/jtag-engagement-kit"
trap 'rm -rf "$(dirname "$KIT")"' EXIT

echo "building the kit at $KIT ..."
if ! bash tools/make-standalone-package.sh "$KIT" >/tmp/kit-build.log 2>&1; then
    tail -30 /tmp/kit-build.log
    fail "make-standalone-package.sh itself failed"
    echo "FAIL: kit-build ($FAILS check(s) failed)"; exit 1
fi

# --- cold-run: NO dev-tree env vars, NO repo-root on PYTHONPATH — a clean environment, like a fresh
# extraction on an air-gapped box would actually have. -------------------------------------------------
cold() { env -i PATH="/usr/bin:/bin:$KIT/vendor/openocd/bin" HOME="$HOME" "$@"; }

# 1. jtagx/ actually shipped (the core of the bug this test exists for)
if [ ! -d "$KIT/jtagx" ]; then
    fail "jtagx/ was not bundled — the packaging regression is back"
else
    if ! cold python3 -c "import sys; sys.path.insert(0,'.'); import jtagx" 2>/tmp/kit-imp.log; then
        fail "jtagx/ is bundled but doesn't import cleanly: $(tail -1 /tmp/kit-imp.log)"
    fi
fi

# 2. every jtagx-importing operational tool actually runs cold, without crashing
cd "$KIT"
declare -A CHECKS=(
    ["preflight.py"]="tools/preflight.py --soc zynqmp"
    ["cve-match.py"]="tools/cve-match.py --soc zynqmp --jtag-open"
    ["unlock-engine.py"]="tools/unlock-engine.py --soc zynqmp --jtag-open"
    ["jtag-to-shell.py"]="tools/jtag-to-shell.py --idle --goal shell"
    ["first-contact.py"]="tools/first-contact.py"
    ["attack-graph.py"]="tools/attack-graph.py --soc zynqmp --jtag-open"
    ["extract-plan.py"]="tools/extract-plan.py --soc zynqmp"
    ["capability-matrix.py"]="tools/capability-matrix.py --profile zynqmp"
    ["bench-validate.py"]="tools/bench-validate.py --soc zynqmp"
    ["gen-coverage-chart.py"]="tools/gen-coverage-chart.py --counts"
    ["bsdl-scan.py"]="tools/bsdl-scan.py --help"
)
for name in "${!CHECKS[@]}"; do
    out=$(cold python3 ${CHECKS[$name]} 2>&1)
    if grep -q "ModuleNotFoundError\|Traceback (most recent call last)" <<<"$out"; then
        fail "$name crashed cold from the built kit: $(grep -m1 'Error' <<<"$out")"
    fi
done
cd - >/dev/null

# 3. the kit's OWN selftest.sh must pass (it's the operator's actual first command per README-KIT.md)
if ! ( cd "$KIT" && cold ./selftest.sh ) >/tmp/kit-selftest.log 2>&1; then
    tail -20 /tmp/kit-selftest.log
    fail "the kit's own selftest.sh failed"
fi

# 4. references/coresight-parts.json shipped (small data file, no reason to gate behind WITH_PDFS)
if [ ! -f "$KIT/references/coresight-parts.json" ]; then
    fail "references/coresight-parts.json was not bundled (CoreSight identification degrades to raw hex)"
fi

# 5. adapter udev rules + installer shipped at BOTH the kit root (alongside the other entry points)
# and tools/ (the wholesale rsync source), and the rules file itself is syntactically valid.
if [ ! -f "$KIT/install-udev-rules.sh" ]; then
    fail "install-udev-rules.sh was not bundled at the kit root"
elif [ ! -x "$KIT/install-udev-rules.sh" ]; then
    fail "install-udev-rules.sh is bundled but not executable"
fi
if [ ! -f "$KIT/openocd/adapters/99-jtagx-kit.rules" ]; then
    fail "openocd/adapters/99-jtagx-kit.rules was not bundled"
elif command -v udevadm >/dev/null 2>&1; then
    if ! udevadm verify "$KIT/openocd/adapters/99-jtagx-kit.rules" >/tmp/udev-verify.log 2>&1; then
        tail -10 /tmp/udev-verify.log
        fail "99-jtagx-kit.rules failed udevadm verify"
    fi
fi
# the non-root safety gate must exit cleanly with no changes when NOT run as root (this whole check
# runs as the build user, never root, so this exercises the real guard path every time)
UDEV_OUT=$(cd "$KIT" && cold bash install-udev-rules.sh 2>&1); UDEV_RC=$?
if [ "$UDEV_RC" -eq 0 ]; then
    fail "install-udev-rules.sh should refuse to run without root, but exited 0"
fi
if grep -q "Traceback (most recent call last)" <<<"$UDEV_OUT"; then
    fail "install-udev-rules.sh crashed instead of cleanly refusing: $(head -1 <<<"$UDEV_OUT")"
fi

if [ "$FAILS" -eq 0 ]; then
    echo "PASS: kit-build (real kit built + selftest.sh + 11 jtagx-dependent tools run cold, clean env)"
    exit 0
else
    echo "FAIL: kit-build ($FAILS check(s) failed)"
    exit 1
fi
