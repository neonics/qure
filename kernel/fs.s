###############################################################################
## FileSystem: mtab / mount, fs
##
.intel_syntax noprefix
.code32

FS_DEBUG = 0

MAX_PATH_LEN = 1024
##############################################################################
## mtab
##
## the mtab structure array / class keeps a record of mounted partitions
## and their filesystem type, for supported filesystems.
##
## 
	# At current partition info contains a pointer to the partition
	# table in the volume boot record.
	# TODO: this uses the same buffer as the master boot record
	# so is not constant.
	#
	# Solution 1: have more buffers per disk
	# Solution 2: make it a pointer to a struct/function parameterized
	#  by mtab_disk and mtab_partition.
	#
	# The OO view is that partition_info becomes the pointer to a class
	# instance, which contains the fields mtab_disk and mtab_partition.
	# The object then consists of a pointer to a class description,
	# the simplest of which is an array of methods,
	# aswell as a pointer to its instance data, the shared implicit
	# parameters for all the methods.
	# 
	# Now, the calling code here has a predefined api for filesystem
	# implementations. Thus, the methods to be called are already
	# hardcoded/known. This is similar to an OO interface.
	#
	# The functions can be proxies to the real filesystem handlers.
	# The functions then merge the knowledge of the mtab struct
	# to yield the address of a function to call.
	# 
	# The simplest implementation is hardcoded: update the API functions
	# to add a check for the newly supported filesystem. This check
	# is as simple as a byte compare.
	#
	# The second iteration will have the filesystem types indexed
	# by a static array of method pointers.
	# Each array entry can be a struct, a fixed size array,
	# and thus represents instances of the filesystem class.
	# Another way to say this is that these structs all implement
	# the same class interface. Or, that they are sub-classes from the
	# filesystem class, which is abstractly defined by the code calling
	# the proxy functions.
	#
	# These proxy functions will provide the calculation for the index
	# to the proper filesystem struct, aswell as an offset within
	# the struct (the method pointer array) to indicate the proper method.
	#
	# The proxy functions then provide the base class implementation.
	#
	# The filesystem implementations then do not override these functions,
	# but can be seen to do so, thereby 'hiding' the object.method()
	# calling mechanism.
	#
	# The mtab code itself already implements basic object/method
	# calling by using its mtab struct array as instance data
	# for all the objects - the mountpoints.
	#
	# It's constructor yields two pointers: an absolute and a relative one.
	# The absolute pointer is the start address of a block of memory
	# containing structs, and the relative one is the pointer to the
	# struct. The array is such that not all objects have to have the
	# same size, and thus, the array is not required to store only
	# the same type of 'objects'.
	#
	# All future operations on the 'instance', which is the relative
	# pointer, require the absolute pointer to be given.
	# This pointer is only updated when the entire block of memory
	# needs to be resized and this causing a relocation of the block.
	#
	# After each object construction/destruction (allocation/free)
	# the absolute pointer has to be assumed to have been updated.
	# All succeeding calls referring to the semantically identical array
	# need to use the latest 'version' of the pointer.
	#
	# This allows for garbage collection, whether during a call,
	# or outside of one. 
	#

.if DEFINE
.global fs_obj_p_size_sectors
.global fs_obj_api_read
.global fs_obj_api_write

.global mtab
.global mtab_fs_instance
.global mtab_mountpoint
.global mtab_get_fs
.text32


mount_init$:
	call	mtab_init
	call	fs_init
	ret
.endif
############################################################################
##
# The mtab maintains a compact array. Any references to its indices
# are not guaranteed to work after mtab_entry_free.
.struct 0
mtab_mountpoint:	.long 0	# string pointer
mtab_flags:		.byte 0
	MTAB_FLAG_PARTITION =  1
mtab_fs:		.byte 0	# filesystem type (at current: standard)
mtab_disk:		.byte 0	# disk number
mtab_partition:		.byte 0	# partition number
mtab_partition_start:	.long 0	# LBA start
mtab_partition_size:	.long 0	# sectors
mtab_fs_instance:	.long 0 # file-system specific data structure
MTAB_ENTRY_SIZE = .
.data
.if DEFINE
MTAB_INITIAL_ENTRIES = 1
mtab: .long 0
.text32

# mtab global static initializer. Call once from kernel.
#
# out: ebx = mtab address
mtab_init:
	mov	ebx, [mtab]
	or	ebx, ebx
	jz	0f
	ret

0:
	push_	eax edx
	call	mtab_entry_alloc$	# out: ebx + edx
	jc	91f
###	# add root entry
	mov	eax, 2
	call	mallocz
	jc	92f
	mov	[eax], word ptr '/'
	mov	[ebx + edx + mtab_mountpoint], eax
	mov	eax, offset class_fs_root
	call	class_newinstance
	jc	93f
	mov	[ebx + edx + mtab_fs_instance], eax#dword ptr offset fs_root_instance
1:	pop_	edx eax
	ret
91:	printlnc 4, "mtab_entry_alloc fail"
	stc
	jmp	1b
92:	printlnc 4, "mallocz fail"
	stc
	jmp	1b
93:	printlnc 4, "class_newinstance(fs_root) fail"
	stc
	jmp	1b

# out: ebx = mtab base ptr (might have changed)
# out: edx = index guaranteed to hold one mtab entry
# side-effect: index increased to point to next.
# side-effect: [mtab] updated on resize
mtab_entry_alloc$:
	push	ecx
	push	eax

	ARRAY_NEWENTRY [mtab], MTAB_ENTRY_SIZE, 1, 2f
	mov	ebx, eax

1:	pop	eax
	pop	ecx
	ret
2:	printlnc 12, "mtab: memory error"
	stc
	jmp	1b


# in: ebx = base ptr
# in: edx = entry to release
mtab_entry_free$:
	ASSERT_ARRAY_IDX edx, ebx, MTAB_ENTRY_SIZE
	push	ecx
	# destructor: free the string pointer
	push	eax
	mov	eax, [ebx + edx]
	call	mfree
	pop	eax
	jc	1f
	# delete the entry from the list
	mov	ecx, MTAB_ENTRY_SIZE
	call	array_remove
	jc	1f
0:	pop	ecx
	ret
1:	printlnc 4, "mtab: memory error"
	stc
	jmp	0b

# in: esi = mount point
# out: edx = object	(for easy OO access where eax is 'this')
mtab_get_fs:
	push_	ebx ecx edi esi
	call	strlen_	# just in case
	push	ecx
	ARRAY_LOOP [mtab], MTAB_ENTRY_SIZE, ebx, edx, 9f
	mov	edi, [ebx + edx + mtab_mountpoint]
	mov	esi, [esp + 4]
	mov	ecx, [esp]
	repz	cmpsb
	jz	1f
	ARRAY_ENDL
	stc
	jmp	0f
1:	mov	edx, [ebx + edx + mtab_fs_instance]
	call	class_ref_inc
	clc
0:	pop_	ecx esi edi ecx ebx	# yes, ecx
	ret


cmd_mount$:
	# check cmd arguments
	lodsd
	lodsd
	or	eax, eax
	jz	mtab_print$

	# if second argument missing, print usage
	cmp	dword ptr [esi], 0
	jz	5f

	# if more than 2 arguments, print usage
	cmp	dword ptr [esi + 4], 0
	jnz	5f

	printc	11, "mount "

	# parse first argument
	call	disk_parse_label
	jc	6f

	# alternative for disk_print_label
	printc 14, "disk "
	movzx	edx, al
	call	printdec32
	cmp	ah, -1
	jz	1f
	printc 14, " partition "
	movzx	edx, ah
	call	printdec32
