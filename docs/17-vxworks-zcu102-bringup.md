# Running npMain's VxWorks 7 on a stock ZCU102 — Issues & Solutions

**Goal:** boot the extracted npMain VxWorks 7 image (`dumps/sd-extract/vxWorks.bin`,
"ULTRA NP") end-to-end on this ZCU102 (XCZU9EG), with a working OS and networking.

**Result:** VxWorks 7 SMP 64-bit boots to a fully interactive shell on all 4 A53 cores
(`build-vxboot/vxworks-BOOT-v5pg.bin`), and `gem0` Ethernet is up (link + TX/RX, 0 errors,
IP stack bound). npMain's *own* application cannot run here (its FPGA bitstream targets
different silicon — see issue 8), so we bypass it; the VxWorks kernel + networking stand on
their own.

Boot chain: **PetaLinux FSBL+PMUFW → npMain bl31 (EL3) → VxWorks (EL1 @ 0x100000)**, built
with `/tmp/zynq-mkbootimage/mkbootimage -u vx5.bif`, booted from SD (SW6=SD).

---

## Issue 1 — Every boot was completely silent (no UART output at all)
**Symptom:** FSBL banner never appeared on ttyUSB0; only the System Controller (ttyUSB3)
printed, proving the board powered up.
**Root cause:** the PetaLinux boot image lays out partition 0 as **`[PMUFW][FSBL]`**, not
`[FSBL][PMUFW]`. We had split it "first `fsblLength` bytes = FSBL", which actually grabbed
all of PMUFW plus the head of FSBL. The BootROM then loaded PMU firmware into OCM as the
"FSBL" and jumped into it → no banner, silent hang.
**Proof:** the string `"Zynq MP First Stage Boot Loader"` lives in the *second* `0x23f48`
chunk; `"PMU_ROM Version"` in the *first* `0x1fae0` chunk.
**Solution:** split partition 0 (277032 B, at byte `0x2800` in `BOOT.petalinux.bin`) as
`pmufw = [0 : 0x1fae0]` (129760 B) and `fsbl = [0x1fae0 : +0x23f48]` (147272 B). Wrap each
to an ELF (`wrap_elf.py`, FSBL load/entry `0xfffc0000`, PMUFW `0xffdc0000`) and rebuild.
→ `fsbl-correct.bin` / `pmufw-correct.bin`.

## Issue 2 — mkbootimage rejected `destination_cpu` / `exception_level`
**Symptom:** `error: node attribute not supported: "destination_cpu"`.
**Root cause:** antmicro `mkbootimage` defaults to Zynq-7000; the ZynqMP attributes are gated
behind the arch flag.
**Solution:** pass **`-u`** (`--zynqmp`).

## Issue 3 — VxWorks booted but wedged at "probe and attach devices"
**Symptom:** FSBL → bl31 → VxWorks → VxBus init printed, then a hard hang.
**Root cause:** npMain's device tree marks the PL/AXI bridges
(`lpd-hpm0@80000000`, `fpd-hpm0@a0000000`, `fpd-hpm1@500000000`, `pl-ps-ints`) `status=okay`.
With no FPGA bitstream loaded, any AXI access to the PL region never completes → the core
stalls. **Proof:** a JTAG read of PA `0x80000000` returns `Timeout during WAIT recovery`.
**Solution:** patch the device tree to mark those PL nodes `status="fail"` (same byte length
as `"okay"`, so the DTB stays within its slot). VxWorks then skips them.

## Issue 4 — Console turned to garbage right after device probe
**Symptom:** clean text at 115200 through the VxBus banner, then unreadable bytes.
**Root cause:** npMain's DT declares `ps_ref_clk = 50 MHz` (`0x02faf080`); the ZCU102's PS
reference clock is **33.333 MHz**. VxWorks's `xlnx,zynqmp-clock` driver reprograms every PLL
from that wrong reference, so all derived clocks (incl. the UART) come out wrong → baud shift.
**Solution:** patch the DT `ps_ref_clk` clock-frequency to `0x01fca055` (33,333,333). The
clock driver then computes correct dividers and the console stays at 115200.

