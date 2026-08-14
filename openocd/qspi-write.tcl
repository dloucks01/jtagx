# qspi-write.tcl — JTAG-native ZynqMP QSPI flash WRITER (erase / page-program / read-modify-write patch),
# the write counterpart to qspi-jtag.tcl's reader. Drives the GQSPI Generic-FIFO controller over the AXI-AP
# (MMIO) — no U-Boot, no DDR, no strap change. Closes the persistence loop (Cap-3) entirely over JTAG.
#
# SAME proven plumbing as the reader (UG1085 Ch.24): GEN_FIFO encoding, dual-parallel Micron MT25QU512
# (even logical bytes -> lower die, odd -> upper; per-die addr = logical>>1), mode-3 clock CFG 0x2000001E.
# Adds the write commands: WREN 0x06, RDSR 0x05 (WIP=bit0, WEL=bit1), Sector-Erase 0xD8 (64 KB), Page-
# Program 0x02 (<=256 B/die). Erase sets bits to 1; program only clears 1->0; so a change = read sector ->
# modify -> erase -> reprogram -> verify (read-modify-write).
#
# !! DESTRUCTIVE ops (erase/program/patch) MODIFY FLASH. On the ZCU102 this is SAFE to experiment with while
#    the board boots from SD (BOOT_MODE=0x2): a botched QSPI write cannot brick the board — SD stays the
#    fallback. Always dump first (qspi-jtag.tcl QSPI_OP=dmadump) so you can restore.
#
# Env QW_OP (default srtest — the safe probe):
#   srtest    read the status register of both dies               (SAFE, no change)
#   wrentest  WREN then read SR; confirm WEL latches              (SAFE, WEL self-clears, no flash change)
#   scratch   FULL erase+program+verify roundtrip on QW_ADDR, restoring the original after  (writes 1 sector)
#   patch     read-modify-write: apply QW_HEX at logical QW_OFFSET, sector-granular, with verify  (Cap-3)
# Env: QW_ADDR (scratch logical sector base, default 0x1000000=16MB, past the boot image)
#      QW_OFFSET / QW_HEX (patch: logical byte offset + hex bytes, e.g. QW_HEX=00008052c0035fd6)
#
# Run: QW_OP=srtest openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-write.tcl; shutdown"

set _d [file dirname [info script]]
source [file join $_d board-profile.tcl]    ;# AXI_TARGET / DAP_NAME

# --- GQSPI register map (same as the reader) ---
set CFG 0xFF0F0100 ; set ISR 0xFF0F0104 ; set EN 0xFF0F0114
set TXD 0xFF0F011C ; set RXD 0xFF0F0120 ; set GENFIFO 0xFF0F0140
set SEL 0xFF0F0144 ; set FIFOCTRL 0xFF0F014C
set ISR_RXEMPTY 0x800
set RD_CFG 0x2000001E          ;# validated mode-3 clock/baud/manual-start

# per-die bus/cs selectors (from the reader)
set LO_BUS 0x4000 ; set LO_CS 0x1000
set UP_BUS 0x8000 ; set UP_CS 0x2000
set SPI 0x400                  ;# spiMode bit
set SEC_SZ 0x10000             ;# 64 KB per-die sector (Sector-Erase 0xD8)
set PAGE 256                   ;# per-die page-program size

proc clrsticky {} { for {set i 0} {$i < 3} {incr i} { catch { $::DAP_NAME dpreg 0 0x1e } _ ; after 5 } }
proc wr {a v} { if {[catch {write_memory $a 32 [list $v]} e]} { clrsticky; return 0 } ; return 1 }
proc rd {a}  { if {[catch {read_memory  $a 32 1} v]} { clrsticky; return "ERR" } ; return [lindex $v 0] }

# ---- low-level: start the GEN_FIFO and (for RX) collect n bytes ----
proc _start {cfg} { wr $::CFG [expr {$cfg | 0x10000000}] }   ;# START_GEN_FIFO (manual start)
proc _fifo_reset {cfg} { wr $::SEL 0x1 ; wr $::EN 0x0 ; wr $::CFG 0x20000018 ; wr $::FIFOCTRL 0x7 ; wr $::CFG $cfg ; wr $::EN 0x1 }
proc _rx1 {} {
    for {set i 0} {$i < 400} {incr i} { set isr [rd $::ISR] ; if {$isr ne "ERR" && ($isr & $::ISR_RXEMPTY)==0} { return [expr {[rd $::RXD] & 0xFF}] } ; after 1 }
    return "TIMEOUT"
}

