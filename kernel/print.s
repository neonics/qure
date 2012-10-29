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

COLOR_STACK_SIZE = 2

.macro PUSHCOLOR c
	.if COLOR_STACK_SIZE == 2
	push	word ptr [screen_color]
	.else
	.error "COLOR_STACK_SIZE unknown value"
	.endif
	mov	byte ptr [screen_color], \c
.endm

.macro POPCOLOR c=0
	.if COLOR_STACK_SIZE == 2
	pop	word ptr [screen_color]
	.else
	.error "COLOR_STACK_SIZE unknown value"
	.endif
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

.macro PUSH_SCREENPOS newval=-1
	push	dword ptr [screen_pos]
	.ifnc -1,\newval
	mov	dword ptr [screen_pos], \newval
	.endif
.endm

.macro POP_SCREENPOS
	pop	dword ptr [screen_pos]
.endm


# c:
# 0  : load ah with screen_color
# > 0: load ah with constant
# < 0: skip load ah. Note that ax will still be pushed.
.macro PRINT_START c=0, char=0
900:MUTEX_LOCK SCREEN, 900b
	push	ax
	pushf	# prevent interrupts during es != ds
	cli
	cld
	push	es
	push	edi
	movzx	edi, word ptr [screen_sel]
	mov	es, edi
	mov	edi, [screen_pos]

	.ifc ah,\c
	.elseif \c == 0
	mov	ah, [screen_color]
	.else
	mov	ah, \c
	.endif

	.if \char
	mov	al, \char
	.endif
#	.if \c > 0
#	mov	ah, \c
#	.else
#	.if \c == 0
#	mov	ah, [screen_color]
#	.endif
#	.endif
.endm


.macro PRINT_START_ c=0, char=0
900:MUTEX_LOCK SCREEN 900b
	pushf	# prevent interrupts during es != ds
	cli
	cld
	push	es
	push	edi
	movzx	edi, word ptr [screen_sel]
	mov	es, edi
	mov	edi, [screen_pos]

	.ifc ah,\c
		mov	al, \char
	.elseif \c == 0
		mov	ah, [screen_color]
		mov	al, \char
	.else
		.if \c < 0
		# do not update ax
		.else
		mov	ax, (\c << 8) | \char
		.endif
	.endif
.endm

# flags:
# 01: do not store position
# 10: do not perform scroll check - only applies when flags & 01 = 00
.macro PRINT_END_ ignorepos=0 noscroll=0
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

	.if 1 # NEW!
		mov	edi, [realsegflat]
		add	edi, [screen_update]
		call	edi
	.endif

	pop	edi
	pop	es
MUTEX_UNLOCK SCREEN
	popf
.endm


.macro PRINT_END ignorepos=0 noscroll=0
	PRINT_END_ \ignorepos, \noscroll
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

.macro sPRINTCHAR c
	mov	[edi], byte ptr \c
	inc	edi
.endm

# does not preserve ax
.macro PRINTCHAR_ c
	mov	al, \c
	call	printchar
.endm

.macro GET_INDEX name, values:vararg
	_INDEX=-1
	_I=0

	.irp r,\values
		.ifc \r,\name
		_INDEX=_I
		.exitm
		.endif
		_I=_I+1
	.endr
.endm

.macro IS_REG8 var, val
	GET_INDEX \val, al,ah,bl,bh,cl,ch,dl,dh
	\var=_INDEX >=0
.endm

.macro PRINTCHARc col, c
	push	ax
	IS_REG8 _IS_REG8, \c
	.if _IS_REG8
	mov	ah, \col
	mov	al, \c
	.else
	mov	ax, (\col<<8) | \c
	.endif
	call	printcharc
	pop	ax
.endm

# does not preserve ax
.macro PRINTCHARc_ col, c
	IS_REG8 _IS_REG8, \c
	.if _IS_REG8
	mov	ah, \col
	mov	al, \c
	.else
	mov	ax, (\col<<8) | \c
	.endif
	call	printcharc
.endm

