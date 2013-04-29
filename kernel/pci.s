##############################################################################
#### PCI ############################### http://wiki.osdev.org/PCI ###########
##############################################################################
.intel_syntax noprefix

.text32

IO_PCI_CONFIG_ADDRESS	= 0xcf8
IO_PCI_CONFIG_DATA	= 0xcfc

# PCI_CONFIG_ADDRESS bits:
#PCI_CONFIG_ENABLE		1 bit 31 whether access to config is translated
#					 into configuration cycles
#PCI_CONFIG_RESERVED		7 bits 30:24
#PCI_CONFIG_BUS			8 bits 23:16
#PCI_CONFIG_DEVICE/SLOT		5 bits 15:11
#PCI_CONFIG_FUNCTION		3 bits 10:8
#PCI_CONFIG_REGISTER/OFFS	6 bits 7:2
#PCI_CONFIG_00		2 bits 1:0
#
# | 1 0000000 | bbbbbbbb | ddddd fff | rrrrrr 00 |
#
# offset: 8 bits. Lowest bit ignored - word alignment.
#
# out 0xcf8, (1<<31) | (bus << 16) | (dev << 11) | (func << 8) | (reg & 0xfc)
#                                     slot                        offset
# (( in 0xcfc ) >> (offset&2) <<3)) & 0xffff
# bit 1: value 2, 2*8 = 16 bytes
# 


#PCI_COMMAND_ACK_INT			= 0b0000
#PCI_COMMAND_SPECIAL_CYCLE		= 0b0001
#PCI_COMMAND_IO_READ			= 0b0010
#PCI_COMMAND_IO_WRITE			= 0b0011
#PCI_COMMAND_RESERVED1			= 0b0100
#PCI_COMMAND_RESERVED2			= 0b0101
#PCI_COMMAND_MEMORY_READ		= 0b0110
#PCI_COMMAND_MEMORY_WRITE		= 0b0111
#PCI_COMMAND_RESERVED3			= 0b1000
#PCI_COMMAND_RESERVED4			= 0b1001
#PCI_COMMAND_CONFIGURATION_READ		= 0b1010
#PCI_COMMAND_CONFIGURATION_WRITE	= 0b1011
#PCI_COMMAND_MEMORY_READ_MULTIPLE	= 0b1100
#PCI_COMMAND_DUAL_ADDRESS_CYCLE		= 0b1101
#PCI_COMMAND_MEMORY_READ_LINE		= 0b1110
#PCI_COMMAND_MEMORY_WRITE_AND_INVALIDATE= 0b1111

# 256 byte Configuration Space Register numbers:
PCI_CFG_DEVICE_VENDOR_ID = 0	# hi word = device id, lo word = vendor id
PCI_CFG_STATUS_COMMAND	= 4
PCI_CFG_CLASS_PROG_REV	= 8	# db class code, subclass, prog if, rev id
PCI_CFG_BIST_HTYPE_LTIMER_CACHE = 0x0c
PCI_CFG_BAR0	= 0x10
PCI_CFG_BAR1	= 0x14
PCI_CFG_BAR2	= 0x18
PCI_CFG_BAR3	= 0x1c
PCI_CFG_BAR4	= 0x20
PCI_CFG_BAR5	= 0x24
PCI_CFG_CARDBUS_CIS_PTR	= 0x28

# 11 bits word
PCI_CMD_IO_SPACE		= 0b00000000001	# 1=can respond, 0=disable resp
PCI_CMD_MEM_SPACE		= 0b00000000010	# 1=can respond, 0=disable resp
PCI_CMD_BUSMASTER		= 0b00000000100	# 1=can busmaster,0=can't xs pci
PCI_CMD_SPECIAL_CYCLES		= 0b00000001000	# 1=can monitor, 0=ignore
PCI_CMD_MEM_WRITE_AND_INVALIDATE= 0b00000010000	# 0=must use memory write cmd
PCI_CMD_VGA_PALETTE_SNOOP	= 0b00000100000	# 1=snoop (no respond)0=normal
PCI_CMD_PARITY_ERROR_RESPONSE	= 0b00001000000	# 1=raise PERR#; 0=set status:15
PCI_CMD_RESERVED		= 0b00010000000
PCI_CMD_SERR_NR_ENABLE		= 0b00100000000
PCI_CMD_FBB_ENABLE		= 0b01000000000	# fast back to back enable
PCI_CMD_INTERRUPT_DISABLE	= 0b10000000000


# 16 bit
# low 4 bits marked reserved in PCI 22 spec...
PCI_STATUS_RESERVED			= 0b0000000000000011
PCI_STATUS_INTERRUPT			= 0b0000000000000100

PCI_STATUS_CAPABILITIES_LIST		= 0b0000000000010000
PCI_STATUS_66_MHZ_CAPABLE		= 0b0000000000100000 # 0=33MHz
PCI_STATUS_RESERVED2			= 0b0000000001000000
PCI_STATUS_FBB_CAPABLE			= 0b0000000010000000 # fast back-to-back
PCI_STATUS_MASTER_DATA_PARITY_ERROR	= 0b0000000100000000
PCI_STATUS_DEVSEL_TIMING_MASK		= 0b0000011000000000 # 0=fast,med,slow=2
PCI_STATUS_TXD_TARGET_ABORT		= 0b0000100000000000 # signalled/transmitted
PCI_STATUS_RXD_TARGET_ABORT		= 0b0001000000000000 # received
PCI_STATUS_RXD_MASTER_ABORT		= 0b0010000000000000
PCI_STATUS_TXD_SYSTEM_ERROR		= 0b0100000000000000
PCI_STATUS_PARITY_ERROR			= 0b1000000000000000

.data SECTION_DATA_STRINGS
dc00$: .asciz "Ancient"
dc01$: .asciz "Mass Storage Controller"
dc02$: .asciz "Network Controller"
dc03$: .asciz "Display Controller"
dc04$: .asciz "Multimedia Controller"
dc05$: .asciz "Memory Controller"
dc06$: .asciz "Bridge Device"
dc07$: .asciz "Simple Communications Device"
dc08$: .asciz "Base System Peripheral"
dc09$: .asciz "Input Device"
dc0a$: .asciz "Docking Station"
dc0b$: .asciz "Processor"
dc0c$: .asciz "Serial Bus Controller"
dc0d$: .asciz "Wireless Controller"
dc0e$: .asciz "Intelligent IO Controller"
dc0f$: .asciz "Satellite Communication Controller"
dc10$: .asciz "Cryptographic Controller"
dc11$: .asciz "Data Acquisition and Signal Processing Controller"
# 0x12 - 0xFE = reserved
# 0xff = doesnt fit a defined class

PCI_MAX_KNOWN_DEVICE_CLASS = 0x11

.macro SUBCLASS subclass, prog_if, devname="", name
	.data SECTION_DATA_STRINGS
	99: .asciz "\name"
	88: .asciz "\devname"
	.data
	.byte \subclass, \prog_if
	.long 99b
	.long 88b
.endm

pci_subclass_unk$: .asciz "unknown"
pci_subclass_eol$: .asciz "Other"

.macro SUBCLASS_EOL
	.data
	.byte 0x80, 0x00
	.long pci_subclass_eol$
	.long pci_subclass_unk$
