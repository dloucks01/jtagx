# probe-csu-surface.tcl — Tier-1 CSU attack-surface characterization.
#
# Non-destructive JTAG/DAP-NS map of the CSU command/engine surface, hunting for
# a BootROM-leak or family-key-oracle opening (see docs/13-attack-research-plan.md,
# vectors 1.1, 1.3, 2.1). Read-mostly; the two field-characterization sections
# WRITE a register then RESTORE its original value (CSU is idle post-boot, low
# risk). To run read-only, set ::CSU_SURFACE_RO 1 before sourcing.
#
# Usage (board can be at JTAG-idle or booted):
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-csu-surface.tcl; shutdown"
#
# Output: reports/csu-surface-<ts>.md (raw values; no summaries).

catch { targets uscale.axi } _
catch { uscale.dap dpreg 0 0x1e } _    ;# clear DP sticky

set _ro 0
if {[info exists ::CSU_SURFACE_RO]} { set _ro $::CSU_SURFACE_RO }

set ts [clock format [clock seconds] -format %Y-%m-%d-%H%M%S]
file mkdir reports
set out "reports/csu-surface-$ts.md"
set fh [open $out w]
proc emit {s} { global fh; puts $fh $s; echo $s }

proc rd {addr} {
    if {[catch {read_memory $addr 32 1} r]} { return "ERR" }
    return [format "0x%08X" [expr {[lindex $r 0] & 0xFFFFFFFF}]]
}
proc rdi {addr} {
    if {[catch {read_memory $addr 32 1} r]} { return -1 }
    return [expr {[lindex $r 0] & 0xFFFFFFFF}]
}
proc wr {addr val} { catch { write_memory $addr 32 [list $val] } }

emit "# CSU attack-surface characterization — $ts"
emit ""
emit "Tier-1 probe per docs/13-attack-research-plan.md. read-only mode = $_ro"
emit ""

