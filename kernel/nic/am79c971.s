##############################################################################
# AMD AM79C971 PCNet Fast Network Controller
.intel_syntax noprefix
##############################################################################
AM79C_DEBUG = 0

# Configuration:
DESC_BITS = 32	# or 16: descriptor size
# calculate sw style by descriptor size choice: only SWSTYLE 2 is fully
# implemented; SWSTYLE 0 partially.
DESC_SIZE = DESC_BITS / 16 * 8 # 16b: 8 bytes; 32b: 16 bytes
SWSTYLE = DESC_BITS / 8 - 2	# 16/8-2 = 0, 32/8-2 = 2
FLAG_SHIFT = 12 * (SWSTYLE&2)	# 0 for swtyle0, 24 for swstyle 2

# ring lengths:
# DESC_BITS 32: max buffers = 1 << 9 = 512 in INIT block
# DESC_BITS 16: max buffers = 1 << 7 = 128 in INIT block
# CSR76 (RCVRL) and CSR78 (XMTRL) allow custom values but are not available
# in VMWare's VLANCE driver.
LOG2_RX_BUFFERS = 3
LOG2_TX_BUFFERS = 2
RX_BUFFERS = 1 << LOG2_RX_BUFFERS # 25
TX_BUFFERS = 1 << LOG2_TX_BUFFERS # 15
# End configuration


##############################################################################
# Constants
# In word IO mode (only available after a H_RESET), the RDP and other
# registers are 16 bit wide, so, the addresses become 0x10, 0x12, 0x14, 0x16.
# This driver only deals with 32 bit mode.
AM79C_APROM	= 0x00	# ..0x0f 16 bytes; first 6 are MAC.
AM79C_RDP	= 0x10					# reads CSR

AM79C_RAP16	= 0x12	# [RB]DP addr
AM79C_RESET16	= 0x14
AM79C_BDP16	= 0x16	# reads BCR

AM79C_RAP32	= 0x14	# [RB]DP addr
AM79C_RESET32	= 0x18
AM79C_BDP32	= 0x1c	# reads BCR


AM79C_RAP = AM79C_RAP32
AM79C_BDP = AM79C_BDP32

# out AM79C_RAP, nr	[nr 0..255]
# in  eax, AM79C_RDP	# read CSRnr
# in  eax, AM79C_BDP	# read BCRnr

AM79C_REG_CSR0 = 0	# CSR0 controller status
	AM79C_CSR0_ERR =	1 << 15	# BABL || CERR || MISS || MERR
	AM79C_CSR0_BABL =	1 << 14	# tx timeout
	AM79C_CSR0_CERR =	1 << 13	# collision error
	AM79C_CSR0_MISS =	1 << 12	# missed frame (no receive descriptors)
	AM79C_CSR0_MERR =	1 << 11	# memory error
	AM79C_CSR0_RINT =	1 << 10	# rx int
	AM79C_CSR0_TINT =	1 << 9	# tx int
	AM79C_CSR0_IDON =	1 << 8	# init done
	AM79C_CSR0_INTR =	1 << 7	# set when interrupt cause occurred (long list)
	AM79C_CSR0_IENA =	1 << 6	# enable INTA
	AM79C_CSR0_RXON =	1 << 5	# readonly; clear with H_RESET or (S_RESET&STOP)
	AM79C_CSR0_TXON =	1 << 4	# readonly
	AM79C_CSR0_TDMD =	1 << 3	# transmit demand: triggers tx desc ring
	AM79C_CSR0_STOP =	1 << 2	# stop DMA activity.
	AM79C_CSR0_STRT =	1 << 1	# clears stop
	AM79C_CSR0_INIT =	1 << 0	# clears stop
AM79C_REG_CSR1 = 1	# IADR lo word (initiialisation address)
AM79C_REG_CSR2 = 2	# IADR hi word
	# When SWSTYLE.SSIZE32 = 0 the high byte is used to generate 32 bit
	# addresses for buffers etc (as only 24 bits are written in descriptors)
AM79C_REG_CSR3 = 3	# interrupt masks and deferral control
	# mask flags (1 means int disabled)
	# (IM) means Interrupt Mask, (IC) means interrupt cause
	AM79C_CSR3_BABLM	= 1 << 14 # (IM)
	AM79C_CSR3_MISSM	= 1 << 12 # (IM)
	AM79C_CSR3_MERRM	= 1 << 11 # (IM)
	AM79C_CSR3_RINTM	= 1 << 10 # (IM) rx packet
	AM79C_CSR3_TINTM	= 1 << 9  # (IM) tx packet
	AM79C_CSR3_IDONM	= 1 << 8  # (IM) init done
	AM79C_CSR3_MASK_ALL	= 0b01011111 << 8
	# deferral control: 1 means enabled or disabled as indicated
	AM79C_CSR3_DXSUFLO	= 1 << 6 # disable transmit stop on underflow
	AM79C_CSR3_LAPPEN	= 1 << 5 # enable look ahead packet processing
	AM79C_CSR3_DXMT2PD	= 1 << 4 # disable transmit two part deferral
	AM79C_CSR3_EMBA		= 1 << 3 # modified back-off algorithm
	AM79C_CSR3_BSWP		= 1 << 2 # fifo bswap; 1 = bigendian (reset->0)
AM79C_REG_CSR4 = 4	# test and features
	AM79C_CSR4_EN124	= 1 << 15 # enable CSR124 access
	AM79C_CSR4_DMAPLUS	= 1 << 14 # always 1
	AM79C_CSR4_TXDPOLL	= 1 << 12 # disable transmit polling
	AM79C_CSR4_APAD_XMT	= 1 << 11 # enable auto pad transmit (to 64b)
	AM79C_CSR4_ASTRP_RCV	= 1 << 10 # enable auto strip receive
	AM79C_CSR4_MFCO		= 1 << 9 # (IC) missed frame counter overflow
	AM79C_CSR4_MFCOM	= 1 << 8 # (IM) missed frame counter ovfl mask
	AM79C_CSR4_UINTCMD	= 1 << 7 # user int command: trigger irq
	AM79C_CSR4_UINT		= 1 << 6 # (IC) user int; host clear: write 1
	AM79C_CSR4_RCVCCO	= 1 << 5 # (IC) receive collision cntr overflow
	AM79C_CSR4_RCVCCOM	= 1 << 4 # (IM) receive collision ctr ovrfl mask
	AM79C_CSR4_TXSTRT	= 1 << 3 # (IC) transmit start status
	AM79C_CSR4_TXSTRTM	= 1 << 2 # (IM) transmit start status mask
	AM79C_CSR4_JAB		= 1 << 1 # (IC) jabber error
	AM79C_CSR4_JABM		= 1 << 0 # (IM) jabber error int mask

