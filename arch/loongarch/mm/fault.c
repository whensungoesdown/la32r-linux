// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#include <linux/context_tracking.h>
#include <linux/signal.h>
#include <linux/sched.h>
#include <linux/interrupt.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/ptrace.h>
#include <linux/ratelimit.h>
#include <linux/mman.h>
#include <linux/mm.h>
#include <linux/smp.h>
#include <linux/kdebug.h>
#include <linux/kprobes.h>
#include <linux/perf_event.h>
#include <linux/uaccess.h>

#include <asm/branch.h>
#include <asm/mmu_context.h>
#include <asm/ptrace.h>

int show_unhandled_signals = 1;

/*
 * This routine handles page faults.  It determines the address,
 * and the problem, and then passes it off to one of the appropriate
 * routines.
 */
static void __kprobes __do_page_fault(struct pt_regs *regs, unsigned long write,
	unsigned long address)
{
	int si_code;
	const int field = sizeof(unsigned long) * 2;
	unsigned int flags = FAULT_FLAG_ALLOW_RETRY | FAULT_FLAG_KILLABLE;
	struct task_struct *tsk = current;
	struct mm_struct *mm = tsk->mm;
	struct vm_area_struct *vma = NULL;
	vm_fault_t fault;

	static DEFINE_RATELIMIT_STATE(ratelimit_state, 5 * HZ, 10);

	// uty: test
	printk("__do_page_fault: address=0x%x, write=0x%x, regs->csr_epc=0x%x, regs->csr_badvaddr=0x%x, r4=0x%x, r12=0x%x\n", (int)address, (int)write, (int)(regs->csr_epc), (int)(regs->csr_badvaddr), (int)(regs->regs[4]), (int)(regs->regs[12]));

	si_code = SEGV_MAPERR;

	if (user_mode(regs) && (address & __UA_LIMIT))
		goto bad_area_nosemaphore;

	/*
	 * We fault-in kernel-space virtual memory on-demand. The
	 * 'reference' page table is init_mm.pgd.
	 *
	 * NOTE! We MUST NOT take any locks for this case. We may
	 * be in an interrupt or a critical region, and should
	 * only copy the information from the master page table,
	 * nothing more.
	 */
#ifdef CONFIG_32BIT
#define VMALLOC_FAULT_TARGET vmalloc_fault
#endif

#ifdef CONFIG_64BIT
#define VMALLOC_FAULT_TARGET no_context
#endif

	if (unlikely(address >= VMALLOC_START && address <= VMALLOC_END))
		goto VMALLOC_FAULT_TARGET;

	/* Enable interrupts if they were enabled in the parent context. */
	if (likely(regs->csr_prmd & CSR_PRMD_PIE))
		//local_irq_enable();
	{
		//uty: test
		printk("do not local_irq_enable() here\n");
	}

	/*
	 * If we're in an interrupt or have no user
	 * context, we must not take the fault..
	 */
	if (faulthandler_disabled() || !mm)
		goto bad_area_nosemaphore;

	if (user_mode(regs))
		flags |= FAULT_FLAG_USER;
retry:
	mmap_read_lock(mm);
	vma = find_vma(mm, address);
	if (!vma)
		goto bad_area;
	if (vma->vm_start <= address)
		goto good_area;
	if (!(vma->vm_flags & VM_GROWSDOWN))
		goto bad_area;
	if (expand_stack(vma, address))
		goto bad_area;
/*
 * Ok, we have a good vm_area for this memory access, so
 * we can handle it..
 */
good_area:
	si_code = SEGV_ACCERR;

	if (write) {
		if (!(vma->vm_flags & VM_WRITE))
			goto bad_area;
		flags |= FAULT_FLAG_WRITE;
	} else {
		if (address == regs->csr_epc && !(vma->vm_flags & VM_EXEC))
			goto bad_area;
		if (!(vma->vm_flags & VM_READ) &&
		    exception_epc(regs) != address)
			goto bad_area;
	}

	/*
	 * If for any reason at all we couldn't handle the fault,
	 * make sure we exit gracefully rather than endlessly redo
	 * the fault.
	 */
	fault = handle_mm_fault(vma, address, flags, regs);

	// uty: test
	printk("handle_mm_fault returns 0x%x\n", (int)fault);

	if ((fault & VM_FAULT_RETRY) && fatal_signal_pending(current))
		return;

	perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS, 1, regs, address);
	if (unlikely(fault & VM_FAULT_ERROR)) {
		if (fault & VM_FAULT_OOM)
			goto out_of_memory;
		else if (fault & VM_FAULT_SIGSEGV)
			goto bad_area;
		else if (fault & VM_FAULT_SIGBUS)
			goto do_sigbus;
		BUG();
	}
	if (flags & FAULT_FLAG_ALLOW_RETRY) {
		if (fault & VM_FAULT_MAJOR) {
			perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS_MAJ, 1,
						  regs, address);
			tsk->maj_flt++;
		} else {
			perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS_MIN, 1,
						  regs, address);
			tsk->min_flt++;
		}
		if (fault & VM_FAULT_RETRY) {
			flags &= ~FAULT_FLAG_ALLOW_RETRY;
			flags |= FAULT_FLAG_TRIED;

			/*
			 * No need to mmap_read_unlock(mm) as we would
			 * have already released it in __lock_page_or_retry
			 * in mm/filemap.c.
			 */

			goto retry;
		}
	}

	mmap_read_unlock(mm);
	return;

