# VxWorks 7 firmware analysis — ZCU102 engagement (2026-08-14)

Static + symbol-guided reverse engineering of the extracted OS, driven by capstone AArch64
disassembly + the recovered symbol map (no Ghidra GUI required).

**Sources:** `dumps/qspi-parts/part2_num0_NONE_kernel-or-app_load0x00100000.bin` (10.6 MB OS/app,
VA base `0xFFFFFFFF80100000`), `dumps/symbols.txt` (16,331 symbols), `dumps/os-live.bin` (16 MB live
DDR @ PA 0x100000). Method: `Cs(CS_ARCH_ARM64)` disasm + `bisect` nearest-symbol + BL/pointer xref scans.

---

## 1. Authentication — `ipcom_auth_login` @ `0xFFFFFFFF8023CE14`

Wind River IPCOM (network stack) login entry. Disassembly:
```
cbz  x0, +0x4c                 ; null ctx        -> error path
mov  w0, #-0x424               ; DEFAULT RETURN = -0x424 (IPCOM error code)
cbz  x1, +0x48                 ; null user       -> error
ldrb w9,[x9]; cbz w9, +0x48    ; empty user      -> error
ldrb w9,[x1]; cbz w9, +0x54    ; empty password  -> error
cbz  x2, +0x5c                 ; null pw buffer  -> error
... mov w2,#0xe4; mov x0,x8; mov w1,wzr   ; -> credential-check subcall
```
- **Return convention: `0` = success, negative (`-0x424` default) = failure.** This *confirms* the
  auth-bypass patch we applied is semantically correct: `mov w0,#0 ; ret` forces authenticated.
- **Dispatched via a registered callback table, not a direct call.** Zero `BL` xrefs across the image;
  the function pointer appears exactly once as data at **file `0x971328`** inside an IPCOM auth-method
  registration struct: `{ 0x…809379cf, ipcom_auth_login, 0, 0x00050000, 0 }`. Because dispatch is
  indirect, patching the **function body** (Cap-2 live-patch / Cap-3 repack, both already done) defeats
  auth regardless — no need to find/patch the call site.

## 2. Application crypto — the `OE_` / `coe` message layer

A custom message-encryption layer (`OE_Message_Encrypt/Decrypt`, `OE_Encryptor_Create/Delete`,
`OE_Endpoint_Auto_Decrypt`; C++ `coeMessage`/`coeEndpoint`/`coeEncryptor`).

- **`0xBEEFFACE` is the OE-message struct magic, NOT a key.** `OE_Message_Decrypt` loads `[x0]`, builds
  `w9 = 0xBEEFFACE` (`mov #0xface ; movk #0xbeef,lsl#16`), `cmp`/`b.ne` → bail (`ret 0x21`) on mismatch.
  The "is-encrypted" gate is **bit 9** of the flags word at `struct+0x10` (`tbnz w8,#9`).
- **No hardcoded key.** `OE_Encryptor_Create` builds the encryptor from a **caller-supplied config
  object** (`ldr w8,[x0]` size; `add x0,x8,#0x38; bl OE_Allocate`), storing the config/callback at
  `[obj+8]`. This matches `symbol-crypto`'s result (0 static AES keys in the image): **the key is
  runtime-provided**, not baked in.
- **No live OE contexts in the captured DRAM.** Scanning `os-live.bin` for `0xBEEFFACE` → 0 hits, i.e.
  no OE messages were in flight in the 16 MB kernel-region window. Recovering the runtime key requires
  either a **wider DDR dump** (the app heap, beyond 0x1100000) or a **`break-capture` on
  `OE_Encryptor_Create`** to catch the config pointer / key in registers (`BC_ADDR=0xFFFFFFFF80130BF0`,
  deref the config arg).

## 3. Credentials (recap, from `dram-secrets`)

Hardcoded in both firmware and RAM: **`u=target/pw=vxTarget`** and **`u=ultraNP/pw=ultraNP`** (with net
config `192.168.1.10/.20`). Persistent — anyone dumping QSPI gets them.

---

## Exploitation summary
- **Auth bypass:** `ret0` on `ipcom_auth_login` — live (Cap-2, proven on silicon) and persistent
  (Cap-3 `boot-patched.bin`, checksums valid). Semantics now confirmed by disassembly.
- **Comms crypto:** custom OE layer, runtime key (not extractable statically). Next step to break it is
  a targeted `break-capture` on `OE_Encryptor_Create` or a heap-range DDR dump.
- **Services present:** `TELNETD`, `RLOGIN`, `shellLogin` — the network login surface the auth bypass
  and hardcoded creds apply to.

## Breaking the OE crypto — live key capture (break-capture recipe)

The OE key is runtime-provided (no static key in the image), so recover it by catching it **in flight**:
a HW breakpoint on the encryptor constructor + dereferencing its config argument over the AXI mem-AP.

```bash
# break on OE_Encryptor_Create; dump x0-x30 + deref the pointer args (the config holds the key material)
BC_ADDR=0xFFFFFFFF80130BF0 BC_DEREF="0 1 2 3" BC_DEREF_LEN=128 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/break-capture.tcl; shutdown"

# (alt) catch a message being decrypted — x0 = the OE message after the 0xBEEFFACE magic check:
BC_ADDR=0xFFFFFFFF8012DD04 BC_DEREF="0" BC_DEREF_LEN=128 \
  openocd -f openocd/zcu102.cfg -c "init; source openocd/break-capture.tcl; shutdown"
```

- `BC_KVA_LO` defaults to `0x80000000` — correct for this VxWorks linear map (`PA = (VA & 0xFFFFFFFF)
  − 0x80000000`), the same mapping the live-patch used.
- **Extract the key:** save the `x0` config deref to a file, then
  `python3 tools/oe-key-extract.py oe-config.bin` — it detects a stored AES key **schedule** and
  RECOVERS the key (AES-128/192/256, FIPS-197-validated), or flags high-entropy key candidates to verify.
- **Operational trigger:** `OE_Encryptor_Create` only runs when the app establishes an OE-crypto session
  (e.g. a network connection using the coe/OE layer). Exercise that service to make the breakpoint fire —
  on an idle system it won't, which is why the static DDR scan found 0 live OE contexts.
