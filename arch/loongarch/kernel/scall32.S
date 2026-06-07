/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#include <linux/errno.h>
#include <asm/asm.h>
#include <asm/asmmacro.h>
#include <asm/irqflags.h>
#include <asm/loongarchregs.h>
#include <asm/regdef.h>
#include <asm/stackframe.h>
#include <asm/asm-offsets.h>
#include <asm/thread_info.h>
#include <asm/unistd.h>

	.text
	.cfi_sections	.debug_frame
	.align	5
SYM_FUNC_START(handle_sys)
	// uty: test
	// SAVE_ALL do not change to kernelsp
	//SAVE_ALL

	// try not use kernelsp
	// //csrrd	t0, PERCPU_BASE_KS
	// la.abs	t1, kernelsp
	// //PTR_ADDU	t1, t1, t0
	 //or	t2, sp, zero
	 or	t0, sp, zero
	// LONG_L	sp, t1, 0

	PTR_ADDIU	sp, sp, -PT_SIZE
	// t2 is usersp
	//cfi_st	t2, PT_R3
	cfi_st	t0, PT_R3
	cfi_rel_offset  sp, PT_R3
	//csrrd	t2, LOONGARCH_CSR_PRMD
	csrrd	t0, LOONGARCH_CSR_PRMD
	//LONG_S	t2, sp, PT_PRMD
	LONG_S	t0, sp, PT_PRMD
	//csrrd	t2, LOONGARCH_CSR_CRMD
	csrrd	t0, LOONGARCH_CSR_CRMD
	//LONG_S	t2, sp, PT_CRMD
	LONG_S	t0, sp, PT_CRMD
	//csrrd	t2, LOONGARCH_CSR_ECFG
	//csrrd	t0, LOONGARCH_CSR_ECFG
	//LONG_S	t2, sp, PT_ECFG
	//LONG_S	t0, sp, PT_ECFG
	//csrrd	t2, LOONGARCH_CSR_EUEN
	//csrrd	t0, LOONGARCH_CSR_EUEN
	//LONG_S	t2, sp, PT_EUEN
	//LONG_S	t0, sp, PT_EUEN

	cfi_st	ra, PT_R1
	//cfi_st	zero, PT_R1
	cfi_st	a0, PT_R4
	cfi_st	a1, PT_R5
	cfi_st	a2, PT_R6
	cfi_st	a3, PT_R7
	cfi_st	a4, PT_R8
	cfi_st	a5, PT_R9
	cfi_st	a6, PT_R10
	cfi_st	a7, PT_R11
	//csrrd	ra, LOONGARCH_CSR_EPC
	csrrd	t0, LOONGARCH_CSR_EPC
	//LONG_S	ra, sp, PT_EPC
	LONG_S	t0, sp, PT_EPC

	//cfi_rel_offset ra, PT_EPC

	// store user tp to PT_R2
	cfi_st	tp, PT_R2
	cfi_st	x0, PT_R21
	cfi_st	fp, PT_R22

	// now tp points to kernel address,
	// but kernelsp & 0xffffe000 is not where kernel tp is
	// there is no kernel tp
	// PTR_LI	tp, ~_THREAD_MASK
	// and	tp, tp, sp

//	// uty: test
	SAVE_TEMP
	SAVE_STATIC
//	move    a0, tp               # 第一个参数：tp
//	move    a1, sp               # 第二个参数：regs (sp 当前指向 pt_regs)
//	la.abs  t0, check_tp_and_regs
//	jirl    ra, t0, 0
//	//
//
//	STI

	// uty: test
	CLI

	// uty: test
	//move    a0, zero             # test
	//la.abs  t0, check_syscall_number
	//jirl    ra, t0, 0

	/* save the initial A0 value (needed in signal handlers) */
	LONG_S	a0, sp, PT_ORIG_A0
	LONG_L	t1, sp, PT_EPC		# skip syscall on return
	PTR_ADDIU	t1, t1, 4		# skip to next instruction
	LONG_S	t1, sp, PT_EPC

//	// uty: test
//	PTR_LI	t1, _TIF_WORK_SYSCALL_ENTRY
//	LONG_L	t0, tp, TI_FLAGS	# syscall tracing enabled?
//	and	t0, t1, t0
//	bnez	t0, syscall_trace_entry
//
syscall_common:
	/* Check to make sure we don't jump to a bogus syscall number. */
	li.w	t0, __NR_syscalls
	PTR_SUBU	t2, a7, t0

	// uty: test
	//move    a0, a7               # 第一个参数：syscall number
	//la.abs  t0, check_syscall_number
	//jirl    ra, t0, 0

	bgez	t2, illegal_syscall

	/* Syscall number held in a7 */
	LONG_SLL	t0, a7, 2		# offset into table
	la	t2, sys_call_table
	PTR_ADDU	t0, t2, t0
	LONG_L	t2, t0, 0		#syscall routine
	beqz    t2, illegal_syscall

	// uty: test
	//move    a0, t2               # 第一个参数：syscall routine addr
	//la.abs  t0, check_syscall_routine
	//jirl    ra, t0, 0

	jalr	t2			# Do The Real Thing (TM)

	// uty: test
	//move    a0, tp               # 第一个参数：tp
	//move    a1, sp               # 第二个参数：regs (sp 当前指向 pt_regs)
	//la.abs  t0, check_tp_and_regs
	//jirl    ra, t0, 0

//loop:
//	b loop

	// uty: test
	//LONG_L	t1, sp, PT_R11		# syscall number
	//PTR_ADDIU	t1, t1, 1		# +1 for handle_signal
	//LONG_S	t1, sp, PT_R0		# save it for syscall restarting
	//LONG_S	v0, sp, PT_R4		# result

la_syscall_exit:
	// uty: test
	//b	syscall_exit_partial
	//b	syscall_exit
	//la.abs	t0, ret_from_exception
	//jirl    zero, t0, 0

	RESTORE_TEMP
	RESTORE_STATIC
//restore_partial:		# restore partial frame
	RESTORE_SOME

	//// uty: test
	//la.abs  t0, check_epc
	//jirl    ra, t0, 0

	//RESTORE_SP_AND_RET
	ld.w    $r3,$r3,0xc
	ertn

// uty: test
loop1:
	b loop1
/* ------------------------------------------------------------------------ */

//syscall_trace_entry:
//	SAVE_STATIC
//	move	a0, sp
//	move	a1, a7
//	bl	syscall_trace_enter
//
//	blt	v0, zero, 1f			# seccomp failed? Skip syscall
//
//	RESTORE_STATIC
//	LONG_L	a0, sp, PT_R4		# Restore argument registers
//	LONG_L	a1, sp, PT_R5
//	LONG_L	a2, sp, PT_R6
//	LONG_L	a3, sp, PT_R7
//	LONG_L	a4, sp, PT_R8
//	LONG_L	a5, sp, PT_R9
//	LONG_L	a6, sp, PT_R10
//	LONG_L	a7, sp, PT_R11		# Restore syscall (maybe modified)
//	b	syscall_common
//
//1:	b	syscall_exit
//
//	/*
//	 * The system call does not exist in this kernel
//	 */
//
illegal_syscall:
	/* This also isn't a valid syscall, throw an error.  */
	li.w	v0, -ENOSYS			# error
	LONG_S	v0, sp, PT_R4
	b	la_syscall_exit
SYM_FUNC_END(handle_sys)
