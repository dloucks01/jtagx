#!/usr/bin/env python3
# Build a bootable VxWorks 7 image for the stock ZCU102 (XCZU9EG) from npMain's
# extracted vxWorks.bin.
#
# Default (networking on) produces the two validated images:
#   vxworks-BOOT-sd.bin    -> SD boot,  GEM3 networking enabled  (== v5pg,  md5 cd4466…)
#   vxworks-BOOT-qspi.bin  -> QSPI boot, GEM3 networking enabled (== v5pg3, md5 2f46c263)
# With --no-net it skips the 3 networking patches and produces the pre-networking SD image:
#   vxworks-BOOT-sd.bin    -> SD boot,  GEM3 disabled            (== v5p,   md5 8d2ebc69)
#
# Applies the fixes from docs/17-vxworks-zcu102-bringup.md:
#   1. Correct FSBL/PMUFW split from the PetaLinux boot image  (partition0 = [PMUFW][FSBL])
#   2. npMain bl31 (EL3) reused as-is
#   3. micrelPhy OUI-accept binary patch (so it drives the ZCU102's TI DP83867)  [networking only]
#   4. Device-tree patches (clock, disable PL/KSZ; enable GEM3+DP83867 [networking only]; +qspi/sdhc for QSPI)
#   5. Wrap to ELFs + mkbootimage
#
# Run from the build-vxboot/ directory:  python3 build_vxworks_zcu102.py [--no-net]
import os, sys, struct, subprocess, shutil

if "-h" in sys.argv[1:] or "--help" in sys.argv[1:]:
    print("usage: build_vxworks_zcu102.py [--no-net]\n"
          "  (default)  build networking SD + QSPI images (v5pg / v5pg3)\n"
          "  --no-net   build the pre-networking SD image only (v5p, md5 8d2ebc69)")
    sys.exit(0)
NO_NET = "--no-net" in sys.argv[1:]

HERE   = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
VXBIN  = "../dumps/sd-extract/vxWorks.bin"      # npMain VxWorks image (input)
PETA   = "sd-staging/BOOT.petalinux.bin"        # PetaLinux boot image (FSBL+PMUFW source)
BL31   = "bl31.elf"                             # npMain bl31 (already extracted; entry 0xfffea000)
DTC    = "/tmp/dtcroot/usr/bin/dtc"             # local device-tree-compiler
MKBOOT = "/tmp/zynq-mkbootimage/mkbootimage"    # antmicro mkbootimage

# ---- constants determined during bring-up (see docs/17) -------------------------------
P0_DATA_OFF = 0xa00 * 4         # PetaLinux partition0 data start (byte 0x2800)
PMU_LEN     = 0x1fae0           # pmuFwLength  (129760)  -> PMUFW is FIRST in partition0
FSBL_LEN    = 0x23f48           # fsblLength   (147272)  -> FSBL is SECOND
FSBL_LOAD   = 0xfffc0000
PMU_LOAD    = 0xffdc0000
VX_LOAD     = 0x00100000
DTB_OFF     = 0x928f90          # embedded device tree inside vxWorks.bin
DTB_SLOT    = 0x4fc5            # its exact byte slot (cannot grow past this)
OUI_OFF     = 0x13968           # micrelPhy verify: csetm w0,ne -> mov w0,wzr
OUI_OLD     = 0x5a9f03e0
OUI_NEW     = 0x2a1f03e0

def need(p, what):
    if not os.path.exists(p):
        sys.exit("MISSING %s: %s\n  (see docs/17 'Reproducible build recipe' for how to obtain it)" % (what, p))
need(VXBIN, "vxWorks.bin"); need(PETA, "PetaLinux BOOT.bin"); need(BL31, "bl31.elf")
need(DTC, "dtc (dpkg-deb -x device-tree-compiler*.deb /tmp/dtcroot)")
need(MKBOOT, "mkbootimage (/tmp/zynq-mkbootimage)")

