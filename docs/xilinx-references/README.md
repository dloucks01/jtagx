# Xilinx reference documentation — local cache

Local copies of Xilinx/AMD reference documentation used during this project's
research. Downloaded 2026-05-28 to support PUF investigation and security
finding documentation.

## Files

| File | Size | Source |
|---|---|---|
| `ug1085.pdf` | 19 MB | Zynq UltraScale+ Device TRM (UG1085 v1.8, Aug 2018) |
| `ug1085-ch12-security-puf.txt` | 55 KB | Extracted ch.12 (Security) including PUF section |
| `ug1137.pdf` | 5.5 MB | Zynq UltraScale+ MPSoC Software Developers Guide (UG1137, 2020.1) |
| `ug1137-puf-sections.txt` | 57 KB | Extracted PUF API sections |
| `xilskey/xilskey_eps_zynqmp_puf.c` | 35 KB | xilskey PUF programming implementation |
| `xilskey/xilskey_eps_zynqmp_puf.h` | 4.7 KB | xilskey PUF constants & API |
| `xilskey/xilskey_eps_zynqmp_hw.h` | 42 KB | xilskey hardware register definitions |
| `xilsecure/xsecure_aes.c` | 55 KB | xilsecure AES engine driver |
| `xilsecure/xsecure_aes.h` | 10 KB | xilsecure AES API |

## Why these were captured

The PUF investigation (see `memory/project_puf_extractable_via_jtag.md`)
required protocol-level details about:
- PUF_CMD command values (REGISTRATION = 1, REGENERATION = 4 — NOT bit-encoded)
- PUF_CFG0_INIT_VAL = 2
- PUF_SHUTTER_VALUE = 0x0100005E
- PUF_STATUS.SYN_WRD_RDY bit position (bit 0)
- CSU.ISR.PUF_ACC_ERROR mask (bit 12)
- Helper data layout (12 syndrome words + CHASH + AUX = ~440 bits)

The Xilinx public PDFs are too large for WebFetch's 10MB cap, so the
relevant ones were downloaded locally for direct grep/sed extraction.

## Provenance

- UG1085 from mirror `0x04.net/~mwk/xidocs/ug/` (Xilinx official URL returned
  HTML preview rather than the PDF)
- UG1137 from `users.ece.utexas.edu/~mcdermot/arch/articles/Zynq/`
- xilskey + xilsecure source files from `github.com/Xilinx/embeddedsw` master

All files are public Xilinx/AMD documentation. Cached locally only to
support this research project; no redistribution.

## Usage

```bash
# Search for PUF references across all docs:
grep -rni "puf" docs/xilinx-references/ --include="*.txt" --include="*.h"

# Extract a specific UG1085 section:
pdftotext -layout docs/xilinx-references/ug1085.pdf - | sed -n '13407,14400p'

# Verify register addresses against canonical Xilinx headers:
grep "PUF_CMD\|PUF_CFG0" docs/xilinx-references/xilskey/xilskey_eps_zynqmp_hw.h
```
