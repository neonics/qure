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


##################################################################
	.if 0 # this works in qemu and vmware
	println "read capacity"
	DEBUG_BYTE al
	push	edx
	push	eax
	call	atapi_read_capacity$
	pop	eax
	pop	edx
	.endif

	println "read volume descriptor"
	# Read Primary Volume Descriptor
	mov	ebx, 16	# LBA
	mov	ecx, 1 	# sectors

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
	movzx	ebx, word ptr [esi + 140]	# LSB path table location
	call	atapi_read12$
	jc	iso_err$

	# print directory structure

	xor	ebx, ebx
0:
	movzx	ecx, byte ptr [esi + ebx]	# directory identifier len
	jecxz	1f

	push	esi
	add	esi, 8
	add	esi, ebx
	PRINT	"Directory: "
	push	edx
	mov	edx, ebx
	call	printhex8
	pop	edx
	PRINT	" '"
	call	nprint
	PRINTLN "'"
	pop	esi

	add	ebx, 8		# directory identifier length identifier (msb and lsb)
	add	ebx, ecx	# dir ident len
	and	ecx, 1		# align
	add	ebx, ecx
	jmp	0b
1:	
	
##################################################################
	ret

iso_err$:
	PRINTLNc 4, "Error reading CD-ROM"
	ret
