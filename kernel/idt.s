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



IRQ_PROXIES = 1	# Experimental!
SCHEDULE_IRET = 1

.text32

# in: ax = interrupt number (at current: al, as the IDT only has 256 ints)
# in: cx = segment selector
# in: ebx = offset
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

.if IRQ_PROXIES
	push	eax
	push	edx

	.if 0 # if len = 9: pushf; lcall; iret
	mov	edx, eax
	shl	eax, 3
	add	eax, edx	# * 9
	.else # len = 15
	shl	eax, 4
	.endif

	mov	[irq_proxies + eax + 2], ebx
	mov	[irq_proxies + eax + 6], cx
	mov	cx, cs
	lea	ebx, [irq_proxies + eax]
	pop	edx
	pop	eax
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

.if IRQ_PROXIES
irq_proxies:
INT_NR = 0
.rept 256
	# size 16
	pushf
	lcall	SEL_compatCS, jmp_table_target + JMP_ENTRY_LEN * INT_NR	# 7
.if SCHEDULE_IRET
	jmp	schedule_isr	# needs to do iret! see schedule.s
	nop
.else
	call	schedule_near
	iret
.endif
	nop
	nop
INT_NR = INT_NR + 1
.endr
.endif

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


# NOTE! Do not proxy IRQ < 32 (exceptions) due to stack expectations of the
# below handler!
#
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
	mov	ds, eax
	mov	es, eax
	cld

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
	mov	dx, cx
	call	printhex2
	call	printspace

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
	jnz	4f
	# 14 page fault: 
	# bit 0: 0=triggered because page present; 1=not because page present
	# bit 1: 0=cause is read, 1 = cause = write
	# bit 2: 0=was ring 0; 1= was ring 3
	# bit 4: 0=not during instruction fetch; 1=during instruction fetch
	# cause address in CR2.

# bit 0: P (present) fault cause: 0 = page not present; 1=protection violation.
# bit 1: W/R: access causing fault: 0 = read, 1 = write
# bit 2: U/S: origin: 0=supervisor mode (CPL<3), 1=user mode (CPL=3)
# bit 3: RSVD: 0=not, 1=caused by reserved bit set to 1 in paging struct entry.
# bit 4: I/D: instruction/data: 0=not caused, 1=caused by instruction fetch.
# bits 31:5: reserved.


	PRINTFLAG dl, 1<<0, "PV ", "NP "
	PRINTFLAG dl, 1<<1, "W", "R"
	PRINTFLAG dl, 1<<2, "U", "S"
	PRINTFLAG dl, 1<<3, "R", " "
	PRINTFLAG dl, 1<<4, "C", "D"
	PRINT	" LinAddr: "
	mov	edx, cr2
	call	printhex8

	jmp	5f
4:
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

5:
	#
	add	edi, 4		# skip over error code: point to EIP:CS:EFLAGS
	# End handle error code
