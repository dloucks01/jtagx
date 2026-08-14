#!/usr/bin/env python3
"""
regenerate-qemu-regs.py — generate `openocd/lib/zynqmp-regs-qemu.tcl`
from Xilinx QEMU register definitions.

This produces a single Tcl dict (::QEMU_REGS) keyed by absolute address,
plus a `dump_reg_qemu ADDR ?LABEL?` helper that pulls the bit-field
decoding straight from the dict. The enumerate.tcl script calls
`dump_reg_qemu 0x...` and bit fields come from QEMU — no possibility
of hand-typed drift.

Run this any time QEMU sources are updated, or when adding coverage
for additional blocks.

⚠️ MANUAL CORRECTIONS — RE-APPLY AFTER ANY REGEN (2026-06-10 KB audit):
The Xilinx QEMU register model disagrees with the authoritative Xilinx firmware
headers in a few places; the firmware headers win (they reflect real silicon).
A blind regen will RE-INTRODUCE these bugs — re-apply them (or add a post-pass):
  • CSU_TAMPER_0..12 BBRAM_ERASE: bit 5 -> bit 4   (csu.h:1533, CSU_TAMPER_0_BBRAM_ERASE_SHIFT=4)
  • PMU_GLOBAL ERROR_*_1 (14 mirror regs) bit 27: "DFT" -> "CSU_SWDT"  (pmu_global.h:2368)
Completeness additions also made by hand (QEMU omits them):
  • JTAG_DAP_CFG += SSSS_RPU_SPNIDEN[7], SSSS_RPU_SPIDEN[6]   (csu.h:809/813)
  • AES_STATUS   += BLACK_KEY_DONE[5]                         (csu.h:999)
  • AES_KEY_CLEAR += AES_OKR_ZERO[3], AES_BOOT_ZERO[2]        (csu.h:1063)
  • CSU_SSS_CFG  += PSTP_SSS[19:16]                           (csu.h:57)
  • MISC_USER_CTRL FPD_SC_EN[16:14], LPD_SC_EN[13:11] widths 1->3 (xilskey hw.h:639-643)

Sources:
  /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_crf.c
  /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_crl.c
  /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_pmu_global.c
  /opt/xilinx/qemu/hw/misc/csu_core.c
  /opt/xilinx/qemu/hw/nvram/xlnx-zynqmp-efuse.c
  /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_apu_ctrl.c
  /opt/xilinx/qemu/hw/misc/xilinx_zynqmp_rpu_ctrl.c
  /opt/xilinx/qemu/hw/misc/zynqmp-iou-slcr.c
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

QEMU_ROOT = Path("/opt/xilinx/qemu")
OUTPUT_PATH = Path(
    "/home/kali/Desktop/research/JTAG/openocd/lib/zynqmp-regs-qemu.tcl"
)

# Blocks to ingest. Each entry: (qemu_file, block_base_address, block_name).
# Adding a new block here + re-running this script extends coverage with
# zero risk of drift from QEMU's actual model.
BLOCKS = [
    ("hw/misc/xilinx_zynqmp_crf.c", 0xFD1A0000, "CRF_APB"),
    ("hw/misc/xilinx_zynqmp_crl.c", 0xFF5E0000, "CRL_APB"),
    ("hw/misc/xilinx_zynqmp_pmu_global.c", 0xFFD80000, "PMU_GLOBAL"),
    ("hw/misc/csu_core.c", 0xFFCA0000, "CSU"),
    ("hw/nvram/xlnx-zynqmp-efuse.c", 0xFFCC0000, "EFUSE"),
    ("hw/misc/xilinx_zynqmp_apu_ctrl.c", 0xFD5C0000, "APU"),
    ("hw/misc/xilinx_zynqmp_rpu_ctrl.c", 0xFF9A0000, "RPU"),
    ("hw/misc/zynqmp-iou-slcr.c", 0xFF180000, "IOU_SLCR"),
    # XPPU register definitions live in a header shared between ZynqMP and Versal.
    # On ZynqMP the single XPPU instance is in LPD at 0xFF980000 (UG1085 §16).
    ("include/hw/misc/xlnx-xppu.h", 0xFF980000, "XPPU"),
    # IPI (Inter-Processor Interrupt) — one common register window per agent;
    # the QEMU model uses agent-relative offsets (TRIG=0x0, OBS=0x4, ISR=0x10,
    # IMR=0x14, IER=0x18, IDS=0x1C). We point at the APU's agent window at
    # 0xFF300000 (UG1085 §13 IPI Block Diagram). Other agent windows (RPU_0
    # 0xFF310000, RPU_1 0xFF320000, PMU0..3 0xFF330000..0xFF360000) reuse the
    # same offsets — the script reads APU's view; later sections can probe
    # the per-agent windows by adding more dump_reg_qemu calls.
    ("hw/intc/xlnx-zynqmp-ipi.c", 0xFF300000, "IPI"),
    # XMPU (Xilinx Memory Protection Unit) — common register layout shared
    # across multiple instances. ZynqMP has 8 XMPU instances (5 DDR + FPD +
    # OCM + others) per UG1085 §16. We only add the two most-confident
    # instances here (OCM_XMPU + DDR_XMPU0) — probing unverified XMPU base
    # addresses risks wedging the DAP. Expand after cloning u-boot-xlnx
    # for authoritative addresses.
    ("include/hw/misc/xlnx-xmpu.h", 0xFFA70000, "OCM_XMPU"),
    ("include/hw/misc/xlnx-xmpu.h", 0xFD000000, "DDR_XMPU0"),
]


REG32_RE = re.compile(r"^\s*REG32\(\s*(\w+)\s*,\s*(0x[0-9a-fA-F]+)\s*\)")
FIELD_RE = re.compile(
    r"^\s*FIELD\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
)


@dataclass
class Reg:
    name: str
    block: str
    address: int
    fields: list[tuple[str, int, int]] = field(default_factory=list)
    """fields: list of (field_name, msb, lsb)"""


def parse_block(qemu_relpath: str, base_addr: int, block_name: str) -> list[Reg]:
    path = QEMU_ROOT / qemu_relpath
    if not path.exists():
        print(f"WARN: {path} not found, skipping", file=sys.stderr)
        return []

    regs: list[Reg] = []
    current: dict[str, Reg] = {}  # qemu name → Reg, for field association

    for line in path.read_text().splitlines():
        m = REG32_RE.match(line)
        if m:
            qname = m.group(1)
            offset = int(m.group(2), 16)
            r = Reg(name=qname, block=block_name, address=base_addr + offset)
            regs.append(r)
            current[qname] = r
            continue
        m = FIELD_RE.match(line)
        if m:
            reg_name = m.group(1)
            field_name = m.group(2)
            lsb = int(m.group(3))
            width = int(m.group(4))
            msb = lsb + width - 1
            if reg_name in current:
                current[reg_name].fields.append((field_name, msb, lsb))

    return regs


def render_tcl(all_regs: list[Reg]) -> str:
    lines: list[str] = []
    lines.append(
        "# zynqmp-regs-qemu.tcl — AUTO-GENERATED. DO NOT EDIT BY HAND."
    )
    lines.append("#")
    lines.append(
        "# Single source of truth for ZynqMP register layouts, extracted"
    )
    lines.append("# from Xilinx QEMU register-model headers.")
    lines.append("#")
    lines.append("# Regenerate with: python3 tools/regenerate-qemu-regs.py")
    lines.append("#")
    lines.append("# Sources:")
    for relpath, _base, _block in BLOCKS:
        lines.append(f"#   /opt/xilinx/qemu/{relpath}")
    lines.append("")
    lines.append(
        "# Schema: dict ::QEMU_REGS keyed by absolute address (decimal int)."
    )
    lines.append("# Each value is a dict:")
    lines.append("#   name    QEMU REG32 name (no block prefix)")
    lines.append("#   block   block this register belongs to")
    lines.append(
        "#   fields  list of {field_name msb lsb} tuples (MSB-first order)"
    )
    lines.append("")
    lines.append("set ::QEMU_REGS [dict create]")
    lines.append("")

    # Sort by block then address for readability
    for r in sorted(all_regs, key=lambda x: (x.block, x.address)):
        lines.append(f"# {r.block}.{r.name}")
        lines.append(f"dict set ::QEMU_REGS {r.address} [dict create \\")
        lines.append(f"    name    {r.name} \\")
        lines.append(f"    block   {r.block} \\")
        lines.append(f"    fields  [list \\")
        # QEMU files often list fields in arbitrary order; sort MSB-descending
        # so the dump output reads top-down naturally.
        for fname, msb, lsb in sorted(r.fields, key=lambda f: -f[1]):
            lines.append(f"        [list {fname} {msb} {lsb}] \\")
        lines.append(f"    ]]")
        lines.append("")

    # The helper proc. Lives in this file so a single source includes
    # both data and accessor.
    lines.append("# ---------------------------------------------------------------------------")
    lines.append("# Helper procs")
    lines.append("# ---------------------------------------------------------------------------")
    lines.append("")
    lines.append("# Returns the QEMU register dict for an absolute address, or empty string")
    lines.append("# if the address isn't covered.")
    lines.append("#")
    lines.append("# Tcl dict keys are strings, so \"0xFD1A0020\" and \"4255842336\" are")
    lines.append("# distinct keys even though they're the same integer. We normalize the")
    lines.append("# caller's input to decimal via [expr] so hex literals work.")
    lines.append("proc qemu_reg_lookup {addr} {")
    lines.append("    set k [expr {int($addr)}]")
    lines.append("    if {[dict exists $::QEMU_REGS $k]} {")
    lines.append("        return [dict get $::QEMU_REGS $k]")
    lines.append("    }")
    lines.append("    return \"\"")
    lines.append("}")
    lines.append("")
    lines.append("# dump_reg variant that pulls bit fields from the QEMU dict.")
    lines.append("# Usage:")
    lines.append("#   dump_reg_qemu 0xFD1A0020              ;# label = CRF_APB.APLL_CTRL")
    lines.append("#   dump_reg_qemu 0xFD1A0020 \"APLL CTRL\" ;# custom label")
    lines.append("#")
    lines.append("# Falls back to a plain hex dump (no bit decoding) when the address")
    lines.append("# isn't in QEMU's coverage, with a one-line warning to the report.")
    lines.append("proc dump_reg_qemu {addr {label \"\"}} {")
    lines.append("    set info [qemu_reg_lookup $addr]")
    lines.append("    if {$info eq \"\"} {")
    lines.append("        if {$label eq \"\"} {")
    lines.append("            set label [format \"reg @ 0x%08X\" $addr]")
    lines.append("        }")
    lines.append("        dump_reg $label $addr")
    lines.append("        say \"  _(no QEMU register model for this address — bit fields unverified)_\"")
    lines.append("        return")
    lines.append("    }")
    lines.append("    set qname  [dict get $info name]")
    lines.append("    set qblock [dict get $info block]")
    lines.append("    if {$label eq \"\"} {")
    lines.append("        set label \"${qblock}.${qname}\"")
    lines.append("    }")
    lines.append("    # Convert QEMU field format {name msb lsb} → dump_reg's {msb lsb name}")
    lines.append("    set bit_decode [list]")
    lines.append("    foreach f [dict get $info fields] {")
    lines.append("        set fname [lindex $f 0]")
    lines.append("        set fmsb  [lindex $f 1]")
    lines.append("        set flsb  [lindex $f 2]")
    lines.append("        lappend bit_decode [list $fmsb $flsb $fname]")
    lines.append("    }")
    lines.append("    set _v [dump_reg $label $addr $bit_decode]")
    lines.append("    # JSON capture: record into ::CAPTURED if json-emit.tcl was sourced.")
    lines.append("    # Builds a fields dict mapping field-name -> { bits, value }.")
    lines.append("    if {[info commands capture_register] ne \"\"} {")
    lines.append("        set _fields [dict create]")
    lines.append("        # Accept both decimal ('1299') and hex ('0x00000513') forms")
    lines.append("        # because OpenOCD's read_memory returns hex strings on some builds.")
    lines.append("        # `expr int(...)` parses both; catch rejects ERR/empty cleanly.")
    lines.append("        if {[catch {expr {int($_v)}} _vint] == 0} {")
    lines.append("            foreach f [dict get $info fields] {")
    lines.append("                set fname [lindex $f 0]")
    lines.append("                set fmsb  [lindex $f 1]")
    lines.append("                set flsb  [lindex $f 2]")
    lines.append("                set fwidth [expr {$fmsb - $flsb + 1}]")
    lines.append("                set fmask  [expr {(1 << $fwidth) - 1}]")
    lines.append("                set fval   [expr {($_vint >> $flsb) & $fmask}]")
    lines.append("                set bitstr [expr {$fmsb == $flsb ? \"$flsb\" : \"$fmsb:$flsb\"}]")
    lines.append("                dict set _fields $fname [dict create bits $bitstr value $fval]")
    lines.append("            }")
    lines.append("        }")
    lines.append("        capture_register $addr $qname $qblock $_v $_fields")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    all_regs: list[Reg] = []
    for relpath, base, block in BLOCKS:
        regs = parse_block(relpath, base, block)
        all_regs.extend(regs)
        print(
            f"  {block:<12} {len(regs):4d} registers from {relpath}",
            file=sys.stderr,
        )

    output = render_tcl(all_regs)
    OUTPUT_PATH.write_text(output)
    print(
        f"\nWrote {len(all_regs)} registers to {OUTPUT_PATH}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
