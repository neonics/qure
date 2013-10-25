#############################################################################
.intel_syntax noprefix
#
# persistent lib/mem_handle.s
#

.global class_oofs_alloc_tbl

.if HANDLE_STRUCT_SIZE == 32
HANDLE_STRUCT_SIZE_SHIFT = 5
.else
.error "HANDLE_STRUCT_SIZE != 32 unimplemented"
.endif

DECLARE_CLASS_BEGIN oofs_alloc_tbl, oofs_array

oofs_alloc_tbl_persistent:	# local separator, for subclasses to use.

oofs_alloc_tbl_ll:
oofs_alloc_tbl_addr_first:	.long 0	# linked-list
oofs_alloc_tbl_addr_last:	.long 0	# linked-list
oofs_alloc_tbl_size_first:	.long 0	# linked-list
oofs_alloc_tbl_size_last:	.long 0	# linked-list
oofs_alloc_tbl_hndl_first:	.long 0	# linked-list
oofs_alloc_tbl_hndl_last:	.long 0	# linked-list

oofs_alloc_tbl_handles:
oofs_alloc_tbl_hndl_count:	.long 0


DECLARE_CLASS_METHOD oofs_api_init, oofs_alloc_tbl_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_alloc_tbl_print, OVERRIDE
DECLARE_CLASS_METHOD oofs_array_api_print_el, oofs_alloc_tbl_print_el, OVERRIDE

#DECLARE_CLASS_METHOD oofs_table_api_add, oofs_alloc_tbl_add, OVERRIDE
#DECLARE_CLASS_METHOD oofs_table_api_get_obj, oofs_alloc_tbl_get_obj, OVERRIDE
#DECLARE_CLASS_METHOD oofs_table_api_lookup, oofs_alloc_tbl_lookup, OVERRIDE
DECLARE_CLASS_END oofs_alloc_tbl
#super = oofs_api_init
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs)
# in: ebx = LBA
# in: ecx = reserved size
oofs_alloc_tbl_init:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_alloc_tbl_init", 0xe0
		DEBUG_DWORD ebx, "LBA"
		DEBUG_DWORD ecx, "size"
		push edx; mov edx,[esp+4]; call debug_printsymbol; pop edx
		call	newline
	.endif
	movb	[eax + oofs_array_shift], HANDLE_STRUCT_SIZE_SHIFT
	mov	[eax + oofs_array_start], dword ptr offset oofs_alloc_tbl_handles
	mov	[eax + oofs_array_persistent_start], dword ptr offset oofs_alloc_tbl_persistent
	call	oofs_persistent_init	# super.init()

	# clear linked list
	push_	edi eax ecx
	lea	edi, [eax + oofs_alloc_tbl_ll]
	mov	eax, -1
	mov	ecx, 2 * 3
	rep	stosd
	pop_	ecx eax

	call	oofs_alloc_tbl_handle_get

	# add free handle
	lea	edi, [eax + oofs_alloc_tbl_handles + 0 * HANDLE_STRUCT_SIZE]
	mov	[edi + handle_flags], byte ptr 0	# free
	mov	[edi + handle_size], ecx
	mov	[edi + handle_fs_next], dword ptr -1
	mov	[edi + handle_fs_prev], dword ptr -1
	pop	edi
	ret


oofs_alloc_tbl_handle_get:
	ret

oofs_alloc_tbl_get_size$:
	mov	ecx, [eax + oofs_alloc_tbl_hndl_count]
	shl	ecx, HANDLE_STRUCT_SIZE_SHIFT
	add	ecx, offset oofs_alloc_tbl_handles - oofs_alloc_tbl_persistent
	ret


# in: eax = this (oofs instance)
# in: ecx = bytes
# in: edx = class def ptr
# out: eax = instance
oofs_alloc_tbl_add:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_alloc_tbl_add", 0xe0
		DEBUG_DWORD ecx
		DEBUG_DWORD [eax+oofs_alloc_tbl_hndl_count],"table size"
		call	newline
	.endif

	push_	ebx esi
	mov	ebx, eax
	mov	esi, [eax + oofs_alloc_tbl_hndl_count]

	#call	[eax + oofs_persistent_api_save]

0:	pop_	esi ebx
	ret


oofs_alloc_tbl_print_el:
	ret


# OK
oofs_alloc_tbl_print:
	STACKTRACE 0,0
	call	oofs_persistent_print

	push_	esi ecx eax edx
	printc 11, " table size "
	call	oofs_alloc_tbl_get_size$
	mov	edx, ecx
	call	printhex8
	add	edx, 511
	shr	edx, 9
	printc 11, " ("
	call	printdec32
	printlnc 11, " sectors)"

	lea	esi, [eax + oofs_alloc_tbl_handles]
	mov	ecx, [eax + oofs_alloc_tbl_hndl_count]
	or	ecx, ecx
	jz	9f
	mov	edx, ecx
	printc 11, "Handles: "
	call	printdec32
	printc 11, " addr("
	mov	edx, [eax + oofs_alloc_tbl_addr_first]
	call	printdec32
	printc 11, ", "
	mov	edx, [eax + oofs_alloc_tbl_addr_last]
	call	printdec32

	printc 11, ") size("
	mov	edx, [eax + oofs_alloc_tbl_size_first]
	call	printdec32
	printc 11, ", "
	mov	edx, [eax + oofs_alloc_tbl_size_last]
	call	printdec32

	printc 11, ") hndl("
	mov	edx, [eax + oofs_alloc_tbl_hndl_first]
	call	printdec32
	printc 11, ", "
	mov	edx, [eax + oofs_alloc_tbl_hndl_last]
	call	printdec32
	printlnc 11, ")"

	printlnc 15, "..base.. ..prev.. ..next.. ..size.. ..prev.. ..next.. fl"

	push	eax
0:	mov	edx, [esi + handle_base]
	call	printhex8
	call	printspace
	mov	edx, [esi + handle_fa_prev]
	call	printhex8
	call	printspace
	mov	edx, [esi + handle_fa_next]
	call	printhex8
	call	printspace

	mov	edx, [esi + handle_size]
	call	printhex8
	call	printspace
	mov	edx, [esi + handle_fs_prev]
	call	printhex8
	call	printspace
	mov	edx, [esi + handle_fs_next]
	call	printhex8
	call	printspace

	mov	dl, [esi + handle_flags]
	call	printhex2
	call	newline

	add	esi, HANDLE_STRUCT_SIZE
	loop	0b
	pop	eax

9:	pop_	edx eax ecx esi
	ret
91:	printlnc 4, " unknown class"
	jmp	9b

