##############################################################################
# Networking
#
# Ethernet, ARP, IPv4, ICMP
.intel_syntax noprefix
.code32
##############################################################################
NET_DEBUG = 0
NET_ARP_DEBUG = NET_DEBUG
NET_IPV4_DEBUG = NET_DEBUG
NET_ICMP_DEBUG = NET_DEBUG

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
PROTO_PRINT_ETHERNET = 2	# 0 = never, 1 = only if nested print, 2=always
PROTO_PRINT_LLC = 0
PROTO_PRINT_IPv4 = 1
PROTO_PRINT_ARP = 1
PROTO_PRINT_IPv6 = 0


COLOR_PROTO = 0x8f
COLOR_PROTO_LOC = 0x80

####################################################
# Protocol handler declarations

#####################################################
.struct 0
proto_struct_name:	.long 0
proto_struct_handler:	.long 0
proto_struct_print_handler:.long 0
proto_struct_flag:	.byte 0
PROTO_STRUCT_SIZE = .
.text

.macro DECL_PROTO_STRUCT name, handler1, handler2, flag
	.data 2
	99: .asciz "\name"
	.data 1
	.long 99b
	.long \handler1
	.long \handler2
	.byte \flag
.endm

.macro DECL_PROTO_STRUCT_START name
	.data
	\name\()_proto$:
	.data 1
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
	.data 1
	\const\()_PROTO_LIST_SIZE = ( . - \name\()_proto_struct$ ) / PROTO_STRUCT_SIZE
	.text
.endm

#
#############################################################################
.data 2
ipv4_id$: .word 0
net_packet$: .space 2048
##############################################################################
# IEEE 802.3 Ethernet / Ethernet II Frame:
.struct 0
eth_header:
eth_dst: .space 6
eth_src: .space 6
eth_len:	# when <= 1500 it is len, otherwise it is type
eth_type: .word 0	# 0x0008	# ipv4 (network byte order MSB)
# 0x0800 ipv4
ETH_PROTO_IPV4 = 0x0800
# 0x0806 ARP
ETH_PROTO_ARP = 0x0806
# 0x0842 wake-on-lan
# 0x1337 SYN3 heartbeat
# 0x8035 RARP
# 0x8100 VLAN tagged frame
# 0x8137 novell IPX
# 0x814c SNMP
# 0x86dd IPV6
ETH_PROTO_IPV6 = 0x86dd
# 0x8809 slow protoocls - IEEE 802.3
# 0x8847 MPLS unicast
# 0x8848 MPLS multicast
# 0x8863 PPoE discovery
# 0x8864 PPoE session
# 0x886f Microsoft NLB heartbeat
# 0x8892 profinet (profibus)
# 0x88a2 ATA over ethernet
# 0x88a8 provider bridging IEE 801.1ad
# 0x88e5 mac security IEE 802.1AE
# 0x88f7 precision time protocol IEE 1588
# 0x8906 fibre channel over ethernet
# 0x9000 configuration test protocol (loop)
# 0xcafe veritas low latency transport (LLT)
ETH_HEADER_SIZE = .

.data
mac_bcast: .byte -1, -1, -1, -1, -1, -1
.text
# in: ebx = nic object
# in: edi = packet buffer
# in: dx = protocol
# in: esi = pointer to destination mac
# out: edi = updated packet pointer
net_eth_header_put:
	push	esi

	# eth_dst: destination mac
	movsd
	movsw

	# eth_src: source mac
	lea	esi, [ebx + nic_mac]
	movsd
	movsw

	pop	esi

	# eth_type: embedded protocol
	xchg	dh, dl
	mov	[edi], dx
	add	edi, 2

	ret

#########################################################################
# ARP - Address Resolution Protocol
.struct 0
arp_hw_type:	.word 0	# 1 = Ethernet
	ARP_HW_ETHERNET = 1 << 8 	# network byte order
arp_proto:	.word 0	# same as ethernet protocol types
arp_hw_size:	.byte 0	# size of mac address (6)
arp_proto_size:	.byte 0	# size of protocol address: 4 for ipv4 (CHK 16 for ipv6)
arp_opcode:	.word 0	# 1 = request, 2 = reply
	ARP_OPCODE_REQUEST = 1 << 8
	ARP_OPCODE_REPLY = 2 << 8
# the data, for ipv4:
arp_src_mac:	.space 6
arp_src_ip:	.long 0
arp_dst_mac:	.space 6
arp_dst_ip:	.long 0
ARP_HEADER_SIZE = .
.text

# in: edi = arp frame pointer
# in: eax = dest ip
net_arp_header_put:
	mov	[edi + arp_hw_type], word ptr 1 << 8
	mov	[edi + arp_proto], word ptr 0x0008
	mov	[edi + arp_hw_size], byte ptr 6
	mov	[edi + arp_proto_size], byte ptr 4
	mov	[edi + arp_opcode], word ptr 0x0100	# 1 = req

	# src mac
	add	edi, arp_src_mac
	push	esi
	push	ecx
	add	esi, arp_src_mac
	mov	ecx, 6
	lea	esi, [ebx + nic_mac]
	rep	movsb
	pop	ecx
	pop	esi

	# src ip
	push	eax
	mov	eax, [ebx + nic_ip]
	stosd

	# dst mac
	xor	eax, eax # 0:0:0:0:0:0 target mac = broadcast
	stosd
	stosw
	# dst ip
	pop	eax
	stosd
	ret