AM79C_REG_CSR5 = 5	# extended control and interrupt
	AM79C_CSR5_SPND		= 1 << 0 # suspend mode; write 1, poll until 1
AM79C_REG_CSR7 = 7	# extended control and interrupt 2
	AM79C_CSR7_FASTSPND	= 1 << 15 # fast suspend
# reg 8,9,10,11: LADR - logical address filter: 64 bit mask
# CRC32(MAC) >> (32-6) = bit index (high 6 bits of CRC32 of target MAC)
AM79C_REG_CSR_LADRF0 = 8	# word sized; specfied in INIT block; writable
AM79C_REG_CSR_LADRF1 = 9	# only when STOP or SPND bit is set. unaffected
AM79C_REG_CSR_LADRF2 = 10	# by H_RESET, S_RESET, or STOP.
AM79C_REG_CSR_LADRF3 = 11
# MAC registers
AM79C_REG_CSR_PADRL = 12 # physical (MAC) address lo 2 bytes
AM79C_REG_CSR_PADRM = 13 # physical (MAC) address lo 2 bytes
AM79C_REG_CSR_PADRH = 14 # physical (MAC) address lo 2 bytes
AM79C_REG_CSR_MODE = 15	# default 0
	AM79C_MODE_PROMISC	= 0x8000
	AM79C_MODE_DRXBA	= 0x4000 # DRCVBC disable rcv broadcast
	AM79C_MODE_DRXPA	= 0x2000 # DRCVPA disable rcv phys addr
	AM79C_MODE_DLNKTST	= 0x1000 # disable link status 0=monitor,1=don't
	AM79C_MODE_DAPC		= 0x0800
	AM79C_MODE_MENDECL	= 0x0400 # MENDEC loopback mode (csr15#2)
	AM79C_MODE_LRT_TSEL	= 0x0200 # 'TMAU' mode: low receive threshold
	AM79C_MODE_PORTSEL1	= 0x0100 # MII, media independent 0x0101
	AM79C_MODE_PORTSEL0	= 0x0080 # 10 Base T
#	AM79C_MODE_PORT_AUI	= 0x0000
#	AM79C_MODE_PORT_10BT	= 0x0080
	AM79C_MODE_INTLOOP	= 0x0040 # internal loopback
	AM79C_MODE_DRTY		= 0x0020 # disable retry
	AM79C_MODE_FCOLL	= 0x0010 # force collision (test)
	AM79C_MODE_DXMTFCS	= 0x0008 # disable transmit CRC (FCS)
	AM79C_MODE_LOOP		= 0x0004
	AM79C_MODE_DTX		= 0x0002 # disable transmit: ignore tx_desc
	AM79C_MODE_DRX		= 0x0001 # disable receive: ignore rx_desc
AM79C_REG_CSR_BADRL	= 24	# CSR24: base address of RCV ring lo
AM79C_REG_CSR_BADRH	= 25	# CSR25: base address of RCV ring hi
AM79C_REG_CSR_BADXL	= 30	# CSR30: base address of XMT ring lo
AM79C_REG_CSR_BADXH	= 31	# CSR31: base address of XMT ring hi
AM79C_REG_CSR_TXPOLLINT	= 47	# transmit polling interval
AM79C_REG_CSR_RXPOLLINT	= 49	# receive polling interval
AM79C_REG_CSR_SWSTYLE	= 58	# alias of/see BCR20
AM79C_REG_CSR_MFC	= 112	# missed frame count
AM79C_REG_CSR114 = 114	# pci status register

# N/A on vmware:
AM79C_REG_CSR_RCVRC	= 72	# receive ring counter (0=last desc) (2's cmpl)
# N/A on vmware:
AM79C_REG_CSR_XMTRC	= 74	# transmit ring counter (2's complement)
# available in vmware VLANCE
AM79C_REG_CSR_RCVRL	= 76	# receive ring length (2's complement)
# N/A on vmware:
AM79C_REG_CSR_XMTRL	= 78	# transmit ring length (2's complement)

AM79C_REG_BCR_2 = 2
AM79C_REG_BCR_5 = 5
AM79C_REG_BCR_6 = 6
AM79C_REG_BCR_7 = 7
AM79C_REG_BCR_18 = 18	# bit 7: 1= 32 bit io mode, 0=16
AM79C_REG_BCR_SWSTYLE	= 20	# p 183 lo byte 0 = 16 byte structures (descr etc)
	AM79C_SWSTYLE_APERREN = 1 << 10	# advanced parity error handling
	AM79C_SWSTYLE_RES = 1 << 9	# undocumented; seems to be 1.
	AM79C_SWSTYLE_SSIZE32 = 1 << 8	# r/o: 32 bit init/descriptor structs
					# determined by low 8 bits as follows:
	# legend:
	#  rbaddr = receive buffer address
	#  bcnt = buffer byte count (size of buffer)
	#  mcnt = message byte count
	AM79C_SWSTYLE_0  = 0x00 # 16 bit; Lance/PCnet-ISA controller
	#	.word rbaddr[15:0]   # upper 8 bytes of 32b addr: CSR2
	#	.word flags8 << 8 | rbaddr[23:16]
	#	.word 0b1111<<12 | BCNT[11:0]
	#	.word 0b0000<<12 | MCNT[11:0]
	AM79C_SWSTYLE_1 = 0x01 # 32 bit; reserved
	AM79C_SWSTYLE_2 = 0x02 # 32 bit; PCnet-PCI controller
	# low byte 2: 32 bit
	#	.long rbaddr
	#	.long flags12 << 20 | 0bRESV1111 << 12 | BCNT[11:0]
	#	.long RES << 31 | RFRTAG[14:0] << 16 | 0b0000<<12 | MCNT
	#	.long userspace
	AM79C_SWSTYLE_3 = 0x03 # 32 bit; PCnet-PCI controller
	#	.long RES << 31 | RFRTAG[14:0] << 16 | 0b0000 << 12 | MCNT
	#	.long flags12 << 20 | 0b????1111 << 12 | BCNT
	#	.long rbaddr
	#	.long userspace
	# all other values are reserved.

