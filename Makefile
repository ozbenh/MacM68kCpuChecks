# export RETRO68=/path/to/Retro68-build/toolchain
RETRO68 ?= $(HOME)/hackplace/macfoo/Retro68-build/toolchain
CC=$(RETRO68)/bin/m68k-apple-macos-gcc
REZ=$(RETRO68)/bin/Rez
CFLAGS=-O2 -Wall -Wno-multichar -Wno-array-bounds
ASFLAGS=-m68030 -m68881
LDFLAGS=-lRetroConsole
RINCLUDES=$(RETRO68)/m68k-apple-macos/RIncludes
REZFLAGS=-I$(RINCLUDES)

all: M68kCpuChecks.bin M68kCpuChecks-1.4MB.img

M68kCpuChecks.bin: M68kCpuChecks.code.bin
	$(REZ) $(REZFLAGS) \
		--copy "M68kCpuChecks.code.bin" \
		"$(RINCLUDES)/Retro68APPL.r" \
		-t "APPL" -c "????" \
		-o M68kCpuChecks.bin --cc "._M68kCpuChecks.ad" --cc M68kCpuChecks.dsk

# 1.44 MB HFS floppy image, for Macs whose drive can't read 800K disks any more
M68kCpuChecks-1.4MB.img: M68kCpuChecks.bin
	rm -f $@
	dd if=/dev/zero of=$@ bs=1024 count=1440 status=none
	hformat -l M68kCpuChecks $@ >/dev/null
	hcopy -m M68kCpuChecks.bin :
	humount >/dev/null

M68kCpuChecks.code.bin: checks.o cc_run.o cc_tests.o
	$(RETRO68)/bin/m68k-apple-macos-g++ $^ -o $@ $(LDFLAGS)

checks.o: checks.c
	$(CC) $(CFLAGS) -c $< -o $@

cc_run.o: cc_run.s
	$(CC) $(ASFLAGS) -c $< -o $@

cc_tests.o: cc_tests.s
	$(CC) $(ASFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -f M68kCpuChecks-1.4MB.img M68kCpuChecks.bin M68kCpuChecks.code.bin M68kCpuChecks.code.bin.gdb *.o M68kCpuChecks.ad ._M68kCpuChecks.ad M68kCpuChecks.dsk
