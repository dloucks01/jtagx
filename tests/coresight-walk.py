#!/usr/bin/env python3
"""
coresight-walk.py — unit test for jtagx/coresight.py (Phase 2 §2.1/2.3).

Builds a synthetic ADIv5 ROM table (a ZynqMP APU CoreSight cluster: A53 Debug/
CTI/PMU/ETM + funnel + ETB) as an in-memory {addr:word} map, runs the real
walk_rom_table() over it via dict_reader(), and asserts every component is
discovered AND identified by PIDR against references/coresight-parts.json.
Also exercises the OpenOCD `dap info` text parser and the ignore paths
(bus-float, unmapped). Fully offline — the walker's read32 is the dict.
"""
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from jtagx import coresight as cs  # noqa: E402


def _fail(m):
    print(f"FAIL(coresight-walk): {m}")
    sys.exit(1)


def _write_ids(mem: dict, base: int, cls: int, part: int, designer_jep: int = 0x3B,
               devtype: int | None = None):
    """Populate the CIDR/PIDR ID block for a component at `base`.

    Encodes designer as a JEP106 7-bit code split across PIDR1[7:4] (low nibble)
    and PIDR2[2:0] (high 3 bits), part across PIDR0[7:0]+PIDR1[3:0] — exactly the
    layout coresight._read_ids() decodes."""
    mem[base + cs.CIDR0] = 0x0D
    mem[base + cs.CIDR1] = ((cls & 0xF) << 4) | 0x0
    mem[base + cs.CIDR2] = 0x05
    mem[base + cs.CIDR3] = 0xB1
    mem[base + cs.PIDR0] = part & 0xFF
    mem[base + cs.PIDR1] = (((designer_jep & 0x0F) << 4) | ((part >> 8) & 0x0F))
    mem[base + cs.PIDR2] = (1 << 3) | ((designer_jep >> 4) & 0x07)   # JEDEC bit + des[6:4]
    mem[base + cs.PIDR4] = 0x4                                        # ARM continuation bank
    if devtype is not None:
        mem[base + cs.DEVTYPE] = devtype
        mem[base + cs.DEVARCH] = 0                                    # ARCHID not present


# --- Build a synthetic ZynqMP APU CoreSight cluster ---
ROM = 0x80000000
COMPONENTS = [
    (0x80010000, 0x9, 0xD03, "Cortex-A53 Debug"),
    (0x80020000, 0x9, 0x9A8, "Cortex-A53 CTI"),
    (0x80030000, 0x9, 0x9D3, "Cortex-A53 PMU"),
    (0x80040000, 0x9, 0x95D, "Cortex-A53 ETM"),
    (0x80050000, 0x9, 0x908, "CoreSight CSTF"),
    (0x80060000, 0x9, 0x907, "CoreSight ETB"),
]
mem: dict = {}
# ROM table itself (class 1, part 0 → identifies as "ROM table")
_write_ids(mem, ROM, cls=0x1, part=0x000)
for i, (cbase, ccls, cpart, _name) in enumerate(COMPONENTS):
    mem[ROM + i * 4] = ((cbase - ROM) & 0xFFFFF000) | 0x1     # ROM entry: offset + present
    _write_ids(mem, cbase, cls=ccls, part=cpart, devtype=0x15)
mem[ROM + len(COMPONENTS) * 4] = 0x00000000                  # terminator

found = cs.walk_rom_table(cs.dict_reader(mem), ROM)

# 1. All 6 components + the ROM table itself are discovered.
bases = {c.base for c in found}
if ROM not in bases:
    _fail("ROM table itself should be in the component list")
for cbase, _c, _p, name in COMPONENTS:
    if cbase not in bases:
        _fail(f"component at 0x{cbase:08X} ({name}) not discovered")

# 2. Each is identified by PIDR against the parts table.
bybase = {c.base: c for c in found}
for cbase, _c, cpart, name in COMPONENTS:
    comp = bybase[cbase]
    if comp.part != cpart:
        _fail(f"0x{cbase:08X}: part decoded 0x{comp.part:03X}, expected 0x{cpart:03X}")
    if comp.designer != 0x3B:
        _fail(f"0x{cbase:08X}: designer decoded 0x{comp.designer:02X}, expected 0x3B (Arm)")
    if name not in comp.name:
        _fail(f"0x{cbase:08X}: name '{comp.name}' should contain '{name}'")

# 3. The summary rolls up correctly.
s = cs.summarize(found)
if s["core_debug_units"] != 1:
    _fail(f"expected 1 core-debug unit, got {s['core_debug_units']}")
if not s["has_trace"]:
    _fail("cluster has ETM/ETB → has_trace should be True")
if not s["has_cti"]:
    _fail("cluster has CTI → has_cti should be True")

# 4. Bus-float / unmapped ROM base → empty (no crash).
if cs.walk_rom_table(cs.dict_reader({}), 0x80000000):
    _fail("empty memory (all bus-float) should yield no components")

# 5. Nested ROM table recursion.
mem2: dict = {}
TOP, SUB = 0x90000000, 0x90100000
_write_ids(mem2, TOP, cls=0x1, part=0x000)
mem2[TOP + 0] = ((SUB - TOP) & 0xFFFFF000) | 0x1
mem2[TOP + 4] = 0
_write_ids(mem2, SUB, cls=0x1, part=0x000)
mem2[SUB + 0] = ((0x90110000 - SUB) & 0xFFFFF000) | 0x1
mem2[SUB + 4] = 0
_write_ids(mem2, 0x90110000, cls=0x9, part=0xC24, devtype=0x15)  # Cortex-M4
nest = cs.walk_rom_table(cs.dict_reader(mem2), TOP)
if not any("Cortex-M4" in c.name for c in nest):
    _fail("nested ROM table: Cortex-M4 behind a sub-table should be discovered")
if max(c.depth for c in nest) < 2:
    _fail("nested component should carry depth >= 2")

# 6. OpenOCD `dap info` text parser (best-effort).
SAMPLE = """AP # 0x0
\t\tAP ID register 0x24770004
\t\tType is MEM-AP AXI3 or AXI4
MEM-AP BASE 0xfe800000
\t\tROM table @ 0xfe800000
\t[0x000] Component base 0xfe810000  Cortex-A53 Debug  Part is 0xd03
\t[0x001] Component base 0xfe820000  CoreSight CTI (Cross Trigger)
\t[0x002] Component base 0xfe9c0000  CoreSight ETB (Trace Buffer)
"""
parsed = cs.parse_dap_info(SAMPLE)
names = " ".join(c.name for c in parsed)
if "Cortex-A53 Debug" not in names or "CTI" not in names or "ETB" not in names:
    _fail(f"dap-info parse missed components: got '{names}'")
# 'No ROM table present' text yields nothing (not a crash).
if cs.parse_dap_info("AP # 0x1\nMEM-AP BASE 0xfeff0002\n\t\tNo ROM table present\n"):
    _fail("'No ROM table present' should parse to no components")

# 7. render_md produces a non-empty section with the summary line.
md = cs.render_md(found)
if "Debug topology" not in md or "core-debug unit" not in md:
    _fail("render_md should include a title and summary line")

print(f"PASS: coresight-walk (walked {len(found)} components, identified A53 cluster + "
      "nested recursion + dap-info parse)")
