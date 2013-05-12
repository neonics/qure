.intel_syntax noprefix

MEM_HANDLE_ALIGN_DEBUG = 0
MEM_HANDLE_SPLIT_DEBUG = 0


.struct 0
# substruct ll_info: [base, prev, next] for fa
# NOTICE!!!!! handle_base is dependent to be 0 for optimization! Search for OPT
handle_ll_el_addr:
handle_fa_prev: .long 0		# offset into [mem_handles]
handle_fa_next: .long 0		# offset into [mem_handles]
handle_base: .long 0
# substruct ll_info: [size, prev, next] for fs
handle_ll_el_size:
handle_fs_prev: .long 0		# offset into [mem_handles]
handle_fs_next: .long 0		# offset into [mem_handles]
handle_size: .long 0
# rest:
handle_flags: .byte 0	# 25
	MEM_FLAG_ALLOCATED = 1
	MEM_FLAG_REUSABLE = 2	# handle's base and size are meaningless/0.
	MEM_FLAG_REFERENCE = 4

	MEM_FLAG_DBG_SPLIT	= 8
	MEM_FLAG_DBG_SPLIT2	= 16
	MEM_FLAG_DBG_SLACK	= 32

	MEM_FLAG_UNK	= 64	#
	MEM_FLAG_HANDLE	= 128	# handle for handle structure

	# When there are more than this number of bytes wasted (i.e. reuse
	# of a chunk of previously free'd memory that is larger than the
	# requested size), the chunk will be split across two handles,
	# yielding a handle for the requested size (possibly padded for
	# alignment).
	MEM_SPLIT_THRESHOLD = 64

	.byte 0,0,0 # 28 : align
handle_caller: .long 0# 32

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

# free-by-address
handle_ll_fa:
handle_fa_first: .long -1	# offset into [mem_handles]
handle_fa_last: .long -1	# offset into [mem_handles]
# free-by-size
handle_ll_fs:
handle_fs_first: .long -1	# offset into [mem_handles]
handle_fs_last: .long -1	# offset into [mem_handles]
# free handles
handle_ll_fh:
handle_fh_first: .long -1
handle_fh_last: .long -1	# not really used...

.text32
.data
mem_phys_total:	.long 0, 0	# total physical memory size
mem_handles: .long 0
mem_numhandles: .long 0
mem_maxhandles: .long 0
mem_handles_handle: .long 0
# substructs: pairs of _first and _last need to be in this order!


.text32


mem_print_handles:
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
		mov	edx, [edi + ll_first]
		HOTOI	edx
		call	printdec32
		printcharc 4, ','
		mov	edx, [edi + ll_last]
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
	LL_PRINT handle_fh_first, handle_ll_el_addr #, MEM_FLAG_REUSABLE
	LL_PRINTARRAY MEM_FLAG_REUSABLE, MEM_FLAG_REUSABLE
	call	newline

	PRINT	"A: "
	LL_PRINT handle_fa_first, handle_ll_el_addr
	LL_PRINTARRAY MEM_FLAG_REUSABLE, 0
	call	newline
	PRINT	"S: "
	LL_PRINT handle_fs_first, handle_ll_el_size
	LL_PRINTARRAY (MEM_FLAG_ALLOCATED|MEM_FLAG_REUSABLE), 0
	call	newline

	.if MEM_PRINT_HANDLES == 2
	call	mem_print_handle_2h$
	.else
	.endif

	mov	ebx, [mem_handles]
0:	mov	edx, [mem_numhandles]
	sub	edx, ecx

	.if MEM_PRINT_HANDLES == 2
	call	mem_print_handle_2$
	.else
	call	mem_print_handle_$
	.endif
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

mem_print_handle_2h$:
	println "Handle hndlptr  base.... size.... flags... caller.. [<- A ->] [<- S ->]"
	ret


# in: ebx = handle pointer ([mem_handles] already added)
mem_print_handle_2$:
	push_	eax edx
	# if the screenis full, force a scroll, to get positive delta-screen_pos
	call	printspace
	call	screen_get_pos
	mov	edx, ebx
	sub	edx, [mem_handles]
	HOTOI edx
	call	printdec32
.if 1
	push	ecx
	mov	ecx, eax
	call	screen_get_pos
	sub	ecx, eax
	sar	ecx, 1
	mov	eax, 6
	add	ecx, eax
	js	1f
