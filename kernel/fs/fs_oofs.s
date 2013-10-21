##############################################################################
# OOFS: Object Oriented File System
.intel_syntax noprefix
.code32


OOFS_VERBOSE = 1
OOFS_DEBUG = 0
OOFS_DEBUG_ATA = 0


OOFS_PARTITION_TYPE = 0x99	# or 69 or 96
OOFS_MAGIC = ( 'O' | 'O' << 8 | 'F' << 16 | 'S' << 24)

###############################################################################
.if DEFINE

.include "fs/oofs/export.h" # so that GAS doesn't assume memref for constants

DECLARE_CLASS_BEGIN fs_oofs, fs
.global oofs_root
oofs_root:	.long 0	# ptr to oofs root object
oofs_lookup_table: .long 0 # ptr to oofs_table

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
	mov	eax, offset class_oofs_vol
	call	class_newinstance
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
	pushd 0
	call stacktrace
	push_	eax ecx edx
		printlnc 9, "fs_oofs_mkfs"
	call	fs_oofs_init$	# out: eax=oofs, edx=fs_oofs
	jc	91f
	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	jc	94f
	# allocate a new array in the next sector
	push_	edx
	mov	ecx, 512
	mov	edx, offset class_oofs_table #[eax + obj_class]
	call	[eax + oofs_vol_api_add]	# out: eax = instance
	pop_	edx
	jc	92f
	push	edx	# preserve oofs root object for fs_oofs_free$
	call	[eax + oofs_persistent_api_save]
	pop	edx
	jc	93f
	OK
	call	fs_oofs_free$
9:	pop_	edx ecx eax
	ret
91:	PUSHSTRING "class instantiation error"
	jmp	0f
92:	PUSHSTRING "table add error"
	jmp	0f
94:	PUSHSTRING "object init error"
	jmp	0f
93:	PUSHSTRING "table save error"
0:	printc 4, "fs_oofs_mkfs: "
	call	_s_println
	stc
	jmp	9b

fs_oofs_mount:
	.if OOFS_DEBUG
		call	newline
	.endif
	push_	eax edx ecx
	call	fs_oofs_init$
	jc	9f

	mov	ecx, [edx + fs_obj_p_size_sectors]
	call	[eax + oofs_api_init]
	jc	91f
	.if OOFS_DEBUG
		printlnc 9, "fs_oofs_mount: load"
	.endif
	call	[eax + oofs_persistent_api_load]	# out: eax = instance
	jc	91f	# eax destroyed
	mov	[edx + oofs_root], eax	# may be mreallocced
	mov	edi, edx
	# tell oofs the class for the first entry
	mov	edx, offset class_oofs_table
	mov	ecx, 1	# first entry (after root entry)

	.if OOFS_DEBUG
		printc 9, "fs_oofs_mount: load oofs_table: "
		DEBUG_METHOD oofs_vol_api_load_entry
		call	newline
	.endif

	call	[eax + oofs_vol_api_load_entry]	# out: eax
	mov	edx, edi
	jc	91f

	mov	[edi + oofs_lookup_table], eax

	.if 0
		push	ebx
		mov	edx, offset class_oofs_alloc_tbl
		xor	ebx, ebx
		# lookup in oofs_table: out: ecx=entry index
		printc 9, "lookup oofs_alloc_tbl"
		call	[eax + oofs_table_api_lookup]	# out:ecx
		jnc	1f
		printlnc 4, "fs_oofs_mount: adding oofs_alloc_tbl"
		# edx=class_
		mov	eax, [edi + oofs_lookup_table]
		mov	ecx, 512 * 257
		call	[eax + oofs_vol_api_add]
		jc	93f
		printlnc 9, "added oofs_alloc_tbl to oofs"
	1:;	DEBUG_DWORD ecx, "entry"
		mov	eax, [edi + oofs_root]
		printc 9, "oofs_alloc_tbl: oofs.load_entry "
		# in: ecx = entry nr
		# in: edx = classdef ptr
		call	[eax + oofs_vol_api_load_entry] #in:eax,ecx,edx
		jc	94f

	1:	pop	ebx
	.endif

	.if OOFS_DEBUG
	OK
	clc
	.endif
9:	pop_	ecx edx eax
	ret
91:	call	fs_oofs_free$	# in: edx = fs_oofs
	stc
	jmp	9b

93:	printlnc 4, "fs_oofs_mount: failed to register oofs_alloc_tbl"
	jmp	1b
94:	printlnc 4, "fs_oofs_mount: failed to load oofs_alloc_tbl"
	jmp	1b


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
#SHELL_COMMAND "oofs", cmd_oofs # see shell.s
.text32
.global cmd_oofs
cmd_oofs:
	lodsd
	lodsd
	xor	edi, edi	# mountpoint
	or	eax, eax
	jz	1f	# default: list

	cmp	byte ptr [eax], '/'
	jnz	91f
	mov	edi, eax	# expect mountpoint


