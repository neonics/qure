################################################################################
# Object Orientation
#
.intel_syntax noprefix

OO_DEBUG = 0
OO_DEBUG_VPTR = 0	# class_resolve and utility
DEBUGGER_NAME OO

OBJ_VPTR_COMPACT = 1	# 0: interleaved with data; 1: negative offsets

# 'Class' class
.global class_def_size
.global class_flags
.global CLASS_FLAG_RESOLVED
.global class_super
.global class_object_size
.global class_name
.global class_object_vptr
.global class_decl_vptr
.global class_decl_vptr_count
.global class_decl_mptr
.global class_decl_mcount
.global class_over_mptr
.global class_over_mcount
.global class_static_mptr
.global class_static_mcount
.global class_match_instance
.global CLASS_STRUCT_SIZE


.if DEFINE
.struct 0
class_def_size:		.long 0
class_flags:		.long 0
	CLASS_FLAG_RESOLVED = 1
class_super:		.long 0
class_object_size:	.long 0	# including the vptr table
class_name:		.long 0
class_object_vptr:	.long 0 # offset in obj for method pointers (if COMPACT)
class_decl_vptr:	.long 0 # pointer to (static) vptr table for class
class_decl_vptr_count:	.long 0 #
class_decl_mptr:	.long 0 # offset in .data SECTION_DATA_CLASS_M_DECLARATIONS
class_decl_mcount:	.long 0 # nr of methods in mptr
class_over_mptr:	.long 0
class_over_mcount:	.long 0 # nr of override methods in mptr
class_static_mptr:	.long 0
class_static_mcount:	.long 0
class_match_instance:	.long 0
CLASS_STRUCT_SIZE = .
.endif



.global class_method_flags
.global CLASS_METHOD_FLAG_DECLARE
.global CLASS_METHOD_FLAG_OVERRIDE
.global CLASS_METHOD_FLAG_STATIC
.global class_method_idx
# depending on class_method_type, the following dword has different semantics:
# for _FLAG_DECLARE, it is a stringpointer for the name
# for _FLAG_OVERRIDE, it is the position in the object to store the ptr
.global class_method_name
.global class_method_target
.global class_method_ptr
.global CLASS_METHOD_STRUCT_SIZE

.if DEFINE
.struct 0
class_method_flags:	.word 0
	CLASS_METHOD_FLAG_DECLARE	= 0<<0
	CLASS_METHOD_FLAG_OVERRIDE	= 1<<0
	CLASS_METHOD_FLAG_STATIC	= 1<<1
class_method_idx:	.word 0	# limit nr metods to 64k
# depending on class_method_type, the following dword has different semantics:
# for _FLAG_DECLARE, it is a stringpointer for the name
# for _FLAG_OVERRIDE, it is the position in the object to store the ptr
class_method_name:
class_method_target:	.long 0	# offs in obj where ptr is copied to
class_method_ptr:	.long 0	# the method address

# NOTE: hardcoded size of 3 dwords!
CLASS_METHOD_STRUCT_SIZE = 12

# TODO: store method names
# TODO: find a way to store the methods in the class struct itself
# TODO: multiple inheritance/interfaces


###################################
# GLOBALS / export
# code (args: eax[, edx] unless otherwise specified)
.global class_newinstance
.global class_deleteinstance
.global class_instance_resize
.global class_instanceof
.global class_extends
.global class_is_class
.global class_get_by_name
.global class_obj_print_classname	# stackarg
.global class_print_classname	# stackarg
.global class_invoke_static
.global class_invoke_virtual
.global class_iterate_classes
.global class_ref_inc
# debug
.global _obj_print_methods$
.global _obj_print_vptr$
.global _class_print_vptr$
.global _class_print$
# data
.global class_instances
# structural
.global OBJ_decl_vptr
.global OBJ_decl_vptr_count
###################################



.section .classdef
class_definitions:	# idem to data_classdef_start

.data SECTION_DATA_BSS
class_instances:	.long 0	# aka objects
class_instances_sem:	.long 0

#class_dyn_definitions:	.long 0 # ptr_array of dynamically registered class defs

.text32
# in: eax = class_ definition pointer
# out: eax = instance
class_newinstance:
	push	ebp
	lea	ebp, [esp + 4]	# for mallocz_
	call	class_resolve
	jc	0f

	# quick hack: don't record the object instance.
	push	esi
	.if OO_DEBUG
		DEBUG "class_newinstance"
		DEBUGS [eax+class_name]
	.endif
	mov	esi, eax
	mov	eax, [esi + class_object_size]
	.if OO_DEBUG
		DEBUG_DWORD eax,"size"
	.endif
	call	mallocz_	# register caller of current method
	jc	9f
.if OBJ_VPTR_COMPACT
	sub	eax, [esi + class_object_vptr]	# skip over vptrs
.endif
	mov	[eax + obj_class], esi
	push	edx	# TODO: efficient
	.if OBJ_VPTR_COMPACT
	mov	edx, [esi + class_decl_vptr_count]
	shl	edx, 2
	neg	edx
	add	edx, [esi + class_object_size]
	.else
	mov	edx, [esi + class_object_size]
	.endif
	mov	[eax + obj_size], edx
	pop	edx

	.if OO_DEBUG
		DEBUG "class_newinstance ", 0xe0
		DEBUG_DWORD eax, "obj"
		DEBUGS [esi + class_name]
		DEBUG_DWORD esi
		DEBUG_DWORD [esi+class_super]
		DEBUG_DWORD [eax+obj_class]
		call newline
	.endif

	call	obj_init_vptrs

	# register the class in the class_instances ptr_array
	push	edx
	push	eax
	PTR_ARRAY_NEWENTRY [class_instances], 20, 9f
	add	edx, eax
	pop	eax
	mov	[edx], eax
	pop	edx

0:	pop	esi
	pop	ebp
	ret
9:	printlnc 4, "class_newinstance: out of memory"
	stc
	jmp	0b



# in: eax = classdef ptr
class_resolve:
	call	class_is_class
	jc	9f
	push	ebx
	xor	ebx, ebx
	call	class_resolve_internal$
	pop	ebx
	ret
9:	printc 4, "class_resolve: not a classdef ptr: "
	push	eax
	call	_s_printhex8
	stc
	STACKTRACE 0, 0
	ret

# in: eax = classdef ptr to be checked
class_is_class:
	push	edx
	mov	edx, offset data_classdef_start #class_definitions
0:	cmp	edx, eax
	jz	1f
	add	edx, [edx + class_def_size]
	cmp	edx, offset data_classdef_end
	jb	0b
#	printc 4, "class_resolve: not classdef ptr: "
#	mov	edx, eax
#	call	printhex8
#	call	newline
	stc
1:	pop	edx
	ret


