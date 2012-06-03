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
	print	" drive(s): "

	movzx	ecx, dl
	mov	esi, offset ata_drives$
	xor	ah, ah
0:	
	movzx	edx, ah		# disk index
	call	printdec32

	mov	dl, [esi]	# ata drive number
	mov	dh, [ata_drive_types - ata_drives$ + esi] # drive type

#######
	push	esi
	
	LOAD_TXT " (hd"
	call	print

	mov	al, dl
	add	al, 'a'
	call	printchar
	call	printspace

	LOAD_TXT "ATA"
	cmp	dh, TYPE_ATA
	jz	1f
	LOAD_TXT "ATAPI"
	cmp	dh, TYPE_ATAPI
	jz	1f
	LOAD_TXT "UNKNOWN: "
	call	printhex2
1:	call	print

	LOAD_TXT ") "
	call	print

	pop	esi
#######

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


getopt:
	mov	eax, [esi]
	cmp	byte ptr [eax], '-'
	clc
	jz	0f
	stc
0:	ret

# in: esi = pointer to string-arguments
# destroys: ecx
cmd_fdisk$:
	cmp	[esi + 4], dword ptr 0
	jne	1f
0:	printlnc 12, "Usage: fdisk [-l] <drive>"
	printlnc 12, " -l:    large: use 255 heads in CHS/LBA calculations"
	printlnc 12, "        for harddisks larger than 0x100000 sectors (512Mb)"
	printlnc 12, " drive: disk number, or hdX with X lowercase alpha"
	printlnc 12, "Run 'disks' to see available disks."
	ret

1:	
	mov	ecx, 16		# 16 heads

	add	esi, 4
	call	getopt
	jc	1f
	add	esi, 4
	cmp	word ptr [eax + 1], 'l'
	jnz	0b
	mov	cl, 255

1:	# edx = maxheads

	mov	eax, [esi]

	call	parse_drivename
	jnc	1f

		# defunct
		call	atoi
		jc	0b
		call	get_ata_drive$
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
	mov	ebx, offset fdisk_init$
	.data
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

	printc	9, "fdisk hd"
	push	eax
	add	al, 'a'
	call	printchar
	pop	eax

	printc 9, "; capacity: "
	push	eax
	push	ebx
	push	edx
	call	ata_get_capacity	# out: edx,eax

	# check if capacity >= 512 mb:

	LBA_H16_LIM = 1024 * 16 * 63	# fc000

	cmp	eax, LBA_H16_LIM
	jb	1f
	print	"(using 255 heads) "
	mov	ecx, 255
1:
	mov	ebx, 1024*1024/512	# mb
	div	ebx
	mov	edx, eax
	call	printdec32
	print	"Mb"

	pop	edx
	pop	ebx
	pop	eax

	call	newline

	call	disk_load_partition_table$

#######
	or	ebx, ebx
	jz	1f
	add	ebx, [realsegflat]
	jmp	ebx
1:
	call	fdisk_check_parttable$
	ret


fdisk_init$:
	push	eax
	push	ecx
	printlnc 11, "fdisk initialize"

	call	fdisk_check_parttable$
	jc	1f
	printlnc 0xcf, "WARNING: Overwriting partition table!"
1:
	printc 0xc1, "Are you sure?"
	
	mov	ecx, 2
0:	printc 0xc1, " Type 'Yes' if so: "
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

0:	printc 13, "Writing partition table to disk hd"
	pop	ecx
	pop	eax
	add	al, 'a'
	call	printchar
	sub	al, 'a'
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
# in: al = ATA device number
# out: esi = partition table buffer
disk_load_partition_table$:
	push	edi
	push	eax
	push	ebx
	push	ecx
	push	edx
	call	partition_get_buf$
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

# in: esi
# out: CF
fdisk_check_parttable$:
	# check for bootsector
	cmp	word ptr [esi + 512 - 2], 0xaa55
	je	1f
	PRINTLNc 12, "No Partition Table"
	stc
	ret

1:	push	esi
	push	edx
	push	ecx
	push	ebx
	push	eax

	add	esi, 446 # offset to MBR
	COLOR 7
	xor	bl, bl

	PRINTLN	"Part | Stat | C/H/S Start | C/H/S End | Type | LBA Start | LBA End | Sectors  |"
	COLOR 8
0:	
	xor	edx, edx
	PRINT " "
	mov	dl, bl		# partition number
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

	call	chs_to_lba_internal$
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
	call	chs_to_lba_internal$
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
	call	chs_to_lba_internal$
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


	inc	bl
	cmp	bl, 4
	jb	0b

	# carry clear here (jc == jb)

	pop	eax
	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
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

chs_to_lba:
	push	ecx
	mov	ecx, 16
	call	chs_to_lba_internal$
	pop	ecx
	ret

chs_to_lba255:
	push	ecx
	mov	ecx, 255
	call	chs_to_lba_internal$
	pop	ecx
	ret

# bytes in partition table (H S C): h[8] | c[2] s[6] | c[8]
# in: eax = [00] | [Cyl] | [Cyl[2] Sect[6]] | [head]
# in: ecx = maxheads (16 or 255)
# this format is for ease of loading from a partition table
chs_to_lba_internal$:

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

