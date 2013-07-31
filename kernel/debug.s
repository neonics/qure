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
.if !DEFINE

.macro OK
	PRINTLNc 0x0a, " Ok"
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

.macro DEBUGc c, str
	pushf
	printc (DEBUG_COLOR3 & 0xf0) | (\c & 0xf), "\str "
	popf
.endm

.macro DEBUGS reg=esi, label=0, color=DEBUG_COLOR2
	pushf
	pushcolor DEBUG_COLOR1
	.ifnc 0,\label
	PRINT "\label="
	.endif
	PRINTCHAR '\''
	COLOR	\color
	.ifc esi,\reg
	call	print
	.else
	push	esi
	mov	esi, \reg
	call	print
	pop	esi
	.endif
	COLOR	DEBUG_COLOR1
	PRINTCHAR '\''
	call	printspace
	popcolor
	popf
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

.endm

.macro DEBUG_WORD r16, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
	pushd	(\color2 << 16) | \color1 | (2<<8)
	.ifc "","\label"
		PUSHSTRING "\r16="
	.else
		PUSHSTRING "\label="
	.endif
	pushw	0	# pad.
	pushw	\r16
	call	debug_printvalue
.endm

.macro DEBUG_DWORD r32, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
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
	call	debug_regstore$
.endm

.macro DEBUG_REGDIFF
	call	debug_regdiff$
.endm


.macro BREAKPOINT label
	pushf
	push 	eax
	PRINTC 0xf0, "\label"
	xor	eax, eax
	call	keyboard
	pop	eax
	popf
.endm



.else	# DEFINE = 1

.data SECTION_DATA_BSS
debug_registers$:	.space 4 * 32

.text32
nop # so that disasm doesnt point to code_debug_start


debug_regstore$:
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
	add	dword ptr [esp], 4 + 2 + 4
	.endif
	pushd	\nr
	PUSHSTRING "\reg"
	call	debug_regdiff0$
.endm

debug_regdiff$:
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
	DEBUG_REGDIFF0 8, cs
	DEBUG_REGDIFF0 9, ds
	DEBUG_REGDIFF0 10, es
	DEBUG_REGDIFF0 11, ss
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
.endif
