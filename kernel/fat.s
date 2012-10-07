##############################################################################
# FAT File System (FAT16, FAT32)

FS_FAT_DEBUG = 0

#
#  HDD
#  ___________
# |bootsector with partition table
# +------------
# |partition 0: Volume boot record sector - FAT info
# +------------
# | FAT Table 1
# | FAT Table 2
# | Cluster 0: root directory 
# | Cluster 2: free clusterspace: data
# |
#
#
# Clustered File System
# 
# A cluster is a number of contiguous sectors.
#
# The VBR - first sector of the partition - contains:
# - sectors per fat
# - sectors per cluster
#
# The data immediately after the VBR consists of the fat sectors.
#
# The data immediately following the fat sectors is the userdata space,
# the free clusters.
#
# For FAT12/FAT16, the root directory cluster starts at cluster 0.
# Here however, the VBR specifies the number of directory entries
# (say 0x200), times 32 bytes per entry, is 0x4000 bytes, or, 0x20 sectors,
# equalling 2 clusters for a sectors-per-cluster of 0x10.
#
# Even though the number of entries may differ, the FAT itself marks
# the first data (the contents of the first directory in the root)
# as cluster 2. It fits with 512 root directory entries, however,
# the reason is that cluster values 0 and 1 are reserved to indicate free
# and reserved clusters, making 2 the first available cluster number.
#
#
#
# So, it seems that the root directory contents need to be cluster aligned.
# Perhaps if the root directory entries were more than 0x200 (512),
# more clusters would be needed, and thus, the data would start at cluster 3.`

# FAT Cluster Numbers
#
# 		(sign extend to nr of bits (12, 16, 32)
# -16 .. -10:	0xF0 .. 0xF6	reserved value
# -9:		0xF7		bad cluster
# -8 .. -1:	0xF8 .. 0xFF	last cluster
# 0: free cluster
# 1: reserved cluster
# 2: next cluster
# ..

#
# -16: reserved
# ..
# -10: reserved
# -9: bad cluster
# -8: last cluster
# ..
# -1: last cluster
#  0: free cluster
#  1: reserved cluster
#  2: next cluster
#  ..
#  


############################################################################
# fs_fat class - virtual method pointers:
.data
fs_fat16_class:
STRINGPTR "fat16"
.long fs_fat16b_mount	# constructor
.long fs_fat16b_umount	# destructor
.long fs_fat16_open
.long fs_fat16_close
.long fs_fat_nextentry
.long fs_fat16_read

.struct FS_OBJ_STRUCT_SIZE
fat_rootdir_buf$:	.long 0	# size: root_size_sectors * sectorsize
fat_rootdir_bufsize$:	.long 0
fat_buf$:		.long 0
fat_bufsize$:		.long 0
fat_fatbuf$:		.long 0

# The LBA addresses here are partition-relative: add fs_obj_p_start_lba.
fat_lba$:		.long 0
fat_clustersize$:	.long 0	# sectors per cluster
fat_sectorsize$:	.long 0	# 0x200
fat_clustersize_bytes$:	.long 0	# sectorsize * clustersize
fat_sectors$:		.long 0		# sectors per fat
fat_root_lba$:		.long 0
fat_root_size_sectors$:	.long 0 # (511+ root_numentries * 32) / 512
fat_user_lba$:		.long 0	# first data sector
FAT_STRUCT_SIZE = .


#########################################################
# fat directory entry format
.struct 0
FAT_DIR_NAME: .space 11	# 8 + 3
FAT_DIR_ATTRIB: .byte 0 # RO=1 H=2 SYS=4 VOL=8 DIR=10 A=20  (0F=long fname)
	.byte 0 # reserved by NT
	# creation time
FAT_DIR_CTIME_DECISECOND: .byte 0 # tenths of a second
FAT_DIR_CTIME: .word 0	# Hour: 5 bits, minuts 6 bits, seconds 5 bits
FAT_DIR_CDATE: .word 0 # year 7 bits, month 4 bits, day 5 bits
FAT_DIR_ADATE: .word 0 # last accessed date
FAT_DIR_HI_CLUSTER: .word 0 # 0 for fat12/fat16
FAT_DIR_MTIME: .word 0 # modification time
FAT_DIR_MDATE: .word 0
FAT_DIR_CLUSTER: .word 0
FAT_DIR_SIZE: .long 0	# filesize in bytes

###################################
# fat long filename directory entry format
.struct 0 # Long file name entries are placed immediately before the 8.3 entry
FAT_DIR_LONG_SEQ: .byte 0 # sequence nr; 0x40 bit means it is last also
FAT_DIR_LONG_NAME1: .space 10	# 5 2-byte chars
FAT_DIR_LONG_ATTRIB: .byte 0 # 0xf for long filenames
FAT_DIR_LONG_TYPE: .byte 0	# 0 for name entires
FAT_DIR_LONG_CKSUM: .byte 0
FAT_DIR_LONG_NAME2: .space 12 # 6 2-byte characteres
	.word 0 # always 0
FAT_DIR_NAME3: .space 4	# final 2 2-byte characters (total: 5+6+2=13)


