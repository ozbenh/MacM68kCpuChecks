/*
 * M68kCpuChecks: runs instructions whose behaviour isn't certain, on the real
 * CPU, and writes down what happens, for comparing with an emulator: undefined
 * condition codes, registers used in their own operation, exception frames,
 * the FPU, and bus errors on an empty slot where the machine has one.
 *
 * Every test runs with interrupts masked, on its own stack and vectors. What
 * it did to the registers and to its memory goes in the results. See README.md
 * for what it touches, and the fragments in cc_tests.s.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <Gestalt.h>
#include <Files.h>
#include <Memory.h>
#include <OSUtils.h>

#define VERSION "4"

/* The NoA7 build leaves out the tests that use A7 in their own operation */
#ifdef NO_A7
#define PROGRAM "M68kCpuChecks-NoA7"
#else
#define PROGRAM "M68kCpuChecks"
#endif

#define NF 1
#define NM 2
#define NB 4
#define NA 8

#define LM_MMU32BIT 0xCB2
#define LM_ROMBASE 0x2AE

/* The layout is known to cc_run.s */
struct cc_state
{
	uint32_t d[8];
	uint32_t a[7];
	uint32_t a7;
	uint32_t usp;
	uint32_t msp;
	uint16_t sr;
};

struct cc_test
{
	const char *name;
	const void *code;
	uint16_t min, max, needs, pad;
};

extern void cc_run(void);
extern struct cc_state *cc_s;
extern uint8_t cc_is020;
extern uint16_t cc_vector;
extern uint32_t cc_out_a6, cc_out_a7;
extern uint16_t cc_out_sr;
extern uint32_t cc_vectors[256];
extern void cc_fpu_save(void *frame);
extern void cc_fpu_null(void);
extern void cc_fpu_regs_save(void *regs);
extern void cc_fpu_regs_restore(const void *regs, const void *frame);
extern const struct cc_test cc_table[];

extern const char cc_f_abcd[], cc_f_sbcd[], cc_f_nbcd[], cc_f_divu[], cc_f_divs[];
extern const char cc_f_chkw[], cc_f_chkl[], cc_f_cmp2b[], cc_f_chk2b[];
extern const char cc_f_divul[], cc_f_divsl[], cc_f_mulul[], cc_f_mulsl[], cc_f_read[];
extern const char cc_f_aslw[], cc_f_roxrw[];

#define DATA_SIZE 1024
#define STACK_SIZE 1024
#define STACK_TOP (STACK_SIZE - 256)

static long cpuType, fpuType, mmuType;
static uint8_t *dataBuf, *dataCopy, *stackBuf, *stackCopy, *mspBuf;
static uint32_t faultAddress;

static char outText[256 * 1024];
static size_t outLength;

static void out(const char *format, ...)
{
	char line[512];
	va_list args;

	va_start(args, format);
	vsnprintf(line, sizeof(line), format, args);
	va_end(args);

	fputs(line, stdout);
	for (const char *c = line; *c && outLength < sizeof(outText); c++)
	{
		outText[outLength++] = (*c == '\n') ? '\r' : *c;
	}
}

static void SaveResults(void)
{
	static const unsigned char name[] = "\p" PROGRAM " Results";
	short refNum;

	(void)FSDelete(name, 0);
	if (Create(name, 0, 'ttxt', 'TEXT') != noErr || FSOpen(name, 0, &refNum) != noErr)
	{
		printf("Could not create the results file\n");
		return;
	}
	long count = outLength;
	(void)FSWrite(refNum, &count, outText);
	(void)FSClose(refNum);
	(void)FlushVol(NULL, 0);
}

/*
 * Before each step, the file below gets its number. A step still in it when the
 * program starts is one that never came back: it is marked and left out from then
 * on, so that restarting and running again gets past whatever hangs a Mac.
 */
#define MAX_STEPS 512

