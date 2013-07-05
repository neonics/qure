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
##############################################################################

IRQ_PROXIES = 1	# needed for scheduling

IRQ_SHARING = 1	# 0: the last device to hook_isr will be the one to use the IRQ

##############################################################################
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
_I=0
.rept 256
DEFIDT (isr_jump_table-.text+_I), SEL_flatCS, ACC_PR|ACC_RING0|ACC_SYS|IDT_ACC_GATE_INT32
_I=_I+8
.endr


.text32

# in: ax = interrupt number (at current: al, as the IDT only has 256 ints)
# in: cx = segment selector
# in: ebx = offset
# out: cx = old segment selector
# out: ebx = old offset
hook_isr:
	pushf
	cli
	push	ecx
	push	ebx
	push	eax
	and	eax, 0xff

	.if DEBUG > 1
		push	edx
		mov	edx, eax
		I	"Hook INT "
		call	printhex2
		I2	" @ "
		call	printspace
		mov	edx, ebx
		call	printhex8
		call	printspace
		call	debug_printsymbol
		pop	edx
	.endif

.if IRQ_PROXIES
	push	eax
	push	edx

	.if 0 # if len = 9: pushf; lcall; iret
	mov	edx, eax
	shl	eax, 3
	add	eax, edx	# * 9
	.else # len = 15
	shl	eax, 4		# table entry size: 16 bytes
	.endif

	# put the old values in the stack for return
	mov	edx, [irq_proxies + eax + 2]
	mov	[esp + 12], edx
	movzx	edx, word ptr [irq_proxies + eax + 6]
	mov	[esp + 16], edx

	mov	[irq_proxies + eax + 2], ebx
	mov	[irq_proxies + eax + 6], cx
	mov	cx, cs
	lea	ebx, [irq_proxies + eax]
	pop	edx
	pop	eax
.endif

	mov	[IDT + eax*8 + 0], bx
	mov	[IDT + eax*8 + 2], cx
	mov	[IDT + eax*8 + 4], word ptr (ACC_PR + IDT_ACC_GATE_INT32 ) << 8
	shr	ebx, 16
	mov	[IDT + eax*8 + 6], bx

	sti
	pop	eax
	pop	ebx
	pop	ecx
	popf
	ret

.if IRQ_SHARING

.data SECTION_DATA_BSS
irq_handlers:	.long 0
MAX_IRQ_HANDLERS_PER_IRQ_SHIFT = 3
MAX_IRQ_HANDLERS_PER_IRQ = 1 << MAX_IRQ_HANDLERS_PER_IRQ_SHIFT
.text32

#### NOTE !!! ### the below code ignores cx/codeseg of handler!

# in: al = IRQ (0-based)
# in: cx = code segment of handler
# in: ebx = offset of handler
add_irq_handler:
	push_	ecx edx esi
	mov	esi, [irq_handlers]
	or	esi, esi
	jnz	1f

	push	eax
	mov	eax, 0x10 * MAX_IRQ_HANDLERS_PER_IRQ * 4	# 16 hndlr=1kb
	call	mallocz
	mov	esi, eax
	pop	eax
	jc	91f
	mov	[irq_handlers], esi

1:	movzx	eax, al
	shl	eax, MAX_IRQ_HANDLERS_PER_IRQ_SHIFT + 2	#1<<2=4=dword ptr
	add	esi, eax
	mov	dx, cx	# codeseg
	mov	ecx, MAX_IRQ_HANDLERS_PER_IRQ
0:	lodsd
	or	eax, eax
	jz	1f
	loop	0b
	jmp	93f

1:	mov	[esi-4], ebx

	clc
9:	pop_	esi edx ecx
	#call print_irq_handlers
	ret
91:	printlnc 4, "add_irq_handler: mallocz fail"
	stc
	jmp	9b
92:	printlnc 4, "add_irq_handler: maximum reached"
	stc
	jmp	9b

