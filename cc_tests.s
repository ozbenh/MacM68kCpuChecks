| The test fragments. Each runs with the registers of Setup() in checks.c
| and ends with E, or in an exception. The result is what the fragment leaves
| in the registers and the memory around them.
|
| T name, mincpu, maxcpu, needs
|   cpu: Gestalt 'proc' value: 1 = 68000, 3 = 68020, 4 = 68030, 5 = 68040
|   needs: NF = FPU, NM = PMMU (68851 or 68030), NB = a bus error address in a5,
|   NA = uses A7 in its own operation, left out of the NoA7 build

	.set	NF, 1
	.set	NM, 2
	.set	NB, 4
	.set	NA, 8

	.macro	T name, min=1, max=9, needs=0
	.text	1
	.long	.Lname\@, .Lcode\@
	.short	\min, \max, \needs, 0
	.text	2
.Lname\@:
	.asciz	"\name"
	.text	0
	.even
.Lcode\@:
	.endm

	.macro	E
	jmp	cc_done
	.endm

| Loads a double into an FP register
	.macro	FD hi, lo, reg
	fmove.d	777f(%pc),\reg
	bra.s	778f
777:	.long	\hi, \lo
778:
	.endm

| An FP test ends with the status and the first two registers in memory at a1
	.macro	FE
	fmove.l	%fpsr,(%a2)
	fmovem.x %fp0-%fp1,(%a1)
	jmp	cc_done
	.endm

	.macro	FS ctl=0
	fmove.l	#0,%fpsr
	fmove.l	#\ctl,%fpcr
	.endm

	.text	1
	.globl	cc_table
cc_table:
	.text	0

| Fragments for the sweeps in checks.c
	.globl	cc_f_abcd, cc_f_sbcd, cc_f_nbcd, cc_f_divu, cc_f_divs, cc_f_chkw
	.globl	cc_f_chkl, cc_f_cmp2b, cc_f_chk2b, cc_f_divul, cc_f_divsl
	.globl	cc_f_mulul, cc_f_mulsl, cc_f_read, cc_f_aslw, cc_f_roxrw
cc_f_abcd:	abcd	%d0,%d1
	E
cc_f_sbcd:	sbcd	%d0,%d1
	E
cc_f_nbcd:	nbcd	%d1
	E
cc_f_divu:	divu.w	%d0,%d1
	E
cc_f_divs:	divs.w	%d0,%d1
	E
cc_f_chkw:	chk.w	%d0,%d1
	E
cc_f_chkl:	chk.l	%d0,%d1
	E
cc_f_cmp2b:	cmp2.b	(%a0),%d1
	E
cc_f_chk2b:	chk2.b	(%a0),%d1
	E
cc_f_divul:	divul.l	%d0,%d2:%d1
	E
cc_f_divsl:	divsl.l	%d0,%d2:%d1
	E
cc_f_mulul:	mulu.l	%d0,%d1
	E
cc_f_mulsl:	muls.l	%d0,%d1
	E
cc_f_read:	move.l	(%a5),%d0
	E
cc_f_aslw:	asl.w	%d0,%d1
	E
cc_f_roxrw:	roxr.w	%d0,%d1
	E

