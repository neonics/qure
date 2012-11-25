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
NET_TCP_DEBUG = NET_DEBUG
NET_DHCP_DEBUG = NET_DEBUG
NET_DNS_DEBUG = 1#NET_DEBUG

NET_TCP_CONN_DEBUG = 0
NET_TCP_OPT_DEBUG = 0

NET_HTTP_DEBUG = 3

CPU_FLAG_I = (1 << 9)
CPU_FLAG_I_BITS = 9

# out: CF = IF
.macro IN_ISR
	push	edx
	pushfd
	pop	edx
	.if NET_DEBUG > 1
		DEBUG "FLAGS:"
		call printbin16
	.endif
	shr	edx, CPU_FLAG_I_BITS
	pop	edx
.endm


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
PROTO_PRINT_ETHERNET = 1	# 0 = never, 1 = only if nested print, 2=always
PROTO_PRINT_LLC = 0
PROTO_PRINT_IPv4 = 1
PROTO_PRINT_ARP = 1
PROTO_PRINT_IPv6 = 0


COLOR_PROTO_DATA = 0x07
COLOR_PROTO = 0x0f
COLOR_PROTO_LOC = 0x09

####################################################
# Protocol handler declarations

#####################################################
.struct 0
proto_struct_name:	.long 0
proto_struct_handler:	.long 0
proto_struct_print_handler:.long 0
proto_struct_flag:	.byte 0
PROTO_STRUCT_SIZE = .
.text32

.macro DECL_PROTO_STRUCT name, handler1, handler2, flag
	.data SECTION_DATA_STRINGS # was 2
	99: .asciz "\name"
	.data SECTION_DATA_CONCAT
	.long 99b
	.long \handler1
	.long \handler2
	.byte \flag
.endm

.macro DECL_PROTO_STRUCT_START name
	.data
	\name\()_proto$:
	.data SECTION_DATA_CONCAT
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
	.data SECTION_DATA_CONCAT
	\const\()_PROTO_LIST_SIZE = ( . - \name\()_proto_struct$ ) / PROTO_STRUCT_SIZE
	.text32
.endm

#
#############################################################################
.data SECTION_DATA_BSS
ipv4_id$: .word 0
BUFFER_SIZE = 0x600
net_buffers: .long 0	# ptr_array
net_buffer_index: .long 0
NET_BUFFERS_NUM = 4
.text32
##############################################################################
.macro DEBUG_NET_BUF
	push	ecx
	push	eax
	push	edx
	pushcolor 0x1f
	call	newline
	printc 0x1d, "NETBUFS "
	mov	eax, [net_buffers]
	or	eax, eax
	jnz	1f
	printlnc 4, "none"
	jmp	2f

1:	mov	edx, eax
	call	printhex8

	printc	0x1d, " idx "
	mov	edx, [eax + array_index]
	call	printhex8

	printc 0x1d, " cap "
	mov	edx, [eax + array_capacity]
	call	printhex8

	printc	0x1c, " INDEX "
	mov	edx, [net_buffer_index]
	call	printhex8
	call	newline

	printc 0x1e, "ptrs: "
	xor	ecx, ecx
90:	mov 	edx, [eax + ecx]
	call	printhex8
	call	printspace
	add	ecx, 4
	cmp	ecx, 4 * NET_BUFFERS_NUM
	jbe	90b
	call	newline
2:	popcolor
	pop	edx
	pop	eax
	pop	ecx
.endm


# out: eax = mem address of BUFFER_SIZE bytes, paragraph aligned
# modifies: edx
net_buffer_allocate:
	PTR_ARRAY_NEWENTRY [net_buffers], NET_BUFFERS_NUM, 9f	# out: eax + edx
	jc	9f
	mov	[net_buffer_index], edx
	add	edx, eax
	mov	eax, BUFFER_SIZE + 16
	call	malloc
	jc	9f
	mov	[edx], eax
	add	eax, 15
	and	al, 0xf0
	ret
9:	printlnc 0x4f, "net_buffer_allocate: malloc error"
	stc
	ret

# mod: eax edx
net_buffer_get:
	mov	eax, [net_buffers]
	or	eax, eax
	jz	net_buffer_allocate
	mov	edx, [net_buffer_index]
	add	edx, 4
	cmp	edx, [eax + array_capacity]
	jb	0f
	xor	edx, edx
0:	mov	[net_buffer_index], edx
	cmp	edx, [eax + array_index]
	mov	eax, [eax + edx]
	jnb	net_buffer_allocate
	add	eax, 15
	and	al, 0xf0
	clc
	ret

# out: edi
.macro NET_BUFFER_GET
	push	eax
	push	edx
	call	net_buffer_get
	mov	edi, eax
	pop	edx
	pop	eax
.endm

# in: esi = start of buffer
# in: edi = end of data in buffer
# in: ebx = nic
# modifies: ecx
.macro NET_BUFFER_SEND
	mov	ecx, edi
	sub	ecx, esi
	call	[ebx + nic_api_send]
.endm

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
.text32
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


# in: esi = ethernet frame (len 6+6+2 = 14)
# out: esi + 14
net_eth_print:
	pushcolor COLOR_PROTO_DATA
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
	popcolor
	ret


.data
DECL_PROTO_STRUCT_START eth
DECL_PROTO_STRUCT_W 0,             "LLC",  net_llc_handle, net_llc_print,  PROTO_PRINT_LLC
DECL_PROTO_STRUCT_W ETH_PROTO_IPV4,"IPv4", net_ipv4_handle, net_ipv4_print, PROTO_PRINT_IPv4
DECL_PROTO_STRUCT_W ETH_PROTO_ARP, "ARP",  net_arp_handle, net_arp_print,  PROTO_PRINT_ARP
DECL_PROTO_STRUCT_W ETH_PROTO_IPV6,"IPv6", net_ipv6_handle, net_ipv6_print, PROTO_PRINT_IPv6
DECL_PROTO_STRUCT_END eth, ETHERNET
.text32

# in: edi = index (0, 1, 2)
# out: edi = protocol structure offset (0, 9, 18, ..)
proto_struct_idx2offs:
	# multiply by the protocol structure size
	push	eax
	mov	eax, PROTO_STRUCT_SIZE
	imul	edi, eax
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




###########################################################################
# ARP Table
.struct 0
arp_entry_mac:		.space 6
arp_entry_ip:		.long 0
arp_entry_status:	.byte 0
	ARP_STATUS_NONE = 0
	ARP_STATUS_REQ = 1
	ARP_STATUS_RESP = 2
ARP_ENTRY_STRUCT_SIZE = .
.data
arp_table: .long 0	# array
.text32

# in: eax = ip
# out: ecx + edx
# out: CF on out of memory
arp_table_newentry:
	push	eax
	ARRAY_NEWENTRY [arp_table], ARP_ENTRY_STRUCT_SIZE, 4, 9f
	mov	ecx, eax
9:	pop	eax

	mov	[ecx + edx + arp_entry_status], byte ptr ARP_STATUS_NONE
	mov	[ecx + edx + arp_entry_ip], eax
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
	push	edx
	push	ecx
	ARRAY_LOOP [arp_table], ARP_ENTRY_STRUCT_SIZE, ecx, edx, 0f
	cmp	eax, [ecx + edx + arp_entry_ip]
	jz	1f
	ARRAY_ENDL
0:	printc 6, "arp_table_put_mac: warning: no request: "
	call	net_print_ip
	call	newline
	call	arp_table_newentry
1:	add	ecx, edx
	mov	[ecx + arp_entry_ip], eax
	mov	edx, [esi]
	mov	[ecx + arp_entry_mac], edx
	mov	dx, [esi + 4]
	mov	[ecx + arp_entry_mac + 4], dx
	mov	byte ptr [ecx + arp_entry_status], ARP_STATUS_RESP
	pop	ecx
	pop	edx
	ret


arp_table_print:
	push	esi
	push	edx
	push	ecx
	push	ebx
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
2:	cmp	dl, ARP_STATUS_RESP
	jnz	2f
	printc 10, "resolved  "
	jmp	3f
2:	printc 12, "unknown   "
3:

	lea	esi, [ebx + ecx + arp_entry_mac]
	call	net_print_mac
	call	printspace

	mov	eax, [ebx + ecx + arp_entry_ip]
	call	net_print_ip
	call	newline

	add	ecx, 1 + 4 + 6
1:	cmp	ecx, [ebx + array_index]
	jb	0b

9:	popcolor
	pop	ebx
	pop	ecx
	pop	edx
	pop	esi
	ret

# in: eax
# out: ecx + edx
arp_table_getentry_by_ip:
	ARRAY_LOOP [arp_table], ARP_ENTRY_STRUCT_SIZE, ecx, edx, 9f
	cmp	eax, [ecx + edx + arp_entry_ip]
	jz	0f
	ARRAY_ENDL
9:	stc
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
# the data, for ipv4:
arp_src_mac:	.space 6
arp_src_ip:	.long 0
arp_dst_mac:	.space 6
arp_dst_ip:	.long 0
ARP_HEADER_SIZE = .
.text32

# in: ebx = nic
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
	printc	COLOR_PROTO, "ARP "

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


net_arp_handle:
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
	.if NET_ARP_DEBUG
		printc 11, "IPv4"
	.endif

	# check if it is request
	cmp	word ptr [esi + arp_opcode], ARP_OPCODE_REQUEST
	jz	1f

	cmp	word ptr [esi + arp_opcode], ARP_OPCODE_REPLY
	.if NET_ARP_DEBUG
		jz	2f
		printc 12, "Unknown opcode"
		jmp	0f
	2:
	.else
		jnz	0f
	.endif

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

	printc 4, "MAC/IP mismatch: packet="
	call	net_print_ip
	printc 4, " nic="
	mov	eax, [ebx + nic_ip]
	call	net_print_ip
	call	newline
	call	net_arp_print
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

0:	ret




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

	pop	esi
	# mov	ecx, edi
	# sub	ecx, esi
	mov	ecx, ARP_HEADER_SIZE + ETH_HEADER_SIZE

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
# out: esi = mac (either in local net, or mac of gateway)
net_arp_resolve_ipv4:
	push	ecx
	push	edx
	push	eax

	# get the route entry
	call	net_route_get	# in: eax=ip; out: edx=gw ip/eax, ebx=nic
	jc	9f
	mov	eax, edx
	call	arp_table_getentry_by_ip # in: eax; out: ecx + edx
	jc	0f
	cmp	byte ptr [ecx + edx + arp_entry_status], ARP_STATUS_RESP
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

9:	printc 11, "[In ISR - arp resolve suspended]"
	stc
	jmp	1b

########
0:	# no entry in arp table. Check if we can make request.
	call	arp_table_newentry	# in: eax; out: ecx + edx
	jc	1b	# out of mem

2:###### have arp entry
#	IN_ISR
#	jc	9b
	# in: ebx = nic
	# in: eax = ip
	# in: edx = arp table offset
	# out: CF
	call	arp_request
	jc	1b
	# in: eax = ip
	# in: edx = arp table offset
	call	arp_wait_response
	jmp	1b


# in: eax = ip
# in: ebx = nic
arp_probe:
	NET_BUFFER_GET
	jc	9f
	push	edi
	mov	dx, ETH_PROTO_ARP
	mov	esi, offset mac_bcast
	call	net_eth_header_put
	call	net_arp_header_put
	mov	[edi - ARP_HEADER_SIZE + arp_src_ip], dword ptr 0
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
	jc	6f
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
	jc	9f

	.if NET_ARP_DEBUG
		DEBUG "Sent ARP request"
	.endif


0:	pop	esi
	pop	ecx
	pop	edi
	ret

9:	printlnc 4, "arp_request: send error"
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
		push edx
		movzx edx, byte ptr [ebx + edx + arp_entry_status]
		call printdec32
		pop edx
		call	newline
	.endif

	# wait for arp response
# TODO: suspend (blocking IO/wait for arp response with timeout)

IN_ISR
jnc 1f
DEBUG "WARNING: IF=0"
1:
	mov	ecx, [pit_timer_frequency]
	shl	ecx, 1	# 2 second delay
	jnz	0f
	mov	ecx, 2000/18	# probably
0:	mov	ebx, [arp_table]
	cmp	byte ptr [ebx + edx + arp_entry_status], ARP_STATUS_RESP
	jz	0f
	.if NET_ARP_DEBUG
		printcharc 11, '.'
	.endif
	hlt
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



################################################
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
	call	net_arp_resolve_ipv4	# out: ebx=nic, esi=mac
	jc	0f	# jc arp_err$:printlnc 4,"ARP error";stc;ret

1:	push	dx
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

#############################################################################
# ICMP
#
# rfc 792
.struct 0	# 14 + 20
icmp_header:
icmp_type: .byte 0
	# type
	#*0	echo (ping) reply
	# 1,2	reserved
	# 3	destination unreachable
	#	codes: 0=net / 1=host / 2=protocol / 3=port unreachable
	#	  4=fragmentation needed & DontFrag set; 5=src route failed
	#	msg format: [type][code][checksum], [id][seq] unused,
	#	[internet header][64 bits of original datagram].
	#	codes 0,1,4,5: gateway; codes 2,3: host
	# 4	source quench: code 0; msg fmt: same as 3; gw queue full.
	#	  gw can send 1 src quench msg for each discarded datagram.
	#	  sender reduces speed of sending datagrams until no src quench
	#	  messages are received.
	# 5	redirect message; codes: 'redirect datagrams for: '
	#	  0=network, 1=host, 2=ToS and network; 3=ToS and host.
	#	  (ToS=Type of Service).
	#	msg format: 2nd dword: gateway internet address to be used.
	# 6	alternate host address
	# 7	reserved
	#*8	echo request (ping)
	# 9	router advertisement
	# 10	router sollicitation
	# 11	time exceeded; code 0: ttl exceeded; 1: fragment reasmbl tm excd
	#	msg format: same as type 3
	# 12	parameter problem: bad ip header; code:0.
	#	msg format: same as type 3,except 2nd dword:.byte ptr;.space 3
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
icmp_2nd:	# 2nd dword - various uses depending on type.
icmp_id: .word 0
icmp_seq: .word 0
icmp_payload:
ICMP_HEADER_SIZE = .
.data
icmp_sequence$: .word 0
.text32
# in: eax = target ip
# in: esi = payload
# in: ecx = payload len
# in: dl = hops (ttl)
# in: edi = out packet
# out: ebx = nic
# successful: modifies eax, esi, edi
net_icmp_header_put:
	push	edx
	push	ecx
	and	edx, 0xff
	jz	1f
	shl	edx, 16
	mov	dh, 2
1:	mov	dl, IP_PROTOCOL_ICMP
	add	ecx, ICMP_HEADER_SIZE
	call	net_ipv4_header_put
	jc	0f

	sub	ecx, ICMP_HEADER_SIZE

	mov	[edi + icmp_type], word ptr 8	# type=ping request code=0
	mov	[edi + icmp_id], word ptr 0x0100# bigendian 1
	mov	dx, [icmp_sequence$]
	xchg	dl, dh
	inc	word ptr [icmp_sequence$]
	mov	[edi + icmp_seq], dx

	push	edi
	push	ecx
	add	edi, ICMP_HEADER_SIZE
	rep	movsb
	pop	ecx
	pop	edi

	push	esi
	push	ecx
	push	edi
	add	ecx, ICMP_HEADER_SIZE
	shr	ecx, 1
	mov	esi, edi
	mov	edi, offset icmp_checksum
	call	protocol_checksum
	pop	edi
	pop	ecx
	pop	esi

	lea	edi, [edi + ecx + ICMP_HEADER_SIZE]

0:	pop	ecx
	pop	edx
	ret

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = icmp frame
# in: ecx = payload len
net_ipv4_icmp_handle:
	call	net_sock_deliver_icmp

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
	jnz	1f
	mov	eax, [edx + ipv4_src]
	.if NET_ICMP_DEBUG
		printc 11, "ICMP PING RESPONSE from "
		call	net_print_ip
		call	newline
	.endif
	call	net_icmp_register_response
	clc
0:	ret

1:	cmp	[esi + icmp_type], byte ptr 5
	jnz	1f
	.if 1# NET_ICMP_DEBUG
		printc 11, "ICMP Redirect "
		mov	dl, [esi + icmp_code]
		call	printhex2
		printc 11, " gw "
		mov	eax, [esi + icmp_2nd]
		call	net_print_ip
		call	newline
	.endif
	clc
	ret

1:	cmp	[esi + icmp_type], byte ptr 11
	jnz	1f
	.if NET_ICMP_DEBUG
		printc 11, "ICMP timeout "
		mov	dl, [esi + icmp_code]
		call	printhex2
		printc 11, " original: "
		add	esi, ICMP_HEADER_SIZE
		sub	ecx, ICMP_HEADER_SIZE
		call	net_ipv4_print#_header
		call	newline
	.endif
	clc
	ret

1:
9:	printlnc 4, "ipv4_icmp: dropped packet"
	call	net_ivp4_icmp_print
	stc
	ret

.struct 0
icmp_request_status: .byte 0
icmp_request_addr: .long 0
ICMP_REQUEST_STRUCT_SIZE = .
.data
icmp_requests: .long 0	# array
.text32

