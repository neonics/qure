#x#############################################################################
# Networking
#
# Ethernet, ARP, IPv4, ICMP
.intel_syntax noprefix
.code32
##############################################################################
NET_DEBUG = 0
NET_QUEUE_DEBUG = 0
NET_ARP_DEBUG = NET_DEBUG
NET_IPV4_DEBUG = NET_DEBUG

NET_RX_QUEUE_MIN_SIZE = 8

#############################################################################
	.macro PRINT_IP initoffs
		mov	al, '.'
		xor	edx, edx
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

#############################################################################
PROTO_PRINT_ETHERNET = 1	# 0 = never, 1 = only if nested print, 2=always
PROTO_PRINT_LLC = 0
PROTO_PRINT_IPv4 = 1
PROTO_PRINT_ARP = 1
PROTO_PRINT_IPv6 = 0


COLOR_PROTO_DATA = 0x07
COLOR_PROTO = 0x0f
COLOR_PROTO_LOC = 0x09

####################################################
# Protocol handler declarations

#####################################################
.struct 0
proto_struct_name:	.long 0
proto_struct_handler:	.long 0
proto_struct_print_handler:.long 0
proto_struct_flag:	.byte 0
PROTO_STRUCT_SIZE = .
.text32

.macro DECL_PROTO_STRUCT name, handler1, handler2, flag
	.section .strings
	99: .asciz "\name"
	.data SECTION_DATA_CONCAT
	.long 99b
	.long \handler1
	.long \handler2
	.byte \flag
.endm

.macro DECL_PROTO_STRUCT_START name
	.data
	\name\()_proto$:
	.data SECTION_DATA_CONCAT
	\name\()_proto_struct$:
.endm

.macro DECL_PROTO_STRUCT_W code, name, handler1, handler2, flag
	.data
	.word \code
	DECL_PROTO_STRUCT \name, \handler1, \handler2 \flag
.endm

.macro DECL_PROTO_STRUCT_B code, name, handler1, handler2, flag
	.data
	.byte \code
	DECL_PROTO_STRUCT \name, \handler1, \handler2, \flag
.endm

.macro DECL_PROTO_STRUCT_END name, const, codesize
	.data SECTION_DATA_CONCAT
	\const\()_PROTO_LIST_SIZE = ( . - \name\()_proto_struct$ ) / PROTO_STRUCT_SIZE
	.text32
.endm

#
#############################################################################
.data SECTION_DATA_BSS
ipv4_id$: .word 0
BUFFER_SIZE = 0x600
net_buffers: .long 0	# ptr_array
net_buffer_index: .long 0
NET_BUFFERS_NUM = 4
net_tx_buffers_sem: .long 0
.text32
##############################################################################
.macro DEBUG_NET_BUF
	push	ecx
	push	eax
	push	edx
	pushcolor 0x1f
	call	newline
	printc 0x1d, "NETBUFS "
	mov	eax, [net_buffers]
	or	eax, eax
	jnz	1f
	printlnc 4, "none"
	jmp	2f

1:	mov	edx, eax
	call	printhex8

	printc	0x1d, " idx "
	mov	edx, [eax + array_index]
	call	printhex8

	printc 0x1d, " cap "
	mov	edx, [eax + array_capacity]
	call	printhex8

	printc	0x1c, " INDEX "
	mov	edx, [net_buffer_index]
	call	printhex8
	call	newline

	printc 0x1e, "ptrs: "
	xor	ecx, ecx
90:	mov 	edx, [eax + ecx]
	call	printhex8
	call	printspace
	add	ecx, 4
	cmp	ecx, 4 * NET_BUFFERS_NUM
	jbe	90b
	call	newline
2:	popcolor
	pop	edx
	pop	eax
	pop	ecx
.endm


# out: eax = mem address of BUFFER_SIZE bytes, paragraph aligned
# modifies: edx
net_buffer_allocate$:
	PTR_ARRAY_NEWENTRY [net_buffers], NET_BUFFERS_NUM, 9f	# out: eax + edx
	jc	9f
	mov	[net_buffer_index], edx
	add	edx, eax
	mov	eax, BUFFER_SIZE + 16
	call	mallocz
	mov	[edx], eax
	jnc	1f
9:	printlnc 0x4f, "net_buffer_allocate: malloc error"
	stc
	pop_	edx eax
	ret
# KEEP-WITH-NEXT (1f)

# XXX TODO FIXME: currently round robin without usage check!
# Proposed solution: add bitstring marking buffer occupation
#
# out: edi
net_buffer_get:
	push_	eax edx
	mov	eax, [net_buffers]
	or	eax, eax
	jz	net_buffer_allocate$
	mov	edx, [net_buffer_index]
	add	edx, 4
	cmp	edx, [eax + array_capacity]
	jb	0f
	xor	edx, edx	# round robin
