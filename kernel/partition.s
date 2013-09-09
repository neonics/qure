.intel_syntax noprefix
.code32

PARTITION_DEBUG = 0

# Partition Table
.struct 0
PT_STATUS: .byte 0
PT_CHS_START: .byte 0,0,0
PT_TYPE: .byte 0
PT_CHS_END: .byte 0,0,0
PT_LBA_START: .long 0
PT_SECTORS: .long 0

# Partition types:
# 0x00	Empty
# 0x01	FAT12 max 32Mb
# 0x04	FAT16 max 64k sectors (32Mb)
# 0x05	Extended partition (CHS)
# 0x06	FAT16b min 64k sectors first 8Gb or within 0x0f logical
#	FAT16 / FAT12 beyond first 32Mb
# 0x07	IFS / HPFS / NTFS / exFAT / QNX
# 0x08	FAT12/FAT16 logical sectored; OS/2 / AIX / QNY
# 0x0b	FAT32 CHS
# 0x0c	FAT32X LBA
# 0x0e	FAT16X LBA
# 0x0f	Extended partition LBA
# 0x11	FAT12/FAT16 logical sectored / Hidden FAT12 (0x01)
#
# 0x41	DR DOS Linux
# 0x42	DR DOS Linux swap
# 0x43	DR DOS Linux native
#
# 0x82	Linux swap (0x42)
# 0x83	Linux (0x43)
# 0x84	MS Hibernation
# 0x85	Linux extended
# 0x86	MS Legacy FAT16
# 0x87	MS Legacy NTFS
# 0x88	Linux plaintext
#
# 0x8b	MS Legacy FT FAT32
# 0x8c	MS Legacy FT FAT32 LBA
# 0x8d	FreeDOS hidden FAT12 (0x01)
# 0x8e	Linux LVM
# 0x90	Freedos Hidden FAT16 (0x04)
# 0x91	Freedos Hidden extended CHS (0x05)
# 0x92	Freedos Hidden FAT16B (0x06)
# 
# 0x97	Hidden FAT32 (0x0b)
# 0x97	Hidden FAT32 (0x0b)

# http://en.wikipedia.org/wiki/GUID_Partition_Table
.struct 0 #GUID Parition Table - LBA 1  (LBA 0 remains MBR, with 1 0xEE part)
gpt_sig:	.long 0,0	# signature	"EFI PART"
gpt_rev:	.long 0		# revision	0,0,1,0
gpt_hsize:	.long 0		# header size	5c,0,0,0  (92 bytes)
gpt_crc32:	.long 0
gpt_reserved:	.long 0
gpt_cur_lba:	.long 0, 0
gpt_bkp_lba:	.long 0, 0
gpt_first_lba:	.long 0, 0	# prim ptable last lba +1
gpt_last_lba:	.long 0, 0	# sec ptable first lba -1
gpt_disk_guid:	.space 16
gpt_pt_lba:	.long 0, 0	# parttion entries lba - 2 in prim
gpt_pt_num:	.long 0
gpt_pt_entsize:	.long 0		# size of partition entry (128)
gpt_pt_crc32:	.long 0		# crc of partition array
# the rest of the block is reserved (420 bytes for 512b)

.struct 0
gpte_type_guid:	.space 16
	# EFI System	{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}
	# The first 3 blocks are stored little endian:
	#   28 73 2a c1 - 1f f8 - d2 11 
	# the last 2 blocks are as is:
	#   ba 4b - 00 a0 c9 3e c9 3b
gpte_uniq_guid:	.space 16 # unique partition guid
gpte_first_lba:	.long 0, 0
gpte_last_lba:	.long 0, 0	# inclusice
gpte_attr:	.long 0, 0	# bit 60 = readonly
	GPTE_ATTR_BIT_SYSTEM = 0
	GPTE_ATTR_BIT_BOOTABLE = 2
	GPTE_ATTR_RO = 60
	GPTE_ATTR_H  = 62
	GPTE_ATTR_NO_AUTO_MOUNT = 63
gpte_name:	.space 72	# 36 UTF-16LE chars


MAX_PARTITIONS = 64

.data
# This contains the ata device partition buffers, 512 bytes for all
# drives that are in use.
disk_br_buf$: .space ATA_MAX_DRIVES * 4	# 8 long's

disk_ptables$: .space ATA_MAX_DRIVES * 4
.text32
#####################################

