// SPDX-License-Identifier: GPL-2.0
/*
 * Check the cpu7b ITLB and DTLB against the page tables of the current
 * task. Debug only.
 *
 * cpu7b has two software-managed TLBs of 32 entries each. TLBIDX.I_D
 * (bit 16) selects which one TLBRD, TLBWR, TLBFILL, TLBSRCH and INVTLB act
 * on, so the kernel must keep both consistent with the page tables.
 *
 * Reports:
 *   DUP    two valid entries in the same TLB match the same VPPN (same ASID,
 *          or one of them global). If both are in the same group of four
 *          (i / 4 == j / 4), the c7btlb priority encoder returns a wrong
 *          index and the lookup uses an unrelated entry.
 *   STALE  a valid page of the current ASID whose PPN does not match the
 *          page table, or that has no present PTE.
 *
 * soc2_tlb_check()        prints all valid entries and the result. Call it
 *                         where the address space is stable, for example
 *                         before do_page_fault() sends SIGSEGV.
 * soc2_tlb_check_quiet()  prints only the first problem it finds, with the
 *                         TLB contents. Cheap enough to call at the end of
 *                         __update_tlb(), after the TLB write, to catch a
 *                         bad entry when it is created.
 *
 * Build: add "obj-y += soc2_tlbcheck.o" to arch/loongarch/mm/Makefile.
 */
#include <linux/irqflags.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <linux/uaccess.h>
#include <asm/pgtable.h>

#define NR_TLB		32

#define CSR_TLBIDX	0x10
#define CSR_TLBEHI	0x11
#define CSR_TLBELO0	0x12
#define CSR_TLBELO1	0x13
#define CSR_ASID	0x18

#define TLBIDX_NE	(1UL << 31)
#define TLBIDX_I_D	(1UL << 16)
#define TLBELO_V	(1UL << 0)
#define TLBELO_G	(1UL << 6)
#define TLBELO_PFN(lo)	(((lo) >> 8) & 0xfffff)		/* PA[31:12] */
#define ASID_MASK	0x3ff

#define __str(x)	#x
#define str(x)		__str(x)

#define csr_rd(csr) ({						\
	unsigned long __v;					\
	asm volatile("csrrd %0, " str(csr) : "=r"(__v));	\
	__v;							\
})

/* csrwr swaps the register and the CSR, the old value is discarded */
#define csr_wr(csr, val) do {					\
	unsigned long __v = (val);				\
	asm volatile("csrwr %0, " str(csr)			\
		     : "+r"(__v) : : "memory");			\
} while (0)

struct tlb_ent {
	unsigned long ehi;
	unsigned long lo[2];
	unsigned long asid;
	int valid;
};

/* 2 x 32 entries, kept off the kernel stack; callers run with irqs off */
static struct tlb_ent tlb[2][NR_TLB];

static void tlb_read_all(void)
{
	unsigned long idx, ehi, lo0, lo1, asid;
	int d, i;

	idx  = csr_rd(CSR_TLBIDX);
	ehi  = csr_rd(CSR_TLBEHI);
	lo0  = csr_rd(CSR_TLBELO0);
	lo1  = csr_rd(CSR_TLBELO1);
	asid = csr_rd(CSR_ASID);

	for (d = 0; d < 2; d++) {
		for (i = 0; i < NR_TLB; i++) {
			struct tlb_ent *e = &tlb[d][i];

			csr_wr(CSR_TLBIDX, (d ? TLBIDX_I_D : 0) | i);
			asm volatile("tlbrd" : : : "memory");

			e->valid = !(csr_rd(CSR_TLBIDX) & TLBIDX_NE);
			e->ehi   = csr_rd(CSR_TLBEHI);
			e->lo[0] = csr_rd(CSR_TLBELO0);
			e->lo[1] = csr_rd(CSR_TLBELO1);
			e->asid  = csr_rd(CSR_ASID) & ASID_MASK;
		}
	}

	/* TLBRD overwrites these; a wrong ASID would break all translation */
	csr_wr(CSR_TLBIDX, idx);
	csr_wr(CSR_TLBEHI, ehi);
	csr_wr(CSR_TLBELO0, lo0);
	csr_wr(CSR_TLBELO1, lo1);
	csr_wr(CSR_ASID, asid);
}

