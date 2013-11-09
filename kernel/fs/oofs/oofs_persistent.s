#############################################################################
.intel_syntax noprefix

###############################################################################

.global class_oofs_persistent
# fields
.global oofs_lba
.global oofs_size
.global oofs_persistence
#.global oofs_persistent

# static methods
.global oofs_persistent_init
# virtual methods
.global oofs_persistent_api_read
.global oofs_persistent_api_write

.global oofs_persistent_api_resize
# abstract methods
.global oofs_persistent_api_load
.global oofs_persistent_api_onload
.global oofs_persistent_api_save

DECLARE_CLASS_BEGIN oofs_persistent, oofs
oofs_persistence:.long 0 # nonpersistent: fs_oofs (same as parent for root obj)
oofs_flags:	.long 0
	OOFS_FLAG_DIRTY = 1

oofs_lba:	.long 0	# for subclasses
oofs_sectors:	# alias for oofs_size
oofs_size:	.long 0

DECLARE_CLASS_METHOD oofs_api_init, oofs_persistent_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_persistent_print, OVERRIDE
# extension:

# load first sector
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_load
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_onload	#event handler
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_save
DECLARE_CLASS_METHOD oofs_persistent_api_resize, oofs_persistent_resize

DECLARE_CLASS_METHOD oofs_persistent_api_read, oofs_persistent_read
DECLARE_CLASS_METHOD oofs_persistent_api_write, oofs_persistent_write
DECLARE_CLASS_END oofs_persistent
#################################################
.text32
# in: eax = instance
# in: edx = parent instance: either class_fs or class_oofs_persistent
# in: ebx = lba
# in: ecx = persistent size (sectors)
oofs_persistent_init:
	# hardcoded (nonvirtual) call to super.init()
	call	oofs_init	# edx is verified to be a class
	jc	91f		# not a class, so does not provide persistence

	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_persistent_init"
		printc 9, " parent="
		DEBUG_CLASS edx
	.endif

####### local initialisation

	# verify edx is an instance of fs_obj
	push	edx

	push_	eax
	mov	eax, edx
	mov	edx, offset class_fs
	call	class_instanceof
	pop_	eax
	mov	edx, [esp]
	jnc	1f

	# check if instanceof oofs_persistent
	push_	eax
	mov	eax, edx
	mov	edx, offset class_oofs_persistent
	call	class_instanceof
	pop_	eax
	jc	91f

	mov	edx, [esp]

	mov	edx, [edx + oofs_persistence]

1:	mov	[eax + oofs_persistence], edx
	mov	[eax + oofs_lba], ebx
	mov	[eax + oofs_size], ecx

	.if OOFS_DEBUG
		printc 9, " persistence="
		DEBUG_CLASS edx
		call newline
	.endif
	clc
0:	pop	edx
	STACKTRACE 0
	ret

91:	printlnc 4, "oofs_persistent_init: parent does not provide persistence"
	stc
	jmp	0b

# This method is given the start of an object's persistent data, and
# the start and size of the data to save, making it possible to save
# only a partial region of the object's persistent data.
#
# This class does not know the start of subclasses persistent data, nor
# their ending, and thus requires to be passed the start. The ending is
# inferred from the object instance size.
#
# in: eax = this
# in: edx = start of persistent data (eax relative)
# in: esi = start of data to save (abs)
# in: ecx = size of data to save
oofs_persistent_write:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 13, ".oofs_persistent_write"
		printc 9, " region(LBA="; pushd [eax + oofs_lba]; call _s_printhex8
		printc 9, " sectors="; pushd [eax + oofs_sectors]; call _s_printhex8
		printc 9, ") size="; pushd ecx; call _s_printhex8
		call	newline
	.endif
	push_	eax ebx ecx edx esi edi

	.if OOFS_DEBUG > 2
		call newline
		push_ esi ecx eax edx
		mov ecx, 80 / 3
		0: lodsb; mov dl, al; call printhex2; call printspace; loop 0b
		call newline
		pop_ edx eax ecx esi
	.endif

	# verify edx
	cmp	edx, oofs_persistent_STRUCT_SIZE
	jb	91f

	# verify esi, ecx within object size
	sub	esi, eax	# make obj relative
	sub	esi, edx	# check if after persistence start
	jb	92f
	mov	edi, [eax + obj_size]
	sub	edi, oofs_persistent_STRUCT_SIZE	# edi = max psts size
	jle	93f	# jl shouldn't happen
	cmp	ecx, edi
	ja	94f

	# esi = edx relative (edx=eax relative)

	# calculate sector offset for partial saving
	mov	edi, esi
	shr	edi, 9
	mov	ebx, ecx
	add	ebx, 511
	shr	ebx, 9
	add	ebx, edi
	cmp	ebx, [eax + oofs_sectors]
	ja	95f

	mov	esi, [esp + 4]	# restore esi

	.if OOFS_DEBUG > 2
		call newline
		push_ esi ecx eax edx
		mov ecx, 80 / 3
		0: lodsb; mov dl, al; call printhex2; call printspace; loop 0b
		call newline
		pop_ edx eax ecx esi
	.endif

	mov	ebx, [eax + oofs_lba]
	add	ebx, edi	# sector offset
	mov	edx, eax
	mov	eax, [eax + oofs_persistence]
	.if OOFS_DEBUG
		printc 9, " LBA="
		push	ebx
		call	_s_printhex8
		printc 9, " size="
		push	ecx
		call	_s_printhex8
	.endif
	call	[eax + fs_obj_api_write]
	.if OOFS_DEBUG
	jc	0f
	OK
	.endif
