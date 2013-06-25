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

###################### 32 bit macros
HEX_END_SPACE = 0	# whether to follow hex print with a space 
			# transitional - temporary!

# The screen buffer keeps track of what is printed to the screen.
# It offers the page-up scrollback history, aswell as support needed
# for multiple virtual consoles. Without it, printing is done only
# directly to the screen.
SCREEN_BUFFER	= 1
.if SCREEN_BUFFER
	SCREEN_BUF_PAGES = 12
	SCREEN_BUF_SIZE = 160 * 25 * SCREEN_BUF_PAGES

	SCREEN_BUFFER_FIRST	= 1

# This flag indicates whether to first print to the screen buffer and then
# copy the data to the screen, or to first print to the screen and then
# copy the data from the screen to the buffer.
# 0 is the legacy mode: print to screen directly, and then copy what was
# printed into the history buffer when the screen is scrolled.
# When this flag is 1, printing is done first to the buffer, and
# secondly the changed data is copied to the screen.
# This flags needs to be 1 in order to support off-screen printing
# in virtual consoles.
	VIRTUAL_CONSOLES	= 1
.else
	VIRTUAL_CONSOLES	= 0	# required to be 0
	SCREEN_BUFFER_FIRST	= 0	# required to be 0
.endif

.if VIRTUAL_CONSOLES
.if !SCREEN_BUFFER_FIRST
.error "VIRTUAL_CONSOLES requires SCREEN_BUFFER_FIRST"
.endif
.if !SCREEN_BUFFER
.error "VIRTUAL_CONSOLES requires SCREEN_BUFFER"
.endif
.endif

################# Colors ###############

# private use
.macro _PUSHCOLOR c
	.if COLOR_STACK_SIZE == 2
		IS_REG8 _ISREG, \c
		.if _ISREG
			push	word ptr 0
			mov	[esp], \c
		.else
			push	word ptr \c
		.endif
	.else
		.error "COLOR_STACK_SIZE unsupported value"
	.endif
.endm

.macro COLOR c
	.if VIRTUAL_CONSOLES
	_PUSHCOLOR \c
	call	_s_setcolor
	.else
	mov	byte ptr [screen_color], \c
	.endif
.endm

COLOR_STACK_SIZE = 2

.macro PUSHCOLOR c
	.if VIRTUAL_CONSOLES
		_PUSHCOLOR \c
		call	_s_pushcolor
	.else
		push	word ptr [screen_color]
		mov	word ptr [screen_color], \c
	.endif
.endm

.macro POPCOLOR
	.if COLOR_STACK_SIZE == 2
		.if VIRTUAL_CONSOLES
			call	_s_setcolor
		.else
			pop	word ptr [screen_color]
		.endif
	.else
		.error "COLOR_STACK_SIZE unknown value"
	.endif
.endm



#################### Position ####################

.macro SCREEN_OFFS x, y
	o =  2 * ( \x + 80 * \y )
	.if o == 0
	xor	edi, edi
	.else
	mov	edi, o
	.endif
.endm

.macro PUSH_SCREENPOS newval=-1
	.if VIRTUAL_CONSOLES
		push	edx
		push	eax
		call	console_get
		.ifnc -1,\newval
		mov	edx, \newval
		xchg	edx, [eax + console_screen_pos]
		.else
		mov	edx, [eax + console_screen_pos]
		.endif
		pop	eax
		xchg	edx, [esp]
	.else
		push	dword ptr [screen_pos]
		.ifnc -1,\newval
		mov	dword ptr [screen_pos], \newval
		.endif
	.endif
.endm

.macro POP_SCREENPOS
	.if VIRTUAL_CONSOLES
	push	edx
	push	eax
	call	console_get
	mov	edx, [esp + 8]
	mov	[eax + console_screen_pos], edx
	pop	eax
	pop	edx
	add	esp, 4
	.else
	pop	dword ptr [screen_pos]
	.endif
.endm

