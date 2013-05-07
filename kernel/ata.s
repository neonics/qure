###############################################################################
# IDE / ATAPI
.intel_syntax noprefix
.code32

ATA_DEBUG = 0		# 0..4
ATAPI_DEBUG = 0		# 0..3

ATA_MAX_DRIVES = 8	# 4 buses with 2 drives each supported

# PCI: class 1.1 (mass storage . ide)
# BAR0: IO_ATA_PRIMARY			0x1F0
# BAR1: IO_ATA_PRIMARY	 base DCR	0x3F4 (+2 for DCR)
# BAR2: IO_ATA_SECONDARY		0x170
# BAR3: IO_ATA_SECONDARY base DCR	0x374 (+2)
# BAR4: Bus Master ID: 16 ports, 8 ports per DMA
# 'Bus':
IO_ATA_PRIMARY		= 0x1F0	# - 0x1F7 DCR: 0x3f6	RM IRQ 14h
IO_ATA_SECONDARY	= 0x170	# - 0x177 DCR: 0x376	RM IRQ 15h
IO_ATA_TERTIARY		= 0x1E8 # - 0x1EF DCR: 0x3E6    (just before PRIMARY)
IO_ATA_QUATERNARY	= 0x168 # - 0x16F DCR: 0x366	(just before SECONDARY)

# Add these to the IO_ATA_ base:
ATA_PORT_DATA		= 0
ATA_PORT_FEATURE	= 1	# write
  ATA_FEATURE_DMA		= 1 << 0	# 0=PIO, 1=DMA
  ATA_FEATURE_OVERLAP		= 1 << 1
ATA_PORT_ERROR		= 1	# read
  ATA_ERROR_BBK			= 0b10000000	# Bad Block
  ATA_ERROR_UNC			= 0b01000000	# Uncorrectable Data Error
  ATA_ERROR_MC			= 0b00100000	# Media Changed
  ATA_ERROR_IDNF		= 0b00010000	# ID mark not found
  ATA_ERROR_MCR			= 0b00001000	# Media Change Requested
  ATA_ERROR_ABRT		= 0b00000100	# command Aborted
  ATA_ERROR_TK0NF		= 0b00000010	# Track 0 Not Found
  ATA_ERROR_AMNF		= 0b00000001	# Address Mark Not Found
ATA_PORT_SECTOR_COUNT	= 2	# Interrupt Reason register (DRQ)
  ATAPI_DRQ_CoD			= 1 << 0	# 0: user data; 1: command
  ATAPI_DRQ_IO			= 1 << 1	# 1=in(dev->host) 0=out(host->dev)
  ATAPI_DRQ_RELEASE		= 1 << 2	# dev release ata bus before cmd completion
  ATAPI_DRQ_SERVICE	 	= 0x10

  ATAPI_DRQ_DATAIN		= 0b010
  ATAPI_DRQ_DATAOUT		= 0b000
  ATAPI_DRQ_CMDOUT		= 0b001
  ATAPI_DRQ_CMDIN		= 0b011

ATA_PORT_ADDRESS1	= 3	# sector	/ LBA lo
ATA_PORT_ADDRESS2	= 4	# cylinder low	/ LBA mid    Byte Count
ATA_PORT_ADDRESS3	= 5	# cylinder hi	/ LBA high   Byte Count
ATA_PORT_DRIVE_SELECT	= 6
  # bits 7 and 5 obsolete, but must be 1 for old (ATA1) drives (pre LBA48)
  ATA_DRIVE_SELECT_RESERVED7	= 0b10000000
  ATA_DRIVE_SELECT_LBA		= 0b01000000	# Sect. Address Mode 0=CHS 1=LBA
  ATA_DRIVE_SELECT_RESERVED5	= 0b00100000
  ATA_DRIVE_SELECT_DEV		= 0b00010000	# 0=master 1=slave
  ATA_DRIVE_SELECT_ADDR		= 0b00001111	# CHS: head; LBA: [27:24]
  ATA_DRIVE_MASTER	= 0xa0
  ATA_DRIVE_SLAVE	= 0xb0
  # bin: 101DHHHH
  # D: drive (0 = master 1 = slace)
  # HHHH: head selection bits
ATA_PORT_COMMAND	= 7	# write
  ATA_COMMAND_PIO_READ			= 0x20	# LBA28 w/retry; +1=w/o retry
  ATA_COMMAND_PIO_READ_LONG		= 0x22	# w/retry; +1=w/o retry
  ATA_COMMAND_PIO_READ_EXT		= 0x24	# LBA48
  ATA_COMMAND_DMA_READ_EXT		= 0x25	# LBA48
  ATA_COMMAND_PIO_WRITE			= 0x30	# LBA28 w/retry; +1=w/o retry
  ATA_COMMAND_PIO_WRITE_LONG		= 0x32	# w/retry; +1=w/o retry
  ATA_COMMAND_PIO_WRITE_EXT		= 0x34	# LBA48
  ATA_COMMAND_DMA_WRITE_EXT		= 0x35	# LBA48
  ATA_COMMAND_PIO_READ_MULTIPLE		= 0xc4	# see word 47 and 59 of IDENTIFY
  ATA_COMMAND_PIO_WRITE_MULTIPLE	= 0xc5	# for sectors per block
  ATA_COMMAND_SET_MULTIPLE_MODE		= 0xc6	# sets nr of sectors/block
  ATA_COMMAND_DMA_READ			= 0xc8	# LBA28
  ATA_COMMAND_DMA_WRITE			= 0xca	# LBA28
  ATA_COMMAND_CACHE_FLUSH		= 0xe7
  ATA_COMMAND_CACHE_FLUSH_EXT		= 0xea
  ATA_COMMAND_IDENTIFY			= 0xec

  ATAPI_COMMAND_PACKET			= 0xa0
  ATAPI_COMMAND_IDENTIFY		= 0xa1
  ATAPI_COMMAND_SRST			= 0x08	# soft reset
  # PACKET Command opcodes:
  ATAPI_OPCODE_READ_CAPACITY		= 0x25
  ATAPI_OPCODE_READ			= 0xa8
  ATAPI_OPCODE_EJECT			= 0x1b
ATA_PORT_STATUS		= 7	# read
  ATA_STATUS_BSY		= 0b10000000	# BSY busy
  ATA_STATUS_DRDY		= 0b01000000	# DRDY device ready
  ATA_STATUS_DF			= 0b00100000	# DF device fault
  ATA_STATUS_DSC		= 0b00010000	# DSC seek complete
  ATA_STATUS_DRQ		= 0b00001000	# DRQ data transfer requested
  ATA_STATUS_CORR		= 0b00000100	# CORR data corrected
  ATA_STATUS_IDX		= 0b00000010	# IDX index mark
  ATA_STATUS_ERR		= 0b00000001	# ERR error
ATA_PORT_DCR		= 0x206	# (206-8 for TERT/QUAT) device control register
  ATA_DCR_0			= 0<<0
  ATA_DCR_nIEN			= 1<<1	# no INT ENable
  ATA_DCR_SRST			= 1<<2	# software reset (all ata drives on bus)
  ATA_DCR_3			= 1<<3
  ATA_DCR_HOB			= 7	# cmd: read High Order Byte of LBA48

##############################################################################

.macro ATA_OUTB reg, val=al
	.if al != \val
	mov	al, \val
	.endif

	.ifc DCR,\reg
	ror	edx, 16
	out	dx, al
	ror	edx, 16
	.else
	add	dx, ATA_PORT_\reg
	out	dx, al
	sub	dx, ATA_PORT_\reg
	.endif
.endm

.macro ATA_INB reg
	.ifc DCR,\reg
	ror	edx, 16
	in	al, dx
	ror	edx, 16
	.else
	add	dx, ATA_PORT_\reg
	in	al, dx
	sub	dx, ATA_PORT_\reg
	.endif
.endm

.macro ATA_INW reg
	add	dx, ATA_PORT_\reg
	in	ax, dx
	sub	dx, ATA_PORT_\reg
.endm

.macro ATA_SELECT_DELAY
	ror	edx, 16
	in	al, dx
	in	al, dx
	in	al, dx
	in	al, dx
	ror	edx, 16
.endm

#########################################################
# ATA IDENTIFY drive information structure
#
.struct 0			#ATAPI: M = mandatory, u=unused, O=optional
				#                         /---- ATAPI
