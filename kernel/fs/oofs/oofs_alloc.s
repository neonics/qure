#############################################################################
.intel_syntax noprefix
#
# persistent lib/mem_handle.s
#

.global class_oofs_alloc

.if HANDLE_STRUCT_SIZE == 32
HANDLE_STRUCT_SIZE_SHIFT = 5
.else
.error "HANDLE_STRUCT_SIZE != 32 unimplemented"
.endif

RESERVE_HANDLES = 16

HANDLE_FLAG_DIRTY = 256	# 2nd byte of flags; first byte reserved by handles.s

####################################################
# Idea: the first sector will contain the linked list information.
# One of the linked list elements (handle will be the handles array itself, the same
# as for mem.
# The first sector will contain the LBA of the handles.
# Each handle will represent a contiguous region.
# 
# Three approaches:
# 1) add translation table (FAT: numbers->sectors)
# 2) allow large files to be split over multiple handles. Make a file
#    a linked list of blocks.
# 3) Use staging area/journalling, reserving some space for new files.
#    When the size #    exceeds the space reserved by the handle, allocate a
#    larger space and copy the contents.
#    This can be combined with 2, where open files use a linked list,
#    whereafter they are consolidated.
#
# For now, this class is the same as mem.s except for diskspace.
# Managing file growth will have to be done elsewhere.
# This class then effectively implements a FAT or sector-lookup-table,
# with variable block length.
#
# IMPLEMENTATION
#
# The handles will be allocated similarly to memory handles, and be flat data.
# When a region can grow, by merging it with the succeeding free region,
# data will not have to be copied on disk.
# When the next region is not free, the handles data will have to be copied,
# marking the old handle region on disk as free.
#
# The persistence of the handles array is handled in this class.
# The first sector is reserved to contain the handles structure containing
# the linked list edges and the index to the handles handle.
#
# Each handle will contain an address and a size; the address will be the LBA
# relative to the oofs_alloc region on disk, and be within it.
#
# Upon load, the reserved sector is read, the location of the handles array
# established, and loaded using custom code.  Loading this secondary data
# is not done using the oofs_persistence since the data is flat and will not
# be represented as an object - for now. (Tried that, but it gets too complex).
#
####################################################
DECLARE_CLASS_BEGIN oofs_alloc, oofs_persistent

#### Volatile

###### begin handles struct fields
oofs_alloc_handles: # the handles struct
oofs_handles_ptr:	.long 0	
oofs_alloc_handles_method_alloc:.long 0 # handles_method_alloc: alloc_handles$ static method

#### Persistent
oofs_alloc_persistent:
.long 0	# handles_num
.long 0 # handles_max
.long 0 # handles_idx
oofs_alloc_ll:		# part of handles struct (lib/handles.s)
oofs_alloc_addr_first:	.long 0	# linked-list
oofs_alloc_addr_last:	.long 0	# linked-list
oofs_alloc_size_first:	.long 0	# linked-list
oofs_alloc_size_last:	.long 0	# linked-list
oofs_alloc_hndl_first:	.long 0	# linked-list
oofs_alloc_hndl_last:	.long 0	# linked-list
###### end handles struct

# store the LBA and sectors of the handles handle (i.e. the disk address for the
# linked list itself)
oofs_alloc_handles_lba:		.long 0
oofs_alloc_handles_sectors:	.long 0

# TODO:
# mark reserved and allocated space just like in mem.
# have alloc_handles use this free space.
#
# OR
#
# manually alloc the handles struct nonpersistent,
# add one handle indicating the entire region as free.
# (bootstrap problems)..


DECLARE_CLASS_METHOD oofs_api_init, oofs_alloc_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_alloc_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_alloc_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_alloc_load, OVERRIDE

