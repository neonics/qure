.data
.align 4
# in the syntax below, the second word of '.word 0,0' is always reserved,
# as the entry is a 32 bit aligned 16 bit value.
TSS: # in the syntax below, the second word of '.word 0,0' is always reserved
tss_LINK:	.word 0, 0
tss_ESP0:	.long 0
tss_SS0:	.word 0, 0
tss_SS1:	.word 0, 0
tss_SS2:	.word 0, 0
tss_CR3:	.long 0
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

.text
.code16
init_tss_16:
	mov	[tss_IOBP], word ptr 104

	mov	[tss_SS0], word ptr SEL_compatDS
	mov	eax, [realsegflat]
	mov	[tss_ESP0], eax

	mov	[tss_EIP], dword ptr offset kernel_task
	# using dwords for sel to clear second word just in case..
	mov	[tss_CS], dword ptr SEL_compatCS
	mov	[tss_ES], dword ptr SEL_vid_txt
	mov	[tss_DS], dword ptr SEL_compatDS
	ret

.code32

task_switch:
	push	dword ptr [tss_EFLAGS]
	push	dword ptr [tss_CS]
	push	dword ptr [tss_EIP]
	iretd

kernel_task:
	mov	ah, 0xf0
	SCREEN_INIT
	SCREEN_OFFS 0, 3
	PRINT "Kernel Task!"
0:	hlt
	jmp	0b
	ret
