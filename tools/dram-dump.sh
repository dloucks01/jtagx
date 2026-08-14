#!/usr/bin/env bash
# Resilient SPARSE DRAM dump for the ZCU102 over JTAG.
#
# WHY: dump-os-ddr.tcl with DUMP_SPARSE=1 captures the full RAM map while skipping the zeros, but a
# multi-hour capture over the VMware-passthrough FTDI wedges partway (LIBUSB_ERROR / MPSSE flush). This
# driver splits the address range into CHUNKs, USB-resets the FTDI before each chunk (fresh MPSSE
# state), retries a wedged chunk, and assembles a sparse full-range image — so you can "capture
# everything" despite the flaky link. Each chunk runs sparse internally (probe -> read only non-zero).
#
# Usage:  tools/dram-dump.sh [ADDR] [SIZE] [OUT]
#   ADDR        start address          (default 0x0 = base of DDR)
#   SIZE        bytes to cover          (default 0x80000000 = 2 GB; use 0x100000000 for the high 2 GB too)
#   OUT         output file             (default dumps/ddr-full.bin) — sparse, full SIZE apparent
#   DRAM_CHUNK  address range / openocd run (default 0x4000000 = 64 MB; MUST be a multiple of 1 MB).
#               Smaller = more resilient + more per-chunk overhead. A data-heavy chunk is slow; if one
#               keeps wedging, lower this so each run is shorter than the link's wedge time.
#   DUMP_HALT=1        freeze cores for a consistent snapshot (passed through; resumed after)
#   DUMP_PROBE_BLK     sparse probe granularity (passed through; default 0x100000)
#   DRAM_CFG           openocd cfg (default openocd/zcu102.cfg)
#
# Then parse it down:  python3 tools/dram-secrets.py OUT -o reports/dram-secrets.md
set -euo pipefail
cd "$(dirname "$0")/.."

ADDR=$(( ${1:-0x0} ))
SIZE=$(( ${2:-0x80000000} ))
OUT=${3:-dumps/ddr-full.bin}
CHUNK=$(( ${DRAM_CHUNK:-0x4000000} ))
CFG=${DRAM_CFG:-openocd/zcu102.cfg}
MB=1048576
(( CHUNK % MB == 0 )) || { echo "DRAM_CHUNK must be a multiple of 1 MB"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"

usb_reset() {  # reset the wedged JTAG adapter without a physical re-plug.
  # Default: any FTDI (VID 0403). Override for a non-default adapter: JTAG_USB=VID:PID. Non-FTDI
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
        elif vid!='0403':
            continue
        b=int(open(s+'/busnum').read()); d=int(open(s+'/devnum').read())
        fd=os.open(f'/dev/bus/usb/{b:03d}/{d:03d}',os.O_WRONLY); fcntl.ioctl(fd,ord('U')<<8|20,0); os.close(fd)
    except Exception: pass
PY
  sleep 3
}

printf 'Resilient sparse DRAM dump: 0x%X..0x%X (%d MB) -> %s  [chunk 0x%X, halt=%s]\n' \
  "$ADDR" "$((ADDR+SIZE))" "$((SIZE/MB))" "$OUT" "$CHUNK" "${DUMP_HALT:-0}"
truncate -s "$SIZE" "$OUT"          # pre-create the sparse full-size output (all holes)
off=0
while (( off < SIZE )); do
  sz=$CHUNK; (( off + sz > SIZE )) && sz=$(( SIZE - off ))
  cf="$TMP/c_$(printf '%010x' "$off").bin"
  ok=0
  for try in 1 2 3; do
    pkill -9 -x openocd 2>/dev/null || true
    usb_reset
    printf '  chunk @0x%09X size 0x%X  (try %d) ... ' "$((ADDR+off))" "$sz" "$try"
    rm -f "$cf"
    if timeout 7200 env DUMP_ADDR=$((ADDR+off)) DUMP_SIZE="$sz" DUMP_SPARSE=1 DUMP_OUT="$cf" \
         ${DUMP_HALT:+DUMP_HALT="$DUMP_HALT"} ${DUMP_PROBE_BLK:+DUMP_PROBE_BLK="$DUMP_PROBE_BLK"} \
         openocd -f "$CFG" -c "init; source openocd/dump-os-ddr.tcl; shutdown" >"$TMP/log" 2>&1 \
       && [[ -f "$cf" ]] && (( $(stat -c%s "$cf") == sz )); then
      kept=$(grep -oE 'kept [0-9]+ blocks \([0-9]+ MB read\)' "$TMP/log" | tail -1)
      # place the chunk at its offset in the final file, keeping zero blocks as holes (conv=sparse)
      dd if="$cf" of="$OUT" bs=1M seek=$(( off / MB )) conv=notrunc,sparse status=none
      printf 'OK (%s)\n' "${kept:-done}"
      ok=1; break
    fi
    echo "WEDGED/short — retrying"
  done
  if (( ! ok )); then echo "  ABORT: chunk @0x$(printf '%X' $((ADDR+off))) failed 3x. Partial image in $OUT."; exit 1; fi
  off=$(( off + sz ))
done
printf 'DONE: %s — %d bytes apparent, ~%s on disk (only used RAM)\n' \
  "$OUT" "$(stat -c%s "$OUT")" "$(du -h "$OUT" | cut -f1)"
echo "Next: python3 tools/dram-secrets.py $OUT -o reports/dram-secrets.md"
