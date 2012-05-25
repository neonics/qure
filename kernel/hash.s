.intel_syntax noprefix
.code32
# requires ll_* - list.s (currently asm.s)
############################################ Two dimensional linked list
.struct 0
# horizontal linked list:
ll_h_value: .long 0	
ll_h_prev: .long 0
ll_h_next: .long 0
# vertical linked list: references pointing down a layer.
ll_v_value: .long 0	# value is tested for nonzero. If 0, it's a reference.
ll_v_prev: .long 0
ll_v_next: .long 0
LL_2D_STRUCT_SIZE = 6*4
.text
# this struct can be overlayed. Either value will serve, as both the base and
# size will be nonzero, and thus can serve as a flag to indicate whether
# or not it is a pointer.
find_by_size_r0$:
0:	cmp	eax, [esi + ebx + ll_h_value]
	jb	1f	# the smallest item can accommodate it
	mov	edx, [esi + ebx + ll_h_next]
	or	edx, edx
	mov	ebx, edx
	jns	0b	# there is a next, so continue
	stc
	ret

1:	cmp	[ecx + ebx + ll_v_value], dword ptr 0
	jz	0f	# not a reference, found it!
	mov	ebx, [ecx + ebx + ll_v_next]	# handle reference
	# it might be possible for a bottom reference node to be 'dangling',
	# and not have a non-reference node as a child. If so, this is an error.
	# or ebx, ebx
	# js error
	jmp	0b

0:	clc
	ret


# One of the fields needs to be chosen for ordering, which affects the
# layout of the 'base' class (putting size before or after base),
# and also limits the application of this 'hash' to either size or base.
# The most dynamic is to not have the two linked list predefined as
# having a fixed distance, as this allows the code to re-use fields
# that are not in use to be repurposed to the reference handle.
# So we'll add edx (or ecx) as a parameter for the vertical.
#
# in: esi = base pointer for horizontal (esi+ebx = h fields in ebx)
# in: ecx = base pointer for vertical   (ecx+ebx = v fields in ebx)
find_by_size_r$:
	# horizontal:
0:	cmp	eax, [esi + ebx + ll_value]
	jb	1f	# the smallest item can accommodate it
	mov	edx, [esi + ebx + ll_next]
	or	edx, edx
	mov	ebx, edx
	jns	0b	# there is a next, so continue
	# eax preserved. When here, this is the last node, that is not
	# large enough.
	# If it is a reference node, it might have larger children.
	# However, it would be most convenient to mark the last node,
	# and not see it as a reference node, but as the node marking
	# the biggest available size: the last node itself from handle_fa.
	# The last node of handle_as would need to point to this in order
	# to move left.
	# as such, if the last node does not accommodate the size, abort.
	stc
	ret
	# specialized code, uses handle_flags. Might generalize the location
	# of the value, but not the test code. Might use ll_value2, but it
	# would have to be indirectly provided [edi], as a const prevents
	# interleaving the ll_next (break the struct).

	# vertical:
1:	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_REFERENCE
	jz	0f	# not a reference, found it!
	# it's a reference. Going deeper.
	mov	ebx, [ecx + ebx + ll_next]	# handle reference
	jmp	0b

0:	clc
	ret

###########################################################################

hash_test:
	.data
		numbers$: .long 0
		hash$: .long 0
	.text
	# set up an array of numbers, from 0 to 1023
	mov	eax, 1024 * 4
	call	malloc
	mov	[numbers$], eax
	mov	edi, eax
	mov	ecx, 1024
	xor	eax, eax
0:	stosd
	inc	eax
	loop	0b

	
	.data
		hash_first$: .long -1
		hash_last$: .long -1
	.text

	mov	edi, offset hash_first$
	call	hash_new_node
	
	ret


##################

HASH_INITIAL_CAPACITY = 16

# in: edi = ll_first/ll_last
hash_new_node:
	cmp	dword ptr [edi], -1
	jne	0f

	mov	eax, LL_2D_STRUCT_SIZE * HASH_INITIAL_CAPACITY
	call	malloc

0:
	ret

#################
BUF_OBJECT_SIZE = 5*4
.struct -BUF_OBJECT_SIZE
buf_base: .long 0	# memory pointer
buf_capacity: .long 0	# pointer to capacity relative to base
buf_index: .long 0	# pointer to the last used element in the buf
buf_itemsize: .long 0 # number of bytes per item 
buf_growsize: .long 0 # bytes to add on each mrealloc
.text
# in: eax = initial capacity
# in: esi = pointer to buf metadata being updated
buf_new:
	mov	[esi + buf_capacity], eax
	mov	[esi + buf_index], dword ptr 0
	add	eax, BUF_OBJECT_SIZE
	call	malloc
	mov	[esi + buf_base], eax
	ret

# in: eax = size to add (in bytes)
# in: esi = pointer to buf metadata
buf_grow:
	push	edx
	mov	edx, eax
	add	edx, [esi + buf_capacity]
	mov	eax, [esi + buf_base]
	push	eax
	call	mrealloc
	mov	[esi + buf_base], eax
	pop	dword ptr [esi + buf_capacity]
	pop	edx
	ret

# in: esi = buf metadata
# out: esi+eax = pointer to item
buf_newitem:
	mov	eax, [esi + buf_index]
	cmp	eax, [esi + buf_capacity]
	jb	0f
	mov	eax, [esi + buf_growsize]
	call	buf_grow

	mov	eax, [esi + buf_index]
	cmp	eax, [esi + buf_capacity]
	jb	0f

0:	
	ret
