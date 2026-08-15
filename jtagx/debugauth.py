"""
debugauth.py — cross-architecture debug-authentication model.

Collapses the per-architecture debug-gate signals into ONE classification that
the rest of the toolkit (weakness layer, attack graph, reports) can reason over:

    OPEN           debug available, no gate in the way
    GATED          on/off gate, re-openable with a lever (mass-erase, RDP
                   downgrade, a register write) — the Phase-2b unlock surface
    AUTHENTICATED  challenge-response gate (Arm SDC-600 / debug certificate,
                   RISC-V External Debug Security) — needs a key/cert, not a lever
    LOCKED         closed with no known lever (eFuse permadisable, sealed)
    NONE           no debug interface, or not determinable from the given signals

The point of the AUTHENTICATED tier is to keep the detector ahead of hardening:
a part that has moved from "on/off debug" to "certificate-authenticated debug"
is a different engagement than one that is simply locked, and a part that is
*capable of* authenticated debug but has no certificate provisioned is the same
opt-in failure mode as an unprovisioned FlashLock.

Signal decoders (decode_dbgauthstatus / decode_edprsr) are the canonical Armv8
external-debug decoders; kept here so any consumer gets the same interpretation.

Spec basis: Arm DDI0487 (DBGAUTHSTATUS_EL1, EDPRSR), Arm SDC-600 (IHI0076),
RISC-V External Debug Support 0.13/1.0 (DMSTATUS), plus vendor RM lock bits.
"""
from __future__ import annotations

OPEN = "OPEN"
GATED = "GATED"
AUTHENTICATED = "AUTHENTICATED"
LOCKED = "LOCKED"
NONE = "NONE"

# 2-bit debug-auth field encoding (DBGAUTHSTATUS / DAUTHSTATUS).
_AUTH2 = {0b00: "not-impl", 0b10: "disabled", 0b11: "ENABLED"}


def decode_dbgauthstatus(v: int) -> dict:
    """Armv8-A DBGAUTHSTATUS_EL1 → the four debug-auth signal states.

    NSID[1:0]=DBGEN, NSNID[3:2]=NIDEN, SID[5:4]=SPIDEN, SNID[7:6]=SPNIDEN.
    Each 2-bit: 0b00 not-impl, 0b10 impl+disabled, 0b11 impl+enabled.
    """
    return {
        "NSID": _AUTH2.get(v & 0x3, "?"),          # non-secure invasive  (DBGEN)
        "NSNID": _AUTH2.get((v >> 2) & 0x3, "?"),  # non-secure trace     (NIDEN)
        "SID": _AUTH2.get((v >> 4) & 0x3, "?"),    # secure invasive      (SPIDEN)
        "SNID": _AUTH2.get((v >> 6) & 0x3, "?"),   # secure trace         (SPNIDEN)
    }


def decode_edprsr(v: int) -> dict:
    """Armv8-A EDPRSR (external debug processor status) → the status bits that
    say whether a core is even debuggable right now (DDI0487 layout)."""
    return {
        "powered": bool(v & (1 << 0)),   # PU  — core powered up
        "halted": bool(v & (1 << 4)),    # HALTED
        "os_locked": bool(v & (1 << 5)),  # OSLK — OS lock set
        "double_locked": bool(v & (1 << 6)),  # DLK — OS double lock
        "ext_dbg_disabled": bool(v & (1 << 7)),  # EDAD — external debug access disabled
    }