# in: al = IRQ
# in: cx = code segment of handler
# in: ebx = offset of handler
remove_irq_handler:
	push_	eax ecx esi edi
	mov	edi, [irq_handlers]
	or	edi, edi
	jz	91f

	movzx	eax, al
	shl	eax, MAX_IRQ_HANDLERS_PER_IRQ_SHIFT + 2
	add	edi, eax
	mov	ecx, MAX_IRQ_HANDLERS_PER_IRQ	# discard cx
	mov	eax, ebx
	repnz	scasd
	jnz	92f

	mov	[edi - 4], dword ptr 0
	# make compact
	jecxz	0f
	mov	esi, edi
	sub	edi, 4
	rep	movsd
0:	pop_	edi esi ecx eax
	#call print_irq_handlers
	ret
91:	printlnc 4, "remove_irq_handler: array null"
	int 3
	jmp	0b
92:	printlnc 4, "remove_irq_handler: not found"
	int 3
	jmp	0b

print_irq_handlers:
	pushad
	mov	esi, [irq_handlers]
	or	esi, esi
	jz	91f
	mov	ecx, 16	# 16 irq's
	xor	edx, edx

0:	print "IRQ "
	mov	edx, 16
	sub	edx, ecx
	call	printhex2

	push	ecx
	mov	ecx, MAX_IRQ_HANDLERS_PER_IRQ
1:	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
	loop	1b
	call	newline
	pop	ecx

	loop	0b

9:	popad
	ret
91:	println "No IRQ Handlers (buffer 0)"
	jmp	9b

# referenced from irq_proxies.
irq_isr:
	push	ebp
	lea	ebp, [esp + 4]
	push_	edx eax ds es
	
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	mov	eax, [ebp]	# get return eip
	cmp	eax, offset irq_proxies
	jb	91f
	cmp	eax, offset irq_proxies + 16*256
	jae	91f
	# eax points somewere in irq_proxies.
	# read the interrupt number.
	# 2 ways:
	movzx	edx, word ptr cs:[eax+5]	# skip the jump schedule_isr
	# calculate the interrupt number:
	sub	eax, offset irq_proxies
	js	91f
	shr	eax, 4	# 16 byte entry size
	cmp	eax, edx
	jnz	92f

	sub	al, IRQ_BASE
	js	93f
	cmp	al, 0x10
	jae	93f
	mov	dl, al

	.if 0
		printc 0xf0, "irq_isr"
		call	printhex2
	.endif

	# do this early
	PIC_SEND_EOI al

#######	# Call IRQ handlers
	push_	esi ecx
	mov	esi, [irq_handlers]
	or	esi, esi
	jz	90f

	shl	eax, MAX_IRQ_HANDLERS_PER_IRQ_SHIFT + 2	#+2 for dword ptr
	mov	ecx, MAX_IRQ_HANDLERS_PER_IRQ
	add	esi, eax
0:	lodsd
	or	eax, eax	
	.if 1 # expect compact
		jz	80f
	.else
		jz	1f
	.endif

	pushf
	pushd	cs
	call	eax

1:	loop	0b

80:	pop_	ecx esi
#######

0:	pop_	es ds eax edx
	pop	ebp
	iret

90:	printc 4, "no isr for IRQ"
	call	printhex2
	jmp	80b

91:	printlnc 4, "irq_isr not called from irq_proxies!"
	int 1
	jmp	0b
92:	printc 4, "irq_proxy offset & data mismatch"
	DEBUG_DWORD edx
	DEBUG_DWORD eax
	int 1
	jmp	0b
93:	printc 4, "irq_isr called for non-IRQ: "
	call	printhex2
	int 1
	jmp	0b
