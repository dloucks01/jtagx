# dump-memory.tcl — generic memory-range dump for deep-probe tools.
#
# Sourced by openocd/dump-bootrom.tcl and friends. Provides one main proc:
#
#   dump_memory ADDR SIZE_BYTES CHUNK_WORDS OUTPUT_PATH ?label?
#
# Reads SIZE_BYTES from ADDR via uscale.axi's read_memory in CHUNK_WORDS-sized
# chunks (each chunk = CHUNK_WORDS × 4 bytes), writes raw little-endian
# binary to OUTPUT_PATH. Tracks per-chunk read errors and clears DP sticky
# state between chunks to keep one bad address from poisoning later reads.
#
# Returns a dict:
#   bytes_written   — actual bytes in OUTPUT_PATH
#   chunks_total    — number of chunks attempted
#   chunks_ok       — chunks where read_memory succeeded
#   chunks_failed   — chunks where read_memory failed (chunk filled with
#                     0xDEADBEEF to keep file at SIZE_BYTES)
#   failed_addrs    — list of addresses for failed chunks
#
# Caller is responsible for:
#   - Halting the target if required (e.g. enumerate.tcl's A53 release recipe)
#   - Selecting the right OpenOCD target (uscale.axi mem-AP)
#   - Writing the sidecar JSON metadata via write_dump_metadata


# Word-to-little-endian-bytes encode + write to an already-open binary fh.
proc _write_words_le {fh words} {
    foreach w $words {
        # `binary format i $w` emits 4 bytes little-endian (int32).
        # expr int() handles both decimal and 0x-prefixed hex inputs.
        if {[catch {expr {int($w)}} wi]} { set wi 0xDEADBEEF }
        puts -nonewline $fh [binary format i $wi]
    }
}


# Read SIZE_BYTES from ADDR, write to OUTPUT_PATH, return summary dict.
# CHUNK_WORDS controls how many 32-bit words per read_memory call. Smaller
# = more DAP round-trips but faster recovery from wedge; larger = fewer
# round-trips but more loss per failure. 256 (1 KB chunks) is a reasonable
# default for offline analysis.
proc dump_memory {addr size_bytes chunk_words output_path {label "memory"}} {
    set fh [open $output_path wb]
    fconfigure $fh -translation binary

    set chunk_bytes [expr {$chunk_words * 4}]
    set total_chunks [expr {($size_bytes + $chunk_bytes - 1) / $chunk_bytes}]
    set chunks_ok 0
    set chunks_failed 0
    set failed_addrs [list]
    set bytes_written 0
    set bytes_remaining $size_bytes

    say ""
    say "Dumping $label: [format 0x%08X $addr] for $size_bytes bytes"
    say "  chunk size = $chunk_words words ($chunk_bytes bytes)"
    say "  total chunks = $total_chunks"
    say ""

    set chunk_idx 0
    set cur_addr $addr
    set t_start [clock milliseconds]
    set t_chunk_slow_count 0    ;# how many chunks took >100ms (fabric pressure?)
    set t_max_chunk_ms 0
    while {$bytes_remaining > 0} {
        # How many words this chunk
        set wanted_bytes [expr {$bytes_remaining < $chunk_bytes ? $bytes_remaining : $chunk_bytes}]
        set wanted_words [expr {($wanted_bytes + 3) / 4}]

        set tc0 [clock milliseconds]
        if {[catch {read_memory $cur_addr 32 $wanted_words} words]} {
            # Read failed — fill with DEADBEEF so file stays at SIZE_BYTES,
            # clear DP sticky to recover for next chunk.
            set fill_words [list]
            for {set i 0} {$i < $wanted_words} {incr i} {
                lappend fill_words 0xDEADBEEF
            }
            _write_words_le $fh $fill_words
            catch { uscale.dap dpreg 0 0x1e } _
            after 5
            incr chunks_failed
            lappend failed_addrs [format 0x%08X $cur_addr]
            if {$chunks_failed <= 5} {
                say [format "  chunk %4d @ %08X: READ FAILED (filled with DEADBEEF)" $chunk_idx $cur_addr]
            } elseif {$chunks_failed == 6} {
                say "  ... (further per-chunk failure messages suppressed)"
            }
        } else {
            _write_words_le $fh $words
            incr chunks_ok
            set tc_ms [expr {[clock milliseconds] - $tc0}]
            if {$tc_ms > $t_max_chunk_ms} { set t_max_chunk_ms $tc_ms }
            if {$tc_ms > 100} { incr t_chunk_slow_count }
            # Heartbeat: every 16th chunk ALWAYS prints, so a slow-link dump (where every chunk is
            # >100ms — e.g. 1 MHz over a VM USB passthrough) isn't silent for minutes and mistaken
            # for a hang. The first few slow chunks also get a one-time "slow link" note.
            if {$tc_ms > 100 && $t_chunk_slow_count <= 3} {
                say [format "  chunk %4d/%d @ %08X: ok (%d ms - slow link; periodic updates follow)" \
                            $chunk_idx $total_chunks $cur_addr $tc_ms]
            } elseif {($chunk_idx % 16) == 0} {
                say [format "  chunk %4d/%d @ %08X: ok (%d words, %d ms)" \
                            $chunk_idx $total_chunks $cur_addr [llength $words] $tc_ms]
            }
        }

        set bytes_written [expr {$bytes_written + $wanted_bytes}]
        set bytes_remaining [expr {$bytes_remaining - $wanted_bytes}]
        set cur_addr [expr {$cur_addr + $wanted_bytes}]
        incr chunk_idx
    }

    close $fh
    set t_total_ms [expr {[clock milliseconds] - $t_start}]

    say ""
    say "Dump complete: $bytes_written bytes -> $output_path"
    say "  chunks ok:     $chunks_ok / $total_chunks"
    say "  chunks failed: $chunks_failed / $total_chunks"
    say "  wall-clock:    ${t_total_ms} ms (max chunk ${t_max_chunk_ms} ms; $t_chunk_slow_count chunks > 100 ms)"
    if {$chunks_failed > 0} {
        set head [join [lrange $failed_addrs 0 9] ", "]
        set tail_n [expr {[llength $failed_addrs] - 10}]
        set tail [expr {$tail_n > 0 ? " ... (and $tail_n more)" : ""}]
        say "  failed addrs:  ${head}${tail}"
    }

    return [dict create \
        bytes_written $bytes_written \
        chunks_total  $total_chunks \
        chunks_ok     $chunks_ok \
        chunks_failed $chunks_failed \
        failed_addrs  $failed_addrs \
        total_ms      $t_total_ms \
        max_chunk_ms  $t_max_chunk_ms \
        slow_chunks   $t_chunk_slow_count]
}


