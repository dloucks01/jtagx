"""
jtagx.preflight — the ENGAGEMENT BLOCKER CHECK core (shared by tools/preflight.py and the GUI).

Given a board profile + the plugged adapters, decide whether you can actually REACH the board: is an
adapter plugged, is it a known path for this SoC, is the backend software it needs installed, does the
transport match? Returns a GO / BLOCKED verdict with the exact fix — so the "wrong adapter blocked me"
surprise happens in triage, not mid-engagement. Pure/offline (only reads shutil.which + the profile).
"""
import shutil

from .transport import match_profile
try:
    from .extraction import ROM_LOADER
except Exception:
    ROM_LOADER = {}

GO, BLOCK, WARN, INFO = "GO", "BLOCKED", "WARN", "info"

# backend → the software that must be on PATH to drive it (any one satisfies it)
BACKEND_TOOLS = {
    "openocd": ["openocd"],
    "hw_server": ["xsdb", "hw_server"],                                  # AMD/Xilinx Vitis/Vivado
    "libero": ["FPExpress", "fpexpress", "libero", "FlashProExpress"],   # Microchip/Microsemi
}
BACKEND_FIX = {
    "hw_server": "install AMD Vivado/Vitis (provides xsdb + hw_server), or bridge the adapter to OpenOCD "
                 "via XVC (Chain ▸ XVC)",
    "libero": "install Microchip Libero SoC / FlashPro Express, or use the OpenOCD SVF/boundary-scan path "
              "for an unprovisioned part",
    "openocd": "install openocd (apt install openocd), or use the bundled engagement kit on an air-gapped box",
}
# soc → vendor ROM-loader extraction tool(s) that make the no-debug avenue usable (informational)
LOADER_TOOLS = {
    "imx6": ["imx_usb", "uuu"], "sama5": ["sam-ba", "bossac"], "esp32": ["esptool.py", "esptool"],
    "rp2040": ["picotool"], "am335x": [], "bcm": [], "esp32c3": ["esptool.py", "esptool"],
}


def _have(tools):
    return next((t for t in tools if shutil.which(t)), None)


def preflight(prof, present):
    """Return (verdict, [(status, title, detail), ...]) for a board profile + the detected adapters."""
    soc = prof.get("soc", "?")
    adapters = prof.get("adapters", [])
    checks = []
    m = match_profile(adapters, present) if present else {"usable": []}

    if not present:
        checks.append((BLOCK, "adapter plugged",
                       "no USB JTAG/SWD adapter detected. If you're in a VM, PASS THE DEVICE THROUGH "
                       "(VMware: VM ▸ Removable Devices ▸ your FTDI/J-Link). Then re-run."))
        return BLOCK, checks
    checks.append((GO, "adapter plugged", f"{len(present)} detected: " +
                   ", ".join(a["name"] for a in present)))

    usable = m["usable"]
    if not usable:
        want = ", ".join(sorted({t for a in adapters for t in a.get("transports", [])})) or "?"
        names = ", ".join(a.get("name", a.get("id", "?")) for a in adapters)
        checks.append((BLOCK, "adapter matches target",
                       f"none of your adapters are a known path for {soc}. It expects one of: {names} "
                       f"(transports: {want}). A generic FTDI may work — verify the cfg/pinout."))
        return BLOCK, checks
    checks.append((GO, "adapter matches target",
                   "usable: " + ", ".join(f"{a['name']} → {a['backend']}" for a in usable)))

    go_paths, missing = [], []
    for a in usable:
        be = a.get("backend", "openocd")
        tool = _have(BACKEND_TOOLS.get(be, [be]))
        (go_paths if tool else missing).append((a, be, tool))
    if go_paths:
        a, be, tool = go_paths[0]
        checks.append((GO, "backend software", f"{be} present ({tool}) for {a['name']}"))
    else:
        a, be, _ = missing[0]
        checks.append((BLOCK, "backend software",
                       f"{a['name']} needs the '{be}' backend, and none of {BACKEND_TOOLS.get(be, [be])} "
                       f"is on PATH. Fix: {BACKEND_FIX.get(be, 'install the vendor software')}."))
        return BLOCK, checks

    def _prof_transports(ua):
        for pa in adapters:
            if pa.get("id") == ua.get("id") or ua.get("usb_id", "").lower() in \
                    [u.lower() for u in pa.get("usb_ids", [])]:
                return pa.get("transports", [])
        return []
    tset = sorted({t for a, _, _ in go_paths for t in _prof_transports(a)})
    checks.append((INFO, "transport", f"available: {', '.join(tset) or 'jtag/swd (per cfg)'}"))

    if soc in ROM_LOADER:
        tools = LOADER_TOOLS.get(soc, [])
        have = _have(tools) if tools else None
        loader = ROM_LOADER[soc][0]
        if tools and not have:
            checks.append((WARN, "ROM-loader extraction",
                           f"the no-debug avenue ({loader}) needs {tools} — not on PATH. Install it if the "
                           "debug port turns out to be locked."))
        else:
            checks.append((INFO, "ROM-loader extraction",
                           f"{loader} available" + (f" ({have})" if have else "") + " as a no-debug fallback."))
    return GO, checks
