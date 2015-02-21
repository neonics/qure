###########################################################################
# DHCP
#
# rfc 2131 (protocol), rfc 1533 (options)
#
# TODO: match response packet mac before reconfiguring network.
# TODO: allow remote configuration changes using latest XID.

NET_DHCP_DEBUG = 0

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
	DHCP_OPT_RL_SERVER	= 11	# ?resource location server
	DHCP_OPT_HOSTNAME	= 12	# ?	string
	DHCP_OPT_BOOT_FILE_SIZE	= 13	# 2	sectors
	# 14=merit dump file (core dump file)
	DHCP_OPT_DOMAIN_NAME	= 15	# 1+	string
	DHCP_OPT_SWAP_SERVER	= 16	# ?
	DHCP_OPT_ROOT_PATH	= 17	# 1+	string (?)
	DHCP_OPT_EXT_PATH	= 18	# 1+	string (?)  extensions path (TFTP)
	DHCP_OPT_IPFW_ENABLE	= 19	# 1	0 or 1
	# 26 = interface mtu opt	# 2	unsigned word; 68+
	DHCP_OPT_ROUTER_DISCOVER= 31
	DHCP_OPT_STATIC_ROUTE	= 33

	DHCP_OPT_VENDOR_INFO	= 43 	# ? vendor specific info
	DHCP_OPT_NB_NAME_SERVER	= 44	# ? netbios/tcpip name server
	DHCP_OPT_NB_NODE_TYPE	= 46	# ? netbios/tcpip node type
	DHCP_OPT_NB_SCOPE	= 47	# ? netbios/tcpip scope

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
		DHCP_MT_INFORM			= 8
		DHCP_MT_FORCE_RENEW		= 9
		DHCP_MT_MAX_		= 9
	DHCP_OPT_SERVER_IP	= 54	# 4	ip
	DHCP_OPT_PARAM_REQ_LIST	= 55	# ?	option nr [,option nr,...]
	DHCP_OPT_MESSAGE	= 56	# 1+	string	(NAK/DECLINE err msg)
	DHCP_OPT_MAX_MSG_SIZE	= 57	# 2	576+ (DISCOVER/REQUEST)
	DHCP_OPT_RENEWAL_TIME	= 58	# 4	seconds	(T1) (assign->RENEW)
	DHCP_OPT_REBINDING_TIME	= 59	# 4	seconds	(T2) (assign->REBIND)
	DHCP_OPT_VENDOR_CLASSID	= 60	# 1+	string vendor class identifier ("MSFT 5.0")
	DHCP_OPT_CLIENT_ID	= 61	# 2+(7)	custom (hwtype(1),mac)
	DHCP_OPT_BOOT_FILENAME	= 67	# 1+	string (?)
	DHCP_OPT_CLIENT_FQDN	= 81	# 3+?	flags, A_RR, PTR_RR, string
	DHCP_OPT_CLIENT_SYSARCH	= 93	# word: 0 = IA x86 PC	Client System Architecture
	DHCP_OPT_CLIENT_DEVIFACE= 94	# NBO hi, lo client device interface
	DHCP_OPT_CLIENT_UUID	= 97	# 17
	DHCP_OPT_CLASSLESS_ST_RT= 121	# ?	 classless static route
	DHCP_OPT_DOCSIS		= 128	# ?
	DHCP_OPT_PXE_0		= 129	# ?	PXE
	DHCP_OPT_PXE_1		= 120	# ?	PXE
	DHCP_OPT_PXE_2		= 131	# ?	PXE
	DHCP_OPT_PXE_3		= 132	# ?	PXE
	DHCP_OPT_PXE_4		= 133	# ?	PXE
	DHCP_OPT_PXE_5		= 134	# ?	PXE
	DHCP_OPT_PXE_6		= 135	# ?	PXE
	DHCP_OPT_PVTCL_ST_RT	= 249	# ?	private/clasless static route (MSFT)
	DHCP_OPT_EOO		= 255	# N/A	N/A - end of options.

