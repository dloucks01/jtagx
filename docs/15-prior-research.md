# Prior Security Research — Zynq UltraScale+ / ZynqMP & JTAG

A survey of **published, externally-sourced** security research and disclosed
vulnerabilities relevant to the AMD/Xilinx Zynq UltraScale+ (ZU+) MPSoC and to JTAG
attacks on it. This is a literature map to (a) avoid re-discovering known issues, (b)
anchor our enumeration/posture-detector against the real published threat surface, and
(c) record what an *enforcing* (provisioned) board is actually known to be vulnerable to.

**Scope note.** Everything here is from third-party publications/advisories (cited
inline). None of it was reproduced by this project. Where a finding targets a *different*
device family (e.g. 7-Series rather than ZU+), that is flagged — the lineage matters but
the applicability does not always carry over. Our own empirical results live in
`docs/14` (§ "Empirical vs vendor-documented") and the `project_*` memory notes; this
doc is deliberately the **outside** view.

---

## At-a-glance

| # | Work | Year | Target | Class | ID | Hits ZU+/ZynqMP? | Reachable on our dev board? |
|---|------|------|--------|-------|----|------------------|------------------------------|
| 1 | F-Secure/Inverse Path — "Encrypt Only" secure-boot bypass | 2019 | ZU+ MPSoC BootROM + FSBL | Boot/partition header auth gap | **CVE-2019-5478** | **Yes** (all ZU+ P/Ns) | N/A — requires *Encrypt-Only* secure boot enabled (ours is off) |
| 2 | JustSTART (Ender, Hahn, Fyrbiak, Moradi, Paar) | 2024 | UltraScale(+) **PL config engine** | RSA authentication bypass | **CVE-2023-20570** | **Yes** (UltraScale+ fabric incl. ZynqMP PL) | N/A — requires PL bitstream auth enabled |
| 3 | "A Cautionary Note…" (Ender, Leander, Moradi, Paar) | 2022 | UltraScale(+) bitstream AES-GCM + RSA | 4 attacks: AES/GHASH + auth-downgrade | (no CVE; config-dependent) | **Yes**, *if mis-configured* | N/A — requires PL bitstream encryption |
| 4 | Starbleed / "The Unpatchable Silicon" (Ender, Moradi, Paar) | 2020 | **7-Series** bitstream encryption | Decryption oracle (WBSTAR readout) | (7-Series) | **No** — 7-Series only; ZU+ hardened against it | N/A |
| 5 | Hettwer, Leger, Fennes, Gehrer, Güneysu — SCA of ZU+ encryption engine | 2021 | **ZU+** AES-256 bitstream-decrypt engine | EM side-channel + deep learning | (no CVE) | **Yes** (ZU+ specifically) | Out of scope — needs EM/SCA hardware (we have none) |
| 6 | Swierczynski et al — "Break Secure Boot on FPGA SoCs through Malicious Hardware" | 2017 | FPGA-SoC (Zynq-class) | Bitstream Trojan → secure-boot compromise | (eprint 2017/625) | Lineage (7-Series-era SoC) | N/A |
| 7 | Voltage fault-injection on Zynq (privilege escalation) | 2016+ | **Zynq-7000** (7010) BL1 | Glitch → skip checks / corrupt instr. | (academic) | Lineage only — *not* ZU+ | Out of scope — no glitch HW; non-destructive only |
| 8 | AMD-SB-8017 — ATF missing Secure flag | (AMD bulletin) | ZynqMP **Arm Trusted Firmware** | Missing TZ Secure flag → conf/integrity loss | **AMD-SB-8017** | **Yes** (software, patchable) | Software issue — not our JTAG-idle target |

---

## 1. CVE-2019-5478 — "Encrypt Only" secure-boot bypass (F-Secure / Inverse Path, 2019)

The most directly relevant *logic* vulnerability for ZynqMP secure boot. Disclosed by
the Inverse Path team at F-Secure (advisory **FSC-HWSEC-VR2019-0001**), confirmed on a
**ZCU104** eval kit; "all Xilinx Zynq UltraScale+ P/Ns are believed to be vulnerable."

**Two flaws, both under the single CVE-2019-5478:**

- **Flaw 1 — boot header (BootROM), UNPATCHABLE.** In *Encrypt-Only* boot mode the ZU+
  internal BootROM does **not authenticate the boot-header fields** — including the FSBL
  execution/start address. An attacker who can rewrite the boot device (e.g. the SD card)
  can redirect execution and gain arbitrary code execution (ROP-style). Because the flaw
  is in mask ROM, "only a new silicon revision" can fix it.
