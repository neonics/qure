.intel_syntax noprefix
.text32
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
	or	dl, dl
	jz	0f	# also cf = 0
	sub	dl, '0'
	js	1f
	cmp	dl, 9
	ja	1f

	inc	esi

	imul	eax, 10
	add	eax, edx

	jmp	0b
1:	stc
0:	pop	edx
	pop	esi
	ret

# in: esi = pointer to string
# out: eax = number on CF=0; CF=1: error
# out: esi
atoi_:
	push	edx
	xor	eax, eax
	xor	edx, edx

	cmp	byte ptr [esi], 0
	jz	1f

0:	mov	dl, [esi]
	or	dl, dl
	jz	0f	# also cf = 0
	sub	dl, '0'
	js	1f
	cmp	dl, 9
	ja	1f

	inc	esi

	imul	eax, 10
	add	eax, edx

	jmp	0b
1:	stc
0:	pop	edx
	ret



# in: eax = pointer to radix 16 (hex) string
# out: eax = number on CF = 0; CF=1: error
htoi:
	push	esi
	push	ebx
	mov	esi, eax
	xor	ebx, ebx

	mov	ah, 9

0:	lodsb
	or	al, al
	jz	0f
	sub	al, '0'
	js	1f
	cmp	al, 9 # '9' - '0'
	jbe	2f
	sub	al, 'A' - '0'
	js	1f
	cmp	al, 6 # 'F' - 'A'
	jbe	4f
	sub	al, 'a' - 'A' 
	js	1f
	cmp	al, 6 # f' - 'a' 
	ja	1f
4:	add	al, 10
2:	
	rol	ebx, 4
#	mov	ah, bl
#	and	ah, 0xf
#	and	bl, 0xf0
#	shl	edx, 4
#	or	dl, ah
	or	bl, al

#	jmp	0b
	dec	ah
	jnz	0b
	stc

0:	mov	eax, ebx
	pop	ebx
	pop	esi
	ret
1:	stc
	jmp	0b


# in: eax = pointer to radix 16 (hex) string
# out: edx:eax = number on CF = 0; CF=1: error
htoid:
	push	esi
	push	ebx
	mov	esi, eax
	xor	ebx, ebx
	xor	edx, edx

	mov	ah, 17

0:	lodsb
	or	al, al
	jz	0f
	sub	al, '0'
	js	1f
	cmp	al, 9 # '9' - '0'
	jbe	2f
	sub	al, 'A' - '0'
	js	1f
	cmp	al, 6 # 'F' - 'A'
	jbe	4f
	sub	al, 'a' - 'A' 
	js	1f
	cmp	al, 6 # f' - 'a' 
	ja	1f
4:	add	al, 10
2:	
	rol	ebx, 4
	mov	ah, bl
	and	ah, 0xf
	and	bl, 0xf0
	shl	edx, 4
	or	dl, ah
	or	bl, al

	jmp	0b
	dec	ah
	jnz	0b
	stc

0:	mov	eax, ebx
	pop	ebx
	pop	esi
	ret
1:	stc
	jmp	0b


# in: eax
# out: eax
strlen:
	push	es
	push	edi
	push	ecx
	mov	edi, ds
	mov	es, edi
	mov	edi, eax
	mov	ecx, -1
	xor	al, al
	repnz	scasb
	mov	eax, -2
	sub	eax, ecx
	pop	ecx
	pop	edi
	pop	es
	ret

# in: esi
# out: ecx
strlen_:
	push	es
	push	edi
	push	eax

	mov	ecx, ds
	mov	es, ecx
	mov	edi, esi
	mov	ecx, -1
	xor	al, al
	repnz	scasb
	add	ecx, 2
	neg	ecx
	pop	eax
	pop	edi
	pop	es
	ret

# in: esi, edi, ecx
strncmp:push	edi
	push	esi
	push	ecx
	repz	cmpsb
	pop	ecx
	pop	esi
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


# in: al = token separator char
# in: esi = cur str ptr
# in: ecx = size of current token (use 0 for first call)
# out: ecx = length of next token (0 for token sep)
# out: CF = 1: match  0: end of string reached
strtok:
	add	esi, ecx
	cmp	[esi], al
	jnz	1f
	inc	esi	# should happen for all but the first (only potentially)
1:	call	strlen_
	stc
	jecxz	9f
	push	edi
	push	ecx
	mov	edi, esi
	repnz	scasb
	jnz	1f
	inc	ecx
	sub	[esp], ecx
1:	pop	ecx
2:	pop	edi
	clc
9:	ret



# in: eax
# in: edx
# out: FLAGS
strcmp:
	push	esi
	push	edi
	push	ecx
	push	eax
	mov	edi, eax
	call	strlen	# eax->eax
	mov	esi, edx
	call	strlen_	# esi->ecx
	cmp	eax, ecx
	jb	0f
	mov	ecx, eax
0:	rep	cmpsb
	pop	eax
	pop	ecx
	pop	edi
	pop	esi
	ret