.endm

# Subclass list: subclass 0x80 = end of list/other device
# prog_if = 0xff: accept all prog_ifs
#
# for a (mostly) complete list: http://pciids.sourceforge.net/v2.2/pci.ids

sc00$:	# Class 0: Display
SUBCLASS 0x00, 0x00, "display", "Non-VGA compatible"
SUBCLASS 0x01, 0x00, "display", "VGA compatible"
SUBCLASS_EOL

DEV_PCI_CLASS_STORAGE = 0x01
DEV_PCI_CLASS_STORAGE_SCSI	= 0x000001
DEV_PCI_CLASS_STORAGE_IDE	= 0xFF0101

sc01$:	# Class 1: Mass Storage
SUBCLASS 0x00, 0x00, "sd",	"SCSI Bus"
SUBCLASS 0x01, 0xFF, "ide",	"IDE"
SUBCLASS 0x02, 0x00, "fd", 	"FLoppy Disk"
SUBCLASS 0x03, 0x00, "ipi",	"IPI Bus"
SUBCLASS 0x04, 0x00, "rd",	"RAID"
SUBCLASS 0x05, 0x20, "ata",	"ATA (Single DMA)"
SUBCLASS 0x05, 0x30, "ata",	"ATA (Chained DMA)"
SUBCLASS 0x06, 0x00, "sata",	"Serial ATA (Direct Port Access)"
SUBCLASS_EOL

DEV_PCI_CLASS_NIC = 0x02
DEV_PCI_CLASS_NIC_ETH = 0x0002
sc02$:	# Class 2: Network Controller
SUBCLASS 0x00, 0x00, "eth",	"Ethernet"
SUBCLASS 0x01, 0x00, "",	"Token Ring"
SUBCLASS 0x02, 0x00, "",	"FDDI"
SUBCLASS 0x03, 0x00, "",	"ATM"
SUBCLASS 0x04, 0x00, "",	"ISDN"
SUBCLASS 0x05, 0x00, "",	"WorldFip"
SUBCLASS 0x06, 0xFF, "",	"PICMG 2.14 Multi Computing"
SUBCLASS_EOL

DEV_PCI_CLASS_VID = 0x03
DEV_PCI_CLASS_VID_VGA = 0x0003
sc03$:	# Class 3: Display Controller
SUBCLASS 0x00, 0x00, "display",	"VGA Compatible"
SUBCLASS 0x00, 0x01, "",	"8512-Compatible"
SUBCLASS 0x01, 0x00, "",	"XGA"
SUBCLASS 0x02, 0x00, "",	"3D"
SUBCLASS_EOL

DEV_PCI_CLASS_MM = 0x04
DEV_PCI_CLASS_MM_VIDEO = 0x0004
DEV_PCI_CLASS_MM_AUDIO = 0x0104
DEV_PCI_CLASS_MM_PHONE = 0x0204
sc04$:	# Class 4: Multimedia Device
SUBCLASS 0x00, 0x00, "",	"Video Device"
SUBCLASS 0x01, 0x00, "",	"Audio Device"
SUBCLASS 0x02, 0x00, "",	"Telephony Device"
SUBCLASS_EOL

sc05$:	# Class 5: Memory Controllers
SUBCLASS 0x00, 0x00, "",	"RAM"
SUBCLASS 0x01, 0x00, "",	"Flash"
SUBCLASS_EOL

DEV_PCI_CLASS_BRIDGE = 0x06
DEV_PCI_CLASS_BRIDGE_ISA 	= 0x000106
DEV_PCI_CLASS_BRIDGE_PCI2PCI 	= 0x000406
DEV_PCI_CLASS_BRIDGE_PCI2PCI_SD = 0x010406
sc06$:	# Class 6: Bridges
SUBCLASS 0x00, 0x00, "host",	"Host"
SUBCLASS 0x01, 0x00, "isa",	"ISA"
SUBCLASS 0x02, 0x00, "",	"EISA"
SUBCLASS 0x03, 0x00, "",	"MCA"
SUBCLASS 0x04, 0x00, "",	"PCI-to-PCI"
SUBCLASS 0x04, 0x01, "",	"PCI-to-PCI (Subtractive Decode)"
SUBCLASS 0x05, 0x00, "",	"PCMCIA"
SUBCLASS 0x06, 0x00, "",	"NuBus"
SUBCLASS 0x07, 0x00, "",	"CardBus"
SUBCLASS 0x08, 0xFF, "",	"RACEway"
SUBCLASS 0x09, 0x40, "",	"PCI-to-PCI (Semi-Transparent, Primary)"
SUBCLASS 0x09, 0x80, "",	"PCI-to-PCI (Semi-Transparent, Secondary)"
SUBCLASS 0x0A, 0x00, "",	"InfiniBrand-to-PCI Host"
SUBCLASS_EOL

sc07$:	# Class 7: Simple Communications (Serial, parallel)
SUBCLASS 0x00, 0x00, "",	"Generic XT-Compatible Serial Controller"
SUBCLASS 0x00, 0x01, "",	"16450-Compatible Serial Controller"
SUBCLASS 0x00, 0x02, "",	"16550-Compatible Serial Controller"
SUBCLASS 0x00, 0x03, "",	"16650-Compatible Serial Controller"
SUBCLASS 0x00, 0x04, "",	"16750-Compatible Serial Controller"
SUBCLASS 0x00, 0x05, "",	"16850-Compatible Serial Controller"
SUBCLASS 0x00, 0x06, "",	"16950-Compatible Serial Controller"
SUBCLASS 0x01, 0x00, "",	"Parallel Port"
SUBCLASS 0x01, 0x01, "",	"Bi-Directional Parallel Port"
SUBCLASS 0x01, 0x02, "",	"ECP 1.X Compliant Parallel Port"
SUBCLASS 0x01, 0x03, "",	"IEEE 1284 Controller"
SUBCLASS 0x01, 0xFE, "",	"IEEE 1284 Target Device"
SUBCLASS 0x02, 0x00, "",	"Multiport Serial Controller"
SUBCLASS 0x03, 0x00, "",	"Generic Modem"
SUBCLASS 0x01, 0x01, "",	"Hayes Compatible Modem (16450-Compatible Interface)"
SUBCLASS 0x01, 0x02, "",	"Hayes Compatible Modem (16550-Compatible Interface)"
SUBCLASS 0x01, 0x03, "",	"Hayes Compatible Modem (16650-Compatible Interface)"
SUBCLASS 0x01, 0x04, "",	"Hayes Compatible Modem (16750-Compatible Interface)"
SUBCLASS 0x04, 0x00, "",	"IEEE 488.1/2 (GPIB) Controller"
SUBCLASS 0x05, 0x00, "",	"Smart Card"
SUBCLASS_EOL

