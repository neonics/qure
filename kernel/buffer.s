#############################################################################
# Buffer
.intel_syntax noprefix
BUFFER_STRUCT_SIZE = 16
.struct -BUFFER_STRUCT_SIZE
buffer_max:	.long 0
buffer_start:	.long 0
buffer_capacity:.long 0
buffer_index:	.long 0
.text32

# MAX size is not used yet.

# in: eax = size
# in: edx = max size
buffer_new:
	push	eax
	add	eax, BUFFER_STRUCT_SIZE
	call	mallocz
	jc	9f
	add	eax, BUFFER_STRUCT_SIZE
	mov	[eax + buffer_max], edx
	pop	dword ptr [eax + buffer_capacity]
	ret
9:	printc 4, "buffer_new: out of memory"
	pop	eax
	stc
	ret

buffer_free:
	sub	eax, BUFFER_STRUCT_SIZE
	jmp	mfree

# in: eax = buffer
# in: esi = data
# in: ecx = size
# out: CF = 1: won't fit - no data copied
buffer_write:
	push	edi
	push	esi
	push	ecx
	push	edx

	mov	edx, [eax + buffer_index]
	add	edx, ecx
	cmp	edx, [eax + buffer_capacity]
	ja	buffer_compact$
2:	# compacted, append:
	mov	edi, eax
	add	edi, [eax + buffer_index]
	add	[eax + buffer_index], ecx
	mov	dl, cl
	shr	ecx, 2
	jz	1f
	rep	movsd
1:	mov	cl, dl
	and	cl, 3
	jz	1f
	rep	movsb
1:	clc
0:	pop	edx
	pop	ecx
	pop	esi
	pop	edi
	ret

buffer_compact$:
	sub	edx, [eax + buffer_start]
	cmp	edx, [eax + buffer_capacity]
	cmc
	jb	0b
	# it will fit
	push	esi
	push	ecx
	mov	edi, eax
	mov	esi, [eax + buffer_start]
	mov	ecx, [eax + buffer_index]
	sub	ecx, esi
	add	esi, eax
	mov	dl, cl
	shr	ecx, 2
	jz	1f
	rep	movsd
1:	mov	cl, dl
	and	cl, 3
	jz	1f
	rep	movsb
1:	
	xchg	ecx, [eax + buffer_start]
	sub	[eax + buffer_index], ecx
	pop	ecx
	pop	esi
	jmp	2b

buffer_put_dword:
	push	esi
	push	ecx
	push	edx		# create pointer
	mov	esi, esp
	mov	ecx, 4
	call	buffer_write
	pop	edx
	pop	ecx
	pop	esi
	ret

# in: eax = buffer
# in: dx = word
buffer_put_word:
	push	esi
	push	ecx
	push	edx		# create pointer
	mov	esi, esp
	mov	ecx, 2
	call	buffer_write
	pop	edx
	pop	ecx
	pop	esi
	ret
