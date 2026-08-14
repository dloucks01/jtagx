// csu-pmu-ipi.S — A53 EL3 SECURE talks to PMU via IPI (PM_GET_API_VERSION).
//
// Goal: prove (or disprove) that A53 EL3 SECURE can communicate with
// PMU ROM via the documented IPI path. PMU ROM has an IPI handler that
// responds to basic PM API queries. If we get a successful response,
// the IPI infrastructure is reachable — opening up further probes
// like PM_MMIO_READ, PM_GET_NODE_STATUS, etc., and potentially the
// LMB-staging + IPI-redirect chain (since we already proved A53 EL3
// can write PMU LMB RAM — see csu-write-survey-v2 2026-05-28-013149).
//
// ZynqMP IPI register map:
//   APU IPI channel base = 0xFF300000
//     +0x00 TRIG (write target's bit to trigger; bit 16 = PMU0)
//     +0x04 OBS  (outstanding requests; bit 16 set while PMU0 hasn't ACKed)
//     +0x10 ISR  (interrupt status; bit 16 set when PMU0 signaled us back)
//     +0x14 IMR
//     +0x18 IER
//     +0x1C IDR
//   PMU0 IPI channel base = 0xFF330000 (same layout, PMU's perspective)
//
//   IPI channel agent-bit map:
//     bit  0: APU
//     bit 16: PMU0
//     bit 17: PMU1, etc.
//
//   Per-channel-pair message buffer (APU↔PMU0):
//   CORRECTED 2026-05-28 from zynqmp.dtsi xlnx,zynqmp-ipi-mailbox reg map
//   + TF-A IPI_BUFFER layout. The earlier 0xFF990400/0440 guess (PMU-ROM
//   theory) was wrong for PMU FW. PMU FW reads the request from the APU
//   base + TARGET_PMU_OFFSET(0x1C0) and writes the response to the PMU
//   base + TARGET_APU_OFFSET(0x80) + RESP_OFFSET(0x20).
//     0xFF9905C0  APU → PMU0 request buffer  (local_request_region)
//     0xFF9905E0  PMU0 → APU response buffer (local_response_region)
//                 = APU_BASE + TARGET_PMU_OFFSET(0x1C0) + RESP_OFFSET(0x20).
//                 TF-A reads the response from the APU buffer region, NOT
//                 the PMU region. (remote_response_region 0xFF990EA0 is for
//                 PMU-INITIATED transactions, not our APU-initiated call.)
//
// COMPLETION SIGNAL: the blocking PM protocol signals done by the caller's
// APU.OBS target bit CLEARING (PMU clears its ISR -> our OBS clears), NOT by
// APU.ISR setting. So we poll APU.OBS for bit 16 to clear.
//
// PM API request format (8 words in request buffer):
//   word[0] = command ID (PM_GET_API_VERSION = 0x1)
//   word[1..7] = command-specific args (zero for PM_GET_API_VERSION)
//
// PM API response format (8 words in response buffer):
//   word[0] = status (0 = SUCCESS, non-zero = error code)
//   word[1] = version (for PM_GET_API_VERSION: upper 16 = major, lower 16 = minor)
//   word[2..7] = unused for this command
//
// OCM staging layout (at 0xFFFE0000):
//   +0x00  pre APU.TRIG
//   +0x04  pre APU.OBS
//   +0x08  pre APU.ISR
//   +0x0C  pre PMU0.ISR (other side; tells us if PMU has any pending signals)
//   +0x10  pre-request buffer word 0 (residual from prior boot or our prior runs)
//   +0x14  pre-request buffer word 1
//   +0x18  pre-response buffer word 0 (likewise residual)
//   +0x1C  pre-response buffer word 1
//   +0x20  post-trigger APU.OBS (bit 16 should be SET)
//   +0x24  post-poll APU.OBS (bit 16 should be CLEAR if PMU ACKed)
//   +0x28  post-poll APU.ISR (bit 16 should be SET if PMU signaled back)
//   +0x2C  poll iters used (lower = faster response)
//   +0x30..+0x4F  response buffer (8 words = 32 bytes)
//   +0x50..+0x6F  echo of request we sent (8 words, for debug)
//   +0x70  ISR after ack-clear write (should be cleared)
//
// Stage marker @ 0xFFFE7080 (1..9 as phases complete).
// Done marker  @ 0xFFFE7000 = 0xCAFEC0DE at end.

.equ STAGE_ADDR,        0xFFFE7080
.equ DONE_MARKER_ADDR,  0xFFFE7000
.equ DONE_MARKER_VAL,   0xCAFEC0DE

.equ OCM_BASE,          0xFFFE0000

.equ APU_IPI_BASE,      0xFF300000
.equ PMU0_IPI_BASE,     0xFF330000
.equ OFF_TRIG,          0x00
.equ OFF_OBS,           0x04
.equ OFF_ISR,           0x10

.equ PMU0_BIT,          0x00010000   // bit 16 in TRIG/OBS/ISR registers
.equ APU_BIT,           0x00000001   // bit 0  in TRIG/OBS/ISR registers

.equ REQ_BUFFER_ADDR,   0xFF9905C0   // APU → PMU0 request  (local_request_region)
.equ RSP_BUFFER_ADDR,   0xFF9905E0   // PMU0 → APU response (local_response_region)