# Write a sidecar JSON file describing the dump.
#
# meta is a Tcl dict whose values are either scalar strings or LISTS.
# Tcl strings and lists are indistinguishable at the language level
# (everything is a string), so auto-detection by `llength` mis-classifies
# multi-word strings like "A53 did not halt" as 7-element arrays.
#
# Solution: caller passes `array_fields` — the list of keys whose values
# should be emitted as JSON arrays. Everything else becomes a JSON scalar
# (number, quoted hex string, or quoted string). An empty array_fields
# means every value is a scalar string.
#
# Backward-compat note: earlier callers relied on auto-detect. To preserve
# that, if array_fields is empty AND a value's llength > 1 AND every
# element parses as a number-or-hex token, we treat it as an array. This
# keeps csu_rom_digest (list of 12 "0x..." strings) working without
# requiring every existing caller to pass array_fields explicitly.

# Sparse skip-zeros dump — capture the FULL DRAM map when most of it is zero (the usual case for a
# running OS using a fraction of multi-GB DDR) WITHOUT paying JTAG read time for the zeros. Each
# PROBE_BLK is sampled at 4 points; an all-zero block is SKIPPED and left as a hole, so the output is
# a SPARSE file of the full SIZE — every byte's address is preserved for parsing, but the holes cost
# no JTAG time and no disk. A non-zero block is read fully in chunk_words bursts (errors -> 0xDEADBEEF).
# Trade-off: a block whose data sits entirely between the 4 sample windows is missed — shrink PROBE_BLK
# for denser probing. Returns occupancy stats.
proc dump_memory_sparse {addr size_bytes probe_blk chunk_words output_path {label "memory"}} {
    set fh [open $output_path wb]
    fconfigure $fh -translation binary
    if {$size_bytes > 0} { seek $fh [expr {$size_bytes - 1}] start ; puts -nonewline $fh "\x00" }  ;# sparse full size

    set dpname [expr {[info exists ::DAP_NAME] ? $::DAP_NAME : "uscale.dap"}]
    set chunk_bytes [expr {$chunk_words * 4}]
    set nblk [expr {($size_bytes + $probe_blk - 1) / $probe_blk}]
    set read_b 0 ; set skip_b 0 ; set fail_b 0 ; set kept 0 ; set skipped 0
    set t0 [clock milliseconds]

    say ""
    say "Sparse dump $label: [format 0x%08X $addr] for $size_bytes bytes (probe block [format 0x%X $probe_blk], $nblk blocks)"
    say "  reads only non-zero blocks; output is a sparse file of the full size (holes read as 0)"
    say ""

    for {set b 0} {$b < $nblk} {incr b} {
        set boff  [expr {$b * $probe_blk}]
        set baddr [expr {$addr + $boff}]
        set blen  [expr {($size_bytes - $boff) < $probe_blk ? ($size_bytes - $boff) : $probe_blk}]
        # probe 4 points x 32 words; non-zero if ANY sampled word is non-zero (a read error -> keep it)
        set nonzero 0
        for {set s 0} {$s < 4 && !$nonzero} {incr s} {
            set paddr [expr {$baddr + ($s * $blen / 4)}]
            if {[catch {read_memory $paddr 32 32} pw]} { set nonzero 1 ; catch { $dpname dpreg 0 0x1e } _ ; break }
            foreach w $pw { if {$w != 0} { set nonzero 1 ; break } }
        }
        if {!$nonzero} { incr skip_b $blen ; incr skipped ; continue }   ;# leave a hole

        incr kept
        seek $fh $boff start
        set o 0
        while {$o < $blen} {
            set wb [expr {($blen - $o) < $chunk_bytes ? ($blen - $o) : $chunk_bytes}]
            set ww [expr {($wb + 3) / 4}]
            if {[catch {read_memory [expr {$baddr + $o}] 32 $ww} words]} {
                set words [lrepeat $ww 0xDEADBEEF] ; incr fail_b $wb
                catch { $dpname dpreg 0 0x1e } _ ; after 5
            }
            _write_words_le $fh $words
            incr o $wb
        }
        incr read_b $blen
        set el [expr {([clock milliseconds] - $t0)/1000 + 1}]
        say [format "  kept %d/%d @ %08X (%d KB) | read %d MB skip %d MB | %d KB/s" \
                $b $nblk $baddr [expr {$blen/1024}] [expr {$read_b/0x100000}] [expr {$skip_b/0x100000}] [expr {($read_b/1024)/$el}]]
    }
    close $fh
    set t_total [expr {[clock milliseconds] - $t0}]
    say ""
    say "Sparse dump complete -> $output_path  ($size_bytes bytes, sparse)"
    say [format "  kept %d blocks (%d MB read), skipped %d blocks (%d MB zero), %d bytes read-failed" \
            $kept [expr {$read_b/0x100000}] $skipped [expr {$skip_b/0x100000}] $fail_b]
    say [format "  wall-clock %d s (~%d MB actually read; holes cost no time/disk)" [expr {$t_total/1000}] [expr {$read_b/0x100000}]]
    return [dict create bytes_total $size_bytes bytes_read $read_b bytes_skipped $skip_b \
            bytes_failed $fail_b blocks_kept $kept blocks_skipped $skipped total_ms $t_total]
}

