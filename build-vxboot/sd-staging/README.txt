SD-card staging — ZCU102 (board 210308BD8D4D)        2026-06-08
==============================================================
Copy this folder to a flash drive -> move to the PC with the SD reader ->
write files onto the SD's FAT (boot) partition. Verify after copy:
    md5sum -c MD5SUMS
Do NOT reformat/repartition. Keep the board's existing files (image.ub,
boot.scr, vxWorks.bin, npMain_*). Boot strap: SW6 = SD (1 ON, 2/3/4 OFF).
Console: ttyUSB0 @115200.

The ZynqMP BootROM (SD mode) loads exactly ONE file: BOOT.BIN, from the FAT
root. Whatever you put there as BOOT.BIN is what boots.

FILES
  BOOT.vxworks-v4.bin  HIGH-FIDELITY VxWorks boot (USE THIS). npMain's own
                       bitstream + bl31@EL3 + custom loader, with only the FSBL
                       swapped for a ZCU102-correct one. The npMain loader runs
                       the REAL VxWorks from QSPI via the REAL npMain launch.
  BOOT.vxworks-v5.bin  Fallback only: self-contained VxWorks (FSBL+PMUFW +
                       bl31@EL3 + vxWorks@0x100000 EL1, no loader/QSPI). Lower
                       fidelity (bypasses npMain's loader) but no QSPI/strap dep.
  BOOT.petalinux.bin   Original PetaLinux image — restore/safe fallback.

ORDER (on the PC with the reader, mounting the SD FAT partition):
  0) SANITY/RESTORE:  copy BOOT.petalinux.bin -> BOOT.BIN ; boot ; confirm
     PetaLinux on ttyUSB0 (proves card+board path good).
  1) HIGH-FIDELITY:   copy BOOT.vxworks-v4.bin -> BOOT.BIN ; boot ; watch ttyUSB0
     for the FSBL banner + npMain loader messages + VxWorks.
  2) IF v4 STALLS:    copy BOOT.vxworks-v5.bin -> BOOT.BIN ; boot (fallback).
  Revert anytime: BOOT.petalinux.bin -> BOOT.BIN.

NOTE: v4 keeps npMain's loader, which does gpio image-select + QSPI copy. If it
misbehaves on the bare board (no tactical carrier), that's the known risk; v5 is
the fallback, and an even-higher-fidelity option (DDR-patch npMain's own FSBL so
the 100%-original QSPI system boots) is possible if wanted.
