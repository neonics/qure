#x#############################################################################
# Networking
#
# Ethernet, ARP, IPv4, ICMP
.intel_syntax noprefix
.code32
##############################################################################
NET_DEBUG = 0
NET_ARP_DEBUG = NET_DEBUG
NET_IPV4_DEBUG = NET_DEBUG

CPU_FLAG_I = (1 << 9)
CPU_FLAG_I_BITS = 9

# out: CF = IF
.macro IN_ISR
	push	edx
	pushfd
	pop	edx
	.if NET_DEBUG > 1
		DEBUG "FLAGS:"
		call printbin16
	.endif
	shr	edx, CPU_FLAG_I_BITS
	pop	edx
.endm


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
	.data SECTION_DATA_STRINGS # was 2
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
net_buffer_allocate:
	PTR_ARRAY_NEWENTRY [net_buffers], NET_BUFFERS_NUM, 9f	# out: eax + edx
	jc	9f
	mov	[net_buffer_index], edx
	add	edx, eax
	mov	eax, BUFFER_SIZE + 16
	call	malloc
	jc	9f
	mov	[edx], eax
	add	eax, 15
	and	al, 0xf0
	ret
9:	printlnc 0x4f, "net_buffer_allocate: malloc error"
	stc
	ret

# mod: eax edx
net_buffer_get:
	mov	eax, [net_buffers]
	or	eax, eax
	jz	net_buffer_allocate
	mov	edx, [net_buffer_index]
	add	edx, 4
	cmp	edx, [eax + array_capacity]
	jb	0f
	xor	edx, edx
0:	mov	[net_buffer_index], edx
	cmp	edx, [eax + array_index]
	mov	eax, [eax + edx]
	jnb	net_buffer_allocate
	add	eax, 15
	and	al, 0xf0
	clc
	ret

# out: edi
.macro NET_BUFFER_GET
	push	eax
	push	edx
	call	net_buffer_get
	mov	edi, eax
	pop	edx
	pop	eax
.endm

# in: esi = start of buffer
# in: edi = end of data in buffer
# in: ebx = nic
# modifies: ecx
.macro NET_BUFFER_SEND
	mov	ecx, edi
	sub	ecx, esi
	call	[ebx + nic_api_send]
.endm

##############################################################################
# gas does not use path's relative to the source file.
# core protocols:
.include "net/eth.s"
.include "net/arp.s"
.include "net/ipv4.s"
#
.include "net/route.s"
.include "net/socket.s"
# socket-enabled protocols:
.include "net/icmp.s"
.include "net/udp.s"
.include "net/tcp.s"

# services
.include "net/dhcp.s"
.include "net/dns.s"
.include "net/httpd.s"
.include "net/smtp.s"

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

# in: esi = pointer to header to checksum
# in: edi = offset relative to esi to receive checksum
# in: ecx = length in bytes
protocol_checksum_:
	push	edx
	push	eax
	jmp	1f
protocol_checksum:
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
	ret

2:	mov	al, [esi + ecx * 2]
	add	edx, eax
	jmp	3b


#############################################################################

# in: eax
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

# in: eax = stringpointer
# out: eax = ip
net_parse_ip:
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

1:	printlnc 12, "net_parse_ip: malformed IP address: "
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
	add	esi, offset udp_dport
	call	net_print_ip_port
	printc	8, "->"
	add	edx, offset ipv4_dst - ipv4_src
	add	esi, offset udp_sport - udp_dport
	call	net_print_ip_port
	sub	edx, offset ipv4_src
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
	jc	2f
	# non-promiscuous mode: check target mac
	cmp	[esi + eth_dst], dword ptr -1
	jnz	2f
	cmp	[esi + eth_dst + 4], word ptr -1
	jz	0f
2:	# verify nic mac
	mov	eax, ebx
	call	nic_get_by_mac # in: esi = mac ptr
	jc	3f	# promiscuous handler
	cmp	eax, ebx
	jnz	4f
0:	mov	edx, [eth_proto_struct$ + proto_struct_handler + edi]
	or	edx, edx
	jz	1f

	add	edx, [realsegflat]
	add	esi, ETH_HEADER_SIZE
	sub	ecx, ETH_HEADER_SIZE
	call	edx
9:	pop	esi
	ret
3:	# can't get nic by mac
4:	# nic's mac doesnt match nic on which pkt was received
	mov	ebx, eax	# restore receiving nic
	jmp	0b		# go ahead anyway
###
2:	printc 4, "net_handle_packet: dropped packet: unknown protocol: "
	jmp	2f
	mov	dx, [esi + eth_type]
	call	printhex4
	stc
	ret

1:	printc 4, "net_handle_packet: dropped packet: "
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
2:	mov	dx, [esi + eth_type]
	call	printhex4
	call	newline
	call	net_print_protocol
	popcolor
	stc
	jmp	9b


# Protocol packet handlers
# These are only called when eth.dst_mac is broadcast or matches a nic



net_ipv6_handle:
	ret

####################################################
# Packet Dumper

