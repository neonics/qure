#############################################################################
.intel_syntax noprefix

.global class_oofs_table

# use the 'persistent offset' feature. 
# it truncates the parent object data length to offs.
DECLARE_CLASS_BEGIN oofs_table, oofs#, offs=oofs_persistent#, psize=oofs_persistent
# to undo the offset: .space (oofs_persistent - 0)

#oofs_parent:	.long 0	# nonpersistent
#oofs_flags:	.long 0 # nonpersistent
#	OOFS_FLAG_DIRTY = 1

oofs_table_persistent:	# local separator, for subclasses to use.
#oofs_table_magic:	.long 0
#oofs_count:	.long 0

#oofs_table_array:
#oofs_table_lba:	.long 0	# first entry: 0
#oofs_table_size:	.long 0	# first entry: entire partition

#.org 512	# make struct size at least 1 sector

DECLARE_CLASS_METHOD oofs_api_init, oofs_table_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_load, oofs_table_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_save, oofs_table_save, OVERRIDE
#DECLARE_CLASS_METHOD oofs_table_api_save, oofs_table_add
DECLARE_CLASS_END oofs_table
#super = oofs_api_init
#################################################
.text32
# in: eax = instance
oofs_table_init:
	DEBUG "oofs_table_init"
	push	edx
	mov	edx, [eax + obj_class]
	DEBUG_DWORD [edx+class_object_size]
	pop	edx
	#call	super	# super() / oofs_init
	#pop	ebx
	ret

# aspect extension: pre & post
oofs_table_save:
	call	oofs_save	# call explicit superclass method
	ret


oofs_table_load: # override, or:
	# onload handler
	call	[eax + oofs_api_load]	# public access
	# onloaded handler
	ret