0:	call	printspace
	loop	0b
1:	pop	ecx
.endif
	mov	edx, ebx	# handle ptr
	call	printhex8
	call	printspace
	mov	edx, [ebx + handle_base]
	call	printhex8
	call	printspace
	mov	edx, [ebx + handle_size]
	call	printhex8
	call	printspace
	mov	dl, [ebx + handle_flags]
	.if 1
	PRINTFLAG dl, MEM_FLAG_ALLOCATED, "A"," "
	PRINTFLAG dl, MEM_FLAG_REUSABLE, "u"," "
	PRINTFLAG dl, MEM_FLAG_REFERENCE, "R"," "
	PRINTFLAG dl, MEM_FLAG_DBG_SPLIT, "/"," "
	PRINTFLAG dl, MEM_FLAG_DBG_SPLIT2, "2"," "
	PRINTFLAG dl, MEM_FLAG_DBG_SLACK, "&"," "
	PRINTFLAG dl, MEM_FLAG_UNK, "?"," "
	PRINTFLAG dl, MEM_FLAG_HANDLE, "H"," "
	.else
	call	printbin8
	.endif
	call	printspace
	mov	edx, [ebx + handle_caller]
	call	printhex8

	call	printspace
	mov	edx, [ebx + handle_fa_prev]
	HOTOI	edx
	call	printdec32
	call	printspace
	mov	edx, [ebx + handle_fa_next]
	HOTOI	edx
	call	printdec32
	call	printspace
	call	printspace
	mov	edx, [ebx + handle_fs_prev]
	HOTOI	edx
	call	printdec32
	call	printspace
	mov	edx, [ebx + handle_fs_next]
	HOTOI	edx
	call	printdec32
	call	printspace

	mov	edx, [ebx + handle_caller]
	push	ebx
	push	esi
	push	edi
	call	debug_getsymbol
	jc	1f
	call	print
	jmp	2f
1:	call	debug_get_preceeding_symbol
	jc	2f
	call	print
	printcharc_ 13,'+'
2:
	pop	edi
	pop	esi
	pop	ebx

	call	newline

	pop_	edx eax
	ret


mem_print_handle_$:
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

mem_print_handle$:
	push	edx
	mov	edx, ebx
	HOTOI	edx
	add	ebx, esi
	call	mem_print_handle_$
	sub	ebx, esi
	pop	edx
	ret


# prints the handles from a linked list (free, allocated).
# in: ebx = [handle_ll_fa] | handle_ll_fs
# in: edi = offset handle_ll_el_addr | offset handle_ll_el_size
mem_print_ll_handles$:

	.if MEM_PRINT_HANDLES == 2
	call	mem_print_handle_2h$
	.else
	.endif

	mov	ebx, [ebx + ll_first]

	mov	ecx, [mem_numhandles]	# inf loop check
	jmp	1f

0:	add	ebx, [mem_handles]

	.if MEM_PRINT_HANDLES == 2
	call	mem_print_handle_2$
	.else
	call	mem_print_handle_$
	.endif

	mov	ebx, [ebx + edi + ll_next]
	dec	ecx
	jz	2f
1:	cmp	ebx, -1
	jnz	0b
2:	ret


# Returns a free handle, base and size to be filled in, marked nonfree.
# in: esi = [mem_handles]
# out: esi might be updated if handle array is reallocated
# out: ebx = handle index
get_handle$:
	# first check if we can reuse handles:
	mov	ebx, [handle_fh_first]
	cmp	ebx, -1
	jz	0f

	push	edi
	mov	edi, offset handle_ll_fh
	add	esi, offset handle_ll_el_addr # OPT
	call	ll_unlink$
	sub	esi, offset handle_ll_el_addr # OPT
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
	mov	[esi + ebx + handle_base], dword ptr 0
	mov	[esi + ebx + handle_size], dword ptr 0
	mov	[esi + ebx + handle_fs_next], dword ptr -1
	mov	[esi + ebx + handle_fs_prev], dword ptr -1
	mov	[esi + ebx + handle_fa_next], dword ptr -1
	mov	[esi + ebx + handle_fa_prev], dword ptr -1
	inc	dword ptr [mem_numhandles]
	ret

# meant for external callers
# in: eax = handle_base (allocated mem ptr)
# out: ebx = handle struct ptr
# out: edx = handle number (decimal count)
mem_find_handle$:
	push	ecx
	mov	ebx, [mem_handles]
	mov	ecx, [mem_numhandles] # can't be 0
