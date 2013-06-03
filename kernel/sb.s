###############################################################################
#
#       Written 1995, 2013
#
#
#   This unit provides flexible SoundBlaster (mono/Pro/16/16ASP/AWE32)
# controling procedures.
#
#
.intel_syntax noprefix

SB_DEBUG = 0

###############################################################################

#select input
SB_LineIn	= 6
SB_MicIn	= 0
SB_CDIn 	= 2

#	SB io addresses (add to base adress)
FMLStatusPort		= 0x00
FMLAddressPort		= 0x00
FMLDataPort		= 0x01
FMRStatusPort		= 0x02
FMRAddressPort		= 0x02
FMRDataPort		= 0x03
MixAddressPort		= 0x04
MixDataPort		= 0x05
DSPResetPort		= 0x06	# DSP Reset
FMAddressPort		= 0x08
FMStatusPort		= 0x08
FMDataPort		= 0x09
sb_dsp_readPort		= 0x0A 	# DSP Read
sb_dsp_writePort	= 0x0C 	# DSP Write (cmd/data/write-buffer status [bit7]
DSPRStatusPort		= 0x0E	# DSP read-buffer status[bit7], DSP IRQ ack
DSPIrqAck8Port		= 0x0E
DSPIrqAck16Port 	= 0x0F
CDROMDataPort		= 0x10 	# all CDrom = Pro only
CDROMStatusPort 	= 0x11
CDROMResetPort		= 0x12
CDROMEnablePort 	= 0x13
ADLIBStatusPort 	= 0x388
ADLIBAddressPort	= 0x388
ADLIBDataPort		= 0x389

# Mixer registers
Mix_Reset		= 0x000			#Write	     SBPro
Mix_Status		= 0x001			#Read	     SBPro
Mix_Master_VolumePro	= 0x002			#Read/Write  SBPro Only
Mix_Voice_Volume	= 0x004			#Read/Write  SBPro
Mix_FM_Output_Control	= 0x006			#Read/Write  SBPro Only
Mix_Microphone_Level	= 0x00A			#Read/Write  SBPro
Mix_Input_Select	= 0x00C    #also filter sel.	#Read/Write  SBPro Only
Mix_Output_Select	= 0x00E    #also stereo sel.	#Read/Write  SBPro Only
Mix_Master_Volume	= 0x022			#Read/Write  SBPro
Mix_FM_Level		= 0x026			#Read/Write  SBPro
Mix_CD_Level		= 0x028			#Read/Write  SBPro
Mix_LineIn_Level	= 0x02E			#Read/Write  SBPro
Mix_Master_Volume_Left	= 0x030			#Read/Write  SB16
Mix_Master_Volume_Right = 0x031			#Read/Write  SB16
Mix_DAC_Level_Left	= 0x032			#Read/Write  SB16
Mix_DAC_Level_Right	= 0x033			#Read/Write  SB16
Mix_FM_Level_Left	= 0x034			#Read/Write  SB16
Mix_FM_Level_Right	= 0x035			#Read/Write  SB16
Mix_CD_Level_Left	= 0x036			#Read/Write  SB16
Mix_CD_Level_Right	= 0x037			#Read/Write  SB16
Mix_LineIn_Level_Left	= 0x038			#Read/Write  SB16
Mix_LineIn_Level_Right	= 0x039			#Read/Write  SB16
Mix_Microphone_Level16	= 0x03A			#Read/Write  SB16
Mix_PC_Speaker_Level	= 0x03B			#Read/Write  SB16
Mix_Output_Control	= 0x03C			#Read/Write  SB16
Mix_Input_Control_Left	= 0x03D			#Read/Write  SB16
Mix_Input_Control_Right = 0x03E			#Read/Write  SB16
Mix_Input_Gain_Control_Left   = 0x03F			#Read/Write  SB16
Mix_Input_Gain_Control_Right  = 0x040			#Read/Write  SB16
Mix_Output_Gain_Control_Left  = 0x041			#Read/Write  SB16
Mix_Output_Gain_Control_Right = 0x042			#Read/Write  SB16
Mix_Automatic_Gain_Control    = 0x043			#Read/Write  SB16
Mix_Treble_Left 	= 0x044			#Read/Write  SB16
Mix_Treble_Right	= 0x045			#Read/Write  SB16
Mix_Bass_Left		= 0x046			#Read/Write  SB16
Mix_Bass_Right		= 0x047			#Read/Write  SB16
Mix_IRQ_Select		= 0x080			#Read/Write  SB16
Mix_DMA_Select		= 0x081			#Read/Write  SB16
Mix_IRQ_Status		= 0x082			#Read	     SB16


