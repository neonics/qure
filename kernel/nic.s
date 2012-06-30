############################################################################
# Network Interface API
#
.intel_syntax noprefix
.code32

############################################################################
NIC_DEBUG = 0
############################################################################
.struct DEV_PCI_STRUCT_SIZE
nic_status:	.byte 0
	NIC_STATUS_UP = 1
nic_name:	.space 8
nic_mac:	.space 6
nic_mcast:	.space 8
.align 4
nic_rx_buf:	.long 0
nic_ip:		.long 0
nic_netmask:	.long 0
nic_network:	.long 0
# API - method pointers
.align 4
nic_api:
nic_api_ifup:	.long 0
nic_api_ifdown:	.long 0
nic_api_send:	.long 0
nic_api_print_status: .long 0
NIC_API_SIZE = . - nic_api
NIC_STRUCT_SIZE = .
############################################################################
.data
nics:	.long 0	# ptr_array of device offsets
# usage: (without checks)
# mov eax, [nics]
# mov edx, [eax]	# assume [eax + array_index] > 0
# mov eax, [devices]	# now [eax + edx] = nic device pointer
############################################################################
.text
# set up the NIC shortlist
# out: eax = [nics]
# out: ebx = [devices]
# out: CF
nic_init:
	push	ecx
	push	edx

	mov	ebx, [devices]
	or	ebx, ebx
	jz	2f
	mov	eax, [nics]
	or	eax, eax
	jnz	0f	# cache

	.if NIC_DEBUG
		DEBUG "nic_init"
	.endif

	inc	eax
	call	ptr_array_new
	jc	0f
	mov	[nics], eax

	OBJ_ARRAY_ITER_START ebx, ecx

	cmp	[ebx + ecx + dev_type], byte ptr DEV_TYPE_PCI
	jnz	3f
	cmp	[ebx + ecx + dev_pci_class], byte ptr 2	# network devices
	jnz	3f

	call	ptr_array_newentry
	mov	[nics], eax
	mov	[eax + edx], ecx

3:	OBJ_ARRAY_ITER_NEXT ebx, ecx

0:	pop	edx
	pop	ecx
	ret

2:	printlnc 4, "nic_init: no devices"
	stc
	jmp	0b

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
	add	ebx, [eax + edx]
	.if NIC_DEBUG
		DEBUG "found nic object"
		call	dev_print
		call	newline
	.endif
	clc
1:	ret


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

# in: eax = ip
# out: ebx = nic
nic_get_by_ipv4:
	push	esi
	mov	esi, eax
	call	nic_init	# out: eax = [nics], ebx = [devices]
	jc	2f

	push	edx
	push	ecx
	ARRAY_ITER_START eax, edx
	mov	ecx, [eax + edx]	# nic device index
	cmp	esi, [ebx + ecx + nic_ip]
	jz	0f
	add	edx, 4
	ARRAY_ITER_NEXT eax, edx, 4
	stc
	jmp	1f
0:	add	ebx, ecx
1:	pop	ecx
	pop	edx

2:	pop	esi
	ret


# in: esi = mac pointer
# out: ebx = nic
nic_get_by_mac:
	push	eax
	call	nic_init	# out: eax = nics, ebx = devices
	jc	2f

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

nic_constructor:

	mov	[ebx + nic_name + 0], dword ptr ( 'u' | 'n'<<8|'k'<<16|'n'<<24)
	mov	[ebx + nic_name + 4], dword ptr ( 'o' | 'w'<<8|'n'<<16)

	# fill in all method pointers

	mov	dword ptr [ebx + nic_api_send], offset nic_unknown_send
	mov	dword ptr [ebx + nic_api_print_status], offset nic_unknown_print_status
	mov	dword ptr [ebx + nic_api_ifup], offset nic_unknown_ifup
	mov	dword ptr [ebx + nic_api_ifdown], offset nic_unknown_ifdown

	# check for supported drivers

	# RTL8139
	cmp	[ebx + dev_pci_device_id], word ptr 0x8139
	jnz	0f

	# good enough.
	push	edx
	mov	dx, [ebx + dev_io]
	or	dx, dx
	jz	1f
	call	rtl8139_init
	jc	1f
	# ...
1:	pop	edx
	jmp	9f

