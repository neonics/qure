#############################################################################
.intel_syntax noprefix

OOFS_HASH_DEBUG = 1

.global oofs_hashidx_api_lookup

.struct 0
hashidx_start: .word 0
hashidx_end: .word 0
hashidx_lba: .long 0

DECLARE_CLASS_BEGIN oofs_hashidx, oofs_array

DECLARE_CLASS_METHOD oofs_api_init, oofs_hashidx_init, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_hashidx_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_array_api_print_el, oofs_hashidx_print_el, OVERRIDE

DECLARE_CLASS_METHOD oofs_hashidx_api_lookup, oofs_hashidx_lookup
DECLARE_CLASS_END oofs_hashidx
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_hashidx_init:
	movb	[eax + oofs_array_shift], 3	# 8 bytes/entry
	call	oofs_array_init	# super.init()

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_hashidx_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif
	ret

oofs_hashidx_verify$:
1:	push_	esi eax edx
	lea	esi, [eax + oofs_array_list]
	xor	dx, dx
0:	lodsw
		DEBUG_WORD ax, "from"
	cmp	ax, dx
	jb	92f
62:	mov	dx, ax
	lodsw
		DEBUG_WORD ax, "to "
	cmp	ax, dx
	jae	93f
63:	mov	dx, ax
	#add	esi, 4
	lodsd
		DEBUG_DWORD eax, "lba"
		call	newline
	loop	0b
	pop_	edx eax esi

	clc
9:	pop	ecx
	STACKTRACE 0
	ret

92:	printc 4, "start > prev.end"
	jmp	62b
93:	printc 4, "start >= end"
	jmp	63b


oofs_hashidx_load:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printlnc 14, ".oofs_hashidx_load"
	.endif
	call	oofs_array_load	# explicit superclass call
	jc	9f
	call	oofs_hashidx_verify$

9:	STACKTRACE 0
	ret


# in: eax = this
# in: edx = hash
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ecx = index in parent table (ecx since oofs_load_entry expects it)
oofs_hashidx_lookup:
	push_	edi esi
	mov	esi, edx
	lea	edi, [eax + oofs_array_list]

	push_	edx eax
	mov	ecx, [eax + oofs_array_count]
	mov	eax, [esi]	# get start of hash
0:	mov	edx, [edi]
	cmp	ax, dx	#[edi + hashidx_start]
	ja	9f
	shr	edx, 16
	cmp	ax, dx	# [edi + hashidx_end]
	jb	1f	# found range
  9: # non-ordered list
	add	edi, 8
	loop	0b
9: # eol
0:	pop_	eax edx
	pop_	esi edi
	STACKTRACE 0
	ret

1:	
	.if OOFS_HASH_DEBUG
		DEBUG "found index: ";
		DEBUG_WORD [edi+hashidx_start],"from";DEBUG_WORD [edi+hashidx_end],"to"
		DEBUG_DWORD[edi + hashidx_lba], "LBA"
		call	newline
	.endif

	# load the sector
	# TODO: cache
	mov	edx, [esp]	# get eax
	mov	edx, [edx + oofs_persistence]
	mov	ebx, [edi + hashidx_lba]
	mov	ecx, 1
	mov	eax, offset class_oofs_hash
	call	class_newinstance
	jc	0b
	call	[eax + oofs_persistent_api_load]
	jc	91f
	mov	esi, edx
	call	[eax + oofs_hash_lookup]
	jc	92f
	DEBUG "found hash"
	jmp	0b

91:	call	class_deleteinstance
	stc
	jmp	0b
92:	DEBUG "hash not found"
	jmp	91b
	

oofs_hashidx_print_el:
	ret
