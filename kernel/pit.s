###########################################################################
# PIT - Programmable Interval Timer 
#
# DOC/Specs/intel-82c54-timer.pdf
#
.intel_syntax noprefix

PIT_IO = 0x40
# PIT2 is either 0x50 or 0xa0 depending on documentation

PIT_FREQUENCY = 250	# 4 ms accuracy

PIT_DEBUG = 1

.if PIT_DEBUG
#PIT_FREQUENCY = 18
.endif

#############################################################################################
# Chip description:
#
# Symbol| DIP |PLCC |I/O|description
# ------|-----|-----|---|----------------------------------------------
# D7-D0	| 1-8 | 2-9 |I/O|data bus buffer - system data bus (register)
# CLK  0|   9 |  10 | I |counter 0 clock input
# OUT  0|  10 |  12 | O |counter 0 clock output
# GATE 0|  11 |  13 | I |counter 0 gate input
# GND   |  12 |  14 |   |0V ground
# OUT  1|  13 |  16 | O |counter 1 clock output
# GATE 1|  14 |  17 | I |counter 1 gate input
# CLK  1|  15 |  18 | I |counter 1 clock input
# GATE 2|  16 |  19 | I |counter 1 gate input
# OUT  2|  17 |  20 | O |counter 1 clock output
# CLK  2|  18 |  21 | I |counter 1 clock input
# A1,A0 |20-19|23-22| I |address - see PIT_PORT below.
# ! CS  |  21 |  24 | I |chip select: 0=respond to RD, WR; 1=ignore
# ! RD  |  22 |  26 | I |read control: 0=read operation
# ! WR  |  23 |  27 | I |write control: 0=cpu write operation
# Vcc   |  24 |  28 |   | +5V power
# NC    |     |     |   | no-connect: PLCC 1, 11, 15, 25

# GATE 0 and 1 are not connected.
# GATE 2 is connected to port 0x61, bit 0 (writable).
# OUT 0 is connected to IRQ 0.
# OUT 1 is not connected/unusable/DRAM refreshing.
# OUT 2 is connected to the speaker, readable in 0x61 bit 5, writable bit 1.
# CS, RD, WR are hardwired to the CPU's IN/OUT instructions.
# A1, A0 are hardwired to the CPU's ports: 4 byte-ports, at PIT_IO.
# These map D7-D0 to the port:
# A1,A0 | port | D7-D0
# ----------------------
#  00   | 0x40 |
#  01   | 0x41 |
#  10   | 0x42 |
#  11   | 0x43 | control: determines values for ports 0x40,0x41,0x42
PIT_PORT_COUNTER_0 = PIT_IO + 0 # A1,A0 = 0b00
PIT_PORT_COUNTER_1 = PIT_IO + 1 # A1,A0 = 0b01
PIT_PORT_COUNTER_2 = PIT_IO + 2 # A1,A0 = 0b10
PIT_PORT_CONTROL   = PIT_IO + 3	# A1,A0 = 0b11

# Control Word: (commands):	[ SC1 | SC0 | RW1 | RW0 | M2 | M1 | M0 | BCD ]
PIT_CW_SC_0		= 0b00 << 6	# select counter 0
PIT_CW_SC_1		= 0b01 << 6	# select counter 1
PIT_CW_SC_2		= 0b10 << 6	# select counter 2
PIT_CW_SC_RB		= 0b11 << 6	# read-back
  PIT_CW_SC_RB_COUNT	= 0 << 5	# NOTE! inverse-flag!
  PIT_CW_SC_RB_STATUS	= 0 << 4	# NOTE! inverse-flag!
  PIT_CW_SC_RB_CNT2	= 1 << 3
  PIT_CW_SC_RB_CNT1	= 1 << 2
  PIT_CW_SC_RB_CNT0	= 1 << 1

PIT_CW_RW_CL		= 0b00 << 4	# counter-latch command
PIT_CW_RW_LSB		= 0b01 << 4	# read/write LSByte only
PIT_CW_RW_MSB		= 0b10 << 4	# read/write MSByte only
PIT_CW_RW_LSB_MSB	= 0b11 << 4	# read/write LSB then MSB

PIT_CW_M_0		= 0b000 << 1	# mode 0
PIT_CW_M_1		= 0b001 << 1	# mode 1
PIT_CW_M_2		= 0b010 << 1	# mode 2 (high bit=don't care)
PIT_CW_M_3		= 0b011 << 1	# mode 3 (high bit=don't care)
PIT_CW_M_4		= 0b100 << 1	# mode 4
PIT_CW_M_5		= 0b101 << 1	# mode 5

PIT_CW_BCD		= 0b1 << 0	# BCD counter

# Internal modes:
#MODE_CLK_PULSE	=	# CLK -> sin(0..PI)
#MODE_TRIGGER	=	# GATE -> cos(PI..2PI)
#MODE_LOAD_COUNTER=	# CR -> CE (count reg->count elemt) transfer


# Modes:
# - Mode 0
# event counter; interrupt on terminal count.
# write control word/count: OUT -> 0. Counter==0: OUT->1
# GATE=1: enable counting; 0=disable.
#
# - Mode 1: hardware-retriggerable one-shot.
# initially: OUT=1. on CLK, OUT->0; counter=0: OUT->1, until trigger.
# trigger: loading counter, set out low (how?)
#
# - Mode 2: rate generator (divide-by-N counter)
# initially: OUT=1; when count=1: OUT->0; when count=0: OUT->1, CR->CE(rept).
# count must be > 1. Writing new count takes effect after current period.
#
# - Mode 3: square wave.
# same as mode 2, except instead of OUT->0 for 1 CLK, OUT->0 for 2nd half
# of cycle.



# Read operations:
# - simple read operation: (inhibit CLK by gate or external logic)
#     in al, PIT_PORT_COUNTER_x (possibily followed by 2nd read)
# - Counter Latch command:
#     # this stores the current counter value in a 'latch', until read.
#     out PIT_PORT_CONTROL, PIT_CW_RW_CL | PIT_CW_SC_?
#     in  al, PIT_PORT_COUNTER_?
#
# - read-back command
#
#   command byte format: [ 11 | !COUNT | !STATUS | CNT2 | CNT1 | CNT0 | 0]
#
#     out PIT_PORT_CONTROL, 0b11CSabc0 (C=!count,S=!status,a,b,c=CNT2..CNT0)
#     # when C=0, the count of the selected counter is latched;
#     # when S=0, the status of the selected counter is latched
#     # abc: to which counters to apply the command.
#   example:
#     out PIT_PORT_CONTROL, PIT_SC_RB | PIT_SC_RB_COUNT | PIT_SC_RB_CNT?
#     in al, PIT_PORT_COUNTER_?
#
#   example of reading status:
#     out PIT_PORT_CONTROL, PIT_SC_RB | PIT_SC_RB_STATUS | PIT_SC_RB_CNT?
#     in  al, PIT_PORT_COUNTER_?	# read status
#
#  status format: [output | nullcount | RW1 | RW0 | M2 | M1 | M0 | BCD]
#      output: current state of out pin
#      nullcount: 1: null count (on writes to control/count register (CR)),
#       0: (CE) count element is loaded from CR (and counting)
#      RW1,RW0,M2,M1,M0,BCD: counter programmed mode.
#
#  When both count and status are latched
#  (PIT_CW_SC_RB_COUNT | PIT_CW_SC_RB_STATUS),
#  the first read returns the status, the 2nd (and third) the count.
#
# End of chip description.
####################################################################################################

.data SECTION_DATA_BSS
clock:			.long 0		# IRQ counter
pit_timer_frequency:	.long 0, 0	# in Hz: fixedpoint
pit_timer_interval:	.long 0		# 'reload value'/CLK pulse counter, written to 0x40, max 0x10000
pit_timer_period:	.long 0, 0	# in milliseconds: fixedpoint
pit_print_timer$:	.byte 0
clock_ms:		.long 0, 0	# accumulated time: [clock] * [pit_timer_period] (49 days)
.text32

