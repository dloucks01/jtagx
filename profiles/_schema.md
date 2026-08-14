# Board-profile schema (v1)

A **profile** is a pure-DATA fact-sheet for one chip/SoC. It contains **no logic** — it only
*describes* the chip so the fixed runner (`tools/board-runner.py`) knows which pre-written scripts to
invoke and with what parameters. Adding support for a new board = writing one of these files. **You
never edit the runner to add a board.** (See `docs/22-multiboard-capability-matrix.md` for the model.)

Format: **JSONC** — plain JSON, except a line whose first non-space characters are `//` or `#` is a
comment and is stripped before parsing. (Don't put `//` inside a value; full-line comments only.)

Profiles live in `profiles/*.json` (one per chip). `profiles/_*.json` and `_schema.md` are ignored by
the loader. Validate the whole registry offline with:

```
python3 tools/board-runner.py --validate
```

## Fields

```jsonc
{
  "schema_version": 1,                  // required, == 1
  "name": "Zynq UltraScale+ (ZynqMP)",  // required, human label
  "soc": "zynqmp",                      // required, short slug
  "paradigm": "A",                      // required, one of A/B/C/D/E (see docs/22)
  "status": "complete",                 // "complete" | "partial" | "stub" — honesty about coverage
  "auto_match": true,                   // optional (default true). false = NEVER auto-selected by
                                        // fingerprint; selectable only via `--profile <soc>`. Use for
                                        // boards that can't be told apart by IDCODE (Pi = generic ARM
                                        // DAP; IGLOO2 = no decoder).

  // --- Tier-1 match: how the runner recognizes this chip from a JTAG chain fingerprint ---
  "match": {
    "family": "zynqmp",                 // required; matched against the decoded IDCODE family
                                        //   (arm | zynqmp | zynq7 | versal | unknown — see gen-board-cfg.decode_idcode)
    "part_ids": [],                     // optional hex part-field strings, e.g. ["0x4738"]; [] = any part in the family
    "min_taps": 2                       // optional; minimum IDCODEs in the chain
  },

  "openocd_cfg": "openocd/zcu102.cfg",  // the board cfg the live steps use (null = use a generic/template cfg)

  // --- capability blocks. Any block may be null = "not implemented for this profile yet"
  //     (the runner skips it and records the gap — that's a 'partial' profile). ---
  "access_check": "openocd/jtag-access-check.tcl",   // the universal OPEN/LOCKED verdict (Paradigm A/B/E)

  // enumerate: security-posture read (chip-specific register KB). Either a bare script string (its
  // output feeds interpret.py), or an object {script, interpret} where interpret:false = the script
  // just prints a snapshot (no interpret.py step). null = no posture read for this SoC.
  "enumerate": "openocd/enumerate.tcl",
  // ...or:  "enumerate": { "script": "openocd/zynq7000-enumerate.tcl", "interpret": false },

  "dump": {
    "dram":  { "script": "openocd/dump-os-ddr.tcl", "addr": "0x00000000", "size": "0x80000000",
               "sparse": true, "out": "dumps/os-live.bin" },           // null if the chip has no DRAM-over-JTAG (Paradigm B/D)
    // flash is fully env-driven so each SoC's own dumper works: "env" is the exact VAR=value set the
    // script reads; "out" names the dumped file for the analysis steps; "note" is shown in the plan.
    "flash": { "script": "openocd/qspi-jtag.tcl", "out": "dumps/boot.bin", "note": "Fast GQSPI DMA dumper.",
               "env": { "QSPI_OP": "dmadump", "QSPI_SIZE": "0xC00000", "QSPI_OUT": "dumps/boot.bin" } }  // null = no driver yet
  },

  "reopen": ["openocd/reopen-debug.tcl"],   // ordered levers tried when the verdict is LOCKED-but-mutable. [] = none.

  // optional: honest per-capability reason a block is absent, shown in the plan's gap list INSTEAD of the
  // generic "not implemented yet" message. Use it to say BY-DESIGN (e.g. "owned by the VideoCore") vs a real
  // TODO. Keys: "flash" | "enumerate" | "reopen".
  "absent": { "flash": "owned by the closed VideoCore GPU — not on the ARM JTAG" },

  // Cap-2 live patch. pa_math: linear|virt2phys. "env" carries any extra vars (e.g. the SoC's target
  // names PATCH_CORE/PATCH_AXI/PATCH_DAP for a non-ZynqMP part). null = not applicable (Paradigm D).
  "patch": { "script": "openocd/probe-phys-patch.tcl", "pa_math": "linear", "kva_lo": "0x80000000",
             "env": {} },

  // Cap-3 WRITE / persistence (DESTRUCTIVE). "repack":true => the dumped flash is a bootgen image, so the
  // runner emits an OFFLINE repack-bootimage.py step. "script" => a live reflash script (Cortex-M via
  // OpenOCD's flash driver); "env" its vars. If no script, "note" describes the method (ZynqMP: SD/U-Boot).
  "reflash": { "repack": false, "script": "openocd/cortexm-flash.tcl", "env": { "CMF_FILE": "patched.bin" },
               "note": "Reflash internal flash. DESTRUCTIVE; part must be unlocked." },

  "analysis": [                                // OFFLINE (safe) post-processing of the dumps
    { "tool": "tools/parse-bootimage.py", "on": "flash" },
    { "tool": "tools/dram-secrets.py",    "on": "dram"  },
    { "tool": "tools/vxworks-symtab.py",  "on": "flash" }
  ],

  "ghidra": "auto",         // "auto" = derive language+base from the bytes via tools/ghidra-loadspec.py
                            // (recommended), OR an object {"language":"AARCH64:LE:64","base":"0x..."}.

  // PARADIGM D ONLY (FPGA, no CPU): the vendor-tool handoff. When paradigm=="D", the runner emits an
  // identify step + this handoff INSTEAD of dump/patch (those don't exist on a programming TAP).
  "vendor": {
    "tool": "Microchip FlashPro Express",
    "cmd":  "# one-line how-to-launch",
    "note": "why there's no memory capability",
    "steps": ["ordered operator steps ..."]
  }
}
```

## Per-board adapter allowlist (`adapters`)

Optional list describing **which adapters can reach this chip and how far**. Board-independent
adapter facts (backend, driver, transports) live in `docs/transport/adapter-catalog.md`; this
per-board list records the subset valid for this silicon **plus the access tier each reaches on it**.
Be comprehensive — list all plausible adapters, not just what the current milestone needs. Discovery
tools (JTAGulator) are board-independent and precede adapter selection, so they are NOT listed here.

```jsonc
"adapters": [
  { "id": "jlink",               // required; short slug, unique within the list
    "name": "SEGGER J-Link",     // human label
    "backend": "openocd",        // required: openocd | hw_server | libero | bmp | vendor | discovery
    "driver": "jlink",           // OpenOCD driver name when backend=="openocd", else null
    "transports": ["swd","jtag"],// subset of: jtag | swd | cjtag | spi | boundary-scan
    "usb_ids": ["1366:0101"],    // "vid:pid" strings for auto-detect ([] if unknown/many)
    "tier": "e",                 // required: reachable tier a..e ON THIS silicon (ladder below)
    "vendor_sw": false,          // true if it needs vendor software (hw_server / Libero / …)
    "note": "…" }
]
```

**Access-tier ladder** (what "talk out" reaches): `a` IDCODE/chain → `b` boundary-scan →
`c` mem-AP (memory/regs) → `d` run-control (halt/resume/breakpoints) → `e` exploitation
(dump/patch/keys). The tier is a property of *(backend, silicon)* — e.g. a J-Link reaches `e` on a
Cortex-M/-A SoC but a FlashPro reaches only `b` (+program) on a Microsemi FPGA programming TAP.
The validator (`--validate`) checks each entry has `id`/`backend`/`tier`, backend is in the vocab,
and tier is `a`–`e`.

## Paradigm-D profiles (FPGA / no CPU)

A Paradigm-D profile (IGLOO2, Lattice, bare FPGA) has **no** `dump`/`patch`/`reopen` — there is no
memory bus on a programming TAP. It carries `vendor` (above) and usually `access_check` pointed at an
identify script (e.g. `discover.tcl`). The runner renders it as: identify → `[VENDOR]` handoff →
"no memory capability" gap. Recognized FPGA *manufacturers* (Lattice/Altera) auto-land in Tier-3's
generic vendor handoff; a specific part with no reliable IDCODE decoder (IGLOO2) uses `--profile`.

## How a profile maps to the three tiers (docs/22)

- A chip with a **matching profile** runs at **Tier 1** — everything the profile defines.
- A chip with **no matching profile** but a probe-detected Paradigm-A mem-AP runs at **Tier 2**
  (generic: access-check + DRAM dump + offline analysis + generic patch) — *no profile needed because
  those steps probe rather than look up.* Authoring a profile **promotes Tier 2 → Tier 1**.
- A chip with no usable AP (or a vendor FPGA TAP) runs at **Tier 3** — identify + report only.

A `"status": "partial"` profile is recognized at Tier 1 but has some capability blocks `null`; the
runner runs what's defined and prints the gaps as "not yet implemented for <soc>".