| --- The addressing register in its own operation ---------------------------

	T	"LINK A7,#-16", 1, 9, NA
	link	%a7,#-16
	E
	T	"LINK.L A7,#-16", 3, 9, NA
	.short	0x480F, 0xFFFF, 0xFFF0
	E
	T	"LINK A0,#-16"
	link	%a0,#-16
	E
	T	"UNLK A6"
	move.l	%a0,(%a6)
	unlk	%a6
	E
	T	"UNLK A7, on the stack", 1, 9, NA
	lea	-16(%sp),%a3
	move.l	%a3,(%sp)
	unlk	%a7
	E
	T	"UNLK A7, to the data", 1, 9, NA
	move.l	%a0,(%sp)
	unlk	%a7
	E
	T	"MOVE.L A0,-(A0)"
	move.l	%a0,-(%a0)
	E
	T	"MOVE.L A0,(A0)+"
	move.l	%a0,(%a0)+
	E
	T	"MOVE.W A0,-(A0)"
	move.w	%a0,-(%a0)
	E
	T	"MOVE.L A7,-(A7)", 1, 9, NA
	move.l	%a7,-(%a7)
	E
	T	"MOVE.L -(A0),A0"
	move.l	-(%a0),%a0
	E
	T	"MOVE.L (A0)+,A0"
	move.l	(%a0)+,%a0
	E
	T	"MOVE.L (A0)+,(A0)+"
	move.l	(%a0)+,(%a0)+
	E
	T	"MOVE.L (A0)+,-(A0)"
	move.l	(%a0)+,-(%a0)
	E
	T	"MOVE.L -(A0),(A0)+"
	move.l	-(%a0),(%a0)+
	E
	T	"MOVEM.L D0/A0,-(A0)"
	movem.l	%d0/%a0,-(%a0)
	E
	T	"MOVEM.W D0/A0,-(A0)"
	movem.w	%d0/%a0,-(%a0)
	E
	T	"MOVEM.L D0-D7/A0-A7,-(A7)", 1, 9, NA
	movem.l	%d0-%d7/%a0-%a7,-(%a7)
	E
	T	"MOVEM.L A0,(A0)"
	movem.l	%a0,(%a0)
	E
	T	"MOVEM.L (A0)+,D0/A0"
	movem.l	(%a0)+,%d0/%a0
	E
	T	"MOVEM.W (A0)+,D0/A1"
	movem.w	(%a0)+,%d0/%a1
	E
	T	"PEA (A7)", 1, 9, NA
	pea	(%a7)
	E
	T	"PEA 4(A7)", 1, 9, NA
	pea	4(%a7)
	E
	T	"LEA 4(A7),A7", 1, 9, NA
	lea	4(%a7),%a7
	E
	T	"ADD.L D0,(A0)+"
	add.l	%d0,(%a0)+
	E
	T	"ADD.L (A0)+,A0"
	add.l	(%a0)+,%a0
	E
	T	"ADDA.L (A0)+,A0"
	adda.l	(%a0)+,%a0
	E
	T	"CMPM.L (A0)+,(A0)+"
	cmpm.l	(%a0)+,(%a0)+
	E
	T	"SUBX.L -(A0),-(A0)"
	subx.l	-(%a0),-(%a0)
	E
	T	"ABCD -(A0),-(A0)"
	abcd	-(%a0),-(%a0)
	E
	T	"MOVE.B D0,-(A7)", 1, 9, NA
	move.b	%d0,-(%a7)
	E
	T	"MOVE.B (A7)+,D0", 1, 9, NA
	move.b	(%a7)+,%d0
	E
	T	"CMPM.B (A7)+,(A7)+", 1, 9, NA
	cmpm.b	(%a7)+,(%a7)+
	E
	T	"EXG A0,A7", 1, 9, NA
	exg	%a0,%a7
	movea.l	%a7,%a1
	movea.l	%a0,%a7
	E
	T	"RTD #8", 2
	lea	1f(%pc),%a3
	move.l	%a3,-(%sp)
	rtd	#8
1:	E
	T	"MOVEP.L D0,1(A0)"
	movep.l	%d0,1(%a0)
	E
	T	"MOVEP.W 1(A0),D0"
	movep.w	1(%a0),%d0
	E

| --- Odd stack pointer, odd address register -------------------------------
| A byte push moves A7 by 2. Word and long pushes on an odd SP are only for the
| 68020 on: on a 68000 the address error can't stack its frame, and that halts.

	T	"Odd SP, MOVE.B D0,-(A7)", 1, 9, NA
	addq.l	#1,%a7
	move.b	%d0,-(%a7)
	move.l	%a7,%d1
	subq.l	#1,%a7
	E
	T	"Odd SP, MOVE.B (A7)+,D0", 1, 9, NA
	addq.l	#1,%a7
	move.b	(%a7)+,%d0
	move.l	%a7,%d1
	subq.l	#3,%a7
	E
	T	"Odd SP, MOVE.W D0,-(A7)", 3, 9, NA
	addq.l	#1,%a7
	move.w	%d0,-(%a7)
	move.l	%a7,%d1
	addq.l	#1,%a7
	E
	T	"Odd SP, MOVE.L D0,-(A7)", 3, 9, NA
	addq.l	#1,%a7
	move.l	%d0,-(%a7)
	move.l	%a7,%d1
	addq.l	#3,%a7
	E
	T	"Odd SP, MOVEM.L D0-D1/A7,-(A7)", 3, 9, NA
	addq.l	#1,%a7
	movem.l	%d0-%d1/%a7,-(%a7)
	move.l	%a7,%d2
	lea	11(%a7),%a7
	E
	T	"Odd SP, LINK A7,#-16", 3, 9, NA
	addq.l	#1,%a7
	link	%a7,#-16
	move.l	%a7,%d1
	lea	19(%a7),%a7
	E
	T	"Odd SP, PEA (A7)", 3, 9, NA
	addq.l	#1,%a7
	pea	(%a7)
	move.l	%a7,%d1
	addq.l	#3,%a7
	E
	T	"Odd SP, JSR", 3, 9, NA
	addq.l	#1,%a7
	jsr	1f(%pc)
