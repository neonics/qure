###############################################################################
# CloudNet - Clustered Distributed Network
.intel_syntax noprefix
.text32

#############################
.global cmd_cloudnetd
.global cmd_cloud

CLOUD_PACKET_DEBUG = 0
# Also see CLUSTER_DEBUG (way) further down

CLOUD_LOCAL_ECHO = 1

CLOUD_ARPWATCH = 0

CLOUD_MCAST = 1	# 0: BCAST
CLOUD_MCAST_IP = 224|123<<24	# 224.0.0.123  (unassigned: .115-.250)

NET_AUTOMOUNT = 1

CLOUD_VERBOSITY_TX		= 2	# prints sending packets
CLOUD_VERBOSITY_RX		= 2	# prints receiving packets
CLOUD_VERBOSITY_INIT_NODE	= 2	# local cluster_node initialisation
CLOUD_VERBOSITY_ACTION_ADD	= 1	# node discovery
CLOUD_VERBOSITY_ACTION_ADD_DETAILS= CLOUD_VERBOSITY_ACTION_ADD + 1
CLOUD_VERBOSITY_ACTION_UPDATE	= 2	# node update
CLOUD_VERBOSITY_ACTION_REGISTER	= 2	# send registration packet
CLOUD_VERBOSITY_ACTION_RESPOND	= 3	# send response packet
CLOUD_VERBOSITY_ACTION_IGNORE	= 3	# rx packet results in no action
CLOUD_VERBOSITY_ACTION_DMZ_IP	= 1	# taking on DMZ IP
CLOUD_VERBOSITY_PING		= 2	# prints ping action
CLOUD_VERBOSITY_PING_RESULT	= 1	# prints online nodes
CLOUD_VERBOSITY_PING_NODELIST	= 3	# prints times for each node
CLOUD_VERBOSITY_NODE_OFFLINE	= 2	# prints name, ip, mac of offline nodes

        .macro CLOUD_VERBOSITY_BEGIN level
                cmpb    [cloud_verbosity], CLOUD_VERBOSITY_\level
                jb      9081f
        .endm

        # optional
        .macro CLOUD_VERBOSITY_ELSE
        jmp     9082f
        9081:
        .endm

        .macro CLOUD_VERBOSITY_END
        9082:
        9081:
        .endm


# start daemon
cmd_cloudnetd:
	I "Starting CloudNet Daemon"

		LOAD_TXT "cloud.verbosity"
		LOAD_TXT "1", edi	# set this to at least 2 for boot debug
		mov	eax, offset cloud_env_var_verbosity_changed
		call	shell_variable_set

		LOAD_TXT "lan.dmz_ip"
		LOAD_TXT "000.000.000.000", edi
		push	edi
		mov	eax, [lan_dmz_ip]
		call	net_sprint_ipv4
		pop	edi
		mov	eax, offset cloud_env_var_dmz_ip_changed
		call	shell_variable_set

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
.if CLOUD_ARPWATCH
cloud_arp_sock:	.long 0
.endif
cloud_flags:	.long 0
	STOP$		= 1
	MAINTAIN_DMZ$	= 2	# makes sure one local node has [lan_dmz_ip]
cluster_dmz_ip:	.long 0	# XXX only 1 DMZ (assuming one NIC)
cloud_verbosity:.byte 0
cluster_node:	.long 0
.text32


cloud_env_var_verbosity_changed:
	call	cloud_env_var_changed
	mov	eax, [eax + env_var_value]
	call	atoi
	jc	9f
	cmp	eax, 9
	ja	9f
	mov	[cloud_verbosity], al
	OK
	ret
9:	printlnc 4, " invalid value: not 0..9"
	ret

cloud_env_var_dmz_ip_changed:
	call	cloud_env_var_changed	# log; out: esi = value
	mov	eax, [eax + env_var_value]
	cmpb	[eax], 0
	jz	1f	# empty
	call	net_parse_ip	# prints error
	jc	9f
	print " set DMZ IP: "
	call	net_print_ip
	mov	[lan_dmz_ip], eax
	or	eax, eax
	jz	9f
	orb	[cloud_flags], MAINTAIN_DMZ$
	OK
	ret
9:	printlnc 12, "invalid IP"
	jmp	2f
1:	println " clear DMZ IP - not maintaining."
2:	andb	[cloud_flags], ~MAINTAIN_DMZ$
	mov	[lan_dmz_ip], dword ptr 0
	ret

# in: eax = env var struct
cloud_env_var_changed:
	printc_ 11, "cloud var changed: "
	pushd	[eax + env_var_label]
	call	_s_print
	printcharc 11, '='
	pushd	[eax + env_var_value]
	call	_s_print
	ret




cloudnet_daemon:
	#orb	[cloud_flags], STOP$
	mov	eax, 100
	call	sleep	# nicer printing
	printlnc 11, "cloud initialising"
	call	cloud_init_ip
	jc	9f

	call	cloud_mcast_init

	call	cloud_socket_open
	jc	9f
	call	cloud_rx_start
	jc	9f
	.if CLOUD_ARPWATCH
	call	cloud_arpwatch_start
	jc	9f
	.endif

	mov	eax, offset class_cluster_node
	call	class_newinstance
	jc	1f
	#call	[eax + init]
	call	cluster_node_factory
	jc	9f	# abort - exit task

	mov	[cluster_node], eax

