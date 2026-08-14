#!/usr/bin/env python3
"""
board-runner.py — the fixed engine of the multi-board engagement toolkit.

One program, walked the same way every time, that turns a JTAG chain fingerprint into an ORDERED
PLAN of concrete commands. It does NOT invent chip knowledge: it LOOKS UP a data profile
(profiles/*.json) when the chip is one we've characterized, and FALLS BACK to probe-based generic
capabilities when it isn't. See docs/22-multiboard-capability-matrix.md for the model, and
profiles/_schema.md for the profile format.

THE STATE MACHINE (identical for every board):
    1. IDENTIFY     — read the chain's IDCODEs (you supply them; this tool plans, it doesn't drive JTAG)
    2. FINGERPRINT  — exact-match a profile? -> Tier 1 (full)
                      else probe-able paradigm (ARM DAP present)? -> Tier 2 (generic)
                      else -> Tier 3 (identify-only)
    3. VERDICT      — access-check (OPEN/LOCKED) ............ planned as a LIVE step
    4. BRANCH       — OPEN -> dump ; LOCKED -> reopen -> re-verdict
    5. ANALYZE      — offline (safe) parse/symbolize/secrets/Ghidra

This tool PLANS (and can write a manifest); the LIVE JTAG steps are run by the operator (the project's
hands-on-JTAG rule). Every step is tagged [LIVE] (you run it on the board), [OFFLINE] (safe to run
now), or [VENDOR] (needs a vendor tool, e.g. FlashPro for an FPGA).

USAGE
    # Plan from IDCODEs you already have (offline — no hardware):
    python3 tools/board-runner.py --idcodes "0x14710093 0x5ba00477"
    # Plan from a saved discover.tcl / jtag-access-check / probe-board log:
    python3 tools/board-runner.py --from-log firstcontact.log
    # Write a machine-readable manifest too:
    python3 tools/board-runner.py --idcodes "..." --out-json reports/plan.json
    # Validate every profile in the registry (CI / offline):
    python3 tools/board-runner.py --validate
"""
import argparse, importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REGISTRY_DEFAULT = os.path.join(ROOT, "profiles")