# Sets the screen position
# in: pos = 2 * ( x + 80 * y )
# in: pos==edi : edi is taken as offset into the screen buffer, if one is used.
#   in this case the start of the current screen buffer's drawing area is
#   subtracted from pos to obtain a zero-relative coordinate.
.macro SET_SCREENPOS pos
	_HANDLED = 0

	.if SCREEN_BUFFER_FIRST
	.ifc edi,\pos
		push	edi
			.if VIRTUAL_CONSOLES
				push	eax
				call	console_get
				sub	edi, [eax + console_screen_buf]
				sub	edi, SCREEN_BUF_SIZE - 160*25
				mov	dword ptr [eax + console_screen_pos], edi
				pop	eax
			.else
				sub	edi, [screen_buf]
				sub	edi, SCREEN_BUF_SIZE - 160*25
				mov	dword ptr [screen_pos], edi
			.endif
		_HANDLED = 1
		pop	edi
	.endif
	.endif

	.if !_HANDLED
	mov	dword ptr [screen_pos], \pos
	.endif
.endm

.macro GET_SCREENPOS target
	.if VIRTUAL_CONSOLES
		.ifc eax,\target
		call	console_get
		mov	eax, [eax + console_screen_pos]
		.else
		push	eax
		call	console_get
		mov	\target, [eax + console_screen_pos]
		pop	eax
		.endif
	.else
		mov	\target, [screen_pos]
	.endif
.endm

# c:
# 0  : load ah with screen_color
# > 0: load ah with constant
# < 0: skip load ah. Note that ax will still be pushed.
.macro PRINT_START c=0, char=0
#900:MUTEX_LOCK SCREEN, 900b
	push	ax
	PRINT_START_ \c, \char
.endm


.macro PRINT_START_ c=0, char=0
#900:MUTEX_LOCK SCREEN 900b
	pushf	# prevent interrupts during es != ds
#	cli
	cld
	push	es
	push	edi
	.if VIRTUAL_CONSOLES
		mov	edi, ds
		mov	es, edi
		push	ebx
		push	eax
		call	console_get
		mov	ebx, eax
		pop	eax
		mov	edi, [ebx + console_screen_pos]
		mov	[ebx + console_screen_buf_pos], edi	# mark begin of change
		add	edi, [ebx + console_screen_buf]
		add	edi, SCREEN_BUF_SIZE - 160*25
	.elseif SCREEN_BUFFER_FIRST
		mov	edi, ds
		mov	es, edi
		mov	edi, [screen_pos]
		mov	[screen_buf_pos], edi	# mark begin of change
		add	edi, [screen_buf]
		add	edi, SCREEN_BUF_SIZE - 160*25
	.else
		movzx	edi, word ptr [screen_sel]
		mov	es, edi
		mov	edi, [screen_pos]
	.endif

	.ifc ah,\c
		mov	al, \char
	.elseif \c == 0
		.if VIRTUAL_CONSOLES
			mov	ah, [ebx + console_screen_color]
		.else
			mov	ah, [screen_color]
		.endif
		.ifnc 0,\char
		mov	al, \char
		.endif
	.elseif \c < 0
		# do not update ax
	.else
		mov	ax, (\c << 8) | \char
	.endif

	.if VIRTUAL_CONSOLES
		pop	ebx
	.endif
.endm

# flags:
# 01: do not store position
# 10: do not perform scroll check - only applies when flags & 01 = 00
.macro PRINT_END_ ignorepos=0 noscroll=0
	.if VIRTUAL_CONSOLES
	push	eax
	call	console_get
	sub	edi, [eax + console_screen_buf]
	sub	edi, SCREEN_BUF_SIZE - 160*25
	.elseif SCREEN_BUFFER_FIRST
	sub	edi, [screen_buf]
	sub	edi, SCREEN_BUF_SIZE - 160*25
	.endif

	.if \ignorepos
	.else
		.if \noscroll
		.else
			cmp	edi, 160 * 25
			jb	199f
			call	__scroll
			199:
		.endif

		.if VIRTUAL_CONSOLES
			mov	[eax + console_screen_pos], edi
		.else
			mov	[screen_pos], edi
		.endif
	.endif

	.if SCREEN_BUFFER_FIRST # applies to VIRTUAL_CONSOLES too
	call	screen_buf_flush
	.endif

	.if VIRTUAL_CONSOLES
	pop	eax
	.endif
	#.if !SCREEN_BUFFER_FIRST
	#pop	es
	#.endif
	pop	edi
	pop	es
