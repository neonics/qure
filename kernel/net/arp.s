###########################################################################
# ARP Protocol
#
# RFC 826
#
# with extensions:
#
# UNARP  RFC 1868

#########################################################################
# ARP Table implementation

# This flag when 0 optimizes the code for IPV4 only. Setting it to 1
# uses a more generic arp table allowing for different protocol addresses.
ARP_TABLE_GENERIC = 0


ARP_TABLE_DEBUG = 0	# records callers

NET_ARP_DEBUG = 0

.struct 0
arp_entry_mac:		.space 6	# only HW type ethernet supported
arp_entry_ip:		.long 0
.if ARP_TABLE_GENERIC
			.long 0,0,0	# space for ipv6
arp_entry_proto:	.word 0		# NET_ETH_IPV6 or NET_ETH_IPV6
.endif
arp_entry_status:	.byte 0
	ARP_STATUS_NONE = 0
	ARP_STATUS_REQ = 1
	ARP_STATUS_RESOLVED = 2
.if ARP_TABLE_DEBUG
arp_entry_caller:	.long 0
.endif
ARP_ENTRY_STRUCT_SIZE = .
.data
arp_table: .long 0	# array
.text32


# in: eax = ip
# out: ecx + edx
# out: CF on out of memory
arp_table_newentry_ipv4:
	push	eax
	ARRAY_NEWENTRY [arp_table], ARP_ENTRY_STRUCT_SIZE, 4, 9f
	mov	ecx, eax
	mov	eax, [esp]

	mov	[ecx + edx + arp_entry_status], byte ptr ARP_STATUS_NONE
	mov	[ecx + edx + arp_entry_ip], eax
.if ARP_TABLE_GENERIC
	mov	[ecx + edx + arp_entry_proto], word ptr ETH_PROTO_IPV4
.endif
.if ARP_TABLE_DEBUG
	mov	eax, [esp + 4]
	mov	[ecx + edx + arp_entry_caller], eax
.endif
9:	pop	eax
	ret

# Optimized for IPV4
# in: eax = protocol address
# in: esi = hardware address pointer (mac, 6 bytes)
# in: ebx = [bit: can add] [15 bits: proto addr size=4] [word eth protocol ID]
# out: ecx + edx = entry
arp_table_put_mac_ipv4:
	.if NET_ARP_DEBUG
		printc 11, "arp_table_put_mac_ipv4: "
		call net_print_ip
		call printspace
		call net_print_mac
		call newline
	.endif
	ARRAY_LOOP [arp_table], ARP_ENTRY_STRUCT_SIZE, ecx, edx, 0f
.if ARP_TABLE_GENERIC
	cmp	word ptr [ecx + edx + arp_entry_proto], ETH_PROTO_IPV4
	jnz	2f
.endif
	cmp	eax, [ecx + edx + arp_entry_ip]
	jz	1f
2:	ARRAY_ENDL
0:	
	test	ebx, 1 << 31
	jz	91f	# do not add
	call	arp_table_newentry_ipv4
1:	push_	ecx edx
	add	ecx, edx
	mov	[ecx + arp_entry_ip], eax
	mov	edx, [esi]
	mov	[ecx + arp_entry_mac], edx
	mov	dx, [esi + 4]
	mov	[ecx + arp_entry_mac + 4], dx
	mov	byte ptr [ecx + arp_entry_status], ARP_STATUS_RESOLVED
	pop_	edx ecx
.if ARP_TABLE_DEBUG
	mov	eax, [esp + 12]
	mov	[ecx + edx + arp_entry_caller], eax
.else
91:
.endif
0:	ret
.if ARP_TABLE_DEBUG
91:	printlnc 4, "arp_table: not adding"
	ret#jmp	0b
.endif

##########################################################################
# Generic implementation for various protocol address sizes
.if ARP_TABLE_GENERIC