sc08$:	# Class 8: Integrated peripherals
SUBCLASS 0x00, 0x00, "pic",	"Generic 8259 PIC"
SUBCLASS 0x00, 0x01, "ipic",	"ISA PIC"
SUBCLASS 0x00, 0x02, "eipic",	"EISA PIC"
SUBCLASS 0x00, 0x10, "ioapic",	"I/O APIC Interrupt Controller"
SUBCLASS 0x00, 0x20, "ioapic",	"I/O(x) APIC Interrupt Controller"
SUBCLASS 0x01, 0x00, "dma",	"Generic 8237 DMA Controller"
SUBCLASS 0x01, 0x01, "dma",	"ISA DMA Controller"
SUBCLASS 0x01, 0x02, "dma",	"EISA DMA Controller"
SUBCLASS 0x02, 0x00, "timer",	"Generic 8254 System Timer"
SUBCLASS 0x02, 0x01, "timer",	"ISA System Timer"
SUBCLASS 0x02, 0x02, "timer",	"EISA System Timer"
SUBCLASS 0x03, 0x00, "rtc",	"Generic RTC Controller"
SUBCLASS 0x03, 0x01, "rtc",	"ISA RTC Controller"
SUBCLASS 0x04, 0x00, "hotplug",	"Generic PCI Hot-Plug Controller"
SUBCLASS_EOL

sc09$:	# Class 9: Input Devices
SUBCLASS 0x00, 0x00, "kb",	"Keyboard Controller"
SUBCLASS 0x01, 0x00, "",	"Digitizer"
SUBCLASS 0x02, 0x00, "mouse",	"Mouse Controller"
SUBCLASS 0x03, 0x00, "",	"Scanner Controller"
SUBCLASS 0x04, 0x00, "game",	"Gameport Controller (Generic)"
SUBCLASS 0x04, 0x10, "game",	"Gameport Contrlller (Legacy)"
SUBCLASS_EOL

sc0a$:
SUBCLASS 0x00, 0x00, "",	"Generic Docking Station"
SUBCLASS_EOL

sc0b$:
SUBCLASS 0x00, 0x00, "cpu",	"386 Processor"
SUBCLASS 0x01, 0x00, "cpu",	"486 Processor"
SUBCLASS 0x02, 0x00, "cpu",	"Pentium Processor"
SUBCLASS 0x10, 0x00, "cpu",	"Alpha Processor"
SUBCLASS 0x20, 0x00, "cpu",	"PowerPC Processor"
SUBCLASS 0x30, 0x00, "cpu",	"MIPS Processor"
SUBCLASS 0x40, 0x00, "fpu",	"Co-Processor"
SUBCLASS_EOL

sc0c$:
DEV_PCI_CLASS_SERIAL = 0x0c
DEV_PCI_CLASS_SERIAL_USB = 0x030c
DEV_PCI_CLASS_SERIAL_USB_EHCI = 0x20030c
SUBCLASS 0x00, 0x00, "",	"IEEE 1394 Controller (FireWire)"
SUBCLASS 0x00, 0x10, "",	"IEEE 1394 Controller (1394 OpenHCI Spec)"
SUBCLASS 0x01, 0x00, "",	"ACCESS.bus"
SUBCLASS 0x02, 0x00, "",	"SSA"
SUBCLASS 0x03, 0x00, "usb",	"USB (UHCS)" #Universal Host Controller Spec
SUBCLASS 0x03, 0x10, "usb",	"USB (OHCS)" #Open Host Controller Spec
SUBCLASS 0x03, 0x20, "usb",	"USB2 (Intel EHCI)" #Enhanced Host Controller Interface)"
SUBCLASS 0x03, 0x80, "usb",	"USB"
SUBCLASS 0x03, 0xFE, "usb",	"USB (Not Host Controller)"
SUBCLASS 0x04, 0x00, "",	"Fibre Channel"
SUBCLASS 0x05, 0x00, "",	"SMBus"
SUBCLASS 0x06, 0x00, "",	"InfiniBand"
SUBCLASS 0x07, 0x00, "",	"IPMI SMIC Interface"
SUBCLASS 0x07, 0x01, "",	"IPMI Kybd Controller Style Interface"
SUBCLASS 0x07, 0x02, "",	"IPMI Block Transfer Interface"
SUBCLASS 0x08, 0x00, "",	"SERCOS Interface Standard (IEC 61491)"
SUBCLASS 0x09, 0x00, "",	"CANbus"
SUBCLASS_EOL

sc0d$:
SUBCLASS 0x00, 0x00, "",	"iRDA Compatible Controller"
SUBCLASS 0x01, 0x00, "",	"Consumer IR Controller"
SUBCLASS 0x10, 0x00, "",	"RF Controller"
SUBCLASS 0x11, 0x00, "",	"Bluetooth Controller"
SUBCLASS 0x12, 0x00, "",	"Broadband Controller"
SUBCLASS 0x20, 0x00, "",	"Ethernet Controller (802.11a)"
SUBCLASS 0x21, 0x00, "",	"Ethernet Controller (802.11b)"
SUBCLASS_EOL

sc0e$:
SUBCLASS 0x00, 0x00, "",	"Message FIFO"
SUBCLASS 0x00, 0xFF, "",	"I20 Architecture"
SUBCLASS_EOL

sc0f$:
SUBCLASS 0x01, 0x00, "",	"TV Controller"
SUBCLASS 0x02, 0x00, "",	"Audio Controller"
SUBCLASS 0x03, 0x00, "",	"Voice Controller"
SUBCLASS 0x04, 0x00, "",	"Data Controller"
SUBCLASS_EOL

sc10$:
SUBCLASS 0x00, 0x00, "",	"Network and Computing Encrpytion/Decryption"
SUBCLASS 0x10, 0x00, "",	"Entertainment Encryption/Decryption"
SUBCLASS_EOL

sc11$:	# data acquisition/signal processing controllers
SUBCLASS 0x00, 0x00, "", "DPIO Modules"
SUBCLASS 0x01, 0x00, "", "Performance Counters"
SUBCLASS 0x10, 0x00, "", "Communications Synchronization Plus Time and Frequency Test/Measurment"
SUBCLASS 0x20, 0x00, "", "Management Card"
SUBCLASS_EOL

scunknown$:
SUBCLASS 0x00, 0xff, "", "unknown"

pci_device_class_names:
.long dc00$, sc00$
.long dc01$, sc01$
.long dc02$, sc02$
.long dc03$, sc03$
.long dc04$, sc04$
.long dc05$, sc05$
.long dc06$, sc06$
.long dc07$, sc07$
.long dc08$, sc08$
.long dc09$, sc09$
.long dc0a$, sc0a$
.long dc0b$, sc0b$
.long dc0c$, sc0c$
.long dc0d$, sc0d$
.long dc0e$, sc0e$
.long dc0f$, sc0f$
.long dc10$, sc10$
.long dc11$, sc11$


# PCI Driver stuff:
.struct 0
pci_driver_class: .byte 0
pci_driver_subclass: .byte 0
	.word 0
pci_driver_vendor_id: .word 0
pci_driver_device_id: .word 0
pci_driver_shortname: .long 0
pci_driver_longname: .long 0

pci_driver_super_init: .long 0
pci_driver_init: .long 0
pci_driver_api_start: .long 0
pci_driver_api_size: .long 0

PCI_DRIVER_DECLARATION_SIZE = .

