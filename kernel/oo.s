##############################################################################_overrides
# Object Orientation
#
.intel_syntax noprefix


OO_DEBUG = 0

# 'Class' class
.struct 0
class_def_size:		.long 0
class_super:		.long 0
class_object_size:	.long 0	# including the vptr table
class_name:		.long 0
class_vptr:		.long 0 # offset in obj for method pointers
class_decl_mptr:	.long 0 # offset in .data SECTION_DATA_CLASS_M_DECLARATIONS
class_decl_mcount:	.long 0 # nr of methods in mptr
class_over_mptr:	.long 0
class_over_mcount:	.long 0 # nr of override methods in mptr
class_static_mptr:	.long 0
class_static_mcount:	.long 0
class_match_instance:	.long 0
CLASS_STRUCT_SIZE = .
# NOTE: [class_object_size] - [class_vptr] == [class_decl_mcount]*4

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

.if DEFINE

###################################
# GLOBALS / export
# code
.global class_newinstance
.global class_instance_resize
.global class_instanceof
# data
.global class_instances
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
#DEBUG "class_newinstance"; DEBUG_DWORD [class_instances]
#DEBUGS [eax+class_name]
	push	ebp
	lea	ebp, [esp + 4]	# for mallocz_
#pushad
#DEBUG "CLASSES:";call newline; call cmd_classes
#popad
	# quick hack: don't record the object instance.
	push	esi
	mov	esi, eax
	mov	eax, [esi + class_object_size]
	call	mallocz_	# register caller of current method
	jc	9f
	# TODO: move offset to make vptr offsets negative
	mov	[eax + obj_class], esi
.if OO_DEBUG
	push dword ptr [esi + class_name]
	DEBUG "class_newinstance ";DEBUG_DWORD eax
	call _s_print
	DEBUG_DWORD esi
	DEBUG_DWORD [esi+class_super]
	DEBUG_DWORD [eax+obj_class]
	call newline
.endif

	call	class_init_vptrs

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

class_init_vptrs:
	# top-down override, implemented as bottom-up (if) zero (then) change
0:	call	class_init_vptr$
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b
	ret

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
0:	call	class_init_vptrs
	# eax is dummy class: copy data
	push_ 	edi ecx
	mov	esi, [esp + 8]	# old instance (edx)
	mov	edi, eax	# new instance
	mov	edx, [eax + obj_class]
	mov	edx, [edx + class_vptr]
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
	mov	ecx, [edx + obj_size]
	call	mdup
	mov	edx, esi
	call	class_init_vptrs
	pop_	ecx esi
	ret

class_clone:
	mov	edx, [eax + obj_class]
	jmp	class_proxy

# in: eax = instance
# in: edx = new size
# out: eax = new instance
class_instance_resize:
	push_	edi ecx
	# find instance
	mov	edi, [class_instances]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd
	jnz	91f

	call	mreallocz
	jc	9f	# malloc print errors
	mov	[edi - 4], eax

9:	pop_	ecx edi
	ret
91:	printc 4, "class_instance_resize: unknown instance"
	stc
	jmp	9b


# in: eax = object
# in: esi = class def
class_init_vptr$:
	.if OO_DEBUG
		call	newline
		DEBUG "class_init_vptr$ "
		push dword ptr [esi + class_name]
		call _s_print
		DEBUG_DWORD [esi + class_decl_mcount]
		DEBUG_DWORD [esi + class_over_mcount]
	.endif

	# initialize the object method pointers
	push_	edi ecx eax edx ebx esi
	mov	ebx, eax	# backup

		
	# first fill in the declared methods:
	mov	ecx, [esi + class_decl_mcount]
	or ecx, ecx
	jz	1f
#	jecxz	1f
	mov	edi, [esi + class_vptr]	# offset into obj
	#############
	or	edi, edi
	jz	2f
	mov	eax, [esi + class_object_size]
	sub	eax, edi
	jle	2f
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
	#loop	0b
	dec ecx; jnz 0b
	sub	edi, ebx
	pop	esi
	jmp	1f
2:	printc 4, "warning: vptr 0 yet "
	mov	edx, ecx
	call	printdec32
	printlnc 4, " methods declared."
	jmp	1f
3:	printc 4, "error: vptr space "
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
	call	printhex8
	printc 4, ", object size: "
	mov	edx, [edi + class_object_size]
	call	printhex8
	call	newline
	pushad
	mov	esi, edi
	call	_print_class$
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
2:	loop	0b
	pop	esi
1:
	
	pop_	esi ebx edx eax ecx edi
	ret


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
	mov	edx, [edi + class_vptr]
	call	printhex8

	print " declared: "
	mov	ecx, [edi + class_object_size]
	sub	ecx, [edi + class_vptr]
	shr	ecx, 2
	mov	edx, ecx
	call	printdec32

	print " override: "
	mov	edx, [edi + class_over_mcount]
	call	printdec32
	call	newline

	jecxz	1f
	mov	esi, [edi + class_vptr]
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
	push_	esi edi ecx

	mov	edi, [class_instances]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd
	jnz	91f

