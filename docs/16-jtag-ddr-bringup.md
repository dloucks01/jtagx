# 16 — JTAG DDR Bring-up via psu_init Replay, and the Open-DAP Threat Model

**Board:** AMD Zynq UltraScale+ MPSoC ZCU102 (XCZU9EG), S/N 210308BD8D4D —
the all-open dev baseline (`SEC_CTRL=0`, JTAG not disabled, unsigned/unencrypted
boot images). **Status:** DDR bring-up + arbitrary code-exec **verified on
silicon 2026-06-08**; the U-Boot launch stage (Stage B) is in progress.

This document records a JTAG-only capability developed during the VxWorks-boot
work and analyses what it grants an attacker — and, equally, what revokes it.
It is a **characterization** finding: the technique is powerful *because this
board has no security provisioned*. The open JTAG DAP is the trust boundary
(see `project_findings_retracted`, the project premise). It composes with the
earlier surface work (`docs/13`, `docs/14`) and maps onto the posture-detector
checklist (`docs/11`, `docs/15`).

---

## 1. The technique

### 1.1 Problem it solves
On a board strapped to JTAG boot mode with no SD/QSPI image to run, you have a
DAP but no DRAM: the BootROM leaves all power domains up and PLLs locked, but the
APU is held in reset and DDR is uninitialised. To run anything substantial
(U-Boot, an OS, a large payload) you need DDR, and DDR needs the board-specific
psu_init sequence (DDRC config + PHY training).

### 1.2 Why running the FSBL over JTAG fails
The obvious approach — load the PetaLinux FSBL into OCM, point the A53 at it,
resume — **wedges the OpenOCD DAP** during psu_init: a hard AXI deadlock
(`Timeout during WAIT recovery`, recoverable only by power-cycle). A software
breakpoint placed *after* DDR training never fires, proving the wedge happens
*during* psu_init, triggered by **A53 code execution**, not by the later
boot-device error-lockdown. Xilinx's XSDB tolerates this (it manages the debug
clock across psu_init); OpenOCD 0.12 does not. Hardware breakpoints are also
unavailable on this target in 0.12 (`resource not available`).

### 1.3 The fix: replay psu_init as pure JTAG MMIO, A53 halted
Instead of *executing* psu_init, **replay the identical register sequence as
JTAG memory writes while the A53 stays halted** — no code runs on the core, so
there is no error-lockdown and (empirically) no wedge.

- **Source of truth:** the exact ZCU102 psu_init ships in the FSBL tree:
  `references/src/embeddedsw/lib/sw_apps/zynqmp_fsbl/misc/zcu102/psu_init_gpl.c`
  (776 `PSU_Mask_Write` + 19 `mask_poll` + 17 `mask_delay`).
- **Extractor:** `tools/psu-init-to-jtag.py` parses it into
  `openocd/psu-init-replay.tcl`. Replayed in psu_init() order, only the parts
  needed for DRAM + a UART console: `mio → peripherals_pre → pll → clock →
  ddr_init → ddr_phybringup → peripherals` (488 ops). Protection/SerDes/XMPU/XPPU
  functions are skipped (not needed; with protection off, DDR is open).
- **Semantics:** `PSU_Mask_Write(off,mask,val)` = read-modify-write
  `(In32 & ~mask) | (val & mask)`; `prog_reg` adds a shift; `mask_poll` waits
  until `(read & mask) != 0`.
- **Hand-coded piece:** `psu_ddr_phybringup_data` is data-dependent (while-loop
  PGSR0 polls, a runtime-computed `cur_R006_tREFPRD`), so it is hand-translated
  in the generator. DDR training is complete when `PGSR0 (0xFD080030) ==
  0x80000FFF`; the error field `(PGSR0 >> 18) & 0x1FFF` must read 0.
- **Prereq:** release A53-0 first (the recipe in `reference_a53_release`:
  `RST_FPD_APU=0x380E` clearing the L2 reset bit 8, set RVBAR, drop a safe
  landing in OCM, `arp_examine`, `halt`).

### 1.4 Result (verified)
Running `openocd -f openocd/zcu102.cfg -c "source openocd/jtag-ddr-boot.tcl"`
walks every phase with **the DAP alive throughout** and ends with DDR
read/write verified at `0x00100000` and `0x40000000`. From there an arbitrary
binary can be staged in DRAM and executed at EL3.

> **Gotcha log:** a proc named `poll` shadows OpenOCD's builtin → renamed
> `mpoll`/`mpollv`. Loading a large image to DDR via the **AXI-AP** silently
> landed wrong data (`load_image` to `0x8000000` read back garbage); resuming
> into it wedged the DDR/FPD path. Fix: load via the **A53 core target**
> (halted, MMU off = direct physical writes) and verify the load before jumping.

---

## 2. The capability this grants

With nothing but JTAG, no firmware, and no signed image, on this board:

1. **Arbitrary physical memory read/write** — registers, OCM, and now DRAM.
2. **DRAM from cold** — full DDR, brought up without the vendor boot chain.
3. **Arbitrary code execution at EL3** — the highest privilege level, by staging
   a blob in DRAM/OCM and pointing a released A53 at it.

