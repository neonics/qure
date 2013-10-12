###############################################################################
# CloudNet - Clustered Distributed Network
.intel_syntax noprefix
.text32

#############################
.global cmd_cloudnetd
.global cmd_cloud

CLOUD_PACKET_DEBUG = 0

CLOUD_LOCAL_ECHO = 1

CLOUD_MCAST = 1	# 0: BCAST
CLOUD_MCAST_IP = 224|123<<24	# 224.0.0.123  (unassigned: .115-.250)

NET_AUTOMOUNT = 1

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
cluster_ip:	.long 0
lan_ip:		.long 0
cloud_sock:	.long 0
cloud_arp_sock:	.long 0
cloud_flags:	.long 0
	STOP$	= 1
cluster_node:	.long 0
.text32

cloudnet_daemon:
	orb	[cloud_flags], STOP$
	mov	eax, 100
	call	sleep	# nicer printing
	call	cloud_init_ip
	jc	9f
	mov	[lan_ip], eax
	mov	[cluster_ip], eax

	call	cloud_mcast_init

	call	cloud_socket_open
	jc	9f
	call	cloud_rx_start
	jc	9f
	call	cloud_arpwatch_start
	jc	9f

	mov	eax, offset class_cluster_node
	call	class_newinstance
	jc	1f
	#call	[eax + init]
	call	cluster_node_factory
	jc	2f
	mov	[cluster_node], eax

# in: eax = ip
# in: edx = cluster state (hello_nr; [word cluster era<<16][word node_age]
# in: esi, ecx = packet
# out: ZF = 0: added, ZF = 1: updated
lea	esi, [eax + cluster_node_persistent]	# also payload start
mov	eax, [lan_ip]
mov	edi, [cloud_nic]
lea	edi, [edi + nic_mac]
call	cluster_add_node	# register self


	jmp	2f
1:	printc 4, "cloudnet_daemon: cluster_node error"
2:
	call	cloud_register

0:	mov	eax, 1000 * 60 * 5
	call	sleep
	testd	[cloud_flags], STOP$
	jnz	0b

	call	cluster_ping

 	jmp	0b

9:	ret


# out: eax = ip
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
	mov	eax, edx
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

.macro IP_LONG reg, a,b,c,d
	mov	\reg, \a|(\b<<8)|(\c<<16)|(\d<<24)
.endm

cloud_mcast_init:
	printc 13, " multicast initialisation "

	IP_LONG	eax, 224,0,0,1
	mov	dl, IGMP_TYPE_QUERY
	call	net_igmp_send
	jc	9f

	mov	eax, CLOUD_MCAST_IP
	call	net_igmp_join

	OK
	ret


# out: eax
cloud_socket_open:

	mov	eax, [clock]
	mov	[tx_clock$], eax

	xor	eax, eax	# IPV4
	mov	edx, IP_PROTOCOL_UDP << 16 | 999
	mov	ebx, SOCK_READPEER|SOCK_READPEER_MAC
	KAPI_CALL socket_open
	jc	9f
	mov	[cloud_sock], eax

	printc 11, "CloudNet listening on "
	KAPI_CALL socket_print
	call	newline

	# add arp watcher
	mov	ebx, SOCK_AF_ETH	# flags
	mov	edx, ETH_PROTO_ARP << 16
	KAPI_CALL socket_open
	jc	9f
	mov	[cloud_arp_sock], eax

	clc
9:	ret


cloud_register:
	printc 13, " register "
	mov	eax, [cluster_node]
	or	eax, eax
	jz	9f
.if CLOUD_MCAST
	mov	edx, CLOUD_MCAST_IP
.else
	mov	edx, -1	# BCAST
.endif
	call	[eax + send]
	ret

9:	printlnc 4, "cloud_register: no cluster_node"
	ret

.struct 0
pkt_cluster_era:	.long 0
pkt_node_age:		.long 0
pkt_kernel_revision:	.long 0
pkt_node_birthdate:	.long 0
pkt_cluster_birthdate:	.long 0	# birthdate of first cluster node
pkt_node_hostname:	.space 16
PKT_STRUCT_SIZE = .

.text32

.macro LOAD_PACKET p
	mov	esi, offset packet_\p\()$
	mov	ecx, offset packet_\p\()_end$ - packet_\p\()$;
.endm

# in: eax = dest
cloud_send_hello:
	DEBUG "cloud_send_hello"
	mov	esi, [cluster_node]
	or	esi, esi
	jz	9f
	#add esi, offset netobj_packet
	mov	ecx, offset cluster_node_packet_end
	call	cloud_packet_send
	ret
9:	printlnc 4, "cloud_send_hello: no cluster node - not sending"
	ret

