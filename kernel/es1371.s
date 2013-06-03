##############################################################################
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

DECLARE_CLASS_BEGIN es1371, sound
DECLARE_CLASS_METHOD dev_api_constructor,	es1371_init, OVERRIDE
DECLARE_CLASS_METHOD sound_set_samplerate,	es1371_set_samplerate,	OVERRIDE
DECLARE_CLASS_METHOD sound_set_format,		es1371_set_format,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_init,	es1371_playback_init,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_start,	es1371_playback_start,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_stop,	es1371_playback_stop,	OVERRIDE
DECLARE_CLASS_END es1371

##########################################
ES1371_REG_INT_CHIP_SELECT	= 0x00	# 8 bytes: interrupt/chip select
ES1371_REG_CONTROL		= 0x00	# alternative name
	# Address 0 [poweron value: 0x7ffffec0]
	# 31:26	R	not implemented, 1
	# 25:24 RW	Joystick port base addr: 0x200 + (.. * 8)
	# 23:20 R	GPIO_IN
	# 19:16 RW	GPIO_OUT
	# 15	RW	MSFMTSEL - MPEG format: 0 = sonly, 1 = I2S.
	# 14	RW	SYNC_RES - warm reset
	ES1371_CTRL_SYNC_RES	= 0x40000
	# 13	RW	ADC_STOP - 0 = CCB transfer enabled; 1 disabled
	# 12	RW	PWR_INTRM - interrupt mask for power management lvl chg
	# 11	RW	M_CB record channel source: 0=CODEC ADC, 1=I2S
	# 10	RW	CCB_INTERM interrupt mask for CCB voice: 0=dis,1=enabled
	# 9:8	RW	PDLEV - power down level: 00=D0, 01=D1,10=D2, 11=D3
	# 7	RW	BREQ - test: 1 = prevent CCB/SERIAL/UART/HOSTIF mem xs
	# 6	RW	DAC1_EN - enable DAC1 playback channel (CODEC FM DAC)
	ES1371_CTRL_DAC1_EN	= 1<<6
	# 5	RW	DAC2_EN - enable DAC2 playback channel (CODEC DAC)
	ES1371_CTRL_DAC2_EN	= 1<<5
	# 4	RW	ADC_EN - enable ADC playback channel (CODEC ADC)
	ES1371_CTRL_ADC_EN	= 1<<4
			# for all 3: to restart a cannel, set low and then high
	# 3	RW	UART_EN: enable UART
	ES1371_CTRL_UART_EN = 1<<3
	# 2	RW	JYSTK_EN: enable joystick module
	ES1371_CTRL_JYSTK_EN = 1<<2
	# 1	RW	XTALCKDIS - Xtal clock disable: 1=disable crystal clock
	# 0:	RW	PCICLKDIS - pci clock disable (except PCI/chip sel mod)
	#

ES1371_REG_STATUS		= 0x04 # interrupt reason register
	ES1371_STAT_RESET	= 0x20000000
	# 31	R	INTR - 1 interrupt from DAC[12],ADC,UART,CCP,PWR MGMT
	# 30:9	R	reserved - all 1
	# 8	R	SYNC_ERR
	# 7:6	R	VC - voice code from ccb mod: 00=DAC1,01=DAC2,10=ADC.
	# 5	R	MPWR - power level interrupt
	# 4	R	MCCB masked CCB inter: 0=no, 1=CCB intr pending
	# 3	R	UART
	# 2	R	DAC1
	# 1	R	DAC2
	# 0	R	ADC
	ES1371_STAT_UART=1<<3
	ES1371_STAT_DAC1=1<<2
	ES1371_STAT_DAC2=1<<1
	ES1371_STAT_ADC	=1<<0

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
	# 3:0	RW	which 16 byte MEMORY_PAGE (access: 0x30-0x3f); 