0:	mov	[edi - 4], dword ptr 0
	jecxz	1f
	mov	esi, edi
	sub	edi, 4
	rep	movsd

1:	call	mfree

	pop_	ecx edi esi
	ret
91:	printlnc 4, "warning: deleting unknown object"
	jmp	0b

# in: eax = object ptr
# in: edx = class ptr
# out: ZF = 1 if eax's class or superclass is the class in edx
class_instanceof:
	push	eax
	mov	eax, [eax + obj_class]
0:	cmp	eax, edx
	jz	1f
	mov	eax, [eax + class_super]
	or	eax, eax
	jnz	0b
	inc	eax	# clear ZF
1:	pop	eax
	ret

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

	#####################
	# little hack
	# quick hack: don't record the object instance.
	push	esi
	mov	esi, eax
	mov	eax, [eax + class_object_size]
	call	mallocz
	jc	91f
	mov	[eax + obj_class], esi
0:	call	class_init_vptr$
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b
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
	.if OO_DEBUG
		DEBUG_DWORD edx,"method offs"
	.endif
	mov	[ebp], edx	# replace
	call	mfree
	jc	9f

	or	edx, edx

	pop_	edx eax
	jnz	1f
	printlnc 4, "error: can't call virtual method (ptr=0)"
	jmp	0f
1:
	# all registers restored. [ebp] contains the method:
	call	[ebp]
0:	pop	ebp
	ret	8	# pop class, method
91:	pop	esi
9:	printlnc 4, "class_invoke_static: newinstance fail"
	pop_	edx eax
	jmp	0b

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
	mov	esi, offset data_classdef_start
	jmp	1f

0:	call	_print_class$
	
	add	esi, [esi + class_def_size]
1:	cmp	esi, offset data_classdef_end
	jb	0b
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
	pop	edx
	call	printspace
	mov	ebx, [eax + obj_class]
	mov	esi, [ebx + class_name]
	call	print

######## print hierarchy
	pushcolor 8
0:	call	printspace
	mov	ebx, [ebx + class_super]
	or	ebx, ebx
	jz	2f
	mov	esi, [ebx + class_name]
	call	print
	jmp	0b
2:	call	newline
	popcolor
########
1:	PTR_ARRAY_ITER_NEXT edi, ecx, eax
0:	ret
9:	printc 4, "Unknown class: "
	mov	esi, eax
	call	println
	ret

_print_class$:
	DEBUG_DWORD esi
	DEBUG_DWORD [esi+class_object_size],"objsize"
	DEBUG_DWORD [esi+class_super],"super"
	DEBUG_DWORD [esi+class_decl_mcount],"#methods"
	DEBUG_DWORD [esi+class_vptr],"vptr"
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
#	call	_print_class$
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

# in: esi = ptr to class_XXX_mptr in class definition
_print_methods$:
	push	ecx
	mov	ecx, [esi + 4] # class_decl_mcount]
#	jecxz	1f
	or	ecx, ecx
	jz	1f
	call	newline
	push	edi
	call	_s_print;call newline
	push_	eax esi edx
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
	mov	edx, eax
	call	printhex8	# target
	call	printspace
	jmp	3f
2:	movzx	edx, dx
	shl	edx, 2
	add	edx, [ebx + class_vptr]
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

.endif	# DEFINE==1

.ifndef __OO_DECLARED
__OO_DECLARED=1

.struct 0
obj_class: .long 0
obj_size: .long 0
OBJ_STRUCT_SIZE = 8
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
	.section .classdef$md; _DECL_CLASS_DECL_MPTR = .;	mptr_\name\():
	.section .classdef$mo; _DECL_CLASS_OVERRIDE_MPTR = .;
	.section .classdef$ms; _DECL_CLASS_STATIC_MPTR = .;

#SECTION_DATA_CLASSES	= 7
#SECTION_DATA_CLASS_M_DECLARATIONS= 8
#SECTION_DATA_CLASS_M_OVERRIDES= 9
#SECTION_DATA_CLASS_M_STATIC= 10
#SECTION_DATA_CLASSES_END = 10

#	.data SECTION_DATA_CLASS_M_DECLARATIONS;_DECL_CLASS_DECL_MPTR = .
#	.data SECTION_DATA_CLASS_M_OVERRIDES;	_DECL_CLASS_OVERRIDE_MPTR = .
#	.data SECTION_DATA_CLASS_M_STATIC;	_DECL_CLASS_STATIC_MPTR = .

	# offset feature: truncate parent struct to that size and append from there.
	.ifc \offs,0
	.struct \super\()_STRUCT_SIZE + \offs
	.else
	.struct \offs
	.endif
	
	# some variables for the _END macro
	_DECL_CLASS_VPTR = 0
	.ifc OBJ,\super
	_DECL_CLASS_SUPER = 0
	.else
	_DECL_CLASS_SUPER = class_\super
	.endif

	.altmacro
	CLASS=\name
	.noaltmacro

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


