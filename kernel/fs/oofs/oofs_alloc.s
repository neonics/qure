#############################################################################
.intel_syntax noprefix
#
# persistent lib/mem_handle.s
#

.global class_oofs_alloc_tbl

DECLARE_CLASS_BEGIN oofs_alloc_tbl, oofs_persistent#, offs=oofs_persistent

oofs_alloc_tbl_persistent:	# local separator, for subclasses to use.
oofs_alloc_tbl_hndl_count:	.long 0

oofs_alloc_tbl_addr_first:	.long 0	# linked-list
oofs_alloc_tbl_addr_last:	.long 0	# linked-list
oofs_alloc_tbl_size_first:	.long 0	# linked-list
oofs_alloc_tbl_size_last:	.long 0	# linked-list
oofs_alloc_tbl_hndl_first:	.long 0	# linked-list
oofs_alloc_tbl_hndl_last:	.long 0	# linked-list

oofs_alloc_tbl_handles:

.org oofs_alloc_tbl_persistent + 512	# make struct size at least 1 sector
oofs_alloc_tbl_persistent_end:

DECLARE_CLASS_METHOD oofs_api_init, oofs_alloc_tbl_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_alloc_tbl_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_alloc_tbl_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_alloc_tbl_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_alloc_tbl_onload, OVERRIDE

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
	call	oofs_persistent_init	# super.init()

#	mov	[eax + oofs_parent], edx	# super field ref
#	mov	[eax + oofs_lba], ebx
#	mov	[eax + oofs_size], ecx
#	push	edx
#	mov	edx, [edx + oofs_persistence]
#	mov	[eax + oofs_persistence], edx
#	pop	edx

	# initialize the handles:
	push	edi
	lea	edi, [eax + oofs_alloc_tbl_handles + 0 * HANDLE_STRUCT_SIZE]
	mov	[edi + handle_flags], byte ptr 0	# free
	mov	[edi + handle_size], ecx
	mov	[edi + handle_fs_next], dword ptr -1
	mov	[edi + handle_fs_prev], dword ptr -1
	pop	edi
	ret

oofs_alloc_tbl_get_size$:
	mov	ecx, [eax + oofs_alloc_tbl_hndl_count]
	.if HANDLE_STRUCT_SIZE == 32
	shl	ecx, 5
	add	ecx, offset oofs_alloc_tbl_handles - oofs_alloc_tbl_persistent
	.else
	.error "HANDLE_STRUCT_SIZE != 32 not implemented"
	.endif
	ret


# aspect extension: pre & post
oofs_alloc_tbl_save:
	push_	ecx esi edx ebx eax
	call	oofs_alloc_tbl_get_size$	# out: ecx = bytes
	lea	esi, [eax + oofs_alloc_tbl_persistent]
	mov	ebx, [eax + oofs_lba]
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_alloc_tbl_save", 0xe0
		DEBUG_DWORD ebx,"LBA"
		DEBUG_DWORD ecx,"bytes"
		call newline
	.endif
	mov	edx, [eax + obj_class]
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_write]
	pop_	eax ebx edx esi ecx
	ret

#don't do partition magic checking.
oofs_alloc_tbl_onload:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG " ***** onload "
		DEBUG_DWORD [eax + oofs_alloc_tbl_hndl_count]
		call	newline
	.endif
	clc
	ret

oofs_alloc_tbl_load:
	push_	ebx ecx edi edx esi
	lea	edi, [eax + oofs_alloc_tbl_persistent]
	mov	ebx, [eax + oofs_lba]	# 0
	call	oofs_alloc_tbl_get_size$	# out: ecx = bytes
	cmp	ecx, 512	# precondition: var obj data = 512
	jbe	1f
	mov	edx, ecx
	call	class_instance_resize
	jc	9f
1:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_alloc_tbl_load", 0xd0
		DEBUG_DWORD ebx, "LBA"
		DEBUG_DWORD ecx, "size"
	.endif
	push	eax
	mov	edx, [eax + obj_class]
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f
	call	[eax + oofs_persistent_api_onload]

9:	pop_	esi edx edi ecx ebx
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

	# first add the string
	pushd	[edx + class_name]
	call	addstring$
	jc	91f

	push_	ebx esi
	mov	ebx, eax
	mov	esi, [eax + oofs_alloc_tbl_hndl_count]
	mov	eax, [eax + oofs_parent]	# add to parent
	call	[eax + oofs_vol_add]	# out: eax
	jc	92f

	xchg	eax, ebx	# restore
	call	oofs_alloc_tbl_save
	mov	eax, ebx	# return value
	#jnc	0f; call class_deleteinstance....

0:	pop_	esi ebx
	ret

91:	printlnc 4, "oofs_alloc_tbl_add: addstring fail"
	stc
	ret
92:	printlnc 4, "oofs_alloc_tbl_add: oofs_add fail"
	mov	[ebx + oofs_alloc_tbl_hndl_count], esi	# rollback
	mov	eax, ebx
	stc
	jmp	0b

# iteration method
# in: eax = this
# in: edx = class
# in: ebx = counter - set to 0 for first in list
# out: CF: counter invalid
# out: eax = object (if CF=0)
oofs_alloc_tbl_get_obj:
	# we don't have parent array children and such..
	stc
	ret


# find by class
# in: eax = this
# in: edx = class
# in: ebx = counter (0 for start)
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ecx = index in parent table (ecx since oofs_load_entry expects it)
# (xxxxout: ebx = next counter / -1
# (xxxx out: eax = object instance matching class edx (preserved on err)
oofs_alloc_tbl_lookup:
	stc
	ret


# OK
oofs_alloc_tbl_print:
	push_	esi ecx eax edx
	printc 11, "Object: "
	mov	edx, eax
	call	printhex8
	mov	edx, eax
	mov	eax, [eax + obj_class]
	call	class_is_class
	jc	91f
	xchg	eax, edx
	mov	esi, [edx + class_name]
	call	printspace
	call	print
	printc 11, " table size "
	call	oofs_alloc_tbl_get_size$
	mov	edx, eax
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

