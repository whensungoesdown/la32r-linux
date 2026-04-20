// arch/loongarch/mm/nommu.c
// SPDX-License-Identifier: GPL-2.0
#include <linux/types.h>
#include <linux/string.h>
#include <linux/mm.h>

/* Memory operations */
void copy_page(void *to, void *from)
{
    memcpy(to, from, PAGE_SIZE);
}

void clear_page(void *page)
{
    memset(page, 0, PAGE_SIZE);
}

/* Address validation */
int __virt_addr_valid(volatile void *kaddr)
{
    return 1;  /* 所有地址都有效 */
}

/* Physical memory access for /dev/mem */
int generic_access_phys(struct vm_area_struct *vma, unsigned long addr,
                        void *buf, int len, int write)
{
    return -EINVAL;
}

/* TLB operations (empty for NOMMU) */
void local_flush_tlb_all(void) { }
void tlb_init(void) { }

/* FPU operations */
void do_fpu(void) { }
void _save_fp(void) { }
void _restore_fp(void) { }
void _init_fpu(void) { }
void _save_fp_context(void) { }
void _restore_fp_context(void) { }

/* Page table operations */
void pagetable_init(void) { }

/* VDSO operations (empty for NOMMU) */
void update_vsyscall(void) { }
void update_vsyscall_tz(void) { }

/* VMA operations for VDSO */
//unsigned long get_unmapped_area(struct file *addr, unsigned long len,
//                                unsigned long pgoff, unsigned long flags, unsigned log)
//{
//    return 0;  /* 简单返回0，VDSO被禁用时不应被调用 */
//}

//struct vm_area_struct *_install_special_mapping(struct mm_struct *mm,
//                             unsigned long addr, unsigned long len,
//                             unsigned long flags, struct page **pages)
//{
//    return 0;  /* VDSO被禁用时不应被调用 */
//}

/* Cache related */
unsigned long shm_align_mask = 0UL;