# in: eax = ip
# out: eax + edx = entry (byte status, dword ip)
net_icmp_register_request:
	push	ebx
	push	ecx
	.if NET_ICMP_DEBUG > 1
		DEBUG "net_icmp_register_request"
		call net_print_ip
		call newline
	.endif
	mov	ebx, eax

	mov	eax, [icmp_requests]
	mov	ecx, ICMP_REQUEST_STRUCT_SIZE
	or	eax, eax
	jnz	0f
	inc	eax
	call	array_new
1:	call	array_newentry
	mov	[icmp_requests], eax
	mov	[eax + edx + icmp_request_addr], ebx
9:	mov	[eax + edx + icmp_request_status], byte ptr 0
	pop	ecx
	pop	ebx
	ret
0:	ARRAY_ITER_START eax, edx
	cmp	ebx, [eax + edx + icmp_request_addr]
	jz	9b
	ARRAY_ITER_NEXT eax, edx, ICMP_REQUEST_STRUCT_SIZE
	jmp	1b

# in: eax = ip
net_icmp_register_response:
	push	ebx
	push	ecx
	ARRAY_LOOP [icmp_requests], ICMP_REQUEST_STRUCT_SIZE, ebx, ecx, 0f
	cmp	eax, [ebx + ecx + icmp_request_addr]
	jnz	1f
	inc	byte ptr [ebx + ecx + icmp_request_status]
	clc
	jmp	2f
1:	ARRAY_ENDL
0:	stc
2:	pop	ecx
	pop	ebx
	ret

net_icmp_list:
	ARRAY_LOOP [icmp_requests], ICMP_REQUEST_STRUCT_SIZE, ebx, ecx, 0f
	printc 11, "icmp "
	mov	dl, [ebx + ecx + icmp_request_status]
	call	printhex2
	call	printspace
	mov	eax, [ebx + ecx + icmp_request_addr]
	call	net_print_ip
	call	newline
	ARRAY_ENDL
0:	ret
#############################################################################

# in: esi = pointer to header to checksum
# in: edi = offset relative to esi to receive checksum
# in: ecx = length of header in 16 bit words
# destroys: eax, ecx, esi
protocol_checksum_:
	push	edx
	push	eax
	jmp	1f
protocol_checksum:
	push	edx
	push	eax
	xor	edx, edx
1:	xor	eax, eax
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


#######################################################
# Packet Analyzer

# in: ebx = nic
# in: esi = ethernet frame
# in: ecx = packet size
net_handle_packet:
	.if NET_DEBUG > 1
		DEBUG "PKTLEN"
		DEBUG_DWORD ecx
	.endif
	push	esi
	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$	# out: edi
	jc	2f
	# non-promiscuous mode: check target mac
	cmp	[esi + eth_dst], dword ptr -1
	jnz	2f
	cmp	[esi + eth_dst + 4], word ptr -1
	jz	0f
2:	# verify nic mac
	mov	eax, ebx
	call	nic_get_by_mac # in: esi = mac ptr
	jc	3f	# promiscuous handler
	cmp	eax, ebx
	jnz	4f
0:	mov	edx, [eth_proto_struct$ + proto_struct_handler + edi]
	or	edx, edx
	jz	1f

	add	edx, [realsegflat]
	add	esi, ETH_HEADER_SIZE
	sub	ecx, ETH_HEADER_SIZE
	call	edx
9:	pop	esi
	ret
3:	# can't get nic by mac
4:	# nic's mac doesnt match nic on which pkt was received
	mov	ebx, eax	# restore receiving nic
	jmp	0b		# go ahead anyway
###
2:	printc 4, "net_handle_packet: dropped packet: unknown protocol: "
	jmp	2f
	mov	dx, [esi + eth_type]
	call	printhex4
	stc
	ret

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
2:	mov	dx, [esi + eth_type]
	call	printhex4
	call	newline
	call	net_print_protocol
	popcolor
	stc
	jmp	9b


# Protocol packet handlers
# These are only called when eth.dst_mac is broadcast or matches a nic



net_ipv6_handle:
	ret

####################################################
# Packet Dumper

# in: esi = points to ethernet frame
# in: ecx = packet size
net_print_protocol:
	push	edi
	PUSHCOLOR COLOR_PROTO_DATA

	mov	ax, [esi + eth_type]
	call	net_eth_protocol_get_handler$
	jnc	1f

	call	net_eth_print
	printc 12, "UNKNOWN"
	mov	dx, ax
	call	printhex4
	call	newline
	stc
	jmp	2f

1:
.if PROTO_PRINT_ETHERNET
	call	net_eth_print
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

#	COLOR	0x87

	push	esi
	call	printspace
	call	printspace
	call	edi
	pop	esi

2:	popcolor
	pop	edi
	ret


###########################################################################
# LLC - Logical Link Control
#
net_llc_handle:ret

# in: dx = length (ethernet.proto)
net_llc_print:
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

################################################################################
# TCP
#
.struct 0
tcp_sport:	.word 0
tcp_dport:	.word 0
tcp_seq:	.long 0	# 4f b2 f7 fc decoded as relative seq nr 0..
	# if SYN is set, initial sequence nr
	# if SYN is clear, accumulated seq nr of first byte packet
tcp_ack_nr:	.long 0	# zeroes - ACK nr when ACK set
	# if ack set, next seq nr receiver is expecting
tcp_flags:	.word 0	# a0, 02:  a = data offset hlen (10=40 bytes), 02=SYN
	TCP_FLAG_DATA_OFFSET	= 15<< 12
		# tcp header size in 32 bit/4byte words (a = 10 * 4=40)
		# min 5 (20 bytes), max 15 (60 bytes = max 40 bytes options)
	TCP_FLAG_RESERVED	= 7 << 9
	TCP_FLAG_NS		= 1 << 8 # NS: ECN NONCE concealment
	TCP_FLAG_CWR		= 1 << 7 # congestion window reduced
	TCP_FLAG_ECE		= 1 << 6 # ECN-Echo indicator: SN=ECN cap
	TCP_FLAG_URG		= 1 << 5 # urgent pointer field significant
	TCP_FLAG_ACK		= 1 << 4 # acknowledgement field significant
	TCP_FLAG_PSH		= 1 << 3 # push function (send buf data to app)
	TCP_FLAG_RST		= 1 << 2 # reset connection
	TCP_FLAG_SYN		= 1 << 1 # synchronize seq nrs
	TCP_FLAG_FIN		= 1 << 0 # no more data from sender.
tcp_windowsize:	.word 0	# sender receive capacity
tcp_checksum:	.word 0 #
tcp_urgent_ptr:	.word 0 # valid when URG
TCP_HEADER_SIZE = .
tcp_options:	#
	# 4-byte aligned - padded with TCP_OPT_END.
	# 3 fields:
	# option_kind:	 .byte 0	# required
	# option_length: .byte 0	# optional (includes kind+len bytes)
	# option_data: 	 .space VARIABLE# optional (len required)

	TCP_OPT_END	= 0	# 0		end of options (no len/data)
	TCP_OPT_NOP	= 1	# 1		padding; (no len/data)
	TCP_OPT_MSS	= 2	# 2,4,w  [SYN]	max seg size
	TCP_OPT_WS	= 3	# 3,3,b  [SYN]	window scale
	TCP_OPT_SACKP	= 4	# 4,2	 [SYN]	selectice ack permitted
	TCP_OPT_SACK	= 5	# 5,N,(BBBB,EEEE)+   N=10,18,26 or 34
						# 1-4 begin-end pairs
	TCP_OPT_TSECHO	= 8	# 8,10,TTTT,EEEE
	TCP_OPT_ACR	= 14	# 14,3,S [SYN]	Alt Checksum Request
	TCP_OPT_ACD	= 15	# 15,N		Alt Checksum Data

	# 20 bytes:
	# 02 04 05 b4:	maximum segment size: 02 04 .word 05b4
	# 01:		nop: 01
	# 03 03 07:	window scale: 03 len: 03 shift 07
	# 04 02:	tcp SACK permission: true
	# timestamp 08 len 0a value 66 02 ae a8 echo reply 00 00 00 00
.text32
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_ipv4_tcp_print:
	printc	15, "TCP"

	print	" sport "
	xor	edx, edx
	mov	dx, [esi + tcp_sport]
	xchg	dl, dh
	call	printdec32

	print	" dport "
	xor	edx, edx
	mov	dx, [esi + tcp_dport]
	xchg	dl, dh
	call	printdec32

	print	" seq "
	mov	edx, [esi + tcp_seq]
	bswap	edx
	call	printhex8

	print	" acknr "
	mov	edx, [esi + tcp_ack_nr]
	bswap	edx
	call	printhex8

	mov	ax, [esi + tcp_flags]
	xchg	al, ah
	movzx	edx, ax
	shr	dx, 12
	print	" hlen "
	call	printdec32

	print	" flags "
	PRINTFLAG ax, TCP_FLAG_NS, "NS "
	PRINTFLAG ax, TCP_FLAG_CWR, "CWR "
	PRINTFLAG ax, TCP_FLAG_ECE, "ECE "
	PRINTFLAG ax, TCP_FLAG_URG, "URG "
	PRINTFLAG ax, TCP_FLAG_ACK, "ACK "
	PRINTFLAG ax, TCP_FLAG_PSH, "PSH "
	PRINTFLAG ax, TCP_FLAG_RST, "RST "
	PRINTFLAG ax, TCP_FLAG_SYN, "SYN "
	PRINTFLAG ax, TCP_FLAG_FIN, "FIN "

	call	newline
	ret


############################################
# TCP Connection management
#
TCP_CONN_REUSE_TIMEOUT	= 30 * 1000	# 30 seconds
.struct 0
tcp_conn_timestamp:	.long 0	# [clock_ms]
tcp_conn_local_addr:	.long 0
tcp_conn_remote_addr:	.long 0	# ipv4 addr
tcp_conn_local_port:	.word 0
tcp_conn_remote_port:	.word 0
tcp_conn_local_seq:	.long 0
tcp_conn_remote_seq:	.long 0
tcp_conn_local_seq_ack:	.long 0
tcp_conn_remote_seq_ack:.long 0
tcp_conn_handler:	.long 0
tcp_conn_state:		.byte 0
	# incoming
	TCP_CONN_STATE_SYN_RX		= 1
	TCP_CONN_STATE_SYN_ACK_TX	= 2
	# outgoing
	TCP_CONN_STATE_SYN_TX		= 4
	TCP_CONN_STATE_SYN_ACK_RX	= 8
	# incoming
	TCP_CONN_STATE_FIN_RX		= 16
	TCP_CONN_STATE_FIN_ACK_TX	= 32
	# outgoing
	TCP_CONN_STATE_FIN_TX		= 64
	TCP_CONN_STATE_FIN_ACK_RX	= 128


#	TCP_CONN_STATE_LISTEN		= 1	# server
#	TCP_CONN_STATE_SYN_RECEIVED	= 2	# server
#	TCP_CONN_STATE_ESTABLISHED	= 3	# both
#	TCP_CONN_STATE_FIN_WAIT_1	= 4
#	TCP_CONN_STATE_FIN_WAIT_2	= 5
#	TCP_CONN_STATE_CLOSE_WAIT	= 6
#	TCP_CONN_STATE_LAST_ACK		= 7
#	TCP_CONN_STATE_TIME_WAIT	= 8
#	TCP_CONN_STATE_CLOSED		= 9
.align 4
TCP_CONN_STRUCT_SIZE = .
.data SECTION_DATA_BSS
tcp_connections: .long 0	# volatile array
.text32
tcp_conn_print_state_$:
	PRINTFLAG dl, 1, "SYN_RX "
	PRINTFLAG dl, 2, "SYN_ACK_TX "
	PRINTFLAG dl, 4, "SYN_TX "
	PRINTFLAG dl, 8, "SYN_ACK_RX "
	PRINTFLAG dl, 16, "FIN_RX "
	PRINTFLAG dl, 32, "FIN_ACK_TX "
	PRINTFLAG dl, 64, "FIN_TX "
	PRINTFLAG dl, 128, "FIN_ACK_RX "
	ret

tcp_conn_print_state$:
	push	edx
	mov	edx, esi
	call	printbin8
	pop	edx
	ret
#	.data
#	tcp_conn_states$:
#	STRINGPTR "<unknown>"
#	STRINGPTR "LISTEN"
#	STRINGPTR "SYN_RECEIVED"
#	STRINGPTR "ESTABLISHED"
#	STRINGPTR "FIN_WAIT_1"
#	STRINGPTR "FIN_WAIT_2"
#	STRINGPTR "CLOSE_WAIT"
#	STRINGPTR "LAST_ACK"
#	STRINGPTR "TIME_WAIT"
#	STRINGPTR "CLOSED"
#	.text32
#	cmp	esi, TCP_CONN_STATE_CLOSED + 1
#	jl	0f
#	xor	esi, esi
#0:	mov	esi, [tcp_conn_states$ + esi * 4]
#	call	print
#	ret


# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# out: eax = tcp_conn array index (add volatile [tcp_connections])
net_tcp_conn_get:
	push	ecx
	push	edx
	mov	ecx, [esi + tcp_sport]
	rol	ecx, 16
	ARRAY_LOOP [tcp_connections], TCP_CONN_STRUCT_SIZE, edx, eax, 9f
	cmp	ecx, [edx + eax + tcp_conn_local_port]
	jz	0f
	ARRAY_ENDL
9:	stc
0:	pop	edx
	pop	ecx
	ret


# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: edi = handler [unrelocated]
# out: eax = tcp_conn array index
net_tcp_conn_newentry:
	push	ecx
	push	edx

	mov	ecx, edx	# ip frame
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "(tcp NewConn)"
	.endif

	push	edi
	mov	edi, [clock_ms]
	sub	edi, TCP_CONN_REUSE_TIMEOUT

	# find free entry (use status flag)
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, eax, edx, 9f
	cmp	byte ptr [eax + edx + tcp_conn_state], -1
	jz	1f
	cmp	byte ptr [eax + edx + tcp_conn_state], 0b01111111
	jnz	2f
	cmp	edi, [eax + edx + tcp_conn_timestamp]
	jnb	1f
2:	ARRAY_ENDL
9:
	push	ecx
	ARRAY_NEWENTRY [tcp_connections], TCP_CONN_STRUCT_SIZE, 4, 9f
	jmp	2f
9:	pop	ecx

	pop	edi
	pop	edx
	pop	ecx
	ret

2:	pop	ecx

1:	pop	edi
	push	edx	# retval eax

0:	MUTEX_LOCK TCP_CONN, nolocklabel=0b
	mov	eax, [tcp_connections]

	add	eax, edx

	# eax = tcp_conn ptr
	# ecx = ip frame
	# edx = free

	mov	[eax + tcp_conn_state], byte ptr 0
	mov	[eax + tcp_conn_handler], edi

	mov	edx, [ecx + ipv4_src]
	mov	[eax + tcp_conn_remote_addr], edx
			.if NET_TCP_CONN_DEBUG > 1
			DEBUG "remote"
				push	eax
				mov	eax, edx
				call	net_print_ip
				pop	eax
			.endif

	mov	edx, [ecx + ipv4_dst]
	mov	[eax + tcp_conn_local_addr], edx
			.if NET_TCP_CONN_DEBUG > 1
				DEBUG "local"
				push	eax
				mov	eax, edx
				call	net_print_ip
				pop	eax
			.endif
	mov	edx, [esi + tcp_sport]
	ror	edx, 16
	mov	[eax + tcp_conn_local_port], edx
			.if NET_TCP_CONN_DEBUG > 1
				DEBUG "local port"
				DEBUG_DWORD edx
			.endif


	mov	[eax + tcp_conn_local_seq], dword ptr 0
	mov	[eax + tcp_conn_remote_seq], dword ptr 0
	mov	[eax + tcp_conn_local_seq_ack], dword ptr 0
	mov	[eax + tcp_conn_remote_seq_ack], dword ptr 0

	MUTEX_UNLOCK TCP_CONN

	pop	eax
	pop	edx
	pop	ecx
	# eax = tcp_conn array index, rest unmodified


	# fallthrough

# in: eax = tcp_conn array index
# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: ecx = tcp frame len (incl header)
net_tcp_conn_update:
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "tcp_conn update"
	.endif

	push	eax
	push	edx
	push	ebx

	add	eax, [tcp_connections]

	mov	ebx, [clock_ms]
	mov	[eax + tcp_conn_timestamp], ebx

	mov	ebx, [esi + tcp_seq]
	bswap	ebx
	mov	[eax + tcp_conn_remote_seq], ebx
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "seq"
		DEBUG_DWORD ebx
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	0f
	mov	ebx, [esi + tcp_ack_nr]
	bswap	ebx
	mov	[eax + tcp_conn_local_seq_ack], ebx
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "ack"
		DEBUG_DWORD ebx
	.endif
0:
	pop	ebx
	pop	edx
	pop	eax
	ret


