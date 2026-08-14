# json-emit.tcl - capture register reads into a structured dict, write JSON.
#
# Rewritten for Jim Tcl compatibility (used by OpenOCD).
# Avoids: split with empty separator, string is integer -strict, fancy
# comment characters, complex line continuations.
#
# Builds up a single ::CAPTURED dict during enumerate.tcl execution;
# written to reports/raw-<timestamp>.json at end of run.
#
# Schema top-level keys:
#   schema_version, metadata, chain, variant, registers, a53,
#   memory_probes, boot_state, coresight, notes

# ---------------------------------------------------------------------------
# Global capture dict.
# ---------------------------------------------------------------------------
set ::CAPTURED [dict create]
dict set ::CAPTURED schema_version "1.0"
dict set ::CAPTURED metadata      [dict create]
dict set ::CAPTURED chain         [dict create taps [list]]
dict set ::CAPTURED variant       [dict create]
dict set ::CAPTURED registers     [dict create]
dict set ::CAPTURED a53           [dict create]
dict set ::CAPTURED memory_probes [dict create]
dict set ::CAPTURED boot_state    [dict create]
dict set ::CAPTURED coresight     [dict create]
dict set ::CAPTURED notes         [list]


# ---------------------------------------------------------------------------
# JSON string escape using string map. Portable across Tcl and Jim Tcl.
# Handles the must-escape characters from RFC 8259. Non-ASCII passes through
# as UTF-8.
# ---------------------------------------------------------------------------
proc json_escape_string {s} {
    return [string map [list \
        "\\" "\\\\" \
        "\"" "\\\"" \
        "\n" "\\n" \
        "\r" "\\r" \
        "\t" "\\t" \
        "\b" "\\b" \
        "\f" "\\f"] $s]
}


# ---------------------------------------------------------------------------
# Is value an integer? Portable check using regex.
# ---------------------------------------------------------------------------
proc _is_decimal_int {v} {
    return [regexp {^-?[0-9]+$} $v]
}

proc _is_hex_int {v} {
    return [regexp {^0[xX][0-9a-fA-F]+$} $v]
}


# ---------------------------------------------------------------------------
# Emit a scalar value as JSON. Hex literals preserved as quoted strings for
# human readability; decimal ints emitted as JSON numbers.
# ---------------------------------------------------------------------------
proc json_emit_scalar {value} {
    if {$value eq "true"}  { return "true"  }
    if {$value eq "false"} { return "false" }
    if {$value eq "null"}  { return "null"  }
    if {[_is_hex_int $value]} {
        return "\"$value\""
    }
    if {[_is_decimal_int $value]} {
        return $value
    }
    return "\"[json_escape_string $value]\""
}


# ---------------------------------------------------------------------------
# Record a register read into ::CAPTURED.registers
# ---------------------------------------------------------------------------
proc capture_register {addr name block value {fields_dict ""}} {
    set addr_int [expr {int($addr)}]
    set addr_hex [format "0x%08X" $addr_int]
    set entry [dict create]
    dict set entry name    $name
    dict set entry block   $block
    dict set entry address $addr_hex
    if {$value eq "ERR"} {
        dict set entry value     "ERR"
        dict set entry value_int "null"
        dict set entry read_error true
    } else {
        dict set entry value     [format "0x%08X" [expr {int($value)}]]
        dict set entry value_int [expr {int($value)}]
    }
    if {$fields_dict ne "" && [dict size $fields_dict] > 0} {
        dict set entry fields $fields_dict
    }
    dict set ::CAPTURED registers $addr_hex $entry
}


# ---------------------------------------------------------------------------
# Serialize the full ::CAPTURED dict and write to a file path.
# ---------------------------------------------------------------------------
proc capture_write_json {path} {
    set fh [open $path w]
    puts $fh [_serialize_top $::CAPTURED]
    close $fh
}


# Top-level serializer. Each top-level block has its own emitter so we can
# control formatting per block.
proc _serialize_top {d} {
    set out "\{\n"
    set parts [list]
    lappend parts "  \"schema_version\": [json_emit_scalar [dict get $d schema_version]]"
    lappend parts "  \"metadata\": [_serialize_flat_dict [dict get $d metadata] 2]"
    lappend parts "  \"chain\": [_serialize_chain [dict get $d chain] 2]"
    lappend parts "  \"variant\": [_serialize_flat_dict [dict get $d variant] 2]"
    lappend parts "  \"registers\": [_serialize_registers [dict get $d registers] 2]"
    lappend parts "  \"a53\": [_serialize_flat_dict [dict get $d a53] 2]"
    lappend parts "  \"memory_probes\": [_serialize_flat_dict [dict get $d memory_probes] 2]"
    lappend parts "  \"boot_state\": [_serialize_flat_dict [dict get $d boot_state] 2]"
    lappend parts "  \"coresight\": [_serialize_coresight [dict get $d coresight] 2]"
    lappend parts "  \"notes\": [_serialize_notes [dict get $d notes] 2]"
    append out [join $parts ",\n"]
    append out "\n\}"
    return $out
}


