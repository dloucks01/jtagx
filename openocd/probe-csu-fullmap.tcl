# probe-csu-fullmap.tcl — complete per-word map of the CSU register space.
#
# Reads every CSU sub-block one word at a time with sticky-error recovery (the CSU
# space is peppered with SLVERR/unmapped offsets that wedge the DP on a block read).
# Emits non-zero values + a fault list per block, for a full CSU analysis.
# Non-destructive: read-only. Best run at JTAG-idle (clean post-BootROM baseline).
#
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-csu-fullmap.tcl; shutdown"
#
# Output: reports/csu-fullmap-<ts>.md (raw values; no summaries).

catch { targets uscale.axi } _
catch { uscale.dap dpreg 0 0x1e } _

set ts [clock format [clock seconds] -format %Y-%m-%d-%H%M%S]
file mkdir reports
set out "reports/csu-fullmap-$ts.md"
set fh [open $out w]
proc emit {s} { global fh; puts $fh $s; echo $s }

# Read `words` 32-bit words from `base`, per-word, recovering the DP on each fault.
# Emits non-zero words; tallies and lists faulting offsets.
proc map_block {base words label} {
    emit ""
    emit [format "## %s  (0x%08X, %d words)" $label $base $words]
    set nz 0; set nf 0; set faults ""
    for {set i 0} {$i < $words} {incr i} {
        set a [expr {$base + $i * 4}]
        if {[catch {read_memory $a 32 1} r]} {
            catch { uscale.dap dpreg 0 0x1e } _
            incr nf
            append faults [format " 0x%X" $a]
            continue
        }
        set w [expr {[lindex $r 0] & 0xFFFFFFFF}]
        if {$w != 0} { incr nz; emit [format "  0x%08X = 0x%08X" $a $w] }
    }
    emit [format "  -- %d non-zero, %d faulting (SLVERR/unmapped)" $nz $nf]
    if {$nf > 0} { emit [format "  faulting offsets:%s" $faults] }
}

emit "# CSU full register-space map — $ts"
emit "Per-word read with DP-sticky recovery. Non-zero values + fault map per CSU sub-block."

map_block 0xFFCA0000 64  "CSU control page (status/ctrl/sss/multiboot/jtag-gates/idcode/rom-digest)"
map_block 0xFFCA1000 32  "CSU AES engine (status/key-src/key-load/kup/iv)"
map_block 0xFFCA2000 32  "CSU SHA engine (start/reset/done/digest words)"
map_block 0xFFCA3000 32  "CSU PCAP (PL config interface)"
map_block 0xFFCA4000 32  "CSU PUF (cmd/cfg/shutter/status/word)"
map_block 0xFFCA4800 8   "CSU PUF trim-mode registers"
map_block 0xFFCA5000 16  "CSU tamper block (status + 13 source-config regs)"

catch { uscale.dap dpreg 0 0x1e } _
emit ""
emit "## done -> $out"
close $fh
echo "CSU full map written to $out"
