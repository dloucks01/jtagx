"""
cortexm_posture.py — parse the live text output of openocd/cortexm-protect.tcl into structured rows +
an OPEN/LOCKED/UNKNOWN verdict.

cortexm-protect.tcl is the Paradigm-B analog of enumerate.tcl (the ZynqMP §1-16 sweep): for a Cortex-M
board it reads identity + readout-protection registers and prints them via a fixed `_p` formatter
(`"   %-22s %s"` — 3-space indent, label left-padded to 22 chars, one space, value) under `" (N) TITLE"`
section headers. That text is otherwise thrown away once it scrolls past in the console; this module
turns it into the same kind of {label: value} rows the ZynqMP Registers tab renders, plus a verdict so
the Dashboard can show REAL measured posture for non-ZynqMP boards instead of only the synthetic
security-model (jtagx.unlock.security_model) "what this silicon type COULD present" view.

Read-only text parsing — no board interaction here.
"""
from __future__ import annotations

import re

_FAMILY_RX = re.compile(r"CORTEX-M SECURITY POSTURE\s+\(family:\s*(\S+)\)")
_SECTION_RX = re.compile(r"^\s\((\d+)\)\s+(.+?)\s*$")


def _split_row(line: str):
    """Split one _p-formatted line ("   %-22s %s") into (label, value), or None if it isn't one.

    The format guarantees: 3-space indent, then the label padded to a 22-char field (only if the label
    itself is under 22 chars — %-22s never truncates a longer label, it just prints it as-is), then ONE
    literal space, then the value. A regex that splits on "2+ spaces" works for the common (label < 22)
    case but breaks silently for the rare label >= 22 chars ("RDPRT (FLASH_OBR bit 1)" is 23 chars, a
    real row from the real script) — there the true gap is exactly one space, indistinguishable by
    space-counting alone from an internal space inside the label. Splitting on a fixed column instead of
    searching is what makes both cases unambiguous: column 22 (0-indexed, right after the 3-space
    indent) is the guaranteed literal separator whenever the label fit in its field; only when it
    DIDN'T do we fall back to a scan starting at that same column.
    """
    if not line.startswith("   ") or len(line) <= 3 or line[3] == " ":
        return None
    rest = line[3:]
    if len(rest) > 22 and rest[22] == " " and rest[:22].strip():
        label, value = rest[:22].strip(), rest[23:].strip()
    else:
        idx = rest.find(" ", 22)
        if idx == -1:
            return None
        label, value = rest[:idx].strip(), rest[idx + 1:].strip()
    return (label, value) if label and value else None

# Per family, the row LABEL that carries the protection verdict, and a regex on its VALUE that means
# "protection is engaged" (LOCKED). Absence of the label (e.g. a SANITY ABORT before it was reached) is
# UNKNOWN, not OPEN — we never default-assume open when we couldn't actually read the register.
_VERDICT_ROWS = {
    "RDP":                  re.compile(r"LEVEL [12]"),                       # stm32-rdp / stm32l4
    "RDP (FLASH_OPTR 7-0)":  re.compile(r"LEVEL [12]"),
    "RDPRT (FLASH_OBR bit 1)": re.compile(r"READ-PROTECTED"),                 # stm32f1
    "APPROTECT":             re.compile(r"ENABLED is the configured intent"), # nrf-approtect
    "PROT":                  re.compile(r"DEBUG-ACCESS PROTECTED"),           # sam-dsu
    "SEC (bits 1-0)":        re.compile(r"^0x\S+ -> SECURED"),                # kinetis-fsec
}
# families with no on-chip protection at all (the row exists but there is no lock to engage)
_ALWAYS_OPEN_FAMILIES = {"none"}   # rp2040: SYSINFO-only, no readout-protection fuse


def parse_cortexm_protect(text: str) -> dict:
    """Parse cortexm-protect.tcl's stdout. Returns:
        {"family": str|None, "sections": [{"title": str, "rows": [(label, value), ...]}],
         "verdict": "OPEN"|"LOCKED"|"UNKNOWN", "verdict_row": (label, value)|None,
         "aborted": str|None}   # the SANITY ABORT message, if the identity read failed
    An empty/unparseable capture returns family=None, sections=[], verdict="UNKNOWN".
    """
    family = None
    m = _FAMILY_RX.search(text)
    if m:
        family = m.group(1)

    sections: list[dict] = []
    cur = None
    aborted = None
    for line in text.splitlines():
        sm = _SECTION_RX.match(line)
        if sm:
            cur = {"title": sm.group(2), "rows": []}
            sections.append(cur)
            continue
        rm = _split_row(line)
        if rm and cur is not None:
            cur["rows"].append(rm)
            continue
        if "SANITY ABORT" in line:
            aborted = line.strip()

    all_rows = [r for s in sections for r in s["rows"]]
    verdict, verdict_row = "UNKNOWN", None
    if family in _ALWAYS_OPEN_FAMILIES and all_rows:
        verdict = "OPEN"
    else:
        for label, rx in _VERDICT_ROWS.items():
            hit = next((r for r in all_rows if r[0] == label), None)
            if hit is None:
                continue
            verdict_row = hit
            verdict = "LOCKED" if rx.search(hit[1]) else "OPEN"
            break

    return {"family": family, "sections": sections, "verdict": verdict,
            "verdict_row": verdict_row, "aborted": aborted}
