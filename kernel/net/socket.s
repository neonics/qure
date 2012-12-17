

#############################################################################
# Sockets
SOCK_LISTEN = 0x80000000
.struct 0
sock_addr:	.long 0
sock_port:	.word 0
sock_proto:	.word 0	# and SOCK flags.
sock_in:	.long 0	# updated by net_rx_packet's packet handlers if
sock_inlen:	.long 0 # the ip, port and proto match.
SOCK_STRUCT_SIZE = .
.data SECTION_DATA_BSS
socket_array: .long 0
.text32
# in: eax = ip
# in: ebx = [SOCK_LISTEN] | [proto << 16] | [port]
# out: eax = socket index
socket_open:
	push	edx
	push	esi
	push	ecx
	mov	esi, eax	# ip
	ARRAY_LOOP [socket_array], SOCK_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + sock_port], dword ptr -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [socket_array], SOCK_STRUCT_SIZE, 4, 9f
1:	mov	[eax + edx + sock_addr], esi
	mov	[eax + edx + sock_port], ebx
	mov	eax, edx
9:	pop	ecx
	pop	esi
	pop	edx
	ret

socket_close:
	push	edx
	mov	edx, [socket_array]
		cmp	eax, [edx + array_index]
		ja	9f
	mov	[edx + eax + sock_port], dword ptr -1
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

socket_get_lport:
	mov	edx, [socket_array]
	movzx	edx, word ptr [edx + sock_port]
	or	edx, edx
	jz	1f
	ret

1:	push	ebx
	push	eax
	mov	ebx, [socket_array]
	cmp	word ptr [edx + sock_proto], IP_PROTOCOL_UDP
	jz	1f
	cmp	word ptr [edx + sock_proto], IP_PROTOCOL_TCP
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

# returns a new socket if a tcp connection is establised
# in: eax = socket idx
# in: ecx = timeout
# out: edx = connected socket
# out: CF
socket_accept:
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx

	ARRAY_LOOP [tcp_connections], TCP_CONN_STRUCT_SIZE, esi, edx
# TODO
#	test	[esi + edx + tcp_flags], 
	ARRAY_ENDL

	pop	ebx
	stc
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