- **Flaw 2 — partition header (FSBL), patchable in principle.** The FSBL likewise does
  **not authenticate partition-header destination addresses**. The destination can be
  pointed at the (attacker-modified) partition header itself, which then carries
  executable instructions.

**Root cause class:** in Encrypt-Only mode the design encrypts payloads but leaves the
*control metadata* (boot/partition headers) unauthenticated → confidentiality without
integrity → the classic "encryption ≠ authentication" trap.

**Vendor remediation:** use **Hardware Root of Trust (HWRoT)** boot mode instead —
HWRoT authenticates the boot and partition headers (RSA). I.e. the fix is a *mode change*
the integrator must make, not a silicon patch.

**Relevance to us:** This is exactly a case our **posture detector should flag**. The
distinction "Encrypt-Only vs HWRoT" is observable from the eFuse/`SEC_CTRL` policy
(`RSA_EN`, `ENC_ONLY`) and the boot-header `encryptionKeySource` — see `docs/14` §6/§7
and `docs/11`. On a hardened target, an enumeration that reports *Encrypt-Only enabled,
RSA_EN=0* is reporting a board exposed to CVE-2019-5478. Our own dev board has secure
boot off entirely, so the CVE is not *exercisable* here, but the catalog should call it
out as a checklist item.

Sources: [F-Secure advisory](https://github.com/f-secure-foundry/advisories/blob/master/Security_Advisory-Ref_FSC-HWSEC-VR2019-0001-Xilinx_ZU+-Encrypt_Only_Secure_Boot_bypass.txt) ·
[CVE-2019-5478 (Tenable)](https://www.tenable.com/cve/CVE-2019-5478) ·
[AllAboutCircuits writeup](https://www.allaboutcircuits.com/news/xilinx-security-flaw-zinc-ultrascale-encrypt-only-secure-boot/)

## 2. CVE-2023-20570 — "JustSTART" RSA authentication bypass (Ender et al., 2024)

*JustSTART: How to Find an RSA Authentication Bypass on Xilinx UltraScale(+) with
Fuzzing* — Maik Ender, Felix Hahn, Marc Fyrbiak, Amir Moradi, Christof Paar (MPI-SP
Bochum + TU Darmstadt), **IACR TCHES** (arXiv:2402.09845).

**What it is:** A new **unpatchable** vulnerability in the **UltraScale(+) FPGA
configuration engine** (the control plane that loads the PL bitstream) that **bypasses
RSA authentication**, letting an attacker load trojanized/modified bitstreams. Found by
fuzzing the opaque configuration engine with their `ConFuzz` framework — the same
program-the-config-registers surface that Starbleed lives in. The work also rediscovered
Starbleed and surfaced undocumented config-engine behavior (crash-to-unresponsive states,
an undocumented RSA test mode).

**Attack surface:** the configuration interfaces (JTAG/ICAP/SelectMAP/SPI/BPI) that drive
the config-engine registers (sync word `0xAA995566`, type-1/type-2 packets to registers
like `FDRI`/`STAT`/`CMD`/`WBSTAR`/`BOOTSTS`). This is the **PL/fabric** trust boundary,
distinct from the **PS** secure-boot ROM in §1 — but ZynqMP contains an UltraScale+ PL,
so the fabric of a ZynqMP is in scope.

**Mitigation:** the attack is prevented when **both** bitstream *encryption* **and**
*authentication* are enabled (auth-only is bypassable). Since the root cause is in the
hardware config engine, there is no patch — only the secure-configuration recommendation.

**Relevance to us:** Reinforces a posture-checklist item for any board that uses the PL:
"RSA-auth-only on the bitstream is not sufficient — require encryption + authentication."
Not exercisable on our board (no authenticated bitstream in play), and the PL config
engine is a different target than our PS/CSU JTAG-idle work — but worth knowing the fabric
side has a standing unpatchable break.

Sources: [arXiv:2402.09845](https://arxiv.org/pdf/2402.09845) ·
[TCHES PDF](https://tches.iacr.org/index.php/TCHES/article/download/11435/10940/11721) ·
CVE-2023-20570

## 3. "A Cautionary Note on Protecting Xilinx' UltraScale(+) Bitstream Encryption & Authentication Engine" (Ender, Leander, Moradi, Paar, 2022)

FCCM 2022 / IEEE ([dblp ELMP22](https://dblp.org/rec/conf/fccm/EnderLMP22.html)). Presents
**four** attacks against the UltraScale(+) bitstream-protection engine:

- **Two attacks on AES + the novel GHASH-based checksum** — showing the Starbleed-style
  malleability break is *still possible on UltraScale(+)* by defeating the periodic
  `X-GHASH` checksum that Xilinx added (AES-GCM + GHASH-of-8-word-blocks).
- **Two authentication-downgrade attacks** — forcing the engine off the strong-auth path.

**Crucial caveat:** these work when the device is configured **outside Xilinx's
recommended settings**. Xilinx only *recommends* configurations not affected by the
attacks, so a careful integrator is "largely secure" — but the large config-option space
makes misconfiguration plausible (the paper frames it as a Security-Misconfiguration risk).

**Relevance to us:** Same theme as §2 — the *secure-vs-misconfigured* line is exactly what
enumeration should detect. A ZU+ that enables encryption but in a non-recommended mode is
a real-world target.

Source: [CASA RUB](https://casa.rub.de/en/research/publications/detail/a-cautionary-note-on-protecting-xilinx-ultrascale-bitstream-encryption-and-authentication-engine) ·
[IEEE Xplore 9786118](https://ieeexplore.ieee.org/document/9786118/)

## 4. Starbleed — "The Unpatchable Silicon: A Full Break of the Bitstream Encryption of Xilinx 7-Series FPGAs" (Ender, Moradi, Paar, USENIX Security 2020)

The foundational FPGA-config-engine break. Turns the FPGA into a **decryption oracle**:
flipping ciphertext bits exploits AES-CBC/CTR malleability so that, when the integrity
check finally fails and the device resets, secret fabric content has been diverted into
the **`WBSTAR`** register — which is **not cleared on reset** and can then be read out,
leaking the full bitstream contents.

**Applicability:** **7-Series only.** UltraScale(+) was independently hardened (AES-GCM +
RSA + GHASH checksum), so Starbleed-as-is does *not* break ZU+ — but §3/§2 show the
*spirit* of the attack survives on UltraScale(+) under weaker configs. Listed here because
it is the lineage every later ZU+ config-engine result builds on, and the WBSTAR-not-
cleared-on-reset pattern is a useful template for reset-residue thinking.

Source: [USENIX Sec 2020 PDF](https://www.usenix.org/system/files/sec20-ender.pdf) ·
[arXiv:2105.13756](https://arxiv.org/pdf/2105.13756)

## 5. Side-Channel Analysis of the ZU+ Encryption Engine (Hettwer, Leger, Fennes, Gehrer, Güneysu, TCHES 2021)

The only public **side-channel** study targeting the **ZU+ specifically** (Robert Bosch +
Ruhr University Bochum; TCHES 2021 vol 1, pp 279–304). First public SCA of the ZU+ AES-256
bitstream-decryption engine.

- **Technique:** black-box reverse-engineering of the AES hardware via **EM measurements
  taken from a decoupling capacitor** of the power supply, then a sophisticated
  methodology attacking the **first five AES rounds** of the **256-bit** key, using
  **deep-learning-based** correlation/evaluation methods.
- **Result:** they did **not** recover all key bytes, but characterized the leakage well
  enough to give **concrete recommendations for the "key rolling" parameter** — ZU+'s
  protocol countermeasure that limits how many data blocks are encrypted under one key
  (configuration image split into chunks, each chunk's key stored in the previous chunk).
- **Why it matters:** knowledge of the bitstream key enables IP cloning/reverse-eng;
  Xilinx added RSA-before-decrypt (HWRoT) *and* key rolling to ZU+ precisely to resist the
  earlier CPA breaks (Moradi et al. on Virtex-4/5, reduced to 2⁸ complexity, applicable
  across 5/6/7-Series).

**Relevance to us:** Targets the **PL bitstream AES key**, which is a *different* secret
than the **family/gray key** the project's headline mission cares about — and it requires
**EM/SCA lab hardware we explicitly do not use** (constraint: no DPA/EM/glitch). It does,
however, confirm the broader truth in `docs/14` §5: durable keys on ZU+ are recoverable
*only* through physical side channels, not via JTAG/software — consistent with our
"family key is hardware-only" disposition.

Source: [TCHES PDF](https://tches.iacr.org/index.php/TCHES/article/download/8735/8335/5461)

## 6. "How to Break Secure Boot on FPGA SoCs through Malicious Hardware" (Swierczynski et al., CHES 2017)

Demonstrates compromising secure boot on FPGA-SoCs by embedding **malicious hardware
(a bitstream Trojan)** in the FPGA fabric, which then subverts the boot/crypto path. A
hardware-Trojan / supply-chain-style result rather than a remote logic bug. Lineage:
7-Series-era SoC; the technique generalizes to any SoC where untrusted bitstreams reach
the fabric. Out of our scope (we don't author malicious bitstreams; non-destructive only)
but it is part of the ZU+-relevant threat catalog.

Source: [eprint 2017/625](https://eprint.iacr.org/2017/625.pdf)

## 7. Voltage / fault-injection on Zynq (lineage; not ZU+-specific)

Public fault-injection work on the **Zynq-7000** family (e.g. reported 2016 voltage-FI
privilege-escalation against a **Zynq-7010** BL1 bootloader, corrupting instructions to
gain code execution) and general voltage-glitch methodology (e.g.
[arXiv:1903.08102](https://arxiv.org/pdf/1903.08102), Synacktiv's
[FI primer](https://www.synacktiv.com/en/publications/how-to-voltage-fault-injection)).
Glitching can **skip signature checks** during secure boot.

**State of the ZU+-specific public record:** sparse. Most published glitch results are on
Zynq-7000 / other ARM SoCs, not ZynqMP. ZU+ adds triple-redundant CSU/PMU MicroBlazes and
tamper monitors (`docs/14` §3 tamper block `0xFFCA5000`) that raise the bar. **Explicitly
out of scope for this project** — the standing constraint is non-destructive, no
ChipWhisperer/glitch/DPA. Recorded so the gap is acknowledged, not pursued.

Sources: [arXiv:1903.08102](https://arxiv.org/pdf/1903.08102) ·
[Synacktiv](https://www.synacktiv.com/en/publications/how-to-voltage-fault-injection)

## 8. AMD/Xilinx vendor advisories

- **AMD-SB-8017 — "Missing Use of the Secure Flag in Zynq UltraScale+ SoC Arm Trusted
  Firmware."** A software issue in ZynqMP **ATF** (not the BootROM/CSU): a missing
  TrustZone Secure flag, rated **High**, impact loss of confidentiality + integrity.
  Patchable in firmware. Not a JTAG-idle target, but part of the platform's secure-boot
  chain. Source:
  [amd.com/.../amd-sb-8017](https://www.amd.com/en/resources/product-security/bulletin/amd-sb-8017.html)
- **CVE-2019-5478 / AR#72588** — the Encrypt-Only bypass (§1); Xilinx answer record
  AR#72588 carries the vendor response (use HWRoT).
- **AMD Design Security** landing + the **"Zynq UltraScale+ MPSoC Security Features"**
  wiki are the canonical vendor descriptions of the intended posture (CSU, JTAG security
  gates, secure boot modes) — useful as the "what it should look like when ON" reference
  that our posture detector compares against.
  Sources:
  [Design Security](https://www.amd.com/en/products/adaptive-socs-and-fpgas/technologies/design-security.html) ·
  [Security Features wiki](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18841708/Zynq+Ultrascale+MPSoC+Security+Features) ·
  [JTAG Security Gates (UG1085)](https://docs.amd.com/r/en-US/ug1085-zynq-ultrascale-trm/JTAG-Security-Gates)

## 9. JTAG / DAP debug-security landscape

No public **DAP-authentication-bypass** result specific to ZynqMP surfaced in this sweep.
The relevant facts found:

- On a **provisioned** ZU+, JTAG is **disabled by default** when an authenticated
  (`RSA_EN`) or encrypted image is booted; re-enabling requires writing the relevant
  CSU/eFuse registers and there is "no built-in system to enable it" once disabled (AMD
  community + UG1085 JTAG Security Gates). This matches `docs/14` §10.
- The general JTAG threat model is well understood and not novel: a low-cost ARM JTAG
  probe + OpenOCD on an **open** DAP gives full core/memory access and arbitrary code
  execution. This is *exactly* the posture of our dev board — and the **closed AMD PSIRT
  case** established that on an unprovisioned dev board the open DAP is **expected**, not a
  vulnerability (the open JTAG DAP *is* the trust boundary — see
  `project_findings_retracted`).
- Adjacent prior art on the *defensive* side: secure-JTAG via challenge-response / PKC
  authentication (multiple patents), and a comparable real-world finding on a *different*
  vendor — Google's "Kioxia: Open JTAG Debug Port" advisory (GHSA-3hh8-94j4-62rh) — as an
  example of "shipped product left JTAG open" being treated as a finding *when the device
  was supposed to be locked.* The discriminator is always *provisioning state*, which is
  the whole point of our enumeration.

Sources:
[AMD community — protecting JTAG](https://adaptivesupport.amd.com/s/question/0D54U00006cpHIjSAM/zynqmp-is-there-a-way-to-protect-the-jtag-like-accessing-the-jtag-with-password-after-disabling-the-jtag) ·
[Google Kioxia open-JTAG advisory](https://github.com/google/security-research/security/advisories/GHSA-3hh8-94j4-62rh)

---

## What this means for the project

1. **Every disclosed *logic* vuln (1–3) targets an ENFORCING device and a config our dev
   board does not have on.** None are exercisable on board 210308BD8D4D (secure boot off,
   no bitstream auth). Their value to us is as **posture-detector checks — now implemented**:
   - `rule_cve_2019_5478_encrypt_only_bypass` (CRITICAL) — Encrypt-Only (`ENC_ONLY=1`) without
     HWRoT (`RSA_EN=0`), the §1 vuln.
   - `rule_auth_only_without_encryption` (MAJOR) — authenticated-but-unencrypted boot image
     (the §2-3 class), via `CSU_STATUS` or the boot-header `encryptionKeySource`.
   - `rule_pl_bitstream_unprotected` (CRITICAL/MAJOR) — per-PL-partition encrypt/auth gap,
     fed by the boot-image PHT walk (live `::BH_ADDR` in `enumerate.tcl` or offline
     `tools/parse-bootimage.py`). This is the direct §2 JustSTART target.
   All abstain on the open dev board; they light up on a hardened/misconfigured part.
2. **Durable-key extraction is a physical-side-channel game (4–5), which we have ruled
   out.** The published ZU+ key result (Hettwer) is EM-SCA against the *PL bitstream* key,
   not the family/gray key, and needs lab hardware. This is fully consistent with our
   standing disposition that the family key is hardware-only and the headline
   "dump family/gray key over JTAG" goal is infeasible under our constraints.
3. **No ZynqMP JTAG/DAP-bypass exists in the public record** — and the open DAP on an
   unprovisioned part is expected behavior, matching the retracted-findings conclusion.
   The genuinely novel-adjacent thing we *did* observe (PUF controller ungated from DAP-NS,
   `docs/14` §4) has no public analogue in this sweep; it remains the most
   disclosure-interesting empirical result, dormant on this die (CHASH=0).
4. **The Bochum/CASA group (Ender, Moradi, Paar, Fyrbiak) owns this space.** For ongoing
   monitoring, watch their publication feed (CASA RUB / MPI-SP) and the AMD product-
   security bulletin list — that is where the next ZU+ break will appear.

## Sources (consolidated)

- F-Secure advisory FSC-HWSEC-VR2019-0001 (CVE-2019-5478): https://github.com/f-secure-foundry/advisories/blob/master/Security_Advisory-Ref_FSC-HWSEC-VR2019-0001-Xilinx_ZU+-Encrypt_Only_Secure_Boot_bypass.txt
- CVE-2019-5478 (Tenable): https://www.tenable.com/cve/CVE-2019-5478
- JustSTART / CVE-2023-20570 — arXiv:2402.09845: https://arxiv.org/pdf/2402.09845 ; TCHES: https://tches.iacr.org/index.php/TCHES/article/download/11435/10940/11721
- A Cautionary Note… (FCCM 2022, ELMP22): https://casa.rub.de/en/research/publications/detail/a-cautionary-note-on-protecting-xilinx-ultrascale-bitstream-encryption-and-authentication-engine ; https://ieeexplore.ieee.org/document/9786118/
- Starbleed / Unpatchable Silicon (USENIX Sec 2020): https://www.usenix.org/system/files/sec20-ender.pdf ; arXiv:2105.13756: https://arxiv.org/pdf/2105.13756
- SCA of ZU+ Encryption Engine (TCHES 2021): https://tches.iacr.org/index.php/TCHES/article/download/8735/8335/5461
- Break Secure Boot on FPGA SoCs through Malicious Hardware (CHES 2017): https://eprint.iacr.org/2017/625.pdf
- Injecting Software Vulnerabilities with Voltage Glitching: https://arxiv.org/pdf/1903.08102 ; Synacktiv FI primer: https://www.synacktiv.com/en/publications/how-to-voltage-fault-injection
- AMD-SB-8017 (ATF Secure flag): https://www.amd.com/en/resources/product-security/bulletin/amd-sb-8017.html
- AMD Design Security: https://www.amd.com/en/products/adaptive-socs-and-fpgas/technologies/design-security.html
- Zynq UltraScale+ MPSoC Security Features (wiki): https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18841708/Zynq+Ultrascale+MPSoC+Security+Features
- UG1085 JTAG Security Gates: https://docs.amd.com/r/en-US/ug1085-zynq-ultrascale-trm/JTAG-Security-Gates
- Google Kioxia open-JTAG advisory (GHSA-3hh8-94j4-62rh): https://github.com/google/security-research/security/advisories/GHSA-3hh8-94j4-62rh
