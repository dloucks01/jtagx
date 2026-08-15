#!/usr/bin/env bash
# mock-secureboot-smoketest.sh — validates the secure-boot auth/key-bypass model against the published
# behaviour: JustSTART (CVE-2023-20570) boots a forged image on an RSA-only device and is mitigated by
# the AES-only fuse; Starbleed recovers the AES key on 7-series (AES-CBC oracle) but is N/A on
# UltraScale+ (AES-GCM). Pure/offline; no hardware.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL(mock-secureboot): $1"; exit 1; }
M="$PWD/tools/mock-secureboot.py"
python3 -m py_compile tools/mock-secureboot.py || fail "compile"
[ -x "$M" ] || chmod +x "$M"
# run the mock, capturing stdout AND the exit code without tripping `set -e`/pipefail
run() { set +e; OUT=$("$@" 2>&1); RC=$?; set -e; }

# 1. RSA-only device: unsigned boot rejected, JustSTART boots it
run "$M" boot --unsigned;   [ "$RC" -ne 0 ] || fail "unsigned boot should be REJECTED under RSA"
run "$M" juststart
echo "$OUT" | grep -q "JustSTART" || fail "JustSTART should reference CVE-2023-20570"
[ "$RC" -eq 0 ] || fail "JustSTART should exit 0 (boot) on an RSA-only device"

# 2. AES-only fuse mitigates JustSTART (the documented countermeasure)
run env MOCK_AESONLY=1 "$M" juststart
echo "$OUT" | grep -qi "mitigation" || fail "AES-only should mitigate JustSTART"
[ "$RC" -ne 0 ] || fail "JustSTART should FAIL when AES-only is enforced"

# 3. Starbleed recovers the AES key on 7-series, N/A on UltraScale+ (GCM)
K="0011223344556677889900aabbccddeeff00112233445566778899aabbccddee"
run env MOCK_FAMILY=zynq7000 MOCK_AESKEY=$K "$M" starbleed
echo "$OUT" | grep -q "$K" || fail "Starbleed should recover the boot AES key on a 7-series device"
run env MOCK_FAMILY=zynqmp "$M" starbleed
echo "$OUT" | grep -qi "AES-GCM" || fail "Starbleed should be N/A on UltraScale+ (AES-GCM)"

# 4. secure boot OFF → any image boots (the repack/reflash path)
run env MOCK_RSA=0 "$M" boot --unsigned
echo "$OUT" | grep -qi "secure boot OFF" || fail "no-secure-boot should let any image run"

echo "PASS: mock-secureboot (JustSTART bypass + AES-only mitigation + Starbleed key recovery + family logic)"