####################################################
# partition types commonly used for FAT
.data
fs_fat_partition_types$:
	.byte	0x01	# FAT12 max 32mb
	.byte	0x04	# FAT16 max 32mb
	.byte	0x06	# FAT16b, FAT16, FAT12
	.byte	0x08	# FAT12, FAT16
	.byte	0x0b	# FAT32
	.byte	0x0c	# FAT32X
	.byte	0x0e	# FAT16x
	.byte	0x11	# FAT12, FAT16
	.byte	0x86	# FAT16 legacy
	.byte	0x8b	# FAT32 legacy
	.byte	0x8c	# FAT32 LBA legacy
	.byte	0x8d	# Freedos hidden FAT12 (0x01)
	.byte	0x90	# Freedos hidden FAT16 (0x04)
	.byte	0x92	# Freedos hidden FAT16b (0x06)
	.byte	0x97	# FAT32 hidden (0x0b)
fs_fat_num_partition_types$ = . - fs_fat_partition_types$


###########################################################################
.text32

fs_fat16b_umount:
	printlnc 4, "fs_fat: umount not implemented"
	stc
	ret

# in: ax = disk/partition
# in: esi = partition info
# out: edi = pointer to filesystem structure
fs_fat16b_mount:
	# check if system supported: scan for partition types
	push	edi
	push	ecx
	push	eax
	mov	al, [esi + PT_TYPE]
	mov	edi, offset fs_fat_partition_types$
	mov	ecx, fs_fat_num_partition_types$
	repnz	scasb
	pop	eax
	pop	ecx
	pop	edi
	jz	0f
	stc
	ret

0:	push	esi
	# allocate fat structure + sector
	push	eax
	mov	eax, 512 + FAT_STRUCT_SIZE
	call	mallocz
	mov	edi, eax
	pop	eax
	mov	[edi + fs_obj_disk], ax
	add	edi, FAT_STRUCT_SIZE
	# load sector
	push	eax
	push	ebx
	push	ecx
	push	edi
	mov	ebx, [esi + PT_LBA_START]
	mov	ecx, 1
	call	ata_read	# in: al = drive, ebx, ecx, edi
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax

	jc	1f
	call	fs_fat16b_verify_vbr
	jc	1f

	mov	esi, edi
	sub	edi, FAT_STRUCT_SIZE
	call	fs_fat16_calculate

	mov	[edi + fs_obj_class], dword ptr offset fs_fat16_class

	# allocate a cluster buffer
	push	eax
	mov	eax, [edi + fat_clustersize_bytes$]
	mov	[edi + fat_bufsize$], eax
	call	mallocz
	mov	[edi + fat_buf$], eax
	pop	eax
	jc	1f

	# allocate root directory buffer
	push	eax
	push	edx
	mov	eax, [edi + fat_root_size_sectors$]
	mul	dword ptr [edi + fat_sectorsize$]
	mov	[edi + fat_rootdir_bufsize$], eax
	# assume edx=0
	call	mallocz
	mov	[edi + fat_rootdir_buf$], eax
	pop	edx
	pop	eax

	push	eax
	mov	eax, edi
	call	fat16_load_root_directory
	pop	eax
	jc	1f

###	# allocate the fat buffer
	push	ecx

##
	push	eax
	push	edx
	mov	edx, [edi + fat_sectorsize$]
	mov	eax, [edi + fat_sectors$]
	mul	edx

	# we'll assume for the malloc that the size is < 4Gb (edx=0)
	push	eax
	call	mallocz
	mov	[edi + fat_fatbuf$], eax
	pop	eax

	# divide by 512 to calculate disk sectors (if it differs)
	shr	edx, 1
	sar	eax, 1
	mov	al, dl
	ror	eax, 8

	.if FS_FAT_DEBUG
		DEBUG_DWORD eax
	.endif

	# load this many sectors

	mov	ecx, eax

	pop	edx
	pop	eax
##

	push	ebx
	push	edi

	mov	ebx, [edi + fat_lba$]
	add	ebx, [edi + fs_obj_p_start_lba]

	.if FS_FAT_DEBUG
		DEBUG "Load "
		DEBUG_DWORD ecx
		DEBUG "sectors at LBA "
		DEBUG_DWORD ebx
	.endif

	mov	al, [edi + fs_obj_disk]
	mov	edi, [edi + fat_fatbuf$]
	call	ata_read
	# out: cf

	pop	edi
	pop	ebx
	
	pop	ecx
###
	#clc
	# possibly mrealloc to FAT_STRUCT_SIZE to release VBR sector

1:	pop	esi
	ret


.struct 11
BPB_BYTES_PER_SECTOR: .word 0
BPB_SECTORS_PER_CLUSTER: .byte 0	# power of 2, max 128 (2^7)
BPB_RESERVED_SECTORS: .word 0
BPB_FATS: .byte 0
BPB_ROOT_ENTRIES: .word 0
BPB_SMALL_SECTORS: .word 0	# 0 for > 64k, see LARGE_SECTORS
BPB_MEDIA_DESCRIPTOR: .byte 0
BPB_SECTORS_PER_FAT: .word 0
BPB_SECTORS_PER_TRACK: .word 0
BPB_HEADS: .word 0
BPB_HIDDEN_SECTORS: .long 0
BPB_LARGE_SECTORS: .long 0

EBPB_DRIVE_NUMBER: .byte 0
EBPB_NT_FLAGS: .byte 0	# bit 0 = run chkdsk, bit 1 = run surface scan
EBPB_SIGNATURE: .byte 0	# 0x28 or 0x29
EBPB_VOLUME_ID_SERIAL: .long 0
EBPB_VOLUME_LABEL: .space 11
EBPB_SYSTEM_ID: .space 8	# "FAT16   "
.text32