.endif
###############################################################
# the following 2 tables comined are 6272 bytes: 256 * (8 + 16)
isr_jump_table:

	INT_NR = 0
	.rept 256
		push	word ptr INT_NR		# 3 bytes
		jmp	jmp_table_target	# 5 bytes
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
		pushf					# 1 byte
		lcall	SEL_compatCS, jmp_table_target	# 7 bytes # 8
		jmp	schedule_isr			# 5 bytes # 13
		.word	INT_NR				# 2 bytes # 15
		nop					# 1 byte  # 16
		INT_NR = INT_NR + 1
	.endr
	IRQ_PROXY_OFFS_OFFS	= 4	# handler offset
	IRQ_PROXY_INT_OFFS	= 13	# interrupt number
.endif

.data
# Faults: correctable; CS:EIP point to faulting instruction
# Trap: CS:EIP points to next instruction
# Abort: no restart/continuation - severe errors.
int_labels$:					# int  Fault/Trp/Abrt/Int Errcde
STRINGPTR "Division by zero";		EX_DE=0x00;	# F	Divide Error
STRINGPTR "Debugger";			EX_DB=0x01;	# F/T
STRINGPTR "NMI";					# I
STRINGPTR "Breakpoint";			EX_BP=0x03;	# T
STRINGPTR "Overflow";			EX_OF=0x04;	# T
STRINGPTR "Bound range exceeded";	EX_BR=0x05;	# F
STRINGPTR "Invalid Opcode";		EX_UD=0x06;	# F	Undefined Opcode
STRINGPTR "Coprocessor not available";	EX_NM=0x07;	# F  (No Math copro)
STRINGPTR "Double fault";		EX_DF=0x08;	# A E
STRINGPTR "Coprocessor Segment Overrun"; 		# F (386 or earlier only)
STRINGPTR "Invalid Task State Segment";	EX_TS=0x0a;	# F E
STRINGPTR "Segment not present";	EX_NP=0x0b;	# F E
STRINGPTR "Stack Segment Fault";	EX_SS=0x0c;	# F E
STRINGPTR "General protection fault";	EX_GP=0x0d;	# F E
STRINGPTR "Page fault";			EX_PF=0x0e;	# F E
STRINGPTR "reserved";					# F
STRINGPTR "Math Fault";			EX_MF=0x10;	# F
STRINGPTR "Alignment Check";		EX_AC=0x11;	# F E
STRINGPTR "Machine Check";		EX_MC=0x12;	# A
STRINGPTR "SIMD Floating-Point Exception";EX_XD=0x13;	# F	SSE
# up to 0x20 is reserved.
# int 0x1c called in qemu doublefault handler
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
	lea	ebp, [esp + 4]
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

	cmp	word ptr [SR_INT], 1	# debugger
	jnz	1f
	call	debugger_handle_int
	jc	9f
1:


	# enter textmode if needed
	cmp	byte ptr [gfx_mode$], 0
	jz	1f
	pushad
	call	cmd_gfx
	popad
1:

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
	#call	newline
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
or edx, edx
jz 11f
	mov	dx, [edx-2]
11:	pop	ds
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
	# if the code references GDT
	mov	eax, ss:[edi]	# reload error code
	and	al, 7
	jnz	3f
	# it's the GDT
	# find out what type of descriptor it is:
	call	debug_print_gdt_descriptor
3:


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

	# Carry 0 Parity 0 Adjust 0 Zero Sign Trap Int Direction Overflow
	LOAD_TXT "ODITSZ A P C"
	push	ecx
	mov	ecx, 12
	shl	dx, 4	# have bit 11 be bit 15
0:	lodsb
	mov	ah, 7
	shl	dx, 1
	jc	1f
	inc	ah
	or	al, 0x20
1:	call	printcharc
	loop	0b
	pop	ecx

	call	printspace
	mov	edx, [scheduler_current_task_idx]
	cmp	edx, -1
	jz	1f
	add	edx, [task_queue]
	mov	edx, [edx + task_pid]
	printc 7, "task "
	call	printhex4