0:	cmp	eax, [ebx + handle_base]
	jz	1f
	add	ebx, HANDLE_STRUCT_SIZE
	loop	0b
	pop	ecx
	stc
	ret

1:	mov	edx, [mem_numhandles]
	sub	edx, ecx
	pop	ecx
	clc
	ret

# in: eax = size
# in: edx = physical address align
# in: esi = [mem_handles]
# out: ebx = handle index that can accommodate it
# out: CF on none found
find_handle_aligned$:
	# lame solution:
	push	eax
	add	eax, edx	# -1?
	call	find_handle$
	pop	eax
	jc	9f

# in: ebx = handle
align_handle$:
	push_	edi edx ecx

	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG "align_handle"
		DEBUG_DWORD eax,"size"
		DEBUG_DWORD edx,"align"
		DEBUG_DWORD [esi+ebx+handle_base],"base"
		DEBUG_DWORD [esi+ebx+handle_size],"size"
		DEBUG "pre:"
		pushad; call mem_print_handles; popad
	.endif

	# have ecx be the new base

	GDT_GET_BASE ecx, ds
	mov	edi, ecx
	mov	ecx, [esi + ebx + handle_base]
	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD ecx,"logical base"
	.endif
	sub	ecx, edi
	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD ecx,"phys base"
	.endif
	dec	edx
	add	ecx, edx
	not	edx
	and	ecx, edx
	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD ecx, "aligned phys base"
	.endif

	jz	1f		# already aligned
	add	ecx, edi	# ecx = phys aligned ds rel base
	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD ecx,"logical aligned base"
		DEBUG_DWORD eax
	.endif
	# now split the handle: shrink the current handle to the slack size eax
	# and return a new handle succeeding it with the remaining size.

	push	eax
	mov	eax, ecx	# new base
	sub	eax, [esi + ebx + handle_base]	# eax = alignment slack
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SLACK
	call	mem_split_handle_tail$
	pop	eax

	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD eax
		DEBUG "post split tail"
		pushad; call mem_print_handles; popad
	.endif
	# NOTE: depending on the handle's base address, the slack size
	# varies. Therefore, the new handle will most likely be larger
	# than required.

	# Do another split if this is so:
	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, eax
	cmp	ecx, MEM_SPLIT_THRESHOLD
	jb	2f
	# split it, this time preserving the head
	call	mem_split_handle_head$
2:

0:	pop_	ecx edx edi
	clc
9:	ret

1:	# already aligned, though size is too large
	jmp	0b





# in: eax = size
# in: esi = [mem_handles]
# out: ebx = handle index that can accommodate it
# out: CF on none found
find_handle$:
	mov	ebx, [handle_fs_first]
	push	ecx
	mov	ecx, [mem_numhandles]

0:	cmp	ebx, -1
	jz	1f
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
3:	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	push	edi
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size
	call	ll_unlink$
	sub	esi, offset handle_ll_el_size
	pop	edi
	clc
	jmp	2b

# sublevel 2: split implementation
1: 	call	mem_split_handle_head$
	# its probably done now, can return: jmp 2b
	jmp	3b

