#############################################################################
.intel_syntax noprefix

.global class_oofs_table
.global oofs_table_size	# for debug

.global oofs_table_api_add
.global oofs_table_api_delete		# in: edx=string
.global oofs_table_api_clear_entry	# in: ecx = index
.global oofs_table_api_lookup
.global oofs_table_api_get

# use the 'persistent offset' feature. 
# it truncates the parent object data length to offs.
DECLARE_CLASS_BEGIN oofs_table, oofs_persistent#, offs=oofs_persistent#, psize=oofs_persistent
# to undo the offset: .space (oofs_persistent - 0)

oofs_table_indices:	.long 0	# ptr_array of offsets

oofs_table_persistent:	# local separator, for subclasses to use.
oofs_table_size:	.long 0
oofs_table_strings:

#oofs_table_array:
#oofs_table_lba:	.long 0	# first entry: 0
#oofs_table_size:	.long 0	# first entry: entire partition

.org oofs_table_persistent + 512	# make struct size at least 1 sector
oofs_table_persistent_end:

DECLARE_CLASS_METHOD oofs_api_init, oofs_table_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_table_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_table_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_table_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_table_onload, OVERRIDE

DECLARE_CLASS_METHOD oofs_table_api_add, oofs_table_add
DECLARE_CLASS_METHOD oofs_table_api_delete, oofs_table_delete
DECLARE_CLASS_METHOD oofs_table_api_clear_entry, oofs_table_clear_entry
DECLARE_CLASS_METHOD oofs_table_api_get, oofs_table_get
DECLARE_CLASS_METHOD oofs_table_api_lookup, oofs_table_lookup
DECLARE_CLASS_END oofs_table
#super = oofs_api_init
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_table_init:
	call	oofs_persistent_init	# super.init()

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_table_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif

	push	edx
	mov	edx, [edx + obj_class]
	pushd	[edx + class_name]
	call	addstring$

	mov	edx, [eax + obj_class]
	pushd	[edx + class_name]
	call	addstring$

	call	[eax + oofs_persistent_api_onload]	# construct index

	pop	edx
	STACKTRACE 0
	ret

# in: eax = this
# in: [esp] = stringptr
addstring$:
	push_	esi edi ecx eax
	mov	esi, [esp + 20]

	mov	ecx,[eax+obj_class]
	.if OOFS_DEBUG > 1
		DEBUGS [ecx+class_name]
		DEBUG_DWORD eax, "addstring", 0xe0
		DEBUGS  esi
		#push edx; mov edx,[esp+4+16]; call debug_printsymbol; pop edx
		call	newline
	.endif

	mov	edi, [eax + obj_size]	# also has vptr...
	sub	edi, offset oofs_table_strings
	mov	ecx, [eax + oofs_table_size]

	cmp	ecx, edi
	jb	1f
	DEBUG "oofs_table_size corrupt"
	DEBUG_DWORD ecx
	DEBUG_DWORD edi
	int 3
1:


	lea	edi, [eax + oofs_table_strings]
	add	edi, ecx
	call	strlen_
	inc	ecx
	add	[eax + oofs_table_size], ecx
	rep	movsb
	.if OOFS_DEBUG > 1
		call	[eax + oofs_api_print]
	.endif

	clc

0:	pop_	eax ecx edi esi
	ret	4
91:	printlnc 4, "oofs_table: string not added"
	stc
	jmp	0b


# aspect extension: pre & post
oofs_table_save:
	push_	ecx esi edx ebx eax
	mov	ecx, [eax + oofs_table_size]
	add	ecx, 4
	lea	esi, [eax + oofs_table_persistent]
	mov	ebx, [eax + oofs_lba]
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_table_save", 0xe0
		DEBUG_DWORD ebx,"LBA"
		DEBUG_DWORD ecx,"bytes"
		call newline
	.endif
	mov	edx, eax#[eax + obj_class]
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_write]
	pop_	eax ebx edx esi ecx
	ret

#don't do partition magic checking.
oofs_table_onload:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG " ***** onload "
		DEBUG_DWORD [eax + oofs_table_size]
		call	newline
	.endif
	push_	ebp edi esi edx ecx ebx eax
	mov	ebp, eax	# backup this

	# free the index buffer
	xor	eax, eax
	xchg	eax, [ebp + oofs_table_indices]
	or	eax, eax
	jz	1f
	call	buf_free
1:
	# allocate a new buffer
	mov	eax, [ebp + oofs_parent]	# get oofs_vol
	mov	eax, [eax + oofs_vol_count]
	#DEBUG_DWORD eax, "oofs_table verify: oofs_vol_count"
	call	ptr_array_new
	mov	[ebp + oofs_table_indices], eax
	jc	91f

	lea	edi, [ebp + oofs_table_strings]
	mov	ebx, edi
	mov	ecx, [ebp + oofs_table_size]