DHCP_HEADER_SIZE = .
.struct 0	# transaction list
# These are used both by the client and the server, depending on FLAG_SC
dhcp_txn_xid:		.long 0
dhcp_txn_nic:		.long 0
dhcp_txn_mac:		.space 6# mac of peer
dhcp_txn_server_ip:	.long 0	# ip of server offering
dhcp_txn_server_mac:	.long 0	# ip of server offering XXX MAC?
dhcp_txn_yiaddr:	.long 0	# ip server offered (0 for discover)
dhcp_txn_router:	.long 0
dhcp_txn_netmask:	.long 0
dhcp_txn_state:		.word 0	# lo byte = last sent msg; hi=last rx'd msg
dhcp_txn_flags:		.word 0
	DHCP_TXN_FLAG_SC	= 1<<0	# Server/Client: 1 = server
DHCP_TXN_STRUCT_SIZE = .
.data SECTION_DATA_BSS
dhcp_transactions:	.long 0	# array
random_state$:	.long 0
.text32

random:
	add	eax, [random_state$]
	add	eax, dword ptr [clock_ms]
	push	cx
	add	cl, al
	add	cl, ah
	shr	cl, 8-3
	ror	eax, cl
	pop	cx
	xor	[random_state$], eax
	ret

# in: ebx = nic
# out: ecx + edx
dhcp_txn_new:
.data; random_tested$: .byte 0;.text32;
cmp byte ptr [random_tested$], 1
jnz 1f
push eax
	orb [random_tested$], 1
.rept 10
	mov	eax, [ebx + nic_mac + 2]
	call random
	DEBUG_DWORD eax
.endr
pop	eax
1:

	push	eax
	# TODO: lock
	ARRAY_NEWENTRY [dhcp_transactions], DHCP_TXN_STRUCT_SIZE, 1, 9f
	mov	ecx, eax
	mov	[ecx + edx + dhcp_txn_nic], ebx
	mov	[ecx + edx + dhcp_txn_state], word ptr 0
	# random approximation:
	mov	eax, [ebx + nic_mac + 2]
	call	random
	mov	[ecx + edx + dhcp_txn_xid], eax
	mov	[ecx + edx + dhcp_txn_mac+0], dword ptr 0
	mov	[ecx + edx + dhcp_txn_mac+4], word ptr 0
9:	pop	eax
	# TODO: unlock
	ret


# destroys: eax, ebx, ecx, edx, esi
dhcp_txn_list:
	ARRAY_LOOP [dhcp_transactions], DHCP_TXN_STRUCT_SIZE, ebx, ecx, 9f
	testw	[ebx + ecx + dhcp_txn_flags], DHCP_TXN_FLAG_SC
	jz	1f	# client
	printc 13, "SERVER "
	jmp	2f
1:	printc 13, "CLIENT "
2:
	printc 11, "xid "
	mov	edx, [ebx + ecx + dhcp_txn_xid]
	call	printhex8

	printc 11, " MAC "
	lea	esi, [ebx + ecx + dhcp_txn_mac]
	call	net_print_mac

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
	call	newline
	printc 11, " server "
	mov	eax, [ebx + ecx + dhcp_txn_server_ip]
	call	net_print_ipv4
	printc 11, " yip "
	mov	eax, [ebx + ecx + dhcp_txn_yiaddr]
	call	net_print_ipv4
	printc 11, "/"
	mov	eax, [ebx + ecx + dhcp_txn_netmask]
	call	net_print_ipv4_mask
	printc 11, " gw "
	mov	eax, [ebx + ecx + dhcp_txn_router]
	call	net_print_ipv4


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
	mov	esi, offset mac_bcast
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
	.if 0	# can't enable yet unless + x is changed!
	push_	esi ecx edi
	mov	esi, offset hostname
	call	strlen_
	mov	[edi + dhcp_options + 9], cl
	lea	edi, [edi + dhcp_options + 10]
	rep	movsb
	pop_	edi esi ecx
	.else
	mov	[edi + dhcp_options + 9], byte ptr 4	# len
	mov	[edi + dhcp_options + 10], dword ptr ('Q'|'u'<<8|'R'<<16|'e'<<24)
	.endif

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
	# in: ecx = udp frame len
	mov	ecx, UDP_HEADER_SIZE + DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	call	net_udp_checksum

	# send packet