#  Mixer source values for high-level mixer control
MIXmaster		=	0
MIXvoice		=	1
MIXfm			=	2
MIXline 		=	3
MIXcd			=	4
MIXgain 		=	5
MIXtreble		=	6
MIXbass 		=	7
MIXin_gain		=	8
MIXmicrophone		=	9
MIXspeaker		=    10
MIXleft 		=	1
MIXright		=	2
MIXboth 		=	3

#  Mixer output controls for SB16
CD_OUT			=	CD_OUT_L+CD_OUT_R
LINE_OUT		=	LINE_OUT_L+LINE_OUT_R
MIC_OUT 		=	1
CD_OUT_L		=	4
CD_OUT_R		=	2
LINE_OUT_L		=    16
LINE_OUT_R		=	8

#  Mixer input controls (for SB16)
FM_IN			=	0x60
LINE_IN 		=	0x18
CD_IN			=	0x06
MIC_IN			=	0x01
FM_IN_L 		=	0x40
FM_IN_R 		=	0x20
LINE_IN_L		=	0x10
LINE_IN_R		=	0x08
CD_IN_L 		=	0x04
CD_IN_R 		=	0x02


#there are actually 59 commands. (sblaster.doc)..
# Soundblaster Basic commands
DSPDirect8BitDAC	= 0x10
DSPDirectADC		= 0x20
DSPSilenceDAC		= 0x80	#plays some silent dac bytes and IRQ's.
DSPStartDMA8BitDAC	= 0x14
DSPStartDMAADC		= 0x24
DSPSpeakerOn		= 0xD1
DSPSpeakerOff		= 0xD3
DSPGetID		= 0xE0
DSPGetVersion		= 0xE1	# 4+: SB16
DSPGetCopy0xrigt 	= 0xE3
DSPSetTimeConstant	= 0x40
DSPPause8DMA		= 0xD0	# pause 8bit DMA initiated by 0xC?
DSPContinue8DMA		= 0xD4	# continue paused by 0xD0

DSP_CMD_GEN_INT		= 0xf2	# generate an interrupt

# Soundblaster 2.0 and Pro commands
DSPSetHSDMASize 	= 0x48
DSPStartAutoInitHSDMA	= 0x90
DSPStartHSDMA		= 0x91	#maybe same as above..
DSPStartHSADCDMA	= 0x99
DSPStartAutoInitHSDMAR	= 0x98

# Soundblaster Pro commands
DSPSBProADCStereo	= 0xA8
DSPSBProADCMono 	= 0xA0

# Soundblaster 16 commands
DSPSB16SetSpeedIn 	= 0x41	# sample rate: hi, lo
DSPSB16SetSpeedOut 	= 0x42	# sample rate: hi, lo


# 0xB?: program 16-bit DMA: command, mode, lo(len-1), hi(len-1)
	DSP_CMD_START_DMA16	= 0xb0
	DSP_CMD_START_DMA8	= 0xc0

# bit 0: always 0;
# bit 1: FIFO on;
# bit 2: 0=SC(single cycle), 1=AI (auto-initialized);
# bit 3: 0=D->A, 1=A->D
		DSP_DMA_FIFO		= (1<<1)
		DSP_DMA_SC		= (0<<2)
		DSP_DMA_AI		= (1<<2)
		DSP_DMA_PLAYBACK	= (0<<3)
		DSP_DMA_RECORD		= (1<<3)
# B8: sincle cycle in; b0: single cycle out
# Be: auto in; B6: auto out 
# MODE: 1<<4: 0=unsigned, 1=signed; 1<<5: 1=stereo
	DSP_MODE_UNSIGNED	= 0<<4
	DSP_MODE_SIGNED		= 1<<4
	DSP_MODE_MONO		= 0<<5
	DSP_MODE_STEREO		= 1<<5
DSPSB16Start16AutoDMA	= 0xB6	# auto-init playback
DSPSB16Start16SingleDMA	= 0xB0	# auto-init playback
DSPSB16Start16ADCDMA	= 0xBE	# auto-init record

	DSP_CMD_START_DMA16_AI_PLAY	= DSP_CMD_START_DMA16|DSP_DMA_AI|DSP_DMA_FIFO
	DSP_CMD_START_DMA8_AI_PLAY	= DSP_CMD_START_DMA8 |DSP_DMA_AI|DSP_DMA_FIFO

	DSP_CMD_START_DMA16_SC_PLAY	= DSP_CMD_START_DMA16|DSP_DMA_SC|DSP_DMA_FIFO
	DSP_CMD_START_DMA8_SC_PLAY	= DSP_CMD_START_DMA8 |DSP_DMA_SC|DSP_DMA_FIFO

