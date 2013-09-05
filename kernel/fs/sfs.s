##############################################################################
# Simple File System
.intel_syntax noprefix
.code32

SFS_VERBOSE = 1
SFS_DEBUG = 1
SFS_DEBUG_ATA = 0


SFS_PARTITION_TYPE = 0x99	# or 69 or 96

SFS_MAGIC = ( 'S' | 'F' << 8 | 'S' << 16 | '0' << 24)

# in bytes
SFS_DIR_RESERVE		= 4096
SFS_NAMES_RESERVE	= 4096

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
# static
DECLARE_CLASS_METHOD fs_api_mkfs,	sfs_format, OVERRIDE
DECLARE_CLASS_METHOD fs_api_mount,	sfs_mount, OVERRIDE
DECLARE_CLASS_METHOD fs_api_umount,	sfs_umount, OVERRIDE
# instance
DECLARE_CLASS_METHOD fs_api_open,	sfs_open, OVERRIDE
DECLARE_CLASS_METHOD fs_api_close,	sfs_close, OVERRIDE
DECLARE_CLASS_METHOD fs_api_nextentry,	sfs_nextentry, OVERRIDE
DECLARE_CLASS_METHOD fs_api_read,	sfs_read, OVERRIDE
DECLARE_CLASS_METHOD fs_api_create,	sfs_create, OVERRIDE
DECLARE_CLASS_METHOD fs_api_write,	sfs_write, OVERRIDE
DECLARE_CLASS_METHOD fs_api_delete,	sfs_delete, OVERRIDE
DECLARE_CLASS_METHOD fs_api_move,	sfs_move, OVERRIDE
DECLARE_CLASS_END fs_sfs




.struct 0	# table structure
tbl_lba:	.long 0,0
tbl_size:	.long 0,0	# bytes
tbl_reserve:	.long 0,0	# bytes
tbl_mem:	.long 0		# runtime: memptr; disk: reserved.
tbl_RESERVED:	.long 0
TBL_STRUCT_SIZE = .	# 32

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
sfs_vol_size:		.long 0, 0	# entire size
sfs_vol_data_lba:	.long 0, 0	# freely allocatable start LBA

sfs_vol_tables_lba:	.long 0, 0
sfs_vol_numtbl:		.long 0
sfs_vol_tbl:
# NOTE: the following sequence is hardcoded in sfs_format.
sfs_vol_tbl_blktab:	.space TBL_STRUCT_SIZE
sfs_vol_tbl_names:	.space TBL_STRUCT_SIZE
sfs_vol_tbl_dir:	.space TBL_STRUCT_SIZE
SFS_VOL_STRUCT_SIZE = 512

.struct 0
sfs_dir_file_posix_perm:.long 0		# POSIX permission flags (fits in word)
sfs_dir_file_posix_uid:	.long 0		# POSIX user id
sfs_dir_file_posix_gid:	.long 0		# POSIX group id
sfs_dir_file_lba:	.long 0, 0	# sectors
sfs_dir_file_size:	.long 0, 0	# bytes
sfs_dir_file_name_ptr:	.long 0
SFS_DIR_STRUCT_SIZE = 32

.struct 0
sfs_table_name:		.space 12
sfs_table_type:		.long 0
sfs_table_start_lba:	.long 0, 0
sfs_table_end_lba:	.long 0, 0
SFS_TABLE_STRUCT_SIZE = .	# 32

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
	jc	91f

	mov	ebx, [esi + PT_SECTORS]
	mov	[edi + sfs_partition_size_lba], ebx
	mov	ebx, [esi + PT_LBA_START]
	mov	[edi + sfs_partition_start_lba], ebx

	.if SFS_VERBOSE
		push	edx
		printc 11, "sfs LBA "
		mov	edx, ebx
		call	printhex8
		pop	edx
	.elseif SFS_DEBUG
		DEBUG_DWORD ebx,"LBA START"
	.endif

	push	edi
	mov	ecx, 1	# 1 sector
	add	edi, offset sfs_blk0
	call	ata_read
	pop	edi
	jc	92f

	cmp	[edi + sfs_blk0 + sfs_vol_magic], dword ptr SFS_MAGIC
	jnz	93f

	cmp	[edi + sfs_blk0 + sfs_vol_numtbl], dword ptr 0
	jz	94f

	.if SFS_VERBOSE

		mov	edx, [edi + sfs_blk0 + sfs_vol_size]
		print	" size: "
		call	printhex8
		print	" sectors. "
	.endif

	# print tables

	push_	ecx esi edi eax
	mov	ecx, [edi + sfs_blk0 + sfs_vol_numtbl]

	.if SFS_VERBOSE
		mov	edx, ecx
		call	printdec32
		println " tables:"
	.endif

	lea	esi, [edi + sfs_blk0 + sfs_vol_tbl]
