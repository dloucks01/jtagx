#!/usr/bin/env python3
"""
unlock-engine.py — CLI for the Phase-2b unlock engine. Thin wrapper: the engine CORE (lock knowledge
base + strategy ranking, build_plan/render_md) now lives in **jtagx.unlock**, and the capture→posture
derivation in **jtagx.posture** — so the CLI and the GUI ("Reopen / Unlock" panel) share one source.

Given a chip + its enumerated LOCK state, classify how each lock is ENFORCED and rank ways to defeat it
(software-lever → misconfig → alternate-path → physical → firmware → fault-injection → side-channel).

Usage (posture flags; unknown facts stay UNKNOWN and are called out):
    python3 tools/unlock-engine.py --soc zynqmp --jtag-locked
    python3 tools/unlock-engine.py --soc zynqmp --jtag-locked --efuse-jtag-dis
    python3 tools/unlock-engine.py --soc zynqmp --jtag-locked --no-efuse-jtag-dis
    python3 tools/unlock-engine.py --from-capture reports/raw-*.json           # auto-derive (ZynqMP)
    python3 tools/unlock-engine.py --soc zynqmp --jtag-locked --json -o reports/unlock.json  # for the GUI
Offline strategist; it reasons over the posture you give it, it does not touch hardware.
"""
import argparse, json, os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)                    # tools/  (interpret_lib)
sys.path.insert(0, os.path.dirname(_HERE))   # repo root — for `import jtagx`
try:
    from interpret_lib import Capture   # canonical field/reg accessor
except Exception:
    Capture = None
# engine core (shared with the GUI). Re-exported so `ue.build_plan` / `ue.KIND_TAG` etc. still resolve
# for importlib consumers like engagement-report.py.
from jtagx.unlock import KIND_RANK, KIND_TAG, strat, build_plan, render_md  # noqa: F401
from jtagx.posture import derive_flags


def derive_posture(cap):
    """Delegates to jtagx.posture.derive_flags. Kept for back-compat (engagement-report calls it)."""
    return derive_flags(cap)


def main():
    ap = argparse.ArgumentParser(description="Phase-2b unlock engine: classify locks + rank ways to defeat them.")
    ap.add_argument("--from-capture", metavar="RAW_JSON",
                    help="derive posture facts from an enumeration capture (reports/raw-*.json); "
                         "explicit flags below override the derived values")
    ap.add_argument("--soc", help="profile slug (default 'zynqmp' when --from-capture is used)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--jtag-open", action="store_true", help="DAP is OPEN (baseline; nothing to unlock)")
    g.add_argument("--jtag-locked", action="store_true", help="DAP debug gate is CLOSED (the case to defeat)")
    ap.add_argument("--efuse-jtag-dis", dest="efuse", action="store_const", const=True,
                    help="SEC_CTRL JTAG-disable eFuse is SET (eFuse-sealed → hardware only)")
    ap.add_argument("--no-efuse-jtag-dis", dest="efuse", action="store_const", const=False,
                    help="JTAG-disable eFuse is CLEAR (register-gated → software-reversible)")
    ap.add_argument("--dap-ns-locked", action="store_true")
    ap.add_argument("--secure-boot", choices=["on", "off", "encrypt-only"])
    ap.add_argument("--aes-encrypt", action="store_true")
    ap.add_argument("--pmu-sec-locked", action="store_true")
    ap.add_argument("--pmu-sec-writable", dest="pmu_w", action="store_const", const=True)
    ap.add_argument("--runtime-lock", action="store_true")
    ap.add_argument("--rdp", type=int)
    ap.add_argument("--approtect-locked", action="store_true")
    ap.add_argument("--flash-encrypted", action="store_true")
    ap.add_argument("--debug-locked", action="store_true", help="SmartFusion2: M3 debug is security-locked")
    ap.add_argument("--flashlock", action="store_true", help="SmartFusion2: FlashLock/eNVM readback protection on")
    ap.add_argument("--json", action="store_true", help="emit structured JSON (for the GUI)")
    ap.add_argument("-o", "--out", help="write to file instead of stdout")
    a = ap.parse_args()
    if not a.soc:
        if a.from_capture:
            a.soc = "zynqmp"   # --from-capture derivation is ZynqMP-specific
        else:
            ap.error("--soc is required (or use --from-capture)")

    P = {}
    if a.from_capture:
        if Capture is None:
            sys.exit("error: interpret_lib.Capture unavailable — run from the repo so tools/ is importable")
        try:
            raw = json.load(open(a.from_capture))
        except Exception as e:
            sys.exit(f"error: cannot read capture {a.from_capture}: {e}")
        P.update(derive_posture(Capture(raw)))
        print(f"# derived posture from {a.from_capture}: {P}", file=sys.stderr)
    # explicit flags override the derived values
    if a.jtag_open: P["jtag_open"] = True; P.pop("jtag_locked", None)
    if a.jtag_locked: P["jtag_open"] = False; P["jtag_locked"] = True
    if a.efuse is not None: P["efuse_jtag_dis"] = a.efuse
    if a.dap_ns_locked: P["dap_ns_locked"] = True
    if a.secure_boot == "on": P["secure_boot"] = True
    elif a.secure_boot == "off": P["secure_boot"] = False
    elif a.secure_boot == "encrypt-only": P["secure_boot"] = "encrypt-only"
    if a.aes_encrypt: P["aes_encrypt"] = True
    if a.pmu_sec_locked: P["pmu_sec_locked"] = True
    if a.pmu_w is not None: P["pmu_sec_writable"] = a.pmu_w
    if a.runtime_lock: P["runtime_lock"] = True
    if a.rdp is not None: P["rdp_level"] = a.rdp
    if a.approtect_locked: P["approtect_locked"] = True
    if a.flash_encrypted: P["flash_encrypted"] = True
    if a.debug_locked: P["debug_locked"] = True
    if a.flashlock: P["flashlock"] = True

    locks = build_plan(a.soc, P)
    if a.json:
        text = json.dumps(dict(soc=a.soc, posture=P, locks=locks), indent=2)
    else:
        text = render_md(a.soc, P, locks)
    if a.out:
        open(a.out, "w").write(text + "\n")
        print(f"wrote {a.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
