##############################################################################
# Intel 8254x PCI/PCI-X Gigabit Ethernet Controller Driver
#
.intel_syntax noprefix
.code32
############################################################################
I8254_DEBUG = 0
############################################################################

I8254_IO_ADDR	= 0
I8254_IO_DATA	= 4

############################################################################
I8254_CTRL	= 0x0000	# Device Control Register
	CTRL_FD		= 1 << 0	# Full Duplex
			# 2:1 reserved
	CTRL_LRST	= 1 << 3	# Link Reset
					# (N/a 82540EP/EM,81541xx/82547Gi/EI
			# 4 reserved
	CTRL_ASDE	= 1 << 5	# Auto Speed Detection Enable
	CTRL_SLU	= 1 << 6	# Set Link Up
	CTRL_ILOS	= 1 << 7	# Invert Loss Of Lignal
					# (82541xx/82547GI/EI)
	CTRL_SPEED	= 3 << 8	# Speed Selection: 10^(Speed)Mbps,11=NA
			# 10 reserved
	CTRL_FRCSPD	= 1 << 11	# Force Speed
	CTRL_FRCDPLX	= 1 << 12	# Force Duplex
			# 17:13 reserved
	CTRL_SDP0_DATA	= 1 << 18	# read/write software ctrlable IO pin
	CTRL_SDP1_DATA	= 1 << 19	# idem. When SPD?_IODIR = 1, read.
	CTRL_ADVD3WUC	= 1 << 20	# D2Cold Wakeup Cap Advertisement enab
	CTRL_EN_PHY_PWR_MGTMT = 1 << 21	# PHY power management enable
	CTRL_SPD0_IODIR	= 1 << 22	# io pin directionality - in/out (r/w)
	CTRL_SPD1_IODIR	= 1 << 23	# io pin directionality - in/out (r/w)
			# 25:24 reserved
	CTRL_RST	= 1 << 26	# Device Reset
	CTRL_RFCE	= 1 << 27	# Receive Flow Control enable
	CTRL_TFCE	= 1 << 28	# Transmit Flow Control enable(XON/XOFF)
			# 29 reserved
	CTRL_VME	= 1 << 30	# VLAN mode enable
	CTRL_PHY_RST	= 1 << 31	# PHY reset (set,wait 3musec/10ms,clear)

I8254_STATUS	= 0x0008	# Device Status Register
	STATUS_FD	= 1 << 0	# Link Full Duplex configuration indic.
	STATUS_LU	= 1 << 1	# Link Up indication
	STATUS_FID	= 3 << 2	# Function Id: 00=Lan A, 01=Lan B.
					# 82546GB/EB only.
	STATUS_TXOFF	= 1 << 4	# Transmission Paused (f dupl flow ctl)
	STATUS_TBIMODE	= 1 << 5	# TBI mode/internal SerDes indication.
					# When 0, works in internal PHY mode.
	STATUS_SPEED	= 3 << 6	# Link Speed Setting (when tbimode=0).
					# 00=10Mbps,01=100Mbps,10=11=1Gbps
	STATUS_ASDV	= 3 << 8	# Auto-Speed detection value (PHY)
					# write CTRL_EXT.ASDCHK, then read.
			# 10 reserved
	STATUS_PCI66	= 1 << 11	# PCI bus speed indication.
	STATUS_BUS64	= 1 << 12	# PCI Bus width indication
	STATUS_PCIX_MODE= 1 << 13	# PCI-X mode indication.
	STATUS_PCIXSPD	= 3 << 14	# PCI-X bus speed indication:
					# 00=50-66Mhz 01=66-100Mhz 10=100-133Mhz
					# 11 = reserved
			# 31:16 reserved.

I8254_EECD	= 0x0010	# EEPROM/Flash control & data register (13.4.3)
I8254_EERD	= 0x0014	# EEPROM Read register
I8254_FLA	= 0x001c	# Flash Access

