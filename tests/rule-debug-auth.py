#!/usr/bin/env python3
"""
rule-debug-auth.py — unit test for rule_debug_auth_matrix + _decode_dbgauth
(docs/findings/zynqmp_rules.py, added Phase 1 §1.3/1.4).

The golden test only exercises the "agree, secure-enabled" path (the dev
baseline). This guards the branches the golden can't reach: the CSU-vs-core
MISMATCH (MAJOR), the secure-closed agree path, and the ignore-conditions
(no cores captured, bus-float 0xFFFFFFFF). Offline; no hardware.
"""
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT / "tools"))
sys.path.insert(0, str(_ROOT / "docs" / "findings"))

from zynqmp_rules import rule_debug_auth_matrix, _decode_dbgauth  # noqa: E402


def _fail(msg):
    print(f"FAIL(rule-debug-auth): {msg}")
    sys.exit(1)


# --- DBGAUTHSTATUS field decode (Arm DDI0487 layout) ---
if _decode_dbgauth(0xFF) != {"NSID": "ENABLED", "NSNID": "ENABLED",
                             "SID": "ENABLED", "SNID": "ENABLED"}:
    _fail("0xFF should decode as all four signals ENABLED")
if _decode_dbgauth(0x0F)["SID"] != "not-impl" or _decode_dbgauth(0x0F)["NSID"] != "ENABLED":
    _fail("0x0F should be NS-enabled, secure not-implemented")
if _decode_dbgauth(0xAF)["SID"] != "disabled":
    _fail("0xAF (0b10 at [5:4]) should be secure-invasive DISABLED")


class _Cap:
    """Minimal Capture stand-in: per-core dbgauth in raw['a53'] + one field()."""
    def __init__(self, cores, spiden):
        self.raw = {"a53": {f"core{n}_dbgauth": v for n, v in cores.items()}}
        self._spiden = spiden

    def field(self, path):
        return self._spiden if path == "CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN" else None


# 1. secure enabled + CSU SPIDEN=1 → INFO (core corroborates the gate)
f = rule_debug_auth_matrix(_Cap({0: "0x000000ff"}, 1))
if f is None or f.severity != "INFO":
    _fail("all-enabled + SPIDEN=1 should be INFO agree")

# 2. CSU SPIDEN=1 but core reports secure-invasive DISABLED → MAJOR mismatch
f = rule_debug_auth_matrix(_Cap({0: "0x000000af"}, 1))
if f is None or f.severity != "MAJOR":
    _fail("SPIDEN=1 vs core SID=disabled should be MAJOR mismatch")
if "MISMATCH" not in f.conclusion:
    _fail("mismatch conclusion should say MISMATCH")

# 3. secure closed everywhere + CSU SPIDEN=0 → INFO agree (secure debug closed)
f = rule_debug_auth_matrix(_Cap({0: "0x0000000f"}, 0))
if f is None or f.severity != "INFO":
    _fail("secure-closed + SPIDEN=0 should be INFO agree")

# 4. no cores captured → rule stays silent
if rule_debug_auth_matrix(_Cap({}, 1)) is not None:
    _fail("no captured cores should yield no finding")

# 5. bus-float (0xFFFFFFFF) is not a real read → ignored → silent
if rule_debug_auth_matrix(_Cap({0: "0xffffffff"}, 1)) is not None:
    _fail("0xFFFFFFFF bus-float should be ignored")

# 6. multi-core, one disagrees → MAJOR (mismatch dominates)
f = rule_debug_auth_matrix(_Cap({0: "0x000000ff", 1: "0x000000af"}, 1))
if f is None or f.severity != "MAJOR":
    _fail("any-core mismatch should escalate to MAJOR")

print("PASS: rule-debug-auth (DBGAUTHSTATUS decode + agree/mismatch/ignore branches)")
