"""
jtagx.attackgraph — the KILL-CHAIN planner.

Fuses the three things we already model into ONE ordered, prerequisite-aware graph for a (board,
posture): the unlock engine (jtagx.unlock — how to open a gate), the transport capability matrix
(jtagx.transport.matrix — what op a plugged adapter can run), and the findings layers (jtagx.weakness
/ jtagx.cve). Instead of a pile of point tools, it answers "given where I am on THIS board, what is the
ordered path to the objective, what's the exact next command, and where does the chain stall?".

Each node reports a STATE + the concrete action + why (its evidence), so this is honest: a node is only
AVAILABLE if a real, non-physical action exists; when the only way forward is glitch/side-channel/
physical it says BLOCKED (deferred), not "try harder".

    from jtagx.attackgraph import plan, render_md
    g = plan("zynqmp", {"jtag_open": True})           # or a locked posture
    print(render_md(g))
"""
from .unlock import build_plan, workflow_steps

# node states (also the colour/priority order for a UI)
ACHIEVED = "ACHIEVED"    # posture/evidence already puts us here
AVAILABLE = "AVAILABLE"  # preconditions met AND a concrete non-physical action exists → the next move
BLOCKED = "BLOCKED"      # preconditions met but the only way on is glitch / side-channel / physical (deferred)
GATED = "GATED"          # a precondition upstream isn't ACHIEVED yet
NA = "N/A"               # not applicable to this chip

# the linear spine (objective ladder). secure-boot is a parallel branch off jtag-up.
SPINE = ["jtag-up", "debug-open", "mem-read", "secrets", "persistence"]


def _route(profile, op):
    """route_op(profile, op) → (row|None, reason), tolerant of a missing profile/transport layer."""
    if not profile:
        return None, "no board profile loaded"
    try:
        from .transport.matrix import route_op
        return route_op(profile, op)
    except Exception as e:
        return None, f"capability matrix unavailable ({e})"


def _debug_lever(soc, P):
    """The runnable software lever that opens debug (or None). Reuses the guided workflow."""
    try:
        steps = workflow_steps(soc, build_plan(soc, P))
    except Exception:
        return None
    return next((s for s in steps if s.get("lever") and s["lever"].get("cmd")), None)


def _node(id, title, state, action="", why="", needs=(), sev=""):
    return dict(id=id, title=title, state=state, action=action, why=why, needs=list(needs), sev=sev)


