.intel_syntax noprefix
# This file assumes ds = SEL_compatDS and uses that to read
# [screen_(sel|pos|color)]. Using any SEL_ constant here will result
# in gas treating it as a memory reference, generating a GPF.
###############################################################################
###### Declaration: macros ####################################################
###############################################################################
###############################################################################
###############################################################################
.ifndef PRINT_32_DECLARED
PRINT_32_DECLARED = 1

# Include GDT selectors
#TMP = DEFINE
#DEFINE = 0
#.include "gdt.s"
#DEFINE = TMP


###################### 32 bit macros
HEX_END_SPACE = 0	# whether to follow hex print with a space 
			# transitional - temporary!


################# Colors ###############

.macro COLOR c
	mov	byte ptr [screen_color], \c
.endm

.macro PUSHCOLOR c
	push	word ptr [screen_color]
	mov	byte ptr [screen_color], \c
.endm

.macro POPCOLOR c
	pop	word ptr [screen_color]
.endm



#################### Position ####################

.macro SCREEN_INIT
	mov	di, SEL_vid_txt
	mov	es, di
	xor	edi, edi
.endm

.macro SCREEN_OFFS x, y
	o =  2 * ( \x + 80 * \y )
	.if o == 0
	xor	edi, edi
	.else
	mov	edi, o
	.endif
.endm


# c:
# 0  : load ah with screen_color
# > 0: load ah with constant
# < 0: skip load ah. Note that ax will still be pushed.
.macro PRINT_START c=0, cregsize=2
	push	ax
	push	es
	push	edi
	movzx	edi, word ptr [screen_sel]
	mov	es, edi
	mov	edi, [screen_pos]
	.if \c > 0
	mov	ah, \c
	.else
	.if \c == 0
	mov	ah, [screen_color]
	.endif
	.endif
.endm

# flags:
# 01: do not store position
# 10: do not perform scroll check - only applies when flags & 01 = 00
.macro PRINT_END ignorepos=0 noscroll=0
	.if \ignorepos
	.else
	
	.if \noscroll
	.else
	cmp	edi, 160 * 25 + 2
	jb	99f
	call	__scroll
	99:	
	.endif

	mov	[screen_pos], edi
	.endif

	pop	edi
	pop	es
	pop	ax
.endm


################ Printing #################

.macro PRINTHEX r
	.if \r eq dx
	call	printhex
	.else
	push	dx
	mov	dx, \r
	call	printhex
	pop	dx
	.endif
.endm

.macro PRINTCHAR c
	PRINT_START
	mov	al, \c
	stosw
	PRINT_END
.endm

.macro PRINTCHARc col, c
	PRINT_START -1
	mov	ax, (\col<<8) | \c
	stosw
	PRINT_END
.endm


###### Load String Pointer
.macro LOAD_TXT txt
	.data
		99: .asciz "\txt"
	.text
	mov	esi, offset 99b
.endm


.macro	PRINT msg
	push	esi
	LOAD_TXT "\msg"
	call	print
	pop	esi
.endm


.macro PRINTLN msg
	push	esi
	LOAD_TXT "\msg"
	call	println
	pop	esi
.endm

.macro PRINTc color, str
	PRINT_START \color
	push	esi
	LOAD_TXT "\str"
	call	__print
	pop	esi
	PRINT_END
.endm

.macro PRINTLNc color, str
	PRINT_START \color
	push	esi
	LOAD_TXT "\str"
	call	__println
	pop	esi
	PRINT_END
.endm
####################


.macro PH8 m, r
	.if \r != edx
	push	edx
	mov	edx, \r
	.endif
	PRINT "\m" 
	call	printhex8
.if HEX_END_SPACE
	add	di, 2
.endif
	.if \r != edx
	pop	edx
	.endif
.endm


############################## debug ####################
.macro DBGSO16 msg, seg, offs
	mov	ah, 0xf0
	PRINT	"\msg"
	mov	dx, \seg
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	dx, \offs
	call	printhex
.endm

.macro DBGSTACK16 msg, offs
	PRINT	"\msg"
	mov	bp, sp
	mov	dx, [bp + offs]
	call	printhex
.endm


.endif
###############################################################################
###############################################################################
###### Definitions: implementation ############################################
###############################################################################
###############################################################################
###############################################################################
.ifdef DEFINE


.data
	screen_pos:	.long 0
	screen_color:	.word 0x0f	# is a byte, but word for push/pop
	screen_sel:	.word 0
.text


.text
.code32

# Methods starting with __ are to be called only when es:edi and ah are
# set up - between PRINT_START and PRINT_END.

####################### PRINT HEX ########################

printhex1:
	push	ecx
	mov	ecx, 1
	rol	edx, 28
	jmp	1f
printhex2:
	push	ecx
	mov	ecx, 2
	rol	edx, 24
	jmp	1f
printhex4:
printhex:
	push	ecx
	mov	ecx, 4
	rol	edx, 16
	jmp	1f
printhex8:
	push	ecx
	mov	ecx, 8
