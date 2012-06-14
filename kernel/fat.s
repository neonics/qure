##############################################################################
# FAT File System (FAT16, FAT32)
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


.data
fs_fat16_class:
.long fs_fat16b_mount	# constructor
.long fs_fat16b_umount	# destructor
.long fs_fat16_opendir
.long fs_fat16_close

.struct 0
fs_class:		.long 0

fat_disk$:		.byte 0
fat_partition$:		.byte 0

fat_partition_start_lba$:.long 0
fat_partition_size_sectors$: .long 0
fat_partition_end_lba$:	.long 0

fat_buf$:		.long 0
fat_fatbuf$:		.long 0

# The LBA addresses here are partition-relative: add fat_partition_start_lba.
fat_lba$:		.long 0
fat_clustersize$:	.long 0	# sectors per cluster
fat_sectorsize$:	.long 0	# 0x200
fat_sectors$:		.long 0		# sectors per fat
fat_root_lba$:		.long 0
fat_root_size_sectors$:	.long 0
fat_user_lba$:		.long 0	# first data sector
FAT_STRUCT_SIZE = .

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

.struct 0 # Long file name entries are placed immediately before the 8.3 entry
FAT_DIR_LONG_SEQ: .byte 0 # sequence nr; 0x40 bit means it is last also
FAT_DIR_LONG_NAME1: .space 10	# 5 2-byte chars
FAT_DIR_LONG_ATTRIB: .byte 0 # 0xf for long filenames
FAT_DIR_LONG_TYPE: .byte 0	# 0 for name entires
FAT_DIR_LONG_CKSUM: .byte 0
FAT_DIR_LONG_NAME2: .space 12 # 6 2-byte characteres
	.word 0 # always 0
FAT_DIR_NAME3: .space 4	# final 2 2-byte characters (total: 5+6+2=13)

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
.text

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
	call	malloc
	mov	edi, eax
	pop	eax
	mov	[edi + fat_disk$], ax
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

	mov	[edi + fs_class], dword ptr offset fs_fat16_class

	# allocate a sector buffer
	push	eax
	mov	eax, 512
	call	malloc
	mov	[edi + fat_buf$], eax
	pop	eax

###	# allocate the fat buffer
	push	ecx

##
	push	eax
	push	edx
	mov	edx, [edi + fat_sectorsize$]
	mov	eax, [edi + fat_sectors$]
	mul	edx

	# we'll assume for the malloc that the size is < 4Gb
	push	eax
	call	malloc
	mov	[edi + fat_fatbuf$], eax
	pop	eax

	# divide by 512 to calculate disk sectors (if it differs)
	shr	edx, 1
	sar	eax, 1
	mov	al, dl
	ror	eax, 8

	DEBUG_DWORD eax

	# load this many sectors

	mov	ecx, eax

	pop	edx
	pop	eax
##

	push	ebx
	push	edi

		DEBUG "Load "
		DEBUG_DWORD ecx
		DEBUG "sectors at LBA "

	mov	ebx, [edi + fat_lba$]
	add	ebx, [edi + fat_partition_start_lba$]
		DEBUG_DWORD ebx

	mov	al, [edi + fat_disk$]
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
.text


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
	mov	[edi + fat_partition_start_lba$], eax

	# partition size
	movzx	edx, word ptr [esi + BPB_SMALL_SECTORS]
	or	edx, edx
	jnz	1f
	mov	edx, [esi + BPB_LARGE_SECTORS]
