.code16
printhex8:
	push	ax
	push	cx
	push	edx
	mov	cx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b
	pop	edx
	pop	cx
	pop	ax
	ret

.code32
printhex8_32:
	push	eax
	push	ecx
	push	edx
	mov	ecx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b
	pop	edx
	pop	ecx
	pop	eax
	ret

.code16
