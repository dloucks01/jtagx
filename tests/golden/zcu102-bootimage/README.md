# Golden boot-image fixture — real ZCU102 BOOT.BIN (header region)

`boot-partial-64k.bin` is the **first 64 KB of the actual `BOOT.BIN`** from board
**210308BD8D4D**'s SD card (its PetaLinux dev build), captured 2026-06-08.

- size: 65536 bytes · sha256: `3a03155734bfcf8423129f2213a1c65abd606ae9bc8990de30efb80f79f5f39c`
- **Header region only** — boot header + Image Header Table + Partition Header Table
  all live in this range; the partition *payloads* (FSBL/PMUFW/ATF/U-Boot/bitstream
  binaries) are intentionally truncated. `tools/parse-bootimage.py` only reads the
  header structures, so this is a complete fixture for boot-posture analysis.
- **Provenance:** pulled over the PS-UART (`ttyUSB0`) when the board had no SD reader
  and no network — board shell driven from Kali, `od -A n -t x1 -v -N 65536` hex over
  serial, decoded with `bytes.fromhex`. Integrity is self-proving: every bootgen
  word-checksum (boot header `0xFD15B7F1`, IHT `0xFEFDF979`, all 6 partition headers)
  validates, so the transfer was bit-perfect.
- **No secrets:** the image is unencrypted (`encryptionKeySource=0`), so the boot-header
  key/IV fields are all zero; no device-unique material is present.

## What it documents (this board's real boot posture)
6 partitions, **all `plain+noauth`** (no encryption, no authentication); IHT
`headerAC=0` (headers unauthenticated): [0] PS-EL3 FSBL · [1] **PL bitstream** ·
[2] PS-EL3-TZ PMUFW · [3] PS-EL3-TZ ATF · [4] PS-EL3 · [5] PS-EL2 U-Boot. This is the
expected zero-protection posture of an unsigned dev build and the diff baseline for a
hardened board.

## Files
- `boot-partial-64k.bin` — the fixture.
- `parse-structural.golden` — frozen deterministic parse output (boot header + IHT + PHT
  facts), diffed by `tests/test-bootimage.sh`. Regenerate after an intentional parser
  change with: `python3 tools/parse-bootimage.py boot-partial-64k.bin | sed '/== Posture findings ==/,$d' > parse-structural.golden`