# in: edi = sector data
# in: esi = partition info
fs_fat16b_verify_vbr:
	push	eax
	push	ebx
	mov	ebx, esi

	LOAD_TXT "not 512 bytes/sector"
	cmp	word ptr [edi + BPB_BYTES_PER_SECTOR], 512
	jnz	1f

	LOAD_TXT "sectors per cluster not power of 2"
	movzx	eax, byte ptr [edi + BPB_SECTORS_PER_CLUSTER]
	push	ecx
	bsr	ecx, eax
	inc	ecx
	shr	eax, cl
	pop	ecx
	jnz	1f
	

	LOAD_TXT "Not 2 FATS"
	cmp	byte ptr [edi + BPB_FATS], 2
	jnz	1f

	# check EBPB:
	LOAD_TXT "invalid signature"
	cmp	byte ptr [edi + EBPB_SIGNATURE], 0x28
	jz	2f
	cmp	byte ptr [edi + EBPB_SIGNATURE], 0x29
	jnz	1f
2:

	LOAD_TXT "Invalid system identifier"
	mov	eax, [edi + EBPB_SYSTEM_ID]
	cmp	eax, ('F') | ('A'<<8) | ('T'<<16) | ('1'<<24)
	jnz	1f
	mov	eax, [edi + EBPB_SYSTEM_ID + 4]
	cmp	eax, (0x20202000)|'6'
	jnz	1f

	LOAD_TXT "ptable LBA start != BPB Hidden sectors"
	mov	eax, [ebx + PT_LBA_START]
	cmp	eax, [edi + BPB_HIDDEN_SECTORS]
	jnz	1f

	LOAD_TXT "ptable numsectors != BPB num sectors"
	movzx	eax, word ptr [edi + BPB_SMALL_SECTORS]
	or	eax, eax
	jnz	2f
	mov	eax, [edi + BPB_LARGE_SECTORS]
2:	cmp	eax, [ebx + PT_SECTORS]
	jnz	1f

	clc
0:	pop	ebx
	pop	eax
	ret

1:	pushcolor 12
	print	"fat16b verification error: "
	call	println
	popcolor
	stc
	jmp	0b



# in: esi = sector data
# in: edi = filesystem info
fs_fat16_calculate:
	push	eax
	push	ecx
	push	edx

	# partition start
	mov	eax, [esi + BPB_HIDDEN_SECTORS]
	mov	[edi + fs_obj_p_start_lba], eax

	# partition size
	movzx	edx, word ptr [esi + BPB_SMALL_SECTORS]
	or	edx, edx
	jnz	1f
	mov	edx, [esi + BPB_LARGE_SECTORS]
1:	mov	[edi + fs_obj_p_size_sectors], edx
	# partition end
	add	edx, eax
	mov	[edi + fs_obj_p_end_lba], edx


	## Calculate start of first FAT
	movzx	ecx, word ptr [esi + BPB_RESERVED_SECTORS]
	#add	eax, [esi + BPB_HIDDEN_SECTORS]	# LBA start
	# this should point to the first sector after the partition boot record
	mov	[edi + fat_lba$], ecx

	# now we add sectors per fat:
	movzx	edx, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[edi + fat_sectors$], edx

	movzx	eax, byte ptr [esi + BPB_FATS]
	mul	edx
	# eax = total fat sectors for all fats

	# calculate fat end:
	add	eax, ecx	
	# now eax points just after the fat, which is where
	# the root directory begins in fat12/16.
	mov	[edi + fat_root_lba$], eax



	# now we add the size of the root directory to it.
	movzx	edx, word ptr [esi + BPB_ROOT_ENTRIES]
	# and we multiply it by the size of directory entries: 32 bytes.
	shl	edx, 5
	# convert to a sector:
	push	ecx
	movzx	ecx, word ptr [esi + BPB_BYTES_PER_SECTOR]
	# add the bytes-per-sector -1 to round up
	add	edx, ecx
	dec	edx
	xor	eax, eax
	xchg	edx, eax
	# divide by bytes per sector
	div	ecx
	pop	ecx

	mov	[edi + fat_root_size_sectors$], eax

	# now we add the sector just after the fat to it
	add	eax, [edi + fat_root_lba$]
	mov	[edi + fat_user_lba$], eax

	movzx	eax, byte ptr [esi + BPB_SECTORS_PER_CLUSTER]
	mov	[edi + fat_clustersize$], eax
	movzx	edx, word ptr [esi + BPB_BYTES_PER_SECTOR]
	mov	[edi + fat_sectorsize$], edx
	mul	edx
	mov	[edi + fat_clustersize_bytes$], eax

	.if FS_FAT_DEBUG

		PRINTc 10, "FAT LBA: "
		mov	edx, [edi + fat_lba$]
		call	printhex8
		PRINTc 10, "  Offset: "
		add	edx, [edi + fs_obj_p_start_lba]
		shl	edx, 9
		call	printhex8
		PRINTc 10, " Size: "
		mov	edx, [edi + fat_sectors$]
		shl	edx, 9
		call	printhex8
		call	newline

		PRINTc 10, "FAT Root Directory: "
		mov	edx, [edi + fat_root_lba$]
		call	printhex8
		PRINTc 10, "  Offset: "
		add	edx, [edi + fs_obj_p_start_lba]
		shl	edx, 9
		call	printhex8
		PRINTc 10, " Size: "
		mov	edx, [edi + fat_root_size_sectors$]
		shl	edx, 9
		call	printhex8
		call	newline

		PRINTc 10, "FAT ClusterSize: "
		mov	edx, [edi + fat_clustersize$]
		call	printdec32
		PRINTc 10, " sectors ("
		mov	edx, [edi + fat_clustersize_bytes$]
		call	printdec32
		PRINTc 10, ") SectorSize: "
		mov	edx, [edi + fat_sectorsize$]
		call	printdec32
		call	newline

		PRINTc 10, "FAT Userdata LBA: "
		mov	edx, [edi + fat_user_lba$]
		call	printhex8
		PRINTc 10, "  Offset: "
		add	edx, [edi + fs_obj_p_start_lba]
		shl	edx, 9
		call	printhex8
		call	newline

	.endif

	pop	edx
	pop	ecx
	pop	eax
	ret

