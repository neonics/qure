##############################################################################
# Memory Management
#
# This implementation combines multiple linked lists to track memory
# efficiently across two dimensions of space: address and size.
#
# It offers the ability to cut up a space into pieces of different
# sizes and keep track of where they belong.
#
# = Extension Points =
#
# == mrealloc ==
#
# When it is possible to avoid copying data, it will do so. When the
# requested size is larger, it's tail will be allocated.
#
#
#
#
# These two basic linked lists are ordered, so that they have to be traversed
# at most once to find the smallest accommodating size.
#
# = Known limitations =
#
# - those of the linked list implementation
#
#
#
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
# mem_handle_ll_fa + ll_first/last: base, non-zero-length memory blocks (allocated&free)
# mem_handle_ll_fh + ll_first/last: base, null memory blocks - available handles.
# mem_handle_ll_fs + ll_first/last: size, available/free pre-allocated memory blocks (malloc)
# mem_handle_ll_?? + ll_first/last: size, unavailable/allocated memory blocks (for mfree)

.intel_syntax noprefix

MEM_DEBUG = 0
MEM_DEBUG2 = 1		# validate handles structure (does printing...)
MEM_PRINT_HANDLES = 2	# 1 or 2: different formats.

MALLOC_PAGE_DEBUG = 0		# 0=off, 1=trace, 2=registers
MALLOC_PAGE_DEBUG_PTR_BIT = 0	# 0=off, 1= set page addr lowest bit to 1 in array

MEM_FEATURE_STRUCT = 1	# 0: static kernel mem variables; 1: use pointer
	# This feature allows to specify a pointer to the memory
	# bookkeeping structure to most of the code, making it possible
	# to manage multiple heaps - even recursively.
	# NOTE: value 1 only partially tested - has some problems.

.include "lib/ll.s"
.include "lib/handles.s"



.macro CHECK_MEM_STRUCT_POINTER
	.if MEM_FEATURE_STRUCT
	push	eax
	mov	eax, [mem_kernel]
	lea	eax, [eax + mem_handles]	# adds 0
	cmp	esi, eax
	jz	9900f
	printc 12, "check_handle_struct_pointer"
	DEBUG_DWORD esi
	DEBUG_DWORD eax
	int 3
9900:
	pop	eax

	.else

	cmp	esi, offset mem_handles
	jz	9900f
	printc 12, "check_handle_struct_pointer"
	DEBUG_DWORD esi
	DEBUG_DWORD (offset mem_handles)
	int 3
9900:
	.endif
.endm

.data
mem_phys_total:	.long 0, 0	# total physical memory size XXX

.if MEM_FEATURE_STRUCT
.struct
.else
.data
.endif

# handles struct (from mem_handle.s)
mem_handles: .long 0
mem_handles_method_alloc: .long 0 # MEM_FEATURE_STRUCT: Check XXX init only!
mem_numhandles: .long 0
mem_maxhandles: .long 0
mem_handles_handle: .long 0	# unused (leave here! mem_handle struct!)
# substructs: pairs of _first and _last need to be in this order!
# free-by-address
mem_handle_ll_fa:
.if MEM_FEATURE_STRUCT
.long 0,0
.else
.long -1#handle_fa_first: .long -1	# offset into [mem_handles]
.long -1#handle_fa_last: .long -1	# offset into [mem_handles]
.endif
# free-by-size
mem_handle_ll_fs:
.if MEM_FEATURE_STRUCT
.long 0,0
.else
.long -1#handle_fs_first: .long -1	# offset into [mem_handles]
.long -1#handle_fs_last: .long -1	# offset into [mem_handles]
.endif
# free handles
mem_handle_ll_fh:
.if MEM_FEATURE_STRUCT
.long 0,0
.else
.long -1#handle_fh_first: .long -1
.long -1#handle_fh_last: .long -1	# not really used...
.endif


# extension of handles struct
# (so we can keep same addr for malloc_internal and handle_get/handles_alloc
mem_heap_start:	.long 0, 0
mem_heap_size:	.long 0, 0	# MEM_FEATURE_STRUCT: XXX malloc_page_phys

mem_heap_alloc_start: .long 0

mem_heap_high_end_phys:	.long 0, 0
mem_heap_high_start_phys:.long 0, 0



.if MEM_FEATURE_STRUCT
MEM_STRUCT_SIZE = .
.data
mem_kernel: .long 1f	# initialize bootstrap memory structure pointer
# allocate bootstrap memory structure
mem_kernel_handles_struct$:	# debug symbol
1:	.space HANDLES_STRUCT_SIZE - 6*4;
.if 0
	.rept 6; .long -1; .endr
.else	# debug syms:
_mem_k_h_fa$: .long -1,-1
_mem_k_h_fs$: .long -1,-1
_mem_k_h_fh$: .long -1,-1
.endif


	.space MEM_STRUCT_SIZE - HANDLES_STRUCT_SIZE
.endif

.text32

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
.if MEM_FEATURE_STRUCT
	mov	eax, [mem_kernel]
.else
	xor	eax, eax
.endif
	mov	[eax + mem_handles_method_alloc], dword ptr offset handles_alloc$


	PRINT " Start           | Size             | Type"

	# ecx:ebx = size, edi=index (for max cmp)
	xor	ebx, ebx
	xor	ecx, ecx
	xor	edi, edi

	mov	esi, offset memory_map
0:	call	newline
	cmp	dword ptr [esi + 16 ], 0 # memory_map_attributes], 0
	jz	0f

	mov	edx, [esi + 4 ] #memory_map_base + 4 ]
mov eax, edx
	call	printhex8
	mov	edx, [esi + 0 ] #memory_map_base + 0 ]
	call	printhex8
	PRINT	" | "

	# summation over available memory:

	# addressable memory:
	cmp	dword ptr [esi + 20], 0	# check ACPI
	jz	1f
	.data SECTION_DATA_BSS
	mem_addr_total: .long 0, 0
	.text32
	push	edx
	mov	edx, [esi + 8]
	add	[mem_addr_total], edx
	mov	edx, [esi + 8+4]
	adc	[mem_addr_total+4], edx
	pop	edx
1:

	# non-BIOS/memory mapped memory.
	cmp	byte ptr [esi + 16], 2 # don't count BIOS/mapped memory
	jz	1f
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

	PRINT	" | "
	mov	edx, [esi + 20]
	call	printhex8
	mov	al, [esi + 16]
	call	printspace
	call	memory_map_print_type$

	add	esi, 24 # memory_map_struct_size
	jmp	0b
0:
	print "Total physical memory: "
	mov	edx, [mem_phys_total + 4]
	mov	eax, [mem_phys_total + 0]
	call	print_size
	print " Total addressable memory: "
	mov	eax, [mem_addr_total]
	mov	edx, [mem_addr_total + 4]
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

	mov	esi, edi
.if MEM_FEATURE_STRUCT
	mov	edi, [mem_kernel]
	lea	edi, [edi + mem_heap_start]
.else
	mov	edi, offset mem_heap_start
.endif
	movsd
	movsd
	movsd
	movsd

	call	printspace
	mov	eax, edx
	xor	edx, edx
	call	print_size
	call	newline

	# > 4Gb check