# out: ecx + edx
# out: CF on out of memory
arp_table_newentry:
	push	eax
	ARRAY_NEWENTRY [arp_table], ARP_ENTRY_STRUCT_SIZE, 4, 9f
	mov	ecx, eax
.if ARP_TABLE_DEBUG
	mov	eax, [esp+4]
	mov	[ecx + edx + arp_entry_caller], eax
.endif
9:	pop	eax
	ret



# in: eax = ipv6 ptr
# in: esi = mac ptr
arp_table_put_mac_ipv6:
	push	ebx
	mov	ebx, ETH_PROTO_IPV6 | (16 << 16)
	call	arp_table_put
	pop	ebx
	ret


# Searches the arp table for the matching protocol address (hardware
# is not checked as only ethernet is supported).
# If the address is found, the MAC is updated.
# If it is not found, the highest bit of ebx is checked to see if the address
# should be added.
# in: eax = protocol address pointer
# in: esi = hardware address pointer (mac, 6 bytes)
# in: ebx = [bit: can add] [15 bits: protocol address size] [eth protocol ID]
arp_table_put:
	.if NET_ARP_DEBUG
		printc 11, "arp_table_put_mac: "
		push	eax
		mov	eax, [eax]
		call net_print_ip
		pop	eax
		call printspace
		call net_print_mac
		call newline
	.endif
	push	edx
	push	ecx
	push	esi
	push	edi
	ARRAY_LOOP [arp_table], ARP_ENTRY_STRUCT_SIZE, ecx, edx, 0f
	cmp	bx, [edx + ecx + arp_entry_proto]
	jnz	2f
	push_	ecx edx
	add	edx, ecx
	mov	ecx, ebx
	shr	ecx, 16+2	# assume sizeof(protocol addr) & 3 = 0
	mov	esi, eax
	lea	edi, [edx + arp_entry_ip]
	repz	cmpsd
	pop_	edx ecx
	jz	1f
2:	ARRAY_ENDL
0:	test	ebx, 1 << 31
	jz	0f	# do not add
	call	arp_table_newentry
1:	add	ecx, edx
	mov	[ecx + arp_entry_ip], eax
	mov	edx, [esi]
	mov	[ecx + arp_entry_mac], edx
	mov	dx, [esi + 4]
	mov	[ecx + arp_entry_mac + 4], dx
	mov	byte ptr [ecx + arp_entry_status], ARP_STATUS_RESOLVED
.if ARP_TABLE_DEBUG
	mov	eax, [esp+4+16]
	mov	[ecx + edx + arp_entry_caller], eax
.endif
0:	pop	edi
	pop	esi
	pop	ecx
	pop	edx
	ret

.endif

#########################################################################

arp_table_print:
	push	esi
	push	edx
	push	ecx
	push	ebx
	push	eax
	pushcolor 7
	mov	ebx, [arp_table]
	or	ebx, ebx
	jz	9f
	xor	ecx, ecx
	jmp	1f
0:	printc_	11, "arp "
	color 8
	mov	dl, [ebx + ecx + arp_entry_status]
	call	printhex2
	call	printspace

	cmp	dl, ARP_STATUS_NONE
	jnz	2f
	printc 12, "none      "
	jmp	3f
2:	cmp	dl, ARP_STATUS_REQ
	jnz	2f
	printc  9, "requested "
	jmp	3f
2:	cmp	dl, ARP_STATUS_RESOLVED
	jnz	2f
	printc 10, "resolved  "
	jmp	3f
2:	printc 12, "unknown   "
3:

	lea	esi, [ebx + ecx + arp_entry_mac]
	call	net_print_mac
	call	printspace

.if ARP_TABLE_GENERIC
	printc_ 11, "proto "
	mov	dx, [ebx + ecx + arp_entry_proto]
	call	printhex4
	call	printspace

	mov	ax, [ebx + ecx + arp_entry_proto]
	cmp	ax, ETH_PROTO_IPV4
	jz	3f
	cmp	ax, ETH_PROTO_IPV6
	jnz	2f	# no idea how to print
	lea	eax, [ebx + ecx + arp_entry_ip]
	call	net_print_ipv6
	jmp	2f
