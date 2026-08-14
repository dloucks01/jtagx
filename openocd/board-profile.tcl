# board-profile.tcl — single source of per-board variables for the capability scripts
# (reopen-debug / dump-os-ddr / dump-boot-flash). Those scripts hardcode NOTHING board-specific:
# they source this, which resolves every variable with precedence
#       env  >  boards/<soc>.env  >  runtime-detect  >  default
# Assumes a RUNNING board (so the silicon can be queried). Generate the .env with harvest-profile.tcl.
#
# Sets globals: AXI_TARGET, DAP_NAME — and imports any KEY=VALUE from the chosen boards/*.env
# (BOARD_SOC, BOOT_MEDIA, DDR_BASE, OS_BASE, FLASH_READ_CMD, ...) so callers can use them too.
#
# CSU register addresses (JTAG_SEC, JTAG_DAP_CFG, OCM, ...) are UNIVERSAL across ZynqMP and stay in
# the scripts — only the things that genuinely vary per board live here.

# Runtime auto-detect: the mem-AP target is the one whose name contains "axi"; the DAP is the first.
proc bp_detect_axi {} {
  if {![catch {target names} ts]} {
    foreach t $ts { if {[string match {*axi*} $t]} { return $t } }
  }
  return uscale.axi
}
proc bp_detect_dap {} {
  if {![catch {dap names} ds]} { if {[llength $ds] > 0} { return [lindex $ds 0] } }
  return uscale.dap
}

# 1) import the per-board .env  (BOARD_PROFILE=path, else newest boards/*.env)
set _bp_dir  [file join [file dirname [info script]] .. boards]
set _bp_file ""
if {[info exists ::env(BOARD_PROFILE)]} { set _bp_file $::env(BOARD_PROFILE) }
if {$_bp_file eq "" && [file isdirectory $_bp_dir]} {
  set _bp_cands [lsort [glob -nocomplain [file join $_bp_dir *.env]]]
  if {[llength $_bp_cands] > 0} { set _bp_file [lindex $_bp_cands end] }
}
if {$_bp_file ne "" && [file exists $_bp_file]} {
  set _fh [open $_bp_file r]
  while {[gets $_fh _line] >= 0} {
    if {[regexp {^\s*#} $_line]} { continue }
    if {[regexp {^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$} $_line -> _k _v]} {
      set ::$_k [string trim $_v]
    }
  }
  close $_fh
  catch { echo "board-profile: loaded $_bp_file" }
}

# 2) resolve target/dap names: env > .env(already in ::AXI_TARGET) > detect > default
if {[info exists ::env(AXI_TARGET)]} {
  set ::AXI_TARGET $::env(AXI_TARGET)
} elseif {![info exists ::AXI_TARGET]} {
  set ::AXI_TARGET [bp_detect_axi]
}
if {[info exists ::env(DAP_NAME)]} {
  set ::DAP_NAME $::env(DAP_NAME)
} elseif {![info exists ::DAP_NAME]} {
  set ::DAP_NAME [bp_detect_dap]
}

catch { echo "board-profile: AXI_TARGET=$::AXI_TARGET  DAP_NAME=$::DAP_NAME" }
