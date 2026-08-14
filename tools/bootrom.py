#!/usr/bin/env python3
"""
bootrom.py — analyze and summarize BootROM dumps from
openocd/dump-bootrom.tcl.

Three modes (auto-detected from arguments):

  python3 tools/bootrom.py
      No args. Find the most recent extraction set in dumps/, analyze every
      method's .bin, write a per-bin .analysis.md next to each, and write a
      cross-method summary to reports/bootrom-summary-<ts>.md.

  python3 tools/bootrom.py analyze <bin>
      Analyze one binary. Writes <bin>.analysis.md (or to stdout with --stdout).
      Equivalent to the previous tools/analyze-bootrom.py.

  python3 tools/bootrom.py summary [--timestamp <ts>]
      Cross-method comparison only. No per-bin analyses written. Use when you
      just want the summary table.

Options apply across modes:
  --dumps-dir DIR     where to look for .bin + .json (default: dumps/)
  --reports-dir DIR   where summary lands (default: reports/)
  --timestamp TS      pin to a specific timestamp set
  --stdout            print to stdout instead of writing files
  --json              emit summary as JSON instead of markdown
  --ascii             use ASCII bar chart for per-region entropy
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
from collections import Counter
from pathlib import Path


# ---------------------------------------------------------------------------
# Shared analysis helpers (used by both analyze + summary modes)
# ---------------------------------------------------------------------------

def shannon_entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = Counter(data)
    total = len(data)
    return -sum((c / total) * math.log2(c / total) for c in counts.values())


def fill_pattern_status(data: bytes) -> tuple[bool, str]:
    """Return (is_fill, descriptor) if buffer is a single byte or word fill."""
    if not data:
        return (False, "empty")
    if len(set(data)) == 1:
        return (True, f"all-0x{data[0]:02X} byte fill")
    if len(data) >= 4 and len(data) % 4 == 0:
        first = data[:4]
        if all(data[i:i+4] == first for i in range(0, len(data), 4)):
            w = struct.unpack("<I", first)[0]
            return (True, f"all-0x{w:08X} word fill")
    return (False, "")


def fill_label(data: bytes) -> str:
    """Short label form ('all-0xDEADBEEF', 'all-0x00', 'mixed')."""
    is_fill, desc = fill_pattern_status(data)
    if not is_fill:
        return "mixed"
    return desc.split(" ")[0]


def find_non_fill_bounds(data: bytes, fill_byte: int) -> tuple[int | None, int | None]:
    first = None
    last = None
    for i, b in enumerate(data):
        if b != fill_byte:
            if first is None:
                first = i
            last = i
    return (first, last)


_PRINTABLE_RE = re.compile(rb"[\x20-\x7e]{4,}")


def extract_strings(data: bytes, min_len: int = 4) -> list[tuple[int, str]]:
    # Honor min_len: the module-level regex is hardcoded to {4,} for the common
    # case; compile a wider threshold on demand so min_len isn't silently ignored.
    pat = _PRINTABLE_RE if min_len == 4 else re.compile(
        (r"[\x20-\x7e]{%d,}" % max(1, min_len)).encode("ascii"))
    return [(m.start(), m.group().decode("ascii", errors="replace"))
            for m in pat.finditer(data)]


# AArch64 opcode top-bit patterns. Common encodings only — heuristic.
AARCH64_PATTERNS = [
    ("B    (unconditional branch)",   0x14000000, 0xFC000000),
    ("BL   (branch with link)",       0x94000000, 0xFC000000),
    ("B.cond",                        0x54000000, 0xFF000010),
    ("RET",                           0xD65F0000, 0xFFFFFC1F),
    ("NOP",                           0xD503201F, 0xFFFFFFFF),
    ("MOV (wide imm)",                0x52800000, 0x7F800000),
    ("LDR (literal)",                 0x18000000, 0x3F000000),
    ("STR (immediate)",               0xB9000000, 0xFFC00000),
    ("LDR (immediate)",               0xB9400000, 0xFFC00000),
    ("MSR/MRS (sysreg)",              0xD5000000, 0xFFC00000),
    ("ADD/SUB (imm)",                 0x11000000, 0x7F000000),
]


def aarch64_match_fraction(data: bytes) -> tuple[float, dict]:
    if len(data) < 4:
        return (0.0, {})
    n_words = len(data) // 4
    matched = 0
    per_pat: dict[str, int] = {name: 0 for name, _, _ in AARCH64_PATTERNS}
    for i in range(n_words):
        word = struct.unpack_from("<I", data, i * 4)[0]
        for name, opc, mask in AARCH64_PATTERNS:
            if (word & mask) == opc:
                matched += 1
                per_pat[name] += 1
                break
    return (matched / n_words, per_pat)


def per_region_entropy(data: bytes, region_size: int = 1024) -> list[tuple[int, float]]:
    out = []
    for off in range(0, len(data), region_size):
        chunk = data[off:off + region_size]
        if chunk:
            out.append((off, shannon_entropy(chunk)))
    return out


def hex_preview(data: bytes, offset: int = 0, n_bytes: int = 64) -> list[str]:
    """Return canonical hexdump-style lines for a slice of data (A3)."""
    out = []
    chunk = data[offset:offset + n_bytes]
    for i in range(0, len(chunk), 16):
        line_bytes = chunk[i:i + 16]
        hex_part = " ".join(f"{b:02X}" for b in line_bytes)
        ascii_part = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in line_bytes)
        out.append(f"  {offset + i:08X}  {hex_part:<48}  {ascii_part}")
    return out


def csu_rom_digest_to_bytes(words: list) -> bytes | None:
    """Concatenate 12 hex-string words into a 48-byte SHA-384 hash buffer.
    Returns None if any word fails to parse."""
    try:
        # Each word is a 32-bit big-endian piece of the SHA-384 hash as
        # produced by the CSU hardware. Per Xilinx docs the digest is stored
        # word-by-word in big-endian order (MSW first).
        out = b""
        for w in words:
            out += struct.pack(">I", int(w, 16))
        return out
    except (ValueError, struct.error, TypeError):
        return None


def sha384_matches_digest(data: bytes, digest_words: list) -> tuple[bool, str, str]:
    """Compute SHA-384 of dump and compare to vendor-measured digest (H1).
    Returns (matched, computed_hex, expected_hex_or_reason)."""
    if not digest_words:
        return (False, "", "(no digest captured)")
    expected = csu_rom_digest_to_bytes(digest_words)
    if expected is None:
        return (False, "", "(digest words malformed)")
    computed = hashlib.sha384(data).digest()
    return (computed == expected, computed.hex(), expected.hex())


def verdict_for(data: bytes) -> str:
    """One-line verdict string used in both summary table + analyze report."""
    if not data:
        return "no data"
    is_fill, desc = fill_pattern_status(data)
    if is_fill:
        if "DEADBEEF" in desc.upper():
            return "all-deadbeef — AXI-gated"
        if desc.startswith("all-0x00"):
            return "all-zero — uninitialized SRAM"
        if desc.startswith("all-0xFF"):
            return "all-0xFF — erased flash / read-as-ones"
        return f"uniform fill ({desc})"
    frac, _ = aarch64_match_fraction(data)
    if frac > 0.30:
        return f"AArch64 code (opcode match {frac*100:.0f}%)"
    if frac > 0.10:
        return f"mixed code/data (opcode match {frac*100:.0f}%)"
    ent = shannon_entropy(data)
    if ent > 7.5:
        return f"high-entropy data (ent {ent:.2f})"
    if ent < 2.0:
        return "low-entropy / sparse"
    return "non-uniform, low ARM-opcode match"


# ---------------------------------------------------------------------------
# Per-binary analysis ("analyze" mode)
# ---------------------------------------------------------------------------

def render_analyze(bin_path: Path, data: bytes, sidecar: dict | None,
                   *, ascii_bars: bool = False) -> str:
    out: list[str] = []
    out.append(f"# BootROM dump analysis — `{bin_path.name}`")
    out.append("")
    out.append("## File facts")
    out.append("")
    out.append(f"- Path: `{bin_path}`")
    out.append(f"- Size: {len(data)} bytes ({len(data) // 1024} KB)")
    md5 = hashlib.md5(data).hexdigest()
    sha1 = hashlib.sha1(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()
    sha384 = hashlib.sha384(data).hexdigest()
    out.append(f"- MD5:    `{md5}`")
    out.append(f"- SHA1:   `{sha1}`")
    out.append(f"- SHA256: `{sha256}`")
    out.append(f"- SHA384: `{sha384}`")
    out.append("")

    if sidecar:
        out.append("## Sidecar metadata (from dump-bootrom.tcl)")
        out.append("")
        # Every scalar sidecar field worth surfacing in the analysis report.
        # Listed in display order; missing keys silently skipped.
        scalar_fields = (
            "timestamp", "method", "source_address",
            "size_bytes", "chunks_total", "chunks_ok", "chunks_failed",
            "dump_total_ms", "dump_max_chunk_ms", "method_total_ms",
            # csudma:
            "attempts_used", "sss_cfg_orig", "sss_cfg_used",
            "poll_iters", "poll_ms",
            "src_busy_final", "dst_busy_final",
            "src_intr_sts", "dst_intr_sts",
            "src_intr_decoded", "dst_intr_decoded",
            "csu_status_pre", "csu_status_post",
            "csu_ctrl_pre", "csu_ctrl_post",
            # baseline security state:
            "csu_status", "csu_ctrl", "csu_sss_cfg",
            "csu_tamper_trig", "csu_tamper_status",
            "csu_jtag_chain_sts", "csu_jtag_dap_cfg", "csu_jtag_sec",
            "efuse_sec_ctrl",
            # a53 payloads:
            "a53_state", "a53_pc_final",
            "esr_el3", "far_el3", "elr_el3", "spsr_el3",
            "done_marker_ok", "done_marker_lo", "done_marker_hi",
            "marker_polled", "marker_poll_ms",
            "sctlr_before", "sctlr_after",
            "sctlr_before_decoded", "sctlr_after_decoded",
            "stage_start", "stage_start_m1m2_expected",
            "error", "binary_path",
        )
        for k in scalar_fields:
            if k in sidecar:
                val = sidecar[k]
                if k == "a53_pc_final":
                    val = _coerce_pc_str(val)
                out.append(f"- `{k}`: {val}")
        if sidecar.get("failed_addrs"):
            n = len(sidecar["failed_addrs"]) if isinstance(sidecar["failed_addrs"], list) else 1
            out.append(f"- `failed_addrs`: {n} address(es) failed read")
        out.append("")

        # Adjacent-region survey from baseline (H4)
        if sidecar.get("adjacent_survey"):
            out.append("## Adjacent-region readability survey")
            out.append("")
            out.append("Single-word probe at each waypoint to scope the gating.")
            out.append("")
            out.append("```")
            out.append("  ADDRESS      FIRST WORD   STATUS                              LABEL")
            for entry in sidecar["adjacent_survey"]:
                # Format from dump-bootrom.tcl: "addr|first_word|status|label"
                parts = entry.split("|", 3) if isinstance(entry, str) else []
                if len(parts) == 4:
                    out.append(f"  {parts[0]}   {parts[1]}   {parts[2]:<36}{parts[3]}")
                else:
                    out.append(f"  {entry}")
            out.append("```")
            out.append("")

    out.append("## Fill-pattern detection")
    out.append("")
    is_fill, descriptor = fill_pattern_status(data)
    tool_fill = bool(sidecar) and all_reads_failed(sidecar)
    if is_fill:
        out.append(f"**Buffer is a uniform fill pattern**: {descriptor}")
        out.append("")
        out.append("Interpretation:")
        out.append("")
        if tool_fill:
            out.append("- **All chunks failed read** (`chunks_ok=0`). These bytes are")
            out.append("  this tool's DEADBEEF fill for failed reads — they did NOT")
            out.append("  come from the chip. The transport (DAP/AXI/CSU path) was")
            out.append("  broken at dump time, so the buffer says nothing about the")
            out.append("  source address's contents. See sidecar `error` /")
            out.append("  `failed_addrs` and the per-method log for the actual fault.")
        elif "DEADBEEF" in descriptor.upper():
            out.append("- Address range is **unmapped or AXI-gated**. OpenOCD's AXI")
            out.append("  mem-AP returns 0xDEADBEEF for failed reads on ZynqMP.")
        elif descriptor.startswith("all-0x00"):
            out.append("- Address range is **uninitialized SRAM**. OCM bank reads as")
            out.append("  zeros until written.")
        elif descriptor.startswith("all-0xFF"):
            out.append("- Returns all-1s — typical for erased flash, unusual for OCM/CSU ROM.")
    else:
        out.append("Buffer is NOT a uniform fill pattern — proceeding with deeper analysis.")
    out.append("")

    if not is_fill:
        for fb, label in [(0x00, "zero"), (0xFF, "0xFF")]:
            first, last = find_non_fill_bounds(data, fb)
            if first is not None and (last - first) < len(data) - 1:
                out.append(f"- First non-{label} byte at offset 0x{first:X}; "
                           f"last at 0x{last:X} (active region ≈ {last - first + 1} bytes)")
        out.append("")

    out.append("## Entropy")
    out.append("")
    overall = shannon_entropy(data)
    out.append(f"- Overall Shannon entropy: **{overall:.3f} bits/byte** (max 8.000)")
    if overall < 1.0:
        out.append("  - Very low — single byte value (fill pattern)")
    elif overall < 3.0:
        out.append("  - Low — repeating patterns, padding, or sparse data")
    elif overall < 6.0:
        out.append("  - Medium — typical compiled code with strings + tables")
    elif overall < 7.5:
        out.append("  - High — dense compiled code or compressed data")
    else:
        out.append("  - Very high (≥7.5) — likely encrypted, compressed, or random")
    out.append("")

    regions = per_region_entropy(data, 1024)
    if regions and len(regions) > 1:
        out.append(f"- Per-1KB-region entropy ({len(regions)} regions):")
        bar_char = "#" if ascii_bars else "█"
        for off, ent in regions:
            bar = bar_char * int(ent)
            out.append(f"  - `0x{off:04X}`: {ent:.2f} {bar}")
        out.append("")

    out.append("## AArch64 instruction-shape detection")
    out.append("")
    if is_fill:
        out.append("_(Skipped — buffer is a fill pattern.)_")
    else:
        frac, per_pat = aarch64_match_fraction(data)
        # Each word matches at most one pattern (the loop breaks on first hit),
        # so sum(per_pat) IS the exact integer match count — use it directly
        # rather than re-deriving from the float ratio (which can round wrong).
        matched = sum(per_pat.values())
        out.append(f"- Words matching known AArch64 opcode patterns: "
                   f"**{frac*100:.1f}%** "
                   f"({matched} of {len(data) // 4} words)")
        out.append("")
        if frac > 0.30:
            out.append("Interpretation: **dump contains AArch64 code** — high opcode match.")
        elif frac > 0.10:
            out.append("Interpretation: mixed code + data, OR partial code visible.")
        else:
            out.append("Interpretation: **does not look like AArch64 code**.")
        out.append("")
        out.append("Per-pattern counts:")
        for name, count in sorted(per_pat.items(), key=lambda x: -x[1])[:8]:
            if count:
                out.append(f"  - `{name}`: {count}")
        out.append("")

    out.append("## Printable strings (length ≥ 4)")
    out.append("")
    strings = extract_strings(data, min_len=4)
    if not strings:
        out.append("_(No printable strings found.)_")
    else:
        out.append(f"Found {len(strings)} string(s). Showing first 30:")
        out.append("")
        for off, s in strings[:30]:
            out.append(f"  - `0x{off:04X}`: `{s}`")
        if len(strings) > 30:
            out.append(f"  - ... ({len(strings) - 30} more)")
    out.append("")

    # A3: hex preview of first + last 64 bytes
    if data:
        out.append("## Hex preview")
        out.append("")
        out.append("First 64 bytes:")
        out.append("")
        out.append("```")
        out.extend(hex_preview(data, 0, 64))
        out.append("```")
        out.append("")
        if len(data) > 128:
            tail_off = len(data) - 64
            out.append(f"Last 64 bytes (offset 0x{tail_off:X}):")
            out.append("")
            out.append("```")
            out.extend(hex_preview(data, tail_off, 64))
            out.append("```")
            out.append("")

    # CSU digest cross-check (only meaningful for method 0 baseline)
    if sidecar and sidecar.get("csu_rom_digest"):
        raw = sidecar["csu_rom_digest"]
        if isinstance(raw, dict):
            words: list[str] = []
            for k, v in raw.items():
                words.append(k); words.append(v)
        elif isinstance(raw, list):
            words = list(raw)
        else:
            words = []

        out.append("## CSU.CSU_ROM_DIGEST_0..11 cross-check")
        out.append("")
        out.append("```")
        for i, w in enumerate(words):
            out.append(f"  CSU_ROM_DIGEST_{i:2d} = {w}")
        out.append("```")
        out.append("")
        try:
            non_zero = sum(1 for w in words if int(w, 16) != 0)
            digest_be = csu_rom_digest_to_bytes(words)
            if digest_be:
                out.append(f"- Concatenated big-endian: `{digest_be.hex()}`")
                # Some tools emit little-endian word order — show both for cross-ref.
                digest_le = b"".join(struct.pack("<I", int(w, 16)) for w in words)
                out.append(f"- Concatenated little-endian: `{digest_le.hex()}`")
            out.append(f"- Non-zero words: {non_zero} / {len(words)}")
            if non_zero == 0:
                out.append("- All digest words zero → CSU hasn't measured the BootROM "
                           "in this boot session, OR digest registers were unreadable.")
            elif non_zero >= len(words) * 0.7:
                out.append("- High non-zero fraction → CSU has measured the BootROM. "
                           "The hash is authentic vendor data even if the BootROM "
                           "region itself was unmapped.")
        except (ValueError, struct.error):
            out.append("- (couldn't parse digest words)")
        out.append("")

        # H1: SHA-384 cross-check — if this dump's SHA-384 matches the
        # vendor's CSU_ROM_DIGEST then we have the REAL BootROM bytes.
        # This is the definitive "did we get it?" check.
        matched, computed, expected = sha384_matches_digest(data, words)
        out.append("### SHA-384 cross-check vs CSU_ROM_DIGEST")
        out.append("")
        out.append(f"- Dump SHA-384:  `{computed[:48]}…`" if computed else "- Dump SHA-384:  _(empty)_")
        if isinstance(expected, str) and expected.startswith("("):
            out.append(f"- Vendor digest: {expected}")
        else:
            out.append(f"- Vendor digest: `{expected[:48]}…`")
        if matched:
            out.append("- **MATCH** ✓ — this dump IS the real BootROM. Cryptographic proof.")
        elif computed and not expected.startswith("("):
            out.append("- No match — this dump is either gated/fill bytes or the "
                       "digest is byte-ordered differently than assumed (BE word order).")
        out.append("")

    out.append("## Verdict")
    out.append("")
    if tool_fill:
        out.append("all reads failed (transport broken) — bytes are tool fill, not chip response")
    else:
        out.append(verdict_for(data))
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Cross-method summary ("summary" mode)
# ---------------------------------------------------------------------------

# (sort_order, file_prefix, display_id, display_name, mech)
METHODS = [
    (0, "bootrom",            "M0", "Baseline (JTAG mem-AP)",    "JTAG → DAP → AXI mem-AP → CSU"),
    (1, "bootrom-via-csudma", "M3", "CSU DMA loopback",          "CSU DMA SRC→DST inside CSU"),
    (2, "bootrom-via-a53",    "M1", "A53 EL3 dump",              "A53 EL3 → CCI → AXI mem-AP"),
    (3, "bootrom-via-loader", "M2", "Loader (D-cache off)",      "A53 EL3 with SCTLR_EL3.C=0"),
    (4, "bootrom-via-r5",     "M4", "R5 RPU dump",               "Cortex-R5 ATCM payload → AXI"),
    (5, "bootrom-via-aes",    "M5", "CSU AES route (speculative)", "BootROM → CSU AES → DMA-dst"),
]
METHOD_ID = {prefix: did for _, prefix, did, _, _ in METHODS}


_TS_REGEX = re.compile(
    r"\Abootrom(?:-via-[a-z0-9]+)?-(\d{4}-\d{2}-\d{2}-\d{6})\.json\Z"
)


def discover_timestamp(dumps_dir: Path) -> str | None:
    counts: Counter[str] = Counter()
    for p in dumps_dir.glob("bootrom*.json"):
        m = _TS_REGEX.match(p.name)
        if m:
            counts[m.group(1)] += 1
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: (kv[1], kv[0]))[0]


def _coerce_pc_str(v: object) -> str:
    """Pre-fix runs stored a53_pc_final as a multi-word string, which the
    buggy write_dump_metadata then emitted as a JSON array
    ['pc', '(/64):', '0x...']. Newer runs store it as a clean hex scalar.
    Accept either."""
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        for tok in v:
            if isinstance(tok, str) and tok.startswith("0x"):
                return tok
        return " ".join(str(x) for x in v)
    return str(v)


def all_reads_failed(sidecar: dict) -> bool:
    """True if every chunk in the dump failed to read — the binary is tool-fill
    (0xDEADBEEF from our dump_memory recovery), not chip data."""
    total = sidecar.get("chunks_total", 0)
    failed = sidecar.get("chunks_failed", 0)
    return total > 0 and failed == total


def load_method(dumps_dir: Path, ts: str, prefix: str) -> dict | None:
    """Load one method's artifacts. Distinguishes three cases:
      - MISSING:  no .json sidecar (method never ran)
      - ABORTED:  sidecar present + 'error' field set (method ran, failed early)
      - OK:       .bin + .json both present
    """
    bin_path = dumps_dir / f"{prefix}-{ts}.bin"
    json_path = dumps_dir / f"{prefix}-{ts}.json"

    sidecar: dict = {}
    if json_path.exists():
        try:
            sidecar = json.loads(json_path.read_text())
        except json.JSONDecodeError:
            pass

    # Aborted: sidecar exists, error recorded, no bin (or zero-size bin)
    if sidecar and sidecar.get("error") and not bin_path.exists():
        return {
            "status": "aborted",
            "bin_path": bin_path,
            "json_path": json_path,
            "data": b"",
            "sidecar": sidecar,
            "sha256": "",
            "fill": "",
            "verdict": f"ABORTED — {sidecar['error']}",
        }

    if not bin_path.exists():
        return None

    data = bin_path.read_bytes()
    # Override verdict if all reads failed — the binary is tool-fill, not data.
    if all_reads_failed(sidecar):
        verdict = "all reads failed (DAP wedged) — bytes are tool fill, not chip response"
    else:
        verdict = verdict_for(data)
    return {
        "status": "ok",
        "bin_path": bin_path,
        "json_path": json_path if json_path.exists() else None,
        "data": data,
        "sidecar": sidecar,
        "sha256": hashlib.sha256(data).hexdigest(),
        "fill": fill_label(data),
        "verdict": verdict,
        "tool_fill": all_reads_failed(sidecar),
    }


def _safe_hex_int(w, default: int = 0) -> int:
    """Parse a hex string to int, returning `default` on any failure.
    Centralizes the int(w, 16) call so the summary path can't crash on
    a malformed sidecar value (None, integer, non-hex string, etc.)."""
    if isinstance(w, int):
        return w          # already an int (e.g. sidecar stored a JSON number)
    try:
        return int(w, 16)
    except (TypeError, ValueError):
        return default


def _get_digest_words_from_results(results: dict) -> list:
    """Extract the CSU_ROM_DIGEST captured by the baseline method, if any.
    Accepts both list-shaped and dict-shaped digest payloads (the latter
    is what older runs wrote when sidecar serialization treated the digest
    as a key-value sequence)."""
    baseline = results.get("bootrom")
    if baseline is None:
        return []
    sc = baseline.get("sidecar", {})
    raw = sc.get("csu_rom_digest", [])
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        # Flatten in insertion order; values are the actual hex strings.
        # (Earlier sidecar writer interleaved key/value as 12 entries each.)
        return list(raw.values())
    return []


# Display order for the headline (not the same as METHODS sort_order — the
# headline groups by intuitive ordering for triage).
_HEADLINE_ORDER = [
    ("bootrom",            "M0", "baseline"),
    ("bootrom-via-csudma", "M3", "csu-dma"),
    ("bootrom-via-a53",    "M1", "a53-el3"),
    ("bootrom-via-loader", "M2", "a53-cache-off"),
    ("bootrom-via-r5",     "M4", "r5-rpu"),
    ("bootrom-via-aes",    "M5", "csu-aes"),
]


def _classify_for_headline(prefix: str, r: dict | None) -> tuple[str, str, str]:
    """Compress a method result into (icon, label, one-line detail).
    Icons: ✓ success, ✗ hard failure (something we should fix),
           ⏸ expected/known-gated failure, ◌ missing."""
    if r is None:
        return ("◌", "MISSING", "(no artifacts)")
    sc = r.get("sidecar", {}) or {}
    if r["status"] == "aborted":
        err = sc.get("error", "")
        # Classify by error fingerprint
        if "DEFERRED" in err:
            # Historical: M2 used to be auto-deferred. As of 2026-05-28,
            # M2 is active in the `all` flow. DEFERRED status should only
            # appear if the user manually crafts a deferred-tagged sidecar.
            return ("⏸", "DEFERRED", "marked deferred in sidecar — see error text")
        if "DAP wedged" in err:
            return ("⏸", "SKIPPED", "DAP wedged from prior method")
        if "RPU" in err or "TCM" in err or "XMPU" in err:
            # Confirmed real chip behavior 2026-05-28: RPU power-island
            # requires PMU FW to bring up. JTAG can release R5 reset bit
            # but the island stays gated. Not a tool bug — needs Phase 7
            # SD/QSPI boot with PMU FW loaded.
            return ("⏸", "GATED", "RPU power-island off — needs PMU FW")
        if "did not halt" in err:
            stage = sc.get("stage_start", "")
            stage_exp = sc.get("stage_start_m1m2_expected", "") or sc.get("stage_start_expected", "")  # back-compat
            sctlr_b = sc.get("sctlr_before", "")
            try:
                stage_i = int(stage, 16) if stage else 0
                stage_exp_i = int(stage_exp, 16) if stage_exp else 0
                sctlr_b_i = int(sctlr_b, 16) if sctlr_b else 0
            except ValueError:
                stage_i = stage_exp_i = sctlr_b_i = 0
            if stage_exp_i and stage_i == stage_exp_i and sctlr_b_i == 0:
                # Note: in JTAG-idle SCTLR_EL3.C is already 0, so an MRS
                # that reads 0 isn't necessarily a fault — could be benign.
                return ("✗", "EL3-FAULT?",
                        "stage marker set but SCTLR=0 — MRS may have read benign 0")
            if stage_exp_i and stage_i == 0:
                # PRE-2026-05-28: this was the dominant failure mode due
                # to the UTF-8 byte-count bug truncating payloads. That
                # bug is now fixed. If PAYLOAD-DEAD triggers post-fix,
                # it's a genuine A53 release / OCM write issue, not a
                # payload truncation issue.
                return ("✗", "PAYLOAD-DEAD",
                        "stage_start=0 → A53 never reached payload (real chip-state issue)")
            return ("✗", "PAYLOAD-HUNG", err)
        if "release_a53" in err:
            return ("✗", "RELEASE-FAIL", err)
        return ("✗", "ABORTED", err or "(unspecified)")
    # status == ok
    if r.get("tool_fill"):
        return ("✗", "TRANSPORT-FAIL",
                f"all {sc.get('chunks_failed','?')} chunks failed (DAP/AXI broken)")
    fill = (r.get("fill") or "").upper()
    detail = ""
    if "DEADBEEF" in fill:
        label = "CHIP-GATED"
        if prefix == "bootrom":
            digest = sc.get("csu_rom_digest", [])
            if isinstance(digest, dict):
                digest = list(digest.values())
            non_zero = sum(1 for w in digest if _safe_hex_int(w) != 0)
            n = len(digest) if digest else 0
            detail = f"16KB DEADBEEF, vendor digest {non_zero}/{n} words"
        elif prefix == "bootrom-via-csudma":
            src_d = sc.get("src_intr_decoded") or "(none)"
            detail = f"I_STS={src_d}"
        elif prefix in ("bootrom-via-a53", "bootrom-via-loader"):
            ms = sc.get("marker_poll_ms")
            if sc.get("done_marker_ok"):
                detail = f"payload OK, marker met in {ms}ms"
            else:
                detail = "payload returned but marker NOT set"
        elif prefix == "bootrom-via-aes":
            sss = sc.get("sss_cfg_used", "?")
            detail = f"AES route programmed (SSS={sss})"
        return ("✓", label, detail)
    if "0X00" in fill:
        return ("✓", "ALL-ZERO", "uninitialized region")
    if "0XFF" in fill:
        return ("✓", "ALL-0xFF", "erased flash pattern")
    if fill:
        return ("✓", "FILL", fill.lower())
    return ("✓", "BYTES", f"non-fill {len(r['data'])}B captured")


def _summarize_outcome(results: dict) -> str:
    """One-line cross-method finding."""
    digest_words = _get_digest_words_from_results(results)
    # Real bootrom?
    if digest_words and any(_safe_hex_int(w) for w in digest_words):
        for r in results.values():
            if r and r["status"] == "ok" and not r.get("tool_fill"):
                matched, _, _ = sha384_matches_digest(r["data"], digest_words)
                if matched:
                    return ("REAL BOOTROM CAPTURED — SHA-384 matches vendor "
                            "CSU_ROM_DIGEST")
    # Hash agreement?
    by_hash: dict[str, list[str]] = {}
    for prefix, r in results.items():
        if r and r["status"] == "ok" and not r.get("tool_fill"):
            by_hash.setdefault(r["sha256"], []).append(prefix)
    n_ok = sum(len(v) for v in by_hash.values())
    if n_ok == 0:
        return ("no method captured chip bytes — transport broken or "
                "every method aborted")
    if n_ok == 1:
        # Single OK method, nothing to cross-check
        return "only 1 method returned bytes — no cross-method agreement to check"
    if len(by_hash) == 1:
        return (f"{n_ok} methods agree on byte content — chip is gating, "
                "not transport failure")
    return (f"{n_ok} OK methods returned {len(by_hash)} distinct hashes "
            "(unexpected — investigate)")


def _suggest_next(results: dict) -> str:
    """Heuristic 'what to do next'."""
    suggestions = []
    # Hard failures take priority
    for prefix, r in results.items():
        if r and r["status"] == "aborted":
            err = r.get("sidecar", {}).get("error", "")
            if "did not halt" in err:
                suggestions.append(
                    f"investigate {METHOD_ID.get(prefix, prefix)} "
                    "(A53 release leaves PC stale — see sidecar stage_start)")
                break
            if "release_a53" in err:
                suggestions.append(
                    f"diagnose {METHOD_ID.get(prefix, prefix)} release failure "
                    "(check RST_FPD_APU read-back in log)")
                break
    # If any wedge happened, recommend power-cycle for next run
    wedged = any(
        r and r["status"] == "aborted"
        and "wedged" in (r.get("sidecar", {}).get("error", ""))
        for r in results.values()
    )
    if wedged:
        suggestions.append("power-cycle board before next run (DAP residue)")
    # If we have a digest but no match, suggest non-AXI paths
    digest_words = _get_digest_words_from_results(results)
    has_digest = digest_words and any(_safe_hex_int(w) for w in digest_words)
    has_real = False
    if has_digest:
        for r in results.values():
            if r and r["status"] == "ok" and not r.get("tool_fill"):
                if sha384_matches_digest(r["data"], digest_words)[0]:
                    has_real = True
                    break
    if has_digest and not has_real and not suggestions:
        suggestions.append(
            "explore non-AXI extraction paths (boot from SD/QSPI, PMU IPI, "
            "side-channel) — every AXI-side method is gated")
    return " ; ".join(suggestions) or "(no specific recommendation)"


def _diff_vs_previous(dumps_dir: Path, ts: str, results: dict) -> str:
    """Compare this run's per-method outcomes to the previous run, if any."""
    # Find all timestamps in dumps_dir, return the one immediately before ts.
    # Uses _TS_REGEX (module-level) so naming changes stay in sync with
    # discover_timestamp.
    all_ts = set()
    for p in dumps_dir.glob("bootrom*.json"):
        m = _TS_REGEX.match(p.name)
        if m:
            all_ts.add(m.group(1))
    earlier = sorted(t for t in all_ts if t < ts)
    if not earlier:
        return "(no previous run to compare)"
    prev_ts = earlier[-1]
    prev_results = {}
    for _, prefix, _, _, _ in METHODS:
        prev_results[prefix] = load_method(dumps_dir, prev_ts, prefix)
    deltas = []
    for prefix, _, short in _HEADLINE_ORDER:
        cur = results.get(prefix)
        prev = prev_results.get(prefix)
        cur_lbl = _classify_for_headline(prefix, cur)[1]
        prev_lbl = _classify_for_headline(prefix, prev)[1]
        if cur_lbl != prev_lbl:
            deltas.append(f"{METHOD_ID.get(prefix, prefix)}: {prev_lbl} → {cur_lbl}")
    if not deltas:
        return f"vs {prev_ts}: no per-method status changes"
    return f"vs {prev_ts}: " + " ; ".join(deltas)


