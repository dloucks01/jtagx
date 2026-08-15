#!/usr/bin/env python3
"""bootrom-fuzz-triage.py — diff each BootROM-fuzz trial's reaction fingerprint against the
0000-baseline and rank anomalies, so the interesting parser reactions surface from a manual
flash/boot/observe campaign.

Inputs:
  - the FUZZ_FP log produced by openocd/bootrom-fuzz-observe.tcl (reports/bootrom-fuzz.log)
  - the corpus manifest.json from bootrom-fuzz-gen.py (maps trial id -> mutated field + hypothesis)

What the signals mean:
  MULTIBOOT changed  -> BootROM detected the bad field and searched for a golden image = the field
                        IS validated/rejected (a "clean reject" — lower interest, but informative).
  FT_STATUS changed  -> CSU triple-redundancy fault — the parser may have CRASHED (HIGH interest).
  DAP wedge          -> BootROM hung in an anomalous state (HIGH interest).
  OCM content changed-> different data staged at 0xFFFC0000 — a copy landed somewhere unexpected;
                        combined with a fault, this is the memory-corruption JACKPOT (chase it:
                        full-dump OCM and check for ROM content).

Usage: python3 tools/bootrom-fuzz-triage.py reports/bootrom-fuzz.log fuzz-corpus/manifest.json
"""
import json, re, sys

FIELDS = ["CSU_STATUS", "MULTIBOOT", "FT_STATUS", "BOOT_MODE", "OCM_SUM",
          "OCM_W0", "OCM_W1", "OCM_W2", "OCM_W3", "DAP"]


def parse_log(path):
    trials = {}
    line_re = re.compile(r"FUZZ_FP\s+id=(\S+)\s+(.*)")
    for ln in open(path):
        m = line_re.search(ln)
        if not m:
            continue
        tid, rest = m.group(1), m.group(2)
        kv = dict(re.findall(r"(\w+)=(\S+)", rest))
        trials[tid] = kv
    return trials


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: bootrom-fuzz-triage.py <fuzz.log> <manifest.json>")
    try:
        trials = parse_log(sys.argv[1])
    except OSError as e:
        sys.exit(f"error: cannot read the fuzz log {sys.argv[1]!r}: {e}")
    try:
        with open(sys.argv[2]) as fh:
            manifest_raw = json.load(fh)
    except OSError as e:
        sys.exit(f"error: cannot read the manifest {sys.argv[2]!r}: {e}")
    except json.JSONDecodeError as e:
        sys.exit(f"error: {sys.argv[2]!r} is not valid JSON: {e}")
    manifest = {str(e["id"]): e for e in manifest_raw}

    if "0" not in trials:
        sys.exit("no baseline (id=0) fingerprint in the log — boot 0000-baseline.bin and observe it first.")
    base = trials["0"]

    rows = []
    for tid, fp in trials.items():
        if tid == "0":
            continue
        changed = [f for f in FIELDS if fp.get(f) != base.get(f)]
        ocm_changed = any(c.startswith("OCM_") for c in changed)
        ft_changed = "FT_STATUS" in changed
        wedge = fp.get("DAP") == "wedge" and base.get("DAP") != "wedge"
        multiboot = "MULTIBOOT" in changed

        if ocm_changed and (ft_changed or wedge):
            interest, verdict = 0, "JACKPOT? mem-corruption: OCM changed + CSU fault/wedge"
        elif wedge:
            interest, verdict = 1, "HIGH: DAP wedge (BootROM hung anomalously)"
        elif ft_changed:
            interest, verdict = 1, "HIGH: CSU FT_STATUS changed (possible parser crash)"
        elif ocm_changed:
            interest, verdict = 2, "HIGH: OCM content changed (unexpected staged data)"
        elif multiboot:
            interest, verdict = 3, "INFO: MULTIBOOT changed (field validated -> clean reject)"
        elif changed:
            interest, verdict = 4, "INFO: minor status diff (" + ",".join(changed) + ")"
        else:
            interest, verdict = 5, "normal (no observable effect)"

        man = manifest.get(tid, {})
        rows.append((interest, tid, man.get("region", "?"), man.get("field", "?"),
                     man.get("new", "?"), verdict, ",".join(changed) or "-", man.get("hyp", "")))

    rows.sort(key=lambda r: (r[0], int(r[1]) if r[1].isdigit() else 1 << 30))

    labels = {0: "JACKPOT", 1: "HIGH", 2: "HIGH", 3: "INFO", 4: "INFO", 5: "normal"}
    counts = {}
    print(f"\nBootROM-fuzz triage — {len(rows)} trials vs baseline (id=0)\n" + "=" * 78)
    for interest, tid, region, field, new, verdict, changed, hyp in rows:
        counts[labels[interest]] = counts.get(labels[interest], 0) + 1
        if interest <= 3:  # show JACKPOT/HIGH/INFO-multiboot; hide pure-normal noise
            print(f"[{labels[interest]:7}] #{tid:>4} {region}.{field}={new}")
            print(f"           {verdict}")
            if changed != "-":
                print(f"           changed: {changed}")
            if hyp:
                print(f"           hyp: {hyp}")
    print("=" * 78)
    print("summary: " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    jp = [r for r in rows if r[0] == 0]
    if jp:
        print("\n>>> Chase the JACKPOT trial(s): re-flash, full-dump OCM (openocd dump-memory 0xFFFC0000 0x20000),")
        print("    and check the dump for ROM content (compare a SHA-3-384 over a 128KB-aligned region to ROM_DIGEST).")
    else:
        print("\nNo jackpot. HIGH rows (FT_STATUS/DAP/OCM) are still worth a manual OCM dump; INFO/MULTIBOOT = field rejected cleanly.")


if __name__ == "__main__":
    main()