/*
 * Something tried to access memory that isn't in our memory map..
 * Fix it, but check if it's kernel or user first..
 */
bad_area:
	mmap_read_unlock(mm);

bad_area_nosemaphore:
	/* User mode accesses just cause a SIGSEGV */
	if (user_mode(regs)) {
		tsk->thread.csr_badvaddr = address;
		tsk->thread.error_code = write;
		if (show_unhandled_signals &&
		    unhandled_signal(tsk, SIGSEGV) &&
		    __ratelimit(&ratelimit_state)) {
			pr_info("do_page_fault(): sending SIGSEGV to %s for invalid %s %0*lx\n",
				tsk->comm,
				write ? "write access to" : "read access from",
				field, address);
			pr_info("epc = %0*lx in", field,
				(unsigned long) regs->csr_epc);
			print_vma_addr(KERN_CONT " ", regs->csr_epc);
			pr_cont("\n");
			pr_info("ra  = %0*lx in", field,
				(unsigned long) regs->regs[1]);
			print_vma_addr(KERN_CONT " ", regs->regs[1]);
			pr_cont("\n");
		}
		current->thread.trap_nr = read_csr_excode();
		force_sig_fault(SIGSEGV, si_code, (void __user *)address);
		return;
	}

no_context:
	/* Are we prepared to handle this kernel fault?	 */
	if (fixup_exception(regs)) {
		current->thread.csr_baduaddr = address;
		return;
	}

	/*
	 * Oops. The kernel tried to access some bad page. We'll have to
	 * terminate things with extreme prejudice.
	 */
	bust_spinlocks(1);

	pr_alert("CPU %d Unable to handle kernel paging request at "
	       "virtual address %0*lx, epc == %0*lx, ra == %0*lx\n",
	       raw_smp_processor_id(), field, address, field, regs->csr_epc,
	       field,  regs->regs[1]);
	die("Oops", regs);

out_of_memory:
	/*
	 * We ran out of memory, call the OOM killer, and return the userspace
	 * (which will retry the fault, or kill us if we got oom-killed).
	 */
	mmap_read_unlock(mm);
	if (!user_mode(regs))
		goto no_context;
	pagefault_out_of_memory();
	return;

do_sigbus:
	mmap_read_unlock(mm);

	/* Kernel mode? Handle exceptions or die */
	if (!user_mode(regs))
		goto no_context;

	/*
	 * Send a sigbus, regardless of whether we were in kernel
	 * or user mode.
	 */
	current->thread.trap_nr = read_csr_excode();
	tsk->thread.csr_badvaddr = address;
	force_sig_fault(SIGBUS, BUS_ADRERR, (void __user *)address);

	return;

