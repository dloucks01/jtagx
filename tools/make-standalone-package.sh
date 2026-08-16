#!/usr/bin/env bash
# make-standalone-package.sh — build a SELF-SUFFICIENT engagement kit that runs on an air-gapped Kali
# (no OpenOCD installed, no internet). Bundles a portable OpenOCD (binary + its shared libs + a wrapper),
# the Python deps (capstone), the whole toolkit, and an entry point. Also stages the .deb files as an
# install fallback. Output: a self-contained directory you can burn to a CD/USB and run in place.
#
# Run this on a machine that DOES have openocd + capstone + internet (to gather the bundle). Then copy
# the output dir to the target. The bundle is glibc/arch-portable across the SAME Kali release family
# (it does NOT bundle libc/ld-linux — it uses the target's). If the portable path ever fails, the kit's
# install-offline.sh dpkg-installs the staged .debs instead.
#
# Usage:  tools/make-standalone-package.sh [output-dir]   (default: dist/jtag-engagement-kit)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/jtag-engagement-kit}"
WITH_PDFS="${WITH_PDFS:-0}"     # set WITH_PDFS=1 to also copy references/pdf (≈200M)

say(){ printf '>> %s\n' "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1"; exit 1; }; }
need openocd; need ldd; need rsync

rm -rf "$OUT"; mkdir -p "$OUT"
say "building kit at $OUT"

# ---- 1. the toolkit (operator-facing only — no dev/CI suite, no research/historical docs) ----
say "copying toolkit (openocd scripts / operational tools / profiles / boards / docs)"
# openocd: all the live JTAG scripts, minus the test-only mock harness
rsync -a --exclude='__pycache__' --exclude='lib/mock-openocd.tcl' "$ROOT/openocd/" "$OUT/openocd/"
rsync -a --exclude='__pycache__' "$ROOT/profiles/" "$OUT/profiles/"
rsync -a --exclude='__pycache__' "$ROOT/boards/" "$OUT/boards/"
# jtagx: the Python ENGINE PACKAGE — transport/unlock/extraction/coresight/debugauth/firstcontact/
# jtagtoshell/weakness/cve/attackgraph/preflight/posture/paths. 16+ of the operational tools/*.py
# scripts (preflight, cve-match, engagement-report, unlock-engine, jtag-to-shell, first-contact,
# attack-graph, extract-plan, capability-matrix, bench-validate, transport-probe, report-html,
# gen-coverage-chart, bsdl-scan, ...) `from jtagx import ...` at MODULE LOAD, not lazily — omitting
# this directory was found (2026-08-15) to make every one of them crash with ModuleNotFoundError on
# first cold run from a built kit, even though interpret.py's OWN jtagx import degrades gracefully
# (it's wrapped in try/except) and so never surfaced the gap. See tools/cli-adversarial-smoketest.sh
# for the CLI-level regression test and the kit-build-smoketest.sh for the packaging-level one.
rsync -a --exclude='__pycache__' "$ROOT/jtagx/" "$OUT/jtagx/"
# the small CoreSight PIDR->name lookup jtagx/coresight.py reads at runtime — NOT the bulk vendor-PDF
# reference material gated behind WITH_PDFS (this one file is a few KB of our own curated data, and
# skipping it only degrades identification quality — see the graceful _load_parts() fallback — but
# there's no reason to leave it out of the default kit when it's this small).
mkdir -p "$OUT/references"
cp "$ROOT/references/coresight-parts.json" "$OUT/references/coresight-parts.json"
# payloads: the runnable .bin (loaded by inject.tcl / dump-bootrom) + the README; drop build scaffolding
# (.S/.o/.elf/.lds/Makefile — can't rebuild on the target anyway, no cross-toolchains there)
rsync -a --exclude='*.o' --exclude='*.elf' --exclude='*.S' --exclude='*.lds' --exclude='Makefile' \
    "$ROOT/payloads/" "$OUT/payloads/"