I8254_CTRL_EXT	= 0x0018	# Extended Device Control Register
			# 1:0 reserved for 82541xx and 82547GI/EI
	CTRL_EXT_GPI_EN	= 0b1111 << 0	# General Purpose Interrupt Enables
			# 4 reserved
	CTRL_EXT_PHYINT	= 1 << 5	# PHY Interrupt value (..41xx,..47GI/EI)
	CTRL_EXT_SDP6_DATA= 1 << 6	# Software controllable IO Pin 6 data
	CTRL_EXT_SDP7_DATA= 1 << 7	# idem; 6,7 = 2,3 for ..41xx/..47GI/EI)
			# 9:8 reserved write as 01
	CTRL_EXT_SPD6_IODIR= 1 << 10
	CTRL_EXT_SDP7_IODIR= 1 << 11
	CTRL_EXT_ASDCHK	= 1 << 12	# Auto-Speed-Dection initiation
	CTRL_EXT_EE_RST	= 1 << 13	# EEPROM reset
			# 14 reserved
	CTRL_EXT_SPD_BYPS= 1 << 15	# Speed Select Bypass (force CTRL.SPEED)
			# 16 reserved
	CTRL_EXT_RO_DIS	= 1 << 17	# Relaxed Ordering disabled (PCI-X)
			# 20:18 reserved
	CTRL_EXT_VREG_POWER_DOWN = 1 << 21# Voltage Regulator Power Down
					# (..41xx/..47GI/EI only)
	CTRL_EXT_LINK_MODE = 3 << 22	# Link Mode:
					# 00 = direct copper (1000Base-T, PHY)
					# 01 = resrved
					# 10 = Direct Fiber Interface (SerDes)
					# 11 = external TBI interface.
					# ..40EP/EM, ..41xx, ..47GI/EI only.
			# 31:24 reserved.
	


# Interrupt registers
I8254_ICR	= 0x00c0	# Interrupt Cause Read
I8254_ITR	= 0x00c4	# Interrupt Throttling: minimum inter-irq 
				# interval. 16 bits * 256ns ; 0 = disable.
I8254_ICS	= 0x00c8	# Interrupt Cause Set (triggers IRQ,writes ICR)
I8254_IMS	= 0x00d0	# Interrupt Mask Set
I8254_IMC	= 0x00d8	# Interrupt mask clear
				# writing 1 clear the IR; writing 0 in IMS
				# has no effect.

	IR_RXDW		= 1 << 0	# transmit descriptor written back
	IR_TXQE		= 1 << 1	# transmit queue empty
	IR_LSC		= 1 << 2	# Link status change
	IR_RXSEQ	= 1 << 3	# receive sequence error
/*Rx*/	IR_RXDMT	= 1 << 4	# receive desc min thresh reached
			# 1 << 5 reserved
/*Rx*/	IR_RXO		= 1 << 6	# receiver fifo overrun
/*Rx*/	IR_RXT		= 1 << 7	# receiver timer interrupt
			# 1 << 8 reserved
	IR_MDAC		= 1 << 9	# MDI/O access complete
	IR_RXCFG	= 1 << 10	# receiving /C/ ordered sets: auto negt
			# 1 << 11 reserved; for 85244GC/EI: 14:11 = GPI
	IR_PHYINT	= 1 << 12	# 82541xx/82547GI/EI; N/A for 82544GC/EI
	IR_GPI		= 3 << 13	# general purpose
	IR_TXD_LOW	= 1 << 15
/*Rx*/	IR_SRPD		= 1 << 16	# small receive packet detection
			# 32:17 reserved

I8254_RSRPD	= 0x2c00	# Receive Small Packet Detect Interrupt
				# 12 bits min packet size; rest reserved.