# little proxy for ata elevation
.global disk_read
disk_read:
	push	eax
	mov	eax, cs
	and	al, 3
	pop	eax
	jz	ata_read
	KAPI_CALL disk_read
	ret

KAPI_DECLARE disk_read
	jmp	ata_read


.global disk_write
disk_write:
	push	eax
	mov	eax, cs
	and	al, 3
	pop	eax
	jz	ata_write
	KAPI_CALL disk_write
	ret

KAPI_DECLARE disk_write
	jmp	ata_write


# in: al = ATA device number
# out: esi = pointer to the ptables info for the disk: all partition tables
#  for the disk, concatenated: MBR, and optionally EBR's. esi is an array.
disk_read_partition_tables:
	call	ata_is_disk_known
	jc	9f

	push	eax
	push	ecx
	push	ebx
	push	edi

	.if PARTITION_DEBUG
		DEBUG "read ptables"
		DEBUG_R16 ax
	.endif

	movzx	ebx, al
	mov	ebx, dword ptr [disk_ptables$ + ebx * 4]
	or	ebx, ebx
	jz	1f
	# reset array to zero size
	mov	[ebx + array_index], dword ptr 0
1:
	xor	ebx, ebx	# first sector
	call	disk_load_partition_table$	# out: esi = ptable in MBR/EBR
	jc	1f
	# copy the info
	call	disk_ptables_append$	# in: esi, out: esi = array

	# check for extended partition info:
	xor	ecx, ecx
0:	mov	bl, [esi + ecx + PT_TYPE]
	cmp	bl, 0x05	# extended partition
	jz	4f
	cmp	bl, 0x91	# extended linux partition (same as 0x05)
	jz	4f
	cmp	bl, 0x85	# extended linux partition CHS
	jz	4f
	cmp	bl, 0x0f	# extended partition LBA
	jz	4f
5:	add	ecx, 16
	cmp	ecx, [esi + array_index]
	jb	0b
	clc
1:	pop	edi
	pop	ebx
	pop	ecx
	pop	eax
9:	ret

4:	mov	ebx, [esi + PT_LBA_START]
	call	disk_load_partition_table$
	jc	1b
	call	disk_ptables_append$
	jmp	5b


# in: al = disk
# in: ebx = LBA of sector (bootsector or extended partition sector)
# out: CF = failure (error already printed)
# out: esi = offset to partition table structure
disk_load_partition_table$:
	.if PARTITION_DEBUG
		DEBUG "load ptable"
		DEBUG_R16 ax
	.endif
	call	ata_is_disk_known
	jc	disk_err_unknown_disk$

	push	edi
	push	ecx

	# get a sector buffer
	call	disk_get_br_buf$	# in: al; out: edi
	jc	1f

	mov	esi, edi	# save for ptable verify/print

	# load the MBR
	mov	ecx, 1		# 1 sector
	push	eax		# preserve drive
	push	edx
	call	ata_read	# in: al, ebx, ecx, edi;
	pop	edx
	pop	eax
	jc	1f

	push	eax
	call	ata_get_hs_geometry
	pop	eax
	call	disk_br_verify$	# in: ecx, esi
	jc	2f
	add	esi, 446
	clc

1:
	pop	ecx
	pop	edi
0:	ret

2:	call	newline
	call	disk_ptable_print$	# in: ecx, esi
	# sets carry on error (which is why this code is run)
	jmp	1b


#############################################################

disk_err_unknown_disk$:
	printc	4, "unknown disk: "
	call	disk_print_label
	stc
	ret

############################################################

# in: eax = al = ata device number
# out: edi = 512 byte buffer
disk_get_br_buf$:
	push	ebx
	push	ecx
	mov	ebx, offset disk_br_buf$
	mov	ecx, 512
	call	disk_get_buf_$
	pop	ecx
	pop	ebx
	ret

# in: al = disk
# in: ebx = buffer offset
# in: ecx = size to allocate
# out: edi = buffer
disk_get_buf_$:
	cmp	al, ATA_MAX_DRIVES
	jae	disk_err_unknown_disk$

	push	eax
	movzx	eax, al
	mov	edi, [ebx + eax * 4]
	or	edi, edi
	jnz	0f
	push	eax
	mov	eax, ecx
	call	mallocz
	mov	edi, eax
	pop	eax
	mov	[ebx + eax * 4], edi
