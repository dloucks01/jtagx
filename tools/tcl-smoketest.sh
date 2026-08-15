#!/usr/bin/env bash
# tcl-smoketest.sh — fast offline check that enumerate.tcl parses and runs.
#
# Catches:
#   - Tcl syntax errors (unclosed braces, malformed expr, etc.)
#   - Bracket-in-double-quoted-string bugs (e.g., "[2:0]" being interpreted
#     as command substitution and crashing the script mid-run)
#   - Undefined-variable references
#   - Bad foreach lists
#
# Does NOT catch (delegated to other layers):
#   - Wrong register addresses inside dump_reg_qemu calls — caught by
#     golden-test-roundtrip.sh comparing against tests/golden/zcu102-jtag-idle/raw.json
#   - Wrong annotation field names — caught by the golden-test.sh interpreted-md diff
#   - Anything that requires real hardware behaviour (DAP state, AXI timing)
#
# Run before every commit that touches openocd/enumerate.tcl or its
# helpers. Exits 0 on clean run, 1 on any error.

set -euo pipefail

cd "$(dirname "$0")/.."

# Static check: scan for the bracket-in-string pattern that has bitten us
# multiple times. Heuristic: a "..." string containing [digit:digit] or
# [digit] inside a [list ...] or lappend context. NOT inside foreach {}
# braces (those don't substitute).
#
# Scan extended (audit B6, 2026-05-28) to cover dump-bootrom.tcl too —
# the dispatcher's handler text was where the most recent regression hit.
for tcl_file in openocd/*.tcl openocd/lib/research-*.tcl; do
    if [ ! -f "$tcl_file" ]; then continue; fi
    STATIC_BUGS=$(awk -v file="$tcl_file" '
        /^[[:space:]]*foreach[[:space:]].*\{/ { in_foreach = 1; next }
        /^[[:space:]]*\}[[:space:]]*\{/ && in_foreach { in_foreach = 0 }
        !in_foreach && /\[(list|lappend|format|expr|say|puts)[[:space:]]/ {
            line = $0
            # Look for "..." with raw [digit] or [digit:digit] inside
            if (match(line, /"[^"]*\[[0-9]+(:[0-9]+)?\][^"]*"/)) {
                printf "  %s:%d  bracket-in-string: %s\n", file, NR, line
                found = 1
            }
        }
        END { if (found) exit 1; else exit 0 }
    ' "$tcl_file") || {
        echo "FAIL: bracket-in-string pattern detected"
        echo "$STATIC_BUGS"
        echo ""
        echo "Tcl will interpret [N] or [N:M] inside double quotes as command substitution."
        echo "Replace with (bits N to M) or (bit N) notation instead."
        exit 1
    }
done

# Static check: backslash line-continuation INSIDE a {...} list literal. Works in
# tclsh but Jim Tcl (OpenOCD) leaves the '\' as a literal element -> hardware-only
# breakage the tclsh mock can't catch. See feedback_tcl_jim_brace_continuation.
# Heuristic: a '{' with non-'}' content ending in '\' (brace-list continuation).
# (Command-context continuation like `[list \` is fine and won't match — no '{'.)
# Exclude expression braces (expr/if/while/elseif/for) — backslash continuation
# inside an EXPRESSION is fine in Jim; only LIST literals (foreach/set/lappend)
# break (the '\' becomes a literal list element).
BRACE_CONT=$(grep -nE '\{[^}]*\\$' openocd/*.tcl openocd/lib/*.tcl 2>/dev/null \
    | grep -vE '(expr|if|while|elseif|for)[[:space:]]*\{' || true)
if [ -n "$BRACE_CONT" ]; then
    echo "FAIL: backslash line-continuation inside a {...} list (breaks in Jim Tcl)"
    echo "$BRACE_CONT"
    echo "Use multi-line braces with NO backslash, e.g. foreach x {"
    echo "    a b c"
    echo "    d e f"
    echo "} { ... }"
    exit 1
fi

# Dynamic check: stub OpenOCD-specific commands and try to source the
# script end-to-end. Any uncaught Tcl error fails the test.
STUB_SCRIPT=$(mktemp)
trap "rm -f $STUB_SCRIPT" EXIT

cat > "$STUB_SCRIPT" <<'EOF'
proc targets {args} { return "" }
# Return hex string to mirror OpenOCD's real read_memory output. Catches
# hex/decimal regressions in code that gates on `string is integer` /
# numeric regex without considering 0x-prefixed input.
proc safe_rd {args} { return "0x12345678" }
proc safe_wr {args} { return 0 }
proc clear_dp_sticky {args} { return 0 }
proc reg {args} { return "0x12345678" }
proc read_memory {args} { return [list 0x00000000 0x00000001 0x00000002 0x00000003 0x00000004 0x00000005 0x00000006 0x00000007] }
proc halt {args} { return 0 }
proc uscale.dap {args} { return 0 }
proc uscale.axi {args} { return 0 }
proc uscale.a53.0 {args} { return "halted" }
proc jtag {args} { return "" }
proc after {args} { return 0 }
proc sleep {args} { return 0 }
proc echo {args} { return 0 }
proc exit {args} { return 0 }
if {[catch {source openocd/enumerate.tcl} err]} {
    puts stderr "DYNAMIC FAIL: $err"
    puts stderr $::errorInfo
    exit 1
}
puts "OK"
EOF

OUTPUT=$(tclsh "$STUB_SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "DYNAMIC FAIL\|FAIL:"; then
    echo "FAIL: dynamic smoke test"
    echo "$OUTPUT"
    exit 1
fi
if ! echo "$OUTPUT" | grep -q "^OK$"; then
    echo "FAIL: smoke test did not reach end of script"
    echo "$OUTPUT"
    exit 1
fi

# Clean up the stub-run reports (markdown + raw JSON, always timestamped today)
for pattern in "reports/enumerate-*.md" "reports/raw-*.json"; do
    RECENT=$(ls -t $pattern 2>/dev/null | head -1)
    if [ -n "$RECENT" ]; then
        # Only delete if it was created in the last minute (stub run we just did)
        if [ -n "$(find "$RECENT" -mmin -1 2>/dev/null)" ]; then
            rm "$RECENT"
        fi
    fi
done

echo "PASS: enumerate.tcl parses and runs end-to-end under stubs"

# ---------------------------------------------------------------------------
# Address-correctness audit (added 2026-05-28 audit B8).
# Cross-checks every register-name → address pair in code/docs against the
# canonical Xilinx QEMU register model. Catches the JTAG_SEC/DAP_CFG-swap
# class of bug that cost the project multiple debug sessions in 2026-05-27.
# ---------------------------------------------------------------------------

echo ""
echo "Verifying register-address consistency..."
if ! python3 tools/verify-addresses.py --quiet; then
    echo "FAIL: register-address mismatch (run 'python3 tools/verify-addresses.py' for details)"
    exit 1
fi
echo "PASS: all register addresses match canonical source"

echo ""
echo "Running handler-verdict unit tests..."
if ! tclsh tests/handler-verdicts.tcl >/tmp/handler-verdict-output 2>&1; then
    cat /tmp/handler-verdict-output
    echo "FAIL: handler-verdict tests"
    exit 1
fi
# Only print the PASS count summary on success.
grep -E "^Tests (run|passed|failed)" /tmp/handler-verdict-output || tail -3 /tmp/handler-verdict-output
echo "PASS: handler verdict logic"

# ---------------------------------------------------------------------------
# Phase 4 golden tests — only run if the golden directory exists. Lets the
# smoke test stay useful on a fresh checkout without forcing golden setup.
# ---------------------------------------------------------------------------

echo ""
echo "Checking annotation modules (typos, dead wildcards, unknown registers)..."
if ! python3 tools/check-annotations.py; then
    exit 1
fi

GOLDEN_DIR="tests/golden/zcu102-jtag-idle"
if [ -d "$GOLDEN_DIR" ]; then
    echo ""
    echo "Running golden tests (interpret.py output)..."
    if ! bash tools/golden-test.sh; then
        exit 1
    fi
    echo ""
    echo "Running roundtrip golden test (enumerate.tcl via mock)..."
    if ! bash tools/golden-test-roundtrip.sh; then
        exit 1
    fi
fi

echo ""
echo "Running debug-authentication rule test (DBGAUTHSTATUS decode + cross-check)..."
if ! python3 tests/rule-debug-auth.py; then
    echo "FAIL: rule-debug-auth test"
    exit 1
fi

echo ""
echo "Running CoreSight ROM-table walker test (ADIv5/v6 walk + PIDR identify)..."
if ! python3 tests/coresight-walk.py; then
    echo "FAIL: coresight-walk test"
    exit 1
fi

echo ""
echo "Running cross-arch debug-auth classifier test (OPEN/GATED/AUTHENTICATED/LOCKED)..."
if ! python3 tests/debugauth-classify.py; then
    echo "FAIL: debugauth-classify test"
    exit 1
fi

echo ""
echo "Running first-contact troubleshooting test (blocker KB + symptom routing)..."
if ! python3 tests/first-contact.py; then
    echo "FAIL: first-contact test"
    exit 1
fi

echo ""
echo "Running HTML report generator test (operator-first stylized report)..."
if ! bash tools/report-html-smoketest.sh; then
    echo "FAIL: report-html smoketest"
    exit 1
fi

echo ""
echo "Running jtag-to-shell planner test (live-patch/catch-in-flight/cold-boot/persist)..."
if ! python3 tests/jtagtoshell-plan.py; then
    echo "FAIL: jtagtoshell-plan test"
    exit 1
fi

echo ""
echo "Running boot-image parser + PHT-walk test..."
if ! bash tests/test-bootimage.sh; then
    echo "FAIL: boot-image test"
    exit 1
fi

# ---------------------------------------------------------------------------
# VxWorks build reproducibility (added 2026-06-10). Confirms
# build-vxboot/build_vxworks_zcu102.py still emits the three validated boot
# images byte-for-byte (v5p via --no-net, v5pg/v5pg3 by default). SKIPs cleanly
# if the build tools (mkbootimage) aren't provisioned, so this stays offline-safe.
# ---------------------------------------------------------------------------
echo ""
echo "Verifying VxWorks build reproduces the validated images..."
if ! bash tools/build-vxboot-smoketest.sh; then
    echo "FAIL: VxWorks build reproducibility"
    exit 1
fi

echo ""
echo "Running multi-board engine checks (board-runner + profiles)..."
if ! bash tools/board-runner-smoketest.sh; then
    echo "FAIL: board-runner smoketest"
    exit 1
fi

echo ""
echo "Running per-chip posture golden tests (decode + OFF->ON hardening flip)..."
if ! bash tools/posture-golden-test.sh; then
    echo "FAIL: posture golden tests"
    exit 1
fi

echo ""
echo "Running unlock-engine checks (Phase-2b enforcement classify + strategies)..."
if ! bash tools/unlock-engine-smoketest.sh; then
    echo "FAIL: unlock-engine smoketest"
    exit 1
fi

echo ""
echo "Running transport checks (backend-agnostic adapter layer: openocd/hw_server/libero)..."
if ! bash tools/transport-smoketest.sh; then
    echo "FAIL: transport smoketest"
    exit 1
fi

echo ""
echo "Running capability-matrix checks (adapter × backend × op grid + honest op routing)..."
if ! bash tools/capability-matrix-smoketest.sh; then
    echo "FAIL: capability-matrix smoketest"
    exit 1
fi

echo ""
echo "Running secure-boot analyzer checks (generic MCUboot/wolfBoot/FIT auth-structure findings)..."
if ! bash tools/secureboot-analyze-smoketest.sh; then
    echo "FAIL: secureboot-analyze smoketest"
    exit 1
fi

echo ""
echo "Running attack-graph checks (kill-chain planner: ordered path + honest BLOCKED stalls)..."
if ! bash tools/attack-graph-smoketest.sh; then
    echo "FAIL: attack-graph smoketest"
    exit 1
fi

echo ""
echo "Running bench-validate checks (per-board validation protocol: generate + grade)..."
if ! bash tools/bench-validate-smoketest.sh; then
    echo "FAIL: bench-validate smoketest"
    exit 1
fi

echo ""
echo "Running break-secrets checks (automatic secret-in-flight capture from break-capture derefs)..."
if ! bash tools/break-secrets-smoketest.sh; then
    echo "FAIL: break-secrets smoketest"
    exit 1
fi

echo ""
echo "Running coverage-chart generator checks (chart generated from live data — no drift)..."
if ! bash tools/gen-coverage-chart-smoketest.sh; then
    echo "FAIL: gen-coverage-chart smoketest"
    exit 1
fi

echo ""
echo "Running extract-plan checks (per-board extraction: mem-AP + vendor ROM loaders + chip-off)..."
if ! bash tools/extract-plan-smoketest.sh; then
    echo "FAIL: extract-plan smoketest"
    exit 1
fi

echo ""
echo "Running preflight checks (engagement blocker check: adapters/backends/transport → GO/BLOCKED)..."
if ! bash tools/preflight-smoketest.sh; then
    echo "FAIL: preflight smoketest"
    exit 1
fi

echo ""
echo "Running unlock-workflow checks (guided reopen→verify loop; core locked-board mission)..."
if ! bash tools/unlock-workflow-smoketest.sh; then
    echo "FAIL: unlock-workflow smoketest"
    exit 1
fi

echo ""
echo "Running mock-xsdb checks (hw_server path rehearsed against the high-fidelity mock)..."
if ! bash tools/mock-xsdb-smoketest.sh; then
    echo "FAIL: mock-xsdb smoketest"
    exit 1
fi

echo ""
echo "Running GUI checks (offscreen end-to-end shell; SKIPs without PySide6)..."
if ! bash tools/gui-smoketest.sh; then
    echo "FAIL: gui smoketest"
    exit 1
fi

echo ""
echo "Running console-mock checks (console command surface under both backend mocks)..."
if ! bash tools/console-mock-smoketest.sh; then
    echo "FAIL: console-mock smoketest"
    exit 1
fi

echo ""
echo "Running mock-fidelity checks (per-region memory + captured regs + hardened-board rehearsal)..."
if ! bash tools/mock-fidelity-smoketest.sh; then
    echo "FAIL: mock-fidelity smoketest"
    exit 1
fi

echo ""
echo "Running mock-cortexm checks (SmartFusion2 M3 eNVM extraction; open vs debug-locked)..."
if ! bash tools/mock-cortexm-smoketest.sh; then
    echo "FAIL: mock-cortexm smoketest"
    exit 1
fi

echo ""
echo "Running mock-board checks (parametric per-board chain + flash dump + locked fault)..."
if ! bash tools/mock-board-smoketest.sh; then echo "FAIL: mock-board smoketest"; exit 1; fi

echo ""
echo "Running mock-secureboot checks (auth/key bypass model: JustSTART / Starbleed)..."
if ! bash tools/mock-secureboot-smoketest.sh; then echo "FAIL: mock-secureboot smoketest"; exit 1; fi

echo ""
echo "Running CLI adversarial checks (every tool vs missing/empty/garbage input, as a real subprocess)..."
if ! bash tools/cli-adversarial-smoketest.sh; then echo "FAIL: cli-adversarial smoketest"; exit 1; fi

echo ""
echo "Running happy-path checks (tools coverage flagged as zero/near-zero: good input, real assertions)..."
if ! bash tools/happy-path-smoketest.sh; then echo "FAIL: happy-path smoketest"; exit 1; fi

echo ""
echo "Running cortexm-posture checks (real .tcl round-trip + mock matrix, board-generic Dashboard posture)..."
if ! bash tools/cortexm-posture-smoketest.sh; then echo "FAIL: cortexm-posture smoketest"; exit 1; fi

exit 0
