
.data
msg_vbe_not_supported: .asciz "VBE Function not supported"
msg_vbe_error: .asciz "VBE error: 0x"
vbe_old_mode: .word 0
.text

gfxmode:
	pushad
	push	es

	mov	ax, 0x4f03	# VBE get video mode
	int	0x10
	cmp	ax, 0x004f
	jne	vbe_err$
	mov	[vbe_old_mode], bx

	#vbe modes:
	#0x0355 GFX	1440x900
	#0x010c TEXT	132x60 text
	#0x0118 GFX	1024x768
	mov	bx, 0x118 # 1024x768

	mov	ax, 0x4f02
	int	0x10
	cmp	ax, 0x4f
	jne	vbe_err$


	mov	ax, 0xa000
	mov	es, ax
	xor	di, di

	#mov	ecx, 1024 * 768
	xor	cx, cx

	xor	ax, ax
1:	push	cx

	xor	cx, cx

	xor	bl, bl
0:	stosw
	xchg	al, bl
	stosb
	xchg	al, bl
	inc	al
	add	bl, ah

	ror	edi, 16
	mov	dx, di
	shr	dx, 4
	add	dx, 0xa000
	mov	es, dx
	ror	edi, 16

	loop	0b

	pop	cx
	inc	cx
	cmp	cx, 0x0c
	jb	1b

	call	waitkey
	mov	bx, [vbe_old_mode]
	mov	ax, 0x4f02
	int	0x10

	mov	dx, 0x1337
	mov	ah, 0xf3
	call	printhex

2:	pop	es
	popad
	ret

vbe_err$:
	cmp	al, 0x4f
	jne	0f

	mov	si, offset msg_vbe_not_supported
	mov	ah, 0xf4
	call	println
	jmp	2b

0:	mov	si, offset msg_vbe_error
	call	print
	mov	dl, ah
	call	printhex2
	call	newline
	jmp	2b

