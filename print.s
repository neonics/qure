
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
printhex2:
	push	cx
	push	dx
	mov	cx, 2
	shl	dx, 8
	jmp	0f
printhex:
	push	cx
	push	dx
	mov	cx, 4
0:	rol	dx, 4
	mov	al, dl
	and	al, 0xf
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b

	add	di, 2
	pop	dx
	pop	cx
	ret
	
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


print:
	lodsb
0:	stosw
	lodsb
	test	al, al
	jnz	0b
	ret




regnames$:
.ascii "cs"
.ascii "ds"
.ascii "es"
.ascii "fs"
.ascii "gs"
.ascii "ss"
.ascii "ax"
.ascii "cx"
.ascii "dx"
.ascii "bx"
.ascii "sp"
.ascii "bp"
.ascii "si"
.ascii "di"
.ascii "fl"
.ascii "ip"
.equ REGDATA, . - regnames$  # results to 0x0f, rather than 32
.byte 0
.bss
registers$:
r_cs: .word 0
r_ds: .word 0
r_es: .word 0
r_fs: .word 0
r_gs: .word 0
r_ss: .word 0

r_ax: .word 0
r_cx: .word 0
r_dx: .word 0
r_bx: .word 0
r_sp: .word 0
r_bp: .word 0
r_si: .word 0
r_di: .word 0
r_fl: .word 0
r_ip: .word 0
.text
printregisters:

	mov	si, offset regnames$
	mov	bx, offset registers$
1:	call	newline
0:
	lodsb
	or	al, al
	jz	0f
	stosw
	lodsb
	stosw
	mov	al, ':'
	stosw
	mov	dx, [bx]
	add	bx, 2
	call	printhex

	cmp	bx, offset r_ax
	jz	1b

	jmp	0b
0:	call	newline
	ret

