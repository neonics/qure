.intel_syntax noprefix
.text
.code32
# in: eax = pointer to string
# out: eax = number on CF=0; CF=1: error
atoi:
	push	esi
	push	edx
	mov	esi, eax
	xor	eax, eax
	xor	edx, edx

0:	mov	dl, [esi]
	inc	esi
	or	dl, dl
	jz	0f	# also cf = 0
	sub	dl, '0'
	js	1f
	cmp	dl, 9
	ja	1f

	imul	eax, 10
	add	eax, edx

	jmp	0b
1:	stc
0:	pop	edx
	pop	esi
	ret

