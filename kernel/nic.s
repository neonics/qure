############################################################################
# Network Interface API
#
.intel_syntax noprefix
.code32

############################################################################
IFCONFIG_OLDSKOOL = 0

NIC_MCAST_RX_MEMBER_ONLY = 0	# 1: only net_igmp_join-ed 224/3 IP's; 0=all

NIC_DEBUG = 0
############################################################################
DECLARE_CLASS_BEGIN nic, dev_pci
nic_status:	.word 0
	NIC_STATUS_UP = 1
nic_mac:	.space 6
nic_mcast_list:	.long 0	# ptr_array of mcast (224/3) addresses (igmp.s)
nic_ip:		.long 0
nic_netmask:	.long 0
.if IFCONFIG_OLDSKOOL
nic_network:	.long 0
.endif
nic_buf:	.long 0	# mallocced address
nic_rx_buf:	.long 0
nic_tx_buf:	.long 0
nic_rx_desc:	.long 0
nic_rx_desc_h:	.long 0
nic_rx_desc_t:	.long 0
nic_tx_desc:	.long 0
nic_tx_desc_h:	.long 0
nic_tx_desc_t:	.long 0
nic_rx_count:	.long 0
nic_tx_count:	.long 0
nic_rx_bytes:	.long 0, 0
nic_tx_bytes:	.long 0, 0
nic_rx_dropped:	.long 0
# API - method pointers
.align 4
DECLARE_CLASS_METHODS
DECLARE_CLASS_METHOD nic_api_ifup,	0
DECLARE_CLASS_METHOD nic_api_ifdown,	0
DECLARE_CLASS_METHOD nic_api_send,	0
DECLARE_CLASS_METHOD nic_api_print_status, 0
DECLARE_CLASS_END nic
############################################################################
.data
nics:	.long 0	# ptr_array of device offsets
# usage: (without checks)
# mov eax, [nics]
# mov edx, [eax]	# assume [eax + array_index] > 0
# mov eax, [devices]	# now [eax + edx] = nic device pointer
############################################################################
.text32
# set up the NIC shortlist
# out: eax = [nics]
# out: CF
nic_init:
	mov	eax, [nics]
	or	eax, eax
	jnz	9f
	# iterate the class_instances to find nics
	push_	esi edx ebx
	mov	esi, [class_instances]
	or	esi, esi
	jz	91f
	mov	ebx, esi	# base ptr
	add	ebx, [ebx + array_index]	# last offset


########
0:	lodsd	# object
	mov	edx, offset class_nic
	call	class_instanceof
	jnz	3f
##
	push	eax
	PTR_ARRAY_NEWENTRY [nics], 1, 92f
	add	edx, eax
	pop	dword ptr [edx]
###
3:	cmp	esi, ebx	# check next object
	jb	0b
########
8:	mov	eax, [nics]
	or	eax, eax
	jnz	1f
	stc
1:	pop_	ebx edx esi
9:	ret

91:	printlnc 4, "nic_init: class_instances null"
	stc
	jmp	8b
92:	printlnc 4, "nic_init: out of memory"
	stc
	jmp	8b

# in: eax = nic index (not offset!)
# out: eax + edx = nic pointer
# out: ebx = nic object
# OUT: ZF = 1: no nic; 0: got a nic
nic_getobject:
	lea	edx, [eax * 4]
	call	nic_init
	jc	1f
	cmp	edx, [eax + array_index]
	cmc
	jc	1f
	mov	ebx, [eax + edx]
	.if NIC_DEBUG
		DEBUG_DWORD ebx, "found nic object"
		call	dev_print
		call	newline
	.endif
	clc
1:	ret


.if IFCONFIG_OLDSKOOL
# in: eax = ip
# out: ebx = device for the network of ip (using device's netmask)
# out: CF
nic_get_by_network:
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi
	mov	esi, eax
	call	nic_init	# out: eax, ebx
	jc	9f
	xor	ebx, ebx	# used to be base addr for *[nic] ptr's
	ARRAY_ITER_START eax, edx
	mov	ecx, [eax + edx]
	mov	edi, esi
	and	edi, [ebx + ecx + nic_netmask]
	cmp	edi, [ebx + ecx + nic_network]
	jz	0f
	ARRAY_ITER_NEXT eax, edx, 4
	stc
	jmp	9f
