##############################################################################
# Broadcom NetXtreme BCM57xx Ethernet Network Controller
# (specifically the BCM5782)
.intel_syntax noprefix
##############################################################################
BCM57_DEBUG = 1

BIG_ENDIAN = 0	# for clarity on init code only

##############################################################################
# Constants

# PCI: Device Specific Registers
# These follow after the PCI header region (0x00-0x67)
# Can be accessed using PCI or MMIO
BCM57_PCIREG_MHC		= 0x68	# Misc Host Control	// boot value: 3003 02b2
	BCM57_PCIREG_MHC_CHIPREV_SHIFT = 16	# high word is chip revision:
	# pci_chip_rev_id = word
	# asic_rev = pci_chip_rev_id >> 12	# ASIC: 5705
	# chip_rev = pci_chip_rev_id >> 8	# CHIP: 5705_A3

	# 0    2    b    2
	# 0000 0010 1011 0010

# 1	ETSM
# 0	MIM
#
# 1	EIA	indirect access
# 0	ERWS	reg wordswap
# 1	ECCRW	clock control
# 1	ESRW	pci status reg
#
# 0	EEWS
# 0	EEBS
# 1	MPCIIO
# 0	CINTA

	BCM57_PCIREG_MHC_ETSM	= 1 << 9	# enable Tagged Status Mode
	BCM57_PCIREG_MHC_MIM	= 1 << 8	# Mask Interrupt Mode (mask INTA_L)
	BCM57_PCIREG_MHC_EIA	= 1 << 7	# Enable Indirect Access
						# pci shadows registers, local
						# mem, and mailboxes.
	BCM57_PCIREG_MHC_ERWS	= 1 << 6	# Enable Register Word Swap
	BCM57_PCIREG_MHC_ECCRW	= 1 << 5	# Enable Clock Control R/W
	BCM57_PCIREG_MHC_ESRW	= 1 << 4	# Enable PCI Status register R/W
	BCM57_PCIREG_MHC_EEWS	= 1 << 3	# Enable Endian Word Swap
	BCM57_PCIREG_MHC_EEBS	= 1 << 2	# Enable Endian Byte Swap
	BCM57_PCIREG_MHC_MPCIIO	= 1 << 1	# Mask PCI Interrupt Output
	BCM57_PCIREG_MHC_CINTA	= 1 << 0	# Clear INTA
BCM57_PCIREG_DMARWC		= 0x6c	# PCI DMA Read/Write Control Register
	# Recommended values:
	# Default PCI Write command = 7	(bits 31:28)
	# Default PCI Read command = 6  (bits 27:24)
	
BCM57_PCIREG_PCISTATE		= 0x70	# PCI State register
	# NOTE: set MHC_ESRW too!
	BCM57_PCIREG_PCISTATE_FLAT_VIEW = 1 << 8 # reset for 64k, set for 32m
	
BCM57_PCIREG_CC			= 0x74	# Clock Control
BCM57_PCIREG_REG_BASE_ADDR	= 0x78	# Register Base Address
	# Indirect Access to Register Block. Regions:
	# 0x0000-0x8000 (VALID)
	#   0x0000-0x0400: empty?
	#   0x0400-0x8000 BCM570X registers
	# 0x8000-0x30000 : (INVALID) not accessible via register indirect mode
	# 0x30000-0x38800 (VALID)
	#    0x30000-x034000: Rx scatchpad
	#    0x34000-x038000: Tx scatchpad
	#    0x38000-x038800: Rx CPU ROM
	#
	# For MMIO and setting REG_BASE_ADDR to 0 will have BAR0+[0..32k] access
	# the 32k NIC register block.
BCM57_PCIREG_WIN_BASE_ADDR	= 0x7c	# Memory Window Base Address
	# Indirect access to Memory Block. Ranges:
	# 0x00000000-0x0001ffff: internal memory (128k)
	# 0x00020000-0x00ffffff: external memory (SSRAM, max 16Mb)
	#
	# NOTE: # [31:24 RSVD] [23:15 Window] [14:2 dontcare] [1:0 RSVD]
	# So, 9 bits for the window, aligned at 32k boundary (1<<15).
# 32 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1
# [         8           ] [          9             ] [            13               ] [2]
	# For MMIO (Standard Mode), accessing BAR0 + 32K + OFFSET (where OFFSET is max 32k)
	# will access the NIC local memory based in WIN_BASE_ADDR.

BCM57_PCIREG_REGDATA		= 0x80	# Register Data R/W
BCM57_PCIREG_WIN_DATA		= 0x84	# Memory Window Data R/W
BCM57_PCIREG_MODE_CONTROL	= 0x88	# Mode Control (Shadow Register)
BCM57_PCIREG_MISC_CONFIG	= 0x8c	# Misc Configuration (Shadow Register)
BCM57_PCIREG_MISC_LOCAL_CONTROL	= 0x90	# Misc Local Control (Shadow Register)
# 0x94 Reserved

# UNDI Mailbox shadows: register block. Only ring1 is shadowed.
BCM57_PCIREG_UNDI_RX_BDSTDR_PIM	= 0x98	# UNDI Receive BD Std Ring Producer Index Mailbox
	# Access register offset 0x5868
	# any write advances ring index; triggers rx buffer desc avail to hw
BCM57_PCIREG_UNDI_RX_RRR_CIM	= 0x98	# UNDI Receive Return Ring Consumer Index Mailbox
	# Access register offset 0x5880
	# a write indicates host consumed RX buffer descriptor;
BCM57_PCIREG_UNDI_TX_BDR_PIM	= 0x98	# UNDI Send BD Ring Producer Index Mailbox
	# Access register offset 0x5980 (BCM5700/BCM5701 only)
	# write index of buffer desc to signal TX of eth frames.
# 0xb0 and up: reserved (only until 0x100)



# MMIO addresses:
BCM57_REG_MAC_ETH_MODE		= 0x00000400	# Ethernet MAC Mode register (value = 8 on boot)
BCM57_REG_MAC_ADDR0_HI		= 0x00000410 /* upper 2 bytes */
BCM57_REG_MAC_ADDR0_LO		= 0x00000414 /* lower 4 bytes */
BCM57_REG_MAC_ADDR1_HI		= 0x00000418 /* upper 2 bytes */
BCM57_REG_MAC_ADDR1_LO		= 0x0000041c /* lower 4 bytes */
BCM57_REG_MAC_ADDR2_HI		= 0x00000420 /* upper 2 bytes */
BCM57_REG_MAC_ADDR2_LO		= 0x00000424 /* lower 4 bytes */
BCM57_REG_MAC_ADDR3_HI		= 0x00000428 /* upper 2 bytes */
BCM57_REG_MAC_ADDR3_LO		= 0x0000042c /* lower 4 bytes */
BCM57_REG_MAC_ACPI_MBUF_PTR	= 0x00000430
BCM57_REG_MAC_ACPI_LEN_OFFSET	= 0x00000434

BCM57_REG_LWMMRF		= 0x00000504	# Low Watermark Max Receive Frames reg

BCM57_REG_MAC_SRAM_FIRMWARE_MBOX= 0xb50
	BCM57_T3_MAGIC_NUMBER	= 0x4b657654

BCM57_REG_MAM			= 0x4000	# Memory Arbiter Mode register
	BCM57_REG_MAM_RESET	= 1 << 0
	BCM57_REG_MAM_ENABLE	= 1 << 1
	# much more here...