0:
	.if SFS_VERBOSE
		mov	edx, [edi + sfs_blk0 + sfs_vol_numtbl]
		sub	edx, ecx
		call	printdec32
		print ": LBA: "
		mov	edx, [esi + tbl_lba]
		call	printhex8
		print " size: "
		mov	edx, [esi + tbl_size]
		call	printhex8
		printchar '/'
		mov	edx, [esi + tbl_reserve]
		call	printhex8
	.endif

	mov	eax, edi

	push_	edi ecx
	mov	ebx, [esi + tbl_lba]
	mov	ecx, [esi + tbl_size]
	mov	[esi + tbl_mem], dword ptr 0
	jecxz	1f
	call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
	mov	[esi + tbl_mem], edi
1:	pop_	ecx edi
	jc	2f

	printc 10, "Ok"

	.if SFS_VERBOSE
		call	newline
	.endif

	add	esi, TBL_STRUCT_SIZE
	loop	0b

2:	pop_	eax edi esi ecx
	jc	95f

	.if SFS_DEBUG
		.irp n,blktab,names,dir
		DEBUG "\n"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_\n\() + tbl_lba],"LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_\n\() + tbl_size],"size"
		call newline
		.endr
	.endif

	.if SFS_DEBUG > 1
		DEBUG_DWORD edi, "instance"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_dir+tbl_lba], "DIR LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_dir+tbl_size], "DIR size"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_names+tbl_lba], "NAMES LBA"
		DEBUG_DWORD [edi + sfs_blk0 + sfs_vol_tbl_names+tbl_size], "NAMES size"
	.endif

	clc
9:	pop	edx
	ret

0:	mov	eax, edi
	call	class_deleteinstance
	mov	edi, -1
	stc
	jmp	9b
91:	printlnc 4, " cannot instantiate object"
	stc
	jmp	9b
92:	printlnc 4, " ata error"
	stc
	jmp	9b
93:	printlnc 4, " signature error"
	jmp	0b
94:	printlnc 4, " no tables"
	jmp	0b
95:	printlnc 4, "table corrupt"
	jmp	0b

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

.if SFS_DEBUG > 1
	call	newline
	DEBUG_DWORD eax
	DEBUG_DWORD ebx,"load_blk"
	DEBUG_DWORD ecx
.endif

	call	sfs_buffer_find
	jc	1f
	.if SFS_DEBUG > 1
		DEBUG_DWORD ebx, "cache hit for sector"; DEBUG_DWORD edi
	.endif
	ret

1:	push_	esi edx eax ecx
	mov	esi, eax

	cmp	ebx, [esi + sfs_partition_size_lba]
	jae	93f

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
	shr	ecx, 9	# ecx = num sectors
	.if 1#SFS_DEBUG > 1
		DEBUG_DWORD ecx, "load sectors"; DEBUG_DWORD ebx, "pLBA"
	.endif


	add	ebx, [esi + sfs_partition_start_lba]
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

91:	printlnc 4, "sfs_load_blk: malloc error"
	stc
	jmp	0b

92:	printlnc 4, "sfs_load_blk: ata_read error"
	stc
	jmp	0b

93:	printc 4, "sfs_load_blk: sector not in partition: "
	mov	edx, ebx
	call	printhex8
	call	newline
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
91:	DEBUG "Not found", 0x94
	jmp	9b
.endif


sfs_alloc_dir_OLD:
	mov	ecx, 512
