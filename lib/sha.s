##############################################################################
# SHA1  RFC 3174

.intel_syntax noprefix
.text32

SHA1_DEBUG = 0

# in: esi = source ptr (paddable to next 64byte/512bit boundary)
# in: ecx = source len
# in: edi = pointer to 160 bits (20 bytes)
sha1:
	push_	eax ebx ecx edx ebp

	.if SHA1_DEBUG
		DEBUG "sha1"
		call	nprintln
		DEBUG_DWORD ecx, "sha1 inlen"
	.endif

	call	sha_pad	# destroys eax, edx; updates ecx

	.if SHA1_DEBUG
		DEBUG_DWORD ecx, "sha1 padded len"
		call	newline
		call	sha_dump
	.endif

	sub	esp, 5*4 + 5*4 + 80*4
	mov	ebp, esp

	SHA_A = 0
	SHA_B = 4
	SHA_C = 8
	SHA_D = 12
	SHA_E = 16

	SHA_H0 = 20
	SHA_H1 = 24
	SHA_H2 = 28
	SHA_H3 = 32
	SHA_H4 = 36

	SHA_W0 = 40
	SHA_W79 = 40 * 79*4

	mov	[ebp + SHA_H0], dword ptr 0x67452301
	mov	[ebp + SHA_H1], dword ptr 0xEFCDAB89
	mov	[ebp + SHA_H2], dword ptr 0x98BADCFE
	mov	[ebp + SHA_H3], dword ptr 0x10325476
	mov	[ebp + SHA_H4], dword ptr 0xC3D2E1F0

	shr	ecx, 9	# 512 bits
	inc	ecx
0:	push	ecx
	call	sha1_block
	pop	ecx
	loop	0b

	# processing done: hash is H0,...H4
	push	esi
	lea	esi, [ebp + SHA_H0]
	mov	ecx, 5
0:	lodsd
	bswap	eax
	stosd
	loop	0b
	sub	edi, 20# 5 dwords = 5 * 4 * 8 bits = 20 * 8 = 160 bits

	.if SHA1_DEBUG
		print "SHA1: "
		DEBUG_DWORD edi
		mov	esi, edi
		mov	ecx, 5
	0:	lodsd
		mov	edx, eax
		bswap	edx
		call	printhex8
		call	printspace
		loop	0b
		call	newline
	.endif
	pop	esi

	add	esp, 5*4 + 5*4 + 80*4
	pop_	ebp edx ecx ebx eax
	ret

# process 512 bits/64 bytes
#
# in: ebp = scratch
# in: esi = data
# destroys: ecx, eax
sha1_block:
	.if SHA1_DEBUG
		DEBUG "Pre process: "
		call	sha_print_h
		call	newline
	.endif

	# a. 16 dwords: SHA_W0..SHA_W15
	push	edi
	lea	edi, [ebp + SHA_W0]
	mov	ecx, 16
#	rep	movsd
0:	lodsd
	bswap	eax
	stosd
	loop	0b
	pop	edi

	.if SHA1_DEBUG
		call sha_print_w
	.endif

	# b. words 16..79:
	mov	ecx, 16
0:
	# W(t) = S^1(W(t-3) XOR W(t-8) XOR W(t-14) XOR W(t-16))
	# where S^1 = rol 1

	mov	eax, [ebp + SHA_W0 + ecx * 4 -  3*4]
	xor	eax, [ebp + SHA_W0 + ecx * 4 -  8*4]
	xor	eax, [ebp + SHA_W0 + ecx * 4 - 14*4]
	xor	eax, [ebp + SHA_W0 + ecx * 4 - 16*4]
	rol	eax, 1
	mov	[ebp + SHA_W0 + ecx * 4], eax

	inc	ecx
	cmp	ecx, 80
	jb	0b

	# c. A = SHA_H0, B=SHA_H1.. E=SHA_H4
	push_	esi edi
	lea	esi, [ebp + SHA_H0]
	lea	edi, [ebp + SHA_A]
	mov	ecx, 5
	rep	movsd
	pop_	edi esi
	.if SHA1_DEBUG
		call sha_print_a
	.endif

	# d. words 0..79:
	xor	ecx, ecx