# in: eax = ip
# in: edx = cluster state (hello_nr; [word cluster era<<16][word node_age]
# in: esi, ecx = packet
# out: ZF = 0: added, ZF = 1: updated
lea	esi, [eax + cluster_node_persistent]	# also payload start
mov	edi, [cloud_nic]
mov	eax, [edi + nic_ip]
lea	edi, [edi + nic_mac]
call	cluster_add_node	# register self
mov	[cluster_nodeidx], eax

	jmp	2f
1:	printc 4, "cloudnet_daemon: cluster_node error"
2:

	call	cloud_register

	mov	eax, 1000 * 60 + 999	# 60.999 secs
	call	_calc_time_clocks$
	mov	[ping_timeout_clocks], eax

	# delay to make sure the 1st sleep period will exceed
	# the ping timeout
	mov	eax, 1000 	# 1 sec
	call	sleep
# main loop

0:	mov	eax, 1000 * 60	# 1 min
	call	sleep
	testd	[cloud_flags], STOP$
	jnz	0b

	call	cluster_check_status	# maybe updates IP
	call	cluster_ping

 	jmp	0b

9:	ret


# out: eax = ip
cloud_init_ip:
	mov	ebx, [cloud_nic]
	or	ebx, ebx
	jnz	1f
	xor	eax, eax
	call	nic_getobject
	jc	9f
	mov	[cloud_nic], ebx
1:


	cmpd	[ebx + nic_ip], 0
	jz	nic_init_ip
	ret

.macro IP_LONG reg, a,b,c,d
	mov	\reg, \a|(\b<<8)|(\c<<16)|(\d<<24)
.endm

cloud_mcast_init:
	printc 13, " multicast initialisation "

	mov	ebx, [cloud_nic]

	IP_LONG	eax, 224,0,0,1
	mov	dx, IGMP_TYPE_QUERY | 1 << 8
	call	net_igmp_send
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

	.if CLOUD_ARPWATCH
	# add arp watcher
	mov	ebx, SOCK_AF_ETH	# flags
	mov	edx, ETH_PROTO_ARP << 16
	KAPI_CALL socket_open
	jc	9f
	mov	[cloud_arp_sock], eax
	.endif

	clc
9:	ret

# out: eax = cluster_node
# out: edx = MCAST or BCAST IP
cloud_register:

	CLOUD_VERBOSITY_BEGIN ACTION_REGISTER
		printc 13, " register "
	CLOUD_VERBOSITY_END

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
	mov	[esi + cluster_node_pkt], dword ptr 'h'|'e'<<8|'l'<<16|'l'<<24
	mov	[esi + cluster_node_pkt+4], word ptr 'o'
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
	CLOUD_VERBOSITY_BEGIN TX
		printc 9, "[cloud-tx] "
		call	print_ip$
		call	printspace
		call	cloudnet_packet_print
	CLOUD_VERBOSITY_END
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

.if CLOUD_ARPWATCH
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
.endif

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
node_clock:	.long 0	# last seen
#node_cycles:	.long 0	# node age?
NODE_SIZE = .
.data
cluster_ips:	.long 0	# ptr_array for scasd (synchronized with cluster_nodes)
cluster_nodes:	.long 0	# array of node struct (synchronized with cluster_ips)
cluster_nodeidx:.long 0 # index in cluster_nodes for local node
.text32

# in: eax = IP
# in: edi = MAC
# in: esi = ptr pkt_*
# out: eax = index/offset in cluster_nodes
cluster_add_node:
	push	ebp
	push_	eax	# STACKREF will be updated!
	mov	ebp, esp
	push_	ebx ecx edx
	mov	ecx, eax

	ARRAY_LOOP [cluster_nodes], NODE_SIZE, eax, edx, 1f
.if 0	# check IP (may change due to DHCP - not reliable)
	cmp	ecx, [eax + edx + node_addr]
.else	# check MAC
	mov	ebx, [edi]
	cmp	ebx, [eax + edx + node_mac]
	jnz	0f
	mov	bx, [edi + 4]
	cmp	bx, [eax + edx + node_mac + 4]
.endif
	lea	ebx, [eax + edx]
	jz	2f
0:	ARRAY_ENDL
	jmp	1f
2:

	CLOUD_VERBOSITY_BEGIN ACTION_UPDATE
		printc 13, " update node "
		push	eax
		mov	eax, [eax + edx + node_addr]
		call	net_print_ipv4
		printc 8, "->"
		mov	eax, ecx
		call	net_print_ipv4
		pop	eax
		call newline
	CLOUD_VERBOSITY_END
	jmp	2f

