// AArch64 hello-world for ZCU102 PS UART0
// Loaded at 0xFFFC0000 (OCM bank 0 start).
// Assumes: UART0 ref clock is set up by host before A53 is resumed
//          (the OpenOCD loader writes IOU_SLCR.UART0_REF_CTRL via AXI mem-AP)

.equ UART0_BASE,    0xFF000000
.equ UART_CR,       0x00       // Control
.equ UART_MR,       0x04       // Mode
.equ UART_BAUDGEN,  0x18       // Baud rate generator (CD)
.equ UART_CSR,      0x2C       // Channel status
.equ UART_FIFO,     0x30       // TX/RX FIFO
.equ UART_BAUD_DIV, 0x34       // Baud rate divider (BDIV)

.equ CR_TXRST,      0x02
.equ CR_RXRST,      0x01
.equ CR_TX_EN,      0x10
.equ CR_RX_EN,      0x04
.equ SR_TXFULL,     0x10

.section .text
.global _start

_start:
    // x0 = UART0 base
    movz x0, #0x0000
    movk x0, #0xFF00, lsl #16

    // CR = TXRST | RXRST (reset both FIFOs)
    mov w1, #(CR_TXRST | CR_RXRST)
    str w1, [x0, #UART_CR]

    // MR = 0x20 (8 bits, no parity, 1 stop, normal mode, ref_clk/1)
    mov w1, #0x20
    str w1, [x0, #UART_MR]

    // BAUDGEN.CD = 124 (0x7C) -> for 100MHz ref clock + BDIV=6, baud≈115200
    mov w1, #0x7C
    str w1, [x0, #UART_BAUDGEN]

    // BAUD_DIV.BDIV = 6 (so divisor is BDIV+1 = 7)
    mov w1, #0x6
    str w1, [x0, #UART_BAUD_DIV]

    // CR = TX_EN | RX_EN
    mov w1, #(CR_TX_EN | CR_RX_EN)
    str w1, [x0, #UART_CR]

    // x2 = pointer to message
    adr x2, message

print_loop:
    ldrb w3, [x2]
    cbz  w3, hang                // null terminator?

wait_tx:
    ldr  w4, [x0, #UART_CSR]
    tst  w4, #SR_TXFULL
    b.ne wait_tx

    str  w3, [x0, #UART_FIFO]
    add  x2, x2, #1
    b    print_loop

hang:
    b    hang

.balign 4
message:
    .ascii "Hello from A53 core 0, running via raw JTAG bring-up\r\n"
    .ascii "(no FSBL, no PMU firmware, no Xilinx tooling)\r\n"
    .byte  0
