"""
jtagx.posture — read a security posture from an enumeration capture.

Single home for the capture→posture logic that was duplicated in tools/unlock-engine.py
(`derive_posture`) and gui-spike/qt_spike.py (`load_real_posture`). Both now delegate here:
  - derive_flags(capture)  -> the flat posture dict the unlock engine reasons over
  - posture_rows(capture)  -> table rows (impl, location, value, state) for the GUI posture table
Reuses the canonical field paths from zynqmp_rules.py (via interpret_lib.Capture).
"""
import glob
import json
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if os.path.join(_ROOT, "tools") not in sys.path:
    sys.path.insert(0, os.path.join(_ROOT, "tools"))
from interpret_lib import Capture   # noqa: E402  (canonical field/reg accessor)


def load_capture(path):
    """Path to a raw-*.json → a Capture."""
    return Capture(json.load(open(path)))


def newest_capture(root=_ROOT):
    """Newest reports/raw-*.json path, or None."""
    caps = sorted(glob.glob(os.path.join(root, "reports", "raw-*.json")), key=os.path.getmtime)
    return caps[-1] if caps else None


# --- flat posture facts (for the unlock engine) -------------------------------------------------
def derive_flags(cap):
    """Map the canonical ZynqMP security fields to the unlock-engine posture keys.
    Absent fields stay UNKNOWN (key not set)."""
    P = {}
    dbgen    = cap.field("CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN")
    jtag_dis = cap.field("EFUSE.SEC_CTRL.JTAG_DIS")
    dft_dis  = cap.field("EFUSE.SEC_CTRL.DFT_DIS")
    if jtag_dis is not None:
        P["efuse_jtag_dis"] = (jtag_dis == 1 or dft_dis == 1)
    if dbgen is not None:
        is_open = (dbgen == 1) and (jtag_dis != 1)
        P["jtag_open"] = bool(is_open)
        if not is_open:
            P["jtag_locked"] = True
    elif jtag_dis == 1:
        P["jtag_open"] = False
        P["jtag_locked"] = True
    rsa      = cap.field("EFUSE.SEC_CTRL.RSA_EN")
    enc_only = cap.field("EFUSE.SEC_CTRL.ENC_ONLY")
    if rsa == 1:
        P["secure_boot"] = True
    elif enc_only == 1:
        P["secure_boot"] = "encrypt-only"
    elif rsa == 0 and enc_only == 0:
        P["secure_boot"] = False
    boot_enc = cap.field("CSU.CSU_STATUS.BOOT_ENC")
    eks      = cap.reg("BOOTHDR.ENC_KEY_SRC")
    if boot_enc == 1 or enc_only == 1 or (eks not in (None, 0)):
        P["aes_encrypt"] = True
    return P


# --- posture table rows (for the GUI) -----------------------------------------------------------
# (impl label, field path, value format, is-OPEN predicate)  — OPEN = exposed/dev, else hardened.
SECURITY_FIELDS = [
    ("APU debug enable",   "CSU.JTAG_DAP_CFG.SSSS_APU_DBGEN", "DBGEN={}",   lambda v: v == 1),
    ("JTAG disable eFuse", "EFUSE.SEC_CTRL.JTAG_DIS",         "jtag_dis={}", lambda v: v == 0),
    ("DFT disable eFuse",  "EFUSE.SEC_CTRL.DFT_DIS",          "dft_dis={}",  lambda v: v == 0),
    ("Secure Boot (RSA)",  "EFUSE.SEC_CTRL.RSA_EN",           "rsa_en={}",   lambda v: v == 0),
    ("Encrypt-only boot",  "EFUSE.SEC_CTRL.ENC_ONLY",         "enc_only={}", lambda v: v == 0),
    ("Boot AES encrypt",   "CSU.CSU_STATUS.BOOT_ENC",         "boot_enc={}", lambda v: v == 0),
    ("eFuse secure lock",  "EFUSE.SEC_CTRL.SEC_LOCK",         "sec_lock={}", lambda v: v == 0),
]


def posture_rows(cap):
    """Rows (impl, location, value, state) for a posture table; state ∈ {open, hardened}."""
    rows = []
    for impl, path, fmt, is_open in SECURITY_FIELDS:
        v = cap.field(path)
        if v is None:
            continue
        loc = path.split(".")[-2] if path.count(".") >= 2 else path
        rows.append((impl, loc, fmt.format(v), "open" if is_open(v) else "hardened"))
    return rows or None