1:	PRINT_START
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'a' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
.if HEX_END_SPACE
	add	edi, 2
.endif
	PRINT_END
	pop	ecx
	ret

__printhex4:
	push	ecx
	mov	ecx, 4
	rol	edx, 16
	jmp	0f
__printhex8:
	push	ecx
	mov	ecx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'a' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
.if HEX_END_SPACE
	add	edi, 2
.endif
	pop	ecx
	ret


########################### CLEAR SCREEN, NEW LINE, SCROLL ##########

.global cls
cls:	PRINT_START
	push	ecx
	xor	edi, edi
	xor	al, al
	mov	[screen_pos], edi
	mov	ecx, 80 * 25 # 7f0
	rep	stosw
	pop	ecx
	PRINT_END 1
	ret

__newline:
	push	ax
	push	dx
	mov	ax, di
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	di, ax
	pop	dx
	pop	ax
	ret

.global newline
newline:
	push	ax
	push	dx
	mov	ax, [screen_pos]
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	[screen_pos], ax
	pop	dx
	cmp	ax, 160 * 25 + 2
	pop	ax
	jb	0f
	PRINT_START -1
	PRINT_END
0:	ret

__scroll:
	push	esi
	push	ecx
	push	ds

	mov	esi, es
	mov	ds, esi

	mov	ecx, edi
	mov	esi, 160
	xor	edi, edi
	sub	ecx, esi
	push	ecx
	rep	movsd
	pop	edi

	pop	ds
	pop	ecx
	pop	esi

0:	ret

############################## PRINT ASCII ####################

printchar:
	PRINT_START
	stosw
	PRINT_END
	ret

# in: esi = string
# in: ecx = max len
nprint:	or	ecx, ecx
	jz	1f
	PRINT_START
	push	ecx
0:	lodsb
	or	al, al
	jz	0f
	stosw
	loop	0b
0:	pop	ecx
	PRINT_END
1:	ret

.global println
println:call	print
	jmp	newline
#println:push	offset newline

.global print
print:	PRINT_START
	jmp	1f

0:	stosw
1:	lodsb
	test	al, al
	jnz	0b

	PRINT_END
	ret

__println:
	call	__print
	jmp	__newline

0:	stosw
__print:	
1:	lodsb
	test	al, al
	jnz	0b
	ret


######################### PRINT BINARY ####################
printbin32:
	push	ecx
	mov	ecx, 32
	jmp	0f
printbin16:
	push	ecx
	mov	ecx, 16
	rol	edx, 16
	jmp	0f
printbin4:
	push	ecx
	mov	ecx, 4
	rol	edx, 28
	jmp	0f
	jmp	0f
printbin8:
	push	ecx
	mov	ecx, 8
	rol	edx, 24

0:	PRINT_START

0:	mov	al, '0'
	rol	edx, 1
	adc	al, 0
	stosw
	loop	0b

	PRINT_END
	pop	ecx
	ret


############################ PRINT DECIMAL ####################

# unsigned 32 bit print
printdec32:	# UNTESTED
	PRINT_START

	push	eax
	push	ebx
	push	edx
	push	ecx

	mov	bh, ah
	mov	ecx, 10

	xor	eax, eax
	xchg	edx, eax

	push	dword ptr -1	# stack marker (no need for counter then)

0:	div	ecx

	mov	bl, dl
	add	bl, '0'

	push	ebx

	#mov	es:[edi], bx
	#add	edi, 2

	xor	edx, edx

	or	eax, eax
	jnz	0b

	# print loop
0:	pop	eax
	cmp	eax, -1
	jz	1f
	stosw
	jmp	0b
1:

	pop	ecx
	pop	edx
	pop	ebx
	pop	eax

	PRINT_END
	ret

############################ PRINT FORMATTED STRING ###########

# in: esi, stack
__printf:
	push	ebp
	mov	ebp, esp
	add	ebp, 4 + 4
	push	edx

2:	lodsb
	or	al, al
	jz	2f

###########################
0:	# %
	cmp	al, '%'
	jne	0f

	lodsb
	mov	edx, [ebp]
	add	ebp, 4

	cmp	al, 'x'
	jne	1f
	call	printhex8
	jmp	2b
1:	cmp	al, 'd'
	jne	1f
	call	printdec32
	jmp	2b
1:	cmp	al, 'b'
	jne	1f
	call	printbin8
	jmp	2b
1:	cmp	al, 's'
	jne	1f
	push	esi
	mov	esi, edx
	call	__print
	pop	esi
	jmp	0b
1:
	push	ax
	mov	ah, 0xf4
	mov	al, '<'
	stosw
	mov	al, '?'
	stosw
	mov	al, '>'
	stosw
	pop	ax
	jmp	2b


###########################
0:	# Escape
	cmp	al, '\\'
	jne	1f
	lodsb
	or	al, al
	jz	2f
	cmp	al, 'n'
	je	1f
	call	newline
	jmp	0b

1:	cmp	al, 'r'	# ignore
	jne	1f

###########################
	jmp	2b
2:	pop	edx
	pop	ebp
	ret

.endif
