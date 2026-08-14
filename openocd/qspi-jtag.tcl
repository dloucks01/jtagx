# qspi-jtag.tcl — JTAG-native ZynqMP QSPI flash reader: drives the GQSPI Generic-FIFO controller
# directly over the AXI-AP (MMIO). Reads the boot flash from ANY state — no U-Boot, no DDR, no clean
# slate, no boot-strap change — because it's pure debug-port register I/O. Works on a live system or
# a strap-locked board (the engagement case where you can't flip SW6 to JTAG mode).
#
# Built from UG1085 (v1.8) Ch.24 "Quad-SPI Controllers":
#   GQSPI base 0xFF0F0000. Regs: CFG 0x100, ISR 0x104, En 0x114, TXD 0x11C, RXD 0x120,
#                                GEN_FIFO 0x140, SEL 0x144, FIFO_CTRL 0x14C.
#   GQSPI_CFG: MODE_EN[31:30] (00=I/O), GEN_FIFO_START_MODE[29], START_GEN_FIFO[28],
#              BAUD[5:3], CLK_PH[2], CLK_POL[1].
#   GQSPI_ISR: RX_FIFO_EMPTY = bit 11 (0x800).
#   GEN_FIFO entry: poll[19] stripe[18] rx[17] tx[16] busSel[15:14] csUpper[13] csLower[12]
#                   spiMode[11:10] exp[9] dataXfer[8] imm[7:0].
#   PIO read flow (TRM §"Generic Quad-SPI Controller in PIO Mode"): SEL=1; MODE_EN=00; write
#   GEN_FIFO; manual-start trigger; poll RX-not-empty; read RXD.
#
# THIS STAGE = the JEDEC-ID self-test (RDID 0x9F -> 3 bytes). It's the smallest GQSPI transaction:
# if it returns a known flash manufacturer ID, the whole GEN-FIFO sequence is proven correct and we
# extend to a bulk read. If it returns 0x00/0xFF, an encoding/clock knob is wrong (the values below
# are the first-try assumptions: SPI mode-0, baud /16, manual start, lower bus, single die).
#
# Run: openocd -f openocd/zcu102.cfg -c "init; source openocd/qspi-jtag.tcl; shutdown"

set _d [file dirname [info script]]
source [file join $_d board-profile.tcl]    ;# sets AXI_TARGET / DAP_NAME

# --- GQSPI register map ---
set CFG       0xFF0F0100
set ISR       0xFF0F0104
set EN        0xFF0F0114
set TXD       0xFF0F011C
set RXD       0xFF0F0120
set GENFIFO   0xFF0F0140
set SEL       0xFF0F0144
set FIFOCTRL  0xFF0F014C
# QSPIDMA (DST = stream->memory) registers — DMA flash data straight to DDR, then block-read DDR fast.
set DST_ADDR     0xFF0F0800
set DST_SIZE     0xFF0F0804
set DST_STS      0xFF0F0808
set DST_CTRL     0xFF0F080C   ;# DST channel control: PAUSE_MEM(0)/PAUSE_STRM(1) + FIFO thr/outstanding
set DST_I_STS    0xFF0F0814
set DST_CTRL2    0xFF0F0824   ;# DST channel control 2 (rate/timeout); driver reset val 0x0000FFF8
set DST_ADDR_MSB 0xFF0F0828
# DST_CTRL bits: PAUSE_MEM=bit0, PAUSE_STRM=bit1 (csudma.h layout; the PMU's idle_hooks.c SETS these
# to pause QSPI-DMA when going idle — leaving them set makes a DMA "complete" but move ZERO bytes).
# The xqspipsu driver's operational/reset DST_CTRL value is 0x803FFA00 (PAUSE bits clear).
set DST_CTRL_OPVAL   0x803FFA00
set DST_CTRL2_OPVAL  0x081BFFF8   ;# observed HW/firmware value (reset val); upper bits are AXI/FIFO attrs
set DST_CTRL_PAUSE   0x3          ;# PAUSE_MEM | PAUSE_STRM

# --- config word: I/O mode (MODE_EN=00), manual start (bit29), baud /16 (0x18), SPI mode 0 ---
set CFG_BASE  0x20000018
set CFG_TRIG  0x30000018   ;# CFG_BASE | START_GEN_FIFO (bit28)
set ISR_RXEMPTY 0x800      ;# RX_FIFO_EMPTY (bit 11)

# --- GEN_FIFO entries for RDID (0x9F -> 3 bytes), SPI mode, lower bus, single CS ---
#   common bits: busSel_lower(0x4000) | cs_lower(0x1000) | spiMode_SPI(0x400)
set GF_CS_ASSERT   0x000054FF   ;# +imm 0xFF (CS setup cycles)
set GF_TX_RDID     0x0001549F   ;# +TX(0x10000), data_xfer=0 -> imm 0x9F sent on the bus
set GF_RX_3        0x00025503   ;# +RX(0x20000), data_xfer=1(0x100), imm=3 bytes into RXFIFO
set GF_CS_DEASSERT 0x000040FF   ;# busSel_lower, cs released, imm 0xFF (CS hold cycles)