############################################################################
.struct 0
fat_handle_name:	.long 0
fat_handle_dir_buf:	.long 0
fat_handle_dir_bufsize:	.long 0
fat_handle_dir_entry:	.long 0	# relative offset
fat_handle_cluster:	.long 0
fat_handle_parent:	.long 0	# parent handle
FAT_HANDLE_STRUCT_SIZE = .
.data
fat_handles: .long 0
.text32
# out: eax + ebx = fat_handle
fat_gethandle:
	push	ecx
	push	edx
	mov	ecx, FAT_HANDLE_STRUCT_SIZE
	mov	eax, [fat_handles]
	or	eax, eax
	jnz	0f
	mov	eax, 16
	call	array_new
	jc	9f
	mov	[fat_handles], eax
0:	xor	ebx, ebx
	jmp	1f
0:	
	cmp	dword ptr [eax + ebx + fat_handle_dir_entry], -1
	jz	9f
	add	ebx, FAT_HANDLE_STRUCT_SIZE
1:	cmp	ebx, [eax + array_index]
	jb	0b
	call	array_newentry
	mov	ebx, edx
	mov	[fat_handles], eax
9:	pop	edx
	pop	ecx
	ret

# in: ebx = array index
fat_freehandle:
	push	eax
	push	ecx

	mov	ecx, [fat_handles]
	or	ecx, ecx
	stc
	jz	9f
	cmp	ebx, [ecx + array_index]
	stc
	jae	9f

0:	mov	dword ptr [ecx + ebx + fat_handle_dir_entry], -1
	mov	eax, [ecx + ebx + fat_handle_dir_buf]
	call	mfree
	mov	eax, [ecx + ebx + fat_handle_name]
	call	mfree
	#mov	ebx, [ecx + ebx + fat_handle_parent]
	#cmp	ebx, -1
	#jnz	0b

9:	pop	ecx
	pop	eax
	ret

cmd_fat_handles:
	printlnc 15, " handle | parent |cluster | buf    |bufsize |name"
	ARRAY_LOOP [fat_handles], FAT_HANDLE_STRUCT_SIZE, eax, ebx, 9f
	mov	edx, ebx
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fat_handle_parent]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fat_handle_cluster]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fat_handle_dir_buf]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + fat_handle_dir_bufsize]
	call	printhex8
	call	printspace
	mov	esi, [eax + ebx + fat_handle_name]
	call	println
	ARRAY_ENDL
9:	ret
######################################################

# in: eax = pointer to fs_instance structure
# in: ebx = parent directory handle (-1 for root)
# in: esi = asciz directory name
# in: edi = fs dir entry struct (to be filled in)
# out: ebx = directory/file handle
fs_fat16_open:
	.if FS_FAT_DEBUG > 1
		DEBUG "fs_instance"
		DEBUG_DWORD eax

		pushcolor 0xf1
		print	"fs_fat16_open("
		call	print
		print ")"
		popcolor

		DEBUG_DWORD ebx
		call newline
	.endif

	push	ecx
	push	edx
	push	esi
	push	edi

	cmp	ebx, -1
	jnz	0f

	# parent dir is root.
	# check what to open
	cmp	word ptr [esi], '/'
	jnz	1f

	mov	[edi + fs_dirent_attr], byte ptr 0x10
	mov	[edi + fs_dirent_name], word ptr '/'
	mov	[edi + fs_dirent_size], dword ptr 0
	mov	[edi + fs_dirent_size+4], dword ptr 0

	.if FS_FAT_DEBUG > 2
		mov	esi, [eax + fat_rootdir_buf$]
		DEBUG_DWORD esi
		mov	ecx, [eax + fat_rootdir_bufsize$]
		call	newline
		call	fs_fat16_print_directory$
	.endif

	clc
	jmp	9f	# ebx remains -1 to indicate root
#######
1:
	mov	ecx, [eax + fat_rootdir_bufsize$]
	mov	edi, [eax + fat_rootdir_buf$]
	.if FS_FAT_DEBUG > 1
		print "root"
	.endif
	jmp	2f

#######
0:	# ebx != -1: cluster
	mov	ecx, [eax + fat_bufsize$]
	mov	edi, [eax + fat_buf$]
	.if FS_FAT_DEBUG > 1
		print "subdir"
	.endif