# KEEP-WITH-NEXT: sfs_alloc_blk
# in: eax = sfs instance
# in: ecx = size in bytes
# out: ebx = lba
sfs_alloc_blk_OLD:
	DEBUG "sfs_alloc_blk"
	push_	ebp eax edx esi edi ecx
	mov	ebp, esp
	mov	ebx, [eax + sfs_blk0+sfs_vol_tbl_blktab + tbl_lba]#blktab_lba]
	mov	ecx, [eax + sfs_blk0+sfs_vol_tbl_blktab + tbl_size]#blktab_size]
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
	add	ebx, [eax + sfs_blk0 + sfs_vol_tbl_blktab + tbl_lba]#blktab_lba]
	call	sfs_write_blk
	pop	ebx		# pushed as buf, swapped: pop LBA

0:	pop_	ecx edi esi edx eax ebp
	ret
9:	call	0f
	printlnc 4, "partition full"
	stc
	jmp	0b
91:	call	0f
	printlnc 4, "load_blk error"
	stc
	jmp	0b
0:	printc 4, "sfs_alloc_blk: "
	ret




# in: eax = sfs instance
# in: ebx = lba (relative to partition start)
# in: esi = buffer
# in: ecx = bytes
sfs_write_blk:
	push_	ebx eax
	add	ecx, 511
	add	ebx, [eax + sfs_partition_start_lba]
	shr	ecx, 9
	mov	ax, [eax + sfs_disk]
.if SFS_DEBUG_ATA
	DEBUG "write_blk"
	DEBUG_WORD ax
	DEBUG_DWORD ebx
	DEBUG_DWORD esi
	DEBUG_DWORD ecx
	push edx
	mov edx, [esp + 12]
	call debug_printsymbol
	pop edx
.endif
	call	ata_write
	pop_	eax ebx
	ret

# in: eax = sfs instance
sfs_write_blk0$:
	push_	eax ebx ecx esi
	lea	esi, [eax + sfs_blk0]
	mov	ecx, 512
	xor	ebx, ebx
	.if SFS_DEBUG; DEBUG "write blk0"; .endif
	call	sfs_write_blk
	pop_	esi ecx ebx eax
	ret


# in: eax = sfs instance
sfs_write_vol_dir$:
	push_	eax ebx ecx esi edi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_dir + tbl_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_tbl_dir + tbl_size]
	.if SFS_DEBUG; DEBUG "write dir"; .endif
	call	sfs_load_blk	# get from cache
	jc	9f
	mov	esi, edi
	call	sfs_write_blk
9:	pop_	edi esi ecx ebx eax
	ret


# in: eax = sfs instance
sfs_write_vol_names$:
	push_	eax ebx ecx esi edi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size]
	.if SFS_DEBUG
		DEBUG "write names"
		DEBUG_DWORD ebx
		DEBUG_DWORD ecx
	.endif
	call	sfs_load_blk
	jc	9f
	.if SFS_DEBUG
		DEBUG_DWORD edi
	.endif
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
	.if 1	# check for special commands
		cmp	byte ptr [esi], '?'
		jz	sfs_backdoor
	.endif

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
	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_dir + tbl_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_tbl_dir + tbl_size]
	DEBUG_DWORD ebx,"dir lba"
	call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
	pop_	edx eax esi
	jc	9f

	# load names
	.if SFS_DEBUG
		DEBUG "load names"
	.endif
	push_	ebx esi
	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size]
	call	sfs_load_blk	# in: eax, ebx, ecx; out: edi
	pop_	esi ebx
	jc	9f

	clc# ebx remains -1
	jmp	0f

1:	# not root
2:	# open a file/dir in the root dir.
	call	sfs_find_entry$

0:	pop_	edx edi
	.if SFS_DEBUG
		pushf;call newline;popf
	.endif
	ret

9:	DEBUG "sfs_load_blk error"
	stc
	jmp	0b

sfs_close:
	.if SFS_DEBUG
		DEBUG "sfs_close"
		push	esi
		lea	esi, [edi + fs_dirent_name]
		DEBUGS esi
		pop	esi
		call	newline
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

	push_	ebp eax esi ecx edx edi ebx
	mov	ebp, esp
	sub	esp, 8
	# [ebp] = ebx
	# [ebp-4] = edi for ebx
	# [ebp+4] = fs_dirent

	mov	edx, edi	# fs_dirent

