/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#include <asm/asm.h>
#include <asm/export.h>
#include <asm/loongarchregs.h>
#include <asm/page.h>
#include <asm/pgtable-bits.h>
#include <asm/regdef.h>
#include <asm/stackframe.h>

#include <asm/pgtable-32.h>

	// uty: test
	.macro set_tlbidx_by_esubcode tmp0, tmp1
	    csrrd   \tmp1, 0x5                // Read ESTAT
	    srli.w  \tmp1, \tmp1, 22
	    andi    \tmp1, \tmp1, 0x1ff
	
	    li.w    \tmp0, 1
	    bne     \tmp1, \tmp0, .Lnot_esubcode1_\@
	    li.w    \tmp0, 0x00010000         // rd: value to write (set bit16)
	    b       .Ldone_\@
	.Lnot_esubcode1_\@:
	    li.w    \tmp0, 0x00000000         // rd: value to write (clear bit16)
	.Ldone_\@:
	    li.w    \tmp1, 0x00010000         // rj: mask (only bit16)
	    csrxchg \tmp0, \tmp1, 0x10        // Now tmp0 = old TLBIDX, CSR updated
	.endm

	// Macro: Set bit 16 (I/D flag) in TLBIDX CSR
	// Usage: set_tlbidx_i_d t0, t1
	// The macro uses two temporary registers (overwritten).
	.macro set_tlbidx_i_d tmp0, tmp1
	    li.w    \tmp0, 0x00010000          // Value to write: bit16 = 1
	    li.w    \tmp1, 0x00010000          // Mask: only bit16 is affected
	    csrxchg \tmp0, \tmp1, 0x10         // Atomic update of TLBIDX (CSR address 0x10)
	.endm
	
	// Macro: Clear bit 16 (I/D flag) in TLBIDX CSR
	// Usage: clear_tlbidx_i_d t0, t1
	// The macro uses two temporary registers (overwritten).
	.macro clear_tlbidx_i_d tmp0, tmp1
	    li.w    \tmp0, 0x00000000          // Value to write: bit16 = 0
	    li.w    \tmp1, 0x00010000          // Mask: only bit16 is affected
	    csrxchg \tmp0, \tmp1, 0x10         // Atomic update of TLBIDX (CSR address 0x10)
	.endm

.macro OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_BADV
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

.macro TLBEHI_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_TLBEHI
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

.macro TLBELO0_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_TLBELO0
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

.macro TLBELO1_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_TLBELO1
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

.macro TLBIDX_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_TLBIDX
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm


.macro EPC_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_EPC
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

.macro KS0_OUT_HEX_NIBBLE shift
    csrrd   t1, LOONGARCH_CSR_KS0
    srli.w  t1, t1, \shift
    andi    t1, t1, 0xf
    slti    t0, t1, 10
    bnez    t0, 1f
    addi.w  t1, t1, 0x37          # 'A' - 10
    b       2f
1:  addi.w  t1, t1, 0x30          # '0'
2:  li.w    t0, 0xa0020000        # serial data register
    st.b    t1, t0, 0
    li.w    t0, 0xa0020004        # serial status register
3:  ld.w    t1, t0, 0
    bnez    t1, 3b
.endm

	.macro tlb_do_page_fault, write
	SYM_FUNC_START(tlb_do_page_fault_\write)
	SAVE_ALL
	// uty: test
	move    a0, sp
    	bl      dump_tlb_pf_caller

	csrrd	a2, LOONGARCH_CSR_BADV
	KMODE
	move	a0, sp
	REG_S	a2, sp, PT_BVADDR
	li.w	a1, \write
	la.abs	t0, do_page_fault
	jirl    ra, t0, 0
	// uty: test
	//la.abs	t0, ret_from_exception
	//jirl    zero, t0, 0
	RESTORE_ALL_AND_RET
	SYM_FUNC_END(tlb_do_page_fault_\write)
	.endm

SYM_FUNC_START(handle_tlb_rixi)
	csrwr	t0, EXCEPTION_KS0
	csrwr	t1, EXCEPTION_KS1
SYM_FUNC_END(handle_tlb_rixi)
	/* Go through */
	tlb_do_page_fault 0
	tlb_do_page_fault 1


