#!/usr/bin/env python3
"""
check-annotations.py — sanity check for docs/annotations/zynqmp_*.py.

Catches the regressions the per-rendering golden tests miss:
  - import errors in either annotation module
  - duplicate (register, field) entries (one would silently win, the other dead)
  - field annotations whose (register, field) pair doesn't exist in either
    openocd/lib/zynqmp-regs-qemu.tcl OR the manually-injected IDCODE path
  - wildcard annotations (register="*") whose field doesn't appear in ANY
    register (matches nothing → dead)
  - register-level annotations whose register doesn't exist anywhere

Exit 0 = all clean.
Exit 1 = at least one issue (printed to stderr).
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
ANN_DIR = PROJECT / "docs" / "annotations"
REGS_TCL = PROJECT / "openocd" / "lib" / "zynqmp-regs-qemu.tcl"
EXTENSION_TCL = PROJECT / "openocd" / "lib" / "zynqmp-regs-extension.tcl"
ENUMERATE_TCL = PROJECT / "openocd" / "enumerate.tcl"

# Manually-injected fields not in zynqmp-regs-qemu.tcl — see enumerate.tcl
# around line 99-115 (the IDCODE capture block).
MANUAL_INJECTED_FIELDS = {
    ("CSU.IDCODE", "CONST_1"),
    ("CSU.IDCODE", "MANUF_ID"),
    ("CSU.IDCODE", "PART_ID"),
    ("CSU.IDCODE", "REVISION"),
}


def _load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, str(path))
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(PROJECT / "tools"))
    spec.loader.exec_module(mod)
    return mod


_REG_RE = re.compile(
    r"name\s+(\w+)\s*\\\s*\n\s*block\s+(\w+)\s*\\\s*\n\s*fields\s*\[list\s*\\?(.*?)\]\]",
    re.DOTALL,
)
_FIELD_RE = re.compile(r"\[list\s+(\w+)\s+\d+\s+\d+\]")


def _add_regs(text: str, out: dict) -> None:
    for name, block, fields_body in _REG_RE.findall(text):
        regset = out.setdefault(block, {}).setdefault(name, set())
        for f in _FIELD_RE.finditer(fields_body):
            regset.add(f.group(1))


def parse_regs_tcl() -> dict:
    """Return {block: {regname: set(field_names)}} merged from the auto-generated
    QEMU regs Tcl plus the hand-verified extension Tcl. Both contribute to
    the same ::QEMU_REGS dict at runtime, so they're both authoritative."""
    out: dict[str, dict[str, set]] = {}
    _add_regs(REGS_TCL.read_text(), out)
    if EXTENSION_TCL.exists():
        _add_regs(EXTENSION_TCL.read_text(), out)
    return out


def main() -> int:
    issues: list[str] = []

    # Load both annotation modules
    sec = _load(ANN_DIR / "zynqmp_security.py")
    gen = _load(ANN_DIR / "zynqmp_general.py")

    field_anns = list(getattr(sec, "ANNOTATIONS", [])) + list(getattr(gen, "ANNOTATIONS", []))
    reg_anns = list(getattr(sec, "REGISTER_ANNOTATIONS", [])) + list(getattr(gen, "REGISTER_ANNOTATIONS", []))

    # Index registers from generated Tcl
    regs = parse_regs_tcl()
    # Build lookups
    all_regs = set()  # {"BLOCK.REG", "REG"}
    all_fields_anywhere = set()
    field_to_regs: dict[str, set] = {}
    for block, regs_map in regs.items():
        for regname, fields in regs_map.items():
            all_regs.add(f"{block}.{regname}")
            all_regs.add(regname)
            for f in fields:
                all_fields_anywhere.add(f)
                field_to_regs.setdefault(f, set()).add(f"{block}.{regname}")
    # Add manual-injected
    for reg, field in MANUAL_INJECTED_FIELDS:
        all_regs.add(reg)
        all_regs.add(reg.split(".", 1)[1])
        all_fields_anywhere.add(field)
        field_to_regs.setdefault(field, set()).add(reg)

    # Check 1: duplicate (register, field) across modules
    seen: dict[tuple[str, str], str] = {}
    for ann in field_anns:
        key = (ann.register, ann.field)
        if key in seen:
            issues.append(
                f"DUPLICATE field annotation: register={ann.register!r} field={ann.field!r} "
                f"(first declared in {seen[key]}, redeclared — second silently wins via first-occurrence)"
            )
        else:
            seen[key] = "ANNOTATIONS list"

    # Check 2: register-level duplicates
    seen_r: dict[str, str] = {}
    for ann in reg_anns:
        if ann.register in seen_r:
            issues.append(
                f"DUPLICATE register-level annotation: register={ann.register!r}"
            )
        else:
            seen_r[ann.register] = "REGISTER_ANNOTATIONS list"

    # Check 3: field annotation's register must exist
    for ann in field_anns:
        if ann.register == "*":
            # Wildcard: field must exist somewhere
            if ann.field not in all_fields_anywhere:
                issues.append(
                    f"DEAD wildcard: register='*' field={ann.field!r} matches no register — "
                    f"annotation is unreachable"
                )
            continue
        if ann.register not in all_regs:
            issues.append(
                f"UNKNOWN register: {ann.register!r} (field={ann.field!r}) — "
                f"not in zynqmp-regs-qemu.tcl"
            )
            continue
        # Check the field name exists in that register
        target_regs = field_to_regs.get(ann.field, set())
        if "." in ann.register:
            if ann.register not in target_regs:
                issues.append(
                    f"FIELD NOT IN REGISTER: {ann.register}.{ann.field} — "
                    f"field {ann.field!r} not declared on {ann.register}"
                )
        else:
            # Short-form register — check that SOME block.REG.field exists
            short = ann.register
            if not any(r.endswith(f".{short}") or r == short for r in target_regs):
                issues.append(
                    f"FIELD NOT IN REGISTER (short-form): {ann.register}.{ann.field} — "
                    f"no block has {short}.{ann.field}"
                )

    # Check 4: register-level annotation's register must exist
    for ann in reg_anns:
        if ann.register not in all_regs:
            issues.append(
                f"UNKNOWN register (register-level): {ann.register!r} — "
                f"not in zynqmp-regs-qemu.tcl"
            )

    # Output
    if issues:
        print(f"check-annotations.py: {len(issues)} issue(s)", file=sys.stderr)
        for issue in issues:
            print(f"  - {issue}", file=sys.stderr)
        return 1

    print(
        f"check-annotations.py: OK — "
        f"{len(field_anns)} field annotations, "
        f"{len(reg_anns)} register-level annotations, "
        f"all references resolve",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
