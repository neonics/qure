##############################################################################
#
# Address Space Management routines.
#
.intel_syntax noprefix

MEM_HANDLE_ALIGN_DEBUG = 0
MEM_HANDLE_SPLIT_DEBUG = 0

HANDLE_ASSERT = 1	# data integrity assertions


.global handle_get
.global handle_free
.global handle_free_by_base
.global handle_find
.global handles_print
##############################################################################
# This is the 'static' handle management structure.
# Note that even though it says 'array' below, this is not the array
# from hash.s, which stores the max/num fields in the array itself.
# The array here is simply a memory block containing elements of variable
# size (though they will generally just be fixed size handle_ struct).
# The elements must contain the fields as defined in handle_ struct below.
.struct 0	# handles struct
handles_ptr:	.long 0	# base pointer to array of handle_ struct
handles_method_alloc: .long 0	# method to reallocate the handles handle
handles_num:	.long 0	# number of handles in array
handles_max:	.long 0	# max handles that can fit in the array
handles_idx:	.long 0	# handles handle; set, but unused
handles_ll_fa:	.long 0,0	# linked-list by address (handle_base)
handles_ll_fs:	.long 0,0	# linked-list by size (handle_size)
handles_ll_fh:	.long 0,0	# linked-list of unused handles.
HANDLES_STRUCT_SIZE = .


###################################
# This structure is present as array elements in the handles_ptr array.
# It consists of two ll_info structures, one for the base address and one for
# size. These linked lists are sorted according to the values.
.struct 0	# handle_ struct
# fields to maintain a linked list sorted by address
handle_ll_el_addr:	# ll_info
handle_fa_prev: .long 0		# offset into containing array (handles_ptr)
handle_fa_next: .long 0		# offset into containing array (handles_ptr)
handle_base:	.long 0		# address of block of data

# fields to maintain a linked list sorted by size
handle_ll_el_size:	# ll_info
handle_fs_prev: .long 0		# offset into containing array (handles_ptr)
handle_fs_next: .long 0		# offset into containing array (handles_ptr)
handle_size:	.long 0		# size of block of data

# These are custom fields indicating the type of handle and other info.
handle_flags:	.byte 0
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

.if . != HANDLE_STRUCT_SIZE
.error "HANDLE_STRUCT_SIZE must be 32"
.endif

##############################################################################


.if DEFINE

.macro HITO r	# handle_index_to_offset
	shl	\r, 5
.endm

.macro HITDS r	# doubleword size (for movsd)
	shl	\r, 3
.endm

.macro HOTOI r
	sar	\r, 5
.endm

# initial and incremental handle allocation
ALLOC_HANDLES = 32 # 1024


.text32
###############################################################################
# Handle list printing routines

# in: esi = handles struct ptr
handles_print:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi	# esi must be last