def _armv8a(sig: dict) -> dict:
    """Classify from DBGAUTHSTATUS (+ optional EDPRSR, + optional authenticated-
    debug presence for the SDC-600 frontier)."""
    da = sig.get("dbgauthstatus")
    ed = sig.get("edprsr")
    auth_present = sig.get("auth_debug")   # "none" | "present" | "provisioned"

    # Authenticated-debug frontier takes precedence when declared.
    if auth_present == "provisioned":
        return _verdict(AUTHENTICATED, sig,
                        "Certificate/authenticated secure debug is provisioned "
                        "(SDC-600 or equivalent): debug needs a signed challenge "
                        "response, not a simple lever.",
                        levers=["obtain/abuse the debug certificate", "SDC-600 COM-port challenge"])
    if auth_present == "present":
        return _verdict(GATED, sig,
                        "Authenticated-debug hardware is present but NO certificate "
                        "is provisioned — the same opt-in failure mode as an "
                        "unprovisioned FlashLock. Debug may still be reachable.",
                        levers=["debug is open until a cert is enrolled — enumerate now"])

    if ed:
        e = decode_edprsr(ed) if isinstance(ed, int) else ed
        if e.get("double_locked"):
            return _verdict(LOCKED, sig, "OS double-lock set (DLK) — external debug hard-blocked.")
        if e.get("ext_dbg_disabled"):
            return _verdict(GATED, sig,
                            "External debug access disabled (EDAD) — a firmware/authentication "
                            "gate, typically re-openable by controlling the debug-auth signals.")

    if da is not None:
        d = decode_dbgauthstatus(da) if isinstance(da, int) else da
        secure_open = d.get("SID") == "ENABLED"
        ns_open = d.get("NSID") == "ENABLED"
        if secure_open:
            return _verdict(OPEN, sig, "Secure AND non-secure invasive debug enabled (SID+NSID) — fully open.",
                            secure=True)
        if ns_open:
            return _verdict(OPEN, sig, "Non-secure invasive debug enabled (NSID); secure debug (SID) gated.",
                            secure=False)
        return _verdict(GATED, sig, "Invasive debug not enabled in DBGAUTHSTATUS — gated by the debug-auth signals.")
    return _verdict(NONE, sig, "No Armv8 debug-auth signals supplied.")


def _cortex_m(sig: dict) -> dict:
    """Cortex-M: DHCSR debug-enable + a vendor lock (RDP/APPROTECT/CRP/FSEC).
    'lock' in {none, engaged, permalock}; 'lever' optional runnable recovery."""
    lock = sig.get("lock", "none")
    dauth = sig.get("dauthstatus")   # SDC-600 DAUTHSTATUS on M-profile secure parts
    if dauth == "provisioned":
        return _verdict(AUTHENTICATED, sig, "M-profile authenticated debug (SDC-600 DAUTHSTATUS) provisioned.")
    if lock in ("permalock", "sealed"):
        return _verdict(LOCKED, sig, "Debug permanently locked (e.g. RDP level 2 / permanent APPROTECT) — no lever.")
    if lock in ("engaged", "on", True):
        return _verdict(GATED, sig,
                        "Debug locked but re-openable via a destructive mass-erase / RDP downgrade "
                        "(the lever wipes flash = debug access, not the original image).",
                        levers=[sig.get("lever", "vendor mass-erase / RDP downgrade")])
    return _verdict(OPEN, sig, "Cortex-M debug open (no readout protection engaged).")


def _riscv(sig: dict) -> dict:
    """RISC-V DMSTATUS.authenticated / authbusy (External Debug Security)."""
    authed = sig.get("authenticated")
    if authed is False:
        return _verdict(AUTHENTICATED, sig,
                        "RISC-V Debug Module reports authenticated=0 — external debug is behind "
                        "the authentication interface (authdata challenge). Needs a key, not a lever.")
    if authed is True or authed is None:
        # authenticated=1 (or DM present with no auth) → debug reachable; SBA extracts memory.
        return _verdict(OPEN, sig, "RISC-V Debug Module authenticated/open — halt + System Bus Access (SBA) available.")
    return _verdict(NONE, sig, "No RISC-V DMSTATUS supplied.")


_ARCHES = {
    "armv8a": _armv8a, "aarch64": _armv8a, "cortex-a": _armv8a, "zynqmp": _armv8a,
    "cortex-m": _cortex_m, "cortexm": _cortex_m,
    "riscv": _riscv, "risc-v": _riscv,
}


def _verdict(verdict: str, sig: dict, detail: str, secure: bool | None = None,
             levers: list | None = None) -> dict:
    return {
        "verdict": verdict,
        "detail": detail,
        "secure_debug": secure,
        "reopen_levers": levers or [],
        "reopenable": verdict in (OPEN, GATED),
    }


def classify(arch: str, signals: dict) -> dict:
    """Classify the debug-authentication posture for `arch` from `signals`.

    Returns {verdict, detail, secure_debug, reopen_levers, reopenable}.
    `arch` is matched case-insensitively; unknown archs return NONE."""
    fn = _ARCHES.get((arch or "").lower())
    if fn is None:
        return _verdict(NONE, signals, f"No debug-auth model for arch '{arch}'.")
    return fn(signals or {})
