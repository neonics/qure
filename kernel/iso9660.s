.intel_syntax noprefix
.text

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

	# Read Primary Volume Descriptor

	mov	ebx, 16	# LBA
	call	atapi_read12$
	jc	iso_err$

	PRINT "Volume descriptor type: "
	push	edx
	mov	dl, [esi]
	call	printhex2
	pop	edx

	call	newline
	PRINT "Standard Identifier: "
	mov	ecx, 5
	push	esi
	inc	esi
	call	nprint
	pop	esi
	call	newline

	xor	ebx, ebx
	mov	bx, [esi + 140]	# LSB path table location
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
