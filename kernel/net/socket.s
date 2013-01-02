#############################################################################
# Sockets
#
# Only AF_INET supported.


NET_SOCKET_DEBUG = 0

SOCKET_BUFSIZE	= 2048

# socket options:
SOCK_LISTEN	= 0x80000000
SOCK_STREAM	= 0x40000000	# 1: continuous buffer; 0: packetized buffer
# NOTE: gnored: the above option is automatically determined based on IP_PROTOCOL_TCP.
SOCK_READPEER	= 0x40000000 	# prepend packetized data with peer address (ip:port)

# internal flags
SOCK_PEER	= 0x04000000
SOCK_ACCEPTABLE	= 0x02000000
.struct 0
sock_addr:	.long 0
sock_port:	.word 0
sock_proto:	.word 0
sock_flags:	.long 0
sock_in_buffer:	.long 0	# buffer.s
sock_cust:	.long 0	# custom data depending on socket (sock idx)
sock_conn:	.long 0 # custom connection information (tcp_conn idx)
SOCK_STRUCT_SIZE = .
.data SECTION_DATA_BSS
socket_array: .long 0
.text32
# in: eax = sock_addr (ip)
# in: edx = sock_proto << 16 | sock_port
# in: ebx = flags (SOCK_LISTEN)
# out: eax = socket index
# out: CF
socket_open:
	push	edi
	push	edx
	push	esi
	push	ecx
	mov	esi, eax	# ip
	mov	edi, edx	# proto, port
	MUTEX_SPINLOCK_ SOCK
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + sock_port], dword ptr -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [socket_array], SOCK_STRUCT_SIZE, 4, 9f
1:	mov	[eax + edx + sock_addr], esi
	mov	[eax + edx + sock_port], edi
	mov	[eax + edx + sock_flags], ebx
	mov	edi, eax

	test	ebx, SOCK_LISTEN
	jnz	1f	# dont alloc buffer for server sockets.

	mov	eax, SOCKET_BUFSIZE
	call	buffer_new
	jc	91f
	mov	[edi + edx + sock_in_buffer], eax

1:	mov	eax, edx
9:	MUTEX_UNLOCK_ SOCK
	pop	ecx
	pop	esi
	pop	edx
	pop	edi
	ret
91:	printlnc 4, "socket_open: out of memory"
	mov	[edi + edx + sock_port], dword ptr -1	# mark available
	mov	eax, -1
	stc
	jmp	9b

socket_close:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	edx

	mov	edx, [socket_array]
		cmp	eax, [edx + array_index]
		ja	9f

	cmp	dword ptr [edx + eax + sock_port], -1
	jz	8f


	# protocol layer
	cmp	byte ptr [edx + eax + sock_proto], IP_PROTOCOL_TCP
	jnz	1f
	push	eax
	mov	eax, [edx + eax + sock_conn]
	call	net_tcp_fin
	pop	eax
1:
	mov	[edx + eax + sock_port], dword ptr -1
	mov	[edx + eax + sock_cust], dword ptr -1
	mov	[edx + eax + sock_conn], dword ptr -1
	.if 0
	add	eax, SOCK_STRUCT_SIZE
	cmp	eax, [edx + array_index]
	jnz	1f
	sub	[edx + array_index], dword ptr SOCK_STRUCT_SIZE
	.endif
	add	edx, eax
	xor	eax, eax
	xchg	eax, [edx + sock_in_buffer]
	or	eax, eax
	jz	1f
	call	buffer_free

1:	MUTEX_UNLOCK_ SOCK
	pop	edx
	ret

9:	printc 12, "socket_close: invalid socket"
0:	printc 12, "; caller: "
	mov	edx, [esp + 4]
	call	debug_printsymbol
	call	newline
	stc
	jmp	1b

8:	printc 12, "socket_close: socket already closed"
	jmp	0b


socket_list:
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, ebx, ecx, 9f
	cmp	dword ptr [ebx + ecx + sock_port], -1
	jz	2f

	printc 11, "socket "
	mov	edx, ecx
	call	printhex4
	printc 11, " ip "
	mov	eax, [ebx + ecx + sock_addr]
	call	net_print_ip
	printcharc 11, ':'
	movzx	edx, word ptr [ebx + ecx + sock_port]
	call	printdec32
	printc 11, " proto "
	movzx	edx, word ptr [ebx + ecx + sock_proto]
	call	printdec32

	mov	eax, [ebx + ecx + sock_in_buffer]
	or	eax, eax
	jz	1f
	printc 11, " inlen "
	mov	edx, [eax + buffer_index]
	sub	edx, [eax + buffer_start]
	call	printdec32
1:	call	newline
2:	ARRAY_ENDL
9:	ret

