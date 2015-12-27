##############################################################################
# RSR232 Serial COM Port Driver 8250/16450/16550/16550A UART chips 
#
# Ported from original DOS UART Driver 0.4 (C) 1995-'96 Kenney Westerhof
#
# See also http://www.sci.muni.cz/docs/pc/serport.txt
.intel_syntax noprefix

UART_DEBUG = 0

UART_POLLING = 0	# 1: send bytes one at a time; 0: use IRQ and buffer
##############################################################################
# Constants
# serial ports: 3f8 2f8
# parallell ports: 378 9f80

UART_IO_COM1 = 0x3f8	# 3f8..3ff
UART_IO_COM2 = 0x2f8	# 3f8..3ff
UART_IO_COM3 = 0x3e8	# maybe these  
UART_IO_COM4 = 0x2e8	# to are swapped

UART_IRQ_COM1 = 4	# IRQ_COM1
UART_IRQ_COM2 = 3	# IRQ_COM2
UART_IRQ_COM3 = 4	# IRQ_COM1
UART_IRQ_COM4 = 3	# IRQ_COM2

# XXX BUF IE and LC
#     00  0b     03
#     01  00     83


UART_REG_BUF		= 0	# (0x3f8) data out(w)/in(r) register
UART_REG_IE		= 1	# (0x3f9) Interrupt Enable register
	# bits 7-4: reserved
	UART_REG_IE_MS	= 1<<3	# modem status interrupt enable (delta bits)
	UART_REG_IE_RLS	= 1<<2	# receiver line status interrupt enable
	UART_REG_IE_THRE= 1<<1	# transmitter holding register empty int. en.
	UART_REG_IE_DA	= 1<<0	# received data available interrupt enable

UART_REG_DLAB_LO	= 0	# DLAB bit=1: divisor latch low byte, else BUF
UART_REG_DLAB_HI	= 1	# DLAB bit=1: divisor latch hi byte, else IEN

UART_REG_IS		= 2	# (0x3fa r) Interrupt Identification(status) reg
	UART_REG_IS_FIFO=1<<6	# fifo queues enabled
		# actually, bits 7:6:
		# 00 = reserved (8250,8251,16450
		# 01 = fifo queues enabled (16550)
		# 11 = fifo queues enabled (16550A)
	# bits 5-4 reserved
	UART_REG_IS_TO	= 1<<3	# 1: timeout interrupt (16550); 0=reserved
	UART_REG_IS_ID_MASK = 0b11 << 1
	UART_REG_IS_ID_SHIFT = 1
	UART_REG_IS_ID_RLS = 0b11 << 1	# receiver line status int; prio=max
	UART_REG_IS_ID_RDA = 0b10 << 1	# received data available int; prio=2nd
	UART_REG_IS_ID_TE  = 0b01 << 1	# tx reg empty int; prio=3rd
	UART_REG_IS_ID_MS  = 0b00 << 1	# modem status int; prio=min
	UART_REG_IS_IP	= 1<<0	# 0: interrupt pending; 1: nope.
# 1100 1100
#         IP
#       --RDA
#      TO  

UART_REG_FC		= 2	# (0x3fa w) FIFO control register
	UART_REG_FC_RDATL_MASK=0b11<<6	# received data avail. trigger level
	UART_REG_FC_RDATL_SHIFT=6	# 
	UART_REG_FC_RDATL_1  = 0b00<<6	# 1 byte data available
	UART_REG_FC_RDATL_4  = 0b01<<6	# 4 bytes data available
	UART_REG_FC_RDATL_8  = 0b10<<6	# 8 bytes data available
	UART_REG_FC_RDATL_14 = 0b11<<6	# 14 bytes data available
	# bits 5:4 reserved
	UART_REG_FC_XRDY_MODE=1<<3	# TXRDY/RXDRY mode 0 or mode 1 (DMA)
	UART_REG_FC_CLR_XMIT =1<<2	# clear XMIT FIFO buffer
	UART_REG_FC_CLR_RECV =1<<1	# clear RCVR FIFO buffer
	UART_REG_FC_ENWR =1<<0	# 1: enable writing bits // also: FIFO enable

