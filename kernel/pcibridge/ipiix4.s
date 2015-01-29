###############################################################################
# Intel PIIX4 PCI-to-ISA/IDE Bridge 'Xcelerator'
.intel_syntax noprefix

# Multi-function PCI-to-ISA Bridge device.
#
# Function 0:	(device id 7110)
#   DMA Controller
#   Interupt Controller
#   Counter, Timers, Real Time Clock
#
# Function 1:	(device id 7111)
#   IDE Controller
#
# Function 2:	(device id 7112)
#   USB UHCI Host and Root Hub and 2 USB ports.
#
# Function 3:	(device id 7113)
#   Power Management and System Management Bus.

DECLARE_PCI_DRIVER BRIDGE_ISA,	nulldev,   0x8086, 0x7110, "piix4-isa", "Intel 82371AB/EB/MB PIIX4 ISA Host Bridge"
DECLARE_PCI_DRIVER STORAGE_IDE,	piix4_ide, 0x8086, 0x7111, "piix4-ide", "Intel 82371AB/EB/MB PIIX4 IDE Host Bridge"
DECLARE_PCI_DRIVER SERIAL_USB,	nulldev,   0x8086, 0x7112, "piix4-usb", "Intel 82371AB/EB/MB PIIX4 USB"
DECLARE_PCI_DRIVER BRIDGE_PCI2PCI_STS,nulldev,   0x8086, 0x7113, "piix4-acpi","Intel 82371AB/EB/MB PIIX4 ACPI"


############################################################################
DECLARE_CLASS_BEGIN piix4_ide, dev_pci
dev_ide_dtp_buf:	.long 0	# description table pointer buffer (logical address)
dev_ide_dtp_prim:	.long 0	# DTP for primary channel (logical address)
dev_ide_dtp_sec:	.long 0	# DTP for secondary channel (logical address)
DECLARE_CLASS_METHOD dev_api_constructor, piix4_ide_init, OVERRIDE
DECLARE_CLASS_END piix4_ide

.data
dev_ide: .long 0
.text32

# [dev_io+0], [dev_io+8]
BM_IDE_CMD_RWCON_R	= 0<<3
BM_IDE_CMD_RWCON_W	= 1<<3
BM_IDE_CMD_SSBM_START	= 1
BM_IDE_CMD_SSBM_STOP	= 0

# in: ebx = dev_ide ptr
piix4_ide_init:
	mov [dev_ide], ebx # for ATA routines
	push_	eax ecx edx
	I "Intel PIIX4 IDE Bridge"
	call	newline

	.if 0	# pci_list_devices has filled this in
	print "Bus Master Interface address: "
	mov	dl, 0x20	# BAR 4
	call	dev_pci_read_config
	mov	edx, eax
	call	printhex8
	DEBUG_DWORD [ebx+dev_io],"base"
	DEBUG_DWORD [ebx+dev_io_size],"size"
	DEBUG_DWORD [ebx+dev_pci_addr],"pci-addr"
	call	newline
	.endif

	mov	dl, 12	# 0xc..0xf: 0xd = MLT, master latency timer register
	call	dev_pci_read_config
	mov	dl, ah	# 0xd
	print "MLT "
	call	printhex2
	call	printspace

	mov	dl, 0x04
	call	dev_pci_read_config
	print "PCI Cmd: "
	mov	edx, eax
	call	printhex4

	# only BME (bus master enable) and IOSE (IO space enable) are implemented on the chip.
	print " [BME "; PRINTBITb al, 2
	print " IOSE "; PRINTBITb al, 0

	print "] Status: "
	shr	edx, 16
	call	printhex4
	shr	eax, 16
	PRINT " [MAS "; PRINTBITw ax, 13	# R/WC	master abort status
	PRINT " RTA ";  PRINTBITw ax, 12	# R/WC	received target abort status
	PRINT " STA ";  PRINTBITw ax, 11	# R/WC	signalled target abort status
	PRINT " DEVT "; PRINTBITSw ax, 9, 2	# RO	10:9 devsel timing status (01)
	# 	DPD		8	# N/A 0	Data parity detected
	PRINT " FBC ";  PRINTBITb al, 7		# RO	Fast back-to-back capable
	#			6:0	# reserved: 0
	print	"]"
	call	newline

	mov	dl, 0x40
	call	dev_pci_read_config
	mov	edx, eax	# 40-41: prim, 42-43: second
	print "IDE Timing:"
	call	printhex8
	call newline
	print " PRI: "
	xor	ecx, ecx
