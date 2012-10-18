##############################################################################
# Realtek 8139
.intel_syntax noprefix
.code32
##############################################################################
RTL8139_DEBUG = 0 # NIC_DEBUG
RTL8139_STATUS_COMPACT = 1
##############################################################################
# Constants

NIC_IO = 0xc000
NIC_IRQ = 0x0b

# Registers are RW unless specified (RO).

RTL8139_MAC	= 0	# size 6
# 6,7 reserved
RTL8139_MAR	= 8	# size 8	Multicast
RTL8139_TSD0	= 0x10	# size 4 descriptor 0 transmit status
RTL8139_TSD1	= 0x14	# size 4 descriptor 1 transmit status
RTL8139_TSD2	= 0x18	# size 4 descriptor 2 transmit status
RTL8139_TSD3	= 0x1c	# size 4 descriptor 3 transmit status
		TSD_CRS	= 1<<31		# (RO) carrier sense lost
		TSD_TABT= 1<<30		# (RO) transmit abort
		TSD_OWC = 1<<29		# (RO) out of window collision
		TSD_CDH = 1<<28		# (RO) cd heart beat send fail(100mb=0)
		TSD_NCC = 0b1111 << 24	# (RO) number of collision count
		# 23-22 reserved
		TSD_ERTXTH=0b111111<<16	# early Tx tresh; 0=8 1=32,2=64 etc
		TSD_TOK	= 1<<15		# (RO) Transmit ok
		TSD_TUN	= 1<<14		# (RO) Transmit Underrun
		TSD_OWN	= 1<<13		# dma operation completed; set to 0
					# when transmit byte count is written
		TSD_SIZE= (1<<13)-1	# transmit byte count/descriptor size

RTL8139_TSAD0	= 0x20	# size 4 transmit start address for descriptor 0
RTL8139_TSAD1	= 0x24	# size 4 transmit start address for descriptor 1
RTL8139_TSAD2	= 0x28	# size 4 transmit start address for descriptor 2
RTL8139_TSAD3	= 0x2c	# size 4 transmit start address for descriptor 3
RTL8139_RBSTART	= 0x30	# size 4 receive buffer start
RTL8139_ERBCR	= 0x34	# size 2 (RO) early RX byte count
RTL8139_ERSR	= 0x36	# size 1 (RO) early RX status
		# writing 1 to these bits will clear them:
		ERSR_GOOD = 0b1000	# received good packet 
		ERSR_BAD  = 0b0100	# received bad packet
		ERSR_OVW  = 0b0010	# rx overwrite: local addr=capr
		# writing 1 to this bit invokes a ROK interrupt:
		ERSR_OK   = 0b0001	# default 0; rx byte>rx threshold;
		# on complete, clears this bit and aets ROK or RER in ISR

RTL8139_CR	= 0x37	# size 1 command register
		CMD_RST	= 1<<4	# reset
		CMD_RE	= 1<<3	# receiver enable
		CMD_TE	= 1<<2	# transmitter enable
		CMD_BUFE= 1	# (R)
RTL8139_CAPR	= 0x38	# size 2 current address of packet read
RTL8139_CBR	= 0x3a	# size 2 (RO) current buffer address (RX buffer content)
RTL8139_IMR	= 0x3C	# size 2 interrupt mask - 1 = enable
RTL8139_ISR	= 0x3E	# size 2 interrupt status
		# these apply to both IMR and ISR:
		IR_SERR		= 1<<15	# System Error
		IR_TIMEOUT	= 1<<14	# TCTR reaches TINT
		IR_LENCHG	= 1<<13	# Cable length changed
		IR_FOVW		= 1<<6	# Rx FIFO overflow
		IR_PUN		= 1<<5	# Packet Underrun/Link change
		IR_RXOVW	= 1<<4	# Rx buffer overflow
		IR_TER		= 1<<3	# Tx error
		IR_TOK		= 1<<2	# Tx ok
		IR_RER		= 1<<1	# Rx error
		IR_ROK		= 1<<0	# Rx ok
