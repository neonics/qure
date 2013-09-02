##############################################################################
# Simple File System
.intel_syntax noprefix
.code32

SFS_DEBUG = 1

SFS_PARTITION_TYPE = 0x99	# or 69 or 96

SFS_MAGIC = ( 'S' | 'F' << 8 | 'S' << 16 | '0' << 24)

SFS_DIR_RESERVE	= 1024*1024 / 512	# 1 Mb
SFS_NAMES_RESERVE = 1024*512 / 512	# .5 Mb

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
DECLARE_CLASS_METHOD fs_api_create,	sfs_create, OVERRIDE
DECLARE_CLASS_METHOD fs_api_write,	sfs_write, OVERRIDE
DECLARE_CLASS_METHOD fs_api_delete,	sfs_delete, OVERRIDE
DECLARE_CLASS_METHOD fs_api_move,	sfs_move, OVERRIDE
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
.struct 0	# blk0:
sfs_vol_magic:		.long 0	# "SFS0"
sfs_vol_blocksize_bits:	.byte 0	# 9 - hardcoded 512 bytes
			.byte 0, 0, 0	# align
sfs_vol_size:		.long 0, 0
sfs_vol_blktab_lba:	.long 0, 0
sfs_vol_blktab_size:	.long 0, 0
sfs_vol_directory_lba:	.long 0, 0	# LBA
sfs_vol_directory_size:	.long 0, 0	# sectors
sfs_vol_names_lba:	.long 0, 0
sfs_vol_names_size:	.long 0, 0
sfs_vol_data_lba:	.long 0, 0	# freely allocatable start LBA
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

9:	pop	edx
	.if SFS_DEBUG
		DEBUG_DWORD edi, "instance"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_directory_lba], "DIR LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_directory_size], "DIR size"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_names_lba], "NAMES LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_names_size], "NAMES size"
	.endif

	ret

# in: edi
sfs_umount:
	mov	eax, edi
	call	class_deleteinstance
	ret



# in: eax = class_sfs instance
# in: ebx = sector
# in: ecx = bytes to load (rounded up to sectors)
# out: edi = blk buffer (loaded/filled)
sfs_load_blk:
	call	sfs_buffer_find
	jc	1f
	.if SFS_DEBUG > 1
		DEBUG_DWORD ebx, "cache hit for sector"; DEBUG_DWORD edi
	.endif
	ret

1:	push_	esi edx eax ecx
	mov	esi, eax

	PTR_ARRAY_NEWENTRY [esi + sfs_buffer_lba], 16, 91f
	mov	[eax + edx], ebx
	PTR_ARRAY_NEWENTRY [esi + sfs_buffer_ptr], 16, 91f
	add	edx, eax
	add	ecx, 511
	mov	eax, ecx
	and	eax, ~511
	push edx; mov edx, 4
	call	mallocz_aligned
	pop edx
	jc	91f
	mov	[edx], eax
	# ebx = sector
	push	ebx
	add	ebx, [esi + sfs_partition_start_lba]
	.if SFS_DEBUG > 1
		DEBUG_DWORD ecx, "load sectors"; DEBUG_DWORD ebx, "LBA"
	.endif
	shr	ecx, 9	# ecx = num sectors
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

0:	pop_	ecx eax edx esi
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
	.if SFS_DEBUG > 1
		DEBUG "sfs_buffer_find"
		DEBUG_DWORD ebx
#		call newline
	.endif

	or	ebx, ebx
	stc
	jnz	1f
	printlnc 4, "sfs_buffer_find: error: LBA 0"
	int 3
	stc
	ret
1:	push_	ecx eax
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
	.if SFS_DEBUG > 1
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


sfs_alloc_dir:
	mov	ecx, 512
# KEEP-WITH-NEXT: sfs_alloc_blk

