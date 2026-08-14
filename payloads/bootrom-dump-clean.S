// AArch64 BootROM extraction with explicit D-cache teardown — Method 2.
//
// STATUS: M2 is ACTIVE in the default dispatcher (as of 2026-05-28).
// Previously labeled DEFERRED under the wrong theory that "A53 warm-
// release JTAG path needs PMU FW". The real cause was the UTF-8 byte-
// count bug in OpenOCD's Tcl payload loader, which silently truncated
// this 224-byte payload to 221 bytes. With the fix in place, M2 runs
// cleanly via the M2 branch in dump-bootrom.tcl::_method_a53_common
// (validated 2026-05-28-002236 — done marker met in 6ms).
//
// Same copy as bootrom-dump.S, but starts by disabling D-cache via
// SCTLR_EL3.C. Live data showed D-cache was ALREADY off in JTAG-idle
// (SCTLR_EL3 = 0x00C52838, bit 2 = 0), so this version is now mostly a
// control payload — produces identical bytes to M1 by content, but
// exercises a different load/release path so both are useful as
// harness cross-checks.
//
// Sequence:
//   0. Write stage_start marker (no sysreg access — proves A53 ran our code)
//   1. Snapshot SCTLR_EL3 (BEFORE) to OCM   [requires EL3 — diagnostic if 0]
//   2. Clear C bit, write back, ISB (no-op if C was already 0)
//   3. Snapshot SCTLR_EL3 (AFTER) to OCM (proves MSR was honored)
//   4. Copy 0x4000 bytes from 0xFFFFC000 to 0xFFFE0000
//   5. DSB SY, write completion magic
//   6. Snapshot ESR/FAR/ELR/SPSR_EL3 to OCM
//   7. Spin
//
// Stage-marker rationale: stage_start lets us distinguish failure modes
// if M2 hangs. stage_start == 0 → A53 never executed our code (release
// failure or OCM write didn't land). stage_start == 0xC0DEBA5E but
// SCTLR_BEFORE == 0 → A53 ran our code, MRS sctlr_el3 was a no-op
// (SCTLR_EL3.C is already 0 in JTAG-idle, so MSR was technically
// honored — the snapshot just returns the same 0).

.equ SRC_ADDR,          0xFFFFC000
.equ DST_ADDR,          0xFFFE0000
.equ DUMP_SIZE,         0x4000
.equ DONE_FLAG_ADDR,    0xFFFE7000
.equ SCTLR_BEFORE_ADDR, 0xFFFE7010
.equ SCTLR_AFTER_ADDR,  0xFFFE7018
.equ ESR_EL3_SAVE,      0xFFFE7030
.equ FAR_EL3_SAVE,      0xFFFE7038
.equ ELR_EL3_SAVE,      0xFFFE7040
.equ SPSR_EL3_SAVE,     0xFFFE7048
// Stage marker address + value — these MUST match dump-bootrom.tcl's
// ::ADDR_STAGE_START and ::STAGE_START_VAL constants. If you change one,
// change the other.
.equ STAGE_START_ADDR,  0xFFFE7080
.equ STAGE_START_VAL,   0xC0DEBA5E
.equ DONE_FLAG_LO,      0x0000C0DE
.equ DONE_FLAG_HI,      0xCAFEBABE

// SCTLR_EL3.C is the D-cache enable bit.
.equ SCTLR_C, (1 << 2)

.section .text
.global _start

.macro load_addr reg, addr
    movz    \reg, #(\addr & 0xFFFF)
    movk    \reg, #((\addr >> 16) & 0xFFFF), lsl #16
.endm

// CLOBBERS: x10 (sysreg value), x12 (address scratch). Callers must
// not rely on these registers across this macro.
.macro snapshot_sysreg sysreg, save_addr
    mrs     x10, \sysreg
    load_addr x12, \save_addr
    str     x10, [x12]
.endm

_start:
    // --- Stage 0: prove we got here (no sysreg, works at any EL) ---
    movz    x14, #(STAGE_START_VAL & 0xFFFF)
    movk    x14, #((STAGE_START_VAL >> 16) & 0xFFFF), lsl #16
    load_addr x15, STAGE_START_ADDR
    str     x14, [x15]

    // --- Snapshot SCTLR_EL3 before modification ---
    snapshot_sysreg sctlr_el3, SCTLR_BEFORE_ADDR

    // --- Disable D-cache at EL3 ---
    // ARM ARM recommends DSB SY + ISB after SCTLR_ELx writes that change
    // cache/MMU enables, so prior accesses drain in the old state before
    // the context-synchronization event takes effect.
    mrs     x10, sctlr_el3
    movz    x11, #SCTLR_C
    bic     x10, x10, x11
    msr     sctlr_el3, x10
    dsb     sy
    isb

    // --- Snapshot SCTLR_EL3 after modification ---
    snapshot_sysreg sctlr_el3, SCTLR_AFTER_ADDR

    // --- Copy loop (same as Method 1, no per-iter barrier) ---
    load_addr x0, SRC_ADDR
    load_addr x1, DST_ADDR
    movz    x2, #(DUMP_SIZE / 16)

copy_loop:
    ldp     x3, x4, [x0], #16
    stp     x3, x4, [x1], #16
    subs    x2, x2, #1
    b.ne    copy_loop

    dsb     sy
    isb

    // --- Completion marker ---
    movz    x5, #(DONE_FLAG_LO & 0xFFFF)
    movk    x5, #((DONE_FLAG_LO >> 16) & 0xFFFF), lsl #16
    movk    x5, #(DONE_FLAG_HI & 0xFFFF),          lsl #32
    movk    x5, #((DONE_FLAG_HI >> 16) & 0xFFFF), lsl #48

    load_addr x6, DONE_FLAG_ADDR
    str     x5, [x6]
    dsb     sy

    // --- Snapshot EL3 exception syndrome ---
    snapshot_sysreg esr_el3,  ESR_EL3_SAVE
    snapshot_sysreg far_el3,  FAR_EL3_SAVE
    snapshot_sysreg elr_el3,  ELR_EL3_SAVE
    snapshot_sysreg spsr_el3, SPSR_EL3_SAVE
    dsb     sy

// Busy-loop spin (NOT wfe). See bootrom-dump.S for why — keeping A53
// out of WFE makes inter-method PC writes reliable.
spin:
    b       spin