def render_headline(ts: str, results: dict, dumps_dir: Path | None = None) -> str:
    """Render the at-a-glance headline block. Goes at the top of summary.md
    AND is auto-printed to stdout by mode_summary."""
    # 78 chars accommodates the longest per-method line in the body
    # (icon + "M0 baseline" + label + detail) without raggedness.
    width = 78
    bar = "=" * width
    out: list[str] = []
    out.append(bar)
    out.append(f"  BootROM Extraction — {ts}")
    out.append(bar)
    out.append("")
    # Per-method one-liners
    for prefix, mid, short in _HEADLINE_ORDER:
        r = results.get(prefix)
        icon, label, detail = _classify_for_headline(prefix, r)
        out.append(f"  {icon} {mid} {short:<14}  {label:<14}  {detail}")
    out.append("")
    # Hash agreement summary
    hashes: dict[str, list[str]] = {}
    for prefix, r in results.items():
        if r and r["status"] == "ok" and not r.get("tool_fill"):
            hashes.setdefault(r["sha256"], []).append(METHOD_ID.get(prefix, prefix))
    if hashes:
        h_lines = []
        for h, mids in hashes.items():
            h_lines.append(f"{len(mids)} method(s) agree on {h[:16]}… ({', '.join(mids)})")
        out.append(f"  HASHES:   {h_lines[0]}")
        for extra in h_lines[1:]:
            out.append(f"            {extra}")
    # Digest status
    digest_words = _get_digest_words_from_results(results)
    if digest_words:
        non_zero = sum(1 for w in digest_words if _safe_hex_int(w) != 0)
        has_match = False
        if non_zero:
            for r in results.values():
                if r and r["status"] == "ok" and not r.get("tool_fill"):
                    if sha384_matches_digest(r["data"], digest_words)[0]:
                        has_match = True
                        break
        if non_zero == 0:
            out.append("  DIGEST:   vendor digest registers all zero (not measured this boot)")
        elif has_match:
            out.append(f"  DIGEST:   vendor SHA-384 captured ({non_zero}/{len(digest_words)} "
                       "words) — MATCH found! ✓")
        else:
            out.append(f"  DIGEST:   vendor SHA-384 captured ({non_zero}/{len(digest_words)} "
                       "words), no method matches yet")
    out.append(f"  OUTCOME:  {_summarize_outcome(results)}")
    if dumps_dir is not None:
        out.append(f"  VS LAST:  {_diff_vs_previous(dumps_dir, ts, results)}")
    out.append(f"  NEXT:     {_suggest_next(results)}")
    out.append("")
    out.append(bar)
    return "\n".join(out)


