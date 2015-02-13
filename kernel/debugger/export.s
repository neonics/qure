############################################################################
# This file may only contain macros and constants - no code and no data,
# as it is the first file included, before the start offset. This way
# we save a jump instruction.
############################################################################

# DEBUG LEVELS
#
# 1: display initialization
# 2: detailed inintialization
# 3: memory addresses
# 4: interrupts - use fixed screen coordinates


############################# 32 bit macros 
.if DEFINE

	.global breakpoint
	.global debug_regstore
	.global debug_regdiff
.endif

.if !DEFINE

.ifndef __DEBUG_DECLARED

##############################################
_DBG_ENABLED = 1
_DBG_BP_ENABLED = 1	# whether to compile conditional breakpoints
_DBG_PRINT_ENABLED = 1	# legacy behaviour

.macro DEBUGGER command, argv:vararg
	DEBUGGER_\command \argv
.endm

.macro DEBUGGER_NAME name:req
.endm

##############################################


.macro OK
	PRINTLNc 0x0a, " Ok"
	clc
.endm

.macro I m
	PRINTCHARc 0x09 '>'
	PRINTc 15 " \m"
	#COLOR 7
.endm

.macro I2 m
	PRINTc 7 "\m"
.endm


.macro MORE
	pushf
	push	eax
	call	newline
	PUSH_SCREENPOS
	#sub	[esp], dword ptr 160
	PRINTc 0xf1, " --- More ---"
0:	xor	ah, ah
	call	keyboard
	cmp	ax, K_ENTER
	jnz	0b
	POP_SCREENPOS
	PUSH_SCREENPOS
	PRINT "             "
	POP_SCREENPOS
	pop	eax
	popf
.endm


DEBUG_COLOR1 = 0x1a
DEBUG_COLOR2 = 0x17
DEBUG_COLOR3 = 0x1f

.macro DEBUG str, color=DEBUG_COLOR3
	.ifnes "\str", ""
	pushf
	printc \color, "\str "
	popf
	.endif
.endm

.macro DEBUGS reg=esi, label=0, color2=DEBUG_COLOR2, color1=DEBUG_COLOR1
	pushf
	pushcolor \color1
	.ifnc 0,\label
	PRINT "\label="
	.endif
	PRINTCHAR '\''
	COLOR	\color2
	.ifc esi,\reg
	call	print
	.else
	push	esi
	mov	esi, \reg
	call	print
	pop	esi
	.endif
	COLOR	\color1
	PRINTCHAR '\''
	call	printspace
	popcolor
	popf
.endm

.macro DEBUGz yes, no
	jnz	9001f
	DEBUG "\yes"
	.ifc \no,
9001:
	.else
	jmp	9009f
9001:	DEBUG "\no"
9009:
	.endif
.endm

.macro DEBUGc yes, no
	jnc	9001f
	DEBUG "\yes"
	.ifc \no,
9001:
	.else
	jmp	9009f
9001:	DEBUG "\no"
9009:
	.endif
.endm


.macro DEBUG_R8 r
DEBUG_BYTE \r
.endm

.macro DEBUG_R16 r
DEBUG_WORD \r
.endm

.macro DEBUG_R32 r
DEBUG_DWORD \r
.endm

.macro DEBUG_BYTE r8, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
#.if _DBG_PRINT_ENABLED	# inside, so leave calls
	pushd	(\color2 << 16) | \color1 | (1<<8)
	.ifc "","\label"
		PUSHSTRING "\r8="
	.else
		PUSHSTRING "\label="
	.endif
		push	edx
	IS_REG8 _, \r8
	.if _
		movzx	edx, \r8
	.else
		movzx	edx, byte ptr \r8
	.endif
		xchg	edx, [esp]
	call	debug_printvalue
#.endif
.endm

.macro DEBUG_WORD r16, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
#.if _DBG_PRINT_ENABLED	# inside, so leave calls
	pushd	(\color2 << 16) | \color1 | (2<<8)
	.ifc "","\label"
		PUSHSTRING "\r16="
	.else
		PUSHSTRING "\label="
	.endif
	pushw	0	# pad.
	pushw	\r16
	call	debug_printvalue
#.endif
.endm

.macro DEBUG_DWORD r32, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
#.if _DBG_PRINT_ENABLED	# inside, so leave calls
	pushd	(\color2 << 16) | \color1 | (4<<8)
	.ifc "","\label"
		PUSHSTRING "\r32="
	.else
		PUSHSTRING "\label="
	.endif
	pushd	\r32
	.ifc \r32,esp
		add	[esp], dword ptr 8
	.endif
	call	debug_printvalue
#.endif
.endm

.macro DEBUG_DIV_PRE r32
	pushcolor 8
	push	edx
	call	printhex8
	printchar ':'
	mov	edx, eax
	call	printhex8
	printchar '/'
	mov	edx, \r32
	call	printhex8
	pop	edx
	popcolor
