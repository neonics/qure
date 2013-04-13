###############################################################################
# Base64 Encoding
# RFC 4648 (page 5)
.intel_syntax noprefix
.data
base64$:
.ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
.ascii "abcdefghijlkmnopqrstuvwxyz"
.ascii "0123456789+/"	# '=' is pad; base64url: +/ becomes -_
.text32

# TODO: optimize: there are some bswaps that may be optimized out


# in: esi, ecx
# in: edi: out buffer (0 = alloc buffer)
# out: ecx = encoded buffer len (excl zero terminator)
base64_encode:
	or	edi, edi
	jnz	1f

	push	eax
	mov	eax, ecx
	call	base64_encoded_len
	inc	eax	# zero terminated
	call	malloc
	mov	edi, eax
	pop	eax

1:	push_	edi eax esi ebx edx
	mov	ebx, offset base64$
0:	mov	edx, [esi]	# read 3 bytes
	sub	ecx, 3
	js	1f

	bswap	edx
	rol	edx, 6

	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	
	rol	edx, 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	
	rol	edx, 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb
	
	rol	edx, 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb

	add	esi, 3
	jmp	0b

2:	mov	byte ptr [edi], 0
	pop_ 	edx ebx esi eax
	mov	ecx, edi
	pop	edi
	sub	ecx, edi
	ret

1:	# special case: last bytes
	inc	cl	# check -1 ( 2 bytes )
	jz	1f
	inc	cl	# check -2 ( 1 byte )
	jnz	2b	# no: must be -3, so done.

	# handle 1 bytes:
	rol	edx, 8 + 16 + 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb

	rol	edx, 6
	mov	al, dl
	and	al, 0b111111
	xlatb
	stosb

	mov	ax, '=' | '=' << 8
	stosw
	jmp	2b

1:	# handle 2 bytes:
	bswap	edx
	rol	edx, 6

	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb

	rol	edx, 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb

	rol	edx, 6
	mov	al, dl
	and	al, 0b00111111
	xlatb
	stosb

	mov	al, '='
	stosb
	jmp	2b



# in: eax = len
# out: eax = base64 len
base64_encoded_len:
	# (eax + 2) / 3 * 4 + 1
	push_	edx ebx
	mov	ebx, 3
	add	eax, 2
	xor	edx, edx
	shl	eax, 2
	idiv	ebx
	inc	eax
	pop_	ebx edx
	ret

##################################################
# decoding

# in: esi, ecx
# in: edi
base64_decode:
	test	ecx, 3
	jnz	91f

	push	ebx
	sub	esp, 128
	mov	ebx, esp

	shr	ecx, 2

	call	base64_make_decode_table$
	# read 4, write 3


0:	lodsd
	test	eax, 0x80808080
	jnz	9f

	xor	edx, edx	# clear high 2 bits of dl

	xlatb
	mov	dl, al
	shl	edx, 6
	shr	eax, 8

	xlatb
	or	dl, al
	shl	edx, 6
	shr	eax, 8

	xlatb
	or	dl, al
	shl	edx, 6
	shr	eax, 8

	xlatb
	or	dl, al

	shl	edx, 8
	bswap	edx

	mov	eax, edx
	stosd
	dec	edi

	loop	0b

	mov byte ptr [edi], 0

0:	add	esp, 128
	pop	ebx
	ret

9:	printlnc 4, "base64_decode: invalid characters"
	debug_dword eax
	jmp	0b
91:	printlnc 4, "base64_decode: length not multiple of 4"
	ret


# in: ebx
	# create translation table
base64_make_decode_table$:
	push_	edi ecx
	mov	edi, ebx
	mov	eax, -1
	mov	ecx, 128 / 4
	rep	stosd

	xor	al, al

	lea	edi, [ebx + 'A']
	mov	ecx, 26
0:	stosb
	inc	al
	loop	0b

	add	edi, 'a' - 'Z' - 1
	mov	ecx, 26
0:	stosb
	inc	al
	loop	0b

	add	edi, '0' - 'z' -1
	mov	ecx, 10
0:	stosb
	inc	al
	loop	0b

	mov	[ebx + '+'], byte ptr 62
	mov	[ebx + '/'], byte ptr 63
	mov	[ebx + '='], byte ptr 0

	pop_	ecx edi
	ret

