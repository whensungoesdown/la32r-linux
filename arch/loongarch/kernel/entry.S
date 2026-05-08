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
//SYM_FUNC_START(handle_general_exception)
//	/* Save all registers and build pt_regs structure */
//	SAVE_ALL
//
//	/* Read ESTAT register */
//	csrrd	t0, LOONGARCH_CSR_ESTAT
//
//	/* Extract ECODE (bits 16-21) */
//	srli.w	t1, t0, 16		/* t1 = (ESTAT >> 16) & 0x3F */
//	andi	t1, t1, 0x3f
//
//	/* Check if it's an external interrupt (ECODE == 0) */
//	bnez	t1, 1f			/* ECODE != 0 -> exception, not interrupt */
//
//	/* ----------------- Interrupt handling ----------------- */
//	/* Call common interrupt dispatcher, argument: pt_regs pointer (sp) */
//	move	a0, sp
//	la.abs	t0, plat_irq_dispatch
//	jirl	ra, t0, 0
//
//	/* Return from interrupt */
//	b	2f
//
//1:
//	/* ----------------- Exception handling ----------------- */
//	/* Ensure ECODE index is within valid range (0~63) */
//	slli.d	t2, t1, 2		/* t2 = ECODE * 4 */
//	la.abs	t3, excp_handlers
//	add.d	t3, t3, t2
//	LONG_L	t0, t3, 0		/* t0 = handler function address */
//
//	/* Call C handler, argument: pt_regs *regs = sp */
//	move	a0, sp
//	jirl	ra, t0, 0
//
//2:
//	/* Return from exception / interrupt, restore context */
//	//la.abs	t0, ret_from_exception
//	//jirl	zero, t0, 0
//	RESTORE_ALL
//	ertn
//SYM_FUNC_END(handle_general_exception)

//SYM_FUNC_START(handle_general_exception)
//     addi.w     $r3,$r3,-80   #(0xfb0)
//     st.w       $r1,$r3,76    #(0x4c)
//     st.w       $r22,$r3,72   #(0x48)
//     addi.w     $r22,$r3,80   #(0x50)
//
//     st.w       $r4,$r22,-12
//     st.w       $r5,$r22,-16
//     st.w       $r6,$r22,-20
//     st.w       $r7,$r22,-24
//     st.w       $r8,$r22,-28
//     st.w       $r9,$r22,-32
//     st.w       $r10,$r22,-36
//     st.w       $r11,$r22,-40
//     st.w       $r12,$r22,-44
//     st.w       $r13,$r22,-48
//     st.w       $r14,$r22,-52
//     st.w       $r15,$r22,-56
//     st.w       $r16,$r22,-60
//     st.w       $r17,$r22,-64
//     st.w       $r18,$r22,-68
//     st.w       $r19,$r22,-72
//     st.w       $r20,$r22,-76
//
//
//     bl plat_irq_dispatch
//
//
//     ld.w       $r4,$r22,-12
//     ld.w       $r5,$r22,-16
//     ld.w       $r6,$r22,-20
//     ld.w       $r7,$r22,-24
//     ld.w       $r8,$r22,-28
//     ld.w       $r9,$r22,-32
//     ld.w       $r10,$r22,-36
//     ld.w       $r11,$r22,-40
//     ld.w       $r12,$r22,-44
//     ld.w       $r13,$r22,-48
//     ld.w       $r14,$r22,-52
//     ld.w       $r15,$r22,-56
//     ld.w       $r16,$r22,-60
//     ld.w       $r17,$r22,-64
//     ld.w       $r18,$r22,-68
//     ld.w       $r19,$r22,-72
//     ld.w       $r20,$r22,-76
//
//     andi       $r0,$r0,0x0
//     ld.w       $r1,$r3,76    #(0x4c)
//     ld.w       $r22,$r3,72   #(0x48)
//     addi.w     $r3,$r3,80    #(0x50)
//     ertn
//
//SYM_FUNC_END(handle_general_exception)


