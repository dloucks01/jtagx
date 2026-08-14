#!/usr/bin/env bash
# probe-board.sh — once a board is PHYSICALLY connected, take it from "unknown board" to a
# READY-TO-ENUMERATE config + an access verdict, halting at the first gate that fails. It does
# NOT enumerate — that's a separate, deliberate step you run against the cfg this produces:
#     openocd -f openocd/<name>.cfg -c "init; source openocd/enumerate.tcl; shutdown"
#
#   adapter (lsusb) -> speed-ladder chain scan -> decode IDCODE -> [ZynqMP?] generate cfg
#     -> access verdict (jtag-access-check) -> hand off the cfg + verdict
#
# WHAT IT CANNOT DO (see docs/18 "bootstrap paradox" + the harsh critique):
#   * fix PHYSICAL problems — wrong voltage / pinout / dead wire -> zero IDCODEs -> NO-CHAIN, stop.
#   * bring up a NON-STANDARD scan chain (extra CPLD / odd IRLEN) — that fails init before any
#     identification is possible; it captures the raw IDCODEs and stops for manual chain work.
#   * guarantee a clock speed is stable for bulk transfers just because IDCODEs read at it.
#
# SAFETY: strictly READ-ONLY — no reset, no halt, no writes. It runs OpenOCD live, repeatedly.
# YOU launch it (the operator drives JTAG). Only run against a board you are authorized to test.
# It STOPS and reports at every gate rather than forcing past a restricted/locked DAP.
#
# Usage (all flags optional):
#   tools/probe-board.sh [--name <board>] [--adapter <iface>] [--speeds "200 1000"]
#                        [--target <cfg>] [--force]
#   --name defaults to a name derived from the detected SoC (e.g. openocd/zynqmp-zu9.cfg).
# Override the OpenOCD binary for testing:  OPENOCD=/path/to/fake tools/probe-board.sh ...
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPENOCD="${OPENOCD:-openocd}"
NAME=""; ADAPTER=""; SPEEDS="200 1000"; TARGET="target/xilinx_zynqmp.cfg"; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --adapter) ADAPTER="$2"; shift 2;;
    --speeds) SPEEDS="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --force) FORCE="--force"; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done
# --name is optional: if omitted, gen-board-cfg.py derives it from the detected SoC (e.g.
# zynqmp-zu9) and we capture the path it writes.
LOG=$(mktemp); ACC=$(mktemp); trap 'rm -f "$LOG" "$ACC"' EXIT
hr(){ echo "================================================================"; }
stop(){ hr; echo " STOP — $1"; hr; exit "${2:-1}"; }
# No "proceed?" prompt: probe-board is strictly read-only and the operator launched it — running
# it IS the consent. The deliberate human gate lives before the SEPARATE enumeration step.

# Run board-template.cfg with the given speed + a -c body; capture combined output.
run_ocd(){ # $1=speed  $2=tcl-body  -> writes stdout+stderr to stdout
  JTAG_IFACE="$IFACE" JTAG_SPEED="$1" JTAG_TARGET="$TARGET" \
    "$OPENOCD" -f openocd/board-template.cfg -c "$2" 2>&1
}
# Pull 8-hex-digit IDCODEs out of OpenOCD output (init success OR mismatch errors both print them).
grep_idcodes(){ grep -oiE '0x[0-9a-f]{8}' | tr 'A-F' 'a-f' | sort -u; }

hr; echo " PROBE-BOARD — ${NAME:-<auto-name from SoC>}   (READ-ONLY; authorized engagement only)"; hr
echo " adapter : ${ADAPTER:-<auto-detect via lsusb>}"
echo " speeds  : $SPEEDS kHz (ascending; first that reads IDCODEs wins)"
echo " target  : $TARGET (for identification; a cfg is emitted only if it's ZynqMP)"
echo " openocd : $OPENOCD"
echo " (read-only: chain scan + register reads only — no reset, halt, or writes)"

# --- adapter -----------------------------------------------------------------------------
if [ -z "$ADAPTER" ]; then
  IFACE=$(python3 tools/gen-board-cfg.py --detect-adapter) \
    || stop "no adapter auto-detected. Re-run with --adapter <interface cfg> (see openocd/adapters/README.md)."
  echo ">> adapter auto-detected: $IFACE"
else
  IFACE="$ADAPTER"
fi

