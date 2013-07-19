.struct 0
# in the syntax below, the second word of '.word 0,0' is always reserved,
# as the entry is a 32 bit aligned 16 bit value.
tss_LINK:	.word 0, 0	# previous TSS when EFLAGS.NT, set automatically
tss_ESP0:	.long 0		# static stack pointers for 3 privilege levels
tss_SS0:	.word 0, 0
tss_ESP1:	.long 0
tss_SS1:	.word 0, 0
tss_ESP2:	.long 0
tss_SS2:	.word 0, 0
tss_CR3:	.long 0		# paging
tss_EIP:	.long 0
tss_EFLAGS:	.long 0
tss_EAX:	.long 0
tss_ECX:	.long 0
tss_EDX:	.long 0
tss_EBX:	.long 0
tss_ESP:	.long 0
tss_EBP:	.long 0
tss_ESI:	.long 0
tss_EDI:	.long 0
tss_ES:		.word 0, 0
tss_CS:		.word 0, 0
tss_SS:		.word 0, 0
tss_DS:		.word 0, 0
tss_FS:		.word 0, 0
tss_GS:		.word 0, 0
tss_LDTR:	.word 0, 0
		.word 0 # low word at offset 64 is reserved, hi=IOBP offset
tss_IOBP:	.word 0 # io bitmask base pointer, 104 + ...
TSS_STRUCT_SIZE = .

.data16 # realmode access, keep within 64k
.align 4
TSS:	.space TSS_STRUCT_SIZE
TSS_DF:	.space TSS_STRUCT_SIZE	# TSS for Double Fault handler
TSS_PF:	.space TSS_STRUCT_SIZE	# TSS for Page Fault handler
TSS_NP:	.space TSS_STRUCT_SIZE	# TSS for Segment Not Present handler
NUM_TSS = (. - TSS) / TSS_STRUCT_SIZE

.text16
# in: ebx = GDT_compatDS.base
init_tss_16:
	push_	eax ecx edx esi edi

	pushfd
	pop	eax
	mov	edi, cr3
	mov	edx, [kernel_tss0_stack_top]	# setup by init_gdt_16
	mov	cx, NUM_TSS
	mov	si, offset TSS

0:	mov	[si + tss_IOBP], word ptr 108
	mov	[si + tss_CR3], edi
	mov	[si + tss_EFLAGS], eax
	#mov	[tss0_LDTR], sgtd?
	mov	[si + tss_SS0], word ptr SEL_compatDS
	mov	[si + tss_SS], word ptr SEL_compatDS
	mov	[si + tss_ESP0], edx
	mov	[si + tss_ESP], edx
	sub	edx, 0x0200
	# TODO: setup tss0_(SS|ESP)[12]
	mov	[si + tss_EIP], dword ptr offset default_task # default
	mov	[si + tss_CS], dword ptr SEL_compatCS
	mov	[si + tss_ES], dword ptr SEL_vid_txt
	mov	[si + tss_DS], dword ptr SEL_compatDS
	mov	[si + tss_ECX], dword ptr 0

	add	si, TSS_STRUCT_SIZE
	loop	0b

	mov	[kernel_sysenter_stack], edx

	pop_	edi esi edx ecx eax
	ret

.text32

default_task:
	printlnc 0xf0, "Unconfigured Task Switch"
	0:hlt;jmp 0b

	DEBUG_DWORD cs
	DEBUG_DWORD ds
	DEBUG_DWORD es
	DEBUG_DWORD ss
	DEBUG_DWORD ecx
	call	newline

	xor	edx, edx
	str	dx
	call	print_tss

0:	hlt
	jmp 0b


# in: dx = tss selector
print_tss:
	push_	edx eax
	movzx	edx, dx
0:	DEBUG_WORD dx, "TSS"
	GDT_GET_FLAGS al, edx
	DEBUG_BYTE al, "F"
	GDT_GET_ACCESS al, edx
	DEBUG_BYTE al, "A"


	GDT_GET_BASE eax, edx
	GDT_GET_BASE edx, ds
	sub	eax, edx
	DEBUG_DWORD [eax + tss_ESP], "esp"
	DEBUG_DWORD [eax + tss_ESP0], "esp0"
	DEBUG_DWORD [eax + tss_CS], "cs"
	DEBUG_DWORD [eax + tss_EIP], "eip"
	DEBUG_WORD [eax + tss_LINK], "LINK"
	call	newline
	mov	edx, [eax + tss_EIP]
	call	debug_printsymbol
	call	newline
	mov	edx, [eax + tss_LINK]
	or	edx, edx
	jnz	0b
	pop_	eax edx
	ret