SYM_FUNC_START(handle_general_exception)

	BACKUP_T0T1

	csrrd	t0, LOONGARCH_CSR_ESTAT
	srli.w	t1, t0, 0x10   /* get Ecode */
	andi	t1, t1, 0x3f
	beq	t1, zero, 1f	/* if irq */

        csrrd	t0, LOONGARCH_CSR_EENTRY
        slli.w	t1, t1, 0x9  /* get ex entry shift = Ecode * vec_size  */
        add.w	t0, t0, t1
        lu12i.w	t1, 0x4
        sub.w	t0, t0, t1
        jirl	zero,t0 , 0  /* go to exception_handler */

1:
	SAVE_SOME
	la.abs	t1, __arch_cpu_idle
	LONG_L	t0, sp, PT_EPC

	/* 32 byte rollback region */
	ori	t0, t0, 0x1f
	xori	t0, t0, 0x1f
	bne	t0, t1, 2f
	LONG_S	t0, sp, PT_EPC
2:
	SAVE_TEMP
	SAVE_STATIC

	CLI
	TRACE_IRQS_OFF

	ld.w	s0, tp, TI_REGS
	st.w	sp, tp, TI_REGS
	move	s1, sp

	# uty: test
	#csrrd	t0, LOONGARCH_CSR_TMID
	move    t0, zero
	la.abs	t1, irq_stack
	slli.w	t0, t0, LONGLOG
	ld.w	t0, t1, 0

	li.w	t1, ~(_THREAD_SIZE-1)
	and	t1, t1, sp
	beq	t0, t1, 2f

	li.w	t1, _IRQ_STACK_START
	add.w	sp, t0, t1
	st.w	s1,sp, 0

2:
	la.abs	t0, plat_irq_dispatch
	jirl	ra, t0, 0

	move	sp, s1

	la.abs	t0, ret_from_irq
	jirl	zero, t0, 0
SYM_FUNC_END(handle_general_exception)

//SYM_FUNC_START(handle_general_exception)
//	BACKUP_T0T1
//	SAVE_SOME
//	addi.d	v0, zero, 7
//	la.abs	v1, uty_except_vec_vi_handler
//	jirl	zero, v1, 0
//SYM_FUNC_END(handle_general_exception)

//SYM_FUNC_START(handle_general_exception)
////	BACKUP_T0T1
//	csrwr   $r12,0x30
//	csrwr   $r13,0x31
//
////	SAVE_SOME
////	csrrd   $r13,0x1
////	andi    $r13,$r13,0x3
////	slli.w  $r12,$r3,0x0
////	beq     $r13,$r0,18f
////	lu12i.w $r13,0x2573
////	ori     $r13,$r13,0xcd4
////	slli.w  $r12,$r3,0x0
////	ld.w    $r3,$r13,0
////18:
//	addi.w  $r3,$r3,-160
//	st.w    $r12,$r3,12
//	st.w    $r0,$r3,0
//	csrrd   $r12,0x1
//	st.w    $r12,$r3,132
//	csrrd   $r12,0x0
//	st.w    $r12,$r3,128
//	csrrd   $r12,0x4
//	st.w    $r12,$r3,140
//	csrrd   $r12,0x2
//	st.w    $r12,$r3,136
//	st.w    $r1,$r3,4
//	st.w    $r4,$r3,16
//	st.w    $r5,$r3,20
//	st.w    $r6,$r3,24
//	st.w    $r7,$r3,28
//	st.w    $r8,$r3,32
//	st.w    $r9,$r3,36
//	st.w    $r10,$r3,40
//	st.w    $r11,$r3,44
////	csrrd   $r1,0x6
////	st.w    $r1,$r3,148
////	st.w    $r2,$r3,8
////	st.w    $r22,$r3,88
////	csrrd   $r12,0x1
////	andi    $r12,$r12,0x3
////	beq     $r12,$r0,19f
////	lu12i.w $r2,-2        // 0xffffe
////	and     $r2,$r2,$r3
////	st.w    $r21,$r3,84
////19:
//	addi.d	v0, zero, 7
//	la.abs	v1, uty_except_vec_vi_handler
//	jirl	zero, v1, 0
//SYM_FUNC_END(handle_general_exception)