# 0xC?: same as 0xB except for 8 bit dma
DSPSB16Start8DMA	= 0xC6
DSPSB16Start8ADCDMA	= 0xCE

DSPSB16Stereo		= 0x20
DSPSB16Mono		= 0x00
DSPSB16StereoSign	= 0x30
DSPSB16MonoSign 	= 0x10

DSPSB16Pause16DMA	= 0xD5	# pause, initiated by 0xB?
DSPSB16Continue16DMA	= 0xD6	# continue, paused 0xD4
DSPSB16Stop16AutoDMA	= 0xD9	# after current block
DSPSB16Stop8AutoDMA	= 0xDA	# after current block

DSPSB16Cont8DMA 	= 0x45
DSPSB16Cont16DMA	= 0x47


# Defines for 8237 DMA Controller IO addresses */
DMABase0Port		= 0
DMACount0Port		= 1
DMABase1Port		= 2
DMACount1Port		= 3
DMABase2Port		= 4
DMACount2Port		= 5
DMABase3Port		= 6
DMACount3Port		= 7
DMAStatusPort		= 8
DMACommandPort		= 8
DMARequestPort		= 9
DMAMaskPort		= 10
DMAModePort		= 11
DMAFFPort		= 12
DMATMPPort		= 13
DMAClearPort		= 13
DMAClearMaskPort	= 14
DMAWriteMask		= 15
DMAPagePort		= 0x80


#############################################################################
DECLARE_CLASS_BEGIN sb, sound	# extends dev_pci, but we ignore that
DECLARE_CLASS_METHOD dev_api_constructor,	sb_dev_init,		OVERRIDE
DECLARE_CLASS_METHOD sound_set_samplerate,	sb_dev_set_samplerate,	OVERRIDE
DECLARE_CLASS_METHOD sound_set_format,		sb_dev_set_format,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_init,	sb_dev_playback_init,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_start,	sb_dev_playback_start,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_stop,	sb_dev_playback_stop,	OVERRIDE
DECLARE_CLASS_END sb
.text32

#############################
# in: ebx = class_sb instance
sb_dev_init:
	I "SoundBlaster constructor"
	call	newline
	call	sb_detect
	ret

# in: eax = samplerate
sb_dev_set_samplerate:
	#mov	[ebx + sound_samplerate], ax
	mov	[SB_SampleRate], word ptr 44100
	ret

# in: al = [0: 0=mono, 1=stereo][1: 0=8bit 1=16 bit]
sb_dev_set_format:
	mov	ah, al
	and	ah, 1
	neg	ah	# becomes 0 or -1
	mov	[SB_Stereo], ah

	mov	ah, 8
	test	al, 1
	mov	al, [sb_dma8]
	jz	1f
	add	ah, ah
	mov	al, [sb_dma16]
1:	mov	[SB_Bits_Sample], ah
	mov	[SB_DMA], al
	ret

# in: ebx = dev
# in: eax = handler
sb_dev_playback_init:
	mov	[ebx + sound_playback_handler], eax
	mov	[sb_dev$], ebx	# so ISR can find the handler
	jmp	sb_playback_init

sb_dev_playback_start:
	jmp	sb_dma_transfer

sb_dev_playback_stop:
	jmp	SB_ExitTransfer

#############################




sb_dsp_write:
	push_	dx ecx ax
	mov	ah, al	# value to write
	mov	dx, word ptr [sb_addr]
	add	dl, 0x0c	# R=status W=write
	mov	ecx, 1000
0:	in	al, dx
	or	al, al
	jns	1f
	loop	0b
	stc
	jmp	9f
1:	mov	al, ah
	out	dx, al
	clc
9:	pop_	ax ecx dx
	ret

sb_dsp_read:
	push_	dx ecx
	mov	dx, word ptr [sb_addr]
	add	dl, DSPRStatusPort
	mov	ecx, 1000
0:	in	al, dx
	or	al, al
	js	1f
	loop	0b
	stc
	jmp	9f
1:	sub	dl, 4	# 0xa = read port
	in	al, dx
	clc
9:	pop_	ecx dx
	ret

sb_dsp_reset:
	push_	ax ecx dx
	mov	dx, word ptr [sb_addr]
	mov	al, 1		# start the dsp reset.
	add	dx, 6
	out	dx, al
	mov	ecx, 40*10       # wait 3 microsec.
