.intel_syntax noprefix
.code32

.data
# Theis list contains the ata device number
ata_drives$: .byte -1, -1, -1, -1, -1, -1, -1, -1
ata_num_drives$: .byte -1

# This contains the ata device partition buffers, 512 bytes for all
# drives that are in use.
# Ata device numbers are  different from ata_drives!
# ata drive number is translated early on to ata device number, for the
# ata_* API.
ata_device_partition_buf$: .long 0,0,0,0,0,0,0,0
.text

## Shell utilities ##########################################################
# in: eax = al = ata device number
# out: edi = 512 byte buffer
partition_get_buf$:
	push	eax
	movzx	eax, al
	mov	edi, [ata_device_partition_buf$ + eax * 4]
	or	edi, edi
	jnz	0f
	mov	eax, 1024
	call	malloc
	mov	edi, eax
	mov	[ata_device_partition_buf$], edi
0:	pop	eax
	ret


#####################################
disks_init$:
	cmp	[ata_num_drives$], byte ptr -1
	jne	1f

	push	edi
	push	esi
	push	ecx
	push	eax
	mov	edi, offset ata_drives$
	mov	esi, offset ata_drive_types
	mov	ecx, 8
0:	lodsb
	or	al, al
	jz	2f
	#cmp	al, TYPE_ATA
	#jnz	2f
	mov	al, 8
	sub	al, cl
	stosb
2:	loop	0b
	sub	edi, offset ata_drives$
	mov	eax, edi
	mov	[ata_num_drives$], al
	pop	eax
	pop	ecx
	pop	esi
	pop	edi
1:	ret

disks_print$:
	call	disks_init$
	push	esi
	push	edx
	push	ecx
	push	eax

	mov	dl, [ata_num_drives$]
	call	printhex1
	print	" ATA drive(s): "

	movzx	ecx, dl
	mov	esi, offset ata_drives$
	xor	ah, ah
0:	mov	dl, ah
	call	printhex1

	mov	dl, [esi]
	print	" (hd"
	mov	al, dl
	add	al, 'a'
	call	printchar
	print	") "

	inc	ah
	inc	esi
	loop	0b

	call	newline

	pop	eax
	pop	ecx
	pop	edx
	pop	esi
	ret
	
#####################################
# Reads and prints the MBR

# Returns the ATA device number for the given disk number. If there
# are two disks recorded, say hda and hdc, disk 0 will be hda, disk 1 hdc.
# This method may be removed at some point.
#
# in: al = recorded disk number 
# out: eax = al = ATA device number (bus<<1|device), 0=hda, 1=hdb, 2=hdc etc
# NOTE: this is translated to an ata device number for the ata routines.
get_ata_drive$:
	call	disks_init$
	movzx	eax, al
	cmp	al, [ata_num_drives$]
	jb	1f
0:	printc	4, "Unknown disk: "
	push	edx
	mov	edx, eax
	call	printdec32
	call	newline
	pop	edx
	stc
	ret
1:	mov	al, [ata_drives$ + eax]
	clc
	ret

# in: esi = pointer to string-arguments
cmd_fdisk$:
	cmp	[esi + 4], dword ptr 0
	jne	1f
0:	printlnc 12, "Usage: fdisk <drive number>"
	printlnc 12, "Run 'disks' to see available disks."
	ret

1:	mov	eax, [esi + 4]
	call	atoi
	jc	0b

	call	get_ata_drive$
	jc	0b

	printc	9, "Partition table for hd"
	push	eax
	add	al, 'a'
	call	printchar
	pop	eax

	call	newline

	call	disk_load_partition_table$

	# uses esi
	call	fdisk_check_parttable$
	ret

# in: al = ATA device number
# out: esi = partition table buffer
disk_load_partition_table$:
	push	edi
	push	ecx
	push	ebx
	call	partition_get_buf$
	mov	esi, edi	# return value
	mov	ecx, 1		# 1 sector
	mov	ebx, 0		# lba 0
	call	ata_read
	pop	ebx
	pop	ecx
	pop	edi
	jc	read_error$
	ret

fdisk_check_parttable$:
	# check for bootsector
	mov	dx, [esi + 512 - 2]
	cmp	dx, 0xaa55
	je	1f
	PRINTLNc 10, "No Partition Table"
	stc
	ret

1:	add	esi, 446 # offset to MBR
	COLOR 7
	xor	cl, cl

	PRINTLN	"Part | Stat | C/H/S Start | C/H/S End | Type | LBA Start | LBA End | Sectors  |"
	COLOR 8
0:	
	xor	edx, edx
	PRINT " "
	mov	dl, cl		# partition number
	call	printhex1
	PRINTc  7, "   | "

	lodsb			# Status
	mov	dl, al
	call	printhex2
	PRINTc	7, "   | "