###### Load String Pointer
.macro LOAD_TXT txt, reg = esi
	.data SECTION_DATA_STRINGS
		99: .asciz "\txt"
	.text32
	mov	\reg, offset 99b
.endm

.macro PUSH_TXT txt
	.data SECTION_DATA_STRINGS
		99: .asciz "\txt"
	.text32
	push	dword ptr offset 99b
.endm

# for printf
.macro PUSHSTRING s
	PUSH_TXT \s
.endm


# call from .data
.macro STRINGPTR n
	.data SECTION_DATA_STRINGS
	99: .asciz "\n"
	.data
	.long 99b
.endm

# call from .data
.macro STRINGNULL
	.data
	.long 0
.endm


# prints esi, not preserving it.
.macro PRINT_ msg
	.ifnes "\msg", ""
	LOAD_TXT "\msg"
	.endif
	call	print_
.endm

.macro PRINTS_
	call	print_
.endm

.macro PRINTLNS_
	call	println_
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
	LOAD_TXT "\msg"
	call	print_
	pop	esi
.endm

.macro SPRINT msg
	push	esi
	LOAD_TXT "\msg"
	call	sprint
	pop	esi
.endm

.macro PRINTLN msg
	push	esi
	LOAD_TXT "\msg"
	call	println_
	pop	esi
.endm

.macro PRINTc_ color, str
  .if 0
  	DEBUG_DWORD esp
  	push	word ptr \color # 
	PUSH_TXT "\str"
	call	_s_printc
  .else
	pushcolor \color
	PRINT_ "\str"
	popcolor
  .endif
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


.macro PRINTFLAG reg, bit, msg, altmsg=""
	test	\reg, \bit
	jz	111f
	PRINT	"\msg"
	jmp	112f
111:
	PRINT	"\altmsg"
112:
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


.data16	# realmode access, keep within 64k
	screen_color:	.word 0x0f	# is a byte, but word for push/pop
	screen_pos:	.long 0
	screen_sel:	.word 0
	screen_update:	.long default_screen_update
.text32
default_screen_update:	# 16 and 32 bit
	ret

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
	PRINT_START -1
	PRINT_END
	ret

.global newline
newline:
	push	ax
	push	dx
				push	ecx
	mov	ax, [screen_pos]
				movzx	ecx, ax
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	[screen_pos], ax
				jcxz	2f
				push	edi
				push	es
				mov	edi, [screen_sel]
				mov	es, edi
				movzx	edi, cx
				sub	cx, ax
				neg	ecx
				movzx	ecx, cx
				shr	ecx, 1
				jz	1f
				mov	ax, es:[edi-2]
				xor	al, al
				rep	stosw
			1:	pop	es
				pop	edi
			2:	pop	ecx
	pop	dx
	cmp	ax, 160 * 25 + 2
	pop	ax
	jb	0f
	PRINT_START -1
	PRINT_END
0:	ret


##### SCROLLBACK BUFFER ######
SCREEN_BUFFER = 1
.if SCREEN_BUFFER
.data SECTION_DATA_BSS # TODO: objectify: convert to array of struct - multiple buffers.
SCREEN_BUF_PAGES = 12
SCREEN_BUF_SIZE = 160 * 25 * SCREEN_BUF_PAGES
screen_buf_offs:	.long 0
screen_buf:		.space SCREEN_BUF_SIZE
screen_scroll_lines:	.long 0	# total count
.text32
.endif
##############################
# this method is only to be called when edi > 160 * 25
__scroll:
	push	esi
	push	ecx
	push	ds

	.if SCREEN_BUFFER
	# |bufA  |      |bufB_|
	# |bufB__|	|A____|
	#  _____	 _____
	# |A____|	|B____|
	# |B____|	|C____|
	# |C____|	|D____|
	# |D____|abc#	|abc#_|

		# edi = # (left)
		push eax
		push edx
		xor	edx, edx
		mov	eax, edi
		sub	eax, 160 * 25
		jle	1f
		add	eax, 159

		# eax = len(abc)
		# calculate nr of lines
		mov	ecx, 160
		div	ecx
		add	[screen_scroll_lines], eax
		mul	ecx
		mov	ecx, eax

		# shift the buffer
		push	esi
		push	edi
		push	es
		mov	esi, ds
		mov	eax, es
		mov	es, esi
		mov	edi, offset screen_buf
		lea	esi, [edi + 160]
		push	ecx
		neg	ecx
		add	ecx, SCREEN_BUF_SIZE
		rep	movsb
		pop	ecx
		# es:edi = ok
		# ecx = ok
		# ds:esi:
		mov	ds, eax	# no need to restore - is altered right below
		mov	esi, 160 * 24
		sub	edi, ecx
		rep	movsb
		pop	es
		pop	edi
		pop	esi
	1:
		pop edx
		pop eax
	.endif


	mov	esi, es
	mov	ds, esi

	mov	ecx, edi
	mov	esi, 160
	xor	edi, edi
	sub	ecx, esi
	push	ecx
	shr	ecx, 1
	rep	movsd
	pop	edi

	pop	ds
	pop	ecx
	pop	esi

