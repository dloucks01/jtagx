// csu-pmu-r5-bootrom.S — A53 EL3 -> PMU: power TCM, stage the FULL
// bootrom-dump-r5 extractor, wake R5, let R5 dump BootROM via its own
// bus-master ID. Requires BOOTED_STATE.
//
// This is the "M4" capstone. The wake mechanism was proven by
// csu-pmu-r5-wakeup.S (R5 ran a 7-word liveness stub, marker 0x600D5A11
// confirmed 2026-05-28-183949). Here we swap that stub for the real
// payloads/bootrom-dump-r5 extractor (embedded verbatim via .incbin), so
// the R5 core — NOT the A53 and NOT the JTAG-DAP — issues the BootROM
// reads. A53-EL3 and DAP-NS reads of 0xFFFFC000 returned all-0xDEADBEEF
// (filtered). If the CSU BootROM gate is keyed on master ID and the RPU
// is not on the blocklist, R5 reads where the A53 could not. Either
// outcome is a clean, falsifiable result.
//
// DIVISION OF LABOUR / MEMORY MAP (deliberately split so the A53 driver
// and the R5 extractor never alias each other, and so the EXISTING
// dump-bootrom harness poll+readback works unchanged — it is driven by
// the R5's marker, not ours):
//
//   0xFFE00000          TCM_A — R5 code lands here; R5 runs it from 0x0 alias
//   0xFFFFC000          BootROM (CSU) — what R5 reads (SRC in bootrom-dump-r5)
//   0xFFFE0000-3FFF     R5 dump destination (= harness ::ADDR_DUMP_DST; the
//                       harness zeroes this pre-run and reads it back to .bin)
//   0xFFFE5000+ (0x40)  A53 IPI debug slots (cmd0/1/2) — THIS payload writes
//   0xFFFE6000          A53 done marker = 0xCAFEC0DE  ("A53 issued the wake")
//   0xFFFE6080          A53 stage marker (0..12)
//   0xFFFE7000/04       R5 done marker 0x0000C0DE / 0xCAFEBABE — set by the
//                       R5 extractor; this IS the marker the harness polls
//                       (::DONE_MARKER_LO/HI). THIS payload must NOT touch it.
//
// Sequence (all PM calls over the validated APU<->PMU0 IPI channel):
//   cmd0  PM_REQUEST_NODE(TCM_0_A=0xF)   -> power TCM A
//   cmd1  PM_REQUEST_NODE(TCM_0_B=0x10)  -> power TCM B
//   copy  bootrom-dump-r5.bin (84 B / 21 words) -> TCM 0xFFE00000
//   cmd2  PM_REQUEST_WAKEUP(NODE_RPU_0=7, encAddr=0x1 [addr0|setAddr], hi=0, BLOCK)
//   delay so the R5 finishes its 16 KB copy + marker before we are halted
//
// PM_REQUEST_WAKEUP pack: word0=10, word1=node, word2=encAddr_lo, word3=encAddr_hi, word4=ack.
// PM_REQUEST_NODE   pack: word0=13, word1=node, word2=capabilities, word3=qos, word4=ack.

.equ STAGE_ADDR,        0xFFFE6080
.equ DONE_MARKER_ADDR,  0xFFFE6000
.equ DONE_MARKER_VAL,   0xCAFEC0DE

.equ RESULTS_BASE,      0xFFFE5000
.equ SLOT_STRIDE,       0x40

.equ APU_IPI_BASE,      0xFF300000
.equ OFF_TRIG,          0x00
.equ OFF_OBS,           0x04
.equ PMU0_BIT,          0x00010000

.equ REQ_BUFFER_ADDR,   0xFF9905C0
.equ RSP_BUFFER_ADDR,   0xFF9905E0

.equ TCM_A_BASE,        0xFFE00000

.equ PM_REQUEST_NODE,    13
.equ PM_REQUEST_WAKEUP,  10
.equ NODE_RPU_0,         7
.equ NODE_TCM_0_A,       0xF
.equ NODE_TCM_0_B,       0x10
.equ PM_CAP_ACCESS,      1
.equ QOS_MAX,            100
.equ ACK_BLOCKING,       2

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