0:	clc
	pop	eax
	ret


# in: esi = pointer to partition table
# out: esi = base pointer to array
disk_ptables_append$:
	cmp	al, ATA_MAX_DRIVES
	jae	disk_err_unknown_disk$

	push	eax
	push	ebx
	push	ecx
	push	edx

	mov	ecx, 16 * 4	# entry size (4 partitions)
	movzx	ebx, al
	mov	eax, [ebx * 4 + disk_ptables$]
	or	eax, eax
	jnz	1f
	inc	eax		# eax=1; initial entries (conservative)
	call	array_new	# out: eax
1:	call	array_newentry	# in: eax, ecx; out: eax + edx
	mov	[disk_ptables$ + ebx * 4], eax
	mov	edi, eax
	add	edi, edx
	rep	movsb
	mov	esi, eax

	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

############################################################

DEBUG_CHS = 0

# TODO: in: eax = CHS structure as in partition table
# in: esi = points to 3 bytes with ptable CHS info
disk_print_chs$:
	.if DEBUG_CHS
		mov dl, [esi]
		call printhex2
		mov al, '-'
		call printchar
		mov dl, [esi+1]
		call printhex2
		mov al, '-'
		call printchar
		mov dl, [esi+2]
		call printhex2
		mov al, ' '
		call printchar
	.endif

	mov	dl, [esi + 1]	# 2 bits of cyl, 6 bits sector
	shl	edx, 2
	mov	dl, [esi + 2]	# 8 bits of cyl
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex4
		popcolor
	.endif
	mov	al, '/'
	call	printchar

	xor	dh, dh
	lodsb			# head
	mov	dl, al
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex2
		popcolor
	.endif
	mov	al, '/'
	call	printchar

	lodsb
	inc	esi
	mov	dl, al
	and	dl, 0b111111
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex2
		popcolor
	.endif
	ret


# in: esi = offset to partition table information
# in: ecx = maxcylinders << 16 | maxheads
# in: ebx = bl = number of 4-partion-groups to print. This is so it can
#   be used for the disk_ptables array aswell as for an MBR or EBR.
disk_ptables_print$:
	PUSHCOLOR 7
	push	esi
	push	edx
	push	ecx
	push	eax
	push	ebx

	PRINTLN	"Part | Stat | C/H/S Start | C/H/S End | Type | LBA Start | LBA End | Sectors  |"
	COLOR 8

0:	
	xor	edx, edx
	PRINT " "
	mov	dl, [esp]	# partition number
	sub	dl, bl
	call	printhex1
	PRINTc  7, "   | "

	lodsb			# Status
	mov	dl, al
	call	printhex2
	PRINTc	7, "   | "

	call	disk_print_chs$	# in: esi;  CHS start
	PRINTc	7, "     | "

	lodsb		# partition type
	mov	ah, al
	
	call	disk_print_chs$	# in: esi; CHS end
	PRINTc	7, "  | "

	mov	dl, ah		# Type
	call	printhex2
	PRINTc	7, "   | "

	lodsd			# LBA start
	mov	edx, eax
	call	printhex8
	PRINTc	7, "  | "

	mov	eax, [esi - 16 + 5 + 4]	# CHS end
	and	eax, 0x00ffffff

	call	chs_to_lba	# in: ecx=C H
	mov	edx, eax
	call	printhex8
	PRINTc	7, "| "

	lodsd			# Num Sectors
	mov	edx, eax
	call	printhex8
	PRINTLNc 7, " |"



	# verify LBA start
	mov	eax, [esi - 16 + 1]
	and	eax, 0x00ffffff
	mov	edx, eax
	call	chs_to_lba
	mov	edx, eax
	mov	eax, [esi - 16 + 8]
	cmp	edx, eax
	jz	1f
	PRINTc 4, "ERROR: CHS/LBA start mismatch: expect "
	call	printdec32
	PRINTc 4, ", got "
	mov	edx, eax
	call	printdec32
	call	newline