pit_hook_isr:
	mov	cx, SEL_compatCS
	movzx	eax, byte ptr [pic_ivt_offset]
	# add eax, IRQ_TIMER
	mov	ebx, offset pit_isr
	call	hook_isr
pit_enable:
	call	pit_init
	PIC_ENABLE_IRQ IRQ_TIMER
	ret

pit_disable:
	PIC_DISABLE_IRQ IRQ_TIMER

	# reset to 18.206 Hz
	mov	al, PIT_CW_SC_0 | PIT_CW_RW_LSB_MSB | PIT_CW_M_2 # 0b00110100
	pushf
	cli
	out	PIT_PORT_CONTROL, al
	xor	al, al	# 0x10000
	out	PIT_PORT_COUNTER_0, al	# lsb
	out	PIT_PORT_COUNTER_0, al	# msb
	popf
	ret

pit_init:
	I "PIT "
	mov	al, PIT_CW_SC_0 | PIT_CW_RW_LSB_MSB | PIT_CW_M_2 # 0b00110100
	out	PIT_PORT_CONTROL, al

	mov	eax, PIT_FREQUENCY

	.if PIT_DEBUG
		printc 11, "request "
		mov	edx, eax
		call	printdec32
		print " Hz: "
	.endif

	call	pit_calc_interval
	mov	[pit_timer_interval], eax

	.if PIT_DEBUG
		printc 11, "ticks "
		mov	edx, eax
		call	printdec32
	.endif

	pushf
	cli	# prevent countdown during loading of reload-value
	out	PIT_PORT_COUNTER_0, al
	xchg	al, ah
	out	PIT_PORT_COUNTER_0, al
	popf
	xchg	al, ah

	push	eax
	call	pit_calc_frequency	# in: eax; out: edx:eax
	mov	[pit_timer_frequency], edx
	mov	[pit_timer_frequency + 4], eax
	.if PIT_DEBUG
		printc 13, " (actual: "
		mov	bl, 4
		call	print_fixedpoint_32_32$
		print " Hz "
	.endif
	pop	eax


	call	pit_calc_period

	mov	[pit_timer_period], edx
	mov	[pit_timer_period + 4], eax

	.if PIT_DEBUG
		printc 13, "resolution: "
		mov	edx, [pit_timer_period]
		mov	eax, [pit_timer_period+4]
		mov	bl, 4
		call	print_fixedpoint_32_32$
		print " ms"
		printlnc 13, ")"
	.endif

	ret

# Base frequency:	14.31818 Mhz
# cpu bus frequency:	14.31818 MHz / 3  = 4.77272[6] MHz  (0.1[6] means 0.1666..)
# CGA frequency:	14.31818 MHz / 4  = 3.579545   MHz
# PIT Frequency:	14.31818 MHz / 12 = 1.193181[6] MHz (CPU && CGA)

PIT_FREQ_ROUND	= 1193182	# rounded
PIT_FREQ_INT	= 1193181	# fixed point precise
PIT_FREQ_FRAC	= 0xaaaaaaaa	# (2<<32)/3

# Typically the PIT is inaccurate to about 1.37 seconds/day.
# .000015856[481] per second (or double: .00003171[296]).
# This leaves 4 decimal accuracy for the input of the calculations.
# The calc_frequency calculation itself is accurate up to and including 9 decimals,
# and the calc_period calculation itself is accurate up to and including 8 decimals.


# in: eax = interval - clock delay counter
# out: edx:eax = 32:32 fixed point Hz
pit_calc_frequency:
	# bind ebx to [1..65536]
	mov	ebx, eax
	cmp	ebx, 0x00010000
	jbe	0f
	mov	ebx, 0x00010000
0:	cmp	ebx, 0
	ja	0f
	mov	ebx, 1
