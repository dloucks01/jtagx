#!/usr/bin/env python3
"""
firmware-id.py — identify the OS / RTOS / bootloader in a JTAG-extracted dump, and map its VERSION to
a set of known-CVE classes. The semantic step after dump-triage (what container) and dram-secrets
(what secrets): "what is running, what version, and what published bugs does that version carry?".

    tools/firmware-id.py dumps/os-live.bin
    tools/firmware-id.py dumps/flash.bin --json

Offline, read-only. Banner-based (honest: it reads the version string the firmware prints); the CVE map
gives version-gated CLASSES to verify, not a claim the exact build is exploitable.
"""
import argparse
import json
import re
import sys


def _ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3]) if s else ()


# banner regexes → (os-name, version-extractor group)
BANNERS = [
    ("Linux kernel", rb"Linux version (\d+\.\d+(?:\.\d+)?)"),
    ("U-Boot",       rb"U-Boot (\d{4}\.\d{2}(?:\.\d+)?)"),
    ("VxWorks",      rb"VxWorks(?:[^\d]{0,12}(\d+\.\d+))?"),
    ("FreeRTOS",     rb"FreeRTOS(?:[ _]Kernel)?[ V]*?(\d+\.\d+(?:\.\d+)?)"),
    ("Zephyr",       rb"Zephyr(?:[^\d]{0,12}(\d+\.\d+(?:\.\d+)?))?"),
    ("ThreadX",      rb"(?:ThreadX|Azure RTOS)(?:[^\d]{0,12}(\d+\.\d+))?"),
    ("BusyBox",      rb"BusyBox v(\d+\.\d+\.\d+)"),
    ("Das U-Boot",   rb"Das U-Boot"),
]

# version-gated CVE CLASSES — grounded, well-known. `when` takes the parsed version tuple.
CVE_MAP = {
    "Linux kernel": [
        (lambda v: v and v < (4, 8, 3),  "CVE-2016-5195 (Dirty COW)", "COW race → local root; pre-4.8.3"),
        (lambda v: v and (5, 8) <= v < (5, 16, 11), "CVE-2022-0847 (Dirty Pipe)",
         "pipe page-cache write → arbitrary file overwrite / root; 5.8–5.16.11"),
        (lambda v: v and v < (5, 9),  "old-kernel class", "EOL kernel: many net/driver/eBPF LPEs — audit the exact build"),
    ],
    "VxWorks": [
        (lambda v: True, "URGENT/11 (CVE-2019-12255…12263)", "IPnet TCP/IP RCE class (VxWorks 6.5–7); verify the IPnet version"),
    ],
    "U-Boot": [
        (lambda v: True, "U-Boot CVE class", "e.g. CVE-2022-30767 (NFS), CVE-2022-33967 (squashfs), env/fdt parsing — version-gate on the exact release"),
    ],
    "BusyBox": [
        (lambda v: v and v < (1, 33, 1), "BusyBox CVE class", "pre-1.33.1: awk/unlzma/etc. memory-safety CVEs (CVE-2021-42373…42386)"),
    ],
    "FreeRTOS": [
        (lambda v: v and v < (10, 4, 3), "FreeRTOS-Plus-TCP CVE class",
         "pre-10.4.3: the AWS/FreeRTOS-Plus-TCP RCE/OOB set (CVE-2021-31571…31572, 32020…32023) — verify the +TCP version"),
    ],
    "Zephyr": [
        (lambda v: v and v < (3, 1), "Zephyr CVE class",
         "pre-3.1: net/USB/BT stack memory-safety CVEs (e.g. CVE-2021-3625 BT, IP-stack OOB) — version-gate the exact subsystem"),
    ],
    "ThreadX": [
        (lambda v: True, "ThreadX / NetX CVE class",
         "Azure RTOS NetX Duo IP/DNS/DHCP parsing CVEs (2023-era) — confirm the NetX version and enabled protocols"),
    ],
}


def identify(data):
    found = []
    for name, rx in BANNERS:
        m = re.search(rx, data)
        if not m:
            continue
        ver = ""
        if m.groups() and m.group(1):
            ver = m.group(1).decode("latin1")
        found.append({"os": name, "version": ver or "?", "_vt": _ver(ver)})
    # de-dup by os (keep the first/most-specific)
    seen, uniq = set(), []
    for f in found:
        if f["os"] in seen:
            continue
        seen.add(f["os"]); uniq.append(f)
    findings = []
    for f in uniq:
        for pred, cve, note in CVE_MAP.get(f["os"], []):
            try:
                hit = pred(f["_vt"])
            except Exception:
                hit = False
            if hit:
                findings.append({"os": f["os"], "version": f["version"], "cve": cve, "note": note})
    for f in uniq:
        f.pop("_vt", None)
    return uniq, findings


def main():
    ap = argparse.ArgumentParser(description="Identify OS/RTOS/bootloader in a dump → known-CVE classes.")
    ap.add_argument("dump")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    try:
        data = open(a.dump, "rb").read()
    except OSError as e:
        sys.exit(f"error: cannot read {a.dump}: {e.strerror}")
    ids, findings = identify(data)
    if a.json:
        print(json.dumps({"identified": ids, "cve_classes": findings}, indent=2))
        return 0
    print(f"# firmware id — {a.dump}")
    if not ids:
        print("  no OS/RTOS/bootloader banner found (packed/encrypted? run dump-triage.py first)")
        return 0
    for f in ids:
        print(f"  {f['os']:14s} {f['version']}")
    if findings:
        print("\nversion-gated CVE classes to verify (not a claim the exact build is exploitable):")
        for f in findings:
            print(f"  [{f['os']} {f['version']}] {f['cve']}\n         {f['note']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