# Sample Rate Covnerter:
ES1371_REG_SRC= 0x10	# 4 bytes: Sample Rate Converter
	# 31:25	RW	SRC_RAM_ADR [7 bits]
	ES1371_SRC_RAMADDR_SHIFT= 25
	ES1371_SRC_RAMADDR_MASK	= (0b1111111<<25)
	# 24	RW	SRC_RAM_WE - read/write contrl bit (WE=write enab?)
	ES1371_SRC_WE		= 1 << 24
	# 23	R	SRC_RAM_BUSY
	ES1371_SRC_BUSY		= 1 << 23

	# 22	RW	SRC_DISABLE
	ES1371_SRC_DISABLE	= 1 << 22
	# 21	RW	DIS_P1 - disable playback channel 1 accumulator
	ES1371_SRC_DDAC1	= 1 << 21
	# 20	RW	DIS_P2
	ES1371_SRC_DDAC2	= 1 << 20
	# 19	RW	DIS_REC - disable record channel accumulator
	ES1371_SRC_DADC		= 1 << 19

	ES1371_SRC_DIS_MASK = 0b1111 << 19
	# 18:16	RW	undefined
	# 15:0	RW	SRC_RAM_DATA data to read/write from mem @ SRC_RAM_ADDR

	# RAMADDR registers:
	ES1371_SRC_RAMADDR_DAC1		= 0x70	# aka _SYNTH_BASE
	ES1371_SRC_RAMADDR_DAC2		= 0x74	# DAC_BASE
	ES1371_SRC_RAMADDR_ADC		= 0x78	# ADC_BASE

	ES1371_SRC_RAMADDR_DAC1_LVOL	= 0x7c	# aka SYNTH_LVOL
	ES1371_SRC_RAMADDR_DAC1_RVOL	= 0x7d	# aka SYNTH_RVOL
	ES1371_SRC_RAMADDR_DAC2_LVOL	= 0x7e
	ES1371_SRC_RAMADDR_DAC2_RVOL	= 0x7f
	ES1371_SRC_RAMADDR_ADC_LVOL	= 0x6c
	ES1371_SRC_RAMADDR_ADC_RVOL	= 0x6d

	# These are relative to SRC_RAMADDR_(DAC[12]|ADC)
	ES1371_SRC_OFFS_TRUNC_N		= 0x00
	ES1371_SRC_OFFS_INT_REGS	= 0x01
	ES1371_SRC_OFFS_ACCUM_FRAC	= 0x02
	ES1371_SRC_OFFS_VFREQ_FRAC	= 0x03

	ES1371_SRC_FIFO_SYNTH		= 0x00
	ES1371_SRC_FIFO_DAC		= 0x20
	ES1371_SRC_FIFO_ADC		= 0x40

# SYNTH_FREEZE	= 1<<21
# DAC_FREEZE	= 1<<20
# ADC_FREEZE	= 1<<19


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
ES1371_REG_LEGACY2		= 0x1c	# undoc

#########################################
ES1371_REG_SERIAL		= 0x20	# 16 bytes
	# 31:23	RW	ones
	# 21:19	RW	P2_END_INC in loop mode add to smpl addr cnt;8bt:1,16b:2
	# 18:16 RW	P2_ST_INC same but for start/restart,may be 0
	# 15	RW	R1_LOOP_SEL: ADC loop(0)/stop(1) mode
	# 14	RW	P2_LOP_SEL: DAC2
	# 13	RW	P1_LOOP_SEL: DAC1
	ES1371_SERIAL_ADC_LOOP	= 1 <<15
	ES1371_SERIAL_DAC2_LOOP	= 1 <<14
	ES1371_SERIAL_DAC1_LOOP	= 1 <<13
	# 12	RW	P2_PAUSE: DAC2
	ES1371_SERIAL_DAC2_PAUSE= 1<<12
	# 11	RW	P1_PAUSE: DAC1
	ES1371_SERIAL_DAC1_PAUSE= 1<<11
	# 10	RW	R1_INT_EN: ADC interrupt enable(clear, then set)
	# 9	RW	P2_INTR_EN: DAC2
	# 8	RW	P1_INTR_EN: DAC1
	ES1371_SERIAL_ADC_INT_EN =1<<10
	ES1371_SERIAL_DAC2_INT_EN=1<<9
	ES1371_SERIAL_DAC1_INT_EN=1<<8
	# 7	RW	P1_SCT_RLD 1musec 1=reload sample counter
	# 6	RW	P2_DAC_SEN 0=play 0s;1=play last smp when disab&stop
	# 5	RW	R1_S_EB: ADC: 0=8 bit mode 1=16 bit mode
	# 4	RW	R1_S_MB: ADC: 0=mono 1=stereo
	# 3	RW	P2_S_EB: DAC2: 0=8 bit mode 1=16 bit mode
	# 2	RW	P2_S_MB: DAC2: 0=mono 1=stereo
	# 1	RW	P1_S_EB: DAC1: 0=8 bit mode 1=16 bit mode
	# 0	RW	P1_S_MB: DAC1: 0=mono 1=stereo
	ES1371_SERIAL_DAC1_8BIT	= 0<<1
	ES1371_SERIAL_DAC1_16BIT= 1<<1
	ES1371_SERIAL_DAC1_MONO	= 0<<0
	ES1371_SERIAL_DAC1_STEREO= 1<<0