#MUTEX_UNLOCK SCREEN
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

.macro PRINTCHAR c
	push	ax
	PRINTCHAR_ \c
	pop	ax
.endm

# does not preserve ax
.macro PRINTCHAR_ c
	mov	al, \c
	call	printchar
.endm

.macro sPRINTCHAR c
	mov	[edi], byte ptr \c
	inc	edi
.endm

.macro PRINTCHARc col, c
	push	ax
	PRINTCHARc_ \col, \c
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
	_CODE_OFFS = .
	.data SECTION_DATA_STRINGS
		199: .asciz "\txt"
	.section .strtab
		.long 199b, _CODE_OFFS + 1
	.text32
	mov	\reg, offset 199b
.endm

.macro PUSH_TXT txt
	_CODE_OFFS = .
	.data SECTION_DATA_STRINGS
		199: .asciz "\txt"
	.section .strtab
		.long 199b, _CODE_OFFS + 1
	.text32
	push	dword ptr offset 199b
.endm

# for printf
.macro PUSHSTRING s
	PUSH_TXT "\s"
.endm


# call from .data
.macro STRINGPTR n
	.data SECTION_DATA_STRINGS
	199: .asciz "\n"
	.section .strtab
		.long 199b, 198f
	.data
	198: .long 199b
.endm

# call from .data
.macro STRINGNULL
	.data
	.long 0
.endm


# prints esi, not preserving it.
.macro PRINT_ msg=esi
	.ifnes "\msg", ""
	.ifnc esi,\msg
	LOAD_TXT "\msg"
	.endif
	.endif
	call	print_
.endm


.macro PRINTSKIP_
191:	lodsb
	or	al, al
	jnz	191b
.endm

# like PRINT_, except the string is skipped when ZF=1, and printed when ZF=0
.macro PRINT_NZ_
	jz	199f
	call	print_
	jmp	198f
199:	PRINTSKIP_
198:
.endm

.macro PRINT_Z_
	jnz	199f
	call	print_
	jmp	198f
199:	PRINTSKIP_
198:
.endm


.macro PRINTLN_ msg=esi
	.ifnc esi,\msg
	LOAD_TXT "\msg"
	.endif
	call	println
.endm


.macro PRINT msg=esi
	.ifnes "esi","\msg"
	PUSH_TXT "\msg"
	call	_s_print
	.else
	call	print_
	.endif
.endm

.macro SPRINT msg
	push	esi
	LOAD_TXT "\msg"
	call	sprint
	pop	esi
.endm

.macro PRINTLN msg=esi
	.ifc esi,\msg
	call	println_
	.else
	push	esi
	LOAD_TXT "\msg"
	call	println_
	pop	esi
	.endif
.endm

.macro PRINTc_ color, str=esi
	pushcolor \color
	PRINT_ "\str"
	popcolor
.endm

.macro PRINTLNc_ color, str
	pushcolor \color
	PRINTLN_ "\str"
	popcolor
.endm

.macro PRINTc color, str=esi
.if 1
	.ifc esi,\str
		push	esi
	.else
		PUSH_TXT "\str"
	.endif

	.if COLOR_STACK_SIZE == 2
	push	word ptr \color
	.else
	.error "COLOR_STACK_SIZE unknown value"
	.endif

	call	_s_printc
.else
	pushcolor \color
	PRINT "\str"
	popcolor
.endif
.endm

.macro PRINTLNc color, str=esi
.if 1
	.ifc esi,\str
		push	esi
	.else
		PUSH_TXT "\str"
	.endif

	.if COLOR_STACK_SIZE == 2
	push	word ptr \color
	.else
	.error "COLOR_STACK_SIZE unknown value"
	.endif

	call	_s_printlnc
	#call	_s_printc
	#call newline
.else
	pushcolor \color
	PRINTLN "\str"
	popcolor
.endif
.endm

####################

.macro PRINTIF reg, val, msg
	cmp	\reg, \val
	jne	111f
	PRINT	"\msg"
111:
.endm


