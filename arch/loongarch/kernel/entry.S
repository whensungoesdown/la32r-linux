/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */

#include <asm/asm.h>
#include <asm/asmmacro.h>
#include <asm/compiler.h>
#include <asm/irqflags.h>
#include <asm/regdef.h>
#include <asm/loongarchregs.h>
#include <asm/stackframe.h>
#include <asm/thread_info.h>

#ifndef CONFIG_PREEMPTION
#define resume_kernel	restore_all
#else
#define __ret_from_irq	ret_from_exception
#endif

	.text
	.align	5
#ifndef CONFIG_PREEMPTION
SYM_CODE_START(ret_from_exception)
	local_irq_disable			# preempt stop
	b	__ret_from_irq
SYM_CODE_END(ret_from_exception)
#endif
SYM_CODE_START(ret_from_irq)
	LONG_S	s0, tp, TI_REGS
	b	__ret_from_irq
SYM_CODE_END(ret_from_irq)

SYM_CODE_START(__ret_from_irq)
/*
 * We can be coming here from a syscall done in the kernel space,
 * e.g. a failed kernel_execve().
 */
resume_userspace_check:
	LONG_L  t0, sp, PT_PRMD # returning to kernel mode?
	andi    t0, t0, PLV_MASK
	beqz	t0, resume_kernel

resume_userspace:
	local_irq_disable		# make sure we dont miss an
					# interrupt setting need_resched
					# between sampling and return
	LONG_L	a2, tp, TI_FLAGS	# current->work
	andi	t0, a2, _TIF_WORK_MASK	# (ignoring syscall_trace)
	bnez	t0, work_pending
	b	restore_all
SYM_CODE_END(__ret_from_irq)

#ifdef CONFIG_PREEMPTION
resume_kernel:
	local_irq_disable
	ld.w	t0, tp, TI_PRE_COUNT
	bnez	t0, restore_all
need_resched:
	LONG_L	t0, tp, TI_FLAGS
	andi	t1, t0, _TIF_NEED_RESCHED
	beqz	t1, restore_all

	LONG_L  t0, sp, PT_PRMD		# Interrupts off?
	andi	t0, t0, CSR_PRMD_PIE
	beqz	t0, restore_all
	bl	preempt_schedule_irq
	b	need_resched
#endif

SYM_CODE_START(ret_from_kernel_thread)
	bl	schedule_tail		# a0 = struct task_struct *prev
	move	a0, s1
	jirl	ra, s0, 0
	b	syscall_exit
SYM_CODE_END(ret_from_kernel_thread)

SYM_CODE_START(ret_from_fork)
	bl	schedule_tail		# a0 = struct task_struct *prev
	b	syscall_exit
SYM_CODE_END(ret_from_fork)

SYM_CODE_START(syscall_exit)
#ifdef CONFIG_DEBUG_RSEQ
	move	a0, sp
	bl	rseq_syscall
#endif
	local_irq_disable		# make sure need_resched and
					# signals dont change between
					# sampling and return
	LONG_L	a2, tp, TI_FLAGS	# current->work
	li.w	t0, _TIF_ALLWORK_MASK
	and	t0, a2, t0
	bnez	t0, syscall_exit_work

restore_all:				# restore full frame
	RESTORE_TEMP
	RESTORE_STATIC
restore_partial:		# restore partial frame
	RESTORE_SOME
	RESTORE_SP_AND_RET

work_pending:
	andi	t0, a2, _TIF_NEED_RESCHED # a2 is preloaded with TI_FLAGS
	beqz	t0, work_notifysig
work_resched:
	bl	schedule

	local_irq_disable		# make sure need_resched and
					# signals dont change between
					# sampling and return
	LONG_L	a2, tp, TI_FLAGS
	andi	t0, a2, _TIF_WORK_MASK	# is there any work to be done
					# other than syscall tracing?
	beqz	t0, restore_all
	andi	t0, a2, _TIF_NEED_RESCHED
	bnez	t0, work_resched

