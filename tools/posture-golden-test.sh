#!/usr/bin/env bash
# posture-golden-test.sh — decode-correctness golden tests for the per-chip enumerate/protect scripts.
#
# Feeds each script a SMALL, doc-derived register fixture (a dev baseline + a HARDENED example) through a
# mock read_memory and diffs the DECODED posture against a frozen golden. This proves two things offline,
# with no hardware and no vast mockup (~10 register values per chip):
#   1. the decode logic is right (correct shifts/masks -> correct verdict);
#   2. the OFF -> ON hardening flip works — which real all-open silicon NEVER shows us.
# It complements the runtime SANITY GATES (which validate against live silicon) and the doc audit
# (which validates the addresses). First run with no goldens CREATES them (review, then keep). Re-runs diff.
# Run by tcl-smoketest.sh. Register values are cited in docs/24-25; hardened values are constructed per the docs.
set -u
cd "$(dirname "$0")/.."
GDIR=tests/golden/posture; mkdir -p "$GDIR"
FAIL=0

# read_memory is case-insensitive on the address (scripts use mixed-case hex); fixtures key REGS lowercase.
STUBS='proc halt args {return 0}; proc targets args {return 0}; proc arp_examine args {return 0}
proc uscale.axi args {return 0}; proc zynq.axi args {return 0}
proc echo args { puts [join $args { }] }
proc read_memory {a w n} { global REGS; set k [string tolower $a]
    if {[info exists REGS($k)]} { return [list $REGS($k)] } ; return [list 0] }'

run() { # $1=name  $2=script  $3=tcl-setup (REGS array, lowercase keys, + any globals)
    local name="$1" script="$2" setup="$3" fx got golden
    fx=$(mktemp); printf '%s\n%s\nsource %s\n' "$STUBS" "$setup" "$script" > "$fx"
    got=$(tclsh "$fx" 2>&1 | grep -v '^board-profile:'); rm -f "$fx"
    golden="$GDIR/$name.golden"
    if [ ! -f "$golden" ]; then printf '%s\n' "$got" > "$golden"; echo "  CREATED $name.golden"; return; fi
    if diff <(printf '%s\n' "$got") "$golden" >/dev/null; then echo "  ok: $name"
    else echo "  FAIL: $name"; diff <(printf '%s\n' "$got") "$golden" | head -20; FAIL=1; fi
}

echo "posture golden tests (decode + OFF->ON flip):"

# ===== Zynq-7000 ===== (registers per docs/24; hardened = secure-booted + eFuse + DBG-lock, DAP still up)
run zynq7000-dev openocd/zynq7000-enumerate.tcl 'array set REGS {
  0xf8000530 0x13727093  0xf8007000 0x0c00607f  0xf8007004 0x00000000  0xf8007014 0x40000820
  0xf8007080 0x1c000000  0xf800025c 0x00000001  0xf800000c 0x00000000  0xf8000258 0x00400000
  0xf8000300 0x00000000  0xf8000440 0x00000000  0xf8000448 0x00000000 }'
run zynq7000-hardened openocd/zynq7000-enumerate.tcl 'array set REGS {
  0xf8000530 0x13727093  0xf8007000 0x0c007e87  0xf8007004 0x0000000f  0xf8007014 0x4000082c
  0xf8007080 0x3c000000  0xf800025c 0x00000001  0xf800000c 0x00000001  0xf8000258 0x00400005
  0xf8000300 0x00000007  0xf8000440 0x00000001  0xf8000448 0x00000000 }'
run zynq7000-wrongchip openocd/zynq7000-enumerate.tcl 'array set REGS { 0xf8000530 0xffffffff }'

# ===== STM32F4 ===== (RDP 0xAA=L0 dev / 0x55=L1 hardened)
run stm32f4-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND stm32-rdp; array set REGS {
  0xe0042000 0x10006413  0x1fff7a10 0xcafebabe  0x1fff7a14 0x12345678  0x1fff7a18 0xdeadbeef
  0x1fff7a22 1024  0x40023c14 0x0fffaaed }'
run stm32f4-rdp1 openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND stm32-rdp; array set REGS {
  0xe0042000 0x10006413  0x1fff7a22 256  0x40023c14 0x0ff055ed }'

# ===== STM32L4 ===== (RDP in OPTR[7:0])
run stm32l4-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND stm32l4; array set REGS {
  0xe0042000 0x10076435  0x1fff75e0 512  0x40022020 0xfffff8aa }'

# ===== STM32F1 ===== (RDPRT bit)
run stm32f1-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND stm32f1; array set REGS {
  0xe0042000 0x20036414  0x1ffff7e0 512  0x4002201c 0x03fffffc }'
run stm32f1-rdp openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND stm32f1; array set REGS {
  0xe0042000 0x20036414  0x1ffff7e0 512  0x4002201c 0x03fffffe }'

# ===== nRF52840 ===== (APPROTECT 0xFFFFFFFF open / 0x0 enabled)
run nrf52-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND nrf-approtect; array set REGS {
  0x10000100 0x00052840  0x10000104 0x41414230  0x1000010c 256  0x10000110 1024
  0x10000060 0x11223344  0x10000064 0x55667788  0x10001208 0xffffffff  0x10001210 0xffffffff
  0x10001304 0xffffffff }'
run nrf52-hardened openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND nrf-approtect; array set REGS {
  0x10000100 0x00052840  0x1000010c 256  0x10000110 1024  0x10001208 0x00000000
  0x10001210 0xffffffff  0x10001304 0xffffffff }'
run nrf52-wrongchip openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND nrf-approtect; array set REGS {
  0x10000100 0x12345678 }'

# ===== RP2040 ===== (no protection)
run rp2040 openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND none; array set REGS {
  0x40000000 0x10002927  0x40000004 0x00000002  0x40000040 0xabcd1234 }'

# ===== SAM D5x/E5x ===== (DSU.STATUSB.PROT 0=open / 1=protected)
run samd5x-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND sam-dsu; array set REGS {
  0x41002018 0x61840303  0x41002002 0x00000000 }'
run samd5x-protected openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND sam-dsu; array set REGS {
  0x41002018 0x61840303  0x41002002 0x00000001 }'

# ===== Kinetis K64 ===== (FSEC SEC 0b10 unsecured / 0b00 secured + MEEN 0b10 no-recovery)
run kinetis-dev openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND kinetis-fsec; array set REGS {
  0x40048024 0x12340680  0x40020002 0x000000fe }'
run kinetis-secured openocd/cortexm-protect.tcl 'set ::CM_PROT_KIND kinetis-fsec; array set REGS {
  0x40048024 0x12340680  0x40020002 0x00000020 }'

if [ "$FAIL" = 0 ]; then echo "posture golden tests: all passed"; else echo "posture golden tests: FAILURES"; exit 1; fi