proc clrsticky {} { for {set i 0} {$i < 3} {incr i} { catch { $::DAP_NAME dpreg 0 0x1e } _ ; after 5 } }
proc wr {a v} { if {[catch {write_memory $a 32 [list $v]} e]} { clrsticky; return 0 } ; return 1 }
proc rd {a}  { if {[catch {read_memory  $a 32 1} v]} { clrsticky; return "ERR" } ; return [lindex $v 0] }
proc rdhex {a} { set v [rd $a] ; if {$v eq "ERR"} { return "ERR" } ; return [format 0x%08X [expr {$v & 0xFFFFFFFF}]] }
# Un-rotate a per-die byte list by the DST-FIFO lead-in (rotate left by L). The QSPIDMA writes the
# (byte-perfect) data starting L bytes into the buffer and wraps at DST_SIZE, so this restores order.
proc _derot {lst L} { if {$L <= 0} { return $lst } ; return [concat [lrange $lst $L end] [lrange $lst 0 [expr {$L-1}]]] }

puts ""
puts "================================================================"
puts " GQSPI JEDEC-ID self-test (JTAG-native, via AXI-AP MMIO)"
puts "================================================================"

set OP [expr {[info exists ::env(QSPI_OP)] ? $::env(QSPI_OP) : "id"}]

# DMA modes stream flash data into a DDR scratch the running OS would otherwise clobber. Halt the
# cores FIRST — *before* the AXI-AP recovery below — so the mem-AP is (re-)examined in the halted
# state. Examining the mem-AP AFTER a halt fails in this OpenOCD/board combo ("Target not examined");
# halting first and letting the recovery block examine works (same as probe-phys-patch).
# By default DON'T halt for DMA: halting makes the mem-AP flaky here, and a *free* DDR scratch (one
# the OS never touched) needs no halt — the OS won't clobber it and it has no dirty cache line to
# shadow the DMA write. Set QSPI_HALT=1 to force a halt (only if you must use OS-owned scratch).
if {($OP eq "dmaread" || $OP eq "dmadump") && [info exists ::env(QSPI_HALT)]} {
    if {![catch {target names} _ts]} {
        foreach c $_ts { if {[string match {*a53*} $c] || [string match {*a72*} $c]} { catch { targets $c ; halt } _ } }
    }
    after 50
}

# Recover the AXI mem-AP. A leftover DP sticky error (e.g. from a prior failed AXI burst) makes the
# mem-AP examine fail at init -> every MMIO read/write errors "Target not examined yet". Fix: CLEAR
# the sticky error FIRST, then (re-)examine, retrying. Bail cleanly if it stays wedged.
set examined 0
for {set i 0} {$i < 6} {incr i} {
    clrsticky
    catch { targets $AXI_TARGET } _
    if {![catch { $AXI_TARGET arp_examine } e] && [rd $ISR] ne "ERR"} { set examined 1 ; break }
    after 30
}
if {!$examined} {
    puts " ERROR: AXI mem-AP will not examine (DAP sticky-error wedge)."
    puts "   Recover: re-run this command once; if it persists, power-cycle the board (see"
    puts "   reference_dap_wedge). The GQSPI sequence below never ran."
    puts "================================================================"
    return
}

array set MFG {0x20 Micron 0xC2 Macronix 0x01 Spansion/Cypress 0xEF Winbond 0x9D ISSI 0xBF SST 0x1F Atmel}

# Validated SPI clock mode from the id self-test: mode 3 (CPOL+CPHA), baud /16, manual start.
set RD_CFG 0x2000001E

# --- RDID self-test (one transaction, single lower die) ---
proc do_rdid {cfg} {
    global SEL EN FIFOCTRL CFG GENFIFO ISR RXD ISR_RXEMPTY
    global GF_CS_ASSERT GF_TX_RDID GF_RX_3 GF_CS_DEASSERT
    wr $SEL 0x1 ; wr $EN 0x0 ; wr $FIFOCTRL 0x7 ; wr $CFG $cfg ; wr $EN 0x1
    foreach gf [list $GF_CS_ASSERT $GF_TX_RDID $GF_RX_3 $GF_CS_DEASSERT] { wr $GENFIFO $gf }
    wr $CFG [expr {$cfg | 0x10000000}]
    for {set i 0} {$i < 200} {incr i} {
        set isr [rd $ISR] ; if {$isr ne "ERR" && ($isr & $ISR_RXEMPTY) == 0} break ; after 2
    }
    return [rd $RXD]
}