static struct
{
	int32_t current;
	uint8_t hung[MAX_STEPS];
} progress;
static int stepNumber;
static const unsigned char progressName[] = "\p" PROGRAM " Progress";

static void SaveProgress(void)
{
	short refNum;
	long count = sizeof(progress);

	if (FSOpen(progressName, 0, &refNum) != noErr)
	{
		if (Create(progressName, 0, 'ttxt', 'BINA') != noErr ||
			FSOpen(progressName, 0, &refNum) != noErr)
		{
			return;
		}
	}
	(void)SetFPos(refNum, fsFromStart, 0);
	(void)FSWrite(refNum, &count, &progress);
	(void)FSClose(refNum);
	(void)FlushVol(NULL, 0);
}

static void LoadProgress(void)
{
	short refNum;
	long count = sizeof(progress);

	progress.current = -1;
	if (FSOpen(progressName, 0, &refNum) != noErr)
	{
		return;
	}
	if (FSRead(refNum, &count, &progress) != noErr)
	{
		memset(&progress, 0, sizeof(progress));
		progress.current = -1;
	}
	(void)FSClose(refNum);
	if (progress.current >= 0 && progress.current < MAX_STEPS)
	{
		progress.hung[progress.current] = 1;
	}
	progress.current = -1;
}

static void EndProgress(void)
{
	(void)FSDelete(progressName, 0);
	(void)FlushVol(NULL, 0);
}

/* Returns false if this step hung the Mac on an earlier run */
static bool BeginStep(const char *name)
{
	int step = stepNumber++;

	printf("> %s\n", name);
	fflush(stdout);
	if (step < MAX_STEPS && progress.hung[step])
	{
		out("%s: hung on an earlier run, left out\n", name);
		return false;
	}
	progress.current = step;
	SaveProgress();
	return true;
}

static long GestaltOr(OSType selector, long otherwise)
{
	long v;
	return Gestalt(selector, &v) == noErr ? v : otherwise;
}

static inline uint16_t DisableIRQ(void)
{
	uint16_t sr;
	__asm__ volatile("move.w %%sr,%0\n\tori.w #0x0700,%%sr" : "=d"(sr) : : "cc", "memory");
	return sr;
}

static inline void RestoreIRQ(uint16_t sr)
{
	__asm__ volatile("move.w %0,%%sr" : : "d"(sr) : "cc", "memory");
}

/* The registers a test starts with */
static struct cc_state state, initial;

static void Setup(const void *code, uint16_t ccr)
{
	uint32_t data = (uint32_t)dataBuf;

	for (int i = 0; i < DATA_SIZE; i++)
	{
		dataBuf[i] = (uint8_t)(i * 7 + 0x35);
	}
	memset(stackBuf, 0xEE, STACK_SIZE);
	for (int i = 0; i < 8; i++)
	{
		state.d[i] = 0x12345678UL + i * 0x11111111UL;
	}
	for (int i = 0; i < 7; i++)
	{
		state.a[i] = data + 0x100 + i * 0x40;
	}
	state.a[5] = faultAddress ? faultAddress : state.a[5];
	state.usp = (uint32_t)stackBuf + STACK_TOP - 128;
	state.msp = (uint32_t)mspBuf + 512;
	state.sr = 0x2700 | ccr;
	*(const void **)(stackBuf + STACK_TOP - 4) = code;
	state.a7 = (uint32_t)stackBuf + STACK_TOP - 4;
}

static void Snapshot(void)
{
	initial = state;
	memcpy(dataCopy, dataBuf, DATA_SIZE);
	memcpy(stackCopy, stackBuf, STACK_SIZE);
}