########
	call	sfs_tbl_dir_insert	# in: eax; out: ebx=id, edi=entry in parent
	mov	[ebp - 4], edi

	mov	[edi + sfs_dir_file_lba], ebx
	mov	[edi + sfs_dir_file_size], dword ptr 0

	# copy info from fs_dirent
	mov	ecx, [edx + fs_dirent_posix_perm]
	mov	[edi + sfs_dir_file_posix_perm], ecx #dword ptr 0100644	#10: file
	mov	ecx, [edx + fs_dirent_posix_uid]
	mov	[edi + sfs_dir_file_posix_uid], ecx#dword ptr 0
	mov	ecx, [edx + fs_dirent_posix_uid]
	mov	[edi + sfs_dir_file_posix_gid], ecx#dword ptr 0

	mov	[edi + sfs_dir_file_lba], dword ptr -1
	mov	[edi + sfs_dir_file_size], dword ptr 0
	call	sfs_tbl_names_append	# in: eax, esi, ecx; out: edx
	mov	[edi + sfs_dir_file_name_ptr], esi
	jc	91f

	mov	esi, edi

	# update blk0
	add	[eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size], ecx
	call	sfs_write_blk0$
	jc	92f

	# update nametable
	call	sfs_write_vol_names$
	jc	92f

	# update directory sector
	#call	sfs_write_vol_dir$
	push_	ebx esi
	mov	ebx, [ebp]	# parent LBA
	mov	esi, [ebp -4]	# parent buffer
	mov	ecx, 512
	call	sfs_write_blk
	pop_	esi ebx
	jc	92f

	mov	ecx, [edi + sfs_dir_file_posix_perm]
	and	ecx, POSIX_TYPE_MASK
	cmp	ecx, POSIX_TYPE_DIR 
	jnz	1f
	# is a dir, so allocate LBA

	DEBUG "clearing DIR", 0xe0

	sub	esp, 512
	push	edi
	lea	edi, [esp + 4]
	mov	ecx, 512/4
	push	eax
	xor	eax, eax
	rep	stosd
	pop	eax
	pop	edi
	mov	esi, esp
	call	sfs_write_blk
	add	esp, 512

	call	sfs_write_vol_dir$
1:
	call newline
########
	# fill fs dir entry
	mov	edi, [ebp + 4]
	call	sfs_fill_dir$	# in: esi=sfs_dir, edx=name, edi=fs_dirent
	clc
0:	mov	esp, ebp
	pop_	ebx edi edx ecx esi eax ebp
	ret

9:	printlnc 4, "sfs_create: illegal parent blk"
9:	stc
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
# in: edx = sfs_dir_file_name_ptr value
# out: edx = name
sfs_resolve_name$:
	push_	ebx edi

	# for now we'll use the offset in bytes (no 8 byte boundary)
	mov	ebx, edx
	shr	ebx, 9	# convert to sector
	add	ebx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_lba]
	push	ecx
	mov	ecx, 512
	call	sfs_load_blk	# in: eax, ebx; out: edi
	pop	ecx
	jc	91f
	# for now, the buffer will be contiguous and have all sectors:
	and	edx, 0b111111111
	lea	edx, [edi + edx]

0:	pop_	edi ebx
	ret

91:	printc 4, "sfs_resolve_name$: can't find sector "
	mov	edx, ebx
	call	printhex8
	call	newline
	stc
	jmp	0b


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
#	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_dir + tbl_lba]
	push_	edi ecx
	mov	ecx, 512
	call	sfs_load_blk	# in: eax, ebx; out: edi
	mov	esi, edi
	pop_	ecx edi
	jc	91f

	# esi = directory

	# ecx = offset in buffer or 0 for start
	lea	esi, [esi + ecx]
	add	ecx, SFS_DIR_STRUCT_SIZE
	mov	edx, [esi + sfs_dir_file_posix_perm]
	or	edx, edx
	jz	1f
	DEBUG "entry"

	mov	[edi + fs_dirent_posix_perm], edx # ptr 0x10
	mov	edx, [esi + sfs_dir_file_size]
	mov	[edi + fs_dirent_size], edx #dword ptr 0
	mov	[edi + fs_dirent_size+4], dword ptr 0

	# find name cache
	mov	edx, [esi + sfs_dir_file_name_ptr]
	call	sfs_resolve_name$	# in: eax, edx; out: edx
	jc	92f

	# copy the name
	push_	esi edi ecx
	mov	esi, edx
	lea	edi, [edi + fs_dirent_name]
	call	strlen_
	cmp	ecx, 254
	jbe	2f
	mov	ecx, 254