1:	PTR_ARRAY_NEWENTRY [cluster_ips], 1, 9f	# out: eax+edx; destroys: ecx
	mov	[eax + edx], ecx
	mov	ebx, ecx # ecx destroyed next line:
	ARRAY_NEWENTRY [cluster_nodes], NODE_SIZE, 1, 9f
	mov	[ebp], edx	# STACKREF set return value
	mov	ecx, ebx
	lea	ebx, [eax + edx]
	mov	[ebx + node_addr], ecx
	mov	eax, [edi + 0]	# read mac
	mov	[ebx + node_mac], eax
	mov	ax, [edi + 4]	# read mac
	mov	[ebx + node_mac + 4], ax
	mov	eax, [clock]
	mov	[ebx + node_clock_met], eax

	CLOUD_VERBOSITY_BEGIN ACTION_ADD
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
	CLOUD_VERBOSITY_END
	CLOUD_VERBOSITY_BEGIN ACTION_ADD_DETAILS
		print "                  n "
		mov	edx, [esi + pkt_node_birthdate]
		call	print_datetime
		print " c "
		mov	edx, [esi + pkt_cluster_birthdate]
		call	print_datetime
		call	newline
	CLOUD_VERBOSITY_END

2:	mov	eax, [clock]
	mov	[ebx + node_clock], eax
	mov	[ebx + node_addr], ecx	# update IP

	push_ esi edi
	lea	edi, [ebx + node_cluster_data]
	mov	ecx, PKT_STRUCT_SIZE / 4
	rep	movsd
	pop_ edi esi

	clc

9:	pop_	edx ecx ebx
	pop	eax	# STACKREF return value
	pop	ebp
	ret


.data
packet_ping$:
.asciz "ping "
packet_ping_cluster_era:.long 0
packet_ping_node_age:	.long 0
packet_ping_end$ = .

ping_timeout_clocks: .long 0

.text32
cluster_ping:
	pushad

	CLOUD_VERBOSITY_BEGIN PING
		printlnc 11, "ping cluster"
	CLOUD_VERBOSITY_END

	LOAD_PACKET ping
	mov	eax, [cluster_node]
	mov	edx, [eax + cluster_era]
	mov	[esi + packet_ping_cluster_era], edx
	mov	edx, [eax + node_age]
	mov	[esi + packet_ping_node_age], edx
.if CLOUD_MCAST
	mov	eax, CLOUD_MCAST_IP
.else
	mov	eax, -1	# BCAST
.endif
	call	cloud_packet_send
	popad
	ret


# verify alive nodes
cluster_check_status:
	pushad
	#call	get_time_ms
	mov	ecx, [clock]

	# pretend we received a ping from ourselves
	mov	ebx, [cluster_node]
	mov	[ebx + node_clock], ecx
	# also update our node's ip using nic ip
	mov	ebx, [cloud_nic]
	mov	eax, [ebx + nic_ip]
	call	set_ip$

#	DEBUG_DWORD ecx,"clock"; DEBUG_DWORD [ping_timeout_clocks];call newline;
	mov	ebx, eax	# nic ip
	xor	edi, edi	# count on/offline nodes || (DMZ IP present)<<31

	testb	[cloud_flags], MAINTAIN_DMZ$
	jz	1f
	# mark if we have the DMZ IP
	cmp	eax, [lan_dmz_ip]
	jnz	1f
	or	edi, 1 << 31
1:

	ARRAY_LOOP [cluster_nodes], NODE_SIZE, eax, esi, 1f
	add	edi, 1 << 16	# high word: total nodes

	# update self
	cmp	ebx, [eax + esi + node_addr]
	jnz	1f
	mov	[eax + esi + node_clock], ecx
1:

	mov	edx, [eax + esi + node_clock]
	sub	edx, ecx	# cur clock
	neg	edx

	CLOUD_VERBOSITY_BEGIN PING_NODELIST
		push	esi
		lea	esi, [eax + esi + node_node_hostname]
		call	print
		pop	esi

		call	printspace
		push	eax
		mov	eax, [eax + esi + node_addr]
		call	net_print_ipv4
		pop	eax
		call	printspace

		call	printhex8
		call	printspace
		call	_print_time$
		call	_print_onoffline$
		call	newline
	CLOUD_VERBOSITY_END
1:
	cmp	edx, [ping_timeout_clocks]
	adc	edi, 0	# count

	# take action when a node times out
	cmp	edx, [ping_timeout_clocks]
	jb	1f
	#call	cluster_reboot_node

############## NODE OFFLINE

	CLOUD_VERBOSITY_BEGIN NODE_OFFLINE
		printc 12, "cluster node offline: "
		push_	eax esi
		add	eax, esi
		lea	esi, [eax + node_node_hostname]
		call	print
		call	printspace
		mov	esi, eax
		mov	eax, [esi + node_addr]
		call	net_print_ipv4
		call	printspace
		lea	esi, [esi + node_mac]
		call	net_print_mac
		call	newline
		pop_	esi eax
	CLOUD_VERBOSITY_END

	jmp	2f
############## END NODE OFFLINE
1:
############## NODE ONLINE
	########
		testb	[cloud_flags], MAINTAIN_DMZ$
		jz	4f
		mov	edx, [lan_dmz_ip]	# edx free here
	#	DEBUG_DWORD edx, "DMZ_IP"
	#	DEBUG_DWORD [eax+esi+node_addr], "node.addr"
		# check if it has DMZ IP
		cmpd	edx, [eax + esi + node_addr]
		jnz	4f
	#	DEBUG "dmz node found"
		or	edi, 1<<31	# mark found
	4:
	########


