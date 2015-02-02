##############################################################################
# Intel 82801 ICH AC'97 Audio Controller
#
# DOC/Specs/82801eb-82801er-io-controller-hub-datasheet.pdf#Chapter_15
#
.intel_syntax noprefix

DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x2415, "ac97", "Intel 82801AA (ICH) AC'97 Audio Controller"
DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x2425, "ac97", "Intel 82801AB (ICH0) AC'97 Audio Controller"
DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x2445, "ac97", "Intel 82801BA/BAM (ICH2) AC'97 Audio Controller"
DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x2485, "ac97", "Intel 82801CA/CAM (ICH?) AC'97 Audio Controller"
DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x24c5  "ac97", "Intel 82801DB/DBL/DBM (ICH4/ICH4-L/ICH4-M) AC'97 Audio Controller"
DECLARE_PCI_DRIVER MM_AUDIO, ac97, 0x8086, 0x24d5, "ac97", "Intel 82801EB/ER (ICH5/ICH5R) AC'97 Audio Controller"
# 25a6  6300ESB AC'97 Audio Controller (more id's)


# Compilation flags (result in different code!)

AC97_DEBUG	= 0	# 0 or 1;
AC97_DEBUG_ISR	= 0	# 0 or 1; whether to have debug output in the ISR
AC97_TEST	= 0	# 0 or 1; enable self-tests (requires DEBUG)


# in order of decreasing priority:  (set only 1 of them to 1):
IO_MULTI_INLINE	= 1	# 1) inline both MMIO and PIO code; check mode on each IO access
AC97_MMIO_ONLY	= 0	# 2) set to 1 to use MMIO optimized code, 0 to auto-detect MMIO/PIO
AC97_PIO_ONLY	= 1	# 3) set to 1 to use PIO optimized code, 0 to auto-detect MMIO/PIOC
			# 4) all 0: use MMIO detection and object method pointer updates

# A note on the above Compilation Flags.
#
# The first implementation was for an ICH5 motherboard, which supports MMIO.
# Testing using USB is tedious, so I tested against Qemu (-soundhw ac97) which
# features an ICH0 which only supports PIO (no BAR2/3). The second iteration then
# had to support PIO: enter flag AC97_MMIO_ONLY where 1 is the old code and 0
# is what is now option 4.
#
# Option 4 first detects MMIO and PIO in the device constructor, and configures
# one of two sets of 4 methods: read and write the mixer or channels, either in
# MMIO mode or PIO. At runtime, the READ/WRITE macros push the register and call
# the object method. These methods are specialized either for MMIO or PIO and
# either for reading or writing. Their only difference is the operand size:
# the controller returns -1 on various misaligned reads. A bitmap encoding the
# 8 methods (7 actually, but the 8th is nowhere used except at one offset)
# is consulted at runtime to determine the proper operand size.  Code for
# accessing the mixer is simple, as all accesses are 16 bit.
# The channel methods are generated using a macro defining the method template.
# It is the slowest runtime option as it is dynamic - it figures out the operand
# size for the register at runtime.
#
# Since option 4 did not work properly, I decided to ad a PIO_ONLY mode to
# facilitate testing on Qemu. The code would then inline any port IO using
# the proper register size (al, ax, or eax is passed to the macro).
# This required to update all code referencing the macros to explicitly state
# the operand size, and to replace constants with (part of) eax.
# This mode tested successfully.
#
# The first option, IO_MULTI_INLINE, is the latest. All IO calls
# will test whether the device supports MMIO and thus inlines both
# PIO and MMIO code.
#
# One other option was considered and that is to
# reserve some space in the register address stack parameter
# to encode the register size. Macros could then check for proper
# access. Alternatively these can then be set in the macros
# using .ifc \val,eax etc, not polluting the constants. A simpler
# option would be to encode the size in the constants, but this
# would require to update all code using status/control registers
# to mask out these flags.
# The PIO code simply does
#   mov dx, [ebx + ...pio
#   add dx, [ebp]
# which would effectively filter out the high dword, whereas MMIO code does
#   mov esi, [ebx + ... mmio]
#   add esi, [ebp]
# which would then require to instead
#   movzx esi, byte ptr [ebp]
#   add esi, [ebx + ... mmio]
# However this would loose the bits, and soon either more registers
# or more duplicate code would be needed (for instance:
#   mov esi, [ebp]
#   test esi, 2; jz 4f
#   test esi, 1; jz 2f
# 1:and esi, ~3;  inb/movb; jmp;
# 2:and esi, ~3;  inw/movw; jmp;
# 4:and esi, ~3;  ind/movd; jmp;
# )
#
# Option 4 is currently slow because it determines register size
# at runtime using a relatively slow method (constant time but
# a couple of handful of memory references). Once the above option
# to encode the size during macro invocation and encoding it in the
# runtime register address is implemented, the object method will
# be comparable to the inline method (it's MMIO test and jump can
# compare to the method pointer dereference).
# The inline method is then faster since it encodes the correct
# operand size in each access. This does result in some duplicate
# code, which is only compressable for PIO (as the MMIO is a mov,
# the smallest and fastest).
# The object solution has the fewest duplicate code. It can be
# improved by adding more methods: read/write api methods
# for byte/word/dword for the channel api. However this is becoming
# dangerously close to the full-blown version, creating a method
# for each register.
# Nonetheless, the object solution can be the fastest and smallest,
# since all access will be simply:
#   call [ebx + ac97_api_bus_(read|write)].
# This single instruction combines the following features:
# - runtime-configurable IO mode
# - on a per-object basis
# - cached testing for MMIO or PIO.
# The test would have to dereference memory anyway. In this case,
# no internal knowledge of which IO mode is used is needed in
# the code beyond the device constructor (initialisation). Also,
# both the test for the mode and the calling of the proper
# method is folded into 1 instruction.

