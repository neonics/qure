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
	push	eax
	push	ebx
	and	eax, 0xff
	shl	eax, 4
	add	eax, offset IDT
	cli
	mov	[eax], bx
	mov	[eax+2], cx
	mov	[eax+4], word ptr (ACC_CODE + ACC_PR) << 8
	shr	ebx, 16
	mov	[eax+6], bx
	sti
	pop	ebx
	pop	eax
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
	call	printhex8_32
	inc	dword ptr [int_count]
	add	edi, 2

	# read instruction to see if it is INT x
	mov	ax, [ebp + 6]	# code selector
	mov	ds, ax
	mov	edx, [ebp + 4]	# get return address
	mov	edx, [edx - 2]	# load instruction (assume sel=readable) 

	mov	ax, SEL_compatDS
	mov	ds, ax

	mov	ah, 0xf3
	call	printhex8_32
	add	edi, 2

	cmp	dl, 0xcd	# check for INT opcode
	LOAD_TXT "Not called by INT instruction!"
	jne	0f

	PRINT_32 "INT "
	mov	dl, dh
	call	printhex2_32


	jmp	1f
0:	mov	ah, 0xf4
	call	print_32
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

int_count0: .rept 256; .long 0; .endr
int_jmp_table:
.rept 256
	call	jmp_table_target
	iret
.endr
jmp_table_target:
	cli
	push	ebp
	mov	ebp, esp
	push	eax
	push	es
	push	ds
	push	edi
	push	edx

	SCREEN_INIT
	SCREEN_OFFS 0, 0
	mov	ax, SEL_compatDS
	mov	ds, ax

	mov	eax, [ebp + 4]
	sub	eax, offset int_jmp_table - 6
	mov	edx, eax
	mov	ah, 0xf4
	call	printhex_32
	add	edi, 2

	inc	dword ptr [int_count0]
	mov	edx, [int_count0]
	call	printhex_32

#	mov	dl, 6
#	div	dl
#	mov	dx, ax
#	call	printhex_32

	pop	edx
	pop	edi
	pop	ds
	pop	es
	pop	eax
	pop	ebp
	sti
	ret


init_idt: # assume ds = SEL_compatDS/realmodeDS
	cli
	mov	ecx, 256
	mov	esi, offset IDT

	.if 1
	mov	eax, offset gate_int32 # int_jmp_table
	.else
	mov	eax, offset int_jmp_table
	.endif

0:	mov	[esi], ax
	mov	[esi + 2], word ptr SEL_compatCS
	mov	[esi + 4], word ptr 0x8e00
	ror	eax, 16
	mov	[esi + 6], ax
	ror	eax, 16
	add	esi, 8
	loop	0b

	mov	eax, [realsegflat]
	add	eax, offset IDT
	mov	[pm_idtr + 2], eax
	lidt	[pm_idtr]
	sti
	ret