1:	move.l	%a7,%d1
	addq.l	#3,%a7
	E
	T	"Odd SP, TRAP #5", 3, 9, NA
	addq.l	#1,%a7
	trap	#5
	E
	T	"Odd SP, UNLK A7", 3, 9, NA
	addq.l	#1,%a7
	move.l	%a0,(%a7)
	unlk	%a7
	E
	T	"Odd A0, MOVE.B D0,-(A0)"
	addq.l	#1,%a0
	move.b	%d0,-(%a0)
	E
	T	"Odd A0, MOVE.W D0,-(A0)"
	addq.l	#1,%a0
	move.w	%d0,-(%a0)
	E
	T	"Odd A0, MOVE.L D0,-(A0)"
	addq.l	#1,%a0
	move.l	%d0,-(%a0)
	E
	T	"Odd A0, MOVE.W (A0)+,D0"
	addq.l	#1,%a0
	move.w	(%a0)+,%d0
	E
	T	"Odd A0, MOVE.L (A0)+,D0"
	addq.l	#1,%a0
	move.l	(%a0)+,%d0
	E
	T	"Odd A0, MOVEM.L D0-D1,-(A0)"
	addq.l	#1,%a0
	movem.l	%d0-%d1,-(%a0)
	E
	T	"Odd A0, MOVEM.L (A0)+,D0-D1"
	addq.l	#1,%a0
	movem.l	(%a0)+,%d0-%d1
	E
	T	"Odd A0, ADD.W D0,-(A0)"
	addq.l	#1,%a0
	add.w	%d0,-(%a0)
	E

