###############################################################################
# Linked List with indirect pointers
#
# This file implements a digital chain.
#
#
#
# Technical Details
#
# This implementation of a linked list takes a base and offset approach so that
# the elements it refers to are capable of being stored in an array that can be
# mreallocced. To use this implementation for 'absolute' pointers, simply
# provide a zero base.
# Further, it provides maintaining an ascending ordered list.
#
# The general API is:
#
# edi: pointer to ll_first,ll_last dwords containing the first/last elements
#	of the linked list. 
# 
# esi: base pointer into array of structs, called elements from the perspective
#	of the list. The implementation is agnostic of the size of elements,
#	and therefore allows different for sized elements.
#	The only requirement is that the base pointer + the element pointer
#	point to an 'll_element' struct (ll_value, ll_prev, ll_next).
#	The ll_next/ll_prev are relative pointers to other elements.
#
# ebx: the element to be operated upon (insert, remove, displace).
#
# eax: optional: relative (i.e., insert_after, insert_before).
#
# Example for identical-sized elements:
#
# .struct 0
# foo_a: .byte 0
# foo_b: .long 0
# foo_ll_a_el: .long 0,0,0 # ll_value, ll_prev, ll_next for list 'a'
# foo_c: .word 0
# foo_ll_b_el: .long 0,0,0 # ll_value, ll_prev, ll_next for list 'b'.
# FOO_STRUCT_SIZE = .
#
# .data
# foo_ll_a: .long 0,0 # ll_first, ll_last for list 'a'
# foo_ll_b: .long 0,0 # ll_first, ll_last for list 'b'
# foo_array: .long 0	# array base pointer
#
# .text32
# foo_init:
#	mov	eax, FOO_STRUCT_SIZE * 3
#	call	mallocz
#	mov	[foo_array], eax
#
# foo_add_a:
# 	mov	esi, [foo_array]
#	add	esi, offset foo_ll_a_el
#	mov	edi, offset foo_ll_a
#	xor	ebx, ebx			# entry 0
#	call	ll_insert
#	add	ebx, FOO_STRUCT_SIZE
#	call	ll_append
#
# foo_add_b:
#	mov	esi, [foo_array]
#	add	esi, offset foo_ll_b_el
#	mov	edi, offset foo_ll_b
#	mov	ebx, FOO_STRUCT_SIZE * 2	# entry 2
#	call	ll_insert
##
# at this point, [foo_ll_a + ll_first] is 0, pointing to entry 0 in
# the array, and [foo_ll_b + ll_last] is FOO_STRUCT_SIZE, pointing to entry 1
# in the array. Further, [[foo_array] + ll_prev] is -1 as it is the first
# entry in list 'a', and [[foo_array] + ll_next] is FOO_STRUCT_SIZE, pointing
# to entry 1. Similarly, [[foo-array] + FOO_STRUCT_SIZE + ll_prev] is 0,
# and [[foo_array] + FOO_STRUCT_SIZE + ll_next] is -1 as it is the last entry.
#
# For list 'b', containing only one element,
# [foo_ll_b + ll_first] == [foo_ll_b + ll_last ] == FOO_STRUCT_SIZE * 2.
# Also, [[foo_array] + foo_ll_b_prev] == [[foo_array] + foo_ll_b_next] == -1
# as it is both the first and last element in the list.
#
# In this way, a single struct can be part of multiple linked lists.
#
# In the above example, each element of the array is the same size, but ebx
# could as easily have pointed to different sized elements, as long as they
# share the next/prev membership fields. It is not even required to have
# the ll_value field in the struct if the ll_insert_sorted is not used,
# by simply subtracting 4 from esi before the call.
.intel_syntax noprefix

.global ll_insert_sorted$

.struct 0	# Offsets into the linked list: main entry points.
ll_first: .long 0
ll_last: .long 0

# These fields are required to be present in a struct participating in a linked
# list. A linked list does not need to consist of the same structures, nor is
# this structure required to appear at a specific offset in it's embedding
# structure, as long as the prev/next fields point to this particular structure.
# The third field is required for sorted linked lists.
.struct 0	# ll_info
ll_prev: .long 0
ll_next: .long 0
ll_value: .long 0	# optional; used by ll_insert_sorted
.text32