# ---- Step 1: extract FSBL + PMUFW with the CORRECT split ------------------------------
print("[1] extracting FSBL + PMUFW from PetaLinux partition0 ([PMUFW][FSBL])")
peta = open(PETA, "rb").read()
part0 = peta[P0_DATA_OFF : P0_DATA_OFF + PMU_LEN + FSBL_LEN]
pmu  = part0[:PMU_LEN]
fsbl = part0[PMU_LEN:PMU_LEN + FSBL_LEN]
assert b"PMU_ROM Version" in pmu and b"First Stage Boot Loader" in fsbl, "split sanity check failed"
open("pmufw.bin", "wb").write(pmu)
open("fsbl.bin",  "wb").write(fsbl)

# ---- minimal-AArch64-ELF wrapper (mkbootimage needs ELF inputs) -----------------------
def wrap_elf(data, outp, load, entry):
    shstr = b"\x00.text\x00.shstrtab\x00"
    eh=64; she=64; toff=eh; soff=toff+len(data); shoff=(soff+len(shstr)+7)&~7
    ident=b"\x7fELF"+bytes([2,1,1,0])+b"\x00"*8
    ehdr=struct.pack("<16sHHIQQQIHHHHHH", ident, 2,183,1, entry,0,shoff,0, eh,0,0, she,3,2)
    def sh(n,t,f,a,o,s,l,i,al,e): return struct.pack("<IIQQQQIIQQ", n,t,f,a,o,s,l,i,al,e)
    out=bytearray(ehdr); out+=data; out+=shstr; out+=b"\x00"*(shoff-(soff+len(shstr)))
    out+=sh(0,0,0,0,0,0,0,0,0,0)+sh(1,1,0x6,load,toff,len(data),0,0,4,0)+sh(7,3,0,0,soff,len(shstr),0,0,1,0)
    open(outp,"wb").write(out)

# ---- device-tree editing helpers -----------------------------------------------------
def dtb_to_dts(dtb_bytes):
    open("/tmp/_in.dtb","wb").write(dtb_bytes)
    return subprocess.check_output([DTC,"-I","dtb","-O","dts","/tmp/_in.dtb"], stderr=subprocess.DEVNULL).decode()
def dts_to_dtb(dts_text):
    open("/tmp/_in.dts","w").write(dts_text)
    return subprocess.check_output([DTC,"-I","dts","-O","dtb","/tmp/_in.dts"], stderr=subprocess.DEVNULL)
def set_node_status(dts, node, value):
    """Set status of the given node (matched by its 'name {' line) to value."""
    lines=dts.split("\n");
    for i,l in enumerate(lines):
        if (node+" {") in l:
            for j in range(i+1,i+40):
                if "{" in lines[j] and j!=i: break          # entered a child node; stop
                if "status = " in lines[j]:
                    lines[j]=lines[j].split("status = ")[0]+'status = "%s";'%value
                    return "\n".join(lines)
            # no status line -> add one right after the opening brace
            lines.insert(i+1, lines[i].split(node)[0]+'\tstatus = "%s";'%value)
            return "\n".join(lines)
    sys.exit("node not found in dts: "+node)
def replace_once(dts, old, new):
    assert old in dts, "dts text not found: "+old
    return dts.replace(old, new, 1)

# ---- Step 4: build the patched device tree -------------------------------------------
print("[4] patching the embedded device tree")
orig_dtb = open(VXBIN,"rb").read()[DTB_OFF:DTB_OFF+DTB_SLOT]
assert orig_dtb[:4]==b"\xd0\x0d\xfe\xed", "embedded DTB magic not found"
dts = dtb_to_dts(orig_dtb)
# clock: ps_ref_clk 50MHz -> 33.333MHz (ZCU102's real PS reference clock)
dts = replace_once(dts, "clock-frequency = <0x2faf080>", "clock-frequency = <0x1fca055>")
# PL fabric isn't present on a stock ZCU102 -> disable everything that touches it
for n in ("lpd-hpm0@80000000","fpd-hpm0@a0000000","fpd-hpm1@500000000","pl-ps-ints@"):
    dts = set_node_status(dts, n, "fail")
