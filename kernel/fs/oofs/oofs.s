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


.struct 0
oofs_el_size:	.long 0
oofs_el_lba:
oofs_el_obj:	.long 0
OOFS_EL_SIZE = 8


.if OOFS_EL_SIZE != 8
.error "OOFS_EL_SIZE != 8 unimplemented"
.endif

DECLARE_CLASS_BEGIN oofs#, relatable
oofs_parent:	.long 0	# nonpersistent
oofs_flags:	.long 0 # nonpersistent
	OOFS_FLAG_DIRTY = 1
oofs_lba:	.long 0	# for subclasses

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
DECLARE_CLASS_END oofs
#################################################
.text32
# in: eax = instance
# in: edx = parent
# in: ecx = persistent size (sectors)
oofs_init:
	DEBUG "oofs_init"
	push edx
	mov	edx, [eax + obj_class]
	DEBUG_DWORD edx, "obj_class"
	DEBUG_DWORD [edx + class_object_size]

	pop edx
	# nonpersistent
	mov	[eax + oofs_parent], edx
	mov	[eax + oofs_magic], dword ptr OOFS_MAGIC
	mov	[eax + oofs_lba], dword ptr 0	# first sector

	mov	[eax + oofs_count], dword ptr 2
	# first array element: self-referential entry recording the vol sector
	mov	[eax + oofs_array + 0 + oofs_el_size], dword ptr 1	
	mov	[eax + oofs_array + 0 + oofs_el_lba], dword ptr 0
	# second entry: free space (always last entry)
	dec	ecx
	mov	[eax + oofs_array + 8 + oofs_el_size], ecx	
	inc	ecx
	mov	[eax + oofs_array + 8 + oofs_el_lba], dword ptr 1
	call oofs_entries_print$
	ret

oofs_save:
	push_	eax ebx ecx esi
	mov	ebx, [eax + oofs_lba]
	mov	ecx, [eax + oofs_count]
	lea	ecx, [ecx * 8 + oofs_array - oofs_persistent]
	lea	esi, [eax + oofs_persistent]

	mov	eax, [eax + oofs_parent]
	call	[eax + fs_obj_api_write]
	pop_	esi ecx ebx eax
	ret

# in: eax = instance
# out: eax = mreallocced instance if needed
oofs_load:
	push_	ebx ecx edi edx esi
	lea	edi, [eax + oofs_persistent]
	mov	ebx, [eax + oofs_lba]	# 0
	mov	ecx, 512
	mov	edx, eax

	mov	esi, [eax + oofs_parent]

	push	eax
	mov	eax, esi
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f

	mov	ecx, [edx + oofs_count]
	lea	ecx, [ecx * 8 + oofs_persistent]
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
	mov	eax, esi
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f

###########################################
1:	call	oofs_entries_print$
###########################################
	clc

9:	pop_	esi edx edi ecx ebx
	ret
91:	printlnc 4, "oofs_load: mrealloc error"
	stc
	jmp	9b


# in: ecx = bytes
# in: edx = class def ptr
oofs_add:
	call	class_instanceof	# check edx is self/superclass
	jc	91f
	# or:
	# push eax
	# mov eax, [eax + obj_class]
	# xchg eax, edx
	# call class_extends
	# mov edx, eax
	# pop eax
	push_	edx
	mov	edx, [eax + oofs_count]
	and	edx, 511
	jz	1f
	add	edx, 8
	cmp	edx, 512
	jbe	2f

1:	# grow
	DEBUG "oofs_add: grow"
	mov	edx, [eax + oofs_count]
	lea	edx, [edx * 8 + oofs_array - oofs_persistent + 512]
	call	class_instance_resize
	jc	9f

2:	# record entry
	push_	ebx ecx
	add	ecx, 511
	shr	ecx, 9	# convert to sectors

	mov	ebx, [eax + oofs_count]
	lea	ebx, [eax + oofs_array + ebx * 8]

	# tail = free space
	# append adjusted tail
	inc	dword ptr [eax + oofs_count]
	mov	edx, [ebx - 8 + oofs_el_size]	# get free space
	sub	edx, ecx	# edx = remaining free space
	jle	92f

	# update prev last entry: set size.
	mov	[ebx - 8 + oofs_el_size], ecx	# reserve

	# append entry representing free space:
	mov	[ebx + oofs_el_size], edx # remaining free space
	add	ecx, [ebx - 8 + oofs_el_lba]
	mov	[ebx + oofs_el_lba], ecx # new free start


	pop_	ecx ebx
	call	[eax + oofs_api_save]
	#orb	[eax + oofs_flags], OOFS_FLAG_DIRTY

	# instantiate array element
	mov	edx, eax	# parent ref
	mov	eax, [esp]
	call	class_newinstance
	jc	9f
	call	[eax + oofs_api_init]

9:	pop_	edx
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

###########################################################################

oofs_entries_print$:
	push_	esi edx ecx
	mov	ecx, [eax + oofs_count]
	mov	edx, ecx
	printc 11, "Entries: "
	call	printdec32
	call	newline
	lea	esi, [eax + oofs_array]
0:	print " * pLBA "
	mov	edx, [esi + oofs_el_lba]
	call	printhex8
	print ", "
	mov	edx, [esi + oofs_el_size]
	call	printhex8
	println " sectors"
	add	esi, 8
	loop	0b
	pop_	ecx edx esi
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
