###############################################################################
# ICMP
#
# rfc 792

NET_ICMP_DEBUG = 0

#############################################################################
.struct 0	# 14 + 20
icmp_header:
icmp_type: .byte 0
	# type
	#*0	echo (ping) reply
	# 1,2	reserved
	# 3	destination unreachable
	#	codes: 
	#	  0000 0=net unreachable
	#	  0001 1=host unreachable
	#	  0010 2=protocol unreachable
	#	  0011 3=port unreachable
	#
	#	  0100 4=fragmentation needed & DontFrag set
	#
	#	  0101 5=src route failed
	#	  0110 6=dest net unknown
	#	  0111 7=dest host unknown
	#	  1000 8=source host isolated
	#
	#	  1001 9  = dest net comm prohibit
	#	  1010 10 = dest host admin prhbt
	#
	#	  1011 11 = dest net unreach for TOS
	#	  1100 12 = dest Host unr for TOS,
	#
	#	  1101 13 = comm prohibit
	#	  1110 14 = host precedence violation
	#	  1111 15 = precedence cutoff in effect.
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
	mov	dh, 2	# indicate edx>>16 &0xff = ttl
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
	add	ecx, ICMP_HEADER_SIZE		# in: ecx = len in bytes
	mov	esi, edi			# in: esi = start
	mov	edi, offset icmp_checksum	# in: edi = offset of cksum word
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

	mov	ax, [esi + icmp_type]	# al=type ah=code

	# check for ping request
	cmp	al, 8
	jnz	1f
	.if NET_ICMP_DEBUG
		printc 11, "ICMP PING REQUEST "
	.endif
	call	protocol_icmp_ping_response
	clc
	ret

1:	cmp	al, byte ptr 0
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

1:	cmp	al, byte ptr 5
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

1:	cmp	al, byte ptr 11
	jnz	1f
	.if NET_ICMP_DEBUG
		printc 11, "ICMP timeout "
		mov	dl, [esi + icmp_code]
		call	printhex2
		printc 11, " original: "
		add	esi, ICMP_HEADER_SIZE	# icmp_payload
		sub	ecx, ICMP_HEADER_SIZE
		call	net_ipv4_print#_header
		call	newline
	.endif
	clc
	ret

1:	cmp	al, 3	# destination unreachable
	jnz	1f
	.if 1#NET_ICMP_DEBUG
		printc 11, "ICMP destination unreachable: code "
		mov	al, ah
		call	printhex2
	.endif

	# TCP handling (this should be moved to tcp.s at some point)
	cmpb	[esi + icmp_payload + ipv4_protocol], IP_PROTOCOL_TCP
	jnz	1f
	mov	eax, [esi + icmp_payload + ipv4_src]
	cmp	eax, [ebx + nic_ip]
	jnz	1f
	# it's a TCP packet we originated

	# in: edx = ip frame pointer
	# in: esi = tcp frame pointer
	# out: eax = tcp_conn array index (add volatile [tcp_connections])
	# out: CF
	movzx	eax, byte ptr [esi + icmp_payload + ipv4_v_hlen]
	and	al, 0x0f
	lea	edi, [esi + icmp_payload]
	lea	esi, [esi + icmp_payload + eax * 4]
	# XXX it might expect incoming packets: src/dst reversed
	call	net_tcp_conn_get
	jc	2f	# we do not have that connection registered
	printlnc 4, "TODO: closing TCP connection"
	jmp	9f
2:	printlnc 4, "unknown TCP connection"
	jmp	9f


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

	push	eax
	call	get_time_ms
	xchg	eax, [esp]

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
		mov     edx, IP_PROTOCOL_ICMP << 16 | 0
		mov	ebx, SOCK_READPEER | SOCK_READTTL
		mov	eax, -1
		KAPI_CALL socket_open
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
	jc	91f

	# Wait for response

.if PING_USE_SOCKET
	push	eax
	mov	eax, [ebp + 4]
	mov	ecx, 2000 # 2 seconds
	KAPI_CALL socket_read # in: eax, ecx
	pop	eax
	jc	3f
	mov	ecx, [esi]	# SOCK_READPEER
	mov	[eax + edx + 1], ecx # update ip in icmp request registration
	add	esi, (4+2)*2+1	# src(ip, port), dst(ip,port), ttl
	movzx	ecx, byte ptr [esi + icmp_type]
	cmp	cl, 0	# ping response
	jz	1f
	cmp	cl, 11	# ttl exceeded
	jnz	4f
	printc 4, "ttl exceeded: "
	push	edx
	movsx	edx, byte ptr [esi - 1]	# SOCK_READTTL
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
2:	push	eax
	call	get_time_ms
	sub	ebx, eax
	pop	eax
	mov	eax, [eax + edx + 1]
	call	net_print_ip
	call	printspace
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
	pop	eax
	pop	ecx
	dec	ecx
	jz	1f

	.if 1
	push	eax
	mov	eax, 1000
	call	sleep
	pop	eax
	.else
	push	ecx
	mov	ecx, [pit_timer_frequency]
0:	hlt
	loop	0b
	pop	ecx
	.endif
	jmp	7b
1:
	.if PING_USE_SOCKET
	mov	eax, [ebp + 4]
	or	eax, eax
	js	2f
	KAPI_CALL socket_close
2:	add	esp, 8
	.else
	add	esp, 4	# local var
	.endif
	pop	ebp
	ret
9:	printlnc 12, "usage: ping [-ttl hops] [-n count] <ip>"
	jmp	1b

91:	#printc 4, "tx fail" # arp timeout message already printed.
	pop	eax
	pop	ecx
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

	cmp	byte ptr [esi + icmp_type], 3
	jnz	1f
	push_	esi ecx
	add	esi, offset icmp_payload
	mov	ecx, TCP_HEADER_SIZE + 64/8	# 64 bits orig dgram
	call	net_ipv4_print
	pop_	ecx esi

1:
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

	# call arp_table_put_mac

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
	push	ecx
	sub	ecx, ICMP_HEADER_SIZE
	jle	2f
	rep	movsb
2:	pop	ecx
	pop	edi

	# call checksum
	push	edi
	push	ecx				# in: ecx = len in bytes
	mov	esi, edi			# in: esi = start
	mov	edi, offset icmp_checksum	# in: edi = start/base
	call	protocol_checksum
	pop	ecx
	pop	edi

	add	edi, ecx

	# done, send the packet.

	.if NET_ICMP_DEBUG
		printlnc 11, "Sending ICMP PING response"
	.endif

	pop	esi
	NET_BUFFER_SEND
9:	ret
1:	pop	esi
	ret