#	clc
#8:	# unused label
	pop	esi
#	jc	9f
	NET_BUFFER_SEND

9:	ret


###########################################################################
# DHCP protocol handlers

# client to server message:
# in: ebx = nic
# in: edx = ipv4 frame
# in: eax = udp frame
# in: esi = payload
# in: ecx = payload len
ph_ipv4_udp_dhcp_c2s:
	pushad
	mov	ebp, esp
	pushd	0	# dhcp txn element offset
	pushd	0	# client UUID

	.if NET_DHCP_DEBUG
		printlnc 11, "DHCP client to server"
		call	net_dhcp_print
	.endif

	# handler for DHCP server goes here.

	cmp	byte ptr [esi + dhcp_op], DHCP_OP_BOOTREQUEST
	jnz	91f

	# check type 1 (ethernet) hw addrsize 6
	cmp	word ptr [esi + dhcp_hwaddrtype], (6<<8)|1
	jnz	92f	# addresstype we don't know about


	mov	dl, DHCP_OPT_MSG_TYPE
	call	net_dhcp_get_option$
	jc	93f
	movzx	edi, byte ptr [edx]	# message type

	cmp	edi, DHCP_MT_MAX_
	ja	94f
	.if NET_DHCP_DEBUG
		DEBUG_WORD di, "Message type: "
		pushcolor 14
		pushd	[dhcp_message_type_labels$ + edi * 4]
		call	_s_println
		popcolor
	.endif

#DHCP_MT_DISCOVER                = 1
#DHCP_MT_OFFER                   = 2
#DHCP_MT_REQUEST                 = 3
#DHCP_MT_DECLINE                 = 4
#DHCP_MT_ACK                     = 5
#DHCP_MT_NAK                     = 6
#DHCP_MT_RELEASE                 = 7
	cmp	di, DHCP_MT_DISCOVER
	jz	1f
	cmp	di, DHCP_MT_REQUEST
	jnz	95f
1:
	mov	eax, [esi + dhcp_xid]
	# ecx (payload len), edx (ipv4 frame) no longer needed
	call	dhcp_txn_get	# out: ecx + edx
	jc	1f

		# XXX FIXME - assume received DISCOVER
		movb	[ecx + edx + dhcp_txn_state+1], DHCP_MT_REQUEST 
		movb	[ecx + edx + dhcp_txn_state], DHCP_MT_ACK  # premature but

	jmp	2f
1:	
	call	dhcp_txn_new	# out: ecx + edx
	jc	96f
		movb	[ecx + edx + dhcp_txn_state+1], DHCP_MT_DISCOVER
		movb	[ecx + edx + dhcp_txn_state+0], DHCP_MT_OFFER # premature but..