# in: eax = sfs instance
# in: ecx = size in bytes
# out: ebx = lba
sfs_alloc_blk:
	mov	ebx, [eax + sfs_blk0+sfs_vol_blktab_lba]
	push_	ecx eax edx esi edi
	mov	ecx, [eax + sfs_blk0+sfs_vol_blktab_size]
	mov	edx, eax
	DEBUG_DWORD ecx, "blktab size"
	call	sfs_load_blk
	jc	91f
	mov	esi, edi
	# bitstring: 0=free, 1=allocated.
	# first bit: [eax+sfs_vol_data_lba]
	mov	eax, -1
	shr	ecx, 2
	DEBUG_DWORD edi,"start"
	dEBUG_DWORD [edi]
	DEBUG_DWORD ecx
	repz	scasd	# find a free sector
	jz	9f
	DEBUG_DWORD ecx
	DEBUG_DWORD edi
	DEBUG_DWORD esi
	sub	edi, 4
	mov	eax, [edi]	# find bit
	sub	edi, esi
	DEBUG_DWORD edi,"dw offs"
	# edi = byte index (dword aligned)
	shl	edi, 5-2
	DEBUG_DWORD edi

	mov	ebx, [edx + sfs_blk0 + sfs_vol_data_lba] # first

	# figure out first free sector in eax:
	not	eax		# bs[f/r] scans for 1, so invert
	DEBUG_DWORD eax
	bsf	ecx, eax	# ecx <- first bit 1 in eax
	# edx = bit index, 5bits range
	add	ebx, edi
	add	ebx, ecx
	DEBUG_DWORD ebx, "user LBA"
	DEBUG_DWORD ebx, "LBA"
	call	newline

	# TODO: write changed sector
	# figure out which sector:
	# mark used
	push	ebx	# return LBA
	mov	ebx, 1
	not	eax
	shl	ebx, cl
	or	eax, ebx
	DEBUG_DWORD eax
	shr	edi, 5-2
	DEBUG_DWORD edi,"dw offs"
	mov	[esi + edi], eax

	# write sector containing the bit
	mov	ebx, edi
	shr	ebx, 9		# rel sector to blktab_lba
	and	edi, ~511
	add	esi, edi
	mov	ecx, 1
	mov	eax, edx
	add	ebx, [eax + sfs_blk0 + sfs_vol_blktab_lba]
	DEBUG "write blk"
	DEBUG_DWORD ebx
	call	sfs_write_blk
	pop	ebx		# pushed as buf, swapped: pop LBA

0:	pop_	edi esi edx eax ecx
	ret
9:	printlnc 4, "partition full"
	stc
	jmp	0b
91:	printlnc 4, "load_blk error"
	stc
	jmp	9b


	

# in: eax = sfs instance
# in: ebx = lba
# in: esi = buffer
# in: ecx = bytes
sfs_write_blk:
	push_	ebx eax
	add	ecx, 511
	add	ebx, [eax + sfs_partition_start_lba]
	shr	ecx, 9
	mov	ax, [eax + sfs_disk]
	call	ata_write
	pop_	eax ebx
	ret

# in: eax = sfs instance
sfs_write_blk0$:
	push_	eax ebx ecx esi
	lea	esi, [eax + sfs_blk0]
	mov	ecx, 512
	xor	ebx, ebx
	call	sfs_write_blk
	pop_	esi ecx ebx eax
	ret


# in: eax = sfs instance
sfs_write_vol_dir$:
	push_	eax ebx ecx esi edi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_directory_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_directory_size]
	call	sfs_load_blk
	jc	9f
	mov	esi, edi
	call	sfs_write_blk
9:	pop_	edi esi ecx ebx eax
	ret


# in: eax = sfs instance
sfs_write_vol_names$:
	push_	eax ebx ecx esi edi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_names_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_names_size]
	call	sfs_load_blk
	jc	9f
	mov	esi, edi
	call	sfs_write_blk
9:	pop_	edi esi ecx ebx eax
	ret



