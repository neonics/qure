.intel_syntax noprefix
.code32
.text

NIC_IO = 0xc000
NIC_IRQ = 0x0b

# Registers are RW unless specified (RO).

RTL8139_MAC	= 0	# size 6
# 6,7 reserved
RTL8139_MAR	= 8	# size 8	Multicast
RTL8139_TSD0	= 0x10	# size 4 descriptor 0 transmit status
RTL8139_TSD1	= 0x14	# size 4 descriptor 1 transmit status
RTL8139_TSD2	= 0x18	# size 4 descriptor 2 transmit status
RTL8139_TSD3	= 0x1c	# size 4 descriptor 3 transmit status
		TSD_CRS	= 1<<31		# (RO) carrier sense lost
		TSD_TABT= 1<<30		# (RO) transmit abort
		TSD_OWC = 1<<29		# (RO) out of window collision
		TSD_CDH = 1<<28		# (RO) cd heart beat send fail(100mb=0)
		TSD_NCC = 0b1111 << 24	# (RO) number of collision count
		# 23-22 reserved
		TSD_ERTXTH=0b111111<<16	# early Tx tresh; 0=8 1=32,2=64 etc
		TSD_TOK	= 1<<15		# (RO) Transmit ok
		TSD_TUN	= 1<<14		# (RO) Transmit Underrun
		TSD_OWN	= 1<<13		# dma operation completed; set to 0
					# when transmit byte count is written
		TSD_SIZE= (1<<13)-1	# transmit byte count/descriptor size

RTL8139_TSAD0	= 0x20	# size 4 transmit start address for descriptor 0
RTL8139_TSAD1	= 0x24	# size 4 transmit start address for descriptor 1
RTL8139_TSAD2	= 0x28	# size 4 transmit start address for descriptor 2
RTL8139_TSAD3	= 0x2c	# size 4 transmit start address for descriptor 3
RTL8139_RBSTART	= 0x30	# size 4 receive buffer start
RTL8139_ERBCR	= 0x34	# size 2 (RO) early RX byte count
RTL8139_ERSR	= 0x36	# size 1 (RO) early RX status
		# writing 1 to these bits will clear them:
		ERSR_GOOD = 0b1000	# received good packet 
		ERSR_BAD  = 0b0100	# received bad packet
		ERSR_OVW  = 0b0010	# rx overwrite: local addr=capr
		# writing 1 to this bit invokes a ROK interrupt:
		ERSR_OK   = 0b0001	# default 0; rx byte>rx threshold;
		# on complete, clears this bit and aets ROK or RER in ISR

RTL8139_CR	= 0x37	# size 1 command register
		CMD_RST	= 1<<4	# reset
		CMD_RE	= 1<<3	# receiver enable
		CMD_TE	= 1<<2	# transmitter enable
		CMD_BUFE= 1	# (R)
RTL8139_CAPR	= 0x38	# size 2 current address of packet read
RTL8139_CBR	= 0x3a	# size 2 (RO) current buffer address (RX buffer content)
RTL8139_IMR	= 0x3C	# size 2 interrupt mask - 1 = enable
RTL8139_ISR	= 0x3E	# size 2 interrupt status
		# these apply to both IMR and ISR:
		IR_SERR		= 1<<15	# System Error
		IR_TIMEOUT	= 1<<14	# TCTR reaches TINT
		IR_LENCHG	= 1<<13	# Cable length changed
		IR_FOVW		= 1<<6	# Rx FIFO overflow
		IR_PUN		= 1<<5	# Packet Underrun/Link change
		IR_RXOVW	= 1<<4	# Rx buffer overflow
		IR_TER		= 1<<3	# Tx error
		IR_TOK		= 1<<2	# Tx ok
		IR_RER		= 1<<1	# Rx error
		IR_ROK		= 1<<0	# Rx ok