def render_summary(ts: str, results: dict[str, dict | None],
                   dumps_dir: Path | None = None) -> str:
    out: list[str] = []
    # ASCII headline block at the very top — same content auto-printed to
    # console after a run, so this file reads the same as the console output.
    out.append("```")
    out.append(render_headline(ts, results, dumps_dir))
    out.append("```")
    out.append("")
    out.append(f"# BootROM Extraction Summary — {ts}")
    out.append("")
    out.append("Side-by-side comparison of all six extraction methods. "
               "See the headline above for the at-a-glance triage view; "
               "the sections below have the raw per-method data.")
    out.append("")

    out.append("## Per-method results")
    out.append("")
    out.append("| Method | Mechanism | Status | Size | SHA-256 (first 16) | Verdict |")
    out.append("|---|---|---|---|---|---|")
    for _, prefix, did, name, mech in METHODS:
        r = results.get(prefix)
        if r is None:
            out.append(f"| **{did}** {name} | {mech} | MISSING | — | — | (no artifacts) |")
        elif r["status"] == "aborted":
            out.append(f"| **{did}** {name} | {mech} | **ABORTED** | — | — | {r['verdict']} |")
        else:
            out.append(f"| **{did}** {name} | {mech} | ok | {len(r['data']):,} B | "
                       f"`{r['sha256'][:16]}…` | {r['verdict']} |")
    out.append("")

    out.append("## Hash agreement")
    out.append("")
    out.append("Same SHA-256 across methods = identical bytes captured. "
               "Aborted methods are excluded (no bytes to compare).")
    out.append("")
    by_hash: dict[str, list[str]] = {}
    for prefix, r in results.items():
        if r is not None and r["status"] == "ok" and not r.get("tool_fill"):
            by_hash.setdefault(r["sha256"], []).append(prefix)
    if not by_hash:
        out.append("_(No successful methods to compare.)_")
    else:
        out.append("| Hash | Methods |")
        out.append("|---|---|")
        for h, prefixes in by_hash.items():
            ids = ", ".join(METHOD_ID[p] for p in sorted(
                prefixes, key=lambda x: [m[1] for m in METHODS].index(x)))
            out.append(f"| `{h[:32]}…` | {ids} |")
    out.append("")

    # H1: SHA-384 cross-check — compares every OK dump's SHA-384 against
    # the vendor-measured CSU_ROM_DIGEST captured by the baseline method.
    # A MATCH here is the definitive "we got the real BootROM" signal.
    digest_words = _get_digest_words_from_results(results)
    if digest_words and any(_safe_hex_int(w) for w in digest_words):
        out.append("## SHA-384 cross-check vs CSU_ROM_DIGEST (H1)")
        out.append("")
        out.append("CSU_ROM_DIGEST is the vendor's hardware-measured SHA-384 of the "
                   "real BootROM. If any method's SHA-384 matches, that dump IS the "
                   "real BootROM bytes — cryptographic proof, not heuristic.")
        out.append("")
        out.append("| Method | SHA-384 (first 32) | Match |")
        out.append("|---|---|---|")
        any_match = False
        for _, prefix, did, name, _ in METHODS:
            r = results.get(prefix)
            if r is None or r["status"] != "ok" or not r["data"]:
                continue
            if r.get("tool_fill"):
                out.append(f"| **{did}** {name} | _(tool fill — not chip bytes)_ | — |")
                continue
            matched, computed, _expected = sha384_matches_digest(r["data"], digest_words)
            marker = "**YES ✓**" if matched else "no"
            if matched:
                any_match = True
            out.append(f"| **{did}** {name} | `{computed[:32]}…` | {marker} |")
        out.append("")
        if any_match:
            out.append("**At least one method captured the real BootROM.** "
                       "See the matching method's `.analysis.md` for the bytes.")
        else:
            out.append("No matches — every dump is either gated/fill bytes or a "
                       "different region than the digest was computed over.")
        out.append("")

    # New: per-method diagnostics for the things that matter for triage
    out.append("## Per-method diagnostics")
    out.append("")
    diag_emitted = False
    for _, prefix, did, name, _ in METHODS:
        r = results.get(prefix)
        if r is None:
            continue
        sc = r.get("sidecar", {})
        lines: list[str] = []
        if r["status"] == "aborted":
            lines.append(f"  - **Error**: {sc.get('error', '(unspecified)')}")
            if sc.get("a53_state"):
                lines.append(f"  - A53 state at abort: `{sc['a53_state']}`")
            if sc.get("a53_pc_final"):
                lines.append(f"  - A53 PC at halt: `{_coerce_pc_str(sc['a53_pc_final'])}`")
        else:
            # OK methods — only emit diag block if there's something to say
            if prefix in ("bootrom-via-csudma", "bootrom-via-aes"):
                src_d = sc.get("src_intr_decoded", "")
                dst_d = sc.get("dst_intr_decoded", "")
                if src_d or dst_d:
                    lines.append(f"  - SRC I_STS: `{sc.get('src_intr_sts','?')}` ({src_d})")
                    lines.append(f"  - DST I_STS: `{sc.get('dst_intr_sts','?')}` ({dst_d})")
                if sc.get("src_busy_final") == 1 or sc.get("dst_busy_final") == 1:
                    lines.append(f"  - **DMA still busy after poll**: "
                                 f"SRC.BUSY={sc.get('src_busy_final')} "
                                 f"DST.BUSY={sc.get('dst_busy_final')} "
                                 f"after {sc.get('poll_iters','?')} iters "
                                 f"({sc.get('poll_ms','?')} ms)")
                if sc.get("attempts_used", 1) > 1:
                    lines.append(f"  - DMA retried {sc['attempts_used']} times")
            if prefix in ("bootrom-via-a53", "bootrom-via-loader", "bootrom-via-r5"):
                if sc.get("a53_pc_final"):
                    lines.append(f"  - A53 PC at halt: `{_coerce_pc_str(sc['a53_pc_final'])}`")
                # EL3 sysregs are RESIDUAL — our payload doesn't take an
                # exception (LDP from gated memory returns 0xDEADBEEF as DATA,
                # not as a fault). These are whatever BootROM left in the
                # registers before handoff. Reported when non-zero in case
                # the values themselves are diagnostically interesting.
                esr = sc.get("esr_el3", "")
                if esr and esr not in ("0x0", "0x00000000", "(unavailable)"):
                    lines.append(f"  - ESR_EL3 = `{esr}` (residual; payload took "
                                 f"no exception — FAR=`{sc.get('far_el3','?')}` "
                                 f"ELR=`{sc.get('elr_el3','?')}`)")
                # Treat missing done_marker_ok the same as 0 (defensive) —
                # the absence of evidence is not evidence of completion.
                if not sc.get("done_marker_ok"):
                    poll_info = ""
                    if sc.get("marker_poll_ms") is not None:
                        poll_info = f" (polled {sc['marker_poll_ms']} ms)"
                    lines.append(f"  - **Done marker NOT set**{poll_info} "
                                 f"(lo=`{sc.get('done_marker_lo','?')}` "
                                 f"hi=`{sc.get('done_marker_hi','?')}`) — "
                                 f"payload did not reach completion, dump may be partial")
                elif sc.get("marker_poll_ms") is not None:
                    lines.append(f"  - Marker met after {sc['marker_poll_ms']} ms")
                # SCTLR before/after for M2. Use None as default so we can
                # tell "missing key" (suppress) from "captured-as-zero"
                # (show — that's a real EL3-FAULT signal, see _classify_
                # for_headline's EL3-FAULT detection).
                sb = sc.get("sctlr_before")
                sa = sc.get("sctlr_after")
                if sb is not None or sa is not None:
                    same = "unchanged" if sb == sa else "modified"
                    lines.append(f"  - SCTLR_EL3 before=`{sb}` "
                                 f"after=`{sa}` ({same})")
            if sc.get("chunks_failed", 0) > 0:
                lines.append(f"  - **{sc['chunks_failed']}/{sc.get('chunks_total','?')} "
                             f"chunks failed read** (filled with 0xDEADBEEF)")
            if sc.get("method_total_ms") is not None:
                ms = sc["method_total_ms"]
                lines.append(f"  - Method wall-clock: {ms} ms")
        if lines:
            out.append(f"- **{did}** {name}")
            out.extend(lines)
            diag_emitted = True
    if not diag_emitted:
        out.append("_(No anomalies to report — all methods clean.)_")
    out.append("")

    out.append("## Combined verdict")
    out.append("")
    # Only consider OK methods for the combined-verdict heuristics
    ok_results = {p: r for p, r in results.items()
                  if r is not None and r["status"] == "ok"}
    fills = {p: r["fill"] for p, r in ok_results.items()}
    n_ok = len(ok_results)
    n_aborted = sum(1 for r in results.values() if r and r["status"] == "aborted")
    n_total = len(METHODS)

    if n_ok == 0:
        out.append(f"**No methods produced bytes** ({n_aborted} aborted, "
                   f"{n_total - n_aborted} missing). See per-method diagnostics.")
        out.append("")
    else:
        all_deadbeef = all("DEADBEEF" in lbl.upper() for lbl in fills.values())
        any_code = any("code" in r["verdict"].lower() for r in ok_results.values())
        all_uniform = all(lbl != "mixed" for lbl in fills.values())

        if all_deadbeef and n_ok == n_total:
            out.append(f"**All {n_ok} methods returned all-0xDEADBEEF.** BootROM region is gated")
            out.append("at the CSU mem-AP level — even CSU DMA can't reach it from JTAG-idle.")
            out.append("The unmap is enforced inside the CSU itself, not just on outgoing paths.")
            out.append("")
            out.append("The vendor's measured hash (CSU.CSU_ROM_DIGEST_0..11, captured in the")
            out.append("baseline run's sidecar) is your only signal for this BootROM in this")
            out.append("boot state. Use it as a fingerprint for device identification.")
            out.append("")
            out.append("### Possible next steps")
            out.append("- Phase 7: SD/QSPI boot to catch BootROM while still mapped")
            out.append("- Vendor-side: request BootROM source from AMD under NDA")
            out.append("- Hardware-side: chip decap + SEM (destructive, costly)")
        elif any_code:
            code_methods = [(p, r) for p, r in ok_results.items()
                            if "code" in r["verdict"].lower()]
            out.append(f"**{len(code_methods)} of {n_total} methods captured AArch64 code.**")
            out.append("")
            for prefix, r in code_methods:
                out.append(f"- **{METHOD_ID[prefix]}** got real code: `{r['bin_path']}`")
            out.append("")
            out.append("### Recommended next steps")
            out.append("- Disassemble: `aarch64-linux-gnu-objdump -D -b binary -m aarch64 <bin>`")
            out.append("- Search known BootROM CVEs against extracted code")
        elif all_uniform:
            out.append(f"**{n_ok} of {n_total} methods returned uniform fill (varying patterns).**")
            if n_aborted:
                out.append(f"({n_aborted} aborted — see diagnostics above.)")
            out.append("")
            for prefix, r in ok_results.items():
                out.append(f"- {METHOD_ID[prefix]}: {r['fill']}")
            out.append("")
            out.append("Interpretations: 0xDEADBEEF = AXI-gated, 0x00 = uninitialized SRAM, "
                       "0xFF = erased flash.")
        else:
            out.append("Methods returned mixed results — see per-method analyses below.")
        out.append("")

    payload_methods = [p for p in ("bootrom-via-a53", "bootrom-via-loader", "bootrom-via-r5")
                       if results.get(p) and results[p]["status"] == "ok"]
    if payload_methods:
        out.append("## A53-payload completion markers")
        out.append("")
        out.append("M1 (and M2 when explicitly run) uses a payload that writes "
                   "`0xCAFEBABE0000C0DE` to 0xFFFE7000 on completion. Marker NOT "
                   "set ⇒ payload didn't reach its end, so the dump may be partial.")
        out.append("")
        for prefix in payload_methods:
            sc = results[prefix].get("sidecar", {})
            ok = sc.get("done_marker_ok")
            lo = sc.get("done_marker_lo", "?")
            hi = sc.get("done_marker_hi", "?")
            status = "OK" if ok else "NOT SET"
            out.append(f"- **{METHOD_ID[prefix]}**: marker {status} (low={lo}, high={hi})")
        out.append("")

    out.append("## Per-method full analyses")
    out.append("")
    for _, prefix, did, name, _ in METHODS:
        r = results.get(prefix)
        if r is None:
            out.append(f"- **{did}** {name}: _(no artifacts)_")
        else:
            analysis = r["bin_path"].with_suffix(".analysis.md")
            out.append(f"- **{did}** {name} — `{r['bin_path']}` / `{analysis}`")
    out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Entry points per mode
