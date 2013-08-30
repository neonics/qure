##############################################################################
# Simple File System
.intel_syntax noprefix
.code32

SFS_DEBUG = 0

SFS_PARTITION_TYPE = 0x99	# or 69 or 96

SFS_MAGIC = ( 'S' | 'F' << 8 | 'S' << 16 | '0' << 24)

SFS_DIR_RESERVE	= 1024*1024 / 512	# 1 Mb

#############################################################################
DECLARE_CLASS_BEGIN fs_sfs, fs
sfs_disk:		.byte 0
sfs_partition:		.byte 0
sfs_partition_start_lba:.long 0, 0
sfs_partition_size_lba:	.long 0, 0
.align 4
sfs_blk0:		.space 512
sfs_buffer_lba:		.long 0
sfs_buffer_ptr:		.long 0
DECLARE_CLASS_METHOD fs_api_mount,	sfs_mount, OVERRIDE
DECLARE_CLASS_METHOD fs_api_umount,	sfs_umount, OVERRIDE
DECLARE_CLASS_METHOD fs_api_open,	sfs_open, OVERRIDE
DECLARE_CLASS_METHOD fs_api_close,	sfs_close, OVERRIDE
DECLARE_CLASS_METHOD fs_api_nextentry,	sfs_nextentry, OVERRIDE
DECLARE_CLASS_METHOD fs_api_read,	sfs_read, OVERRIDE
DECLARE_CLASS_END fs_sfs

###############################
# LBA: 32 bit * 512 bytes = 2 terabyte.
# LBA: 40 bit * 512 bytes = 512 terabyte
# LBA: 48 bit * 512 bytes = 128 petabyte
# LBA: 64 bit * 512 bytes = 8192 exabytes = 8 zettabytes = 0.008 yottabytes
#
# offsets in bytes:
# 32 bit = 4 Gb
# 40 bit = 1 Tb
# 48 bit = 256 Tb
# 64 bit = 16384 petabyte = 16 exabyte
.struct 0
sfs_vol_magic:		.long 0	# "SFS0"
sfs_vol_blocksize_bits:	.byte 0	# 9 - hardcoded 512 bytes
			.byte 0, 0, 0	# align
sfs_vol_size:		.long 0, 0
sfs_vol_directory_lba:	.long 0, 0	# LBA
sfs_vol_directory_size:	.long 0, 0	# sectors
sfs_vol_names_lba:	.long 0, 0
sfs_vol_names_size:	.long 0, 0
SFS_VOL_STRUCT_SIZE = 512

.struct 0
sfs_dir_file_posix_perm:.long 0		# POSIX permission flags (fits in word)
sfs_dir_file_posix_uid:	.long 0		# POSIX user id
sfs_dir_file_posix_gid:	.long 0		# POSIX group id
sfs_dir_file_lba:	.long 0, 0	# sectors
sfs_dir_file_size:	.long 0, 0	# bytes
sfs_dir_file_name_ptr:	.long 0
SFS_DIR_STRUCT_SIZE = 32

.text32
# in: ax = disk/partition
# in: esi = partition info
# out: edi = pointer to fs structure
#  edi - 512 = first partition sector
#  if num_entries > 30 (plus 2 for blk0 and blk1), then for each 32 more entries,
#  another sector will be available -512 bytes in mem.
#  edi grows in the + direction at half the size as it only maintains the
#  buffers - two mem pointers (malloced and aligned), 8 bytes, vs 16 bytes
#  for each entry.
sfs_mount:
	push	edx
	cmp	byte ptr [esi + PT_TYPE], SFS_PARTITION_TYPE
	stc
	jnz	9f

	push	eax
	mov	eax, offset class_fs_sfs
	call	class_newinstance
	mov	edi, eax
	pop	eax
	jc	9f

	mov	ebx, [esi + PT_SECTORS]
	mov	[edi + sfs_partition_size_lba], ebx
	mov	ebx, [esi + PT_LBA_START]
	mov	[edi + sfs_partition_start_lba], ebx

	.if SFS_DEBUG
		DEBUG_DWORD ebx,"LBA START"
	.endif
	push	edi
	mov	ecx, 1	# 1 sector
	add	edi, offset sfs_blk0
	call	ata_read
	pop	edi
	jc	9f

	cmp	[edi + sfs_blk0 + sfs_vol_magic], dword ptr SFS_MAGIC
	stc
	jnz	9f
	.if SFS_DEBUG
		DEBUG_DWORD edi, "instance"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_directory_lba], "DIR LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_directory_size], "DIR size"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_names_lba], "NAMES LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_names_size], "NAMES size"
	.endif