## Issue 5 — Couldn't decode the hang from the serial console
**Root cause:** once the baud shifted, the USB-UART re-frames per byte and discards the
idle/framing timing, so the original waveform can't be reconstructed in software (tried byte
resampling, autocorrelation, 460800 oversampling — all yield repeating non-text).
**Solution:** stop fighting the console — switch to JTAG.

## Issue 6 — JTAG `halt` was refused
**Symptom:** core examines fine and reads as `running`, but `halt` times out.
**Root cause:** npMain's bl31 gates *invasive* debug (external halt) for lower ELs.
**Solution:** use **non-invasive** debug. EDPCSR (PC Sample Register) reads the running PC
without halting; the AXI-AP reads DDR/OCM while the core runs.
- APB debug mem_ap: `target create uscale.dbg mem_ap -dap uscale.dap -ap-num 1` (before init)
- core 0 debug base `0x80410000`: EDPCSR_lo `+0x0A0`, EDSCR `+0x088`, EDPRSR `+0x314`
- AXI-AP is `uscale.axi` (ap 0).
The JTAG chain reads clean (DAP `0x5ba00477`, PS `0x24738093`) once the PL is empty.

## Issue 7 — Pinpointing the stall + extracting the device tree
EDPCSR pinned the PC at `0x8029949c` (kernel VA `0x80000000` ↔ PA `0x100000`, verified
against a live AXI read) — FDT/`/memory` parsing, with the next store stalling on a PL access.
The device tree itself is in DDR at PA `0x10000` (magic `d00dfeed`). Bulk `dump_image` wedges
this target, so it was read in **64-word chunks** via `uscale.axi read_memory` and
reassembled. The same DTB is **embedded in `vxWorks.bin` at file offset `0x928f90`** (slot
`0x4fc5` = 20421 B, tightly packed) — which is what makes all the DT patches above possible.

## Issue 8 — npMain's FPGA bitstream cannot be loaded (the hard blocker)
**Context:** trying to load npMain's bitstream so the PL exists and its app can run; the
FSBL hung after its banner when given the bitstream.
**Root cause:** the bitstream's IDCODE register write = **`0x04a46093`** (device field
`0x4a46`, a different/larger Zynq UltraScale+ part). Our board is **XCZU9EG**, PL TAP IDCODE
`0x_4738093` (`0x4738`). The FPGA config engine compares the bitstream IDCODE against the
device's hardwired IDCODE, mismatches, and refuses to assert `DONE` → the FSBL polls forever.
**Solution:** none — npMain was built for different silicon, and we have no PL source to
rebuild for the ZU9EG. **Consequence:** npMain's *application* (which needs PL interrupts and
an HSSB/CoE block in the fabric) can't run, so its built-in networking can't run either.
We instead run the VxWorks **kernel** and bring up *generic* Ethernet (issues 9–11).

## Issue 9 — VxWorks 7 boots to a shell (MILESTONE)
With issues 1 + 3 + 4 fixed: `build-vxboot/vxworks-BOOT-v5p.bin` boots VxWorks 7 SMP 64-bit
to a live shell on ttyUSB0 @115200 — `help`/`version`/`devs`/`i` all work, `tIdleTask0–3`
confirm SMP on all four A53 cores.

## Issue 10 — The npMain app crashes during init (signal 11)
**Symptom:** `edrShow` shows a Data abort (FAR `0x68`) in
`...HssbMediaBindingConfig::configMediaBinding → CoeHssbProtocolLayer::userInitialize →
zynqmpPlIntHandlerConnect`. The app does *all* device/network bring-up itself.
**Root cause:** the app wires up a PL-fabric interrupt; with `pl-ps-ints` disabled the lookup
returns null → deref. Enabling `pl-ps-ints` gets past it, but the app then hard-hangs on PL
register access (no fabric) — *worse*, it takes the whole core down.
**Solution / trade-off:** keep `pl-ps-ints` **disabled**. The app then crashes *cleanly*
(signal 11 kills `tRootTask`), but the **kernel, shell, and any already-attached interfaces
survive**. We bring `gem0` up *before* that crash point (issue 11) so it persists.

