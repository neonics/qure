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
.include "list.s"
.data
mem_heap_start:	.long 0, 0
mem_heap_size:	.long 0, 0

mem_heap_alloc_start: .long 0

mem_sel_base: .long 0
mem_sel_limit: .long 0

MEM_DEBUG = 0

.text
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
# as it together with the base and flags allow to fall back to linear
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
#    pop [alloc_start]
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
.if 0
choose_direction$:
	mov	ebx, [edi + ll_first]
	mov	ebx, [esi + ebx + ll_value]
	sub	ebx, eax
	jns	1f	# the first is already big enough
	mov	ecx, [edi + ll_last]
	mov	ecx, [esi + ecx + ll_value]
	sub	ecx, eax
	js	2f	# the last is not big enough
	add	ecx, ebx	# difference of difference
	js	3f	# first difference is greater, go back from end
			# last difference is greater, go right from start
	# right:
	mov	ebx, [edi + ll_first]
	#...

3:	mov	ebx, [edi + ll_prev]
	#...
	ret

# uses temporary register edx to save one memory access per iteration.
# in: eax = size, ebx = the first node to start searching from.
# breadth-first search algorithm, no recursion:
find_by_size_r$:
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
1:	test	[esi + ebx + handle_flags], MEM_FLAG_REFERENCE
	jz	0f	# not a reference, found it!
	# it's a reference. Going deeper.
	# Option 1: does not keep track of the vertical path,
	# and will not support node removal.
	mov	ebx, [esi + ebx + handle_base]	# handle reference
	jmp	0b

0:	clc
	ret

# breadth first, using stack:
# in: eax=size, ebx=starting node
# out: ecx = depth of path
# out: [esp - 4] = bottom reference node
# out: [esp - 4 - ecx * 4] = top reference node
find_by_size_r$:
	xor	ecx, ecx

0:	cmp	eax, [esi + ebx + ll_value]
	jb	1f	# the smallest item can accommodate it
	mov	edx, [esi + ebx + ll_next]
	or	edx, edx
	mov	ebx, edx
	jns	0b	# there is a next, so continue

	shl	ecx, 2
	add	esp, ecx
	shr	ecx, 2
	stc
	ret

1:	test	[esi + ebx + handle_flags], MEM_FLAG_REFERENCE
	jz	0f	# not a reference, found it!

	push	ebx
	inc	ecx
	mov	ebx, [esi + ebx + handle_base]	# handle reference
	jmp	0b

0:	shl	ecx, 2
	add	esp, ecx
	shr	ecx, 2
	clc
	ret

.endif

# Now, with the above approach, unlinking an item from handle_fs directly,
# would need to have another field pointing up.

# The base list in the item is unused, except for base pointing to the
# lower item. 
# A rewrite for using two linked list: see find_by_size_r$ below.


#
# 
#
#
.struct 0	# ll_info
ll_value: .long 0
ll_prev: .long 0	
ll_next: .long 0
# ll_prev and ll_next, when their sign bit is 1, serve to mark the first/last
# nodes.
# This restricts the usage of pointers to be below 2Gb.
# 

.struct 0
# substruct ll_info: [base, prev, next] for fa
# NOTICE!!!!! handle_base is dependent to be 0 for optimization! Search for OPT
handle_base: .long 0
handle_fa_prev: .long 0		# offset into [mem_handles]
handle_fa_next: .long 0		# offset into [mem_handles]
# substruct ll_info: [size, prev, next] for fs
handle_size: .long 0	
handle_fs_prev: .long 0		# offset into [mem_handles]
handle_fs_next: .long 0		# offset into [mem_handles]
# rest:
handle_flags: .byte 0	# 25
	MEM_FLAG_ALLOCATED = 1
	MEM_FLAG_REUSABLE = 2	# handle's base and size are meaningless/0.
	MEM_FLAG_REFERENCE = 4

	# When there are more than this number of bytes wasted (i.e. reuse
	# of a chunk of previously free'd memory that is larger than the
	# requested size), the chunk will be split across two handles,
	# yielding a handle for the requested size (possibly padded for 
	# alignment).
	MEM_SPLIT_THRESHOLD = 64

HANDLE_STRUCT_SIZE = 32
.macro HITO r	# handle_index_to_offset
	shl	\r, 5
.endm

.macro HITDS r	# doubleword size (for movsd)
	shl	\r, 3
.endm

.macro HOTOI r
	sar	\r, 5
.endm

ALLOC_HANDLES = 32 # 1024
.data
mem_handles: .long 0
mem_numhandles: .long 0
mem_maxhandles: .long 0
mem_handles_handle: .long 0
.struct 0
ll_first: .long 0
ll_last: .long 0
.data
# substructs: pairs of _first and _last need to be in this order!
handle_fa_first: .long -1	# offset into [mem_handles]
handle_fa_last: .long -1	# offset into [mem_handles]
handle_fs_first: .long -1	# offset into [mem_handles]
handle_fs_last: .long -1	# offset into [mem_handles]
handle_fh_first: .long -1
handle_fh_last: .long -1	# not really used...
.text

