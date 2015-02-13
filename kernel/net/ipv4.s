
##############################################################################
# IPv4
.struct 0	# offset 14 in ethernet frame
IP_PROTOCOL_VERSION = 4	# mostly a marker for the use of the constant
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
	IP_PROTOCOL_IGMP = 0x02
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
	# http://www.iana.org/assignments/ip-parameters/ip-parameters.xhtml
	#
	# .byte option_type;
	#	IS_COPY << 7 | CLASS_[0123] << 5 | NUMBER_[0..31]
	IP_OPTFLAG_COPY		= 1 << 7
	IP_OPTFLAG_CLASS2	= 2 << 5 # apparently only 0 and 2 are used
	IP_OPTMASK_COPY		= 0b10000000
	IP_OPTMASK_CLASS	= 0b01100000
	IP_OPTMASK_NUMBER	= 0b00011111
	#
	# if option & ~1	# only option 0 and 1 are 1 byte length
	# .byte option_length
	# .space option_length - 2
	# fi
	IPFLAG_C = IP_OPTFLAG_COPY
	IPFLAG_2 = IP_OPTFLAG_CLASS2
	IPFLAG_6 = IPFLAG_C | IPFLAG_2
	# RFC6814:  ENCODE, EIP, SDB, ...
	IP_OPTION_EOO	= 0	# end of options ('EEOL')
	IP_OPTION_NOP	= 1
	IP_OPTION_SEC	= 2 | IPFLAG_C	# security
	IP_OPTION_LSR	= 3 | IPFLAG_C	# loose source route
	IP_OPTION_LSR	= 4 | IPFLAG_2	# timestamp
	IP_OPTION_ESEC	= 5 | IPFLAG_C	# extended security
	IP_OPTION_CIPSO	= 6 | IPFLAG_C	# commercial security
	IP_OPTION_RR	= 7		# record route
	IP_OPTION_SID	= 8 | IPFLAG_C	# stream id
	IP_OPTION_SSR	= 9 		# strict source route
	IP_OPTION_ZSU	= 10 		# experimental measurement
	IP_OPTION_MTUP	= 11		# MTU Probe
	IP_OPTION_MTUR	= 12		# MTU Reply
	IP_OPTION_FINN	= 13		# experimental flow control
	IP_OPTION_VISA	= 14 | IPFLAG_C	# experimental access control
	IP_OPTION_ENCODE= 15		# ENCODE (rfc6814)
	IP_OPTION_IMITD	= 16 | IPFLAG_C	# IMI Traffic Descriptor
	IP_OPTION_EIP	= 17 | IPFLAG_C	# Extended Internet Protocol(rfc1385,6814)
	IP_OPTION_TR	= 18 | IPFLAG_2	# traceroute (rfc6814)
	IP_OPTION_ADDEXT= 19 | IPFLAG_C # address extension
	IP_OPTION_RTRALT= 20 | IPFLAG_C	# router alert (rfc2113)
	IP_OPTION_SDB	= 21 | IPFLAG_C # selective directed broadcast (rfc6814)
	IP_OPTION__FREE_= 22 | IPFLAG_C	# unassigned (since 10 years)
	IP_OPTION_DPS	= 23 | IPFLAG_C	# dynamic packet state
	IP_OPTION_UMP	= 24 | IPFLAG_C	# upstream multicast packet
	IP_OPTION_QS	= 25		# quick-start (rfc4782)

	IP_OPTION_EXP1	= 30		# rfc3692-style rfc4727 experiment
	IP_OPTION_EXP2	= 30 | IPFLAG_2	# rfc3692-style rfc4727 experiment
	IP_OPTION_EXP3	= 30 | IPFLAG_C	# rfc3692-style rfc4727 experiment
	IP_OPTION_EXP4	= 30 | IPFLAG_6	# rfc3692-style rfc4727 experiment
IPV4_HEADER_SIZE = .	# 20 bytes without options
.text32

# in: edi = out packet
# in: dl = ipv4 sub-protocol
# in: dh = flags
#	1<<0: 0=use nic ip; 1: 0.0.0.0
#	1<<1: 1=(edx >> 16) & 255 = ttl
#	1<<2: 1=force use esi MAC
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
	test	dh, 4
	jnz	1f	# force use of esi MAC
	# TODO: make suspendable. Only netq task would be allowed
	# to send packets; netq (or delegated) task would yield.
	# XXX HTTP responses may hang when the peer IP is not in the ARP table.
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

	# esi free to use
	# check Local network control block (224.0.0.0/24)
	mov	esi, eax
	and	esi, 0x00ffffff
	cmp	esi, 224
	jnz	1f
	mov	dl, 1	# set TTL to 1
	jmp	2f
1:

	# ttl
	test	dh, 2
	jz	1f
	shr	edx, 16
2:	mov	[edi + ipv4_ttl], dl
1:
	# checksum
	push	edi
	mov	esi, edi			# in: esi = start
	mov	edi, offset ipv4_checksum	# in: edi = offset to cksum word
	mov	ecx, IPV4_HEADER_SIZE		# in: ecx = len in bytes
	call	protocol_checksum
	pop	edi
	pop	ecx

	add	edi, IPV4_HEADER_SIZE