0:	add	ebx, ecx
9:
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret
.endif

# in: ebx = nic
# out: eax = ipv4
nic_get_ipv4:
	mov	eax, [ebx + nic_ip]	# NEW: ebx = abs!
	ret

# in: eax = ip
# out: ebx = nic
# out: CF
# does not preserve ebx on error/no match
nic_get_by_ipv4:
	push_	eax esi
	mov	esi, eax
	call	nic_init	# out: eax = [nics], ebx = [devices]
	jc	2f
	xor	ebx, ebx	# used to be base addr for *[nic] ptr's
	push_	edx ecx
	ARRAY_ITER_START eax, edx
	mov	ecx, [eax + edx]	# nic device index
	cmp	esi, [ebx + ecx + nic_ip]
	jz	0f

	# check if net broadcast
	# NOTE: if there are multiple NICs on the same subnet, ...
	push	eax
	mov	eax, [ebx + ecx + nic_netmask]
	not	eax
	or	eax, [ebx + ecx + nic_ip]
	cmp	esi, eax
	mov	eax, esi
	pop	eax
	jz	0f

	# check mcast membership
	push_	ebx eax
	mov	eax, esi
	shr	al, 4
	cmp	al, 0b1110	# 224.0.0.0/3
.if NIC_MCAST_RX_MEMBER_ONLY
	jnz	3f		# not multicast
	mov	eax, esi
	add	ebx, ecx
	call	net_igmp_ismember
3:
.endif
	pop_	eax ebx
	jz	0f

	add	edx, 4
	ARRAY_ITER_NEXT eax, edx, 4
	stc
	jmp	1f
0:	add	ebx, ecx
1:	pop_	ecx edx

2:	pop_	esi eax
	ret

nic_get_by_ipv6:
	stc
	ret

# in: esi = mac pointer
# out: ebx = nic
nic_get_by_mac:
	push	eax
	call	nic_init	# out: eax = nics, ebx = devices
	jc	2f
	xor	ebx, ebx	# used to be base addr for *[nic] ptr's

	push	edx
	push	ecx

	PTR_ARRAY_ITER_START eax, edx, ref = ecx # nic device index
	push	edi
	push	esi
	lea	edi, [ebx + ecx + nic_mac]
	cmpsd
	jnz	3f
	cmpsw
3:	pop	esi
	pop	edi
	jz	0f
	PTR_ARRAY_ITER_NEXT eax, edx, ref = ecx
	stc
	jmp	1f
0:	add	ebx, ecx
1:	pop	ecx
	pop	edx

2:	pop	eax
	ret



###########################################################################

nic_list_short:
	mov	eax, [nics]
	or	eax, eax
	jz	2f
	mov	ecx, [eax + array_index]
	shr	ecx, 2	# pointer
	jz	2f
	xor	edx, edx
0:	print_ "eth"
	call	printdec32
	call	printspace
	add	eax, 4	# pointer
	inc	edx
	loop	0b
2:	ret

############################################################################
# NIC Base Class API

###########################################
############################################
# protected methods (to be called by subclasses)

# in: ebx = nic
# in: eax = descriptor size
# in: ecx = rx descriptors
# in: edx = tx descriptors
NIC_ALLOC_BUF_OPTIMIZE = 0

.macro NIC_ALLOC_BUFFERS nrx, ntx, descSize, packetSize, errLabel, align=0
	_NIC_BUF_SLACK = 2 * \descSize + \align

	mov	eax, (\nrx + \ntx) * (\descSize + \packetSize) + _NIC_BUF_SLACK
	call	malloc
	jc	\errLabel
	mov	[ebx + nic_buf], eax
	.if \align != 0
	add	eax, \align -1
	and	eax, ~(\align -1)
	.endif
	.if NIC_ALLOC_BUF_OPTIMIZE
	mov	edi, eax
	lea	esi, [eax + (\nrx * \ntx) * \descSize + _NIC_BUF_SLACK]
	.else
	mov	[ebx + nic_rx_desc], eax
	add	eax, \nrx * \descSize
	mov	[ebx + nic_tx_desc], eax
	add	eax, (\nrx + \ntx) * \descSize
	mov	[ebx + nic_rx_buf], eax
	add	eax, \nrx * \packetSize
	mov	[ebx + nic_tx_buf], eax
	.endif
	_NIC_BUF_nrx = \nrx
	_NIC_BUF_ntx = \ntx
	_NIC_BUF_descSize = \descSize
	_NIC_BUF_pSize = \packetSize
	_NIC_BUF_err = \errLabel
