# 30 — The Authenticated-Debug Frontier (SDC-600 / RISC-V debug security)

Reference for the **next trust boundary above an on/off debug gate**, and how the posture layer
represents it. Written 2026-08-14 as part of the non-physical SOTA gap-close (plan Phase 2).

## Why this matters

Our founding thesis is "on an unprovisioned board the OPEN DAP *is* the trust boundary" — the CSU
`JTAG_DAP_CFG` / `JTAG_SEC` gates are just registers behind that DAP (see `docs/14`, the
`open-dap-thesis` hypothesis). That is true for the **on/off gate** model: debug is either enabled or
disabled (optionally eFuse-frozen).

Hardened 2026 silicon is moving past that to **authenticated debug** — the debugger must present a
signed credential before invasive debug is granted:

- **ARM CoreSight SDC-600** — a dedicated Secure Debug Channel that exchanges a **debug certificate**
  through the DAP to authenticate debug access; integrates with the platform's security IP and ADIv6.
  (arm.com/products/silicon-ip-system/coresight-debug-trace/sdc-600)
- **RISC-V External Debug Security Extension** — ratified **Feb 2025**; the Debug Module gains
  `authenticated` / `authbusy` / `authdata` registers so the DM can require an access key /
  certificate exchange (bidirectional auth is an active research direction). (github.com/riscv/riscv-debug-spec)

This changes the posture question from *"is the DAP shut?"* to *"is invasive debug **authenticated**,
and is the credential actually enrolled?"*

## How the posture layer represents it

A single cross-arch posture key, `debug_auth`, with three states:

| `debug_auth` | meaning | our reading |
|---|---|---|
| `none` | classic on/off gate (DBGEN/SPIDEN/JTAG_SEC). The ZCU102 and every board we've profiled. | the `open-dap-thesis` world — a software lever or eFuse decides everything |
| `present` | the part **implements** authenticated debug (SDC-600 / RISC-V debug-auth) but **no** debug certificate/key is enrolled | **decorative** — same failure mode as an unprovisioned FlashLock |
| `provisioned` | a debug certificate/key is enrolled and enforced | the gate is real; attack shifts to the **debug key** and the un-authenticated leakage below it |

The `jtagx.weakness` hypotheses that fire on it (distinct from CVEs — implementation-review):

- **`auth-debug-unprovisioned`** (HIGH, `present`) — capable but not enrolled ⇒ full invasive debug to
  anyone. The common real-world miss (opt-in security left off).
- **`debug-cert-trust`** (MED, `provisioned`) — the whole scheme reduces to **debug-key management**;
  a leaked/HSM-compromised debug signing key re-opens every device that trusts it (fleet-wide SPOF).
- **`secure-debug-noninvasive-leak`** (LOW, `present`/`provisioned`) — IDCODE / boundary-scan and often
  non-invasive debug (NIDEN / trace) stay answerable **below** the authenticated channel: recon and some
  observation survive SDC-600. It is not a full blackout.

## Honest scope

We have **no SDC-600 / RISC-V-debug-auth board on the bench**, so `debug_auth` is set by the operator
(`unlock-engine.py --debug-auth present|provisioned`, or a profile/GUI toggle), not read from silicon
yet. When such a board arrives, the live detection is: probe for the SDC-600 APB component ID / the
RISC-V DM `authenticated` bit, and set `debug_auth` accordingly. The *analysis* (what the three states
imply, and the ranked response) is complete and testable today; only the live read is deferred — the
same discipline as the HW-UNVALIDATED board profiles.

## References

- ARM CoreSight SDC-600 Secure Debug Channel — arm.com (product + developer blog).
- RISC-V External Debug Security Extension — github.com/riscv/riscv-debug-spec (ratified 2025-02-20).
- ADIv6 Debug Interface Architecture — ARM (authenticated/secure debug scope).
- Cross-refs: `docs/14` (ZynqMP debug gates), `docs/15` (prior research), `jtagx/weakness.py`
  (`auth-debug-unprovisioned` / `debug-cert-trust` / `secure-debug-noninvasive-leak`).
