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


########################## 16 bit macros

.macro PRINT_START_16
	push	es
	push	di
	push	ax
	mov	ax, 0xb800
	mov	es, ax
	mov	di, [screen_pos]
	mov	ah, [screen_color]
.endm

.macro PRINT_END_16
	mov	[screen_pos], di
	pop	ax
	pop	di
	pop	es	
.endm


.macro PRINT_16 m
	.data
		9:.asciz "\m"
	.text
	push	si
	mov	si, offset 9b
	call	print_16
	pop	si
.endm


.macro PRINTLN_16 m
	PRINT_16 "\m"
	call	newline_16
.endm


.macro PH8_16 m x
	PRINT_16 "\m"
	.if \x != edx
	push	edx
	mov	edx, \x
	pop	edx
	.endif
	call	printhex8_16
.endm


.macro rmCOLOR c
	mov	[screen_color], byte ptr \c
.endm


.macro rmD a b
	PRINT_START_16
	mov	ax, (\a << 8 ) + \b
	stosw
	PRINT_END_16
.endm


.macro rmW
	D 0x2f '?'
	push	ax
	xor	ah, ah
	int	0x16
	pop	ax
.endm


.macro rmH
	D 0x4f 'H'
9:	hlt
	jmp 9b
.endm


.macro rmPC c m
	rmCOLOR \c
	PRINT_16 "\m"
.endm


.macro rmI m
	rmD 0x09 '>'
	rmPC 0x07 " \m"
.endm


.macro rmI2 m
	rmPC 0x08 "\m"
.endm


.macro rmOK
	rmCOLOR 0x0a
	PRINTLN_16 " Ok"
.endm

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
	PRINTc 7 " \m"
.endm

.macro I2 m
	PRINTc 8 "\m"
.endm