RTL8139_TCR	= 0x40	# size 4 transmit config
		TCR_HWVERID_A	= 0b11111 << 26  # (RO)
				# HW ID A   ID B
				# --------- ---
				# 1 1 0 0 0 0 0 RTL8139
				# 1 1 1 0 0 0 0 RTL8139A
				# 1 1 1 0 1 0 0 RTL8139A-G
				# 1 1 1 1 0 0 0 RTL8139B
				# 1 1 1 1 0 0 0 RTL8130
				# 1 1 1 0 1 0 0 RTL8139C
				# 1 1 1 1 0 1 0 RTL8100
				# 1 1 1 0 1 0 1 RTL8100B/8139D
				# 1 1 1 0 1 1 0 RTL8139C+
				# 1 1 1 0 1 1 1 RTL8101
		TCR_IFG		= 3<<24	# interframe gap time
		TCR_HWVERID_B	= 3<<22 # (RO)
		TCR_LBK		= 3<<17	# loopback test
		TCR_CRC		= 1<<16	# append crc_ 0=no, 0=append
		TCR_MXDMA2	= 7<<8	# Max DMA burst size per Tx
				# 000 = 16, 001=32, 010=64, 011=128...111=2048
		TCR_TXRR	= 15<<4	# Tx retry count: 16*(TXRR+1)
		TCR_CLRABT	= 1	# clear abort: 1=retransmit

RTL8139_RCR	= 0x44	# size 4 receive config
		# 31-28 reserved
		RCR_ERTH = 0b1111<<24	# early rx thr multiplier: ERTH/16 
		# 23-18 reserved
		RCR_MulERINT=1<<17	# multiple early int select
		RCR_RER8 = 1<<16	# error packet reception (see AER/AR)
		RCR_RXFTH= 0b111<<14	# rx fifo thresh: 16<<RXFTH;111=no thres
		RCR_RBLEN= 0b11 << 11	# rx buflen:16+(8k<<RBLEN)
		RCR_MXDMA= 0b111 <<8	# dma burst size=16<<MXDMA,111=unlimited
		RCR_WRAP= 1 << 7	# 0=wraparound, 1=buffer overflow(1.5k)
		# 6 = reserved
		RCR_AER	= 1 << 5	# accept error packet
		RCR_AR	= 1 << 4	# accept runt (smaller than 64 bytes)
		RCR_AB	= 1 << 3	# accept broadcast
		RCR_AM	= 1 << 2	# accept multicast
		RCR_APM	= 1 << 1	# accept physical match
		RCR_AAP	= 1 << 0	# accept all

# Receive Status 'Register': 16 bits bytes in RBSTART + CBR
# (followed by 16 bits of packet length, not dword aligned)
		# RSR_MAR and RSR_BAR are never simultaneously set)
		RSR_MAR = 1<<15	# multicast packet
		RSR_PAM = 1<<14	# physical address matched
		RSR_BAR = 1<<13	# broadcast packet 
		# 12-6 reserved
		RSR_ISE = 1<<5	# invalid symbol error
		RSR_RUNT= 1<<4	#'RUNT' packe: smaller than 64 bytes
		RSR_LONG= 1<<3	#packet > 4k
		RSR_CRC = 1<<2	#CRC error
		RSR_FAE = 1<<1	# Frame alignment error
		RSR_ROK = 1<<0	#good packet received



RTL8139_TCTR	= 0x48	# size 4 timer count - write will restart count
RTL8139_MPC	= 0x4c	# size 4 missed packet counter (24 bit), write=reset
RTL8139_9346CR	= 0x50	# size 1 93C46 command register
RTL8139_CONFIG0	= 0x51	# size 1
RTL8139_CONFIG1	= 0x52	# size 2
# 0x53 reserved
RTL8139_TINT	= 0x54	# size 4 timer interrupt. ISR.timeout=1 when TCTR
			# reaches the written (nonzero) value.
