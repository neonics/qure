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

.data16	# realmode access, keep within 64k
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

.text32

# in: ax: interrupt number (at current: al, as the IDT only has 256 ints)
#     cx: segment selector
#     ebx: offset
hook_isr:
	pushf
	cli
	push	eax
	push	ebx
	and	eax, 0xff

	.if DEBUG > 1
		push	edx
		mov	edx, eax
		I	"Hook INT "
		call	printhex2
		pop	edx
		I2	" @ "
	.endif

	shl	eax, 3
	add	eax, offset IDT

	.if DEBUG > 1
		push	edx
		mov	dx, cx
		call	printhex
		PRINT	":"
		mov	edx, eax
		call	printhex8
		call	newline
		pop	edx
	.endif
	
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
# Faults: correctable; CS:EIP point to faulting instruction
# Trap: CS:EIP points to next instruction
# Abort: no restart/continuation - severe errors.
int_labels$:					# int  Fault/Trp/Abrt/Int Errcde
STRINGPTR "Division by zero"			# 0x00 F
STRINGPTR "Debugger"				# 0x01 F/T
STRINGPTR "NMI"					# 0x02 I
STRINGPTR "Breakpoint"				# 0x03 T
STRINGPTR "Overflow"				# 0x04 T
STRINGPTR "Bounds"				# 0x05 F
STRINGPTR "Invalid Opcode"			# 0x06 F
STRINGPTR "Coprocessor not available"		# 0x07 F
STRINGPTR "Double fault"			# 0x08 A E
STRINGPTR "Coprocessor Segment Overrun" 	# 0x09 F (386 or earlier only)
STRINGPTR "Invalid Task State Segment"		# 0x0a F E
STRINGPTR "Segment not present"			# 0x0b F E
STRINGPTR "Stack Fault"				# 0x0c F E
STRINGPTR "General protection fault"		# 0x0d F E
STRINGPTR "Page fault"				# 0x0e F E
STRINGPTR "reserved"				# 0x0f F
STRINGPTR "Math Fault"				# 0x10 F
STRINGPTR "Alignment Check"			# 0x11 F E
STRINGPTR "Machine Check"			# 0x12 A
STRINGPTR "SIMD Floating-Point Exception"	# 0x13 F
.text32


# Stack:
#
# dd [ EFLAGS ] esp + 14
# dd [   CS   ] esp + 10
# dd [  EIP   ] esp +  6
#(dd [ErrCode ] esp +  2 ) only when exception (intnr < 0x20)
# dw [ intnr  ] esp 	   the interrupt number as pushed by the jump table.
jmp_table_target:
	.data SECTION_DATA_BSS
		int_count: .rept 256; .long 0; .endr
	.text32
	push	ebp		# [ebp -  4] (after add ebp,4)
	mov	ebp, esp
	add	ebp, 4		# skip ebp itself
	push	eax		# [ebp -  8]
	push	ecx		# [ebp - 12]
	push	ds		# [ebp - 16]
	push	es		# [ebp - 20]
	push	edi		# [ebp - 24]
	push	esi		# [ebp - 28]
	push	ebx		# [ebp - 32]
	push	edx		# [ebp - 36]
	mov	edi, ebp	# used for [ebp + x] refs

	# if there is errorcode:
	SR_INT	= ebp
	#SR_ERR	= ebp + 2
	SR_EIP	= edi + 0
	SR_CS	= edi + 4
	SR_FLAGS= edi + 8

	SR_EBP	= ebp -  4
	SR_EAX	= ebp -  8
	SR_ECX	= ebp - 12
	SR_DS	= ebp - 16
	SR_ES	= ebp - 20
	SR_EDI	= ebp - 24
	SR_ESI	= ebp - 28
	SR_EBX	= ebp - 32
	SR_EDX	= ebp - 36

	mov	eax, SEL_compatDS
	mov	ds, ax

	PUSHCOLOR 8
	PRINT "(ISR "
	movzx	edx, word ptr [SR_INT]	# interrupt number from jumptable
	call	printhex2		# assume maxint = 255

	mov	ecx, edx		# int nr
	add	edi, 2			# we're done with referencing that

	# print count
	inc	dword ptr [edx*4 + int_count]
	mov	edx, [edx*4 + int_count]
	PRINT " count "
	call	printdec32
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

	COLOR 11
	mov	esi, [int_labels$ + ecx*4]
	call	print
	COLOR 8

	##################################################################
	# Handle error code.

	# check whether this exception has an error code
	mov	edx, 0b00100111110100000000
	bt	edx, ecx
	jnc	1f

