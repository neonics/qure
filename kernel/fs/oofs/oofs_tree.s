#############################################################################
.intel_syntax noprefix

OOFS_TREE_DEBUG = 0


TREE_ENTRY_SIZE = (FS_DIRENT_STRUCT_SIZE + 4)	# 4: handle index

.struct 0
.space FS_DIRENT_STRUCT_SIZE
tree_entry_handle:	.long 0

#####

.global oofs_tree_api_next
.global oofs_tree_api_add

DECLARE_CLASS_BEGIN oofs_tree, oofs_handle

oofs_tree_persistent_start:
oofs_tree_size:	.long 0	# total occupied space
oofs_tree_entries:

DECLARE_CLASS_METHOD oofs_api_init, oofs_tree_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_tree_print, OVERRIDE

#DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_tree_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_tree_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_tree_onload, OVERRIDE

DECLARE_CLASS_METHOD oofs_tree_api_next, oofs_tree_next
DECLARE_CLASS_METHOD oofs_tree_api_add, oofs_tree_add
DECLARE_CLASS_METHOD oofs_tree_api_find_by_name, oofs_tree_find_by_name

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
	mov	[eax + oofs_handle_persistent_start], dword ptr offset oofs_tree_persistent_start
	call	oofs_handle_init	# super.init()
	ret

91:	printlnc 12, "oofs_tree_init: persistence not oofs_alloc"
	stc
	ret

.if 0
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
.endif
	# TODO: onload: read rest.

oofs_tree_onload:
	.if OOFS_TREE_DEBUG
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
	.if OOFS_TREE_DEBUG
		PRINT_CLASS
		printc 14, "oofs_tree_save"
	.endif

	push_	edx ebx edi
########
	# set up edx=HEAD, ebx=this handle
	push	eax
	mov	eax, [eax + oofs_handle_persistence]
	mov	edx, -1
	INVOKEVIRTUAL oofs_alloc txtab_get
	jc	1f
	mov	edi, eax	# backup txtab for set later
	mov	edx, ebx
	xor	ebx, ebx
	INVOKEVIRTUAL oofs_txtab get	# get entry 0
	mov	edx, -1
	jc	1f
	mov	edx, ebx
1:	pop	eax
	mov	ebx, [eax + oofs_handle_handle]	# remember for change event
	# now, edx = txtab[0], and ebx is this handle
########

	call	oofs_handle_save	# explicit super call
	jc	9f

########
	# check if ebx is the root dir
	cmp	ebx, edx
	clc
	jnz	9f
	# match: update.
	xor	ebx, ebx
	mov	edx, [eax + oofs_handle_handle] # new handle
	push	eax
	mov	eax, edi
	INVOKEVIRTUAL oofs_txtab set
	# now also save the txtab
	mov	eax, [esp]
	mov	eax, [eax + oofs_handle_persistence]
	INVOKEVIRTUAL oofs_alloc txtab_save
	pop	eax
########
9:	pop_	edi ebx edx
	STACKTRACE 0
	ret


# in: eax = this
# in: ecx = entry offset
# out: edx = entry pointer
# out: ecx = next entry offset or -1 if current entry doesnt exist
# XXX for now, entries are (FS_DIRENT_STRUCT_SIZE+4) constant length,
# otherwise ecx might need to contain the current entry, and have
# the caller increment ecx.
oofs_tree_next:
	# check if the current entry exists
	lea	edx, [ecx + oofs_tree_persistent_start + TREE_ENTRY_SIZE]
	cmp	edx, [eax + obj_size]
	ja	91f

	lea	edx, [ecx + TREE_ENTRY_SIZE]
	cmp	edx, [eax + oofs_tree_size]
	ja	91f

	# check posix perm (or check first byte of name)
	lea	edx, [eax + oofs_tree_entries + ecx]
	cmpd	[edx + fs_dirent_posix_perm], 0
	jz	91f
	add	ecx, TREE_ENTRY_SIZE
	ret

# cur entry doesn't exist
91:	mov	ecx, -1
	stc
	ret


# in: eax = this
# in: edx = fs_dirent to be added
oofs_tree_add:
	.if OOFS_TREE_DEBUG
		DEBUG "oofs_tree_add: "
		push	esi
		lea	esi, [edx + fs_dirent_name]
		call	println
		pop	esi
	.endif

	push_	edx
	# calc needed object size
	mov	edx, TREE_ENTRY_SIZE + offset oofs_tree_entries
	cmp	[eax + obj_size], edx
	jnb	1f
	call	oofs_persistent_resize
1:	pop	edx
	jc	91f

	# append *edx
	push_	edi ecx esi
	mov	edi, [eax + oofs_tree_size]
	lea	edi, [eax + oofs_tree_entries + edi]
	mov	esi, edx
	mov	ecx, FS_DIRENT_STRUCT_SIZE >> 2
	rep	movsd
	mov	cl, FS_DIRENT_STRUCT_SIZE & 3
	rep	movsb
	mov	[edi], dword ptr -1	# handle index
	addd	[eax + oofs_tree_size], TREE_ENTRY_SIZE
	pop_	esi ecx edi

	# let's save.
DEBUG "save"
DEBUG_DWORD [eax+oofs_handle_handle],"pre handle"
	INVOKEVIRTUAL oofs_persistent save
	jc	9f

DEBUG_DWORD [eax+oofs_handle_handle],"post handle"
		call newline
		DEBUG "TREE:",0xf0; call newline
		call	oofs_tree_print
		clc

9:	STACKTRACE 0
	ret

91:	printlnc 12, "oofs_tree_add: resize error"
	stc
	jmp	9b



# in: eax = this
# in: esi = entry name
# out: esi = tree entry (fs_dirent + handle idx)
# out: ebx = handle index (to prevent exposure of tree_entry_handle)
# out: CF
oofs_tree_find_by_name:
	push_	ecx edx edi ebx esi # ebx,esi need to be last!

	call	strlen_	# esi->ecx
	lea	ebx, [ecx + 1]	# also cmp trailing 0

	xor	ecx, ecx
0:	call	oofs_tree_next
	jc	0f

	lea	edi, [edx + fs_dirent_name]
	push_	ecx
	mov	ecx, ebx
	repz	cmpsb
	pop_	ecx
	mov	esi, [esp]
	jnz	0b
	mov	esi, edx
	mov	ecx, [edx + tree_entry_handle]
	mov	[esp+4], ecx	# ebx return value
0:
	pop_	esi ebx edi edx ecx
	ret


oofs_tree_print:
	printc 11, "oofs_tree: "
	printc 9, "handle: "
	pushd	[eax + oofs_handle_handle]
	shr	dword ptr [esp], HANDLE_STRUCT_SIZE_SHIFT
	call	_s_printhex8

	printc 9, " size: "
	pushd	[eax + oofs_tree_size]
	call	_s_printhex8
	call	newline

	push_	ecx esi edx
	lea	esi, [eax + oofs_tree_entries]
	mov	ecx, [eax + oofs_tree_size]
0:	sub	ecx, TREE_ENTRY_SIZE
	jb	0f
	
	call	fs_dirent_print

	add	esi, TREE_ENTRY_SIZE
	jmp	0b
0:
	pop_	edx esi ecx


	ret
