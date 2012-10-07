###############################################################################
## FileSystem: mtab / mount, fs
##
.intel_syntax noprefix
.code32

FS_DEBUG = 0

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

.text32


mount_init$:
	call	mtab_init
	call	fs_init
	ret

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
	push	edx
	call	mtab_entry_alloc$	# out: ebx + edx
	jc	2f
###	# add root entry
	push	eax
	mov	eax, 2
	call	mallocz
	jc	1f
	mov	[eax], word ptr '/'
	mov	[ebx + edx + mtab_mountpoint], eax
	mov	[ebx + edx + mtab_fs_instance], dword ptr offset fs_root_instance
1:	pop	eax
###
2:	pop	edx
	ret


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
	push	eax
	push	ecx
	push	esi
	mov	esi, ecx
	call	fs_load$	# out: edi = fs info structure
	pop	esi
	pop	ecx
	pop	eax
	jc	4f

	# create a new mtab entry

	call	mtab_entry_alloc$	# out: ebx + edx
	jc	7f

	mov	[ebx + edx + mtab_flags], word ptr MTAB_FLAG_PARTITION
	mov	[ebx + edx + mtab_disk], ax
	mov	[ebx + edx + mtab_fs_instance], edi

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
	mov	eax, ebx
	add	eax, edx

	mov	dl, [eax + mtab_fs]
	printc	14, "type "
	call	printhex2
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
	push	ebx
	push	ecx
	push	edx
	ARRAY_LOOP [fs_classes], 4, ebx, edx, 9f
	mov	ecx, [ebx + edx]
	push	ebx
	push	edx
	call	[ecx + fs_api_mount]
	pop	edx
	pop	ebx
	jnc	0f
1:	ARRAY_ENDL

9:	printlnc 4, "unsupported filesystem"
	stc

0:	pop	edx
	pop	ecx
	pop	ebx
	ret


mtab_print$:
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
	mov	esi, [esi + fs_obj_class]
	mov	esi, [esi + fs_api_label]
	call	print
	color 7
	printc_	8, " (disk "
	mov	dl, byte ptr [ebx + ecx + mtab_disk]
	call	printdec32
	printc_	8, " partition "
	mov	dl, byte ptr [ebx + ecx + mtab_partition]
	call	printdec32
	call	printspace
	mov	eax, [ebx + ecx + mtab_partition_size]
	xor	edx, edx
	color	7
	call	ata_print_size
	printc_	8, ")"
1:	call	newline
	ARRAY_ENDL
0:	popcolor
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
fs_api_label:	.long 0	# short filesystem name
# in: ax: al = disk ah = partition
# in: esi = partition table pointer
# out: eax: class instance (object)
fs_api_mount:	.long 0	# constructor; in: ax = part/disk, esi = part info
fs_api_umount:	.long 0 # destructor
# in: eax = fs_instance
# in: ebx = parent/current directory handle (-1 for root)
# in: esi = asciz file/dirname pointer
# in: edi = fs dir entry struct
# out: ebx = fs specific handle
fs_api_open:	.long 0
fs_api_close:	.long 0
fs_api_nextentry:.long 0
fs_api_read:	.long 0	# ebx=filehandle, edi=buf, ecx=size
FS_API_NUM_METHODS = (. - fs_api_mount) / 4
FS_API_STRUCT_SIZE = .

###################################################
# fs_obj 
.struct 0
fs_obj_class:		.long 0	# pointer to fs_class (array of fs_api methods)
fs_obj_disk:		.byte 0
fs_obj_partition:	.byte 0
fs_obj_sector_size:	.long 0 # 512 for ATA, 2048 for ATAPI generally
fs_obj_p_start_lba:	.long 0, 0
fs_obj_p_size_sectors:	.long 0, 0
fs_obj_p_end_lba:	.long 0, 0
fs_obj_methods:		.space FS_API_STRUCT_SIZE
FS_OBJ_STRUCT_SIZE = .
###################################################
.data
fs_classes:	.long 0	# ptr_array of class_ptr
###################################################
.text32

fs_init:
	mov	ecx, 8
	mov	eax, 3
	call	array_new
	mov	[fs_classes], eax

	mov	ebx, offset fs_root_class
	call	fs_register_class

	mov	ebx, offset fs_fat16_class
	call	fs_register_class

	mov	ebx, offset fs_iso9660_class
	call	fs_register_class

	mov	ebx, offset fs_sfs_class
	call	fs_register_class
	ret


fs_list_filesystems:
	ARRAY_LOOP [fs_classes], 4, eax, ebx, 9f
	printc	11, "fs: "
	mov	edx, [eax + ebx]
	call	printhex8
	call	printspace
	pushcolor 14
	mov	esi, [edx + fs_api_label]
	call	println
	popcolor
	ARRAY_ENDL
9:	ret


