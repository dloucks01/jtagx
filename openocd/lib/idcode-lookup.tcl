# JTAG IDCODE lookup — shared between discover.tcl and enumerate.tcl.
#
# IDCODE format (IEEE 1149.1):
#   [31:28] = version (4 bits, usually silicon revision)
#   [27:12] = part   (16 bits)
#   [11:1]  = manufacturer (11 bits, per JEDEC JEP106)
#   [0]     = constant 1
#
# JEP106 manufacturer IDs (subset relevant to us):
#   0x049 = Xilinx (now AMD)
#   0x23B = ARM Ltd
#   0x02B = Lattice
#   0x06E = Altera (now Intel)
#   0x1FF = "continuation" (legacy)
#
# ZynqMP/RFSoC variant data lives in lib/zynqmp-variants.tcl — single source
# of truth, consumed here and by enumerate.tcl. Zynq-7000 and Versal stay
# inline below until they grow their own variant files.
#
# Cross-reference against the SoC's TRM (UG1085 Table 39-1 for ZynqMP,
# UG585 for Zynq-7000, AM011 for Versal).

# Pull in the ZynqMP/RFSoC variant table (defines ::ZYNQMP_VARIANTS and
# variant_lookup_by_partid). Path relative to this file.
source [file dirname [info script]]/zynqmp-variants.tcl

# Returns a {family chip_name notes} list for a given IDCODE, or
# {unknown "" "no match in table"} if not recognized.
proc identify_idcode {idcode} {
    set mfg  [expr {($idcode >> 1)  & 0x7FF}]
    set part [expr {($idcode >> 12) & 0xFFFF}]
    set rev  [expr {($idcode >> 28) & 0xF}]

    # Format identifiers as hex strings for switch
    set mfg_hex  [format "0x%03x" $mfg]
    set part_hex [format "0x%04x" $part]

    # --- ARM Ltd (CoreSight DAPs) ---
    if {$mfg_hex eq "0x23b"} {
        switch -- $part_hex {
            0xba00 { return [list arm "CoreSight DAP-M (generic)" "ARM debug-access port; usually behind a vendor PS-TAP"] }
            0xba01 { return [list arm "CoreSight DAP-Lite" "" ] }
            0xba02 { return [list arm "CoreSight DAP-M v2" ""] }
            default { return [list arm "unknown ARM TAP" "part $part_hex; consult ARM CoreSight architecture spec"] }
        }
    }

    # --- Xilinx (now AMD) ---
    if {$mfg_hex eq "0x049"} {
        # ZynqMP and RFSoC: delegate to the variant table.
        if {[dict exists $::ZYNQMP_VARIANTS $part_hex]} {
            set profile [variant_lookup_by_partid $part]
            set family [dict get $profile family]
            set name [variant_display_name $profile]
            set notes [dict get $profile notes]
            return [list $family $name $notes]
        }
        # Zynq-7000 family (separate target config) — UG585
        switch -- $part_hex {
            0x3722 { return [list zynq7 "XC7Z010" "Zynq-7000, dual A9 — use target/zynq_7000.cfg, NOT xilinx_zynqmp"] }
            0x3727 { return [list zynq7 "XC7Z020" "Zynq-7000, dual A9 — use target/zynq_7000.cfg"] }
            0x372C { return [list zynq7 "XC7Z030" "Zynq-7000, dual A9"] }
            0x372F { return [list zynq7 "XC7Z045" "Zynq-7000, dual A9"] }
            0x3733 { return [list zynq7 "XC7Z100" "Zynq-7000, dual A9 (largest)"] }
        }
        # Versal family (completely different SoC). Part IDs in 0x04Axxx range.
        if {[expr {($part & 0xFF00) == 0x4A00}]} {
            return [list versal "Versal (part $part_hex)" "Versal ACAP. **Different SoC architecture** — needs xilinx_versal.cfg and fundamentally different enumeration. None of the ZynqMP register maps apply."]
        }
        # Unknown Xilinx part
        return [list xilinx-unknown "" "Xilinx part $part_hex not in table. Consult UG1085 (ZynqMP), UG585 (Zynq-7000), or AM011 (Versal) for chip family."]
    }

    # --- Other manufacturers ---
    return [list unknown "" "Manufacturer $mfg_hex not in lookup table. Cross-reference JEP106 standard manufacturer list."]
}

# Pretty-print an IDCODE lookup result.
proc describe_idcode {idcode} {
    set mfg  [expr {($idcode >> 1)  & 0x7FF}]
    set part [expr {($idcode >> 12) & 0xFFFF}]
    set rev  [expr {($idcode >> 28) & 0xF}]
    set info [identify_idcode $idcode]
    set family [lindex $info 0]
    set chip   [lindex $info 1]
    set notes  [lindex $info 2]
    set out [format "IDCODE 0x%08x: mfg=0x%03x part=0x%04x rev=%d → family=%s" \
                    $idcode $mfg $part $rev $family]
    if {$chip ne ""} { append out " ($chip)" }
    if {$notes ne ""} { append out "\n    ↳ $notes" }
    return $out
}