SYM_FUNC_START(handle_tlb_fetch)
	csrwr	ra, EXCEPTION_KS2
	
        // uty: test
        //csrrd   t0, LOONGARCH_CSR_BADV      # t0 = BADV
        //csrwr   t0, LOONGARCH_CSR_TLBEHI    # TLBEHI = t0

        # ---- 串口输出字符 'F' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x46
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

        csrrd   t1, 0x5                // Read ESTAT
        srli.w  t1, t1, 22
        andi    t1, t1, 0x1ff
        addi.w  t1, t1, 0x30           // print '0' or '1'
        li.w    t0, 0xa0020000           # 串口物理地址
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output BADV[31:28], [27:24], ..., [3:0]
    OUT_HEX_NIBBLE 28
    OUT_HEX_NIBBLE 24
    OUT_HEX_NIBBLE 20
    OUT_HEX_NIBBLE 16
    OUT_HEX_NIBBLE 12
    OUT_HEX_NIBBLE 8
    OUT_HEX_NIBBLE 4
    OUT_HEX_NIBBLE 0

    # Output TLBEHI[31:28], [27:24], ..., [3:0]
    TLBEHI_OUT_HEX_NIBBLE 28
    TLBEHI_OUT_HEX_NIBBLE 24
    TLBEHI_OUT_HEX_NIBBLE 20
    TLBEHI_OUT_HEX_NIBBLE 16
    TLBEHI_OUT_HEX_NIBBLE 12
    TLBEHI_OUT_HEX_NIBBLE 8
    TLBEHI_OUT_HEX_NIBBLE 4
    TLBEHI_OUT_HEX_NIBBLE 0

	// uty: test
	//set_tlbidx_by_esubcode t0, t1
        clear_tlbidx_i_d   t0, t1
        //csrwr   t0, 0x10

	lu12i.w	ra, 0xc
	slli.w	ra, ra, 0x10
	csrrd	t0, LOONGARCH_CSR_BADV
	bgeu	t0, ra, vmalloc_fetch

	csrrd	t1, LOONGARCH_CSR_PGD

vmalloc_done_fetch:
	/* Get PGD offset in bytes */
	srli.w	t0, t0, 0x16
	andi	t0, t0,	0x3ff
	slli.w	t0, t0, 0x2
	add.w	t1, t1, t0
	csrrd	t0, LOONGARCH_CSR_BADV
	ld.w	t1, t1, 0
	srli.w	t0, t0, 0xc
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 0x2
	add.w	t0, t0, t1

label_smp_pgtable_fetch:
	ld.w	t1, t0, 0
	tlbsrch

	srli.w  ra, t1, _PAGE_PRESENT_SHIFT
	andi    ra, ra, 1
	beq     ra, zero, nopage_tlb_fetch


	#ori	t1, t1, _PAGE_VALID
	ori	t1, t1, 0x1
	st.w	t1, t0, 0

	ori	t0, t0, 0x4
	xori	t0, t0, 0x4

	ld.w	t1, t0, 0
	srli.w	ra, t1, 0xc
	slli.w	ra, ra, 0x8
	andi	t1, t1, 0xff
	add.w	t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO0

	ld.w	t0, t0, 0x4
	srli.w  ra, t0, 0xc
        slli.w  ra, ra, 0x8
        andi    t0, t0, 0xff
        add.w   t0, t0, ra
	csrwr	t0, LOONGARCH_CSR_TLBELO1

    # Output TLBELO0[31:28], [27:24], ..., [3:0]
    TLBELO0_OUT_HEX_NIBBLE 28
    TLBELO0_OUT_HEX_NIBBLE 24
    TLBELO0_OUT_HEX_NIBBLE 20
    TLBELO0_OUT_HEX_NIBBLE 16
    TLBELO0_OUT_HEX_NIBBLE 12
    TLBELO0_OUT_HEX_NIBBLE 8
    TLBELO0_OUT_HEX_NIBBLE 4
    TLBELO0_OUT_HEX_NIBBLE 0

    # Output TLBELO1[31:28], [27:24], ..., [3:0]
    TLBELO1_OUT_HEX_NIBBLE 28
    TLBELO1_OUT_HEX_NIBBLE 24
    TLBELO1_OUT_HEX_NIBBLE 20
    TLBELO1_OUT_HEX_NIBBLE 16
    TLBELO1_OUT_HEX_NIBBLE 12
    TLBELO1_OUT_HEX_NIBBLE 8
    TLBELO1_OUT_HEX_NIBBLE 4
    TLBELO1_OUT_HEX_NIBBLE 0

    # Output TLBIDX[31:28], [27:24], ..., [3:0]
    TLBIDX_OUT_HEX_NIBBLE 28
    TLBIDX_OUT_HEX_NIBBLE 24
    TLBIDX_OUT_HEX_NIBBLE 20
    TLBIDX_OUT_HEX_NIBBLE 16
    TLBIDX_OUT_HEX_NIBBLE 12
    TLBIDX_OUT_HEX_NIBBLE 8
    TLBIDX_OUT_HEX_NIBBLE 4
    TLBIDX_OUT_HEX_NIBBLE 0

	tlbwr
        // uty: test
        # ---- 串口输出字符 'f' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x66
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待


    # Output EPC[31:28], [27:24], ..., [3:0]
    EPC_OUT_HEX_NIBBLE 28
    EPC_OUT_HEX_NIBBLE 24
    EPC_OUT_HEX_NIBBLE 20
    EPC_OUT_HEX_NIBBLE 16
    EPC_OUT_HEX_NIBBLE 12
    EPC_OUT_HEX_NIBBLE 8
    EPC_OUT_HEX_NIBBLE 4
    EPC_OUT_HEX_NIBBLE 0

	csrrd	t0, LOONGARCH_CSR_KS0
	csrrd	t1, LOONGARCH_CSR_KS1
	csrrd	ra, EXCEPTION_KS2
	ertn

