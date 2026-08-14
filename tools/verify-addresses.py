#!/usr/bin/env python3
"""
verify-addresses.py — register-address consistency checker

Single source of truth: openocd/lib/zynqmp-regs-qemu.tcl. That file is
generated from Xilinx's QEMU register model. Every register-name → address
mapping in code, scripts, payloads, and docs must agree with it.

This validator parses the QEMU regs file, builds a canonical {name: address}
map, then scans the rest of the repo for register references and flags
mismatches.

Why this exists: in 2026-05-28 audit C1, we discovered JTAG_SEC and
JTAG_DAP_CFG addresses had been swapped throughout the project for weeks.
The bug propagated through ~10 files and cost multiple debug sessions of
confused conclusions. A swap like this is silent — chip reads succeed,
empirical data looks plausible, but interpretation is reversed. This tool
catches that class of bug before it ships.

Exit codes:
  0  — all addresses consistent
  1  — at least one mismatch (details printed)
  2  — internal error (canonical source unparseable)

Usage:
  tools/verify-addresses.py                  # validate everything
  tools/verify-addresses.py --reg JTAG_SEC   # only check one register
  tools/verify-addresses.py --quiet          # only print mismatches (good for CI)
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
QEMU_REGS_FILE = REPO_ROOT / "openocd" / "lib" / "zynqmp-regs-qemu.tcl"
EXTENSION_REGS_FILE = REPO_ROOT / "openocd" / "lib" / "zynqmp-regs-extension.tcl"

# Files to scan for register-name → address references.
# Globs are relative to REPO_ROOT.
SCAN_GLOBS = [
    "openocd/*.tcl",
    "openocd/lib/*.tcl",
    "payloads/*.S",
    "tools/*.sh",
    "tools/*.py",
    "tools/*.tcl",
    "docs/**/*.md",
    "*.md",
]

# Exclude the canonical source from "scan" — it IS the source of truth.
EXCLUDE = {
    "openocd/lib/zynqmp-regs-qemu.tcl",
    "openocd/lib/zynqmp-regs-extension.tcl",  # also a canonical layer
}


# Some files contain HISTORICAL annotations describing the old wrong addresses.
# We want those to remain readable but not trigger false positives. Look for an
# OPT-OUT marker: any line containing the literal string `verify-addresses:skip`
# is excluded from validation.
OPT_OUT_MARKER = "verify-addresses:skip"


def parse_qemu_regs(path: Path) -> Dict[str, int]:
    """
    Parse `dict set ::QEMU_REGS <decimal> [dict create name <NAME> ...`
    Returns {register_name: address}.

    The QEMU file uses decimal addresses. We normalize to int.
    """
    if not path.exists():
        print(f"ERROR: canonical source not found at {path}", file=sys.stderr)
        sys.exit(2)

    canonical: Dict[str, int] = {}
    # Match BOTH forms:
    #   dict set ::QEMU_REGS 4291444736 [dict create \      (raw decimal)
    #   dict set ::QEMU_REGS [expr {int(0xFFCA4000)}] [dict create \  (expr form for extensions)
    pattern = re.compile(
        r"dict\s+set\s+::QEMU_REGS\s+"
        r"(?:(\d+)|\[expr\s*\{int\(\s*(0x[0-9A-Fa-f]+)\s*\)\}\])\s+"
        r"\[dict\s+create\s*\\?\s*\n\s*name\s+(\w+)\s+\\",
        re.MULTILINE,
    )
    text = path.read_text()
    for match in pattern.finditer(text):
        if match.group(1):
            addr = int(match.group(1))
        else:
            addr = int(match.group(2), 16)
        name = match.group(3)
        # The QEMU file has multiple register blocks; some register names
        # repeat across blocks (e.g., MULTI_BOOT exists in CSU and CRL).
        # We index by name alone, but track collisions to warn.
        if name in canonical and canonical[name] != addr:
            # Multiple registers with same short name at different addresses.
            # Record under a qualified key.
            block_match = re.search(
                r"name\s+" + re.escape(name) + r".*?block\s+(\w+)",
                match.group(0) + text[match.end() : match.end() + 200],
                re.DOTALL,
            )
            block = block_match.group(1) if block_match else "UNKNOWN"
            canonical[f"{block}.{name}"] = addr
        else:
            canonical[name] = addr
    return canonical


def hex_to_int(s: str) -> int:
    """Parse '0xFFCA0038' or '0xffca0038' or 'FFCA0038' → int."""
    s = s.strip()
    if s.lower().startswith("0x"):
        return int(s, 16)
    return int(s, 16)


# Patterns to find register-name → address references in source files.
# We look for the address (literal) appearing near the register name within
# a small window of characters. This is heuristic but catches the common
# patterns:
#   set ::REG_CSU_JTAG_SEC  0xFFCA0038
#   .equ REG_JTAG_SEC,      0xFFCA0038
#   {0xFFCA0038 jtag_sec}
#   `CSU.JTAG_SEC` at `0xFFCA0038`
#   | CSU_JTAG_SEC | 0xFFCA0038 |
#   "CSU_JTAG_SEC (0xFFCA0038)"
#   set ::REG_CSU_JTAG_SEC 0xFFCA0038   ;# comment
#
# The pattern is: a register name (subset of UPPER_SNAKE matching QEMU)
# within 80 characters of a hex address. Direction does not matter
# (address before or after the name).

# Build a list of names we recognize — only check names that appear in QEMU.
# Avoids false-positives on unrelated UPPER_SNAKE words.


def find_addr_refs(text: str, known_names: List[str]) -> List[Tuple[str, int, int]]:
    """
    For each line, look for (name, address) co-occurrences within a single line.
    Returns list of (name, address_int, line_number).

    We require name + address on the SAME LINE within 80 chars of each other —
    that captures the common patterns and avoids cross-paragraph false matches.

    Names are matched against `known_names` (a list of register names from
    QEMU). Match against either the canonical name or `CSU_<name>` /
    `<block>_<name>` (CSU register names often appear as CSU_JTAG_SEC).
    """
    refs = []
    # Filter out names too generic to use as standalone match keys.
    # STATUS / CTRL / CFG / ISR / IER / RPU / APU / etc. appear in many
    # contexts where the nearby hex address is for a DIFFERENT register.
    # Heuristic: only check names that are (a) ≥ 7 chars, OR (b) contain
    # at least one underscore. That filters generic short words but keeps
    # JTAG_SEC, ROM_DIGEST_0, SHA_DIGEST_0, PCAP_PROG, etc.
    distinctive = [
        n for n in known_names if "_" in n or len(n) >= 7
    ]
    name_set = set(distinctive)
    name_pattern = "|".join(
        sorted({re.escape(n) for n in distinctive}, key=len, reverse=True)
    )
    addr_pattern = r"0x[Ff][Ff][CcDdEe][A-Fa-f0-9]{5}"  # ZynqMP MMIO range
    # Full pattern: capture name and address in either order on a line.
    line_pattern = re.compile(
        rf"({addr_pattern})(?:[^\n]{{0,80}}?)({name_pattern})\b"
        rf"|"
        rf"\b({name_pattern})\b(?:[^\n]{{0,80}}?)({addr_pattern})",
        re.IGNORECASE,
    )

    # Range-expression detector: addresses surrounded by ` - ` or `..`
    # are obviously range bounds, not register references. Skip them.
    range_pattern = re.compile(
        r"(0x[Ff][Ff][CcDdEe][A-Fa-f0-9]{5})\s*(?:-|\.\.|–|—)\s*(0x[Ff][Ff][CcDdEe][A-Fa-f0-9]{5})"
    )

    for lineno, line in enumerate(text.splitlines(), start=1):
        if OPT_OUT_MARKER in line:
            continue
        # Find range-bound addresses on this line — they're not register refs.
        range_bound_addrs = set()
        for rm in range_pattern.finditer(line):
            for g in rm.groups():
                if g:
                    range_bound_addrs.add(g.lower())
        for m in line_pattern.finditer(line):
            addr_str = m.group(1) or m.group(4)
            if addr_str.lower() in range_bound_addrs:
                continue
            name = (m.group(2) or m.group(3)).upper()
            # Strip CSU_ / csu_ prefix to canonical form
            canonical_name = name
            for prefix in ("CSU_", "EFUSE_", "BBRAM_", "CRL_", "CRF_", "IOU_", "LPD_"):
                if canonical_name.startswith(prefix):
                    stripped = canonical_name[len(prefix):]
                    if stripped in name_set:
                        canonical_name = stripped
                        break
            if canonical_name in name_set:
                try:
                    addr = hex_to_int(addr_str)
                    refs.append((canonical_name, addr, lineno))
                except ValueError:
                    pass
    return refs


def iter_repo_files() -> List[Path]:
    files: List[Path] = []
    for pat in SCAN_GLOBS:
        files.extend(REPO_ROOT.glob(pat))
    # Filter exclusions and de-dupe.
    seen = set()
    result = []
    for f in files:
        rel = f.relative_to(REPO_ROOT).as_posix()
        if rel in EXCLUDE:
            continue
        if rel in seen:
            continue
        seen.add(rel)
        result.append(f)
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--reg", help="Only check this register name", default=None)
    parser.add_argument(
        "--quiet", action="store_true", help="Only print mismatches"
    )
    parser.add_argument(
        "--list", action="store_true", help="Print canonical map then exit"
    )
    args = parser.parse_args()

    canonical = parse_qemu_regs(QEMU_REGS_FILE)
    # Merge in hand-verified extensions (PUF, CSU_TAMPER_14, etc.)
    if EXTENSION_REGS_FILE.exists():
        extension = parse_qemu_regs(EXTENSION_REGS_FILE)
        canonical.update(extension)
    if not canonical:
        print("ERROR: parsed zero registers from canonical source", file=sys.stderr)
        sys.exit(2)

    if args.list:
        for name in sorted(canonical.keys()):
            print(f"  {name:<32s}  0x{canonical[name]:08X}")
        sys.exit(0)

    if args.reg and args.reg not in canonical:
        print(f"ERROR: register '{args.reg}' not in canonical source", file=sys.stderr)
        sys.exit(2)

    known_names = list(canonical.keys())
    mismatches: List[Tuple[Path, int, str, int, int]] = []  # (file, line, name, found, expected)
    checked = 0

    for fpath in iter_repo_files():
        try:
            text = fpath.read_text(errors="replace")
        except OSError:
            continue
        refs = find_addr_refs(text, known_names)
        for name, addr, lineno in refs:
            if args.reg and name != args.reg:
                continue
            expected = canonical.get(name)
            if expected is None:
                continue
            checked += 1
            if addr != expected:
                mismatches.append(
                    (fpath.relative_to(REPO_ROOT), lineno, name, addr, expected)
                )

    if not args.quiet:
        print(f"Canonical source: {QEMU_REGS_FILE.relative_to(REPO_ROOT)}")
        print(f"  {len(canonical)} register names indexed")
        print(f"Files scanned: {len(iter_repo_files())}")
        print(f"References checked: {checked}")
        print()

    if mismatches:
        print(f"FOUND {len(mismatches)} ADDRESS MISMATCH(ES):")
        for fpath, lineno, name, found, expected in mismatches:
            print(
                f"  {fpath}:{lineno}  {name}  found 0x{found:08X}  expected 0x{expected:08X}"
            )
        print()
        print(
            "Fix: change the address to match canonical, OR if the file is "
            "intentionally documenting a historical wrong value, add the marker "
            f"'{OPT_OUT_MARKER}' on that line to suppress this check."
        )
        sys.exit(1)

    if not args.quiet:
        print("OK — all register addresses match canonical source.")
    sys.exit(0)


if __name__ == "__main__":
    main()