2:
		mov	[ebp - 4], edx
		mov	[ecx + edx + dhcp_txn_xid], eax
		movw	[ecx + edx + dhcp_txn_flags], DHCP_TXN_FLAG_SC # server entry
		# lo byte = last sent msg; hi=last rx'd msg

		# copy peer MAC
		mov	esi, [ebp + PUSHAD_EDX]	# get ipv4 frame
		lea	esi, [esi - ETH_HEADER_SIZE + eth_src]
		lea	edi, [ecx + edx + dhcp_txn_mac]
		movsd
		movsw
		# verify ETH MAC = DHCP client MAC
		mov	eax, [ebp + PUSHAD_ESI]		# DHCP frame
		lea	esi, [eax + dhcp_chaddr]	# client mac
		lea	edi, [ecx + edx + dhcp_txn_mac]
		mov	ecx, 3
		repz	cmpsw
		jnz	97f

		# check if the request contains a boot file name
		mov	dl, DHCP_OPT_PARAM_REQ_LIST	# in: dl = DHCP_OPT_...
		mov	esi, [ebp + PUSHAD_ESI]		# in: esi = dhcp frame
		mov	ecx, [ebp + PUSHAD_ECX]		# in: ecx = dhcp frame len
		call	net_dhcp_get_option$
		# out: eax = al = option len
		# out: edx = ptr to option ([eax-1]=opt len)
		# out: CF
		jc	98f
		mov	ecx, eax
		mov	esi, edx
	0:	lodsb
		cmp	al, DHCP_OPT_BOOT_FILENAME
		jz	0f
		loop	0b
		jmp	99f
	0:	
		# 3 required options (not in option list) accto RFC4578 (PXE for Intel)
		#
		# 94: client network interface identifier
		# len 3, type t = 1 (UNDI); .byte major(2), minor (1)
		# handled. (not copied though! XXX)
		
		# 93: client system architecture:
		# len: n (even, >0: usually word); .word type
		# type: 0=intel x86PC; 6=EFI IA32;9: EFI x86-64
		# handled (not copied xxx)

		# 97: client UUID (machine identifier)
		mov	dl, DHCP_OPT_CLIENT_UUID
		mov	esi, [ebp + PUSHAD_ESI]
		mov	ecx, [ebp + PUSHAD_ECX]
		call	net_dhcp_get_option$
		jc	910f
		mov	[ebp - 8], edx	# points to 17 bytes: .byte 0; .space 16 (GUID)

		# ok. Send a response
		call	dhcp_server_tx_disc_resp

9:	
	mov	esp, ebp	# free stack variables
	popad
	ret

.if NET_DHCP_DEBUG
91:	printlnc 14, "DHCP SERVER: not BOOTREQUEST"
	jmp	9b
92:	printlnc 12, "DHCP SERVER: unknown hw addrsize"
	jmp	9b
93:	printlnc 12, "DHCP SERVER: no MSG_TYPE opt"
	jmp	9b
94:	printlnc 12, "DHCP SERVER: unknown MSG_TYPE"
	jmp	9b
95:	printlnc 14, "DHCP SERVER: not DISCOVER/REQUEST"
	jmp	9b
96:	printlnc 12, "DHCP SERVER: transactino allocation fail"
	jmp	9b
97:	printlnc 12, "DHCP SERVER: ETH MAC != DHCP MAC"
	jmp	9b
98:	printlnc 12, "DHCP SERVER: no PARAM_REQ_LIST"
	jmp	9b
99:	printlnc 14, "DHCP_SERVER: no BOOT_FILENAME option"
	jmp	9b
910:	printlnc 12, "DHCP_SERVER: no CLIENT_UUID option"
	jmp	9b
.else
91:; 92:; 93:; 94:; 95:; 96:; 97:; 98:; 99:; 910:; 
jmp 9b; 
.endif
	

dhcp_server_tx_disc_resp:
	.if NET_DHCP_DEBUG
		printlnc 11, "DHCP Server: sending DISCOVER response"
	.endif

	# add copy of net_dhcp_request,
	# while iterating the options and setting values

	# POSSIBLY use the OFFER from the default gateway as IP settings
#net_dhcp_request:
# in: ebx = nic
	mov	ebx, [ebp + PUSHAD_EBX]
# in: eax = ptr to dhcp_txn structure (or 0: will be allocated)
	mov	eax, [ebp - 4]
	add	eax, [dhcp_transactions]

	NET_BUFFER_GET	# out: edi
	jc	91f
	push	edi	# start of ETH frame

	call	dhcp_make_tx_resp_packet$
		# udp checksum

	mov	eax, [ebx + nic_ip] # in: eax = src ip
	mov	edx, -1 # in: edx = dst ip
	#mov	esi, [esp] # in: esi = udp frame pointer
	# in: ecx = tcp frame len
	DHCP_OPTIONS_SIZE = 40 + 6*6 + 5+4+3+4 +19
	mov	ecx, UDP_HEADER_SIZE + DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
	#alternatively:
	#mov	ecx, edi
	#sub	ecx, [esp]
	#sub	ecx, ETH_HEADER_SIZE + IPV4_HEADER_SIZE
	# in: eax = src ip
	# in: edx = dest ip
	# in: esi = udp frame pointer
	# in: ecx = udp frame len (header and data)
	call	net_udp_checksum

	# send packet
	pop	esi
	NET_BUFFER_SEND
