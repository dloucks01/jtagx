# jtag-load-uboot.tcl — robust U-Boot load over JTAG (canonical loader; was jtag-uboot-v4).
#   * 4096-word write/read chunks (proven-clean size; avoids 16K-read wedge & load_image)
#   * per-chunk read-back + retry (rides over sparse DDR glitches)
#   * file-read diagnostic + hardcoded spot-check (detects Jim binary-read mangling)
# Sourcing jtag-ddr-boot.tcl first runs: init + release + psu_init replay + verify_ddr.
source openocd/jtag-ddr-boot.tcl

proc fileread_diag {file} {
  set fp [open $file rb]; fconfigure $fp -translation binary
  set data [read $fp 32]; close $fp
  binary scan $data iu* w
  echo "=== Jim file-read diag (first 8 words; expect 1400000a d503201f 08000000 00000000 0015a6c8 00000000 0015a6c8 00000000) ==="
  set s ""; foreach x $w { append s [format "%08x " $x] }
  echo "    got: $s"
  return [lindex $w 0]
}

proc load_uboot {file base} {
  set total [file size $file]
  set fp [open $file rb]; fconfigure $fp -translation binary
  set off 0; set glitch 0; set fail 0
  targets uscale.axi
  while {$off < $total} {
    set rem [expr {$total - $off}]
    if {$rem > 16384} { set nb 16384 } else { set nb $rem }
    set data [read $fp $nb]
    binary scan $data iu* words
    set a [expr {$base + $off}]
    set tries 0
    while {1} {
      write_memory $a 32 $words
      set rb [read_memory $a 32 [llength $words]]
      set bad 0
      foreach wv $words rv $rb { if {$wv != $rv} { incr bad } }
      if {$bad == 0} break
      incr tries; incr glitch
      if {$tries >= 5} { echo "    chunk @[format 0x%x $a]: $bad bad after 5 tries"; incr fail; break }
    }
    set off [expr {$off + $nb}]
    if {$off % 0x80000 == 0} { echo "    [expr {$off/1024}] KB (retried glitches: $glitch)" }
  }
  close $fp
  echo "  load done; glitch-retries=$glitch, chunks-still-bad=$fail"
  return $fail
}

proc verify_uboot {base} {
  set ok 1
  foreach {o exp} {0x0 0x1400000a 0x4 0xd503201f 0x1000 0x08000ff8 0x100000 0x3c006d65 0x150000 0x081326f8} {
    set got [lindex [read_memory [expr {$base+$o}] 32 1] 0]
    if {$got != $exp} { set ok 0; set m BAD } else { set m ok }
    echo "    +[format 0x%08x $o]: got [format 0x%08x $got] exp [format 0x%08x $exp]  $m"
  }
  return $ok
}

if {![alive]} { echo "DAP wedged after replay — abort"; shutdown }
fileread_diag build-vxboot/u-boot.bin
echo "=== loading U-Boot (4K-word chunks, verify+retry) ==="
load_uboot build-vxboot/u-boot.bin 0x08000000
echo "=== final spot-check vs known file values ==="
if {[verify_uboot 0x08000000]} {
  echo "=== U-Boot VERIFIED — set RVBAR + jump @0x8000000 (EL3) ==="
  targets uscale.axi
  write_memory 0xFD5C0040 32 {0x08000000}
  write_memory 0xFD5C0044 32 {0x00000000}
  targets uscale.a53.0
  catch { halt } e
  reg pc 0x08000000
  resume
  echo "=== U-Boot resumed — watch ttyUSB0 @115200 ==="
} else {
  echo "*** spot-check FAILED. If per-chunk retries were ~0 but this is BAD,"
  echo "    the Jim file-read is mangling data -> switch to Python-embedded loader."
}
