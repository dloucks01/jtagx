#!/usr/bin/env python3
"""
mock-cortexm.py — a drop-in `openocd` mock for the Cortex-M path (SmartFusion2 MSS / generic ARM-M),
so the M3 eNVM/eSRAM extraction is rehearsable offline. Point $OPENOCD at it.

Emulates `openocd -f cortexm.cfg -c "init; halt; mdw/dump_image …; resume; shutdown"` and the
`source openocd/cortexm-dump.tcl` wrapper. eNVM/eSRAM content comes from the shared model (mock_common),
so a rehearsed dump carries a firmware banner + a decoy secret that dram-secrets/triage can find.

**The security gate** — $JTAGX_MOCK_LOCK controls the SmartFusion2 M3 debug lock:
  open (default)  → the M3 DAP answers → halt/mdw/dump succeed (extraction works, no FlashPro)
  debug-locked    → the security policy shut the M3 DAP → all access FAULTS (exit 1, no dump),
                    which is exactly when you fall back to FlashPro/DPA (see the unlock plan).
Dumps capped by $JTAGX_MOCK_MAXBYTES. REHEARSAL tool — real validation is a bench SmartFusion2 + J-Link.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_common import load_regs, reg_word, mem_bytes, region_of

MAXBYTES = int(os.environ.get("JTAGX_MOCK_MAXBYTES", str(2 * 1024 * 1024)))
LOCKED = os.environ.get("JTAGX_MOCK_LOCK", "open") == "debug-locked"
REGS = load_regs()
SF2_OUT = os.environ.get("SF2_OUT", "dumps/sf2-mem.bin")   # where `source cortexm-dump.tcl` writes


def _dap_fault(out):
    out.append("Error: Cortex-M debug access failed — DAP did not answer (security-locked?)")
    out.append("Error: could not halt the target")


def dump_to(out, path, addr, size):
    n = min(size, MAXBYTES)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(mem_bytes(REGS, addr, n))
    tag = region_of(addr)
    if n < size:
        out.append(f"# [mock-cortexm] dumped {n}/{size} B of {tag} @ {hex(addr)} to {path} "
                   f"(capped JTAGX_MOCK_MAXBYTES={MAXBYTES})")
    else:
        out.append(f"# [mock-cortexm] dumped {n} B of {tag} @ {hex(addr)} to {path}")


def run_c(out, body):
    for raw in re.split(r";|\n", body):
        c = raw.strip()
        if not c:
            continue
        toks = c.split()
        head = toks[0]
        if head in ("init", "shutdown", "reset"):
            continue
        if LOCKED and head in ("halt", "mdw", "dump_image", "mww", "resume", "reg", "source"):
            _dap_fault(out)
            return False               # abort the batch on a locked DAP
        if head == "halt":
            out.append("# [mock-cortexm] target halted (Cortex-M3)")
        elif head == "resume":
            out.append("# [mock-cortexm] resumed")
        elif head == "mdw":
            addr = int(toks[1], 16) if len(toks) > 1 else 0
            n = int(toks[2]) if len(toks) > 2 else 1
            vals = [reg_word(REGS, addr + 4 * k) for k in range(n)]
            for i in range(0, n, 4):
                out.append(f"0x{addr + 4 * i:08x}: " + " ".join(f"{v:08x}" for v in vals[i:i + 4]))
        elif head == "dump_image":
            dump_to(out, toks[1], int(toks[2], 16), int(toks[3], 0))
        elif head == "source":
            script = toks[1] if len(toks) > 1 else ""
            if "cortexm-dump.tcl" in script:
                dump_to(out, SF2_OUT, 0x60000000, 0x40000)   # eNVM (256 KiB)
            else:
                out.append(f"# [mock-cortexm] sourced {script} (no-op)")
        else:
            out.append(f"# [mock-cortexm] (ignored) {c}")
    return True


def main():
    argv = sys.argv[1:]
    out = []
    ok = True
    i = 0
    while i < len(argv):
        if argv[i] == "-c" and i + 1 < len(argv):
            ok = run_c(out, argv[i + 1])
            if not ok:
                break
            i += 2
        else:
            i += 1
    print("\n".join(out))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