RTL8139_TCR	= 0x40	# size 4 transmit config
		TCR_HWVERID_A	= 0b11111 << 26  # (RO)
				# HW ID A   ID B
				# --------- ---
				# 1 1 0 0 0 0 0 RTL8139
				# 1 1 1 0 0 0 0 RTL8139A
				# 1 1 1 0 1 0 0 RTL8139A-G
				# 1 1 1 1 0 0 0 RTL8139B
				# 1 1 1 1 0 0 0 RTL8130
				# 1 1 1 0 1 0 0 RTL8139C
				# 1 1 1 1 0 1 0 RTL8100
				# 1 1 1 0 1 0 1 RTL8100B/8139D
				# 1 1 1 0 1 1 0 RTL8139C+
				# 1 1 1 0 1 1 1 RTL8101
		TCR_IFG		= 3<<24	# interframe gap time
		TCR_HWVERID_B	= 3<<22 # (RO)
		TCR_LBK		= 3<<17	# loopback test
		TCR_CRC		= 1<<16	# append crc_ 0=no, 0=append
		TCR_MXDMA2	= 7<<8	# Max DMA burst size per Tx
				# 000 = 16, 001=32, 010=64, 011=128...111=2048
		TCR_TXRR	= 15<<4	# Tx retry count: 16*(TXRR+1)
		TCR_CLRABT	= 1	# clear abort: 1=retransmit

RTL8139_RCR	= 0x44	# size 4 receive config
		# 31-28 reserved
		RCR_ERTH = 0b1111<<24	# early rx thr multiplier: ERTH/16 
		# 23-18 reserved
		RCR_MulERINT=1<<17	# multiple early int select
		RCR_RER8 = 1<<16	# error packet reception (see AER/AR)
		RCR_RXFTH= 0b111<<14	# rx fifo thresh: 16<<RXFTH;111=no thres
		RCR_RBLEN= 0b11 << 11	# rx buflen:16+(8k<<RBLEN)
		RCR_MXDMA= 0b111 <<8	# dma burst size=16<<MXDMA,111=unlimited
		RCR_WRAP= 1 << 7	# 0=wraparound, 1=buffer overflow(1.5k)
		# 6 = reserved
		RCR_AER	= 1 << 5	# accept error packet
		RCR_AR	= 1 << 4	# accept runt (smaller than 64 bytes)
		RCR_AB	= 1 << 3	# accept broadcast
		RCR_AM	= 1 << 2	# accept multicast
		RCR_APM	= 1 << 1	# accept physical match
		RCR_AAP	= 1 << 0	# accept all

# Receive Status 'Register': 16 bits bytes in RBSTART + CBR
# (followed by 16 bits of packet length, not dword aligned)
		# RSR_MAR and RSR_BAR are never simultaneously set)
		RSR_MAR = 1<<15	# multicast packet
		RSR_PAM = 1<<14	# physical address matched
		RSR_BAR = 1<<13	# broadcast packet 
		# 12-6 reserved
		RSR_ISE = 1<<5	# invalid symbol error
		RSR_RUNT= 1<<4	#'RUNT' packe: smaller than 64 bytes
		RSR_LONG= 1<<3	#packet > 4k
		RSR_CRC = 1<<2	#CRC error
		RSR_FAE = 1<<1	# Frame alignment error
		RSR_ROK = 1<<0	#good packet received



RTL8139_TCTR	= 0x48	# size 4 timer count - write will restart count
RTL8139_MPC	= 0x4c	# size 4 missed packet counter (24 bit), write=reset
RTL8139_9346CR	= 0x50	# size 1 93C46 command register
RTL8139_CONFIG0	= 0x51	# size 1
RTL8139_CONFIG1	= 0x52	# size 2
# 0x53 reserved
RTL8139_TINT	= 0x54	# size 4 timer interrupt. ISR.timeout=1 when TCTR
			# reaches the written (nonzero) value.