# in: eax = classdef ptr
# in: ebx = vptr start index (automatically set - internal)
class_resolve_internal$:
	testb	[eax + class_flags], CLASS_FLAG_RESOLVED
	jnz	9f

	# resolve superclass, so that its class_decl_vptr is initialized.
	push	eax
	mov	eax, [eax + class_super]
	or	eax, eax
	jnz	1f
	xor	ebx, ebx
1:	call	class_resolve_internal$
2:	pop	eax
	jc	91f

	# resolve current class.
	push_	edi esi ecx edx

	.if OO_DEBUG
		printc 0xb0, "class_resolve "
		DEBUGS [eax + class_name]
		DEBUG_DWORD [eax + class_decl_vptr_count], "vptr.count"
		DEBUG_DWORD [eax + class_decl_mcount], "mptr.count"
		call	newline
	.endif

	# mptr is stored incrementally.
	# vptr is stored reversed (in compact mode), and grows more negative.
	#
	# obj = [vptr]^[data]  ( ^ = object pointer )
	# [vptr] = [this.mptr][super.vptr]^
	#
	# so we first append the mptr reversed at the beginning,
	# which will have highest negative offset, and then we simply append
	# the class_decl_vptr data from the super class - which has been
	# resolved.

	# assert vptr.count = mptr.count + super.vptr.count
	mov	esi, [eax + class_super]
	or	esi, esi
	jz	1f	# no super
	mov	ecx, [eax + class_decl_mcount]
	mov	edi, [eax + class_decl_vptr_count]
	mov	edx, [esi + class_decl_vptr_count]
	lea	esi, [edx + ecx]
	cmp	esi, edi
	jnz	92f
1:

	# declare class methods at beginning of class_decl_vptr
	call	class_resolve_mptr$
	jc	90f
	call	class_resolve_super_vptr$
	jc	90f
	call	class_resolve_overrides$
	jc	90f

	.if OO_DEBUG_VPTR
		mov	esi, eax
		call	_class_print_vptr$
	.endif

	orb	[eax + class_flags], CLASS_FLAG_RESOLVED
	clc
0:	pop_	edx ecx esi edi
9:	ret

91:	printlnc 4, "error resolving super class"
	stc
	ret
90:	printc 4, "class resolution error"
	mov	esi, eax
	call	_class_print_vptr$
	int 3
	stc
	jmp	0b

92:	pushcolor 4
	pushd	edi
	pushd	ecx
	pushd	edx
	pushd	[eax + class_name]
	pushstring "class_resolve(%s): super.vptr.count (%d) + this.mptr.count (%d) != this.vptr.count (%d)\n"
	call	printf
	add	esp, 20
	popcolor
	stc
	jmp	0b

# in: eax = classdef
class_resolve_mptr$:
	# copy this.mptr to this.vptr
	mov	esi, [eax + class_decl_mptr]
	mov	ecx, [eax + class_decl_mcount]
	.if OO_DEBUG_VPTR
		DEBUG "mptr->vptr"
		DEBUG_DWORD ecx, "mptr.count"
		call	newline
	.endif
	cmp	ecx, [eax + class_decl_vptr_count]
	ja	93f	# mcount > vptr_count -> error

	# copy mptr to vptr

	mov	edi, [eax + class_decl_vptr]
	lea	edi, [edi + ecx * 4]

	clc

	jecxz	1f
	push	eax
0:	lodsd	# flags, index
	.if OO_DEBUG_VPTR
		print  "  mptr "
		DEBUG_DWORD eax, "flags|index"
		# perhaps use index?
	.endif
	lodsd	# name (ovr/static: target)
	.if OO_DEBUG_VPTR
		DEBUGS eax
	.endif
	lodsd	# address
	.if OO_DEBUG_VPTR
		DEBUG_DWORD eax, "addr"
		call	newline
	.endif
	sub	edi, 4
	mov	[edi], eax
	.if OO_DEBUG_VPTR
		dec	ecx
		jnz	0b
	.else
	loop	0b
	.endif
	pop	eax
1:	clc
90:
	ret


# decl_mcount (ecx) > decl_vptr_count
93:	pushcolor 4
	pushd	[eax + class_decl_vptr_count]
	pushd	ecx
	pushstring "class_decl_mcount (%d) > class_decl_vptr_count (%d)\n"
	call	printf
	add	esp, 12
	popcolor

	int 3

	stc
	jmp	90b

# in: eax = class
class_resolve_super_vptr$:
	mov	ecx, [eax + class_super]
	jecxz	1f
	mov	esi, [ecx + class_decl_vptr]
	mov	ecx, [ecx + class_decl_vptr_count]
	.if OO_DEBUG_VPTR
		DEBUG_DWORD ecx, "super.vptr.count"
	.endif
	cmp	ecx, [eax + class_decl_vptr_count]
	ja	92f	# super.vptr.count > this.vptr.count -> error

	# calculate edi = vptr + mcount*4
	mov	edi, [eax + class_decl_mcount]
	shl	edi, 2
	add	edi, [eax + class_decl_vptr]

	# super.vptr already in proper order; simply append.
	rep	movsd	# this.vptr[] += super.vptr[]

1:
90:	ret

# super.vptr.count > vptr.count
# in: eax = this
# in: ecx = this.vptr count
# in: edx = super vptr count
92:	pushcolor 4
	pushd	edx
	pushd	ecx
	pushd	[eax + class_name]
	pushstring "class_resolve: %s.vptr.count %d < vptr.count %d\n"
	call	printf
	add	esp, 16
	popcolor
	int 3
	stc
	jmp	90b

# in: eax = class
class_resolve_overrides$:
	mov	esi, [eax + class_over_mptr]
	mov	ecx, [eax + class_over_mcount]
	mov	edi, [eax + class_decl_vptr]
	.if OO_DEBUG_VPTR
		DEBUG_DWORD ecx, "over.count"
		DEBUG_DWORD [eax + class_object_vptr], "vptr"
		DEBUG_DWORD [eax + class_object_size], "objsize"
		call	newline
	.endif
	clc
	jecxz	1f
	push_	eax ebx
	mov	ebx, [eax + class_decl_vptr_count]
	shl	ebx, 2	# vptr bound
	add	edi, ebx	# edi = end of vptr
0:	lodsd	# flags, index
	.if OO_DEBUG_VPTR
		print "  override "
		DEBUG_DWORD eax, "flags|index"
	.endif
	shr	eax, 16	# get vptr offs
	mov	edx, eax
	lodsd	# target
	.if OO_DEBUG_VPTR
		DEBUG_DWORD eax, "target"
	.endif
	lodsd	# address
	.if OO_DEBUG_VPTR
		DEBUG_DWORD eax, "addr"
		call	newline
	.endif
	# check if vptr is within range
	cmp	edx, ebx
	jae	94f

	neg	edx
	sub	edx, 4	# same as target

	mov	[edi + edx], eax
949:
	loop	0b
	clc
	pop_	ebx eax
1:	ret

