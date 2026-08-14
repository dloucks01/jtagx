# 24 — Zynq-7000 Enumerated Attributes (catalog)

The canonical catalog of every security/identity attribute `openocd/zynq7000-enumerate.tcl` reads, with
its location, the value on a **dev/open** board, what the **hardened/provisioned** value means, and why we
care. The Zynq-7000 analog of `docs/11` (ZynqMP). Every field is traced to **UG585 v1.12.2 Appendix B**
(`references/pdf/ug585-zynq7000-trm.pdf`); masks live in `openocd/lib/zynq7000-regs.tcl` (the register KB).

**Posture model.** On Zynq-7000 the secure-boot/eFuse state is *readable* over JTAG via `devcfg.STATUS`
(the eFuse bits are mirrored there). The debug/DAP and AES enables live in `devcfg.CTRL`, frozen by
`devcfg.LOCK`. TrustZone/config-lock is in the SLCR. So a single AHB-AP sweep characterizes the whole
posture — exactly the ZynqMP approach. **Crown jewels = the three eFuse bits in `devcfg.STATUS`.**

> Honest scope: HW-UNVALIDATED — addresses/fields are from UG585, but nothing here has run on real
> Zynq-7000 silicon. Confirm the access verdict + a sanity read on first contact.

---

## (1) Identity

| Attribute | Location | Dev value | Hardened/other | Why we care |
|---|---|---|---|---|
| Device die | `slcr.PSS_IDCODE` `0xF8000530` bits 16:12 | 7z020 etc. (0x02=7z010, 0x07=7z020, 0x11=7z045) | — | Which exact part you're on; sizes the dumps/flash |
| Family / mfg | same, bits 27:21 = 0x1B (Zynq), 11:1 = 0x49 (Xilinx) | Zynq-7000 / Xilinx | — | Confirms it really is a 7-series PS (not a look-alike) |
| Silicon revision | `slcr.PSS_IDCODE` bits 31:28; `devcfg.MCTRL` `0xF8007080` bits 31:28 (PS_VERSION) | 1.0–3.1 | — | Errata/behaviour vary by rev |

## (2) Boot

| Attribute | Location | Dev value | Hardened/other | Why we care |
|---|---|---|---|---|
| Boot device | `slcr.BOOT_MODE` `0xF800025C` bits 2:0 | 0=JTAG 1=QSPI 2=NOR 4=NAND 5=SD | — | Where the boot image lives → which flash dumper to use |
| PLL bypass / JTAG chain | same, bit 4 / bit 3 | PLL enabled / cascade | — | Bring-up sanity |
| Last reset cause | `slcr.REBOOT_STATUS` `0xF8000258` bits 22:16 | POR | DBG_RST / SLC_RST = debug/secure reset | A secure lockdown shows up here |
| BootROM error code | `slcr.REBOOT_STATUS` bits 15:0 | 0x0000 | non-zero = boot fault | Diagnoses a failed/blocked boot |

## (3) Secure boot & eFuse — **the crown jewels** (`devcfg.STATUS` `0xF8007014`, UG585 p.1157)

| Attribute | Bit | Dev value | Hardened (blown) meaning | Why we care |
|---|---|---|---|---|
| **eFuse SECURE_EN** | STATUS[2] | not blown — non-secure boot allowed | **device MUST boot securely w/ the eFuse AES key; non-secure boot → lockdown** | THE secure-boot enforcement fuse |
| **eFuse JTAG_DIS** | STATUS[1] | not blown — JTAG allowed | **ARM DAP permanently in bypass; any DAP activation → lockdown** | THE JTAG-kill fuse (irreversible) |
| **eFuse SW_RESERVE** | STATUS[3] | not blown — BBRAM key usable | BBRAM AES key disabled → eFuse key forced | Key-source policy |
| Booted securely | `devcfg.CTRL` bit 7 (SEC_EN, ro) | no (dev) | this boot was authenticated/encrypted | Whether the *running* image came up secure |
| Secure lockdown | STATUS[7] (SECURE_RST) | clear | device is in lockdown (POR-clear only) | A tamper/violation tripped |
| DEVCI illegal-access | STATUS[6] | clear | wrong UNLOCK word → DEVCI+DAP+secure-boot disabled | A botched unlock self-locks the config port |

## (4) Debug / DAP (`devcfg.CTRL` `0xF8007000` + `devcfg.LOCK` `0xF8007004`, UG585 p.1146-1149)

| Attribute | Bits | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| ARM DAP enable | CTRL[2:0] DAP_EN | 111 (enabled) | ≠111 → DAP bypassed | If bypassed, the AHB-AP is unreachable — no JTAG access |
| Invasive / non-invasive debug | CTRL[3] DBGEN / [4] NIDEN | enabled | disabled | Halt/step + trace gates |
| Secure debug | CTRL[5] SPIDEN / [6] SPNIDEN | enabled | disabled | Secure-world debug |
| JTAG scan chain | CTRL[23] JTAG_CHAIN_DIS | enabled | disabled (PS DAP + PL TAP off) | Whole-chain kill (register, not eFuse) |
| **Debug lock** | LOCK[0] DBG | open — CTRL[6:0] writable | LOCKED → frozen until POR | Decides whether `reopen` works (see below) |

> **Reopen lever:** if DBG-lock is *open*, `devcfg.CTRL |= 0x7F` re-enables DAP + all debug — the same
> software-hardened-vs-locked story as ZynqMP (`openocd/zynq7000-reopen-debug.tcl`). If DBG-lock is set,
> POR-only. The chicken-and-egg: if DAP_EN is already ≠111 you can't reach CTRL over JTAG to rewrite it.

## (5) Crypto / AES (`devcfg.CTRL`)

| Attribute | Bits | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| PL AES engine | CTRL[11:9] AES_EN | 000 (off) | 111 (on) | Bitstream/partition encryption in use |
| AES key source | CTRL[12] AES_FUSE | BBRAM key | eFuse key | Where the decryption key lives |
| SEU lockdown | CTRL[8] SEU_EN | off | armed (SEU → lockdown) | Anti-fault-injection |

## (6) Config lock & TrustZone (SLCR)

| Attribute | Location | Dev value | Hardened | Why we care |
|---|---|---|---|---|
| SLCR write-protect | `slcr.LOCKSTA` `0xF800000C` bit 0 | unlocked | locked | Can system-control regs be rewritten |
| CFGSDISABLE | `slcr.APU_CTRL` `0xF8000300` bit 2 | clear | set → sys-ctrl + GIC writes locked (POR-clear) | TrustZone config freeze |
| CP15SDISABLE | `slcr.APU_CTRL` bits 1:0 | clear | set → CP15 writes locked per-core | Per-core control freeze |
| DMAC TrustZone | `slcr.TZ_DMA_NS` `0xF8000440` bit 0 | secure | non-secure | Which world owns the DMAC |
| DMAC peripheral TZ | `slcr.TZ_DMA_PERIPH_NS` `0xF8000448` bits 3:0 | 0 (secure) | per-channel NS bits | Fine-grained DMAC partitioning |

---

## Verdict logic

The enumerator flags **HARDENING PRESENT** if *any* of: booted securely, an eFuse SECURE_EN/JTAG_DIS is
blown, the ARM DAP is bypassed, or the debug lock is set — else **ALL-OPEN dev baseline**. This dev board
reads all-open (the same baseline ZynqMP shows); the same script lights up a provisioned board, field by
field, against the table above.