## Issue 11 — `gem0` Ethernet wouldn't attach (no compatible PHY driver)
**Symptom:** `ERROR: ipcom_drv_eth_init: drvname:gem` / `interface gem0 not found`;
`muxShow` empty.
**Findings:**
- npMain used `micrelPhy@9` on GEM3; the ZCU102 uses a **TI DP83867 at MDIO addr `0xc`**
  (from the working PetaLinux DT: GEM3 `ff0e0000`, `rgmii-id`, `ti,rx/tx-internal-delay`).
  → DT fix: PHY `reg 9 → 0xc`. MDIO then reads the PHY correctly (`phyId1=0x2000`,
  `phyId2=0xa231`, OUI `0x080028` = Texas Instruments).
- The image's only PHY drivers are `micrelPhy` and `switchPhy` (no TI/generic driver). The
  `micrelPhy` verify function **rejects non-Micrel OUIs**: it computes the OUI and runs
  `cmp w8, #0x885; csetm w0, ne` → returns −1 (reject) for the DP83867 (OUI `0x80028`).
- `fixed-link` is **not honored** by this GEM driver (it always does MDIO PHY management),
  so that workaround didn't help.
**Solution:** one-instruction binary patch to the `micrelPhy` verify function at
`vxWorks.bin` file offset **`0x13968`**: `csetm w0, ne` (`0x5a9f03e0`) → `mov w0, wzr`
(`0x2a1f03e0`) — verify now always returns 0 (accept any PHY). The Micrel driver then
attaches to the DP83867, the GEM END comes up, and the IPv4/ARP stack binds to it.

## Final image — v5pg
`build-vxboot/vxworks-BOOT-v5pg.bin` = the patched `vxWorks.bin` (OUI-accept patch + DTB:
ps_ref_clk 33.333 MHz, PL bridges + KSZ port disabled, GEM3 + `micrelPhy@0xc` enabled,
`pl-ps-ints` disabled) → PetaLinux FSBL+PMUFW + npMain bl31 + VxWorks.
**State:** `gem0` UP RUNNING, MAC `00:0a:35:11:22:36`, TX *and* RX incrementing with
`errors:0 collisions:0`, IP stack functional.

## Open item — external IP connectivity
The app set `gem0` to npMain's hardcoded `192.168.0.60/24` before crashing, and a ping to
`192.168.0.1` failed — almost certainly because the lab LAN is on a different subnet (the MAC
TX/RX both work and the stack answers its own broadcast). To finish: set `gem0` to the lab
subnet from the shell, e.g.
`ifconfig "gem0 inet add <ip>/<prefix>"` (and `route add ...` for a gateway), or put a host on
`192.168.0.x` and ping the board. RGMII TX delay (the DP83867's `ti,*-internal-delay`, not set
by the Micrel driver) is a possible later concern, but TX shows 0 errors so far.

