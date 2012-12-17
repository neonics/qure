
##############################################################################
# IPv4
.struct 0	# offset 14 in ethernet frame
ipv4_header:
ipv4_v_hlen: .byte 0 # .byte (4<<4) | 5
# lo = header len (4 byte/32 bit units), hi = version
ipv4_dscp: .byte 0
# TOS - type of service/dscp differentiated services code point
# DSCP: 76 = ECN - explicit congestion notification
#       5..0: DSCP - tos
ipv4_totlen: .word 0 # 0 interpreted as 1522  1536
ipv4_id: .word 0	# datagram fragment id
ipv4_fragment: .word 0 # high 3 bits = flags(0,DF,MF), low 13 bits fragment offset
# DF = dont fragment, MF = more fragments
ipv4_ttl: .byte 0	# .byte 128
ipv4_protocol: .byte 0	# .byte 1	# icmp
	IP_PROTOCOL_TCP = 0x06
	IP_PROTOCOL_UDP = 0x11
# 0x00 ipv6 hopopt
#*0x01 ICMP internet control message
	IP_PROTOCOL_ICMP = 0x01
# 0x02 IGMP internet group management
# 0x03 GGP gateway-to-gateway
# 0x04 ipv4 encapsulation
# 0x05 ST stream protocol
#*0x06 TCP
	IP_PROTOCOL_TCP = 0x06
# 0x07 CBT core based trees
# 0x08 EGP exterior gateway
# 0x09 IGP interior gateway
# 0x0a BBN RCC monitoring
# 0x0b NVP-II network voice
# 0x10 CHAOS
#*0x11 UDP
	IP_PROTOCOL_UDP = 0x11
# 0x1b RDP - reliable datagram protocol
# 0x29 ipv6 encapsulation
# 0x2b ipv6-route
# 0x2c ipv6-frag
# 0x2e rsvp - resource reservaion
# 0x2f GRE - generic routing encapsulation
# 0x3a ipv6-icmp
# 0x3b ipv6-nonext header
# 0x3c ipv6-opts destination options
# 0x3d any host internal protocol (undefined?)
# 0x3e cftp
# 0x3f any local network
# 0x44 any distributed file system
# 0x46 VISA protocol
# 0x47 IPCV internet packet core uility
ipv4_checksum: .word 0
ipv4_src: .long 0	# .byte 10,0,2,33
ipv4_dst: .long 0	# .byte 10,0,2,1
# if headerlen > 5:
ipv4_options:
IPV4_HEADER_SIZE = .
.text32

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
net_ipv4_header_put:
	push	esi
	cmp	eax, -1
	jz	1f	# require ebx=nic and esi=mac to be arguments
	call	net_arp_resolve_ipv4	# in: eax; out: ebx=nic, esi=mac for eax
	jc	0f	# jc arp_err$:printlnc 4,"ARP error";stc;ret

1:	push	edx
	mov	dx, 0x0800	# ipv4
	call	net_eth_header_put # in: edi, ebx, eax, esi, dx
	pop	edx

	# out: edi points to end of ethernet frame, start of embedded protocol

	mov	[edi + ipv4_v_hlen], byte ptr 0x45 # 4=version, 5*32b=hlen
	mov	[edi + ipv4_dscp], byte ptr 0
	push	ecx
	add	ecx, IPV4_HEADER_SIZE
	xchg	cl, ch
	mov	[edi + ipv4_totlen], cx
	inc	word ptr [ipv4_id$]
	mov	cx, [ipv4_id$]
	mov	[edi + ipv4_id], cx
	mov	[edi + ipv4_fragment], word ptr 0
	mov	[edi + ipv4_ttl], byte ptr 64
	mov	[edi + ipv4_protocol], dl

	# destination ip
	mov	[edi + ipv4_dst], eax
	# source ip
	xor	ecx, ecx
	test	dh, 1
	jnz	1f
	mov	ecx, [ebx + nic_ip]
1:	mov	[edi + ipv4_src], ecx

	# ttl
	test	dh, 2
	jz	1f
	shr	edx, 16
	mov	[edi + ipv4_ttl], dl
1:
	# checksum
	push	edi
	mov	esi, edi
	mov	edi, offset ipv4_checksum
	mov	ecx, IPV4_HEADER_SIZE / 2
	call	protocol_checksum
	pop	edi
	pop	ecx

	add	edi, IPV4_HEADER_SIZE

0:	pop	esi
	ret

######

net_ipv4_print:
	printc 	COLOR_PROTO, "IPv4 "
	mov	dl, [esi + ipv4_v_hlen]
	call	printhex2	# should be 0x45
	mov	dl, [esi + ipv4_protocol]
	print " proto "
	call	printhex2
	call	printspace

	mov	al, dl
	call	ipv4_get_protocol_handler
	jc	1f

	push	esi
	mov	esi, [ipv4_proto_struct$ + proto_struct_name + edi]
	call	print
	pop	esi

	jmp	2f

