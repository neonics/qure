# http://tools.ietf.org/html/rfc1951
.intel_syntax noprefix

MEM = 1
SPEED = 0
OPTIMIZE = SPEED


.if OPTIMIZE == SPEED
PTRSIZE = dword
.else
PTRSIZE = byte
.endif
MEMFACT = 4/(1+3*OPTIMIZE)

# in: esi, ecx = data
# in: edi = dest buffer, min 10Kb size
huffman_encode:
	sub	esp, 8*MEMFACT
	mov	ebp, esp	# local variables
	mov	edx, ecx	# free up ecx for loop

# count bitlengths
	# clear
	mov	edi, esp
	xor	eax, eax
	.rept 8 / (1 + 3*OPTIMIZE)	# speed: 8 dwords; mem: 8 bytes=2 dwords
	stosd
	.endr

	# loop data, count
	xor	ebx, ebx
	mov	ecx, edx
0:	lodsb
	bsr	bl, al
	inc	PTRSIZE ptr [ebp + ebx*MEMFACT]
	loop	0b

	# calc code sizes
	mov	ecx, 256
0:	xor	ah, ah
	.rept 8
	lodsb
	shr	al, 1
	adc	ah, 0
	.endr
	mov	[edi + 288*MEMFACT], ah
	inc	edi
	loop	0b
	sub	edi, 288*MEMFACT

	# generate codes
	mov	ecx, 2
	xor	ebx, ebx	# code counter
0:	cmp	PTRSIZE ptr [edi], 0
	jz	1f

	mov	al, [edi]
	mov	[edi + ebx], 

1:


	ret
########################################


# bit-compress:
# bit: 1: first symbol, done.
# bit: 0: other symbol, continue
#
# bit: 0: second symbol, done.
# bit: 1: next symbol, continue
	ret

bucket_sort:
	call	hufman_freqtab	# edi contains freqtab.
	call	hufman_sort
	ret

memclear$:
	xor	eax, eax
	mov	ecx, 288 / (1+3*OPTIMIZE)	# MEM: /4 SPEED: /1
	rep	stosd
	sub	edi, 288 * (1+3*OPTIMIZE)
	ret

# in: edi = freqtab ptr
# in: edx = source len
# in: esi = source
# purpose: create a frequency analysis of source data.
# implementation: store byte-normalized counts in freqtab
huffman_freqtab:

	mov	ebx, ecx
0:	lodsb
.if OPTIMIZE == MEM
	inc	byte ptr [edi + eax]
	jz	freqtab_shrink$		# mem footprint optimization
.else
	inc	dword ptr [edi + eax]
.endif
1:	dec	ebx
	jnz	0b

	sub	esi, edx
	ret

# halves all counts: order bit-loss on relatively low counts.
freqtab_shrink_1$:
	dec	byte ptr [edi + eax]	# make sure it ends up 0x7f
	mov	ecx, edx
0:	shr	byte ptr [edi], 1	# alt impl: dec
	inc	edi
	loop	0b
	sub	edi, edx
	jmp	1b

# another alg:
# add a second loop to find the minimum (not 0),
# and use that to subtract. The difference between min/max then
# cannot exceed, but bytes will be 'pushed out' and lost also...
# decrements all - zero becomes max.
freqtab_shrink_2$:
	mov	ecx, edx
0:	dec	byte ptr [edi]
	adc	dword ptr [ebp], 0	# count
	inc	edi
	loop	0b
	sub	edi, edx
	jmp	1b

# in: edi = freqtab
huffman_sort:
	lea	ebx, [edi + 288*(1+3*OPTIMIZE)]

	ret