work_notifysig:				# deal with pending signals and
					# notify-resume requests
	move	a0, sp
	li.w	a1, 0
	bl	do_notify_resume	# a2 already loaded
	b	resume_userspace_check
SYM_CODE_END(syscall_exit)

SYM_CODE_START(syscall_exit_partial)
#ifdef CONFIG_DEBUG_RSEQ
	move	a0, sp
	bl	rseq_syscall
#endif
	local_irq_disable		# make sure need_resched doesn't
					# change between and return
	LONG_L	a2, tp, TI_FLAGS	# current->work
	li.w	t0, _TIF_ALLWORK_MASK
	and	t0, t0, a2
	beqz	t0, restore_partial
	SAVE_STATIC
syscall_exit_work:
	LONG_L	t0, sp, PT_PRMD			# returning to kernel mode?
	andi	t0, t0, PLV_MASK
	beqz	t0, resume_kernel
	li.w	t0, _TIF_WORK_SYSCALL_EXIT
	and	t0, t0, a2			# a2 is preloaded with TI_FLAGS
	beqz	t0, work_pending	# trace bit set?
	local_irq_enable		# could let syscall_trace_leave()
					# call schedule() instead
	move	a0, sp
	bl	syscall_trace_leave
	b	resume_userspace
SYM_CODE_END(syscall_exit_partial)


// uty: test
/* Exception handler table, indexed by ECODE (0~63) */
	.section .rodata
	.align 3
excp_handlers:
	PTR	do_reserved		/* 0: External interrupt, handled separately */
	PTR	do_reserved		/* 1: Reserved */
	PTR	do_ade			/* 2: Address error exception */
	PTR	do_ale			/* 3: Unaligned access exception */
	PTR	do_bp			/* 4: Breakpoint exception (break) */
	PTR	do_ri			/* 5: Illegal instruction exception */
	PTR	do_reserved		/* 6: Reserved */
	PTR	do_reserved		/* 7: Reserved */
	PTR	do_fpu			/* 8: FPU disabled exception */
	PTR	do_fpe			/* 9: FPU exception (fpe) */
	PTR	do_lsx			/* 10: LSX extension disabled */
	PTR	do_lasx			/* 11: LASX extension disabled */
	PTR	do_lbt			/* 12: LBT extension disabled */
	PTR	do_watch		/* 13: Hardware watchpoint exception */
	/* Fill remaining 14~63 with do_reserved */
	.rept	50
	PTR	do_reserved
	.endr

/* General exception entry point (VS == 0) */
SYM_FUNC_START(handle_general_exception)
	/* Save all registers and build pt_regs structure */
	SAVE_ALL

	/* Read ESTAT register */
	csrrd	t0, LOONGARCH_CSR_ESTAT

	/* Extract ECODE (bits 16-21) */
	srli.w	t1, t0, 16		/* t1 = (ESTAT >> 16) & 0x3F */
	andi	t1, t1, 0x3f

	/* Check if it's an external interrupt (ECODE == 0) */
	bnez	t1, 1f			/* ECODE != 0 -> exception, not interrupt */

	/* ----------------- Interrupt handling ----------------- */
	/* Call common interrupt dispatcher, argument: pt_regs pointer (sp) */
	move	a0, sp
	la.abs	t0, plat_irq_dispatch
	jirl	ra, t0, 0

	/* Return from interrupt */
	b	2f

1:
	/* ----------------- Exception handling ----------------- */
	/* Ensure ECODE index is within valid range (0~63) */
	slli.d	t2, t1, 2		/* t2 = ECODE * 4 */
	la.abs	t3, excp_handlers
	add.d	t3, t3, t2
	LONG_L	t0, t3, 0		/* t0 = handler function address */

	/* Call C handler, argument: pt_regs *regs = sp */
	move	a0, sp
	jirl	ra, t0, 0

2:
	/* Return from exception / interrupt, restore context */
	la.abs	t0, ret_from_exception
	jirl	zero, t0, 0
SYM_FUNC_END(handle_general_exception)