I8254_RCTL	= 0x0100	# Receive Control
			# 1 << 0 reserved
	RCTL_EN		= 1 << 1	# receiver enable
	RCTL_SBP	= 1 << 2	# Store bad packets
	RCTL_UPE	= 1 << 3	# unicast promisc enabled
	RCTL_MPE	= 1 << 4	# multicast promisc enabled
	RCTL_LPE	= 1 << 5	# long packet receive enable
	RCTL_LBM	= 3 << 6	# loopback mode
	RCTL_RDMTS	= 3 << 8	# receive descr min thresh
					# 00=1/2, 01=1/4, 10=1/8 RDLEN
			# 3 << 10 reserved
	RCTL_MO		= 3 << 12	# multicast offset
			# 1 << 14 reserved
	RCTL_BAM	= 1 << 15	# broadcast accept
	RCTL_BSIZE	= 3 << 16	# receive buffer size
					# RTCL_BSEX = 0: size=2048>>BSIZE
					# RCTL_BSEX = 1: size=32k>>BSIZE
					#  where BSIZE=00 is prohibited
	RCTL_VFE	= 1 << 18	# VLAN filter enable, see next 2
	RCTL_CFIEN	= 1 << 19	# canonical form indicator enable
	RCTL_CFI	= 1 << 20	# canonical form indicator value
			# 1 << 21 reserved
	RCTL_DPF	= 1 << 22	# discard pause frames
	RCTL_PMCF	= 1 << 23	# pass mac control frames
			# 1 << 24 reserved
	RCTL_BSEX	= 1 << 25	# buffer size extension: 16 * BSIZE
	RCTL_SECRC	= 1 << 26	# strip ethernet crc from incoming pkt
			# 0b11111 <<27 reserved


I8254_TCTL	= 0x0400	# Transmit Control Register
	TCTL_MASK_CNTL	= 0b1111 << 22
	TCTL_MASK_CNTL2	= 0b1111

	TCTL_EN		= 1 << 1	# Transmit Enable
			# 1 << 2 reserved
	TCTL_PSP	= 1 << 3	# Pad Short Packets (up to 64 bytes)
	TCTL_MASK_CT	= 0b11111111 << 4 # Collision Threshold: nr of retries
	TCTL_MASK_COLD	= 0b1111111111 << 12 # collision distance.
				# recommended: half-duplex 0x200, full: 0x40
	TCTL_SWXOFF	= 1 << 22	# software XOFF transmission (pause)
			# 1 << 23 reserved
	TCTL_RTLC	= 1 << 24	# Re-transmit on late collision
	TCTL_NRTU	= 1 << 25	# no-retransmit on underrun/reserved
			# 31:26 reserved

I8254_TIPG	= 0x0410	# Transmit Inter-Packet-Gap timer: 3x 10 bits
	TIPG_IPGT	= 0b1111111111 << 0	# IPG transmit time
	TIPG_IPGR1	= 0b1111111111 << 10	# IPG receive time 1
						# (non-back-to-back Tx)
	TIPG_IPGR2	= 0b1111111111 << 20	# IPG receive time 2 (b2b Tx)
				# IEEE802.3: IPGR1 = 2/3 * IPGR2
			# 31:30 reserved


I8254_PBA	= 0x1000	# Packet Buffer Allocation: TXA <<16 | RXA
				# Configures the on-chip RX/TX buffer ratio.
				# RXA 7 bits: default = 48kb 
				# TXA 7 bits: calculated: 64 - RXA


I8254_RDBAL	= 0x2800	# Receive Descriptor Base Address Low
				# must be 16-byte aligned (low 4 bits ignored)
I8254_RDBAH	= 0x2804	# Receive Descriptor Base Address High
I8254_RDLEN	= 0x2808	# Receive Descriptor Length (multiple of 128
				# bytes, low 7 bits ignored; each descriptor
				# is 16 bytes: 128/16 = multiple of 8 descr.
I8254_RDH	= 0x2810	# Receive Descriptor Head; bits 31:16 reserved
I8254_RDT	= 0x2818	# Receive Descriptor Tail; bits 31:16 reserved
# Intel advises against using RDTR and RADV in favour of ITR.
I8254_RDTR	= 0x2820	# Receive Interrupt Delay Timer
	RDTR_DELAY	= (1<<16)-1	# 16 bits * 1.024 microsec
					# set to 0: disable RDTR and RADV
			# 30:16 reserved
	RDTR_FPD	= 1 << 31	# flush partial descriptor block
					# reads as 0b (self-clearing)
I8254_RADV	= 0x282c	# Receive Interrupt Absolute Delay timer
				# 16 bit delay timer * 1.024 microsec
				# 31:16 reserved.


I8254_TDBAL	= 0x3800	# Transmit Descriptor Base Address low
I8254_TDBAH	= 0x3804	# Transmit Descriptor Base Address high
I8254_TDLEN	= 0x3808	# Transmit Descriptor len
I8254_TDH	= 0x3810	# Transmit Descriptor Head
I8254_TDT	= 0x3818	# Transmit Descriptor Tail
I8254_TIDV	= 0x3820	# Transmit Interrupt Delay Value (0 not allowed)
	