.endm


.macro DEBUG_DIV_POST
	pushcolor 8
	printchar '='
	push	edx
	mov	edx, eax
	call	printhex8
	pop	edx
	printchar '.'
	call	printhex8
	popcolor
.endm


.macro DEBUG_REGSTORE name=""
	DEBUG "\name"
	call	debug_regstore
.endm

.macro DEBUG_REGDIFF
	call	debug_regdiff
.endm

.macro BREAKPOINT label
	.if _DBG_BP_ENABLED
	pushstring	"\label"
	call	breakpoint
	nop	# the function may modify it into int3
	.else; printc 0xf4, "BREAKPOINT: \label";
	.endif
.endm

.irp f, Z,C,S,NZ,NC,NS
.macro BREAKPOINT_\f\()F label
	jn\f	9001f
	BREAKPOINT "\label"
9001:
.endm
.endr

.macro ASSERT_ARRAY_IDX index, arrayref, elsize, mutex=0
	.ifnc 0,\mutex
	MUTEX_SPINLOCK \mutex
	.endif
	push_txt "\arrayref"
	push	\elsize
	push	\arrayref
	push	\index
	call	debug_assert_array_index
	.ifnc 0,\mutex
	MUTEX_UNLOCK \mutex
	.endif
.endm

.macro STACKTRACE stackret=a, check_cf=1
	.ifc \stackret,a
	.error "STACKTRACE needs stack depth for method return"
	.endif

	.if \check_cf
	jnc	9000f
	.endif

	.ifc \stackret,ebp
	call	stacktrace_ebp
	.else
	pushd	\stackret
	call	stacktrace
	.endif
9000:
.endm

__DEBUG_DECLARED=1
.endif

.else	# DEFINE = 1

.data SECTION_DATA_BSS
debug_registers$:	.space 4 * 32

_DEBUGGER_BP_FLAG_ENABLE=1
_DEBUGGER_BP_FLAG_DISABLE=0
_DEBUGGER_STATE_BP_BIT = 0
.data SECTION_DATA_BSS
debugger_state: .long 1
.text32
.macro DEBUGGER_BP w
	.if _DEBUGGER_BP_FLAG_\w
	bts	dword ptr [debugger_state], _DEBUGGER_STATE_BP_BIT	# or 1
	.else
	btr	dword ptr [debugger_state], _DEBUGGER_STATE_BP_BIT	# and ~1
	.endif
.endm

.text32
nop # so that disasm doesnt point to code_debug_start
# in: [esp] = label
breakpoint:
	push_	ebp ebx eax
	mov	ebp, esp
	pushf
.if 1
	PRINTC 0xf0, "breakpoint "
	push	esi
	mov	esi, [ebp + 4]
	DEBUG_DWORD esi
	call	print
	pop	esi
.endif

	mov	ebx, [ebp + 12] # get return address
	mov	al, [ebx] # get opcode
	# verify integrity
	cmp	al, 0x90
	jz	1f
	cmp	al, 0xcc
	jnz	91f

	mov	al, 0x90 # nop
1:	bt	dword ptr [debugger_state], _DEBUGGER_STATE_BP_BIT
	jnc	9f
	PUSHCOLOR 0xf0
	print "BREAKPOINT "
	pushd	[ebp + 12+4]
	call	_s_print
	POPCOLOR

	mov	al, 0xcc # int 3
9:	mov	[ebx], al # modify opcode
	popf
	pop_	eax ebx ebp
	ret	4

91:	printc 0xf4, "breakpoint: corrupt opcode: "
	push	edx
	mov	dl, al
	call	printhex2
	printc 0xf4, " @ "
	mov	edx, [esp + 12 + 4]
	call	printhex8
	pop	edx
	mov	al, 0x90
	jmp	9b




debug_regstore:
	mov	[debug_registers$ + 4 * 0], eax
	mov	[debug_registers$ + 4 * 1], ebx
	mov	[debug_registers$ + 4 * 2], ecx
	mov	[debug_registers$ + 4 * 3], edx
	mov	[debug_registers$ + 4 * 4], esi
	mov	[debug_registers$ + 4 * 5], edi
	mov	[debug_registers$ + 4 * 6], ebp
	mov	[debug_registers$ + 4 * 7], esp
	add	[debug_registers$ + 4 * 7], dword ptr 4
	mov	[debug_registers$ + 4 * 8], cs
	mov	[debug_registers$ + 4 * 9], ds
	mov	[debug_registers$ + 4 * 10], es
	mov	[debug_registers$ + 4 * 11], ss
	ret

