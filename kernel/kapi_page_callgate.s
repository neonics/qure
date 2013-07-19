kapi_init_page_callgate:
	mov	[IDT + EX_PF*8 + 2], word ptr SEL_compatCS
	mov	[IDT + EX_PF*8 + 4], word ptr (ACC_PR|ACC_RING0|IDT_ACC_GATE_INT32)<<8
	mov	eax, offset kapi_pf_isr
	mov	[IDT + EX_PF*8 + 0], ax
	shr	eax, 16
	mov	[IDT + EX_PF*8 + 6], ax

	.if 1
	mov	eax, offset kapi_ldt
	GDT_GET_BASE ebx, ds
	sub	eax, ebx
	GDT_SET_BASE	SEL_ldt, eax
	.else
	GDT_SET_BASE	SEL_ldt, (offset kapi_ldt-.text)
	.endif

	.if 0	# running this ensures #NP
	mov	esi, offset kapi_ldt
	mov	ecx, KAPI_NUM_METHODS
0:	and	[esi + 5], byte ptr ~ACC_PR
	add	esi, 8
	loop	0b
	.endif

	.if 1
	mov	eax, [GDT_kernelGate]
	mov	[kapi_ldt+8], eax
	mov	eax, [GDT_kernelGate+4]
	mov	[kapi_ldt+8+4], eax
	.endif

	#GDT_SET_LIMIT	SEL_ldt, (8 * KAPI_NUM)
	#(offset data_kapi_ldt_end - offset kapi_ldt)
	mov	eax, 8*KAPI_NUM_METHODS-1#(offset data_kapi_ldt_end - kapi_ldt)-1
	GDT_SET_LIMIT SEL_ldt, eax
	mov	eax, SEL_ldt
	DEBUG "loading SEL_ldt"
	lldt	ax
	# serialize
	push eax; xor eax,eax; cpuid; pop eax

	GDT_GET_BASE edx, eax
	DEBUG_DWORD edx, "base"
	GDT_GET_LIMIT edx, eax
	DEBUG_DWORD edx, "limit"

	DEBUG "Loading FS"
	mov	eax, 0x04
	GDT_GET_BASE edx, eax, kapi_ldt
	DEBUG_DWORD edx, "base"
	GDT_GET_LIMIT edx, eax, kapi_ldt
	DEBUG_DWORD edx, "limit"
	DEBUG_WORD fs
	mov	eax, 0x08+4
	mov	fs, ax
	DEBUG "ok"

call	newline
mov	eax, SEL_kernelGate
GDT_GET_BASE edx, eax
DEBUG_DWORD edx, "base"
GDT_GET_LIMIT edx, eax
DEBUG_DWORD edx, "limit"
GDT_GET_ACCESS dl,eax
DEBUG_BYTE dl,"A"
PRINTFLAG dl, ACC_NRM, "NRM", "SYS"
PRINTFLAG dl, ACC_CODE, "CODE", "DATA"
PRINTFLAG dl, ACC_PR, "PR", "NP"
push dx
PRINTBITSb dl, 5,2, "DPL"
pop dx
and	dl, 0xf
call	printbin4
GDT_GET_FLAGS dl,eax
DEBUG_BYTE dl,"F"


call	newline
	DEBUG "LDT1:"
	mov	eax, 0x8	# first etnry
	GDT_GET_BASE edx, eax, kapi_ldt
	DEBUG_DWORD edx, "base"
	GDT_GET_LIMIT edx, eax, kapi_ldt
	DEBUG_DWORD edx, "limit"
	GDT_GET_ACCESS dl,eax, kapi_ldt
	DEBUG_BYTE dl,"A"
	PRINTFLAG dl, ACC_NRM, "NRM", "SYS"
	PRINTFLAG dl, ACC_CODE, "CODE", "DATA"
	PRINTFLAG dl, ACC_PR, "PR", "NP"
	push dx
	PRINTBITSb dl, 5,2, "DPL"
	pop dx
	and	dl, 0xf
	call	printbin4
	GDT_GET_FLAGS dl,eax, kapi_ldt
	DEBUG_BYTE dl,"F"
DEBUG "Calling"
	#call	SEL_kernelGate: 0
	call 0x0f:0
	DEBUG "Halting"
	jmp halt



KAPI_PF_DEBUG=1
kapi_pf_isr:
	.if KAPI_PF_DEBUG
		DEBUG "kapi_pf_isr callgate", 0xf0
		DEBUG_WORD cs
		DEBUG_WORD ss
		DEBUG_DWORD esp
	.endif
	pushad
	lea	ebp, [esp + 32]
	mov	edx, cr2
	.if KAPI_PF_DEBUG
		DEBUG_DWORD edx,"cr2"
		#call	newline
		DEBUG_DWORD [ebp+0], "error"
		DEBUG_DWORD [ebp+4], "eip"
		DEBUG_DWORD [ebp+8], "cs"
		DEBUG_DWORD [ebp+12], "eflags"
		DEBUG_DWORD [ebp+16], "esp"
		DEBUG_DWORD [ebp+20], "ss"
		#call	newline
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
	lea	eax, [ebx * 8 + 0b100]
	# +0=error; +4=eip; +8=cs
	mov	[ebp + 8], eax	# set the selector to the call gate
	popad
	add	esp, 4	# pop errorcode
	push ebp; lea ebp, [esp + 4]
	_I=0; .rept 5; DEBUG_DWORD [ebp + 4*_I]; _I=_I+1;.endr
	pop ebp
	iret

9:	printc 4, "invalid KAPI call: unknown method: "
	mov	ebx, ebx
	call	printhex8
	
1:	DEBUG "not kapi"
	popad
	pushw	EX_PF
	jmp	jmp_table_target

.data SECTION_DATA_KAPI_LDT
.align 8
kapi_ldt:
DEFGDT 0, 0xffff, ACCESS_DATA, FLAGS_32
DEFCALLGATE SEL_compatCS, (kernel_callgate_3-.text), 3, 0
.text32
1: DEBUG "first KAPI callgate thingy"; retf

