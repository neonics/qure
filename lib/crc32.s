##################################################################
# ISO 3309 / ITU-T V.42
.intel_syntax noprefix

.data
crc32_table$:	.space 1024	# 256 dwords

.text32
crc32_calctable:
	push	ebx
	mov	ebx, 0xedb88320 # standard: 0xedb88320; ethernet: 0x104C11DB7 (magic const: 0xC704DD7B)
	call	crc32_calctable_
	pop	ebx
	ret

# in: ebx = polynomial
crc32_calctable_:
	push_	eax ecx edx
	xor	ecx, ecx
	xor	al, al
0:	mov	edx, ecx
	mov	ah, 8
1:	shr	edx, 1
	jnc	2f
	xor	edx, ebx
2:	dec	ah
	jnz	1b
3:
	mov	[crc32_table$ + ecx * 4], edx

	inc	cl
	jnz	0b

	pop_	edx ecx eax
	ret

# in: esi = data
# in: ecx = datalen
# out: eax = crc32
crc32:
	xor	eax, eax
# KEEP-WITH-NEXT fallthrough

# in: eax = crc
# in: esi = data
# in: ecx = datalen
# out: eax = crc
update_crc32:
	push_	ecx edx esi 
	mov	edx, -1
	xor	edx, eax
	cmpb	[crc32_table$ + 4], 0
	jz	61f
16:
	xor	eax, eax
	lodsb	# buf[n] & 0xff
	xor	al, dl	# c ^
	mov	eax, [crc32_table$ + eax * 4]
	shr	edx, 8
	xor	edx, eax
	loop	16b

	mov	eax, -1
	xor	eax, edx
	pop_	esi edx ecx
	ret

61:	call	crc32_calctable
	jmp	16b
