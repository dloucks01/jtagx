# OCM staging layout standard for A53 EL3 probe payloads

## TL;DR

New probe payloads should follow this OCM Bank-2 (`0xFFFE0000`–`0xFFFEFFFF`) layout:

```
0xFFFE0000 — 0xFFFE0FFF   Probe-specific staging (4 KB)
    Per-slot layout: each slot is N bytes describing one probe target.
    The handler reads slots; layout convention documented per payload.

0xFFFE1000 — 0xFFFE6FFF   Dump destination (24 KB)
    Used by methods that copy data out (M1/M2/M3/M4/M5 BootROM dumps).

0xFFFE7000 — 0xFFFE7FFF   Markers + harness scratch (4 KB)
    0xFFFE7000  Done marker (little-endian dword 0xCAFEC0DE)
    0xFFFE7004  Done marker upper word (0xCAFEBABE; legacy M1/M2 8-byte marker)
    0xFFFE7010  SCTLR_EL3 before (M2 uses this)
    0xFFFE7018  SCTLR_EL3 after  (M2 uses this)
    0xFFFE7030  ESR_EL3 save (fault registers, M1/M2 use these)
    0xFFFE7038  FAR_EL3 save
    0xFFFE7040  ELR_EL3 save
    0xFFFE7048  SPSR_EL3 save
    0xFFFE7080  Stage marker (advances 1, 2, 3, ... as probe progresses)
```

The address constants are in `openocd/dump-bootrom.tcl`:

```
ADDR_DUMP_DST              0xFFFE0000  (legacy — payloads using this overlap with staging area)
ADDR_DONE_MARKER           0xFFFE7000
ADDR_SCTLR_BEFORE          0xFFFE7010
ADDR_SCTLR_AFTER           0xFFFE7018
ADDR_ESR_EL3_SAVE          0xFFFE7030
ADDR_FAR_EL3_SAVE          0xFFFE7038
ADDR_ELR_EL3_SAVE          0xFFFE7040
ADDR_SPSR_EL3_SAVE         0xFFFE7048
ADDR_STAGE_START           0xFFFE7080
```

## Why standardize

Existing payloads use ad-hoc OCM layouts:
- `csu-write-probe.S` puts stage at 0xFFFE7080 + done at 0xFFFE7000 with random staging slots
- `csu-enumerate.S` uses 12 × 4-byte witness slots starting at 0xFFFE0000
- `csu-write-survey-v2.S` uses 12 × 12-byte slots starting at 0xFFFE0000
- `csu-sha-probe-v2.S` uses 6 × 16-byte snapshots starting at 0xFFFE0000
- `csu-pmu-ipi.S` uses an irregular mix at 0xFFFE0000..0xFFFE0070

Result: handler authors have to look up each payload's specific layout. Mistakes have caused mis-reads (handler reads OCM offset N expecting field X but the payload wrote field Y there).

## What the standard requires of new payloads

1. **Stage marker AT 0xFFFE7080.** Always. Increments as the payload progresses. Probe handlers poll it to determine progress when the probe doesn't reach the done marker.

2. **Done marker AT 0xFFFE7000.** Write `0xCAFEC0DE` at end (32-bit). If you also need the legacy 8-byte marker (M1/M2 compat), write `0xCAFEBABE` to `0xFFFE7004`.

3. **Probe-specific data in 0xFFFE0000..0xFFFE0FFF (slot region).** Document the slot layout at the top of the `.S` file. Use a comment block like:

   ```
   // OCM slot layout (12 bytes per slot):
   //   +0  baseline read
   //   +4  readback after write
   //   +8  readback after restore
   ```

4. **Don't overlap with the dump-destination region 0xFFFE1000..0xFFFE6FFF** unless the probe IS a BootROM dump. Existing probes accidentally use `0xFFFE0060+` which can collide if a dump method runs after the probe without a power-cycle.

## Legacy payloads (don't break, but don't propagate)

These predate the standard:

| Payload | Status |
|---|---|
| `bootrom-dump.S` (M1) | Uses standard markers; staging is at 0xFFFE0000 (dump dest); fine |
| `bootrom-dump-clean.S` (M2) | Same as M1; uses ESR/FAR/ELR/SPSR save slots in 0xFFFE7030+ |
| `bootrom-dump-r5.S` (M4) | R5-side payload; same marker contract |
| `csu-write-probe.S` (csu-probe) | Stage 0xFFFE7080, done 0xFFFE7000; rest ad-hoc |
| `csu-enumerate.S` | 12 × 4-byte slots at 0xFFFE0000 |
| `csu-write-survey.S` | Original 8-target sweep; 0xFFFE0000+ |
| `csu-write-survey-v2.S` | 12 × 12-byte slots — already follows the recommended slot convention |
| `csu-sha-probe.S` | 3 × 16-byte snapshots |
| `csu-sha-probe-v2.S` | 6 × 16-byte snapshots |
| `csu-dapcfg-set.S` | 4 metadata words at 0xFFFE0000 |
| `csu-pmu-ipi.S` | Irregular layout — most likely needing migration |
| `csu-pmu-wake-probe.S` | 3 + 3 metadata words |
| `csu-dma-from-a53.S` | DMA destination at 0xFFFE1000, metadata at 0xFFFE0000 (good: separated) |

When migrating an old payload to the standard:
1. Verify the handler still reads correctly after the change.
2. Add a test case in `tests/handler-verdicts.tcl` mocking the new OCM addresses.
3. Run `make` to rebuild the `.bin`.
4. Re-run `bash tools/tcl-smoketest.sh` to confirm no regressions.

## Why we're not retrofitting all old payloads now

Migration requires per-payload chip re-runs to confirm the new layout produces the same verdicts. Without chip access, the safest move is to:
1. Document the standard (this file)
2. Apply it to all NEW payloads going forward
3. Migrate old payloads opportunistically when they're touched for other reasons