ATA_ID_CONFIG:			.word 0 	#0     0  M 2 Fixed
	# 15:14: protocol type: 0? = ATA, 10 = atapi, 11 = reserved
	# 13: reserved
	# 12:8: device type
	# 7: removable
	# 6:5 CMD DRQ type:
	#    00=microprocessor DRQ (DRQ within 3 ms of 0xA0 packet cmd)
	#    01=Interrupt DRQ: within 10 ms)
	#    10=accellerated DRQ: assert DRQ within 50us
	#    11=reserved
	# 4:2 reserved
	# 1:0 command packet size: 00=12 bytes, 01=16 bytes, 1X=reserved
	#    
ATA_ID_NUM_CYLINDERS:		.word 0		#1     2  u 2
ATA_ID_RESERVED1:		.word 0		#2     4  u 2
ATA_ID_NUM_HEADS:		.word 0		#3     6  u 2
ATA_ID_BYTES_PER_TRACKu:	.word 0 	#4     8  u 2 unformtd bytes/trk
ATA_ID_BYTES_PER_SECTORu:	.word 0 	#5     10 u 2 unformtd bytes/sec
.struct 12
ATA_ID_SECTORS_PER_TRACK:	.word 0		#6     12 u 2
ATA_ID_VENDOR_SPEC1:		.word 0,0,0 	#7-9   14 u 6
.struct 20
ATA_ID_SERIAL_NO:		.space 20 	#10-19 20 O 10 Fixed
ATA_ID_BUFFER_TYPE:		.word 0 	#20    40 u 2
ATA_ID_BUFFER_SIZE:		.word 0 	#21    42 u 2
ATA_ID_NUM_ECC_BYTES:		.word 0 	#22    44 u 2
ATA_ID_FIRMWARE_REV:		.space 8 	#23-26 46 M 8 #Fixed ASCII (18c)
.struct 54
ATA_ID_MODEL_NAME:		.space 40 	#27-46 54 M 40 # ASCII
ATA_ID_MULTIPLE_SEC_PER_INT:	.word 0 	#47    94 u 2
ATA_ID_DWIO:			.word 0 	#48    96 u 2 # reserved
ATA_ID_LBADMA:/*CAPABILITIES*/	.word 0 	#49    98 M 2 
	# bit 15: reserved for interleaved DMA
	# bit 14: reserved for proxy interrupt
	# bit 13: overlap operation supported
	# bit 12: reserved
	# bit 11: IORDY supported
	# bit 10: IORDY can be disabled
	# bit  9: LBA supported
	# bit  8: DMA supported
ATA_ID_RESERVED2:		.word 0 	#50   100 u 2 # reserved
ATA_ID_PIO_TI_MODE:		.word 0 	#51   102 M 2 # PIO cycle timing
ATA_ID_DMA_TI_MODE:		.word 0 	#52   104 M 2 # DMA cycle timing
.struct 106
ATA_ID_RESERVED3:/*FIELDVALID*/	.word 0 	#53   106 M 2
	# bits 15:2 reserved (fixed)
	# bit 1: fields in words 64-70 valid (fixed)
	# bit 0: fields in words 54-58 valid (variable)
ATA_ID_AP_NUM_CYLINDERS:	.word 0 	#54    108 u 2 cur Cylinders
ATA_ID_AP_NUM_HEADS:		.word 0 	#55    110 u 2 cur Heads
ATA_ID_AP_SECTORS_PER_TRACK:	.word 0 	#56    112 u 2 cur Sectors
ATA_ID_CAPACITY:		.word 0,0 	#57-58 114 u 4 cur capacity
ATA_ID_SECTORS_PER_INT:		.word 0 	#59    118 u 2 reserved 
.struct 120
ATA_ID_LBA28_SECTORS:/*MAX_LBA*/.long 0 	#60-61 120 u 4 usr addrsble sect
ATA_ID_SIN_DMA_MODES:		.word 0 	#62    124 M 2
	# high byte: singleword DMA transfer mode active (variable)
	# low byte:  singleword DMA transfer modes supported (fixed)
ATA_ID_MUL_DMA_MODES:		.word 0 	#63    126 M 2
	# high byte: multiword DMA transfer mode active (var)
	# low byte: multiword DMA transfer modes supported (fixed)
ATA_ID_ADV_PIO_MODE:		.word 0		# 64   128 M
	# high byte: reserved
	# low byte: Advanced PIO transfer mode supported (fixed)
ATA_ID_MIN_MWORD_DMA_TCT:	.word 0		# 65   130 M
	# minimum multiword DMA transfer cycle time per word (ns)
ATA_ID_RECOMMENDED_MWORD_DMA_TCT:.word 0	# 66   132 o Fixed
	# manufacturers recommended multiword dma transfer cycle time (ns)
ATA_ID_MIN_PIO_TCT_WO_FLOWCTL:	.word 0		# 67	   o Fixed
ATA_ID_MIN_PIO_TCT_W_IORDY_FLOWCTL:.word 0	# 68	   o Fixed
ATA_ID_RESERVED5:		.word 0,0	# 69-70	   u
ATA_ID_OVERLAP_RELEASE_TIME:	.word 0		# 71 O fixed, (microsec)
ATA_ID_SERVICE_RELEASE_TIME:	.word 0		# 72 O fixed, (microsec)
ATA_ID_MAJOR_REVISION:		.word 0		# 73 O fixed (-1 = unsupp)
ATA_ID_MINOR_VERSION:		.word 0		# 74 O fixed (-1 = unsupp)
ATA_ID_RESERVED6:		.space 127-75	# reserved unused
.struct 164
ATA_ID_COMMANDSETS:		.word 0		# 164
ATA_ID_FLAGS:			.word 0		# 166
	# flag 1 << 10: LBA48
.struct 176
ATA_ID_UDMA:			.word 0
.struct 186
ATA_ID_FLAGS2:			.word 0 
	# 1<<12: 1 = 80-pin cable (only works for master (0) drive)
.struct 200
ATA_ID_MAX_LBA_EXT:		.word 0		# 200
.struct 256
ATA_ID_VENDOR_SPEC2:		.space 64 	# 256	64
ATA_ID_RESERVED7:		.word 0 	# 320


#####################################################################
.data
ata_bus_presence: .byte 0	# bit x: IDEx
ata_buses:
	.word IO_ATA_PRIMARY
	.word IO_ATA_SECONDARY
	.word IO_ATA_TERTIARY
	.word IO_ATA_QUATERNARY
ata_bus_dcr_rel:	# the DCR ports, in relative offset to the bus port
	.word ATA_PORT_DCR
	.word ATA_PORT_DCR
	.word ATA_PORT_DCR - 8
	.word ATA_PORT_DCR - 8


.data SECTION_DATA_BSS
ata_drive_types: .space 8
	TYPE_ATA = 1
	TYPE_ATAPI = 2

.struct 0
ata_driveinfo_sectorsize:	.long 0
ata_driveinfo_max_lba:		.long 0, 0
ata_driveinfo_lba28_sectors:	.long 0
ata_driveinfo_capacity:		.long 0, 0	# calculated from lba28*512
ata_driveinfo_cmd_packet_size:	.byte 0
# drive geometry:
ata_driveinfo_c:		.word 0	# cylinders
ata_driveinfo_h:		.word 0 # heads
ata_driveinfo_s:		.word 0	# sectors per track
ata_driveinfo_cap_in_s:		.long 0	# capacity in sectors

# data from first part of ATA_ID, values seem off (values are for all drives):
# these are the unformatted c/h/s etc..:
ata_driveinfo_num_cylinders:	.word 0 # 0x6220
ata_driveinfo_num_:		.word 0 # 0x6f6f (RESERVED1)
ata_driveinfo_num_heads:	.word 0 # 0x6974
ata_driveinfo_bpt:		.word 0 # 0x6763
ata_driveinfo_bps:		.word 0 # 0x5600
ATA_DRIVEINFO_STRUCT_SIZE = .
.data SECTION_DATA_BSS
ata_drives_info: .space ATA_DRIVEINFO_STRUCT_SIZE * 8

.text32
.code32

# PREREQUISITE: ata_list_drives
# in: al = drive type (TYPE_ATA or TYPE_ATAPI)
# out: al = (bus<<1)|drive (0..7)
ata_find_first_drive:
	push	esi
	push	ecx
	mov	esi, offset ata_drive_types
	mov	ecx, 8
	mov	ah, al