#######
2:
	call	fat16_find_entry# in: esi, edi, ecx; out: edi
	jc	9f

	mov	bx, [edi + FAT_DIR_HI_CLUSTER]
	shl	ebx, 16
	mov	bx, [edi + FAT_DIR_CLUSTER]

	.if FS_FAT_DEBUG > 2
		DEBUG_DWORD ebx
		push	edx
		call	newline
		DEBUG "Clusters: ["
		call	printhex8
		call	printspace
	0:	DEBUG_DWORD edx
		call	fat16_get_next_cluster
		jc	0f
		call	printhex8
		call	printspace
		cmp	edx, 2
		jg	0b
		DEBUG "]"
	0:	pop	edx
	.endif

	mov	edx, edi
	mov	edi, [esp]
	call	fat16_make_fs_entry	# in: edx, edi; out [edi]

	test	byte ptr [edx + FAT_DIR_ATTRIB], 0x10
	clc
	jz	9f

	call	fat_load_directory$

	.if FS_FAT_DEBUG > 2
		jc	9f
		DEBUG "return cluster:"
		DEBUG_DWORD ebx
		call	newline
		mov	esi, [eax + fat_buf$]
		mov	ecx, 32 * 10 # [eax + fat_bufsize$]
		call	fs_fat16_print_directory$
		clc
	.endif

9:	pop	esi
	pop	edi
	pop	edx
	pop	ecx
	ret

######################################################

# in: eax = fs_instance
# in: ebx = directory/file handle
fs_fat16_close:
	# release resources
	ret


# in: eax = pointer to fs_instance
# in: edx = cluster
# out: edx = cluster
fat16_get_next_cluster:
	sub	edx, 2
	jns	0f
	cmp	edx, -9
	jz	_err_inv_cluster$
	jg	0f
	cmp	edx, -18
	jge	_err_inv_cluster$
0:
	push	eax
	mov	eax, [eax + fat_fatbuf$]
	movsx	edx, word ptr [eax + edx * 2]
	pop	eax
	clc
	ret


# in: eax = fs_instance
# in: edx = cluster
# out: ebx = sector
fs_fat16_cluster_to_sector$:
	sub	edx, 2
	js	1f

3:
	# calculate sector 
	push	eax
	push	edx
	mov	eax, [eax + fat_clustersize$]	# sectors per cluster
	mul	edx
	mov	ebx, eax
	pop	edx
	pop	eax
	add	edx, 2

	add	ebx, [eax + fat_user_lba$]

	clc
	ret

1:	cmp	edx, -18
	jl	0b

_err_inv_cluster$:
	printc 4, "fat_cluster: invalid cluster number: "
	add	edx, 2
	call	printhex8	# for fat32
	call	newline
	stc
	ret

# in: eax = fs_instance
# in: edx = cluster
# out: ecx = num clusters
fat16_get_num_clusters:
	push	edx
	xor	ecx, ecx
0:	cmp	edx, 2
	jb	9f
	inc	ecx
	call	fat16_get_next_cluster
	jnc	0b
9:	pop	edx
	ret


# in: esi = directory to find
# in: edi = preloaded-directory buffer
# in: ecx = buf size
# out: edi = pointer to directory entry
fat16_find_entry:

	.if FS_FAT_DEBUG > 2
		DEBUG "find "
		DEBUGS
		DEBUG_DWORD eax
	.endif

	push	esi
	push	ecx
	push	edx
	push	eax
	push	ebp

	# edx marks end of buffer
	mov	edx, edi
	add	edx, ecx

	# convert filename to dos
	push	edi
	lea	ebp, [esp - 3*4 - 12]	# 3*4 pushes, 12 for 8.3=11+z
	mov	edi, ebp
	mov	ecx, 8
0:	lodsb
	or	al, al
	jz	0f
	cmp	al, '.'
	jz	0f
	stosb
	loop	0b
0:	or	ecx, ecx
	jz	0f
	mov	ah, al
	mov	al, ' '
	rep	stosb
	mov	al, ah
0:	mov	ecx, 3
	or	al, al
	jz	0f
1:	lodsb
	or	al, al
	jz	0f
	stosb
	loop	1b
0:	or	ecx, ecx
	jz	0f
	mov	al, ' '
	rep	stosb
0:	pop	edi

	.if FS_FAT_DEBUG > 2
		mov	esi, ebp
		mov	ecx, 11
		pushcolor 0xb0
		call	nprint
		popcolor
	.endif


0:	cmp	byte ptr [edi], 0
	stc
	jz	1f

	.if FS_FAT_DEBUG > 2
		mov	esi, edi
		mov	ecx, 11
		pushcolor 0xa0
		call	nprint
		popcolor
		call	printspace
	.endif

	push	edi
	mov	ecx, 11
	mov	esi, ebp
	repz	cmpsb
	pop	edi
	jz	2f

	add	edi, 32
	cmp	edi, edx
	jb	0b
	stc
	jmp	1f

2:	.if FS_FAT_DEBUG > 2
		DEBUG "found:"
		#sub	edi, edx
		#DEBUG_DWORD edi
		DEBUG "Cluster: "
		mov	dx, [edi + FAT_DIR_HI_CLUSTER]
		shl	edx, 16
		mov	dx, [edi + FAT_DIR_CLUSTER]
		DEBUG_DWORD edx
		call	newline
	.endif

	clc
