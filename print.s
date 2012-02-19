.global cls
cls:
	mov	di, 0xb800
	mov	es, di
	xor	di, di
	mov	cx, 80 * 25 # 7f0
	rep	stosw
	xor	di, di
	ret


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


# arg: es:di screen ptr
# arg: ax: number
# uses: ax, dx, di

# arg: dx
.global printhex2
printhex2:
	push	ax
	push	cx
	push	dx
	mov	cx, 2
	shl	dx, 8
	jmp	0f
.global printhex
printhex:
	push	ax
	push	cx
	push	dx
	mov	cx, 4
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


.global newline
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

.global println
.if !1337
0:	call	newline
	ret
println:push 	offset 0b
.else
println:call print
	call	newline
	ret
.endif

.global print
0:	stosw
print:	lodsb
	test	al, al
	jnz	0b
	ret


# DO NOT USE IN bootloader.s BEFORE SECTOR 1!!
.macro	PRINT a
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