3:
.endif
	mov	eax, [ebx + ecx + arp_entry_ip]
	call	net_print_ip
.if ARP_TABLE_GENERIC
2:
.endif

.if ARP_TABLE_DEBUG
	mov	edx, [ebx + ecx + arp_entry_caller]
	call	debug_printsymbol
.endif
	call	newline

	add	ecx, ARP_ENTRY_STRUCT_SIZE # 1 + 4 + 6
1:	cmp	ecx, [ebx + array_index]
	jb	0b

9:	popcolor
	pop	eax
	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
	ret

# in: eax = ipv4
# out: ecx + edx
# out: CF
arp_table_getentry_by_ipv4:
	ARRAY_LOOP [arp_table], ARP_ENTRY_STRUCT_SIZE, ecx, edx, 9f
.if ARP_TABLE_GENERIC
	cmp	word ptr [ecx + edx + arp_entry_proto], ETH_PROTO_IPV4
	jnz	1f
.endif
	cmp	eax, [ecx + edx + arp_entry_ip]
	jz	0f
1:	ARRAY_ENDL
9:
########
	# check mcast
	mov	edx, eax
	shr	dl, 4
	cmp	dl, 0b1110
	stc
	#	jz 11f
	#	DEBUG "ARP:not mcast"
	#	jmp 10f
	#	11:DEBUG "ARP:mcast"
	#	10:
	jnz	0f	# not mcast, do not auto-add entry

	# in: eax = protocol address
	mov	edx, eax
	# in: esi = hardware address pointer (mac, 6 bytes)
	# mcast mac: 01:00:5e:[23 bits of dest ip]
	bswap	edx
	and	edx, (1<<24)-1	# low 23 bits
	or	edx, 0x5e << 24
	bswap	edx
	push	esi
	sub	esp, 6
	mov	esi, esp
	mov	[esi], word ptr 1	# 01:00
	mov	[esi + 2], edx		# 5e:bb:cc:dd
	push	ebx
	# in: ebx = [bit: add] [15 bits: proto addr size=4] [word eth protocol ID]
	mov	ebx, 1 << 31 | 4 << 16 | ETH_PROTO_IPV4
	call	arp_table_put_mac_ipv4
	pop	ebx
	add	esp, 6
	pop	esi
	clc
########
0:	ret

cmd_arp:
	lodsd
	lodsd
	or	eax, eax
	jz	arp_table_print
	printlnc 12, "usage: arp"
	printlnc 8, "shows the arp table"
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
arp_payload:
ARP_HEADER_SIZE = .
# the data, for ipv4:
arp_src_mac:	.space 6	# this will also apply to ipv6 over ethernet.
arp_src_ip:	.long 0
arp_dst_mac:	.space 6	# here however, it will not.
arp_dst_ip:	.long 0
ARP_IPV4_PAYLOAD_SIZE = . - arp_payload

# UNARP (RFC 1868): hw_size is 0 (I assume because the HW ADDR (MAC) is
# already present in the ethernet frame).
#
# Hardware Address Space       as appropriate			(2)
# Protocol Address Space       0x800 (IP)			(2)
# Hardware Address Length      0 (see Backwards Compatibility)	(1)
# Protocol Address Length      4 (length of an IP address)	(1)
# Opcode                       2 (Reply)			(2)
# Source Hardware Address      Not Included			(0)
# Source Protocol Address      IP address of detaching host	(4)
# Target Hardware Address      Not Included			(0)
# Target Protocol Address      255.255.255.255 (IP broadcast)	(4)
#                                                             -------
#                                                               (16)
.text32