vmalloc_fetch:
	la.abs  t1, swapper_pg_dir
	b       vmalloc_done_fetch

	/*
	 * This is the entry point when build_tlbchange_handler_head
	 * spots a huge page.
	 */

nopage_tlb_fetch:
	dbar	0
        csrrd   ra, EXCEPTION_KS2
	la.abs	t0, tlb_do_page_fault_0
	jirl	$r0, t0, 0

SYM_FUNC_END(handle_tlb_fetch)


SYM_FUNC_START(handle_tlb_load)
	csrwr	ra, EXCEPTION_KS2
	
        // uty: test
        //csrrd   t0, LOONGARCH_CSR_BADV      # t0 = BADV
        //csrwr   t0, LOONGARCH_CSR_TLBEHI    # TLBEHI = t0

        # ---- 串口输出字符 'L' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x4c
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

        csrrd   t1, 0x5                // Read ESTAT
        srli.w  t1, t1, 22
        andi    t1, t1, 0x1ff
        addi.w  t1, t1, 0x30           // print '0' or '1'
        li.w    t0, 0xa0020000           # 串口物理地址
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output BADV[31:28], [27:24], ..., [3:0]
    OUT_HEX_NIBBLE 28
    OUT_HEX_NIBBLE 24
    OUT_HEX_NIBBLE 20
    OUT_HEX_NIBBLE 16
    OUT_HEX_NIBBLE 12
    OUT_HEX_NIBBLE 8
    OUT_HEX_NIBBLE 4
    OUT_HEX_NIBBLE 0

    # Output TLBEHI[31:28], [27:24], ..., [3:0]
    TLBEHI_OUT_HEX_NIBBLE 28
    TLBEHI_OUT_HEX_NIBBLE 24
    TLBEHI_OUT_HEX_NIBBLE 20
    TLBEHI_OUT_HEX_NIBBLE 16
    TLBEHI_OUT_HEX_NIBBLE 12
    TLBEHI_OUT_HEX_NIBBLE 8
    TLBEHI_OUT_HEX_NIBBLE 4
    TLBEHI_OUT_HEX_NIBBLE 0

	// uty: test
	//set_tlbidx_by_esubcode t0, t1
	set_tlbidx_i_d   t0, t1 

	lu12i.w	ra, 0xc
	slli.w	ra, ra, 0x10
	csrrd	t0, LOONGARCH_CSR_BADV
	bgeu	t0, ra, vmalloc_load

	csrrd	t1, LOONGARCH_CSR_PGD

vmalloc_done_load:
	/* Get PGD offset in bytes */
	srli.w	t0, t0, 0x16
	andi	t0, t0,	0x3ff
	slli.w	t0, t0, 0x2
	add.w	t1, t1, t0
	csrrd	t0, LOONGARCH_CSR_BADV
	ld.w	t1, t1, 0
	srli.w	t0, t0, 0xc
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 0x2
	add.w	t0, t0, t1

