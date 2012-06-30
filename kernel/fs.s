###############################################################################
## FileSystem: mtab / mount, fs
##
.intel_syntax noprefix
.code32

FS_DEBUG = 1

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

.text


mount_init$:
	call	mtab_init
	call	fs_init
	ret

############################################################################
##
# The mtab maintains a compact array. Any references to its indices
# are not guaranteed to work after mtab_entry_free.
# mtab global static initializer. Call once from kernel.
.struct 0
mtab_mountpoint:	.long 0	# string pointer
mtab_flags:		.byte 0
mtab_fs:		.byte 0	# filesystem type (at current: standard)
mtab_disk:		.byte 0	# disk number
mtab_partition:		.byte 0	# partition number
mtab_partition_start:	.long 0	# LBA start
mtab_partition_size:	.long 0	# sectors
mtab_fs_instance:	.long 0 # file-system specific data structure
MTAB_FLAG_PARTITION =  1
.data
MTAB_ENTRY_SIZE = 20
MTAB_INITIAL_ENTRIES = 1
mtab: .long 0
.text
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
1:	pop	eax
###
2:	pop	edx
	ret


# out: ebx = mtab base ptr (might have change)
# out: edx = index guaranteed to hold one mtab entry
# side-effect: index increased to point to next.
# side-effect: [mtab] updated on resize
mtab_entry_alloc$:
	push	ecx
	push	eax

	mov	eax, [mtab]
	mov	ecx, MTAB_ENTRY_SIZE

	or	eax, eax
	jnz	0f
	inc	eax
	call	array_new
	jc	2f

0:	call	array_newentry
	jc	2f
	mov	[mtab], eax
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
	call	mount_init$	# TODO: remove

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
	call	disk_parse_partition_label
	jc	6f

	# alternative for disk_print_label
	printc 14, "disk "
	movzx	edx, al
	call	printdec32
	printc 14, " partition "
	movzx	edx, ah
	call	printdec32
	call	printspace

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
	mov	ebx, [fs_classes]
	xor	edx, edx
	jmp	1f
0:	
	mov	ecx, [ebx + edx]
	mov	ecx, [ecx + fs_api_mount]
	jecxz	2f
	add	ecx, [realsegflat]
	call	ecx
	jnc	0f

2:	add	edx, 4
1:	cmp	edx, [ebx + array_index]
	jb	0b
	printlnc 4, "unsupported filesystem"
	stc

0:	pop	edx
	pop	ecx
	pop	ebx
	ret


fs_load_OLD$:
	cmp	byte ptr [esi + PT_TYPE], 6
	jz	fs_fat16b_mount

	printlnc 4, "unsupported partition type: "
	push	edx
	mov	dl, [esi + PT_TYPE]
	call	printhex2
	pop	edx
	call	newline
	stc
	ret



mtab_print$:
	xor	ecx, ecx
	xor	edx, edx
0:	cmp	ecx, [ebx + buf_index]
	jae	0f
	test	byte ptr [ebx + ecx + mtab_flags], MTAB_FLAG_PARTITION
	jz	1f
	mov	ax, [ebx + ecx + mtab_disk]
	call	disk_print_label
	.if 0
	print_	"hd"
	mov	al, [ebx + ecx + mtab_disk]
	add	al, 'a'
	call	printchar
	movzx	edx, byte ptr [ebx + ecx + mtab_partition]
	call	printdec32
	.endif
	jmp	2f
1:	print_	"none"
2:	print_	" on "
	mov	esi, [ebx + ecx + mtab_mountpoint]
	call	print
	print_	" fs "
	mov	dl, [ebx + ecx + mtab_fs]
	call	printhex2
	print_	" (disk "
	mov	dl, byte ptr [ebx + ecx + mtab_disk]
	call	printdec32
	print_	" partition "
	mov	dl, byte ptr [ebx + ecx + mtab_partition]
	call	printdec32
	call	printspace
	mov	eax, [ebx + ecx + mtab_partition_size]
	xor	edx, edx
	call	ata_print_size
	print_	")"
	
	call	newline

	add	ecx, MTAB_ENTRY_SIZE
	jmp	0b
0:	ret