static int user_pte(struct mm_struct *mm, unsigned long addr, pte_t *out)
{
	pgd_t *pgd;
	p4d_t *p4d;
	pud_t *pud;
	pmd_t *pmd;
	pte_t *ptep;

	pgd = pgd_offset(mm, addr);
	if (pgd_none(*pgd))
		return 0;
	p4d = p4d_offset(pgd, addr);
	if (p4d_none(*p4d))
		return 0;
	pud = pud_offset(p4d, addr);
	if (pud_none(*pud))
		return 0;
	pmd = pmd_offset(pud, addr);
	if (pmd_none(*pmd))
		return 0;

	ptep = pte_offset_map(pmd, addr);
	*out = *ptep;
	pte_unmap(ptep);
	return 1;
}

static int is_global(const struct tlb_ent *e)
{
	return !!(e->lo[0] & TLBELO_G);
}

static void dump_entries(void)
{
	int d, i;

	for (d = 0; d < 2; d++) {
		for (i = 0; i < NR_TLB; i++) {
			struct tlb_ent *e = &tlb[d][i];

			if (!e->valid)
				continue;
			pr_info("  %cTLB[%2d] ehi=%08lx asid=%03lx lo0=%08lx lo1=%08lx\n",
				d ? 'D' : 'I', i, e->ehi, e->asid, e->lo[0], e->lo[1]);
		}
	}
}

static int check_dups(void)
{
	int d, i, j, n = 0;

	for (d = 0; d < 2; d++) {
		for (i = 0; i < NR_TLB; i++) {
			struct tlb_ent *a = &tlb[d][i];

			if (!a->valid)
				continue;
			for (j = i + 1; j < NR_TLB; j++) {
				struct tlb_ent *b = &tlb[d][j];

				if (!b->valid || (a->ehi >> 13) != (b->ehi >> 13))
					continue;
				if (a->asid != b->asid && !is_global(a) && !is_global(b))
					continue;
				pr_err("  DUP   %cTLB[%d] and [%d], va %08lx%s\n",
				       d ? 'D' : 'I', i, j, a->ehi & ~0x1fffUL,
				       i / 4 == j / 4 ?
				       ", same group of 4: lookup returns a wrong entry" : "");
				n++;
			}
		}
	}
	return n;
}

static int check_stale(struct mm_struct *mm, unsigned long cur_asid)
{
	int d, i, k, n = 0;

	if (!mm)
		return 0;

	for (d = 0; d < 2; d++) {
		for (i = 0; i < NR_TLB; i++) {
			struct tlb_ent *e = &tlb[d][i];

			if (!e->valid || is_global(e) || e->asid != cur_asid)
				continue;

			for (k = 0; k < 2; k++) {
				unsigned long va = (e->ehi & ~0x1fffUL) | (k << PAGE_SHIFT);
				unsigned long lo = e->lo[k];
				pte_t pte;

				if (!(lo & TLBELO_V) || va >= TASK_SIZE)
					continue;

				if (!user_pte(mm, va, &pte) || !pte_present(pte)) {
					pr_err("  STALE %cTLB[%d] va %08lx -> pfn %05lx, no present pte\n",
					       d ? 'D' : 'I', i, va, TLBELO_PFN(lo));
					n++;
				} else if (pte_pfn(pte) != TLBELO_PFN(lo)) {
					pr_err("  STALE %cTLB[%d] va %08lx -> pfn %05lx, pte pfn %05lx\n",
					       d ? 'D' : 'I', i, va, TLBELO_PFN(lo), pte_pfn(pte));
					n++;
				}
			}
		}
	}
	return n;
}