DECLARE_CLASS_END oofs_alloc
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs)
# in: ebx = LBA
# in: ecx = reserved size
oofs_alloc_init:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_alloc_init", 0xe0
		DEBUG_DWORD ebx, "LBA"
		DEBUG_DWORD ecx, "size"
		push edx; mov edx,[esp+4]; call debug_printsymbol; pop edx
		call	newline
	.endif

	call	oofs_persistent_init	# super.init()

	# clear linked list
	push_	ebx ecx edx esi edi
	push_	eax 
	lea	edi, [eax + oofs_alloc_ll]
	mov	eax, -1
	mov	ecx, 2 * 3
	rep	stosd
	pop_	eax

	# satisfy handles struct:
	lea	esi, [eax + oofs_alloc_handles]

	mov	[esi + handles_ptr], dword ptr 0
	mov	[esi + handles_num], dword ptr 0
	mov	[esi + handles_max], dword ptr 0
	mov	[esi + handles_method_alloc], dword ptr offset oofs_alloc_handles$

	# initialize

	# add handle for handles.
	call	oofs_alloc_handle_get	# out:ebx
	jc	91f

	mov	[esi + handles_idx], ebx	# remember the handles handle index

	mov	edi, [esi + handles_ptr]
	mov	edx, [esi + handles_max]
	shl	edx, HANDLE_STRUCT_SIZE_SHIFT
	add	edx, 511
	shr	edx, 9
	mov	[edi + ebx + handle_size], edx
	mov	[edi + ebx + handle_base], dword ptr 0	# LBA 0 (relative)
	mov	[edi + ebx + handle_flags], dword ptr MEM_FLAG_HANDLE|HANDLE_FLAG_DIRTY
	# TODO: insert into LL's?

	# add handle for free space
	call	oofs_alloc_handle_get
	jc	91f

	mov	edi, [eax + oofs_alloc_handles + handles_ptr]
	mov	ecx, [eax + oofs_sectors]
	dec	ecx
	mov	[edi + ebx + handle_size], ecx
	mov	[edi + ebx + handle_base], edx	# size of handles handle
	mov	[edi + ebx + handle_flags], dword ptr 0	# free space
	# insert into address list (free)
	lea	edi, [esi + handles_ll_fa]
	mov	esi, [esi + handles_ptr]
	add	esi, offset handle_ll_el_addr
	call	ll_insert_sorted$

	# add free handle
	#lea	edi, [eax + oofs_alloc_handles + 0 * HANDLE_STRUCT_SIZE]
	#mov	[edi + handle_flags], byte ptr 0	# free
	#mov	[edi + handle_size], ecx
	#mov	[edi + handle_fs_next], dword ptr -1
	#mov	[edi + handle_fs_prev], dword ptr -1
9:	pop_	edi esi edx ecx ebx
	STACKTRACE 0
	ret

91:	printlnc 4, "oofs_alloc: error getting handle"
	stc
	jmp	9b

# method called by handles.s when handles region is too small
# in: esi = handles struct
# in: ebx = minimum handles offset to accommodate (thus, size must be ebx+HANDLE_STRUCT_SIZE)
oofs_alloc_handles$:
	push_	eax ebx ecx edx
	mov	eax, [esi + handles_ptr]	
	or	eax, eax
	jz	61f

0:	mov	edx, [esi + handles_max]
	add	edx, RESERVE_HANDLES
	cmp	ebx, edx
	jbe	0b	# shouldn't happen

	mov	ecx, edx	# backup

	shl	edx, HANDLE_STRUCT_SIZE_SHIFT
	call	mreallocz
	jc	91f

	mov	[esi + handles_ptr], eax
	mov	[esi + handles_max], ecx

	clc
9:	pop_	edx ecx ebx eax
	STACKTRACE 0
	ret

# exceptional condition: first time init
61:	DEBUG "no handles, instantiating"
	# first time alloc
	mov	eax, RESERVE_HANDLES * HANDLE_STRUCT_SIZE
	call	mallocz
	jc	91f
	mov	[esi + handles_ptr], eax
	mov	[esi + handles_max], dword ptr RESERVE_HANDLES
	mov	[esi + handles_num], dword ptr 0
	clc
	jmp	9b


91:	printlnc 4, "oofs_alloc_handles: malloc error"
	stc
	jmp	9b


# in: eax = this
oofs_alloc_save:
	push_	ebx ecx edx esi
# DISABLED:
#
# We don't have the volatile data for each handle.
#
#	# save the handles that need saving
#	mov	edx, [eax + oofs_alloc_handles + handles_ptr]
#	mov	ecx, [eax + oofs_alloc_handles + handles_num]
#0:	testd	[edx + handle_flags], HANDLE_FLAG_DIRTY
#	jz	1f
#
#		mov	ebx, [eax + oofs_lba]
#		add	ebx, [edx + handle_base]
#		mov	ecx, [edx + handle_size]
#		mov	esi, 
#
#
#
#
#1:	add	edx, HANDLE_STRUCT_SIZE
#	loop	0b