# --- read N bytes from ONE die (cmd 0x03 + 3-byte addr), on a given bus/cs. Returns a byte list. ---
# The stripe-mode read leaves the upper die at 0xFF (the mirrored command doesn't reach it), but each
# die answers fine when addressed alone — so we read them separately and interleave (read_dual).
proc read_die {cfg bus cs addr nbytes} {
    global SEL EN FIFOCTRL CFG GENFIFO TXD RXD ISR ISR_RXEMPTY
    wr $SEL 0x1 ; wr $EN 0x0 ; wr $FIFOCTRL 0x7 ; wr $CFG $cfg ; wr $EN 0x1
    # 3 address bytes, MSB-first on the wire -> low byte of the FIFO word is sent first.
    set addrword [expr {(($addr >> 16) & 0xFF) | ((($addr >> 8) & 0xFF) << 8) | (($addr & 0xFF) << 16)}]
    wr $GENFIFO [expr {$bus | $cs | 0x400 | 0xFF}]                 ;# CS assert
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | 0x03}]       ;# TX read cmd 0x03
    wr $TXD     $addrword
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | 0x100 | 0x3}];# TX 3-byte address (from TXFIFO)
    wr $GENFIFO [expr {0x20000 | $bus | $cs | 0x400 | 0x100 | ($nbytes & 0xFF)}]  ;# RX nbytes
    wr $GENFIFO [expr {$bus | 0xFF}]                               ;# CS deassert
    wr $CFG [expr {$cfg | 0x10000000}]
    # The RX FIFO fills progressively (backpressure) — must poll RX-not-empty before EACH word, or a
    # read races ahead of the fill and grabs stale/zero data. (A poll-once optimization corrupted the
    # dump; reverted. The slow part is this 2-reads-per-word, which is why DMA mode is the real fix.)
    set bytes {}
    set nwords [expr {($nbytes + 3) / 4}]
    for {set w 0} {$w < $nwords} {incr w} {
        set ok 0
        for {set i 0} {$i < 500} {incr i} {
            set isr [rd $ISR] ; if {$isr ne "ERR" && ($isr & $ISR_RXEMPTY) == 0} { set ok 1 ; break } ; after 1
        }
        if {!$ok} { return "TIMEOUT" }
        set word [rd $RXD] ; if {$word eq "ERR"} { return "ERR" }
        lappend bytes [expr {$word & 0xFF}] [expr {($word>>8)&0xFF}] [expr {($word>>16)&0xFF}] [expr {($word>>24)&0xFF}]
    }
    return [lrange $bytes 0 [expr {$nbytes-1}]]
}

# --- read $nbytes LOGICAL bytes from logical $offset across the dual-parallel pair, by interleaving ---
# lower die holds even logical bytes, upper die holds odd. per-die addr = offset>>1, per-die n = nbytes/2.
proc flash_read {cfg offset nbytes} {
    set pd_addr [expr {$offset >> 1}]
    set pd_n    [expr {($nbytes + 1) / 2}]
    set lo [read_die $cfg 0x4000 0x1000 $pd_addr $pd_n]   ;# lower bus/cs -> even bytes
    set up [read_die $cfg 0x8000 0x2000 $pd_addr $pd_n]   ;# upper bus/cs -> odd bytes
    foreach r [list $lo $up] { if {$r eq "ERR" || $r eq "TIMEOUT"} { return $r } }
    set out {}
    for {set k 0} {$k < $pd_n} {incr k} { lappend out [lindex $lo $k] [lindex $up $k] }
    return [lrange $out 0 [expr {$nbytes-1}]]
}

# --- Program the QSPIDMA DST channel into an operational (un-paused) state. ---
# THE PARKED-DMA FIX: the PMU's idle_hooks.c sets DST_CTRL.PAUSE_MEM|PAUSE_STRM when it idles QSPI,
# which makes a DMA "complete" (DONE sets) but stream ZERO bytes to DDR. We read DST_CTRL; if it looks
# uninitialised (0) we install the driver operational value 0x803FFA00; either way we CLEAR the PAUSE
# bits, and program DST_CTRL2. Returns the post-write DST_CTRL value (or "ERR").
proc dma_unpause {} {
    global DST_CTRL DST_CTRL2 DST_CTRL_OPVAL DST_CTRL2_OPVAL DST_CTRL_PAUSE
    # Preserve the firmware-programmed control regs — only ever CLEAR the PAUSE bits, never clobber the
    # AXI/FIFO attribute fields. (An earlier version force-wrote DST_CTRL2=0xFFF8, wiping the HW upper
    # bits 0x081B0000 and garbling the DMA'd data.) Install a sane default ONLY if the reg reads 0.
    set cur [rd $DST_CTRL]
    if {$cur eq "ERR"} { return "ERR" }
    if {$cur == 0} { set cur $DST_CTRL_OPVAL }
    set new [expr {$cur & ~$DST_CTRL_PAUSE}]      ;# clear PAUSE_MEM|PAUSE_STRM only
    if {$new != $cur} { wr $DST_CTRL $new }
    set cur2 [rd $DST_CTRL2]
    # restore the AXI/FIFO attribute bits if they're missing (==0 fresh, or wiped by the old bad write)
    if {$cur2 ne "ERR" && ($cur2 & 0xFFFF0000) == 0} { wr $DST_CTRL2 $DST_CTRL2_OPVAL }
    return [rd $DST_CTRL]
}

