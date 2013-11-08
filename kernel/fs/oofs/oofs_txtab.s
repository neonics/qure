#############################################################################
.intel_syntax noprefix

.global oofs_txtab_api_get
.global oofs_txtab_api_set

DECLARE_CLASS_BEGIN oofs_txtab, oofs_array

oofs_txtab_array:	# passed to super
oofs_txtab_count:	.long 0
oofs_txtab_tbl:

DECLARE_CLASS_METHOD oofs_api_init, oofs_txtab_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_array_api_print_el, oofs_txtab_print_el, OVERRIDE

DECLARE_CLASS_METHOD oofs_txtab_api_get, oofs_txtab_get
DECLARE_CLASS_METHOD oofs_txtab_api_set, oofs_txtab_set

DECLARE_CLASS_END oofs_txtab
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_txtab_init:
	movb	[eax + oofs_array_shift], 2
	mov	[eax + oofs_array_start], dword ptr offset oofs_txtab_array
	mov	[eax + oofs_array_persistent_start], dword ptr offset oofs_txtab_array
	call	oofs_array_init	# super.init()

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_txtab_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif
	clc
	ret


# in: eax = this
# in: ebx = index
# out: ebx = handle index
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
oofs_txtab_get:
	push	edx
	# check index
	cmp	ebx, [eax + oofs_txtab_count]
	jae	91f
	# get handle index
	mov	ebx, [eax + oofs_txtab_tbl + ebx * 4]
	or	ebx, ebx	# index 0 illegal
	jz	92f
	# verify handle exists
	mov	edx, [eax + oofs_parent]	# oofs_alloc
	mov	edx, [edx + oofs_alloc_handles + handles_num]
	shl	edx, HANDLE_STRUCT_SIZE_SHIFT	# from oofs_alloc.s
	cmp	ebx, edx
	jae	91f
	# handle should be allocated
	mov	edx, [eax + oofs_parent]	# oofs_alloc
	mov	edx, [edx + oofs_alloc_handles + handles_ptr]
	test	[edx + ebx + handle_flags], byte ptr MEM_FLAG_ALLOCATED
	jz	93f


9:	STACKTRACE 0
	pop	edx
	ret

91:	printc 12, "oofs_txtab_lookup: index out of bounds: "
	push	ebx
	call	_s_printhex8
	printcharc 12, '/'
	push	[eax + oofs_txtab_count]
	call	_s_printhex8
	call	newline
92:	stc
	jmp	9b
93:	printc 12, "oofs_txtab_lookup: unallocated handle"
	stc
	jmp	9b

# in: eax = this
# in: ebx = index
# in: edx = handle index
oofs_txtab_set:
	.if 0
		DEBUG "set"
		DEBUG_DWORD ebx,"idx"
		DEBUG_DWORD edx,"val"
	.endif
	cmp	ebx, [eax + oofs_txtab_count]
	jb	1f

	# resize
	push	edx
	lea	edx, [ebx * 4 + oofs_txtab_tbl + 4]
	call	[eax + oofs_persistent_api_resize]
	pop	edx
	jc	9f
	inc	ebx
	mov	[eax + oofs_txtab_count], ebx
	dec	ebx

1:	mov	[eax + oofs_txtab_tbl + ebx * 4], edx
	clc
9:	STACKTRACE 0
	ret


# in: edx = index
# in: esi = element pointer
oofs_txtab_print_el:
	push	edx
	pushcolor 8
	call	printhex8
	call	printspace
	color 15
	mov	edx, [esi]
	call	printhex8
	call	newline
	popcolor
	pop	edx
	ret