9:	ret

91:	printlnc 12, "DHCP SERVER: error allocating packet"
	jmp	9b


# in: ebx = NIC
# in: eax = DHCP_TXN (dhcp_transactions) struct ptr
# in: edi = start of network packet (ETH)
# out: edi = end of DHCP frame
# out: esi = UDP frame pointer
dhcp_make_tx_resp_packet$:
	DHCP_OPTIONS_SIZE = 40 + 6*6 + 5+4+3+4 +19
	# ETH, IPV4, UDP headers
	push	eax
		mov	eax, -1		# broadcast
		mov	esi, offset mac_bcast
		mov	dx, IP_PROTOCOL_UDP #| 1 << 8	# don't use ip

		mov	ecx, UDP_HEADER_SIZE + DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
		call	net_ipv4_header_put
		mov	esi, edi	# remember udp frame ptr for checksum
		mov	eax, (67 << 16) | 68	# sport dport: server->client
		mov	ecx, DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
		call	net_udp_header_put

		xor	eax, eax
		rep	stosb
		mov	ecx, DHCP_HEADER_SIZE + DHCP_OPTIONS_SIZE
		sub	edi, ecx
	pop	eax

	# DHCP header
	movb	[edi + dhcp_op], DHCP_OP_BOOTREPLY
	movb	[edi + dhcp_hwaddrtype], 1
	movb	[edi + dhcp_hwaddrlen], 6
	movb	[edi + dhcp_hops], 0	# due to rep stosb not needed
	push	eax
	mov	eax, [eax + dhcp_txn_xid]
	mov	[edi + dhcp_xid], eax
	pop	eax
	movw	[edi + dhcp_secs], 0	# due to rep stosb not needed
	mov	[edi + dhcp_flags], word ptr 0x0080 # broadcast

	# addresses:
	mov	[edi + dhcp_ciaddr], dword ptr 0 # XXX client ip from request
	YIADDR = 192 | (168<<8) | ( 1 << 16 ) | ( 50 << 24 )
	mov	[edi + dhcp_yiaddr], dword ptr YIADDR # XXX FIXME
	push	eax
	mov	eax, [ebx + nic_ip]
	mov	[edi + dhcp_siaddr], eax	# next server ip (bootp)
	mov	[edi + dhcp_giaddr], eax	# 'relay agent' (gw) (bootp)
	pop	eax

	# client hw addr
	push_	esi
	mov	esi, [ebp + PUSHAD_ESI]		# DHCP frame
	lea	esi, [esi + dhcp_chaddr]	# client mac
	add	edi, offset dhcp_chaddr
	movsd
	movsw
	pop	esi
	sub	edi, offset dhcp_chaddr + 6	# reset edi to DHCP packet start

	# sname: server host name (64)
	#mov	[edi + dhcp_sname], 
	# file: boot filename (128)
	push_	edi esi ecx
	LOAD_TXT "/boot.img", esi, ecx
	lea	edi, [edi + dhcp_file]
	rep	movsb
	pop_	ecx esi edi

	mov	dword ptr [edi + dhcp_magic], DHCP_MAGIC

	# DHCP options
	push	eax	# backup txn ptr
	OPT_OFFS = 0

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_MSG_TYPE	# dhcp message type
	movb	[edi + dhcp_options + OPT_OFFS + 1], byte ptr 1	# len
	mov	dl, [eax + dhcp_txn_state]	# DHCP_MT_OFFER/ACK
	mov	[edi + dhcp_options + OPT_OFFS + 2], dl
	#mov	[edi + dhcp_options + 2], byte ptr 1	# message type: see dl above
	OPT_OFFS = OPT_OFFS + 3

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_SERVER_IP
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	eax, [ebx + nic_ip]
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_IP_LEASE_TIME
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	eax, 3600*24
	bswap	eax
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_SUBNET_MASK
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	eax, [ebx + nic_netmask]
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_ROUTER
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	and	eax, [ebx + nic_ip]	# calc network
	or	eax, 1 << 24	# .1	# XXX
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_NAME_SERVER
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax	# XXX (gw ip)
	OPT_OFFS = OPT_OFFS + 6


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_VENDOR_CLASSID
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], dword ptr ('Q')|('u'<<8)|('R'<<16)|('e'<<24)
	OPT_OFFS = OPT_OFFS + 6


	# EAX = gw ip