MEM_LL = 0

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
	call	printhex8
	mov	edx, [esi + 0 ] #memory_map_base + 0 ]
	call	printhex8
	PRINT	" | "

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


#	call	malloc_test$
	ret

###########################################

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
		call	print_handles$
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
	call	print_handles$
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
	call	print_handles$
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
	call	print_handles$
	call	more
	COLOR	15
	.endm

	.macro MEM_TEST_FREE 
	print	"free "
	mov	edx, eax
	call	printhex8
	call	mfree
	COLOR	7
	call	print_handles$
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
	call	print_handles$
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
	call	print_handles$
	printlnc 15, "* Test completed."

	ret

more:	MORE
	ret
#######################################################################

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
	jae	1f

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

1:	printc 4, "malloc_internal: out of memory: free="
	call	printhex8
	printc 4, " requested: "
	mov	edx, eax
	call	printhex8
	call	newline
	stc
	jmp	0b

########################################################################

.text
kalloc_test:
	mov	eax, 1024
	.rept 5
	push	eax

		print "allocating "
		mov	edx, eax
		call	printhex8

	call	kalloc

		print " address: "
		mov	edx, eax
		call	printhex8
		call	newline

	pop	eax
	shr	eax, 1
	.endr
	call	kalloc_printmem
	ret


kalloc:
	add	eax, 4	# reserve space for size
	push	eax
	call	malloc_internal$
	pop	[eax]
	add	eax, 4
	push	eax
	mov	eax, [mem_heap_alloc_start]
	mov	[eax], dword ptr 0
	pop	eax
	ret

kalloc_printmem:
	println "kalloc memory map:"
	mov	esi, [mem_heap_start]

0:	mov	edx, esi
	call	printhex8
	mov	al, ' '
	call	printchar

	mov	edx, [esi]
	call	printhex8
	call	newline

	or	edx, edx
	jz	0f

	add	esi, edx
	jmp	0b
0:
	ret

#######################################################################

print_handles$:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi

######### print handles..

	print "handles: "
	mov	edx, [mem_numhandles]
	mov	ecx, edx
	call	printdec32
	printchar '/'
	mov	edx, [mem_maxhandles]
	call	printdec32
	print " addr: "
	mov	edx, [mem_handles]
	call	printhex8
	print " handle: "
	mov	edx, [mem_handles_handle]
	HOTOI	edx
	call	printdec32
	print " U["
	mov	edx, [handle_fh_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [handle_fh_last]
	HOTOI	edx
	call	printdec32
	print "] A["
	mov	edx, [handle_fa_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [handle_fa_last]
	HOTOI	edx
	call	printdec32
	print	"] S["
	mov	edx, [handle_fs_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [handle_fs_last]
	HOTOI	edx
	call	printdec32
	print	"]"
	call	newline

#	jecxz	1f
	or	ecx, ecx
	jz	6f


	.macro PRINT_LL_FIRSTLAST listname=""
	.if MEM_DEBUG
		printc 4, " \listname["
		push	edx
		mov	edx, [edi]
		HOTOI	edx
		call	printdec32
		printcharc 4, ','
		mov	edx, [edi+ll_last]
		HOTOI	edx
		call	printdec32
		pop	edx
		printc 4, "] "
	.endif
	.endm

	.macro LL_PRINT firstlast, prevnext
		push	edi
		mov	edi, offset \firstlast
		PRINT_LL_FIRSTLAST
		pop	edi
		push	ecx
		mov	esi, [mem_handles]
		add	esi, \prevnext
		mov	ebx, [\firstlast + ll_first]
		# check first
		or	ebx, ebx
		jns	1f

		# the first is -1, so check if last is -1
		cmp	[\firstlast + ll_last], ebx
		jz	2f
		printc 4, " first "
		mov	edx, ebx
		HOTOI	edx
		call	printdec32
		printc 4, " != last "
		mov	edx, [\firstlast + ll_last]
		HOTOI	edx
		call	printdec32
		jmp	2f

		# first is not -1, so check if it's prev is -1
	1:	mov	edx, [esi + ebx + ll_prev]
		or	edx, edx
		js	0f
		pushcolor 4
		HOTOI	edx
		call	printdec32
		print	"<-"
		popcolor

	######### loop the list forward
	0:	
		# print next
		mov	edx, ebx
		HOTOI	edx
		call	printdec32

		# check backreference of next
		mov	eax, [esi + ebx + ll_next]
		or	eax, eax
		js	0f	# it's the last
		cmp	[esi + eax + ll_prev], ebx
		jz	1f
		printc 4, "<"
	1: 
		printc	8, "->"
		mov	ebx, eax
		loop	0b
	0:
	##########

	.if 0
		# check the last
		mov	edx, [\firstlast + ll_last]
		cmp	edx, ebx
		jz	0f
		pushcolor 4
		print	"->"
		HOTOI	edx
		call	printdec32
		printchar ' '
		mov	edx, [esi + ebx + ll_next]
		HOTOI	edx
		call	printdec32
		popcolor
	0:
	.endif
	2:
		pop	ecx
	.endm

	.macro LL_PRINTARRAY mask, cmp
		printc 8, "    ["
		push	ecx
		mov	esi, [mem_handles]
		xor	ebx, ebx
	0:	mov	al, [esi + ebx + handle_flags]
		and	al, \mask
		cmp	al, \cmp
		jne	1f
		mov	edx, ebx
		HOTOI	edx
		call	printdec32
		printcharc 8, ','
	1:	add	ebx, HANDLE_STRUCT_SIZE
		loop	0b
		pop	ecx
		printc	8,"]"
	.endm

	print	"U: "
	LL_PRINT handle_fh_first, handle_base #, MEM_FLAG_REUSABLE
	LL_PRINTARRAY MEM_FLAG_REUSABLE, MEM_FLAG_REUSABLE
	call	newline

	PRINT	"A: "
	LL_PRINT handle_fa_first, handle_base
	LL_PRINTARRAY MEM_FLAG_REUSABLE, 0
	call	newline
	PRINT	"S: "
	LL_PRINT handle_fs_first, handle_size
	LL_PRINTARRAY (MEM_FLAG_ALLOCATED|MEM_FLAG_REUSABLE), 0
	call	newline


	mov	ebx, [mem_handles]
0:	mov	edx, [mem_numhandles]
	sub	edx, ecx
	
	call	print_handle_$
	add	ebx, HANDLE_STRUCT_SIZE

	#loop	0b
	dec	ecx
	jnz	0b
6:

	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

print_handle_$:
	print "Handle " 
	call	printdec32
	printchar ' '
	mov	edx, ebx
	call	printhex8
	print " base "
	mov	edx, [ebx + handle_base]
	call	printhex8
	print " size "
	mov	edx, [ebx + handle_size]
	call	printhex8
	print " flags "
	mov	dl, [ebx + handle_flags]
	call	printbin8
	print " A["
	mov	edx, [ebx + handle_fa_prev]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [ebx + handle_fa_next]
	HOTOI	edx
	call	printdec32
	print "] S["
	mov	edx, [ebx + handle_fs_prev]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [ebx + handle_fs_next]
	HOTOI	edx
	call	printdec32
	print "]"

	call	newline

	ret

print_handle$:
	push	edx
	mov	edx, ebx
	HOTOI	edx
	add	ebx, esi
	call	print_handle_$
	sub	ebx, esi
	pop	edx
	ret


# Returns a free handle, base and size to be filled in, marked nonfree.
# in: esi = [mem_handles]
# out: esi might be updated if handle array is reallocated
# out: ebx = handle index
get_handle$:
	# first check if we can reuse handles:
	mov	ebx, [handle_fh_first]
	or	ebx, ebx
	js	0f

	push	edi
	mov	edi, offset handle_fh_first
	#add	esi, offset handle_base OPT
	call	ll_unlink$
	#sub	esi, offset handle_base OPT
	pop	edi

	and	[esi + ebx + handle_flags], byte ptr ~MEM_FLAG_REUSABLE
	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	ret

0:	mov	ebx, [mem_numhandles]
	cmp	ebx, [mem_maxhandles]
	jb	0f
	call	alloc_handles$	# updates esi
	# jc halt?
0:	mov	ebx, [mem_numhandles]
	
	HITO	ebx
	mov	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	mov	[esi + ebx + handle_fs_next], dword ptr -1
	mov	[esi + ebx + handle_fs_prev], dword ptr -1
	mov	[esi + ebx + handle_fa_next], dword ptr -1
	mov	[esi + ebx + handle_fa_prev], dword ptr -1
	inc	dword ptr [mem_numhandles]
	ret

# in: eax = size
# in: esi = [mem_handles]
# out: ebx = handle index that can accommodate it
# out: CF on none found
find_handle$:
	mov	ebx, [handle_fs_first]
	push	ecx
	mov	ecx, [mem_numhandles]

0:	or	ebx, ebx
	js	1f
	# safety check
	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	2f
	cmp	eax, [esi + ebx + handle_size]
	jbe	0f
2:	mov	ebx, [esi + ebx + handle_fs_next]
	loop	0b

1:	stc
2:	pop	ecx
	ret

# sublevel 1: whether to split
# out: ebx 
0:	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, eax
	cmp	ecx, MEM_SPLIT_THRESHOLD
	jae	1f
	.if MEM_DEBUG 
		printc 3, "No Split"
	.endif
	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	push	edi
	mov	edi, offset handle_fs_first
	add	esi, offset handle_size
	call	ll_unlink$
	sub	esi, offset handle_size
	pop	edi
	clc
	jmp	2b

# sublevel 2: split implementation
1: 
	.if MEM_DEBUG 
		printc 4, "Split "
	.endif
	push	edx
# sublevel 3: set up new handle
	mov	edx, ebx
	call	get_handle$	# already marked MEM_FLAG_ALLOCATED
	.if MEM_DEBUG
		push edx
		pushcolor 4
		HOTOI edx
		call	printdec32
		print " -> new "
		mov	edx, ebx
		HOTOI edx
		call	printdec32
		printchar ' '
		popcolor
		pop edx
	.endif
	# debug markings
	or	byte ptr [esi + ebx + handle_flags], 8
	or	byte ptr [esi + edx + handle_flags], 16

	# edx = handle to split, ebx = handle to return, eax = size
	mov	ecx, [esi + edx + handle_base]
	# donate the first eax bytes of edx to ebx, and shift the base of edx
	add	[esi + edx + handle_base], eax
	sub	[esi + edx + handle_size], eax
	mov	[esi + ebx + handle_base], ecx
	mov	[esi + ebx + handle_size], eax

	# since both handles are within the range of the original,
	# it's base (handle_fa_..) won't change. 

	# insert the new handle before the old handle
	push	edi
	push	eax
	# prepend ebx to edx
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base
	mov	eax, edx
	call	ll_insert_before$
	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.
	# use a specialized insert routine, that starts searching
	# somewhere in the list (not necessarily at the beginning/ending).
	# Since the list has shrunk in size, only search left.
	mov	edi, offset handle_fs_first
	add	esi, offset handle_size - offset handle_base
	# ebx is the new handle - ignore it (but save it)
	push	ebx
	mov	ebx, edx
	call	ll_update_left$
	pop	ebx

	sub	esi, offset handle_size

	pop	eax
	pop	edi

	## return

	pop	edx
	clc
	jmp	2b	# 'ret'
.if 1
.else
# defunct code

	# insert the new handle in the address list directly before edx
	mov	eax, edx
		pushcolor 4
		push	edx
		HOTOI edx
		call	printdec32
		print "<-"
		mov	edx, ebx
		HOTOI edx
		call	printdec32
		pop	edx
		popcolor
	push	edi
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base
	xchg	eax, ebx
	call	ll_insert$
	xchg	eax, ebx
	sub	esi, offset handle_base
	pop	edi
# sublevel 4: update list ordering
	# since edx has shrunk in size, see if we need to move it
	push	ebx

	mov	ebx, [esi + edx + handle_fs_prev]
	or	ebx, ebx
	js	1f	# is first, dont do anything
	mov	eax, [esi + edx + handle_size]
	cmp	eax, [esi + ebx + handle_size]
	jae	1f	# same or larger size, dont change position (append)
	printc 2, "loop"
# sublevel 5: find new place in list
	# walk to 'prev' to find find the first block that is smaller
	mov	ecx, [mem_numhandles] # safety check
0:	cmp	[esi + ebx + handle_fs_prev], dword ptr -1
	jz	3f	# it is smaller than the first handle, so prepend
	mov	ebx, [esi + ebx + handle_fs_prev]
	cmp	eax, [esi + ebx + handle_size]
	jae	0f	# insert (not append)
	loop	0b
# sublevel 6: prepend
3:	# prepend
	printc 2, "prepend"
	mov	[esi + ebx + handle_fs_prev], edx
	mov	[handle_fs_first], edx
	mov	[esi + ebx + handle_fs_next], ebx
# sublevel 6: nop/append when last
1:	# nop
	printc 2, "nop"
	pop	ebx
	pop	edx
	clc
	jmp	2b	# 'ret'
# sublevel 6: insert
0:	# insert
	printc 2, "insert"
	mov	[esi + edx + handle_fs_prev], ebx
	mov	eax, [esi + ebx + handle_fs_next]
	mov	[esi + edx + handle_fs_next], eax
	mov	[esi + ebx + handle_fs_next], edx
	mov	[esi + eax + handle_fs_prev], edx
	jmp	1b
.endif

# TODO: use [esi+ebx+handle_fs_next] to find smallest fit,
# then, see if difference in size is large enough (threshold) to split 

# in: eax = size
# out: ebx = handle that can accommodate it
# out: ZF on none found
# Returns a handle pointing to pre-allocated free memory that fits the request.
find_handle_linear$:
	.if MEM_DEBUG > 1
		pushcolor 3
		print "find handle size "
		push	edx
		mov	edx, eax
		call	printhex8
		pop	edx
		call	print_handles$
		popcolor
	.endif
	push	ecx

	mov	ecx, [mem_numhandles]
	jecxz	1f

	mov	ebx, [mem_handles]
0:	
		pushcolor 2
		push	edx
		mov	edx, ebx
		call	printhex8
		printchar ' '
		movzx	edx, byte ptr [ebx + handle_flags]
		call	printdec32
		printchar ' '
		pop	edx
		popcolor 2

	test	[ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	2f
	cmp	[ebx + handle_size], eax
	jae	3f
2:	add	ebx, HANDLE_STRUCT_SIZE
	loop	0b

	# when storing in non-record form - each field in its own array -,
	# a repne scasb will more quickly find a free handle.

1:	or	ecx, ecx
	pop	ecx
	ret

3:	or	[ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	push	esi
	mov	esi, [mem_handles]
	sub	ebx, esi
	push	edi
	mov	edi, offset handle_fs_first
	add	esi, offset handle_size
	call	ll_unlink$
	sub	esi, offset handle_size
	pop	edi
	clc
	pop	esi
	jmp	1b

# out: esi = [mem_handles]
alloc_handles$:
	push	eax
	push	ebx

	mov	eax, ALLOC_HANDLES 
	add	eax, [mem_maxhandles]
	HITO	eax
	push	eax	# save size for later
	call	malloc_internal$

	# bootstrap realloc
	cmp	dword ptr [mem_handles], 0
	jz	1f

	push	edi
	push	ecx
	mov	esi, [mem_handles]
	mov	edi, eax
	mov	ecx, [mem_maxhandles]
	HITDS	ecx
	rep	movsd
	pop	ecx
	pop	edi


	# free the old handle
	push	ebx
	mov	ebx, [mem_handles_handle]
	mov	[eax + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED | (1<<6)
	pop	ebx

1:	
	mov	[mem_handles], eax
	add	[mem_maxhandles], dword ptr ALLOC_HANDLES

	# reserve a handle
	mov	esi, eax
	call	get_handle$	# potential recursion
	mov	[mem_handles_handle], ebx
	pop	dword ptr [esi + ebx + handle_size]
	mov	[esi + ebx + handle_base], eax
	or	[esi + ebx + handle_flags], byte ptr 1 << 7
	push	edi
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base
	call	ll_update$
	sub	esi, offset handle_base
	pop	edi


		.if MEM_DEBUG > 1
		push	edx
		print " newhandle "
		mov	edx, ebx
		call	printhex8
		printchar ' '
		mov	edx, [ebx + handle_base]
		call	printhex8
		call	newline
		pop	edx

		pushad
		pushcolor 14
		call	print_handles$
		popcolor
		MORE
		popad	
		.endif
	
	# When we're here, the handles are set up properly, at least one
	# allocated for the handle structures themselves.
	# Now allocate the lists:

	pop	ebx
	pop	eax
	ret

mallocz:
	push	ecx
	mov	ecx, eax
	call	malloc
_mallocz_malloc_ret$:
	jc	9f
	push	edi
	mov	edi, eax
	push	eax
	xor	eax, eax
	push	ecx
	and	ecx, 3
	rep	stosb
	pop	ecx
	shr	ecx, 2
	rep	stosd
	clc
	pop	eax
	pop	edi
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
	call	newline
	pop	edx
	jmp	1b


#########################################################
# in: eax = size
# out: eax = base pointer
malloc:
#call mem_debug
	push	ebx
	push	esi
	mov	esi, [mem_handles]
	call	find_handle$
	jc	2f
	# jz	2f	# for find_handle_linear$
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
	jmp	1f

2:	call	get_handle$
	jc	2f

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
	jc	3f

	.if MEM_DEBUG
		push	edx
		print " base: "
		mov	edx, eax
		call	printhex8
		pop	edx
	.endif

	mov	[esi + ebx + handle_base], eax

	push	edi
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base
	call	ll_update$
	sub	esi, offset handle_base
	pop	edi

	clc

1:	pop	esi
	pop	ebx

	.if MEM_DEBUG > 1
		pushf
		pushcolor 8
		call	print_handles$
		MORE
		popcolor
		popf
	.endif
	ret

2:	printlnc 4, "malloc: no more handles"
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
	call	newline
2:	pop	eax
	pop	edx
	
	stc
	jmp	1b


.if 0
# in: eax = mem base ptr
# out: ebx = handle ptr
get_handle_by_base_linear$:
	push	ecx
	mov	ecx, [mem_numhandles]
	or	ecx, ecx
	jnz	1f
2:	stc
3:	pop	ecx
	ret

1:	mov	ebx, [mem_handles]
0:	cmp	eax, [ebx + handle_base]
	jz	3b
	add	ebx, HANDLE_STRUCT_SIZE
	loop	0b
	jmp	2b
.endif

# in: eax = mem base ptr
# out: ebx = handle ptr
get_handle_by_base$:
	push	esi
	push	ecx
	mov	ecx, [mem_numhandles]
	jecxz	2f
####
	mov	esi, [mem_handles]
	mov	ebx, [handle_fa_first]

0:	or	ebx, ebx
	js	2f
	cmp	eax, [esi + ebx + handle_base]
	jz	3f
	mov	ebx, [esi + ebx + handle_fa_next]
	loop	0b
####
2:	stc
3:	pop	ecx
	pop	esi
	ret


.macro MREALLOC malloc
	or	eax, eax
	jnz	1f
	mov	eax, edx
	jmp	\malloc
1:
########
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
	call	newline
	pop	edx
	
	jmp	0f
1:
########
	# Check if the call is for growth
	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, edx	# ecx = cursize - newsize
	jns	2f	# shrink

	neg	ecx

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
	mov	ecx, edx
	sub	ecx, [esi + ebx + handle_size] # ecx = bytes to borrow
	sub	ecx, [esi + edi + handle_size]
	neg	ecx	# ecx contains the leftover size of edi.
	# js...
	cmp	ecx, MEM_SPLIT_THRESHOLD
	jb	5f	# take it all

	# just borrow the bytes, leave the handle as is.

	mov	ecx, edx
	sub	ecx, [esi + ebx + handle_size]
	add	[esi + ebx + handle_size], ecx
	sub	[esi + edi + handle_size], ecx
	add	[esi + edi + handle_base], ecx
	jmp	0f

5:	# take all the memory - merge the handles.

	# edi is unallocated handle, and thus it is part of the lists:
	# handle_fa - to maintain address order
	# handle_fs - free-by-size
	# Clear them both out.
	mov	ebx, edi
	mov	edi, offset handle_fs_first
	add	esi, offset handle_size
	call	ll_unlink$
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base - offset handle_size
	call	ll_unlink$
	mov	edi, offset handle_fh_first
	call	ll_update$

	# eax is unchanged
	jmp	0f

####### allocate a new block and copy the data.
1:
	mov	ecx, [esi + ebx + handle_size]
	push	esi
	mov	esi, eax

	mov	eax, edx
	call	\malloc
	# copy
	or	ecx, ecx	# shouldnt happen if malloc checks for it.
	jz	1f
	mov	edi, eax
	rep	movsb

1:	pop	esi
	or	[ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED

	# free the old handle
	push	eax
	mov	eax, [esi + ebx + handle_base]
	call	mfree	# TODO: optimize, as handle is known
	pop	eax

	# jmp 0f # when shrink implemented.

########
2:	# shrink: ignore.
########

0:	pop	edi
	pop	esi
	pop	ecx
	pop	ebx
.endm


# in: eax = mem, edx = new size
# out: eax = reallocated (memcpy) mem
mrealloc:
	MREALLOC malloc
	ret

mreallocz:
	MREALLOC mallocz
	ret

# in: eax = memory pointer
mfree:
	push	esi
	push	ecx
	push	ebx
	mov	ecx, [mem_numhandles]
	or	ecx, ecx
	jz	1f
	#jecxz	1f
	mov	esi, [mem_handles]
	mov	ebx, [handle_fa_last]

0:	or	ebx, ebx
	js	1f
	cmp	eax, [esi + ebx + handle_base]
	jz	3f
	mov	ebx, [esi + ebx + handle_fa_prev]
	loop	0b
	jmp	1f

3:	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jz	1f
	and	[esi + ebx + handle_flags], byte ptr ~MEM_FLAG_ALLOCATED

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
	ret

1:	pushcolor 4
	print	"free called for unknown pointer "
	push	edx
	mov	edx, eax
	call	printhex8
	print " called from "
	mov	edx, [esp + 4*4 + 2]
	call	printhex8
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


# in: esi, ebx
# destroyed: edi, eax, edx
# out: CF = 0: merged; ebx = new handle. CF=1: no merge, ebx is marked free.
handle_merge_fa$:
0:	xor	edi, edi

	# Check if ebx follows the previous handle
	mov	eax, [esi + ebx + handle_fa_prev]
	or	eax, eax
	js	1f
	test	byte ptr [esi + eax + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f
	mov	edx, [esi + eax + handle_base]
	add	edx, [esi + eax + handle_size]
	cmp	edx, [esi + ebx + handle_base]
	jnz	1f

	# eax preceeds ebx immediately
	# empty ebx, add memory to eax:
	xor	edx, edx
	xchg	edx, [esi + ebx + handle_size]
	add	[esi + eax + handle_size], edx
	# empty out ebx
	jmp	2f

1:	# check if ebx preceeds the following handle
	mov	eax, [esi + ebx + handle_fa_next]
	or	eax, eax
	js	1f
	test	byte ptr [esi + eax + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f
	mov	edx, [esi + ebx + handle_base]
	add	edx, [esi + ebx + handle_size]
	cmp	edx, [esi + eax + handle_base]
	jnz	1f

	# ebx preceeds eax immediately.
	# Prepend ebx's size to eax:
	xor	edx, edx
	xchg	edx, [esi + ebx + handle_size]
	sub	[esi + eax + handle_base], edx

2:	# merge

	# empty out ebx:
	# remove from the address list
	mov	edi, offset handle_fa_first
	add	esi, offset handle_base
	call	ll_unlink$
	# add to the reusable handles list
	mov	edi, offset handle_fh_first
	call	ll_update$
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_REUSABLE

MERGE_RECURSE = 0
	# eax's address list membership doesnt change.
	# eax's size address might have changed:
	mov	ebx, eax
.if MERGE_RECURSE
	sub	esi, offset handle_base
	mov	edi, -1	# loop 
	jmp	0b
3:
.else
	add	esi, offset handle_size - offset handle_base
.endif
	mov	edi, offset handle_fs_first
	call	ll_unlink$
	call	ll_update$

	# leave ebx to point to the newly free'd memory.
	clc
	ret

1:	# no matches. mark memory as free.
.if MERGE_RECURSE
	cmp	edi, -1
	je	3b
.endif
	mov	edi, offset handle_fs_first
	add	esi, offset handle_size
	call	ll_update$
	sub	esi, offset handle_size
	stc
	ret


# State diagram for the linked list memory management
#
# Notation:
#   x.base<->	base is a linked list, where x.base is the value of base for x.
#
# handle.size = 0:
#	handle.base<->:
#		flags:
#			REUSABLE, ALLOCATED
#				1	, (0,1) => handle_fh[]
#				0	, 0	=> handle_fa[] // reserved=free
#				0	, 1	=> handle_fa[] // allocated 
#	handle.base<->:
#		handle_fh[]: size == 0 := REUSABLE = 1;
#		handle_fa[]: size != 0 := REUSABLE = 0;
#
#	handle.size<->:
#		handle_fs[]: size >= && REUSABLE == 0; // free by size
#		handle_as[]:
#
#		REUSABLE, ALLOCATED	base		size
# handle_fa:	0		, irrelevant	base > 0	size > 0
# handle_fs: 	0		, irrelevant	base > 0	size > 0
# handle_fh:	1		, irrelevant 	0/irrelevant	0/irrelevant
# handle_as:
#
# base: handle_fa, handle_fh
# size: handle_fs
#
# for items in handle_fh, using base, size is ignored.
# this means that these elements will not be in lists based on size,
# which means that handle_fs will not contain this item.
# all items in handle_fa are in handle_fs and vice versa.
# 
# The cross-section of handle_fh and handle_fa is empty.
# The cross-section of handle_fh and handle_fs is empty.
# The cross-section of handle_fa and handle_fs is their union.
# [this last one means that they are identical].
# 
# Triggers:
#
# size == 0 -> join handle_fh, [leave handle_fa], leave handle_fs.
#   [the base value is meaningless, even though the base list is used, to keep
#    a dynamic list (i did this in c++ once) of reusable handles].
#   [leave handle_fa is a consequence of join_handle_fh as they are both
#   based on the handle_base field.]
# size > 0 == base > 0: [this means that when size becomes > 0, base
#   is required to also become > 0, and vice versa].
#
###########################################################################


##################################################### LINKED LIST ############
#
# in: ebx = handle index
# in: esi = [mem_handles] + offset to ll_info within struct
# 	offset to linked list info: [value, prev, next]
#	[esi + ebx + ll_value]	= link_value (i.e. _base, _size)
#	[esi + ebx + ll_prev]	= link_prev (i.e. _fa_prev, _fs_prev)
#	[esi + ebx + ll_next]	= link_next (i.e. _fa_next, _fs_next)
# in: edi = first/last list info pointer: [first, last]
#
# This routine inserts ebx into an ascending sorted list.
ll_update$:
	push	edx
	push	ecx
	push	ebx
	push	eax

	mov	eax, [edi + ll_first]
	or	eax, eax
	js	1f

	######################################################
	mov	edx, [esi + ebx + ll_value]
	mov	ecx, [mem_maxhandles]
0:	
	# check free-by-size
	cmp	[esi + eax + ll_value], edx
	jae	2f
	mov	eax, [esi + eax + ll_next]
	or	eax, eax
	js	3f
	loop	0b
3:	# append to end of list
	.if MEM_DEBUG
	printc 3, "LAST"
	.endif
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
	.if MEM_DEBUG > 1
	push	edx
	print "INSERT "
	mov	edx, eax
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [esi + eax + ll_value]
	call	printhex8
	print " -> "
	mov	edx, ebx
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [esi + ebx + ll_value]
	call	printhex8
	print " esi = "
	mov	edx, esi
	call	printhex8
	pop	edx
	.endif
	
	.if MEM_DEBUG
	printc 3, "PREPEND"
	.endif

#	or	eax, eax
#	js	3f
	mov	edx, [esi + eax + ll_prev] # edx = eax.prev
	or	edx, edx
	jns	6f
	mov	[edi + ll_first], ebx
4:	jmp	4f
6:	mov	[esi + edx + ll_next], ebx # eax.prev.next = ebx
4:	mov	[esi + eax + ll_prev], ebx # eax.prev = ebx
	mov	[esi + ebx + ll_prev], edx # ebx.prev = eax.prev
3:	mov	[esi + ebx + ll_next], eax # ebx.next = eax
	jmp	5f
	######################################################

1:	# store it as the first handle
	.if MEM_DEBUG
	printc 3, "FIRST"
	.endif
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

# in: esi, edi
# in: ebx: handle to place in the list, still part of it
ll_update_left$:
	push	eax
	push	ecx
	push	edx

	mov	ecx, [mem_numhandles]	# circular list protection
	mov	edx, [esi + ebx + ll_value]
	mov	eax, [esi + ebx + ll_prev]
	or	eax, eax	# already first, dont move
	js	1f
	cmp	edx, [esi + eax + ll_value]	# check the first
	ja	1f				# no change
	mov	eax, [esi + eax + ll_prev]

0:	cmp	edx, [esi + eax + ll_value]
	ja	2f
	loop	0b
	# first
	call	ll_unlink$
	call	ll_prepend$
	jmp	1f
	
2:	# insert
	call	ll_unlink$
	call	ll_update$

1:	pop	edx
	pop	ecx
	pop	eax
	ret


# in: esi, edi
# in: ebx: handle to place in the list, still part of it
ll_update_right$:
	push	eax
	push	ecx
	push	edx

	mov	ecx, [mem_numhandles]	# circular list protection
	mov	edx, [esi + ebx + ll_value]
	mov	eax, [esi + ebx + ll_next]
	or	eax, eax	# already first, dont move
	js	1f
	cmp	edx, [esi + eax + ll_value]	# check the first
	ja	1f				# no change
	mov	eax, [esi + eax + ll_next]

0:	cmp	edx, [esi + eax + ll_value]
	ja	2f
	loop	0b
	# first
	print "(ll_update_right first)"
	call	ll_unlink$
	call	ll_prepend$
	jmp	1f
	
2:	# insert
	print "(ll_update_right insert)"
	call	ll_unlink$
	call	ll_insert$

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

# inserts ebx after eax.
#
# in: esi = array pointer + ll_value
# in: ebx is record offset within array to append to
# in: eax, record offset.
# in: edi = ll_first pointer
ll_insert$:
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

# in: ebx = record offset, handle must have been unlinked!
# in: esi = array offset + ll_value
# in: edi = offset ll_first
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

# WARNING: this routine will reset the lists's ll_first/last when the item
# is not IN the list!
# in: ebx = record ofset
# in: esi = array offset + ll_value
# in: edi = offset ll_first
ll_unlink$:
	push	eax
	push	edx
	mov	eax, -1
	mov	edx, eax
	# eax = ebx.prev
	# edx = ebx.next
	xchg	eax, [esi + ebx + ll_prev]
	xchg	edx, [esi + ebx + ll_next]

	or	eax, eax	# is ebx.prev -1?
	jns	0f
	# ebx was the first
	mov	[edi + ll_first], edx # yes - mark ebx.next as first
	jmp	1f
0:	mov	[esi + eax + ll_next], edx
1:
	or	edx, edx
	jns	0f
	mov	[edi + ll_last], eax
	jmp	1f
0:	mov	[esi + edx + ll_prev], eax
1:	
	pop	edx
	pop	eax
	ret



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


##############################################################################
# Commandline utility

cmd_mem$:
	printc 15, "Heap: "
	mov	eax, [mem_heap_size]
	xor	edx, edx
	call	print_size

	printc 15, " Allocated: "
	mov	eax, [mem_heap_alloc_start]
	sub	eax, [mem_heap_start]
	call	print_size

	printc 15, " Free: "
	sub	eax, [mem_heap_size]
	neg	eax
	call	print_size

	call	newline

0:	add	esi, 4
	call	getopt
	jc	0f
	mov	eax, [eax]
	and	eax, 0x00ffffff
	cmp	eax, '-' | ('h'<<8)
	jz	1f
	cmp	eax, '-' | ('k'<<8)
	jnz	9f
	
	printc 15, "Kernel: "
	mov	eax, kernel_end - realmode_kernel_entry
	call	print_size
	call	newline
	printc 15, " Code: "
	mov	eax, kernel_code_end - realmode_kernel_entry 
	call	print_size
	printc 15, " (realmode: "
	mov	eax, realmode_kernel_end - realmode_kernel_entry
	call	print_size
	printc 15, " pmode: "
	mov	eax, kernel_code_end - realmode_kernel_end
	call	print_size
	printlnc 15, ")"
	printc 15, " Data: "
	mov	eax, kernel_end - data_0_start
	call	print_size
	printc 15, " (0: "
	mov	eax, data_0_end - data_0_start
	call	print_size
	printc 15, " str: "
	mov	eax, data_str_end - data_str_start
	call	print_size
	printc 15, " bss: "
	mov	eax, data_bss_end - data_bss_start
	call	print_size
	printc 15, " 99: "
	mov	eax, kernel_end - data_bss_end
	call	print_size
	printlnc 15, ")"


	jmp	0b

1:	push	esi
	call	print_handles$
	pop	esi
	jmp	0b
0:	
	ret

9:	printlnc 4, "usage: mem [-hk]"
	printlnc 4, "  -k   print kernel sizes"
	printlnc 4, "  -h   print handles"
	ret