# in: ebx = nic
# in: edi = arp frame pointer
# in: eax = dest ip
net_arp_header_put:
	movw	[edi + arp_hw_type], ARP_HW_ETHERNET 	# word ptr 1 << 8
	movw	[edi + arp_proto], 0x0008 # bswap ETH_PROTO_IPV4
	movb	[edi + arp_hw_size], 6
	movb	[edi + arp_proto_size], byte ptr 4
	movw	[edi + arp_opcode], ARP_OPCODE_REQUEST

	# src mac
	add	edi, arp_src_mac
	push	esi
	push	ecx
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

net_arp_print:
	push_	eax edx esi edi
	printc	COLOR_PROTO, "ARP "

	# header

	print  "HW "
	mov	dx, [esi + arp_hw_type]
	call	printhex4

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

	# payload
	mov	edi, esi	# reference header

	lea	esi, [esi + ARP_HEADER_SIZE]

	movzx	edx, byte ptr [edi + arp_hw_size]
	or	dl, dl
	jz	1f
	cmp	dl, 6
	jz	2f
	printc 4, "   (unknown hw size: "
	call	printdec32
	printc 4, ")"
	jmp	1f

2:	print	"   SRC MAC "
	call	net_print_mac
	add	esi, edx	# 6

1:	movzx	eax, byte ptr [edi + arp_proto_size]	# 4
	cmp	al, 4
	jz	1f
	printc 4, " (unknown proto size: "
	push	eax
	call	_s_printdec32
	add	esi, eax	# skip proto addr src
	jmp	2f
1:

	print	" IP "
	lodsd
	call	net_print_ipv4

2:	call	newline

	cmp	dl, 6
	jnz	1f	# warning already printed
	print	"   DST MAC "
	push	esi
	lea	esi, [esi + arp_dst_mac]
	call	net_print_mac
	pop	esi

1:	add	esi, edx	# skip mac addr

	cmpb	[edi + arp_proto_size], 4
	jnz	1f	# warning already printed

	print	" IP "
	mov	eax, [edi + arp_dst_ip]
	call	net_print_ipv4

1:	call	newline
	pop_	edi esi edx eax
	ret



# As per RFC.
# in: ebx = nic
# in: esi, ecx = arp frame
net_arp_handle:
	push_	ebx edx

	.if NET_ARP_DEBUG
		printc 15, "ARP"
	.endif

	# check if the opcodes are known:
	cmp	[esi + arp_opcode], word ptr ARP_OPCODE_REQUEST
	jz	1f
	cmp	[esi + arp_opcode], word ptr ARP_OPCODE_REPLY
	jnz	91f
1:

	# check if it is for ethernet
	cmp	word ptr [esi + arp_hw_type], ARP_HW_ETHERNET
	jnz	95f	# don't have any other hardware types as yet.

	# proto size 4, hw size 6, proto 0800 (ipv4)
	cmp	dword ptr [esi + arp_proto], 0x04060008
	jz	4f

	# check UNARP (ipv4 no hw size)
	cmpd	[esi + arp_proto],  0x04000008
	jz	5f

	# proto size 0x10, hw size 6, proto 0x86dd (ipv6)
	cmp	dword ptr [esi + arp_proto], 0x1006dd86
	jnz	96f


6:	# IPv6
	.if NET_ARP_DEBUG
		printc 11, "IPv6"
	.endif

.if ARP_TABLE_GENERIC # requred for ipv6 support
	# check if it is a local target
	mov	edx, ( (16 << 16) | ETH_PROTO_IPV6 ) << 1	# will be shr 1
	call	nic_get_by_ipv6
	cmc
	rcr	edx, 1
	xchg	ebx, edx	# edx = nic, ebx = arp_table arg

	push_	esi
	# XXX FIXME: the arp_src_* fields happen to align, but the other fields
	# will not due to the arp_src_ip not being 4 bytes.
	lea	eax, [esi + arp_src_ip]
	lea	esi, [esi + arp_src_mac]
	call	arp_table_put
	pop_	esi

	# not supported yet, so no response.
