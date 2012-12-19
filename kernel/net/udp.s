###########################################################################
# UDP

UDP_LOG = 0	# 1: print dropped packets

.struct 0
udp_sport:	.word 0
udp_dport:	.word 0
udp_len:	.word 0
udp_checksum:	.word 0
UDP_HEADER_SIZE = .
.text32
# in: edi = udp frame pointer
# in: eax = sport/dport
# in: cx = udp payload len (without header size)
net_udp_header_put:
	push	eax

	bswap	eax
	stosd

	mov	ax, cx
	add	ax, UDP_HEADER_SIZE
.if 1
	shl	eax, 16
	bswap	eax
	stosd
.else
	xchg	al, ah
	stosw	# udp frame size
	xor	ax, ax
	stosw	# checksum
.endif
	pop	eax
	ret

# Stores ethernet, ip and udp headers before the payload and calculates the
# udp checksum. The caller should prepare the payload, and then have edi
# decremented to make room for the protocol headers before it.
#
# in: edi = packet start
# in: eax = ipv4 dest addr
# in: edx = dport << 16 | sport
# in: ecx = udp payload size (without udp headers)
# in: edi+ETH_HEADER_SIZE+IPV4_HEADER_SIZE+UDP_HEADER_SIZE = payload start
# out: ebx = nic
# out: edi = end of headers
# out: CF = 1: no MAC for dest ip/gateway
net_put_eth_ipv4_udp_headers:
	push	ecx
	push	esi
	push	edx

	# ETH, IP frame
	add	ecx, UDP_HEADER_SIZE
	mov	dx, IP_PROTOCOL_UDP
	# in: edi = out packet
	# in: dl = ipv4 sub-protocol
	# in: dh = bit 0: 0=use nic ip; 1=use 0 ip; bit 1: 1=edx>>16&255=ttl
	# in: eax = destination ip
	# in: ecx = payload length (without ethernet/ip frame)
	# in: ebx = nic - ONLY if eax = -1!
	# in: esi = mac - ONLY if eax = -1!
	# out: edi = points to end of ethernet+ipv4 frames in packet
	# out: ebx = nic object (for src mac & ip) [calculated from eax]
	# out: esi = destination mac [calculated from eax]
	push	edi	# remember eth frame start
	call	net_ipv4_header_put
	pop	edx	# edx = eth frame
	jc	9f

	# UDP frame

	push	eax
	mov	eax, [esp + 4]	# edx: ports
	bswap	eax
	ror	eax, 16			# in: eax = sport | dport
	sub	ecx, UDP_HEADER_SIZE	# in: ecx = udp payload len
	mov	esi, edi		# remember udp frame start
	call	net_udp_header_put
	add	ecx, UDP_HEADER_SIZE
.if 1
	mov	eax, [edx + ETH_HEADER_SIZE + ipv4_src]
	mov	edx, [edx + ETH_HEADER_SIZE + ipv4_dst]
	call	net_udp_checksum
.else
	push	edi
	add	edx, offset ipv4_src + ETH_HEADER_SIZE # in: edx = ipv4 src,dst
	mov	eax, IP_PROTOCOL_UDP
	mov	edi, offset udp_checksum
	call	net_ip_pseudo_checksum
	pop	edi
.endif

	clc
	pop	eax

9:	pop	esi
	pop	ecx
	pop	edx
	ret

# in: eax = src ip
# in: edx = dest ip
# in: esi = udp frame pointer
# in: ecx = udp frame len (header and data)
net_udp_checksum:
	push	esi
	push	edi
	push	edx
	push	ecx
	push	eax
	# calculate tcp pseudo header:
	# dd ipv4_src
	# dd ipv4_src
	# db 0, protocol	# dw 0x0600 # protocol
	# dw headerlen+datalen

	# add ip addresses:
	add	edx, eax
	adc	edx, 0
	movzx	eax, dx
	shr	edx, 16
	add	edx, eax
	add	edx, IP_PROTOCOL_UDP << 8 # protocol + zeroes

	#xchg	cl, ch		# headerlen + datalen
	shl	ecx, 8	# hmmm
	add	edx, ecx
	shr	ecx, 8

	mov	edi, offset udp_checksum	#
	call	protocol_checksum_	# in: ecx=len, esi=start,esi+edi=cksum

	pop	eax
	pop	ecx
	pop	edx
	pop	edi
	pop	esi
	ret