1:	print	"UNKNOWN"
2:

	print " src "
	PRINT_IP ipv4_src
	print " dst "
	PRINT_IP ipv4_dst


	movzx	edx, byte ptr [esi + ipv4_v_hlen]
	and	dl, 0xf
	shl	edx, 2
	print " HLEN "
	call	printhex4

	print " SIZE "
	mov	dx, [esi + ipv4_totlen]
	xchg	dl, dh
	call	printhex4

	call	newline

# check if ip matches
mov	eax, [esi + ipv4_dst]
cmp	eax, [ebx + nic_ip]
jnz	1f
.if NET_DEBUG
PRINTc 11, "IP MATCH"
.endif	# might move this after 1: as to skip handling packet
1:
	# call nested protocol handler
	#add	esi, edx
	add	esi, 20

	or	edi, edi
	js	1f
	print	"    "
	mov	edx, [ipv4_proto_struct$ + proto_struct_print_handler + edi]
	add	edx, [realsegflat]
	call	edx
1:
	ret


###########################################################
DECL_PROTO_STRUCT_START ipv4
DECL_PROTO_STRUCT_B 0x01, "ICMP", net_ipv4_icmp_handle, net_ivp4_icmp_print,  0
DECL_PROTO_STRUCT_B 0x06, "TCP",  net_ipv4_tcp_handle, net_ipv4_tcp_print,  0
DECL_PROTO_STRUCT_B 0x11, "UDP",  ph_ipv4_udp, net_ipv4_udp_print,  0
DECL_PROTO_STRUCT_END ipv4, IPV4	# declare IPV4_PROTO_LIST_SIZE
.text32

############################

# in: al = protocol
# out: edi = index
ipv4_get_protocol_handler:
	mov	edi, offset ipv4_proto$
	push	ecx
	mov	ecx, IPV4_PROTO_LIST_SIZE
	repne	scasb
	pop	ecx
	jnz	2f
	sub	edi, offset ipv4_proto$ + 1

	call	proto_struct_idx2offs

	clc
	ret
2:	mov	edi, -1
	stc
	ret



###########################################################
# in: ebx = nic XXX
# in: esi = incoming ipv4 frame  [ethernet frame = esi - ETH_HEADER_SIZE]
# in: ecx = frame length
net_ipv4_handle:
	.if NET_IPV4_DEBUG
		printc 11<<4, "IPv4"
	.endif
	push	ebp

	# verify integrity
# changed: eax was ebx, now use eax and then edi
	mov	al, [esi + ipv4_v_hlen]
	mov	ah, al
	shr	ah, 4
	cmp	ah, 4
	LOAD_TXT "not version 4", edx
	jnz	9f
	and	eax, 0xf
	cmp	eax, 5	# minimum size
	LOAD_TXT "header too small", edx
	jb	9f
	mov	edi, eax

	movzx	eax, word ptr [esi + ipv4_totlen] # including header
	xchg	al, ah
	cmp	ecx, eax
	LOAD_TXT "packet length mismatch", edx
	.if 0
	jnz	9f
	.else
	jb	9f	# ip hdr reports larger packet than NIC
	.endif
	# since the NIC driver may report a larger packet, we correct
	# it here:
	mov	ecx, eax


	# verify checksum
	push	esi
	push	ecx
	# XXX pseudo header??
	lea	ecx, [edi * 2]
	xor	edx, edx
	xor	eax, eax
0:	lodsw
	add	edx, eax
	loop	0b
	pop	ecx
	pop	esi
	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	LOAD_TXT "checksum error", edx
	inc	ax
	jnz	9f

	lea	ebp, [edi * 4]	# header len

#	printlnc 11, "IPv4 packet okay"

	# TODO: IPv4 ROUTING GOES HERE

# XXX FIXME TODO: for DHCP, there is no IP yet, so cannot discard message here.
# Instead, the handler should receive the nic on which the packet was received.
	# if broadcast, accept
	mov	eax, [esi + ipv4_dst]
	cmp	eax, -1
	jz	1f
	# ebx is already known: check if all is ok:
		mov	edx, ebx
	call	nic_get_by_ipv4	# out: ebx
	jc	0f	# not for us
		cmp	edx, ebx
		jz	1f
		printc 4, "nic mismatch: "
		DEBUG_DWORD edx
		DEBUG_DWORD ebx
1:

	# forward to ipv4 sub-protocol handler
	mov	al, [esi + ipv4_protocol]
	call	ipv4_get_protocol_handler	# out: edi
	LOAD_TXT "unknown protocol", edx
	jc	9f

	mov	edx, esi
	add	esi, ebp	# payload offset
	sub	ecx, ebp	# subtract header len

	mov	eax, [ipv4_proto_struct$ + proto_struct_handler + edi]
	or	eax, eax
	jz	1f
	add	eax, [realsegflat]
#DEBUG "call"
#DEBUG_DWORD eax
	call	eax	# ebx=nic, edx=ipv4 frame, esi=payload, ecx=payload len

	clc
0:	pop	ebp
	ret

1:	printlnc 4, "ipv4: dropped packet: no handler"
	jmp	1f
9:	printc 4, "ipv4: malformed header: "
	push	esi
	mov	esi, edx
	call	println
	pop	esi
1:	call	net_ipv4_print
	stc
	jmp	0b
	ret