0:	ret

############################## PRINT ASCII ####################

printspace:
	PRINT_START 0, ' '
	stosw
	PRINT_END
	ret

printchar:
	PRINT_START
	stosw
	PRINT_END
	ret

.if 0
printchar_:
	push	ax
	lodsb
	PRINT_START_
	stosw
	PRINT_END_
	pop	ax
	ret
.endif

.if 0
# in: [esp] = offset
# in: [esp + 4] = color (word)
# out: clear stack arguments
_s_printc:
	push	esi
	push	eax
	mov	esi, [esp + 8 + 4 + 0]
	mov	ah, [esp + 8 + 4 + 4]
	call	printc
	pop	eax
	pop	esi
	ret	4 + COLOR_STACK_SIZE

_s_printcharc:
	push	eax
	mov	ah, [esp + 4 + 4 + 0]
	call	printcharc
	pop	eax
	ret	COLOR_STACK_SIZE
.endif

printcharc:
	PRINT_START_ -1
	stosw
	PRINT_END_
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
printlnc:
	call	printc
	jmp	newline

# in: ah = color
# in: esi = string
printc:	PRINT_START c=ah
	push	esi
	jmp	1f
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

sprint:	push	esi
	jmp	1f

0:	stosb
1:	lodsb
	test	al, al
	jnz	0b

	pop	esi
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

println_:
	call	print_
	jmp	newline

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
printbin2:
	push	ecx
	mov	ecx, 2
	rol	edx, 30
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

# identical except uses stosb
sprintdec32:
	push	edx
	push	eax
	push	ebx
	push	ecx

	or	edx, edx
	jns	0f
	neg	edx
	mov	al, '-'
	stosb
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

	xor	edx, edx
	or	eax, eax
	jnz	0b

	# print loop
0:	pop	eax
	cmp	eax, -1
	jz	1f
	stosb
	jmp	0b
1:	mov	[edi], byte ptr 0
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

###########################################
# in: bl = digits
sprint_fixedpoint_32_32$:
	push	eax
	push	edx

	call	sprintdec32
	or	eax, eax
	jz	1f

	sprintchar '.'	# i18n
	push	ecx
	mov	ecx, 10
0:	mul	ecx
	call	sprintdec32
	dec	bl
	jnz	0b
	pop	ecx
1:
	pop	edx
	pop	eax
	ret

sprint_fixedpoint_32_32:
	push	ebx
	mov	bl, 3
	call	sprint_fixedpoint_32_32$
	pop	ebx
	ret


##############################################################################
# Byte-Size (kb, Mb, Gb etc)

