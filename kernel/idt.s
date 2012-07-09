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


.data	# not data 2 due to large sizes of data 0 and 1 > 64k for realmode
.align 4

pm_idtr:.word . - IDT - 1
	.long IDT

# Real Mode IDT (IVT)
rm_idtr:.word 256 * 4
	.long 0



IDT:
.rept 256
#.space 8
DEFIDT 0, SEL_flatCS, ACC_PR+ACC_RING0+ACC_SYS+IDT_ACC_GATE_INT32
.endr
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

.data SECTION_DATA_STRINGS
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

.data

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



# Stack:
#
# dd [ EFLAGS ] ebp + 18
# dd [   CS   ] ebp + 14
# dd [  EIP   ] ebp + 10 
#(dd [ErrCode ] ebp + 6	) only when exception (intnr < 0x20)
# dw [ intnr  ] ebp + 4	  the interrupt number as pushed by the jump table.
jmp_table_target:
	.data SECTION_DATA_BSS
		int_count: .rept 256; .long 0; .endr
	.text
	push	ebp
	mov	ebp, esp
	add	ebp, 4	# skip ebp itself
	push	eax
	push	ecx
	push	ds	# [ebp - 14]
	push	es	# [ebp - 16]
	push	edi
	push	esi
	push	edx
	push	ebp	# ebp will be modifed, use for reference of stack regs

	mov	eax, SEL_compatDS
	mov	ds, ax

	PUSHCOLOR 8

	PRINT "(ISR "
	movzx	edx, word ptr [ebp]	# interrupt number from jumptable
	call	printhex2		# assume maxint = 255

	mov	ecx, edx			# int nr
	add	ebp, 2			# we're done with referencing that

	# print count
	inc	dword ptr [edx*4 + int_count]
	mov	edx, [edx*4 + int_count]
	PRINT " count "
	call	printhex8
	PRINTCHAR ' '

########
	# First determine if it is an exception, since it may push an error
	# code on the stack.

	cmp	cx, 0x20
	jnb	0f

	##################################################################
	# it is an exception. Print exception name.
	call	newline
	PRINTc	12, "Exception: "

	push	esi
	PUSHCOLOR 11
	mov	esi, [int_labels$ + ecx*4]
	call	print
	POPCOLOR
	pop	esi

	# check whether this exception has an error code
	mov	edx, 0b100111110100000000
	bt	edx, ecx
	jnc	1f

.if 1	# Extra check to see whether this exception was called by an INT
	# instruction. If so, there is no error code.
	mov	edx, [ebp + 4] # code selector when there is no error code
	cmp	edx, SEL_MAX
	ja	2f
	test	dl, 0b100
	jnz	2f
	# the value checks out as a segment selector. See if the instruction
	# is an INT call
	push	ds
	and	dl, 0b11111000
	mov	ds, dx
	mov	edx, [ebp]
	mov	dx, [edx-2]
	pop	ds
	cmp	dl, 0xcd
	jne	2f
	cmp	dh, cl
	jne	2f
	PRINTc	13, " Explicitly triggered"
	jmp	1f
2:
.endif

	PRINT " Error code: "
	mov	edx, [ebp]
	call	printhex8
	add	ebp, 4			# adjust to point to EIP:CS:EFLAGS
1:
	PRINT " Flags: "
	mov	edx, [ebp + 8]
	call	printhex8

	call	newline

0:	COLOR 8

	# check code selector validity

	mov	dx, [ebp + 4]		# cs
	verr	ax
	jnz	ics$
	cmp	dx, SEL_MAX		# max selector
	ja	ics$
	test	dl, 0b100
	jnz	0f

	PRINTc	7, "RPL"
	mov	ax, dx
	and	dl, 3
	push	ax
	mov	ah, dl
	add	ah, 9
	PUSHCOLOR ah
	call	printhex1
	POPCOLOR
	pop	ax
	mov	dl, al
	and	dl, 0b11111000

	PRINTc	7, " Address: "
	call	printhex

	PRINTCHAR ':'
	mov	edx, [ebp]	# eip
	call	printhex8
	PRINTc	7, " ("
	push	edx
	sub	edx, [realsegflat] #offset realmode_kernel_entry
	call	printhex8
	pop	edx
	PRINTc	7, ") "
	
	push	ds
	mov	ds, ax
	mov	edx, [edx-4]	# check instruction XXX
	call	printhex
	pop	ds
	
	PRINTc	9, " OPCODE["
	.rept 3
	call	printhex2
	shr	edx, 8
	PRINTCHAR ' '
	.endr
	call	printhex2
	PRINTCHARc 9, ']'

	cmp	dl, 0xcd	# check for INT opcode
	jne	0f

	COLOR 10
	PRINT "INT "
	call	printhex2
	PRINTCHAR ' '

	jmp	1f

ics$:	COLOR 11
	PRINT "Cannot find cause: Illegal code selector: "
	call	printhex
0:	

########

##############################


	COLOR 8
	PRINT	")"
.if 1
	#############################
	push	ebp
	mov	ebp, [esp + 4]
	call	newline
	printc_ 7, "cs="
	mov	edx, [ebp + 14]
	call	printhex4
	printc_ 7, " eip="
	mov	edx, [ebp + 10]
	call	printhex8

	printc_ 7, " ds="
	mov	edx, [ebp - 14]
	call	printhex4
	printc_ 7, " es="
	mov	edx, [ebp - 16]
	call	printhex4
	pop	ebp

	printc 11, "STACK: "
	printc 10, "esp="
	mov	edx, esp
	call	printhex8
	call	newline
	push	ebp
	push	ecx
	mov	ecx, 10
0:	mov	edx, ebp
	color	12
	call	printhex8
	printc	8, ": "
	mov	edx, [ebp]
	color	7
	call	printhex8
	call	newline
	add	ebp, 4
	loop	0b
	pop	ecx
	pop	ebp
	#############################
.endif
	cmp	cx, 0x20 #PF
	jb	halt


### A 'just-in-case' handler for PIC IRQs, hardcoded to 0x20 offset
	movzx	dx, byte ptr [pic_ivt_offset]
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

	POPCOLOR
	call	newline

	pop	ebp
	pop	edx
	pop	esi
	pop	edi
	pop	es
	pop	ds
	pop	ecx
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