# tools: the OPERATIONAL ones; drop the dev/CI runners (they prove code correctness — a frozen tarball
# can't change that — and need tests/, which the kit doesn't ship). selftest.sh below replaces them.
rsync -a --exclude='__pycache__' \
    --exclude='*-smoketest.sh' --exclude='golden-test*.sh' --exclude='posture-golden-test.sh' \
    --exclude='check-annotations.py' --exclude='generate-mock-seed.py' --exclude='regenerate-qemu-regs.py' \
    --exclude='verify-addresses.py' --exclude='make-standalone-package.sh' \
    "$ROOT/tools/" "$OUT/tools/"
# docs: keep ALL the project's .md documentation (it's small + self-consistent — no dead cross-links) plus
# the REQUIRED .py modules interpret.py imports. Drop only the non-doc BULK: the whitepaper (a duplicate
# narrative deliverable) and the vendor-source mirror, and any .pdf/.docx.
rsync -a --exclude='__pycache__' --exclude='*.pdf' --exclude='*.docx' \
    --exclude='whitepaper' --exclude='xilinx-references' "$ROOT/docs/" "$OUT/docs/"
# output dirs the live scripts + the self-test write to (must exist)
mkdir -p "$OUT/reports" "$OUT/dumps"
: > "$OUT/reports/.keep"; : > "$OUT/dumps/.keep"
# the register-source PDFs are reference, not runtime — opt in with WITH_PDFS=1
if [ "$WITH_PDFS" = 1 ]; then say "including references/pdf (WITH_PDFS=1)"; rsync -a "$ROOT/references/" "$OUT/references/"; fi

# ---- 2. portable OpenOCD (binary + its non-glibc shared libs + stock scripts + a wrapper) ----
say "bundling OpenOCD ($(openocd --version 2>&1 | head -1))"
OO="$OUT/vendor/openocd"; mkdir -p "$OO/bin" "$OO/lib" "$OO/scripts"
cp "$(command -v openocd)" "$OO/bin/openocd.real"
# copy every shared lib EXCEPT the core glibc/loader ones (use the target's those)
ldd "$(command -v openocd)" | awk '/=>/ {print $3}' | grep -E '^/' | while read -r lib; do
    base="$(basename "$lib")"
    case "$base" in libc.so*|libm.so*|libpthread.so*|libdl.so*|ld-linux*|libgcc_s.so*|librt.so*) continue;; esac
    cp -L "$lib" "$OO/lib/" 2>/dev/null || true
done
cp -a /usr/share/openocd/scripts/. "$OO/scripts/" 2>/dev/null || true
cat > "$OO/bin/openocd" <<'WRAP'
#!/bin/sh
# portable OpenOCD wrapper — uses the bundled libs + stock scripts, no system install needed.
OO="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$OO/lib:${LD_LIBRARY_PATH:-}"
exec "$OO/bin/openocd.real" -s "$OO/scripts" "$@"
WRAP
chmod +x "$OO/bin/openocd"

# ---- 3. Python deps (capstone — optional, used by ghidra-loadspec.py) ----
say "bundling capstone (python)"
PY="$OUT/vendor/python"; mkdir -p "$PY"
CAP="$(python3 -c 'import capstone, os; print(os.path.dirname(capstone.__file__))' 2>/dev/null || true)"
if [ -n "$CAP" ] && [ -d "$CAP" ]; then cp -a "$CAP" "$PY/"; else say "  (capstone not found — ghidra-loadspec arch-detect will degrade gracefully)"; fi