# in: eax = socket
socket_print:
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	eax
	push	edx
	push	ebx
	mov	ebx, [socket_array]
	add	ebx, eax

#	mov	eax, [ebx + sock_remote_addr]
#	call	net_print_ip
#	print_ ':'
#	mov	edx, [ebx + sock_remote_port]
#	call	printdec32

#	mov	ax, 8<<8 | '-'
#	call	printcharc
#	mov	al, '>'
#	call	printcharc

	mov	eax, [ebx + sock_addr]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [ebx + sock_port]
	call	printdec32
	pop	ebx
	pop	edx
	pop	eax
	ret

socket_get_lport:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	mov	edx, [socket_array]
	movzx	edx, word ptr [edx + eax + sock_port]
	or	edx, edx
	jnz	8f

1:	push	ebx
	push	eax
	mov	ebx, [socket_array]
	cmp	word ptr [ebx + eax + sock_proto], IP_PROTOCOL_UDP
	jz	1f
	cmp	word ptr [ebx + eax + sock_proto], IP_PROTOCOL_TCP
	jz	2f
	pop	eax
	stc
	jmp	9f	# no change

1:	call	net_udp_port_get
	jmp	3f
2:	call	net_tcp_port_get
3:	movzx	edx, ax
	clc

	pop	eax
	mov	[ebx + eax + sock_port], dx
9:	pop	ebx
8:	MUTEX_UNLOCK_ SOCK
	ret


# Blocking read: waits for packet
#
# in: eax = socket index (as returned by socket_open)
# in: ecx = timeout in milliseconds
# out: esi, ecx
# out: CF = timeout.
socket_read:
	push	edx
	mov	edx, 1
	call	socket_buffer_read
	jc	9f
	mov	edx, [esi + buffer_start]
	call	socket_is_stream
	jnz	1f
0:	add	[esi + buffer_start], ecx
	add	esi, edx
	clc
9:	pop	edx
	ret

1:	# packet socket: adjust ecx, esi, buffer_start
		cmp	cx, [esi + edx]	# assert; assume ecx < 64k
		jbe	9f
1:	movzx	ecx, word ptr [esi + edx]
	add	[esi + buffer_start], dword ptr 2
	add	edx, 2
	jmp	0b

9:	printc 0x4f, "socket_read: packet queue corrupt: ecx="
	push	edx
	mov	edx, ecx
	call	printhex8
	pop	edx
	printc 0x4f, " packetlen="
	push	edx
	movzx	edx, word ptr [esi + edx]
	call	printhex8
	pop	edx
	int	3
	jmp	1b


# in: eax = socket index
# in: ecx = timeout in milliseconds
# in: edx = min bytes
# similar to socket_read, except the buffer_start is not updated (bytes not marked read).
socket_peek:
	call	socket_buffer_read
	jc	9f
	add	esi, [esi + buffer_start]
	call	socket_is_stream
	jnz	1f
0:	clc
9:	ret

1:	# packet socket: replace ecx with packet size, and adjust esi
		cmp	cx, [esi]	# assertion (assume ecx < 64k)
		jbe	9f
1:	movzx	ecx, word ptr [esi]
	add	esi, 2
	jmp	0b

9:	printlnc 0x4f, "socket_peek: packet buffer corrupt"
	int	3
	jmp	1b


# in: eax = socket
# out: ZF = 1: it's a streaming(tcp) socket; 0: it's a packet socket.
socket_is_stream:
	MUTEX_SPINLOCK_ SOCK
	push	eax
	add	eax, [socket_array]
	cmp	word ptr [eax + sock_proto], IP_PROTOCOL_TCP
	pop	eax
	MUTEX_UNLOCK_ SOCK
	ret

# in: eax = socket
# in: edx = min bytes
# out: esi = buffer (see buffer.s)
# out: ecx = available data
socket_buffer_read:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	edi
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx # SO_TIMEOUT: 10 seconds


0:	mov	edi, [socket_array]
	mov	esi, [edi + eax + sock_in_buffer]
	mov	ecx, [esi + buffer_index]
	mov	edi, [esi + buffer_start]
	MUTEX_UNLOCK_ SOCK
	sub	ecx, edi
#	jnbe	1f	# if edx is 0
	cmp	ecx, edx
	jnb	1f
	cmp	ebx, [clock_ms]
	jb	1f
	.if 0
		# doesn't work with ping...
		call	schedule_near
	.else
		sti
		hlt
	.endif
	MUTEX_SPINLOCK_ SOCK
	jmp	0b

1:	pop	ebx
	pop	edi
	MUTEX_UNLOCK_ SOCK
	ret

# in: eax = socket index
# in: esi = data
# in: ecx = data len
# out: esi = data not written
# out: ecx = datalen not written
# out: CF: 1: write fail (unsupported proto)
socket_write:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	eax
	add	eax, [socket_array]
	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_TCP
	jz	socket_write_tcp$
