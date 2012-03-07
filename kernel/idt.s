#########################################################
# IDT: Interrupt Descriptor Table.
#
# The structure is the same as the GDT, except:
# - limit is the offset into a selector
# - base is 16 bits segment selector
# - access lower 4 bits determine gate type
# - in the GDT, the last word starts with the low nybble of the 3rd byte
#   of limit. In the IDT, the last word is the high word of the limit.
#
# ACC_PR: 0 means unused interrupt, or Paging.
# ACC_NRM(1), ACC_SYS(0): SYS for interrupt gates.
#
# The low nybble of the access byte desribes the gate type.
# For a TASK Gate, the entire context is switched using TSS.
# For an INT Gate, cli/sti is automatic; it isn't for a TRAP gate.
#
.equ IDT_ACC_GATE_TASK32, 0b0101 # TASK Gate. selector:offset = TSS:0.
.equ IDT_ACC_GATE_INT16,  0b0110
.equ IDT_ACC_GATE_TRAP16, 0b0111
.equ IDT_ACC_GATE_INT32,  0b1110 # 0xe
.equ IDT_ACC_GATE_TRAP32, 0b1111


.macro DEFIDT offset, selector, access
# DPL field of selector must be 0
.word (\offset) & 0xffff
.word \selector
.byte 0
.byte \access
.word (\offset) >> 16
.endm


.data
.align 4

IDT:
.rept 256
#.space 8
DEFIDT 0, SEL_flatCS, ACC_PR+ACC_RING0+ACC_SYS+IDT_ACC_GATE_INT32
.endr
pm_idtr:.word . - IDT - 1
	.long IDT

# Real Mode IDT (IVT)
rm_idtr:.word 256 * 4
	.long 0

.text
.code32

# in: ax: interrupt number (at current: al, as the IDT only has 256 ints)
#     cx: segment selector
#     ebx: offset
hook_isr:
	pushf
	cli
	push	eax
	push	ebx
	and	eax, 0xff

	push	edx
	push	ax
	mov	edx, eax
	mov	ah, 0xf1
	PRINT "Hook INT "
	call	printhex2
	pop	ax
	pop	edx

	shl	eax, 3
	add	eax, offset IDT
	push	edx
	mov	edx, eax
	push	ax
	mov	ah, 0xf1
	call	printhex8
	pop	ax
	pop	edx
	
	mov	[eax], bx
	mov	[eax+2], cx
	mov	[eax+4], word ptr (ACC_PR + IDT_ACC_GATE_INT32 ) << 8
	shr	ebx, 16
	mov	[eax+6], bx
	sti
	pop	ebx
	pop	eax
	popf
	ret
#########################


int_count: .long 0
gate_int32:	# cli/sti automatic due to IDT_GATE_INT32
	push	ebp
	mov	ebp, esp
	push	eax
	push	esi
	push	es
	push	ds
	push	edi
	push	edx

	SCREEN_INIT

	mov	ax, 0xf2<<8 + '!'
	stosw

	mov	ax, SEL_compatDS
	mov	ds, ax

	mov	ah, 0xf2

	mov	edx, [int_count]
	call	printhex8
	inc	dword ptr [int_count]
	add	edi, 2

	# read instruction to see if it is INT x
	mov	ax, [ebp + 6]	# code selector
	mov	ds, ax
	mov	edx, [ebp + 4]	# get return address
	mov	edx, [edx - 2]	# load instruction (assume sel=readable) 

	mov	ah, 0xf3
	call	printhex8
	add	edi, 2

	cmp	dl, 0xcd	# check for INT opcode
	LOAD_TXT "Not called by INT instruction!"
	jne	0f

	PRINT "INT "
	mov	dl, dh
	call	printhex2

	jmp	1f
0:	mov	ah, 0xf4
	call	print
1:
	pop	edx
	pop	edi
	pop	ds
	pop	es
	pop	esi
	pop	eax
	pop	ebp
	iret

########################