ES1371_REG_SERIAL_DAC1_SC	= 0x24	# DAC1 sample count register
	# high word: CURR_SAMP_CT; low word: SAMP_CT
	# samples played = SAMP_CT - CURR_SAMP_CT
ES1371_REG_SERIAL_DAC2_SC	= 0x28
ES1371_REG_SERIAL_ADC_SC	= 0x2c

##########################################
ES1371_REG_HOSTIF_MEM		= 0x30	# 16 bytes: host interface - memory
# See ES1371_REG_HOSTIF_MEM_PAGE: select which memory page.
# Block 0: DAC 1
# memory page 0b0000: DAC1 sample bytes 15-0 lower half buffer
# memory page 0b0001: DAC1 sample bytes 31-16
# memory page 0b0010: DAC1 sample bytes 47-32 upper half buffer
# memory page 0b0011: DAC1 sample bytes 63-48
# Block 1: DAC 2
# memory page 0b0100: DAC2 sample bytes 15-0 lower half buffer
# memory page 0b0101: DAC2 sample bytes 31-16
# memory page 0b0110: DAC2 sample bytes 47-32 upper half buffer
# memory page 0b0111: DAC2 sample bytes 63-48
# Block 2: ADC
# memory page 0b1000: ADC sample bytes 15-0 lower half buffer
# memory page 0b1001: ADC sample bytes 31-16
# memory page 0b1010: ADC sample bytes 47-32 upper half buffer
# memory page 0b1011: ADC sample bytes 63-48
# Block 3: Frame/UART
# memory page 0b1100: DAC1, DAC2 frame buffer info
# memory page 0b1101: ADC frame buffer info (last 2 dwords unused)
# memory page 0b1110: UART fifo: 4 dwords, each 9 bits used.
# memory page 0b1111: UART fifo (idem)

ES1371_HOSTIF_MEM_PAGE_DAC_FB	= 0b1100# memory page 0b1100
ES1371_REG_HOSTIF_DAC1_F1	= 0x30	# DAC1 Frame Register 1
ES1371_REG_HOSTIF_DAC1_F2	= 0x34	# DAC1 Frame Register 2
ES1371_REG_HOSTIF_DAC2_F1	= 0x38	# phys sample buffer address
ES1371_REG_HOSTIF_DAC2_F2	= 0x3c	# hi: dwords transferred;lo:dword buflen

ES1371_HOSTIF_MEM_PAGE_ADC_FB	= 0b1101# memory page 0b1101
ES1371_REG_HOSTIF_ADC_F1	= 0x30	# ADC sample buffer phys addr
ES1371_REG_HOSTIF_ADC_F2	= 0x34	# hi: dwords transferred;lo:bufsize

ES1371_HOSTIF_MEM_PAGE_UART0	= 0b1110# 4 fifo dwords
ES1371_HOSTIF_MEM_PAGE_UART1	= 0b1111# 4 fifo dwords
ES1371_REG_HOSTIF_UART_FIFO0	= 0x30	# these 4 have the same layout:
ES1371_REG_HOSTIF_UART_FIFO1	= 0x34	# 31:9 not used
ES1371_REG_HOSTIF_UART_FIFO2	= 0x38	# bit 8: whether UART byte is valid
ES1371_REG_HOSTIF_UART_FIFO3	= 0x3c	# bits 7:0: UART rx'd MIDI byte