.endm

.macro NIC_DESC_LOOP rxtx
	mov	ecx, _NIC_BUF_n\rxtx\()
	.if NIC_ALLOC_BUF_OPTIMIZE
	mov	[ebx + nic_\rxtx\()_buf], esi
	mov	[ebx + nic_\rxtx\()_desc], edi
	.else
	mov	esi, [ebx + nic_\rxtx\()_buf]
	mov	edi, [ebx + nic_\rxtx\()_desc]
	.endif
88:
.endm

.macro NIC_DESC_ENDL
	add	esi, _NIC_BUF_pSize
	add	edi, _NIC_BUF_descSize
	loop	88b
.endm

#####################
# default methods

nic_unknown_send:
	push	esi
	LOAD_TXT "send"
	jmp	0f

nic_unknown_print_status:
	push	esi
	LOAD_TXT "print_status"
	jmp	0f

nic_unknown_ifup:
	push	esi
	LOAD_TXT "ifup"
	jmp	0f

nic_unknown_ifdown:
	push	esi
	LOAD_TXT "ifdown"
	jmp	0f

0:	pushcolor 12
	print	"nic_"
	push	esi
	mov	esi, [ebx + dev_drivername_short]
	color	7
	call	print
	pop	esi
	color 12
	printchar '_'
	call	print
	printlnc 4, ": not implemented"
	popcolor
	pop	esi
	stc
	ret


############################################################################
# NIC API

cmd_nic_list:
	xor	eax, eax
	call	nic_getobject
	jc	2f

	xor	ecx, ecx
0:	call	nic_print

	inc	ecx
	mov	eax, ecx
	call	nic_getobject
	jnc	0b

	ret
2:	println "No NICs"
	ret

# in: ebx = device
nic_print:
	push_	eax edx esi
	call	dev_print
	call	printspace

	mov	esi, [ebx + dev_drivername_short]
	call	print

	print	" MAC "
	lea	esi, [ebx + nic_mac]
	call	net_print_mac

	call	newline

	print	"  IP "
	mov	eax, [ebx + nic_ip]
	pushcolor 15
	call	net_print_ipv4
	popcolor
	print	" MASK "
.if 1#IFCONFIG_OLDSKOOL
	mov	eax, [ebx + nic_netmask]
	call	net_print_ipv4
	print	" NET "
	and	eax, [ebx + nic_ip]
	call	net_print_ipv4
	print " BCAST "
	mov	eax, [ebx + nic_netmask]
	not	eax
	or	eax, [ebx + nic_ip]
	call	net_print_ipv4
.endif
	call	newline

	print	"  rx: "
	mov	edx, [ebx + nic_rx_count]
	call	printdec32
	print " ("
	mov	eax, [ebx + nic_rx_bytes + 0]
	mov	edx, [ebx + nic_rx_bytes + 4]
	call	print_size
	print ") tx: "
	mov	edx, [ebx + nic_tx_count]
	call	printdec32
	print " ("
	mov	eax, [ebx + nic_tx_bytes + 0]
	mov	edx, [ebx + nic_tx_bytes + 4]
	call	print_size

	print ") dropped: "
	mov	edx, [ebx + nic_rx_dropped]
	call	printdec32
	call	newline

	push	ecx
	push	ebx
	call	[ebx + nic_api_print_status]
	pop	ebx
	pop	ecx
	pop_	esi edx eax
	ret

############################################################################
# Commandline Interface

cmd_ifup:
	xor	eax, eax
	call	nic_getobject
	jc	1f
	call	[ebx + nic_api_ifup]
1:	ret

cmd_ifdown:
	xor	eax, eax
	call	nic_getobject
	jc	1f
	call	[ebx + nic_api_ifdown]
1:	ret


