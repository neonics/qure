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
	sti
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
	IS_REG8 _, \r8
	.if _
		GET_REG32 _, \r8
		pushd	_
	.else
		push	edx
		mov	dl, \r8
		xchg	dl, [esp]
	.endif
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
	push	\r16
	call	debug_printvalue
.endm

.macro DEBUG_DWORD r32, label="", color1=DEBUG_COLOR1, color2=DEBUG_COLOR2
	pushd	(\color2 << 16) | \color1 | (4<<8)
	.ifc "","\label"
		PUSHSTRING "\r32="
	.else
		PUSHSTRING "\label="
	.endif
	IS_REG32 _, \r32
	.if _
		pushd	\r32
	.else
		push	edx
		mov	edx, \r32
		xchg	edx, [esp]
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


.else	# DEFINE = 1


.text32
nop # so that disasm doesnt point to code_debug_start
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