DECLARE_CLASS_BEGIN ac97, sound
ac97_mixer_pio:	.long 0
ac97_bus_pio:	.long 0
ac97_mixer_mmio:.long 0
ac97_bus_mmio:	.long 0

ac97_buf_po:	.long 0	# PCM out mallocced buffer descriptor ring (256 bytes)
DECLARE_CLASS_METHOD dev_api_constructor,	ac97_init, OVERRIDE
DECLARE_CLASS_METHOD dev_api_isr,		ac97_isr, OVERRIDE
DECLARE_CLASS_METHOD sound_set_samplerate,	ac97_set_samplerate,	OVERRIDE
DECLARE_CLASS_METHOD sound_set_format,		ac97_set_format,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_init,	ac97_playback_init,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_start,	ac97_playback_start,	OVERRIDE
DECLARE_CLASS_METHOD sound_playback_stop,	ac97_playback_stop,	OVERRIDE
# tODO: add desctructor, mfree [ebx+ac97_buf_po] etc..
.if !(AC97_MMIO_ONLY|AC97_PIO_ONLY)
DECLARE_CLASS_METHOD ac97_api_chan_read,	0
DECLARE_CLASS_METHOD ac97_api_chan_write,	0
DECLARE_CLASS_METHOD ac97_api_mixer_read,	0
DECLARE_CLASS_METHOD ac97_api_mixer_write,	0
.endif
DECLARE_CLASS_END ac97




##########################################
# Constants

# NOTE: register scheme:
# PCI address 0x40 (just above std decoded) contains the ID's for secondary and
# tertiary codecs sent on the AC line. These are two bits.
# Something similar applies here: A register is present at
# primary, secondary, and tertiary offsets that lie 0x80 apart.
# So for example, AC97_MIXer_REG_RESET is at 0, 0x80, and 0x100.
# This is the same as OR-ing the register offset with the unit index << 8.
#
# All registers 16 bit.
AC97_MIXER_REG_RESET			= 0x00
AC97_MIXER_REG_MASTER_VOL		= 0x02
AC97_MIXER_REG_AUX_OUT_VOL		= 0x04
AC97_MIXER_REG_MONO_VOL			= 0x06
AC97_MIXER_REG_MASTER_TONE		= 0x08
AC97_MIXER_REG_PC_BEEP_VOL		= 0x0a
AC97_MIXER_REG_PHONE_VOL		= 0x0c
AC97_MIXER_REG_MIC_VOL			= 0x0e
AC97_MIXER_REG_LINE_IN_VOL		= 0x10
AC97_MIXER_REG_CD_VOL			= 0x12
AC97_MIXER_REG_VIDEO_VOL		= 0x14
AC97_MIXER_REG_AUX_IN_VOL		= 0x16
AC97_MIXER_REG_PCM_OUT_VOL		= 0x18
AC97_MIXER_REG_RECORD_SELECT		= 0x1a
AC97_MIXER_REG_RECOD_GAIN		= 0x1c
AC97_MIXER_REG_RECORD_GAIN_MIC		= 0x1e
AC97_MIXER_REG_GENERAL_PURPOSE		= 0x20
AC97_MIXER_REG_3D_CONTROL		= 0x22
AC97_MIXER_REG_RESERVED0		= 0x24
AC97_MIXER_REG_PWRDN_CTRL_STAT		= 0x26
AC97_MIXER_REG_EXT_AUDIO		= 0x28
AC97_MIXER_REG_EXT_AUDIO_CTRL_STAT	= 0x2a
AC97_MIXER_REG_PCM_FROM_DAC_RATE	= 0x2c
AC97_MIXER_REG_PCM_SURROUND_DAC_RATE	= 0x2e
AC97_MIXER_REG_PCM_LFE_DAC_RATE		= 0x30
AC97_MIXER_REG_PCM_LR_ADC_RATE		= 0x32
AC97_MIXER_REG_MIC_ADC_RATE		= 0x34
AC97_MIXER_REG_6CH_C_LFE_VOL		= 0x36
AC97_MIXER_REG_6CH_L_R_SURROUND_VOL	= 0x38
AC97_MIXER_REG_SPDIF_CONTROL		= 0x3a
# 0x3c-0x56 intel reserved;
# 0x58 AC97 reserved
# 0x5a venor reserved
AC97_MIXER_REG_VENDOR_ID1		= 0x7c
AC97_MIXER_REG_VENDOR_ID2		= 0x7e

#######
# Bus Mastering Registers
#  offset 0..0x51; byte,word,word,qword write, read dword boundary.
#
# The 6 channels,
#  PI = PCM IN channel
#  PO = PCM OUT channel
#  MC = MIC IN channel
#  MC2= MIC2 channel
#  PI2 = PCM in 2 channel
#  SP = SPDIF out channel
# each have these channels:

.macro MAP_CHANNEL name, offs
AC97_CHANNEL_REG_\name\()_BDBAR	= 0x00	+ \offs	# (R/W)     default 0x00000000	Buffer Descriptor list Base Address
	# low 2 bits: 0; rest: probably hardware DMA address.
	# Data: 8-byte aligned 32 8-byte descriptors # .align 8; .space 256
AC97_CHANNEL_REG_\name\()_CIV	= 0x04	+ \offs	# (RO)      default 0x00	Current Index Value (5 bit wide)
AC97_CHANNEL_REG_\name\()_LVI	= 0x05	+ \offs	# (R/W)     default 0x00	Last Valid Index (idem)
AC97_CHANNEL_REG_\name\()_SR	= 0x06	+ \offs	# (R/WC,RO) default 0x0001	Status [See AC97_CHANNEL_STATUS_*]
AC97_CHANNEL_REG_\name\()_PICB	= 0x08	+ \offs	# (RO)      default 0x0000	Position in Current Buffer (samples left)
AC97_CHANNEL_REG_\name\()_PIV	= 0x0a	+ \offs	# (RO)      default 0x00	Prefetched Index Value
AC97_CHANNEL_REG_\name\()_CR	= 0x0b	+ \offs	# (R/W,R/W) default 0x00	Control [See AC97_CHANNEL_CONTROL_*]
AC97_CHANNEL_REG_\name\()_UNKNOWN=0x0c	+ \offs	# (N/A)	    default 0x????????
.endm