# TODO URGENT XXX add to DHCP_OPTIONS_SIZE

	# just send some response options found in the request
	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_DNS
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax	# XXX (gw ip)
	OPT_OFFS = OPT_OFFS + 6

	mov	eax, [ebx + nic_ip]
	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_RL_SERVER
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_HOSTNAME
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], dword ptr ('t')|('e'<<8)|('s'<<16)|('t'<<24)
	OPT_OFFS = OPT_OFFS + 6


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_BOOT_FILE_SIZE
	movb	[edi + dhcp_options + OPT_OFFS + 1], 2	# must be 2
	push	eax
	push	ecx	# get boot image filesize
		LOAD_TXT "/a/boot/pxeboot.img", eax
		mov     cl, [boot_drive]
		add     cl, 'a'
		mov     [eax + 1], cl
		KAPI_CALL fs_stat		# in: eax; out: ecx, al
		lea	eax, [ecx + 511]	# rounding
		shr	eax, 9			# convert to sectors
	pop	ecx
	xchg	al, ah	# bswap for nbo
	mov	[edi + dhcp_options + OPT_OFFS + 2], ax	# sectors!
	pop	eax
	OPT_OFFS = OPT_OFFS + 6 # leave for now - actually + 4 (.byte 0,0=padding


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_DOMAIN_NAME
	movb	[edi + dhcp_options + OPT_OFFS + 1], 2
	mov	[edi + dhcp_options + OPT_OFFS + 2], dword ptr ('q')|('r'<<8)
	OPT_OFFS = OPT_OFFS + 4

	
	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_SWAP_SERVER
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], eax
	OPT_OFFS = OPT_OFFS + 6


	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_ROOT_PATH
	movb	[edi + dhcp_options + OPT_OFFS + 1], 1
	mov	[edi + dhcp_options + OPT_OFFS + 2], byte ptr '/'
	OPT_OFFS = OPT_OFFS + 3

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_EXT_PATH
	movb	[edi + dhcp_options + OPT_OFFS + 1], 4
	mov	[edi + dhcp_options + OPT_OFFS + 2], dword ptr ('/')|('e'<<8)|('x'<<16)|('t'<<24)
	OPT_OFFS = OPT_OFFS + 6

	
	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_CLIENT_SYSARCH
	movb	[edi + dhcp_options + OPT_OFFS + 1], 2
	movw	[edi + dhcp_options + OPT_OFFS + 2], 0	# IA x86 PC
	OPT_OFFS = OPT_OFFS + 4

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_CLIENT_DEVIFACE
	movb	[edi + dhcp_options + OPT_OFFS + 1], 3
	movb	[edi + dhcp_options + OPT_OFFS + 2], 1	# type? 1= UNDI?
	movb	[edi + dhcp_options + OPT_OFFS + 3], 2	# major version	
	movb	[edi + dhcp_options + OPT_OFFS + 4], 1	# minor version	
	OPT_OFFS = OPT_OFFS + 5
	# SKIP: vendor class identifier: opt 60, len 32,"PXEClient:Arch:00000:UNDI:002001"
	# SKIP: opt 57 max DHCP msg size (1260)
	# opt 97 (UUID/GUID client id), len 17,...

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_CLIENT_UUID
	movb	[edi + dhcp_options + OPT_OFFS + 1], 17
	push_	edi esi
	lea	edi, [edi + dhcp_options + OPT_OFFS + 2]
	mov	esi, [ebp - 8]
	movsb	# type 0 (GUID)
	movsd
	movsd
	movsd
	movsd
	pop_	esi edi
	OPT_OFFS = OPT_OFFS + 19
	

	# PARAMETER REQUEST LIST:
	# 1 subnet mask CHECK
	# 2 time offset
	# 3 router
	# 5 name server
	# 6 domain name server
	# 11 resource location server
	# 12 hostname
	# 13 boot file size
	# 15 domain name
	# 16 swap server
	# 17 root path
	# 18 extensions path
	# 43 vendor specific info
	# 54 DHCP server identifie
	# 60 vendor class identifier
	# 67 bootfile name
	# 128 DOCSIS full security server ip
	# 129 PXE
	# ..
	# 135 PXE


