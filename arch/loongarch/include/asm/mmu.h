/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#ifndef __ASM_MMU_H
#define __ASM_MMU_H

#include <linux/atomic.h>
#include <linux/spinlock.h>

typedef struct {
	u64 asid[NR_CPUS];
	void *vdso;
	unsigned long end_brk;
#ifdef CONFIG_BINFMT_ELF_FDPIC
	unsigned long	exec_fdpic_loadmap;
	unsigned long	interp_fdpic_loadmap;
#endif
} mm_context_t;

#endif /* __ASM_MMU_H */
