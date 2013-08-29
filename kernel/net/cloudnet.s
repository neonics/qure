###############################################################################
# CloudNet - Clustered Distributed Network
.intel_syntax noprefix
.text32

#############################
.global cmd_cloudnetd
.global cmd_cloud

CLOUD_PACKET_DEBUG = 0


CLOUD_LOCAL_ECHO = 1

# start daemon
cmd_cloudnetd:
	I "Starting CloudNet Daemon"

	# start worker thread/task
	PUSH_TXT "cloudnet"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset cloudnet_daemon
	KAPI_CALL schedule_task
	jc	9f
	OK

9:	ret

######################################################
# worker/main daemon

.data
cloud_nic:	.long 0
cloud_sock:	.long 0
cloud_flags:	.long 0
	STOP$	= 1
.text32

cloudnet_daemon:
	orb	[cloud_flags], STOP$
	mov	eax, 100
	call	sleep	# nicer printing
	call	cloud_init_ip
	jc	9f
	call	cloud_socket_open
	jc	9f
	call	cloud_rx_start
	jc	9f

0:	call	cloud_register
1:	mov	eax, 10000
	call	sleep

	testd	[cloud_flags], STOP$
	jz	0b

#	printlnc 11, " idle"
 	jmp	1b

9:	ret


cloud_init_ip:
	printlnc 11, "cloud initialising"
	printlnc 13, " address verification "
	xor	eax, eax
	call	nic_getobject
	jc	9f
	mov	[cloud_nic], ebx
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
	call	net_arp_resolve_ipv4
	jnc	1f	# if not error then in use
	mov	[ebx + nic_ip], edx
	printlnc 10, "Ok"
	clc
	ret

# ip in use
1:	printc 12, " in use"
	print " - DHCP "

	mov	ecx, 100	# 100 * .2s = 10s
0:	
	test	cl, 7
	jnz	2f
	printchar '.'
	mov	dl, 1
	xor	eax, eax
	call	net_dhcp_request
2:
	mov	eax, 100	# .2s
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


# out: eax
cloud_socket_open:

	mov	eax, [clock]
	mov	[tx_clock$], eax

	xor	eax, eax	# IPV4
	mov	edx, IP_PROTOCOL_UDP << 16 | 999
	mov	ebx, SOCK_READPEER
	KAPI_CALL socket_open
	jc	9f
	mov	[cloud_sock], eax

	printc 11, "CloudNet listening on "
	KAPI_CALL socket_print
	call	newline

	clc
9:	ret


cloud_register:
	printc 13, " register "
#	mov	eax, [cloud_sock]
	mov	ebx, [cloud_nic]
	mov	eax, -1
	incw	[packet_hello_nr$]
	call	cloud_send_hello
	ret


.data
packet_hello$:
.asciz "hello"
packet_hello_nr$:.long 0
packet_hello_end$ = .
.text32

.macro LOAD_PACKET p
	mov	esi, offset packet_\p\()$
	mov	ecx, offset packet_\p\()_end$ - packet_\p\()$;
.endm

# in: eax = dest
cloud_send_hello:
	LOAD_PACKET hello
	call	cloud_packet_send
	ret

cloud_packet_send:
	call	cloud_tx_throttle

	.if CLOUD_LOCAL_ECHO
		printc 9, "[cloud-tx] "
		call	print_addr$
		call	printspace
		call	cloudnet_packet_print
		call	newline
	.endif

	NET_BUFFER_GET		# cached buffers
	jc	9f
	push	eax		# dest ip
	mov	eax, edi
	push	edi
	####

	add	edi, ETH_HEADER_SIZE + IPV4_HEADER_SIZE + UDP_HEADER_SIZE
	mov	edx, edi	# payload start

	rep	movsb		# copy payload

	push	edi
	mov	ecx, edi	# packet end
	sub	ecx, edx	# - payload start = payload len
	mov	edi, eax	# packet start
	mov	eax, [esp+8]	# IPV4 dest
	mov	edx, (999<<16) | (999) # dport<<16|sport
	bswap	edx
	mov	esi, offset mac_bcast
	mov	ebx, [cloud_nic]
	call	net_put_eth_ipv4_udp_headers	# out: ebx=nic;
	pop	edi

	####
	pop	esi	# net buffer start
	.if CLOUD_PACKET_DEBUG
		DEBUG_DWORD esi
		mov ecx, edi
		sub ecx, esi
		call net_packet_print
	.endif
	NET_BUFFER_SEND		# automatic free
	pop	eax
	jnc	1f
	printc 4, "net_buf_send fail"
1: 	ret
9:	printc 4, "net_buf_get fail";
	ret;

.data
tx_count$:	.long 0
tx_clock$:	.long 0
tx_silence$:	.long 0		# delta clock
# throughput, count, throttle
.text32
cloud_tx_throttle:
	push_	eax edx ecx
	incd	[tx_count$]
	mov	eax, [tx_clock$]
	mov	edx, [clock]
	mov	[tx_clock$], edx
	sub	edx, eax		# eax = delta time
	add	[tx_silence$], edx

	mov	eax, edx
	xor	edx, edx
	mov	ecx, [tx_count$]