/* Runs what Setup() and later changes prepared, leaves the results in state */
static void Run(void)
{
	static uint32_t saved[64];
	uint16_t sr = DisableIRQ();

	cc_s = &state;
	if (cpuType >= 2)
	{
		cc_is020 = 1;
		cc_run();
	}
	else
	{
		/* Everything but the interrupts: those are masked, and level 7 stays theirs */
		volatile uint32_t *low = (volatile uint32_t *)0;
		for (int i = 2; i < 64; i++)
		{
			saved[i] = low[i];
			if (i < 24 || i > 31)
			{
				low[i] = cc_vectors[i];
			}
		}
		cc_is020 = 0;
		cc_run();
		for (int i = 2; i < 64; i++)
		{
			low[i] = saved[i];
		}
	}
	RestoreIRQ(sr);
}

/* An address relative to the buffers of the program, or as it is */
static const char *Rel(uint32_t v, const void *code)
{
	static char text[4][24];
	static int n;
	char *t = text[n++ & 3];
	uint32_t data = (uint32_t)dataBuf, stack = (uint32_t)stackBuf, msp = (uint32_t)mspBuf;
	uint32_t cod = (uint32_t)code;

	if (v >= data && v < data + DATA_SIZE)
	{
		sprintf(t, "D+%03lX", (unsigned long)(v - data));
	}
	else if (v >= stack && v < stack + STACK_SIZE)
	{
		sprintf(t, "S+%03lX", (unsigned long)(v - stack));
	}
	else if (v >= msp && v < msp + 1024)
	{
		sprintf(t, "M+%03lX", (unsigned long)(v - msp));
	}
	else if (v >= cod && v < cod + 256)
	{
		sprintf(t, "C+%03lX", (unsigned long)(v - cod));
	}
	else if (faultAddress && v == faultAddress)
	{
		sprintf(t, "FAULT");
	}
	else
	{
		sprintf(t, "%08lX", (unsigned long)v);
	}
	return t;
}

static uint16_t Word(uint32_t addr)
{
	return *(uint16_t *)addr;
}

static uint32_t Long(uint32_t addr)
{
	return *(uint32_t *)addr;
}

/* The frame at sp, by format */
static void PrintFrame(uint32_t sp, const void *code)
{
	uint16_t fv = Word(sp + (cpuType == 1 ? 0 : 6));

	if (cpuType == 1)
	{
		if (cc_vector == 2 || cc_vector == 3)
		{
			out("  frame sr=%04X pc=%s access=%04X addr=%s ir=%04X\n", Word(sp + 8),
				Rel(Long(sp + 10), code), Word(sp), Rel(Long(sp + 2), code), Word(sp + 6));
		}
		else
		{
			out("  frame sr=%04X pc=%s\n", Word(sp), Rel(Long(sp + 2), code));
		}
		return;
	}
	out("  frame sr=%04X pc=%s fmt=%X off=%03X", Word(sp), Rel(Long(sp + 2), code), fv >> 12,
		fv & 0xFFF);
	switch (fv >> 12)
	{
	case 0x2:
	case 0x3:
		out(" addr=%s\n", Rel(Long(sp + 8), code));
		break;
	case 0xA:
	case 0xB:
		out(" ssw=%04X c=%04X b=%04X fa=%s dob=%08lX", Word(sp + 10), Word(sp + 12), Word(sp + 14),
			Rel(Long(sp + 16), code), (unsigned long)Long(sp + 24));
		if (fv >> 12 == 0xB)
		{
			out(" sbaddr=%s dib=%08lX", Rel(Long(sp + 36), code), (unsigned long)Long(sp + 44));
		}
		out("\n");
		break;
	case 0x7:
		out(" ea=%s ssw=%04X\n", Rel(Long(sp + 8), code), Word(sp + 12));
		break;
	default:
		out("\n");
		break;
	}
}

