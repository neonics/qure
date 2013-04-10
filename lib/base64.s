.intel_syntax noprefix
.data
base64$:
.ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
.ascii "abcdefghijlkmnopqrstuvwxyz"
.ascii "0123456789+/"	# '=' is pad
.text32
# in: esi, ecx
# out: eax = mallocced buffer (zero terminated)
# out: ecx = mallocced buffer len
base64_encode:
	mov	eax, ecx
	call	base64_encoded_len
	call	mallocz
	push_	edi eax ecx esi ebx edx
	mov	edi, eax
	mov	ebx, offset base64$
0:	mov	edx, [esi]	# read 3 bytes
	sub	ecx, 3
	js	1f

	.rept 4
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	shr	edx, 6
	.endr	# note: one shr too many..

	add	esi, 3
	jmp	0b

2:
	pop_ 	edx ebx esi ecx eax edi
	ret
1:	# special case: last bytes
	inc	cl	# check -1
	jz	1f
	inc	cl	# check -2
	jnz	2b	# no: must be -3, so done.
	# handle 2 bytes:
	and	edx, 0xffff
	.rept 3
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	shr	edx, 6
	.endr	# note: one shr too many
	mov	al, '='
	stosb
	jmp	2b

1:	# handle 1 bytes:
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	mov	al, dl
	shr	al, 6
	and	al, 0b11
	xlatb
	stosb
	# expect 2 more bytes:
	mov	ax, '=' | '=' << 8
	stosw

	jmp	2b


# in: eax = len
# out: eax = base64 len
base64_encoded_len:
DEBUG_DWORD eax,"plain len"
	# (eax + 2) / 3 * 4 + 1
	push_	edx ebx
	mov	ebx, 3
	add	eax, 2
	xor	edx, edx
	shl	eax, 2
	idiv	ebx
	inc	eax
	pop_	ebx edx
DEBUG_DWORD eax,"encoded len"
DEBUG "press key";push eax; xor eax,eax; call keyboard; pop eax
	ret
