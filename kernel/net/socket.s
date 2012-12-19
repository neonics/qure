

#############################################################################
# Sockets
#
# Only AF_INET supported.
SOCK_LISTEN	= 0x80000000
SOCK_PEER	= 0x40000000
SOCK_ACCEPTABLE	= 0x20000000
.struct 0
sock_addr:	.long 0
sock_port:	.word 0
sock_proto:	.word 0
sock_flags:	.long 0
sock_in:	.long 0	# updated by net_rx_packet's packet handlers if
sock_inlen:	.long 0 # the ip, port and proto match.
sock_data:	.long 0	# custom data depending on socket (sock idx)
sock_conn:	.long 0 # custom connection information (tcp_conn idx)
SOCK_STRUCT_SIZE = .
.data SECTION_DATA_BSS
socket_array: .long 0
.text32
# in: eax = sock_addr (ip)
# in: edx = sock_proto << 16 | sock_port
# in: ebx = flags (SOCK_LISTEN)
# out: eax = socket index
socket_open:
	push	edi
	push	edx
	push	esi
	push	ecx
	mov	esi, eax	# ip
	mov	edi, edx	# proto, port
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + sock_port], dword ptr -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [socket_array], SOCK_STRUCT_SIZE, 4, 9f
1:	mov	[eax + edx + sock_addr], esi
	mov	[eax + edx + sock_port], edi
	mov	[eax + edx + sock_flags], ebx
	mov	eax, edx
9:	pop	ecx
	pop	esi
	pop	edx
	pop	edi
	ret

socket_close:
	push	edx
	mov	edx, [socket_array]
		cmp	eax, [edx + array_index]
		ja	9f
	mov	[edx + eax + sock_port], dword ptr -1
	mov	[edx + eax + sock_data], dword ptr -1
	mov	[edx + eax + sock_conn], dword ptr -1
	add	eax, SOCK_STRUCT_SIZE
	cmp	eax, [edx + array_index]
	jnz	1f
	sub	[edx + array_index], dword ptr SOCK_STRUCT_SIZE
1:	pop	edx
	ret
9:	printc 12, "invalid socket: "
	mov	edx, eax
	call	printhex8
	call	newline
	pop	edx
	stc
	ret


socket_list:
	mov	esi, [socket_array]
	
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, ebx, ecx, 9f
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
	printc 11, " inlen "
	mov	edx, [ebx + ecx + sock_inlen]
	call	printdec32
	call	newline
	ARRAY_ENDL
9:	ret

# in: eax = socket
socket_print:
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
	mov	edx, [socket_array]
	movzx	edx, word ptr [edx + eax + sock_port]
	or	edx, edx
	jz	1f
	ret

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
	ret

# Blocking read: waits for packet
#
# in: eax = socket index (as returned by socket_open)
# in: ecx = timeout in milliseconds
# out: esi, ecx
# out: CF = timeout.
socket_read:
	push	edx
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx # SO_TIMEOUT: 10 seconds
0:	mov	edx, [socket_array]
	xor	esi, esi
	xor	ecx, ecx
	xchg	esi, [edx + eax + sock_in]
	xchg	ecx, [edx + eax + sock_inlen]
#DEBUG "socket_read"
#DEBUG_DWORD eax,"sock"
#add edx, eax
#DEBUG_DWORD edx
#DEBUG_DWORD ecx
#call newline
	or	ecx, ecx	# clears CF
	jnz	1f
	cmp	ebx, [clock_ms]
	jb	1f
	.if 1
		call	schedule_near
	.else
		sti
		hlt
	.endif
	jmp	0b

1:	pop	ebx
	pop	edx
	ret

# in: eax = socket index
# in: esi = data
# in: ecx = data len
# out: esi = data not written
# out: ecx = datalen not written
# out: CF: 1: write fail (unsupported proto)
socket_write:
	push	eax
	add	eax, [socket_array]
	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_TCP
	jz	socket_write_tcp$
#	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_UDP
#	jz	socket_write_udp$

	stc
	jmp	9f
#socket_write_udp$:
#	mov	eax, [eax + sock_data]
#	call	net_udp_sendbuf

	
socket_write_tcp$:
	mov	eax, [eax + sock_conn]	# tcp connection
	call	net_tcp_sendbuf