#ifndef CONFIG_64BIT
vmalloc_fault:
	{
		/*
		 * Synchronize this task's top level page-table
		 * with the 'reference' page table.
		 *
		 * Do _not_ use "tsk" here. We might be inside
		 * an interrupt in the middle of a task switch..
		 */
		int offset = __pgd_offset(address);
		pgd_t *pgd, *pgd_k;
		pud_t *pud, *pud_k;
		pmd_t *pmd, *pmd_k;
		pte_t *pte_k;

		pgd = (pgd_t *) __csrrd_w(LOONGARCH_CSR_PGD) +offset ;
		pgd_k = init_mm.pgd + offset;

		if (!pgd_present(*pgd_k))
			goto no_context;
		set_pgd(pgd, *pgd_k);

		pud = pud_offset((p4d_t *)pgd, address);
		pud_k = pud_offset((p4d_t *)pgd_k, address);
		if (!pud_present(*pud_k))
			goto no_context;

		pmd = pmd_offset(pud, address);
		pmd_k = pmd_offset(pud_k, address);
		if (!pmd_present(*pmd_k))
			goto no_context;
		set_pmd(pmd, *pmd_k);

		pte_k = pte_offset_kernel(pmd_k, address);
		if (!pte_present(*pte_k))
			goto no_context;
		return;
	}
#endif
}

void print_csr_ks(void)
{
    unsigned long ks0, ks1;

    /* 读取CSR_KS0 (0x30) */
    __asm__ volatile (
        "csrrd %0, 0x30"
        : "=r" (ks0)
        :
        : "memory"
    );

    /* 读取CSR_KS1 (0x31) */
    __asm__ volatile (
        "csrrd %0, 0x31"
        : "=r" (ks1)
        :
        : "memory"
    );

    printk("KS0 = 0x%lx, KS1 = 0x%lx\n", ks0, ks1);
}

void print_csr_epc(void)
{
    unsigned long epc;

    /*
     * 读取EPC寄存器（CSR 0x0e）
     * 使用内嵌汇编: csrrd rd, csr_num
     */
    __asm__ volatile (
        "csrrd %0, 0x06"
        : "=r" (epc)
        :
        : "memory"
    );

    printk("EPC = 0x%lx\n", epc);
}

void dump_user_16d40_4dwords(void);

static void dump_pt_regs(const char *tag, struct pt_regs *regs)
{
    unsigned long sp = regs->regs[3];
    unsigned int argc = 0;
    int err;

    err = get_user(argc, (unsigned int __user *)sp);

    pr_info("[%s] epc=0x%lx badv=0x%lx r3=0x%lx r4=0x%lx "
            "r12=0x%lx r5=0x%lx r6=0x%lx argc_err=%d argc=%u\n",
            tag,
            regs->csr_epc,
            regs->csr_badvaddr,
            regs->regs[3],
            regs->regs[4],
            regs->regs[12],
            regs->regs[5],
            regs->regs[6],
            err,
            argc);

    if (regs->csr_epc == 0x16d40)
    {
            dump_user_16d40_4dwords();
    }
}

void dump_csr_regs(void)
{
    unsigned long badv, tlbidx, tlbehi, tlbelo0, tlbelo1, pgd;

    asm volatile("csrrd %0, 0x7"  : "=r"(badv));     /* CSR_BADV    */
    asm volatile("csrrd %0, 0x10" : "=r"(tlbidx));   /* CSR_TLBIDX  */
    asm volatile("csrrd %0, 0x11" : "=r"(tlbehi));   /* CSR_TLBEHI  */
    asm volatile("csrrd %0, 0x12" : "=r"(tlbelo0));  /* CSR_TLBELO0 */
    asm volatile("csrrd %0, 0x13" : "=r"(tlbelo1));  /* CSR_TLBELO1 */
    asm volatile("csrrd %0, 0x1b" : "=r"(pgd));      /* CSR_PGD     */

    pr_info("[CSR] BADV=0x%08lx TLBIDX=0x%08lx TLBEHI=0x%08lx "
            "TLBELO0=0x%08lx TLBELO1=0x%08lx PGD=0x%08lx\n",
            badv, tlbidx, tlbehi, tlbelo0, tlbelo1, pgd);
}

#include <asm/io.h>          /* phys_to_virt */
#include <asm/pgtable.h>

