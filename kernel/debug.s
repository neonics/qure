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
.if 1
	pushf
	sti
	push	eax
	call	newline
	call	newline
	sub	[screen_pos], dword ptr 160
	PUSH_SCREENPOS
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
.else
	call	newline
	PRINT_START 0xf1
	LOAD_TXT " --- More --- "
	call	__println
	PRINT_END -1
	xor	ah, ah
	call	keyboard
	PRINT_START
	LOAD_TXT "              "
	call	__print
	PRINT_END -1

.endif
.endm


DEBUG_COLOR1 = 0x1a
DEBUG_COLOR2 = 0x17
DEBUG_COLOR3 = 0x1f

.macro DEBUG str
	.ifnes "\str", ""
	pushf
	printc DEBUG_COLOR3, "\str "
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


.macro DEBUG_BYTE r8
	pushf
	pushcolor DEBUG_COLOR1
	print	"\r8="
	color	DEBUG_COLOR2
	.ifc dl,\r8
	call	printhex2
	.else
	push	edx
	mov	dl, \r8
	call	printhex2
	pop	edx
	.endif
	call	printspace
	popcolor
	popf
.endm

.macro DEBUG_WORD r16
	pushf
	pushcolor DEBUG_COLOR1
	print	"\r16="
	color	DEBUG_COLOR2
	.ifc dx,\r16
	call	printhex4
	.else
	push	edx
	mov	dx, \r16
	call	printhex4
	pop	edx
	.endif
	call	printspace
	popcolor
	popf
.endm

.macro DEBUG_DWORD r32, label=""
	pushf
	pushcolor DEBUG_COLOR1
	.ifc "","\label"
	print	"\r32="
	.else
	print	"\label="
	.endif
	color	DEBUG_COLOR2
	.ifc	edx,\r32
	call	printhex8
	.else
	push	edx
	.ifc esp,\r32
	lea	edx, [esp + 8 + COLOR_STACK_SIZE]
	.else
	mov	edx, \r32
	.endif
	call	printhex8
	pop	edx
	.endif
	call	printspace
	popcolor
	popf
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