1:
	# if sectorcount zero, dont perform check
	cmp	dword ptr [esi - 4], 0
	jz	1f

	# verify num sectors:
	mov	eax, [esi - 16 + 5] # chs end
	and	eax, 0xffffff
	call	chs_to_lba
	inc	eax

	# subtract LBA start
	sub	edx, eax	# lba start - lba end
	neg	edx
	mov	eax, [esi - 16 + 0xc] # load num sectors
	cmp	eax, edx
	jz	1f
	PRINTc 4, "ERROR: CHS/LBA numsectors mismatch: expect "
	#call	printdec32
	call	printhex8
	PRINTc 4, ", got "
	mov	edx, eax
	#call	printdec32
	call	printhex8
	call	newline
1:
	dec	bl
	ja	0b

	# carry clear here (jc == jb)

	pop	ebx
	pop	eax
	pop	ecx
	pop	edx
	pop	esi
	POPCOLOR
	ret




# in: esi = pointer to string-arguments
# destroys: ecx
cmd_fdisk:
	cmp	[esi + 4], dword ptr 0
	jne	1f
fdisk_print_usage$:
0:	printlnc 12, "Usage: fdisk [-l] <drive> [cmd] [args]"
	printlnc 12, " -l:    large: use 255 heads in CHS/LBA calculations"
	printlnc 12, "        for harddisks larger than 0x100000 sectors (512Mb)"
	printlnc 12, "  cmd:  list - the default; lists the partition table"
	call	newline
	printlnc 12, "        init - writes the partition table"
	printlnc 12, "             args:  -t [nr]   : select partition, set partition type (hex)"
	printlnc 12, " drive: hdX with X lowercase alpha (hda, hdb, ...)"
	printlnc 12, "Run 'disks' to see available disks."
	ret

1:	
	printcharc 4, '!'
	mov	ecx, 16		# 16 heads

	add	esi, 4
	call	getopt
	jc	1f
	add	esi, 4
	cmp	word ptr [eax + 1], 'l'
	jnz	0b
	mov	cl, 255

1:	# ecx = maxheads

	printcharc 4, '!'

	lodsd
	call	disk_parse_drivename
	jc	0b
	mov	dx, ax	# remember partition/drive
1:
	# now check other arguments

#######
	push	eax

	xor	ebx, ebx	# command ptr

	lodsd
	or	eax, eax
	jz	1f

	CMD_ISARG "list"
	jz	1f

	CMD_ISARG "init"
	mov	ebx, offset fdisk_cmd_init$
	jz	1f

	# check for command
	printc	12, "illegal command: "
	push	esi
	mov	esi, eax
	call	println
	pop	esi
	stc
	pop	eax
	jmp	0b

1:	pop	eax

#######

	printc	9, "fdisk "
	call	disk_print_label
	printc 9, "; capacity: "
	push	eax
	push	edx
	call	disk_get_capacity
	call	print_size
	pop	edx
	pop	eax

	# check for ATA
	push	eax
	movzx	eax, al
#	cmp	byte ptr [ata_drive_types + eax], TYPE_ATAPI
	cmp	byte ptr [ata_drive_types + eax], TYPE_ATA
	pop	eax
	jz	1f
	printlnc 12, " unsupported drive type: not ATA"
	stc
	ret
1:

	push_	eax ebx esi edx
	call	ata_get_drive_info
	mov	ebx, eax
	printc	9, " geometry: "
	movzx	edx, word ptr [ebx + ata_driveinfo_c]
	call	printdec32
	printcharc_ 9, '/'
	movzx	edx, word ptr [ebx + ata_driveinfo_h]
	call	printdec32
	printcharc_ 9, '/'
	movzx	edx, word ptr [ebx + ata_driveinfo_s]
	call	printdec32
	mov	al, [esp]
	call	ata_get_hs_geometry
	cmp	cl, 255
	jnz	1f
	printc_	9, " ("
	mov	edx, 1023
	call	printdec32
	printcharc_ 9, '/'
	mov	dx, cx
	call	printdec32
	printcharc_ 9, '/'
	mov	edx, ecx
	shr	edx, 16
	call	printdec32
	printcharc_ 9, ')'
1:	call	newline
	pop_	edx esi ebx eax

#######
	or	ebx, ebx
	jz	1f

	.if 0
		DEBUG "call"
		DEBUG_DWORD ebx
		DEBUG_BYTE al
	.endif

	add	ebx, [realsegflat]
	jmp	ebx
1:
	call	disk_read_partition_tables
	jc	0f
	mov	ebx, [esi + buf_index]
	shr	ebx, 4
	call	ata_get_hs_geometry
	call	disk_ptables_print$
	ret
0:	printlnc 12, "error reading partition tables"
	ret