1:	ARRAY_LOOP [mtab], MTAB_ENTRY_SIZE, ebx, edx, 9f
	pushad
		mov	eax, [ebx + edx + mtab_fs_instance]
		#DEBUG_CLASS
		#DEBUGS	[ebx + edx + mtab_mountpoint]
		#call	newline

		cmp	[eax + obj_class], dword ptr offset class_fs_oofs
		jnz	1f
		or	edi, edi
		jz	2f

		push_	eax edx
		mov	eax, [ebx + edx + mtab_mountpoint]
		mov	edx, edi
		call	strcmp
		pop_	edx eax
		jnz	1f

	2:	printc 9, "OOFS mounted at "
		pushd	[ebx + edx + mtab_mountpoint]
		call	_s_println
		mov	eax, [eax + oofs_root]
		call	[eax + oofs_api_print]
		call	newline

		or	edi, edi
		jz	1f
		DEBUG "match"
		# we have a match. Check command
		mov	ebx, eax	# done with iteration: remember root
		lodsd
		or	eax, eax
		jz	2f

		# we have command
		CMD_ISARG "save"
		jz	oofs_save$

		# other commands have common argument: class or index
		mov	ecx, eax	# backup
		lodsd
		or	eax, eax
		jz	94f

		call	htoi
		jc	3f
		xor	edx, edx	# class null
		xchg	eax, ecx	# ecx=entry index, eax=restore
		jmp	4f


	3:	call	class_get_by_name
		jc	92f
		mov	edx, offset class_oofs
			DEBUGS [eax + class_name]
			DEBUGS [edx + class_name]
		call	class_extends
		jc	93f

		mov	edx, eax	# argument for stuff below

		mov	eax, ecx	# restore
	4:	CMD_ISARG "drop"
		jz	oofs_drop$
		CMD_ISARG "add"
		jz	oofs_add$
		CMD_ISARG "resize"
		jz	oofs_resize$
		call	91f
	2:	popad
		ret

1:	popad
	ARRAY_ENDL
9:	ret

91:	pushcolor 12
	.section .strings
	10:
	.ascii "usage: oofs [mountpoint [command class [args]]]\n"
	.ascii "  commands: add drop resize save\n"
	.ascii "\n\\c\x0f  save\n"
	.ascii "\t\\c\x07persists oofs_vol and oofs_table\n"
	.ascii "\n\\c\x0f  drop (class|index_hex)\n"
	.ascii "\t\\c\x07unloads object if loaded, removes classname from oofs_table,\n"
	.ascii "\tand merges the entry with free space if it is the last.\n"
	.byte 0
	.text32

	pushd	offset 10b
	call	printf
	add	esp, 4
	call	newline
	popcolor
	ret

92:	printc 4, "not a class: "
	mov	esi, eax
	call	println
####### fallthrough

66:
1:	popad
	ret

93:	printc 4, "class not subclass of oofs: "
	pushd	[eax + class_name]
	call	_s_println
	printlnc 4, "run 'classes oofs' to see a complete list"
	jmp	66b

94:	call	91b
	jmp	66b

# in: ebx = root oofs instance
oofs_save$:
	mov	eax, ebx
	call	[eax + oofs_persistent_api_save]
	# lookup table:
	push_	edx ebx
	mov	edx, offset class_oofs_table
	xor	ebx, ebx
	call	[eax + oofs_vol_api_lookup]	# lookup the lookup table
	pop_	ebx edx
	jc	92f
	call	[eax + oofs_persistent_api_save]
	jmp	66b

# in: ebx = root oofs instance
# in: edx = subclass of oofs or 0
# in: ecx = entry index (if edx==0)
oofs_drop$:
	mov	eax, ebx

	or	edx, edx
	jnz	2f
	# find entry with start lba
	mov	ebx, ecx	# in: ebx = start lba
	call	[eax + oofs_vol_api_delete]
	jc	91f

	call	newline
	jmp	3f

2:	push	ebx
	xor	ebx, ebx	# iteration arg
	call	[eax + oofs_vol_api_lookup]	# in: eax,ebx,edx; out: eax=inst,ebx
	mov	edx, ebx	# done with edx: set to idx +1
	pop	ebx
	jc	91f
	DEBUG "found:";
	DEBUG_CLASS

	push	ebx
	mov	edx, eax	# the instance to drop
	mov	eax, ebx	# root oofs obj
	DEBUG "delete from oofs:"
	DEBUG_CLASS
	mov	ebx, edx
	call	[eax + oofs_vol_api_delete]	# in: eax,ebx=index
	pop	ebx

	mov	esi, [edx + obj_class]
	mov	esi, [esi + class_name]

3:	DEBUG "delete from table:"
	# lookup table:
	push_	edx ebx
	mov	edx, offset class_oofs_table
	xor	ebx, ebx
	call	[eax + oofs_table_api_lookup]	# lookup the lookup table
	pop_	ebx edx
	jc	92f

	# eax is now the lookup table instance
	push	edx
	mov	edx, esi
	call	[eax + oofs_table_api_delete] 	# in: eax,edx=name
	pop	edx

#	call	[eax + oofs_persistent_api_save]

	printlnc 4, "drop not implemented"
	jmp	66b
91:	printlnc 4, "drop: no such entry"
	jmp	66b
92:	printlnc 4, "drop: can't lookup oofs_table"
	jmp	66b
93:	printc 4, "drop: no entry with start lba "
	push	ebx
	call	_s_printhex8
	jmp	66b

oofs_add$:
	printc 11, "ADD "
	pushd	[edx + class_name]
	call	_s_print

	# check args
	mov	ecx, eax	# backup this
	lodsd
	or	eax, eax
	jz	1f
	call	atoi
	jc	91f
	cmpd	[esi], 0	# end of args
	jnz	92f

1:	xchg	eax, ecx	# eax = this, ecx = numsect
	or	ecx, ecx
	jnz	1f
	inc	ecx
1:
	printc 11, " numsect "
	mov	edx, ecx
	call	printdec32
	call	newline

	jmp	66b

91:	printc 12, "expect decimal number: "
	pushd	[esi - 4]
	call	newline
	jmp	66b
92:	printc 4, "trailing arguments: "
	lodsd
1:	push	eax
	call	_s_print
	call	printspace
	lodsd
	or	eax, eax
	jnz	1b
	call	newline
	jmp	66b



oofs_resize$:
	printlnc 4, "resize not implemented"
	jmp	66b
.endif