1:	call	printspace

	# load the partition table for the disk
	push	esi
	call	disk_get_partition	# esi = pointer to partition info
	mov	ecx, esi	# ecx (heads) no longer needed
	pop	esi
	jc	4f
	# ax = disk, ecx = partition info pointer, esi = mountpoint
	# mount the filesystem
	push_	eax ecx edx esi
	mov	esi, ecx
	call	fs_load$	# out: edi = fs info structure
	pop_	esi edx ecx eax
	jc	4f
	# double check: edi
	cmp	edi, -1
	jz	4f
	or	edi, edi
	jz	4f

	# create a new mtab entry

	call	mtab_entry_alloc$	# out: ebx + edx
	jc	7f

	mov	[ebx + edx + mtab_flags], word ptr MTAB_FLAG_PARTITION
	mov	[ebx + edx + mtab_disk], ax
	mov	[ebx + edx + mtab_fs_instance], edi

	# XXX FIXME
	# load partition again - the buffer is overwritten?
	push	esi
	call	disk_get_partition
	mov	ecx, esi
	pop	esi
	jnc	1f
	printc 4, "get_partition error"
	# TODO: free mtab_entry
	# TODO: free fs instance
	jmp	4f
1:

	push	eax
	mov	eax, [ecx + PT_LBA_START]
	mov	[ebx + edx + mtab_partition_start], eax
	mov	eax, [ecx + PT_SECTORS]
	mov	[ebx + edx + mtab_partition_size], eax
	mov	al, [ecx + PT_TYPE]
	mov	[ebx + edx + mtab_fs], al
	pop	eax


	push	eax
	mov	eax, [esi]
	call	strdup
	mov	[ebx + edx + mtab_mountpoint], eax
	pop	eax

	# print type and size
	push	edx
	push	eax
	lea	eax, [ebx + edx]

	printc	14, "type "
	mov	dl, [eax + mtab_fs]
	call	printhex2
	call	printspace
	pushcolor 9
	mov	esi, [eax + mtab_fs_instance]
	mov	esi, [esi + obj_class]
	mov	esi, [esi + class_name]
	call	print
	popcolor
	call	printspace

	mov	eax, [eax + mtab_partition_size]
	xor	edx, edx
	call	ata_print_size

	pop	eax
	pop	edx


	.if FS_DEBUG 
		call	newline
		push	edx
		printc 8, "LBA start: "
		mov	edx, [ecx + PT_LBA_START]
		call	printhex8
		printc 8, " sectors: "
		mov	edx, [ecx + PT_SECTORS]
		call	printhex8
		printc 8, " LBA end: "
		add	edx, [ecx + PT_LBA_START]
		dec	edx
		call	printhex8
		printc 8, " Type: "
		mov	dl, [ecx + PT_TYPE]
		call	printhex2
		pop	edx
	.endif

	call	newline
	ret

7:	printlnc 12, "memory error"
	stc
	ret

4:	printlnc 12, "invalid disk/partition"
	stc
6:	ret

5:	pushcolor 12
	println  "usage: mount [<partition> <mountpoint>]"
	println  "  partition:  hda1, hdb4, .... "
	println  "  mountpoint: /path"
	popcolor
	ret

# in: ax = disk/partition
# in: esi = partition info
# out: edi = fs info pointer
fs_load$:
	push_	ebx edx
	xor	bl, bl	# 1 indicates successful mount
	mov	edx, offset _fs_load_iter$
	add	edx, [realsegflat]
	push	edx
	xor	edi, edi
	call	class_iterate_classes
	jnc	0f

	printlnc 4, "unsupported filesystem"
	stc

0:	pop_	edx ebx
	ret

# in: [esp]: classdef ptr
# out: CF = 1: abort iteration
# out: bl = 1 = success (if CF==1)
_fs_load_iter$:
	push	ebp
	lea	ebp, [esp + 8]

	push_	eax edx
	mov	edx, offset class_fs
	mov	eax, [ebp]
	cmp	edx, eax
	jz	9f	# class_fs is abstract, skip
	call	class_extends
	pop_	edx eax
	stc
	jnz	1f

	push	dword ptr [ebp]	# class def ptr
	push	dword ptr offset fs_api_mount
	call	class_invoke_static	# out: CF = 0: mount ok
	# CF = 0: mount ok, stop iteration
1:	pop	ebp
	ret

9:	pop_	edx eax
	stc
	jmp	1b


mtab_print$:
	push_	eax ebx ecx edx
	xor	edx, edx
	pushcolor 7
	ARRAY_LOOP [mtab], MTAB_ENTRY_SIZE, ebx, ecx, 0f
	color 15
	test	byte ptr [ebx + ecx + mtab_flags], MTAB_FLAG_PARTITION
	jz	1f
	mov	ax, [ebx + ecx + mtab_disk]
	call	disk_print_label
	jmp	2f
1:	print_	"none"
2:	printc_	8, " on "
	mov	esi, [ebx + ecx + mtab_mountpoint]
	call	print
	test	byte ptr [ebx + ecx + mtab_flags], MTAB_FLAG_PARTITION
	jz	1f
	printc_	8, " fs "
	mov	dl, [ebx + ecx + mtab_fs]
	call	printhex2
	call	printspace
	color 14
	mov	esi, [ebx + ecx + mtab_fs_instance]
	mov	esi, [esi + obj_class]
	mov	esi, [esi + class_name]
	call	print
	color 7
	printc_	8, " (disk "
	mov	dl, byte ptr [ebx + ecx + mtab_disk]
	call	printdec32
	mov	dl, byte ptr [ebx + ecx + mtab_partition]
	cmp	dl, -1
	jz	2f
	printc_	8, " partition "
	call	printdec32
2:	call	printspace
	mov	eax, [ebx + ecx + mtab_partition_size]
	xor	edx, edx
	color	7
	call	ata_print_size
	printc_	8, ")"
1:	call	newline
	ARRAY_ENDL
0:	popcolor
	pop_	edx ecx ebx eax
	ret

# in: esi = path string
# in: ecx = path string length
# out: ebx = [mtab]
# out: ecx = offset relative to ebx
mtab_find_mountpoint:
	push	edi
	push	eax
	push	edx

#	call	strlen_	# in: esi; out: ecx

	mov	ebx, [mtab]
	xor	eax, eax
	mov	edx, -1

0:	cmp	eax, [ebx + buf_index]
	jae	1f
	mov	edi, [ebx + eax + mtab_mountpoint]
	push	ecx
	push	esi
	rep	cmpsb
	pop	esi
	pop	ecx
	jnz	2f
	cmp	byte ptr [edi], 0
	jnz	2f
	mov	edx, eax	# remember match
2:	add	eax, MTAB_ENTRY_SIZE
	jmp	0b

1:	mov	ecx, edx

	inc	edx	# if edx was -1 then carry is set
	jnz	1f
	stc
1:
	pop	edx
	pop	eax
	pop	edi
	ret


cmd_umount$:
	printlnc 4, "umount: not implemented"
	ret