######
# table 382 page 466 (pdf 531): Buffer manager Control Registers
# 0x4400-0x4403	Buffer Manager Mode register
# 0x4404-0x4407	Buffer Manager Status register
# 0x4408-0x440b	MBUF pool base address
# 0x440c-0x440f	MBUF pool length
# 0x4410-0x4413	MBUF pool Read DMA low watermark
# 0x4414-0x4417	MBUF pool MAC RX low watermark
# 0x4418-0x441b	MBUF pool high watermark
# 0x441c-0x441f	RX RISC MBUF Allocation Request register
# 0x4420-0x4423	RX RISC MBUF Allocation Response register
# 0x4424-0x4427	Reserved
# 0x4428-0x442b	Reserved
# 0x442c-0x442f	DMA Descriptor pool base address
# 0x4430-0x4433	DMA Descriptor pool length
# 0x4434-0x4437	DMA Descriptor pool low watermark
# 0x4438-0x443b	DMA Descriptor pool high watermark
# 0x443c-0x443f	Reserved
# 0x4440-0x4443	Reserved
# 0x4444-0x4447	Reserved
# 0x4448-0x444b	Reserved
# 0x444c-0x444f	Hardware Diagnostic 1 register
# 0x4450-0x4453	Hardware Diagnostic 2 register
# 0x4454-0x4457Hardware Diagnostic 3 register
# 0x4458-0x445b	Receive Flow Threshold Register
# 0x445c-0x47ff	Reserved
 
BCM57_REG_BMMC		= 0x4400	# Buffer Manager Mode Control register
	# bits 31:6 are reserved
	BCM57_REG_BMMC_RESET_RXMBUF_PTR	= 1<<5
	BCM57_REG_BMMC_MBUF_LO_ATTN_ENABLE=1<<4
	BCM57_REG_BMMC_BM_TESTMODE	= 1<<3
	BCM57_REG_BMMC_ATTN_ENABLE	= 1<<2
	BCM57_REG_BMMC_ENABLE		= 1<<1
	BCM57_REG_BMMC_RESET		= 1<<0
	
BCM57_REG_BMST		= 0x4404	# Buffer Manager Status register
BCM57_REG_MP_BASE_ADDR	= 0x4408	# MBUF pool base address
BCM57_REG_MP_LEN	= 0x440c	# MBUF pool length
BCM57_REG_MP_RDMA_WM_LO	= 0x4410	# MBUF pool Read DMA low watermark
BCM57_REG_MP_MAC_RX_WM_LO=0x4414	# MBUF pool MAC RX low watermark
BCM57_REG_MP_WM_HI	= 0x4418	# MBUF pool high watermark
BCM57_REG_MP_RX_AREQ	= 0x441c	# RX RISC MBUF Allocation Request register
BCM57_REG_MP_RX_ARESP	= 0x4420	# RX RISC MBUF Allocation Response register
#BCM57_REG_		= 0x4424	# Reserved
#BCM57_REG_		= 0x4428	# Reserved
BCM57_REG_DMADP_BASE_ADDR=0x442c	# DMA Descriptor pool base address
BCM57_REG_DMADP_LEN	= 0x4430	# DMA Descriptor pool length
BCM57_REG_DMADP_WM_LO	= 0x4434	# DMA Descriptor pool low watermark
BCM57_REG_DMADP_WM_HI	= 0x4438	# DMA Descriptor pool high watermark
#BCM57_REG_		= 0x443c	# Reserved
#BCM57_REG_		= 0x4440	# Reserved
#BCM57_REG_		= 0x4444	# Reserved
#BCM57_REG_		= 0x4448	# Reserved
BCM57_REG_HWDIAG1	= 0x444c	# Hardware Diagnostic 1 register
BCM57_REG_HWDIAG2	= 0x4450	# Hardware Diagnostic 2 register
BCM57_REG_HWDIAG3	= 0x4454	# Hardware Diagnostic 3 register
BCM57_REG_RFLOW_THRESH	= 0x4458	# Receive Flow Threshold Register
#BCM57_REG_		= 0x445c	# Reserved
######




#########################
BCM57_REG_FTQ_RESET	= 0x5c00



# GRC:
# GRC_MODE = 0x6800
# GRC_MISC_CFG = 0x6804

BCM57_REG_GMC		=	0x6800	# General Mode Control register (aka GRC_MOE
	# 0 reserved
	BCM57_REG_GMC_BSNFD	= 1<<1	# byte swap non-frame data
	BCM57_REG_GMC_WSNFD	= 1<<2	# byte swap non-frame data
	# 3 reserved
	BCM57_REG_GMC_BSD	= 1<<4	# byte swap data
	BCM57_REG_GMC_WSD	= 1<<5	# byte swap data
	# and much more...
	BCM57_REG_GMC_HSU	= 1<<16	# Host Stack Up (RX enable)
	BCM57_REG_GMC_HSBD	= 1<<17	# Host Send BDs (send rings in host mem, not MAC)

	BCM57_REG_GMC_SNPHCKSUM	= 1<<20	# Send No Pseudo-header checksum
	BCM57_REG_GMC_RNPHCKSUM	= 1<<23	# Receive No Pseudo-header checksum

BCM57_REG_GCMC			= 0x6804	# General Control Misc Configuration
	BCM57_REG_GCMC_CCBR	= 1 << 0	# CORE Clock Blocks Reset
	BCM57_REG_GCMC_PS_MASK	= 0xfe		# Prescalar mask
	BCM57_REG_GCMC_PS_SHIFT	= 1		# Prescalar mask
	BCM57_REG_GCMC_BID_MASK	= 0x0001e000	# Board ID mask (5700,5701,5702FE,5703[S?]5704[CIOBE?|A2?],5788[M?],AC91002A1
	BCM57_REG_GCMC_EPHY_IDDQ = 0x00200000
	BCM57_REG_GCMC_KEEP_GPHY_POWER = 0x04000000

BCM57_REG_GLC			= 0x6808	# General Local Control
	BCM57_REG_GLC_INT_ACTIVE= 1<<0
	BCM57_REG_GLC_CLEARINT= 1<<1
	BCM57_REG_GLC_SETING= 1<<2
	BCM57_REG_GLC_INT_ON_ATTN= 1<<3
	BCM57_REG_GLC_GPIO_UART_SEL= 1<<4
	BCM57_REG_GLC_USE_SIG_DETECT= 1<<4
	BCM57_REG_GLC_USE_EXT_SIG_DETECT= 1<<5 # 0x20
	BCM57_REG_GLC_GPIO_INPUT3	= 0x20
	BCM57_REG_GLC_GPIO_OE3		= 0x40	# 1 < 6
	BCM57_REG_GLC_GPIO_OUTPUT3	= 0x80
	BCM57_REG_GLC_GPIO_INPUT0	= 0x100
	BCM57_REG_GLC_GPIO_INPUT1	= 0x200
	BCM57_REG_GLC_GPIO_INPUT2	= 0x400
	BCM57_REG_GLC_GPIO_OE0	= 0x800
	BCM57_REG_GLC_GPIO_OE1	= 0x1000
	BCM57_REG_GLC_GPIO_OE2	= 0x2000
	BCM57_REG_GLC_OUTPUT0	= 0x00004000
	BCM57_REG_GLC_OUTPUT1	= 0x00008000
	BCM57_REG_GLC_OUTPUT2	= 0x00010000
	BCM57_REG_GLC_EXTMEM_ENABLE = 0x00020000
	BCM57_REG_GLC_MEMSZ_MASK	= 0x001c0000	# 20-18: 1 bits: 000-111 (111 reserved)
	BCM57_REG_GLC_MEMSZ_256K	= 0x00000000
	BCM57_REG_GLC_MEMSZ_512K	= 0x00040000
	BCM57_REG_GLC_MEMSZ_1M	= 0x00080000
	BCM57_REG_GLC_MEMSZ_2M	= 0x000c0000
	BCM57_REG_GLC_MEMSZ_4M	= 0x00100000
	BCM57_REG_GLC_MEMSZ_8M	= 0x00140000
	BCM57_REG_GLC_MEMSZ_16M	= 0x00180000
	BCM57_REG_GLC_MEMSZ_BANK_SELECT = 0x00200000	# if set, 2 SSRAM banks installed
	BCM57_REG_GLC_MEMSZ_SSRAM_TYPE = 0x00400000
	BCM57_REG_GLC_MEMSZ_AUTO_SEEPROM = 0x01000000


