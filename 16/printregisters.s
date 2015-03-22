.intel_syntax noprefix

.ifndef COLOR_BG
COLOR_BG	= 0xf0
.endif

.ifndef PRINTREGISTERS_PRINT_FLAGS
PRINTREGISTERS_PRINT_FLAGS=0
.endif

printregisters:
	pusha
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# assume es:di is valid
	mov	ax, 0xb800
	mov	es, ax
	cmp	di, 80*25 * 2
	jb	1f
	xor	di, di
1:

	call	newline
	mov	bx, sp

	mov	si, offset regnames$
	mov	cx, 16	# 6 seg 9 gu 1 flags 1 ip

0:	mov	ah, COLOR_BG # 0xf0
	lodsb
	stosw
	lodsb
	stosw

	mov	ah, COLOR_BG & 0xf0 | 8	# 0xf8
	mov	al, ':'
	stosw

	mov	ah, COLOR_BG & 0xf0 | 9	# 0xf1
	mov	dx, ss:[bx]
	add	bx, 2

	call	printhex

	cmp	cx, 10
	jne	1f

.if PRINTREGISTERS_PRINT_FLAGS
	# print flag characters
	push	bx
	push	si
	push	cx

	mov	si, offset regnames$ + 32 # flags
	mov	cx, 16
2:	lodsb
	mov	bl, dl
	and	bl, 1
	jz	3f
	add	al, 'A' - 'a'
3:	shl	bl, 1
	add	ah, bl
	stosw
	sub	ah, bl
	shr	dx, 1
	loop	2b
	
	pop	cx
	pop	si
	pop	bx
.endif

	call	newline

1: 	loopnz	0b

	call	newline

	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popf
# TODO:
#	mov	ss:[sp + ?], di
#	popa
.if 0
	mov	[tmp_di$], di
	popa
	mov	di, [tmp_di$]
	ret
tmp_di$: .word 0
.else
	pop	ax	# manual pop to preserve di
	pop	si
	pop	bp
	pop	ax	# ignore sp
	pop	bx
	pop	dx
	pop	cx
	pop	ax
	ret
.endif

regnames$:
.ascii "cs"	# 0
.ascii "ds"	# 2
.ascii "es"	# 4
.ascii "fs"	# 6
.ascii "gs"	# 8
.ascii "ss"	# 10

.ascii "fl"	# 12

.ascii "di"	# 14
.ascii "si"	# 16
.ascii "bp"	# 18
.ascii "sp"	# 20
.ascii "bx"	# 22
.ascii "dx"	# 24
.ascii "cx"	# 26
.ascii "ax"	# 28
.ascii "ip"	# 30

.ascii "c.p.a.zstidoppn."