# --- Stage 1: speed-ladder chain scan ----------------------------------------------------
hr; echo " Stage 1 — chain scan (find IDCODEs at the lowest working speed)"
FOUND=""; USED_SPEED=""
for sp in $SPEEDS; do
  echo ">> init at ${sp} kHz ..."
  out=$(run_ocd "$sp" "init; shutdown")
  ids=$(printf '%s\n' "$out" | grep_idcodes)
  if [ -n "$ids" ]; then
    printf '%s\n' "$out" > "$LOG"
    FOUND="$ids"; USED_SPEED="$sp"
    echo "   IDCODEs seen: $(echo "$ids" | tr '\n' ' ')"
    break
  fi
  echo "   (no IDCODEs at ${sp} kHz)"
done
[ -n "$FOUND" ] || stop "NO-CHAIN: no IDCODEs at any speed. This is almost always PHYSICAL —
  check Vref/voltage (ZynqMP PS-JTAG=1.8V), pinout/connector, GND, lead length, board power,
  and whether JTAG is fused off. Software cannot sweep past a physical fault. (docs/18 Stage 1-2)"

# --- Stage 2: decode + decide (delegated to gen-board-cfg.py; refuses non-ZynqMP) --------
# --name is optional: omit it so gen-board-cfg derives the name from the SoC, then capture the
# path it actually wrote (e.g. openocd/zynqmp-zu9.cfg).
hr; echo " Stage 2 — identify SoC + generate config"
NAME_ARG=""; [ -n "$NAME" ] && NAME_ARG="--name $NAME"
if GEN=$(python3 tools/gen-board-cfg.py $NAME_ARG --from-discovery "$LOG" \
           --adapter "$IFACE" --speed "$USED_SPEED" --target "$TARGET" $FORCE 2>&1); then
  printf '%s\n' "$GEN"
else
  printf '%s\n' "$GEN"
  stop "SoC is not ZynqMP (or no usable IDCODE). enumerate.tcl/register-KB do not apply.
  See the decode above; for Zynq-7000/Versal/non-Xilinx use the appropriate toolset, or pass
  --target <cfg> --force to generate a config for chain access only."
fi
BOARD_CFG=$(printf '%s\n' "$GEN" | grep -oE 'openocd/[A-Za-z0-9._-]+\.cfg' | head -1)
[ -n "$BOARD_CFG" ] || stop "could not determine the generated config path from gen-board-cfg output."
echo ">> config: $BOARD_CFG"

# --- Stage 3: access verdict (non-destructive) -------------------------------------------
# BOARD_CFG is self-contained (adapter+speed+target baked in) — no env needed here.
hr; echo " Stage 3 — DAP access verdict"
"$OPENOCD" -f "$BOARD_CFG" -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee "$ACC"
VERDICT=$(grep -oE 'ACCESS VERDICT: [A-Z-]+' "$ACC" | head -1 | awk '{print $3}')
echo ">> verdict: ${VERDICT:-<none parsed>}"
STAMP=$(date '+%Y-%m-%d %H:%M')
if [ "$VERDICT" != "OPEN" ]; then
  printf '# probe-board.sh access verdict: %s (%s) — NOT open; enumeration not advised\n' \
    "${VERDICT:-UNKNOWN}" "$STAMP" >> "$BOARD_CFG"
  stop "DAP verdict is '${VERDICT:-UNKNOWN}', not OPEN. On a production board that is itself a
  RESULT — the access controls are doing their job. Document what faulted (Stage 3 output above).
  Verdict recorded in $BOARD_CFG. Not handing off for enumeration."
fi

# --- Handoff: record the verdict in the cfg, then print the exact enumeration step --------
# probe-board does NOT enumerate (separation of concerns). The cfg it produced is self-contained
# and sufficient; the verdict is recorded in it so the handoff carries the access decision.
printf '# probe-board.sh access verdict: OPEN (%s) — DAP open, enumeration possible\n' \
  "$STAMP" >> "$BOARD_CFG"
hr
echo " READY — $BOARD_CFG"
echo "   SoC identified, DAP OPEN (verdict recorded in the cfg). probe-board stops here."
echo ""
echo " Enumerate as a separate, deliberate step:"
echo "   openocd -f $BOARD_CFG -c \"init; source openocd/enumerate.tcl; shutdown\""
echo "   python3 tools/interpret.py \"\$(ls -t reports/raw-*.json | head -1)\" -O"
echo ""
echo " NOTE: this cfg's adapter speed is the LOWEST that scanned the chain (${USED_SPEED} kHz)."
echo "   Enumeration does many reads — consider raising 'adapter speed' in $BOARD_CFG once stable."
hr