0:
	mov	eax, [ebp + oofs_table_indices]
	mov	edx, [eax + array_index]
	#DEBUG_DWORD ecx,"tblsize"
	#DEBUG_DWORD edx, "index"
	#DEBUG_DWORD [eax+array_capacity],"cap"
	cmp	edx, [eax + array_capacity]
	jae	9f	# done
	addd	[eax + array_index], 4
	add	eax, edx	# collapse
	mov	edx, edi
	sub	edx, ebx	# string offset
	mov	[eax], edx
	#DEBUG_DWORD edx
	#DEBUGS edi
	#call newline
	jecxz	9f
	xor	al, al
	repnz	scasb
	jnz	92f	# end should have at least a 0...?
	jmp	0b

9:
	# clear the rest of the table
	mov	eax, edi
	sub	eax, offset oofs_table_strings
	sub	eax, ebp
	mov	[ebp + oofs_table_size], eax

	mov	ecx, [ebp + obj_size]
	add	ecx, ebp
	sub	ecx, edi
	jle	1f

	xor	al, al
	rep	stosb
1:

	mov	eax, ebp	# restore this

	# print entries using offset array
	printc 15, "oofs_table constructed index; entries: "
	mov	edi, [eax + oofs_table_indices]
	mov	edx, [edi + array_index]
	shr	edx, 2
	call	printdec32
	call	newline

	xor	edx, edx
	PTR_ARRAY_ITER_START edi, ebp, esi
	pushcolor 8
	call	printhex4
	popcolor
	call	printspace
	push	esi
	call	_s_printhex8
	call	printspace
	add	esi, ebx
	call	println
	inc	edx
	PTR_ARRAY_ITER_NEXT edi, ebp, esi

	clc

9:	pop_	eax ebx ecx edx esi edi ebp
	STACKTRACE 0
	ret
91:	printc 4, "oofs_table_onload: ptr_array malloc error"
	stc
	jmp	9b
92:	printc 4, "oofs_table_onload: table not zero-terminated"
	stc
	jmp 9b


	clc
	ret

oofs_table_load:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printlnc 14, ".oofs_table_load"
		push eax
		mov eax, [eax + oofs_parent]
		call [eax + oofs_api_print]
		pop eax
	.endif
	push_	ebx ecx edi edx esi
	mov	edx, offset oofs_table_persistent
	lea	edi, [eax + oofs_table_persistent]
	mov	ecx, [eax + oofs_table_size]
	add	ecx, offset oofs_table_strings - offset oofs_table_persistent

	call	[eax + oofs_persistent_api_read]
	jc	9f
	call	[eax + oofs_persistent_api_onload]

9:	pop_	esi edx edi ecx ebx
	STACKTRACE 0
	ret


# in: eax = this (oofs_table instance)
# in: ecx = bytes (passed on to oofs.add)
# in: edx = class def ptr
# out: eax = instance
oofs_table_add:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_table_add", 0xe0
		DEBUG_DWORD ecx
		DEBUG_DWORD [eax+oofs_table_size],"table size"
		call	newline
	.endif

	push	ecx
	call	oofs_table_lookup
	pop	ecx

	# first add the string
	pushd	[edx + class_name]
	call	addstring$
	jc	91f

	push_	ebx esi
	mov	ebx, eax
	mov	esi, [eax + oofs_table_size]
	mov	eax, [eax + oofs_parent]	# add to parent
	call	oofs_vol_add	# out: eax
	jc	92f

	#call	oofs_table_set	# in: ecx=index, edx=string

	#xchg	eax, ebx	# restore
	#call	oofs_table_save
	#mov	eax, ebx	# return value
	##jnc	0f; call class_deleteinstance....

0:	pop_	esi ebx
	ret

91:	printlnc 4, "oofs_table_add: addstring fail"
	stc
	ret
92:	printlnc 4, "oofs_table_add: oofs_add fail"
	mov	[ebx + oofs_table_size], esi	# rollback
	mov	eax, ebx
	stc
	jmp	0b

# remove entry from string table
# in: eax=this
# in: edx=name to delete
oofs_table_delete:
	push_	edi esi
	mov	esi, edx
	call	findstring$
	jc	1f

	# TODO: compact.
	mov	byte ptr [edi], 1	# mark free (overwrite first char)

1:	pop_	esi edi
	ret

# in: eax=this
# in: ecx = entry nr
oofs_table_clear_entry:
	push_	edx edi
	mov	edi, [eax + oofs_table_indices]
	lea	edx, [ecx * 4]
	cmp	edx, [edi + array_index]
	jae	91f

	# check if it is the last entry
	add	edx, 4
	cmp	edx, [edi + array_index]
	jb	1f
	subd	[edi + array_index], 4

	# reset the table size
	mov	edi, [edi + edx - 4]
	mov	[eax + oofs_table_size], edi
	jmp	2f