0:	in	al, dx
	loop	0b
	mov	al, 0		# stop the dsp reset.
	out	dx, al
	add	dx, 8		# check for 0xaa response.
	mov	ecx, 100*10	# max 100 microseconds
0:	in	al, dx		# check read ready
	and	al, 0x80
	jz	1f
	sub	dx, 4		# dsp port is ready to be read.
	in	al, dx		# read and check for 0xaa
	add	dx, 4
	cmp	al, 0x0aa
	clc
	jz	9f
1:	loop	0b
	stc
9:	pop_	dx ecx ax
	ret



# in: al=addr
# out: ah
sb_mixer_read:
	push_	dx cx ax
	mov	dx, word ptr [sb_addr]
	add	dx, MixAddressPort    #4: selection register.
	out	dx, al
	mov	ecx, 6
0:	in	al, dx
	loop	0b
	inc	dx	    #Data reg
	in	al, dx
	mov	cl, al
	pop	ax
	mov	ah, cl
	pop_	cx dx
	ret

# in: al=reg, ah=byte
sb_mixer_write:
	push_	dx cx
	mov	dx, word ptr [sb_addr]
	add	dx, MixAddressPort    #4: selection register.
	out	dx, al
	mov	ecx, 6
0:	in	al, dx
	loop	0b
	inc	dx	    #Data reg
	mov	al, ah
	out	dx, al
	dec	dx
	mov	ecx, 35
0:	in	al, dx
	loop	0b
	pop_	cx dx
	ret

sb_detect:
	call	sb_detect_addr
	jc	4f
	call	sb_detect_irq
	jc	4f
	call	sb_detect_dma
	jc	4f
	call	sb_reset

	# version override:
	mov	al, [sb_version_]
	or	al, al
	jz	1f
	mov	[sb_version], al
1:
	# samplerate override:
	mov	ax, [SB_SampleRate_]
	or	ax, ax
	jnz	1f
	mov	ax, -1
1:	mov	[SB_SampleRate], ax

	cmp	[sb_version], byte ptr 3
	jae	1f		#not a card wich supports only
	mov	[SB_Stereo], byte ptr 0	#mono. stereo cards def. stereo.
1:	call	sb_calc_samplerate
	clc
4:	ret


sb_calc_samplerate:
	push_	eax ecx edx

	movzx	eax, word ptr [SB_SampleRate]

	cmp	ax, 4000
	jae	1f
	mov	ax, 4000
1:	call	sb_check_samplerate$

	movzx	ecx, ax			#calc timerconst for excact
	mov	eax, 1000000		#samplerate..
	xor	edx, edx
	div	ecx			#al=timerconst
	movzx	ecx, al
0:	mov	eax, 1000000
	xor	edx, edx
	div	ecx			#eax=smprate

	call	sb_check_samplerate$
	jc	@@Sure$
	inc	cl
	jmp	0b

@@Sure$:cmp	[sb_version], byte ptr 3
	jb	1f	#!!!!!!! jnz! want sb4 kan 44k!
	shr	cl, 1
1:	neg	cl
	mov	[TimeConstant], cl
	mov	[SB_SampleRate], ax
	pop_	edx ecx eax
	ret
#sb_calc_samplerate	EndP


sb_check_samplerate$:
	cmp	[sb_version], byte ptr 1
	jz	22f		#mono, max 22kHz
	cmp	[sb_version], byte ptr 2
	jz	44f		#mono, max 44kHz
	cmp	[sb_version], byte ptr 3
	ja	44f		#above: mono/stereo 44kHz
	cmp	[SB_Stereo], byte ptr 0
	jz	44f		#mono$: 44kHz. Stereo 22kHz.

22:	cmp	eax, 22000
	jb	1f
	mov	eax, 22000
	jmp	1f

44:	cmp	eax, 44000
	jbe	1f
	mov	eax, 44000
1:	mov	[SB_SampleRate], ax     #carry=ok, noc=changed
	ret


# in: [sb_addr], -1 for auto-detect
# out: [sb_version]
# out: CF
sb_detect_addr:
	push	eax

	call	sb_reset
	jc	9f

	mov	al, DSPDirect8BitDAC	#standard..
	call	sb_dsp_write
	mov     al, DSPSilenceDAC
	call    sb_dsp_write

	mov	al, DSPGetVersion
	call	sb_dsp_write
	call	sb_dsp_read
	mov	ah, al
	call	sb_dsp_read
	ror	ax, 8
	mov	word ptr [sb_version], ax
	clc
	pop	eax
	ret