0:	pop_	edi esi edx ecx ebx eax
	STACKTRACE 0
	ret

90:	printc 4, "oofs_write: "
	call	_s_println
	stc
	jmp	0b

91:	PUSH_TXT "persistent start overlaps with volatile data"
	jmp	90b
92:	PUSH_TXT "data start before persistent start"
	jmp	90b
93:	PUSH_TXT "object tail empty"
	jmp	90b
94:	PUSH_TXT "data size exceeds object size"
	jmp	90b
95:	PUSH_TXT "data exceeds partition"
	DEBUG_DWORD ebx; DEBUG_DWORD [eax+oofs_sectors]
	jmp	90b

# For now, this method does not support partial data loading.
#
# in: eax = instance
# in: edi = start of persistent data offset in object
# in: ecx = bytes to load
# out: eax = mreallocced instance if needed
oofs_persistent_read:
	.if OOFS_DEBUG
		push_	eax edx
		DEBUG_CLASS
		printc 14, ".oofs_persistent_read"
		printc 9, " bytes="
		mov	edx, ecx
		call	printhex8

		.if OOFS_DEBUG > 1
			printc 9, " parent="
			mov	edx, [eax + oofs_parent]
			DEBUG_CLASS edx
			printc 9, " persistence="
			mov	eax, [eax + oofs_persistence]
			DEBUG_CLASS eax
			call newline
		.endif

		pop_	edx eax
	.endif

	push_	ebx ecx edx esi edi	# same as oofs_write!
	# verify edi
	mov	edx, edi
	sub	edx, eax	# edx = min obj size
	jle	93f
	cmp	edx, oofs_persistent_STRUCT_SIZE
	jb	93f
	add	edx, ecx
	add	edx, 511
	and	edx, ~511
	cmp	edx, [eax + obj_size]
	jbe	1f
	# resize
	sub	edi, eax
	call	[eax + oofs_persistent_api_resize]	# in/out: eax
	jc	92f
	add	edi, eax
1:
	# if edx indicates persistence start (and is preserved above), then:
	# calculate start sector, add ebx to it. (but not implemented)
	#lea	edi, [eax + oofs_persistent]
	#mov	ecx, 512
	mov	ebx, [eax + oofs_lba]

	.if OOFS_DEBUG
		.if OOFS_DEBUG > 1
		printc 9, "  LBA="
		.else
		printc 9, " LBA="
		.endif
		push ebx; call _s_printhex8
		printc 9, " size="
		push ecx; call _s_printhex8
		call printspace
	.endif

	push	eax
	mov	edx, eax
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	91f
	.if OOFS_DEBUG
	OK
	.endif

0:	pop_	edi esi edx ecx ebx
	STACKTRACE 0
	ret

90:	printc 4, "oofs_persistent_read: "
	call	_s_println
	stc
	jmp	0b

91:	PUSH_TXT "fs_obj_api_read error"
	jmp	0b
92:	PUSH_TXT "resize error"
	jmp	0b
93:	PUSH_TXT "persistent start overlaps with volatile data"
	jmp	90b

# in: eax = this
# in: edx = new size
# out: eax = this, reallocated
oofs_persistent_resize:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_persistent_resize"
		DEBUG_DWORD eax
		DEBUG_DWORD edx
		STACKTRACE 0,0
	.endif
	push_	ebx edx
	mov	ebx, eax
	call	class_instance_resize	# out: eax
	jc	9f

	mov	edx, ebx	# old
	mov	ebx, eax	# new
	mov	eax, [eax + oofs_parent]
	push	edx
	mov	edx, offset class_oofs
	call	class_instanceof	# out: CF=!ZF
	pop	edx
	clc		# prevent stacktrace
	jnz	9f	# not class_oofs: don't call method
	call	[eax + oofs_api_child_moved]
	clc
9:	mov	eax, ebx	# restore new
	pop_	edx ebx
	STACKTRACE 0
	ret

###########################################################################

# Override these methods
oofs_onload:
	# no warning - not required
	ret

oofs_load:
	printc 0xf4, "WARNING: oofs_load not implemented for "
	jmp	1f

oofs_save:
	printc 0xf4, "WARNING: oofs_save not implemented for "
1:	PRINT_CLASS
	stc
	ret

###########################################################################

# in: eax = this
oofs_persistent_print:
STACKTRACE 0,0
	call	oofs_print	# super.print()
	push_	esi edx
	printc 11, "persistence: "
	mov	esi, [eax + oofs_persistence]
	mov	esi, [esi + obj_class]
	mov	esi, [esi + class_name]
	call	print
	printc 11, " LBA "
	mov	edx, [eax + oofs_lba]
	call	printhex8
	printc 11, " Sectors "
	mov	edx, [eax + oofs_sectors]
	call	printhex8
	call	newline
	pop_	edx esi
	ret

#oofs_sector_dump$:
#	push_	esi eax ecx edx
#	call	newline
#	DEBUG "DUMP"
#	DEBUG_DWORD ecx
#	lea	esi, [eax + oofs_persistent]
#	0:	lodsd; mov edx, eax; call printhex8; call printspace
#	loop 0b
#	call	newline
#	pop_	edx ecx eax esi
#	ret
