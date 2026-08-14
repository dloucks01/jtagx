# bootrom-fuzz-observe.tcl — capture the CSU BootROM's REACTION fingerprint after booting a
# (possibly malformed) image, for black-box parser fuzzing. NON-DESTRUCTIVE (reads only, via
# the AXI-AP; no reset/halt/write).
#
# Run AFTER flashing a fuzz image and power-cycling the board (SW6 = the boot device, NOT JTAG —
# the BootROM only parses an image when booting from SD/QSPI):
#   openocd -f openocd/zcu102.cfg -c "init; set ::FUZZ_ID 7; source openocd/bootrom-fuzz-observe.tcl; shutdown"
#
# Emits one FUZZ_FP line (also appended to reports/bootrom-fuzz.log) — feed the log to
# tools/bootrom-fuzz-triage.py to diff every trial against the 0000-baseline fingerprint.
#
# Signals it captures (what a parser bug looks like from outside):
#   CSU_MULTI_BOOT : increments when the BootROM hit an error and searched for a golden image
#   CSU_FT_STATUS  : CSU triple-redundancy/fault status — a fault here can mean the parser crashed
#   CSU_STATUS     : boot-stage status bits
#   BOOT_MODE      : sanity (which device the BootROM used)
#   OCM_SUM/words  : a window of OCM (0xFFFC0000, where the FSBL is staged) — an unexpected change
#                    vs baseline can mean an attacker-controlled copy landed there (the goal: ROM)
#   DAP            : ok / wedge — a wedge can mean the BootROM hung in an anomalous state

set FUZZ_ID "?"
if {[info exists ::env(FUZZ_ID)]} { set FUZZ_ID $::env(FUZZ_ID) }
if {[info exists ::FUZZ_ID]} { set FUZZ_ID $::FUZZ_ID }

proc _clr {} { for {set i 0} {$i < 3} {incr i} { catch { uscale.dap dpreg 0 0x1e } _ ; after 5 } }
proc _rd {a} { if {[catch {read_memory $a 32 1} v]} { _clr; return "ERR" } ; return [lindex $v 0] }
proc _hx {v} { if {$v eq "ERR"} { return "ERR" } ; return [format "0x%08X" $v] }

catch { targets uscale.axi } _
catch { uscale.axi arp_examine } _

set csu_status [_rd 0xFFCA0000]
set multiboot  [_rd 0xFFCA0010]
set ft_status  [_rd 0xFFCA0018]
set boot_mode  [_rd 0xFF5E0200]

# OCM window: sum 0x2000 words (32 KB) from 0xFFFC0000 + sample words, to fingerprint what got
# staged there. ERR on any read => DAP not answering (treated as wedge).
set ocm_sum 0
set ocm_w0 "ERR"; set ocm_w1 "ERR"; set ocm_w2 "ERR"; set ocm_w3 "ERR"
set dap "ok"
if {[catch {read_memory 0xFFFC0000 32 0x800} blk]} {
    set dap "wedge"
} else {
    foreach w $blk { set ocm_sum [expr {($ocm_sum + $w) & 0xFFFFFFFF}] }
    set ocm_w0 [lindex $blk 0]
    set ocm_w1 [lindex $blk 1]
    set ocm_w2 [lindex $blk 2]
    set ocm_w3 [lindex $blk 3]
}
if {$csu_status eq "ERR" && $multiboot eq "ERR"} { set dap "wedge" }

proc _w {v} { if {$v eq "ERR"} { return "ERR" } ; return [format "0x%08X" $v] }
set line [format "FUZZ_FP id=%s CSU_STATUS=%s MULTIBOOT=%s FT_STATUS=%s BOOT_MODE=%s OCM_SUM=0x%08X OCM_W0=%s OCM_W1=%s OCM_W2=%s OCM_W3=%s DAP=%s" \
    $FUZZ_ID [_hx $csu_status] [_hx $multiboot] [_hx $ft_status] [_hx $boot_mode] \
    $ocm_sum [_w $ocm_w0] [_w $ocm_w1] [_w $ocm_w2] [_w $ocm_w3] $dap]

puts ""
puts $line
puts ""
catch {
    set fh [open "reports/bootrom-fuzz.log" a]
    puts $fh $line
    close $fh
}
puts "Logged to reports/bootrom-fuzz.log. Triage: python3 tools/bootrom-fuzz-triage.py reports/bootrom-fuzz.log <corpus>/manifest.json"
puts "If a trial flags ANOMALY (esp. OCM change + FT_STATUS change), full-dump OCM with dump-memory and check it for ROM content."
