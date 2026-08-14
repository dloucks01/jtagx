"""
jtagx.bsdl — BSDL parser + boundary-scan planner/decoder core.

Moved here (from tools/bsdl-scan.py) so the CLI and any GUI/consumer share it. Parses a .bsdl
(IR length, instruction opcodes, IDCODE, boundary length, boundary-register cells), plans a SAMPLE
capture, and decodes a captured boundary register into per-pin states — the Phase-2b boundary-scan
alt-path for a DAP-gated part.
"""
import re

INPUT_FUNCS = {"input", "bidir", "observe_only", "clock"}   # cells whose captured value = a pin reading


def strip_comments(text):
    return "\n".join(re.sub(r"--.*$", "", ln) for ln in text.splitlines())


def join_quoted(s):
    """Concatenate the contents of all "..." pieces (BSDL attributes are quoted strings joined by &)."""
    return "".join(re.findall(r'"([^"]*)"', s))


def attr_raw(text, name):
    m = re.search(rf"attribute\s+{name}\s+of\s+\w+\s*:\s*entity\s+is\s*(.*?);", text,
                  re.IGNORECASE | re.DOTALL)
    return m.group(1) if m else None


def parse_bsdl(text):
    t = strip_comments(text)
    d = {}
    m = re.search(r"\bentity\s+(\w+)\s+is", t, re.IGNORECASE)
    d["entity"] = m.group(1) if m else "?"
    ir = attr_raw(t, "INSTRUCTION_LENGTH")
    d["ir_length"] = int(re.search(r"\d+", ir).group()) if ir else None
    # opcodes: NAME (bits)
    opc = join_quoted(attr_raw(t, "INSTRUCTION_OPCODE") or "")
    d["opcodes"] = {n.upper(): b for n, b in re.findall(r"(\w+)\s*\(([01]+)\)", opc)}
    # idcode: concatenated binary (may contain X)
    idc = join_quoted(attr_raw(t, "IDCODE_REGISTER") or "").replace(" ", "")
    d["idcode_bits"] = idc or None
    d["idcode"] = (f"0x{int(idc, 2):08X}" if idc and set(idc) <= set("01") else (idc or None))
    bl = attr_raw(t, "BOUNDARY_LENGTH")
    d["boundary_length"] = int(re.search(r"\d+", bl).group()) if bl else None
    # boundary cells: NUM (celltype, port, function, safe[, ...])
    br = join_quoted(attr_raw(t, "BOUNDARY_REGISTER") or "")
    cells = []
    for num, inner in re.findall(r"(\d+)\s*\(([^)]*)\)", br):
        parts = [p.strip() for p in inner.split(",")]
        cells.append(dict(num=int(num), celltype=parts[0] if parts else "",
                          port=parts[1] if len(parts) > 1 else "*",
                          function=(parts[2].lower() if len(parts) > 2 else ""),
                          safe=parts[3] if len(parts) > 3 else ""))
    d["cells"] = sorted(cells, key=lambda c: c["num"])
    return d


def summary(d):
    L = [f"BSDL: {d['entity']}"]
    L.append(f"  IDCODE          : {d['idcode']}")
    L.append(f"  IR length       : {d['ir_length']}")
    L.append(f"  opcodes         : " + ", ".join(f"{k}={v}" for k, v in d["opcodes"].items()))
    L.append(f"  boundary length : {d['boundary_length']}  ({len(d['cells'])} cells)")
    funcs = {}
    for c in d["cells"]:
        funcs[c["function"]] = funcs.get(c["function"], 0) + 1
    L.append("  cell functions  : " + ", ".join(f"{k}×{v}" for k, v in sorted(funcs.items())))
    readable = [c["port"] for c in d["cells"] if c["function"] in INPUT_FUNCS and c["port"] != "*"]
    L.append(f"  readable pins   : {', '.join(sorted(set(readable))) or '(none)'}")
    if "SAMPLE" not in d["opcodes"]:
        L.append("  ! no SAMPLE opcode found — boundary read may not be possible")
    return "\n".join(L)


def sample_plan(d, tap="tap0"):
    op = d["opcodes"].get("SAMPLE") or d["opcodes"].get("PRELOAD")
    if not op or not d["boundary_length"]:
        return "(no SAMPLE opcode / boundary length — cannot plan a capture)"
    ophex = f"0x{int(op, 2):X}"
    n = d["boundary_length"]
    return (
        f"# SAMPLE capture plan for {d['entity']} (boundary length {n} bits)\n"
        f"#   Even with the debug DAP gated, this reads the live pin states via boundary scan.\n"
        f"#   Replace '{tap}' with your chain's TAP name; needs the part in the JTAG chain.\n"
        f"# OpenOCD:\n"
        f"    irscan {tap} {ophex}                 ;# load SAMPLE (IR={d['ir_length']} bits)\n"
        f"    set cap [drscan {tap} {n} 0]          ;# capture the {n}-bit boundary register\n"
        f"    echo \"boundary = 0x$cap\"\n"
        f"# then decode:  python3 tools/bsdl-scan.py <this.bsdl> --decode 0x$cap\n"
        f"# UrJTAG:  instruction SAMPLE ; shift ir ; shift dr ; dr    (then feed the hex to --decode)"
    )


def decode(d, value):
    n = d["boundary_length"] or 0
    L = [f"decoding boundary register 0x{value:0{(n + 3) // 4}X} ({n} bits) for {d['entity']}:"]
    any_pin = False
    for c in d["cells"]:
        if c["function"] in INPUT_FUNCS and c["port"] != "*":
            bit = (value >> c["num"]) & 1
            L.append(f"  cell {c['num']:>3}  {c['port']:<10} {c['function']:<8} = {bit}")
            any_pin = True
    if not any_pin:
        L.append("  (no readable input/bidir cells)")
    return "\n".join(L)


def pin_lookup(d, name):
    hits = [c for c in d["cells"] if c["port"].upper() == name.upper()]
    if not hits:
        return f"pin '{name}' not found in the boundary register"
    L = [f"pin '{name}':"]
    for c in hits:
        L.append(f"  boundary bit {c['num']}  ({c['function']}, cell {c['celltype']}, safe={c['safe']})")
    return "\n".join(L)
