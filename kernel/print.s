.intel_syntax noprefix

###############################################################################
###### Declaration: macros ####################################################
###############################################################################
###############################################################################
###############################################################################
.ifndef PRINT_32_DECLARED
PRINT_32_DECLARED = 1
###################### 32 bit macros



################# Colors ###############

.macro COLOR c
	mov	[screen_color], byte ptr \c
.endm

.macro PUSHCOLOR c
	push	word ptr [screen_color]
	mov	[screen_color], byte ptr c
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

.macro PRINT_START
	push	ax
	push	es
	push	edi
	mov	di, [screen_sel]
	mov	es, di
	mov	edi, [screen_pos]
	mov	ah, [screen_color]
.endm

.macro PRINT_END
	mov	[screen_pos], edi
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


.macro	PRINT a
	.data
	9: .asciz "\a"
	.text
	push	esi
	mov	esi, offset 9b
	call	print
	pop	esi
.endm


.macro PRINTLN a
	.data
	9: .asciz "\a"
	.text
	push	esi
	mov	esi, offset 9b
	call	println
	pop	esi
.endm

.macro PRINTc color, str
	COLOR \color
	PRINT	"\str"
.endm

.macro PRINTLNc color, str
	COLOR \color
	PRINTLN "\str"
.endm
####################


.macro PH8 m, r
	push	edx
	.if \r != edx
	mov	edx, \r
	.endif
	push	ax
	mov	ah, 0xf0
	PRINT "\m" 
	call	printhex8
	add	di, 2
	pop	ax
	pop	edx
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


##################### Loading a string pointer ##############

.macro LOAD_TXT txt
	.data
	9: .asciz "\txt"
	.text
	mov	esi, offset 9b
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

####################### PRINT HEX ########################

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
1:	print_start
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'a' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	add	edi, 2
	print_end
	pop	ecx
	ret

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
	add	edi, 2
	pop	ecx
	ret


########################### CLEAR SCREEN, NEW LINE, SCROLL ##########

.global cls
# in: ax: ah = color, al = char
cls:	push	ax
	push	es
	push	edi
	push	ecx

	mov	di, SEL_vid_txt
	mov	es, di
	xor	edi, edi
	mov	[screen_pos], edi
	mov	ecx, 80 * 25 # 7f0
	rep	stosw

	pop	ecx
	pop	edi
	pop	es
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
	pop	ax
	ret

############################## PRINT ASCII ####################

.global println
println:call	print
	jmp	newline


.global print
print:	PRINT_START
	jmp	1f

0:	stosw
1:	lodsb
	test	al, al
	jnz	0b

	PRINT_END
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


printdec8:	# UNTESTED
	push	eax
	push	ebx
	push	edx
	push	ecx
	mov	bh, ah
	mov	ecx, 10

	xor	eax, eax
	xchg	edx, eax

0:	div	ecx

	mov	bl, dl
	add	bl, '0'
	mov	es:[edi], bx
	add	edi, 2

	or	eax, eax
	jnz	0b
	

	pop	ecx
	pop	edx
	pop	ebx
	pop	eax
	ret

############################ PRINT FORMATTED STRING ###########

# in: esi, stack
_printf:
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
	call	printdec8
	jmp	2b
1:	cmp	al, 'b'
	jne	1f
	call	printbin8
	jmp	2b
1:	cmp	al, 's'
	jne	1f
	push	esi
	mov	esi, edx
	call	print
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