# in: ebx = nic
# in: esi = incoming arp frame pointer
protocol_arp_response:
	# set up ethernet frame

	# destination mac
	mov	edi, offset net_packet$

	push	esi
	add	esi, arp_src_mac
	mov	dx, 0x0806
	call	net_eth_header_put
	pop	esi

.if 0
	push	esi
	add	esi, arp_src_mac
	movsd
	movsw
	pop	esi

	# source mac
	push	esi
	lea	esi, [ebx + nic_mac]
	movsd
	movsw
	pop	esi

	# protocol/type
	mov	ax, 0x0806
	xchg	al, ah
	stosw
.endif
	# ethernet frame done.
	
	# set arp data
	mov	[edi + arp_hw_type], word ptr 1 << 8
	mov	[edi + arp_proto], word ptr 0x8	# IP
	mov	[edi + arp_hw_size], byte ptr 6
	mov	[edi + arp_proto_size], byte ptr 4
	mov	[edi + arp_opcode], word ptr 2 << 8# reply
	
	# set dest mac and ip in arp packet
	push	edi
	push	esi
	add	edi, arp_dst_mac
	add	esi, arp_src_mac
	movsd	# 4 bytes mac
	movsw	# 2 bytes mac
	movsd	# 4 bytes ip
	pop	esi
	pop	edi

	# set source mac and ip in arp packet
	push	edi
	push	esi
	add	edi, arp_src_mac
	lea	esi, [ebx + nic_mac]
	movsd
	movsw
	lea	esi, [ebx + nic_ip]
	movsd
	pop	esi
	pop	edi

	# done, send the packet.

	mov	ecx, ARP_HEADER_SIZE + ETH_HEADER_SIZE
	mov	esi, offset net_packet$

	.if NET_ARP_DEBUG > 1
		printlnc 11, "Sending ARP response"
		call	net_packet_hexdump
	.endif

	call	nic_send
	ret

#######################################################
# ARP Table
.data
arp_table: .long 0
.text
# out: ebx + ecx
arp_table_newentry:
	push	eax
	push	edx
	mov	ecx, 4 + 6 + 1
	mov	eax, [arp_table]
	or	eax, eax
	jnz	1f
	mov	eax, 4
	call	array_new
	jc	9f
1:	call	array_newentry
	jc	9f
	mov	[arp_table], eax
	mov	ebx, eax
	mov	ecx, edx
9:	pop	edx
	pop	eax
	ret

# in: eax = ip
# in: esi = mac ptr
arp_table_put_mac:
	.if NET_ARP_DEBUG
		printc 11, "arp_table_put_mac: "
		call net_print_ip
		call printspace
		call net_print_mac
		call newline
	.endif
	push	ebx
	push	ecx
	mov	ebx, [arp_table]
	or	ebx, ebx
	jnz	0f
	# doesnt exist
	call	arp_table_newentry
	mov	[ebx + ecx + 1], eax
	jmp	2f
0:
	xor	ecx, ecx
0:	cmp	ecx, [ebx + array_index]
	jae	1f
	cmp	[ebx + ecx + 1], eax
	jz	2f
	add	ecx, 4+6+1
	jmp	0b

2:	push	edi
	push	esi
	inc	byte ptr [ebx + ecx]
	lea	edi, [ebx + ecx + 1 + 4]
	movsd
	movsw
	pop	esi
	pop	edi

1:	pop	ecx
	pop	ebx
	ret


arp_table_print:
	push	esi
	push	edx
	push	ecx
	push	ebx
	mov	ebx, [arp_table]
	or	ebx, ebx
	jz	9f
	xor	ecx, ecx
	jmp	1f
0:	
	mov	dl, [ebx + ecx]
	call	printhex2
	call	printspace

	lea	esi, [ebx + ecx + 1 + 4]
	call	net_print_mac
	call	printspace

	mov	eax, [ebx + ecx + 1]
	call	net_print_ip
	call	newline

	add	ecx, 1 + 4 + 6
1:	cmp	ecx, [ebx + array_index]
	jb	0b

9:	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
	ret

# in: eax
# out: ebx + ecx
arp_table_getentry_by_ip:
	mov	ebx, [arp_table]
	or	ebx, ebx
	jz	9f
	xor	ecx, ecx
	jmp	1f
0:	cmp	eax, [ebx + ecx + 1]
	jz	0f
2:	add	ecx, 1 + 4 + 6
1:	cmp	ecx, [ebx + array_index]
	jb	0b
9:	stc
0:	ret

################################################

# in: eax = ip
# in: ebx = nic (obsolete)
# out: esi = gw mac ptr
# out: eax = gw ip
net_arp_resolve_ip:
	push	edx
	push	ebx
	push	ecx

	mov	edx, ebx

	# check cache:

	.if NET_ARP_DEBUG
		DEBUG "arp_resolve_ip"
		call net_print_ip
	.endif

	call	arp_table_getentry_by_ip # in: eax; out: ebx + ecx
	jc	0f
