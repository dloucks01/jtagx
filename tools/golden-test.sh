#!/usr/bin/env bash
# golden-test.sh — interpret.py regression test.
#
# Runs interpret.py against the frozen golden raw JSON in both default
# (compact) and --full modes, diffs the output against the frozen golden
# interpreted markdown. Any difference fails the test — meaning an
# unintended change to the renderer or annotations slipped in.
#
# To intentionally update the golden after a deliberate change to
# interpret.py or annotations:
#   bash tools/golden-test.sh --update
#
# Exit 0 = goldens match. Exit 1 = mismatch (diff printed to stderr).

set -euo pipefail

cd "$(dirname "$0")/.."

GOLDEN_DIR="tests/golden/zcu102-jtag-idle"
RAW="$GOLDEN_DIR/raw.json"

if [ ! -f "$RAW" ]; then
    echo "FAIL: golden raw JSON missing at $RAW" >&2
    exit 1
fi

UPDATE_MODE=0
if [ "${1:-}" = "--update" ]; then
    UPDATE_MODE=1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Render both modes from the golden raw JSON.
python3 tools/interpret.py "$RAW" -o "$TMP/actual-compact.md" 2>/dev/null
python3 tools/interpret.py "$RAW" --full -o "$TMP/actual-full.md" 2>/dev/null

FAIL=0

check_one() {
    local label="$1"
    local actual="$2"
    local golden="$3"
    if [ ! -f "$golden" ]; then
        if [ $UPDATE_MODE -eq 1 ]; then
            cp "$actual" "$golden"
            echo "  $label: golden created (was missing)"
        else
            echo "FAIL: golden missing at $golden — run with --update to create" >&2
            FAIL=1
        fi
        return
    fi
    if diff -q "$actual" "$golden" >/dev/null 2>&1; then
        echo "  $label: PASS"
    else
        if [ $UPDATE_MODE -eq 1 ]; then
            cp "$actual" "$golden"
            echo "  $label: UPDATED"
        else
            echo "FAIL: $label differs from golden ($golden)" >&2
            diff -u "$golden" "$actual" | head -40 >&2
            echo "  ... (truncated; full diff: diff -u $golden $actual)" >&2
            FAIL=1
        fi
    fi
}

check_one "interpreted-compact.md" "$TMP/actual-compact.md" "$GOLDEN_DIR/interpreted-compact.md"
check_one "interpreted-full.md"    "$TMP/actual-full.md"    "$GOLDEN_DIR/interpreted-full.md"

if [ $FAIL -eq 0 ]; then
    echo "PASS: all goldens match"
    exit 0
else
    echo ""
    echo "Goldens diverged. If the change is intentional, run:" >&2
    echo "  bash tools/golden-test.sh --update" >&2
    echo "and commit the updated $GOLDEN_DIR/* files." >&2
    exit 1
fi