.macro PRINTFLAG reg, bit, msg, altmsg=0
	test	\reg, \bit
	jz	111f
	PRINT	"\msg"
	.ifnc 0,\altmsg
	jmp	112f
	.endif
111:
	.ifnc 0,\altmsg
	PRINT	"\altmsg"
	.endif
112:
.endm

.macro _PRINTBITSHEX width
	.if \width <=4
	call	printhex1
	.else
		.if \width <= 8
		call	printhex2
		.else
			.if \width <=16
			call	printhex4
			.else
			call	printhex8
			.endif
		.endif
	.endif
.endm


.macro PRINTBITSb reg, firstbit, width, msg=0
	.ifnc 0,\msg
	PRINTc	7, "\msg"
	.endif
	mov	dl, \reg
	shr	dl, \firstbit
	and	dl, (1 << \width) - 1
	_PRINTBITSHEX \width
	.endm

.macro PRINTBITSw reg, firstbit, width, msg=0
	.ifnc 0,\msg
	PRINTc	7, "\msg"
	.endif
	mov	dx, \reg
	shr	dx, \firstbit
	and	dx, (1 << \width) - 1
	_PRINTBITSHEX \width
.endm

.macro PRINTBITSd reg, firstbit, width, msg=0
	.ifnc 0,\msg
	PRINTc	7, "\msg"
	.endif
	mov	edx, \reg
	shr	edx, \firstbit
	and	edx, (1 << \width) - 1
	_PRINTBITSHEX \width
.endm

.macro PRINTBITb reg, bit
	mov	dl, \reg
	and	dl, 1<<\bit
	shr	dl, \bit
	call	printhex1
.endm

.macro PRINTBITw reg, bit
	mov	dx, \reg
	and	dx, 1<<\bit
	shr	dx, \bit
	call	printhex1
.endm


.endif
###############################################################################
###############################################################################
###### Definitions: implementation ############################################
###############################################################################
###############################################################################
###############################################################################
.if DEFINE

.if VIRTUAL_CONSOLES
.tdata
tls_console_cur_ptr:	.long 0
.tdata_end
.struct 0
console_screen_color:		.word 0
console_screen_pos:		.long 0
console_screen_buf:		.long 0
console_screen_buf_pos:		.long 0
console_screen_scroll_lines:	.long 0
console_pid:			.long 0
CONSOLE_STRUCT_SIZE = .
.data SECTION_DATA_BSS
console_cur:	.byte 0
console_cur_ptr:.long consoles	# initialize to first console
.data16
consoles:	# 10 CONSOLE_STRUCTs: the first being the screen_ (default)
.endif	# keep with next:

.data16	# realmode access, keep within 64k
	# the first console:
	screen_color:	.word 0x0f	# is a byte, but word for push/pop
	screen_pos:	.long 0
	.if SCREEN_BUFFER
	screen_buf:		.long screen_buf0
	screen_buf_pos:		.long 0	# screen_buf_flush argument; -1=scrolled;-2=cls
	.endif
	screen_scroll_lines:	.long 0	# total count
	.long 0	# the pid

.if VIRTUAL_CONSOLES
	.space 9* CONSOLE_STRUCT_SIZE
.endif

	screen_sel:	.long 0
	screen_update:	.long default_screen_update
.text32
default_screen_update:	# 16 and 32 bit
	ret

# Methods starting with __ are to be called only when es:edi and ah are
# set up - between PRINT_START and PRINT_END.

####################### PRINT HEX ########################
# in: edx = nr to print
# in: edi = buffer
sprinthex8:
	push	eax
	push	ecx
	mov	ecx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'a' - '0' - 10
1:	add	al, '0'
	stosb
	loop	0b
	pop	ecx
	pop	eax
	ret


# in: ecx = num hex digits, edx = value
nprinthex:
	push	ecx
	and	ecx, 63
	jz	0f
	shl	ecx, 2
	neg	ecx
	add	ecx, 32
	rol	edx, cl
	sub	ecx, 32
	neg	ecx
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
0:	push	ax
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'a' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	pop	ax
.if HEX_END_SPACE
	add	edi, 2
.endif
	pop	ecx
	ret

