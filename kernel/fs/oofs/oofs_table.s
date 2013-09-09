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
# in: edx = parent (instace of class_oofs)
# in: ebx = LBA
# in: ecx = reserved size
oofs_table_init:
	.if OOFS_DEBUG
		DEBUG_DWORD eax, "oofs_table_init", 0xe0
		DEBUG_DWORD ebx, "LBA"
		DEBUG_DWORD ecx, "size"
		call	newline
	.endif
	mov	[eax + oofs_parent], edx	# super field ref
	mov	[eax + oofs_lba], ebx
	mov	[eax + oofs_size], ecx
	push	edx
	mov	edx, [edx + oofs_persistence]
	mov	[eax + oofs_persistence], edx
	pop	edx
	mov	[eax + oofs_count], dword ptr 0
	#call	super	# super() / oofs_init
	ret

# aspect extension: pre & post
oofs_table_save:
	call	oofs_save	# call explicit superclass method
	ret


oofs_table_load: # override, or:
	# onload handler
	call	oofs_load	# explicit call; [eax+oofs_api_load -> recursion
	# onloaded handler
	ret