2:	rep	movsb
	mov	[edi], cl
	pop_	ecx edi esi

	clc

0:	pop_	eax edx esi edi ebp
	ret

92:	printlnc 4, "sfs_nextentry: name resolution error"
	jmp	1f
91:	printlnc 4, "sfs_nextentry: illegal call (no buffer)"
1:	mov	ecx, -1
	stc
	jmp	0b

# in: eax = sfs instance
# in: ebx = parent dir handle, -1 for root
# in: esi = asciz dir/file name
# in: edi = fs dir entry struct (to be filled)
# out: ebx = dir handle
sfs_find_entry$:
	push_	eax ecx esi edx edi
	DEBUG "sfs_find_entry"
	DEBUG_DWORD ebx
	DEBUGS esi

	# load directory (should be cached)
	mov	ecx, 512
	call	sfs_load_blk	# out: edi
	jc	8f

	call	strlen_		# esi->ecx

	# iterate through the entries
	xor	ebx, ebx	# offset
0:	cmp	dword ptr [edi + ebx + sfs_dir_file_posix_perm], 0
	jz	8f	# reached end, not found

	mov	edx, [edi + ebx + sfs_dir_file_name_ptr]
	call	sfs_resolve_name$	# in: eax,edx; out: edx
	jc	9f		# error resolving name

	push_	esi edi ecx
	mov	edi, edx
	repz	cmpsb
	pop_	ecx edi esi
	jz	1f		# match

	add	ebx, SFS_DIR_STRUCT_SIZE
	cmp	ebx, 512
	jb	0b

8:	stc

9:	pop_	edi edx esi ecx eax
	ret

1:	lea	esi, [edi + ebx]
	mov	ebx, [edi + ebx + sfs_dir_file_lba]
	mov	edi, [esp]
	call	sfs_fill_dir$	# in: esi=sfs_dir, edx=name, edi=fs_dirent
	clc
	jmp	9b


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
	push	eax
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

	mov	ebx, eax
	mov	eax, offset class_fs_sfs
	call	class_newinstance
	jc	93f

	call	sfs_format_init$
	jc	93f

	# this sequence matches hardcoded structure elements in sfs_vol_blk_*

	call	sfs_format_init_blktab$
	jc	94f

	call	sfs_format_init_names$
	jc	94f

	call	sfs_format_init_dir$
	jc	94f
	#########################
	# write volume descriptor

	printc 11, " * volume descriptor"
	call	sfs_write_blk0$
	jc	94f

	OK

	printlnc 11, "Partition formatted."

	clc

8:	pushf
	call	class_deleteinstance	# free sfs instance
	popf
9:	mov	esp, ebp
	pop	ebp
	pop	eax
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

# in: eax = sfs instance
# in: bx = partition <<8 | disk
sfs_format_init$:
	mov	[eax + sfs_disk], bx

	mov	edx, [esi + PT_LBA_START]
	mov	[eax + sfs_partition_start_lba], edx

		print "Partition LBA: "
		call	printhex8

	mov	edx, [esi + PT_SECTORS]
	mov	[eax + sfs_partition_size_lba], edx

		print ". Formatting "
		call	printdec32
		println " sectors"


	# init sfs_blk0

	lea	edi, [eax + sfs_blk0]
	mov	[edi + sfs_vol_magic], dword ptr SFS_MAGIC
	mov	[edi + sfs_vol_blocksize_bits], byte ptr 9 # 512 byte sectors
	mov	[edi + sfs_vol_size + 0], edx
	mov	[edi + sfs_vol_size + 4], dword ptr 0

	mov	[edi + sfs_vol_data_lba], dword ptr 1	# blk0 end
	clc
	ret

# in: ebx-512 = start of buf
# in: 512 = size of buf
# out: esi = buffer offset
sfs_format_clear_buf$:
	push_	edi eax ecx
	xor	eax, eax
	lea	edi, [ebp - 512]
	mov	ecx, 512/4
	mov	esi, edi
	rep	stosd
	pop_	ecx eax edi
	ret

