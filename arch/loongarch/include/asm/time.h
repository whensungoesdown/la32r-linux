/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#ifndef _ASM_TIME_H
#define _ASM_TIME_H

#include <linux/clockchips.h>
#include <linux/clocksource.h>
#include <asm/loongarchregs.h>

extern u64 cpu_clock_freq;
extern u64 const_clock_freq;

extern void sync_counter(void);

#ifdef CONFIG_64BIT
static inline unsigned int calc_const_freq(void)
{
	unsigned int res;
	unsigned int base_freq;
	unsigned int cfm, cfd;

	res = read_cpucfg(LOONGARCH_CPUCFG2);
	if (!(res & CPUCFG2_LLFTP))
		return 0;

	base_freq = read_cpucfg(LOONGARCH_CPUCFG4);
	res = read_cpucfg(LOONGARCH_CPUCFG5);
	cfm = res & 0xffff;
	cfd = (res >> 16) & 0xffff;

	if (!base_freq || !cfm || !cfd)
		return 0;
	else
		return (base_freq * cfm / cfd);
}
#endif

#ifdef CONFIG_32BIT
static inline unsigned int calc_const_freq(void)
{
#ifdef CONFIG_LS_SOC
	return 200000000;
#elif CONFIG_BX_SOC
	return 33000000;
#endif
}
#endif

/*
 * Initialize the calling CPU's timer interrupt as clockevent device
 */
extern int constant_clockevent_init(void);
extern int constant_clocksource_init(void);

static inline void clockevent_set_clock(struct clock_event_device *cd,
					unsigned int clock)
{
	clockevents_calc_mult_shift(cd, clock, 4);
}

#endif /* _ASM_TIME_H */
