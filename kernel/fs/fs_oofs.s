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

# destructor
# in: edx = fs_oofs instance
fs_oofs_free$:
	mov	eax, [edx + oofs_root]
	call	class_deleteinstance
	mov	eax, edx
	call	class_deleteinstance
	ret

fs_oofs_mkfs:
	push_	eax ecx edx
	call	fs_oofs_init$	# out: eax=oofs, edx=fs_oofs
	jc	91f
	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	# allocate a new array in the next sector
	push_	edx
	mov	ecx, 512
	mov	edx, offset class_oofs_table #[eax + obj_class]
	call	[eax + oofs_api_add]	# out: eax = instance
	pop_	edx
	jc	92f
	push	edx	# preserve oofs root object for fs_oofs_free$
	call	[eax + oofs_api_save]
	pop	edx
	jc	93f
	OK
1:	call	fs_oofs_free$
9:	pop_	edx ecx eax
	ret
91:	PUSHSTRING "class instantiation error"
	jmp	0f
92:	PUSHSTRING "table add error"
	jmp	0f
93:	PUSHSTRING "table save error"
0:	printc 4, "fs_oofs_mkfs: "
	call	_s_println
	stc
	jmp	9b

fs_oofs_mount:
	push_	eax edx ecx
	call	fs_oofs_init$
	jc	9f
	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	jc	91f
	call	[eax + oofs_api_load]	# out: eax = instance
	jc	91f	# eax destroyed
	mov	[edx + oofs_root], eax	# may be mreallocced
	mov	edi, edx
	# tell oofs the class for the first entry
	mov	edx, offset class_oofs_table
	mov	ecx, 1	# first entry
	call	[eax + oofs_api_load_entry]	# out: eax
	mov	edx, edi
	jc	91f
	OK
	clc
9:	pop_	ecx edx eax
	ret
91:	call	fs_oofs_free$
	stc
	jmp	9b


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


############################################################################
__FOO:
SHELL_COMMAND oofs, cmd_oofs
.text32
cmd_oofs:
	ARRAY_LOOP [mtab], MTAB_ENTRY_SIZE, ebx, edx, 9f
	pushad
		DEBUGS	[ebx + edx + mtab_mountpoint]
		mov	eax, [ebx + edx + mtab_fs_instance]
		mov esi, [eax+obj_class]
		DEBUGS [esi+class_name]
		call newline


		cmp	[eax + obj_class], dword ptr offset class_fs_oofs
		jnz	1f
		printc 9, "OOFS mounted at "
		mov	esi, [ebx + edx + mtab_mountpoint]
		call	println
		mov	eax, [eax + oofs_root]
		call	[eax + oofs_api_print]
		call	newline
1:	popad
	ARRAY_ENDL
9:	ret

.endif
