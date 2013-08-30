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

	call	cloud_register

0:	mov	eax, 1000 * 60 * 5
	call	sleep
	testd	[cloud_flags], STOP$
	jnz	0b

	call	cluster_ping

 	jmp	0b

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
	jc	9f	# skip tx

	.if CLOUD_LOCAL_ECHO
		printc 9, "[cloud-tx] "
		call	print_ip$
		call	printspace
		call	cloudnet_packet_print
		call	newline
	.endif

	NET_BUFFER_GET		# cached buffers
	jc	91f
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
91:	printc 4, "net_buf_get fail";
9:	ret

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
.struct 0
node_addr:	.long 0
node_handshake: .long 0
node_cycles:	.long 0
node_clock_met:	.long 0
node_clock:	.long 0
NODE_SIZE = .
.data
cluster_ips:	.long 0	# ptr_array for scasd
cluster_nodes:	.long 0	# array of node struct
.text32

# in: eax = ip
# in: esi, ecx = packet
# out: ZF = 0: added, ZF = 1: updated
cluster_add_node:
	push_	eax ebx ecx edx
	mov	ebx, eax

	.if 1
	ARRAY_LOOP [cluster_nodes], NODE_SIZE, eax, edx, 1f
	cmp	ebx, [eax + edx + node_addr]
	jz	2f
	ARRAY_ENDL
	jmp	1f
2:	printc 13, " update node"
	mov	ebx, [clock]
	mov	[eax + edx + node_clock], ebx
	jmp	9f

	.else
	mov	eax, [cluster_ips]
	or	eax, eax
	jz	1f
	push_	edi ecx
	mov	edi, eax
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	mov	edx, ecx
	mov	eax, ebx
	repnz	scasd
	pop_	ecx edi
	jz	9f
	.endif

1:	PTR_ARRAY_NEWENTRY [cluster_ips], 1, 9f	# out: eax+edx
	mov	[eax + edx], ebx
	ARRAY_NEWENTRY [cluster_nodes], NODE_SIZE, 1, 9f
	mov	[eax + edx + node_addr], ebx
	lea	ebx, [eax + edx]
	mov	eax, [clock]
	mov	[ebx + node_clock_met], eax
	mov	[ebx + node_clock], eax
	mov	eax, [packet_hello_nr$]
	mov	[ebx + node_handshake], eax

	printc 13, " add cluster node "
	mov	eax, [ebx + node_addr]
	call	print_ip$
	mov	edx, [ebx + node_handshake]
	call	printspace
	call	printhex8
	call	newline
		pushad; xor esi, esi;call cmd_cloud; popad
	call	newline
	call	newline

	or	eax, eax	# ZF = 0
9:	pop_	edx ecx ebx eax
	ret


.data
packet_ping$:
.asciz "ping "
packet_ping_nr$:.long 0
packet_ping_end$ = .

packet_pong$:
.asciz "ping"
packet_pong_nr$:.long 0
packet_pong_end$ = .
.text32
cluster_ping:
	printlnc 11, "ping cluster"
	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, edx, 2f
	mov	eax, [ebx + edx + node_addr]
	mov	ecx, [ebx + edx + node_handshake]
	mov	[packet_hello_nr$], ecx	# send initial handshake

	pushad
	LOAD_PACKET ping
	call	cloud_packet_send
	popad

	ARRAY_ENDL
2:	ret

#############################################################################
# Cluster Event Handler

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

	# detect message
	.macro ISMSG name, label
		push_	edi esi ecx
		add	esi, 12
		LOAD_TXT "\name", edi, ecx
		repz	cmpsb
		pop_	ecx esi edi
		jz	\label
	.endm

#	ISMSG "hello", 1f
#	ISMSG "ping", 2f
#	ISMSG "pong", 3f
#	jmp	91f
	.purgem ISMSG

# hello packet
1:	cmpd	[esi + 6], -1	# destination broadcast?
	jnz	9f
	mov	dx, [esi + 12 + 6]
	mov	[packet_hello_nr$ + 2], dx 
	printc 13, " respond "
	LOAD_PACKET hello
	call	cloud_packet_send
	ret
# ping
2:	LOAD_PACKET pong

# pong
3:
9:	printlnc 13, " ignore"
	ret
91:	printlnc 13, " ignore: unknown message"
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

	cmp	ecx, 1500
	jb 1f
	printlnc 4, "packet size error";
	jmp	9f

1:
#jmp 9f
#######
	color 8
# print binary
	push	ecx
	mov	ah, 15
0:	lodsb
	mov	edi, esi
	call	printcharc
	or	al, al
	jz	1f
	loop	0b
	jmp	2f
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
1:	loop	0b
2:	mov	esi, edi
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
9:	popcolor
	pop	eax
	pop	edi
	pop	esi
	ret

###############################################################################
# command interface
SHELL_COMMAND "cloud", cmd_cloud

cmd_cloud:
	or	esi, esi
	jz	2f
	lodsd
	lodsd

	or	eax, eax
	jnz	1f
2:	printc 11, "CloudNet status: "
	mov	ax, [cloud_flags]
	PRINTFLAG ax, STOP$, "passive", "active"
	call	newline

	mov	ebx, [cluster_nodes]
	or	ebx, ebx
	jz	2f
	print "local cluster: "
	mov	edx, [ebx + array_index]
	shr	edx, 2
	call	printdec32
	call	newline


	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, ecx
	print "  "
	mov	eax, [ebx + ecx + node_addr]
	call	print_ip$
	call	printspace
	mov	edx, [ebx + ecx + node_handshake]
	call	printhex8
		
	printc 15, " met: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock_met]
	call	_print_time$
	print " ago"


	printc 15, " seen: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock]
	call	_print_time$
	print " ago"

	call	newline
	ARRAY_ENDL
2:
	ret

_print_time$:
	mov	edi, edx
	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]
	shrd	eax, edx, 8
	shr	edx, 8
	imul	edi
	call	print_time_ms_40_24
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