def plan(soc, P=None, profile=None, source="asserted"):
    """Compute the kill-chain graph for (soc, posture, [profile]). Returns {soc, nodes:[...], depth,
    depth_label, source} where `nodes` is the ordered spine + the secure-boot branch, and `depth` is how
    far down the spine a NON-PHYSICAL attack reaches right now.

    `source` is the honesty flag on the posture: "capture" = read from live silicon (the states are
    CONFIRMED); "asserted" = operator-supplied flags (the states are a PREDICTION to verify on hardware)."""
    P = P or {}
    source = "capture" if (source == "capture" or P.get("_source") == "capture") else "asserted"
    nodes = []
    achieved = set()

    # 1. jtag-up — the premise: a chain that answers IDCODE. (No chain ⇒ nothing below is reachable.)
    if P.get("no_chain"):
        nodes.append(_node("jtag-up", "JTAG chain answers (IDCODE)", BLOCKED,
                           why="no TAP responded — check wiring/adapter/voltage first",
                           action='openocd -f <cfg> -c "init; source openocd/discover.tcl; shutdown"'))
    else:
        achieved.add("jtag-up")
        nodes.append(_node("jtag-up", "JTAG chain answers (IDCODE)", ACHIEVED,
                           why="a TAP is on the chain (assumed connected)",
                           action='openocd -f <cfg> -c "init; source openocd/discover.tcl; shutdown"'))

    # 2. debug-open — the DAP/AHB-AP is reachable, either already or via a software lever.
    if "jtag-up" not in achieved:
        nodes.append(_node("debug-open", "Debug port OPEN (DAP / AHB-AP)", GATED, needs=["jtag-up"],
                           why="needs a responding chain"))
    elif P.get("jtag_open") is True or P.get("debug_open") is True:
        achieved.add("debug-open")
        nodes.append(_node("debug-open", "Debug port OPEN (DAP / AHB-AP)", ACHIEVED, needs=["jtag-up"],
                           why="posture: debug already OPEN — the DAP is the trust boundary",
                           action='openocd -f <cfg> -c "init; source openocd/enumerate.tcl; shutdown"'))
    else:
        lever = _debug_lever(soc, P)
        if lever:
            achieved.add("debug-open-viable")   # not achieved, but a concrete move exists
            d = "  ⚠destructive" if lever["lever"].get("destructive") else ""
            nodes.append(_node("debug-open", "Debug port OPEN (DAP / AHB-AP)", AVAILABLE, needs=["jtag-up"],
                               action=lever["lever"]["cmd"],
                               why=f"software lever: {lever['lever']['title']}{d} → verify with "
                                   f"{lever.get('verify_cmd') or 'access-check'}", sev="the pivot"))
        else:
            nodes.append(_node("debug-open", "Debug port OPEN (DAP / AHB-AP)", BLOCKED, needs=["jtag-up"],
                               why="no software lever for this posture — needs glitch / side-channel / "
                                   "physical (deferred, needs a rig)"))

    dbg_ok = "debug-open" in achieved
    dbg_reach = dbg_ok or "debug-open-viable" in achieved   # achievable this step

    # 3. mem-read — flash/DRAM extractable. A dump in hand ⇒ ACHIEVED. Else the best CABLE-reachable
    # extraction method (jtagx.extraction): a debug-port dump if debug is open, OR a vendor ROM loader /
    # readback that needs NO debug port (the second avenue). Only chip-off left ⇒ BLOCKED.
    try:
        from .extraction import extraction_plan, best_cable
        ex_plan = extraction_plan(soc, P, profile)
    except Exception:
        ex_plan = []
    cable = best_cable(ex_plan, debug_open=dbg_reach) if ex_plan else None
    if P.get("dumped"):
        achieved.add("mem-read")
        nodes.append(_node("mem-read", "Memory / flash extractable", ACHIEVED, needs=["debug-open"],
                           why="a dump has already been captured"))
    elif cable is not None:
        achieved.add("mem-read-viable")
        note = "" if cable["access"] == "jtag" else f" (no debug port needed — {cable['access']})"
        nodes.append(_node("mem-read", "Memory / flash extractable", AVAILABLE,
                           needs=["debug-open"] if cable["needs_debug"] else [],
                           action=f"{cable['method']}: {cable['how'][:80]}",
                           why=f"best cable path: {cable['method']}{note}"))
    else:
        nodes.append(_node("mem-read", "Memory / flash extractable", BLOCKED, needs=["debug-open"],
                           why="no cable-reachable extraction — only external boot-flash off-board "
                               "(SOIC clip / chip-off) remains"))

    mem_reach = "mem-read" in achieved or "mem-read-viable" in achieved

    # 4. secrets — keys/creds from a dump (offline analysis).
    if not mem_reach:
        nodes.append(_node("secrets", "Keys / credentials extracted", GATED, needs=["mem-read"],
                           why="needs a memory/flash dump"))
    else:
        achieved.add("secrets-viable")
        nodes.append(_node("secrets", "Keys / credentials extracted", AVAILABLE, needs=["mem-read"],
                           action="python3 tools/dram-secrets.py <dump> · tools/symbol-crypto.py <dump> · "
                                  "tools/secureboot-analyze.py <image> · tools/firmware-id.py <dump>",
                           why="offline: entropy/regex/crypto-symbol scan + boot-image auth analysis + "
                               "OS/RTOS id → version-gated CVE classes"))

    # 5. persistence — a reflash implant, once debug is open and the part is reflashable.
    reflash = bool((profile or {}).get("reflash"))
    if not dbg_reach:
        nodes.append(_node("persistence", "Persistent implant (reflash)", GATED, needs=["debug-open"],
                           why="needs debug OPEN first"))
    elif reflash:
        nodes.append(_node("persistence", "Persistent implant (reflash)", AVAILABLE,
                           needs=["debug-open"],
                           action="python3 tools/repack-bootimage.py <img> --patch ...  then the profile's "
                                  "reflash script (DESTRUCTIVE)",
                           why="profile advertises a reflash path"))
    else:
        nodes.append(_node("persistence", "Persistent implant (reflash)", BLOCKED, needs=["debug-open"],
                           why="no reflash path in the profile (add one, or reflash via SD/U-Boot/vendor)"))

    # branch: secure-boot — defeat/forge the boot image (parallel to the spine).
    sb = P.get("secure_boot")
    if sb in (True, "encrypt-only"):
        strat = _secureboot_action(soc, P)
        nodes.append(_node("secure-boot", "Secure boot defeated / image forgeable", AVAILABLE,
                           needs=["jtag-up"], action=strat[0], why=strat[1], sev="branch"))
    elif sb is False:
        nodes.append(_node("secure-boot", "Secure boot defeated / image forgeable", ACHIEVED,
                           needs=["jtag-up"], why="posture: secure boot OFF — unsigned images boot as-is"))
    else:
        nodes.append(_node("secure-boot", "Secure boot defeated / image forgeable", NA, needs=["jtag-up"],
                           why="secure-boot state unknown — run enumerate / secureboot-analyze on an image"))

    # depth = the DEEPEST objective reached (ACHIEVED/AVAILABLE), allowing gaps — because a vendor ROM
    # loader can reach flash/secrets even when the debug-open node is BLOCKED (extraction ≠ strictly
    # dependent on the debug port anymore). The node states show exactly which path got there.
    reach_states = {ACHIEVED, AVAILABLE}
    spine_nodes = {n["id"]: n for n in nodes if n["id"] in SPINE}
    depth = 0
    for i, sid in enumerate(SPINE):
        n = spine_nodes.get(sid)
        if n and n["state"] in reach_states:
            depth = i + 1
    return dict(soc=soc, posture=P, nodes=nodes, depth=depth, depth_label=_depth_label(depth),
                source=source)


