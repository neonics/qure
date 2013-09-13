###############################################################################
# CloudNet - Clustered Distributed Network
.intel_syntax noprefix
.text32

#############################
.global cmd_cloudnetd
.global cmd_cloud

CLOUD_PACKET_DEBUG = 0


CLOUD_LOCAL_ECHO = 1

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
	call	cloud_socket_open
	jc	9f
	call	cloud_rx_start
	jc	9f

	mov	eax, offset class_cluster_node
	call	class_newinstance
	jc	1f
	call	[eax + init]
	jc	2f
	mov	[cluster_node], eax
	printc 11, "cluster_node initialized: cluster era: "
	mov	edx, [eax + cluster_era]
	call	printdec32
	printc 11, " node age: "
	mov	edx, [eax + node_age]
	call	printdec32
	call	newline
# in: eax = ip
# in: edx = cluster state (hello_nr; [word cluster era<<16][word node_age]
# in: esi, ecx = packet
# out: ZF = 0: added, ZF = 1: updated
mov	eax, [lan_ip]
lea	esi, [packet_hello_payload]
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
	call	cloud_send_hello
	ret

.struct 0
pkt_cluster_era:	.long 0
pkt_node_age:		.long 0
pkt_kernel_revision:	.long 0
pkt_node_birthdate:	.long 0
PKT_STRUCT_SIZE = .

.data
packet_hello$:
.asciz "hello"
packet_hello_payload:
.space PKT_STRUCT_SIZE
packet_hello_end$ = .
.text32

.macro LOAD_PACKET p
	mov	esi, offset packet_\p\()$
	mov	ecx, offset packet_\p\()_end$ - packet_\p\()$;
.endm

# in: eax = dest
cloud_send_hello:
	LOAD_PACKET hello
	push_	edx eax
	mov	eax, [cluster_node]
	mov	edx, [eax + cluster_era]
	mov	[packet_hello_payload + pkt_cluster_era], edx
	mov	edx, [eax + node_age]
	mov	[packet_hello_payload + pkt_node_age], edx
	mov	edx, [kernel_boot_time]
	mov	[packet_hello_payload + pkt_node_birthdate], edx
	mov	edx, KERNEL_REVISION
	mov	[packet_hello_payload + pkt_kernel_revision], edx
	pop_	eax edx
	call	cloud_packet_send
	ret

cluster_packet_send:
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


9:	printlnc 4, "cloudnet: cannot open socket, terminating"
	ret


################################################
# Cluster Management
.struct 0
node_addr:	.long 0
node_cstatus_c_era: .long 0
node_cstatus_n_age: .long 0
node_cycles:	.long 0
node_clock_met:	.long 0
node_clock:	.long 0
node_birthdate:	.long 0
node_kernel_revision: .long 0
NODE_SIZE = .
.data
cluster_ips:	.long 0	# ptr_array for scasd
cluster_nodes:	.long 0	# array of node struct
.text32

# in: eax = ip
# in: esi = ptr to [.long cluster_era, node_age] in packet
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
2:	printc 13, " update node"
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
	mov	eax, [clock]
	mov	[ebx + node_clock_met], eax

	printc 13, " add cluster node "
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

2:	mov	eax, [clock]
	mov	[ebx + node_clock], eax
	mov	eax, [esi + pkt_cluster_era]	# cluster era
	mov	[ebx + node_cstatus_c_era], eax
	mov	eax, [esi + pkt_node_age] # node age
	mov	[ebx + node_cstatus_n_age], eax
	mov	eax, [esi + pkt_kernel_revision]
	mov	[ebx + node_kernel_revision], eax
	mov	eax, [esi + pkt_node_birthdate]
	mov	[ebx + node_birthdate], eax

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
	# send era,age nown for node
	mov	ecx, [ebx + edx + node_cstatus_c_era]
	mov	[packet_hello_payload + pkt_cluster_era], ecx
	mov	ecx, [ebx + edx + node_cstatus_n_age]
	mov	[packet_hello_payload + pkt_cluster_era], ecx

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
	xchg	dl, dh
	call	print_addr$
	call	printspace