.macro DECLARE_PCI_DRIVER pciclass, base, vendor, device, shortname, longname, init
	.data SECTION_DATA_PCI_DRIVERINFO # \kind (NIC,VID,USB..ignore)
	.long DEV_PCI_CLASS_\pciclass
	.word \vendor, \device
	.long 1199f	# shortname
	.long 1198f	# longname

	.long \base\()_obj_init
	.long \init
	.long \base\()_api
	.long \base\()_api_end - \base\()_api
	.data SECTION_DATA_STRINGS
	1199:	.asciz "\shortname"
	1198:	.asciz "\longname"
	.text32
.endm


.text32

# in: bx = pci_class
pci_list_drivers:
	mov	esi, offset data_pci_driverinfo_start
	jmp	1f
0:
	cmp	bx, [esi + pci_driver_class]
	jnz	2f

	printc	11, "vendor "
	mov	dx, [esi + pci_driver_vendor_id]
	call	printhex4
	printc	11, " device "
	mov	dx, [esi + pci_driver_vendor_id]
	call	printhex4
	call	printspace

	push	esi
	pushcolor 14
	mov	esi, [esi + pci_driver_shortname]
	call	print
	call	printspace
	popcolor
	pop	esi

	pushcolor 15
	push	esi
	mov	esi, [esi + pci_driver_longname]
	call	println
	pop	esi
	popcolor

2:	add	esi, PCI_DRIVER_DECLARATION_SIZE

1:	cmp	esi, offset data_pci_driverinfo_end
	jb	0b
	ret


# NOTE! This method is optimized according to the device structure
# above.
#
# in: ebx = pci_dev subclass object
pci_find_driver:
	# check for supported drivers
	push	esi
	push	eax

	mov	esi, offset data_pci_driverinfo_start
	jmp	1f

0:	push	esi

	lodsd	# pci class stuff
	cmp	eax, [ebx + dev_pci_class]
	jnz	2f
	lodsd	# vendor | (device <<16)
	cmp	eax, [ebx + dev_pci_vendor]
	jz	0f

2:	pop	esi
	add	esi, PCI_DRIVER_DECLARATION_SIZE
1:	cmp	esi, offset data_pci_driverinfo_end
	jb	0b

	.if 0 # PCI_DEV_DEBUG
		push	edx
		printc 12, "No driver for vendor "
		mov	edx, [ebx + dev_pci_vendor]
		call	printhex4
		printc 12, " device "
		shr	edx, 16
		call	printhex4
		call	newline
		pop	edx
	.endif
8:	stc

9:	pop	eax
	pop	esi
	ret

	# Found driver
0:	add	esp, 4	# 'pop' esi - not needed for loop anymore

	lodsd	# short name
	mov	[ebx + dev_drivername_short], eax
	lodsd	# long name
	mov	[ebx + dev_drivername_long], eax

	lodsd	# obj_init method (base class constructor)
	or	eax, eax
	jz	1f	# sanity check - can't happen
	add	eax, [realsegflat]
	push	esi
	call	eax
	pop	esi

1:	lodsd	# init method
	or	eax, eax	# sanity check
	jz	8b
	add	eax, [realsegflat]
	push	esi
	call	eax
	pop	esi
	jc	9b

	# relocate methods
	push_	ecx edx
	lodsd	# api
	lea	edx, [ebx + edx]
	lodsd	# api size
	mov	ecx, eax
	shr	ecx, 2
	jz	1f

	mov	eax, [realsegflat]
0:	add	[edx + ecx * 4 - 4], eax
	loop	0b
1:
	pop_	edx ecx
	clc
	jmp	9b

	ret

# in: al = eax = pci device class
# in: dh = prog if
# in: dl = subclass
# out: esi points to subclass structure
pci_get_device_subclass_info:
	mov	esi, [pci_device_class_names + 4 + eax * 8]
	push	eax
	# entrylen is 10: byte subclass, byte prog if, long name, long devname
5:	mov	ax, [esi]
	cmp	al, dl		# check subclass
	jne	6f
	cmp	ah, 0xff	# check prog if
	je	9f
	cmp	dh, ah
	je	9f

6:	add	esi, 10
	cmp	al, 0x80
	jne	5b
DEBUG "not found"
	stc
	mov	esi, offset scunknown$

9:	pop	eax
	ret


.data

dev_pci_obj_counters: .long 0
.text32
pci_clear_obj_counters:
	push	eax
	push	ecx
	mov	eax, [dev_pci_obj_counters]
	or	eax, eax
	jz	1f
	call	array_free
1:	mov	eax, 16
	mov	ecx, 5
	call	array_new
	mov	[dev_pci_obj_counters], eax
	pop	ecx
	pop	eax
	ret

# in: eax = const device class name pointer
# out: al = object counter
pci_get_obj_counter:
	push	esi
	push	edi
	push	ecx

	mov	esi, eax
	call	strlen
	mov	ecx, eax
	mov	eax, [dev_pci_obj_counters]
	ARRAY_ITER_START eax, edx
	mov	edi, [eax + edx]
	call	strncmp
	jz	0f
	ARRAY_ITER_NEXT eax, edx, 5

	mov	ecx, 5
	call	array_newentry
	mov	[dev_pci_obj_counters], eax
	mov	[eax + edx], esi

0:	add	edx, eax
	mov	al, [edx + 4]
	inc	byte ptr [edx + 4]

	pop	ecx
	pop	edi
	pop	esi
	ret

pci_list_obj_counters:
	mov	eax, [dev_pci_obj_counters]
	or	eax, eax
	jz	0f
	ARRAY_ITER_START eax, ecx
	mov	esi, [eax + ecx]
	call	print
	call	printspace
	movzx	edx, byte ptr [eax + ecx + 4]
	call	printdec32
	call	newline
	ARRAY_ITER_NEXT eax, ecx, 5
0:	ret


pci_list_devices:

	call	pci_clear_obj_counters

	xor	cx, cx	# bus 0, dev 0
loop$:

	mov	ax, cx	# bus, device
	xor	bl, bl	# 0: device id, vendor
	call	pci_read_config

	inc	eax
	jz	1f	# nonexistent device
	dec	eax

			push	eax	# remember device, vendor (pop as edi)
	###################
	call	newline
	PRINTc	10, "Bus "
	mov	dl, ch
	COLOR	7
	call	printhex2


	PRINTc	11, " Slot "
	mov	dl, cl
	COLOR	7
	call	printhex2

	###################
	PRINTc	12, " Vendor "
	mov	edx, eax
	COLOR	7
	call	printhex4


	PRINTc	13, " Device ID "
	shr	edx, 16
	COLOR	7
	call	printhex4

	#################
	mov	bl, 4	# status, command
	mov	ax, cx
	call	pci_read_config

	mov	esi, eax	# backup command & status

	PRINTc	8, " Command "
	mov	edx, eax
	COLOR	7
	call	printhex4

	PRINTc	8, " Status "
	shr	edx, 16
	COLOR	7
	call	printhex4


	call	newline

	#################
	mov	bl, 8	# class code, subclass, prog IF, revision id
	mov	ax, cx
	call	pci_read_config

	mov	edx, eax

			push	edx
			mov	al, DEV_TYPE_PCI
			call	dev_getinstance	# in: al, cx; out: eax+edx
			jnc	2f
			mov	al, DEV_TYPE_PCI
			call	dev_newinstance	# in: al, edx
		2:	lea	edi, [eax + edx]
			mov	[edi + dev_pci_addr], cx
			pop	edx

			pop	eax	# device/vendor
			mov	[edi + dev_pci_vendor], ax
			shr	eax, 16
			mov	[edi + dev_pci_device_id], ax

	PRINTc	8, " Revision "
	COLOR	7
	call	printhex2

	PRINTc	8, " Class "
	COLOR	7
	rol	edx, 8	# subclass, prog if, rev id, class
	call	printhex2
	PRINTCHAR '.'

			mov	[edi + dev_pci_class], dl


	rol	edx, 8	# prog if, rev id, class, subclass
	call	printhex2
	PRINTCHAR '.'

			mov	[edi + dev_pci_subclass], dl

	rol	edx, 8	# rev id, class, subclass, prog if
	call	printhex2

			mov	[edi + dev_pci_progif], dl

	################################################################
	ror	edx, 8	# prog if, rev, class, subclass
	movzx	eax, dh
	cmp	eax, PCI_MAX_KNOWN_DEVICE_CLASS
	ja	4f
	PRINTCHAR ' '

	rol	edx, 8	# rev, class, subclass, prog if


	COLOR	14
	########### find device - subclass & if

	push	esi

	# al = eax = device class
	# dh = subclass
	# dl = prog if
	xchg	dh, dl
	call	pci_get_device_subclass_info
	mov	esi, [esi + 2]
	call	print


	COLOR 15
	PRINTCHAR ' '
	mov	esi, [pci_device_class_names + 0 + eax * 8]
	call	println

	pop	esi