1:	mov	[edi + fat_partition_size_sectors$], edx
	# partition end
	add	edx, eax
	mov	[edi + fat_partition_end_lba$], edx


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
	movzx	eax, word ptr [esi + BPB_BYTES_PER_SECTOR]
	mov	[edi + fat_sectorsize$], eax


	PRINTc 10, "FAT LBA: "
	mov	edx, [edi + fat_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	add	edx, [edi + fat_partition_start_lba$]
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
	add	edx, [edi + fat_partition_start_lba$]
	shl	edx, 9
	call	printhex8
	PRINTc 10, " Size: "
	mov	edx, [edi + fat_root_size_sectors$]
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Userdata LBA: "
	mov	edx, [edi + fat_user_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	add	edx, [edi + fat_partition_start_lba$]
	shl	edx, 9
	call	printhex8
	call	newline

	pop	edx
	pop	ecx
	pop	eax
	ret

############################################################################
# fs_fat class - virtual method pointers:

# in: eax = pointer to fs_instance structure
# in: ebx = directory handle (-1 for root)
# in: esi = directory name
# out: ebx = directory handle
fs_fat16_opendir:

	.if FS_DEBUG > 1
		DEBUG "fs_instance"
		DEBUG_DWORD eax

		pushcolor 0xf1
		print	"fs_fat16_opendir("
		call	print
		print ")"
		popcolor

		DEBUG_DWORD ebx
		call newline
	.endif

	cmp	ebx, -1
	jnz	0f

	# load root directory
##
	mov	ebx, [eax + fat_root_lba$]
	call	fs_fat16_load_directory$
	jc	1f
	call	fs_fat16_print_directory$
	clc
	jmp	1f

0:
##
	# load the directory
	# in: eax = fs_instance structure, ebx = dir handle
	call	fs_fat16_load_directory$
	jc	1f
	# call	fs_fat16_print_directory$


	# find subdirectory

	push	edi

	call	fs_fat16_find_entry$	# out: CF, edi = pointer to entry
	jc	2f

# FAT_DIR_NAME: .space 11	# 8 + 3
# FAT_DIR_ATTRIB: .byte 0 # RO=1 H=2 SYS=4 VOL=8 DIR=10 A=20  (0F=long fname)
# 	.byte 0 # reserved by NT
# 	# creation time
# FAT_DIR_CTIME_DECISECOND: .byte 0 # tenths of a second
# FAT_DIR_CTIME: .word 0	# Hour: 5 bits, minuts 6 bits, seconds 5 bits
# FAT_DIR_CDATE: .word 0 # year 7 bits, month 4 bits, day 5 bits
# FAT_DIR_ADATE: .word 0 # last accessed date
# FAT_DIR_HI_CLUSTER: .word 0 # 0 for fat12/fat16
# FAT_DIR_MTIME: .word 0 # modification time
# FAT_DIR_MDATE: .word 0
# FAT_DIR_CLUSTER: .word 0
# FAT_DIR_SIZE: .long 0	# filesize in bytes
	push	edx

	mov	dx, [edi + FAT_DIR_HI_CLUSTER]
	shl	edx, 16
	mov	dx, [edi + FAT_DIR_CLUSTER]

	.if 0
		call	newline
		DEBUG "Clusters: "
		call	printhex8
		call	printspace
	0:	call	fs_fat16_get_next_cluster$
		call	printhex8
		call	printspace
		cmp	dx, -1
		jnz	0b
	.endif

	call	fs_fat16_cluster_to_sector$	# in: eax, edx; out: ebx
	call	fs_fat16_load_directory$
	jc	3f

	call	fs_fat16_print_directory$
	clc
3:	pop	edx
2:	pop	edi
##

1:	ret


# in: eax = fs_instance
# in: ebx = directory/file handle
fs_fat16_close:
	# release resources
	ret


# in: eax = pointer to fs_instance
# in: edx = cluster
fs_fat16_get_next_cluster$:
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
	movzx	edx, word ptr [eax + edx * 2]
	pop	eax
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
	stc
	ret


# in: eax = fs_instance
# in: esi = directory to find
# out: edi = pointer to directory entry
fs_fat16_find_entry$:

	.if FS_DEBUG > 1
		DEBUG "find "
		DEBUGS
		DEBUG_DWORD eax
	.endif

	push	ecx
	push	edx
	push	eax

	mov	edi, [eax + fat_buf$]
	mov	edx, edi
	add	edx, 512

	mov	eax, esi
	call	strlen
	mov	ecx, eax

0:	cmp	byte ptr [edi], 0
	stc
	jz	1f

	.if FS_DEBUG > 1
	DEBUGS
		push esi
		push ecx
		mov esi, edi
		mov ecx, 11
		call nprint
		pop ecx
		pop esi
	.endif

	
	push	esi
	push	edi
	push	ecx
	repz	cmpsb
	jnz	3f
	cmp	[edi + ecx], byte ptr 0x20
3:	pop	ecx
	pop	edi
	pop	esi
	jz	2f

	add	edi, 32
	cmp	edi, edx
	jb	0b
	stc
	jmp	1f

2:	.if FS_DEBUG  >1
		DEBUG "found:"
		#sub	edi, edx
		#DEBUG_DWORD edi
		DEBUG "Cluster: "
		mov	dx, [edi + FAT_DIR_HI_CLUSTER]
		shl	edx, 16
		mov	dx, [edi + FAT_DIR_CLUSTER]
		DEBUG_DWORD edx
	.endif

	clc
1:	pop	eax
	pop	edx
	pop	ecx
	ret


# in: eax = fs_instance pointer
# in: ebx = directory handle (LBA address)
# out: edi = buffer
fs_fat16_load_directory$:
	push	eax
	push	ebx
	push	ecx
	push	edi
	mov	ecx, 1
	add	ebx, [eax + fat_partition_start_lba$]
	mov	edi, [eax + fat_buf$]
	mov	al, [eax + fat_disk$]
	call	ata_read
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
	ret

#fat_lba$:		.long 0
#fat_clustersize$:	.long 0	# sectors per cluster
#fat_sectorsize$:	.long 0	# 0x200
#fat_sectors$:		.long 0		# sectors per fat
#fat_root_lba$:		.long 0
#fat_user_lba$:		.long 0




fs_fat16_print_directory$:
	push	esi
	push	ebx
	push	ecx
	push	edx
	push	eax

	mov	esi, [eax + fat_buf$]
	mov	edx, esi
	add	edx, 512

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
	.text
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
	mov	dx, [esi + FAT_DIR_CLUSTER]
	call	printhex4

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

#  OLD CODE

############

.data
tmp_part$: .long 0
fat$: .space 512
.text

# in: esi points to partition table entry
ls_fat16b$:
	mov	[tmp_part$], esi	# save partition table ptr
	mov	ebx, [esi + PT_LBA_START]
	mov	ecx, 1
	mov	edi, offset fat$
	# al = drive
	call	ata_read
	jc	read_error$

	# VBR - Volume Boot Record

	# Print BIOS Parameter Block - BPB

	mov	esi, offset fat$ + 3
	PRINTc 15, "OEM Identifier: "
	mov	ecx, 8
	call	nprint
	call	newline

	mov	esi, offset fat$ + 11

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
	mov	esi, offset fat$
	mov	ebx, [tmp_part$]

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

	.data
	tmp_fat_lba$: .long 0
	tmp_fat_clustersize$: .long 0	# sectors per cluster
	tmp_fat_sectorsize$: .long 0	# 0x200
	tmp_fat_sectors$: .long 0		# sectors per fat
	tmp_fat_root_lba$: .long 0
	tmp_fat_user_lba$: .long 0
	.text
	## Calculate start of first FAT
	movzx	eax, word ptr [esi + BPB_RESERVED_SECTORS]
	add	eax, [esi + BPB_HIDDEN_SECTORS]	# LBA start
DEBUG "FAT start sector"
DEBUG_DWORD eax
	# this should point to the first sector after the partition boot record

	mov	[tmp_fat_lba$], eax
DEBUG "fat lba"
DEBUG_DWORD eax
	# now we add sectors per fat:
	movzx	edx, word ptr [esi + BPB_SECTORS_PER_FAT]
DEBUG "sectors/fat"
DEBUG_DWORD edx
	mov	[tmp_fat_sectors$], edx
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
	# add eax, [tmp_fat_lba$]

	# now eax points just after the fat, which is where
	# the root directory begins.
	mov	[tmp_fat_root_lba$], eax

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
	add	eax, [tmp_fat_root_lba$]
	mov	[tmp_fat_user_lba$], eax

	movzx	eax, byte ptr [esi + BPB_SECTORS_PER_CLUSTER]
	mov	[tmp_fat_clustersize$], eax
	movzx	eax, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[tmp_fat_sectorsize$], eax


	PRINTc 10, "FAT LBA: "
	mov	edx, [tmp_fat_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Root Directory: "
	mov	edx, [tmp_fat_root_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Userdata LBA: "
	mov	edx, [tmp_fat_user_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline
	ret


