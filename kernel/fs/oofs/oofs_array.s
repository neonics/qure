#############################################################################
.intel_syntax noprefix

.global class_oofs_array


DECLARE_CLASS_BEGIN oofs_array, oofs_persistent

# These must be set by extending classes before calling constructor.
oofs_array_persistent_start: .long 0
oofs_array_start:	.long 0	# offset of array start
oofs_array_shift:	.byte 0
.align 4

DECLARE_CLASS_METHOD oofs_api_init, oofs_array_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_array_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_array_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_array_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_array_onload, OVERRIDE

DECLARE_CLASS_METHOD oofs_array_api_iterate, oofs_array_iterate
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

	# ensure the class is proper size
	push	edx
	mov	edx, [eax + oofs_array_start]
	mov	[eax + edx], dword ptr 0	# set count to 0
	add	edx, 4
	cmp	edx, [eax + obj_size]
	jbe	1f
	call	[eax + oofs_persistent_api_resize]#class_instance_resize
	mov	edx, [eax + oofs_array_start]
1:	pop	edx

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_array_init"
		# printed by persistent_init
		#printc 9, " LBA=";  push ebx; call _s_printhex8
		#printc 9, " size="; push ecx; call _s_printhex8
		#printc 9, " parent="; PRINT_CLASS edx
		push	edx
		printc 9, " array_shift=";
		movzx edx, byte ptr [eax + oofs_array_shift]; call printhex2
		printc 9, " array_start=";
		pushd [eax + oofs_array_start]; call _s_printhex8;
		mov	edx, [eax + oofs_array_start]
		printc 9, " array_count=";
		mov	edx, [eax + edx]
		call	printhex8
		pop	edx
		call	newline
	.endif

	# verify subclass has set array_shift
	cmpb	[eax + oofs_array_shift], 0
	jnz	1f
	printc 12, "oofs_array_init: subclass has not set array_shift"
	STACKTRACE 0,0
	int 3
1:
	cmpd	[eax + oofs_array_start], 0
	jnz	1f
	printc 12, "oofs_array_init: subclass has not set array_start"
	STACKTRACE 0,0
	int 3
1:	
	ret

oofs_array_save:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG ".oofs_array_save", 14
		DEBUG_DWORD edx, "start", 9, 7
		DEBUG_DWORD ecx, "size", 9, 7
		call	newline
	.endif

	push_	ecx esi edx
	# calculate array data length
	mov	edx, [eax + oofs_array_start]
	mov	esi, [eax + edx]	# count
	mov	cl, [eax + oofs_array_shift]
	shl	esi, cl
	lea	ecx, [esi + edx + 4]

	mov	edx, [eax + oofs_array_persistent_start]
	sub	ecx, edx	# subtract
	# ecx = array_start - persistent_start + sizeof(count) + count*elsize
	lea	esi, [eax + edx]
	call	[eax + oofs_persistent_api_write]
	pop_	edx esi ecx
	ret

oofs_array_onload:
	.if OOFS_DEBUG
		DEBUG_CLASS
		DEBUG ".oofs_array_onload", 14
		call	newline
	.endif
	push_	ecx edx
	mov	edx, [eax + oofs_array_start]
	mov	edx, [eax + edx]	# count
	mov	cl, [eax + oofs_array_shift]
	shl	edx, cl

	mov	ecx, [eax + oofs_array_start]
	sub	ecx, [eax + oofs_array_persistent_start]

	lea	ecx, [ecx + edx + 4]

	cmp	ecx, 512
	jbe	1f
####### read the rest
	push_	ecx edi
	sub	ecx, 512
	mov	edx, [eax + oofs_array_persistent_start]
	lea	edi, [eax + edx + 512]	# 2nd sector and onward
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
		DEBUG ".oofs_array_load", 14
		call	newline
	.endif
	push_	ebx ecx edi edx esi
	mov	edi, [eax + oofs_array_start]
# NOTE: at this point, count is probably not initialized unless the object
# size includes the field.
	#mov	edx, [eax + edi]	# count
	#mov	cl, [eax + oofs_array_shift]
	#shl	edx, cl
	#lea	ecx, [edx + edi + 4]
	mov	edx, [eax + oofs_array_persistent_start]
	#add	ecx, edi	# add persistent....array data too
	#sub	ecx, edx
	lea	edi, [eax + edx]
mov ecx, 512
	call	[eax + oofs_persistent_api_read]
	jc	9f
	# recalculate edi, as eax might have changed
	mov	edi, [eax + oofs_array_persistent_start]
	add	edi, eax
	call	[eax + oofs_persistent_api_onload]

9:	pop_	esi edx edi ecx ebx
	call	newline
	STACKTRACE 0
	ret

# in: eax = this
# in: ebx = handler method:
#     in: esi = current element ptr
#     in: edx = current element index
oofs_array_iterate:
	push_	esi edx ecx edi
	mov	edx, [eax + oofs_array_start]
	lea	esi, [eax + edx + 4]	# 4: count
	mov	edi, 1
	mov	cl, [eax + oofs_array_shift]
	shl	edi, cl
	mov	ecx, [eax + edx]	# count

	jecxz	1f

	mov	edx, ecx
0:	push_	edi esi edx ecx ebx eax
	sub	edx, ecx
	call	ebx
	pop_	eax ebx ecx edx esi edi
	add	esi, edi
	loop	0b

1:
	pop_	edi ecx edx esi
	ret

oofs_array_print:
.if OOFS_PRINT_TRACE
	STACKTRACE 0,0
.endif

	push_	edx ebx
	printc 11, "oofs_array: count: "
	mov	edx, [eax + oofs_array_start]
	mov	edx, [eax + edx]
	call	printdec32

	printc 11, " element size: "
	mov	edx, 1
	push	ecx
	mov	cl, byte ptr [eax + oofs_array_shift]
	shl	edx, cl
	pop	ecx
	call	printdec32
	call	newline

	mov	ebx, [eax + oofs_array_api_print_el]
	or	ebx, ebx
	jz	9f
	call	oofs_array_iterate
9:	pop_	ebx edx
	ret