UART_REG_LC		= 3	# (0x3fb r/w) Line Control register
	UART_REG_LC_DLAB = 1<<7# 1:divisor latch access bit;0:RX/TX/IEN access
	UART_REG_LC_BE	  = 1<<6# 1: set break enable (output forced to spacing state)
	UART_REG_LC_SP	= 1<<5	# stuck parity: mark/space
	UART_REG_LC_PE	= 1<<4	# 1: even parity; 0: odd parity
	UART_REG_LC_PEN	= 1<<3	# parity enable: 1=even, 0=0dd
	  UART_REG_LC_P_NONE = 0              | 0              | 0
	  UART_REG_LC_P_ODD  = 0              | 0              | UART_REG_LC_PEN
	  UART_REG_LC_P_EVEN = 0              | UART_REG_LC_PE | UART_REG_LC_PEN
	  UART_REG_LC_P_MARK = UART_REG_LC_SP | 0              | UART_REG_LC_PEN
	  UART_REG_LC_P_SPACE= UART_REG_LC_SP | UART_REG_LC_PE | UART_REG_LC_PEN

	UART_REG_LC_SB	= 1<<2	#0: 1 stop bit; 1: 0 stop bits
	UART_REG_LC_WL_MASK = 0b00<<0	# word-length (bits)
	UART_REG_LC_WL_SHIFT=0
	UART_REG_LC_WL_5 = 0b00	# 5 bits
	UART_REG_LC_WL_6 = 0b01	# 6 bits
	UART_REG_LC_WL_7 = 0b10	# 7 bits
	UART_REG_LC_WL_8 = 0b11	# 8 bits

	# 0x75 : 01 1   1  0  1   01
	#           SP  PO PD S1  WL6
	# 0x03:  000 00 0 11
	#             N  1  8

UART_REG_MC		= 4	# (0x3fc r/w) Modem Control
	# bits 7:5 reserved
	UART_REG_MC_LB	= 1 << 4	# loopback mode
	UART_REG_MC_AUX2= 1 << 3	# aux user-designated output 2 (enable ints!)
	UART_REG_MC_AUX1= 1 << 2	# aux user-designated output 1
	UART_REG_MC_RTS	= 1 << 1	# force request-to-send active
	UART_REG_MC_DTR	= 1 << 0	# force data-terminal-ready active

UART_REG_LS		= 5	# (0x3fd r) Line Status register
#61:0110 0001
#           rx data ready
#     TXHE
#    TXSHE
	# bit 7 reserved (16550+: 1 char in FIFO RX has errors; read=clear;)
	UART_REG_LS_TEMT	= 1 << 6	# transm. shift/hold regs empty
	UART_REG_LS_TXHE	= 1 << 5	# transm. holding reg empty
	UART_REG_LS_BI		= 1 << 4	# break inicator (rx 2xspace)
	UART_REG_LS_FE		= 1 << 3	# framing error
	UART_REG_LS_PE		= 1 << 2	# parity error
	UART_REG_LS_OE		= 1 << 1	# overrun error
	UART_REG_LS_DR		= 1 << 0	# RX data ready 

UART_REG_MS		= 6	# (0x3fe r) Modem Status register
	UART_REG_MS_DCD		= 1 << 7	# data carrier detect
	UART_REG_MS_RI		= 1 << 6	# ring indicator
	UART_REG_MS_DSR		= 1 << 5	# data set ready
	UART_REG_MS_CTS		= 1 << 4	# clear to send
	UART_REG_MS_DDCD	= 1 << 3	# delta data carrier detect
	UART_REG_MS_TERI	= 1 << 2	# trailing edge ring indic.
	UART_REG_MS_DDSR	= 1 << 1	# delta data set ready
	UART_REG_MS_DCTS	= 1 << 0	# delta clear to send
	# reading resets bits 3:0
	# during loopback test:
	UART_REG_MS_LB_RTS = 1 << 4
	UART_REG_MS_LB_DTR = 1 << 5
	UART_REG_MS_LB_OUT1 = 1 << 6
	UART_REG_MS_LB_OUT2 = 1 << 7

UART_REG_SCRATCH	= 7	# (0x3ff r/w) Scratch register


.macro UART_WRITE reg, val=al
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_\reg
	.ifnc \val,al
	mov	al, \val
	.endif
	out	dx, al
.endm

.macro UART_WRITEw reg, val=ax
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_\reg	# only 0 valid!
	.ifnc \val,ax
	mov	ax, \val
	.endif
	out	dx, ax
.endm

XOFF	= 17	# ^Q
XON	= 19	# ^S

############################################################################
# structure for the device object instance:
DECLARE_CLASS_BEGIN uart, dev

uart_mode_databits:	.byte 0	# 8,7,6,5
uart_mode_parity:	.byte 0	# 'O'dd, 'E'ven, 'N'one
uart_mode_stopbits:	.byte 0	# 2 or 1

uart_mode:	.byte 0	# 0b 000 s pp dd
			# s:  stopbits: 1 = 2, 0 = 1
			# pp: parity: 00=none, 10=even, 01=odd
			# dd: databits: 00=5,01=6,10=7,11=8
	UART_MODE_D8 = 0b11 << 0
	UART_MODE_D7 = 0b10 << 0
	UART_MODE_D6 = 0b01 << 0
	UART_MODE_D5 = 0b00 << 0

	UART_MODE_PN = 0b00 << 2
	UART_MODE_PE = 0b10 << 2
	UART_MODE_PO = 0b01 << 2

	UART_MODE_S1 =    0 << 3
	UART_MODE_S2 =    1 << 3