0:	lodsb
	cmp	al, ah
	jne	1f
	mov	al, 8
	sub	al, cl
	jmp	0f
1:	loop	0b
	mov	al, -1
0:	pop	ecx
	pop	esi
	or	al, al
	ret

# in: al = disk nr: (bus<<1)+device
# out: CF; error message printed.
ata_is_disk_known:
	cmp	al, ATA_MAX_DRIVES
	jae	ata_err_unknown_disk$
	push	eax
	movzx	eax, al
	cmp	byte ptr [ata_drive_types + eax], 0
	pop	eax
	jz	ata_err_unknown_disk$
	clc
	ret

ata_err_unknown_disk$:
	printc 4, "ata: unknown device: bus "
	push	edx
	movzx	edx, al
	shr	dl, 1
	call	printdec32
	mov	dl, al
	and	dl, 1
	printc 4, " device "
	call	printhex1
	pop	edx
	stc
	ret

# in: al = disk
# out: eax = drive info struct ptr
# out: CF
ata_get_drive_info:
	call	ata_is_disk_known
	jc	9f
	mov	ah, ATA_DRIVEINFO_STRUCT_SIZE
	mul	ah
	movzx	eax, ax
	lea	eax, [ata_drives_info + eax]
	clc
9:	ret

# in: al = ata drive (bus<<1 + drive)
# out: edx:eax = drive capacity in bytes
ata_get_capacity:
	call	ata_get_drive_info
	jc	ata_err_unknown_disk$
	mov	edx, [eax + ata_driveinfo_capacity + 4]
	mov	eax, [eax + ata_driveinfo_capacity + 0]
	ret

# in: al = drive
# out: eax = max cylinders
# out: cx = maxsectors << 16 | max heads
ata_get_geometry:
.if 1
	call	ata_get_drive_info
	jc	0f

	mov	cx, [eax + ata_driveinfo_s]
	shl	ecx, 16
	mov	cx, [eax + ata_driveinfo_h]
	mov	eax, [eax + ata_driveinfo_c]

.else
	mov	ecx, 16 | ( 64 << 16 )

	call	ata_get_capacity	# out: edx:eax
	jc	0f

	# check if capacity >= 512 mb:
	LBA_H16_LIM = 1024 * 16 * 63 * 512	# fc000<<9: 0x1f800000
	cmp	eax, LBA_H16_LIM
	jb	1f
	mov	cx, 255
1:	clc
.endif
0:
	ret



ata_list_drives:

	#cli

	# Detect 'floating bus': unwired, status register will read 0xFF

	# print	"Detecting ATA buses:"

	xor	ecx, ecx
1:	mov	dx, [ata_buses + ecx * 2]
	add	dx, ATA_PORT_STATUS
	in	al, dx
	mov	dl, al
	inc	dl	# 0xFF: 'floating bus'
	jz	0f
	mov	al, 1
	shl	al, cl
	or	byte ptr [ata_bus_presence], al
	PRINT " IDE"
	mov	dl, cl
	call	printhex1
0:
	inc	cx
	cmp	cx, 4
	jb	1b

	mov	dl, [ata_bus_presence]

	or	dl, dl
	jnz	0f
	PRINTc	4, "None."
0:	call	newline


	# For all detected buses, check master and slave:

	xor	cl, cl
0:	mov	al, 1
	shl	al, cl
	test	byte ptr [ata_bus_presence], al
	jz	1f

	mov	ah, cl
	xor	al, al

3:	push	cx
	push	ax
	call	ata_list_drive
	.if ATA_DEBUG > 3
		call	more
	.endif
	pop	ax
	pop	cx
	inc	al
	cmp	al, 2
	jb	3b

1:	inc	cl
	cmp	cl, 4
	jb	0b

2:	#sti


	.if ATA_DEBUG 
		# list array of ata_drive_types
		mov	esi, offset ata_drive_types
		mov	ecx, 8
		mov	dh, -1
	0:	lodsb
		mov	dl, al
		call	printhex2

		cmp	dl, TYPE_ATAPI
		jne	1f
		mov	dh, 8
		sub	dh, cl
	1:
		mov	al, ' '
		call	printchar
		loop	0b
		call	newline

		mov	dl, dh
		call	printhex2
	.endif


###################################################
.if 1
	mov	cx, cs
	mov	ebx, offset ata_isr1
	add	ebx, [realsegflat]
	mov	ax, IRQ_BASE + IRQ_PRIM_ATA
	call	hook_isr

	mov	cx, cs
	mov	ebx, offset ata_isr2
	add	ebx, [realsegflat]
	mov	ax, IRQ_BASE + IRQ_SEC_ATA
	call	hook_isr


	PIC_ENABLE_IRQ IRQ_PRIM_ATA
	PIC_ENABLE_IRQ IRQ_SEC_ATA

	# enable IRQ on ATA buses
	mov	cx, 0x0100
0:	test	[ata_bus_presence], ch
	jz	1f

	mov	al, cl
	call	ata_get_ports_$
	ATA_OUTB DCR, 0 # reset nIEN  // out dx, ax crashes vmware

1:	shl	ch, 1
	add	cl, 2
	cmp	cl, ATA_MAX_DRIVES
	jb	0b
.endif
###################################################
	ret

.data SECTION_DATA_BSS
ata_irq: .byte 0
.text32
ata_isr1:
	push_	eax edx
	xor	ah, ah	# ATA0
	jmp	1f
ata_isr2:
	push_	eax edx
	mov	ah, 1	# ATA1
1:	push	ds
	mov	edx, SEL_compatDS
	mov	ds, edx
	.if ATA_DEBUG > 2
		printc 0xcf, "ATA_ISR"
		mov	dl, al
		call	printhex1

		.if 0
			call	ata_get_ports2$	# in: ah; out edx

			add	dx, ATA_PORT_STATUS
			in	al, dx
			sub	dx, ATA_PORT_STATUS
			call	ata_print_status$

			ATA_INB SECTOR_COUNT # DRQ reason
			call	ata_print_drq_reason$
		.endif
	.endif

# INTRQ (device interrupt), ATA-2 spec, 5.2.10:
# cleared by:
# - assertion of RESET
# - setting SRST of device control register
# - writing the command register
# - reading the status register

# INTRQ asserted:
# - PIO mode: begining of each data block
# - DMA mode: on completion.
#
	inc	byte ptr [ata_irq]
	mov	al, 0x20
	out	IO_PIC2, al
	out	IO_PIC1, al
	pop	ds
	pop_	edx eax
	iret

# in: al = (ata bus << 1) | drive (0 or 1)
# out: edx = [DCR, Base]
# out: CF
ata_get_ports$:
	call	ata_is_disk_known
	jc	9f
ata_get_ports_$:
	# check whether ata bus is known
	cmp	al, 8
	cmc
	jb	9f	# jb = jc
	# skip drive known check as this code may be called for drive detection.

	push	eax
	and	al, 0xfe	# mask out bit 0
	movzx	edx, al
	mov	ax, [ata_buses + edx]
	mov	dx, [ata_bus_dcr_rel + edx]
	add	dx, ax
	shl	edx, 16		# out: CF=0
	mov	dx, ax
	pop	eax
9:	ret

# in: ah = ata bus
# out: edx = [DCR, Base]
ata_get_ports2$:
	push	eax
	movzx	edx, ah
	mov	ax, [ata_buses + edx * 2]
	mov	dx, [ata_bus_dcr_rel + edx * 2]
	add	dx, ax
	shl	edx, 16
	mov	dx, ax
	pop	eax
	ret