# override idx (edx) > vptr.size (ebx)
94:	push	eax
	mov	eax, [esp + 8]	# get orig eax=class
	mov	eax, [eax + class_name]
	pushcolor 4
	pushd	ebx
	pushd	edx
	pushd	eax
	pushstring "class_resolve_overrides$(%s): idx (%08x) out of vptr bounds (%08x)\n"
	call	printf
	add	esp, 12
	popcolor
	pop	eax
	stc
	STACKTRACE 12	# should be 8!
	int 3
	jmp	949b


# make a temporary class using a given class reference
# in: eax = instance
# in: edx = class def ptr
# out: eax = proxy instance
# TODO: cache.
# OUT: CF = 1 : class_cast exception
class_cast:
	# verify edx is superclass of eax
	call	class_instanceof
	jnz	91f

	xchg	eax, edx
	call	class_newinstance
	jc	92f
	# eax = new instance
	# edx = old instance

	push_	esi edx
	mov	edx, [edx + obj_class]	# old instance class
	# skip subclasses of edx
	mov	esi, [eax + obj_class]
0:	cmp	edx, esi
	jz	0f
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b
		printc 4, "class_cast assertion: superclass missing in hierarchy"
		call	class_deleteinstance
		stc
		jmp	9f
0:	call	obj_init_vptrs
	# eax is dummy class: copy data
	push_ 	edi ecx
	mov	esi, [esp + 8]	# old instance (edx)
	mov	edi, eax	# new instance
	mov	edx, [eax + obj_class]
	mov	edx, [edx + class_object_vptr]
	movzx	ecx, dl
	and	cl, 3
	rep	movsb
	mov	ecx, edx
	shr	ecx, 2
	rep	movsd
	pop_	ecx edi

9:	pop_	edx esi
	ret

91:	printc 4, "class_cast exception: "
	pushd	[edx + class_name]
	call	print
	printc 4, " not instanceof "
	push	eax
	mov	eax, [eax + obj_class]
	mov	eax, [eax + class_name]
	xchg	eax, [esp]
	call	_s_println
	stc
	ret
92:	printc 4, "class_cast exception: "
	pushd	[eax + class_name]
	printlnc 4, " cannot be instantiated."
	stc
	ret


# this method will create a copy of the current object, cast as the proxy.
# The size of the object will be as much as the proxy class needs. Thus,
# using a superclass whith the proper definitions and handlers is best.
# Any class desiring to create a proxy must override an event handler method,
# which is called when the object is recycled. This method then - the
# default implementation - then simply copies the data back to the original
# instance.
# In multithreading environments, a semaphore can be used, to count the
# number of data modifications on either instance, to determine whether
# and which data must be copied, and which event handlers must be called
# instead.
# Hardware support in terms of page faults: multiple objects can be shared
# in the same page - at sector boundary, 8. A page fault then reveals
# by a simple mask and shift which object, and which field, is accessed.
# For now, this is a todo.
#
# in: eax = instance
# out: edx = proxy
class_proxy:
	push_	esi ecx
	mov	esi, eax
	.if OBJ_VPTR_COMPACT
	mov	ecx, [edx + obj_class]
	mov	ecx, [ecx + class_decl_vptr_count]
	shl	ecx, 2
	add	ecx, [edx + obj_size]
	.else
	mov	ecx, [edx + obj_size]
	.endif
	call	mdup
	mov	edx, esi
	call	obj_init_vptrs
	pop_	ecx esi
	ret

class_clone:
	mov	edx, [eax + obj_class]
	jmp	class_proxy

# in: eax = instance
# in: edx = new size
# out: eax = new instance
class_instance_resize:
	push_	edi ecx ebx esi
	# find instance
	mov	edi, [class_instances]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	jz	91f
	repnz	scasd
	jnz	91f
	lea	ebx, [edi - 4]	# remember pointer offset

	.if OO_DEBUG
		DEBUG "class_instance_resize"
		#DEBUG_DWORD eax,"obj"
		pushd [eax+obj_class]; call class_print_classname
	.endif

	mov	edi, [eax + obj_size]

	.if OBJ_VPTR_COMPACT
	# add vptr size to obj size
	mov	esi, [eax + obj_class]
	mov	esi, [esi + class_decl_vptr_count]
	shl	esi, 2
	add	edi, esi
	add	edx, esi
	.endif

	.if OO_DEBUG
		DEBUG_DWORD edi, "old size"
		DEBUG_DWORD edx, "new size"
	.endif

	.if OBJ_VPTR_COMPACT
	mov	ecx, [eax + obj_class]
	add	eax, [ecx + class_object_vptr]
	.endif
	call	mreallocz
	jc	9f	# malloc prints errors

	.if OBJ_VPTR_COMPACT
	sub	eax, [ecx + class_object_vptr]
	.endif

########
.if 0
	# clear the extra data (mreallocz should do this)
	mov	ecx, edx
	sub	ecx, edi
	jle	1f
	push	eax
	lea	edi, [eax + edx]
	mov	ah, cl
	shr	ecx, 2
	xor	al, al
	rep	stosb
	movzx	ecx, ah
	and	cl, 3
	xor	eax, eax
	rep	stosd
	pop	eax
1:
.endif
########

	.if OBJ_VPTR_COMPACT
	sub	edx, esi
	.endif

	mov	[eax + obj_size], edx
	mov	[ebx], eax	# replace instance pointer
	clc

9:	pop_	esi ebx ecx edi
	ret
91:	printc 4, "class_instance_resize: unknown instance"
	stc
	jmp	9b

# in: eax = object having reference to object edx
# in: edx = object being referred to
class_ref_inc:
	.if 0 # HUGE_MEM
		mov	%rdi, edx
		shl	%rdi, 32
		mov	%rdi, eax
		incd	[%rdi]
	.else
	.endif

	#incd	[edx + obj_refcount]
	ret

class_ref_dec:
	ret


##########################################################################
# VPTR

.if !OBJ_VPTR_COMPACT
# in: eax = object
# in: esi = class def
class_init_vptr$:
	.if OO_DEBUG	# XXX
		call	newline
		DEBUG "class_init_vptr$"
		DEBUG_DWORD eax,"for"
		push eax; mov eax, [eax + obj_class]; pushd [eax+class_name]; call _s_print;
		DEBUG_DWORD [eax + class_object_size],"objsize"
		DEBUG_DWORD [eax + class_object_vptr],"vptr"
		pop eax
		DEBUG "using"
		push dword ptr [esi + class_name]
		call _s_print
		call newline
		DEBUG_DWORD [esi + class_decl_mcount]
		DEBUG_DWORD [esi + class_over_mcount]
		DEBUG_DWORD [esi + class_object_vptr]
		call	newline
		push_ ecx esi eax
		mov	esi, [eax + obj_class]
		.if OBJ_VPTR_COMPACT
			mov	ecx, [esi + class_object_vptr]
			neg	ecx
			mov	esi, eax
			add	esi, ecx
		.else
			mov	ecx, [esi + class_object_size]
			sub	ecx, [esi + class_object_vptr]
			add	esi, [esi + class_object_vptr]
		.endif
		shr	ecx, 2
		jz	1f
		0: DEBUG_DWORD esi; lodsd; DEBUG_DWORD eax
		loop	0b
		1:
		call	newline
		pop_ eax esi ecx
	.endif

	# initialize the object method pointers
	push_	edi ecx eax edx ebx esi
	mov	ebx, eax	# backup


	# first fill in the declared methods:
	mov	ecx, [esi + class_decl_mcount]
	or	ecx, ecx
	jz	1f
	mov	edi, [esi + class_object_vptr]	# offset into obj
	#############
	or	edi, edi
	jz	2f
	mov	eax, [esi + class_object_size]
	.if OO_DEBUG
		DEBUGS [esi+class_name]
		DEBUG_DWORD eax,"objsize"
		DEBUG_DWORD edi,"objvptr"
	.endif
	sub	eax, edi
	jle	21f
	# cmp vptr space with decl mcount
	shr	eax, 2
	cmp	eax, ecx
	jnz	3f
	#############
	push	esi
	add	edi, ebx
	mov	esi, [esi + class_decl_mptr]
