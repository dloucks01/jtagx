#!/usr/bin/env bash
# board-runner-smoketest.sh — offline checks for the multi-board engine (tools/board-runner.py +
# profiles/). Proves the three-tier identification ladder WITHOUT touching hardware, so the engine
# and the degradation behaviour are locked before any new silicon work. Run by tcl-smoketest.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

R="python3 tools/board-runner.py"
fail() { echo "  FAIL: $1"; exit 1; }
# assert that running the runner with $1 produces output matching $2 (extended regex)
expect() { # $1=args  $2=regex  $3=label
    out="$($R $1 2>&1)" || fail "$3 — runner errored: $out"
    echo "$out" | grep -qE "$2" || fail "$3 — expected /$2/ not found in output"
    echo "  ok: $3"
}
refute() { # $1=args  $2=regex  $3=label — assert the regex is ABSENT
    out="$($R $1 2>&1)" || fail "$3 — runner errored: $out"
    echo "$out" | grep -qE "$2" && fail "$3 — did NOT expect /$2/ but found it"
    echo "  ok: $3"
}

echo "board-runner: registry validates"
$R --validate >/dev/null || fail "registry failed validation"
echo "  ok: --validate"

echo "board-runner: Tier 1 (exact profile, complete)"
expect '--idcodes 0x14738093 0x5ba00477' 'TIER 1: Zynq UltraScale' "ZynqMP -> Tier 1"
expect '--idcodes 0x14738093 0x5ba00477' 'enumerate\.tcl'           "ZynqMP plans posture enumerate"
expect '--idcodes 0x14738093 0x5ba00477' 'qspi-jtag\.tcl'           "ZynqMP plans flash dump"

echo "board-runner: Tier 1 (exact profile, PARTIAL -> honest gaps + wired caps)"
expect '--idcodes 0x13727093 0x4ba00477' 'PARTIAL'                  "Zynq-7000 flagged partial"
expect '--idcodes 0x13727093 0x4ba00477' 'zynq7000\.cfg'           "Zynq-7000 uses its pinned cfg"
expect '--idcodes 0x13727093 0x4ba00477' 'zynq7000-flash\.tcl'     "Zynq-7000 plans LQSPI flash dump"
expect '--idcodes 0x13727093 0x4ba00477' 'zynq7000-enumerate\.tcl' "Zynq-7000 plans posture snapshot"
expect '--idcodes 0x13727093 0x4ba00477' 'PATCH_CORE=zynq.cpu0'    "Zynq-7000 Cap-2 uses A9 target names"
expect '--idcodes 0x13727093 0x4ba00477' 'zynq7000-reopen-debug\.tcl' "Zynq-7000 plans the devcfg.CTRL reopen lever"

echo "board-runner: Tier 2 (no profile, ARM DAP -> generic probe plan)"
expect '--idcodes 0x4ba00477' 'TIER 2'                              "lone ARM DAP -> Tier 2"
expect '--idcodes 0x4ba00477' 'Probe for a mem-AP'                  "Tier 2 plans generic DRAM dump"

echo "board-runner: Tier 3 (FPGA TAP -> identify + vendor handoff)"
expect '--idcodes 0x41110057' 'TIER 3'                              "Lattice -> Tier 3"
expect '--idcodes 0x41110057' '\[VENDOR\]'                          "Tier 3 hands off to vendor tool"

echo "board-runner: --profile override (un-fingerprintable boards)"
expect '--profile bcm'    'TIER 1: Raspberry Pi'        "Pi: --profile bcm -> Tier 1 (operator-asserted)"
expect '--profile bcm'    'rpi\.cfg'                    "Pi: uses rpi.cfg"
expect '--profile bcm'    'PATCH_USE_V2P=1'             "Pi: Cap-2 uses Linux virt2phys"
expect '--profile bcm'    'VideoCore'                   "Pi: flash gap gives the honest (VideoCore-owned) reason"
expect '--idcodes 0x4ba00477' 'TIER 2'                  "Pi NOT auto-matched on lone ARM DAP (auto_match:false)"

