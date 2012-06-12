.intel_syntax noprefix
.code32
# requires ll_* - list.s (currently asm.s)

BUF_DEBUG = 0
ARRAY_DEBUG = 0


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
BUF_OBJECT_SIZE = 8
.struct -BUF_OBJECT_SIZE
buf_capacity: .long 0	# pointer to capacity relative to base
buf_index: .long 0	# pointer to the last used element in the buf

ARRAY_OBJECT_SIZE = 16
.struct -ARRAY_OBJECT_SIZE
array_constructor: .long 0
array_destructor: .long 0
array_capacity: .long 0
array_index: .long 0

#
#buf_itemsize: .long 0 # number of bytes per item 
#buf_growsize: .long 0 # bytes to add on each mrealloc
.text
# in: eax = initial capacity
# out: eax = pointer to BUF object.
buf_new:
	push	eax

	.if BUF_DEBUG
		push edx
		printc 5, "buf_new("
		mov edx, eax
		call printdec32
		printc 5, "): "
	.endif

	add	eax, 8
	call	mallocz
	pop	[eax]
	mov	[eax + 4], dword ptr 0
	add	eax, 8

	.if BUF_DEBUG
		mov edx, eax
		call printhex8
		call newline
		pop edx
	.endif

	ret

buf_free:
	sub	eax, 8
	call	mfree
	ret

# in: eax = buffer array base pointer
# in: edx = size to add (in bytes)
# out: eax = pointer to new buffer 
# destroyed: edx
buf_grow:
	add	edx, [eax + buf_capacity]

# in: eax = buf base pointer
# in: edx = new size
# out: eax = pointer to new buffer
buf_resize:
	.if BUF_DEBUG
		printc 5, "buf_resize("
		call printdec32
		printc 5, ", "
		push edx
		mov edx, eax
		call printhex8
		printc 5, " called from "
		mov edx, [esp+4]
		call printhex8
		printc 5, ": "
		pop edx
	.endif

	sub	eax, 8
	push	edx
	add	edx, 8
	call	mrealloc
	pop	dword ptr [eax + buf_capacity]
	add	eax, 8

	.if BUF_DEBUG
		push edx
		mov edx, eax
		call printhex8
		call newline
		pop edx
	.endif
	ret

# in: esi = buf metadata
# out: esi+eax = pointer to item
#buf_newitem:
#	mov	eax, [esi + buf_index]
#	cmp	eax, [esi + buf_capacity]
#	jb	0f
#	mov	eax, [esi + buf_growsize]
#	call	buf_grow
#
#	mov	eax, [esi + buf_index]
#	cmp	eax, [esi + buf_capacity]
#	jb	0f
#
#0:	
#	ret

# in: eax = base ptr
array_appendcopy:
	mov	edi, [eax - 4]
	mov	edx, [eax - 8]
	sub	edx, edi
	cmp	ecx, edx
	jb	0f
	mov	edx, ecx
	call	buf_grow
0:
	ret



# in: ecx = entry size
# in: eax = initial entries
# out: eax = base pointer
array_new:
	push	edx
	mul	ecx
	# assume edx = 0
	call	buf_new	# in: eax; out: eax
	pop	edx
	ret

array_free:
	call	buf_free
	ret

# in: eax = buf/array base pointer
# in: ecx = entry size
# out: edx = relative offset
# out: eax = base pointer (might be updated due to realloc)
array_newentry:
	mov	edx, [eax + buf_index]
	cmp	edx, [eax + buf_capacity]
	jb	0f

	.if ARRAY_DEBUG
		printc 10, "mtab grow "
		call	printhex8
		printchar ' '
		push	edx
		mov	edx, eax
		call	printhex8
		call	newline
		pop	edx
	.endif
	
	add	edx, ecx # MTAB_ENTRY_SIZE
	# optionally: increase grow size
	call	buf_resize	# in: eax, out: eax
	mov	edx, [eax + buf_index]
0:	add	[eax + buf_index], ecx # dword ptr MTAB_ENTRY_SIZE

	.if ARRAY_DEBUG
		printc 10, "mtab_entry_alloc "
		call	printdec32
		printchar ' '
		push	edx
		mov	edx, eax
		call	printhex8
		pop	edx
		call	newline
	.endif

	# REMEMBER: eax might be updated, so always store it after a call!

	ret


# in: eax = base ptr
# in: ecx = entry size / size of memory to remove
# in: edx = entry to release
array_remove:
	add	edx, ecx
	cmp	edx, [eax + buf_capacity]
	jae	0f	# ja -> misalignment
	mov	esi, edx
	mov	edi, edx
	sub	edi, ecx
	add	esi, eax
	add	edi, eax
	push	ecx
	rep	movsb
	pop	ecx
0:	sub	[eax + buf_index], ecx
	ret


######################################### OOP ###########################

.data
DEFAULT_OBJECT_POOL_SIZE = 16
DEFAULT_OBJECT_POOL_GROW_SIZE = 4
CLASS_CLASS	= 0
CLASS_OBJECT	= 1
CLASS_ARRAY	= 2
global_class_pool: .long 0
.text

