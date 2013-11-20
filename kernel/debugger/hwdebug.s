.intel_syntax noprefix
.text32

# debug registers:
# DR7	Debug Control register
#	lnRWlnRWlnRWlnRW..G...GLGLGLGLGL
/*	3333222211110000ooDooiEE33221100*/
#
#	len3[2] | len2[2] | len1[2] | len0[2]
#
#	L0, L1, L2, L3 (bits 0, 2, 4, 6): local breakpoint enable (cur task)
#		on task switch these are cleared.
#	G0, G1, G2, G3 (bits 1, 3, 5, 7): global breakpoint enable (all tasks)
#		on task switch these remain the same.
#	LE (bit 8) local exact breakpoint enable
#	GE (bit 9) global exact breakpoint enable
#		LE and GE are not commonly supported in newer architectures.
#	GD (bit 13): general detect; enable debug register protection, by
#	  triggering the debug interrupt when the next instr refs DR0..7.
#	RW0..RW3 (bits 16,17, 20,21, 24,25, 28,29).
#	  When CR4.DE (debug extensions) = 1:
#		00 = break on instruction execution only
#		01 = break on data writes only
#		10 = break on I/O reads or writes
#		11 = break on data reads or writes but not instruction fetches
#	  When CR4.DE is clear (386/486 compatible):
#		00 = break on instruction execution only
#		01 = break on data writes only
#		10 = undefined
#		11 = break on data reads or writes but not instruction fetches
#	LEN0..LEn3: data length:
#		00 = 1 byte	(requred when RWx = 00 (execution))
#		01 = 2 byte
#		10 = udnefined / 8 bytes
#		11 = 4 byte

# DR6	debug status register 0xffff << 16 | BT BS BD 0 | 1111 1111 | B3 B2 B1 B0
#	b3..b0: breakpoint condition detected; only valid when DR7 Ln or Gn set
#	BD (bit 13): next instr accesses DR0..7; only valid when DR7.GD is set
#	BS (bit 14): interrupt cause is single step (TF flag in EFLAGS)
#	BT (bit 15): interrupt cause is task switch (Trap flag in TSS set)
# DR5	alias for DR7; #UD invalid opcode exception on access when CR4.DE == 0
# DR4 	alias for DR6; #UD invalid opcode exception on access when CR4.DE == 0
# DR3	Linear address 3
# DR2	linear address 2
# DR1	linear address 1
# DR0	linear address 0

# in: eax = mem address
KAPI_DECLARE breakpoint_memwrite_dword
breakpoint_enable_memwrite_dword:
.global breakpoint_memwrite_dword
breakpoint_memwrite_dword:
enable_breakpoint_memwrite_dword:
.if 0
	DEBUG "Set breakpoint: addr:"
	DEBUG_DWORD eax
	call	newline
	STACKTRACE 0,0
.endif

	push	ebx
	GDT_GET_BASE ebx, ds
	add	eax, ebx
	pop	ebx
	#DEBUG " hw addr:"
	#DEBUG_DWORD eax

# KEEP-WITH-NEXT fallthrough

breakpoint_set_memwrite_dword:
call bp_disabled
	push_	eax ebx

# clear old breakpoints:
	xor	ebx, ebx
	mov	dr0, ebx
	mov	dr1, ebx
	mov	dr2, ebx
	mov	dr3, ebx

	mov	ebx, dr7
	#	ebx, 0b11111111111111110010011111111111 # 0=reserved bit
	#              f   f   f   f   2   7   aabbccdd
	#	       0   0   0   0   0   4   0   0

	test	al, 1
	jz	1f
	# not byte aligned; DR0 = first byte, DR1 = last byte, DR2 = middle word
	mov	dr0, eax
	add	eax, 3
	mov	dr1, eax
	sub	eax, 2
	mov	dr2, eax
	#	......|....MidlLastFrst
	and	ebx, 0b11110000000000001111111111111111 # clear bits to change
	or	ebx, 0b00000101000100010000000000010101 # len 1, data wr only
	mov	dr7, ebx
	pop_	ebx eax
	ret

1:	test	al, 2
	jz	0f

	mov	dr0, eax
	add	eax, 2
	mov	dr1, eax      #SECNfrst
	and	ebx, 0b11111111000000001111111111111111 # clear bits to change
	or	ebx, 0b00000000010101010000000000000101 # len 2 Write, len 2 write
	mov	dr7, ebx
	pop_	ebx eax
	ret

0:
	mov	dr0, eax	# use 4th register

	###############lnRWlnRWlnRWlnRW..G...GLGLGLGLGL
	###############3333222211110000ooDooiEE33221100
	#and	eax, 0b11111111111111110010011111111111
	#	.......####
	and	ebx, 0b11111111111100001111111111111111 # clear bits to change
	or	ebx, 0b00000000000011010000000000000001 # len 4, data wr only

	mov	dr7, ebx
	pop_	ebx eax
	ret


breakpoint_set_memwrite_word:
call bp_disabled
	mov	ebx, dr7
	test	al, 1
	jz	1f

	mov	dr0, eax
	inc	eax
	mov	dr1, eax
		#              LLRWLLRW  LL=00=byte
	and	ebx, 0b11111111000000001111111111111111 # clear bits to change
	or	ebx, 0b00000000000100010000000000000101 # len 1, data wr only
	mov	dr7, ebx
	ret