label_smp_pgtable_load:
	ld.w	t1, t0, 0
	tlbsrch

	srli.w  ra, t1, _PAGE_PRESENT_SHIFT
	andi    ra, ra, 1
	beq     ra, zero, nopage_tlb_load


	ori	t1, t1, _PAGE_VALID
	st.w	t1, t0, 0

	ori	t0, t0, 0x4
	xori	t0, t0, 0x4

	ld.w	t1, t0, 0
	srli.w	ra, t1, 0xc
	slli.w	ra, ra, 0x8
	andi	t1, t1, 0xff
	add.w	t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO0

	ld.w	t0, t0, 0x4
	srli.w  ra, t0, 0xc
        slli.w  ra, ra, 0x8
        andi    t0, t0, 0xff
        add.w   t0, t0, ra
	csrwr	t0, LOONGARCH_CSR_TLBELO1

    # Output TLBELO0[31:28], [27:24], ..., [3:0]
    TLBELO0_OUT_HEX_NIBBLE 28
    TLBELO0_OUT_HEX_NIBBLE 24
    TLBELO0_OUT_HEX_NIBBLE 20
    TLBELO0_OUT_HEX_NIBBLE 16
    TLBELO0_OUT_HEX_NIBBLE 12
    TLBELO0_OUT_HEX_NIBBLE 8
    TLBELO0_OUT_HEX_NIBBLE 4
    TLBELO0_OUT_HEX_NIBBLE 0

    # Output TLBELO1[31:28], [27:24], ..., [3:0]
    TLBELO1_OUT_HEX_NIBBLE 28
    TLBELO1_OUT_HEX_NIBBLE 24
    TLBELO1_OUT_HEX_NIBBLE 20
    TLBELO1_OUT_HEX_NIBBLE 16
    TLBELO1_OUT_HEX_NIBBLE 12
    TLBELO1_OUT_HEX_NIBBLE 8
    TLBELO1_OUT_HEX_NIBBLE 4
    TLBELO1_OUT_HEX_NIBBLE 0

    # Output TLBIDX[31:28], [27:24], ..., [3:0]
    TLBIDX_OUT_HEX_NIBBLE 28
    TLBIDX_OUT_HEX_NIBBLE 24
    TLBIDX_OUT_HEX_NIBBLE 20
    TLBIDX_OUT_HEX_NIBBLE 16
    TLBIDX_OUT_HEX_NIBBLE 12
    TLBIDX_OUT_HEX_NIBBLE 8
    TLBIDX_OUT_HEX_NIBBLE 4
    TLBIDX_OUT_HEX_NIBBLE 0


	tlbwr
        // uty: test
        # ---- 串口输出字符 'l' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x6c
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

	csrrd	t0, LOONGARCH_CSR_KS0
	csrrd	t1, LOONGARCH_CSR_KS1
	csrrd	ra, EXCEPTION_KS2
	ertn

vmalloc_load:
	la.abs  t1, swapper_pg_dir
	b       vmalloc_done_load

	/*
	 * This is the entry point when build_tlbchange_handler_head
	 * spots a huge page.
	 */

nopage_tlb_load:
	dbar	0
        csrrd   ra, EXCEPTION_KS2
	la.abs	t0, tlb_do_page_fault_0
	jirl	$r0, t0, 0

SYM_FUNC_END(handle_tlb_load)




SYM_FUNC_START(handle_tlb_store)
	csrwr	ra, EXCEPTION_KS2

        // uty: test
        //csrrd   t0, LOONGARCH_CSR_BADV      # t0 = BADV
        //csrwr   t0, LOONGARCH_CSR_TLBEHI    # TLBEHI = t0

        # ---- 串口输出字符 'S' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x53
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待


        csrrd   t1, 0x5                // Read ESTAT
        srli.w  t1, t1, 22
        andi    t1, t1, 0x1ff
        addi.w  t1, t1, 0x30           // print '0' or '1'
        li.w    t0, 0xa0020000           # 串口物理地址
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output BADV[31:28], [27:24], ..., [3:0]
    OUT_HEX_NIBBLE 28
    OUT_HEX_NIBBLE 24
    OUT_HEX_NIBBLE 20
    OUT_HEX_NIBBLE 16
    OUT_HEX_NIBBLE 12
    OUT_HEX_NIBBLE 8
    OUT_HEX_NIBBLE 4
    OUT_HEX_NIBBLE 0

    # Output TLBEHI[31:28], [27:24], ..., [3:0]
    TLBEHI_OUT_HEX_NIBBLE 28
    TLBEHI_OUT_HEX_NIBBLE 24
    TLBEHI_OUT_HEX_NIBBLE 20
    TLBEHI_OUT_HEX_NIBBLE 16
    TLBEHI_OUT_HEX_NIBBLE 12
    TLBEHI_OUT_HEX_NIBBLE 8
    TLBEHI_OUT_HEX_NIBBLE 4
    TLBEHI_OUT_HEX_NIBBLE 0

	// uty: test
	//set_tlbidx_by_esubcode t0, t1
	set_tlbidx_i_d   t0, t1   // dtlb

	lu12i.w ra, 0xc
        slli.w  ra, ra, 0x10
	csrrd	t0, LOONGARCH_CSR_BADV
	bgeu    t0, ra, vmalloc_store

	csrrd	t1, LOONGARCH_CSR_PGD