# Transmit descriptor structure:
#
# SWSTYLE 0:  (4th byte of TBADR is taken from CSR2)
#
# 0x00:	TBADR[15:0]
# 0x02: OWN | ERR | ADD_FCS | MORE/LTINT | ONE | DEF | STP | ENP | TBADR[23:16]
# 0x04: 0b1111 | BCNT[12:0]
# 0x06: BUFF | UFLO | EXDEF | LCOL | LCAR | RTRY | TDR[9:0]
#
# SWSTYLE 2:
#
# 0x00: TBADR[31:0]
# 0x04: OWN|ERR|ADD_FCS|MORE/LTINT|ONE|DEF|STP|ENP|BPE|res|1111|BCNT[11:0]
# 0x08: BUFF|UFLO|EXDEC|LCOL|LCAR|RTRY|res[25:4]|TRC[3:0] # TRC=tx retrt cnt
# 0x0c: user space[31:0]
#
# SWSTYLE 3:
#
# 0x00: swstyle 2 0x08 (BUFFF|UFLO|EXDEF...|TRC[3:0]
# 0x04: swstyle 2 0x04 (OWN|ERR|..|BCNT[11:0])
# 0x08: swstyle 2 0x00 (TBADR[31:0)
# 0x0c: swstyle 2 0x0c (user space)


# Receive descriptor structure:
#
# SWSTYLE 0: (4th byte of RBADR is taken from CSR2)
#
# 0x00: RBADR[15:0]	# linear buffer address
# 0x02: OWN | ERR | FRAM | OFLO | CRC | BUFF | STP | ENP | RBADR[23:16]
# 0x04: 1111 | BCNT[11:0]	# size of buffer
# 0x06: 0000 | MCNT[11:0]	# size of packet stored in buffer
#
# SWSTYLE 2
#
# 0x00: RBADR[31:0]
# 0x04: OWN|ERR|FRAM|OFLO|CRC|BUFF|STP|ENP|BPE|PAM|LAFM|BAM|RES|1111|BCNT[11:0]
# 0x08: res| RFRTAG[14:0] | 0000 | MCNT[11:0]
# 0x0c: user space[31:0]
#
# SWSTYLE 3
#
# 0x00: swstyle 2 0x08 (res|RFRTAG|0000|MCNT)
# 0x04: swstyle 2 0x04 (OWN|ERR|..|1111|BCNT)
# 0x08: swstyle 2 0x00 (RBADR[31:0)
# 0x0c: swstyle 2 0x0c (user space)

# The descriptor flags below are shifted according to the SWSTYLE.
# For SWSTYLE 0 (four words) the flags are byte-based,
# i.e. the lowest flag RDF_ENP is bit 1.
# For SWSTYLE 1, the flags are shifted so they align with the 2nd DWORD
# in the structure. This is done because there are more flags in SWSTYLE > 0.

# Receive Descriptor Flags
	# Second byte/word in receive descriptor structure:
	# SW STYLE 0: byte 2 (flags8; << 8 in structure) SWSTYLE 2: byte 4
	RDF_OWN	= 1 << (7 + FLAG_SHIFT)
	RDF_ERR	= 1 << (6 + FLAG_SHIFT)
	RDF_FRAM= 1 << (5 + FLAG_SHIFT)
	RDF_OFLO= 1 << (4 + FLAG_SHIFT)
	RDF_CRC	= 1 << (3 + FLAG_SHIFT)
	RDF_BUFF= 1 << (2 + FLAG_SHIFT)
	RDF_STP	= 1 << (1 + FLAG_SHIFT)	# start of packet; LAPPEN=0: nic sets,0=host sets
	RDF_ENP	= 1 << (0 + FLAG_SHIFT) # end of packet; STP+ENP=packet fits
	# SW STYLE>1: shift above flags 24 bit
	RDF_BPE = 1 << 23 #11	# parity error
	RDF_PAM = 1 << 22 #10	# physical address match
	RDF_LAFM= 1 << 21 #9	# logical address filter match
	RDF_BAM = 1 << 20 # 8	# broadcast address match
	RDF_RES = 0b0000 << 16
	RDF_ONES= 0b1111 << 12

# Transmit Descriptor flags
	# SWSTYLE 0: byte 2; SWSTYLE 2: 2nd dword
	TDF_OWN		= 1 << (7 + FLAG_SHIFT)
	TDF_ERR		= 1 << (6 + FLAG_SHIFT)
	TDF_ADD_FCS	= 1 << (5 + FLAG_SHIFT)
	TDF_MORE_LTINT	= 1 << (4 + FLAG_SHIFT)
	TDF_ONE		= 1 << (2 + FLAG_SHIFT)
	TDF_DEF		= 1 << (2 + FLAG_SHIFT)
	TDF_STP		= 1 << (1 + FLAG_SHIFT)
	TDF_ENP		= 1 << (0 + FLAG_SHIFT)
	# SWSTYLE 0: byte 6; SWSTYLE 2: 3rd dword
	TDF_BUFF	= 1 << (7 + FLAG_SHIFT)
	TDF_UFLO	= 1 << (6 + FLAG_SHIFT)
	TDF_EXDEF	= 1 << (5 + FLAG_SHIFT)
	TDF_LCOL	= 1 << (4 + FLAG_SHIFT)
	TDF_LCAR	= 1 << (3 + FLAG_SHIFT)
	TDF_RTRY	= 1 << (2 + FLAG_SHIFT)

############################################################################
# structure for the AM79C971 device object instance:
# append field to nic structure (subclass)
DECLARE_CLASS_BEGIN nic_am79c, nic
nic_am79c_init_block:	.long 0
DECLARE_CLASS_METHOD dev_api_constructor, am79c971_init, OVERRIDE
DECLARE_CLASS_METHOD dev_api_isr,	am79c971_isr, OVERRIDE
DECLARE_CLASS_METHOD nic_api_send,	am79c971_send, OVERRIDE
DECLARE_CLASS_METHOD nic_api_print_status, am79c971_print_status, OVERRIDE
DECLARE_CLASS_METHOD nic_api_ifup,	am79c971_ifup, OVERRIDE
DECLARE_CLASS_METHOD nic_api_ifdown,	am79c971_ifdown, OVERRIDE