############## END NODE ONLINE
2:
	ARRAY_ENDL

	# ~(1<<31) & edi: lo: online nodes, hi: total nodes
	mov	eax, edi	# see cluster_check_dmz_ip$

	CLOUD_VERBOSITY_BEGIN PING_RESULT
		printc 11, "[cluster nodes] "
		#DEBUG_DWORD edi #(online + offline == total?)
		printc 10, "online: "
		movzx	edx, di
		call	printdec32
		shr	edi, 16
		and	edi, 0x7fff	# high bit indicates DMZ ip found
		sub	edi, edx
		jz	1f
		printc 12, " offline: "
		mov	edx, edi
		call	printdec32
	1:
		call	newline
	CLOUD_VERBOSITY_END

	call	cluster_check_dmz_ip$	# in: eax top bit: 1=DMZ IP present in cluster

	popad
	ret


cluster_check_dmz_ip$:
	testb	[cloud_flags], MAINTAIN_DMZ$
	jz	1f
	# check for DMZ IP and take over IP.
	test	eax, 1<<31	# see above (edi destroyed)
	jz	2f
1:	ret
2:

	CLOUD_VERBOSITY_BEGIN ACTION_DMZ_IP
		printc 12, " taking DMZ IP "
		DEBUG_DWORD eax
	CLOUD_VERBOSITY_END

	mov	eax, [lan_dmz_ip]
	call	arp_table_getentry_by_ipv4 # in: eax = ipv4; out: ecx + edx
	jc	3f
	movb	[ecx + edx + arp_entry_status], 0
3:	call	net_arp_resolve_ipv4
	jnc	91f

		mov	ebx, [cloud_nic]
		# IGMP leave
		mov	eax, CLOUD_MCAST_IP
		call	net_igmp_leave

		# UNARP
		mov	eax, -1		# UNARP wants BCAST
		call	arp_unarp

		mov	eax, [lan_dmz_ip]	# restore eax

	call	set_ip$

		# IGMP join
		mov	eax, CLOUD_MCAST_IP
		call	net_igmp_join

		mov	eax, [lan_dmz_ip]	# restore eax

	printc 14, " DMZ IP "
	call	net_print_ipv4
	printc 14, " obtained"

1:
	ret

91:	printlnc 4, "DMZ ip taken"
	ret





set_ip$:
	push	ebx
	mov	ebx, [cloud_nic]
	mov	[ebx + nic_ip], eax
	mov	ebx, [cluster_nodes]
	add	ebx, [cluster_nodeidx]
	mov	[ebx], eax
	# TODO: UNARP
	# TODO: MCAST
	pop	ebx
	ret


# in: eax + esi = node
cluster_reboot_node:
	printc 0xf0, "rebooting node: "
	pushad	# only ebp/esp not used
	lea	edx, [eax + esi + node_node_hostname]
	push	edx
	call	_s_println
	# send UDP packet to IP

	NET_BUFFER_GET
	jc	91f
	push	edi

	add	esi, eax
	mov	eax, [esi + node_addr]	# IPV4 dest
	lea	esi, [esi + node_mac]
	mov	ebx, [cloud_nic]

	# ETH, IP frame
	mov	ecx, 4 + UDP_HEADER_SIZE
	mov	dx, IP_PROTOCOL_UDP | 4 << 8	# force use esi MAC
	# in: edi = out packet
	# in: dl = ipv4 sub-protocol
	# in: dh = bit 0: 0=use nic ip; 1=use 0 ip; bit 1: 1=edx>>16&255=ttl
	# in: eax = destination ip
	# in: ecx = payload length (without ethernet/ip frame)
	# in: ebx = nic - ONLY if eax = -1!
	# in: esi = mac - ONLY if eax = -1!
	# out: edi = points to end of ethernet+ipv4 frames in packet
	# out: ebx = nic object (for src mac & ip) [calculated from eax]
	# out: esi = destination mac [calculated from eax]
	push	edi	# remember eth frame start
	call	net_ipv4_header_put
	pop	edx	# edx = eth frame
	jc	9f

	# UDP frame
	mov	eax, (999<<16) | (999) # dport<<16|sport !XXXX should make edx like tcp!
	sub	ecx, UDP_HEADER_SIZE	# in: ecx = udp payload len
	mov	esi, edi		# remember udp frame start
	call	net_udp_header_put
	add	ecx, UDP_HEADER_SIZE

	mov	[edi], dword ptr 0x1337c0de
	add	edi, 4	# for NET_BUFFER_SEND
.if 1
	mov	eax, [esi - IPV4_HEADER_SIZE + ipv4_src]
	mov	edx, [esi + IPV4_HEADER_SIZE + ipv4_dst]
	call	net_udp_checksum	# in: eax,edx, esi=udp frame, ecx=udp framelen
.else
	push	edi
	add	edx, offset ipv4_src + ETH_HEADER_SIZE # in: edx = ipv4 src,dst
	mov	eax, IP_PROTOCOL_UDP
	mov	edi, offset udp_checksum
	call	net_ip_pseudo_checksum
	pop	edi
.endif


	pop	esi
	NET_BUFFER_SEND
	jc	91f

9:	popad
	ret