uart_baudrate: .long 0


# detection 
uart_flags: .word 0
	UART_FLAG_16450	= 1 << 0	# 0: 8250
	UART_FLAG_FIFO	= 1 << 1
	UART_FLAG_NOTX	= 1 << 2	# flow control: no xfer-out
	UART_FLAG_NORX	= 1 << 3	# flow control: no xfer-in
	# these flags must match UART_REG_MS_(DSR|CTS)
	UART_FLAG_CTS_RTS= 1<< 4
	UART_FLAG_DSR_DTR= 1<< 5
	# receive:
	UART_FLAG_XON_XOFF= 1 << 6
	#

uart_flowcontrol: .byte 0
	UART_FLOWCTL_NO_XFER_OUT= 1 << 0
	UART_FLOWCTL_NO_XFER_IN = 1 << 1
	UART_FLOWCTL_S_XON	= 1 << 2
	UART_FLOWCTL_S_XOFF	= 1 << 3

uart_fifo_size: .byte 0	# 0: disabled; 1, 4, 8, 14

uart_bufsize: .long 0	# both for rx and tx
# the buffers are circular (TODO: re-use code!)
# The order is important here! see purgein/out
uart_rxbuf: .long 0	# mallocced - free
uart_rxbuf_rpos: .long 0
uart_rxbuf_wpos: .long 0
uart_txbuf: .long 0	# offset into rxbuf; do not free
uart_txbuf_rpos: .long 0
uart_txbuf_wpos: .long 0

uart_near_full: .long 0
uart_near_full2: .long 0
uart_near_empty: .long 0

uart_linestatus: .byte 0
uart_modemstatus:.byte 0



DECLARE_CLASS_METHOD dev_api_constructor, uart_init, OVERRIDE
DECLARE_CLASS_METHOD dev_api_isr,	  uart_isr, OVERRIDE
DECLARE_CLASS_END uart
############################################################################
.text32

###############################################################################

# in: ebx = pci nic object
uart_init:
	push_	ebp edx ebx
	mov	ebp, esp

	I "Init UART "
	#movw	[ebx + dev_io], 0x3f8

	mov	ax, [ebx + dev_io]
	or	ax, ax
	jz	93f
	cmpb	[ebx + dev_irq], 0
	jnz	1f
	inc	ah	# get high byte (0x3f8>>8, 0x2f8>>8 etc): 3->4, 2->3
	movb	[ebx + dev_irq], ah	# IRQ_COM1, IRQ_COM2
1:
	# Detect port
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_LC	# Line Control
	mov	al, 0x75
	out	dx, al
	in	al, dx	# delay; DOS code did 'jmp . + 2'
	in	al, dx
	cmp	al, 0x75
	jnz	91f
	mov	al, 3	# set 8N1
	out	dx, al

	# detect 16450 / 8250
	add	dl, UART_REG_SCRATCH - UART_REG_LC
	mov	al, 0x75 # some random value
	out	dx, al
	in	al, dx	# delay
	in	al, dx
	cmp	al, 0x75
	jnz	1f
	orb	[ebx + uart_flags], UART_FLAG_16450
1:


	# detect FIFO
	add	dl, UART_REG_FC - UART_REG_SCRATCH
	in	al, dx
	mov	ah, 1
	xchg	al, ah
	out	dx, al
	in	al, dx	# delay
	in	al, dx
	and	al, 0xc0	# check top 2 bits
	cmp	al, 0xc0
	jnz	1f
	orb	[ebx + uart_flags], UART_FLAG_FIFO
	# initialize FIFO:
	movb	[ebx + uart_fifo_size], 14 # or 8, 4, 1, 0 (disable)
	mov	cl, [ebx + uart_fifo_size]
	xor	al, al
	or	cl, cl
	jz	2f
	cmp	cl, 14
	mov	al, 0b11001111	# FC_(DATL_14|XRDY_MODE|CLR_XMIT|CLR_RECV|ENWR)
	jz	2f
	cmp	cl, 8
	mov	al, 0b10001111	# FC_(DATL_8|XRDY_MODE|CLR_XMIT|CLR_RECV|ENWR)
	jz	2f
	cmp	cl, 4
	mov	al, 0b01001111	# FC_(DATL_4|XRDY_MODE|CLR_XMIT|CLR_RECV|ENWR)
	jz	2f
	cmp	cl, 1
	mov	al, 0b00001111	# FC_(DATL_1|XRDY_MODE|CLR_XMIT|CLR_RECV|ENWR)
	jz	2f
	# illegal FIFO size:
	movb	[ebx + uart_fifo_size], 0
