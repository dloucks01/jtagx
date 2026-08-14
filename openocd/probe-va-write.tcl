# probe-va-write.tcl — can JTAG overwrite running-kernel instructions (VA, MMU on)?
# Decides whether an in-place VA-patch live injection is feasible.
# Halts all A53 cores, snapshots 2 words at core0's current PC, writes NOPs,
# reads back, then RESTORES and resumes. Read-back == NOPs => RO bypassed (patch
# feasible). Tries both the core (VA) path and the AXI-AP (physical) path.

proc _pc {} {
    if {[catch {reg pc} out]} { return 0 }
    if {[regexp {0x[0-9a-fA-F]+} $out m]} { return $m }
    return 0
}

# freeze all cores
foreach c {uscale.a53.0 uscale.a53.1 uscale.a53.2 uscale.a53.3} {
    catch { $c arp_examine } _
    catch { targets $c; halt } _
}
targets uscale.a53.0
after 50

set P [_pc]
echo "=== core0 PC = $P ==="
if {$P == 0} { echo "could not read PC"; resume; shutdown }

set NOP 0xd503201f

# --- Path A: write via the core (uscale.a53.0 -> VA, subject to MMU RO) ---
echo "--- Path A: core/VA write ---"
catch { targets uscale.a53.0 } _
set origA "ERR"
if {[catch {read_memory $P 32 2} origA]} { echo "VA read failed: $origA"; set origA "ERR" }
echo "VA orig    : $origA"
catch { write_memory $P 32 [list $NOP $NOP] } werrA
set rbA "ERR"
catch {read_memory $P 32 2} rbA
echo "VA readback: $rbA"
if {$origA ne "ERR"} { catch { write_memory $P 32 $origA } _ }
set vaStuck 0
if {$rbA ne "ERR" && [lindex $rbA 0] == $NOP} { set vaStuck 1 }
echo "VA_WRITE_STUCK: $vaStuck"

# --- Path B: write via AXI-AP (uscale.axi -> PHYSICAL; only valid if P is a
#     physical-equal address, which a kernel VA is NOT — expected to miss, but
#     confirms the physical path is distinct). ---
echo "--- Path B: axi/PHYS write at same numeric addr (sanity, expect no effect on VA) ---"
catch { targets uscale.axi } _
set rbB "ERR"
catch {read_memory $P 32 2} rbB
echo "PHYS read at \$P: $rbB  (kernel VA via phys AP — likely ERR/garbage)"

# restore + resume everything
catch { targets uscale.a53.0 } _
if {$origA ne "ERR"} {
    catch { write_memory $P 32 $origA } _
    set chk "ERR"; catch {read_memory $P 32 2} chk
    echo "VA restored: $chk"
}
foreach c {uscale.a53.0 uscale.a53.1 uscale.a53.2 uscale.a53.3} {
    catch { targets $c; resume } _
}
echo "=== cores resumed ==="