############################## print octal
# 18 bits:
printoct6:
	push	ecx
	push	edx
	mov	cl, 18 - 3
	jmp	1f
# in: edx
printoct:
	push	ecx
	push	edx
	mov	cl, 32 - 2
1:	push	ebx
	PRINT_START
0:	mov	ebx, edx
	shr	ebx, cl
	and	bl, 7
	add	bl, '0'
	mov	al, bl
	stosw

	sub	cl, 3
	jge	0b
	PRINT_END
	pop	ebx
	pop	edx
	pop	ecx
	ret

########################### CLEAR SCREEN, NEW LINE, SCROLL ##########

cls:	SET_SCREENPOS 0
	PRINT_START
	push	ecx
	#xor	edi, edi
	xor	al, al
	#mov	[screen_pos], edi
	mov	ecx, 80 * 25 # 7f0
	rep	stosw
	pop	ecx
	.if SCREEN_BUFFER
	mov	[screen_buf_pos], dword ptr -2
	.endif
	PRINT_END 1
	ret


newline:
	push	ecx
	push	eax
	push	edx
	GET_SCREENPOS eax
	mov	ecx, eax
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	sub	ecx, eax
	neg	ecx
	PRINT_START
	add	ecx, 160	# clear next line too
	xor	al, al
	shr	ecx, 1
	rep	stosw
	sub	edi, 160
	PRINT_END
	pop	edx
	pop	eax
	pop	ecx
	ret


##### SCROLLBACK BUFFER ######
.if SCREEN_BUFFER
.data SECTION_DATA_BSS
# pre-allocated buffer for the first screen, as it is accessed before
# memory management is initialized.
screen_buf0:	.space SCREEN_BUF_SIZE + 1024	# a little print overflow space
.text32
.endif
##############################
# this method is only to be called when edi >= 160 * 25
# in: edi = [screen_pos]
# out: edi = updated screenpos
__scroll:
	push	ds
	push	esi
	push	ecx

	push eax
	push edx

	# calc nr lines
	# edi = # (left)
	xor	edx, edx
	mov	eax, edi
	# check if screen pos is exactly at end of screen:
	cmp	eax, 160*25
	jnz	1f
	inc	eax
1:
	sub	eax, 160 * 25
	jle	1f
	add	eax, 159

	# eax = len(abc)
	# calculate nr of lines
	mov	ecx, 160
	div	ecx
	.if VIRTUAL_CONSOLES
	push	ebx
	push	eax
	call	console_get
	mov	ebx, eax
	pop	eax
	add	[ebx + console_screen_scroll_lines], eax
	.else
	add	[screen_scroll_lines], eax
	.endif
	mul	ecx
2:	mov	ecx, eax
	# ecx: nr lines * cols = data

	.if !SCREEN_BUFFER_FIRST
	.if SCREEN_BUFFER
	# |bufA  |      |bufB_|
	# |bufB__|	|A____|
	#  _____	 _____
	# |A____|	|B____|
	# |B____|	|C____|
	# |C____|	|D____|
	# |D____|abc#	|abc#_|

		# shift the buffer
		push	esi
		push	edi
		push	es
		mov	edx, es
		mov	esi, ds
		mov	es, esi
		mov	edi, [screen_buf]
		lea	esi, [edi + 160]	# FIXME [edi + ecx] ?
		neg	ecx
		add	ecx, SCREEN_BUF_SIZE
		rep	movsb	# buf->buf
		mov	ecx, eax
		# es:edi = ok
		# ecx = ok
		# ds:esi:
		mov	ds, edx	# no need to restore - is altered right below
		mov	esi, 160 * 24
		sub	edi, ecx
		rep	movsb	# vid->buf
		mov	ecx, eax
		pop	es
		pop	edi
		pop	esi
	.else
		mov	eax, es
		mov	ds, eax
	.endif
	.endif

.if SCREEN_BUFFER_FIRST
sub edi, ecx
push edi

xor edi, edi	# target = start of screen buf
mov esi, ecx	# source = discard start..screen_scroll lines
mov ecx, SCREEN_BUF_SIZE	# total buf size
sub ecx, esi	# minus screen_scroll_lines
.else
	mov     esi, ecx # scroll lines * 160
	mov     ecx, edi # screenpos
	sub     ecx, esi #
	xor     edi, edi
	push	ecx