1:	call	newline

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

	str	dx	# load TR into dx
	call	debug_print_tss$

	call	debug_print_exception_registers$

########
	.if 0
	cmp	cx, 0x0e	# page fault: show mem
	jnz	1f
	print "MEM: used="
	call mem_get_used
	call printhex8
	mov edx, eax
	call printhex8
	print " reserved: "
	call mem_get_reserved
	call printhex8
	mov edx, eax
	call printhex8
	print " hi="
	mov edx, [mem_heap_alloc_start]
	call printhex8
	call newline
1:
	.endif

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
	cmp	ebx, SEL_MAX
	jb	2f
	DEBUG_DWORD ebx, "illegal user stack selector", 4
	jmp	1f
2:	mov	esi, ss:[edi + 12]	# user esp
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
	jz	3f
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
9:	pop	edx
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

3:	# page fault
	push	fs
	mov	eax, SEL_flatDS
	mov	fs, eax

	print "CR3: "
	mov	edx, cr3	# PDE
	mov	ebx, edx
	call	printhex8
	print " krnl PD: "
	mov	edx, [page_directory_phys]
	call	printhex8
	print " CR2: "
	mov	edx, cr2	# fault address
	call	printhex8

	print " PDE #"
	shr	edx, 22
	call	printdec32
	call	printspace

	#mov	edx, fs:[ebx + edx * 4] # causes page fault
	mov	edx, fs:[ebx + edx * 4]
	call	printhex8
	.if 0
		mov	eax, edx
		call	printspace
		and	edx, ~((1<<22)-1)
		call	printhex8
		mov	edx, eax
		and	edx, (1<<22)-1
		call	printspace
		call	printhex8
	call	newline
	.endif
	0: hlt; jmp 0b

	pop	fs
	jmp	2b


# in: edx = selector from GDT
debug_print_gdt_descriptor:
	push_	ebx esi edx
	mov	ebx, edx
	printc 7, " Descriptor: "
	call	printhex4
	call	printspace
	GDT_GET_ACCESS al, edx
	mov	dl, al
	call	printbin8
	# better called SEGMENT flag: 1 = segment, 0 = descriptor (gate[int,call,trap],LDT,TSS)
	test	al, ACC_NRM	# SYS flag 0 = descriptor; 1 = segment
	jz	1f
	# it's a segment selector
	PRINTFLAG al, ACC_CODE, "Code", "Data"
	PRINTBITSb al, ACC_RING_SHIFT, 2, " DPL"
	GDT_GET_BASE edx, ebx
	print " Base: "
	call	printhex8
	print " Limit: "
	GDT_GET_LIMIT edx, ebx
	call	printhex8
	jmp	9f

1:	and	al, 0xf	# low 4 bits is the GATE type

#16			32
#0 000			1 000
#0 001	TSS		1 001	TSS
#0 010	LDT		1 010
#0 011	TSS	(busy)	1 011	TSS	(busy)
#0 100	CALL		1 100	CALL
#0 101	TASK32		1 101
#0 110	INT		1 110	INT
#0 111	TRAP		1 111	TRAP

.data
desc_types$:	.asciz "RSV", "TSS", "LDT", "TSS(b)", "CALL", "TASK", "INT", "TRAP";
.text32
	mov	esi, offset desc_types$
	# first test for singly-reserved values.([01]000 prints RSV so ok)
	cmp	al, 0b1010	# LDT 32 -> reserved; LDT16 = LDT
	jz	3f

	mov	edx, 16
	test	al, 0b1000
	jz	2f
	mov	edx, 32
2:	mov	ah, al
	and	ah, 0b0111
	jmp	1f

0:	PRINTSKIP_
	dec	ah
1:	jnz	0b
	pushcolor 0xf0
	call	print
	call	printdec32
	popcolor

	jmp	9f

3:	printc 4, "invalid type: "
	mov	dl, al
	call	printbin4

