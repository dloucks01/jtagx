// csu-pmu-rpu-wake.S — A53 EL3 -> PMU: wake RPU island + TCM banks via PM API.
//
// Chain 2 (Phase 7): in JTAG-idle the RPU power island stayed gated by PMU,
// so M4 (R5 dump) and TCM dump (task #66) were impossible. With PMU FW running
// we can drive PM_REQUEST_NODE on the TCM slave banks (which powers TCM) and on
// the RPU processor node, then confirm TCM is reachable from JTAG.
//
// Validated primitive (2026-05-28): A53 reset to EL3 -> APU<->PMU0 IPI works.
//   Request  0xFF9905C0, Response 0xFF9905E0, doorbell APU.TRIG bit16,
//   completion = APU.OBS bit16 CLEAR. Request word[0]=API ID, no module header.
//
// PM API (confirmed numbering: GET_API_VERSION=1, MMIO_READ=20, GET_CHIPID=24):
//   PM_GET_NODE_STATUS = 3   : PACK_PAYLOAD1(api, node)
//   PM_REQUEST_NODE    = 13  : PACK_PAYLOAD4(api, node, capabilities, qos, ack)
// Node IDs: NODE_RPU_0=7, NODE_TCM_0_A=0xF, NODE_TCM_0_B=0x10
// Caps: PM_CAP_ACCESS=1.  Ack: REQUEST_ACK_BLOCKING=2 (PMU writes status to resp buf).
//
// GET_NODE_STATUS response: word[0]=status, word[1]=currState, word[2]=requirement,
//                           word[3]=usage.
//
// OCM results layout (base 0xFFFE0000), 0x40 per command (same as pm-probe):
//   +0x00..0x1F response  +0x20 api  +0x24 trigOBS  +0x28 pollOBS  +0x2C iters  +0x30 arg1(node)
//   cmd i slot = 0xFFFE0000 + i*0x40
//
// Commands:
//   0 : GET_NODE_STATUS(RPU_0)                         -- baseline power state
//   1 : REQUEST_NODE(RPU_0,  CAP_ACCESS, 100, BLOCK)   -- request RPU proc node
//   2 : REQUEST_NODE(TCM_0_A,CAP_ACCESS, 100, BLOCK)   -- power TCM bank A
//   3 : REQUEST_NODE(TCM_0_B,CAP_ACCESS, 100, BLOCK)   -- power TCM bank B
//   4 : GET_NODE_STATUS(RPU_0)                         -- confirm state changed
//
// Stage marker @ 0xFFFE7080 ; Done marker @ 0xFFFE7000 = 0xCAFEC0DE.

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

.equ PM_GET_NODE_STATUS, 3
.equ PM_REQUEST_NODE,    13
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

// send_cmd idx, api, a1, a2, a3, a4 — fill request words 0..4, stamp diag,
// set stage, call do_ipi, advance slot. Pass 0 for unused args.
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

    send_cmd 0, PM_GET_NODE_STATUS, NODE_RPU_0, 0, 0, 0
    send_cmd 1, PM_REQUEST_NODE,    NODE_RPU_0,   PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING
    send_cmd 2, PM_REQUEST_NODE,    NODE_TCM_0_A, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING
    send_cmd 3, PM_REQUEST_NODE,    NODE_TCM_0_B, PM_CAP_ACCESS, QOS_MAX, ACK_BLOCKING
    send_cmd 4, PM_GET_NODE_STATUS, NODE_RPU_0, 0, 0, 0

    load_imm  w0, DONE_MARKER_VAL
    str       w0, [x6]
    dsb       sy
    mov       w4, #5
    str       w4, [x5]
    dsb       sy

spin:
    b       spin

// do_ipi — trigger one IPI, poll OBS-clear, copy response + diag to [x19].
//   clobbers x1,w2,x4,w7,w8 ; preserves x5/x6/x19/x21 and lr.
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
