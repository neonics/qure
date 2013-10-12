###########################################################################
# IGMP / multicast
#
# [RFC 1112] IGMP v1
# [RFC 2236] IGMP v2
# [RFC 3376] IGMP v3
#
# Class D IP addresses: 224.0.0.0/3 (224.0.0.0-239.255.255.255)
#
# MAC: ETH mcast 01:00:5e:00:00:00 | host_group_ip & ((1<<23)-1)
# or, the low 23 bits of a host group are placed in network byte order
# in the last 23 bits the eth mcast mac:
#
#   01:00:5e:[0 bbbbbbb]:[cccccccc]:[dddddddd] for IPv4 a.b.c.d

IGMP_LOG = 1	# 1: print dropped packets

.struct 0
# http://www.iana.org/assignments/igmp-type-numbers/igmp-type-numbers.xhtml
#  TYPE	 	NAME                    REF
#  ----------|-----------------------|----------
#  0x00		reserved
#  0x01-0x08	obsolete		[RFC  988] (create group etc)
#  0x09-0x10	unassigned
#
# *0x11		membership query	[RFC 1112]
# *0x12		V1 membership report	[RFC 1112]
#
#  0x13		DVMRP
#  0x14		PIM v1
#  0x15		Cisco trace msgs
#
# *0x16		V2 membership report	[RFC 2236]
# *0x17		V2 leave group		[RFC 2236]
#
#  0x1e		mcast traceroute response
#  0x1f		mcast traceroute
#
# *0x22		V3 membership report	[RFC 3376] (source filtering)
#
#  0x30		mcast router advertise	[RFC 4286]
#  0x31		mcast router sollicit 	[RFC 4286]
#  0x31		mcast router terminate 	[RFC 4286]
#  0xf0-0xff	reserver for experiments[RFC 3228|BCP57]
igmp_type:	.byte 0	# lo 4 bits = version; hi 4 bits = type
	IGMP_TYPE_QUERY		= 0x11
	IGMP_TYPE_REPORTv1	= 0x12
	IGMP_TYPE_REPORTv2	= 0x16
	IGMP_TYPE_LEAVEv2	= 0x17
	IGMP_TYPE_REPORTv3	= 0x22
		.byte 0 # unused
igmp_checksum:	.word 0
igmp_addr:	.long 0	# group address
IGMP_HEADER_SIZE = .
.text32

# in: edi = igmp frame pointer
# in: dl = message type
# in: eax = group address (igmp_addr)
net_igmp_header_put:
	push	edx

	movzx	edx, dl
	mov	[edi], dx	# type, unused

	# calc checksum: 
	add	dx, ax
	adc	dx, 0
	ror	eax, 16
	add	dx, ax
	adc	dx, 0
	ror	eax, 16
	not	dx
	mov	[edi + 2], dx
	add	edi, 4

	stosd			# addr

	pop	edx
	ret


net_ipv4_igmp_print:
	cmp	ecx, IGMP_HEADER_SIZE
	jnz	9f
	push_	eax edx
	print	"IGMP v"
	mov	dl, [esi + igmp_type]
	mov	dh, dl
	and	dl, 15
	call	printhex1
	call	printspace
	# decode message type
	mov	ax, 'Q' | '1' << 8
	cmp	dh, IGMP_TYPE_QUERY 
	jz	1f
	mov	ax, 'R' | '1' << 8
	cmp	dh, IGMP_TYPE_REPORTv1
	mov	ah, '2'
	cmp	dh, IGMP_TYPE_REPORTv2
	mov	ah, '3'
	cmp	dh, IGMP_TYPE_REPORTv3
	mov	ax, 'L' | '2' << 8
	cmp	dh, IGMP_TYPE_LEAVEv2
	jz	1f

	mov	ax, '?' | '?' << 8

1:	call	printchar
	printchar_ 'v'
	mov	al, ah
	call	printchar
	call	printspace
	mov	eax, [esi + igmp_addr]
	call	net_print_ipv4

	print	" checksum "
	mov	dx, [esi + igmp_checksum]
	call	printhex4
	call	newline

0:	pop_	edx eax
	ret

9:	printc 4, "IGMP: wrong packet length: "
	push	ecx
	call	_s_printdec32
	printlnc 4, "; should be 8"
	STACKTRACE 0,0
	ret

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (igmp frame)
# in: ecx = payload len (8 minimum)
ph_ipv4_igmp:
	cmp	ecx, IGMP_HEADER_SIZE
	jb	91f
	# verify checksum
	call	protocol_checksum_verify
	jc	92f

	push_	eax edx

	mov	eax, [edx + ipv4_dst]
	cmp	eax, -1	# broadcast
	jz	1f
	# check multicast
	rol	eax, 4
	and	al, 0b1111
	cmp	al, 0b1110
	jz	1f	# 244.0.0.0/4 match
	mov	eax, [edx + ipv4_dst]	# not multicast

	call	nic_get_by_ipv4	# in: eax = ip; out: ebx = nic (ignored)
	jc	93f	# ret: no match

