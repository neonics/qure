#############################################################################
.intel_syntax noprefix

###############################################################################
.include "extern.h"
# subclasses included at end
###############################################################################

.global class_oofs
.global oofs_parent

# virtual
.global oofs_api_init
.global oofs_api_print
.global oofs_api_child_moved
# direct/static
.global oofs_init
.global oofs_print

OOFS_DEBUG = 0	# 1 = trace methods; 2 = verbose

DECLARE_CLASS_BEGIN oofs#, relatable
oofs_parent:	.long 0	# nonpersistent

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
DECLARE_CLASS_METHOD oofs_api_print, oofs_print
DECLARE_CLASS_METHOD oofs_api_child_moved, oofs_child_moved
DECLARE_CLASS_END oofs
#################################################
.text32
.global code_oofs_start
code_oofs_start:
# in: eax = instance
# in: edx = parent
oofs_init:
	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_init"
		printc 9, " parent: "
		PRINT_CLASS edx
		call	newline
	.endif

	push	eax
	mov	eax, edx
	mov	eax, [eax + obj_class]
	call	class_is_class
	pop	eax
	jc	91f

	mov	[eax + oofs_parent], edx
	ret

91:	printlnc 4, "oofs_init: parent not a class"
	stc
	STACKTRACE 0
	ret

# in: eax = this
oofs_print:
	pushd 0
	call stacktrace
	printc 11, "Object "
	push	eax
	call	_s_printhex8
	printc 11, " class "
	DEBUG_CLASS
	call	newline
	ret

oofs_child_moved:
	DEBUG_CLASS
	printc 13, ".oofs_child_moved: "
	printlnc 12, "event ignored"
	pushd	0
	call	stacktrace
	int 3
	ret

###############################################################################
.include "oofs_persistent.s"
.include "oofs_vol.s"
.include "oofs_table.s"
.include "oofs_alloc.s"

.include "oofs_array.s"
.include "oofs_hash.s"
.include "oofs_hashidx.s"
###############################################################################
.global code_oofs_end
code_oofs_end:
