
###########################################################################
# UDP
.struct 0
udp_sport:	.word 0
udp_dport:	.word 0
udp_len:	.word 0
udp_checksum:	.word 0
UDP_HEADER_SIZE = .
.text32
# in: edi = udp frame pointer
# in: eax = sport/dport
# in: cx = len
net_udp_header_put:
	push	eax

	bswap	eax
	stosd

	mov	ax, cx
	add	ax, UDP_HEADER_SIZE
	xchg	al, ah
	stosw	# udp frame size
	xor	ax, ax
	stosw	# checksum

	pop	eax
	ret

# in: eax = ipv4 dest addr
# in: edx = dport << 16 | sport
# in: ecx = udp payload size (without udp headers)
# out: CF = 1: no MAC for dest ip/gateway
net_put_eth_ipv4_udp_headers:
	# ETH, IP frame
	add	ecx, UDP_HEADER_SIZE
	push	edx
	mov	dx, IP_PROTOCOL_UDP
	call	net_ipv4_header_put
	pop	edx
	jc	9f

	# UDP frame

	push	eax
	mov	eax, edx
	bswap	eax
	ror	eax, 16
	sub	ecx, UDP_HEADER_SIZE
	call	net_udp_header_put
	clc
	pop	eax
9:	ret


# in: eax = source ip
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

	# deal with odd length:
	mov	word ptr [esi + ecx], 0	# just in case
	inc	ecx
	shr	ecx, 1

1:	mov	edi, offset udp_checksum	#
	call	protocol_checksum_

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
		# in: eax = ip
		# in: edx = [proto] [port]
		# in: esi, ecx: packet
		push	edx
		mov	eax, [edx + ipv4_dst]
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
9:	printc 4, "ipv4_udp["
	push	eax
	mov	eax, [edx + ipv4_src]
	call	net_print_ip
	printchar_ ':'
	pop	eax
	push	edx
	movzx	edx, word ptr [esi + udp_dport]
	xchg	dl, dh
	call	printdec32
	pop	edx
	printc 4, "]: dropped packet: "
	push	esi
	mov	esi, eax
	call	println
	pop	esi
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