1:	pop	ebp
	pop	eax
	pop	edx
	pop	ecx
	pop	esi
	ret

# Root directory is 'special', as it isnt referenced by cluster, but
# by sectors. Also, since the root directory is accessed on every directory
# access, it is cached.
#
# in: eax = fs_instance pointer
# in: ebx = LBA address within partition
# out: edi = buffer [eax+fat_buf$]
fat16_load_root_directory:
	push	eax
	push	ebx
	push	ecx
	push	edi
	mov	ecx, [edi + fat_root_size_sectors$]
	mov	edi, [eax + fat_rootdir_buf$]
	mov	ebx, [eax + fat_root_lba$]
	add	ebx, [eax + fs_obj_p_start_lba]
	mov	al, [eax + fs_obj_disk]
	call	ata_read
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
	ret

# in: eax = fs_instance pointer
# in: ebx = cluster
# out: edi = buffer [eax + fat_buf$]
fat_load_directory$:
	.if FS_FAT_DEBUG > 2
		DEBUGc 12, "fat_load_directory"
		DEBUG_DWORD ebx
	.endif
	push	eax
	push	ebx
	push	ecx
	push	edi
	push	edx
	mov	edx, ebx
	call	fs_fat16_cluster_to_sector$
	add	ebx, [eax + fs_obj_p_start_lba]
	mov	edi, [eax + fat_buf$]
	mov	ecx, [eax + fat_clustersize$]
	mov	al, [eax + fs_obj_disk]
	call	ata_read
	pop	edx
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
	ret


# in: eax = fs_instance pointer
# in: ebx = fat_handle structure index
# out: ebx = new fat_handle structure index, linked to parent
fat_handle_load_directory$:
	call	fat_load_helper$
	push	eax
	push	ebx
	push	ecx
	push	edi
	add	ebx, [fat_handles]
	mov	edi, [ebx + fat_handle_dir_buf]
	mov	ebx, [ebx + fat_handle_cluster]
	add	ebx, [eax + fs_obj_p_start_lba]

	mov	ecx, [eax + fat_clustersize$]
	mov	al, [eax + fs_obj_disk]
0:	call	ata_read
	jc	1f

	mov	edx, ebx
	call	fat16_get_next_cluster
	jc	1f
	add	edi, ecx
	jmp	0b

1:	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
	ret

# Allocates a fat_handle and a buffer to load all clusters.
#
# in: eax = fs_instance
# in: ebx = fat_handle
# in: esi = directory/file name
# out: ebx = new fat_handle
fat_load_helper$:
	push	esi
	push	edi
	push	edx
	push	ecx
	push	eax

	mov	edx, ebx
	xchg	esi, eax
	call	strdup
	mov	edi, eax

call newline
DEBUG "fat_load_helper"
DEBUG "parent"
DEBUG_DWORD edx
	call	fat_gethandle	# out: eax + ebx
	jc	1f
	mov	[eax + ebx + fat_handle_parent], edx
	mov	[eax + ebx + fat_handle_name], edi

	# get load size:
mov ecx, [eax + edx +fat_handle_dir_entry]
DEBUG "dirent"
DEBUG_DWORD ecx
	# load parent buffer
	mov	ecx, [eax + edx + fat_handle_dir_buf]
DEBUG "dir_buf"
DEBUG_DWORD ecx
	cmp	ecx, -1
	jnz	0f
	mov	ecx, [esi + fat_rootdir_buf$]
DEBUG_DWORD ecx
0:	add	ecx, [eax + edx + fat_handle_dir_entry]
	# ecx = fat directory entry

DEBUG "name["
push ecx
push esi
mov esi, ecx
mov ecx, 11
call nprint
pop esi
pop ecx
DEBUG "]"
	# get the cluster:
	mov	dx, [ecx + FAT_DIR_HI_CLUSTER]
	shl	edx, 16
	mov	dx, [ecx + FAT_DIR_CLUSTER]
	mov	[eax + ebx + fat_handle_cluster], edx
DEBUG "cluster"
DEBUG_DWORD edx

	# calculate size:
	call	fat16_get_num_clusters	# out: ecx
DEBUG "num"
DEBUG_DWORD ecx
	push	eax
	mov	eax, [esi + fat_clustersize_bytes$]
	mul	ecx
	mov	edx, eax
	call	mallocz
	mov	ecx, eax
	pop	eax
	mov	[eax + ebx + fat_handle_dir_buf], eax
	mov	[eax + ebx + fat_handle_dir_bufsize], edx
1:	
	pop	eax
	pop	ecx
	pop	edx
	pop	edi
	pop	esi
	ret

#fat_lba$:		.long 0
#fat_clustersize$:	.long 0	# sectors per cluster
#fat_sectorsize$:	.long 0	# 0x200
#fat_sectors$:		.long 0		# sectors per fat
#fat_root_lba$:		.long 0
#fat_user_lba$:		.long 0

# in: eax = fs info
# in: ebx = dir handle
# in: ecx = cur entry
# in: edi = fs dir entry struct
# out: ecx = next entry (-1 for none)
# out: edx = directory name
fs_fat_nextentry:
	cmp	ebx, -1
	jnz	0f

	cmp	ecx, [eax + fat_rootdir_bufsize$]
	jae	1f
	mov	edx, [eax + fat_rootdir_buf$]
	jmp	2f