# ---- reuse the single-source IDCODE decoder + log regexes from gen-board-cfg.py -----------------
def _load_gbc():
    spec = importlib.util.spec_from_file_location("gen_board_cfg", os.path.join(HERE, "gen-board-cfg.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

_GBC = _load_gbc()
decode_idcode = _GBC.decode_idcode          # idc:int -> (family, name, note)
DEV_IDCODE_RES = _GBC.DEV_IDCODE_RES         # tuple of compiled regexes for real device-report lines

# JEP106 manufacturer -> paradigm hint, for chips with no profile (so Tier-2/3 classification is honest).
MFG_PARADIGM = {
    0x23B: ("A/B", "ARM CoreSight DAP — Cortex-A (Paradigm A) or Cortex-M MCU (Paradigm B); the mem-AP probe decides"),
    0x049: ("A",   "Xilinx Zynp/ZynqMP-class — ARM Cortex-A + DRAM"),
    0x02B: ("D",   "Lattice FPGA — programming TAP, no CPU; bitstream via vendor tool"),
    0x06E: ("D",   "Altera/Intel — FPGA or SoC-FPGA; if SoC-FPGA it's Paradigm A, else D"),
}


# ---- profile registry (declarative data) --------------------------------------------------------
def load_jsonc(path):
    """JSON with full-line // or # comments stripped (see profiles/_schema.md)."""
    keep = []
    for ln in open(path, encoding="utf-8"):
        s = ln.lstrip()
        if s.startswith("//") or s.startswith("#"):
            continue
        keep.append(ln)
    return json.loads("".join(keep))


REQUIRED_FIELDS = ("schema_version", "name", "soc", "paradigm", "match")

def validate_profile(prof, path):
    errs = []
    for f in REQUIRED_FIELDS:
        if f not in prof:
            errs.append(f"missing required field '{f}'")
    if prof.get("schema_version") != 1:
        errs.append(f"schema_version must be 1 (got {prof.get('schema_version')!r})")
    if prof.get("paradigm") not in ("A", "B", "C", "D", "E"):
        errs.append(f"paradigm must be one of A/B/C/D/E (got {prof.get('paradigm')!r})")
    m = prof.get("match", {})
    if not isinstance(m, dict) or "family" not in m:
        errs.append("match.family is required")
    # warn (not error) if referenced scripts/tools don't exist on disk
    warns = []
    def _check(p):
        if p and not os.path.exists(os.path.join(ROOT, p)):
            warns.append(f"referenced path not found: {p}")
    _check(prof.get("openocd_cfg")); _check(prof.get("access_check"))
    enum = prof.get("enumerate")
    _check(enum if isinstance(enum, str) else (enum or {}).get("script"))
    for lever in prof.get("reopen", []) or []:
        _check(lever)
    d = prof.get("dump") or {}
    for blk in ("dram", "flash"):
        if d.get(blk):
            _check(d[blk].get("script"))
    if prof.get("patch"):
        _check(prof["patch"].get("script"))
    for a in prof.get("analysis", []) or []:
        _check(a.get("tool"))
    # adapters allowlist (optional): validate shape if present
    adapters = prof.get("adapters")
    if adapters is not None:
        ADAPTER_BACKENDS = {"openocd", "hw_server", "libero", "bmp", "vendor", "discovery"}
        ADAPTER_TIERS = {"a", "b", "c", "d", "e"}
        if not isinstance(adapters, list):
            errs.append("adapters must be a list")
        else:
            for i, ad in enumerate(adapters):
                if not isinstance(ad, dict):
                    errs.append(f"adapters[{i}] must be an object")
                    continue
                for req in ("id", "backend", "tier"):
                    if req not in ad:
                        errs.append(f"adapters[{i}] missing required '{req}'")
                if ad.get("backend") not in ADAPTER_BACKENDS:
                    errs.append(f"adapters[{i}].backend {ad.get('backend')!r} not in {sorted(ADAPTER_BACKENDS)}")
                if ad.get("tier") not in ADAPTER_TIERS:
                    errs.append(f"adapters[{i}].tier {ad.get('tier')!r} must be one of a/b/c/d/e")
    return errs, warns


def load_registry(reg_dir):
    profs = []
    if not os.path.isdir(reg_dir):
        return profs
    for fn in sorted(os.listdir(reg_dir)):
        if not fn.endswith(".json") or fn.startswith("_"):
            continue
        path = os.path.join(reg_dir, fn)
        try:
            prof = load_jsonc(path)
        except Exception as e:
            sys.stderr.write(f"WARN: failed to parse {path}: {e}\n")
            continue
        prof["_path"] = path
        profs.append(prof)
    return profs


# ---- identify -----------------------------------------------------------------------------------
def parse_idcodes(args):
    """Return a list of IDCODE ints from --idcodes or --from-log."""
    ids = []
    if args.idcodes:
        toks = args.idcodes if isinstance(args.idcodes, list) else [args.idcodes]
        for tok in toks:
            for t in re.split(r"[\s,]+", tok.strip()):
                if t:
                    ids.append(int(t, 16))
    if args.from_log:
        text = open(args.from_log, encoding="utf-8", errors="replace").read()
        for rgx in DEV_IDCODE_RES:
            for m in rgx.finditer(text):
                ids.append(int(m.group(1), 16))
    # de-dup preserving order
    seen, out = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i); out.append(i)
    return out


def fingerprint(idcodes):
    """Decode every IDCODE into a structured fingerprint."""
    taps = []
    for idc in idcodes:
        mfg = (idc >> 1) & 0x7FF
        part = (idc >> 12) & 0xFFFF
        fam, name, note = decode_idcode(idc)
        taps.append({"idcode": f"0x{idc:08x}", "mfg": mfg, "part": f"0x{part:04x}",
                     "family": fam, "name": name, "note": note})
    return taps


def classify_paradigm(taps):
    """Best-guess paradigm + reason from the decoded taps, for the no-profile case."""
    fams = {t["family"] for t in taps}
    mfgs = {t["mfg"] for t in taps}
    if fams & {"zynqmp", "zynq7"} or 0x23B in mfgs:
        # an ARM DAP (or a Zynq PS) is present -> Cortex-A SoC (A); could be a bare Cortex-M (B).
        if 0x23B in mfgs and not (fams & {"zynqmp", "zynq7"}):
            return "A/B", MFG_PARADIGM[0x23B][1]
        return "A", "ARM Cortex-A SoC with a CoreSight mem-AP onto external DRAM"
    if "versal" in fams:
        return "A", "Versal ACAP — ARM Cortex-A, but a different register map than ZynqMP"
    for mfg in mfgs:
        if mfg in MFG_PARADIGM and MFG_PARADIGM[mfg][0] == "D":
            return "D", MFG_PARADIGM[mfg][1]
    return "?", "manufacturer/part not classified — treat as identify-only"


# ---- the three-tier match -----------------------------------------------------------------------
def match_tier1(taps, registry):
    """Return the first profile whose match{} is satisfied by the fingerprint, else None."""
    fams = {t["family"] for t in taps}
    parts = {t["part"].lower() for t in taps}
    for prof in registry:
        if prof.get("auto_match") is False:
            continue   # un-fingerprintable board (e.g. Pi, IGLOO2): selectable only via --profile
        m = prof.get("match", {})
        if m.get("family") not in fams:
            continue
        want_parts = [p.lower() for p in (m.get("part_ids") or [])]
        if want_parts and not (set(want_parts) & parts):
            continue
        if len(taps) < int(m.get("min_taps", 0)):
            continue
        return prof
    return None


# ---- plan construction --------------------------------------------------------------------------
def _ocd(cfg, body):
    c = cfg or "<your-board.cfg>"
    return f'openocd -f {c} -c "init; {body}; shutdown"'

def _envjoin(env):
    """Render an ordered {VAR: value} env map as a 'A=1 B=2 ' prefix (empty if none)."""
    if not env:
        return ""
    return " ".join(f"{k}={v}" for k, v in env.items()) + " "

def _step(n, mode, title, cmd, note="", optional=False):
    return {"n": n, "mode": mode, "title": title, "cmd": cmd, "note": note, "optional": optional}


def plan_for_profile(prof):
    """Dispatch a profile to the right plan by paradigm (A/E -> CoreSight; D -> vendor handoff)."""
    if prof.get("paradigm") == "D":
        return plan_paradigm_d(prof)
    return plan_paradigm_a(prof)


def plan_paradigm_d(prof):
    """FPGA / no-CPU profile: identify + hand off to the vendor tool. No memory capability."""
    cfg = prof.get("openocd_cfg")
    steps, n = [], 0
    def add(*a, **k):
        nonlocal n; n += 1; steps.append(_step(n, *a, **k))
    if prof.get("access_check"):
        add("LIVE", "Identify / chain + status",
            _ocd(cfg, f"source {prof['access_check']}"),
            "Record IDCODE(s) + device status. (No ARM DAP / no memory bus on this TAP.)")
    v = prof.get("vendor") or {}
    tool = v.get("tool", "the FPGA vendor's programming tool")
    add("VENDOR", f"Hand off to {tool}",
        v.get("cmd", f"# use {tool}"),
        v.get("note", "FPGA programming TAP — bitstream/eNVM only via the vendor protocol; OpenOCD can't."))
    for s in v.get("steps", []) or []:
        add("VENDOR", s, "# " + s, "")
    return steps, ["no memory capability over JTAG (FPGA TAP — vendor tool only)"]


def plan_paradigm_a(prof):
    cfg = prof.get("openocd_cfg")
    steps, n = [], 0
    gaps = []
    absent = prof.get("absent") or {}   # honest per-profile reason a capability is missing (by-design vs TODO)
    def gap(cap, default):
        gaps.append(absent.get(cap, default))
    def add(*a, **k):
        nonlocal n; n += 1; steps.append(_step(n, *a, **k))

    if prof.get("access_check"):
        add("LIVE", "Access verdict (is the DAP OPEN?)",
            _ocd(cfg, f"source {prof['access_check']}"),
            "Universal OPEN/RESTRICTED/LOCKED check. Proceed only on OPEN.")

    if prof.get("reopen"):
        for lever in prof["reopen"]:
            add("LIVE", f"Reopen debug (if LOCKED-but-mutable): {os.path.basename(lever)}",
                _ocd(cfg, f"source {lever}"),
                "Only needed if the verdict was not OPEN. Re-run the verdict after.", optional=True)
    else:
        gap("reopen", "reopen lever (LOCKED targets can't be re-opened by this profile yet)")

    enum = prof.get("enumerate")
    if enum:
        # enumerate may be a bare script string, or {script, interpret} (interpret defaults true).
        escript = enum if isinstance(enum, str) else enum.get("script")
        interpret = True if isinstance(enum, str) else enum.get("interpret", True)
        add("LIVE", "Enumerate security posture",
            _ocd(cfg, f"source {escript}"),
            "Chip-specific register read." + (" -> reports/raw-*.json" if interpret else " (prints a posture snapshot)"))
        if interpret:
            add("OFFLINE", "Interpret the posture capture",
                'python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O')
    else:
        gap("enumerate", "security-posture enumeration (no register KB for this SoC yet)")

    # Phase-2b unlock plan: if the verdict was not OPEN, classify the locks + rank ways to defeat them.
    # Placed after enumerate so the capture exists for --from-capture; it drives the reopen step above.
    soc = prof.get("soc", "")
    if soc in ("zynqmp", "zynq7000"):
        uecmd = (f'python3 tools/unlock-engine.py --soc {soc} '
                 '--from-capture "$(ls -t reports/raw-*.json | head -1)"')
    else:
        uecmd = f'python3 tools/unlock-engine.py --soc {soc or "<soc>"} --jtag-locked   # + posture flags from enumerate'
    add("OFFLINE", "Unlock plan (only if the verdict was not OPEN) — classify locks + rank defeat strategies",
        uecmd,
        "Phase-2b: enforcement-classifies each lock (software-reversible vs eFuse-sealed) and ranks "
        "strategies software-lever -> alternate-path -> physical. Drives the reopen step above.")

    dump = prof.get("dump") or {}
    dram = dump.get("dram")
    if dram:
        env = f"DUMP_SPARSE={1 if dram.get('sparse') else 0} DUMP_ADDR={dram['addr']} DUMP_SIZE={dram['size']} DUMP_OUT={dram['out']}"
        body = "source " + dram["script"]
        add("LIVE", "Dump live OS from DRAM (sparse)",
            f"{env} {_ocd(cfg, body)}",
            "Skips zero regions; only used RAM hits disk.")
    flash = dump.get("flash")
    if flash:
        env = _envjoin(flash.get("env"))
        body = "source " + flash["script"]
        add("LIVE", "Dump boot flash (over JTAG)",
            f"{env}{_ocd(cfg, body)}",
            flash.get("note", "Reads the boot flash over the debug bus."))
    else:
        gap("flash", "flash dump (no flash-controller driver for this SoC yet)")

    # auto: structural triage of the primary dump (what IS this blob?) — before the targeted analyzers.
    primary_dump = (flash or {}).get("out") or (dram or {}).get("out")
    if primary_dump:
        add("OFFLINE", "Triage the dump (entropy map + embedded signatures)",
            f"python3 tools/dump-triage.py {primary_dump}",
            "What is it: code vs encrypted/compressed vs blank, + filesystems/boot-images/certs.")

    for a in prof.get("analysis", []) or []:
        on = a.get("on")
        src = (dram or {}).get("out") if on == "dram" else (flash or {}).get("out")
        if src:
            add("OFFLINE", f"Analyze ({os.path.basename(a['tool'])} on {on})",
                f"python3 {a['tool']} {src}")

    g = prof.get("ghidra")
    if g:
        primary = (flash or {}).get("out") or (dram or {}).get("out")
        if primary:
            if g == "auto":
                add("OFFLINE", "Determine Ghidra load settings (from the bytes)",
                    f"python3 tools/ghidra-loadspec.py {primary}")
            else:
                add("OFFLINE", "Ghidra load settings (from profile)",
                    f"# language={g.get('language')}  base={g.get('base')}")

    if prof.get("patch"):
        p = prof["patch"]
        usev2p = "PATCH_USE_V2P=1 " if p.get("pa_math") == "virt2phys" else ""
        extra = _envjoin(p.get("env"))   # e.g. PATCH_CORE/PATCH_AXI/PATCH_DAP for a non-ZynqMP SoC
        patch_body = "source " + p["script"]
        add("LIVE", "Capability 2 — live memory patch (physical R/W proof)",
            f"{extra}{usev2p}PATCH_VA=<target-VA> PATCH_HALT=0 {_ocd(cfg, patch_body)}",
            "Find a target VA with tools/find-patch-target.py. The mem-AP write hits physical memory "
            "directly (bypasses the MMU's RO .text on MMU parts; on a no-MMU MCU, target SRAM).",
            optional=True)

    # ---- Capability 3 — WRITE / persistence (DESTRUCTIVE): patch the firmware on flash, not just RAM ----
    rf = prof.get("reflash")
    if rf:
        fout = (flash or {}).get("out", "dumps/flash.bin")
        if rf.get("repack"):   # ZynqMP/Zynq-7000 bootgen image: patch offline + recompute checksums first
            add("OFFLINE", "Repack the dumped boot image with your patch (recompute bootgen checksums)",
                f"python3 tools/repack-bootimage.py {fout} --inspect   "
                f"# then: --patch 0xOFF=HEX -o dumps/boot-patched.bin",
                "Plain (non-auth/non-enc) partitions are patchable; it warns on auth/encrypt/data-checksum.",
                optional=True)
        if rf.get("script"):   # a live reflash script (e.g. Cortex-M via OpenOCD's flash driver)
            renv = _envjoin(rf.get("env"))
            add("LIVE", "Capability 3 — reflash (PERSISTENT, DESTRUCTIVE)",
                f"{renv}{_ocd(cfg, 'source ' + rf['script'])}",
                rf.get("note", "Writes the patched firmware to flash. Part must be UNLOCKED."),
                optional=True)
        elif rf.get("note"):   # doc-only method (ZynqMP: SD card / U-Boot sf write)
            add("LIVE", "Capability 3 — reflash (PERSISTENT, DESTRUCTIVE)",
                "# " + rf["note"], "", optional=True)

    return steps, gaps


def plan_tier2(paradigm, reason):
    """Generic, profile-less plan for a probe-detectable Paradigm-A board."""
    steps, n = [], 0
    def add(*a, **k):
        nonlocal n; n += 1; steps.append(_step(n, *a, **k))
    cfg = "<your-board.cfg>"   # from probe-board.sh / gen-board-cfg.py
    add("LIVE", "Access verdict (is the DAP OPEN?)",
        _ocd(cfg, "source openocd/jtag-access-check.tcl"),
        "Universal ADIv5 check — no profile needed.")
    add("LIVE", "Probe for a mem-AP + dump DRAM by walking (sparse)",
        f"DUMP_SPARSE=1 DUMP_ADDR=0x0 DUMP_SIZE=0x80000000 DUMP_OUT=dumps/os-live.bin "
        f"{_ocd(cfg, 'source openocd/dump-os-ddr.tcl')}",
        "If the mem-AP probe finds no DRAM, this is likely Paradigm B (a Cortex-M MCU): read its "
        "INTERNAL flash/SRAM directly instead, and drop to Tier 3 for the report.")
    add("OFFLINE", "Scan the DRAM dump for secrets",
        "python3 tools/dram-secrets.py dumps/os-live.bin --base 0x0")
    add("OFFLINE", "Determine Ghidra load settings (from the bytes)",
        "python3 tools/ghidra-loadspec.py dumps/os-live.bin")
    add("LIVE", "Capability 2 — generic live patch (virt2phys VA->PA)",
        f"PATCH_USE_V2P=1 PATCH_VA=<target-VA> PATCH_HALT=1 {_ocd(cfg, 'source openocd/probe-phys-patch.tcl')}",
        "No profile, so use virt2phys (translate through the core) rather than a known linear map.",
        optional=True)
    return steps, ["chip-specific posture / flash / reopen — author a profile to promote this to Tier 1"]


def plan_tier3(paradigm, reason):
    steps = [_step(1, "LIVE", "Access verdict / identify",
                   _ocd("<your-board.cfg>", "source openocd/jtag-access-check.tcl"),
                   "Record IDCODEs, chain, verdict.")]
    if paradigm == "D":
        steps.append(_step(2, "VENDOR", "FPGA — hand off to the vendor tool",
                           "# IGLOO2/SmartFusion: Microchip FlashPro Express   |   Lattice: Diamond / open tools",
                           "No CPU / no memory bus over JTAG. Best case: identify + bitstream readback if unprovisioned."))
    return steps, ["no memory capability over JTAG for this target"]


# ---- render -------------------------------------------------------------------------------------
def build_plan(taps, registry):
    if not taps:
        return {"tier": 0, "label": "no IDCODEs", "paradigm": "?", "reason": "no chain", "steps": [], "gaps": [], "profile": None}
    prof = match_tier1(taps, registry)
    if prof:
        steps, gaps = plan_for_profile(prof)
        return {"tier": 1, "label": prof["name"], "soc": prof["soc"], "status": prof.get("status", "complete"),
                "paradigm": prof["paradigm"], "reason": f"exact profile match ({os.path.basename(prof['_path'])})",
                "steps": steps, "gaps": gaps, "profile": prof["_path"]}
    paradigm, reason = classify_paradigm(taps)
    if paradigm in ("A", "A/B"):
        steps, gaps = plan_tier2(paradigm, reason)
        return {"tier": 2, "label": f"unknown Paradigm-{paradigm} board", "paradigm": paradigm,
                "reason": reason, "steps": steps, "gaps": gaps, "profile": None}
    steps, gaps = plan_tier3(paradigm, reason)
    return {"tier": 3, "label": f"unidentified ({paradigm})", "paradigm": paradigm,
            "reason": reason, "steps": steps, "gaps": gaps, "profile": None}


def render_text(taps, plan):
    L = []
    bar = "=" * 70
    L.append(bar)
    L.append(" BOARD-RUNNER PLAN")
    L.append(bar)
    L.append(" Chain fingerprint:")
    for t in taps:
        L.append(f"   {t['idcode']}  {t['family']:<8} {t['name']}")
    if not taps:
        L.append("   (none — supply --idcodes or --from-log)")
    L.append("")
    L.append(f" TIER {plan['tier']}: {plan['label']}   [Paradigm {plan['paradigm']}]")
    if plan.get("status") and plan["status"] != "complete":
        L.append(f"   profile status: {plan['status'].upper()} — some capabilities not yet implemented")
    L.append(f"   why: {plan['reason']}")
    L.append("")
    L.append(" PLAN (run [LIVE] yourself on the board; [OFFLINE] is safe now; [VENDOR] needs a vendor tool):")
    for s in plan["steps"]:
        tag = f"[{s['mode']}]"
        opt = "  (optional)" if s.get("optional") else ""
        L.append(f"   {s['n']:>2}. {tag:<9} {s['title']}{opt}")
        L.append(f"        $ {s['cmd']}")
        if s.get("note"):
            L.append(f"        - {s['note']}")
    if plan["gaps"]:
        L.append("")
        L.append(" NOT AVAILABLE for this target (honest gaps):")
        for g in plan["gaps"]:
            L.append(f"   - {g}")
    L.append(bar)
    return "\n".join(L)


# ---- main ---------------------------------------------------------------------------------------
def cmd_validate(reg_dir):
    profs = load_registry(reg_dir)
    print(f"validating {len(profs)} profile(s) in {reg_dir}")
    bad = 0
    for prof in profs:
        errs, warns = validate_profile(prof, prof["_path"])
        name = os.path.basename(prof["_path"])
        if errs:
            bad += 1
            print(f"  [FAIL] {name}: " + "; ".join(errs))
        else:
            tag = "OK  " if not warns else "WARN"
            print(f"  [{tag}] {name}  ({prof.get('soc')}, paradigm {prof.get('paradigm')}, {prof.get('status','complete')})")
        for w in warns:
            print(f"         - {w}")
    if bad:
        print(f"{bad} profile(s) FAILED validation")
        return 1
    print("all profiles valid")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Plan an engagement run from a JTAG chain fingerprint.")
    ap.add_argument("--idcodes", nargs="+", help='one or more IDCODEs, e.g. --idcodes 0x14710093 0x5ba00477')
    ap.add_argument("--from-log", help="parse IDCODEs out of a discover/access-check/probe-board log")
    ap.add_argument("--profile", help="force a profile by its 'soc' slug (for boards that can't be "
                                      "fingerprinted, e.g. a Pi = generic ARM DAP, or IGLOO2). Operator-asserted.")
    ap.add_argument("--registry", default=REGISTRY_DEFAULT, help="profile directory (default: profiles/)")
    ap.add_argument("--out-json", help="also write the plan as JSON to this path")
    ap.add_argument("--validate", action="store_true", help="validate the profile registry and exit")
    ap.add_argument("--list", action="store_true", help="list profiles in the registry and exit")
    args = ap.parse_args()

    if args.validate:
        sys.exit(cmd_validate(args.registry))

    registry = load_registry(args.registry)

    if args.list:
        for prof in registry:
            am = "" if prof.get("auto_match", True) else "  (--profile only)"
            print(f"  {prof.get('soc'):14} {prof.get('paradigm')}  {prof.get('status','complete'):8} {prof.get('name')}{am}")
        return 0

    idcodes = parse_idcodes(args)
    taps = fingerprint(idcodes)

    if args.profile:
        prof = next((p for p in registry if p.get("soc") == args.profile), None)
        if not prof:
            ap.error(f"--profile '{args.profile}' not found. Available: "
                     + ", ".join(p.get("soc") for p in registry))
        steps, gaps = plan_for_profile(prof)
        plan = {"tier": 1, "label": prof["name"], "soc": prof["soc"], "status": prof.get("status", "complete"),
                "paradigm": prof["paradigm"], "reason": f"operator-asserted (--profile {args.profile})",
                "steps": steps, "gaps": gaps, "profile": prof["_path"]}
    else:
        if not args.idcodes and not args.from_log:
            ap.error("supply --idcodes or --from-log, or --profile <soc> (or --validate / --list)")
        plan = build_plan(taps, registry)

    print(render_text(taps, plan))

    if args.out_json:
        out = {"fingerprint": taps, "plan": plan}
        os.makedirs(os.path.dirname(os.path.abspath(args.out_json)), exist_ok=True)
        with open(args.out_json, "w") as f:
            json.dump(out, f, indent=2)
        print(f"\nwrote manifest: {args.out_json}")


if __name__ == "__main__":
    main()