vmalloc_done_store:
	/* Get PGD offset in bytes */
	srli.w	t0, t0, 0x16
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 2
	add.w	t1, t1, t0
	csrrd	t0, LOONGARCH_CSR_BADV
	ld.w	t1, t1, 0
	srli.w	t0, t0, 0xc
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 0x2
	add.w	t1, t1, t0

label_smp_pgtable_store:
	ld.w	t0, t1, 0
	tlbsrch

	srli.w  ra, t0, _PAGE_PRESENT_SHIFT
        andi    ra, ra, ((_PAGE_PRESENT | _PAGE_WRITE) >> _PAGE_PRESENT_SHIFT)
	xori    ra, ra, ((_PAGE_PRESENT | _PAGE_WRITE) >> _PAGE_PRESENT_SHIFT)
	bne	ra, $r0, nopage_tlb_store

	ori	t0, t0, (_PAGE_VALID | _PAGE_DIRTY)
	st.w	t0, t1, 0

	ori	t1, t1, 4
	xori	t1, t1, 4

	ld.w	t0, t1, 0
	srli.w  ra, t0, 0xc
        slli.w  ra, ra, 0x8
        andi    t0, t0, 0xff
        add.w   t0, t0, ra
	csrwr   t0, LOONGARCH_CSR_TLBELO0

	ld.w	t1, t1, 4
	srli.w  ra, t1, 0xc
        slli.w  ra, ra, 0x8
        andi    t1, t1, 0xff
        add.w   t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO1

    # Output TLBELO0[31:28], [27:24], ..., [3:0]
    TLBELO0_OUT_HEX_NIBBLE 28
    TLBELO0_OUT_HEX_NIBBLE 24
    TLBELO0_OUT_HEX_NIBBLE 20
    TLBELO0_OUT_HEX_NIBBLE 16
    TLBELO0_OUT_HEX_NIBBLE 12
    TLBELO0_OUT_HEX_NIBBLE 8
    TLBELO0_OUT_HEX_NIBBLE 4
    TLBELO0_OUT_HEX_NIBBLE 0

    # Output TLBELO1[31:28], [27:24], ..., [3:0]
    TLBELO1_OUT_HEX_NIBBLE 28
    TLBELO1_OUT_HEX_NIBBLE 24
    TLBELO1_OUT_HEX_NIBBLE 20
    TLBELO1_OUT_HEX_NIBBLE 16
    TLBELO1_OUT_HEX_NIBBLE 12
    TLBELO1_OUT_HEX_NIBBLE 8
    TLBELO1_OUT_HEX_NIBBLE 4
    TLBELO1_OUT_HEX_NIBBLE 0

    # Output TLBIDX[31:28], [27:24], ..., [3:0]
    TLBIDX_OUT_HEX_NIBBLE 28
    TLBIDX_OUT_HEX_NIBBLE 24
    TLBIDX_OUT_HEX_NIBBLE 20
    TLBIDX_OUT_HEX_NIBBLE 16
    TLBIDX_OUT_HEX_NIBBLE 12
    TLBIDX_OUT_HEX_NIBBLE 8
    TLBIDX_OUT_HEX_NIBBLE 4
    TLBIDX_OUT_HEX_NIBBLE 0

	tlbwr

        // uty: test
        # ---- 串口输出字符 's' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x73
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output EPC[31:28], [27:24], ..., [3:0]
    EPC_OUT_HEX_NIBBLE 28
    EPC_OUT_HEX_NIBBLE 24
    EPC_OUT_HEX_NIBBLE 20
    EPC_OUT_HEX_NIBBLE 16
    EPC_OUT_HEX_NIBBLE 12
    EPC_OUT_HEX_NIBBLE 8
    EPC_OUT_HEX_NIBBLE 4
    EPC_OUT_HEX_NIBBLE 0

	csrrd   t0, LOONGARCH_CSR_KS0
	csrrd	t1, LOONGARCH_CSR_KS1
	csrrd	ra, EXCEPTION_KS2
	ertn