# in: esi = points to ethernet frame
# in: ecx = packet size
net_print_protocol:
	push	edi
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

	# check whether to print this protocol
	cmp	byte ptr [eth_proto_struct$ + proto_struct_flag + edi], 0
	jz	2f

	mov	edi, [eth_proto_struct$ + proto_struct_print_handler + edi]
	add	edi, [realsegflat]

#	COLOR	0x87

	push	esi
	call	printspace
	call	printspace
	call	edi
	pop	esi

2:	popcolor
	pop	edi
	ret

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

	call	net_dns_request

	ret
9:	printlnc 12, "usage: host <hostname>"
	stc
	ret

##############################################################################

NET_RX_QUEUE = 1
NET_RX_QUEUE_ITER_RESCHEDULE = 0	# 0=task loop, 1=task reschedule
NET_RX_QUEUE_DEBUG = 0

.if NET_RX_QUEUE == 0

# in: ds = es = ss
# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet:
	PUSH_TXT "net"
	push	dword ptr 0 # TASK_FLAG_RESCHEDULE # flags
	push	cs
	push	eax
	mov	eax, offset net_rx_packet_task
	add	eax, [realsegflat]
	xchg	eax, [esp]
	call	schedule_task
	jc	9f	# lock fail, already scheduled, ...
	ret
9:	printlnc 4, "net: packet dropped"
	ret

.else
# A queue for incoming packets so as to not flood the scheduler with a job
# (and possibly a stack) for each packet.
.struct 0
net_rx_queue_status:	.long 0
net_rx_queue_args:	.space 8*4
NET_RX_QUEUE_STRUCT_SIZE = .
.data SECTION_DATA_BSS
net_rx_queue:	.long 0
.text32
# out: eax + edx
net_rx_queue_newentry:
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 1f
	cmp	[eax + edx + net_rx_queue_status], dword ptr 0
	jz	2f
	ARRAY_ENDL
1:	ARRAY_NEWENTRY [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, 4, 9f
2:	mov	[eax + edx + net_rx_queue_status], dword ptr 1
9:	ret

# in: ds = es = ss
# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet:
	pushad
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	call	net_rx_queue_newentry	# out: eax + edx
	jnc	1f
	MUTEX_UNLOCK NET
	popad
	jmp	9f

1:	lea	edi, [eax + edx + net_rx_queue_args]
	mov	esi, esp
	mov	ecx, 8
	rep	movsd
	mov	[edi-4], eax
	mov	[edi-12], edx
	popad
	MUTEX_UNLOCK NET

net_rx_queue_schedule:	# target for net_rx_queue_handler if queue not empty
	PUSH_TXT "net"
	push	dword ptr TASK_FLAG_RESCHEDULE # flags
	push	cs
	push	eax
	mov	eax, offset net_rx_queue_handler
	add	eax, [realsegflat]
	xchg	eax, [esp]
	call	schedule_task
	setc	al
	.if NET_RX_QUEUE_DEBUG
		DEBUG_BYTE al
	.endif

# have queue
#	jc	9f	# lock fail, already scheduled, ...
	ret
9:	printlnc 4, "net: packet dropped"
	ret


net_rx_queue_handler:
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + net_rx_queue_status], dword ptr 1
	jz	1f
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET
	ret	# queue exhausted

1:	sub	esp, 8*4
	lea	esi, [eax + edx + net_rx_queue_args]
	mov	edi, esp
	mov	ecx, 8
	rep	movsd
	popad

	mov	eax, [net_rx_queue]
	mov	[eax + edx + net_rx_queue_status], dword ptr 0
	MUTEX_UNLOCK NET

	call	net_rx_packet_task

.if NET_RX_QUEUE_ITER_RESCHEDULE
	# check if the queue is empty, if not, schedule job again
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	xor	ecx, ecx
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	add	ecx, [eax + edx + net_rx_queue_status]
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET

	jecxz	9f
	jmp	net_rx_queue_schedule
9:
.else
	jmp	net_rx_queue_handler
.endif
	ret



net_rx_queue_print:
	printc 11, "net_rx_queue: "
	xor	ecx, ecx
	xor	ebx, ebx
	# count packets
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	add	ecx, [eax + edx + net_rx_queue_status]	# 1 indicates pkt in q
	inc	ebx
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET

	mov	edx, ecx
	call	printdec32
	printcharc 11, '/'
	mov	edx, ebx
	call	printdec32
	printlnc 11, " packets"

	ret
.endif

# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet_task:
	push	esi
	push	ecx
	push	ebx

	push	esi
	push	edx
	push	eax
	LOAD_TXT "ethdump"
	call	shell_variable_get
	pop	eax
	pop	edx
	pop	esi
	jc	1f

	push	esi
	push	ecx
	pushad
	call	net_print_protocol
	popad
	pop	ecx
	pop	esi

1:	call	net_handle_packet

	pop	ebx
	pop	ecx
	pop	esi
	ret

############################################################################
cmd_netstat:
	call	net_tcp_conn_list
	call	socket_list
	call	net_icmp_list
	call	arp_table_print
	.if NET_RX_QUEUE
	call	net_rx_queue_print
	.endif
	ret