########
	cmp	byte ptr [ebx + ecx], 0
	jz	1f
	lea	esi, [ebx + ecx + 1 + 4]

	.if NET_ARP_DEBUG 
		DEBUG "cache"
		call	net_print_ip
		call	printspace
		call	net_print_mac
		call	newline
	.endif

	clc
	jmp	9f
########
0:	# no entry
	call	nic_get_by_network
	jnc	0f
	call	net_route_get
	jnc	2f
	printlnc 4, "no route for "
	call	net_print_ip
	stc
	jmp	9f
2:	print "gw "
	call	net_print_ip
	# recursion: get mac for gw
	call	net_arp_resolve_ip
	jmp	9f

########
0:	# add new entry

	call	arp_table_newentry
	jc	9f

	mov	[ebx + ecx + 0], byte ptr 0
	mov	[ebx + ecx + 1], eax

######## have arp entry
1:
	mov	ebx, edx
	call	arp_request
########
9:	pop	ecx
	pop	ebx
	pop	edx
	ret


# in: ebx = nic
# in: eax = ip
# in: ecx = arp table offset
# out: esi = mac
# out: CF
arp_request:
	push	ebx
	push	edi
	push	edx
	push	ecx
	push	ecx
	# in: ebx = nic object
	# in: edi = packet buffer
	# in: dx = protocol
	# in: esi = pointer to destination mac
	# out: edi = updated packet pointer
	mov	edi, offset net_packet$
	mov	dx, ETH_PROTO_ARP
	mov	esi, offset mac_bcast
	call	net_eth_header_put

	# in: edi
	# in: eax = target mac
	call	net_arp_header_put

	# in: esi
	# in: ecx
	mov	esi, offset net_packet$
	mov	ecx, edi
	sub	ecx, esi
	call	nic_send

	.if NET_ARP_DEBUG
		DEBUG "Wait for ARP on "
		call net_print_ip
		call	newline
	.endif

	pop	edx	# arp table index

	# wait for arp response
	mov	ecx, 0x3
0:	mov	ebx, [arp_table]
	cmp	byte ptr [ebx + edx], 0
	jnz	0f
	hlt
	loop	0b

	printc 4, "arp timeout for "
	call	net_print_ip
	call	newline
	stc
	jmp	1f

0:	
	lea	esi, [ebx + edx + 1 + 4]

	.if NET_ARP_DEBUG 
		printc 9, "Got MAC "
		call	net_print_mac
		printc 9, " for IP "
		call	net_print_ip
		call	newline
	.endif

	clc
	
1:	pop	ecx
	pop	edx
	pop	edi
	pop	ebx
	ret


pph_arp$:
	printc	COLOR_PROTO, "ARP "

	print  "HW "
	mov	dx, [esi + arp_hw_type]
	call	printhex2

	print	" PROTO "
	mov	ax, [esi + arp_proto]

	mov	dx, ax
	xchg	dl, dh
	call	printhex4
	call	printspace

	call	net_eth_protocol_get_handler$
	jnc	1f
	printc 12, "UNKNOWN"
	jmp	2f
1:	push	esi
	mov	esi, [eth_proto_struct$ + proto_struct_name + edi]
	call	print
	pop	esi
2:
	print	" HW size "
	mov	dl, [esi + arp_hw_size]
	call	printhex2

	print	" PROTO SIZE "
	mov	dl, [esi + arp_proto_size]
	call	printhex2

	print	" OPCODE "
	mov	dx, [esi + arp_opcode]
	call	printhex4
	call	newline
	call	printspace
	call	printspace

	print	" SRC MAC "
	push	esi
	lea	esi, [esi + arp_src_mac]
	call	net_print_mac
	pop	esi

	print	" IP "
	PRINT_IP arp_src_ip

	call	newline
	call	printspace
	call	printspace
	print	" DST MAC "
	push	esi
	lea	esi, [esi + arp_dst_mac]
	call	net_print_mac
	pop	esi

	print	" IP "
	PRINT_IP arp_dst_ip

	call	newline
	ret

ph_arp$:
	.if NET_ARP_DEBUG 
		printc 15, "ARP"
	.endif
	
	# check if it is for ethernet
	cmp	word ptr [esi + arp_hw_type], ARP_HW_ETHERNET
	jnz	0f

	# proto size 4, hw size 6, proto 0800 (ipv4)
	cmp	dword ptr [esi + arp_proto], 0x04060008
	jz	4f
	# proto size 0x10, hw size 6, proto 0x86dd (ipv6)
	cmp	dword ptr [esi + arp_proto], 0x1006dd86
	jnz	0f

6:	# IPv6	
	.if NET_ARP_DEBUG
		printc 11, "IPv6"
	.endif
	jmp	0f

