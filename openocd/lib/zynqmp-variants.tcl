# Single source of truth for ZynqMP/RFSoC variant capabilities, indexed by
# IDCODE PART_ID (bits [27:12] of the JTAG IDCODE).
#
# Sources:
#   - UG1085 (ZynqMP TRM) Table 39-1 — part ID assignments
#   - DS891 / DS925 / DS926 — product specs for MPSoC, MPSoC-EV, RFSoC
#   - openocd/lib/idcode-lookup.tcl (predecessor; values carried forward)
#
# Schema per variant entry (Tcl dict keys):
#   family        zynqmp | rfsoc
#   die           short die name (e.g., "XCZU9")
#   marketed_as   list of package suffixes shipped on this die
#                   CG  = cost-optimized (reduced peripherals)
#                   EG  = standard
#                   EV  = with H.264/H.265 VCU
#                   TEG = extended-temp standard
#                   DR  = RFSoC (with RF data converters)
#   a53_cores     2 or 4 (silicon-level — same across all packages on a die)
#   r5_cores      always 2 on ZynqMP/RFSoC
#   has_gpu       1 on all ZynqMP/RFSoC dies (Mali-400 MP2)
#   may_have_vcu  1 if at least one package on this die includes the VCU.
#                 IDCODE alone cannot disambiguate EG vs EV bonding.
#                 ACTUAL presence must be probed by reading VCU IDR at
#                 0xFE100000. This flag is informational only.
#   has_rf        1 for RFSoC dies (RF-ADC/DAC tiles present)
#   gem_count     Number of GEM Ethernet controllers (typically 4)
#   notes         free text
#
# Lookup contract:
#   variant_lookup IDCODE → profile dict (returns default_profile if no match)
#   variant_default_profile  → conservative all-capabilities profile (so probes
#                              still run on unknown silicon and reveal truth)

set ::ZYNQMP_VARIANTS [dict create]

proc variant_register {part_id_hex profile} {
    dict set ::ZYNQMP_VARIANTS $part_id_hex $profile
}