9:	printc 4, "sb_reset err"
	pop	eax
	ret


sb_reset:
	cmp	word ptr [sb_addr], -1
	jz	1f
	call	sb_dsp_reset
	jnc	9f
	# auto detect
1:	mov	word ptr [sb_addr], 0x210
0:	call	sb_dsp_reset
	jnc	9f
	add	word ptr [sb_addr], 0x10
	cmp	word ptr [sb_addr], 0x290
	jbe	0b
	stc
9:	ret


sb_detect_irq:
	cmp	[sb_irq], byte ptr -1
	jz	1f
	call	Test_IRQ
	jae	9f			#lets look for others then!

1:	print "Detecting IRQ... "
	mov	byte ptr [sb_irq], 7
	call	Test_IRQ
	jnc	9f			#=jnc
	mov	byte ptr [sb_irq], 5
	call	Test_IRQ
	jnc	9f
	mov	byte ptr [sb_irq], 3
	call	Test_IRQ
	jnc	9f
	mov	byte ptr [sb_irq], 0x0a
	call	Test_IRQ
	jnc	9f
	mov	byte ptr [sb_irq], 2
	call	Test_IRQ
	jnc	9f
	printlnc 4, "Fail"
	stc
	ret
9:	movzx	edx, byte ptr [sb_irq]
	call	printdec32
	call	newline
	clc
	ret



Test_IRQ:
	push_	si ax cx
	mov	byte ptr [IRQ_Flag], 0

	mov	al, [sb_irq]
	.if SB_DEBUG
		DEBUG_BYTE al, "TEST IRQ", 13
	.endif
	mov	ebx, offset TestIntHandler
	call	HookVector

	mov	al, DSP_CMD_GEN_INT	# 0xf2
	call	sb_dsp_write
	sti			#enable em (just in case)
	mov	ecx, 0x10000
0:	cmp	byte ptr [IRQ_Flag], 0
	clc
	jnz	1f
	loop	0b
	stc

1:	mov	al, [sb_irq]
	call	UnHookVector
	pop_	cx ax si
	ret


# in: al = [sb_irq]
HookVector:	
	pushf
	cli
	push_	ebx ecx
	.if SB_DEBUG
		mov	[sb_isr_irq], al
	.endif
	add	al, IRQ_BASE
	mov	cx, cs
	call	hook_isr
	mov	[sb_old_isr_offs], ebx
	mov	[sb_old_isr_sel], cx

	push ax; PIC_GET_MASK; mov [sb_old_pic_mask], ax; pop ax;
	push ax; PIC_ENABLE_IRQ_LINE; pop ax
	pop_	ecx ebx
	popf
	ret

# in: al = [sb_irq]
UnHookVector:
	pushf
	cli
	push_	ebx ecx
	PIC_SET_MASK [sb_old_pic_mask]
	add	al, IRQ_BASE
	mov	cx, cs
	mov	ebx, [sb_old_isr_offs]
	mov	cx, [sb_old_isr_sel]
	call	hook_isr
	pop_	ecx ebx
	popf
	ret


.if SB_DEBUG
.data
sb_isr_irq: .byte 0
.text32
.endif

TestIntHandler:
	push_	eax edx ds
	mov ax, SEL_compatDS
	mov ds, ax

	.if SB_DEBUG
		DEBUG "TestIntHandler", 12
		mov dl, [sb_irq]#[sb_isr_irq]
		call printhex2
		movzx edx, byte ptr [SB_DMA]
		cmp dl, -1
		jz 1f
		in al, 0x08	# dma controller 0
		DEBUG_BYTE al, "DMA0 STATUS"
		in al, 0xd0	# dma controller 1
		DEBUG_BYTE al, "DMA1 STATUS"
	1:
	.endif

	mov	dx, word ptr [sb_addr]
	add	dl, DSPIrqAck8Port
	cmp	byte ptr [SB_Bits_Sample], 8
	jz	8f
	add	dl, DSPIrqAck16Port-DSPIrqAck8Port
8:	in	al, dx

	inc	byte ptr [IRQ_Flag]
	PIC_SEND_EOI [sb_irq]
	pop_	ds edx eax
	iret


sb_detect_dma:
	mov	al, -1
	xchg	al, [sb_dma8]
	cmp	al, -1
	jz	1f
	mov	[SB_DMA], al
	call	sb_test_dma
	jnc	2f

