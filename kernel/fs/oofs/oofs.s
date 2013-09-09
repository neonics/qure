#############################################################################
.intel_syntax noprefix

###############################################################################
.include "extern.h"
# subclasses included at end
###############################################################################

.global class_oofs
.global oofs_parent
.global oofs_api_init
.global oofs_api_load
.global oofs_api_save
.global oofs_api_add
.global oofs_api_load_entry
.global oofs_api_lookup


OOFS_DEBUG = 0

.struct 0
oofs_el_size:	.long 0
oofs_el_lba:	.long 0
OOFS_EL_STRUCT_SIZE = 8

.macro OOFS_IDX_TO_EL reg
	.if OOFS_EL_STRUCT_SIZE == 8
	shl	\reg, 3
#	.elseif OOFS_EL_STRUCT_SIZE == 16
#	shl	\reg, 4
	.else
	.error "OOFS_EL_STRUCT_SIZE != 16, 8"
	.endif
.endm

DECLARE_CLASS_BEGIN oofs#, relatable
oofs_parent:	.long 0	# nonpersistent
oofs_persistence:.long 0 # nonpersistent: fs_oofs (same as parent for root obj)
oofs_flags:	.long 0 # nonpersistent
	OOFS_FLAG_DIRTY = 1
oofs_lba:	.long 0	# for subclasses
oofs_children:	.long 0	# ptr array

oofs_persistent:
oofs_magic:	.long 0
oofs_count:	.long 0
oofs_array:	# {oofs_el_obj, oofs_el_size}[]
# direct access to first entry: special semantics: free space
oofs_size:	.long 0

.org oofs_persistent + 512	# make data struct size at least 1 sector


# API CONVENTION:
# The object instantiating this class must pass along
# a reference to an object - usually itself. This object
# is labeled 'parent' as it is a construct applied in the
# class hiearchy itself.
# The object passed along 
# Generally:
# parent instance must pass itself along in edx
# parent instance must have a field oofs_child.
#  (this means, that the parent must reserve a dword
#   in it's structure at offset oofs_root. This is a
#   limitatoin, solved in one of two ways:
#   1) referential access: call a method in local hierarchy.
#      so far these methods are static, defined in oo.s,
#      yet follow the object calling convention (but are
#      not declared, yet can be easily in a class_class).
#      Beside the point. The parent can provide an offset
#      relative to which the child accesses direct data:
#      an offset or address, which may differ from the parent
#      instance. 
#      The calling class thus receives a consequence, and
#      can either:
#       a) implement an interface class/extend a base class
#       b) create a proxy object
#     This option includes having the parent provide an
#     event handler method with signature (edx, eax).
#  2) multiple inheritance / aspect oriented programming.
#     The parent class must implement the oofs class itself,
#     in order to offer the parent a place for the child
#     to notify a change in address, such as with dynamic
#     (resizable) objects.
#     However, this limits the number of children per parent.
#     The parent class then cannot simply pass any offset
#     as this would make it's methods operate on the wrong
#     data. A proxy may be used in this case.
DECLARE_CLASS_METHOD oofs_api_init, oofs_init
DECLARE_CLASS_METHOD oofs_api_load, oofs_load
DECLARE_CLASS_METHOD oofs_api_save, oofs_save
DECLARE_CLASS_METHOD oofs_api_add, oofs_add
DECLARE_CLASS_METHOD oofs_api_verify_load, oofs_verify_load	#event handler
DECLARE_CLASS_METHOD oofs_api_load_entry, oofs_load_entry
DECLARE_CLASS_METHOD oofs_api_get_obj, oofs_get_obj
DECLARE_CLASS_METHOD oofs_api_lookup, oofs_lookup
DECLARE_CLASS_END oofs
#################################################
.text32
# in: eax = instance
# in: edx = parent
# in: ecx = persistent size (sectors)
oofs_init:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_init", 0xe0
	.endif
	push_	eax edx ebx

	mov	ebx, eax

	# nonpersistent
	mov	[eax + oofs_parent], edx
	mov	[eax + oofs_persistence], edx
	.if OOFS_DEBUG
		mov	edx, [eax + obj_class]
		DEBUGS [edx + class_name]
	.endif
	.if OOFS_DEBUG > 1
		DEBUG_DWORD edx, "obj_class"
		DEBUG_DWORD [edx + class_object_size]
	.endif

	mov	eax, 10	# init cap
	call	ptr_array_new
	jc	9f
	mov	[ebx + oofs_children], eax

	mov	[ebx + oofs_magic], dword ptr OOFS_MAGIC
	mov	[ebx + oofs_lba], dword ptr 0	# first sector

	mov	[ebx + oofs_count], dword ptr 2
	# first array element: self-referential entry recording the vol sector
	mov	[ebx + oofs_array + 0 + oofs_el_size], dword ptr 1
	mov	[ebx + oofs_array + 0 + oofs_el_lba], dword ptr 0
	call	ptr_array_newentry
	jc	9f
	mov	[eax + edx], ebx	# children[0] = this
	# second entry: free space (always last entry)
	dec	ecx
	mov	[ebx + oofs_array + OOFS_EL_STRUCT_SIZE + oofs_el_size], ecx
	inc	ecx
	mov	[ebx + oofs_array + OOFS_EL_STRUCT_SIZE + oofs_el_lba], dword ptr 1
	#	mov	eax, ebx
	#	call	oofs_entries_print$
