#############################################################################
.intel_syntax noprefix

.global class_oofs_table
.global oofs_table_size	# for debug

.global oofs_table_api_add
.global oofs_table_api_delete
.global oofs_table_api_lookup
.global oofs_table_api_get_obj

# use the 'persistent offset' feature. 
# it truncates the parent object data length to offs.
DECLARE_CLASS_BEGIN oofs_table, oofs_persistent#, offs=oofs_persistent#, psize=oofs_persistent
# to undo the offset: .space (oofs_persistent - 0)

#oofs_parent:	.long 0	# nonpersistent
#oofs_flags:	.long 0 # nonpersistent
#	OOFS_FLAG_DIRTY = 1

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
DECLARE_CLASS_METHOD oofs_table_api_get_obj, oofs_table_get_obj
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
	pop	edx
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

	xchg	eax, ebx	# restore
	call	oofs_table_save
	mov	eax, ebx	# return value
	#jnc	0f; call class_deleteinstance....

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
	DEBUGS edx, "delete name"
	push_	edi esi
	mov	esi, edx
	call	findstring$
	jc	1f

	# TODO: compact.
	mov	byte ptr [edi], 1	# mark free (overwrite first char)

1:	pop_	esi edi
	ret

# iteration method
# in: eax = this
# in: edx = class
# in: ebx = counter - set to 0 for first in list
# out: CF: counter invalid
# out: eax = object (if CF=0)
oofs_table_get_obj:
	# we don't have parent array children and such..
	ret


# find by class
# in: eax = this
# in: edx = class
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
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