# in: esi = string
# out: ebx = [mtab]
# out: ecx = offset relative to ebx
mtab_find_mountpoint:
	push	edi
	push	eax

	mov	eax, esi
	call	strlen
	mov	ecx, eax
	# esi, ecx
	mov	ebx, [mtab]
	xor	eax, eax

0:	cmp	eax, [ebx + buf_index]
	jae	1f
	mov	edi, [ebx + eax + mtab_mountpoint]

	push	ecx
	push	esi
	rep	cmpsb
	pop	esi
	pop	ecx
	clc
	jz	0f
	add	eax, MTAB_ENTRY_SIZE
	jmp	0b

1:	xor	eax, eax
	stc
0:	mov	ecx, eax

	pop	eax
	pop	edi
	ret


cmd_umount$:
	printlnc 4, "umount: not implemented"
	ret

#############################################################################
# The FS_API - fs info structure/class: method pointers
#
# for all calls:
# eax = pointer to fs info (as stored in mtab_fs_instance)
# in: ebx = fs-specific handle from previous call or -1 for root directory
.struct 0
# in: ax: al = disk ah = partition
# in: esi = partition table pointer
# out: eax: class instance (object)
fs_api_mount:	.long 0	# constructor
fs_api_umount:	.long 0 # destructor
# in: esi = string (directory entry name)
# out: ebx = fs specific handle
fs_api_opendir:	.long 0
fs_api_close:	.long 0


.data
fs_classes:	.long 0	# array
.text

fs_init:
	mov	ecx, 4
	mov	eax, 1
	call	array_new

	call	array_newentry
	mov	dword ptr [eax + edx], offset fs_fat16_class

	mov	[fs_classes], eax
	ret


fs_mount:
	ret

fs_unmount:
	ret

#############################################################################
.struct 0
fs_node_label:	.long 0
fs_node_parent:	.long 0
fs_node_data:	.long 0
fs_node_flags:	.byte 0
	FS_NODE_FLAG_MTAB = 1	# node_data is an mtab relative-offset
FS_NODE_SIZE = 16
FS_NODE_SIZE_BITS = 4
FS_TREE_INITIAL_NODECOUNT = 4

.data
fs_root$:	.long 0
.text


fs_printtree:
	call	fs_getroot$
	jc	1f

	push	edx
	push	ebx
	mov	ebx, edx

0:	cmp	ebx, [eax + array_index]
	jae	2f

	printc	11, "FS Node: "
	mov	edx, ebx
	sar	edx, FS_NODE_SIZE_BITS
	call	printdec32

	printc	11, " label "

	mov	esi, [eax + ebx + fs_node_label]
	call	print

	printc	11, " parent "
	mov	edx, [eax + ebx + fs_node_parent]
	sar	edx, FS_NODE_SIZE_BITS
	call	printdec32

	printc	11, " flags "
	mov	dl, [eax + ebx + fs_node_flags]
	call	printbin8

	printc	11, " data "
	mov	edx, [eax + ebx + fs_node_data]
	call	printhex8

	test	byte ptr [eax + ebx + fs_node_flags], FS_NODE_FLAG_MTAB
	jz	3f

	printc	11, " MTAB: "
	add	edx, [mtab]
	push	esi
	mov	esi, [edx + mtab_mountpoint]
	call	print
	pop	esi
3:
	call	newline

	add	ebx, FS_NODE_SIZE
	jmp	0b

2:	pop	ebx
	pop	edx

1:	ret

# array/buf functions with eax + edx
# fs_/mtab functions with  ebx + edx


# out: eax = [fs_root$], base ptr
# out: edx = 0, index
fs_getroot$:
	xor	edx, edx
	mov	eax, [fs_root$]
	or	eax, eax
	jnz	0f

	push	ebx
	push	ecx
	push	esi

	mov	ecx, FS_NODE_SIZE
	mov	eax, FS_TREE_INITIAL_NODECOUNT
	call	array_new	# in: eax, ecx; out: eax
	mov	[fs_root$], eax

	LOAD_TXT "/"
	call	mtab_find_mountpoint	# in: esi; out: ebx+ecx
	jc	2f

	mov	esi, [ebx + ecx + mtab_mountpoint]

	mov	edx, -1
	call	fs_newnode	# in: esi; out: eax+edx

	mov	[eax + edx + fs_node_data], ecx	# store mtab rel ptr
	mov	[eax + edx + fs_node_flags], byte ptr FS_NODE_FLAG_MTAB