I8254_TXDCTL	= 0x3828	# Transmit Descriptor Control
	TXDCTL_PTHRESH	= 0b111111	# prefetch threshold
	TXDCTL_HTHRESH	= 0b111111 << 8	# host threshold
	TXDCTL_WTHRESH	= 0b111111 << 16# write back thresh
	TXDCTL_GRAN	= 1 << 24	# 1=txd gran:16b;0=cache line gran:512b
	TXDCTL_LWTHRES	= 0b1111111 << 25# txd low threshold


# 16 registers, 8 dword pairs, each 64 bit pair contains 48 bit MAC address.
# The 2nd pair starts at 5408.
#
I8254_RAL	= 0x5400	# Receive Address Low - MAC address
I8254_RAH	= 0x5404	# Receive Address High - MAC address
		RAH_AS	= 1 << 16	# address filter select: 0=dst,1=src
		RAH_AV	= 1 << 31	# address valid

I8254_MTA	= 0x5200	# ..0x53FC Multicast Table Array
				# overflow for RAL/RAH, 'imperfect filter'.
				# see page 327. 'mac firewall'.



#############################################

# Receive Descriptor Format
.struct 0
rdesc_addr:	.long 0, 0	# 8 bytes, 64 bit addr
rdesc_len:	.word 0
rdesc_checksum:	.word 0
rdesc_status:	.byte 0
	RDESC_STATUS_PIF	= 1 << 7	# passed inexact filter
	RDESC_STATUS_IPCS	= 1 << 6	# ip checksum calculated
	RDESC_STATUS_TCPCS	= 1 << 5	# tcp checksum calculated
	RDESC_STATUS_RSV	= 1 << 4	# reserved
	RDESC_STATUS_VP		= 1 << 3	# 802.1Q (VLAN) packet (VET)
	RDESC_STATUS_IXSM	= 1 << 2	# ignore checksum indication
	RDESC_STATUS_EOP	= 1 << 1	# end of packet
	RDESC_STATUS_DD		= 1 << 0	# descriptor done
rdesc_errors:	.byte 0
	RDESC_ERROR_RXE		= 1 << 7	# RX data error
	RDESC_ERROR_IPE		= 1 << 6	# IP checksum error
	RDESC_ERROR_TCPE	= 1 << 5	# TCP/UDP checksum error
	RDESC_ERROR_RSV_CXE	= 1 << 4	# Carrier Extension error
	RDESC_ERROR_RSV		= 1 << 3	# reserved
	RDESC_ERROR_SE_QRSV	= 1 << 2	# sequence error/framing err.
	RDESC_ERROR_SE_SRV	= 1 << 1	# symbol error
	RDESC_ERROR_CE		= 1 << 0	# CRC or Alignment error
rdesc_special:	.word 0
	# for 802.1q (VLAN) packets:
	RDESC_SPECIAL_VLAN	= (1<<12)-1	# vlan identifier
	RDESC_SPECIAL_CFI	= 3 << 12	# canonical form indicator
	RDESC_SPECIAL_PRI	= 3 << 13	# user priority
	# for other pakcets: zero.

.struct 0	# legacy format
tdesc_addr:	.long 0, 0
tdesc_len:	.word 0	# max 16288; min len for packet 48 bytes (ex crc)
tdesc_cso:	.byte 0	# checksum offset (cmd.IC)
tdesc_cmd:	.byte 0 # command field
	TDESC_CMD_IDE	= 1 << 7	# interrupt delay enable
	TDESC_CMD_VLE	= 1 << 6	# vlan packet enable
	TDESC_CMD_DEXT	= 1 << 5	# 1 = extension 0 = legacy
	TDESC_CMD_RPS	= 1 << 4	# report packet sent (status.DD)
					# 82544GC/EI only
	TDESC_CMD_RS	= 1 << 3	# report status (status.DD)
	TDESC_CMD_IC	= 1 << 2	# insert checksum, only when EOP set
	TDESC_CMD_IFCS	= 1 << 1	# insert FCS/CRC; only when EOP
	TDESC_CMD_EOP	= 1 << 0	# End Of Packet - last descr for pkt
