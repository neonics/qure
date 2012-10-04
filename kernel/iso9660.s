##############################################################################
# ISO 9660 File System
#
.intel_syntax noprefix

##############################################################################

ISO9660_VOLDESC_BOOT		= 0
ISO9660_VOLDESC_PRIMARY		= 1
ISO9660_VOLDESC_ENHANCED	= 2
ISO9660_VOLDESC_PARTITION	= 3


##############################################################################
.data
fs_iso9660_class:
.long fs_iso9660_mount
.long fs_iso9660_umount
.long fs_iso9660_open
.long fs_iso9660_close
.long fs_iso9660_nextentry
.long fs_iso9660_read

.struct FS_OBJ_STRUCT_SIZE
iso_buf$:	.long 0

.text32
fs_iso9660_umount:
fs_iso9660_open:
fs_iso9660_close:
fs_iso9660_nextentry:
fs_iso9660_read:
	printlnc 12, "iso9660: not implemented"
	stc
	ret

# in: ax = disk/partition
# in: esi = partition info
# out: edi = pointer to filesystem structure
fs_iso9660_mount:
	DEBUG_WORD ax
	printc 12, "iso9660_mount: not implemented"
	stc
	ret



###########################################################################
iso9660_test:
	
	mov	esi, offset ata_drive_types
	mov	ecx, 8
	mov	dh, -1
0:	lodsb
	cmp	al, TYPE_ATAPI
	jne	1f
	mov	dh, 8
	sub	dh, cl
1:	loop	0b

	cmp	dh, -1
	jne	0f

	PRINTln	"No ATAPI device detected"
	ret
0:
	# convert drive index to bus+drive
	mov	al, dh
	.if 0
	mov	ah, dh
	mov	al, ah
	shr	ah, 1
	and	al, 1
	.endif
	# load edx with the ports
	call	ata_get_ports$
.data
atapi_al: .byte 0
atapi_edx: .long 0
.text32
	mov	[atapi_al], al
	mov	[atapi_edx], edx

##################################################################
	println "read capacity"
	DEBUG_BYTE al
	push	edx
	push	eax
	call	atapi_read_capacity$
	pop	eax
	pop	edx

	println "read volume descriptor"
	# Read Primary Volume Descriptor
	mov	eax, ecx # block len
	call	malloc
	jc	iso_err$
	mov	edi, eax
	mov	[iso_root], eax
	mov	ebx, 16	# LBA
	#mov	ecx, 1 	# sectors
	mov	al, [atapi_al]
	mov	edx, [atapi_edx]

	call	atapi_read12$
	jc	iso_err$

################################################################
	PRINTc	11, "Volume descriptor type: "
	push	edx
	movzx	edx, byte ptr [esi]
	call	printhex2
	call	printspace
	cmp	dl, 4
	jae	1f
	.data
	iso9660_voldesc_labels$:
	STRINGPTR "Boot Record"
	STRINGPTR "Primary Volume Descriptor"
	STRINGPTR "Supplementary/Enhanced Volume Descriptor"
	STRINGPTR "Volume Partition Descriptor"
	.text32
	push	esi
	mov	esi, [iso9660_voldesc_labels$ + edx * 4]
	call	print
	pop	esi
	jmp	2f
1:	printc 4, "[reserved]"
2:	pop	edx
	call	newline
################################################################
	cmp	byte ptr [esi], ISO9660_VOLDESC_BOOT
	jz	iso_print_boot$
	cmp	byte ptr [esi], ISO9660_VOLDESC_PRIMARY
	jz	iso_print_primary$
	cmp	byte ptr [esi], ISO9660_VOLDESC_ENHANCED
	jz	iso_print_enhanced$
	cmp	byte ptr [esi], ISO9660_VOLDESC_PARTITION
	jz	iso_print_partition$
	ret
################################################################
iso_print_boot$:
iso_print_enhanced$:
iso_print_partition$:
	ret


################################################################
iso_print_primary$:
	PRINTc	11, "Standard Identifier: "
	mov	ecx, 5
	inc	esi
	call	nprint
	dec	esi
	call	newline