1:	pop	esi
	pop	ecx
	pop	ebx
	
0:	ret

2:	printlnc 12, "root filesystem node not found"
	stc
	jmp	1b


# in: esi = pointer to string (will be strdup'd)
# in: edx = parent node
# out: eax = fs tree base pointer
# out: edx = fs node index
# side effect: fs_root$ updated on resize
fs_newnode:
	push	eax
	mov	eax, esi
	call	strdup
	mov	esi, eax
	pop	eax

	push	edx

	push	ecx
	mov	ecx, FS_NODE_SIZE
	mov	eax, [fs_root$]
	call	array_newentry
	mov	[fs_root$], eax	# edx = 0, so, base ptr works!
	pop	ecx

	mov	[eax + edx + fs_node_label], esi
	pop	dword ptr [eax + edx + fs_node_parent]

	.if FS_DEBUG
		call newline
		printc 11, "Created new node: "
		call	printhex8
		call	printspace
		printchar '\''
		call	print
		printchar '\''
		call	newline
	.endif
	ret

# in: esi = string pointer to node to find
# in: eax = fs tree base pointer
# in: edx = fs current node
# out: edx = fs result node
# out: CF (1: edx destroyed)
fs_getentry:
	push	ebx
	call	strlen
	mov	ecx, eax

call newline
DEBUG "  fs_getentry(path="
DEBUGS
DEBUG " slen="
DEBUG_DWORD ecx
DEBUG " cur="
DEBUG_DWORD edx
DEBUG ")"

	mov	eax, [fs_root$]	# REQUIRE fs_getroot
	xor	ebx, ebx

	jmp	1f
	# for now, slow iteration through all to see if match
0:	
call newline
DEBUG "    check n="
DEBUG_DWORD ebx
DEBUG "parent="
push ecx
mov ecx, [eax+ebx+fs_node_parent]
DEBUG_DWORD ecx
pop ecx
push esi
mov esi, [eax + ebx + fs_node_label]
DEBUG "'"
DEBUGS
DEBUG "'"
pop esi

	# check if it is a child node
	cmp	[eax + ebx + fs_node_parent], edx
	jnz	2f
DEBUG "parent match"
	# check if the label matches
	push	ecx
	push	esi
	push	edi
	mov	edi, [eax + ebx + fs_node_label]
	repz	cmpsb
	pop	edi
	pop	esi
	pop	ecx
	jz	3f
DEBUG "path mismatch"
2:	add	ebx, FS_NODE_SIZE
1:	cmp	ebx, [eax + array_index]
	jb	0b
DEBUG "fail"
call newline
	stc
0:	pop	ebx
	ret

3:	mov	edx, ebx
DEBUG "match"
DEBUG_DWORD edx
call newline
	clc
	jmp	0b

# in: ebx = mtab index
# out: ebx = mtab-compatible index
fs_getentry_TODO:
	push	ebx
	push	ecx

	# TODO: use [mtab] + ebx to load partition type and find
	# proper handler.
	#
	# so far the approach is that this method is called once for
	# each deeper directory, and thus, another pointer must be
	# kept that:
	# - builds the path string relative to the mount point, or:
	# - holds a handle with meaning for the specific fs implementation,
	#   such as a FAT cluster number.
	#
	# Another approach is to construct a tree (for caching)
	# with all the directories traversed.
	#
	#

0:	pop	ecx
	pop	ebx
	ret

.struct 0			# index bits available:
fs_handle_label:	.long 0	# total 2
fs_handle_mtab_idx:	.long 0 # total 3
fs_handle_dir:		.long 0 # total 2
fs_handle_dir_iter:	.long 0 # total 4
fs_handle_dir_size:	.long 0 # total 2
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
.text

# out: eax + edx = fs_handle base + index
fs_new_handle$:
	push	ecx
	mov	ecx, FS_HANDLE_STRUCT_SIZE
	mov	eax, [fs_handles$]
	or	eax, eax
	jnz	1f
	inc	eax
	call	array_new

1:	
	call	array_newentry
	mov	[fs_handles$], eax
	pop	ecx
	ret