######### print handles..

	print "handles: "
	mov	edx, [esi + handles_num]
	mov	ecx, edx
	call	printdec32
	printchar '/'
	mov	edx, [esi + handles_max]
	call	printdec32
	print " addr: "
	mov	edx, [esi + handles_ptr]
	call	printhex8
	print " U["
	mov	edx, [esi + handles_ll_fh + ll_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [esi + handles_ll_fh + ll_last]
	HOTOI	edx
	call	printdec32
	print "] A["
	mov	edx, [esi + handles_ll_fa + ll_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [esi + handles_ll_fa + ll_last]
	HOTOI	edx
	call	printdec32
	print	"] S["
	mov	edx, [esi + handles_ll_fs + ll_first]
	HOTOI	edx
	call	printdec32
	printchar ' '
	mov	edx, [esi + handles_ll_fs + ll_last]
	HOTOI	edx
	call	printdec32
	print	"]"
	call	newline
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
		push_	ecx edi esi
		lea	edi, [esi + \firstlast]
		PRINT_LL_FIRSTLAST
		mov	esi, [esi + handles_ptr]
		#mov	edi, esi
		add	esi, offset \prevnext
		mov	ebx, [edi + ll_first]
		# check first
		or	ebx, ebx
		jns	1f

		# the first is -1, so check if last is -1
		cmp	[edi + ll_last], ebx
		jz	2f
		printc 4, " first "
		mov	edx, ebx
		HOTOI	edx
		call	printdec32
		printc 4, " != last "
		mov	edx, [edi + ll_last]
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
		mov	edx, [edi + ll_last]
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
		pop_	esi edi ecx
	.endm

	.macro LL_PRINTARRAY mask, cmp
		printc 8, "    ["
		push_	ecx esi
		mov	esi, [esi + handles_ptr]
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
		pop_	esi ecx
		printc	8,"]"
	.endm

	print	"U: "
	LL_PRINT handles_ll_fh, handle_ll_el_addr #, MEM_FLAG_REUSABLE
	LL_PRINTARRAY MEM_FLAG_REUSABLE, MEM_FLAG_REUSABLE
	call	newline

	PRINT	"A: "
	LL_PRINT handles_ll_fa, handle_ll_el_addr
	LL_PRINTARRAY MEM_FLAG_REUSABLE, 0
	call	newline
	PRINT	"S: "
	LL_PRINT handles_ll_fs, handle_ll_el_size
	LL_PRINTARRAY (MEM_FLAG_ALLOCATED|MEM_FLAG_REUSABLE), 0
	call	newline

	.if MEM_PRINT_HANDLES == 2
	call	handle_print_2h$
	.endif

	mov	esi, [esp]
	mov	ebx, [esi + handles_ptr]
0:	mov	edx, [esi + handles_num]
	sub	edx, ecx

	.if MEM_PRINT_HANDLES == 2
	call	handle_print_2$
	.else
	call	handle_print_$
	.endif
	add	ebx, HANDLE_STRUCT_SIZE

	loop	0b
6:
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

handle_print_2h$:
	println "Handle base.... size.... flags... caller.. [<- A ->] [<- S ->]"
	ret


# in: ebx = abs handle pointer ([handles_ptr] already added)
# in: edx = handle number (0,1,2,...)
handle_print_2$:
	push_	eax edx
	# if the screenis full, force a scroll, to get positive delta-screen_pos
	call	printspace
	call	screen_get_pos	# out: eax
#	mov	edx, ebx
#	sub	edx, esi	# sub handles_ptr to get index
#	HOTOI edx
	call	printdec32
.if 1	# padding
	push	ecx
	mov	ecx, eax
	call	screen_get_pos
	sub	ecx, eax
	sar	ecx, 1
	mov	eax, 6
	add	ecx, eax
	jg	0f
	neg	ecx
	jz	1f
0:	call	printspace
	loop	0b
1:	pop	ecx
.endif
	#mov	edx, ebx	# handle ptr (add to _2h$)
	#call	printhex8
	#call	printspace
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

# in: ebx = abs handle ptr
# in: edx = handle number (0,1,2,..)
handle_print_$:
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

# in: ebx = handle index
# in: esi = [handles_ptr]
handle_print$:
	push	edx
	mov	edx, ebx
	HOTOI	edx
	add	ebx, esi
	call	handle_print_$
	sub	ebx, esi
	pop	edx
	ret


# prints the handles from a linked list (free, allocated).
# in: ebx = offset handles_ll_(fa|fs)
# in: edi = offset handle_ll_el_(addr|size)
# in: esi = handles struct ptr
handles_print_ll:

	.if MEM_PRINT_HANDLES == 2
	call	handle_print_2h$
	.else
	.endif

	mov	ebx, [ebx + ll_first]

	mov	ecx, [esi + handles_num]	# inf loop check
	jmp	1f

0:	add	ebx, [esi + handles_ptr]

	.if MEM_PRINT_HANDLES == 2
	call	handle_print_2$
	.else
	call	handle_print_$
	.endif

	mov	ebx, [ebx + edi + ll_next]
	dec	ecx
	jz	2f
1:	cmp	ebx, -1
	jnz	0b
2:	ret



###############################################################################
# Handle management


# Returns a free handle, base and size to be filled in, marked nonfree.
#
# in: esi = handles struct pointer
# out: ebx = handle index
# side-effect: [esi + handles_ptr] updated if handle array is reallocated
# effect: [esi + handles_num] incremented
handle_get:
	push	esi
	# first check if we can reuse handles:
	mov	ebx, [esi + handles_ll_fh + ll_first]
	cmp	ebx, -1
	jz	1f

	push	edi
	lea	edi, [esi + handles_ll_fh]
	mov	esi, [esi + handles_ptr]
	add	esi, offset handle_ll_el_addr
	call	ll_unlink$
	sub	esi, offset handle_ll_el_addr
	pop	edi

	and	[esi + ebx + handle_flags], byte ptr ~MEM_FLAG_REUSABLE
	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
9:	pop	esi
	ret

1:	mov	ebx, [esi + handles_num]
	cmp	ebx, [esi + handles_max]
	jb	1f
	call	[esi + handles_method_alloc] # handles_alloc$	# updates esi
	jc	9b

1:	mov	ebx, [esi + handles_num]
	mov	esi, [esi + handles_ptr]
	HITO	ebx
	mov	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	mov	[esi + ebx + handle_base], dword ptr 0
	mov	[esi + ebx + handle_size], dword ptr 0
	mov	[esi + ebx + handle_fs_next], dword ptr -1
	mov	[esi + ebx + handle_fs_prev], dword ptr -1
	mov	[esi + ebx + handle_fa_next], dword ptr -1
	mov	[esi + ebx + handle_fa_prev], dword ptr -1
	pop	esi
	incd	[esi + handles_num]
	ret


# in: esi = handles struct ptr
# in: eax = size
# in: edx = physical address align
# out: ebx = handle index that can accommodate it
# out: CF on none found
handle_find_aligned:
	# lame solution:
	push	eax
	add	eax, edx	# -1?
	call	handle_find
	pop	eax
	jc	9f
# KEEP-WITH-NEXT

# (this method is not called; fallthrough)
# in: esi = handles struct ptr
# in: ebx = handle
# out: ebx = handle
align_handle$:
	push_	edi edx ecx esi	# esi must be last

	# have ecx be the new base

	GDT_GET_BASE ecx, ds
	mov	edi, ecx
	mov	esi, [esi + handles_ptr]
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
	mov	esi, [esp + 4]	# get handles struct ptr
	call	handle_split_tail$
	pop	eax

	.if MEM_HANDLE_ALIGN_DEBUG > 1
		DEBUG_DWORD eax
		DEBUG "post split tail"
		pushad; call handles_print; popad
	.endif
	# NOTE: depending on the handle's base address, the slack size
	# varies. Therefore, the new handle will most likely be larger
	# than required.

	# Do another split if this is so:
	mov	esi, [esi + handles_ptr]
	mov	ecx, [esi + ebx + handle_size]
	sub	ecx, eax
	cmp	ecx, MEM_SPLIT_THRESHOLD
	jb	2f
	# split it, this time preserving the head
	mov	esi, [esp]
	call	handle_split_head$
2:

0:	pop_	esi ecx edx edi
	clc
9:	ret

1:	# already aligned, though size is too large
	jmp	0b





# in: esi = handles struct ptr
# in: eax = size
# out: ebx = handle index that can accommodate it
# out: CF on none found
handle_find:
	push_	ecx esi	# esi must be last
	mov	ebx, [esi + handles_ll_fs + ll_first]
	mov	ecx, [esi + handles_num]
	mov	esi, [esi + handles_ptr]

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
2:	pop_	esi ecx
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
	mov	edi, [esp + 4]	# get handles struct ptr
	add	edi, offset handles_ll_fs	# first/last ptr
	add	esi, offset handle_ll_el_size	# handle field
	call	ll_unlink$
	sub	esi, offset handle_ll_el_size
	pop	edi
	clc
	jmp	2b

# sublevel 2: split implementation
1: 	mov	esi, [esp]	# handles struct ptr
	call	handle_split_head$
	mov	esi, [esi + handles_ptr]
	# its probably done now, can return: jmp 2b
	jmp	3b

# This method will split the current handle at size eax,
# returning a NEW ALLOCATED handle of size eax, relegating
# the extra space at the TAIL to the OLD handle.
#
# Thus the OLD handle will be SHIFTED and SHRUNK and FREE.
# The NEW handle will have the SAME BASE but SIZE eax and ALLOCATED.
#
# in: esi = handles struct ptr
# in: ebx = handle to split, still part of ll_fs, not allocated
# in: eax = desired handle size
# out: ebx = new handle of size eax preceeding the old handle in address.
# SIDE EFFECT:
# original handle ebx: base+=eax; size-=eax;
# original handle is repositioned in the free by size list.
# new handle is marked allocated (by get_handle)
handle_split_head$:
	push_	edx ecx esi	# esi must be last

	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG "head: old, new";call newline;
		mov	esi, [esi + handles_ptr]
		add	ebx, esi;
		call	handle_print_2$
		sub	ebx, esi
		mov	esi, [esp]
	.endif

	mov	edx, ebx	# backup
	call	handle_get	# in: esi; out: ebx, already marked MEM_FLAG_ALLOCATED
	mov	esi, [esi + handles_ptr]

	.if MEM_HANDLE_SPLIT_DEBUG
		add	ebx, esi
		call	handle_print_2$
		sub	ebx, esi
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
	mov	edi, [esp + 8]	# handles struct ptr
	add	edi, offset handles_ll_fa
	add	esi, offset handle_ll_el_addr
	mov	eax, edx
	call	ll_insert_before$

	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.
	# use a specialized insert routine, that starts searching
	# somewhere in the list (not necessarily at the beginning/ending).
	# Since the handle has shrunk in size, only search left.
	add	edi, offset handles_ll_fs - offset handles_ll_fa
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
		call	handle_print_2$
		mov	ebx, [esp]
		add	ebx, esi
		call	handle_print_2$
		call	newline
		pop	ebx
	.endif

	## return

	pop_	esi ecx edx
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
# in: esi = handles struct ptr
# in: ebx = handle to split
# in: eax = size to shrink ebx to.
# out: ebx = new handle with remaining size SUCCEEDING old handle in address.
# SIDE EFFECT:
# original handle ebx: size=eax, FREE
# original handle is repositioned in the free by size list.
# new handle: base = old.base + eax, size = old.size - eax; ALLOCATED.
handle_split_tail$:
	push_	edx ecx eax esi	# esi must be last
	mov	edx, ebx	# backup
	.if MEM_HANDLE_SPLIT_DEBUG
		DEBUG_DWORD eax,"shrinkto"
	.endif
	call	handle_get	# in: esi; out: ebx, already marked MEM_FLAG_ALLOCATED
	mov	esi, [esi + handles_ptr]
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
	mov	edi, [esp + 4]	# arg esi: handles struct ptr
	add	edi, offset handles_ll_fa
	add	esi, offset handle_ll_el_addr
	mov	eax, edx
	call	ll_insert_after$	# insert new ebx after old edx (eax)

	# the size list for unallocated memory needs to continue
	# to contain the original block with free memory, but
	# it may need to shift in the list.

	# NOTE: this is identical to handle_split_head, where the OLD handle
	# remained in the FREE list, except here, it PRECEEDS the new handle by address,
	# whereas in the other, the new handle's base is shifted to SUCCEED.
	# In both cases, the old handle remains FREE and the new ALLOCATED,
	# and in both cases, the size of the old handle shrinks.
	add	edi, offset handles_ll_fs - offset handles_ll_fa
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
	# ebx is the new handle - ignore it (but save it)
	push	ebx
	mov	ebx, edx
	call	ll_update_left$	# shift old handle the free/size list
	pop	ebx

	sub	esi, offset handle_ll_el_size
	pop_	edi

	## return

	pop_	esi eax ecx edx
	clc
	ret


###################################


# in: esi = handles struct ptr
# updates [esi + handles_ptr]
handles_alloc$:
	push_	eax ebx ecx edi esi	# esi must be last
	mov	eax, ALLOC_HANDLES
	add	eax, [esi + handles_max]
	HITO	eax
	push	eax	# save size for later
	call	malloc_internal$

	# bootstrap realloc
	cmpd	[esi + handles_ptr], 0
	jz	1f

	mov	edi, eax
	mov	ecx, [esi + handles_max]
	mov	esi, [esi + handles_ptr]
	HITDS	ecx
	rep	movsd
		## clear the rest:
		#mov	ecx, ALLOC_HANDLES * HANDLE_STRUCT_SIZE / 4
		#push	eax
		#xor	eax, eax
		#rep	stosd
		#pop	eax

1:
	mov	esi, [esp + 4]	# restore handles struct ptr
	xchg	eax, [esi + handles_ptr]	# eax = old ptr, to free later
	addd	[esi + handles_max], ALLOC_HANDLES

	# reserve a handle
	call	handle_get # in: esi; out: ebx; potential recursion
	# jc?
	mov	[esi + handles_idx], ebx	# otherwise unused
	mov	edi, esi
	mov	esi, [esi + handles_ptr]
	pop	dword ptr [esi + ebx + handle_size]	# the saved size
	mov	[esi + ebx + handle_base], esi
	mov	[esi + ebx + handle_caller], dword ptr offset handles_alloc$
	or	[esi + ebx + handle_flags], byte ptr MEM_FLAG_HANDLE #1 << 7
	mov	ecx, [edi + handles_max]
	add	edi, offset handles_ll_fa
	add	esi, offset handle_ll_el_addr
	call	ll_insert_sorted$	# in: esi, edi, ebx, ecx
	sub	esi, offset handle_ll_el_addr


	pop	esi

	# now mark the old memory region as free:
	or	eax, eax	# only applies to first time
	jz	1f
	call	handle_free_by_base	# see 1b for eax
1:

	# When we're here, the handles are set up properly, at least one
	# allocated for the handle structures themselves.

	pop_	edi ecx ebx eax
	ret


handles_validate_contiguous_address$:
	pushf
	push_	eax ebx ecx edx edi esi	# esi must be last
	mov	ecx, [esi + handles_num]
	or	ecx, ecx
	jz	9f
	mov	esi, [esi + handles_ptr]
	or	esi, esi
	jz	9f

	xor	ebx, ebx
0:
	mov	eax, [esi + ebx + handle_base]
	# check address prev
	mov	edi, [esi + ebx + handle_fa_prev]
	cmp	edi, -1
	jz	1f
	mov	edx, [esi + edi + handle_size]
or edx, edx
js 99f
	add	edx, [esi + edi + handle_base]
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

9:	pop_	esi edi edx ecx ebx eax
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
	call	handle_print_$
	lea	ebx, [esi + edi]
	call	handle_print_$
	printlnc 4,"-----------------------------";
	mov	esi, [esp]
	call	handles_print
	int 3
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
	call	handle_print_$
	lea	ebx, [esi + edi]
	call	handle_print_$
	printlnc 4,"-----------------------------";
	mov	esi, [esp]
	call	handles_print
99:	int 3
	sti
	jmp	9b


# in: esi = handles struct ptr
# in: eax = mem base ptr
# out: ebx = handle index
# out: CF
handle_get_by_base:
	push_	esi ecx

		.if HANDLE_ASSERT
			push_ edx edi
			mov edx, [esi + handles_num]
			HITO edx
			mov	edi, 0x1337c0de
		.endif

	mov	ecx, [esi + handles_num]
	jecxz	2f	# shouldn't happen
####
	mov	ebx, [esi + handles_ll_fa + ll_first]
	mov	esi, [esi + handles_ptr]

0:	cmp	ebx, -1
	jz	2f

		.if HANDLE_ASSERT
			cmp	ebx, edx
			jae	91f

			mov	edi, ebx
		.endif

	cmp	eax, [esi + ebx + handle_base]
	jz	3f
	mov	ebx, [esi + ebx + handle_fa_next]
	loop	0b
####
2:	stc
	mov	ebx, -1
3:
		.if HANDLE_ASSERT
			pop_ edi edx
		.endif

	pop_	ecx esi
	ret
		.if HANDLE_ASSERT
		91:	printc 4, "corrupt handle"
			DEBUG_DWORD ebx
			DEBUG_DWORD edx
			# inspect ebx (rel handle ptr), edi = prev handle ptr
			call	handle_print$
			int 3
			jmp	2b
		.endif

# in: esi = handles struct ptr
# in: ebx = handle index
# out: CF = 0: merged; ebx = new handle. CF=1: no merge, ebx is marked free.
handle_merge_fa$:
	push_	eax edx edi esi	# esi must be last
0:	xor	edi, edi

	# Check if ebx.base follows the previous handle AND is also free
	mov	esi, [esi + handles_ptr]
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
	add	[esi + eax + handle_size], edx

2:	# merge
	# empty ebx; size is already zero. 
	# remove from address list (and set address 0),
	# and remove from size list,
	# and add it to the free-handles list.

	# remove from the address list
	mov	[esi + ebx + handle_base], dword ptr 0
	mov	edi, [esp]	# handles struct ptr
	push	ecx
	mov	ecx, [edi + handles_max] # arg for insert_sorted
	add	edi, offset handles_ll_fa
	add	esi, offset handle_ll_el_addr
	call	ll_unlink$
	# add to the reusable handles list
	add	edi, offset handles_ll_fh - offset handles_ll_fa
	call	ll_insert_sorted$	# this does a loop on address, unneeded; call append instead?
	pop	ecx
	or	byte ptr [esi + ebx + handle_flags], MEM_FLAG_REUSABLE

MERGE_RECURSE = 0
	# eax's address list membership doesnt change.
	# eax's size address might have changed:
	mov	ebx, eax
.if MERGE_RECURSE
	sub	esi, offset handle_ll_el_addr
	mov	edi, -1	# loop
	jmp	0b
3:
.else
	add	esi, offset handle_ll_el_size - offset handle_ll_el_addr
.endif
	mov	edi, [esp]
	add	edi, offset handles_ll_fs
	# remove and insert:
	#call	ll_unlink$
	#call	ll_insert_sorted$
	# better: size has grown, so update right:
	call	ll_update_right$

	# leave ebx to point to the newly free'd memory.
	clc
0:	pop_	esi edi edx eax
	ret

1:	# no matches. mark memory as free.
.if MERGE_RECURSE
	cmp	edi, -1
	je	3b
.endif
	mov	edi, [esp]
	push	ecx
	mov	ecx, [edi + handles_max]
	add	edi, offset handles_ll_fs
	add	esi, offset handle_ll_el_size
	call	ll_insert_sorted$
	pop	ecx
	stc
	jmp	0b


# in: esi = handles struct ptr
# in: eax = base pointer
handle_free_by_base:
	push_	ebx
	call	handle_get_by_base
	jc	91f
	call	handle_free
0:	pop	ebx
	STACKTRACE 0
	ret
91:	printc 4, "handle_free_by_base: unknown pointer: "
	push	eax
	call	_s_printhex8
	call	newline
	stc
	jmp	0b

# in: ebx = handle index
# in: esi = handles struct
handle_free:
	push_	esi	# stackref
	mov	esi, [esi + handles_ptr]
	test	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jz	91f
	and	[esi + ebx + handle_flags], byte ptr ~MEM_FLAG_ALLOCATED
	# alt:
	# btc	[esi + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED_SHIFT
	# jnc	92f

##################
	mov	esi, [esp]	# handles struct ptr
	push	edi
	push	edx
	# this takes care of everything:
	call	handle_merge_fa$
	pop	edx
	pop	edi

	clc
##################

9:	pop_	esi
	STACKTRACE 0
	ret

91:	printc 4, "handle_free: pointer already free: "
	push	ebx
	call	_s_printhex8
	call	newline
	stc
	jmp	9b


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

.endif