1:	mov	edi, [edi + edx - 4]	# get string offset
	mov	byte ptr [eax + oofs_table_strings + edi], 1	# mark deleted

2:
	clc
0:	pop_	edi edx
	ret
91:	printlnc 4, "oofs_table_clear_entry: no such entry"
	stc
	jmp	0b

# return the string value for the given index
# in: eax = this
# in: ecx = index
# out: CF: counter invalid
# out: edx = string (class name)
oofs_table_get:
	mov	edx, [eax + oofs_table_indices]
	shl	ecx, 2
	cmp	ecx, [edx + array_index]
	jae	91f
	mov	edx, [edx + ecx]	# offset into string table
	# verify it is the start of a string
	or	edx, edx
	jz	1f
	cmp	byte ptr [eax + oofs_table_strings + edx -1], 0
	jnz	92f
1:	lea	edx, [eax + oofs_table_strings + edx]

0:	shr	ecx, 2
	clc
	ret
91:	stc	# index-out-of-bounds
	jmp	0b
92:	printc 4, "oofs_table: index corrupt"
	# TODO: recalculate
	int 3
	jmp	0b
# KEEP-WITH-NEXT

# in: eax = this
# in: ecx = index
# in: edx = string
oofs_table_set:
	push_	ebx esi edi ecx
	mov	esi, edx # backup
	call	oofs_table_get	# out: edx = stringptr
	jc	1f
	push	esi
	mov	esi, edx
	call	strlen_
	pop	esi
	mov	ebx, ecx	# ebx = old strlen
	call	strlen_		# ecx = new string len

	cmp	ecx, ebx
	jz	2f
	jb	3f
	# new is longer; add space.
	sub	ecx, ebx
	lea	edi, [edx + ebx+1]	# old string + old stringlen
	lea	esi, [edi + ecx]	# new old string pos
	std
	rep	movsb
	cld
	jmp	2f

3:	# new is shorter; copy and compact
	mov	edi, edx
	rep	movsb


2:	# same stringlen, just copy

1:

	pop_	ecx edi esi ebx
	ret


# find by class
# in: eax = this
# in: edx = class
# out: CF = 0: edx valid; 1: ebx = -1
# out: ecx = index in parent table (ecx since oofs_load_entry expects it)
oofs_table_lookup:
	push_	edi esi
	mov	esi, [edx + class_name]
	call	findstring$
	pop_	esi edi
	ret

# in: eax = this
# in: esi = string to find
# out: edi = ptr to string found
# out: ecx = string index
findstring$:
	push_	esi ebx ebp eax
	call	strlen_
	mov	ebx, ecx

	lea	edi, [eax + oofs_table_strings]
	mov	ecx, [eax + obj_size]
	sub	ecx, offset oofs_table_strings	# limit
	mov	ecx, [eax + oofs_table_size]
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG_DWORD eax, "oofs_table_findstring$", 0xe0
		DEBUGS esi
		DEBUG_DWORD ecx
		DEBUG_DWORD [eax + oofs_table_size]
		call	newline
		pushad;call oofs_table_print;popad
	.endif
	xor	ebp, ebp	# index

	mov	ah, [esi]
	cmp	al, [edi]
	jz	1f

0:	stc
	jecxz	9f
	xor	al, al
	repnz	scasb
	stc
	jnz	92f	# end should have at least a 0...?
	inc	ebp
	cmp	ah, [edi]
	jnz	0b

1:	# first char match
	push_	ecx edi esi
	mov	ecx, ebx
	rep	cmpsb
	pop_	esi edi ecx
	jnz	0b
	mov	ecx, ebp
	clc

9:	pop_	eax ebp ebx esi
	ret
92:	printc 4, "oofs_table_lookup: table not zero-terminated"
	stc
	jmp 9b



oofs_table_print:
	STACKTRACE 0,0
	call	oofs_persistent_print	# super.print();
	push_	esi ecx eax edx
	printc 11, "Table: persistent size "
	mov	edx, offset oofs_table_persistent_end - offset oofs_table_persistent
	call	printhex8
	printc 11, " table size "
	mov	edx, [eax + oofs_table_size]
	call	printhex8
	call	newline

	lea	esi, [eax + oofs_table_strings]
	mov	ecx, [eax + oofs_table_size]
	jecxz	9f

	xor	ah, ah
	xor	edx, edx
0:	call	printhex8
	call	printspace


1:	lodsb
	inc	edx
	or	al, al
	jz	2f
	xor	ah, ah	# reset 0 counter
	call	printchar
	loop	1b
	printlnc 4, " warning: not zero terminated"
	jmp	9f
2:	call	newline
	cmp	ah, 1	# two consecutive 0 is end of list
	jz	9f
	inc	ah
	loop	0b

	call	printhex8
	printlnc 8, " end"

9:	pop_	edx eax ecx esi
	ret
91:	printlnc 4, " unknown class"
	jmp	9b