# in: eax = ip
# in: esi = payload start
# in: ecx = payload len
cluster_packet_send:
cloud_packet_send:
	call	cloud_tx_throttle
	jc	9f	# skip tx

	.if CLOUD_LOCAL_ECHO
		printc 9, "[cloud-tx] "
		call	print_ip$
		call	printspace
		call	cloudnet_packet_print
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

	div	ecx	# silence : 0 / count
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
0:	mov	ecx, -1	# infinite wait
	KAPI_CALL socket_read
	jc	0b

	# handle packet

	push	eax	# preserve server socket
	call	cloudnet_handle_packet
	pop	eax

	jmp	0b


# start arpwatch listener thread/task
cloud_arpwatch_start:
	printc 13, " start arpwatch "
	PUSH_TXT "cloudnet-arp"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset cloudnet_arpwatch
	mov	eax, [cloud_arp_sock]
	KAPI_CALL schedule_task
	jc	9f
	OK
	clc
	ret
9:	printlnc 4, "fail"
	stc
	ret

cloudnet_arpwatch:
0:	mov	ecx, -1	# infinite wait
	KAPI_CALL socket_read
	jc	0b

	# handle packet

	push	eax

	# filter
	cmp	word ptr [esi + arp_hw_type], ARP_HW_ETHERNET
	jnz	9f
	cmp	dword ptr [esi + arp_proto], 0x04060008 # protosz 4,hw6,ipv4
	jnz	9f

	mov	dx, [esi + arp_opcode]
	mov	al, '?'
	cmp	dx, ARP_OPCODE_REQUEST
	jz	1f
	mov	al, '!'
	cmp	dx, ARP_OPCODE_REPLY
	jnz	9f

1:	printc 12, " rx ARP "
	call	printchar
	call	printspace
	mov	eax, [esi + arp_dst_ip]
	call	net_print_ipv4
	print " -> "
	mov	eax, [esi + arp_src_ip]
	call	net_print_ipv4
	call	newline

9:	pop	eax
	jmp	0b


################################################
# Cluster Management
.struct 0
node_addr:	.long 0
# pkt_*
node_cluster_data:
node_cluster_era:	.long 0
node_node_age:		.long 0
node_kernel_revision:	.long 0
node_node_birthdate:	.long 0
node_cluster_birthdate:	.long 0	# birthdate of first cluster node
node_node_hostname:	.space 16

# local
node_mac:	.space 6

node_clock_met:	.long 0
node_clock:	.long 0
#node_cycles:	.long 0	# node age?
NODE_SIZE = .
.data
cluster_ips:	.long 0	# ptr_array for scasd
cluster_nodes:	.long 0	# array of node struct
.text32

# in: eax = IP
# in: edi = MAC
# in: esi = ptr pkt_*
cluster_add_node:
	push_	eax ebx ecx edx
	mov	ecx, eax

	.if 1
	ARRAY_LOOP [cluster_nodes], NODE_SIZE, eax, edx, 1f
	cmp	ecx, [eax + edx + node_addr]
	lea	ebx, [eax + edx]
	jz	2f
	ARRAY_ENDL
	jmp	1f
2:	printlnc 13, " update node"
	jmp	2f

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

1:	PTR_ARRAY_NEWENTRY [cluster_ips], 1, 9f	# out: eax+edx; destroys: ecx
	mov	[eax + edx], ecx
	mov	ebx, ecx # ecx destroyed next line:
	ARRAY_NEWENTRY [cluster_nodes], NODE_SIZE, 1, 9f
	mov	ecx, ebx
	lea	ebx, [eax + edx]
	mov	[ebx + node_addr], ecx
	mov	eax, [edi + 0]	# read mac
	mov	[ebx + node_mac], eax
	mov	ax, [edi + 4]	# read mac
	mov	[ebx + node_mac + 4], ax
	mov	eax, [clock]
	mov	[ebx + node_clock_met], eax

	printc 13, " add cluster node "
	push	esi
	lea	esi, [esi + pkt_node_hostname]
	call	print
	call	printspace
	pop	esi
	mov	eax, ecx
	call	print_ip$
	print " era "
	mov	edx, [esi + pkt_cluster_era]
	call	printdec32
	print " age "
	mov	edx, [esi + pkt_node_age]
	call	printdec32
	print " krev "
	mov	edx, [esi + pkt_kernel_revision]
	call	printdec32
	call	newline
	print "                  n "
	mov	edx, [esi + pkt_node_birthdate]
	call	print_datetime
	print " c "
	mov	edx, [esi + pkt_cluster_birthdate]
	call	print_datetime
	call	newline

