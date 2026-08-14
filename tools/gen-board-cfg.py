#!/usr/bin/env python3
"""gen-board-cfg.py — write a filled-in OpenOCD <board>.cfg for a new board.

WHAT THIS IS HONEST ABOUT (read docs/18 'bootstrap paradox'):
  A config cannot be auto-divined from JTAG discovery — discovery only runs once a config
  already works. So this generator codifies a KNOWN-GOOD first contact into a repeatable
  config; it does not guess unknowns. It determines:
    - the adapter interface cfg  (from host USB enumeration via lsusb, or --adapter)
    - the SoC family             (by decoding IDCODEs from a discover/access-check log)
  and it REFUSES to emit a ZynqMP target config if the IDCODE says the part isn't ZynqMP.
  It CANNOT determine (you must verify): I/O voltage / Vref / level-shifting, the JTAG
  pinout/connector, a stable clock speed, or the transport. These are printed as caveats.

TWO-PASS WORKFLOW:
  1. Loose first contact (operator supplies physical facts):
       JTAG_IFACE=openocd/adapters/ft2232h-generic.cfg JTAG_SPEED=300 \
         openocd -f openocd/board-template.cfg \
           -c "init; source openocd/jtag-access-check.tcl; shutdown" 2>&1 | tee firstcontact.log
  2. Generate a pinned config from that log:
       python3 tools/gen-board-cfg.py --name targetX --from-discovery firstcontact.log --speed 1000
     -> writes openocd/targetX.cfg  (+ a confidence report on stdout)

Run with no --from-discovery to generate purely from --adapter/--speed/--target.
"""
import argparse, os, re, subprocess, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Known JTAG adapters: (vid, pid) -> (label, interface_cfg, transport, note). interface_cfg is
# a stock OpenOCD path or one of openocd/adapters/*.cfg. Heuristic — FTDI VIDs are shared by
# clones, so a match is a SUGGESTION the operator confirms.
ADAPTER_DB = {
    (0x0403, 0x6010): ("FTDI FT2232H (generic / Olimex / clones)", "openocd/adapters/ft2232h-generic.cfg", "jtag",
                       "dual-channel; verify channel + pin layout for your wiring"),
    (0x0403, 0x6014): ("FTDI FT232H / Digilent SMT2-NC", "interface/ftdi/digilent_jtag_smt2_nc.cfg", "jtag",
                       "stock cfg assumes Digilent; for a bare FT232H use openocd/adapters/ft232h-generic.cfg"),
    (0x15ba, 0x002b): ("Olimex ARM-USB-OCD-H", "interface/ftdi/olimex-arm-usb-ocd-h.cfg", "jtag", ""),
    (0x1366, None):   ("SEGGER J-Link", "interface/jlink.cfg", "jtag", "many PIDs; matched on VID 0x1366"),
    (0x0d28, 0x0204): ("ARM CMSIS-DAP / mbed", "interface/cmsis-dap.cfg", "jtag", ""),
    (0x0483, 0x374b): ("ST-Link/V2-1", "interface/stlink.cfg", "hla_swd",
                       "SWD-oriented — NOT suitable for ZynqMP PS-JTAG; listed for completeness"),
}

# Match ONLY genuine device-report formats, so a register dump line that merely contains the
# substring "idcode" (e.g. enumerate's "CSU_IDCODE: 0xffca0040 = ...") can't inject a false hit.
DEV_IDCODE_RES = (
    re.compile(r"tap/device found:\s*0x([0-9a-fA-F]{8})", re.I),   # OpenOCD init
    re.compile(r"unexpected\s+idcode:?\s*0x([0-9a-fA-F]{8})", re.I),  # OpenOCD chain mismatch (actual device)
    re.compile(r"\bidcode\s+0x([0-9a-fA-F]{8})\b", re.I),          # discover.tcl describe_idcode output
)

# Minimal Xilinx part-ID classification (mirrors lib/idcode-lookup.tcl ranges). Exact ZynqMP die
# lives in lib/zynqmp-variants.tcl — here we only need family applicability.
ZYNQ7_PARTS = {0x3722, 0x3727, 0x372C, 0x372F, 0x3733}