# in: dx = ax = partition/drive
fdisk_cmd_init$:
	mov	edi, 0x99
	mov	edx, eax

	lodsd
	or	eax, eax
	jz	0f
	CMD_ISARG "-t"
	jnz	fdisk_print_usage$
	lodsd
	call	htoi
	jc	fdisk_print_usage$
	mov	edi, eax
	cmp	edi, 255
	ja	fdisk_print_usage$
0:
	mov	eax, edx

	printlnc 11, "fdisk initialize"
	push	eax
	call	ata_get_hs_geometry	# get ecx
	pop	eax
	DEBUG_DWORD ecx

	xor	ebx, ebx	# first sector
	call	disk_load_partition_table$	# out: esi = ptable in MBR/EBR
	jnc	0f
	printlnc 4, "Error loading partition table"
	jmp	1f
0:	mov	ebx, 4
		call	disk_ptables_print$
	printlnc 0xcf, "WARNING: Overwriting partition table!"
1:
	print	"Writing bootsector to "
	call	disk_print_label

	call	reallysure
	jc	1f

	printc 13, "Writing partition table to "
	call	disk_print_label
	call	newline

	# prepare the bootsector
	push	eax
	mov	eax, 512
	call	mallocz
	mov	esi, eax
	pop	eax
	jc	1f

	mov	word ptr [esi + 512 - 2], 0xaa55
	mov	[esi + 446 + PT_STATUS], byte ptr 0x80
	mov	[esi + 446 + PT_CHS_START + 1], byte ptr 2
	mov	[esi + 446 + PT_TYPE], edi	# guaranteed to be <256
	mov	[esi + 446 + PT_LBA_START], dword ptr 1
	push	eax
	call	ata_get_capacity
DEBUG "cap"
DEBUG_DWORD edx
DEBUG_DWORD eax
call newline
.if 1
	shrd	eax, edx, 9
	shr	edx, 9
.else
	mov	al, dl
	ror	eax, 8
	shr	edx, 8
	shr	edx, 1
	sar	eax, 1
.endif
	or	edx, edx
	jz	2f
	printlnc 12, "Warning: Disk capacity too large, truncating"
	mov	eax, -1
2:	mov	[esi + 446 + PT_SECTORS], eax
	mov	al, [esp]	# restore drive nr
	call	ata_get_hs_geometry	# in: al; out: ecx
	call	lba_to_chs
	mov	[esi + 446 + PT_CHS_END], eax
	pop	eax
	mov	[esi + 446 + PT_LBA_START], dword ptr 1 # chs_end overwrites

	#

	mov	ecx, 1	# 1 sector
	mov	ebx, 0	# address 0
	push	esi
	call	ata_write
	pop	esi

	mov	eax, esi
	call	mfree
	
	ret

1:	printlnc 12, "Aborted."
	pop	eax
	ret


reallysure:
	push	ecx
	push	eax

	printc 0xc7, " Are you sure?"
	
	mov	ecx, 2
0:	printc 0xc1, " Type 'Yes' if so:"
	call	printspace

	mov	ah, offset KB_GETCHAR
	call	keyboard
	mov ah, 0xf0
	call	printchar
	cmp	al, 'Y'
	jnz	1f
	mov	ah, offset KB_GETCHAR
	call	keyboard
	call	printchar
	cmp	al, 'e'
	jnz	1f
	mov	ah, offset KB_GETCHAR
	call	keyboard
	call	printchar
	cmp	al, 's'
	jnz	1f
	mov	ah, offset KB_GETCHAR
	call	keyboard
	cmp	ax, K_ENTER
	jnz	1f
	call	newline

	dec	ecx
	clc	# odd that this is needed...
	jz	0f

	printc 0xc1, "Are you really sure?"
	jmp	0b
1:	stc
0:	pop	eax
	pop	ecx
	ret

# This method includes the verification from disk_br_verify.
#
# in: esi = bootsector
# in: ecx = number of cylinders << 16 | number of heads
# out: CF
disk_ptable_print$:
	# check for bootsector
	cmp	word ptr [esi + 512 - 2], 0xaa55
	je	1f
	printlnc 4, "invalid partition table"
	stc
	ret

1:	push	ebx
	mov	ebx, 1
	add	esi, 446
	call	disk_ptables_print$
	sub	esi, 446
	pop	ebx
	ret