# NVRAM_CMD	= 0x00007000
# NVRAM_CMD_RESET	= 1<<0	# 0x00001
# NVRAM_CMD_DONE	= 1<<3	# 0x00008
# NVRAM_CMD_GO		= 1<<4	# 0x00010
# NVRAM_CMD_WR		= 1<<5	# 0x00020
# NVRAM_CMD_RD		= 0
# NVRAM_CMD_ERASE	= 1<<6	# 0x00040
# NVRAM_CMD_FIRST	= 1<<7	# 0x00080
# NVRAM_CMD_LAST	= 1<<8	# 0x00100
# NVRAM_CMD_WREN	= 1<<16	# 0x10000
# NVRAM_CMD_WRDI	= 1<<17	# 0x20000
#
# NVRAM_STAT	= 0x7004
# NVRAM_WRDATA	= 0x7008	
# NVRAM_ADDR	= 0x700c	# ADDR_MASK + 0x00ffffff
# NVRAM_RDDATA	= 0x7010
# NVRAM_CFG1	= 0x7014
# NVRAM_CFG2	= 0x7018
# NVRAM_CFG3	= 0x701c
# NVRAM_SWARB	= 0x7020 // SAR!
# NVRAM_ACCESS	= 0x7024
# NVRAM_WRITE1	= 0x7028
# NVRAM_ADDR_LOCKOUT	= 0x7030

BCM57_REG_SAR			=	0x7020	# software arbitration register
	BCM57_REG_SAR_REQ_SET0	= 1 << 0
	BCM57_REG_SAR_REQ_SET1	= 1 << 1
	BCM57_REG_SAR_REQ_SET2	= 1 << 2
	BCM57_REG_SAR_REQ_SET3	= 1 << 3
	BCM57_REG_SAR_REQ_CLR0	= 1 << 4
	BCM57_REG_SAR_REQ_CLR1	= 1 << 5
	BCM57_REG_SAR_REQ_CLR2	= 1 << 6
	BCM57_REG_SAR_REQ_CLR3	= 1 << 7
	BCM57_REG_SAR_ARB_WON0	= 1 << 8
	BCM57_REG_SAR_ARB_WON1	= 1 << 9
	BCM57_REG_SAR_ARB_WON2	= 1 << 10
	BCM57_REG_SAR_ARB_WON3	= 1 << 11
	BCM57_REG_SAR_REQ0	= 1 << 12
	BCM57_REG_SAR_REQ1	= 1 << 13
	BCM57_REG_SAR_REQ2	= 1 << 14
	BCM57_REG_SAR_REQ3	= 1 << 15
	BCM57_REG_SAR_REQ_SET4	= 1 << 16
	BCM57_REG_SAR_REQ_CLR4	= 1 << 17
	BCM57_REG_SAR_REQ_WON4	= 1 << 18
	BCM57_REG_SAR_REQ4	= 1 << 19
	BCM57_REG_SAR_REQ_SET4	= 1 << 20
	BCM57_REG_SAR_REQ_CLR4	= 1 << 21
	BCM57_REG_SAR_REQ_WON4	= 1 << 22
	BCM57_REG_SAR_REQ4	= 1 << 23


###############################################

# Indirect Mode: no MMIO; MAC resources shadowed in PCI config registers:
# - Registers, - Local Memory, - Mailboxes. Independent of PCI access mode,
# which can be Standard (64k MMIO) or Flat (32MB MMIO).

# high prio mailboxes: 0x200-0x3ff: host standard and flat modes
# low  prio mailboxes: 0x5800-0x59ff: indirect mode.


# Standard Mode: 64kb mmio (BAR0) 
# 0x00000000 - 0x000000ff: PCI configuration space registers (shadow copy)
# 0x000000ff - 0x000001ff: reserved
# 0x00000200 - 0x000003ff: high priority mailboxes
# 0x00000400 - 0x00007fff: registers
# 0x00008000 - 0x0000ffff: memory window (high 32k). Access here is mapped
#			   to NIC local mem based on WIN_BASE_ADDR.
#
 
# Flat Mode: 32Mb MMIO (BAR0)
# 0x00000000 - 0x000001ff PCI shadow
# 0x00000200 - 0x000003ff high prio mailboxes
# 0x00000400 - 0x00008000 registers
# 0x00008000 - 0x000fffff memory window
# 0x00100000 - 0x00110000 IRQ mailbox 0-3
# 0x00110000 - 0x00130000 General mailbox 1-8
# 0x00130000 - 0x00180000 Rx BD send producer index (jumbo, std, mini)
#			  Rx BD return ring 1-16 Consumer index
# 0x00180000 - 0x001c0000 Tx BD ring 1-16 host producer index
# 0x001c0000 - 0x01000000 Tx BD ring 1-16 NIC producer index
# 0x01000000 - 0x01ffffff memory

# General memory map:
# A): (5700/5701/5702/5703c/5703s/5704c/5704s)
# B): 5705,5788,5721,5751,5752 (BCM5782 has ASIC 5705) so we use this)
# -----A-------------  -------B--------
# 0x000 - 0x0ff (256b)	idem		page zero
# 0x100 - 0x1ff (256b)	0x100-0x10f	send ring RCB
#			0x110-0x1ff	(unmapped)
# 0x200 - 0x2ff (256b)	0x200-0x20f	receive return ring RCB
#			0x210-0x2ff	(unmapped)
# 0x300 - 0xaff (2kb) 	(unmapped)	statistics block
# 0xb00 - 0xb4f (80b)	(unmapped)	status block
# 0xb50 - 0xfff (1200b)	0xb50-0xf4f	software general communications (0xb50: FIRMWARE_MBOX)
#			0xf50-0x1fff	unmapped
# 0x1000-0x1fff (4k)			unmapped
# 0x2000-0x3fff (8k)	(unmapped)	DMA descriptors
# 0x4000-0x4fff (8k)	0x4000-0x47ff	send rings 1-4
#			0xf800-0x4fff 	unmapped
# 0x6000-0x6fff (4k)			standard receive rings
# 0x7000-0x7fff (4k)	(unmapped)	jumbo receive rings
# 0x8000-0xffff (32k)			buffer pool 1
#			0x8000-0x9fff	TXMBUF
#			0xa000-0xffff	unmapped
# 0x10000-0x17fff (32k)			buffer pool 2 (or expansion rom) - PXE image mapped here during boot
#			0x10000-0x1dfff	RXMBUF/scratchpad 5705
# etc etc - more exceptions for ---B---
# 0x18000-0x1ffff (32k)			buffer pool 3 (or expansion rom) - PXE image mapped here during boot