# in: ah = ATA bus index (0..3)
# in: al = drive (0 or 1)
ata_list_drive:
	COLOR 7
	call	ata_get_ports2$	# out: edx = [DCR, Base]

	mov	bh, al
	add	al, ah
	add	al, ah
	mov	bl, al

	push	eax
	mov	ah, ATA_DRIVEINFO_STRUCT_SIZE
	mul	ah
	movzx	edi, ax
	add	edi, offset ata_drives_info
	pop	eax

	# Proposed algorithm from osdev:
	# 1) select drive
	# 2) write 0 to sector_count, and the 3 LBA registers
	# 3) send IDENTIFY command
	# 4) read status port (same port)
	# 5) if 0, drive doesnt exist, abort.
	# 6) poll status port until BSY is clear
	# 7) check LBAmid/hi ports: if nonzero: not ATA, abort.
	# 8) continue polling until DRQ or ERR
	# 9) read 256 words from data port.

	# implemented:
	# 1) wait for RDY
	# 2) select drive
	# 3) wait BSY clear
	# 4) write nIEN 
	# 5) set PIO
	# 6) clear sector_count and the 3 LBA registers
	# 7) send IDENTIFY command (0xEC)
	# 8) read status port. if 0, abort
	# 9) wait status RDY clear
	# 10) wait DRQ
	# 11) if DRQ times out, send ATAPI IDENTIFY (0xA1)
	# 12) wait BSY clear RDY set
	# 13) wait DRQ

	push	dx
	PRINTc	15, "* ATA"
	mov	dl, ah
	call	printhex1
	PRINTc	15, " Drive "
	mov	dl, bh
	call	printhex1
	PRINTc	15, ": "
	pop	dx

	push	ax
	call	ata_select_drive$
	pop	ax
	jc	ata_timeout$
	jz	nodrive$

	mov	ax, ATA_STATUS_BSY << 8
	call	ata_wait_status$
	jc	ata_timeout$

		push	eax
		push	edx
		push	ecx
	.if 1
		mov	eax, offset class_dev_ata
		call	class_newinstance
		mov	esi, eax
	.else
		mov	al, DEV_TYPE_ATA
		mov	cl, bl
		call	dev_getinstance
		jnc	1f
		call	dev_newinstance
	1:	lea	esi, [eax + edx]
	.endif
		mov	[esi + dev_ata_device], bl
		push	ebx
		mov	ebx, esi
		call	[esi + dev_api_constructor]
		pop	ebx
		pop	ecx
		pop	edx
		pop	eax

	push	edx
	ror	edx, 16
	mov	al, 0b0001010 # 'nIEN'(1000b) - skip INTRQ_WAIT
	out	dx, al	
	ror	edx, 16


	add	dx, ATA_PORT_FEATURE 
	mov	al, 0	# 0 = PIO, 1 = DMA
	out	dx, al

	# Set to 0: Sector count, LBA lo, LBA mid, LBA hi
	xor	eax, eax
	add	dx, ATA_PORT_SECTOR_COUNT - ATA_PORT_FEATURE
	out	dx, eax		# out DWORD = 4x out byte to 4 consec. ports
	pop	edx

	# Send ID command
	push	dx
	add	dx, ATA_PORT_COMMAND
	mov	al, ATA_COMMAND_IDENTIFY
	out	dx, al	# write command
	in	al, dx	# read status
	pop	dx
	.if ATA_DEBUG > 1
		call	ata_print_status$
	.endif
	
	or	al, al
	jz	nodrive$	# drive doesnt exist	
	# this should work but ATAPI is returning RDY.
	#test	al, ATA_STATUS_ERR	# ATAPI / SATA
	#jnz	atapi$

	# Check registers:
	push	dx
	add	dx, ATA_PORT_ADDRESS2
	in	ax, dx	# read port ADDR2 and ADDR3
	mov	dx, ax
	.if ATA_DEBUG > 1
		call	printhex4
		PRINTCHAR ' '
	.endif
	pop	dx


	# ax=0000 : PATA
	# ax=c33c : SATA
	# ax=EB14 : PATAPI
	# ax=9669 : SATAPI

	or	ax, ax
	jz	ata$
	cmp	ax, 0xeb14
	jz	atapi$
	cmp	ax, 0xc33c
	jz	sata$

	# try atapi anyway
	jmp	atapi$


sata$:	PRINT "SATA - not implemented"
	jmp	done$

ata$:	mov	bh, TYPE_ATA
	call	ata_wait_ready$
	jc	ata_timeout$
	call	ata_wait_DRQ1$
	LOAD_TXT "ATA   "
	jnc	read$	# has data!

	# DRQ fail: fallthrough to try atapi

atapi$:	mov	bh, TYPE_ATAPI
	push	ax
	push	dx
	add	dx, ATA_PORT_COMMAND
	mov	al, ATAPI_COMMAND_IDENTIFY
	out	dx, al
	pop	dx
	pop	ax

	# wait IRQ / poll BSY/DRQ
	call	ata_wait_ready$
	jc	ata_timeout$
	call	ata_wait_DRQ1$
	jc	ata_timeout$

	LOAD_TXT "ATAPI "

######## 512 bytes of data ready!
read$:	call	print

	.data
		parameters_buffer$: .space 512
	.text32
	push	dx
	add	dx, ATA_PORT_DATA
	push	es
	push	ds
	pop	es
	mov	ecx, 0x100
	push	edi
	mov	edi, offset parameters_buffer$
	rep	insw
	pop	edi
	pop	es
	pop	dx

	# store drive type 
	mov	al, bh
	movzx	ebx, bl
	mov	[ata_drive_types + ebx], al

	.if ATA_DEBUG > 2
		PRINTLNc 14, "Raw Data: "
		push	esi
		mov	esi, offset parameters_buffer$
		mov	ecx, 256
	0:	lodsb
		PRINTCHAR al
		loop	0b
		pop	esi
		call	newline
	.endif

	.macro ATA_ID_STRING_PRINT
		push	esi
		push	ecx
	0:	lodsw
		xchg	al, ah
		mov	[esi-2], ax
		loop	0b
		pop	ecx
		pop	esi

		PRINT_START
	0:	lodsb
		stosw
		cmp	al, ' '	# if current char is not space, update pos
		je	1f
		SET_SCREENPOS edi
	1:	loop	0b
		PRINT_END ignorepos=1	# effectively trim space
	.endm

	PRINTc	15, "Model: "
	push	esi
	mov	esi, offset parameters_buffer$
	add	esi, ATA_ID_MODEL_NAME
	mov	ecx, 40 / 2
	ATA_ID_STRING_PRINT
	pop	esi

	push	esi
	PRINTc	15, " Serial: "
	mov	esi, offset parameters_buffer$
	add	esi, ATA_ID_SERIAL_NO
	mov	ecx, 20 / 2
	ATA_ID_STRING_PRINT

	.if ATA_DEBUG
		PRINTc	15, " Firmware rev: "
		mov	esi, offset parameters_buffer$
		add	esi, ATA_ID_FIRMWARE_REV
		mov	ecx, 8 / 2
		ATA_ID_STRING_PRINT
		call	newline
	.endif
	pop	esi


	###
	COLOR 8

	##################################################
	mov	dx, [parameters_buffer$ + ATA_ID_CONFIG]
	.if ATA_DEBUG
		PRINTc	7, "Word 0: "
		call	printhex
	.endif

	# 15:14: protocol type: 0? = ATA, 10 = atapi, 11 = reserved
	test	dh, 1 << 7
	jnz	0f
	.if ATA_DEBUG
		PRINT	" ATA "
	.endif
	mov	[edi + ata_driveinfo_sectorsize], dword ptr 512
	jmp	2f
0:	test	dh, 1 << 6
	jnz	0f
	.if ATA_DEBUG
		PRINT	" ATAPI "
	.endif
	jmp	2f
0:	.if ATA_DEBUG
		PRINT	" Reserved "
	.endif
2:	# TODO: check if these values match the previously detected ones.


	# 12:8: device type
	.if ATA_DEBUG
		push	dx
		shr	dx, 8
		and	dl, 0b11111
		PRINT	"DevType: "
		call	printhex1
		pop	dx
	.endif

	# 7: removable
	test	dl, 1<<7
	jnz	0f
	PRINT	" Removable "