4:	################################################################
	#################

	mov	bl, 12	# BIST, header type, latency timer, cache line size
	mov	ax, cx
	call	pci_read_config

	.if 1
	PRINTc	8, "   Cache Line Size "	# (optional) - word units
	mov	edx, eax
	COLOR	7
	call	printhex2

	PRINTc	8, " Latency Timer "	# (optional)
	shr	edx, 8
	COLOR	7
	call	printhex2

	# Header type specfices layout of data at address 16 (0x10)
	# x00: general device
	# x01: PCI-to-PCI bridge
	# x02: cardbus bridge
	# bit 7: multiple functions (1)/single function (0)
	PRINTc	8, " Header Type "
	shr	edx, 8
	COLOR	7
	call	printhex2

	# BIST: bits:
	# 7	BIST capable
	# 6	start BIST; cleared within 2 seconds
	# 4:5	reserved
	# 3:0	completion code: 0 = success
	ror	dx, 8
	test	dl, 1 << 7
	jz	4f
	PRINTc	8, " BIST "		# (optional) built-in self test
	COLOR	7
	call	printhex2
4:
	call	newline
	.else
	mov	edx, eax
	ror	edx, 16
	ror	dx, 8
	.endif

	#################### detailed print of header type
	# dh = header type field.
	push	esi	# preserve command & status
	LOAD_TXT " Single function"
	test	dh, 0x80
	jz	2f
	LOAD_TXT " Multiple function"
2:	COLOR 7
	call	print
	pop	esi
	and	dh, 0x7f
	jz	std$
	cmp	dh, 1
	jz	pci2pci$
	cmp	dh, 2
	jz	cardbus$

	printc 4, " Unknown header type: "
	shr dx, 8
	COLOR 4
	call	printhex4
	call	newline
	jmp	cont$	# we don't know the layout beyond 0x10.

# Header Type 2: PCI-to-CardBus bridge
cardbus$:
	PRINTLNc 	6, " PCI-to-CardBus Bridge"
	# 0x10: dd cardbus socket/ExCa base address
	# 0x14: dw secondary status, db reserved, db offset of cap list
	# 0x18: latency timer, subordinate bus nr, cardbus nr, pci bus nr
	# 0x1c: memory base address 0
	# 0x20: memory limit 0
	# 0x24: memory base address 1
	# 0x28: memory limit 1
	# 0x2c: IO base address 0
	# 0x30: IO limit 0
	# 0x34: IO base address 1
	# 0x38: IO limit 1
	# 0x3c: dw bridge control, db interrupt pin, db interrupt line
	# 0x40: subsystem vendor id, subsystem device id
	# 0x44: 16bit PC Card legacy mode base address
	jmp	cont$

# Header type 1
pci2pci$:
	PRINTLNc 	7, " PCI-to-PCI Bridge"
	call	pci_list_pcibridge$

	jmp	0f

std$:	# Header Type 0
	PRINTc 	3, " General device"

	# print 0x10-0x24 (inclusive): Base Address #0-#5
	mov	bl, 0x10
2:	call	pci_list_bar$
	add	bl, 4
	cmp	bl, 0x24
	jbe	2b

	# bl = 0x28
	# 0x28: dd cardbus cis poiner

	mov	ax, cx
	call	pci_read_config
	or	eax, eax
	jz	4f
	PRINTc	8, "   CIS Ptr " # Card Information Structure
	mov	edx, eax
	call	printhex8
4:
	call	newline

	# 0x2c: subsystem id, subsystem vendor id
	mov	bl, 0x2c
	mov	ax, cx
	call	pci_read_config

			mov	[edi + dev_pci_subvendor], eax

	PRINTc	8, " SubSystem Vendor ID "
	mov	edx, eax
	call	printhex4
	shr	edx, 16
	PRINTc	8, " ID "
	call	printhex4

	mov	ax, cx
	mov	bl, 0x30
	call	pci_read_config
	or	eax, eax
	jz	4f
	PRINTc	8, " Expansion ROM BAR "
	mov	edx, eax
	call	printhex8
4:
	call	newline

	##################################################
	# 0x34: reserved db 3 dup(0), cap_ptr db 0
	# test whether available
	test	esi, PCI_STATUS_CAPABILITIES_LIST << 16
	jz	4f

	call	pci_list_caps$
4:

	# skip 0x38 - reserved

	# 0x3c: max latency, min grant, interrupt pin, interrupt line
	mov	ax, cx
	mov	bl, 0x3c
	call	pci_read_config
	or	eax, eax
	jz	0f
	PRINTc	8, "   Interrupt Line "
	mov	edx, eax
	call	printhex2

			mov	[edi + dev_irq], dx

	PRINTc	8, "   Interrupt PIN "
	shr	edx, 8
	call	printhex2

	PRINTc	8, "   Min Grant "
	shr	edx, 8
	call	printhex2

	PRINTc	8, "   Max latency "
	shr	edx, 8
	call	printhex2

	call	newline
0:

			mov	ebx, edi
			push	ecx
			call	[edi + dev_api_constructor]
			pop	ecx

###################
cont$:
1:	inc	cl
	cmp	cl, 0x1f
	jbe	loop$
	xor	cl, cl
	inc	ch
	jnz	loop$

	ret


##### some reusable functions from pci_list above:
pci_list_pcibridge$:
.if 1
	# layout: PCI-to-PCI.Bridge.Architecture.Specification.Rev1.1.pdf p25
	# 0x10: BAR 0
	# 0x14: BAR 1
	# 0x18: [2nd Latency Timer][Subordinate Bus nr][secnd bus nr][prim bus nr]
	# 0x1c: [word: 2nd status][byte:IO limit][byte:IO base]
	# 0x20: [word: mem limit][word: mem base]
	# 0x24: [prefetchable mem limit][prefetchable mem base]
	# 0x28: prefetchable base upper 32 bits
	# 0x2c: prefetchable limit upper 32 bits
	# 0x30: [io limit upper 16][io base upper 16]
	# 0x34: [reserved][byte: capabilities pointer]
	# 0x38: expansion rom base address
	# 0x3c: [word: bridge control][interrupt pin][interrupt line]
	mov	bl, 0x10
	call	pci_list_bar$
	mov	bl, 0x14
	call	pci_list_bar$
