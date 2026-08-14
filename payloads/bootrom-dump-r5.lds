/* Linker script for bootrom-dump-r5.S (Cortex-R5).
 *
 * R5 boots from address 0x00000000 (its local view of ATCM). JTAG writes
 * the payload to global address 0xFFE00000 which is the same physical
 * memory. We place .text at 0x0 from R5's perspective.
 */
OUTPUT_ARCH(arm)
ENTRY(_start)
SECTIONS
{
    . = 0x00000000;
    .text   : { *(.text*) }
    .data   : { *(.data*) }
    .rodata : { *(.rodata*) }
}