.endif
	jmp	94f


######### IPV4
5:	# IPv4 UNARP (no MAC (hw_addr 0)
	#DEBUG "IPv4 UNARP"; call newline; call	arp_table_print;
	push_	eax ecx edx
	mov	eax, [esi + arp_payload]	# src IP
	call	arp_table_getentry_by_ipv4	# in: eax=IP; out: ecx + edx
	jc	5f
	movb	[ecx + edx + arp_entry_status], 0
	#DEBUG "UPDATE ARP TABLE";call newline; call arp_table_print
5:	pop_	edx ecx eax
	jmp	93f	# 'not a request' (since UNARP is an unsollicited reply)


4:	# ipv4 + MAC
	.if NET_ARP_DEBUG
		printc 11, "IPv4"
	.endif

	# flag = false;
	# if proto type/sender address is in table, update it and set flag=true
	# if target protocol address is local, 
	#	if flag == false add proto type,sender proto/hw address.
	# if opcode = request, respond.
	#
	# post conditions:
	# - if the sender is unknown in the arp table and the target is not local,
	#   the address will not be recorded.
	# - if the sender is unknown and the target is local, it is added.
	# - if the sender is known it is updated.

	# This suggested algorithm requires to:
	# 1) check the arp table for a match for ANY incoming arp packet,
	#    and update the entry if found.
	# 2) check if it is targeted towards a local address, and if so,
	#    add the entry unless 1) has already added it.
	# 3) (only when 2's condition succeeds) respond if it is a request.

	# Changing the algorithm:
	# 1) if the target is local, add or update the entry.
	# 2) if it is not local, see if we had dealings with the address in the
	#    past, by checking if the address is present in the arp table.
	# 3) respond if needed.

	# It is quite possible that existing communication can be disrupted
	# by the MAC address being changed if it is spoofed.
	# Assuming that the Ethernet hardware mac does not change, a first
	# sanity check is to see whether the sender mac matches the sender eth
	# address, and if so, allow updating.

	# find out if it is a local target
	mov	edx, ((4 << 16) | ETH_PROTO_IPV4)<<1	# ignored unless ARP_TABLE_GENERIC

	mov	eax, [esi + arp_dst_ip]
	call	nic_get_by_ipv4	# in: eax
	cmc
	rcr	edx, 1

	xchg	edx, ebx	# edx = nic, ebx = arp_table arg

	# now the highest bit of ebx indicates whether or not target is local,
	# and thus, whether or not to add the entry to the table if it doesnt
	# exist.

	mov	eax, [esi + arp_src_ip]
	# check if sender has IP (gratuitious arp)
	or	eax, eax
	jz	1f	# no ip, don't add to table
	push	esi
	lea	esi, [esi + arp_src_mac]
	push_	ecx edx
	call	arp_table_put_mac_ipv4	# in: eax, esi, ebx; out: ecx/edx
	pop_	edx ecx
	pop	esi
1:
	# check if it is a request directed at us. If it is not,
	# even if it is a response to a prior request we made, it will have
	# been processed. Therefore, only if it is a request respond.

	test	ebx, 1 << 31	# local target
	jz	92f		# nope.
	cmp	word ptr [esi + arp_opcode], ARP_OPCODE_REQUEST
	jnz	93f		# nope, done.

	.if NET_ARP_DEBUG > 1
		DEBUG "ARP who has"
		mov eax, [esi + arp_dst_ip]
		call net_print_ip
		DEBUG "tell"
		mov eax, [esi + arp_src_ip]
		call net_print_ip
		call newline
	.endif
	mov	ebx, edx	# restore nic
	mov	eax, [esi + arp_dst_ip]
	mov	eax, [ebx + nic_ip]
	call	protocol_arp_response

