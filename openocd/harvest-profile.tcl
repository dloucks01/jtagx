# harvest-profile.tcl — ONE read-only discovery pass on a RUNNING ZynqMP board -> boards/<soc>.env,
# which the capability scripts then source via board-profile.tcl. Nothing here is ZCU102-specific:
# every value is read from the silicon or detected from the cfg, so the SAME pass works on any
# UltraScale+ board. Non-invasive: does NOT halt cores or write memory.
#
# Run: BOARD_SOC=<name> openocd -f openocd/<board>.cfg -c "init; source openocd/harvest-profile.tcl; shutdown"
#   (BOARD_SOC just names the output file; default "zynqmp". probe-board.sh passes the IDCODE-decoded SoC.)

set _d [file dirname [info script]]
if {[info commands say] eq ""} { proc say {l} { echo $l } }
source [file join $_d board-profile.tcl]    ;# sets $AXI_TARGET / $DAP_NAME (auto-detected)

proc _envd {n d} { if {[info exists ::env($n)]} { return $::env($n) } ; return $d }
set SOC [_envd BOARD_SOC zynqmp]

catch { targets $AXI_TARGET } _
catch { $AXI_TARGET arp_examine } _
for {set i 0} {$i < 3} {incr i} { catch { $DAP_NAME dpreg 0 0x1e } _ ; after 5 }

# --- boot media from BOOT_MODE_USER (0xFF5E0200, bits 3-0) — read, never assumed ---
set BOOT_MODE_REG 0xFF5E0200
set bm "ERR"; set media "unknown"; set readcmd ""
if {![catch {read_memory $BOOT_MODE_REG 32 1} v]} {
  set bm [expr {[lindex $v 0] & 0xF}]
  switch -- $bm {
    0       { set media jtag ; set readcmd "" }
    1       { set media qspi ; set readcmd "sf probe 0 0 0 ; sf read" }
    2       { set media qspi ; set readcmd "sf probe 0 0 0 ; sf read" }
    3       { set media sd   ; set readcmd "(SD = FAT partition; pull files over UART — see project_sd_extract)" }
    5       { set media sd   ; set readcmd "mmc dev 0 ; mmc read" }
    6       { set media emmc ; set readcmd "mmc dev 0 ; mmc read" }
    7       { set media usb  ; set readcmd "" }
    8       { set media pjtag; set readcmd "" }
    14      { set media sd   ; set readcmd "mmc dev 0 ; mmc read" }
    default { set media "mode-$bm" ; set readcmd "" }
  }
}

# --- DDR base: ZynqMP low DRAM window is 0x0 on every part (high window 0x800000000 if >2 GB) ---
set DDR_BASE 0x00000000

# --- write the profile ---
file mkdir [file join $_d .. boards]
set out [file join $_d .. boards "${SOC}.env"]
set ts "unknown-time"
catch { set ts [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"] }
set fh [open $out w]
puts $fh "# board profile — harvested $ts from a RUNNING board (read-only pass)"
puts $fh "# sourced automatically by board-profile.tcl; override any line, or delete to re-harvest."
puts $fh "BOARD_SOC=$SOC"
puts $fh "AXI_TARGET=$AXI_TARGET"
puts $fh "DAP_NAME=$DAP_NAME"
puts $fh "BOOT_MODE=[expr {$bm eq {ERR} ? {ERR} : [format 0x%X $bm]}]"
puts $fh "BOOT_MEDIA=$media"
puts $fh "FLASH_READ_CMD=$readcmd"
puts $fh "DDR_BASE=$DDR_BASE"
puts $fh "# OS_BASE — discover: DUMP_ADDR=0x0 DUMP_SIZE=0x04000000 source dump-os-ddr.tcl ; strings/binwalk the result"
puts $fh "OS_BASE="
close $fh

say ""
say "================================================================"
say " BOARD PROFILE HARVESTED (read-only, running board)"
say "================================================================"
say " soc          $SOC"
say " axi target   $AXI_TARGET    (auto-detected — not hardcoded)"
say " dap          $DAP_NAME"
say [format " boot mode    %s  -> media=%s" [expr {$bm eq {ERR} ? {ERR} : [format 0x%X $bm]}] $media]
if {$readcmd ne ""} { say " flash read   $readcmd <ddr> <off> <len>" }
say " ddr base     $DDR_BASE"
say " profile ->   $out"
say ""
say "reopen-debug / dump-os-ddr / dump-boot-flash now auto-source this — no per-board edits needed."
say ""