0:	# TEMP = S^5(A) + f(cl,B,C,D) + E + W(t) + K(t)
	mov	eax, [ebp + SHA_A]
	rol	eax, 5				# S^5(A)

	call	sha_f	# out: ebx
	add	eax, ebx			# + f(cl,B,C,D)

	add	eax, [ebp + SHA_E]		# + E
	add	eax, [ebp + SHA_W0 + ecx * 4]	# + W(t)
	call	sha_k				# + K(t)

	# E = D;
	mov	ebx, [ebp + SHA_D]
	mov	[ebp + SHA_E], ebx

	# D = C;
	mov	ebx, [ebp + SHA_C]
	mov	[ebp + SHA_D], ebx

	# C = S^30(B);
	mov	ebx, [ebp + SHA_B]
	rol	ebx, 30
	mov	[ebp + SHA_C], ebx

	# B = A;
	mov	ebx, [ebp + SHA_A]
	mov	[ebp + SHA_B], ebx

	# A = TEMP
	mov	[ebp + SHA_A], eax

	.if SHA1_DEBUG
		mov dl, cl
		call printhex2
		print ": "
		call sha_print_a
	.endif

	inc	cl
	cmp	cl, 80
	jb	0b


	# e. H0+=A, H1+=B, H2+=C, H3+=D, H4+=E
	mov	ecx, 5
0:	mov	eax, [ebp + SHA_A + ecx*4 -4]
	add	[ebp + SHA_H0 + ecx * 4 -4], eax
	loop	0b

	.if SHA1_DEBUG
		DEBUG "Block processed: "
		call	sha_print_h
		call	newline
	.endif

	ret



########################################################
#### staged version
# sha1_init
# sha1_next
# sha1_finish

# in: ebx = sha1 state buffer: 360 bytes
sha1_init:
	push_	eax ebx ecx edx ebp
	mov	ebp, ebx

	SHA_A = 0
	SHA_B = 4
	SHA_C = 8
	SHA_D = 12
	SHA_E = 16

	SHA_H0 = 20
	SHA_H1 = 24
	SHA_H2 = 28
	SHA_H3 = 32
	SHA_H4 = 36

	SHA_W0 = 40
	SHA_W79 = 40 * 79*4

	mov	[ebp + SHA_H0], dword ptr 0x67452301
	mov	[ebp + SHA_H1], dword ptr 0xEFCDAB89
	mov	[ebp + SHA_H2], dword ptr 0x98BADCFE
	mov	[ebp + SHA_H3], dword ptr 0x10325476
	mov	[ebp + SHA_H4], dword ptr 0xC3D2E1F0

	pop_	ebp edx ecx ebx eax
	ret



# in: ebx = sha1 state buffer
# in: esi = source ptr (paddable to next 64byte/512bit boundary)
# in: ecx = source len
sha1_next:
	push_	esi eax ecx edx ebp
	mov	ebp, ebx

	call	sha_pad

	shr	ecx, 9	# 512 bits
	inc	ecx
0:	push	ecx
	call	sha1_block
	pop	ecx
	loop	0b


	.if SHA1_DEBUG
		DEBUG_DWORD ecx, "sha1 padded len"
		call	newline
		call	sha_dump
	.endif

	pop_	ebp edx ecx eax esi
	ret


# in: ebx = sha1 state buffer
# in: edi = pointer to 160 bits (20 bytes)
sha1_finish:
	# processing done: hash is H0,...H4
	push_	esi eax
	lea	esi, [ebx + SHA_H0]
	.rept 5	# saves push, pop, 5x loop
	# unrolled loop:
	#   15 instr: 10 mem, 5 bswap
	# loop:
	#   22 instr: 12 mem, 5 bswap, 5 loop
	lodsd
	bswap	eax
	stosd
	.endr
	sub	edi, 20# 5 dwords = 5 * 4 * 8 bits = 20 * 8 = 160 bits

	.if SHA1_DEBUG
		push_	edx ecx
		print "SHA1: "
		DEBUG_DWORD edi
		mov	esi, edi
		mov	ecx, 5
	0:	lodsd
		mov	edx, eax
		bswap	edx
		call	printhex8
		call	printspace
		loop	0b
		call	newline
		pop_	ecx edx
	.endif

	pop_	eax esi
	ret


#########################################
# internal functions


sha_k:	cmp	cl, 20
	jb	sha_k0
	cmp	cl, 40
	jb	sha_k1
	cmp	cl, 60
	jb	sha_k2
	cmp	cl, 80
	jb	sha_k3
	DEBUG_BYTE cl, "sha_k: wrong number, must be 0..79"
	int 1