#	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_UDP
#	jz	socket_write_udp$

	stc
	jmp	9f
#socket_write_udp$:
#	mov	eax, [eax + sock_cust]
#	call	net_udp_sendbuf


socket_write_tcp$:
	mov	eax, [eax + sock_conn]	# tcp connection
	call	net_tcp_sendbuf

9:	pop	eax
	MUTEX_UNLOCK_ SOCK
	ret

# flushes pending writes
socket_flush:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	eax
	add	eax, [socket_array]
	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_TCP
	jnz	9f
	mov	eax, [eax + sock_conn]
	call	net_tcp_sendbuf_flush
9:	pop	eax
	MUTEX_UNLOCK_ SOCK
	ret

# TCP socket usage:
#
# registering a service:
# socket_open( 0.0.0.0, 80, IP_PROTOCOL_TCP | SOCK_LISTEN)
#   creates a socket entry in [socket_array]
#
# On an incoming tcp connection request, this array is scanned for matching ip,
# port, proto, and LISTEN (see net_socket_find).
# If such a socket exists, the tcp connection is accepted and a tcp_conn entry
# made in [tcp_connections]. 
# Next, net_sock_deliver_accept is called, creating a new socket in
# [peer_socket_array]. The sock_cust field of that socket is set to the server
# socket, and the sock_conn is set to the tcp connection.
# Next, the tcp_conn_sock is updated with the peer socket index.
#
# So:
#
# [socket_array] <- [peer_socket_array].sock_cust
# [tcp_connections] <- [peer_socket_array].sock_conn
# [peer_socket_array] <- [tcp_connections].tcp_conn_sock
# 
# NOTE: [peer_socket_array] is now a virtual array consisting of all sockets
# in [socket_array] that are peer sockets (SOCK_PEER flag).

# in: eax = server socket
# in: bx = port
# in: edx = peer ip
# in: ecx = connection
# out: edx = peer socket
# out: CF: socket_open error
net_sock_deliver_accept:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	ebx
	push	eax
	xchg	eax, edx
	add	edx, [socket_array]
	mov	dx, [edx + sock_proto]
	shl	edx, 16
	mov	dx, bx
	mov	ebx, SOCK_PEER | SOCK_ACCEPTABLE
	MUTEX_UNLOCK_ SOCK
	call	socket_open
	MUTEX_SPINLOCK_ SOCK
	mov	edx, eax
	pop	eax
	mov	ebx, [socket_array]
	mov	[ebx + edx + sock_cust], eax
	mov	[ebx + edx + sock_conn], ecx
	pop	ebx
	MUTEX_UNLOCK_ SOCK
	ret

# returns a new socket if a tcp connection is establised
# in: eax = local socket idx
# in: ecx = timeout
# out: edx = connected peer socket
# out: CF
socket_accept:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	esi
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx
	jmp	1f

0:	MUTEX_UNLOCK SOCK
	call	schedule_near
	MUTEX_SPINLOCK_ SOCK
1:	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, esi, edx, 9f
	test	[esi + edx + sock_flags], dword ptr SOCK_PEER
	jz	2f
	test	[esi + edx + sock_flags], dword ptr SOCK_ACCEPTABLE
	jz	2f
	cmp	[esi + edx + sock_cust], eax
	jz	1f
2:	ARRAY_ENDL
9:	cmp	ebx, [clock_ms]
	jnb	0b
	jmp	9f
1:	and	[esi + edx + sock_flags], dword ptr ~SOCK_ACCEPTABLE
#	DEBUG "!!! ACCEPT !!!"
	clc
9:	pop	ebx
	pop	esi
	MUTEX_UNLOCK_ SOCK
	ret


#in: esi, ecx
net_sock_deliver_icmp:
	push	eax
	push	edx
	mov	eax, [esi - IPV4_HEADER_SIZE + ipv4_dst]
	mov	edx, IP_PROTOCOL_ICMP << 16	# no port for icmp
	call	net_socket_deliver
	pop	edx
	pop	eax
	ret

# in: ebx = ipv4 frame
# in: eax = ip
# in: edx = [proto] [port]
# in: esi = udp payload
# in: ecx = udp payload len
net_socket_deliver_udp:
	MUTEX_SPINLOCK_ SOCK
	push	edx
	push	eax
	call	net_socket_find_
	jc	9f
	# got a local socket

	mov	eax, edx
	mov	edx, [socket_array]

	# if the UDP is a LISTEN, we support accepting connections.
	test	[edx + eax + sock_flags], dword ptr SOCK_LISTEN
	jz	1f	# nope, just deliver the data.
