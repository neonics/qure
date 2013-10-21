#############################################################################
.intel_syntax noprefix

.global class_oofs_array

.struct 0
hash_sha1: .space 20
hash_size: .long 0
hash_lba:  .long 0
.long 0

DECLARE_CLASS_BEGIN oofs_array, oofs_persistent

oofs_array_shift:	.byte 0	# must be set by subclass before calling super().

oofs_array_persistent:	# local separator, for subclasses to use.
oofs_array_count:	.long 0
oofs_array_header_end:

oofs_array_list:

.org oofs_array_persistent + 512	# make struct size at least 1 sector
oofs_array_persistent_end:

DECLARE_CLASS_METHOD oofs_api_init, oofs_array_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_array_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_array_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_array_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_array_onload, OVERRIDE

DECLARE_CLASS_METHOD oofs_array_api_add, oofs_array_add
DECLARE_CLASS_METHOD oofs_array_api_delete, oofs_array_delete
DECLARE_CLASS_METHOD oofs_array_api_lookup, oofs_array_lookup
DECLARE_CLASS_METHOD oofs_array_api_print_el, 0	# abstract class
DECLARE_CLASS_END oofs_array
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_array_init:
	call	oofs_persistent_init	# super.init()
	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_array_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif

	# verify subclass has set array_shift
	cmpb	[eax + oofs_array_shift], 0
	jz	9f
	printc 12, "oofs_array_init: subclass has not set array_shift"
	STACKTRACE 0,0
	int 3
9:	ret

oofs_array_save:
	push_	ecx esi edx
	mov	edx, offset oofs_array_persistent
	mov	esi, [eax + oofs_array_count]
	mov	cl, [eax + oofs_array_shift]
	shl	esi, cl
	mov	ecx, esi
	add	ecx, offset oofs_array_header_end - offset oofs_array_persistent
	lea	esi, [eax + oofs_array_persistent]
	call	[eax + oofs_persistence_api_write]
	pop_	edx esi ecx
	ret

oofs_array_onload:
	push_	ecx edx
	mov	edx, [eax + oofs_array_count]
	mov	cl, [eax + oofs_array_shift]
	shl	edx, cl
	mov	ecx, edx
	cmp	ecx, 512
	jbe	1f
####### read the rest
	push_	ecx edi
	sub	ecx, 512
	mov	edx, offset oofs_array_persistent
	lea	edi, [eax + oofs_array_persistent + 512]
	call	[eax + oofs_persistent_api_read]	# does resizing
	pop_	edi ecx
	jc	9f
####### 
1:	clc
9:	pop_	edx ecx
	STACKTRACE 0
	ret


oofs_array_load:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printlnc 14, ".oofs_array_load"
	.endif
	push_	ebx ecx edi edx esi
	mov	edx, [eax + oofs_array_count]
	mov	cl, [eax + oofs_array_shift]
	shl	edx, cl
	lea	ecx, [edx + offset oofs_array_strings - offset oofs_array_persistent]
	lea	edi, [eax + oofs_array_persistent]
	mov	edx, offset oofs_array_persistent
	call	[eax + oofs_persistent_api_read]
	jc	9f
	call	[eax + oofs_persistent_api_onload]

9:	pop_	esi edx edi ecx ebx
	STACKTRACE 0
	ret


oofs_array_print:
	STACKTRACE 0,0
	push_	esi edx ecx
	lea	esi, [eax + oofs_array_list]
	mov	edx, 1
	mov	cl, [eax + oofs_array_shift]
	shl	edx, cl
	mov	ecx, [eax + oofs_array_count]

	printc 11, "oofs_array: count: "
	push	ecx
	call	_s_printdec32
	printc 11, " element size: "
	call	printdec32

0:	call	[eax + oofs_array_print_el]
	add	esi, edx
	loop	0b

	pop_	ecx edx esi
	ret