.text32
es1371_init:
	I "es1371 Ensoniq AudioPCI-97"
	call	newline

	push	ebx
	mov	[es1371_isr_dev$], ebx
	movzx	ax, byte ptr [ebx + dev_irq]
	mov	ebx, offset es1371_isr
	mov	cx, cs
.if IRQ_SHARING
	call	add_irq_handler
.else
	add	ax, IRQ_BASE
	call	hook_isr
.endif
	pop	ebx
	mov	al, [ebx + dev_irq]
	call	pic_enable_irq_line32
	

	.if 1
	call	dev_pci_busmaster_enable
	.else
	# enable SERR 0x0100, BUSMASTER 0x0004 and IO access 0x0001
	# Disabled: IO_SPACE already enabled (mmio device),
	# and: SERR has no effect. Therefore only busmaster is enabled.
	mov	eax, [ebx + dev_pci_addr]
	mov	ecx, eax
	push	ebx
	mov	bl, PCI_CFG_STATUS_COMMAND
	call	pci_read_config
	or      eax, PCI_CMD_BUSMASTER | PCI_CMD_IO_SPACE | PCI_CMD_SERR_NR_ENABLE
	DEBUG_DWORD eax,"EXPECT:"
	mov	edx, eax
	mov	bl, PCI_CFG_STATUS_COMMAND
	mov	eax, ecx
	call	pci_write_config
	DEBUG_DWORD eax,"PCI STATUS"
	pop	ebx
	.endif

# minix:
	mov	dx, [ebx + dev_io]
	xor	eax, eax
	out	dx, eax	# turn off
	in eax, dx; DEBUG_DWORD eax,"reg0"

	add	dx, ES1371_REG_LEGACY
	out	dx, eax
	add	dx, 4	# REG_LEGACY2 
	out	dx, eax

	add	dx, ES1371_REG_SERIAL - ES1371_REG_LEGACY2
	out	dx, eax

	mov	dx, [ebx +dev_io]
	in	eax, dx
	DEBUG_DWORD eax, "CTRL"
	or	eax, 0x0100 # XCTL0
	or	eax, 0x0002 # CDC_EN
	out	dx, eax	#enable codec

	#####################

	# clear mem:
	add	dx, ES1371_REG_HOSTIF_MEM_PAGE
	mov	ecx, 0x10
	xor	eax, eax
0:	out	dx, eax
	push_	ecx edx
	mov	ecx, 0x10
	add	dx, ES1371_REG_HOSTIF_MEM
1:	out	dx, eax
	inc	dx
	loop	1b
	pop_	edx ecx
	inc	eax
	loop	0b

	#######################
	# start

	# set sample rate
	call	es1371_src_init # Set up the Sample Rate Converter

	# set stereo
	# set bits
	# set sign
	# set int cnt
	# resume:
	#   reenable int
	#   clar pause bit in SERIAL CTRL
	mov	al, 0b11	# 16 bit stereo
	call	es1371_set_format
	mov	eax, 44100
	call	es1371_set_samplerate

.if 0
	# warm reset
	mov	dx, [ebx + dev_io]
	mov	eax, ES1371_CTRL_SYNC_RES
	out	dx, eax
	in	eax, dx	# 1 musec delay
	in	eax, dx	# 1 musec delay
	xor	eax, eax
	out	dx, eax
	in	eax, dx
	DEBUG_DWORD eax,"control after reset"

	DEBUG "UART"
	add	dx, ES1371_REG_UART
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
.endif

	ret

###########################################
.data SECTION_DATA_BSS
es1371_isr_dev$: .long 0
.text32
es1371_isr:
	push_	eax ebx ecx edx esi edi ds es
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax
	mov	ebx, [es1371_isr_dev$]
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_STATUS
	in	eax, dx
	test	eax, 1<<31
	jz	9f

	test	eax, ES1371_STAT_DAC1
	jz	1f

	add	dx, ES1371_REG_SERIAL - ES1371_REG_STATUS
	in	eax, dx
	test	eax, ES1371_SERIAL_DAC1_INT_EN
	jz	1f

	# reset interrupt bit: write 0, then re-enable.
	and	eax, ~ES1371_SERIAL_DAC1_INT_EN
	out	dx, eax
	or	eax, ES1371_SERIAL_DAC1_INT_EN
	out	dx, eax

	# must do this before calling the handler, which may use interrupts.
	.if !IRQ_SHARING
		PIC_SEND_EOI [ebx + dev_irq]
	.endif

	mov	ecx, [ebx + sound_playback_handler]
	jecxz	1f
	pushad
	call	ecx
	popad