1:	# no FIFO
	xchg	al, ah	# restore FC value
2:	out	dx, al

	mov	ax, [ebx + uart_flags]
	PRINTFLAG al, UART_FLAG_16450, "16450 ", "8250 "
	PRINTFLAG al, UART_FLAG_FIFO, "FIFO ", ""

	# allocate rx/tx buffers
	mov	eax, 8#4200	# use 8 or so for testing

	add	eax, 3	# dword align for rep stosd
	and	al, ~3
	mov	[ebx + uart_bufsize], eax
	add	eax, eax	# allocate rx and tx both in 1 block
	call	mallocz
	jc	92f
	mov	[ebx + uart_rxbuf], eax
	add	eax, [ebx + uart_bufsize]
	mov	[ebx + uart_txbuf], eax

	mov	ecx, [ebx + uart_bufsize]
	mov	eax, ecx
	shr	ecx, 2	# 1/4th
	sub	eax, ecx	# 3/4th, 12/16th
	mov	[ebx + uart_near_full], eax
	shr	ecx, 2	# 1/16th
	add	eax, ecx	# 13/16th
	mov	[ebx + uart_near_full2], eax
	mov	[ebx + uart_near_empty], ecx

	call	dev_add_irq_handler	# also enables PIC IRQ line


	mov	dx, [ebx + dev_io]
.if 0
	UART_WRITE IE 0
	UART_WRITE LC 0x80	# DLAB
	UART_WRITEw BUF 1	# 115200/3=38400
	UART_WRITE LC 3		# no DLAB; 8N1
	UART_WRITE FC 7#0x87	# enable fifo, clear, 8 bytes
	UART_WRITE IE 0xb#0xa	# AUX2 | DTS | RTS # not 0xb/bit0:
	UART_WRITE MC 0
.else

	# disable all interrupts
	add	dl, UART_REG_IE
	xor	al, al
	out	dx, al

	# set 8N1
	movb	[ebx + uart_mode], UART_MODE_D8 | UART_MODE_PN | UART_MODE_S1
	movb	[ebx + uart_mode_databits], 8
	movb	[ebx + uart_mode_parity], 'N'
	movb	[ebx + uart_mode_stopbits], 1
	mov	[ebx + uart_baudrate], dword ptr 115200

	call	uart_set # set 8N1 and baudrate; clears DLAB
	call	uart_print

	add	dl, UART_REG_MC
	in	al, dx
	or	al, UART_REG_MC_AUX2	# enable interrupts
	out	dx, al

	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_IE
	mov	al, 0b1101# all except THRE; //0xb # 0b1011: UART_REG_IE_DA | UART_REG_IE_MS
	out	dx, al	# THRE only set when needed
	#add	dl, UART_REG_MC - UART_REG_IE
	#xor	al, al
	#out	dx, al

.endif

	call	uart_get
	call	uart_print
	call	newline

	LOAD_TXT "QuRe Booting. Hello World!\r\n", esi, ecx, 1
1:	call	uart_send
	jc	1b

	clc
0:	pop_	ebx edx ebp
	ret

91:	printlnc 4, "no UART"
	stc
	jmp	0b
92:	printlnc 4, "malloc error"
	stc
	jmp	0b
93:	printlnc 4, "no IO address"
	stc
	jmp	0b

############################################################
# static methods
uart_purgeout:
	push_	edi ecx
	mov	edi, offset uart_txbuf
	jmp	1f
# KEEP-WITH-NEXT 1f
uart_purgein:
	push_	edi ecx
	mov	edi, offset uart_rxbuf
1:	mov	ecx, [ebx + uart_bufsize]
	mov	[edi + 4], dword ptr 0	# clear readpos
	mov	[edi + 8], dword ptr 0 	# clear writepos
	mov	edi, [ebx + edi]	# load rxbuf/txbuf pointer
	shr	ecx, 2
	xor	eax, eax
	rep	stosd
	pop_	ecx edi
	ret

uart_numbytesr:
	mov	eax, [ebx + uart_rxbuf_wpos]
	sub	eax, [ebx + uart_rxbuf_rpos]
	jnle	1f
	add	eax, [ebx + uart_bufsize]
1:	ret


uart_get_txbuf_free_space:
	mov	eax, [ebx + uart_txbuf_rpos]
	sub	eax, [ebx + uart_txbuf_wpos]
	dec	eax	# leave 1 byte as read/write boundary marker
	jns	1f
	add	eax, [ebx + uart_bufsize]
1:	ret

uart_get_txbuf_pending_size:
	mov	eax, [ebx + uart_txbuf_rpos]
	sub	eax, [ebx + uart_txbuf_wpos]
	jns	1f
	add	eax, [ebx + uart_bufsize]
1:	ret