9:	pop_	edx esi ebx
	ret



# in: dx = TSS selector
debug_print_tss$:
call print_tss
	push_	esi edi
	printc 15, "TSS: "
	call	printhex4
	movzx	esi, dx
	GDT_GET_BASE edx, esi
	mov	edi, edx
	GDT_GET_BASE edx, ds
	sub	edi, edx	# make ds-rel
	GDT_GET_LIMIT edx, esi
	print " LIM: "
	call printhex8
	add	esi, offset GDT

	print " A="
	mov	dl, [esi + 5] # type (access)
	call	printhex2
	print " F="
	mov	dl, [esi + 6]
	call	printhex2


	printc 7, " SS0:ESP0="
	mov	edx, [edi + tss_SS0]
	call	printhex4
	print ":"
	mov	edx, [edi + tss_ESP0]
	call	printhex8
	printc 7, " SS:ESP="
	mov	edx, [edi + tss_SS]
	call	printhex4
	printchar_ ':'
	mov	edx, [edi + tss_ESP]
	call	printhex8
	mov	dx, [edi + tss_LINK]
	print " Link: "
	call	printhex4
	call	newline
	pop_	edi esi
.if 0
	printc 11, " ss:esp="
	mov	edx, ss
	call	printhex4
	printchar_ ':'
	mov	edx, esp
	call	printhex8

	printc 7, " TSS: cs="
	mov	edx, [TSS + tss_CS]
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
	lea	edx, [edi + 12]
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
# GDT: SEL_tss2
# IDT: entry 8 - IDT_ACC_GATE_INT32 with SEL_tss2 as descriptor
# code offset: [tss2_EIP]
# All registers loaded from [tss2_*].
# tss2_LINK -> old TSS, containing the info of the suspended task.
ex_df_task_isr:
	#push_	es ds eax ebp
	#lea	ebp, [esp + 16]
	# not needed - TSS has these set up.
	#mov	eax, SEL_compatDS
	#mov	es, eax
	#mov	ds, eax
	call	newline
	printc 0xf4, "Double Fault"
#jmp 0f
	DEBUG_WORD ss
	DEBUG_DWORD esp
	mov	ebp, esp
	DEBUG_DWORD [ebp],"error"
	xor	edx, edx
	str	dx
	GDT_GET_BASE ebx, ds
	GDT_GET_BASE eax, edx
	sub	eax, ebx
	DEBUG_DWORD [eax + tss_ESP], "ESP"
	DEBUG_DWORD [eax + tss_ESP0], "ESP0"
	pushfd
	pop	eax
	DEBUG_DWORD eax, "flags"
	call	newline

	str	dx
	call	print_tss

#call more
.if 1
	jmp	halt
.else
	iret	# doesn't use stack if EFLAGS.NT (next task)
	DEBUG "again!"
	call newline
	jmp	ex_df_task_isr
.endif
	#pop_	ebp eax ds es
###################################################################
# Page Fault Interrupt Task Gate
ex_pf_task_isr:
	printc 0xf4, "Page Fault"
	DEBUG_DWORD ecx
	DEBUG_WORD ss
	DEBUG_DWORD esp
	DEBUG_DWORD [TSS_PF + tss_ESP], "ESP"
	DEBUG_DWORD [TSS_PF + tss_ESP0], "ESP0"
	mov	edx, cr2
	DEBUG_DWORD edx, "cr2"
	pushfd
	pop	eax
	DEBUG_DWORD eax, "flags"
	call	newline

	mov	eax, [TSS_PF + tss_LINK]
	DEBUG_DWORD eax,"linked TSS"
	GDT_GET_BASE edx, eax
	DEBUG_DWORD edx, "linked TSS base"
	GDT_GET_BASE eax, ds
	sub	edx, eax
	mov	ebp, [edx + tss_ESP]
	DEBUG_DWORD ebp, "linked task ESP"
	DEBUG_DWORD [ebp + 0], "eip"
	DEBUG_DWORD [ebp + 4], "cs"
	DEBUG_DWORD [ebp + 8], "eflags"
	DEBUG_DWORD [ebp + 12], "esp"
	DEBUG_DWORD [ebp + 16], "ss"
	call	newline

	str	dx
	call	print_tss

	inc	ecx