##### pci_chip_rev_id = MHC >> 16 (word):
CHIPREV_ID_5700_A0                = 0x7000
CHIPREV_ID_5700_A1                = 0x7001
CHIPREV_ID_5700_B0                = 0x7100
CHIPREV_ID_5700_B1                = 0x7101
CHIPREV_ID_5700_B3                = 0x7102
CHIPREV_ID_5700_ALTIMA            = 0x7104
CHIPREV_ID_5700_C0                = 0x7200
CHIPREV_ID_5701_A0                = 0x0000
CHIPREV_ID_5701_B0                = 0x0100
CHIPREV_ID_5701_B2                = 0x0102
CHIPREV_ID_5701_B5                = 0x0105
CHIPREV_ID_5703_A0                = 0x1000
CHIPREV_ID_5703_A1                = 0x1001
CHIPREV_ID_5703_A2                = 0x1002
CHIPREV_ID_5703_A3                = 0x1003
CHIPREV_ID_5704_A0                = 0x2000
CHIPREV_ID_5704_A1                = 0x2001
CHIPREV_ID_5704_A2                = 0x2002
CHIPREV_ID_5704_A3                = 0x2003
CHIPREV_ID_5705_A0                = 0x3000
CHIPREV_ID_5705_A1                = 0x3001
CHIPREV_ID_5705_A2                = 0x3002
CHIPREV_ID_5705_A3                = 0x3003	# our 5782 matches this
CHIPREV_ID_5750_A0                = 0x4000
CHIPREV_ID_5750_A1                = 0x4001
CHIPREV_ID_5750_A3                = 0x4003
CHIPREV_ID_5750_C2                = 0x4202
CHIPREV_ID_5752_A0_HW             = 0x5000
CHIPREV_ID_5752_A0                = 0x6000
CHIPREV_ID_5752_A1                = 0x6001
CHIPREV_ID_5714_A2                = 0x9002
CHIPREV_ID_5906_A1                = 0xc001
CHIPREV_ID_57780_A0               = 0x57780000
CHIPREV_ID_57780_A1               = 0x57780001
CHIPREV_ID_5717_A0                = 0x05717000
CHIPREV_ID_5717_C0                = 0x05717200
CHIPREV_ID_57765_A0               = 0x57785000
CHIPREV_ID_5719_A0                = 0x05719000
CHIPREV_ID_5720_A0                = 0x05720000
CHIPREV_ID_5762_A0                = 0x05762000


# ( MHC >> 16 ) >> 12 = 4 bits
ASIC_REV_5700                    = 0x07
ASIC_REV_5701                    = 0x00
ASIC_REV_5703                    = 0x01
ASIC_REV_5704                    = 0x02
ASIC_REV_5705                    = 0x03	# our 5782 matches this
ASIC_REV_5750                    = 0x04
ASIC_REV_5752                    = 0x06
ASIC_REV_5780                    = 0x08
ASIC_REV_5714                    = 0x09
ASIC_REV_5755                    = 0x0a
ASIC_REV_5787                    = 0x0b
ASIC_REV_5906                    = 0x0c
ASIC_REV_USE_PROD_ID_REG         = 0x0f
ASIC_REV_5784                    = 0x5784
ASIC_REV_5761                    = 0x5761
ASIC_REV_5785                    = 0x5785
ASIC_REV_57780  	         = 0x57780
ASIC_REV_5717                    = 0x5717
ASIC_REV_57765          	 = 0x57785
ASIC_REV_5719                    = 0x5719
ASIC_REV_5720                    = 0x5720
ASIC_REV_57766          	 = 0x57766
ASIC_REV_5762                    = 0x5762


############################################################################
# structure for the device object instance:
# append field to nic structure (subclass)
DECLARE_CLASS_BEGIN nic_bcm57, nic
bcm57_flags:	.long 0
	BCM57_FLAG_SRAM_USE_CONFIG = 1 # must be in byte
DECLARE_CLASS_METHOD dev_api_constructor, bcm57_init, OVERRIDE
DECLARE_CLASS_METHOD dev_api_isr,	bcm57_isr, OVERRIDE
DECLARE_CLASS_METHOD nic_api_send,	bcm57_send, OVERRIDE
DECLARE_CLASS_METHOD nic_api_print_status, bcm57_print_status, OVERRIDE
DECLARE_CLASS_METHOD nic_api_ifup,	bcm57_ifup, OVERRIDE
DECLARE_CLASS_METHOD nic_api_ifdown,	bcm57_ifdown, OVERRIDE

DECLARE_CLASS_END nic_bcm57

DECLARE_PCI_DRIVER NIC_ETH, nic_bcm57, 0x14e4, 0x1696, "bcm5782", "BCM5782 Gigabit Ethernet"
############################################################################
.text32
DRIVER_NIC_BCM57_BEGIN = .


# PCI read/write
.macro BCM_PCIREG_OR_ reg, val
	mov	dl, BCM57_PCIREG_\reg
	call	dev_pci_read_config
	or	eax, \val
	call	dev_pci_write_config
.endm

.macro BCM_PCIREG_OR reg, val
	mov	dl, BCM57_PCIREG_\reg
	call	dev_pci_read_config
	or	eax, BCM57_PCIREG_\reg\()_\val
	call	dev_pci_write_config
.endm

.macro BCM_PCIREG_READ reg
	mov	dl, BCM57_PCIREG_\reg
	call	dev_pci_read_config
.endm

.macro BCM_PCIREG_WRITE reg, value=eax
	mov	dl, BCM57_PCIREG_\reg
	.ifnes "\value","eax"
	mov	eax, \value
	.endif
	call	dev_pci_write_config
.endm




# Register space (mmio) R/W
# in: esi = [ebx + dev_mmio]

.macro BCM_REG_OR reg, bitname
	ord	[esi + BCM57_REG_\reg\()], BCM57_REG_\reg\()_\bitname\()
.endm

.macro BCM_REG_OR_ reg, value
	ord	[esi + BCM57_REG_\reg\()], \value\()
.endm

.macro BCM_REG_TEST reg, bitname
	testd	[esi + BCM57_REG_\reg\()], BCM57_REG_\reg\()_\bitname\()
.endm

.macro BCM_REG_READ reg
	mov	eax, [esi + BCM57_REG_\reg\()]
.endm


.macro BCM_REG_WRITE_ reg, value=eax
	mov	dword ptr [esi + BCM57_REG_\reg\()], \value
.endm

.macro BCM_REG_WRITE reg, value=eax
	.ifnes "\value","eax"
	BCM_REG_WRITE_ \reg, BCM57_REG_\value
	.else
	BCM_REG_WRITE_ \reg, eax
	.endif
.endm


# destroys eax
.macro BCM_WIN_WRITE name, value
	BCM_WIN_WRITE_ \name, WIN_ADDR_\name\()_\value
.endm


.macro BCM_WIN_WRITE_ name, value
	BCM_PCIREG_WRITE WIN_BASE_ADDR, BCM57_REG_MAC_\name
	BCM_PCIREG_READ WIN_BASE_ADDR
	BCM_PCIREG_WRITE WIN_DATA, \value
	BCM_PCIREG_READ WIN_DATA
	BCM_PCIREG_WRITE WIN_BASE_ADDR, 0
.endm

# out: eax
# destroys: edx
.macro BCM_WIN_READ name
	testb	[ebx + bcm57_flags], BCM57_FLAG_SRAM_USE_CONFIG
	jz	201f
	BCM_PCIREG_WRITE WIN_BASE_ADDR, BCM57_REG_MAC_\name
	BCM_PCIREG_READ WIN_BASE_ADDR
	BCM_PCIREG_READ WIN_DATA
	jmp	209f