#############################################################################
# The FS_API - fs info structure/class: method pointers
#
###################################################
# for all calls:
# eax = pointer to fs info (as stored in mtab_fs_instance)
# in: ebx = fs-specific handle from previous call or -1 for root directory
###################################################
.struct 0
###################################################
DECLARE_CLASS_BEGIN fs
fs_obj_disk:		.byte 0
fs_obj_partition:	.byte 0
fs_obj_sector_size:	.long 0 # 512 for ATA, 2048 for ATAPI generally
fs_obj_p_start_lba:	.long 0, 0
fs_obj_p_size_sectors:	.long 0, 0
fs_obj_p_end_lba:	.long 0, 0
fs_obj_label:		.long 0	# short filesystem name

# protected methods:
DECLARE_CLASS_METHOD fs_obj_api_read,	fs_obj_read
DECLARE_CLASS_METHOD fs_obj_api_write,	fs_obj_write

# in: ax: al = disk ah = partition
# in: esi = partition table pointer
# out: eax: class instance (object)
DECLARE_CLASS_METHOD fs_api_mkfs, 0, STATIC
DECLARE_CLASS_METHOD fs_api_mount, 0, STATIC
DECLARE_CLASS_METHOD fs_api_umount, 0 		# destructor
# in: eax = fs_instance
# in: ebx = parent/current directory handle (-1 for root)
# in: esi = asciz file/dirname pointer
# in: edi = fs dir entry struct
# out: ebx = fs specific handle
DECLARE_CLASS_METHOD fs_api_open, 0
DECLARE_CLASS_METHOD fs_api_close, 0
DECLARE_CLASS_METHOD fs_api_nextentry, 0
DECLARE_CLASS_METHOD fs_api_read, 0	# ebx=filehandle, edi=buf, ecx=size
DECLARE_CLASS_METHOD fs_api_create, 0
DECLARE_CLASS_METHOD fs_api_write, 0
DECLARE_CLASS_METHOD fs_api_delete, 0
DECLARE_CLASS_METHOD fs_api_move, 0

DECLARE_CLASS_END fs
###################################################
.text32
# protected methods:
FS_OBJ_DEBUG_RW=0	# 0=none; 1=print; 2=enter before disk access
# in: eax = fs_obj/class_fs instance
# in: ecx = size
# in: ebx = sectors
# out: ecx = error msg on CF
fs_obj_rw_init$:
	add	ecx, 511
	shr	ecx, 9
	LOAD_TXT "data size 0", edx
	jz	9f
	cmp	ebx, [eax + fs_obj_p_size_sectors]
	LOAD_TXT "sector outside partition", edx
	jae	9f
	add	ebx, [eax + fs_obj_p_start_lba]
	mov	ax, [eax + fs_obj_disk]
	ret
9:	stc
	ret

# in: eax = instance
# in: ebx = partition-relative LBA
# in: edi = buffer
# in: ecx = bytes
#[in: edx = class being saved]
fs_obj_read:
	push_	eax ebx ecx edx
	.if FS_OBJ_DEBUG_RW
		call newline
		DEBUG_CLASS
		DEBUG "fs_obj_read", 0x4f
		DEBUGS [edx+class_name]
		DEBUG_DWORD ecx
		DEBUG_DWORD ebx
	.endif
	call	fs_obj_rw_init$
	.if FS_OBJ_DEBUG_RW
		DEBUG_DWORD ebx
		call newline
	.endif
	.if FS_OBJ_DEBUG_RW > 1
		call more
	.endif
	call	disk_read
	LOAD_TXT "disk_read error", edx
	jc	9f
0:	pop_	edx ecx ebx eax
	ret
9:	printc 4, "fs_obj_read: "
	push	edx
	call	_s_println
	stc
	jmp	0b


# in: eax = sfs instance
# in: ebx = partition-relative LBA
# in: esi = buffer
# in: ecx = bytes	# writes at least 1 sector
#[in: edx = class being saved]
fs_obj_write:
	push_	edx ecx ebx eax
	.if FS_OBJ_DEBUG_RW
		call newline
		DEBUG_CLASS
		DEBUG "fs_obj_write", 0x4f
		DEBUGS [edx+class_name]
		DEBUG_DWORD ecx
		DEBUG_DWORD ebx
	.endif
	call	fs_obj_rw_init$
	jc	9f
	.if FS_OBJ_DEBUG_RW
		DEBUG_DWORD ebx
		call newline
	.endif
	.if FS_OBJ_DEBUG_RW > 1
		call more
	.endif
	call	disk_write
	LOAD_TXT "disk_write error", edx
	jc	9f
0:	pop_	eax ebx ecx edx
	ret
9:	printc 4, "fs_obj_write: "
	push	edx
	call	_s_println
	stc
	jmp	0b

################################################

fs_init:
.if 0 # disabled for now - statically defined
	mov	eax, offset class_fs_root
	call	class_register

	mov	eax, offset class_fs_fat16
	call	class_register

	mov	eax, offset class_fs_iso9660
	call	class_register

	mov	eax, offset class_fs_sfs
	call	class_register
.endif
	ret

fs_list_filesystems:
	mov	edx, offset _fs_iter_m$
	add	edx, [realsegflat]
	push	edx
	call	class_iterate_classes
	ret

# in: eax = class def ptr
# out: CF = 1: stop iteration
_fs_iter_m$:
	mov	eax, [esp + 4]
	mov	edx, offset class_fs
	cmp	eax, edx
	jz	1f		# skip fs class itself
	call	class_extends	# eax extends ... edx
	jnz	1f

	printc	11, "fs: "
	mov	edx, eax
	call	printhex8
	call	printspace
	pushcolor 14
	mov	esi, [eax + class_name]
	call	println
	popcolor
1:	stc	# keep iterating
	ret

KAPI_DECLARE fs_mount
fs_mount:
	call	cmd_mount$
	ret

fs_unmount:
	ret

cmd_mkfs:
	lodsd
	lodsd
	or	eax, eax
	jz	9f

	mov	edx, offset class_fs_oofs #default

	cmp	byte ptr [eax], '-'
	jnz	1f
	CMD_ISARG "-t"
	jnz	9f
	lodsd
	call	fs_get_by_name$
	jc	91f

	lodsd
	or	eax, eax
	jz	9f

1:	call	disk_parse_partition_label
	jc	9f

	push	eax
	lodsd
	or	eax, eax
	pop	eax
	jnz	92f

	printc 11, "formatting "
	call	disk_print_label
	printc 11, " type "
	mov	esi, [edx + class_name]
	call	print

	push	edx				# class def ptr
	push	dword ptr offset fs_api_mkfs	# static method ptr
	call	class_invoke_static	# out: CF = 0: mount ok
	ret

91:	printlnc 4, "unknown file system type. Available: "
	call	fs_list_filesystems
	ret
92:	printlnc 4, "trailing arguments."
9:	printlnc 4, "usage: mkfs [-t <fstype>] <hdXY>"
	ret


fs_get_by_name$:
	push_	eax esi edi ecx ebp
	mov	ebp, esp

	mov	esi, eax
	call	strlen_
	add	ecx, 4
	sub	esp, ecx

	mov	edi, esp
	LOAD_TXT "fs_", esi, ecx
	rep	movsb
	dec	edi
	mov	esi, eax
	call	strcopy

	mov	eax, esp
	DEBUGS eax
	call	class_get_by_name
	mov	edx, eax

	mov	esp, ebp
	pop_	ebp ecx edi esi eax
	ret