MAP_CHANNEL PI, 0x00	# PCM IN
MAP_CHANNEL PO, 0x10	# PCM OUT
MAP_CHANNEL MC, 0x20	# MIC IN	(note: _UNKNOWN overlaps with GLOBAL_CONTROL)

AC97_CHANNEL_REG_GLOBAL_CONTROL	= 0x0c + 0x20	# (R/W,R/W*)	default 0x00000000	Control [see AC97_GLOBAL_STATUS_*]
AC97_CHANNEL_REG_GLOBAL_STATUS	= 0x00 + 0x30	# (R/W,R/WC/RO)	default 0x00700000	Status [see AC97_GLOBAL_CONTROL_*]
AC97_CHANNEL_REG_CAS		= 0x04 + 0x30	# (R/W*)	default 0x00   		Codec Access Semaphore
#AC97_CHANNEL_REG_?		= 0x05 + 0x30	# (N/A)		default 0x??
#AC97_CHANNEL_REG_?		= 0x06 + 0x30	# (N/A)		default 0x????
#AC97_CHANNEL_REG_?		= 0x08 + 0x30	# (N/A)		default 0x????????
#AC97_CHANNEL_REG_?		= 0x0c + 0x30	# (N/A)		default 0x????????

MAP_CHANNEL MC2, 0x40	# MIC2 IN
MAP_CHANNEL PI2, 0x50	# PCM2 IN
MAP_CHANNEL SP,  0x60	# S/PDIF
#MAP_CHANNEL ??, 0x70
AC97_CHANNEL_REG_SDM		= 0x00 + 0x80	# (R/W,RO)	default 0x00	SData_IN Map

.purgem MAP_CHANNEL



.struct # AC97_DESCRIPTOR	# this is a guess:
ac97_desc_addr:	.long 0	# max 64k, dword aligned, 64k boundary (i'm assuming there's already code for malloccing this)
	# bit 1 is generally reserved
ac97_desc_size:	.word 0	# bytes, 15 its (high bit reserved)
.byte 0	# reserved
ac97_desc_flags: .byte 0
	AC97_DESC_IOC = 1 << 7	# interrupt on completion
	AC97_DESC_BUP = 1 << 6	# buffer underrun policy: 1 = stop playback
AC97_DESCRIPTOR_SIZE = .
.text32


############################
# Control and Status bits
#
# The values for the _SR (Status Register, word)
# These are IOC (Interrupt On Completion) cause indicators.
# Some of them are cleared by hardware, others by writing 1.
# bits 15:5 reserved
AC97_CHANNEL_STATUS_FIFOE = 1 << 4	# PCM(2) IN: fifo overrun; OUT: underrun (cleared by hardware)
AC97_CHANNEL_STATUS_BCIS  = 1 << 3	# (R/O,W/C) Buffer Completion Interrupt Status
AC97_CHANNEL_STATUS_LVBC  = 1 << 2	# (R/O,W/C) Last Valid Buffer Completion Interrupt
AC97_CHANNEL_STATUS_CELV  = 1 << 1	# (R/O) Current Equals Last Valid (cleared by hardware)
AC97_CHANNEL_STATUS_DCH   = 1 << 0	# (R/O,W/C) DMA Controller Halted

# The values for the _CR (Control Register; byte)
# bits 7:5 reserved
# NOTE: unfortunately bits 4:2 in STATUS and CONTROL are not mapped 1:1!
AC97_CHANNEL_CONTROL_IE_OC	= 1 << 4	# Interrupt On Completion Enable: triggered by DESCRIPTOR_FLAG_IOC; [Rel status bit 3?]
AC97_CHANNEL_CONTROL_IE_FIFOE	= 1 << 3	# FIFO Err int enable; trigger int when STATUS_FIFOE is set?; [Rel Status bit 4]
AC97_CHANNEL_CONTROL_IE_LVBC	= 1 << 2	# Last Valid Buffer Completion Interrupt (LVBIE); [Rel Status bit 2]
AC97_CHANNEL_CONTROL_RESET	= 1 << 1	# Reset Registers (RR); clears all registers except bit 2,3,4 in CR. Self-clearing.
AC97_CHANNEL_CONTROL_BM_ENABLE	= 1 << 0	# Run/Pause bus master. (can busmaster disable/enable and resume)


######################################
# Channel Global Status register bits:
# 0x0140
#  x0100
#  x0040
#
AC97_GLOBAL_STATUS_S2RI		= 1 << 29	# (RO) AC_SDIN2 Resume Interrupt (resume event)
AC97_GLOBAL_STATUS_S2CR		= 1 << 28	# (RO) AC_SDIN2 Codec Ready (must be 1 before staring bus masters)
AC97_GLOBAL_STATUS_BCS		= 1 << 27	# (RO) Bit Clock Stopped (no AC_BIT_CLK transition during 4 PCI clocks)
AC97_GLOBAL_STATUS_SOI		= 1 << 26	# (RO) S/PDIF OUT Interrupt  (SPINT)
AC97_GLOBAL_STATUS_PI2I		= 1 << 25	# (RO) PCM2 IN Interrupt
AC97_GLOBAL_STATUS_MC2I		= 1 << 24	# (RO) MIC2 IN Interrupt