0:	mov	edx, eax
	call	printhex4

	mov	edx, eax
	PRINTFLAG ax, 1<<15, " IDE_DE"	#'ide decode enable'->'ide'...
	PRINTFLAG ax, 1<<14, " SITRE"	# Slave IDE Timing Register Enable
	shr	edx, 12
	not	dl
	and	edx, 3
	add	dl, 2
	print " IORDY-SP "	# IO Ready Sample Point (clock)
	call	printhex1
	print " RT "		# Recovery Time
	mov	edx, eax
	shr	edx, 8
	not	dl
	and	edx, 3
	inc	dl
	call	printhex1
	print " [0:"
	# DTE: DMA Timing Enable: 0=DMA and PIO use fast timing; 1=DMA fast,PIO slow
	# PPE: prefetch and posting enable for IDE data port
	# ISP/IE: IORDY Sample Point Enable Drive Select;
	# TIME: fast timing bank drive select: 0=16 bit compat timing of IO range
	# 1 = accesses to data port of enabled IO range use fast timing.
	#     PIO uses fast timing only if PPE=1.
	PRINTFLAG ax, 1<<3, " DTE0" # DMA timing Enable Only
	PRINTFLAG ax, 1<<2, " PPE0" # prefetch and posting enable (IDE data port)
	PRINTFLAG ax, 1<<1, " IE0" # iordy sample point enable drive select 0
	PRINTFLAG ax, 1<<0, " TIME0" # fast timing ban kdrive select
	print "] [1:"
	PRINTFLAG ax, 1<<7, " DTE1" # DMA Timing Enable
	PRINTFLAG ax, 1<<6, " PPE1" # prefetch and posting enable
	PRINTFLAG ax, 1<<5, " IE1" # IORDY sample pointenable drive select 1
	PRINTFLAG ax, 1<<4, " TIME1" # fast timing bank drive select 1
	printchar ']'

	or	ecx, ecx
	jnz	1f
	call	newline
	print " SEC: "
	inc	ecx
	shr	eax, 16
	jmp	0b
1:

	call	newline

	mov	dl, 0x44
	call	dev_pci_read_config
	mov	edx, eax	# byte: high 3 is reserved
	print " Slave IDE Timing: "
	# 1:0: primary drive 1 recovery time:        00=4, 11=1 (clocks)
	# 3:2: primary drive 1 IORDY sample point:   00=5, 11=2
	# 5:4: secondary drive 1 recovery time:      00=4, 11=1 (clocks)
	# 7:6: secondary drive 1 IORDY sample point: 00=5, 11=2
	call	printhex2
	mov	ah, (2<<6)|(1<<4)|(2<<2)|1
	mov	ecx, 4
0:	mov	dx, ax
	shr	ax, 2
	not	dl
	and	dx, 0x0303
	add	dl, dh
	call	printspace
	call	printhex1
	loop	0b
	call	newline

	print "UDMA/33 Control: "
	mov	dl, 0x48	# [48 UDMACTL][49 -][4a-4b UDMATIM]
	call	dev_pci_read_config
	mov	edx, eax	# 4byte
	call	printhex8
	call	newline

	xor	ecx, ecx
0:	print " hd"
	mov	al, 'a'
	add	al, cl
	call	printchar
	call	printspace
	mov	al, dl

	mov	dh, 1
	shl	dl, cl
	PRINTFLAG al, dl, "UDMA/33", "PIO    "	# 1<<[0..3] = udma/33 flag