//void dump_pte_pair(void)
//{
//    unsigned long pgd_phys, badv;
//    unsigned long pgd_idx, pmd_idx;
//    unsigned int  pmd_phys, pte_phys;
//    unsigned int *pgd, *pmd;
//    unsigned int  pte0, pte1;
//
//    /* 读取 CSR */
//    asm volatile("csrrd %0, 0x1b" : "=r"(pgd_phys));   /* CSR_PGD  */
//    asm volatile("csrrd %0, 0x7"  : "=r"(badv));       /* CSR_BADV */
//
//    /* ---- 仿照汇编：PGD 索引 ---- */
//    pgd_idx = (badv >> 0x16) & 0x3ff;   /* BADV >> 22，10 位 */
//    //pgd = (unsigned int *)phys_to_virt(pgd_phys);
//    pgd = pgd_phys; // PGD=0xa303e000
//    printk("pgd va= 0x%x\n", (int)pgd);
//
//    pmd_phys = pgd[pgd_idx];            /* PGD[pgd_idx] = PMD 物理基址 */
//
//    pr_info("[PTE] BADV=0x%08lx PGD=0x%08lx pgd_idx=%lu pmd_phys=0x%08x\n",
//            badv, pgd_phys, pgd_idx, pmd_phys);
//
//    if (!pmd_phys) {
//        pr_info("[PTE] PMD is NULL, no PTE to read\n");
//        return;
//    }
//
//    /* ---- 仿照汇编：PMD 索引 ---- */
//    pmd_idx  = (badv >> 0xc) & 0x3ff;   /* BADV >> 12，10 位 */
//    //pmd      = (unsigned int *)phys_to_virt(pmd_phys);
//    pmd      = pmd_phys;
//    pte_phys = pmd_phys + pmd_idx * 4;  /* PTE 物理地址 */
//
//    pte0 = pmd[pmd_idx];                /* PTE0 */
//    pte1 = pmd[pmd_idx + 1];            /* PTE1（相邻下一项） */
//
//    pr_info("[PTE] pmd_idx=%lu pte_phys=0x%08x PTE0=0x%08x PTE1=0x%08x\n",
//            pmd_idx, pte_phys, pte0, pte1);
//
//    /* 简单解读 V 位和 PRESENT 位 */
//    pr_info("[PTE] PTE0: V=%u PRESENT=%u  PTE1: V=%u PRESENT=%u\n",
//            pte0 & 1, (pte0 >> _PAGE_PRESENT_SHIFT) & 1,
//            pte1 & 1, (pte1 >> _PAGE_PRESENT_SHIFT) & 1);
//}

//void dump_pte_pair(void)
//{
//    unsigned long pgd_phys, badv;
//    unsigned long pgd_idx, pmd_idx, vpn, vppn, pte_pair_idx;
//    unsigned int  pmd_phys, pte_phys;
//    unsigned int *pgd, *pmd;
//    unsigned int  pte0, pte1;
//
//    asm volatile("csrrd %0, 0x1b" : "=r"(pgd_phys));
//    asm volatile("csrrd %0, 0x7"  : "=r"(badv));
//
//    /* PGD 索引 */
//    pgd_idx = (badv >> 0x16) & 0x3ff;
//    //pgd = (unsigned int *)phys_to_virt(pgd_phys);
//    pgd = (unsigned int*)pgd_phys;
//    pmd_phys = pgd[pgd_idx];
//
//    if (!pmd_phys) {
//        pr_info("[PTE] BADV=0x%08lx PGD=0x%08lx pgd_idx=%lu pmd_phys=0 (PMD not built)\n",
//                badv, pgd_phys, pgd_idx);
//        return;
//    }
//
//    /* PMD 索引 */
//    pmd_idx = (badv >> 0xc) & 0x3ff;
//
//    /* 计算 VPN / VPPN，找到页对起始 PTE */
//    vpn          = badv >> 12;
//    vppn         = vpn >> 1;
//    pte_pair_idx = vpn & ~1;      /* == pmd_idx & ~1 */
//
//    //pmd      = (unsigned int *)phys_to_virt(pmd_phys);
//    pmd      = (unsigned int*)pmd_phys;
//    pte_phys = pmd_phys + pte_pair_idx * 4;
//    pte0     = pmd[pte_pair_idx];       /* 偶页 PTE */
//    pte1     = pmd[pte_pair_idx + 1];   /* 奇页 PTE */
//
//    pr_info("[PTE] BADV=0x%08lx VPN=0x%lx VPPN=0x%lx "
//            "pmd_idx=0x%lx pair_idx=0x%lx pte_phys=0x%08x\n",
//            badv, vpn, vppn, pmd_idx, pte_pair_idx, pte_phys);
//    pr_info("[PTE] PTE0=0x%08x PTE1=0x%08x  V0=%u V1=%u\n",
//            pte0, pte1, pte0 & 1, pte1 & 1);
//}