0:	lodsd	# flags | idx
	lodsd	# target (override) or name (decl)
	lodsd	# function offset
	cmp	dword ptr [edi], 0	# don't overwrite
	jnz	4f
	#stosd	# store in vptr
	mov	[edi], eax
4:	add	edi, 4
	loop	0b
	sub	edi, ebx
	pop	esi
	jmp	1f
2:	printc 4, "warning: vptr 0 yet "
	mov	edx, ecx
	call	printdec32
	printlnc 4, " methods declared."
	jmp	1f
21:	printlnc 4, "vptr beyond object size"
	jmp	1f
3:	printc 4, "error: vptr space ("
	mov	edx, eax
	call	printdec32
	printc 4, ") != declared methods ("
	mov	edx, ecx
	call	printdec32
	printlnc 4, ")"

1:	# next, the overrides
	mov	ecx, [esi + class_over_mcount]
	#jecxz	1f
	or	ecx, ecx
	jz	1f
	mov	edi, esi
	push	esi
	mov	esi, [esi + class_over_mptr]
0:	lodsd	# flags | idx
	lodsd	# target
	mov	edx, eax
	lodsd	# function offset
	###############
	cmp	edx, [edi + class_object_size]
	jb	3f
	printc 4, "warning: method override has illegal target: "
	DEBUG_DWORD [esi-12],"flags|idx"
	DEBUG_DWORD [esi-8], "target"
	DEBUG_DWORD [esi-4], "addr"
	call	printhex8
	printc 4, ", object size: "
	mov	edx, [edi + class_object_size]
	call	printhex8
	call	newline
	pushad
	mov	esi, edi
	call	_class_print$
	popad
	# TODO: further check to see if the override is within any vptr range
	# of all (super)classes.
	jmp	2f	# skip
3:
	###############
	.if OO_DEBUG
		print "override @"
		call	printhex8
		print ": "
		push edx; mov edx, eax; call printhex8; pop edx
		call	printspace
	.endif
	add	eax, [realsegflat]
	cmp	[ebx + edx], dword ptr 0
	jnz	2f	# don't override,already filled in (sub->super iter)
	mov	[ebx + edx], eax
2:	dec ecx;jnz 0b#loop	0b
	pop	esi
1:

	pop_	esi ebx edx eax ecx edi
	ret
.endif

# in: eax = obj
# in: esi = class ([eax+obj_class])
obj_init_vptrs:
.if OBJ_VPTR_COMPACT		# compact vptr
	push_	edi esi ecx
	mov	edi, [esi + class_object_vptr]
	add	edi, eax
	mov	ecx, [esi + class_decl_vptr_count]
	mov	esi, [esi + class_decl_vptr]
	rep	movsd
	pop_	ecx esi edi
.else
	# top-down override, implemented as bottom-up (if) zero (then) change
0:	call	class_init_vptr$	# interleaved vptr
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b
.endif
	ret


# in: esi
_class_print_vptr$:
	push_	ebx ecx esi

	mov	ebx, [esi + class_name]	# for printf
	mov	ecx, [esi + class_decl_vptr_count]
	mov	esi, [esi + class_decl_vptr]

	pushcolor 10
	pushd	ecx
	pushd	esi
	pushd	ebx
	pushstring "vptr table for class '%s' addr %08x count %d\n"
	call	printf
	add	esp, 16
	popcolor

	call	_print_vptr$
	pop_	esi ecx ebx
	ret

# in: eax = obj
_obj_print_vptr$:
	push_	ebx ecx edx esi
	mov	esi, [eax + obj_class]
	.if OO_DEBUG_VPTR
		DEBUG "obj_print_vptr"
		DEBUG_DWORD eax,"obj"
		DEBUG_DWORD esi,"class"
		DEBUGS [esi+class_name]
	.endif

	mov	ecx, [esi + class_decl_vptr_count]
	# esi + ecx * 4 == eax (for compact)
	pushd	[esi+class_object_vptr]
	pushd	ecx
	pushstring "vptr table size %d addr %08x\n"
	call	printf
	add	esp, 12

	lea	ebx, [ecx * 4]
	neg	ebx
	mov	esi, [esi + class_object_vptr]
	cmp	ebx, esi
	jnz	91f
919:	add	esi, eax
	call	_print_vptr$
	pop_	esi edx ecx ebx
	ret
91:	printc 4, "vptr != -4* vptr_count"
	DEBUG_DWORD ebx
	DEBUG_DWORD esi
	jmp	919b

# in: esi = vptr table start
# in: ecx = vptr table length
# in: ebx = vptr rel offset start (0 for class, [eax+class_object_vptr] for obj)
_print_vptr$:
	jecxz	9f
	push	edx

	lea	esi, [esi + ecx * 4]
	xor	ebx, ebx

0:	pushcolor 8
	sub	ebx, 4
	mov	edx, ebx
	call	printhex8
	popcolor
	call	printspace

	sub	esi, 4
	mov	edx, [esi]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	loop	0b
	pop	edx
9:	ret

######################################################################


# in: eax = obj
_obj_print_methods$:
	push_	eax edi edx ebx esi ecx
	mov	ebx, eax
	mov	edi, [eax + obj_class]
	#esi
2:	print "methods for class "
	push	dword ptr [edi + class_name]
	call	_s_print

	print ": vptr: "
	mov	edx, [edi + class_object_vptr]
	call	printhex8

	print " vptrcnt: "
.if OBJ_VPTR_COMPACT
	mov	ecx, [edi + class_object_vptr]
	neg	ecx
.else
	mov	ecx, [edi + class_object_size]
	sub	ecx, [edi + class_object_vptr]