2:	mov	eax, [clock]
	mov	[ebx + node_clock], eax

	push_ esi edi
	lea	edi, [ebx + node_cluster_data]
	mov	ecx, PKT_STRUCT_SIZE / 4
	rep	movsd
	pop_ edi esi

	clc

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
	pushad
	LOAD_PACKET ping
	call	cloud_packet_send
	popad
	ARRAY_ENDL
2:	ret

#############################################################################
# Cluster Event Handler

CLUSTER_DEBUG = 1

CL_PAYLOAD_START = 18	# sock readpeer: src.ip,src.port,dst.ip,dst.port,src.mac

# in: esi,ecx = packet
cloudnet_handle_packet:
	printc 11, " rx "

.if 1	# SOCK_READPEER (getsockflag;jz/jc?)
	# readpeer:
	mov	eax, [esi]		# peer ip
	mov	dx, word ptr [esi + 4]	# peer port
	xchg	dl, dh
	call	print_addr$

	add	esi, 12	# mac
	pushcolor 8
	call	printspace
	call	net_print_mac
	popcolor
	sub	esi, 12

	print "->"

	mov	eax, [esi+ 6]		# peer ip
	mov	dx, word ptr [esi + 10]	# peer port
	xchg	dl, dh
	call	print_addr$
	call	newline
	print "    "
.endif
	push	esi
	lea	edi, [esi + 12]	# mac
	add	esi, CL_PAYLOAD_START
	sub	ecx, CL_PAYLOAD_START
	call	cloudnet_packet_print
	add	ecx, CL_PAYLOAD_START
	pop	esi

	mov	eax, [esi]	# peer ip
	push	esi
	lea	edi, [esi + 12]	# mac
	lea	esi, [esi + CL_PAYLOAD_START + 6] # 6: "hello\0"
	call	cluster_add_node
	pop	esi

	# detect message
	.macro ISMSG name, label
		push_	edi esi ecx
		add	esi, CL_PAYLOAD_START
		LOAD_TXT "\name", edi, ecx
		repz	cmpsb
		pop_	ecx esi edi
		jz	\label
	.endm

	cmpd	[esi + CL_PAYLOAD_START + 0], 'h'|'e'<<8|'l'<<16|'l'<<24
	jnz	91f
	cmpw	[esi + CL_PAYLOAD_START + 4], 'o'
	jnz	91f

#	ISMSG "hello", 1f
#	ISMSG "ping", 2f
#	ISMSG "pong", 3f
#	jmp	91f
	.purgem ISMSG

# hello packet
1:
	mov	eax, [cluster_node]

	# adopt cluster information
	.if CLUSTER_DEBUG
		printc 13, " analyzing: "
	.endif
	mov	edx, [esi + CL_PAYLOAD_START + 6 + pkt_cluster_era]
	cmp	edx, [eax + cluster_era]
	jz	1f	# same era
	jb	51f	# remote node out of date: respond
		# sanity check
		push	edx
		sub	edx, [eax + cluster_era]
		cmp	edx, 100
		pop	edx
		jae	53f
	# local node out of date.
	.if CLUSTER_DEBUG
		printc 14, "adopt new cluster era: "
		pushd	[eax + cluster_era]
		call	_s_printdec32
		printc 13, "->"
		call	printdec32
		call	newline
	.endif
	mov	[eax + cluster_era], edx
	mov	edx, [esi + CL_PAYLOAD_START + 6 + pkt_cluster_birthdate]
	mov	[eax + cluster_birthdate], eax
	mov	edx, [eax + node_age]
	mov	[eax + cluster_era_start], edx	# 'our' age when we saw this era
	jmp	3f	# persist

1:	# same era: check date
	.if CLUSTER_DEBUG
		printlnc 10, "no; same era"
	.endif
	mov	edx, [esi + CL_PAYLOAD_START + 6 + pkt_cluster_birthdate]
	or	edx, edx
	jz	52f		# remote no date: out of date, respond?
	cmpd	[eax + cluster_birthdate], 0	# do we have a date?
	jz	1f	# we dont have date; remote has one, take it
	cmp	edx, [eax + cluster_birthdate]
	jz	4f	# remote same date - ok
	ja	52f	# remote has newer date: out of date. respond?
	# jb: remote has older birthdate, update local.
1:	mov	[eax + cluster_birthdate], edx	# record cluster birthdate
	printc 14, " adopt cluster birthdate "
	call	print_datetime
	printc 14, " for era "
	mov	edx, [eax + cluster_era]
	call	printdec32
	call	newline