That triad — DRAM + EL3 code-exec + unauthenticated memory R/W — is the
foundation everything below composes from.

---

## 3. Offensive surface it composes into (this board)

| Capability | Mechanism | Composes with |
|---|---|---|
| **Boot-chain persistence / backdoor** | Bring up DDR → run U-Boot → `fatwrite`/flash a *trojaned* `BOOT.BIN` (patched FSBL/ATF/OS) that survives power cycles and reflashes. JTAG → flash is a persistence channel (the "evil maid"). | The SD/QSPI flashing path itself |
| **Runtime secret extraction** | DRAM holds decrypted firmware, keys, OS process memory; EL3 + DRAM-read dumps any of it. | PUF helper-data extraction (`project_puf_extractable_via_jtag`), CSU/AES/SHA surface, BBRAM/eFuse-cache reads (`reference_hashes_keys_security`) |
| **Live-OS compromise** | Halt a running Linux/VxWorks, patch the kernel in place, disable auth, inject a payload. DDR bring-up means an OS need not even be booted first. | `openocd/probe-phys-patch.tcl`, `probe-va-write.tcl` (VA→PA + AXI-AP kernel patch demos) |
| **Software-security bypass** | Any protection assuming a trusted boot chain (software-enforced verified boot, keys in DRAM, FSBL-trusting anti-tamper) is moot when the attacker is the EL3 monitor before any of it runs. | `docs/14` subsystem model |

Out of scope by user constraint and project ethics: no glitch/DPA/ChipWhisperer,
no eFuse-bricking (destructive), no targeting of hardware not owned.

---

## 4. The caveat — what revokes all of it (the characterization payoff)

**Every item in §2–§3 collapses the moment the DAP is closed.** On a provisioned
ZynqMP the same scripts get nothing. This is the value of the finding: it is a
concrete demonstration of the threat model the security eFuses/features defend
against, one-to-one with the posture detector.

| Open-board enabler (this board) | Hardened-board control | Effect on the attack |
|---|---|---|
| DAP examinable; `JTAG_SEC`/`DBGEN` open | `JTAG_DIS` / `DBGEN`/`SPIDEN` eFuses | A53 can't be released; STICKY ERROR is terminal — **the whole technique dies at step 0** |
| Unsigned, unencrypted boot images (`encryptionKeySource=0`, IHT `headerAC=0`) | Secure boot: RSA-4096 auth (PPK hash in eFuse) + AES-256 | Trojaned `BOOT.BIN` rejected by BootROM — **no persistence** |
| No memory isolation | XMPU / XPPU + TrustZone | Even with code-exec, DRAM/peripheral regions are walled — **no free secret read / live patch** |
| Keys/PPK/BBRAM unprovisioned (all-zero) | eFuse AES key, PPK0/1 hashes, BBRAM key | Nothing sensitive sitting readable |
| `SEC_CTRL = 0` | Provisioned secure-control eFuses | The posture detector flags the gap |

This is precisely what `rule_security_posture_summary` enumerates OFF→ON, and it
slots next to the published-research checklist in `docs/15` (CVE-2019-5478,
JustSTART, etc. all likewise require an enforcing board to be interesting).

---

## 5. Reproduction

```bash
# 1. SW6 = JTAG (all ON, mode 0x0); power-cycle (1-min drain); FT232H on ttyUSB4.
# 2. (Re)generate the replay from the vendor psu_init source:
python3 tools/psu-init-to-jtag.py            # -> openocd/psu-init-replay.tcl
# 3. Release A53, replay psu_init via MMIO, verify DDR:
openocd -f openocd/zcu102.cfg -c "source openocd/jtag-ddr-boot.tcl" -c shutdown
# 4. (Stage B) load + run U-Boot, then fatwrite/flash from its prompt:
openocd -f openocd/zcu102.cfg -c "source openocd/jtag-load-uboot.tcl" -c shutdown
```

Artifacts: `tools/psu-init-to-jtag.py`, `openocd/{psu-init-replay,jtag-ddr-boot,
jtag-load-uboot}.tcl`, `build-vxboot/u-boot.bin` (FSBL/PMUFW are split from the
PetaLinux image by `build-vxboot/build_vxworks_zcu102.py`).
Earlier loader iterations (`jtag-uboot-v2/v3`, `recover-uboot`, `stage-b-debug`, the
`ddr-*test` / `inspect-*` diagnostics) now live in `_archive/openocd-scratch/`.
Full state + gotchas: memory `project_jtag_ddr_bringup`,
`project_vxworks_boot_build`, `reference_a53_release`, `reference_dap_wedge`.

---

## 6. Bottom line

A small, reproducible JTAG toolchain turns an open DAP into full board ownership
— DRAM, EL3 code-exec, persistence, secret extraction, live-OS patching — with
no vendor tooling and no signed image. None of it survives a board that has set
its JTAG-disable, secure-boot, and isolation eFuses. The deliverable is therefore
not an exploit but a **measurement**: here is the complete attacker reach an
unprovisioned DAP grants, and here is each control that takes it away.