.endif
	shr	ecx, 2
	mov	edx, ecx
	call	printdec32
	print " decl: "
	mov	edx, [edi + class_decl_mcount]
	call	printdec32

	print " override: "
	mov	edx, [edi + class_over_mcount]
	call	printdec32
	call	newline

	jecxz	1f
	mov	esi, [edi + class_object_vptr]
	add	esi, ebx
0:
	print " offs@obj: "
	mov	edx, esi
	sub	edx, ebx
	call	printhex8
	print " ("
	mov	edx, esi
	call	printhex8
	print ")"

	print " method: "
	lodsd
	mov	edx, eax
	call	printhex8
	call	debug_printsymbol
	call	newline
	loop	0b
1:

	mov	edi, [edi + class_super]
	or	edi, edi
	jnz	2b

	pop_	ecx esi ebx edx edi eax
	ret

# in: eax = object
# TODO: call destructor
class_deleteinstance:
	push	ebp
	lea	ebp, [esp + 4]	# for mfree
	push_	esi edi ecx

	mov	edi, [class_instances]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	jz	92f
	sub	[edi + array_index], dword ptr 4
	repnz	scasd
	jnz	91f

0:	mov	[edi - 4], dword ptr 0
	jecxz	1f
	mov	esi, edi
	sub	edi, 4
	rep	movsd
1:

.if OBJ_VPTR_COMPACT
	mov	esi, [eax + obj_class]
	add	eax, [esi + class_object_vptr]
.endif

	call	mfree_
	mov	eax, -1

9:	pop_	ecx edi esi ebp
	STACKTRACE 0
	ret

91:	call	0f
	print "unknown object: "
	push	eax
	call	_s_printhex8
	call	printspace
	push	eax
	call	class_obj_print_classname
	call	newline
	stc
	jmp	9b
92:	call	0f
	print "no instances"
	stc
	jmp	9b
0:	printc 12, "class_deleteinstance: "
	ret


# in: eax = object ptr
# in: edx = class ptr
# out: ZF = 1 if eax's class or superclass is the class in edx
# out: CF = !ZF (i.e.: jz=jc)
class_instanceof:
	or	eax, eax
	jz	9f
	push	eax
	xchg	eax, edx
	call	class_is_class
	jc	91f
	xchg	eax, edx
	mov	eax, [eax + obj_class]
	call	class_is_class
	jc	92f
0:	cmp	eax, edx
	jz	0f
	mov	eax, [eax + class_super]
	or	eax, eax
	jnz	0b
	inc	eax	# clear ZF
	stc
0:	pop	eax
	ret
9:	or	esp, esp
	stc
	ret

91:	printc 12, "class_instanceof: not a class: "
	jmp	1f
92:	printc 12, "class_instanceof: not an object: "
1:	push	eax
	call	_s_printhex8
	stc
	STACKTRACE 4
	jmp	0b


# in: eax = class def ptr to be checked (subclass)
# in: edx = class def ptr to be checked against (superclass)
# out: ZF = 1 if eax extends from, or is, edx
# out: CF = 0 always
class_extends:
	push	eax
0:	cmp	eax, edx
	jz	1f
	mov	eax, [eax + class_super]
	or	eax, eax
	jnz	0b
	inc	eax	# clear ZF
	stc
1:	pop	eax
	ret

# checks if classdef edx is a superclass of instance eax
# in: eax = instance
# in: edx = classdef
class_is_super:
	push	eax
	mov	eax, [eax + obj_class]
	call	class_extends
	pop	eax
	ret


# in: [esp+4] = class def ptr
# in: [esp+0] = static method offset
class_invoke_static:
	push	ebp
	lea	ebp, [esp + 8]
	push_	eax edx
	mov	eax, [ebp + 4]	# class def

	call	class_resolve
	jc	94f

	.if OO_DEBUG
		DEBUG "class_invoke_static "
		DEBUGS [eax+class_name]
		DEBUG_DWORD [ebp]
	.endif

.if OBJ_VPTR_COMPACT
	cmp	dword ptr [ebp], 0
	jns	92f

	mov	edx, [eax + class_decl_vptr_count]
	shl	edx, 2
	add	edx, [eax + class_decl_vptr]
	add	edx, [ebp]
	cmp	edx, [eax + class_decl_vptr]
	jb	92f	# before start
	mov	edx, [edx]	# get method ptr
.else
	#####################
	# little hack
	# quick hack: don't record the object instance.
	push	esi
	mov	esi, eax
	mov	eax, [eax + class_object_size]
	call	mallocz
	jc	91f
	mov	[eax + obj_class], esi
	call	obj_init_vptrs
	pop	esi
	##############
#pushad; mov esi, [eax+obj_class];call _obj_print_methods$; popad

# not called - replaced by above code - due to ptr array containing obsolete entry.
#	call	class_newinstance	# in: eax; out: eax
#	jc	9f
	####################
	# the methods are filled in, so now we can call.
	mov	edx, [ebp] 	# method ptr
	mov	edx, [eax + edx]
	call	mfree
	jc	9f
	# end of hack: we got the vptr
	########################
.endif

	.if OO_DEBUG
		DEBUG_DWORD edx, "static method"
		call debug_printsymbol
	.endif
	mov	[ebp], edx	# replace
	or	edx, edx

	pop_	edx eax
	jz	93f
1:
	# all registers restored. [ebp] contains the method:
	call	[ebp]
0:	pop	ebp
	ret	8	# pop class, method

91:	pop	esi
	printlnc 4, "class_invoke_static: newinstance fail"
9:	pop_	edx eax
	stc
	jmp	0b

# compact; [ebp] >=0
92:	printc 4, "class_invoke_static: invalid method index: "
	mov	edx, [ebp]
	call	printhex8
	call	newline
	int 3
	jmp	9b
93:	# addr 0
	printlnc 4, "class_invoke_static: can't call virtual method (ptr=0)"
	int 3
	jmp	9b
94:	printlnc 4, "class_invoke_static: class resolution failed"
	jmp	9b



# in: [esp + 0] = object
# in: [esp + 4] = api method index
# in: [esp + 8] = classdef ptr
# out: eax = method return value for eax
class_invoke_virtual:
	push	edx
	mov	eax, [esp + 8 + 0]	# object
	mov	edx, [esp + 8 + 8]	# class
	call	class_instanceof
	pop	edx
	# instanceof prints if edx or eax are wrong; keeps silent if not extends
	jc	91f

	# verify the method is implemented
	push	edx
	mov	edx, [esp + 8 + 4]	# method index
	cmp	[eax + edx], dword ptr 0
	pop	edx
	jz	92f

	# macro INVOKEVIRTUAL provides compiletime checking for api method
	# using class_api_ naming convention.

	# the object vptr table allows runtime method overrides, but does
	# not provide method pointers for multiple inheritance.
	#pushd	offset 1f
	push	edx
	mov	edx, [esp + 8 + 4]	# method index
	mov	edx, [eax + edx]	# method ptr
	mov	[esp + 8 + 4], edx	# method index->ptr
.if 0
	pop	edx

	call	[esp + 4 + 4]