net_tcp_conn_list:
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, esi, ebx, 9f
	printc	11, "tcp/ip "


	.macro TCP_PRINT_ADDR element
		mov	eax, [esi + ebx + \element\()_addr]
		call	net_print_ip
		printchar ':'
		movzx	edx, word ptr [esi + ebx + \element\()_addr]
		xchg	dl, dh
		call	printdec32
	.endm

	#call	screen_pos_mark
	#TCP_PRINT_ADDR tcp_conn_local
	mov	eax, [esi + ebx + tcp_conn_local_addr]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [esi + ebx + tcp_conn_local_port]
	xchg	dl, dh
	call	printdec32

	#mov	eax, 16 + 5 + 3
	#call	print_spaces
	call	printspace

	#call	screen_pos_mark
	#TCP_PRINT_ADDR tcp_conn_remote
	mov	eax, [esi + ebx + tcp_conn_remote_addr]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [esi + ebx + tcp_conn_remote_port]
	xchg	dl, dh
	call	printdec32
	#mov	eax, 16 + 5 + 3 + 2
	#call	print_spaces
	call	printspace

	push	esi
	movzx	esi, byte ptr [esi + ebx + tcp_conn_state]
	call	tcp_conn_print_state$
	pop	esi

	print	" last comm: "
	mov	edx, [clock_ms]
	sub	edx, [esi + ebx + tcp_conn_timestamp]
	call	printdec32
	print	" ms ago"

	call	newline
	call	printspace

	printc 13, "local"
	printc 8 " seq "
	mov	edx, [esi + ebx + tcp_conn_local_seq]
	call	printhex8
	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_local_seq_ack]
	call	printhex8

	printc 13, " remote"
	printc 8, " seq "
	mov	edx, [esi + ebx + tcp_conn_remote_seq]
	call	printhex8
	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_remote_seq_ack]
	call	printhex8

	printc 14, " hndlr "
	mov	edx, [esi + ebx + tcp_conn_handler]
	call	printhex8

	#call	newline	# already at eol

	ARRAY_ENDL
9:
	ret

# out: ax
net_tcp_port_get:
	.data
	TCP_FIRST_PORT = 48000
	tcp_port_counter: .word TCP_FIRST_PORT
	.text32
	mov	ax, [tcp_port_counter]
	push	eax
	inc	ax
	cmp	ax, 0xff00
	jb	0f
	mov	ax, TCP_FIRST_PORT
0:	mov	[tcp_port_counter], ax
	pop	eax
	ret



TCP_DEBUG_COL_RX = 0xf9
TCP_DEBUG_COL_TX = 0xfd
TCP_DEBUG_COL    = 0xf3
TCP_DEBUG_COL2   = 0xf2
TCP_DEBUG_COL3   = 0xf4

.macro TCP_DEBUG_CONN
	push	eax
	push	edx
	pushcolor TCP_DEBUG_COL
	print	"tcp["
	mov	edx, eax
	call	printdec32
	print	"] "
	popcolor
	pop	edx
	pop	eax
.endm

.macro TCP_DEBUG_REQUEST
	pushcolor TCP_DEBUG_COL_RX
	print "tcp["
	color	TCP_DEBUG_COL2
	push	edx
	movzx	edx, word ptr [esi + tcp_sport]
	xchg	dl, dh
	call	printdec32
	color	TCP_DEBUG_COL_RX
	print "->"
	color	TCP_DEBUG_COL2
	movzx	edx, word ptr [esi + tcp_dport]
	xchg	dl, dh
	call	printdec32
	pop	edx
	color	TCP_DEBUG_COL_RX
	print	"]: Rx ["
	push	eax
	mov	ax, [esi + tcp_flags]
	xchg	al, ah
	color	TCP_DEBUG_COL2
	TCP_DEBUG_FLAGS ax
	pop	eax
	printc TCP_DEBUG_COL_RX "] "
	popcolor
.endm

.macro TCP_DEBUG_FLAGS r=ax
	PRINTFLAG ax, TCP_FLAG_NS, "NS "
	PRINTFLAG ax, TCP_FLAG_CWR, "CWR "
	PRINTFLAG ax, TCP_FLAG_ECE, "ECE "
	PRINTFLAG ax, TCP_FLAG_URG, "URG "
	PRINTFLAG ax, TCP_FLAG_ACK, "ACK "
	PRINTFLAG ax, TCP_FLAG_PSH, "PSH "
	PRINTFLAG ax, TCP_FLAG_RST, "RST "
	PRINTFLAG ax, TCP_FLAG_SYN, "SYN "
	PRINTFLAG ax, TCP_FLAG_FIN, "FIN "
.endm

# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_ipv4_tcp_handle:
	# firewall
	call	net_tcp_conn_get
	jc	0f

	.if NET_TCP_DEBUG
		TCP_DEBUG_CONN
		TCP_DEBUG_REQUEST
	.endif

	# known connection
	call	net_tcp_conn_update
	call	net_tcp_handle	# in: eax=tcp_conn idx, ebx=ip, esi=tcp,ecx=len
	ret


0:	# firewall: new connection
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	8f # its not a new or known connection

	.if NET_TCP_DEBUG
		pushcolor TCP_DEBUG_COL_RX
		print	"tcp: Rx SYN "
		color	TCP_DEBUG_COL2
		push	edx
		movzx	edx, word ptr [esi + tcp_dport]
		xchg	dl, dh
		call	printdec32
		pop	edx
		call	printspace
		popcolor
	.endif

	# firewall / services:

	call	net_tcp_service_get	# out: edi = handler
	jc	9f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL, "tcp: ACCEPT SYN"
	.endif
	call	net_tcp_conn_newentry	# in: edx, esi, edi
	call	net_tcp_handle_syn$
	.if NET_TCP_DEBUG
		call	newline
	.endif
	ret

	#
8:	# unknown connection, not SYN
	.if NET_TCP_DEBUG
		TCP_DEBUG_REQUEST
		printc TCP_DEBUG_COL3, "tcp: unknown connection"
	.endif
	jmp	1f
9:	.if NET_TCP_DEBUG
		printc 0x8c, "tcp: DROP SYN: "
	.endif
1:	.if NET_TCP_DEBUG
		mov	eax, [edx + ipv4_src]
		call	net_print_ip
		printc 4, " port "
		movzx	edx, word ptr [esi + tcp_dport]
		xchg	dl, dh
		call	printdec32
		printlnc 4, "unknown port"

		call	net_ipv4_tcp_print
	.endif
	ret

# in: eax = tcp_conn array index
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle:
	# C->S  FIN, ACK
	# S->C  FIN, ACK
	# C->S  ACK
	.if NET_TCP_DEBUG
		printc	TCP_DEBUG_COL_RX, "<"
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	0f
	.if NET_TCP_DEBUG
		printc	TCP_DEBUG_COL_RX, "dup SYN"
	.endif
0:


	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "ACK "
	.endif
	call	net_tcp_conn_update_ack
0:
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_FIN
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "FIN "
	.endif
	# FIN

	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_TX, "tcp: Tx "
	.endif

	push	eax
	add	eax, [tcp_connections]
	inc	dword ptr [eax + tcp_conn_remote_seq]
	or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX
	test	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_TX
	pop	eax
	push	edx
	push	ecx
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_TX, "ACK "
	.endif
	mov	dl, TCP_FLAG_ACK
#	jnz	1f
#	.if NET_TCP_DEBUG
#		printc TCP_DEBUG_COL_TX, "FIN "
#	.endif
#	# XXX
#	or	dl, TCP_FLAG_FIN
1:	xor	ecx, ecx
	# send ACK [FIN]
	call	net_tcp_send
	pop	ecx
	pop	edx
	.if NET_TCP_DEBUG
		call	newline
	.endif
	#ret
########
0:
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_PSH
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "PSH "
	.endif
	call	net_tcp_handle_psh
0:
	.if NET_TCP_DEBUG
		printlnc	TCP_DEBUG_COL_RX, ">"
	.endif
	ret


# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle_psh:
	push	ecx
	push	edx
	push	esi

	# get offset and length of payload
	movzx	edx, byte ptr [esi + tcp_flags]	# headerlen
	shr	edx, 2
	and	dl, ~3
	sub	ecx, edx
	add	esi, edx

	push	eax
	add	eax, [tcp_connections]
	add	[eax + tcp_conn_remote_seq], ecx
	pop	eax
	# send ack
	push	eax
	call	net_tcp_conn_send_ack
	pop	eax

		# UNTESTED
		# in: eax = ip
		# in: edx = [proto] [port]
		# in: esi, ecx: packet
		#mov	dx, [esi + ipv4_protocol]
		#shl	edx, 16	# no port known yet
		#mov	eax, [esp + 4] # edx
		#mov	eax, [eax + ipv4_dst]
		#call	net_socket_deliver

	# call handler

	mov	edi, [tcp_connections]
or edi, edi
jz 10f
	add	edi, eax
	mov	edi, [edi + tcp_conn_handler]
	add	edi, [realsegflat]
jz	9f
	pushad
	call	edi
	popad

0:	pop	esi
	pop	edx
	pop	ecx
	ret
9:	printlnc 4, "net_tcp_handle_psh: null handler"
	# eax = edi = 0; edx=tcp hlen=ok, ecx=0x75.
	jmp	1f
10:	printlnc 4, "net_tcp_handle_psh: no connections"
1:	pushad
	call	net_tcp_conn_list
	popad
	int	1
	jmp	0b

net_tcp_conn_update_ack:
	push	eax
	push	ebx
	add	eax, [tcp_connections]
	mov	ebx, [esi + tcp_ack_nr]
	mov	[eax + tcp_conn_local_seq_ack], ebx
	movzx	ebx, byte ptr [eax + tcp_conn_state]
	test	bl, TCP_CONN_STATE_FIN_TX
	jz	1f
	or	bh, TCP_CONN_STATE_FIN_ACK_RX
1:	test	bl, TCP_CONN_STATE_SYN_TX
	or	bh, TCP_CONN_STATE_SYN_ACK_RX
	or	[eax + tcp_conn_state], bh
	pop	ebx
	pop	eax
	ret


net_tcp_conn_send_ack:
	push	edx
	push	ecx
	xor	dl, dl
	xor	ecx, ecx
	call	net_tcp_send
	pop	ecx
	pop	edx
	ret

# in: esi = tcp frame
# out: edi = handler
net_tcp_service_get:
	.data
	tcp_service_ports: .word 80
	TCP_NUMSERVICES = (. - tcp_service_ports)/2
	tcp_service_handlers: .long net_service_tcp_http
	.text32
	push	eax
	push	ecx
	mov	ax, [esi + tcp_dport]
	xchg	al, ah
	mov	edi, offset tcp_service_ports
	mov	ecx, TCP_NUMSERVICES
	repne	scasw
	pop	ecx
	pop	eax
	stc
	jnz	9f
	sub	edi, offset tcp_service_ports + 2
	mov	edi, [tcp_service_handlers + edi * 4]
	clc
9:	ret


#######################################################################
# HTTP Server
#
.data SECTION_DATA_STRINGS
html:
.ascii "HTTP/1.1 200 OK\r\n"
.ascii "Content-Type: text/html; charset=UTF-8\r\n"
.ascii "Connection: close\r\n"
.ascii "\r\n"
.ascii "<html>\n"
.ascii "  <head>\n"
.ascii "    <style type='text/css'>\n"
.ascii "      .ss { width: 144px; }\n"
.ascii "      .ss:hover { width: 738px; }\n"
.ascii "      dl { padding-left: 1em; }\n"
.ascii "    </style>\n"
.ascii "  </head>\n"
.ascii "  <body>"
.ascii "    <h1>QuRe - Intel Assembly Cloud Operating System</h1>\n"
.ascii "    <i>This webpage is self-hosted</i>"
.ascii "    <ul>\n"
.ascii "      <li>extremely small memory footprint:<ul>\n"
ep1: .space 260, ' '
.ascii "</ul></li>\n"
.ascii "      <li>memory location independent</li>\n"
.ascii "      <li>manually optimized:\n"
.ascii "        <ul>\n"
.ascii "          <li>minimal stack usage</li>\n"
.ascii "          <li>some pipelining</li>\n"
.ascii "          <li>hardware string functions used whenever possible</li>\n"
.ascii "          <li>maximal code reuse - methods and macros</li>\n"
.ascii "        </ul>\n"
.ascii "      </li>\n"
.ascii "    </ul>\n\n"
.ascii "    <h2><a name='s_source'>Source / Issues / Wiki</h2>\n"
.ascii "      <a href='https://github.com/neonics/qure'>GitHub</a>\n"
.asciz "    </code>\n"
html2:
.ascii "  </body>\n"
.asciz "</html>\n"
.text32

# in: eax = tcp_conn array index
# in: esi = request data
# in: ecx = request data len
net_service_tcp_http:
	.if NET_HTTP_DEBUG
		printc 11, "TCP HTTP "
		push	eax
		add	eax, [tcp_connections]
		movzx	edx, word ptr [eax + tcp_conn_remote_port]
		xchg	dl, dh
		mov	eax, [eax + tcp_conn_remote_addr]
		call	net_print_ip
		printchar_ ':'
		call	printdec32
		call	printspace
		pop	eax
	.endif

	call	http_parse_header

	# Send a response
	cmp	edx, -1	# no GET / found in headers
	jz	404f

	.if NET_HTTP_DEBUG
		push	esi
		pushcolor 14
		mov	esi, edx
		call	println
		popcolor
		pop	esi
	.endif

	cmp	word ptr [edx], '/'
	jz	0f	# serve root

	# serve custom file:
	.data SECTION_DATA_STRINGS
	www_docroot$: .asciz "/c/www/"
	WWW_DOCROOT_STR_LEN = . - www_docroot$
	.data SECTION_DATA_BSS
	www_content$: .long 0
	www_file$: .space MAX_PATH_LEN
	.text32
	push	eax
	movzx	eax, byte ptr [boot_drive]
	add	al, 'a'
	mov	[www_docroot$ + 1], al
	pop	eax

	mov	esi, edx
	call	strlen_
	cmp	ecx, MAX_PATH_LEN - WWW_DOCROOT_STR_LEN -1
	jae	414f

	# calculate path
	mov	edi, offset www_file$
	mov	esi, offset www_docroot$
	mov	ecx, WWW_DOCROOT_STR_LEN
	rep	movsb

	mov	edi, offset www_file$
	mov	esi, edx
	inc	esi	# skip leading /
	call	fs_update_path	# edi=base/output, esi=rel
	# strip last char
	mov	byte ptr [edi-1], 0

	# check whether path is still in docroot:
	mov	esi, offset www_docroot$
	mov	edi, offset www_file$
	mov	ecx, WWW_DOCROOT_STR_LEN - 1 # skip null terminator
	repz	cmpsb
	jnz	404f

	.if NET_HTTP_DEBUG > 1
		printc 13, "Serving file: '"
		mov	esi, offset www_file$
		call	print
		printlnc 13, "'"
	.endif

	push	eax	# preserve net_tcp_conn_index
	mov	eax, offset www_file$
	call	fs_openfile
	jc	1f
	push	eax
	call	fs_handle_read	# out: esi, ecx
	pop	eax
	pushf
	call	fs_close
	popf
1:	pop	eax
	jc	404f

	push	esi
	push	ecx
	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
	call	strlen_
	push	edx
	mov	dl, TCP_FLAG_PSH # | TCP_FLAG_FIN
	call	net_tcp_send
	pop	edx
	pop	ecx
	pop	esi

	jmp	10f	# in: esi, ecx

404:
.data SECTION_DATA_STRINGS
www_404$:
.ascii "HTTP/1.1 404 OK\r\n"
.ascii "Content-Type: text/html; charset=UTF-8\r\n"
.ascii "Connection: close\r\n"
.ascii "\r\n"
.ascii "<html><body>File not found!</body></html>"
.byte 0
.text32
	mov	esi, offset www_404$
	jmp	8f

414:	# request uri too long
.data SECTION_DATA_STRINGS
www_414$:
.ascii "HTTP/1.1 414 ERROR\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
.asciz "<html><body>Request uri too long</body></html>"
.text32
	mov	esi, offset www_414$
	jmp	8f

# default root:
0:	# fill in the ep1:
	push	eax
	xor	edx, edx
	mov	edi, offset ep1
	SPRINT "<li>Kernel Size: <b>Code:</b> "
	mov	eax, kernel_code_end - kernel_code_start # realmode_kernel_entry
	call	sprint_size

	SPRINT " <b>Data:</b> "
	mov	eax, kernel_end - data_0_start
	call	sprint_size

	SPRINT " (<b>0:</b> "
	mov	eax, data_0_end - data_0_start
	call	sprint_size

	SPRINT " <b>strings:</b> "
	mov	eax, data_str_end - data_str_start
	call	sprint_size

	SPRINT " <b>bss:</b> "
	mov	eax, data_bss_end - data_bss_start
	call	sprint_size

	SPRINT " <b>other:</b> "
	mov	eax, kernel_end - data_bss_end
	call	sprint_size

	SPRINT ") <b>Total:</b> "
	mov	eax, kernel_end - kernel_code_end
	# kernel_end - realmode_kernel_entry + kernel_end - kernel_signature
	call	sprint_size
	SPRINT "</li>"

	SPRINT "<li>Heap: "
	mov	eax, [mem_heap_size]
	call	sprint_size

	SPRINT " <b>Allocated:</b> "
	mov	eax, [mem_heap_alloc_start]
	sub	eax, [mem_heap_start]
	call	sprint_size

	SPRINT " <b>Free:</b> "
	sub	eax, [mem_heap_size]
	neg	eax
	call	sprint_size
	SPRINT "</li>"

	pop	eax

	mov	esi, offset html
	call	strlen_	# in: esi; out: ecx

	push	edx
	mov	dl, TCP_FLAG_PSH # | TCP_FLAG_FIN
	call	net_tcp_send
	pop	edx

	mov	esi, offset html2