net_ipv4_udp_print:
	cmp	ecx, UDP_HEADER_SIZE
	jbe	9f
	print	"UDP "
	print	"sport "
	xor	edx, edx
	mov	dx, [esi + udp_sport]
	xchg	dl, dh
	.if 1
		call	printhex4
		print	" ("
		call	printdec32
		print	") dport "
	.else
		call	printdec32
		print	" dport "
	.endif

	mov	dx, [esi + udp_dport]
	xchg	dl, dh
	.if 1
		call	printhex4
		print	" ("
		call	printdec32
		print	") len "
	.else
		call	printdec32
		print " len "
	.endif
	mov	dx, [esi + udp_len]
	xchg	dl, dh
	call	printhex4

	print	" checksum "
	mov	dx, [esi + udp_checksum]
	call	printhex4
	call	newline

	mov	eax, esi
	add	esi, UDP_HEADER_SIZE
	sub	ecx, UDP_HEADER_SIZE
	jle	0f	# jl shouldnt happen

	cmp	[eax + udp_sport], word ptr 53 << 8	# DNS
	jz	net_dns_print
	cmp	[eax + udp_sport], dword ptr ( (67 << 8) | (68 << 24))
	jz	net_dhcp_print
	cmp	[eax + udp_sport], dword ptr ( (68 << 8) | (67 << 24))
	jz	net_dhcp_print

0:	ret

9:	printlnc 4, "udp: short packet"
	ret
# XXX keep with next!


# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len (incl udp header)
ph_ipv4_udp:
	cmp	ecx, UDP_HEADER_SIZE
	jbe	9b	# XXX keep with prev!
.if 0	# verify checksum
	cmp	[esi + udp_checksum], word ptr 0
	jz	1f	# no checksum
	push	edx
	push	esi
	push	ecx
	.if 0
	sub	esi, 8	# point to ipv4 frame's src/dst ip's.
	xor	eax, eax
	mov	edx, ecx	# add length
	xchg	dl, dh
	add	edx, IP_PROTOCOL_UDP << 8
	.else
	mov	eax, [edx + ipv4_src]
	mov	edx, [edx + ipv4_dst]
	add	edx, eax
	adc	edx, 0
	movzx	eax, dx
	shr	edx, 16
	add	edx, eax
	mov	ax, cx
	xchg	al, ah
	add	edx, eax
	.endif
	add	edx, IP_PROTOCOL_UDP << 8
0:	lodsw
	add	edx, eax
	loop	0b
	pop	ecx
	pop	esi
	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	inc	ax
	LOAD_TXT "checksum error", eax
	pop	edx
	jnz	9f
1:
.endif

	mov	eax, [edx + ipv4_dst]
	cmp	eax, -1	# broadcast
	jz	2f
	mov	ebx, eax # multicast
	rol	ebx, 4
	and	bl, 0b1111
	cmp	bl, 0b1110
	jz	2f	# 244.0.0.0/4 match

	call	nic_get_by_ipv4
	jc	1f	# ret: no match
2:
		# in: eax = ip
		# in: edx = [proto] [port]
		# in: esi, ecx: packet
		push	edx
		mov	edx, IP_PROTOCOL_UDP << 16
		mov	dx, [esi + udp_dport]
		xchg	dl, dh
		push	ecx
		# esi: udp frame
		sub	ecx, UDP_HEADER_SIZE
		call	net_socket_deliver
		pop	ecx
		pop	edx

	# call handler

	mov	eax, esi	# udp frame
	add	esi, UDP_HEADER_SIZE
	sub	ecx, UDP_HEADER_SIZE

	cmp	[eax + udp_sport], word ptr 53 << 8	# DNS
	jz	1f	#net_dns_print
	cmp	[eax + udp_dport], word ptr 53 << 8	# DNS
	jz	net_dns_service
	cmp	[eax + udp_sport], dword ptr ( (67 << 8) | (68 << 24))
	jz	ph_ipv4_udp_dhcp_s2c
	cmp	[eax + udp_sport], dword ptr ( (68 << 8) | (67 << 24))
	jz	ph_ipv4_udp_dhcp_c2s

	mov	esi, eax	# restore udp frame for error message below

	LOAD_TXT "unknown port", eax
9:	.if UDP_LOG
	printc 4, "ipv4_udp["
	call	net_print_ip_pair
	printc 4, "]: dropped packet: "
	push	esi
	mov	esi, eax
	call	println
	pop	esi
	.endif
1:	ret

net_udp_port_get:
	.data
	UDP_FIRST_PORT = 48000
	udp_port_counter: .word UDP_FIRST_PORT
	.text32
	mov	ax, [udp_port_counter]
	push	eax
	inc	ax
	cmp	ax, 0xff00
	jb	0f
	mov	ax, UDP_FIRST_PORT
0:	mov	[udp_port_counter], ax
	pop	eax
	ret

