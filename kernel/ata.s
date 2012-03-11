###############################################################################
# IDE / ATAPI

.intel_syntax noprefix


ATA_DEBUG = 0

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
ATA_PORT_ERROR		= 1	# read
  ATA_ERROR_BBK			= 0b10000000	# Bad Block
  ATA_ERROR_UNC			= 0b01000000	# Uncorrectable Data Error
  ATA_ERROR_MC			= 0b00100000	# Media Changed
  ATA_ERROR_IDNF		= 0b00010000	# ID mark not found
  ATA_ERROR_MCR			= 0b00001000	# Media Change Requested
  ATA_ERROR_ABRT		= 0b00000100	# command Aborted
  ATA_ERROR_TK0NF		= 0b00000010	# Track 0 Not Found
  ATA_ERROR_AMNF		= 0b00000001	# Address Mark Not Found
ATA_PORT_SECTOR_COUNT	= 2
ATA_PORT_ADDRESS1	= 3	# sector	/ LBA lo
ATA_PORT_ADDRESS2	= 4	# cylinder low	/ LBA mid
ATA_PORT_ADDRESS3	= 5	# cylinder hi	/ LBA high
ATA_PORT_DRIVE_SELECT	= 6
  ATA_DRIVE_MASTER	= 0xa0
  ATA_DRIVE_SLAVE	= 0xb0
  # bin: 101DHHHH
  # D: drive (0 = master 1 = slace)
  # HHHH: head selection bits
ATA_PORT_COMMAND	= 7	# write
  ATA_COMMAND_PIO_READ			= 0x20	# w/retry; +1=w/o retry
  ATA_COMMAND_PIO_READ_LONG		= 0x22	# w/retry; +1=w/o retry
  ATA_COMMAND_PIO_READ_EXT		= 0x24
  ATA_COMMAND_DMA_READ_EXT		= 0x25
  ATA_COMMAND_PIO_WRITE_		= 0x30	# w/retry; +1=w/o retry
  ATA_COMMAND_PIO_WRITE_LONG		= 0x32	# w/retry; +1=w/o retry
  ATA_COMMAND_DMA_WRITE_EXT		= 0x35
  ATA_COMMAND_DMA_READ			= 0xc8
  ATA_COMMAND_DMA_WRITE			= 0xca
  ATA_COMMAND_CACHE_FLUSH		= 0xe7
  ATA_COMMAND_CACHE_FLUSH_EXT		= 0xea
  ATA_COMMAND_IDENTIFY			= 0xec
  ATAPI_COMMAND_PACKET			= 0xa0
  ATAPI_COMMAND_IDENTIFY		= 0xa1

  ATAPI_COMMAND_READ			= 0xa8
  ATAPI_COMMAND_EJECT			= 0x1b
ATA_PORT_STATUS		= 7	# read
  ATA_STATUS_BUSY		= 0b10000000	# BSY busy
  ATA_STATUS_DRDY		= 0b01000000	# DRDY device ready
  ATA_STATUS_DF			= 0b00100000	# DF device fault
  ATA_STATUS_DSC		= 0b00010000	# DSC seek complete
  ATA_STATUS_DRQ		= 0b00001000	# DRQ data transfer requested
  ATA_STATUS_CORR		= 0b00000100	# CORR data corrected
  ATA_STATUS_IDX		= 0b00000010	# IDX index mark
  ATA_STATUS_ERR		= 0b00000001	# ERR error
ATA_PORT_DCR		= 0x206	# (206-8 for TERT/QUAT) device control register
  ATA_DCR_nIEN			= 1	# no INT ENable
  ATA_DCR_SRST			= 2	# software reset (all ata drives on bus)
  ATA_DCR_HOB			= 7	# cmd: read High Order Byte of LBA48


