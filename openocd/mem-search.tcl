# mem-search.tcl — search LIVE memory for a pattern over the mem-AP, without dumping the whole region.
#
# For locating a key / string / magic in a large RAM when you don't want (or can't afford) a full dump —
# e.g. "is this AES key still resident, and where?". Reads the region in chunks via the mem-AP and reports
# every hit address. For sweeping all of DRAM, prefer dump-os-ddr.tcl + dram-secrets.py; this is for a
# targeted region or a quick live look.
#
# Env:
#   MS_ADDR    start address (default 0x0)
#   MS_SIZE    bytes to search (default 0x100000 = 1 MB)
#   MS_PATTERN an ASCII string to find        (use MS_HEX for raw bytes)
#   MS_HEX     hex bytes to find, e.g. deadbeef
#   MS_CHUNK   read granularity in bytes (default 0x1000)
#   MS_MAX     stop after this many hits (default 64)
#
# Usage:  MS_ADDR=0x0 MS_SIZE=0x4000000 MS_PATTERN="PRIVATE KEY" \
#           openocd -f openocd/zcu102.cfg -c "init; source openocd/mem-search.tcl; shutdown"
# Read-only.

set _d [file dirname [info script]]
source [file join $_d board-profile.tcl]      ;# ::AXI_TARGET
proc _envd {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }

set ADDR  [_envd MS_ADDR 0x0]
set SIZE  [_envd MS_SIZE 0x100000]
set CHUNK [_envd MS_CHUNK 0x1000]
set MAX   [_envd MS_MAX 64]
set PAT   [_envd MS_PATTERN ""]
set HEX   [_envd MS_HEX ""]

# build the pattern as a list of byte values
set pat {}
if {$HEX ne ""} {
    regsub -all {[^0-9a-fA-F]} $HEX "" h
    for {set i 0} {$i+1 < [string length $h]} {incr i 2} { lappend pat [expr "0x[string range $h $i [expr {$i+1}]]"] }
} elseif {$PAT ne ""} {
    binary scan $PAT c* sb ; foreach b $sb { lappend pat [expr {$b & 0xFF}] }
}
if {[llength $pat] == 0} { echo " ERROR: set MS_PATTERN=<string> or MS_HEX=<bytes>"; return }
set plen [llength $pat]

catch { targets $::AXI_TARGET } _
catch { $::AXI_TARGET arp_examine } _

echo ""
echo "================================================================"
echo " LIVE MEMORY SEARCH  (mem-AP: $::AXI_TARGET)"
echo [format " range %s .. %s   pattern: %d bytes" $ADDR [format 0x%X [expr {$ADDR + $SIZE}]] $plen]
echo "================================================================"

set hits 0
set end [expr {$ADDR + $SIZE}]
set step [expr {$CHUNK - $plen + 1}]   ;# overlap chunks so a match across a boundary isn't missed
if {$step < 1} { set step $CHUNK }
for {set a $ADDR} {$a < $end && $hits < $MAX} {incr a $step} {
    set n $CHUNK ; if {[expr {$end - $a}] < $n} { set n [expr {$end - $a}] }
    set nw [expr {($n + 3) / 4}]
    if {[catch {read_memory $a 32 $nw} words]} { continue }   ;# skip unreadable/gated windows
    # unpack words -> byte list (little-endian)
    set bytes {}
    foreach w $words { for {set k 0} {$k < 4} {incr k} { lappend bytes [expr {($w >> ($k*8)) & 0xFF}] } }
    set blen [llength $bytes]
    for {set i 0} {$i + $plen <= $blen} {incr i} {
        if {[lindex $bytes $i] != [lindex $pat 0]} { continue }
        set match 1
        for {set j 1} {$j < $plen} {incr j} {
            if {[lindex $bytes [expr {$i+$j}]] != [lindex $pat $j]} { set match 0 ; break }
        }
        if {$match} { echo [format "   HIT @ 0x%08X" [expr {$a + $i}]] ; incr hits ; if {$hits >= $MAX} { break } }
    }
}
echo "----------------------------------------------------------------"
set tail "" ; if {$hits >= $MAX} { set tail " (MAX reached — raise MS_MAX)" }
echo " $hits hit(s)$tail."
echo "================================================================"
