#!/usr/bin/env python3
"""
mock-xsdb.py — a high-fidelity stand-in for AMD's `xsdb` (Xilinx System Debugger), so the whole
hw_server / SmartLynq2 transport path can be REHEARSED offline before the bench (G3), exactly the
way openocd/lib/mock-openocd.tcl stands in for OpenOCD.

It emulates `xsdb -eval "<tcl>"` for the command subset the transport layer emits
(jtagx/transport/xsdb.py): connect / targets / targets -set -filter / stop / con / mrd / mwr.
Output is formatted to match real xsdb closely enough to validate our `targets` PARSER and the
mem-read/dump flow. Point the transport at it with:

    JTAGX_XSDB=tools/mock-xsdb.py python3 tools/transport-probe.py --profile zynqmp --backend hw_server ...
    JTAGX_XSDB=$PWD/tools/mock-xsdb.py  (in the GUI) → Dump DDR under Transport=hw_server actually runs

Fidelity notes / honest limits:
  * The target tree is the canonical ZynqMP reference (jtagx.transport.targets.ZYNQMP_TARGETS_REF),
    rendered in real xsdb indentation with a leading '*' on the selected target.
  * `mrd -bin -file` writes a DETERMINISTIC pattern (addr-derived), capped at $JTAGX_MOCK_MAXBYTES
    (default 2 MiB) so rehearsals stay fast — a banner marks the truncation. Real xsdb writes the
    full range; the point here is to exercise the plumbing, not to fake silicon contents.
  * A few known registers return their real ZCU102 values (IDCODE 0xFFCA0040 → 0x24738093, etc.)
    so the `mrd <reg>` cross-check in the checklist behaves like the board.
This is a REHEARSAL tool; the REAL validation is G3 against actual hw_server output.
"""
import fnmatch
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jtagx.transport.targets import zynqmp_reference, flatten, ZYNQMP_TARGETS_REF
from mock_common import load_regs, reg_word, mem_bytes

MAXBYTES = int(os.environ.get("JTAGX_MOCK_MAXBYTES", str(2 * 1024 * 1024)))
REGS = load_regs()          # the newest capture's 153 real registers (faithful mrd)


class Session:
    def __init__(self):
        self.roots = zynqmp_reference()
        self.nodes = list(flatten(self.roots))
        self.selected = None          # tid of the selected target

    # ---- targets ----
    def render_tree(self):
        """Render the reference tree in xsdb format, '*' on the selected target."""
        out = []
        for ln in ZYNQMP_TARGETS_REF.splitlines():
            m = re.match(r"^(\s*)(\d+)\s+(.*)$", ln)
            if not m:
                continue
            indent, tid, rest = m.group(1), int(m.group(2)), m.group(3)
            mark = "*" if tid == self.selected else " "
            out.append(f"{indent}{mark}{tid:>2}  {rest}")
        return "\n".join(out)

    def select_by_filter(self, expr):
        # supports `name =~ "glob"` possibly OR-joined with `||`
        globs = re.findall(r'name\s*=~\s*"([^"]+)"', expr)
        for n in self.nodes:
            if any(fnmatch.fnmatch(n.name, g) for g in globs):
                self.selected = n.tid
                return n
        return None

    def select_by_id(self, tid):
        for n in self.nodes:
            if n.tid == tid:
                self.selected = tid
                return n
        return None

    def sel_name(self):
        for n in self.nodes:
            if n.tid == self.selected:
                return n.name
        return "(none)"


def cmd_mrd(sess, args, out):
    # forms: mrd <addr> [n]  |  mrd -bin -file <path> <addr> <n>
    if "-bin" in args:
        i = args.index("-file")
        path = args[i + 1]
        rest = [a for a in args[i + 2:]]
        addr = int(rest[0], 16) if rest else 0
        nwords = int(rest[1], 16) if len(rest) > 1 and rest[1].lower().startswith("0x") else \
                 (int(rest[1]) if len(rest) > 1 else 1)
        want = nwords * 4
        n = min(want, MAXBYTES)
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "wb") as f:
            f.write(mem_bytes(REGS, addr, n))
        if n < want:
            out.append(f"# [mock-xsdb] wrote {n} of {want} bytes to {path} "
                       f"(capped by JTAGX_MOCK_MAXBYTES={MAXBYTES}); real xsdb writes the full range")
        else:
            out.append(f"# [mock-xsdb] wrote {n} bytes to {path}")
        return
    # text form — real captured values where known
    addr = int(args[0], 16) if args else 0
    nwords = int(args[1]) if len(args) > 1 else 1
    for k in range(nwords):
        a = addr + 4 * k
        out.append(f"{a:X}:   {reg_word(REGS, a):08X}")


def run_script(script, out):
    sess = Session()
    # split on ; and newlines, honoring nothing fancy (the transport emits simple `;`-joined tcl)
    parts = re.split(r";|\n", script)
    for raw in parts:
        c = raw.strip()
        if not c:
            continue
        toks = c.split()
        head = toks[0]
        if head == "connect":
            out.append("tcfchan#0")                      # xsdb returns the channel id
        elif head == "targets":
            if "-set" in toks:
                m = re.search(r"-filter\s*\{(.+?)\}", c)
                if m:
                    n = sess.select_by_filter(m.group(1))
                    if n is None:
                        out.append(f'no targets found with "{m.group(1)}"')
                elif len(toks) >= 2 and toks[1].isdigit():
                    sess.select_by_id(int(toks[1]))
            elif len(toks) >= 2 and toks[1].isdigit():   # `targets <id>` (select)
                sess.select_by_id(int(toks[1]))
            else:
                out.append(sess.render_tree())           # `targets` → the tree
        elif head == "stop":
            out.append(f"# [mock-xsdb] {sess.sel_name()} stopped")
        elif head == "con":
            out.append(f"# [mock-xsdb] {sess.sel_name()} running")
        elif head == "mrd":
            cmd_mrd(sess, toks[1:], out)
        elif head == "mwr":
            out.append(f"# [mock-xsdb] wrote {toks[2] if len(toks) > 2 else '?'} @ {toks[1] if len(toks) > 1 else '?'}")
        else:
            out.append(f"# [mock-xsdb] (ignored) {c}")


def main():
    argv = sys.argv[1:]
    script = ""
    if "-eval" in argv:
        script = argv[argv.index("-eval") + 1]
    elif argv and os.path.isfile(argv[-1]):
        script = open(argv[-1]).read()
    else:
        script = sys.stdin.read()
    out = []
    run_script(script, out)
    print("\n".join(out))


if __name__ == "__main__":
    main()