static void tlb_check(int verbose)
{
	static int reported;
	struct mm_struct *mm = current->mm;
	unsigned long cur_asid, flags;
	int dups, stale;

	if (!verbose && reported)
		return;

	local_irq_save(flags);
	cur_asid = csr_rd(CSR_ASID) & ASID_MASK;
	tlb_read_all();
	local_irq_restore(flags);

	if (verbose)
		pr_info("TLB check: pid %d (%s) asid %03lx\n",
			current->pid, current->comm, cur_asid);

	dups = check_dups();
	stale = check_stale(mm, cur_asid);

	if (!verbose && !dups && !stale)
		return;

	if (!verbose) {
		reported = 1;	/* report the first problem only */
		pr_err("TLB check: problem after TLB update, pid %d (%s) asid %03lx\n",
		       current->pid, current->comm, cur_asid);
		dump_stack();
	}
	dump_entries();
	pr_info("TLB check: %d duplicate, %d stale\n", dups, stale);
}

void soc2_tlb_check(void)
{
	tlb_check(1);
}

void soc2_tlb_check_quiet(void)
{
	tlb_check(0);
}

/*
 * soc2_dump_user_words() - print n words at user address va, each read
 * twice: through the user mapping (TLB) and through the kernel mapping of
 * the physical page found in the page table. Debug only.
 *
 * Use it on data that was written and then read back wrong:
 *   user == kernel == expected  memory is right, the load that crashed
 *                               returned wrong data or was not executed
 *   user == kernel == old       the store never reached memory
 *   user != kernel              the user mapping goes to another frame
 */
void soc2_dump_user_words(unsigned long va, int n)
{
	struct mm_struct *mm = current->mm;
	int i;

	va &= ~3UL;
	for (i = 0; i < n; i++, va += 4) {
		u32 uval = 0, kval = 0;
		int uerr, have_k = 0;
		unsigned long pfn = 0;
		pte_t pte;

		uerr = copy_from_user_nofault(&uval, (const void __user *)va, 4);

		if (mm && va < TASK_SIZE && user_pte(mm, va, &pte) && pte_present(pte)) {
			pfn = pte_pfn(pte);
			if (pfn_valid(pfn)) {
				kval = *(u32 *)(page_address(pfn_to_page(pfn)) + (va & ~PAGE_MASK));
				have_k = 1;
			}
		}

		if (uerr)
			pr_info("  %08lx: user <fault>", va);
		else
			pr_info("  %08lx: user %08x", va, uval);
		if (have_k)
			pr_cont("  pfn %05lx kernel %08x%s\n", pfn, kval,
				(!uerr && uval != kval) ? "  <-- differ" : "");
		else
			pr_cont("  (no present pte)\n");
	}
}

/*
 * soc2_scan_user_words() - print the user words in [start, start + len)
 * with (word & mask) == value, at most 16. Pages that are not mapped are
 * skipped. Debug only.
 *
 * Used to find where a store went: for example the _flags of a stdio
 * FILE (0xfbadxxxx) that is missing from the FILE that crashed.
 */
void soc2_scan_user_words(unsigned long start, unsigned long len,
			  u32 mask, u32 value)
{
	unsigned long va, end;
	u32 buf[64];		/* 256 bytes, never crosses a page */
	int i, found = 0;

	start &= ~(sizeof(buf) - 1);
	end = start + len;
	for (va = start; va < end; va += sizeof(buf)) {
		if (copy_from_user_nofault(buf, (const void __user *)va, sizeof(buf)))
			continue;
		for (i = 0; i < 64; i++) {
			if ((buf[i] & mask) != value)
				continue;
			pr_info("  %08lx: %08x\n", va + i * 4, buf[i]);
			if (++found >= 16)
				return;
		}
	}
	if (!found)
		pr_info("  none\n");
}
