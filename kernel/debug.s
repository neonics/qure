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
	COLOR 0x0a
	PRINTLN " Ok"
.endm

.macro D c m
	PRINT_START \c
	.if \m ne al
	mov	al, \m
	.endif
	stosw
	PRINT_END
.endm

.macro I m
	D 0x09 '>'
	PRINTc 15 " \m"
	COLOR 7
.endm

.macro I2 m
	PRINTc 7 "\m"
.endm


.macro MORE
.if 1
	push	eax
	call	newline
	sub	[screen_pos], dword ptr 160
	PUSH_SCREENPOS
	PRINTc 0xf1, " --- More ---"
	xor	ah, ah
	call	keyboard
	POP_SCREENPOS
	PUSH_SCREENPOS
	PRINT "             "
	POP_SCREENPOS
	pop	eax
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


DEBUG_COLOR1 = 0x80
DEBUG_COLOR2 = 0x87
DEBUG_COLOR3 = 0x8f

.macro DEBUG str
	pushf
	printc DEBUG_COLOR3, "\str "
	popf
.endm

.macro DEBUGc c, str
	pushf
	printc (DEBUG_COLOR3 & 0xf0) | (\c & 0xf), "\str "
	popf
.endm

.macro DEBUGS reg=esi
	pushf
	pushcolor DEBUG_COLOR1
	PRINTCHAR '\''
	COLOR	DEBUG_COLOR2
	.if \reg == esi
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
	.if \r8 == dl
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
	.if \r16 != dx
	push	edx
	mov	dx, \r16
	call	printhex4
	pop	edx
	.else
	call	printhex4
	.endif
	call	printspace
	popcolor
	popf
.endm

.macro DEBUG_DWORD r32
	pushf
	pushcolor DEBUG_COLOR1
	print	"\r32="
	color	DEBUG_COLOR2
	.if \r32 != dx
	push	edx
	mov	edx, \r32
	call	printhex8
	pop	edx
	.else
	call	printhex8
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


