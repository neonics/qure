# TODO: free does not always merge properly
# TODO: handle_fa (base) keeps the list ordered by address. The idea
# was to have the second list, size, be used for malloc. A list is needed
# for free, as now the address list contains both the allocated and the free.
# Perhaps the size list can serve double duty here: when free, it is
# ordered by size to make malloc fast; when allocated, it lists all allocated
# memory blocks.
# Similarly the fa/base already serves double duty: when the handle references
# memory, the list keeps the base addresses ordered so that they can be freed
# and merged easily - both free and allocated/reserved memory are in this
# list. When it doesnt reference memory, it indicates the list
# of free handles.
# so the size list will also serve double duty.
# handle_fa_first/last: base, non-zero-length memory blocks (allocated&free)
# handle_fh_first/last: base, null memory blocks - available handles.
# handle_fs_first/last: size, available/free pre-allocated memory blocks (malloc)
# handle_??_first/last: size, unavailable/allocated memory blocks (for mfree)

.intel_syntax noprefix

MEM_DEBUG = 0
MEM_DEBUG2 = 0
MEM_PRINT_HANDLES = 2	# 1 or 2: different formats.


.include "ll.s"
.include "mem_handle.s"

.data
mem_heap_start:	.long 0, 0
mem_heap_size:	.long 0, 0

mem_heap_alloc_start: .long 0

mem_sel_base: .long 0
mem_sel_limit: .long 0



.text32
.code32

# The 'handle' class is written with optimization of speed and size.
#
# There are several linked list methods. They use a similar calling
# convention:
#  ebx: the item's offset from the start of the list.
#  esi: the start of the list, it's base pointer.
#  edi: the list's meta-data: it's start and end items:long ll_first, ll_last;
# Semantically and practically, ebx is the item, esi is the array of items,
# and edi points to the memory locations holding the first and last items
# for the list.
#
# From one perspective this allows an array of objects to be ordered
# according to a self-embedded linked list. The linked list methods do
# not alter the base pointers, and use these indirectly to reference
# it's neighbours. Indirect, because a second reference (esi) is always
# added to the pointers so that as long as their internal distance does
# not change in terms of relative memory addresses, they can be relocated,
# and only the base pointer needs to be updated.
#
# Ofcourse the best way to test this is to use it on memory management
# code. The linked lists themselves, besides some 'global constant' variables,
# as this code is operating-system level, relating directly to the hardware,
# are managed by themselves.
# Basically this code is birthed from marrying a linked list with itself.
# The attribute of the linked list being dynamic, i.e., not limited in size,
# allows it to be both conservative aswell as expansive,
# as it's data is secure under memory relocation.
#
# From another perspective, the linked list is the backbone of any object
# oriented system. Part of the concept of object orientation is the
# concept of constructing and destructing, or, temporary occupation
# of memory space. This memory space needs to be reclaimable so it is
# available for other processes. The kernel itself does not require
# to release the memory, as when it's execution ends, it's management
# data will be ignored since it is the only process using it.
#
# One requirement of object orientation is to be able to group attributes
# together in an object. As such, the backbone does not know the size
# of the object. In fact, it does not have to. All pointers to objects
# are handed to it, wherever they may be located in memory.
#
# An implementation of a linked list that would need to know the size
# of the objects would have to employ an indexed array.
#
# Another purpose for the size of the object would be to be able to mark
# it's memory free upon destruction, and would be needed for allocation.
# The linked list itself is not concerned with allocation.
#
# The allocation and memory management of the objects is left open to the
# software using it.
#
# The malloc/mfree methods can be considered part of the construction
# and destruction routines.
#
# The allocation of memory results in it being recorded by malloc into
# a linked list. Since this memory is 'absolute', meaning, it does
# not change relative to the allocation routines, the linked list
# can contain absolute memory addresses - this is the 'base' field.
# The purpose of this field is to keep reference of all memory blocks,
# which requires the need for a 'size' field. This field can be eliminated
# by remembering an ordered linked list (handle_fa), however, it is kept
# as it, together with the base and flags allow to fall back to linear
# processing in case the linked list management contains a bug.
#
# The start of the evolution of this code was the internal_malloc$ code,
# which simply uses the base pointer that BIOS returned for the largest
# block of memory available. Giving it any block of memory, it will
# manage it's allocations by using four bytes per malloc call, by
# storing the size/offset relative to the start of the global memory block.
# More information was needed to be kept in order to be able to reuse
# other blocks of memory, besides the last one.
# The first malloc code is something like this:
#    push [alloc_start]
#    add [alloc_start], eax
#    pop eax
# transforming eax (the size) to the base address (eax again).
# Using two registers: (left-to-right notation, despite %)
#    mov %o0, [alloc_start]
#    add [alloc_start], %i0
#
# This malloc implementation does not interleave the accounting objects
# with the memory blocks they are accounting. This serves to reduce the
# chance of 'buffer overflows', aswell as needing to load many pages of
# virtual memory. The bookkeeping data is very small, 32 bytes.
# With an array, the minimum required is 5 (or 4 with a 2Gb limit).
#
# The first implementation was using an array with base and size.
# The size was not needed, but, the first optimization was to keep track
# of a list based on the address field (handle_base). Since this linked
# list would be ordered differently than the array ordering, the size
# field was needed.
#
#
# The basic methods are:
# ll_prepend	ebx, esi, edi
#		This takes item ebx and places it in the front of the list esi,
#		updating the reference to the first list item, [edi].
#		If [edi] != -1, it will, before [edi] = ebx, do this:
#			[esi+ebx].next = [edi];
#			[esi+[edi]].prev = ebx;
#
# ll_append	ebx, esi, edi
#		Similarly this method works on the ll_last [edi+4].
#
# ll_insert	eax, ebx, esi, edi
#		Inserts item ebx after item eax in list esi, possibly
#		updating [edi+4].
#		This is the ll_append using object eax instead of the first
#		item, [edi]. It will update ll_last if eax has no ll_next,
#		and is thus [edi+4].
#
# The array for the base address serves mfree, which is reflected in the
# updated malloc, re-using previously freed memory.
#
# The linked list for the sizes serves to have malloc re-use all memory,
# and not have it scatter into too small segments by always splitting from
# the biggest blocks. When relatively small sizes are allocated and freed
# often, this approach - starting at the low end of the list, serves best.
#
# A choice can be made to start from either end of the list, based on
# the smallest difference of the requested size and the size of the items
# bookending the list.
#
# When all malloc-maintained allocated memory is freed, all of it will
# be joined into at at most two blocks: the one remaining memory block
# containing the bookkeeping data, and the memory between it and the start
# of the managed memory, available for allocation.
# If a memory block that is freed is the one with the highest memory address,
# it will be remerged with the global heap (internal_malloc), as both
# that block and the global memory will be available. Not merging it imposes
# an artifical barrier, where, when all future memory allocations are bigger
# than that last block of free memory, it will remain unused.
#
# This code is written with the idea of it being callable throughout the
# entire operating system, by the kernel and by 'user level' processes
# themselves. When all processes shut down, all memory will be available for
# allocation, all joined into at most 2 blocks as described above.
#
# The code is optimized to have no artificial memory barriers.
# This means that upon freeing memory adjoining free memory blocks,
# they merge to become one available memory block. This reduces the need
# to allocate more data from the global memory pool.
#
# This also results in handles becoming available for reuse, which is
# efficiently managed by reusing the address list (handle_fa, handle_base),
# as the handles that have no address are not kept in the address list.
#
# When all linked list data would be corrupted, the flags field
# aswell as the base field would provide enough information to reconstruct
# it.
#
# The address list code uses the size list as it wouldn't want to search
# the entire (address) list to find the next higher base address to calculate
# the size. If the handles, in 'physical memory', are kept in order of
# allocation from the main heap, it would be possible to simply use another
# direction of reference, to add the size of the structure to it's own
# offset in the list, to calculate the size.
# However, since blocks are joined, handles become free, and gaps can
# be created.
#
# Eliminating the size field then can be done by copying the base address
# of the next item into the empty handle:
#   base  flags
#   0	   allocated (size=100)
#   100    allocated (size=100)
#   200    allocated (size=800)
#   1000   eof       (size ignored)
#
# Then, free base 100:
#
#   base  flags
#   0	   allocated (size=100)
#   200    reusable (size=0)
#   200    allocated (size=800)
#   1000   eof       (size ignored)
#
# To find a suitable sized available block of memory, randomness would
# be the fastest on average perhaps.
# The purpose of the size field is to have a linked list with multiple
# entry points. Whenever the list grows above a certain size,
# another entrypoint is added. ANother way to implement this is to have
# a series of memory blocks all point to the same higher (say twice the size)
# of memory block (for example having 1000 blocks of 32 bytes and one of
# 1000 and then 1000 of 1M), all of the 32 would point to the 1000.
# This would require 1000 updates, but would allow to skip quite a few to
# speed things up. So, in this way, blocks that are within a certain
# range are grouped together.
#
# Now, rather than doing it this way, a node/handle containing a first/last
# field, is kept in a linked list, handle_as (available by size).
#
# The base/size fields can serve this type of handle, having a certain
# flag, base=first, size=last, or, have 2 nodes, one marking first,
# one last, using the size field - address/base ignored.
#
# Now the linked list will have several layers.
# The bottom layer will be: ll_first/ll_last in handle_as.
#   this list contains all handles referencing memory ordered by size.
# The top layer will be: ll_first/ll_last in handle_as.
#
# Initially handle_as will be identical to handle_fs.
#
# When a certain condition occurs (the difference between the smallest/largest
# memory block is a factor of 2, or when they are very close together
# and the number of elements referenced from handle_fa grows too big),
# another layer of depth will be added.
#
# The first node inserted between first/last in handle_fa will be somewhere
# in the list, adding a third point to handle_as.
# This first 'real' node will be an indirect pointer. The start/end
# cases can be handled specially [faster].
#
# So, the handle_as is a linked list of nodes that divide the entire linked
# list into chunks organized by the underlying principle.
#
# The next/prev fields on the level of handle_as (using size for ordering),
# refer to this layer of nodes only. The base field will serve as a pointer
# to the underlying (base) list, to the element on the 'dividing line'.
#
# A search then proceeds by iterating through the top list, first choosing
# from which end, until a size that can accommodate the request is found.
# Then a flag is checked, to see whether this is a node, or a pointer.
# If it is the node, allocate as usual - remove it from the list,
# and update the pointer node. [might need another dimension (field)
# for this, seeing the layers as horizontal (strings of pearls),
# each higher string having significantly less pearls; the new dimension
# then, is vertical]. Either runtime remembrance of vertical descent,
# using the stack, to update the nodes, or, add a field that points up
# (as only the down-pointing field base is used).
# This administration is required because a node may point down to
# the last item, yet it itself not being the last item (but the one
# before it). When removing that bottom node, the parent node must
# be removed aswell, up to the top.
#
.text32