# in: eax = fs_instance structure
# in: ebx = parent dir handle, -1 for root
# in: esi = asciz dir/file name
# in: edi = fs dir entry struct (to be filled)
# out: ebx = dir handle
sfs_open:
	push_	edi edx
	mov	edx, eax

	.if SFS_DEBUG
		DEBUG "sfs_open"
		DEBUG_DWORD ebx
		DEBUGS esi
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
	.if SFS_DEBUG
		DEBUG "load dir"
	.endif
	push_	esi eax edx
	mov	ebx, [eax + sfs_blk0 + sfs_vol_directory_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_directory_size]
	DEBUG_DWORD ebx,"dir lba"
	call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
	pop_	edx eax esi
	jc	9f

	# load names
	.if SFS_DEBUG
		DEBUG "load names"
	.endif
	push_	ebx esi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_names_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_names_size]
	call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
	pop_	esi ebx
	jc	9f

	clc# ebx remains -1
	jmp	0f

1:	# not root
2:	# open a file/dir in the root dir.
	call	sfs_find_entry$

0:	pop_	edx edi
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

sfs_delete:
sfs_move:
	stc
	ret

# in: eax = sfs_instance structure
# in: ebx = parent dir handle, -1 for root
# in: edi = fs dir entry struct (already filled)
# out: ebx = dir handle
sfs_create:

	.if SFS_DEBUG
		DEBUG "sfs_create"
		DEBUG_DWORD eax,"SFS",0xe0
		DEBUG_DWORD ebx,"parent LBA"
		push	esi
		lea	esi, [edi + fs_dirent_name]
		DEBUGS esi
		pop	esi
		call	newline
	.endif

	push_	ebx esi ecx edx
	mov	edx, edi	# fs_dirent

########
	push	edi

	mov	ecx, 1		# at least 1 byte
	call	sfs_load_blk	# in: eax=inst, ebx=dir, ecx=nsect; out: edi
	jc	9f

	# edi = dir blk
	lea	ecx, [edi + 512]	# max offs
0:	cmpd	[edi + sfs_dir_file_posix_perm], 0
	jz	1f	# found
	add	edi, SFS_DIR_STRUCT_SIZE
	cmp	edi, ecx
	jb	0b
	printc 4, "dir sector exhausted"
	int 3

1:	# found empty entry
	# copy info from fs_dirent
	mov	ecx, [edx + fs_dirent_posix_perm]
	mov	[edi + sfs_dir_file_posix_perm], ecx #dword ptr 0100644	#10: file
	mov	ecx, [edx + fs_dirent_posix_uid]
	mov	[edi + sfs_dir_file_posix_uid], ecx#dword ptr 0
	mov	ecx, [edx + fs_dirent_posix_uid]
	mov	[edi + sfs_dir_file_posix_gid], ecx#dword ptr 0

	mov	[edi + sfs_dir_file_lba], dword ptr -1
	mov	[edi + sfs_dir_file_size], dword ptr 0
	mov	[edi + sfs_dir_file_name_ptr], dword ptr 0	# first name

		push_	edi ebx
		# load names
		mov	ebx, [eax + sfs_blk0 + sfs_vol_names_lba]
		mov	ecx, [eax + sfs_blk0 + sfs_vol_names_size]
		DEBUG_DWORD ecx,"nametab size"
		call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
		jc	1f
		# append name
		mov	edx, ecx
		call	strlen_	# esi->ecx
		inc	ecx
		lea	ebx, [edx + ecx]
		DEBUG_DWORD ebx,"nametab size"
		cmp	ebx, 512	# sector limit
		jb	2f
		printc 4, "sfs: name table exhausted"
		DEBUG_DWORD ebx
		DEBUG_DWORD edx
		DEBUG_DWORD ecx
		int 3

	2:	add	edi, edx	# name ptr
		push	ecx
		rep	movsb
		pop	ecx
		clc
	1:	pop_	ebx edi
		jc	91f

	mov	esi, edi
	mov	[edi + sfs_dir_file_name_ptr], edx

	# update blk0
	DEBUG "write blk0"
	add	[eax + sfs_blk0 + sfs_vol_names_size], ecx
	call	sfs_write_blk0$
	jc	92f

	# update nametable
	DEBUG "write names"
	call	sfs_write_vol_names$
	jc	92f

	# update directory sector
	DEBUG "write dir"
	call	sfs_write_vol_dir$
	jc	92f

	mov	ecx, [edi + sfs_dir_file_posix_perm]
	and	ecx, POSIX_TYPE_MASK
	cmp	ecx, POSIX_TYPE_DIR 
	jnz	1f
	# is a dir, so allocate LBA

	sub	esp, 512
	push	edi
	lea	edi, [esp + 4]
	mov	ecx, 512/4
	push	eax
	xor	eax, eax
	rep	stosd
	pop	eax
	call	sfs_alloc_dir	# in: eax; out: ebx=lba
	pop	edi
	mov	[edi + sfs_dir_file_lba], ebx
	mov	[edi + sfs_dir_file_size], ebx
	mov	esi, esp
	call	sfs_write_blk
	add	esp, 512

	call	sfs_write_vol_dir$