AC97_GLOBAL_STATUS_SAMPLE_CAPS	= 0b11 << 22	# (RO) 01=16 and 20 bit audio supported; rest is reserved
AC97_GLOBAL_STATUS_MULTICHANNEL	= 0b11 << 20	# (RO) undocumented: multichannel capabilities (4/6 ch PCM out)

# note: modem shares this register with audio; these 2 bits are for software
# to coordinate the entry of the two codecs into D3 (power) state.
AC97_GLOBAL_STATUS_MD3		= 1 << 17	# Modem power-down semaphore
AC97_GLOBAL_STATUS_AD3		= 1 << 16	# Audio power-down semaphore

AC97_GLOBAL_STATUS_RCS		= 1 << 15	# (R/WC) Read Completion Status (0=normal; 1=timeout)

AC97_GLOBAL_STATUS_S12B3	= 1 << 14	# (RO) Bit 3 of most recent slot 12
AC97_GLOBAL_STATUS_S12B2	= 1 << 13	# (RO) Bit 2 of most recent slot 12
AC97_GLOBAL_STATUS_S12B1	= 1 << 12	# (RO) Bit 1 of most recent slot 12

AC97_GLOBAL_STATUS_S1RI		= 1 << 11	# (R/WC) AC_SDIN1 Resume Interrupt
AC97_GLOBAL_STATUS_S0RI		= 1 << 10	# (R/WC) AC_SDIN0 Resume Interrupt
AC97_GLOBAL_STATUS_S1CR		= 1 << 9	# (RO) AC_SDIN1 Codec Ready (must be 1 before staring bus masters)
AC97_GLOBAL_STATUS_S0CR		= 1 << 8	# (RO) AC_SDIN0 Codec Ready (must be 1 before staring bus masters)

AC97_GLOBAL_STATUS_MII		= 1 << 7	# (R/O) MIC IN interrupt
AC97_GLOBAL_STATUS_POI		= 1 << 6	# (R/O) PCM OUT interrupt
AC97_GLOBAL_STATUS_PII		= 1 << 5	# (R/O) PCM IN interrupt
AC97_GLOBAL_STATUS_MOI		= 1 << 2	# (R/O) Modem OUT Interrupt
AC97_GLOBAL_STATUS_MII		= 1 << 1	# (R/O) Modem IN Interrupt
AC97_GLOBAL_STATUS_GSCI		= 1 << 0	# (R/WC) GPI Status Change Interrupt

#######################################
# Channel Global Control register bits:
AC97_GLOBAL_CONTROL_GIE		= 1 << 0	# (R/W) GPI Interrupt Enable
AC97_GLOBAL_CONTROL_COLD_RESET	= 1 << 1	# (R/W) Cold Reset - write 0 to reset (!)
AC97_GLOBAL_CONTROL_WARM_RESET	= 1 << 2	# (R/W) Warm Reset - write 1 to reset (awakens suspended codec)
AC97_GLOBAL_CONTROL_LSO		= 1 << 3	# (R/W) ACLINK Shut Off
AC97_GLOBAL_CONTROL_IE_S0	= 1 << 4	# (R/W) AC_SDIN0 Interrupt Enable
AC97_GLOBAL_CONTROL_IE_S1	= 1 << 5	# (R/W) AC_SDIN1 Interrupt Enable
AC97_GLOBAL_CONTROL_IE_S2	= 1 << 6	# (R/W) AC_SDIN2 Interrupt Enable
# 19:7 reserved
AC97_GLOBAL_CONTROL_PCM46_ENABLE= 0b00 << 20	# (R/W) PCM 4/6 Enable: 00*=2chan, 01=4 chan, 10=6chan, 11=resvd
AC97_GLOBAL_CONTROL_POM		= 0b11 << 22	# (R/W) PCM OUT Mode: 00*=16 bit, 01=20bit, 1?=reserved.
# 29:24 reserved
AC97_GLOBAL_CONTROL_SSM		= 0b00 << 30	# ($/W) S/PDIF Slot Map: 00=resvd, 01=7&8, 10=6&9, 11=10&11



.macro AC97_CHANNEL_READ offs, dest=eax
  .if IO_MULTI_INLINE
		cmpd	[ebx + ac97_bus_mmio], 0
		jz	101f
  .endif
  .if AC97_MMIO_ONLY | IO_MULTI_INLINE
		mov	\dest, [esi + AC97_CHANNEL_REG_\offs]
  .endif
  .if IO_MULTI_INLINE
		jmp	109f
	101:
  .endif
  .if AC97_PIO_ONLY | IO_MULTI_INLINE
		mov	dx, [ebx + ac97_bus_pio]
		add	dx, AC97_CHANNEL_REG_\offs
		in	\dest, dx
  .endif
  .if !(AC97_PIO_ONLY | AC97_MMIO_ONLY | IO_MULTI_INLINE )
		pushd	AC97_CHANNEL_REG_\offs
		call	[ebx + ac97_api_chan_read]
  .endif
   .if IO_MULTI_INLINE
	109:
  .endif
.endm




.macro AC97_CHANNEL_WRITE offs, val=eax
  .if IO_MULTI_INLINE
		cmpd	[ebx + ac97_bus_mmio], 0
		jz	101f
  .endif
  .if AC97_MMIO_ONLY | IO_MULTI_INLINE
		mov	[ebx + AC97_CHANNEL_REG_\offs], \val
  .endif
  .if IO_MULTI_INLINE
		jmp	109f
	101:
  .endif
  .if AC97_PIO_ONLY | IO_MULTI_INLINE
		mov	dx, [ebx + ac97_bus_pio]
		add	dx, AC97_CHANNEL_REG_\offs
		out	dx, \val
  .endif
  .if !(AC97_PIO_ONLY | AC97_MMIO_ONLY | IO_MULTI_INLINE )
		pushd	AC97_CHANNEL_REG_\offs
		call	[ebx + ac97_api_chan_write]
  .endif
  .if IO_MULTI_INLINE
	109:
  .endif