# iterate through bios memory map, finding the largest block; for a machine
# with less than 2Gb ram this'll be the block from 1Mb to almost the end
# of physical memory generally. The first Mb is skipped, reserved for real-mode
# kernel and legacy 16 bits apps and such.
mem_init:
	PRINT " Start           | Size             | Type"

	# ecx:ebx = size, edi=index (for max cmp)
	xor	ebx, ebx
	xor	ecx, ecx
	xor	edi, edi

	mov	esi, offset memory_map
0:	call	newline
	cmp	dword ptr [esi + 20 ], 0 # memory_map_attributes], 0
	jz	0f

	mov	edx, [esi + 4 ] #memory_map_base + 4 ]
mov eax, edx
	call	printhex8
	mov	edx, [esi + 0 ] #memory_map_base + 0 ]
	call	printhex8
	PRINT	" | "
# compare start addresses:
cmp	eax, [mem_phys_total + 4]
jb	1f
cmp	edx, [mem_phys_total + 0]
jb	1f
# entry has highest memory start address. Add size:
add	edx, [esi + 8]
adc	eax, [esi + 12]
mov	[mem_phys_total + 4], eax
mov	[mem_phys_total + 0], edx
1:
	mov	edx, [esi + 12 ] #memory_map_length + 4 ]
	mov	eax, edx
	call	printhex8
	mov	edx, [esi + 8 ] # memory_map_length + 0 ]
	call	printhex8
	PRINT	" | "

	push	edx
	mov	edx, [esi + 16 ] # memory_map_region_type ]
	call	printhex8
	cmp	edx, 1
	pop	edx
	jnz	1f

	cmp	ecx, edx
	ja	1f
	cmp	eax, ebx
	ja	1f
	mov	edi, esi
	mov	ecx, edx
	mov	ebx, eax
1:

	add	esi, 24 # memory_map_struct_size
	jmp	0b
0:
	print "Total physical memory: "
	mov	edx, [mem_phys_total + 4]
	mov	eax, [mem_phys_total + 0]
	call	print_size
	call	newline

	print "Max: address: "
	mov	edx, [edi+4]
	call	printhex8
	mov	edx, [edi+0]
	call	printhex8
	print " size: "
	mov	edx, [edi+12]
	call	printhex8
	mov	edx, [edi+8]
	call	printhex8
	call	println

	mov	esi, edi
	mov	edi, offset mem_heap_start
	movsd
	movsd
	movsd
	movsd


	# > 4Gb check

	cmp	dword ptr [mem_heap_start + 4], 0
	jz	0f
	printlnc 4, "ERROR - Memory offset beyond 4Gb limit"
	jmp	halt
0:	cmp	dword ptr [mem_heap_size + 4], 0
	jz	0f
	printlnc 4, "WARNING - Truncating available memory to 4Gb"
	mov	edi, offset mem_heap_size
	mov	eax, -1
	stosd
	inc	eax
	stosd

