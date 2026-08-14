/* Linker script: place .text at OCM bank 0 start (0xFFFC0000). */
OUTPUT_ARCH(aarch64)
ENTRY(_start)
SECTIONS
{
    . = 0xFFFC0000;
    .text : { *(.text*) }
    .data : { *(.data*) }
    .rodata : { *(.rodata*) }
}
