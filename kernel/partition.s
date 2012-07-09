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

MAX_PARTITIONS = 64

.data
# This contains the ata device partition buffers, 512 bytes for all
# drives that are in use.
disk_br_buf$: .space ATA_MAX_DRIVES * 4	# 8 long's

disk_ptables$: .space ATA_MAX_DRIVES * 4
.text
#####################################

# in: al = ATA device number
# out: esi = pointer to the ptables info for the disk: all partition tables
#  for the disk, concatenated: MBR, and optionally EBR's. esi is an array.
disk_read_partition_tables:
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
	ret

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

	call	ata_get_heads	# in: al; out: ecx
	call	disk_br_verify$	# in: ecx, esi
	jc	2f

	add	esi, 446
	clc

1:	pop	ecx
	pop	edi
0:	ret

2:	call	disk_ptable_print$
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
	call	malloc
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

.if 0
# in: al = ATA device number
# out: esi = partition table buffer
disk_load_partition_table$:
	push	edi
	push	eax
	push	ebx
	push	ecx
	push	edx
	call	disk_get_br_buf$
	mov	esi, edi	# return value
	mov	ecx, 1		# 1 sector
	mov	ebx, 0		# lba 0
	call	ata_read
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	pop	edi
	jc	read_error$
	ret
.endif
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
# in: ecx = number of heads to use for calulations
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
	mov	dl, [esp]		# partition number
	sub	dl, bl
	call	printhex1
	PRINTc  7, "   | "

	lodsb			# Status
	mov	dl, al
	call	printhex2
	PRINTc	7, "   | "

	call	disk_print_chs$	# CHS start
	PRINTc	7, "     | "

	lodsb		# partition type
	mov	ah, al
	
	call	disk_print_chs$	# CHS end
	PRINTc	7, "  | "

	mov	dl, ah		# Type
	call	printhex2
	PRINTc	7, "   | "

	lodsd			# LBA start
	mov	edx, eax
	call	printhex8
	PRINTc	7, "  | "

	mov	eax, [esi - 16 + 5 + 4]	# LBA end
	and	eax, 0xffffff

	call	chs_to_lba
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
	POPCOLOR 7
	ret




# in: esi = pointer to string-arguments
# destroys: ecx
cmd_fdisk$:
	cmp	[esi + 4], dword ptr 0
	jne	1f
0:	printlnc 12, "Usage: fdisk [-l] <drive>"
	printlnc 12, " -l:    large: use 255 heads in CHS/LBA calculations"
	printlnc 12, "        for harddisks larger than 0x100000 sectors (512Mb)"
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

	mov	eax, [esi]

	call	disk_parse_drivename
	jc	0b

1:
	# now check other arguments

#######
	push	eax

	xor	ebx, ebx	# command ptr

	add	esi, 4
	mov	eax, [esi]
	or	eax, eax
	jz	1f

	# check for command
	push	esi
	mov	esi, eax
	mov	ebx, offset fdisk_cmd_init$
	.data SECTION_DATA_STRINGS
	9: .asciz "init"
	.text
	mov	edi, offset 9b

	push	ecx
	call	strlen
	mov	ecx, eax
	repz	cmpsb
	pop	ecx
	pop	esi
	jz	1f
	
	printc	12, "illegal command: "
	push	esi
	mov	esi, [esi]
	call	println
	pop	esi
	pop	eax
	stc
	jmp	0b


1:	pop	eax

#######

	printc	9, "fdisk "
	call	disk_print_label

	printc 9, "; capacity: "
	call	ata_print_capacity

	push	edx
	print	" (using "
	call	ata_get_heads
	mov	edx, ecx
	call	printdec32
	println	" heads)"
	pop	edx

	call	disk_read_partition_tables
	jc	0f
#######
	or	ebx, ebx
	jz	1f
	add	ebx, [realsegflat]
	jmp	ebx
1:
	mov	ebx, [esi + buf_index]
	shr	ebx, 4
	call	disk_ptables_print$
	ret
0:	printlnc 12, "error reading partition tables"
	ret

fdisk_cmd_init$:
	push	eax
	push	ecx
	printlnc 11, "fdisk initialize"

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
	printc 0xc1, " Are you sure?"
	
	mov	ecx, 2
0:	printc 0xc1, " Type 'Yes' if so:"
	call	printspace

	mov	ah, KB_GETCHAR
	call	keyboard
	call	printchar
	cmp	al, 'Y'
	jnz	1f
	mov	ah, KB_GETCHAR
	call	keyboard
	call	printchar
	cmp	al, 'e'
	jnz	1f
	mov	ah, KB_GETCHAR
	call	keyboard
	call	printchar
	cmp	al, 's'
	jnz	1f
	mov	ah, KB_GETCHAR
	call	keyboard
	cmp	ax, K_ENTER
	jnz	1f
	call	newline

	dec	ecx
	jz	0f

	printc 0xc1, "Are you really sure?"
	jmp	0b