#############################################################################
DECLARE_CLASS_BEGIN fs_root, fs
DECLARE_CLASS_METHOD fs_api_mount, fs_root_mount$, OVERRIDE
DECLARE_CLASS_METHOD fs_api_umount, fs_root_umount$, OVERRIDE
DECLARE_CLASS_METHOD fs_api_open, fs_root_open$, OVERRIDE
DECLARE_CLASS_METHOD fs_api_close, fs_root_close$, OVERRIDE
DECLARE_CLASS_METHOD fs_api_nextentry, fs_root_nextentry$, OVERRIDE
DECLARE_CLASS_METHOD fs_api_read, fs_root_read$, OVERRIDE
DECLARE_CLASS_END fs_root

fs_root_instance:
.long class_fs_root	# leave for now.. no object data.

.text32
fs_root_mount$:
	stc
	ret
fs_root_umount$:
	printlnc 4, "fs_root_umount: not implemented"
	stc
	ret

ROOT_DEV_PATH = ('d')|('e'<<8)|('v'<<16)

# in: eax = offset fs_root_instance
# in: esi = directory
# in: edi = fs dirent
# out: ebx = file/dir handle
fs_root_open$:
	mov	byte ptr [edi + fs_dirent_attr], 0x10
	cmp	word ptr [esi], '/'
	jz	0f
	cmp	[esi], dword ptr ROOT_DEV_PATH
	jz	1f

9:
	.if FS_DEBUG > 1
		printc 4, "fs_root_open "
		call	print
		printlnc 4, ": not found"
	.endif
	stc
	ret

1:	mov	ebx, -2 # indicates /dev
	mov	[edi + fs_dirent_name + 0], byte ptr '/'
	mov	[edi + fs_dirent_name + 1], dword ptr ROOT_DEV_PATH
	clc
	ret

0:	mov	ebx, -1	# indicates root
	mov	word ptr [edi + fs_dirent_name], '/'
	clc
	ret

# in: eax = fs info
fs_root_close$:
	clc
	ret

# Generate a root directory listing on the fly. First entry is /dev,
# the rest is all mountpoints that are direct descendents of /.
# in: eax = fs info
# in: ebx = dir handle
# in: ecx = cur entry
# in: edi = fs dir entry struct
# out: ecx = next entry (-1 for none)
# out: edx = directory name
fs_root_nextentry$:
	cmp	ebx, -1	# /
	jz	1f

	cmp	ebx, -2	# /dev
	jnz	9f

########
	mov	byte ptr [edi + fs_dirent_attr], 0x04 # system
	mov	esi, [class_instances]
	or	esi, esi
	jz	9f

	mov	edx, offset class_dev
0:
	cmp	ecx, [esi + array_index]
	jae	9f
	# skip objects until a dev is found
	mov	eax, [esi + ecx]
	DEBUG_DWORD eax
	call	class_instanceof
	jz	2f
	mov eax, [eax + obj_class]
	push dword ptr [eax + class_name]; call _s_print
	add	ecx, 4
	jmp	0b
2:
	lea	esi, [eax + dev_name]
	push	edi
	push	ecx
	call	strlen_
	inc	ecx
	lea	edi, [edi + fs_dirent_name]
	rep	movsb
	pop	ecx
	pop	edi

	add	ecx, 4 #[eax + ecx + obj_size]
	clc
	ret

########
1:	mov	byte ptr [edi + fs_dirent_attr], 0x10
	or	ecx, ecx
	jnz	1f
	mov	[edi + fs_dirent_name + 0], byte ptr '/'
	mov	[edi + fs_dirent_name + 1], dword ptr ROOT_DEV_PATH
	inc	ecx
	ret

1:	mov	eax, [mtab]
	or	eax, eax
	jz	9f
0:	dec	ecx
	cmp	ecx, [eax + array_index]
	jae	9f
	# check if dir is mounted in root:
	push	ecx
	push	esi
##
	mov	esi, [eax + ecx + mtab_mountpoint]
	call	strlen_
	cmp	ecx, 1
	jz	1f
	push	ecx
	push	edi
	mov	edi, esi
	mov	al, '/'
	inc	edi	# assume all mountpoints are absolute
	repnz	scasb
	pop	edi
	pop	ecx
	jz	1f

	push	edi
	add	edi, offset fs_dirent_name
	inc	ecx
	rep	movsb
	pop	edi
	or	esi, esi	# clear ZF
1:	pop	esi
	pop	ecx
	pushf
	add	ecx, MTAB_ENTRY_SIZE + 1
	popf
	jz	0b
	clc
	ret

9:	mov	ecx, -1
	stc
	ret

fs_root_read$:
	printlnc 4, "fs_root_read: not implemented"
	stc
	ret

############################################################################
# FS Handles
#
# These are API structures for maintaining state between caller and fs api.


# Directory Entry
.struct 0
FS_DIRENT_MAX_NAME_LEN = 255
fs_dirent_name: .space FS_DIRENT_MAX_NAME_LEN
fs_dirent_attr:	.byte 0		# RHSVDA78
  FS_DIRENT_ATTR_DIR = 1 << 4
fs_dirent_size:	.long 0, 0
fs_dirent_posix_perm:	.long 0
fs_dirent_posix_uid:	.long 0
fs_dirent_posix_gid:	.long 0
fs_dirent_posix_ctime:	.long 0,0	# use short 7 byte fmt - reserve 8
fs_dirent_posix_mtime:	.long 0,0
fs_dirent_posix_atime:	.long 0,0
# some other times - ignored.
FS_DIRENT_STRUCT_SIZE = .

.global fs_dirent_posix_mtime

.text32


.struct 0			# index bits available:
fs_handle_parent:	.long 0 # total 2
fs_handle_label:	.long 0	# total 3
fs_handle_mtab_idx:	.long 0 # total 2
fs_handle_dir:		.long 0 # total 4
fs_handle_dir_iter:	.long 0 # total 2
fs_handle_dir_size:	.long 0 # total 3?
fs_handle_buf:		.long 0 # total 4?
fs_handle_dirent:	.space FS_DIRENT_STRUCT_SIZE
FS_HANDLE_STRUCT_SIZE = .

.global fs_handle_dirent

# Since the structure is several doublewords long, a number of bits in the
# offset becomes available. These can be used as flags. Otherwise,
# the index/handle might be shifted this number of bits to provide a contiguous
# numbering scheme with a distance of 1.
#
# 3 bits:
# - directory or file
# - softlink

.data SECTION_DATA_BSS
.align 4
# open files
fs_handles$:	.long 0
fs_handles_sem:	.long 0
.text32

# precondition: handle write locked
# out: eax + edx = fs_handle base + index
fs_new_handle$:
	push	ecx
	mov	eax, [fs_handles$]
	xor	edx, edx
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	or	eax, eax
	jnz	1f
	call	array_new
	jc	9f
	mov	[fs_handles$], eax
0:	cmp	[eax + edx + fs_handle_label], dword ptr -1
	jz	9f
	add	edx, ecx
1:	cmp	edx, [eax + array_index]
	jb	0b
	call	array_newentry
	mov	[fs_handles$], eax
9:	pop	ecx
	ret

#	mov	ecx, FS_HANDLE_STRUCT_SIZE
#	mov	eax, [fs_handles$]
#	or	eax, eax
#	jnz	1f
#	inc	eax
#	call	array_new
#
#1:	
#	call	array_newentry
#	mov	[fs_handles$], eax
#	pop	ecx
#	ret

FS_HANDLE_PRINTINFO_COMPACT = 1