tdesc_status:	.byte 0	# high 4 bits reserved
	TDESC_STATUS_TU	= 1 << 3	# transmit underrun
	TDESC_STATUS_LC	= 1 << 2	# late collision in half-duplex
	TDESC_STATUS_EC	= 1 << 1	# excess collisions in half duplex
	TDESC_STATUS_DD	= 1 << 0	# descriptor done - set when cmd.RS set
tdesc_css:	.byte 0	# checksm start
tdesc_special:	.word 0
#############################################


	.macro I8254_WRITE addr, value=eax
		push	eax
		mov	eax, I8254_\addr
		out	dx, eax
		pop	eax
		add	dx, 4
		.if \value != eax
		mov	eax, \value
		.endif
		out	dx, eax
		sub	dx, 4
	.endm

	.macro I8254_READ addr
		mov	eax, I8254_\addr
		out	dx, eax
		add	dx, 4
		in	eax, dx
		sub	dx, 4
	.endm

############################################################################
DECLARE_CLASS_BEGIN nic_i8254, nic
nic_i8254_buf:		.long 0	# the malloced buffer
nic_i8254_rd_buf:	.long 0	# receive descriptor
nic_i8254_td_buf:	.long 0 # transmit descriptor
nic_i8254_rx_buf:	.long 0
nic_i8254_tx_buf:	.long 0
nic_i8254_rd_tail:	.long 0	# 
nic_i8254_td_tail:	.long 0	# 
DECLARE_CLASS_METHOD dev_api_constructor, i8254_init, OVERRIDE
DECLARE_CLASS_METHOD dev_api_isr,	  i8254_isr, OVERRIDE
DECLARE_CLASS_END nic_i8254

DECLARE_PCI_DRIVER NIC_ETH, nic_i8254, 0x8086, 0x100e, "i8254x", "Intel 8254x PCI/PCI-X"
############################################################################


.text32
# in: ebx = pci nic object
i8254_init:
	LOAD_TXT "i8254", (dword ptr [ebx + dev_drivername_short])

	mov	dword ptr [ebx + nic_api_send], offset i8254_send
	mov	dword ptr [ebx + nic_api_print_status], offset i8254_print_status
	mov	dword ptr [ebx + nic_api_ifup], offset i8254_ifup
	mov	dword ptr [ebx + nic_api_ifdown], offset i8254_ifdown

	# hook the isr
	call	dev_add_irq_handler

	# allocate buffers
	# allocate and configure descriptor reception buffer
	_RD_NUM = 8
	_TD_NUM = 8
	_RX_BUFSIZE = 2048
	_TX_BUFSIZE = 2048
	_TOTSIZE = _RD_NUM * (16 + _RX_BUFSIZE) + _TD_NUM * (16 + _TX_BUFSIZE)
	mov	eax, 16 + _TOTSIZE
	call	malloc
	jc	9f
	mov	[ebx + nic_i8254_buf], eax	# for mfree
	and	al, 0xf0	# 16 byte align

	# layout of the buffer:
	# _RD_NUM times 16 bytes for the receive descriptors
	# _TD_NUM times 16 bytes for the transmit descriptors
	# _RD_NUM times _RX_BUFSIZE for the receive buffers
	# _TD_NUM times _TX_BUFSIZE for the transmit buffers
	mov	[ebx + nic_i8254_rd_buf], eax
	add	eax, _RD_NUM * 16
	mov	[ebx + nic_i8254_td_buf], eax
	add	eax, _TD_NUM * 16
	mov	[ebx + nic_i8254_rx_buf], eax
	add	eax, _RD_NUM * _RX_BUFSIZE
	mov	[ebx + nic_i8254_tx_buf], eax
	add	eax, _TD_NUM * _TX_BUFSIZE

	## store pointers in receive descriptor ring
	mov	ecx, _RD_NUM
	mov	esi, [ebx + nic_i8254_rd_buf]
	GDT_GET_BASE eax, ds
	add	eax, [ebx + nic_i8254_rx_buf]