.struct 0
ATA_ID_CONFIG:			.word 0 	# 0	2
ATA_ID_NUM_CYLINDERS:		.word 0		# 2	2
ATA_ID_RESERVED1:		.word 0		# 4	2
ATA_ID_NUM_HEADS:		.word 0		# 6	2
ATA_ID_BYTES_PER_TRACKu:	.word 0 	# 8	2
ATA_ID_BYTES_PER_SECTORu:	.word 0 	# 10	2
.struct 12
ATA_ID_SECTORS_PER_TRACK:	.word 0		# 12	2
ATA_ID_VENDOR_SPEC1:		.word 0,0,0 	# 14	6
.struct 20
ATA_ID_SERIAL_NO:		.space 20 	# 20	10
ATA_ID_BUFFER_TYPE:		.word 0 	# 40	2
ATA_ID_BUFFER_SIZE:		.word 0 	# 42	2
ATA_ID_NUM_ECC_BYTES:		.word 0 	# 44	2
ATA_ID_FIRMWARE_REV:		.space 8 	# 46    8 # ASCII
.struct 54
ATA_ID_MODEL_NAME:		.space 40 	# 54    40 # ASCII
ATA_ID_MUL_SEC_PER_INT:		.word 0 	# 94	2
ATA_ID_DWIO:			.word 0 	# 96	2
ATA_ID_LBADMA:/*CAPABILITIES*/			.word 0 	# 98	2
ATA_ID_RESERVED2:		.word 0 	# 100	2
ATA_ID_PIO_TI_MODE:		.word 0 	# 102	2
ATA_ID_DMA_TI_MODE:		.word 0 	# 104	2
.struct 106
ATA_ID_RESERVED3:/*FIELDVALID*/	.word 0 	# 106	2
ATA_ID_AP_NUM_CYLINDERS:	.word 0 	# 108	2
ATA_ID_AP_NUM_HEADS:		.word 0 	# 110	2
ATA_ID_AP_SECTORS_PER_TRACK:	.word 0 	# 112	2
ATA_ID_CAPACITY:		.word 0 	# 114	2
ATA_ID_SECTORS_PER_INT:		.word 0 	# 118	2
.struct 120
ATA_ID_LBA_SECTORS:/*MAX_LBA*/	.word 0,0 	# 120	4
ATA_ID_SIN_DMA_MODES:		.word 0 	# 124	2
ATA_ID_MUL_DMA_MODES:		.word 0 	# 126	2
.struct 164
ATA_ID_COMMANDSETS:		.word 0		# 164
.struct 200
ATA_ID_MAX_LBA_EXT:		.word 0		# 200
.struct 256
ATA_ID_VENDOR_SPEC2:		.space 64 	# 256	64
ATA_ID_RESERVED5:		.word 0 	# 320

.data
ata_bus_presence: .byte 0	# bit x: IDEx
ata_buses:
	.word IO_ATA_PRIMARY
	.word IO_ATA_SECONDARY
	.word IO_ATA_TERTIARY
	.word IO_ATA_QUATERNARY
ata_bus_dcr_rel:
	.word ATA_PORT_DCR
	.word ATA_PORT_DCR
	.word ATA_PORT_DCR - 8
	.word ATA_PORT_DCR - 8
.text
.code32

# in: al = status register byte
ata_print_status:
	.data
	ata_status$: .asciz "BSY\0RDY\0DF \0DSC\0DRQ\0COR\0IDX\0ERR\0"
	.text
	PRINT_START 8
	push	esi
	mov	esi, offset ata_status$
0:	shl	al, 1
	jnc	1f
	call	__print
	add	edi, 2
1:	add	esi, 4
	test	al, al
	jnz	0b
	pop	esi
	PRINT_END
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
	pop	ax
	pop	cx
	inc	al
	cmp	al, 2
	jb	3b

1:	inc	cl
	cmp	cl, 4
	jb	0b

2:	#sti
	ret


# in: ah = ATA bus index (0..3)
# in: al = drive (0 or 1)
ata_list_drive:
	COLOR 7
	push	ax
	movzx	edx, ah
	mov	ax, [ata_buses + edx * 2]
	mov	dx, [ata_bus_dcr_rel + edx * 2]
	add	dx, ax
	shl	edx, 16
	mov	dx, ax
	pop	ax
	# EDX: DSR, Base


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
	push	ax
	call	ata_select_drive$
	pop	ax
	jc	timeout$
	jz	nodrive$

	push	dx
	PRINTc	15, "* ATA"
	mov	dl, ah
	call	printhex1
	PRINTc	15, " Drive "
	mov	dl, al
	call	printhex1
	PRINTc	15, ": "
	pop	dx

	push	ax
	call	ata_wait_busy$
	pop	ax
	jc	timeout$



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
	.if ATA_DEBUG
		call	ata_print_status
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
	.if ATA_DEBUG
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

ata$:
	call	ata_wait_ready$
	jc	timeout$
	call	ata_wait_drq$
	LOAD_TXT "ATA   "
	jnc	read$	# has data!

	# DRQ fail: fallthrough to try atapi

atapi$:
	push	dx
	add	dx, ATA_PORT_COMMAND
	mov	al, ATAPI_COMMAND_IDENTIFY
	out	dx, al
	pop	dx

	# wait IRQ / poll BSY/DRQ
	call	ata_wait_ready$
	jc	timeout$
	call	ata_wait_drq$
	jc	timeout$

	LOAD_TXT "ATAPI "

######## 512 bytes of data ready!
read$:	call	print

	.data
		parameters_buffer$: .space 512
	.text
	push	dx
	add	dx, ATA_PORT_DATA
	push	es
	push	ds
	pop	es
	mov	ecx, 0x100
	mov	edi, offset parameters_buffer$
	rep	insw
	pop	es
	pop	dx

	.if ATA_DEBUG > 1
		PRINTLNc 14, "Raw Data: "
		mov	esi, offset parameters_buffer$
		mov	ecx, 256
	0:	lodsb
		PRINTCHAR al
		loop	0b
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
		mov	[screen_pos], edi
	1:	loop	0b
		PRINT_END ignorepos=1	# effectively trim space
	.endm

	PRINTc	15, "Model: "
	mov	esi, offset parameters_buffer$
	add	esi, ATA_ID_MODEL_NAME
	mov	ecx, 40 / 2
	ATA_ID_STRING_PRINT
