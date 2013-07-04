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

KAPI_METHOD_PAGE_TASK = 0	# 1 to use task, 0 to use isr on caller TSS SS0

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


	################################

	# update page fault handler:
	.if KAPI_METHOD_PAGE_TASK
		mov	eax, offset kapi_pf_task
		xchg	eax, dword ptr [TSS_PF + tss_EIP]
		mov	[kapi_pf_next], eax

		# update the callgate selector:
		mov	eax, offset kapi_callgate
		mov	[GDT_kernelGate + 0], ax
		shr	eax, 16
		mov	[GDT_kernelGate + 6], ax
	.else
		mov	[IDT + EX_PF*8 + 2], word ptr SEL_compatCS
		mov	[IDT + EX_PF*8 + 4], word ptr (ACC_PR|ACC_RING0|IDT_ACC_GATE_INT32)<<8
		mov	eax, offset kapi_pf_isr
		mov	[IDT + EX_PF*8 + 0], ax
		shr	eax, 16
		mov	[IDT + EX_PF*8 + 6], ax
	.endif

	ret
9:	printlnc 4, "kapi init error"
	int 3
	ret

KAPI_PF_DEBUG = 0


.if KAPI_METHOD_PAGE_TASK

.data SECTION_DATA_BSS
kapi_pf_next:	.long 0	# original page fault handler; delegated to unless kapi
.text32

kapi_pf_task:
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
	jmp	kapi_pf_task

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
	pushd	offset 1f# kapi_pf_task
	jmp	dword ptr [kapi_pf_next]
1:	DEBUG "returned"
	iret
	jmp	kapi_pf_task

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

2:	
	.if KAPI_PROXY_DEBUG
		DEBUG "method called"
		push ebp; lea ebp,[esp+4];
		DEBUG_DWORD[ebp]
		DEBUG_DWORD[ebp+4]
		DEBUG_DWORD[ebp+8]
		DEBUG_DWORD[ebp+12]
		pop ebp
	.endif
	retf	8


.else	# KAPI_METHOD_PAGE_TASK: PAGE_ISR.


kapi_pf_isr:
	.if KAPI_PF_DEBUG
		DEBUG "kapi_pf_isr", 0xf0
		DEBUG_WORD cs
		DEBUG_WORD ss
		DEBUG_DWORD esp
	.endif
	sub	esp, 4	# add another space
	pushad
	lea	ebp, [esp + 32]
	mov	edx, cr2
	.if KAPI_PF_DEBUG
		DEBUG_DWORD edx,"cr2"
		call	newline
		DEBUG_DWORD [ebp+4], "error"
		DEBUG_DWORD [ebp+8], "eip"
		DEBUG_DWORD [ebp+12], "cs"
		DEBUG_DWORD [ebp+16], "eflags"
		DEBUG_DWORD [ebp+20], "esp"
		DEBUG_DWORD [ebp+24], "ss"
		call	newline
	.endif

	mov	ebx, edx
	and	edx, 0xfffff000
	cmp	edx, 0xfffff000
	jnz	1f

	and	ebx, 0xfff
	cmp	ebx, KAPI_NUM_METHODS
	jae	9f

	mov	edx, [kapi_ptr + ebx * 4]
	mov	ecx, [kapi_arg + ebx * 4]
	.if KAPI_PF_DEBUG 
		print "KAPI call!"
		DEBUG_DWORD ebx

		mov	esi, [kapi_idx + ebx * 4]
		call	print
		call	printspace
		DEBUG_DWORD ecx, "ARG",0x07
		call	printhex8
		call	debug_printsymbol
		call	newline
	.endif

# Stack possibilities: (ebp; below ebp is 32 bytes pushad)
# CPL0: [0][error][eip][cs][eflags]         [ret  ][cs ][stackargs]
# to:	          [eip][cs][eflags]         [catch]     [stackargs][ret][cs][cr3]
#
# CPL>0:[0][error][eip][cs][eflags][esp][ss]
#				ss:esp:	 [ret][cs][stackargs]
# to:             [eip][cs][eflags]         [catch][stackargs] [ret][cs][esp][ss]


	# in both cases, [eip][cs] will be updated with the method:
#	mov	[ebp + 8], edx

# IF stackargs
#     move stackargs], [cs]

	test	byte ptr [ebp + 12], 3	# test RPL
	jnz	2f
## privileged call
	.if KAPI_PF_DEBUG
		DEBUG "priv"
	.endif
	mov	[ebp], edx	# new eip
	mov	[ebp+4], cs	# new cs
	lea	edi, [ebp + 8]	# point to old [eip][cs][eflags][ret][cs][stackargs]
	lea	esi, [edi + 8]	# point to [eflags][ret][cs][stackargs]
	movsd			# [eip][cs][eflags] edi [cs][eflags][ret][cs][stackargs]
				# esi: [ret][cs][stackargs]
	lodsd	# ret eip
	mov	edx, eax
	lodsd	# ret cs
	# edx = [ret]
	# eax = [cs]
	# esi: [stackargs]
	mov	[edi], dword ptr offset kapi_catch
	add	edi, 4
	mov	ebx, ecx
	rep	movsd
	mov	ecx, ebx
#jecxz 110f; 0: lodsd; DEBUG_DWORD eax; stosd; loop 0b; 110:
	.if KAPI_PF_DEBUG
		call newline
		DEBUG_DWORD [ebp], "m" 
		DEBUG_DWORD [ebp+4], "cs" 
		DEBUG_DWORD [ebp+8], "eflags" 
		jecxz 10f
		DEBUG_DWORD [ebp+12], "0" 
		DEBUG_DWORD [ebp+16], "1" 
		DEBUG_DWORD [ebp+20], "2" 
		DEBUG_DWORD [ebp+24], "3" 
		10:
	.endif
	# [eip][cs][eflags][stackargs] edi [...]
	# esi: end of stackargs.
	# @ edi: 3 dwords free for [cr3][ret][cs]
	mov	[edi], edx
	mov	[edi+4], eax
	mov	eax, cr3
	mov	[edi + 8], eax
	mov	eax, [page_directory_phys]
	mov	cr3, eax
	# now, CPL0 stack is complete.
	popad
	.if KAPI_PF_DEBUG
		push	ebp
		call	newline
		lea	ebp,[esp+4]
		DEBUG_DWORD [ebp+0], "method"
		DEBUG_DWORD [ebp+4], "cs"
		DEBUG_DWORD [ebp+8], "eflags"
		DEBUG_DWORD [ebp+12], "catch"
		.if 1
		DEBUG_DWORD [ebp+16], "A0"
		DEBUG_DWORD [ebp+20], "A1"
		DEBUG_DWORD [ebp+24], "A2"
		DEBUG_DWORD [ebp+32], "A3"

		DEBUG_DWORD [ebp+36], "ret"
		DEBUG_DWORD [ebp+40], "cs"
		DEBUG_DWORD [ebp+44], "cr3"
		DEBUG_DWORD [ebp+48], "esp"
		DEBUG_DWORD [ebp+52], "ss"
		.else
		DEBUG_DWORD [ebp+16], "ret"
		DEBUG_DWORD [ebp+20], "cs"
		DEBUG_DWORD [ebp+24], "cr3"
		DEBUG_DWORD [ebp+28], "esp"
		DEBUG_DWORD [ebp+32], "ss"
		.endif
		pop	ebp
	.endif

	iret

kapi_catch:
	#DEBUG "kapi_catch"
	push	eax
	mov	eax, [esp + 4 + 8]
	mov	cr3, eax
	.if KAPI_PF_DEBUG
	lea eax, [esp + 4 + 12]
	DEBUG_DWORD eax
	DEBUG_DWORD[eax-12],"EIP"
	DEBUG_DWORD[eax- 8],"CS"
	DEBUG_DWORD[eax- 4],"CR3"
	DEBUG_DWORD[eax- 0],"ESP"
	DEBUG_DWORD[eax+ 4],"SS"
	.endif
	pop	eax
	
	retf 4	# also pops from other stack!


