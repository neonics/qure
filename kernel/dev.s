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
.struct OBJ_STRUCT_SIZE	# variable length objects
dev_name:		.space 16	# short device name (/dev/)

# injected by pci.s/pci_find_driver
dev_drivername_short:	.long 0
dev_drivername_long:	.long 0

dev_type:		.byte 0	# see device_classes/DEV_TYPE
#dev_nr:		.byte 0 # device tpe-specific number (usb0, usb1)

dev_irq:		.byte 0
dev_irq_pin:		.byte 0
dev_io:			.long 0
dev_io_size:		.long 0
dev_mmio:		.long 0
dev_mmio_size:		.long 0

#################
.align 4
dev_api:
dev_api_constructor:	.long 0	# in: ebx = base
dev_api_print:		.long 0
DEV_API_SIZE =  . - dev_api
#################
dev_subclass_start:
DEV_STRUCT_SIZE = .
#################
# ATA
.struct dev_subclass_start
dev_ata_device:		.byte 0
DEV_ATA_STRUCT_SIZE = .
#################
# PCI
.struct dev_subclass_start
dev_pci_addr:
 dev_pci_slot:		.byte 0
 dev_pci_bus:		.byte 0
dev_pci_vendor:		.word 0
dev_pci_device_id:	.word 0

dev_pci_class:		.byte 0
dev_pci_subclass:	.byte 0
dev_pci_progif:		.byte 0	
dev_pci_revision:	.byte 0
DEV_PCI_STRUCT_SIZE = .

################################
# Class class
.struct 0
class_object_size: .long 0
class_pre_constructor: .long 0
class_match_instance: .long 0

class_methods:
.text32
# in: eax = class pool
# in: dl = class number
# out: eax = class info pointer
# out: dl = edx = (corrected) class number
class_get_info:
	movsx	edx, dl
	shl	edx, 2
	cmp	edx, [eax - 4]
	jb	1f
	printc	4, "class_get_info: unknown class: "
	call	printhex2
	call	newline
	xor	edx, edx
1:	mov	eax, [eax + edx]
	shr	edx, 2
	ret

###############################
.data
# local class pool
.long device_classes_end - device_classes
device_classes:	.long dev_class_unknown, dev_class_pci, dev_class_ata
	DEV_TYPE_PCI = 1
	DEV_TYPE_ATA = 2
device_classes_end:

.data
###############################
dev_class_unknown:
	.long	DEV_STRUCT_SIZE
	.long	dev_api_not_implemented
	.long	dev_api_not_implemented

	.long	dev_api_not_implemented
	.long	dev_unknown_print
dev_class_pci:
	.long	DEV_PCI_STRUCT_SIZE
	.long	dev_pci_pre_constructor
	.long	dev_pci_match_instance

	.long	dev_pci_constructor
	.long	dev_pci_print
###############################
dev_class_ata:
	.long	DEV_ATA_STRUCT_SIZE
	.long	dev_ata_pre_constructor
	.long	dev_ata_match_instance

	.long	dev_ata_constructor
	.long	dev_ata_print
###############################
devices: .long 0
.text32

dev_init:
	mov	eax, [devices]
	or	eax, eax
	jnz	1f
dev_init$:
	push	ecx
	mov	eax, 100 # 16	# inital entries
	mov	ecx, DEV_PCI_STRUCT_SIZE	# largest struct
	call	array_new
	mov	[devices], eax
	pop	ecx
	ret
1:	printlnc 4, "dev_init: already initialized"
	stc
	ret

# usage:
#	call	dev_newentry
#	add	[eax + edx + dev_api_print], offset mydevclass_print
#
# in: ecx = struct size
# out: eax + edx = base + offset
# out: all method fields are filled with the code base address in memory,
#      as the code is compiled with base 0 - dynamically relocatable.
dev_newentry:
	mov	eax, [devices]
	or	eax, eax
	jnz	0f
	call	dev_init$
0:	call	obj_array_newentry
	mov	[devices], eax
	ret

# The dev_newentry is the first method that stores the relocation [realsegflat],
# and thus, does not use the 'latest' value for the code base at each call.
# When code relocation is implemented, each 'module' provides a 'relocate'
# method that will update all existing method pointers. new entries will
# be created using the base offset variable [realsegflat], so this method
# is at current never called.
#
# in: eax = difference
dev_relocate:
	push	edx
	push	ecx
	push	ebx

	mov	ebx, [devices]
	xor	edx, edx

1:	push	ebx
	add	ebx, edx

	mov	ecx, DEV_API_SIZE / 4
0:	add	[ebx + ecx * 4 - 4], eax
	loop	0b

	pop	ebx
2:	cmp	edx, [ebx + array_index]
	jb	1b

	pop	ebx
	pop	ecx
	pop	edx
	ret

# in: al: DEV_TYPE_....
# out: ebx = bl = (corrected) device class
# out: ecx = object size
# out: esi = method pointers
dev_get_class_info:
	movsx	ebx, al
	cmp	ebx, ( offset device_classes_end - offset device_classes ) / 4
	jb	1f
	printc 4, "dev_newinstance: warning: unknown device type: "
	mov	dl, bl
	call	printhex2
	call	newline
	xor	ebx, ebx
1:
	
	mov	esi, [device_classes + ebx * 4]
	mov	ecx, [esi]	# first entry: object size

	.if DEV_DEBUG
		DEBUG "dev_newinstance"
		DEBUG "type"
		DEBUG_BYTE al
		DEBUG "size"
		DEBUG_DWORD ecx
		push	edx
		mov	edx, [devices]
		or	edx, edx
		jz	1f
		mov	edx, [edx + array_index]
		DEBUG_DWORD edx
	1:	pop	edx
	.endif

	# call the class' init method, it may change the object size etc.
	push	ebx
	mov	ebx, [esi + class_pre_constructor]
	add	ebx, [realsegflat]
	call	ebx
	pop	ebx
	add	esi, class_methods
	ret