8:	call	strlen_

10:	cmp	ecx, 1024 # 1536 - TCP_HEADER_LEN - ETH_HEADER_LEN
	jb	0f

	push	ecx
	mov	ecx, 1024 # 1536 - TCP_HEADER_LEN - ETH_HEADER_LEN
	push	edx
	mov	dl, TCP_FLAG_PSH
	call	net_tcp_send
	pop	edx
	pop	ecx
	add	esi, 1024 # 1536 - TCP_HEADER_LEN - ETH_HEADER_LEN
	sub	ecx, 1024 # 1536 - TCP_HEADER_LEN - ETH_HEADER_LEN
	ja	10b
	jz	9f

0:	push	edx
	mov	dl, TCP_FLAG_PSH # | TCP_FLAG_FIN
	call	net_tcp_send
	pop	edx

9:	push	edx
	xor	ecx, ecx
	mov	dl, TCP_FLAG_FIN
	call	net_tcp_send
	pop	edx
	ret


# in: esi = header
# in: ecx = header len
# out: edx = -1 or resource name (GET /x -> /x)
http_parse_header:
	push	eax
	.if NET_HTTP_DEBUG > 1
		pushcolor 15
	.endif
	mov	edx, -1		# the file to serve
	mov	edi, esi	# mark beginning
0:	lodsb
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
	.if NET_HTTP_DEBUG > 1
		call	newline
		color	15
	.endif
	call	http_parse_header_line$	# update edx if GET /...
	mov	edi, esi	# mark new line beginning
	jmp	1f

2:	.if NET_HTTP_DEBUG > 1
		call	printchar
		color	7
	.endif

1:	loop	0b
	.if NET_HTTP_DEBUG > 1
		popcolor
		call	newline
	.endif
	pop	eax
	ret



# in: edi = start of header line
# in: esi = end of header line
# in: edx = known value (-1) to compare against
# out: edx = resource identifier (if request match): 0 for root, etc.
http_parse_header_line$:
	push	esi
	push	ecx
	mov	ecx, esi
	sub	ecx, edi
	mov	esi, edi

	.if NET_HTTP_DEBUG > 2
		push esi
		push ecx
		printchar '<'
		call nprint
		printchar '>'
		pop ecx
		pop esi
	.endif

	LOAD_TXT "GET /", edi
	push	ecx
	push	esi
	mov	ecx, 5
	repz	cmpsb
	pop	esi
	pop	ecx
	jnz	9f

	add	esi, 4		# preserve the leading /
	sub	ecx, 4
	mov	edx, esi	# start of resource
0:	lodsb
	cmp	al, ' '
	jz	0f
	cmp	al, '\n'
	jz	0f
	cmp	al, '\r'
	jz	0f
	loop	0b
	# hmmm
0:	mov	[esi - 1], byte ptr 0
	mov	esi, edx

	.if NET_HTTP_DEBUG > 1
	print "Resource: <"
	call	print
	println ">"
	.endif

9:	pop	ecx
	pop	esi
	ret

# in: eax = tcp_conn array index
# in: dl = TCP flags (FIN)
# in: esi = payload
# in: ecx = payload len
net_tcp_send:
	cmp	ecx, 1536 - TCP_HEADER_SIZE - ETH_HEADER_SIZE
	jb	0f
	printlnc 4, "tcp payload too large"
	stc
	ret
0:

	push	esi
	push	eax
	push	ebp
	lea	ebp, [esp + 4]

	NET_BUFFER_GET
	jc	9f
	push	edi

	push	esi
	push	edx
	push	ecx
	push	eax
	add	eax, [tcp_connections]
	mov	eax, [eax + tcp_conn_remote_addr]
#	mov	eax, [edx + ipv4_src]
	mov	dx, IP_PROTOCOL_TCP
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	add	ecx, TCP_HEADER_SIZE
	call	net_ipv4_header_put # mod eax, esi, edi, ebx
	pop	eax
	pop	ecx
	pop	edx
	pop	esi

	# add tcp header
	push	edi
	push	ecx
	push	eax
	mov	ecx, TCP_HEADER_SIZE
	xor	eax, eax
	rep	stosb
	pop	eax
	pop	ecx
	pop	edi

	# copy connection state
	push	ebx
	add	eax, [tcp_connections]

	mov	ebx, [eax + tcp_conn_local_port]
	mov	[edi + tcp_sport], ebx

	mov	ebx, [eax + tcp_conn_local_seq]
	bswap	ebx
	mov	[edi + tcp_seq], ebx
	add	[eax + tcp_conn_local_seq], ecx

	mov	ebx, [eax + tcp_conn_remote_seq]
	mov	[eax + tcp_conn_remote_seq_ack], ebx
	bswap	ebx
	mov	[edi + tcp_ack_nr], ebx # dword ptr 0	# maybe ack
	pop	ebx


	mov	ax, TCP_FLAG_ACK| ((TCP_HEADER_SIZE/4)<<12)
	or	al, dl	# additional flags
	xchg	al, ah
	mov	[edi + tcp_flags], ax

	.if NET_TCP_DEBUG
		pushcolor TCP_DEBUG_COL_TX
		print "[Tx "
		xchg	al, ah
		TCP_DEBUG_FLAGS ax
		print "]"
		popcolor
	.endif

	mov	[edi + tcp_windowsize], word ptr 0x20

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0

	jecxz	0f
	push	esi
	push	edi
	push	ecx
	add	edi, TCP_HEADER_SIZE
	rep	movsb
	pop	ecx
	pop	edi
	pop	esi
0:
	# calculate checksum

	# in: eax = tcp conn
	mov	eax, [ebp]
	# in: esi = tcp frame pointer
	mov	esi, edi
	# in: ecx = tcp frame len
	add	ecx, TCP_HEADER_SIZE
	call	net_tcp_checksum

	# send packet

	pop	esi
	add	ecx, edi	# add->mov ?
	sub	ecx, esi
	call	[ebx + nic_api_send]
	jc	9f

	# update flags
	add	eax, [tcp_connections]
	mov	dh, [eax + tcp_conn_state]

	test	dl, TCP_FLAG_FIN
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_TX
1:	test	dh, TCP_CONN_STATE_FIN_RX
	jz	1f
	test	dl, TCP_FLAG_ACK
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_ACK_TX
1:	or	[eax + tcp_conn_state], dh

9:	pop	ebp
	pop	eax
	pop	esi
	ret


# in: eax = tcp_conn array index
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle_syn$:
	pushad
	push	ebp
	mov	ebp, esp
	push	eax


#### accept tcp connection

	# send a response

	_TCP_OPTS = 12	# mss (4), ws (3), nop(1), sackp(2), nop(2)
	_TCP_HLEN = (TCP_HEADER_SIZE + _TCP_OPTS)

	NET_BUFFER_GET
	jc	9f
	push	edi

	mov	eax, [edx + ipv4_src]
	push	edx
	mov	dx, IP_PROTOCOL_TCP
	push	esi
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	mov	ecx, _TCP_HLEN
	call	net_ipv4_header_put # mod eax, esi, edi
	pop	esi
	pop	edx
	jc	8f

	# add tcp header
	push	edi
	push	ecx
	mov	ecx, _TCP_HLEN
	xor	al, al
	rep	stosb
	pop	ecx
	pop	edi

	mov	eax, [esi + tcp_sport]
	rol	eax, 16
	mov	[edi + tcp_sport], eax

	mov	eax, [esi + tcp_seq]
	bswap	eax
	inc	eax
		push	edx
		mov	edx, [ebp - 4]
		add	edx, [tcp_connections]
		mov	[edx + tcp_conn_remote_seq_ack], eax
		or	[edx + tcp_conn_state], byte ptr TCP_CONN_STATE_SYN_RX
	bswap	eax
	mov	[edi + tcp_ack_nr], eax

		# calculate a seq of our own
		mov	eax, [edx + tcp_conn_local_seq]
		bswap	eax
		# SYN counts as one seq
		inc	dword ptr [edx + tcp_conn_local_seq]
		pop	edx

	mov	[edi + tcp_seq], eax

	mov	ax, TCP_FLAG_SYN | TCP_FLAG_ACK | ((_TCP_HLEN/4)<<12)
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_TX, "tcp: Tx SYN ACK"
	.endif
	xchg	al, ah
	mov	[edi + tcp_flags], ax

	mov	ax, [esi + tcp_windowsize]
	mov	[edi + tcp_windowsize], ax

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0


	# tcp options

	# in: esi = source tcp frame
	# in: edi = target tcp frame
	.if 1
	add	esi, TCP_HEADER_SIZE
	mov	esi, edi
	add	edi, TCP_HEADER_SIZE
	mov	eax, 0x01010101	# 'nop'
	stosd
	stosd
	stosd
	.else
	call	net_tcp_copyoptions
	.endif

	# calculate checksum

	# in: eax = tcp_conn
	mov	eax, [ebp - 4]
	# in: esi = tcp frame pointer
	# in: ecx = tcp frame len
	mov	ecx, _TCP_HLEN
	call	net_tcp_checksum

	# send packet

	pop	esi
	NET_BUFFER_SEND

9:	pop	eax
	jc	1f
	add	eax, [tcp_connections]
	or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_SYN_ACK_TX | TCP_CONN_STATE_SYN_TX
1:	pop	ebp
	popad
	ret
8:	pop	edi
	jmp	9b

# in: esi = source tcp frame
# in: edi = target tcp frame
# out: edi = end of tcp header
# out: esi = target tcp frame
net_tcp_copyoptions:
	push	ecx
	push	edx
	push	eax
	push	ebx

	# scan incoming options

	# get the source options length
	movzx	ecx, byte ptr [esi + tcp_flags]
	shr	cl, 4
	shl	cl, 2
	sub	cl, 20

	.if NET_TCP_OPT_DEBUG > 1
		DEBUG_WORD cx
	.endif


	xor	edx, edx	# contains MSS and WS

	add	esi, TCP_HEADER_SIZE
0:
	.if NET_TCP_OPT_DEBUG > 1
		call newline
		DEBUG_DWORD ecx
	.endif

	dec	ecx
	jle	0f
	#jz	0f
	#jc	0f
	lodsb

	.if NET_TCP_OPT_DEBUG > 1
		printc 14, "OPT "
		DEBUG_BYTE al
	.endif

	or	al, al	# TCP_OPT_END
	jz	0f
	cmp	al, TCP_OPT_NOP
	jz	0b
	cmp	al, TCP_OPT_MSS
	jnz	1f
		sub	ecx, 3
		jb	0f
		lodsb
		sub	al, 4
		jnz	0f
		lodsw
		mov	dx, ax

	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "MSS"
		DEBUG_WORD dx
		DEBUG_WORD cx
	.endif

	jmp	0b
1:
	cmp	al, TCP_OPT_WS
	jnz	1f
		sub	ecx, 2
		jb	0f
		lodsb
		sub	al, 3
		jnz	0f
		lodsb
		rol	edx, 8
		mov	dl, al
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "WS"
		DEBUG_BYTE dl
	.endif
		ror	edx, 8
	jmp	0b
1:
	cmp	al, TCP_OPT_SACKP
	jnz	1f
		dec	ecx
		jb	0f
		lodsb
		rol	edx, 16
		mov	dl, al
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "SACKP"
		DEBUG_BYTE dl
	.endif
		ror	edx, 16
	jmp	0b

1:
	cmp	al, TCP_OPT_SACK
	jz	2f
	cmp	al, TCP_OPT_TSECHO
	jz	2f
	cmp	al, TCP_OPT_ACR
	jz	2f
	cmp	al, TCP_OPT_ACD
	jz	2f
	jmp	0b

2:
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "skip-opt"
		DEBUG_BYTE al
	.endif

	dec	ecx
	jz	0f
	lodsb
	sub	al, 2
	jz	0b
	sub	cl, al
	ja	0b
0:
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "opts done"
		DEBUG_DWORD ecx
		call	newline
	.endif

	# set the options:  edx = [8:WS][8:00][16:MSS]

	mov	esi, edi	# return value

	add	edi, TCP_HEADER_SIZE

	push	edi
	mov	al, TCP_OPT_NOP
	mov	ecx, _TCP_OPTS
	rep	stosb
	pop	edi

	or	dx, dx
	jz	1f

	# MSS
	mov	[edi], byte ptr TCP_OPT_MSS
	mov	[edi + 1], byte ptr 2+2
	mov	[edi + 2], word ptr 0xb405
1:
	add	edi, 4
	rol	edx, 8
	or	dl, dl
	jz	1f
	# WS
	mov	[edi], byte ptr TCP_OPT_WS
	mov	[edi + 1], byte ptr 2 + 1
	mov	[edi + 2], dl # byte ptr 7	# * 128
	# nop
	mov	[edi + 3], byte ptr TCP_OPT_NOP
1:
	add	edi, 4

	rol	edx, 8
	or	dl, dl
	jz	1f
	mov	[edi], byte ptr TCP_OPT_SACKP
	mov	[edi + 1], dl
	mov	[edi + 2], byte ptr TCP_OPT_NOP
	mov	[edi + 3], byte ptr TCP_OPT_NOP
1:
	add	edi, 4


	pop	ebx
	pop	eax
	pop	edx
	pop	ecx
	ret

# in: eax = tcp_conn array index
# in: esi = tcp frame pointer
# in: ecx = tcp frame len (header and data)
net_tcp_checksum:
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
	add	eax, [tcp_connections]
#	lea	esi, [edx + ipv4_src]
	lea	esi, [eax + tcp_conn_local_addr]
	xor	edx, edx
	xor	eax, eax
	# ipv4 src, ipv4 dst
	.rept 4
	lodsw
	add	edx, eax
	.endr
	add	edx, 0x0600	# tcp protocol + zeroes

	#xchg	cl, ch		# headerlen + datalen
	shl	ecx, 8	# hmmm
	add	edx, ecx
	shr	ecx, 8
	pop	esi

	# esi = start of ipv4 frame (saved above)
	# deal with odd length:
	mov	word ptr [esi + ecx], 0	# just in case
	inc	ecx
	shr	ecx, 1

1:	mov	edi, offset tcp_checksum	#
	call	protocol_checksum_

	pop	eax
	pop	ecx
	pop	edx
	pop	edi
	pop	esi
	ret

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




net_ivp4_icmp_print:
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

	# in: edi = out packet
	NET_BUFFER_GET
	jc	9f
	push	edi

	# set up ethernet and ip frame

	push	esi
	# in: eax = destination ip
	mov	eax, [edx + ipv4_src]
	# in: esi = destination mac
	# in: ebx = nic object (for src mac & ip (ip currently static))
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src]

# FIXME bypass arp lookup - this code is triggered from the NIC ISR and thus
# cannot rely on IRQ's for packet Tx/Rx for the ARP protocol.
#call arp_table_put_mac

	# in: dl = ipv4 sub-protocol
	mov	dx, IP_PROTOCOL_ICMP
	# in: cx = payload length
	call	net_ipv4_header_put # in: dl, ebx, edi, eax, esi, cx
	pop	esi
	jc	1f

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

	.if NET_ICMP_DEBUG
		printlnc 11, "Sending ICMP PING response"
	.endif

	pop	esi
	mov	ecx, ICMP_HEADER_SIZE + IPV4_HEADER_SIZE + ETH_HEADER_SIZE + 32
	call	[ebx + nic_api_send]
9:	ret
1:	pop	esi
	ret

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


net_ipv4_udp_print:
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

	cmp	[esi + udp_sport], word ptr 53 << 8	# DNS
	jz	net_dns_print
	cmp	[esi + udp_sport], dword ptr ( (67 << 8) | (68 << 24))
	jz	net_dhcp_print
	cmp	[esi + udp_sport], dword ptr ( (68 << 8) | (67 << 24))
	jz	net_dhcp_print

	# add	esi, UDP_HEADER_SIZE
	ret

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len (incl udp header)
ph_ipv4_udp:
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

	cmp	[esi + udp_sport], word ptr 53 << 8	# DNS
	jz	1f	#net_dns_print
	cmp	[esi + udp_dport], word ptr 53 << 8	# DNS
	jz	net_dns_service
	cmp	[esi + udp_sport], dword ptr ( (67 << 8) | (68 << 24))
	jz	ph_ipv4_udp_dhcp_s2c
	cmp	[esi + udp_sport], dword ptr ( (68 << 8) | (67 << 24))
	jz	ph_ipv4_udp_dhcp_c2s

	LOAD_TXT "unknown port", eax
9:	printc 4, "ipv4_udp: dropped packet: "
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


###############################################################################
# DNS
#
# RFC 1035
#
# Messages over UDP follow the below format.
# Messages over TCP are prefixed with a word indicating the message length,
# not counting the word.