0:	

	# 6:5 CMD DRQ type:
	#    00=microprocessor DRQ (DRQ within 3 ms of 0xA0 packet cmd)
	#    01=Interrupt DRQ: within 10 ms)
	#    10=accellerated DRQ: assert DRQ within 50us
	#    11=reserved
	.if ATA_DEBUG
		mov	al, dl
		shr	al, 5
		and	al, 3
		jnz	0f
		PRINT " mDRQ "
		jmp	1f
	0:	cmp	al, 1
		jnz	0f
		PRINT " intDRQ "
		jmp	1f
	0:	cmp	al, 2
		jnz	1f
		PRINT " aDRQ "
	1:
	.endif

	# 1:0 command packet size: 00=12 bytes, 01=16 bytes, 1X=reserved
	and	edx, 3
	shl	dl, 2
	add	dl, 12
	mov	[edi + ata_driveinfo_cmd_packet_size], dl
	.if ATA_DEBUG
		PRINT "CMDPacketSize: "
		call	printdec32
	.endif
	##################################################
	

	.if ATA_DEBUG
		mov	dx, [parameters_buffer$ + ATA_ID_FLAGS]
		test	dx, 1<<10
		jz	0f
		PRINTc	7, " LBA48 "
	0:	

		mov	dx, [parameters_buffer$ + ATA_ID_UDMA]
		PRINTc	7, " UDMA: "
		call	printhex4

		# if master drive:
		mov	dx, [parameters_buffer$ + ATA_ID_FLAGS2]
		test	dx, 1<<12
		jz	0f
		PRINTc	7, " 80-pin cable "
	0:

		PRINTc	7, " LBA28 sectors: "
		mov	edx, [parameters_buffer$ + ATA_ID_LBA28_SECTORS]
		call	printhex8
	.endif


	push	eax
	mov	edx, [parameters_buffer$ + ATA_ID_MAX_LBA_EXT + 4]
	mov	[edi + ata_driveinfo_max_lba + 4], edx

	.if ATA_DEBUG
		PRINTc	7, " LBA48 sectors: "
		call	printhex8
	.endif

	mov	eax, [parameters_buffer$ + ATA_ID_MAX_LBA_EXT + 0]
	mov	[edi + ata_driveinfo_max_lba + 0], eax

	# mul with sectorsize: hardcoded 512 (as LBA is defined that way)
	shld	edx, eax, 9
	shl	eax, 9

	mov	[edi + ata_driveinfo_capacity + 4], edx
	mov	[edi + ata_driveinfo_capacity + 0], eax

	.if ATA_DEBUG
		call	printhex8
	.endif
	pop	eax


	mov	dx, [parameters_buffer$ + ATA_ID_AP_NUM_CYLINDERS]
	mov	[edi + ata_driveinfo_c], dx
	.if ATA_DEBUG
		DEBUG "num cyl"
		call	printhex4
	.endif

	mov	dx, [parameters_buffer$ + ATA_ID_AP_NUM_HEADS]
	mov	[edi + ata_driveinfo_h], dx
	.if ATA_DEBUG
		DEBUG "num heads"
		call	printhex4
	.endif

	mov	dx, [parameters_buffer$ + ATA_ID_AP_SECTORS_PER_TRACK]
	mov	[edi + ata_driveinfo_s], dx
	.if ATA_DEBUG
		DEBUG "sectpertrack"
		call	printhex4
	.endif

	mov	edx, [parameters_buffer$ + ATA_ID_CAPACITY]
	mov	[edi + ata_driveinfo_cap_in_s], edx
	.if ATA_DEBUG
		DEBUG "capacity"
		call	printhex8
	.endif

	mov	dx, [parameters_buffer$ + ATA_ID_NUM_CYLINDERS]
	mov	[edi + ata_driveinfo_num_cylinders], dx
	mov	dx, [parameters_buffer$ + ATA_ID_RESERVED1]
	mov	[edi + ata_driveinfo_num_], dx
	mov	dx, [parameters_buffer$ + ATA_ID_NUM_HEADS]
	mov	[edi + ata_driveinfo_num_heads], dx
	mov	dx, [parameters_buffer$ + ATA_ID_BYTES_PER_TRACKu]
	mov	[edi + ata_driveinfo_bpt], dx
	mov	dx, [parameters_buffer$ + ATA_ID_BYTES_PER_SECTORu]
	mov	[edi + ata_driveinfo_bps], dx

	mov	edx, [parameters_buffer$ + ATA_ID_LBA28_SECTORS]
	mov	[edi + ata_driveinfo_lba28_sectors], edx
	call	newline
	###

done$:	ret

ata_timeout$:
	LOAD_TXT "Timeout"
	jmp	1f
nodrive$:
	LOAD_TXT "None"
1:	PRINTLNc 12
	stc
	jmp	done$

ata_error$:
	PRINTc	4, "ERROR "
	push	dx
	add	dx, ATA_PORT_ERROR
	in	al, dx
	call	ata_print_error$
	pop	dx
	stc
	ret

######################################################################

# in: al = status register byte
ata_print_status$:
	push	dx
	mov	dl, al
	pushcolor 8
	call	printhex2
	popcolor
	pop	dx
ata_print_status1$:
	.data SECTION_DATA_STRINGS
	9:	.ascii "BSY\0 DRDY\0DF\0  DSC\0 DRQ\0 CORR\0IDX\0 ERR\0\0"
	.text32
	push	esi
	mov	esi, offset 9b
#	pushcolor 8
	call	ata_print_bits$
#	popcolor
	pop	esi
	ret

ata_print_error$:
	.data SECTION_DATA_STRINGS
	9: .ascii "BBK\0 UNC\0 MC\0  IDNF\0MCR\0 ABRT\0T0NF\0AMNF\0"
	.text32
	push	dx
	pushcolor 8
	mov	dl, al
	call	printhex2
	popcolor
	pop	dx

	push	esi
	mov	esi, offset 9b
	pushcolor 4
	call	ata_print_bits$
	popcolor
	pop	esi
	ret


ata_print_bits$:
	PRINT_START 
0:	shl	al, 1
	jnc	1f
	push	ax
	push	esi
	xor	al, al
	stosw
	call	__print
	pop	esi
	pop	ax
1:	add	esi, 5
	test	al, al
	jnz	0b
	PRINT_END
	ret

ata_print_drq_reason$:
	DEBUG "DRQ Reason:"
	DEBUG_BYTE al
	PRINTFLAG al, ATAPI_DRQ_CoD, "CMD", "DATA"
	PRINTFLAG al, ATAPI_DRQ_IO, "IN", "OUT"
	PRINTFLAG al, ATAPI_DRQ_RELEASE, "RELEASE"
	ret


ATA_WAIT_STATUS_COUNT = 0x00010000
# in: edx = [DCR, base]
# in: ah = status bits to be 0
# in: al = status bits to be 1
ata_wait_status$:
	push	bx
	push	ecx
	push	edx
	mov	bx, ax

	add	dx, ATA_PORT_STATUS

	.if ATA_DEBUG > 1
		PRINTc	5 "[Wait"
		pushcolor 0x0c
		or	bh, bh
		jz	0f
		mov	al, bh
		call	ata_print_status1$
		call	printspace
	0:	mov	al, bl
		color	0x0a
		call	ata_print_status1$
		popcolor
		PRINTc	5, "]"
	.endif

	# error bits are not set by default as ATAPI sometimes has ERR
	# set before it's ready. Also it interferes with list_drives.
	#or	bh, ATA_STATUS_CORR #| ATA_STATUS_ERR

	# TODO: when BSY, other bits are meaningless
	# Also, BSY only valid after 400ns
	mov	ecx, ATA_WAIT_STATUS_COUNT

	.if 0	# when enabling this, timeouts can occur in VMWare.
	in	al, dx
	in	al, dx
	in	al, dx
	in	al, dx
	.endif
0:	in	al, dx
	#test	al, ATA_STATUS_ERR
	#jnz	1f
	mov	ah, bh
	and	ah, al	# test for bits to be 0
	jnz	2f
	mov	ah, al
	and	ah, bl
	cmp	ah, bl	# test for bits to be 1
	jz	0f
2:	loop	0b

	.if ATA_DEBUG
		PRINTC 0xfb, "WAIT TIMEOUT"
	.endif

1:	
	.if ATA_DEBUG
		call	ata_print_status$
	.endif

	test	bh, ATA_STATUS_ERR	# werent asked to check err, so dont print
	jz	0f
	test	al, ATA_STATUS_ERR
	jz	0f
	call	ata_print_status$
	add	dx, ATA_PORT_ERROR - ATA_PORT_STATUS
	mov	ah, al
	in	al, dx
	printc 4, "ATA error: "
	call	ata_print_error$
	call	printspace
	xchg	al, ah
1:	stc
0:
	.if ATA_DEBUG > 1
		pushf
		cmp	ecx, ATA_WAIT_STATUS_COUNT
		jz	1f
		DEBUG "ata_wait_status"
		neg	ecx
		add	ecx, ATA_WAIT_STATUS_COUNT
		DEBUG_DWORD ecx
	1:	popf
	.endif

	pop	edx
	pop	ecx
	pop	bx
	ret

