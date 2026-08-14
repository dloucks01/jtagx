// inject-demo.S — position-independent A53 demo payload for inject.tcl.
//
// Works at ANY load address (OCM/DDR/TCM) and in both cold (EL3) and live
// (MMU-off) modes because it is fully PC-relative and uses no stack.
//
// Effect: writes a marker 0x1A7EC0DE at (load_addr + 0x800) and the low 32
// bits of its own runtime address at (load_addr + 0x804) — the latter proves
// position-independence (shows exactly where it executed), then spins.
//
// inject.tcl reads (load_addr + 0x800) as the done marker / result region.

.section .text
.global _start
_start:
    adr     x0, _start                 // x0 = our actual runtime load address
    movz    w1, #0xC0DE
    movk    w1, #0x1A7E, lsl #16        // w1 = 0x1A7EC0DE  ("LATE CODE")
    str     w1, [x0, #0x800]           // marker
    str     w0, [x0, #0x804]           // low32 of where we actually ran
    dsb     sy
spin:
    b       spin