# Silent version of disk_ptable_print$
#
# in: al = drive
# in: esi = pointer to MBR/EBR sector
# in: ecx = number of cylinders << 16 | number of heads
# out: CF
disk_br_verify$:
	# check for bootsector
	cmp	word ptr [esi + 512 - 2], 0xaa55
	je	1f
	stc
	ret

1:	push	esi
	push	edi
	push	edx
	push	ebx
	push	eax

	add	esi, 446 # offset to MBR
	xor	bl, bl
0:	
	# verify LBA start
	mov	eax, [esi + PT_CHS_START]
	and	eax, 0x00ffffff
	# TODO: verify C/H/S range
	mov	edx, eax
	call	chs_to_lba
	# eax = lba start
	cmp	eax, [esi + PT_LBA_START]
	jnz	0f	# CHS/LBA mismatch

	# if sectorcount zero, dont perform check
	cmp	dword ptr [esi + PT_SECTORS], 0
	jz	1f

	mov	edx, eax	# lba start

	# verify num sectors:
	mov	eax, [esi + PT_CHS_END]
	and	eax, 0xffffff
	# TODO: verify C/H/S range
	call	chs_to_lba
	inc	eax

	# subtract LBA start
	sub	eax, edx	# lba end - lba start = numsectors
	sub	eax, [esi + PT_SECTORS]
	jnz	0f		# chs end-start != numsectors

	add	esi, 16

	inc	bl
	cmp	bl, 4
	jb	0b

	# carry clear here (jc == jb)

1:	pop	eax
	pop	ebx
	pop	edx
	pop	edi
	pop	esi
	ret

0:	stc
	jmp	1b

# in: al = disk (ATA device number), ah = partition (-1: entire disk;0:first)
# out: esi = pointer to partition table entry
# out: CF
disk_get_partition:
	.if PARTITION_DEBUG
		DEBUG "get partition"
		DEBUG_BYTE al
		DEBUG_BYTE ah
	.endif

	call	ata_is_disk_known
	jc	1f

	cmp	ah, -1
	jnz	0f

	.data
	fake_partition: .space 16
	.text32
	push	eax
	push	edx

	call	disk_get_capacity
	jc	9f
	shrd	eax, edx, 9	# shr eax,9, fill with edx
	shr	edx, 9

	mov	esi, offset fake_partition
	mov	[esi + PT_STATUS], byte ptr 0
	mov	[esi + PT_CHS_START], dword ptr 0	# 3 bytes
	mov	[esi + PT_TYPE], byte ptr 0
	mov	[esi + PT_CHS_END], dword ptr 0	# 3 bytes
	mov	[esi + PT_LBA_START], dword ptr 0 # or 1
	mov	[esi + PT_SECTORS], eax
9:	pop	edx
	pop	eax
1:	ret

0:	call	disk_read_partition_tables
	jc	1f
	movzx	esi, al
	mov	esi, [disk_ptables$ + esi * 4]
	push	edx
	movzx	edx, ah
	shl	edx, 4
	cmp	edx, [esi + array_index]
	jb	2f
	printc 4, "unknown partition: "
	call	disk_print_label
2:	add	esi, edx
	pop	edx
	ret

1:	printlnc 4, "disk_get_partition: failed to load ptable"
	stc
	ret


	# load the partition table for the disk:
	push	esi
	call	disk_load_partition_table$

	push	ecx
	push	eax
	call	ata_get_hs_geometry
	pop	eax
	call	disk_br_verify$

	jc	3f	# partition table malformed

	cmp	ah, 4
	jae	4f

	movzx	eax, ah
	shl	eax, 4
	add	eax, 446
	add	eax, esi
	cmp	[eax + PT_SECTORS], dword ptr 0
	stc
	jz	5f

	clc

0:	pop	esi

1:	pop	ecx
9:	ret

3:	
DEBUG "err"
DEBUG_DWORD ecx
	call	disk_ptable_print$	# prints the errors
	jmp	0b

4:	printc 4, "Extended partitions not supported yet: partition "
	push	edx
	movzx	edx, ah
	call	printdec32
	pop	edx
	call	newline
	stc
	jmp	0b

5:	printlnc 4, "empty partition"
	stc
	jmp	0b

#####################################

cmd_partinfo$:
	mov	eax, [esi + 4]
	or	eax, eax
	jnz	1f
