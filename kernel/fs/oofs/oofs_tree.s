#############################################################################
.intel_syntax noprefix

.global oofs_tree_api_next
.global oofs_tree_api_add

DECLARE_CLASS_BEGIN oofs_tree, oofs_handle

oofs_tree_persistent_start:
oofs_tree_size:	.long 0	# total occupied space
oofs_tree_entries:

DECLARE_CLASS_METHOD oofs_api_init, oofs_tree_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_tree_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_tree_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_tree_onload, OVERRIDE

DECLARE_CLASS_METHOD oofs_tree_api_next, oofs_tree_next
DECLARE_CLASS_METHOD oofs_tree_api_add, oofs_tree_add

DECLARE_CLASS_END oofs_tree
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs_alloc)
# in: ebx = oofs_alloc handle index
oofs_tree_init:
	.if OOFS_DEBUG
		pushf
		PRINT_CLASS
		printc 14, ".oofs_tree_init"
		printc 9, " handle=";  push ebx; call _s_printhex8
		call	newline
		popf
	.endif
	call	oofs_handle_init	# super.init()
	ret

91:	printlnc 12, "oofs_tree_init: persistence not oofs_alloc"
	stc
	ret

oofs_tree_load:
	push_	ecx edx edi
	mov	ecx, 512
	mov	edx, offset oofs_tree_persistent_start
	lea	edi, [eax + edx]
	call	[eax + oofs_persistent_api_read]
	jc	1f
	# recalculate edi
	lea	edi, [eax + edx]
	INVOKEVIRTUAL oofs_persistent onload
1:	pop_	edi edx ecx
	STACKTRACE 0
	ret
	# TODO: onload: read rest.

oofs_tree_onload:
	.if 0
		PRINT_CLASS
		printc 14, ".onload"
		DEBUG_DWORD [eax + oofs_tree_size]
		push edx; lea edx, [eax + oofs_tree_persistent_start]
		DEBUG_DWORD edx
		pop edx
		call	newline
	.endif
	clc
	ret

oofs_tree_save:
	push_	ecx edx esi
	mov	ecx, [eax + oofs_tree_size]
	add	ecx, 4	# the size dword itself
	mov	edx, offset oofs_tree_persistent_start
	lea	esi, [eax + edx]
	call	[eax + oofs_persistent_api_write]
	pop_	esi edx ecx
	STACKTRACE 0
	ret


# in: eax = this
# in: ecx = entry offset
# out: edx = entry pointer
# out: ecx = next entry offset or -1 if current entry doesnt exist
# XXX for now, entries are FS_DIRENT_STRUCT_SIZE constant length,
# otherwise ecx might need to contain the current entry, and have
# the caller increment ecx.
oofs_tree_next:
	# check if the current entry exists
	lea	edx, [ecx + oofs_tree_persistent_start + FS_DIRENT_STRUCT_SIZE]
	cmp	edx, [eax + obj_size]
	jae	91f

	lea	edx, [ecx + FS_DIRENT_STRUCT_SIZE]
	cmp	edx, [eax + oofs_tree_size]
	ja	91f

	# check posix perm (or check first byte of name)
	lea	edx, [eax + oofs_tree_entries + ecx]
	cmpd	[edx + fs_dirent_posix_perm], 0
	jz	91f
	add	ecx, FS_DIRENT_STRUCT_SIZE
	ret

# cur entry doesn't exist
91:	mov	ecx, -1
	ret


# in: eax = this
# in: edx = fs_dirent to be added
oofs_tree_add:
	.if 0
		DEBUG "oofs_tree_add: "
		push	esi
		lea	esi, [edx + fs_dirent_name]
		call	println
		pop	esi
	.endif

	push_	edx
	# calc needed object size
	mov	edx, FS_DIRENT_STRUCT_SIZE + offset oofs_tree_entries
	cmp	[eax + obj_size], edx
	jnb	1f
	call	oofs_persistent_resize
1:	pop	edx
	jc	91f

	push_	edi ecx esi
	mov	edi, [eax + oofs_tree_size]
	lea	edi, [eax + oofs_tree_entries + edi]
	mov	esi, edx
	mov	ecx, FS_DIRENT_STRUCT_SIZE >> 2
	rep	movsd
	mov	cl, FS_DIRENT_STRUCT_SIZE & 3
	rep	movsb
	addd	[eax + oofs_tree_size], FS_DIRENT_STRUCT_SIZE
	pop_	esi ecx edi

	# let's save.

#	INVOKEVIRTUAL oofs_persistent save

	push_	eax ebx edx
	mov	ebx, [eax + oofs_handle_handle]
	mov	edx, eax
	mov	eax, [eax + oofs_handle_persistence]
	INVOKEVIRTUAL oofs_alloc handle_save	# updates initialized size
	pop_	edx ebx eax

9:	STACKTRACE 0
	ret

91:	stc
	jmp	9b