.if MEM_FEATURE_STRUCT
	mov	ebx, [mem_kernel]
	cmp	dword ptr [ebx + mem_heap_start + 4], 0
	#cmp	dword ptr [edi - 16 + 4], 0
.else
	xor	ebx, ebx	# just in case
	cmp	dword ptr [mem_heap_start + 4], 0
.endif
	jz	0f
	printlnc 4, "ERROR - Memory offset beyond 4Gb limit"
	jmp	halt
0:
.if MEM_FEATURE_STRUCT
	cmp	dword ptr [ebx + mem_heap_size + 4], 0
.else
	cmp	dword ptr [mem_heap_size + 4], 0
.endif
	jz	0f
	printlnc 4, "WARNING - Truncating available memory to 4Gb"
.if MEM_FEATURE_STRUCT
	lea	edi, [ebx + mem_heap_size]
.else
	mov	edi, offset mem_heap_size
.endif
	mov	eax, -1
	stosd
	inc	eax
	stosd

0:


	# Adjust base relative to selectors

	GDT_GET_BASE ebx, ds

	# Adjust the heap start

	print "Adjust heap base "
.if MEM_FEATURE_STRUCT
	mov	eax, [mem_kernel]
.else
	xor	eax, eax
.endif
	mov	edx, [eax + mem_heap_start]
	call	printhex8
	print "->"
	sub	[eax + mem_heap_start], ebx
	mov	edx, [eax + mem_heap_start]
	mov	[eax + mem_heap_alloc_start], edx
	call	printhex8

	print " end "
	mov	edx, [eax + mem_heap_size]
	add	edx, [eax + mem_heap_start]
	call	printhex8
	print "->"
	sub	edx, ebx
	and	edx, ~4095	# page-align
	call	printhex8
	call	newline

# XXX
	mov	[eax + mem_heap_high_end_phys], edx
	mov	[eax + mem_heap_high_start_phys], edx
	ret

#############################################################################
# Memory map management

memory_map_print:
	push_	eax edx esi ecx
	PRINT " Start           | Size             | Type"

	# ecx:ebx = size, edi=index (for max cmp)
	mov	esi, offset memory_map
	mov	ecx, RM_MEMORY_MAP_MAX_SIZE
0:	call	newline
	cmp	dword ptr [esi + 16 ], 0 # memory_map_attributes], 0
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

	mov	edx, [esi + 16 ] # memory_map_region_type ]
	call	printhex8
	PRINT	" | "
	mov	edx, [esi + 20 ]
	call	printhex8
######## print type
	call	printspace
	mov	al, [esi + 16]	# type
	call	memory_map_print_type$
#######
	add	esi, 24 # memory_map_struct_size
	loop	0b
0:	pop_	ecx esi edx eax
	ret

memory_map_print_type$:
	LOAD_TXT "free", edx	# 1
	dec	al
	jz	1f
	LOAD_TXT "bios", edx	# 2
	dec	al
	jz	1f

	LOAD_TXT "kernel", edx	# 0x10
	sub	al, MEMORY_MAP_TYPE_KERNEL - 2
	jz	1f
	js	2f

	LOAD_TXT "stack", edx	# 0x11
	dec	al
	jz	1f

	LOAD_TXT "reloc", edx	# 0x12
	dec	al
	jz	1f
	LOAD_TXT "symtab", edx	# 0x13
	dec	al
	jz	1f
	LOAD_TXT "srctab", edx	# 0x14
	dec	al
	jz	1f
	print "?"
	jmp	2f

1:	pushcolor 15
	push	edx
	call	_s_print
	popcolor
2:	ret
#

# in: edi = memory type to set
# in: edx = start of mem region
# in: ebx = region size
memory_map_update_region:
	# update the memory map so malloc won't use that area
	pushad
	mov	esi, offset memory_map
	mov	ecx, RM_MEMORY_MAP_MAX_SIZE
	# find the entry that has higher address:
0:	cmp	dword ptr [esi + 4], 0	# check high addr 0 (we do 32 bit)
	jnz	1f		# somehow missed injection pt, continue
	cmp	dword ptr [esi + 16], 0	# region type
	jz	2f	# end of list: append
	cmp	edx, [esi]	# check start address
	je	3f	# insert
	jb	4f	#in range of prev entry - not implemented: append.
1:	add	esi, 24
	loop	0b
	printc 4, "memory_map_update: no match"

0:	popad
	ret

# reached end of list: append
2:	call	memory_map_store$
	jmp	0b

# edx=[esi]: insert (since memory map is contiguous, current entry is updated/split)
3:	cmp	[esi + 8], ebx		# check if the size happens to match
	jnz	1f
# identical
	mov	[esi + 16], edi		# set type
	jmp	0b
# insert
1:	add	esi, 24
	dec	ecx
	call	memory_map_insert$	# copy entry
	mov	[esi - 24 + 8], ebx	# set size
	mov	[esi - 24 + 16], edi	# set type
	add	[esi + 0], ebx		# adjust start
	sub	[esi + 8], ebx		# adjust size
	jmp	0b

# after start of prev entry
4:	# check if prev entry can hold the range
	mov	eax, [esi + 0]		# current entry start
	sub	eax, ebx		# subtract size from cur entry start
	cmp	eax, [esi - 24]		# see if offset after prev entry still
	jb	2b	# nah, the entry is flawed - just append it

	call	memory_map_insert$	# dup and insert current row
	mov	eax, edx	
	sub	eax, [esi - 24]		# eax = curstart - prevstart = prev size
	mov	[esi -24 + 8], eax	# adjust size of prev entry
	add	[esi], eax		# adjust start of current entry
	sub	[esi + 8], eax		# adjust size of current entry

	# now split the current entry to store the section.
	add	esi, 24
	dec	ecx
	call	memory_map_insert$
	# the current entry is the one we needed to store; addr=ok
	mov	[esi - 24 + 8], ebx	# set size
	mov	[esi - 24 + 16], edi	# set type
	sub	[esi + 8], ebx		# subtract next entry size
	add	[esi + 0], ebx		# add next entry start
	jmp	0b

# in: edx = start
# in: ebx = size
# in: edi = type
memory_map_store$:
	mov	[esi + 0], edx		# mem start
	mov	[esi + 4], dword ptr 0
	mov	[esi + 8], ebx
	mov	[esi + 12], dword ptr 0
	mov	[esi + 16], edi	# mem type
	ret
	

# shifts all entries back, producing a duplicate of the current entry.
# in: edx = start
# in: ebx = size
# in: edi = type
# in: ecx = entries after cur ptr - RM_..MAX_SIZE - current index
memory_map_insert$:
	push	ecx
	cmp	ecx, 1
	jl	9f
	jz	0f
	push_	edi esi
	imul	ecx, ecx, 6	# each entry is 6 dwords (leaves edx alone..?)
	lea	edi, [memory_map_end - 4]
	lea	esi, [edi - 24]
	std
	rep	movsd	# make some space	# NOTE: werd
	cld

	pop_	esi edi
0:	pop	ecx
	ret

9:	printlnc 4, "memory_map_insert$: table exhausted"
	stc
	jmp	0b

###############################################################

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
.if MEM_FEATURE_STRUCT
		mov	edx, [mem_kernel]
		mov	edx, [edx + mem_numhandles]