1:	print "Detecting 8-bit DMA channel.. "

	mov	byte ptr [SB_DMA], 1
	call	sb_test_dma
	jnc	2f
	mov	byte ptr [SB_DMA], 3
	call	sb_test_dma
	jc	1f
2:	mov	dl, [SB_DMA]
	mov	[sb_dma8], dl
	call	printhex1
	call	newline

1:	cmp	byte ptr [sb_version], 3	# SB Pro, last 8 bit card
	jbe	1f				# skip testing 16 bit dma

	mov	al, -1
	xchg	al, [sb_dma16]
	cmp	al, -1
	jz	1f
	mov	[SB_DMA], al
	call	sb_test_dma
	jnc	2f

1:	print "Detecting 16-bit DMA channel.. "
	mov	byte ptr [SB_DMA], 5
	call	sb_test_dma
	jnc	2f
	mov	byte ptr [SB_DMA], 6
	call	sb_test_dma
	jnc	2f
	mov	byte ptr [SB_DMA], 7
	call	sb_test_dma
	jc	1f
2:	mov	dl, [SB_DMA]
	mov	[sb_dma16], dl
	call	printhex1
	call	newline

9:
1:	cmp	byte ptr [sb_dma8], -1
	stc
	jz	1f
	clc
1:	ret



sb_test_dma:
	call	sb_reset
	mov	al, [sb_irq]
	mov	ebx, offset TestIntHandler
	call	HookVector
	mov	[IRQ_Flag], byte ptr 0x33

	mov     al, DMA_MODE_SINGLE | DMA_MODE_READ # 0x48
	mov     ecx, 4# 4 min for 16 bit->(4>>1)-1 must be >0
	mov     ah, byte ptr [SB_DMA]
	.if SB_DEBUG
		call	newline
		DEBUG_BYTE [SB_DMA], "   TEST DMA CHAN", 14
	.endif
	call    dma_transfer

	call	sb_write_samplerate

	cmp	byte ptr [SB_DMA], 4
	jae	1f
	
	mov	al, DSPStartDMA8BitDAC
	call	sb_dsp_write
	mov     ax, 1            #size-1
	call	sb_dsp_write
	mov	al, ah
	call	sb_dsp_write
	jmp	2f

1:	mov	al, DSP_CMD_START_DMA16_SC_PLAY # 0xb0
	call	sb_dsp_write
	mov	al, DSP_MODE_SIGNED|DSP_MODE_STEREO # 0x30
	call	sb_dsp_write
	mov     ax, 1            #size-1
	call	sb_dsp_write
	mov	al, ah
	call	sb_dsp_write

2:	mov	ebx, [clock_ms]
	mov	eax, ebx
	add	ebx, 10
0:	cmp	byte ptr [IRQ_Flag], 0x33
	clc
	jnz	1f
	cmp	ebx, [clock_ms]
	ja	0b
2:	stc

1:	pushf	# preserve CF
	mov	al, [sb_irq]
	call	UnHookVector
	mov     ah, byte ptr [SB_DMA]
	call	dma_stop
	popf
	ret


sb_dma_transfer:
	push_	eax ecx edx
	mov     ecx, [dma_buffersize]
	mov     ah, byte ptr [SB_DMA]
	mov     al, DMA_MODE_READ|DMA_MODE_AUTO|DMA_MODE_SINGLE
	cmp	byte ptr [SB_Direction], 0
	jz	1f
	mov     al, DMA_MODE_WRITE|DMA_MODE_AUTO|DMA_MODE_SINGLE
1:	call    dma_transfer

	cmp     [sb_version], byte ptr 4
	jae	16f
	cmp	[sb_version], byte ptr 1
	ja	20f

	#Sigh.. we'll have to do it the lame-way.. no auto init.. :(

	mov	al, DSPStartDMA8BitDAC
	cmp	byte ptr [SB_Direction], 0
	jz	1f
	mov	al, DSPStartDMAADC
1:	call	sb_dsp_write
	mov     eax, [dma_buffersize]
	dec     eax
	call	sb_dsp_write
	xchg	al, ah		       #send MSB of DATALENGTH
	call	sb_dsp_write
	jmp	9f

16:	mov     edx, [dma_buffersize]

	cmp	byte ptr [SB_Bits_Sample], 8
	jz	8f
	shr	edx, 1	# 16 bitsper sample
	mov	al, DSP_CMD_START_DMA16_AI_PLAY
	jmp	1f
