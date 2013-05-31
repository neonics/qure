###############################################################################
# Ensoniq AudioPCI-97  #  1274 1371
#
# DOC/Specs/Ensoniq_ES1371_*.pdf
#
# There are many subsystem vendor id's to this one; the one with the same
# subsystem id's as the top level Id's is a Creative Sound Blaster
# AudioPCI64v/AudioPCI128.
#
# SPEC:
#
# 4 interactive subsystems:
#
# * PCI busmaster/slave
# * DMA control : 3 channel dma controller built in:
#      CCB (bus master cache control), PCI, Serial.
# * LEGACY
# * CODEC
#
.intel_syntax noprefix

DECLARE_PCI_DRIVER MM_AUDIO, es1371, 0x1274, 0x1371, "es1371", "Ensoniq AudioPCI-97"

DECLARE_CLASS_BEGIN es1371, dev_pci	# TODO: subclassing generic audio
DECLARE_CLASS_METHOD dev_api_constructor, es1371_init, OVERRIDE
DECLARE_CLASS_END es1371

##########################################
ES1371_REG_INT_CHIP_SELECT	= 0x00	# 8 bytes: interrupt/chip select
	# Address 0 [poweron value: 0x7ffffec0]
	# 31:26	R	not implemented, 1
	# 25:24 RW	Joystick port base addr: 0x200 + (.. * 8)
	# 23:20 R	GPIO_IN
	# 19:16 RW	GPIO_OUT
	# 15:	RW	MSFMTSEL - MPEG format: 0 = sonly, 1 = I2S.
	# 14:	RW	SYNC_RES - warm reset
	# 13:	RW	ADC_STOP - 0 = CCB transfer enabled; 1 disabled
	# 12:	RW	PWR_INTRM - interrupt mask for power management lvl chg
	# 11:	RW	M_CB record channel source: 0=CODEC ADC, 1=I2S
	# 10:	RW	CCB_INTERM interrupt mask for CCB voice: 0=dis,1=enabled
	# 9:8	RW	PDLEV - power down level: 00=D0, 01=D1,10=D2, 11=D3
	# 7	RW	BREQ - test: 1 = prevent CCB/SERIAL/UART/HOSTIF mem xs
	# 6	RW	DAC1_EN - enable DAC1 playback channel (CODEC FM DAC)
	# 5	RW	DAC2_EN - enable DAC2 playback channel (CODEC DAC)
	# 4	RW	ADC_EN - enable ADC playback channel (CODEC ADC)
			# for all 3: to restart a cannel, set low and then high
	# 3	RW	UART_EN: enable UART
	# 2	RW	JYSTK_EN: enable joystick module
	# 1	RW	XTALCKDIS - Xtal clock disable: 1=disable crystal clock
	# 0:	RW	PCICLKDIS - pci clock disable (except PCI/chip sel mod)
	#
	# Address 0x4: interrupt reason register
	# 31:	R	INTR - 1 interrupt from DAC[12],ADC,UART,CCP,PWR MGMT
	# 30:9	R	reserved - all 1
	# 8:	R	SYNC_ERR
	# 7:6	R	VC - voice code from ccb mod: 00=DAC1,01=DAC2,10=ADC.
	# 5:	R	MPWR - power level interrupt
	# 4:	R	MCCB masked CCB inter: 0=no, 1=CCB intr pending
	# 3:	R	UART
	# 2:	R	DAC1
	# 1:	R	DAC2
	# 0:	R	ADC
ES1371_REG_UART			= 0x08	# 4 bytes
	ES1371_REG_UART_DATA	= ES1371_REG_UART
	# address 0x08: [1 byte] UART Data register: MIDI serial data in/out
	ES1371_REG_UART_STATUS	= ES1371_REG_UART+1
	# address 0x09: [1 byte] UART status register: [read]
	# 15: 	R	RXINT receiver interrupt pending
	# 14:11	R	ZERO
	# 10:	R	TXINT transmitter interrupt pending
	# 9:	R	TXRDY transmitter ready
	# 8:	R	RXRDY receiver ready
	#
	ES1371_REG_UART_CONTROL	= ES1371_REG_UART+1
	# address 0x09 [1 byte] UART control register: [write]
	# 15	W	RXINTEN - UART rx interrupt enable bit
	# 14:13	W	TXINTEN ; 01: txrdy intr enabled; others undefined
	# 12:10	?	UDNEFINED
	# 9:8	W	CNTRL - UART control: 11 = software reset; others undef
	#
	# [NOTE: the bit numbers seem to be 8 too high!]
	#
	# address 0x0a: UART reserved register
	# 7:1	?	undefined
	# 0:	RW	TEST_MODE: uart clock switched to the faster pci clock.
	#
	# Address 0x0b: not specified.
