#!/usr/bin/env bash
# test-coverage-report.sh — how much of tools/ and jtagx/ does the offline suite actually
# execute? (code coverage, NOT tools/gen-coverage-chart.py's per-board support rubric — that's
# a different "coverage" entirely; this one is about the test suite, not the toolkit's board list.)
#
# Almost none of this suite calls Python functions directly in-process — by design, after
# Testing Hardening Pass I found that in-process function calls skip argv parsing, file I/O,
# and error paths (see cli-adversarial-smoketest.sh). Nearly every check is a real
# `python3 tools/x.py ...` subprocess. Plain `coverage run` only measures the ONE process it
# launches, so a naive `coverage run tools/tcl-smoketest.sh` would only ever show the bash
# script itself at 0% Python coverage. Fixed via coverage.py's documented subprocess-coverage
# hook: COVERAGE_PROCESS_START points every subprocess at .coveragerc, and
# tools/coverage-sitecustomize/sitecustomize.py (on PYTHONPATH, auto-imported by every `python3`
# process at startup) calls coverage.process_startup() to attach instrumentation before that
# subprocess's own code runs. Each process writes its own parallel data file; `coverage combine`
# merges them afterward.
set -uo pipefail
cd "$(dirname "$0")/.."

if ! python3 -c "import coverage" 2>/dev/null; then
    echo "SKIP: test-coverage-report (coverage.py not installed — pip3 install --user coverage," \
         "or apt-get install python3-coverage)"
    exit 0
fi

rm -f .coverage .coverage.*
mkdir -p reports

export COVERAGE_PROCESS_START="$PWD/.coveragerc"
export PYTHONPATH="$PWD/tools/coverage-sitecustomize${PYTHONPATH:+:$PYTHONPATH}"

echo "running the full offline suite under coverage instrumentation (every python3 subprocess)..."
bash tools/tcl-smoketest.sh
SUITE_RC=$?

unset COVERAGE_PROCESS_START PYTHONPATH

if ! ls .coverage.* >/dev/null 2>&1 && [ ! -f .coverage ]; then
    echo "FAIL: no coverage data was written at all — the sitecustomize hook did not fire" \
         "(check PYTHONPATH propagated into subprocesses, and that .coveragerc's data_file matches)"
    exit 1
fi

python3 -m coverage combine
python3 -m coverage report -m --rcfile=.coveragerc | tee reports/coverage-report.txt
python3 -m coverage html --rcfile=.coveragerc

echo ""
echo "wrote reports/coverage-report.txt + reports/coverage-html/index.html"
if [ "$SUITE_RC" -ne 0 ]; then
    echo "NOTE: the underlying suite itself had failures (exit $SUITE_RC) — coverage was still measured," \
         "but treat the report as partial (failed checks may exit before touching some code paths)."
fi
exit "$SUITE_RC"