# in: eax = handle offset
fs_handle_printinfo:
	LOCK_READ [fs_handles_sem]
	ASSERT_ARRAY_IDX eax, [fs_handles$], FS_HANDLE_STRUCT_SIZE
	push	esi
	push	edx
	push	ebx
	push	eax

.if !FS_HANDLE_PRINTINFO_COMPACT
	printc	11, "Handle "
.endif
	mov	edx, eax
	call	printhex8
	mov	ebx, [fs_handles$]

.if FS_HANDLE_PRINTINFO_COMPACT
	call	printspace
	mov	edx, [eax + ebx + fs_handle_parent]
	call	printhex8
	call	printspace
.else
	printc 	13, " mtab "
.endif
	mov	edx, [eax + ebx + fs_handle_mtab_idx]
	call	printhex8

.if FS_HANDLE_PRINTINFO_COMPACT
	call	printspace
.else
	printc 	13, " dir "
.endif
	mov	edx, [eax + ebx + fs_handle_dir]
	call	printhex8

.if 1
.if FS_HANDLE_PRINTINFO_COMPACT
	call	printspace
.else
	printc	10, " attr: "
.endif
	mov	dl, [eax + ebx + fs_handle_dirent + fs_dirent_attr]
	call	printhex2
	print_ "   "
.endif

	mov	esi, [eax + ebx + fs_handle_label]
	cmp	esi, -1
	jz	1f
.if FS_HANDLE_PRINTINFO_COMPACT
	call	printspace
.else
	printc	10, " name: '"
.endif
	call	print
	printcharc 10, '\''
	jmp	2f
1:	printc 11, " Available"
2:

.if 1
	test	al, 2
	jnz	1f
.if FS_HANDLE_PRINTINFO_COMPACT
	call	printspace
.else
	printc 6, " entries: "
.endif
	mov	edx, [eax + ebx + fs_handle_dir_iter]
	call	printdec32
	printcharc 6, '/'
	mov	edx, [eax + ebx + fs_handle_dir_size]
	call	printdec32
1: 
.endif
	pop	eax
	pop	ebx
	pop	edx
	pop	esi
	UNLOCK_READ [fs_handles_sem]
	ret


# out: ZF = 1: file, 0: directory (jz dir$ ;  jnz file$)
fs_handle_isdir:
	ASSERT_ARRAY_IDX eax, [fs_handles$], FS_HANDLE_STRUCT_SIZE
	test	eax, 1
	ret

# in: eax = handle index
# out: esi
fs_handle_getname:
	LOCK_READ [fs_handles_sem]
	ASSERT_ARRAY_IDX eax, [fs_handles$], FS_HANDLE_STRUCT_SIZE
	mov	esi, [fs_handles$]
	mov	esi, [eax + esi + fs_handle_label]
	UNLOCK_READ [fs_handles_sem]
	ret

# in: eax = handle index
# out: esi
.global fs_handle_get_mtime
fs_handle_get_mtime:
	LOCK_READ [fs_handles_sem]
	ASSERT_ARRAY_IDX eax, [fs_handles$], FS_HANDLE_STRUCT_SIZE
	mov	esi, [fs_handles$]
	lea	esi, [eax + esi + fs_handle_dirent + fs_dirent_posix_mtime]
	UNLOCK_READ [fs_handles_sem]
	ret

	.macro FS_HANDLE_CALL_API api, reg
		# proxy through mtab to fs_instance
		mov	eax, [eax + edx + fs_handle_mtab_idx]
		add	eax, [mtab]
		mov	eax, [eax + mtab_fs_instance]
		# locate the method
#		mov	\reg, [eax + obj_class]
#		call	[\reg + fs_api_\api]
		call	[eax + fs_api_\api]

#		#mov	\reg, [\reg + fs_api_\api]
#		#clc
#		#jecxz	99f	# root
##		add	\reg, [realsegflat]
#		#call	\reg	# in: eax, ebx
	99:	
	.endm
# in: eax = handle index
# out: edx = fs_dirent or something..
# out: esi = fs_dirent
# out: CF = error
# out: ZF = no next entry
KAPI_DECLARE fs_nextentry
fs_nextentry:
	LOCK_READ [fs_handles_sem]
	push	eax
	call	fs_validate_handle$	# in: eax; out: eax + edx
	jc	9f
	lea	esi, [eax + edx + fs_handle_dirent]
	push	esi
	push	ecx
	push	ebx
	# in: eax = fs info
	# in: ebx = dir handle
	# in: ecx = cur entry
	# in: edi = fs_dir entry struct
	mov	edi, esi
	mov	ecx, [eax + edx + fs_handle_dir_iter]
	mov	ebx, [eax + edx + fs_handle_dir]
	UNLOCK_READ [fs_handles_sem]

	push	edx
	FS_HANDLE_CALL_API nextentry, edx	# out: edx=dir name, ecx=next
	mov	esi, edx
	pop	edx

	LOCK_READ [fs_handles_sem]
	mov	eax, [fs_handles$]
	mov	[eax + edx + fs_handle_dir_iter], ecx
	pop	ebx
	pop	ecx
	mov	edx, esi
	pop	esi

0:	pop	eax
	UNLOCK_READ [fs_handles_sem]
	ret

9:	printc 4, "fs_nextentry: unknown handle: "
	call	printhex8
	stc
	jmp	0b

# in: eax = handle
# out: esi = buffer
# out: ecx = buffer size
KAPI_DECLARE fs_handle_read
fs_handle_read:
	LOCK_READ [fs_handles_sem]
	push	eax
	push	ebx
	push	edi
	push	edx
	call	fs_validate_handle$
	jc	9f

	mov	edi, [eax + edx + fs_handle_buf]
	or	edi, edi
	jnz	1f	# assume buffer is large enough
	push	eax
	mov	eax, [eax + edx + fs_handle_dirent +  fs_dirent_size]
#	add	eax, 511
#	and	eax, 0xfffffe00
	add	eax, 2048	# ATAPI bufsize, just in case
	and	eax, ~2047
	call	malloc
	mov	edi, eax
	pop	eax
	jc	0f

	mov	[eax + edx + fs_handle_buf], edi
1:
	mov	ecx, [eax + edx + fs_handle_dirent +  fs_dirent_size]
	mov	ebx, [eax + edx + fs_handle_dir]
	push	ecx
	push	edi
	FS_HANDLE_CALL_API read, edx	# in: ebx=handle, edi,ecx = buf
	pop	esi
	pop	ecx

0:	pop	edx
	pop	edi
	pop	ebx
	pop	eax
	UNLOCK_READ [fs_handles_sem]
	ret
9:	printc 4, "fs_handle_read: unknown handle"
	stc
	jmp	0b

# in: eax = handle
# in: edi = buffer	# minimal 2kb
# in: ecx = bytes to read
KAPI_DECLARE fs_read
fs_read:
	LOCK_READ [fs_handles_sem]
	push_	eax ebx ecx edx edi
	call	fs_validate_handle$
	jc	9f

	cmp	ecx, [eax + edx + fs_handle_dirent + fs_dirent_size]
	jbe	1f
	mov	ecx, [eax + edx + fs_handle_dirent + fs_dirent_size]
1:	mov	ebx, [eax + edx + fs_handle_dir]

	push_ eax edx
	FS_HANDLE_CALL_API read, edx
	pop_ edx eax
	jc	0f
	shr	ecx, 11	# 2kb !! NOTE!! iso9660!
	add	[eax + edx + fs_handle_dir], ecx	# add lba lseek pos

0:	pop_	edi edx ecx ebx eax
	pushf
	UNLOCK_READ [fs_handles_sem]
	popf
	ret