fs_handle_printinfo:
	printc	11, "Handle "
	mov	edx, eax
#	push	edx
#	shr	edx, 4
	call	printhex8
#	pop	edx

	printc	5, " Flags: "
	call	printbin2

	mov	eax, [fs_handles$]

	printc	5, " name: '"
	mov	esi, [eax + edx + fs_handle_label]
	call	print
	printcharc 5, '\''

	test	dl, 1
	jnz	1f

	add	eax, edx
	mov	edx, [eax + fs_handle_dir_size]
	printc 6, " entries: "
	call	printdec32

	mov	edx, [eax + fs_handle_dir_iter]
	printc 6, " current: "
	call	printdec32
1: 
	call	newline
	ret


# out: ZF = 1: file, 0: directory (jz dir$ ;  jnz file$)
fs_handle_isdir:
	test	eax, 1
	ret

# out: esi
fs_handle_getname:
	mov	esi, [fs_handles$]
	mov	esi, [eax + esi + fs_handle_label]
	ret

fs_nextentry:
	stc
	ret


fs_list_openfiles:
	# map { print } @fs_handles;
	mov	eax, [fs_handles$]
	or	eax, eax
	jz	1f
	print "handles: "
	mov	edx, [eax + array_index]
	call	printhex8
	call	newline

	xor	ebx, ebx
	jmp	1f
0:
	mov	edx, ebx
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fs_handle_mtab_idx]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fs_handle_dir]
	call	printhex8
	call	printspace
	mov	esi, [eax + ebx + fs_handle_label]
	mov	edx, esi
	call	printhex8
	call	printspace
	call	println
	add	ebx, FS_HANDLE_STRUCT_SIZE
1:	cmp	ebx, [eax + array_index]
	jb	0b

1:	ret

# in: eax = index
fs_close:	# fs_free_handle
	mov	edx, eax

	or	edx, edx
	js	1f	# limit on number of handles: 2Gb/FS_HANDLE_STRUCT_SIZE

	mov	ebx, [fs_handles$]
	or	ebx, ebx
	jz	1f
	cmp	edx, [ebx + array_index]
	jae	1f

	# ebx + edx = array + index

	mov	eax, [ebx + edx + fs_handle_label]

	.if FS_DEBUG
		push esi
		PRINT_ "fs_close: "
		mov	esi, eax
		PRINTLNS_
		pop esi
	.endif

	call	mfree

	# mark filesystem handle as free
	# proxy through mtab to fs_instance
	mov	eax, [mtab]
	mov	eax, [eax + edx + mtab_fs_instance]
	# locate the method
	mov	ecx, [eax + fs_class]
	mov	ecx, [ecx + fs_api_close]
	clc
	jecxz	0f	# root
	add	ecx, [realsegflat]
	call	ecx	# in: eax, ebx
0:
	# mark the handle as available
	mov	[ebx + edx + fs_handle_label], dword ptr -1

0:	ret

1:	printlnc 4, "fs_close: free for unknown handle: "
	call	printhex8
	call	newline
	stc
	jmp	0b

# Traverses the directories indicated by the path, giving precedence
# to mountpoints, delegating directory opening to whatever filesystem.
# 
# It returns a directory handle index which must be freed by fs_free_handle.
# The structure it returns contains a strdupped label, aswell as
# a reference to the mountpoint used - the filesystem type - and a directory
# handle, which only has meaning to the specific filesystem.
# The single return value thus abstracts the use of different filesystems.
# For file/directory operations, the file handle along would be insufficient
# as the filesystem it refers to is unknown.
#
# 
# in: eax = pointer to path string
# out: eax = directory handle (pointer to struct)
fs_opendir:
	push	ebp
	push	edi
	push	esi
	push	edx
	push	ecx
	push	ebx
	push	eax	# [ebp + 8]

	call	strdupn		# in: eax; out: eax, ecx
	push	eax	# [ebp + 4]
	mov	esi, eax

	# allocate space to hold the processed path
	mov	eax, ecx
	inc	eax
	call	malloc
	push	eax	# [ebp]
	mov	ebp, esp

# in: esi = label

	printc 10, "opendir "
	call	println

	mov	edx, -1		# mtab index
	mov	ebx, -1		# fs specific directory handle