RTL8139_MSR	= 0x58	# size 1 media status
RTL8139_CONFIG3	= 0x59
RTL8139_CONFIG4	= 0x5a
# 0x5b reserved
RTL8139_MULINT	= 0x5c	# size 2 multiple interrupt select
RTL8139_RERID	= 0x5e	# size 1 (RO) PCI revision ID = 0x10
# 0x5f reserved
RTL8139_TSAD	= 0x60	# size 2 (RO) transmit status of all descriptors
RTL8139_BMCR	= 0x62	# size 2 basic mode control
RTL8139_BMSR	= 0x64	# size 2 (RO) basic mode status
RTL8139_ANAR	= 0x66	# size 2 auto-negotiation advertisement
RTL8139_ANLPAR	= 0x68	# size 2 (RO) auto-negotiation link partner
RTL8139_ANER	= 0x6a	# size 2 (RO) auto-negotiation expansion
RTL8139_DIS	= 0x6c	# size 2 (RO) disconnect counter
RTL8139_FCSC	= 0x6e	# size 2 (RO) false carrier sense counter
RTL8139_NWAYTR	= 0x70	# size 2 N-Way test register
RTL8139_REC	= 0x72	# size 2 (RO) RX_ER counter
RTL8139_CSCR	= 0x74	# size 2 CS configuration register
# 0x76-77 reserved 
RTL8139_PHY1_PAR= 0x78	# size 2 PHY param 1
RTL8139_TW_PAR	= 0x7c	# size 4 twister param
RTL8139_PHY2_PAR= 0x80	# size 1 PHY param 2
# 81-83 reserved
RTL8139_CRC0	= 0x84	# size 1x8 power mgmnt crc for wakeup frame0..7
RTL8139_WAKEUP0	= 0x8c	# size 8x8 power mgmnt wakeup frame 0..7 (64bit each
RTL8139_LSBCR0	= 0xcc	# size 1 LSB of mask byte of wakeup within offs 12..75
# 0xd4-d7 reserved
RTL8139_CONFIG5	= 0xd8	
# 0xd9-0xff reserved

############################################################################

.struct 0
nic_object_size:.long 0
nic_name:	.space 8
nic_port:	.word 0
nic_mac:	.space 6
nic_mcast:	.space 8
nic_rx_buf:	.long 0
nic_api_send:	.long 0
nic_api_print_status: .long 0
NIC_STRUCT_SIZE = .

############################################################################
# structure for the RTL8139 device object instance: append field (subclass)
.struct NIC_STRUCT_SIZE
nic_rtl8139_desc_idx: .word 0
NIC_RTL8139_STRUCT_SIZE = .

############################################################################
.data
nics:	.long 0
.text

cmd_ifup:
	cmp	dword ptr [nics], 0
	jz	nic_init

	mov	al, CMD_TE | CMD_RE
	mov	dx, NIC_IO + RTL8139_CR
	out	dx, al
	call	rtl8139_print_status
	ret

cmd_ifdown:
	xor	al, al
	mov	dx, NIC_IO + RTL8139_CR
	out	dx, al
	call	rtl8139_print_status
	ret

nic_init:
	mov	dx, NIC_IO
	call	rtl8139_init
	jc	1f
	call	nic_list
1:	ret

nic_list:
	mov	eax, [nics]
	or	eax, eax
	jz	2f
	xor	edx, edx
	jmp	1f

0:	mov	ebx, eax
	add	ebx, edx

	print	"NIC "
	lea	esi, [ebx + nic_name]
	call	print

	print	" MAC "
	lea	esi, [ebx + nic_mac]
	call	nic_printmac$

	call	newline

	mov	ecx, [ebx + nic_api_print_status]
	add	ecx, [realsegflat]
	push	eax
	push	ebx
	push	edx
	call	ecx
	pop	edx
	pop	ebx
	pop	eax

	add	edx, [ebx + nic_object_size] # NIC_STRUCT_SIZE
