.code32
printhex8:
	push	ecx
	push	edx
	push	ax
	mov	ecx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	pop	ax
	pop	edx
	pop	ecx
	ret

.code16