4:	# IPv4.
	# check if it is request
	cmp	word ptr [esi + arp_opcode], ARP_OPCODE_REQUEST
	jz	1f

	cmp	word ptr [esi + arp_opcode], ARP_OPCODE_REPLY
	jnz	0f	# unknown

	.if NET_ARP_DEBUG
		DEBUG "ARP"
		mov	eax, [esi + arp_dst_ip]
		call	net_print_ip
		DEBUG ":"
		mov	eax, [esi + arp_src_ip]
		call net_print_ip
		DEBUG "is at"
		push esi
		lea esi, [esi + arp_src_mac]
		call net_print_mac
		pop esi
		call newline
	.endif

	# check if it is meant for us
	push	esi
	lea	esi, [esi + arp_dst_mac]
	call	nic_get_by_mac
	pop	esi
	#call	nic_get_by_ipv4
	jc	0f
	mov	eax, [esi + arp_dst_ip]
	cmp	eax, [ebx + nic_ip]
	jz	3f

	printc 4, "MAC/IP mismatch: "
	call	net_print_ip
	mov	eax, [ebx + nic_ip]
	call	net_print_ip
	call	newline
	stc
	jmp	0f
3:
	# update arp table
	mov	eax, [esi + arp_src_ip]
	lea	esi, [esi + arp_src_mac]
	call	arp_table_put_mac
	clc
	jmp	0f

1:	# handle arp request

	.if NET_ARP_DEBUG > 1
		DEBUG "ARP who has"
		mov eax, [esi + arp_dst_ip]
		call net_print_ip
		DEBUG "tell"
		mov eax, [esi + arp_src_ip]
		call net_print_ip
		call newline
	.endif
	mov	eax, [esi + arp_dst_ip]
	call	nic_get_by_ipv4
	jc	0f

	mov	eax, [ebx + nic_ip]
	call	protocol_arp_response
	call	newline

0:	ret




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
# 0x02 IGMP internet group management
# 0x03 GGP gateway-to-gateway
# 0x04 ipv4 encapsulation
# 0x05 ST stream protocol
#*0x06 TCP
# 0x07 CBT core based trees
# 0x08 EGP exterior gateway
# 0x09 IGP interior gateway
# 0x0a BBN RCC monitoring
# 0x0b NVP-II network voice
# 0x10 CHAOS
#*0x11 UDP
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
.text

# in: edi = out packet
# in: ebx = nic object (for src mac & ip (ip currently static))
# in: dl = ipv4 sub-protocol
# in: esi = destination mac
# in: eax = destination ip
# in: cx = payload length (without ethernet/ip frame)
# out: edi = points to end of ethernet+ipv4 frames in packet
net_ipv4_header_put:

	push	eax
	call	net_arp_resolve_ip
	pop	eax
	jc	0f

	mov	edi, offset net_packet$
	push	dx
	mov	dx, 0x0800	# ipv4
	call	net_eth_header_put # in: edi, ebx, eax, esi, dx, cx 
	pop	dx
	# out: edi points to end of ethernet frame, start of embedded protocol

	mov	[edi + ipv4_v_hlen], byte ptr 0x45 # 4=version, 5*32b=hlen
	mov	[edi + ipv4_dscp], byte ptr 0
	push	ecx
	add	ecx, IPV4_HEADER_SIZE
	xchg	cl, ch
	mov	[edi + ipv4_totlen], cx
	pop	ecx
	push	dx
	inc	word ptr [ipv4_id$]
	mov	dx, [ipv4_id$]
	mov	[edi + ipv4_id], dx
	pop	dx
	mov	[edi + ipv4_fragment], word ptr 0
	mov	[edi + ipv4_ttl], byte ptr 64
	mov	[edi + ipv4_protocol], dl

	# destination ip
	mov	[edi + ipv4_dst], eax

	# source ip
	mov	eax, [ebx + nic_ip]
	mov	[edi + ipv4_src], eax

	# checksum
	push	esi
	push	edi
	push	ecx
	mov	esi, edi
	mov	edi, offset ipv4_checksum
	mov	ecx, IPV4_HEADER_SIZE / 2
	call	protocol_checksum
	pop	ecx
	pop	edi
	pop	esi

	add	edi, IPV4_HEADER_SIZE

0:	ret


#############################################################################
# ICMP 
.struct 0	# 14 + 20
icmp_header:
icmp_type: .byte 0 # .byte 8
	# type  
	#*0	echo (ping) reply
	# 1,2	reserved
	# 3	destination unreachable
	# 4	source quench
	# 5	redirect message
	# 6	alternate host address
	# 7	reserved
	#*8	echo request (ping)
	# 9	router advertisement
	# 10	router sollicitation
	# 11	time exceeded
	# 12	parameter problem: bad ip header
	# 13	timestamp
	# 14	timestamp reply
	# 15	information request
	# 16	information reply
	# 17	address mask request
	# 18	address mask reqply
	# 19	reserved for security
	# 20-29	reserved for robustness experiment
	# 30	traceroute
	# 31	datagram conversion error
	# 32	mobile host redirect
	# 33	where are you (ipv6)
	# 34	here i am (ipv6)
	# 35	mobile registration request
	# 36	mobile registration reply
	# 37	domain name request
	# 38	domain name reply
	# 39	SKIP (simple key management for IP) discovery protocol
	# 40	photuris security failures
	# 41	ICMP for experimental mobile protocols
	# 42-255 reserved