0:	mov	[net_buffer_index], edx
	cmp	edx, [eax + array_index]
	mov	eax, [eax + edx]
	jnb	net_buffer_allocate$
1:	add	eax, 15
	and	al, 0xf0
	mov	edi, eax

	# clear buffer
	push	ecx
	xor	eax, eax
	mov	ecx, BUFFER_SIZE >> 2
	rep	stosd
	sub	edi, BUFFER_SIZE
	pop	ecx

	pop_	edx eax
	clc
	ret

# out: edi
.macro NET_BUFFER_GET
	call	net_buffer_get
.endm

# in: esi = start of buffer
# in: ecx = length of buffer
# in: ebx = nic
net_buffer_send$:
	push	eax
	mov	eax, cs
	and	al, 3
	pop	eax
	jz	net_buffer_send
	KAPI_CALL net_buffer_send
	ret

# in: esi = start of buffer
# in: ecx = length of buffer
# in: ebx = nic
KAPI_DECLARE net_buffer_send
net_buffer_send:
	call	[ebx + nic_api_send]
	ret

# in: esi = start of buffer
# in: edi = end of data in buffer
# in: ebx = nic
# modifies: ecx
.macro NET_BUFFER_SEND
	mov	ecx, edi
	sub	ecx, esi
	call	net_buffer_send$
.endm

.macro NET_BUFFER_FREE
	# TODO
.endm

net_buffers_print:
	printc 11, "tx buffers: "
	mov	edx, [net_buffers]
	mov	edx, [edx + array_index]
	shr	edx, 2
	call	printdec32
	print " x "
	xor	edx, edx
	mov	eax, BUFFER_SIZE
	call	print_size
	call	newline
	ret

##############################################################################
# gas does not use path's relative to the source file.
# core protocols:
.include "net/eth.s"
.include "net/arp.s"
.include "net/ipv4.s"
.include "net/ipv6.s"
#
.include "net/route.s"
.include "net/socket.s"
# socket-enabled protocols: (arp also)
.include "net/icmp.s"
.include "net/igmp.s"	# no socket yet
.include "net/udp.s"
.include "net/tcp.s"

# services
.include "net/dhcp.s"
.include "net/tftp.s"
.include "net/dns.s"
.include "net/httpd.s"
.include "net/smtp.s"
.include "net/sip.s"
.include "net/ssh.s"

.include "net/cloudnet.s"

###########################################################################
# LLC - Logical Link Control
#
net_llc_handle:ret

# in: dx = length (ethernet.proto)
net_llc_print:
	printc	COLOR_PROTO, "LLC "

	mov	ax, dx		# payload size

	print	"DSAP "
	mov	dl, [esi]
	call	printhex2
	print	" SSAP "
	mov	dl, [esi+1]
	call	printhex2
	print	" Control "
	mov	dl, [esi + 2]
	call	printhex2
	add	esi, 3

	sub	ax, 3
	print	" payload len: "
	mov	dx, ax
	call	printhex4

	ret

#############################################################################
# IPv6
#
net_ipv6_print:
	printc	COLOR_PROTO, "IPv6 "
	call	newline
	ret


#############################################################################

# RFC 1071: computing internet checksums.
#
# in: esi = pointer to header to checksum
# in: edi = offset relative to esi to receive checksum
# in: ecx = length in bytes
protocol_checksum_:
	push	edx
	push	eax
	jmp	1f
protocol_checksum:
	jecxz	9f
	push	edx
	push	eax
	xor	edx, edx
1:	xor	eax, eax
	mov	[esi + edi], ax

	push	ecx
	shr	ecx, 1
	jc	2f
3:	push	esi
0:	lodsw
	add	edx, eax
	loop	0b
	pop	esi
	pop	ecx

	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	adc	ax, 0
	not	ax
	mov	[esi + edi], ax

	pop	eax
	pop	edx
9:	ret

2:	mov	al, [esi + ecx * 2]
	add	edx, eax
	jmp	3b


# in: esi = pointer to header to checksum
# in: ecx = length in bytes
# out: CF = !ZF (jnz=jc, jz=jnc)
protocol_checksum_verify:
	push_	eax ecx edx esi
	xor	edx, edx
	xor	eax, eax

	shr	ecx, 1
	jc	2f
0:	lodsw
	add	edx, eax
	loop	0b

	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	adc	ax, 1
	stc
	jnz	1f
	clc

1:	pop_	esi edx ecx eax
	ret

2:	mov	al, [esi + ecx * 2]
	add	edx, eax
	jmp	3b



#############################################################################

