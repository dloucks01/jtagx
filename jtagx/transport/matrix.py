#!/usr/bin/env python3
"""
jtagx.transport.matrix — the capability MATRIX + op ROUTING over the transport backends.

The engagement lesson (memory project_adapter_transport_gap) was not only "OpenOCD can't drive a
FlashPro4" — it was "given the adapter in my hand and the op I need, WHICH backend does it, and if
none does, say so honestly instead of silently failing." base.Capabilities already says what one
(backend) can do; this module joins that across a board's whole adapter allowlist into a grid, and
routes each primitive to the best adapter — or reports it BLOCKED with the reason + what tool would
unblock it. Pure/offline: it reads profiles + backend capabilities, emits no USB traffic.

    from jtagx.transport.matrix import capability_matrix, route_op, matrix_markdown
    rows = capability_matrix(profile)                 # adapter × backend × per-op grid
    row, reason = route_op(profile, "mem_read", present=detect_adapters())
    print(matrix_markdown(profile, present))
"""
from __future__ import annotations

# NOTE: make_transport / BACKENDS live in this package's __init__, which imports THIS module last —
# so import them lazily (inside functions) to avoid a circular import at package-load time.

# the JTAG primitives we route, in access-ladder order (scan is the floor, run-control the ceiling)
OPS = ["scan", "boundary_scan", "mem_read", "mem_write", "halt", "run"]
OP_LABEL = {"scan": "scan/IDCODE", "boundary_scan": "bscan", "mem_read": "mem read",
            "mem_write": "mem write", "halt": "halt", "run": "run/resume"}
# access tiers (mirrors base.Capabilities.max_tier): a=IDCODE b=bscan c=mem-AP d=run-control e=exploit
TIER_LABEL = {"a": "IDCODE", "b": "boundary-scan", "c": "mem-AP", "d": "run-control", "e": "exploitation"}
_TIER_RANK = {"a": 0, "b": 1, "c": 2, "d": 3, "e": 4}
# the minimum reach an op needs — so a boundary-scan-only adapter (FlashPro on IGLOO2, tier b) is
# honestly shown as scan-only, NOT crediting it with the generic backend's mem/run-control verbs.
# This is what makes the matrix correct for fabric-only parts (no CPU ⇒ no halt/mem, whatever the probe).
OP_MIN_TIER = {"scan": "a", "boundary_scan": "b", "mem_read": "c", "mem_write": "c",
               "halt": "d", "run": "d"}


def _rank(tier):
    return _TIER_RANK.get(tier, 0)


def _backend_caps(backend: str, soc: str = "", cfg: str = ""):
    """Capabilities for a backend (constant per backend today; soc/cfg passed for future variance)."""
    from . import make_transport, BACKENDS      # lazy: avoid circular import at package load
    if backend not in BACKENDS:
        return None
    if backend == "openocd" and not cfg:
        cfg = f"openocd/{soc or 'board'}.cfg"
    try:
        return make_transport(backend, cfg=cfg, soc=soc).capabilities()
    except Exception:
        return None


def capability_matrix(profile: dict) -> list:
    """One row per allowlisted adapter of the board: what backend it uses and which ops it supports.

    Row = {adapter, id, backend, transports, tier, vendor_sw, driver, present(False until joined),
           ops:{op:bool}, max_tier, notes}. Ordered by reach (max_tier desc) so the most capable
           adapter is first — that's the one you'd reach for."""
    soc = profile.get("soc", "")
    cfg = profile.get("openocd_cfg", "") or ""
    rows = []
    for a in profile.get("adapters") or []:
        backend = a.get("backend", "openocd")
        caps = _backend_caps(backend, soc, cfg)
        if caps is None:
            ops = {op: False for op in OPS}
            row = dict(adapter=a.get("name", a.get("id", "?")), id=a.get("id", ""), backend=backend,
                       transports=a.get("transports", []), tier=a.get("tier", ""), vendor_sw=True,
                       driver=a.get("driver", ""), present=False, ops=ops, max_tier="a",
                       notes=f"backend {backend!r} unavailable")
            rows.append(row)
            continue
        # effective reach = the LOWER of what the backend can do and what THIS adapter reaches on THIS
        # board (the profile's per-adapter tier). A fabric-only part gives its FTDI/FlashPro tier "b",
        # which caps mem/halt/run off even though the OpenOCD backend generically claims them.
        adapter_tier = a.get("tier", "") or caps.max_tier
        eff_tier = adapter_tier if _rank(adapter_tier) <= _rank(caps.max_tier) else caps.max_tier
        ops = {op: bool(getattr(caps, op, False)) and _rank(eff_tier) >= _rank(OP_MIN_TIER[op])
               for op in OPS}
        rows.append(dict(
            adapter=a.get("name", a.get("id", "?")), id=a.get("id", ""), backend=backend,
            transports=a.get("transports", []), tier=adapter_tier,
            vendor_sw=bool(caps.needs_vendor_sw or a.get("vendor_sw")), driver=a.get("driver", ""),
            present=False, ops=ops, max_tier=eff_tier, notes=(a.get("note") or caps.notes or "")))
    rows.sort(key=lambda r: _rank(r["max_tier"]), reverse=True)
    return rows