# Waits BSY=0 DRDY=1 ERR=0
# in: edx = HI = DCR, LO (dx) = base port
# out: CF ZF
ata_wait_ready$:
	mov	ax, (ATA_STATUS_BSY << 8) 
	call	ata_wait_status$
	mov	ax, ATA_STATUS_DRDY
	call	ata_wait_status$
	ret

# Waits DRQ = 1 (Device has data to send)
# in: edx = HI = DCR, LO (dx) = base port
ata_wait_DRQ1$:
	mov	ax, ATA_STATUS_DRQ
	call	ata_wait_status$
	ret

# Waits for DRQ=0 (device ready to read data from host)
ata_wait_DRQ0$:
	mov	ax, ATA_STATUS_DRQ << 8
	call	ata_wait_status$
	ret

# in: al = drive number
# in: edx = HI = DCR, LO (dx) = base port
# out: CF
ata_select_drive$:
	# ATA 2 protocol spec, section 8.3, PIO data in commands:
	# a) host reads status until BSY=0
	push	ax
	mov	ax, ATA_STATUS_BSY << 8
	call	ata_wait_status$
	pop	ax
	jc	1f

	# b) host writes device/head register with DEV bit value
	and	al, 1	# mask out bus (if al=bus|drive)
	shl	al, 4
	# optionally: for 28bit PIO, low 4 bits = highest 4 bits of LBA
	# for 28bit pio: E0 master, F0 slave
	# for 48bit pio: 40 master, 50 slave
	or	al, 0xA0 	# (B0 for slave)
	#or	al, 0xef	#  all bits 1, bit 4=0 drive 0, 1=drive 1
	ATA_OUTB DRIVE_SELECT

	# c) host reads status until BSY=0 and DRDY=1 (ignore ERR!)
	mov	ax, (ATA_STATUS_BSY << 8) | ATA_STATUS_DRDY
	call	ata_wait_status$
	jc	1f
	
	# other addendum: if al=0 then the drive is nonexistent
	# (and 0x7f seems to indicate the same).
	or	al, al
	jnz	1f
	stc

1:	.if ATA_DEBUG > 1
		pushf
		jnc	0f
		printc 4, "err"
		DEBUG_BYTE al
	0:
		DEBUG "ata_select_drive:"
		call	ata_dbg$
		popf
	.endif
	ret


# in: edx = [DCR, Base]
ata_software_reset:
	ror	edx, 16
	# NOTE: DCR is a readonly register, so the other bits (nIEN, HOB)
	# need to be remembered.
	mov	al, ATA_DCR_SRST
	out	dx, al	# reset both drives on bus and select master drive
	xor	al, al
	out	dx, al
	ror	edx, 16
	ret

ata_dbg$:
	PRINTc	9 "STATUS["
	push	dx
	push	ax
	add	dx, ATA_PORT_STATUS
	in	al, dx
	call	ata_print_status$
	test	al, ATA_STATUS_ERR
	jz	0f
	add	dx, ATA_PORT_ERROR - ATA_PORT_STATUS
	in	al, dx
	call	ata_print_error$
0:	pop	ax
	pop	dx
	PRINTc	9 "]"
	ret

################################################################ ATA ########

# in: al = (bus << 1) | drive
# in: ebx = abs LBA (32 bit), ecx >> 16 = high 16 bits, cx=sectorcount
# in: edi = pointer to buffer
# out: CF
ata_read:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	edi

	call	ata_rw_init$
	jc	2f

	# al = 0 for LBA28, 4 for LBA48
	add	al, ATA_COMMAND_PIO_READ
	add	dx, ATA_PORT_COMMAND
	out	dx, al
	sub	dx, ATA_PORT_COMMAND

	.if ATA_DEBUG > 1
		call	ata_print_status$
		PRINTLN " reading..."
	.endif

0:	mov	ax, ((ATA_STATUS_ERR | ATA_STATUS_BSY) << 8) | ATA_STATUS_DRQ
	call	ata_wait_status$
	jc	1f

	# read.. (ATA_PORT_DATA = 0 so..)
	push	ecx
	mov	ecx, 256
	rep	insw
	pop	ecx

	loop	0b

	.if ATA_DEBUG > 1
		call	ata_print_status$
		DEBUG "ata_read done"
		call newline
	.endif

	clc
2:	pop	edi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

1:	call	ata_print_status$
	PRINTLNc 4, "ata_read: DRQ timeout"
	stc
	jmp	2b


# in: al = (bus << 1) | drive
# in: ebx = abs LBA (32 bit), ecx >> 16 = high 16 bits, cx=sectorcount
# in: esi = pointer to buffer
# out: CF
ata_write:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	edi

	call	ata_rw_init$
	jc	2f

	# al = 0 for LBA28, 4 for LBA48
	add	al, ATA_COMMAND_PIO_WRITE
	add	dx, ATA_PORT_COMMAND
	out	dx, al
	sub	dx, ATA_PORT_COMMAND

	.if ATA_DEBUG > 1
		PRINTc 10, " Write sector "
		call	printhex8
	.endif

0:	mov	ax, ((ATA_STATUS_ERR | ATA_STATUS_BSY) << 8) | ATA_STATUS_DRQ
	call	ata_wait_status$
	jc	1f

	# write.. (ATA_PORT_DATA = 0 so..)
	push	ecx
	mov	ecx, 256
	rep	outsw
	pop	ecx
	# osdev advises to not use rep outsw but:
	#0:	outsw
	#	loop	0b

	loop	0b
	clc

2:	pop	edi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

1:	PRINTLNc 4, "ata_write: DRQ timeout"
	stc
	jmp	2b


# destroys: eax ecx
ata_rw_init$:
	call	ata_get_ports$
	jc	ata_err_unknown_disk$
	push	ax
	call	ata_select_drive$
	pop	ax
	jc	ata_err_unknown_disk$

	# preserve drive info as al gets used in port io
	mov	ah, al
	add	dx, ATA_PORT_SECTOR_COUNT

	# Check to see whether LBA28 can be used (faster)
	cmp	ebx, 0xfffffff	# 28 bits
	ja	r48$
	# cx = sector count, if more than 255 use lba48 (65k sectors)
	# ecx >> 16 is high 16 bits of LBA 48. Even if sectorcount < 256,
	# when high LBA bits are set, also use LBA48 mode.
	cmp	ecx, 0x100	
	ja	r48$
	# cl = 0 = 256 sectors
r28$:	#PRINT " LBA28 "
	#call	printhex8

	mov	al, cl
	out	dx, al	# sector count

	inc	dx
	mov	al, bl
	out	dx, al	# LBA lo [7:0]

	inc	dx
	mov	al, bh	# LBA mid [15:8]
	out	dx, al
	
	inc	dx
	ror	ebx, 16
	mov	al, bl	# LBA hi [23:16]
	out	dx, al

	# drive select and LBA hi [27:24]
	inc	dx
	mov	al, ah
	and	al, 1
	shl	al, 4	# ATA_DRIVE_SELECT_DEV
	or	al, bh	# the test above should have made sure bh <= 0xf
	or	al, ATA_DRIVE_SELECT_LBA
	out	dx, al

	xor	al, al	# ATA_COMMAND_PIO_READ = 0x20, READ_EXT=0x24
	sub	dx, ATA_PORT_DRIVE_SELECT

	ret

#	mov	al, ATA_COMMAND_PIO_READ
#	jmp	go_read$