# ---------------------------------------------------------------------------

def render_aborted_analysis(json_path: Path, sidecar: dict) -> str:
    """Minimal analysis for aborted methods (A5) — they have no .bin to dump,
    but the sidecar carries all the diagnostic information we need."""
    out: list[str] = []
    out.append(f"# BootROM dump analysis — `{json_path.name}` (ABORTED)")
    out.append("")
    out.append("## Status")
    out.append("")
    out.append(f"**Method aborted**: {sidecar.get('error', '(unspecified)')}")
    out.append("")
    out.append("No `.bin` was written — payload did not complete. Diagnostic info from sidecar follows.")
    out.append("")
    out.append("## Sidecar metadata")
    out.append("")
    for k, v in sidecar.items():
        if k == "a53_pc_final":
            v = _coerce_pc_str(v)
        if isinstance(v, (list, dict)):
            v = json.dumps(v)
        out.append(f"- `{k}`: {v}")
    out.append("")
    return "\n".join(out)


def mode_analyze(args) -> int:
    bin_path: Path = args.bin
    if not bin_path.exists():
        print(f"ERROR: {bin_path} not found", file=sys.stderr)
        return 1
    data = bin_path.read_bytes()
    sidecar = None
    json_path = args.sidecar or bin_path.with_suffix(".json")
    if json_path.exists():
        try:
            sidecar = json.loads(json_path.read_text())
        except json.JSONDecodeError as exc:
            print(f"WARN: sidecar not valid JSON: {exc}", file=sys.stderr)
    report = render_analyze(bin_path, data, sidecar, ascii_bars=args.ascii)
    if args.stdout:
        sys.stdout.write(report)
    else:
        out_path = bin_path.with_suffix(".analysis.md")
        out_path.write_text(report)
        print(f"Wrote: {out_path}", file=sys.stderr)
    return 0