ES1371_REG_HOSTIF_MEM_PAGE	= 0x0c	# 4 bytes: Host Interface - memory page
	# 31:4	?	udnefined
	# 3:0	RW	which MEMORY_PAGE (access: 0x30-0x3f); 
ES1371_REG_SAMPLE_RATE_CONVERTER= 0x10	# 4 bytes: Sample Rate Converter
	# 31:25	RW	SRC_RAM_ADR [7 bits]
	# 24	RW	SRC_RAM_WE - read/write contrl bit (WE=write enab?)
	# 23	R	SRC_RAM_BUSY
	# 22	RW	SRC_DISABLE
	# 21	RW	DIS_P1 - disable playback channel 1 accumulator
	# 20	RW	DIS_P2
	# 19	RW	DIS_REC - disable record channel accumulator
	# 18:16	RW	undefined
	# 15:0	RW	SRC_RAM_DATA data to read/write from mem @ SRC_RAM_ADDR
ES1371_REG_CODEC		= 0x14	# 4 bytes
	# 31:24	W	ZERO
	# 23	W	PIRD AC97 Codec register read/write control bit: 1=read
	# 22:16	W	PIADDR - address of codec reg to read/write
	# 15:0	W	PIDATA - data to be written; set to 0 for a read.
	# SAME REG: read register:
	# 31	R	RDY
ES1371_REG_LEGACY		= 0x18	# 8 bytes
	# 31	RW	JFAST 0=ISA joystick timing, 1=FAST timing
	# 30	RW	HIB - host interrupt blocking enable bit (req DMA cfg)
	# 29	RW	VSB - SB capture port range:0=220?H-22f?H;1=240?H-24f?H
	# 28:27	RW	VMPU - base reg capt rnge: 320xH-327xH + 0x100*bits
	# 26:25	RW	CDCD - CODEC capture addr range:
	#		  00=530x-537xH; 01=undef; 10=e80xH-e87xH;11=f40x-f47xH
	# 18	RW	SBCAP - sound blaster event capture
	ES1371_LEGACY_SB_CAP = 1<<18
ES1371_REG_SERIAL		= 0x20	# 16 bytes
ES1371_REG_HOSTIF_MEM		= 0x30	# 16 bytes: host interface - memory

.text32
es1371_init:
	I "es1371 Ensoniq AudioPCI-97"
	call	newline

#	call	dev_pci_busmaster_enable

	mov	dx, [ebx + dev_io]
	DEBUG_WORD dx
	in	eax, dx	# 0x0
	DEBUG_DWORD eax,"CONTROL"
	add	dx, 4
	in	eax, dx	# 0x4
	DEBUG_DWORD eax,"STATUS"
	DEBUG "UART"
	add	dx, 4
	in	al, dx	# 0x8
	DEBUG_BYTE al,"MIDI"
	inc	dx	# 0x9: write only control reg
	inc	dx	# 0xa: RO status
	in	al, dx
	DEBUG_BYTE al,"STATUS"
	call	newline
	inc	dx	# 0xb: uart reserved

	inc	dx	# 0xc
	DEBUG_WORD dx,"mem page reg"
	in	eax, dx
	DEBUG_DWORD eax,"MEMORY_PAGE"
	call	newline
	
	add	dx, 0x18#ES1371_REG_LEGACY
	in	eax, dx
	DEBUG_DWORD eax
	or	eax, 1<<18#ES1371_LEGACY_SB_CAP
	out	dx, eax
	in	eax, dx

	DEBUG_DWORD eax
	and	eax, 1<<29
	shr	eax, 27-8-2
	add	eax, 0x2200
	DEBUG_DWORD eax,"SB capture port"
	call	newline
.if 0
	mov	[sb_addr], ax

	call	sb_detect

	call	more
.endif
	ret