1:
	call newline

	pop	edi
########
	# fill fs dir entry
	call	sfs_fill_dir$	# in: esi=sfs_dir, edx=name, edi=fs_dirent
	clc
0:	pop_	edx ecx esi ebx
	ret

9:	printlnc 4, "sfs_create: illegal parent blk"
9:	stc
	pop	edi
	jmp	0b
91:	printlnc 4, "sfs_create: error loading name table"
	jmp	9b
92:	printlnc 4, "sfs_create: error writing blk0"
	jmp	9b



# in: esi = sfs_dir_file* entry
# in: edx = entry name
# in: edi = fs_dirent *
sfs_fill_dir$:
	push	eax

	push_	esi edi
	add	esi, offset sfs_dir_file_posix_perm
	add	edi, offset fs_dirent_posix_perm
	movsd
	movsd
	movsd
	pop_	edi esi

	push_	esi edi
	add	esi, offset sfs_dir_file_size
	add	edi, offset fs_dirent_size
	movsd
	movsd
	pop_	edi esi

	push_	edi esi ecx
	mov	esi, edx	# name
	lea	edi, [edi + fs_dirent_name]
	mov	ecx, FS_DIRENT_MAX_NAME_LEN
	rep	movsb
	pop_	ecx esi edi

	pop	eax
	ret

# in: eax = sfs instance
# in: esi = sfs_dir_file struct ptr
sfs_resolve_name$:
	ret


sfs_write:
	.if SFS_DEBUG
		DEBUG "sfs_write"
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
	push	ebp
	mov	ebp, esp
	# allocate a zero stackbuffer
	sub	esp, 512
	push_	edi eax
	xor	eax, eax
	lea	edi, [esp + 8]
	mov	ecx, 512/4
	rep	stosd
	pop_	eax edi

	call	disk_get_partition
	jc	91f

	cmp	[esi + PT_TYPE], byte ptr SFS_PARTITION_TYPE
	jnz	92f

	# allocate blk0: volume descriptor
	mov	edi, eax
	mov	eax, 512
	call	mallocz
	xchg	edi, eax
	jc	93f

	mov	edx, [esi + PT_SECTORS]
		print "Formatting "
		call	printdec32
		println " sectors"
	DEBUG_DWORD edi
	mov	[edi + sfs_vol_magic], dword ptr SFS_MAGIC
	mov	[edi + sfs_vol_blocksize_bits], byte ptr 9 # 512 byte sectors
	mov	[edi + sfs_vol_size + 0], edx
	mov	[edi + sfs_vol_size + 4], dword ptr 0

	DEBUG_DWORD edx, "vol_size"
	mov	[edi + sfs_vol_blktab_lba], dword ptr 1
	shr	edx, 8	# bits->bytes; 
	DEBUG_DWORD edx,"blktab_size"
	mov	[edi + sfs_vol_blktab_size], edx
	add	edx, 511
	shr	edx, 9	# bytes->sectors
	inc	edx	# +blktab_lba
	DEBUG_DWORD edx, "vol_dir_lba"
	mov	[edi + sfs_vol_directory_lba], edx
	mov	[edi + sfs_vol_directory_size], dword ptr 1
	add	edx, SFS_DIR_RESERVE
	DEBUG_DWORD edx, "vol_names_lba"
	mov	[edi + sfs_vol_names_lba], edx
	mov	[edi + sfs_vol_names_size], dword ptr 1
	add	edx, SFS_NAMES_RESERVE
	DEBUG_DWORD edx, "vol_data_lba"
	mov	[edi + sfs_vol_data_lba], edx


	#########################
	# write volume descriptor

	mov	ebx, [esi + PT_LBA_START]

		print "Partition LBA: "
		mov	edx, ebx
		call	printhex8
		call	newline

	push	esi
	mov	esi, edi
	mov	ecx, 1
	call	ata_write
	pop	esi
	jc	94f


	#########################################
	# write sfs_vol_blktab: sector allocation

		mov	edx, [edi + sfs_vol_blktab_lba]
		print " BLKTAB LBA: "
		call	printhex8
		call	newline

	DEBUG_DWORD edi
	# write the empty sectors
	mov	ebx, [edi + sfs_vol_blktab_lba]
	add	ebx, [esi + PT_LBA_START]
	mov	ecx, [edi + sfs_vol_blktab_size]
	shr	ecx, 9
	
