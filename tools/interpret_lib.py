"""
interpret_lib.py — shared classes for the capture/interpret split.

Imported by:
  - tools/interpret.py (the main analysis tool)
  - docs/annotations/zynqmp_security.py (the annotation data module)
  - docs/findings/zynqmp_rules.py (the rules module)

Defines:
  - Capture: a read-only wrapper around a raw JSON capture, with
    convenient field/variant/etc. accessors used by rules
  - Annotation: dataclass for per-field human-readable annotations
  - Finding: dataclass for fired rule output, displayed in the report
"""

from __future__ import annotations

from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Capture wrapper — read-only access to a loaded raw JSON
# ---------------------------------------------------------------------------

class Capture:
    """
    Wraps a loaded raw JSON capture. Provides O(1) field lookups via a
    pre-built index. Currently the only consumer is `field()`; other
    accessors (variant, metadata, ...) were removed during Phase 2 cleanup
    as unused. Re-add only when a rule legitimately needs them.

    A "field path" is "BLOCK.REGISTER.FIELD" where BLOCK is the QEMU
    block name (CSU, EFUSE, CRF_APB, ...), REGISTER is the register's
    name (without block prefix), and FIELD is the bit-field name. The
    short form "REGISTER.FIELD" also works (matches across blocks).

    Examples:
      c.field("CSU.JTAG_DAP_CFG.SSSS_APU_SPIDEN")  -> 1 (or 0, or None)
      c.field("EFUSE.SEC_CTRL.JTAG_DIS")           -> 0
      c.field("RESET_REASON.EXTERNAL_POR")         -> 1 (short form)

    Missing field paths return None (not 0) so rules can distinguish
    "field absent from capture" from "field present with value 0".
    """

    def __init__(self, raw: dict):
        self.raw = raw
        # Index every field for fast lookup: "BLOCK.REGISTER.FIELD" -> value
        self._field_index: dict[str, int] = {}
        # Index whole-register raw values: "BLOCK.REGISTER" / "REGISTER" /
        # "0xADDR" -> integer value. Needed for field-less registers (PPK hash
        # words, AES_CRC, AES_STATUS, tamper config) that have no sub-fields.
        self._reg_index: dict[str, int] = {}
        for addr, reg in raw.get("registers", {}).items():
            block = reg.get("block", "")
            name = reg.get("name", "")
            val = reg.get("value_int")
            if val is not None:
                self._reg_index[f"{block}.{name}"] = val
                self._reg_index.setdefault(name, val)
                self._reg_index.setdefault(str(addr), val)
                if reg.get("address"):
                    self._reg_index.setdefault(reg["address"], val)
            for fname, fdata in reg.get("fields", {}).items():
                path = f"{block}.{name}.{fname}"
                self._field_index[path] = fdata.get("value")
                # Also index as just "REGISTER.FIELD" so rules can omit block
                short = f"{name}.{fname}"
                self._field_index.setdefault(short, fdata.get("value"))

    # --- field/value lookups ---

    def field(self, path: str) -> int | None:
        """Look up a bit-field value. Returns None if path not in capture.

        Path can be 'BLOCK.REGISTER.FIELD' or 'REGISTER.FIELD'.
        Currently the only Capture method used by rules — others were
        removed during cleanup as unused. Add them back when a rule
        legitimately needs them.
        """
        return self._field_index.get(path)

    def reg(self, key: str) -> int | None:
        """Look up a whole register's raw integer value. Returns None if the
        register isn't in the capture.

        Key can be 'BLOCK.REGISTER', 'REGISTER', or the '0xADDR' string. Use
        this for field-less registers (PPK hash words, AES_CRC, AES_STATUS,
        tamper config) where field() has nothing to return.
        """
        return self._reg_index.get(key)


# ---------------------------------------------------------------------------
# Annotation — per-field human-readable meaning
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Annotation:
    """
    Describes the human meaning of a specific register field.

    Attributes:
      register: "BLOCK.REGISTER" or just "REGISTER"
                  (matches enumerate.tcl naming)
      field:    bit-field name (matches QEMU's FIELD() macro name)
      description: general meaning (value-independent)
      values:   map of int value -> { label, meaning, expected_state,
                  offensive_use (optional), ... }

    Annotate fields where interpretation isn't obvious from the field name
    alone. Skip fields that are pure data (DNA, counts, capacities,
    free-form values).
    """
    register: str
    field: str
    description: str
    values: dict


@dataclass(frozen=True)
class RegisterAnnotation:
    """
    Register-level annotation for registers that have no bit fields —
    the whole 32-bit value is the value (boot offsets, base addresses,
    counts, aperture sizes).

    Attributes:
      register:    "BLOCK.REGISTER" or just "REGISTER" (matches enumerate.tcl)
      description: short prose describing what this register holds
      interpret:   optional callable (int_value) -> str. Lets the annotation
                   compute a derived meaning from the raw value (e.g. boot
                   image offset in bytes from a 32 KB-unit value, base
                   address pretty-print, decoded count, etc.). If None,
                   only `description` is shown.
    """
    register: str
    description: str
    interpret: object = None  # Callable[[int], str] or None


# ---------------------------------------------------------------------------
# Finding — output of a rule that fired
# ---------------------------------------------------------------------------

@dataclass
class Finding:
    """
    Output of a rule when its conditions match.

    Attributes:
      name:       short rule name (heading in the report)
      severity:   "CRITICAL" | "MAJOR" | "MINOR" | "INFO"
      conclusion: prose explaining what the combination means
      description (optional): one-sentence summary
      offensive_implications (optional): list of concrete attack primitives

    Severity values "CRITICAL" / "MAJOR" / "MINOR" / "INFO" map to the
    SEVERITY_MARKER dict in interpret.py for the report's coloured glyph.
    """
    name: str
    severity: str
    conclusion: str
    description: str = ""
    offensive_implications: list = field(default_factory=list)