.if !NET_ARP_DEBUG
91:; 92:; 93:; 94:; 95:; 96:
.endif
9:	
	mov	dx, ETH_PROTO_ARP
	call	net_sock_deliver_raw
	pop_	edx ebx
	ret

.if NET_ARP_DEBUG
0:	pushad
	mov	edx, [esp + 32]
	call	net_arp_print#net_print_protocol
	popad
	jmp	9b
	
91:	printlnc 4, "arp: unknown opcode"
	jmp	0b
92:	printlnc 4, "arp: not for us"
	jmp	0b
93:	printlnc 4, "arp: not a request"
	jmp	0b
94:	printlnc 4, "arp: IPv6 not implemented"
	jmp	0b
95:	printlnc 4, "arp: hw type not ethernet"
	jmp	0b
96:	printlnc 3, "arp: unknown protocol"
	jmp	0b
.endif


# in: ebx = nic
# in: esi = incoming arp frame pointer
protocol_arp_response:
	# set up ethernet frame

	NET_BUFFER_GET
	jc	9f
	push	edi

#	mov	esi, edi	# esi = start of packet, edi = end of packet

	# destination mac

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
	movw	[edi + arp_hw_type], ARP_HW_ETHERNET
	movw	[edi + arp_proto], word ptr 0x8	# IP
	movb	[edi + arp_hw_size], byte ptr 6
	movb	[edi + arp_proto_size], byte ptr 4
	movw	[edi + arp_opcode], ARP_OPCODE_REPLY

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

	pop	esi
	# mov	ecx, edi
	# sub	ecx, esi
	mov	ecx, ETH_HEADER_SIZE + ARP_HEADER_SIZE + ARP_IPV4_PAYLOAD_SIZE

	.if NET_ARP_DEBUG > 1
		printlnc 11, "Sending ARP response"
	.endif
	.if NET_ARP_DEBUG > 2
		call	net_packet_hexdump
	.endif

	call	[ebx + nic_api_send]
9:	ret



######################################
# in: eax = ip
# out: ebx = nic
# out: esi = mac (either in local net/mcast, or mac of gateway)
net_arp_resolve_ipv4:
	push	ecx
	push	edx
	push	eax
	# get the route entry
	call	net_route_get	# in: eax=ip; out: edx=gw ip/eax, ebx=nic
	jc	9f
	mov	eax, edx	# update dest ip
	call	arp_table_getentry_by_ipv4 # in: eax; out: ecx + edx
	jc	0f
	cmp	byte ptr [ecx + edx + arp_entry_status], ARP_STATUS_RESOLVED
	jnz	2f
	lea	esi, [ecx + edx + arp_entry_mac]

1:	pop	eax
	pop	edx
	pop	ecx
	ret
########
9:	printlnc 4, "net_arp_resolve_ipv4: no route: "
	call	net_print_ip
	stc
	jmp	1b

########
0:	# no entry in arp table. Check if we can make request.
	call	arp_table_newentry_ipv4	# in: eax; out: ecx + edx
	jc	1b	# out of mem

2:###### have unresolved arp entry

	mov	ecx, 5
0:
	# in: ebx = nic
	# in: eax = ip
	# in: edx = arp table offset
	# out: CF
	call	arp_request
	jc	1b
	# in: eax = ip
	# in: edx = arp table offset
	call	arp_wait_response
	jnc	1b
	#
	push edx; mov edx, ecx; call printdec32; call printspace; pop edx
#	pushad
#	call	arp_table_print
#	popad

	loop	0b
	printlnc 4, "arp timeout - giving up"
	stc
	jmp	1b


# in: eax = ip
# in: ebx = nic
# destroys: esi, edi, dx
arp_probe:
	NET_BUFFER_GET
	jc	9f
	push	edi
	mov	dx, ETH_PROTO_ARP
	mov	esi, offset mac_bcast
	call	net_eth_header_put
	call	net_arp_header_put
	mov	[edi - ARP_HEADER_SIZE - ARP_IPV4_PAYLOAD_SIZE + arp_src_ip], dword ptr 0
	pop	esi
	NET_BUFFER_SEND