0:	mov	[esi + rdesc_addr + 0], eax
	mov	[esi + rdesc_addr + 4], dword ptr 0
	mov	[esi + rdesc_len], word ptr 0 # _RX_BUFSIZE
	mov	[esi + rdesc_status], byte ptr 0
	mov	[esi + rdesc_errors], byte ptr 0
	mov	[esi + rdesc_special], word ptr 0
	add	eax, _RX_BUFSIZE
	add	esi, 16
	loop	0b

	mov	ecx, _TD_NUM * 16 / 4
	mov	edi, [ebx + nic_i8254_td_buf]
	xor	eax, eax
#	rep	stosd


	#######################################################
	# Rx Setup
	#
	# section 14.4 from developer manual: Receive Initialisation

	mov	dx, [ebx + dev_io]

	## configure RAL/RAH

	# read mac
	I8254_READ RAL
	mov	[ebx + nic_mac], eax
	I8254_READ RAH
	mov	[ebx + nic_mac + 4 ], ax

	## initialize MTA to 0b
	mov	ecx, 128
0:	mov	eax, 128
	sub	eax, ecx
	shl	eax, 2
	add	eax, I8254_MTA
	out	dx, eax
	add	dx, 4
	xor	eax, eax
	out	dx, ax
	sub	dx, 4
	loop	0b

	# disable receive interrupt delay timers
	I8254_WRITE RDTR, 0

	## program IMS - interrupt mask set/read: RXT, RXO, RXDMT, RXSEQ, LSC
	I8254_WRITE IMC, -1	# clear all interrupts
	I8254_WRITE IMS, (IR_RXDW | IR_RXT | IR_RXO | IR_RXDMT | IR_RXSEQ | IR_LSC)

	## receive descriptor circular buffer base
	I8254_WRITE RDBAH, 0
	GDT_GET_BASE eax, ds
	add	eax, [ebx + nic_i8254_rd_buf]
	I8254_WRITE RDBAL, eax
	# do not write RDBAH in 32 bit mode
	## configure the descriptor length buffer.
	I8254_WRITE RDLEN, (_RD_NUM * 16)	# must be multiple of 128

	# initialize the receive-descriptor head (p 27 and 376)
	I8254_WRITE RDH, 0
	I8254_WRITE RDT, (_RD_NUM -1) 	# should be within ring. 
	mov	[ebx + nic_i8254_rd_tail], dword ptr 0

	## program RCTL
	_RCTL_RECEPTION = RCTL_EN | RCTL_UPE | RCTL_MPE | RCTL_BAM   | RCTL_SBP | RCTL_SECRC | RCTL_LPE 
	_RCTL_BUFSIZE = RCTL_BSEX | ( 2 << 16 )	# 32>>2 = 8kb
	I8254_WRITE RCTL, (_RCTL_RECEPTION | _RCTL_BUFSIZE)


	# disable flow control
	#I8254_WRITE FCAL, 0
	#I8254_WRITE FCAH, 0
	#I8254_WRITE FCT, 0
	#I8254_WRITE FCTTV, 0

	# trigger interrupt
	#DEBUG "Trigger int"
	#I8254_WRITE ICS, IR_RXT


	#######################################################
	# Tx Setup

	## transmit descriptor circular buffer
	I8254_WRITE TDBAH, 0
	GDT_GET_BASE eax, ds
	add	eax, [ebx + nic_i8254_td_buf]
	I8254_WRITE TDBAL, eax
	I8254_WRITE TDLEN, (_TD_NUM * 16)

	# set up transmit descriptor head BEFORE TCTL_EN!
	I8254_WRITE TDH, 0
	I8254_WRITE TDT, 0 # (_TD_NUM -1)
	mov	[ebx + nic_i8254_td_tail], dword ptr 0

	I8254_WRITE TCTL, (TCTL_EN | TCTL_PSP | (0x10<<4) | (0x40<<12))
#	I8254_WRITE TIPG, (( 10 << 0 ) | (10 << 10 ) | (10<<20))

	I8254_WRITE TXDCTL, TXDCTL_GRAN | (1<<8) | (1<<16) | (1<<24)
	I8254_WRITE TIDV, 1
	call	i8254_print_status

9:	ret