.endm



.macro AC97_MIXER_WRITE reg, val=ax
  .if IO_MULTI_INLINE
		cmpd	[ebx + ac97_bus_mmio], 0
		jz	101f
  .endif
  .if AC97_MMIO_ONLY | IO_MULTI_INLINE
		mov	word ptr [esi + AC97_MIXER_REG_\reg], \val
  .endif
  .if IO_MULTI_INLINE
		jmp	109f
	  101:
  .endif
  .if AC97_PIO_ONLY | IO_MULTI_INLINE
	.ifnc \val,ax
		movw	ax, \val
	.endif
		mov	dx, [ebx + ac97_mixer_pio]
		add	dx, AC97_MIXER_REG_\reg
		outw	dx, ax
  .endif
  .if !(AC97_PIO_ONLY | AC97_MMIO_ONLY | IO_MULTI_INLINE )
		pushd	AC97_MIXER_REG_\reg
		call	[ebx + ac97_api_mixer_write]
  .endif
  .if IO_MULTI_INLINE
	  109:
  .endif
.endm





#######################
# Debug macros
.macro AC97_DGSB bit
	PRINTFLAG eax, AC97_GLOBAL_STATUS_\bit, " \bit"
.endm

.macro AC97_DEBUG_GLOBAL_REGS
	push_	eax edx
	DEBUG "GLOBAL"
	AC97_CHANNEL_READ GLOBAL_STATUS, eax
	#mov	eax, [esi + AC97_CHANNEL_REG_GLOBAL_STATUS]
	DEBUG_DWORD eax, "SR"
	AC97_DGSB S2RI
	AC97_DGSB S2CR
	AC97_DGSB BCS
	AC97_DGSB SOI
	AC97_DGSB PI2I
	AC97_DGSB MC2I

	AC97_DGSB RCS

	AC97_DGSB S1RI
	AC97_DGSB S0RI
	AC97_DGSB S1CR
	AC97_DGSB S0CR

	AC97_DGSB MII
	AC97_DGSB POI
	AC97_DGSB PII
	AC97_DGSB MOI
	AC97_DGSB MII
	AC97_DGSB GSCI

	AC97_CHANNEL_READ GLOBAL_CONTROL, eax
	#mov	eax, [esi + AC97_CHANNEL_REG_GLOBAL_CONTROL]
	DEBUG_DWORD eax, "CR"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_GIE, " GIE"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_COLD_RESET, " CRST"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_WARM_RESET, " WRST"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_LSO, " LSO"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_IE_S2, " S2"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_IE_S1, " S1"
	PRINTFLAG eax, AC97_GLOBAL_CONTROL_IE_S0, " S0"

	shr	eax, 20
	and	al, 0b1111
	movzx	edx, al
	and	dl, 0b11	# num chans
	PRINTIF dl, 0, " 2"
	PRINTIF dl, 1, " 4"
	PRINTIF dl, 2, " 6"
	print "chan "
	mov	dl, al
	shr	dl, 2	# PCM out mode
	PRINTIF dl, 0, "16"
	PRINTIF dl, 1, "20"
	println "bit"
	pop_	edx eax
.endm


.macro AC97_DEBUG_CHAN chan
	AC97_CHANNEL_READ \chan\()_SR, ax
	cmp	ax, -1	# reg reads -1: absent (high bits reserved, should be 0)
	jz	109f
	DEBUG "\chan"
	#mov	ax, [esi + AC97_CHANNEL_REG_\chan\()_SR]
#	and	ax, 0b11111 	# mask out reserved bits
	DEBUG_WORD ax, "SR"
	PRINTFLAG ax, AC97_CHANNEL_STATUS_FIFOE, " FIFOE"
	PRINTFLAG ax, AC97_CHANNEL_STATUS_BCIS, " BCIS"
	PRINTFLAG ax, AC97_CHANNEL_STATUS_LVBC, " LVBC"
	PRINTFLAG ax, AC97_CHANNEL_STATUS_CELV, " CELV"
	PRINTFLAG ax, AC97_CHANNEL_STATUS_DCH, " DCH"

	call	printspace
	#mov	al, [esi + AC97_CHANNEL_REG_\chan\()_CR]
	AC97_CHANNEL_READ \chan\()_CR, al
#	and	al, 0b11111 	# mask out reserved bits
	DEBUG_BYTE al, "CR"

	PRINTFLAG al, AC97_CHANNEL_CONTROL_IE_OC, " OC"
	PRINTFLAG al, AC97_CHANNEL_CONTROL_IE_FIFOE, " FIFOE"
	PRINTFLAG al, AC97_CHANNEL_CONTROL_IE_LVBC, " LVBC"
	PRINTFLAG al, AC97_CHANNEL_CONTROL_RESET, " RESET"
	PRINTFLAG al, AC97_CHANNEL_CONTROL_BM_ENABLE, " ENABLE"
	call	newline
109:
.endm


##########################################
# Code
.text32
ac97_init:
	PRINTCHARc 0x09 '>'
	call	printspace
	mov	esi, [ebx + dev_drivername_long]
	mov	ah, 15
	call	printlnc
	#I "Intel ICH5 AC'97 Audio Controller"
	#call	newline

	call	dev_add_irq_handler
	call	dev_pci_busmaster_enable
	# BAR0: 'NAMMBAR'  IO 2000-2100				Native Audio Mixer Base Address
	# BAR1: 'NAMMBAR'  IO 2400-2440 			Native Audio Bus Mastering Base Address
	# BAR2: 'MMBAR'   MEM f0a00400-f0a00600 (0x200 len)	Mixer Base Address (mem)
	# BAR3: 'MMBAR'   MEM f0a00600-f0a00700 (0x100 len)	Bus Master Base Address (mem)
	# IRQ 5
	# (note: f0000000 is nearly 4Gb, so is virtual mem as the box only has 3Gb)
	# XXX fix pci code - must be 2100! read is ffff2100

	mov	ecx, [ebx + dev_pci_addr]
	xor	dl, dl
	lea	edi, [ebx + ac97_mixer_pio]