r48$:	#PRINT " LBA48"
# EBX:  [LBAmidHI, LBAmidLO, LBAloHI, LBAloLO]
# ECX:	[LBAhiHI, LBAhiLO, SectHI, SectLO]
# output order:
# hi: SectHI, LBAloHI, LBAmidHI, LBAhiHI
# lo: SectLO, LBAloLO, LBAmidLO, LBAhiLO
#
	xchg	bl, bh	# LBAmidHI LBAmidLO LBAloLO LBAloHI
	xchg	cl, ch	# LBAhiHI, LBAhiLO, SectLO, sectHI
	rol	ebx, 8	# LBAmidLO LBAloLO LBAloHI LBAmidHI
	rol	ecx, 8	# LBAhiLO, SectLO, sectHI, LBAhiHI

	# output high bytes
	mov	al, ch	# sectHI
	out	dx, al

	inc	dx	# LBAloHI
	mov	al, bh
	out	dx, al

	inc	dx	# LBAmidHI
	mov	al, bl
	out	dx, al
	ror	ebx, 16	# prepare for lo bytes

	inc	dx	# LBAhiHI
	mov	al, cl
	out	dx, al
	ror	ecx, 16	# prepare for lo bytes

	# output low bytes
	sub	dl, 3
	mov	al, cl	# SectLO
	out	dx, al

	inc	dx
	mov	al, bl	# LBAloLO
	out	dx, al

	inc	dx
	mov	al, bh	# LBAmidLO
	out	dx, al

	inc	dx
	mov	al, ch	# LBAhiLO
	out	dx, al

	# make ecx sector count
	# ecx: sectHI lbahiHI lbaHilo sectLO
	mov	al, cl
	shr	ecx, 16
	mov	ch, al

	# drive select
	inc	dx
	mov	al, ah
	and	al, 1
	shl	al, 4	# ATA_DRIVE_SELECT_DEV
	or	al, ATA_DRIVE_SELECT_LBA
	out	dx, al

	mov	al, 4	# ATA_COMMAND_PIO_READ_EXT - ATA_COMMAND_PIO_READ
	sub	dx, ATA_PORT_DRIVE_SELECT
	ret

################################################################ ATAPI ######
ATAPI_SECTOR_SIZE = 2048

atapi_packet_clear$:
	push	edi
	push	eax
	mov	edi, offset atapi_packet
	xor	eax, eax
	stosd
	stosd
	stosd
	pop	eax
	pop	edi
	ret

# in: al = drive nr
# out: edx:eax = bytes
# out: CF
atapi_get_capacity:
	push	ebx
	push	ecx

	call	atapi_read_capacity	# out: ebx=lba, ecx=blocklen, edx:eax=capacity

9:	pop	ecx
	pop	ebx
	ret

# in: al = drive nr
# out: ecx = block length (typically 0x0800)
# out: ebx = last LBA (medium size)
# out: edx:eax = capacity in bytes
atapi_read_capacity:
	call	ata_get_ports$
	jc	9f
	push	esi
	push	edi

	call	atapi_packet_clear$
	mov	[atapi_packet_opcode], byte ptr ATAPI_OPCODE_READ_CAPACITY
	mov	esi, offset atapi_packet
	mov	edi, offset atapi_packet # overwrites...
	mov	ecx, 8
	call	atapi_packet_command
	jc	1f

	.if ATAPI_DEBUG > 1
		PRINT "Received "
		mov	edx, ecx
		call	printdec32
		PRINTLN " bytes: "
	.endif

	mov	ebx, [esi]	# LBA
	bswap	ebx

	mov	ecx, [esi + 4]	# block length
	bswap	ecx

	.if ATAPI_DEBUG
		print	" LBA: "
		mov	edx, ebx
		call	printhex8
		print 	" Block length: "
		mov	edx, ecx
		call	printhex8
	.endif

	mov	eax, ecx
	inc	ebx
	mul	ebx
	dec	ebx

	.if ATAPI_DEBUG
		PRINT " Capacity: "
		call	print_size
		call	newline
	.endif

1:	pop	edi
	pop	esi
9:	ret


atapi_print_packet$:
	push	dx
	push	esi
	mov	ecx, 12
	PRINT "ATAPI PACKET: "
0:	lodsb
	mov	dl, al
	call	printhex2
	mov	al, ' '
	call	printchar
	loop	0b
	call	newline
	pop	esi
	pop	dx

	ret



# in: al = drive
# in: ebx = LBA
# in: ecx = nr of sectors (2kb/sect typically)
# in: edi = buffer
# out: esi = offset to buffer
# out: ecx = length of data in buffer
atapi_read12$:
	push	edx
	push	ebx

	call	ata_get_ports$
	jc	9f

	call	atapi_packet_clear$

	.if ATAPI_DEBUG > 1
		DEBUG "atapi_read12 LBA"
		DEBUG_DWORD ebx
	.endif

	# convert to MSB:
	bswap	ebx

	mov	[atapi_packet_opcode], byte ptr ATAPI_OPCODE_READ
	mov	[atapi_packet_LBA], ebx
	mov	[atapi_packet_ext_transfer_length + 3], byte ptr 1
	mov	esi, offset atapi_packet

	mov	ecx, ATAPI_SECTOR_SIZE
	call	atapi_packet_command
9:	pop	ebx
	pop	edx
	ret

.data SECTION_DATA_BSS
atapi_packet: 
	atapi_packet_opcode: .byte 0
		# bits 7,6,5: group code
		# bits 4:0: command code
	atapi_packet_reserved: .byte 0
	atapi_packet_LBA: .long 0	# MSB, base 0
	atapi_packet_ext_transfer_length: .byte 0	# 4 bytes
	atapi_packet_transfer_length: .word 0 # MSB (translen/paramlen/alloclen)
	# 0 means no data transfer...
	# transfer length: number of blocks or number of bytes
	# parameter list length: number of bytes.
	# allocation length:  host buffer size
	atapi_packet_reserved2: .byte 0,0,0
	# normal commands use _length, not _ext_length
	# extended commands use ext_length (4 bytes) where the middle 2 bytes
	# overlap the _length
	# Since most fields are reserved, the following parameters apply:
	# - db opcode
	# - dd lba
	# - dd transfer length (or dw)
	.long 0	# config WORD 0 may indicate 16 byte packet structure
.text32


####### ATAPI Packet Command
# in: al = bus<<1|drive
# in: edx = [DCR, Base]
# in: esi = 6 word packet data
# in: edi = buffer
# in: ecx = max transfer size
# out: esi = offset to buffer, ecx = data in buffer
atapi_packet_command:
	cmp	ecx, ATAPI_SECTOR_SIZE
	jbe	0f

	PRINTLNc 4, "atapi_packet_command: Transfer length too large"
	stc
	ret
0:
	mov	byte ptr [ata_irq], 0

	.if ATAPI_DEBUG > 2
		PRINT "Select Drive "
		DEBUG_BYTE al
		DEBUG_DWORD edx
	.endif

	call	ata_select_drive$
	jc	ata_timeout$

	mov	ax, ( ATA_STATUS_BSY | ATA_STATUS_DRQ ) << 8
	call	ata_wait_status$
	jc	ata_timeout$

	ATA_OUTB FEATURE, 0	# 0=PIO 1=DMA
	ATA_OUTB ADDRESS2, cl	# byte count
	ATA_OUTB ADDRESS3, ch
	ATA_OUTB COMMAND, ATAPI_COMMAND_PACKET

	# dev sets BSY before status read
	# dev sets CoD, clears RELEASE, IO when ready to accept command packet
	# DRQ asserted

	mov	ax, (ATA_STATUS_BSY << 8) | ATA_STATUS_DRQ
	call	ata_wait_status$
	jc	ata_timeout$

	.if ATAPI_DEBUG > 2
		call	ata_dbg$
		call	newline
	.endif
	
	# check IO clear and CoD set
	ATA_INB SECTOR_COUNT
	cmp	al, ATAPI_DRQ_CMDOUT
	jnz	atapi_drq_reason_mismatch$

	.if ATAPI_DEBUG > 2
		PRINT "Write Packet "
		push	dx
		push	esi
		.rept 12
		lodsb
		mov	dl, al
		call	printhex2
		mov	al, ' '
		call	printchar
		.endr
		call	newline
		pop	esi
		pop	dx
	.endif

	# write packet data
	push	dx
	push	ecx
	add	dx, ATA_PORT_DATA
	mov	ecx, 6
	rep	outsw
	pop	ecx
	pop	dx

	.if ATAPI_DEBUG > 2
		call	ata_dbg$
	.endif

	# device clears DRQ (when 6th word written), sets BSY, reads features/bytecount,
	# prepares release of ATA bus or bus transfer.
	# IF not cfg specifies to gen int after accepting packet cmd data,
	# device may not release ata bus, and moves to data transfer, DRQ=1,CoD=0,IO=0
	# ELSE clears IO, CoD, DRQ, BSY. When ready, device sets SERVICE in ATAPI STATUS
	# register, DRQ, INTRQ. On INTRQ read status, send Service 0xa2 command.
	# When dev ready, CYL hi/lo contians data count, SERVICE cleared, IO set, CoD
	# clear, DRQ set, BSY clear.

	# TODO: check IO set and CoD clear

	call	ata_wait_irq
	jc	ata_timeout$
	#WAIT_DATAREADY 1f

	.if ATAPI_DEBUG > 2
		call ata_dbg$
	.endif

	ATA_INB SECTOR_COUNT	# (DRQ) interrupt reason
	.if ATAPI_DEBUG > 2
		DEBUG "DRQ Reason:"
		DEBUG_BYTE al
		PRINTFLAG al, ATAPI_DRQ_CoD, "CMD", "DATA"
		PRINTFLAG al, ATAPI_DRQ_IO, "IN", "OUT"
		PRINTFLAG al, ATAPI_DRQ_RELEASE, "RELEASE"
	.endif
	cmp	al, ATAPI_DRQ_DATAIN
	jnz	atapi_drq_reason_mismatch$

	xor	eax, eax	# clear high word for malloc
	ATA_INB ADDRESS3
	mov	ah, al
	ATA_INB ADDRESS2

	movzx	ecx, ax
	or	ecx, ecx
	jnz	1f
	printlnc 4, "atapi_packet_command: error: transfer size 0"
	stc
	ret