icmp_code: .byte 0
icmp_checksum: .word 0 
icmp_id: .word 0
icmp_seq: .word 0
ICMP_HEADER_SIZE = .
.text
# in: ebx = nic 
# in: eax = target ip
# in: esi = payload
# in: ecx = payload len
# in: edi = out packet
net_icmp_header_put:
	mov	dl, 1	# ICMP
	add	ecx, ICMP_HEADER_SIZE
	call	net_ipv4_header_put
	jc	0f

	mov	[edi + icmp_type], byte ptr 8	# ping request
	mov	[edi + icmp_id], word ptr 0x0100# bigendian 1
	.data
	icmp_sequence$: .word 0
	.text
	mov	dx, [icmp_sequence$]
	xchg	dl, dh
	inc	word ptr [icmp_sequence$]
	mov	[edi + icmp_seq], dx

	push	esi
	push	ecx
	push	edi
	shr	ecx, 1
	mov	esi, edi
	mov	edi, offset icmp_checksum
	call	protocol_checksum
	pop	edi
	pop	ecx
	pop	esi

	add	edi, ICMP_HEADER_SIZE

	#rep	movsb

	mov	ecx, edi
	mov	esi, offset net_packet$
	sub	ecx, esi
0:	ret

.data
icmp_requests: .long 0
.text

# in: eax = ip
# out: eax + edx = entry (byte status, dword ip)
net_icmp_register_request:
	push	ebx
	push	ecx
	mov	ebx, eax

	mov	eax, [icmp_requests]
	mov	ecx, 4+1
	or	eax, eax
	jnz	0f
	inc	eax
	call	array_new
1:	call	array_newentry
	mov	[icmp_requests], eax
	mov	[eax + edx + 1], ebx
9:	mov	[eax + edx + 0], byte ptr 0
	pop	ecx
	pop	ebx
	ret

0:	ARRAY_ITER_START eax, edx
	cmp	ebx, [eax + edx + 1]
	jz	9b
	ARRAY_ITER_NEXT eax, edx, 5
	jmp	1b
	
	
net_icmp_register_response:
	push	ebx
	push	ecx
	mov	ebx, [icmp_requests]
	or	ebx, ebx
	jz	0f
	ARRAY_ITER_START ebx, ecx
	cmp	eax, [ebx + ecx + 1]
	jnz	1f
	inc	byte ptr [ebx + ecx + 0]
	clc
	jmp	0f
1:	ARRAY_ITER_NEXT ebx, ecx, 5
	stc
0:	pop	ecx
	pop	ebx
	ret
#############################################################################

# in: esi = pointer to header to checksum
# in: edi = offset relative to esi to receive checksum
# in: ecx = length of header in 16 bit words
# destroys: eax, ecx, esi
protocol_checksum:
	push	edx
	push	eax

	xor	edx, edx
	xor	eax, eax
	mov	[esi + edi], ax

	push	esi
0:	lodsw
	add	edx, eax
	loop	0b
	pop	esi

	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	not	ax
	mov	[esi + edi], ax

	pop	eax
	pop	edx
	ret


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




##############################################

.data
DECL_PROTO_STRUCT_START eth
DECL_PROTO_STRUCT_W 0,             "LLC",  ph_llc$, pph_llc$,  PROTO_PRINT_LLC
DECL_PROTO_STRUCT_W ETH_PROTO_IPV4,"IPv4", ph_ipv4$, pph_ipv4$, PROTO_PRINT_IPv4
DECL_PROTO_STRUCT_W ETH_PROTO_ARP, "ARP",  ph_arp$, pph_arp$,  PROTO_PRINT_ARP
DECL_PROTO_STRUCT_W ETH_PROTO_IPV6,"IPv6", ph_ipv6$, pph_ipv6$, PROTO_PRINT_IPv6
DECL_PROTO_STRUCT_END eth, ETHERNET
.text

# in: edi = index (0, 1, 2)
# out: edi = protocol structure offset (0, 9, 18, ..)
proto_struct_idx2offs:
	# multiply by the protocol structure size
	push	eax
	push	edx
	mov	eax, PROTO_STRUCT_SIZE
	mul	edi
	mov	edi, eax
	pop	edx
	pop	eax
	ret

# in: ax = protocol word
# out: edi = protocol index:
#   [proto$ + edi * 2]: protocol word (ax)
#   [eth_proto_handlers$ + edi*4] = unrelocated offset to protocol handler
#   [proto_names$ + edi * 4 ] = pointer to protocol name string
net_eth_protocol_get_handler$:
	# test if the protocol word is smaller than the maximum packet size
	xchg	al, ah
	cmp	ax, 1500
	ja	1f
	# it is, so, it is a packet length, not a protocol identifier.
	xor	edi, edi	# LLC protocol
	ret

1:	push	ecx
	mov	edi, offset eth_proto$
	mov	ecx, ETHERNET_PROTO_LIST_SIZE
	repne	scasw
	pop	ecx
	stc
	jnz	1f

	# calculate the index
	# scas always points just after the match
	sub	edi, offset eth_proto$ + 2
	shr	edi, 1
	call	proto_struct_idx2offs
	
	clc	# redundant