def results_to_json(ts: str, results: dict) -> str:
    """A7: JSON-serialized cross-method summary for downstream tooling."""
    payload = {"timestamp": ts, "methods": {}}
    digest_words = _get_digest_words_from_results(results)
    for _, prefix, did, name, _ in METHODS:
        r = results.get(prefix)
        if r is None:
            payload["methods"][did] = {"status": "missing", "name": name}
            continue
        entry: dict = {
            "name": name,
            "status": r["status"],
            "sidecar": r.get("sidecar", {}),
        }
        if r["status"] == "ok":
            entry["size_bytes"] = len(r["data"])
            entry["sha256"] = r["sha256"]
            entry["sha384"] = hashlib.sha384(r["data"]).hexdigest()
            entry["fill"] = r["fill"]
            entry["verdict"] = r["verdict"]
            if digest_words:
                matched, computed, expected = sha384_matches_digest(r["data"], digest_words)
                entry["digest_match"] = matched
        payload["methods"][did] = entry
    return json.dumps(payload, indent=2)


def mode_summary(args, *, also_analyze_each: bool = False) -> int:
    if not args.dumps_dir.exists():
        print(f"ERROR: dumps dir {args.dumps_dir} not found", file=sys.stderr)
        return 1
    ts = args.timestamp or discover_timestamp(args.dumps_dir)
    if ts is None:
        print(f"ERROR: no bootrom-*.json in {args.dumps_dir}", file=sys.stderr)
        return 1

    results = {}
    for _, prefix, _, _, _ in METHODS:
        results[prefix] = load_method(args.dumps_dir, ts, prefix)
    n_found = sum(1 for r in results.values() if r is not None)
    if n_found == 0:
        print(f"ERROR: no method artifacts for timestamp {ts}", file=sys.stderr)
        return 1

    # Optionally write per-bin analyses too (auto-detect mode)
    if also_analyze_each:
        for prefix, r in results.items():
            if r is None:
                continue
            if r["status"] == "ok":
                report = render_analyze(r["bin_path"], r["data"], r["sidecar"],
                                        ascii_bars=args.ascii)
                out_path = r["bin_path"].with_suffix(".analysis.md")
            elif r["status"] == "aborted":
                # A5: aborted methods get a minimal analysis from sidecar
                report = render_aborted_analysis(r["json_path"], r["sidecar"])
                out_path = r["json_path"].with_suffix(".analysis.md")
            else:
                continue
            out_path.write_text(report)
            print(f"Wrote: {out_path}", file=sys.stderr)

    if args.json:
        summary = results_to_json(ts, results)
        ext = "json"
    else:
        summary = render_summary(ts, results, args.dumps_dir)
        ext = "md"

    if args.stdout:
        sys.stdout.write(summary)
        if not summary.endswith("\n"):
            sys.stdout.write("\n")
    else:
        args.reports_dir.mkdir(parents=True, exist_ok=True)
        out_path = args.reports_dir / f"bootrom-summary-{ts}.{ext}"
        out_path.write_text(summary)
        print(f"Wrote: {out_path}  ({n_found}/{len(METHODS)} methods)", file=sys.stderr)
        # Also print the headline to stdout so anyone watching the OpenOCD
        # auto-run gets the at-a-glance summary without having to open a file.
        if not args.json:
            print("")
            print(render_headline(ts, results, args.dumps_dir))
            print("")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--dumps-dir", type=Path, default=Path("dumps"),
                    help="Directory containing bootrom-*.bin/json (default: dumps/)")
    ap.add_argument("--reports-dir", type=Path, default=Path("reports"),
                    help="Where to write summary (default: reports/)")
    ap.add_argument("--timestamp", "-t", default=None,
                    help="Specific timestamp set (YYYY-MM-DD-HHMMSS)")
    ap.add_argument("--stdout", action="store_true",
                    help="Print to stdout instead of writing files")
    ap.add_argument("--json", action="store_true",
                    help="Emit summary as JSON instead of markdown (A7)")
    ap.add_argument("--ascii", action="store_true",
                    help="Use ASCII bar chart for per-region entropy (A6)")

    sub = ap.add_subparsers(dest="mode", required=False)

    ap_an = sub.add_parser("analyze", help="Analyze one .bin")
    ap_an.add_argument("bin", type=Path, help="Path to bootrom-*.bin")
    ap_an.add_argument("--sidecar", type=Path, default=None,
                       help="Sidecar JSON path (default: <bin>.json)")

    sub.add_parser("summary", help="Cross-method summary only")

    args = ap.parse_args()

    if args.mode == "analyze":
        return mode_analyze(args)
    if args.mode == "summary":
        return mode_summary(args, also_analyze_each=False)
    # No subcommand: auto-detect — write all per-bin analyses + the summary
    return mode_summary(args, also_analyze_each=True)


if __name__ == "__main__":
    sys.exit(main())
