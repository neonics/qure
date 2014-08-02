#############################################################################
.intel_syntax noprefix

OOFS_HANDLE_DEBUG = 0

DECLARE_CLASS_BEGIN oofs_handle, oofs_persistent

oofs_handle_persistence:.long 0 # oofs_alloc instance
oofs_handle_handle:	.long 0	# oofs_alloc handle

oofs_handle_persistent_start: .long 0	# eax relative offset

DECLARE_CLASS_METHOD oofs_api_init, oofs_handle_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_handle_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_handle_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_handle_onload, OVERRIDE

DECLARE_CLASS_END oofs_handle
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs_alloc)
# in: ebx = oofs_alloc handle index
# out: ebx = fs handle index (for use with oofs_alloc_handle_*)
oofs_handle_init:
	# verify that the persistence is indeed oofs_alloc:
	push_	edx eax
	mov	eax, edx
	mov	edx, offset class_oofs_alloc
	call	class_instanceof
	pop_	eax edx
	jc	91f
	mov	[eax + oofs_handle_persistence], edx
	mov	[eax + oofs_handle_handle], ebx

	# calculate LBA, size
	push_	ebx ecx

	cmp	ebx, -1
	jnz	1f
	printc 0xf4, "handle -1"
	int 3
	# it's a dummy handle
	mov	ebx, -1
	mov	ecx, -1
	jmp	2f

1: 
	mov	ecx, [edx + oofs_alloc_handles + handles_ptr]
	add	ecx, ebx
	mov	ebx, [ecx + handle_base]
	mov	ecx, [ecx + handle_size]
	inc	ebx	# skip reserved sector
	add	ebx, [edx + oofs_lba]
	# in: ebx = LBA
	# in: ecx = reserved size

	.if OOFS_HANDLE_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_handle_init"
		printc 9, " handle="; pushd [esp+4]; call _s_printhex8
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif

2:	call	oofs_persistent_init	# super.init()
	pop_	ecx ebx

	xchg	eax, edx
	call	oofs_alloc_handle_register	# out: ebx = fs hndl idx
	xchg	eax, edx


9:	STACKTRACE 0
	ret

91:	printlnc 12, "oofs_handle_init: persistence not oofs_alloc"
	stc
	jmp	9b


# utility method: calculates and sets lba and size
# XXX TODO move to oofs_alloc as get_geo, out: ebx, ecx
# in: eax = this
# in: ebx = handle index
handle_set_geo$:
	push_	esi edx ecx ebx
	mov	edx, [eax + oofs_handle_persistence]	# oofs_alloc
	mov	esi, [edx + oofs_alloc_handles + handles_ptr]
	add	esi, ebx
	mov	ebx, [esi + handle_base]
	mov	ecx, [esi + handle_size]
	inc	ebx	# skip reserved sector
	add	ebx, [edx + oofs_lba]

	mov	[eax + oofs_lba], ebx
	mov	[eax + oofs_sectors], ecx
	pop_	ebx ecx edx esi
	ret


oofs_handle_load:
	.if OOFS_HANDLE_DEBUG
		DEBUG_CLASS
		printlnc 14, ".oofs_handle_load"
	.endif
	push_	ecx edx edi
	# get the persisted handle size in sectors
	mov	ecx, [eax + oofs_handle_persistence]
	mov	ecx, [ecx + oofs_alloc_handles + handles_ptr]
	add	ecx, [eax + oofs_handle_handle]
	mov	ecx, [ecx + handle_caller]	# initialized sectors
	shl	ecx, 9
	jnz	1f
	mov	ecx, 512	# read at least 1 sector
1:
	mov	edx, [eax + oofs_handle_persistent_start]
	lea	edi, [eax + edx]
	INVOKEVIRTUAL oofs_persistent read
	jc	1f
	# recalculate edi
	lea	edi, [eax + edx]
	INVOKEVIRTUAL oofs_persistent onload
1:	pop_	edi edx ecx
	STACKTRACE 0
	ret
	# TODO: onload: read rest.

oofs_handle_onload:
	.if OOFS_HANDLE_DEBUG
		PRINT_CLASS
		DEBUG ".onload", 14
		DEBUG_DWORD edi, "data", 9, 7
		DEBUG_DWORD [eax + oofs_handle_persistent_start], "persistent_start", 9, 7
		call	newline
	.endif
	# XXX TODO load rest
	clc
	ret

oofs_handle_save:
	.if OOFS_HANDLE_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_handle_save"
	.endif
	push_	eax ebx edx esi	# esp ref!
	# assume the persistent part is the tail end of the object
	mov	ecx, [eax + obj_size]
	mov	edx, [eax + oofs_handle_persistent_start]
	sub	ecx, edx
	DEBUG_DWORD ecx, "oofs_handle_size"

	# if the size won't fit, reallocate the handle
	push	ecx	# esp ref!
	add	ecx, 511
	shr	ecx, 9
	cmp	[eax + oofs_sectors], ecx	# copied from handle
	jae	1f
	# we need to realloc a handle.
	mov	esi, eax	# backup this
	mov	eax, [eax + oofs_handle_persistence]
	# XXX TODO add oofs_alloc.resize which may optimize
	INVOKEVIRTUAL oofs_alloc alloc	# out: ebx
	jc	1f
	xchg	ebx, [esi + oofs_handle_handle]
	INVOKEVIRTUAL oofs_alloc free	# in: ebx
	jc	1f
	# update handle, lba, and size
	mov	eax, esi	# restore this
	mov	ebx, [eax + oofs_handle_handle]
	call	handle_set_geo$

	# update the handle's persisted size
	push_	esi ecx
	mov	esi, [eax + oofs_handle_persistence] # oofs_alloc
	mov	esi, [esi + oofs_alloc_handles + handles_ptr]
	add	esi, ebx
	# ecx is still good I think
	mov	[esi + handle_caller], ecx
	# handles are changed; to remain consistent, save:
	mov	ecx, eax
	mov	eax, [eax + oofs_handle_persistence]
	INVOKEVIRTUAL oofs_persistent save
	mov	eax, ecx

	pop_	ecx esi

	clc

1:	pop	ecx
	jc	91f

	lea	esi, [eax + edx]
	INVOKEVIRTUAL oofs_persistent write

	pop_	esi edx ebx eax
9:	STACKTRACE 0
	ret
91:	printlnc 12, "oofs_handle_save: error reallocating diskspace"
	stc
	jmp	0b