# ---------------------------------------------------------------------------
# ZynqMP MPSoC (non-RFSoC) dies
# Per DS891: all have Mali-400 MP2 GPU. VCU only on EV bonding of select dies.
# ---------------------------------------------------------------------------
variant_register 0x4711 {
    family zynqmp die XCZU2 marketed_as {EG CG}
    a53_cores 2 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Dual A53 entry-level MPSoC; no EV variant on this die"
}
variant_register 0x4710 {
    family zynqmp die XCZU3 marketed_as {EG CG TEG}
    a53_cores 2 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Dual A53; Ultra96 boards typically use ZU3EG"
}
variant_register 0x4721 {
    family zynqmp die XCZU4 marketed_as {EG CG EV}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 1 has_rf 0 gem_count 4
    notes "Quad A53; ZU4EV adds VCU"
}
variant_register 0x4720 {
    family zynqmp die XCZU5 marketed_as {EG CG EV}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 1 has_rf 0 gem_count 4
    notes "Quad A53; ZU5EV adds VCU"
}
variant_register 0x4739 {
    family zynqmp die XCZU6 marketed_as {EG CG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Quad A53; no EV variant on this die"
}
variant_register 0x4730 {
    family zynqmp die XCZU7 marketed_as {EG CG EV}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 1 has_rf 0 gem_count 4
    notes "Quad A53; ZU7EV adds VCU"
}
variant_register 0x4738 {
    family zynqmp die XCZU9 marketed_as {EG CG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Quad A53; ZCU102 ships with ZU9EG — no VCU on this die"
}
variant_register 0x4740 {
    family zynqmp die XCZU11 marketed_as {EG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Quad A53; ZCU106 ships with ZU11EG"
}
variant_register 0x4750 {
    family zynqmp die XCZU15 marketed_as {EG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Quad A53 mid-large MPSoC"
}
variant_register 0x4759 {
    family zynqmp die XCZU17 marketed_as {EG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Quad A53 large MPSoC"
}
variant_register 0x4758 {
    family zynqmp die XCZU19 marketed_as {EG}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 0 gem_count 4
    notes "Largest non-RFSoC ZynqMP die"
}

# ---------------------------------------------------------------------------
# RFSoC dies (ZynqMP + RF data converters)
# Same APU/RPU/CSU register map as MPSoC; adds RF tile registers.
# ---------------------------------------------------------------------------
variant_register 0x4828 {
    family rfsoc die XCZU21 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen1"
}
variant_register 0x4829 {
    family rfsoc die XCZU25 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen1"
}
variant_register 0x4830 {
    family rfsoc die XCZU27 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen1"
}
variant_register 0x4831 {
    family rfsoc die XCZU28 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen1; ZCU111 ships with ZU28DR"
}
variant_register 0x4839 {
    family rfsoc die XCZU29 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen1"
}
variant_register 0x4838 {
    family rfsoc die XCZU39 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen2"
}
variant_register 0x4840 {
    family rfsoc die XCZU42 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen2"
}
variant_register 0x4841 {
    family rfsoc die XCZU43 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen2"
}
variant_register 0x4848 {
    family rfsoc die XCZU46 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen2"
}
variant_register 0x4849 {
    family rfsoc die XCZU47 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen3; ZCU208 ships with ZU47DR"
}
variant_register 0x4850 {
    family rfsoc die XCZU48 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen3"
}
variant_register 0x4851 {
    family rfsoc die XCZU49 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen3"
}
variant_register 0x4859 {
    family rfsoc die XCZU65 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen3"
}
variant_register 0x4858 {
    family rfsoc die XCZU67 marketed_as {DR}
    a53_cores 4 r5_cores 2
    has_gpu 1 may_have_vcu 0 has_rf 1 gem_count 4
    notes "RFSoC Gen3; ZCU216 ships with ZU67DR"
}

# ---------------------------------------------------------------------------
# Lookup procs
# ---------------------------------------------------------------------------

# Returns a conservative profile for unknown PART_IDs: assumes 4 A53 cores,
# all capabilities possibly present. This guarantees probes still run on
# unrecognized silicon and findings come from actual hardware behavior,
# not the table.
proc variant_default_profile {part_id} {
    return [dict create \
        family unknown \
        die [format "unknown(0x%04x)" $part_id] \
        marketed_as {?} \
        a53_cores 4 \
        r5_cores 2 \
        has_gpu 1 \
        may_have_vcu 1 \
        has_rf 0 \
        gem_count 4 \
        notes "PART_ID not in zynqmp-variants.tcl; using conservative defaults so probes still run"]
}

# Extract PART_ID from a full IDCODE and look it up.
proc variant_lookup_by_idcode {idcode} {
    set part [expr {($idcode >> 12) & 0xFFFF}]
    return [variant_lookup_by_partid $part]
}

proc variant_lookup_by_partid {part_id} {
    set part_hex [format "0x%04x" $part_id]
    if {[dict exists $::ZYNQMP_VARIANTS $part_hex]} {
        return [dict get $::ZYNQMP_VARIANTS $part_hex]
    }
    return [variant_default_profile $part_id]
}

# Human-readable variant name. Uses die + package list.
proc variant_display_name {profile} {
    set die [dict get $profile die]
    set pkgs [dict get $profile marketed_as]
    if {[llength $pkgs] == 1 && [lindex $pkgs 0] eq "?"} {
        return $die
    }
    return "$die ([join $pkgs /])"
}

# Multi-line capability summary suitable for findings tables.
proc variant_summarize {profile} {
    set lines {}
    lappend lines "Die: [dict get $profile die]"
    lappend lines "Family: [dict get $profile family]"
    lappend lines "Packages on this die: [join [dict get $profile marketed_as] {, }]"
    lappend lines "A53 cores: [dict get $profile a53_cores]"
    lappend lines "R5 cores: [dict get $profile r5_cores]"
    lappend lines "GEM controllers: [dict get $profile gem_count]"
    if {[dict get $profile has_gpu]} {
        lappend lines "GPU (Mali-400): present"
    }
    if {[dict get $profile may_have_vcu]} {
        lappend lines "VCU: possibly present (probe 0xFE100000 to confirm)"
    } else {
        lappend lines "VCU: not on this die"
    }
    if {[dict get $profile has_rf]} {
        lappend lines "RF data converters: present (RFSoC)"
    }
    return [join $lines "\n"]
}
