##############################################################################
# Simple File System
.intel_syntax noprefix
.code32

SFS_PARTITION_TYPE = 0x99	# or 69 or 96

SFS_MAGIC = ( 'S' | 'F' << 8 | 'S' << 16 | '0' << 24)

#############################################################################
.data
fs_sfs_class:
.long sfs_mount, sfs_umount, sfs_opendir, sfs_close, sfs_nextentry
.struct FS_OBJ_STRUCT_SIZE # runtime struct
sfs_disk:		.byte 0
sfs_partition:		.byte 0
sfs_partition_start_lba:.long 0, 0
sfs_partition_size_lba:	.long 0, 0
sfs_buffers:		
SFS_STRUCT_SIZE = .

###############################
.struct 0
# Block 0: 
sfs_blk_lba:	.long 0, 0	# relative - chain
sfs_blk_size:	.long 0, 0	# consecutive sectors
SFS_BLK_HEADER_SIZE = .
######################
.struct SFS_BLK_HEADER_SIZE
# Block 1:
sfs_vol_magic:		.long 0	# "SFS0"
sfs_vol_blocksize_bits:	.byte 0
			.byte 0, 0, 0
sfs_vol_num_entries:	.long 0
sfs_vol_entry_size:	.long 0
# Block 2 and on
sfs_vol_blocks:
# blocks 2..31 sfs_blk_ (16 bytes per entry)
# blk 32..63 will be in 512 bytes BEFORE this sector in mem, indicated
# by the blk_next on disk, etc..
SFS_VOL_STRUCT_SIZE = .
.struct 0

SFS_VOL_NUM_BLOCKS = (512 - SFS_VOL_STRUCT_SIZE)/16	# = 512/16 -1 = 31
SFS_SEC_NUM_BLOCKS = 512 / 16	# 32
.text
# in: esi = sfs struct
# in: edx = blk nr
# out: eax = block nr
# out: ecx = block size
# out: edx = edx * 8
sfs_get_blk_info:
	cmp	edx, [esi - 512 + sfs_vol_num_entries]
	jae	9f
	shl	edx, 4
	jz	9f
	neg	edx
	mov	eax, [esi - 512 + edx]
	mov	ecx, [esi - 512 + edx + 4]
	neg	edx
	shr	edx, 1
	ret
9:	printc 4, "sfs: illegal block number: "
	call	printdec32
	call	newline
	ret
	

	# start: .long 0,0
	# size: .long 0,0
# followed by num_blocks * 8 bytes: sfs_vol_blk_lba: .long 0, 0
# first block is root block.
.text
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
	mov	eax, 512 + (512-SFS_VOL_STRUCT_SIZE) + SFS_STRUCT_SIZE
	call	mallocz
	mov	edi, eax
	pop	eax
	jc	9f

	mov	ecx, 1	# 1 sector
	mov	ebx, [esi + PT_LBA_START]
	push	edi
	call	ata_read
	pop	edi
	jc	9f

	cmp	[edi + sfs_vol_magic], dword ptr SFS_MAGIC
	stc
	jnz	9f
	mov	eax, [edi + sfs_vol_num_entries]
	cmp	eax, dword ptr (512-SFS_VOL_STRUCT_SIZE)/16
	jbe	0f

	# entries span multiple sectors - calculate the number of sectors

	mov	ecx, eax
	shr	ecx, 5
	inc	ecx

	mov	eax, ecx
	inc	eax
	shr	eax, 1
	add	eax, ecx
	call	mallocz
	jc	9f
	mov	esi, edi
	xchg	eax, edi

0:	add	edi, 512
	jmp	9f

8:	mov	eax, edi
	call	mfree
9:	pop	edx
	ret

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

	push	eax
	mov	eax, 512
	call	mallocz
	mov	edi, eax
	pop	eax
	jc	9f

	mov	ecx, [esi + PT_SECTORS]
	# fill in block 0: entire volume size
	mov	[edi + sfs_blk_lba + 0], dword ptr 0
	mov	[edi + sfs_blk_lba + 4], dword ptr 0
	mov	[edi + sfs_blk_size + 0], ecx
	mov	[edi + sfs_blk_size + 4], dword ptr 0
	# fill in block 1
	mov	[edi + sfs_vol_magic], dword ptr SFS_MAGIC
	mov	[edi + sfs_vol_blocksize_bits], byte ptr 9 # 512 byte sectors
	mov	[edi + sfs_vol_num_entries], dword ptr 30
	mov	[edi + sfs_vol_entry_size], dword ptr 16
	# fill in block 2: 
	mov	[edi + 32 + sfs_blk_lba + 0], dword ptr 0
	mov	[edi + 32 + sfs_blk_lba + 4], dword ptr 0
	mov	[edi + 32 + sfs_blk_size + 0], dword ptr 1
	mov	[edi + 32 + sfs_blk_size + 4], dword ptr 0

	mov	ebx, [esi + PT_LBA_START]
	push	esi
	mov	esi, edi
	mov	ecx, 1
	call	ata_write
	pop	esi
	jc	9f

	printlnc 11, "Partition formatted."

9:	ret
8:	printlnc 4, "sfs_format: partition not "
	push	edx
	mov	edx, SFS_PARTITION_TYPE
	call	printhex2
	pop	edx
	stc
	ret


# in: edi
sfs_umount:
	lea	esi, [edi + sfs_buffers + 4]
0:	mov	eax, [esi]
	or	eax, eax
	jz	0f
	call	mfree
	add	esi, 8
	jmp	0b
0: 
	lea	eax, [edi - 512]
	call	mfree
	ret


# in: eax = directory name
# in: esi = fs struct
sfs_open_dir:
	xor	edx, edx
	call	load_blk
	inc	edx
	call	load_blk
	ret


# in: esi = fs struct
# in: edx = sfs_block index
load_blk:
	shl	edx, 3
	mov	eax, [esi + sfs_buffers + edx]
	or	eax, eax
	jnz	0f
	mov	eax, [esi - 512 + sfs_vol_blocks + edx + 4]
	shl	eax, 9
	add	eax, 511
	call	malloc
	jc	9f
	mov	[esi + sfs_buffers + edx + 4], eax
	and	eax, ~511
	mov	[esi + sfs_buffers + edx + 0], eax

	mov	ebx, [esi - 512 + sfs_vol_blocks + edx + sfs_blk_lba]
	add	ebx, [esi + sfs_partition_start_lba]
	mov	ecx, [esi - 512 + sfs_vol_blocks + edx + sfs_blk_size]
	mov	edi, eax
	mov	ax, [esi + sfs_disk]
	call	ata_read
	jc	9f
0:
	
9:	
	ret

sfs_nextentry:
sfs_opendir:
sfs_close:
	ret

sfs_open:
#	call	sfs_open_dir
#	call	sfs_open_file
	ret