/* What the test changed */
static void PrintResult(const char *name, const void *code)
{
	static const char regName[2] = {'d', 'a'};

	out("%s:", name);
	if (cc_vector)
	{
		out(" vector=%u", cc_vector);
	}
	out(" sr=%04X", cc_out_sr);
	state.a[6] = cc_out_a6;
	for (int k = 0; k < 2; k++)
	{
		const uint32_t *now = k ? state.a : state.d;
		const uint32_t *was = k ? initial.a : initial.d;
		for (int i = 0; i < (k ? 7 : 8); i++)
		{
			if (now[i] != was[i])
			{
				out(" %c%d=%s", regName[k], i, Rel(now[i], code));
			}
		}
	}
	/* The stack pointer after the return address was taken off */
	if (cc_out_a7 != initial.a7 + 4)
	{
		out(" a7=%s", Rel(cc_out_a7, code));
	}
	out("\n");
	for (int k = 0; k < 2; k++)
	{
		const uint8_t *now = k ? stackBuf : dataBuf;
		const uint8_t *was = k ? stackCopy : dataCopy;
		int size = k ? STACK_SIZE : DATA_SIZE;

		/* The frame of an exception is printed below */
		if (cc_vector && k == 1)
		{
			continue;
		}
		for (int i = 0; i < size;)
		{
			if (now[i] == was[i])
			{
				i++;
				continue;
			}
			int end = i + 1;
			while (end < size && now[end] != was[end])
			{
				end++;
			}
			/* A long word whose first bytes didn't change, an address in our buffers */
			int aligned = i & ~3;
			if (aligned != i)
			{
				uint32_t v = ((uint32_t)now[aligned] << 24) | ((uint32_t)now[aligned + 1] << 16) |
					((uint32_t)now[aligned + 2] << 8) | now[aligned + 3];
				if (Rel(v, code)[1] == '+')
				{
					i = aligned;
				}
			}
			/* In long words as far as they go, so addresses show as relative ones */
			out("  %c+%03X=", k ? 'S' : 'D', i);
			for (; i + 4 <= end; i += 4)
			{
				uint32_t v = ((uint32_t)now[i] << 24) | ((uint32_t)now[i + 1] << 16) |
					((uint32_t)now[i + 2] << 8) | now[i + 3];
				out("%s ", Rel(v, code));
			}
			for (; i < end; i++)
			{
				out("%02X", now[i]);
			}
			out("\n");
		}
	}
	if (cc_vector)
	{
		PrintFrame(cc_out_a7, code);
	}
}

static bool Runnable(const struct cc_test *t)
{
	if (cpuType < t->min || cpuType > t->max)
	{
		return false;
	}
	if ((t->needs & NF) && !fpuType)
	{
		return false;
	}
	if ((t->needs & NM) && !mmuType)
	{
		return false;
	}
	if ((t->needs & NB) && !faultAddress)
	{
		return false;
	}
	return true;
}

/* An empty slot gives a bus error on a read, on the machines that have slots */
static void FindFaultAddress(void)
{
	bool mode32 = *(volatile uint8_t *)LM_MMU32BIT != 0;

	if (cpuType < 3 || cpuType > 4)
	{
		out("Bus errors: not tried on this CPU\n");
		return;
	}
	for (uint32_t slot = 0xE; slot >= 0x9; slot--)
	{
		faultAddress = 0;
		uint32_t addr = mode32 ? 0xF0000000UL | (slot << 24) | 0x00FFFFFCUL : (slot << 20) | 0x000FFFFCUL;
		Setup(cc_f_read, 0);
		state.a[5] = addr;
		Run();
		if (cc_vector == 2)
		{
			faultAddress = addr;
			out("Bus errors: on the empty slot %lX\n", (unsigned long)slot);
			return;
		}
	}
	out("Bus errors: no empty slot found, not tried\n");
}

/* --- Sweeps ------------------------------------------------------------- */

static const uint8_t bcdValues[] = {
	0x00, 0x01, 0x09, 0x0A, 0x0F, 0x10, 0x19, 0x1A, 0x1F, 0x50, 0x55, 0x5A,
	0x90, 0x99, 0x9A, 0x9F, 0xA0, 0xA5, 0xAA, 0xAF, 0xF0, 0xF9, 0xFA, 0xFF,
};
#define BCD_COUNT (sizeof(bcdValues) / sizeof(bcdValues[0]))
static const uint8_t bcdCcrs[] = {0x00, 0x04, 0x14, 0x0A};