echo "board-runner: Paradigm-D profile (IGLOO2 -> vendor handoff, no memory)"
expect '--profile igloo2' 'Paradigm D'                  "IGLOO2: paradigm D"
expect '--profile igloo2' '\[VENDOR\].*FlashPro'        "IGLOO2: FlashPro handoff"
expect '--profile igloo2' 'no memory capability'        "IGLOO2: declares no-memory gap"
refute '--profile igloo2' 'Dump live OS|Dump boot flash' "IGLOO2: plans NO dump steps"

echo "board-runner: Paradigm-B Cortex-M MCU profiles"
expect '--profile stm32f4' 'Paradigm B'                  "STM32F4: paradigm B"
expect '--profile stm32f4' 'cortexm-protect\.tcl'        "STM32F4: plans the readout-protection check"
expect '--profile stm32f4' 'cortexm-dump\.tcl'           "STM32F4: plans the flash+SRAM dump"
refute '--profile stm32f4' 'source None'                 "STM32F4: no null access_check step"
expect '--profile nrf52'   'cortexm-nrf52\.cfg'          "nRF52: uses its per-family cfg"
expect '--profile rp2040'  'cortexm-rp2040\.cfg'         "RP2040: uses its per-family cfg"
expect '--profile stm32l4' 'cortexm-stm32l4\.cfg'        "STM32L4: per-family cfg"
expect '--profile stm32f1' 'cortexm-stm32f1\.cfg'        "STM32F1: per-family cfg"
expect '--profile samd5x'  'cortexm-samd5x\.cfg'         "SAM D5x/E5x: per-family cfg"
expect '--profile kinetis' 'cortexm-kinetis\.cfg'        "Kinetis: per-family cfg"
expect '--profile kinetis' 'mass-erase'                  "Kinetis: honest destructive-unlock gap"

echo "board-runner: --list shows un-fingerprintable boards"
out="$($R --list 2>&1)"; echo "$out" | grep -qE 'bcm .*--profile only' || fail "--list missing bcm marker"
echo "$out" | grep -qE 'igloo2 .*--profile only' || fail "--list missing igloo2 marker"; echo "  ok: --list"

echo "board-runner: --from-log on the REAL ZCU102 capture (tests/fixtures/zcu102-firstcontact.log)"
FIX=tests/fixtures/zcu102-firstcontact.log
expect "--from-log $FIX" 'TIER 1: Zynq UltraScale'                  "real ZCU102 log -> Tier 1 ZynqMP"
expect "--from-log $FIX" '0x24738093  zynqmp'                       "real ZCU102 log -> ZU9 part 0x4738 decoded"
refute "--from-log $FIX" '0xffca0040'                               "register-read line NOT mis-parsed as a device IDCODE"

# --- dynamic parse-check of the Zynq-7000 scripts under stubs ---------------------------------
# These aren't sourced anywhere else in the suite, and the static bracket-scan only inspects certain
# command contexts — so source them here to catch syntax / bracket-in-string / undefined-var bugs.
echo "board-runner: Zynq-7000 scripts parse + run under stubs"
Z7STUBS='proc targets {args} { return 0 }
proc read_memory {a w n} { switch -- $a 0xF8007000 { return [list 0x0C00607F] } 0xF8007004 { return [list 0x0] } 0xF800025C { return [list 0x00000005] } 0xFC000000 { return [list 0xaa995566 0x584e4c58 0 0 0 0 0 0] } default { return [list 0 0 0 0 0 0 0 0] } }
proc write_memory {args} { return 0 }
proc arp_examine {args} { return 0 }
proc zynq.axi {args} { return 0 }
proc halt {args} { return 0 }
proc after {args} { return 0 }
proc echo {args} { return 0 }'
for s in zynq7000-enumerate zynq7000-reopen-debug; do
    D="$(mktemp)"; printf '%s\nsource openocd/%s.tcl\nputs PARSE-OK\n' "$Z7STUBS" "$s" > "$D"
    out="$(tclsh "$D" 2>&1)"; rm -f "$D"
    echo "$out" | grep -q '^PARSE-OK$' || fail "openocd/$s.tcl crashed under stubs: $(echo "$out" | grep -iE 'invalid|wrong #|no such|can.t' | head -1)"
    echo "  ok: openocd/$s.tcl"
