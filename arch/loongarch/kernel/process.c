// SPDX-License-Identifier: GPL-2.0
/*
 * Author: Huacai Chen <chenhuacai@loongson.cn>
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/sched/debug.h>
#include <linux/sched/task.h>
#include <linux/sched/task_stack.h>
#include <linux/tick.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/stddef.h>
#include <linux/unistd.h>
#include <linux/export.h>
#include <linux/ptrace.h>
#include <linux/mman.h>
#include <linux/personality.h>
#include <linux/sys.h>
#include <linux/init.h>
#include <linux/completion.h>
#include <linux/kallsyms.h>
#include <linux/random.h>
#include <linux/prctl.h>
#include <linux/nmi.h>
#include <linux/cpu.h>

#include <asm/abi.h>
#include <asm/asm.h>
#include <asm/bootinfo.h>
#include <asm/cpu.h>
#include <asm/fpu.h>
#include <asm/irq.h>
#include <asm/pgtable.h>
#include <asm/loongarchregs.h>
#include <asm/processor.h>
#include <asm/reg.h>
#include <asm/io.h>
#include <asm/elf.h>
#include <asm/inst.h>
#include <asm/irq_regs.h>

/*
 * Idle related variables and functions
 */

unsigned long boot_option_idle_override = IDLE_NO_OVERRIDE;
EXPORT_SYMBOL(boot_option_idle_override);

#ifdef CONFIG_HOTPLUG_CPU
void arch_cpu_idle_dead(void)
{
	play_dead();
}
#endif

asmlinkage void ret_from_fork(void);
asmlinkage void ret_from_kernel_thread(void);

void start_thread(struct pt_regs *regs, unsigned long pc, unsigned long sp)
{
	unsigned long crmd;
	unsigned long prmd;
	unsigned long euen;

	/* New thread loses kernel privileges. */
	crmd = regs->csr_crmd & ~(PLV_MASK);
	crmd |= PLV_USER;
	regs->csr_crmd = crmd;

	prmd = regs->csr_prmd & ~(PLV_MASK);
	prmd |= PLV_USER;
	regs->csr_prmd = prmd;

	euen = regs->csr_euen & ~(CSR_EUEN_FPEN);
	regs->csr_euen = euen;
	lose_fpu(0);

	clear_thread_flag(TIF_LSX_CTX_LIVE);
	clear_thread_flag(TIF_LASX_CTX_LIVE);
	clear_used_math();
	regs->csr_epc = pc;
	regs->regs[3] = sp;

	// uty: test
	printk("start_thread: pc = 0x%lx, sp = 0x%lx\n", pc, sp);

}

void exit_thread(struct task_struct *tsk)
{
}

int arch_dup_task_struct(struct task_struct *dst, struct task_struct *src)
{
	/*
	 * Save any process state which is live in hardware registers to the
	 * parent context prior to duplication. This prevents the new child
	 * state becoming stale if the parent is preempted before copy_thread()
	 * gets a chance to save the parent's live hardware registers to the
	 * child context.
	 */
	preempt_disable();

	if (is_fpu_owner())
		save_fp(current);

	preempt_enable();

	if (used_math())
		memcpy(dst, src, sizeof(struct task_struct));
	else
		memcpy(dst, src, offsetof(struct task_struct, thread.fpu.fpr));

	return 0;
}

/*
 * Copy architecture-specific thread state
 */