91:	printlnc 4, "net_buffer get/send error"
	jmp	9b

#############################################################################
# Cluster Event Handler

CLUSTER_DEBUG = 0

CL_PAYLOAD_START = 18	# sock readpeer: src.ip,src.port,dst.ip,dst.port,src.mac

# in: esi,ecx = packet
cloudnet_handle_packet:

	CLOUD_VERBOSITY_BEGIN RX
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
	CLOUD_VERBOSITY_END


	# detect message
	.macro ISMSG name, label
		push_	edi esi ecx
		add	esi, CL_PAYLOAD_START
		LOAD_TXT "\name", edi, ecx
		repz	cmpsb
		pop_	ecx esi edi
		jz	\label
	.endm

	#cmpd	[esi + CL_PAYLOAD_START + 0], 'h'|'e'<<8|'l'<<16|'l'<<24
	mov	eax, [esi + CL_PAYLOAD_START + 0]
	or	eax, 0x20202020
	cmp	eax, 'h'|'e'<<8|'l'<<16|'l'<<24
	jnz	60f
	cmpw	[esi + CL_PAYLOAD_START + 4], 'o'
	jnz	60f

#	ISMSG "hello", 1f
#	ISMSG "ping", 2f
#	ISMSG "pong", 3f
#	jmp	91f
	.purgem ISMSG

# hello packet
1:

	mov	eax, [esi]	# peer ip
	push	esi
	lea	edi, [esi + 12]	# mac
	lea	esi, [esi + CL_PAYLOAD_START + 6] # 6: "hello\0"
	call	cluster_add_node
	pop	esi

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
	mov	[eax + cluster_birthdate], edx
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
	.if CLUSTER_DEBUG
		printc 14, " adopt cluster birthdate "	# XXX TODO do not adopt in same era!
		call	print_datetime
		printc 14, " for era "
		mov	edx, [eax + cluster_era]
		call	printdec32
		call	newline
	.endif

3:	# persist
	call	[eax + oofs_persistent_api_save] # XXX sometimes eax = 0 here!

	# update local node in nodelist
	CLOUD_VERBOSITY_BEGIN ACTION_UPDATE
		printc 8, " (local) "
	CLOUD_VERBOSITY_END

	push	esi
	lea	esi, [eax + cluster_node_persistent]
	mov	edi, [cloud_nic]
	mov	eax, [edi + nic_ip]
	lea	edi, [edi + nic_mac]
	call	cluster_add_node	# update display list
	pop	esi
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
.if CLOUD_MCAST
	testb	[esi + CL_PAYLOAD_START], 0x20	# check capital letter
	jz	9f	# zero - capital letter - no response
	andb	[eax + cluster_node_pkt], ~0x20
	mov	[eax + cluster_node_pkt], byte ptr 'H'
.else
	cmpd	[esi + 6], -1	# destination broadcast?
	jnz	9f
.endif

	CLOUD_VERBOSITY_BEGIN ACTION_RESPOND
		printc 13, " respond "
	CLOUD_VERBOSITY_END

	mov	edx, [esi]	# src ip
	push eax
	call	[eax + send]
	pop eax
.if CLOUD_MCAST
	orb	[eax + cluster_node_pkt], 0x20
	mov	[eax + cluster_node_pkt], byte ptr 'h'
.endif
	ret
# pong
9:
	CLOUD_VERBOSITY_BEGIN ACTION_IGNORE
		printlnc 13, " ignore"
	CLOUD_VERBOSITY_END
	ret


# not hello, check ping
60:	cmp	eax, 'p'|'i'<<8|'n'<<16|'g'<<24
	jnz	91f
	cmpb	[esi + CL_PAYLOAD_START + 4], ' '
	jnz	91f
# ping
	pushad
	mov	eax, [esi]	# SOCK READPEER ip

	CLOUD_VERBOSITY_BEGIN RX
		printc 11, " rx ping "
		mov	eax, [esi]		# peer ip
		mov	dx, word ptr [esi + 4]	# peer port
		xchg	dl, dh
		call	print_addr$
		call	printspace
		add	esi, 12	# ipv4 + port *2
		call	net_print_mac
		sub	esi, 12
	CLOUD_VERBOSITY_END

	mov	edx, [clock]	# ???

	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, ecx, 1f
.if 0	# match by IP
	cmp	eax, [ebx + ecx + node_addr]
	jz	1f
.else	# match by MAC
	push_	esi edi
	add	esi, 12	# mac
	lea	edi, [ebx + ecx + node_mac]
	cmpsd
	jnz	4f
	cmpsw
4:	pop_	edi esi
	jz	1f
	# ... and name - TODO: automatic unique hostname 
.endif
	ARRAY_ENDL

	printc 12, " cloud rx ping: new node: "
	call	net_print_ip
	call	newline

	# send hello to the unknown node
	CLOUD_VERBOSITY_BEGIN ACTION_RESPOND
		printc 13, " respond "
	CLOUD_VERBOSITY_END

	mov	edx, [esi]	# src ip
	mov	eax, [cluster_node]
	call	[eax + send]

	#pushad
	#call	cloud_send_hello	# in: eax = dest
	#popad

	jmp	2f

