
.data 2
tmp_part$: .long 0
fat$: .space 512
.text
ls_fat16b$:
	mov	[tmp_part$], esi	# save partition table ptr
	mov	eax, [esi + 8]	# LBA start
	mov	ebx, eax
	mov	ecx, 1
	mov	al, [tmp_drv$]
	mov	edi, offset fat$
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
.text
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
	fat_lba$: .long 0
	fat_clustersize$: .long 0	# sectors per cluster
	fat_sectorsize$: .long 0	# 0x200
	fat_sectors$: .long 0		# sectors per fat
	fat_root_lba$: .long 0
	fat_user_lba$: .long 0
	.text
	## Calculate start of first FAT
	movzx	eax, word ptr [esi + BPB_RESERVED_SECTORS]
	add	eax, [esi + BPB_HIDDEN_SECTORS]	# LBA start
	# this should point to the first sector after the partition boot record

	mov	[fat_lba$], eax

	# now we add sectors per fat:
	movzx	edx, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[fat_sectors$], edx
	movzx	ecx, byte ptr [esi + BPB_FATS]
	jecxz	1f
0:	add	eax, edx
	loop	0b
1:
	# movzx eax, [esi+BPB_SECTORS_PER_FAT]
	# movzx edx, byte ptr [esi+BPB_FATS]
	# mul edx
	# add eax, [fat_lba$]

	# now eax points just after the fat, which is where
	# the root directory begins.
	mov	[fat_root_lba$], eax

	# now we add the size of the root directory to it.
	movzx	edx, word ptr [esi + BPB_ROOT_ENTRIES]
	# and we multiply it by the size of directory entries: 32 bytes.
	shl	edx, 5
	add	eax, edx
	mov	[fat_user_lba$], eax

	movzx	eax, byte ptr [esi + BPB_SECTORS_PER_CLUSTER]
	mov	[fat_clustersize$], eax
	movzx	eax, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[fat_sectorsize$], eax


	PRINTc 10, "FAT LBA: "
	mov	edx, [fat_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Root Directory: "
	mov	edx, [fat_root_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Userdata LBA: "
	mov	edx, [fat_user_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline
	ret

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



fat_find_dir:
	ret