def join_present(rows: list, present: list) -> list:
    """Mark which matrix rows correspond to a physically-plugged adapter (detect_adapters output),
    matching on USB backend/id. Mutates + returns rows so the GUI can show a 'plugged' dot."""
    have = {(c.get("backend"), c.get("id")) for c in (present or [])}
    have_backends = {c.get("backend") for c in (present or [])}
    for r in rows:
        r["present"] = (r["backend"], r["id"]) in have or r["backend"] in have_backends
    return rows


def route_op(profile: dict, op: str, present: list = None, *, prefer_present=True):
    """Pick the adapter/backend to run `op` on this board → (row, reason).

    Chooses the reachable adapter that supports `op`, preferring one that is PLUGGED IN and a
    non-vendor (plain-OpenOCD) path — the cheapest route. If some adapter *could* do it but only
    with vendor software (hw_server/Libero) or only when plugged in, that becomes the reason. If NO
    adapter supports it at all, returns (None, honest blocked reason + what would unblock it)."""
    if op not in OPS:
        return None, f"unknown op {op!r}"
    rows = capability_matrix(profile)
    if present is not None:
        join_present(rows, present)
    supporting = [r for r in rows if r["ops"].get(op)]
    if not supporting:
        # nobody can — say why + the escalation. Distinguish "needs a debugger this board lacks"
        # (fabric-only parts: FlashPro can't do run-control/mem) from "needs vendor sw".
        best = rows[0] if rows else None
        via = "chip-off / DPA / vendor readback" if op in ("mem_read", "mem_write") else "a CoreSight debugger"
        why = (f"no allowlisted adapter for {profile.get('soc','?')} can {OP_LABEL.get(op,op)} "
               f"— this op needs {via}")
        if best and best["backend"] == "libero":
            why += " (FlashPro is a program/verify engine, not a debugger)"
        return None, why

    def rank(r):
        return (
            0 if (prefer_present and r["present"]) else 1,   # plugged-in first
            0 if not r["vendor_sw"] else 1,                  # plain OpenOCD before vendor sw
            -_TIER_RANK.get(r["max_tier"], 0),               # more reach first
        )
    supporting.sort(key=rank)
    chosen = supporting[0]
    reason = f"{OP_LABEL.get(op, op)} via {chosen['adapter']} ({chosen['backend']})"
    if chosen["vendor_sw"]:
        reason += " — needs vendor software on PATH"
    if present is not None and not chosen["present"]:
        reason += " — not currently plugged in (command preview)"
    return chosen, reason


def routing_plan(profile: dict, present: list = None) -> dict:
    """{op: (row|None, reason)} for every primitive — the board's full op→adapter routing."""
    return {op: route_op(profile, op, present) for op in OPS}


def matrix_markdown(profile: dict, present: list = None) -> str:
    """A readable capability matrix + op-routing table for the CLI / a report."""
    soc = profile.get("soc", "?")
    rows = capability_matrix(profile)
    if present is not None:
        join_present(rows, present)
    out = [f"# Capability matrix — {soc}  ({profile.get('name', soc)})", ""]
    if not rows:
        out.append("_no adapter allowlist in this profile._")
        return "\n".join(out)
    # grid: adapter × ops
    hdr = "| adapter | backend | reach | " + " | ".join(OP_LABEL[o] for o in OPS) + " | vendor sw | plugged |"
    sep = "|" + "---|" * (5 + len(OPS))
    out += [hdr, sep]
    for r in rows:
        cells = ["✓" if r["ops"][o] else "·" for o in OPS]
        out.append(f"| {r['adapter']} | {r['backend']} | {TIER_LABEL.get(r['max_tier'], r['max_tier'])} | "
                   + " | ".join(cells) + f" | {'yes' if r['vendor_sw'] else 'no'} | "
                   + (("●" if r["present"] else "○") if present is not None else "—") + " |")
    out += ["", "## Op routing (best adapter per primitive)", ""]
    for op, (row, reason) in routing_plan(profile, present).items():
        mark = "→" if row else "✗ BLOCKED —"
        out.append(f"- **{OP_LABEL[op]}**: {mark} {reason}")
    return "\n".join(out)