# ---------------------------------------------------------------------------
emit "## 1. CSU control-page key registers"
# ---------------------------------------------------------------------------
foreach {addr name} {
    0xFFCA0000 CSU_STATUS
    0xFFCA0004 CSU_CTRL
    0xFFCA0008 CSU_SSS_CFG
    0xFFCA0010 CSU_MULTI_BOOT
    0xFFCA0018 CSU_FT_STATUS
    0xFFCA0038 JTAG_SEC
    0xFFCA003C JTAG_DAP_CFG
    0xFFCA0040 IDCODE
    0xFFCA0044 VERSION
} {
    emit [format "  %-16s %s = %s" $name $addr [rd $addr]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 2. CSU AES engine (0xFFCA1000)"
# ---------------------------------------------------------------------------
foreach {addr name} {
    0xFFCA1000 AES_STATUS
    0xFFCA1004 AES_KEY_SRC
    0xFFCA1008 AES_KEY_LOAD
    0xFFCA100C AES_START_MSG
    0xFFCA1010 AES_RESET
    0xFFCA1014 AES_KEY_CLR
    0xFFCA101C AES_KUP_WR
} {
    emit [format "  %-16s %s = %s" $name $addr [rd $addr]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 3. CSU SHA (0xFFCA2000) + PUF (0xFFCA4000)"
# ---------------------------------------------------------------------------
foreach {addr name} {
    0xFFCA2000 SHA_START
    0xFFCA2008 SHA_DONE
    0xFFCA4000 PUF_CMD
    0xFFCA4010 PUF_STATUS
} {
    emit [format "  %-16s %s = %s" $name $addr [rd $addr]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 4. CSU DMA channels (CSUDMA 0xFFC80000: SRC +0x00, DST +0x80)"
# ---------------------------------------------------------------------------
foreach {addr name} {
    0xFFC80000 SRC_ADDR
    0xFFC80004 SRC_SIZE
    0xFFC80008 SRC_STS
    0xFFC8000C SRC_CTRL
    0xFFC80014 SRC_ADDR_MSB
    0xFFC80080 DST_ADDR
    0xFFC80084 DST_SIZE
    0xFFC80088 DST_STS
    0xFFC8008C DST_CTRL
    0xFFC80094 DST_ADDR_MSB
} {
    emit [format "  %-16s %s = %s" $name $addr [rd $addr]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 5. SSS_CFG source-select characterization (vector 1.1)"
emit "   write field patterns to CSU_SSS_CFG (0xFFCA0008), read back which bits"
emit "   latch (maps which sources are routable to DMA/AES/SHA/PCAP sinks)."
# ---------------------------------------------------------------------------
set sss_orig [rdi 0xFFCA0008]
emit [format "  original SSS_CFG = 0x%08X" $sss_orig]
if {$_ro} {
    emit "  (read-only mode: skipping write characterization)"
} else {
    foreach pat {0x00000000 0xFFFFFFFF 0x55555555 0xAAAAAAAA 0x0000000F 0x000000F0 0x00000F00 0x0000F000} {
        wr 0xFFCA0008 $pat
        emit [format "  wrote %s -> readback %s" $pat [rd 0xFFCA0008]]
    }
    wr 0xFFCA0008 $sss_orig
    emit [format "  restored SSS_CFG -> %s" [rd 0xFFCA0008]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 6. AES_KEY_SRC accepted-value characterization (vector 2.1)"
emit "   write candidate KEY_SRC values to 0xFFCA1004, read back which latch."
emit "   (which key sources the AES engine accepts at runtime - looking for an"
emit "   obfuscated/family/device source selectable outside the BootROM flow.)"
# ---------------------------------------------------------------------------
set ks_orig [rdi 0xFFCA1004]
emit [format "  original AES_KEY_SRC = 0x%08X" $ks_orig]
if {$_ro} {
    emit "  (read-only mode: skipping write characterization)"
} else {
    foreach v {0x00000000 0x00000001 0x00000002 0x00000003 0x00000004 0x00000005 0x00000006 0x00000007 0x0000000F 0xFFFFFFFF} {
        wr 0xFFCA1004 $v
        set back [rd 0xFFCA1004]
        set sts  [rd 0xFFCA1000]
        emit [format "  KEY_SRC <- %s  readback %s  AES_STATUS %s" $v $back $sts]
    }
    wr 0xFFCA1004 $ks_orig
    emit [format "  restored AES_KEY_SRC -> %s" [rd 0xFFCA1004]]
}
emit ""

# ---------------------------------------------------------------------------
emit "## 7. CSU control sub-block per-word sweep with fault-recovery (vector 1.3)"
emit "   read 0xFFCA0000..0xFFCA00FC one word at a time; recover sticky on FAULT."
emit "   0xFFCA001C and 0xFFCA0030 are undocumented/reserved - watch them."
# ---------------------------------------------------------------------------
set nz 0; set nf 0
for {set off 0} {$off < 0x100} {incr off 4} {
    set a [expr {0xFFCA0000 + $off}]
    if {[catch {read_memory $a 32 1} r]} {
        emit [format "  0x%08X = FAULT (read wedged the DP - recovered)" $a]
        catch { uscale.dap dpreg 0 0x1e } _
        incr nf
        continue
    }
    set w [expr {[lindex $r 0] & 0xFFFFFFFF}]
    if {$w != 0} { incr nz; emit [format "  0x%08X = 0x%08X" $a $w] }
}
emit [format "  (%d non-zero, %d faulting in 0xFFCA0000..0xFFCA00FC)" $nz $nf]
emit ""

# ---------------------------------------------------------------------------
emit "## 8. AES-engine-wake live KEY_SRC test (vector 2.1 pivot)"
emit "   release AES_RESET, then for each KEY_SRC pulse KEY_LOAD and watch"
emit "   AES_STATUS - a cleared *_ZERO bit (8/9/10/11) = a real key got loaded"
emit "   from that source. All-0xF00 across sources = no usable runtime key path."
# ---------------------------------------------------------------------------
if {$_ro} {
    emit "  (read-only mode: skipping AES-wake test)"
} else {
    set aes_rst0 [rd 0xFFCA1010]
    set aes_ks0  [rdi 0xFFCA1004]
    emit [format "  AES_RESET before = %s ; releasing (write 0)" $aes_rst0]
    wr 0xFFCA1010 0x00000000
    after 5
    emit [format "  AES_STATUS after wake = %s" [rd 0xFFCA1000]]
    foreach {v label} {0 KUP 1 dev/eFuse 2 boot 3 operational 4 PUF 5 src5 6 src6 7 src7} {
        wr 0xFFCA1010 0x00000000
        wr 0xFFCA1004 $v
        wr 0xFFCA1008 0x00000001
        after 5
        emit [format "  KEY_SRC=%d (%-10s) -> AES_STATUS %s" $v $label [rd 0xFFCA1000]]
    }
    wr 0xFFCA1004 $aes_ks0
    wr 0xFFCA1010 0x00000001
    catch { uscale.dap dpreg 0 0x1e } _
    emit [format "  restored AES_KEY_SRC=%s AES_RESET=%s" [rd 0xFFCA1004] [rd 0xFFCA1010]]
}
emit ""

catch { uscale.dap dpreg 0 0x1e } _
emit "## done -> $out"
close $fh
echo "CSU surface report written to $out"