1:	ret




#######################################################
# Packet Analyzer

# in: esi = ethernet frame
# in: ecx = packet size
net_handle_packet:
	push	esi
	mov	ebx, -1	# local use
	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$	# out: edi
	jc	1f
	# non-promiscuous mode: check target mac
	cmp	[esi + eth_dst], dword ptr -1
	jnz	2f
	cmp	[esi + eth_dst + 4], word ptr -1
	jz	0f
2:	call	nic_get_by_mac # in: esi = mac ptr
	jc	9f	# promiscuous handler
0:	mov	edx, [eth_proto_struct$ + proto_struct_handler + edi]
	or	edx, edx
	jz	1f
	add	edx, [realsegflat]
	add	esi, ETH_HEADER_SIZE
	sub	ecx, ETH_HEADER_SIZE
	call	edx
9:	pop	esi
	ret
###
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
2:	mov	dx, ax
	call	printhex4
	call	newline
	call	net_print_protocol
	popcolor
	stc
	jmp	9b


# Protocol packet handlers
# These are only called when eth.dst_mac is broadcast or matches a nic

ph_llc$:ret


ph_ipv6$:
	ret

####################################################
# Packet Dumper

# in: esi = points to ethernet frame
# in: ecx = packet size
net_print_protocol:
	push	edi
	pushcolor 0x1b

	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$
	jnc	1f

	call	net_print_ethernet$
	printc 12, "UNKNOWN"
	mov	dx, ax
	call	printhex4
	call	newline
	stc
	jmp	2f

1:
.if PROTO_PRINT_ETHERNET
	call	net_print_ethernet$
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

	COLOR	0x87

	push	esi
	call	printspace
	call	printspace
	call	edi
	pop	esi

2:	popcolor
	pop	edi
	ret


net_print_ethernet$:
	printc	COLOR_PROTO, "Ethernet "

	printc	COLOR_PROTO_LOC, "DST "
	call	net_print_mac
	add	esi, 6

	printc	COLOR_PROTO_LOC, " SRC "
	call	net_print_mac
	add	esi, 6

	printc	COLOR_PROTO_LOC, " PROTO "
	movzx	edx, word ptr [esi]
	xchg	dl, dh
	add	esi, 2
	call	printhex4

	printc COLOR_PROTO_LOC, " LEN "
	mov	edx, ecx
	call	printhex4

	call	printspace
	ret

# in: dx = length
pph_llc$:
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

###########################################################
DECL_PROTO_STRUCT_START ipv4
DECL_PROTO_STRUCT_B 0x01, "ICMP", ph_ipv4_icmp, pph_ipv4_icmp$,  0
DECL_PROTO_STRUCT_B 0x06, "TCP",  0, pph_ipv4_tcp$,  0
DECL_PROTO_STRUCT_B 0x11, "UDP",  0, pph_ipv4_udp$,  0
DECL_PROTO_STRUCT_END ipv4, IPV4	# declare IPV4_PROTO_LIST_SIZE
.text

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
# in: esi = incoming ipv4 frame
# in: ecx = frame length
ph_ipv4$:
	.if NET_IPV4_DEBUG
		printc 11<<4, "IPv4"
	.endif
	push	ebp

	# verify integrity
	mov	bl, [esi + ipv4_v_hlen]
	mov	bh, bl
	shr	bh, 4
	cmp	bh, 4
	LOAD_TXT "not version 4", edx
	jnz	9f
	and	ebx, 0xf
	cmp	ebx, 5	# minimum size
	LOAD_TXT "header too small", edx
	jb	9f

	movzx	eax, word ptr [esi + ipv4_totlen] # including header
	xchg	al, ah
	cmp	ecx, eax
	LOAD_TXT "packet length mismatch", edx
	jnz	9f

	# calculate crc
	push	esi
	push	ecx
	lea	ecx, [ebx * 2]
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

	lea	ebp, [ebx * 4]	# header len

#	printlnc 11, "IPv4 packet okay"

	# TODO: IPv4 ROUTING GOES HERE

	mov	eax, [esi + ipv4_dst]
	call	nic_get_by_ipv4	# out: ebx
	jc	0f	# not for us

	# forward to ipv4 sub-protocol handler
	mov	al, [esi + ipv4_protocol]
	call	ipv4_get_protocol_handler
	LOAD_TXT "unknown protocol", edx
	jc	9f
	
	mov	edx, esi
	add	esi, ebp	# payload
	sub	ecx, ebp	# subtract header len

	mov	eax, [ipv4_proto_struct$ + proto_struct_handler + edi]
	or	eax, eax
	jz	1f
	add	eax, [realsegflat]

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
1:	call	pph_ipv4$
	stc
	jmp	0b
	ret

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload
# in: ecx = payload len
ph_ipv4_icmp:
	# check for ping request
	cmp	[esi + icmp_type], byte ptr 8
	jnz	1f
	.if NET_ICMP_DEBUG
		printc 11, "ICMP PING REQUEST "
	.endif
	call	protocol_icmp_ping_response
	clc
	ret