static void SweepBcd(const char *name, const void *code, bool unary)
{
	for (size_t c = 0; c < sizeof(bcdCcrs); c++)
	{
		for (size_t x = 0; x < (unary ? 1 : BCD_COUNT); x++)
		{
			out("%s ccr=%02X s=%02X:", name, bcdCcrs[c], unary ? 0 : bcdValues[x]);
			for (size_t y = 0; y < BCD_COUNT; y++)
			{
				Setup(code, bcdCcrs[c]);
				state.d[0] = bcdValues[x];
				state.d[1] = bcdValues[y];
				Run();
				out(" %02lX/%02X", (unsigned long)(state.d[1] & 0xFF), cc_out_sr & 0x1F);
			}
			out("\n");
		}
	}
}

static const uint32_t divDividends[] = {
	0x00000000, 0x00000001, 0x00007FFF, 0x00008000, 0x0000FFFF, 0x00010000, 0x12345678, 0x7FFF0000,
	0x7FFFFFFF, 0x80000001, 0x80000002, 0xFFFF0000, 0xFFFF8000, 0xFFFFFFFF, 0xFFFE0000, 0x40000000,
	0x00020000, 0x00FF0000,
};
static const uint32_t divDivisors[] = {
	0x0001, 0x0002, 0x0003, 0x0100, 0x7FFF, 0x8000, 0x8001, 0xFF00, 0xFFFE, 0xFFFF,
};

#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

/* DIVS of $80000000 by -1 is left for the end: it stops some emulators */
static void SweepDiv(const char *name, const void *code, bool sign)
{
	for (size_t c = 0; c < 2; c++)
	{
		uint16_t ccr = c ? 0x1F : 0;
		for (size_t x = 0; x < COUNT(divDividends); x++)
		{
			out("%s ccr=%02X %08lX:", name, ccr, (unsigned long)divDividends[x]);
			for (size_t y = 0; y < COUNT(divDivisors); y++)
			{
				Setup(code, ccr);
				state.d[0] = divDivisors[y];
				state.d[1] = divDividends[x];
				Run();
				out(" %08lX/%02X", (unsigned long)state.d[1], cc_out_sr & 0x1F);
			}
			out("\n");
		}
	}
	(void)sign;
}

static const uint32_t longValues[] = {
	0x00000000, 0x00000001, 0x00010000, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0x12345678,
};

/* Two long operands with Dh or Dr in d2 */
static void SweepLong(const char *name, const void *code, bool div)
{
	for (size_t c = 0; c < 2; c++)
	{
		uint16_t ccr = c ? 0x1F : 0;
		for (size_t x = 0; x < COUNT(longValues); x++)
		{
			out("%s ccr=%02X %08lX:", name, ccr, (unsigned long)longValues[x]);
			for (size_t y = 0; y < COUNT(longValues); y++)
			{
				if (div && longValues[y] == 0)
				{
					continue;
				}
				Setup(code, ccr);
				state.d[0] = longValues[y];
				state.d[1] = longValues[x];
				state.d[2] = (longValues[x] & 0x80000000UL) ? 0xFFFFFFFFUL : 0;
				Run();
				out(" %08lX:%08lX/%02X", (unsigned long)state.d[2], (unsigned long)state.d[1],
					cc_out_sr & 0x1F);
			}
			out("\n");
		}
	}
}

static const uint16_t chkValues[] = {0x0000, 0x0001, 0x7FFF, 0x8000, 0xFFFF, 0x0005};