1:	# done with ipv4 frame (edx available)
	mov	dl, [esi + igmp_type]
	cmp	dl, IGMP_TYPE_REPORTv1
	jz	1f
	cmp	dl, IGMP_TYPE_REPORTv2
	jz	1f
	cmp	dl, IGMP_TYPE_REPORTv3
	jz	1f
	cmp	dl, IGMP_TYPE_QUERY
	jz	2f

.if IGMP_LOG
	printc 4, "IGMP: unknown type: "
	call	printhex2
	call	newline
	call	net_ipv4_igmp_print
.endif
	jmp	9f
1:	# report / join
	printc 15, "IGMP report "
	jmp	4f
2:	# query
	printc 15, "IGMP query "
	jmp	4f
3:	# leave

4:	call	net_print_ipv4
	call	printspace
	mov	eax, [esp]
	pushad
	call	net_ipv4_igmp_print
	popad

9:	pop_	edx eax
	ret
91:	printlnc 4, "IGMP: short packet"
	ret
92:	printlnc 4, "IGMP: checksum error"
	jmp 62b	# continue anyway
	ret
93:	printc 4, "IGMP: no nic for "
	call	net_print_ipv4
	call	newline
	jmp	9b

# in: dl = IGMP_TYPE
# in: ebx = nic
# in: eax = dest ip
net_igmp_send:
	NET_BUFFER_GET
	jc	91f
	push	eax
	push	edx	# stack referenced below
	push	edi
	# in: edi = out packet
	# in: edx = [ 00 ] [ ttl ] [flags(1<<1=ttl)] [ipv4 sub-protocol]
	mov	edx, IP_PROTOCOL_IGMP | 1<<9 | 1 << 16
	# in: eax = destination ip
	# in: ecx = payload length (without ethernet/ip frame)
	mov	ecx, IGMP_HEADER_SIZE
	# in: ebx = nic - ONLY if eax = -1!
	mov	ebx, [cloud_nic]
	# out: edi = points to end of ethernet+ipv4 frames in packet
	# out: ebx = nic object (for src mac & ip) [calculated from eax]
	# out: esi = destination mac [calculated from eax]
	call	net_ipv4_header_put

	mov	dl, [esp + 4] # IGMP_TYPE_REPORTv1
	cmp	dl, IGMP_TYPE_QUERY
	jnz	1f
	xor	eax, eax	# query zeroed 
1:
	# in: dl = proto
	# in: eax = group address
	call	net_igmp_header_put

	pop	esi
	NET_BUFFER_SEND
	pop	edx
	pop	eax
	jc	92f
	ret
91:	printlnc 4, "net_buffer_get error"
	stc
	ret
92:	printlnc 4, "net_buffer_send error"
	stc
	ret

# in: ebx = NIC
net_igmp_print:
	push_	esi eax edx
	lea	esi, [ebx + dev_name]
	mov	ah, 15
	call	printc
	printc 11, " MCAST groups: "
	xor	edx, edx
	mov	esi, [ebx + nic_mcast_list]
	or	esi, esi
	jz	1f
	mov	edx, [esi + array_index]
	shr	edx, 2
1:	call	printdec32
	call	newline
	or	edx, edx
	jz	9f

0:	lodsd
	call	printspace
	call	net_print_ipv4
	call	newline
	dec	edx
	jnz	0b

9:	pop_	edx eax esi
	ret

# in: ebx = NIC
# in: eax = IP
net_igmp_join:
	push_	ecx edx

	# verify that the IP is not in the list
	call	net_igmp_ismember
	jz	92f	# already added to list

	mov	ecx, eax	# backup ip
	PTR_ARRAY_NEWENTRY [ebx + nic_mcast_list], 1, 91f
	mov	[eax + edx], ecx
	mov	eax, ecx

62:	# report
	# TODO: timer, repeat
	mov	dl, IGMP_TYPE_REPORTv2
	call	net_igmp_send	# in: eax, ebx, dl

0:	pop_	edx ecx
	ret
91:	printc 4, "net_igmp_join: malloc error"
	jmp	0b
92:	printc 4, "net_igmp_join: alrady member of "
	call	net_print_ipv4
	call	newline
	jmp	62b

# in: ebx = NIC
# in: eax = IP
net_igmp_leave:
	call	net_igmp_ismember
	jnz	91f

	push	edx
	mov	dl, IGMP_TYPE_LEAVEv2
	call	net_igmp_send
	pop	edx

	ret

91:	printc 4, "net_igmp_leave: not member of "
	call	net_print_ipv4
	call	newline
	ret

# in: eax = IP
# in: ebx = NIC
# out: ZF
net_igmp_ismember:
	cmp	eax, 224|1<<24	# all-hosts address
	jz	9f
	push	edi
	mov	edi, [ebx + nic_mcast_list]
	or	edi, edi
	jz	1f
	push	ecx
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd		# ZF = 1 = member
	pop	ecx
	pop	edi
9:	ret

1:	or	esp, esp	# ZF = 0
	pop	edi
	ret