# similar to sha_f, we could put the constant in ebx for it to be added
# by the caller; however, the only use for these constants is to add to eax.
sha_k0:	add	eax, 0x5A827999  #       ( 0 <= t <= 19)
	ret
sha_k1:	add	eax, 0x6ED9EBA1  #       (20 <= t <= 39)
	ret
sha_k2:	add	eax, 0x8F1BBCDC  #       (40 <= t <= 59)
	ret
sha_k3:	add	eax, 0xCA62C1D6  #       (60 <= t <= 79).
	ret


sha_f:	cmp	cl, 20
	jb	sha_f0
	cmp	cl, 40
	jb	sha_f1
	cmp	cl, 60
	jb	sha_f2
	cmp	cl, 80
	jb	sha_f3
	DEBUG_BYTE cl, "sha_f: wrong number, must be 0..79"
	int 1


sha_f0:	# (B and C) or ((NOT B and D))
	mov	ebx, [ebp + SHA_B]
	mov	edx, ebx
	and	ebx, [ebp + SHA_C]
	not	edx
	and	edx, [ebp + SHA_D]
	or	ebx, edx
	ret

sha_f1:	# B XOR C XOR D
sha_f3:	# B XOR C XOR D
	mov	ebx, [ebp + SHA_B]
	xor	ebx, [ebp + SHA_C]
	xor	ebx, [ebp + SHA_D]
	ret

sha_f2:	# (B AND C) OR (B AND D) OR (C AND D)
	mov	ebx, [ebp + SHA_B]
	mov	edx, ebx
	and	ebx, [ebp + SHA_C]	# B AND C
	and	edx, [ebp + SHA_D]	# B AND D
	or	ebx, edx
	mov	edx, [ebp + SHA_C]
	and	edx, [ebp + SHA_D]	# C AND D
	or	ebx, edx
	ret

# out: ecx = new message len
# destroys: eax, edx
sha_pad:
	push	edi
	xor	eax, eax
	lea	edi, [esi + ecx]

	# pad
	mov	edx, ecx
	push	ecx
	mov	ecx, 64

	# we need to append a 1 bit,
	# then pad with 0 bits until the offset & 512bits is 448 bits,
	# then store the message length in 8 bytes (64 bits)
	# 512 bits = 64 bytes
	# 448 bits = 64 - 8 = 56 bytes
	and	edx, 63
	sub	ecx, edx
	jz	1f	# no room at all
	# ecx is the room in the last block.
	cmp	ecx, 9	# 8 bytes len, 1 bit(byte) pad:
	ja	2f	# enough room.
	# not enough room.
	rep	stosb	# clear the remainder
	# append whole block
1:	mov	ecx, 64
2:	mov	dl, cl
	shr	ecx, 2
	rep	stosd
	mov	cl, dl
	and	cl, 3
	rep	stosb
###
	pop	ecx
	mov	byte ptr [esi + ecx], 0x80
	shl	ecx, 3	# length in bits
	bswap	ecx
	mov	[edi - 4], ecx
	mov	ecx, edi
	sub	ecx, esi
	pop	edi
	ret


##############################################################################
## debug utility
.if SHA1_DEBUG
sha_dump:
	push_	eax edx esi ecx
	xor	dh, dh
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	inc	dh
	cmp	dh,16
	jz	1f
2:	loop	0b
	call	newline
	pop_	ecx esi edx eax
	ret
1:	call	newline
	xor	dh, dh
	jmp	2b


sha_print_w:
	push	esi
	lea	esi, [ebp + SHA_W0]
	mov	ecx, 16
0:	print "W["
	mov	edx, 16
	sub	edx, ecx
	call	printhex2
	print "] = "

	lodsd
	mov	edx, eax
	call	printhex8
	call	newline
	loop	0b
	pop	esi
	ret

sha_print_h:
	push_	esi edx ecx eax
	lea	esi, [ebp + SHA_H0]
	mov	ecx, 5
0:	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	loop	0b
	pop_	eax ecx edx esi
	ret

sha_print_a:
	push_	esi edx ecx eax
	lea	esi, [ebp + SHA_A]
	mov	ecx, 5
0:	mov	al, 'F'
	sub	al, cl
	call	printchar
	print " = "
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	loop	0b
	call	newline
	pop_	eax ecx edx esi
	ret
.endif