#	DEBUG_DWORD ecx; DEBUG_DWORD eax; DEBUG_DWORD edx
	div	ecx	# silence : 0 / count
#	DEBUG_DWORD eax; DEBUG_DWORD edx
1:	pop_	ecx edx eax
	ret


######################################################
# listener daemon

# start listener thread/task
cloud_rx_start:
	printc 13, " start rx "
	PUSH_TXT "cloudnet-rx"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset cloudnet_rx
	mov	eax, [cloud_sock]
	KAPI_CALL schedule_task
	jc	9f
	OK
	clc
	ret
9:	printlnc 4, "fail"
	stc
	ret


cloudnet_rx:
0:	mov	cl, 1	# ecx != 0: blocking read
	KAPI_CALL socket_read
	jc	0b

	# handle packet

	push	eax	# preserve server socket
	call	cloudnet_handle_packet
	pop	eax

	jmp	0b
	

9:	printlnc 4, "cloudnet: cannot open socket, terminating"
	ret


################################################
# Cluster Management
.data
cluster_ips:	.long 0	# ptr_array
.text32

# in: eax = ip
# in: esi, ecx = packet
# out: ZF = 0: added, ZF = 1: updated
cluster_add_node:
	push_	ebx
	mov	ebx, eax
	mov	eax, [cluster_ips]
	or	eax, eax
	jz	1f
	push_	edi ecx
	mov	edi, eax
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	mov	eax, ebx
	repnz	scasd
	pop_	ecx edi
	mov	eax, ebx
	jz	9f

1:	PTR_ARRAY_NEWENTRY [cluster_ips], 1, 9f	# out: eax+edx
	mov	[eax + edx], ebx
	printc 13, " add cluster node "
	mov	eax, ebx
	call	print_ip$
	call	newline
	or	eax, eax	# ZF = 0

9:	
	pop_	ebx
	ret

# in: esi,ecx = packet
# in: eax = remote ip, edx = ports
#
cloudnet_handle_packet:
	printc 11, "rx "

.if 1	# SOCK_READPEER (getsockflag;jz/jc?)
	# readpeer:
	mov	eax, [esi]		# peer ip
	mov	dx, word ptr [esi + 4]	# peer port
	xchg	dl, dh
	call	print_addr$

	print "->"

	mov	eax, [esi+ 6]		# peer ip
	mov	dx, word ptr [esi + 10]	# peer port
	call	print_addr$
	call	printspace
.endif
	push	esi
	add	esi, 12
	sub	ecx, 12
	call	cloudnet_packet_print
	pop	esi

	call	print_addr$
	call	newline

	mov	eax, [esi]	# peer ip
	call	cluster_add_node

	cmpd	[esi + 6], -1	# destination broadcast?
	jnz	1f
	printc 13, " respond "

		.data; respond_count$:.long 0;.text32
		incd	[respond_count$]
		cmpd	[respond_count$], 100
		ja	1f
	mov	dx, [esi + 12 + 6]
	mov	[packet_hello_nr$ + 2], dx 
	call	cloud_send_hello
	ret

1:	printlnc 13, " ignore"
	ret

print_ip$:
	cmp	eax, -1
	jnz	1f
	print "BCAST"
	ret
1:	call	net_print_ipv4
	ret

print_addr$:
	call	print_ip$
	printchar ':'
	call	printdec16
	ret


cloudnet_packet_print:
	push	esi
	push	edi
	push	eax
	pushcolor 8
	mov	edx, ecx
	call	printdec32
	call	printspace
#######
	color 15
# print binary
	push	ecx
0:	lodsb
	mov	edi, esi
	call	printchar
	or	al, al
	jz	0f
	loop	0b
0:	color 8
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	lodsb
	loop	0b
	mov	esi, edi
	pop	ecx

	color 15
	mov	edx, [esi]
	call	printdec16
	call	printspace
	ror	edx, 16
	call	printdec16
	ror	edx, 16
	call	printspace
	color 8
	call	printhex8
#######
	popcolor
	pop	eax
	pop	edi
	pop	esi
	ret

###############################################################################
# command interface
SHELL_COMMAND "cloud", cmd_cloud

cmd_cloud:
	lodsd
	lodsd

	or	eax, eax
	jnz	1f
	printc 11, "CloudNet status: "
	mov	ax, [cloud_flags]
	PRINTFLAG ax, STOP$, "passive", "active"
	call	newline

	mov	ebx, [cluster_ips]
	or	ebx, ebx
	jz	2f
	print "local cluster: "
	mov	edx, [ebx + array_index]
	shr	edx, 2
	call	printdec32
	call	newline

	ARRAY_LOOP [cluster_ips], 4, ebx, edx
	print "  "
	mov	eax, [ebx + eax]
	call	print_ip$
	call	newline
	ARRAY_ENDL
2:
	ret

1:	CMD_ISARG "start"
	jnz	1f
	andd	[cloud_flags], ~STOP$
	ret

1:	CMD_ISARG "stop"
	jnz	1f
	ord	[cloud_flags], STOP$
	ret

1:	printlnc 4, "usage: cloud <command> [args]"
	printlnc 4, " commands: start stop"
	ret
