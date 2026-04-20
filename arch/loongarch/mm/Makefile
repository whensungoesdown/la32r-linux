# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the Linux/LoongArch-specific parts of the memory manager.
#

obj-y				+= init.o cache.o extable.o \
				   fault.o ioremap.o nommu.o 

#obj-$(CONFIG_32BIT)		+= pgtable-32.o tlbex-32.o
obj-$(CONFIG_HUGETLB_PAGE)	+= hugetlbpage.o

obj-$(CONFIG_MMU)		+= tlb.o page.o pgtable.o pgtable-32.o tlbex-32.o mmap.o

#obj-$(CONFIG_NOMMU) 		+= nommu.o

