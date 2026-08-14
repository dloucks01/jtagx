/* Linker script for bootrom-dump.S
 * Places .text at 0xFFFC0100 — leaves OCM 0xFFFC0000..0xFFFC00FF for the
 * §8 release recipe's safe-landing branch (the 'b .' at 0xFFFC0000).
 */
OUTPUT_ARCH(aarch64)
ENTRY(_start)
SECTIONS
{
    . = 0xFFFC0100;
    .text   : { *(.text*) }
    .data   : { *(.data*) }
    .rodata : { *(.rodata*) }
}