201:
	mov	dword ptr [esi + BCM57_PCIREG_WIN_BASE_ADDR], BCM57_REG_MAC_\name
	mov	edx, [esi + BCM57_PCIREG_WIN_BASE_ADDR]
	mov	eax, [esi + BCM57_PCIREG_WIN_DATA]		# tr32 MEM_WIN_DATA
	mov	dword ptr [esi + BCM57_PCIREG_WIN_BASE_ADDR], BCM57_REG_MAC_\name
	mov	edx, [esi + BCM57_PCIREG_WIN_BASE_ADDR]
209:
.endm


###############################################################################

# in: ebx = pci nic object
bcm57_init:
	push_	ebp edx ebx
	mov	ebp, esp

	I "Init BCM57xx"
	DEBUG_WORD [ebx + dev_io]
	DEBUG_DWORD [ebx + dev_mmio]

	mov     esi, [page_directory_phys]
	mov     eax, [ebx + dev_mmio]
	mov     ecx, [ebx + dev_mmio_size]
	call    paging_idmap_memrange

	call	bcm57_read_mac

#	call	bcm57_alloc_buffers
#	jc	9f

	call	dev_add_irq_handler


	# For the rest of the initialization code, we have
	# ebx = dev pointer
	# esi = mmio pointer
	# dev_pci_(read|write) args are dl = reg, eax = value
	# BCM_REG_* macro args are esi = mmio, eax = value

	mov	esi, [ebx + dev_mmio]

	orb	[ebx + bcm57_flags], BCM57_FLAG_SRAM_USE_CONFIG # XXX test!

	call	bcm57_debug_registers

	# print some pci stuff:
	xor	dl, dl
	call	dev_pci_read_config
	DEBUG_DWORD eax, "PCI vendor/device ID"
	call	newline
	DEBUG_DWORD [esi], "MAC vendor/device ID"
	call	newline


# 57XX-PG105-R.pdf Section 8 "Device Control" - "Initialization", p146 (PDF p221)
# step 1: enable PCI busmaster and mmio
	call	dev_pci_busmaster_enable

# step 2: disable and clear PCI interrupts
	BCM_PCIREG_OR_ MHC, 0b11		# MASK_PCI_INTERRUPT_OUTPUT | CLEAR_INTERRUPT_INTA

# step 3: backup PCI cache line size and subsystem vendor ID
#  these will be reset in step7 (clock reset)
	# [ebx + dev_pci_subvendor] already saved
	mov	dl, PCI_CFG_BIST_HTYPE_LTIMER_CACHE	# 0xc
	call	dev_pci_read_config
	.data SECTION_DATA_BSS
	_tmp_bm57_cls: .long 0	# cache line size etc
	.text32
	mov	[_tmp_bm57_cls], eax

# step 4: acquire NVRAM lock
	#orb	[esi + 0x7020], 2	# REQ_SET1
	BCM_REG_READ SAR; DEBUG_DWORD eax, "SAR"
	BCM_REG_OR SAR, REQ_SET1
	BCM_REG_READ SAR; DEBUG_DWORD eax, "SAR"
	mov	ecx, 1000
0:	BCM_REG_TEST SAR, ARB_WON1
	jnz	1f
		# add some delay
		mov	eax, 5
		call	udelay
	loop	0b
	printlnc 4, "Could not acquire NVRAM lock"
	jmp	2f

1:	print "* acquired NVRAM lock -- delays: "
	mov	edx, 1000
	sub	edx, ecx
	call	printdec32
	BCM_REG_READ SAR; DEBUG_DWORD eax, "SAR"
	call	newline
2:

# step 5: prepare for writing T3_MAGIC_NUMBER to 0xb50
	# a) Enable Memory Arbiter
	BCM_REG_OR MAM, ENABLE
	# b) Enable indirect access
	BCM_PCIREG_OR_ MHC, 1<<7	# Enable Indirect Access
	# c) enable endian byte/word swap (unsure - doesn't say little/big!)
	# We'll assume for now that since it's a RISC processor it's big endian
	# so we swap for little endian
	BCM_PCIREG_READ MHC # offset 0x68 (pci)
.if BIG_ENDIAN
	or	eax, 0b1100	# enable endian word,byte swap for PCI target interface access
.else
	and	eax, ~0b1100	# disable
.endif
	BCM_PCIREG_WRITE MHC
	# d) byte/word swap non-frame data:
	BCM_REG_READ GMC	# General Mode Control ofset 0x6800 - NIC register space
.if BIG_ENDIAN
	or	eax, (BCM57_REG_GMC_BSNFD | BCM57_REG_GMC_WSNFD)
.else
	and	eax,~(BCM57_REG_GMC_BSNFD | BCM57_REG_GMC_WSNFD)
.endif
	BCM_REG_WRITE GMC

# step 6: next reset is warm reset:
	BCM_WIN_WRITE_ SRAM_FIRMWARE_MBOX, BCM57_T3_MAGIC_NUMBER

# step 7: reset core clocks
	# This will:
	# - reset the core clocks
	# - disable indirect/flat/standard modes (local mem iface disabled)
	BCM_REG_OR GCMC, CCBR|(1<<26)	# CORE Clock Blocks Reset
	#   NOTE: set bit 26 (GPHY_POWer-DOWN_OVERRIDe for BCM5705 etc (which is the ASIC for 5782)
	# XXX NOTE: bit 26 and/or bit 29 should be set for certain models (not 5782)

# step 8: wait for the reset to complete (cannot poll)
	mov	eax, 100	# PCI/PCI-X: 100 musec; PCIe: 100ms (pcie: PCI capabilty reg; BCM5782 doesn't.)
	call	udelay

# step 9: disable interrupts (same as step 2 except INTA not cleared)
	BCM_PCIREG_OR MHC, MPCIIO	# MASK_PCI_INTERRUPT_OUTPUT

# step 10: enable MAC memory space decode and bus mastering:
	call	dev_pci_busmaster_enable	# also sets IO and MMIO bits (only MMIO supported by dev)

# step 11: disable PCI-X relaxed ordering
	# XXX NOTE: manual says to set this in register 0x04 (PCI_CFG_COMMAND reg)
	# this card doesn't support PCI-X (acccording to PCI capabilities structure)
	/*
	mov	dl, PCI_X_REG_CMD
	call	dev_pci_read_config
	and	eax, ~ PCI_X_REG_CMD_ERO	# clear Enable Relaxed Ordering
	call	dev_pci_write_config
	*/

# Step 12: enable MAC memory arbiter
	BCM_REG_OR MAM, ENABLE

# Step 13: Enable External Memory (optional - skipped; it has 256K SSRAM though!)
	# XXX For now leave disabled: see step 33 and "Buffer manager control registers" p466/pdf531
	# Having this enabled we'd ahve to relocate some rings/buffers to SSRAM etc.
	#BCM_REG_OR GLC, EXTMEM_ENABLE
	# should also set mem size and external mem bank slect bits, but these remain set anyway so..
	# udelay 10 * 1000

# Step 14: Initialize MISC_HOST register
	# a) endian word swap (optional)
	# b) endian byte swap (optional)
	# These are only necessary for big-endian host processors, which Intel/AMD is not.
.if BIG_ENDIAN
	# XXX ???
	BCM_PCIREG_OR_ MHC, 0b1100	# enable endian word, byte swap for PCI target interface access
.else
	BCM_PCIREG_READ MHC
	and	eax, ~( BCM57_PCIREG_MHC_EEWS | BCM57_PCIREG_MHC_EEBS )
	or	eax, BCM57_PCIREG_MHC_EEWS # EEWS (enable endian word swap) is enabled on boot
	BCM_PCIREG_WRITE MHC
