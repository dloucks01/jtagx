# Whitepaper Series — JTAG Enumeration for Security Research on the Zynq UltraScale+ MPSoC

A three-volume technical report on JTAG enumeration of the Zynq UltraScale+
(ZynqMP) family. The series is a **characterization reference**: what the platform
exposes over JTAG, how to read each security control, and — using the ZCU102 dev
board as a known all-open baseline — what those same controls look like on another
(hardened) target board, with the attacker playbook each state enables.

Companion to [`../11-enumerated-attributes.md`](../11-enumerated-attributes.md) (the
per-attribute catalog) and [`../05-enumeration-tool.md`](../05-enumeration-tool.md)
(the tool manual).

## Volumes

| Volume | Title | Markdown source | PDF | DOCX | Pages |
|---|---|---|---|---|---|
| 1 | Foundation — context, threat model, ZynqMP and JTAG security background | [`01-foundation.md`](01-foundation.md) | [`01-foundation.pdf`](01-foundation.pdf) | [`01-foundation.docx`](01-foundation.docx) | 11 |
| 2 | Methodology and Workflow — design principles + hands-on walkthrough + ZCU102 case study | [`02-workflow.md`](02-workflow.md) | [`02-workflow.pdf`](02-workflow.pdf) | [`02-workflow.docx`](02-workflow.docx) | 13 |
| 3 | What Enumeration Reveals — indicator categories with paired offensive use cases, future work, references | [`03-enumeration-reveals.md`](03-enumeration-reveals.md) | [`03-enumeration-reveals.pdf`](03-enumeration-reveals.pdf) | [`03-enumeration-reveals.docx`](03-enumeration-reveals.docx) | 17 |

A **combined PDF with all three volumes** is at
[`whitepaper-combined.pdf`](whitepaper-combined.pdf) (39 pages, 860 KB).

Total: ~41 pages across three documents (each readable in 20-30
minutes).

## Companion: lab setup and test architecture

| File | Title | Purpose |
|---|---|---|
| [`lab-setup.md`](lab-setup.md) | Lab Setup and Test Architecture | Hardware shopping list, software install, USB topology, change-gate validation pipeline, reproduction checklist |
| [`lab-setup.pdf`](lab-setup.pdf) | (PDF, 12 pages) | |
| [`lab-setup.docx`](lab-setup.docx) | (DOCX) | |

Different audience from the main volumes — focused on standing up
the lab and operating the toolchain, not on what the enumeration
reveals.

## Format choice

| Format | Best for |
|---|---|
| **PDF** | Distribution, archival, printing, citing |
| **DOCX** | Reviewer comments / track changes / in-line edits |
| **Markdown** | Editing the source of truth — regenerate PDF and DOCX from it |

The markdown files are the source of truth. PDFs and DOCXs are
build outputs. To regenerate after editing:

```
cd docs/whitepaper
pandoc --defaults=pandoc-defaults.yaml -o 01-foundation.pdf 01-foundation.md
# repeat per volume, plus the combined build
```

## Figures

All diagrams live under [`figures/`](figures/) as both Graphviz
`.dot` source files and rendered `.png` images:

| File | Used in |
|---|---|
| `01-zynqmp-block.png` | Vol 1 §3.1 — subsystem overview |
| `02-jtag-chain.png` | Vol 1 §3.4 — JTAG chain composition |
| `03-boot-flow.png` | Vol 1 §3.3 — boot flow |
| `04-hardening-continuum.png` | Vol 1 §2.3 — hardening continuum |
| `05-pipeline.png` | Vol 2 §1.1 — three-layer pipeline |
| `06-qemu-sot.png` | Vol 2 §1.2 — QEMU as source of truth |
| `07-workflow-stages.png` | Vol 2 §2 — four-stage workflow |

To regenerate after editing a `.dot` file:

```
cd figures
dot -Tpng -Gdpi=150 -Gsplines=ortho FILE.dot -o FILE.png
```

## Audience

Internal test team primary, with a tone bridging academic and
public-technical. Not for public distribution.

## What's deliberately out of scope

- Defensive recommendations / hardening checklists (deferred — future
  mitigations companion)
- Reproducibility, hardware setup, test architecture (separate
  `lab-setup.md` companion when written)
- Comparison to alternative tools (vendor or commercial)
- Limitations section (the work has limitations — they're
  acknowledged in flow rather than enumerated as a dedicated section)
- Ethics, authorization, responsible disclosure caveats

## Related project documents

For deeper register-level reference and tool documentation:

- `../05-enumeration-tool.md` — full `enumerate.tcl` manual, including
  the complete table of every register probed
- `../09-discover-tool.md` — `discover.tcl` reference
- `../11-enumerated-attributes.md` — enumerated security-attribute catalog

## Reading flow for a returning reader

1. Skim Volume 1 §3.4 (JTAG security architecture) for refresher
2. Volume 2 §3 (ZCU102 case study) for concrete examples
3. Volume 3 — pick the indicator section relevant to current
   investigation, read indicator + offensive-use pair
4. Volume 3 §10 future work for what's coming next