1:	cmp	edx, [eax + array_index]
	jb	0b
	ret
2:	println "No NICs"
	ret

# in: ecx = total object size: NIC_STRUCT_SIZE, or larger
nic_newentry:
	mov	eax, [nics]
	or	eax, eax
	jnz	1f
	inc	eax
	call	array_new
1:	call	array_newentry	
	mov	[nics], eax
	mov	[eax + edx + nic_object_size], ecx # for iteration
	ret


nic_status:
	ret


nic_test:
	mov	eax, [nics]
	or	eax, eax
	jnz	1f

	call	nic_init
	jc	2f
	mov	eax, [nics]
	println	"nic initialized"

1:	# for now, use first card only


	# Prepare packet
	.data
	9: .asciz "payload, waddup!"
	8: 
	.text
	mov	ebx, eax
	mov	esi, offset 9b
	mov	eax, esi
	call	strlen
	mov	ecx, eax
	call	protocol_icmp

mov	eax, 1
0:
	call	nic_send
dec	eax
jnz	0b

	println "sent."

	clc
	ret

2:	printlnc 12, "nic_test: failed to initialize network card"
	ret

# in: ebx = nic object
nic_send:
	print	"Send packet: "
	mov	edx, [ebx + nic_api_send]
	add	edx, [realsegflat]
	pushad
	call	edx
	popad
	ret


nic_printmac$:
	push	esi
	push	ecx
	push	eax
	push	edx

	mov	ecx, 5
0:	lodsb
	mov	dl, al
	call	printhex2
	mov	al, ':'
	call	printchar
	loop	0b
	lodsb
	mov	dl, al
	call	printhex2

	pop	edx
	pop	eax
	pop	ecx
	pop	esi
	ret


##############################################################################
# Realtek 8139

# in: dx = base port
rtl8139_init:
	push	ebp
	push	edx
	mov	ebp, esp

	# power on device
	mov	dx, [ebp]
	add	dx, RTL8139_CONFIG1
	mov	al, 0x52 	# LWAKE + LWPTN high - power on
	out	dx, al

	# software reset
	mov	dx, [ebp]
	add	dx, RTL8139_CR
	mov	al, CMD_RST
	out	dx, al
	# test status
	mov	ecx, 0x1000
0:	in	al, dx
	test	al, CMD_RST
	jz	0f
	loop	0b
	printlnc 4, "rtl8138: reset failed"
	stc
	jmp	9f
0:
	# set receive buffer start address
	mov	eax, 8192 + 16
	call	mallocz
	jc	9f
	mov	ecx, eax	# preserve

	# calculate and send physical address
	mov	edx, eax
	call	get_ds_base
	add	eax, edx

	mov	dx, [ebp]
	add	dx, RTL8139_RBSTART
	out	dx, eax

	# enable receiving packets

	#	RCR_RBLEN= 0b11 << 11	# rx buflen:16+(8k<<RBLEN)
	mov	eax, RCR_AER | RCR_AR | RCR_AB | RCR_AM | RCR_APM | RCR_AAP
	mov	dx, [ebp]
	add	dx, RTL8139_RCR	# receive config
	out	dx, eax


	# set CAPR to end
#	xor	ax, ax
#	mov	ax, 8192
#	mov	dx, [ebp]
#	add	dx, RTL8139_CAPR
#	out	dx, ax

	# enable transmitter and receiver
	mov	dx, [ebp]
	add	dx, RTL8139_CR
	mov	al, CMD_TE |CMD_RE
	out	dx, al
	in	al, dx
	and	al, CMD_TE | CMD_RE
	cmp	al, CMD_TE | CMD_RE
	jz	0f
	printlnc 4, "rtl8139: warning: transmitter/receiver not enabled"