.endif
	# c) enable indirect register pairs
	# d) enable PCI state register
	# e) enable PCI clock control register
	# enable: indirect access | status rw | clock control
	BCM_PCIREG_OR_ MHC, BCM57_PCIREG_MHC_EIA | BCM57_PCIREG_MHC_ESRW | BCM57_PCIREG_MHC_ECCRW

# Step 15: Set Byte Swap Non-Frame Data in General Mode Control reg
	BCM_REG_OR GMC, BSNFD	# XXX can be done in 1 instr
	BCM_REG_OR GMC, BSD
# Step 16: for little endian set word swap (non-frame) data
.if !BIG_ENDIAN	# yes:
	BCM_REG_OR GMC, WSNFD	# XXX can be done in 1 instr
	BCM_REG_OR GMC, WSD
.endif

# Step 17: poll for bootcode completion
	mov	ecx, 35000#1000 # should be done in 1s for for Flash and 10s for SEEPROM
	mov	edx, ~BCM57_T3_MAGIC_NUMBER
	DEBUG_DWORD edx, "polling for"
0:	BCM_WIN_READ SRAM_FIRMWARE_MBOX	# 0xb50
	cmp	eax, ~BCM57_T3_MAGIC_NUMBER
	jz	1f
	mov	eax, 10
	call	udelay	# cannot use sleep
	loop	0b
	printc 12, "NIC boot code completion timeout "
	BCM_WIN_READ SRAM_FIRMWARE_MBOX
	DEBUG_DWORD eax, "magic"
	call	newline
	jmp	2f
1:	printlnc 10, "NIC boot code completed."
2:

	call	bcm57_debug_registers


# Step 18: Initialize Ethernet MAC Mode register
	BCM_REG_WRITE_ MAC_ETH_MODE, 0	# 0xc for fiber, 0 for copper
# Step 19: enable PCIe bugfixes for certain models - skip
# Step 20: enable FIFO protection for certain models - skip
# Step 21: enable hardware fixes for BCM4704 B0 and later - skip
# Step 22: Enable Tagged Status Mode (optional)
	# unique byte inserted into status Block Status Tag
	BCM_PCIREG_OR MHC, ETSM	# enable Tagged Status Mode
# Step 23: restore PCI Cache Line Size and Subvendor ID
	mov	dl, PCI_CFG_BIST_HTYPE_LTIMER_CACHE	# 0x0c
	mov	eax, [_tmp_bm57_cls]	# Cache Line Size: low byte
	call	dev_pci_write_config	# XXX also resets other fields!
	mov	eax, [ebx + dev_pci_subvendor]	# both IDs
	mov	dl, 0x2c	# PCI Subsystem ID / Vendor ID
	call	dev_pci_write_config

# Step 24: clear MAC Statistics Block
	lea	edi, [esi + 0x300]
	xor	eax, eax
	mov	ecx, (0xb00 - 0x300) / 4
	rep	stosd
# Step 25: Clear driver statistics memory region
	# Clear DMA target host memory; DMA not setup yet!
# Step 26: Clear Driver Status memory region
	# Clear DMA target host memory; DMA not setup yet!
# Step 27: set default PCI command encoding for R/W transactions
	mov	dl, BCM57_PCIREG_DMARWC	# PCI DMA Read/Write Control Register
	call	dev_pci_read_config
	DEBUG_DWORD eax, "DMA RW Control"
	# 31:28: Default PCI Write Command (for write < 4 words)
	# 27:24: Default PCI Read Command (for write < 4 words)
	# 21:19 DMA Write Watermark
	#  For PCI/PCIe: [0..7] -> [32..256] in 32 increments
	#  For PCI-X: [0..4] -> [64,128,256,384,512] (safe: 256)
	# 18:16: DMA Read watermark (similar but less/more)
	#rol	eax, 8
	#mov	al, 0x76	# 0x7 write (no constraint); 0x6: read (??)
	#ror	eax, 8
	mov	eax, 0x763F0000 # from recommended values for BCM5705 on PDF p214
	call	dev_pci_write_config
	DEBUG_DWORD eax, "DMA RW Control"
	call	newline
# Step 28: DMA Byte swapping (optional) when host arch is bigendian.

# Step 29: configure Host Based Send Rings
	# send rings in host local storage rather than MAC memory:
	BCM_REG_OR GMC, HSBD
# Step 30: enable RX traffic
	BCM_REG_OR GMC, HSU
# Step 31: checksum calcuation offloading
	# we do our own checksum calculations
	BCM_REG_OR GMC, SNPHCKSUM	# send no pseudo header checksum
	BCM_REG_OR GMC, RNPHCKSUM	# receive no pseudo header checksum
# Step 32: config frequency of MAC 32 bit timer (readable at 0x680c)
	BCM_REG_READ GCMC
	mov	al, (66-1)<<1	# 66Mhz -1 into bits 7:1
	BCM_REG_WRITE GCMC
# Step 33: Configure MAC local memory pool
	call	newline
	DEBUG "(Step 33) Buffer manager:"
	BCM_REG_READ BMMC; DEBUG_DWORD eax, "mode control"
	BCM_REG_READ BMST; DEBUG_DWORD eax, "status"
	DEBUG "Pool:"
	BCM_REG_READ MP_BASE_ADDR; DEBUG_DWORD eax, "base addr"	# 0x10000
	BCM_REG_READ MP_LEN; DEBUG_DWORD eax, "len"		# 0x08000
	# XXX for BCM5705 do not change boot values
	call	newline
# Step 34: Configure MAC DMA resource pool (for BCM570[01234])
#	NOTE: these settings are device local addresses
	DEBUG "(Step 34) DMA Pool:"
	BCM_REG_READ DMADP_BASE_ADDR; DEBUG_DWORD eax, "base addr"	# recommended: 0x2000
	BCM_REG_WRITE_ DMADP_BASE_ADDR, 0x2000
	BCM_REG_READ DMADP_LEN; DEBUG_DWORD eax, "len"	# should be 8kb	# recommended: 0x2000
	BCM_REG_WRITE_ DMADP_LEN, 0x2000
	call	newline
	# we must allocate 8kb...?
# Step 35: Configure MAC memory pool watermarks.
	DEBUG "(step 35) MAC Mempool watermarks:";# recommended values (standard frames BCM5705)
	BCM_REG_READ MP_RDMA_WM_LO; DEBUG_DWORD eax, "RDMA lo (0)"	# 0
	BCM_REG_WRITE_ MP_RDMA_WM_LO, 0
	BCM_REG_READ MP_MAC_RX_WM_LO; DEBUG_DWORD eax, "MAC RX lo (10)"	# 0x10
	BCM_REG_WRITE_ MP_MAC_RX_WM_LO, 0x10
	BCM_REG_READ MP_WM_HI; DEBUG_DWORD eax, "HI (60)"		# 0x60
	BCM_REG_WRITE_ MP_WM_HI, 0x60
	call	newline
# Step 36: DMA resource watermarks
	DEBUG "(step 36) DMA descr. watermarks:"
	BCM_REG_READ DMADP_WM_LO; DEBUG_DWORD eax, "DMAD lo (5)"	# 0
	BCM_REG_WRITE_ DMADP_WM_LO, 5
	BCM_REG_READ DMADP_WM_HI; DEBUG_DWORD eax, "DMAD lo (10)"	# 0
	BCM_REG_WRITE_ DMADP_WM_HI, 10
	call	newline
# Step 37: flow control low watermark (reg 0x504)
	BCM_REG_READ LWMMRF; DEBUG_DWORD eax, "lo WM max RX frames (2)"
	BCM_REG_WRITE_ LWMMRF, 2