| --- 68020 forms with registers in odd places ---------------------------

	T	"CAS.L Dc=Du", 3
	move.l	(%a0),%d1
	cas.l	%d1,%d1,(%a0)
	E
	T	"CAS.L mismatch", 3
	cas.l	%d1,%d2,(%a0)
	E
	T	"CAS.L (A0)+", 3
	cas.l	%d1,%d2,(%a0)+
	E
	T	"CAS.L -(A0)", 3
	cas.l	%d1,%d2,-(%a0)
	E
	T	"CAS.B A7 inc", 3, 9, NA
	cas.b	%d1,%d2,(%a7)+
	E
	T	"CAS2.L match", 3
	move.l	(%a0),%d1
	move.l	(%a1),%d2
	cas2.l	%d1:%d2,%d3:%d4,(%a0):(%a1)
	E
	T	"CAS2.L first mismatch, same Dc", 3
	cas2.l	%d1:%d1,%d3:%d4,(%a0):(%a1)
	E
	T	"CAS2.W same address", 3
	move.w	(%a0),%d1
	move.w	(%a0),%d2
	cas2.w	%d1:%d2,%d3:%d4,(%a0):(%a0)
	E
	T	"MULU.L Dh=Dl", 3
	mulu.l	%d1,%d2:%d2
	E
	T	"MULS.L Dh=Dl", 3
	muls.l	%d1,%d2:%d2
	E
	T	"DIVU.L Dr=Dq", 3
	divu.l	%d1,%d2:%d2
	E
	T	"DIVSL.L 32/32 Dr=Dq", 3
	divsl.l	%d1,%d2:%d2
	E
	T	"BFFFO D0{D1:D2} big offset", 3
	move.l	#35,%d1
	moveq	#8,%d2
	bfffo	%d0{%d1:%d2},%d3
	E
	T	"BFFFO none set, negative offset", 3
	moveq	#-3,%d1
	moveq	#8,%d2
	clr.l	(%a0)
	clr.l	-4(%a0)
	bfffo	(%a0){%d1:%d2},%d3
	E
	T	"BFEXTU width 0 is 32", 3
	moveq	#4,%d1
	moveq	#0,%d2
	bfextu	%d0{%d1:%d2},%d3
	E
	T	"BFEXTS 5 byte field", 3
	bfexts	(%a0){7:32},%d3
	E
	T	"BFINS 5 byte field", 3
	bfins	%d0,(%a0){7:32}
	E
	T	"BFINS register wraps", 3
	bfins	%d1,%d0{28:8}
	E
	T	"BFCHG negative Dn offset", 3
	moveq	#-20,%d1
	bfchg	(%a0){%d1:12}
	E
	T	"PACK -(A0),-(A0)", 3
	pack	-(%a0),-(%a0),#0x1234
	E
	T	"UNPK D0,D0", 3
	unpk	%d0,%d0,#0x1234
	E
	T	"EXTB.L", 3
	extb.l	%d0
	E
	T	"SCALED INDEX D1*8", 3
	moveq	#2,%d1
	move.l	(0,%a0,%d1.l*8),%d3
	E
	T	"FULL EA ([4,A0],D1*2,8)", 3
	move.l	%a1,4(%a0)
	moveq	#2,%d1
	move.l	([4,%a0],%d1.w*2,8),%d3
	E
	T	"FULL EA ([4,A0,D1*2],8)", 3
	move.l	%a1,8(%a0)
	moveq	#2,%d1
	move.l	([4,%a0,%d1.w*2],8),%d3
	E
	T	"MOVES.L (A0),D1 FC5", 3
	moveq	#5,%d7
	movec	%d7,%sfc
	moves.l	(%a0),%d1
	E
	T	"MOVES.L A0,(A0)+", 3
	moveq	#5,%d7
	movec	%d7,%dfc
	moves.l	%a0,(%a0)+
	E
	T	"MOVES.L A0,-(A0)", 3
	moveq	#5,%d7
	movec	%d7,%dfc
	moves.l	%a0,-(%a0)
	E
	T	"MOVES.W (A0),A1 sign", 3
	moveq	#5,%d7
	movec	%d7,%sfc
	moves.w	(%a0),%a1
	E

| --- Status register and control registers --------------------------------

	T	"SR all ones"
	move.w	#0xFFFF,%d0
	andi.w	#0x3FFF,%d0
	ori.w	#0x0700,%d0
	move.w	%d0,%sr
	move.w	%sr,%d1
	move.w	#0x2700,%sr
	E
	T	"CCR all ones"
	move.w	#0xFFFF,%ccr
	move.w	%sr,%d1
	E
	T	"MOVE SR,D0 keeps upper word"
	move.w	%sr,%d0
	E
	T	"MOVE CCR,D0", 2
	move.w	#0x1F,%ccr
	move.w	%ccr,%d0
	E
	T	"M bit stack switch", 3
	move.l	%a7,%d1
	ori.w	#0x1000,%sr
	move.l	%a7,%d2
	move.w	%sr,%d3
	andi.w	#0xEFFF,%sr
	E
	T	"MOVEC SFC DFC masks", 3
	moveq	#-1,%d0
	movec	%d0,%sfc
	movec	%d0,%dfc
	movec	%sfc,%d1
	movec	%dfc,%d2
	moveq	#0,%d0
	movec	%d0,%sfc
	movec	%d0,%dfc
	E
	T	"MOVEC undefined register", 3
	.short	0x4E7A, 0x1FFF
	E
	T	"CACR write all ones", 3, 4
	movec	%cacr,%d4
	moveq	#-1,%d0
	movec	%d0,%cacr
	movec	%cacr,%d1
	move.l	#0x0808,%d0
	movec	%d0,%cacr
	movec	%d4,%cacr
	moveq	#0,%d4
	E
	T	"CAAR write all ones", 3, 4
	movec	%caar,%d4
	moveq	#-1,%d0
	movec	%d0,%caar
	movec	%caar,%d1
	movec	%d4,%caar
	moveq	#0,%d4
	E

