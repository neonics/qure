#############################################################################
# Sockets
#
# Only AF_INET supported.


NET_SOCKET_DEBUG = 0

SOCKET_BUFSIZE	= 2048

# socket options:
SOCK_LISTEN	= 0x80000000
SOCK_STREAM	= 0x40000000	# 1: continuous buffer; 0: packetized buffer
# address family:
SOCK_AF_MASK	= 0x0000000f
SOCK_AF_IP	= 0x00000000	# backwards compat
SOCK_AF_ETH	= 0x00000001	
# NOTE: gnored: the above option is automatically determined based on IP_PROTOCOL_TCP.
# options affecting socket packetized read/peek contents (i.e. deliver)
# READPEER: the ordering will be as listed here:
SOCK_READPEER	= 0x08000000 	# prepend packetized data with peer address (ip:port)
SOCK_READPEER_MAC=0x04000000 	# prepend packetized data with peer MAC
SOCK_READTTL	= 0x02000000	# prepend IP ttl (after peer)
SOCK_READTTL_SHIFT = (24+1)

# internal flags
SOCK_PEER	= 0x00400000	# socket is 'forked' from SOCK_LISTEN on rx SYN
SOCK_ACCEPTABLE	= 0x00200000
SOCK_CLOSED	= 0x00100000
.struct 0
sock_addr:	.long 0
sock_port:	.word 0
sock_proto:	.word 0 # flags & SOCK_AF_ETH ? ETH_PROTO_* : IP_PROTOCOL_*
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
# in: ebx = flags (SOCK_LISTEN, SOCK_AF)
# out: eax = socket index
# out: CF
KAPI_DECLARE socket_open
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
1:	
	mov	[eax + edx + sock_port], edi	# also sets proto
	mov	[eax + edx + sock_flags], ebx
	mov	edi, ebx
	and	edi, SOCK_AF_MASK
	jnz	1f	# not SOCK_AF_IP, skip addr
	mov	[eax + edx + sock_addr], esi
1:	mov	edi, eax

	.if NET_SOCKET_DEBUG
		DEBUG_DWORD edx, "socket_open "
		mov	eax, esi
		call	net_print_ip
		printchar_ ':'
		push	edi
		push	edx
		add	edi, edx
		movzx	edx, word ptr [edi + sock_port]
		call	printdec32
		DEBUG " proto "
		mov	dx, [edi + sock_proto]
		call	printhex4
		DEBUG " flags "
		mov	edx, [edi + sock_flags]
		call	printhex8
		pop	edx
		pop	edi
	.endif

	test	ebx, SOCK_LISTEN
	jnz	1f	# dont alloc buffer for server sockets.

	mov	eax, SOCKET_BUFSIZE
	call	buffer_new
	jc	91f
	mov	[edi + edx + sock_in_buffer], eax

	.if 1
		test	dword ptr [edi + edx + sock_flags], SOCK_PEER
		jnz	1f	# don't send SYN for peer sockets
		cmp	[edi + edx + sock_proto], word ptr IP_PROTOCOL_TCP
		jnz	1f
		# connect
		push	edx
		mov	eax, [edi + edx + sock_addr]
		movzx	edx, word ptr [edi + edx + sock_port]
		call	net_ipv4_tcp_connect
		pop	edx
		mov	[edi + edx + sock_conn], eax
	1:	clc
	.endif

1:	mov	eax, edx
9:	MUTEX_UNLOCK_ SOCK
	pop	ecx
	pop	esi
	pop	edx
	pop	edi
	.if NET_SOCKET_DEBUG
		DEBUG_DWORD eax,"SOCKET_OPEN_RETURN"
	.endif
	ret
91:	printlnc 4, "socket_open: out of memory"
	mov	[edi + edx + sock_port], dword ptr -1	# mark available
	mov	eax, -1
	stc
	jmp	9b

KAPI_DECLARE socket_close
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
	cmp	eax, -1
	jz	22f
	call	net_tcp_fin
22:	pop	eax
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
KAPI_DECLARE socket_print	# not needed?
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

KAPI_DECLARE socket_get_lport
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
KAPI_DECLARE socket_read
socket_read:
	push	edx
	mov	edx, 1
	call	socket_buffer_read
	jc	9f
	mov	edx, [esi + buffer_start]
	call	socket_is_stream
	jnz	1f	# not tcp
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
KAPI_DECLARE socket_peek
socket_peek:
	call	socket_buffer_read
	jc	9f
	jecxz	9f	# if socket closed
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