1:	cmp	[esi + icmp_type], byte ptr 0
	jnz	9f
	mov	eax, [edx + ipv4_src]
	.if NET_ICMP_DEBUG
		printc 11, "ICMP PING RESPONSE from "
		call	net_print_ip
		call	newline
	.endif
	call	net_icmp_register_response
	clc
0:	ret

9:	printlnc 4, "ipv4_icmp: dropped packet"
	call	pph_ipv4_icmp$
	stc
	ret




pph_ipv4$:
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
PRINTc 11, "IP MATCH"
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

pph_ipv4_tcp$:
	print	"TCP "
	call	newline
	ret


pph_ipv4_icmp$:
	printc	15, "ICMP"

	print " TYPE "
	mov	dl, [esi + icmp_type]
	call	printhex2
	
	print " CODE "
	mov	dl, [esi + icmp_code]
	call	printhex2

	print " CHECKSUM "
	mov	dx, [esi + icmp_checksum]
	call	printhex4

	print " ID "
	mov	dx, [esi + icmp_id]
	call	printhex4

	print " SEQ "
	mov	dx, [esi + icmp_seq]
	call	printhex4

	call	newline
	ret


# in: ebx = nic
# in: edx = incoming ipv4 frame pointer
# in: esi = incoming icmp frame pointer
# in: ecx = icmp frame length
# in: esi - edx = ipv4 header length
protocol_icmp_ping_response:

	# set up ethernet and ip frame

	# in: ebx = nic object (for src mac & ip (ip currently static))
	# in: edi = out packet
	mov	edi, offset net_packet$

	push	esi
	# in: eax = destination ip
	mov	eax, [edx + ipv4_src]
	# in: esi = destination mac
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src]

# FIXME bypass arp lookup - this code is triggered from the NIC ISR and thus
# cannot rely on IRQ's for packet Tx/Rx for the ARP protocol.
call arp_table_put_mac

	# in: dl = ipv4 sub-protocol
	mov	dl, 1	# icmp
	# in: cx = paload length
	call	net_ipv4_header_put # in: dl, ebx, edi, eax, esi, cx
	pop	esi

	# ethernet/ip frame done.

	# set icmp data
	mov	[edi + icmp_type], byte ptr 0	# ping reply
	mov	[edi + icmp_code], byte ptr 0
	mov	[edi + icmp_checksum], word ptr 0
	mov	ax, [esi + icmp_id]
	mov	[edi + icmp_id], ax
	mov	ax, [esi + icmp_seq]
	mov	[edi + icmp_seq], ax

	push	edi
	add	edi, ICMP_HEADER_SIZE
	# append ping data
	add	esi, ICMP_HEADER_SIZE
	.rept 8
	movsd
	.endr
	pop	edi

	# call checksum
	push	esi
	push	edi
	push	ecx
	mov	esi, edi
	mov	edi, offset icmp_checksum
	mov	ecx, ICMP_HEADER_SIZE / 2 + 32/2
	# edi = start/base
	call	protocol_checksum
	pop	ecx
	pop	edi
	pop	esi

	# done, send the packet.

	mov	ecx, ICMP_HEADER_SIZE + IPV4_HEADER_SIZE + ETH_HEADER_SIZE + 32
	mov	esi, offset net_packet$

	.if NET_ICMP_DEBUG
		printlnc 11, "Sending ICMP PING response"
	.if NET_ICMP_DEBUG > 1
		call	net_packet_hexdump
		DEBUG_DWORD ebx
	.endif
	.endif

	call	nic_send
	ret

###########################################################################
# UDP
.struct 0
udp_sport: .word 0
udp_dport: .word 0
udp_len: .word 0
udp_cksum: .word 0
UDP_HEADER_SIZE = .
.text
# in: edi = udp frame pointer
# in: eax = sport/dport
protocol_udp:
	bswap	eax
	stosd
	mov	[edi], word ptr 0x0800	# 8 bytes len
	mov	[edi + 2], word ptr 0	# checksum - allowed to be 0
	add	edi, 4
	ret


pph_ipv4_udp$:
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
	mov	dx, [esi + udp_cksum]
	call	printhex4

	add	esi, UDP_HEADER_SIZE

	call	newline
	ret

pph_ipv6$:
	printc	COLOR_PROTO, "IPv6 "
	call	newline
	ret


##############################################################################
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet:
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

1:
	call	net_handle_packet

	pop	ebx
	pop	ecx
	pop	esi
	ret


############################################################################
# IPv4 Routing

.struct 0
net_route_gw: .long 0
net_route_network: .long 0
net_route_netmask: .long 0
net_route_device: .long 0
NET_ROUTE_STRUCT_SIZE = .
.data
net_route: .long 0
.text

# in: eax = gw
# in: ebx = device
# in: ecx = network
# in: edx = netmask
net_route_add:
	push	eax
	push	ebx
	push	ecx
	push	edx
	mov	eax, [net_route]
	or	eax, eax
	jnz	1f
	inc	eax
	mov	ecx, NET_ROUTE_STRUCT_SIZE
	call	array_new
	jc	9f
