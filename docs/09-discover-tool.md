# discover.tcl — The First-Contact Chain Probe

This document explains what `openocd/discover.tcl` does, what it
reads from the chip, when to use it, and how it fits with the other
tools in the workflow.

## What it is

A small Tcl script (~190 lines) that runs inside an OpenOCD session
and reports what's on the JTAG chain in a human-readable format. It is
**family-agnostic** — it works on any chip, not just ZynqMP.

Think of it as: `ifconfig` for the JTAG chain. It tells you what's
connected; it doesn't decode the device's internal state.

## When to use it

| Scenario | Use discover? |
|---|---|
| First time on an unfamiliar board, want to see what's responding | Yes |
| Sanity-check after changing OpenOCD interface or target configs | Yes |
| Investigating "is the JTAG chain alive at all?" | Yes |
| Already have a working board config, want the full SoC enumeration | **No — use `enumerate.tcl`** |
| Generating documentation of the board's debug topology | Yes (for the AP list) |

`discover.tcl` is an optional sanity check: run it before `enumerate.tcl`
to confirm the JTAG chain (TAPs, IDCODEs, APs) matches what you expect
for the board in front of you, so you don't trust an enumeration taken
against a mis-declared chain.

## How to run it

Against the board config:

```
openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"
```

Runtime: under a second after OpenOCD init completes.

## What it actually reads from the chip

Three things, in order:

### 1. TAP enumeration (no chip reads — purely OpenOCD metadata)

```
[jtag names]
```

This is a query to the OpenOCD runtime, not a JTAG transaction. It
returns the list of TAPs that the loaded target config declared. For
a ZCU102 with `target/xilinx_zynqmp.cfg`:

```
uscale.tap        (ARM CoreSight DAP, IRLen 4)
uscale.ps         (Xilinx PS-TAP, IRLen 12)
```

The TAP IDCODEs themselves come from OpenOCD's `init` (which already
ran before discover started) — they appear in lines like:

```
Info : JTAG tap: uscale.tap tap/device found: 0x5ba00477 (mfg: 0x23b (ARM Ltd), part: 0xba00, ver: 0x5)
Info : JTAG tap: uscale.ps  tap/device found: 0x24738093 (mfg: 0x049 (Xilinx), part: 0x4738, ver: 0x2)
```

Discover doesn't re-read the IDCODEs; it relies on these init lines
appearing in the OpenOCD log above its output.

### 2. Access Port (AP) enumeration

For each DAP object, discover walks `AP 0` through `AP 7` and reads
each one's IDR register (offset `0xFC`):

```tcl
catch { $dap dpreg 0 0x1e } _   ;# clear sticky errors first
for {set ap 0} {$ap < 8} {incr ap} {
    set idr [$dap apreg $ap 0xFC]
    # decode class (bits 16:13) and type (bits 3:0)
}
```

For each AP that responds with a non-zero IDR, discover decodes:

| Field | What it tells you |
|---|---|
| **AP class** (bits 16:13) | `8` = MEM-AP (memory access), `0` = JTAG-AP (CoreSight) |
| **AP type** (bits 3:0) | `1` = AHB3, `2` = APB2/3, `4` = AXI3/AXI4, `5` = AHB5, `6` = APB4/5, `7` = AXI5 |
| **Designer ID** (bits 27:17) | Usually ARM (`0x23B`) — the AP IP designer |

On a typical ZynqMP board you'll see:

```
  AP 0: IDR = 0x44770002  designer=0x23b  class 8 = MEM-AP  type 2 = APB2 or APB3 (debug-register access)
  AP 1: IDR = 0x44770002  designer=0x23b  class 8 = MEM-AP  type 2 = APB2 or APB3 (debug-register access)
  AP 2: IDR = 0x24770004  designer=0x23b  class 8 = MEM-AP  type 4 = AXI3/AXI4 (memory access)
```

The combination tells you which debug paths are exposed:
- AP for APB → CoreSight debug registers (per-core Debug Units, CTI, ETM, PMU)
- AP for AXI → main memory bus (DDR, OCM, peripherals)
- AP for AHB → alternative memory access path (older designs)

### 3. Family identification + next-step suggestion

A pattern-match on the TAP name list:

```tcl
foreach name $tap_names {
    if {[string match "*uscale*" $name]} { set is_zynqmp 1 }
    if {[string match "*zynq7*" $name]}  { set is_zynq7 1 }
    if {[string match "*versal*" $name]} { set is_versal 1 }
}
```