0:
	# Adjust base relative to selectors

	# Get the data selector information

	mov	eax, ds

	mov	edx, eax
	print "Data Selector "
	call	printhex4

	print " base "
	xor	edx, edx
	mov	dl, [GDT + eax + 7]
	shl	edx, 16
	mov	dx, [GDT + eax + 2]
	mov	[mem_sel_base], edx
	call	printhex8

	print " segment limit: "
	lsl	edx, eax
	mov	[mem_sel_limit], edx
	call	printhex8
	printchar ' '
	call	printdec32
	printchar ' '
	shr	edx, 20
	call	printdec32
	println "Mb"


	# Adjust the heap start

	print "Adjusting heap: base "
	mov	edx, [mem_heap_start]
	call	printhex8
	mov	edx, [mem_heap_size]
	print " size "
	call	printhex8


	print " to: base "

	mov	edx, [mem_sel_base]
	sub	[mem_heap_start], edx # TODO check if base is byte gran
	mov	edx, [mem_heap_start]
	call	printhex8

	sub	[mem_heap_size], edx
	mov	[mem_heap_alloc_start], edx

	mov	edx, [mem_heap_size]
	print " size "
	call	printhex8
	print " ("
	shr	edx, 20
	call	printdec32
	println "Mb)"

	ret

###########################################

mem_test$:
	call	mem_print_handles

	mov	eax, 0x1000
	DEBUG_DWORD eax,"malloc"
	call	malloc
	call	mem_print_handles

	DEBUG_DWORD eax,"mfree"
	call	mfree
	call	mem_print_handles

	mov	eax, 0x200
	DEBUG_DWORD eax,"malloc"
	call	malloc
	call	mem_print_handles

	DEBUG_DWORD eax,"mfree"
	call	mfree
	call	mem_print_handles

	printlnc 11, "Press enter"
0:	xor	ax,ax
	call	keyboard
	cmp	ax, K_ENTER
	jnz	0b
	ret

malloc_test$:
	# malloc some space to store pointers; remember as edi
	printc 15, "MALLOC "
	mov	eax, 0x200
	call	malloc
	mov	edx, eax
	mov	edi, eax

	mov	eax, 0x10	# this one won't be freed.
	call	malloc

	.macro ASSERT_NUMHANDLES num
		push	edx
		mov	edx, [mem_numhandles]
		cmp	edx, \num
		je	9f
		pushcolor 0xf4
		print "Expected numhandles \num, got "
		call	printdec32
		popcolor
		call	newline
		call	more
	9:	pop	edx
	.endm

	.macro ASSERT_FLAG op, idx, flag
		push	ebx
		mov	ebx, \idx
		HITO	ebx
		add	ebx, [mem_handles]
		test	[ebx + handle_flags], byte ptr \flag
		j\op	9f
		printlnc 0xf4, "Flag \flag mismatch"
	9:	pop	ebx
	.endm

	ASSERT_NUMHANDLES 3
	ASSERT_FLAG nz, 0, (1<<7)
	ASSERT_FLAG nz, 0, 1
	ASSERT_FLAG nz, 1, 1
	ASSERT_FLAG nz, 2, 1


		call	newline
		call	mem_print_handles
		call	more


	println "* Test allocate"
	# Allocate memory blocks of different size
	mov	eax, 0x180
	.rept 4
	push	eax
	call	malloc
	stosd
	pushcolor 15
	mov	edx, eax
	call	printhex8
	popcolor
	printchar ' '
	pop	eax
	shl	eax, 1
	.endr
	call	newline

	ASSERT_NUMHANDLES 7

	println "* Test free"
	call	mem_print_handles
	call	more
	# free the memory blocks
	sub	edi, 4 * 4
	mov	esi, edi
	.rept 4
	pushcolor 15
	print	"FREE "
	lodsd
	mov	edx, eax
	call	printhex8
	popcolor
	call	mfree
	call	mem_print_handles
	call	more
	.endr
	call	newline

	println "* Test split"


	.macro MEM_TEST_MALLOC size
	mov	eax, \size
	mov	edx, eax
	color	15
	print 	"malloc "
	call	printhex8
	call	malloc
	mov	edx, eax
	printchar ' '
	call	printhex8
	call	newline
	COLOR	7
	call	mem_print_handles
	call	more
	COLOR	15
	.endm

	.macro MEM_TEST_FREE
	print	"free "
	mov	edx, eax
	call	printhex8
	call	mfree
	COLOR	7
	call	mem_print_handles
	call	more
	.endm

	PUSHCOLOR 14
	# the first blocks are merged to 0x1680.
	# free the first handle, edi, size 0x180, so that when 0x1680
	# is split it's size will become less and should move in the size list.
	mov	eax, edi
	MEM_TEST_FREE


	MEM_TEST_MALLOC 0x300	# leaves 1380 reserved, 300 allocated
	mov	ecx, eax
	MEM_TEST_MALLOC 0x1380
	print	"* test join, order 1"
	xchg	ecx, eax
	MEM_TEST_FREE
	xchg	ecx, eax
	MEM_TEST_FREE

	print	"* test join, order 2"
	MEM_TEST_MALLOC (0x1680 - 0x200 + 1)
	MEM_TEST_FREE
	POPCOLOR

	printlnc 0xf0, "cleanup"
	call	mem_print_handles
	call	more

	mov	esi, [mem_handles]
	mov	ebx, [handle_fa_last]
	mov	ecx, [mem_numhandles]
0:	test	byte ptr [esi + ebx + handle_flags], 1 << 7
	jnz	1f
	test	byte ptr [esi + ebx + handle_flags], MEM_FLAG_ALLOCATED
	jz	1f
	mov	eax, [esi + ebx + handle_base]
	mov	edx, ebx
	HOTOI	edx
	call	printhex8
	call	mfree
1:	mov	ebx, [esi + ebx + handle_fa_prev]
	or	ebx, ebx
	js	0f
	loop	0b
0:

	call	more
	call	mem_print_handles
	printlnc 15, "* Test completed."

	ret

more:	MORE
	ret
#######################################################################
# in: eax = size to allocate
# in: edx = physical address alignment
malloc_internal_aligned$:	# can only be called from malloc_aligned!

	# calculate worst case scenario for required contiguous memory
	push	edx
	push	eax
	add	eax, edx	# worst case
	mov	edx, [mem_heap_alloc_start]
	add	edx, [mem_heap_size]
	sub	edx, [mem_heap_start]
	cmp	eax, edx
	pop	eax
	jae	9f	# note: only edx on stack!

	mov	edx, [esp]	# restore edx (pop/push)


	# calculate the required slack for the alignment
	push_	ebx ecx edi
	GDT_GET_BASE ecx, ds
	mov	edi, [mem_heap_alloc_start]
	sub	edi, ecx	# physical address (with id paging)
	dec	edx
	add	edi, edx
	not	edx
	and	edi, edx
	add	edi, ecx	# edi now ds el phys aligned
	push_	esi eax
	mov	eax, edi
	sub	eax, [mem_heap_alloc_start]	# eax = slack size
	jz	1f

	# register the slack as free space

	mov	esi, [mem_handles]
	call	get_handle$
	jc	4f

	mov	[esi + ebx + handle_size], eax
	and	byte ptr [esi + ebx + handle_flags], ~MEM_FLAG_ALLOCATED
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SLACK

	push	dword ptr [mem_heap_alloc_start]
	add	[mem_heap_alloc_start], eax
	pop	dword ptr [esi + ebx + handle_base]
	# insert the handle in the FS list.
	push	edi
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	call	ll_append$
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
	mov	edi, offset handle_ll_fs
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$	# insert
	pop	edi

	# now get the memory:
	clc