1:	###################################################################
	# ss:[edi] now points to EIP,CS,EFLAGS

	PRINT " Flags: "
	mov	edx, ss:[SR_FLAGS]
	call	printhex8
	call	printspace
	PRINTFLAG edx, 1 << 21, "ID "	# CPUID available (pentium+)
	PRINTFLAG edx, 1 << 20, "VIP "	# virtual interrupt pending (pentium+)
	PRINTFLAG edx, 1 << 19, "VIF "	# virtual interrupt flag (pentium+)
	PRINTFLAG edx, 1 << 18, "AC "	# alignment check (486SX+)
	PRINTFLAG edx, 1 << 17, "VM "	# virtual 8086 mode (386+)
	PRINTFLAG edx, 1 << 16, "RF "	# resume flag (386+)

	PRINTFLAG dx, 1 << 15, "XT "	# reserved: 1 for 8086/80186, 0 for above
	PRINTFLAG dx, 1 << 14, "NT "	# Nested task (1 for 8086/80186)
	printc	13, "IOPL "
	push	edx
	shr	edx, 12
	and	edx, 3
	call	printhex1
	pop	edx
	call	printspace

	.macro PRINTFLAGc_ reg, bit, char
		mov	al, \char
		test	\reg, \bit
		jnz	77f
		color	8
		or	al, 0x20	# lowercase
		jmp	78f
	77:	color	7
	78:	call	printchar
	.endm

	PRINTFLAGc_ dx, 1 << 11, 'O'	# overflow
	PRINTFLAGc_ dx, 1 << 10, 'D'	# direction
	PRINTFLAGc_ dx, 1 << 9, 'I'	# interrupt enable
	PRINTFLAGc_ dx, 1 << 8, 'T'	# trap (single step)
	PRINTFLAGc_ dx, 1 << 7, 'S'	# sign
	PRINTFLAGc_ dx, 1 << 6, 'Z'	# zero
	# reserved: 0
	PRINTFLAGc_ dx, 1 << 4, 'A'	# adjust
	# reserved: 0
	PRINTFLAGc_ dx, 1 << 2, 'P'	# parity
	# reserved: 1
	PRINTFLAGc_ dx, 1 << 0, 'C'	# carry

	call	printspace
	mov	edx, [scheduler_current_task_idx]
	add	edx, [task_queue]
	mov	edx, [edx + task_pid]
	printc 7, "task "
	call	printhex4
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
	PRINTc 12, "IP beyond limit: "
	push	ebx
	call	_s_printhex8
	jmp	0f
1: 
	# print the opcode: 4 bytes before, 4 bytes after cs:eip
	PRINTc	9, "OPCODE["
	push	fs
	mov	fs, ax
	mov	ebx, edx
	cmp	ebx, 4
	jb	2f
	mov	edx, fs:[ebx-4]	# check instruction XXX
	.rept 3
	call	printhex2
	shr	edx, 8
	call	printspace
	.endr
	call	printhex2
	call	printspace
2:	mov	edx, fs:[ebx]	# check instruction XXX
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

	call	debug_print_tss$

	call	debug_print_exception_registers$

#######
	mov	esi, edi	# remember original stack ptr
	mov	ebx, ss
	call	debug_print_stack$

	mov	edx, cs
	mov	dh, dl
	and	dh, 3
	mov	dl, ss:[edi + 4]	# cs
	and	dl, 3
	cmp	dl, dh
	jz	1f
	# privilege level changed: esp,ss on stack after eflags,
	# use this as the 'main' stack to print (for debugger scroll),
	# as the last printed stack's position on screen is remembered.
	mov	ebx, ss:[edi + 16]	# user ss
	mov	esi, ss:[edi + 12]	# user esp
	mov	edi, esi
	printc_ 11, "USER"
	call	debug_print_stack$
1:
#######

	or	cx, cx	# division by zero
	jz	2f
	cmp	cx, 0xd	# general protection fault
	jz	2f
	cmp	cx, 6	# invalid opcode
	jz	2f
	cmp	cx, 5	# bounds
	jz	2f
	cmp	cx, 0xa	# invalid TSS
	jz	2f
	cmp	cx, 0xe	# page fault
	jz	2f
	#############################
.endif
	cmp	cx, 1	# debugger
	jz	2f
	cmp	cx, 3	# manual breakpoint
	jz	2f

	cmp	cx, 0x20
	jb	halt

### A 'just-in-case' handler for PIC IRQs
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

2:	call	debugger
	jmp	0b


debug_print_tss$:
	printc 15, "TSS: "
	printc 7, "ESP0="
	mov	edx, [tss_ESP0]
	call	printhex8
	printc 7, " SS0="
	mov	edx, [tss_SS0]
	call	printhex4
	printc 7, " SS1="
	mov	edx, [tss_SS1]
	call	printhex4
	printc 7, " SS2="
	mov	edx, [tss_SS2]
	call	printhex4
	printc 7, " SS:ESP="
	mov	edx, [tss_SS]
	call	printhex4
	printchar_ ':'
	mov	edx, [tss_ESP]
	call	printhex8
	call	newline
.if 1
	printc 11, " ss:esp="
	mov	edx, ss
	call	printhex4
	printchar_ ':'
	mov	edx, esp
	call	printhex8

	printc 7, " TSS: cs="
	mov	edx, [tss_CS]
	call	printhex4

	printc	11, " cs:"
	mov	edx, cs
	call	printhex4
	call	newline