int copy_thread(unsigned long clone_flags, unsigned long usp,
	unsigned long kthread_arg, struct task_struct *p, unsigned long tls)
{
	unsigned long childksp;
	struct pt_regs *childregs, *regs = current_pt_regs();

	childksp = (unsigned long)task_stack_page(p) + THREAD_SIZE - 32;

	/* set up new TSS. */
	childregs = (struct pt_regs *) childksp - 1;
	/*  Put the stack after the struct pt_regs.  */
	childksp = (unsigned long) childregs;
	p->thread.csr_euen = 0;
	p->thread.csr_crmd = csr_readl(LOONGARCH_CSR_CRMD);
	p->thread.csr_prmd = csr_readl(LOONGARCH_CSR_PRMD);
	p->thread.csr_ecfg = csr_readl(LOONGARCH_CSR_ECFG);
	if (unlikely(p->flags & PF_KTHREAD)) {
		/* kernel thread */
		unsigned long csr_crmd = p->thread.csr_crmd;
		unsigned long csr_euen = p->thread.csr_euen;
		unsigned long csr_prmd = p->thread.csr_prmd;
		unsigned long csr_ecfg = p->thread.csr_ecfg;

		memset(childregs, 0, sizeof(struct pt_regs));
		p->thread.reg23 = usp; /* fn */
		p->thread.reg24 = kthread_arg;
		p->thread.reg03 = childksp;
		p->thread.reg01 = (unsigned long) ret_from_kernel_thread;
		childregs->csr_euen = csr_euen;
		childregs->csr_prmd = csr_prmd;
		childregs->csr_ecfg = csr_ecfg;
		childregs->csr_crmd = csr_crmd;
		return 0;
	}

	/* user thread */
	*childregs = *regs;
	childregs->regs[7] = 0; /* Clear error flag */
	childregs->regs[4] = 0; /* Child gets zero as return value */
	if (usp)
		childregs->regs[3] = usp;

	p->thread.reg03 = (unsigned long) childregs;
	p->thread.reg01 = (unsigned long) ret_from_fork;

	/*
	 * New tasks lose permission to use the fpu. This accelerates context
	 * switching for most programs since they don't use the fpu.
	 */
	childregs->csr_euen = 0;

	clear_tsk_thread_flag(p, TIF_USEDFPU);
	clear_tsk_thread_flag(p, TIF_USEDSIMD);
	clear_tsk_thread_flag(p, TIF_LSX_CTX_LIVE);
	clear_tsk_thread_flag(p, TIF_LASX_CTX_LIVE);

	if (clone_flags & CLONE_SETTLS)
		childregs->regs[2] = tls;

	return 0;
}

unsigned long get_wchan(struct task_struct *task)
{
	return 0;
}

unsigned long stack_top(void)
{
	unsigned long top = TASK_SIZE & PAGE_MASK;

	/* Space for the VDSO & data page */
	top -= PAGE_ALIGN(current->thread.abi->vdso->size);
	top -= PAGE_SIZE;

	/* Space to randomize the VDSO base */
	if (current->flags & PF_RANDOMIZE)
		top -= VDSO_RANDOMIZE_SIZE;

	return top;
}

/*
 * Don't forget that the stack pointer must be aligned on a 8 bytes
 * boundary for 32-bits ABI and 16 bytes for 64-bits ABI.
 */
unsigned long arch_align_stack(unsigned long sp)
{
	if (!(current->personality & ADDR_NO_RANDOMIZE) && randomize_va_space)
		sp -= get_random_int() & ~PAGE_MASK;

	return sp & ALMASK;
}

static DEFINE_PER_CPU(call_single_data_t, backtrace_csd);
static struct cpumask backtrace_csd_busy;

static void handle_backtrace(void *info)
{
	nmi_cpu_backtrace(get_irq_regs());
	cpumask_clear_cpu(smp_processor_id(), &backtrace_csd_busy);
}

static void raise_backtrace(cpumask_t *mask)
{
	call_single_data_t *csd;
	int cpu;

	for_each_cpu(cpu, mask) {
		/*
		 * If we previously sent an IPI to the target CPU & it hasn't
		 * cleared its bit in the busy cpumask then it didn't handle
		 * our previous IPI & it's not safe for us to reuse the
		 * call_single_data_t.
		 */
		if (cpumask_test_and_set_cpu(cpu, &backtrace_csd_busy)) {
			pr_warn("Unable to send backtrace IPI to CPU%u - perhaps it hung?\n",
				cpu);
			continue;
		}

		csd = &per_cpu(backtrace_csd, cpu);
		csd->func = handle_backtrace;
		smp_call_function_single_async(cpu, csd);
	}
}