static void SweepChk(const char *name, const void *code, bool lng)
{
	for (size_t c = 0; c < 2; c++)
	{
		uint16_t ccr = c ? 0x1F : 0;
		for (size_t x = 0; x < COUNT(chkValues); x++)
		{
			out("%s ccr=%02X reg=%04X:", name, ccr, chkValues[x]);
			for (size_t y = 0; y < COUNT(chkValues); y++)
			{
				Setup(code, ccr);
				uint32_t r = (uint32_t)(int32_t)(int16_t)chkValues[x];
				uint32_t b = (uint32_t)(int32_t)(int16_t)chkValues[y];
				state.d[0] = lng ? b : chkValues[y];
				state.d[1] = lng ? r : chkValues[x];
				Run();
				/* The flags as stacked for a trap */
				uint16_t sr = cc_vector ? Word(cc_out_a7) : cc_out_sr;
				out(" %u/%02X", cc_vector, sr & 0x1F);
			}
			out("\n");
		}
	}
}

static const uint8_t boundValues[] = {0x00, 0x10, 0x20, 0x7F, 0x80, 0xF0, 0xFF};

static void SweepBounds(const char *name, const void *code)
{
	for (size_t l = 0; l < COUNT(boundValues); l++)
	{
		for (size_t u = 0; u < COUNT(boundValues); u++)
		{
			out("%s lo=%02X hi=%02X:", name, boundValues[l], boundValues[u]);
			for (size_t r = 0; r < COUNT(boundValues); r++)
			{
				Setup(code, 0);
				dataBuf[0x100] = boundValues[l];
				dataBuf[0x101] = boundValues[u];
				state.d[1] = boundValues[r];
				Run();
				uint16_t sr = cc_vector ? Word(cc_out_a7) : cc_out_sr;
				out(" %u/%02X", cc_vector, sr & 0x1F);
			}
			out("\n");
		}
	}
}

static void SweepShift(const char *name, const void *code)
{
	static const uint8_t counts[] = {0, 1, 15, 16, 17, 31, 32, 33, 63, 64};
	static const uint16_t values[] = {0x0000, 0x0001, 0x8000, 0xFFFF, 0x4000, 0x5555};

	for (size_t c = 0; c < 2; c++)
	{
		uint16_t ccr = c ? 0x1F : 0;
		for (size_t v = 0; v < COUNT(values); v++)
		{
			out("%s ccr=%02X %04X:", name, ccr, values[v]);
			for (size_t n = 0; n < COUNT(counts); n++)
			{
				Setup(code, ccr);
				state.d[0] = counts[n];
				state.d[1] = values[v];
				Run();
				out(" %04lX/%02X", (unsigned long)(state.d[1] & 0xFFFF), cc_out_sr & 0x1F);
			}
			out("\n");
		}
	}
}

/* --- Main --------------------------------------------------------------- */

static void RunTable(void)
{
	for (const struct cc_test *t = cc_table; t->name; t++)
	{
#ifdef NO_A7
		if (t->needs & NA)
		{
			out("%s: left out of this build\n", t->name);
			continue;
		}
#endif
		if (!Runnable(t))
		{
			out("%s: not on this machine\n", t->name);
			continue;
		}
		if (!BeginStep(t->name))
		{
			continue;
		}
		Setup(t->code, 0);
		Snapshot();
		Run();
		PrintResult(t->name, t->code);
		if (t->needs & NF)
		{
			/* After a trap the FPU may be in an exception state */
			if (cc_vector >= 48 && cc_vector <= 54)
			{
				static uint32_t frame[64];
				cc_fpu_save(frame);
				out("  fsave %08lX\n", (unsigned long)frame[0]);
				cc_fpu_null();
			}
		}
		/* A crash from here on still leaves the results of what ran */
		printf("  saving\n");
		SaveResults();
	}
}