array_newinstance:
	mov	eax, CLASS_ARRAY
	#mov	eax, offset global_class_pool + eax * 4
	call	object_new
	# e
	add	edx, eax

	mov	eax, 8
	call	malloc
	mov	[edx], eax

	mov	[eax], dword ptr 0
	mov	[eax+4], dword ptr 0
	ret



# in: eax = reference to memory address holding global class pool pointer
# in: ecx = bytes to allocate for the object.
# out: eax = pointer to newly allocated object of given class.
# out: edx = reference to memory address holding pointer
#
# 2^30 bit classes (due to 32 bit limitation), dynamically allocated.

.data
foo_class:
	.long 0 # offset to class constructor
	.long 0 # bytes to allocate
	.long 0 # offset to new
	.long 0 # pool pointer (class id)
.text

test_class:
	mov	ebx, offset foo_class



	# class initialization
	# dword array
	mov	eax, [global_class_pool]
	or	eax, eax
	jz	1f	# malloc

		# check if initialized ([[global_class_pool]+[ebx+12])
	.if 1
	mov	edx, [ebx + 3*4]
	or	edx, edx
	jnz	6f
	mov	edx, [eax + 4]	# load used size
	cmp	edx, [eax]	# cmp with allocated size
	jae	2f		# realloc
0:	# [edx] is free pointer in array

2:	add	edx, 4	# grow by one pointer
	push	edx
	call	mrealloc
	pop	[eax]
	sub	edx, 4
	mov	[ebx + 3*4], edx
	ret

	.else
	lea	edx, [edx * 4 + 16]
	cmp	edx, [eax]
	jae	2f	# realloc
	.endif
0:	
	sub	edx, 16
	add	eax, 16

	mov	ecx, [eax + edx]
	or	ecx, ecx
	jz	5f
6:	add	edx, eax
	mov	eax, [ecx + 4]
	call	malloc
	mov	[edx], eax
	call	[ecx + 4]	# constructor
	ret

5:	call	[ebx]	# call class constructor
	mov	[eax + edx], ecx	# store pointer
	jmp	6b
	



object_new:


	# class initialization
	# dword array
	mov	edx, eax
	mov	eax, [global_class_pool]
	or	eax, eax
	jz	1f
	lea	edx, [edx * 4 + 16]
	cmp	edx, [eax]
	jae	2f
0:	
	sub	edx, 16
	add	eax, 16

	# eax = array/buf base
	# edx = relative offset into array/buf, guaranteed to exist.
	# append
	mov	edx, [eax+4]
	add	[eax+4], dword ptr 4
	add	edx, eax
	# [eax + edx ] = available memory address
	# eax = object array base
	# edx = pointer to object (size 4)
	ret

2:	add	edx, 4
	push	edx
	call	mrealloc
	pop	[eax]
	sub	edx, 4
	ret

# in: eax = memory pointer
# in: ecx = address of memory to hold the address
# in: edx = class number
# out: eax
1:	lea	eax, [edx * 4 + 16]
	push	eax
	call	malloc
	pop	[eax]
	mov	[global_class_pool], eax
	jmp	0b
	

##############################################################################
	mov	ecx, offset global_class_pool
	mov	eax, [ecx]
	or	eax, eax
	mov	ebx, offset 0f
	jz	2f	
	cmp	edx, [eax]
	jae	2f

# First call:
# in: eax = base address of mem to realloc
# in: edx = class number
2:	add	edx, DEFAULT_OBJECT_POOL_GROW_SIZE * 4
	call	mrealloc
	mov	[ecx], eax	# double reference: ptr->buf->size
	mov	[eax], edx	#                   ecx->eax->edx
	sub	edx, DEFAULT_OBJECT_POOL_GROW_SIZE * 4
	jmp	ebx


#
#object_new:
#	# class initialization
#	# dword array
#	mov	edx, eax
#	mov	eax, [global_class_pool]
#	or	eax, eax
#	jz	1f
#	lea	edx, [edx * 4 + 16]
#	cmp	edx, [eax]
#	jae	2f
#0:	
#	sub	edx, 16
#	add	eax, 16
#
#	# eax = array/buf base
#	# edx = relative offset into array/buf, guaranteed to exist.
#	# append
#	mov	edx, [eax+4]
#	add	[eax+4], dword ptr 4
#	add	edx, eax
#	# [eax + edx ] = available memory address
#	# eax = object array base
#	# edx = pointer to object (size 4)
#	ret
#
#2:	add	edx, 4
#	push	edx
#	call	mrealloc
#	pop	[eax]
#	sub	edx, 4
#	ret
#
## in: eax = memory pointer
## in: ecx = address of memory to hold the address
## in: edx = class number
## out: eax
#1:	lea	eax, [edx * 4 + 16]
#	push	eax
#	call	malloc
#	pop	[eax]
#	mov	[global_class_pool], eax
#	jmp	0b
#	
#
#