8:	mov	al, DSP_CMD_START_DMA8_AI_PLAY
1:	call	sb_dsp_write

	mov	al, 0b00110000	# mode 0x30 (signed stereo)
	call	sb_dsp_write

	shr	edx, 1# 2 irqs per transfer, so can fill one half of buffer
	dec     edx
	mov	ax, dx
	call	sb_dsp_write
	mov	al, ah			#send MSB of DATALENGTH
	call	sb_dsp_write
	jmp	9f

20:	# pro2.0: autoinit
	mov	al, DSPSetHSDMASize
	call	sb_dsp_write
	mov     eax, [dma_buffersize]
	dec     eax
	call	sb_dsp_write
	mov	al, ah			#send MSB of DATALENGTH
	call	sb_dsp_write
	mov	al, DSPStartAutoInitHSDMA   #..and GO!
	cmp	byte ptr [SB_Direction], 0
	jz	1f
	mov	al, DSPStartAutoInitHSDMAR  #..and GO!
1:	call	sb_dsp_write

9:	pop_	edx ecx eax
	ret




sb_record_init:
	push_	ax
	mov	byte ptr [SB_Direction], -1

	mov	al, DSPSpeakerOn
	call	sb_dsp_write

	mov	al, Mix_Output_Select
	mov	ah, 1 shl 5
	cmp	[SB_Stereo], byte ptr 0
	jz	1f	# mono
	or      ah, 2
1:	cmp	byte ptr [SB_Output_Filter], 0
	jz	1f	# no filter
	and	ah, not (1 shl 5)
1:	call	sb_mixer_write

	mov	al, Mix_Input_Select
	mov	ah, [SB_Input_Select]
	cmp	[SB_Input_Filter], byte ptr 0
	jnz	1f	# no input filter
	or	ah, 1 shl 5
1:	call	sb_mixer_write

	mov	ax, 0xff shl 8+Mix_Master_Volume
	call	sb_mixer_write
	mov	ax, 0xff shl 8+Mix_Voice_Volume
	call	sb_mixer_write

	mov	al, DSPSetTimeConstant
	call	sb_dsp_write
	mov	al, [TimeConstant]
	call	sb_dsp_write

	push	ebx
	mov	ebx, offset sb_isr_record
	mov	al, [sb_irq]
	call	HookVector
	pop	ebx
	mov	[SB_PlayStopped], byte ptr 0
	mov	[SB_StopPlay], byte ptr 0

	pop_	ax
	ret


sb_write_samplerate:
	cmp	byte ptr [sb_version], 4
	jb	1f

	# sb16 and up
	mov	al, DSPSB16SetSpeedOut 
	call	sb_dsp_write
	mov	ax, [SB_SampleRate]	
	xchg	al, ah	# ac
	call	sb_dsp_write
	xchg	al, ah	# 44
	call	sb_dsp_write
	ret

	# sb pro and lower
1:	mov	al, DSPSetTimeConstant
	call	sb_dsp_write
	mov	al, [TimeConstant]	# d3
	call	sb_dsp_write

 	ret


sb_playback_init:
	push	eax
	mov	byte ptr [SB_Direction], 0

	mov	al, DSPSpeakerOn
	call	sb_dsp_write

	mov	ax, 0x33 shl 8 + Mix_Output_Select
	cmp	[sb_version], byte ptr 3	# pro or higher
	jae	1f
	mov	ah, 0x31
1:	call	sb_mixer_write

#		 mov	 al, Mix_Output_Select
#		 mov	 ah, 1 shl 5
#		 cmp	 [SB_Stereo], 0
#		 jz	 @@Mono$
#		 mov	 ah, 2+1 shl 5
#@@Mono$:	 cmp	 byte ptr [SB_Output_Filter], 0
#		 jz	 @@NoFilter$
#		 and	 ah, not (1 shl 5)
#@@NoFilter$:	 call	 sb_mixer_write


	mov	ax, 0xff shl 8+Mix_Master_Volume
	call	sb_mixer_write
	mov	ax, 0xff shl 8+Mix_Voice_Volume
	call	sb_mixer_write

	call	sb_write_samplerate

	push	ebx
	mov	ebx, offset sb_isr_playback
	mov	al, [sb_irq]
	call	HookVector
	pop	ebx

	mov	byte ptr [SB_RecordStopped], 0
	mov	byte ptr [SB_StopRecord], 0
	mov	byte ptr [sb_dma_buf_half], 0

	pop	eax
	ret

.data
sb_dev$:	.long 0
.text32
sb_isr_playback:
	push_	ds es edx ecx ebx eax edi
	mov	edx, SEL_compatDS
	mov	ds, edx
	mov	es, edx

	mov	ah, [SB_DMA]
	call	dma_getpos	# not really needed...

	mov	ebx, [sb_dev$]
	mov	ecx, [ebx + sound_playback_handler]
	jecxz	1f
	call	ecx