.endif
	push	esi
	add	esi, 12	# adjust
	sub	ecx, 12
	call	cloudnet_packet_print
	pop	esi

	mov	eax, [esi]	# peer ip
	push	esi
	lea	esi, [esi + 12 + 6] # 12:READPEER, 6: "hello\0"
	call	cluster_add_node
	pop	esi

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
	push	eax	# preserve ip
	mov	eax, [cluster_node]
	mov	edx, [eax + cluster_era]
	mov	[packet_hello_payload + pkt_cluster_era], edx
	mov	edx, [eax + node_age]
	mov	[packet_hello_payload + pkt_node_age], edx
	pop	eax
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
	mov	dl, al
	call	printhex2
	call	printspace
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
#######
9:	popcolor
	pop_	eax ecx edx edi esi
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
	mov	eax, [lan_ip]
	call	printspace
	call	net_print_ipv4
	call	newline

	mov	eax, [cluster_node]
	or	eax, eax
	jz	2f

	sub	esp, 128
	mov	edi, esp
	mov	ecx, 128
	call	cluster_get_kernel_revision
	pushd	esp
	pushd	[eax + node_age]
	pushd	[eax + cluster_era]
	pushstring "cluster era: %d  node age: %d  Kernel Revision: %s\n"
	call	printf
	add	esp, 16 + 128

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
	mov	eax, [ebx + ecx + node_addr]
	call	print_ip$
	pushd	[ebx + ecx + node_kernel_revision]
	mov	edx, [ebx + ecx + node_cstatus_n_age]
	push	edx
	mov	edx, [ebx + ecx + node_cstatus_c_era]
	push	edx
	pushstring " c.era %3d n.age %3d krnlrev %3d"
	call	printf
	add	esp, 4*4

	print " birthdate: "
	mov	edx, [ebx + ecx + node_birthdate]
	call	print_datetime

	call	newline
	printc 15, "  (met: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock_met]
	call	_print_time$
	print " ago"

	printc 15, " seen: "
	mov	edx, [clock]
	sub	edx, [ebx + ecx + node_clock]
	call	_print_time$
	println " ago)"

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

1:	CMD_ISARG "init"
	jnz	1f
	mov	eax, [cluster_node]
		or	eax, eax
		jnz	2f
		mov	eax, offset class_cluster_node
		call	class_newinstance
		jc	9f
		mov	[cluster_node], eax
2:	call	[eax + init]
9:	ret

1:	printlnc 4, "usage: cloud <command> [args]"
	printlnc 4, " commands: start stop"
	ret


###############################################################################
# NETOBJ & persistence: OOFS extension
#

.include "fs/oofs/export.h"

.global netobj

.if 0
###################################
DECLARE_CLASS_BEGIN persistent
	persistence:	.long 0 # fs_oofs instance field oofs_root: class oofs

DECLARE_CLASS_METHOD persistence_init, netobj_persistence_init
DECLARE_CLASS_END persistent
.text32
# in: eax = this netobj
# in: edx = instance of net/fs/oofs
netobj_persistence_init:
	mov	[eax + persistence], edx
	ret
###################################
.endif

# base class network object
DECLARE_CLASS_BEGIN netobj, oofs, offs=oofs_persistent
netobj_packet:
	# can't declare class data here: struct!
	#.ascii "NOBJ"
DECLARE_CLASS_METHOD init, 0
DECLARE_CLASS_METHOD send, netobj_send
DECLARE_CLASS_END netobj
.text32
# in: ecx = offset of end of packet, payload size
netobj_send:
	lea	esi, [eax + netobj_packet]
	call	cluster_packet_send
	ret
###################################
DECLARE_CLASS_BEGIN cluster_node, netobj

cluster_node_persistent:
	cluster_era:	.long 0 # cluster incarnations
	node_age:	.long 0
	cluster_era_start:.long 0 # age when era incremented
	cluster_birthdate:.long 0 # cmos time

.org cluster_node_persistent + 512

cluster_node_volatile:
	net_fs:		.long 0	# fs_oofs object (direct access), mounted on /net/
	net_persistence:.long 0	# oofs object - root

DECLARE_CLASS_METHOD init, cluster_node_init, OVERRIDE
DECLARE_CLASS_METHOD send, cluster_node_send, OVERRIDE


DECLARE_CLASS_METHOD oofs_api_init, cluster_node_init$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_load, cluster_node_load$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_add, cluster_node_add$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_save, cluster_node_save$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_onload, cluster_node_onload, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_get_obj, cluster_node_get_obj$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, cluster_node_print$, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_lookup, cluster_node_lookup$, OVERRIDE

DECLARE_CLASS_END cluster_node
.text32