0:	printlnc 12, "Usage: partinfo <hdXn>"
	ret

1:	call	disk_parse_partition_label
	jc	0b

	call	disk_print_label
	printc	11, ": "

	mov	dl, al	# preserve disk (al)
	call	disk_get_partition
	jc	0b
	mov	al, dl

	# check for known partition types
	

	mov	dl, [esi + PT_TYPE]
	call	fs_fat_is_partition_supported
	cmp	dl, 6		# FAT16B
	jz	fs_fat_partinfo
	#jz	0f

	printc 12, "unknown partition type: "
	movzx	edx, al
	call	printdec32
	call	newline
	ret

0:
	ret

# in: dl = partition type
fs_fat_is_partition_supported:
	cmp	dl, 6
0:	ret


#############################################################################

# in: al = ata drive nr
# out: edx:eax
# out: CF
disk_get_capacity:
	call	ata_is_disk_known
	jc	9f
	movzx	edx, al
	mov	dl, [ata_drive_types + edx]

	cmp	dl, TYPE_ATA
	jz	ata_get_capacity
	cmp	dl, TYPE_ATAPI
	jz	atapi_get_capacity

	printc	12, "disk_get_capacity: unknown drive type: "
	call	printhex2
	stc
9:	ret

#############################################################################

# in: eax = pointer to drive name
# expects 'hdX', anything else prints error.
disk_parse_drivename:
	push	edx
	push	ebx
	push	esi
	push	eax	# for error message

	mov	esi, eax
	lodsw
	cmp	ax, ('d'<<8)|'h'
	jnz	2f

	lodsb
	sub	al, 'a'
	js	3f
	cmp	al, 25
	ja	3f

	mov	ah, -1
	cmp	byte ptr [esi], 0
	jz	0f
#jmp 1f # parse partition nr
	mov	ebx, esi
	LOAD_TXT "trailing characters"
	jmp	5f

# in: eax = pointer to 'hda' type string
# out: al = ata drive number, ah = partition (-1)
disk_parse_label:
	push	edx
	push	ebx
	push	esi
	push	eax	# for error message

	mov	esi, eax
	lodsw
	cmp	ax, ('d'<<8)|'h'
	jnz	2f

	lodsb
	sub	al, 'a'
	js	3f
	cmp	al, 25
	ja	3f
	mov	dl, al

	mov	ah, -1
	cmp	byte ptr [esi], 0
	jz	0f	# okay
	jmp	1f

# in: eax = pointer to 'hda0' type string
# out: al = drive, ah = partition
disk_parse_partition_label:
	push	edx
	push	ebx
	push	esi
	push	eax	# for error message
	mov	esi, eax

	mov	ebx, esi	# for error message
	lodsw
	cmp	ax, ('d'<<8)|'h'
	jnz	2f

	mov	ebx, esi	# for error message
	lodsb
	sub	al, 'a'
	js	3f
	cmp	al, 25
	ja	3f
	mov	dl, al
	
	# now, parse the partition. might be two decimals (extended etc..)
1:	mov	ebx, esi	# for error message
	mov	eax, esi
	call	atoi
	jc	4f
	cmp	eax, 255
	jae	1f
	shl	eax, 8
	mov	al, dl

	clc
0:	pop	esi	# for error message
	pop	esi
	pop	ebx
	pop	edx
	ret
4:	LOAD_TXT "partition string not number"
	jmp	5f
3:	LOAD_TXT "drive number not lowercase alpha"
	jmp	5f
2:	LOAD_TXT "not starting with 'hd'"
	jmp	5f
1:	LOAD_TXT "invalid partition number"

5:	printc	12, "parse error: '"
	push	esi
	# print original string
	mov	esi, [esp + 4]
	call	print
	printc	12, "': "
	pop	esi
	# print error message
	call	print
	# print remainder of string
	printc	12, ": '"
	mov	esi, ebx
	call	print
	printcharc 12, '\''
	call	newline
	stc
	jmp	0b



# in: al = disk, ah = partition (or -1)
disk_print_label:
	push	edx
	push	eax
	print	"hd"
	add	al, 'a'
	call	printchar
	cmp	ah, -1
	je	1f
	movzx	edx, ah
	call	printdec32
1:	pop	eax
	pop	edx
	ret


#############################################################################

DEBUG_CHS = 0