.data SECTION_DATA_BSS
# we use a single sem for all buffers, because the socket array can be
# reallocated and this would invalidate any pointers to a field in a socket.
socket_buffer_sem:	.long 0
.text32

# in: eax = socket
# in: edx = min bytes
# [in: ecx = timeout]
# out: esi = buffer (see buffer.s)
# out: ecx = available data
socket_buffer_read:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	edi
	push	ebx
	mov	ebx, ecx	# SO_TIMEOUT in ms
	cmp	ecx, -1
	jz	0f		# do not adjust infinite time
	add	ebx, [clock_ms]

0:	mov	edi, [socket_array]
		xor	ecx, ecx
		test	dword ptr [edi + eax + sock_flags], SOCK_CLOSED
		jnz	61f
	mov	esi, [edi + eax + sock_in_buffer]
	mov	ecx, [esi + buffer_index]
	mov	edi, [esi + buffer_start]
	MUTEX_UNLOCK_ SOCK
	sub	ecx, edi
#	jnbe	1f	# if edx is 0
	cmp	ecx, edx
	jnb	1f		# min datasize satisfied

######### timeout handling
	# packets may arrive that fill the buffer, but may not provide enough
	# accumulated data to satisfy edx (min data).
	# Thus, YIELD_SEM may return several times before this method returns.
	cmp	ebx, [clock_ms]
	jb	2f
	mov	edi, ebx
	cmp	ebx, -1
	jz	3f		# infinite time (49 days)
	sub	edi, [clock_ms]	# time left in ms
3:	YIELD_SEM (offset socket_buffer_sem), edi
########
	MUTEX_SPINLOCK_ SOCK
	jmp	0b

1:	cmp	dword ptr [socket_buffer_sem], 0
	jbe	9f	# TODO FIXME - just in case. 2 appends can result in 1 read...
	lock dec dword ptr [socket_buffer_sem]
	clc
2:	pop	ebx
	pop	edi
	ret

9:	printlnc 4, "socket_buffer_sem < 0: "; DEBUG_DWORD [socket_buffer_sem]
	jmp	1b

61:	DEBUG "sock closed"
	MUTEX_UNLOCK_ SOCK
	jmp	1b

# in: eax = socket index
# in: esi = data
# in: ecx = data len
# out: esi = data not written
# out: ecx = datalen not written
# out: CF: 1: write fail (unsupported proto)
KAPI_DECLARE socket_write
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
#	jmp	9f


socket_write_tcp$:
	mov	eax, [eax + sock_conn]	# tcp connection
	call	net_tcp_sendbuf

9:	pop	eax
	MUTEX_UNLOCK_ SOCK
	ret

# flushes pending writes
KAPI_DECLARE socket_flush
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

# a TCP socket is closed remotely: signal any pending readers.
# in: edx = socket index
net_socket_deliver_close:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX edx, [socket_array], SOCK_STRUCT_SIZE
	push	edx
	add	edx, [socket_array]
	cmp	[edx + sock_port], dword ptr -1
	jz	9f	# skip, already closed
	or	dword ptr [edx + sock_flags], SOCK_CLOSED
	pop	edx
	lock inc dword ptr [socket_buffer_sem]
9:	MUTEX_UNLOCK_ SOCK
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

.data SECTION_DATA_BSS
sock_accept_sem: .long 0
.text32

# in: eax = server socket
# in: bx = port
# in: edx = peer ip
# in: ecx = connection
# out: edx = peer socket
# out: CF: socket_open error
net_sock_deliver_accept:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	.if NET_SOCKET_DEBUG
		DEBUG "SOCK DELIVER ACCEPT"
	.endif
	push	ebx
	push	eax
	xchg	eax, edx
	add	edx, [socket_array]
	push	dword ptr [edx + sock_flags]
	mov	dx, [edx + sock_proto]
	shl	edx, 16
	mov	dx, bx
	pop	ebx	# flags
	and	ebx, ~SOCK_LISTEN
	or	ebx, SOCK_PEER | SOCK_ACCEPTABLE
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
	lock inc dword ptr [sock_accept_sem] # notify scheduler
	ret