# preload
cluster_node_init$:
	printc 4, "cluster_node.oofs_api_init"
	mov	[eax + oofs_parent], edx
	mov	[eax + oofs_lba], ebx
	mov	[eax + oofs_size], ecx
	pushd	[edx + oofs_persistence]
	popd	[eax + oofs_persistence]
	clc
	ret

cluster_node_load$:
	push_	ebx ecx edi edx esi
	lea	edi, [eax + cluster_node_persistent]
	mov	ebx, [eax + oofs_lba]	# 0
	mov	ecx, 512
	# TODO: class_instance_resize if edi + ecx > obj_size
	mov	edx, eax

	push	eax
	mov	edx, [eax + obj_class]
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	jc	9f
	call	[eax + oofs_api_onload]

0:	pop_	esi edx edi ecx ebx
	ret
9:	printc 4, "cluster_node_load: read error"
	stc
	jmp	0b


cluster_node_onload:
	mov	[cluster_node], eax	# update singleton/static access

	# TEMPORARY reset:
	mov	dword ptr [eax + cluster_era], 0
	mov	dword ptr [eax + cluster_era_start], 0

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



cluster_node_add$: printlnc 4, "oofs_api_add: N/A @ cluster_node";stc;ret
cluster_node_get_obj$: printlnc 4, "oofs_api_get_obj: N/A @ cluster_node";stc;ret
cluster_node_print$: printlnc 4, "oofs_api_print: N/A @ cluster_node";stc;ret
cluster_node_lookup$: printlnc 4, "oofs_api_lookup: N/A @ cluster_node";stc;ret

cluster_node_save$:
	printc 9, "cluster_node.oofs_api_save: "
	push_	ecx esi edx ebx eax
	mov	ecx, 512
	lea	esi, [eax + cluster_node_persistent]
	mov	ebx, [eax + oofs_lba]
	mov	edx, [eax + obj_class]
	mov	eax, [eax + oofs_persistence]
	call	[eax + fs_obj_api_write]
	pop_	eax ebx edx esi ecx
	ret


# out: eax = instance
cluster_node_init:
	push_	esi edx ecx ebx eax
	LOAD_TXT "/net"
	call	mtab_get_fs	# out: edx
	.if NET_AUTOMOUNT
	jnc	1f

	pushad
	mov	ebp, esp
	printc 9, "cluster_node: auto-mounting /net: "
	pushd	0
	pushstring "/net"
	pushstring "hda0"
	pushstring "mount"
	mov	esi, esp
	KAPI_CALL fs_mount
	mov	esp, ebp
	popad
	jc	9f
	printlnc 11, " mounted."
	call	mtab_get_fs
	.endif
	jc	9f
1:

	printc 11, "cluster_node: opened "
	call	print
	print ", class="

	mov	esi, [edx + obj_class]
	pushd [esi + class_name]
	call _s_println

	mov	esi, eax	# backup
	mov	eax, edx
	mov	edx, offset class_fs_oofs
	call	class_instanceof
	jnz	91f
	mov	[esi + net_fs], eax	# fs_oofs
	mov	eax, [eax + oofs_root]
	mov	edx, offset class_oofs
	call	class_instanceof
	jnz	91f
	mov	[esi + net_persistence], eax

	mov	edx, eax	# oofs
	mov	eax, esi	# this
#	call	[eax + persistence_init]	# super constructor
#	mov	[eax + persistence], edx

	mov	eax, edx
	mov	edx, offset class_oofs_table
	xor	ebx, ebx	# iteration arg
	call	[eax + oofs_api_lookup]	# out: eax
	jc	92f

##################################################################
1:	printc 10, " * got table: "
	mov	edx, [eax + obj_class]
	mov	esi, [edx + class_name]
	call	println
.data SECTION_DATA_BSS
table:.long 0
.text32
	mov	[table], eax

	# find cluster node
	mov	edx, offset class_cluster_node
	xor	ebx, ebx
	printlnc 9, "lookup cluster_node"
	call	[eax + oofs_api_lookup]	#out:ecx
	jnc	1f
	printlnc 4, "cluster_node_init: oofs_table: cluster node not found"
	# edx=class_cluster_node
	mov	eax, [table]
	mov	ecx, 512
	call	[eax + oofs_api_add]
	jc	93f
	printlnc 9, "added cluster_node to oofs"
	jmp	2f