# in: eax
.global net_print_ipv4
net_print_ipv4:
net_print_ip:
	push	eax
	push	edx
	movzx	edx, al
	call	printdec32
	mov	al, '.'
	call	printchar
	mov	dl, ah
	call	printdec32
	call	printchar
	ror	eax, 16
	mov	dl, al
	call	printdec32
	mov	al, '.'
	call	printchar
	mov	dl, ah
	call	printdec32
	ror	eax, 16
	pop	edx
	pop	eax
	ret

# in: eax
.global net_print_ipv4_mask
net_print_ipv4_mask:
	# if the mask is /^1{N}0{32-N$/ then print as bits, else as IP.
	push_	eax ecx edx
	mov	ecx, -1# for debug
	bsr	ecx, eax	# find highest bit set (IP is in NBO: A.B.C.D = 0xDDCCBBAA)
	jz	1f		# no bits set	# XXX http://web.itu.edu.tr/~aydineb/index_files/instr/bsr.html has it wrong!
	# ecx = highest bit set.
	# check if all bits below it are also set:
	mov	edx, 2
	shl	edx, cl
	dec	edx
	cmp	eax, edx
	jnz	2f
	# all low bits set.
	lea	edx, [ecx + 1]	# bit 0 set: mask /1
	pushcolor 3
	call	printdec32
	popcolor
	jmp	9f

2:	# not all high bits set. print as IP
	call	net_print_ipv4
	jmp	9f

1:	printc 12, "0";DEBUG_DWORD eax;DEBUG_DWORD ecx; call net_print_ipv4
9:	pop_	edx ecx eax
	ret

# in: eax = stringpointer
# out: eax = ip
.global net_parse_ip
net_parse_ip:
	push	ebx
	mov	bl, 1
	call	net_parse_ip$
	pop	ebx
	ret

# in: eax = stringpointer
# out: eax = ip
net_parse_ip_:
	push	ebx
	xor	bl, bl
	call	net_parse_ip$
	pop	ebx
	ret

# in: eax = stringpointer
# in: bl = 1: print parse errors; 0: don't
# out: eax = ip
net_parse_ip$:
	push	esi
	push	edx
	push	ecx
	mov	edx, eax

	mov	esi, eax
	.rept 3
	call	atoi_
	cmp	byte ptr [esi], '.'
	jnz	1f
	cmp	eax, 255
	ja	1f
	shl	ecx, 8
	mov	cl, al
	inc	esi
	.endr
	call	atoi_
	jc	1f
	cmp	eax, 255
	ja	1f
	shl	ecx, 8
	mov	cl, al
	mov	eax, ecx
	bswap	eax

	clc

0:	pop	ecx
	pop	edx
	pop	esi
	ret

1:	or	bl, bl
	stc
	jz	0b
	printc 12, "net_parse_ip: malformed IP address: "
	print "at '"
	call	print
	print "': "
	mov	esi, edx
	call	println
	stc
	jmp	0b


net_print_mac:
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

# in: edx = ip frame
# in: esi = udp or tcp frame (or ptr to sport, dport in network byte order)
net_print_ip_pair:
	add	edx, offset ipv4_src
	add	esi, offset udp_sport
	call	net_print_ip_port
	printc	8, "->"
	add	edx, offset ipv4_dst - ipv4_src
	add	esi, offset udp_dport - udp_sport
	call	net_print_ip_port
	sub	edx, offset ipv4_dst
	sub	esi, offset udp_dport
	ret

# in: edx = ptr to ipv4 src
# in: esi = ptr to port, network byte order
net_print_ip_port:
	push	eax
	push	edx
	mov	eax, [edx]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [esi]
	xchg	dl, dh
	call	printdec32
	pop	edx
	pop	eax
	ret

# in: esi
# in: ecx
net_packet_hexdump:
	push	eax
	push	ecx
	push	edx
	push	esi
	PUSHCOLOR 0xb0

	mov	ah, 16
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace

	dec	ah
	jnz	2f
	call	newline
	mov	ah, 16
2:	loop	0b

	call	newline
	POPCOLOR
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret


#######################################################
# Packet Analyzer

# in: ebx = nic
# in: esi = ethernet frame
# in: ecx = packet size
net_handle_packet:
	.if NET_DEBUG > 1
		DEBUG "PKTLEN"
		DEBUG_DWORD ecx
	.endif
	push	esi
	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$	# out: edi
	jc	91f	# firewall: DROP
	# non-promiscuous mode: check target mac
	.if 1
	# check broad/multicast bit
	test	[esi + eth_dst], byte ptr 1 # IG bit
	jnz	0f	# ACCEPT
	.else	# if the b/mcast bit is not set, -1 is impossible
	# check broadcast mac (all -1)
	cmp	[esi + eth_dst], dword ptr -1
	jnz	2f	# not broadcast
	cmp	[esi + eth_dst + 4], word ptr -1
	jz	0f	# ACCEPT
	2:
	.endif
	# verify nic mac
	mov	eax, ebx
	call	nic_get_by_mac # in: esi = mac ptr
	jc	93f	# promiscuous handler
	cmp	eax, ebx
	jnz	94f