############################################################
uart_print:
	pushad
	mov	edx, [ebx + uart_baudrate]
	call	printdec32
	print " baud "

	movzx	edx, byte ptr [ebx + uart_mode_databits]
	call	printdec32	# or printhex1
	mov	al, [ebx + uart_mode_parity]
	call	printchar
	mov	dl, [ebx + uart_mode_stopbits]
	call	printdec32

	call	newline
	popad
	ret


uart_set:
	push_	eax ecx edx
	# round the baudrate to a valid value
	xor	edx, edx
	mov	eax, 115200
	div	dword ptr [ebx + uart_baudrate]
	or	eax, eax
	jnz	1f
	inc	al	# divisor was 0 - round
1:	# ax = divisor
	push	eax

	# now recalculate baud rate using the divisor:
	mov	ecx, eax
	xor	edx, edx
	mov	eax, 115200
	div	ecx
	mul	ecx
	mov	[ebx + uart_baudrate], eax

	# cli
	# set DLAB
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_LC
	mov	al, 0x80	# discard other bits - they are set below
	out	dx, ax
	# now we can set the baudrate
	pop eax # preserve divisor
	sub	dl, UART_REG_LC
	out	dx, ax
	# set 8N1
	add	dl, UART_REG_LC
	mov	al, [ebx + uart_mode_databits]	# 5..8
	sub	al, 5
	mov	ah, [ebx + uart_mode_stopbits]	# 2,1
	dec	ah
	shl	ah, 2
	or	al, ah
	mov	cl, [ebx + uart_mode_parity]
	mov	ah, UART_REG_LC_P_ODD
	cmp	cl, 'O'
	jz	1f
	mov	ah, UART_REG_LC_P_EVEN
	cmp	cl, 'E'
	jz	1f
	mov	ah, UART_REG_LC_P_NONE	# 0
	cmp	cl, 'N'
	#jz	1f
1:	or	al, ah
	out	dx, al	# clear DLAB aswell
	# activate DTR, IE
	add	dl, UART_REG_MC - UART_REG_LC
	in	al, dx
	and	al, ~( UART_REG_MC_DTR | UART_REG_MC_RTS )
	or	al, UART_REG_MC_DTR | UART_REG_MC_AUX2
	out	dx, al
	#sti

	pop_	edx ecx eax
	ret

# in: ebx = device
uart_get:
	push_	eax ecx edx
	mov	dx, [ebx + dev_io]
	#cli
	add	dl, UART_REG_LC
	in	al, dx
	mov	ah, al
	or	al, 0x80	# DLAB
	out	dx, al
	movb	[ebx + uart_mode_stopbits], 1
	test	ah, 0b100
	jz	1f
	incb	[ebx + uart_mode_stopbits]
1:

	mov	al, ah
	shr	al, 3
	and	al, 3
	movb	[ebx + uart_mode_parity], 'N'
	test	al, 1
	jz	1f
	movb	[ebx + uart_mode_parity], 'O'
	test	al, 0b10
	jz	1f
	movb	[ebx + uart_mode_parity], 'E'
1:

	and	ah, 3
	add	ah, 5
	movb	[ebx + uart_mode_databits], ah

#	add	dl, UART_REG_DLAB_HI - UART_REG_LC
#	in	al, dx
#	mov	ah, al
#	add	dl, UART_REG_DLAB_LO - UART_REG_DLAB_HI
#	in	al, dx
	add	dl, UART_REG_BUF - UART_REG_LC # base IO
	in	ax, dx
	or	ax,ax
	jnz 1f
	inc al
1:	# ax = divisor
	movzx	ecx, ax
	xor	edx, edx
	mov	eax, 115200
	div	ecx
	mov	[ebx + uart_baudrate], eax

	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_LC
	in	al, dx
	and	al, 0x7f	# mask out DLAB
	out	dx, al
	#sti
	pop_	edx ecx eax
	ret
############################################################
# Send Packet

# in: ebx = device
# in: esi = packet
# in: ecx = packet size
# out: CF = 1: tx buffer full, try again soon
# out: esi = points to data not in buffer
# out: ecx = datalen not in buffer
.global uart_send
uart_send:

.if UART_POLLING
	push	eax 
0:	lodsb
	call	uart_sendbyte
	jc	9f
	loop	0b
9:	pop	eax
.else
	push_	edx eax ecx
	call	uart_get_txbuf_free_space	# out: eax = write buf space avail
	.if UART_DEBUG > 1
		DEBUG_DWORD ecx, "sending bytes"
		DEBUG_DWORD eax, "txbuf free space"
		DEBUG_DWORD [ebx + uart_txbuf_rpos], "rpos"
		DEBUG_DWORD [ebx + uart_txbuf_wpos], "wpos"
	.endif
	cmp	ecx, eax
	jb	1f
	.if UART_DEBUG > 1
		DEBUG "wontfit"
	.endif
	sub	ecx, eax
	mov	[esp], ecx	# update remaining len
	mov	ecx, eax	# this much will fit
	jmp	2f