##################################################################
1:	# table lookup: edx= entry nr
	mov	eax, [esp] #get this
	mov	eax, [eax + net_persistence]	# 'root': oofs
	printc 9, "cluster_node: oofs.load_entry "
	xchg ecx,edx;call printdec32;xchg edx,ecx
	call	[eax+oofs_api_load_entry]
	jc	94f

##################################################################
2:	printc 10, " * got cluster node: "
	incd	[eax + node_age]
	call	[eax + oofs_api_save]

	pushd	[eax + node_age]
	pushd	[eax + cluster_era]
	pushstring "cluster era: %d  node age: %d\n"
	call	printf
	add	esp, 12

	mov	edx, [eax + cluster_era]
	mov	[packet_hello_payload + pkt_cluster_era], edx
	mov	edx, [eax + node_age]
	mov	[packet_hello_payload + pkt_node_age], edx
	mov	edx, KERNEL_REVISION
	mov	[packet_hello_payload + pkt_kernel_revision], edx
	mov	edx, [kernel_boot_time]
	mov	[packet_hello_payload + pkt_node_birthdate], edx

	mov	[esp], eax

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

cluster_node_send:
	push_	esi ecx
	mov	ecx, offset cluster_node_volatile
	call	[eax + send]	# or: netobj_send
	pop_	ecx esi
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
# in: edi, ecx = buffer
# out: ecx = len
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
# in: edi, ecx = buffer
# out: ecx = len
cluster_get_status_:
	push_	edx ebx esi edi ecx ebp
	lea	ebp, [esp + 4]

	mov	edx, ecx
	LOAD_TXT "nodes: ", esi, ecx
	sub	edx, ecx
	jle	9f
	sub	[ebp], ecx
	rep	movsb
	dec	edi
	mov	ecx, edx

	xor	edx, edx
	mov	ebx, [cluster_nodes]
	or	ebx, ebx
	jz	1f

	mov	eax, [ebx + array_index]
	xor	edx, edx
	mov	esi, NODE_SIZE
	div	esi
	mov	edx, eax

1:	call	sprintdec32
	testb	[ebp + 16], 1
	jz	9f

	mov	word ptr [edi], ' '

	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|('u'<<8)|('l'<<16)|('>'<<24)
	stosd
	jmp	3f

1:	mov	edx, ecx
	LOAD_TXT "<table>", esi, ecx, 1
	sub	edx, ecx
	jle	9f
	sub	[ebp], ecx
	rep	movsb
	mov	ecx, edx
3:
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
1:	push	esi
	LOAD_TXT "<tr><td>", esi, ecx, 1
	rep	movsb
	pop	esi
2:	mov	eax, [cloud_nic]
	mov	eax, [eax + nic_ip]
	cmp	eax, [ebx + esi + node_addr]
	mov	ah, 0
	jnz	1f
	mov	eax, '<'|('b'<<8)|('>'<<16)
	stosd
	dec	edi
	mov	ah, 1
	1:
	mov	edx, [ebx + esi + node_cstatus_c_era]
	call	sprintdec32
	mov	al, '#'
	stosb
	mov	edx, [ebx + esi + node_cstatus_n_age]
	call	sprintdec32
	cmp	ah, 1
	jnz	1f
	mov	eax, '<'|('/'<<8)|('b'<<16)|'>'<<24
	stosd
	1:

	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|'/'<<8|'l'<<16|'i'<<24
	stosd
	mov	al, '>'
	stosb
	jmp	0f

1:	push esi
	LOAD_TXT "</td><td>", esi, ecx, 1
	rep	movsb
	pop esi
	movzx	edx, word ptr [ebx + esi + node_kernel_revision]
	call	sprintdec32

	mov	edx, [ebx + esi + node_birthdate]
	push	esi
	LOAD_TXT "</td><td>birthdate ", esi, ecx, 1
	rep	movsb
	call	sprint_datetime
	LOAD_TXT "</td></tr>", esi, ecx, 1
	rep	movsb
	pop	esi
0:	ARRAY_ENDL

	testb	[ebp + 16], 2
	jnz	1f
	mov	eax, '<'|('/'<<8)|('u'<<16)|('l'<<24)
	stosd
	mov	al, '>'
	stosb
	jmp	9f

1:	LOAD_TXT "</table>", esi, ecx, 1
	rep	movsb

9:	mov	ecx, edi
	sub	ecx, [ebp + 4]
	mov	[ebp], ecx
	pop_	ebp ecx edi esi ebx edx
	ret