DECLARE_CLASS_END nic_am79c

DECLARE_PCI_DRIVER NIC_ETH, nic_am79c, 0x1022, 0x2000, "am79c971", "AMD 79C971 PCNet"
############################################################################
.text32
DRIVER_NIC_AM79C_BEGIN = .

.macro AM79C_WRITE which, val
	mov	dx, [ebx + dev_io]
	add	dx, AM79C_\which
	.ifnes "\val", "eax"
	mov	eax, \val
	.endif
	.if AM79C_DEBUG > 3
		DEBUG_DWORD eax, "W \which"
	.endif
	out	dx, eax
.endm

.macro AM79C_READ which
	mov	dx, [ebx + dev_io]
	add	dx, AM79C_\which
	in	eax, dx
	.if AM79C_DEBUG > 3
		DEBUG_DWORD eax, "R \which"
	.endif
.endm

.macro AM79C_READw which
	mov	dx, [ebx + dev_io]
	add	dx, AM79C_\which
	in	ax, dx
	.if AM79C_DEBUG > 3
		DEBUG_WORD ax, "R \which"
	.endif
.endm

.macro AM79C_WRITE_CSR csr, val
	.ifc eax,\val
	push	eax
	.endif
	AM79C_WRITE RAP AM79C_REG_\csr
	.ifc eax,\val
	pop	eax
	.endif
	AM79C_WRITE RDP \val
.endm

.macro AM79C_READ_CSR csr
	AM79C_WRITE RAP AM79C_REG_\csr
	AM79C_READ RDP
.endm

.macro AM79C_WRITE_BCR bcr, val
	.ifc eax,\val
	push	eax
	.endif
	AM79C_WRITE RAP AM79C_REG_BCR_\bcr
	.ifc eax,\val
	pop	eax
	.endif
	AM79C_WRITE BDP \val
.endm

.macro AM79C_READ_BCR bcr
	AM79C_WRITE RAP AM79C_REG_BCR_\bcr
	AM79C_READ BDP
.endm




###############################################################################

# in: ebx = pci nic object
am79c971_init:
	push	ebp
	push	edx
	push	dword ptr [ebx + dev_io]
	mov	ebp, esp

	call	am79c_read_mac_aprom	# needed for the PADR in INIT buffer

	call	am79c_alloc_buffers
	jc	9f

	call	dev_add_irq_handler
	call	dev_pci_busmaster_enable

	# reset
	mov	dx, [ebx + dev_io]
	add	dx, AM79C_RESET32
	in	eax, dx
	xor	eax, eax
	out	dx, eax
	add	dx, AM79C_RESET16 - AM79C_RESET32
	in	ax, dx

	# wait 5 musec
	mov	eax, 5
	call	udelay

	AM79C_WRITE_CSR CSR_MODE, AM79C_MODE_PORTSEL0 #| AM79C_MODE_PROMISC
	# stop (rreg): clear all interrupt bits and set the STOP bit
	AM79C_WRITE_CSR CSR0, AM79C_CSR0_BABL|AM79C_CSR0_CERR|AM79C_CSR0_MISS|AM79C_CSR0_MERR|AM79C_CSR0_TINT|AM79C_CSR0_RINT|AM79C_CSR0_STOP

	AM79C_WRITE_CSR CSR3, AM79C_CSR3_MASK_ALL	# disable all interrupts

	# disable tx polling - only tx on demand. # N/A on vmware VLANCE.
	AM79C_WRITE_CSR CSR_TXPOLLINT, 0

	.if 0
	# led configuration
	AM79C_WRITE_BCR 5, 0x00a0
	AM79C_WRITE_BCR 6, 0x0081
	AM79C_WRITE_BCR 7, 0x0090
	AM79C_WRITE_BCR 2, 0x0000	# mode
	.endif


	# set software style (structure of descriptors)
	AM79C_READ_BCR SWSTYLE
	mov	al, SWSTYLE
	AM79C_WRITE_BCR SWSTYLE, eax


	# write init block
	GDT_GET_BASE ecx, ds
	add	ecx, [ebx + nic_am79c_init_block]
	movzx	eax, cx
	AM79C_WRITE_CSR CSR1, eax
	mov	eax, ecx
	shr	eax, 16
	AM79C_WRITE_CSR CSR2, eax


	# enable all interrupt messages
	AM79C_WRITE_CSR CSR3, 0 # AM79C_CSR3_IDONM|AM79C_CSR3_BABLM|AM79C_CSR3_DXSUFLO

	# features: enable auto-pad tx packets, disable int on tx start
	AM79C_READ_CSR CSR4
	or	eax, AM79C_CSR4_APAD_XMT | AM79C_CSR4_TXSTRTM
	AM79C_WRITE_CSR CSR4, eax
	###########################################

	# initialize
	I "Init AM79C971"
	AM79C_WRITE_CSR CSR0, AM79C_CSR0_INIT

	# Wait for CSR0.IDON;
	mov	ecx, 0x1000
0:	AM79C_READ_CSR CSR0
	test	eax, AM79C_CSR0_IDON
	jnz	0f
	loop	0b
0:
	test	eax, AM79C_CSR0_IDON
	jz	0f
	AM79C_WRITE_CSR CSR0, eax	# clear the IDON bit
	AM79C_READ_CSR CSR_MODE
	and	eax, 0xfff	# mask out non-mode bits
	cmp	eax, AM79C_MODE_PORTSEL0
	jnz	2f
	OK
	jmp	1f
2:	printlnc 4, " Error"
	jmp	1f