# Step 38: enable Buffer manager.
	DEBUG "Enabling buffer manager..."
	BCM_REG_OR_ BMMC, BCM57_REG_BMMC_ENABLE | BCM57_REG_BMMC_ATTN_ENABLE
# Step 39: poll for successful start of buffer manager for 10ms
	# we set the ENABLE bit, but it will be reset/deasserted on poll
	# until BM is started, at which time the bit will be 1.
0:	mov	ecx, 1000	# 1000 times 10 musec = 10 millisec
	BCM_REG_TEST BMMC, ENABLE	
	jnz	1f
	mov	eax, 10	# 1000 
	call	udelay
	loop	0b
	printlnc 12, "timeout."
	jmp	2f	# ignore for now (untested - works ;-))
1:	OK
2:

# Step 40: Enable internal hardware queues
	BCM_REG_READ FTQ_RESET; DEBUG_DWORD eax,"FTQ RESET";
	BCM_REG_WRITE_ FTQ_RESET, -1
	BCM_REG_WRITE_ FTQ_RESET, 0
	BCM_REG_READ FTQ_RESET; DEBUG_DWORD eax,"FTQ RESET";
	call newline
# Step 41
	DEBUG "Step 41/102....init std RX buffer ring. TODO"
	call	newline
	# TODO: create constant: Standard Receive BD Ring RCB Register (offset 2450 page 439)
	DEBUG_DWORD [esi + 0x2450+0],"STD RX BD RING RCB hi"  # ring host hi
	DEBUG_DWORD [esi + 0x2450+4],"lo" 
	DEBUG_WORD [esi + 0x2450+8+2],"Len" 
	DEBUG_WORD [esi + 0x2450+8+0],"flags" 
	# bit 0: extended rx enable (extended rx buffer descriptors)
	# bit 1: disable ring
	# bits 2-15:reserved
	DEBUG_DWORD [esi + 0x2450+12],"Recv prod Ring NIC address"  # 000000 (nic ring address is NIC addr of first ring element)

	# 0x2450: standard receibe bd ring rcb register: 16 bytes (4 dwords)
	# dword 0: host addr hi
	# dword 1: host addr lo
	# dword 2: hi word: len; lo: flags
	# dword 3: receive producer ring nic addr

	# now set them:
	mov [esi + 0x2450+12], dword ptr 0x6000	# NIC Ring Address recommendeed value for internal mem; 0xc000 for SSRAM
	mov [esi + 0x2450+8], word ptr 0x200	# 0x600, 0x200 (BCM5705) , 0x100   #0x600 = max size enet frame + vlan tag
	call	newline

# Step 42: init Jumbo receive ring (optional)
	# we skip it, don't think ASIC 5705 (BCM5782) has it
# Step 43: init Mini receive ring (optional)
	# skip, same.
# Step 44: init BD Ring replenish threshold for mini/std/jumbo RX producerrings.
#  nr of buffer descrs host offers before DMA fetches additional rx descriptors to replenish used receive descrs.
	# 0x2c14 mini
	# 0x2c18 std
	# 0x2c1c jumbo
	DEBUG_DWORD [esi + 0x2c18], "DB replenish"
	mov	[esi + 0x2c18], dword ptr 25	# total bd's 512; set to 1/8th ring size
# Step 45: disable unused send producer rings (up tp 5704S only)

# ...
# step 102

	# reset
	# wait 5 musec
	#mov	eax, 5
	#call	udelay

	###########################################

	# initialize

	clc
9:	
	call	more

	pop_	ebx edx ebp
	ret

bcm57_debug_registers:
	pushad
	mov	esi, [ebx + dev_mmio]
	# BCM_PCIREG_READ MHC; DEBUG_DWORD eax, "MHC"; // same!
	mov eax, [esi + BCM57_PCIREG_MHC]; DEBUG_DWORD eax, "MHC"

.macro PF r
	PRINTFLAG ax, BCM57_PCIREG_MHC_\r, "\r "
.endm
	PF ETSM
	PF MIM
	PF EIA
	PF ERWS
	PF ECCRW
	PF ESRW
	PF EEWS
	PF EEBS
	PF MPCIIO
	PF CINTA
.purgem PF

	shr	eax, 16	# MHC_CHIPREV_SHIFT
	# // DWORD on boot: 30030088
	# pci_chip_rev_id = word		# 3003
	# asic_rev = pci_chip_rev_id >> 12	# 3
	# chip_rev = pci_chip_rev_id >> 8	# 30
	call	newline
	DEBUG_WORD ax, "pci_chip_rev_id"
	mov	dx, ax
	shr	dx, 12
	DEBUG_BYTE dl, "asic_rev"
	DEBUG_BYTE ah, "chip_rev"

	printc 11, "CHIP: "
	PRINTIF ax, CHIPREV_ID_5700_A0, "5700_A0"
	PRINTIF ax, CHIPREV_ID_5700_A1, "5700_A1"
	PRINTIF ax, CHIPREV_ID_5700_B0, "5700_B0"
	PRINTIF ax, CHIPREV_ID_5700_B1, "5700_B1"
	PRINTIF ax, CHIPREV_ID_5700_B3, "5700_B3"
	PRINTIF ax, CHIPREV_ID_5700_ALTIMA, "5700_ALTIMA"
	PRINTIF ax, CHIPREV_ID_5700_C0, "5700_C0"
	PRINTIF ax, CHIPREV_ID_5701_A0, "5701_A0"
	PRINTIF ax, CHIPREV_ID_5701_B0, "5701_B0"
	PRINTIF ax, CHIPREV_ID_5701_B2, "5701_B2"
	PRINTIF ax, CHIPREV_ID_5701_B5, "5701_B5"
	PRINTIF ax, CHIPREV_ID_5703_A0, "5703_A0"
	PRINTIF ax, CHIPREV_ID_5703_A1, "5703_A1"
	PRINTIF ax, CHIPREV_ID_5703_A2, "5703_A2"
	PRINTIF ax, CHIPREV_ID_5703_A3, "5703_A3"
	PRINTIF ax, CHIPREV_ID_5704_A0, "5704_A0"
	PRINTIF ax, CHIPREV_ID_5704_A1, "5704_A1"
	PRINTIF ax, CHIPREV_ID_5704_A2, "5704_A2"
	PRINTIF ax, CHIPREV_ID_5704_A3, "5704_A3"
	PRINTIF ax, CHIPREV_ID_5705_A0, "5705_A0"
	PRINTIF ax, CHIPREV_ID_5705_A1, "5705_A1"
	PRINTIF ax, CHIPREV_ID_5705_A2, "5705_A2"
	PRINTIF ax, CHIPREV_ID_5705_A3, "5705_A3"
	PRINTIF ax, CHIPREV_ID_5750_A0, "5750_A0"
	PRINTIF ax, CHIPREV_ID_5750_A1, "5750_A1"
	PRINTIF ax, CHIPREV_ID_5750_A3, "5750_A3"
	PRINTIF ax, CHIPREV_ID_5750_C2, "5750_C2"
	PRINTIF ax, CHIPREV_ID_5752_A0_HW, "5752_A0_HW"
	PRINTIF ax, CHIPREV_ID_5752_A0, "5752_A0"
	PRINTIF ax, CHIPREV_ID_5752_A1, "5752_A1"
	PRINTIF ax, CHIPREV_ID_5714_A2, "5714_A2"
	PRINTIF ax, CHIPREV_ID_5906_A1, "5906_A1"
	#PRINTIF ax, CHIPREV_ID_57780_A0, "57780_A0"
	#PRINTIF ax, CHIPREV_ID_57780_A1, "57780_A1"
	#PRINTIF ax, CHIPREV_ID_5717_A0, "5717_A0"
	#PRINTIF ax, CHIPREV_ID_5717_C0, "5717_C0"
	#PRINTIF ax, CHIPREV_ID_57765_A0, "57765_A0"
	#PRINTIF ax, CHIPREV_ID_5719_A0, "5719_A0"
	#PRINTIF ax, CHIPREV_ID_5720_A0, "5720_A0"
	#PRINTIF ax, CHIPREV_ID_5762_A0, "5762_A0"

