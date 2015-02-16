############################################################################
# IPv4 Routing

ROUTE_DEBUG = 0

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
	call	printhex4
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
.global net_route_get
net_route_get:
		.if ROUTE_DEBUG
			DEBUG "route"; call net_print_ip;call printspace;
		.endif
	push	ebp		# temp gateway
	push	edi		# array base
	push	ecx		# array index
	push	esi		# metric
	xor	esi, esi
	xor	ebp, ebp
	ARRAY_LOOP [net_route], NET_ROUTE_STRUCT_SIZE, edi, ecx, 9f
	cmp	word ptr [edi + ecx + net_route_flags], -1
	jz	0f
	cmp	si, [edi + ecx + net_route_metric]
	ja	0f
	mov	edx, eax
	and	edx, [edi + ecx + net_route_netmask]	# zf=1 for default gw
		.if ROUTE_DEBUG
			pushf
			push	eax
			mov	eax, [edi + ecx + net_route_netmask]
			DEBUG "mask"
			call	net_print_ip
			DEBUG "net"
			mov	eax, [edi + ecx + net_route_network]
			call	net_print_ip
			DEBUG "ip&mask"
			mov	eax, edx
			call net_print_ip
			call printspace
			pop	eax
			popf
		.endif
	cmp	edx, [edi + ecx + net_route_network]
	jnz	0f
		.if ROUTE_DEBUG
			DEBUG "net match";
			push eax; mov eax, edx; call net_print_ip;pop eax
		.endif
1:	mov	ebp, [edi + ecx + net_route_gateway]
		.if ROUTE_DEBUG
			DEBUG "gw";
			push eax; mov eax, ebp; call net_print_ip;pop eax
		.endif
	or	ebp, ebp
	jnz	1f
		.if ROUTE_DEBUG
			DEBUG "ignore,use:";
			call net_print_ip
		.endif
	mov	ebp, eax	# use ip as route
1:	mov	ebx, [edi + ecx + net_route_nic]
	mov	si, [edi + ecx + net_route_metric]
0:;		.if ROUTE_DEBUG
			DEBUG "curgw"
			push eax; mov eax,ebp; call net_print_ip;pop eax
			call newline
		.endif
	ARRAY_ENDL
		.if ROUTE_DEBUG
			DEBUG "target"
			push eax; mov eax, ebp; call net_print_ip;pop eax
			call newline
		.endif
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

####################

.data
.global lan_dmz_ip
lan_dmz_ip: .long 0
.text32
# in: eax = a global DMZ IP.
.global net_route_set_dmz_ip
net_route_set_dmz_ip:
	mov	[lan_dmz_ip], eax
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
	jnz	2f
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
	call	printhex4
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

9:	printlnc 12, "usage: route [print]"
	printlnc 12, "       route add [default] gw <ip> [metric <nr>] [<nic>]"
	printlnc 12, "       route add [net <ip>] [mask <ip>] gw <ip> [metric <nr>] [<nic>]"
	call	newline
	printlnc 12, "  metric: <nr> decimal or hex if prefixed with '0x'"
	printlnc 12, "          lower numbers: higher priority."
	printlnc 12, "  <ip>:   ipv4 only."
	printlnc 12, "  <nic>:  eth<X>, where X is decimal."
	jmp	0b