.endif
	add	ecx, 160	# copy beyond buffer - without this: eol dup
	.if SCREEN_BUFFER_FIRST
	.if VIRTUAL_CONSOLES
	mov	eax, [ebx + console_screen_buf]
	mov	[ebx + console_screen_buf_pos], dword ptr -1
	.else
	mov	eax, [screen_buf]
	mov	[screen_buf_pos], dword ptr -1
	.endif
	add	edi, eax	# add buffer offset
	add	esi, eax	# add buffer offset
#	add	edi, SCREEN_BUF_SIZE -160*25	# this enabled: only scroll
#	add	esi, SCREEN_BUF_SIZE -160*25	# within last page of buffer
	.endif

	shr	ecx, 1
	rep	movsw	# buf->buf | vid->vid
	pop	edi

	.if VIRTUAL_CONSOLES
	pop	ebx
	.endif

1:	pop	edx
	pop	eax

	pop	ecx
	pop	esi
	pop	ds
	ret


.if SCREEN_BUFFER_FIRST

DEBUG_SCREEN_FLUSH = 0

screen_buf_flush:
	push	edi
	push	esi
	push	ecx
		push edx
	push	es
	mov	edi, [screen_sel]
	mov	es, edi
	.if VIRTUAL_CONSOLES
	push	ebx
	push	eax
	call	console_get
	mov	ebx, eax
	pop	eax
	cmp	ebx, [console_cur_ptr]
	jnz	8f	# console not active, don't flush
	mov	esi, [ebx + console_screen_buf]
	.else
	mov	esi, [screen_buf]
	.endif
	add	esi, SCREEN_BUF_SIZE - 160*25
	.if DEBUG_SCREEN_FLUSH > 1
		# clear bg color for debug a bit below
		push esi
		mov	ecx, 80*25 / 2 #movsw->movsd
		xor	edi, edi
		rep	movsd
		pop esi
	.endif

	.if VIRTUAL_CONSOLES
	mov	ecx, [ebx + console_screen_pos]
	mov	edi, [ebx + console_screen_buf_pos]
	.else
	mov	ecx, [screen_pos]	# fa0
	mov	edi, [screen_buf_pos]
	.endif

	or	edi, edi
	jns	1f		# -1 means scrolled, screen_pos will be before
	inc	edi		# end of screen - on the last line, so we need
	jz	2f		# -2 (now -1) means cls.
	inc	edi
3:	mov	ecx, 160*25-160
2:
	add	ecx, 160	# to copy the last line too.
1:
	add	esi, edi
	sub	ecx, edi
	jg	1f	# screen_pos < screen_buf_pos
	neg	ecx
1:	shr	ecx, 1
		mov edx, ecx
	jz	2f

	rep	movsw
2:
	.if DEBUG_SCREEN_FLUSH
	pushad
		# print offsets etc at top row
		push	esi
		push edi
		push edx
		xor edi, edi
		mov ax, 0x8f << 8
#		mov edx, ebx
		call __printhex8
		.if VIRTUAL_CONSOLES
			mov edx, [ebx + console_screen_pos]
		.else
			mov edx, [screen_pos]
		.endif
		LOAD_TXT " screenpos "
		call __print
		call __printhex8
		stosw
		mov ecx, edx
		.if VIRTUAL_CONSOLES
			mov edx, [eax + console_screen_buf_pos]
		.else
			mov edx, [screen_buf_pos]
		.endif
		sub ecx, edx
		LOAD_TXT "bufpos "
		call __print
		call __printhex8
		mov edx, ecx
		stosw
		LOAD_TXT "len "
		call __print
		call __printhex8
		stosw
		LOAD_TXT "tls "
		call __print
		mov	edx, [tls]
		call __printhex8

		.if DEBUG_SCREEN_FLUSH > 1
			# change background color of newly printed
			.if VIRTUAL_CONSOLES
				mov edi, [ebx + console_screen_buf_pos]
				mov ecx, [ebx + console_screen_pos]
			.else
				mov edi, [screen_buf_pos]
				mov ecx, [screen_pos]
			.endif
			or edi, edi
			jns 1f
			xor edi, edi
			1:
			sub ecx, edi
			jle 2f
			shr ecx, 1
			0:xor es:[edi + 1], byte ptr 0xff
			add edi, 2
			loop 0b
			2:
		.endif
		pop edx
		pop edi
		pop	esi
	popad
	.endif

	.if VIRTUAL_CONSOLES
	mov	[ebx + console_screen_buf_pos], edi