0:	# unknown nic

9:	# relocate the methods
	push	ecx
	push	eax
	mov	eax, [realsegflat]
	mov	ecx, NIC_API_SIZE / 4
0:	add	[ebx + nic_api + ecx * 4 - 4], eax
	loop	0b
	pop	eax
	pop	ecx
	ret


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
	lea	esi, [ebx + nic_name]
	color	7
	call	print
	pop	esi
	color 12
	printchar '_'
	call	print
	printlnc 4, ": not implemented"
	pop	esi
	popcolor
	stc
	ret


############################################### 
# Proxy methods
.if 0
# in: ebx = nic object
nic_ifup:
	pushad
	mov	edx, [ebx + nic_api_ifup]
	#add	edx, [realsegflat]
	call	edx
	popad
	jc	0f
	or	[ebx + nic_status], byte ptr NIC_STATUS_UP
0:	ret

# in: ebx = nic object
nic_ifdown:
	pushad
	mov	edx, [ebx + nic_api_ifdown]
	#add	edx, [realsegflat]
	call	edx
	popad
	jc	0f
	and	[ebx + nic_status], byte ptr NIC_STATUS_UP
0:	ret

# in: ebx = nic object
# in: esi
# in: ecx
nic_send:
	.if NIC_DEBUG 
		print	"Send packet: "
		push	eax
		mov	eax, [ebx + nic_ip]
		call	net_print_ip
		pop	eax
	.endif

	mov	edx, [ebx + nic_api_send]
	or	edx, edx
	jz	1f
	#add	edx, [realsegflat]
	pushad
	call	edx	# changes eax, edx
	popad
	ret
1:	printc 4, "nic_api_send not implemented for "
	push	esi
	mov	esi, [ebx + nic_name]
	call	println
	pop	esi
	ret

nic_print_status:
	pushad
	mov	edx, [ebx + nic_api_print_status]
	#add	edx, [realsegflat]
	call	edx
	popad
	ret
.endif
############################################################################
# NIC API

cmd_nic_list:
	xor	eax, eax
	call	nic_getobject
	jc	2f

	xor	ecx, ecx
0:	call	dev_print
	call	printspace

	lea	esi, [ebx + nic_name]
	call	print

	print	" MAC "
	lea	esi, [ebx + nic_mac]
	call	net_print_mac

	print	" IP "
	mov	eax, [ebx + nic_ip]
	call	net_print_ip

	print	" NETWORK "
	mov	eax, [ebx + nic_network]
	call	net_print_ip
	printchar_ '/'
	mov	eax, [ebx + nic_netmask]
	call	net_print_ip

	call	newline

	push	ecx
	push	ebx
	push	edx
	call	[ebx + nic_api_print_status]
	pop	edx
	pop	ebx
	pop	ecx

	inc	ecx
	mov	eax, ecx
	call	nic_getobject
	jnc	0b

	ret
2:	println "No NICs"
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

DEBUG_REGSTORE
	push	ebx
	call	dev_print
	call	printspace
	pop	ebx
DEBUG_REGDIFF

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
	# parse ip
	call	net_parse_ip
	jc	9f
	printc 11, "ip "
	call	net_print_ip
	mov	[ebx + nic_ip], eax
	mov	[ebx + nic_netmask], dword ptr 0x00ffffff
	and	eax, 0x00ffffff
	mov	[ebx + nic_network], eax
	call	newline
	jmp	0b

0:	# print nic status
	call	[ebx + nic_api_print_status]
	clc

	ret
9:	printlnc 12, "usage: ifconfig <device> <ip>"
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

nic_zeroconf:
	push	esi
	push	eax
	.data
77:	STRINGPTR "ifconfig"
	STRINGPTR "eth0"
	STRINGPTR "192.168.1.11"
	STRINGPTR "up"
	STRINGNULL
	.text
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_ifconfig
	jc	0f
	# set up route
	.data
77:	STRINGPTR "route"
	STRINGPTR "add"
	STRINGPTR "gw"
	STRINGPTR "192.168.1.1"
	STRINGNULL
	.text
	mov	esi, offset 77b
	mov	eax, esi
	call	cmdline_print_args$
	call	cmd_route
	jc	0f
0:	
	pop	eax
	pop	esi
	ret

