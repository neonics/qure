# See DOC/8259A.pdf
# See DOC/Interrupt.txt
#
# PIC1: ports 0x20, 0x21 : command, data
# PIC1: ports 0xA0, 0xA1 : command, data

IO_PIC1 = 0x20
IO_PIC2 = 0xA0

PIC1_COMMAND = IO_PIC1
PIC1_DATA = PIC1_COMMAND + 1
PIC2_COMMAND = IO_PIC2
PIC2_DATA = PIC2_COMMAND + 2


# PIC 1
IRQ_TIMER	= 0
IRQ_KEYBOARD	= 1
IRQ_CASCADE	= 2
IRQ_COM2	= 3
IRQ_COM1	= 4
IRQ_LPT2	= 5
IRQ_FLOPPY	= 6
IRQ_LPT1	= 7
# PIC 2
IRQ_RTC		= 8
IRQ_FREE1	= 9
IRQ_FREE2	= 10
IRQ_FREE3	= 11
IRQ_PS2_MOUSE	= 12
IRQ_FPU		= 13
IRQ_PRIM_ATA	= 14
IRQ_SEC_ATA	= 15


# A0: bit indicating which port. This is the command port/data port.
# read/write port IO_PICx = A0 = 0; Port IO_PICx+1 = A1
#
# The empty spaces below indicate address bits used in MCS-80, 85 mode,
# which are ignored in 8086 mode.
#
# INIT: Writing a command to CMD port, then 2 to 4 bytes to DATA
#
# A0 | D7 D6 D5 D4 D3 D2 D1 D0  |
# ------------------------------+
#  0 |          1 LTM AI SC ICW4| ICW1: LTM=LTIM, AI=ADI, SC=SNGL
#  1 | t7 t6 t5 t4 t3           | ICW2
#M 1 | s7 s6 s5 s4 s3 s2 s1 s0  | ICW3, Master: mark slaves present.
#S 1 |                s2 s1 s0  | ICW3, Slave: mark slaves present.
#  1 | 0  0  0  SM BF MS AE PM  | ICW4: SM=SFNM, BF=BUF, AE=AEOI, PM=8086
#
# Master mode is designated by SP=1 (an input pin, hardware?), or
# in buffered mode (PIC_ICW4_BUF =1, PIC_ICW4_MS=0). This word (byte)
# is written AFTER ICW4, and thus, the next byte sent will determine
# the interpretation of ICW3.
#
# ICW1 as a command is regocnized by the chip when A0 = 0 and D4 = 1.
# This simply means to write an 1000b (0x10, 16) to the IO_PIC base port.
#
# The IRQ's that get triggered get translated to an address:
# offset = (ICW2 + IRQ) * (ICW1_ADI ? 4 : 8 )

PIC_CMD_INIT	= 0b00010000
# Expect 3 bytes on data port 'Init Command Words'? ICW
# ICW1:
 PIC_ICW1_ICW4		= 0b00000001	# ICW4 needed / not
 PIC_ICW1_SNGL		= 0b00000010	# single / cascade mode
 PIC_ICW1_ADI		= 0b00000100	# call address interval 4 / 8
 PIC_ICW1_LTIM		= 0b00001000	# level triggered/edge mode
 PIC_ICW1_INIT		= 0b00010000	# required bit
 PIC_ICW1_ADDR_MASK	= 0b11100000	# A7-A5 of addr; MCS 80/85 mode only
# ICW2: vector offset

# ICW3: read when PIC1_ICW1_SNGL is not set
 PIC_ICW3_MASTER	= 0b100		# master / slave
 PIC_ICW3_IRQ_MASK	= 0b011		# which irq (0, 1, 2 or 3)

# ICW4: read when PIC1_ICW1_ICW4 is set.
 PIC_ICW4_8086		= 0b00001 # microprocessor mode: 0 = MCS, 1 = 8086
 PIC_ICW4_AEOI		= 0b00010 # automatic end of interrupt mode
 PIC_ICW4_BUF		= 0b00100 # buffered mode; config with MS
 PIC_ICW4_MS		= 0b01000 # master / slave (enabled with BUF)
 PIC_ICW4_SFNM		= 0b10000 # specual fully nested mode