1:
9:
	pop_	es ds edi esi edx ecx ebx eax
	iret


#########################################################################
es1371_set_samplerate:
	jmp	es1371_set_dac1_rate

# in: al: bit1 = 16bit; bit 0=stereo
es1371_set_format:
	push_	edx ecx
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SERIAL
	mov	cl, al
	in	eax, dx
	and	eax, ~3	# reset to 8 bit mono
	or	al, cl #ES1371_SERIAL_DAC1_STEREO | ES1371_SERIAL_DAC1_16BIT
	out	dx, eax
	pop_	ecx edx
	ret

# in: eax = playback handler
es1371_playback_init:
	push	edx
	mov	[ebx + sound_playback_handler], eax
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SERIAL
	in	eax, dx
	and	eax, ~(ES1371_SERIAL_DAC1_PAUSE)
	out	dx, eax
	# enable ints for DAC1
	in	eax, dx
	and	eax, ~(ES1371_SERIAL_DAC1_INT_EN)
	out	dx, eax
	in	eax, dx	# 1 microsec delay
	or	eax, ES1371_SERIAL_DAC1_INT_EN
	out	dx, eax
	pop	edx
	ret

es1371_playback_start:
	push_	edx ecx
	# set up the sample count
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SERIAL
	in	eax, dx	
	and	eax, 3	# mask the 16bit stereo bits
	mov	cl, al
	shr	cl, 1
	and	al, 1
	add	cl, al	# count the bits: 2

	add	dx, ES1371_REG_SERIAL_DAC1_SC - ES1371_REG_SERIAL
	mov	eax, [dma_buffersize]
	shr	eax, cl		# adjust for 16 bit, stereo
	shr	eax, 1	# two ints per buffer.. hopefully
	out	dx, ax

	xor	eax, eax	# phys buffer addr
	mov	eax, [dma_buffer_abs]
	mov	ecx, [dma_buffersize] # buf len (will be /=4)
	call	es1371_set_dma_dac1

	# play
	mov	dx, [ebx + dev_io]	# control reg
	in	eax, dx
	or	eax, ES1371_CTRL_DAC1_EN
	out	dx, eax
	pop_	ecx edx
	ret

es1371_playback_stop:
	push	edx
	mov	dx, [ebx + dev_io]
	in	eax, dx
	and	eax, ~ES1371_CTRL_DAC1_EN
	out	dx, eax
	pop	edx
	ret

#########################################################################
# Sample Rate Converter methods
# reference: http://www.cs.fsu.edu/~baker/devices/lxr/http/source/linux/sound/oss/es1371.c?v=2.6.11.8
# reference: http://faculty.qu.edu.qa/rriley/cmpt507/minix/sample__rate__converter_8c-source.html

es1371_src_init:
	push_	edx ecx eax esi
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC

	call	es1371_src_wait_ready$	# out: eax=value
	jc	9f
	push	eax
	mov	eax, ES1371_SRC_DISABLE
	out	dx, eax
	pop	eax

	# write 0 to SRC RAMADDR 0..7f
	mov	ecx, 0x80
	xor	esi, esi	# top 7 bits: ramaddr
	# es1371_src_write unpacked:
0:	call	es1371_src_wait_ready$	# out: eax=value
	jc	9f
	# preserve these bits
	and	eax, ES1371_SRC_DIS_MASK
	or	eax, ES1371_SRC_WE	# write enable
	or	eax, esi
	out	dx, eax
	add	esi, 1<<ES1371_SRC_RAMADDR_SHIFT # inc addr
	loop	0b

	_ES1371_SRC_WRITE_LASTVAL = 0
	.macro ES1371_SRC_WRITE val, base, off=0
		.if _ES1371_SRC_WRITE_LASTVAL != \val
		mov	dx, \val
		.endif
		_ES1371_SRC_WRITE_LASTVAL = \val
		.ifc \off,0
		mov	al, ES1371_SRC_RAMADDR_\base
		.else
		mov	al, ES1371_SRC_RAMADDR_\base + ES1371_SRC_OFFS_\off
		.endif
		call	es1371_src_write
		jc	9f
	.endm

	ES1371_SRC_WRITE 16<<4,  DAC1, TRUNC_N
	ES1371_SRC_WRITE 16<<10, DAC1, INT_REGS
	ES1371_SRC_WRITE 16<<4,  DAC2, TRUNC_N
	ES1371_SRC_WRITE 16<<10, DAC2, INT_REGS
	ES1371_SRC_WRITE 1<<12, DAC1_LVOL
	ES1371_SRC_WRITE 1<<12, DAC1_RVOL
	ES1371_SRC_WRITE 1<<12, DAC2_LVOL
	ES1371_SRC_WRITE 1<<12, DAC2_RVOL
	ES1371_SRC_WRITE 1<<12, ADC_LVOL
	ES1371_SRC_WRITE 1<<12, ADC_RVOL

	.purgem ES1371_SRC_WRITE

	# max/fixed rate is 48kHz
	mov	eax, 44100#22050
	call	es1371_set_adc_rate
	mov	eax, 44100#22050
	call	es1371_set_dac1_rate
	mov	eax, 44100#22050
	call	es1371_set_dac2_rate

	# enable
	call	es1371_src_wait_ready$
	jc	9f
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC
	xor	eax, eax
	out	dx, eax

9:	pop_	esi eax ecx edx
	ret

es1371_bound_smprate$:
	cmp	eax, 48000
	jbe	1f
	mov	eax, 48000
1:	cmp	eax, 4000
	jae	1f
	mov	eax, 4000
1:	ret

es1371_set_adc_rate:
	push_	edx eax ecx
	push	ebp
	mov	ebp, esp
	sub	esp, 12

	call	es1371_bound_smprate$
	xor	edx, edx
	mov	ecx, 3000
	div	ecx
	mov	ecx, eax	# cl = n = 3000/rate
	mov	[ebp - 4], ecx
	mov	eax, 1
	shl	eax, cl
	test	eax, (1<<15)|(1<<13)|(1<<11)|(1<<9)
	jz	1f
	dec	ecx
1:	

	# truncm = (21*n-1)|1
#ebp-8	# freq = ((48000<<15) / rate) *n


	cmp	eax, 24000	# eax = rate (the argument)
	jb	1f
	cmp	edx, 239	# edx = truncm
	jbe	2f
	mov	edx, 239
2:	neg	edx
	add	edx, 239
	sar	edx, 1
	shl	edx, 9
	jmp	3f

1:	cmp	edx, 119
	jb	2f
	mov	edx, 119
2:	neg	edx
	add	edx, 119
	sar	edx, 1
	shl	edx, 9
	or	dx, 0x8000

3:	shl	ecx, 4
	or	edx, ecx
	mov	al, ES1371_SRC_RAMADDR_ADC+ES1371_SRC_OFFS_TRUNC_N
	call	es1371_src_write

	mov	al, ES1371_SRC_RAMADDR_ADC+ES1371_SRC_OFFS_INT_REGS
	push	eax
	call	es1371_src_read
	pop	eax
	xor	dh, dh	# mask, dl = value
	push	ecx
	mov	ecx, [ebp - 8]	# freq
	shr	ecx, 5
	and	ecx, 0xfc00
	or	dx, cx
	call	es1371_src_write
	pop	ecx

	mov	al, ES1371_SRC_RAMADDR_ADC+ES1371_SRC_OFFS_VFREQ_FRAC
	mov	dx, cx
	and	dx, 0x7fff
	call	es1371_src_write

	mov	al, ES1371_SRC_RAMADDR_ADC_LVOL
	xor	dl, dl
	mov	dh, [ebp - 4]	# n
	call	es1371_src_write
	inc	al
	call	es1371_src_write

	mov	esp, ebp
	pop	ebp
	pop_	ecx eax edx
	ret

# in: eax = samplerate
# in: ebx = dev
es1371_set_dac1_rate:
	push	ecx
	mov	cl, ES1371_SRC_RAMADDR_DAC1
	call	es1371_set_dac_rate$
	pop	ecx
	ret