3:	# persist
	call	[eax + oofs_persistent_api_save]
	# update array
	lea	esi, [eax + cluster_node_persistent]
	mov	eax, [lan_ip]
	mov	edi, [cloud_nic]
	lea	edi, [edi + nic_mac]
	call	cluster_add_node	# update display list
	mov	eax, [cluster_node]
	jmp	4f
####################
51:
	.if CLUSTER_DEBUG
		printc 12, "no; remote era out of date "
		DEBUG_DWORD edx,"r era"
		DEBUG_DWORD [eax+cluster_era],"l.era"
		call	newline
	.endif
	jmp 4f
52:
	.if CLUSTER_DEBUG
		printc 12, "no; remote cluster date too old "
		printc 8, "(time remote: "
		call	print_datetime
		printc 8, " local: "
		mov	edx,[eax+cluster_birthdate]
		call	print_datetime
		printlnc 8, ")"
	.endif
	jmp	4f
53:	printc 12, "cluster age difference too high, ignoring"
	jmp	4f

5:	.if CLUSTER_DEBUG
		DEBUG "remote out of date"
	.endif
####################
4:	# respond?
	cmpd	[esi + 6], -1	# destination broadcast?
	jnz	9f
5:	printc 13, " respond "
	mov	edx, [esi]	# src ip
	call	[eax + send]
	ret
# pong
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
	push_	esi edi edx ecx eax
	pushcolor 8
	mov	edx, ecx
	call	printdec32
	call	printspace

	cmp	ecx, 1500 # - UDP_HEADER_SIZE - ETH_HEADER_SIZE
	jb 1f
	printlnc 4, "packet size error";
	jmp	9f
1:
	color 8
	mov	ah, 15
0:	lodsb
	mov	edi, esi
	call	printcharc
	or	al, al
	jz	1f
	loop	0b
	jmp	2f
0:	lodsb
.if CLOUD_PACKET_DEBUG
	mov	dl, al
	call	printhex2
	call	printspace
.endif
1:	loop	0b
2:	mov	esi, edi

	color 15
	mov	edx, [esi]
	call	printdec32
	call	printspace
	mov	edx, [esi+4]
	call	printdec32
	call	printspace
	color 8
	call	printhex8
	call	newline
#######
9:	popcolor
	pop_	eax ecx edx edi esi
	ret

###############################################################################
# command interface
SHELL_COMMAND "cloud", cmd_cloud

cmd_cloud:
	or	esi, esi
	jz	cmd_cloud_print$
	lodsd
	lodsd

	or	eax, eax
	jz	cmd_cloud_print$

1:	CMD_ISARG "start"
	jnz	1f
	andd	[cloud_flags], ~STOP$
	ret

1:	CMD_ISARG "stop"
	jnz	1f
	ord	[cloud_flags], STOP$
	ret

1:	CMD_ISARG "register"
	jz	cloud_register

1:	CMD_ISARG "init"
	jnz	1f
	mov	eax, [cluster_node]
	or	eax, eax
	jnz	2f
	call	cluster_node_factory
	jc	9f
	mov	[cluster_node], eax
9:	ret
2:	call	[eax + oofs_persistent_api_load]
	ret

1:	printlnc 4, "usage: cloud <command> [args]"
	printlnc 4, " commands: init start stop"
	ret


cmd_cloud_print$:
	printc 11, "CloudNet status: "
	mov	ax, [cloud_flags]
	PRINTFLAG ax, STOP$, "passive", "active"
	mov	eax, [lan_ip]
	call	printspace
	call	net_print_ipv4
	call	newline

	mov	eax, [cluster_node]
	or	eax, eax
	jz	2f

	printc 15, "Kernel Revision: "
	sub	esp, 128
	mov	edi, esp
	mov	ecx, 128
	call	cluster_get_kernel_revision
	mov	esi, esp
	call	println
	add	esp, 128

	call	[eax + oofs_api_print]
2:

	mov	ebx, [cluster_nodes]
	or	ebx, ebx
	jz	2f
	print "local cluster: "
	mov	eax, [ebx + array_index]
	xor	edx, edx
	mov	ecx, NODE_SIZE
	div	ecx
	mov	edx, eax
	call	printdec32
	call	newline

	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, ecx
	mov	eax, [cloud_nic]
	mov	eax, [eax + nic_ip]
	cmp	eax, [ebx + ecx + node_addr]
	mov	ax, 9 << 8 | '*'
	jz	1f
	xor	al, al