RTL8139_MSR	= 0x58	# size 1 media status
RTL8139_CONFIG3	= 0x59
RTL8139_CONFIG4	= 0x5a
# 0x5b reserved
RTL8139_MULINT	= 0x5c	# size 2 multiple interrupt select
RTL8139_RERID	= 0x5e	# size 1 (RO) PCI revision ID = 0x10
# 0x5f reserved
RTL8139_TSAD	= 0x60	# size 2 (RO) transmit status of all descriptors
RTL8139_BMCR	= 0x62	# size 2 basic mode control
RTL8139_BMSR	= 0x64	# size 2 (RO) basic mode status
RTL8139_ANAR	= 0x66	# size 2 auto-negotiation advertisement
RTL8139_ANLPAR	= 0x68	# size 2 (RO) auto-negotiation link partner
RTL8139_ANER	= 0x6a	# size 2 (RO) auto-negotiation expansion
RTL8139_DIS	= 0x6c	# size 2 (RO) disconnect counter
RTL8139_FCSC	= 0x6e	# size 2 (RO) false carrier sense counter
RTL8139_NWAYTR	= 0x70	# size 2 N-Way test register
RTL8139_REC	= 0x72	# size 2 (RO) RX_ER counter
RTL8139_CSCR	= 0x74	# size 2 CS configuration register
# 0x76-77 reserved 
RTL8139_PHY1_PAR= 0x78	# size 2 PHY param 1
RTL8139_TW_PAR	= 0x7c	# size 4 twister param
RTL8139_PHY2_PAR= 0x80	# size 1 PHY param 2
# 81-83 reserved
RTL8139_CRC0	= 0x84	# size 1x8 power mgmnt crc for wakeup frame0..7
RTL8139_WAKEUP0	= 0x8c	# size 8x8 power mgmnt wakeup frame 0..7 (64bit each
RTL8139_LSBCR0	= 0xcc	# size 1 LSB of mask byte of wakeup within offs 12..75
# 0xd4-d7 reserved
RTL8139_CONFIG5	= 0xd8	
# 0xd9-0xff reserved

############################################################################
# structure for the RTL8139 device object instance:
# append field to nic structure (subclass)
.struct NIC_STRUCT_SIZE
nic_rtl8139_desc_idx: .word 0
NIC_RTL8139_STRUCT_SIZE = .

DECLARE_PCI_DRIVER NIC, 0x10ec, 0x8139, rtl8139_init, "rtl8139", "Realtek 8139"
############################################################################
.text32
DRIVER_NIC_RTL8139_BEGIN = .


# in: dx = base port
# in: ebx = pci nic object
rtl8139_init:
	push	ebp
	push	edx
	push	dword ptr [ebx + dev_io]
	mov	ebp, esp

	# power on device
	mov	dx, [ebp]
	add	dx, RTL8139_CONFIG1
	mov	al, 0x52 	# LWAKE + LWPTN high - power on
	out	dx, al

	# software reset
	mov	dx, [ebp]
	add	dx, RTL8139_CR
	mov	al, CMD_RST
	out	dx, al
	# test status
	mov	ecx, 0x1000
0:	in	al, dx
	test	al, CMD_RST
	jz	0f
	loop	0b
	printlnc 4, "rtl8139: reset failed"
	stc
	jmp	9f
0:
	# set receive buffer start address
	mov	eax, 8192 + 16
	call	mallocz
	jc	9f
	mov	ecx, eax	# preserve

	# calculate and send physical address
	GDT_GET_BASE eax, ds
	add	eax, ecx

	mov	dx, [ebp]
	add	dx, RTL8139_RBSTART
	out	dx, eax

	# enable receiving packets

	#	RCR_RBLEN= 0b11 << 11	# rx buflen:16+(8k<<RBLEN)
	mov	eax, RCR_AER | RCR_AR | RCR_AB | RCR_AM | RCR_APM | RCR_AAP
	mov	dx, [ebp]
	add	dx, RTL8139_RCR	# receive config
	out	dx, eax

