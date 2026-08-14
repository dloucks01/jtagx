// csu-pmu-r5-wakeup.S — A53 EL3 -> PMU: power TCM, stage R5 stub, wake R5.
//
// Capstone of Chain 2 (Phase 7). Validated primitives used:
//   - A53 reset-to-EL3 (BOOTED_STATE) + APU<->PMU0 IPI (2026-05-28).
//   - PM_REQUEST_NODE(TCM_0_A/B) powers TCM, which is then writable (180121).
// New step: stage a Cortex-R5 liveness stub in the now-powered TCM and start
// the R5 core via PM_REQUEST_WAKEUP (the PMU-sanctioned processor-start path;
// raw CRL reset-release failed in JTAG-idle because the island was gated).
//
// Sequence:
//   cmd0  PM_REQUEST_NODE(TCM_0_A=0xF, CAP_ACCESS, 100, BLOCK)  -> power TCM A
//   cmd1  PM_REQUEST_NODE(TCM_0_B=0x10,CAP_ACCESS, 100, BLOCK)  -> power TCM B
//   copy  7-word R5 stub (writes 0x600D5A11 to 0xFFE01000, then spins) -> TCM 0xFFE00000
//   cmd2  PM_REQUEST_WAKEUP(NODE_RPU_0=7, encAddr=0x1, hi=0x0, BLOCK)
//         encAddr = (address 0x0) | (setAddress=1) -> R5 vector = 0x0 (TCM low alias)
//   delay ~spin so the R5 has time to execute before we read its marker
//
// PM_REQUEST_WAKEUP pack: word0=10, word1=node, word2=encAddr_lo, word3=encAddr_hi, word4=ack.
//
// OCM results (base 0xFFFE0000, 0x40/cmd): cmd0 slot0, cmd1 slot1, cmd2 slot2.
//   +0x00.. response  +0x20 api  +0x24 trigOBS  +0x28 pollOBS  +0x2C iters  +0x30 arg1
// R5 liveness marker is read by the harness from TCM 0xFFE01000 (expect 0x600D5A11).
//
// Stage @ 0xFFFE7080 ; Done @ 0xFFFE7000 = 0xCAFEC0DE.

.equ STAGE_ADDR,        0xFFFE7080
.equ DONE_MARKER_ADDR,  0xFFFE7000
.equ DONE_MARKER_VAL,   0xCAFEC0DE

.equ RESULTS_BASE,      0xFFFE0000
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

.macro store_word reg, base, val, off
    load_imm \reg, \val
    str      \reg, [\base, #\off]
.endm

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

    // cmd0/cmd1: power both TCM banks
    send_cmd 0, PM_REQUEST_NODE, NODE_TCM_0_A, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING
    send_cmd 1, PM_REQUEST_NODE, NODE_TCM_0_B, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING

    // stage marker 10 = copying R5 stub into TCM
    mov     w4, #10
    str     w4, [x5]
    load_addr x7, TCM_A_BASE
    store_word w2, x7, 0xe3011000, 0     // movw r1,#0x1000
    store_word w2, x7, 0xe34f1fe0, 4     // movt r1,#0xffe0
    store_word w2, x7, 0xe3050a11, 8     // movw r0,#0x5a11
    store_word w2, x7, 0xe346000d, 12    // movt r0,#0x600d
    store_word w2, x7, 0xe5810000, 16    // str r0,[r1]
    store_word w2, x7, 0xf57ff04f, 20    // dsb sy
    store_word w2, x7, 0xeafffffe, 24    // b .
    dsb     sy

    // cmd2: wake R5_0 at vector 0x0 (TCM low alias). encAddr = 0|setAddr = 0x1.
    send_cmd 2, PM_REQUEST_WAKEUP, NODE_RPU_0, 0x1, 0x0, ACK_BLOCKING

    // stage 11 = delay so R5 can execute its 7-instruction stub
    mov     w4, #11
    str     w4, [x5]
    load_imm w7, 2000000
delay:
    subs    w7, w7, #1
    bne     delay

    load_imm  w0, DONE_MARKER_VAL
    str       w0, [x6]
    dsb       sy
    mov       w4, #12
    str       w4, [x5]
    dsb       sy

spin:
    b       spin

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
