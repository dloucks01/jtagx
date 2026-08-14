#!/usr/bin/env bash
# build-vxboot-smoketest.sh — verify build-vxboot/build_vxworks_zcu102.py still reproduces
# the three validated VxWorks boot images byte-for-byte:
#     --no-net  SD   == vxworks-BOOT-v5p.bin   (md5 8d2ebc69, pre-networking)
#     (default) QSPI == vxworks-BOOT-v5pg3.bin (md5 2f46c263, networking)
#     (default) SD   == v5pg                   (md5 cd4466…,  networking)
#
# Offline-safe: SKIPs cleanly (exit 0) if the build prerequisites aren't present, so the
# main smoketest stays green on a fresh checkout / in CI. dtc is auto-provisioned from the
# repo's kept device-tree-compiler*.deb; mkbootimage must be built once (see docs/17 +
# memory reference_vxworks_build_toolchain) — if it's missing the test just skips.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BV="$ROOT/build-vxboot"
DTC=/tmp/dtcroot/usr/bin/dtc
MKBOOT=/tmp/zynq-mkbootimage/mkbootimage
V5P="$BV/vxworks-BOOT-v5p.bin"
V5PG3="$BV/vxworks-BOOT-v5pg3.bin"
V5PG_MD5=cd4466564f4703dce1d1e47d9188a5cc          # default-mode SD image (no reference file kept)

skip(){ echo "SKIP: build-vxboot reproduce — $1"; exit 0; }
fail(){ echo "FAIL: build-vxboot reproduce — $1"; exit 1; }

# --- inputs + reference images must exist -----------------------------------------------
for f in "$BV/build_vxworks_zcu102.py" "$BV/bl31.elf" "$BV/sd-staging/BOOT.petalinux.bin" \
         "$ROOT/dumps/sd-extract/vxWorks.bin" "$V5P" "$V5PG3"; do
    [ -f "$f" ] || skip "missing $f"
done

# --- dtc: auto-extract from the kept .deb (offline) -------------------------------------
if [ ! -x "$DTC" ]; then
    DEB=$(ls "$ROOT"/device-tree-compiler*.deb 2>/dev/null | head -1)
    [ -n "$DEB" ] && dpkg-deb -x "$DEB" /tmp/dtcroot 2>/dev/null
fi
[ -x "$DTC" ] || skip "dtc unavailable (extract device-tree-compiler*.deb -> /tmp/dtcroot)"

# --- mkbootimage: can't build offline -> skip if absent ---------------------------------
[ -x "$MKBOOT" ] || skip "mkbootimage not built (see docs/17 / reference_vxworks_build_toolchain)"

# --- clean up every regenerated artifact on exit (keep the tree tidy) -------------------
cleanup(){ rm -f "$BV"/vxworks-BOOT-sd.bin "$BV"/vxworks-BOOT-qspi.bin "$BV"/vxworks-sd.bin \
    "$BV"/vxworks-qspi.bin "$BV"/vxworks.elf "$BV"/fsbl.bin "$BV"/fsbl.elf "$BV"/pmufw.bin \
    "$BV"/pmufw.elf "$BV"/vx.bif 2>/dev/null; }
trap cleanup EXIT

# --- 1. --no-net -> v5p -----------------------------------------------------------------
python3 "$BV/build_vxworks_zcu102.py" --no-net >/tmp/bv-nonet.log 2>&1 \
    || { cat /tmp/bv-nonet.log; fail "--no-net build errored"; }
cmp -s "$BV/vxworks-BOOT-sd.bin" "$V5P" || fail "--no-net SD != v5p (8d2ebc69)"
echo "  --no-net  SD   == v5p   (8d2ebc69)"

# --- 2. default -> v5pg (SD) + v5pg3 (QSPI) ---------------------------------------------
python3 "$BV/build_vxworks_zcu102.py" >/tmp/bv-default.log 2>&1 \
    || { cat /tmp/bv-default.log; fail "default build errored"; }
cmp -s "$BV/vxworks-BOOT-qspi.bin" "$V5PG3" || fail "default QSPI != v5pg3 (2f46c263)"
echo "  default   QSPI == v5pg3 (2f46c263)"
GOT_SD=$(md5sum "$BV/vxworks-BOOT-sd.bin" | cut -d' ' -f1)
[ "$GOT_SD" = "$V5PG_MD5" ] || fail "default SD md5 $GOT_SD != v5pg ($V5PG_MD5)"
echo "  default   SD   == v5pg  (cd4466…)"

echo "PASS: build-vxboot reproduces all three validated images byte-for-byte"