1:	call	printcharc
	call	printspace

	lea	eax, [ebx + ecx + node_node_hostname]
	push	eax
	pushstring "%8s"
	call	printf

	add	esp, 8
	call	printspace
	mov	eax, [ebx + ecx + node_addr]
	call	print_ip$
	call	printspace
	pushcolor 8
	lea	esi, [ebx + ecx + node_mac]
	call	net_print_mac
	popcolor

	pushd	[ebx + ecx + node_kernel_revision]
	mov	edx, [ebx + ecx + node_node_age]
	push	edx
	mov	edx, [ebx + ecx + node_cluster_era]
	push	edx
	pushstring " c.era %3d n.age %3d krnlrev %3d"
	call	printf
	add	esp, 4*4

	call	newline
	printc 15, "   (met: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock_met]
	call	_print_time$
	print " ago"

	printc 15, " seen: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock]
	call	_print_time$
	println " ago)"

	######################################################

	printc 15, "   N birth "
	mov	edx, [ebx + ecx + node_node_birthdate]
	call	print_datetime

		push	esi
		.if 1
			call	get_datetime_s
			mov	esi, edx
			mov	eax, edx
		.else
			mov	edx, [clock_ms_fp]
			mov	eax, [clock_ms_fp+4]
			shrd	eax, edx, 24
			shr	edx, 24

			mov	esi, 1000
			idiv	esi
			# (edx:)eax = seconds since boot;
			# drop edx (since datetime can't hold it)

			mov	edx, [kernel_boot_time]
			call	datetime_to_s
			add	eax, edx
			# eax = now, in seconds since epoch
			mov	esi, eax
		.endif

		mov	edx, [ebx + ecx + node_node_birthdate]
		call	datetime_to_s

		sub	eax, edx
		# eax = now - node birthdate

			DEBUG "uptime"
			mov edx, eax
			call printdec32
			DEBUG "s"
		xor	edx, edx

	printc 15, " uptime "
	call	print_time_s

	call	newline

	######################################################

	printc 15, "   C birth "
	mov	edx, [ebx + ecx + node_cluster_birthdate]
	call	print_datetime

		call	datetime_to_s
		mov	eax, esi
		pop	esi
		sub	eax, edx
			DEBUG "uptime"
			mov edx, eax
			call printdec32
			DEBUG "s"
		xor	edx, edx

	printc 15, " uptime "
		call	print_time_s

	call	newline
	call	newline

	ARRAY_ENDL
2:	ret

_print_time$:
	mov	edi, edx
	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]
	shrd	eax, edx, 8
	shr	edx, 8
	imul	edi
	call	print_time_ms_40_24
	ret



###############################################################################
# NETOBJ & persistence: OOFS extension
#
OO_DEBUG = 0

.include "fs/oofs/export.h"

# base class network object
DECLARE_CLASS_BEGIN netobj, oofs_persistent#, offs=oofs_persistent
netobj_packet:
	# can't declare class data here: struct!
	#.ascii "NOBJ"
DECLARE_CLASS_METHOD init, 0
DECLARE_CLASS_METHOD send, netobj_send
DECLARE_CLASS_END netobj
.text32
# in: ecx = offset of end of packet, payload size
# in: edx = dest IP
netobj_send:
	push_	eax ebx esi
	lea	esi, [eax + netobj_packet]
	mov	eax, edx
	call	cluster_packet_send
	pop_	esi ebx eax
	ret
###################################
DECLARE_CLASS_BEGIN cluster_node, netobj
cluster_node_pkt:	.space 6	# .asciz "hello"
cluster_node_persistent:
	# NOTE: for now, keep semantically the same as pkt_*
	cluster_era:	.long 0 # cluster incarnations
	node_age:	.long 0
	kernel_revision:.long 0	# detect commit
	node_birthdate:	.long 0	# detect boot frequency
	cluster_birthdate:.long 0 # cmos time
	node_hostname:	.space 16
cluster_node_packet_end:
	# not on network
	cluster_era_start:.long 0 # age when era incremented

.org cluster_node_persistent + 512

cluster_node_volatile:
	net_fs:		.long 0	# fs_oofs object (direct access), mounted on /net/
	net_persistence:.long 0	# oofs object - root

DECLARE_CLASS_METHOD send, cluster_node_send, OVERRIDE

DECLARE_CLASS_METHOD oofs_api_init, cluster_node_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, cluster_node_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, cluster_node_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, cluster_node_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, cluster_node_onload, OVERRIDE

DECLARE_CLASS_END cluster_node
.text32

# preload
cluster_node_init:
	call	oofs_persistent_init	# super.init()

	.if OO_DEBUG
		DEBUG_CLASS
		printlnc 14, ".cluster_node_init"
	.endif

	mov	[eax + cluster_node_pkt], dword ptr 'h'|'e'<<8|'l'<<16|'l'<<24
	mov	[eax + cluster_node_pkt+4], word ptr 'o'
	clc
	ret