0:
	# we have 15 bits left to shift left (as ebx is max 0x00010000),
	# so we'll shift for increased accuracy:
	FREQ_BIT_SHIFT = 15

	shl	ebx, FREQ_BIT_SHIFT
	# 1193181.[6] << FREQ_BIT_SHIFT:
	mov	edx, (PIT_FREQ_INT >> (32 - FREQ_BIT_SHIFT))
	mov	eax, 0xffffffff & ((PIT_FREQ_INT << FREQ_BIT_SHIFT) | (PIT_FREQ_FRAC >> (32-FREQ_BIT_SHIFT)))
	div	ebx
	# convert rest in edx to fixedpoint:
	push	eax
	mov	eax, edx
	mul	ebx	# both ebx and edx are FREQ_BIT_SHIFT too large
	shrd	eax, edx, 2 * FREQ_BIT_SHIFT	# accuracy: 9 digits
	# shifting edx that much yields 0
	pop	edx
	ret

# Lowest frequency: 18.206507364 90885416666 Hz
#                                7536337 

# in: eax = frequency in Hz
# out: eax = clock interval (nr of CLK pulses of 1/1193181.[6] Hz)
pit_calc_interval:
	mov	ebx, eax
	mov	eax, 65536
	cmp	ebx, 18 	# 18.2065...
	jbe	1f
	mov	eax, 1
	cmp	ebx, PIT_FREQ_ROUND
	jae	1f

	# a bit more accuracy for easy rounding
	INTERVAL_BIT_SHIFT = 2
	shl	ebx, INTERVAL_BIT_SHIFT
	mov	eax, (PIT_FREQ_INT << INTERVAL_BIT_SHIFT) | (PIT_FREQ_FRAC >> (32-INTERVAL_BIT_SHIFT))
	xor	edx, edx
	div	ebx
1:	ret


# in: eax = interval (clock ticks)
# out: edx:eax = 32:32 fixedpoint millisecond interval duration
pit_calc_period:
	# calculate period:
	# ticks * 1000 / 1193181.[6] = ticks / 1193.181[6]
	# max shift: 1<<42 / 1193.181[6] = 3685982305.9388832938
	#				   3685982305 (osdev)
	mov	ebx, 3685982306
	mul	ebx
	shrd	eax, edx, 10
	shr	edx, 10		# accurate to 8 decimals
	ret


pit_isr:
	push	es
	push	ds
	push	eax
	push	edx

	mov	edx, SEL_compatDS	# required for PRINT_START, PRINT
	mov	ds, edx
	mov	es, edx

	.if 0	# don't read the counter, it's no use
	#xor	al, al		# read channel 0 (bits 6,7 = channel)
	mov	al, byte ptr PIT_CW_RW_CL | PIT_CW_SC_0
	out	PIT_PORT_CONTROL, al	# 0x43

	in	al, PIT_PORT_COUNTER_0	# 0x40
	movzx	edx, al
	in	al, PIT_PORT_COUNTER_0	# 0x40
	mov	dh, al
	.endif

	inc	dword ptr [clock]

	# pit_timer_period stored as 32:32 fixed point
	mov	eax, [pit_timer_period + 4]
	mov	edx, [pit_timer_period + 0]
	# update clock_ms (32:32 fp)
	add	[clock_ms + 4], eax
	adc	[clock_ms + 0], edx

	# update clock_ms_fp (40:24 fp)
	shrd	eax, edx, 8	# convert to 40:24
	shr	edx, 8
	add	[clock_ms_fp + 4], eax
	adc	[clock_ms_fp + 0], edx

########
	cmp	byte ptr [pit_print_timer$], 0
	jz	0f

	pushf
	cli	# 'mutex'

	PUSH_SCREENPOS

	PRINT_START 8
	mov	ax, (8<<8) | '('
	stosw

	push	esi
	LOAD_TXT "TIMER "
	mov	ah, 13
	call	__print
	pop	esi
	call	__printhex4

	mov	ax, (8<<8)|','
	stosw

	mov	ah, 9

	mov	dx, [clock]
	call	__printhex4

	mov	al, ')'
	stosw
	PRINT_END #1
	POP_SCREENPOS

	popf