0:	printlnc 4, " Timeout"
1:

	AM79C_WRITE_CSR CSR0, AM79C_CSR0_STOP

	##################################################
	# These values are set in the INIT block:
	.if 0
	# rreg BCR L ADR 8..11 # write a multi-hash - todo, requires CRC16
	# write PADR
	lea	esi, [ebx + nic_mac]
	xor	eax, eax
	lodsw
	AM79C_WRITE_CSR CSR_PADRL, eax
	lodsw
	AM79C_WRITE_CSR CSR_PADRM, eax
	lodsw
	AM79C_WRITE_CSR CSR_PADRH, eax

	#############################
	# write ring buffer addresses
	GDT_GET_BASE eax, ds
	add	eax, [ebx + nic_rx_desc]
	push	eax
	and	eax, 0xffff
	AM79C_WRITE_CSR CSR_BADRL, eax	# [ ebx + nic_rx_desc]
	pop	eax
	shr	eax, 16
	AM79C_WRITE_CSR CSR_BADRH, eax

	GDT_GET_BASE eax, ds
	add	eax, [ebx + nic_tx_desc]
	push	eax
	and	eax, 0xffff
	AM79C_WRITE_CSR CSR_BADXL, eax	# [ ebx + nic_rx_desc]
	pop	eax
	shr	eax, 16
	AM79C_WRITE_CSR CSR_BADXH, eax

	# these registers are N/A in VMWare
	AM79C_WRITE_CSR CSR_RCVRL, -RX_BUFFERS
	AM79C_WRITE_CSR CSR_XMTRL, -TX_BUFFERS
#	AM79C_WRITE_CSR CSR_RCVRC, 0
#	AM79C_WRITE_CSR CSR_XMTRC, 0
	##################################################
	.endif

	.if AM79C_DEBUG > 1
		call	am79c_print_csr0
		call	am79c_print_csr3
		call	am79c_print_csr4
		call	am79c_print_iadr
		call	am79c_print_iobits
	.endif

	clc
9:	pop	edx
	pop	edx
	pop	ebp
	ret


########################################################################
am79c_alloc_buffers:
	.if SWSTYLE == 1
		_BUF_ALIGN  = 8
	.else
		_BUF_ALIGN = 16
	.endif
	NIC_ALLOC_BUFFERS RX_BUFFERS, TX_BUFFERS, DESC_SIZE, 1600, 9f,_BUF_ALIGN
	#############################################################
	NIC_DESC_LOOP rx
	GDT_GET_BASE edx, ds
	add	edx, esi
	.if SWSTYLE == 0
		mov	[edi], dx # si
		shr	edx, 16
		mov	dh, RDF_OWN
		mov	[edi + 2], dx
		mov	[edi + 3], dl
		mov	[edi + 4], word ptr -1600
		mov	[edi + 6], word ptr 0
	.elseif SWSTYLE == 2
		#	.long rbaddr
		mov	[edi], edx
		#	.long flags12 << 20 | 0bRESV1111 << 12 | BCNT[11:0]
		mov	[edi + 4], dword ptr RDF_OWN | 0xf000 | (-1600 & 0x0fff)
		#	.long RES << 31 | RFRTAG[14:0] << 16 | 0b0000<<12 | MCNT
		mov	[edi + 8], dword ptr 0
		mov	[edi + 12], esi # userspace
	.endif
	NIC_DESC_ENDL
	#############################################################
	NIC_DESC_LOOP tx
	GDT_GET_BASE edx, ds
	add	edx, esi
	.if SWSTYLE == 0
	mov	[edi], dx # si
	shr	edx, 16
	mov	dh, RDF_STP|RDF_ENP
	mov	[edi + 2], dx
	mov	[edi + 4], word ptr -1600
	mov	[edi + 6], word ptr 0
	.elseif SWSTYLE == 2
	mov	[edi], edx	# tbaddr
	mov	[edi + 12], esi	# userspace
	mov	[edi + 4], dword ptr (TDF_STP|TDF_ENP)| 0xf000| (-1600 & 0x0fff)
	.endif
	NIC_DESC_ENDL
	#############################################################

	# Initialisation block

.struct 0
am79c_init_mode: .word 0	# csr15, card mode
am79c_init_rlen: .byte 0	# receive descriptor entries (log2)
am79c_init_tlen: .byte 0	# transmit descriptor entries (log2)
	# DESC_BITS = 16: 3 bits: 1 << [rt]len
	# DESC_BITS = 32: 4 bits: min( 1 << [rt]len, 512) (eff max: 0b1001)
am79c_init_padr: .space 6	# physical address
		.word 0	# reserved
am79c_init_ladrf: .space 8	# logical address filter (mcast mac)
am79c_init_rdra: .long 0	# receive descriptor ring address
am79c_init_tdra: .long 0	# transmit descriptor ring address
AM79C_INIT_BLOCK_SIZE = .	# 28 bytes
.text32

	mov	eax, AM79C_INIT_BLOCK_SIZE
	mov	edx, 4
	call	mallocz_aligned
	jc	9f
	mov	[ebx + nic_am79c_init_block], eax	# dword aligned

#	mov	dword ptr [eax + am79c_init_mode], AM79C_MODE_PORTSEL0 | AM79C_MODE_PROMISC | ((LOG2_TX_BUFFERS&0xf)<<28)|((LOG2_RX_BUFFERS&0xf)<<20)
	mov	word ptr [eax + am79c_init_mode], AM79C_MODE_PORTSEL0 #| AM79C_MODE_PROMISC
	mov	byte ptr [eax + am79c_init_rlen], (LOG2_RX_BUFFERS<<4)&0xf0
	mov	byte ptr [eax + am79c_init_tlen], (LOG2_TX_BUFFERS<<4)&0xf0
	lea	edi, [eax + am79c_init_padr]	# from read_mac_aprom
	lea	esi, [ebx + nic_mac]
	movsd
	movsw
	xor	eax, eax
	stosw	# reserved word
	mov	eax, -1	# accept all multicast packets
	stosd	# am79c_init_ladr
	stosd	# am79c_init_ladr + 4

	GDT_GET_BASE ecx, ds
	mov	eax, [ebx + nic_rx_desc]
	add	eax, ecx
	stosd	# am79c_init_rdra
	mov	eax, [ebx + nic_tx_desc]
	add	eax, ecx
	stosd	# am79c_init_tdra

	.if AM79C_DEBUG
		call	newline
		mov	esi, [ebx + nic_am79c_init_block]
		print "mode: "
		mov	dx, [esi + am79c_init_mode]
		call	printhex4
		print " rlen: "
		mov	dl, [esi + am79c_init_rlen]
		call	printhex2
		print " tlen: "
		mov	dl, [esi + am79c_init_rlen]
		call	printhex2
		push	esi
		add	esi, offset am79c_init_padr
		print " padr: "
		call	net_print_mac
		pop	esi
		print " ladrf: "
		mov	edx, [esi + am79c_init_ladrf]
		call	printhex8
		mov	edx, [esi + am79c_init_ladrf + 4]
		call	printhex8
		print " rx desc: "
		mov	edx, [esi + am79c_init_rdra]
		call	printhex8
		print " tx desc: "
		mov	edx, [esi + am79c_init_tdra]
		call	printhex8
		call	newline
	.endif

	clc