#########################
# First Table: allocation

# write sfs_vol_blktab: sector allocation
# in: eax = sfs instance
sfs_format_init_blktab$:
	LOAD_TXT "blktab"
	#lea	edx, [eax + sfs_blk0 + sfs_vol_tbl_blktab]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_size]
	shr	ecx, 8	# bits->bytes; 
	call	sfs_tbl_alloc
	ret

#####################
# Second Table: names

sfs_format_init_names$:
	LOAD_TXT "names"
	#lea	edx, [eax + sfs_blk0 + sfs_vol_tbl_names]
	mov	ecx, SFS_NAMES_RESERVE
	call	sfs_tbl_alloc # mod: edx, esi

	lea	edi, [ebp - 512]
	mov	[edx + sfs_blk0 + sfs_vol_tbl_names + tbl_mem], edi

	push	esi
	LOAD_TXT "blktab", esi, ecx
	DEBUG_DWORD ecx
	rep	movsb
	pop	esi
	# copy given label ("names")
	call	strlen_
	DEBUG_DWORD ecx
	rep	movsb

	lea	ecx, [ebp - 512]
	sub	edi, ecx
	DEBUG_DWORD edi

	mov	[edx + tbl_size], edi
	ret

########################
# Third Table: directory

sfs_format_init_dir$:
	LOAD_TXT "dir"
	#lea	edx, [eax + sfs_blk0 + sfs_vol_tbl_dir]
	mov	ecx, SFS_DIR_RESERVE
	call	sfs_tbl_alloc
	mov	[edx + tbl_size], dword ptr 512	# empty root directory

	call	strlen_
#	call	sfs_tbl_names_append
clc
	ret

# in: eax = sfs instance
# in: ecx = reserve size
# out: edx = table def ptr (sfs_blk0 + SFS_STRUCT_SIZE*[sfs_vol_numtbl++])
sfs_tbl_alloc:
	printc 11, " * init table "
	call	print
	push	ecx
	call	strlen_
	neg	ecx
	add	ecx, 12
0:	call	printspace
	loop	0b
	pop	ecx

	mov	edx, [eax + sfs_blk0 + sfs_vol_numtbl]
	DEBUG_DWORD edx
	inc	dword ptr [eax + sfs_blk0 + sfs_vol_numtbl]
	.if TBL_STRUCT_SIZE == 32
	shl	edx, 5
	.else
	.error "TBL_STRUCT_SIZE 32 not implemented"
	.endif

	lea	edx, [eax + sfs_blk0 + sfs_vol_tbl + edx]

	push_	esi ebx ecx
	mov	ebx, [eax + sfs_blk0 + sfs_vol_data_lba]
	mov	[edx + tbl_lba], ebx
	mov	[edx + tbl_reserve], ecx
	mov	[edx + tbl_size], dword ptr 0
	add	ecx, 511
	shr	ecx, 9
	add	[eax + sfs_blk0 + sfs_vol_data_lba], ecx

		push	edx
		mov	edx, ebx
		print " LBA: "
		call	printhex8
		mov	edx, ecx
		print " Reserve: "
		call	printhex8
		print " sectors. "
		pop	edx

	mov	ecx, [edx + tbl_reserve]
	add	ecx, 511
	shr	ecx, 9
	call	sfs_format_clear_buf$	# out: esi
	mov	ebx, [edx + tbl_lba]

0:	push	ecx
	printchar '.'
	call	sfs_write_blk
	inc	ebx
	pop	ecx
	loop	0b

	OK
	clc

	pop_	ecx ebx esi
	ret

# in: eax = sfs instance
# in: edx = table def ptr
# in: esi = buffer
sfs_tbl_write:
	push_	edx ecx ebx
	mov	ebx, [edx + tbl_lba]
	mov	ecx, [edx + tbl_size]
	call	sfs_write_blk
	pop_	ebx ecx edx
	ret


###############################################################################
# Directory Table

# in: eax
# in: ebx = parent dir id (-1 for root level)
# out: ebx = dir id (lba for now - directory entires are sector aligned).
# out: edi = sfs_dir ptr
# out: edx = parent pointer
sfs_tbl_dir_insert:

	push_	esi ecx
	lea	esi, [eax + sfs_blk0 + sfs_vol_tbl_dir]
	mov	edi, [esi + tbl_mem]
	or	edi, edi	# exception
	jnz	81f