0:
	
	mov	al, 0x20
	out	0x20, al
	pop	edx
	pop	eax
	pop	ds
	pop	es
	iret


########## for now here:

# in: eax = nr of microseconds to delay
udelay:
	push	ecx
	mov	ecx, eax
	# reading from an IO port equals 1 microsecond delay
0:	in	al, 0x80	# DMA page register, safe to read.
	loop	0b
	pop	ecx
	ret

# in: eax = milliseconds
sleep:
.if 1
	YIELD eax
.else
	push_	ebx edx
	mov	edx, eax
	call	get_time_ms
	add	edx, eax
	mov	ebx, eax
0:	cmp	dword ptr [task_queue_sem], -1
	jz	1f
	YIELD
	jmp	2f
1:	hlt
2:	call	get_time_ms
	cmp	eax, edx
	jb	0b
	sub	eax, ebx
0:	pop_	edx ebx
.endif
	ret

pit_test:
#	ENTER_CPL0
	mov	ecx, 0
0:	

cli
	mov	al, PIT_CW_RW_CL | PIT_CW_SC_0
	out	PIT_PORT_CONTROL, al
	in	al, PIT_PORT_COUNTER_0
	mov	ah, al
	in	al, PIT_PORT_COUNTER_0
	xchg	al, ah
	mov edx,[clock]
sti
	DEBUG_DWORD edx
	DEBUG_WORD ax

	mov	al, 0b11100010#PIT_CW_SC_RB | (1<<5) | PIT_CW_SC_RB_STATUS | PIT_CW_SC_0
	out	PIT_PORT_CONTROL, al
	in	al, PIT_PORT_COUNTER_0
	DEBUG_BYTE al

call newline
	loop	0b
	call	newline

	ret


.data
last_time: .long 0,0


cur_clock:	.long 0
cur_status:	.byte 0
latch_val:	.word 0
frac:		.long 0,0
.global clock_ms_fp
clock_ms_fp:	.long 0, 0 # clock_ms >> 8 (34 year; 24 bit fraction)

last_clock:	.long 0
last_status:	.byte 0
last_latch_val:	.word 0
last_frac:	.long 0,0
last_clock_ms_fp:.long 0,0
.text32
# out: edx:eax >> 24 = milliseconds (24 bit fractional part)
get_time_ms_40_24:
	ENTER_CPL0

	pushf
	cli	# lock pit port / disable scheduler
	MUTEX_SPINLOCK TIME

	push_	ebx ecx edi esi

mov eax, [clock]
mov [cur_clock], eax
	mov	esi, [clock_ms_fp+4]
	mov	edi, [clock_ms_fp+0]
	.if 1
	mov	eax, PIT_CW_RW_CL | PIT_CW_SC_0
	out	PIT_PORT_CONTROL, al
	in	al, PIT_PORT_COUNTER_0
	mov	ah, al
	in	al, PIT_PORT_COUNTER_0
	xchg	al, ah
	mov	[latch_val], ax
		.if 0
		push	eax
		mov	eax, 0b11100010#PIT_CW_SC_RB | (1<<5) | PIT_CW_SC_RB_STATUS | PIT_CW_SC_0
		out	PIT_PORT_CONTROL, al
		in	al, PIT_PORT_COUNTER_0
		mov	[cur_status], al
		pop	eax
		.endif
	.else
	mov	eax, (PIT_CW_SC_RB) | (PIT_CW_SC_RB_COUNT) | (PIT_CW_SC_RB_STATUS) | (PIT_CW_SC_0)
	out	PIT_PORT_CONTROL, al
	in	al, PIT_PORT_COUNTER_0
	mov	[cur_status], al
	in	al, PIT_PORT_COUNTER_0
	mov	ah, al
	in	al, PIT_PORT_COUNTER_0
	xchg	al, ah
	mov	[latch_val], ax
	.endif



	# eax = counter (counts down!)
	# (pit_timer_interval - counter) / pit_timer_interval = fraction
	# fraction * pit_timer_period = ms

	mov	ebx, [pit_timer_interval]
	sub	eax, ebx 	# elapsed counter
	neg	eax
	mov	edx, eax
	xor	eax, eax
	div	ebx		# eax = fraction <<32

	# multiply by the period:
	mov	ebx, eax
	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]

	shrd	eax, edx, 16
	shr	edx, 16

	mul	ebx
	# shr 16: have edx be ms since boot, and eax the fractional part
	# shr 8: divide by 256, so that eax>>24 == ms.
	# this allows for 34.865 years of uptime (without the >>8 only 49 days)
	shrd	eax, edx, 16+8
	shr	edx, 16+8