| --- Exception frames ---------------------------------------------------

	T	"ILLEGAL"
	illegal
	E
	T	"LINE A"
	.short	0xA123
	E
	T	"LINE F, coprocessor 7"
	.short	0xFE00
	E
	T	"BKPT #3"
	.short	0x484B
	E
	T	"TRAP #5"
	trap	#5
	E
	T	"TRAPV"
	move.w	#2,%ccr
	trapv
	E
	T	"TRAPT", 3
	trapt
	E
	T	"TRAPT.W", 3
	trapt.w	#0x1234
	E
	T	"TRAPT.L", 3
	trapt.l	#0x12345678
	E
	T	"CHK.W trap"
	moveq	#5,%d1
	moveq	#2,%d0
	chk.w	%d0,%d1
	E
	T	"CHK2.L trap", 3
	move.l	#0x80000000,(%a0)
	move.l	#0x80000001,4(%a0)
	chk2.l	(%a0),%d1
	E
	T	"DIVU.W by zero"
	moveq	#0,%d0
	divu.w	%d0,%d1
	E
	T	"DIVS.L by zero", 3
	moveq	#0,%d0
	divs.l	%d0,%d1
	E
	T	"Privilege, MOVE to SR"
	move	#0x0700,%sr
	move	#0x2700,%sr
	E
	T	"Privilege, MOVEC", 3
	move	#0x0700,%sr
	movec	%vbr,%d0
	E
	T	"Trace, NOP"
	ori.w	#0x8000,%sr
	nop
	E
	T	"Trace, TRAP"
	ori.w	#0x8000,%sr
	trap	#5
	E
	T	"Trace, illegal"
	ori.w	#0x8000,%sr
	illegal
	E
	T	"Trace on change of flow, NOP", 3
	ori.w	#0x4000,%sr
	nop
	move.w	%sr,%d1
	andi.w	#0x3FFF,%sr
	E
	T	"Trace on change of flow, BRA", 3
	ori.w	#0x4000,%sr
	bra.s	1f
	nop
1:	andi.w	#0x3FFF,%sr
	E
	T	"RTE format 0"
	lea	1f(%pc),%a3
	move.w	#0,-(%sp)
	move.l	%a3,-(%sp)
	move.w	#0x2700,-(%sp)
	rte
1:	E
	T	"RTE format 1 alone", 3
	lea	1f(%pc),%a3
	move.w	#0x1020,-(%sp)
	move.l	%a3,-(%sp)
	move.w	#0x2700,-(%sp)
	rte
1:	E
	T	"RTE undefined format", 3
	lea	1f(%pc),%a3
	move.w	#0xF020,-(%sp)
	move.l	%a3,-(%sp)
	move.w	#0x2700,-(%sp)
	rte
1:	E
	T	"M=1, TRAP", 3
	ori.w	#0x1000,%sr
	trap	#5
	E

| --- Odd addresses --------------------------------------------------------

	T	"JMP odd"
	lea	1f+1(%pc),%a3
	jmp	(%a3)
	E
1:	nop
	E
	T	"JSR odd"
	lea	1f+1(%pc),%a3
	jsr	(%a3)
	E
1:	nop
	E
	T	"RTS odd"
	lea	1f+1(%pc),%a3
	move.l	%a3,-(%sp)
	rts
	E
1:	nop
	E
	T	"RTE odd"
	lea	1f+1(%pc),%a3
	move.w	#0,-(%sp)
	move.l	%a3,-(%sp)
	move.w	#0x2700,-(%sp)
	rte
	E
1:	nop
	E
	T	"Read word odd"
	move.w	1(%a0),%d1
	E
	T	"Read long odd"
	move.l	1(%a0),%d1
	E
	T	"Write long odd"
	move.l	%d0,1(%a0)
	E
	T	"MOVEM odd"
	movem.l	%d0-%d1,1(%a0)
	E