#########################################
0:	or	ecx, ecx
	jz	0f

	mov	edi, esi
	mov	al, '/'
	repne	scasb

	mov	eax, edi
	sub	eax, esi	# always at least 1

	mov	byte ptr [edi - 1], 0

	.if FS_DEBUG 
		pushcolor 4

		push	edx
		mov	edx, eax
		call	printdec32
		printchar ' '
		pop	edx

		color	11
		call	print

		popcolor
	.endif

	# copy path scanned so far

	push	edi
	push	esi
	push	ecx
	mov	ecx, edi
	sub	ecx, [ebp + 4]	# scan path
	dec	ecx		# remove trailing /
	jnz	1f
	inc	ecx
1:	mov	edi, [ebp]	# current path
	mov	esi, [ebp + 8]	# original path
	rep	movsb
	mov	byte ptr [edi], 0
	pop	ecx
	pop	esi
	pop	edi

	.if FS_DEBUG
		push	esi
		call	printspace
		printcharc 15, '<'
		mov	esi, [ebp]
		call	print
		printcharc 15, '>'
		pop	esi
	.endif

	# ecx = total string left
	# esi = start of match
	# edi = end of match/start of rest of string to scan
	# eax = match length (edi-esi)
	# ebx = current directory handle
#DEBUG_REGSTORE
	call	fs_process_pathent$	# out: ebx
#DEBUG_REGDIFF
	jc	2f

	call	newline
#########

	mov	esi, edi
	jmp	0b

#########################################

2:	call	newline
	printc 12, "directory not found: "
	mov	esi, [ebp]
	call	println

	mov	eax, [ebp]
	call	mfree
	stc
	jmp	1f

0:	
	# allocate a handle
	call	fs_new_handle$

	mov	esi, [ebp]
	mov	[eax + edx + fs_handle_mtab_idx], edx
	mov	[eax + edx + fs_handle_dir], ebx
	mov	[eax + edx + fs_handle_label], esi

	clc
1:
	pop	esi	# processed string
	pop	eax	# work buffer
	pushf
	call	mfree
	popf
	pop	eax	# old eax: original path string
	mov	eax, edx
	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
	pop	edi
	pop	ebp
	ret




# in: eax = pathent match len
# in: edx = current mtab entry
# in: ebx = current directory entry (within mount)
# in: [ebp] = pathstring so far
# out: CF = path not found
# preserve: edi, ecx
fs_process_pathent$:

	.if FS_DEBUG > 1
		DEBUG "cur="
		DEBUG_DWORD edx
		DEBUG "dirhandle="
		DEBUG_DWORD ebx

		push esi
		DEBUG "esi"
		DEBUGS
		DEBUG "[ebp]"
		mov esi, [ebp]
		DEBUGS
		DEBUG "[ebp+4]"
		mov esi, [ebp+4]
		DEBUGS
		DEBUG "[ebp+8]"
		mov esi, [ebp+8]
		DEBUGS
		call newline
		pop esi
	.endif

	## check mountpoint
	
	# first see if the current path is a mount point
	push	ecx
	push	ebx

	push	esi
	mov	esi, [ebp]
	call	mtab_find_mountpoint # in: esi; out: ebx+ecx
	pop	esi
	pop	ebx
	jc	1f

	printc 11, "mountpoint"

	mov	edx, ecx
	LOAD_TXT "/"

	clc
###

1:	mov	eax, [mtab]
	mov	eax, [eax + edx + mtab_fs_instance]
	mov	ecx, [eax + fs_class]
	mov	ecx, [ecx + fs_api_opendir]
	clc
	jecxz	3f	# root
	add	ecx, [realsegflat]

	# in: eax = pointer to fs info
	# in: esi = pointer to directory name
	call	ecx
	# out: ebx = directory handle if found.
	jc	3f
	clc
###

3:	
	pop	ecx
	
	ret



# in: eax = pathent match len
# out: CF = path not found
# preserve: edi, ecx
fs_process_pathent_TMP$:

	### check root
	dec	eax
	jnz	1f

######## root
	.if FS_DEBUG
		printc 13, " root '"
		push esi
		mov esi, [ebp]
		call print
		pop esi
		printc 13, "'"
	.endif

	mov	edx, -1
	clc
	jmp	3f