0:	printc 13, "Writing partition table to "
	pop	ecx
	pop	eax
	call	disk_print_label
	call	newline

	.data
	9: .space 446
	8: #.space 16
		.byte 0x80
		.byte 0, 2, 0
		.byte 6
		.byte 0, 0, 0
		.long 1
		.long 0
	7: .space 16
	6: .space 16
	5: .space 16
	.byte 0x55, 0xaa
	.text

	push	eax
	call	ata_get_capacity
	or	edx, edx
	jz	2f
	printlnc 12, "Warning: Disk capacity too large, truncating"
	mov	eax, -1
2:	mov	edx, eax
	call	lba_to_chs
	mov	[8b + PT_CHS_END], eax
	pop	eax

	mov	[8b + PT_LBA_START], dword ptr 1
	mov	[8b + PT_SECTORS], edx


	#

	mov	esi, offset 9b
	mov	ecx, 1	# 1 sector
	mov	ebx, 0	# address 0
	call	ata_write
	
	ret

1:	printlnc 12, "Aborted."
	pop	eax
	ret

# This method includes the verification from disk_br_verify.
#
# in: esi = bootsector
# in: ecx = number of heads
# out: CF
disk_ptable_print$:
	# check for bootsector
	cmp	word ptr [esi + 512 - 2], 0xaa55
	je	1f
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
# in: esi = pointer to MBR/EBR sector
# in: ecx = number of heads
# out: CF
disk_br_verify$:
	# check for bootsector
	cmp	word ptr [esi + 512 - 2], 0xaa55
	je	1f
	stc
	ret

1:	push	esi
	push	edx
	push	ebx
	push	eax

	add	esi, 446 # offset to MBR
	xor	bl, bl

0:	
	# verify LBA start
	mov	eax, [esi + PT_CHS_START]
	and	eax, 0x00ffffff
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
	pop	esi
	ret

0:	stc
	jmp	1b

# in: al = disk (ATA device number), ah = partition
# out: esi = pointer to partition table entry
# out: CF
disk_get_partition:
	.if PARTITION_DEBUG
		DEBUG "get partition"
		DEBUG_BYTE al
		DEBUG_BYTE dl
	.endif

	call	disk_read_partition_tables
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
	call	ata_get_heads
	call	disk_br_verify$
	pop	eax
	pop	ecx

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
1:	ret

3:	call	disk_ptable_print$	# prints the errors
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

DEBUG_BYTE al
	call	disk_print_label
	printc	11, ": "

DEBUG_BYTE al
	mov	dl, al	# preserve disk (al)
	call	disk_get_partition
	jc	0b
	mov	al, dl
DEBUG "pi: "
DEBUG_BYTE al
	# check for known partition types

	mov	dl, [esi + PT_TYPE]
	call	fs_fat_is_partition_supported
	cmp	dl, 6		# FAT16B
	jz	ls_fat16b$
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

# in: eax = pointer to 'hda' type string
# out: al = ata drive number, ah = partition (-1)
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

	mov	ebx, esi
	LOAD_TXT "trailing characters"
	jmp	5f

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
	mov	ebx, esi	# for error message
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


# bytes in partition table (H S C): h[8] | c[2] s[6] | c[8]
# in: eax = [00] | [Cyl] | [Cyl[2] Sect[6]] | [head]
# in: ecx = maxheads (16 or 255)
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

	.if 0
	shl	edx, 4	# * maxheads (16)
	.else
	push	eax
	movzx	eax, dx
	mul	ecx	# ecx = maxheads
	mov	edx, eax
	pop	eax
	.endif
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

	mov	ebx, edx	# * 63:
	shl	edx, 6	# * max sectors (64)
	sub	edx, ebx
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
# in: ecx = maxheads
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


	.if 0	# this is specified by ecx parameter
	# check for max size (C = 1023 H = 16 S = 63) = 503Mb

	#	$lba = (($c * $hpc) + $h) * $spt + $s - 1;

		mov	ecx, 16	# 16 heads
		cmp	eax, LBA_H16_LIM
		jbe	0f
		mov	ecx, 255 # heads
		printc 4, "Using 255 heads"
		# LBA = ( cyl * maxheads + head ) * maxsectors + ( sectors - 1 )
	0:

	.endif

	inc	eax

	# eax = max 24 bits
	mov	ebx, 63		# max sectors
	xor	edx, edx
	div	ebx

	# dl = sectors
	# eax = max 18 bits, clear edx
	# eax = cyl * maxheads + head
	mov	ebx, ecx	# max heads
	mov	cl, dl		# cl = sectors
	xor	edx, edx
	div	ebx

	# dl = heads
	# eax = max 10 bits, cyl

.if DEBUG_CHS
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

