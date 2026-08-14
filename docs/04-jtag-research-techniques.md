# JTAG Research Techniques

With OpenOCD attached, this document covers the three core techniques
that everything downstream is built on:

1. **Passive AXI memory reads** — read any SoC register without halting
   any CPU
2. **A53 core release from raw JTAG** — bring up the APU without any
   FSBL, PMU firmware, or vendor tooling
3. **OCM payload execution** — load a tiny AArch64 binary, point the
   APU at it, observe execution

These are the primitives. Section 5 (the enumeration tool) wraps these
together into a reproducible workflow.

## Technique 1: Passive AXI memory reads (no halt required)

### The mechanism

The ARM CoreSight DAP has multiple **Access Ports (APs)**:
- **AP 0 = AXI-AP** (memory-AP variant). Lets the DAP perform AXI bus
  transactions to anywhere in the SoC's 64-bit physical address space.
- **AP 1 = APB-AP**. Used for accessing the CoreSight debug components
  (Debug Units, CTIs, ETMs, etc.). Discoverable via the ROM table.

The AXI-AP is what we use for register reads. It is reachable
**regardless of CPU state** — even with all CPUs in reset, the AXI
fabric is alive (in the LPD power domain, brought up by BootROM).

OpenOCD wraps this as the `uscale.axi` target (a `mem_ap` type).

### Why it matters for research

You can read:
- CSU registers (boot status, security configuration, eFUSE bits)
- PMU global registers (power state, error status)
- Clock controller registers (PLL config, peripheral ref clocks)
- Reset controller registers (which peripherals are reset)
- OCM contents
- DDR contents (if DDR controller is initialized; not in JTAG idle)
- Peripheral registers (those not held in reset)

Without halting a CPU, without injecting any code, without altering any
state. This is the most non-invasive reconnaissance possible — anything
that observably changes the SoC could potentially trigger a tamper
response on a hardened device. AXI reads do not.

### Quirk: AXI-AP needs explicit examination

In a fresh OpenOCD session, `init` tries to auto-examine `uscale.a53.0`,
which fails (CPU in reset), and the failure leaves the DP in a sticky
error state. This blocks downstream AXI-AP examination too.

The recovery pattern:

```tcl
catch { uscale.dap dpreg 0 0x1e } _   ;# clear DP sticky errors
catch { uscale.axi arp_examine } _    ;# now examine AXI-AP
targets uscale.axi                     ;# make it the active target
```

After this, `read_memory addr 32 count` works for any address the SoC's
AXI bus can reach.

### Critical scripting gotcha

`mdw` (memory display word) **prints to OpenOCD's log channel** rather
than returning a Tcl value. This makes it invisible in `-c` batch mode
and unusable for programmatic capture.

**Use `read_memory addr 32 count`** instead — it returns a Tcl list of
32-bit values that you can capture.

```tcl
set values [read_memory 0xFFCA0000 32 4]
foreach v $values {
    echo [format "0x%08x" $v]
}
```

### Quirks to know

- After a failed read (e.g. accessing an unmapped or in-reset
  peripheral), the DP sticky bit gets set and **subsequent reads silently
  return ERR**. Always clear sticky after a known-bad read.
- Reading from a peripheral held in reset (most are in JTAG idle) often
  causes an unrecoverable AXI bus timeout. Check `RST_LPD_IOU2` etc.
  before probing peripheral bases.

## Technique 2: A53 release from raw JTAG (no FSBL, no PMU firmware)

### The goal

End state: A53 core 0 halted in EL3 (highest privilege), under
debugger control, with no Xilinx vendor code having executed.

### Why this is non-obvious

The official AMD workflow assumes you load FSBL (which does APU
bring-up as part of its job) followed by ATF (which sets up EL3) before
you can attach to a halted CPU at EL3. Vitis/XSCT scripts wrap this for
you.

For research, we want **no vendor code anywhere** — pure observations
of the SoC's reset state. So we have to do the APU bring-up ourselves.

### What's already done by BootROM (in JTAG idle)

You'd think APU release would require: configuring APLL, configuring
ACPU_CTRL, powering up the FPD, clearing reset bits. **In fact,
BootROM does most of this for us:**

- `PMU_GLOBAL.PWR_STATE` shows ACPU0-3, L2, FP, OCM, RPU all already
  powered (`0x00FFFCBF` on ZCU102 in JTAG idle).
- `PLL_STATUS` shows APLL, DPLL, VPLL all already locked.
- `ACPU_CTRL` already has working clock divisors and CLKACT bits set.

What's missing is just **clearing the reset bits**.

### The four-step recipe