mov [frac], edx
mov [frac+4], eax
	
	add	eax, esi#[clock_ms_fp+4]
	adc	edx, edi#[clock_ms_fp]

	# check for negative time
	mov	edi, [last_time]
	mov	esi, [last_time+4]
	mov	ecx, edx
	mov	ebx, eax
	sub	ebx, esi
	sbb	ecx, edi
	jns	2f	# allright
#DEBUG "time adj"
	# we'll adjust, assuming we missed a tick
	mov	edi, [pit_timer_period]
	mov	esi, [pit_timer_period+4]

	shrd	esi, edi, 8
	shr	edi, 8
	add	eax, esi
	adc	edx, edi
1:
	# check again
	mov	edi, [last_time]
	mov	esi, [last_time+4]
	mov	ecx, edx
	mov	ebx, eax
	sub	ebx, esi
	sbb	ecx, edi
	jns	2f

.if 0
	printc 4, "ERROR: last time diff"
	DEBUG_DWORD edx
	DEBUG_DWORD eax
	DEBUG_DWORD edi
	DEBUG_DWORD esi
	call	newline

	DEBUG "cur  "
	DEBUG_DWORD [cur_clock],"clock"
	DEBUG_DWORD [clock_ms_fp],"ms"
	DEBUG_DWORD [clock_ms_fp+4]," "
	DEBUG_BYTE  [cur_status], "ST"
	DEBUG_WORD  [latch_val], "latch"
	DEBUG_DWORD [frac], "frac"
	DEBUG_DWORD [frac+4], " "
	call	newline

	DEBUG "last "
	DEBUG_DWORD [last_clock], "clock"
	DEBUG_DWORD [last_clock_ms_fp], "ms"
	DEBUG_DWORD [last_clock_ms_fp+4], " "
	DEBUG_BYTE  [last_status], "ST"
	DEBUG_WORD  [last_latch_val], "latch"
	DEBUG_DWORD [last_frac], "frac"
	DEBUG_DWORD [last_frac+4], " "
	call	newline
	DEBUG "timer"
	DEBUG_DWORD [pit_timer_interval], "interval"
	DEBUG_DWORD [pit_timer_period],"period"
	DEBUG_DWORD [pit_timer_period+4]," "
.endif

2:	mov	[last_time], edx
	mov	[last_time+4], eax

	mov	esi, offset cur_clock
	mov	edi, offset last_clock
	movsd	# clock
	movsb	# status
	movsw	# latch
	movsd	# frac
	movsd	# frac+4
	movsd	# clock_ms_fp
	movsd	# clock_ms_fp+4

	MUTEX_UNLOCK TIME

	pop_	esi edi ecx ebx
	popf
	ret

get_time_ms:
	push	edx
	call	get_time_ms_40_24
	shld	edx, eax, 8
	mov	eax, edx
	pop	edx
	ret

.global get_datetime_s
# out: edx = time in seconds since epoch (2000)
get_datetime_s:
	push_	esi eax
	# bypass CMOS: read kernel time
	mov	edx, [clock_ms_fp]
	mov	eax, [clock_ms_fp+4]
	shrd	eax, edx, 24
	shr	edx, 24

	mov	esi, 1000
	idiv	esi		# eax: seconds since boot

	mov	edx, [kernel_boot_time]
	call	datetime_to_s	# TODO: cache
	add	edx, eax

	pop_	eax esi
	ret