9:	pop_	ebx edx eax
	ret

oofs_save:
	.if OOFS_DEBUG
		DEBUG "oofs_save", 0xe0
	.endif
	push_	eax ebx ecx esi
	mov	ebx, [eax + oofs_lba]
	mov	ecx, [eax + oofs_count]
	OOFS_IDX_TO_EL ecx
	lea	ecx, [ecx + oofs_array - oofs_persistent]
	lea	esi, [eax + oofs_persistent]

	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_write]
	pop_	esi ecx ebx eax
	ret

oofs_verify_load:
	cmp	[eax + oofs_magic], dword ptr OOFS_MAGIC
	jz	1f
	stc
1:	ret

# in: eax = instance
# out: eax = mreallocced instance if needed
oofs_load:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_load", 0xe0
	.endif

	.if OOFS_DEBUG > 2
		push_	eax edx
		mov	edx, [eax + oofs_parent]
		DEBUG_DWORD edx,"parent"
		mov edx, [eax + obj_class]
		DEBUGS [edx +class_name]

		mov	eax, [eax + oofs_persistence]
		DEBUG_DWORD edx,"persistence"
		mov edx, [eax + obj_class]
		DEBUGS [edx+class_name]

		DEBUG "persistence.fs_obj_api_read:"
		mov edx, [eax+fs_obj_api_read]
		call debug_printsymbol
		call newline
		pop_	edx eax
	.endif

	push_	ebx ecx edi edx esi
	lea	edi, [eax + oofs_persistent]
	mov	ebx, [eax + oofs_lba]	# 0
	mov	ecx, 512
	mov	edx, eax

	.if OOFS_DEBUG
		DEBUG_DWORD ebx, "LBA"
		DEBUG_DWORD ecx, "size"
	.endif

	push	eax
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f

	call	[eax + oofs_api_verify_load]
	jc	92f
	mov	ecx, [edx + oofs_count]
	OOFS_IDX_TO_EL ecx
	lea	ecx, [ecx + oofs_persistent]
	cmp	ecx, 512
	cmc
	jae	1f	# it'll fit
