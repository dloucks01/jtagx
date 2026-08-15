#!/usr/bin/env python3
"""
interpret.py — produce a rich findings report from a raw enumeration JSON.

This is the analysis half of the capture/interpret split.

Inputs:
  - reports/raw-<timestamp>.json     (from enumerate.tcl)
  - docs/annotations/zynqmp_security.py   (per-field meanings)
  - docs/findings/zynqmp_rules.py         (cross-register rule functions)

Output:
  - reports/interpreted-<timestamp>.md   (or stdout)

The annotation module exports `ANNOTATIONS` — a list of Annotation
dataclass instances. The rules module exports `ALL_RULES` — a list of
functions (Capture -> Finding | None). The interpret tool walks the raw
JSON, looks up annotations for each field, evaluates each rule, and
emits markdown.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

# Add the tools directory itself to sys.path so interpret_lib is importable
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from interpret_lib import Capture, Finding, Annotation, RegisterAnnotation  # noqa: E402


ANNOTATIONS_DIR = PROJECT_ROOT / "docs" / "annotations"
RULES_MODULE = PROJECT_ROOT / "docs" / "findings" / "zynqmp_rules.py"


# ---------------------------------------------------------------------------
# Dynamic module loading — annotations and rules live under docs/ which
# isn't on sys.path; load them by file path.
# ---------------------------------------------------------------------------

def _load_module(name: str, path: Path):
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location(name, str(path))
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_annotations(annotations_dir: Path) -> tuple[list[Annotation],
                                                       list[RegisterAnnotation]]:
    """Load every zynqmp_*.py file under annotations_dir.

    Each module may export ANNOTATIONS (field-level) and/or
    REGISTER_ANNOTATIONS (register-level). Both are concatenated across
    modules so callers see one combined list of each kind.
    """
    field_anns: list[Annotation] = []
    reg_anns: list[RegisterAnnotation] = []
    if not annotations_dir.exists():
        return field_anns, reg_anns
    for path in sorted(annotations_dir.glob("zynqmp_*.py")):
        mod = _load_module(path.stem, path)
        if mod is None:
            continue
        if hasattr(mod, "ANNOTATIONS"):
            field_anns.extend(mod.ANNOTATIONS)
        if hasattr(mod, "REGISTER_ANNOTATIONS"):
            reg_anns.extend(mod.REGISTER_ANNOTATIONS)
    return field_anns, reg_anns


def load_rules(path: Path) -> list:
    mod = _load_module("zynqmp_rules", path)
    if mod is None or not hasattr(mod, "ALL_RULES"):
        return []
    return list(mod.ALL_RULES)


def load_json(path: Path) -> dict:
    try:
        with open(path) as fh:
            return json.load(fh)
    except OSError as e:
        sys.exit(f"error: cannot read {path}: {e.strerror}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        sys.exit(f"error: {path} is not a valid raw JSON capture (expected reports/raw-*.json). "
                 "Did you pass a binary dump by mistake?")


# ---------------------------------------------------------------------------
# Annotation lookup
# ---------------------------------------------------------------------------

def build_annotation_index(annotations: list[Annotation]) -> dict:
    """Build an O(1) lookup index for find_annotation.

    Returns a dict keyed by `(register, field)` where register is the
    annotation's `register` field literal ("BLOCK.REG", "REG", or "*").
    First-occurrence wins on duplicate keys to match find_annotation's
    deterministic-order behaviour.
    """
    idx: dict[tuple[str, str], Annotation] = {}
    for entry in annotations:
        key = (entry.register, entry.field)
        idx.setdefault(key, entry)
    return idx


def find_annotation(annotation_index: dict, block: str,
                    reg: str, field: str) -> Annotation | None:
    """Look up field-level annotation entry for a specific (block, register, field).

    Match precedence (most specific wins, deterministic):
      1. exact match on "BLOCK.REGISTER" + field        (full block-qualified)
      2. exact match on "REGISTER" + field              (register-only)
      3. wildcard "*" + field                           (cross-register)

    O(1) lookup via pre-built index from `build_annotation_index`.
    """
    full = f"{block}.{reg}"
    return (annotation_index.get((full, field))
            or annotation_index.get((reg, field))
            or annotation_index.get(("*", field)))


def build_register_annotation_index(reg_anns: list[RegisterAnnotation]) -> dict:
    """O(1) index for register-level annotations keyed by `register` literal."""
    idx: dict[str, RegisterAnnotation] = {}
    for entry in reg_anns:
        idx.setdefault(entry.register, entry)
    return idx


def find_register_annotation(reg_index: dict, block: str,
                             reg: str) -> RegisterAnnotation | None:
    """Look up register-level annotation. O(1) via pre-built index."""
    full = f"{block}.{reg}"
    return reg_index.get(full) or reg_index.get(reg)


def _value_to_int(v) -> int | None:
    """Best-effort hex/decimal -> int. Returns None on ERR/empty/unparseable."""
    if v is None:
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, str):
        s = v.strip()
        if not s or s == "ERR":
            return None
        try:
            return int(s, 16) if s.lower().startswith("0x") else int(s, 10)
        except ValueError:
            return None
    return None


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------

SEVERITY_MARKER = {
    "CRITICAL": "🔴",
    "MAJOR":    "🟠",
    "MINOR":    "🟡",
    "INFO":     "🔵",
}


def render_markdown(captured: dict, annotations: list[Annotation],
                    reg_annotations: list[RegisterAnnotation],
                    rules: list, raw_path: Path,
                    full: bool = False) -> str:
    """Render the interpreted report.

    Builds O(1) annotation indices once up-front and passes them down to
    field/register lookups so per-field work is constant-time regardless
    of annotation-list size.

    full=False (default, compact): one line per field including label and
        meaning packed together. Blank lines only between registers.
        Roughly half the length of `full` output.
    full=True: original verbose layout — each field gets its own indented
        sub-bullet structure with separate label, meaning, offensive-use
        lines, and a blank line between every field.
    """
    cap = Capture(captured)
    ann_index = build_annotation_index(annotations)
    reg_index = build_register_annotation_index(reg_annotations)
    out: list[str] = []
    meta = captured.get("metadata", {})

    # ===== Header =====
    out.append(f"# Enumeration Findings — {meta.get('board', 'unknown')}")
    out.append("")
    out.append(f"- Captured: `{meta.get('timestamp', '?')}`")
    out.append(f"- Source JSON: `{raw_path}`")
    out.append(f"- Generated by: `tools/interpret.py`")
    out.append("")
    out.append("This report is produced by the analysis half of the capture/interpret split.")
    out.append("Raw register values come from `enumerate.tcl`'s JSON output. Per-field")
    out.append("annotations come from every `docs/annotations/zynqmp_*.py` module. Findings")
    out.append("rules come from `docs/findings/zynqmp_rules.py`.")
    out.append("")
    out.append("---")
    out.append("")

    # ===== Evaluate rules once (shared by the top triage banner + the Findings section) =====
    fired: list[Finding] = []
    failed_rules: list[tuple[str, str]] = []
    for rule_fn in rules:
        try:
            f = rule_fn(cap)
        except Exception as exc:
            failed_rules.append((rule_fn.__name__, repr(exc)))
            continue
        if f is not None:
            fired.append(f)
    n_fired_total = len(fired)

    # ===== Top-line triage banner (BLUF) — promoted above all findings =====
    triage = next((f for f in fired if f.name.startswith("Engagement Triage")), None)
    if triage is not None:
        fired.remove(triage)
        marker = SEVERITY_MARKER.get(triage.severity, "")
        out.append(f"## {marker} {triage.name}".rstrip())
        out.append("")
        if triage.description:
            out.append(f"_{triage.description}_")
            out.append("")
        if triage.conclusion:
            out.append(triage.conclusion)
            out.append("")
        out.append("---")
        out.append("")

    # ===== Silicon identity =====
    variant = captured.get("variant", {})
    if variant:
        out.append("## Silicon identity (from variant lookup)")
        out.append("")
        out.append("| Attribute | Value |")
        out.append("|---|---|")
        ordered_keys = [
            "die", "family", "marketed_as",
            "a53_cores", "r5_cores",
            "has_gpu", "may_have_vcu", "has_rf", "gem_count",
            "part_id", "silicon_rev",
            "device_dna_0", "device_dna_1", "device_dna_2",
        ]
        for k in ordered_keys:
            if k in variant:
                v = variant[k]
                out.append(f"| `{k}` | {v} |")
        if variant.get("notes"):
            out.append(f"| `notes` | {variant['notes']} |")
        out.append("")

    # ===== Findings — rules already evaluated above (triage pulled to the top banner) =====
    out.append("## Findings (rules fired)")
    out.append("")
    if n_fired_total == 0:
        out.append("_No findings rules fired against this capture._")
        out.append("")
    else:
        out.append(f"**{n_fired_total} rule(s) fired** out of {len(rules)} evaluated"
                   + (" (the Engagement Triage banner is shown at the top)." if triage is not None else "."))
        out.append("")
        # Sort by severity then name
        sev_order = {"CRITICAL": 0, "MAJOR": 1, "MINOR": 2, "INFO": 3}
        fired_sorted = sorted(fired, key=lambda f: (sev_order.get(f.severity, 9),
                                                     f.name))
        for f in fired_sorted:
            marker = SEVERITY_MARKER.get(f.severity, "")
            out.append(f"### {marker} {f.severity} — {f.name}")
            out.append("")
            if f.description:
                out.append(f"_{f.description}_")
                out.append("")
            if f.conclusion:
                out.append(f"**Conclusion:** {f.conclusion}")
                out.append("")
            if f.offensive_implications:
                out.append("**Offensive implications:**")
                out.append("")
                for item in f.offensive_implications:
                    out.append(f"- {item}")
                out.append("")
            out.append("")

    if failed_rules:
        out.append("### Rule evaluation errors")
        out.append("")
        out.append("These rules raised exceptions during evaluation — likely a bug "
                   "in the rule code or a missing field in the capture:")
        out.append("")
        for name, exc in failed_rules:
            out.append(f"- `{name}`: {exc}")
        out.append("")

    out.append("---")
    out.append("")

    # ===== CoreSight per-AP capture =====
    coresight = captured.get("coresight", {})
    ap_info = coresight.get("ap_info", {}) if isinstance(coresight, dict) else {}
    if ap_info:
        out.append("## CoreSight DAP topology")
        out.append("")
        out.append("Raw output of OpenOCD's `dap info N` for each Access Port. Each entry")
        out.append("walks the ROM table and identifies every CoreSight component (ETM, ETB,")
        out.append("CTI, ITM, DWT, etc.) by Component Class + Peripheral ID. Per UG1085 §39:")
        out.append("AP0 = APU-DAP, AP1 = APB-AP, AP2 = AHB-AP (RPU), AP3 = JTAG-AP.")
        out.append("")
        out.append("An AP that returns `ERR` or empty output is either not present on this")
        out.append("variant or is gated by JTAG security state (CSU.JTAG_DAP_CFG).")
        out.append("")
        for ap_num in sorted(ap_info.keys(), key=lambda k: int(k)):
            text = ap_info[ap_num]
            out.append(f"### AP {ap_num}")
            out.append("")
            out.append("```")
            out.append(text if text else "(empty)")
            out.append("```")
            out.append("")
        out.append("---")
        out.append("")

    # ===== Per-register raw + annotation =====
    out.append("## Captured registers — raw values + annotated meanings")
    out.append("")
    out.append("Every register the script read appears here, grouped by SoC block. Each")
    out.append("register's heading shows its address, name, and raw value. Below it, each")
    out.append("bit-field gets its own line: name, bit range, value, then an indented")
    out.append("interpretation when a curated annotation exists.")
    out.append("")

    by_block: dict[str, list] = {}
    for addr, reg in captured.get("registers", {}).items():
        block = reg.get("block", "UNKNOWN")
        by_block.setdefault(block, []).append((addr, reg))

    # `bits` can come back from JSON as int (single-bit fields like 0, 5) or
    # str (multi-bit like "31:28"). Normalize for sorting.
    def _msb_of(fdata):
        bits = fdata.get("bits", "0")
        if isinstance(bits, int):
            return bits
        if ":" in bits:
            return int(bits.split(":")[0])
        return int(bits)

    for block in sorted(by_block.keys()):
        out.append(f"### Block: `{block}`")
        out.append("")
        for addr, reg in sorted(by_block[block], key=lambda x: int(x[0], 16)):
            name = reg.get("name", "?")
            value = reg.get("value", "?")
            out.append(f"#### `{addr}` — `{block}.{name}` = `{value}`")
            out.append("")
            fields = reg.get("fields", {})

            # Register-level annotation (for fieldless registers OR as a
            # short header even when fields exist).
            reg_ann = find_register_annotation(reg_index, block, name)
            if reg_ann is not None:
                out.append(f"_{reg_ann.description}_")
                if reg_ann.interpret is not None:
                    vi = _value_to_int(reg.get("value_int", value))
                    if vi is not None:
                        try:
                            derived = reg_ann.interpret(vi)
                        except Exception as exc:
                            derived = f"(interpret() raised {exc!r})"
                        if derived:
                            out.append("")
                            out.append(f"**Derived:** {derived}")
                out.append("")

            if not fields:
                if reg_ann is None:
                    out.append("_(register has no QEMU bit-field decode and no register-level annotation; raw value above)_")
                    out.append("")
                continue

            sorted_fields = sorted(fields.items(), key=lambda x: -_msb_of(x[1]))
            for fname, fdata in sorted_fields:
                bits = fdata.get("bits", "?")
                fval = fdata.get("value", "?")
                ann = find_annotation(ann_index, block, name, fname)
                matched = None
                if ann is not None:
                    matched = ann.values.get(fval)
                    if matched is None and isinstance(fval, int):
                        matched = ann.values.get(str(fval))
                    if matched is None and isinstance(fval, str):
                        fv_int = _value_to_int(fval)
                        if fv_int is not None:
                            matched = ann.values.get(fv_int)

                head = f"- `{fname}` [bits {bits}] = `{fval}`"

                if full:
                    # Original verbose layout
                    out.append(head)
                    if ann is None:
                        out.append("")
                        continue
                    if matched:
                        label = matched.get("label", "")
                        m_meaning = matched.get("meaning", "")
                        offensive = matched.get("offensive_use", "")
                        if label:
                            out.append(f"    - **{label}** — {m_meaning}" if m_meaning
                                       else f"    - **{label}**")
                        elif m_meaning:
                            out.append(f"    - {m_meaning}")
                        if offensive:
                            out.append(f"    - _Offensive use:_ {offensive}")
                    elif not ann.values:
                        out.append(f"    - _{ann.description}_")
                    else:
                        out.append(f"    - _{ann.description}_ (no value-specific entry for `{fval}`)")
                    out.append("")
                    continue

                # Compact layout — pack annotation onto the same line.
                # Format: `- FIELD [bits N:M] = value — **Label** — meaning  _(offensive)_`
                tail_parts: list[str] = []
                if ann is not None:
                    if matched:
                        label = matched.get("label", "")
                        m_meaning = matched.get("meaning", "")
                        offensive = matched.get("offensive_use", "")
                        if label:
                            tail_parts.append(f"**{label}**")
                        if m_meaning:
                            tail_parts.append(m_meaning)
                        if offensive:
                            tail_parts.append(f"_Offensive:_ {offensive}")
                    elif not ann.values:
                        tail_parts.append(f"_{ann.description}_")
                    else:
                        tail_parts.append(f"_{ann.description}_ (no value-specific entry for `{fval}`)")

                if tail_parts:
                    out.append(f"{head} — " + " — ".join(tail_parts))
                else:
                    out.append(head)

            # Compact: one blank line between registers. Full mode already
            # appends blanks per-field.
            if not full:
                out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("raw_json", type=Path,
                    help="Path to reports/raw-<timestamp>.json")
    ap.add_argument("--annotations-dir", type=Path, default=ANNOTATIONS_DIR,
                    help=f"Annotations directory (loads every zynqmp_*.py). Default: {ANNOTATIONS_DIR}")
    ap.add_argument("--rules", type=Path, default=RULES_MODULE,
                    help=f"Findings rules module (default: {RULES_MODULE})")
    ap.add_argument("-o", "--output", type=Path, default=None,
                    help="Output markdown path (default: stdout)")
    ap.add_argument("-O", "--auto-output", action="store_true",
                    help="Auto-name output as reports/interpreted-<ts>.md")
    ap.add_argument("--full", action="store_true",
                    help="Verbose layout (sub-bulleted labels/meanings/offensive on separate lines, "
                         "blank between every field). Default is compact one-line-per-field.")
    args = ap.parse_args()

    if not args.raw_json.exists():
        print(f"ERROR: raw JSON not found: {args.raw_json}", file=sys.stderr)
        return 1

    captured = load_json(args.raw_json)
    annotations, reg_annotations = load_annotations(args.annotations_dir)
    rules = load_rules(args.rules)

    print(
        f"interpret.py: {len(captured.get('registers', {}))} registers, "
        f"{len(annotations)} field annotations, "
        f"{len(reg_annotations)} register annotations, "
        f"{len(rules)} rules loaded",
        file=sys.stderr,
    )

    md = render_markdown(captured, annotations, reg_annotations, rules,
                          args.raw_json, full=args.full)

    if args.auto_output:
        stem = args.raw_json.stem.replace("raw-", "interpreted-")
        out_path = args.raw_json.parent / f"{stem}.md"
        out_path.write_text(md)
        print(f"Wrote: {out_path}", file=sys.stderr)
    elif args.output:
        args.output.write_text(md)
        print(f"Wrote: {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(md)

    return 0


if __name__ == "__main__":
    sys.exit(main())
