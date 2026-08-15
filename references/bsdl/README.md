# BSDL library

Drop a part's **BSDL** file here (named `<soc-or-part>.bsdl`) and the boundary-scan flow can plan a
capture, run it, and decode the live pin states — the DAP-gated fallback (works even when the debug
DAP is shut, since the IEEE-1149.1 boundary-scan layer sits below the debug-security gate).

## Where BSDLs come from
- The silicon vendor's site (per-part BSDL download): AMD/Xilinx, NXP, ST, Microchip/Microsemi, etc.
- The BSDL is a text file describing the TAP (IR length, opcodes, IDCODE, boundary-register cells).
- Not redistributed here (vendor-licensed, like `references/pdf/`); fetch the one for your part.

## End-to-end flow (operator runs the JTAG; we plan + decode)
```
# 1. inspect the part
python3 tools/bsdl-scan.py references/bsdl/<part>.bsdl                 # IDCODE, opcodes, readable pins

# 2. emit the ONE capture command (fills BS_SAMPLE/BS_LEN from the BSDL)
python3 tools/bsdl-scan.py references/bsdl/<part>.bsdl --capture-cmd \
        --tap <chain.tap> --cfg openocd/<chain>.cfg
#    -> BS_TAP=... BS_SAMPLE=... BS_LEN=... openocd -f ... -c "init; source openocd/boundary-scan.tcl; shutdown"

# 3. run it (operator), then decode its output to per-pin states
... run the command, save stdout to cap.txt ...
python3 tools/bsdl-scan.py references/bsdl/<part>.bsdl --decode-output cap.txt
```

`openocd/boundary-scan.tcl` does SAMPLE only (reads pins, non-destructive). EXTEST (driving pins) is
deliberately not automated. A test fixture lives at `tests/fixtures/fake1149.bsdl`.
