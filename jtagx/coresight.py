"""
coresight.py — ADIv5/ADIv6 CoreSight ROM-table walker + component identification.

Two entry points, both feeding the same component model:

  1. walk_rom_table(read32, base)  — the real ADIv5/v6 ROM-table walk. Give it a
     `read32(addr)->int` callable (a live MEM-AP read, or a dict-backed reader over
     a captured memory region) and a ROM base address; it returns a flat list of
     Component objects (class, part, designer, base, human name), recursing into
     nested ROM tables. This is transport-agnostic: the same code runs live and
     offline against a captured map.

  2. parse_dap_info(text)          — best-effort parser for OpenOCD's `dap info N`
     verbatim text (what enumerate.tcl §10 already captures). Turns the human tree
     into the same Component model so a capture that only has the text still yields
     a structured topology.

Identification (identify()) resolves the CoreSight (class,designer,part) triple to
a human name via references/coresight-parts.json.

Spec basis: Arm IHI0031 (ADIv5) / IHI0074 (ADIv6), Arm IHI0029 (CoreSight arch).
Component ID / Peripheral ID register layout is the standard 0xFB0–0xFFC block.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

# --- CoreSight ID-register offsets (top of every 4KB component block) ---
CIDR0, CIDR1, CIDR2, CIDR3 = 0xFF0, 0xFF4, 0xFF8, 0xFFC
PIDR0, PIDR1, PIDR2, PIDR3 = 0xFE0, 0xFE4, 0xFE8, 0xFEC
PIDR4, PIDR5, PIDR6, PIDR7 = 0xFD0, 0xFD4, 0xFD8, 0xFDC
DEVARCH, DEVTYPE = 0xFBC, 0xFCC

# Component classes (CIDR1[7:4]).
CLASS_NAMES = {
    0x0: "generic-verification",
    0x1: "ROM-table",            # ADIv5 ROM table
    0x9: "CoreSight",            # CoreSight component (incl. ADIv6 ROM table)
    0xB: "generic-PrimeCell",
    0xE: "generic-IP",
    0xF: "PrimeCell",
}

# CIDR preamble (fixed): CIDR0=0x0D, CIDR2=0x05, CIDR3=0xB1, CIDR1[3:0]=0.
_CIDR0_PREAMBLE, _CIDR2_PREAMBLE, _CIDR3_PREAMBLE = 0x0D, 0x05, 0xB1

# DEVTYPE major/sub (CoreSight arch) — the coarse "what kind of block" for class-9.
_DEVTYPE_MAJOR = {
    0x0: "misc", 0x1: "trace-sink", 0x2: "trace-link", 0x3: "trace-source",
    0x4: "debug-control", 0x5: "debug-logic", 0x6: "perf-monitor",
}

# ADIv6 ROM table is class-9 with this DEVARCH ARCHID.
_ADIV6_ROM_ARCHID = 0x0AF7

_PARTS_PATH = Path(__file__).resolve().parent.parent / "references" / "coresight-parts.json"
_PARTS_CACHE: dict | None = None


@dataclass
class Component:
    """One CoreSight component discovered on the debug fabric."""
    base: int                       # absolute base address on the AP
    cls: int                        # component class (CIDR1[7:4])
    part: int | None = None         # 12-bit part number (PIDR)
    designer: int | None = None     # JEP106 designer code (7-bit, e.g. 0x3B = Arm)
    devtype: int | None = None      # DEVTYPE (class-9 only)
    archid: int | None = None       # DEVARCH ARCHID (class-9 only)
    name: str = ""                  # resolved human name
    kind: str = ""                  # class name / role
    depth: int = 0                  # nesting depth in the ROM hierarchy

    def as_dict(self) -> dict:
        d = {
            "base": f"0x{self.base:08X}",
            "class": f"0x{self.cls:X}",
            "kind": self.kind or CLASS_NAMES.get(self.cls, f"class-{self.cls:#x}"),
            "name": self.name or "(unidentified)",
            "depth": self.depth,
        }
        if self.part is not None:
            d["part"] = f"0x{self.part:03X}"
        if self.designer is not None:
            d["designer"] = f"0x{self.designer:02X}"
        if self.devtype is not None:
            d["devtype"] = f"0x{self.devtype:02X}"
        if self.archid:
            d["archid"] = f"0x{self.archid:04X}"
        return d


def _load_parts() -> dict:
    """Load + normalize the parts table. Keys are lower-cased so hex-case in the
    JSON never has to match the code's formatting."""
    global _PARTS_CACHE
    if _PARTS_CACHE is None:
        try:
            raw = json.loads(_PARTS_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raw = {"designers": {}, "parts": {}}
        _PARTS_CACHE = {
            "designers": {k.lower(): v for k, v in raw.get("designers", {}).items()},
            "parts": {k.lower(): v for k, v in raw.get("parts", {}).items()},
        }
    return _PARTS_CACHE


def designer_name(designer: int | None) -> str:
    if designer is None:
        return "?"
    return _load_parts().get("designers", {}).get(f"0x{designer:02x}", f"designer-0x{designer:02X}")


def identify(cls: int, designer: int | None, part: int | None,
             devtype: int | None = None, archid: int | None = None) -> str:
    """Resolve a component to a human name. Part table keyed by 'designer:part'."""
    parts = _load_parts().get("parts", {})
    if designer is not None and part is not None:
        key = f"0x{designer:02x}:0x{part:03x}"
        if key in parts:
            return parts[key]
    # Fall back to a class/devtype description so nothing is a bare hex blob.
    if cls == 0x1 or (cls == 0x9 and archid == _ADIV6_ROM_ARCHID):
        return "ROM table"
    if cls == 0x9 and devtype is not None:
        major = _DEVTYPE_MAJOR.get(devtype & 0xF, "misc")
        return f"CoreSight {major} (part 0x{part:03X})" if part is not None else f"CoreSight {major}"
    if part is not None:
        return f"{designer_name(designer)} component 0x{part:03X}"
    return CLASS_NAMES.get(cls, f"class-{cls:#x}")


def _read_ids(read32, base: int) -> dict | None:
    """Read the CIDR/PIDR/DEVARCH/DEVTYPE block for the component at `base`.

    Returns a dict of decoded fields, or None if the CIDR preamble is invalid
    (no component present / bus float)."""
    try:
        c0 = read32(base + CIDR0) & 0xFF
        c1 = read32(base + CIDR1) & 0xFF
        c2 = read32(base + CIDR2) & 0xFF
        c3 = read32(base + CIDR3) & 0xFF
    except Exception:
        return None
    # Validate the fixed CIDR preamble — this is what tells a real component from
    # a floating bus (0xFFFFFFFF) or unmapped space (0).
    if c0 != _CIDR0_PREAMBLE or c2 != _CIDR2_PREAMBLE or c3 != _CIDR3_PREAMBLE:
        return None
    if (c1 & 0x0F) != 0x0:
        return None
    cls = (c1 >> 4) & 0xF

    try:
        p0 = read32(base + PIDR0) & 0xFF
        p1 = read32(base + PIDR1) & 0xFF
        p2 = read32(base + PIDR2) & 0xFF
        p4 = read32(base + PIDR4) & 0xFF
    except Exception:
        p0 = p1 = p2 = p4 = 0
    part = p0 | ((p1 & 0x0F) << 8)                       # 12-bit part number
    # JEP106 designer: 7-bit ID = PIDR2[2:0]<<4 | PIDR1[7:4]; PIDR4[3:0] = continuation.
    designer = (((p2 & 0x07) << 4) | ((p1 >> 4) & 0x0F)) & 0x7F

    devtype = archid = None
    if cls == 0x9:
        try:
            devtype = read32(base + DEVTYPE) & 0xFF
            devarch = read32(base + DEVARCH)
            if devarch & (1 << 20):                       # DEVARCH.PRESENT
                archid = devarch & 0xFFFF
        except Exception:
            pass
    return {"cls": cls, "part": part, "designer": designer,
            "devtype": devtype, "archid": archid}


def _is_rom_table(ids: dict) -> bool:
    """ADIv5 ROM table = class 1. ADIv6 ROM table = class 9 + ARCHID 0x0AF7."""
    if ids["cls"] == 0x1:
        return True
    return ids["cls"] == 0x9 and ids.get("archid") == _ADIV6_ROM_ARCHID


def walk_rom_table(read32, base: int, depth: int = 0, seen: set | None = None,
                   max_entries: int = 960, max_components: int = 256) -> list[Component]:
    """Walk a CoreSight ROM table at `base`, returning a flat Component list.

    `read32(addr)` reads one 32-bit word (live MEM-AP read or a captured-map
    reader). Recurses into nested ROM tables; `seen` guards against cycles.
    Robust to unmapped space / bus floats via the CIDR preamble check.
    """
    if seen is None:
        seen = set()
    out: list[Component] = []
    if base in seen or len(seen) > max_components:
        return out
    seen.add(base)

    ids = _read_ids(read32, base)
    if ids is None:
        return out
    # Record the table itself as a component (depth marks hierarchy).
    tbl = Component(base=base, cls=ids["cls"], part=ids["part"], designer=ids["designer"],
                    devtype=ids["devtype"], archid=ids["archid"], depth=depth)
    tbl.kind = CLASS_NAMES.get(ids["cls"], f"class-{ids['cls']:#x}")
    tbl.name = identify(ids["cls"], ids["designer"], ids["part"], ids["devtype"], ids["archid"])
    out.append(tbl)

    if not _is_rom_table(ids):
        return out

    # Walk entries: 32-bit words from offset 0, terminated by a 0 entry.
    for i in range(max_entries):
        try:
            entry = read32(base + i * 4)
        except Exception:
            break
        if entry == 0:                       # end-of-table marker
            break
        if not (entry & 0x1):                # ENTRY_PRESENT clear → skip slot
            continue
        # ADDRESS_OFFSET is a signed 20-bit value in bits [31:12], scaled by 4KB.
        off = (entry & 0xFFFFF000)
        if off & 0x80000000:                 # sign-extend the 32-bit offset
            off -= 0x100000000
        comp_base = (base + off) & 0xFFFFFFFFFFFF
        child = _read_ids(read32, comp_base)
        if child is None:
            continue
        if _is_rom_table(child):
            out.extend(walk_rom_table(read32, comp_base, depth + 1, seen,
                                      max_entries, max_components))
        else:
            c = Component(base=comp_base, cls=child["cls"], part=child["part"],
                          designer=child["designer"], devtype=child["devtype"],
                          archid=child["archid"], depth=depth + 1)
            c.kind = CLASS_NAMES.get(child["cls"], f"class-{child['cls']:#x}")
            c.name = identify(child["cls"], child["designer"], child["part"],
                              child["devtype"], child["archid"])
            out.append(c)
        if len(out) >= max_components:
            break
    return out


def dict_reader(mem: dict):
    """Build a read32 callable over a {addr:int -> word:int} capture dict.

    Missing addresses read as 0xFFFFFFFF (bus-float) so the preamble check
    rejects them exactly as a live unmapped read would."""
    def _r(addr):
        return mem.get(addr, 0xFFFFFFFF) & 0xFFFFFFFF
    return _r


# --- OpenOCD `dap info` text parser (best-effort convenience path) ---------

# OpenOCD prints component lines that carry a base + a trailing human "Type"/name.
# Formats vary by version; we match the durable fragments:
#   "MEM-AP BASE 0xfeff0002"
#   "\t[0x000]   Component base 0xfe800000"  + a following "Type is ..." / part line
#   "\t\tPeripheral ID ... Designer is ... Part is 0x... <Name>"
_RE_APID = re.compile(r"AP ID register\s+(0x[0-9a-fA-F]+)")
_RE_BASE = re.compile(r"(?:MEM-AP BASE|Component base)\s+(0x[0-9a-fA-F]+)")
_RE_TYPE = re.compile(r"Type is\s+(.+?)\s*$")
_RE_PART = re.compile(r"[Pp]art (?:is |num )?(0x[0-9a-fA-F]+)")
# A component-summary line many OpenOCD versions emit, e.g.:
#   "0x04770906 ... Cortex-A53 Debug ..." or trailing designer/part + name.
_RE_NAMED = re.compile(
    r"(Cortex-[AMR]\d+\w*(?: \w+)?|CTI|ETM\w*|ETB|ETF|ETR|TPIU|TMC|Funnel|Replicator|"
    r"ITM|DWT|FPB|SCS|ROM [Tt]able|CoreSight \w+|MTB|STM|Timestamp \w+)")


def parse_dap_info(text: str) -> list[Component]:
    """Best-effort: turn OpenOCD `dap info` verbatim text into Components.

    This does not re-implement the walk — it lifts the base addresses + human
    names OpenOCD already printed. Returns [] if nothing recognizable is found
    (e.g. 'No ROM table present' / a sticky-error AP)."""
    comps: list[Component] = []
    cur_base = None
    for raw in text.splitlines():
        line = raw.rstrip()
        # Skip the negative / error lines that would otherwise false-match below
        # ("No ROM table present" contains "ROM table"; a sticky-error AP has none).
        low = line.lower()
        if "no rom table" in low or "sticky error" in low or "not present" in low:
            cur_base = None
            continue
        mb = _RE_BASE.search(line)
        if mb:
            cur_base = int(mb.group(1), 16)
        name_m = _RE_NAMED.search(line)
        if name_m and cur_base is not None:
            part_m = _RE_PART.search(line)
            comps.append(Component(
                base=cur_base,
                cls=0x1 if "ROM" in name_m.group(1) else 0x9,
                part=int(part_m.group(1), 16) if part_m else None,
                name=name_m.group(1).strip(),
                kind="ROM-table" if "ROM" in name_m.group(1) else "CoreSight",
            ))
            cur_base = None  # consume; next base line starts a fresh component
    return comps


def summarize(components: list[Component]) -> dict:
    """Roll a component list into a coarse capability summary (for rules/reports)."""
    kinds = {}
    for c in components:
        key = c.name or c.kind
        kinds[key] = kinds.get(key, 0) + 1
    cores = sum(1 for c in components if "Cortex" in (c.name or "") and "Debug" in (c.name or ""))
    return {
        "total": len(components),
        "rom_tables": sum(1 for c in components if c.cls == 0x1 or (c.cls == 0x9 and c.archid == _ADIV6_ROM_ARCHID)),
        "core_debug_units": cores,
        "has_trace": any(k in (c.name or c.kind) for c in components
                         for k in ("ETM", "ETB", "ETF", "ETR", "TPIU", "trace")),
        "has_cti": any("CTI" in (c.name or "") for c in components),
        "by_name": kinds,
    }


def render_md(components: list[Component], title: str = "Debug topology (CoreSight)") -> str:
    """Render a component list as a markdown section."""
    if not components:
        return ""
    lines = [f"### {title}", "",
             "| Base | Class | Component | Part · Designer |",
             "|---|---|---|---|"]
    for c in sorted(components, key=lambda x: x.base):
        indent = "&nbsp;&nbsp;" * c.depth
        part = f"`0x{c.part:03X}`" if c.part is not None else "—"
        des = designer_name(c.designer) if c.designer is not None else "—"
        lines.append(f"| `0x{c.base:08X}` | {c.kind} | {indent}{c.name or '(unidentified)'} | {part} · {des} |")
    s = summarize(components)
    lines += ["",
              f"_{s['total']} components · {s['core_debug_units']} core-debug unit(s) · "
              f"trace={'yes' if s['has_trace'] else 'no'} · cross-trigger(CTI)={'yes' if s['has_cti'] else 'no'}._"]
    return "\n".join(lines)
