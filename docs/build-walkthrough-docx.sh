#!/usr/bin/env bash
# Rebuild docs/21-engagement-walkthrough.docx from the .md with the engagement-doc styling:
#   - NO table of contents
#   - command/code blocks rendered as a shaded box with a blue left-accent bar (code-reference.docx)
#   - inline `code` lightly shaded
# Run this instead of `pandoc -d ...whitepaper/pandoc-defaults-docx.yaml` (that one re-adds the TOC and
# drops the code styling). Edit the .md, then run this.
set -euo pipefail
cd "$(dirname "$0")"
pandoc --from markdown+pipe_tables+yaml_metadata_block+raw_html --to docx --standalone \
  --reference-doc=code-reference.docx \
  21-engagement-walkthrough.md -o 21-engagement-walkthrough.docx
echo "wrote 21-engagement-walkthrough.docx ($(stat -c%s 21-engagement-walkthrough.docx) bytes)"