# This method will split the current handle at size eax,
# returning a NEW ALLOCATED handle of size eax, relegating
# the extra space at the TAIL to the OLD handle.
#
# Thus the OLD handle will be SHIFTED and SHRUNK and FREE.
# The NEW handle will have the SAME BASE but SIZE eax and ALLOCATED.
#
# in: esi = [mem_handles]
# in: ebx = handle to split, still part of ll_fs, not allocated
# in: eax = desired handle size
# out: ebx = new handle of size eax preceeding the old handle in address.
# SIDE EFFECT:
# original handle ebx: base+=eax; size-=eax;
# original handle is repositioned in the free by size list.
# new handle is marked allocated (by get_handle)
mem_split_handle_head$:
	push_	edx ecx

	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG "head: old, new";call newline;
		add	ebx, esi;
		call	mem_print_handle_2$
		sub	ebx, esi
	.endif

	mov	edx, ebx	# backup
	call	get_handle$	# already marked MEM_FLAG_ALLOCATED

	.if MEM_HANDLE_SPLIT_DEBUG
		add	ebx, esi
		call	mem_print_handle_2$
		sub	ebx, esi
			call	mem_print_handles
	.endif

	# debug markings
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SPLIT # 8
	or	byte ptr [esi + edx + handle_flags], MEM_FLAG_DBG_SPLIT2 # 16
	#already the case:
	#and	byte ptr [esi + edx + handle_flags], ~MEM_FLAG_ALLOCATED

	# edx = handle to split, ebx = handle to return, eax = size
	mov	ecx, [esi + edx + handle_base]
	# donate the first eax bytes of edx to ebx, and shift the base of edx
	add	[esi + edx + handle_base], eax	# old handle base starts after desired size
	sub	[esi + edx + handle_size], eax	# old handle size reduced by desired size
	mov	[esi + ebx + handle_base], ecx	# new handle base := old handle base
	mov	[esi + ebx + handle_size], eax	# new handle size := desired size

	# since both handles are within the range of the original,
	# it's base (handle_fa_..) won't change.

	# insert the new handle before the old handle in the address list
	push_	edi eax
	# prepend ebx to edx
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	mov	eax, edx
	call	ll_insert_before$

	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.
	# use a specialized insert routine, that starts searching
	# somewhere in the list (not necessarily at the beginning/ending).
	# Since the handle has shrunk in size, only search left.
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
	# ebx is the new handle - ignore it (but save it)
	push	ebx
	mov	ebx, edx
	call	ll_update_left$	# shift old handle the free/size list
	pop	ebx

	sub	esi, offset handle_ll_el_size

	pop_	eax edi

	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG "updated: old, new";call newline;
		push	ebx
		lea	ebx, [edx + esi]
		call	mem_print_handle_2$
		mov	ebx, [esp]
		add	ebx, esi
		call	mem_print_handle_2$
		call	newline
		pop	ebx
			call	mem_print_handles
	.endif

	## return

	pop_	ecx edx
	clc
	ret




# This method will split the current handle at size-offset eax,
# RETURNING a NEW handle at BASE eax, with size (size-eax).
# The OLD handle will have it's size SHRUNK but the SAME BASE.
#
#
# Thus the OLD handle will be SHRUNK to size eax and FREE.
# The NEW handle will have the SAME BASE but SIZE (size-eax) and ALLOCATED.
#
# In other words, this method will SHRINK the size of the handle TO eax,
# marking it as FREE, and returning a NEW HANDLE with the REMAINING SIZE,
# starting at base + eax.
#
# This method is intended for physical memory address alignment.
#
# in: esi = [mem_handles]
# in: ebx = handle to split
# in: eax = size to shrink ebx to.
# out: ebx = new handle with remaining size SUCCEEDING old handle in address.
# SIDE EFFECT:
# original handle ebx: size=eax, FREE
# original handle is repositioned in the free by size list.
# new handle: base = old.base + eax, size = old.size - eax; ALLOCATED.
mem_split_handle_tail$:
	push_	edx ecx eax
	mov	edx, ebx	# backup
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD eax,"shrinkto"
	.endif
	call	get_handle$	# already marked MEM_FLAG_ALLOCATED
	# debug markings
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SPLIT # 8
	or	byte ptr [esi + edx + handle_flags], MEM_FLAG_DBG_SPLIT2 # 16

	and	byte ptr [esi + edx + handle_flags], ~MEM_FLAG_ALLOCATED

	# edx = handle to split, ebx = handle to return, eax = size
	mov	ecx, [esi + edx + handle_base]
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD ecx,"old base"
	.endif
	add	ecx, eax
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD eax,"shrink to"
		DEBUG_DWORD ecx, "new base"
	.endif
	mov	[esi + ebx + handle_base], ecx	# NEW base at old.base + eax
	mov	ecx, eax
	xchg	eax, [esi + edx + handle_size]	# old handle size reduced TO desired size
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD eax,"old size"
	.endif
	sub	eax, ecx			# eax = remaining size
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD eax,"remaining size"
	.endif
	mov	[esi + ebx + handle_size], eax	# NEW size is remaining size.


	# since both handles are within the range of the original,
	# it's base (handle_fa_..) won't change.

	# insert the NEW handle AFTER the old handle
	push_	edi
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	mov	eax, edx
	call	ll_insert_after$	# insert new ebx after old edx (eax)

	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.

	# NOTE: this is identical to mem_split_handle_head, where the OLD handle
	# remained in the FREE list, except here, it PRECEEDS the new handle by address,
	# whereas in the other, the new handle's base is shifted to SUCCEED.
	# In both cases, the old handle remains FREE and the new ALLOCATED,
	# and in both cases, the size of the old handle shrinks.
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
	# ebx is the new handle - ignore it (but save it)
	push	ebx
	mov	ebx, edx
	call	ll_update_left$	# shift old handle the free/size list
	pop	ebx

	sub	esi, offset handle_ll_el_size
	pop_	edi

	## return

	pop_	eax ecx edx
	clc
	ret