0:

	# register the card
	push	ecx
	mov	ecx, NIC_RTL8139_STRUCT_SIZE
	call	nic_newentry
	pop	ecx

	mov	ebx, eax
	add	ebx, edx

	mov	[ebx + nic_rx_buf], ecx

	# register a name
	LOAD_TXT "rtl8139"
	lea	edi, [ebx + nic_name]
	mov	eax, esi
	call	strlen
	mov	ecx, eax
	rep	movsb

	# fill in the methods
	mov	dword ptr [ebx + nic_api_send], offset rtl8139_send
	mov	dword ptr [ebx + nic_api_print_status], offset rtl8139_print_status

	# fill in the port
	mov	dx, [ebp]
	mov	[ebx + nic_port], dx

	# fill in the MAC address
	mov	edi, ebx
	add	edi, offset nic_mac

	add	dx, RTL8139_MAC
	mov	ecx, 6
0:	in	al, dx
	stosb
	inc	dx
	loop	0b

	# fill in the MCAST
	mov	edi, ebx
	add	edi, offset nic_mcast

	mov	dx, [ebp]
	add	dx, RTL8139_MAR
	mov	ecx, 8
0:	in	al, dx
	stosb
	inc	dx
	loop	0b

	# hook the isr

	push	ebx
	mov	ebx, offset rtl8139_isr
	add	ebx, [realsegflat]
	mov	ax, NIC_IRQ + 0x20
	mov	cx, cs
	call	hook_isr
	pop	ebx

	call	newline

	mov	al, NIC_IRQ
	call	pic_enable_irq_line32

	# enable all interrupts

	mov	dx, [ebp]
	add	dx, RTL8139_IMR
	mov	ax, -1
	out	dx, ax


	clc
9:	pop	edx
	pop	ebp
	ret

NIC_DEBUG = 1

rtl8139_isr:
	push	eax
	push	ebx
	push	edx

	.if NIC_DEBUG
		printc 0xf5, "NIC ISR"
	.if NIC_DEBUG > 1
		call	print_ISR
		call	print_CBR
		#call	print_TSDs
	.endif
	.endif

	# check what interrupts
	mov	dx, NIC_IO + RTL8139_ISR
	in	ax, dx
	test	ax, IR_TOK
	jnz	0f
	test	ax, IR_ROK
	jnz	1f

	# unknown: just clear them all
	.if NIC_DEBUG
		printc 0xf4 "?"
	.endif
	out	dx, ax	# mark them all as handled
	jmp	2f

0:	# tok
	.if NIC_DEBUG
		printc 0xf3, "Tx"
	.endif
	mov	ax, IR_TOK
	out	dx, ax

	mov	dx, NIC_IO + RTL8139_TSD0
	xor	eax, eax
	or	eax, TSD_OWN	# reset, dont trigger send
	out	dx, eax
	jmp	2f

1:	# rok
	.if NIC_DEBUG
		printc 0xf3, "Rx"
	.endif
	mov	ax, IR_ROK
	out	dx, ax


	# Read the CBR
	mov	dx, NIC_IO + RTL8139_CBR
	in	ax, dx
	movzx	ecx, ax

0:	# read packet / update CAPR
	mov	dx, NIC_IO + RTL8139_CAPR
	xor	eax, eax
	in	ax, dx
	add	ax, 16	# correct for CAPR+16=CBR

	# handle buffer wrap
	cmp	eax, 8192
	jb	3f
	xor	eax, eax