##################################################### LINKED LIST ############
#
# in: esi = array base + offset to ll_prev within struct
# in: ebx = element index: pointer relative to esi.
# 	offset to linked list info: [value, prev, next]
#	[esi + ebx + ll_value]	= link_value (i.e. _base, _size)
#	[esi + ebx + ll_prev]	= link_prev (i.e. _fa_prev, _fs_prev)
#	[esi + ebx + ll_next]	= link_next (i.e. _fa_next, _fs_next)
# in: edi = first/last list info pointer: [first, last]
# in: ecx = number of elements in list (infinite loop prevention)
#
# This routine inserts ebx into an ascending sorted list.
ll_insert_sorted$:
	push	edx
	push	ecx
	push	ebx
	push	eax

	mov	eax, [edi + ll_first]
	cmp	eax, -1
	jz	1f

	######################################################
	mov	edx, [esi + ebx + ll_value]

0:	cmp	edx, [esi + eax + ll_value]
	jb	2f	# insert before
	mov	eax, [esi + eax + ll_next]
	or	eax, eax
	js	3f
	loop	0b
3:	# append to end of list
	# last -> ebx
	mov	eax, ebx
	xchg	eax, [edi + ll_last]
	xchg	eax, ebx
	# eax = old last, ebx = new last
	# eax <-> ebx
	mov	[esi + ebx + ll_next], eax
	mov	[esi + eax + ll_prev], ebx

	jmp	5f


2:	# found base that is higher - prepend.
	# x <-> eax <-> y
	# x <-> ebx <-> eax <-> y
	#
	# eax.prev.next = ebx
	# x -> ebx
	# x <- eax <-> y
	# ebx.next = eax
	# x -> ebx -> eax <->y
	# x        <- eax
	# ebx.prev = eax.prev
	# x <-> ebx -> eax <-> y
	# eax.prev = ebx
	# x <-> ebx <-> eax <->y

#	or	eax, eax
#	js	3f
	mov	edx, [esi + eax + ll_prev] # edx = eax.prev
	cmp	edx, -1
	jnz	6f
	# integrity check: assert edi+ll_first==eax
	mov	[edi + ll_first], ebx
4:	jmp	4f
6:	mov	[esi + edx + ll_next], ebx # eax.prev.next = ebx
4:	mov	[esi + eax + ll_prev], ebx # eax.prev = ebx
	mov	[esi + ebx + ll_prev], edx # ebx.prev = eax.prev
3:	mov	[esi + ebx + ll_next], eax # ebx.next = eax
	jmp	5f
	######################################################

1:	# store it as the first handle
	mov	[esi + ebx + ll_next], dword ptr -1
	mov	[esi + ebx + ll_prev], dword ptr -1
	mov	[edi + ll_first], ebx
	mov	[edi + ll_last], ebx

5:
	pop	eax
	pop	ebx
	pop	ecx
	pop	edx
	ret

LL_DEBUG = 0

# in: esi = [mem_handles]
# in: edi = offset of handle_??_first
# in: ebx: handle to place in the list, still part of it
ll_update_left$:
	push	eax
	push	ecx
	push	edx

	# set a limit: struct size is 12 bytes, assume at least 4 more bytes
	# so, 4Gb >> 4
	mov	ecx, 1 << 28	# circular list protection

	mov	edx, [esi + ebx + ll_value]
	mov	eax, [esi + ebx + ll_prev]
	cmp	eax, -1		# already first, dont move
	jz	1f
	cmp	edx, [esi + eax + ll_value]	# check the first
	jae	1f				# no change
	mov	eax, [esi + eax + ll_prev]

0:	cmp	edx, [esi + eax + ll_value]
	ja	2f
	mov	eax, [esi + eax + ll_prev]
	cmp	eax, -1
	jz	3f
	loop	0b
	# first
3:	call	ll_unlink$
	call	ll_prepend$
	jmp	1f

2:	# insert
	call	ll_unlink$
	call	ll_insert_sorted$

	# NOTE: should be ll_insert but this bugs at current.
	# In a sense then, this entire method can be replaced with
	# the unlink/update calls.


#	call	ll_insert$ 
	.if LL_DEBUG
		#push esi
		# debugs the offset into the array which can contain more than one
		# linked list.
		# Disabled, because this code is not exclusive to [mem_handles].
		#sub	esi, [mem_handles]; DEBUG_DWORD esi, "upd L field"
		#mov	esi, [mem_handles]

		dbg_ll_upd_L:
		mov	[esi + ebx + handle_caller], dword ptr offset .
		mov	ecx, ebx
		HOTOI ecx
		DEBUG_DWORD ecx,"update_left"
		call newline
		push	ebx
		add	ebx, esi
		call	mem_print_handle_2$
		pop	ebx
		#pop	esi
	.endif

1:	pop	edx
	pop	ecx
	pop	eax
	ret


