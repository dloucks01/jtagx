#!/usr/bin/env bash
# cli-adversarial-smoketest.sh — every CLI tool, invoked as a REAL subprocess (exactly how an
# operator runs it) against missing/empty/garbage input, asserting a CLEAN error (non-zero exit,
# no raw Python traceback) instead of a crash.
#
# Why this exists: a "32/32 passing" offline suite can still ship a tool that crashes on first
# real use, if every test that touches it only imports and calls its functions directly — that
# skips argv parsing, file I/O, and error paths entirely. This harness is the adversarial pass:
# it runs the tool as a subprocess the way a user actually would, and only checks two things —
# does it exit non-zero on bad input, and does it fail with a clean message instead of a raw
# traceback. It does NOT replace each tool's own correctness tests; it's the "did anyone ever
# actually try to break this" pass that a happy-path suite structurally cannot provide.
#
# Found + fixed 9 real crash bugs writing this (2026-08-15): psu-init-to-jtag.py (missing
# __main__ guard + unconditional module-scope file open — a guaranteed crash in the default
# standalone kit, which bundles the tool but not its vendor-source dependency),
# bootrom-fuzz-triage.py, symbolize.py, vxworks-symtab.py, qspi-make-patch.py,
# bootrom-fuzz-gen.py, ghidra-loadspec.py (all: raw traceback on a missing input file),
# generate-mock-seed.py + hexdump-attributes.py (raw traceback on malformed/empty JSON — a
# *different* bug class than the missing-file case, on tools that already handled THAT case
# cleanly — proof that "half fixed" reads as "fixed" unless every input class is tried).
set -uo pipefail   # NOT -e: individual adversarial probes are EXPECTED to fail; we check *how*.
cd "$(dirname "$0")/.."

FAILS=0
fail() { echo "FAIL(cli-adversarial): $1"; FAILS=$((FAILS+1)); }

ADV="$(mktemp -d)"
trap 'rm -rf "$ADV"' EXIT
: > "$ADV/empty.bin"
: > "$ADV/empty.json"
: > "$ADV/empty.txt"
head -c 256 /dev/urandom > "$ADV/garbage.bin"
echo 'not json at all {{{' > "$ADV/garbage.json"
printf 'garbage\x00\x01\x02 not a symbol map\n' > "$ADV/garbage.txt"
printf '0x1000 aes_key\n' > "$ADV/syms.txt"
NOPE="$ADV/does-not-exist"

