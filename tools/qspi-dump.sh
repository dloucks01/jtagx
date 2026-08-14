#!/usr/bin/env bash
# Resilient full-flash DMA dump for the ZCU102 over JTAG.
#
# WHY: openocd/qspi-jtag.tcl QSPI_OP=dmadump is byte-exact and fast (~9 KB/s vs ~1 KB/s PIO), but the
# FTDI adapter (Digilent 0403:6014) wedges under sustained DMA traffic through VMware USB passthrough
# (LIBUSB_ERROR / "error while flushing MPSSE queue"). A single 20-min dump usually dies partway. This
# driver dumps in fixed CHUNKs, USB-resets the FTDI before each chunk (fresh MPSSE state), retries a
# wedged chunk, and concatenates -> a complete dump despite the flaky link.
#
# Usage:  tools/qspi-dump.sh [TOTAL_SIZE] [OUT]
#   TOTAL_SIZE  total bytes to dump   (default 0xB00000 = 11 MB, covers the ~9 MB boot image + tail)
#   OUT         output file           (default dumps/boot-image-full.bin)
#   QSPI_CHUNK  bytes per chunk        (default 0x100000 = 1 MB; smaller = more resilient, more overhead)
#
# Each chunk is a separate openocd invocation (fresh FTDI state). Concatenation is in offset order.
set -euo pipefail
cd "$(dirname "$0")/.."

TOTAL=$(( ${1:-0xB00000} ))
OUT=${2:-dumps/boot-image-full.bin}
CHUNK=$(( ${QSPI_CHUNK:-0x100000} ))
CFG=${QSPI_CFG:-openocd/zcu102.cfg}
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$(dirname "$OUT")"

usb_reset() {  # reset the wedged JTAG adapter without a physical re-plug.
  # Default: any FTDI (VID 0403 — Digilent SMT2, FT2232H/FT4232H/FT232H — the MPSSE-wedge-prone family).
  # Override for a non-default adapter:  JTAG_USB=VID:PID  (e.g. 1366:0105 for some J-Links). Non-FTDI
  # adapters generally don't need this; if none match, it's a harmless no-op.
  JTAG_USB="${JTAG_USB:-}" python3 - <<'PY' 2>/dev/null || true
import os,fcntl,glob
want=os.environ.get('JTAG_USB','').lower()
vw,pw=((want.split(':')+[''])[:2]) if want else ('','')
for s in glob.glob('/sys/bus/usb/devices/*'):
    try:
        vid=open(s+'/idVendor').read().strip().lower(); pid=open(s+'/idProduct').read().strip().lower()
        if want:
            if vid!=vw or (pw and pid!=pw): continue
        elif vid!='0403':                       # default: any FTDI
            continue
        b=int(open(s+'/busnum').read()); d=int(open(s+'/devnum').read())
        fd=os.open(f'/dev/bus/usb/{b:03d}/{d:03d}',os.O_WRONLY); fcntl.ioctl(fd,ord('U')<<8|20,0); os.close(fd)
    except Exception: pass
PY
  sleep 3
}

printf 'Resilient QSPI dump: %d bytes (0x%X) -> %s  [chunk 0x%X]\n' "$TOTAL" "$TOTAL" "$OUT" "$CHUNK"
: > "$OUT"
off=0
while (( off < TOTAL )); do
  sz=$CHUNK; (( off + sz > TOTAL )) && sz=$(( TOTAL - off ))
  cf="$TMPDIR/chunk_$(printf '%08x' "$off").bin"
  ok=0
  for try in 1 2 3; do
    pkill -9 -x openocd 2>/dev/null || true
    usb_reset
    printf '  chunk @0x%06X size 0x%X  (try %d) ... ' "$off" "$sz" "$try"
    rm -f "$cf"
    if timeout 600 env QSPI_OP=dmadump QSPI_OFFSET="$off" QSPI_SIZE="$sz" QSPI_OUT="$cf" \
         openocd -f "$CFG" -c "init; source openocd/qspi-jtag.tcl; shutdown" >"$TMPDIR/log" 2>&1 \
       && [[ -s "$cf" ]] && (( $(stat -c%s "$cf") >= sz )); then
      kbps=$(grep -oE '[0-9]+ KB/s' "$TMPDIR/log" | tail -1)
      unc=$(grep -oE '[0-9]+ uncovered' "$TMPDIR/log" | tail -1)
      printf 'OK (%s, %s)\n' "${kbps:-?}" "${unc:-0 uncovered}"
      ok=1; break
    fi
    echo "WEDGED/short — retrying"
  done
  if (( ! ok )); then echo "  ABORT: chunk @0x$(printf %X $off) failed 3x. Partial dump in $OUT."; exit 1; fi
  head -c "$sz" "$cf" >> "$OUT"      # trim any block-rounding overshoot, append in order
  off=$(( off + sz ))
done
printf 'DONE: %s (%d bytes, md5 %s)\n' "$OUT" "$(stat -c%s "$OUT")" "$(md5sum "$OUT" | cut -d' ' -f1)"
echo "Next: python3 tools/parse-bootimage.py $OUT   # shows where the real image ends"