# part-ID -> die slug, mirrored from lib/zynqmp-variants.tcl (the IDCODE fixes the die, not the
# EG/CG/EV package suffix — those share a die). Used to name the generated config after the SoC.
PART_DIE = {
    0x4711: "zu2", 0x4710: "zu3", 0x4721: "zu4", 0x4720: "zu5", 0x4739: "zu6", 0x4730: "zu7",
    0x4738: "zu9", 0x4740: "zu11", 0x4750: "zu15", 0x4759: "zu17", 0x4758: "zu19",
    0x4828: "zu21", 0x4829: "zu25", 0x4830: "zu27", 0x4831: "zu28", 0x4839: "zu29", 0x4838: "zu39",
    0x4840: "zu42", 0x4841: "zu43", 0x4848: "zu46", 0x4849: "zu47", 0x4850: "zu48", 0x4851: "zu49",
    0x4859: "zu65", 0x4858: "zu67",
}


def decode_idcode(idc):
    mfg = (idc >> 1) & 0x7FF
    part = (idc >> 12) & 0xFFFF
    rev = (idc >> 28) & 0xF
    if mfg == 0x23B:
        return ("arm", f"Arm CoreSight DAP (part 0x{part:04x})", "DAP behind a vendor PS-TAP")
    if mfg == 0x049:
        if part in ZYNQ7_PARTS:
            return ("zynq7", f"Zynq-7000 (part 0x{part:04x})", "UG585 — enumerate.tcl does NOT apply")
        if (part & 0xFF00) == 0x4A00:
            return ("versal", f"Versal (part 0x{part:04x})", "AM011 — different SoC; enumerate.tcl does NOT apply")
        return ("zynqmp", f"Xilinx ZynqMP/RFSoC (part 0x{part:04x}, rev {rev})",
                "verify exact die in lib/zynqmp-variants.tcl")
    return ("unknown", f"mfg 0x{mfg:03x} part 0x{part:04x}", "non-Xilinx — cross-ref JEP106")


def derive_name(idcodes):
    """SoC-derived config-name slug (e.g. 'zynqmp-zu9') from the first Xilinx IDCODE — skips the
    Arm DAP and non-Xilinx TAPs. Returns None if nothing decodes to a Xilinx device."""
    for idc in idcodes:
        if ((idc >> 1) & 0x7FF) != 0x049:   # not Xilinx (e.g. Arm DAP) — not a naming anchor
            continue
        part = (idc >> 12) & 0xFFFF
        fam = decode_idcode(idc)[0]
        slug = PART_DIE.get(part) or f"part{part:04x}"
        return f"{fam}-{slug}"
    return None


def detect_usb_adapters():
    """Return list of (vid,pid,label,iface,transport,note) for plugged adapters we recognize."""
    try:
        out = subprocess.check_output(["lsusb"], stderr=subprocess.DEVNULL).decode()
    except Exception:
        return []
    found = []
    for line in out.splitlines():
        m = re.search(r"ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})", line)
        if not m:
            continue
        vid, pid = int(m.group(1), 16), int(m.group(2), 16)
        key = (vid, pid) if (vid, pid) in ADAPTER_DB else (vid, None)
        if key in ADAPTER_DB:
            label, iface, transport, note = ADAPTER_DB[key]
            found.append((vid, pid, label, iface, transport, note))
    return found


def resolve_iface(iface):
    """If iface is a repo adapters/ path or absolute, return as-is. Else probe OpenOCD script dirs."""
    if os.path.isabs(iface) or iface.startswith("openocd/"):
        p = iface if os.path.isabs(iface) else os.path.join(ROOT, iface)
        return iface, os.path.exists(p)
    for base in ("/usr/share/openocd/scripts", "/usr/local/share/openocd/scripts"):
        if os.path.exists(os.path.join(base, iface)):
            return iface, True
    return iface, False  # may still be findable by OpenOCD's own [find]; flag as unverified