debug_regdiff0$:
	push	ebp
	lea	ebp, [esp + 8]
	push_	eax ebx
	mov	eax, [ebp + 4]	# \nr
	mov	ebx, [ebp + 8]	# \reg
	cmp	[debug_registers$ + 4 * eax], ebx
	jz	1f
	push	dword ptr [ebp]	# stringptr
	call	_s_print
	print	": "
	push	edx
	mov	edx, [debug_registers$ + 4 * eax]
	call	printhex8
	print	" -> "
	pop	edx
	push	edx
	mov	edx, ebx
	call	printhex8
	pop	edx
	call	newline
1:	pop_	ebx eax
	pop	ebp
	ret	12

.macro DEBUG_REGDIFF0 nr, reg
	pushd	\reg
	.ifc \reg,esp
	add	dword ptr [esp], 4 + COLOR_STACK_SIZE + 4
	.endif
	pushd	\nr
	PUSHSTRING "\reg"
	call	debug_regdiff0$
.endm

# for segment registers
.macro DEBUG_REGDIFF1 nr, reg
	pushd	\reg
	andd	[esp], 0xffff
	pushd	\nr
	PUSHSTRING "\reg"
	call	debug_regdiff0$
.endm

debug_regdiff:
	pushf
	pushcolor 0xf4
	DEBUG_REGDIFF0 0, eax
	DEBUG_REGDIFF0 1, ebx
	DEBUG_REGDIFF0 2, ecx
	DEBUG_REGDIFF0 3, edx
	DEBUG_REGDIFF0 4, esi
	DEBUG_REGDIFF0 5, edi
	DEBUG_REGDIFF0 6, ebp
	DEBUG_REGDIFF0 7, esp
	DEBUG_REGDIFF1 8, cs
	DEBUG_REGDIFF1 9, ds
	DEBUG_REGDIFF1 10, es
	DEBUG_REGDIFF1 11, ss
	popcolor
	popf
	ret

.purgem DEBUG_REGDIFF0

# in: [esp] = value
# in: [esp + 4] = label
# in: [esp + 8] = (color1 | color2 << 16) # dword, up to [esp+12]
# in: [esp + 9] = nr of bytes of value: 4, 2, 1
debug_printvalue:
	pushfd
	push	ebp
	lea	ebp, [esp + 12]	# ebp + flags + ret

	push_	edx ecx eax
	mov	edx, [ebp]
	movzx	ecx, byte ptr [ebp + 9]	# byte size

	PUSHCOLOR [ebp + 8]
	pushd	[ebp + 4]
	call	_s_print

	shl	ecx, 1
	COLOR	[ebp + 10]
	call	nprinthex
	call	printspace
	POPCOLOR
	pop_	eax ecx edx

	pop	ebp
	popfd
	ret	12

# in: [esp+0] index
# in: [esp+4] arrayref
# in: [esp+8] elsize
# in: [esp+12] arrayref name
debug_assert_array_index:
	push	ebp
	lea	ebp, [esp + 8]
	pushf
	push	eax
	push	edx
	push	ebx
	push	ecx
	mov	ebx, [ebp + 4]	# arrayref
	mov	edx, [ebp + 0]	# index

	# check range
	cmp	edx, [ebx + array_index]
	jb	1f
	printc 4, "array index out of bounds: "
	jmp	9f

	# check alignment
1:	xor	eax, eax
	xchg	edx, eax
	mov	ecx, [ebp + 8]	# elsize
	div	ecx
	or	edx, edx
	jz	0f
	printc 4, "array index alignment error: off by: "
	call	printhex8
	printc 4, " relative to "
	mov	edx, eax
	call	printhex8
	jmp	9f

0:	pop	ecx
	pop	ebx
	pop	edx
	pop	eax
	popf
	pop	ebp
	ret	16

9:	printc 4, " array: "
	push	[ebp + 12]	# name
	call	_s_print
	call	printspace
	push	ebx
	call	_s_printhex8

	printc 4, " index="
	push	dword ptr [ebp + 0]	# index
	call	_s_printhex8

	printc 4, " max="
	push	dword ptr [ebx + array_index]
	call	_s_printhex8

	call	newline

	printc 4, "caller: "
	mov	edx, [ebp - 4]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	int	3
	jmp	0b


.global stacktrace
# in: [esp] = stack depth until return eip
stacktrace:
	push	ebp
	mov	ebp, [esp + 8]
	lea	ebp, [esp + 12 + ebp]
	call	stacktrace_ebp
	lea	ebp, [esp + 4]	# log the location where the stacktrace is printed
	call	stacktrace_ebp
	pop	ebp
	ret	4

.global stacktrace_ebp
# meant for mem.s etc, which have ebp point to eip ret.
# in: [esp] = return eip
stacktrace_ebp:
	push	edx
	mov	edx, [ebp]
	pushf
	printc 14, " at "
	pushcolor 8
	call	printhex8
	popcolor
	call	printspace
	call	debug_printsymbol
	jnc	1f
	printc 12, " - not code?"
1:	call	newline
	popf
	pop	edx
	ret



.endif	# DEFINE