.if 0
	# enable transmitter and receiver
	mov	dx, [ebp]
	add	dx, RTL8139_CR
	mov	al, CMD_TE |CMD_RE
	out	dx, al
	in	al, dx
	and	al, CMD_TE | CMD_RE
	cmp	al, CMD_TE | CMD_RE
	jz	0f
	printlnc 4, "rtl8139: warning: transmitter/receiver not enabled"
0:
.endif

	.if 0
	# register the card
	push	ecx
	mov	ecx, NIC_RTL8139_STRUCT_SIZE
	call	nic_newentry	# out: eax = base; edx = index
	pop	ecx

	mov	ebx, eax
	add	ebx, edx
	.endif

	mov	[ebx + nic_rx_buf], ecx

	# register a name
	LOAD_TXT "rtl8139", (dword ptr [ebx + nic_name]);

	# fill in the methods
	mov	dword ptr [ebx + nic_api_send], offset rtl8139_send
	mov	dword ptr [ebx + nic_api_print_status], offset rtl8139_print_status
	mov	dword ptr [ebx + nic_api_ifup], offset rtl8139_ifup
	mov	dword ptr [ebx + nic_api_ifdown], offset rtl8139_ifdown

	# fill in the port
	#mov	dx, [ebp]
	#mov	[ebx + dev_io], dx

	# fill in the MAC address
	mov	edi, ebx
	add	edi, offset nic_mac
#BREAKPOINT "read mac"
	mov	dx, [ebx + dev_io]
	add	dx, RTL8139_MAC
	mov	ecx, 6
0:	in	al, dx
#DEBUG_BYTE al
	stosb
	inc	dx
	loop	0b
#BREAKPOINT "read mcast"
	# fill in the MCAST
	mov	edi, ebx
	add	edi, offset nic_mcast

	mov	dx, [ebp]
	add	dx, RTL8139_MAR
	mov	ecx, 8
0:	in	al, dx
	stosb
	inc	dx
	loop	0b
#BREAKPOINT "mcast read."
	# hook the isr

	mov	[rtl8139_isr_dev], ebx	# XX direct mem offset
	push	ebx
	movzx	ax, byte ptr [ebx + dev_irq]
	mov	[rtl8139_isr_irq], al
	add	ax, IRQ_BASE
	mov	ebx, offset rtl8139_isr
	add	ebx, [realsegflat]
	mov	cx, cs
	call	hook_isr
	pop	ebx

	mov	al, [ebx + dev_irq] # NIC_IRQ
	call	pic_enable_irq_line32

	# enable all interrupts

	mov	dx, [ebp]
	add	dx, RTL8139_IMR
	mov	ax, -1
	out	dx, ax


	clc
9:	pop	edx
	pop	edx
	pop	ebp
	ret

################################################################

# in: ebx = nic object
rtl8139_ifup:	
	mov	dx, [ebx + dev_io]

	add	dx, RTL8139_CR
	mov	al, CMD_TE | CMD_RE	# enable transmitter/receiver
	out	dx, al
	ret

# in: ebx = nic object
rtl8139_ifdown:	
	mov	dx, [ebx + dev_io]

	DEBUG_WORD dx
	add	dx, RTL8139_CR
	DEBUG_WORD dx
	xor	al, al
	out	dx, al
	in	al, dx
	call	printhex2
	ret

################################################################
# Interrupt Service Routine
.data
rtl8139_isr_irq: .byte 0
rtl8139_isr_dev: .long 0	# direct memory address of device object
.text32
rtl8139_isr:
	pushad
	push	es
	push	ds
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	es, ax

	.if RTL8139_DEBUG
		printc 0xf5, "NIC ISR"
	.endif

	mov	ebx, [rtl8139_isr_dev]

	.if RTL8139_DEBUG > 1
		call	rtl8139_print_ISR
		call	rtl8139_print_CBR
		#call	rtl8139_print_TSDs
	.endif

	# check what interrupts
	mov	dx, [ebx + dev_io]
	add	dx, RTL8139_ISR
	in	ax, dx
	or	ax, ax
	.if 1
	jnz	1f
	printlnc 4, "rtl8139_isr: spurious IRQ"
	jmp	9f
	1:
	.else
	jz	9f
	.endif

	test	ax, IR_TOK
	jnz	0f
	test	ax, IR_ROK
	jnz	1f

