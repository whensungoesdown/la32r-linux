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

excp_handlers:
        PTR     handle_reserved         /* 0: External interrupt, handled separately */
        PTR     handle_reserved         /* 1: Reserved */
        PTR     handle_reserved         /* 2: Reserved */
        PTR     handle_reserved         /* 3: Reserved */
        PTR     handle_reserved         /* 4: Reserved */
        PTR     handle_reserved         /* 5: Reserved */
        PTR     handle_reserved         /* 6: Reserved */
        PTR     handle_reserved         /* 7: Reserved */
        PTR     handle_ade              /* 8: Address error exception */
        PTR     handle_ale              /* 9: Unaligned access exception */
        PTR     handle_reserved         /* a: Reserved */
        PTR     handle_sys              /* b: Syscall */
        PTR     handle_bp               /* c: Breakpoint exception (break) */
        PTR     handle_ri               /* d: Illegal instruction exception */
        /* Fill remaining 14~63 with do_reserved */
        .rept   50
        PTR     handle_reserved
        .endr

SYM_FUNC_START(handle_general_exception)

        BACKUP_T0T1

        csrrd   t0, LOONGARCH_CSR_ESTAT
        srli.w  t1, t0, 0x10   /* get Ecode */
        andi    t1, t1, 0x3f
        beq     t1, zero, 1f    /* if irq */

        /* ----------------- Exception handling ----------------- */
        /* Ensure ECODE index is within valid range (0~63) */
        slli.w  t0, t1, 2               /* t0 = ECODE * 4 */
        la.abs  t1, excp_handlers
        add.w   t1, t1, t0
        LONG_L  t0, t1, 0               /* t0 = handler function address */


        /* Call C handler*/
        // code wont return here, do not use ra before SAVE_SOME
        //jirl  ra, t0, 0     
        jirl    $r0, t0, 0

1:
        SAVE_SOME
        la.abs  t1, __arch_cpu_idle
        LONG_L  t0, sp, PT_EPC

        /* 32 byte rollback region */
        ori     t0, t0, 0x1f
        xori    t0, t0, 0x1f
        bne     t0, t1, 2f
        LONG_S  t0, sp, PT_EPC
2:
        SAVE_TEMP
        SAVE_STATIC

        CLI
        TRACE_IRQS_OFF

        ld.w    s0, tp, TI_REGS
        st.w    sp, tp, TI_REGS
        move    s1, sp

        # uty: test
        #csrrd  t0, LOONGARCH_CSR_TMID
        move    t0, zero
        la.abs  t1, irq_stack
        slli.w  t0, t0, LONGLOG
        ld.w    t0, t1, 0

        li.w    t1, ~(_THREAD_SIZE-1)
        and     t1, t1, sp
        beq     t0, t1, 2f

        li.w    t1, _IRQ_STACK_START
        add.w   sp, t0, t1
        st.w    s1,sp, 0

2:
        la.abs  t0, plat_irq_dispatch
        jirl    ra, t0, 0

        move    sp, s1

        la.abs  t0, ret_from_irq
        jirl    zero, t0, 0
SYM_FUNC_END(handle_general_exception)