# returns a new socket if a tcp connection is establised
# in: eax = local socket idx
# in: ecx = timeout: 0: peek; any other value: block.
# out: edx = connected peer socket
# out: CF
KAPI_DECLARE socket_accept
socket_accept:
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	esi
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx
	jmp	1f

0:	MUTEX_UNLOCK_ SOCK

	YIELD_SEM (offset sock_accept_sem)

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
	lock dec dword ptr [sock_accept_sem]
#	DEBUG "!!! ACCEPT !!!"
	clc
9:	pop	ebx
	pop	esi
	MUTEX_UNLOCK_ SOCK
	ret


# in: esi, ecx: icmp frame
# in: edx = ipv4 frame
net_sock_deliver_icmp:
	push	eax
	push	edx
	mov	eax, [edx + ipv4_dst]
	mov	edx, IP_PROTOCOL_ICMP << 16	# no port for icmp
#	call	net_socket_deliver
	MUTEX_SPINLOCK_ SOCK
	call	net_socket_find_	# out: edx
	jc	9f

	mov	eax, edx	# in: eax = socket index
	mov	ebx, [esp]	# in: ebx = ipv4 frame
	xor	edx, edx	# in: dx = [port]
	call	net_socket_in_append$ # in: esi = payload; ecx = payload len

9:	MUTEX_UNLOCK_ SOCK
	pop	edx
	pop	eax
	ret


# in: dx = ETH_PROTO_*
# in: esi, ecx: raw packet
net_sock_deliver_raw:
	push	eax
	push	edx
	MUTEX_SPINLOCK_ SOCK
	# in: dx = proto
	call	net_socket_find_af_eth_	# out: edx
	jc	9f

	mov	eax, edx	# in: eax = socket index
	mov	ebx, -1		# in: ebx = ipv4 frame (N/A for ARP)
	xor	edx, edx	# in: dx = [port] (N/A for ARP)
	call	net_socket_in_append$ # in: esi = payload; ecx = payload len

9:	MUTEX_UNLOCK_ SOCK
	pop	edx
	pop	eax
	ret

#
# in: ebx = ipv4 frame
# in: eax = ip
# in: edx = [proto] [port]
# in: esi = udp payload
# in: ecx = udp payload len
net_socket_deliver_udp:
	MUTEX_SPINLOCK_ SOCK
	push	edx
	push	ebx
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
	mov	edx, [esp + 8]		# in: edx = [proto] [port]
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
	##mov	eax, [socket_array]
	##add	eax, edx
	mov	eax, edx
######### packet oriented socket: write in local (!SOCK_LISTEN) or peer socket
1:	mov	ebx, [esp + 4]				# in : ebx = ip frame
	mov	dx, [esi - UDP_HEADER_SIZE + udp_sport]	# in: dx = port
	call	net_socket_in_append$	# in: eax=sock,esi,ecx
########
0:
	MUTEX_UNLOCK_ SOCK
	pop	eax
	pop	ebx
	pop	edx
	ret

9:	#printc 4, "udp: packet dropped - no socket"
	jmp	0b

# precondition: [socket_array] locked
# in: eax = socket index
# in: esi = payload
# in: ecx = payload len
#OPTIONAL: only for IP sockets:
# in: ebx = ipv4 frame (preceeded by ethernet frame)
# in: edx = [dest port] [peer port]
net_socket_in_append$:
	.if NET_SOCKET_DEBUG
		DEBUG_DWORD eax, "SOCK IN APPEND"
	.endif
	push	edi
	push	eax
	push	edx
	mov	edi, [socket_array]
	add	edi, eax

	mov	eax, [edi + sock_in_buffer]
	or	eax, eax
	jz	9f
	mov	edi, [edi + sock_flags]
	test	edi, SOCK_STREAM
	jnz	2f

	# check if SOCK_READPEER makes sense (only for IP)
	mov	edx, edi
	and	dl, SOCK_AF_MASK
	cmp	dl, SOCK_AF_IP

	# write packetized len
	mov	edx, ecx

	jnz	3f	# not IP, don't write peer/ttl

	test	edi, SOCK_READPEER
	jz	1f
	add	edx, 12
1:	test	edi, SOCK_READPEER_MAC
	jz	1f
	add	edx, 6
1:	bt	edi, SOCK_READTTL_SHIFT
	adc	edx, 0