vmalloc_store:
        la.abs  t1, swapper_pg_dir
        b       vmalloc_done_store

	/*
	 * This is the entry point when build_tlbchange_handler_head
	 * spots a huge page.
	 */

nopage_tlb_store:
	dbar	0
	csrrd	ra, EXCEPTION_KS2
	la.abs	t0, tlb_do_page_fault_1
	jirl	$r0, t0, 0

SYM_FUNC_END(handle_tlb_store)

SYM_FUNC_START(handle_tlb_modify)
	csrwr	ra, EXCEPTION_KS2

        // uty: test
        //csrrd   t0, LOONGARCH_CSR_BADV      # t0 = BADV
        //csrwr   t0, LOONGARCH_CSR_TLBEHI    # TLBEHI = t0

        # ---- 串口输出字符 'M' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x4d
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

        csrrd   t1, 0x5                // Read ESTAT
        srli.w  t1, t1, 22
        andi    t1, t1, 0x1ff
        addi.w  t1, t1, 0x30           // print '0' or '1'
        li.w    t0, 0xa0020000           # 串口物理地址
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

	// uty: test
	//set_tlbidx_by_esubcode t0, t1
	set_tlbidx_i_d   t0, t1   // dtlb


	/*
	 * The vmalloc handling is not in the hotpath.
	 */
	lu12i.w ra, 0xc
        slli.w  ra, ra, 0x10
        csrrd   t0, LOONGARCH_CSR_BADV
        bgeu    t0, ra, vmalloc_modify

	csrrd	t1, LOONGARCH_CSR_PGD

vmalloc_done_modify:
	/* Get PGD offset in bytes */
	srli.w	t0, t0, 0x16
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 2
	add.w	t1, t1, t0
	csrrd	t0, LOONGARCH_CSR_BADV
	ld.w	t1, t1, 0
	srli.w	t0, t0, 0xc
	andi	t0, t0, 0x3ff
	slli.w	t0, t0, 0x2
	add.w	t1, t1, t0

label_smp_pgtable_modify:
	ld.w	t0, t1, 0
	tlbsrch

	srli.w  ra, t0, _PAGE_WRITE_SHIFT
        andi    ra, ra, 1
	beq	ra, $r0, nopage_tlb_modify

	ori	t0, t0, (_PAGE_VALID | _PAGE_DIRTY)
	st.w	t0, t1, 0

	ori	t1, t1, 4
	xori	t1, t1, 4

	ld.w	t0, t1, 0
        srli.w  ra, t0, 0xc
        slli.w  ra, ra, 0x8
        andi    t0, t0, 0xff
        add.w   t0, t0, ra
	csrwr   t0, LOONGARCH_CSR_TLBELO0

	ld.w	t1, t1, 0x4
	srli.w  ra, t1, 0xc
        slli.w  ra, ra, 0x8
        andi    t1, t1, 0xff
        add.w   t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO1

	tlbwr

        // uty: test
        # ---- 串口输出字符 'm' ----
        li.w    t0, 0xa0020000           # 串口物理地址
        li.w    t1, 0x6d
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

	csrrd	t0, LOONGARCH_CSR_KS0
	csrrd	t1, LOONGARCH_CSR_KS1
	csrrd	ra, EXCEPTION_KS2
	ertn

vmalloc_modify:
        la.abs  t1, swapper_pg_dir
        b       vmalloc_done_modify


nopage_tlb_modify:
	dbar	0
	csrrd	ra, EXCEPTION_KS2
	la.abs	t0, tlb_do_page_fault_1
	jirl	$r0, t0, 0

SYM_FUNC_END(handle_tlb_modify)



SYM_FUNC_START(handle_tlb_refill)
	csrwr	t0, LOONGARCH_CSR_KS0
	csrwr   t1, LOONGARCH_CSR_KS1
	csrwr   ra, EXCEPTION_KS2

//	SAVE_ALL

        // uty: test
        //csrrd   t0, LOONGARCH_CSR_BADV      # t0 = BADV
        //csrwr   t0, LOONGARCH_CSR_TLBEHI    # TLBEHI = t0

        # ---- 串口输出字符 'R' ----
        li.w    t0, 0x20000           # 串口物理地址
        li.w    t1, 0x52
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

        csrrd   t1, 0x5                // Read ESTAT
        srli.w  t1, t1, 22
        andi    t1, t1, 0x1ff
        addi.w  t1, t1, 0x30           // print '0' or '1'
        li.w    t0, 0x20000           # 串口物理地址
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output KS0[31:28], [27:24], ..., [3:0]
    KS0_OUT_HEX_NIBBLE 28
    KS0_OUT_HEX_NIBBLE 24
    KS0_OUT_HEX_NIBBLE 20
    KS0_OUT_HEX_NIBBLE 16
    KS0_OUT_HEX_NIBBLE 12
    KS0_OUT_HEX_NIBBLE 8
    KS0_OUT_HEX_NIBBLE 4
    KS0_OUT_HEX_NIBBLE 0