void arch_trigger_cpumask_backtrace(const cpumask_t *mask, bool exclude_self)
{
	nmi_trigger_cpumask_backtrace(mask, exclude_self, raise_backtrace);
}

#ifdef CONFIG_64BIT
void loongarch_dump_regs64(u64 *uregs, const struct pt_regs *regs)
{
	unsigned int i;

	for (i = LOONGARCH64_EF_R1; i <= LOONGARCH64_EF_R31; i++) {
		uregs[i] = regs->regs[i - LOONGARCH64_EF_R0];
	}

	uregs[LOONGARCH64_EF_CSR_EPC] = regs->csr_epc;
	uregs[LOONGARCH64_EF_CSR_BADVADDR] = regs->csr_badvaddr;
	uregs[LOONGARCH64_EF_CSR_CRMD] = regs->csr_crmd;
	uregs[LOONGARCH64_EF_CSR_PRMD] = regs->csr_prmd;
	uregs[LOONGARCH64_EF_CSR_EUEN] = regs->csr_euen;
	uregs[LOONGARCH64_EF_CSR_ECFG] = regs->csr_ecfg;
	uregs[LOONGARCH64_EF_CSR_ESTAT] = regs->csr_estat;
}
#endif /* CONFIG_64BIT */

// uty: test
#include <linux/uaccess.h>

void dump_pt_regs_at_restore(struct pt_regs *regs)
{
    unsigned int argc_val = 0;
    unsigned long argv0 = 0, argv1 = 0;
    int err;

    pr_info("=== PT_REGS at restore_all ===\n");
    pr_info("csr_epc (user pc) = 0x%lx\n", regs->csr_epc);
    pr_info("regs[3] (user sp) = 0x%lx\n", regs->regs[3]);
    pr_info("regs[1]=0x%lx regs[2]=0x%lx regs[4]=0x%lx regs[5]=0x%lx regs[6]=0x%lx\n",
            regs->regs[1], regs->regs[2], regs->regs[4],
            regs->regs[5], regs->regs[6]);

    /* 安全地读取用户栈上的 argc / argv[0] / argv[1] */
    err = get_user(argc_val, (unsigned int __user *)regs->regs[3]);
    if (!err)
        pr_info("*(user sp)      = %u (argc)\n", argc_val);
    else
        pr_info("get_user argc failed: %d\n", err);

    err = get_user(argv0, (unsigned long __user *)(regs->regs[3] + 4));
    if (!err)
        pr_info("*(user sp + 4)  = 0x%lx (argv[0])\n", argv0);

    err = get_user(argv1, (unsigned long __user *)(regs->regs[3] + 8));
    if (!err)
        pr_info("*(user sp + 8)  = 0x%lx (argv[1])\n", argv1);
}

void dump_tlb_pf_caller(struct pt_regs *regs)
{
    unsigned long estat, ecode, esubcode;
    unsigned long ks2;

    /* 读 CSR_ESTAT 的 Ecode/ESubCode */
    asm volatile("csrrd %0, 0x5" : "=r"(estat));
    ecode    = (estat >> 16) & 0x3f;
    esubcode = (estat >> 22) & 0x1ff;

    /* 读 EXCEPTION_KS2（handle_tlb_load 把原始 ra 存在这里） */
    asm volatile("csrrd %0, 0x7" : "=r"(ks2));

    pr_info("tlb_do_page_fault: ra=0x%lx epc=0x%lx badv=0x%lx "
            "ecode=0x%lx esubcode=0x%lx ks2=0x%lx\n",
            regs->regs[1], regs->csr_epc, regs->csr_badvaddr,
            ecode, esubcode, ks2);
}