# in: eax = samplerate
# in: ebx = dev
es1371_set_dac2_rate:
	push	ecx
	mov	cl, ES1371_SRC_RAMADDR_DAC2
	call	es1371_set_dac_rate$	# TODO: use cl
	pop	ecx
	ret

# in: eax = samplerate
# in: ebx = dev
# in: cl = DAC1 or DAC2 - TODO!
es1371_set_dac_rate$:
	push_	esi edi
	call	es1371_bound_smprate$
	mov	esi, eax	# backup

	# disable channel
	call	es1371_src_wait_ready$
	jc	9f
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC
	and	eax, ES1371_SRC_DIS_MASK
	or	eax, ES1371_SRC_DDAC1	# disable
	out	dx, eax

	# calc freq
	xor	edx, edx
	mov	eax, esi
	shl	eax, 16
	mov	edi, 3000
	div	edi
	mov	edi, eax	# freq = (rate<<16)/3000

	mov	al, ES1371_SRC_RAMADDR_DAC1 + ES1371_SRC_OFFS_INT_REGS
	call	es1371_src_read	# out: ax = value
	jc	9f
	mov	edx, edi
	shr	edx, 6
	and	edx, 0xfc00
	mov	dl, al	# the value read - preserving
	mov	al, ES1371_SRC_RAMADDR_DAC1 + ES1371_SRC_OFFS_INT_REGS
	call	es1371_src_write
	jc	9f
	
	mov	al, ES1371_SRC_RAMADDR_DAC1 + ES1371_SRC_OFFS_VFREQ_FRAC
	mov	edx, edi
	shr	edx, 1
	call	es1371_src_write
	jc	9f

	# enable channel
	call	es1371_src_wait_ready$
	jc	9f
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC
	and	eax, ES1371_SRC_DIS_MASK & ~(ES1371_SRC_DDAC1)
	out	dx, eax

9:	pop_	edi esi
	ret

###########################################################
# in: ebx = dev
# in: eax = buffer address
# in: ecx = buffer len 
es1371_set_dma_dac1:
	push	edx
	push	eax
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_HOSTIF_MEM_PAGE
	mov	al, ES1371_HOSTIF_MEM_PAGE_DAC_FB	# for DAC1 and DAC2
	out	dx, al	# select mem page
	add	dx, ES1371_REG_HOSTIF_MEM - ES1371_REG_HOSTIF_MEM_PAGE
	pop	eax
	# for DAC2: add dx, 8
	out	dx, eax	# write address
	add	dx, 4
	mov	eax, ecx
	shr	eax, 2
	dec	eax
	out	dx, eax
	pop	edx
	ret
###########################################################

# in: al = SRC RAMADDR to write (7 bits)
# in: dx = value
es1371_src_write:
	push	edx
	shl	al, 1
	or	al, 1
	jmp	es1371_src_rw$

# in: al = SRC RAMADDR
# out: eax = value (ax = data)
es1371_src_read:
	push	edx
	xor	edx, edx
	shl	al, 1

# in: al = [7:1 = SRC RAMADDR][0: 0=read 1=write]
# in: dx = value to write (0 for read)
# out: eax = value (ax = data)
es1371_src_rw$:
	push	edi
	mov	edi, eax
	shl	edi, ES1371_SRC_RAMADDR_SHIFT-1 # 25-1
	mov	di, dx
	call	es1371_src_wait_ready$	# out: eax = read value
	jc	9f
	and	eax, ES1371_SRC_DIS_MASK# preserve enable/disable bits
	or	eax, edi		# add the RAMADDR top 7 bits 
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC
	out	dx, eax			# write the address & read command
	call	es1371_src_wait_ready$	# out: eax = read value
9:	pop	edi
	pop	edx
	ret


es1371_src_wait_ready$:
	push_	ecx edx
	mov	dx, [ebx + dev_io]
	add	dx, ES1371_REG_SRC
	mov	ecx, 0x10000
0:	in	eax, dx
	test	eax, ES1371_SRC_BUSY
	jz	1f
	loop	0b
	DEBUG_DWORD eax
	printlnc 4, "es1371 SRC busy timeout"
	stc
1:	pop_	edx ecx
	ret