// send_cmd idx, api, a1, a2, a3, a4 — fill 8-word request, stamp diag
// (api @ slot+0x20, a1 @ slot+0x30), set stage marker, fire IPI, advance slot.
.macro send_cmd idx, api, a1, a2, a3, a4
    load_addr x21, REQ_BUFFER_ADDR
    load_imm  w2, \api;  str w2, [x21, #0];  str w2, [x19, #0x20]
    load_imm  w2, \a1;   str w2, [x21, #4];  str w2, [x19, #0x30]
    load_imm  w2, \a2;   str w2, [x21, #8]
    load_imm  w2, \a3;   str w2, [x21, #12]
    load_imm  w2, \a4;   str w2, [x21, #16]
    str       wzr, [x21, #20]
    str       wzr, [x21, #24]
    str       wzr, [x21, #28]
    dsb       sy
    mov       w4, #\idx
    str       w4, [x5]
    bl        do_ipi
    add       x19, x19, #SLOT_STRIDE
.endm

_start:
    load_addr x5, STAGE_ADDR
    load_addr x6, DONE_MARKER_ADDR
    load_addr x19, RESULTS_BASE

    // cmd0/cmd1: power both TCM banks (DOUBLE_REQ 0x7D4 if already requested = OK)
    send_cmd 0, PM_REQUEST_NODE, NODE_TCM_0_A, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING
    send_cmd 1, PM_REQUEST_NODE, NODE_TCM_0_B, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING

    // stage 10 = copy the embedded bootrom-dump-r5 extractor into TCM_A.
    // Word-copy r5_blob .. r5_blob_end (84 bytes, 4-byte aligned) to 0xFFE00000.
    mov     w4, #10
    str     w4, [x5]
    adr     x9, r5_blob
    adr     x10, r5_blob_end
    load_addr x7, TCM_A_BASE
copy_r5:
    cmp     x9, x10
    b.hs    copy_done
    ldr     w0, [x9], #4
    str     w0, [x7], #4
    b       copy_r5
copy_done:
    dsb     sy

    // cmd2: wake R5_0 at vector 0x0 (TCM low alias). encAddr = 0|setAddr = 0x1.
    send_cmd 2, PM_REQUEST_WAKEUP, NODE_RPU_0, 0x1, 0x0, ACK_BLOCKING

    // stage 11 = delay so R5 can power up and copy 16 KB (0xFFFFC000 -> 0xFFFE0000)
    // and set its own done marker at 0xFFFE7000 before the harness halts us.
    mov     w4, #11
    str     w4, [x5]
    load_imm w7, 8000000
delay:
    subs    w7, w7, #1
    bne     delay

    // A53 done marker (we issued the wake) — distinct from the R5 marker.
    load_imm  w0, DONE_MARKER_VAL
    str       w0, [x6]
    dsb       sy
    mov       w4, #12
    str       w4, [x5]
    dsb       sy

spin:
    b       spin

// ------------------------------------------------------------------
// do_ipi — trigger one IPI, poll APU.OBS bit16 to clear, copy 8 response
//   words + diag (OBS post-trigger @+0x24, OBS post-poll @+0x28, iters
//   @+0x2C) into [x19]. clobbers x1,w2,x4,w7,w8; preserves x5/x6/x19/x21/lr.
// ------------------------------------------------------------------
do_ipi:
    load_addr x1, APU_IPI_BASE
    load_imm  w2, PMU0_BIT
    str       w2, [x1, #OFF_TRIG]
    dsb       sy
    ldr       w2, [x1, #OFF_OBS]
    str       w2, [x19, #0x24]
    dsb       sy
    load_imm  w7, 100000
    mov       w8, #0
1:  ldr       w2, [x1, #OFF_OBS]
    and       w2, w2, #PMU0_BIT
    cbz       w2, 2f
    add       w8, w8, #1
    subs      w7, w7, #1
    bne       1b
2:  ldr       w2, [x1, #OFF_OBS]
    str       w2, [x19, #0x28]
    str       w8, [x19, #0x2C]
    dsb       sy
    load_addr x4, RSP_BUFFER_ADDR
    ldr       w2, [x4, #0];  str w2, [x19, #0x00]
    ldr       w2, [x4, #4];  str w2, [x19, #0x04]
    ldr       w2, [x4, #8];  str w2, [x19, #0x08]
    ldr       w2, [x4, #12]; str w2, [x19, #0x0C]
    ldr       w2, [x4, #16]; str w2, [x19, #0x10]
    ldr       w2, [x4, #20]; str w2, [x19, #0x14]
    ldr       w2, [x4, #24]; str w2, [x19, #0x18]
    ldr       w2, [x4, #28]; str w2, [x19, #0x1C]
    dsb       sy
    ret

// The R5 extractor, embedded verbatim. Kept in sync with the source by
// pulling the compiled bytes directly (build dep in Makefile). It reads
// 0xFFFFC000 -> 0xFFFE0000 (16 KB) and sets 0xFFFE7000 = 0x0000C0DE /
// 0xFFFE7004 = 0xCAFEBABE, which is exactly the harness done marker.
.balign 4
r5_blob:
    .incbin "bootrom-dump-r5.bin"
r5_blob_end:
.balign 4