################################################################
.data
iso_logical_block_size: .long 0
iso_path_table_lba: .long 0
iso_path_table: .long 0
iso_root: .long 0
iso_cur_pt_lba:.long 0
.text32
	movzx	ebx, word ptr [esi + 140]	# LSB path table location
	mov	[iso_path_table_lba], ebx
	mov	[iso_cur_pt_lba],ebx
	push	eax
	movzx	eax, word ptr [esi + 128]	# logical block size
	mov	[iso_logical_block_size], eax
	call	malloc
	mov	edi, eax
	mov	[iso_path_table], eax
	pop	eax
	jc	iso_err$
	call	atapi_read12$
	jc	iso_err$

	# print directory structure

iso_print_path_table:
	xor	ebx, ebx
0:
.struct 0
iso9660_dir_name_len: .byte 0
iso9660_extent_attr_len: .byte 0
iso9660_extent_location: .long 0
iso9660_parent_dir_nr: .word 0
iso9660_dir_name: 
.text32
	movzx	ecx, byte ptr [esi + ebx + iso9660_dir_name_len]
	jecxz	1f

	PRINT	"Directory: "
	push	esi
	add	esi, 8
	add	esi, ebx
	mov	edx, ebx
	call	printhex8
	print	" name='"
	call	nprint
	pop	esi
	PRINT	"' parent="
	mov	dx, [esi + ebx + iso9660_parent_dir_nr]
	call	printhex4
	print	" extentLBA: "
	mov	edx, [esi + ebx + iso9660_extent_location]
	call	printhex8
	call	newline

	call	iso_print_dir_extent
#	jc	iso_err$
	
	add	ebx, 8		# directory identifier length identifier (msb and lsb)
	add	ebx, ecx	# dir ident len
	and	ecx, 1		# align
	add	ebx, ecx
	jmp	0b
1:	
	
##################################################################
	ret

iso_print_dir_extent:
	push	esi
	push	ebx
	push	ecx
	push	eax

	mov	ebx, [esi + ebx + iso9660_extent_location]
	cmp	ebx, [iso_cur_pt_lba]
	jz	3f
	mov	[iso_cur_pt_lba],ebx

	mov	eax, [iso_logical_block_size]
	call	malloc
	jc	2f
	mov	edi, eax
	mov	edx, [atapi_edx]
	mov	al, [atapi_al]
	call	atapi_read12$	# in: edx, ebx, edi; out: esi
	jc	2f

0:	cmp	byte ptr [esi], 0	# record len
	jz	0f

	print "  File: "
	push	esi
	add	esi, 33
	movzx	ecx, byte ptr [esi -1]
	call	nprint
	pop	esi
	print " size: "
	mov	edx, [esi + 10]
	call	printdec32
	print " fileext: "
	mov	edx, [esi + 2]
	call	printhex8
	call	newline

		push	edi
		push	esi
		add	esi, 33
		movzx	ecx, byte ptr [esi-1]
		LOAD_TXT "HELLO.TXT;1", edi
		repz	cmpsb
		pop	esi
		pop	edi
		jnz	1f
			
			mov	eax, [esi + 10]
			call	malloc
			jc	2f

			push	edi
			mov	edi, eax
			push	edi
			mov	al, [atapi_al]
			mov	edx, [atapi_edx]
			mov	ebx, [esi + 2]

			push	esi
			call	atapi_read12$
			jc	4f
			print "   Content: ["
			mov	ecx, [esp]
			mov	ecx, [ecx + 10]
			call	nprint
			printchar ']'
		4:	pop	esi

			pop	eax
			call	mfree
			pop	edi
			call	newline

	1:

	movzx	ecx, byte ptr [esi]
	add	esi, ecx
	jmp	0b
0:
	mov	eax, edi
	call	mfree
	jnc	3f

2:	printlnc 4, "iso_print_dir_extent: error"
	stc
3:
	pop	eax
	pop	ecx
	pop	ebx
	pop	esi
	ret



iso_err$:
	PRINTLNc 4, "Error reading CD-ROM"
	ret