#
# OCW: Operation Control Words (Writing a command to DATA port)
#
# A0 | D7 D6 D5 D4 D3 D2 D1 D0  |
# ------------------------------+
#  1 | m  m  m  m  m  m  m  m   | OCW1: interrupt mask
#  0 | R SL EOI 0  0  l2 l1 l0  | OCW2: l[210]=IR level [R,SL,EOI]=cmd
#                                 EOI:
#      0  0  1                      non-specific EOI
#      0  1  1                      specific EOI
#                                 Automatic rotation:
#      1  0  1                      rotate on non-specific EOI command
#      1  0  0                      set rotate in automatic EOI mode
#      0  0  0                      clear rotate in automatic EOI mode
#                                 Specific rotation:
#      1  1  1                      rotate on specific EOI command
#      1  1  0                      Set priority command
#
#      0  1  0                    cmd: Nop
#
# A0 | D7 D6 D5 D4 D3 D2 D1 D0  |
# ------------------------------+
#  0 | 0 SMM RS  0  1  P RR RIS | 
#


PIC_OCW3		= 0b00001000 
PIC_OCW3_READ_REGISTER	= 0b00000010 | PIC_OCW3
  PIC_OCW3_IRR		= 0b00000000
  PIC_OCW3_ISR		= 0b00000001
PIC_OCW3_POLL		= 0b00000100
PIC_OCW3_SMM		= 0b01000000 | PIC_OCW3 # special mask mode
 PIC_OCW3_SET_SM	= 0b00100000 # set special mask

PIC_DATA_CMD_READ_IRR	= PIC_OCW3_READ_REGISTER 		# 1010b
PIC_DATA_CMD_READ_ISR	= PIC_OCW3_READ_REGISTER | PIC_OCW3_ISR # 1011b
PIC_DATA_CMD_SET_SMM	= PIC_OCW3_SMM | PIC_OCW3_SET_SM
PIC_DATA_CMD_CLEAR_SMM	= PIC_OCW3_SMM 

#
#
#

PIC_CMD_EOI		= 0x20	# End Of Interrupt

.intel_syntax noprefix


.data
pic_ivt_offset: .word 0

.text

# in: al = vector offset Master PIC (default = 0x08)
#     ah = vector offset Slave PIC  (default = 0x70)
.macro PROGRAM_PIC picport, offsetreg, connect, icw4
	in	al, \picport + 1
	mov	ah, al

		.if DEBUG > 2
		push	ax
		push	dx
		mov	ah, 0xf0
		rmI2 "  PIC "
		mov	dl, \picport
		call	printhex2_16
		rmI2 "mask "
		mov	dl, al
		call	printhex2_16
		rmI2 "ICW1 "
		mov	dl, bh
		call	printhex2_16
		rmI2 "ICW2 "
		mov	dl, \offsetreg
		call	printhex2_16
		rmI2 "ICW3 "
		mov	dl, \connect
		call	printhex2_16
		rmI2 "ICW4 "
		mov	dl, \icw4
		call	printhex2_16
		pop	dx
		pop	ax
		call	newline_16
		.endif

	# use ADI in realmode (4 byte addr), no ADI in pmode (8 byte addr)
	mov	al, PIC_ICW1_INIT + PIC_ICW1_ICW4
	add	al, bh # PIC_ICW1_ADI
	out	\picport, al
	# io_wait()
	mov	al, \offsetreg	# icw2
	out	\picport+1, al
	mov	al, \connect	# icw3	
	out	\picport+1, al
	mov	al, \icw4	# icw4
	out	\picport+1, al

	mov	al, ah
	out	\picport+1, al
.endm

.macro PIC_INIT
	mov	[pic_ivt_offset], ax

	push	bx
	push	eax
	mov	bl, al

	mov	eax, cr0	# set bh to 100b for pmode, 0 for realmode
	mov	bh, bl		# which is PIC_ICW1_ADI
	not	bh
	and	bh, 1
	shl	bh, 2

	# first 0x1f are reserved.
	PROGRAM_PIC IO_PIC1, bl, PIC_ICW3_MASTER, PIC_ICW4_8086
	pop	ax
	mov	bl, ah
	push	ax
	PROGRAM_PIC IO_PIC2, bl, PIC_ICW3_IRQ_MASK & 2, PIC_ICW4_8086

	pop	eax
	pop	bx
	ret
.endm

.code16
pic_init16:
	PIC_INIT
.code32
pic_init32:
	PIC_INIT

.code16