9:	pop	eax
	ret

# flushes pending writes
socket_flush:
	push	eax
	add	eax, [socket_array]
	cmp	byte ptr [eax + sock_proto], IP_PROTOCOL_TCP
	jnz	9f
	mov	eax, [eax + sock_conn]
	call	net_tcp_sendbuf_flush
9:	pop	eax
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
# [peer_socket_array]. The sock_data field of that socket is set to the server
# socket, and the sock_conn is set to the tcp connection.
# Next, the tcp_conn_sock is updated with the peer socket index.
#
# So:
#
# [socket_array] <- [peer_socket_array].sock_data
# [tcp_connections] <- [peer_socket_array].sock_conn
# [peer_socket_array] <- [tcp_connections].tcp_conn_sock
# 
# NOTE: [peer_socket_array] is now a virtual array consisting of all sockets
# in [socket_array] that are peer sockets (SOCK_PEER flag).

#
# in: eax = local socket
# in: edx = peer ip
# in: ebx = peer port (high 16 bit 0)
# in: ecx = flags
# in: [socket_array][eax].sock_proto will be copied
# out: edx = peer socket index
# side effect: set peer socket's data to local socket index
peer_socket_open:
	push	edi
	push	esi
	push	ecx
	mov	esi, eax	# local socket
	mov	edi, edx	# peer ip
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + sock_port], dword ptr -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [socket_array], SOCK_STRUCT_SIZE, 4, 9f
	mov	ecx, [esp]
1:	mov	[eax + edx + sock_addr], edi
	mov	[eax + edx + sock_data], esi
	mov	[eax + edx + sock_port], ebx
	mov	[eax + edx + sock_flags], ecx
	mov	ebx, [socket_array]
	mov	bx, [ebx + esi + sock_proto]
	mov	[eax + edx + sock_proto], bx

	mov	eax, esi	# restore
	mov	edx, edi	# restore
0:	pop	ecx	# changed by ARRAY_NEWENTRY
	pop	esi
	pop	edi
	ret

# in: eax = server socket
# in: bx = port
# in: edx = peer ip
# in: ecx = connection
# out: edx = peer socket
net_sock_deliver_accept:
	push	ebx
	push	eax
	xchg	eax, edx
	add	edx, [socket_array]
	mov	dx, [edx + sock_proto]
	shl	edx, 16
	mov	dx, bx
	mov	ebx, SOCK_PEER | SOCK_ACCEPTABLE
	call	socket_open
	mov	edx, eax
	pop	eax
	mov	ebx, [socket_array]
	mov	[ebx + edx + sock_data], eax
	mov	[ebx + edx + sock_conn], ecx
	pop	ebx
	ret

# returns a new socket if a tcp connection is establised
# in: eax = locak socket idx
# in: ecx = timeout
# out: edx = connected peer socket
# out: CF
socket_accept:
	push	esi
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx
	jmp	1f

0:	call	schedule_near
1:	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, esi, edx, 9f
	test	[esi + edx + sock_flags], dword ptr SOCK_PEER
	jz	2f
	test	[esi + edx + sock_flags], dword ptr SOCK_ACCEPTABLE
	jz	2f
	cmp	[esi + edx + sock_data], eax
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

# in: eax = ip
# in: edx = [proto] [port]
# out: edx = socket idx
net_socket_find:
#DEBUG "find socket:"
#call net_print_ip
#printchar ':'
#push edx
#movzx edx, dx
#call printdec32
#pop edx
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
	push	edi
	push	ebx
	push	ebp
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
9:	pop	ebp
	pop	ebx
	pop	edi
	ret
########
2:	# got a match
	# TODO: copy packet (though that should've been done in net_rx_packet).
	mov	[ebx + edi + sock_in], esi
	mov	[ebx + edi + sock_inlen], ecx
	jmp	9b

net_socket_write:
	# TODO: copy/append
	push	eax
#DEBUG "net_socket_write"
#DEBUG_DWORD eax,"sock"
	add	eax, [socket_array]
#DEBUG_DWORD eax, "net_socket_write:"
#DEBUG_DWORD ecx,"len"
	mov	[eax + sock_in], esi
	mov	[eax + sock_inlen], ecx
	pop	eax
	ret