0:	# ACCEPT
	mov	edx, [eth_proto_struct$ + proto_struct_handler + edi]
	or	edx, edx
	jz	1f
	add	edx, [realsegflat]
	add	esi, ETH_HEADER_SIZE
	sub	ecx, ETH_HEADER_SIZE
	call	edx
9:	pop	esi
	ret

###
91: 	# DROP: unknown protocol
	call	0f
	printc 4, "unknown protocol: "
	mov	dx, [esi + eth_type]
	call	printhex4
	jmp	9f	# dump packet, goto DROP (9b)

93:	# can't get nic by mac
	printc 4, ""
94:	# nic's mac doesnt match nic on which pkt was received
	mov	ebx, eax	# restore receiving nic
	jmp	0b		# go ahead anyway

1:	call	0f
	pushcolor 4
	cmp	ebx, -1
	jz	1f
	print "no handler for: "
	push	esi
	mov	esi, [eth_proto_struct$ + proto_struct_name + edi]
	call	print
	pop	esi
	call	printspace
	jmp	2f
1:	print	"unknown "



0:	printc 4, "net_handle_packet: dropped packet: "
	ret

9:	call	newline
	call	net_print_protocol
	popcolor
	stc
	jmp	9b	# DROP

# Protocol packet handlers
# These are only called when eth.dst_mac is broadcast or matches a nic


####################################################
# Packet Dumper

# in: esi = points to ethernet frame
# in: ecx = packet size
net_packet_print:
net_print_protocol:
	push_	edi esi ecx
	PUSHCOLOR COLOR_PROTO_DATA

	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$
	jnc	1f

	call	net_eth_print
	printc 12, "UNKNOWN"
	mov	dx, ax
	call	printhex4
	call	newline
	stc
	jmp	2f

1:
.if PROTO_PRINT_ETHERNET
	call	net_eth_print
	# print the nested protocol name
	push	esi
	mov	esi, [eth_proto_struct$ + proto_struct_name + edi]
	call	println
	pop	esi
.else
	add	esi, 14
.endif
	sub	ecx, 14
	jle	91f

	# check whether to print this protocol
	cmp	byte ptr [eth_proto_struct$ + proto_struct_flag + edi], 0
	jz	2f

	mov	edi, [eth_proto_struct$ + proto_struct_print_handler + edi]
	add	edi, [realsegflat]

#	COLOR	0x87

	call	printspace
	call	printspace
	call	edi

2:	popcolor
	pop_	ecx esi edi
	ret
91:	printc 4, "  short packet"
	jmp	2b

####################################
cmd_host:
	xor	eax, eax
	call	nic_getobject

	lodsd
	lodsd
	or	eax, eax
	jz	9f

	mov	esi, eax
	call	strlen
	mov	ecx, eax

	mov	eax, esi
	call	net_parse_ip_	# _ version: don't print parse errors
	jc	1f

	call	dns_resolve_ptr	# out: eax = mallocced stringbuf
	jc	92f
	mov	esi, eax
	call	println
	call	mfree
	jmp	0f

1:	call	dns_resolve_name
	jc	0f
	call	net_print_ip
	call	newline

0:	ret
9:	printlnc 12, "usage: host <hostname>"
	ret
91:	printlnc 12, "no network adapter"
	ret
92:	printlnc 12, "host not found "
	ret
##############################################################################

NET_RX_QUEUE_DEBUG = 0

# A queue for incoming packets so as to not flood the scheduler with a job
# (and possibly a stack) for each packet.
.struct 0
net_rx_queue_status:	.long 0
	NET_RX_QUEUE_STATUS_FREE	= 0	# 
	NET_RX_QUEUE_STATUS_RESERVED	= 1	# net_rx_queue_getentry sets this
	NET_RX_QUEUE_STATUS_SCHEDULED	= 2	# queue entry is configured.
net_rx_queue_buf:	.long 0		# index into net_rx_buffer / ptr
net_rx_queue_args:	.space 8*4	# pushad; eax+edx, esi,ecx
NET_RX_QUEUE_STRUCT_SIZE = .
.data SECTION_DATA_BSS
net_rx_queue:		.long 0
net_rx_queue_head:	.long 0
net_rx_queue_tail:	.long 0
net_rx_buffer:		.long 0	# receive packet buffer containing copies
.text32

#
# 0 |RW R  R  R |W          |W           |W
# 0 |   W       |R  RW R  R |   W        |   W
# 0 |      W    |      W    |R  R  RW R  |      W
# 0 |         W |         W |         W  |R  R  R  RW