1:

	mov	dx, [sb_addr] # ACKnowledge SB IRQ
	add	dl, DSPIrqAck8Port
	cmp	byte ptr [SB_Bits_Sample], 8
	jz	8f
	add	dl, DSPIrqAck16Port-DSPIrqAck8Port
8:	in	al, dx
	cmp	[SB_StopPlay], byte ptr 0
	jne	2f # stop irq	#Don't reprogram (if sb=1)
	cmp	[sb_version], byte ptr 1
	jnz	3f # skipmask

	mov	al, DSPStartDMA8BitDAC
	call	sb_dsp_write
	mov     eax, [dma_buffersize]
	dec     eax
	call	sb_dsp_write	# send LSB of buffer length
	mov	al, ah
	call	sb_dsp_write	# send MSB of buffer length
	jmp	3f	# skipmask

2:	mov	[SB_PlayStopped], byte ptr 1

3:	PIC_SEND_EOI [sb_irq]
	pop_	edi eax ebx ecx edx es ds
	iret



sb_isr_record:
	push_	ds edx eax
	mov	eax, SEL_compatDS
	mov	ds, eax

	mov	dx, word ptr [sb_addr]
	add	dl, DSPIrqAck8Port
	cmp	byte ptr [SB_Bits_Sample], 8
	jz	8f
	add	dl, DSPIrqAck16Port-DSPIrqAck8Port
8:	in	al, dx
	cmp	byte ptr [SB_StopRecord], 0
	jne	2f #stopirq	#Don't reprogram (if sb=1)
	cmp	[sb_version], byte ptr 1
	jnz	3f	# skipmask

	mov	al, DSPStartDMAADC
	call	sb_dsp_write
	mov	eax, [dma_buffersize]
	dec	eax
	call	sb_dsp_write	# send LSB of buffer length
	mov	al, ah
	call	sb_dsp_write	# send MSB of buffer length
	jmp	3f# @@skipmask$

2:	mov	byte ptr [SB_RecordStopped], 1

3:	PIC_SEND_EOI [sb_irq]
	pop_	eax edx ds
	iret



SB_ExitTransfer:
	push_	ax cx
	cmp	byte ptr [SB_Bits_Sample], 8
	jz	8f
	mov	al, DSPSB16Stop16AutoDMA
	jmp	1f
8:	cmp	[sb_version], byte ptr 1
	jz	2f	# no auto-init
	mov	al, DSPSB16Stop8AutoDMA
	jmp	1f
2:	mov	al, DSPPause8DMA
1:	call	sb_dsp_write
	mov	ah, byte ptr [SB_DMA]
	call	dma_stop
	call	sb_reset
	mov	al, DSPSpeakerOff
	call	sb_dsp_write
	call	UnHookVector
	pop_	cx ax
	ret

########################################################################
.data

IRQ_Flag:.byte 0	#For detecting..

sb_version:	.byte 0, 0
sb_addr:	.word -1
sb_irq:		.byte -1
sb_dma8:	.byte -1
sb_dma16:	.byte -1

SB_DMA:		.byte -1
SB_Midi:	.word -1
sb_version_:	.byte 0		#User override
SB_SampleRate:	.word 22000
SB_SampleRate_:	.word 0		#User override
SB_Stereo:	.byte -1		#0=mono, -1=stereo
SB_Bits_Sample:	.byte 8		#of 16..

SB_Direction:	.byte 0		#0=output, -1=input (set by sb_initr/pl.)

SB_Input_Select:.byte SB_LineIn
SB_Input_Filter:.byte 0		#0=no filter, -1=filter
SB_Output_Filter:.byte 0		 #0=no filter, -1=filter

TimeConstant:	.byte 0		 # -1000000/smprate for outing

sb_dma_buf_half:.byte 0		# flag keeping track of which half is playing


# HookVector and UnhookVector
sb_old_pic_mask:.word 0		#saves original 21 and a1 port vals
sb_old_isr_offs:.long 0
sb_old_isr_sel:	.word 0

# control
SB_StopPlay:	.byte 0		#-1 means stop playing
SB_PlayStopped:	.byte 0		#-1 means stopped.
SB_StopRecord:	.byte 0		#-1 means stop recording
SB_RecordStopped:.byte 0	#-1 means stopped.


SB_EnvStr:	.asciz "BLASTER"
EnvStrBuff:	.space 32

#SBData		EndS