0:

	cmp	ecx, [eax + fat_bufsize$]
	jae	1f
	mov	edx, [eax + fat_buf$]

2:
	.if FS_FAT_DEBUG > 2
		DEBUG "fat_nextentry"
		DEBUG_DWORD edx
		DEBUG_DWORD ecx
	.endif
	add	edx, ecx
	cmp	byte ptr [edx], 0
	stc
	jz	1f

	call	fat16_make_fs_entry
	add	ecx, 32
	jmp	0f

1:	mov	ecx, -1
	stc
0:	ret


# in: edi = fs dir entry struct (out)
# in: edx = fat dir entry
fat16_make_fs_entry:
	push	ecx

	push	eax
	push	esi
	push	edi

	mov	esi, edx
	lea	edi, [edi + fs_dirent_name]
	mov	ecx, 8
0:	lodsb
	cmp	al, ' '
	jz	0f
	stosb
	loop	0b
0:	
	lea	esi, [edx + 8]
	lodsb
	cmp	al, ' '
	jz	2f
	mov	byte ptr [edi], '.'
	inc	edi
	stosb
	.rept 2
	lodsb
	cmp	al, ' '
	jz	2f
	stosb
	.endr

2:	xor	al,al
	stosb

	pop	edi
	pop	esi
	pop	eax

	mov	cl, [edx + FAT_DIR_ATTRIB]
	mov	[edi + fs_dirent_attr], cl
	mov	ecx, [edx + FAT_DIR_SIZE]
	mov	[edi + fs_dirent_size], ecx
	mov	[edi + fs_dirent_size + 4], dword ptr 0
	pop	ecx
	ret


# in: eax = fs info
# in: ebx = filehandle
# in: edi = buf
# in: ecx = buf size
fs_fat16_read:
	push	eax
	push	ebx
	push	ecx
	push	edi
	add	ecx, 511
	shr	ecx, 9
	# TODO: read sectors using the FAT table...
	push	edx
	mov	edx, ebx
	call	fs_fat16_cluster_to_sector$
	add	ebx, [eax + fs_obj_p_start_lba]
	pop	edx
	mov	al, [eax + fs_obj_disk]
	call	ata_read
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
	jc	9f
	ret
9:	printc 4, "fs_fat16_read: read error"
	stc
	ret

# in: eax = fs info
# in: esi = cluster buffer
# in: ecx = buffer size
fs_fat16_print_directory$:
	push	esi
	push	ebx
	push	ecx
	push	edx
	push	eax

	mov	edx, esi
	add	edx, ecx
0:	
	cmp	byte ptr [esi], 0
	jz	0f

	push	edx

	PRINT	"Name: "	# space padded
	mov	ecx, 11
	call	nprint

	PRINT	" Attr "
	mov	dl, [esi + FAT_DIR_ATTRIB]
	call	printhex2
	.data
		9: .ascii "RHSVDA78"
	.text32
	mov	ebx, offset 9b
	mov	ecx, 8
2:	mov	al, ' '
	shr	dl, 1
	jnc	3f
	mov	al, [ebx]
3:	call	printchar
	inc	ebx
	loop	2b
	

	PRINT	" Cluster "
	mov	dx, [esi + FAT_DIR_HI_CLUSTER]
	shl	edx, 16
	mov	dx, [esi + FAT_DIR_CLUSTER]
	call	printhex8

	PRINT	" Size: "
	mov	edx, [esi + FAT_DIR_SIZE]
	call	printdec32
	call	newline

	pop	edx
	add	esi, 32
	cmp	esi, edx
	jb	0b
0:	
	pop	eax
	pop	edx
	pop	ecx
	pop	ebx
	pop	esi
	ret

############################################################################

# in: esi points to partition table entry
fs_fat_partinfo:
	push	esi	# save partition table ptr
	sub	esp, 512
	mov	ebp, esp

	mov	ebx, [esi + PT_LBA_START]
	mov	ecx, 1
	mov	edi, ebp
	# al = drive
	call	ata_read
	jc	9f

	# VBR - Volume Boot Record

	# Print BIOS Parameter Block - BPB

	lea	esi, [ebp + 3]
	PRINTc 15, "OEM Identifier: "
	mov	ecx, 8
	call	nprint
	call	newline

	lea	esi, [ebp + 11]

	.macro BPB_B label
		PRINTc 15, "\label: 0x"
		lodsb
		mov	dl, al
		call	printhex2
		call	newline
	.endm

	.macro BPB_W label
		PRINTc 15, "\label: 0x"
		lodsw
		mov	dx, ax
		call	printhex4
		call	newline
	.endm

	.macro BPB_D label
		PRINTc 15, "\label: 0x"
		lodsd
		mov	edx, eax
		call	printhex8
		call	newline
	.endm

	BPB_W "Bytes/Sector"
	BPB_B "Sectors/Cluster"
	BPB_W "Reserved sectors" # includes boot record
	BPB_B "FATs" 
	BPB_W "Directory Entries"
	BPB_W "Total Sectors"	 # max 64k, 0 for > 64k
	BPB_B "Media Descriptor Type"
	BPB_W "Sectors/FAT" # Fat12/16 only
	BPB_W "Sectors/Track"
	BPB_W "Heads"
	BPB_D "Hidden Sectors / LBA start"
	BPB_D "Total Sectors (large)"
