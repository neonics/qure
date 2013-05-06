###############################################################################
# Device Driver Base

DEV_DEBUG = 0
DEV_PRINT_IO = 0	# 1 = print IRQ, io, mmio
DEV_PCI_PRINT_BUS = 0
DEV_PCI_PRINT_VENDOR_ID = 1
DEV_ATA_PRINT_BUS = 0

.intel_syntax noprefix
.text32

###############################
DECLARE_CLASS_BEGIN dev
#.struct OBJ_STRUCT_SIZE	# variable length objects
dev_name:		.space 16	# short device name (/dev/)

# injected by pci.s/pci_find_driver
dev_drivername_short:	.long 0
dev_drivername_long:	.long 0

dev_type:		.byte 0	# see device_classes/DEV_TYPE
#dev_nr:		.byte 0 # device tpe-specific number (usb0, usb1)
dev_state:		.byte 0
	DEV_STATE_INITIALIZED = 1

dev_irq:		.byte 0
dev_irq_pin:		.byte 0
dev_io:			.long 0
dev_io_size:		.long 0
dev_mmio:		.long 0
dev_mmio_size:		.long 0

#################
#DECLARE_CLASS_METHODS
dev_api:
DECLARE_CLASS_METHOD dev_api_constructor, 0
DECLARE_CLASS_METHOD dev_api_print, 0
#dev_api_constructor:	.long 0	# in: ebx = base
#dev_api_print:		.long 0
DEV_API_SIZE =  . - dev_api
#################
#DEV_STRUCT_SIZE = .
DECLARE_CLASS_END dev

#################
# ATA
DECLARE_CLASS_BEGIN dev_ata, dev
#.struct DEV_STRUCT_SIZE
dev_ata_device:		.byte 0
#DEV_ATA_STRUCT_SIZE = .
DECLARE_CLASS_METHOD dev_api_constructor, dev_ata_constructor, OVERRIDE
DECLARE_CLASS_METHOD dev_api_print, dev_ata_print, OVERRIDE
DECLARE_CLASS_END dev_ata
#################
# PCI
#.struct DEV_STRUCT_SIZE
DECLARE_CLASS_BEGIN dev_pci, dev
dev_pci_addr:
 dev_pci_slot:		.byte 0
 dev_pci_bus:		.byte 0
 dev_pci_func:		.byte 0
			.byte 0	# for dword loading
dev_pci_vendor:		.word 0
dev_pci_device_id:	.word 0

dev_pci_subvendor:	.word 0
dev_pci_subdevice:	.word 0

dev_pci_class:		.byte 0
dev_pci_subclass:	.byte 0
dev_pci_progif:		.byte 0	
dev_pci_revision:	.byte 0
DECLARE_CLASS_METHOD dev_api_print, dev_pci_print, OVERRIDE
DECLARE_CLASS_END dev_pci

###############################
DECLARE_CLASS_BEGIN vid, dev_pci
vid_name:	.long 0
vid_fb_addr:	.long 0
vid_fb_size:	.long 0
vid_fifo_addr:	.long 0
vid_fifo_size:	.long 0
DECLARE_CLASS_END vid
###############################

############################################################################
# Utility methods

# in: ebx = device pointer
dev_print:
	push	edx
	push	eax

	.macro DEV_PRINT_ msg, offs, digits
		print	"\msg"
		mov	edx, [ebx + \offs]
		call	printhex\digits
	.endm

	.macro DEV_PRINT_D msg, offs
		DEV_PRINT_ "\msg", \offs, 8
	.endm

	.macro DEV_PRINT_W msg, offs
		DEV_PRINT_ "\msg",\offs, 4
	.endm

	.macro DEV_PRINT_B msg, offs
		DEV_PRINT_ "\msg", \offs, 2
	.endm

	.if DEV_DEBUG > 1
		DEBUG "objsize"
		lea edx, [ebx + obj_size]
		DEBUG "offs"
		DEBUG_DWORD edx
		mov edx, [ebx + obj_size]
		DEBUG_DWORD edx

		DEBUG "call api_print"
		mov edx, [ebx + dev_api_print]
		DEBUG_DWORD edx
	.endif

	printc	7, "/dev/"

	pushcolor 15
	push	esi
	lea	esi, [ebx + dev_name]
	call	print
	call	printspace
	pop	esi
	popcolor

	call	[ebx + dev_api_print]

	.if DEV_PRINT_IO
	push	esi
		cmp	[ebx + dev_irq], byte ptr 0
		jz	0f
		DEV_PRINT_B " irq ", dev_irq
	0:	cmp	[ebx + dev_io], dword ptr 0
		jz	0f
		DEV_PRINT_D " io ", dev_io
		DEV_PRINT_D "+", dev_io_size
	0:	cmp	[ebx + dev_mmio], dword ptr 0
		jz	0f
		DEV_PRINT_D " mmio ", dev_mmio
		DEV_PRINT_D "+", dev_mmio_size
	0:
	pop	esi
	.endif

	pop	eax
	pop	edx
	ret