3:	
	mov	ebx, [nics]
	mov	ebx, [ebx + nic_rx_buf]

	push	esi
	push	ecx
	push	eax
	push	ebx
	push	edx
	pushcolor 0x8b

	lea	esi, [ebx + eax + 4]
	mov	ecx, [ebx + eax]
	DEBUG_DWORD ecx
	shr	ecx, 16
	print "DST "
	call	nic_printmac$
	add	esi, 6
	print " SRC "
	call	nic_printmac$
	add	esi, 6
	movzx	edx, word ptr [esi]
	xchg	dl, dh

	print " PROTO "
	call	printhex4
	call	printspace
	call	net_print_protocol$

	call	printspace

	popcolor
	pop	edx
	pop	ebx
	pop	eax
	pop	ecx
	pop	esi

	mov	ebx, [ebx + eax]
	.if NIC_DEBUG > 1
		DEBUG_DWORD eax				# 1fc4
		DEBUG_DWORD ebx			# 40 => 2004
	.endif

	.if NIC_DEBUG
		# check flags
		PRINTFLAG bx, RSR_MAR, "MAR "
		PRINTFLAG bx, RSR_PAM, "PAM "
		PRINTFLAG bx, RSR_BAR, "BAR "

		PRINTFLAG bx, RSR_ISE, "ISE "
		PRINTFLAG bx, RSR_RUNT, "RUNT "
		PRINTFLAG bx, RSR_LONG, "LONG "
		PRINTFLAG bx, RSR_CRC, "CRC "
		PRINTFLAG bx, RSR_FAE, "FAE "
		PRINTFLAG bx, RSR_ROK, "ROK "
	.endif

	# shift out the status bits
	shr	ebx, 16
	# packet size may be not dword aligned
	add	bx, 3
	and	bx, ~3
	add	eax, ebx			# 2004
	# add 4 bytes of the packet header (ebx) to get proper end-of-packet
	# subtract 16 bytes so that the card will write new packets. 
	# CAPR must be 16 bytes before CBR.
	add	eax, 4 - 16			# 2008  - 16
	# wrap
	cmp	eax, 8192
	jb	3f
	sub	eax, 8192
3:
	.if NIC_DEBUG > 1
		DEBUG "CBR"
		DEBUG_WORD ax
	.endif
	out	dx, ax	# update CAPR


	# infinite loop check
	ror	ecx, 16
	inc	cx
	cmp	cx, 10
	jb	3f
	printlnc 4, "packet burst - might be bug"
	jmp	halt
3:	ror	ecx, 16

	# check if we have more packets:
	add	ax, 16
	cmp	ax, cx
	jb	0b
4:

2:
	.if NIC_DEBUG > 1
		#call	print_ISR
		call	print_CBR
	.endif

#	call	print_TSDs

	printlnc 0xf5, "DONE"
	PIC_SEND_EOI NIC_IRQ
	pop	edx
	pop	ebx
	pop	eax
	iret


# in dx = protocol id
net_print_protocol$:
	.macro DECLNAME n
		.data 1
		99: .asciz "\n"
		.data
		.long 99b
		.text
	.endm
	.data
	proto$:		.word 0x0800, 0x0806, 0x86dd
	protoname$:	
	DECLNAME "IPv4"
	DECLNAME "ARP"
	DECLNAME "IPv6"
	.data
	proto_print_handlers$: .long pph_ipv4$, pph_arp$, pph_ipv6$
	.text

	cmp	dx, 1500
	ja	1f
	print	"LLC"
	ret
1:
	push	edi

	mov	edi, offset proto$
	mov	ecx, ( offset protoname$ - offset proto$ ) / 2
	mov	ax, dx
	repne	scasw
	jz	1f
	print	"Unknown"
	jmp	2f

1:
	sub	edi, 2
	sub	edi, offset proto$

	push	esi
	mov	esi, [protoname$ + edi * 2]
	call	print
	pop	esi

	mov	edi, [proto_print_handlers$ + edi * 2]
	add	edi, [realsegflat]
	push	esi
	add	esi, 2	# nested protocol frame pointer
	call	newline
	call	edi
	pop	esi

2:	pop	edi

	ret

