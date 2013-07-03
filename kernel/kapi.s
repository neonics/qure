###############################################################################
# Kernel API 
.intel_syntax noprefix
.data SECTION_DATA_KAPI_IDX
kapi_idx:
.data SECTION_DATA_KAPI_PTR
kapi_ptr:
.data SECTION_DATA_KAPI_STR
kapi_str:
.data SECTION_DATA_KAPI_ARG
kapi_arg:
.text32

KAPI_NUM_METHODS = ( offset data_kapi_idx_end - offset kapi_idx ) / 4

KAPI_PAGE	= (0xffc00000>>12) + 1023
KAPI_BASE	= 4096 * KAPI_PAGE

_KAPI_COUNTER = 0


.macro KAPI_DECLARE name, stackargs=0
	_PTR = .	# get .text offset
	.data SECTION_DATA_KAPI_STR
	999: .asciz "\name"
	.data SECTION_DATA_KAPI_IDX
	.long 999b
	.data SECTION_DATA_KAPI_PTR
	.long	_PTR
	.data SECTION_DATA_KAPI_ARG
	.long	\stackargs

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

	# update the callgate selector:
	mov	eax, offset kapi_callgate
	mov	[GDT_kernelGate + 0], ax
	shr	eax, 16
	mov	[GDT_kernelGate + 6], ax

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
		GDT_GET_ACCESS al, edx
		DEBUG_BYTE al, "A"
		GDT_GET_FLAGS al, edx
		DEBUG_BYTE al, "F"
		DEBUG_DWORD [edi + tss_CS],"CS"
		DEBUG_DWORD [edi + tss_EIP],"EIP"
		DEBUG_DWORD [edi + tss_EFLAGS],"EFLAGS"
		DEBUG_DWORD [edi + tss_SS],"SS"
		DEBUG_DWORD [edi + tss_ESP],"ESP"
		DEBUG_DWORD [edi + tss_SS0],"SS0"
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

	# TODO: check the acess (error code 0)

	# check the address

	mov	edx, cr2
	mov	ebx, edx
	and	edx, 0xfffff000
	cmp	edx, 0xfffff000
	jnz	1f

	and	ebx, 0xfff
	cmp	ebx, KAPI_NUM_METHODS
	jae	9f



	# alter the linked tss stack - we're not actually going to execute
	# code in SEL_kapi.
	# the below will effectively 'nop' the call
	mov	edx, [kapi_ptr + ebx * 4]
	.if KAPI_PF_DEBUG 
		print "KAPI call!"
		DEBUG_DWORD ebx

		mov	esi, [kapi_idx + ebx * 4]
		call	print
		call	printspace
		mov	ecx, [kapi_arg + ebx * 4]
		DEBUG_DWORD ecx, "ARG",0x07
		call	printhex8
		call	debug_printsymbol
		call	newline
	.endif
	# the called method may block, thereby keeping the TSS busy, causing
	# a #DF on the next call. This could be handled there, but it is best
	# to let the call continue in the interrupted TSS, which is already
	# set up with the task SS0 (but is not using it yet because this handler
	# is declared as a TASK using it's own TSS.).

	# ebp = linked tss stack
	# edx = KAPI method
	
	mov	eax, [ebp+4]	# get task cs

	mov	[edi + tss_CS], eax	# replace SEL_kapi with original cs

	cmp	eax, SEL_compatCS	# check if the call was made from kernel mode
	jnz	2f
	# it's a kernel mode call
	.if KAPI_PF_DEBUG
		DEBUG "kernel->kernel"
	.endif

	# we adjust the stack to make it a near call
	mov	ebx, [ebp]
	mov	[ebp + 4], ebx
	add	[edi + tss_ESP], dword ptr 4
	# now we set the continuation address:
	mov	[edi + tss_EIP], edx	# the method
	jmp	3f	# and done.

2:	# it's a call from unprivileged code. This means that we must first switch
	# back to the original task to execute the call in it's TSS context,
	# and then use a callgate to enter kernel mode to call the method.
	mov	[edi + tss_EIP], dword ptr offset kapi_proxy
	# put the api method and stackargs count on the stack
	sub	dword ptr [edi + tss_ESP], 8
	mov	ebp, [edi + tss_ESP]
	mov	[ebp + 4], edx
	mov	[ebp + 0], ecx
	# the kapi_proxy will take care of calling the callgate.