If ZynqMP: prints the command to run the full enumeration.
If Zynq-7000: warns that `enumerate.tcl` won't work as-is.
If Versal: warns about Versal's different architecture.
If unknown: suggests how to look up the chain via JEP106 manufacturer
codes.

For interactive use, you can also call:

```
describe_idcode 0x24738093
```

to decode any IDCODE manually. This goes through
`openocd/lib/idcode-lookup.tcl`, which itself consults the variant
table in `openocd/lib/zynqmp-variants.tcl` for ZynqMP/RFSoC part
identification.

## What it does NOT do

Critical to understand:

- **It does not read any SoC register.** No CSU, eFUSE, PMU, clock,
  or power-state reads. AP IDR reads are debug-port-level only.
- **It does not detect the specific variant** (ZU9 vs ZU5 vs ZU28DR).
  That requires reading `CSU_IDCODE` and looking up the PART_ID
  against the variant table — which is `enumerate.tcl`'s job in §2.
- **It does not modify state.** No writes. Pure passive enumeration.
- **It does not capture a CoreSight ROM walk.** That would require
  reading each AP's memory space to enumerate components, which
  discover doesn't do today.

## Sample output

Against a ZCU102 in JTAG-idle mode:

```
================================================================
 JTAG CHAIN DISCOVERY
================================================================

IDCODEs were printed by OpenOCD init above this output. Look for
lines like:
    Info : JTAG tap: NAME tap/device found: 0x........

To decode any IDCODE interactively, run from this Tcl shell:
    describe_idcode 0x<value>

----------------------------------------------------------------
 TAPs defined in current OpenOCD target config
----------------------------------------------------------------

Count: 2
  - uscale.tap
  - uscale.ps

----------------------------------------------------------------
 ACCESS PORTS (APs) visible on each DAP
----------------------------------------------------------------

DAP: uscale.dap
  AP 0: IDR = 0x44770002  designer=0x23b  class 8 = MEM-AP  type 2 = APB2 or APB3 (debug-register access)
  AP 1: IDR = 0x44770002  designer=0x23b  class 8 = MEM-AP  type 2 = APB2 or APB3 (debug-register access)
  AP 2: IDR = 0x24770004  designer=0x23b  class 8 = MEM-AP  type 4 = AXI3/AXI4 (memory access)

================================================================
 SUGGESTED NEXT STEPS
================================================================

▸ Detected ZynqMP target config (TAPs named uscale.*)

  Cross-reference the PS-TAP IDCODE from the init log with:
      describe_idcode 0x........

  Run the full enumeration:
      openocd -f openocd/zcu102.cfg \
              -c "init; source openocd/enumerate.tcl"
================================================================
```

## How discover fits with the rest of the workflow

```
1. openocd -f openocd/zcu102.cfg -c "init; source openocd/discover.tcl; shutdown"
   └─ Verifies the chain (TAPs/IDCODEs/APs) matches expectation  ←─── (this script)
                    ↓
2. openocd -f openocd/zcu102.cfg -c "init; source openocd/enumerate.tcl; shutdown"
   ├─ §1-12: full ZynqMP SoC state with QEMU-verified bit layouts
   └─ Saves a markdown report to reports/
```

Discover is the optional validation step before enumerate's deep probing.

## Limitations and planned improvements

**Today:** discover's output goes to stdout only. Nothing consumes it
programmatically. It exists purely for humans.

**Planned (task #35 in the backlog):** discover will write a structured
file (`openocd/last-discovered.tcl`) with the family, IDCODE, TAP
list, and AP enumeration table. `enumerate.tcl` could source that file
and produce a new "AP topology" section — which APs are exposed is a
useful characterization datum (a hardened device may gate some APs that
are visible on a dev kit).

**Today:** discover doesn't do a CoreSight ROM walk. Each AP could be
probed for its ROM table to enumerate every CoreSight component
(per-core Debug Units, CTIs, PMUs, ETMs, trace funnels, TMCs, TPIU,
STM). That richer enumeration is in `enumerate.tcl` §10 today (via
`uscale.dap info 1`), but its output goes to stdout only — it doesn't
land in the report file. Folding this into the discover pipeline
would make CoreSight topology a structured artifact.

## See also

- [`05-enumeration-tool.md`](05-enumeration-tool.md) — `enumerate.tcl`, the next-step tool after discover
- [`whitepaper/lab-setup.md`](whitepaper/lab-setup.md) — OpenOCD install + lab setup