0:	mov	al, dl
	call	pci_get_bar_addr
	stosd
	inc	dl
	cmp	dl, 4
	jb	0b

	DEBUG "Mixer";
	DEBUG_DWORD [ebx + ac97_mixer_pio], "PIO"
	DEBUG_DWORD [ebx + ac97_mixer_mmio], "MMIO"
	DEBUG "Bus"
	DEBUG_DWORD [ebx + ac97_bus_pio], "PIO"
	DEBUG_DWORD [ebx + ac97_bus_mmio], "MMIO"
	call	newline

.if !(AC97_MMIO_ONLY|AC97_PIO_ONLY|IO_MULTI_INLINE)
	# set up instance methods. We can override the VPTR methods.
	cmpd	[ebx + ac97_mixer_mmio], 0	# detect MMIO
	jz	1f
	mov	[ebx + ac97_api_chan_read], dword ptr offset ac97_chan_read_mmio$
	mov	[ebx + ac97_api_chan_write], dword ptr offset ac97_chan_write_mmio$
	mov	[ebx + ac97_api_mixer_read], dword ptr offset ac97_mixer_read_mmio$
	mov	[ebx + ac97_api_mixer_write], dword ptr offset ac97_mixer_write_mmio$
	jmp	2f
1:
	mov	[ebx + ac97_api_chan_read], dword ptr offset ac97_chan_read_pio$
	mov	[ebx + ac97_api_chan_write], dword ptr offset ac97_chan_write_pio$
	mov	[ebx + ac97_api_mixer_read], dword ptr offset ac97_mixer_read_pio$
	mov	[ebx + ac97_api_mixer_write], dword ptr offset ac97_mixer_write_pio$
2:
.endif

	# reset mixer
	AC97_MIXER_WRITE RESET, 42
	mov	eax, 2	# COLD_RESET
	AC97_CHANNEL_WRITE GLOBAL_CONTROL, eax #(byte ptr 2)	# COLD_RESET
	mov	eax, 100 * 1000	# 100 ms wait
	call	udelay	# can't use sleep (requires scheduler)

	# set volume
	TMP_VOLUME = 0	# 0 = max
	AC97_MIXER_WRITE MASTER_VOL,	(TMP_VOLUME<<8) | TMP_VOLUME
	AC97_MIXER_WRITE PCM_OUT_VOL,	(TMP_VOLUME<<8) | TMP_VOLUME
	AC97_MIXER_WRITE MONO_VOL,	TMP_VOLUME
	AC97_MIXER_WRITE PC_BEEP_VOL,	TMP_VOLUME


.if AC97_TEST
	push	ebp
	pushd	0
	mov	ebp, esp
	mov	ecx, 16
0:	mov	[ebp], ecx
	decd	[ebp]
	call	ac97_reg_size$
	call	newline
	loop	0b

	add	esp, 4
	pop	ebp

	call	more
.endif
	ret


####################################
# Dynamic MMIO/PIO methods
#
# One set of methods implements MMIO, the other PIO.
# The object method pointers will be initialized with
# either depending on the results of examining the PCI BARs.
.if !(AC97_MMIO_ONLY|AC97_PIO_ONLY|IO_MULTI_INLINE)

# in: [ebp]: AC97_CHANNEL_REG_*
# out: SF = 1: dword (has priority over ZF): 0: use ZF
# out: ZF = 1: word, 0: byte
ac97_reg_size$:
	push_	ecx eax
	mov	cx, [ebp]
	#DEBUG_WORD cx	# register
		#       f  e  d  c  b  a  9  8  7  6  5  4  3  2  1  0
		#       dw dw dw dw dw dw dw dw dw dw dw dw dw dw dw dw # [0,1,2] = [00, 01, 10]
		#	xx xx xx D   B  B xx  W xx  W  B  B xx xx xx D
	#mov	edx, 0b 00 00 00 10 00 00 00 01 00 01 00 00 00 00 00 10	# log2[1,2,4]
	mov	eax, 0b00000010000000010001000000000010
	add	cl, cl
	shr	eax, cl
	and	al, 3
	# Now we need to return some flags for al.
	# Unfortunately this does not work: bt clears ZF.
	#	and	al, 3	# first we set ZF
	#	bt	dx, 1	# next we set CF (only need dl but bt doesn't support byte)
	# So we pick SF and ZF since they are consecutive bits (7 and 6; CF = 0)
	#
	# al SF ZF
	#----------
	# 0  0  0
	# 1  0  1	jz word		(do this second)
	# 2  1  0	js dword	(do this first)
	# 3   N/A
	shl	al, 6
	lahf	# load flags into ah
	and	ah, ~((1<<6)|(1<<7))	# clear ZF/SF
	or	ah, al
	sahf	# store ah into flags

.if AC97_TEST	# called from init: print test output
	js	4f
	jz	2f

1:	DEBUG "byte"; jmp 9f
2:	DEBUG "word"; jmp 9f
4:	DEBUG "dword"
9:
.endif
	pop_	eax ecx
	ret



# These methods expect ebx to be the device pointers,
# even though they are declared as class methods (expecting this=eax).
# all methods:
# in: [esp] = AC97_CHANNEL_REG_*
# in: eax
# read methods:
# out: eax
# write methods:
# in: eax


# Mixer register routines. All accesses are 16 bit.
ac97_mixer_read_mmio$:
	DEBUG "mixer_read_mmio"
	push	esi
	mov	esi, [ebx + ac97_mixer_mmio]
	add	esi, [esp + 8]
	mov	ax, [esi]
	pop	esi
	ret	4
