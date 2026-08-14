# dump-os-ddr.tcl — dump a live memory range (the running OS, OCM/FSBL, any region) from the
# target over JTAG via the AXI-AP (mem-AP). Pure-JTAG, non-destructive, works WHILE an OS runs.
#
# This is the "dump the OS" capability: on an engagement you arrive blind, so you read the live
# image straight out of DRAM. Use it to recover the running kernel for offline analysis, to feed
# the live-patch path (find a function -> probe-phys-patch), or to grab OCM (where the FSBL runs).
# Note: DRAM holds the *loaded/decompressed* OS — for the reflashable flash artifact use
# dump-boot-flash.tcl instead.
#
# Parameters via environment (ZCU102/VxWorks-friendly defaults):
#   DUMP_ADDR   start address           (default 0x00000000 — base of DDR)
#   DUMP_SIZE   bytes to read           (default 0x02000000 = 32 MB)
#   DUMP_CHUNK  words per read_memory   (default 4096 = 16 KB; keep <=4096 — >16 KB reads wedge.
#               16 KB = the max safe chunk, halves round-trips vs the old 8 KB; bench-validated at 15 MHz)
#   DUMP_LABEL  short name for the file (default os-ddr)
#   DUMP_OUT    output path             (default dumps/<label>.bin)
#   DUMP_SPARSE 1 = skip all-zero blocks (probe each block; only read non-zero) — for "capture
#               everything" over a huge mostly-zero DDR without paying JTAG time for the zeros. The
#               output is a SPARSE file of the full SIZE (holes read as 0; addresses preserved).
#   DUMP_PROBE_BLK  sparse probe granularity (default 0x100000 = 1 MB; smaller = denser, safer, slower)
#
#   # capture the whole low 2 GB of DDR, skipping the zeros (only the used RAM costs JTAG time):
#   DUMP_ADDR=0x0 DUMP_SIZE=0x80000000 DUMP_SPARSE=1 DUMP_LABEL=ddr-full \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"
#
# Examples (operator runs these):
#   # 32 MB from base of DDR (catches a low-loaded kernel)
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"
#   # the VxWorks kernel region (loads at 0x100000), 16 MB, named
#   DUMP_ADDR=0x00100000 DUMP_SIZE=0x01000000 DUMP_LABEL=vxworks-ddr \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"
#   # on-chip RAM (FSBL executes here): 256 KB at top-of-OCM
#   DUMP_ADDR=0xFFFC0000 DUMP_SIZE=0x00040000 DUMP_LABEL=ocm \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/dump-os-ddr.tcl; shutdown"

set _d [file dirname [info script]]
if {[info commands say] eq ""} { proc say {l} { echo $l } }
source [file join $_d lib dump-memory.tcl]

proc _envd {name def} { if {[info exists ::env($name)]} { return $::env($name) } ; return $def }
set ADDR  [_envd DUMP_ADDR  0x00000000]
set SIZE  [_envd DUMP_SIZE  0x02000000]
set CHUNK [_envd DUMP_CHUNK 4096]
set LABEL [_envd DUMP_LABEL os-ddr]
set OUT   [_envd DUMP_OUT   ""]
if {$OUT eq ""} { set OUT [file join $_d .. dumps "${LABEL}.bin"] }
# Target/DAP names are auto-detected (+ boards/<soc>.env) by board-profile.tcl — not board-hardcoded.
source [file join $_d board-profile.tcl]

# DUMP_HALT=1 freezes the CPU cores first so the AXI-AP read of a RUNNING SMP OS's DRAM doesn't
# collide with live cache-coherency traffic (which can HANG the read, not just fail it). Cores are
# detected by name (a53/a72/cpu) so this stays board-general. Resumed after the dump (best-effort).
set HALT [_envd DUMP_HALT 0]
set _cores [list]
if {$HALT ne "0"} {
    if {![catch {target names} _ts]} {
        foreach c $_ts {
            if {[string match {*a53*} $c] || [string match {*a72*} $c] || [string match {*cpu*} $c]} {
                catch { targets $c; halt } _
                lappend _cores $c
            }
        }
    }
    after 50
    say "DUMP_HALT: froze [llength $_cores] core(s): $_cores"
}

# Select the AXI mem-AP, examine it, and clear any sticky DP error before we start.
catch { targets $AXI_TARGET } _
catch { $AXI_TARGET arp_examine } _
for {set i 0} {$i < 3} {incr i} { catch { $DAP_NAME dpreg 0 0x1e } _ ; after 5 }

say ""
say "================================================================"
say " DUMP MEMORY (live, via AXI-AP)"
say "================================================================"
say [format " %-12s %08X" addr  $ADDR]
say [format " %-12s %X bytes" size $SIZE]
say " out          $OUT"

# DUMP_SPARSE=1 -> skip all-zero blocks (probe each DUMP_PROBE_BLK; only read non-zero ones). The
# output is a SPARSE file of the full SIZE, so you can "capture everything" (e.g. all of DDR) without
# paying JTAG time for the zeros. DUMP_PROBE_BLK = probe granularity (default 1 MB; smaller = denser
# probing, fewer missed regions, more probe overhead).
set SPARSE [_envd DUMP_SPARSE   0]
set PROBE  [_envd DUMP_PROBE_BLK 0x100000]
if {$SPARSE ne "0"} {
    say [format " %-12s sparse (probe block 0x%X — skip all-zero blocks)" mode $PROBE]
    set res [dump_memory_sparse $ADDR $SIZE $PROBE $CHUNK $OUT $LABEL]
    set meta [dict create source_addr [format 0x%08X $ADDR] size_bytes $SIZE chunk_words $CHUNK \
        label $LABEL mode sparse probe_block $PROBE \
        bytes_read [dict get $res bytes_read] bytes_skipped [dict get $res bytes_skipped] \
        bytes_failed [dict get $res bytes_failed] blocks_kept [dict get $res blocks_kept] \
        blocks_skipped [dict get $res blocks_skipped]]
} else {
    set res [dump_memory $ADDR $SIZE $CHUNK $OUT $LABEL]
    set meta [dict create source_addr [format 0x%08X $ADDR] size_bytes $SIZE chunk_words $CHUNK \
        label $LABEL bytes_written [dict get $res bytes_written] \
        chunks_ok [dict get $res chunks_ok] chunks_failed [dict get $res chunks_failed]]
}
write_dump_metadata "${OUT}.json" $meta {}

# Resume any cores we halted (best-effort; an EL1 resume can throw a cpsr quirk — non-fatal, the
# dump is already saved; power-cycle the board afterward if the OS doesn't continue).
if {$HALT ne "0" && [llength $_cores] > 0} {
    foreach c $_cores { catch { targets $c; resume } _ }
    say "DUMP_HALT: resumed [llength $_cores] core(s) (power-cycle if the OS doesn't continue)"
}

say ""
say "metadata -> ${OUT}.json"
if {[dict exists $res chunks_failed] && [dict get $res chunks_failed] > 0} {
    say "NOTE: [dict get $res chunks_failed] chunk(s) failed (filled 0xDEADBEEF) — likely unmapped/"
    say "      protected windows in the range. Narrow DUMP_ADDR/DUMP_SIZE to the region you want."
}
say ""
say "next: strings $OUT | less     binwalk $OUT     python3 tools/parse-bootimage.py $OUT"
say ""
