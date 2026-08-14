# jtag-ddr-boot.tcl — bring up DDR over JTAG by REPLAYING psu_init as MMIO (A53 halted),
# then verify DDR. No A53 code execution -> no FSBL boot-device error-lockdown -> no wedge.
# Stage B (load + run U-Boot) is separate, once DDR is confirmed.
#
# Preconditions: SW6 = JTAG (all ON), freshly power-cycled (1-min drain).
# Run: openocd -f openocd/zcu102.cfg -c "source openocd/jtag-ddr-boot.tcl" -c shutdown

source openocd/psu-init-replay.tcl

proc do_release {} {
  catch { uscale.dap dpreg 0 0x1e } e
  targets uscale.axi
  catch { uscale.axi arp_examine } e
  write_memory 0xFFFC0000 32 {0x14000000}   ;# safe landing (b .)
  write_memory 0xFD5C0040 32 {0xFFFC0000}   ;# RVBARADDR0L
  write_memory 0xFD5C0044 32 {0x00000000}   ;# RVBARADDR0H
  write_memory 0xFD1A0104 32 {0x0000380E}   ;# RST_FPD_APU: clear core0+L2+pwron reset
  catch { uscale.dap dpreg 0 0x1e } e
  catch { uscale.a53.0 arp_examine } e
  targets uscale.a53.0
  halt
  echo "=== A53-0 released + parked (halted at safe landing) ==="
}

proc verify_ddr {} {
  echo "=== verify DDR (write/readback at 2 regions) ==="
  set ok 1
  foreach base {0x00100000 0x40000000} {
    write_memory $base 32 {0xCAFEBABE 0x55AA1234 0x0BADF00D 0xFEEDFACE}
    set rb [read_memory $base 32 4]
    echo "    [format 0x%08x $base]: $rb"
    if {[lindex $rb 0] != 0xcafebabe || [lindex $rb 3] != 0xfeedface} { set ok 0 }
  }
  if {$ok} { echo "*** DDR IS LIVE ***" } else { echo "*** DDR NOT working ***" }
  return $ok
}

init
do_release
targets uscale.axi
echo "=== replaying psu_init via JTAG MMIO (A53 halted) ==="
psu_replay
echo "=== psu_init replay finished; checking DAP + DDR ==="
if {[alive]} { verify_ddr } else { echo "DAP wedged during replay (see WEDGE line above)" }

# ---- Stage B: load U-Boot into DDR and run it (call after DDR is confirmed) ----
proc boot_uboot {} {
  echo "=== Stage B: load U-Boot to 0x08000000 and run ==="
  targets uscale.axi
  load_image build-vxboot/u-boot.bin 0x08000000 bin
  # verify a couple words landed
  echo "    U-Boot @0x8000000: [read_memory 0x08000000 32 2]"
  targets uscale.a53.0
  catch { halt } e
  reg pc 0x08000000
  resume
  echo "    U-Boot resumed at 0x08000000 (EL3). Watch ttyUSB0 @115200."
}