9:	printc 4, "fs_read: invalid handle"
	stc
	jmp	0b


# in: eax = filename ptr 
# in: edx = POSIX flags
# out: eax = hanle
KAPI_DECLARE fs_create
fs_create:
DEBUG "fs_create"
	push_	esi edi ecx ebx edx

	mov	esi, eax
	cmp	byte ptr [esi], '/'
	jnz	91f

	# open the file to see if it exists.
	xor	edx, edx
	call	fs_stat
	jnc	92f

	# open parent dir
	call	strlen_

	lea	edi, [esi + ecx]
	mov	al, '/'
	std
	repnz	scasb
	cld
	# ZF=1 since string starts with '/'
	inc	edi
	cmp	edi, esi
	jnz	1f
	DEBUG "create "
	call	print
	DEBUG " in root"

1:	# edi points to last '/'
	xor	bl, bl
	xchg	bl, [edi]	# zero-terminate path & remember

	mov	eax, esi
	.if FS_DEBUG
		DEBUG "open"
		DEBUGS esi
	.endif
	push	ecx
	mov	edx, 0x80000000
	call	fs_open		# in: eax; out: eax, ecx
	pop	ecx
	xchg	bl, [edi]	# restore original string
	jc	93f
	# parent dir opened.

	lea	esi, [edi + 1]	# file/dirname pointer

#######	prepare args, call filesystem api
	LOCK_WRITE [fs_handles_sem]

	mov	ebx, eax	# parent handle
	mov	ecx, [esp]	# posix perms

	# prepare new filehandle
	call	fs_new_handle$	# out: eax + edx
	jc	94f
	mov	[eax + edx + fs_handle_parent], ebx
	push	edx		# new file handle index

	lea	edi, [eax + edx + fs_handle_dirent]

	mov	[edi + fs_dirent_posix_perm], ecx #dword ptr 0100644	# 10=file
	mov	[edi + fs_dirent_posix_uid], dword ptr 0
	mov	[edi + fs_dirent_posix_gid], dword ptr 0

	add	edi, offset fs_dirent_name
	call	strcopy
	sub	edi, offset fs_dirent_name # in: edi = new fs_handle_dirent

	# load mtab fs instance from parent
	mov	ecx, [mtab]
	add	ecx, [eax + ebx + fs_handle_mtab_idx]
	mov	ebx, [eax + ebx + fs_handle_dir]	# in: ebx = directory handle 
	mov	eax, [ecx + mtab_fs_instance]	# in: eax = fs_instance

	call	[eax + fs_api_create]
	pop	eax		# new file handle

	pushf	# just in case.. (inc affects CF?)
	UNLOCK_WRITE [fs_handles_sem]
	popf
	jnc	0f
	call	fs_close	# close new file handle and parents.
	stc
#####
0:	pop_	edx ebx ecx edi esi
	ret
9:	jmp	0b

# need to have 1 '/'
91:	printc 4, "fs_create: error: relative path: "
	call	println
	stc
	jmp	0b
92:	printc 4, "fs_create: path exists: "
	call	println
	stc
	jmp	0b
93:	printc 4, "fs_create: parent path doesn't exist: "
	call	println
	stc
	jmp	0b
94:	printc 4, "fs_create: can't allocate handle"
	UNLOCK_WRITE [fs_handles_sem]
	mov	eax, ebx	# parent handle
	call	fs_close
	stc
	jmp	0b


KAPI_DECLARE fs_write
	ret

KAPI_DECLARE fs_delete
	ret

KAPI_DECLARE fs_move
	ret


# cmd_lsof
fs_list_openfiles:
	LOCK_READ [fs_handles_sem]
	# map { print } @fs_handles;
	mov	ebx, [fs_handles$]
	or	ebx, ebx
	jz	1f
	print "handles: "
	mov	eax, [ebx + array_index]
	xor	edx, edx
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	div	ecx
	mov	edx, eax
	call	printdec32
	call	printspace
	mov	edx, ebx
	call	printhex8
	call	newline
	println "handle.. parent.. mtab.... dir..... attr name.... entries"

	xor	eax, eax
	jmp	2f
0:	push	eax
	push	ebx
	call	fs_handle_printinfo
	pop	ebx
	pop	eax
	call	newline
	add	eax, FS_HANDLE_STRUCT_SIZE
2:	cmp	eax, [ebx + array_index]
	jb	0b

1:	UNLOCK_READ [fs_handles_sem]
	ret


# precondition: fs_handles_sem locked.
# in: eax = handle index
# out: eax = [fs_handles]
# out: edx = handle index
# out: CF
fs_validate_handle$:
	ASSERT_ARRAY_IDX eax, [fs_handles$], FS_HANDLE_STRUCT_SIZE
	mov	edx, eax
	cmp	edx, 0
	jl	1f

	mov	eax, [fs_handles$]
	or	eax, eax
	jz	1f

	cmp	edx, [eax + array_index]
	jae	1f

	cmp	[eax + edx + fs_handle_label], dword ptr -1
	jz	1f

	clc
	ret
1:	stc
	ret


# in: eax = handle index
KAPI_DECLARE fs_close
fs_close:	# fs_free_handle
	push	edx
	push	ebx
	push	ecx

	LOCK_READ [fs_handles_sem]
0:	call	fs_validate_handle$	# out: eax+edx
	jc	9f

	mov	ebx, eax
	mov	eax, [ebx + edx + fs_handle_label]

	.if FS_DEBUG
		push esi
		PRINT_ "fs_close: "
		mov	esi, eax
		PRINTLN_
		pop esi
	.endif

	call	mfree

	mov	eax, [ebx + edx + fs_handle_buf]
	or	eax, eax
	jz	1f
	call	mfree
1:

	mov	eax, ebx
	# mark filesystem handle as free
	mov	[eax + edx + fs_handle_label], dword ptr -1

	mov	ebx, [eax + edx + fs_handle_dir]
	push	edi
	lea	edi, [eax + edx + fs_handle_dirent]
	push_	eax edx
	FS_HANDLE_CALL_API close, ecx
	pop_	edx eax
	pop	edi

	# free parent handles:
	mov	eax, [eax + edx + fs_handle_parent]
	cmp	eax, -1
	jnz	0b

0:	mov	eax, -1
	pop	ecx
	pop	ebx
	pop	edx
	UNLOCK_READ [fs_handles_sem]
	ret

9:	printc	4, "fs_close: unknown handle: "
	call	printhex8
	call	newline
	stc
	jmp	0b


# Traverses the directories indicated by the absolute path, giving precedence
# to mountpoints, delegating directory opening to whatever filesystem.
# 
# It returns a directory handle index which must be freed by fs_free_handle.
# The structure it returns contains a strdupped label, aswell as
# a reference to the mountpoint used - the filesystem type - and a directory
# handle, which only has meaning to the specific filesystem.
# The single return value thus abstracts the use of different filesystems.
# For file/directory operations, the file handle alone would be insufficient
# as the filesystem it refers to is unknown.
#
# 
# in: eax = pointer to path string
# out: eax = directory handle (pointer to struct), to be freed with fs_close.
KAPI_DECLARE fs_openfile
KAPI_DECLARE fs_opendir
fs_openfile:
fs_opendir:
	push	edx
	mov	edx, 0x80000000
	call	fs_open
	pop	edx
	ret

fs_stat_:
	call	SEL_kernelCall:0
