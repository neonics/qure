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
.intel_syntax noprefix
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
	mov	edx, eax
	I	"Hook INT "
	call	printhex2
	pop	edx
	I2	" @ "

	shl	eax, 3
	add	eax, offset IDT
	push	edx
	mov	dx, cx
	call	printhex
	PRINT	":"
	mov	edx, eax
	call	printhex8
	call	newline
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

#################################################

isr_jump_table:

	INT_NR = 0
	.rept 256
		push	word ptr INT_NR
		jmp	jmp_table_target
		.if INT_NR == 0
			JMP_ENTRY_LEN = . - isr_jump_table
		.endif
		INT_NR = INT_NR + 1
	.endr

.data 
msg_int_00$: 	.asciz "Division by zero"
msg_int_01$: 	.asciz "Debugger"
msg_int_02$: 	.asciz "NMI"
msg_int_03$: 	.asciz "Breakpoint"
msg_int_04$: 	.asciz "Overflow"
msg_int_05$: 	.asciz "Bounds"
msg_int_06$: 	.asciz "Invalid Opcode"
msg_int_07$: 	.asciz "Coprocessor not available"
msg_int_08$: 	.asciz "Double fault"
msg_int_09$: 	.asciz "Coprocessor Segment Overrun (386 or earlier only)"
msg_int_0A$: 	.asciz "Invalid Task State Segment"
msg_int_0B$: 	.asciz "Segment not present"
msg_int_0C$: 	.asciz "Stack Fault"
msg_int_0D$: 	.asciz "General protection fault"
msg_int_0E$: 	.asciz "Page fault"
msg_int_0F$: 	.asciz "reserved"
msg_int_10$: 	.asciz "Math Fault"
msg_int_11$: 	.asciz "Alignment Check"
msg_int_12$: 	.asciz "Machine Check"
msg_int_13$: 	.asciz "SIMD Floating-Point Exception"

int_labels$:
	.long msg_int_00$
	.long msg_int_01$
	.long msg_int_02$
	.long msg_int_03$
	.long msg_int_04$
	.long msg_int_05$
	.long msg_int_06$
	.long msg_int_07$
	.long msg_int_08$
	.long msg_int_09$
	.long msg_int_0A$
	.long msg_int_0B$
	.long msg_int_0C$
	.long msg_int_0D$
	.long msg_int_0E$
	.long msg_int_0F$
	.long msg_int_10$
	.long msg_int_11$
	.long msg_int_12$
	.long msg_int_13$


.text


jmp_table_target:
	.data
		int_count: .rept 256; .long 0; .endr
	.text
	push	ebp
	mov	ebp, esp
	push	eax
	push	ds
	push	edi
	push	edx

	mov	ax, SEL_compatDS
	mov	ds, ax

	PUSHCOLOR 8
	PRINT "(ISR "
	movzx	edx, word ptr [ebp+4]
	call	printhex2
	shl	edx, 2
	inc	dword ptr [edx + int_count]
	mov	edx, [edx + int_count]
	PRINT " count "
	call	printhex8


########
	# read instruction to see if it is INT x
	mov	ax, [ebp + 4 + 2 + 4]	# code selector
	push	ds
	mov	ds, ax
	mov	edx, [ebp + 4 + 2]	# get return address
	mov	edx, [edx - 2]	# load instruction (assume sel=readable) 
	pop	ds

	COLOR 9
	PRINT " ["
	call	printhex
	PRINT "]"

	COLOR 10
	cmp	dl, 0xcd	# check for INT opcode
	mov	dl, [pic_ivt_offset] # assume all 16 are contiguous
	je	0f
	PRINT "IRQ "
	sub	dh, dl
	xchg	dl, dh
	call	printhex2

	jmp	1f

0:	PRINT " INT "
	mov	dl, dh
	call	printhex2

1:
########

##############################
# well, having this here should make no difference.. but it crashes
	or al, al
##############################

.if 0
	#ja	0f
	#0:

	.if 0
	xor	eax, eax
	mov	al, dl
	push	esi
	#mov	esi, [int_labels$ + eax*4]
	mov	edx, int_labels$
	call	printhex8
	mov	edx, eax
	call	printhex8
	#call	print
	pop	esi
	.endif
.endif


	COLOR 8
	PRINT	")"


	POPCOLOR

### A 'just-in-case' handler for PIC IRQs, hardcoded to 0x20 offset
	# dh = [pic_ivt_offset]
	shr	dx, 8
	mov	ax, [ebp + 4]
	sub	ax, dx		# assume [pic_ivt_offset] continuous
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

	pop	edx
	pop	edi
	pop	ds
	pop	eax
	pop	ebp
	add	esp, 2	# pop interrupt number
	iret

###################################################################

init_idt: # assume ds = SEL_compatDS/realmodeDS
	pushf
	cli

	mov	ecx, 256
	mov	esi, offset IDT

	mov	eax, offset isr_jump_table

0:	mov	[esi], ax
	mov	[esi + 2], word ptr SEL_compatCS
	mov	[esi + 4], word ptr (ACC_PR + IDT_ACC_GATE_INT32 ) << 8
	ror	eax, 16
	mov	[esi + 6], ax
	ror	eax, 16
	add	esi, 8
	add	eax, JMP_ENTRY_LEN
	loop	0b

	mov	eax, [realsegflat]
	add	eax, offset IDT
	mov	[pm_idtr + 2], eax
	lidt	[pm_idtr]

	popf	# leave IF (cli/sti) as it was
	ret