# in: esi = array base
# in: edi = ll struct ptr
# in: ebx: handle to place in the list, still part of it
ll_update_right$:
	push	eax
	push	ecx
	push	edx

	# set a limit: struct size is 12 bytes, assume at least 4 more bytes
	# so, 4Gb >> 4
	mov	ecx, 1 << 28	# circular list protection

	mov	edx, [esi + ebx + ll_value]
	mov	eax, [esi + ebx + ll_next]
	cmp	eax, -1		# already last, dont move
	jz	1f
	cmp	edx, [esi + eax + ll_value]	# check the first
	jbe	1f				# no change
	mov	eax, [esi + eax + ll_next]

0:	cmp	edx, [esi + eax + ll_value]
	ja	2f
	mov	eax, [esi + eax + ll_next]
	cmp	eax, -1
	jz	3f
	loop	0b
	# last
3:	call	ll_unlink$
	call	ll_append$
	jmp	1f

2:	# insert
	call	ll_unlink$
	#call	ll_insert$
	call	ll_insert_sorted$

	.if LL_DEBUG
		dbg_ll_upd_R:
		mov	ecx, esi # [mem_handles]
		mov	[ecx + ebx + handle_caller], dword ptr offset .
		mov	ecx, ebx
		HOTOI ecx
		DEBUG_DWORD ecx,"update_right"
	.endif

1:	pop	edx
	pop	ecx
	pop	eax
	ret


# in: esi, edi
# in: ebx
ll_prepend$:
	push	eax
	mov	eax, ebx
	xchg	[edi + ll_first], eax
	or	eax, eax
	js	1f
	mov	[esi + ebx + ll_next], eax
	mov	[esi + eax + ll_prev], ebx
1:	pop	eax
	ret

# in: ebx = record offset, handle must have been unlinked!
# in: esi = array offset + ll_value
# in: edi = ll struct ptr
ll_append$:
	push	eax
	mov	eax, [edi + ll_last]
	or	eax, eax
	jns	1f
	mov	[edi + ll_first], ebx
	jmp	3f
1:	mov	[esi + eax + ll_next], ebx
	mov	[esi + ebx + ll_prev], eax
3:	mov	[edi + ll_last], ebx
	pop	eax
	ret



# inserts ebx after eax.
#
# in: esi = array pointer + ll_value
# in: ebx is record offset within array to append to
# in: eax, record offset.
# in: edi = ll struct pointer
ll_insert$:
ll_insert_after$:
	push	edx
	mov	edx, [esi + eax + ll_next]
	or	edx, edx
	jns	0f
	mov	[edi + ll_last], ebx
	jmp	1f
0:	mov	[esi + edx + ll_prev], ebx
1:	mov	[esi + ebx + ll_prev], eax
	mov	[esi + ebx + ll_next], edx
	mov	[esi + eax + ll_next], ebx
	pop	edx
	ret

# inserts ebx before eax
# in: edi = ll struct ptr
ll_insert_before$:
	push	edx
	mov	edx, [esi + eax + ll_prev]
	or	edx, edx
	jns	0f
	mov	[edi + ll_first], ebx
	jmp	1f
0:	mov	[esi + edx + ll_next], ebx
1:	mov	[esi + ebx + ll_prev], edx
	mov	[esi + ebx + ll_next], eax
	mov	[esi + eax + ll_prev], ebx
	pop	edx
	ret

# in: ebx = record ofset
# in: esi = array offset + ll_value
# in: edi = ll struct ptr
ll_unlink$:
	push	eax
	push	edx
	mov	eax, -1
	mov	edx, eax
	# eax = ebx.prev
	# edx = ebx.next
	xchg	eax, [esi + ebx + ll_prev]
	xchg	edx, [esi + ebx + ll_next]

	cmp	eax, -1			# is ebx.prev -1?
	jnz	0f
	cmp	edx, -1
	jz	2f			# prev and next both -1
	# ebx was the first
3:	mov	[edi + ll_first], edx	# yes - mark ebx.next as first
	jmp	1f
0:	mov	[esi + eax + ll_next], edx
1:
	cmp	edx, -1
	jnz	0f
	mov	[edi + ll_last], eax
	jmp	1f
0:	mov	[esi + edx + ll_prev], eax
1:
	pop	edx
	pop	eax
	ret

2:	# special case: both prev and next are -1.
	# either the entry constituted the entire list, in which case
	# ll_first == ll_last == ebx,
	# or it was not part of the list.
	cmp	ebx, [edi + ll_first]
	jz	3b
	cmp	ebx, [edi + ll_last]
	jnz	1b
	printlnc 4, "linked list was corrupt"
	jmp	1b