#	print " hda "; PRINTFLAG al, 1<<0, "UDMA/33","PIO"
#	print " hdb "; PRINTFLAG al, 1<<1, "UDMA/33","PIO"
#	print " hdc "; PRINTFLAG al, 1<<2, "UDMA/33","PIO"
#	print " hdd "; PRINTFLAG al, 1<<3, "UDMA/33","PIO"

	mov	eax, edx
	shr	eax, 16
	shl	cl, 2
	shr	eax, cl
	shr	cl, 2
	and	al, 3
	PRINTIF al, 0b00, "Mode 0 (120ns) CT=4/RP=6"
	PRINTIF al, 0b01, "Mode 1  (90ns) CT=3/RP=5"
	PRINTIF al, 0b10, "Mode 2  (60ns) CT=2/RP=4"
	PRINTIF al, 0b11, "RESERVED"
	call	newline

	inc	cl
	cmp	cl, 4
	jb	0b


	# ATA_PRI.base = BAR0 & ~3 == 0 ? 0x1f0 : ...
	# ATA_PRI.ctrl = BAR1 & ~3 == 0 ? 0x3f4 : ...
	# ATA_SEC.base = BAR2 & ~3 == 0 ? 0x170 : ...
	# ATA_SEC.ctrl = BAR3 & ~3 == 0 ? 0x374 : ...
	# ATA_PRI.bmide= BAR4 & ~3 + 0
	# ATA_SEC.bmide= BAR4 & ~3 + 8
	pushad
	mov	ecx, [ebx + dev_pci_addr]
	xor	bl, bl
0:	mov	al, bl
	call	pci_get_bar
	print " BAR"
	mov	dl, bl
	call	printhex2
	mov	edx, eax
	print ": "
	call	printhex8
	inc	bl
	cmp	bl, 6
	jb	0b
	popad
	call	newline



	######### IO space registers
	print "[I/O]: Bus Master IDE"

	call	newline
	print "  [Primary]   "
	xor	ecx, ecx
0:
	print "Command: "
	mov	dx, [ebx + dev_io]
	add	dx, cx
	in	al, dx
	mov	dl, al
	call	printhex2

	print " Status: "
	mov	dx, [ebx + dev_io]
	add	dx, cx
	add	dx, 2
	in	al, dx
	mov	dl, al
	call	printhex2
	print " [DMA CAP d0:"
	PRINTFLAG al,1<<5,"Y","N"
	print " d1:"
	PRINTFLAG al,1<<6,"Y","N"
	PRINTFLAG al,1<<2," INT"
	PRINTFLAG al,1<<1," ERR"
	PRINTFLAG al,1<<0," BM"
	print "]"

	print " DTPtr: "
	mov	dx, [ebx + dev_io]
	add	dx, cx
	add	dx, 4
	in	eax, dx
	mov	edx, eax
	call	printhex8

	call	newline

	or	ecx, ecx
	jnz	1f
	add	ecx, 8
	print "  [Secondary] "
	jmp	0b
	
1:	

	## set up the description table
	# alloc 64k on 64k boundary
	mov	eax, 1*1024
	mov	edx, 64*1024	# spec is confusing: dword, 4k, 64k..?
	call	malloc_aligned
	jc	9f

	# 1k buffer: 512 bytes per channel, or, 64 entries.

	mov	[ebx + dev_ide_dtp_buf], eax
	mov	ecx, eax
	mov	[ebx + dev_ide_dtp_prim], eax
	add	ecx, 512
	mov	[ebx + dev_ide_dtp_sec], ecx

	GDT_GET_BASE edx, ds
	sub	eax, edx

	# spec for port says dword align, not cross 4k
	mov	dx, [ebx + dev_io]
	add	dx, 4	# + 0 for prim + 8 for sec; 4=BMIDTPX
	out	dx, eax	# prim
	add	dx, 8	# sec
	add	eax, 512
	out	dx, eax

#MORE
0:	
	pop_	edx ecx eax
	ret

9:	printlnc 4, "IDE: can't alloc description table"
	jmp	0b
