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

.data SECTION_DATA_CLASSES
class_definitions:	# idem to data_classes_start
.data
class_instances:	.long 0	# aka objects
class_dyn_definitions:	.long 0 # ptr_array of dynamically registered class defs

.text32
# in: eax = class_ definition pointer
# out: eax = instance
class_newinstance:
#pushad
#DEBUG "CLASSES:";call newline; call cmd_classes
#popad
	# quick hack: don't record the object instance.
	push	esi
	mov	esi, eax
	mov	eax, [esi + class_object_size]
	call	mallocz
	jc	9f
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

0:	call	class_init_vptr$
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b

	# register the class in the class_instances ptr_array
	push	edx
	push	eax
	PTR_ARRAY_NEWENTRY [class_instances], 20, 9f
	add	edx, eax
	pop	eax
	mov	[edx], eax
	pop	edx

0:	pop	esi
	ret
9:	printlnc 4, "class_newinstance: out of memory"
	stc
	jmp	0b

# in: esi = class definition
# in: eax = object/class instance
class_init_vptr_OLD$:
	.if OO_DEBUG
		DEBUG "class_init_vptr$ "
		push dword ptr [esi + class_name]
		call _s_print
		DEBUG_DWORD [esi + class_decl_mcount]
		DEBUG_DWORD [esi + class_over_mcount]
	.endif

	# initialize the object method pointers
	push_	edi ecx eax edx ebx esi
	mov	ebx, eax	# backup

	mov	edi, [esi + class_vptr]	# offset into obj
	.if OO_DEBUG
		DEBUG_DWORD edi,"vptr"
	.endif
	or	edi, edi
	jnz	1f	# obj doesn't declare space for method ptrs
	mov	edi, [esi + class_object_size]
	# XXX this will likely overwrite memory!!
	printc 0xf4, "WARNING: overwriting mem for vptr"
1:
	xchg	eax, edi	# without: edi=obj+vptr,eax=obj;
	add	edi, eax	# with: edi=obj+vptr,eax=vptr
	.if OO_DEBUG
		DEBUG_DWORD edi,"first method@obj"
	.endif
	neg	eax
	add	eax, [esi + class_object_size]
	shr	eax, 2
	.if OO_DEBUG
		DEBUG_DWORD eax,"vptr.length"
		DEBUG_DWORD [esi+class_over_mcount]
	.endif
	add	eax, [esi + class_over_mcount]

#	mov	ecx, [esi + class_def_size]
#	sub	ecx, CLASS_STRUCT_SIZE
	mov	ecx, [esi + class_decl_mcount]
	.if OO_DEBUG
		DEBUG_DWORD ecx,"class_decl_mcount"
		call	newline
	.endif
	DEBUG_DWORD eax;DEBUG_DWORD ecx

	cmp	eax, ecx
	jnz	91f
#	shr	ecx, 2
	or	ecx, ecx
	jz	1f	# class doesn't list any methods
	
	mov	esi, [esi + class_decl_mptr]
0:	lodsd	# dx=flags, high = idx
	test	ax, CLASS_METHOD_FLAG_OVERRIDE
	lodsd	# target
	mov	edx, eax
	#or	eax, eax
	lodsd	# method address
	jz	2f	# no override/target is 0, so, normal method ptr
	.if OO_DEBUG
		DEBUG_DWORD edx,"override offs"
		push edx;add edx, ebx; DEBUG_DWORD edx,"@";pop edx
	.endif
	# edx/target is not 0: override method. it is the offset in the obj
	# where to store the ptr
	add	eax, [realsegflat]
	cmp	[ebx + edx], dword ptr 0
	jnz	3f	# don't override,already filled in (sub->super iter)
	mov	[ebx + edx], eax
	jmp	3f

2:	
	.if OO_DEBUG
		DEBUG "normal"
		DEBUG_DWORD edi,"method_ptr@obj"
	.endif
	add	eax, [realsegflat] # obsolete relocation
	cmp	dword ptr [edi], 0
	jnz	41f	# 
	stosd
3:
	.if OO_DEBUG
		mov	edx, eax
		sub	edx, [realsegflat]
		call	printhex8
		call	printspace
		call	debug_printsymbol
		call	newline
	dec	ecx
	jnz	0b
	.else
	loop	0b
	.endif

1:	
	.if 0	# print the method pointers in the obj struct
	push_	esi eax
	mov	eax, ebx	# object
	mov	esi, [esp]	# class
	call	_obj_print_methods	# in: ebx = obj, esi = class
	pop	eax esi
	.endif

	pop_	esi ebx edx eax ecx edi
	ret

41:	
	.if OO_DEBUG
		DEBUG "skip"
	.endif
	add	edi, 4
	jmp	3b

91:	printlnc 4, "class method declaration does not match object vptr"
	DEBUG_DWORD eax,"(obj_size-obj_vptr)/4"
	DEBUG_DWORD ecx,"class_decl_mcount"
	jmp	1b


# in: eax = object
# in: esi = class def
class_init_vptr$:
	.if 1#OO_DEBUG
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
	mov	esi, [esi + class_decl_mptr]