.else
		mov	edx, [mem_numhandles]
.endif
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
.if MEM_FEATURE_STRUCT
		push	eax
		mov	eax, [mem_kernel]
		add	ebx, [eax + mem_handles]
		pop	eax
.else
		add	ebx, [mem_handles]
.endif
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

.if MEM_FEATURE_STRUCT
	mov	ecx, [mem_kernel]
.else
	xor	ecx, ecx
.endif
	mov	esi, [ecx + mem_handles]
	mov	ebx, [ecx + mem_handle_ll_fa + ll_last]
	mov	ecx, [ecx + mem_numhandles]
0:	test	byte ptr [esi + ebx + handle_flags], MEM_FLAG_HANDLE # 1 << 7
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
.if MEM_FEATURE_STRUCT
# in: esi = memory base structure pointer
.endif
malloc_internal_aligned$:	# can only be called from malloc_aligned!
	CHECK_MEM_STRUCT_POINTER
	# calculate worst case scenario for required contiguous memory
	push	edx
	push	eax
	add	eax, edx	# worst case
.if MEM_FEATURE_STRUCT
	mov	edx, [esi + mem_heap_alloc_start]
	add	edx, [esi + mem_heap_size]
	sub	edx, [esi + mem_heap_start]
.else
	mov	edx, [mem_heap_alloc_start]
	add	edx, [mem_heap_size]
	sub	edx, [mem_heap_start]
.endif
	cmp	eax, edx
	pop	eax
	jae	9f	# note: only edx on stack!

	mov	edx, [esp]	# restore edx (pop/push)


	# calculate the required slack for the alignment
	push_	ebx ecx edi
	GDT_GET_BASE ecx, ds
.if MEM_FEATURE_STRUCT
	mov	edi, [esi + mem_heap_alloc_start]
.else
	mov	edi, [mem_heap_alloc_start]
.endif
	sub	edi, ecx	# physical address (with id paging)
	dec	edx
	add	edi, edx
	not	edx
	and	edi, edx
	add	edi, ecx	# edi now ds el phys aligned
	push_	esi eax		# STACKREF esi
	mov	eax, edi
.if MEM_FEATURE_STRUCT
	sub	eax, [esi + mem_heap_alloc_start]# eax = slack size
.else
	sub	eax, [mem_heap_alloc_start]	# eax = slack size
.endif
	jz	1f

	# register the slack as free space

.if MEM_FEATURE_STRUCT
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handle_get	# in: esi; out: ebx
	jc	4f
	mov	esi, [esi + handles_ptr] # [mem_handles]

	mov	[esi + ebx + handle_size], eax
	and	byte ptr [esi + ebx + handle_flags], ~MEM_FLAG_ALLOCATED
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SLACK

.if MEM_FEATURE_STRUCT
	push	edi
	mov	edi, [esp + 8]	# ref pushed esi
	push	dword ptr [edi + mem_heap_alloc_start]
	add	[edi + mem_heap_alloc_start], eax
	pop	dword ptr [esi + ebx + handle_base]
	pop	edi
.else
	push	dword ptr [mem_heap_alloc_start]
	add	[mem_heap_alloc_start], eax
	pop	dword ptr [esi + ebx + handle_base]
.endif

	# insert the handle in the FS list.
	push	edi
.if MEM_FEATURE_STRUCT
	mov	edi, [esp + 8]
	lea	edi, [edi + mem_handle_ll_fa]
.else
	mov	edi, offset mem_handle_ll_fa
.endif
	add	esi, offset handle_ll_el_addr
	call	ll_append$
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
.if MEM_FEATURE_STRUCT
	mov	ecx, [esp + 8]
	lea	edi, [ecx + mem_handle_ll_fs]
	mov	ecx, [ecx + mem_maxhandles]
.else
	mov	edi, offset mem_handle_ll_fs
	mov	ecx, [mem_maxhandles]
.endif
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
.if MEM_FEATURE_STRUCT
# in: esi = MEM_STRUCT
.endif
# out: base address of allocated memory
malloc_internal$:
	.if MEM_FEATURE_STRUCT
	CHECK_MEM_STRUCT_POINTER
	.endif
	.if MEM_DEBUG > 1
		push	edx
		pushcolor 10
		mov	edx, eax
		call	printhex8	# alloc size
		printchar ' '
.if MEM_FEATURE_STRUCT
		mov	edx, [esi + mem_heap_alloc_start]# base
.else
		mov	edx, [mem_heap_alloc_start]	# base
.endif
		call	printhex8
		printchar ' '
	.endif

	push	edx
.if MEM_FEATURE_STRUCT
	mov	edx, [esi + mem_heap_alloc_start]
	add	edx, [esi + mem_heap_size]
	sub	edx, [esi + mem_heap_start]
.else
	mov	edx, [mem_heap_alloc_start]
	add	edx, [mem_heap_size]
	sub	edx, [mem_heap_start]
.endif
	cmp	eax, edx
	jae	9f

.if MEM_FEATURE_STRUCT
	push	dword ptr [esi + mem_heap_alloc_start]
	add	[esi + mem_heap_alloc_start], eax
.else
	push	dword ptr [mem_heap_alloc_start]
	add	[mem_heap_alloc_start], eax
.endif
	pop	eax

	.if MEM_DEBUG > 1
.if MEM_FEATURE_STRUCT
		mov	edx, [esi + mem_heap_alloc_start]# new free
.else
		mov	edx, [mem_heap_alloc_start]	# new free
.endif
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
# Get total heap size
# out: edx:eax
.global mem_get_heap
mem_get_heap:
.if MEM_FEATURE_STRUCT
	push	ebx
	mov	ebx, [mem_kernel]
	mov	edx, [ebx + mem_heap_size + 4]
	mov	eax, [ebx + mem_heap_size + 0]
	pop	ebx
.else
	mov	edx, [mem_heap_size + 4]
	mov	eax, [mem_heap_size + 0]
.endif
	ret

# sums all allocated handles.
# out: edx:eax
.global mem_get_used
mem_get_used:
	push	ebx
.if MEM_FEATURE_STRUCT
	mov	edx, [mem_kernel]
	mov	ebx, [edx + mem_handles]
	mov	edx, [edx + mem_handle_ll_fa + ll_first]
.else
	mov	ebx, [mem_handles]
	mov	edx, [mem_handle_ll_fa + ll_first]
.endif
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

.global mem_get_reserved
mem_get_reserved:
.if MEM_FEATURE_STRUCT
	mov	edx, [mem_kernel]
	mov	eax, [edx + mem_heap_alloc_start]
	sub	eax, [edx + mem_heap_start]
.else
	mov	eax, [mem_heap_alloc_start]
	sub	eax, [mem_heap_start]
.endif
	xor	edx, edx
	ret

.global mem_get_free
mem_get_free:
.if MEM_FEATURE_STRUCT
	mov	edx, [mem_kernel]
	mov	eax, [edx + mem_heap_size]
	add	eax, [edx + mem_heap_start]
	sub	eax, [edx + mem_heap_alloc_start]
.else
	mov	eax, [mem_heap_size]
	add	eax, [mem_heap_start]
	sub	eax, [mem_heap_alloc_start]