cmd_ifconfig:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	call	nic_parse	# out: ebx
	jc	9f

	push	esi
	mov	esi, [ebx + dev_drivername_short]
	pushcolor 9
	call	print
	call	printspace
	popcolor
	pop	esi
	.if IFCONFIG_OLDSKOOL
		xor	edi, edi
		mov	eax, [ebx + nic_gateway]
		mov	ecx, [ebx + nic_network]
		mov	edx, [ebx + nic_netmask]
		call	route_del	# in: ebx
		mov	ecx, 0xffffff00
		xor	ecx, ecx	# netmask
	.endif

	# check for options
0:	lodsd
	or	eax, eax
	jz	0f

	mov	edx, [eax]
	and	edx, 0x00ffffff
	cmp	edx, 'u' | ('p'<<8)
	jnz	1f

	push	esi
	call	[ebx + nic_api_ifup]
	pop	esi
	jmp	0b
1:
	mov	edx, [eax]
	cmp	edx, 'd' | ('o'<<8) | ('w'<<16) | ('n' << 24)
	jnz	1f
	cmp	byte ptr [eax + 4], 0
	jnz	1f

	push	esi
	call	[ebx + nic_api_ifdown]
	pop	esi
	jmp	0b

	1:
		CMD_ISARG "mask"
		jnz	1f

		lodsd
		call	net_parse_ip
		jc	9f
		printc 11, " mask "
		call	net_print_ip
		mov	[ebx + nic_netmask], eax

		#mov	ecx, eax

		#and	eax, [ebx + nic_ip]
		#cmp	eax, [ebx + nic_ip]
		#LOAD_TXT "netmask does not include ip"
		#jnz	9f

		jmp	0b

	.if IFCONFIG_OLDSKOOL
	1:
		CMD_ISARG "gw"
		jnz	1f
		lodsd
		call	net_parse_ip
		jc	9f
		printc 11, " gw "
		call	net_print_ip
		mov	[ebx + nic_gateway], eax
	.endif

1:
	# parse ip
	call	net_parse_ip
	jc	9f
	printc 11, "ip "
	call	net_print_ip
	call	newline
	mov	[ebx + nic_ip], eax

	.if IFCONFIG_OLDSKOOL
		mov	[ebx + nic_netmask], ecx # dword ptr 0x00ffffff
		and	eax, ecx # 0x00ffffff
		mov	[ebx + nic_network], eax
	.endif

	jmp	0b

0:	# print nic status
	call	[ebx + nic_api_print_status]

	.if IFCONFIG_OLDSKOOL
		mov	eax, [ebx + nic_gateway]
		mov	ecx, [ebx + nic_network]
		mov	edx, [ebx + nic_netmask]
		call	route_add	# in: ebx
	.endif

	clc
	ret

9:	printlnc 12, "usage: ifconfig <device> [up|down] [<ip>]"
	stc
	ret

# in: eax = string pointer
# out: ebx = device or CF
nic_parse:
	push	edx
	push	esi
	mov	esi, eax
	mov	edx, [esi]
	and	edx, 0x00ffffff
	jz	1f
	cmp	edx, ('h'<<16)|('t'<<8)|('e'<<0)
	jnz	1f
	add	eax, 3
	call	atoi
	jc	2f
	call	nic_getobject
	jc	3f
9:	pop	esi
	pop	edx
	ret

1:	printc 4, "nic_parse: unknown device type: "
	call	println
	stc
	jmp	9b

2:	printc 4, "nic_parse: malformed number: "
	print "eth"
	printcharc 13, '<'
	pushcolor 12
	add	esi, 3
	call	print
	popcolor
	printcharc 13, '>'
	call	newline
	stc
	jmp	9b

3:	printc 4, "nic_parse: unknown device: "
	call	println
	printc 4, "known devices: "
	call	nic_list_short
	call	newline
	stc
	jmp	9b

##############################################################################

# also see root/etc/init.rc for an alternative
# TODO: implement rfc3927 "Dynamic Configuration of IPv4 Link-Local Addresses"
nic_zeroconf:
	push	esi
	push	eax

	xor	eax, eax	# get the first NIC
	call	nic_getobject	# out: ebx (and eax+edx)
	jc	91f


	# default route without gateway
	.data
