###############################################################################
# Kernel API 
.intel_syntax noprefix
.data SECTION_DATA_KAPI_IDX
kapi_idx:
.data SECTION_DATA_KAPI_PTR
kapi_ptr:
.data SECTION_DATA_KAPI_STR
kapi_str:
.text32


KAPI_PAGE	= (0xffc00000>>12) + 1023
KAPI_BASE	= 4096 * KAPI_PAGE

_KAPI_COUNTER = 0


.macro KAPI_DECLARE name
	_PTR = .	# get .text offset
	.data SECTION_DATA_KAPI_STR
	999: .asciz "\name"
	.data SECTION_DATA_KAPI_IDX
	.long 999b
	.data SECTION_DATA_KAPI_PTR
	.long	_PTR

	KAPI_\name = _KAPI_COUNTER
	.print "Declare Kernel API: \name"
	_KAPI_COUNTER = _KAPI_COUNTER + 1
	.text32
.endm


cmd_kapi:
	KAPI_NUM_METHODS = ( offset data_kapi_idx_end - offset kapi_idx ) / 4
	mov	ecx, KAPI_NUM_METHODS
	mov	edx, ecx
	print "Kernel Api Methods: "
	call	printdec32
	call	newline

	mov	esi, offset kapi_idx
	xor	ebx, ebx
0:	mov	edx, ebx	# _KAPI_COUNTER
	call	printhex8
	call	printspace

	mov	edx, [esi + 4 * KAPI_NUM_METHODS]
	call	printhex8
	call	printspace
	lodsd
	pushd	eax
	call	_s_print

	call	printspace

	mov	edx, eax
	call	printhex8
	call	newline
	inc	ebx
	loop	0b
	ret

kapi_init:
	# ensure the KAPI_BASE page 4mb range has a page table
	mov	esi, [page_directory]
	mov	eax, [esi + 4*(KAPI_BASE >> 22)]
	DEBUG_DWORD eax, "PDE"
	or	eax, eax
	jnz	1f

	#call	malloc_page_phys
	mov	esi, cr3
	call	paging_alloc_page_idmap
	jc	9f
	#call	paging_idmap_page_pt_alloc	# make the page table accessible
	#jc	9f
	or	eax, PDE_FLAG_RW | PDE_FLAG_P
	mov	esi, [page_directory]
	mov	[esi + 4*(KAPI_BASE>>22)], eax
	and	eax, 0xfffff000
1:
	DEBUG_DWORD eax, "page table"

	mov	eax, KAPI_BASE
	GDT_SET_BASE SEL_kapi, eax

	# update page fault handler:
	mov	dword ptr [TSS_PF + tss_EIP], offset kapi_pf
	ret
9:	printlnc 4, "kapi init error"
	int 3
	ret

kapi_pf:
	print "KAPI - Page Fault"
	DEBUG_WORD cs
	mov ebp, esp
	DEBUG_DWORD ebp
	DEBUG_DWORD [ebp]
	mov	edx, cr2
	DEBUG_DWORD edx, "cr2"
	pushfd
	pop	edx
	DEBUG_DWORD edx, "eflags"
	mov	ebp, esp
	call	newline
#	DEBUG "local stack"
#	DEBUG_DWORD [ebp], "eip"
#	DEBUG_DWORD [ebp+4], "cs"
#	DEBUG_DWORD [ebp+8], "eflags"
#	DEBUG_DWORD [ebp+12], "esp"
#	DEBUG_DWORD [ebp+16], "ss"
#	call	newline

	GDT_GET_BASE ebx, ds

	xor	edx, edx
	str	dx
	GDT_GET_BASE eax, edx
	sub	eax, ebx
#	DEBUG "local TSS"
#	DEBUG_DWORD [eax + tss_ESP0]
#	DEBUG_DWORD [eax + tss_ESP]
#	call	newline
	mov	edx, [eax + tss_LINK]
	GDT_GET_BASE eax, edx
	sub	eax, ebx

	DEBUG "linked TSS"
	DEBUG_WORD dx, "link"
	DEBUG_DWORD [eax + tss_CS]
	DEBUG_DWORD [eax + tss_EIP]
	DEBUG_DWORD [eax + tss_EFLAGS]
	DEBUG_DWORD [eax + tss_ESP]
	call	newline

	DEBUG "linked stack"
	mov	ebp, [eax + tss_ESP]
	DEBUG_DWORD ebp
	DEBUG_DWORD [ebp], "eip"
	DEBUG_DWORD [ebp+4], "cs"
#	DEBUG_DWORD [ebp+8], "eflags"
#	DEBUG_DWORD [ebp+12], "esp"
#	DEBUG_DWORD [ebp+16], "ss"
	call	newline

	# check the instruction
	#mov	edx, [eax + tss_EIP]
	#mov	edx, [edx]
	#DEBUG_DWORD edx,"opcode"

	# alter the linked tss stack - we're not actually going to execute
	# code in SEL_kapi.
	# the below will effectively 'nop' the call
	mov	edx, [ebp]
	mov	[eax + tss_EIP], edx
	mov	edx, [ebp + 4]
	mov	[eax + tss_CS], edx
	add	dword ptr [eax + tss_ESP], 8	# far call

	mov	edx, cr2
	mov	ebx, edx
	and	edx, 0xfffff000
	cmp	edx, 0xfffff000
	jnz	1f
	print "KAPI call!"
	and	ebx, 0xfff
	DEBUG_DWORD ebx
	mov	esi, [kapi_idx + ebx * 4]
	call	print
	call	printspace
	mov	edx, [kapi_ptr + ebx * 4]
	call	printhex8
	call	debug_printsymbol
	call	newline

1:

#	or	dword ptr [eax+tss_EFLAGS], 1 << 16 # resume flag
	iret

cmd_kapi_test:
	.if 1
	call	SEL_kapi:1 #KAPI_BASE + 10
	.else
	push	fs
	mov	eax, SEL_flatDS
	mov	fs, eax
	mov	eax, KAPI_BASE + 10
	DEBUG_DWORD eax
	mov	eax, fs:[eax]
	DEBUG_DWORD eax
	pop	fs
	.endif
	ret
