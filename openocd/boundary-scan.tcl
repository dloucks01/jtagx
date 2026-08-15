# boundary-scan.tcl — capture the live boundary register (IEEE 1149.1 SAMPLE) in ONE command, then
# hand the hex to jtagx.bsdl for per-pin decoding. The DAP-gated fallback: even when the debug DAP is
# shut, the boundary-scan layer usually still answers, so you can read strap/mode/bus pin states.
#
# Non-destructive (SAMPLE only reads; it does NOT drive pins — that's EXTEST, deliberately not here).
#
# Driven by env vars emitted by `tools/bsdl-scan.py --capture-cmd` (from the part's BSDL):
#   BS_TAP     chain TAP name (e.g. msfabric.tap / auto.cpu)      [required]
#   BS_SAMPLE  SAMPLE instruction opcode, hex (e.g. 0x1)          [required]
#   BS_LEN     boundary-register length in bits                   [required]
#
#   BS_TAP=msfabric.tap BS_SAMPLE=0x1 BS_LEN=8 \
#     openocd -f <chain.cfg> -c "init; source openocd/boundary-scan.tcl; shutdown"
#
# Emits a machine-parseable line:  BOUNDARY_CAPTURE=0x<hex>   (fed back to bsdl --decode-output).

proc bs_env {name} {
    if {[info exists ::env($name)]} { return $::env($name) }
    return ""
}

set tap    [bs_env BS_TAP]
set sample [bs_env BS_SAMPLE]
set len    [bs_env BS_LEN]

if {$tap eq "" || $sample eq "" || $len eq ""} {
    puts "BOUNDARY_CAPTURE=ERR (need BS_TAP + BS_SAMPLE + BS_LEN; run tools/bsdl-scan.py --capture-cmd)"
    return
}

puts " boundary-scan SAMPLE capture: tap=$tap  SAMPLE=$sample  len=$len bits"
if {[catch {irscan $tap $sample} e]} {
    puts "BOUNDARY_CAPTURE=ERR (irscan failed: $e — wrong TAP name or chain not up)"
    return
}
if {[catch {drscan $tap $len 0} cap]} {
    puts "BOUNDARY_CAPTURE=ERR (drscan failed: $cap)"
    return
}
# OpenOCD returns the captured DR as a hex string (no 0x). Normalise.
set cap [string trim $cap]
puts "BOUNDARY_CAPTURE=0x$cap"
puts " decode with:  python3 tools/bsdl-scan.py <part.bsdl> --decode 0x$cap"
