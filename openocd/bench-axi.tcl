# bench-axi.tcl — measure AXI mem-AP read throughput at a given JTAG clock, with an integrity check.
# Env: BM_SPEED (kHz), BM_MB (MB to read, default 4), BM_CW (chunk words, default 4096), BM_BASE (default 0x100000)
proc _envd {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
proc _now {} {
    if {![catch {clock millis} m]} { return $m }
    if {![catch {clock micros} u]} { return [expr {$u/1000}] }
    return [expr {[clock seconds]*1000}]
}
set spd  [_envd BM_SPEED 1000]
set MB   [_envd BM_MB 4]
set cw   [_envd BM_CW 4096]
set base [_envd BM_BASE 0x100000]

catch { adapter speed $spd } _
catch { targets uscale.axi } _

set total   [expr {$MB*1024*1024}]
set nchunks [expr {$total/($cw*4)}]

# integrity: known VxWorks entry word at 0x100000 = 0xaa0003e5
set w0 "ERR"
if {![catch { read_memory $base 32 1 } v]} { set w0 [format 0x%08x [expr {[lindex $v 0] & 0xFFFFFFFF}]] }

set t0 [_now]
set failed 0
for {set i 0} {$i < $nchunks} {incr i} {
    if {[catch { read_memory [expr {$base + $i*$cw*4}] 32 $cw } _]} { incr failed }
}
set t1 [_now]
set ms [expr {$t1 - $t0}]
set kbps 0.0
if {$ms > 0} { set kbps [expr {($total/1024.0)/($ms/1000.0)}] }
echo [format "BENCH speed=%-6d kHz  read=%d MB  chunk=%dw  time=%-6d ms  thru=%8.1f KB/s  failed=%d  w0=%s" \
        $spd $MB $cw $ms $kbps $failed $w0]