77:	STRINGPTR "route"
	STRINGPTR "add"
	STRINGPTR "default"
	# no gateway
	STRINGPTR "metric"
	STRINGPTR "0x80000010"	# little hack: 0x80000000=dynamic flag
	STRINGPTR "eth0"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_route
	jc	0f

	# multicast route
	.data
77:	STRINGPTR "route"
	STRINGPTR "add"
	STRINGPTR "net"
	STRINGPTR "224.0.0.0"
	STRINGPTR "mask"
	STRINGPTR "240.0.0.0"
	STRINGPTR "metric"
	STRINGPTR "0x00000080"
	STRINGPTR "eth0"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_route
	jc	0f

	# bring device up
	.data
77:	STRINGPTR "ifconfig"
	STRINGPTR "eth0"
	#STRINGPTR "0.0.0.0"	# redundant
	STRINGPTR "mask"
	STRINGPTR "255.255.255.0"
	STRINGPTR "up"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_ifconfig
	jc	0f

	# try DHCP ("dhcp eth0")
	call	nic_init_ip	# uses gratuitious ARP, DHCP
	jnc	1f


	# try the 192.168.1.0/24 local network
	.data
77:	STRINGPTR "ifconfig"
	STRINGPTR "eth0"
	STRINGPTR "192.168.1.0"
	STRINGPTR "mask"
	STRINGPTR "255.255.255.0"
	STRINGPTR "up"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_ifconfig

	# find a free IP
	mov	eax, 0x0201a8c0	# 192.168.1.2, but is incremented first:
10:	rol	eax, 8
	inc	al
	cmp	al, 254
	jae	0f
	ror	eax, 8
	call	net_arp_resolve_ipv4
	jnc	10b

	print "Found free IP: "
	call	net_print_ipv4
	call	newline

	# set up local route
	call    net_route_delete_dynamic        # in: ebx
	.data
77:	STRINGPTR "route"
	STRINGPTR "add"
	STRINGPTR "net"
	STRINGPTR "192.168.1.0"
	STRINGPTR "mask"
	STRINGPTR "255.255.255.0"
	STRINGPTR "metric"
	STRINGPTR "0x80000080"	# little hack: 0x80000000=dynamic flag
	STRINGPTR "eth0"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_route
	jc	0f

	# set up default gateway
	.data
77:	STRINGPTR "route"
	STRINGPTR "add"
	STRINGPTR "default"
	STRINGPTR "gw"
	STRINGPTR "192.168.1.1"
	STRINGPTR "metric"
	STRINGPTR "0x80000010"	# little hack: 0x80000000=dynamic flag
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_route
	jc	0f
1:
.if 0
	.data
77:	STRINGPTR "ping"
	STRINGPTR "192.168.1.1"
	STRINGNULL
	.text32
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_ping
	jc	0f
.endif
0:
	pop	eax
	pop	esi
	ret
91:	printlnc 4, "No network interaces"
	jmp	0b


# in: ebx
nic_init_ip:
	print "  MAC "
	lea	esi, [ebx + nic_mac]
	call	net_print_mac
	call	newline
	print "  IP "
	xor	eax, eax
	xchg	eax, [ebx + nic_ip]
	call	net_print_ipv4
	mov	edx, eax	# remember original IP

	# gratuitious arp
	or	eax, eax
	jz	2f	# ip is 0, so no ip.
	call	net_arp_resolve_ipv4
	jnc	1f	# if not error then in use
	mov	[ebx + nic_ip], edx
	mov	eax, edx
	printlnc 10, "Ok"
	clc
	ret

# ip in use
1:	printc 12, " in use"
2:	print " - DHCP "

	mov	ecx, 100	# 100 * .1s = 10s
0:
	test	cl, 7
	jnz	2f
	printchar '.'
	mov	dl, 1
	xor	eax, eax
	push ecx
	call	net_dhcp_request
	pop ecx
2:
	mov	eax, 100	# .1s
	call	sleep
	cmp	dword ptr [ebx + nic_ip], 0
	jnz	1f
	loop	0b
	printlnc 4, " fail"
	stc
	ret

1:	mov	eax, [ebx + nic_ip]
	call	printspace
	call	net_print_ipv4
	OK
	clc
	ret

9:	printlnc 4, "no network interfaces"
	stc
	ret