.if 1	# Check to see whether this exception was called by an INT instruction.
	# If so, there is no error code on the stack.
	mov	edx, ss:[SR_CS]	# code selector when there is no error code
	cmp	edx, SEL_MAX
	ja	2f
	test	dl, 0b100
	jnz	2f
	verr	dx
	jnz	2f
	# the value checks out as a segment selector.
	# See if the instruction is an INT call
	push	ds
	and	dl, 0b11111000	# CPL0 access
	mov	ds, dx
	mov	edx, ss:[SR_EIP]	# EIP when no error code
	mov	dx, [edx-2]
	pop	ds
	cmp	dl, 0xcd	# INT instruction opcode
	jne	2f
	cmp	dh, cl		# interrupt number
	jne	2f
	PRINTc	13, " Explicitly triggered"
	jmp	1f
2:	# not caused by 'INT' instruction
.endif

	PRINT " Error code: "
	mov	edx, ss:[edi]
	call	printhex8
	call	printspace

	# Error code formats:
	# 8: double fault: error code always 0

	cmp	cl, 14	# Page fault
	jz	4f
	# 14 page fault: 
	# bit 0: 0=triggered because page present; 1=not because page present
	# bit 1: 0=cause is read, 1 = cause = write
	# bit 2: 0=was ring 0; 1= was ring 3
	# bit 4: 0=not during instruction fetch; 1=during instruction fetch
	# cause address in CR2.


	#######################
	# exception 10, 11, 12, 13: 
	# bit 0: external event (0=internal)
	# bit 1: 0=description location (0=GDT/LDT); 1=gate descriptor in IDT
	# bit 2: GDT/LDT: (only if bit 1=0): 0=curr GDT, 1=LDT
	# bit 3:15: segment selector index
	# bit 31:16: reserved
	LOAD_TXT "Intrn"
	test	dl, 1
	jz	3f
	LOAD_TXT "Extrn"
3:	call	print
	call	printspace
	LOAD_TXT "IDT"
	test	dl, 2
	jnz	3f
	# its GDT/LDT
	LOAD_TXT "GDT"
	test	dl, 4
	jz	3f
	LOAD_TXT "LDT"
3:	call	print
	call	printspace
	and	dl, 0b11111000
	call	printhex8
	#######################

4:
	#
	add	edi, 4		# skip over error code: point to EIP:CS:EFLAGS
	# End handle error code
1:	###################################################################
	# ss:[edi] now points to EIP,CS,EFLAGS

	PRINT " Flags: "
	mov	edx, ss:[SR_FLAGS]
	call	printhex8

	call	newline

0:	COLOR 8
########

	# check code selector validity

	mov	edx, ss:[edi + 4] # cs
	cmp	dx, SEL_MAX		# max selector
	ja	ics$
	test	dl, 0b100
	jnz	0f
	verr	dx
	jnz	ics$

	PRINTc	7, "RPL"
	mov	eax, edx
	and	dl, 3
	push	eax
	mov	ah, dl
	add	ah, 9
	COLOR	ah
	call	printhex1
	COLOR	8
	pop	eax
	mov	dl, al
	and	dl, 0b11111000

	PRINTc	7, " Address: "
	call	printhex

	PRINTCHAR ':'
	mov	edx, ss:[edi]	# eip
	call	printhex8
	PRINTc	7, " ("
	push	edx
	sub	edx, [realsegflat]
	call	printhex8
	pop	edx
	PRINTc	7, ") "
	
	# check if edx within limit:
	GDT_GET_LIMIT ebx, eax
	cmp	edx, ebx
	jb	1f
	PRINTc 12, "IP beyond limit"
	jmp	0f