9:	pop	edx
	ret

# in: edi
sfs_umount:
	mov	eax, edi
	call	class_deleteinstance
	ret



# in: eax = class_sfs instance
# in: ebx = sector
# in: ecx = num sectors to load
# out: edi = blk buffer (loaded/filled)
sfs_load_blk:
	call	sfs_buffer_find
	jc	1f
	.if SFS_DEBUG
		DEBUG_DWORD ebx, "cache hit for sector"; DEBUG_DWORD edi
	.endif
	ret

1:	push	esi
	mov	esi, eax

	PTR_ARRAY_NEWENTRY [esi + sfs_buffer_lba], 16, 91f
	mov	[eax + edx], ebx
	PTR_ARRAY_NEWENTRY [esi + sfs_buffer_ptr], 16, 91f
	add	edx, eax
	mov	eax, ecx
	shl	eax, 9
	call	mallocz
	jc	91f
	mov	[edx], eax
	# ebx = sector
	push	ebx
	add	ebx, [esi + sfs_partition_start_lba]

	.if SFS_DEBUG
		DEBUG_DWORD ecx, "load sectors"; DEBUG_DWORD ebx, "LBA"
	.endif
	# ecx = num sectors
	mov	edi, eax
	mov	ax, [esi + sfs_disk]
	call	ata_read
	pop	ebx
	jc	92f

	.if SFS_DEBUG
		DEBUG "LOADED"
		call	newline
	.endif
	clc

0:	pop	esi
	ret

91:	printlnc 4, "sfs_load_blk malloc error"
	stc
	jmp	0b

92:	printlnc 4, "ata_read error"
	stc
	jmp	0b


# in: eax = class_sfs instance
# in: ebx = lba
# out: edi = buffer
sfs_buffer_find:
	.if SFS_DEBUG
		DEBUG "sfs_buffer_find"
		DEBUG_DWORD ebx
		call newline
	.endif

	or	ebx, ebx
	stc
	jnz	1f
	printlnc 4, "sfs_buffer_find: error: LBA 0"
	int 3
	ret
1:

	push_	ecx eax
	mov	edi, [eax + sfs_buffer_lba]
	or	edi, edi
	stc
	jz	9f

	mov	ecx, [edi + array_index]
	shr	ecx, 2
	xchg	eax, ebx
	repnz	scasd
	xchg	eax, ebx
	stc
.if SFS_DEBUG
	jnz	91f
.else
	jnz	9f
.endif
	sub	edi, 4
	sub	edi, [eax + sfs_buffer_lba]
	add	edi, [eax + sfs_buffer_ptr]
	mov	edi, [edi]
	.if SFS_DEBUG
		DEBUG "Found", 0xf0
		DEBUG_DWORD edi
		call newline
	.endif
	clc

9:	pop_	eax ecx
	ret

.if SFS_DEBUG
91:	DEBUG "Not found", 4
	jmp	9b
.endif