############################################################################
# dev_pci class methods

# in: eax + edx = device object
# in: ecx = pci address: [00][func][bus][slot]
dev_pci_match_instance:
	cmp	[eax + edx + dev_pci_addr], ecx
	ret

dev_pci_print:
	push	esi
	pushcolor 7

	.if DEV_PCI_PRINT_BUS
		DEV_PRINT_B "/pci/bus", dev_pci_bus
		DEV_PRINT_B "/slot", dev_pci_slot
		DEV_PRINT_B "/class", dev_pci_class
		DEV_PRINT_B ".", dev_pci_subclass
		DEV_PRINT_B ".", dev_pci_progif
	.endif

	DEV_PRINT_B "class ", dev_pci_class
	DEV_PRINT_B ".", dev_pci_subclass
	DEV_PRINT_B ".", dev_pci_progif
	call	printspace

	movzx	eax, byte ptr [ebx + dev_pci_class]
	mov	dx, [ebx + dev_pci_subclass]
	call	pci_get_device_subclass_info
	mov	esi, [esi + 2]
	color 10
	call	print
	call	printspace
	mov	esi, [pci_device_class_names + eax * 8]
	color 11
	call	print

	.if DEV_PCI_PRINT_VENDOR_ID
	color 9
		DEV_PRINT_W " vendor ", dev_pci_vendor
		DEV_PRINT_W " deviceid ", dev_pci_device_id
	.endif

	popcolor
	pop	esi
	ret

# in: ebx: device
# in: al: pci configuration register
# out: eax
dev_pci_read_config:
	push_	ebx edx
	mov	ebx, [ebx + dev_pci_addr]
	xchg	eax, ebx
	call	pci_read_config	# in: eax=pci addr; bl = pci config reg
	pop_	edx ebx
	ret

# in: ebx = device
# in: al = pci config register
# in: edx = value to write
# out: eax = readback value
dev_pci_write_config:
	push	ebx
	mov	ebx, [ebx + dev_pci_addr]
	xchg	eax, ebx
	call	pci_write_config
	pop	ebx
	ret

# in: ebx = device
dev_pci_busmaster_enable:
	push	eax
	mov	eax, [ebx + dev_pci_addr]
	call	pci_busmaster_enable
	pop	eax
	ret

#############################################################################
# dev_ata class methods

# in: eax + edx = device object
# in: cl = ata device
dev_ata_match_instance:
	cmp	[eax + edx + dev_ata_device], cl
	ret

dev_ata_constructor:
	push	ecx
	mov	[ebx + dev_name], dword ptr 'h' | ('d'<<8)
	add	cl, 'a'
	mov	[ebx + dev_name + 2], cl

#	xor	ch, ch
#	shl	ecx, 16
#	mov	cx, 'h' | ('d'<<8)
#	mov	[ebx + dev_name], ecx
	pop	ecx
	ret

dev_ata_print:
	mov	al, [ebx + dev_ata_device]

	.if DEV_ATA_PRINT_BUS
		print	"/ata/bus"
		xor	edx, edx
		mov	dl, al
		shr	dl, 1
		call	printhex1
		print	"/device"
		mov	dl, al
		and	dl, 1
		call	printhex1
	.endif

	print	"capacity "
	mov	al, [ebx + dev_ata_device]
	call	ata_print_capacity
	ret

############################################################################
# dev_unknown class methods

dev_api_not_implemented:
	printlnc 4, "dev_api_...: not implemented"
	stc
	ret

dev_unknown_print:
	DEV_PRINT_B "/unknown", dev_type
	ret

############################################################################
# Commandline Utilities


# dev [operation]
# operation: list, scan
cmd_dev:
	lodsd
	lodsd
	or	eax, eax
	jz	cmd_dev_list
	
	CMD_ISARG "list"
	jz	cmd_dev_list

	CMD_ISARG "scanpci"
	jz	pci_list_devices

	CMD_ISARG "scanata"
	jz	cmd_disks_print$

	printlnc 12, "usage: dev [<list>|<scanpci>|<scanata>]"
	ret

cmd_dev_list:
.if 0
	mov	eax, [devices]
	or	eax, eax
	jz	2f
	OBJ_ARRAY_ITER_START eax, edx
	lea	ebx, [eax + edx]
	call	dev_print
	call	newline
	OBJ_ARRAY_ITER_NEXT eax, edx
.endif
	ret

2:	printlnc 12, "dev_list: device system not initialized"
	ret