1:	call	array_newentry
	jc	9f
	mov	[net_route], eax

	mov	ebx, [esp + 0]
	mov	[eax + edx + net_route_netmask], ebx
	mov	ebx, [esp + 4]
	mov	[eax + edx + net_route_network], ebx
	mov	ebx, [esp + 8]
	mov	[eax + edx + net_route_device], ebx
	mov	ebx, [esp + 12]
	mov	[eax + edx + net_route_gw], ebx

9:	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret


net_route_print:
	push	eax
	push	ebx
	push	edx

	printlnc 11, "IPv4 Route Table"

	mov	ebx, [net_route]
	or	ebx, ebx
	jz	9f
	ARRAY_ITER_START ebx, edx
	mov	eax, [ebx + edx + net_route_network]
	call	net_print_ip
	printchar_ '/'
	mov	eax, [ebx + edx + net_route_netmask]
	call	net_print_ip
	print	" gw "
	mov	eax, [ebx + edx + net_route_gw]
	call	net_print_ip
	call	printspace

	push	ebx	# WARNING: using nonrelative pointer
	mov	ebx, [ebx + edx + net_route_device]
#	call	dev_print
	pop	ebx

	call	newline

	ARRAY_ITER_NEXT ebx, edx, NET_ROUTE_STRUCT_SIZE
9:	pop	edx
	pop	ebx
	pop	eax
	ret

# in: eax = ipv4 address
# out: ebx = nic to use
# out: esi = gateway
net_route_get:
	push	ebx
	push	ecx
	push	edx
	mov	ebx, [net_route]
	or	ebx, ebx
	jz	1f
	ARRAY_ITER_START ebx, ecx
	mov	edx, [ebx + ecx + net_route_netmask]
	or	edx, edx
	jnz	0f
	# default gw
2:	
	mov	eax, [ebx + ecx + net_route_gw]
	jmp	9f
0:	and	edx, eax
	cmp	edx, [ebx + ecx + net_route_network]
	jz	2b
	ARRAY_ITER_NEXT ebx, ecx, NET_ROUTE_STRUCT_SIZE
1:	stc
	printlnc 4, "net_route_get: no route: "
	call	net_print_ip
	call	newline
9:	pop	edx
	pop	ecx
	pop	ebx
	ret


cmd_route:
	lodsd
	lodsd
	or	eax, eax
	jz	net_route_print
	CMD_ISARG "add"
	jnz	1f
	xor	ebx, ebx	# device
	xor	ecx, ecx	# network
	xor	edx, edx	# netmask
	lodsd
	CMD_ISARG "default"
	jnz	0f
	lodsd
0:	CMD_ISARG "gw"
	jnz	0f
	lodsd
0:	call	net_parse_ip
	jc	1f

	print "route add "
	call	net_print_ip
	call	newline

	call	net_route_add
	ret

1:	printlnc 12, "usage: route add [[default] gw] <ip>"
	ret
############################################################################
cmd_ping:
	lodsd
	lodsd
	or	eax, eax
	jz	1f
	call	net_parse_ip
	jc	1f

	push	eax
	call	nic_get_by_network
	pop	eax
	jnc	0f	# it's a local ip

	# get the default gateway
	push	eax
	call	net_route_get
	mov	ebx, eax
	pop	eax
	jc	1f

	push	eax
	print "using route "
	mov	eax, ebx
	call net_print_ip
	call	nic_get_by_network
	pop	eax
	jnc	0f

1:	printlnc 4, "ping: no route: "
	call	net_print_ip
	call	newline
	stc
	jmp	9f


0:	print	"Pinging "
	call	net_print_ip
	print	": "
	mov	ecx, 32
	mov	esi, offset mac_bcast
	mov	edi, offset net_packet$
	call	net_icmp_header_put	# in: edi, eax, esi, ecx
	jc	9f

	# payload
	mov	ecx, 23
	jnc	0f
	mov	al, 'a'
0:	stosb
	inc	al
	loop	0b
	mov	al, 'A'
	mov	ecx, 9
0:	stosb
	inc	al
	loop	0b

	mov	eax, [net_packet$ + ETH_HEADER_SIZE + ipv4_dst]
	call	net_icmp_register_request
	push	edx

	mov	ecx, edi
	sub	ecx, offset net_packet$
	mov	edi, offset net_packet$
	call	nic_send
	pop	edx

	mov	ecx, 0x03
0:	mov	eax, [icmp_requests]
	cmp	byte ptr [eax + edx + 0], 0
	jnz	1f
	hlt
	loop	0b
	printc 4, "PING timeout for "
	jmp	2f

1:	print	"ICMP PING response from "
2:	mov	eax, [eax + edx + 1]
	call	net_print_ip
	call	newline
	dec	byte ptr [eax + edx + 0] # not really needed

9:	ret
1:	printlnc 12, "usage: ping <ip>"
	ret


cmd_arp:
	lodsd
	lodsd
	or	eax, eax
	jz	arp_table_print
	printlnc 12, "usage: arp"
	printlnc 8, "shows the arp table"
	ret