pph_ipv4$:
	print "IPv4 "
	mov	dl, [esi + ipv4_v_hlen]
	call	printhex2	# should be 0x45
	mov	dl, [esi + ipv4_protocol]
	print " proto "
	call	printhex2
	xor	edx, edx
	mov	al, '.'
	.macro PRINT_IP initoffs
		i = \initoffs
		.rept 3
		mov	dl, [esi + i]
		call	printdec32
		call	printchar
		i=i+1
		.endr
		mov	dl, [esi + i]
		call	printdec32
	.endm
	print " src "
	PRINT_IP ipv4_src
	print " dst "
	PRINT_IP ipv4_dst

	ret

pph_arp$:
	print "ARP"
	ret
pph_ipv6$:
	print "IPv6"
	ret

# in: ebx = nic device
# in: esi = packet
# in: ecx = packet size
rtl8139_send:

.if 0
DEBUG "send"
call	rtl8139_print_status
.endif


	# get descriptor: MUST use round robin, otherwise only 1 packet is sent
	mov	dx, [ebx + nic_rtl8139_desc_idx]

	mov	ax, dx
	inc	ax
	cmp	ax, 4
	jb	0f
	xor	ax, ax
0:	mov	[ebx + nic_rtl8139_desc_idx], ax

	shl	dx, 2
	add	dx, [ebx + nic_port]


	xor	eax, eax
	call	get_ds_base
	add	eax, esi

	add	dx, RTL8139_TSAD0
	out	dx, eax

	add	dx, RTL8139_TSD0 - RTL8139_TSAD0
	mov	eax, ecx
	and	eax, TSD_SIZE	# TODO: check
	# leave early transmit at 0 (8 bytes)
	# clears OWN bit (among others)
	out	dx, eax

	.if 0
		push edx
		call	rtl8139_print_status
		pop edx
	.endif

.if 0
	mov	ecx, 0x1000
0:	in	eax, dx
	test	eax, TSD_OWN
	jnz	0f
	loop	0b
0:	
DEBUG "FIFO"
DEBUG_DWORD eax

	mov	ecx, 0x1000
0:	in	eax, dx
	test	eax, TSD_TOK
	jnz	0f
	loop	0b
0:	
DEBUG "TOK"
DEBUG_DWORD eax
		call	rtl8139_print_status
.endif
	# let the IRQ handler deal with it

#	print "Clear TOK in ISR "
#	# clear bit in ISR
#	mov	dx, NIC_IO + RTL8139_ISR
#	mov	ax, IR_TOK
#	out	dx, ax
#	call	newline
	
#		call	rtl8139_print_status
	ret


rtl8139_print_status:
	printlnc 11, "rtl8139: status:"
	print	"  "
	call	print_CR
	call	newline

	.if 0
	print	"  "
	call	print_IMR
	call	newline
	.endif
	print	"  "
	call	print_ISR

	print "  "
	call	print_RCR


	call	print_CBR
	print	"  "
	call	print_TSDs
	ret

##########################
print_CBR:
	printc	15, "CBR: "
	mov	dx, NIC_IO + RTL8139_CBR
	in	ax, dx
	mov	dx, ax
	call	printhex4

	printc 15, " CAPR: "
	mov	dx, NIC_IO + RTL8139_CAPR
	in	ax, dx
	mov	dx, ax
	call	printhex4
.if 0
	printc 15, " ERCBR: "
	mov	dx, NIC_IO + RTL8139_ERBCR
	in	ax, dx
	mov	dx, ax
	call	printhex4
.endif
	ret


##########################
print_RCR:
	mov	dx, NIC_IO + RTL8139_RCR
	in	ax, dx
	mov	dx, ax
	printc 15, "RCR: "
	call	printhex4
	call	printspace
	ret
##########################
print_CR:
	printc	15, "CR:  "
	mov	dx, NIC_IO + RTL8139_CR
	in	al, dx
	mov	dl, al
	call	printhex2

	test	al, CMD_RE
	jz	0f
	print	" Rx"
0:
	test	al, CMD_TE
	jz	0f
	print	" Tx"
0:
	test	al, CMD_BUFE
	jz	0f
	print	" BUFE"
	ret