# Parameterized class instantiation:
# al contains a subclass identifier (index into device_classes).
# It will lookup the class (and provide a default if it is unknown),
# allocate an instance using the object size found, and store this
# aswell as the class id in the object. Further it will initialize
# all method pointers for dev_api by copying them from the class definition
# for easy calling:  call [eax + edx + dev_api_print]
#
# in: al = device type (DEV_TYPE_...)
# in: edx = constructor arg
# out: eax + edx
# out: [eax + edx + {obj_size, dev_type, dev_api_*}] filled in.
dev_newinstance:
	push	edi
	push	esi
	push	ebx
	push	ecx

	call	dev_get_class_info	# in: al; out: ebx, ecx, esi
	call	dev_newentry

	mov	[eax + edx + obj_size], ecx
	mov	[eax + edx + dev_type], bl	# class pointer

	# fill in methods

	lea	edi, [eax + edx + dev_api]
	mov	ecx, DEV_API_SIZE / 4

0:	lodsd
	add	eax, [realsegflat]	# relocate
	stosd
	loop	0b

	mov	eax, [devices]

	# if subclasses add their own API methods these will be
	# starting at an unknown offset, and the specific
	# subclass initialisation needs to deal with this.

	pop	ecx
	pop	ebx
	pop	esi
	pop	edi
	ret

# in: al = device type
# in: ecx = device-type specific identifier (i.e. pci address for dev_pci)
# out: eax + edx = existing device entry (preserved when CF)
# out: CF
dev_getinstance:
	push	esi
	push	ebx
	push	ecx

	push	eax
	push	edx

	mov	dl, al
	mov	eax, offset device_classes
	call	class_get_info	# in: al; out: ebx, ecx, esi
	mov	bl, dl
	mov	esi, [eax + class_match_instance]
	add	esi, [realsegflat]
	mov	eax, [devices]
	or	eax, eax
	jz	2f

	OBJ_ARRAY_ITER_START eax, edx
	cmp	bl, [eax + edx + dev_type]
	jnz	1f
	call	esi	# in: eax+edx, ebx
	jnz	1f
	add	esp, 8
	jmp	9f
1:	OBJ_ARRAY_ITER_NEXT eax, edx
2:	stc
	pop	edx
	pop	eax

9:	pop	ecx
	pop	ebx
	pop	esi
	ret

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
# in: cx = pci address
dev_pci_match_instance:
	cmp	[eax + edx + dev_pci_addr], cx
	ret

# in: al = DEV_TYPE_PCI
# in: ecx = class object size
# in: edx = pci class/subclass/progif/revision 
# out: ecx updated
dev_pci_pre_constructor:
	mov	ecx, DEV_PCI_STRUCT_SIZE
	push	edx
	shr	edx, 16
	cmp	dx, 0x0200	# 02=NIC, 00 = Ethernet
	jnz	1f

	# use 'offset' because declared later (and thus used as memref)
	# the + 64 is for various nic structures
	mov	ecx, offset NIC_STRUCT_SIZE + 64	# for now...

1:	pop	edx
	ret

# After the pre-constructor is called, the memory is allocated,
# and the caller to dev_newinstance has the opportunity to initialize
# the object fields, after which it should call dev_api_constructor.

# in: ebx = device object
dev_pci_constructor:
	push	esi
	push	edi
	push	edx
	# the fields are already filled in.

	# get the device name
	movzx	eax, byte ptr [ebx + dev_pci_class]
	mov	dx, [ebx + dev_pci_subclass]
	call	pci_get_device_subclass_info	# out: esi

	# get a counter
	mov	eax, [esi + 2 + 4]
	mov	esi, eax
	call	pci_get_obj_counter	# out: al
	movzx	edx, al

	lea	edi, [ebx + dev_name]

	push	ecx
	mov	ecx, 16 - 4	# max nr 255 + terminating 0
0:	lodsb
	or	al, al
	jz	0f
	stosb
	loop	0b
0:	pop	ecx
	
	call	sprintdec32

	call	pci_find_driver

.if 0
		# lets see if it is a nic:

		cmp	[ebx + dev_pci_class], word ptr 0x0002	# Ethernet NIC
		jnz	0f
		# the pre-constructor will have taken care of offering the right
		# size for the structure.

		# it's a nic, check if we support it:
		call	nic_constructor
		jmp	9f
	0:
	# TODO: merge

		cmp	[ebx + dev_pci_class], word ptr 0x0003 # Display Adapter
		jnz	0f
		DEBUG "Is video device - calling vid_constructor"
		DEBUG_DWORD (offset vid_constructor)
		call	vid_constructor
		jmp	9f
	0:

		cmp	[ebx + dev_pci_class], word ptr 0x030c # USB
		jnz	0f
		call	usb_constructor

	0:
.endif
9:	pop	edx
	pop	edi
	pop	esi
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

#############################################################################
# dev_ata class methods

# in: eax + edx = device object
# in: cl = ata device
dev_ata_match_instance:
	cmp	[eax + edx + dev_ata_device], cl
	ret

dev_ata_pre_constructor:
	mov	ecx, DEV_ATA_STRUCT_SIZE
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
	mov	eax, [devices]
	or	eax, eax
	jz	2f
	OBJ_ARRAY_ITER_START eax, edx
	lea	ebx, [eax + edx]
	call	dev_print
	call	newline
	OBJ_ARRAY_ITER_NEXT eax, edx
	ret

2:	printlnc 12, "dev_list: device system not initialized"
	ret

