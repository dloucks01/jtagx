// csu-pmu-wake-probe.S — test if A53 EL3 can write PMU_GLOBAL.GLOBAL_CNTRL
//
// Purpose: determine if A53 EL3 has write access to PMU_GLOBAL space.
// This is a prerequisite for any actual PMU wake attempt
// (clearing MB_SLEEP bit 11 to wake the PMU MicroBlaze).
//
// SAFETY: this probe does NOT actually wake the PMU. It only tests
// if the WRITE goes through, by writing reserved bit 31 (which has
// no functional effect) and reading back. Restore step writes the
// baseline value back unconditionally.
//
// Baseline 2026-05-28: PMU_GLOBAL.GLOBAL_CNTRL @ 0xFFD80000 = 0x00018800
//   bit 11 = MB_SLEEP (set)
//   bit 15 = ?
//   bit 16 = ?
//   bit 31 = reserved (clear)
//
// Test: write (baseline | 0x80000000) — sets only reserved bit 31.
// If write took, readback shows 0x80018800.
// If write rejected, readback shows 0x00018800 (baseline).
// If write partially took (bit 31 fixed-at-0), same as rejected verdict.
//
// OCM layout (12 bytes):
//   +0x00 baseline GLOBAL_CNTRL
//   +0x04 readback after reserved-bit write
//   +0x08 readback after restore
//
// Also captures sibling registers for context:
//   +0x10 PMU_GLOBAL.PWR_STATE (0xFFD80100)
//   +0x14 PMU_GLOBAL.GPI1 (0xFFD80008) — interrupt signals into PMU
//   +0x18 PMU_GLOBAL.GPO1 (0xFFD80038) — output signals from PMU
//
// Stage marker @ 0xFFFE7080.
// Done marker @ 0xFFFE7000 = 0xCAFEC0DE.

.equ STAGE_ADDR,        0xFFFE7080
.equ DONE_MARKER_ADDR,  0xFFFE7000
.equ DONE_MARKER_VAL,   0xCAFEC0DE
.equ OCM_BASE,          0xFFFE0000

.equ PMU_GLOBAL_CNTRL,  0xFFD80000
.equ PMU_PWR_STATE,     0xFFD80100
.equ PMU_GPI1,          0xFFD80008
.equ PMU_GPO1,          0xFFD80038

.equ TEST_BIT,          0x80000000   // reserved bit 31, no functional effect

.section .text
.global _start

.macro load_addr reg, addr
    movz    \reg, #((\addr) & 0xFFFF)
    movk    \reg, #(((\addr) >> 16) & 0xFFFF), lsl #16
.endm

.macro load_imm reg, val
    movz    \reg, #((\val) & 0xFFFF)
    movk    \reg, #(((\val) >> 16) & 0xFFFF), lsl #16
.endm

_start:
    load_addr x5, STAGE_ADDR
    load_addr x6, DONE_MARKER_ADDR
    load_addr x10, OCM_BASE

    // ---- Stage 1: read GLOBAL_CNTRL baseline (saved in w11) ----
    load_addr x1, PMU_GLOBAL_CNTRL
    ldr     w11, [x1]
    str     w11, [x10, #0x00]
    dsb     sy
    mov     w4, #1
    str     w4, [x5]

    // ---- Stage 2: write (baseline | TEST_BIT) — sets reserved bit 31 ----
    load_imm w0, TEST_BIT
    orr     w0, w11, w0                 // w0 = baseline | 0x80000000
    str     w0, [x1]
    dsb     sy

    // Readback
    ldr     w12, [x1]
    str     w12, [x10, #0x04]
    dsb     sy
    mov     w4, #2
    str     w4, [x5]

    // ---- Stage 3: restore baseline ----
    str     w11, [x1]
    dsb     sy
    ldr     w13, [x1]
    str     w13, [x10, #0x08]
    dsb     sy
    mov     w4, #3
    str     w4, [x5]

    // ---- Stage 4: snapshot sibling registers for context ----
    load_addr x1, PMU_PWR_STATE
    ldr     w0, [x1]
    str     w0, [x10, #0x10]
    load_addr x1, PMU_GPI1
    ldr     w0, [x1]
    str     w0, [x10, #0x14]
    load_addr x1, PMU_GPO1
    ldr     w0, [x1]
    str     w0, [x10, #0x18]
    dsb     sy
    mov     w4, #4
    str     w4, [x5]

    // ---- Done marker ----
    load_imm w0, DONE_MARKER_VAL
    str     w0, [x6]
    dsb     sy
    mov     w4, #5
    str     w4, [x5]
    dsb     sy

spin:
    b       spin
