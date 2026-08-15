#!/usr/bin/env python3
"""
mock-secureboot.py — a HIGH-FIDELITY model of the Zynq/ZynqMP secure-boot authentication + bitstream
encryption state machine and the PUBLISHED bypasses, so the "boot a forged image / recover the key"
side of an engagement is rehearsable offline (the debug-lock unlock is mock-openocd; this is the
auth/key layer). Grounded in the real research:

  * JustSTART (CVE-2023-20570) — RSA authentication is bypassed by loading the signed bitstream but
    inserting "just start" commands so it boots WITHOUT running auth. Mitigated ONLY by enforcing AES
    bitstream encryption (the device won't decrypt an attacking bitstream).      [TCHES 2024, arXiv 2402.09845]
  * Starbleed — a full break of the 7-series AES-CBC bitstream encryption: turn the config engine into
    a decryption ORACLE by rerouting decrypted words to the WBSTAR register and reading them back after
    reset (CBC malleability). Unpatchable in silicon.                            [Ender et al., USENIX Security 2020]
  * UltraScale(+) uses AES-GCM; the "Cautionary Note" IV/GHASH issues make it harder but not immune.  [Cautionary Note, HOST 2022]

Device security posture via env (defaults model the JustSTART-vulnerable config):
  MOCK_FAMILY=zynqmp|zynq7000   MOCK_RSA=1|0 (RSA auth enforced)   MOCK_AESONLY=1|0 (AES-only fuse)
  MOCK_AESKEY=<hex>  (the BBRAM/eFuse boot key the bypasses recover)
Commands:
  status                       — print the device security posture
  boot   --signed|--unsigned [--encrypted] [--juststart]   — model the BootROM auth+decrypt decision
  juststart                    — attempt the CVE-2023-20570 RSA-auth bypass
  starbleed                    — run the 7-series decryption oracle → recover the AES key + plaintext
  glitch                       — fault-inject the auth decision (force-accept; probabilistic)
REHEARSAL model — grounded in published findings, not silicon. Real validation is a bench + a glitch rig.
"""
import os
import sys

FAMILY = os.environ.get("MOCK_FAMILY", "zynqmp")
RSA = os.environ.get("MOCK_RSA", "1") == "1"          # RSA auth enforced (secure boot on)
AESONLY = os.environ.get("MOCK_AESONLY", "0") == "1"  # AES-only fuse (encryption enforced)
AESKEY = os.environ.get("MOCK_AESKEY", "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")


def status():
    print(f"device: {FAMILY}")
    print(f"  RSA authentication enforced : {RSA}")
    print(f"  AES-only (encryption) fuse  : {AESONLY}")
    print(f"  boot AES key (BBRAM/eFuse)  : {'<sealed>' if RSA or AESONLY else AESKEY}")
    print(f"  posture: " + ("hardened (RSA+AES)" if RSA and AESONLY else
                            "RSA-auth only  ← JustSTART-vulnerable" if RSA and not AESONLY else
                            "AES-only" if AESONLY else "OPEN (no secure boot)"))


def boot(signed, encrypted, juststart):
    # BootROM decision, modelling the real auth+decrypt order and the JustSTART mitigation.
    if AESONLY and not encrypted:
        print("REJECT: AES-only fuse set — BootROM will not process an unencrypted image "
              "(this is exactly the JustSTART mitigation)."); return 1
    if RSA:
        if signed:
            print("BOOT: RSA signature valid (PPK/SPK chain OK) → FSBL runs."); return 0
        if juststart and not AESONLY:
            print("BOOT: *** JustSTART (CVE-2023-20570) *** — 'just start' commands ran the config "
                  "engine WITHOUT RSA auth. Forged/unsigned image booted. Unpatchable in silicon."); return 0
        print("REJECT: RSA enforced and signature invalid (no bypass applied)."); return 1
    print("BOOT: secure boot OFF — any image runs (repack a trojanized BOOT.bin and reflash)."); return 0


def juststart():
    print("[JustSTART / CVE-2023-20570] load the (signed) bitstream, insert 'just start' config commands…")
    return boot(signed=False, encrypted=False, juststart=True)


def starbleed():
    if FAMILY != "zynq7000":
        print("N/A: Starbleed is the 7-series AES-CBC oracle. UltraScale(+) uses AES-GCM — see the "
              "Cautionary-Note IV/GHASH issues (harder, not a turnkey oracle). Set MOCK_FAMILY=zynq7000.")
        return 1
    print("[Starbleed] config engine as a decryption oracle: reroute decrypted words → WBSTAR, reset, read back…")
    print(f"  recovered boot AES key: {AESKEY}")
    print("  → decrypted bitstream/plaintext recoverable word-by-word (CBC malleability). Unpatchable.")
    return 0


def glitch():
    print("[Fault injection] EM/voltage glitch on the CSU RSA/HMAC authenticate branch…")
    print("  force-accept of an unsigned image (checkm8-model). Probabilistic — needs a glitch rig + trigger.")
    print("  if it lands: unsigned FSBL runs. If AES-only is set, you still need the key (see starbleed).")
    return 0


def main():
    argv = sys.argv[1:]
    cmd = argv[0] if argv else "status"
    if cmd == "status":
        status(); return
    if cmd == "boot":
        rc = boot(signed=("--signed" in argv), encrypted=("--encrypted" in argv),
                  juststart=("--juststart" in argv))
    elif cmd == "juststart":
        rc = juststart()
    elif cmd == "starbleed":
        rc = starbleed()
    elif cmd == "glitch":
        rc = glitch()
    else:
        print(f"unknown command {cmd}; try: status|boot|juststart|starbleed|glitch"); rc = 2
    sys.exit(rc)


if __name__ == "__main__":
    main()
