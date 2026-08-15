# riscv-sba-dump.tcl — dump a RISC-V target's system memory over the Debug Module's
# System Bus Access (SBA), the RISC-V equivalent of an Arm mem-AP dump. SBA reads
# memory through the DM's sbcs/sbaddress0/sbdata0 registers WITHOUT using a hart, so
# it works even while the core is running and without a Program Buffer. Non-destructive.
#
# Requires the DM to be reachable AND authenticated (DMSTATUS.authenticated=1). If the
# part implements RISC-V External Debug Security and no key is provisioned, SBA is
# behind the authdata challenge — this dump will fail cleanly (see docs/30 / jtagx.debugauth).
#
# Parameters via environment:
#   SBA_ADDR   start address            (default 0x80000000 — typical RAM base)
#   SBA_LEN    bytes to read            (default 0x00100000 = 1 MB)
#   SBA_CHUNK  words per read_memory    (default 1024 = 4 KB)
#   SBA_LABEL  short name for the file  (default riscv-sba)
#   SBA_OUT    output path              (default dumps/<label>.bin)
#
#   # 4 MB of RAM from 0x80000000 via SBA:
#   SBA_ADDR=0x80000000 SBA_LEN=0x400000 \
#     openocd -f openocd/riscv.cfg -c "init; source openocd/riscv-sba-dump.tcl; shutdown"
#
# The operator runs this (per the hands-on-JTAG model). It is read-only.

proc _env {name def} { if {[info exists ::env($name)]} { return $::env($name) } ; return $def }

set SBA_ADDR  [_env SBA_ADDR  0x80000000]
set SBA_LEN   [_env SBA_LEN   0x00100000]
set SBA_CHUNK [_env SBA_CHUNK 1024]
set SBA_LABEL [_env SBA_LABEL "riscv-sba"]
set SBA_OUT   [_env SBA_OUT   "dumps/${SBA_LABEL}.bin"]

# Normalize numeric env (hex strings → integers).
set addr  [expr {$SBA_ADDR}]
set len   [expr {$SBA_LEN}]
set chunk [expr {$SBA_CHUNK}]

puts "riscv-sba-dump: reading [format 0x%X $len] bytes from [format 0x%08X $addr] via System Bus Access"

# Pick a RISC-V target object (first target OpenOCD created for this cfg).
set tgt ""
if {![catch {target names} names]} { set tgt [lindex $names 0] }
if {$tgt eq ""} { set tgt "riscv.cpu" }

# Force SBA as the memory-access method (vs progbuf/abstract). OpenOCD's RISC-V driver
# exposes this per-target; ignore the error if the build auto-selects sysbus.
if {[catch { $tgt riscv set_mem_access sysbus } e]} {
    catch { riscv set_mem_access sysbus } e2
}

# Report DM authentication state up front (SBA needs authenticated=1). Best-effort —
# some builds don't expose dmstatus directly; the dump itself is the real test.
if {![catch { $tgt riscv dmi_read 0x11 } dmstatus]} {
    set authed [expr {($dmstatus >> 7) & 1}]
    puts [format "riscv-sba-dump: DMSTATUS=0x%08X  authenticated=%d" $dmstatus $authed]
    if {$authed == 0} {
        puts "riscv-sba-dump: WARNING DM reports authenticated=0 — SBA is behind the debug-auth"
        puts "                challenge (RISC-V External Debug Security). The dump will likely fail;"
        puts "                a key/cert is needed, not a lever. See jtagx.debugauth / docs/30."
    }
}

# Stream the range in chunks; write to a binary file. dump_image uses the configured
# access method (sysbus, set above). Chunked so a huge range doesn't stall one call.
set fh [open $SBA_OUT "wb"]
fconfigure $fh -translation binary
set done 0
set failed 0
while {$done < $len} {
    set this [expr {min($chunk * 4, $len - $done)}]
    set words [expr {($this + 3) / 4}]
    if {[catch { read_memory [expr {$addr + $done}] 32 $words } vals]} {
        puts [format "riscv-sba-dump: read failed at 0x%08X — stopping (%s)" [expr {$addr + $done}] $vals]
        set failed 1
        break
    }
    foreach w $vals {
        puts -nonewline $fh [binary format i $w]
    }
    set done [expr {$done + $words * 4}]
}
close $fh

if {$failed} {
    puts "riscv-sba-dump: partial dump ([format 0x%X $done] bytes) written to $SBA_OUT"
} else {
    puts "riscv-sba-dump: OK — [format 0x%X $done] bytes → $SBA_OUT"
    puts "  next: python3 tools/dump-triage.py $SBA_OUT   (structural triage before deeper analysis)"
}