#	Save the handles handle

	DEBUG_DWORD [eax + oofs_alloc_handles + handles_idx]
	mov	esi, [eax + oofs_alloc_handles + handles_ptr]
	add	esi, [eax + oofs_alloc_handles + handles_idx]

	mov	ebx, [esi + handle_base]
	mov	[eax + oofs_alloc_handles_lba], ebx	# save in reserved sector
	DEBUG_DWORD ebx, "handles.lba"

	add	ebx, [eax + oofs_lba]
	mov	ecx, [esi + handle_size]
	inc	ebx	# skip the reserved sector
	mov	[eax + oofs_alloc_handles_sectors], ecx	# save in reserved sector
	DEBUG_DWORD ecx, "handles.sectors"
	shl	ecx, 9	# sectors->bytes

	mov	edx, eax
	mov	eax, [edx + oofs_persistence]
	DEBUG "WRITE HANDLES"
	DEBUG_DWORD ebx, "lba"
	DEBUG_DWORD ecx, "size"	# XXX shl 9?
	call	[eax + fs_obj_api_write]
	mov	eax, edx

	# save the reserved sector
	mov	edx, offset oofs_alloc_persistent
	lea	esi, [eax + edx]
	mov	ecx, 1	# 1 byte, will write 1 sector
	call	[eax + oofs_persistent_api_write]

	pop_	esi edx ecx ebx
	STACKTRACE 0
	ret


oofs_alloc_load:
	push_	ebx ecx edx edi
	# load reserved sector
	mov	edx, offset oofs_alloc_persistent
	lea	edi, [eax + edx]
	mov	ecx, 1
	call	[eax + oofs_persistent_api_read]	# might change eax
	jc	9f

	DEBUG "loaded reserved sector"

	# load handles handle
	mov	ebx, [eax + oofs_alloc_handles_lba]
	DEBUG_DWORD ebx, "handles.lba"

	mov	ecx, [eax + oofs_alloc_handles_sectors]
	DEBUG_DWORD ecx, "handles.sectors"
	shl	ecx, 9
	jz	9f

	mov	edi, eax	# backup
	mov	eax, ecx
	call	mallocz
	xchg	eax, edi
	jc	91f
	mov	[eax + oofs_alloc_handles + handles_ptr], edi

	DEBUG_DWORD [eax+oofs_lba]
	DEBUG_DWORD ebx

	add	ebx, [eax + oofs_lba]
	inc	ebx
	DEBUG_DWORD ebx
	mov	edx, eax
	mov	eax, [edx + oofs_persistence]
	DEBUG_CLASS eax
	DEBUG_CLASS edx
	DEBUG_DWORD ebx,"LBA"
	DEBUG_DWORD ecx, "bytes"
	call	[eax + fs_obj_api_read]

9:	STACKTRACE 0
	pop_	edi edx ecx ebx
	ret
91:	printlnc 4, "oofs_alloc_load: mallocz error"
	stc
	jmp	9b



# in: eax= this
# out: ebx = handle index
oofs_alloc_handle_get:
	push	esi
	lea	esi, [eax + oofs_alloc_handles]
	call	handle_get
	pop	esi
	STACKTRACE 0
	ret


# in: eax = this (oofs instance)
# in: ecx = bytes
# in: edx = class def ptr
# out: eax = instance
oofs_alloc_add:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_alloc_add", 0xe0
		DEBUG_DWORD ecx
		call	newline
	.endif
	ret

# OK
oofs_alloc_print:
	STACKTRACE 0,0
	call	oofs_persistent_print

	printc 11, "handles: "
	pushd	[eax + oofs_alloc_handles + handles_num]
	call	_s_printhex8
	printcharc 11, '/'
	pushd	[eax + oofs_alloc_handles + handles_max]
	call	_s_printhex8
	printc 11, " rLBA "
	pushd	[eax + oofs_alloc_handles_lba]
	call	_s_printhex8
	printc 11, " rSectors "
	pushd	[eax + oofs_alloc_handles_sectors]
	call	_s_printhex8
	call	newline

	printc 11, "Handles handle: idx "
	pushd	[eax + oofs_alloc_handles + handles_idx]
	call	_s_printhex8

	printc 11, " rLBA "
	push	esi
	mov	esi, [eax + oofs_alloc_handles + handles_ptr]
	add	esi, [eax + oofs_alloc_handles + handles_idx]
	pushd	[esi + handle_base]
	call	_s_printhex8
	printc 11, " sectors "
	pushd	[esi + handle_size]
	call	_s_printhex8
	call	newline

	#

	lea	esi, [eax + oofs_alloc_handles]
	call	handles_print
	pop	esi
	ret