1:
	CLOUD_VERBOSITY_BEGIN RX
		printc 13, " update node "
		lea	esi, [ebx + ecx + node_node_hostname]
		call	println
	CLOUD_VERBOSITY_END

	mov	[ebx + ecx + node_clock], edx
	mov	[ebx + ecx + node_addr], eax # update IP
	# TODO also: ifconfig ip change event handler to update local node_addr
2:	popad
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
	lodsd

	xor	edi, edi	# verbosity / global option

	# parse options
0:	lodsd
	or	eax, eax
	jz	cmd_cloud_print$	# default action

	cmpb	[eax], '-'
	jnz	1f			# no more options
	CMD_ISARG "-v"
	jnz	2f
	inc	edi
	jmp	0b

2:	printc 12, "unknown argument: "
	push	eax
	call	_s_println
	ret

1:	CMD_ISARG "status"
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

	CMD_ISARG "reboot"
	jz	cmd_cloud_reboot_node

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

1:	printlnc 12, "usage: cloud [options] [<command> [args]]"
	printlnc 12, " options: -v: increase verbosity; can have more than one"
	printlnc 12, " commands: status init register start stop reboot"
	ret

cmd_cloud_reboot_node:
	lodsd
	or	eax, eax
	jz	91f
	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, ecx
	lea	edx, [ebx + ecx + node_node_hostname]
	call	strcmp
	jz	1f
	ARRAY_ENDL
	ret
1:	mov	eax, ebx
	mov	esi, ecx
	call	cluster_reboot_node
	ret
91:	printlnc 12, "reboot expects hostname"
	ret

# in: edi = format/verbose level:
cmd_cloud_print$:
	printc 11, "CloudNet status: "
	mov	eax, [cloud_flags]
	PRINTFLAG al, STOP$, "passive", "active"
	PRINTFLAG al, MAINTAIN_DMZ$, " maintain_dmz", ""
	mov	eax, [cloud_nic]
	mov	eax, [eax + nic_ip]
	call	printspace
	call	net_print_ipv4
	cmp	eax, [lan_dmz_ip]
	jnz	1f
	printc 10, " (DMZ)"
1:	call	newline

	cmp	edi, 1
	jb	2f

	mov	eax, [cluster_node]
	or	eax, eax
	jz	2f


	printc 15, "Kernel Revision: "
	push	edi
	sub	esp, 128
	mov	edi, esp
	mov	ecx, 128
	call	cluster_get_kernel_revision
	mov	esi, esp
	call	println
	add	esp, 128
	pop	edi

	call	[eax + oofs_api_print]
2:

	mov	ebx, [cluster_nodes]


	or	ebx, ebx
	jz	2f

	cmp	edi, 1
	jb	1f

	print "local cluster: "
	mov	eax, [ebx + array_index]
	xor	edx, edx
	mov	ecx, NODE_SIZE
	div	ecx
	mov	edx, eax
	call	printdec32
	call	newline
1:
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
	pushstring "%16s"
	call	printf
	add	esp, 8

	call	printspace
	mov	eax, [ebx + ecx + node_addr]
	call	print_ip$
	call	printspace

	cmp	edi, 1
	jb	1f

	pushcolor 8
	lea	esi, [ebx + ecx + node_mac]
	call	net_print_mac
	popcolor
	call	newline

	pushd	[ebx + ecx + node_kernel_revision]
	mov	edx, [ebx + ecx + node_node_age]
	push	edx
	mov	edx, [ebx + ecx + node_cluster_era]
	push	edx
	pushstring "   c.era %3d n.age %3d krnlrev %3d"
	call	printf
	add	esp, 4*4

	call	newline
	printc 15, "   (met: "

	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock_met]
	call	_print_time$
	print " ago"

	printc 15, " seen: "
1:	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock]
	call	_print_time$
	cmp	edi, 1
	jb	1f
	print " ago) "

1:	call	_print_onoffline$
	call	newline

	######################################################

	cmp	edi, 2
	jb	1f

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
1:

	ARRAY_ENDL
2:	ret

_print_time$:
	push_	edi eax edx
	mov	edi, edx
	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]
	shrd	eax, edx, 8
	shr	edx, 8
	imul	edi
	call	print_time_ms_40_24
	pop_	edx eax edi
	ret


# in: eax = milliseconds
# out: eax = clocks
_calc_time_clocks$:
	push_	edx ebx
	mov	ebx, eax

	# let's assume that the timer is at least 4Hz,
	# or 255 milliseconds per clock

	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]
	shrd	eax, edx, 8
	shr	edx, 8
	jnz	91f

	# it does.

	mov	edx, ebx
	# edx:eax = millisec period : 00000000
	mov	ebx, eax
	xor	eax, eax
	# ebx = clock period millisecs 8:24
	div	ebx
	shr	eax, 8
	mov	edx, eax
9:	pop_	ebx edx
	ret
91:	printc 12, "warning: clock < 4Hz not implemented"
	mov	eax, [pit_timer_period + 4]	# approximate
	jmp	9b

_print_onoffline$:
	cmp	edx, [ping_timeout_clocks]
	jae	1f
	printc 10, " online"
	jmp	2f