###################################


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
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_DBG_SPLIT # 8
	or	byte ptr [esi + edx + handle_flags], MEM_FLAG_DBG_SPLIT2 # 16

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
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	mov	eax, edx
	call	ll_insert_before$
	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.
	# use a specialized insert routine, that starts searching
	# somewhere in the list (not necessarily at the beginning/ending).
	# Since the list has shrunk in size, only search left.
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
	# ebx is the new handle - ignore it (but save it)
	push	ebx
	mov	ebx, edx
	call	ll_update_left$
	pop	ebx

	sub	esi, offset handle_ll_el_size

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
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	xchg	eax, ebx
	call	ll_insert$
	xchg	eax, ebx
	sub	esi, offset handle_ll_el_addr
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
		call	mem_print_handles
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
		popcolor

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
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size
	call	ll_unlink$
	sub	esi, offset handle_ll_el_size
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
		## clear the rest:
		#mov	ecx, ALLOC_HANDLES * HANDLE_STRUCT_SIZE / 4
		#push	eax
		#xor	eax, eax
		#rep	stosd
		#pop	eax
	pop	ecx
	pop	edi


1:
	mov	esi, eax
	xchg	eax, [mem_handles]
	add	[mem_maxhandles], dword ptr ALLOC_HANDLES

	# reserve a handle
	call	get_handle$	# potential recursion
	mov	[mem_handles_handle], ebx
	pop	dword ptr [esi + ebx + handle_size]	# the saved size
	mov	[esi + ebx + handle_base], esi
	mov	[esi + ebx + handle_caller], dword ptr offset alloc_handles$
	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_HANDLE #1 << 7
	push	edi
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	push	ecx
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$
	pop	ecx
	sub	esi, offset handle_ll_el_addr
	pop	edi

	# now mark the old memory region as free:
	or	eax, eax	# only applies to first time
	jz	1f
	call	mfree	# see 1b for eax
1:

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
		call	mem_print_handles
		popcolor
		MORE
		popad
		.endif

	# When we're here, the handles are set up properly, at least one
	# allocated for the handle structures themselves.

	pop	ebx
	pop	eax
	ret


# search term: verify
mem_validate_handles:
_mem_validate_contiguous_address$:
	pushf
	pushad
	mov	esi, [mem_handles]
	or	esi, esi
	jz	9f
	mov	ecx, [mem_numhandles]
	or	ecx, ecx
	jz	9f

	xor	ebx, ebx
0:
	mov	eax, [esi + ebx + handle_base]
	# check address prev
	mov	edi, [esi + ebx + handle_fa_prev]
	cmp	edi, -1
	jz	1f
	mov	edx, [esi + edi + handle_base]
	add	edx, [esi + edi + handle_size]
	cmp	edx, eax
	jnbe	41f
1:
	add	eax, [esi + ebx + handle_size]
	mov	edi, [esi + ebx + handle_fa_next]
	cmp	edi, -1
	jz	1f
	cmp	eax, [esi + edi + handle_base]
	jnbe	42f
1:
	add	ebx, HANDLE_STRUCT_SIZE
	loop	0b

9:	popad
	popf
	ret

41:	cli
	printlnc 4, "MEM ERROR: prev(base+size) != curr(base)";
	DEBUG "curr", 0x04
	push	edx
	mov	edx, ebx
	call	printdec32
		DEBUG_DWORD [esi+ebx+handle_base],"base"
		DEBUG_DWORD [esi+ebx+handle_size],"size"
		DEBUG_DWORD eax
	call	newline

	DEBUG "prev", 0x04
	mov	edx, edi
	call	printdec32
	pop	edx
		DEBUG_DWORD [esi+edi+handle_base],"base"
		DEBUG_DWORD [esi+edi+handle_size],"size"
		DEBUG_DWORD edx, "sum"
		call	newline

	add	ebx, esi
	call	mem_print_handle_$
	lea	ebx, [esi + edi]
	call	mem_print_handle_$
	printlnc 4,"-----------------------------";
	call	mem_print_handles
	int 1
	sti

	jmp	9b

