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
oofs_alloc:	.long 0	# ptr to oofs_alloc
#oofs_handles:	.long 0	# cache array

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
	jc	91f

	mov	[edi + oofs_lookup_table], eax


	mov	edx, offset class_oofs_alloc
	# eax is still lookup table
	call	[eax + oofs_table_api_lookup]	# out: ecx
	jc	1f	# not added/found yet, ok.
	mov	eax, [edi + oofs_root]
	call	[eax + oofs_vol_api_load_entry]
	jc	1f
	mov	[edi + oofs_alloc], eax
	mov	eax, [edi + oofs_root]
	call	[eax + oofs_api_print]
1:	clc

	.if OOFS_DEBUG
	OK
	clc
	.endif
9:	pop_	ecx edx eax
	ret
91:	call	fs_oofs_free$	# in: edx = fs_oofs
	stc
	jmp	9b

93:	printlnc 4, "fs_oofs_mount: failed to register oofs_alloc"
	jmp	1b
94:	printlnc 4, "fs_oofs_mount: failed to load oofs_alloc"
	jmp	1b


fs_oofs_umount:
	DEBUG "umount"; jmp 1f
fs_oofs_read:
	DEBUG "read"; jmp 1f
fs_oofs_write:
	DEBUG "write"; jmp 1f
fs_oofs_delete:
	DEBUG "delete"; jmp 1f
fs_oofs_move:
	DEBUG "move";
1:	DEBUG "not implemented"
	STACKTRACE 0
	stc
	ret

# in: eax = fs
# in: edi = fs_dirent
# in: ebx = directory handle
fs_oofs_create:
	DEBUG "create"
	DEBUG_DWORD ebx
	push_	ebx edx

	push	eax
	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc handle_get
	mov	ebx, eax
	pop	eax
	jc	91f	# note: destroys ebx

	xchg	eax, ebx
	mov	edx, offset class_oofs_tree
	call	class_instanceof
	xchg	eax, ebx
	jc	91f
	xchg	eax, ebx
	mov	edx, edi
	INVOKEVIRTUAL oofs_tree add
	mov	eax, ebx	# restore this
9:	pop_	edx ebx
	STACKTRACE 0
	ret
91:	printc 12, "fs_oofs_create: invalid handle: "
	push	ebx
	call	_s_printhex8
	call	newline
	stc
	jmp	9b

# in: eax = fs info
# in: ebx = dir handle
# in: ecx = cur entry
# in: edi = fs dir entry struct
# out: ecx = next entry (-1 for none)
# out: edx = directory name
fs_oofs_nextentry:
	push	eax

	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc handle_get	# ebx -> eax
	jc	91f

	# verify instance is oofs_tree
	or	eax, eax
	jz	9f
	push_	edx
	mov	edx, offset class_oofs_tree
	call	class_instanceof
	pop_	edx
	jc	92f

	INVOKEVIRTUAL oofs_tree next	# in: ecx=idx/offs; out: edx=ptr, ecx=next idx/offs
	jc	9f	# cur entry doesn't exist

	push_	esi edi ecx
	mov	ecx, FS_DIRENT_STRUCT_SIZE >> 2
	mov	esi, edx
	rep	movsd
	mov	cl, FS_DIRENT_STRUCT_SIZE & 3
	rep	movsb
	pop_	ecx edi esi

0:	pop	eax
	ret

9:	mov	ecx, -1
	jmp	0b

91:	printc 12, "fs_oofs_nextentry: invalid handle: "
	push	ebx
	call	_s_printhex8
	call	newline
	stc
	jmp	9b

92:	printc 12, "fs_oofs_nextentry: illegal instance: not oofs_tree: "
	PRINT_CLASS eax
	call	newline
	stc
	jmp	9b


# in: eax = this
# in: esi = file/dir name
# in: ebx = directory handle / -1 for root
# in: edi = fs direntry struct to be filled
# out: ebx = our handle
fs_oofs_open:
	#DEBUG "open"; DEBUG_DWORD ebx; DEBUGS esi
	cmp	ebx, -1
	jnz	1f