ac97_mixer_write_mmio$:
	DEBUG "mixer_write_mmio"
	push	esi
	mov	esi, [ebx + ac97_mixer_mmio]
	add	esi, [esp + 8]
	mov	[esi], ax
	pop	esi
	ret	4

ac97_mixer_read_pio$:
	DEBUG "mixer_read_pio"
	push	edx
	mov	dx, [ebx + ac97_mixer_pio]
	add	dx, [esp + 8]
	in	ax, dx
	pop	edx
	ret	4
ac97_mixer_write_pio$:
	DEBUG "mixer_write_pio"
	push	edx
	mov	dx, [ebx + ac97_mixer_pio]
	add	dx, [esp + 8]
	out	dx, ax
	pop	edx
	ret	4


# Channel access routines: 8, 16 or 32 bit.

# xs: read, write
# mode: mmio, pio
.macro TMP_METHOD xs, mode
	ac97_chan_\xs\()_\mode\()$:
		push_	esi ebp
		lea	ebp, [esp + 12]
	.ifc \mode,mmio
		TMP_REG = esi
	.else
		TMP_REG = dx
	.endif
		mov	TMP_REG, [ebx + ac97_bus_\mode]
		add	TMP_REG, [ebp]
		call	ac97_reg_size$
		js	4f
		jz	2f

		.if AC97_DEBUG
			DEBUG "CHAN_\xs\()_\mode\()"
			1: DEBUG "byte"; jmp 1f
			2: DEBUG "word"; jmp 2f
			4: DEBUG "dword"; jmp 4f
		.endif

	.ifc \mode,mmio
		.ifc \mode,read
	1:	mov	eax, [esi]; jmp 9f
	2:	mov	ax, [esi]; jmp 9f
	4:	mov	al, [esi]
		.else
	1:	mov	[esi], eax; jmp 9f
	2:	mov	[esi], ax; jmp 9f
	4:	mov	[esi], al
		.endif
	.else
		.ifc \mode,read
	1:	in	eax, dx; jmp 9f
	2:	in	ax, dx; jmp 9f
	4:	in	al, dx
		.else
	1:	out	dx, eax; jmp 9f
	2:	out	dx, ax; jmp 9f
	4:	out	dx, al
		.endif
	.endif

	9:	pop_	ebp esi
		ret	4
.endm

.irp xs, read, write
.irp mode, mmio, pio
	TMP_METHOD \xs, \mode
.endr
.endr

.purgem TMP_METHOD

.endif


###########################################
ac97_isr:
	# using the irq_proxies / irq_isr so ds/es properly setup
	pushad
	mov	ebx, edx	# see irq_isr and (dev_)add_irq_handler
	mov	esi, [ebx + ac97_bus_mmio]

	.if AC97_DEBUG_ISR
		DEBUG "ac97 IRQ";
		call newline
	.endif

	AC97_CHANNEL_READ GLOBAL_STATUS, eax
	cmp	eax, -1
	jnz	1f
	printc 12, "ac97_isr: STATUS -1"
	xor	eax, eax
	AC97_CHANNEL_WRITE GLOBAL_CONTROL, eax
	#DEBUG "System halt";0:hlt;jmp 0b
	int3	# invoke debugger from within intrrupt... ;-)
	jmp	9f
1:

	.if AC97_DEBUG_ISR
		AC97_DEBUG_GLOBAL_REGS
		AC97_DEBUG_CHAN PI
		AC97_DEBUG_CHAN PO
		AC97_DEBUG_CHAN MC
		AC97_DEBUG_CHAN MC2
		AC97_DEBUG_CHAN PI2
		AC97_DEBUG_CHAN SP
	.endif

	AC97_CHANNEL_READ GLOBAL_STATUS, eax
	test	eax, AC97_GLOBAL_STATUS_POI
	jz	1f
### PCM OUT handler
	.if AC97_DEBUG_ISR
		DEBUG "PCM OUT"
		AC97_CHANNEL_READ PO_CIV, al; DEBUG_BYTE al, "CIV"
		AC97_CHANNEL_READ PO_LVI, al; DEBUG_BYTE al, "LVI"
		AC97_CHANNEL_READ PO_PIV, al; DEBUG_BYTE al, "PIV"
	.endif
	# First time,
	# CIV = LIV = 0, PIV 1
	AC97_CHANNEL_READ PO_SR, ax
	AC97_CHANNEL_WRITE PO_SR, ax	# W/C

	mov	dx, ax	# backup

	# before DMA halts, we get a warning: FIFOE, LVBC, and OC
	# the OC is because we asked for an interrupt in all even
	# descriptors (which are 2 descriptors repeated 16 times).
	#
	# set last valid descriptor
	AC97_CHANNEL_READ PO_LVI, al
	inc	al
	and	al, 31
	AC97_CHANNEL_WRITE PO_LVI, al
	.if AC97_DEBUG_ISR
		DEBUG_BYTE al, "SET LVI"
		call	newline
	.endif

	# NOTE: duplicate code!
	mov	ecx, [ebx + sound_playback_handler]
	jecxz	1f
	#pushad
	call	ecx
	#popad
#########
1:
9:
	# EOI handled by IRQ_SHARING code
	popad
	iret


#########################################################################
ac97_set_samplerate:
	DEBUG "TODO: AC97 samplerate"
	ret

# in: al: bit1 = 16bit; bit 0=stereo
ac97_set_format:
	# the card only supports 16* or 20 bit 2*,4 or 6 channels.
	DEBUG "TODO: AC97 samplesize"
	ret