.endif
	xor	edx, edx
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
	.if MEM_DEBUG2 > 1
		DEBUG "mallocz ";
		push edx; mov edx,[esp+4]; call debug_printsymbol; pop edx
	.endif
	push	ecx
	mov	ecx, eax
	call	malloc_
_mallocz_malloc_ret$:	# debug symbol
	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax,"malloc";DEBUG_DWORD ecx; pushf; call newline; popf
	.endif
	jc	9f
	push	edi
	mov	edi, eax
	push	eax
	xor	eax, eax
	push	ecx
	and	ecx, 3
	rep	stosb
	pop	ecx
push ecx
	shr	ecx, 2
	rep	stosd
pop ecx
	pop	eax
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
	TIMING_BEGIN
	MUTEX_SPINLOCK MEM
	push_	ebx esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handle_find_aligned
	jnc	1f	# : mov eax, base; clc; ret
	call	handle_get	# in: esi; out: ebx
	jc	4f	# error: no more handles

	push	esi
	mov	esi, [esi + handles_ptr] # [mem_handles]

	mov	[esi + ebx + handle_size], eax
	# register caller
	push	edx
	mov	edx, [ebp]#[esp + 3*4]	# edx+esi+ebx+ret
	mov	[esi + ebx + handle_caller], edx
	pop	edx

	xchg	esi, [esp]
	call	malloc_internal_aligned$
	pop	esi
	jnc	3f
	DEBUG "malloc_internal_aligned error"
	jmp	3f
# KEEP-WITH-NEXT malloc_ 1f, 3f, 4f

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
	TIMING_BEGIN
#DEBUG_REGSTORE
	MUTEX_SPINLOCK MEM

	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax,"malloc("
	.endif
	.if MEM_DEBUG2
		call mem_validate_handles
	.endif

#call mem_debug
	push_	ebx esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	TIMING_BEGIN
	call	handle_find	# in: esi; out: ebx
	TIMING_END "malloc_ handle_find"
	jc	2f
1:	# malloc_aligned jumps here
	mov	esi, [esi + handles_ptr]
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

2:
	TIMING_BEGIN
	call	handle_get	# in: esi; out: ebx
	TIMING_END "malloc_ handle_get"
	jc	4f
	mov	esi, [esi + handles_ptr] # [mem_handles]

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

		TIMING_BEGIN
	mov	[esi + ebx + handle_size], eax
.if MEM_FEATURE_STRUCT
	push	esi
	mov	esi, [mem_kernel]
	call	malloc_internal$
	pop	esi
.else
	call	malloc_internal$
.endif
		TIMING_END "malloc_ malloc_internal"
3:	jc	3f	# malloc_aligned jumps here
	.if MEM_DEBUG
		push	edx
		print " base: "
		mov	edx, eax
		call	printhex8
		pop	edx
	.endif

	mov	[esi + ebx + handle_base], eax

	push	edi
	push	ecx
.if MEM_FEATURE_STRUCT
	mov	edi, [mem_kernel]
	mov	ecx, [edi + mem_maxhandles]
	lea	edi, [edi + mem_handle_ll_fa]
.else
	mov	ecx, [mem_maxhandles]
	mov	edi, offset mem_handle_ll_fa
.endif
	add	esi, offset handle_ll_el_addr
		TIMING_BEGIN
	call	ll_insert_sorted$
		TIMING_END "malloc_ ll_insert_sorted"
	pop	ecx
	sub	esi, offset handle_ll_el_addr
	pop	edi

	# register caller
0:	add	esi, ebx
	mov	ebx, [ebp]
	mov	[esi + handle_caller], ebx

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
	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax,")"
	.endif
	.if MEM_DEBUG2
		call mem_validate_handles
	.endif
	MUTEX_UNLOCK MEM

#DEBUG_REGDIFF
	TIMING_END "malloc_"
	ret	# WEIRD BUG: 0x001008f0 on stack (called from mdup@net.s:685)


4:	printlnc 4, "malloc: no more handles"	# malloc_aligned jumps here
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
 	push	ebx
	push	ecx
	push	esi
	push	edi

	MUTEX_SPINLOCK MEM
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handle_get_by_base	# in: esi, eax; out: ebx
	jc	0f

	mov	esi, [esi + handles_ptr]
	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f

0:	printc 4, "mrealloc: unknown pointer "
	push	eax
	call	_s_printhex8
	call	newline
	stc
	STACKTRACE ebp, 0

	jmp	0f	# does unlock
1:
########
	# Check if the call is for growth
	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, edx	# ecx = cursize - newsize
	jns	2f	# shrink
	jz	0f	# no change.

	neg	ecx
	.if MEM_DEBUG2 > 1
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
	.if MEM_DEBUG2 > 1
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
	.if MEM_DEBUG2 > 1
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
	.if MEM_DEBUG2 > 1
		DEBUG "M",0x6f
	.endif

	# edi is unallocated handle, and thus it is part of the lists:
	# handle_fa - to maintain address order
	# handle_fs - free-by-size
	# Clear them both out.
	mov	ebx, edi
	add	esi, offset handle_ll_el_size
.if MEM_FEATURE_STRUCT
	mov	ecx, [mem_kernel]	# ecx not used in ll_unlink
	lea	edi, [ecx + mem_handle_ll_fs]
.else
	mov	edi, offset mem_handle_ll_fs
.endif
	call	ll_unlink$
.if MEM_FEATURE_STRUCT
	lea	edi, [ecx + mem_handle_ll_fa]
.else
	mov	edi, offset mem_handle_ll_fa
.endif
	add	esi, offset handle_ll_el_addr - offset handle_ll_el_size
	call	ll_unlink$
.if MEM_FEATURE_STRUCT
	lea	edi, [ecx + mem_handle_ll_fh]
	mov	ecx, [ecx + mem_maxhandles]
.else
	mov	edi, offset mem_handle_ll_fh
	mov	ecx, [mem_maxhandles]
.endif
	call	ll_insert_sorted$

	# eax is unchanged

	jmp	0f

####### allocate a new block and copy the data.
1:
	.if MEM_DEBUG2 > 1
		DEBUG "C",0x6f
	.endif
	mov	ecx, [esi + ebx + handle_size]
	push	esi
	mov	esi, eax

	mov	eax, edx
	MUTEX_UNLOCK MEM
	call	\malloc\()_
	MUTEX_SPINLOCK MEM
	# copy
	or	ecx, ecx	# shouldnt happen if malloc checks for it.
	jz	1f
	mov	edi, eax
	rep	movsb