# ---- 4. .deb install fallback (robust on the same Kali release) ----
say "staging .deb fallback (apt-get download; needs internet on THIS machine)"
DEBS="$OUT/vendor/debs"; mkdir -p "$DEBS"
if apt-get download openocd 2>/dev/null; then
    mv ./*.deb "$DEBS/" 2>/dev/null || true
    # the runtime libs openocd links (best-effort; already-installed ones are skipped by dpkg on target)
    apt-get download libftdi1-2 libusb-1.0-0 libhidapi-hidraw0 libjaylink0 libcapstone5 libjim0.83 2>/dev/null || true
    mv ./*.deb "$DEBS/" 2>/dev/null || true
    say "  staged $(ls "$DEBS" | wc -l) .deb(s)"
else
    say "  (apt-get download failed/offline — portable bundle is the primary path; debs skipped)"
fi

# ---- 5. environment + entry points ----
say "writing env.sh / engage.sh / install-offline.sh / selftest.sh"
# install-udev-rules.sh is a real file (tools/), already bundled into $OUT/tools/ by the rsync above;
# also copy it to the kit root so it sits alongside the other entry points (env.sh/engage.sh/
# install-offline.sh/selftest.sh) instead of being the one operator-run script buried in tools/.
cp "$ROOT/tools/install-udev-rules.sh" "$OUT/install-udev-rules.sh"
chmod +x "$OUT/install-udev-rules.sh"
cat > "$OUT/env.sh" <<'ENV'
# source this to use the bundled tools:  . ./env.sh
KIT="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)"
export PATH="$KIT/vendor/openocd/bin:$PATH"
export PYTHONPATH="$KIT/vendor/python:${PYTHONPATH:-}"
export JTAG_KIT="$KIT"
echo "JTAG kit ready. openocd -> $(command -v openocd). Try: ./engage.sh --list"
ENV
cat > "$OUT/engage.sh" <<'ENG'
#!/usr/bin/env bash
# engage.sh — entry point. Sources the bundled env, then runs the multi-board engine.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"; cd "$KIT"
export PATH="$KIT/vendor/openocd/bin:$PATH"
export PYTHONPATH="$KIT/vendor/python:${PYTHONPATH:-}"
if [ $# -eq 0 ]; then
    echo "JTAG multi-board engagement kit"
    echo "  ./engage.sh --list                       # profiles available"
    echo "  ./engage.sh --from-log firstcontact.log  # identify an unknown board -> plan"
    echo "  ./engage.sh --profile stm32f4            # operator-assert a board"
    echo "  ./selftest.sh                            # verify the kit (offline)"
    echo "  docs/26-unknown-board-walkthrough.md     # the step-by-step runbook"
    exit 0
fi
exec python3 tools/board-runner.py "$@"
ENG
chmod +x "$OUT/engage.sh"
cat > "$OUT/install-offline.sh" <<'INST'
#!/bin/sh
# FALLBACK only — the portable bundle (vendor/openocd/bin/openocd) needs no install. Use this only if the
# portable binary won't run on your target (e.g. a very different release). Installs the staged .debs.
set -e
KIT="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$(ls -A "$KIT/vendor/debs" 2>/dev/null)" ]; then echo "no .debs staged"; exit 1; fi
echo "installing staged .debs (needs root)..."; sudo dpkg -i "$KIT"/vendor/debs/*.deb || sudo apt-get -f install -y
INST
chmod +x "$OUT/install-offline.sh"
cat > "$OUT/selftest.sh" <<'TST'
#!/usr/bin/env bash
# selftest.sh — confirm the BUNDLE runs on THIS machine (it survived the transfer). This is NOT a code-
# correctness test (that was proven in the dev tree at build time and can't change in a frozen tarball) —
# it checks the things that CAN break in transit: the bundled openocd binary/libs/arch, and python.
set -u
KIT="$(cd "$(dirname "$0")" && pwd)"; cd "$KIT"
export PATH="$KIT/vendor/openocd/bin:$PATH"; export PYTHONPATH="$KIT/vendor/python:${PYTHONPATH:-}"
fail(){ echo "FAIL: $1"; exit 1; }
echo "== bundled OpenOCD =="; openocd --version 2>&1 | head -1 || fail "bundled openocd won't run here (lib/arch mismatch — try ./install-offline.sh)"
echo "== engine (board-runner) =="
python3 tools/board-runner.py --validate >/dev/null || fail "board-runner --validate"
python3 tools/board-runner.py --list | sed 's/^/   /'
python3 tools/board-runner.py --profile stm32f4 >/dev/null || fail "board-runner --profile (plan generation)"
echo "== jtagx engine package (transport/unlock/extraction/cve/attackgraph/...) =="
python3 -c "import jtagx" || fail "jtagx package not importable — the kit is missing jtagx/ (packaging bug)"
# actually RUN two of the many tools/*.py that import jtagx at module load (not just ast.parse the
# syntax below, which never executes an import and would NOT have caught this): a missing jtagx/
# broke preflight.py, cve-match.py, engagement-report.py, unlock-engine.py, jtag-to-shell.py,
# first-contact.py, attack-graph.py, extract-plan.py, capability-matrix.py, bench-validate.py,
# transport-probe.py, report-html.py, gen-coverage-chart.py, bsdl-scan.py, and mock-xsdb.py — every
# one of them, cold, with ModuleNotFoundError — while this exact check block reported "OK" (this IS
# the fix for that: 2026-08-15, see the packaging comment on the jtagx rsync above).
# preflight.py legitimately exits 1 with no adapter plugged in (this IS that environment) — check
# for the ABSENCE of a crash/traceback, not the exit code, or a correct BLOCKED verdict false-fails.
PF_OUT=$(python3 tools/preflight.py --soc zynqmp 2>&1)
if grep -q "Traceback (most recent call last)" <<<"$PF_OUT"; then fail "preflight.py --soc zynqmp crashed (jtagx import?): $(head -1 <<<"$PF_OUT")"; fi
python3 tools/cve-match.py --soc zynqmp --jtag-open >/dev/null || fail "cve-match.py --soc zynqmp (jtagx import)"
echo "== analyzers parse =="
for m in board-runner dram-secrets dump-triage ghidra-loadspec parse-bootimage interpret; do
    python3 -c "import ast; ast.parse(open('tools/$m.py').read())" || fail "tools/$m.py syntax"
done
python3 -c "import capstone" 2>/dev/null && echo "   capstone OK (ghidra-loadspec arch-detect available)" \
    || echo "   capstone not importable (ghidra-loadspec degrades gracefully)"
echo "== vendor backend software (NOT bundled -- proprietary; see README-KIT.md 3b) =="
command -v openocd >/dev/null 2>&1 && echo "   openocd:    bundled (vendor/openocd) + $(command -v openocd)" \
    || echo "   openocd:    bundled (vendor/openocd/bin) -- no system copy on PATH, that's fine"
if command -v xsdb >/dev/null 2>&1 || command -v hw_server >/dev/null 2>&1; then
    echo "   hw_server/xsdb: found on PATH -- SmartLynq2/Platform Cable USB II are usable"
else
    echo "   hw_server/xsdb: NOT found -- SmartLynq2/Platform Cable need AMD Vitis Lab Tools/Vivado"
    echo "                   Lab Edition installed separately (README-KIT.md 3b), or bridge via XVC"
fi
if command -v FPExpress >/dev/null 2>&1 || command -v FlashProExpress >/dev/null 2>&1 || command -v libero >/dev/null 2>&1; then
    echo "   Libero/FlashPro Express: found on PATH -- FlashPro4/5 are usable"
else
    echo "   Libero/FlashPro Express: NOT found -- FlashPro4/5 need Microchip Libero/FlashPro Express"
    echo "                   installed separately (README-KIT.md 3b), or the ftdi_sio-unbind path"
    echo "                   for generic-cable enumeration-only work (openocd/adapters/flashpro-notes.md)"
fi
echo "kit selftest: OK — the bundle runs on this machine."
TST
chmod +x "$OUT/selftest.sh"

# ---- 6. kit README (the operator's full get-it-running guide — this IS the in-package documentation) ----
cat > "$OUT/README-KIT.md" <<'MD'
# JTAG Multi-Board Engagement Kit — standalone

Self-sufficient. Copy to an **air-gapped Kali** (NO OpenOCD, NO internet) and run in place — nothing to
install. Bundles a portable OpenOCD + its libraries + capstone, plus the whole toolkit.

---

## Get it running on a fresh Kali (step by step)

**1. Copy the tarball off the CD/USB and extract:**
```
tar xzf jtag-engagement-kit.tar.gz
cd jtag-engagement-kit
```

**2. Confirm the bundle runs on THIS machine:**
```
./selftest.sh
```
Should end `kit selftest: OK` and list the supported boards. If it says *"bundled openocd won't run here"*
(different glibc/arch than where it was built) use the offline .deb fallback, then re-check:
```
./install-offline.sh      # sudo dpkg -i vendor/debs/*.deb  (no internet needed)
./selftest.sh
```

**3. Hardware:**
- Plug in your JTAG/SWD adapter (FT2232H, J-Link, ST-Link, CMSIS-DAP, SmartLynq2, FlashPro…).
- **If this Kali is in a VM, enable USB passthrough** for the adapter.
- Check the OS sees it: `lsusb` (e.g. `0403:6010` for an FTDI).
- OpenOCD needs USB access — the usual fresh-box gotcha. One-time fix (recommended, no more `sudo`
  for every run after this): `sudo bash install-udev-rules.sh` — installs
  `openocd/adapters/99-jtagx-kit.rules` (every adapter this kit's board profiles know about — FTDI
  family, J-Link, ST-Link, CMSIS-DAP/DAPLink, Altera Blaster, Atmel-ICE, WCH-Link, RP2040 Debug Probe,
  plus AMD Platform Cable/SmartLynq2 and Microsemi FlashPro4/5 for their hw_server/Libero backends)
  and adds you to the `plugdev` group. Unplug/replug the adapter afterward. Skip this and just prefix
  live commands with `sudo vendor/openocd/bin/openocd …` if you'd rather not touch system udev rules.

**3b. Vendor backend software — NOT bundled (know this before you're mid-engagement):**
This kit bundles OpenOCD (open-source, GPL) and everything it needs. It does **not**, and legally
cannot, bundle the proprietary vendor software two of the adapters above route through —
`jtagx.transport` picks the right one automatically, but only if it's actually installed:
- **AMD SmartLynq / SmartLynq2, Platform Cable USB II** → need `xsdb` + `hw_server`, which ship with
  **AMD Vitis Lab Tools** (or Vivado Lab Edition — same install, smaller than full Vivado but still a
  multi-GB download, free AMD account required: https://www.xilinx.com/support/download.html).
  Alternative that avoids installing it at all: bridge the adapter to OpenOCD over **XVC** (hw_server
  can expose an XVC server; OpenOCD's `xvc` driver speaks to it over TCP, keeping the existing
  OpenOCD-Tcl scripts working) — see the Chain page's XVC hint in the GUI, or `docs/22-multi-board-engine.md`.
- **Microsemi/Microchip FlashPro4/5** → need **Libero SoC** or the smaller standalone **FlashPro
  Express** (Microchip account required). See `openocd/adapters/flashpro-notes.md` for the
  `ftdi_sio`-unbind path that lets a *generic* FTDI cable do enumeration-only work on these targets
  without any Microchip software at all.
- Check what's actually usable on THIS box right now, for a specific target, before you rely on it:
  `python3 tools/preflight.py --soc <soc>` — gives a live GO/BLOCKED verdict + the exact fix if the
  backend software for your adapter isn't found on PATH.

**4. First contact — scan the chain for IDCODEs** (point JTAG_IFACE at your adapter; interface cfgs live in
the bundled `vendor/openocd/scripts/interface/…`):
```
JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
  sudo vendor/openocd/bin/openocd -f openocd/board-template.cfg \
    -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee firstcontact.log
```
Generic FTDI/FT232H adapter stanzas ship in `openocd/adapters/`; for a J-Link/ST-Link/CMSIS-DAP use the
bundled stock cfg instead (`JTAG_IFACE=interface/jlink.cfg`, `interface/stlink.cfg`, `interface/cmsis-dap.cfg`).

**5. Identify + get a plan** (offline, no sudo):
```
./engage.sh --from-log firstcontact.log     # auto-identify -> a tiered, numbered plan
# or, if you already know the chip:
./engage.sh --profile stm32f4               # ./engage.sh --list shows all 11
```
The plan tags each step `[LIVE]` (run on the board, with sudo), `[OFFLINE]` (analysis, safe now), or
`[VENDOR]` (a vendor tool, e.g. FlashPro for IGLOO2). **Then follow `docs/26-unknown-board-walkthrough.md`**
— the full connect → verdict → enumerate → dump → analyze runbook with expected output + failure modes.

**What the target already has (all the kit needs from the OS):** `python3`, `bash`, `lsusb`, `sudo`.
Everything else (OpenOCD, its libs, capstone) is bundled.

---

## What's in this kit (and why)

| Path | Why it's here |
|---|---|
| `engage.sh` / `env.sh` / `selftest.sh` / `install-offline.sh` | entry point / shell setup / on-machine check / .deb fallback |
| `vendor/openocd/` | **portable OpenOCD** — binary + its shared libs + stock target/interface scripts + a wrapper |
| `vendor/python/capstone` | arch detection for `ghidra-loadspec.py` (the other analyzers are pure stdlib) |
| `vendor/debs/` | fallback .deb install, used only if the portable binary won't run |
| `tools/` | the engine `board-runner.py` + the offline analyzers (dram-secrets, dump-triage, ghidra-loadspec, …) |
| `openocd/` | the **live JTAG scripts** — enumerate/posture, flash+RAM dump, reopen, Cap-2 patch, the board cfgs |
| `profiles/` | one data fact-sheet per chip (11 boards). Add a board = add a JSON, no code change |
| `boards/` | a harvested per-board env (target names / boot media / DDR base) |
| `payloads/` | bare-metal `.bin` injected over JTAG for the advanced ZynqMP paths (R5 ROM, PMU, reopen-via-code) |
| `docs/` | the full doc set — tool manuals (05, 09, 11), bring-up (18), the **walkthroughs** (19, 21, 23, **26**), the capability matrix (22), the cited attribute catalogs (24, 25), the internals/research references (12–17, 20), appendices, a quick-reference, + the `*.py` modules `interpret.py` imports |
| `reports/` `dumps/` | empty — where the live scripts write their output |

**Deliberately NOT included** (it's an operator kit, not the dev repo): the test/CI suite, the whitepaper
(a duplicate narrative), and the vendor-source mirrors.

> Note: the docs are the project's full documentation, so a few of them *mention* dev/CI files that this
> kit doesn't bundle (e.g. "validated by `tcl-smoketest.sh` / `golden-test*`", or `openocd/lib/mock-openocd.tcl`).
> Those are informational "how it was tested" notes — no operator step depends on them. `openocd/last-discovered.tcl`
> is normal: `discover.tcl` writes it at runtime.

## Honesty
Every profile except **ZynqMP** is **HW-unvalidated** — addresses are vendor-doc-cited and audited, and the
enumerate/protect scripts **self-check against the live silicon on first contact** (the sanity gates abort if
the identity register isn't what's expected). Still: confirm the access verdict + a sanity read before any
bulk dump. The bundled OpenOCD is glibc/arch-portable within the same Kali release family.
MD

# ---- 7. roll the single distributable tarball (this is the artifact you carry to the target) ----
TARBALL="$(dirname "$OUT")/$(basename "$OUT").tar.gz"
say "rolling tarball $TARBALL"
tar -czf "$TARBALL" -C "$(dirname "$OUT")" "$(basename "$OUT")"

# ---- summary ----
say "DONE."
echo "  staged dir : $(du -sh "$OUT" | awk '{print $1}')   $OUT"
echo "  TARBALL    : $(du -h "$TARBALL" | awk '{print $1}')   $TARBALL"
echo
echo "  On the air-gapped target:"
echo "    tar xzf $(basename "$TARBALL") && cd $(basename "$OUT")"
echo "    ./selftest.sh        # confirm the bundle runs here"
echo "    ./engage.sh --list   # then follow docs/26-unknown-board-walkthrough.md"