######## subdir
1:	printc 13, " sub "

	## check mountpoint
	
	# first see if the current path is a mount point
	push	esi
	push	ecx
	push	ebx

	mov	esi, [ebp]
	call	mtab_find_mountpoint # in: esi; out: ebx+ecx
	jc	1f

	printc 11, "mountpoint"

	mov	esi, [ebx + ecx + mtab_mountpoint]

	clc

1:	pop	ebx
	pop	ecx
	pop	esi

	jc	3f	

###
	# the tree doesnt have the directory entry, so try to load
	# using filesystem handler:
	call newline
DEBUG "fs="
DEBUG_DWORD eax
DEBUG "idx="
DEBUG_DWORD edx
	printc 8, "delegate "
	printc 8, "flags "
	push edx
	mov dl, [eax+edx+fs_node_flags]
	call printhex2
	pop edx
	push edx
	printc 8, "node_data "
	mov edx, [eax+edx +fs_node_data]
	call printhex8
	call printspace
	pop edx
	test	byte ptr [eax + edx + fs_node_flags], FS_NODE_FLAG_MTAB
	jz	1f

	push	ebx
	push	ecx
	mov	ebx, [mtab]
DEBUG "mtab="
DEBUG_DWORD ebx
	mov	ecx, [eax + edx + fs_node_data]
DEBUG "idx="
DEBUG_DWORD ecx
	# now use the mtab data to call the handler
	mov	dx, [ebx + ecx + mtab_disk]
	printc 8, "MTAB disk "
	call	printhex2
	printc 8, " partition "
	xchg	dl, dh
	call	printhex2
	printc 8, " fs "
	mov	dl, [ebx + ecx + mtab_fs]
	call	printhex2
	printc 8, " LBA "
	mov	edx, [ebx + ecx + mtab_partition_start]
	call	printhex8
	printc 8, " size "
	mov	edx, [ebx + ecx + mtab_partition_size]
	call	printhex8
	call	printspace

	# delegate. Need to load VBR, preferrably at mount time,
	# and set up the FATs and such there.

	stc
	
	pop	ecx
	pop	ebx
	
	jnc	3f

1:	printc 4, "no handler for FS node"
	stc
###
3:	
	ret


############################################################

# in: eax = pointer to path string
fs_opendir_OLD:
	push	ebp
	push	edi
	push	esi
	push	edx
	push	ecx
	push	ebx
	push	eax	# [ebp + 8]

	call	strdupn		# in: eax; out: eax, ecx
	push	eax	# [ebp + 4]
	mov	esi, eax

	mov	eax, ecx
	call	malloc
	push	eax	# [ebp]
	mov	ebp, esp

	printc 10, "opendir "
	call	println

	mov	edx, -1		# fs handle
	xor	ebx, ebx	# mtab handle

#########################################
0:	or	ecx, ecx
	jz	0f

	mov	edi, esi
	mov	al, '/'
	repne	scasb

	mov	eax, edi
	sub	eax, esi	# always at least 1

	mov	byte ptr [edi - 1], 0

	.if FS_DEBUG 
		pushcolor 4

		push	edx
		mov	edx, eax
		call	printdec32
		printchar ' '
		pop	edx

		color	11
		call	print

		popcolor
	.endif

	# copy path scanned so far

	push	edi
	push	esi
	push	ecx
	mov	ecx, edi
	sub	ecx, [ebp + 4]	# scan path
	dec	ecx		# remove trailing /
	mov	edi, [ebp]	# current path
	mov	esi, [ebp + 8]	# original path
	rep	movsb
	mov	byte ptr [edi], 0
	pop	ecx
	pop	esi
	pop	edi

	.if FS_DEBUG
		push	esi
		call	printspace
		printcharc 15, '<'
		mov	esi, [ebp]
		call	print
		printcharc 15, '>'
		pop	esi
	.endif


#########
	# ecx = total string left
	# esi = start of match
	# edi = end of match/start of rest of string to scan
	# eax = match length (edi-esi)
	# ebx = current directory handle

### check root
	dec	eax
	jnz	2f

	.if FS_DEBUG
		printc 13, " root "
	.endif

	call	fs_getroot$	# out: eax, edx
	jc	0f
	jmp	3f