.else
# [esp+ 0] edx
# [esp+ 4] invokevirtual ret
# [esp+ 8] object
# [esp+12] api method
# [esp+16] classdef	-> invokevirtual ret
	mov	edx, [esp + 4] # ret
	mov	[esp + 16], edx
	pop	edx
	add esp, 12-4	# 4 for the method ptr ptr
	ret	#call

.endif

	# for multiple inheritance, the method must be looked up in the
	# class definition rather than using the runtime VPTR, as the VPTR
	# only contains a single inheritance hierarchy.
.if 0
	# using multiple inheritance:
	push	edx 	# TODO: optimize
	mov	edx, [esp + 12 + 8]	# class
	mov	eax, [esp + 12 + 4]	# method
	mov	edx, [edx + class_vptr + eax]
	mov	[esp + 12 + 4], edx
	pop	edx
	mov	eax, [esp + 8 + 0]	# object
.endif

9:	STACKTRACE 0
	ret	12

91:	printc 12, "invokevirtual: class cast exception: instance of type "
	pushd	[eax + obj_class]
	call	class_print_classname
	printc 12, " is not a subclass of "
	pushd	[esp + 4 + 8]	# class
	call	class_print_classname
	call	newline
	stc
	jmp	9b
92:	printc 12, "invokevirtual: "
	# get the method name from the classdef
	push	edx
	mov	edx, [esp + 8 + 8]	# class decl ptr
	pushd	[edx + class_name]
	call	_s_print
	printchar '.'

	mov	edx, [esp + 8 + 4]	# method index
	push_	ecx eax
	mov	eax, [esp + 8 + 8 + 8]	# class decl ptr

	neg	edx
	mov	ecx, edx
	lea	edx, [ecx + edx * 2 - 12] # * 12 -12 (mptr struct size)
	add	edx, [eax + class_decl_mptr]
	pop_	eax ecx
	pushd	[edx + 4]	# 4: name ptr
	call	_s_print
	pop	edx

	printc 12, " not implemented in "
	pushd	[eax + obj_class]
	call	class_print_classname
	call	newline
	stc
	jmp	9b


.if 0 # Disabled for now - tested to work
# Dynamically registers a class, as opposed to built-in classes defined
# in DATA_SECTION_CLASSES.
# in: eax = pointer to class definition
class_register:
	push_	eax ebx edx
	mov	ebx, eax
	PTR_ARRAY_NEWENTRY [class_dyn_definitions], 4, 9f	# out: eax+edx
	mov	[eax + edx], ebx
	clc
0:	pop_	edx ebx eax
	ret

9:	printlnc 4, "error registering class"
	stc
	jmp	0b
.endif

# in: STACKARG: method to call for each iteration (popped on behalf of caller)
# Signature of the method being called:
#	in: STACKARG: class def ptr (caller pop)
#	out: CF = 0: abort iteration
#
# Usage:
#
# 	push dword ptr offset my_method
#	call	class_iterate_classes
#	ret
#
# my_method:
#	mov	eax, [esp + 4]	# class def ptr
#	ret
#
class_iterate_classes:
	push	ebp
	lea	ebp, [esp + 8]
	push	eax
	mov	eax, offset data_classdef_start
	jmp	1f
0:	push_	eax		# preserve, and pass as argument
	mov	eax, [esp + 4]	# restore original value of eax
	# TODO: restore other registers to initial values, and leave
	# modified on success.
	call	[ebp]
	pop_	eax
	jnc	2f
	add	eax, [eax + class_def_size]
1:	cmp	eax, offset data_classdef_end
	jb	0b
	stc
2:	pop	eax
	pop	ebp
	ret	4


cmd_classes:
	lodsd
	xor	edx, edx
	lodsd
	or	eax, eax
	jz	1f
	call	class_get_by_name
	jc	91f
	mov	edx, eax
1:

	mov	esi, offset data_classdef_start
	jmp	1f

0:	or	edx, edx
	jz	3f	# don't filter
	mov	eax, esi
	call	class_extends
	jnz	2f

3:	call	_class_print$

	testb	[esi + class_flags], CLASS_FLAG_RESOLVED
	jz	2f
	call	_class_print_vptr$
2:

	add	esi, [esi + class_def_size]
1:	cmp	esi, offset data_classdef_end
	jb	0b
	ret
91:	printlnc 4, "unknown class: "
	push	eax
	call	_s_println
	ret

# in: eax = string ptr
# out: eax = class definition pointer
class_get_by_name:
	push_	esi edi ecx ebx
	mov	ebx, offset data_classdef_start
0:	mov	edx, [ebx + class_name]
	call	strcmp	# in: eax, edx; out: flags
	jz	1f
	add	ebx, [ebx + class_def_size]
	cmp	ebx, offset data_classdef_end
	jb	0b
	stc
0:	pop_	ebx ecx edi esi
	ret
1:	mov	eax, ebx
	jmp	0b


cmd_objects:
	xor	edx, edx	# the class def ptr to compare with
	lodsd
	lodsd
	or	eax, eax
	jz	1f
	call	class_get_by_name
	jc	9f
	mov	edx, eax
1:
	# list classes
	mov	edi, [class_instances]
	PTR_ARRAY_ITER_START edi, ecx, eax
	or	edx, edx
	jz	2f
	call	class_instanceof
	jnz	1f
2:
	push	edx
	mov	edx, eax
	call	printhex8
	or	eax, eax
	pop	edx
	jz	3f
	call	printspace
	push	eax
	call	class_obj_print_classname

######## print hierarchy
	pushcolor 8
	mov	eax, [eax + obj_class]
0:	call	printspace
	call	class_is_class
	jc	2f
	mov	eax, [eax + class_super]
	or	eax, eax
	jz	2f
	mov	esi, [eax + class_name]
	call	print
	jmp	0b
2:	popcolor
3:	call	newline
########
1:	PTR_ARRAY_ITER_NEXT edi, ecx, eax
0:	ret
9:	printc 4, "Unknown class: "
	mov	esi, eax
	call	println
	ret

_class_print$:
	DEBUG_DWORD esi
	DEBUG_DWORD [esi+class_object_size],"objsize"
	DEBUG_DWORD [esi+class_super],"super"
	DEBUG_DWORD [esi+class_object_vptr],"vptr"
	DEBUG_DWORD [esi+class_decl_vptr_count],"vptr.size"
	DEBUG_DWORD [esi+class_decl_mptr],"mptr"
	DEBUG_DWORD [esi+class_decl_mcount],"mcount"
	call	newline
	cmp	dword ptr [esi + class_name], 0
	jz	2f
	push	dword ptr [esi + class_name]
	call	_s_print
2:	#call	newline

	# print extends
	push	esi
0:	mov	esi, [esi + class_super]
	or	esi, esi
	jz	1f
	print " extends "
#	call	_class_print$
	push	dword ptr [esi + class_name]
	call	_s_print
	jmp	0b