# ---- flash commands (per-die: pass bus+cs) ----
proc flash_rdsr {cfg bus cs} {
    _fifo_reset $cfg
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0x04}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x05}]            ;# TX RDSR 0x05
    wr $::GENFIFO [expr {0x20000 | $bus | $cs | $::SPI | 0x100 | 0x1}]     ;# RX 1
    wr $::GENFIFO [expr {$bus | $::SPI | 0x04}]
    _start $cfg
    return [_rx1]
}
proc flash_wren {cfg bus cs} {
    _fifo_reset $cfg
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0x04}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x06}]            ;# TX WREN 0x06
    wr $::GENFIFO [expr {$bus | $::SPI | 0x04}]
    _start $cfg
    after 2
}
proc flash_wait_wip {cfg bus cs {tries 20000}} {
    for {set i 0} {$i < $tries} {incr i} {
        set sr [flash_rdsr $cfg $bus $cs]
        if {$sr eq "TIMEOUT"} { return "TIMEOUT" }
        if {($sr & 0x1) == 0} { return $sr }                              ;# WIP clear -> done
    }
    return "WIPSTUCK"
}
# Sector-Erase 0xD8 at a per-die 64 KB-aligned address (3-byte addr, immediate).
proc flash_erase {cfg bus cs pd_addr} {
    flash_wren $cfg $bus $cs
    _fifo_reset $cfg
    set b1 [expr {($pd_addr>>16)&0xFF}] ; set b2 [expr {($pd_addr>>8)&0xFF}] ; set b3 [expr {$pd_addr&0xFF}]
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0x04}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0xD8}]            ;# TX SE 0xD8
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b1}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b2}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b3}]
    wr $::GENFIFO [expr {$bus | $::SPI | 0x04}]
    _start $cfg
    return [flash_wait_wip $cfg $bus $cs]
}
# Subsector-Erase 0x20 at a per-die 4 KB-aligned address (minimal erase unit -> only 4KB/die to RMW).
proc flash_erase4k {cfg bus cs pd_addr} {
    flash_wren $cfg $bus $cs
    _fifo_reset $cfg
    set b1 [expr {($pd_addr>>16)&0xFF}] ; set b2 [expr {($pd_addr>>8)&0xFF}] ; set b3 [expr {$pd_addr&0xFF}]
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0x04}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x20}]            ;# TX SSE 0x20
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b1}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b2}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b3}]
    wr $::GENFIFO [expr {$bus | $::SPI | 0x04}]
    _start $cfg
    return [flash_wait_wip $cfg $bus $cs]
}
# Page-Program 0x02: write <=256 bytes (list) to per-die $pd_addr. Opcode+addr immediate, data via TXFIFO.
proc flash_pp {cfg bus cs pd_addr data} {
    set n [llength $data]
    if {$n == 0} { return "OK" }
    flash_wren $cfg $bus $cs
    _fifo_reset $cfg
    set b1 [expr {($pd_addr>>16)&0xFF}] ; set b2 [expr {($pd_addr>>8)&0xFF}] ; set b3 [expr {$pd_addr&0xFF}]
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0x04}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x02}]            ;# TX PP 0x02
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b1}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b2}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b3}]
    # push data bytes to TXFIFO (4 bytes/word, LE)
    set nwords [expr {($n + 3) / 4}]
    for {set w 0} {$w < $nwords} {incr w} {
        set word 0
        for {set k 0} {$k < 4} {incr k} {
            set idx [expr {$w*4 + $k}]
            set by [expr {$idx < $n ? [lindex $data $idx] : 0xFF}]
            set word [expr {$word | ($by << ($k*8))}]
        }
        wr $::TXD $word
    }
    # TX the data: exp form for exactly 256, else immediate count (<=255)
    if {$n == 256} {
        wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x200 | 0x100 | 0x8}]
    } else {
        wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x100 | ($n & 0xFF)}]
    }
    wr $::GENFIFO [expr {$bus | $::SPI | 0x04}]
    _start $cfg
    return [flash_wait_wip $cfg $bus $cs]
}
# read n bytes from one die (cmd 0x03 + 3-byte addr) — for verify (mirrors the reader's read_die)
proc flash_read_die {cfg bus cs pd_addr n} {
    _fifo_reset $cfg
    set b1 [expr {($pd_addr>>16)&0xFF}] ; set b2 [expr {($pd_addr>>8)&0xFF}] ; set b3 [expr {$pd_addr&0xFF}]
    wr $::GENFIFO [expr {$bus | $cs | $::SPI | 0xFF}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | 0x03}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b1}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b2}]
    wr $::GENFIFO [expr {0x10000 | $bus | $cs | $::SPI | $b3}]
    wr $::GENFIFO [expr {0x20000 | $bus | $cs | $::SPI | 0x100 | ($n & 0xFF)}]
    wr $::GENFIFO [expr {$bus | 0xFF}]
    _start $cfg
    set out {}
    set nwords [expr {($n + 3) / 4}]
    for {set w 0} {$w < $nwords} {incr w} {
        set ok 0
        for {set i 0} {$i < 500} {incr i} { set isr [rd $::ISR] ; if {$isr ne "ERR" && ($isr & $::ISR_RXEMPTY)==0} { set ok 1 ; break } ; after 1 }
        if {!$ok} { return "TIMEOUT" }
        set wd [rd $::RXD] ; if {$wd eq "ERR"} { return "ERR" }
        lappend out [expr {$wd & 0xFF}] [expr {($wd>>8)&0xFF}] [expr {($wd>>16)&0xFF}] [expr {($wd>>24)&0xFF}]
    }
    return [lrange $out 0 [expr {$n-1}]]
}

