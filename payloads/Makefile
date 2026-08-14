# Payload Makefile — rebuilds .bin from .S for JTAG payloads.
#
# Two toolchains are used because the payloads target different ISAs:
#   - AArch64 payloads (A53):  aarch64-linux-gnu-*
#   - ARMv7-R payloads (R5):   arm-none-eabi-*  (Cortex-R/M cross)
#
# Usage:
#   make              -> build all payloads
#   make clean        -> remove .o, .elf, .bin
#   make check        -> verify every .bin is newer than its .S
#   make disasm       -> dump disassembly for every payload

A64       := aarch64-linux-gnu-
A64_ASFLAGS := -march=armv8-a -g
A32R5     := arm-none-eabi-
A32R5_CPU := -mcpu=cortex-r5
A32R5_ASFLAGS := -g

# AArch64 payloads (A53)
A64_PAYLOADS  := bootrom-dump bootrom-dump-clean hello csu-pmu-ipi csu-pmu-pm-probe csu-pmu-rpu-wake csu-pmu-r5-wakeup csu-pmu-r5-bootrom csu-hello-uart inject-demo csu-pmu-wake-probe reopen-gates csu-pmu-mmio-write cache-flush

# ARMv7-R payloads (R5)
R5_PAYLOADS   := bootrom-dump-r5

ALL_PAYLOADS  := $(A64_PAYLOADS) $(R5_PAYLOADS)
BINS          := $(addsuffix .bin,$(ALL_PAYLOADS))
ELFS          := $(addsuffix .elf,$(ALL_PAYLOADS))
OBJS          := $(addsuffix .o,$(ALL_PAYLOADS))

.PHONY: all clean check disasm
.SECONDARY: $(ELFS) $(OBJS)        # keep intermediates for objdump / debugging
all: $(BINS)

# --- AArch64 build rules ---
$(addsuffix .o,$(A64_PAYLOADS)): %.o: %.S
	$(A64)as $(A64_ASFLAGS) $< -o $@

# csu-pmu-r5-bootrom embeds the compiled R5 extractor via .incbin, so its
# object depends on that binary existing first.
csu-pmu-r5-bootrom.o: bootrom-dump-r5.bin

# --- ARMv7-R build rules ---
$(addsuffix .o,$(R5_PAYLOADS)): %.o: %.S
	$(A32R5)as $(A32R5_CPU) $(A32R5_ASFLAGS) $< -o $@

# --- Linker rules (per-payload .lds if exists, else fall back to bootrom-dump.lds) ---
$(addsuffix .elf,$(A64_PAYLOADS)): %.elf: %.o
	$(A64)ld -T $(if $(wildcard $*.lds),$*.lds,bootrom-dump.lds) $< -o $@

$(addsuffix .elf,$(R5_PAYLOADS)): %.elf: %.o
	$(A32R5)ld -T $(if $(wildcard $*.lds),$*.lds,bootrom-dump.lds) $< -o $@

# --- Binary extraction (toolchain-agnostic) ---
$(addsuffix .bin,$(A64_PAYLOADS)): %.bin: %.elf
	$(A64)objcopy -O binary $< $@

$(addsuffix .bin,$(R5_PAYLOADS)): %.bin: %.elf
	$(A32R5)objcopy -O binary $< $@

clean:
	rm -f $(BINS) $(ELFS) $(OBJS)

check:
	@fail=0; \
	for p in $(ALL_PAYLOADS); do \
		if [ ! -f "$$p.S" ]; then \
			echo "MISSING SRC: $$p.S not found"; fail=1; \
		elif [ ! -f "$$p.bin" ]; then \
			echo "MISSING:     $$p.bin (run 'make $$p.bin')"; fail=1; \
		elif [ "$$p.S" -nt "$$p.bin" ]; then \
			echo "STALE:       $$p.bin is older than $$p.S - run 'make $$p.bin'"; fail=1; \
		else \
			echo "ok:          $$p.bin"; \
		fi; \
	done; \
	exit $$fail

disasm: $(ELFS)
	@for p in $(A64_PAYLOADS); do \
		if [ -f "$$p.elf" ]; then \
			echo "===== $$p.elf (AArch64) ====="; \
			$(A64)objdump -d "$$p.elf"; \
		fi; \
	done
	@for p in $(R5_PAYLOADS); do \
		if [ -f "$$p.elf" ]; then \
			echo "===== $$p.elf (Cortex-R5 / ARMv7-R) ====="; \
			$(A32R5)objdump -d "$$p.elf"; \
		fi; \
	done
