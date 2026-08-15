#!/usr/bin/env bash
# happy-path-smoketest.sh — real subprocess invocations of the tools that had zero or near-zero
# coverage from the rest of the fast suite (found via tools/test-coverage-report.sh, 2026-08-15).
#
# cli-adversarial-smoketest.sh proves these tools fail CLEANLY on bad input; this file proves they
# actually WORK on good input — a gap of its own, since a tool can pass every adversarial check and
# still be broken on the one input it exists to handle. Every fixture here is either a small file
# already committed to the repo (tests/fixtures/, tests/golden/, payloads/) or synthesized inline —
# no live hardware, no vendor source tree, no gitignored dumps/ data.
set -uo pipefail
cd "$(dirname "$0")/.."

FAILS=0
fail() { echo "FAIL(happy-path): $1"; FAILS=$((FAILS+1)); }

HP="$(mktemp -d)"
trap 'rm -rf "$HP"' EXIT

run() { out=$("$@" 2>&1); rc=$?; }   # sets $out/$rc; never exits the script

# --- 1. first-contact.py — pure offline KB lookup, no fixture needed ---
run python3 tools/first-contact.py
[ "$rc" -eq 0 ] || fail "first-contact.py (no args): expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "stage:" <<<"$out" || fail "first-contact.py (no args): missing the stage-ordered tree"

run python3 tools/first-contact.py "flashpro won't work"
[ "$rc" -eq 0 ] || fail "first-contact.py (symptom): expected exit 0, got $rc"
grep -qi "proprietary-adapter" <<<"$out" || fail "first-contact.py (symptom): 'flashpro' should route to proprietary-adapter"

# --- 2. gen-board-cfg.py --from-discovery — real ZCU102 discovery-log fixture (also used by
#        board-runner-smoketest.sh's --from-log check) ---
run python3 tools/gen-board-cfg.py --from-discovery tests/fixtures/zcu102-firstcontact.log --out "$HP/gen.cfg"
[ "$rc" -eq 0 ] || fail "gen-board-cfg.py --from-discovery: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "zynqmp" "$HP/gen.cfg" 2>/dev/null || fail "gen-board-cfg.py --from-discovery: output cfg missing 'zynqmp'"

# --- 3/4/5. repack-bootimage.py / find-patch-target.py / qspi-make-patch.py — real (partial)
#            ZynqMP boot-image fixture already used by the parse-bootimage golden test ---
BOOTIMG=tests/golden/zcu102-bootimage/boot-partial-64k.bin
run python3 tools/repack-bootimage.py "$BOOTIMG" --inspect
[ "$rc" -eq 0 ] || fail "repack-bootimage.py --inspect: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "partitions)" <<<"$out" || fail "repack-bootimage.py --inspect: missing partition summary"

run python3 tools/find-patch-target.py "$BOOTIMG"
[ "$rc" -eq 0 ] || fail "find-patch-target.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "PATCH_VA=" <<<"$out" || fail "find-patch-target.py: missing the ready-to-run PATCH_VA line"

python3 tools/qspi-make-patch.py "$BOOTIMG" --offset 0x2800 --hex deadbeef -o "$HP/qpatch.tcl" >/dev/null 2>"$HP/qspi.err"
rc=$?
[ "$rc" -eq 0 ] || fail "qspi-make-patch.py: expected exit 0, got $rc: $(head -1 "$HP/qspi.err")"
grep -q "PHEX   deadbeef" "$HP/qpatch.tcl" 2>/dev/null || fail "qspi-make-patch.py: emitted Tcl missing the patch hex"

run python3 tools/bootrom-fuzz-gen.py "$BOOTIMG" -o "$HP/fuzz-corpus"
[ "$rc" -eq 0 ] || fail "bootrom-fuzz-gen.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
[ -f "$HP/fuzz-corpus/manifest.json" ] || fail "bootrom-fuzz-gen.py: manifest.json was not written"

run python3 tools/bootrom.py --stdout analyze "$BOOTIMG"
[ "$rc" -eq 0 ] || fail "bootrom.py analyze: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "Shannon entropy" <<<"$out" || fail "bootrom.py analyze: missing the entropy section"

# --- 6/7. symbolize.py / patch-recipe.py — a trivial synthetic symbol map ---
printf '0xffffffff80100000 vxAuthCheck\n' > "$HP/syms.txt"

run python3 tools/symbolize.py 0xffffffff80100000 --syms "$HP/syms.txt"
[ "$rc" -eq 0 ] || fail "symbolize.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "vxAuthCheck" <<<"$out" || fail "symbolize.py: exact-match VA did not resolve to its symbol"

run python3 tools/patch-recipe.py --arch aarch64 --func vxAuthCheck --syms "$HP/syms.txt" --behavior ret0
[ "$rc" -eq 0 ] || fail "patch-recipe.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "PATCH_HEX=" <<<"$out" || fail "patch-recipe.py: missing the ready-to-run PATCH_HEX line"