######## open root
	push_	esi edx ebx eax ebp
	lea	ebp, [esp + 4]
	mov	eax, [eax + oofs_alloc]
	or	eax, eax
	jz	91f

	mov	edx, offset class_oofs_txtab
	call	[eax + oofs_alloc_api_txtab_get] # in: edx; out: eax=txtab
	jc	92f
	# get HEAD: entry 0

	xor	ebx, ebx
	INVOKEVIRTUAL oofs_txtab get	# ebx->ebx
	jnc	2f

	# initialize the translation table (symbolic handle references)
	# allocate a handle for HEAD:
	push_	ecx eax
	mov	ecx, 1
	mov	eax, [ebp]	# fs_oofs
	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc alloc	# out: ebx
	pop_	eax ecx
	jc	93f
	# insert it into the txtab
	mov	edx, ebx	# handle
	xor	ebx, ebx	# index
	INVOKEVIRTUAL oofs_txtab set #	call [eax + oofs_txtab_api_set]
	jc	94f
	mov	ebx, edx	# HEAD handle index
	# save txtab
	mov	eax, [ebp]
	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc txtab_save	# in: eax.
	jc	94f

2:	# ebx = handle for HEAD
	jc	9f

	# load handle content
	mov	eax, offset class_oofs_tree
	call	class_newinstance
	jc	96f
	# in: ebx = handle
	# in: edx = oofs_alloc
	mov	edx, [ebp]
	mov	edx, [edx + oofs_alloc]
	mov	esi, ebx	# backup alloc handle index
	INVOKEVIRTUAL oofs init	# out: ebx = fs handle index
	jc	96f

	mov	edx, eax

	mov	eax, [ebp]	# just in case
	mov	eax, [eax + oofs_alloc]
	push	eax
	xchg	ebx, esi	# ebx = alloc handle index, esi=fs handle idx
	INVOKEVIRTUAL oofs_alloc handle_load	# ebx->eax
	pop	eax
	jc	95f

	# return the handle index
	mov	[ebp + 4], esi # update ebx return value
#	DEBUG_DWORD esi

9:	pop_	ebp eax ebx edx esi
	STACKTRACE 0
	ret

91:	printlnc 12, "no oofs_alloc region"
	stc
	jmp	9b
92:	printlnc 12, "no oofs_txtab"
	stc
	jmp	9b
93:	printlnc 12, "can't alloc HEAD"
	stc
	jmp	9b
94:	printlnc 12, "can't record HEAD"
	stc
	jmp	9b
95:	printlnc 12, "error loading dir"
	stc
	jmp	9b
96:	printlnc 12, "can't instantiate oofs_tree"
	stc
	jmp	9b
97:	printlnc 12, "error finding handle index"
	stc
	jmp	9b

####### open subdir/file
# in: ebx = parent directory handle
# in: esi = entry name
1:	push_	eax edx	# stackref!

	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc handle_get	# ebx->eax
	jc	91f

	INVOKEVIRTUAL oofs_tree find_by_name	# esi->esi,ebx
	jc	9f	# not found
	# edi to be filled
	push_	edi ecx esi
	mov	ecx, FS_DIRENT_STRUCT_SIZE >> 2
	rep	movsd
	mov	cl, FS_DIRENT_STRUCT_SIZE & 3
	rep	movsb
	pop_	esi ecx edi

	# return a handle index in ebx.

	# check if the handle is allocated:
	cmp	ebx, -1
	jnz	1f
	# not allocated. Don't instantiate, but register the fs handle:
	xor	edx, edx	# null object
	mov	eax, [esp + 4]	# this
	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc handle_register # out: ebx = fs handle idx
	jc	95f
	jmp	9f


1:	mov	edx, eax	# backup eax = parent handle instance
	mov	eax, offset class_oofs_tree
	call	class_newinstance
	# in: ebx = handle
	# in: edx = oofs_alloc
	mov	edx, [esp + 4]	# this
	mov	edx, [edx + oofs_alloc]
	INVOKEVIRTUAL oofs init	# out: ebx = handle index
	jc	93f


9:	pop_	edx eax
	ret

90:	PUSH_TXT "fs_oofs_open: %s\n"
	PUSHCOLOR 12
	call	printfc
	POPCOLOR
	add	esp, 8
	stc
	jmp	9b

91:	PUSH_TXT "invalid handle"
	jmp	90b
92:	PUSH_TXT "error instantiating oofs_tree"
	jmp	90b
93:	PUSH_TXT "error initializing oofs_tree"
	jmp	90b
95:	PUSH_TXT "error registering handle"
	jmp	90b


# in: ebx = directory/file handle
fs_oofs_close:
	cmp	ebx, -1
	jz	1f
	# ebx is handle index
	push	eax
	mov	eax, [eax + oofs_alloc]
	INVOKEVIRTUAL oofs_alloc handle_remove
	jc	91f
	or	eax, eax	# null (unallocated) handle object?
	jz	9f
	call	class_deleteinstance