done
# flash script writes a file via dump_memory -> tiny size, /tmp out
D="$(mktemp)"; printf '%s\nsource openocd/zynq7000-flash.tcl\nputs PARSE-OK\n' "$Z7STUBS" > "$D"
out="$(FLASH_SIZE=0x40 FLASH_OUT=/tmp/_z7smoke.bin tclsh "$D" 2>&1)"; rm -f "$D" /tmp/_z7smoke.bin
echo "$out" | grep -q '^PARSE-OK$' || fail "openocd/zynq7000-flash.tcl crashed under stubs: $(echo "$out" | grep -iE 'invalid|wrong #|no such|can.t' | head -1)"
echo "  ok: openocd/zynq7000-flash.tcl"

# Cortex-M scripts: source under stubs WITH the CM_* globals the per-family cfg would set.
echo "board-runner: Cortex-M scripts parse + run under stubs"
CMGLOBALS='set ::CM_PROT_KIND stm32-rdp
set ::CM_PROT_REG 0x40023C14
set ::CM_ID_REG 0xE0042000
set ::CM_FLASH_SIZE 0x40
set ::CM_FLASH_OUT /tmp/_cmf.bin
set ::CM_SRAM_SIZE 0x40
set ::CM_SRAM_OUT /tmp/_cms.bin'
CMSTUBS='proc targets {args} { return 0 }
proc halt {args} { return 0 }
proc read_memory {a w n} { return [list 0x0fffaaed 0 0 0 0 0 0 0] }
proc echo {args} { return 0 }'
for s in cortexm-protect cortexm-dump; do
    D="$(mktemp)"; printf '%s\n%s\nsource openocd/%s.tcl\nputs PARSE-OK\n' "$CMSTUBS" "$CMGLOBALS" "$s" > "$D"
    out="$(tclsh "$D" 2>&1)"; rm -f "$D" /tmp/_cmf.bin /tmp/_cms.bin
    echo "$out" | grep -q '^PARSE-OK$' || fail "openocd/$s.tcl crashed under stubs: $(echo "$out" | grep -iE 'invalid|wrong #|no such|can.t' | head -1)"
    echo "  ok: openocd/$s.tcl"
done
# pi-enumerate (CoreSight AUTHSTATUS read; sources board-profile -> AXI_TARGET)
D="$(mktemp)"; cat > "$D" <<'PIEOF'
proc targets {args} { return 0 }
proc arp_examine {args} { return 0 }
proc uscale.axi {args} { return 0 }
proc read_memory {a w n} { return [list 0x000000ff] }
proc echo {args} { return 0 }
set ::PI_DBGBASE 0x80010000
source openocd/pi-enumerate.tcl
puts PARSE-OK
PIEOF
out="$(tclsh "$D" 2>&1)"; rm -f "$D"
echo "$out" | grep -q '^PARSE-OK$' || fail "openocd/pi-enumerate.tcl crashed under stubs: $(echo "$out" | grep -iE 'invalid|wrong #|no such' | head -1)"
echo "  ok: openocd/pi-enumerate.tcl"

# auto triage step is planned, and dump-triage.py works on a synthetic structured blob.
echo "board-runner: dump-triage auto-step + tool functional"
expect '--idcodes 0x14738093 0x5ba00477' 'dump-triage\.py'   "plan auto-includes the dump triage step"
python3 - > /tmp/_triage_smoke.bin <<'PY'
import os
b = b"\xff"*0x1000 + b"\x1f\x8b\x08" + os.urandom(0x2000) + b"-----BEGIN CERTIFICATE-----\n"
open("/tmp/_triage_smoke.bin","wb").write(b)
PY
TOUT="$(python3 tools/dump-triage.py /tmp/_triage_smoke.bin --block 0x400 2>&1)"; rm -f /tmp/_triage_smoke.bin
echo "$TOUT" | grep -q 'region map' || fail "dump-triage: no region map"
echo "$TOUT" | grep -q 'gzip'       || fail "dump-triage: missed gzip signature"
echo "$TOUT" | grep -qi 'BEGIN\|PEM\|crypto' || fail "dump-triage: missed PEM/cert signature"
echo "  ok: dump-triage.py (region map + gzip + cert detected)"

