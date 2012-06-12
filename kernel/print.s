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

.macro PUSH_SCREENPOS
	push	dword ptr [screen_pos]
.endm

.macro POP_SCREENPOS
	pop	dword ptr [screen_pos]
.endm


# c:
# 0  : load ah with screen_color
# > 0: load ah with constant
# < 0: skip load ah. Note that ax will still be pushed.
.macro PRINT_START c=0, char=0
	push	ax
	push	es
	push	edi
	movzx	edi, word ptr [screen_sel]
	mov	es, edi
	mov	edi, [screen_pos]

	.if \c == 0
	mov	ah, [screen_color]
	.else
	mov	ah, \c
	.endif

	.if \char != 0
	xor	al, al
	.endif
#	.if \c > 0
#	mov	ah, \c
#	.else
#	.if \c == 0
#	mov	ah, [screen_color]
#	.endif
#	.endif
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

.macro PRINTSPACE
	call	printspace
.endm

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
	.if 1
	push	ax
	mov	al, \c
	call	printchar
	pop	ax
	.else
	PRINT_START
	mov	al, \c
	stosw
	PRINT_END
	.endif
.endm

.macro PRINTCHARc col, c
	PRINT_START -1
	mov	ax, (\col<<8) | \c
	stosw
	PRINT_END
.endm


###### Load String Pointer
.macro LOAD_TXT txt, reg = esi
	.data
		99: .asciz "\txt"
	.text
	mov	\reg, offset 99b
.endm

.macro PUSH_TXT txt
	.data 
		99: .asciz "\s"
	.text
	push	dword ptr offset 99b
.endm

# for printf
.macro PUSHSTRING s
	PUSH_TXT \s
.endm


# prints esi, not preserving it.
.macro PRINT_ msg
	.ifnes "\msg", ""
	LOAD_TXT "\msg"
	.endif
	call	print_
.endm


.macro PRINTSKIP_
91:	lodsb
	or	al, al
	jnz	91b
.endm

# like PRINT_, except the string is skipped when ZF=1, and printed when ZF=0
.macro PRINT_NZ_
	jz	99f;
	call	print_
	jmp	98f
99:	PRINTSKIP_
98:
.endm

.macro PRINT_Z_
	jnz	99f;
	call	print_
	jmp	98f
99:	PRINTSKIP_
98:
.endm



.macro PRINTLN_ msg
	LOAD_TXT "\msg"
	call	println
.endm


.macro PRINT msg
	push	esi
	PRINT_	"\msg"
	pop	esi
.endm


.macro PRINTLN msg
	push	esi
	PRINTLN_ "\msg"
	pop	esi
.endm

.macro PRINTc_ color, str
	pushcolor \color
	PRINT_ "\str"
	popcolor
.endm

.macro PRINTLNc_ color, str
	pushcolor \color
	PRINTLN_ "\str"
	popcolor
.endm

.macro PRINTc color, str
	pushcolor \color
	PRINT "\str"
	popcolor
.endm

.macro PRINTLNc color, str
	pushcolor \color
	PRINTLN "\str"
	popcolor
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
# in: ecx = num hex digits, edx = value
nprinthex:
	push	ecx
	and	ecx, 63
	jz	0f
	shl	ecx, 2
	rol	edx, cl
	shr	ecx, 2
	jmp	1f
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
0:	mov	ecx, 8
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
push edi
push edx
mov edx, edi
mov edi, 80
push eax
mov ah, 0xe0
call __printhex8
pop eax
pop edx
pop edi
	pop	ds
	pop	ecx
	pop	esi

0:	ret

############################## PRINT ASCII ####################

printspace:
	PRINT_START 0, 1
	stosw
	PRINT_END
	ret

printchar:
	PRINT_START
	stosw
	PRINT_END
	ret

printchar_:
	push	ax
	lodsb
	PRINT_START
	stosw
	PRINT_END
	pop	ax
	ret

