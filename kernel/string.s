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

	cmp	byte ptr [esi], 0
	jz	1f

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


strlen:
	push	edi
	push	ecx
	mov	edi, eax
	mov	ecx, -1
	xor	al, al
	repnz	scasb
	mov	eax, -2
	sub	eax, ecx
	pop	ecx
	pop	edi
	ret

# in: eax
# out: eax
strdup:
	push	esi
	push	edi
	push	ecx
	mov	esi, eax
	call	strlen
	inc	eax
	mov	ecx, eax
	call	malloc
	mov	edi, eax
	rep	movsb
	pop	ecx
	pop	edi
	pop	esi
	ret

# in: eax
# out: eax, ecx
strdupn:
	push	esi
	push	edi
	mov	esi, eax
	call	strlen
	push	eax
	inc	eax
	mov	ecx, eax
	call	malloc
	mov	edi, eax
	rep	movsb
	pop	ecx
	pop	edi
	pop	esi
	ret

# in: eax, ecx
# out: eax
strndup:
	push	esi
	push	edi
	push	ecx
	mov	esi, eax
	mov	eax, ecx
	inc	eax
	call	malloc
	mov	edi, eax
	rep	movsb
	mov	byte ptr [edi], 0
	pop	ecx
	pop	edi
	pop	esi
	ret