## Issue 12 — standalone QSPI boot wedged (`sdhc` on the QSPI boot path)
**Goal:** boot from QSPI so no SD card is needed (provisioned via U-Boot `sf` from PetaLinux:
`fatload` → `sf erase 0 0xB00000` → `sf write 0x10000000 0 0xA70DE0` → `sf read`+`cmp.b`; QSPI =
`mt25qu512a`, 128 MiB, 128 KiB erase; SW6 QSPI = 1 ON/2 OFF/3 ON/4 ON; npMain's QSPI first 16 MB
backed up to SD as `qspi-npmain-16m.bak`). FSBL + VxWorks loaded fine from QSPI, but VxWorks
**wedged** (no shell), unlike the SD boot.
**Diagnosis (JTAG, non-invasive):** EDPCSR pinned the PC at `0x8029d9ec`. Using the correct
mapping **`file = VA − 0x80100000`** (the kernel links at `0x80100000`: `sysInit` = file 0) plus
the live SD-boot symbol table (`lkAddr 0xffffffff8029d9ec`, full 64-bit address), that PC is the
`STR w2,[x1]` inside **`vxbWrite32`** — i.e. a **hung device-register write**. (Couldn't probe the
device on the wedged board: the stuck write jams the whole peripheral-AXI path, so every JTAG
peripheral read sticky-errors; DDR still reads.)
**Root cause:** the PetaLinux FSBL does **boot-device-specific init** — it initializes the SD/MMC
controller on SD boot but **not** on QSPI boot. So on QSPI boot VxWorks's `sdhc` driver writes an
uninitialized controller → the AXI write never completes → core stall. (`sdBusMonitor` is a live
task on the SD boot, confirming the driver runs.)
**Solution:** disable **`sdhc@ff160000`** (`status="fail"`) in the DTB — and also `qspi@ff0f0000`
(its `0xc0000000` linear window also hangs post-QSPI-boot, a separate trap). VxWorks doesn't need
either driver once booted. → `vxworks-BOOT-v5pg3.bin` boots VxWorks 7 SMP + `gem0` **standalone
from QSPI**.
**Restore npMain's QSPI** anytime from the SD backup:
`sf probe; sf erase 0 0x1000000; fatload mmc 0:1 0x10000000 qspi-npmain-16m.bak; sf write 0x10000000 0 0x1000000`.

## Final images
- **SD boot:** `vxworks-BOOT-v5pg.bin` (`sdhc`/`qspi` left enabled — fine on SD).
- **QSPI standalone boot:** `vxworks-BOOT-v5pg3.bin` (`sdhc`+`qspi` disabled). Currently in QSPI.

---

## Reproducible build recipe

**One command:** `cd build-vxboot && python3 build_vxworks_zcu102.py` performs every step
below and emits the two networking images — SD `== v5pg` (md5 `cd4466…`) and QSPI
`vxworks-BOOT-v5pg3.bin` (md5 `2f46c263`). Adding **`--no-net`** skips the 3 networking
patches (micrelPhy OUI-accept + GEM3/DP83867 DTB) and emits the **pre-networking** SD image,
byte-identical to the validated `vxworks-BOOT-v5p.bin` (md5 `8d2ebc69`) — the image that first
booted to an interactive shell. All three validated images are thus reproducible from source.
It needs the inputs `bl31.elf`,
`sd-staging/BOOT.petalinux.bin`, `../dumps/sd-extract/vxWorks.bin`, the local `dtc` (from the
top-level `device-tree-compiler*.deb`), and antmicro `mkbootimage`. The steps below document
what it does (the manual session intermediates — `fsbl-correct.bin`, `wrap_elf.py`, the `vx*.bif`
files — are kept in `_archive/build-vxboot-intermediates/`):

1. Split partition 0 → PMUFW + FSBL (`pmufw.bin`/`fsbl.bin`); wrap to ELFs (issue 1).
2. Carve embedded DTB `vxWorks.bin[0x928f90 : +0x4fc5]`; decompile with local `dtc`
   (`dpkg-deb -x device-tree-compiler*.deb /tmp/dtcroot`) **using stdout redirect**.
3. Edit the DTS: `ps_ref_clk → 0x01fca055`; PL bridges + `gemToKsz` port + `pl-ps-ints` →
   `status="fail"`; GEM3 `status="okay"`, PHY `reg=<0x0c>`, `compatible="micrelPhy"`.
   Recompile; must be ≤ 20421 B (pad to slot).
4. Patch `vxWorks.bin` @ `0x13968`: `0x5a9f03e0 → 0x2a1f03e0`.
5. Splice patched DTB into the patched `vxWorks.bin` @ `0x928f90`; wrap to `vxworks.elf`
   (`0x100000`).
6. `mkbootimage -u vx5.bif vxworks-BOOT-v5pg.bin`
   (`vx5.bif`: bootloader `fsbl.elf` + `pmufw_image` + bl31 EL3 + vxworks EL1).
7. SD: `BOOT.BIN = vxworks-BOOT-v5pg.bin`; SW6=SD; console = ttyUSB0 @115200.