void dump_pte_pair(void)
{
    unsigned long pgd_phys, badv;
    unsigned long pgd_idx, pmd_idx, vpn, vppn, pair_idx;
    unsigned long pmd_phys, pte_phys;
    unsigned int *pgd, *pmd;
    unsigned int pte0, pte1;

    asm volatile("csrrd %0, 0x1b" : "=r"(pgd_phys));
    asm volatile("csrrd %0, 0x7"  : "=r"(badv));

    pgd_idx = (badv >> 0x16) & 0x3ff;
    //pgd     = (unsigned int *)phys_to_virt(pgd_phys);
    pgd     = (unsigned int *)pgd_phys;
    pmd_phys = pgd[pgd_idx] & PAGE_MASK;   /* 去掉低位标志位 */

    if (!pmd_phys) {
        pr_info("[PTE] BADV=0x%08lx PGD=0x%08lx pgd_idx=%lu pmd_phys=0\n",
                badv, pgd_phys, pgd_idx);
        return;
    }

    pmd_idx  = (badv >> 0xc) & 0x3ff;

    vpn      = badv >> 12;
    vppn     = vpn >> 1;
    pair_idx = pmd_idx & ~1UL;             /* 关键：用 pmd_idx，不用 vpn */

    //pmd      = (unsigned int *)phys_to_virt(pmd_phys);
    pmd      = (unsigned int *)pmd_phys;
    pte_phys = pmd_phys + pair_idx * 4;
    pte0     = pmd[pair_idx];
    pte1     = pmd[pair_idx + 1];

    pr_info("[PTE] BADV=0x%08lx VPN=0x%lx VPPN=0x%lx "
            "pmd_idx=0x%lx pair_idx=0x%lx pte_phys=0x%08lx\n",
            badv, vpn, vppn, pmd_idx, pair_idx, pte_phys);
    pr_info("[PTE] PTE0=0x%08x PTE1=0x%08x  V0=%u V1=%u\n",
            pte0, pte1, pte0 & 1, pte1 & 1);
}

void dump_user_16d40_4dwords(void)
{
    unsigned long base = 0x16d40;
    unsigned int  val[4];
    int i, err;

    if (!current->mm) {
        pr_info("[USER] no mm\n");
        return;
    }

    for (i = 0; i < 4; i++) {
        err = get_user(val[i], (unsigned int __user *)(base + i * 4));
        if (err) {
            pr_info("[USER] read dword %d at 0x%lx failed, err=%d\n",
                    i, base + i * 4, err);
            return;
        }
    }

    pr_info("[USER] 0x%lx: %08x %08x %08x %08x\n",
            base, val[0], val[1], val[2], val[3]);
}

asmlinkage void __kprobes do_page_fault(struct pt_regs *regs,
	unsigned long write, unsigned long address)
{
	enum ctx_state prev_state;

	// uty: test
        //unsigned long kernel_ra;

        //asm volatile("move %0, $r1" : "=r"(kernel_ra));

        //pr_info("\ndo_page_fault: kernel_ra=0x%lx, epc=0x%lx, badv=0x%lx\n", kernel_ra, regs->csr_epc, address);

        //printk("\n");
        //dump_stack();

	//print_csr_epc();


        printk("Before: ");
        dump_csr_regs();
	prev_state = exception_enter();
	__do_page_fault(regs, write, address);
	exception_exit(prev_state);

	// uty: test
	//print_csr_ks();
        printk("After: ");
        dump_csr_regs();
	dump_pt_regs("leave do_page_fault", regs);
        dump_pte_pair();
}
