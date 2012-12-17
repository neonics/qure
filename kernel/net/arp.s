
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



