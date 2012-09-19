##############################################################################
# ISO 9660 File System
#
.intel_syntax noprefix
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
	DEBUG_DWORD edx


##################################################################

	# Read Primary Volume Descriptor

	mov	ebx, 16	# LBA
	call	atapi_read12$
	jc	iso_err$

	PRINTc	11, "Volume descriptor type: "
	push	edx
	mov	dl, [esi]
	call	printhex2
	pop	edx

	call	newline
	PRINTc	11, "Standard Identifier: "
	mov	ecx, 5
	push	esi
	inc	esi
	call	nprint
	pop	esi
	call	newline

	xor	ebx, ebx
	mov	bx, [esi + 140]	# LSB path table location
	DEBUG_WORD bx
	call	atapi_read12$
	jc	iso_err$

	# print directory structure

	xor	ebx, ebx
	xor	ecx, ecx
0:
	mov	cl, [esi+ebx]	# directory identifier len
	or	cl, cl
	jz	1f

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

	add	ebx, 8
	add	ebx, ecx
	and	ecx, 1
	add	ebx, ecx
	jmp	0b
1:	
	
##################################################################
	ret

iso_err$:
	PRINTLNc 4, "Error reading CD-ROM"
	ret