9:	pop	eax
	STACKTRACE 0
1:	ret
91:	printc 12, "fs_oofs_close: invalid handle: "
	push	ebx
	call	_s_printhex8
	call	newline
	stc
	jmp	9b

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
		push	eax
		mov	eax, [eax + oofs_root]
		call	[eax + oofs_api_print]
		pop	eax
		call	newline

		or	edi, edi
		jz	1f
		# we have a match. Check command
		mov	ebx, eax	# done with iteration: remember fs
		lodsd
		or	eax, eax
		jz	2f

		# we have command
		CMD_ISARG "save"
		jz	oofs_save$

		# other commands have common argument: class or index
		mov	ecx, eax	# backup command str ptr

		lodsd
		or	eax, eax
		jz	94f

		call	htoi
		jc	3f
		xor	edx, edx	# class null
		xchg	eax, ecx	# ecx=entry index, eax=restore cmd
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
	4:
		# edx = classdef or 0
		# ecx = entry when ecx = 0 or undefined

		CMD_ISARG "drop"
		jz	oofs_drop$
		CMD_ISARG "add"
		jz	oofs_add$
		CMD_ISARG "resize"
		jz	oofs_resize$
		CMD_ISARG "load"
		jz	oofs_load$
		CMD_ISARG "show"
		jz	oofs_show$
		call	91f
	2:	popad
		ret

1:	popad
	ARRAY_ENDL
	# check if there were arguments
	or	edi, edi
	jz	9f
	printc 12, "oofs not mounted at "
	mov	esi, edi
	call	println
9:	ret

91:	pushcolor 12
	.section .strings
	10:
	.ascii "usage: oofs [mountpoint [command class [args]]]\n"
	.ascii "  commands: add drop resize save show\n"

	.ascii "\n\\c\x0f  save [class|index_hex]\n"
	.ascii "\t\\c\x07persists oofs_vol and oofs_table OR the given entry\n"

	.ascii "\n\\c\x0f  drop (class|index_hex)\n"
	.ascii "\t\\c\x07unloads object if loaded, removes classname from "
	.ascii "oofs_table, and merges\n"
	.ascii "\tthe entry with free space if it is the last.\n"

	.ascii "\n\\c\x0f  add <class> <sectors_hex>\n"
	.ascii "\\c\x07\tadds a region to oofs_vol and oofs_table.\n"

	.ascii "\n\\c\x0f  load (class|index_hex)\n"
	.ascii "\t\\c\x07loads the specified entry.\n"

	.ascii "\n\\c\x0f  show (class|index_hex)\n"
	.ascii "\t\\c\x07prints the contents of the specified object.\n"
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


# in: eax = argument string pointer: (class|hex_id)
# out: edx = 0 or classdef ptr
# out: ecx = entry index if edx = 0, undefined otherwise
parse_entry_arg$:
	call	htoi
	jc	1f	# not hex
	# is hex index
	xor	edx, edx	# class null
	mov	ecx, eax
	DEBUG_DWORD ecx, "entry index"
	# clc
	ret

1:	call	class_get_by_name	# eax->eax
	jc	91f
	mov	edx, offset class_oofs
		DEBUGS [eax + class_name]
		DEBUGS [edx + class_name]
	call	class_extends
	jc	92f

9:	ret


91:	printc 4, "not a class: "
	push	eax
	call	_s_println
	stc
	jmp	9b

92:	printc 4, "class not subclass of oofs: "
	pushd	[eax + class_name]
	call	_s_println
	printlnc 4, "run 'classes oofs' to see a complete list"
	stc
	jmp	9b


# in: ebx = class_oofs instance
oofs_save$:
	lodsd
	or	eax, eax
	jz	1f	# save oofs_vol and oofs_table

	DEBUGS eax

	# save specific entry
	call	parse_entry_arg$
	jc	66b
	DEBUG "arg:"
	DEBUG_DWORD edx
	DEBUG_DWORD ecx
	or	edx, edx
	jz	2f	# have entry nr

	# lookup entry index for classdef
	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_table_api_lookup]
	jc	92f
	DEBUG_DWORD ecx,"index"

	# save by entry-index