i8254_isr:
	pushad

	.if I8254_DEBUG
		DEBUG "ISR"
	.endif

	mov	ebx, edx
	mov	dx, [ebx + dev_io]
	I8254_READ ICR

	.if I8254_DEBUG
		DEBUG "ICR"
		DEBUG_DWORD eax
		PRINTFLAG eax, IR_SRPD, "SRPD"	# bit 16 (17th bit)
		LOAD_TXT "TXD_LOW\0GPI1\0GPI0\0PHYINT\0?11\0RXCFG\0MDAC\0?8\0RXT\0RXO\0?5\0RXDMT\0RXSEQ\0LSC\0TXQE\0RXDW"
		push	eax
		call	print_flags16
		pop	eax
	.endif

	push	eax	# remember ICR
	I8254_READ RDH
	mov	esi, eax
	I8254_READ RDT
	mov	edi, eax
	pop	eax

	.if I8254_DEBUG
		DEBUG "RDH"
		DEBUG_WORD si
		DEBUG "RDT"
		DEBUG_WORD di
	.endif


######## Link Status Change
	test	eax, IR_LSC
	jnz	0f
	push	eax
	I8254_READ CTRL
	or	eax, CTRL_SLU	# Set Link Up
	I8254_WRITE CTRL
	pop	eax
	and	eax, ~IR_LSC
0:
######## Rx Packet
	test	eax, IR_RXT
	jz	0f
	and	eax, ~IR_RXT
	# receive packet

	# esi = head, edi = tail
	dec	esi
	jns	2f
	add	esi, _RD_NUM
###
2:	inc	edi
	cmp	edi, _RD_NUM
	jb	1f
	sub	edi, _RD_NUM
1: 

	.if I8254_DEBUG
		call	newline
		call	printspace
		call	printspace
	.endif

		pushad
		shl	edi, 4
		add	edi, [ebx + nic_i8254_rd_buf]

		mov	esi, [edi + rdesc_addr]
		GDT_GET_BASE eax, ds
		sub	esi, eax

		movzx	ecx, word ptr [edi + rdesc_len]

		xor	dx, dx
		xchg	dx, [edi + rdesc_status]

		mov	dx, [edi + rdesc_errors]

		push_	edi eax
		call	net_rx_packet
		pop_	eax edi

		add	esi, eax	# relocation
		mov	[edi + rdesc_addr], esi	# replace packet buffer
		popad

	cmp	edi, esi
	jb	2b
###
	mov	dx, [ebx + dev_io]
	mov	eax, edi
	I8254_WRITE RDT, eax

	.if I8254_DEBUG
		DEBUG "RDT"
		DEBUG_WORD ax
	.endif
0:
########
	.if I8254_DEBUG
		call	newline
	.endif

	# EOI handled by IRQ_SHARING
	popad
	iret


# in: ebx
# in: esi
# in: ecx
i8254_send:
	pushad
	incd	[ebx + nic_tx_count]
	add	[ebx + nic_tx_bytes + 0], ecx
	adcd	[ebx + nic_tx_bytes + 4], 0

	mov	dx, [ebx + dev_io]
I8254_READ TDH
DEBUG "TDH:"
DEBUG_WORD ax
	I8254_READ TDT
DEBUG "TDT: "
DEBUG_WORD ax
	inc	eax
	cmp	eax, _TD_NUM
	jb	1f
	sub	eax, _TD_NUM
1:
	mov	edi, eax
	shl	edi, 4
	add	edi, [ebx + nic_i8254_td_buf]

	# fill in tx buf
	GDT_GET_BASE edx, ds
	add	esi, edx
	mov	[edi + tdesc_addr], esi
	mov	[edi + tdesc_addr + 4], dword ptr 0
	mov	[edi + tdesc_len], cx
	.if I8254_DEBUG
		DEBUG "Tx"
		DEBUG_WORD cx
	.endif
	mov	[edi + tdesc_cso], byte ptr 0
	mov	[edi + tdesc_cmd], byte ptr TDESC_CMD_EOP | TDESC_CMD_RPS
	mov	[edi + tdesc_status], dword ptr 0 # status, css, special

	mov	dx, [ebx + dev_io]
push	eax
I8254_READ TDH
DEBUG "TDH:"
DEBUG_WORD ax
pop	eax
DEBUG "TDT: "
DEBUG_WORD ax
call newline
	I8254_WRITE TDT

	popad
	ret