# bytes in partition table (H S C): h[8] | c[2] s[6] | c[8]
# in: eax = [00] | [Cyl] | [Cyl[2] Sect[6]] | [head]
# in: ecx = number of sectors << 16 | number of heads
# this format is for ease of loading from a partition table
chs_to_lba:
	# LBA = ( cyl * maxheads + head ) * maxsectors + ( sectors - 1 )
	# cyl: 1024
	# head: 16
	# sect: 64
	and	eax, 0x00ffffff
	jnz	0f	# when CHS = 0, also return LBA 0 (as CHS 0 is invalid)
	ret
0:
	push	edx
	push	ebx

			# 0 C CS H
	ror	eax, 8	# H 0 C CS
	xchg	al, ah	# H 0 CS C

	mov	edx, eax

	.if DEBUG_CHS
		pushcolor 11
		call printhex8
		popcolor
	.endif

	movzx	edx, ax
	shr	dh, 6		# dx = cyl

	.if DEBUG_CHS
		PRINT "C="
		call	printhex8
	.endif

	push	eax
	movzx	eax, dx
	movzx	ebx, cx
	mul	ebx	# ebx = maxheads
	mov	edx, eax
	pop	eax

	.if DEBUG_CHS
		pushcolor 3
		call printhex4
		popcolor
	.endif

	mov	ebx, eax
	shr	ebx, 24	# ebx = bl = head
	add	edx, ebx

	.if DEBUG_CHS
		PRINT " H="
		push edx
		mov	edx, ebx
		call	printhex8
		pop edx
	.endif

	.if 1
	push	eax
	mov	eax, edx
	mov	edx, ecx
	shr	edx, 16
	mul	edx
	mov	edx, eax
	pop	eax
	.else
	mov	ebx, edx	# * 63:
	shl	edx, 6	# * max sectors (64)
	sub	edx, ebx
	.endif

	.if DEBUG_CHS
		pushcolor 3
		call printhex4
		popcolor
	.endif

	mov	bl, ah
	and	ebx, 0b111111
	add	edx, ebx
	.if DEBUG_CHS
		PRINT " S="
		push edx
		mov	edx, ebx
		call	printhex8
		pop edx
		PRINTCHAR ' '
	.endif

	dec	edx
	mov	eax, edx

	.if DEBUG_CHS
		PRINT " LBA="
		call	printhex8
	.endif

	pop	ebx
	pop	edx
	
	ret

#############################################################################

# Cylinders:	10 bits	-> 1023
# Heads:	8 bits	-> 255
# Sectors:	6 bits	-> 63
# 24 bits (16.7M) * 512 b (+9 bits) = 33 bits
# Encoding in Partition Record: H[7:0] | C[9:8] S[5:0] | C[7:0]

# in: eax = LBA
# in: ecx = number of cylinders << 16 | number of heads
# out: eax = 00 | [cyl8] | Cyl[2] Sect[6] | head[8]
# this format is for ease of loading from a partition table
lba_to_chs:
	# LBA = ( cyl * maxheads + head ) * maxsectors + ( sectors - 1 )
	# cyl: 1024
	# head: 16
	# sect: 64
	and	eax, 0x00ffffff
	jnz	0f	# when CHS = 0, also return LBA 0 (as CHS 0 is invalid)
	ret
0:
	push	edx
	push	ebx
	push	ecx

	inc	eax
	# eax = max 24 bits
	mov	ebx, ecx		# max sectors
	shr	ebx, 16
	xor	edx, edx
	div	ebx
	# dl = sectors
	# eax = max 18 bits, clear edx
	# eax = cyl * maxheads + head
	movzx	ebx, cx		# max heads
	mov	cl, dl		# cl = sectors
	xor	edx, edx
	div	ebx
	# dl = heads
	# eax = max 10 bits, cyl

.if 0 # DEBUG_CHS
push edx
print "H="
call printhex8
print " C="
mov edx, eax
call printhex8
print " S="
movzx edx, cl
call printhex8
call newline
pop edx
.endif

	# out: eax = 00 | cyl[8] | Cyl[2] Sect[6] | head[8]
	# convert:
	# ax = cylinders
	# dl = heads
	# cl = sectors

	shl	ah, 6
	or	ah, cl
	xchg	al, ah
	shl	eax, 8
	mov	al, dl

	pop	ecx
	pop	ebx
	pop	edx
	ret

