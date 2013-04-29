.data16 # realmode access, keep within 64k
.align 4
# in the syntax below, the second word of '.word 0,0' is always reserved,
# as the entry is a 32 bit aligned 16 bit value.
TSS: # in the syntax below, the second word of '.word 0,0' is always reserved
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

.data16
TSS2:
tss2_LINK:	.word 0, 0
tss2_ESP0:	.long 0
tss2_SS0:	.word 0, 0
tss2_ESP1:	.long 0
tss2_SS1:	.word 0, 0
tss2_ESP2:	.long 0
tss2_SS2:	.word 0, 0
tss2_CR3:	.long 0
tss2_EIP:	.long 0
tss2_EFLAGS:	.long 0
tss2_EAX:	.long 0
tss2_ECX:	.long 0
tss2_EDX:	.long 0
tss2_EBX:	.long 0
tss2_ESP:	.long 0
tss2_EBP:	.long 0
tss2_ESI:	.long 0
tss2_EDI:	.long 0
tss2_ES:	.word 0, 0
tss2_CS:	.word 0, 0
tss2_SS:	.word 0, 0
tss2_DS:	.word 0, 0
tss2_FS:	.word 0, 0
tss2_GS:	.word 0, 0
tss2_LDTR:	.word 0, 0
		.word 0 # low word at offset 64 is reserved (bit0=T), hi=IOBP offset
tss2_IOBP:	.word 0 # io bitmask base pointer, 104 + ...



.text16
init_tss_16:
	mov	[tss_IOBP], word ptr 104
	mov	[tss2_IOBP], word ptr 104

	# mov	[tss_LDTR], sgtd?

	push	eax

	mov	eax, cr3
	mov	[tss_CR3], eax
	mov	[tss2_CR3], eax

	pushfd
	pop	dword ptr [tss_EFLAGS]
	pushfd
	pop	dword ptr [tss2_EFLAGS]

	mov	[tss_SS0], word ptr SEL_compatDS
	mov	[tss2_SS0], word ptr SEL_compatDS
	mov	eax, [kernel_tss0_stack_top]	# setup by init_gdt_16
	mov	[tss_ESP0], eax
	sub	eax, 0x0200
	mov	[tss2_ESP0], eax

	# TODO: setup tss_(SS|ESP)[12]

	mov	[tss_EIP], dword ptr offset kernel_task
	mov	[tss2_EIP], dword ptr offset kernel_task
	# using dwords for sel to clear second word just in case..
	mov	[tss_CS], dword ptr SEL_compatCS
	mov	[tss2_CS], dword ptr SEL_compatCS
	mov	[tss_ES], dword ptr SEL_vid_txt
	mov	[tss2_ES], dword ptr SEL_vid_txt
	mov	[tss_DS], dword ptr SEL_compatDS
	mov	[tss2_DS], dword ptr SEL_compatDS

	pop	eax
	ret

.text32

task_switch:
.if 0
	call SEL_tss, 0
	ret
.else
#mov [tss_LINK], word ptr SEL_tss
PRINTLN "<<<<<<<<<<<<<<<<<<<<<< TASK_SWITCH >>>>>>>>>>>>>>>>>>>>>>"
	push	dword ptr [tss_EFLAGS]
	#or	[esp], word ptr 1 << 14 # set NT flag
	push	dword ptr [tss_CS]
	push	dword ptr [tss_EIP]
	iretd
	ret
.endif