# ( MHC >> 16 ) >> 12 = 4 bits
	printc 11, " ASIC: ";
	PRINTIF dl, ASIC_REV_5700, "5700"
	PRINTIF dl, ASIC_REV_5701, "5701"
	PRINTIF dl, ASIC_REV_5703, "5703"
	PRINTIF dl, ASIC_REV_5704, "5704"
	PRINTIF dl, ASIC_REV_5705, "5705"
	PRINTIF dl, ASIC_REV_5750, "5750"
	PRINTIF dl, ASIC_REV_5752, "5752"
	PRINTIF dl, ASIC_REV_5780, "5780"
	PRINTIF dl, ASIC_REV_5714, "5714"
	PRINTIF dl, ASIC_REV_5755, "5755"
	PRINTIF dl, ASIC_REV_5787, "5787"
	PRINTIF dl, ASIC_REV_5906, "5906"
	PRINTIF dl, ASIC_REV_USE_PROD_ID_REG, "USE_PROD_ID_REG"
	#PRINTIF dl, ASIC_REV_5784, "5784"
	#PRINTIF dl, ASIC_REV_5761, "5761"
	#PRINTIF dl, ASIC_REV_5785, "5785"
	#PRINTIF dl, ASIC_REV_57780, "57780"
	#PRINTIF dl, ASIC_REV_5717, "5717"
	#PRINTIF dl, ASIC_REV_57765, "57765"
	#PRINTIF dl, ASIC_REV_5719, "5719"
	#PRINTIF dl, ASIC_REV_5720, "5720"
	#PRINTIF dl, ASIC_REV_57766, "57766"
	#PRINTIF dl, ASIC_REV_5762, "5762"

	call	newline

	#BCM_PCIREG_READ CC; DEBUG_DWORD eax, "CC"; // Same!
	mov eax, [esi + BCM57_PCIREG_CC]; DEBUG_DWORD eax, "CC"
	BCM_REG_READ SAR; DEBUG_DWORD eax, "SAR"
	BCM_REG_READ MAM; DEBUG_DWORD eax, "MAM"
	BCM_REG_READ GMC; DEBUG_DWORD eax, "GMC"
	BCM_REG_READ GCMC; DEBUG_DWORD eax, "GCMC"
	call	newline


	BCM_REG_READ GLC; DEBUG_DWORD eax, "GLC"	# General Local Control
.macro PF r
	PRINTFLAG eax, BCM57_REG_GLC_\r, "\r "
.endm
	PF INT_ACTIVE
	PF CLEARINT
	PF SETING
	PF INT_ON_ATTN
	PF GPIO_UART_SEL
	PF USE_SIG_DETECT
	PF USE_EXT_SIG_DETECT
	PF GPIO_INPUT3	
	PF GPIO_OE3		
	PF GPIO_OUTPUT3	
	PF GPIO_INPUT0	
	PF GPIO_INPUT1	
	PF GPIO_INPUT2	
	PF GPIO_OE0	
	PF GPIO_OE1	
	PF GPIO_OE2	
	PF OUTPUT0
	PF OUTPUT1	
	PF OUTPUT2	
	PF EXTMEM_ENABLE 
	# MEMSZ_MASK/sizes here
	PF MEMSZ_BANK_SELECT 
	PF MEMSZ_SSRAM_TYPE 
	PF MEMSZ_AUTO_SEEPROM 
.purgem PF
	and	eax, BCM57_REG_GLC_MEMSZ_MASK
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_256K, "256K"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_512K, "512K"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_1M, "1M"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_2M, "2M"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_4M, "4M"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_8M, "8M"
	PRINTIF eax, BCM57_REG_GLC_MEMSZ_16M, "16M"

	call	newline
	popad
	ret

########################################################################
bcm57_alloc_buffers:
ret
	NIC_ALLOC_BUFFERS RX_BUFFERS, TX_BUFFERS, DESC_SIZE, 1600, 9f,_BUF_ALIGN
	#############################################################
	NIC_DESC_LOOP rx
	GDT_GET_BASE edx, ds
	add	edx, esi
	# set up [edi + 0..?]
	NIC_DESC_ENDL
	#############################################################
	NIC_DESC_LOOP tx
	GDT_GET_BASE edx, ds
	add	edx, esi
	# set up [edi + 0..?]
	NIC_DESC_ENDL
	#############################################################

	GDT_GET_BASE ecx, ds
	mov	eax, [ebx + nic_rx_desc]
	#add	eax, ecx
	#stosd	# bcm57_init_rdra
	#mov	eax, [ebx + nic_tx_desc]
	#add	eax, ecx
	#stosd	# bcm57_init_tdra

	clc
9:	ret


# in: ebx = pci_dev nic device
bcm57_read_mac:
	push_	eax ecx edx edi esi

	lea	edi, [ebx + nic_mac]
	mov	esi, [ebx + dev_mmio] # XXX TODO reloc/phys addr
	BCM_REG_READ MAC_ADDR0_HI #mov	eax, [esi + BCM57_MAC_ADDR0_HI]
	xchg	al, ah
	stosw
	BCM_REG_READ MAC_ADDR0_LO #mov	eax, [esi + BCM57_MAC_ADDR0_LO]
	bswap	eax
	stosd

	# HP: MAC prefix 00:0e:7f

	push	esi
	print_ "MAC: "
	lea	esi, [ebx + nic_mac]
	call	net_print_mac
	pop	esi
	call	newline

	# TODO: check vendor bytes in mac to see if card matches

	clc

	pop_	esi edi edx ecx eax
	ret


	###############
################################################################

# in: ebx = nic object
bcm57_ifup:
	ret

# in: ebx = nic object
bcm57_ifdown:
	ret

################################################################
# Interrupt Service Routine
bcm57_isr:
	pushad
	mov	ebx, edx	# see irq_isr and (dev_)add_irq_handler

	.if BCM57_DEBUG
		printc 0xf5, "NIC ISR"
	.endif

	mov	ecx, 100	# infinite loop bound

	# check what interrupts
0:
	loop	0b
0:

	.if BCM57_DEBUG
		call	newline
	.endif
########################################################################
	# EOI is handled by IRQ_SHARING code
	popad	# edx ebx eax
	iret

############################################################
# Send Packet

# in: ebx = nic device
# in: esi = packet
# in: ecx = packet size
bcm57_send:
	pushad
	incd	[ebx + nic_tx_count]
	add	[ebx + nic_tx_bytes + 0], ecx
	adcd	[ebx + nic_tx_bytes + 4], 0

	.if BCM57_DEBUG > 1
		DEBUG "bcm57_send"
		DEBUG_DWORD ecx
	.endif

	popad
	ret


# in: ebx = nic object
bcm57_print_status:
	printlnc 12, "print_status not implemented"
	ret


############################################################################

DRIVER_NIC_BCM57_SIZE =  . - DRIVER_NIC_BCM57_BEGIN
