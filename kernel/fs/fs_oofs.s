##############################################################################
# OOFS: Object Oriented File System
.intel_syntax noprefix
.code32


OOFS_VERBOSE = 1
OOFS_DEBUG = 1
OOFS_DEBUG_ATA = 0


OOFS_PARTITION_TYPE = 0x99	# or 69 or 96
OOFS_MAGIC = ( 'O' | 'O' << 8 | 'F' << 16 | 'S' << 24)

###############################################################################
.if DEFINE

DECLARE_CLASS_BEGIN fs_oofs, fs
.global oofs_root
oofs_root:	.long 0	# ptr to root object

# static
DECLARE_CLASS_METHOD fs_api_mkfs,	fs_oofs_mkfs, OVERRIDE,STATIC
DECLARE_CLASS_METHOD fs_api_mount,	fs_oofs_mount, OVERRIDE,STATIC
DECLARE_CLASS_METHOD fs_api_umount,	fs_oofs_umount, OVERRIDE
# instance
DECLARE_CLASS_METHOD fs_api_open,	fs_oofs_open, OVERRIDE
DECLARE_CLASS_METHOD fs_api_close,	fs_oofs_close, OVERRIDE
DECLARE_CLASS_METHOD fs_api_nextentry,	fs_oofs_nextentry, OVERRIDE
DECLARE_CLASS_METHOD fs_api_read,	fs_oofs_read, OVERRIDE
DECLARE_CLASS_METHOD fs_api_create,	fs_oofs_create, OVERRIDE
DECLARE_CLASS_METHOD fs_api_write,	fs_oofs_write, OVERRIDE
DECLARE_CLASS_METHOD fs_api_delete,	fs_oofs_delete, OVERRIDE
DECLARE_CLASS_METHOD fs_api_move,	fs_oofs_move, OVERRIDE
DECLARE_CLASS_END fs_oofs
.text32
# in: al = disk, ah = partition
# out: edx = fs_oofs instance
# out: eax = oofs instance
fs_oofs_init$:
	push_	ebx esi
	call	disk_get_partition
	jc	91f
	cmp	[esi + PT_TYPE], byte ptr OOFS_PARTITION_TYPE
	jnz	92f

	mov	ebx, eax
	mov	eax, offset class_fs_oofs
	call	class_newinstance
	jc	93f

	mov	[eax + fs_obj_disk], bx
	mov	edx, [esi + PT_LBA_START]
	mov	[eax + fs_obj_p_start_lba], edx
	mov	edx, [esi + PT_SECTORS]
	mov	[eax + fs_obj_p_size_sectors], edx

	mov	edx, eax
	mov	eax, offset class_oofs
	push	edx
	call	class_newinstance
	pop	edx
	jc	94f
	mov	[edx + oofs_root], eax
	mov	[eax + oofs_parent], edx
9:	pop_	esi ebx
	ret

91:	call	0f
	printlnc 4, "error reading partition table"
	stc
	jmp	9b

92:	call	0f
	printc 4, "partition not "
	push	edx
	mov	edx, OOFS_PARTITION_TYPE
	call	printhex2
	pop	edx
	call	newline
	stc
	jmp	9b

93:	call	0f
	printlnc 4, "malloc error"
	stc
	jmp	9b
94:	call	0f
	printlnc 4, "class_newinstance error"
	mov	eax, edx
	# call class_deleteinstance?
	stc
	jmp	9b
0:	printc 4, "fs_oofs_init$: "
	ret

fs_oofs_mkfs:
	push_	eax ecx edx
	call	fs_oofs_init$	# out: eax=oofs, edx=fs_oofs
	jc	91f
	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	# allocate a new array in the next sector
	push_	eax edx
	mov	ecx, 512
	mov	edx, offset class_oofs_table #[eax + obj_class]
	call	[eax + oofs_api_add]	# out: eax = instance
	pop_	edx eax
	jc	1f
	call	[eax + oofs_api_save]
	jc	1f
	OK
1:	call	class_deleteinstance
	mov	eax, edx
	call	class_deleteinstance
9:	pop_	edx ecx eax
	ret
91:	printlnc 4, "fs_oofs_mkfs: fs_oofs_init error"
	stc
	jmp	9b

fs_oofs_mount:
	DEBUG "oofs_mount"
	push_	eax edx ecx
	call	fs_oofs_init$
	jc	9f
	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	call	[eax + oofs_api_load]
	mov	[edx + oofs_root], eax	# may be mreallocced
	mov	edi, edx
	# tell oofs the class for the first entry
	mov	edx, offset class_oofs_table
	mov	ecx, 1	# first entry
	call	[eax + oofs_api_load_entry]	# out: eax
	OK
	clc
9:	pop_	ecx edx eax
	ret

fs_oofs_umount:
fs_oofs_open:
fs_oofs_close:
fs_oofs_nextentry:
fs_oofs_read:
fs_oofs_create:
fs_oofs_write:
fs_oofs_delete:
fs_oofs_move:
	DEBUG "not implemented"
	stc
	ret
.endif