0:	pop	esi
	ret

# in: esi = IPv4 frame start
# the standard IPV4_HEADER_SIZE w/o options is assumed.
net_ipv4_checksum:
net_ip_checksum:
	push_	edi ecx
	mov	edi, offset ipv4_checksum	# in: edi = offset to cksum word
	mov	ecx, IPV4_HEADER_SIZE		# in: ecx = len in bytes
	call	protocol_checksum		# in: esi = start
	pop_	ecx edi
	ret

# in: esi = IP frame pointer
# in: ecx = IP payload size (w/o IPv4 header)
# out: ecx = IP frame size (incl header)
net_ip_set_size:
	push_	eax
	movzx	eax, byte ptr [esi + ipv4_v_hlen]	# preserve options (IPV4_HEADER_SIZE)
	and	al, 15
	shl	eax, 2
	add	ecx, eax
	mov	ah, cl
	mov	al, ch
	mov	[esi + ipv4_totlen], ax
	pop_	eax
	jmp	net_ip_checksum

# in: esi = IP frame pointer
# in: al = option nr
# in: ah = option data size (ex option header)
# in: edx = option data pointer
net_ip_add_option:
	push_	ecx esi edi ebx
	# calculate used option space
	mov	ebx, esi	# backup frame pointer
	mov	ecx, eax	# backup option

	movzx	edi, byte ptr [esi + ipv4_v_hlen]
	and	edi, 15
	lea	edi, [esi + edi * 4]	# end of option space
0:	cmp	esi, edi
	jz	51f		# no (more) options, don't parse
	ja	15f		# indirection to 51f: option overflow
	call	net_ip_parse_option$	# out: eax; esi updated
	jnc	0b
51:
	mov	edi, esi	# send of options
	mov	eax, ecx	# restore option
	mov	esi, ebx	# restore frame pointer

		# append the option
		test	al, ~1
		jz	16f	# indirection to 61f

		movzx	ecx, ah
		add	ah, 2
		stosw		# option and length
		rep	movsb	# option data
	61:

	# update the header
	mov	ecx, edi
	sub	ecx, esi	# ip header size
	add	ecx, 3		# rounding
	shr	ecx, 2		# size in dwords
		test	ecx, ~15# max size encoding check
		jz	17f	# indirection to 71f: cl&=15
	71:
	or	cl, IP_PROTOCOL_VERSION << 4
	mov	[esi + ipv4_v_hlen], cl

9:	pop_	ebx edi esi ecx
	jmp	net_ip_checksum

15:	BREAKPOINT "IP Option overflow"	# previously...
	jmp	51b

16:	stosb	# option 0 or 1
	jmp	61b

17:	BREAKPOINT "Too many IP options"
	and	cl, 15	# trunc
	jmp	71b

# in: esi = option pointer
# in: edi = max offset for esi
# destroys: eax
net_ip_parse_option$:
	xor	eax, eax
	# for now, increment esi with the option size
	lodsb
	test	al, ~1
	jz	1f	# option 0 or 1

	lodsb		# option length
	sub	al, 2
	BREAKPOINT_SF "Malformed IP option"
	jz	9f	# done, no data. (optimisation)
	add	esi, eax
9:	ret

1:	bt	ax, 1	# set CF on end of options
	ret


# Calculates a checksum for UDP and TCP over IPv4 constructing a psesudo-header.
# in: al = IP_PROTOCOL_...
# in: edx = ptr to ipv4 src, dst
# in: edi = ptr to checksum field (tcp_checksum, udp_checksum)
# in: esi = tcp/udp frame pointer
# in: ecx = tcp/udp frame len (header and data)
net_ip_pseudo_checksum:
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
	push	esi
	mov	esi, edx
	movzx	edx, al		# protocol
	shl	edx, 8		# 0 byte
.if 1	# 9 instructions, 2 memory references
	lodsd
	add	edx, eax
	adc	edx, 0
	lodsd
	add	edx, eax
	adc	edx, 0
	movzx	eax, dx
	shr	eax, 16
	add	edx, eax
.else	# 9 instructions, 4 memory references
	xor	eax, eax
	# ipv4 src, ipv4 dst
	.rept 4
	lodsw
	add	edx, eax
	.endr
.endif

	#xchg	cl, ch		# headerlen + datalen
	shl	ecx, 8	# hmmm
	add	edx, ecx	# header + data len
	shr	ecx, 8
	pop	esi

	call	protocol_checksum_	# in: ecx=len, esi=start, esi+edi=cksum

	pop	eax
	pop	ecx
	pop	edx
	pop	edi
	pop	esi
	ret

######