1:	# DO NOT CHANGE CF
	pop_	eax esi

	pop_	edi ecx ebx
	pop	edx
	jnc	malloc_internal$ # heap should be nicely aligned now.
	ret

4:	printlnc 4, "malloc_internal_aligned: no more handles"
	stc
	jmp	1b

# in: eax = size to allocate
# out: base address of allocated memory
malloc_internal$:
	.if MEM_DEBUG > 1
		push	edx
		pushcolor 10
		mov	edx, eax
		call	printhex8	# alloc size
		printchar ' '
		mov	edx, [mem_heap_alloc_start]	# base
		call	printhex8
		printchar ' '
	.endif

	push	edx
	mov	edx, [mem_heap_alloc_start]
	add	edx, [mem_heap_size]
	sub	edx, [mem_heap_start]
	cmp	eax, edx
	jae	9f

	push	dword ptr [mem_heap_alloc_start]
	add	[mem_heap_alloc_start], eax
	pop	eax

	.if MEM_DEBUG > 1
		mov	edx, [mem_heap_alloc_start]	# new free
		call	printhex8
		call	newline
		popcolor 10
		pop	edx
	.endif

0:	pop	edx
	ret

9:	printc 4, "malloc_internal: out of memory: free="
	call	printhex8
	printc 4, " requested: "
	mov	edx, eax
	call	printhex8
	call	newline
	stc
	jmp	0b

#######################################################################
# sums all allocated handles.
# out: edx:eax
mem_get_used:
	push	ebx
	mov	ebx, [mem_handles]
	mov	edx, [handle_fa_first]
	xor	eax, eax