nprintln:
	call	nprint
	jmp	newline

# in: esi = string
# in: ecx = max len
nprint:	or	ecx, ecx
	jz	1f
	PRINT_START
	push	esi
	push	ecx
0:	lodsb
	or	al, al
	jz	0f
	stosw
	loop	0b
0:	pop	ecx
	pop	esi
	PRINT_END
1:	ret

.global println
println:call	print
	jmp	newline
#println:push	offset newline

.global print
print:	PRINT_START
	push	esi
	jmp	1f

0:	stosw
1:	lodsb
	test	al, al
	jnz	0b

	pop	esi
	PRINT_END
	ret

print_:
	PRINT_START
	jmp	1f
0:	stosw
1:	lodsb
	test	al, al
	jnz	0b
	PRINT_END
	ret
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

printdec8:
	push	edx
	movzx	edx, dl
	call	printdec32
	pop	edx
	ret

# unsigned 32 bit print
printdec32:
	PRINT_START
	call	__printdec32
	PRINT_END
	ret

# unsigned 32 bit print
__printdec32:
	push	edx
	push	eax
	push	ebx
	push	ecx

	or	edx, edx
	jns	0f
	neg	edx
	mov	al, '-'
	stosw
0:

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
	pop	ebx
	pop	eax
	pop	edx

	ret

#############################################################################
# Fixed Point

# in: edx:eax = 32.32 fixed point
# in: bl = digits afer '.' to print
# destroys: bl
print_fixedpoint_32_32$:
	push	eax
	push	edx

	call	printdec32
	or	eax, eax
	jz	1f

	printchar '.'	# i18n
	push	ecx
	mov	ecx, 10
0:	mul	ecx
	call	printdec32
	dec	bl
	jnz	0b
	pop	ecx
1:
	pop	edx
	pop	eax
	ret

print_fixedpoint_32_32:
	push	ebx
	mov	bl, 3
	call	print_fixedpoint_32_32$
	pop	ebx
	ret

##############################################################################
# Byte-Size (kb, Mb, Gb etc)

print_size:
	push	eax
	push	edx


	or	edx, edx
	jnz	1f
	cmp	eax, 1024
	jae	1f

	mov	edx, eax
	call	printdec32
	mov	al, 'b'
	call	printchar
	jmp	2f

1:	
	shr	edx, 1
	sar	eax, 1
	shr	edx, 1
	sar	eax, 1
	mov	al, dl
	shr	edx, 8
	ror	eax, 8

	call	print_size_kb

2:	pop	edx
	pop	eax
	ret

# in: edx:eax = size in kilobytes to print
# destroys: edx, eax
print_size_kb:
	push	eax
	push	edx
	push	esi

	# check 1Mb limit:
	or	edx, edx
	jnz	1f	# nope
	cmp	eax, 1024	# check 1Mb
	jae	2f
	# print it in kb
	xchg	edx, eax
	LOAD_TXT "kb"
	jmp	3f
2:	cmp	eax, 1024*1024	# check 1Gb
	jae	2f
	LOAD_TXT "Mb"
	mov	edx, eax
	shr	edx, 10
	shl	eax, 10
	jmp	3f
2:	cmp	eax, 1024*1024*1024	# 30 bits, check 1Tb
	jae	2f
	LOAD_TXT "Gb"
	mov	edx, eax
	shr	edx, 20
	shl	eax, 20
	jmp	3f
2:	LOAD_TXT "Tb"
	shl	eax, 1
	sal	edx, 1
	shl	eax, 1
	sal	edx, 1
	jmp	3f

##### edx != 0
1:	cmp	edx, 1024 / 4	# check Pb
	jb	2b
	LOAD_TXT "Pb"
	shr	edx, 1
	sar	eax, 1
	shr	edx, 1
	sar	edx, 1

3:	call	print_fixedpoint_32_32
	call	print
	pop	esi
	pop	edx
	pop	eax
	ret


############################ PRINT FORMATTED STRING ###########

