# microsemi-access-check.tcl — the fabric-part access verdict: is this IGLOO2 / SmartFusion2 fabric
# device SECURITY-PROVISIONED (FlashLock / pass-key / AES set), or unprovisioned and therefore readable
# over the standard programming TAP?
#
# This is the fabric analog of jtag-access-check.tcl / cortexm-access-check.tcl and the VERIFY step of
# the guided flow: there is no CPU to halt, so "access" here means "can the eNVM / fabric bitstream be
# read back?". Non-destructive — IDCODE + a benign security-status read only.
#
#   openocd -f openocd/microsemi-fpga.cfg -c "init; source openocd/microsemi-access-check.tcl; shutdown"
#
# Verdict:
#   OPEN    — security NOT provisioned → SVF/DirectC readback of eNVM+fabric works over a plain FTDI
#             (microsemi-readback.tcl), no FlashPro, no pass-key.
#   LOCKED  — FlashLock / pass-key / AES provisioned → readback gated; escalate to DPA pass-key
#             recovery (Skorobogatov/Woods) or authorized FlashPro readback.

proc ms {s} { puts $s }
proc ms_hdr {s} { puts ""; puts "================================================================"; puts " $s"; puts "================================================================" }

# Read the fabric IDCODE (proves the TAP answers).
set idcode 0
if {![catch {drscan msfabric.tap 32 0x0 -endstate RUN/IDLE} v]} {
    catch { set idcode [expr {"0x$v"}] }
}

# Microsemi security-status query: IR opcode reads a status DR whose lock bits report whether
# FlashLock / pass-key / AES is provisioned. (Opcode + bit layout are device-family specific; the
# operator can override MSS_SECIR/MSS_SECLEN. Default probes the common status instruction.)
set secir  0x89
set seclen 32
if {[info exists ::env(MSS_SECIR)]}  { set secir  $::env(MSS_SECIR) }
if {[info exists ::env(MSS_SECLEN)]} { set seclen $::env(MSS_SECLEN) }

set locked -1   ;# -1 = couldn't read; 0 = unprovisioned; 1 = provisioned
if {![catch {irscan msfabric.tap $secir} _]} {
    if {![catch {drscan msfabric.tap $seclen 0x0} st]} {
        set stv 0
        catch { set stv [expr {"0x$st"}] }
        # any lock/security bit set ⇒ provisioned. 0 ⇒ open.
        set locked [expr {$stv != 0 ? 1 : 0}]
    }
}

ms_hdr "MICROSEMI FABRIC ACCESS CHECK"
ms [format "  fabric IDCODE     = 0x%08X" $idcode]
if {$locked == 1} {
    ms "  security status   = PROVISIONED (FlashLock / pass-key / AES bits set)"
} elseif {$locked == 0} {
    ms "  security status   = unprovisioned (no lock bits set)"
} else {
    ms "  security status   = UNREADABLE over JTAG — assume provisioned; confirm with FlashPro Inspect"
}
ms_hdr [format " ACCESS VERDICT: %s" [expr {$locked == 0 ? {OPEN} : {LOCKED}}]]
if {$locked == 0} {
    ms "  Unprovisioned — SVF/DirectC readback of eNVM + fabric bitstream works over this FTDI."
    ms "  next: microsemi-readback.tcl  (no FlashPro, no pass-key)"
} else {
    ms "  Readback gated. Escalate: DPA pass-key recovery (Skorobogatov/Woods) or authorized FlashPro."
}