.struct 0	# max UDP payload len: 512 bytes
dns_tid:	.word 0	# transaction id
dns_flags:	.word 0	# 0001 = standard query (0100)
	DNS_FLAG_QR		= 1 << 15	# 0=query, 1=response
	DNS_OPCODE_SHIFT	= 11
	DNS_OPCODE_MASK 	= 0b1111 << DNS_OPCODE_SHIFT
	DNS_OPCODE_STDQ		= 0 << DNS_OPCODE_SHIFT	# std query
	DNS_OPCODE_IQUERY	= 1 << DNS_OPCODE_SHIFT	# inverse query
	DNS_OPCODE_STATUS	= 2 << DNS_OPCODE_SHIFT	# server status request
	DNS_FLAG_AA		= 1 << 10	# (R) authoritative answer
	DNS_FLAG_TC		= 1 << 9	# (Q,R) truncation
	DNS_FLAG_RD		= 1 << 8	# (Q->R) recursion desired
	DNS_FLAG_RA		= 1 << 7	# (A) recursion avail
	DNS_FLAG_Z		= 0b110 << 4	# reserved
	DNS_FLAG_NO_AUTH_ACCEPT	= 1 << 4 # non-authenticated data: 0=unacceptbl
	DNS_RCODE_SHIFT		= 0
	DNS_RCODE_MASK		= 0b1111	# (R)
	DNS_RCODE_OK		= 0		# no error
	DNS_RCODE_FORMAT_ERR	= 1		# server unable to interpret
	DNS_RCODE_SERVER_FAIL	= 2		# problem with name server
	DNS_RCODE_NAME_ERR	= 3		# (auth ns): name doesn't exist
	DNS_RCODE_NOT_IMPL	= 4		# query kind not implemented
	DNS_RCODE_REFUSED	= 5		# policy restriction


dns_questions:	.word 0	# nr of questions
dns_answer_rr:	.word 0	# answer RRs
dns_auth_rr:	.word 0	# authorit RRs
dns_add_rr:	.word 0	# additional RRs
dns_queries:	# questions, answers, ...

# Question format:
# QNAME: seq of labels (pascal style), zero label term
# QTYPE: word; QCLASS: word
#
# Example: format for 'foo.nl' IN A request:
# .byte 3 'foo' 2 'nl' 0
# .word type	# 0001 = A
# .word class	# 0001 = IN

# RR (resource record) format: answer, authority, additional:
# NAME: domain name to which this record pertains
# TYPE: word: DNS_TYPE_..
# CLASS: word: DNS_CLASS_..
# TTL: dword: seconds
# RDLEN: word: length in bytes of RDATA
# RDATA: resource data depending on TYPE and CLASS; for IN A, 4 byte IPv4 addr.
#
# Compression: word [11 | OFFSET ]
# domain name labels can be compressed: a word, high 2 bits 1,
# refers to a prior occurrence.
# Since labels must be < 64 len, 01xxxxxx/10xxxxxxxx (reserved), 11xxxxxx
# indicates reference.
# The offset is relative to the DNS payload frame (i.e. offset 0 is first
# byte of dns_tid).
# Valid names:
# - sequence of labels, zero octet terminated (root: no labels, zero octet)
# - a pointer
# - sequence of labels ending with pointer

DNS_TYPE_A	= 1	# host address
DNS_TYPE_NS	= 2	# authoritative name server
# MD=3, mail destination; MF = 4, mail forwarder: both obsolete, use MX
DNS_TYPE_CNAME	= 5	# canonical name for alias
DNS_TYPE_SOA	= 6	# start of zone of authority
# experimental: MB=7, mailbox domain
# experimental: MG=8, mail group member
# experimental: MR=9, mail rename domain
# experimental: NULL = 10 - null RR
DNS_TYPE_WKS	= 11	# well-known service description
DNS_TYPE_PTR	= 12	# domain name pointer
DNS_TYPE_HINFO	= 13	# host information
DNS_TYPE_MINFO	= 14	# mailbox or mail list information
DNS_TYPE_MX	= 15	# mail exchange
DNS_TYPE_TXT	= 16	# text strings

# QTYPE is superset of TYPE: query type, in question part of query:
DNS_QTYPE_AXFR	= 252	# request for transfer of entire zone
DNS_QTYPE_MAILB	= 253	# request for mailbox related records (MB, MG, MR)
DNS_QTYPE_MAILA	= 254	# request for mail agent RRs (obsolete, use MX)
DNS_QTYPE_ALL	= 255	# request for all records

# resource record class identifiers:
DNS_CLASS_IN	= 1	# internet
DNS_CLASS_CS	= 2	# CSNET class - obsolete
DNS_CLASS_CH	= 3	# CHAOS class
DNS_CLASS_HS	= 4	# Hesiod

# QCLASS, superset of CLASS: appear in question section of query
DNS_QCLASS_ALL	= 255	# any QCLASS

DNS_HEADER_SIZE = .
.text32

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
net_dns_print:
	push	edi
	push	esi
	push	edx
	push	ecx

	add	esi, offset UDP_HEADER_SIZE
#	test	byte ptr [esi + dns_flags], 0x80
#	jz	1f
#	DEBUG "Response"
#	# check pending requests

6:
	printc COLOR_PROTO, "   DNS "
	printc COLOR_PROTO_LOC, "tid "
	mov	dx, [esi + dns_tid]
	call	printhex4
	printc COLOR_PROTO_LOC, " flags "
	mov	dx, [esi + dns_flags]
	xchg	dl, dh
	call	printhex4
	call	printspace
	PRINTFLAG dx, DNS_FLAG_QR, "Q", "R"
	PRINTFLAG dx, DNS_FLAG_TC, "T", " "
	PRINTFLAG dx, DNS_FLAG_RD, "r", " "
	PRINTFLAG dx, DNS_FLAG_NO_AUTH_ACCEPT, "A", "U"
	and	dx, DNS_OPCODE_MASK
	shr	dx, DNS_OPCODE_SHIFT
	printc COLOR_PROTO_LOC, " op "
	call	printhex2

	printc COLOR_PROTO_LOC, " #Q "
	movzx	edx, word ptr [esi + dns_questions]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Ans RR "
	mov	dx, [esi + dns_answer_rr]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Auth RR "
	mov	dx, [esi + dns_auth_rr]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Addt RR "
	mov	dx, [esi + dns_add_rr]
	xchg	dl, dh
	call	printdec32
	call	newline

#	mov	ax, [esi + dns_questions]
#	mov	bx, [esi + dns_answer_rr]
#	cmp	ax, bx
#	jnz	2f

	mov	edi, esi	# remember dns frame
	add	esi, DNS_HEADER_SIZE

	mov	eax, ecx
	add	eax, edi
	push	eax	# end of packet
########
	movzx	ecx, word ptr [edi + dns_questions]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	printc COLOR_PROTO_LOC, "    Question "
	call	dns_print_question$
	pop	ecx
	jmp	0b
1:
########
	movzx	ecx, word ptr [edi + dns_answer_rr]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	printc COLOR_PROTO_LOC, "    Answer "
	call	dns_print_answer$
	pop	ecx
	jmp	0b
1:
########
	pop	eax

	pop	ecx
	pop	edx
	pop	esi
	pop	edi
	ret

2:	printlnc 4, "dns: questions != answers"
	ret


dns_print_question$:
	lodsb	# length of text segment (domain name part)
3:	movzx	ecx, al
0:	lodsb
	call	printchar
	loop	0b
	mov	al, '.'
	call	printchar

	lodsb
	or	al, al
	jnz	3b

	print " type "
	lodsw
	mov	dx, ax
	call	printhex4
	print " class "
	lodsw
	mov	dx, ax
	call	printhex4
	call	newline
	ret

dns_print_answer$:
	lodsw	# c0 0c: reference to name
	mov	dx, ax
	call	printhex4

	print " type "
	lodsw
	mov	dx, ax
	xchg	dl, dh
	call	printhex4

	print " class "
	lodsw
	mov	dx, ax
	xchg	dl, dh
	call	printhex4

	print " ttl "
	lodsd
	bswap	eax
	mov	edx, eax
	call	printdec32

	print " len "
	xor	eax, eax
	lodsw
	xchg	al, ah
	cmp	ax, 4	# ipv4
	jnz	1f
	lodsd
	call	net_print_ip
	call	newline
	ret

1:	mov	ecx, eax
0:	lodsb
	movzx	edx, al
	call	printdec32
	mov	al, ':'
	call	printchar
	loop	0b
	call	newline
	ret

# in: esi: RR ptr in DNS message - label
# in: edi: ptr to buffer to contain domain name
# in: ebp: end of buffer
dns_parse_name$:
	push	eax
	push	ecx
0:	lodsb
	movzx	ecx, al
	jecxz	1f

	# stack verify:
	lea	eax, [ecx + edi]
	cmp	eax, ebp
	mov	al, DNS_RCODE_SERVER_FAIL
	jae	9f

	rep	movsb
	mov	al, '.'
	stosb
	jmp	0b
1:	stosb
	clc
9:	pop	ecx
	pop	eax
	ret
# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
net_dns_service:
	.if 1#NET_DNS_DEBUG
		PRINTLN "Servicing DNS request"
		call	net_dns_print
	.endif

	add	esi, UDP_HEADER_SIZE

	push	esi
	lea	eax, [esi + ecx]
	push	eax	# for sanity check
	push	edx
	push	ebp
	mov	ebp, esp
	push	dword ptr 0	# question size
	sub	esp, 80	# max domain name len
	mov	edi, esp
	mov	edx, edi
	mov	ax, [esi + dns_flags]
	xchg	al, ah
	and	ax, DNS_FLAG_QR | DNS_OPCODE_MASK
	mov	al, DNS_RCODE_FORMAT_ERR
	jnz	9f

	movzx	ecx, word ptr [esi + dns_questions]
	xchg	cl, ch

	add	esi, DNS_HEADER_SIZE
	mov	[ebp - 4], esi	# question size

	# check domain
	call	dns_parse_name$
	jc	9f

	lodsd		# type, class

	sub	[ebp -4], esi		# update question len
	neg	dword ptr [ebp -4]

	bswap	eax	# [class][type]
	cmp	eax, 0x00010001
	mov	al, DNS_RCODE_NOT_IMPL
	jnz	9f

		mov	esi, edx

		LOAD_TXT "cloud.neonics.com"
		call	strlen_
		mov	edi, edx
		repz	cmpsb
		mov	al, DNS_RCODE_NAME_ERR
		jnz	9f

			xor	al, al
			cmp	dword ptr [internet_ip], 0
			jnz	1f
			push	esi
			LOAD_TXT "cloudns.neonics.com"
			call	dns_resolve_name
			pop	esi
			or	eax, eax
			mov	[internet_ip], eax
			mov	al, 0
			jnz	9f
			.if NET_DNS_DEBUG
				printlnc 4, "dns: cannot resolve"
			.endif
			mov	al, DNS_RCODE_SERVER_FAIL
	1:

# in: al = DNS_RCODE_*. 0 means, no error; otherwise no payload after DNS_HEADER
# in: [ebp + 12]: incoming DNS frame
# in: [ebp + 4]: incoming IPv4 frame
# in: ebx: nic
9:	NET_BUFFER_GET
	push	edi
debug_byte al
	# calculate payload len:
	mov	ecx, [ebp - 4]	# question size
	or	al, al
	jnz	1f		# on error, no answers
	# add answer len:
	add	ecx, 16		# label:2 type:2 class:2 ttl:4 len:2 addr:4
1:
	# ETH, IP frame

	add	ecx, UDP_HEADER_SIZE + DNS_HEADER_SIZE
	mov	dx, IP_PROTOCOL_UDP
	push	eax
	mov	eax, [ebp + 4]	# ipv4 frame
	mov	eax, [eax + ipv4_src]
	push	esi
	call	net_ipv4_header_put
	pop	esi
	pop	eax
	jc	9f
# XXXX
	mov	esi, [ebp + 12]	# incoming dns frame
	# UDP frame

	push	eax
	mov	eax, [esi - UDP_HEADER_SIZE + udp_sport]
	bswap	eax
	ror	eax, 16
	push	ecx
	sub	ecx, UDP_HEADER_SIZE
	call	net_udp_header_put
	pop	ecx
	pop	eax

	# DNS frame

	# al & 0xf is response code:
	mov	ah, al
	and	ah, 0b1111	# response code
	mov	al, 1 << 7	# response

	mov	[edi + dns_flags], ax
	# put the DNS header:
	mov	dx, [esi + dns_tid]
	mov	[edi + dns_tid], dx
	mov	[edi + dns_questions], word ptr 1 << 8
	mov	[edi + dns_answer_rr], word ptr 0
	jnz	1f	# from and, see above
	mov	[edi + dns_answer_rr], word ptr 1 << 8
1:	mov	[edi + dns_auth_rr], word ptr 0
	mov	[edi + dns_add_rr], word ptr 0
	add	edi, DNS_HEADER_SIZE

	# offset of answer relative to DNS frame, which begins with label
	mov	edx, DNS_HEADER_SIZE

	# copy the question:
	add	esi, DNS_HEADER_SIZE
	mov	ecx, [ebp - 4]	# question label size
	rep	movsb

	or	ah, ah
	jnz	1f
	# copy answer:
	mov	ax, dx
	or	ah, 0b11000000
	xchg	al, ah
	stosw	# label ptr
	mov	eax, 0x01000100
	stosd	# type, class
	mov	eax, 3600	# 1 hour
	bswap	eax
	stosd	# ttl
	mov	ax, 0x0400
	stosw	# data len

	.data SECTION_DATA_BSS
	internet_ip: .long 0
	.text32
	mov	eax, [internet_ip]
	stosd
1:
	pop	esi
	NET_BUFFER_SEND	# uses edi-esi for ecx
	jmp	1f
9:	pop	edi
	printlnc 4, "error constructing response packet"
	# TODO: net_buffer_release
1:
	mov	esp, ebp
	pop	ebp
	pop	edx
	pop	eax
	pop	esi
	ret

# in: esi = domain name
# out: eax = ipv4 address
dns_resolve_name:
	# receives all dns packets....
	push	ebx
	mov	ebx, IP_PROTOCOL_UDP << 16
	call	net_udp_port_get
	mov	bx, dx
	xor	eax, eax	# ip
	call	socket_open
	pop	ebx
	jc	9f

	push	edi
	push	edx
	push	ecx
	push	ebx
	mov	edi, esi

	call	strlen_
	mov	edx, ecx
	call	net_dns_request

	mov	ecx, 2 * 1000
	call	socket_read	# in: eax, ecx; out: esi, ecx
	jc	8f

#	printlnc 11, "socket UDP read:"
	push	eax
#	call	net_dns_print

		add	esi, UDP_HEADER_SIZE

		mov	ebx, esi	# for compressed rr ref

	#	push	esi

		# verify flag
		mov	ax, [esi + dns_flags]
		xchg	al, ah
		and	ax, DNS_FLAG_QR | DNS_RCODE_MASK
		cmp	ax, DNS_FLAG_QR
		jnz	1f

		# verify question/answer:
		cmp	dword ptr [esi + dns_questions], 0x01000100
		jnz	1f


		push	ecx
		mov	ecx, edx
		add	esi, DNS_HEADER_SIZE
		mov	edx, esi	# remember for compressed names
		# validate question
		push	edi
		push	ebp
		mov	ebp, esp
		sub	esp, 80
		mov	edi, esp

		push	edi
		call	dns_parse_name$	# in: edi, ebp; in: esi
		pop	edi
		jc	2f


		push	esi
		mov	esi, [ebp + 4]	# edi on stack=orig esi backup=name
		repz	cmpsb
		pop	esi
		stc
		jnz	2f
		cmp	word ptr [edi], '.'
		stc
		jnz	2f
		clc

	2:	mov	esp, ebp
		pop	ebp
		pop	edi
		pop	ecx
		jc	1f
		lodsd	# load type/class
		cmp	eax, 0x01000100
		jnz	1f

		# parse answer

	######## compare answer rr name, type, class
		xor	eax, eax
		lodsb
		cmp	al, 0b11000000
		jb	2f
		mov	ah, al
		and	ah, 0b00111111
		lodsb
		add	eax, ebx
		cmp	eax, edx	# question rr
		jnz	1f
		lodsd
		cmp	eax, 0x01000100	# type, class
		jnz	1f
		jmp	3f
	2:	# noncompressed name: compare label, type, class
		push	edi
		push	ecx
		dec	esi	# unread byte
		mov	ecx, esi
		sub	ecx, edx	# start of question rr
		mov	edi, edx
		repz	cmpsb
		pop	ecx
		pop	edi
		jnz	1f
	3:
	########
		lodsd	# ttl - ignore
		lodsw	# addr len
		cmp	ax, 0x0400
		jnz	1f
		lodsd	# ip
		mov	edx, eax

		jmp	7f
	1:	printlnc 4, "DNS error: wrong response"
		xor	edx, edx
7:
	pop	eax

0:	call	socket_close
	mov	eax, edx
	.if NET_DNS_DEBUG
		DEBUG_DWORD eax, "resolve: ip"
	.endif
	pop	ebx
	pop	ecx
	pop	edx
	pop	edi
	ret

8:	printlnc 4, "socket read timeout"
	xor	edx, edx
	jmp	0b

9:	printlnc 4, "failed to open UDP socket"
	xor	eax, eax
	ret