.data
int_count0: .rept 256; .long 0; .endr
scr_offs32: .long 0
.text
int_jmp_table:

	INT_NR = 0
	.rept 256
		push	word ptr INT_NR
		jmp	jmp_table_target

		.if INT_NR == 0
			JMP_ENTRY_LEN = . - int_jmp_table
		.endif
		INT_NR = INT_NR + 1
	.endr


jmp_table_target:
	push	ebp
	mov	ebp, esp
	push	eax
	push	es
	push	ds
	push	edi
	push	edx
	push	ecx

	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	ax, SEL_vid_txt
	mov	es, ax
	mov	edi, [scr_offs32]

	mov	ax, [ebp + 4]
	mov	edx, eax
	mov	ah, 0xf4
	PRINT "INT "
	call	printhex
	add	edi, 2

	inc	dword ptr [int_count0]
	mov	edx, [int_count0]
	call	printhex
	add	edi, 2
########
	.if 1 
	# read instruction to see if it is INT x
	mov	ax, [ebp + 4 + 2 + 4]	# code selector
	push	ds
	mov	ds, ax
	mov	edx, [ebp + 4 + 2]	# get return address
	mov	edx, [edx - 2]	# load instruction (assume sel=readable) 
	pop	ds

	mov	ah, 0xf3
	call	printhex8
	add	edi, 2

	cmp	dl, 0xcd	# check for INT opcode
	LOAD_TXT "Not called by INT instruction!"
	jne	0f

	PRINT "INT "
	mov	dl, dh
	call	printhex2

	jmp	1f
0:	mov	ah, 0xf4
	call	print
1:

	.endif
########

#	mov	dl, 6
#	div	dl
#	mov	dx, ax
#	call	printhex


### A 'just-in-case' handler for PIC IRQs, hardcoded to 0x20 offset
	mov	ax, [ebp + 4]
	sub	ax, 0x20
	js	0f
	cmp	ax, 0x10
	jae	0f
	shr	ax, 3
	mov	al, 0x20
	jz	1f
	out	IO_PIC2 + 1, al
1:	out	IO_PIC1 + 1, al
	mov	ah, 0x4f
	PRINT " IRQ "
0:


	mov	ah, 0x73

	xor	al, al		# read channel 0 (bits 6,7 = channel)
	out	0x43, al	# PIT port

	in	al, 0x40
	mov	dl, al
	in	al, 0x40
	mov	dh, al
	call	printhex8


	add	edi, 4
	mov	[scr_offs32], edi

	pop	ecx
	pop	edx
	pop	edi
	pop	ds
	pop	es
	pop	eax
	pop	ebp
	add	esp, 2
	iret


init_idt: # assume ds = SEL_compatDS/realmodeDS
	pushf
	cli

	mov	ecx, 256
	mov	esi, offset IDT

JMP_TABLE = 1

	.if JMP_TABLE
	mov	eax, offset int_jmp_table
	.else
	mov	eax, offset gate_int32 # int_jmp_table
	.endif

0:	mov	[esi], ax
	mov	[esi + 2], word ptr SEL_compatCS
	mov	[esi + 4], word ptr (ACC_PR + IDT_ACC_GATE_INT32 ) << 8
	ror	eax, 16
	mov	[esi + 6], ax
	ror	eax, 16
	add	esi, 8
	.if JMP_TABLE
	add	eax, JMP_ENTRY_LEN
	.endif
	loop	0b

	mov	eax, [realsegflat]
	add	eax, offset IDT
	mov	[pm_idtr + 2], eax
	lidt	[pm_idtr]

	popf	# leave IF (cli/sti) as it was
	ret



######################################
# PIT - Programmable Interrupt Timer 
######################################

isr_timer: 
	push	es
	push	ds
	push	ax
	push	edi
	push	dx
	SCREEN_INIT
	mov	di, SEL_compatCS
	mov	ds, di
	mov	edi, [scr_offs32]
	mov	ax, 0xf0
	PRINT "TIMER "
	inc	word ptr [int_count]
	mov	dx, [int_count]
	call	printhex2
	pop	dx
	pop	edi
	mov	al, 0x20
	out	0x20, al
	pop	ax
	pop	ds
	pop	es
	iret