1:	mov	[esp], dword ptr 0	# will fit
2:
	mov	edi, [ebx + uart_txbuf]
	add	edi, [ebx + uart_txbuf_wpos]

	# check circular wrapping:
	mov	eax, [ebx + uart_bufsize]
	sub	eax, [ebx + uart_txbuf_wpos]
	cmp	eax, ecx
	jae	1f	# enough contiguous space
	# split:
	# copy eax bytes
	# copy ecx - eax bytes
	sub	ecx, eax	# bytes after wrap
	.if UART_DEBUG > 1
		DEBUG "write split"
		DEBUG_DWORD eax,"A"
		DEBUG_DWORD ecx,"B"
	.endif
	xchg	eax, ecx
	rep	movsb
	mov	edi, [ebx + uart_txbuf] # wrap
	mov	ecx, eax
1:	rep	movsb
	sub	edi, [ebx + uart_txbuf]
	cmp	edi, [ebx + uart_bufsize]
	jb	1f
	sub	edi, [ebx + uart_bufsize]
1:
	.if UART_DEBUG > 1
		DEBUG_DWORD edi
		more
	.endif
	mov	[ebx + uart_txbuf_wpos], edi

	# now we signal the UART that there's data to send:
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_IE
	in	al, dx
	.if UART_DEBUG > 1
		DEBUG_BYTE al, "IE"
	.endif
	or	al, UART_REG_IE_THRE	# let us know when xmit reg emty
	out	dx, al
	inc al	# delay
	in	al, dx
	.if UART_DEBUG > 1
		DEBUG_BYTE al, "IE"
	.endif

	pop_	ecx eax edx
	# set CF if ecx != 0
	clc
	jecxz	1f
	stc
1:
	.if UART_DEBUG > 1
		call newline
	.endif
.endif
	ret

# in: ebx = dev
# in: al = byte
uart_sendbyte:
	pushad
	#incd	[ebx + nic_tx_count]
	#add	[ebx + nic_tx_bytes + 0], ecx
	#adcd	[ebx + nic_tx_bytes + 4], 0

	.if UART_DEBUG > 1
		DEBUG "uart_send"
		DEBUG_DWORD ecx
	.endif
.if UART_POLLING
	mov	ah, al
	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_LS
0:	in	al,dx
	test	al, UART_REG_LS_TEMT	# 0x20
	jz	0b
	mov	al, ah
	sub	dl, UART_REG_LS
	out	dx, al
.else
	mov	edx, [ebx + uart_txbuf_wpos]
	# check room:
	mov	esi, edx
	inc	esi
	cmp	esi, [ebx + uart_bufsize]
	jb	1f
	xor	esi, esi
1:	cmp	esi, [ebx + uart_txbuf_rpos]
	stc
	jz	9f

	mov	edi, [ebx + uart_txbuf]
	mov	[edi + esi], al
	mov	[ebx + uart_rxbuf_wpos], edx

	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_IE
	in	al, dx
	or	al, UART_REG_IE_THRE
	out	dx, al
	clc
9:
.endif
	popad
	ret


##############################################################
# Interrupt Service Routine
uart_isr:
	pushad
	mov	ebx, edx	# see irq_isr and (dev_)add_irq_handler

	.if UART_DEBUG
		printc 0xf5, "UART ISR"
	.endif

	mov	dx, [ebx + dev_io]
	add	dl, UART_REG_IS
	mov	ecx, 100	# infinite loop bound
0:	xor	eax, eax
	in	al, dx
	.if UART_DEBUG
		DEBUG_BYTE al,"IS"
	.endif
	# 0xc0: high 2 bits: fifo enabled
	# bit 0 = 0 = interrupt pending
	# cc: 1100 1100 : 
	test	al, 1
	jnz	9f	# no (more) interrupt pending

	push_	ecx edx
	sub	dl, UART_REG_IS	# reset to base IO
########

.if 1	# simple: ignore fifo timeouts
	and al, 0b110
.else
#### check 0b1100; normally mask with 0b110 is ok.
	and	al, 0b1110
	test	al, 0b1000
	jz	1f	#  0b110 <<1 = 0bXX00: 4 handlers
	cmp	al, 0b1100
	jz	3f
	DEBUG "uart_isr: unknown IID!"
