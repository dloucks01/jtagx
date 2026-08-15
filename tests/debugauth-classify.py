#!/usr/bin/env python3
"""
debugauth-classify.py — unit test for jtagx/debugauth.py (Phase 2 §2.2/2.5).

Covers the cross-arch classifier (Armv8-A / Cortex-M / RISC-V) across all five
verdicts (OPEN/GATED/AUTHENTICATED/LOCKED/NONE) and the DBGAUTHSTATUS/EDPRSR
decoders. Offline.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from jtagx import debugauth as da  # noqa: E402


def _fail(m):
    print(f"FAIL(debugauth-classify): {m}")
    sys.exit(1)


def _eq(got, want, ctx):
    if got != want:
        _fail(f"{ctx}: got {got!r}, want {want!r}")


# --- decoders ---
d = da.decode_dbgauthstatus(0xFF)
_eq(d["SID"], "ENABLED", "0xFF SID"); _eq(d["NSID"], "ENABLED", "0xFF NSID")
d = da.decode_dbgauthstatus(0x0F)                       # NS enabled, secure not-impl
_eq(d["NSID"], "ENABLED", "0x0F NSID"); _eq(d["SID"], "not-impl", "0x0F SID")
d = da.decode_dbgauthstatus(0xAF)                       # secure 0b10 = disabled
_eq(d["SID"], "disabled", "0xAF SID")

e = da.decode_edprsr(0x01)
_eq(e["powered"], True, "EDPRSR PU"); _eq(e["ext_dbg_disabled"], False, "EDPRSR EDAD")
e = da.decode_edprsr(0x80 | 0x40)                       # EDAD + DLK
_eq(e["ext_dbg_disabled"], True, "EDPRSR EDAD set"); _eq(e["double_locked"], True, "EDPRSR DLK set")

# --- Armv8-A ---
_eq(da.classify("armv8a", {"dbgauthstatus": 0xFF})["verdict"], da.OPEN, "A: all-enabled")
r = da.classify("zynqmp", {"dbgauthstatus": 0xFF}); _eq(r["secure_debug"], True, "A: secure open flag")
_eq(da.classify("armv8a", {"dbgauthstatus": 0x0F})["verdict"], da.OPEN, "A: NS-open secure-gated")
_eq(da.classify("armv8a", {"dbgauthstatus": 0x0F})["secure_debug"], False, "A: NS-open secure flag false")
_eq(da.classify("armv8a", {"dbgauthstatus": 0xAA})["verdict"], da.GATED, "A: all signals disabled → gated")
# EDPRSR gates take precedence
_eq(da.classify("armv8a", {"dbgauthstatus": 0xFF, "edprsr": 0x40})["verdict"], da.LOCKED, "A: double-lock → LOCKED")
_eq(da.classify("armv8a", {"dbgauthstatus": 0xFF, "edprsr": 0x80})["verdict"], da.GATED, "A: EDAD → GATED")
# authenticated-debug frontier
_eq(da.classify("armv8a", {"auth_debug": "provisioned"})["verdict"], da.AUTHENTICATED, "A: cert provisioned")
_eq(da.classify("armv8a", {"auth_debug": "present"})["verdict"], da.GATED, "A: cert present-not-provisioned")

# --- Cortex-M ---
_eq(da.classify("cortex-m", {"lock": "none"})["verdict"], da.OPEN, "M: unlocked")
r = da.classify("cortex-m", {"lock": "engaged", "lever": "nrf52_recover ERASEALL"})
_eq(r["verdict"], da.GATED, "M: locked → gated")
if "nrf52_recover ERASEALL" not in r["reopen_levers"]:
    _fail("M: lever should propagate into reopen_levers")
_eq(da.classify("cortex-m", {"lock": "permalock"})["verdict"], da.LOCKED, "M: RDP2 → LOCKED")
_eq(da.classify("cortexm", {"dauthstatus": "provisioned"})["verdict"], da.AUTHENTICATED, "M: SDC-600 provisioned")

# --- RISC-V ---
_eq(da.classify("riscv", {"authenticated": True})["verdict"], da.OPEN, "R: authed open")
_eq(da.classify("riscv", {"authenticated": None})["verdict"], da.OPEN, "R: DM present no-auth open")
_eq(da.classify("risc-v", {"authenticated": False})["verdict"], da.AUTHENTICATED, "R: auth required")

# --- unknown arch / empty ---
_eq(da.classify("mips", {})["verdict"], da.NONE, "unknown arch → NONE")
_eq(da.classify("armv8a", {})["verdict"], da.NONE, "no signals → NONE")

# --- reopenable flag semantics ---
if not da.classify("armv8a", {"dbgauthstatus": 0xFF})["reopenable"]:
    _fail("OPEN should be reopenable")
if da.classify("cortex-m", {"lock": "permalock"})["reopenable"]:
    _fail("LOCKED must not be reopenable")

print("PASS: debugauth-classify (armv8a/cortex-m/riscv × OPEN/GATED/AUTHENTICATED/LOCKED/NONE + decoders)")