8:	pop	ebx
	.else
	mov	[screen_buf_pos], edi
	.endif
	pop	es
		pop	edx
	pop	ecx
	pop	esi
	pop	edi
9:	

	.if 1 # NEW!
		mov	edi, [realsegflat]
		add	edi, [screen_update]
		call	edi
	.endif
	ret
.endif

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

# Stack-arg methods '_s_'-prefix:

_s_printlnc:
	push	esi
	push	eax
	mov	esi, [esp + 12 + COLOR_STACK_SIZE]
	mov	ah, [esp + 12]
	call	printlnc
	pop	eax
	pop	esi
	ret	4 + COLOR_STACK_SIZE

_s_println:
	push	esi
	mov	esi, [esp + 8]
	call	println
	pop	esi
	ret	4

_s_print:
	push	eax
	push	esi
.if VIRTUAL_CONSOLES
	call	console_get
	mov	ah, [eax + console_screen_color]
.else
	mov	ah, [screen_color]
.endif
	mov	esi, [esp + 12]
	call	print
	pop	esi
	pop	eax
	ret	4

# in: [esp + COLOR_STACK_SIZE] = offset
# in: [esp] = color (word)
# out: clear stack arguments
_s_printc:
	push	esi
	push	eax
	mov	esi, [esp + 8 + 4 + COLOR_STACK_SIZE]
	mov	ah, [esp + 8 + 4 + 0]
	call	printc
	pop	eax
	pop	esi
	ret	4 + COLOR_STACK_SIZE

# in: [esp] = color<<8 | char
_s_printcharc:
	push	eax
	mov	ax, [esp + 4 + 4 + 0]
	call	printcharc
	pop	eax
	ret	COLOR_STACK_SIZE

_s_printhex8:
	push	edx
	mov	edx, [esp + 8]
	call	printhex8
	pop	edx
	ret	4

.if VIRTUAL_CONSOLES
_s_setcolor:
	push	dx
	mov	dx, [esp + 6]
	push	eax
	call	console_get
	mov	[eax + console_screen_color], dx
	pop	eax
	pop	dx
	ret	COLOR_STACK_SIZE

# in: [esp] = word color to set.
# out: [esp] = replaced color
_s_pushcolor:
	push_   ebx eax
	call    console_get
	mov     bl, [esp + 12]
	xchg    bl, [eax + console_screen_color]
	mov	[esp + 12], bl
	pop_	eax ebx
	ret
.endif

printcharc:
	PRINT_START_ -1
	stosw
	PRINT_END_
	ret

nprintln:
	call	nprint
	jmp	newline

# in: ah = color
# in: esi = string
# in: ecx = max len
nprintc:
	jecxz	1f
	push_	esi ecx edx
	PRINT_START -1
	jmp	2f
1:	ret

# in: esi = string
# in: ecx = max len
nprint:	or	ecx, ecx
	jz	1f
	push_	esi ecx edx
	PRINT_START
2:		mov	dl, 80
0:	lodsb
	or	al, al
	jz	0f
	stosw
		dec	dl; jz	2f; 3:
	loop	0b
0:	PRINT_END
	pop_	edx ecx esi
1:	ret

		2: mov	dl, 80; PRINT_END; PRINT_START; jmp 3b

# in: esi = string
# in: ecx = exact len to print
# out: esi += ecx, ecx = 0
nprint_:
	jecxz	9f
	push	eax
0:	lodsb
	call	printchar
	loop	0b
	pop	eax
9:	ret

nprintln_:
	call	nprint_
	jmp	newline

println:call	print
	jmp	newline