def _secureboot_action(soc, P):
    """The best non-physical secure-boot defeat for (soc, posture) → (action, why)."""
    if soc == "zynqmp" and P.get("secure_boot") is True:
        return ("python3 tools/repack-bootimage.py <BOOT.bin> --patch ... (JustSTART, CVE-2023-20570)",
                "RSA-auth bypass — forge + repack a boot image (unpatchable in silicon)")
    if soc == "zynqmp" and P.get("secure_boot") == "encrypt-only":
        return ("modify the UNAUTHENTICATED boot header (CVE-2019-5478)",
                "encrypt-only leaves the header unauthenticated → redirect execution")
    if soc == "zynq7000" and P.get("aes_encrypt"):
        return ("Starbleed bitstream recovery + FSBL RSA bypass (USENIX WOOT'24)",
                "7-series AES-CBC malleability decrypts the bitstream; FSBL is a single point of failure")
    return ("python3 tools/secureboot-analyze.py <image>",
            "analyze the image's auth structure; the sig-verify branch is the (deferred) FI target")


def _depth_label(depth):
    return ["nothing reachable", "chain only", "debug reachable", "memory extractable",
            "secrets extractable", "full chain + persistence"][min(depth, 5)]


def render_md(g):
    src = ("posture CONFIRMED from a live capture" if g.get("source") == "capture"
           else "posture ASSERTED (operator flags) — states are a prediction, verify on hardware")
    L = [f"# Attack graph — {g['soc']}   (posture: {g['posture'] or '(none)'})", "",
         f"**Reach: {g['depth']}/5 — {g['depth_label']}** (non-physical). ⚠ glitch/side-channel/physical "
         "are deferred (need a rig).", "", f"_{src}._", "",
         "| # | objective | state | next action |", "|--|--|--|--|"]
    order = {n["id"]: i for i, n in enumerate(g["nodes"])}
    for n in sorted(g["nodes"], key=lambda x: (x["id"] not in SPINE, order[x["id"]])):
        spine = f"{SPINE.index(n['id']) + 1}" if n["id"] in SPINE else "↳"
        act = (n["action"][:70] + "…") if len(n.get("action", "")) > 71 else n.get("action", "")
        L.append(f"| {spine} | {n['title']} | **{n['state']}** | {act or '—'} |")
    L.append("")
    for n in g["nodes"]:
        if n["state"] in (AVAILABLE, BLOCKED):
            L.append(f"- **{n['title']}** ({n['state']}): {n['why']}")
    return "\n".join(L)