# in: eax = path string
# out: ecx = file size
# out: CF = 0: exists; 1: does not exist.
KAPI_DECLARE fs_stat
fs_stat:
	push	edx
	xor	edx, edx
	call	fs_open
	jc	9f
	LOCK_READ [fs_handles_sem]
	mov	edx, [fs_handles$]
	push	dword ptr [edx + eax + fs_handle_dirent + fs_dirent_attr] # byte
	mov	ecx, [eax + edx + fs_handle_dirent +  fs_dirent_size] # return
	UNLOCK_READ [fs_handles_sem]
	call	fs_close
	pop	eax
	and	eax, 0xff
9:	pop	edx
	ret


# in: eax = pointer to path string
# in: edx = flags:
#	0x80000000 = print error
#	0x40000000 = return deepest existing path handle
# out: eax = directory handle (pointer to struct), to be freed with fs_close.
# out: ecx = file size
KAPI_DECLARE fs_open
fs_open:
####################################################################
	push	ebp
	push	ebx
	#push	ecx
	push	edx
	push	esi
	push	edi
	push	dword ptr -1	# space for last handle
	mov	ebp, esp
	push	eax				# [ebp - 4] = full path
	sub	esp, FS_HANDLE_STRUCT_SIZE	# [ebp -4-FS_HANDLE_STRUCT_SIZE]
	mov	edi, esp
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	xor	al, al
	rep	stosb
	mov	edi, esp
	mov	[edi + fs_handle_mtab_idx], dword ptr -1
	mov	[edi + fs_handle_dir], dword ptr -1

	mov	esi, [ebp - 4]
	.if FS_DEBUG > 1
		DEBUG "parse path: "
		call	println
	.endif

###############################################
	# special case. strtok will skip '/'.
	# assume [esi]='/'
	mov	ecx, 1
	call	handle_copy_path$
	push	esi
	call	handle_pathpart$
	pop	esi
	jc	91f
	push	esi
	call	handle_dup$
	pop	esi
###############################################

	xor	ecx, ecx
0:	mov	al, '/'
	call	strtok	# out: esi, ecx
	jc	1f

	push	esi	# preserve for next strtok call
	push	ecx

	# todo: clear stack handle
	call	handle_copy_path$ # copy path so far
	call	handle_pathpart$
	jc	2f
	# allocate handle for each subdir
	call	handle_dup$ # copy from stack
2:

	pop	ecx
	pop	esi
	jnc	0b
	mov	eax, [edi + fs_handle_label]
	call	mfree
	# error: CF=1
	mov	eax, [ebp]
	cmp	eax, -1	# optional if root is always present
	jz	2f
	testd	[ebp + 12], 0x40000000
	jnz	3f		# return deepest dir handle
	call	fs_close
2:	mov	eax, -1	# return value for clarity
3:	stc
	jmp	9f

1:	# end of path found. done.

	.if 0
		# copy the fs_handle on the stack to a new entry
		call	fs_new_handle$	# out: eax + edx
		jc	9f
		lea	edi, [eax + edx]
		lea	esi, [ebp - 4 - FS_HANDLE_STRUCT_SIZE]
		mov	ecx, FS_HANDLE_STRUCT_SIZE
		rep	movsb
		mov	ecx, eax
		mov	eax, [ebp - 4]
		call	strdup	# in: eax; out: eax
		mov	[ecx + edx + fs_handle_label], eax
		mov	eax, edx
	.endif
	mov	eax, [ebp] # get last handle
	mov	ecx, [fs_handles$]
	mov	ecx, [ecx + eax + fs_handle_dirent + fs_dirent_size]

	clc

9:	mov	esp, ebp
	pop	edi	# pop space for last handle
	pop	edi
	pop	esi
	pop	edx
	#pop	ecx
	pop	ebx
	pop	ebp
	ret

91:	# free handle_label
	push	eax
	mov	eax, [ebp - 4 - FS_HANDLE_STRUCT_SIZE + fs_handle_label]
	call	mfree
	pop	eax
	stc
	jmp	9b


handle_copy_path$:
	# copy path so far:
	push	ecx
	push	esi
	push	edi
	add	ecx, esi
	mov	eax, [ebp - 4]
	sub	ecx, eax
	call	strndup	# in: eax, ecx; out: eax
	lea	edi, [ebp - 4 - FS_HANDLE_STRUCT_SIZE + fs_handle_label]
	stosd
	pop	edi
	pop	esi
	pop	ecx
	ret

# private/inner function:
# in: ebp
# out: eax, esi, ecx, [ebp]
handle_dup$:
	LOCK_WRITE [fs_handles_sem]
	call	fs_new_handle$	# out: eax + edx
	jc	9f	# TODO: also dealloc handle_pathparth's ebx
	push	edi
	lea	edi, [eax + edx]
	lea	esi, [ebp - 4 - FS_HANDLE_STRUCT_SIZE]
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	rep	movsb
	mov	ecx, eax
	#mov	eax, [ebp - 4]
	#call	strdup	# in: eax; out: eax
	#mov	[ecx + edx + fs_handle_label], eax
	mov	eax, [ebp]
	mov	[ecx + edx + fs_handle_parent], eax
	mov	[ebp], edx # store last handle
	pop	edi
	clc
9:	UNLOCK_WRITE_ [fs_handles_sem]
	ret

# in: esi = path part ptr
# in: ecx = path part len
# in: [ebp - 4] = full path
# in: edi = ptr to fs_handle struct
# out: [edi + fs_handle_mtab_idx]
# out: [edi + fs_handle_dir]
handle_pathpart$:
	.if FS_DEBUG > 1
		DEBUG "pathpart"
		call	nprint
		call	printspace
	.endif
	push	ecx
	push	esi
	# have esi, ecx refer to full path parsed so far
	add	ecx, esi
	mov	esi, [ebp - 4]
	sub	ecx, esi

	.if FS_DEBUG > 1
		DEBUG "so far"
		call	nprint
		call	printspace
	.endif

	push	ecx
	call	mtab_find_mountpoint	# in: esi, ecx; out: ebx+ecx
	mov	eax, ecx
	pop	ecx

	pop	esi
	pop	ecx
	jc	2f

	.if FS_DEBUG > 1
		printc 11, "mountpoint "
		push	esi
		mov	esi, [mtab]
		mov	esi, [esi + eax + mtab_mountpoint]
		call	print
		DEBUG_DWORD eax
		pop	esi
	.endif

	mov	[edi + fs_handle_mtab_idx], eax
	mov	[edi + fs_handle_dir], dword ptr -1	# filehandle

	# open mountpoint-relative root:
	push	ebp
	mov	ebp, esp
	push	dword ptr '/'	# keep stack align
	jmp	4f

2:	cmp	dword ptr [edi + fs_handle_mtab_idx], -1
	jz	1f
	######## copy the pathpart onto stack
	push	ebp
	mov	ebp, esp
	#################################################
	dec	esp		# allocate room for string + 0 terminator
	sub	esp, ecx
	push	edi		# copy string
	lea	edi, [esp + 4]
	rep	movsb
	mov	byte ptr [edi], 0
	pop	edi
	#######	prepare args, call filesystem api