//    # ---- 输出 BADV 最高字节 (31:24) ----
//    csrrd   t1, LOONGARCH_CSR_BADV   # 读 BADV
//    srli.w  t1, t1, 24               # 右移 24 位，取最高字节
//    andi    t1, t1, 0xff             # 只保留低 8 位
//    li.w    t0, 0x20000              # 串口数据寄存器
//    st.b    t1, t0, 0                # 写字节到串口
//    li.w    t0, 0xa0020004           # 串口状态寄存器
//1:
//    ld.w    t1, t0, 0                # 读状态
//    bnez    t1, 1b                   # 非 0 则等待
//
//    # ---- 输出 BADV 次高字节 (23:16) ----
//    csrrd   t1, LOONGARCH_CSR_BADV
//    srli.w  t1, t1, 16
//    andi    t1, t1, 0xff
//    li.w    t0, 0x20000
//    st.b    t1, t0, 0
//    li.w    t0, 0xa0020004
//2:
//    ld.w    t1, t0, 0
//    bnez    t1, 2b
//
//    # ---- 输出 BADV 字节 (15:8) ----
//    csrrd   t1, LOONGARCH_CSR_BADV
//    srli.w  t1, t1, 8
//    andi    t1, t1, 0xff
//    li.w    t0, 0x20000
//    st.b    t1, t0, 0
//    li.w    t0, 0xa0020004
//3:
//    ld.w    t1, t0, 0
//    bnez    t1, 3b
//
//    # ---- 输出 BADV 最低字节 (7:0) ----
//    csrrd   t1, LOONGARCH_CSR_BADV
//    andi    t1, t1, 0xff
//    li.w    t0, 0x20000
//    st.b    t1, t0, 0
//    li.w    t0, 0xa0020004
//4:
//    ld.w    t1, t0, 0
//    bnez    t1, 4b

    # Output BADV[31:28], [27:24], ..., [3:0]
    OUT_HEX_NIBBLE 28
    OUT_HEX_NIBBLE 24
    OUT_HEX_NIBBLE 20
    OUT_HEX_NIBBLE 16
    OUT_HEX_NIBBLE 12
    OUT_HEX_NIBBLE 8
    OUT_HEX_NIBBLE 4
    OUT_HEX_NIBBLE 0