# 0 1 1 0 0
# 0 0 1 1 1
# 0 0 1 1 1
# 0 0 0 1 0

# circular array
# PRECONDITION:
#   tail = starting point for inject
# POSTCONDITION:
#   tail = new starting point for inject
# out: eax + edx
net_rx_queue_newentry:
	push	ecx
	mov	eax, [net_rx_queue]
	or	eax, eax
	jz	1f

	mov	ecx, NET_RX_QUEUE_STRUCT_SIZE
	mov	edx, [net_rx_queue_tail]

	# see if head is before tail
	cmp	edx, [net_rx_queue_head]
	jz	5f
	ja	3f	# 0..head.=?.tail..cap
.if NET_QUEUE_DEBUG
	DEBUG "tail<-head"
.endif
#########
	# 0..tail..head..capacity
	# see if there is room between head..tail
	#add	edx, ecx
	#cmp	edx, [net_rx_queue_head]
	#ja	4f	# no room!
	
	# since ! jae = jb, there is room.
	jmp	2f	# 


#########
3:	# 0..head..tail..capacity
.if NET_QUEUE_DEBUG
	DEBUG "head->tail"
.endif

	# check if there is room between tail...capacity
	cmp	edx, [eax + array_capacity]
	jb	2f	# it'll fit	# XXX maybe jbe
	# won't fit: no room between tail..capacity

	# check if room between 0..head
	cmp	dword ptr [net_rx_queue_head], 0
#	jz	1f	# no room, expand array
	jz	4f	# no room - drop

	# we have room between 0..head
	xor	edx, edx			# return index
	jmp	2f

################################################################################
# this will be called when the queue has not been allocated.
# (and potentially when the queue is expanded).
#
1:	or	eax, eax
	jnz	1f
	# queue is not set up. Allocate a buffer to contain the packet data.
	mov	eax, 1500 * NET_RX_QUEUE_MIN_SIZE
	call	malloc
	jnc	10f
	printc 12, "cannot allocate rx packet buffers"
	stc
	jmp	9f
10:	mov	[net_rx_buffer], eax
	mov	edx, eax

	mov	ecx, NET_RX_QUEUE_STRUCT_SIZE
	mov	eax, NET_RX_QUEUE_MIN_SIZE
	call	array_new	# eax,ecx -> eax
	jc	9f
	mov	[net_rx_queue], eax
	mov	ecx, NET_RX_QUEUE_MIN_SIZE
10:	mov	[eax + net_rx_queue_buf], edx
	add	eax, NET_RX_QUEUE_STRUCT_SIZE
	add	edx, 1500
	loop	10b
	# array_newentry will simply increase array_index.
################################################################################

