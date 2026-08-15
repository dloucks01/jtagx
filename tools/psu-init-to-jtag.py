#!/usr/bin/env python3
"""psu-init-to-jtag.py — turn the ZCU102 psu_init_gpl.c into a JTAG MMIO replay.

The PetaLinux FSBL's psu_init, run as A53 code over JTAG, wedges the OpenOCD DAP
(it reconfigures a clock/reset the debug path needs). Instead we replay the SAME
register sequence as pure JTAG MMIO writes with the A53 HALTED — no code exec, no
error-lockdown. Emits an OpenOCD Tcl that does read-modify-write per PSU_Mask_Write,
polls per mask_poll, and DAP-health checks between functions so a wedge is localized.

Only the functions needed for DDR + a U-Boot console are replayed, in psu_init() order:
  mio -> peripherals_pre -> pll -> clock -> ddr -> ddr_phybringup -> peripherals

Needs the vendor FSBL source (references/src/embeddedsw/...) — NOT bundled in the
default standalone engagement kit (WITH_PDFS=1 pulls it in, since it lives under
references/). Most operators never need to run this: its OUTPUT,
openocd/psu-init-replay.tcl, is already pre-generated and ships in every kit. Only
re-run this tool if you're regenerating the replay against different/updated vendor
source.
"""
import re
import sys

D = "references/src/embeddedsw/lib/sw_apps/zynqmp_fsbl/misc/zcu102"
SRC = f"{D}/psu_init_gpl.c"
HDR = f"{D}/psu_init_gpl.h"

ORDER = ["psu_mio_init_data", "psu_peripherals_pre_init_data",
         "psu_pll_init_data", "psu_clock_init_data",
         "psu_ddr_init_data", "psu_ddr_phybringup_data",
         "psu_peripherals_init_data"]

HANDCODED = {"psu_ddr_phybringup_data"}
CALL = re.compile(
    r'PSU_Mask_Write\s*\(([^;]*?)\)\s*;'
    r'|mask_pollOnValue\s*\(([^;)]*?)\)'
    r'|mask_poll\s*\(([^;)]*?)\)'
    r'|mask_delay\s*\(([^;)]*?)\)'
    r'|prog_reg\s*\(([^;)]*?)\)', re.S)

PHYBRINGUP = r'''proc step_psu_ddr_phybringup_data {} {
  echo "=== psu_ddr_phybringup_data (DDR PHY training) ==="
  set pll_retry 10; set pll_locked 0
  while {($pll_retry > 0) && (!$pll_locked)} {
    wr 0xFD080004 0x00040010; wr 0xFD080004 0x00040011
    set i 0; while {([rd 0xFD080030] & 0x1) != 1} { incr i; if {$i>3000} { echo "  PIR init timeout"; return }; after 1 }
    set pll_locked [expr {([rd 0xFD080030] & 0x80000000) >> 31}]
    set pll_locked [expr {$pll_locked & (([rd 0xFD0807E0] & 0x10000) >> 16)}]
    set pll_locked [expr {$pll_locked & (([rd 0xFD0809E0] & 0x10000) >> 16)}]
    set pll_locked [expr {$pll_locked & (([rd 0xFD080BE0] & 0x10000) >> 16)}]
    set pll_locked [expr {$pll_locked & (([rd 0xFD080DE0] & 0x10000) >> 16)}]
    incr pll_retry -1
  }
  wr 0xFD0800C4 [expr {[rd 0xFD0800C4] | ($pll_retry << 16)}]
  if {!$pll_locked} { echo "  *** DDR DLL/PLL NOT LOCKED"; return }
  wr 0xFD080004 0x00040063
  set i 0; while {([rd 0xFD080030] & 0xF) != 0xF} { incr i; if {$i>8000} {echo "  ZQ/init timeout PGSR0=[format 0x%08x [rd 0xFD080030]]";return}; after 1 }
  mwsh 0xFD080004 0x1 0x0 0x1
  set i 0; while {([rd 0xFD080030] & 0xFF) != 0x1F} { incr i; if {$i>8000} {echo "  DRAM init timeout";return}; after 1 }
  wr 0xFD0701B0 0x1; wr 0xFD070320 0x1
  set i 0; while {([rd 0xFD070004] & 0xF) != 0x1} { incr i; if {$i>8000} {echo "  DDRC normal-mode timeout";return}; after 1 }
  mwsh 0xFD080014 0x40 0x6 0x1
  wr 0xFD080004 0x0004FE01
  set i 0; while {[rd 0xFD080030] != 0x80000FFF} { incr i; if {$i>30000} {echo "  *** DDR TRAINING timeout PGSR0=[format 0x%08x [rd 0xFD080030]]";return}; after 1 }
  set err [expr {([rd 0xFD080030] & 0x1FFF0000) >> 18}]
  if {$err != 0} { echo "  *** DDR training ERROR bits=[format 0x%x $err]"; return }
  wr 0xFD080200 0x100091C7
  set cur [expr {[rd 0xFD080018] & 0x3FFFF}]
  mwsh 0xFD080018 0x3FFFF 0x0 $cur
  mwsh 0xFD08001C 0x18 0x3 0x3
  foreach a {0xFD08142C 0xFD08146C 0xFD0814AC 0xFD0814EC 0xFD08152C} { mwsh $a 0x30 0x4 0x3 }
  wr 0xFD080004 0x00060001
  set i 0; while {([rd 0xFD080030] & 0x80004001) != 0x80004001} { incr i; if {$i>30000} {echo "  *** VREF train timeout";return}; after 1 }
  set err [expr {([rd 0xFD080030] & 0x1FFF0000) >> 18}]
  if {$err != 0} { echo "  *** VREF train ERROR bits=[format 0x%x $err]"; return }
  mwsh 0xFD08001C 0x18 0x3 0x0
  foreach a {0xFD08142C 0xFD08146C 0xFD0814AC 0xFD0814EC 0xFD08152C} { mwsh $a 0x30 0x4 0x0 }
  wr 0xFD080200 0x800091C7
  mwsh 0xFD080018 0x3FFFF 0x0 $cur
  wr 0xFD080004 0x0000C001
  set i 0; while {([rd 0xFD080030] & 0x80000C01) != 0x80000C01} { incr i; if {$i>30000} {echo "  *** final train timeout";return}; after 1 }
  wr 0xFD070180 0x01000040; wr 0xFD070060 0x00000000
  mwsh 0xFD080014 0x40 0x6 0x0
  if {![alive]} { echo "WEDGE after psu_ddr_phybringup_data"; return }
  echo "  -- DDR PHY training COMPLETE, DAP alive --"
}'''