# in: eax = fs_instance structure
# in: ebx = parent dir handle, -1 for root
# in: esi = asciz dir/file name
# in: edi = fs dir entry struct (to be filled)
# out: ebx = dir handle
sfs_open:
	push	edx
	mov	edx, eax

	.if SFS_DEBUG
		DEBUG "sfs_open"
	.endif
	cmp	ebx, -1
	jnz	1f

	# root dir/file
	cmp	word ptr [esi], '/'
	jnz	2f
	# open root itself.
	mov	[edi + fs_dirent_posix_perm], dword ptr 0040755
	mov	[edi + fs_dirent_posix_uid], dword ptr 0
	mov	[edi + fs_dirent_posix_gid], dword ptr 0
	mov	[edi + fs_dirent_name], word ptr '/'
	mov	[edi + fs_dirent_size], dword ptr 0
	mov	[edi + fs_dirent_size+4], dword ptr 0

	# load directory
	push_	esi eax edx
	mov	ebx, [edx + sfs_blk0 + sfs_vol_directory_lba]
	mov	ecx, [edx + sfs_blk0 + sfs_vol_directory_size]
	add	ecx, 511
	shr	ecx, 9
	call	sfs_load_blk	# in: edx = class_sfs; out: eedi
	pop_	edx eax esi
	jc	9f

	# load names
	push	esi
	mov	ebx, [edx + sfs_blk0 + sfs_vol_names_lba]
	mov	ecx, [edx + sfs_blk0 + sfs_vol_names_size]
	add	ecx, 511
	shr	ecx, 9
	call	sfs_load_blk	# in: edx = class_sfs; out: eedi
	pop	esi
	jc	9f

	clc# ebx remains -1
	jmp	0f

1:	# not root
2:	# open a file/dir in the root dir.
	call	sfs_find_entry$

0:	pop	edx
	ret

9:	DEBUG "sfs_load_blk error"
	stc
	jmp	0b

sfs_close:
	.if SFS_DEBUG
		DEBUG "sfs_close"
	.endif
	ret

sfs_read:
	.if SFS_DEBUG
		DEBUG "sfs_read"
	.endif
	ret

# in: eax = fs instance
# in: ebx = dir handle
# in: ecx = cur entry
# in: edi = fs dir entry
# out: ecx = next entry, or -1
# out: edx = dir name (obsolete)
sfs_nextentry:
	push_	ebp edi esi edx eax
	mov	ebp, esp

	# find directories
	mov	ebx, [eax + sfs_blk0 + sfs_vol_directory_lba]
	push	edi
	call	sfs_buffer_find	# in: eax, ebx; out: edi
	mov	esi, edi
	pop	edi
	jc	91f

	# esi = directory

	# ecx = offset in buffer or 0 for start
	lea	esi, [esi + ecx]
	add	ecx, SFS_DIR_STRUCT_SIZE
	mov	edx, [esi + sfs_dir_file_posix_perm]
	or	edx, edx
	jz	1f

	mov	[edi + fs_dirent_posix_perm], edx # ptr 0x10
	mov	edx, [esi + sfs_dir_file_size]
	mov	[edi + fs_dirent_size], edx #dword ptr 0
	mov	[edi + fs_dirent_size+4], dword ptr 0

	# find name cache
	mov	ebx, [esi + sfs_dir_file_name_ptr]
	mov	edx, ebx
	# for now we'll use the offset in bytes (no 8 byte boundary)
	shr	ebx, 9	# convert to sector
	add	ebx, [eax + sfs_blk0 + sfs_vol_names_lba]
	push	edi
	call	sfs_buffer_find	# in: eax, ebx; out: edi
	# for now, the buffer will be contiguous and have all sectors:
	lea	esi, [edi + edx]
	pop	edi
	jc	91f
	# copy the name
	push_ esi edi ecx
	lea	edi, [edi + fs_dirent_name]
	call	strlen_
	cmp	ecx, 254
	jbe	2f
	mov	ecx, 254
2:	rep	movsb
	mov	[edi], cl
	pop_ ecx edi esi

	clc

0:	pop_	eax edx esi edi ebp
	ret

