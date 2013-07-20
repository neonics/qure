kapi_init_page_int:
	mov	[IDT + EX_PF*8 + 2], word ptr SEL_compatCS
	mov	[IDT + EX_PF*8 + 4], word ptr (ACC_PR|ACC_RING0|IDT_ACC_GATE_INT32)<<8
	mov	[IDT + EX_PF*8 + 0], word ptr (offset kapi_pf_isr-.text)&0xffff
	mov	[IDT + EX_PF*8 + 6], word ptr ((offset kapi_pf_isr-.text)<<16)&0xffff
	ret


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
	push	eax
	mov	eax, [esp + 4 + 8]
	mov	cr3, eax
	.if KAPI_PF_DEBUG
	DEBUG "kapi_catch", 0xd0
	lea	eax, [esp + 4]
	DEBUG_DWORD eax
	DEBUG_DWORD[eax+ 0],"EIP"
	DEBUG_DWORD[eax+ 4],"CS"
	DEBUG_DWORD[eax+ 8],"CR3"
	DEBUG_DWORD[eax+12],"ESP"
	DEBUG_DWORD[eax+16],"SS"
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
		DEBUG_DWORD ecx,"#sa"
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
	sub	esp, 8
# CPL>0:[argsppace][meth][argsize][ebp][cs][eflags][esp][ss]
# CPL>0:[meth][cs][eflags][catch][stackargs][ret][cs][cr3][esp][ss]
	pushad
	mov	eax, [ebp + 8]	# orig ebp
	mov	[esp + 8], eax	# overwrite ebp for popad
	mov	eax, [ebp]	# method
	lea	edi, [esp + 32]
	stosd
	mov	ecx, [ebp + 4]#[edi]	# ebp+4 = stacksize
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
.if 0
DEBUG_DWORD ecx, "ARGS:"
jecxz 9999f
push eax
9990: lodsd; DEBUG_DWORD eax,"a"; stosd; loop 9990b
pop eax
9999: 
.else
	rep	movsd	# stackargs
.endif
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
		DEBUG_WORD cs, "CS", 0xe0
		DEBUG_DWORD ebp, "EBP",0xe0
		DEBUG_DWORD [ebp+0], "method"
		DEBUG_DWORD [ebp+4], "cs" #ok
		DEBUG_DWORD [ebp+8], "eflags"
		DEBUG_DWORD [ebp+12], "catch"
		# stack args here
# we don't have the nr of stackargs available on the stack anymore:
# little hack - schedule_task is the only stackarg method so far.
cmp [ebp+0], dword ptr offset schedule_task
jnz 9999f
DEBUG_DWORD [ebp+16], "A0"; add ebp, 4
DEBUG_DWORD [ebp+16], "A1"; add ebp, 4
DEBUG_DWORD [ebp+16], "A2"; add ebp, 4
DEBUG_DWORD [ebp+16], "A3"; add ebp, 4
9999:
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