def main(out_path="openocd/psu-init-replay.tcl"):
    try:
        with open(HDR, encoding="utf-8") as fh:
            hdr_lines = fh.readlines()
        with open(SRC, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as e:
        print(f"error: cannot read the vendor FSBL source: {e}", file=sys.stderr)
        print(f"  needed: {SRC}\n  and:    {HDR}", file=sys.stderr)
        print("  This is the ZynqMP FSBL vendor source (Xilinx/AMD embeddedsw), not bundled in the "
              "default standalone kit — only with WITH_PDFS=1 (it lives under references/).",
              file=sys.stderr)
        print("  You probably don't need to run this at all: the OUTPUT of this tool, "
              f"{out_path}, is already pre-generated and ships in every kit. Only re-run "
              "this if you're regenerating the replay against different/updated vendor source.",
              file=sys.stderr)
        return 1

    # 1. symbol -> address
    addr = {}
    for line in hdr_lines:
        m = re.match(r'\s*#define\s+(\w+)\s+0[xX]([0-9A-Fa-f]+)', line)
        if m:
            addr[m.group(1)] = int(m.group(2), 16)

    def resolve(tok):
        tok = tok.strip()
        if re.match(r'0[xX][0-9A-Fa-f]+[Uu]?$', tok):
            return int(tok.rstrip('Uu'), 16)
        if tok in addr:
            return addr[tok]
        return None

    # 2. slice out each function body
    def body(fn):
        m = re.search(r'unsigned long %s\(void\)\s*\{' % re.escape(fn), text)
        if not m:
            return ""
        i = m.end(); depth = 1
        while depth and i < len(text):
            if text[i] == '{': depth += 1
            elif text[i] == '}': depth -= 1
            i += 1
        return text[m.end():i]

    # 3. parse ops, flag anything not understood. Operate on comment-stripped,
    #    newline-collapsed body so multi-line PSU_Mask_Write(...) are caught.
    # psu_ddr_phybringup_data has data-dependent training logic -> hand-coded below.
    ops = []          # (fn, kind, args...)
    flags = []        # control-flow / unhandled lines per function
    for fn in ORDER:
        if fn in HANDCODED:
            ops.append((fn, 'handcoded')); flags.append(f"{fn}: hand-coded"); continue
        b = body(fn)
        if not b:
            flags.append(f"{fn}: NOT FOUND"); continue
        b = re.sub(r'/\*.*?\*/', '', b, flags=re.S)   # strip block comments
        b = re.sub(r'//[^\n]*', '', b)                # strip line comments
        nops = 0
        for m in CALL.finditer(b):
            if m.group(1) is not None:    # PSU_Mask_Write
                parts = [p.strip() for p in m.group(1).split(',')]
                a, mask, val = resolve(parts[0]), resolve(parts[1]), resolve(parts[2])
                if None in (a, mask, val): flags.append(f"{fn}: unresolved MaskWrite {parts}"); continue
                ops.append((fn, 'w', a, mask, val)); nops += 1
            elif m.group(2) is not None:  # mask_pollOnValue
                parts = [p.strip() for p in m.group(2).split(',')]
                a, mask, val = resolve(parts[0]), resolve(parts[1]), resolve(parts[2])
                if None in (a, mask, val): flags.append(f"{fn}: unresolved pollv {parts}"); continue
                ops.append((fn, 'pv', a, mask, val)); nops += 1
            elif m.group(3) is not None:  # mask_poll
                parts = [p.strip() for p in m.group(3).split(',')]
                a, mask = resolve(parts[0]), resolve(parts[1])
                if None in (a, mask): flags.append(f"{fn}: unresolved poll {parts}"); continue
                ops.append((fn, 'p', a, mask)); nops += 1
            elif m.group(4) is not None:  # mask_delay
                v = m.group(4).strip()
                ops.append((fn, 'd', int(v, 0) if re.match(r'\d', v) else 1000)); nops += 1
            elif m.group(5) is not None:  # prog_reg
                parts = [p.strip() for p in m.group(5).split(',')]
                a, mask, sh, val = (resolve(parts[0]), resolve(parts[1]),
                                    resolve(parts[2]), resolve(parts[3]))
                if None in (a, mask, sh, val): flags.append(f"{fn}: unresolved prog_reg {parts}"); continue
                ops.append((fn, 'w', a, mask, (val << sh) & mask)); nops += 1
        flags.append(f"{fn}: parsed {nops} ops")

    # 4. emit report + OpenOCD replay
    print("=== PARSE REPORT ===", file=sys.stderr)
    for f in flags: print("  " + f, file=sys.stderr)
    print(f"  TOTAL ops: {len(ops)}", file=sys.stderr)

    out = ['# AUTO-GENERATED by tools/psu-init-to-jtag.py — DDR+UART bring-up via JTAG MMIO.',
           '# A53 stays halted; all writes via the AXI-AP. proc step replays one psu_* function',
           '# with a DAP-health check after, so a wedge is localized.', '',
           'proc rd {a} { return [lindex [read_memory $a 32 1] 0] }',
           'proc wr {a v} { write_memory $a 32 [list $v] }',
           'proc mw {a mask val} { set r [rd $a]; set r [expr {($r & ~$mask) | ($val & $mask)}]; wr $a $r }',
           'proc mwsh {a mask shift val} { set r [rd $a]; set r [expr {($r & ~$mask) | (($val << $shift) & $mask)}]; wr $a $r }',
           'proc mpoll {a mask} { for {set i 0} {$i < 2000} {incr i} { if {[rd $a] & $mask} { return 1 }; after 1 }; echo "  POLL TIMEOUT @[format 0x%08x $a] mask [format 0x%08x $mask]"; return 0 }',
           'proc mpollv {a mask val} { for {set i 0} {$i < 2000} {incr i} { if {([rd $a] & $mask) == ($val & $mask)} { return 1 }; after 1 }; echo "  POLLV TIMEOUT @[format 0x%08x $a]"; return 0 }',
           'proc alive {} { if {[catch {rd 0xFFCA0000} e]} { echo "  *** DAP WEDGED: $e"; return 0 }; return 1 }',
           '']
    cur = None
    for op in ops:
        fn = op[0]
        if op[1] == 'handcoded':
            if cur is not None:
                out.append(f'  if {{![alive]}} {{ echo "WEDGE after {cur}"; return }}')
                out.append(f'  echo "  -- {cur} done, DAP alive --"'); out.append('}')
                cur = None
            out.append(PHYBRINGUP)
            continue
        if fn != cur:
            if cur is not None:
                out.append(f'  if {{![alive]}} {{ echo "WEDGE after {cur}"; return }}')
                out.append(f'  echo "  -- {cur} done, DAP alive --"'); out.append('}')
            out.append(f'proc step_{fn} {{}} {{')
            out.append(f'  echo "=== {fn} ==="')
            cur = fn
        k = op[1]
        if k == 'w':   out.append(f'  mw 0x{op[2]:08X} 0x{op[3]:08X} 0x{op[4]:08X}')
        elif k == 'p': out.append(f'  mpoll 0x{op[2]:08X} 0x{op[3]:08X}')
        elif k == 'pv':out.append(f'  mpollv 0x{op[2]:08X} 0x{op[3]:08X} 0x{op[4]:08X}')
        elif k == 'd': out.append(f'  after {min(op[2],200)}')
    if cur is not None:
        out.append(f'  if {{![alive]}} {{ echo "WEDGE after {cur}"; return }}')
        out.append(f'  echo "  -- {cur} done, DAP alive --"')
        out.append('}')

    out.append('')
    out.append('proc psu_replay {} {')
    for fn in ORDER:
        if any(o[0] == fn for o in ops):
            out.append(f'  step_{fn}')
    out.append('}')

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write('\n'.join(out) + '\n')
    print(f"WROTE {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