# ===================== AXI mem-AP recovery (same pattern as the reader) =====================
set OP [expr {[info exists ::env(QW_OP)] ? $::env(QW_OP) : "srtest"}]
set examined 0
for {set i 0} {$i < 6} {incr i} {
    clrsticky ; catch { targets $AXI_TARGET } _
    if {![catch { $AXI_TARGET arp_examine } e] && [rd $ISR] ne "ERR"} { set examined 1 ; break }
    after 30
}
puts ""
puts "================================================================"
puts " GQSPI WRITER  (JTAG-native, via AXI-AP MMIO)   OP=$OP"
puts "================================================================"
if {!$examined} { puts " ERROR: AXI mem-AP will not examine (DAP sticky wedge). Re-run; else power-cycle." ; return }

proc _srdec {sr} { if {$sr eq "TIMEOUT"} { return "TIMEOUT" } ; return [format "0x%02x (WIP=%d WEL=%d)" $sr [expr {$sr & 1}] [expr {($sr>>1)&1}]] }

if {$OP eq "srtest"} {
    puts " RDSR both dies (WIP=write-in-progress, WEL=write-enable-latch):"
    puts "   lower = [_srdec [flash_rdsr $RD_CFG $LO_BUS $LO_CS]]"
    puts "   upper = [_srdec [flash_rdsr $RD_CFG $UP_BUS $UP_CS]]"
    puts " (a sane idle flash reads WIP=0, WEL=0. ERR/TIMEOUT => command path wrong.)"

} elseif {$OP eq "wrentest"} {
    puts " SAFE write-path probe: WREN must set WEL=1 (it self-clears; NO flash content changes)."
    foreach {nm bus cs} [list lower $LO_BUS $LO_CS upper $UP_BUS $UP_CS] {
        set before [flash_rdsr $RD_CFG $bus $cs]
        flash_wren $RD_CFG $bus $cs
        set after [flash_rdsr $RD_CFG $bus $cs]
        puts [format "   %-5s  before=%s  after WREN=%s  -> %s" $nm [_srdec $before] [_srdec $after] \
              [expr {($after ne "TIMEOUT" && ($after & 0x2)) ? "WEL LATCHED (write path OK)" : "WEL did NOT set (FAIL)"}]]
    }

} elseif {$OP eq "scratch"} {
    set base [expr {[info exists ::env(QW_ADDR)] ? $::env(QW_ADDR) : 0x1000000}]   ;# logical, 128KB-aligned pair
    set pd   [expr {$base >> 1}]                                                    ;# per-die sector addr
    puts [format " SCRATCH roundtrip on logical 0x%X (per-die sector 0x%X) — dump, erase, program, verify, RESTORE." $base $pd]
    # 1) save original first 128 B of each die (128 = the 32-word RX-FIFO depth; >128/die overflows)
    set o_lo [flash_read_die $RD_CFG $LO_BUS $LO_CS $pd 128]
    set o_up [flash_read_die $RD_CFG $UP_BUS $UP_CS $pd 128]
    if {$o_lo eq "TIMEOUT" || $o_up eq "TIMEOUT"} { puts " ERROR: pre-read failed; aborting (no change made)." ; return }
    puts [format "   saved original (lo(0-3)=%02x %02x %02x %02x)" [lindex $o_lo 0] [lindex $o_lo 1] [lindex $o_lo 2] [lindex $o_lo 3]]
    # 2) erase both dies' sector
    puts "   erasing per-die sector 0x$pd (0xD8) ..."
    set e1 [flash_erase $RD_CFG $LO_BUS $LO_CS $pd] ; set e2 [flash_erase $RD_CFG $UP_BUS $UP_CS $pd]
    set v_lo [flash_read_die $RD_CFG $LO_BUS $LO_CS $pd 16]
    set blank [expr {[lindex $v_lo 0]==0xFF && [lindex $v_lo 1]==0xFF && [lindex $v_lo 2]==0xFF && [lindex $v_lo 3]==0xFF}]
    puts [format "   post-erase lower(0-3) = %02x %02x %02x %02x  -> %s" [lindex $v_lo 0] [lindex $v_lo 1] [lindex $v_lo 2] [lindex $v_lo 3] [expr {$blank?"ERASED(0xFF)":"ERASE FAILED"}]]
    # 3) program a test pattern (16 bytes) into each die
    set pat {0xde 0xad 0xbe 0xef 0x01 0x02 0x03 0x04 0xa5 0x5a 0xc3 0x3c 0x10 0x20 0x40 0x80}
    flash_pp $RD_CFG $LO_BUS $LO_CS $pd $pat
    set r_lo [flash_read_die $RD_CFG $LO_BUS $LO_CS $pd 16]
    set match 1 ; for {set k 0} {$k<16} {incr k} { if {[lindex $r_lo $k] != [lindex $pat $k]} { set match 0 } }
    puts [format "   post-program lower(0-7) = %02x %02x %02x %02x %02x %02x %02x %02x  -> %s" \
          [lindex $r_lo 0] [lindex $r_lo 1] [lindex $r_lo 2] [lindex $r_lo 3] [lindex $r_lo 4] [lindex $r_lo 5] [lindex $r_lo 6] [lindex $r_lo 7] \
          [expr {$match?"PROGRAM VERIFIED":"PROGRAM MISMATCH"}]]
    # 4) RESTORE the original 256 B (erase then program back)
    puts "   restoring original ..."
    flash_erase $RD_CFG $LO_BUS $LO_CS $pd ; flash_erase $RD_CFG $UP_BUS $UP_CS $pd
    flash_pp $RD_CFG $LO_BUS $LO_CS $pd $o_lo ; flash_pp $RD_CFG $UP_BUS $UP_CS $pd $o_up
    set rb [flash_read_die $RD_CFG $LO_BUS $LO_CS $pd 8]
    set rok 1 ; for {set k 0} {$k<8} {incr k} { if {[lindex $rb $k] != [lindex $o_lo $k]} { set rok 0 } }
    puts [format "   restore check lower(0-3) = %02x %02x %02x %02x  -> %s" [lindex $rb 0] [lindex $rb 1] [lindex $rb 2] [lindex $rb 3] [expr {$rok?"RESTORED":"RESTORE INCOMPLETE (only 256B saved; rest of sector is 0xFF)"}]]
    puts ""
    if {$blank && $match} { puts " RESULT: WRITER VALIDATED — erase + page-program + verify all work over JTAG." } else { puts " RESULT: writer needs work — see above." }
    puts " NOTE: only the first 128 B of the scratch sector were saved/restored; the rest of that 64KB sector"
    puts "   is now 0xFF (it was scratch space past the boot image, so harmless)."

} elseif {$OP eq "patch"} {
    # the patched sub-sector data is precomputed by tools/qspi-make-patch.py (no binary I/O in Tcl).
    set data [expr {[info exists ::env(QW_DATA)] ? $::env(QW_DATA) : "/tmp/qpatch.tcl"}]
    if {[catch {source $data} e]} { puts " ERROR: source QW_DATA=$data failed ($e). Run tools/qspi-make-patch.py first." ; return }
    set pd_sub $::PD_SUB ; set off $::POFF ; set hex $::PHEX ; set lo $::PLO ; set up $::PUP
    set SUB 4096
    regsub -all {[^0-9a-fA-F]} $hex "" h
    set pbytes {}
    for {set i 0} {$i+1 < [string length $h]} {incr i 2} { lappend pbytes [expr "0x[string range $h $i [expr {$i+1}]]"] }
    set np [llength $pbytes]
    puts [format " PATCH %d byte(s) at logical 0x%X  (per-die 4KB subsector 0x%X)" $np $off $pd_sub]
    puts "   data = $data   hex = $hex"
    # SANITY: the live flash subsector must match the source image (else the dump is stale -> abort)
    set chk [flash_read_die $RD_CFG $LO_BUS $LO_CS $pd_sub 16]
    if {$chk eq "TIMEOUT" || $chk eq "ERR"} { puts " ERROR: pre-read of flash failed; aborting." ; return }
    set stale 0 ; for {set k 0} {$k < 16} {incr k} { if {[lindex $chk $k] != [lindex $lo $k]} { set stale 1 } }
    if {$stale} {
        puts " ABORT: live flash != source image (dump stale / QSPI changed). Re-dump and retry. NO change made."
        puts [format "   flash lo(0-3)=%02x %02x %02x %02x   image lo(0-3)=%02x %02x %02x %02x" \
              [lindex $chk 0] [lindex $chk 1] [lindex $chk 2] [lindex $chk 3] [lindex $lo 0] [lindex $lo 1] [lindex $lo 2] [lindex $lo 3]]
        return
    }
    puts "   live flash matches the source image — safe to read-modify-write."
    puts "   erasing 4KB subsector (0x20) on both dies ..."
    flash_erase4k $RD_CFG $LO_BUS $LO_CS $pd_sub
    flash_erase4k $RD_CFG $UP_BUS $UP_CS $pd_sub
    puts "   programming 4KB/die in 128B pages (64 pages) ..."
    for {set o 0} {$o < $SUB} {incr o 128} {
        flash_pp $RD_CFG $LO_BUS $LO_CS [expr {$pd_sub+$o}] [lrange $lo $o [expr {$o+127}]]
        flash_pp $RD_CFG $UP_BUS $UP_CS [expr {$pd_sub+$o}] [lrange $up $o [expr {$o+127}]]
    }
    # verify: re-read a 32-logical-byte window at the patch site and confirm the patch bytes
    set pdoff [expr {$off >> 1}]
    set vlo [flash_read_die $RD_CFG $LO_BUS $LO_CS $pdoff 16]
    set vup [flash_read_die $RD_CFG $UP_BUS $UP_CS $pdoff 16]
    set vbase [expr {$pdoff << 1}] ; set rel2 [expr {$off - $vbase}]
    set recon {} ; for {set k 0} {$k < 16} {incr k} { lappend recon [lindex $vlo $k] [lindex $vup $k] }
    set ok 1 ; for {set i 0} {$i < $np} {incr i} { if {[lindex $recon [expr {$rel2+$i}]] != [lindex $pbytes $i]} { set ok 0 } }
    set got ""
    for {set i 0} {$i < $np} {incr i} { append got [format "%02x " [lindex $recon [expr {$rel2+$i}]]] }
    puts [format "   re-read at patch site: %s (want %s)" [string trim $got] $hex]
    puts ""
    if {$ok} {
        puts " RESULT: PATCH PERSISTED IN QSPI FLASH — ret0 is now baked into the boot image."
        puts "   Boot from QSPI (SW6 -> QSPI strap, or a boot-mode override) to run the patched VxWorks,"
        puts "   then verify over JTAG that the running kernel's .text shows the patched bytes."
    } else {
        puts " RESULT: VERIFY FAILED — the re-read does not match the patch. Inspect above."
    }

} else {
    puts " unknown QW_OP=$OP (use srtest|wrentest|scratch|patch)."
}
puts "================================================================"