.endif
	ret


debug_print_exception_registers$:
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
	printc_ 7, " fs="
	mov	edx, fs
	call	printhex4
	printc_ 7, " gs="
	mov	edx, gs
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

	mov	edx, cs
	mov	dh, dl
	and	dh, 3
	mov	dl, ss:[edi + 4]
	and	dl, 3
	cmp	dl, dh
	jz	1f
	# privilege level changed: esp,ss on stack after eflags:

	printc_ 7, " ss:esp="
	movzx	edx, word ptr ss:[edi + 16]
	call	printhex8
	printchar_ ':'
	mov	edx, ss:[edi + 12]
	call	printhex8

1:	call	newline
	ret


# in: ebx = stack segment
# in: edi = stack pointer
# in: esi = original stack pointer (points to eip,cs,eflags)
# destroys: eax, edx
debug_print_stack$:
	.data SECTION_DATA_BSS
		stack_print_lines$:.long 0
		stack_print_pos$:.long 0
	.text32
	call	screen_get_scroll_lines
	mov	[stack_print_lines$], eax
	call	screen_get_pos
	mov	[stack_print_pos$], eax

	printc 11, " STACK: "
	mov	dx, bx
	call	printhex4
	printcharc 10 ':'
	mov	edx, edi
	call	printhex8
	printc 11, " EFLAGS: "
	pushfd
	pop	edx
	call	printhex8
	call	newline

	push	fs
	mov	fs, ebx
	push	ebp
	push	ecx
##
	xor	edx, edx
	mov	ecx, ss
	cmp	ebx, ecx
	jnz	1f	# printed stack != exception stack: flag is 0
	inc	edx	# flag 1 (or higher): printing exception stack
	# if privilege level change, ss:esp of ring3 is also on stack
	mov	ecx, cs
	and	cl, 3
	mov	ch, ss:[esi + 4]	# cs
	and	ch, 3
	cmp	cl, ch
	jz	1f	# same privilege
	inc	edx	# privilege level different: have ss:esp on stack
1:	push	edx	# 0=user stack;>0=excpt stack; 1=same priv, 2=diff priv
##

	mov	ebp, edi

	mov	ecx, 5#10 # 16
0:	mov	edx, ebp
	color	12
	call	printhex8
	printc	8, ": "
	mov	edx, fs:[ebp]
	color	7
	call	printhex8
	call	printspace

	cmp	byte ptr [esp], 0
	jz	3f	# user stack, skip exception stack interpretation

	# check if stack address points to eip,cs,eflags, and opt ss:esp
	push	edx
	push	esi
	mov	eax, esi
	mov	dl, 1
	sub	eax, ebp
	LOAD_TXT "eip \0cs \0eflags \0esp \0ss "
	jz	1f	# print "eip "
	inc	dl
	add	esi, 5	# skip "eip \0"
	add	eax, 4
	jz	1f	# print "cs "
	add	esi, 4	# skip "cs \0"
	add	eax, 4
.if 0
	jnz	2f
.else
	jz	1f	# print "eflags "
	cmp	byte ptr [esp + 8], 1
	jz	2f	# same priv level, no ss:esp
	add	esi, 8	# skip "eflags \0"
	add	eax, 4
	jz	1f	# print "esp "
	add	esi, 5	# skip "esp \0"
	add	eax, 4
	jnz	2f
.endif
1:	mov	ah, 9
	call	printc
	dec	dl
2:	pop	esi
	pop	edx
	jnz	1f	# don't print symbol for cs, eflags

3:	call	debug_printsymbol
1:	call	newline

	add	ebp, 4
	dec	ecx
	jnz	0b

	add	esp, 4	# pop the userstack flag
	pop	ecx
	pop	ebp
	pop	fs

	# calculate stack print screenpos
	call	screen_get_scroll_lines
	sub	eax, [stack_print_lines$]
	mov	[stack_print_lines$], eax
	mov	edx, 160
	imul	eax, edx
	mov	edx, [stack_print_pos$]
	sub	edx, eax
	mov	[stack_print_pos$], edx
	ret

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