1:	pop	esi
	or	[ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED

	# free the old handle
	.if MEM_DEBUG2 > 1
		DEBUG "<", 0x6f
	.endif
	.if MEM_DEBUG2
		call mem_validate_handles;
	.endif

	MUTEX_UNLOCK MEM
	push	eax
	mov	eax, [esi + ebx + handle_base]
	.if MEM_DEBUG2 > 1
		DEBUG ".", 0x6f
	.endif
	call	mfree	# TODO: optimize, as handle is known
	pop	eax

	jmp	1f

########
2:	# shrink: ignore.
	.if MEM_DEBUG2 > 1
		DEBUG "-", 0x6f
	.endif
########

0:	MUTEX_UNLOCK MEM
1:	pop	edi
	pop	esi
	pop	ecx
	pop	ebx
	.if MEM_DEBUG2
		call mem_validate_handles
	.endif
	.if MEM_DEBUG2 > 1
		DEBUG "]", 0x6f
	.endif
	pop	ebp
.endm


# in: eax = mem, edx = new size
# out: eax = reallocated (memcpy) mem
mrealloc:
	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax,"mrealloc";DEBUG_DWORD edx
	.endif
	MREALLOC malloc
	.if MEM_DEBUG2 > 1
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
	push	ebx
.if MEM_FEATURE_STRUCT
	mov	ebx, [mem_kernel]
.else
	xor	ebx, ebx
.endif
	push	edi
	push	esi
	push	ecx
	push	edx
	####################
	push	eax
		#DEBUG "mreallocz", 0xe0
		#DEBUG_DWORD edx, "new size", 0xe0
	xchg	eax, edx	# eax=new size; edx=old ptr
	call	mallocz_
	jc	9f
#	DEBUG "mreallocz";DEBUG_DWORD esi;DEBUG_DWORD edi;DEBUG_DWORD edx
# XXX get old size: copied from mfree_; TODO: refactor;
	MUTEX_SPINLOCK MEM
		mov	ecx, [ebx + mem_numhandles]
		jecxz	1f
		mov	esi, [ebx + mem_handles]
		#mov	esi, [esi + handles_ptr]
		mov	edi, [ebx + mem_handle_ll_fa + ll_last]
	0:	cmp	edi, -1
		jz	1f
		cmp	edx, [esi + edi + handle_base]
		jz	2f
		mov	edi, [esi + edi + handle_fa_prev]
		loop	0b
	1:	# not found
		DEBUG "WARN: mfree cannot find old size", 0xf4
		int 3
		# legacy: use new size.
		mov	edx, [esp + 4]	# restore edx = new size
		jmp	3f

	2:	mov	edx, [esi + edi + handle_size]
		mov	esi, [esp + 4]	# less memory references
		cmp	edx, esi	# old size <> new size
		jb	3f		# old size < new size
		mov	edx, esi
	3:
	MUTEX_UNLOCK MEM

	mov	esi, [esp]
	mov	edi, eax

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
0:	pop	edx
	pop	ecx
	pop	esi
	pop	edi
	pop	ebx
	ret
9:	pop	eax
	jmp	0b
.else
	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax,"mrealloc";DEBUG_DWORD edx
	.endif
	MREALLOC mallocz
	.if MEM_DEBUG2 > 1
		DEBUG_DWORD eax
	.endif
	ret
.endif

# in: eax = memory pointer
mfree:
	push	ebp
	lea	ebp, [esp + 4]
	call	mfree_
	pop	ebp
	ret

mfree_:
	TIMING_BEGIN
	MUTEX_SPINLOCK MEM
	.if MEM_DEBUG2 > 1
		DEBUG "["
		DEBUG_DWORD eax,"mfree"
	.endif
	.if MEM_DEBUG2
		call mem_validate_handles
	.endif
	.if MEM_DEBUG2 > 1
		DEBUG ","
	.endif
	push	esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handle_free_by_base
	pop	esi
        .if MEM_DEBUG2 
		call mem_validate_handles
	.endif
        .if MEM_DEBUG2 > 1
                DEBUG "]"
        .endif
	MUTEX_UNLOCK MEM
	TIMING_END "mfree_"
	STACKTRACE ebp
	ret


###########################################################################

mem_debug:
	.if MEM_DEBUG
	push	ebx
	push	ecx
	push	edx
	push	esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
.else
	xor	esi, esi
.endif
	print "[malloc "
	mov	edx, eax
	call	printhex8
	print " heap "
	mov	edx, [esi + mem_heap_start]
	mov	ecx, edx
	call	printhex8
	printchar '-'
	mov	ebx, [esi + mem_heap_size]
	add	edx, ebx
	call	printhex8
	print " size "
	mov	edx, ebx
	call	printhex8
	print " start "
	mov	edx, [esi + mem_heap_alloc_start]
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
mem_print_handles:
	push	esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handles_print
	pop	esi
	ret

##############################################################################
# Commandline utility
CMD_MEM_OPT_HANDLES	= 1 << 0
CMD_MEM_OPT_KERNELSIZES	= 1 << 1	# kernel pm/rm code,data,symbols,stack
CMD_MEM_OPT_ADDRESSES	= 1 << 2	# start/end addresses of kernelsizes
CMD_MEM_OPT_KERNEL_MEMMAP=1 << 3	# verbose memory map of all sections
CMD_MEM_OPT_CODESIZES	= 1 << 8	# verbose subsystem code sizes
CMD_MEM_OPT_HANDLES_A	= 1 << 9
CMD_MEM_OPT_HANDLES_S	= 1 << 10
CMD_MEM_OPT_MEMORY_MAP	= 1 << 11
CMD_MEM_OPT_GRAPH	= 1 << 16	# experimental

cmd_mem$:
	push	ebp
	push	dword ptr 0	# allocate a flag to mark the options
	mov	ebp, esp
.if MEM_FEATURE_STRUCT
	mov	edi, [mem_kernel]
.else
	xor	edi, edi
.endif

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
	or	dword ptr [ebp], CMD_MEM_OPT_KERNEL_MEMMAP # print sections/memory map
	jmp	2f
1:	cmp	eax, '-' | ('c'<<8)	# print verbose
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_CODESIZES
	jmp	2f
1:	cmp	eax, '-' | ('m'<<8)	# print memory_map
	jnz	1f
	or	dword ptr [ebp], CMD_MEM_OPT_MEMORY_MAP
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
	mov	eax, [edi + mem_heap_size]
	xor	edx, edx
	call	print_size

	printc 15, " Reserved: "
	mov	eax, [edi + mem_heap_alloc_start]
	sub	eax, [edi + mem_heap_start]
	call	print_size

	push	eax
	printc 15, " Allocated: "
	call	mem_get_used
	call	print_size
	pop	eax

	printc 15, " Free: "
	sub	eax, [edi + mem_heap_size]
	neg	eax
	call	print_size

	mov	ecx, ds
	mov	edx, [edi + mem_heap_start]
	mov	eax, [edi + mem_heap_size]
	add	eax, edx
	call	cmd_mem_print_addr_range$
	call	newline

	# print paging info
	printc 15, "Paging: "
	mov	eax, [edi + mem_heap_high_end_phys]
	sub	eax, [edi + mem_heap_high_start_phys]
	xor	edx, edx
	call	print_size
	shr	eax, 12
	mov	edx, eax
	print " ("
	push	edx
	# calculate nr of free pages
	LOCK_READ [mem_pages_sem]
	mov	esi, [mem_pages_free]
	mov	ecx, [esi + array_index]
	xor	edx, edx
	shr	ecx, 2
	jz	2f
0:	lodsd

	push	ecx
	mov	ecx, 32
1:	shr	eax, 1
	adc	edx, 0
	loop	1b
	pop	ecx

	loop	0b
2:	UNLOCK_READ [mem_pages_sem]

	neg	edx
	add	edx, [esp]
	call	printdec32
	printchar '/'
	pop	edx
	call	printdec32
	print " pages)"

	mov	ecx, ds
	mov	edx, [edi + mem_heap_high_start_phys]
	mov	eax, [edi + mem_heap_high_end_phys]
	call	cmd_mem_print_addr_range$
	call	newline

	.if MALLOC_PAGE_DEBUG
		call	page_phys_print_free$
		call	priv_stack_print$
	.endif

######## print kernel sizes
1:	test	dword ptr [ebp], CMD_MEM_OPT_KERNELSIZES
	jz	1f

	printc 15, "Kernel: "
	xor	edx, edx
	# reloc: DISP32 .data
	#mov	eax, kernel_end - kernel_code_start # realmode_kernel_entry
	mov	eax, offset KERNEL_SIZE
	#(kernel_code_end - kernel_code_start)+(kernel_data_end-kernel_data_start)
	call	print_size

	mov	edx, offset realmode_kernel_entry
	mov	eax, [kernel_stack_top]
	mov	ecx, cs
	call	cmd_mem_print_addr_range$
	call	newline

	printc 15, " Code: "
	mov	eax, offset KERNEL_CODE_SIZE
	xor	edx, edx
	call	print_size
	printc 15, " (realmode: "
	mov	eax, offset KERNEL_CODE16_SIZE #kernel_rm_code_end - kernel_rm_code_start
	call	print_size
	printc 15, " pmode: "
	mov	eax, offset KERNEL_CODE32_SIZE #kernel_pm_code_end - kernel_pm_code_start
	call	print_size
	printc 15, ")"

	mov	ecx, cs
	mov	edx, offset realmode_kernel_entry
	mov	eax, offset kernel_code_end
	call	cmd_mem_print_addr_range$
	call	newline

	printc 15, " Data: "
	xor	edx, edx
	mov	eax, offset KERNEL_DATA_SIZE
	call	print_size
	printc 15, " (rm: "
	mov	eax, data16_end - data16_start
	call	print_size

	mov	ecx, cs
	mov	edx, KERNEL_DATA16_START
	mov	eax, KERNEL_DATA16_END
	call	cmd_mem_print_addr_range$
	xor	edx, edx

	printc 15, " 0: "
	mov	eax, data_0_end - kernel_data_start
	call	print_size
	printc 15, " str: "
	mov	eax, data_str_end - data_str_start	# local syms
	add	eax, offset data_ring2_strings_end	# extern syms
	sub	eax, offset data_ring2_strings_start
	call	print_size
	printc 15, " bss: "
	mov	eax, data_bss_end - data_bss_start
	add	eax, offset data_ring2_bss_end
	sub	eax, offset data_ring2_bss_start
	call	print_size
.if 0
	mov	eax, kernel_end - data_bss_end
	or	eax, eax
	jz	2f
	printc 12, " 99: "
	call	print_size
2:	
.endif
	printc 15, ")"

	mov	ecx, cs
	mov	edx, offset kernel_data_start
	mov	eax, offset data_bss_end
	call	cmd_mem_print_addr_range$
	call	newline

	xor	edx, edx
	mov	eax, [kernel_reloc_size]
	or	eax, eax
	jz	2f
	printc 15, " Relocation tables: "
	call	print_size
	mov	edx, [reloc_load_start_flat]
	mov	eax, [reloc_load_end_flat]
	mov	ecx, SEL_flatDS
	call	cmd_mem_print_addr_range$

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
	# get pid0 stack
	xor	eax, eax
	push_	ebx ecx
	call	task_get_by_pid	# out: ebx + ecx
	lea	edx, [ebx + ecx]
	pop_	ecx ebx
	mov	eax, [kernel_stack_top]
	sub	eax, [edx + task_regs + task_reg_esp]
	xor	edx, edx
	call	print_size
	PRINTC 8, "/"
	mov	eax, [kernel_stack_top]
	sub	eax, [kernel_stack_bottom]	# offset kernel_end
	call	print_size
#	mov	ecx, ss
	mov	edx, [kernel_stack_bottom] # offset kernel_end
	mov	eax, [kernel_stack_top]
	call	cmd_mem_print_addr_range$
	call	newline

######## print handles
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES
	jz	1f
	call	mem_print_handles
	jmp	2f
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES_A
	jz	1f
.if MEM_FEATURE_STRUCT
	lea	esi, [edi + mem_handles]
	lea	ebx, [edi + mem_handle_ll_fa]
	push	edi
	mov	edi, offset handle_ll_el_addr
	call	handles_print_ll
	pop	edi
.else
	lea	esi, [mem_handles]
	mov	ebx, offset mem_handle_ll_fa
	mov	edi, offset handle_ll_el_addr
	call	handles_print_ll
.endif
	jmp	2f
1:	test	dword ptr [ebp], CMD_MEM_OPT_HANDLES_S
	jz	1f
.if MEM_FEATURE_STRUCT
	lea	esi, [edi + mem_handles]
	lea	ebx, [edi + mem_handle_ll_fs]
	push	edi
	mov	edi, offset handle_ll_el_size
	call	handles_print_ll
	pop	edi
.else
	lea	esi, [mem_handles]
	mov	ebx, offset mem_handle_ll_fs
	mov	edi, offset handle_ll_el_size
	call	handles_print_ll
.endif
2:
######## print memory map
1:	test	dword ptr [ebp], CMD_MEM_OPT_KERNEL_MEMMAP
	jz	1f

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
	.macro PRINT_MEMRANGE label, st=0, nd=0, sz=0, indent="", fl=0, uc=0
		.data
		99: .ascii "\indent\label: "
		88: .space 22-(88b-99b), ' '
		.byte 0
		.text32

		# print label
		mov	ah, 15
		mov	esi, offset 99b
		call	printc

		# set up eax, edx:
		.ifnc 0,\st
			mov	edx, \st
		.else
			.if \uc
			mov	edx, offset \label\()_START
			.else
			mov	edx, offset \label\()_start
			.endif
		.endif

		.ifnc 0,\nd
			mov	eax, \nd
		.else
			.if \uc
			mov	eax, offset \label\()_END
			.else
			mov	eax, offset \label\()_end
			.endif
		.endif

		.if \sz
			add	eax, edx
		.endif
		.ifnc 0,\fl
			sub	eax, [database]
			sub	edx, [database]
		.endif

		call	print_memrange$
	.endm

	mov	ecx, [reloc$] 	# relocation; end addr of prev entry
				# can't use .text as it will use ring2 text start
	PRINT_MEMRANGE KERNEL_CODE16 uc=1#kernel_rm_code
	PRINT_MEMRANGE data16_data
	PRINT_MEMRANGE data16_str
	# align4 new section
	add	ecx, 3
	and	cl, ~3
	PRINT_MEMRANGE KERNEL_CODE32 uc=1#kernel_pm_code

	test	dword ptr [ebp], CMD_MEM_OPT_CODESIZES
	jz	2f

	mov	ecx, offset code_print_start
	printlnc 14, "RING0 code"
	.irp _, print,debug,pmode,paging,kapi,pit,keyboard,console,hash,mem,buffer,string,scheduler,tokenizer,oo,bios,cmos,dma,gfx,vmware,shell,debugger,kernel
	PRINT_MEMRANGE code_\_\(), indent="  "
	.endr

	printlnc 14, "RING2 code"
	# new object, align:
	add	cl, 3
	and	cl, ~3
	.irp _,ring2_inc,dev,pci,ata,partition,fs,fs_fat,fs_iso9660,fs_sfs,fs_oofs,nic,net,vid,usb,southbridge,vbox,sound
	PRINT_MEMRANGE code_\_\(), indent="  "
	.endr
	# new object, align:
	add	cl, 3
	and	cl, ~3
	PRINT_MEMRANGE code_oofs, indent="  "

2:	printlnc 14, "RING0 data"
	# data section: align 16
	add	ecx, 15
	and	cl, ~15
	PRINT_MEMRANGE data_0
	PRINT_MEMRANGE data_sem
	PRINT_MEMRANGE data_tls
	PRINT_MEMRANGE data_concat
	#PRINT_MEMRANGE data_concat within data0's range
	PRINT_MEMRANGE data_fonts
	PRINT_MEMRANGE data_stats
	# bss section
	PRINT_MEMRANGE data_bss
	printlnc 14, "RING2 data"
	PRINT_MEMRANGE data_ring2
	PRINT_MEMRANGE data_pci_driverinfo
	PRINT_MEMRANGE data_ring2_bss

	printlnc 14, "CORE"
	add	ecx, 4
	and	cl, ~3
	PRINT_MEMRANGE data_str
	PRINT_MEMRANGE data_ring2_strings

	# new obj, align
	add	ecx, 3
	and	cl, ~3
	PRINT_MEMRANGE data_classes
	PRINT_MEMRANGE data_kapi
	PRINT_MEMRANGE data_shell_cmds

	PRINT_MEMRANGE "signature", (offset kernel_signature), (offset kernel_signature+4)

	PRINT_MEMRANGE "stack", cs:[kernel_stack_bottom], cs:[kernel_stack_top]
	#mov	edi, [kernel_load_end_flat]
	#PRINT_MEMRANGE "<slack>", ecx, edi
	PRINT_MEMRANGE "<free>", ecx, [kernel_reloc]
	PRINT_MEMRANGE "relocation table", [kernel_reloc], [kernel_reloc_size], sz=1
	PRINT_MEMRANGE "symbol table", [kernel_symtab], [kernel_symtab_size], sz=1
	PRINT_MEMRANGE "stabs", [kernel_stabs], [kernel_stabs_size], sz=1
.if MEM_FEATURE_STRUCT
	mov	edi, [mem_kernel]
	mov	edi, [edi + mem_heap_high_start_phys]
.else
	mov	edi, [mem_heap_high_start_phys]
.endif
	sub	edi, [database]
	PRINT_MEMRANGE "<free>", ecx, edi
.if MEM_FEATURE_STRUCT
# XXX different addresssing style
	PRINT_MEMRANGE "paging", ds:[mem_kernel+4+mem_heap_high_start_phys], ds:[mem_kernel+4+mem_heap_high_end_phys],fl=1
.else
	PRINT_MEMRANGE "paging", ds:[mem_heap_high_start_phys], ds:[mem_heap_high_end_phys],fl=1
.endif

######## print memory map
1:	test	dword ptr [ebp], CMD_MEM_OPT_MEMORY_MAP
	jz	1f
	call	memory_map_print
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
	printlnc_ 12, "  -s   print kernel code/data sections/images/memory map"
	printlnc_ 12, "    -c print detailed code sections"
	printlnc_ 12, "  -m   print BIOS/ACPI memory map"
	jmp	1b


# in: ecx = end address of last section/memory range, to be compared with the
#           start of this one, for misalignment/overlap error detection.
# in: edx = start (ds-relative)
# in: eax = end (ds-relative)
# out: ecx updated
# out: (side-effect) ebx = start
# out: (side-effect) edi = end (same as ecx)
# destroys: eax, edx. (eax=range size, edx=0)
print_memrange$:
	enter	3+1+3+2+1, 0
	# print ds-relative addresses:
	call	printhex8

	mov	ebx, edx	# remember start
	mov	edi, eax	# remember end

	mov	edx, eax
	printchar '-'
	call	printhex8
	call	printspace

	sub	eax, ebx

	# a little check: ebx=start,ecx=prev end
	cmp	ebx, ecx
	mov	cl, '!'
	jnz	1f
	or	eax, eax
	js	1f
	mov	cl, ' '
1:	printcharc 12, cl

	call	printspace


	# print flat addresses:
	mov	edx, ebx	# start
	add	edx, [database]
	call	printhex8
	printchar '-'
	mov	edx, edi	# end
	add	edx, [database]
	call	printhex8
	call	printspace
	call	printspace

	# print size

	xor	edx, edx
	or	eax, eax
	jns	1f
	neg	eax
	printcharc 12, '-'
1:
	push	edi
	#mov	edi, offset mem_size_str_buf$
	lea	edi, [ebp - (3+1+3+2+1)]
	mov	bl, 1<<4 | 3
	call	sprint_size_
	mov	byte ptr [edi], 0
	pop	edi

	#mov	esi, offset mem_size_str_buf$
	lea	esi, [ebp - (3+1+3+2+1)]
	call	strlen_
	neg	ecx
	add	ecx, 3 + 1 + 3 + 2 +1
	jle	1f	# just in case
0:	call	printspace
	loop	0b
	call	print
1:
	mov	ecx, edi	# remember end for next check

	call	newline
	leave
	ret


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
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	mov	ecx, [esi + mem_numhandles]
	mov	esi, [esi + mem_handles]
.else
	mov	esi, [mem_handles]
	mov	ecx, [mem_numhandles]
.endif
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
	and	ecx, 3
	mov	edi, eax
	xor	eax, eax
	rep	stosb
	pop	ecx
	shr	ecx, 2
	rep	stosd
	pop_	eax edi

9:	pop	ecx
	ret


mem_validate_handles:
	push	esi
.if MEM_FEATURE_STRUCT
	mov	esi, [mem_kernel]
	lea	esi, [esi + mem_handles]
.else
	lea	esi, [mem_handles]
.endif
	call	handles_validate_order$
	pop	esi
	ret
############################################################
#

# See MALLOC_PAGE_DEBUG at top
.data SECTION_DATA_BSS
mem_pages_sem:		.long 0
mem_pages:		.long 0
mem_pages_free:		.long 0	# array of bit-strings (size = 1/32th of mem_pages)
.text32

# Allocate a single page
# out: eax = physical memory address
malloc_page_phys:

	.if MALLOC_PAGE_DEBUG
		DEBUG "alloc page"
	.endif

	LOCK_WRITE [mem_pages_sem]
	push_	ebx edx esi ecx
.if MEM_FEATURE_STRUCT
	push	edi
	mov	edi, [mem_kernel]
.endif
	########################
	mov	esi, [mem_pages_free]
	or	esi, esi
	jz	1f		# init [mem_pages_free]

	xor	ebx, ebx	# bit index
	mov	ecx, [esi + array_index]
	shr	ecx, 2
	# XXX a just-in case jz? So far not needed
	.if MALLOC_PAGE_DEBUG > 1
		DEBUG_DWORD ecx
	.endif
0:	lodsd
	.if MALLOC_PAGE_DEBUG > 1
		DEBUG_DWORD eax
	.endif
	bsf	edx, eax	# set edx to first bit set in eax
	jnz	2f		# found
	add	ebx, 4*32	# increment bit index (XXX?)
	loop	0b
	.if MALLOC_PAGE_DEBUG
		DEBUG "no free page"
	.endif
	jmp	1f

2:
	# edx = bit index in current (eax/[esi-4]) mem_pages_free dword
	# ebx = absolute bit index, rel to [mem_pages_free]
	.if MALLOC_PAGE_DEBUG
		DEBUG "re-use page"; DEBUG_DWORD ebx;DEBUG_DWORD edx
	.endif

	btr	dword ptr [esi - 4], edx	# mark allocated
	#jc 99f; DEBUG "ERROR: page already allocated", 0x4f; 99:
	add	ebx, [mem_pages]	# XXX!
	mov	eax, [ebx + edx * 4]
	.if MALLOC_PAGE_DEBUG
		DEBUG_DWORD eax
	.endif

	.if MALLOC_PAGE_DEBUG_PTR_BIT
	and	eax, ~1
	andb	[ebx + edx * 4], ~1
	.endif

	clc
	jmp	0f	# done

1:	########################
	# Alloc a page
	.if MALLOC_PAGE_DEBUG
		DEBUG "alloc new page"
	.endif

	mov	eax, 4096
.if MEM_FEATURE_STRUCT
	cmp	eax, [edi + mem_heap_size]
	jae	9f

	sub	[edi + mem_heap_high_start_phys], eax
	sbb	[edi + mem_heap_high_start_phys+4], dword ptr 0

	sub	[edi + mem_heap_size], eax
	sbb	[edi + mem_heap_size+4], dword ptr 0

.else
	cmp	eax, [mem_heap_size]
	jae	9f

	sub	[mem_heap_high_start_phys], eax
	sbb	[mem_heap_high_start_phys+4], dword ptr 0

	sub	[mem_heap_size], eax
	sbb	[mem_heap_size+4], dword ptr 0
.endif
	###################
	# [mem_heap_high_start_phys] = address of newly allocated page
	# register page
	PTR_ARRAY_NEWENTRY [mem_pages], 4, 9f	# initializes [mem_pages] if needed
.if MEM_FEATURE_STRUCT
	mov	ebx, [edi + mem_heap_high_start_phys]
.else
	mov	ebx, [mem_heap_high_start_phys]
.endif

	# ebx = address of newly allocated heap page
	mov	[eax + edx], ebx	# [eax+edx] == [ [mem_pages] + dword idx ]

	mov	eax, [mem_pages_free]	# pipelining

	shr	edx, 2	# convert edx to dword index
	# split index into 32-bit base + bit index
	mov	ebx, edx
	mov	ecx, edx
	shr	ebx, 5-2	# 32 bits per entry * 4
	and	ecx, 31	# bit index
	and	bl, ~3

	.if MALLOC_PAGE_DEBUG > 1
		DEBUG_DWORD edx
		DEBUG_DWORD ebx
		DEBUG_DWORD ecx
	.endif

	or	eax, eax
	jz	1f	# first-time only

	cmp	ebx, [eax + array_index]
	jb	2f

1:	PTR_ARRAY_NEWENTRY [mem_pages_free], 4, 9f	# out: eax+edx
	.if MALLOC_PAGE_DEBUG
		DEBUG "alloc mem_pages_free dword"
	.endif

	# assert ebx == edx
	cmp	ebx, edx
	jz	3f
	PRINTc 0xf4, "malloc_page_phys ASSERTION fail! ebx!=edx"
	3:
	mov	dword ptr [eax + ebx], 0 # mark allocated so wont reuse
	# we ignore edx, and calc it again
2:
	btr	[eax + ebx], ecx	# mark allocated
.if MEM_FEATURE_STRUCT
	mov	eax, [edi + mem_heap_high_start_phys]
.else
	mov	eax, [mem_heap_high_start_phys]
.endif
	clc

0:	# preserve CF!

	.if MALLOC_PAGE_DEBUG
		pushf
		call	newline;
		DEBUG "MALLOC: "
		call	page_phys_print_free$
		popf
	.endif


.if MEM_FEATURE_STRUCT
	pop	edi
.endif
	pop_	ecx esi edx ebx
	UNLOCK_WRITE [mem_pages_sem]
	ret
9:	printlnc 4, "malloc_phys_page: out of memory"
	stc
	jmp	0b

# in: eax = page(s) physical base address
mfree_page_phys:
	# assume that malloc_page_phys is called, [mem_pages(_free)] setup.
	LOCK_WRITE [mem_pages_sem]

	.if MALLOC_PAGE_DEBUG;
		DEBUG "freeing page:"; DEBUG_DWORD eax
	.endif

	push_	edi ecx
	mov	edi, [mem_pages]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd
	jnz	9f
	sub	edi, 4			# correct scasd

	.if MALLOC_PAGE_DEBUG_PTR_BIT
	orb	[edi], 1		# set lowest bit to mark free - for DEBUGGING!
	.endif

	sub	edi, [mem_pages]	# convert to relative page pointer offset
	shr	edi, 2			# convert to dword index
	.if MALLOC_PAGE_DEBUG > 1
		DEBUG_DWORD edi
	.endif
	mov	ecx, edi
	shr	edi, 5
	shl	edi, 2
	and	ecx, 31			# bit index

	.if MALLOC_PAGE_DEBUG > 1
		DEBUG_DWORD edi
		DEBUG_DWORD ecx
	.endif

	add	edi, [mem_pages_free]
	bts	[edi], ecx
	jc	91f

	.if MALLOC_PAGE_DEBUG
		call	newline;
		debug "FREE: "
		call	page_phys_print_free$
	.endif

0:	pop_	ecx edi
	UNLOCK_WRITE [mem_pages_sem]
	ret
9:	printc 4, "mfree_page_phys: unknown page: "
	push edx; mov edx, eax; call printhex8; pop edx;
	call	newline
	jmp	0b

91:	printc 4, "mfree_page_phys: error: page already free: "
	push edx; mov edx, eax; call printhex8; pop edx
	call	newline
	jmp	0b


.if MALLOC_PAGE_DEBUG
page_phys_print_free$:
	pushf
	#call	newline
	DEBUG "free:"
	push_	esi eax  edx
	mov	esi, [mem_pages_free]
	mov	ecx, [esi + array_index]
	shr	ecx, 2
	DEBUG_BYTE cl
	jz	1f

0:	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	loop	0b
	call	newline

	mov	esi, [mem_pages_free]
	mov	ecx, [esi + array_index]
	shr	ecx, 2
	DEBUG_BYTE cl
0:	lodsd
	mov	edx, eax
	call	printbin32
	call	printspace
	loop	0b
	call	newline

	# print page addresses
	mov	esi, [mem_pages]
	mov	ecx, [esi + array_index]
	shr	ecx, 2
	jz	9f	# shouldn't happen
0:	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	loop	0b
	call	newline

9:	pop_	edx eax esi
	popf
	ret

1:	DEBUG "no data"
	call	newline
	jmp	9b
.endif