########
	# unknown: just clear them all
	.if RTL8139_DEBUG
		printc 0xf4 "?"
	.endif
	out	dx, ax	# mark them all as handled
	jmp	2f

########
0:	# TOK / Tx
	.if RTL8139_DEBUG
		printc 0xf3, "Tx"
	.endif
	mov	ax, IR_TOK
	out	dx, ax

	jmp	2f

########
1:	# ROK / Rx
	.if RTL8139_DEBUG
		printc 0xf3, "Rx"
		call	newline
	.endif

	# acknowledge interrupt to network card
	mov	ax, IR_ROK
	out	dx, ax		# RTL8139_ISR

	# Read the CBR
	add	dx, RTL8139_CBR - RTL8139_ISR
	in	ax, dx
	movzx	ecx, ax

	add	dx, RTL8139_CAPR - RTL8139_CBR
########
0:	
		# TMP: dx is modified....
		mov	ebx, [rtl8139_isr_dev]
		mov	dx, [ebx + dev_io]
		add	dx, RTL8139_CAPR

	# read packet / update CAPR
	xor	eax, eax
	in	ax, dx		# RTL8139_CAPR
	add	ax, 16	# correct for CAPR+16=CBR

	# handle buffer wrap
	cmp	eax, 8192
	jb	3f
	xor	eax, eax
3:	
	# FIXME: this does not take into account rx buffer wrapping
	push	esi
	push	ecx

	mov	esi, [ebx + nic_rx_buf]
	add	esi, eax
	mov	edx, [esi]
	add	esi, 4

	.if RTL8139_DEBUG > 1
		DEBUG_DWORD eax
		DEBUG_DWORD edx
	.endif

	.if RTL8139_DEBUG
		# check flags
		PRINTFLAG dx, RSR_MAR, "MAR "
		PRINTFLAG dx, RSR_PAM, "PAM "
		PRINTFLAG dx, RSR_BAR, "BAR "

		PRINTFLAG dx, RSR_ISE, "ISE "
		PRINTFLAG dx, RSR_RUNT, "RUNT "
		PRINTFLAG dx, RSR_LONG, "LONG "
		PRINTFLAG dx, RSR_CRC, "CRC "
		PRINTFLAG dx, RSR_FAE, "FAE "
		PRINTFLAG dx, RSR_ROK, "ROK "
	.endif

	# shift out the status bits
	mov	ecx, edx
	shr	ecx, 16

	test	dl, RSR_ROK
	jz	1f

	push	ecx
	push	ebx
	push	eax
	sub	ecx, 4	# the header includes the header size
	# NOTE: packets of 0x34 bytes for instance will have a len
	# of 0x40 - 4 = 0x3c - seems qword padded. So the real packet
	# length is unknown.
	call	net_rx_packet
	pop	eax
	pop	ebx
	pop	ecx
1:	
	# packet size may be not dword aligned
	add	cl, 3
	and	cl, ~3
	add	eax, ecx
	# add 4 bytes of the packet header (ebx) to get proper end-of-packet
	# subtract 16 bytes so that the card will write new packets:
	# CAPR must be 16 bytes before CBR.
	add	eax, 4 - 16
	# wrap
	cmp	eax, 8192
	jb	3f
	sub	eax, 8192
3:
	.if RTL8139_DEBUG > 1
		DEBUG "CBR"
		DEBUG_WORD ax
	.endif

	mov	ebx, [rtl8139_isr_dev]
	mov	dx, [ebx + dev_io]
	add	dx, RTL8139_CAPR
	out	dx, ax			# RTL8139_CAPR

	pop	ecx
	pop	esi


	# infinite loop check
	ror	ecx, 16
	inc	cx
	cmp	cx, 100
	jb	3f
	printlnc 4, "packet burst - might be bug"
	mov	ebx, [rtl8139_isr_dev]
	mov	dx, [ebx + dev_io]
	call	rtl8139_init
	call	newline
	sti
	BREAKPOINT "continue"
	jmp	9f