0:	push_	ecx esi
	lea	esi, [esp + 8]
	mov	ecx, 1
	call	ata_write
	pop_	esi ecx
	jc	94f
	inc	ebx
	loop	0b


	############################
	# write directory descriptor

	mov	ebx, [edi + sfs_vol_directory_lba]
		print " Directory LBA: "
		mov	edx, ebx
		call	printhex8
		call	newline
	add	ebx, [esi + PT_LBA_START]

	push	edi
	lea	edi, [esp+4]
	mov	ecx, 512 / 4
	push	eax	# remember drive/partition
	xor	eax, eax
	rep	stosd
	pop	eax
	sub	edi, 512
	.if 0
		# add a file...
		mov	[edi + sfs_dir_file_posix_perm], dword ptr 0140644
		mov	[edi + sfs_dir_file_posix_uid], dword ptr 0
		mov	[edi + sfs_dir_file_posix_gid], dword ptr 0
		mov	[edi + sfs_dir_file_lba], dword ptr 10
		mov	[edi + sfs_dir_file_size], dword ptr 303
		mov	[edi + sfs_dir_file_name_ptr], dword ptr 0	# first name
	.endif
	push	esi
	mov	esi, edi
	inc	ecx	# ecx = 1
	call	ata_write
	pop	esi
	pop	edi
	jc	94f

	# write name table

	mov	ebx, [edi + sfs_vol_names_lba]
		add	ebx, SFS_DIR_RESERVE
		print " Name table LBA: "
		mov	edx, ebx
		call	printhex8
		call	newline
	add	ebx, [esi + PT_LBA_START]

	push_	edi esi
	lea	edi, [esp+8]
	mov	esi, edi
	mov	ecx, SFS_DIR_STRUCT_SIZE + 1
	push	eax	# remember drive/partition
	xor	eax, eax
	rep	stosd
	pop	eax
	mov	edi, esi
	.if 0
		# set the filename
		push_ esi edi
		LOAD_TXT "First Filename On SFS!"
		call	strlen_
		inc	ecx
		rep	movsb
		pop_ edi esi
	.endif
	inc	ecx	# ecx = 1
	call	ata_write
	pop_	esi edi
	jc	94f

		mov	edx, [edi + sfs_vol_data_lba]
		print " Free data LBA: "
		call	printhex8
		call	newline

	printlnc 11, "Partition formatted."

	clc

8:	pushf
	mov	eax, edi
	call	mfree
	popf
9:	mov	esp, ebp
	pop	ebp
	ret

91:	call	0f
	printlnc 4, "error reading partition table"
	stc
	jmp	9b

92:	call	0f
	printc 4, "partition not "
	push	edx
	mov	edx, SFS_PARTITION_TYPE
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
	printlnc 4, "ata_write error"
	stc
	jmp	8b

0:	printc 4, "sfs_format: "
	ret