i8254_print_status:
	push	edx
	push	eax
DEBUG_DWORD ecx
DEBUG_DWORD ebx
	mov	dx, [ebx + dev_io]
DEBUG_WORD dx
	
mov esi, [ebx + nic_i8254_rd_buf]
mov eax, [esi + rdesc_addr]
DEBUG_DWORD esi
DEBUG_DWORD eax

	printc	15, "CTRL: "
	I8254_READ CTRL
	push	edx
	mov	edx, eax
	call	printhex8
	call	printspace
	pop	edx

	printc	15, "STATUS: "
	I8254_READ STATUS
	push	edx
	mov	edx, eax
	call	printhex8
	call	printspace
	PRINTFLAG eax, STATUS_LU, "Link-Up", "Link-Down"
	PRINTFLAG eax, STATUS_FD, "Full-Duplex", "Half-Duplex"
	PRINTCHAR '1'
	# speed, bits 7:6:  00=1 Mbps, 01= 10 Mbps, 10/11= 1 Gbps
	mov	ah, al
	mov	al, 'G'
	shl	ah, 1
	jc	1f
	mov	al, 'M'
	shl	ah, 1
	jnc	1f
	printchar '0'
1:	call	printchar
	PRINT "bps"

#	STATUS_FID	= 3 << 2	# Function Id: 00=Lan A, 01=Lan B.
#					# 82546GB/EB only.
#	STATUS_TXOFF	= 1 << 4	# Transmission Paused (f dupl flow ctl)
#	STATUS_TBIMODE	= 1 << 5	# TBI mode/internal SerDes indication.
#					# When 0, works in internal PHY mode.
#	STATUS_SPEED	= 3 << 6	# Link Speed Setting (when tbimode=0).
#					# 00=10Mbps,01=100Mbps,10=11=1Gbps
#	STATUS_ASDV	= 3 << 8	# Auto-Speed detection value (PHY)
#					# write CTRL_EXT.ASDCHK, then read.
#			# 10 reserved
#	STATUS_PCI66	= 1 << 11	# PCI bus speed indication.
#	STATUS_BUS64	= 1 << 12	# PCI Bus width indication
#	STATUS_PCIX_MODE= 1 << 13	# PCI-X mode indication.
#	STATUS_PCIXSPD	= 3 << 14	# PCI-X bus speed indication:
	


	pop	edx

	I8254_READ RCTL
	printc	15, " RCTL: "
	push	edx
	mov	edx, eax
	call	printhex8
	call	printspace
	PRINTFLAG eax, RCTL_EN, "Rx "
	PRINTFLAG eax, RCTL_UPE, "UPE "
	PRINTFLAG eax, RCTL_MPE, "MPE "
	PRINTFLAG eax, RCTL_BAM, "BAM "
	PRINTFLAG eax, RCTL_BSEX, "BSEX "
	shr	edx, 16
	and	dx, 3
	call	printhex1
	pop	edx

	printc	15, " ICR: "
	I8254_READ ICR
	push	edx
	mov	edx, eax
	call	printhex8
	pop	edx

	printc	15, " RDH "
	I8254_READ RDH
	push	edx
	mov	edx, eax
	call	printhex4
	pop	edx

	printc	15, " RDT "
	I8254_READ RDT
	push	edx
	mov	edx, eax
	call	printhex4
	pop	edx

	call	newline
	pop	eax
	pop	edx
	ret


i8254_ifup:
	push	edx
	push	eax
	mov	dx, [ebx + dev_io]

	# Enable receiver
	I8254_READ RCTL
	or	eax, RCTL_EN
	I8254_WRITE RCTL

	# link up
	I8254_READ CTRL
	or	eax, CTRL_SLU
	I8254_WRITE CTRL
	
	pop	eax
	pop	edx
	ret

i8254_ifdown:
	push	edx
	push	eax
	mov	dx, [ebx + dev_io]
	I8254_READ RCTL
	and	eax, ~ RCTL_EN
	I8254_WRITE RCTL

	# link down
	I8254_READ CTRL
	and	eax, ~CTRL_SLU
	I8254_WRITE CTRL
	pop	eax
	pop	edx
	ret