.equ PM_GET_API_VERSION, 0x1         // simplest PM API command, no args

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

    // ============================================================
    // Stage 1: pre-state snapshot (4 reads, save to OCM +0..+0x0F)
    // ============================================================
    load_addr x1, APU_IPI_BASE
    ldr     w0, [x1, #OFF_TRIG]
    str     w0, [x10, #0x00]
    ldr     w0, [x1, #OFF_OBS]
    str     w0, [x10, #0x04]
    ldr     w0, [x1, #OFF_ISR]
    str     w0, [x10, #0x08]
    load_addr x1, PMU0_IPI_BASE
    ldr     w0, [x1, #OFF_ISR]
    str     w0, [x10, #0x0C]
    dsb     sy
    mov     w4, #1
    str     w4, [x5]

    // ============================================================
    // Stage 2: snapshot pre-request and pre-response buffer contents
    // ============================================================
    load_addr x1, REQ_BUFFER_ADDR
    ldr     w0, [x1, #0]
    str     w0, [x10, #0x10]
    ldr     w0, [x1, #4]
    str     w0, [x10, #0x14]
    load_addr x1, RSP_BUFFER_ADDR
    ldr     w0, [x1, #0]
    str     w0, [x10, #0x18]
    ldr     w0, [x1, #4]
    str     w0, [x10, #0x1C]
    dsb     sy
    mov     w4, #2
    str     w4, [x5]

    // ============================================================
    // Stage 3: write PM_GET_API_VERSION request to REQ_BUFFER_ADDR
    // word[0] = 0x1, word[1..7] = 0
    // ============================================================
    load_addr x1, REQ_BUFFER_ADDR
    mov     w0, #PM_GET_API_VERSION
    str     w0, [x1, #0]
    str     wzr, [x1, #4]
    str     wzr, [x1, #8]
    str     wzr, [x1, #12]
    str     wzr, [x1, #16]
    str     wzr, [x1, #20]
    str     wzr, [x1, #24]
    str     wzr, [x1, #28]
    dsb     sy

    // Echo request to OCM +0x50..+0x6F for debug
    ldr     w0, [x1, #0]
    str     w0, [x10, #0x50]
    ldr     w0, [x1, #4]
    str     w0, [x10, #0x54]
    ldr     w0, [x1, #8]
    str     w0, [x10, #0x58]
    ldr     w0, [x1, #12]
    str     w0, [x10, #0x5C]
    ldr     w0, [x1, #16]
    str     w0, [x10, #0x60]
    ldr     w0, [x1, #20]
    str     w0, [x10, #0x64]
    ldr     w0, [x1, #24]
    str     w0, [x10, #0x68]
    ldr     w0, [x1, #28]
    str     w0, [x10, #0x6C]
    dsb     sy
    mov     w4, #3
    str     w4, [x5]

    // ============================================================
    // Stage 4: trigger IPI — write PMU0_BIT to APU.TRIG
    // ============================================================
    load_addr x1, APU_IPI_BASE
    load_imm w0, PMU0_BIT
    str     w0, [x1, #OFF_TRIG]
    dsb     sy

    // Immediately read APU.OBS — bit 16 should be SET (outstanding)
    ldr     w0, [x1, #OFF_OBS]
    str     w0, [x10, #0x20]
    dsb     sy
    mov     w4, #4
    str     w4, [x5]

    // ============================================================
    // Stage 5: poll APU.OBS for PMU's completion (bit 16 CLEARS). Max 100000.
    // Blocking PM protocol: OBS target bit is SET on trigger and CLEARS when
    // PMU has serviced the request and the response buffer is valid.
    // ============================================================
    load_imm w7, 100000
    mov     w8, #0                      // iters used
poll_loop:
    load_addr x1, APU_IPI_BASE
    ldr     w0, [x1, #OFF_OBS]
    and     w0, w0, #PMU0_BIT
    cbz     w0, poll_done               // OBS bit 16 CLEARED => PMU done
    add     w8, w8, #1
    subs    w7, w7, #1
    bne     poll_loop
poll_done:
    str     w8, [x10, #0x2C]            // iters used
    dsb     sy
    mov     w4, #5
    str     w4, [x5]

    // ============================================================
    // Stage 6: snapshot post-poll APU.OBS + APU.ISR
    // ============================================================
    load_addr x1, APU_IPI_BASE
    ldr     w0, [x1, #OFF_OBS]
    str     w0, [x10, #0x24]
    ldr     w0, [x1, #OFF_ISR]
    str     w0, [x10, #0x28]
    dsb     sy
    mov     w4, #6
    str     w4, [x5]

    // ============================================================
    // Stage 7: read response buffer (8 words to OCM +0x30..+0x4F)
    // ============================================================
    load_addr x1, RSP_BUFFER_ADDR
    ldr     w0, [x1, #0]
    str     w0, [x10, #0x30]
    ldr     w0, [x1, #4]
    str     w0, [x10, #0x34]
    ldr     w0, [x1, #8]
    str     w0, [x10, #0x38]
    ldr     w0, [x1, #12]
    str     w0, [x10, #0x3C]
    ldr     w0, [x1, #16]
    str     w0, [x10, #0x40]
    ldr     w0, [x1, #20]
    str     w0, [x10, #0x44]
    ldr     w0, [x1, #24]
    str     w0, [x10, #0x48]
    ldr     w0, [x1, #28]
    str     w0, [x10, #0x4C]
    dsb     sy
    mov     w4, #7
    str     w4, [x5]

    // ============================================================
    // Stage 8: acknowledge ISR (write bit 16 back to clear)
    // ============================================================
    load_addr x1, APU_IPI_BASE
    load_imm w0, PMU0_BIT
    str     w0, [x1, #OFF_ISR]
    dsb     sy
    // Snapshot ISR after clear-write
    ldr     w0, [x1, #OFF_ISR]
    str     w0, [x10, #0x70]
    dsb     sy
    mov     w4, #8
    str     w4, [x5]

    // ============================================================
    // Done marker
    // ============================================================
    load_imm w0, DONE_MARKER_VAL
    str     w0, [x6]
    dsb     sy
    mov     w4, #9
    str     w4, [x5]
    dsb     sy

spin:
    b       spin
