// csu-pmu-pm-probe.S — A53 EL3 -> PMU multi-command PM API probe.
//
// Builds on csu-pmu-ipi.S (validated 2026-05-28: PM_GET_API_VERSION -> v1.1).
// Issues a SEQUENCE of PM API commands over the APU<->PMU0 IPI channel and
// records each response. Purpose:
//   - #3 breadth: confirm PM_GET_CHIPID works (more than just version).
//   - #1 PM_MMIO_READ: characterize PMU FW's read allowlist (pm_mmio_access.c).
//        Whitelisted addrs (CRF/CRL clock regs) should SUCCEED; secure addrs
//        (eFuse cache, PMU ROM) should return XST_PM_NO_ACCESS (0x7D2 = 2002).
//
// IPI map (corrected, from zynqmp.dtsi + TF-A IPI_BUFFER layout):
//   Request  (APU->PMU): 0xFF9905C0  (local_request_region)
//   Response (PMU->APU): 0xFF9905E0  (local_response_region)
//   Doorbell: write PMU0 bit (bit16) to APU.TRIG (0xFF300000)
//   Completion: poll APU.OBS (0xFF300004) bit16 to CLEAR (blocking protocol).
//
// PM request format (ZynqMP, no module header):
//   word[0] = API ID, word[1..5] = args.
// PM response format:
//   word[0] = status (0 = XST_SUCCESS), word[1..] = return values.
//
// OCM results layout (base 0xFFFE0000), 0x40 bytes per command:
//   +0x00..0x1F  response buffer (8 words copied from 0xFF9905E0)
//   +0x20        diag: API ID sent
//   +0x24        diag: post-trigger APU.OBS  (bit16 SET expected)
//   +0x28        diag: post-poll    APU.OBS  (bit16 CLEAR = completed)
//   +0x2C        diag: poll iters used
//   +0x30        diag: arg1 sent (e.g. MMIO address)
//   cmd i slot   = 0xFFFE0000 + i*0x40   (i = 0..5)
//
// Commands (i : API : arg):
//   0 : PM_GET_API_VERSION (1)   : -        expect status0 ver 0x10001
//   1 : PM_GET_CHIPID      (24)  : -        expect status0 + idcode/version
//   2 : PM_MMIO_READ       (20)  : 0xFF5E0020 (CRL_APB clk - WHITELISTED) -> SUCCESS+value
//   3 : PM_MMIO_READ       (20)  : 0xFD1A0020 (CRF_APB clk - WHITELISTED) -> SUCCESS+value
//   4 : PM_MMIO_READ       (20)  : 0xFFCC1058 (eFuse SEC_CTRL cache - NOT listed) -> NO_ACCESS
//   5 : PM_MMIO_READ       (20)  : 0xFFD00000 (PMU ROM base - NOT listed)         -> NO_ACCESS
//
// Stage marker @ 0xFFFE7080 = command index in flight (0..6).
// Done marker  @ 0xFFFE7000 = 0xCAFEC0DE at end.

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

.equ PM_GET_API_VERSION, 1
.equ PM_GET_CHIPID,      24
.equ PM_MMIO_READ,       20

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

// send_cmd idx, api, arg1 :
//   fills request buffer, stamps diag (api @ +0x20, arg1 @ +0x30), sets the
//   stage marker, calls do_ipi (which fills response + obs/iters), advances
//   the result slot pointer x19 by SLOT_STRIDE.
.macro send_cmd idx, api, arg1
    load_addr x21, REQ_BUFFER_ADDR
    load_imm  w2, \arg1
    str       w2, [x21, #4]
    str       w2, [x19, #0x30]
    load_imm  w2, \api
    str       w2, [x21, #0]
    str       w2, [x19, #0x20]
    str       wzr, [x21, #8]
    str       wzr, [x21, #12]
    str       wzr, [x21, #16]
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

    send_cmd 0, PM_GET_API_VERSION, 0
    send_cmd 1, PM_GET_CHIPID,      0
    send_cmd 2, PM_MMIO_READ,       0xFF5E0020
    send_cmd 3, PM_MMIO_READ,       0xFD1A0020
    send_cmd 4, PM_MMIO_READ,       0xFFCC1058
    send_cmd 5, PM_MMIO_READ,       0xFFD00000

    load_imm  w0, DONE_MARKER_VAL
    str       w0, [x6]
    dsb       sy
    mov       w4, #6
    str       w4, [x5]
    dsb       sy

spin:
    b       spin

// ------------------------------------------------------------------
// do_ipi — trigger one IPI, poll OBS-clear, copy response + diag to [x19].
//   in:  request already staged at REQ_BUFFER_ADDR; x19 = result slot.
//   clobbers: x1, w2, x4, w7, w8 (preserves x5/x6/x19/x21 and lr).
// ------------------------------------------------------------------
do_ipi:
    load_addr x1, APU_IPI_BASE
    load_imm  w2, PMU0_BIT
    str       w2, [x1, #OFF_TRIG]
    dsb       sy

    ldr       w2, [x1, #OFF_OBS]
    str       w2, [x19, #0x24]          // post-trigger OBS
    dsb       sy

    load_imm  w7, 100000
    mov       w8, #0
1:  ldr       w2, [x1, #OFF_OBS]
    and       w2, w2, #PMU0_BIT
    cbz       w2, 2f                     // OBS bit16 cleared => PMU done
    add       w8, w8, #1
    subs      w7, w7, #1
    bne       1b
2:  ldr       w2, [x1, #OFF_OBS]
    str       w2, [x19, #0x28]          // post-poll OBS
    str       w8, [x19, #0x2C]          // iters used
    dsb       sy

    // copy 8 response words from RSP_BUFFER_ADDR to [x19, #0..0x1C]
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