## unprivileged call
#
# CPL>0:[0][error][eip][cs][eflags][esp][ss]
#				ss:esp:	 [ret][cs][stackargs]
# to:             [eip][cs][eflags]         [catch][stackargs] [ret][cs][cr3][esp][ss]
2:	
	.if KAPI_PF_DEBUG
		DEBUG "unpriv"
		DEBUG_DWORD [ebp + 20],"esp"
	.endif
	mov	[ebp], edx
	shl	ecx, 2
	mov	[ebp + 4], ecx
	mov	ebp, [ebp + 20]	# user esp
	.if KAPI_PF_DEBUG
		DEBUG_DWORD [ebp+0],"U"
		DEBUG_DWORD [ebp+4],"U"
	.endif
	popad
	# esp: [meth][stacksize][eip]...
	mov	[esp + 8], ebp	# store ebp in old [eip]
	mov	ebp, esp
	.if KAPI_PF_DEBUG
		DEBUG_DWORD [ebp+0],"m"
		DEBUG_DWORD [ebp+4],"sz"
		DEBUG_DWORD [ebp+8],"ebp"
	.endif
# CPL>0: ebp:      [meth][argsize][ebp][cs][eflags][esp][ss]
	sub	esp, [esp+4]
# CPL>0:[argsppace][meth][argsize][ebp][cs][eflags][esp][ss]
# CPL>0:[meth][cs][eflags][catch][stackargs][ret][cs][cr3][esp][ss]
	pushad
	mov	eax, [ebp + 8]	# orig ebp
	mov	[esp + 8], eax	# overwrite ebp for popad
	mov	eax, [ebp]	# method
	lea	edi, [esp + 32]
	stosd
	mov	ecx, [edi]	# ebp+4 = stacksize
	mov	[edi], cs
	add	edi, 4
	# [meth][cs] done now.
	mov	eax, [ebp + 16]	# eflags
	stosd
	pushd	[ebp + 20]	# esp
	pushd	[ebp + 24]	# ss
	mov	[edi], dword ptr offset kapi_catch
	add	edi, 4
	# [meth][cs][eflags][catch]
	mov	esi, [ebp + 20]	# user esp (before mod)
	add	ecx, 4	# kapi_catch retf 4 pops both stacks
	add	[esp+4],ecx#[ebp + 20], ecx	# retf [stackargs]
	sub	ecx, 4
	shr	ecx, 2
	lodsd
	mov	edx, eax	# ret eip
	lodsd			# ret cs
	rep	movsd	# stackargs
	mov	[edi], edx
	mov	[edi + 4], eax
	mov	eax, cr3
	mov	[edi + 8], eax	# NOTE: not sure if space allocated!
		mov	eax, [page_directory_phys]
		mov	cr3, eax
	# user esp, ss:
	popd	[edi + 16]	# ss
	popd	[edi + 12]	# esp
	# stack should be ok now.
	popad

	.if KAPI_PF_DEBUG
		push	ebp
		call	newline
		lea	ebp,[esp+4]
		DEBUG_DWORD [ebp+0], "method"
		DEBUG_DWORD [ebp+4], "cs"
		DEBUG_DWORD [ebp+8], "eflags"
		DEBUG_DWORD [ebp+12], "catch"
		DEBUG_DWORD [ebp+16], "ret"
		DEBUG_DWORD [ebp+20], "cs"
		DEBUG_DWORD [ebp+24], "cr3"
		DEBUG_DWORD [ebp+28], "esp"
		DEBUG_DWORD [ebp+32], "ss"
		pop	ebp
	.endif
	iret

1:	printc 4, "page fault - not kapi call"
	popad
	add	esp, 4
	push	word ptr EX_PF
	jmp	jmp_table_target
9:	printc 4, "unknown KAPI method index: "
	mov	edx, ebx
	call	printhex8
	jmp	halt

.endif


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