3:	ror	ecx, 16

	# check if we have more packets:
	add	ax, 16
	cmp	ax, cx
	jb	0b
########
2:
	.if RTL8139_DEBUG > 1
		mov	ebx, [rtl8139_isr_dev]
		#call	rtl8139_print_ISR
		call	rtl8139_print_CBR
	.endif
9:
	.if RTL8139_DEBUG
		printlnc 0xf5, "DONE"
	.endif

	mov	ebx, [rtl8139_isr_dev]
	PIC_SEND_EOI [ebx + dev_irq]

	pop	ds
	pop	es
	popad	# edx ebx eax
	iret

############################################################
# Send Packet

# in: ebx = nic device
# in: esi = packet
# in: ecx = packet size
rtl8139_send:
	pushad

	.if RTL8139_DEBUG > 1
		DEBUG "send"
		call	rtl8139_print_status
	.endif

	# get descriptor: MUST use round robin, otherwise only 1 packet is sent
	mov	dx, [ebx + nic_rtl8139_desc_idx]

	mov	ax, dx
	inc	ax
	cmp	ax, 4
	jb	0f
	xor	ax, ax
0:	mov	[ebx + nic_rtl8139_desc_idx], ax

	shl	dx, 2
	add	dx, [ebx + dev_io]

	GDT_GET_BASE eax, ds
	add	eax, esi

	add	dx, RTL8139_TSAD0
	out	dx, eax

	add	dx, RTL8139_TSD0 - RTL8139_TSAD0
	mov	eax, ecx
	and	eax, TSD_SIZE	# TODO: check
	# leave early transmit at 0 (8 bytes)
	# clears OWN bit (among others)
	out	dx, eax

	.if 0
		push edx
		call	rtl8139_print_status
		pop edx
	.endif

.if 0
	mov	ecx, 0x1000
0:	in	eax, dx
	test	eax, TSD_OWN
	jnz	0f
	loop	0b
0:	
DEBUG "FIFO"
DEBUG_DWORD eax

	mov	ecx, 0x1000
0:	in	eax, dx
	test	eax, TSD_TOK
	jnz	0f
	loop	0b
0:	
DEBUG "TOK"
DEBUG_DWORD eax
		call	rtl8139_print_status
.endif
	# let the IRQ handler deal with it

#	print "Clear TOK in ISR "
#	# clear bit in ISR
#	mov	dx, NIC_IO + RTL8139_ISR
#	mov	ax, IR_TOK
#	out	dx, ax
#	call	newline
	
#		call	rtl8139_print_status
	popad
	ret


# in: ebx = nic object
rtl8139_print_status:
	.if RTL8139_STATUS_COMPACT
		printc 11, "rtl8139: status: "
		call	rtl8139_print_CR
		call	rtl8139_print_ISR
		call	rtl8139_print_RCR
		call	rtl8139_print_CBR
		call	newline
	.else
		printlnc 11, "rtl8139: status: "
		print	"  "
		call	rtl8139_print_CR
		call	newline

		print	"  "
		call	rtl8139_print_ISR

		print "  "
		call	rtl8139_print_RCR

		call	rtl8139_print_CBR
	.endif

	.if RTL8139_DEBUG > 1
		print	"  "
		call	rtl8139_print_IMR
		call	newline
		print	"  "
		call	rtl8139_print_TSDs
	.endif
	ret

##########################

# in: ebx = nic object
rtl8139_print_CBR:
	mov	dx, [ebx + dev_io]

	printc	15, "CBR: "
	add	dx, RTL8139_CBR
	in	ax, dx
	mov	dx, ax
	call	printhex4

	printc 15, " CAPR: "
	mov	dx, [ebx + dev_io]
	add	dx, RTL8139_CAPR
	in	ax, dx
	mov	dx, ax
	call	printhex4