# --- new capability tools (write/persistence + offensive patching + live RAM) ---
echo "board-runner: capability tools (reflash / patch-recipe / mem-search / watch-access)"
CAPSTUBS='proc targets a {return 0}; proc arp_examine a {return 0}; proc uscale.axi a {return 0}
proc halt a {return 0}; proc resume a {return 0}; proc reset a {return 0}; proc flash a {return 0}
proc verify_image a {return 0}; proc wp a {return 0}; proc rwp a {return 0}; proc reg a {return 0x1000}
proc after a {return 0}; proc uscale.a53.0 a {return halted}; proc target a {return uscale.a53.0}
proc bp args {return 0}; proc rbp a {return 0}; proc get_reg a {return "$a 0x1000"}
proc read_memory {a w n} { set l {}; for {set i 0} {$i<$n} {incr i} {lappend l 0x504b4956}; return $l }
proc write_memory {a w d} {return 0}
proc echo a {}'
for s in cortexm-flash mem-search watch-access break-capture; do
    D="$(mktemp)"; printf '%s\nset ::env(CMF_FILE) x.bin\nset ::env(MS_PATTERN) KIV\nset ::env(WA_ADDR) 0x1000\nset ::env(BC_ADDR) 0x1000\nsource openocd/%s.tcl\nputs PARSE-OK\n' "$CAPSTUBS" "$s" > "$D"
    out="$(tclsh "$D" 2>&1)"; rm -f "$D"
    echo "$out" | grep -q '^PARSE-OK$' || fail "openocd/$s.tcl crashed under stubs: $(echo "$out" | grep -iE 'invalid|wrong #|no such' | head -1)"
    echo "  ok: openocd/$s.tcl"
done
# patch-recipe: encoding correctness (aarch64 ret0 must be mov w0,#0 ; ret)
O=$(python3 tools/patch-recipe.py --arch aarch64 --va 0x1000 --behavior ret0 2>/dev/null)
grep -q 'PATCH_HEX=00008052c0035fd6' <<<"$O" || fail "patch-recipe aarch64 ret0 encoding wrong"
O=$(python3 tools/patch-recipe.py --arch thumb --va 0x1000 --behavior ret0 2>/dev/null)
grep -q 'PATCH_HEX=00207047' <<<"$O" || fail "patch-recipe thumb ret0 encoding wrong"
echo "  ok: patch-recipe.py (aarch64 + thumb ret0 encodings)"
# repack-bootimage: parses + --help
python3 tools/repack-bootimage.py --help >/dev/null 2>&1 || fail "repack-bootimage.py --help"
echo "  ok: repack-bootimage.py"

# --- coverage (#3) + intel/reporting (#4) ---
echo "board-runner: new SoC profiles plan (imx6/am335x/sama5/riscv/esp32)"
expect '--profile imx6'   'TIER 1: NXP i.MX6'              "imx6 -> Paradigm A plan"
expect '--profile riscv'  'Paradigm E'                     "riscv -> Paradigm E"
expect '--profile esp32'  'esptool'                        "esp32 -> esptool flash note"
echo "board-runner: intel tools (cve-match + engagement-report)"
O=$(python3 tools/cve-match.py --soc zynqmp --jtag-open --secure-boot off 2>/dev/null)
grep -q 'POSTURE.*full debug compromise' <<<"$O" || fail "cve-match zynqmp posture finding"
O=$(python3 tools/cve-match.py --soc stm32f4 --rdp 0 2>/dev/null)
grep -q 'RDP level 0' <<<"$O" || fail "cve-match stm32 rdp0"
echo "  ok: cve-match.py (zynqmp + stm32 posture findings)"
O=$(python3 tools/engagement-report.py --soc zynqmp --jtag-open 2>/dev/null)
grep -q '# JTAG Engagement Report' <<<"$O" || fail "engagement-report.py"
grep -q 'Kill chain' <<<"$O"           || fail "engagement-report should include the kill-chain section"
grep -q 'Extraction avenues' <<<"$O"   || fail "engagement-report should include the extraction avenues"
# a locked board that has a ROM loader → the report shows extraction reachable without the debug port
O2=$(python3 tools/engagement-report.py --soc imx6 --jtag-locked 2>/dev/null)
grep -q 'SDP' <<<"$O2" || fail "imx6 report should surface the SDP extraction avenue"
echo "  ok: engagement-report.py (+ kill-chain + extraction avenues consolidated)"

echo "board-runner smoketest: all checks passed"