1:

	.if ATAPI_DEBUG > 2
		push	edx
		mov	edx, ecx
		PRINT "Reading "
		call	printdec32
		PRINT " bytes "
		pop	edx
	.endif
#DEBUG_DWORD edi,"READ", 0x2f
	push	ecx
	push	dx
	add	dx, ATA_PORT_DATA
	push	es
	push	ds
	pop	es
	push	edi
	inc	ecx
	shr	ecx, 1
	rep	insw
	pop	edi
	pop	es
	pop	dx
	pop	ecx
	push	dx
	add	dx, ATA_PORT_STATUS
	in	al, dx	# DRDY | DSC
	pop	dx
	test	al, ATA_STATUS_BSY | ATA_STATUS_DRQ

	# drq 0. If more data then device sets BSY: goto 'wait for data ready'
	# device sets CoD, IO, DRDY, clears BSY and DRQ.

	.if ATAPI_DEBUG > 1
		PRINTln "Data read."
	.endif

	mov	esi, edi
	clc
1:	ret

# jump target for when SECTOR_COUNT register (ATAPI DRQ Reason) shows 
# unexpected value (i.e. OUT vs IN, CMD vs DATA, or RELEASE when not expected).
atapi_drq_reason_mismatch$:
	printlnc 4, "atapi_drq_reason_mismatch"
	stc
	ret

#######
ATA_WAIT_IRQ_TIMEOUT = 0x100	# using hlt.
ata_wait_irq:
	push	ecx
	mov	ecx, 0x100 # ATA_WAIT_IRQ_TIMEOUT

	.if ATA_DEBUG > 2
		DEBUG "ata_wait_irq:"
		DEBUG_BYTE [ata_irq]
	.endif

1:	cmp	byte ptr [ata_irq], 0
	jnz	1f
	hlt
	loop	1b
	printc 4, "ata_wait_irq: timeout"
	stc
	pop	ecx
	ret
1:	.if ATA_DEBUG > 2
		DEBUG "ata_wait_irq: Got IRQ"
		neg	ecx
		add	ecx, ATA_WAIT_IRQ_TIMEOUT
		DEBUG_DWORD ecx
		DEBUG_BYTE [ata_irq]
	.endif
	mov	byte ptr [ata_irq], 0
	pop	ecx
	clc
	ret


##############################################################################
# commandline utilities

# out: eax = number of drives
ata_get_numdrives:
	push	esi
	push	ecx
	mov	esi, offset ata_drive_types
	mov	ecx, ATA_MAX_DRIVES
	xor	eax, eax
0:	lodsb		# possible values for drive_type: 0, 1 = ata, 2 = atapi
	# NOTE: optimized code: drive_type can only be 0, 1 or 2
	shr	al, 1	# 0 -> 0, ZF; 1 -> 0, ZF, CF; 2 -> 1, _ :  al + CF = 0/1
	adc	ah, al
	loop	0b
	shr	ax, 8
	pop	ecx
	pop	esi
	ret

# in: al = drive number
ata_print_capacity:
	push	edx
	push	eax
	call	ata_get_capacity	# in: al; out: 64 bit edx:eax
	jc	0f			# error already printed
	call	print_size
0:	pop	eax
	pop	edx
	ret


# prints the size as given in sectors (512 bytes)
# in: edx:eax = size in sectors of 512 bytes
ata_print_size:
	push	edx
	push	eax

	shld	edx, eax, 9
	shl	eax, 9

	call	print_size

	pop	eax
	pop	edx
	ret

################################################

cmd_disks_print$:
	lodsd
	lodsd
	or	eax, eax
	jz	0f
	CMD_ISARG "-v"
	jnz	9f

0:
	push	esi

	# print max number of drives:
	call	ata_get_numdrives
	mov	edx, eax
	call	printdec32
	print	" drive(s): "


	# iterate through drives
	mov	ecx, ATA_MAX_DRIVES
	mov	ebx, offset ata_drive_types
	xor	dl, dl
0:	mov	ah, [ebx]
	or	ah, ah
	jz	1f

	.data SECTION_DATA_STRINGS
	99:	.asciz ", ", "hd", " (", "ATA", "PI", "UNKNOWN", ")"
	.text32
	mov	esi, offset 99b
	or	dl, dl
	PRINT_NZ_

	PRINT_		# "hd"
	mov	al, dl
	add	al, 'a'
	call	printchar
	PRINT_		# " ("

	# 3 strings: "ATA",0,0  or  "ATA","PI",0   or  0,0,"UNKNOWN"
	cmp	ah, TYPE_ATA
	jnz	2f
	PRINT_
	PRINTSKIP_
	PRINTSKIP_
	jmp	3f
2:	cmp	ah, TYPE_ATAPI
	jnz	2f
	PRINT_
	PRINT_
	PRINTSKIP_
	jmp	3f
2:	PRINTSKIP_
	PRINTSKIP_
	PRINT_
3:	PRINT_
	inc	dl

1:	inc	ebx
	loop	0b
	call	newline


	pop	esi

######## Check verbose args

	mov	eax, [esi-4]
	or	eax, eax
	jz	1f
	CMD_ISARG "-v"
	jnz	1f

	call	ata_get_numdrives
	or	eax, eax
	jz	1f
	mov	ecx, eax
	xor	ah, ah
0:	mov	al, ah
	mov	ah, -1
	call	disk_print_label
	mov	ah, al
	print	": "

	push	eax
	call	ata_get_drive_info

	printc	15, "C/H/S: "

	movzx	edx, word ptr [eax + ata_driveinfo_c]
	call	printdec32
	printcharc 15, '/'

	movzx	edx, word ptr [eax + ata_driveinfo_h]
	call	printdec32
	printcharc 15, '/'

	movzx	edx, word ptr [eax + ata_driveinfo_s]
	call	printdec32

	call newline

	printc	15, " cap in s: "
	mov	edx, [eax + ata_driveinfo_cap_in_s]
	call	printhex8


	printc 15, " cap: "
	mov	edx, [eax + ata_driveinfo_capacity + 4]
	#call	printhex8
	mov	edx, [eax + ata_driveinfo_capacity + 0]
	#call	printhex8
	call	printhex8

	printc 15, " lba28sect: "
	mov	edx, [eax + ata_driveinfo_lba28_sectors]
	call	printhex8

	printc 15, " maxlba: "
	mov	edx, [eax + ata_driveinfo_max_lba]
	call	printhex8

	###############

	.if 0	# these values are off:
		call	newline
		printc	15, "     cyl: "
		movzx	edx, word ptr [edi + ata_driveinfo_num_cylinders]
		call	printhex4

		printc	15, " ?: "
		movzx	edx, word ptr [edi + ata_driveinfo_num_]
		call	printhex4

		printc	15, " heads: "
		movzx	edx, word ptr [edi + ata_driveinfo_num_heads]
		call	printhex4

		printc	15, " bytes/track: "
		movzx	edx, word ptr [edi + ata_driveinfo_bpt]
		call	printhex4

		printc	15, " bytes/sector: "
		movzx	edx, word ptr [edi + ata_driveinfo_bps]
		call	printhex4
	.endif

	pop	eax

	inc	ah
	call	newline
	.if 1
	dec	ecx
	jnz	0b
	.else
	loop	0b
	.endif

1:	ret

9:	printlnc 12, "usage: disks [-v]"
	ret