2:	mov	eax, [ebx + oofs_root]
	xchg	ecx, ebx
	call	[eax + oofs_vol_api_get_obj]
	xchg	ecx, ebx
	jc	91f
	DEBUG_DWORD eax,"got obj"
	call	[eax + oofs_persistent_api_save]
	jmp	66b

	# save vol and table
1:	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_persistent_api_save]
	mov	eax, [ebx + oofs_root]
	call	[eax + oofs_persistent_api_save]
	jmp	66b

91:	printc 4, "no such entry: "
	push	ecx
	call	_s_printhex8
	call	newline
	stc
	jmp	66b

92:	printc 4, "no such entry: "
	pushd	[edx + class_name]
	call	_s_println
	stc
	jmp	66b


# in: ebx = class_oofs instance
# in: edx = subclass of oofs or 0
# in: ecx = entry index (if edx==0)
oofs_drop$:
	mov	eax, [ebx + oofs_root]

	or	edx, edx
	jz	1f
	# have class, look up index
	push	ebx
	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_table_api_lookup]	# out: ecx
	pop	ebx
	jc	91f	# not found

1:	# ecx = entry number

	push	ebx
	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_table_api_clear_entry]
	pop	ebx
	#jc	91f	# entry might not be loaded

	push	ebx
	mov	eax, [ebx + oofs_root]
	mov	ebx, ecx	# in: ebx = entry index
	call	[eax + oofs_vol_api_delete]
	pop	ebx
	jc	91f

#	call	[eax + oofs_persistent_api_save]

	jmp	66b
91:	printlnc 4, "drop: no such entry"
	jmp	66b
93:	printc 4, "drop: no entry with start lba "
	push	ebx
	call	_s_printhex8
	jmp	66b

# in: edx = class to add
# in: ebx = class_oofs instance
oofs_add$:
	printc 11, "add "
	pushd	[edx + class_name]
	call	_s_print

	# check args
	lodsd
	or	eax, eax
	jz	1f
	call	htoi
	jc	91f
	cmpd	[esi], 0	# end of args
	jnz	92f

1:	mov	ecx, eax	# ecx = numsect
	or	ecx, ecx
	jnz	1f
	inc	ecx
1:
	printc 11, " numsect "
	push	ecx
	call	_s_printhex8
	call	newline

	shl	ecx, 9
	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_table_api_add]
	jmp	66b

91:	printc 12, "expect hex number: "
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


# in: ebx = class_oofs instance
# in: edx = subclass of oofs or 0
# in: ecx = entry index (if edx==0)
oofs_load$:
	or	edx, edx
	jnz	1f

	# find class by index
	push	ebx
	mov	eax, [ebx + oofs_lookup_table]
	mov	ebx, ecx	# index
	call	[eax + oofs_table_api_get] # in: ecx=index; out: edx=string
	pop	ebx
	jc	93f
	push	eax
	mov	eax, edx
	call	class_get_by_name
	mov	edx, eax
	pop	eax
	jc	92f
	push	edx
	call	class_print_classname
	jmp	2f

1:	push	ebx
	mov	eax, [ebx + oofs_lookup_table]
	call	[eax + oofs_table_api_lookup]	# in: edx=class; out: ecx=index
	pop	ebx
	jc	93f

# load: edx = class, ecx = index
2:	mov	eax, [ebx + oofs_root]
	call	[eax + oofs_vol_api_load_entry]
	jc	94f
	mov	eax, [ebx + oofs_root]
	call	[eax + oofs_api_print]
	jmp	66b

91:	printlnc 4, "instance already loaded"
	jmp	66b
92:	printlnc 4, "class not found"
	jmp	66b
93:	printlnc 4, "class not in table"
	jmp	66b
94:	printlnc 4, "error loading entry"
	jmp	66b




# in: ebx = class_oofs instance
# in: edx = subclass of oofs or 0
# in: ecx = entry index (if edx==0)
oofs_show$:
	mov	eax, [ebx + oofs_root]
DEBUG_DWORD edx
DEBUG_DWORD ecx
	or	edx, edx
	jz	2f

	push	ebx
	xor	ebx, ebx	# counter / index
	call	[eax + oofs_vol_api_lookup]
	pop	ebx
	jc	91f

1:	call	[eax + oofs_api_print]
	jmp	66b

2:	push	ebx
	mov	ebx, ecx	# index
	call	[eax + oofs_vol_api_get_obj]
	pop	ebx
	jnc	1b

91:	printlnc 4, "instance not found"
	jmp	66b

oofs_resize$:
	printlnc 4, "resize not implemented"
	jmp	66b
.endif