# not printed, as VMWare's values are 0 up to 0x2c,
# which returns the subsystem vendor id and device id,
# and -1 afterwards.
	mov	bl, 0x18
	mov	ax, cx
	call	pci_read_config
	DEBUG_BYTE al, "prim bus"
	DEBUG_BYTE ah, "2nd bus"
	shr	eax, 16
	DEBUG_BYTE al, "sub bus"
	DEBUG_BYTE ah, "2nd lat timer"


	mov	bl, 0x1c	# [word:status][byte io limit][byte io base]
	mov	ax, cx
	call	pci_read_config
	mov	edx, eax
	shr	edx, 16
	printc 8, "2nd status"
	call	printhex4
	call	newline


	print	"  IO Base="
	push	edi
	xor	dl, dl

	# upper 4 bits = [15:12] of address; [11:0] = 0 for base, 0xffff for limit
	mov	dh, al
	and	dh, ~0b1111
	and	al, 0b1111
	jz	11f	# 16 bit

	# read high 16 bits for base & limit
	push	eax
	push	edx
	mov	bl, 0x30
	mov	ax, cx
	call	pci_read_config
	mov	dx, ax
	call	printhex4	# print 31:16 of io base
	pop	edx
	mov	edi, eax
	pop	eax
	shr	edi, 16
11:	call	printhex4	# print 15:12 of io base

	print " Limit="
	mov	dh, ah
	and	ah, 0b1111
	jz	11f

	mov	edx, edi
	call	printhex4

11:	or	dx, 0xfff
	call	printhex4

	pop	edi

	call	newline

	####


	mov	bl, 0x20	# each word's [15:4] (12) is 31:20; 3:0 = 0
	mov	ax, cx
	call	pci_read_config
	print "  Memory Base="
	mov	dx, ax
	#and	dl, ~0b1111
	shl	edx, 16
	call	printhex8

	print " Limit="
	mov	edx, eax
	and	edx, 0xfff00000
	call	printhex8
	call	newline

	# if the mem prefetch limit is less than the base, and no mmio,
	# mem transactions are forwarded from the secondary to the primary.
	print "  Prefetchable Memory: Base="
	mov	bl, 0x24	# lo word: high 16 of mem base; hi word: limit
	mov	ax, cx
	call	pci_read_config
	# both low 4 bit of each word must be 0b0000 for 32 bit
	# or 0b1111 for 64 bit

	mov	dl, al
	and	al, ~0b1111
	and	dl, 0b1111
	jz	11f
	# only 0b0000 and 0b0001 are allowed: 32 and 64 bit addressing.

	push	eax
	mov	bl, 0x28	# read high 32 bit of mem base
	mov	ax, cx
	call	pci_read_config
	mov	edx, eax
	pop	eax
	call	printhex8
	call	printspace
11:
	mov	dx, ax		# lo 4 bits is masked: hi 16 bits
	shl	edx, 16
	call	printhex8

	shr	eax, 16
	push	eax	# remember prefetchable memory limit low 16
	print " Limit="

	mov	dl, al
	and	al, ~0b1111
	and	dl, 0b1111
	jz	11f
	# assert dl = 0b1111

	push	eax
	mov	bl, 0x2c	# read high 32 bit of mem limit
	mov	ax, cx
	call	pci_read_config
	mov	edx, eax
	pop	eax
	call	printhex8
	call	printspace
11:
	pop	edx
#	and	edx, 0xfff00000
	or	edx, 0x000fffff
	call	printhex8
	call	newline

	# 0x34: capabilities pointer (identical to header type=0)
	call	pci_list_caps$


	mov	bl, 0x38
	mov	ax, cx
	call	pci_read_config
	DEBUG_DWORD eax, "expansion rom base address"
	call	newline

	# 0x3c: identical to standard header except for bridge control
	mov	bl, 0x3c
	mov	ax, cx
	call	pci_read_config
	DEBUG_BYTE al, "interrupt line"
	DEBUG_BYTE ah, "interrupt pin"
	shr	eax, 16
	DEBUG_WORD ax, "bridge control"
	call	newline
.endif
	ret



# in: cx = pci address (bus etc)
# in: bl = BARx pci address (BAR0 is usualy 0x10 / 16)
# in: edi = dev ptr, to be updated with dev_io(_size) and dev_mmio(_size).
#  the last match will be the one used.
pci_list_bar$:
	mov	ax, cx
	call	pci_read_config

	or	eax, eax
	jz	4f
##
	push	eax

	# Memory BAR:
	# bits 31:4:	16 byte aligned base address (& ~ 0b1111)
	# bit  3:	prefetchable
	# bits 2:1	type
	# bit  0:	0

	# IO BAR:
	# bits 31:2:	4 byte aligned base address
	# bit  1:	reserved
	# bit  0:	1
	PRINTc	8, "  BAR"
	mov	dl, bl
	sub	dl, 16
	shr	dl, 2
	call	printhex1

	PRINT ": "
	mov	edx, eax
	call	printhex8

	# create mask: bit 0 = 1: 11b (IO) bit 0 = 0: 1111b (MEM)
	push	ecx
	mov	cl, al
	and	cl, 1	# 1 = 4 byte io, 0 = 16 byte mem
	mov	bh, 0b1111
	shl	cl, 1	# 2 or 0
	shr	bh, cl	# 0b11 or 0b1111
	not	bh	# mask 0b11110000 or 0b11111100
	pop	ecx

			push	edi

	test	al, 1
	jz	3f
#
	print " IO "
	and	dl, ~ 0b11

			mov	[edi + dev_io], edx
			add	edi, dev_io_size

	jmp	5f
#
3:	print " MEM "
	test	dl, 1<<3
	jz	3f
	print "PF "	# prefetchable
3:	and	dl, ~ 0b1111

			mov	[edi + dev_mmio], edx
			add	edi, dev_mmio_size

	and	al, 0b110
	cmp	al, 0 << 1
	jz	3f
	cmp	al, 2 << 1
	jz	6f
	print "?? "
	jmp	5f
6:	print "64 "
	jmp	5f
3:	print "32 "
	#jmp	5f
5:
	call	printhex8
	print "-"

#
	mov	ax, cx
	mov	edx, -1	# determine memory used
	call	pci_write_config
	mov	edx, eax
	and	dl, bh
	not	edx
	inc	edx	# edx = memory/io size used

			mov	[edi], edx
			pop	edi

	#call	printhex8
	#call	printspace
	add	edx, [esp]
	and	dl, bh
	call	printhex8
	# restore original address
	pop	edx
	mov	ax, cx
	call	pci_write_config

4:
	ret


pci_list_caps$:
	mov	ax, cx
	mov	bl, 0x34
	call	pci_read_config
	cmp	al, 0x40	# officially. usually 0 or 40
	jb	4f