//        # ---- 读取 TLBIDX 并清除 I_D 位 ----
//        csrrd   t0, 0x10              # t0 = TLBIDX
//        li.w    t1, 0xfffeffff        # 掩码 ~0x00010000
//        and     t0, t0, t1            # t0 = 清除 I_D 后的 TLBIDX
//
//        # ---- 暂存清除后的 TLBIDX 到 KS3 ----
//        csrwr   t0, LOONGARCH_CSR_KS3
//
//        # ---- 提取 ESUBCODE ----
//        csrrd   t1, 0x5               # t1 = ESTAT
//        srli.w  t1, t1, 22
//        andi    t1, t1, 0x1ff         # t1 = ESUBCODE (0 或 1)
//
//        # ---- 判断 ESUBCODE 是否等于 1 ----
//        li.w    t0, 0x1               # t0 = 1（用作比较）
//        bne     t1, t0, set_itlb      # 若 ESUBCODE != 1 → ITLB，跳转
//
//        # ---- ESUBCODE == 1 → DTLB refill ----
//        li.w    t1, 0x00010000        # I_D = 1
//        b       set_i_d_done
//
//set_itlb:
//        # ---- ESUBCODE != 1 → ITLB refill ----
//        li.w    t1, 0x0               # I_D = 0
//
//set_i_d_done:
//
//        # ---- 恢复 TLBIDX（从 KS3） ----
//        csrrd   t0, LOONGARCH_CSR_KS3
//
//        # ---- 合并 I_D 并写回 TLBIDX ----
//        or      t0, t0, t1
//        csrwr   t0, 0x10

	set_tlbidx_by_esubcode t0, t1

	csrrd	t0, LOONGARCH_CSR_PGD
	csrrd   t1, LOONGARCH_CSR_BADV
	srli.w	t1, t1, 0x16
	andi    t1, t1, 0x3ff 
	slli.w	t1, t1, 0x2
	add.w	t0, t0, t1
	li.w	ra, 0x1fffffff
	and	t0, t0, ra
	ld.w	t0, t0, 0

	csrrd	t1, LOONGARCH_CSR_BADV
	#srli.w	t1, t1, 0xa
	#andi	t1, t1, 0xff8
	srli.w  t1, t1, 12    
	#andi    t1, t1, 0x1ff 
	andi    t1, t1, 0x3ff 
	slli.w  t1, t1, 2     
	add.w	t0, t0, t1
	and	t0, t0, ra

        // uty: test
        // clear bit[2]
	ori	t0, t0, 0x4
	xori	t0, t0, 0x4

	ld.w	t1, t0, 0
	srli.w  ra, t1, 0xc
        slli.w  ra, ra, 0x8
        andi    t1, t1, 0xff
        add.w   t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO0


	ld.w	t1, t0, 0x4
	srli.w  ra, t1, 0xc
        slli.w  ra, ra, 0x8
        andi    t1, t1, 0xff
        add.w   t1, t1, ra
	csrwr	t1, LOONGARCH_CSR_TLBELO1

    # Output TLBELO0[31:28], [27:24], ..., [3:0]
    TLBELO0_OUT_HEX_NIBBLE 28
    TLBELO0_OUT_HEX_NIBBLE 24
    TLBELO0_OUT_HEX_NIBBLE 20
    TLBELO0_OUT_HEX_NIBBLE 16
    TLBELO0_OUT_HEX_NIBBLE 12
    TLBELO0_OUT_HEX_NIBBLE 8
    TLBELO0_OUT_HEX_NIBBLE 4
    TLBELO0_OUT_HEX_NIBBLE 0

    # Output TLBELO1[31:28], [27:24], ..., [3:0]
    TLBELO1_OUT_HEX_NIBBLE 28
    TLBELO1_OUT_HEX_NIBBLE 24
    TLBELO1_OUT_HEX_NIBBLE 20
    TLBELO1_OUT_HEX_NIBBLE 16
    TLBELO1_OUT_HEX_NIBBLE 12
    TLBELO1_OUT_HEX_NIBBLE 8
    TLBELO1_OUT_HEX_NIBBLE 4
    TLBELO1_OUT_HEX_NIBBLE 0

    # Output TLBIDX[31:28], [27:24], ..., [3:0]
    TLBIDX_OUT_HEX_NIBBLE 28
    TLBIDX_OUT_HEX_NIBBLE 24
    TLBIDX_OUT_HEX_NIBBLE 20
    TLBIDX_OUT_HEX_NIBBLE 16
    TLBIDX_OUT_HEX_NIBBLE 12
    TLBIDX_OUT_HEX_NIBBLE 8
    TLBIDX_OUT_HEX_NIBBLE 4
    TLBIDX_OUT_HEX_NIBBLE 0

	# uty: test
	#csrrd   t1, LOONGARCH_CSR_BADV
	#srli.w  t1, t1, 13
	#slli.w  t1, t1, 13
	#csrwr   t1, LOONGARCH_CSR_TLBEHI

	tlbfill

        # ---- 串口输出字符 'r' ----
        li.w    t0, 0x20000           # 串口物理地址
        li.w    t1, 0x72
        st.b    t1, t0, 0
	li.w    t0, 0xa0020004           # 串口状态寄存器
1:
        ld.w    t1, t0, 0                # 读状态
        bnez    t1, 1b                   # 非 0 则继续等待

    # Output KS0[31:28], [27:24], ..., [3:0]
    KS0_OUT_HEX_NIBBLE 28
    KS0_OUT_HEX_NIBBLE 24
    KS0_OUT_HEX_NIBBLE 20
    KS0_OUT_HEX_NIBBLE 16
    KS0_OUT_HEX_NIBBLE 12
    KS0_OUT_HEX_NIBBLE 8
    KS0_OUT_HEX_NIBBLE 4
    KS0_OUT_HEX_NIBBLE 0

	csrrd	t0, LOONGARCH_CSR_KS0
	csrrd   t1, LOONGARCH_CSR_KS1
	csrrd   ra, EXCEPTION_KS2

//	RESTORE_ALL_AND_RET
	ertn
SYM_FUNC_END(handle_tlb_refill)