# in: eax = playback handler
ac97_playback_init:
	push_	esi eax
	mov	[ebx + sound_playback_handler], eax
	mov	esi, [ebx + ac97_bus_mmio]

	printlnc 15, "Initializing playback..."

	.if AC97_DEBUG
		AC97_DEBUG_GLOBAL_REGS
	.endif
	AC97_CHANNEL_READ GLOBAL_CONTROL, eax
	and	eax, ~( AC97_GLOBAL_CONTROL_LSO | AC97_GLOBAL_CONTROL_WARM_RESET )
	or	eax, AC97_GLOBAL_CONTROL_GIE | AC97_GLOBAL_CONTROL_IE_S0 # | AC97_GLOBAL_CONTROL_WARM_RESET
	AC97_CHANNEL_WRITE GLOBAL_CONTROL
	.if AC97_DEBUG
		AC97_DEBUG_GLOBAL_REGS

		AC97_DEBUG_CHAN PO
	.endif
	AC97_CHANNEL_READ PO_CR, al
	and	al, ~( AC97_CHANNEL_CONTROL_RESET | AC97_CHANNEL_CONTROL_BM_ENABLE )
	or	al, AC97_CHANNEL_CONTROL_IE_OC	| AC97_CHANNEL_CONTROL_IE_FIFOE	| AC97_CHANNEL_CONTROL_IE_LVBC #| AC97_CHANNEL_CONTROL_RESET
# set on playback start: AC97_CHANNEL_CONTROL_BM_ENABLE	= 1 << 0	# Run/Pause bus master. (can busmaster disable/enable and resume)
	AC97_CHANNEL_WRITE PO_CR, al
	.if AC97_DEBUG
		AC97_DEBUG_CHAN PO
	.endif

	call	ac97_setup_buffer$	# alloc and init buf_po (buffer descriptor ring)

	pop_	eax esi
	ret

ac97_setup_buffer$:
	call	ac97_alloc_dr$	# allocate descriptor ring; out: eax
	jc	9f
	mov	[ebx + ac97_buf_po], eax
	mov	edi, eax

	# configure ring address
	GDT_GET_BASE eax, ds
	add	eax, edi
	.if AC97_DEBUG
		DEBUG_DWORD eax, "PO_BDBAR"
	.endif
	AC97_CHANNEL_WRITE PO_BDBAR, eax
9:	ret


ac97_playback_start:
	push_	edi esi edx ecx eax
	.if AC97_DEBUG
		DEBUG_DWORD eax, "playbacks handler"
	.endif
	mov	[ebx + sound_playback_handler], eax
	mov	esi, [ebx + ac97_bus_mmio]

	# setup a descriptor.
	mov	edi, [ebx + ac97_buf_po]
	lea	edi, [edi + AC97_DESCRIPTOR_SIZE * 0]

	# write all descriptors. There is only 1 DMA buffer,
	# filled in two parts. We will thus alternate
	# the DMA buffer offset in each pair of descriptors.
	# Further, we repeat each pair 16 times so as to fill
	# all the descriptors (I have not seen the documentation
	# that would allow for a reset of the Descriptor Index
	# Counter - execept a warm reset which would require
	# to reconfigure the descriptor base address.
	mov	ecx, 32
	mov	edx, [dma_buffersize]
	shr	edx, 1	# half a buffer
	.if AC97_DEBUG
		DEBUG_DWORD edx
		call	newline
	.endif
0:

# apparently the documentation is unclear: the size is in bytes per channel
shr edx, 1
	mov	[edi + ac97_desc_size], dx
shl edx, 1
	mov	eax, [dma_buffer_abs]

	# configure the even buffers to:
	# - contain the first half of the DMA buffer,
	# - trigger a FIFO buffer underrun interrupt (BUP)
	# configure the odd buffers to:
	# - contain the 2nd half of the DMA buffer.
	# - trigger an On Completion interrupt (IOC)
	# [see ac97_isr]

	test	cl, 1		# when odd,
	jz	1f
	add	eax, edx	# 2nd half of buffer
	movb	[edi + ac97_desc_flags], AC97_DESC_IOC
	jmp	2f
1:	movb	[edi + ac97_desc_flags], AC97_DESC_IOC | AC97_DESC_BUP
2:	mov	[edi + ac97_desc_addr], eax

	.if AC97_DEBUG
		DEBUG_DWORD ecx
		DEBUG_DWORD [edi + ac97_desc_addr],"ADDR"
		DEBUG_WORD [edi + ac97_desc_size],"SIZE"
		DEBUG_BYTE [edi + ac97_desc_flags-1],"RSVD"
		DEBUG_BYTE [edi + ac97_desc_flags],"FLAGS"
		call	newline
	.endif

	add	edi, AC97_DESCRIPTOR_SIZE
	.if AC97_DEBUG
	dec	ecx
	jnz	0b
	.else
	loop	0b
	.endif

	# set last valid descriptor
	xor	al, al # maybe 1
	AC97_CHANNEL_WRITE PO_LVI, al

	# play
	AC97_CHANNEL_READ PO_CR, al
	or	eax, AC97_CHANNEL_CONTROL_BM_ENABLE
	AC97_CHANNEL_WRITE PO_CR, al

	pop_	eax ecx edx esi edi
	ret

ac97_alloc_dr$:
	mov	eax, 32 * 8
	mov	edx, 8
	call	mallocz_aligned
	jc	9f
9:	ret


ac97_playback_stop:
	push	esi
	mov	esi, [ebx + ac97_bus_mmio]
	#AC97_CHANNEL_WRITE PO_CR, (word ptr AC97_CHANNEL_CONTROL_BM_ENABLE)

	# TODO: add macro AC97_CHANNEL_OR etc and optimize OR for mmio
	AC97_CHANNEL_READ PO_CR, al
	and	al, ~AC97_CHANNEL_CONTROL_BM_ENABLE
	AC97_CHANNEL_WRITE PO_CR, al

	# stop calling update on IRQ
	mov	dword ptr [ebx + sound_playback_handler], 0
	pop	esi
	ret