18:

	cmp	ebx, -1
	jz	61f

	mov	ebx, [esi + tbl_size]
	and	ebx, 511
	jz	82f		# end is sector aligned i.e. not loaded.
	add	ebx, SFS_DIR_STRUCT_SIZE
	shr	ebx, 9
	jnz	82f
28:	add	edi, [esi + tbl_size]
16:
	.if 1	# backward compat LBA addr
	mov	ebx, [eax + sfs_blk0 + sfs_vol_data_lba]
	inc	dword ptr [eax + sfs_blk0 + sfs_vol_data_lba]
	mov	edx, [esi + tbl_size]
	add	[esi + tbl_size], dword ptr SFS_DIR_STRUCT_SIZE
	.else
		mov	ebx, edx	# use offset in table as id
		.if SFS_DIR_STRUCT_SIZE != 32
		.error "SFS_DIR_STRUCT_SIZE 32 not implemented in sfs_tbl_dir_insert"
		.endif
		shr	ebx, 5
	.endif

#	mov	[edi + sfs_dir_file_lba], ebx

	clc

0:	pop_	ecx esi
	ret

61:
	.if 0 # ebx as entry id:
		.if SFS_DIR_STRUCT_SIZE != 32
		.error "SFS_DIR_STRUCT_SIZE 32 not implemented in sfs_tbl_dir_insert"
		.endif
		shl	ebx, 5
		cmp	dword ptr [edi + ebx + sfs_dir_file_perm], 0
		jz	91f
		#mov	ebx, [edi + ebx + sfs_dir_file_lba]
		mov	ecx, [edi + ebx + sfs_dir_file_size]
	.else
	mov	ecx, 1	# fixme
	.endif
	call	sfs_load_blk	# in: eax=inst, ebx=dir, ecx=nsect; out: edi
	jc	92f
	#mov	[ebp - 4], edi

	# edi = dir blk
	lea	ecx, [edi + 512]	# max offs
62:	cmpd	[edi + sfs_dir_file_posix_perm], 0
	jz	16b	# found
	add	edi, SFS_DIR_STRUCT_SIZE
	cmp	edi, ecx
	jb	62b
	printc 4, "dir sector exhausted"
	int 3
	# TODO: mreallocz, like 81 below,
	# and update the cache (mem_ptr elsewhere!)
	jmp	16b



9:	printc 4, "sfs_tbl_dir_insert: "
	call	_s_println
	stc
	jmp	0b

# table not loaded.
81:	mov	ebx, [esi + tbl_lba]
	call	sfs_load_blk
	mov	[esi + tbl_mem], edi
	jnc	18b
	PUSH_TXT "table load error"
	jmp	9b

# adding data crosses section boundary
82:	push_	eax edx
	mov	eax, edi
	mov	edx, [esi + tbl_size]
	add	edx, 511 + 512*1
	and	edx, ~511
	call	mreallocz
	mov	[esi + tbl_mem], eax
	pop_	edx eax
	jnc	28b
	PUSH_TXT "mrealloc"
	jmp	9b

# dir handle invalid
91:	PUSH_TXT "invalid handle:         "
	push_	edx edi
	mov	edi, [esp + 4]
	add	edi, 16
	mov	edx, ebx
	call	sprinthex8
	pop_	edi edx
	jmp	9b

92:	PUSH_TXT "error loading parent"
	jmp	9b

# Name Table

# in: esi
# in: ecx (ignored)
# out: esi = offset in name table
sfs_tbl_names_append:
.if 1
	push_	edi ecx
	mov	edx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size]
	call	strlen_
	add	[eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size], ecx
	mov	edi, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_mem]
	add	edi, edx
	rep	movsb
	pop_	ecx edi
	ret
.else
	push_	edi ebx ecx edx
	# load names
	mov	ebx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_lba]
	mov	ecx, [eax + sfs_blk0 + sfs_vol_tbl_names + tbl_size]
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
1:	pop_	edx ecx ebx edi
	ret
.endif


# sfs_open redirects here if the name starts with '?'.
sfs_backdoor:
	DEBUG "backdoor"
	stc
	ret