# in: eax = socket
# in: esi = name to resolve
# in: ecx = length of name
net_dns_request:
	.data
	dns_server_ip: .byte 192, 168, 1, 1
	.text32
	push	edi
	push	esi
	push	eax
	push	ebx
	push	ecx
	push	edx

	NET_BUFFER_GET
	push	edi

	# 6:
	# 1 byte trailing zero for domain name
	# 1 byte leading zero for first name-part
	# (the '.' in the domain names are used for lengths)
	# 2 bytes for the Type
	# 2 bytes for the Class
	add	ecx, DNS_HEADER_SIZE + 6
	#mov	ecx, 27

	push	ecx
	push	eax
	# in: cx = payload length (without ethernet/ip frame)
	add	ecx, UDP_HEADER_SIZE
	# in: eax = destination ip
	mov	eax, [dns_server_ip]
	# in: edi = out packet
	# in: ebx = nic object (for src mac & ip (ip currently static))
	# in: dl = ipv4 sub-protocol
	mov	dx, IP_PROTOCOL_UDP
	push	esi
	call	net_ipv4_header_put
	pop	esi
	pop	eax
	pop	ecx
	jc	9f

#	call	net_udp_port_get
	call	socket_get_lport	# in: eax; out: edx=dx
	mov	ax, dx
	shl	eax, 16
	mov	ax, 0x35 	# DNS port 53
	push	ecx
	call	net_udp_header_put
	pop	ecx

	# put the DNS header:
	mov	[edi + dns_tid], dword ptr 0x0000
	mov	[edi + dns_flags], word ptr 1
	mov	[edi + dns_questions], word ptr 1 << 8
	mov	[edi + dns_answer_rr], word ptr 0
	mov	[edi + dns_auth_rr], word ptr 0
	mov	[edi + dns_add_rr], word ptr 0
	add	edi, DNS_HEADER_SIZE


2:	mov	edx, edi	# remember offs
	inc	edi
	xor	ah, ah
0:	lodsb
	cmp	al, '.'
	jnz	1f
	# have dot. fill preceeding length
	mov	[edx], ah
	jmp	2b
1:	stosb
	inc	ah
	or	al, al
	jnz	0b
	dec	ah
	mov	[edx], ah

#	mov	al, 6
#	stosb
#	LOAD_TXT "google"
#	movsd
#	movsw
#	mov	al, 2
#	stosb
#	LOAD_TXT "nl"
#	movsw
#	mov	al, 0
#	stosb

	mov	ax, 1 << 8	# Type A
	stosw
	mov	ax, 1 << 8	# Class IN
	stosw

	pop	esi
	NET_BUFFER_SEND

9:
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	pop	esi
	pop	edi
	ret

####################################
cmd_host:
	xor	eax, eax
	call	nic_getobject

	lodsd
	lodsd
	or	eax, eax
	jz	9f

	mov	esi, eax
	call	strlen
	mov	ecx, eax

	call	net_dns_request

	ret
9:	printlnc 12, "usage: host <hostname>"
	stc
	ret


###########################################################################
# DHCP
#
# rfc 2131 (protocol), rfc 1533 (options)
.struct 0
dhcp_op:	.byte 0
	DHCP_OP_BOOTREQUEST	= 1
	DHCP_OP_BOOTREPLY	= 2
dhcp_hwaddrtype:.byte 0	# 1 = 10mbit ethernet
dhcp_hwaddrlen:	.byte 0 # 6 bytes mac
dhcp_hops:	.byte 0 # 0
dhcp_xid:	.long 0 # transaction id
dhcp_secs:	.word 0 # 0 seconds since acquisition/renewal
dhcp_flags:	.word 0 # 0
dhcp_ciaddr:	.long 0			# client ip
dhcp_yiaddr:	.long 0			# your ip
dhcp_siaddr:	.long 0			# 'next server' ip (bootp)
dhcp_giaddr:	.long 0			# 'relay agent' (gateway) ip (bootp)
dhcp_chaddr:	.space 16# client hardware addr (MAC), 6 bytes, 10 bytes 0.
dhcp_sname:	.space 64
dhcp_file:	.space 128
dhcp_magic:	.long 0 # 0x63825363
	DHCP_MAGIC = 0x63538263
dhcp_options:	# variable. Format: .byte DHCP_OPT_..., len; .space [len]
	# http://tools.ietf.org/html/rfc1533
	#				# len	type
	DHCP_OPT_SUBNET_MASK	= 1	# 4	ip	(must precede router)
	DHCP_OPT_TIME_OFFSET	= 2	# 4	seconds
	DHCP_OPT_ROUTER		= 3	# 4*n	ip list, minimum 1 ip
	DHCP_OPT_TIME_SERVER	= 4	# 4*n	ip list
	DHCP_OPT_NAME_SERVER	= 5	# 4*n	ip list (IEN 116 nameservers)
	DHCP_OPT_DNS		= 6	# 4*n	ip list
	# other servers: (all ip lists:)
	# 7=log 8=cookie 9=lpr 10=impress 11=resource location
	DHCP_OPT_HOSTNAME	= 12	# ?	string
	DHCP_OPT_BOOT_FILE_SIZE	= 13	# 2	sectors
	# 14=merit dump file (core dump file)
	DHCP_OPT_DOMAINNAME	= 15	# 1+	string
	# 16=swap server 17=root path 18=extensions path (TFTP)
	# 19=ip forward enable/disable	# 1	0 or 1
	# 26 = interface mtu opt	# 2	unsigned word; 68+
	# 31 - router discover
	# 33 - static route
	# 43 - vendor specific info
	# 44 - netbios/tcpip name server
	# 46 - netbios/tcpip node type
	# 47 - netbios/tcpip scope
	DHCP_OPT_REQ_IP		= 50	# 4	ip	# requested ip address
	DHCP_OPT_IP_LEASE_TIME	= 51	# 4	seconds
	DHCP_OPT_OPTION_OVERLOAD= 52	# 1	1=file,2=sname,3=both have opts
		# 53, 1, ? = message type, len 1, 1=DISCOVER,2=offer,3=req,4=decline,5=ACK, 8=inform
	DHCP_OPT_MSG_TYPE	= 53	# 1	DHCP_MT_
		DHCP_MT_DISCOVER		= 1
		DHCP_MT_OFFER			= 2
		DHCP_MT_REQUEST			= 3
		DHCP_MT_DECLINE			= 4
		DHCP_MT_ACK			= 5
		DHCP_MT_NAK			= 6
		DHCP_MT_RELEASE			= 7
		# not in rfc1533:
		#DHCP_MT_INFORM			= 8
		#DHCP_MT_FORCE_RENEW		= 9
	DHCP_OPT_SERVER_IP	= 54	# 4	ip
	DHCP_OPT_PARAM_REQ_LIST	= 55	# ?	option nr [,option nr,...]
	DHCP_OPT_MESSAGE	= 56	# 1+	string	(NAK/DECLINE err msg)
	DHCP_OPT_MAX_MSG_SIZE	= 57	# 2	576+ (DISCOVER/REQUEST)
	DHCP_OPT_RENEWAL_TIME	= 58	# 4	seconds	(T1) (assign->RENEW)
	DHCP_OPT_REBINDING_TIME	= 59	# 4	seconds	(T2) (assign->REBIND)
	# 60 - vendor class identifier
	DHCP_OPT_CLIENT_ID	= 61	# 2+(7)	custom (hwtype(1),mac)
	DHCP_OPT_CLIENT_FQDN	= 81	# 3+?	flags, A_RR, PTR_RR, string
	# 121 - classless static route
	# 249 - private/classless static route (MSFT)
	DHCP_OPT_EOO		= 255	# N/A	N/A - end of options.
DHCP_HEADER_SIZE = .
.struct 0	# transaction list
dhcp_txn_xid:		.long 0
dhcp_txn_nic:		.long 0
dhcp_txn_server_ip:	.long 0	# ip of server offering
dhcp_txn_server_mac:	.long 0	# ip of server offering
dhcp_txn_yiaddr:	.long 0	# ip server offered (0 for discover)
dhcp_txn_router:	.long 0
dhcp_txn_netmask:	.long 0
dhcp_txn_state:		.word 0	# lo byte = last sent msg; hi=last rx'd msg
DHCP_TXN_STRUCT_SIZE = .
.data
mac_broadcast: .space 6, -1
.data SECTION_DATA_BSS
dhcp_xid_counter:	.long 0
dhcp_transactions:	.long 0	# array
.text32
# in: ebx = nic
# out: ecx + edx
dhcp_txn_new:
	push	eax
	ARRAY_NEWENTRY [dhcp_transactions], DHCP_TXN_STRUCT_SIZE, 1, 9f
	mov	ecx, eax
	mov	[ecx + edx + dhcp_txn_nic], ebx
	mov	[ecx + edx + dhcp_txn_state], word ptr 0
	mov	eax, [dhcp_xid_counter]
	inc	dword ptr [dhcp_xid_counter]
	mov	[ecx + edx + dhcp_txn_xid], eax
9:	pop	eax
	ret


# destroys: eax, ebx, ecx, edx, esi
dhcp_txn_list:
	ARRAY_LOOP [dhcp_transactions], DHCP_TXN_STRUCT_SIZE, ebx, ecx, 9f
	printc 11, "xid "
	mov	edx, [ebx + ecx + dhcp_txn_xid]
	call	printhex8
	printc 11, " nic "
	mov	edx, [ebx + ecx + dhcp_txn_nic]
	lea	esi, [edx + dev_name]
	call	print
	printc 10, " state: rx="
	movzx	edx, byte ptr [ebx + ecx + dhcp_txn_state + 1]
	cmp	dl, 8
	ja	1f
	mov	esi, [dhcp_message_type_labels$ + edx * 4]
	call	print
	jmp	2f
1:	call	printhex2
2:	printc 10, " tx="
	movzx	edx, byte ptr [ebx + ecx + dhcp_txn_state]
	cmp	dl, 8
	ja	1f
	mov	esi, [dhcp_message_type_labels$ + edx * 4]
	call	print
	jmp	2f
1:	call	printhex2
2:
	printc 11, " server "
	mov	eax, [ebx + ecx + dhcp_txn_server_ip]
	call	net_print_ip
	printc 11, " yip "
	mov	eax, [ebx + ecx + dhcp_txn_yiaddr]
	call	net_print_ip
	printc 11, "/"
	mov	eax, [ebx + ecx + dhcp_txn_netmask]
	call	net_print_ip
	printc 11, " gw "
	mov	eax, [ebx + ecx + dhcp_txn_router]
	call	net_print_ip

	call	newline
	ARRAY_ENDL
9:	ret

# in: eax = xid
# out: ecx + edx = dhcp_txn object
# out: CF
dhcp_txn_get:
	ARRAY_LOOP [dhcp_transactions], DHCP_TXN_STRUCT_SIZE, ecx, edx, 9f
	cmp	[ecx + edx + dhcp_txn_xid], eax
	jz	1f
	ARRAY_ENDL
9:	stc
1:	ret

# in: ebx = nic
# in: dl = DHCP message type
# in: eax = ptr to dhcp_txn structure (or 0: will be allocated)
net_dhcp_request:
	or	eax, eax	# have dhcp_txn object
	jnz	1f
	push	edx
	call	dhcp_txn_new
	lea	eax, [ecx + edx]
	pop	edx
	jc	9f
1:
	mov	[eax + dhcp_txn_nic], ebx
	mov	[eax + dhcp_txn_state], dl

	NET_BUFFER_GET
	jc	9f
	push	edi

DHCP_OPTIONS_SIZE = 32
	push	eax

	mov	eax, -1		# broadcast
	mov	esi, offset mac_broadcast
	mov	dx, IP_PROTOCOL_UDP | 1 << 8	# don't use ip

	mov	ecx, UDP_HEADER_SIZE + DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	call	net_ipv4_header_put
	mov	esi, edi	# remember udp frame ptr for checksum
	mov	eax, (68 << 16) | 67	# sport dport
	mov	ecx, DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	call	net_udp_header_put

	xor	eax, eax
	rep	stosb
	mov	ecx, DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	sub	edi, ecx
	pop	eax

	mov	dl, [eax + dhcp_txn_state]
	push	eax
	mov	eax, [eax + dhcp_txn_xid]

	mov	[edi + dhcp_options + 2], dl
	mov	[edi + dhcp_op], byte ptr 1
	mov	[edi + dhcp_hwaddrtype], byte ptr 1
	mov	[edi + dhcp_hwaddrlen], byte ptr 6
	mov	[edi + dhcp_flags], word ptr 0x0080 # broadcast

	mov	[edi + dhcp_xid], eax
	pop	eax
	mov	dword ptr [edi + dhcp_magic], DHCP_MAGIC
	push	esi
	lea	esi, [ebx + nic_mac]	# 16 byte-padded hw addr
	add	edi, offset dhcp_chaddr
	movsd
	movsw
	pop	esi
	sub	edi, offset dhcp_chaddr + 6
	mov	[edi + dhcp_options + 0], byte ptr 53	# dhcp message type
	mov	[edi + dhcp_options + 1], byte ptr 1	# len
	# see dl above
	#mov	[edi + dhcp_options + 2], byte ptr 1	# message type

	mov	[edi + dhcp_options + 3], byte ptr 55	# request options
	mov	[edi + dhcp_options + 4], byte ptr 3	# len
	mov	[edi + dhcp_options + 5], byte ptr 1	# subnet mask
	mov	[edi + dhcp_options + 6], byte ptr 3	# router
	mov	[edi + dhcp_options + 7], byte ptr 6	# dns

	mov	[edi + dhcp_options + 8], byte ptr 12	# hostname
	mov	[edi + dhcp_options + 9], byte ptr 4	# len
	mov	[edi + dhcp_options + 10], dword ptr ('Q'|'u'<<8|'R'<<16|'e'<<24)

	mov	[edi + dhcp_options + 14], byte ptr DHCP_OPT_CLIENT_ID
	mov	[edi + dhcp_options + 15], byte ptr 7
	mov	[edi + dhcp_options + 16], byte ptr 1	# hw type
	push	edi
	push	esi
	lea	esi, [edi + dhcp_chaddr]
	lea	edi, [edi + dhcp_options + 17]
	movsd
	movsw
	pop	esi
	pop	edi
	# at option offset 23
	mov	edx, [eax + dhcp_txn_yiaddr]
	or	edx, edx
	jz	1f
	mov	[edi + dhcp_options + 23], byte ptr DHCP_OPT_REQ_IP
	mov	[edi + dhcp_options + 24], byte ptr 4
	mov	[edi + dhcp_options + 25], edx
1:

	mov	[edi + dhcp_options + 29], byte ptr 0xff	# end options
	add	edi, DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE

	# udp checksum

	# in: eax = src ip
	mov	eax, 0
	# in: edx = dst ip
	mov	edx, -1
	# in: esi = udp frame pointer
	#mov	esi, [esp]
	# in: ecx = tcp frame len
	mov	ecx, UDP_HEADER_SIZE + DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	call	net_udp_checksum

	# send packet

	clc
8:	pop	esi
	jc	9f
	NET_BUFFER_SEND

9:	ret


###########################################################################
# DHCP protocol handlers

# client to server message:
# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
ph_ipv4_udp_dhcp_c2s:
	.if NET_DHCP_DEBUG
		println "    DHCP client to server"
	.endif
	# handler for DHCP server goes here.
	ret

# NOTE! nonstandard - see net_dhcp_print
#
# server to client message:
# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
ph_ipv4_udp_dhcp_s2c:
	.if NET_DHCP_DEBUG
		println "    DHCP server to client"
	.endif

	# note: see note above
	add	esi, offset UDP_HEADER_SIZE

	.if NET_DHCP_DEBUG
		push	edx
		call	net_dhcp_print
		pop	edx
	.endif

	cmp	byte ptr [esi + dhcp_op], DHCP_OP_BOOTREPLY
	jnz	19f

	mov	dl, DHCP_OPT_MSG_TYPE
	call	net_dhcp_get_option$
	jc	18f
	movzx	edi, byte ptr [edx]	# message type

	cmp	edi, 8
	jae	17f
	.if NET_DHCP_DEBUG
		push	esi
		mov	esi, [dhcp_message_type_labels$ + edi * 4]
		call	print
		pop	esi
	.endif

	mov	eax, [esi + dhcp_xid]
	# ecx no longer needed
	call	dhcp_txn_get	# out: ecx + edx
	jc	16f	# unknown transaction
	lea	eax, [ecx + edx]

	mov	edx, edi
	mov	[eax + dhcp_txn_state + 1], dl

	mov	dh, [eax + dhcp_txn_state]
	xor	dl, dl
	or	dx, di

	.if NET_DHCP_DEBUG
		DEBUG "DHCP MT/STATE:"
		DEBUG_WORD dx
		DEBUG_DWORD [eax + dhcp_txn_xid]
	.endif

	# dl = received message type
	# dh = txn state (last sent message type)

	cmp	dx, DHCP_MT_DISCOVER << 8 | DHCP_MT_OFFER
	jz	1f
	cmp	dx, DHCP_MT_REQUEST << 8 | DHCP_MT_NAK
	jz	2f
	cmp	dx, DHCP_MT_REQUEST << 8 | DHCP_MT_ACK
	jz	3f

	printc 4, "DHCP: unknown state: server="
	call	printhex2
	mov	dl, dh
	printc 4, " client="
	call	printhex2
	call	newline
	jmp	9f	# unknown state