```tcl
# (1) Safe landing in OCM. Without this, A53 would execute the
# 0xDEADBEEF poison pattern BootROM wrote to OCM and trap.
# 0x14000000 is AArch64 'b .' = infinite branch-to-self.
write_memory 0xFFFC0000 32 {0x14000000}

# (2) Point A53 core 0 reset vector at the safe landing.
write_memory 0xFD5C0040 32 {0xFFFC0000}   ;# APU.RVBARADDR0L
write_memory 0xFD5C0044 32 {0x00000000}   ;# APU.RVBARADDR0H

# (3) Clear core-0 and L2 reset bits in CRF_APB.RST_FPD_APU.
# Default value 0x00003D0F. Clear bit 0 (ACPU0_RESET),
# bit 8 (APU_L2_RESET), bit 10 (ACPU0_PWRON_RESET).
# Result: 0x0000380E.
write_memory 0xFD1A0104 32 {0x0000380E}

# (4) Clear DP sticky errors from prior failed examines, then examine + halt.
uscale.dap dpreg 0 0x1e
uscale.a53.0 arp_examine
targets uscale.a53.0
halt
```

Expected result:
```
uscale.a53.0 halted in AArch64 state due to debug-request, current mode: EL3H
cpsr: 0x000003cd  pc: 0xfffc0000
MMU: disabled, D-Cache: disabled, I-Cache: disabled
```

**EL3H** = Exception Level 3, Handler mode. Highest privilege. From
here you can do anything: read/write all system registers, execute
arbitrary code, manipulate TrustZone state.

### The bit that was the rabbit hole

Clearing core-0 reset alone is not enough. You must **also clear bit 8
(APU_L2_RESET)** — without L2 cache out of reset, A53 cannot fetch
instructions, even though it's clocked and out of reset itself.
Examination fails with the cryptic `JTAG-DP STICKY ERROR`.

This isn't documented prominently anywhere. Discovered empirically:
clearing bit 0 alone → fail; clearing bits 0+10 → still fail; clearing
bits 0+8+10 → success.

### Extending to other cores

| Core | RESET bit | PWRON_RESET bit | RVBARADDR registers |
|------|-----------|-----------------|---------------------|
| 0    | 0         | 10              | `0xFD5C0040` / `0xFD5C0044` |
| 1    | 1         | 11              | `0xFD5C0048` / `0xFD5C004C` |
| 2    | 2         | 12              | `0xFD5C0050` / `0xFD5C0054` |
| 3    | 3         | 13              | `0xFD5C0058` / `0xFD5C005C` |

L2 reset (bit 8) only needs to be cleared once (it's shared).

Cores 1-3 are configured with `-defer-examine` in `xilinx_zynqmp.cfg`,
so they need explicit `uscale.a53.N arp_examine`.

## Technique 3: OCM payload execution

### The setup

Once A53 is halted, you can load arbitrary code into OCM and execute it.
OCM (256 KB total, 4 banks of 64 KB at `0xFFFC0000` - `0xFFFFFFFF`) is
SRAM in the LPD power domain — always available even with DDR off.

### Build a payload

The AArch64 toolchain on Kali (`aarch64-linux-gnu-as` etc.) is
sufficient. Example payload that initializes PS UART0 and prints a
string:

```bash
cd payloads
aarch64-linux-gnu-as hello.S -o hello.o
aarch64-linux-gnu-ld -T hello.lds hello.o -o hello.elf
aarch64-linux-gnu-objcopy -O binary hello.elf hello.bin
```

The linker script places the binary at `0xFFFC0000` (OCM bank 0 start).

### Load and run

```tcl
halt
load_image payloads/hello.bin 0xFFFC0000 bin
reg pc 0xFFFC0000
resume
```

The A53 executes from OCM. Observe output on `/dev/ttyUSB0`.

### The catch (and why this is still incomplete)

Getting code execution is the easy part. Getting **useful output** out of
a peripheral like UART requires replicating what FSBL does:

1. Clear the peripheral's reset bit (e.g. `RST_LPD_IOU2` bit 1 for UART0)
2. Configure the peripheral's reference clock divisor
3. Route the right MIO pins to the peripheral function
4. Clear the MIO output tri-state

Each of these is one or more register writes with magic numbers from
UG1085. Replicating FSBL's pin/clock setup from scratch is a multi-hour
rabbit hole per peripheral. **The pragmatic path is to use Vitis-generated
`psu_init.tcl`** which has every magic number for a given hardware
platform.

Our hello-world payload reaches the "code executes on A53" milestone
(verified by halting at the post-init `hang:` label). The UART output
remains incomplete pending Vitis install — bytes transmit but at the
wrong baud rate due to IOPLL frequency assumptions that don't match
this board's actual configuration.

## Putting it together

All three techniques are combined in the `enumerate.tcl` script:
- AXI reads dump every relevant register
- A53 release happens in §8 so we can read system registers (deferred)
- The cleanup at end re-asserts A53 reset for clean re-runs

See **[05-enumeration-tool.md](05-enumeration-tool.md)** next.