44:	PRINTc	8, " Capability @ "
	mov	dl, al
	call	printhex2

	mov	bl, al
	and	bl, ~3	# low 2 bits are reserved
	mov	ax, cx
	call	pci_read_config
	mov	edx, eax
	printc	8, ": "
	call	printhex2
	# (ECN_ClassCodeCapID_Extraction_2010-04-28.pdf)
	# 0x00: reserved
	# 0x01: power management
	# 0x02: agp
	# 0x03: vital product data
	# 0x04: slot numbering cap id: arg=word[chassis nr, expansion slot]
	# 0x05: message signaled interrupts
	# 0x06: compactpci
	# 0x07: PCI-X 2.0+; args: [.word cmd_reg;] .long status,ecc_ctrl_st,ecc_1st,ecc_2nd,ecc_attr
	# 0x08: hypertransport
	# 0x09: vendor specific; byte after next ptr is length (eax & 0x00ff0000)
	# 0x0a: debug port
	# 0x0b: CompactPCI central resource control
	# 0x0c: PCI hotplug
	# 0x0d: pci bridge subsystem vendor id
	# 0x0e: AGP 8x
	# 0x0f: secure device
	# 0x10: PCI express
	# 0x11: MSI-X (message signalled interrupts)
	# 0x12-0xff: reserved
	printc 8, " next: " 
	shr	edx, 8
	call	printhex2
	printc 8, " arg: "
	shr	edx, 8
	call	printhex4
	call	printspace

	PRINTIF al, 0x01, "power management"
	PRINTIF al, 0x02, "agp"
	PRINTIF al, 0x03, "vital product data"
	PRINTIF al, 0x04, "slot numbering"# cap id: arg=word[chassis nr, expansion slot]"
	PRINTIF al, 0x05, "MSI"#message signaled interrupts"
	PRINTIF al, 0x06, "CompactPCI"
	PRINTIF al, 0x07, "PCI-X"# 2.0+; args: [.word cmd_reg;] .long status,ecc_ctrl_st,ecc_1st,ecc_2nd,ecc_attr"
	PRINTIF al, 0x08, "HyperTransport"
	PRINTIF al, 0x09, "Vendor Specific"#; byte after next ptr is length (eax & 0x00ff0000)"
	PRINTIF al, 0x0a, "Debug Port"
	PRINTIF al, 0x0b, "CompactPCI central resource control"
	PRINTIF al, 0x0c, "PCI hotplug"
	PRINTIF al, 0x0d, "pci bridge subsystem vendor id"
	PRINTIF al, 0x0e, "AGP 8x"
	PRINTIF al, 0x0f, "secure device"
	PRINTIF al, 0x10, "PCI express"
	PRINTIF al, 0x11, "MSI-X"# (message signalled interrupts)"

	call	newline
	mov	al, ah
	or	al, al
	jnz	44b

4:	ret



# in: ah = bus (8 bits), al=slot (5 bits)
# in: bl = register/offset (4 byte align)
# out: eax
pci_read_config:
	push	edx
	# eax: |                      | bbbbbbbb  | 000 ddddd |
	and	eax, 0x0000ff1f	# ah & 8 bits, al & 5 bits

	shl	al, 3		# low 3 bits: func 0
	shl	eax, 8
	and	bl, 0b11111100	# register dword align
	mov	al, bl		# low 8 bits: register
	or	eax, 1<<31

	# eax: | 1 0000000 | bbbbbbbb | ddddd fff | rrrrrr 00 |

	mov	dx, IO_PCI_CONFIG_ADDRESS
	out	dx, eax
	add	dx, 4
	in	eax, dx
	pop	edx
	ret

# in: ah = bus (8 bits) al = slot (5 bits)
# in: bl = register (4 byte align)
# in: edx = value to write
# out: eax = value readback
pci_write_config:
	push	edx
	and	eax, 0x0000ff1f
	shl	al, 3
	shl	eax, 8
	and	bl, 0b11111100
	mov	al, bl
	or	eax, 1 << 31

	mov	dx, IO_PCI_CONFIG_ADDRESS
	out	dx, eax
	add	dx, 4
	mov	eax, [esp]
	out	dx, eax
	in	eax, dx
	pop	edx
	ret

# in: cx = pci addr
# in: al = bar nr
pci_get_bar:
	push_	ecx ebx
	mov	bl, al
	shl	bl, 2
	add	bl, PCI_CFG_BAR0
	mov	ax, cx
	call	pci_read_config
	pop_	ebx ecx
	ret

pci_get_bar_addr:
	call	pci_get_bar
	test	al, 1
	jz	1f
	and	al, ~3
	ret
1:	and	al, ~15
	ret


# in: ax = pci addr ( bus << 8 | slot )
pci_busmaster_enable:
	push_	ebx edx ecx
	mov	ecx, eax	# remember pci addr

	mov	bl, PCI_CFG_STATUS_COMMAND
	call	pci_read_config

	or	al, PCI_CMD_BUSMASTER | PCI_CMD_IO_SPACE | PCI_CMD_MEM_SPACE
	mov	edx, eax

	mov	bl, PCI_CFG_STATUS_COMMAND
	mov	eax, ecx
	call	pci_write_config

	test	al, PCI_CMD_BUSMASTER
	jnz	0f
	printlnc 4, "warning: PCI busmaster enable failed"

0:	pop_	ecx edx ebx
	ret

pci_print_dev$:
	inc	eax
	jz	1f
	dec	eax
	PRINT	"PCI Device: Vendor "
	mov	edx, eax
	call	printhex
	PRINT	" Device: "
	ror	edx, 16
	call	printhex
	call	newline
1:	ret




#############################################################################
# TEMPORARY HERE: some null-drivers for known devices at this time.
.struct 0
nulldev_api:
nulldev_api_end:



#Bus 00 Slot 00 Vendor 8086 7190 Command 0006 Status 0200
DECLARE_PCI_DRIVER BRIDGE, nulldev, 0x8086, 0x7190, "i440", "Intel 440BX/ZX/DC Host Bridge", dev_pci_null_driver
#Bus 00 Slot 01 Vendor 8086 7191 Command 011f Status 0220 Revision 01 Class 06.04.00 PCI-to-PCI Single functionPCI-to-CardBus Bridge
DECLARE_PCI_DRIVER BRIDGE_PCI2PCI,    nulldev, 0x8086, 0x7191, "i440agp", "Intel 440 AGP Bridge", dev_pci_null_driver
#Bus 00 Slot 07 Vendor 8086 7110 Command 0007 Status 0280 Revision 08 Class 06.01.00 ISA Bridge Device Multiple function General device SubSystem Vendor ID 15ad ID 1976
DECLARE_PCI_DRIVER BRIDGE_ISA, nulldev, 0x8086, 0x7110, "ipiix4", "Intel PIIX4 ISA Host Bridge", dev_pci_null_driver

#Bus 00 Slot 0f Vendor 15ad 0405 Command 0003 Status 0290 Revision 00 Class 03.00.00 VGA Compatible Display Controller > VMWare SVGA II 
# implemented in mware/svga2.s