3:
	.if KAPI_PF_DEBUG
		call	newline
		DEBUG_DWORD edx
		DEBUG_DWORD [ebp]
		DEBUG_DWORD [ebp+4]
		DEBUG_DWORD [ebp+8]
		DEBUG_DWORD [edi+tss_CS]
		DEBUG_DWORD [edi+tss_EIP]
		DEBUG_DWORD [edi+tss_ESP]
	.endif


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


KAPI_PROXY_DEBUG = 0

# runs unprivileged in original task
# in: [esp + 0] = stackarg count
# in: [esp + 4] = method pointer
# in: [esp + 8] = return eip
# in: [esp +12] = return cs
kapi_proxy:
	.if KAPI_PF_DEBUG
		DEBUG "kapi_proxy"
		DEBUG_WORD cs
		DEBUG_WORD ss
		DEBUG_DWORD esp
		push ebp
		lea ebp, [esp+4]
		DEBUG_DWORD [ebp]
		DEBUG_DWORD [ebp+4]
		DEBUG_DWORD [ebp+8]
		DEBUG_DWORD [ebp+12]
		pop ebp
	.endif

	call	SEL_kernelGate:0	# call kapi_callgate
	# the callgate takes care of popping the 2 stackargs
	# from this stack aswell.

	.if KAPI_PROXY_DEBUG
		DEBUG "KMETHOD return"
		DEBUG_DWORD cs
		DEBUG_DWORD ss
		DEBUG_DWORD esp
		push	ebp;lea ebp,[esp+4]
		DEBUG_DWORD [ebp+0]
		DEBUG_DWORD [ebp+4]
		DEBUG_DWORD [ebp+8]
		DEBUG_DWORD [ebp+12]
		pop	ebp
	.endif
	retf

# built to accept 2 stackargs (8 bytes)
# (GDT descriptor: GDT_kernelGate)
kapi_callgate:

	.if KAPI_PROXY_DEBUG
		DEBUG "kapi_callgate", 0xb0
		DEBUG_DWORD esp
		push ebp; lea ebp,[esp+4];
		DEBUG_DWORD[ebp],"cEIP"		# caller eip
		DEBUG_DWORD[ebp+4],"cCS"	# caller cs
		DEBUG_DWORD[ebp+8],"argc"	# nr of stackargs to copy
		DEBUG_DWORD[ebp+12],"meth"	# method to call
		DEBUG_DWORD[ebp+16],"cESP"	# caller esp
		DEBUG_DWORD[ebp+20],"cSS"	# caller ss
		pop ebp
	.endif

	cmp	dword ptr [esp + 8], 0
	jz	1f
	# it's a stackarg method.
	# it will expect esp to point to a near address followed by the args.
	# adjust the stack.
	push_	eax ebp
	lea	ebp, [esp + 8]		# remember orig stack ptr
	mov	eax, [ebp + 8]		# stackarg count
	shl	eax, 2
	sub	esp, eax

	push_	esi edi ecx
	mov	ecx, [ebp + 8]
	lea	edi, [esp + 12]
	mov	esi, [ebp + 16]		# get caller esp
	add	esi, 8			# skip far return
	rep	movsd
	pop_	ecx edi esi

	# esp:
	# [stackargs]
	# [eax ebp]
	# [c EIP CS] [argc method] [cESP cSS]
	
	pushd	offset 2f
	pushd	[ebp + 12]
	ret
2:	DEBUG "callgate stackargs called"
	mov	esp, ebp
	pop_	ebp eax
	jmp	2f

#########
1:	call	[esp + 12]

2:	.if KAPI_PROXY_DEBUG
		DEBUG "method called"
		push ebp; lea ebp,[esp+4];
		DEBUG_DWORD[ebp]
		DEBUG_DWORD[ebp+4]
		DEBUG_DWORD[ebp+8]
		DEBUG_DWORD[ebp+12]
		pop ebp
	.endif
	retf	8




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
