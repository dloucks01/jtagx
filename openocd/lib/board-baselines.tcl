# board-baselines.tcl — per-board observed register baselines.
#
# Many research probes know what value a register should hold on the
# reference board so the verdict text can say "OK, restore correct" or
# "DRIFT detected". Hardcoding these in handlers makes the tool
# non-portable and clutters the verdict logic. Instead, handlers look
# baselines up here via:
#
#     set baseline [::baseline::get FFCAF000]
#
# To add support for a new board:
#   1. Identify the board (chip rev, eFuse policy, boot state)
#   2. Run `openocd -f your-board.cfg -c "init; source openocd/enumerate.tcl"`
#      to capture baselines
#   3. Add a new namespace block below following the zcu102_jtag_idle pattern
#   4. Set ::baseline::ACTIVE_BOARD to your board key (default: zcu102_jtag_idle)
#
# The baselines below are from board S/N 210308BD8D4D, XCZU9EG, JTAG-idle,
# no FSBL. They were captured 2026-05-26..05-28 across multiple sessions
# and verified stable across power-cycles.

namespace eval ::baseline {
    # Per-board baseline dictionaries. Keys are hex addresses (without
    # 0x prefix, uppercase). Values are the expected idle value.
    variable BOARDS [dict create]

    # zcu102_jtag_idle: ZCU102 dev kit (XCZU9EG), JTAG-idle, no FSBL/PMU FW.
    # Reference board S/N 210308BD8D4D.
    dict set BOARDS zcu102_jtag_idle [dict create \
        FFCA0000 0x00000000 \
        FFCA0004 0x00000000 \
        FFCA0008 0x00000050 \
        FFCA0020 0x00008034 \
        FFCA0038 0x0000003F \
        FFCA003C 0x000000FF \
        FFCA0050 0x26042731 \
        FFCA0054 0x0B5A3BDB \
        FFCA0058 0x7FBEE59B \
        FFCA005C 0x8327B4E3 \
        FFCA5000 0x00000000 \
        FFCA1000 0x00000F00 \
        FFCA3000 0x00000001 \
        FFCAF000 0x02DDB2CB \
        FFCAF004 0x00000003 \
        FFCC0008 0x00000027 \
        FFCC1058 0x00000000 \
        FFD80000 0x00018800 \
        FFD80100 0x00FFFCBF]

    # Active board — set this via env or override before sourcing.
    variable ACTIVE_BOARD "zcu102_jtag_idle"
    if {[info exists ::env(BASELINE_BOARD)]} {
        set ACTIVE_BOARD $::env(BASELINE_BOARD)
    }

    # Lookup helper. Returns the baseline as an integer (matching what
    # an int($safe_rd_result) produces), or empty string if unknown.
    # Address may be passed as "FFCAF000" or "0xFFCAF000" — case-insensitive.
    proc get {addr} {
        variable BOARDS
        variable ACTIVE_BOARD
        set key [string toupper [regsub -nocase {^0x} $addr ""]]
        if {![dict exists $BOARDS $ACTIVE_BOARD]} { return "" }
        set board_dict [dict get $BOARDS $ACTIVE_BOARD]
        if {![dict exists $board_dict $key]} { return "" }
        return [dict get $board_dict $key]
    }

    # As above but formatted as a 0x%08X hex string for display.
    proc get_hex {addr} {
        set v [get $addr]
        if {$v eq ""} { return "(unknown)" }
        return [format "0x%08X" [expr {$v & 0xFFFFFFFF}]]
    }
}