9:	ret

# in: eax = dest ip (BCAST)
# in: ebx = nic
# destroys: esi, edi, dx
arp_unarp:
	NET_BUFFER_GET
	jc	9f
	push	edi
	mov	dx, ETH_PROTO_ARP
	mov	esi, offset mac_bcast
	call	net_eth_header_put

	#
	movw	[edi + arp_hw_type], ARP_HW_ETHERNET
	movw	[edi + arp_proto], 0x0008	# ipv4
	movb	[edi + arp_hw_size], 0
	movb	[edi + arp_proto_size], 4
	movw	[edi + arp_opcode], ARP_OPCODE_REPLY

	add	edi, ARP_HEADER_SIZE # offset arp_payload
	# skip src mac (hw_addr)
	# src ip
	push	eax
	mov	eax, [ebx + nic_ip]
	stosd
	# skip dst mac
	# dst ip (BCAST)
	pop	eax
	stosd
	pop	esi
	NET_BUFFER_SEND
9:	ret


# in: ebx = nic
# in: eax = ip
# in: edx = arp table offset
# out: CF
arp_request:
	.if NET_ARP_DEBUG
		DEBUG "arp_request: ip:"
		call net_print_ip
	.endif
	push	edi
	push	ecx
	push	esi

	mov	edi, [arp_table]
	mov	byte ptr [edi + edx + arp_entry_status], ARP_STATUS_REQ

	NET_BUFFER_GET
	jc	91f
	push	edi

	# in: ebx = nic object
	# in: edi = packet buffer
	# in: dx = protocol
	# in: esi = pointer to destination mac
	# out: edi = updated packet pointer
	push	edx
	mov	dx, ETH_PROTO_ARP
	mov	esi, offset mac_bcast
	call	net_eth_header_put
	pop	edx

	# in: edi
	# in: ebx
	# in: eax = target ip
	call	net_arp_header_put

	pop	esi
	NET_BUFFER_SEND
	jc	92f

	.if NET_ARP_DEBUG
		DEBUG "Sent ARP request"
	.endif


0:	pop	esi
	pop	ecx
	pop	edi
	ret
91:	printlnc 4, "arp_request: buffer error"
	stc
	jmp	0b
92:	printlnc 4, "arp_request: send error"
	stc
	jmp	0b


# in: eax = ip
# in: edx = arp table index
# out: esi = MAC for ip
arp_wait_response:
	push	ebx
	push	ecx
	push	edx

	.if NET_ARP_DEBUG
		DEBUG "Wait for ARP on "
		call	net_print_ip
		call	printspace
		push	edx
		mov	ebx, [arp_table]
		movzx	edx, byte ptr [ebx + edx + arp_entry_status]
		call	printdec32
		pop 	edx
		call	newline
	.endif

	# wait for arp response

	mov	ecx, 10
0:	mov	ebx, [arp_table]
	cmp	byte ptr [ebx + edx + arp_entry_status], ARP_STATUS_RESOLVED
	jz	0f
	.if NET_ARP_DEBUG
		printcharc 11, '.'
	.endif
	YIELD timeout=10
	loop	0b

	printc 4, "arp timeout for "
	call	net_print_ip
	call	newline
	stc
	jmp	1f

0:
	lea	esi, [ebx + edx + arp_entry_mac]

	.if NET_ARP_DEBUG
	.if NET_ARP_DEBUG > 1
		printc 9, "Got MAC "
		call	net_print_mac
		printc 9, " for IP "
		call	net_print_ip
		movzx	edx, byte ptr [ebx + edx + arp_entry_status]
		printc 9, " status "
		call	printdec32
		call	newline
	.else
		printc 11, "arp"
	.endif
	.endif

	clc

1:
	pop	edx
	pop	ecx
	pop	ebx
	ret