# END ADD TO DHCP_OPTIONS_SIZE
	
	pop	eax	# restore txn ptr

	movb	[edi + dhcp_options + OPT_OFFS + 0], DHCP_OPT_EOO	# end of options
	add	edi, DHCP_HEADER_SIZE + OPT_OFFS + 1
	ret



# server to client message:
# in: ebx = nic
# in: edx = ipv4 frame
# in: eax = udp frame
# in: esi = payload
# in: ecx = payload len
ph_ipv4_udp_dhcp_s2c:
	.if NET_DHCP_DEBUG
		printlnc 11, "DHCP server to client"
		call	net_dhcp_print
	.endif

	cmp	byte ptr [esi + dhcp_op], DHCP_OP_BOOTREPLY
	jnz	19f

######## verify eth and dhcp dest mac
	push_	esi edi ecx
	mov	ecx, esi

	# verify eth mac dest
	lea	edi, [edx - ETH_HEADER_SIZE + eth_dst]

	# check for broadcast dest mac
	mov	eax, -1
	scasd
	jnz	1f
	scasw
	jz	2f

1:	lea	edi, [ebx + nic_mac]
	lea	esi, [edx - ETH_HEADER_SIZE + eth_dst]
	cmpsd
	jnz	2f
	cmpsw
	jnz	1f
2:	# eth mac either bcast or our mac
	mov	esi, ecx

	# check the MAC field in the DHCP packet

	# check type 1 (ethernet) hw addrsize 6
	cmp	word ptr [esi + dhcp_hwaddrtype], (6<<8)|1
	jnz	1f	# addresstype we don't know about

	lea	edi, [esi + dhcp_chaddr]
	lea	esi, [ebx + nic_mac]
	cmpsd
	jnz	1f
	cmpsw

1:	pop_	ecx edi esi
	jnz	9f
########

	# verify destination in ipv4 frame
	mov	eax, [edx + ipv4_dst]
	cmp	eax, -1
	jz	1f
	# compare with nic ip
	cmp	eax, [ebx + nic_ip]
	jnz	9f
1:

	mov	dl, DHCP_OPT_MSG_TYPE
	call	net_dhcp_get_option$
	jc	18f
	movzx	edi, byte ptr [edx]	# message type

	cmp	edi, DHCP_MT_MAX_
	ja	17f
	.if NET_DHCP_DEBUG
		pushd	[dhcp_message_type_labels$ + edi * 4]
		call	_s_print
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

	# configure nic ip
	mov	eax, [esi + dhcp_yiaddr]
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
		print " router: "
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
	# configure nic mask
	mov	[ebx + nic_netmask], edx

	.if NET_DHCP_DEBUG
		print " netmask: "
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

# in: ebx = nic
# in: edx = ipv4 frame
# in: eax = udp frame
# in: esi = payload
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
	add	edx, [realsegflat]	# XXX legacy
	call	edx
	jmp	9f

1:	mov	edx, ecx
	printchar_ ','
	call	printdec32

9:	printcharc_ 1, ']'
	ret


# idem, almost - doesn't call print handler (just option nr + label)
# for use in request param list
#
# in: al
# destroys: ah
dhcp_print_option_2$:
	push	edx
	push	esi

	pushcolor 8
	movzx	edx, al
	call	printdec32
	call	printspace
	popcolor

	call	dhcp_option_get_label$	# out: edx
	jc	1f

	mov	esi, [edx]
	mov	ah, 11
	call	printc