1: # this'll append - assuming tail = [eax+array_index]
	ARRAY_NEWENTRY [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, NET_RX_QUEUE_MIN_SIZE, 9f
2:	add	ecx, edx
	cmp	ecx, [eax + array_capacity]
	jb	1f
	xor	ecx, ecx
1:	clc
	mov	[net_rx_queue_tail], ecx	# record the new tail
	mov	[eax + edx + net_rx_queue_status], dword ptr NET_RX_QUEUE_STATUS_RESERVED

9:	pop	ecx
	ret

5:	# head = tail
	# check if empty or full:
	cmp	[eax + edx + net_rx_queue_status], dword ptr NET_RX_QUEUE_STATUS_FREE
	jz	3b
	# fallthrough
4:	
.if NET_QUEUE_DEBUG
printlnc 4,"netq full";
pushad;call net_rx_queue_print_;popad;
.endif
stc;jmp 9b	# code below unstable
# 0..tail=head..capacity: no room.
	# expand array
	# reorganize data
	push	esi
	push	edi
	mov	esi, eax	# old [net_rx_queue]

	mov	eax, [eax + array_capacity]
	xor	edx, edx
	div	ecx
	call	array_new
	mov	edi, eax	# edi = new array data

	# copy head...capacity
	mov	ecx, [esi + array_capacity]
	sub	ecx, [net_rx_queue_head]
	mov	[eax + array_index], ecx
	rep	movsb
	mov	dword ptr [net_rx_queue_head], 0

	# append 0..tail
	mov	esi, [net_rx_queue]
	mov	ecx, [net_rx_queue_tail]
	add	ecx, NET_RX_QUEUE_STRUCT_SIZE
	add	[eax + array_index], ecx
	rep	movsb

	xchg	eax, [net_rx_queue]
	call	mfree

	pop	edi
	pop	esi

	jmp	1b

# out: eax + edx
# out: CF = no entry
# EFFECT: move head to next
net_rx_queue_get:
	mov	eax, [net_rx_queue]
	or	eax, eax
	stc
	jz	9f
.if NET_QUEUE_DEBUG
call newline
pushcolor 7
push ebx
push esi
xor esi,esi
0: mov edx, [eax + esi + net_rx_queue_status]

mov bl, 7
cmp esi, [net_rx_queue_tail]
jnz 2f
add bl, 4
2:
cmp esi, [net_rx_queue_head]
jnz 2f
or bl, 0x10
2:
push ebx; color bl; pop ebx
call printhex1
color 7
call printspace

add esi, NET_RX_QUEUE_STRUCT_SIZE
cmp esi, [eax + array_capacity]
jb 0b
pop esi
pop ebx
popcolor
#pushad
#call net_rx_queue_print_
#popad
.endif

	mov	edx, [net_rx_queue_head]
	cmp	[eax + edx + net_rx_queue_status], dword ptr NET_RX_QUEUE_STATUS_SCHEDULED
	stc
	# overlook the case NET_RX_QUEUE_STATUS_RESERVED as it will be SCHEDULED shortly
	jnz	9f
	push	ecx
	lea	ecx, [edx + NET_RX_QUEUE_STRUCT_SIZE]
	cmp	ecx, [eax + array_capacity]
	jb	1f
	xor	ecx, ecx
1:	mov	[net_rx_queue_head], ecx
.if NET_QUEUE_DEBUG
	DEBUG_DWORD ecx,"queue next head"
.endif
	pop	ecx
	clc
.if NET_QUEUE_DEBUG
	ret
9:	DEBUG "net_rx_queue_get", 0x4f;
	ret
.else
9:	ret
.endif

##############################################################################

# in: ds = es = ss
# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
# out: esi = new packet buffer (at current: the same as input)
# effect: appends a copy of the packet to net_rx_queue
net_rx_packet:
	push	eax
	push	edx
	push	esi

	incd	[ebx + nic_rx_count]
	add	[ebx + nic_rx_bytes + 0], ecx
	adcd	[ebx + nic_rx_bytes + 4], 0

	call	net_check_reboot_packet

cmp ecx, 2000
jb 1f
printc 4, "net_rx_packet: packet size too large: ";DEBUG_DWORD ecx
int 3
1:
	MUTEX_SPINLOCK NET
	call	net_rx_queue_newentry	# out: eax + edx
	jc	91f

	# we have a queue entry - set it up.

	# ** NOTE **
	# It is possible that a task using mem functions (lib/mem.s) is suspended
	# while holding a lock. In that case the mdup's spinlock will yield,
	# causing the NIC IRQ handler to be suspended. Since the IRQ sharing
	# code sends EOI to the PIC before calling the handlers, another interrupt
	# may occur. This interrupt will not be processed until EFLAGS.IF is true,
	# which occurs not only when the IRQ handler calling this method IRET's,
	# but also when another task it scheduled that has interrupts enabled -
	# which is the case by default.
	# This method then is reentrant, and will cause MUTEX_SPINLOCK timeouts
	# for NET if the MEM mutex is locked at this point.
	#
	# In theory, using round robin scheduling, the task holding the lock will
	# get scheduled again and will release it. Only when another task acquires
	# the lock and is suspended before this task is scheduled again will
	# the problem persist.
	#
	# However, it appears that is more often the case than one would expect.
	#
	# More advanced mutex aware scheduling would record the fact that a task
	# is suspended (YIELD) because it failed to acquire a mutex.
	# The scheduler would prioritize to schedule the task that holds the lock,
	# and be notified when it is released. At this point it would take over
	# once more and schedule the task attempting to hold the lock.
	#
	# An approach relying entirely on the hook in acquiring a mutex would
	# be aware that another task had already attempted to acquire the lock
	# and failed to do so, and suspend the new task until the old task
	# had acquired and released the lock: a first-come-first-serve basis.
	#
	# Since the timeout only occurs when both NET and MEM are locked,
	# another solution could be attempted. For, the NET mutex is only
	# used in this file, whereas the MEM mutex is used throughout the
	# kernel and all it's tasks, as they all share the same heap. This is
	# indeed insecure as any task could corrupt all other tasks and even
	# the kernel, however, it allows for testing the kernel's integrity.
	#
	# A solution preventing both task and kernel corruption aswell as
	# making the NET mutex depend on the global MEM mutex is to have
	# memory allocation per task, and to have a per task MEM mutex.
	# (the recently removed 'local mutex' code).
	#
	# As yet there is no concept of threads-within-a-process implemented,
	# as all tasks are seen as kernel threads. The most straighforward
	# way then is to have per-task memory management, which may prevent
	# tasks from referring to each others' data if the heap is mapped
	# to the same address for each task. What is supported however, if
	# the kernel heap is distinct from task heap, is for a task to share
	# and expose it's data with the kernel.
	#
	# Such memory allocation would use the same mechanism as is used for
	# allocating the privileged stack for tasks, which means that the kernel
	# has access to the memory of all tasks simultaneously as each page
	# has a different physical address, and the kernel's view of the memory
	# is through identity mapping.
	# This then would allow each task to indicate whether it's memory is to
	# be private within the task context, or public, accessible to other tasks.
	# This then would mean that there have to be two pages and thus two pools
	# of memory allocation. A flag can be passed to indicate which type of
	# memory is to be allocated.
	#
	# Regardless of all of the above, at current interrupts, which require
	# privilege elevation, run in the context of the task they interrupted.
	# Suspending the thread of execution would also suspend the interrupted
	# task, as it won't continue until the interrupt has completed.
	#
	# This then is why it can occur that the NET mutex remains locked,
	# as in those cases it is the interrupted task that has acquired the
	# lock, and it will not be scheduled to execute, because when it is,
	# it is the interrupt that will run.
	#
	# Therefore, interrupts must execute within their own task context
	# so that they can be scheduled individually, independent of the
	# task they interrupt.
	# 
#########
#	call	mdup	# in: esi, ecx; out: esi
#net_rx_pkt$:	# debug symbol for malloc handles
#	jc	92f
#########
push_ esi edi ecx edx
# get preallocated buffer location
mov edi, [eax + edx + net_rx_queue_buf]
# copy
mov dl, cl
shr ecx, 2
rep movsd
mov cl, dl
and cl, 3
rep movsb
pop_ edx ecx edi esi
# have esi be the new packet source
mov esi, [eax + edx + net_rx_queue_buf]
#########
	pushad
	lea	edi, [eax + edx + net_rx_queue_args]
	mov	esi, esp
	mov	ecx, 8
	rep	movsd
	popad
	mov	[eax + edx + net_rx_queue_status], dword ptr NET_RX_QUEUE_STATUS_SCHEDULED
	call	net_rx_queue_schedule
########################################################

0:	MUTEX_UNLOCK NET
	pop	esi
	pop	edx
	pop	eax
	ret

90:	printc 4, "net: packet dropped: "
	mov	ah, 4
	call	printlnc
	jmp	0b

91:	incd	[ebx + nic_rx_dropped]
	LOAD_TXT "queue full"
	jmp	90b

92:	LOAD_TXT "mdup error"
	jmp	90b

########################################################
.data SECTION_DATA_BSS
net_rx_queue_scheduled$:.byte 0
netq_sem:	.long 0
ethdump_val$:	.byte 0
.text32
net_rx_queue_schedule:	# target for net_rx_queue_handler if queue not empty
	lock inc dword ptr [netq_sem]	# notify scheduler

	cmp	byte ptr [net_rx_queue_scheduled$], 1
	jz	1f
	lock inc byte ptr [net_rx_queue_scheduled$]

	push_	esi edi eax
	LOAD_TXT "ethdump", esi
	LOAD_TXT "0", edi
	mov	eax, offset net_ethdump_var_changed$
	call	shell_variable_set
	pop_	eax edi esi

	PUSH_TXT "netq"
	push	dword ptr 0#TASK_FLAG_TASK#TASK_FLAG_RESCHEDULE # flags
	push	cs
	push	eax
	mov	eax, offset net_rx_queue_handler
	add	eax, [realsegflat]
	xchg	eax, [esp]
	# use KAPI because it requires page mapping and CR3 is not
	# modified for normal (network) interrupts.
	KAPI_CALL schedule_task
	jc	91f

	# hint scheduler that this task will process data buffered
	# by PCI NIC device interrupt handlers
	push	ebx
	mov	ebx, TASK_FLAG_OPT_DEV_PCI
	mov	edx, DEV_PCI_CLASS_NIC
	KAPI_CALL schedule_task_setopt
	pop	ebx

1:	ret

91:	DEBUG_BYTE [net_rx_queue_scheduled$]
	printlnc 4, "schedule error"	# task already scheduled: happens often
	ret	# BUG: edx = [esp] = 00100900

net_ethdump_var_changed$:
	#DEBUG "net: var changed: "
	#DEBUGS [eax + env_var_label]
	#DEBUG "="
	#DEBUGS [eax + env_var_value]
	push_	esi eax
	mov	esi, [eax + env_var_value]
	call	atoi_
	jc	91f
	cmp	eax, 9
	ja	91f
	mov	[ethdump_val$], al
0:	pop_	eax esi
	ret
91:	printc 4, "illegal value for var ethdump: not 0..9"
	jmp	0b


net_check_reboot_packet:
	push_	edi esi ecx
	lea	edi, [ebx + nic_mac]
	lea	esi, [esi + eth_dst]
	cmpsd
	jnz	1f
	cmpsw
	jnz	1f
	sub	esi, 6 + offset eth_dst
	cmpw	[esi + eth_type], 8#bswap word ETH_PROTO_IPV4
	jnz	1f
	cmpb	[esi + ETH_HEADER_SIZE + ipv4_protocol], IP_PROTOCOL_UDP
	jnz	1f
	mov	eax, [esi + ETH_HEADER_SIZE + ipv4_dst]
	mov	ecx, [ebx + nic_ip]
	cmp	eax, ecx
	jnz	1f
	and	eax, [ebx + nic_netmask]
	and	ecx, [ebx + nic_netmask]
	cmp	eax, ecx
	jnz	1f
	cmpw	[esi + ETH_HEADER_SIZE + IPV4_HEADER_SIZE + udp_sport], 0xe703 # NBO 999
	jnz	1f
	cmpw	[esi + ETH_HEADER_SIZE + IPV4_HEADER_SIZE + udp_dport], 0xe703 # NBO 999
	jnz	1f
	cmpd	[esi + ETH_HEADER_SIZE + IPV4_HEADER_SIZE + UDP_HEADER_SIZE], 0x1337c0de
	jnz	1f

	printlnc 0x4f, "Received reboot packet"

	call	SEL_kernelMode:0
	printc 11, "Rebooting"
	cli
	pushd	0
	pushw	0
	lidt [esp]
	int 3

1:	pop_	ecx esi edi
	ret


net_rx_queue_handler:
	cli
	MUTEX_SPINLOCK NET
	call	net_rx_queue_get
	jnc	1f
	MUTEX_UNLOCK NET
	sti

	call	net_tcp_cleanup

	YIELD_SEM (offset netq_sem)
	lock dec dword ptr [netq_sem]
	jmp	net_rx_queue_handler

# note: mutex NET locked!
1:	sub	esp, 8*4
	lea	esi, [eax + edx + net_rx_queue_args]
	mov	edi, esp
	mov	ecx, 8
	rep	movsd
	popad	# esp ignored

	mov	eax, [net_rx_queue]
	mov	[eax + edx + net_rx_queue_status], dword ptr 0

	MUTEX_UNLOCK NET
	sti

	call	net_rx_packet_task
	jmp	net_rx_queue_handler


net_rx_queue_print:
	MUTEX_SPINLOCK NET
	call	net_rx_queue_print_
	MUTEX_UNLOCK NET
	ret

net_rx_queue_print_:
	printc 11, "net_rx_queue: "
	xor	ecx, ecx
	xor	ebx, ebx
	# count packets
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	add	ecx, [eax + edx + net_rx_queue_status]	# 1 indicates pkt in q
	inc	ebx
	ARRAY_ENDL

	mov	edx, ecx
	call	printdec32
	printcharc 11, '/'
	mov	edx, ebx
	call	printdec32
	printc 11, " packets; head="
	mov	edx, [net_rx_queue_head]
	call	printhex8
	printc 11, " tail="
	mov	edx, [net_rx_queue_tail]
	call	printhex8
	mov	eax, [net_rx_queue]
	printc 11, " index="
	mov	edx, [eax + array_index]
	call	printhex8
	printc 11, " cap="
	mov	edx, [eax + array_capacity]
	call	printhex8
	call	newline
.if 1
	mov	eax, [net_rx_queue]
	or	eax, eax
	jz	9f
	xor	ecx, ecx

0:	mov	edx, ecx
	call	printhex8
	print ": "
	mov	edx, [eax + ecx + net_rx_queue_status]
	call	printhex8
	cmp	ecx, [net_rx_queue_head]
	jnz	1f
	printc 11, " head"
1:
	cmp	ecx, [net_rx_queue_tail]
	jnz	1f
	printc 11, " tail"
1:
	call	newline

	add	ecx, NET_RX_QUEUE_STRUCT_SIZE
	cmp	ecx, [eax + array_capacity]
	jb	0b
.endif
9:

	ret

# in: ebx = nic
# in: esi = packet (ethernet frame) [to be freed on completion]
# in: ecx = packet len
# side-effect: esi freed.
net_rx_packet_task:
	cmpb	[ethdump_val$], 0
	jz	1f

	push	esi
	push	ecx
	call	net_print_protocol
	pop	ecx
	pop	esi

1:	push	esi
	call	net_handle_packet
	pop	eax
#	call	mfree
	ret

############################################################################
cmd_netstat:
	call	net_tcp_conn_list
	call	socket_list
	call	net_icmp_list
	call	arp_table_print

	xor	ecx, ecx
0:	mov	eax, ecx
	call	nic_getobject	# eax->eax+edx,ebx
	jc	1f
	call	net_igmp_print
	inc	ecx
	jmp	0b
1:
	call	net_rx_queue_print
	call	net_buffers_print
	ret