| --- Bus errors, on an empty slot -----------------------------------------

	T	"Bus error, read byte", 3, 4, NB
	move.b	(%a5),%d1
	E
	T	"Bus error, read word", 3, 4, NB
	move.w	(%a5),%d1
	E
	T	"Bus error, read long", 3, 4, NB
	move.l	(%a5),%d1
	E
	T	"Bus error, write byte", 3, 4, NB
	move.b	%d0,(%a5)
	E
	T	"Bus error, write word", 3, 4, NB
	move.w	%d0,(%a5)
	E
	T	"Bus error, write long", 3, 4, NB
	move.l	%d0,(%a5)
	E
	T	"Bus error, TAS", 3, 4, NB
	tas	(%a5)
	E
	T	"Bus error, CAS", 3, 4, NB
	cas.l	%d1,%d2,(%a5)
	E
	T	"Bus error, MOVEM to memory", 3, 4, NB
	movem.l	%d0-%d3,(%a5)
	E
	T	"Bus error, memory indirect", 3, 4, NB
	move.l	([0,%a5]),%d1
	E
	T	"Bus error, JMP", 3, 4, NB
	jmp	(%a5)
	E
	T	"Bus error, MOVES FC5", 3, 4, NB
	moveq	#5,%d7
	movec	%d7,%sfc
	moves.l	(%a5),%d1
	E

| --- MMU, read only ---------------------------------------------------------

	T	"PMOVE out TC CRP SRP", 3, 4, NM
	pmove	%tc,(%a1)
	pmove	%crp,8(%a1)
	pmove	%srp,16(%a1)
	E
	T	"PTESTR FC5 level 7", 3, 4, NM
	ptestr	#5,(%a0),#7,%a2
	pmove	%psr,(%a1)
	E
	T	"PTESTR FC5 level 0", 3, 4, NM
	ptestr	#5,(%a0),#0
	pmove	%psr,(%a1)
	E
	T	"MMUSR: set it, bus error", 3, 4, NM+NB
	ptestr	#5,(%a0),#7
	pmove	%psr,(%a1)
	move.l	(%a5),%d1
	E
	T	"MMUSR: after the bus error", 3, 4, NM
	pmove	%psr,(%a1)
	E
	T	"MMU instruction in user mode", 3, 4, NM
	move	#0x0700,%sr
	pmove	%psr,(%a1)
	E
	T	"PFLUSHA in user mode", 3, 4, NM
	move	#0x0700,%sr
	pflusha
	E