# --- 8. ghidra-loadspec.py — a real committed payload binary (known arch: AArch64/ARM) ---
run python3 tools/ghidra-loadspec.py payloads/hello.bin
[ "$rc" -eq 0 ] || fail "ghidra-loadspec.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "architecture (trial disassembly" <<<"$out" || fail "ghidra-loadspec.py: missing the architecture section"

# --- 9. bootrom-fuzz-triage.py — a synthetic FUZZ_FP log + manifest.json, including a JACKPOT row
#        (OCM change + CSU fault together) so the highest-interest branch is actually exercised ---
cat > "$HP/fuzz.log" <<'EOF'
FUZZ_FP id=0 CSU_STATUS=0x1 MULTIBOOT=0x0 FT_STATUS=0x0 BOOT_MODE=0x1 OCM_SUM=0xaaaa OCM_W0=0x1 OCM_W1=0x2 OCM_W2=0x3 OCM_W3=0x4 DAP=ok
FUZZ_FP id=1 CSU_STATUS=0x1 MULTIBOOT=0x1 FT_STATUS=0x0 BOOT_MODE=0x1 OCM_SUM=0xaaaa OCM_W0=0x1 OCM_W1=0x2 OCM_W2=0x3 OCM_W3=0x4 DAP=ok
FUZZ_FP id=2 CSU_STATUS=0x1 MULTIBOOT=0x0 FT_STATUS=0x9 BOOT_MODE=0x1 OCM_SUM=0xbbbb OCM_W0=0x9 OCM_W1=0x2 OCM_W2=0x3 OCM_W3=0x4 DAP=wedge
EOF
cat > "$HP/fuzz-manifest.json" <<'EOF'
[
  {"id": 1, "region": "IHT", "field": "partitionCount", "new": "0xff", "hyp": "overflow"},
  {"id": 2, "region": "PHT", "field": "totalDataWordLength", "new": "0xffffffff", "hyp": "OOB copy length"}
]
EOF
run python3 tools/bootrom-fuzz-triage.py "$HP/fuzz.log" "$HP/fuzz-manifest.json"
[ "$rc" -eq 0 ] || fail "bootrom-fuzz-triage.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "JACKPOT" <<<"$out" || fail "bootrom-fuzz-triage.py: OCM+FT_STATUS trial should trigger the JACKPOT verdict"

# --- 10. vxworks-symtab.py — a synthetic minimal symtab entry (namePtr/value pair + name string),
#         matching the documented VxWorks 7 AArch64 entry layout exactly ---
python3 -c "
import struct
va_base = 0xFFFFFFFF80100000
name_off = 0x20
name_va = va_base + name_off
value = va_base + 0x1000
buf = bytearray(64)
struct.pack_into('<QQ', buf, 0, name_va, value)
buf[name_off:name_off+len(b'myTestFunc')] = b'myTestFunc'
open('$HP/synvx.bin', 'wb').write(bytes(buf))
"
run python3 tools/vxworks-symtab.py "$HP/synvx.bin" --out-ghidra "$HP/synvx-ghidra.py" --out-map "$HP/synvx-map.txt"
[ "$rc" -eq 0 ] || fail "vxworks-symtab.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "myTestFunc" "$HP/synvx-map.txt" 2>/dev/null || fail "vxworks-symtab.py: synthesized entry was not extracted"

# --- 11. symbol-crypto.py — a synthetic dump with a REAL, valid AES-128 key schedule embedded
#         (standard Rijndael key expansion — same math tools/dram-secrets.py's find_aes_keys()
#         verifies), so this exercises the actual key-schedule validator, not just argv/file I/O ---
python3 -c "
_SBOX = bytes.fromhex(
 '637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0'
 'b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275'
 '09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf'
 'd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2'
 'cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb'
 'e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08'
 'ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e'
 'e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6428441992d0fb054bb16')
_T = bytes.maketrans(bytes(range(256)), _SBOX)
_RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d]
def expand_128(key):
    W = [key[i*4:i*4+4] for i in range(4)]
    for i in range(4, 44):
        t = W[i-1]
        if i % 4 == 0:
            sw = (t[1:]+t[:1]).translate(_T)
            t = bytes((sw[0]^_RCON[i//4-1], sw[1], sw[2], sw[3]))
        W.append(bytes(a^b for a,b in zip(W[i-4], t)))
    return b''.join(W)
sched = expand_128(bytes.fromhex('000102030405060708090a0b0c0d0e0f'))
buf = bytearray(1024)
buf[0x200:0x200+len(sched)] = sched
open('$HP/syn-dump.bin', 'wb').write(bytes(buf))
"
printf '0xFFFFFFFF80100200 wlanAesKey\n' > "$HP/syn-syms.txt"
run python3 tools/symbol-crypto.py "$HP/syn-dump.bin" --syms "$HP/syn-syms.txt"
[ "$rc" -eq 0 ] || fail "symbol-crypto.py: expected exit 0, got $rc: $(head -1 <<<"$out")"
grep -q "VALIDATED AES-128 KEY" <<<"$out" || fail "symbol-crypto.py: embedded real key schedule was not detected as VALIDATED"
grep -q "000102030405060708090a0b0c0d0e0f" <<<"$out" || fail "symbol-crypto.py: recovered key bytes don't match the embedded key"

if [ "$FAILS" -eq 0 ]; then
    echo "PASS: happy-path (13 tools exercised on real/synthetic good input, not just argv-error paths)"
    exit 0
else
    echo "FAIL: happy-path ($FAILS check(s) failed)"
    exit 1
fi
