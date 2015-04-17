#############################################################################
# Counting Sort

#									out
# idx		bucket		bucket	 				1 2 3
#		a b c d		[0] 0       [0]=0	bucket
# 0	c	0 0 1 0		[a] 0+1	    [1]=1	[c-1=2]++=2	. c .
# 1	a	1 0 1 0		[b] 0+1+1   [2]=2	[a-1=0]++=0	. c e
# 2	b	1 1 1 0		[c] 0+1+1+1 [3]=3	[b-1=1]++=1	b c e
#				[d] 0+1+1+1 [4]=3
#
#		bucket		bucket					out
# idx		a b c d		[0] 0	      [0]=0	bucket		1 2 3
# 0	a	1 0 0 0		[a] 0+2       [1]=2	[a-1=0]++=0	a . .
# 1	d	1 0 0 1		[b] 0+2+0     [2]=2	[d-1=3]++=2	a . d
# 2	a	2 0 0 1		[c] 0+2+0+0   [3]=2	[a-1=0]++=1	a a d
#				[d] 0+2+0+0+1 [4]=3

IN_SITU = 0

# Order of complexity: 64 + 5 = 69
.macro SORT_CLEAR_BUCKETS
	# clear buckets
	lea	edi, [_SORT_BUCKETS]
	push	ecx
	mov	ecx, 256 / 4
	rep	stosd
	stosd
	pop	ecx
.endm

# Order of complexity: 4*N
.macro SORT_COUNT
	# count: b[n] = sum(i=0..N : data[i])
1:	mov	al, [esi + ebx]
	inc	dword ptr [_SORT_BUCKETS + eax * 4 + 4]
	add	esi, edx
	loop	1b
.endm

# Order of complexity: 4 + 256 * 4 = 1028
.macro SORT_CALC_OFFSETS
	# calc offsets: b[n] = sum(i=0..n : b[i])
	mov	ecx, 256
	lea	esi, [_SORT_BUCKETS]
	xor	eax, eax
	xor	edx, edx
1:	lodsd			# a<-[0]  b<-[1]  c<-[2]
	add	[esi-4], edx	# [1]<-0  [1]<-a   [2]<-a+b
	add	edx, eax	#  0+a     a+b	   a+b+c
	loop	1b
.endm

# Order of complexity: N * 7
.macro SORT_DIRECT
1:	mov	al, [esi + ebx]	# original data
	mov	edi, [_SORT_BUCKETS + eax * 4]	# get offset
	inc	dword ptr [_SORT_BUCKETS + eax * 4]	# inc offset
	add	edi, [_SORT_IDX]
	mov	[edi], esi	# store pointer
	add	esi, edx
	loop	1b
	# [_SORT_IDX] contains the sorted pointers to the elements
.endm

# Order of complexity: N * 8
.macro SORT_POINTERS
	# iterate over sorted pointers
1:	mov	eax, [esi]	# get pointer to original data
	movzx	eax, byte ptr [eax + ebx]	# original data
	mov	edi, [_SORT_BUCKETS + eax * 4]	# get offset
	inc	dword ptr [_SORT_BUCKETS + eax * 4]	# inc offset
	add	edi, [_SORT_IDX]
	mov	[edi], esi	# store pointer
	add	esi, 4
	loop	1b
.endm

# Order of complexity: 3 + (c&3) + 3 + c/4 = 6..9 + c/4
.macro SORT_COPY
	mov	eax, ecx
	shr	ecx, 2
	rep	movsd
	mov	cl, al
	and	cl, 3
	rep	movsb
.endm

# in: esi = an array of structs
# in: ecx = number of items in array
# in: edx = structure element size
#[in: eax = start offset within element]
#[in: ebx = length of element part to use in comparison]
sort:
	push	ebp
	push	edx
	push	ecx
	push	esi
	_SORT_BUCKETSIZE = 257 * 4
	sub	esp, _SORT_BUCKETSIZE
	mov	ebp, esp
	_SORT_BUCKETS	= ebp
	_SORT_ARRAY	= ebp + _SORT_BUCKETSIZE + 0
	_SORT_LEN	= ebp + _SORT_BUCKETSIZE + 4
	_SORT_ITEMSIZE	= ebp + _SORT_BUCKETSIZE + 8
	.if IN_SITU
	_SORT_SCRATCH	= ebp - 4
	mov	eax, esp
	sub	eax, edx
	sub	eax, 4
	push	eax
	sub	esp, eax
	.else
	_SORT_IDX	= ebp - 4
	mov	eax, 4	# pointers
	imul	eax, ecx
	call	mallocz
	jc	9f
	push	eax
	.endif


	xor	eax, eax

	mov	ebx, edx
######################################
# Order of complexity: 1 * (6 + [...])
	dec	ebx
	jz	8f
	SORT_CLEAR_BUCKETS	# O(69)
	SORT_COUNT		# O(4N)
	SORT_CALC_OFFSETS	# O(1028)

	# sort
	mov	ecx, [_SORT_LEN]
	mov	edx, [_SORTY_ITEMSIZE]
	mov	esi, [_SORT_ARRAY]
	xor	eax, eax
	.if IN_SITU
	.else
	SORT_DIRECT		# O(7N)
	.endif
# Order of complexity:		# O(69 + 1028 + 4N + 7N) = O(1097 + 11N)
######################################
# Order of complexity: c * (3 + 2 + 4 + [...])
0:	dec	ebx
	jz	8f

	SORT_CLEAR_BUCKETS	# O(69)

	mov	esi, [_SORT_ARRAY]
	mov	ecx, [_SORT_LEN]
	#mov	edx, [_SORT_ITEMSIZE]
	SORT_COUNT		# O(4N)
	SORT_CALC_OFFSETS	# O(1028)

	# sort
	mov	ecx, [_SORT_LEN]
	mov	edx, [_SORTY_ITEMSIZE]
	mov	esi, [_SORT_IDX]
	xor	eax, eax
	.if IN_SITU
	.else
	SORT_POINTERS		# O(8N)
	.endif
######################################
	jmp	0b
# Order of complexity:		# (c-1) * O(69 + 1028 + 4N + 8N) = (c-1) * O(1097 + 12N)

# Total: O( 1097*2*c + 11N + 12N * (c-1))
# For c generally 4 (sorting dwords/floats:)
# O(2194*4 + 11N+ 36N) = O(8776 + 47N)
8:

	# calculate swap order
	mov	esi, [_SORT_IDX]








	.if !IN_SITU
	# we have the pointers sorted, reorganize data:
	mov	ebx, [_SORT_LEN]
	mov	edx, [_SORT_IDX]
1:	
	# copy target to scratch
	mov	ecx, [_SORT_ITEMSIZE]
	mov	esi, [edx]
	mov	edi, [_SORT_SCRATCH]
	SORT_COPY	# O(9..9 + c/4)
	# copy source to target
	mov	ecx, [_SORT_ITEMSIZE]
	mov	esi, edx	# calculate index in original array
	sub	esi, [_SORT_IDX]# esi = idx * 4
	shr	esi, 2
	imul	esi, ecx	# esi = idx * [_SORT_ITEMSIZE]
	add	esi, [_SORT_ARRAY]
	mov	edi, [edx]
	SORT_COPY	# O(9..9 + c/4)

	add	edx, 4
	dec	ebx
	jnz	1b

	pop	eax
	call	mfree
	.endif
9:	pop	esi
	pop	ecx
	pop	edx
	pop	ebp
	ret