# in: eax
# out: eax
cluster_node_load:
	push_	ebx ecx edi edx esi
	.if OO_DEBUG
		DEBUG_CLASS
		printlnc 14, ".cluster_node_load"
	.endif
	lea	edi, [eax + cluster_node_persistent]
	mov	edx, offset cluster_node_persistent
	mov	ecx, 512

	call	[eax + oofs_persistent_api_read]
	jc	9f
	call	[eax + oofs_persistent_api_onload]

0:	pop_	esi edx edi ecx ebx
	STACKTRACE 0
	ret
9:	printc 4, "cluster_node_load: read error"
	stc
	jmp	0b


cluster_node_onload:
	mov	[cluster_node], eax	# update singleton/static access

	# TEMPORARY reset:
	#mov	dword ptr [eax + cluster_era], 0
	#mov	dword ptr [eax + cluster_era_start], 0

	mov	edx, KERNEL_REVISION
	mov	[eax + kernel_revision], edx
	mov	edx, [kernel_boot_time]
	mov	[eax + node_birthdate], edx

	push_	esi edi
	lea	edi, [eax + node_hostname]
	mov	esi, offset hostname
	movsd
	movsd
	movsd
	movsd
	pop_	edi esi

	## SEED
	#mov	edx, [eax + node_birthdate]
	#mov	[eax + cluster_birthdate], edx

	.if OO_DEBUG
	call	[eax + oofs_api_print]
	.endif

#	mov	edx, [eax + cluster_era]
#	cmp	edx, KERNEL_REVISION
#	jz	1f
#	mov	[eax + cluster_era], dword ptr KERNEL_REVISION
#	.if 1
#	mov	edx, [eax + node_age]
#	mov	[eax + cluster_era_start], edx
#	.else
#	mov	[eax + node_age], dword ptr 0
#	.endif
1:	clc
	ret



cluster_node_print:
	call	oofs_print	# super.super.super.print();
	printc 11, "cluster_node: "

	pushd	[eax + node_age]
	pushd	[eax + cluster_era]
	pushd	[eax + kernel_revision]
	push	edx
	lea	edx, [eax + node_hostname]
	xchg	edx, [esp]
	pushstring "%s krev %d era %3d age %3d\n  n.date ";
	call	printf
	add	esp, 5<<2

	push	edx
	mov	edx, [eax + node_birthdate]
	call	print_datetime
	print " c.date "
	mov	edx, [eax + cluster_birthdate]
	call	print_datetime
	pop	edx
	call	newline
	ret

cluster_node_save:
	.if OO_DEBUG
		DEBUG_CLASS
		printlnc 14, ".cluster_node_save"
	.endif
	push_	ecx esi edx ebx eax
	mov	ecx, 512
	lea	esi, [eax + cluster_node_persistent]
	mov	edx, offset cluster_node_persistent
	call	[eax + oofs_persistent_api_write]
	.if OO_DEBUG
	pushf
	call	[eax + oofs_api_print]
	popf
	.endif
	pop_	eax ebx edx esi ecx
	STACKTRACE 0
	ret

# in: eax = cluster_node instance: XXX shouldn't be necessary! TODO mfree
# out: eax = cluster_node_instance (as loaded from disk)
cluster_node_factory:
	push_	esi edx ecx ebx eax
	LOAD_TXT "/net"
	call	mtab_get_fs	# out: edx = fs instance
.if NET_AUTOMOUNT
	jnc	1f

	pushad
	mov	ebp, esp
	printc 13, " auto-mounting /net: "
	pushd	0
	pushstring "/net"
	pushstring "hda0"
	pushstring "mount"
	mov	esi, esp
	KAPI_CALL fs_mount
	mov	esp, ebp
	popad
	jc	9f
	call	mtab_get_fs
.endif
	jc	9f
1:

	printc 13, " open "
	call	print
	print ", class="
	PRINT_CLASS edx
	call	newline

	mov	esi, eax	# backup cluster_node instance (XXX)

	mov	eax, edx
	mov	edx, offset class_fs_oofs
	call	class_instanceof
	jnz	91f
	mov	[esi + net_fs], eax	# fs_oofs

	mov	eax, [eax + oofs_root]
	mov	edx, offset class_oofs_vol
	call	class_instanceof
	jnz	91f
	mov	[esi + net_persistence], eax

#	mov	edx, eax	# oofs subclass (oofs_vol)
#	mov	eax, esi	# cluster_node
#	call	[eax + persistence_init]	# super constructor
#	mov	[eax + persistence], edx
#	mov	eax, edx	# eax = oofs_vol

	mov	edx, offset class_oofs_table
	xor	ebx, ebx	# iteration arg
	call	[eax + oofs_vol_api_lookup]	# out: eax
	jc	92f