0:	lodsd	# flags | idx
	lodsd	# target (override) or name (decl)
	lodsd	# function offset
	stosd	# store in vptr
	print "declare "
	loop	0b
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
		print "override @"
		call	printhex8
		print ": "
		push edx; mov edx, eax; call printhex8; pop edx
		call	printspace
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
# in: esi = class def
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
	mov	eax, [esi + class_object_size]
	call	mallocz
	jc	9f
	mov	[eax + obj_class], esi
0:	call	class_init_vptr$
	mov	esi, [esi + class_super]
	or	esi, esi
	jnz	0b
	pop	esi
	##############

# not called - replaced by above code - due to ptr array containing obsolete entry.
#	call	class_newinstance	# in: eax; out: eax
#	jc	9f
	####################
	# the methods are filled in, so now we can call.
	mov	edx, [ebp] 	# method ptr
	mov	edx, [eax + edx]
	DEBUG_DWORD edx,"method offs"
	mov	[ebp], edx	# replace
	call	mfree
	jc	9f
	pop_	edx eax
	# all registers restored. [ebp] contains the method:
	call	[ebp]
0:	pop	ebp
	ret	8	# pop class, method
9:	printlnc 4, "class_invoke_static: newinstance fail"
	pop_	edx eax
	jmp	0b

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


cmd_classes:
	mov	esi, offset data_classes_start
	jmp	1f

0:	call	_print_class$
	
	add	esi, [esi + class_def_size]
1:	cmp	esi, offset data_classes_end
	jb	0b
	ret

# in: eax = string ptr
# out: eax = class definition pointer
class_get_by_name:
	push_	esi edi ecx ebx
	mov	ebx, offset data_classes_start
0:	mov	edx, [ebx + class_name]
	call	strcmp	# in: eax, edx; out: flags
	jz	1f
	add	ebx, [ebx + class_def_size]
	cmp	ebx, offset data_classes_end
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
	call	newline
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

##############################
# Usage:
#
# DECLARE_CLASS_BEGIN foo, superclass
# field: .long 0
# DECLARE_CLASS_METHOD methodname, method_pointer
# DECLARE_CLASS_END


.macro DECLARE_CLASS_BEGIN name, super=OBJ
	.data SECTION_DATA_CLASS_M_DECLARATIONS;_DECL_CLASS_DECL_MPTR = .
	.data SECTION_DATA_CLASS_M_OVERRIDES;	_DECL_CLASS_OVERRIDE_MPTR = .
	.data SECTION_DATA_CLASS_M_STATIC;	_DECL_CLASS_STATIC_MPTR = .

	.struct \super\()_STRUCT_SIZE
	
	# some variables for the _END macro
	_DECL_CLASS_VPTR = 0
	.ifc OBJ,\super
	_DECL_CLASS_SUPER = 0
	.else
	_DECL_CLASS_SUPER = class_\super
	.endif
.endm

.macro DECLARE_CLASS_METHODS
	_DECL_CLASS_VPTR = .
	_DECL_CLASS_DECL_MCOUNT = 0
	_DECL_CLASS_OVERRIDE_MCOUNT = 0
	_DECL_CLASS_STATIC_MCOUNT = 0
.endm

.macro DECLARE_CLASS_METHOD name, offs, flag=0
	.if _DECL_CLASS_VPTR == 0
		DECLARE_CLASS_METHODS
	.endif

	_STRUCT_OFFS = .

	.ifc \flag,OVERRIDE
		.data SECTION_DATA_CLASS_M_OVERRIDES
			mptr_\name\()_\offs\()_flags:	.word CLASS_METHOD_FLAG_OVERRIDE
			mptr_\name\()_\offs\()_idx:	.word 0 # TODO: find idx
			mptr_\name\()_\offs\()_target:	.long \name
			mptr_\name\()_\offs:		.long \offs
		.struct _STRUCT_OFFS
		_DECL_CLASS_OVERRIDE_MCOUNT = _DECL_CLASS_OVERRIDE_MCOUNT + 1
	.else
	.ifc \flag,STATIC
		.data SECTION_DATA_CLASS_M_STATIC
			static_m_\name\()_\offs\():	.word CLASS_METHOD_FLAG_STATIC
			mptr_\name\()_\offs\()_idx:	.word 0 # idx
							.long \name	# target in obj
			\name:				.long \offs	# offs
		.struct _STRUCT_OFFS
		_DECL_CLASS_STATIC_MCOUNT = _DECL_CLASS_STATIC_MCOUNT + 1

	.else
		.data SECTION_DATA_STRINGS
		999:	.asciz "\name"
		.data SECTION_DATA_CLASS_M_DECLARATIONS
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
	.data SECTION_DATA_CLASS_M_DECLARATIONS
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
	.data SECTION_DATA_CLASSES
	class_\name\():
		.long CLASS_STRUCT_SIZE			# class_def_size
		.long _DECL_CLASS_SUPER			# class_super
		.long _DECL_CLASS_OBJ_SIZE		# class_obj_size
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
