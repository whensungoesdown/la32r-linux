# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the Linux/LoongArch-specific parts of the memory manager.
#

obj-y				+= init.o cache.o tlb.o extable.o \
				   fault.o ioremap.o mmap.o pgtable.o page.o

obj-$(CONFIG_32BIT)		+= pgtable-32.o tlbex-32.o

# SoC2 debug: ITLB/DTLB consistency check, see soc2_tlbcheck.c
obj-y				+= soc2_tlbcheck.o
obj-$(CONFIG_HUGETLB_PAGE)	+= hugetlbpage.o
