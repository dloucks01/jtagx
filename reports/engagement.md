# JTAG Engagement Report — ZCU102

- target: **ZCU102**   chip: **zynqmp** — Zynq UltraScale+ (ZynqMP) (Paradigm A)
- posture (enumerated): {'jtag_open': True, 'secure_boot': False}

## 1. Capabilities on this target
  - Cap-1: DRAM/RAM dump
  - Cap-1: flash dump
  - posture enumeration
  - debug reopen (software-hardened only)
  - Cap-2: live memory/function patch
  - Cap-3: reflash / persistence

## 2. Dumps captured
| file | size | md5 |
|---|---:|---|
| `boot-image-dma.bin` | 1,164,672 | `4cb3de072871cc66dad1fec8e83a75cc` |
| `boot-image-full.bin` | 11,534,336 | `03cb706239bfa9da3615f62ec0ac582d` |
| `boot-image.bin` | 11,534,336 | `03cb706239bfa9da3615f62ec0ac582d` |
| `boot.bin` | 12,582,912 | `655c18ceb4a2e9a2cbd4a4ef775ae45c` |
| `bootrom-via-pmu-r5-bootrom-2026-06-08-113330.bin` | 16,384 | `9fa5a7dc10d2971568ff7936b2093c7e` |
| `fuzz-base-min.bin` | 149,768 | `f98977a20b0c5aa6b2896c4b50fe0cb0` |
| `ocm-0xFFFC0000-128k-freshboot-2026-06-08-125258.bin` | 131,072 | `9e6962d129a7702ab6921e07bad8244c` |
| `os-live.bin` | 16,777,216 | `f3d5f90b7a732e25bbfcc81d44a98139` |
| `qspi-dma-auto.bin` | 4,096 | `fc91bf804878215ef94b8d468c98741d` |
| `qspi-dma-fix.bin` | 4,096 | `fc91bf804878215ef94b8d468c98741d` |
| `qspi-dma-lower.bin` | 4,096 | `a164a87255070edb107aae57fa7a504e` |
| `qspi-jtag-test.bin` | 65,536 | `6042d558a23dac4d79cc8f52466074f2` |
| `qspi-jtag-test2.bin` | 65,536 | `3728c3d670481789ce50302876ce50c7` |
| `speedtest.bin` | 262,144 | `88f4e6aa6d1ef729a7dbdd609fbaf22c` |
| `vxworks-live.bin` | 2,097,152 | `6d0bd91cbd1033369560591886fc4637` |

## 3. Analysis (dram-secrets + dump-triage)
### boot-image-dma.bin
```
## first-look verdict
```
secrets:
```
Heuristic — verify each before acting. CRIT/HIGH first.
```
### boot-image-full.bin
```
## first-look verdict
```
secrets:
```
**59 findings** — 4 CRIT, 55 MED
Heuristic — verify each before acting. CRIT/HIGH first.
- **[CRIT]** `0x00841221`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.2 e=192.168.1.6:ffffff00 g=192.168.1.1 u=target pw=vxTarget`
- **[CRIT]** `0x00841269`  boot user/password: `u=target  pw=vxTarget`
- **[CRIT]** `0x0097e8c0`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.20 e=192.168.1.10:ffffff00 u=ultraNP pw=ultraNP f=0x0`
- **[CRIT]** `0x0097e8fc`  boot user/password: `u=ultraNP  pw=ultraNP`
```
### boot-image.bin
```
## first-look verdict
```
secrets:
```
**59 findings** — 4 CRIT, 55 MED
Heuristic — verify each before acting. CRIT/HIGH first.
- **[CRIT]** `0x00841221`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.2 e=192.168.1.6:ffffff00 g=192.168.1.1 u=target pw=vxTarget`
- **[CRIT]** `0x00841269`  boot user/password: `u=target  pw=vxTarget`
- **[CRIT]** `0x0097e8c0`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.20 e=192.168.1.10:ffffff00 u=ultraNP pw=ultraNP f=0x0`
- **[CRIT]** `0x0097e8fc`  boot user/password: `u=ultraNP  pw=ultraNP`
```
### boot.bin
```
## first-look verdict
```
secrets:
```
**59 findings** — 4 CRIT, 55 MED
Heuristic — verify each before acting. CRIT/HIGH first.
- **[CRIT]** `0x00841221`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.2 e=192.168.1.6:ffffff00 g=192.168.1.1 u=target pw=vxTarget`
- **[CRIT]** `0x00841269`  boot user/password: `u=target  pw=vxTarget`
- **[CRIT]** `0x0097e8c0`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.20 e=192.168.1.10:ffffff00 u=ultraNP pw=ultraNP f=0x0`
- **[CRIT]** `0x0097e8fc`  boot user/password: `u=ultraNP  pw=ultraNP`
```
### bootrom-via-pmu-r5-bootrom-2026-06-08-113330.bin
```
## first-look verdict
```
secrets:
```
Heuristic — verify each before acting. CRIT/HIGH first.
```
### fuzz-base-min.bin
```
## first-look verdict
```
secrets:
```
Heuristic — verify each before acting. CRIT/HIGH first.
```

## 4. Known issues — CVEs / published attacks / posture
- **[verify]** MED `Cautionary-GHASH` — AES-GCM IV/GHASH weakness in the boot AES (a cautionary-note class issue)  *(ref: docs/15)*
- **[APPLIES]** MED `ZU+EM-SCA` — ZynqMP electromagnetic side-channel on the boot AES key (physical access)  *(ref: docs/15)*
- **[posture]** HIGH — JTAG/DAP is OPEN and not eFuse-disabled — full debug compromise: halt, dump RAM/flash, patch a running auth check (Cap-1/2/3). The DAP *is* the trust boundary.
- **[posture]** HIGH — Secure boot is OFF — the BootROM accepts an unsigned/unencrypted image. repack-bootimage.py a patched BOOT.bin and reflash for a persistent implant.

## 5. Recommended next steps
- Run `tools/board-runner.py --profile zynqmp` for the full step-by-step plan.
- Defeat an auth/license check: `patch-recipe.py` → `probe-phys-patch.tcl` (Cap-2).
- For persistence: patch + `repack-bootimage.py` → reflash (Cap-3, DESTRUCTIVE).
- Confirm any **[verify]** issue above by reading the relevant posture register (enumerate step).

> All findings here are from the chip + posture supplied; profiles other than ZynqMP are HW-unvalidated (vendor-doc-cited + audited). Confirm on the live target.
