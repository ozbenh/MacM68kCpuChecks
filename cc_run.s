| Runs one test fragment with its own registers, SR and stack, and catches
| every exception on the way.
|
| void cc_run(void)
|
| Takes the struct cc_state pointed to by cc_s. The 68020 and later get a
| private vector table in VBR; on the 68000 the caller patches the low memory
| vectors around the call. Interrupts stay masked throughout.

	.text
	.globl	cc_run, cc_done, cc_s, cc_is020, cc_vector, cc_out_a6, cc_out_a7
	.globl	cc_out_sr, cc_vectors, cc_fpu_save, cc_fpu_null, cc_fpu_regs_save, cc_fpu_regs_restore

| Offsets in struct cc_state
	.set	ST_REGS, 0	| d0-d7, a0-a6
	.set	ST_A7, 60	| where the fragment starts: the stack with its address on top
	.set	ST_USP, 64
	.set	ST_MSP, 68
	.set	ST_SR, 72

cc_run:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.w	%sr,-(%sp)
	ori.w	#0x0700,%sr
	move.l	%usp,%a0
	move.l	%a0,-(%sp)
	move.l	%sp,cc_saved_sp
	move.w	#0,cc_vector
	movea.l	cc_s,%a6
	tst.b	cc_is020
	beq.s	1f
	movec	%vbr,%d0
	move.l	%d0,cc_saved_vbr
	movec	%msp,%d0
	move.l	%d0,cc_saved_msp
	lea	cc_vectors,%a0
	movec	%a0,%vbr
	move.l	ST_MSP(%a6),%d0
	movec	%d0,%msp
1:
	move.l	ST_USP(%a6),%a0
	move.l	%a0,%usp
	movea.l	ST_A7(%a6),%sp
	move.w	ST_SR(%a6),%sr
	movem.l	(%a6),%d0-%d7/%a0-%a6
	rts

| The end of a fragment, or an exception through the stubs below
cc_done:
	move.l	%a7,cc_out_a7
	move.l	%a6,cc_out_a6
	move.w	%sr,cc_out_sr
	movea.l	cc_s,%a6
	movem.l	%d0-%d7/%a0-%a5,(%a6)
	move.w	#0x2700,%sr
	movea.l	cc_saved_sp,%sp
	tst.b	cc_is020
	beq.s	1f
	move.l	cc_saved_msp,%d0
	movec	%d0,%msp
	move.l	cc_saved_vbr,%d0
	movec	%d0,%vbr
1:
	move.l	(%sp)+,%a0
	move.l	%a0,%usp
	move.w	(%sp)+,%sr
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

| void cc_fpu_save(void *frame): FSAVE, the frame is up to 216 bytes
cc_fpu_save:
	move.l	4(%sp),%a0
	fsave	(%a0)
	rts

| void cc_fpu_null(void): FRESTORE of a null frame, resets the FPU
cc_fpu_null:
	clr.l	-(%sp)
	frestore (%sp)+
	rts

| void cc_fpu_regs_save(void *regs): the FP registers
cc_fpu_regs_save:
	move.l	4(%sp),%a0
	fmovem.x %fp0-%fp7,(%a0)
	fmovem.l %fpcr/%fpsr/%fpiar,96(%a0)
	rts

| void cc_fpu_regs_restore(const void *regs, const void *frame)
cc_fpu_regs_restore:
	move.l	4(%sp),%a0
	fmovem.x (%a0),%fp0-%fp7
	fmovem.l 96(%a0),%fpcr/%fpsr/%fpiar
	move.l	8(%sp),%a0
	frestore (%a0)
	rts

| One stub per vector, the vector number in cc_vector
	.set	n, 0
	.macro	STUB
	move.w	#n,cc_vector
	jmp	cc_done
	.set	n, n+1
	.endm
cc_stubs:
	.rept	256
	STUB
	.endr

	.even
cc_vectors:
	.set	n, 0
	.rept	256
	.long	cc_stubs + n * 14
	.set	n, n+1
	.endr

	.data
	.even
cc_s:		.long	0
cc_saved_sp:	.long	0
cc_saved_vbr:	.long	0
cc_saved_msp:	.long	0
cc_out_a6:	.long	0
cc_out_a7:	.long	0
cc_out_sr:	.short	0
cc_vector:	.short	0
cc_is020:	.byte	0
	.even
