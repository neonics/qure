###########################################################################
######################## Bootloader: bootsector and sector1 ###############
###########################################################################
#.print "*** 16/print.s:"


.ifndef SECTOR1
#.print " * including cls"
cls:
	mov	di, 0xb800
	mov	es, di
	xor	di, di
	mov	cx, 80 * 25 # 7f0
	rep	stosw
	xor	di, di
	ret
.endif

# arg: es:di screen ptr
# arg: ax: number
# uses: ax, dx, di
# arg: dx
.if BOOTSECTOR
.else
#.print " * including printhex2"
printhex2:
	push	ax
	push	cx
	push	dx
	mov	cx, 2
	shl	dx, 8
	jmp	printhex$
.endif
.ifndef SECTOR1
#.print " * including printhex"
printhex_16:
printhex:
	push	ax
	push	cx
	push	dx
	mov	cx, 4
printhex$:
0:	rol	dx, 4
	mov	al, dl
	and	al, 0xf
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b

	add	di, 2
	pop	dx
	pop	cx
	pop	ax
	ret

newline_16:
newline:
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

println:push	offset newline
	jmp	print
	
.if 0
	call print
	call	newline
	ret
.endif

0:	stosw
print_16:
print:	lodsb
	test	al, al
	jnz	0b
	ret

.endif

.if BOOTSECTOR
.else
#.print " * Including extended print functions"
###########################################################################
############ Non-bootloader code is safe to go here #######################
###########################################################################

.if 0
	savecursor$:
	.bss
		cursor: .word 0
		cursor_form: .word 0
	.text
		mov	ah, 3
		mov	bh, 0
		int	0x10
		mov	[cursor_form], cx
	hidecursor$:
		mov	ah, 1
		mov	cx, 0x2706
		int	0x10
		ret
.endif


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

.macro PRINT a
	PRINT_16 a
.endm

.macro	PRINT_16 a
	.data
	9: .asciz "\a"
	.text
	push	si
	mov	si, offset 9b
	call	print
	pop	si
.endm

.macro PRINTLN a
	.data
	9: .asciz "\a"
	.text
	push	si
	mov	si, offset 9b
	call	println
	pop	si
.endm

.macro PRINTc color, str
	push	ax
	mov	ah, \color
	PRINT	"\str"
	pop	ax
.endm

.macro PRINTLNc color, str
	push	ax
	mov	ah, \color
	PRINTLN	"\str"
	pop	ax
.endm

printhex8_16:
printhex8:
	push	cx
	push	ax
	mov	cx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	add	di, 2
	pop	ax
	pop	cx
	ret

.endif
