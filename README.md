# M68kCpuChecks

M68kCpuChecks runs instructions on the processor of a classic 68k Macintosh
and writes down exactly what they do. It covers what the Motorola manuals leave
undefined or say little about, such as the flags of BCD instructions and of a
division overflow, registers used in their own operation (`LINK A7`,
`MOVEM A0,-(A0)`, an odd stack pointer), bit fields and `CAS2` in corner cases,
trace, exception stack frames, the FPU's constants and flags, MMU status, patching
code that is in the cache, and bus errors. The results help the [Snow](https://github.com/twvd/snow) emulator
behave like the real chips, as so far it relies on the manuals and on other
emulators for the 68020 and 68030.

It only changes its own memory, and for a moment its own code. Interrupts are masked during each test, for a
very short time, so the mouse pointer may stutter.

## Running it

1. Restart the Mac, and don't start any other application.
2. Turn **virtual memory off** (Memory control panel), then restart. With
   virtual memory on, it stops with a message. It doesn't run under A/UX.
3. Run M68kCpuChecks, from one of:
   - `M68kCpuChecks.dsk`: 800K disk image;
   - `M68kCpuChecks-1.4MB.img`: 1.44 MB (MFM, HFS) disk image, for Macs with a
     SuperDrive whose drive no longer reads 800K disks;
   - `M68kCpuChecks.bin`: MacBinary file.

   The disk images also have `M68kCpuChecks-NoA7` (`M68kCpuChecks-NoA7.bin` on
   its own), which leaves out the tests using the stack pointer in their own
   operation. Only run it if asked to, or if the first one doesn't get to the end
   on your Mac even after running it again. It writes its own results file.

   Copy the application to the hard disk first if you like: it writes its
   results next to itself, so a write-protected floppy won't do.
4. **Don't touch the mouse or the keyboard** until it says it is done. It should
   take under a few minutes on the slowest Macs.
5. When it says "Saved", press Return to quit.

If it hangs or crashes: a slow test can look like a hang, as each test saves
its results, so give it a few minutes first. Then take a photo of the screen,
restart the Mac, **and run it again**. It remembers the test it was on, marks it
as hung and goes on past it. Do this as many times as it takes to get to "Saved".
A hung test is a useful result, not a problem with your Mac.

It needs Gestalt (System 6.0.4 or later) and is meant for any 68000 to 68040
Mac; so far it has only run on an emulator, under System 7.1.

## What to send back

- The file **"M68kCpuChecks Results"**, which the program writes next to
  itself. It is a text file.
- Any photos of the screen from hangs, and whether the mouse pointer still moved.
- The model of the Mac, and any accelerator card, CPU, FPU or clock upgrade.

## Bus errors

On a 68020 or 68030 with an empty NuBus or PDS slot, it provokes bus errors by
accessing that slot, to record the stack frames. It looks for an empty slot by
reading one; the writes it does only go to a slot that gave a bus error on the
read. Without a free slot, those tests are skipped. A Mac with a card in every
slot gives fewer results, which is fine.

## Reading the results

One entry per test, with what it changed:

    LINK A7,#-16: sr=2700 a7=S+2EC
      S+2FC=S+300

Registers not listed kept their value. `S+`, `D+` and `M+` are offsets in the
program's stack, data and master stack buffers, `C+` is in the code of the test,
and `FAULT` the address on the empty slot, so results compare across runs with
`diff`. `vector=` is an exception taken, with its frame on the next line.

The sweeps at the end run one instruction over a grid of operands: each column
is `result/flags` (the low five bits of SR).

The tests are in `cc_tests.s`, the runner in `cc_run.s`.

## Building

M68kCpuChecks is built with [Retro68](https://github.com/autc04/Retro68):

    export RETRO68=/path/to/Retro68-build/toolchain
    make

This gives the three files above. hfsutils (`hformat`, `hcopy`) are needed for
the 1.44 MB image.

## License

MIT, see `LICENSE`.
