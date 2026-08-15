#!/usr/bin/env python3
"""
jtagx.transport — backend-agnostic JTAG transport layer.

The engagement lesson: never assume the adapter speaks OpenOCD. Given a board profile and the
adapter in hand, pick the right *backend* (OpenOCD / AMD hw_server+xsdb / Microsemi Libero) and
emit runnable commands for each primitive (scan / mem-read / mem-write / halt / run).

Typical use:
    from jtagx.transport import detect_adapters, make_transport, for_profile
    present = detect_adapters()                      # what's plugged in (USB VID:PID)
    t = for_profile(profile, present)                # auto-pick backend+adapter for this board
    print(t.scan().as_shell())                       # the exact command to run

Everything is pure/command-generating — nothing here opens USB or touches silicon (hands-on model).
"""
from __future__ import annotations

from .base import Transport, Command, Capabilities
from .openocd import OpenOCDTransport
from .xsdb import XsdbTransport
from .libero import LiberoTransport
from .detect import (detect_adapters, parse_lsusb, classify, match_profile, KNOWN)
from .targets import (TargetNode, parse_targets, classify_role, resolve_selector,
                      find as find_target, flatten as flatten_targets, render as render_targets,
                      zynqmp_reference, ROLE_FILTERS)
from .matrix import (capability_matrix, route_op, routing_plan, matrix_markdown, join_present,
                     OPS, OP_LABEL, TIER_LABEL)

BACKENDS = {
    "openocd": OpenOCDTransport,
    "hw_server": XsdbTransport,
    "libero": LiberoTransport,
}

__all__ = [
    "Transport", "Command", "Capabilities",
    "OpenOCDTransport", "XsdbTransport", "LiberoTransport",
    "BACKENDS", "make_transport", "for_profile",
    "detect_adapters", "parse_lsusb", "classify", "match_profile", "KNOWN",
    "TargetNode", "parse_targets", "classify_role", "resolve_selector", "find_target",
    "flatten_targets", "render_targets", "zynqmp_reference", "ROLE_FILTERS",
    "capability_matrix", "route_op", "routing_plan", "matrix_markdown", "join_present",
    "OPS", "OP_LABEL", "TIER_LABEL",
]


def make_transport(backend: str, *, cfg="", soc="", host="127.0.0.1", port=None,
                   target="", extra=None) -> Transport:
    """Instantiate the transport for a backend name (from a profile adapter's `backend`)."""
    cls = BACKENDS.get(backend)
    if cls is None:
        raise ValueError(f"unknown backend {backend!r}; known: {sorted(BACKENDS)}")
    return cls(cfg=cfg, soc=soc, host=host, port=port, target=target, extra=extra)


def _profile_cfg(profile: dict) -> str:
    return profile.get("openocd_cfg", "") or ""


def for_profile(profile: dict, present: list = None, *, prefer=None) -> Transport:
    """Auto-select a backend+adapter for this board.

    Strategy: intersect the board's adapter allowlist with what's physically present (if given),
    then pick — preferring a non-vendor OpenOCD path when available (simplest), unless `prefer`
    names a backend. Falls back to the profile's first allowlisted adapter when nothing is plugged
    in (so the GUI/CLI can still show the intended command).
    """
    adapters = profile.get("adapters") or []
    soc = profile.get("soc", "")
    cfg = _profile_cfg(profile)

    chosen_backend = None
    if prefer in BACKENDS:
        # `prefer` is an explicit operator choice (CLI --backend / GUI selector) — a HARD override,
        # honored even if that adapter isn't physically present yet (command preview / bench prep).
        chosen_backend = prefer
    elif present is not None:
        # auto-select from what's plugged in: prefer a working non-vendor OpenOCD path
        usable = sorted(match_profile(adapters, present)["usable"],
                        key=lambda c: 0 if c["backend"] == "openocd" else 1)
        if usable:
            chosen_backend = usable[0]["backend"]

    if chosen_backend is None:
        # no explicit choice and no live match — fall back to profile intent
        if adapters:
            oc = next((a for a in adapters if a.get("backend") == "openocd"), None)
            chosen_backend = (oc or adapters[0]).get("backend", "openocd")
        else:
            chosen_backend = "openocd"

    # openocd needs a cfg; if the profile has none, hand a placeholder so the error is legible
    if chosen_backend == "openocd" and not cfg:
        cfg = f"openocd/{soc or 'board'}.cfg"
    return make_transport(chosen_backend, cfg=cfg, soc=soc)