# in: al = IRQ
# if ( al >= 8 ) outb( IO_PIC2, PIC_COMMAND_EOI );
# outb( IO_PIC1, PIC_COMMAND_EOI );
pic_send_eoi:
	push	ax

	mov	ah, al
	mov	al, PIC_CMD_EOI
	cmp	ah, 8
	jb	0f
	out	IO_PIC2, al
0:
	out	IO_PIC1, al

	pop	ax
	ret

.macro PIC_SEND_EOI for_irq
	mov	al, 0x20
	.if \for_irq < 8
	P = IO_PIC1
	.else
	P = IO_PIC2
	.endif
	out	P, al
.endm



.macro SETUP_IRQLINE_MASK
	mov	dx, IO_PIC1 + 1
	and	al, 0xf
	cmp	al, 8
	jb	0f
	sub	al, 8
	add	dx, IO_PIC2 - IO_PIC1
0:	xchg	al, ah
.endm

.macro PIC_ENABLE_IRQ irqline
	.if \irqline < 8
		P = IO_PIC1 + 1
		A = \irqline
	.else
		P = IO_PIC2 + 1
		A = irqline - 8
	.endif
	in	al, P
	and	al, ~ ( 1 << A )
	out	P, al
.endm

.macro PIC_DISABLE_IRQ irqline
	.if \irqline < 8
		P = IO_PIC1 + 1
		A = \irqline
	.else
		P = IO_PIC2 + 1
		A = irqline - 8
	.endif
	in	al, P
	or	al, 1 << A
	out	P, al
.endm




# in: al = bit number, < 16
pic_enable_irq_line:
	push	ax
	push	dx

	SETUP_IRQLINE_MASK
	in	al, dx
	or	al, ah
	out	dx, al

	pop	dx
	pop	ax
	ret

pic_disable_irq_line:
	push	ax
	push	dx

	SETUP_IRQLINE_MASK
	in	al, dx
	not	ah
	and	al, ah
	out	dx, al

	pop	dx
	pop	ax
	ret

# works in 16, 32 and 64 bit mode...
.macro PIC_SET_MASK mask
	push	ax
	mov	ax, \mask
	out	IO_PIC1+1, al
	ror	ax, 8
	out	IO_PIC2+1, al
	pop	ax
.endm


# in: ax = bitmask (al = master, ah = slave)
pic_set_mask:
	push	ax
	out	IO_PIC1+1, al
	shr	ax, 8
	out	IO_PIC1+1, al
	pop	ax
	ret


# out: ax = bitmask (al = master, ah = slave)
pic_get_mask:
	in	al, IO_PIC2 + 1
	shl	ax, 8
	in	al, IO_PIC1 + 1
	ret


pic_disable:
	push	ax
	mov	ax, 0xffff
	call	pic_set_mask
	pop	ax
	ret

.data
pic_mask: .word 0
.text
pic_savemask:
	push	ax
	call	pic_get_mask
	mov	[pic_mask], ax
	pop	ax
	ret
pic_restore:
	push	ax
	mov	ax, [pic_mask]
	call	pic_set_mask
	pop	ax
	ret
	
# in: al = irq.
# out: cf = 1: yes, spurious. Dont send EOI.
#
# If the interrupt is spurious, the ISR does not need to be reset.
# Another way to view this is to check whether the interrupt is 'in service'.
pic_is_spurious_irq:
	push	ax
	push	dx
	cmp	al, 7
	jne	0f
	mov	dx, IO_PIC1
	jmp	1f

0:
	cmp	al, 15
	jne	0f
	mov	dx, IO_PIC2
	shr	al, 3

1:	mov	ah, 1
	push	cx
	mov	cl, al
	shl	ah, cl
	pop	cx
	mov	al, PIC_DATA_CMD_READ_ISR
	out	dx, al
	in	al, dx 
	test	al, ah
	jz	0f # (assume cf = 0 aswell)
	stc	
0:	
	pop	dx
	pop	ax
	ret

# irq_handler( int irq_num ) 
# {
#  if ( irq == 7 ) # PIC1 IRQ
#  {
#    if ( pic_read_isr( IO_PIC1 ) & (1 << 7) )
#	{ handleIRQ(); sendEOI( IO_PIC1) ; }
#  }
#  else if ( irq == 15 ) # PIC2 IRQ
#  {
#    if ( pic_read_isr( IO_PIC2 ) & ( 1 << 7) )
#      { handleIRQ(); sendEOI( IO_PIC2 ); sendEOI( IO_PIC1 ); }
#    else
#      sendEOI( IO_PIC1 );
#  }