# npMain's custom KSZ switch port isn't on a ZCU102 -> disable
dts = set_node_status(dts, "ethernet@ff0d0000", "fail")
if NO_NET:
    # Pre-networking v5p: leave GEM3 disabled + PHY addr untouched (micrelPhy OUI patch also
    # skipped below). Result is byte-identical to vxworks-BOOT-v5p.bin (md5 8d2ebc69).
    dts = set_node_status(dts, "ethernet@ff0e0000", "fail")
else:
    # GEM3 is the ZCU102 Ethernet: keep enabled, point PHY at the DP83867 (MDIO addr 0xc)
    dts = set_node_status(dts, "ethernet@ff0e0000", "okay")
    dts = replace_once(dts, "reg = <0x09>", "reg = <0x0c>")     # only the ethernet-phy@9 node uses 0x09

def finish(dts_text, tag, sf_bl, vx_bytes):
    dtb = dts_to_dtb(dts_text)
    if len(dtb) > DTB_SLOT:
        sys.exit("patched DTB %d > slot %d for %s" % (len(dtb), DTB_SLOT, tag))
    vx = bytearray(vx_bytes)
    # Step 3: micrelPhy OUI-accept patch (networking only; skipped for --no-net / v5p)
    assert struct.unpack("<I", vx[OUI_OFF:OUI_OFF+4])[0]==OUI_OLD, "OUI patch site mismatch"
    if not NO_NET:
        vx[OUI_OFF:OUI_OFF+4]=struct.pack("<I", OUI_NEW)
    # splice the patched DTB back in (pad to slot)
    vx[DTB_OFF:DTB_OFF+len(dtb)]=dtb
    if len(dtb)<DTB_SLOT: vx[DTB_OFF+len(dtb):DTB_OFF+DTB_SLOT]=b"\x00"*(DTB_SLOT-len(dtb))
    open("vxworks-%s.bin"%tag,"wb").write(vx)
    # Step 5: wrap ELFs + mkbootimage
    wrap_elf(fsbl,"fsbl.elf",FSBL_LOAD,FSBL_LOAD)
    wrap_elf(pmu,"pmufw.elf",PMU_LOAD,PMU_LOAD)
    wrap_elf(bytes(vx),"vxworks.elf",VX_LOAD,VX_LOAD)
    bif="the_ROM_image:\n{\n\t[bootloader, destination_cpu=a53-0] fsbl.elf\n\t[pmufw_image] pmufw.elf\n"\
        "\t[destination_cpu=a53-0, exception_level=el-3] bl31.elf\n"\
        "\t[destination_cpu=a53-0, exception_level=el-1] vxworks.elf\n}\n"
    open("vx.bif","w").write(bif)
    out="vxworks-BOOT-%s.bin"%tag
    subprocess.check_call([MKBOOT,"-u","vx.bif",out], stdout=subprocess.DEVNULL)
    print("    built %s (%d bytes)"%(out, os.path.getsize(out)))

vx_in = open(VXBIN,"rb").read()
# SD image: sdhc/qspi left enabled (fine when actually booting from SD)
print("[5a] building SD image")
finish(dts, "sd", None, vx_in)
if NO_NET:
    print("\nDONE (--no-net). SD boot: vxworks-BOOT-sd.bin  == validated v5p (md5 8d2ebc69)")
else:
    # QSPI image: additionally disable qspi + sdhc (FSBL doesn't init them on the QSPI boot path)
    print("[4b] +disable qspi@ff0f0000 and sdhc@ff160000 for the QSPI boot path")
    dts_qspi = set_node_status(dts,       "qspi@ff0f0000", "fail")
    dts_qspi = set_node_status(dts_qspi,  "sdhc@ff160000", "fail")
    print("[5b] building QSPI image")
    finish(dts_qspi, "qspi", None, vx_in)
    print("\nDONE. SD boot: vxworks-BOOT-sd.bin   QSPI boot: vxworks-BOOT-qspi.bin")