#Bus 00 Slot 10 Vendor 104b 1040 Command 0007 Status 0280 Revision 01 Class 01.00.00 SCSI Bus Mass Storage Controller Single function General device  SubSystem Vendor ID 104b ID 1040 
DECLARE_PCI_DRIVER STORAGE_SCSI,      nulldev, 0x104b, 0x1040, "scsi???", "SCSI mass storage", dev_pci_null_driver


# VMWare

#DECLARE_PCI_DRIVER VID_VGA          , nulldev, 0x15ad, 0x0405, "vmwsvga2", "VMWare SVGA II Adapter", dev_pci_null_driver
DECLARE_PCI_DRIVER VID_VGA          , nulldev, 0x15ad, 0x0710, "vmwsvga", "VMWare SVGA Adapter", dev_pci_null_driver
DECLARE_PCI_DRIVER NIC_ETH   ,        nulldev, 0x15ad, 0x0720, "vmxnet", "VMWare VMXNET Ethernet Controller", dev_pci_null_driver
DECLARE_PCI_DRIVER BRIDGE   ,         nulldev, 0x15ad, 0x0740, "vmwci", "VMWare Communication Interface", dev_pci_null_driver
DECLARE_PCI_DRIVER SERIAL_USB,        nulldev, 0x15ad, 0x0770, "vmwusb2.0", "VMWare USB2 EHCI Controller", dev_pci_null_driver

DECLARE_PCI_DRIVER SERIAL_USB       , nulldev, 0x15ad, 0x0774, "vmwusb1.1", "VMWare USB 1.1 UHCI", dev_pci_null_driver
# subsys: 15ad 1976

#Bus 00 Slot 11 Vendor 15ad 0790 Command 0007 Status 0290 Revision 02 Class 06.04.01 PCI-to-PCI (Subtractive Decode) Bridge Device
DECLARE_PCI_DRIVER BRIDGE_PCI2PCI_SD, nulldev, 0x15ad, 0x0790, "vmwbridge", "VMWare PCI Bridge", dev_pci_null_driver


# These are pci-to-cardbrige PCI config layouts - not implemented.
#Bus 00 Slot 16 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Multiple functionPCI-to-CardBus Bridge
#Bus 00 Slot 17 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Multiple functionPCI-to-CardBus Bridge
#Bus 00 Slot 18 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Single function General device  SubSystem Vendor ID 15ad 1976
DECLARE_PCI_DRIVER BRIDGE_PCI2PCI   , nulldev, 0x15ad, 0x07a0, "vmwbridge", "VMWare PCI Express Root Port", dev_pci_null_driver
DECLARE_PCI_DRIVER NIC_ETH   ,        nulldev, 0x15ad, 0x07b0, "vmxnet3", "VMWare VMXNET3 Ethernet Controller", dev_pci_null_driver
DECLARE_PCI_DRIVER STORAGE_SCSI   ,   nulldev, 0x15ad, 0x07c0, "vmwscsi", "VMWare PVSCSI SCSI Controller", dev_pci_null_driver
DECLARE_PCI_DRIVER BRIDGE/*???*/  ,   nulldev, 0x15ad, 0x0801, "vmwi", "VMWare Virtual Machine Interface", dev_pci_null_driver
# and subsys 15ad 8000 : hypervisor rom interface
#


#Bus 02 Slot 01 Vendor 1022 2000 Command 0003 Status 0280 Revision 10 Class 02.00.00 Ethernet Network Controller SubSystem Vendor ID 1022 ID 2000
#Bus 02 Slot 02 Vendor 1274 1371  Revision 02 Class 04.01.00 Audio Device Multimedia Controller Single function General device  SubSystem Vendor ID 1274 ID 1371
DECLARE_PCI_DRIVER MM_AUDIO, nulldev, 0x1274, 0x1371, "audio", "Ensoniq AudioPCI-97", dev_pci_null_driver


#Bus 02 Slot 03 Vendor 15ad 0770 Command 0002 Status 0000 Single function General device  SubSystem Vendor ID 15ad ID 0770 > EHCI Driver USB 2.14
# Implemented in usb.s

#15ad VMWare
#        0405  SVGA II Adapter
#        0710  SVGA Adapter
#        0720  VMXNET Ethernet Controller
#        0740  Virtual Machine Communication Interface
#        0770  USB2 EHCI Controller
#        0774  USB1.1 UHCI Controller
#        0790  PCI bridge
#        07a0  PCI Express Root Port
#        07b0  VMXNET3 Ethernet Controller
#        07c0  PVSCSI SCSI Controller
#        0801  Virtual Machine Interface
#                15ad 0800  Hypervisor ROM Interface
#


.text32
nulldev_obj_init:
	ret
dev_pci_null_driver:
	DEBUG "NULL Driver:"
	push	esi
	lea	esi, [ebx + dev_name]
	call	print
	DEBUG "driver:"
	mov	esi, [ebx + dev_drivername_short]
	call	print
	DEBUG ":"
	mov	esi, [ebx + dev_drivername_long]
	call	print
	cmp	[ebx + dev_pci_subvendor], word ptr 0x15ad
	jnz	1f
	cmp	[ebx + dev_pci_subdevice],word ptr  0x1976
	jnz	1f
	printc	11, " Virtual Machine"

1:	pop	esi
	call	println
	ret






#Bus 00 Slot 00 Vendor 8086 7190 Command 0006 Status 0200
#Bus 00 Slot 01 Vendor 8086 7191 Command 011f Status 0220 Revision 01 Class 06.04.00 PCI-to-PCI Single functionPCI-to-CardBus Bridge
#Bus 00 Slot 07 Vendor 8086 7110 Command 0007 Status 0280 Revision 08 Class 06.01.00 ISA Bridge Device Multiple function General device SubSystem Vendor ID 15ad ID 1976
#Bus 00 Slot 0f Vendor 15ad 0405 Command 0003 Status 0290 Revision 00 Class 03.00.00 VGA Compatible Display Controller > VMWare SVGA II 
#Bus 00 Slot 10 Vendor 104b 1040 Command 0007 Status 0280 Revision 01 Class 01.00.00 SCSI Bus Mass Storage Controller Single function General device  SubSystem Vendor ID 104b ID 1040 
#Bus 00 Slot 11 Vendor 15ad 0790 Command 0007 Status 0290 Revision 02 Class 06.04.01 PCI-to-PCI (Subtractive Decode) Bridge Device
#Bus 00 Slot 16 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Multiple functionPCI-to-CardBus Bridge
#Bus 00 Slot 17 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Multiple functionPCI-to-CardBus Bridge
#Bus 00 Slot 18 Vendor 15ad 07a0 Command 0007 Status 0010 Revision 01 Class 06.04.00 PCI-to-PCI Single function General device  SubSystem Vendor ID 15ad 1976
#Bus 02 Slot 01 Vendor 1022 2000 Command 0003 Status 0280 Revision 10 Class 02.00.00 Ethernet Network Controller SubSystem Vendor ID 1022 ID 2000
#Bus 02 Slot 02 Vendor 1274 1371  Revision 02 Class 04.01.00 Audio Device Multimedia Controller Single function General device  SubSystem Vendor ID 1274 ID 1371
#Bus 02 Slot 03 Vendor 15ad 0770 Command 0002 Status 0000 Single function General device  SubSystem Vendor ID 15ad ID 0770 > EHCI Driver USB 2.14