3:
	# bit 4 set: no receiver FIFO action since 4 words (bytes) time,
	# but data in rX-FIFO. service: read RBR (receive buffer reg)
	mov dx,[ebx+dev_io]
	DEBUG_WORD dx
	in	al, dx
	DEBUG_BYTE al, "rxBUF"	# 03
	add dl,UART_REG_FC
	in al, dx
	DEBUG_BYTE al,"FC"	#cc
	add dl, UART_REG_LS-UART_REG_FC
	in al, dx
	DEBUG_BYTE al,"LS"	# 61: DR(0),THRE(5),TEMT(6)
	test al, 1 # data ready
	jz 2f
	add dl, UART_REG_BUF - UART_REG_LS
	in al, dx
	DEBUG_BYTE al,"DR"
	# 
	jmp	2f
####
.endif
1:	lea	eax, [eax * 2 + uart_isr_services$]
	call	[eax]
########
2:	pop_	edx ecx
	dec ecx; jnz 0b;#loop	0b
	DEBUG "uart_isr: loop end!"	# when this is seen, something's up.:w

9:
	.if UART_DEBUG
		call	newline
	.endif
	# EOI is handled by IRQ_SHARING code
	popad
	iret

.data
uart_isr_services$:	# these match (in(UART_REG_IS) & 0b110)<<1
	.long uart_isr_ms$
	.long uart_isr_tx$
	.long uart_isr_rx$
	.long uart_isr_ls$
.text32

uart_isr_ms$:	# Modem Status change (0b0000)
	add	dl, UART_REG_MS
	in	al, dx
	DEBUG_BYTE al, "MS"
	mov	[ebx + uart_modemstatus], al
	add	dl, UART_REG_IE - UART_REG_MS
	in	al, dx
	test	al, UART_REG_IE_THRE
	jnz	1f
	or	al, UART_REG_IE_THRE
	out	dx, al
1:	ret


uart_isr_tx$:	# Send (0b0010)
	.if UART_DEBUG > 1
		DEBUG "UART: SEND!"
	.endif
	mov	dx, [ebx + dev_io]

	testb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_OUT
	jnz	9f
#DEBUG "xfer out permitted"
#--------------------------------------------------------- XON/XOFF
	testb	[ebx + uart_flowcontrol], UART_FLOWCTL_S_XON|UART_FLOWCTL_S_XOFF
	jz	1f	# no XON/XOFF
	#  XON and/or XOFF set.
#DEBUG "XON/XOFF enabled"
	mov	ah, [ebx + uart_flags]
	and	ah, UART_FLAG_DSR_DTR | UART_FLAG_CTS_RTS
	jz	2f
		add	dl, UART_REG_MS
		in	al, dx	# read modem status
		sub	dl, UART_REG_MS
		and	al, ah	# mask shiftbits
		cmp	al, ah	# can we send?
		jnz	8f	# no write
2:	# no DSR/DTR and/or CTS/RTS

	# check 
	testb	[ebx + uart_flowcontrol], UART_FLOWCTL_S_XON
	jz	2f
	andb	[ebx + uart_flowcontrol], ~(UART_FLOWCTL_S_XON|UART_FLOWCTL_NO_XFER_IN)
	mov	al, XON
	jmp	4f	# send XON/XOFF
2:	# no XON; must be XOFF (otherwise 1f)
	andb	[ebx + uart_flowcontrol], ~(UART_FLOWCTL_S_XOFF)
	orb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_IN
	mov	al, XOFF
4: 	# send al (XON/XOFF)
	out	dx, al	# dx at base IO (_BUF)
	jmp	9f

1:	# no XON/XOFF
#DEBUG "no XON/XOFF"
#---------------------------------------------------------
	mov	ah, [ebx + uart_flags]
	and	ah, UART_FLAG_DSR_DTR | UART_FLAG_CTS_RTS
	jz	1f	# no flowcontrol
	add	dl, UART_REG_MS
	in	al, dx	# get modem status
	sub	dl, UART_REG_MS
	and	al, ah
	cmp	al, ah
	jnz	8f # no write

1:	mov	ecx, [ebx + uart_txbuf_rpos]
	cmp	ecx, [ebx + uart_txbuf_wpos]
	jz	8f # no write
	mov	eax, [ebx + uart_txbuf]
	mov	al, [eax + ecx]
	out	dx, al
	inc	ecx
	cmp	ecx, [ebx + uart_bufsize]
	jb	1f
	xor	ecx, ecx
1:	mov	[ebx + uart_txbuf_rpos], ecx
9:	ret

8: # no write
	add	dl, UART_REG_IE
	in	al, dx
	and	al, ~ UART_REG_IE_THRE
	# and al, 0b1101b
	out	dx, al	# disable THRE
	.if UART_DEBUG
		DEBUG_BYTE al,"IRQ: IE"
	.endif
	ret



uart_isr_rx$:	# Receive (0b0100)
	mov	dx, [ebx + dev_io]
	in	al, dx	# dx at IO base (_BUF)
	DEBUG "RX:"; call printchar