0:	print	" Packet available"
# XXX
	ret



_pa$:
	jz	1f
	print	"enabled"
	ret
1:	print	"disabled"
	ret

print_IMR:
	printc	15, "IMR: "
	mov	dx, NIC_IO + RTL8139_IMR
	jmp	print_IR$

print_ISR:
	printc	15, "ISR: "
	mov	dx, NIC_IO + RTL8139_ISR
	jmp	print_IR$

print_IR$:
	push	esi
	LOAD_TXT "SERR\0TimeOut\0LenChg\0.12\0.11\0.10\0.9\0.8\0.7\0FOVW\0PUN/LinkChg\0RXOVW\0TER\0TOK\0RER\0ROK\0"
	in	ax, dx
	mov	dx, ax
	call	printhex4
	call	printspace
	call	_print_flags16$
	pop	esi
	ret


print_TSDs:
	call	newline
	mov	edx, 0
	call	0f
	mov	edx, 1
	call	0f
	mov	edx, 2
	call	0f
	mov	edx, 3
	call	0f
	ret

print_TSD:
0:	printc	15, "TSD"
	call	printdec32
	printc 15, ": "
	call	printspace
	shl	dx, 2
	add	dx, NIC_IO + RTL8139_TSD0
	in	eax, dx
	mov	edx, eax
	call	printhex8
	call	printspace

	PRINTFLAG eax, TSD_CRS, "CRS "
	PRINTFLAG eax, TSD_TABT, "TABT "
	PRINTFLAG eax, TSD_OWC, "OWC "
	PRINTFLAG eax, TSD_CDH, "CDH "
	PRINTFLAG eax, TSD_TOK, "TOK "
	PRINTFLAG eax, TSD_TUN, "TUN "
	PRINTFLAG eax, TSD_OWN, "OWN "
.if 0
	PRINT "(NCC "
	and	edx, TSD_NCC
	shr	edx, 24
	call	printdec32

	print	" ERTXTH "
	mov	edx, eax
	and	edx, TSD_ERTXTH
	shr	edx, 16
	jz	1f
	shl	edx, 5	# * 32 bytes
	jmp	2f
1:	mov	edx, 8
2:	call	printdec32

	print	" SIZE "
	mov	edx, eax
	and	edx, TSD_SIZE
	call	printdec32

	println ")"
.endif
	ret


#########################################################################
ph$:	push dx
	mov	dl, al
	call	printhex2
	mov	al, ':'
	call	printchar
	pop	dx
	ret

_print_flags8$:
	push	ebx
	push	ecx
	mov	bl, al
	mov	ecx, 8
0:	shl	bl, 1
	jnc	1f
	call	print_
	call	printspace
	jmp	2f
1:	PRINTSKIP_
2:	loop	0b
	pop	ecx
	pop	ebx
	ret

_print_flags16$:
	push	ebx
	push	ecx
	mov	ecx, 16
	mov	bx, ax
0:	shl	bx, 1
	jnc	1f
	call	print_
	call	printspace
	jmp	2f
1:	PRINTSKIP_
2:	loop	0b
	pop	ecx
	pop	ebx
	ret



	.macro PRINT_REG n, p, r, s
		printc 15, "\n: "
		# select page
#		mov	dx, NIC_IO + NE2K_IO_CR
		mov	al, \p << 6
		out	dx, al

		mov	dx, NIC_IO + \r
		in	al, dx
		mov	dl, al
		pushcolor 6 
		call	printhex2
		popcolor
		call	printspace
		LOAD_TXT "\s"
		call	_print_flags$
		call	printspace
	.endm

#	PRINT_REG "CR", 0, NE2K_IO_CR, "P13\0P02\0RD2\0RD1\0RD0\0TXP\0STA\0STP"


# out: eax
get_ds_base:
	push	edx
	mov	edx, ds
	GDT_GET_BASE edx	# in: edx; out: eax
	pop	edx
	ret