# --- DMA-read $nbytes (power-of-2) from ONE die into DDR $dst, then the caller block-reads $dst. ---
# MODE_EN=2'b10 (DMA) -> the controller streams flash data to DDR via the on-chip DMA, so we read it
# back with a fast block read_memory instead of the slow keyhole RXD. nbytes must be a power of 2
# (the GEN_FIFO exponent field). Returns 1 if the DMA DONE bit set, else 0.
proc dma_read_die {bus cs addr nbytes dst} {
    global SEL EN FIFOCTRL CFG GENFIFO TXD DST_ADDR DST_SIZE DST_I_STS DST_ADDR_MSB
    set exp 0 ; set t $nbytes ; while {$t > 1} { set t [expr {$t >> 1}] ; incr exp }
    # ORDER MATTERS: reset+configure the controller (clears the RX/GEN FIFOs) BEFORE arming the DMA.
    # Arming DST_SIZE while the RXFIFO still holds residual bytes makes the DMA write pointer start
    # mid-buffer, so the (otherwise byte-perfect) data lands ROTATED. Controller-first → clean start.
    set dcfg [expr {[info exists ::env(QSPI_DCFG)] ? $::env(QSPI_DCFG) : 0xA000001E}]
    ;# default 0xA000001E = MODE_EN=10(DMA) | GEN_FIFO_START_MODE(manual,bit29) | mode-3 clock/baud.
    # Perform Abort per UG1085 Fig 24-8: "switch I/O mode AND clear RXFIFO" BEFORE entering DMA mode.
    # A FIFO reset issued while already in DMA mode does NOT flush the RXFIFO; the residual RX words
    # then prepend to the DMA stream and the (byte-perfect) data lands ROTATED by that residual count.
    wr $SEL 0x1
    wr $EN 0x0
    wr $CFG 0x20000018          ;# I/O mode (MODE_EN=2'b00), manual start
    wr $FIFOCTRL 0x7            ;# flush GEN/TX/RX FIFOs while in I/O mode
    wr $CFG $dcfg               ;# now switch to DMA mode (MODE_EN=2'b10)
    wr $EN 0x1
    # ---- now set up + arm the DMA destination channel ----
    # The QSPIDMA DST-FIFO has a fixed ~132-byte fill latency when driven one-shot from JTAG, so its
    # write pointer starts LEADIN bytes into the buffer and wraps at DST_SIZE -> the (byte-perfect) data
    # lands ROTATED. DST_SIZE stays = nbytes (matches the 2^exp flash RX, so the DMA completes promptly);
    # the caller un-rotates the read-back by LEADIN in software (see dmadump). Growing DST_SIZE instead
    # would stall the DMA waiting for bytes the flash never sends.
    dma_unpause
    wr $DST_ADDR     $dst
    wr $DST_ADDR_MSB 0x0
    wr $DST_I_STS    0xFE             ;# clear DMA interrupt status (write-1-clear)
    wr $DST_SIZE     $nbytes          ;# = 2^exp flash RX -> DMA completes cleanly (no stall)
    # Canonical page-read GEN_FIFO sequence per UG1085 Table 24-21: opcode + 3 address bytes are sent
    # as IMMEDIATE entries (data_xfer=0, imm=byte), NOT via the TXFIFO. The TXFIFO-address path works
    # in PIO but delivers a wrong/incomplete address in DMA mode (flash returns garbage). CS assert/
    # deassert carry the SPI-mode bit (0x400) and small setup/hold counts (imm 0x04), per the table.
    set b1 [expr {($addr >> 16) & 0xFF}]
    set b2 [expr {($addr >>  8) & 0xFF}]
    set b3 [expr {$addr & 0xFF}]
    wr $GENFIFO [expr {$bus | $cs | 0x400 | 0x04}]                  ;# CS assert (setup 4 REFCLK)
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | 0x03}]        ;# TX opcode 0x03 (immediate)
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | $b1}]         ;# TX addr[23:16] (immediate)
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | $b2}]         ;# TX addr[15:8]
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | $b3}]         ;# TX addr[7:0]
    wr $GENFIFO [expr {0x20000 | $bus | $cs | 0x400 | 0x200 | 0x100 | $exp}]  ;# RX 2^exp bytes (DMA)
    wr $GENFIFO [expr {$bus | 0x400 | 0x04}]                        ;# CS deassert (hold 4 REFCLK)
    wr $CFG [expr {$dcfg | 0x10000000}]                            ;# manual start (START_GEN_FIFO)
    for {set i 0} {$i < 4000} {incr i} {                           ;# ~8s cap (a good DMA completes in ~35)
        set s [rd $DST_I_STS] ; if {$s ne "ERR" && ($s & 0x2)} { return 1 }
    }
    return 0
}

# Single-die RDID on a specific bus/cs — to test whether each die is individually reachable.
# bus: lower=0x4000 upper=0x8000 ; cs: lower=0x1000 upper=0x2000.
proc rdid_bus {cfg bus cs} {
    global SEL EN FIFOCTRL CFG GENFIFO ISR RXD ISR_RXEMPTY
    wr $SEL 0x1 ; wr $EN 0x0 ; wr $FIFOCTRL 0x7 ; wr $CFG $cfg ; wr $EN 0x1
    wr $GENFIFO [expr {$bus | $cs | 0x400 | 0xFF}]
    wr $GENFIFO [expr {0x10000 | $bus | $cs | 0x400 | 0x9F}]
    wr $GENFIFO [expr {0x20000 | $bus | $cs | 0x400 | 0x100 | 0x3}]
    wr $GENFIFO [expr {$bus | 0xFF}]
    wr $CFG [expr {$cfg | 0x10000000}]
    for {set i 0} {$i < 200} {incr i} { set isr [rd $ISR] ; if {$isr ne "ERR" && ($isr & $ISR_RXEMPTY)==0} break ; after 2 }
    return [rd $RXD]
}