debug "ex_pf_task_isr returning"
mov ebp, esp
DEBUG_DWORD [ebp], "eip"
DEBUG_DWORD [ebp+4], "cs"
DEBUG_DWORD [ebp+8], "eflags"
	iret	# EFLAGS.NT
	jmp	ex_pf_task_isr


ex_np_task_isr:
	printc 4, "Segment Not Present"
0:hlt; jmp 0b
	iret
	jmp	ex_np_task_isr

ex_gp_task_isr:
	printc 4, "General Protection Fault"
0:hlt; jmp 0b
	iret
	jmp	ex_np_task_isr


###################################################################



init_idt: # assume ds = SEL_compatDS/realmodeDS
	pushf
	cli

	# update int 3: make CPL3 accessible
	mov	[IDT + 3*8 + 5], byte ptr (ACC_PR|IDT_ACC_GATE_INT32|ACC_RING3)

	push_	esi edi ebx edx
	mov	esi, offset TSS_PF
	mov	edi, EX_PF
	mov	edx, SEL_tss_pf
	mov	ebx, offset ex_pf_task_isr
	call	idt_init_ex

	mov	esi, offset TSS_DF
	mov	edi, EX_DF
	mov	edx, SEL_tss_df
	mov	ebx, offset ex_df_task_isr
	call	idt_init_ex

.if 1
	mov	esi, offset TSS_NP
	mov	edi, EX_NP
	mov	edx, SEL_tss_np
	mov	ebx, offset ex_np_task_isr
	call	idt_init_ex
.endif

.if 0
	mov	esi, offset TSS_NP	# reuse the tss
	mov	edi, EX_GP
	mov	edx, SEL_tss_np
	mov	ebx, offset ex_gp_task_isr
	call	idt_init_ex
.endif
	pop_	edx ebx edi esi

.if IRQ_SHARING
	# register the IRQ core handlers
	mov	al, IRQ_BASE
	push	ebx
	mov	ecx, 16
0:	push	ecx
	mov	ebx, offset irq_isr
	mov	cx, cs
	call	hook_isr	# changes cx,ebx
	pop	ecx
	inc	al
	loop	0b
	pop	ebx
.endif

	mov	eax, [reloc$]#[realsegflat]
	add	eax, offset IDT
	mov	[pm_idtr + 2], eax
	lidt	[pm_idtr]

	popf	# leave IF (cli/sti) as it was
	ret


# in: edx = selector
# in: edi = exception nr
# in: esi = TSS
# in: ebx = handler offset
idt_init_ex:

	# update page fault handler: IDT offset is ignored when using TSS
	mov	[IDT + edi*8 + 2], dx # word ptr SEL_tss_pf
	mov	[IDT + edi*8 + 4], word ptr (ACC_PR|ACC_RING0|IDT_ACC_GATE_TASK32)<<8

	# this determines what code is called when the TSS is activated:
	mov	[esi + tss_EIP], ebx # dword ptr offset ex_pf_task_isr
	mov	[esi + tss_SS0], dword ptr SEL_compatDS
	mov	[esi + tss_SS], dword ptr SEL_compatDS
	mov	[esi + tss_DS], dword ptr SEL_compatDS
	mov	[esi + tss_ES], dword ptr SEL_compatDS
	mov	[esi + tss_CS], dword ptr SEL_compatCS
	mov	eax, [page_directory_phys]
	mov	[esi + tss_CR3], eax
	mov	eax, [esi + tss_ESP0]
	mov	[esi + tss_ESP], eax

	ret