1:	pop	esi

	# print methods
	push_	edi ebx
	mov	ebx, esi
	LOAD_TXT "declarations", edi
	add	esi, offset class_decl_mptr
	call	_print_methods$
	LOAD_TXT "overrides", edi
	add	esi, offset class_over_mptr - class_decl_mptr
	call	_print_methods$
	LOAD_TXT "static", edi
	add	esi, offset class_static_mptr - class_over_mptr
	call	_print_methods$
	sub	esi, offset class_static_mptr
	pop_	ebx edi

	# done
	call	newline
	ret

# in: ebx = class def ptr
# in: esi = ptr to class_XXX_mptr in class definition (somewhere in ebx)
_print_methods$:
	push	ecx
	mov	ecx, [esi + 4] # class_decl_mcount]
#	jecxz	1f
	or	ecx, ecx
	jz	1f
	call	newline
	push	edi
	call	_s_print
	print ": "
	push	edx
	mov	edx, ecx
	call	printdec32
	pop	edx
	call	newline
	push_	eax esi edx	# STACKREF!
	mov	esi, [esi] # + class_decl_mptr]
8:
	########################
	print "flags: "
	lodsd
	mov	edx, eax
	call	printhex4
	ror	edx, 16
	print " idx: "
	call	printhex4
	########################
	lodsd
	print " target: "
	test	edx, CLASS_METHOD_FLAG_OVERRIDE<<16 # due to ror
	jz	2f
.if OBJ_VPTR_COMPACT
	printcharc 0xf0,'-'
	mov	edx, [ebx + class_object_vptr]
	add	edx, eax
.endif
	mov	edx, eax
	call	printhex8	# target
	call	printspace
	jmp	3f
2:	movzx	edx, dx
.if OBJ_VPTR_COMPACT
	not	edx	# neg edx; dec edx
	push	eax
	mov	eax, [esp + 8] # get orig esi
	mov	eax, [eax + 4]	# get count
	add	edx, eax
	pop	eax
.endif
	shl	edx, 2
	add	edx, [ebx + class_object_vptr]
	call	printhex8
	print " name: "
	push	eax
	call	_s_print
	call	printspace
3:
	#########################
	lodsd
	mov	edx, eax
	call	printhex8
	or	edx, edx
	jz	3f
	call	printspace
	call	debug_printsymbol
3:	call	newline
	#loop	8b
	dec	ecx
	jnz	8b
	pop_	edx esi eax
1:	pop	ecx
	ret


# in: [esp] = instance
class_obj_print_classname:
	cmpd	[esp + 4], 0
	jz	1f
	push	eax
	mov	eax, [esp + 8]
	mov	eax, [eax + obj_class]
	mov	[esp + 8], eax
	pop	eax
	jmp	class_print_classname

1:	printc 4, "<null>"
	ret	4


# in: [esp] = classdef ptr
class_print_classname:
	push	eax
	mov	eax, [esp + 8]
	call	class_is_class
	jc	91f
	pushd	[eax + class_name]
	call	_s_print
	pop	eax
	ret	4
91:	printc 4, "<not a class:"
	push	eax
	call	_s_printhex8
	printc 4, ">"
	pop	eax
	ret	4

.endif	# DEFINE==1

.ifndef __OO_DECLARED
__OO_DECLARED=1

.section .classdef$vptr
OBJ_decl_vptr=.
OBJ_decl_vptr_count=0
.struct 0
#obj_refcount: .long 0
obj_class: .long 0
obj_size: .long 0	# the data part of the object
OBJ_STRUCT_SIZE = .
.text32

##############################
# Usage:
#
# DECLARE_CLASS_BEGIN foo, superclass
# field: .long 0
# DECLARE_CLASS_METHOD methodname, method_pointer
# DECLARE_CLASS_END


.macro DECLARE_CLASS_BEGIN name, super=OBJ, offs=0
	CLASS = \name
	.section .classdef$md; _DECL_CLASS_DECL_MPTR = .;
		mptr_\name\():
	.section .classdef$mo; _DECL_CLASS_OVERRIDE_MPTR = .;
	.section .classdef$ms; _DECL_CLASS_STATIC_MPTR = .;

	.section .classdef$vptr;
		_class_decl_vptr = .
		.global \name\()_decl_vptr
		\name\()_decl_vptr = .
		.if \super\()_decl_vptr_count > 0
		.space \super\()_decl_vptr_count * 4
		.endif

	# offset feature: truncate parent struct to that size and append from there.
	.ifc \offs,0
	.struct \super\()_STRUCT_SIZE + \offs
	.else
	.struct \offs
	.endif

	# some variables for the _END macro
	_DECL_CLASS_VPTR = -1
	.ifc OBJ,\super
		_DECL_CLASS_SUPER = 0
		_class_vptr_offs = 0
	.else
		_DECL_CLASS_SUPER = class_\super
		_class_vptr_offs = \super\()_vptr	# super.vptr missing!!!
	.endif

	# some new variables.
	_class_data_offs = .
	_class_mdecl_count = 0

	CLASS=\name

#	INVOKE_BEGIN_HANDLERS CLASS
.endm


#########################################################################
# automatic macro invocation on each class declaration
# use:
#  DECLARE_CLASS_BEGIN_HANDLER ASPECT
#   calls DECLARE_CLASS_ASPECT_BEGIN CLASS automatically on each
#   DECLARE_CLASS_BEGIN declaration.
#.altmacro
#.macro invoke_begin_handlers c=CLASS
#.endm
#.macro DECLARE_CLASS_BEGIN_HANDLER name
#	LOCAL invoke_prev_handler
#	.macro invoke_prev_handler c=CLASS
#		_PREV_BEGIN_HANDLER \p \c	# call prev
#		DECLARE_CLASS_\name()_BEGIN \c	# add new
#	.endm
#	.purgem invoke_begin_handlers
#	.macro invoke_begin_handlers c=CLASS
#		invoke_begin_handlers_+\n \c
#	.endm
#
#	_PREV_BEGIN_HANDLER=invoke_prev_handler
#.endm
#.noaltmacro
#########################################################################


# is called automatically
.macro DECLARE_CLASS_METHODS
	_DECL_CLASS_DECL_MCOUNT = 0
	_DECL_CLASS_OVERRIDE_MCOUNT = 0
	_DECL_CLASS_STATIC_MCOUNT = 0

	.if OBJ_VPTR_COMPACT
		_DECL_CLASS_VPTR = 0
	.else
		_DECL_CLASS_VPTR = .
	.endif
.endm


.macro DECLARE_CLASS_METHOD name, offs, flags:vararg

	.if _DECL_CLASS_VPTR < 0
		DECLARE_CLASS_METHODS
	.endif

	_STRUCT_OFFS = .

	_FLAGS = 0
	.irp f,\flags
		.ifnc \f,
		_FLAGS = _FLAGS | CLASS_METHOD_FLAG_\f
		.endif
	.endr