9:	ret


am79c_dword_mode:
	# set to dword mode
	mov	dx, [ebx + dev_io]
	add	dx, AM79C_RAP16	# RAP addr in 16 bit mode
	xor	eax, eax
	out	dx, eax	# dword write inits dword mode
	ret

# in: ebx = pci_dev nic device
am79c_read_mac:
	print "PADR MAC: "
	AM79C_READ_CSR CSR_PADRL
	mov	dx, ax
	call	printhex4
	printchar ':'
	AM79C_READ_CSR CSR_PADRM
	mov	dx, ax
	call	printhex4
	printchar ':'
	AM79C_READ_CSR CSR_PADRH
	mov	dx, ax
	call	printhex4
	ret

am79c_read_mac_aprom:
	push	eax
	push	ecx
	push	edx
	push	edi

	# read APROM first 6 bytes: MAC
	lea	edi, [ebx + nic_mac]
	mov	dx, [ebx + dev_io]
	mov	ecx, 6
0:	in	al, dx
	stosb
	inc	dx
	loop	0b

	push	esi
	print_ "APROM MAC: "
	lea	esi, [ebx + nic_mac]
	call	net_print_mac
	pop	esi

	# TODO: check vendor bytes in mac to see if card matches

	call	newline

	clc

	pop	edi
	pop	edx
	pop	ecx
	pop	eax
	ret


	###############

.if AM79C_DEBUG
am79c_print_rx_desc:
	push	eax
	push	edx
	push	esi
	push	ecx
	pushcolor 11

	print "debug rx desc head="
	mov	edx, [ebx + nic_rx_desc_h]
	call	printdec32
	print " tail="
	mov	edx, [ebx + nic_rx_desc_t]
	call	printdec32
	call	newline

	# debug the descriptors
	mov	esi, [ebx + nic_rx_desc]
	mov	ecx, RX_BUFFERS
2:	mov	edx, RX_BUFFERS
	sub	edx, ecx

	mov	ah, [ebx + nic_rx_desc_h]
	dec	ah
	and	ah, RX_BUFFERS -1

	mov	al, 7
	cmp	ah, dl
	jnz	1f
	mov	al, 13
1:	color	al

	call	printdec32
	call	printspace

.if SWSTYLE==0

	print "rbaddr "
	lodsw	# low 15 bits of addr
	mov	dx, ax
	lodsw	# lo byte is 3rd byte; 4th byte in CSR2
	shl	edx, 16
	mov	dl, al
	# mov ah, read CSR2
	ror	edx, 16
	call	printhex8

	print " stat "
	mov	dl, ah
	call	printbin8
	push	esi
	LOAD_TXT "OWN\0ERR\0FRAM\0OFLO\0CRC\0BUFF\0STP\0ENP\0"
	call	print_flags8
	pop	esi

	print " size "
	lodsw
	mov	dx, ax
	neg	dx
	call	printhex4

	print " ?? "
	lodsw
	mov	dx, ax
	call	printhex4

.elseif SWSTYLE==2
.if 0
	print "rbaddr "
	lodsd
	mov	edx, eax
	call	printhex8

	print " flags "
	lodsw
	mov	dx, ax
	call	printbin16
	.if 0
	LOAD_TXT "OWN\0ERR\0FRAM\0OFLO\0CRC\0BUFF\0STP\0ENP\0BPE\0PAM\0LAFM\0BAM\0"
	and	dx, ~ 0b1111
	call	print_flags16
	.endif

	lodsw
	mov	dx, ax
	neg	dx
	print " size "
	call	printdec32

	lodsd
	lodsd
.endif

	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8

	call	printspace
	push	esi
	mov	ax, [esi - 16 + 4 + 2]
	call	printhex4
	call	printspace
	and	eax, 0xfff0
	LOAD_TXT "OWN\0ERR\0FRAM\0OFLO\0CRC\0BUFF\0STP\0ENP\0BPE\0PAM\0LAFM\0BAM"
	call	print_flags16
	pop	esi
.endif
	call	newline
	dec	ecx
	jnz	2b
#	loop	2b

	popcolor
	pop	ecx
	pop	esi
	pop	edx
	pop	eax
	ret



am79c_print_tx_desc:
	push	eax
	push	edx
	push	esi
	push	ecx
	pushcolor 11

	print "debug tx desc head="
	mov	edx, [ebx + nic_tx_desc_h]
	call	printdec32
	print " tail="
	mov	edx, [ebx + nic_tx_desc_t]
	call	printdec32
	call	newline

	# debug the descriptors
	mov	esi, [ebx + nic_tx_desc]
	mov	ecx, TX_BUFFERS
2:	mov	edx, TX_BUFFERS
	sub	edx, ecx

	mov	al, 7
	cmp	edx, [ebx + nic_tx_desc_h]
	jnz	1f
	mov	al, 13
1:	color	al


	call	printdec32
	call	printspace

.if SWSTYLE==0

	print "tbaddr "
	lodsw
	mov	dx, ax
	lodsw
	shl	edx, 16
	mov	dl, al
	# mov ah, read CSR2
	ror	edx, 16
	call	printhex8	# note: high byte of addr may be invalid (CSR2)

	print " stat "
	mov	dl, ah
	call	printbin8
	push	esi
	LOAD_TXT "OWN\0ERR\0ADD_FCS\0MORE/LTINT\0ONE\0DEF\0STP\0ENP\0"
	call	print_flags8
	pop	esi

	print " size "
	lodsw
	mov	dx, ax
	neg	dx
	call	printhex4

	print " ?? "
	lodsw
	mov	dx, ax
	call	printhex4

