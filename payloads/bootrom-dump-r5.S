@ ARMv7-R BootROM extraction for Cortex-R5 (ZynqMP RPU core 0).
@
@ Run by R5 in supervisor mode (default after release) from address 0x00000000.
@ That address maps to global 0xFFE00000 (RPU0 ATCM) where JTAG loaded us.
@
@ Memory layout while running:
@   0x00000000  THIS payload (R5 local view of ATCM)
@   0xFFE00000  global view of the same payload (where JTAG wrote it)
@   0xFFFFC000  BootROM (CSU)                — what we want to read
@   0xFFFE0000  dump destination (OCM bank 2) — JTAG reads this back
@   0xFFFE7000  completion marker (8 bytes)
@
@ The R5 master ID is different from A53's and from JTAG-DAP's. If the
@ BootROM gating is keyed on master ID and R5 isn't blocked, this method
@ might succeed where M1/M2 (A53 paths) returned all-DEADBEEF.
@
@ Build:
@   arm-none-eabi-as -mcpu=cortex-r5 bootrom-dump-r5.S -o bootrom-dump-r5.o
@   arm-none-eabi-ld -T bootrom-dump-r5.lds bootrom-dump-r5.o -o bootrom-dump-r5.elf
@   arm-none-eabi-objcopy -O binary bootrom-dump-r5.elf bootrom-dump-r5.bin

.equ SRC_ADDR,         0xFFFFC000
.equ DST_ADDR,         0xFFFE0000
.equ DUMP_SIZE,        0x4000           @ 16 KB
.equ DONE_FLAG_ADDR,   0xFFFE7000
.equ DONE_FLAG_LO,     0x0000C0DE
.equ DONE_FLAG_HI,     0xCAFEBABE

.section .text
.global _start

.arm
.syntax unified

_start:
    @ Set up source and destination pointers.
    @ ARM32 immediates can't load arbitrary 32-bit values directly, so use
    @ movw/movt pair (available on Cortex-R5 / ARMv7).
    movw    r0, #(SRC_ADDR & 0xFFFF)
    movt    r0, #((SRC_ADDR >> 16) & 0xFFFF)

    movw    r1, #(DST_ADDR & 0xFFFF)
    movt    r1, #((DST_ADDR >> 16) & 0xFFFF)

    @ Loop count = DUMP_SIZE / 16 (each iter copies 16 bytes via LDM/STM)
    movw    r2, #(DUMP_SIZE / 16)

copy_loop:
    ldm     r0!, {r3, r4, r5, r6}     @ load 4 × 4 bytes, post-incr by 16
    stm     r1!, {r3, r4, r5, r6}     @ store 4 × 4 bytes, post-incr by 16
    subs    r2, r2, #1
    bne     copy_loop

    @ Data barrier — ensure all stores have hit memory before we set marker.
    @ ARMv7-R: `dsb` defaults to SY; `isb` takes no operand (some Binutils
    @ versions reject `isb sy` — use bare `isb` for portability).
    dsb
    isb

    @ Write completion marker — JTAG mem-AP polls 0xFFFE7000 for the magic.
    @ Layout matches A64's 64-bit little-endian store: lo word (0x0000C0DE)
    @ at +0, hi word (0xCAFEBABE) at +4. TCL polls both halves separately.
    @ Two 32-bit stores; ARMv7-R has no 64-bit store, no problem.
    movw    r7, #(DONE_FLAG_ADDR & 0xFFFF)
    movt    r7, #((DONE_FLAG_ADDR >> 16) & 0xFFFF)
    movw    r8, #(DONE_FLAG_LO & 0xFFFF)
    movt    r8, #((DONE_FLAG_LO >> 16) & 0xFFFF)
    str     r8, [r7]                  @ low 32 bits at 0xFFFE7000
    movw    r8, #(DONE_FLAG_HI & 0xFFFF)
    movt    r8, #((DONE_FLAG_HI >> 16) & 0xFFFF)
    str     r8, [r7, #4]              @ high 32 bits at 0xFFFE7004
    dsb     sy

    @ Hang in busy loop until JTAG halts us. (NOT WFE — the A53 .S files
    @ removed WFE because OpenOCD's reg-pc-after-halt-from-WFE was unreliable
    @ on this platform. R5 is never actually run in practice — RPU island
    @ stays gated without PMU FW — but kept consistent for when it is.)
spin:
    b       spin