# in: eax = ptr to dhcp_txn
1:	# have offer to request
	mov	dl, DHCP_MT_REQUEST
	jmp	0f
2:	# got NAK on request
	printlnc 4, "DHCP request NAK'd"
	jmp	9f
3:	# got ACK
	mov	edi, eax	# remember txn obj

	# configure nic
	mov	eax, dword ptr [esi + dhcp_yiaddr]
	mov	[ebx + nic_ip], eax

	.if NET_DHCP_DEBUG
		printc 2, "DHCP ACK: "
		print "ip: "
		call	net_print_ip
	.endif

	# add routes
	mov	dl, DHCP_OPT_ROUTER
	call	net_dhcp_get_option$
	jc	1f
	test	al, 0b11	# size: n*4, n>1.
	jnz	1f
	shr	al, 2
	jz	1f
	mov	eax, [edx]
	mov	[edi + dhcp_txn_router], eax
	.if NET_DHCP_DEBUG
		print "router: "
		call	net_print_ip
	.endif
1:
	mov	dl, DHCP_OPT_SUBNET_MASK
	call	net_dhcp_get_option$
	jc	15f
	cmp	al, 4
	jnz	15f
	mov	edx, [edx]
	mov	[edi + dhcp_txn_netmask], edx

	.if NET_DHCP_DEBUG
		print "netmask: "
		mov eax, edx
		call 	net_print_ip
	.endif

	call	net_route_delete_dynamic	# in: ebx

	# calculate params
	#mov	edx, [edi + dhcp_txn_netmask]
	xor	eax, eax	# eax = gw
	mov	ecx, [edi + dhcp_txn_yiaddr]
	and	ecx, edx	# ecx = network
	mov	esi, 50 | NET_ROUTE_FLAG_DYNAMIC << 16	# metric & flag
	call	net_route_add

	mov	eax, [edi + dhcp_txn_router]
	or	eax, eax
	jz	9f	# no router, dont add route
	xor	ecx, ecx
	xor	edx, edx
	mov	esi, 40 | NET_ROUTE_FLAG_DYNAMIC << 16
	call	net_route_add
	jmp	9f

# in: eax = dhcp_txn
# in: dl = DHCP_MT_
0:	push	dword ptr [esi + dhcp_yiaddr]
	pop	dword ptr [eax + dhcp_txn_yiaddr]
	push	dword ptr [esi - UDP_HEADER_SIZE - 8] # sender ip
	pop	dword ptr [eax + dhcp_txn_server_ip]
	call	net_dhcp_request
9:	ret


19:	printlnc 4, "DHCP: not REPLY"
	ret
18:	printlnc 4, "DHCP: can't get MSG TYPE"
	ret
17:	printlnc 4, "DHCP: unknown message type"
	ret
16:	printlnc 4, "DHCP: unknown XID"
	ret
# ACK errors:
15:	printlnc 4, "DHCP: no subnet mask"
	ret

# in: dl = DHCP_OPT_...
# in: esi = dhcp frame
# in: ecx = dhcp frame len
# out: eax = al = option len
# out: edx = ptr to option ([eax-1]=opt len)
# out: CF
net_dhcp_get_option$:
	push	esi
	push	ecx
	xor	eax, eax
	add	esi, offset dhcp_options
	sub	ecx, offset dhcp_options
	jle	9f
0:	lodsb
	dec	ecx
	jz	9f
	cmp	al, -1
	jz	9f
	cmp	al, dl
	lodsb
	jz	1f
	dec	ecx
	jz	9f
	add	esi, eax
	sub	ecx, eax
	jg	0b
9:	stc
	jmp	0f

1:	mov	edx, esi

0:	pop	ecx
	pop	esi
	ret

# NOTE! nonstandard: esi points to the UDP frame, not its payload! Also, edx
# points to the ipv4 frame. A 'proper' way would be to have:
#   - eax = udp frame
#   - edx = ipv4 frame (could swap with eax)
#   - esi = udp payload
#
# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
net_dhcp_print:
	pushcolor COLOR_PROTO_DATA
	push	ecx
	push	edx	# remember ipv4 frame
	push	esi	# free up esi for printing
	mov	edi, esi

	printc_ COLOR_PROTO, "   DHCP "

	mov	edx, [edi + dhcp_magic]
	cmp	edx, DHCP_MAGIC
	jz	1f
	printc_ 12, "WRONG MAGIC: "
	call	printhex8
	call	printspace
1:
	printc_	COLOR_PROTO_LOC, "OP "
	mov	dl, [edi + dhcp_op]
	call	printhex2
	LOAD_TXT " BOOTP Request"
	cmp	dl, 1
	jz	1f
	LOAD_TXT " BOOTP Reply"
	cmp	dl, 2
	jz	1f
	LOAD_TXT " UNKNOWN"
1:	call	print

	printc_ COLOR_PROTO_LOC, " HW "
	mov	dl, [edi + dhcp_hwaddrtype]
	call	printhex2	# should be 1
	printc_ COLOR_PROTO_LOC, " len "
	mov	dl, [edi + dhcp_hwaddrlen]
	call	printhex2	# should be 6
	printc_ COLOR_PROTO_LOC, " hops "
	mov	dl, [edi + dhcp_hops]
	call	printhex2
	printc_ COLOR_PROTO_LOC, " XID "
	mov	edx, [edi + dhcp_xid]
	call	printhex8
	printc_ COLOR_PROTO_LOC, " secs "
	movzx	edx, word ptr [edi + dhcp_secs]
	xchg	dl, dh
	call	printdec32
	printc_ COLOR_PROTO_LOC, " flags "
	mov	dx, [edi + dhcp_flags]
	xchg	dl, dh
	call	printhex2
	call	newline

	print	"   "

	.macro DHCP_ADDR_PRINT t
		printc_ COLOR_PROTO_LOC, " \t\()ip "
		mov	eax, [edi + dhcp_\t\()iaddr]
		call	net_print_ip
	.endm

	DHCP_ADDR_PRINT c
	DHCP_ADDR_PRINT y
	DHCP_ADDR_PRINT s
	DHCP_ADDR_PRINT g

	printc_ COLOR_PROTO_LOC, " mac "
	lea	esi, [edi + dhcp_chaddr]
	call	net_print_mac
	call	newline

	print	"   "

	push	ecx
	add	esi, dhcp_sname - dhcp_chaddr
	mov	ecx, 64	# sname len
	cmp	byte ptr [esi], 0
	jz	1f
	printc COLOR_PROTO_LOC, " sname "
	call	nprint
1:
	add	esi, ecx
	mov	ecx, 128
	cmp	byte ptr [esi], 0
	jz	1f
	printc COLOR_PROTO_LOC, " file "
	call	nprint
1:	pop	ecx

	lea	esi, [edi + dhcp_options]
	sub	ecx, offset dhcp_options
	jle	1f	# no room for options
	cmp	byte ptr [esi], -1
	jz	1f	# first option is end of options
	printc COLOR_PROTO_LOC, " options: "

0:	lodsb
	cmp	al, -1
	jz	1f
	dec	ecx
	jz	1f
	movzx	edx, al
	lodsb
	movzx	eax, al
	push	esi
	push	eax
	push	ecx
	mov	ecx, eax

	call	dhcp_print_option$

	pop	ecx
	pop	eax
	pop	esi
	add	esi, eax
	sub	ecx, eax
	jg	0b

1:	call	newline

	pop	esi
	pop	edx
	pop	ecx
	popcolor
	ret

##########################################################
# DHCP option handlers/printing

# in: dl = edx = option id
# in: ecx = cl = eax = option len
# in: esi = ptr to option data
# preserved by caller: eax, ecx, esi, edx; require preserve rest.
dhcp_print_option$:
	printcharc_ 1, '['
	mov	al, dl

	pushcolor 8
	call	printdec32
	popcolor


	call	dhcp_option_get_label$
	jc	1f
	call	printspace

	push	esi
	mov	esi, [edx]
	mov	ah, 10
	call	printc
	call	printspace
	pop	esi
	mov	edx, [edx + 4]
	or	edx, edx
	jz	1f
	add	edx, [realsegflat]
	call	edx
	jmp	9f

1:	mov	edx, ecx
	printchar_ ','
	call	printdec32

9:	printcharc_ 1, ']'
	ret

##########################################################
# some macro 'wizardry' to create a demuxed datastructure:
# .data itself contains the option struct pointers (called
# labels, but the fields are 8 bytes wide: the 2nd dword
# contains a print handler).
# SECTION_DATA_CONCAT contains the option identifiers for
# scasb.
# SECTION_DATA_STRINGS (used by STRINGPTR) has the labels.
#
.data SECTION_DATA_CONCAT
dhcp_option_have_label$:
.data
dhcp_option_labels$:
.macro DHCP_DECLARE_OPTION_LABEL optnr, handler, label
	STRINGPTR "\label"
	.data
	.ifc 0,\handler
	.long 0
	.else
	.long dhcp_opt_print_\handler
	.endif
	.data SECTION_DATA_CONCAT
	.byte \optnr
.endm
DHCP_DECLARE_OPTION_LABEL 1, 	ip,	"subnet mask"
DHCP_DECLARE_OPTION_LABEL 3, 	ip,	"router"
DHCP_DECLARE_OPTION_LABEL 6, 	ip,	"dns"
DHCP_DECLARE_OPTION_LABEL 12,	s,	"hostname"
DHCP_DECLARE_OPTION_LABEL 15,	s,	"domain name"
DHCP_DECLARE_OPTION_LABEL 31, 	0,	"router discover"
DHCP_DECLARE_OPTION_LABEL 33, 	0,	"static route"
DHCP_DECLARE_OPTION_LABEL 43, 	0,	"vendor specific info"
DHCP_DECLARE_OPTION_LABEL 44, 	0,	"netbios name server"
DHCP_DECLARE_OPTION_LABEL 46, 	0,	"netbios node type"
DHCP_DECLARE_OPTION_LABEL 47, 	0,	"netbios scope"
DHCP_DECLARE_OPTION_LABEL 50,	ip,	"requested ip address"
DHCP_DECLARE_OPTION_LABEL 60, 	s,	"vendor class identifier"
DHCP_DECLARE_OPTION_LABEL 61,	cid,	"client identifier" #hwtype=1(ethernet), mac (client identifier)"
DHCP_DECLARE_OPTION_LABEL 81,	s,	"fqdn"
DHCP_DECLARE_OPTION_LABEL 53,	mt,	"message type" #1, ? = message type, len 1, 1=DISCOVER,2=offer,3=req,4=decline,5=ACK, 8=inform"
DHCP_DECLARE_OPTION_LABEL 54,	ip,	"server_ip"
DHCP_DECLARE_OPTION_LABEL 51,	time,	"lease time"
DHCP_DECLARE_OPTION_LABEL 55,	optlst,	"param req list"
DHCP_DECLARE_OPTION_LABEL 121,	0,	"classless static route"
DHCP_DECLARE_OPTION_LABEL 249,	0,	"private/classless static route (MSFT)"
DHCP_DECLARE_OPTION_LABEL 255,	0,	"end option"
DHCP_OPTION_LABEL_NUM = . - dhcp_option_have_label$	# expect .data ..CONCAT
.text32

# in: al = option id
# out: edx = handler structure (offs 0=label, 0ffs 4=print handler)
# out: CF
dhcp_option_get_label$:
	push	edi
	push	ecx
	mov	edi, offset dhcp_option_have_label$
	mov	ecx, DHCP_OPTION_LABEL_NUM
	repnz	scasb
	stc
	jnz	9f
	jecxz	9f
	mov	edx, DHCP_OPTION_LABEL_NUM
	sub	edx, ecx	# clears carry (or not, but shouldn't happen)
	lea	edx, [dhcp_option_labels$ + edx * 8 - 8]
9:	pop	ecx
	pop	edi
	ret



# these get called in dhcp_option_print$.
# in: ecx = length
# preserved by caller: esi, ecx

dhcp_opt_print_ip:
	cmp	ecx, 4
	jnz	9f
	lodsd
	call	net_print_ip
9:	ret

dhcp_opt_print_s:
	call	nprint
	ret

dhcp_opt_print_cid:
	cmp	ecx, 7
	jnz	9f
	lodsb
	mov	dl, al
	call	printdec32	# hw type
	call	printspace
	call	net_print_mac
9:	ret

.data
dhcp_message_type_labels$:
STRINGPTR "<invalid:0>"	# 0
STRINGPTR "DISCOVER"	# 1
STRINGPTR "OFFER"	# 2
STRINGPTR "REQUEST"	# 3
STRINGPTR "DECLINE"	# 4
STRINGPTR "ACK"		# 5
STRINGPTR "NAK"		# 6
STRINGPTR "RELEASE"	# 7
STRINGPTR "INFORM"	# 8
STRINGPTR "FORCE RENEW"	# 9
.text32
dhcp_opt_print_mt:
	cmp	ecx, 1
	jnz	9f
	movzx	eax, byte ptr [esi]
	cmp	al, 8
	ja	9f
	mov	esi, [dhcp_message_type_labels$ + eax * 4]
	call	print
9:	ret
dhcp_opt_print_time:
	cmp	ecx, 4
	jnz	9f
	lodsd
	# TODO: fancy hh:mm:ss
	mov	edx, eax
	bswap	edx
	call	printdec32
	printchar_ 's'
9:	ret
dhcp_opt_print_optlst:
	lodsb
	movzx	edx, al
	call	printdec32
	call	printspace
	call	dhcp_option_get_label$
	jc	9f
	call	print
9:	ret
###########################################################################

cmd_dhcp:
	lodsd
0:	call	getopt
	jc	1f
	mov	eax, [eax]
	and	eax, 0x00ffffff
	cmp	eax, '-'|'h'<<8
	jz	9f
	cmp	eax, '-'|'l'<<8
	jz	2f
	jmp	9f

1:	# no more options
	lodsd
	or	eax, eax
	jz	9f

	call	nic_parse
	jc	9f

#	xor	eax, eax
#	call	nic_getobject
	mov	dl, 1
	xor	eax, eax
	jmp	net_dhcp_request

2:	call	dhcp_txn_list
	ret

9:	printlnc 12, "usage: dhcp -l        # list transactions"
	printlnc 12, "       dhcp <ethX>    # configure ethX using DHCP"
	ret

#############################################################################
# IPv6
#
net_ipv6_print:
	printc	COLOR_PROTO, "IPv6 "
	call	newline
	ret

##############################################################################

NET_RX_QUEUE = 1
NET_RX_QUEUE_ITER_RESCHEDULE = 0	# 0=task loop, 1=task reschedule
NET_RX_QUEUE_DEBUG = 0

.if NET_RX_QUEUE == 0

# in: ds = es = ss
# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet:
	PUSH_TXT "net"
	push	dword ptr 0 # TASK_FLAG_RESCHEDULE # flags
	push	cs
	push	eax
	mov	eax, offset net_rx_packet_task
	add	eax, [realsegflat]
	xchg	eax, [esp]
	call	schedule_task
	jc	9f	# lock fail, already scheduled, ...
	ret
9:	printlnc 4, "net: packet dropped"
	ret

.else
# A queue for incoming packets so as to not flood the scheduler with a job
# (and possibly a stack) for each packet.
.struct 0
net_rx_queue_status:	.long 0
net_rx_queue_args:	.space 8*4
NET_RX_QUEUE_STRUCT_SIZE = .
.data SECTION_DATA_BSS
net_rx_queue:	.long 0
.text32
# out: eax + edx
net_rx_queue_newentry:
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 1f
	cmp	[eax + edx + net_rx_queue_status], dword ptr 0
	jz	2f
	ARRAY_ENDL