.elseif SWSTYLE==2
.if 0
	print "rbaddr "
	lodsd
	mov	edx, eax
	call	printhex8

	print " flags "
	lodsw
	mov	dx, ax
	call	printbin16
	.if 0
	LOAD_TXT "OWN\0ERR\0FRAM\0OFLO\0CRC\0BUFF\0STP\0ENP\0BPE\0PAM\0LAFM\0BAM\0"
	and	dx, ~ 0b1111
	call	print_flags16
	.endif

	lodsw
	mov	dx, ax
	neg	dx
	print " size "
	call	printdec32

	lodsd
	lodsd
.endif

	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	lodsd
	mov	edx, eax
	call	printhex8
.endif
	call	newline
	loop	2b

	popcolor
	pop	ecx
	pop	esi
	pop	edx
	pop	eax
	ret

.endif

################################################################

# in: ebx = nic object
am79c971_ifup:
	AM79C_WRITE_CSR CSR0, AM79C_CSR0_IENA | AM79C_CSR0_STRT
	ret

# in: ebx = nic object
am79c971_ifdown:
	AM79C_WRITE_CSR CSR0, AM79C_CSR0_STOP
	ret

################################################################
# Interrupt Service Routine
am79c971_isr:
	pushad
	push	ds
	push	es
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax
	mov	ebx, edx	# see irq_isr and (dev_)add_irq_handler

	.if AM79C_DEBUG
		printc 0xf5, "NIC ISR"
	.endif
	.if AM79C_DEBUG > 2
		pushad
		call	am79c971_print_status
		popad
	.endif
	.if AM79C_DEBUG > 2
		pushad
		call	am79c_print_rx_desc
		popad
	.endif

	mov	ecx, 100	# infinite loop bound

	# check what interrupts
0:
	AM79C_READ_CSR CSR0

	.if AM79C_DEBUG
		push	eax
		and	eax, 0xff00	# hi byte=int flags, lo byte = status
		# might want jz here.
		call	am79c_print_csr0_
		pop	eax
	.endif

	# clear the interrupt bits
	push	eax
	and	eax, (AM79C_CSR0_IENA|AM79C_CSR0_TINT|AM79C_CSR0_RINT| AM79C_CSR0_MERR|AM79C_CSR0_MISS|AM79C_CSR0_CERR|AM79C_CSR0_BABL|AM79C_CSR0_IDON)
	AM79C_WRITE_CSR CSR0, eax
	pop	eax

	##########################

	.if 0
	test	eax, AM79C_CSR0_IDON
	jz	1f
	println "IDON: "
1:
	.endif

	test	eax, AM79C_CSR0_RINT
	jz	1f

	.if AM79C_DEBUG
		DEBUG "rx"
	.endif

	push	ecx
	push	ebx
	push	eax

3:
	mov	eax, [ebx + nic_rx_desc_h]

	.if AM79C_DEBUG > 2
		print " idx "
		mov	edx, eax
		call	printdec32
	.endif

	mov	esi, [ebx + nic_rx_desc]
	shl	eax, (DESC_BITS / 16) + 2	# 16: * 8; 32: * 16
	add	eax, esi


	.if SWSTYLE == 0
	#...
	.elseif SWSTYLE == 2
	.if AM79C_DEBUG > 2
		mov	edx, [eax + 4]	# flags, BCNT
		neg	edx
		and	edx, 0x0fff
		print " buf len "
		call	printdec32
		mov	edx, [eax + 4]
		shr	edx, 20
		print " flags "
		call	printbin16
	.endif

	mov	edx, [eax +4]
	test	edx, RDF_OWN
	jnz	2f

	mov	esi, [eax + 12]	# userspace: logical buffer address
	mov	ecx, [eax + 8]	# rfrtag, packet size
	and	ecx, 0x0fff

	.if AM79C_DEBUG > 2
		mov	edx, ecx
		print " packet size "
		call	printdec32
		call newline
	.endif
	.endif

	inc	dword ptr [ebx + nic_rx_desc_h]
	and	dword ptr [ebx + nic_rx_desc_h], (1<<LOG2_RX_BUFFERS)-1

	push	eax
	call	net_rx_packet	# esi, ecx -> esi
	pop	eax
	.if SWSTYLE == 2
	mov	[eax + 12], esi	# update packet buffer
	push	edx
	GDT_GET_BASE edx, ds
	add	edx, esi
	mov	[eax + 0], edx	# physical buffer address
	pop	edx
	.else
	.endif
	mov	[eax + 4 + 2], word ptr 0x8000  # flags = OWN
#	mov	[eax + 8], dword ptr 0 # clear packet size

	jmp	3b	# check if more packets

2:	pop	eax
	pop	ebx
	pop	ecx
1:
	############################
	test	eax, AM79C_CSR0_TINT
	jz	1f

	.if AM79C_DEBUG
		DEBUG "tx"
#		call	newline
#		pushad
#		call	am79c_print_tx_desc
#		popad
	.endif
1:

	##########################

	#loop	0b
	dec ecx
	jnz 0b
0:

	.if AM79C_DEBUG
		call	newline
	.endif
########################################################################
	# EOI is handled by IRQ_SHARING code
	pop	es
	pop	ds
	popad	# edx ebx eax
	iret

############################################################
# Send Packet

# in: ebx = nic device
# in: esi = packet
# in: ecx = packet size
am79c971_send:
	pushad
	incd	[ebx + nic_tx_count]
	add	[ebx + nic_tx_bytes + 0], ecx
	adcd	[ebx + nic_tx_bytes + 4], 0

	.if AM79C_DEBUG > 1
		DEBUG "am79c_send"
		DEBUG_DWORD ecx
	.endif

	mov	edx, [ebx + nic_tx_desc_h]
	mov	eax, edx
	inc	edx
	and	edx, (1<<LOG2_TX_BUFFERS) -1
	mov	[ebx + nic_tx_desc_h], edx

	shl	eax, (DESC_BITS / 16) + 2
	add	eax, [ebx + nic_tx_desc]
	# set size
	push	ecx
	and	cx, 0x0fff
	neg	cx
	mov	[eax + 4], cx
	pop	ecx