0:	test	[ebx + edx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jz	1f
	add	eax, [ebx + edx + handle_size]
1:	mov	edx, [ebx + edx + handle_fa_next]
	cmp	edx, -1
	jnz	0b
	xor	edx, edx	# for print_size etc...
	pop	ebx
	ret

mem_get_reserved:
	xor	edx, edx
	mov	eax, [mem_heap_alloc_start]
	sub	eax, [mem_heap_start]
	ret
mem_get_free:
	xor	edx, edx
	mov	eax, [mem_heap_size]
	add	eax, [mem_heap_start]
	sub	eax, [mem_heap_alloc_start]
	ret

# in: eax = size
# out: eax
# out: CF
mallocz:
	push	ebp
	lea	ebp, [esp + 4]
	call	mallocz_
	pop	ebp
	ret

# in: eax = size
# in: [ebp] = caller return
# out: eax
# out: CF
mallocz_:
	.if MEM_DEBUG2
		DEBUG "mallocz ";
		push edx; mov edx,[esp+4]; call debug_printsymbol; pop edx
	.endif
	push	ecx
	mov	ecx, eax
#DEBUG_DWORD ecx,"mallocz"
	call	malloc_
_mallocz_malloc_ret$:	# debug symbol
	.if MEM_DEBUG2
		DEBUG_DWORD eax; pushf; call newline; popf
	.endif
	jc	9f
	push	edi
	mov	edi, eax
	push	eax
	xor	eax, eax
	push	ecx
#DEBUG_DWORD edi
#DEBUG_DWORD ecx
	and	ecx, 3
	rep	stosb
	pop	ecx
push ecx
	shr	ecx, 2
	rep	stosd
pop ecx
	pop	eax
.if 0
pushf
push edi
push eax
push ecx
mov edi, eax
xor al, al
DEBUG_DWORD edi,"scan"
DEBUG_DWORD ecx
repz scasb
jz 2f
or ecx, ecx
jz 2f
printc 4, "NOT 0"
DEBUG_DWORD ecx,"size-index"
DEBUG_DWORD edi
mov eax, [esp + 4]
DEBUG_DWORD eax,"alloccd"
mov eax, [esp]
DEBUG_DWORD eax,"ecx"
call newline
2:
pop ecx
pop eax
pop edi
popf
.endif
	pop	edi
	clc
1:	pop	ecx
	ret
9:	printc 4, "mallocz: can't allocate "
	push	edx
	push	eax
	mov	eax, ecx
	xor	edx, edx
	call	print_size
	pop	eax
	printc 4, " called from "
	mov	edx, [esp + 2*4]	# edx+ecx
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	pop	edx
	jmp	1b


#########################################################
# in: eax = size
# in: edx = physical alignment (power of 2)
malloc_aligned:
	push	ebp
	lea	ebp, [esp + 4]
	call	malloc_aligned_
	pop	ebp
	ret

# in: eax = size
# in: ebp = caller return stack ptr
# in: edx = physical alignment (power of 2)
malloc_aligned_:
	MUTEX_SPINLOCK MEM
	push_	ebx esi

	mov	esi, [mem_handles]
	call	find_handle_aligned$
	jnc	1f	# : mov eax, base; clc; ret
	call	get_handle$
	jc	4f	# error: no more handles

	mov	[esi + ebx + handle_size], eax
	# register caller
	push	edx
	mov	edx, [ebp]#[esp + 3*4]	# edx+esi+ebx+ret
	mov	[esi + ebx + handle_caller], edx
	pop	edx

.if 0
	push	ecx
	mov	edi, eax	# backup size

	add	eax, edx
	mov	[esi + ebx + handle_size], eax
	call	malloc_internal$	# out: eax
	jc	3f	# can't use malloc's 3f due to ecx on stack

	# success code from 3f:
	mov	[esi + ebx + handle_base], eax

	push	edi
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	push	ecx
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$
	pop	ecx
	sub	esi, offset handle_ll_el_addr
	pop	edi

	# it is done.

	# now split the handle: pretend it was just found as free
	# in find_handle_aligned, and execute tail part:
	xchg	eax, ecx	# eax = size; ecx = remember ptr
	call	align_handle$	# out: ebx
	mov	eax, ecx	# restore ptr
	clc

1:	pop_	ecx esi ebx
	MUTEX_UNLOCK_ MEM
	ret


3:	printlnc 4, "malloc_aligned: no more handles"
	stc
	jmp	1b

.else
# BUG
	call	malloc_internal_aligned$
	jnc	3f
	DEBUG "malloc_internal_aligned error"
	jmp	3f
.endif



# in: eax = size
# out: eax = base pointer
# out: CF = out of mem
malloc:
	push	ebp
	lea	ebp, [esp + 4]
	call	malloc_
	pop	ebp
	ret

# in: eax = size
# in: ebp = stack pointer to caller return address
# out: edx = base pointer
# out: CF = out of mem
malloc_:
#DEBUG_REGSTORE
	MUTEX_SPINLOCK MEM
	.if MEM_DEBUG2
		DEBUG_DWORD eax,"malloc("
	.endif
#call mem_debug
	push_	ebx esi
	mov	esi, [mem_handles]
	call	find_handle$
	jc	2f
	# jz	2f	# for find_handle_linear$
1:
		.if MEM_DEBUG
		pushcolor 13
		print " ReUse "
		push	edx
		mov	edx, ebx
		HOTOI	edx
		call printhex8
		printchar ' '
		mov	dl, [esi + ebx + handle_flags]
		call	printbin8
		pop	edx
		popcolor
		.endif
	mov	eax, [esi + ebx + handle_base]
	jmp	0f

2:	call	get_handle$
	jc	4f

	.if MEM_DEBUG
		pushcolor 13
		print " new "
		push	edx
		mov	edx, ebx
		HOTOI	edx
		call	printhex8
		printchar ' '
		pop	edx
		popcolor
	.endif

	mov	[esi + ebx + handle_size], eax
	call	malloc_internal$
3:	jc	3f
	.if MEM_DEBUG
		push	edx
		print " base: "
		mov	edx, eax
		call	printhex8
		pop	edx
	.endif

	mov	[esi + ebx + handle_base], eax

	push	edi
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	push	ecx
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$
	pop	ecx
	sub	esi, offset handle_ll_el_addr
	pop	edi

	# register caller
0:	push	edx
#	mov	edx, offset _mallocz_malloc_ret$
#	add	edx, [realsegflat]
#	cmp	edx, [esp + 20]
#	mov	edx, [esp + 24]
#	jz	5f
#	mov	edx, [esp + 20]	# edx+esi+ebx+ret
#5:
mov edx, [ebp]
	mov	[esi + ebx + handle_caller], edx
	pop	edx

	clc

1:	pop_	esi ebx

	.if MEM_DEBUG > 1
		pushf
		pushcolor 8
		call	mem_print_handles
		MORE
		popcolor
		popf
	.endif
	.if MEM_DEBUG2
		DEBUG_DWORD eax,")"
		call mem_validate_handles
	.endif
	MUTEX_UNLOCK_ MEM
#DEBUG_REGDIFF
	ret	# WEIRD BUG: 0x001008f0 on stack (called from mdup@net.s:685)

4:	printlnc 4, "malloc: no more handles"
	stc
	jmp	1b

3:
	push	edx
	push	eax
	# check if called from mallocz. if so, dont print as mallocz will.
	mov	edx, offset _mallocz_malloc_ret$
	add	edx, [realsegflat]
	cmp	edx, [esp + 4*4]
	jz	2f

	printc 4, "malloc: out of memory: can't allocate "
	xor	edx, edx
	call	print_size
	printc 4, ": called from: "
	mov	edx, [esp + 4*4]	# eax+edx+esi+ebx
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
2:	pop	eax
	pop	edx

	stc
	jmp	1b


.macro MREALLOC malloc
	or	eax, eax
	jnz	1f
	mov	eax, edx
	jmp	\malloc
1:
########
	push	ebp
	lea	ebp, [esp + 4]
	MUTEX_LOCK MEM locklabel=1f
	DEBUG "MREALLOC mutex fail"
	pushad
	mov	edx, [esp + 32]
	call debug_printsymbol; call newline
	call	debugger_print_mutex$
	popad
	jmp 1b
1:
	.if MEM_DEBUG2
		DEBUG "[", 0x6f
	.endif
 	push	ebx
	push	ecx
	push	esi
	push	edi

	mov	esi, [mem_handles]

	call	get_handle_by_base$
	jc	0f

	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f

0:	printc 4, "mrealloc: unknown pointer "
	push	edx
	mov	edx, eax
	call	printhex8
	printc 4, " called from: "
	mov	edx, [esp + 5*4]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	pop	edx

	jmp	0f
1:
########
	# Check if the call is for growth
	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, edx	# ecx = cursize - newsize
	jns	2f	# shrink
	jz	0f	# no change.

	neg	ecx
	.if MEM_DEBUG2
		DEBUG "+", 0x6f
	.endif
1:	# grow
	# check if the next memory block is free
	mov	edi, [esi + ebx + handle_fa_next]
	or	edi, edi
	js	1f	# has no next, allocate new.
	test	byte ptr [esi + edi + handle_flags], MEM_FLAG_ALLOCATED
	jnz	1f	# allocated; resort to copy.

	# check the size
	cmp	ecx, [esi + edi + handle_size]
	ja	1f	# not large enough.

	# in theory, the next in the address list SHOULD follow this one.
	# let's check to be sure:
	mov	ecx, [esi + ebx + handle_base]
	add	ecx, [esi + ebx + handle_size]
	cmp	ecx, [esi + edi + handle_base]
	jnz	1f	# no go. [perhaps issue warning]

	# we're lucky!

	# clear first:
	.ifc \malloc,mallocz
	push	edi
	mov	ecx, edx			# new size
	sub	ecx, [esi + ebx + handle_size]	# - current size = borrow
	.if MEM_DEBUG2
		DEBUG_DWORD ecx,"clr",0x9f
	.endif
	mov	edi, [esi + edi + handle_base]
	push	eax
	xor	eax, eax
	rep	stosb
	pop	eax
	pop	edi
	.endif


	mov	ecx, edx
	sub	ecx, [esi + ebx + handle_size] # ecx = bytes to borrow
	sub	ecx, [esi + edi + handle_size]
	neg	ecx	# ecx contains the leftover size of edi.
	# js...
	cmp	ecx, MEM_SPLIT_THRESHOLD
	jb	5f	# take it all
	.if MEM_DEBUG2
		DEBUG "B",0x6f
	.endif
	# just borrow the bytes, leave the handle as is.

	mov	ecx, edx
	sub	ecx, [esi + ebx + handle_size]
	add	[esi + ebx + handle_size], ecx
	sub	[esi + edi + handle_size], ecx
	add	[esi + edi + handle_base], ecx

	jmp	0f

5:	# take all the memory - merge the handles.
	.if MEM_DEBUG2
		DEBUG "M",0x6f
	.endif

	# edi is unallocated handle, and thus it is part of the lists:
	# handle_fa - to maintain address order
	# handle_fs - free-by-size
	# Clear them both out.
	mov	ebx, edi
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size
	call	ll_unlink$
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr - offset handle_ll_el_size
	call	ll_unlink$
	mov	edi, offset handle_ll_fh
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$

	# eax is unchanged

	jmp	0f

####### allocate a new block and copy the data.
1:
	.if MEM_DEBUG2
		DEBUG "C",0x6f
	.endif
	mov	ecx, [esi + ebx + handle_size]
	push	esi
	mov	esi, eax

	mov	eax, edx
	MUTEX_UNLOCK_ MEM
	call	\malloc\()_
	MUTEX_SPINLOCK_ MEM
	# copy
	or	ecx, ecx	# shouldnt happen if malloc checks for it.
	jz	1f
	mov	edi, eax
	rep	movsb

1:	pop	esi
	or	[ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED

	# free the old handle
	.if MEM_DEBUG2
		DEBUG "<", 0x6f; call mem_validate_handles;
	.endif

	MUTEX_UNLOCK_ MEM
	push	eax
	mov	eax, [esi + ebx + handle_base]
	.if MEM_DEBUG2
		DEBUG ".", 0x6f
	.endif
	call	mfree	# TODO: optimize, as handle is known
	pop	eax

	jmp	1f

########
2:	# shrink: ignore.
	.if MEM_DEBUG2
		DEBUG "-", 0x6f
	.endif
########

0:	MUTEX_UNLOCK_ MEM
1:	pop	edi
	pop	esi
	pop	ecx
	pop	ebx
	.if MEM_DEBUG2
		call mem_validate_handles
		DEBUG "]", 0x6f
	.endif
	pop	ebp
.endm


# in: eax = mem, edx = new size
# out: eax = reallocated (memcpy) mem
mrealloc:
	.if MEM_DEBUG2
		DEBUG_DWORD eax,"mrealloc";DEBUG_DWORD edx
	.endif
	MREALLOC malloc
	.if MEM_DEBUG2
		DEBUG_DWORD eax
	.endif
	ret

# in: eax = old buffer
# in: edx = new size
# out: eax = new buffer
# out: CF
mreallocz:
	push	ebp
	lea	ebp, [esp + 4]
	call	mreallocz_
	pop	ebp
	ret

# in: eax = old buffer
# in: edx = new size
# in: [ebp] = caller
# out: eax = new buffer
# out: CF
mreallocz_:
.if 1
	push	edi
	push	esi
	push	ecx
	####################
	push	eax
	mov	eax, edx
	call	mallocz_
	jc	9f
	mov	esi, [esp]
	mov	edi, eax
#	DEBUG "mreallocz";DEBUG_DWORD esi;DEBUG_DWORD edi;DEBUG_DWORD edx
	movzx	ecx, dl
	and	cl, 3
	rep	movsb
	mov	ecx, edx
	shr	ecx, 2
	rep	movsd
	xchg	eax, [esp]
	call	mfree
	pop	eax
	clc
	####################
0:	pop	ecx
	pop	esi
	pop	edi
	ret
9:	pop	eax
	jmp	0b
.else
	.if MEM_DEBUG2
		DEBUG_DWORD eax,"mrealloc";DEBUG_DWORD edx
	.endif
	MREALLOC mallocz
	.if MEM_DEBUG2
		DEBUG_DWORD eax
	.endif
	ret
.endif

# in: eax = memory pointer
mfree:
	MUTEX_SPINLOCK_ MEM
	.if MEM_DEBUG2
		DEBUG "["
		DEBUG_DWORD eax,"mfree"
		call mem_validate_handles
		DEBUG ","
	.endif
	push	esi
	push	ecx
	push	ebx
	mov	ecx, [mem_numhandles]
	or	ecx, ecx
	jz	1f
	#jecxz	1f
	mov	esi, [mem_handles]
	mov	ebx, [handle_fa_last]

0:	#or	ebx, ebx
	#js	1f
	cmp	ebx, -1
	jz	1f
	cmp	eax, [esi + ebx + handle_base]
	jz	3f
	mov	ebx, [esi + ebx + handle_fa_prev]
	loop	0b
	jmp	1f

3:	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jz	1f
	and	[esi + ebx + handle_flags], byte ptr ~MEM_FLAG_ALLOCATED
	# alt:
	# btc	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED_SHIFT
	# jnc	1f

##################
	push	edi
	push	edx
	# this takes care of everything:
	call	handle_merge_fa$
	pop	edx
	pop	edi

	clc
##################

2:	pop	ebx
	pop	ecx
	pop	esi
	.if MEM_DEBUG2
		call mem_validate_handles
		DEBUG "]"
	.endif
	MUTEX_UNLOCK_ MEM
	ret

1:	pushcolor 4
	print	"free called for unknown pointer "
	push	edx
	mov	edx, eax
	call	printhex8
	print " called from "
	mov	edx, [esp + 4*4 + COLOR_STACK_SIZE]
	call	printhex8
	call	printspace
	call	debug_printsymbol
		.if 0
		print " ecx="
		mov	edx, ecx
		call	printhex8
		print " ebx="
		mov	edx, ebx
		call	printhex8
		.endif
	call	newline
	pop	edx
	popcolor
	stc
	jmp	2b


	.macro PRINT_LL_UNLINK listname
		printc 4, "Unlink \listname "
		push	edx
		mov	edx, ebx
		HOTOI	edx
		call	printdec32
		pop	edx
	.endm

###########################################################################

mem_debug:
	.if MEM_DEBUG
	push	ebx
	push	ecx
	push	edx
	print "[malloc "
	mov	edx, eax
	call	printhex8
	print " heap "
	mov	edx, [mem_heap_start]
	mov	ecx, edx
	call	printhex8
	printchar '-'
	mov	ebx, [mem_heap_size]
	add	edx, ebx
	call	printhex8
	print " size "
	mov	edx, ebx
	call	printhex8
	print " start "
	mov	edx, [mem_heap_alloc_start]
	call	printhex8
	print " allocated "
	sub	edx, ecx
	call	printhex8
	print " flags "
	sub	ebx, edx
	mov	edx, ebx
	call	printbin8
	println "]"
	pop	edx
	pop	ecx
	pop	ebx
	.endif
	ret


malloc_optimized:

# Idea: have a 2-bit segmented index.
	# eax = size to allocate
	bsr	ecx, eax
	mov	ebx, 1
	shl	ebx, cl
	dec	ebx
	test	eax, ebx
	jz	0f	# jump if aligned perfectly (power of 2)

	and	eax, ebx	# mask off the highest bit of the size
	bsr	ecx, eax
	# cl = highest order bit
	# ch = second order bit.
	# When allocating lets say 1025 bytes,
	# wanting the segment sizes to be power-two, this would result
	# in allocating 2048 bytes, wasting 1023 bytes.
	# The most waste with a 2 bit index will occur in case of
	# allocating 1.5 times a power-of-two plus one, for
	# instance: 1024 + 512 + 1, would waste 511 bytes, 25% instead of
	# almost 50%. Memory waste can be further reduced by adding more
	# bits - until it is exact.

	# another approach would be to find the next higher size of an
	# integer amount of a smaller section of bytes.
	# For instance, 1025 would fit in:
	# 1 * 2048
	# 2 * 1024	waste 1023
	# 3 * 512	waste 511
	# 5 * 256	waste 255
	# 9 * 128	waste 127
	# 17 * 64	waste 63
	# 33 * 32	waste 31

0:


#	call	get_pid
#	mov	eax, [esi+pi_heap]

	ret

# in: esi = data
# in: ecx = datalen
# out: esi = new buffer containing data
mdup:	push	ebp
	lea	ebp, [esp + 4]
	push	eax

	mov	eax, ecx
	call	malloc_
	jc	9f

	push	eax
	push	edi
	push	ecx
	mov	edi, eax
	mov	al, cl
	shr	ecx, 2
	rep	movsd
	mov	cl, al
	and	cl, 3
	rep	movsb
	pop	ecx
	pop	edi
	pop	esi

9:	pop	eax
	pop	ebp
	ret

##############################################################################
# Commandline utility
CMD_MEM_OPT_HANDLES	= 1 << 0
CMD_MEM_OPT_KERNELSIZES	= 1 << 1	# kernel pm/rm code,data,symbols,stack
CMD_MEM_OPT_ADDRESSES	= 1 << 2	# start/end addresses of kernelsizes
CMD_MEM_OPT_MEMMAP	= 1 << 3	# verbose memory map of all sections
CMD_MEM_OPT_CODESIZES	= 1 << 8	# verbose subsystem code sizes
CMD_MEM_OPT_HANDLES_A	= 1 << 9
CMD_MEM_OPT_HANDLES_S	= 1 << 10
CMD_MEM_OPT_GRAPH	= 1 << 16	# experimental

cmd_mem$:
	push	ebp
	push	dword ptr 0	# allocate a flag to mark the options
	mov	ebp, esp

######## parse options
	add	esi, 4	# skip cmd name
	jmp	2f
0:	mov	eax, [eax]
	# 3 char flags: '-', 'h', 'a', 0
	cmp	eax, '-' | ('h'<<8)|('a'<<16)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_HANDLES_A
	jmp	2f
1:	cmp	eax, '-' | ('h'<<8)|('s'<<16)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_HANDLES_S
	jmp	2f
1:	# 2 char flags: '-', '?', 0
	and	eax, 0x00ffffff
	cmp	eax, '-' | ('h'<<8)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_HANDLES
	jmp	2f
1:	cmp	eax, '-' | ('k'<<8)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_KERNELSIZES
	jmp	2f
1:	cmp	eax, '-' | ('a'<<8)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_ADDRESSES
	jmp	2f
1:	cmp	eax, '-' | ('s'<<8)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_MEMMAP # print sections/memory map
	jmp	2f
1:	cmp	eax, '-' | ('c'<<8)	# print verbose
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_CODESIZES
	jmp	2f
	# experimental options:
1:	cmp	eax, '-' | ('g'<<8)
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_GRAPH	# print graph
	jmp	2f
	###
1:	jmp	9f
2:	call	getopt
	jnc	0b

######## print heap (default)
	printc 15, "Heap: "
	mov	eax, [mem_heap_size]
	xor	edx, edx
	call	print_size

	printc 15, " Reserved: "
	mov	eax, [mem_heap_alloc_start]
	sub	eax, [mem_heap_start]
	call	print_size

	push	eax
	printc 15, " Allocated: "
	call	mem_get_used
	call	print_size
	pop	eax

	printc 15, " Free: "
	sub	eax, [mem_heap_size]
	neg	eax
	call	print_size

	mov	ecx, ds
	mov	edx, [mem_heap_start]
	mov	eax, [mem_heap_size]
	add	eax, edx
	call	cmd_mem_print_addr_range$
	call	newline

######## print kernel sizes
1:	test	dword ptr [ebp], CMD_MEM_OPT_KERNELSIZES
	jz	1f

	printc 15, "Kernel: "
	xor	edx, edx
	mov	eax, kernel_end - kernel_code_start # realmode_kernel_entry
	call	print_size

	mov	edx, offset realmode_kernel_entry
	mov	eax, [kernel_stack_top]
	mov	ecx, cs
	call	cmd_mem_print_addr_range$
	call	newline

	printc 15, " Code: "
	mov	eax, kernel_code_end - kernel_code_start
	xor	edx, edx
	call	print_size
	printc 15, " (realmode: "
	mov	eax, kernel_rm_code_end - kernel_rm_code_start
	call	print_size
	printc 15, " pmode: "
	mov	eax, kernel_pm_code_end - kernel_pm_code_start
	call	print_size
	printc 15, ")"

	mov	ecx, cs
	mov	edx, offset realmode_kernel_entry
	mov	eax, offset kernel_code_end
	call	cmd_mem_print_addr_range$
	call	newline

	printc 15, " Data: "
	xor	edx, edx
	mov	eax, kernel_end - data_0_start
	call	print_size
	printc 15, " (rm: "
	mov	eax, data16_end - data16_start
	call	print_size

	mov	ecx, cs
	mov	edx, offset data16_start
	mov	eax, offset data16_end
	call	cmd_mem_print_addr_range$
	xor	edx, edx

	printc 15, " 0: "
	mov	eax, data_0_end - data_0_start
	call	print_size
	printc 15, " str: "
	mov	eax, data_str_end - data_str_start
	call	print_size
	printc 15, " bss: "
	mov	eax, data_bss_end - data_bss_start
	call	print_size
	mov	eax, kernel_end - data_bss_end
	or	eax, eax
	jz	2f
	printc 12, " 99: "
	call	print_size
2:	printc 15, ")"

	mov	ecx, cs
	mov	edx, offset data_0_start
	mov	eax, offset data_bss_end
	call	cmd_mem_print_addr_range$
	call	newline

	xor	edx, edx
	mov	eax, [kernel_symtab_size]
	or	eax, eax
	jz	2f
	printc 15, " Symbols: "
	call	print_size
	mov	edx, [symtab_load_start_flat]
	mov	eax, [symtab_load_end_flat]
	mov	ecx, SEL_flatDS
	call	cmd_mem_print_addr_range$

	# no stabs without symbols (though possible)
	xor	edx, edx
	mov	eax, [kernel_stabs_size]
	or	eax, eax
	jz	2f
	printc 15, " STABS: "
	call	print_size
	mov	edx, [stabs_load_start_flat]
	mov	eax, [stabs_load_end_flat]
	mov	ecx, SEL_flatDS
	call	cmd_mem_print_addr_range$
	call	newline

2:	xor	edx, edx
	printc 15, " Stack: "
	mov	eax, [kernel_stack_top]
	sub	eax, [ramdisk_load_end]	# offset kernel_end
	call	print_size
	mov	ecx, ss
	mov	edx, [ramdisk_load_end] # offset kernel_end
	mov	eax, [kernel_stack_top]
	call	cmd_mem_print_addr_range$
	call	newline

	xor	edx, edx
	printc 15, " Paging tables: "
	mov	eax, [page_tables_phys_end]
	sub	eax, [page_directory_phys]
	call	print_size
	mov	ecx, ds
	mov	eax, [page_directory_phys]
	mov	edx, [page_tables_phys_end]
	call	cmd_mem_print_addr_range$
	call	newline

######## print handles
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES
	jz	1f
	call	mem_print_handles
	jmp	2f
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES_A
	jz	1f
	mov	ebx, offset handle_ll_fa
	mov	edi, offset handle_ll_el_addr
	call	mem_print_ll_handles$
	jmp	2f
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES_S
	jz	1f
	mov	ebx, offset handle_ll_fs
	mov	edi, offset handle_ll_el_size
	call	mem_print_ll_handles$
2:
######## print memory map
1:	test	dword ptr [ebp], CMD_MEM_OPT_MEMMAP
	jz	1f

	.data SECTION_DATA_BSS
	mem_size_str_buf$: .space 3 + 1 + 3 + 2 + 1
	.text32
	# in: (besides arguments): ecx = end address of last section/memory range,
	#   to be compared with the start of this one, for misalignment/overlap error detection.
	# in: st = start address
	# in: nd = end address
	# in: sz = size (instead of nd)
	# in: fl = 1 = st/nd = flat addresses, 0=ds/kernel relative
	# out: ecx updated
	# out: (side-effect) ebx = start
	# out: (side-effect) edi = end (same as ecx)
	# destroys: eax, edx. (eax=range size, edx=0)
	.macro PRINT_MEMRANGE label, st=0, nd=0, sz=0, indent="", fl=0
		.ifnc 0,\st
		_PR_S = \st
		.else
		_PR_S = offset \label\()_start
		.endif
		.ifnc 0,\nd
		_PR_E = \nd
		.else
		_PR_E = offset \label\()_end
		.endif
		.data
		99: .ascii "\indent\label: "
		88: .space 22-(88b-99b), ' '
		.byte 0
		.text32
		# print label
		mov	ah, 15
		mov	esi, offset 99b
		call	printc

		# print cs/ds relative:
		mov	edx, _PR_S # offset \label\()_start
		.ifnc 0,\fl
		sub	edx, [database]
		.endif
		mov	ebx, edx	# remember start
		push	edx
		call	printhex8
		printchar_ '-'
		.if \sz
		add	edx, _PR_E #offset \label\()_end
		.else
		mov	edx, _PR_E #offset \label\()_end
		.ifnc 0,\fl
		sub	edx, [database]
		.endif
		.endif
		mov	edi, edx	# remember end
		call	printhex8
		# print size
		mov	eax, edx
		xchg	edx, [esp]	# store addresses
		sub	eax, edx	# for flat print
		push	edx
		call	printspace

		# a little check: ebx=start,ecx=prev end
		cmp	ebx, ecx
		mov	cl, '!'
		jnz	77f
		or	eax, eax
		js	77f
		mov	cl, ' '
	77:	printcharc 12, cl
		mov	ecx, edi	# remember new end

		call	printspace

		# print flat addresses:
		pop	edx	# start
		add	edx, [database]
		call	printhex8
		printchar '-'
		pop	edx	# end
		add	edx, [database]
		call	printhex8
		call	printspace
		call	printspace

		xor	edx, edx
		or	eax, eax
		jns	77f
		neg	eax
		printcharc 12, '-'
	77:
		push	edi
		mov	edi, offset mem_size_str_buf$
		mov	bl, 1<<4 | 3
		call	sprint_size_
		mov	byte ptr [edi], 0
		pop	edi

		push	ecx
		mov	esi, offset mem_size_str_buf$
		call	strlen_
		neg	ecx
		add	ecx, 3 + 1 + 3 + 2 +1
	77:	call	printspace
		loop	77b
		call	print
		pop	ecx

		call	newline
	.endm

	xor	ecx, ecx	# end address of previous entry
	PRINT_MEMRANGE kernel_rm_code
	PRINT_MEMRANGE data16
	PRINT_MEMRANGE kernel_pm_code

	test	dword ptr [ebp], CMD_MEM_OPT_CODESIZES
	jz	2f

	mov	ecx, offset code_print_start
	.irp _, print,pmode,paging,debugger,pit,keyboard,console,mem,hash,buffer,string,scheduler,tokenizer,dev,pci,bios,cmos,ata,fs,partition,fat,sfs,iso9660,shell,nic,net,vid,usb,gfx,hwdebug,vmware,kernel
	PRINT_MEMRANGE code_\_\(), indent="  "
	.endr

2:	PRINT_MEMRANGE data_0
	PRINT_MEMRANGE data_sem
	PRINT_MEMRANGE data_tls
	PRINT_MEMRANGE data_concat
	#PRINT_MEMRANGE data_concat within data0's range
	PRINT_MEMRANGE data_str
	PRINT_MEMRANGE data_shell_cmds
	PRINT_MEMRANGE data_pci_driverinfo
	PRINT_MEMRANGE data_fonts
	.if SECTION_DATA_SIGNATURE < SECTION_DATA_BSS
	PRINT_MEMRANGE data_signature
	PRINT_MEMRANGE data_bss
	.else
	PRINT_MEMRANGE data_bss
	PRINT_MEMRANGE data_signature
	.endif
	mov	edi, [kernel_load_end_flat]
	sub	edi, [database]
	PRINT_MEMRANGE "<slack>", ecx, edi
	PRINT_MEMRANGE "symbol table", [kernel_symtab], [kernel_symtab_size], sz=1
	PRINT_MEMRANGE "stabs", [kernel_stabs], [kernel_stabs_size], sz=1
	PRINT_MEMRANGE "stack", cs:[ramdisk_load_end], cs:[kernel_stack_top]
	PRINT_MEMRANGE "paging", ds:[page_directory_phys], ds:[page_tables_phys_end],fl=1

######## print graph
1:	test	dword ptr [ebp], CMD_MEM_OPT_GRAPH
	jz	1f
	call	cmd_mem_print_graph$

1:	add	esp, 4
	pop	ebp
	ret

9:	printlnc_ 12, "usage: mem [-k [-a]] [-h|-ha|-hs] [-s [-c]]"
	printlnc_ 12, "  -k   print kernel sizes"
	printlnc_ 12, "    -a print physical addresses"
	printlnc_ 12, "  -h   print malloc handles"
	printlnc_ 12, "  -ha  print allocated/free malloc handles by address"
	printlnc_ 12, "  -hs  print free malloc handles by size"
	printlnc_ 12, "  -s   print code/data sections/images/memory map"
	printlnc_ 12, "    -c print detailed code sections"
	jmp	1b


# in: edx = start
# in: eax = end
# in: ecx = selector
# in: [ebp]:2 = whether to print or not
cmd_mem_print_addr_range$:
	test	dword ptr [ebp], CMD_MEM_OPT_ADDRESSES
	jnz	1f
	ret
1:	GDT_GET_BASE ebx, ecx
	pushcolor 8
	print	" ["
	add	edx, ebx
	call	printhex8
	print	".."
	mov	edx, eax
	add	edx, ebx
	call	printhex8
	printchar ']'
	popcolor
	ret

cmd_mem_print_graph$:
	# 'graph': block diagram
	# iterate through handles, printing blocks
	push	esi
	push	eax
	mov	esi, [mem_handles]
	mov	ecx, [mem_numhandles]
	xor	edx, edx

3:	.if 1
	PRINT_START
	mov	ah, [esi + edx + handle_flags]
	and	ah, 0b1
	shl	ah, 2
	add	ah, 9
	shl	ah, 4
	mov	al, [esi + edx + handle_size]
	stosw
	PRINT_END
	.else
	push	edx
	movzx	edx, byte ptr [esi + edx + handle_flags]
	call	printhex2
	call	printspace
	pop	edx
	.endif
	add	edx, HANDLE_STRUCT_SIZE
	loop	3b
	pop	eax
	pop	esi
	call	newline
	ret

# in: eax = size to allocate
# in: edx = physial address alignment (must be powe of 2)
# FOR NOW:
# out: eax = mallocced address
# out: edx = aligned address
mallocz_aligned:
	push	ecx
	mov	ecx, eax
	call	malloc_aligned_
	jc	9f
	push_	edi eax
	push	ecx
	and	cl, 3
	mov	edi, eax
	xor	eax, eax
	rep	stosb
	pop	ecx
	shr	ecx, 2
	rep	stosd
	pop_	eax edi

9:	pop	ecx
	ret