1: 
	
	# print the opcode: 4 bytes before, 4 bytes after cs:eip
	PRINTc	9, "OPCODE["
	push	fs
	mov	fs, ax
	mov	ebx, edx
	mov	edx, fs:[ebx-4]	# check instruction XXX
	.rept 3
	call	printhex2
	shr	edx, 8
	call	printspace
	.endr
	call	printhex2
	call	printspace
	mov	edx, fs:[ebx]	# check instruction XXX
	.rept 3
	call	printhex2
	shr	edx, 8
	PRINTCHAR ' '
	.endr
	call	printhex2

	mov	dx, fs:[ebx - 2] # location of INT instruction
	pop	fs
	PRINTCHARc 9, ']'

	cmp	dl, 0xcd	# check for INT opcode
	jne	0f

	PRINTc	10, " INT "
	mov	dl, dh
	call	printhex2
	PRINTCHAR ' '

	jmp	0f

ics$:	PRINTc	11, "Cannot find cause: Illegal code selector: "
	call	printhex
0:	

##############################


	COLOR 8
	PRINTCHAR ')'
.if 1
	#############################
	call	newline

	printc_ 7, "cs:eip="
	mov	edx, ss:[edi + 4]
	call	printhex4
	printcharc 7, ':'
	mov	edx, ss:[edi + 0]
	call	printhex8

	printc_ 7, " ds="
	mov	edx, [SR_DS] #[ebp - 16]
	call	printhex4
	printc_ 7, " es="
	mov	edx, [SR_ES] #[ebp - 20]
	call	printhex4
	call	newline

	printc_ 7, "eax="
	mov	edx, [SR_EAX]
	call	printhex8

	printc_ 7, " ebx="
	mov	edx, [SR_EBX]
	call	printhex8

	printc_ 7, " ecx="
	mov	edx, [SR_ECX]
	call	printhex8

	printc_ 7, " edx="
	mov	edx, [SR_EDX]
	call	printhex8
	call	newline

	printc_ 7, "esi="
	mov	edx, [SR_ESI]
	call	printhex8

	printc_ 7, " edi="
	mov	edx, [SR_EDI]
	call	printhex8

	printc_ 7, " ebp="
	mov	edx, [SR_EBP]
	call	printhex8

	printc_ 7, " esp="
	lea	edx, [edi + 8]
	call	printhex8

	call	newline

	# print stack

	printc 11, " STACK: "
	mov	dx, ss
	call	printhex4
	printcharc 10 ':'
	mov	edx, edi
	call	printhex8
	call	newline

	push	ebp
	push	ecx
	mov	ebp, edi

.if 0	# print part of ISR local stack
sub ebp, 12
.rept 3
color 12
mov edx, ebp
call printhex8
printc 8, ": "
mov edx, [ebp]
color 7
call printhex8
add	ebp, 4
call printspace
.endr
call newline
.endif

	mov	edx, ebp
	color	12
	call	printhex8
	printc	8, ": "
	mov	edx, [ebp]
	color	7
	call	printhex8
	printlnc 9, " eip"
	add	ebp, 4

	mov	edx, ebp
	color	12
	call	printhex8
	printc	8, ": "
	mov	edx, [ebp]
	color	7
	call	printhex8
	printlnc 9, " cs"
	add	ebp, 4

	mov	edx, ebp
	color	12
	call	printhex8
	printc	8, ": "
	mov	edx, [ebp]
	color	7
	call	printhex8
	printlnc 9, " flags"
	add	ebp, 4

	mov	ecx, 10 # 16
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
	mov	ax, cx # [ebp + 4]
	sub	ax, dx		# assume [pic_ivt_offset] continuous
	js	0f
	cmp	ax, 0x10
	jae	0f
	shr	ax, 3
	mov	al, 0x20
	jz	1f
	out	IO_PIC2 + 1, al
1:	out	IO_PIC1 + 1, al
	color 0x4f
	PRINT	" IRQ "
	sub	dx, cx
	neg	dx
	call	printhex2
0:

	POPCOLOR
	call	newline

	pop	edx
	pop	ebx
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

	mov	eax, [reloc$]#[realsegflat]
	add	eax, offset IDT
	mov	[pm_idtr + 2], eax
	lidt	[pm_idtr]

	popf	# leave IF (cli/sti) as it was
	ret

