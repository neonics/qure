.intel_syntax noprefix

.text
.code32

PCI_IO	= 0xcf8
PCI_IO2	= 0xcfa

PCI_COMMAND_ACK_INT			= 0b0000
PCI_COMMAND_SPECIAL_CYCLE		= 0b0001
PCI_COMMAND_IO_READ			= 0b0010
PCI_COMMAND_IO_WRITE			= 0b0011
PCI_COMMAND_RESERVED1			= 0b0100
PCI_COMMAND_RESERVED2			= 0b0101
PCI_COMMAND_MEMORY_READ			= 0b0110
PCI_COMMAND_MEMORY_WRITE		= 0b0111
PCI_COMMAND_RESERVED3			= 0b1000
PCI_COMMAND_RESERVED4			= 0b1001
PCI_COMMAND_CONFIGURATION_READ		= 0b1010
PCI_COMMAND_CONFIGURATION_WRITE		= 0b1011
PCI_COMMAND_MEMORY_READ_MULTIPLE	= 0b1100
PCI_COMMAND_DUAL_ADDRESS_CYCLE		= 0b1101
PCI_COMMAND_MEMORY_READ_LINE		= 0b1110
PCI_COMMAND_MEMORY_WRITE_AND_INVALIDATE	= 0b1111

pci_list_devices:


	xor	eax, eax

	mov	dx, PCI_IO
	out	dx, al
	add	dx, 2
	out	dx, al
	sub	dx, 2

	in	al, dx
	shl	ax, 8
	add	dx, 2
	in	al, dx
	or	ax, ax
	jz	2f		# pci type 2

	mov	dx, PCI_IO
	in	eax, dx		# backup
	mov	ebx, eax

	mov	eax, 1<<31
	out	dx, eax
	in	eax, dx

	xchg	eax, ebx	# restore
	out	dx, eax

	cmp	ebx, 1<<31
	je	1f		# pci type 1

	PRINTln "PCI Type 0"
	ret

#######
1:	PRINTln "PCI Type 1"
	xor	ecx, ecx
0:	mov	eax, ecx
	shl	eax, 11
	or	eax, 1 << 31
	mov	dx, PCI_IO
	out	dx, eax
	call	pci_print_dev$

1:
	inc	ecx
	cmp	eax, 511
	jbe	0b
	ret

#######
2:	PRINTln "PCI Type 2"
	mov	dx, PCI_IO
	mov	al, 0x80
	out	dx, al
	add	dx, 2
	xor	al, al
	out	dx, al

	mov	ecx, 16
	mov	dx, 0xc000
0:	in	eax, dx
	call	pci_print_dev$
	add	dx, 256
	loop	0b

	
	ret


pci_print_dev$:
	in	eax, dx
	inc	eax
	jz	1f
	PRINT " PORT: "
	call	printhex
	push	edx
	dec	eax
	PRINT	"PCI Device: Vendor "
	mov	edx, eax
	call	printhex
	PRINT	" Device: "
	ror	edx, 16
	call	printhex
	pop	edx
	call	newline
1:	ret