1:	printcharc 8,','
	pop	esi
	pop	edx
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
# params
DHCP_DECLARE_OPTION_LABEL 1, 	ip,	"subnet mask"	# garbled printed
DHCP_DECLARE_OPTION_LABEL 2, 	time,	"time offset"	# seconds
DHCP_DECLARE_OPTION_LABEL 3, 	ip,	"router"
DHCP_DECLARE_OPTION_LABEL 4, 	ip,	"time server"
DHCP_DECLARE_OPTION_LABEL 5, 	ip,	"name server"
DHCP_DECLARE_OPTION_LABEL 6, 	ip,	"domain name server"
DHCP_DECLARE_OPTION_LABEL 11,	0,	"resource location server"
DHCP_DECLARE_OPTION_LABEL 12,	s,	"hostname"
DHCP_DECLARE_OPTION_LABEL 13,	0,	"boot file size"
DHCP_DECLARE_OPTION_LABEL 15,	s,	"domain name"
DHCP_DECLARE_OPTION_LABEL 16,	0,	"swap server"
DHCP_DECLARE_OPTION_LABEL 17,	0,	"root path"
DHCP_DECLARE_OPTION_LABEL 18,	0,	"extensions path"
DHCP_DECLARE_OPTION_LABEL 31, 	0,	"router discover"
DHCP_DECLARE_OPTION_LABEL 33, 	0,	"static route"
DHCP_DECLARE_OPTION_LABEL 43, 	0,	"vendor specific info"
DHCP_DECLARE_OPTION_LABEL 44, 	0,	"netbios name server"
DHCP_DECLARE_OPTION_LABEL 46, 	0,	"netbios node type"
DHCP_DECLARE_OPTION_LABEL 47, 	0,	"netbios scope"
DHCP_DECLARE_OPTION_LABEL 50,	ip,	"requested ip address"
DHCP_DECLARE_OPTION_LABEL 51,	time,	"lease time"
DHCP_DECLARE_OPTION_LABEL 53,	mt,	"message type" #1, ? = message type, len 1, 1=DISCOVER,2=offer,3=req,4=decline,5=ACK, 8=inform"
DHCP_DECLARE_OPTION_LABEL 54,	ip,	"server_ip"
DHCP_DECLARE_OPTION_LABEL 54,	0,	"dhcp server identifier"	# XXX dup!
DHCP_DECLARE_OPTION_LABEL 55,	optlst,	"param req list"
DHCP_DECLARE_OPTION_LABEL 56,	s,	"message"
DHCP_DECLARE_OPTION_LABEL 57,	0,	"max message size"	# TODO: print value (word)
DHCP_DECLARE_OPTION_LABEL 58,	time,	"renewal time"		# 4, seconds
DHCP_DECLARE_OPTION_LABEL 59,	time,	"rebinding time"	# 4, seconds
DHCP_DECLARE_OPTION_LABEL 60, 	s,	"vendor class identifier"
DHCP_DECLARE_OPTION_LABEL 61,	cid,	"client identifier" #hwtype=1(ethernet), mac (client identifier)"
DHCP_DECLARE_OPTION_LABEL 67,	s,	"bootfile name"
DHCP_DECLARE_OPTION_LABEL 81,	s,	"client fqdn"
DHCP_DECLARE_OPTION_LABEL 93,	0,	"client system architecture" # TODO: print value (word; 0 = IA x86 PC)
DHCP_DECLARE_OPTION_LABEL 94,	0,	"client device interface" # TODO: print (version: byte hi, byte lo (network order));
DHCP_DECLARE_OPTION_LABEL 97,	0,	"client uuid"		# TODO: print value (17 bytes)
DHCP_DECLARE_OPTION_LABEL 121,	0,	"classless static route"
DHCP_DECLARE_OPTION_LABEL 128,	0,	"DOCSIS"
DHCP_DECLARE_OPTION_LABEL 129,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 130,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 131,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 132,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 133,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 134,	0,	"PXE"
DHCP_DECLARE_OPTION_LABEL 135,	0,	"PXE"
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


# DHCP Option 55: Parameter Request List 
dhcp_opt_print_optlst:
0:	lodsb
	push	ecx
	call	dhcp_print_option_2$
	pop	ecx
	loop	0b
	ret

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

