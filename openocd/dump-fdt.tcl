# Dump npMain FDT (~0x6000 bytes) from PA 0x10000 in small chunks (avoids bulk-read wedge).
catch { jtag arp_init } e
catch { uscale.a53.0 arp_examine } e
set FDT 0x00010000
set NW 0x1800   ;# 0x6000 bytes = 6144 words
set CH 64
echo "FDTDUMP-BEGIN"
for {set i 0} {$i < $NW} {set i [expr {$i + $CH}]} {
    set addr [expr {$FDT + $i*4}]
    if {[catch { set ws [uscale.axi read_memory $addr 32 $CH] } e]} {
        echo "ERR @ [format 0x%x $addr]: $e"
        break
    }
    echo "$i: $ws"
}
echo "FDTDUMP-END"