| --- FPU ------------------------------------------------------------------

	T	"FMOVE.L rounding", 3, 9, NF
	FS
	FD	0x400C0000, 0, %fp0		| 3.5
	fmove.l	%fp0,%d1
	FD	0x40040000, 0, %fp0		| 2.5
	fmove.l	%fp0,%d2
	FD	0xC0040000, 0, %fp0		| -2.5
	fmove.l	%fp0,%d3
	FE
	T	"FMOVE.L round toward zero", 3, 9, NF
	FS	0x10
	FD	0x400C0000, 0, %fp0
	fmove.l	%fp0,%d1
	FE
	T	"FMOVE.L overflow", 3, 9, NF
	FS
	FD	0x426D1A94, 0xA2000000, %fp0	| 1e12
	fmove.l	%fp0,%d1
	FE
	T	"FMOVE.W overflow", 3, 9, NF
	FS
	FD	0x40F00000, 0, %fp0		| 65536
	fmove.w	%fp0,%d1
	FE
	T	"FINT ties", 3, 9, NF
	FS
	FD	0x40040000, 0, %fp0
	fint.x	%fp0,%fp0
	FD	0x400C0000, 0, %fp1
	fint.x	%fp1,%fp1
	FE
	T	"FINTRZ", 3, 9, NF
	FS
	FD	0xC00C0000, 0, %fp0
	fintrz.x	%fp0,%fp0
	FE
	T	"FCMP infinities", 3, 9, NF
	FS
	FD	0x7FF00000, 0, %fp0
	FD	0x7FF00000, 0, %fp1
	fcmp.x	%fp1,%fp0
	FE
	T	"FCMP +0 -0", 3, 9, NF
	FS
	FD	0x80000000, 0, %fp0
	FD	0, 0, %fp1
	fcmp.x	%fp1,%fp0
	FE
	T	"FCMP keeps the destination, FPCR single", 3, 9, NF
	FS	0x40
	FD	0x3FF00000, 0x00001000, %fp0
	FD	0x3FF00000, 0, %fp1
	fcmp.x	%fp1,%fp0
	FE
	T	"FTST keeps the register, FPCR single", 3, 9, NF
	FS	0x40
	FD	0x3FF00000, 0x00001000, %fp0
	ftst.x	%fp0
	FE
	T	"FADD exact in single, FPCR single", 3, 9, NF
	FS	0x40
	FD	0x3FF00000, 0x10000000, %fp0	| 1 + 2^-24
	FD	0x3E700000, 0, %fp1		| 2^-24
	fadd.x	%fp1,%fp0
	FE
	T	"FDIV by zero status", 3, 9, NF
	FS
	FD	0x3FF00000, 0, %fp0
	FD	0, 0, %fp1
	fdiv.x	%fp1,%fp0
	FE
	T	"FDIV inexact status", 3, 9, NF
	FS
	FD	0x3FF00000, 0, %fp0
	FD	0x40080000, 0, %fp1
	fdiv.x	%fp1,%fp0
	FE
	T	"FSQRT of -1 status", 3, 9, NF
	FS
	FD	0xBFF00000, 0, %fp0
	fsqrt.x	%fp0,%fp0
	FE
	T	"FMUL overflow status", 3, 9, NF
	FS
	lea	cc_big(%pc),%a3
	fmove.x	(%a3),%fp0
	fmul.x	%fp0,%fp0
	FE
	T	"FADD status of a signalling NaN", 3, 9, NF
	FS
	lea	cc_snan(%pc),%a3
	fmove.x	(%a3),%fp0
	FD	0x3FF00000, 0, %fp1
	fadd.x	%fp0,%fp1
	FE
	T	"FGETMAN -6", 3, 9, NF
	FS
	FD	0xC0180000, 0, %fp0
	fgetman.x	%fp0,%fp0
	FE
	T	"FGETEXP 8 and 0", 3, 9, NF
	FS
	FD	0x40200000, 0, %fp0
	fgetexp.x	%fp0,%fp0
	FD	0, 0, %fp1
	fgetexp.x	%fp1,%fp1
	FE
	T	"FMOD -10 by 3", 3, 9, NF
	FS
	FD	0xC0240000, 0, %fp0
	FD	0x40080000, 0, %fp1
	fmod.x	%fp1,%fp0
	FE
	T	"FREM 10 by 3", 3, 9, NF
	FS
	FD	0x40240000, 0, %fp0
	FD	0x40080000, 0, %fp1
	frem.x	%fp1,%fp0
	FE
	T	"FMOD 2^70 by 3", 3, 9, NF
	FS
	FD	0x44500000, 0, %fp0
	FD	0x40080000, 0, %fp1
	fmod.x	%fp1,%fp0
	FE
	T	"FETOXM1 and FLOGNP1 of 1e-20", 3, 9, NF
	FS
	FD	0x3BC79CA1, 0x0C924223, %fp1
	fetoxm1.x	%fp1,%fp0
	flognp1.x	%fp1,%fp1
	FE
	T	"FSCALE", 3, 9, NF
	FS
	FD	0x3FF80000, 0, %fp0
	FD	0x40100000, 0, %fp1
	fscale.x	%fp1,%fp0
	FE
	T	"FMOVEM.L FPCR/FPSR/FPIAR,(A0)", 3, 9, NF
	FS	0x10
	fmove.l	#0x08000000,%fpsr
	fmove.l	#0x12345678,%fpiar
	fmovem.l %fpcr/%fpsr/%fpiar,(%a0)
	FS
	E
	T	"FMOVEM.L FPCR/FPSR/FPIAR,-(A0)", 3, 9, NF
	FS	0x10
	fmove.l	#0x08000000,%fpsr
	fmove.l	#0x12345678,%fpiar
	fmovem.l %fpcr/%fpsr/%fpiar,-(%a0)
	FS
	E
	T	"FMOVEM.L FPCR/FPSR,4(A0)", 3, 9, NF
	FS	0x10
	fmove.l	#0x08000000,%fpsr
	fmovem.l %fpcr/%fpsr,4(%a0)
	FS
	E
	T	"FMOVEM.L (A0)+,FPCR/FPSR", 3, 9, NF
	clr.l	(%a0)
	clr.l	4(%a0)
	fmovem.l (%a0)+,%fpcr/%fpsr
	E
	T	"FPCR write all ones", 3, 9, NF
	moveq	#-1,%d0
	fmove.l	#0,%fpsr
	fmove.l	%d0,%fpcr
	fmove.l	%fpcr,%d1
	fmove.l	#0,%fpcr
	E
	T	"FPSR write all ones", 3, 9, NF
	fmove.l	#0,%fpcr
	moveq	#-1,%d0
	fmove.l	%d0,%fpsr
	fmove.l	%fpsr,%d1
	fmove.l	#0,%fpsr
	E
	T	"FPIAR after FADD", 3, 9, NF
	fmove.l	#0,%fpiar
	lea	1f(%pc),%a3
	FS
