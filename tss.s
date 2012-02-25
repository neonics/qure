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
tss_IOPB:	.word 0 # io bitmask base pointer, 104 + ...