.macro DECLARE_CLASS_METHODS
	_DECL_CLASS_VPTR = .
	_DECL_CLASS_DECL_MCOUNT = 0
	_DECL_CLASS_OVERRIDE_MCOUNT = 0
	_DECL_CLASS_STATIC_MCOUNT = 0
.endm

MPTR_SIZE = (2+2+4+4)

.macro DECLARE_CLASS_METHOD name, offs, flag=0
	.if _DECL_CLASS_VPTR == 0
		DECLARE_CLASS_METHODS
	.endif

	_STRUCT_OFFS = .

	.ifc \flag,OVERRIDE
		#.data SECTION_DATA_CLASS_M_OVERRIDES
		.section .classdef$mo
			mptr_\name\()_\offs\()_flags:	.word CLASS_METHOD_FLAG_OVERRIDE
			mptr_\name\()_\offs\()_idx:	.word 0 # TODO: find idx
			mptr_\name\()_\offs\()_target:	.long \name
			mptr_\name\()_\offs:		.long \offs
		.struct _STRUCT_OFFS
		_DECL_CLASS_OVERRIDE_MCOUNT = _DECL_CLASS_OVERRIDE_MCOUNT + 1
	.else
	.ifc \flag,STATIC
		#.data SECTION_DATA_CLASS_M_STATIC
		.section .classdef$ms
			static_m_\name\()_\offs\():	.word CLASS_METHOD_FLAG_STATIC
			mptr_\name\()_\offs\()_idx:	.word 0 # idx
							.long \name	# target in obj
			\name:				.long \offs	# offs
		.struct _STRUCT_OFFS
		_DECL_CLASS_STATIC_MCOUNT = _DECL_CLASS_STATIC_MCOUNT + 1

	.else
		.data SECTION_DATA_STRINGS
		999:	.asciz "\name"
		#.data SECTION_DATA_CLASS_M_DECLARATIONS
		.section .classdef$md
			mptr_\name\()_flags:	.word CLASS_METHOD_FLAG_DECLARE
			mptr_\name\()_idx:	.word _DECL_CLASS_DECL_MCOUNT
			mptr_\name\()_target:	.long 999b
			mptr_\name:		.long \offs
		.struct _STRUCT_OFFS	# method vptr declaration
			\name: .long 0
		_DECL_CLASS_DECL_MCOUNT = _DECL_CLASS_DECL_MCOUNT + 1
	.endif
	.endif
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
	\name\()_STRUCT_SIZE = .	# for compile-time subclass, see _BEGIN

	.if _DECL_CLASS_VPTR == 0
		DECLARE_CLASS_METHODS
	.endif

	_DECL_CLASS_OBJ_SIZE = .
	_DECL_CLASS_VPTR_SIZE = (. - _DECL_CLASS_VPTR)/4


	#################################################
	# check if method declarations are contiguous
	#.data SECTION_DATA_CLASS_M_DECLARATIONS
	.section .classdef$md
	_DECL_CLASS_NUM_METHODS = ( . - _DECL_CLASS_DECL_MPTR )/4/3

	.if (_DECL_CLASS_VPTR_SIZE )!= _DECL_CLASS_NUM_METHODS
		.error "vptr.len != class_num_methods; you cannot declare fields after DECLARE_CLASS_METHOD(S)"
	#	.print "VPTR_SIZE:"
	#	_PRINT_NUM _DECL_CLASS_VPTR_SIZE
	#	.print "NUM_METHODS:"
	#	_PRINT_NUM _DECL_CLASS_NUM_METHODS
	#	.print "NUM_DECL:"
	#	_PRINT_NUM _DECL_CLASS_DECL_MCOUNT
	#	.print "NUM_OVERRIDES:"
	#	_PRINT_NUM _DECL_CLASS_OVERRIDE_MCOUNT

	#	.print "VPTR_SIZE + NUM_OVERRIDES"
	#	_PRINT_NUM (_DECL_CLASS_VPTR_SIZE + _DECL_CLASS_OVERRIDE_MCOUNT)
	.endif
	#################################################
	.data SECTION_DATA_STRINGS
	999:	.asciz "\name"
	#.data SECTION_DATA_CLASSES
	.section .classdef
	class_\name\():
		.long CLASS_STRUCT_SIZE			# class_def_size
		.long _DECL_CLASS_SUPER			# class_super
		.long _DECL_CLASS_OBJ_SIZE		# class_obj_size
		# TODO: .long _DECL_CLASS_OBJ_ALLOC_SIZE - variable length
		.long 999b				# class_name
		.long _DECL_CLASS_VPTR			# class_vptr
		.long _DECL_CLASS_DECL_MPTR		# class_decl_mptr
		.long _DECL_CLASS_DECL_MCOUNT		# class_decl_mcount
		.long _DECL_CLASS_OVERRIDE_MPTR		# class_over_mptr
		.long _DECL_CLASS_OVERRIDE_MCOUNT	# class_over_mcount
		.long _DECL_CLASS_STATIC_MPTR		# class_over_mptr
		.long _DECL_CLASS_STATIC_MCOUNT		# class_over_mcount
		.long 0					# class_match_instance 
	.text32
.endm
.endif	#  __OO_DECLARED