# in: edx:eax = 64 bit byte-size
# out: esi = size string (Xb, Pb, Tb, Gb, Mb, Kb, b)
# out: edx:eax = 32.32 fixed point
# destroys: cl
calc_size:
	# approach:
	# have edx be the main component (b, Kb, Mb, Gb, Tb, Pb, Exa, Zetta, Yotta)
	# have eax be the fixed point

	LOAD_TXT "Xb\0Pb\0Tb\0Gb\0Mb\0Kb\0b"
	mov	cl, 28	# Exabytes
	cmp	edx, 1 << (60-32)
	jae	8f

	add	esi, 3	# Petabytes
	mov	cl, 18
	cmp	edx, 1 << (50-32)
	jae	8f

	add	esi, 3	# Terabytes
	mov	cl, 8
	cmp	edx, 1 << (40-32)
	jae	8f

	add	esi, 3	# Gigabytes
	mov	cl, 2	# 30, -2: switch to shift right
	or	edx, edx
	jnz	9f
	cmp	eax, 1 << 30	# 1 Gb
	jae	9f		# 3.99 Gb max

	add	esi, 3	# Mb
	mov	cl, 12
	cmp	eax, 1 << 20	# 1 Mb
	jae	9f

	add	esi, 3	# Kb
	mov	cl, 22
	cmp	eax, 1 << 10	# 1 Kb
	jae	9f

	add	esi, 3	# b
	mov	edx, eax
	xor	eax, eax
	ret

8:	shrd	eax, edx, cl
	shr	edx, cl
	ret

9:	shld	edx, eax, cl
	shl	eax, cl
	ret

# in: edx:eax = size in bytes
print_size:
	push	eax
	push	ecx
	push	edx
	push	esi
	call	calc_size
	call	print_fixedpoint_32_32
	call	print
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret

# in: edx:eax = size in bytes
# in: edi = buf ptr
sprint_size:
	push	eax
	push	ecx
	push	edx
	push	esi
	call	calc_size
	call	sprint_fixedpoint_32_32
	call	sprint
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret


############################ PRINT FORMATTED STRING ###########
PRINTF_DEBUG = 0
# in: stack
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
0:	lodsb
	or	al, al
	jz	2f

###########################
	# %
	cmp	al, '%'
	jne	0f
	.if PRINTF_DEBUG
		PRINTc	10, "%"
	.endif
	lodsb
	or	al, al
	jz	2f
	.if PRINTF_DEBUG
		pushcolor 10
		call	printchar
		popcolor
	.endif

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
	.if PRINTF_DEBUG
		pushcolor 11
		mov edx, ecx
		call printhex8
		popcolor
	.endif
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
	.if PRINTF_DEBUG
		pushcolor 11
		mov edx, ecx
		call printhex8
		popcolor
	.endif
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
	.if PRINTF_DEBUG
		PRINTc	11, ">"
		call printchar
		PRINTc	11, "<"
	.endif
	
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

#########################################################################

# in: al = flags
# in: esi = pointer to 8 packed asciz strings
print_flags8:
	push	eax
	push	ebx
	push	ecx
	mov	bl, al
	mov	ecx, 8
0:	shl	bl, 1
	jnc	1f
	call	print_
	call	printspace
	jmp	2f
1:	PRINTSKIP_
2:	loop	0b
	pop	ecx
	pop	ebx
	pop	eax
	ret

# in: ax = flags
# in: esi = pointer to 16 packed asciz strings
print_flags16:
	push	eax
	push	ebx
	push	ecx
	mov	ecx, 16
	mov	bx, ax
0:	shl	bx, 1
	jnc	1f
	call	print_
	call	printspace
	jmp	2f
1:	PRINTSKIP_
2:	loop	0b
	pop	ecx
	pop	ebx
	pop	eax
	ret


screen_pos_mark:
	.data SECTION_DATA_BSS
	screen_pos_mark$: .long 0
	.text32
	push	eax
	mov	eax, [screen_pos]
	mov	[screen_pos_mark], eax
	pop	eax
	ret

# prints eax - [screen_pos] + [screen_pos_mark] spaces.
# in: eax = max nr of spaces
# out: eax = nr of printed chars
#   (call with 0 to get strlen of output since screen_pos_mark)
print_spaces:
	push	ecx
	mov	ecx, eax
	mov	eax, [screen_pos]
	sub	eax, [screen_pos_mark]
	jle	9f
	shr	eax, 1
	sub	ecx, eax
	jle	9f
0:	call	printspace
	loop	0b
#	PRINT_START
#	rep	stosw
#	PRINT_END
9:	pop	ecx
	ret
.endif