/*
add dl, UART_REG_LS
in al, dx 
test al, 1
jnz uart_isr_rx$
# rx/tx simultaneous lockup fixup:
test al, 0x40
jz 1f
	call uart_isr_tx$
1:
ret
*/
#------- check if XON/XOFF is enabled and if so check for XON/XOFF
	testb	[ebx + uart_flags], UART_FLAG_XON_XOFF
	jz	1f
	cmp	al, XOFF
	jnz	2f
	orb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_IN
	jmp	9f

2:	cmp	al, XON
	jnz	2f
	andb	[ebx + uart_flowcontrol], ~UART_FLOWCTL_NO_XFER_IN
	jmp	9f
2:
1:	# XON/XOFF not enabled
#-------
	mov	ecx, [ebx + uart_rxbuf_wpos]
	add	ecx, [ebx + uart_rxbuf]
	mov	[ecx], al
	mov	ecx, [ebx + uart_rxbuf_wpos]
	inc	ecx
	cmp	ecx, [ebx + uart_bufsize]
	jb	1f
	xor	ecx, ecx
1:	cmp	ecx, [ebx + uart_rxbuf_rpos]
	jz	1f	# not okay - writing would overwrite unread byes
	mov	[ebx + uart_rxbuf_wpos], ecx
1:

	call	uart_numbytesr
	cmp	eax, [ebx + uart_near_full]
	jb	9f

	testb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_IN
	jnz	1f
	push	eax
	mov	ah, [ebx + uart_flags]
	and	ah, UART_FLAG_CTS_RTS | UART_FLAG_DSR_DTR
	jz	2f
	add	dl, UART_REG_MC
	in	al, dx
	not	ah
	and	al, ah
	out	dx, al
	sub	dl, UART_REG_MC
2:	pop	eax
1: # skip DSR/DTR and CTS/RTS

	# 'high watermark 2': XON/XOFF trigger
	cmp	eax, [ebx + uart_near_full2]
	jae	1f	# send XON/XOFF
	testb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_IN
	jnz	9f #2f	# already set.

1:	# send XON/XOFF
	testb	[ebx + uart_flags], UART_FLAG_XON_XOFF
	jz	2f	# not enabled.
	orb	[ebx + uart_flowcontrol], UART_FLOWCTL_S_XOFF
2:	orb	[ebx + uart_flowcontrol], UART_FLOWCTL_NO_XFER_IN
	
9:	ret


uart_isr_ls$:	# Line Status change (0b1100)
	add	dl, UART_REG_LS
	in	al, dx
	DEBUG_BYTE al, "linestatus"
	and	al, 0x1e	# strip some bits
	mov	[ebx + uart_linestatus], al
	ret


#####################################
# Add hook to screen update
.global serial_log_init
serial_log_init:
	mov     esi, [class_instances]
	mov     edx, offset class_uart
	PTR_ARRAY_ITER_START esi, ecx, eax
	call    class_instanceof
	jnz     1f
	print "Hooking serial logging to "
	mov     ebx, eax
	lea	esi, [ebx + dev_name]
	call	println
	jmp	2f
1:      PTR_ARRAY_ITER_NEXT esi, ecx, eax
	printlnc 12, "No serial interface found"
	jmp	3f	# not found

2:	# hook a serial method:
	mov	[serial_log_dev], eax
	#mov	eax, offset default_screen_update#1f
	mov	eax, offset 1f	# 'offset' needed!
	#mov	[screen_update], eax	# XXX used in scroll - will break it! pgup OK, pgdown hangs
	# NOTE XXX FIXME TODO screen_update is purely meant for rendering,
	# so we must have another hook for printing (appending content).
	jmp	3f

.data
serial_log_dev: .long 0
serial_log_msg: .ascii "serial print called: prev_pos="
serial_log_pp:	.ascii "00000000"; .ascii " next pos="
serial_log_cp:	.ascii "00000000"; .ascii " \r\n\0"
SERIAL_LOG_MSG_SIZE = . - serial_log_msg
.text32

1:	#int 3# serial print handler
	#PRINT "SERIAL PRINT HOOK!";
	#ret

	# in: edx = cur pos
	# in: edi = prev pos
	ENTER_CPL0
	pushad
	.if 0
		LOAD_TXT "serial print called!\r\n", esi, ecx, 1
	.else
		mov	ecx, edi
		mov	edi, offset serial_log_cp
		call	sprinthex8

		mov	edx, ecx
		mov	edi, offset serial_log_pp
		call	sprinthex8
		mov	esi, offset serial_log_msg
		mov	ecx, SERIAL_LOG_MSG_SIZE
	.endif
	mov	ebx, [serial_log_dev]
1:	call	uart_send
	jc	1b
	popad

3:	ret

