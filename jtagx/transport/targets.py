#!/usr/bin/env python3
"""
jtagx.transport.targets — the xsdb / hw_server debug-target tree.

`xsdb targets` prints a *tree* of debug targets, not a flat core list. On ZynqMP it looks like:

      1  PS TAP
         2  PMU
         3  PL
      4  PSU
         5  RPU
            6  Cortex-R5 #0 (Lock Step Mode)
            7  Cortex-R5 #1 (Lock Step Mode)
         8  APU
            9  Cortex-A53 #0 (Running)
           10  Cortex-A53 #1 (Power On Reset)
           ...

The leading integer is the target id you pass to `targets <id>`; indentation is tree depth; a
trailing "(State)" is the run state. To read A53 core 0's memory you must select target 9 (or a
`-filter` that resolves to it) BEFORE `mrd`. This module parses that output into a structured tree,
classifies each node's role, and resolves a friendly selector ("a53-0", "rpu", "pmu") into the xsdb
target selector — completing the xsdb backend so it can drive the *right* core, not a hardcoded one.

Pure/offline: parse_targets() takes text (live `targets` output OR the reference tree below), so it
is testable without hw_server installed.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field


@dataclass
class TargetNode:
    tid: int                       # xsdb target id (what `targets <id>` takes)
    name: str
    state: str = ""                # e.g. "Running", "Power On Reset", "Halted"
    level: int = 0                 # tree depth (from indentation)
    role: str = "?"                # a53 / r5 / pmu / pl / psu / apu / rpu / tap / ?
    index: int = None             # core index (#0..#3) when present
    children: list = field(default_factory=list)

    def flat(self):
        yield self
        for c in self.children:
            yield from c.flat()


# name-substring -> role (checked in order; first match wins)
_ROLE_RULES = [
    (r"cortex-?a53", "a53"),
    (r"cortex-?r5", "r5"),
    (r"\bapu\b", "apu"),
    (r"\brpu\b", "rpu"),
    (r"microblaze|\bpmu\b", "pmu"),
    (r"\bpl\b|fpga|programmable logic", "pl"),
    (r"\bpsu\b", "psu"),
    (r"ps tap|\bdap\b|debug|tap", "tap"),
]
_LINE = re.compile(r"^(?P<indent>\s*)\*?\s*(?P<id>\d+)\s+(?P<rest>.+?)\s*$")
_STATE = re.compile(r"\(([^)]+)\)\s*$")
_IDX = re.compile(r"#\s*(\d+)")


def classify_role(name: str) -> str:
    n = name.lower()
    for pat, role in _ROLE_RULES:
        if re.search(pat, n):
            return role
    return "?"


def parse_targets(text: str):
    """Parse `xsdb targets` output into a list of root TargetNodes (a forest).

    Indentation determines nesting; a target with strictly greater indent than the previous is its
    child. Robust to the leading '*' xsdb marks on the currently-selected target.
    """
    roots = []
    stack = []   # (indent_len, node)
    for ln in text.splitlines():
        m = _LINE.match(ln)
        if not m:
            continue
        indent = len(m.group("indent").expandtabs(4))
        tid = int(m.group("id"))
        rest = m.group("rest")
        state = ""
        sm = _STATE.search(rest)
        if sm:
            state = sm.group(1).strip()
            rest = rest[:sm.start()].strip()
        name = rest.strip()
        idx = None
        im = _IDX.search(name)
        if im:
            idx = int(im.group(1))
        node = TargetNode(tid=tid, name=name, state=state, level=0,
                          role=classify_role(name), index=idx)
        # pop deeper-or-equal levels off the stack to find our parent
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if stack:
            parent = stack[-1][1]
            node.level = parent.level + 1
            parent.children.append(node)
        else:
            roots.append(node)
        stack.append((indent, node))
    return roots


def flatten(roots):
    for r in roots:
        yield from r.flat()


def find(roots, role=None, index=None):
    """First target matching role (and index, if given)."""
    for n in flatten(roots):
        if role and n.role != role:
            continue
        if index is not None and n.index != index:
            continue
        return n
    return None


def render(roots) -> str:
    """A compact text rendering of the tree (for CLI/GUI display)."""
    out = []
    for n in flatten(roots):
        pad = "  " * n.level
        st = f"  ({n.state})" if n.state else ""
        out.append(f"{pad}[{n.tid:>2}] {n.name}{st}   <{n.role}>")
    return "\n".join(out)


# --- role selector -> xsdb `targets -filter` expression -------------------------------
# friendly names the CLI/GUI/transport accept; resolve to an xsdb filter that hits exactly one core
ROLE_FILTERS = {
    "apu":   'name =~ "*A53*#0"',      # default APU core
    "a53":   'name =~ "*A53*#0"',
    "a53-0": 'name =~ "*A53*#0"', "a53-1": 'name =~ "*A53*#1"',
    "a53-2": 'name =~ "*A53*#2"', "a53-3": 'name =~ "*A53*#3"',
    "rpu":   'name =~ "*R5*#0"',       # default RPU core
    "r5":    'name =~ "*R5*#0"',
    "r5-0":  'name =~ "*R5*#0"', "r5-1": 'name =~ "*R5*#1"',
    "pmu":   'name =~ "*PMU*" || name =~ "MicroBlaze*"',
    "pl":    'name =~ "*PL*"',
    "psu":   'name =~ "*PSU*"',
}


def resolve_selector(sel) -> str:
    """Turn a friendly selector into an xsdb `targets ...` command.

    - int / numeric str  -> `targets <id>`  (a concrete id from a parsed tree)
    - a known role name  -> `targets -set -filter {<expr>}`
    - a raw filter expr (contains '=~') -> `targets -set -filter {<expr>}`
    - anything else -> a name-glob filter as a best effort
    """
    if isinstance(sel, int) or (isinstance(sel, str) and sel.strip().isdigit()):
        return f"targets {int(sel)}"
    s = str(sel).strip()
    if s.lower() in ROLE_FILTERS:
        return f'targets -set -filter {{{ROLE_FILTERS[s.lower()]}}}'
    if "=~" in s or "==" in s:
        return f"targets -set -filter {{{s}}}"
    return f'targets -set -filter {{name =~ "*{s}*"}}'


# --- reference ZynqMP tree (what a healthy ZCU102 enumerates), for offline/GUI use ---
ZYNQMP_TARGETS_REF = """\
  1  PS TAP
     2  PMU
     3  PL
  4  PSU
     5  RPU
        6  Cortex-R5 #0 (Lock Step Mode)
        7  Cortex-R5 #1 (Lock Step Mode)
     8  APU
        9  Cortex-A53 #0 (Running)
       10  Cortex-A53 #1 (Power On Reset)
       11  Cortex-A53 #2 (Power On Reset)
       12  Cortex-A53 #3 (Power On Reset)
"""


def zynqmp_reference():
    """The parsed reference ZynqMP debug-target tree (roots)."""
    return parse_targets(ZYNQMP_TARGETS_REF)
