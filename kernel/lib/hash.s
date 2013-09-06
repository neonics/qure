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

.if DEFINE
.text32
###########################################################################

hash_test:
	.data
		numbers$: .long 0
		hash$: .long 0
	.text32
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
	.text32

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
.text32
# in: eax = initial capacity
# out: eax = pointer to BUF object.
buf_new:
	push	ebp
	lea	ebp, [esp + 4]
	call	buf_new_
	pop	ebp
	ret

buf_new_:
	push	eax

	.if BUF_DEBUG
		push edx
		printc 5, "buf_new("
		mov edx, eax
		call printdec32
		printc 5, "): "
		pop edx
	.endif

	add	eax, 8
	call	mallocz_
	jc	9f
	pop	[eax]
	mov	[eax + 4], dword ptr 0
	add	eax, 8

	.if BUF_DEBUG
		pushf
		push edx
		mov edx, eax
		call printhex8
		call newline
		pop edx
		popf
	.endif
	ret

9:	pop	eax
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
	push	ebp
	lea	ebp, [esp + 4]
	call	buf_resize_
	pop	ebp
	ret

buf_resize_:
	.if BUF_DEBUG
		printc 5, "buf_resize("
		call printdec32
		printc 5, ", "
		push edx
		mov edx, eax
		call printhex8
		printc 5, " called from "
		mov edx, [ebp]
		call printhex8
		printc 5, ": "
		pop edx
	.endif
push edi
push ecx
##
push dword ptr [eax + buf_capacity]
	sub	eax, 8
	push	edx
	add	edx, 8
	call	mreallocz_	# mrealloc: crashes vm sometimes
	add	eax, 8
	pop	dword ptr [eax + buf_capacity]
mov ecx, [eax + buf_capacity] # new cap
pop edi # old cap
sub ecx, edi # added cap
add edi, eax
#
push eax
xor eax, eax
rep stosb
pop eax
##
pop ecx
pop edi

	.if BUF_DEBUG
		pushf
		push edx
		mov edx, eax
		call printhex8
		call newline
		pop edx
		popf
	.endif
	ret


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
	push	ebp
	lea	ebp, [esp + 4]
	push	edx
	mul	ecx
	# assume edx = 0
	call	buf_new_	# in: eax; out: eax
	pop	edx
	pop	ebp
	ret

array_free:
	call	buf_free
	ret

# in: eax = buf/array base pointer
# in: ecx = entry size
# out: edx = relative offset
# out: eax = base pointer (might be updated due to realloc)
array_newentry:
	push	ebp
	lea	ebp, [esp + 4]
	mov	edx, [eax + buf_index]
	push	edx
	add	edx, ecx
	cmp	edx, [eax + buf_capacity]
	pop	edx
	jb	0f

	add	edx, ecx # MTAB_ENTRY_SIZE
	# optionally: increase grow size
	call	buf_resize_	# in: eax, out: eax
	mov	edx, [eax + buf_index]
0:	add	[eax + buf_index], ecx # dword ptr MTAB_ENTRY_SIZE
	# REMEMBER: eax might be updated, so always store it after a call!
	pop	ebp
	ret
.endif

.ifndef __HASH_DECLARED
.macro ARRAY_ITER_START base, index
	xor	\index, \index
	jmp	91f
90:	
.endm

.macro ARRAY_ITER_NEXT base, index, size
	add	\index, \size
91:	cmp	\index, [\base + array_index]
	jb	90b
.endm
.endif

.if DEFINE
##################################################
# Pointer Array

ptr_array_new:
	push	ebp
	lea	ebp, [esp + 4]
	push	edx
	shl	eax, 2
	call	buf_new_
	pop	edx
	pop	ebp
	ret


ptr_array_newentry:
	push	ebp
	lea	ebp, [esp + 4]
	mov	edx, [eax + array_index]
	cmp	edx, [eax + array_capacity]
	jb	0f
	add	edx, 4*4
	call	buf_resize_
	mov	edx, [eax + array_index]
0:	add	[eax + array_index], dword ptr 4
	pop	ebp
	ret
.endif

.ifndef __HASH_DECLARED
.macro PTR_ARRAY_ITER_START base, index, ref
	xor	\index, \index
	jmp	91f
90:	mov	\ref, [\base + \index]
.endm

.macro PTR_ARRAY_ITER_NEXT base, index, ref
	add	\index, 4
91:	cmp	\index, [\base + array_index]
	jb	90b
.endm
.endif

##################################################

.if DEFINE

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

.endif

.ifndef __HASH_DECLARED
__HASH_DECLARED=1
	.macro ARRAY_LOOP arrayref, entsize, base=eax, index=edx, errlabel=9f
		L_entsize = \entsize
		L_base = \base
		L_index = \index

		mov	\base, \arrayref
		or	\base, \base
		jz	\errlabel
		ARRAY_ITER_START \base, \index
	.endm


	.macro ARRAY_ENDL
		ARRAY_ITER_NEXT L_base, L_index, L_entsize
	.endm

	# modifies ecx, eax, edx
	.macro ARRAY_NEWENTRY arrayref, entsize, initcapacity, errlabel
		mov	ecx, \entsize
		mov	eax, \arrayref
		or	eax, eax
		jnz	66f
		mov	eax, \initcapacity
		call	array_new
		jc	\errlabel
	66:	call	array_newentry
		jc	\errlabel
		mov	\arrayref, eax
	.endm

	# modifies eax, edx
	.macro PTR_ARRAY_NEWENTRY arrayref, initcapacity, errlabel
		mov	eax, \arrayref
		or	eax, eax
		jnz	66f
		mov	eax, \initcapacity
		call	ptr_array_new
		jc	\errlabel
	66:	call	ptr_array_newentry
		jc	\errlabel
		mov	\arrayref, eax
	.endm
.endif
