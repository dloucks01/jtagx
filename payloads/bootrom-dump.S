// AArch64 BootROM extraction payload for ZCU102.
//
// Run by the A53 in EL3 after JTAG halts + sets PC here.
//
// Reads 0x4000 bytes from CSU BootROM region (0xFFFFC000) and copies them
// to OCM bank 2 (0xFFFE0000). Writes a completion magic to 0xFFFE7000 so
// the JTAG-side script can poll for "done" before halting the core and
// extracting the dump destination.
//
// Also snapshots the EL3 exception syndrome (ESR/FAR/ELR/SPSR_EL3) into
// OCM, because OpenOCD's `reg` interface doesn't reliably expose these.
// Values are residual from BootROM execution (this payload doesn't itself
// take an exception when LDP from gated memory returns 0xDEADBEEF as data).
//
// Memory layout while this runs:
//   0xFFFC0000  safe-landing branch (placed by §8 release recipe)
//   0xFFFC0100  THIS payload (entry point)
//   0xFFFE0000  dump destination (16 KB)
//   0xFFFE7000  completion magic (8 bytes)
//   0xFFFE7010  SCTLR_EL3 BEFORE (8 bytes; M2-only, not written by M1 — undefined)
//   0xFFFE7018  SCTLR_EL3 AFTER  (8 bytes; M2-only, not written by M1 — undefined)
//   0xFFFE7030  ESR_EL3   (8 bytes)
//   0xFFFE7038  FAR_EL3   (8 bytes)
//   0xFFFE7040  ELR_EL3   (8 bytes)
//   0xFFFE7048  SPSR_EL3  (8 bytes)
//
// Build:
//   aarch64-linux-gnu-as bootrom-dump.S -o bootrom-dump.o
//   aarch64-linux-gnu-ld -T bootrom-dump.lds bootrom-dump.o -o bootrom-dump.elf
//   aarch64-linux-gnu-objcopy -O binary bootrom-dump.elf bootrom-dump.bin

.equ SRC_ADDR,       0xFFFFC000   // BootROM region (CSU-mapped)
.equ DST_ADDR,       0xFFFE0000   // OCM bank 2 — separate bank from payload
.equ DUMP_SIZE,      0x4000       // 16 KB (matches Method 0 default for diff)
.equ DONE_FLAG_ADDR, 0xFFFE7000   // completion marker location
.equ DONE_FLAG_LO,   0x0000C0DE   // lower  32 bits of 0xCAFEBABE0000C0DE
.equ DONE_FLAG_HI,   0xCAFEBABE   // upper  32 bits of 0xCAFEBABE0000C0DE
.equ ESR_EL3_SAVE,   0xFFFE7030
.equ FAR_EL3_SAVE,   0xFFFE7038
.equ ELR_EL3_SAVE,   0xFFFE7040
.equ SPSR_EL3_SAVE,  0xFFFE7048

.section .text
.global _start

// Macro: load a 32-bit literal address into a 64-bit register.
// Upper 32 bits cleared by movz; lower set by movz+movk pair.
.macro load_addr reg, addr
    movz    \reg, #(\addr & 0xFFFF)
    movk    \reg, #((\addr >> 16) & 0xFFFF), lsl #16
.endm

// Macro: snapshot an EL3 sysreg to OCM at the given address.
// CLOBBERS: x10 (sysreg value), x12 (address scratch). Callers must
// not rely on these registers across this macro.
.macro snapshot_sysreg sysreg, save_addr
    mrs     x10, \sysreg
    load_addr x12, \save_addr
    str     x10, [x12]
.endm

_start:
    // x0 = source pointer (SRC_ADDR = 0xFFFFC000)
    load_addr x0, SRC_ADDR

    // x1 = destination pointer (DST_ADDR = 0xFFFE0000)
    load_addr x1, DST_ADDR

    // x2 = loop count = DUMP_SIZE / 16
    movz x2, #(DUMP_SIZE / 16)

copy_loop:
    ldp     x3, x4, [x0], #16
    stp     x3, x4, [x1], #16
    subs    x2, x2, #1
    b.ne    copy_loop

    dsb     sy
    isb

    // Write the completion marker — JTAG polls this.
    movz    x5, #(DONE_FLAG_LO & 0xFFFF)
    movk    x5, #((DONE_FLAG_LO >> 16) & 0xFFFF), lsl #16
    movk    x5, #(DONE_FLAG_HI & 0xFFFF),          lsl #32
    movk    x5, #((DONE_FLAG_HI >> 16) & 0xFFFF), lsl #48

    load_addr x6, DONE_FLAG_ADDR
    str     x5, [x6]
    dsb     sy

    // Snapshot EL3 exception syndrome registers.
    // Values are residual from BootROM boot-time execution; our payload
    // didn't itself take an exception. Useful for understanding what
    // BootROM was doing before handoff.
    snapshot_sysreg esr_el3,  ESR_EL3_SAVE
    snapshot_sysreg far_el3,  FAR_EL3_SAVE
    snapshot_sysreg elr_el3,  ELR_EL3_SAVE
    snapshot_sysreg spsr_el3, SPSR_EL3_SAVE
    dsb     sy

// Busy-loop spin (NOT wfe). WFE leaves A53 in a low-power debug state
// where subsequent JTAG `reg pc` writes can silently fail — observed
// when M2 followed M1 (M1 ended in WFE, M2 couldn't reset PC). A simple
// branch-to-self keeps A53 in a normal running state that halts cleanly.
spin:
    b       spin