##################################################################
1:	printc 10, " * got table: "
	PRINT_CLASS
	call	newline

.data SECTION_DATA_BSS
table:.long 0
.text32
	mov	[table], eax

	# find cluster node
	mov	edx, offset class_cluster_node
	xor	ebx, ebx

	printc 13, " lookup cluster_node"

	call	[eax + oofs_table_api_lookup]	# out: ecx=index
	jnc	1f
	printc 4, " not found"

	# edx=class_cluster_node
	mov	eax, [table]
	mov	ecx, 512
	call	[eax + oofs_table_api_add]	# edx=class -> eax=instance
	jc	93f
	printc 9, " - added cluster_node to oofs"
	jmp	2f

##################################################################
# in: ecx = oofs_vol entry number
1:	call	newline
	mov	eax, [esp]	# oofs_vol
	mov	eax, [eax + net_persistence]	# 'root': oofs
	#printc 9, "cluster_node: oofs.load_entry "
	#xchg ecx,edx;call printdec32;xchg edx,ecx
	call	[eax + oofs_vol_api_load_entry]	# in: ecx = index; out: eax
	jc	94f

##################################################################
2:	printc 10, " * got cluster node: "
	incd	[eax + node_age]

# TEMP FIX
#mov [eax+cluster_era], dword ptr 0
#mov [eax + cluster_birthdate], dword ptr 0x365b77dc

	pushd	[eax + node_age]
	pushd	[eax + cluster_era]
	pushstring "cluster era: %d  node age: %d\n"
	call	printf
	add	esp, 12
	mov	[esp], eax

	call	[eax + oofs_persistent_api_save]

	clc
0:	pop_	eax ebx ecx edx esi
	ret

9:	printlnc 4, "cluster_node_init: /net/ not mounted"
	stc
	jmp	0b
91:	printlnc 4, "cluster_node_init: /net/ not fs_oofs.oofs"
	stc
	jmp	0b
92:	printlnc 4, "cluster_node_init: oofs: no table"
	stc
	jmp	0b
93:	printlnc 4, "cluster_node_init: error adding"
	stc
	jmp	0b
94:	printlnc 4, "cluster_node_init: error loading"
	stc
	jmp	0b

# in: edx = dest IP
cluster_node_send:
	push	ecx
	mov	ecx, offset cluster_node_packet_end
	call	netobj_send # explicit super ref
	pop	ecx
	ret


##############################################################
# httpd interface

# in: edi, ecx
# out: ecx
cluster_get_kernel_revision:
	push_	eax esi edx ebx edi
	LOAD_TXT "dev:", esi, ecx
	rep	movsb
	dec	edi
	LOAD_KERNEL_VERSION_TXT esi, ecx
	# lets assume it fits for clarity
	rep	movsb
	dec	edi

	mov	ebx, [cluster_node]
	or	ebx, ebx
	jz	9f	# no node.

	mov	al, '.'
	stosb
	mov	edx, [ebx + cluster_era]
	call	sprintdec32
	stosb
	mov	edx, [ebx + node_age]
	sub	edx, [ebx + cluster_era_start]
	call	sprintdec32
	mov	al, '/'
	stosb
	mov	edx, [ebx + node_age]
	call	sprintdec32
9:	mov	ecx, edi
	sub	ecx, [esp]
	pop_	edi ebx edx esi eax
	ret

# called from httpd:
# in: [ebp] = socket (write content directly)
#[in: edi, ecx = buffer]
#[out: ecx = len]
cluster_get_status:
	push	edx
	mov	edx, 1
	call	cluster_get_status_
	pop	edx
	ret
cluster_get_status_list:
	push	edx
	mov	edx, 3
	call	cluster_get_status_
	pop	edx
	ret
# Produces html
# in: edx = flags
# in: [ebp] = socket (writes directly)
# in: edi, ecx = buffer
#[out: ecx = len]
cluster_get_status_:

	.macro APPEND_STRING str, nofit=91f
		push	esi
		push	ecx
		mov	edx, [ebp + 4]	# bufsize
		add	edx, edi	# add offs
		sub	edx, [ebp + 4]	# correct buf start

		LOAD_TXT "\str", esi, ecx, 1
		sub	edx, ecx
		jle	\nofit
		rep	movsb
		pop	ecx
		pop	esi
	.endm


	push_	edx ebx esi edi ecx ebp
	lea	ebp, [esp + 4]
	# [[ebp-4]] = socket
	# [ebp+0] = buffer size
	# [ebp+4] = buffer

	APPEND_STRING "<b>Host:</b> "
	mov	esi, offset hostname
	call	strlen_
	rep	movsb

	APPEND_STRING " <b>nodes:</b> "

	xor	edx, edx
	mov	ebx, [cluster_nodes]
	or	ebx, ebx
	jz	1f	# shouldn't happen

	mov	eax, [ebx + array_index]
	xor	edx, edx
	mov	esi, NODE_SIZE
	div	esi
	mov	edx, eax