### check subdir
2:	printc 13, " sub "
DEBUG "cur="
DEBUG_DWORD edx

	# check if we already have fs entry
	#push	edx
	mov	eax, [fs_root$]
#DEBUG_DWORD edx
#	mov	edx, [eax+edx+fs_node_parent]
DEBUG_DWORD edx
	call	fs_getentry
	jc	45f
	printc 15, "found entry: "
	jmp 46f
45:	printc 4, "not found: "
46:	call printhex8
	#pop	edx

## check mountpoint
1:	
	# first see if the current path is a mount point
	push	esi
	mov	esi, [ebp]

	push	ecx
	push	ebx
	call	mtab_find_mountpoint # in: esi; out: ebx+ecx
	jc	1f

	printc 11, "mountpoint"

	mov	esi, [ebx + ecx + mtab_mountpoint]

	call	fs_newnode	# in: esi; out: eax+edx
push edx
mov edx, ecx
printc 8, "fs.new node_data="
call printhex8
pop edx
	mov	[eax + edx + fs_node_data], ecx	# store mtab rel ptr
	mov	[eax + edx + fs_node_flags], byte ptr FS_NODE_FLAG_MTAB

.if 0 # works
	#####
	# test fs_getentry
	push	edx
	mov	edx, [eax+edx+fs_node_parent]
	call	fs_getentry
	jc 5f
	printc 15, "found entry: "
	jmp 6f
5:	printc 4, "not found: "
6:	call printhex8
	pop	edx
.endif

	#####

	clc

1:	pop	ebx
	pop	ecx

	pop	esi
	jnc	3f	
###
	call	fs_getentry
	jc	1f
	printc 13, "fs node "
	call	printhex8
	jmp	3f
###
1:	# the tree doesnt have the directory entry, so try to load
	# using filesystem handler:
	call newline
	printc 8, "delegate "
	printc 8, "flags "
	push edx
	mov dl, [eax+edx+fs_node_flags]
	call printhex2
	pop edx
	push edx
	printc 8, "node_data "
	mov edx, [eax+edx +fs_node_data]
	call printhex8
	call printspace
	pop edx
	test	byte ptr [eax + edx + fs_node_flags], FS_NODE_FLAG_MTAB
	jz	1f

	push	ebx
	push	ecx
	mov	ebx, [mtab]
DEBUG "mtab="
DEBUG_DWORD ebx
	add	ebx, [eax + edx + fs_node_data]
	# now use the mtab data to call the handler
	mov	dx, [ebx + mtab_disk]
	printc 8, "MTAB disk "
	call	printhex2
	printc 8, " partition "
	xchg	dl, dh
	call	printhex2
	printc 8, " fs "
	mov	dl, [ebx + mtab_fs]
	call	printhex2
	printc 8, " LBA "
	mov	edx, [ebx + mtab_partition_start]
	call	printhex8
	printc 8, " size "
	mov	edx, [ebx + mtab_partition_size]
	call	printhex8
	call	printspace

	# delegate. Need to load VBR, preferrably at mount time,
	# and set up the FATs and such there.

	stc
	
	pop	ecx
	pop	ebx
	
	jnc	3f

1:	printc 4, "no handler for FS node"
	jmp	2f
###
3:		call	newline
#########

	mov	esi, edi
	jmp	0b

#########################################

2:		call	newline
	printc 12, "directory not found: "
	mov	esi, [ebp]
	call	println
	stc
0:	.rept 2
	pop	eax
	pushf
	call	mfree
	popf
	.endr
	pop	eax
	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
	pop	edi
	pop	ebp
	ret


###############################################################################
# Utility functions


##############################################
# in: edi = current path / output
# in: esi = relative/new path
# out: edi points to end of the new path pointed to by edi.
# effect: applies the (relative or absolute) path in esi to edi.
fs_update_path:
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
		cmp	byte ptr [ebp], 0
		jz	1f
		pushcolor 13
		push	esi
		mov	esi, offset cd_cwd$
		call	println
		pop	esi
		popcolor
	1:

	mov	ebx, esi
	or	al, al
	jnz	0b
########
4:	ret


###############################################################################
