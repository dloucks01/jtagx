// cache-flush.S — make an EXTERNALLY-written (DAP AXI-AP / DMA) code patch coherent for execution.
//
// probe-phys-patch.tcl writes a patch to .text via the AXI-AP — a bus master that bypasses the MMU's
// read-only permission, so the bytes land in DRAM (Point of Coherency). But the A53s may still hold the
// OLD instruction in their per-core L1 I-cache and the unified L2 (Point of Unification), so the CPU keeps
// executing the stale instruction — the "write landed but isn't behavioral" caveat. This payload runs the
// architecturally-required maintenance to fix that, over a caller-supplied VA range:
//
//   x0 = start VA (inclusive)   x1 = end VA (exclusive)
//
//   pass 1:  DC CIVAC over each 64B line   — clean+invalidate D/unified cache to PoC (drops stale copies)
//   DSB ISH
//   pass 2:  IC IVAU  over each 64B line   — invalidate I-cache to PoU; IS-broadcast to ALL A53 cores
//   DSB ISH ; ISB                          — completion + this PE's pipeline/prefetch flush
//   BRK #0                                 — return control to the debugger (the driver restores context)
//
// This is the standard libgcc __clear_cache sequence. Cache maintenance by VA broadcasts within the Inner
// Shareable domain, so running it on ONE core makes the patch coherent cluster-wide. A53 line size = 64B.
//
// Position-independent (only x0/x1 inputs + a BRK). Delivered by a driver that halts a core, sets x0/x1 and
// PC=load addr, runs to the BRK, then restores the borrowed core's full context. The instructions must run
// at the OS's EL (EL1, MMU on) so the VAs resolve — i.e. on a LIVE (not COLD-reset) core.

.section .text
.global _start
_start:
    bic     x3, x0, #0x3f          // align start down to a 64-byte cache line
    mov     x4, x3                 // save aligned start for pass 2

1:  dc      civac, x3              // clean + invalidate D/unified cache to PoC
    add     x3, x3, #64
    cmp     x3, x1
    b.lo    1b
    dsb     ish                    // ensure all DC ops complete across the IS domain

    mov     x3, x4                 // rewind to the aligned start
2:  ic      ivau, x3               // invalidate I-cache to PoU (broadcast Inner-Shareable)
    add     x3, x3, #64
    cmp     x3, x1
    b.lo    2b
    dsb     ish                    // ensure all IC ops complete
    isb                            // flush this PE's pipeline / prefetch

    brk     #0                     // halt back to the debugger