1:	fadd.x	%fp0,%fp0
	fmove.l	%fpiar,%d1
	sub.l	%a3,%d1
	suba.l	%a3,%a3
	E
	T	"FPIAR after FMOVE to FPSR", 3, 9, NF
	fmove.l	#0x12345678,%fpiar
	FS
	fmove.l	%fpiar,%d1
	E
	T	"FPCR precision 11", 3, 9, NF
	FS	0xC0
	FD	0x3FF00000, 0x00000001, %fp0
	FD	0x3FF00000, 0, %fp1
	fadd.x	%fp1,%fp0
	fmove.l	#0,%fpcr
	FE
	T	"FMOVEM.X bit patterns", 3, 9, NF
	lea	cc_fpx(%pc),%a3
	fmovem.x (%a3),%fp0-%fp5
	fmovem.x %fp0-%fp5,(%a1)
	E
	T	"FMOVE.X of unnormal and denormal", 3, 9, NF
	FS
	lea	cc_fpx(%pc),%a3
	fmove.x	24(%a3),%fp0
	fmove.x	48(%a3),%fp1
	FE
	T	"FDIV by zero trap", 3, 9, NF
	FS	0x0400
	FD	0x3FF00000, 0, %fp0
	FD	0, 0, %fp1
	fdiv.x	%fp1,%fp0
	fnop
	E
	T	"FDIV inexact trap", 3, 9, NF
	FS	0x0200
	FD	0x3FF00000, 0, %fp0
	FD	0x40080000, 0, %fp1
	fdiv.x	%fp1,%fp0
	fnop
	E
	T	"BSUN trap", 3, 9, NF
	FS	0x8000
	fmove.l	#0x01000000,%fpsr
	fbgt	1f
1:	fnop
	E
	T	"FBcc predicate 32", 3, 9, NF
	FS
	.short	0xF2A0, 0x0002
	E
	T	"FSAVE after reset", 3, 9, NF
	lea	cc_null(%pc),%a3
	frestore (%a3)
	fsave	(%a1)
	E
	T	"FSAVE after an operation", 3, 9, NF
	FS
	FD	0x3FF00000, 0, %fp0
	fsave	(%a1)
	frestore (%a1)
	E
	T	"FSAVE in user mode", 3, 9, NF
	move	#0x0700,%sr
	fsave	(%a1)
	E
	T	"FRESTORE in user mode", 3, 9, NF
	lea	cc_null(%pc),%a3
	move	#0x0700,%sr
	frestore (%a3)
	E
	T	"FRESTORE bad frame", 3, 9, NF
	lea	cc_badframe(%pc),%a3
	frestore (%a3)
	E

| --- Last, as it stops some emulators ---------------------------------------

	T	"DIVS.W $80000000 by -1"
	move.l	#0x80000000,%d1
	moveq	#-1,%d0
	divs.w	%d0,%d1
	E

	.even
cc_big:		.long	0x7FFE0000, 0x80000000, 0
cc_snan:	.long	0x7FFF0000, 0xA0000000, 0
cc_null:	.long	0
cc_badframe:	.long	0x55180000
cc_fpx:		.long	0x7FFF0000, 0xC0000000, 0x00001234	| quiet NaN, payload
		.long	0x7FFF0000, 0xA0000000, 0x00000001	| signalling NaN
		.long	0x3FFF0000, 0x40000000, 0x00000000	| unnormal
		.long	0x00000000, 0x00000000, 0x00000001	| denormal
		.long	0x80000000, 0x00000000, 0x00000000	| -0
		.long	0x7FFF0000, 0x00000000, 0x00000000	| infinity

	.text	1
	.long	0, 0, 0, 0