# clean_fail CMD... — runs a command, asserts exit != 0 AND no raw traceback in its output.
clean_fail() {
    local desc="$1"; shift
    local out rc
    out=$("$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "$desc: expected non-zero exit on bad input, got 0"
        return
    fi
    if grep -q "Traceback (most recent call last)" <<<"$out"; then
        fail "$desc: raw Python traceback leaked to the user (exit=$rc): $(head -1 <<<"$out")"
        return
    fi
}

# --- the 9 confirmed-and-fixed bugs, regression-guarded ---
clean_fail "psu-init-to-jtag.py (missing vendor source)" \
    bash -c 'cd "$0" && python3 tools/psu-init-to-jtag.py' "$ADV"
clean_fail "bootrom-fuzz-triage.py (missing log+manifest)" \
    python3 tools/bootrom-fuzz-triage.py "$NOPE.log" "$NOPE.json"
clean_fail "symbolize.py (missing --syms)" \
    python3 tools/symbolize.py 0x1000 --syms "$NOPE.txt"
clean_fail "symbolize.py (garbage --syms)" \
    python3 tools/symbolize.py 0x1000 --syms "$ADV/garbage.txt"
clean_fail "vxworks-symtab.py (missing image)" \
    python3 tools/vxworks-symtab.py "$NOPE.bin"
clean_fail "qspi-make-patch.py (missing image)" \
    python3 tools/qspi-make-patch.py "$NOPE.bin" --offset 0x100 --hex deadbeef -o "$ADV/x.tcl"
clean_fail "qspi-make-patch.py (empty/too-short image)" \
    python3 tools/qspi-make-patch.py "$ADV/empty.bin" --offset 0x100 --hex deadbeef -o "$ADV/x.tcl"
clean_fail "bootrom-fuzz-gen.py (missing base image)" \
    python3 tools/bootrom-fuzz-gen.py "$NOPE-BOOT.BIN"
clean_fail "ghidra-loadspec.py (missing image)" \
    python3 tools/ghidra-loadspec.py "$NOPE.bin"
clean_fail "generate-mock-seed.py (empty JSON)" \
    python3 tools/generate-mock-seed.py "$ADV/empty.json"
clean_fail "generate-mock-seed.py (garbage JSON)" \
    python3 tools/generate-mock-seed.py "$ADV/garbage.json"
clean_fail "hexdump-attributes.py (garbage JSON)" \
    python3 tools/hexdump-attributes.py "$ADV/garbage.json"

# --- already-clean tools, kept as regression anchors so a future edit can't silently break them ---
clean_fail "hexdump-attributes.py (missing capture)" \
    python3 tools/hexdump-attributes.py "$NOPE.json"
clean_fail "symbol-crypto.py (missing dump+syms)" \
    python3 tools/symbol-crypto.py "$NOPE.bin" --syms "$NOPE.txt"
clean_fail "find-patch-target.py (missing image)" \
    python3 tools/find-patch-target.py "$NOPE.bin"
# NOTE: an EMPTY image is not an error for this tool — it's a report-generator ("scanned it,
# found 0 candidates" is a valid, successful outcome), so it correctly exits 0. Only a MISSING
# file (can't even open it) is the adversarial case worth asserting non-zero exit on.
clean_fail "jtag-to-shell.py (missing --from-capture)" \
    python3 tools/jtag-to-shell.py --from-capture "$NOPE.json"
clean_fail "gen-board-cfg.py (missing --from-discovery)" \
    python3 tools/gen-board-cfg.py --from-discovery "$NOPE.log"
clean_fail "make-fuzz-base.py (missing peta image)" \
    python3 tools/make-fuzz-base.py "$NOPE-peta.bin"

# --- psu-init-to-jtag.py: import-safety regression guard (the __main__-guard fix) ---
# importing the module must NOT execute anything (no side-effect file write, no crash) — this is
# what let the original bug hide: any test harness that imported it for introspection would have
# silently regenerated openocd/psu-init-replay.tcl (or crashed) as an import side effect.
IMPORT_CHECK=$(python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('psu_init_to_jtag', 'tools/psu-init-to-jtag.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print('OK' if callable(getattr(mod, 'main', None)) else 'MISSING-MAIN')
" 2>&1)
if [ "$IMPORT_CHECK" != "OK" ]; then
    fail "psu-init-to-jtag.py: importing the module should be side-effect-free (got: $IMPORT_CHECK)"
fi

# --- happy-path regression guard: the fixes above must not have broken the working case ---
if ! python3 tools/hexdump-attributes.py tests/golden/zcu102-jtag-idle/raw.json >/dev/null 2>&1; then
    fail "hexdump-attributes.py: happy path broke after the JSON-error-handling fix"
fi
if ! python3 tools/generate-mock-seed.py tests/golden/zcu102-jtag-idle/raw.json -o "$ADV/seed.tcl" >/dev/null 2>&1; then
    fail "generate-mock-seed.py: happy path broke after the JSON-error-handling fix"
fi
if [ -f openocd/psu-init-replay.tcl ]; then
    HASH_BEFORE=$(sha256sum openocd/psu-init-replay.tcl | cut -d' ' -f1)
    if python3 tools/psu-init-to-jtag.py >/dev/null 2>&1; then
        HASH_AFTER=$(sha256sum openocd/psu-init-replay.tcl | cut -d' ' -f1)
        if [ "$HASH_BEFORE" != "$HASH_AFTER" ]; then
            fail "psu-init-to-jtag.py: regeneration changed openocd/psu-init-replay.tcl (should be deterministic/idempotent)"
        fi
    fi
    # else: vendor source not present in this checkout — the missing-file path is already covered above
fi

if [ "$FAILS" -eq 0 ]; then
    echo "PASS: cli-adversarial (12 confirmed-fixed bugs regression-guarded + 7 clean-tool anchors + happy-path checks)"
    exit 0
else
    echo "FAIL: cli-adversarial ($FAILS check(s) failed)"
    exit 1
fi