fs_register_class:
	call	ptr_array_newentry
	mov	[fs_classes], eax
	add	edx, eax
	mov	[edx], ebx	# class ptr
	mov	edx, [realsegflat]
	mov	ecx, FS_API_NUM_METHODS
0:	add	[ebx + ecx * 4 - 4], edx
	loop	0b
	ret


fs_mount:
	ret

fs_unmount:
	ret

#############################################################################
.data
fs_root_class:	# declaration of fs_api for fs_root class
	STRINGPTR "root"
	.long fs_root_mount$
	.long fs_root_umount$
	.long fs_root_open$
	.long fs_root_close$
	.long fs_root_nextentry$
	.long fs_root_read$

fs_root_instance:
.long fs_root_class

.text32
fs_root_mount$:
	stc
	ret
fs_root_umount$:
	printlnc 4, "fs_root_umount: not implemented"
	stc
	ret

# in: eax = offset fs_root_instance
# in: esi = directory
# in: edi = fs dirent
fs_root_open$:
	cmp	word ptr [esi], '/'
	jz	0f
	.if FS_DEBUG > 1
		printc 4, "fs_root_open "
		call	print
		printlnc 4, ": not found"
	.endif
	stc
	ret
0:	mov	ebx, -1	# indicates root
	mov	byte ptr [edi + fs_dirent_attr], 0x10
	mov	word ptr [edi + fs_dirent_name], '/'
	clc
	ret

fs_root_close$:
	clc
	ret

fs_root_nextentry$:
	printlnc 4, "fs_root_nextentry: not implemented"
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
fs_dirent_name: .space 255
fs_dirent_attr:	.byte 0		# RHSVDA78
  FS_DIRENT_ATTR_DIR = 1 << 4
fs_dirent_size:	.long 0, 0
FS_DIRENT_STRUCT_SIZE = .
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

# Since the structure is several doublewords long, a number of bits in the
# offset becomes available. These can be used as flags. Otherwise,
# the index/handle might be shifted this number of bits to provide a contiguous
# numbering scheme with a distance of 1.
#
# 3 bits:
# - directory or file
# - softlink

.data
# open files
fs_handles$:	.long 0
.text32

# out: eax + edx = fs_handle base + index
fs_new_handle$:
	push	ecx
	mov	eax, [fs_handles$]
	xor	edx, edx
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	or	eax, eax
	jnz	1f
	call	array_new
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

# in: eax = handle offset
fs_handle_printinfo:
	push	esi
	push	edx
	push	ebx
	push	eax

	printc	11, "Handle "
	mov	edx, eax
	call	printhex8
	mov	ebx, [fs_handles$]

	printc 	13, " mtab "
	mov	edx, [eax + ebx + fs_handle_mtab_idx]
	call	printhex8

	printc 	13, " dir "
	mov	edx, [eax + ebx + fs_handle_dir]
	call	printhex8

.if 1
	printc	10, " attr: "
	mov	dl, [eax + ebx + fs_handle_dirent + fs_dirent_attr]
	call	printhex2
.endif

	mov	esi, [eax + ebx + fs_handle_label]
	cmp	esi, -1
	jz	1f
	printc	10, " name: '"
	call	print
	printcharc 10, '\''
	jmp	2f
1:	printc 11, " Available"
2:

.if 1
	test	al, 2
	jnz	1f
	printc 6, " entries: "
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
	ret


# out: ZF = 1: file, 0: directory (jz dir$ ;  jnz file$)
fs_handle_isdir:
	test	eax, 1
	ret

# in: eax = handle index
# out: esi
fs_handle_getname:
	mov	esi, [fs_handles$]
	mov	esi, [eax + esi + fs_handle_label]
	ret


	.macro FS_HANDLE_CALL_API api, reg
		# proxy through mtab to fs_instance
		mov	eax, [eax + edx + fs_handle_mtab_idx]
		add	eax, [mtab]
		mov	eax, [eax + mtab_fs_instance]
		# locate the method
		mov	\reg, [eax + fs_obj_class]
		call	[\reg + fs_api_\api]
		#mov	\reg, [\reg + fs_api_\api]
		#clc
		#jecxz	99f	# root
#		add	\reg, [realsegflat]
		#call	\reg	# in: eax, ebx
	99:	
	.endm
# in: eax = handle index
# out: edx = fs_dirent or something..
# out: esi = fs_dirent
# out: CF = error
# out: ZF = no next entry
fs_nextentry:
	push	eax
	call	fs_validate_handle	# in: eax; out: eax + edx
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
	push	edx
	FS_HANDLE_CALL_API nextentry, edx
	# out: edx = fir name
	mov	esi, edx
	pop	edx
	# out: ecx = next entry
	mov	eax, [fs_handles$]
	mov	[eax + edx + fs_handle_dir_iter], ecx
	pop	ebx
	pop	ecx
	mov	edx, esi
	pop	esi