1:	printc 12, " offline"
2:	ret


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
1:
	CLOUD_VERBOSITY_BEGIN INIT_NODE
		printc 10, " * got table: "
		PRINT_CLASS
		call	newline
	CLOUD_VERBOSITY_END

.data SECTION_DATA_BSS
table:.long 0
.text32
	mov	[table], eax

	# find cluster node
	mov	edx, offset class_cluster_node
	xor	ebx, ebx

	CLOUD_VERBOSITY_BEGIN INIT_NODE
		printc 13, " lookup cluster_node"
	CLOUD_VERBOSITY_END

	call	[eax + oofs_table_api_lookup]	# out: ecx=index
	jnc	1f

	CLOUD_VERBOSITY_BEGIN INIT_NODE
		printc 4, " not found"
	CLOUD_VERBOSITY_END

	# edx=class_cluster_node
	mov	eax, [table]
	mov	ecx, 512
	call	[eax + oofs_table_api_add]	# edx=class -> eax=instance
	jc	93f

	CLOUD_VERBOSITY_BEGIN INIT_NODE
		printc 9, " - added cluster_node to oofs"
	CLOUD_VERBOSITY_END

	jmp	2f

##################################################################
# in: ecx = oofs_vol entry number
1:
	CLOUD_VERBOSITY_BEGIN INIT_NODE
		call	newline
	CLOUD_VERBOSITY_END

	mov	eax, [esp]	# oofs_vol
	mov	eax, [eax + net_persistence]	# 'root': oofs
	#printc 9, "cluster_node: oofs.load_entry "
	#xchg ecx,edx;call printdec32;xchg edx,ecx
	call	[eax + oofs_vol_api_load_entry]	# in: ecx = index; out: eax
	jc	94f

##################################################################
2:	incd	[eax + node_age]
# TEMP FIX
#mov [eax+cluster_era], dword ptr 0
#mov [eax + cluster_birthdate], dword ptr 0x365b77dc

	CLOUD_VERBOSITY_BEGIN INIT_NODE
		printc 10, " * got cluster node: "
		pushd	[eax + node_age]
		pushd	[eax + cluster_era]
		pushstring "cluster era: %d  node age: %d\n"
		call	printf
		add	esp, 12
	CLOUD_VERBOSITY_END

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

# stores the cluster kernel revision in the given buffer
# in: edi = buffer
# in: ecx = buffer size, minimum: 4+version.length+1+era.length+age.length*2
# out: ecx = bytes stored in buffer
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

# in: [esp + 0] = len
# in: [esp + 4] = stringptr
# in: [ebp + 0] = bufsize
# in: [ebp + 4] = buffer
# in: [[ebp-4]] = socket
# in: edi = buf pos to append to
# out: edi updated
# out: esp += 8 (pops stackargs)
sockbuf_append_string$:
	push_	esi ecx edx eax
	mov	edx, edi
	mov	ecx, [esp + 5*4 + 0]
	sub	edx, [ebp + 4]	# edx = remaining buflen
	sub	edx, ecx
	jnle	1f
	call	sockbuf_flush$	# resets edi, ecx
1:	mov	esi, [esp + 5*4 + 4]
	mov	al, cl
	shr	ecx, 2
	rep	movsd
	mov	cl, al
	and	cl, 3
	rep	movsb
	pop_	eax edx ecx esi
	ret	8

# in: [ebp + 0] = bufsize
# in: [ebp + 4] = buffer
# in: [[ebp-4]] = socket
# in: edi = buf pos
sockbuf_flush$:
	push_	eax ecx esi
	# write socket
	mov	ecx, edi
	mov	esi, [ebp + 4]	# buffer start
	sub	ecx, esi	# buffer filled
	mov	eax, [ebp - 4]	# socket ptr
	mov	eax, [eax]	# socket
	KAPI_CALL socket_write
	# reset buffer
	mov	edi, [ebp + 4]
	#mov	ecx, [ebp + 0]
	pop_	esi ecx eax
	ret


.macro SOCKBUF_APPEND_STRING str
	PUSH_TXT "\str", 1	# push len also, w/o trailing 0
	call	sockbuf_append_string$
.endm