42:	cli
	printlnc 4, "MEM ERROR: curr(base+size) != next(base)";
	DEBUG "curr", 0x04
	push	edx
	mov	edx, ebx
	call	printdec32
		DEBUG_DWORD [esi+ebx+handle_base],"base"
		DEBUG_DWORD [esi+ebx+handle_size],"size"
		DEBUG_DWORD eax, "sum"
	call	newline

	DEBUG "next", 0x04
	mov	edx, edi
	call	printdec32
	pop	edx
		DEBUG_DWORD [esi+edi+handle_base],"base"
		DEBUG_DWORD [esi+edi+handle_size],"size"
		call	newline

	add	ebx, esi
	call	mem_print_handle_$
	lea	ebx, [esi + edi]
	call	mem_print_handle_$
	printlnc 4,"-----------------------------";
	call	mem_print_handles
	int 1
	sti

	jmp	9b


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


# in: esi, ebx
# destroyed: edi, eax, edx
# out: CF = 0: merged; ebx = new handle. CF=1: no merge, ebx is marked free.
handle_merge_fa$:
0:	xor	edi, edi

	# Check if ebx.base follows the previous handle AND is also free
	mov	eax, [esi + ebx + handle_fa_prev]
	cmp	eax, -1
	jz	1f
	test	byte ptr [esi + eax + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f
	mov	edx, [esi + eax + handle_base]
	add	edx, [esi + eax + handle_size]
	cmp	edx, [esi + ebx + handle_base]
	jnz	1f
	# eax preceeds ebx immediately, address wise, and is also free.
	# empty ebx, add memory to eax:
	xor	edx, edx
	xchg	edx, [esi + ebx + handle_size]
	add	[esi + eax + handle_size], edx
	# empty out ebx
	jmp	2f

1:	# check if ebx base+size preceeds the following handle's base AND it is free
	mov	eax, [esi + ebx + handle_fa_next]
	cmp	eax, -1
	jz	1f
#DEBUG "e",0x8f
	test	byte ptr [esi + eax + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jnz	1f
#DEBUG "f",0x8f
	mov	edx, [esi + ebx + handle_base]
	add	edx, [esi + ebx + handle_size]
	cmp	edx, [esi + eax + handle_base]
	jnz	1f

#DEBUG "g",0x8f
	# ebx preceeds eax immediately.
	# Prepend ebx's size to eax:
	xor	edx, edx
	xchg	edx, [esi + ebx + handle_size]
	sub	[esi + eax + handle_base], edx
	add	[esi + eax + handle_size], edx

2:	# merge
	# empty ebx; size is already zero. 
	# remove from address list (and set address 0),
	# and remove from size list,
	# and add it to the free-handles list.

	# remove from the address list
	mov	[esi + ebx + handle_base], dword ptr 0
	mov	edi, offset handle_ll_fa
	add	esi, offset handle_ll_el_addr
	call	ll_unlink$
	# add to the reusable handles list
	mov	edi, offset handle_ll_fh
	push	ecx
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$	# this does a loop on address, unneeded; call append instead?
	pop	ecx
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_REUSABLE

MERGE_RECURSE = 0
	# eax's address list membership doesnt change.
	# eax's size address might have changed:
	mov	ebx, eax
.if MERGE_RECURSE
#DEBUG "R",0x8f
	sub	esi, offset handle_ll_el_addr
	mov	edi, -1	# loop
	jmp	0b
3:
.else
#DEBUG "!",0x8f
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
.endif
	mov	edi, offset handle_ll_fs
	# remove and insert:
	#call	ll_unlink$
	#call	ll_insert_sorted$
	# better: size has grown, so update right:
	call	ll_update_right$

	# leave ebx to point to the newly free'd memory.
	clc
	ret

1:	# no matches. mark memory as free.
.if MERGE_RECURSE
	cmp	edi, -1
	je	3b
.endif
	mov	edi, offset handle_ll_fs
	add	esi, offset handle_ll_el_size
	push	ecx
	mov	ecx, [mem_maxhandles]
	call	ll_insert_sorted$
	pop	ecx
	sub	esi, offset handle_ll_el_size
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