# disabled for now - static treated as virtual.
#	.if _FLAGS & CLASS_METHOD_FLAG_STATIC
#		.print ">>>>> static \name"
#
#		.if  _FLAGS & CLASS_METHOD_FLAG_OVERRIDE
#			# don't declare new....
#		.else
#
#		#.data SECTION_DATA_CLASS_M_STATIC
#		.section .classdef$ms
#			static_m_\name\()_\offs\():	.word CLASS_METHOD_FLAG_STATIC
#			mptr_\name\()_\offs\()_idx:	.word 0 # idx
#							.long \name	# target in obj
#			\name:				.long \offs	# offs
#		.struct _STRUCT_OFFS
#		_DECL_CLASS_STATIC_MCOUNT = _DECL_CLASS_STATIC_MCOUNT + 1
#		.endif
#
#	.else
	.if _FLAGS & CLASS_METHOD_FLAG_OVERRIDE
		.section .classdef$mo
			mptr_\name\()_\offs\()_flags:	.word CLASS_METHOD_FLAG_OVERRIDE
			mptr_\name\()_\offs\()_idx:	.word _vptr_\name
			mptr_\name\()_\offs\()_name:	.long \name
			mptr_\name\()_\offs:		.long \offs
		.struct _STRUCT_OFFS
		_DECL_CLASS_OVERRIDE_MCOUNT = _DECL_CLASS_OVERRIDE_MCOUNT + 1
		# do not add new mptr
	.else
		.section .strings
		999:	.asciz "\name"
		.section .classdef$md
			mptr_\name\()_flags:	.word CLASS_METHOD_FLAG_DECLARE
			mptr_\name\()_idx:	.word _DECL_CLASS_DECL_MCOUNT
			mptr_\name\()_name:	.long 999b
			mptr_\name:		.long \offs

		.section .classdef$vptr
			_vptr_\name = . - _class_decl_vptr	# create increment label
			.global _vptr_\name
			.long 0	# add space for declared method

		.if OBJ_VPTR_COMPACT
			_class_vptr_offs = _class_vptr_offs - 4
			.struct _class_vptr_offs
				\name: .long 0
			.struct _STRUCT_OFFS
		.else
		.struct _STRUCT_OFFS	# method vptr declaration
			\name: .long 0
		.endif
		_DECL_CLASS_DECL_MCOUNT = _DECL_CLASS_DECL_MCOUNT + 1
		.global \name
	.endif
#	.endif
.endm

.macro _PRINT_NUM n
	.if \n == 0
		.print "0"
	.else
		.print "1"
		_PRINT_NUM \n-1
	.endif
.endm

.macro DECLARE_CLASS_END name
	.ifc \name,
	.error "DECLARE_CLASS_END requires classname parameter"
	.endif

	.global \name\()_STRUCT_SIZE 	# for compile-time subclass, see _BEGIN
	\name\()_STRUCT_SIZE = .	# for compile-time subclass, see _BEGIN

	.if _DECL_CLASS_VPTR < 0
		DECLARE_CLASS_METHODS
	.endif

	.global \name\()_vptr
	\name\()_vptr = _class_vptr_offs

	_DECL_CLASS_OBJ_SIZE = .

	.if OBJ_VPTR_COMPACT
		_DECL_CLASS_VPTR = _class_vptr_offs
		_DECL_CLASS_VPTR_SIZE = (_class_vptr_offs)/4#- _DECL_CLASS_VPTR/4
		_DECL_CLASS_OBJ_SIZE = _DECL_CLASS_OBJ_SIZE - _class_vptr_offs
	.else
		_DECL_CLASS_VPTR_SIZE = (. - _DECL_CLASS_VPTR)/4
	.endif

	\name\()_VPTR_SIZE = _DECL_CLASS_VPTR_SIZE


	################### done with .struct (data) section
	.section .classdef$vptr
	.global \name\()_decl_vptr_count
	\name\()_decl_vptr_count = (. - \name\()_decl_vptr)/4

	#################################################
	# check if method declarations are contiguous
	.if !OBJ_VPTR_COMPACT
		.section .classdef$md
		.if (_DECL_CLASS_VPTR_SIZE )!= ( . - _DECL_CLASS_DECL_MPTR )/4/3
			.error "\name: vptr.len != class_num_methods; cannot declare fields after DECLARE_CLASS_METHOD(S)"
			.print "VPTR_SIZE:"
			_PRINT_NUM _DECL_CLASS_VPTR_SIZE
			.print "NUM_METHODS:"
			_PRINT_NUM _DECL_CLASS_DECL_MCOUNT
			.print "NUM_OVERRIDES:"
			_PRINT_NUM _DECL_CLASS_OVERRIDE_MCOUNT

		#	.print "VPTR_SIZE + NUM_OVERRIDES"
		#	_PRINT_NUM (_DECL_CLASS_VPTR_SIZE + _DECL_CLASS_OVERRIDE_MCOUNT)
		.endif
	.endif
	#################################################
	.section .strings
	999:	.asciz "\name"
	#.data SECTION_DATA_CLASSES
	.section .classdef
	.global class_\name\()
	class_\name\():
		.long CLASS_STRUCT_SIZE			# class_def_size
		.long 0					# class_flags
		.long _DECL_CLASS_SUPER			# class_super
		.long _DECL_CLASS_OBJ_SIZE		# class_object_size
		# TODO: .long _DECL_CLASS_OBJ_ALLOC_SIZE - variable length
		.long 999b				# class_name
		.long _DECL_CLASS_VPTR			# class_object_vptr
		.long \name\()_decl_vptr		# class_decl_vptr
		.long \name\()_decl_vptr_count		# class_decl_vptr_count
		.long _DECL_CLASS_DECL_MPTR		# class_decl_mptr
		.long _DECL_CLASS_DECL_MCOUNT		# class_decl_mcount
		.long _DECL_CLASS_OVERRIDE_MPTR		# class_over_mptr
		.long _DECL_CLASS_OVERRIDE_MCOUNT	# class_over_mcount
		.long _DECL_CLASS_STATIC_MPTR		# class_over_mptr
		.long _DECL_CLASS_STATIC_MCOUNT		# class_over_mcount
		.long 0					# class_match_instance
	.text32
.endm


.macro PRINT_CLASS this=eax
	#pushd	[\this + obj_class]
	pushd	\this
	call	class_obj_print_classname
.endm

.macro DEBUG_CLASS this=eax
	PRINT_CLASS \this
.endm

.macro DEBUG_METHOD m, this=eax
	push	edx
	mov	edx, [\this + obj_class]
	pushd	[edx + class_name]
	call	_s_print
	print ".\m: "
	mov	edx, [\this + \m]
	call	debug_printsymbol
	pop	edx
.endm



.macro INVOKEVIRTUAL class, method
	pushd	offset class_\class
	pushd	offset \class\()_api_\method
	pushd	eax
	call	class_invoke_virtual
.endm

.endif	#  __OO_DECLARED