#swstyle 2
# 0x00: TBADR[31:0]
# 0x04: OWN|ERR|ADD_FCS|MORE/LTINT|ONE|DEF|STP|ENP|BPE|res|1111|BCNT[11:0]
# 0x08: BUFF|UFLO|EXDEC|LCOL|LCAR|RTRY|res[25:4]|TRC[3:0] # TRC=tx retrt cnt
# 0x0c: user space[31:0]
	.if 0 # use the given buffer
		GDT_GET_BASE edx, ds
		add	esi, edx
		mov	[eax + 0], esi
	.else # copy data in preallocated buffer
		mov	edi, [eax + 12]
		rep	movsb
	.endif


	.if AM79C_DEBUG > 1
		pushad
		DEBUG "Prepared TX DESC:"
		call	newline
		call	am79c_print_tx_desc
		popad
	.endif

	.if SWSTYLE == 2
	or	[eax + 4], dword ptr TDF_OWN
	.endif

	AM79C_READ_CSR CSR0
	or	eax, AM79C_CSR0_TDMD
	AM79C_WRITE_CSR CSR0, eax

	popad
	ret


# in: ebx = nic object
am79c971_print_status:
	call	am79c_print_csr0
	call	am79c_print_csr3
	call	am79c_print_csr4
	.if AM79C_DEBUG
		AM79C_READ_CSR CSR_MODE
		DEBUG_DWORD eax,"CSR15(MODE=0x80?)"
	.endif
	ret


############################################################################

am79c_print_csr0:
	PRINT "CSR0: "
	AM79C_READ_CSR CSR0
	mov	dx, ax
	call	printbin16
	call	printspace
	call	am79c_print_csr0_
	call	newline
	ret
am79c_print_csr0_:
	LOAD_TXT "ERR\0BABL\0CERR\0MISS\0MERR\0RINT\0TINT\0IDON\0INTR\0IENA\0RXON\0TXON\0TDMD\0STOP\0STRT\0INIT\0"
	mov	dx, ax
	call	print_flags16
	ret


am79c_print_iadr:	# csr1 and csr2
	print "IADR: "
	AM79C_READ_CSR CSR2
	mov	dx, ax
	call	printhex4
	AM79C_READ_CSR CSR1
	mov	dx, ax
	call	printhex4
	call	newline
	ret

am79c_print_csr3:
	PRINT "CSR3: "
	AM79C_READ_CSR CSR3
	LOAD_TXT "RESV\0BABLM\0RESV\0MISSM\0MERRM\0RINTM\0TINTM\0IDONM\0RESV\0DXSUFLO\0LAPPEN\0DXMT2PD\0EMBA\0BSWP\0RESV\0RESV\0"
	mov	dx, ax
	call	printbin16
	call	printspace
	call	print_flags16
	call	newline
	ret

am79c_print_csr4:
	PRINT "CSR4: "
	AM79C_READ_CSR CSR4
	LOAD_TXT "EN124\0DMAPLUS\0RESV\0TXDPOLL\0APAD_XMT\0ASTRP_RCV\0MFCO\0MFCOM\0UINTCMD\0UINT\0RCVCCO\0RCVCCOM\0TXSTRT\0TXSTRTM\0JAB\0JABM\0"
	mov	dx, ax
	call	printbin16
	call	printspace
	call	print_flags16
	call	newline
	ret

am79c_print_iobits:
	AM79C_READ_BCR 18
	mov	edx, 16
	test	eax, 1 << 7
	jz	0f
	shl	dl, 1
	0:	print	"IO mode: "
	call	printdec32
	println " bits"
	ret


# This can only be run when in STOP mode.
# Also, it reads the (XMT|RCV)R(L|C) registers, of which only RCVRL (reg 76)
# exists in VMWare's VLANCE driver.
am79c_print_ring_info:
	print "RX Desc Addr: "
	mov	edx, [ebx + nic_rx_desc]
	call	printhex8
	call	printspace
	AM79C_READ_CSR CSR_BADRH
	mov	cx, ax
	shl	ecx, 16
	AM79C_READ_CSR CSR_BADRL
	mov	cx, ax
	mov	edx, ecx
	call	printhex8
	print " ringsize "
	AM79C_READ_CSR CSR_RCVRL
	mov	edx, eax
	call	printdec32
# not supported in VMWare:
	print " index "
	AM79C_READ_CSR CSR_RCVRC
	mov	edx, eax
	call	printdec32
	call	newline

	print "TX Desc Addr: "
	mov	edx, [ebx + nic_tx_desc]
	call	printhex8
	call	printspace
	AM79C_READ_CSR CSR_BADXH
	mov	cx, ax
	shl	ecx, 16
	AM79C_READ_CSR CSR_BADXL
	mov	cx, ax
	mov	edx, ecx
	call	printhex8
# not supported in VMWare:
	print " ringsize "
	AM79C_READ_CSR CSR_XMTRL
	mov	edx, eax
	call	printdec32
# not supported in VMWare:
	print " index "
	AM79C_READ_CSR CSR_XMTRC
	mov	edx, eax
	call	printdec32
	call	newline
	ret

am79c_dumpregs:
	xor	ecx, ecx

0:	mov	eax, ecx

	call	am79c_printregs
	call	newline
	inc	ecx
	cmp	ecx, 2
	jbe	0b
	ret



# in: [ebp] = io port
# in: eax = register offset (x for CSRx/BCRx)
am79c_printregs:
	push	ecx
	mov	ecx, eax

	mov	dx, [ebp]
	add	dx, AM79C_RAP # 0x14
	out	dx, eax

	mov	dx, [ebp]
	add	dx, AM79C_RDP # 0x10	# RDP / CSR
	in	eax, dx
	print "CSR"
	mov	edx, ecx
	call	printdec32
	print ": "
	mov	edx, eax
	call	printhex8

	mov	dx, [ebp]
	add	dx, AM79C_BDP # 0x1c	# BDP / BCR
	in	eax, dx
	print " BCR"
	mov	edx, ecx
	call	printdec32
	print ": "
	mov	edx, eax
	call	printhex8

	pop	ecx
	ret


############################################################################

DRIVER_NIC_AM79C_SIZE =  . - DRIVER_NIC_AM79C_BEGIN