1:	call	sprintdec32
	or	ebx, ebx
	jz	9f	# shouldn't happen

	mov	eax, [cluster_node]
	or	eax, eax
	jz	1f

	APPEND_STRING " <b>era:</b> "
	mov	edx, [eax + cluster_era]
	call	sprintdec32

	APPEND_STRING " <b>uptime:</b> "
	mov	edx, [eax + cluster_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

1:	testb	[ebp + 16], 1
	jz	9f

	mov	word ptr [edi], ' '

	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|('u'<<8)|('l'<<16)|('>'<<24)
	stosd
	jmp	2f
1:	APPEND_STRING "\n<table>"
2:
	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, esi
	mov	ecx, edi
	add	ecx, 64	# guestimate
	sub	ecx, [ebp + 4]
	jle	9f
	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|('l'<<8)|('i'<<16)|('>'<<24)
	stosd
	jmp	2f
1:	APPEND_STRING "\n\t<tr><td>"
2:
	mov	eax, [cloud_nic]
	mov	eax, [eax + nic_ip]
	cmp	eax, [ebx + esi + node_addr]
	mov	ah, 0
	jnz	1f
	mov	eax, '<'|('i'<<8)|('>'<<16)
	stosd
	dec	edi
	mov	ah, 1
	1:
	mov	edx, [ebx + esi + node_cluster_era]
	call	sprintdec32
	mov	al, '#'
	stosb
	mov	edx, [ebx + esi + node_node_age]
	call	sprintdec32
	cmp	ah, 1
	jnz	1f
	mov	eax, '<'|('/'<<8)|('i'<<16)|'>'<<24
	stosd
	1:

	push	esi
	mov	al, ' '
	stosb
	lea	esi, [ebx + esi + node_node_hostname]
	call	strlen_
	rep	movsb
	stosb
	pop	esi

	testb	[ebp + 16], 2
	jnz	1f
	sprintchar '('
	mov	edx, [ebx + esi + node_node_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s
	sprintchar ')'

	mov	eax, '<'|'/'<<8|'l'<<16|'i'<<24
	stosd
	mov	al, '>'
	stosb
	jmp	0f

1:	APPEND_STRING "</td><td>"
	movzx	edx, word ptr [ebx + esi + node_kernel_revision]
	call	sprintdec32

	APPEND_STRING "</td><td>birthdate "
	mov	edx, [ebx + esi + node_node_birthdate]
	call	sprint_datetime

	APPEND_STRING "</td><td>uptime "
	mov	edx, [ebx + esi + node_node_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

	APPEND_STRING "</td><td>cluster since "
	mov	edx, [ebx + esi + node_cluster_birthdate]
	call	sprint_datetime

	APPEND_STRING "</td><td>uptime "
	mov	edx, [ebx + esi + node_cluster_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

	APPEND_STRING "</td></tr>\n"

0:
	# write socket
	push	esi
	mov	ecx, edi
	mov	esi, [ebp + 4]	# buffer start
	sub	ecx, esi
	mov	eax, [ebp - 4]	# socket ptr
	mov	eax, [eax]	# socket
	KAPI_CALL socket_write
	pop	esi
	# reset buffer
	mov	edi, [ebp + 4]
	mov	ecx, [ebp + 0]

	ARRAY_ENDL

	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|('/'<<8)|('u'<<16)|('l'<<24)
	stosd
	mov	al, '>'
	stosb
	jmp	9f

1:	LOAD_TXT "</table>\n", esi, ecx, 1
	rep	movsb

9:
	# write socket
	mov	ecx, edi
	mov	esi, [ebp + 4]	# buffer start
	sub	ecx, esi
	mov	eax, [ebp - 4]	# socket ptr
	mov	eax, [eax]	# socket
	KAPI_CALL socket_write
	# reset buffer
	mov	edi, [ebp + 4]
	mov	ecx, [ebp + 0]

	# update buffer pointers - not needed due to socket write..
	mov	ecx, edi
	sub	ecx, [ebp + 4]
	mov	[ebp], ecx
	pop_	ebp ecx edi esi ebx edx
	ret
91:	# doesn't fit (but should); for now, no flush
	DEBUG "<NOFIT>"
	pop	esi
	jmp	0b