if {$OP eq "id"} {
    set found 0
    foreach {mode add} {mode0 0x0 mode1(CPHA) 0x4 mode2(CPOL) 0x2 mode3(CPOL+CPHA) 0x6} {
        set cfg [expr {0x20000018 | $add}]
        set idw [do_rdid $cfg]
        if {$idw eq "ERR"} { puts [format " %-14s CFG=0x%08X -> read ERR" $mode $cfg] ; continue }
        set b0 [expr {$idw & 0xFF}] ; set mfg [expr {[info exists MFG([format 0x%02X $b0])] ? $MFG([format 0x%02X $b0]) : "?"}]
        puts [format " %-14s CFG=0x%08X -> RXD=0x%08X  mfg=0x%02X (%s)" $mode $cfg $idw $b0 $mfg]
        if {$mfg ne "?" && $b0 != 0x00 && $b0 != 0xFF} { set found 1 ; set win_cfg $cfg ; set win_id $idw ; set win_mfg $mfg }
    }
    puts ""
    if {$found} {
        puts [format " RESULT: PASS — JEDEC ID 0x%06X (%s) at CFG=0x%08X." [expr {$win_id & 0xFFFFFF}] $win_mfg $win_cfg]
    } else {
        puts " RESULT: SUSPECT — all modes returned 0x00/0xFF."
    }

} elseif {$OP eq "read"} {
    set off [expr {[info exists ::env(QSPI_OFFSET)] ? $::env(QSPI_OFFSET) : 0}]
    set len [expr {[info exists ::env(QSPI_LEN)] ? $::env(QSPI_LEN) : 64}]
    # per-die RDID probe: is each die individually reachable? (low byte should be 0x20 = Micron)
    set lo [rdid_bus $RD_CFG 0x4000 0x1000]
    set up [rdid_bus $RD_CFG 0x8000 0x2000]
    puts [format " per-die RDID:  lower=0x%08X (mfg 0x%02X)   upper=0x%08X (mfg 0x%02X)" \
                 $lo [expr {$lo & 0xFF}] $up [expr {$up & 0xFF}]]
    puts "   (both mfg=0x20 -> read each die separately + interleave; upper 0xFF -> upper bus/cs issue)"
    puts ""
    puts [format " dual-parallel read (per-die + software interleave): offset 0x%X, %d bytes" $off $len]
    puts ""
    set bytes [flash_read $RD_CFG $off $len]
    if {$bytes eq "TIMEOUT" || $bytes eq "ERR"} {
        puts " RESULT: read returned $bytes — no/partial data (check stripe/addr encoding)."
    } else {
        set n [llength $bytes]
        for {set i 0} {$i < $n} {incr i 16} {
            set row ""
            for {set j 0} {$j < 16 && $i+$j < $n} {incr j} { append row [format "%02x " [lindex $bytes [expr {$i+$j}]]] }
            puts [format "  %04x: %s" [expr {$off+$i}] $row]
        }
        if {$off == 0 && $n >= 0x28} {
            set ok [expr {[lindex $bytes 0]==0xfe && [lindex $bytes 1]==0xff && [lindex $bytes 2]==0xff && [lindex $bytes 3]==0xea \
                       && [lindex $bytes 0x24]==0x58 && [lindex $bytes 0x25]==0x4e && [lindex $bytes 0x26]==0x4c && [lindex $bytes 0x27]==0x58}]
            puts ""
            puts "  check: bytes 0-3 expect fe ff ff ea (ARM vector);  bytes 0x24-0x27 expect 58 4e 4c 58 (XLNX)"
            if {$ok} {
                puts " RESULT: PASS — per-die read matches the known boot header. The bulk dumper is GO."
            } else {
                puts " RESULT: MISMATCH — data returned but not the expected header (bus or addr byte-order)."
            }
        }
    }

} elseif {$OP eq "dump"} {
    set off   [expr {[info exists ::env(QSPI_OFFSET)] ? $::env(QSPI_OFFSET) : 0}]
    set size  [expr {[info exists ::env(QSPI_SIZE)]   ? $::env(QSPI_SIZE)   : 0x10000}]
    set out   [expr {[info exists ::env(QSPI_OUT)]    ? $::env(QSPI_OUT)    : "dumps/qspi-jtag.bin"}]
    set chunk 256   ;# logical bytes/transaction = 128/die = the 32-word RX FIFO depth (no overflow)
    puts [format " QSPI dump: offset 0x%X, 0x%X bytes -> %s" $off $size $out]
    puts "   (per-die read + interleave, 3-byte addr; boot image < 16MB/die so 3-byte suffices)"
    puts ""
    set fh [open $out wb] ; fconfigure $fh -translation binary
    set done 0 ; set fail 0 ; set t0 [clock milliseconds]
    while {$done < $size} {
        set this [expr {($size - $done) < $chunk ? ($size - $done) : $chunk}]
        set bytes [flash_read $RD_CFG [expr {$off + $done}] $this]
        if {$bytes eq "ERR" || $bytes eq "TIMEOUT"} {
            set bytes {} ; for {set k 0} {$k < $this} {incr k} { lappend bytes 0xFF }
            incr fail ; clrsticky
        }
        puts -nonewline $fh [binary format c* $bytes]
        incr done $this
        if {($done % 0x2000) == 0 || $done >= $size} {
            puts [format "   %5d / %d KB   (%d chunk fail)" [expr {$done/1024}] [expr {$size/1024}] $fail]
        }
    }
    close $fh
    set secs [expr {([clock milliseconds] - $t0) / 1000}]
    puts ""
    puts [format " dumped %d bytes -> %s in %ds (%d chunk failures)" $done $out $secs $fail]
    puts "   separate:  python3 tools/parse-bootimage.py $out --extract dumps/qspi-parts/"

} elseif {$OP eq "dmaread"} {
    # DMA SELF-TEST + DIAGNOSTIC: stream the LOWER die (offset 0, power-of-2 bytes) into DDR scratch,
    # block-read it back, AND cross-check against a slow PIO read of the same region — the definitive
    # "did the DMA move real flash data?" verdict. Dumps the full QSPIDMA DST channel state so a failure
    # is diagnosable from one run. The lower die holds the boot image's EVEN logical bytes (fe fe ...).
    set dst [expr {[info exists ::env(QSPI_DMA_DST)] ? $::env(QSPI_DMA_DST) : 0x40000000}]
    set len [expr {[info exists ::env(QSPI_LEN)]     ? $::env(QSPI_LEN)     : 0x1000}]   ;# power of 2
    set out [expr {[info exists ::env(QSPI_OUT)]     ? $::env(QSPI_OUT)     : "dumps/qspi-dma-lower.bin"}]
    puts [format " DMA read: LOWER die offset 0, %d bytes -> DDR scratch 0x%X -> %s" $len $dst $out]
    puts "   (clobbers DDR at the scratch addr — cores are halted so the buffer survives)"

    # ---- destination channel state BEFORE (catches the PMU idle_hooks PAUSE) ----
    puts [format " DST_CTRL before = %s   DST_CTRL2 before = %s" [rdhex $DST_CTRL] [rdhex $DST_CTRL2]]
    set cb [rd $DST_CTRL]
    if {$cb ne "ERR" && ($cb & 0x3)} {
        puts "   >> DST_CTRL PAUSE bits SET (PAUSE_MEM/STRM) — this is the parked-DMA cause. Un-pausing."
    }
    set ca [dma_unpause]
    puts [format " DST_CTRL after  = %s   (PAUSE bits cleared)   DST_CTRL2 = %s" \
            [expr {$ca eq "ERR" ? "ERR" : [format 0x%08X $ca]}] [rdhex $DST_CTRL2]]

    set ok [dma_read_die 0x4000 0x1000 0 $len $dst]
    set ists [rd $DST_I_STS]
    puts [format " DMA DONE=%d   DST_STS=%s   DST_SIZE(rb)=%s   DST_ADDR(rb)=%s   DST_I_STS=%s" \
            $ok [rdhex $DST_STS] [rdhex $DST_SIZE] [rdhex $DST_ADDR] [rdhex $DST_I_STS]]
    if {$ists ne "ERR"} {
        puts [format "   I_STS bits: DONE(1)=%d AXI_BRESP_ERR(2)=%d TIMEOUT_STRM(3)=%d TIMEOUT_MEM(4)=%d THRESH_HIT(5)=%d INVALID_APB(6)=%d FIFO_OVF(7)=%d" \
            [expr {($ists>>1)&1}] [expr {($ists>>2)&1}] [expr {($ists>>3)&1}] [expr {($ists>>4)&1}] [expr {($ists>>5)&1}] [expr {($ists>>6)&1}] [expr {($ists>>7)&1}]]
        if {($ists>>2)&1} { puts "   >> AXI_BRESP_ERR set: the QSPI-DMA write was REJECTED — the DDR XMPU is blocking the DMA master. Open the XMPU for it." }
        if {($ists>>6)&1} { puts "   >> INVALID_APB set: a bad register access during DMA setup." }
    }
    if {$ok} {
        set leadin [expr {[info exists ::env(QSPI_LEADIN)] ? $::env(QSPI_LEADIN) : 132}]
        set leadin [expr {$leadin % $len}]
        binary scan [binary format i* [read_memory $dst 32 [expr {$len / 4}]]] cu* allb
        set allb [_derot $allb $leadin]                 ;# un-rotate by the DST-FIFO lead-in
        set fh [open $out wb] ; fconfigure $fh -translation binary
        puts -nonewline $fh [binary format c* $allb] ; close $fh
        # ---- cross-check vs a PIO read of the SAME lower-die region (ground truth) ----
        set pio [read_die $RD_CFG 0x4000 0x1000 0 [expr {$len < 64 ? $len : 64}]]
        set dmab [lrange $allb 0 63]
        set match 1 ; set ncmp 0
        if {$pio ne "ERR" && $pio ne "TIMEOUT"} {
            set ncmp [expr {[llength $pio] < [llength $dmab] ? [llength $pio] : [llength $dmab]}]
            for {set k 0} {$k < $ncmp} {incr k} { if {[lindex $pio $k] != [lindex $dmab $k]} { set match 0 ; break } }
        } else { set match -1 }
        puts " wrote $out (de-rotated by lead-in $leadin) — first 16 bytes:"
        set h "" ; foreach x [lrange $allb 0 15] { append h [format "%02x " $x] }
        puts "   $h"
        puts ""
        if {$match == 1 && $ncmp > 0} {
            puts " RESULT: PASS — DMA data matches the PIO read over $ncmp bytes. The DMA path WORKS;"
            puts "         use QSPI_OP=dmadump for the fast bulk dump."
        } elseif {$match == 0} {
            puts " RESULT: MISMATCH — DMA completed but its bytes differ from the PIO read. The DMA moved"
            puts "         stale/zero data (still not streaming). Check DST_CTRL above and DST_SIZE units."
        } else {
            puts " RESULT: INCONCLUSIVE — PIO cross-check read failed; compare $out to a known image by hand."
        }
    } else {
        puts " DMA did NOT complete (DONE never set) — check DST_CTRL (PAUSE), DST_SIZE units, dest addr."
    }

} elseif {$OP eq "dmadump"} {
    # FAST BULK DUMP via DMA. Each block: DMA each die into OCM scratch (on-chip -> no DDR cache-coherency
    # on read-back), block-read with ONE pipelined read_memory. The QSPIDMA DST-FIFO lead-in (a rotation
    # offset = the FIFO fill latency) VARIES per session, so it's AUTO-CALIBRATED PER BLOCK: a 16-byte PIO
    # probe at mid-block pins each die's rotation (_find_leadin), then the block is de-rotated in software.
    # The first `lead-in` raw bytes are DST-FIFO junk and land at the de-rotated tail, so blocks OVERLAP by
    # the lead-in: each block EMITS only its good leading bytes and the next block re-reads the tail. If a
    # block can't be pinned (erased/repeat) or its DMA fails, it falls back to PIO flash_read (after a clean
    # I/O reset) -> output is ALWAYS byte-exact + complete. Much faster than full PIO on real data.
    set off  [expr {[info exists ::env(QSPI_OFFSET)] ? $::env(QSPI_OFFSET) : 0}]
    set size [expr {[info exists ::env(QSPI_SIZE)]   ? $::env(QSPI_SIZE)   : 0x100000}]
    set out  [expr {[info exists ::env(QSPI_OUT)]    ? $::env(QSPI_OUT)    : "dumps/qspi-dma.bin"}]
    set dlo  [expr {[info exists ::env(QSPI_DMA_DST)] ? $::env(QSPI_DMA_DST) : 0xFFFC8000}]   ;# OCM scratch
    set pdblk [expr {[info exists ::env(QSPI_PDBLK)] ? $::env(QSPI_PDBLK) : 4096}]  ;# per-die DMA bytes/block (pow2)
    set dup  [expr {$dlo + ($pdblk < 0x2000 ? 0x2000 : $pdblk)}]   ;# upper-die scratch, spaced >= block size
    set blk   [expr {$pdblk * 2}] ; set nw [expr {$pdblk / 4}]
    set probe [expr {$pdblk / 2}]                       ;# PIO calibration probe offset (mid-block)
    set end   [expr {$off + (($size + $blk - 1) / $blk) * $blk}]   ;# round-up end (logical)

    # de-rotate amount for a clean-rotated block: ref = true 16 B at per-die offset $probe; locate it
    # circularly in $dmab. leadin = (p - probe) mod N. -1 if not UNIQUELY locatable (-> PIO that block).
    proc _find_leadin {dmab ref probe N} {
        if {$ref eq "ERR" || $ref eq "TIMEOUT"} { return -1 }
        set rl [llength $ref] ; set r0 [lindex $ref 0] ; set hits {}
        for {set p 0} {$p < $N} {incr p} {
            if {[lindex $dmab $p] != $r0} { continue }
            set ok 1
            for {set k 1} {$k < $rl} {incr k} { if {[lindex $dmab [expr {($p+$k)%$N}]] != [lindex $ref $k]} { set ok 0 ; break } }
            if {$ok} { lappend hits [expr {(($p - $probe) % $N + $N) % $N}] }
        }
        set u [lsort -unique $hits]
        if {[llength $u] == 1} { return [lindex $u 0] }
        return -1
    }
    # calibrate one die's lead-in by trying SEVERAL probe offsets — a single mid-block window can land on
    # a repetitive run (ambiguous) even in real data, which would lose the block to 0xFF. Returns the
    # lead-in from the first offset that pins uniquely, or -1 if the whole block is uniform/erased.
    proc _calib_die {dmab cfg bus cs pd_addr N} {
        foreach po [list [expr {$N/2}] [expr {$N/4}] [expr {3*$N/4}] [expr {$N/8}] [expr {7*$N/8}] 64] {
            set L [_find_leadin $dmab [read_die $cfg $bus $cs [expr {$pd_addr + $po}] 16] $po $N]
            if {$L >= 0} { return $L }
        }
        return -1
    }
    puts [format " QSPI DMA dump: offset 0x%X, 0x%X bytes -> %s" $off [expr {$end-$off}] $out]
    puts [format "   OCM scratch: lower=0x%X upper=0x%X   per-block lead-in auto-calibration + overlap" $dlo $dup]
    dma_unpause
    puts ""

    set fh [open $out wb] ; fconfigure $fh -translation binary
    set t0 [clock milliseconds] ; set fail 0 ; set nblk 0 ; set emitted 0
    # The lead-in is SESSION-STABLE, so calibrate it ONCE and only re-probe every CHECK blocks (drift
    # tripwire) instead of every block — the per-block PIO probe + lead-in search was the main avoidable
    # cost. sLlo/sLup are the cached per-die lead-ins; -1 forces a (re)calibration.
    set sLlo -1 ; set sLup -1 ; set since 9999 ; set CHECK 24 ; set boff $off
    while {$boff < $end} {
        set pd_addr [expr {$boff >> 1}]
        set G 0 ; set lob {} ; set upb {}
        for {set try 0} {$try < 3 && $G <= 0} {incr try} {
            set okl [dma_read_die 0x4000 0x1000 $pd_addr $pdblk $dlo]
            set oku [dma_read_die 0x8000 0x2000 $pd_addr $pdblk $dup]
            if {!($okl && $oku)} { dma_unpause ; continue }
            binary scan [binary format i* [read_memory $dlo 32 $nw]] cu* lob
            binary scan [binary format i* [read_memory $dup 32 $nw]] cu* upb
            # (re)calibrate only when due: first block, every CHECK blocks, or after a retry. Multi-offset
            # probing so a repetitive 16-B window in REAL data doesn't lose the block (only truly erased
            # regions stay -1 -> they then de-rotate by the cached sL, a no-op on uniform data).
            if {$sLlo < 0 || $sLup < 0 || $since >= $CHECK || $try > 0} {
                set rLlo [_calib_die $lob $RD_CFG 0x4000 0x1000 $pd_addr $pdblk]
                set rLup [_calib_die $upb $RD_CFG 0x8000 0x2000 $pd_addr $pdblk]
                if {$rLlo >= 0} { set sLlo $rLlo }   ;# refresh from a fresh unique match (uniform region -> keep cached)
                if {$rLup >= 0} { set sLup $rLup }
                set since 0
            }
            if {$sLlo >= 0 && $sLup >= 0} {
                set lob [_derot $lob $sLlo] ; set upb [_derot $upb $sLup]
                set Lm $sLlo ; if {$sLup > $Lm} { set Lm $sLup }    ;# (Jim Tcl expr has no max())
                set G [expr {$pdblk - $Lm - 8}]                     ;# good per-die bytes (drop the junk tail)
                if {$nblk < 2} { puts [format "   lead-in lo=%d up=%d  good/die=%d  (calibrate once, re-probe every %d blocks)" $sLlo $sLup $G $CHECK] }
            }
        }
        if {$G > 0} {
            set rem [expr {($end - $boff) / 2}]               ;# per-die logical bytes still wanted
            if {$G > $rem} { set G $rem }
            set ob {}                                          ;# parallel-foreach interleave (faster than indexed for)
            foreach x [lrange $lob 0 [expr {$G-1}]] y [lrange $upb 0 [expr {$G-1}]] { lappend ob $x $y }
            puts -nonewline $fh [binary format c* $ob]
            incr boff [expr {2*$G}] ; incr emitted [expr {2*$G}] ; incr since
        } else {
            # could not DMA+calibrate after retries (rare: hard DMA fail, or block 0 itself uniform).
            incr fail
            set fb [expr {$end - $boff}] ; if {$fb > $blk} { set fb $blk }
            puts -nonewline $fh [binary format c* [lrepeat $fb 0xFF]]
            incr boff $fb ; incr emitted $fb
        }
        incr nblk
        if {($nblk % 24) == 0 || $boff >= $end} {
            set el [expr {([clock milliseconds] - $t0) / 1000 + 1}]
            puts [format "   %5d / %d KB   (%d uncovered(0xFF))   %d KB/s" \
                    [expr {$emitted/1024}] [expr {($end-$off)/1024}] $fail [expr {($emitted/1024)/$el}]]
        }
    }
    close $fh
    set secs [expr {([clock milliseconds] - $t0) / 1000}]
    puts ""
    puts [format " DMA-dumped %d bytes -> %s in %ds (%d uncovered(0xFF))" $emitted $out $secs $fail]
    puts "   verify:    python3 tools/parse-bootimage.py $out --extract dumps/qspi-parts/"
}
puts "================================================================"