proc write_dump_metadata {path meta {array_fields {}}} {
    set fh [open $path w]
    puts $fh "\{"
    set parts [list]
    dict for {k v} $meta {
        set ek "\"[_json_escape $k]\""
        set n [llength $v]
        if {$n == 0} {
            # empty list — JSON empty array
            lappend parts "  $ek: \[\]"
            continue
        }

        # Decide: array or scalar?
        set is_array 0
        if {[lsearch -exact $array_fields $k] >= 0} {
            set is_array 1
        } elseif {$n > 1} {
            # Auto-detect for back-compat: only treat as array if every
            # element is a numeric / hex token (no English words).
            set is_array 1
            foreach tok $v {
                if {![regexp {^-?[0-9]+$|^0[xX][0-9a-fA-F]+$} $tok]} {
                    set is_array 0
                    break
                }
            }
        }

        if {$is_array} {
            set arr [list]
            foreach item $v {
                lappend arr [_json_value $item]
            }
            lappend parts "  $ek: \[[join $arr {, }]\]"
        } else {
            # Scalar (single token or multi-word string).
            lappend parts "  $ek: [_json_value $v]"
        }
    }
    puts $fh [join $parts ",\n"]
    puts $fh "\}"
    close $fh
}


# Minimal JSON helpers (only used if json-emit.tcl isn't sourced).
proc _json_escape {s} {
    return [string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $s]
}
proc _json_value {v} {
    if {$v eq "true" || $v eq "false" || $v eq "null"} { return $v }
    if {[regexp {^-?[0-9]+$} $v]} { return $v }
    if {[regexp {^0[xX][0-9a-fA-F]+$} $v]} { return "\"$v\"" }
    return "\"[_json_escape $v]\""
}