4:	mov	esi, esp			# in: esi = file/dirname pointer
	mov	eax, [mtab]
	add	eax, [edi + fs_handle_mtab_idx]
	mov	eax, [eax + mtab_fs_instance]	# in: eax = fs_instance

	mov	ebx, [edi + fs_handle_dir]	# in: ebx = directory handle 
	push	edi
	add	edi, offset fs_handle_dirent	# in: edi = fs dir entry struct
	call	[eax + fs_api_open]
	pop	edi
	#################################################
	mov	esp, ebp
	pop	ebp
	#######
	jc	1f
	mov	[edi + fs_handle_dir], ebx	# out: ebx = fs specific handle
	ret

1:	test	[ebp + 12], dword ptr 0x80000000 # print error
	jz	1f
19:	printc 12, "File not found: "
	push	ecx
	push	esi
	add	ecx, esi
	mov	esi, [ebp - 4]
	sub	ecx, esi
	call	nprintln
	pop	esi
	pop	ecx
1:	stc
	ret

###############################################################################
# Utility functions


##############################################
# in: edi = current path / output [must be edi+esi bytes long at most]
# in: esi = relative/new path
# out: edi points to end of the new path pointed to by edi.
# effect: applies the (relative or absolute) path in esi to edi.
fs_update_path:
	push	ebp
	push	edi
	mov	ebp, esp
	push	eax
	push	ebx
	push	edx

	mov	ax, [esi]
	cmp	ax, '/'
	jnz	0f
########
	stosw
	jmp	4f
###
0:	cmp	al, '/'
	jnz	2f
##
	inc	esi
	inc	edi
	mov	byte ptr [edi], 0
	jmp	3f
##
2:	xor	al, al
	mov	ecx, MAX_PATH_LEN
	repne	scasb	
	dec	edi	# skip z, assume it ends with /
3:
###

########
	# edi points to somewhere within original path
	mov	ebx, esi
0:	xor	edx, edx
1:	lodsb
	or	al, al
	jz	1f
	cmp	al, '/'	# append / go deeper
	jz	2f
	cmp	al, '.'	# remove tail / ascend
	jnz	1b
	inc	edx
	jmp	1b

1:# 'damagnie' mov	byte ptr [esi -1 ], '/'
2:	# calculate path entry length
	mov	ecx, esi
	sub	ecx, ebx	# strlen
	dec	ecx
	jz	7f	# no length - no effect

	.if FS_DEBUG > 1
		push	esi
		mov	esi, ebx
		call	nprint
		printchar ' '
		pushcolor 13
		mov	esi, [ebp]
		call	print
		print " -> "
		popcolor
		pop	esi
	.endif

###	# check whether we just had a ... sequence
	sub	ecx, edx	# edx contains dotcount
	jnz	1f
##
	dec	edx	# single dot has no effect
	jz	7f
##
	shl	ax, 8	# preserve character
	dec	edi
2:	mov	al, '/'
	mov	ecx, edi
	sub	ecx, [ebp]
	jbe	3f
	je	3f
	dec	edi
	std
	repne	scasb
	cld
	inc	edi
	dec	edx
	jnz	2b
3:	shr	ax, 8

	mov	word ptr [edi], '/'
	inc	edi

	jmp	7f
##
1:	mov	ecx, esi
	sub	ecx, ebx

	push	esi
	mov	esi, ebx
	rep	movsb
	mov	byte ptr [edi], 0
	pop	esi
7:	
###
	.if FS_DEBUG > 1
		pushcolor 13
		push	esi
		mov	esi, [ebp]
		call	println
		pop	esi
		popcolor
	.endif

	mov	ebx, esi
	or	al, al
	jnz	0b
########
4:	pop	edx
	pop	ebx
	pop	eax
	add	esp, 4 # pop edi
	pop	ebp
	ret

#####################################################################
# POSIX file attributes and permissions

POSIX_TYPE_MASK = 0770000
POSIX_TYPE_SHIFT= 4*3

POSIX_TYPE_SOCK	= 0140000
POSIX_TYPE_LINK	= 0120000
POSIX_TYPE_FILE	= 0100000
POSIX_TYPE_BLK	= 0060000
POSIX_TYPE_DIR	= 0040000
POSIX_TYPE_CHR	= 0020000
POSIX_TYPE_FIFO	= 0010000

# Attributes: These apply to the 4th octal from the right:
POSIX_PERM_SETUID = 4
POSIX_PERM_SETGID = 2
POSIX_PERM_STICKY = 1
# These apply to the last 3 octals:
POSIX_PERM_R	= 4
POSIX_PERM_W	= 2
POSIX_PERM_X	= 1

# in: eax = posix bits: 6 octals (18 bits)
# octal values: 000000:  TTAugo
# TT=type: 0TT0000
#  14 = socket			(S_IFSOCK)
#  12 = symbolic link		(S_IFLNK)
#  10 = regular			(S_IFREG)
#  06 = block special		(S_IFBLK)
#  04 = directory		(S_IFDIR)
#  02 = character special	(S_IFCHR)
#  01 = pipe or FIFO		(S_IFIFO)
#  undefined: 00, 03, 05, 07, 11, 13, 15, 16, 17
# A=attributes (setuid, setgid, sticky)
# u,g,o: rwx permissions
fs_posix_perm_print:
	push	eax
	push	ebx
	push	ecx
	mov	ebx, eax

	rol	ebx, 32 - 18 + 6	# have first 2 valid octals in bl:
	movzx	eax, bl
	rol	ebx, 3
	and	al, 077
	.data SECTION_DATA_STRINGS
	posix_file_type_labels$:
	.byte '0'	# 000
	.byte 'f'	# 001 fifo
	.byte 'c'	# 002 char
	.byte '?'	# 003
	.byte 'd'	# 004 dir
	.byte '?'	# 005
	.byte 'b'	# 006 block
	.byte '?'	# 007
	.byte '-'	# 010 regular
	.byte '?'	# 011
	.byte 'l'	# 012 link
	.byte '?'	# 013
	.byte 's'	# 014 socket
	.ascii "???"	# 015, 016, 017: undefined
	.text32
	mov	al, [posix_file_type_labels$ + eax]
	call	printchar

	# get the special bits in ch
	mov	ch, bl
	and	ch, 7
	rol	ebx, 3

	call	posix_perm_3_print$

	rol	ebx, 3
	shl	ch, 1

	call	posix_perm_3_print$

	rol	ebx, 3
	shl	ch, 1
	or	ch, 0x80	# print 'T' 't' instead of 'S' 's'

	call	posix_perm_3_print$

	pop	ecx
	pop	ebx
	pop	eax
	ret

posix_perm_3_print$:
	# 'R' bit
	mov	ax, '-' | 'r' << 8
	mov	cl, bl
	shl	cl, 1
	and	cl, 8
	shr	eax, cl
	call	printchar

	# 'W' bit
	mov	ax, '-' | 'w' << 8
	mov	cl, bl
	shl	cl, 2
	and	cl, 8
	shr	eax, cl
	call	printchar

	# 'X' bit: '-', 'x', 'S', 's'
	mov	eax, '-' | 'x' << 8 | 'S' << 16 | 's' << 24
	mov	cl, bl
	shl	cl, 3
	and	cl, 8
	shr	eax, cl
	mov	cl, ch
	and	cl, 4	#highest special bit
	shl	cl, 2
	shr	eax, cl	# ax is either '-x' or 'Ss'

	# we only want to increment the letter if eax was shifted, cl=16
	shl	cl, 3	# cl is now either 0 or 0x80
	add	ch, cl	# 0x80 + 0x80 -> CF

	adc	al, 0	# increment 'S'/'s' to 'T'/'t'

	call	printchar
	ret

###############################################################################
.endif # DEFINE