int main(void)
{
	static uint32_t fpuSaved[64];
	static uint8_t fpuRegs[96 + 12];

	/* Newlib would buffer the output, which then hides where a hang is */
	setvbuf(stdout, NULL, _IONBF, 0);

	printf(PROGRAM " v%s: don't touch the mouse or the keyboard.\n\n", VERSION);

	cpuType = GestaltOr('proc', 1);
	fpuType = GestaltOr('fpu ', 0);
	mmuType = GestaltOr('mmu ', 0);
	/* Only a 68851 or a 68030 have the PMMU instructions */
	if (mmuType != 2 && mmuType != 3)
	{
		mmuType = 0;
	}

	out(PROGRAM " v%s\n", VERSION);
	out("Machine %ld\nCPU %ld\nFPU %ld\nMMU %ld\n", GestaltOr('mach', 0), cpuType, fpuType,
		GestaltOr('mmu ', 0));
	out("System %04lX\nROM %04X\nAddressing %02X\n", GestaltOr('sysv', 0),
		*(volatile uint16_t *)(*(volatile uint32_t *)LM_ROMBASE + 8),
		*(volatile uint8_t *)LM_MMU32BIT);

	if (GestaltOr('vm  ', 0) & 1)
	{
		out("Virtual memory is on. Turn it off in the Memory control panel, restart and run this again.\n");
		SaveResults();
		getchar();
		return 0;
	}
	if (GestaltOr('a/ux', 0))
	{
		out("This doesn't run under A/UX: it needs the supervisor mode of Mac OS.\n");
		SaveResults();
		getchar();
		return 0;
	}

	dataBuf = (uint8_t *)NewPtr(DATA_SIZE);
	dataCopy = (uint8_t *)NewPtr(DATA_SIZE);
	stackBuf = (uint8_t *)NewPtr(STACK_SIZE);
	stackCopy = (uint8_t *)NewPtr(STACK_SIZE);
	mspBuf = (uint8_t *)NewPtr(1024);
	if (!dataBuf || !dataCopy || !stackBuf || !stackCopy || !mspBuf)
	{
		out("Out of memory\n");
		SaveResults();
		getchar();
		return 0;
	}

	/* The state of the FPU of the system stays as it is, around all this */
	if (fpuType)
	{
		cc_fpu_save(fpuSaved);
		cc_fpu_regs_save(fpuRegs);
	}

	LoadProgress();
	if (BeginStep("Finding an empty slot"))
	{
		FindFaultAddress();
	}
	SaveResults();

	out("\n--- Tests ---\n");
	RunTable();
	out("\n--- Sweeps: result/flags ---\n");
	printf("(the sweeps take a while on a slow Mac)\n");
#define SWEEP(call, name, ...) \
	if (BeginStep(name)) \
	{ \
		call(name, __VA_ARGS__); \
		SaveResults(); \
	}
	SWEEP(SweepBcd, "ABCD", cc_f_abcd, false);
	SWEEP(SweepBcd, "SBCD", cc_f_sbcd, false);
	SWEEP(SweepBcd, "NBCD", cc_f_nbcd, true);
	SWEEP(SweepDiv, "DIVU", cc_f_divu, false);
	SWEEP(SweepDiv, "DIVS", cc_f_divs, true);
	SWEEP(SweepChk, "CHK.W", cc_f_chkw, false);
	SWEEP(SweepShift, "ASL.W", cc_f_aslw);
	SWEEP(SweepShift, "ROXR.W", cc_f_roxrw);
	if (cpuType >= 3)
	{
		SWEEP(SweepChk, "CHK.L", cc_f_chkl, true);
		SWEEP(SweepBounds, "CMP2.B", cc_f_cmp2b);
		SWEEP(SweepBounds, "CHK2.B", cc_f_chk2b);
		SWEEP(SweepLong, "DIVU.L", cc_f_divul, true);
		SWEEP(SweepLong, "DIVS.L", cc_f_divsl, true);
		SWEEP(SweepLong, "MULU.L", cc_f_mulul, false);
		SWEEP(SweepLong, "MULS.L", cc_f_mulsl, false);
	}

	if (fpuType)
	{
		cc_fpu_regs_restore(fpuRegs, fpuSaved);
	}

	out("\nDone.\n");
	SaveResults();
	EndProgress();
	printf("\nSaved. Press Return to quit.\n");
	getchar();
	return 0;
}