1:	# word aligned
	mov	dr0, eax
		#      ............LLRW LL=01=word
	and	ebx, 0b11111111111100001111111111111111 # clear bits to change
	or	ebx, 0b00000000000001010000000000000001 # len 1, data wr only
	mov	dr7, ebx
	ret

breakpoint_set_memwrite_byte:
call bp_disabled
	mov	ebx, dr7
	mov	dr0, eax
	and	ebx, 0b11111111111100001111111111111100 # clear bits to change
	or	ebx, 0b00000000000000010000000000000011 # len 1, data wr only
	mov	dr7, ebx
	ret

bp_disabled:
ret
	DEBUG "breakpoints disabled"
	int 3
	ret

# in: eax = address
# in: bl = size: 1, 2, 3
breakpoint_set_memwrite:

	test	bl, ~3
	jnz	9f
	or	bl, bl
	jz	breakpoint_set_code

	push	edx
	pushcolor 0xe0
	printc	0xe1, "Breakpoint: "
	mov	edx, eax
	call	printhex8
	GDT_GET_BASE edx, ds
	push	eax
	add	eax, edx
	mov	edx, eax
	printc	0xe1 " (phys addr: "
	call	printhex8
	printc	0xe1, ") size "
	push	ecx
	mov	cl, bl
	dec	cl
	mov	edx, 1
	shl	edx, cl
	pop	ecx
	call	printhex1
	printc 0xe1, " cur value: "
	pop	edx
	mov	edx, [edx]
	call	printhex8
	call	printspace
	call	printhex2
	call	printspace
	shr	edx, 8
	call	printhex2
	call	printspace
	shr	edx, 8
	call	printhex2
	call	printspace
	shr	edx, 8
	call	printhex2
	call	printspace
	call	newline
	popcolor
	pop	edx

	cmp	bl, 3
	jz	breakpoint_set_memwrite_dword
	cmp	bl, 2
	jz	breakpoint_set_memwrite_word
	cmp	bl, 1
	jz	breakpoint_set_memwrite_byte

9:	printlnc 4, "breakpoint_set_memwrite: wrong size: "
	push	edx
	movzx	edx, bl
	call	printdec32
	pop	edx
	printlnc 4, " - not 1, 2 or 3"
	stc
	jmp	0b


# in: eax = address
breakpoint_set_code:
	printlnc 0xe4, "code breakpoint not implemented yet"
	ret


# called from idt.s interrupt handler for int 1.
# The purpose is to check for breakpoint conditions more complex than
# a simple write/read.
#
# out: CF = 1: ignore the interrupt
debugger_handle_int:
DEBUG "DEBUGGER INTERRUPT!", 0x4f
	# debugger condition check.
	# hardcode test: assume breakpoint
	mov	edx, dr6	# debug status reg
	test	dl, 0b1111	# check for breakpoint (only valid if dr7....etc)
	jz	1f
	# hardcoded: dr0; can be dr0..dr3
	mov	edx, dr0
	#DEBUG_DWORD edx
	GDT_GET_BASE eax, ds
	sub	edx, eax
	#DEBUG_DWORD edx
	mov	edx, [edx]# get the value
	cmp	edx, 0x20657669	# this is the check!
	stc	# tell caller to ignore the interrupt
#	jnz	9f
#	DEBUG_DWORD edx

	mov	edx, dr6; DEBUG_DWORD edx, "dr6"
	mov	edx, dr3; DEBUG_DWORD edx, "dr3"
	mov	edx, dr2; DEBUG_DWORD edx, "dr2"
	mov	edx, dr1; DEBUG_DWORD edx, "dr1"
	mov	edx, dr0; DEBUG_DWORD edx, "dr0"
	call	newline
	# dr6: ffff 0ff1
	# ffff | BT BS BD | 0 11111111 | B3 B2 B1 B0
	# ffff |     0         f       f        1
	# ffff | BT BS BD 0 | 1111 | 1111 | B3 B2 B1 B0
	#       ---------dh-------- --------dl---------
	mov edx, dr6	# debug status reg
	PRINTFLAG dl, 1<<0, "B0 "
	PRINTFLAG dl, 1<<1, "B1 "
	PRINTFLAG dl, 1<<2, "B2 "
	PRINTFLAG dl, 1<<3, "B3 "
	PRINTFLAG dh, 1<<5, "BD "
	PRINTFLAG dh, 1<<6, "BS "
	PRINTFLAG dh, 1<<7, "BT "
	mov	edx, dr0
	DEBUG_DWORD edx
	GDT_GET_BASE eax, ds
	sub	edx, eax
	DEBUG_DWORD edx
	DEBUG_DWORD [edx]
	call	newline

	clc
9:	ret

1: 	DEBUG "no match"
	mov	edx, dr7; DEBUG_DWORD edx, "dr7"
	mov	edx, dr6; DEBUG_DWORD edx, "dr6"
	mov	edx, dr3; DEBUG_DWORD edx, "dr3"
	mov	edx, dr2; DEBUG_DWORD edx, "dr2"
	mov	edx, dr1; DEBUG_DWORD edx, "dr1"
	mov	edx, dr0; DEBUG_DWORD edx, "dr0"
	call	newline

	clc
	ret