# in: [ebp] = socket (writes directly)
# in: edi, ecx = buffer
cluster_stream_cluster_status:
	push_	edx ebx esi edi ecx ebp
	lea	ebp, [esp + 4]
	# [[ebp-4]] = socket
	# [ebp+0] = buffer size
	# [ebp+4] = buffer

	SOCKBUF_APPEND_STRING "<b>Host:</b> "
	mov	esi, offset hostname
	call	strlen_
	rep	movsb

	SOCKBUF_APPEND_STRING " <b>nodes:</b> "

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

	mov	eax, [cluster_node]
	or	eax, eax
	jz	1f

	SOCKBUF_APPEND_STRING " <b>era:</b> "
	mov	edx, [eax + cluster_era]
	call	sprintdec32

	SOCKBUF_APPEND_STRING " <b>uptime:</b> "
	mov	edx, [eax + cluster_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

1:	call	sockbuf_flush$
	mov	ecx, edi
	sub	ecx, [ebp + 4]
	mov	[ebp], ecx
	pop_	ebp ecx edi esi ebx edx
	ret

91:	# doesn't fit (but should); for now, no flush
	DEBUG "<NOFIT>"
	pop_	ecx esi
	jmp	0b


# in: [ebp + 16] = flags
#	2: table (<tr><td>), else <li>
#	8: add " class='cur'"
_html_item_open$:
	movb	[edi], '\t'
	inc	edi

	mov	eax, '<' | 'l' << 8 | 'i' << 16 | '>' << 24
	testb	[ebp + 16], 2
	jz	1f
	mov	eax, '<' | 't' << 8 | 'r' << 16 | '>' << 24
1:	stosd

	testb	[ebp + 16], 8
	jz	1f

	dec	edi
	SOCKBUF_APPEND_STRING " class='cur'>"

1:	testb	[ebp + 16], 2
	jz	1f
	mov	eax, '<' | 't' << 8 | 'd' << 16 | '>' << 24
	stosd

1:	ret

_html_cell$:
	testb	[ebp + 16], 2
	jz	1f
	SOCKBUF_APPEND_STRING "</td><td>"
	ret
1:	movb	[edi], ' '
	inc	edi
	ret

_html_item_close$:
	testb	[ebp + 16], 2
	jz	1f
	SOCKBUF_APPEND_STRING "</td></tr>\n"
	ret
1:	mov	eax, '<'|'/'<<8|'l'<<16|'i'<<24
	stosd
	mov	ax, '>' | '\n' << 8
	stosw
	ret


# Produces html
# in: [ebp] = socket (writes directly)
# in: edi, ecx = buffer
#[out: ecx = len]
cluster_stream_nodes_table:
	push	edx
	mov	edx, 2
	jmp	1f
cluster_stream_nodes_list:
	push	edx
	xor	edx, edx

# in: edx = flags
#	bit 1: node list format: 0=ul, 1=table
# in: [esp] = edx
1:
	push_	edx ebx esi edi ecx ebp
	lea	ebp, [esp + 4]
	# [[ebp-4]] = socket
	# [ebp+0] = buffer size
	# [ebp+4] = buffer

	mov	ebx, [cluster_nodes]
	or	ebx, ebx
	jz	9f	# no cluster nodes (shouldn't happen)

	# list / table header
	testb	[ebp + 16], 2
	jnz	1f
	SOCKBUF_APPEND_STRING "\n<ul>\n"
	jmp	2f
1:	SOCKBUF_APPEND_STRING "\n<table>\n\t<tr><th>name</th><th>status</th><th>age</th><th>krev</th><th>boot time</th><th>uptime</th><th>joined cluster</th><th>cluster uptime</th></tr>\n"
2:

	# iterate

	ARRAY_LOOP [cluster_nodes], NODE_SIZE, ebx, esi

	# use [ebp + 16] bit 3 to indicate current item = this node
	mov	eax, [cloud_nic]
	mov	eax, [eax + nic_ip]
	cmp	eax, [ebx + esi + node_addr]
	mov	al, 0
	jnz	1f
	mov	al, 8
1:	andb	[ebp + 16], ~8
	orb	[ebp + 16], al

	# element / row

	call	_html_item_open$

	# hostname

	push	esi
	mov	al, ' '
	stosb
	lea	esi, [ebx + esi + node_node_hostname]
	call	strlen_
	rep	movsb
	stosb
	pop	esi

	# cell: online status

	call	_html_cell$

	push	esi
	mov	edx, [clock]
	sub	edx, [ebx + esi + node_clock]
	cmp	edx, [ping_timeout_clocks]
	LOAD_TXT "<span style='color:red'>offline</span>", esi, ecx, 1
	jae	1f
	LOAD_TXT "<span style='color:#0f0'>online</span>", esi, ecx, 1
1:	rep	movsb
	pop	esi

	# cell: era#age

	call	_html_cell$


	mov	edx, [ebx + esi + node_cluster_era]
	call	sprintdec32
	mov	al, '#'
	stosb
	mov	edx, [ebx + esi + node_node_age]
	call	sprintdec32

	testb	[ebp + 16], 2
	jnz	1f
	sprintchar ' '
	sprintchar '('
	mov	edx, [ebx + esi + node_node_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s
	sprintchar ')'

	jmp	0f

1:
	call	_html_cell$

	movzx	edx, word ptr [ebx + esi + node_kernel_revision]
	call	sprintdec32

	call	_html_cell$

	mov	edx, [ebx + esi + node_node_birthdate]
	call	sprint_datetime

	call	_html_cell$

	# uptime
	mov	edx, [ebx + esi + node_node_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

	call	_html_cell$

	mov	edx, [ebx + esi + node_cluster_birthdate]
	call	sprint_datetime

	call	_html_cell$

	mov	edx, [ebx + esi + node_cluster_birthdate]
	call	datetime_to_s
	mov	eax, edx
	call	get_datetime_s
	sub	edx, eax
	mov	eax, edx
	call	sprint_time_s

0:	call	_html_item_close$

	call	sockbuf_flush$

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
	pop_	ebp ecx edi esi ebx edx edx
	ret

91:	# doesn't fit (but should); for now, no flush
	DEBUG "<NOFIT>"
	pop	esi
	jmp	0b