call more
	println "EBPB:" # for fat12 and fat16; fat32 is different
	BPB_B "Drive Number"
	BPB_B "NT Flags"	# bit 0 = run chkdsk, bit 1 = run surface scan
	BPB_B "Signature (0x28 or 0x29)"
	BPB_D "Volume ID Serial"

	PRINTc 15, "Volume Label: "
	push esi
	mov	ecx, 11
	call	nprint
	pop esi
	add esi, 11
	call	newline

	PRINTc 15, "System Identifier: "
	push esi
	mov	ecx, 8
	call	nprint
	pop esi
	# check whether fat16/fat12
	lodsd
	cmp	eax, ('F'<<24) | ('A'<<16) | ('T'<< 8) | '1'
	lodsd
	jnz	0f
	cmp	eax, (0x20202000)|'6'
	jz	0f
1:	PRINTLNc 4, "Warning: System identifier unknown (not FAT16)"
0:
	#add	esi, 8
	call	newline



	# verify
	mov	esi, ebp
	mov	ebx, [esp + 512]

	mov	eax, [ebx + PT_LBA_START]
	cmp	eax, [esi + BPB_HIDDEN_SECTORS]
	jz	0f
	PRINTLNc 4, "Error: Partition Table LBA start != BPB Hidden sectors"
0:	
	movzx	eax, word ptr [esi + BPB_SMALL_SECTORS]
	or	eax, eax
	jnz	1f
	mov	eax, [esi + BPB_LARGE_SECTORS]
1:	cmp	eax, [ebx + PT_SECTORS]
	jz	0f
	PRINTLNc 4, "Error: Partition table numsectors != BPB num sectors"
0:

	mov	dl, [esi + BPB_FATS]
	or	dl, dl
	jnz	0f
	PRINTLNc 4, "Error: Number of FATS in BPB is zero"
0:	cmp	dl, 2
	jbe	0f
	PRINTc 4, "WARNING: more than 2 fats: 0x"
	call	printhex2
	call	newline
0:

	.struct 0
	tmp_fat_lba$: .long 0
	tmp_fat_clustersize$: .long 0	# sectors per cluster
	tmp_fat_sectorsize$: .long 0	# 0x200
	tmp_fat_sectors$: .long 0		# sectors per fat
	tmp_fat_root_lba$: .long 0
	tmp_fat_user_lba$: .long 0
	TMP_FAT_STRUCT_SIZE = .
	.text32

	sub	esp, TMP_FAT_STRUCT_SIZE


	## Calculate start of first FAT
	movzx	eax, word ptr [esi + BPB_RESERVED_SECTORS]
	add	eax, [esi + BPB_HIDDEN_SECTORS]	# LBA start
DEBUG "FAT start sector"
DEBUG_DWORD eax
	# this should point to the first sector after the partition boot record

	mov	[esp + tmp_fat_lba$], eax
DEBUG "fat lba"
DEBUG_DWORD eax
	# now we add sectors per fat:
	movzx	edx, word ptr [esi + BPB_SECTORS_PER_FAT]
DEBUG "sectors/fat"
DEBUG_DWORD edx
	mov	[esp + tmp_fat_sectors$], edx
	movzx	ecx, byte ptr [esi + BPB_FATS]
DEBUG "fats"
DEBUG_WORD cx
	jecxz	1f
0:	add	eax, edx
	loop	0b
1:
	# movzx eax, [esi+BPB_SECTORS_PER_FAT]
	# movzx edx, byte ptr [esi+BPB_FATS]
	# mul edx
	# add eax, [esp + tmp_fat_lba$]

	# now eax points just after the fat, which is where
	# the root directory begins.
	mov	[esp + tmp_fat_root_lba$], eax

DEBUG "root lba"
DEBUG_DWORD eax
call newline


DEBUG "Root Directory size:"

	# calculate size of root dir:
	movzx	edx, word ptr [esi + BPB_ROOT_ENTRIES]
DEBUG_DWORD edx
	# and we multiply it by the size of directory entries: 32 bytes.
	shl	edx, 5

DEBUG_DWORD edx
	# add the bytes-per-sector -1 to round up
	push	ecx
	movzx	ecx, word ptr [esi + BPB_BYTES_PER_SECTOR]
	jecxz	0f
DEBUG_DWORD ecx
	add	edx, ecx
	dec	edx
	xor	eax, eax
	xchg	edx, eax
	# divide by bytes per sector
	div	ecx
0:	pop	ecx
DEBUG_DWORD eax
DEBUG_DWORD edx

	# now we add the sector just after the fat to it
	add	eax, [esp + tmp_fat_root_lba$]
	mov	[esp + tmp_fat_user_lba$], eax

	movzx	eax, byte ptr [esi + BPB_SECTORS_PER_CLUSTER]
	mov	[esp + tmp_fat_clustersize$], eax
	movzx	eax, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[esp + tmp_fat_sectorsize$], eax


	PRINTc 10, "FAT LBA: "
	mov	edx, [esp + tmp_fat_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Root Directory: "
	mov	edx, [esp + tmp_fat_root_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Userdata LBA: "
	mov	edx, [esp + tmp_fat_user_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	add	esp, TMP_FAT_STRUCT_SIZE

9:	add	esp, 512
	pop	esi
	ret


############################################################################