# in: esi, stack
printf:
	push	ebp
	mov	ebp, esp
	add	ebp, 4 + 4
	push	eax
	push	ecx
	push	edx
	push	esi

	mov	esi, [ebp]
	add	ebp, 4

2:	xor	ecx, ecx	# holds width etc..
	lodsb
	or	al, al
	jz	2f

###########################
0:	# %
	cmp	al, '%'
	jne	0f
		PRINTc	10, "%"
	lodsb
	or	al, al
	jz	2f
		pushcolor 10
		call	printchar
		popcolor

	# check for flags:
	# specifier: (rest of specifiers checked later)
	cmp	al, '%'
	je	3f
	# flags: - + ' ' # 0
	cmp	al, '-'
	jne	1f
	jmp	4f
1:	cmp	al, '+'
	jne	1f
	jmp	4f
1:	cmp	al, '#'
	jne	1f
	jmp	4f
1:	cmp	al, ' '
	jne	1f
	jmp	4f
1:	cmp	al, '0'
	jne	1f

4:	lodsb
	or	al, al
	jz	2f

	#############
	# width TODO (just gobbles up)
1:	cmp	al, '1'
	jb	1f
	cmp	al, '9'
	ja	1f
	# TODO: process char..
	jmp	4b

1:	cmp	al, '*' 	# width specifier
	jne	1f
	mov	ecx, [ebp]
	add	ebp, 4
		pushcolor 11
		mov edx, ecx
		call printhex8
		popcolor
	lodsb
	or	al, al
	jz	2f
1:
	########
	# precision
	cmp	al, '.'
	jne	1f
	PRINTc	12, "."
4:	lodsb
	or	al, al
	jz	2f
	call printchar
	cmp	al, '*'
	jne	5f
	mov	ecx, [ebp]
		pushcolor 11
		mov edx, ecx
		call printhex8
		popcolor
	add	ebp, 4
	jmp	4f
5:
	cmp	al, '1'
	jb	1f
	cmp	al, '9'
	ja	1f
	# todo: process char
	jmp	4b

4:	lodsb
	or	al, al
	jz	2f
1:
	# length
	cmp	al, 'h'
	je	4f
	cmp	al, 'l'
	je	4f
	cmp	al, 'L'
	je	4f
	jmp	1f

4:	lodsb
	or	al, al
	jz	2f

1:	
	PRINTc	11, ">"
	call printchar
	PRINTc	11, "<"
	
	mov	edx, [ebp]
	add	ebp, 4

	mov	ah, al		# backup
	and	ah, 0x20	# the lowercase bit
	or	al, 0x20	# a 'tolowercase' hack (may fail if al!=alpha)

	cmp	al, 'x'	# todo: X
	jne	1f
	call	nprinthex
	jmp	2b
1:	cmp	al, 'd'	# todo: i
	jne	1f
	call	printdec32
	jmp	2b
1:	cmp	al, 'b'	# nonstandard
	jne	1f
	call	printbin8
	jmp	2b
1:	cmp	al, 's'
	jne	1f
	push	esi
	mov	esi, edx
	or	ecx, ecx
	jz	4f
	call	nprint
	jmp	5f
4:	call	print
5:	pop	esi
	jmp	0b
1:	# todo: c i e E f g G o s u X p n
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
	jne	0f
	lodsb
	or	al, al
	jz	2f
	cmp	al, 'n'
	je	1f
	call	newline
	jmp	2b

1:	cmp	al, 'r'	# ignore
	jne	1f

1:	# print unsupported escape 

0:	# the compiler already escapes \ characters, so we'll check
	# for the literal:
	cmp	al, '\n'
	jne	1f
	call	newline
	jmp	2b
1:


0:
	.if 0
	pushcolor 6
	mov	dl, al
	call	printhex2
	popcolor
	.endif
3:	call	printchar
###########################
	jmp	2b
2:	
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	pop	ebp
	ret

.endif