91:	printlnc 4, "sfs_nextentry: illegal call (no buffer)"
1:	mov	ecx, -1
	stc
	jmp	0b


sfs_find_entry$:
	DEBUG "sfs_find_entry"
	stc
	ret


#################################
# shell 'mkfs'
cmd_sfs_format:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	call	disk_parse_partition_label
	jc	9f
	call	disk_print_label
	print	": "
	call	sfs_format
	ret
9:	printlnc 4, "usage: mkfs <hdXY>"
	stc
	ret

# in: al = disk, ah = partition
sfs_format:
	call	disk_get_partition
	jc	9f

	cmp	[esi + PT_TYPE], byte ptr SFS_PARTITION_TYPE
	jnz	8f

	mov	edi, eax
	mov	eax, 512
	call	mallocz
	xchg	edi, eax
	jc	9f

	mov	edx, [esi + PT_SECTORS]
		print "Formatting "
		call	printdec32
		println " sectors"
	mov	[edi + sfs_vol_magic], dword ptr SFS_MAGIC
	mov	[edi + sfs_vol_blocksize_bits], byte ptr 9 # 512 byte sectors
	mov	[edi + sfs_vol_size + 0], edx
	mov	[edi + sfs_vol_size + 4], dword ptr 0
	mov	[edi + sfs_vol_directory_lba], dword ptr 1
	mov	[edi + sfs_vol_directory_size], dword ptr 1
	mov	[edi + sfs_vol_names_lba], dword ptr 1 + SFS_DIR_RESERVE
	mov	[edi + sfs_vol_names_size], dword ptr 1

	# write volume descriptor

	mov	ebx, [esi + PT_LBA_START]

		print "Partition LBA: "
		mov	edx, ebx
		call	printhex8

	push	esi
	mov	esi, edi
	mov	ecx, 1
	call	ata_write
	pop	esi
	jc	91f

	# write directory descriptor

	inc	ebx	# PT_LBA_START + sfs_vol_directory_lba(1) = 2

		print " Directory LBA: "
		mov	edx, ebx
		call	printhex8

	mov	ecx, 512 / 4
	push	eax	# remember drive/partition
	xor	eax, eax
	rep	stosd
	pop	eax
	sub	edi, 512
		# add a file...
		mov	[edi + sfs_dir_file_posix_perm], dword ptr 0140644
		mov	[edi + sfs_dir_file_posix_uid], dword ptr 0
		mov	[edi + sfs_dir_file_posix_gid], dword ptr 0
		mov	[edi + sfs_dir_file_lba], dword ptr 10
		mov	[edi + sfs_dir_file_size], dword ptr 303
		mov	[edi + sfs_dir_file_name_ptr], dword ptr 0	# first name
	push	esi
	mov	esi, edi
	inc	ecx	# ecx = 1
	call	ata_write
	pop	esi
	jc	91f

	# write name table

	push	esi
	mov	esi, edi
	mov	ecx, SFS_DIR_STRUCT_SIZE + 1
	push	eax	# remember drive/partition
	xor	eax, eax
	rep	stosd
	pop	eax
	mov	edi, esi
		# set the filename
		push_ esi edi
		LOAD_TXT "First Filename On SFS!"
		call	strlen_
		inc	ecx
		rep	movsb
		pop_ edi esi
	add	ebx, SFS_DIR_RESERVE
		print " Name table LBA: "
		mov	edx, ebx
		call	printhex8
		call	newline
	inc	ecx	# ecx = 1
	call	ata_write
	pop	esi


	printlnc 11, "Partition formatted."

9:	ret

91:	mov	eax, edi
	call	mfree
	printlnc 4, "sfs_format: ata_write error"
	stc
	ret

8:	printlnc 4, "sfs_format: partition not "
	push	edx
	mov	edx, SFS_PARTITION_TYPE
	call	printhex2
	pop	edx
	stc
	ret