#println:push	offset newline
printlnc:
	call	printc
	jmp	newline

# in: ah = color
# in: esi = string
printc: push_	esi edx
	PRINT_START c=ah
		mov	dl, 80
	jmp	1f
print:	push_	esi edx
	PRINT_START
		mov	dl, 80
	jmp	1f

0:	stosw
		dec	dl; jz 2f; 3:
1:	lodsb
	test	al, al
	jnz	0b

	PRINT_END
	pop_	edx esi
	ret

		2: PRINT_END;PRINT_START; mov dl, 80; jmp 3b

sprint:	push	esi
	jmp	1f

0:	stosb
1:	lodsb
	test	al, al
	jnz	0b

	pop	esi
	ret

print_:
.if 0
	push	eax
0:	lodsb
	or	al, al
	jz	1f
	call	printchar
	jmp	0b
1:	pop	eax
	ret
.else
		push	edx
		mov	dl, 40
	PRINT_START
	jmp	1f
0:	stosw
		jmp	2f
		3:
1:	lodsb
	test	al, al
	jnz	0b
	PRINT_END
		pop	edx
	ret

		2: PRINT_END; PRINT_START; mov dl, 40; jmp 3b
.endif

println_:
	call	print_
	jmp	newline

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
# in: bl = [7:4 flags} [3:0 digits]; flags: 1<<4=print .000
sprint_fixedpoint_32_32$:
	push	eax
	push	edx

	call	sprintdec32
	test	bl, 1 << 4
	jnz	0f
	or	eax, eax
	jz	1f

0:	and	bl, 15
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

# in: edx:eax = size in bytes
# in: edi = buf ptr
# in: bl = [flags][digits] (see sprint_fixedpoint_32_32$)
sprint_size_:
	push	eax
	push	ecx
	push	edx
	push	esi
	call	calc_size
	cmp	word ptr [esi], 'b'
	jnz	1f
	and	bl, 15
1:	call	sprint_fixedpoint_32_32$
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

#############################################################################
screen_get_scroll_lines:
.if VIRTUAL_CONSOLES
	call	console_get
	mov	eax, [eax + console_screen_scroll_lines]
.else
	mov	eax, [screen_scroll_lines]
.endif
	ret

screen_get_pos:
	GET_SCREENPOS eax
	ret

screen_set_pos:
	SET_SCREENPOS eax
	ret

.if VIRTUAL_CONSOLES
console_get:
	mov	eax, [tls]
	or	eax, eax
	jz	1f
	mov	eax, [eax + tls_console_cur_ptr]
	or	eax, eax
	jz	1f
	ret

1:	mov	eax, [console_cur_ptr]
	ret
.endif

##############################################################################
# Console - multiple screens
.if VIRTUAL_CONSOLES
# in: al = console nr (0..9)
console_set:
	cmp	al, [console_cur]
	jz	10f

	push	eax
	push	edx
	push	esi

	movzx	edx, al
	mov	[console_cur], dl
	mov	eax, CONSOLE_STRUCT_SIZE
	imul	edx, eax
	add	edx, offset consoles
	mov	[console_cur_ptr], edx

	mov	esi, [edx + console_screen_buf]
	or	esi, esi
	jnz	1f


	mov	eax, SCREEN_BUF_SIZE + 1024
	call	malloc
	jc	9f
	mov	esi, eax
	mov	[edx + console_screen_buf], eax
	mov	[edx + console_screen_color], word ptr 7

	cmp	edx, offset consoles
	jz	1f
	mov	[edx + console_pid], dword ptr -1
1:
	#mov	[edx + console_screen_buf_pos], dword ptr -2
	#call	screen_buf_flush
	push es
	push edi
	push ecx
	mov edi, [screen_sel]
	mov es, edi
	xor edi, edi
	mov ecx, 160*25/4
	add esi, SCREEN_BUF_SIZE - 160*25
	rep movsd
	pop ecx
#		xor edi, edi
#		mov eax, edx
#		mov edx, [eax + console_screen_pos]
#		call __printhex8
	pop edi
	pop es

9:
	pop	esi
	pop	edx
	pop	eax
10:	ret

.endif


.endif	# DEFINE