######### trigger a connect event

	# UNTESTED:

	# find the peer socket:
	mov	ebx, [ebx + ipv4_src]	# in: eax = ip
	xchg	eax, ebx		# in: eax = ip ; backup server socked in ebx
	mov	edx, IP_PROTOCOL_UDP	# in: edx = [proto] [port]
	mov	dx, [esi - UDP_HEADER_SIZE + udp_sport]
	call	net_socket_find_	# out: edx
	jnc	2f
	# create peer socket:
	mov	edx, eax	# in: edx = peer ip
	mov	eax, ebx	# in: eax = server socket
	mov	bx, [esi - UDP_HEADER_SIZE + udp_sport] # in: bx = port
	push	ecx
	xor	ecx, ecx	# in: ecx = connection (unused for udp)
	MUTEX_UNLOCK_ SOCK
	call	net_sock_deliver_accept # out: edx = peer socket
	MUTEX_SPINLOCK_ SOCK
	pop	ecx
	jnc	2f
	printc 4, "net_socket_deliver_udp: error opening peer socket"
	jmp	0f

2:	# edx = peer socket index
	add	edx, [socket_array]
	mov	eax, [edx + sock_in_buffer]
	# packet oriented socket, but do not write socket address:
	mov	edx, ecx
	jmp	2f

######### packet oriented socket: write in local (!SOCK_LISTEN) or peer socket
1:	test	dword ptr [edx + eax + sock_flags], SOCK_READPEER
	mov	eax, [edx + eax + sock_in_buffer]
	mov	edx, ecx
	jz	2f

	add	edx, 6	# 6 bytes for ip and port
	call	buffer_put_word	# write packet length
	mov	edx, [ebx + ipv4_src]
	call	buffer_put_dword
	mov	dx, [esi - UDP_HEADER_SIZE + udp_sport]
2:	call	buffer_put_word
	call	buffer_write
########
0:
	MUTEX_UNLOCK_ SOCK
	pop	eax
	pop	edx
	ret

9:	printc 4, "udp: packet dropped - no socket"
	jmp	0b

# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
net_socket_find:
	MUTEX_SPINLOCK_ SOCK
	call	net_socket_find_
	MUTEX_UNLOCK_ SOCK
	ret

# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
net_socket_find_:
	push	edi
	push	ebx
	push	ebp
	mov	ebx, edx
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, edi, edx, 9f
	mov	ebp, [edi + edx + sock_addr]
	or	ebp, ebp
	jz	1f
	cmp	ebp, -1
	jz	1f
	cmp	ebp, eax
	jnz	3f
1:	cmp	[edi + edx + sock_port], ebx	# compare proto and port
	jz	1f
3:	ARRAY_ENDL
9:	stc
1:	pop	ebp
	pop	ebx
	pop	edi
	ret

# in: eax = ip
# in: edx = [proto] [port]
# in: esi, ecx: packet
net_socket_deliver:
	MUTEX_SPINLOCK_ SOCK
	push	edi
	push	ebx
	push	ebp

	.if NET_SOCKET_DEBUG > 1
		DEBUG "net_socket_deliver:"
		call net_print_ip
		printchar ':'
		push edx;movzx edx, dx; call printdec32;pop edx;
		push edx;shr edx, 16;DEBUG_WORD dx,"proto";pop edx
		call newline
	.endif

	.if 1
	call	net_socket_find_
	jz	2f
	.else
		ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, ebx, edi, 9f
		mov	ebp, [ebx + edi + sock_addr]
		or	ebp, ebp
		jz	1f
		cmp	ebp, -1
		jz	1f
		cmp	ebp, eax
		jnz	3f
	1:	cmp	[ebx + edi + sock_port], edx	# compare proto and port
		jz	2f
	3:	ARRAY_ENDL
	9:;	.if NET_SOCKET_DEBUG > 1
			printc 4, "net_socket_deliver: no match"
		.endif
	.endif
0:	pop	ebp
	pop	ebx
	pop	edi
	MUTEX_UNLOCK_ SOCK
	ret
########
2:	# got a match
	push	eax
	mov	eax, [ebx + edi + sock_in_buffer]
	cmp	word ptr [ebx + edi + sock_proto], IP_PROTOCOL_TCP
	jz	1f
	# packet buffer: prepend packet size; assume ecx < 64k
	push	edx
	mov	edx, ecx
	call	buffer_put_word
	pop	edx
1:	call	buffer_write	# out: CF: data not appended. signal drop pkt.
	pop	eax
	jmp	0b

# in: eax = socket index
# in: esi = data
# in: ecx = datalen
net_socket_write:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	ebx
	push	eax
	mov	ebx, [socket_array]
	mov	eax, [ebx + eax + sock_in_buffer]
	call	buffer_write
	pop	eax
	pop	ebx
	MUTEX_UNLOCK_ SOCK
	ret