3:	call	buffer_put_word

	# write peer address
	test	edi, SOCK_READPEER
	jz	1f
	mov	edx, [ebx + ipv4_src]
	call	buffer_put_dword
	mov	dx, [esp]	# port
	call	buffer_put_word
	mov	edx, [ebx + ipv4_dst]
	call	buffer_put_dword
	mov	edx, [esp+2]
	call	buffer_put_word

1:	test	edi, SOCK_READPEER_MAC
	jz	1f
	mov	edx, [ebx - ETH_HEADER_SIZE + eth_src]
	call	buffer_put_dword
	mov	edx, [ebx - ETH_HEADER_SIZE + eth_src + 4]
	call	buffer_put_word

1:	# write ttl
	test	edi, SOCK_READTTL
	jz	1f
	mov	dl, [ebx + ipv4_ttl]
	call	buffer_put_byte
1:
	# write payload
2:	call	buffer_write
	lock inc dword ptr [socket_buffer_sem]

0:	pop	edx
	pop	eax
	pop	edi
	ret

9:	printc 4, "net_socket_in_append$: no buffer: "
	mov	eax, [esp + 4]
	call	socket_print
	call	newline
	jmp	0b

# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
net_socket_find:
	MUTEX_SPINLOCK_ SOCK
	call	net_socket_find_
	MUTEX_UNLOCK_ SOCK
	ret

# precondition: MUTEX_SOCK locked
#
# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
# out: CF = 0: found 1: not found
net_socket_find_:
	push	edi
	push	ebx
	push	ebp
	mov	ebx, edx
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, edi, edx, 9f
	test	byte ptr [edi + edx + sock_flags], SOCK_AF_MASK
	jnz	3f	# address family not 0 (INET - IPV4)
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

# precondition: MUTEX_SOCK locked
#
# in: dx = ETH_PROTO_*
# out: edx = socket idx
# out: CF = 0: found 1: not found
net_socket_find_af_eth_:
	push	edi
	push	ebx
	push	ebp
	mov	ebx, edx
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, edi, edx, 9f
	mov	ebp, [edi + edx + sock_flags]
	and	ebp, SOCK_AF_MASK
	cmp	ebp, SOCK_AF_ETH
	jnz	3f
	cmp	[edi + edx + sock_proto], bx
	jz	1f
3:	ARRAY_ENDL
9:	stc
1:	pop	ebp
	pop	ebx
	pop	edi
	ret



# These two are used for incoming data in TCP

# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
net_socket_find_remote:
	MUTEX_SPINLOCK_ SOCK
	call	net_socket_find_remote_
	MUTEX_UNLOCK_ SOCK
	ret

# in: eax = remote ip
# in: edx = [proto] [port]
# out: edx = socket idx
# out: CF = 0: found 1: not found
net_socket_find_remote_:
	push	edi
	push	ebx
	push	ebp
	mov	ebx, edx
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, edi, edx, 9f
	mov	ebp, [edi + edx + sock_addr]
	# don't check for 0, must have exact match
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
DEBUG "SOCK DELIVER"
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

	call	net_socket_find_
	jnc	2f
	.if NET_SOCKET_DEBUG > 1
		printc 4, "net_socket_deliver: no match"
	.endif
0:	pop	ebp
	pop	ebx
	pop	edi
	MUTEX_UNLOCK_ SOCK
	ret
########
2:	mov	eax, edx
	call	net_socket_in_append$
	jmp	0b

# in: eax = socket index
# in: esi = data
# in: ecx = datalen
net_socket_write:
	.if NET_SOCKET_DEBUG
		DEBUG_DWORD eax, "SOCK WRITE"
	.endif
	MUTEX_SPINLOCK_ SOCK
	ASSERT_ARRAY_IDX eax, [socket_array], SOCK_STRUCT_SIZE
	push	ebx
	push	eax
	mov	ebx, [socket_array]
	mov	eax, [ebx + eax + sock_in_buffer]
	or	eax, eax
	jz	9f
	call	buffer_write
	lock inc dword ptr [socket_buffer_sem]
0:	pop	eax
	pop	ebx
	MUTEX_UNLOCK_ SOCK
	ret
9:	printc 4, "net_socket_write: in_buffer null for socket "
	push edx; mov edx, [esp +4]; call printhex8; pop edx;
	call newline
	jmp	0b