###########################################
	# resize
	mov	edx, ecx
	add	edx, 511
	and	edx, ~511
	call	mreallocz
	jc	91f

	mov	[eax + oofs_parent], esi
	lea	edi, [eax + oofs_persistent]
	mov	ebx, [eax + oofs_lba]	# 0
	# ecx still ok

	push	eax
	mov	eax, [esi + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f

###########################################
1:
	cmp	[eax + oofs_children], dword ptr 0
	jnz	1f
	push	eax
	mov	eax, [eax + oofs_count]
	add	eax, 10
	call	ptr_array_new
	mov	edx, eax
	pop	eax
	mov	[eax + oofs_children], edx
1:
###########################################
	call	oofs_entries_print$
###########################################
	clc

9:	pop_	esi edx edi ecx ebx
	ret
91:	printlnc 4, "oofs_load: mrealloc error"
	stc
	jmp	9b
92:	printlnc 4, "oofs_load: wrong partition magic"
	stc
	jmp	9b

# in: eax = this (oofs instance)
# in: ecx = bytes
# in: edx = class def ptr
# out: eax = instance
oofs_add:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_add", 0xe0
	.endif
	push_	eax edx
	mov	eax, edx
	mov	edx, offset class_oofs
	call	class_extends
	pop_	edx eax
	jc	91f
	# or:
	# push eax
	# mov eax, [eax + obj_class]
	# xchg eax, edx
	# call class_extends
	# mov edx, eax
	# pop eax
	push_	ebx eax edx ebp 
	lea	ebp, [esp + 4]
	mov	edx, [eax + oofs_count]
	and	edx, 511
	jz	1f
	add	edx, OOFS_EL_STRUCT_SIZE
	cmp	edx, 512
	jbe	2f

1:	# grow
	DEBUG "oofs_add: grow"
	mov	edx, [eax + oofs_count]
	OOFS_IDX_TO_EL edx
	lea	edx, [edx + oofs_array - oofs_persistent + 512]
	call	class_instance_resize
	jc	9f

2:	# record entry
	push_	ebx ecx
	add	ecx, 511
	shr	ecx, 9	# convert to sectors

	mov	ebx, [eax + oofs_count]
	OOFS_IDX_TO_EL ebx
	lea	ebx, [eax + oofs_array + ebx]

	# tail = free space
	# append adjusted tail
	inc	dword ptr [eax + oofs_count]
	mov	edx, [ebx - OOFS_EL_STRUCT_SIZE + oofs_el_size] # get free space
	sub	edx, ecx	# edx = remaining free space
	jle	92f

	# update prev last entry: set size.
	mov	[ebx - OOFS_EL_STRUCT_SIZE + oofs_el_size], ecx	# reserve

	# append entry representing free space:
	mov	[ebx + oofs_el_size], edx # remaining free space
	add	ecx, [ebx - OOFS_EL_STRUCT_SIZE + oofs_el_lba]	# lba field now avail
	mov	[ebx + oofs_el_lba], ecx # new free start

	pop_	ecx ebx
	call	[eax + oofs_api_save]
	#orb	[eax + oofs_flags], OOFS_FLAG_DIRTY

	# instantiate array element
	mov	edx, eax	# parent ref
	mov	eax, [ebp]	# classdef
	call	class_newinstance
	jc	9f
	call	[eax + oofs_api_init]
	jc	93f
	DEBUG "init ok"
	mov	ebx, eax

	# record object instance
	mov	eax, [ebp+4]	# this
	mov	eax, [eax + oofs_children]
	DEBUG_DWORD eax, "oofs_children"
	call	ptr_array_newentry	# out: eax + edx
	jc	94f
	mov	[eax + edx], ebx

	mov	[ebp + 4], ebx	# change return value
9:	pop_	ebp edx eax ebx
	ret

91:	printc 4, "oofs_add: "
	pushd	[edx + class_name]
	call	_s_print
	printc 4, " not super of "
	mov	edx, [eax + obj_class]
	pushd	[edx + class_name]
	call	_s_println
	stc
	jmp	9b

92:	printc 4, "oofs_add: not enough free sectors"
	pop_	ecx ebx
	stc
	jmp	9b

93:	printlnc 4, "oofs_add: oofs_api_init fail"
	call	class_deleteinstance
	# TODO: undo reservation
	stc
	jmp	9b

94:	printlnc 4, "oofs_add: out of memory"
	stc
	jmp	9b

# in: eax = this
# in: edx = classdef ptr
# in: ecx = index
oofs_load_entry:
	# instantiate array element
	push_	edi esi ecx ebx edx eax ebp
	lea	ebp, [esp + 4]

	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_load_entry", 0xe0
	.endif
	.if OOFS_DEBUG > 2
		DEBUG_DWORD ecx
		DEBUG_DWORD edx
		DEBUGS [edx + class_name]
	.endif

	cmp	ecx, [eax + oofs_count]
	jae	9f
	xchg	eax, edx	# eax=classdef; edx=parent ref(this)
	call	class_newinstance
	jc	9f
	# edx = this, still
	mov	ebx, [edx + oofs_array + ecx * 4 + oofs_el_lba]
	mov	ecx, [edx + oofs_array + ecx * 4 + oofs_el_size]
	call	[eax + oofs_api_init]
	jc	9f
	mov	ebx, eax

	# record object instance
	mov	eax, [ebp]	# this
	mov	edi, eax	# backup for entries_print
	mov	eax, [eax + oofs_children]
	call	ptr_array_newentry	# out: eax + edx
	jc	91f
	mov	[eax + edx], ebx
	mov	[ebp], ebx
	mov	eax, ebx

	.if OOFS_DEBUG > 2
		mov ebx, [ebx + obj_class]
		DEBUGS [ebx + class_name]
		DEBUG_DWORD [eax+oofs_api_load]
	.endif

	call	[eax + oofs_api_load]
	jc	9f

	mov	eax, edi
	call	oofs_entries_print$
	clc

0:	pop_	ebp eax edx ebx ecx esi edi
	ret

91:	mov	eax, ebx
	call	class_deleteinstance
9:	printc 4, "oofs_load_entry: fail"
	stc
	jmp	0b


# iteration method
# in: eax = this
# in: edx = class
# in: ebx = counter - set to 0 for first in list
# out: CF: counter invalid
# out: eax = object (if CF=0)
oofs_get_obj:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_get_obj", 0xe0
		DEBUG_DWORD ebx,"idx"
	.endif

	push_	ebx edx

	# check if we have that many persistent entries 
	cmp	ebx, [eax + oofs_count]
	jae	9f

	# check if we have that many loaded
	mov	edx, [eax + oofs_children]
	shl	ebx, 2
	cmp	ebx, [edx + array_index]
	jae	9f

	mov	eax, [edx + ebx]

	.if OOFS_DEBUG
		DEBUG_DWORD eax,"obj!"
	.endif
	clc
0:	pop_	edx ebx
	ret
9:	stc
	jmp	0b

# find by class
# in: eax = this
# in: edx = class
# in: ebx = counter (0 for start)
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ebx = next counter / -1
# out: eax = object instance matching class edx
oofs_lookup:
	.if OOFS_DEBUG
		DEBUG "oofs_lookup"
		DEBUGS [edx + class_name]
		DEBUG_DWORD ebx
	.endif
0:	push	eax
	call	[eax + oofs_api_get_obj]	# out: eax
	jc	9f
	inc	ebx
	or	eax, eax
	stc
	jz	1f
	# ebx verified
	call	class_instanceof
1:	pop	eax
	jc	0b
	clc
	ret
9:	mov	ebx, -1
	pop	eax
	ret

###########################################################################

# in: eax = this
oofs_entries_print$:
	push_	edi esi edx ecx ebx
	printc 11, "Object "
	mov	edx, eax
	call	printhex8
	mov	edx, [eax + obj_class]
	call	printspace
	mov	esi, [edx + class_name]
	call	print

	mov	ecx, [eax + oofs_count]
	mov	edx, ecx
	printc 11, " Entries: "
	call	printdec32
	printc 11, " (instances: "
	mov	esi, [eax + oofs_children]
	DEBUG_DWORD esi
	xor	edx, edx
	or	esi, esi
	jz	1f
	mov	edx, [esi + array_index]
	shr	edx, 2
1:	call	printdec32
	printlnc 11, ")"
	or	ecx, ecx
	jz	9f

	lea	esi, [eax + oofs_array]
	xor	ebx, ebx	# lba sum
	xor	edi, edi	# index
0:	print " * pLBA "
	mov	edx, [esi + oofs_el_lba]
	call	printhex8
	print " ("
	pushcolor 7
	cmp	edx, ebx
	jz	2f
	color 12
2:	mov	edx, ebx
	call	printhex8
	popcolor
	print "), "
	mov	edx, [esi + oofs_el_size]
	call	printhex8
	print " sectors"
	add	ebx, edx

	mov	edx, [eax + oofs_children]
	or	edx, edx
	jz	1f
	cmp	edi, [edx + array_index]
	jae	1f
	mov	edx, [edx + edi]
	print " obj: "
#	call printhex8
#	call printspace
	or	edx, edx
	jz	1f
	mov	edx, [edx + obj_class]
#	call printhex8
#	call printspace
	pushd	[edx + class_name]
	call	_s_print
1:	call	newline
	add	esi, OOFS_EL_STRUCT_SIZE
	add	edi, 4
	dec ecx;jnz 0b#loop	0b
9:	pop_	ebx ecx edx esi edi
	ret


oofs_sector_dump$:
	push_	esi eax ecx edx
	call	newline
	DEBUG "DUMP"
	DEBUG_DWORD ecx
	lea	esi, [eax + oofs_persistent]
	0:	lodsd; mov edx, eax; call printhex8; call printspace
	loop 0b
	call	newline
	pop_	edx ecx eax esi
	ret


###############################################################################
.include "oofs_table.s"
###############################################################################
