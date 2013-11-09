#############################################################################
.intel_syntax noprefix

DECLARE_CLASS_BEGIN oofs_handle, oofs_persistent

oofs_handle_persistence:.long 0 # oofs_alloc instance
oofs_handle_handle:	.long 0	# oofs_alloc handle

oofs_handle_persistent_start:
oofs_handle_size:	.long 0	# bytes

DECLARE_CLASS_METHOD oofs_api_init, oofs_handle_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_handle_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_handle_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_handle_onload, OVERRIDE

DECLARE_CLASS_END oofs_handle
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs_alloc)
# in: ebx = oofs_alloc handle
oofs_handle_init:
	# verify that the persistence is indeed oofs_alloc:
	push_	edx eax
	mov	eax, edx
	mov	edx, offset class_oofs_alloc
	call	class_instanceof
	pop_	eax edx
	jc	91f
	mov	[eax + oofs_handle_persistence], edx
	mov	[eax + oofs_handle_handle], ebx
	mov	[eax + oofs_handle_size], dword ptr 0

	# calculate LBA, size
	push_	ebx ecx
	mov	ecx, [edx + oofs_alloc_handles + handles_ptr]
	add	ecx, ebx
	mov	ebx, [ecx + handle_base]
	mov	ecx, [ecx + handle_size]
	inc	ebx	# skip reserved sector
	add	ebx, [edx + oofs_lba]
	# in: ebx = LBA
	# in: ecx = reserved size

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_handle_init"
		printc 9, " handle="; pushd [esp+4]; call _s_printhex8
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif

	call	oofs_persistent_init	# super.init()
	pop_	ecx ebx

9:	STACKTRACE 0
	ret

91:	printlnc 12, "oofs_handle_init: persistence not oofs_alloc"
	stc
	jmp	9b

oofs_handle_load:
	push_	ecx edx edi
	mov	ecx, 512
	mov	edx, offset oofs_handle_persistent_start
	lea	edi, [eax + edx]
	call	[eax + oofs_persistent_api_read]
	jc	1f
	# recalculate edi
	lea	edi, [eax + edx]
	INVOKEVIRTUAL oofs_persistent onload
1:	pop_	edi edx ecx
	STACKTRACE 0
	ret
	# TODO: onload: read rest.

oofs_handle_onload:
	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".onload"
		DEBUG_DWORD edi
		DEBUG_DWORD [eax + oofs_handle_size]
		push edx; lea edx, [eax + oofs_handle_persistent_start]
		DEBUG_DWORD edx
		pop edx
		call	newline
	.endif
	clc
	ret

oofs_handle_save:
	push_	ecx edx esi
	mov	ecx, [eax + oofs_handle_size]
	add	ecx, 4	# the size dword itself
	mov	edx, offset oofs_handle_persistent_start
	lea	esi, [eax + edx]
	call	[eax + oofs_persistent_api_write]
	pop_	esi edx ecx
	STACKTRACE 0
	ret