0:	pop	eax
	ret

9:	printc 4, "fs_nextentry: unknown handle: "
	call	printhex8
	stc
	jmp	0b

# in: eax = handle
# out: esi = buffer
# out: ecx = bytes to read/max buf size
fs_handle_read:
	push	eax
	push	edi
	push	edx
	call	fs_validate_handle
	jc	9f

	mov	edi, [eax + edx + fs_handle_buf]
	or	edi, edi
	jnz	1f
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
	pop	eax
	ret
9:	printc 4, "fs_handle_read: unknown handle"
	stc
	jmp	0b


# cmd_lsof
fs_list_openfiles:
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

1:	ret


# in: eax = handle index
# out: eax = [fs_handles]
# out: edx = handle index
# out: CF
fs_validate_handle:
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
fs_close:	# fs_free_handle
	push	edx
	push	ebx
	push	ecx

	call	fs_validate_handle	# out: eax+edx
	jc	1f

	mov	ebx, eax
	mov	eax, [ebx + edx + fs_handle_label]

	.if FS_DEBUG
		push esi
		PRINT_ "fs_close: "
		mov	esi, eax
		PRINTLNS_
		pop esi
	.endif

	call	mfree

	mov	eax, ebx
	# mark filesystem handle as free
	mov	[eax + edx + fs_handle_label], dword ptr -1

	mov	ebx, [eax + edx + fs_handle_dir]
	push	edi
	lea	edi, [eax + edx + fs_handle_dirent]
	FS_HANDLE_CALL_API close, ecx
	pop	edi

0:	mov	eax, -1
	pop	ecx
	pop	ebx
	pop	edx
	ret

1:	printc	4, "fs_close: free for unknown handle: "
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
.data
fs_openfoo: .byte 0
.text32


fs_openfile:
	mov	byte ptr [fs_openfoo], 1
	jmp	0f
fs_opendir:
	mov	byte ptr [fs_openfoo], 2
0:
####################################################################
	push	ebp
	push	ebx
	push	ecx
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
	push	esi
	call	handle_pathpart$
	pop	esi
###############################################

	xor	ecx, ecx
0:	mov	al, '/'
	call	strtok	# out: esi, ecx
	jc	1f
	push	esi	# preserve for next strtok call
	push	ecx

		# todo: clear stack handle
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

	call	handle_pathpart$
		jc	2f
		# allocate handle for each subdir
		call	fs_new_handle$	# out: eax + edx
		jc	2f	# TODO: also dealloc handle_pathparth's ebx
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
	2:

	pop	ecx
	pop	esi
	jnc	0b
	# error: CF=1
	mov	eax, -1	# side effect for clarity
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
	clc

9:	mov	esp, ebp
	pop	edi	# pop space for last handle
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	ebp
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

	mov	edx, [eax + fs_obj_class]	# for call
	mov	ebx, [edi + fs_handle_dir]	# in: ebx = directory handle 
	push	edi
	add	edi, offset fs_handle_dirent	# in: edi = fs dir entry struct
	call	[edx + fs_api_open]
	pop	edi
	#################################################
	mov	esp, ebp
	pop	ebp
	#######
	jc	1f
	mov	[edi + fs_handle_dir], ebx	# out: ebx = fs specific handle
	ret

1:	printc 12, "File not found: "
	push	ecx
	push	esi
	add	ecx, esi
	mov	esi, [ebp - 4]
	sub	ecx, esi
	call	nprintln
	pop	esi
	pop	ecx
	stc
2:	ret

###############################################################################
# Utility functions


##############################################
# in: edi = current path / output [must be edi+esi bytes long at most]
# in: esi = relative/new path
# out: edi points to end of the new path pointed to by edi.
# effect: applies the (relative or absolute) path in esi to edi.
fs_update_path:
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

1:	mov	byte ptr [esi -1 ], '/'
2:	# calculate path entry length
	mov	ecx, esi
	sub	ecx, ebx	# strlen
	dec	ecx
	jz	7f	# no length - no effect

	.if 0
		cmp	byte ptr [ebp], 0
		jz	1f
		push	esi
		mov	esi, ebx
		call	nprint
		printchar ' '
		pushcolor 13
		mov	esi, offset cd_cwd$
		call	print
		print " -> "
		popcolor
		pop	esi
	1:
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
	sub	ecx, offset cd_cwd$
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
	.if 0
		cmp	byte ptr [ebp], 0
		jz	1f
		pushcolor 13
		push	esi
		mov	esi, offset cd_cwd$
		call	println
		pop	esi
		popcolor
	1:
	.endif

	mov	ebx, esi
	or	al, al
	jnz	0b
########
4:	pop	edx
	pop	ebx
	pop	eax
	ret


###############################################################################