# Flat dict: keys map to scalar values. Lists with >1 element become JSON arrays.
proc _serialize_flat_dict {d indent} {
    if {[dict size $d] == 0} { return "{}" }
    set ind  [string repeat " " $indent]
    set ind2 [string repeat " " [expr {$indent + 2}]]
    set parts [list]
    dict for {k v} $d {
        set ek "\"[json_escape_string $k]\""
        if {[llength $v] > 1} {
            set arr_parts [list]
            foreach item $v {
                lappend arr_parts [json_emit_scalar $item]
            }
            lappend parts "$ind2$ek: \[[join $arr_parts {, }]\]"
        } else {
            lappend parts "$ind2$ek: [json_emit_scalar $v]"
        }
    }
    return "\{\n[join $parts ",\n"]\n$ind\}"
}


# Chain dict: has a "taps" key that is a list of tap dicts.
proc _serialize_chain {d indent} {
    set ind  [string repeat " " $indent]
    set ind2 [string repeat " " [expr {$indent + 2}]]
    set ind3 [string repeat " " [expr {$indent + 4}]]
    set taps [dict get $d taps]
    if {[llength $taps] == 0} { return "\{\"taps\": \[\]\}" }
    set tap_parts [list]
    foreach tap $taps {
        set tp [list]
        dict for {k v} $tap {
            lappend tp "$ind3\"[json_escape_string $k]\": [json_emit_scalar $v]"
        }
        lappend tap_parts "$ind2\{\n[join $tp ",\n"]\n$ind2\}"
    }
    return "\{\n$ind2\"taps\": \[\n[join $tap_parts ",\n"]\n$ind2\]\n$ind\}"
}


# Registers dict: addr -> { name, block, value, value_int, fields }
proc _serialize_registers {d indent} {
    if {[dict size $d] == 0} { return "{}" }
    set ind  [string repeat " " $indent]
    set ind2 [string repeat " " [expr {$indent + 2}]]
    set ind3 [string repeat " " [expr {$indent + 4}]]
    set ind4 [string repeat " " [expr {$indent + 6}]]
    set parts [list]
    dict for {addr reg} $d {
        set ek "\"[json_escape_string $addr]\""
        set rp [list]
        dict for {k v} $reg {
            set rk "\"[json_escape_string $k]\""
            if {$k eq "fields"} {
                set fp [list]
                dict for {fname fdata} $v {
                    set fpa [list]
                    dict for {fk fv} $fdata {
                        lappend fpa "$ind4\"[json_escape_string $fk]\": [json_emit_scalar $fv]"
                    }
                    lappend fp "$ind3\"[json_escape_string $fname]\": \{\n[join $fpa ",\n"]\n$ind3\}"
                }
                lappend rp "$ind3$rk: \{\n[join $fp ",\n"]\n$ind3\}"
            } else {
                lappend rp "$ind3$rk: [json_emit_scalar $v]"
            }
        }
        lappend parts "$ind2$ek: \{\n[join $rp ",\n"]\n$ind2\}"
    }
    return "\{\n[join $parts ",\n"]\n$ind\}"
}


# Coresight: dict with "ap_info" key mapping AP num -> raw 'dap info N' text.
# Text is multi-line and contains characters that need full JSON-string escape.
proc _serialize_coresight {d indent} {
    if {[dict size $d] == 0} { return "{}" }
    set ind  [string repeat " " $indent]
    set ind2 [string repeat " " [expr {$indent + 2}]]
    set ind3 [string repeat " " [expr {$indent + 4}]]
    set parts [list]
    dict for {k v} $d {
        # k is e.g. "ap_info"; v is a sub-dict ap_num -> text
        set sub [list]
        if {[catch {dict size $v} _]} {
            lappend parts "$ind2\"[json_escape_string $k]\": [json_emit_scalar $v]"
        } else {
            dict for {sk sv} $v {
                lappend sub "$ind3\"[json_escape_string $sk]\": [json_emit_scalar $sv]"
            }
            lappend parts "$ind2\"[json_escape_string $k]\": \{\n[join $sub ",\n"]\n$ind2\}"
        }
    }
    return "\{\n[join $parts ",\n"]\n$ind\}"
}


# Notes: list of {section, text} dicts.
proc _serialize_notes {notes indent} {
    if {[llength $notes] == 0} { return "\[\]" }
    set ind  [string repeat " " $indent]
    set ind2 [string repeat " " [expr {$indent + 2}]]
    set ind3 [string repeat " " [expr {$indent + 4}]]
    set parts [list]
    foreach n $notes {
        set np [list]
        dict for {k v} $n {
            lappend np "$ind3\"[json_escape_string $k]\": [json_emit_scalar $v]"
        }
        lappend parts "$ind2\{\n[join $np ",\n"]\n$ind2\}"
    }
    return "\[\n[join $parts ",\n"]\n$ind\]"
}
