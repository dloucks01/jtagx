// r5-liveness.S — minimal Cortex-R5 (ARMv7-R, ARM32) stub.
// Runs from TCM low-vector (0x0). Writes a liveness marker to TCM global
// 0xFFE01000, then spins. Proves the R5 core actually executed our code.
.syntax unified
.arm
.global _start
_start:
    movw    r1, #0x1000
    movt    r1, #0xFFE0          // r1 = 0xFFE01000 (TCM_A global + 0x1000)
    movw    r0, #0x5A11
    movt    r0, #0x600D          // r0 = 0x600D5A11  marker ("GOOD-ALIVE")
    str     r0, [r1]
    dsb
1:  b       1b
