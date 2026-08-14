// csu-hello-uart.S — A53 EL3 hello-world over PS UART0 on a BOOTED ZCU102.
//
// Closes the long-deferred "hello world" (task #14). The original JTAG-idle
// attempt failed because no PLL/UART clock was set up (wrong baud), pending
// Vitis psu_init magic numbers. In BOOTED state FSBL has already configured
// UART0 (the Linux console runs on it at 115200), so this payload does NOT
// touch CR/MR/BAUDGEN — it simply writes bytes to the TX FIFO using the
// live, correct configuration. BOOTED_STATE freezes Linux so there is no
// console contention while we transmit.
//
// PS UART0 = Cadence UART @ 0xFF000000:
//   CSR  +0x2C  channel status (bit4 = TXFULL)
//   FIFO +0x30  TX/RX FIFO (write a byte to transmit)
//
// Writes a done marker at 0xFFFE7000 = 0xCAFEC0DE so the dump-bootrom harness
// poll succeeds. Observe the text on ttyUSB0.

.equ UART0_BASE,        0xFF000000
.equ UART_CSR,          0x2C
.equ UART_FIFO,         0x30
.equ SR_TXFULL,         0x10

.equ DONE_MARKER_ADDR,  0xFFFE7000
.equ DONE_MARKER_VAL,   0xCAFEC0DE
.equ STAGE_ADDR,        0xFFFE7080

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
    load_addr x0, UART0_BASE
    load_addr x5, STAGE_ADDR
    mov     w4, #1
    str     w4, [x5]
    adr     x2, message

print_loop:
    ldrb    w3, [x2]
    cbz     w3, done
wait_tx:
    ldr     w4, [x0, #UART_CSR]
    tst     w4, #SR_TXFULL
    b.ne    wait_tx
    str     w3, [x0, #UART_FIFO]
    add     x2, x2, #1
    b       print_loop

done:
    load_addr x6, DONE_MARKER_ADDR
    load_imm  w5, DONE_MARKER_VAL
    str       w5, [x6]
    dsb       sy
    load_addr x5, STAGE_ADDR
    mov       w4, #2
    str       w4, [x5]
    dsb       sy
spin:
    b       spin

.balign 4
message:
    .ascii "\r\n==================================================\r\n"
    .ascii "  Hello world from A53 core 0 at EL3, via raw JTAG\r\n"
    .ascii "  on a BOOTED ZCU102 (UART0 configured by FSBL).\r\n"
    .ascii "  Payload only writes the TX FIFO -- correct baud.\r\n"
    .ascii "==================================================\r\n"
    .byte  0