0:
	PRINTc	15, " Serial: "
	mov	esi, offset parameters_buffer$
	add	esi, ATA_ID_SERIAL_NO
	mov	ecx, 20 / 2
	ATA_ID_STRING_PRINT

	PRINTc	15, " Firmware rev: "
	mov	esi, offset parameters_buffer$
	add	esi, ATA_ID_FIRMWARE_REV
	mov	ecx, 8 / 2
	ATA_ID_STRING_PRINT

	call	newline

	###
	COLOR 8

	PRINTc	7, "Word 0: "
	mov	dx, [parameters_buffer$ + 0]
	call	printhex

	mov	dx, [parameters_buffer$ + 2* 83]
	test	dx, 1<<10
	jz	0f
	PRINTc	7, " LBA48 "
0:	
	mov	dx, [parameters_buffer$ + 2* 88]
	PRINTc	7, " UDMA: "
	call	printhex4

	# if master drive:
	mov	dx, [parameters_buffer$ + 2* 93]
	test	dx, 1<<12
	jz	0f
	PRINTc	7, " 80-pin cable "
0:

	PRINTc	7, " LBA28 sectors: "
	mov	edx, [parameters_buffer$ + 2* 60]
	call	printhex8

	PRINTc	7, " LBA48 sectors: "
	mov	edx, [parameters_buffer$ + 2* 100 + 4]
	call	printhex8
	mov	edx, [parameters_buffer$ + 2* 100 + 0]
	call	printhex8

	call	newline
	###

done$:	ret

timeout$:
	LOAD_TXT "Timeout"
	jmp	1f
nodrive$:
	.if 0
	LOAD_TXT "None"
1:	PRINT_START 12
	call	__println
	PRINT_END
	.endif
	stc
	jmp	done$


# in: edx = HI = DCR, LO (dx) = base port
# out: CF
ata_wait_busy$:
	push	ax
	#call	ata_select_delay

	push	ecx
	push	dx
	add	dx, ATA_PORT_STATUS
	mov	ecx, 5 # 0x1000
0:	in	al, dx
	test	al, ATA_STATUS_BUSY
	jz	0f
	loop	0b

	.if 1
	PRINTc 4, "Busy"
	.endif

	stc
0:	pop	dx
	pop	ecx
	pop	ax
	ret

# in: edx = HI = DCR, LO (dx) = base port
# out: CF ZF
ata_wait_ready$:
	push	ax
	call	ata_wait_busy$
	jc	0f

	push	ecx
	push	dx
	add	dx, ATA_PORT_STATUS
	mov	ecx, 5
1:	in	al, dx
	test	al, ATA_STATUS_DRDY
	jnz	1f
	test	al, ATA_STATUS_ERR
	jz	3f
	PRINTc 4, "Error"
	jmp	2f
	3:
	loop	1b
2:	stc
1:	pop	dx
	pop	ecx
0:
.if ATA_DEBUG
	pushf
	PUSHCOLOR 0x0a
	jnz	0f
	COLOR 4
	PRINT "Not "
0:	PRINT "Ready"
	POPCOLOR
	popf
.endif
	pop	ax
	ret

# in: edx = HI = DCR, LO (dx) = base port
ata_wait_drq$:
	push	ecx
	push	dx
	add	dx, ATA_PORT_STATUS
	mov	ecx, 0x5
0:	in	al, dx
	test	al, ATA_STATUS_DRQ
	jnz	0f
	loop	0b

	.if ATA_DEBUG
		PRINTc 4, "DRQ Timeout"
	.endif

	stc
0:	pop dx
	pop ecx
	ret


# in: al = drive number
# in: edx = HI = DCR, LO (dx) = base port
# out: nothing.
ata_select_drive$:
	xor	ah, ah
	call	ata_wait_busy$
	jc	1f
	push	edx
	add	dx, ATA_PORT_DRIVE_SELECT
	shl	al, 4
	or	al, 0xA0 	# (B0 for slave)
	#or	al, 0xef	#  all bits 1, bit 4=0 drive 0, 1=drive 1
	out	dx, al
	
	add	dx, ATA_PORT_STATUS - ATA_PORT_DRIVE_SELECT
	in	al, dx
	.if ATA_DEBUG
		call	ata_print_status
	.endif
	or	al, al
	pop	edx
1:	ret


# simulate 400ns delay
# in: edx = HI = DCR, LO (dx) = base port
ata_select_delay:
	push	ax
	ror	edx, 16
	and	dx, 0xff0	# dx = DCR
	in	al, dx
	in	al, dx
	in	al, dx
	in	al, dx
	ror	edx, 16
	pop	ax
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