.if 0
	printc 15, " ERCBR: "
	mov	dx, [ebx + dev_io]
	add	dx, RTL8139_ERBCR
	in	ax, dx
	mov	dx, ax
	call	printhex4
.endif
	ret


##########################

# in: ebx = nic object
rtl8139_print_RCR:
	mov	dx, [ebx + dev_io]

	printc 15, "RCR: "
	add	dx, RTL8139_RCR
	in	ax, dx
	mov	dx, ax
	call	printhex4
	call	printspace
	ret
##########################

# in: ebx = nic object
rtl8139_print_CR:
	mov	dx, [ebx + dev_io]

	printc	15, "CR: "
	add	dx, RTL8139_CR
	in	al, dx
	mov	dl, al
	call	printhex2

	test	al, CMD_RE
	jz	0f
	print	" Rx"
0:
	test	al, CMD_TE
	jz	0f
	print	" Tx"
0:
	test	al, CMD_BUFE
	jz	0f
	print	" BUFE "
	ret
0:	print	" DATA "
	ret


# in: ebx = nic object
rtl8139_print_IMR:

	printc	15, "IMR: "
	mov	dx, RTL8139_IMR
	jmp	rtl8139_print_IR$

# in: ebx = nic object
rtl8139_print_ISR:
	printc	15, "ISR: "
	mov	dx, RTL8139_ISR
	#jmp	rtl8139_print_IR$

# in: ebx = nic object
rtl8139_print_IR$:
	add	dx, [ebx + dev_io]

	push	esi
	LOAD_TXT "SERR\0TimeOut\0LenChg\0.12\0.11\0.10\0.9\0.8\0.7\0FOVW\0PUN/LinkChg\0RXOVW\0TER\0TOK\0RER\0ROK\0"
	in	ax, dx
	mov	dx, ax
	call	printhex4
	call	printspace
	call	print_flags16
	pop	esi
	ret


# in: ebx = nic object
rtl8139_print_TSDs:
	call	newline
	ret
	call	printspace
	call	printspace
	mov	edx, 0
	call	rtl8139_print_TSD
	mov	edx, 1
	call	rtl8139_print_TSD
	mov	edx, 2
	call	rtl8139_print_TSD
	mov	edx, 3
	call	rtl8139_print_TSD
	ret

# in: ebx = nic object
# in: edx = 0..3
rtl8139_print_TSD:
	printc	15, "TSD"
	call	printdec32
	printc 15, ": "
	call	printspace
	shl	dx, 2
	add	dx, RTL8139_TSD0
	add	dx, [ebx + dev_io]
	in	eax, dx
	mov	edx, eax
	call	printhex8
	call	printspace

	PRINTFLAG eax, TSD_CRS, "CRS "
	PRINTFLAG eax, TSD_TABT, "TABT "
	PRINTFLAG eax, TSD_OWC, "OWC "
	PRINTFLAG eax, TSD_CDH, "CDH "
	PRINTFLAG eax, TSD_TOK, "TOK "
	PRINTFLAG eax, TSD_TUN, "TUN "
	PRINTFLAG eax, TSD_OWN, "OWN "
.if 0
	PRINT "(NCC "
	and	edx, TSD_NCC
	shr	edx, 24
	call	printdec32

	print	" ERTXTH "
	mov	edx, eax
	and	edx, TSD_ERTXTH
	shr	edx, 16
	jz	1f
	shl	edx, 5	# * 32 bytes
	jmp	2f
1:	mov	edx, 8
2:	call	printdec32

	print	" SIZE "
	mov	edx, eax
	and	edx, TSD_SIZE
	call	printdec32

	println ")"
.endif
	ret

DRIVER_NIC_RTL8139_END = .
DRIVER_NIC_RTL8139_SIZE = DRIVER_NIC_RTL8139_END - DRIVER_NIC_RTL8139_BEGIN