1:	ARRAY_NEWENTRY [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, 4, 9f
2:	mov	[eax + edx + net_rx_queue_status], dword ptr 1
9:	ret

# in: ds = es = ss
# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet:
	pushad
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	call	net_rx_queue_newentry	# out: eax + edx
	jnc	1f
	MUTEX_UNLOCK NET
	popad
	jmp	9f

1:	lea	edi, [eax + edx + net_rx_queue_args]
	mov	esi, esp
	mov	ecx, 8
	rep	movsd
	mov	[edi-4], eax
	mov	[edi-12], edx
	popad
	MUTEX_UNLOCK NET

net_rx_queue_schedule:	# target for net_rx_queue_handler if queue not empty
	PUSH_TXT "net"
	push	dword ptr TASK_FLAG_RESCHEDULE # flags
	push	cs
	push	eax
	mov	eax, offset net_rx_queue_handler
	add	eax, [realsegflat]
	xchg	eax, [esp]
	call	schedule_task
	setc	al
	.if NET_RX_QUEUE_DEBUG
		DEBUG_BYTE al
	.endif

# have queue
#	jc	9f	# lock fail, already scheduled, ...
	ret
9:	printlnc 4, "net: packet dropped"
	ret


net_rx_queue_handler:
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	cmp	[eax + edx + net_rx_queue_status], dword ptr 1
	jz	1f
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET
	ret	# queue exhausted

1:	sub	esp, 8*4
	lea	esi, [eax + edx + net_rx_queue_args]
	mov	edi, esp
	mov	ecx, 8
	rep	movsd
	popad

	mov	eax, [net_rx_queue]
	mov	[eax + edx + net_rx_queue_status], dword ptr 0
	MUTEX_UNLOCK NET

	call	net_rx_packet_task

.if NET_RX_QUEUE_ITER_RESCHEDULE
	# check if the queue is empty, if not, schedule job again
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	xor	ecx, ecx
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	add	ecx, [eax + edx + net_rx_queue_status]
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET

	jecxz	9f
	jmp	net_rx_queue_schedule
9:
.else
	jmp	net_rx_queue_handler
.endif
	ret



net_rx_queue_print:
	printc 11, "net_rx_queue: "
	xor	ecx, ecx
	xor	ebx, ebx
	# count packets
0:	MUTEX_SPINLOCK NET, nolocklabel=0b
	ARRAY_LOOP [net_rx_queue], NET_RX_QUEUE_STRUCT_SIZE, eax, edx, 9f
	add	ecx, [eax + edx + net_rx_queue_status]	# 1 indicates pkt in q
	inc	ebx
	ARRAY_ENDL
9:	MUTEX_UNLOCK NET

	mov	edx, ecx
	call	printdec32
	printcharc 11, '/'
	mov	edx, ebx
	call	printdec32
	printlnc 11, " packets"

	ret
.endif

# in: ebx = nic
# in: esi = packet (ethernet frame)
# in: ecx = packet len
net_rx_packet_task:
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

1:	call	net_handle_packet

	pop	ebx
	pop	ecx
	pop	esi
	ret


############################################################################
# IPv4 Routing

.struct 0
net_route_gateway:	.long 0
net_route_network:	.long 0
net_route_netmask:	.long 0
net_route_nic:		.long 0
net_route_metric:	.word 0
net_route_flags:	.word 0	# -1 indicates available - re-use entries.
  NET_ROUTE_FLAG_DYNAMIC = 0x8000 # will be removed on dhcp
NET_ROUTE_STRUCT_SIZE = .
.data
net_route: .long 0
.text32

# in: eax = gw
# in: ebx = device
# in: ecx = network
# in: edx = netmask
# in: esi = [flags | metric]
net_route_add:
	push	eax
	push	ebx
	push	ecx
	push	edx
	xor	edx, edx
	mov	ecx, NET_ROUTE_STRUCT_SIZE
	mov	eax, [net_route]
	or	eax, eax
	jnz	2f
	inc	eax
	call	array_new
	jc	9f
1:	call	array_newentry
	jc	9f
	mov	[net_route], eax

3:	mov	ebx, [esp + 0]
	mov	[eax + edx + net_route_netmask], ebx
	mov	ebx, [esp + 4]
	mov	[eax + edx + net_route_network], ebx
	mov	ebx, [esp + 8]
	mov	[eax + edx + net_route_nic], ebx
	mov	ebx, [esp + 12]
	mov	[eax + edx + net_route_gateway], ebx

	mov	[eax + edx + net_route_metric], esi	# and flags

9:	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret
# check if there's available entry
# in: eax = [net_route]
# in: edx = index
# in: ecx = NET_ROUTE_STRUCT_SIZE
2:	cmp	edx, [eax + array_index]
	jae	1b
	cmp	[eax + edx + net_route_flags], word ptr -1
	jz	3b
	add	edx, ecx
	jmp	2b


# delete all dynamic routes for nic
# in: ebx = nic
net_route_delete_dynamic:
	push	eax
	push	edx
	ARRAY_LOOP [net_route], NET_ROUTE_STRUCT_SIZE, eax, edx, 9f
	cmp	ebx, [eax + edx + net_route_nic]
	jnz	1f
	test	word ptr [eax + edx + net_route_flags], NET_ROUTE_FLAG_DYNAMIC
	jz	1f
	# mark route as deleted/available
	mov	word ptr [eax + edx + net_route_flags], -1
1:	ARRAY_ENDL
9: 	pop	edx
	pop	eax
	ret


net_route_print:
	push	eax
	push	ebx
	push	edx

	printlnc 11, "IPv4 Route Table"

	ARRAY_LOOP [net_route], NET_ROUTE_STRUCT_SIZE, ebx, edx, 9f
	cmp	word ptr [ebx + edx + net_route_flags], -1
	jz	0f
	printc 15, "net "
	mov	eax, [ebx + edx + net_route_network]
	call	net_print_ip
	printchar_ '/'
	mov	eax, [ebx + edx + net_route_netmask]
	call	net_print_ip
	printc	15, " gw "
	mov	eax, [ebx + edx + net_route_gateway]
	call	net_print_ip
	printc	15, " metric "
	push	edx
	movzx	edx, word ptr [ebx + edx + net_route_metric]
	call	printdec32
	pop	edx
	push	edx
	printc	15, " flags "
	mov	dx, [ebx + edx + net_route_flags]
	call	printhex4
	call	printspace
	PRINTFLAG dx, NET_ROUTE_FLAG_DYNAMIC, "Dynamic "
	pop	edx

	push	esi	# WARNING: using nonrelative pointer
	mov	esi, [ebx + edx + net_route_nic]
	lea	esi, [esi + dev_name]
	mov	ah, 14
	call	printc
	pop	esi

	call	newline
0:	ARRAY_ENDL

9:
	pop	edx
	pop	ebx
	pop	eax
	ret

.macro DEBUG_IP reg
	pushf
	DEBUG "\reg:"
	.ifc eax,\reg
	call	net_print_ip
	.else
	push	eax
	mov	eax, \reg
	call	net_print_ip
	pop	eax
	.endif
	popf
.endm

# in: eax = target ip
# out: ebx = nic to use
# out: edx = gateway ip
net_route_get:
	push	ebp		# temp gateway
	push	edi		# array base
	push	ecx		# array index
	push	esi		# metric
	xor	esi, esi
	ARRAY_LOOP [net_route], NET_ROUTE_STRUCT_SIZE, edi, ecx, 9f
	cmp	word ptr [edi + ecx + net_route_flags], -1
	jz	0f
	cmp	si, [edi + ecx + net_route_metric]
	ja	0f
	mov	edx, eax
	and	edx, [edi + ecx + net_route_netmask]	# zf=1 for default gw
	jz	1f
	cmp	edx, [edi + ecx + net_route_network]
	jnz	0f
1:	mov	ebp, [edi + ecx + net_route_gateway]
	or	ebp, ebp
	jnz	1f
	mov	ebp, eax
1:	mov	ebx, [edi + ecx + net_route_nic]
	mov	si, [edi + ecx + net_route_metric]
0:	ARRAY_ENDL
	mov	edx, ebp
	or	esi, esi
	jnz	1f

9:	printc 4, "net_route_get: no route: "
	call	net_print_ip
	call	newline
	stc

1:	pop	esi
	pop	ecx
	pop	edi
	pop	ebp
	ret


##############################################

cmd_route:
	lodsd
	lodsd
	or	eax, eax
	jz	net_route_print
	# parse command:
	CMD_ISARG "print"
	jz	net_route_print
	push	ebp
	mov	ebp, 100	# flags, metric
	CMD_ISARG "add"
	jnz	9f
	xor	edi, edi	# gw ip
	xor	ebx, ebx	# nic object ptr
	xor	ecx, ecx	# network
	xor	edx, edx	# netmask

	CMD_EXPECTARG 9f
####
	CMD_ISARG "net"
	jnz	1f
	CMD_EXPECTARG 9f
	call	net_parse_ip
	jc	9f
	mov	ecx, eax
	CMD_EXPECTARG 9f
	CMD_ISARG "mask"
	jnz	9f
	CMD_EXPECTARG 9f
	call	net_parse_ip
	jc	9f
	mov	edx, eax
	jmp	2f
####
1:	CMD_ISARG "default"
	jnz	0f
	xor	ecx, ecx
	xor	edx, edx
	mov	ebp, 10
####
2:	CMD_EXPECTARG 1f
0:	CMD_ISARG "gw"
	jnz	0f
	CMD_EXPECTARG 9f
	call	net_parse_ip
	jc	9f
	mov	edi, eax
	CMD_EXPECTARG 1f
0:	CMD_ISARG "metric"
	jnz	0f
	CMD_EXPECTARG 9f
	cmp	word ptr [eax], '0'|'x'<<8
	jnz	2f
	add	eax, 2
	call	htoi
	jmp	3f
2:	call	atoi
3:	jc	9f
	mov	ebp, eax	# metric & flags
	CMD_EXPECTARG 1f
0:	call	nic_parse
	jc	9f
	cmp	dword ptr [esi], 0
	jnz	9f
#### args done
1:	or	ebx, ebx
	jnz	0f
	# find nic
	# TODO: use netmask/network to find appropriate nic
	xor	eax, eax
	push	edx
	call	nic_getobject
	mov	esi, edx
	pop	edx
	jnc	0f
	printlnc 12, "no nic"
	jmp	9f

0:
	print "route add "
	mov	eax, ecx
	call	net_print_ip
	printchar_ '/'
	mov	eax, edx
	call	net_print_ip
	print	" gw "
	mov	eax, edi
	call	net_print_ip
	print	" metric "
	push	edx
	movzx	edx, bp
	call	printdec32
	print	" flags "
	mov	edx, ebp
	shr	edx, 16
	call	printhex4
	pop	edx
	call	printspace
	lea	esi, [ebx + dev_name]
	call	print

	call	newline

	mov	eax, edi
	mov	esi, ebp	# metric, flags
	call	net_route_add
0:	pop	ebp
	ret

9:	printlnc 12, "usage: route add [default] gw <ip>"
	printlnc 12, "       route add [net <ip>] [mask <ip>] gw <ip>"
	jmp	0b

############################################################################

.data SECTION_DATA_BSS
icmp_payload$: .space 32
.text32
icmp_get_payload:
	# payload
	mov	esi, offset icmp_payload$

	# 30 bytes code, generating 32 bytes
	push	edi
	mov	edi, esi
	push	eax
	mov	ecx, 23
	mov	al, 'a'
0:	stosb
	inc	al
	loop	0b
	mov	al, 'A'
	mov	ecx, 9
0:	stosb
	inc	al
	loop	0b
	pop	eax
	pop	edi
	mov	ecx, 32
	ret

# in: eax = ip
# in: dl = ttl
# out: ebx = clock
net_ipv4_icmp_send_ping:
	NET_BUFFER_GET
	jc	9f
	push	edi

	# Construct Packet
	call	icmp_get_payload	# out: esi, ecx
	call	net_icmp_header_put	# in: edi, eax, dl=hops, esi, ecx
	jnc	0f
	pop	edi
	jmp	9f
0:
	call	net_icmp_register_request

	pop	esi
	push	dword ptr [clock_ms]
	NET_BUFFER_SEND
	pop	ebx
9:	ret

PING_USE_SOCKET = 1

cmd_ping:
	push	ebp
	.if PING_USE_SOCKET
	push	dword ptr -1
	.endif
	push	dword ptr 0x00000004	# 00 00 00 ttl
	mov	ebp, esp
	lodsd	# skip cmd name
	mov	ecx, 4
	xor	edx, edx	# arg: hops
	CMD_EXPECTARG 9f
	CMD_ISARG "-ttl"
	jnz	1f
	CMD_EXPECTARG 9f
	call	atoi
	jc	9f
	cmp	eax, 255
	jae	9f
	mov	[ebp], al
	CMD_EXPECTARG 9f
1:	CMD_ISARG "-n"
	jnz	1f
	CMD_EXPECTARG 9f
	call	atoi
	jc	9f
	mov	ecx, eax
	CMD_EXPECTARG 9f
1:	call	net_parse_ip
	jc	9f

	.if PING_USE_SOCKET
		push	eax
		mov     ebx, IP_PROTOCOL_ICMP << 16 | 0
		mov	eax, -1
		call	socket_open
		jc	1f
		mov	[ebp + 4], eax
	1:	pop	eax
	.endif

7:	push	ecx
	push	eax
############################
	print	"Pinging "
	call	net_print_ip
	print	": "

	mov	dl, [ebp]
########
	call	net_ipv4_icmp_send_ping	# in: eax, dl; out: ebx=clock, eax+edx=icmp req
	jc	6f

	# Wait for response

.if PING_USE_SOCKET
	push	eax
	mov	eax, [ebp + 4]
	mov	ecx, 2000 # 2 seconds
	call	socket_read # in: eax, ecx
	pop	eax
	jc	3f
	mov	ecx, [esi - 8] # update ip in icmp request registration
	mov	[eax + edx + 1], ecx
	movzx	ecx, byte ptr [esi + icmp_type]
	cmp	cl, 0	# ping response
	jz	1f
	cmp	cl, 11	# ttl exceeded
	jnz	4f
	printc 4, "ttl exceeded: "
	push	edx
	movsx	edx, byte ptr [esi - IPV4_HEADER_SIZE + ipv4_ttl]
#		neg	edx
	call	printdec32
	call	printspace
	pop	edx
	jmp	2f
4:	printc 4, "unimplemented response: type: "
	push	edx
	mov	edx, ecx
	call	printhex8
	pop	edx
	# and dump to ping timeout
3:
.else

	# calc clocks:
	mov	ecx, [pit_timer_frequency]
	shl	ecx, 1
	jnz	0f
	mov	ecx, 2000/18	# probably

0:	mov	eax, [icmp_requests]
	cmp	byte ptr [eax + edx + icmp_request_status], 0
	jnz	1f
	hlt
	loop	0b	# timer freq: roughly the nr of interrupts
.endif

	printc 4, "PING timeout for "
	jmp	2f

1:
	print	"ICMP PING response from "
2:	sub	ebx, [clock_ms]
	mov	eax, [eax + edx + 1]
	call	net_print_ip
	call printspace
	push	edx
	mov	edx, ebx
	neg	edx
	jnz	2f
	print "< "
	mov	edx, [pit_timer_period]
2:	call printdec32
	println "ms"
	pop	edx

	mov	eax, [icmp_requests]
	dec	byte ptr [eax + edx + 0] # not really needed
############################
6:	pop	eax
	pop	ecx
	dec	ecx
	jz	1f
	push	ecx
	mov	ecx, [pit_timer_frequency]
0:	hlt
	loop	0b
	pop	ecx
	jmp	7b
1:
	.if PING_USE_SOCKET
	mov	eax, [ebp + 4]
	or	eax, eax
	js	1f
	call	socket_close
1:	add	esp, 8
	.else
	add	esp, 4	# local var
	.endif
	pop	ebp
	ret
9:	printlnc 12, "usage: ping [-ttl hops] [-n count] <ip>"
	jmp	1b



cmd_traceroute:
	lodsd
	mov	edx, 20	# max hops
	CMD_EXPECTARG 9f
	CMD_ISARG "-n"
	jnz	1f
	CMD_EXPECTARG 9f
	call	atoi
	jc	9f
	mov	edx, eax
	CMD_EXPECTARG 9f
1:
	call	net_parse_ip
	jc	9f
	mov	edi, offset 188f
	# there's no net_sprint_ip, so we'll hack it here:
	push	edx
	.rept 3
	movzx	edx, al
	call	sprintdec32
	mov	al, '.'
	stosb
	shr	eax, 8
	.endr
	movzx	edx, al
	call	sprintdec32
	pop	edx

	.data
	199: .ascii "ping -ttl "
	198: .ascii "       "
	.ascii " -n 1 "
	188: .asciz "000.000.000.000"
	.text32
	mov	ecx, 0
	
0:	push	edx
	push	ecx

	mov	edx, ecx
	call	printdec32
	print ": "

	mov	edi, offset 198b
	mov	edx, ecx
	call	sprintdec32
	mov	[edi], byte ptr ' '
	mov	esi, offset 199b
	call	strlen_
	call	cmdline_execute$

	pop	ecx
	pop	edx
	inc	ecx
	cmp	ecx, edx
	jb	0b
	ret
9:	printlnc 12, "usage: traceroute [-n maxhops] <ip>"
	ret

#############################################################################
cmd_netstat:
	call	net_tcp_conn_list
	call	socket_list
	call	net_icmp_list
	call	arp_table_print
	.if NET_RX_QUEUE
	call	net_rx_queue_print
	.endif
	ret



#############################################################################
# Sockets
.struct 0
sock_addr:	.long 0
sock_port:	.word 0
sock_proto:	.word 0
sock_in:	.long 0	# updated by net_rx_packet's packet handlers if
sock_inlen:	.long 0 # the ip, port and proto match.
SOCK_STRUCT_SIZE = .
.data SECTION_DATA_BSS
socket_array: .long 0
.text32
# in: eax = ip
# in: ebx = [proto] [port]
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
	push	eax
	push	edx
	push	ebx
	mov	ebx, [clock_ms]
	add	ebx, ecx # SO_TIMEOUT: 10 seconds
0:	mov	edx, [socket_array]
	xor	esi, esi
	xor	ecx, ecx
	xchg	esi, [edx + eax + sock_in]
	xchg	ecx, [edx + eax + sock_inlen]
	or	ecx, ecx
	clc	# not sure if or clears it
	jnz	1f
	cmp	ebx, [clock_ms]
	jb	1f
	sti
	hlt
	jmp	0b

2:	stc
1:	pop	ebx
	pop	edx
	pop	eax
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
	ret
########
2:	# got a match
	# TODO: copy packet (though that should've been done in net_rx_packet).
	mov	[ebx + edi + sock_in], esi
	mov	[ebx + edi + sock_inlen], ecx
	jmp	9b