DEBUG_CHS = 0
	.macro PRINT_CHS
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

	.endm

	PRINT_CHS		# CHS start
	PRINTc	7, "     | "

	lodsb		# partition type
	mov	ah, al
	
	PRINT_CHS		# CHS end
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
	and	eax, 0xffffff
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


	inc	cl
	cmp	cl, 4
	jb	0b

	# carry clear here (jc == jb)
	ret


# in: al = disk (ATA device number), ah = partition
# out: eax = pointer to partition table entry
disk_get_partition:
	call	disks_init$ 

	push	esi
	push	ecx

	mov	esi, offset ata_drives$
	movzx	ecx, byte ptr [ata_num_drives$]
0:	cmp	al, [esi]
	jz	0f
	inc	esi
	loop	0b
	pushcolor 4
	print "Unknown disk hd"
	add	al, 'a'
	call	printchar
	sub	al, 'a'
	popcolor
	call	newline
	stc

1:	pop	ecx
	pop	esi
	ret
0:	# the disk pans out.
	# load the partition table for the disk:
	push	eax
	call	disk_load_partition_table$

	# partition table integrity check
	push	esi
	call	fdisk_check_parttable$
	pop	esi
	pop	eax
	jc	1b	# partition table malformed

	movzx	eax, ah
	cmp	al, 4
	jb	0f
	printc 4, "Extended partitions not supported yet: partition "
	push	edx
	mov	edx, eax
	call	printdec32
	pop	edx
	call	newline
	jmp	1b
0:
	shl	eax, 4
	add	eax, 446
	add	eax, esi
	clc
	jmp	1b

#####################################
# Reads and prints the VBR (Volume Boot Record) for all partitions (for now)

.text

cmd_partinfo$:
	mov	eax, [esi + 4]
	or	eax, eax
	jnz	1f
0:	printlnc 12, "Usage: partinfo <drive number>"
	ret
1:	call	atoi
	jc	0b
	call	get_ata_drive$
	jc	0b

	printc	10, "Partition table for hd"
	push	eax
	add	al, 'a'
	call	printchar
	pop	eax
	call	newline

	# load bootsector/MBR

	call	partition_get_buf$ # mov	edi, offset tmp_buf$
	mov	esi, edi	# backup
	mov	ecx, 2	# was 2
	mov	ebx, 0
	call	ata_read
	jc	read_error$


	# find partition
.macro DEBUG_PART_BUF
	print " buf: "
	mov edx, esi
	call printhex8
	call newline
	push	esi
	add	esi, 446
	mov	ecx, 4
0:	mov	edx, [esi + 0xc]
	call	printhex8
	mov	al, ' '
	call	printchar
	add	esi, 16
	loop	0b
	call	newline
	pop	esi
.endm

#	DEBUG_PART_BUF

	mov	ecx, 4

	add	esi, 446
0:	cmp	[esi + 0xc], dword ptr 0	# num sectors
	jz	1f
	# ok, check if partition type supported:

	mov	al, [esi + 4]	# partition type
	cmp	al, 6		# FAT16B
	jz	ls_fat16b$

1:	add	esi, 16
	loop	0b
	PRINTLNc 4, "No recognizable partitions found (run fdisk)"
	ret

#############################################################################


# Partition Table
.struct 0
PT_STATUS: .byte 0
PT_CHS_START: .byte 0,0,0
PT_TYPE: .byte 0
PT_CHS_END: .byte 0,0,0
PT_LBA_START: .long 0
PT_SECTORS: .long 0
.text



#############################################################################


# in: eax = [00] [Cyl[2] Sect[6]] [Cyl] [head]
# this format is for ease of loading from a partition table
chs_to_lba:
	# LBA = ( cyl * maxheads + head ) * maxsectors + ( sectors - 1 )
	# cyl: 1024
	# head: 16
	# sect: 64
	and	eax, 0xffffff
	jnz	0f	# when CHS = 0, also return LBA 0 (as CHS 0 is invalid)
	ret
0:

	push	edx
	push	ebx

			# 0 CS C H
	ror	eax, 8	# H 0 CS C
	xchg	al, ah	# H 0 C CS

	mov	edx, eax
	.if DEBUG_CHS
		pushcolor 11
		call printhex8
		popcolor
	.endif

	xor	edx, edx
	mov	dx, ax
	shr	dh, 6		# dx = cyl
	.if DEBUG_CHS
		PRINTCHAR 'C'
		call	printhex8
	.endif

	shl	edx, 4	# * maxheads (16)
	.if DEBUG_CHS
		pushcolor 3
		call printhex4
		popcolor
	.endif
	mov	ebx, eax
	shr	ebx, 24	# ebx = bl = head
	add	edx, ebx
	.if DEBUG_CHS
		PRINT " H"
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
		PRINT " S"
		push edx
		mov	edx, ebx
		call	printhex8
		pop edx
		PRINTCHAR ' '
	.endif

	dec	edx
	mov	eax, edx

	pop	ebx
	pop	edx
	.if DEBUG_CHS
		popcolor
	.endif
	
	ret

#############################################################################
