#############################################################################
.intel_syntax noprefix

###############################################################################
.if 1
DEFINE = 0
.include "../../defines.s"
.include "../../macros.s"
.include "../../print.s"
.include "../../debug.s"
.include "../../lib/hash.s"	# OBJ_STRUCT_SIZE
.include "../../oo.s"
.include "../../fs.s"
.include "../fs_oofs.s"
.endif
###############################################################################

.global class_oofs
.global oofs_parent
.global oofs_api_init
.global oofs_api_load
.global oofs_api_save


DECLARE_CLASS_BEGIN oofs
oofs_parent:	.long 0	# nonpersistent

oofs_persistent:
oofs_magic:	.long 0
oofs_count:	.long 0

oofs_array:
oofs_lba:	.long 0
oofs_size:	.long 0

.org 512	# make struct size at least 1 sector

DECLARE_CLASS_METHOD oofs_api_init, oofs_init
DECLARE_CLASS_METHOD oofs_api_load, oofs_load
DECLARE_CLASS_METHOD oofs_api_save, oofs_save
DECLARE_CLASS_END oofs
#################################################
.text32
# in: eax = instance
oofs_init:
	mov	[eax + oofs_parent], edx
	mov	[eax + oofs_magic], dword ptr OOFS_MAGIC
	# add 1 entry taking all space
	mov	[eax + oofs_count], dword ptr 1
	push	ebx
	mov	[eax + oofs_lba], dword ptr 0	# first sector
	mov	ebx, [edx + fs_obj_p_size_sectors]
	mov	[eax + oofs_size], ebx
	pop	ebx
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


oofs_entries_print$:
	push_	esi edx ecx
	mov	ecx, [eax + oofs_count]
	mov	edx, ecx
	printc 11, "Entries: "
	call	printdec32
	call	newline
	lea	esi, [eax + oofs_array]
0:	print " * pLBA "
	mov	edx, [esi]
	call	printhex8
	print ", "
	mov	edx, [esi + 4]
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