def parse_discovery(path):
    """Extract ACTUAL-device IDCODEs from an OpenOCD log. Keeps lines that report what's on the
    chain (`tap/device found`, `UNEXPECTED idcode`, discover.tcl's `IDCODE 0x...`); SKIPS the
    target cfg's wish-value lines (`expected ... 0x...`) so a mismatch doesn't get mis-identified
    as the SoC the cfg wanted."""
    idcodes = []
    try:
        text = open(path, errors="replace").read()
    except OSError as e:
        sys.exit(f"cannot read discovery log {path}: {e}")
    for line in text.splitlines():
        low = line.lower()
        if "expected" in low and "unexpected" not in low:
            continue  # cfg's expected-id wish, not a real device
        for rx in DEV_IDCODE_RES:
            m = rx.search(line)
            if m:
                v = int(m.group(1), 16)
                if v and v != 0xFFFFFFFF and v not in idcodes:
                    idcodes.append(v)
                break
    return idcodes


def main():
    ap = argparse.ArgumentParser(description="Generate a filled-in OpenOCD <board>.cfg.")
    ap.add_argument("--name", help="board name -> openocd/<name>.cfg. If omitted, derived from the "
                                   "detected SoC (e.g. zynqmp-zu9); auto-named configs overwrite freely.")
    ap.add_argument("--detect-adapter", action="store_true",
                    help="print the auto-detected adapter interface cfg and exit (for probe-board.sh)")
    ap.add_argument("--from-discovery", metavar="LOG", help="OpenOCD init / discover.tcl log to read IDCODEs from")
    ap.add_argument("--adapter", help="interface cfg path (overrides USB auto-detect)")
    ap.add_argument("--speed", type=int, default=1000, help="adapter clock kHz (default 1000; start low!)")
    ap.add_argument("--target", default="target/xilinx_zynqmp.cfg", help="target cfg (default ZynqMP)")
    ap.add_argument("--out", help="output path (default openocd/<name>.cfg)")
    ap.add_argument("--force", action="store_true", help="emit even if IDCODE says not-ZynqMP / overwrite")
    args = ap.parse_args()

    # --detect-adapter: print the single recognized adapter's interface cfg and exit.
    if args.detect_adapter:
        usb = detect_usb_adapters()
        if len(usb) == 1:
            print(usb[0][3])
            return
        if len(usb) == 0:
            sys.exit("no recognized JTAG adapter on USB (pass --adapter explicitly)")
        sys.stderr.write("multiple recognized adapters — pass one explicitly:\n")
        for _, _, lbl, ifc, _, _ in usb:
            sys.stderr.write(f"  {ifc}   ({lbl})\n")
        sys.exit(2)

    report = []  # (level, message)
    def note(level, msg): report.append((level, msg))

    # --- adapter ---
    iface = transport = adapter_label = adapter_src = None
    if args.adapter:
        iface, transport, adapter_label, adapter_src = args.adapter, "jtag", "(operator-specified)", "--adapter"
    else:
        usb = detect_usb_adapters()
        if len(usb) == 1:
            _, _, adapter_label, iface, transport, anote = usb[0]
            adapter_src = "USB auto-detect (lsusb)"
            if anote:
                note("info", f"adapter note: {anote}")
        elif len(usb) > 1:
            note("warn", "multiple known adapters plugged in — pass --adapter to choose. Seen: "
                 + "; ".join(f"{l} ({iface})" for _, _, l, iface, _, _ in usb))
            sys.exit("\n".join(f"  [{lv}] {m}" for lv, m in report) + "\nABORT: ambiguous adapter.")
        else:
            note("warn", "no recognized JTAG adapter found on USB and no --adapter given.")
            sys.exit("\n".join(f"  [{lv}] {m}" for lv, m in report)
                     + "\nABORT: specify --adapter <interface cfg> (see openocd/adapters/README.md).")

    iface_disp, iface_ok = resolve_iface(iface)
    if not iface_ok:
        note("warn", f"interface cfg '{iface_disp}' not found in repo or OpenOCD script dirs — verify the path.")

    # --- discovery / SoC family ---
    idcodes = []
    family = None
    if args.from_discovery:
        idcodes = parse_discovery(args.from_discovery)
        if not idcodes:
            note("warn", f"no IDCODEs parsed from {args.from_discovery} — cannot confirm the SoC.")
        for idc in idcodes:
            fam, label, hint = decode_idcode(idc)
            note("info", f"IDCODE 0x{idc:08x}: {label} [{fam}] — {hint}")
            # First non-DAP device sets the SoC family. (A ZynqMP board = one PS-TAP carrying the
            # SoC idcode + the Arm DAP idcode, which decodes as 'arm' and is skipped here.)
            if fam != "arm" and family is None:
                family = fam
        # decide applicability of the (default) ZynqMP target
        if "target/xilinx_zynqmp" in args.target and family and family != "zynqmp":
            msg = (f"IDCODE family is '{family}', NOT ZynqMP — target {args.target} will not work. "
                   "enumerate.tcl/register-KB do not apply. Pass --target for the right SoC (or --force).")
            if not args.force:
                sys.exit("\n".join(f"  [{lv}] {m}" for lv, m in report) + f"\nABORT: {msg}")
            note("warn", msg + " (forced)")
    else:
        note("warn", "no --from-discovery log: SoC family unconfirmed. Run jtag-access-check.tcl/discover.tcl first.")

    # --- resolve the config name (explicit --name, else derived from the detected SoC) ---
    if args.name:
        name, auto_name = args.name, False
    else:
        name = derive_name(idcodes)
        auto_name = True
        if not name:
            sys.exit("\n".join(f"  [{lv}] {m}" for lv, m in report)
                     + "\nABORT: no --name given and no Xilinx IDCODE to derive one from "
                       "(need --from-discovery with a decodable device, or pass --name).")
        note("info", f"auto-named config '{name}' from the detected SoC")

    # --- emit ---
    out = args.out or os.path.join(ROOT, "openocd", f"{name}.cfg")
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    # repo-local adapter cfg -> plain source (relative to repo-root cwd); stock cfg -> [find].
    iface_src = (f"source {iface_disp}" if iface_disp.startswith("openocd/")
                 else f"source [find {iface_disp}]")
    idc_lines = "\n".join(f"#     0x{idc:08x}  {decode_idcode(idc)[1]}" for idc in idcodes) or "#     (none — no discovery log provided)"
    cfg = f"""# {name}.cfg — GENERATED by tools/gen-board-cfg.py on {stamp}
# Provenance:
#   adapter : {adapter_label}  ->  {iface_disp}   (source: {adapter_src})
#   speed   : {args.speed} kHz
#   target  : {args.target}
#   IDCODEs observed in discovery:
{idc_lines}
#
# CAVEATS — the generator CANNOT verify these; YOU must (see docs/18):
#   * I/O voltage / Vref / level-shifting   (ZynqMP PS-JTAG = 1.8 V)
#   * JTAG pinout / connector
#   * clock-speed stability — {args.speed} kHz is a starting point; raise only if IDCODEs stay clean
#   * transport (jtag vs cJTAG) and SRST/TRST wiring
# This config is VALIDATED ONLY against the board whose discovery log produced it.
# (run from the repo root so repo-relative source paths resolve)

{iface_src}
transport select jtag
adapter speed {args.speed}

source [find {args.target}]

# APB-debug mem-AP (AP1) for EDPCSR / debug-gate checks (enumerate.tcl §8, jtag-access-check.tcl).
# Must be created at config time; harmless on non-ZynqMP targets.
catch {{ target create uscale.dbg mem_ap -dap uscale.dap -ap-num 1 }}
"""
    if os.path.exists(out) and not (args.force or auto_name):
        sys.exit(f"refusing to overwrite existing {out} (use --force, or omit --name for an auto-named cfg)")
    with open(out, "w") as f:
        f.write(cfg)

    # --- confidence report ---
    print(f"\nWrote {out}\n")
    print("Confidence report:")
    for lv, m in report:
        print(f"  [{lv.upper():4}] {m}")
    print("\n  Determined : adapter interface, clock (starting value), SoC family (if log given).")
    print("  YOU verify : voltage/Vref/level-shift, pinout, speed stability, transport, SRST.")
    print(f"\nNext: openocd -f openocd/{name}.cfg -c \"init; source openocd/jtag-access-check.tcl; shutdown\"")


if __name__ == "__main__":
    main()
