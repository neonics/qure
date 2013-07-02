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

KAPI_NUM_METHODS = ( offset data_kapi_idx_end - offset kapi_idx ) / 4

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

.macro KAPI_CALL name
	call	SEL_kapi:KAPI_\name
.endm

kapi_init: #ret
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
#	and	[GDT_kapi + 5], byte ptr ~ACC_PR	# mark not present
#	or	[GDT_kapi + 5], byte ptr ACC_PR	# mark not present
	#mov eax, 1
	#GDT_SET_LIMIT SEL_kapi, eax

	# update page fault handler:
	mov	eax, offset kapi_pf
	xchg	eax, dword ptr [TSS_PF + tss_EIP]
	mov	[kapi_pf_next], eax
	ret
9:	printlnc 4, "kapi init error"
	int 3
	ret

.data SECTION_DATA_BSS
kapi_pf_next:	.long 0	# original page fault handler; delegated to unless kapi
.text32

KAPI_PF_DEBUG = 0

kapi_pf:
	.if KAPI_PF_DEBUG
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
		call	newline
	#	DEBUG "local stack"
	#	DEBUG_DWORD [ebp], "eip"
	#	DEBUG_DWORD [ebp+4], "cs"
	#	DEBUG_DWORD [ebp+8], "eflags"
	#	DEBUG_DWORD [ebp+12], "esp"
	#	DEBUG_DWORD [ebp+16], "ss"
	#	call	newline
	.endif

	GDT_GET_BASE ebx, ds

	xor	edx, edx
	str	dx

	.if KAPI_PF_DEBUG
		DEBUG_WORD dx,"TR"
	.endif

	GDT_GET_BASE eax, edx
	sub	eax, ebx
	mov	edx, [eax + tss_LINK]
	GDT_GET_BASE eax, edx
	sub	eax, ebx
	mov	edi, eax

	.if KAPI_PF_DEBUG
		DEBUG "linked TSS"
		DEBUG_WORD dx, "link"
		DEBUG_DWORD [edi + tss_CS]
		DEBUG_DWORD [edi + tss_EIP]
		DEBUG_DWORD [edi + tss_EFLAGS]
		DEBUG_DWORD [edi + tss_ESP]
		DEBUG_DWORD [edi + tss_EAX]
		call	newline
	.endif

	mov	ebp, [edi + tss_ESP]
	.if KAPI_PF_DEBUG
		DEBUG "linked stack"

		DEBUG_DWORD ebp
		DEBUG_DWORD [ebp], "eip"
		DEBUG_DWORD [ebp+4], "cs"
	#	DEBUG_DWORD [ebp+8], "eflags"
	#	DEBUG_DWORD [ebp+12], "esp"
	#	DEBUG_DWORD [ebp+16], "ss"

		# check the instruction
		#mov	edx, [edi + tss_EIP]
		#mov	edx, [edx]
		#DEBUG_DWORD edx,"opcode"
		call	newline
	.endif

	# alter the linked tss stack - we're not actually going to execute
	# code in SEL_kapi.
	# the below will effectively 'nop' the call
	mov	edx, [ebp]
	mov	[edi + tss_EIP], edx
	mov	edx, [ebp + 4]
	mov	[edi + tss_CS], edx
	add	dword ptr [edi + tss_ESP], 8	# far call

	mov	edx, cr2
	mov	ebx, edx
	and	edx, 0xfffff000
	cmp	edx, 0xfffff000
	jnz	1f

	and	ebx, 0xfff
	cmp	ebx, KAPI_NUM_METHODS
	jae	9f

	mov	edx, [kapi_ptr + ebx * 4]
	.if KAPI_PF_DEBUG 
		print "KAPI call!"
		DEBUG_DWORD ebx

		mov	esi, [kapi_idx + ebx * 4]
		call	print
		call	printspace
		call	printhex8
		call	debug_printsymbol
		call	newline
	.endif

	# now call the method.
	# we'll need to restore the registers:
	pushfd		# save our flags

	push	edx	# method address

	push	edi	# save the tss pointer
	mov	eax, [edi + tss_EAX]
	mov	ebx, [edi + tss_EBX]
	mov	ecx, [edi + tss_ECX]
	mov	edx, [edi + tss_EDX]
	mov	esi, [edi + tss_ESI]
	mov	ebp, [edi + tss_EBP]
	pushd	[edi + tss_EFLAGS]
	popfd
	mov	edi, [edi + tss_EDI]
	call	[esp+4]
	mov	[esp+4], edi	# overwrite method offs
	pop	edi		# tss ptr

	pushfd
	popd	[edi + tss_EFLAGS]
	mov	[edi + tss_EAX], eax
	mov	[edi + tss_EBX], ebx
	mov	[edi + tss_ECX], ecx
	mov	[edi + tss_EDX], edx
	mov	[edi + tss_ESI], esi
	mov	[edi + tss_EBP], ebp
	popd	[edi + tss_EDI]

	popfd		# restore our flags

0:	iret
	jmp	kapi_pf

9:	printc 4, "invalid KAPI call: no such method: "
	mov	edx, ebx
	call	printhex8
	call	newline
	jmp	0b

1:	# not kapi call
print "not KAPI call"
#0:hlt; jmp 0b
	pushfd
	and	[esp], dword ptr ~(1<<14)	# reset EFLAGS.NT
	pushd	cs
	pushd	offset 1f# kapi_pf
	jmp	dword ptr [kapi_pf_next]
1:	DEBUG "returned"
	iret
	jmp	kapi_pf

kapi_np:
	print "KAPI - Segment Not Present"
1:	DEBUG_WORD cs
	mov ebp, esp
	DEBUG_DWORD ebp
	DEBUG_DWORD [ebp]
	pushfd
	pop	edx
	DEBUG_DWORD edx, "eflags"
	call	newline
	DEBUG "local stack"
	mov	ebp, esp
	DEBUG_DWORD [ebp], "eip"
	DEBUG_DWORD [ebp+4], "cs"
	DEBUG_DWORD [ebp+8], "eflags"
	DEBUG_DWORD [ebp+12], "esp"
	DEBUG_DWORD [ebp+16], "ss"
	call	newline

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
	mov	edx, [GDT + edx * 8]
	GDT_GET_FLAGS bl, edx
	DEBUG_BYTE bl, "F"
	GDT_GET_ACCESS bl, edx
	DEBUG_BYTE bl, "A"
	
	DEBUG_DWORD [eax + tss_CS]
	DEBUG_DWORD [eax + tss_EIP]
	DEBUG_DWORD [eax + tss_EFLAGS]
	DEBUG_DWORD [eax + tss_ESP]
	DEBUG_DWORD [eax + tss_LINK]
	call	newline

	DEBUG "linked stack"
	mov	ebp, [eax + tss_ESP]
	DEBUG_DWORD ebp
	DEBUG_DWORD [ebp], "eip"
	DEBUG_DWORD [ebp+4], "cs"
	DEBUG_DWORD [ebp+8], "eflags"
	DEBUG_DWORD [ebp+12], "esp"
	DEBUG_DWORD [ebp+16], "ss"
	call	newline

1: hlt; jmp 1b;
#	or	dword ptr [eax+tss_EFLAGS], 1 << 16 # resume flag
	iret
	jmp	kapi_pf


cmd_kapi:
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

	mov	edx, [esi + 4 * KAPI_NUM_METHODS]	# read kapi_ptr
	call	printhex8
	call	printspace

	lodsd
	pushd	eax
	call	_s_println

	inc	ebx
	loop	0b
	ret


cmd_kapi_test:
	.if 1
	KAPI_CALL fs_openfile
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