# in: esi = ipv4 frame (esi-ETH_HEADER_SIZE(14)=eth frame)
# in: ecx = max frame len (packet_len - 14: usually minimum 64-14, and thus
#  can be larger than the actual size reported in the IP frame).
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

	pushd	[ipv4_proto_struct$ + proto_struct_name + edi]
	call	_s_print

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

	# set ecx to proper ipv4 frame size
	cmp	edx, ecx
	jbe	1f
	pushcolor 4
	pushd	ecx
	pushd	edx
	pushstring "ipv4: warning: frame length %x > remaining packet length %x"
	call	printf
	add	esp, 3*4
	popcolor
	jmp	2f	# keep smallest framelen
1:	mov	ecx, edx
2:	call	newline

	# subtract ipv4 header len from ipv4 frame len
	movzx	edx, byte ptr [esi + ipv4_v_hlen]
	and	dl, 0xf
	shl	edx, 2
	add	esi, edx
	sub	ecx, edx
	jle	91f
	# call nested protocol handler

	or	edi, edi
	js	1f
	print	"    "
	mov	edx, [ipv4_proto_struct$ + proto_struct_print_handler + edi]
	add	edx, [realsegflat]
	call	edx	# XXX ph_* take edx as ipv4 frame - standardize?
1:
	ret

91:	printlnc 4, "    short packet"
	ret


###########################################################
DECL_PROTO_STRUCT_START ipv4
DECL_PROTO_STRUCT_B 0x01, "ICMP", net_ipv4_icmp_handle, net_ivp4_icmp_print,  0
DECL_PROTO_STRUCT_B 0x02, "IGMP", ph_ipv4_igmp, net_ipv4_igmp_print,  0
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
	.if 0
	jz	1f
	.else
	jnb	1f	# ip hdr reports larger packet than NIC
	.endif

	push	edi
	push	ebx
	LOAD_TXT "packet length mismatch: packet=12345678 header=12345678", ebx
	#         0.........1.........2.........3*........4......7
	lea	edi, [ebx + 31]
	mov	edx, ecx
	call	sprinthex8
	lea	edi, [ebx + 47]
	mov	edx, eax
	call	sprinthex8

	mov	edx, ebx
	pop	ebx
	pop	edi
	jmp	9f
1:

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
# XXX fixed?

	# if broadcast, accept
	mov	eax, [esi + ipv4_dst]
	cmp	eax, -1
	jz	1f
	# ebx is already known: check if all is ok:
		mov	edx, ebx
	call	nic_get_by_ipv4	# out: ebx
	jc	92f	# DROP: not for us
	cmp	edx, ebx	# verify the nic
	jnz	93f	# DROP: nic mismatch
1:
	# forward to ipv4 sub-protocol handler
	mov	al, [esi + ipv4_protocol]
	call	ipv4_get_protocol_handler	# out: edi
	jc	91f	# DROP: no protocol

	# firewall / routing
	#
	# check if the route resolves to the nic
	#
	# in: eax = target ip
	# out: ebx = nic to use
	# out: edx = gateway ip
	# free to use: edx, eax; ebx = nic (=edx)
	push	ebx
	mov	eax, [esi + ipv4_src]
	call	net_route_get	# (ip=eax -> ip=edx, nic=ebx)
	mov	edx, ebx
	pop	ebx
	jc	95f	# DROP: no route
	cmp	ebx, edx
	jnz	96f	# DROP: incoming NIC does not match outgoing route

	# TODO: if ipv4_src is LAN and route is default gateway, DROP.
	# The default gateway could also be the gateway to other LAN
	# networks. In this case though, routing entries for LAN masks
	# should be added explicitly, with the default gw the catch all.
	# We must then extend net_route_get to return the matching rule's
	# network/netmask or an 'is_lan' flag.


	# delegate processing to the protocol handler, edi
	mov	edx, esi
	add	esi, ebp	# payload offset
	sub	ecx, ebp	# subtract header len

	mov	eax, [ipv4_proto_struct$ + proto_struct_handler + edi]
	or	eax, eax
	jz	1f
	add	eax, [realsegflat]
	call	eax	# ebx=nic, edx=ipv4 frame, esi=payload, ecx=payload len

	clc
0:	pop	ebp
	ret

9:	printc 4, "ipv4: malformed header: "
	push	esi
	mov	esi, edx
	call	print
	pop	esi
1:	call	net_ipv4_print
	call	newline
	stc
	jmp	0b
91:	LOAD_TXT "unknown protocol; ", edx
	jmp	9b
92:	printc 4, "ipv4: no nic for "
	jmp	1b
93:	printc 4, "ipv4: nic mismatch for "
	call	net_print_ipv4
	DEBUG_DWORD edx;PRINT_CLASS edx
	DEBUG_DWORD ebx;PRINT_CLASS ebx
	jmp	0b
94:	call	0f;	printlnc 1, "no handler";	jmp 1b
95:	call	0f;	printlnc 1, "no route";		jmp 1b	# DROP - do not send ICMP!
96:	call	0f;DEBUG_DWORD edx;DEBUG_DWORD ebx;	printlnc 1, "rx nic != tx nic";	jmp 1b	# DROP - do not send ICMP!
0:	printc 4, "ipv4: dropped packet: "
	ret
