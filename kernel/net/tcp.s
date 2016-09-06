################################################################################
# TCP  (RF793)
#
# (TODO: rfc1123)
#
NET_TCP_RESPOND_UNK_RST = 0	# whether to respond with RST packet for unknown
				# connections or non-listening ports.

NET_TCP_DEBUG		= 0#2
NET_TCP_CONN_DEBUG	= 0
NET_TCP_OPT_DEBUG	= 0	# only used in copy_options

# rfc879 "TCP Maximum Segment Size"
NET_IP_DEFAULT_MSS	= 576
NET_TCP_DEFAULT_MSS	= NET_IP_DEFAULT_MSS - 40	# i.e. 536

.struct 0	# TCP packet
tcp_sport:	.word 0
tcp_dport:	.word 0
tcp_seq:	.long 0	# 4f b2 f7 fc decoded as relative seq nr 0..
	# if SYN is set, initial sequence nr
	# if SYN is clear, accumulated seq nr of first byte packet
tcp_ack_nr:	.long 0	# zeroes - ACK nr when ACK set
	# if ack set, next seq nr receiver is expecting
tcp_flags:	.word 0	# a0, 02:  a = data offset hlen (10=40 bytes), 02=SYN
	TCP_FLAG_DATA_OFFSET	= 15<< 12
		# tcp header size in 32 bit/4byte words (a = 10 * 4=40)
		# min 5 (20 bytes), max 15 (60 bytes = max 40 bytes options)
	TCP_FLAG_RESERVED	= 7 << 9
	TCP_FLAG_NS		= 1 << 8 # NS: ECN NONCE concealment
	TCP_FLAG_CWR		= 1 << 7 # congestion window reduced
	TCP_FLAG_ECE		= 1 << 6 # ECN-Echo indicator: SN=ECN cap
	TCP_FLAG_URG		= 1 << 5 # urgent pointer field significant
	TCP_FLAG_ACK		= 1 << 4 # acknowledgement field significant
	TCP_FLAG_PSH		= 1 << 3 # push function (send buf data to app)
	TCP_FLAG_RST		= 1 << 2 # reset connection
	TCP_FLAG_SYN		= 1 << 1 # synchronize seq nrs
	TCP_FLAG_FIN		= 1 << 0 # no more data from sender.
tcp_windowsize:	.word 0	# sender receive capacity
tcp_checksum:	.word 0 #
tcp_urgent_ptr:	.word 0 # valid when URG
TCP_HEADER_SIZE = .
tcp_options:	#
	# 4-byte aligned - padded with TCP_OPT_END.
	# 3 fields:
	# option_kind:	 .byte 0	# required
	# option_length: .byte 0	# optional (includes kind+len bytes)
	# option_data: 	 .space VARIABLE# optional (len required)

	TCP_OPT_END	= 0	# 0		end of options (no len/data)
	TCP_OPT_NOP	= 1	# 1		padding; (no len/data)
	TCP_OPT_MSS	= 2	# 2,4,w  [SYN]	max seg size
	TCP_OPT_WS	= 3	# 3,3,b  [SYN]	window scale
	TCP_OPT_SACKP	= 4	# 4,2	 [SYN]	selective ack permitted
	TCP_OPT_SACK	= 5	# 5,N,(BBBB,EEEE)+   N=10,18,26 or 34
						# 1-4 begin-end pairs
	TCP_OPT_TSECHO	= 8	# 8,10,TTTT,EEEE
	TCP_OPT_ACR	= 14	# 14,3,S [SYN]	Alt Checksum Request
	TCP_OPT_ACD	= 15	# 15,N		Alt Checksum Data

	# 20 bytes:
	# 02 04 05 b4:	maximum segment size: 02 04 .word 05b4
	# 01:		nop: 01
	# 03 03 07:	window scale: 03 len: 03 shift 07
	# 04 02:	tcp SACK permission: true
	# timestamp 08 len 0a value 66 02 ae a8 echo reply 00 00 00 00

	# TCP Fast Open (RFC http://tools.ietf.org/html/rfc7413#section-2.2)
	TCP_OPT_TFO	= 34	# SYN only
	# len: 0 or 6..18 bytes , even, max until option space full (TODO find out what that is)
	# data: 0 or 4 .. 16 bytes
	#
	# client sends SYN+TFO with empty cookie (.byte 34,0)
	# server responds with cookie: SYN+ACK+TFO+cookie data;
	#
	# client sends cookie next time it SYN's
	# server responds with SYN+ACK (no cookie option)
	# (possibly with a new cookie option set, which the client
	#  should then use to replace it's old cookie)
	#
	# "The Fast Open Cookie is designed [..] to enable data exchange during
	#  a handshake".
	#
	# This effectively makes it an extension point. The data originally
	# intended is the payload, however, the TFO cookie itself is also data.
	# This can be leveraged by the firewall to route the request to a LAN
	# node. Connections with a proper cookie value will then be directed
	# towards the same node as last time.

.macro TCP_DEBUG_FLAGS r=ax
	PRINTFLAG ax, TCP_FLAG_NS, "NS "
	PRINTFLAG ax, TCP_FLAG_CWR, "CWR "
	PRINTFLAG ax, TCP_FLAG_ECE, "ECE "
	PRINTFLAG ax, TCP_FLAG_URG, "URG "
	PRINTFLAG ax, TCP_FLAG_ACK, "ACK "
	PRINTFLAG ax, TCP_FLAG_PSH, "PSH "
	PRINTFLAG ax, TCP_FLAG_RST, "RST "
	PRINTFLAG ax, TCP_FLAG_SYN, "SYN "
	PRINTFLAG ax, TCP_FLAG_FIN, "FIN "
.endm


.text32
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_ipv4_tcp_print:
	printc	15, "TCP"

	print	" sport "
	xor	edx, edx
	mov	dx, [esi + tcp_sport]
	xchg	dl, dh
	call	printdec32

	print	" dport "
	xor	edx, edx
	mov	dx, [esi + tcp_dport]
	xchg	dl, dh
	call	printdec32

	print	" seq "
	mov	edx, [esi + tcp_seq]
	bswap	edx
	call	printhex8

	print	" acknr "
	mov	edx, [esi + tcp_ack_nr]
	bswap	edx
	call	printhex8

	mov	ax, [esi + tcp_flags]
	xchg	al, ah
	movzx	edx, ax
	shr	dx, 12
	print	" hlen "
	call	printdec32

	print	" flags "
	DEBUG_WORD ax
	TCP_DEBUG_FLAGS ax

	call	newline
	ret


############################################
# TCP Connection management
TCP_MTU = ETH_MAX_PACKET_SIZE - ETH_HEADER_SIZE - IPV4_HEADER_SIZE - TCP_HEADER_SIZE
#
TCP_CONN_REUSE_TIMEOUT	= 30 * 1000	# 30 seconds
TCP_CONN_CLEAN_TIMEOUT	= 5 * 60 * 1000	# 5 minutes
TCP_CONN_BUFFER_SIZE	= 2 * 1500 # 2048
.struct 0	# TCP_CONN structure
# Buffers: not circular, as NIC's need contiguous region.
# The recv and send buf contain the data to be PSH'd.
tcp_conn_recv_buf:	.long 0	# malloc'd address
tcp_conn_recv_buf_size:	.long 0	# malloc'd size
tcp_conn_recv_buf_start:.long 0	# start of buffered data
tcp_conn_recv_buf_len:  .long 0	# length of buffered data

tcp_conn_send_buf:	.long 0	# malloc'd address
tcp_conn_send_buf_size:	.long 0	# malloc'd size
tcp_conn_send_buf_start:.long 0 # payload offset start in buf
tcp_conn_send_buf_len:	.long 0	# size of unsent data

tcp_conn_tx_fin_seq:	.long 0
tcp_conn_tx_syn_seq:	.long 0

tcp_conn_timestamp:	.long 0	# [clock_ms]

tcp_conn_local_addr:	.long 0	# NEEDS to be adjacent to tcp_conn_remote_addr
tcp_conn_remote_addr:	.long 0	# ipv4 addr
tcp_conn_local_port:	.word 0
tcp_conn_remote_port:	.word 0
tcp_conn_local_seq_base:.long 0
tcp_conn_local_seq:	.long 0
tcp_conn_local_seq_ack:	.long 0	# last received tcp.ack_nr
tcp_conn_remote_seq_base:.long 0
tcp_conn_remote_seq:	.long 0	# remote's last received seq
tcp_conn_remote_seq_ack:.long 0	# our ack to remote's seq
tcp_conn_rx_syn_remote_seq: .long 0	# remote's seq when it sent a FIN
tcp_conn_sock:		.long 0	# -1 = no socket; peer socket
tcp_conn_handler:	.long 0	# -1 or 0 = no handler
tcp_conn_remote_mss:	.long 0	# Maximum Segment Size peer supports (.word; long for easy math)
tcp_conn_state:		.byte 0
	# incoming
	TCP_CONN_STATE_SYN_RX		= 1
	TCP_CONN_STATE_SYN_ACK_TX	= 2
	# outgoing
	TCP_CONN_STATE_SYN_TX		= 4
	TCP_CONN_STATE_SYN_ACK_RX	= 8
	# incoming
	TCP_CONN_STATE_FIN_RX		= 16
	TCP_CONN_STATE_FIN_ACK_TX	= 32
	TCP_CONN_STATE_FIN_ACK_TX_SHIFT = 5
	# outgoing
	TCP_CONN_STATE_FIN_TX		= 64
	TCP_CONN_STATE_FIN_ACK_RX	= 128

	TCP_CONN_STATE_LINGER = 0b11011111	# TIME_WAIT; all but FIN_ACK_TX
# rfc793:
tcp_conn_state_official:	.byte 0
# states:
TCP_CONN_STATE_LISTEN		= 1	# wait conn req from remote			(wait for rx SYN)
TCP_CONN_STATE_SYN_SENT		= 2	# wait match conn req after tx conn req		(wait rx SYN after tx SYN)
TCP_CONN_STATE_SYN_RECEIVED	= 3	# wait conn req ack after rx AND tx conn req	(wait rx ACK for tx SYN after rx AND tx SYN)
TCP_CONN_STATE_ESTABLISHED	= 4	# open connection, normal
TCP_CONN_STATE_FIN_WAIT_1	= 5	# wait rx (fin | ack for tx fin)		(wait rx FIN, or, wait rx ACK on tx FIN) # we sent FIN, but haven't received any yet
TCP_CONN_STATE_FIN_WAIT_2	= 6	# wait rx fin					(wait rx FIN)
TCP_CONN_STATE_CLOSE_WAIT	= 7	# wait local close command from 'local user'	# we received FIN, haven't sent FIN yet
TCP_CONN_STATE_CLOSING		= 8	# wait rx ack for tx fin			(wait rx ACK on tx FIN)
TCP_CONN_STATE_LAST_ACK		= 9	# wait rx ack for tx fin			(wait rx ACK on tx FIN including ACK on its tx FIN)
TCP_CONN_STATE_TIME_WAIT	= 10	# delay ensure remote rx ack for rx fin		(wait until remote has rx ACK our tx ACK on its tx FIN)
TCP_CONN_STATE_CLOSED		= 11	# fictional: no conn state

#
# So,
#
# ESTABLISHED -----(tx FIN)-----> FIN_WAIT_1  --(rx ACK for FIN)--> FIN_WAIT_2 --(rx FIN,tx ACK)--> TIME_WAIT --(delay 2MSL)-->CLOSED
# ESTBALISHED -----(tx FIN)-----> FIN_WAIT_1  --(rx FIN,tx ACK)---> CLOSING    --(rx ACK of FIN)--> TIME_WAIT --(delay 2MSL)-->CLOSED
# ESTABLISHED -(rx FIN, tx ACK)-> CLOSE_WAIT  --(tx FIN)----------> LAST_ACK   --(rx ACK of FIN)------------------------------> CLOSED

TCP_MSL = 2 * 60	# maximum segment lifetime in seconds (2 minutes)

###.....?
# S: LISTEN->SYN_RECEIVED->ESTABLISHED
# C: SYN_SENT->ESTABLISHED

#
# events:
# * user calls		OPEN, SEND, RECEIVE, CLOSE, ABORT, STATUS
# * incoming segments	SYN, ACK, RST, FIN
# * timeouts
#
# client:
# active OPEN -> tx SYN -> {SYN_SENT}
#
# server:
# passive OPEN   -> {LISTEN}
# {LISTEN}       -> rx SYN    / tx SYN,ACK -> {SYN_RECEIVED}
# {LISTEN}       -> user SEND / tx SYN     -> {SYN_SENT}
# - reset event:
# {SYN_SENT}     -> rx RST -> {LISTEN}
# {SYN_RECEIVED} -> rx RST -> {LISTEN}
#
# common:
# {SYN_SENT}     -> rx SYN,ACK/tx ACK -> {ESTABLISHED}
# {SYN_SENT}     -> rx SYN    /tx ACK -> {SYN_RECEIVED} -> rx ACK -> {ESTABLSHD}
# {SYN_RECEIVED} -> CLOSE/tx FIN  -> {FIN_WAIT_1}
# {ESTABLISHED}  -> CLOSE/tx FIN  -> {FIN_WAIT_1}
# {ESTABLISHED}  -> rx FIN/tx ACK -> {CLOSE_WAIT} -> CLOSE/tx FIN -> {LAST_ACK}
# {LAST_ACK}     -> rx ACK -> {CLOSED}
# {FIN_WAIT_1}   -> rx ACK  -> {FIN_WAIT_2}
# {FIN_WAIT_1}   -> rx FIN/tx ACK -> {CLOSING} -> rx ACK -> {TIME_WAIT}
# {FIN_WAIT_2}   -> rx FIN/tx ACK -> {TIME_WAIT}
# {TIME_WAIT}    -> timeout 2MSL -> {CLOSED}
# - reset event: abort
# {ESTABLISHED}  -> rx RST -> {CLOSED}, report error
# {FIN_WAIT_1}   -> rx RST -> {CLOSED}, report error
# {FIN_WAIT_2}   -> rx RST -> {CLOSED}, report error
# {CLOSE_WAIT}   -> rx RST -> {CLOSED}, report error
# {CLOSING}      -> rx RST -> {CLOSED}, report error
# {LAST_ACK}     -> rx RST -> {CLOSED}, report error
# {TIME_WAIT}    -> rx RST -> {CLOSED}, report error
#
# Connection state categories:
# - nonexistent: CLOSED
# - non-synchronized: LISTEN, SYN_SENT, SYN_RECEIVED
# - synchronized: ESTABLISHED, FIN_WAIT_1, FIN_WAIT_2, CLOSE_WAIT, CLOSING,
#    LAST_ACK, TIME_WAIT.
#
# RST: sent when unacceptable packet is received.
# Ignored here is precedence levels, security level/compartment for the
# connection as this is not part of the core (minimal) TCP packet.
#
# Basic reasons to send RST depending on connection state:
# - nonexistent: something is received.
# - non-synchronized: something is ACKed which is not sent
# In the following case:
# - synchronized: out-of-window seq or unacceptable ack_nr
# only an empty ACK is sent with current send seq_nr and ack_nr indicating next
# expected sequence number.
#
# In all the above cases, the connection does not change state.
# NOTE: RFC 4987 sect 2.2 states that upon sending a SYN+ACK
# response to a spoofed IP which responds with RST the connection
# control block can be immediately freed.
#
# rx ACK for out-of-window data
# {CLOSED}       -> rx !RST / tx RST -> {CLOSED}   (!RST means anything but RST)
# unsynchronised states:
# {LISTEN}       -> rx ?ACK / tx RST -> {LISTEN}   (?ACK means unacceptable ACK,
# {SYN_SENT}     -> rx ?ACK / tx RST -> {SYN_SENT}      for something not sent.)
# {SYN_RECEIVED} -> rx ?ACK / tx RST -> {SYN_RECEIVED}
#
# -------
#
# MSL: maximum segment lifetime (<4.55 hours, usually 2 minutes)
#
# ISN: initial sequence number: 4 microsecond clock: 4.55 hour cycle.
#
# ISS: initial send sequence nr - chosen by tx data.
# IRS: initial receive sequence nr - learned during 3way handshake.

.align 4
TCP_CONN_STRUCT_SIZE = .  # 1*2+ 2*2 + 4*20 = 86 bytes
.data SECTION_DATA_BSS
tcp_connections: .long 0	# volatile array
.text32
tcp_conn_print_state_$:
	PRINTFLAG dl, 1, "SYN_RX "
	PRINTFLAG dl, 2, "SYN_ACK_TX "
	PRINTFLAG dl, 4, "SYN_TX "
	PRINTFLAG dl, 8, "SYN_ACK_RX "
	PRINTFLAG dl, 16, "FIN_RX "
	PRINTFLAG dl, 32, "FIN_ACK_TX "
	PRINTFLAG dl, 64, "FIN_TX "
	PRINTFLAG dl, 128, "FIN_ACK_RX "
	ret

tcp_conn_print_state$:
	push	edx
	mov	edx, esi
	call	printbin8
	pop	edx
	ret

tcp_conn_print_state_official$:
	.data
	tcp_conn_states_official$:
	STRINGPTR "<unknown>" # 0, undefined/uninitialized/new
	STRINGPTR "LISTEN" #	= 1	# wait conn req from remote
	STRINGPTR "SYN_SENT" #	= 2	# wait match conn req after tx conn req
	STRINGPTR "SYN_RECEIVED" #= 3	# wait conn req ack after rx/tx conn req
	STRINGPTR "ESTABLISHED" #= 4	# open connection, normal
	STRINGPTR "FIN_WAIT_1" #= 5	# wait rx (fin | ack for tx fin)
	STRINGPTR "FIN_WAIT_2" #= 6	# wait rx fin
	STRINGPTR "CLOSE_WAIT" #= 7	# wait local close command
	STRINGPTR "CLOSING" #	= 8	# wait rx ack for tx fin
	STRINGPTR "LAST_ACK" #	= 9	# wait rx ack for tx fin
	STRINGPTR "TIME_WAIT" #= 10	# delay ensure remote rx ack for rx fin
	STRINGPTR "CLOSED" #	= 11	# fictional: no conn state
	.text32
	cmp	esi, TCP_CONN_STATE_CLOSED + 1
	jb	0f
	xor	esi, esi
0:	mov	esi, [tcp_conn_states_official$ + esi * 4]
	call	print
	ret


# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# out: eax = tcp_conn array index (add volatile [tcp_connections])
# out: CF
net_tcp_conn_get:
	MUTEX_SPINLOCK TCP_CONN
	push_	ebx ecx edx
	mov	ebx, [edx + ipv4_src]
	mov	ecx, [esi + tcp_sport]
	rol	ecx, 16
	ARRAY_LOOP [tcp_connections], TCP_CONN_STRUCT_SIZE, edx, eax, 9f
	cmp	ecx, [edx + eax + tcp_conn_local_port]
	jnz	1f
	cmp	ebx, [edx + eax + tcp_conn_remote_addr]
	jz	0f
1:	ARRAY_ENDL
9:	stc
0:	MUTEX_UNLOCK TCP_CONN
	pop_	edx ecx ebx
	ret

# in: eax = remote ipv4
# in: edx = (remote port << 16) | (local port)
# in: ebx = local ipv4
# in: edi = handler
# out: eax = tcp_conn index
# out: CF
net_tcp_conn_newentry:
	MUTEX_SPINLOCK TCP_CONN
	push_	ecx edi edx eax

	call	get_time_ms
	mov	edi, eax
	sub	edi, TCP_CONN_REUSE_TIMEOUT
	jns	1f
	xor	edi, edi
1:

	# find free entry (use status flag)
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, eax, edx, 9f
	cmp	byte ptr [eax + edx + tcp_conn_state], -1
	jz	1f
	cmp	byte ptr [eax + edx + tcp_conn_state], TCP_CONN_STATE_LINGER
	jnz	2f
	cmp	edi, [eax + edx + tcp_conn_timestamp]
	jnb	1f
2:	ARRAY_ENDL

9:
	.if NET_TCP_DEBUG
		DEBUG, "allocating TCP conn entry"
	.endif
	ARRAY_NEWENTRY [tcp_connections], TCP_CONN_STRUCT_SIZE, 4, 9f
1:	
	add	eax, edx	# eax = abs conn ptr
	xchg	edx, [esp]	# [esp]=eax retval; edx = ipv4

	movb	[eax + tcp_conn_state], 0
	movb	[eax + tcp_conn_state_official], 0
	mov	[eax + tcp_conn_sock], dword ptr -1
	mov	edi, [esp + 8]
	mov	[eax + tcp_conn_handler], edi

	mov	[eax + tcp_conn_remote_addr], edx
	mov	[eax + tcp_conn_local_addr], ebx

	mov	edx, [esp + 4]
	bswap	edx
	mov	[eax + tcp_conn_local_port], edx

	mov	[eax + tcp_conn_local_seq], dword ptr 0x1337c0de	# for wireshark rel seq calc
	mov	[eax + tcp_conn_remote_seq], dword ptr 0
	mov	[eax + tcp_conn_local_seq_ack], dword ptr 0
	mov	[eax + tcp_conn_remote_seq_ack], dword ptr 0

	# allocate buffers
	xchg	edx, eax
	cmp	dword ptr [edx + tcp_conn_send_buf], 0
	jnz	1f
	mov	eax, TCP_CONN_BUFFER_SIZE
	call	mallocz
	jc	91f

	mov	[edx + tcp_conn_send_buf], eax
	mov	[edx + tcp_conn_send_buf_size], dword ptr TCP_CONN_BUFFER_SIZE
1:	mov	[edx + tcp_conn_send_buf_start], dword ptr 0
	mov	[edx + tcp_conn_send_buf_len], dword ptr 0

	# allocate receive buffer
	cmp	dword ptr [edx + tcp_conn_recv_buf], 0
	jnz	1f
	mov	eax, TCP_CONN_BUFFER_SIZE
	call	mallocz
	jc	91f

	mov	[edx + tcp_conn_recv_buf], eax
	mov	[edx + tcp_conn_recv_buf_size], dword ptr TCP_CONN_BUFFER_SIZE
1:	mov	[edx + tcp_conn_recv_buf_start], dword ptr 0
	mov	[edx + tcp_conn_recv_buf_len], dword ptr 0

9:	pop_	eax edx edi ecx
	MUTEX_UNLOCK TCP_CONN
	ret

91:	printlnc 4, "tcp: can't allocate buffers"
	stc
	jmp	9b

# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: ecx = tcp frame len
# in: ebx = socket (or -1)
# in: edi = handler [unrelocated]
# out: eax = tcp_conn array index
# out: CF = 1: out of memory
net_tcp_conn_newentry_from_packet:
	push_	edx ebx
	mov	eax, [edx + ipv4_src] # in: eax = remote ipv4
	mov	ebx, [edx + ipv4_dst] # in: ebx = local ipv4
	mov	edx, [esi + tcp_sport]
	bswap	edx
	ror	edx, 16 # in: edx = (remote port << 16) | (local port)
	call	net_tcp_conn_newentry # out: eax = tcp_conn index
	pop_	ebx edx
	ret

# in: eax = tcp_conn array index
# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: ecx = tcp frame len (incl header)
# (out: CF = undefined)
net_tcp_conn_update:
	MUTEX_SPINLOCK TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "tcp_conn update"
	.endif

	push	eax
	push	edx
	push	ebx

	add	eax, [tcp_connections]

	mov	ebx, eax
	call	get_time_ms
	xchg	eax, ebx
	mov	[eax + tcp_conn_timestamp], ebx

	mov	ebx, [esi + tcp_seq]
	bswap	ebx
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_FIN
	jz	1f
	inc	ebx
	# for now ignore whether we already have RXed a FIN and if we have,
	# assume the tcp_seq + FIN is the same as before.
	or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX
	mov	[eax + tcp_conn_rx_syn_remote_seq], ebx
1:
	mov	[eax + tcp_conn_remote_seq], ebx
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "seq"
		DEBUG_DWORD ebx
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	0f
	mov	ebx, [esi + tcp_ack_nr]
	bswap	ebx
	mov	[eax + tcp_conn_local_seq_ack], ebx
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "ack"
		DEBUG_DWORD ebx
	.endif
0:	clc
	pop	ebx
	pop	edx
	pop	eax
	MUTEX_UNLOCK TCP_CONN
	ret


net_tcp_conn_list:
	MUTEX_SPINLOCK TCP_CONN
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, esi, ebx, 9f
	printc	11, "tcp/ip "

	call	net_tcp_conn_print$

	ARRAY_ENDL
9:	MUTEX_UNLOCK TCP_CONN
	ret


# in: esi+ebx
net_tcp_conn_print$:
	push_	edx eax
	.macro TCP_PRINT_ADDR element
		mov	eax, [esi + ebx + \element\()_addr]
		call	net_print_ip
		printchar ':'
		movzx	edx, word ptr [esi + ebx + \element\()_addr]
		xchg	dl, dh
		call	printdec32
	.endm

	#call	screen_pos_mark
	#TCP_PRINT_ADDR tcp_conn_local
	mov	eax, [esi + ebx + tcp_conn_local_addr]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [esi + ebx + tcp_conn_local_port]
	xchg	dl, dh
	call	printdec32

	#mov	eax, 16 + 5 + 3
	#call	print_spaces
	call	printspace

	#call	screen_pos_mark
	#TCP_PRINT_ADDR tcp_conn_remote
	mov	eax, [esi + ebx + tcp_conn_remote_addr]
	call	net_print_ip
	printchar_ ':'
	movzx	edx, word ptr [esi + ebx + tcp_conn_remote_port]
	xchg	dl, dh
	call	printdec32
	#mov	eax, 16 + 5 + 3 + 2
	#call	print_spaces
	call	printspace

	push	esi
	movzx	esi, byte ptr [esi + ebx + tcp_conn_state]
	call	tcp_conn_print_state$
	movzx	esi, byte ptr [esi + ebx + tcp_conn_state]
	call	tcp_conn_print_state_official$
	pop	esi

	print	" last comm: "
	call	get_time_ms
	mov	edx, eax
	sub	edx, [esi + ebx + tcp_conn_timestamp]
	call	printdec32
	print	" ms ago"

	cmp	[esi + ebx + tcp_conn_send_buf], dword ptr 0
	jz	1f
	printc 12, " B"
1:

	call	newline

	.if NET_TCP_DEBUG > 2
	cmp	dword ptr [esi + ebx + tcp_conn_send_buf], 0
	jz	1f
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf],"tx buf"
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf_start],"start"
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf_len],"len"
		call	newline
	1:
	.endif

	call	printspace

	printc 13, "local"
	printc 8 " seq "
	mov	edx, [esi + ebx + tcp_conn_local_seq]
	call	printhex8
	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_local_seq_ack]
	call	printhex8

	printc 13, " remote"
	.if 1
	mov	eax, [esi + ebx + tcp_conn_remote_seq_base]

	printc 8, " seq "
	mov	edx, [esi + ebx + tcp_conn_remote_seq]
	sub	edx, eax
	call	printhex8

	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_remote_seq_ack]
	sub	edx, eax
	call	printhex8

	.else

	printc 8, " seq "
	mov	edx, [esi + ebx + tcp_conn_remote_seq]
	call	printhex8
	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_remote_seq_ack]
	call	printhex8

	printc 8, " base "
	mov	edx, [esi + ebx + tcp_conn_remote_seq_base]
	call	printhex8
	.endif

#	printc 14, " hndlr "
#	mov	edx, [esi + ebx + tcp_conn_handler]
#	call	printhex8

	call	newline

	pop_	eax edx
	ret

# out: ax
net_tcp_port_get:
	.data
	TCP_FIRST_PORT = 48000
	tcp_port_counter: .word TCP_FIRST_PORT
	.text32
	mov	ax, [tcp_port_counter]

	cmp	ax, TCP_FIRST_PORT
	jnz	1f

########
	push	ecx
	xor	ecx, ecx
	# initial setup
2:	xor	ax, [clock_ms]
	cmp	ax, TCP_FIRST_PORT
	jnb	2f
	inc	ecx
	rol	ax, 3
	xor	ax, 0x33aa
	jmp	2b
2:
	cmp	ax, 0xff00
	jb	2f
	sub	ax, 0x00ff
2:
.if NET_TCP_DEBUG
	DEBUG_DWORD ecx, "initial port iter count"
	DEBUG_WORD ax, "initial port"
.endif
	pop	ecx

########
1:	push	eax
	inc	ax
	cmp	ax, 0xff00
	jb	0f
	mov	ax, TCP_FIRST_PORT
0:	mov	[tcp_port_counter], ax
	pop	eax
	ret



TCP_DEBUG_COL_RX = 0x89
TCP_DEBUG_COL_TX = 0x8d
TCP_DEBUG_COL    = 0x83
TCP_DEBUG_COL2   = 0x82
TCP_DEBUG_COL3   = 0x84

.macro TCP_DEBUG_CONN
	push	eax
	print	"tcp["
	push	eax
	call	_s_printdec32
	print	"] "
	pop	eax
.endm

# PRECONDITION: [tcp_connections] locked
# in: eax = tcp_conn idx
.macro TCP_DEBUG_CONN_STATE
	cmp	eax, -1
	jz	9990f
	push	edx
	push	eax
	push	esi
	pushcolor 8

	add	eax, [tcp_connections]
	mov	dl, byte ptr [eax + tcp_conn_state]
	call	printbin8
	printspace
	movzx	esi, byte ptr [eax + tcp_conn_state_official]
	call	tcp_conn_print_state_official$
	printspace

	color TCP_DEBUG_COL_TX
	mov	edx, [eax + tcp_conn_local_seq]
	sub	edx, [eax + tcp_conn_local_seq_base]
	call	printdec32
	printspace
	mov	edx, [eax + tcp_conn_local_seq_ack]
	sub	edx, [eax + tcp_conn_local_seq_base]
	call	printdec32
	printspace


	color TCP_DEBUG_COL_RX
	mov	edx, [eax + tcp_conn_remote_seq]
	sub	edx, [eax + tcp_conn_remote_seq_base]
	call	printdec32
	printspace
	mov	edx, [eax + tcp_conn_remote_seq_ack]
	sub	edx, [eax + tcp_conn_remote_seq_base]
	call	printdec32
	printspace

	popcolor
	pop	esi
	pop	eax
	pop	edx
9990:
.endm

.macro TCP_DEBUG_REQUEST
	pushcolor TCP_DEBUG_COL_RX
	TCP_DEBUG_CONN
	print "["
	color	TCP_DEBUG_COL2
	push	edx
	movzx	edx, word ptr [esi + tcp_sport]
	xchg	dl, dh
	call	printdec32
	color	TCP_DEBUG_COL_RX
	print "->"
	color	TCP_DEBUG_COL2
	movzx	edx, word ptr [esi + tcp_dport]
	xchg	dl, dh
	call	printdec32
	pop	edx
	color	TCP_DEBUG_COL_RX
	print	"]: Rx ["
	push	eax
	mov	ax, [esi + tcp_flags]
	xchg	al, ah
	color	TCP_DEBUG_COL2
	TCP_DEBUG_FLAGS ax
	pop	eax
	printc TCP_DEBUG_COL_RX "] "
	popcolor
	TCP_DEBUG_CONN_STATE
.endm

.macro TCP_DEBUG_RESPONSE
	pushcolor TCP_DEBUG_COL_TX
	TCP_DEBUG_CONN
	print "["

	push	edx
	color	TCP_DEBUG_COL2
	movzx	edx, word ptr [edi + tcp_sport]
	xchg	dl, dh
	call	printdec32
	color	TCP_DEBUG_COL_TX
	print "->"
	color	TCP_DEBUG_COL2
	movzx	edx, word ptr [edi + tcp_dport]
	xchg	dl, dh
	call	printdec32
	pop	edx
	color	TCP_DEBUG_COL_TX
	print	"]: Tx ["

	push	eax
	mov	ax, [edi + tcp_flags]
	xchg	al, ah
	color	TCP_DEBUG_COL2
	TCP_DEBUG_FLAGS ax
	pop	eax

	printc TCP_DEBUG_COL_TX "] "
	popcolor
	TCP_DEBUG_CONN_STATE
.endm


# in: eax = ipv4
# in: dx = port
# out: eax = tcp_conn handle
net_ipv4_tcp_connect:
	push_	ebx edi

	push	edx
	call	net_route_get	# in: eax; out: ebx=nic, edx=gw
	pop	edx
	jc	9f

	push	eax
	call	nic_get_ipv4
	mov	ebx, eax

	call	net_tcp_port_get	# out: ax
	and	edx, 0xffff
	shl	eax, 16
	or	edx, eax
	pop	eax
	# eax = remote ip
	# ebx = local ip
	# edx = [remote port][local port]
	mov	edi, offset tcp_rx_sock
	call	net_tcp_conn_newentry	# out: eax = tcp_conn handle
	jc	9f

	pushad
	# send a SYN
	# in: eax = tcp_conn array index
	# in: dl = TCP flags (FIN,PSH)
	# in: dh = 0: use own buffer; 1: esi has room for header before it
	mov	dx, TCP_FLAG_SYN
	# in: esi = payload
	# in: ecx = payload len
	xor	ecx, ecx
	call	net_tcp_send
	popad
	clc

9:	pop_	edi ebx
	ret

# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_ipv4_tcp_handle:
	# firewall
	call	net_tcp_conn_get
	jc	0f

	.if NET_TCP_DEBUG
		TCP_DEBUG_REQUEST
	.endif

	# known connection
	call	net_tcp_conn_update
	call	net_tcp_handle	# in: eax=tcp_conn idx, ebx=ip, esi=tcp,ecx=len
	ret


0:	# firewall: new connection
	.if NET_TCP_DEBUG
		mov	eax, -1
		TCP_DEBUG_REQUEST
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	8f # its not a new or known connection

	# 1f: return; 2f, 3f: print message.
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jnz	2f # ACK must not be set on initial SYN.

	cmp	[esi + tcp_ack_nr], dword ptr 0
	jnz	3f	# ACK nr must not be set on initial SYN

	.if NET_TCP_DEBUG
	.if 0	# already printed in TCP_DEBUG_REQUEST
		pushcolor TCP_DEBUG_COL_RX
		print	"tcp: Rx SYN "
		color	TCP_DEBUG_COL2
		push	edx
		movzx	edx, word ptr [esi + tcp_dport]
		xchg	dl, dh
		call	printdec32
		pop	edx
		call	printspace
		popcolor
	.endif
	.endif

	# firewall / services:
	mov	eax, [edx + ipv4_dst]
	push	edx
	movzx	edx, word ptr [esi + tcp_dport]
	xchg	dl, dh
	or	edx, IP_PROTOCOL_TCP << 16	# XXX TODO: also test for SOCK_LISTEN
	call	net_socket_find
	mov	ebx, edx
	pop	edx
	jc	9f
	mov	edi, offset tcp_rx_sock

	# firewall / unroutable addresses
	#
	# (RFC 2872 describes the problem as resources being allocated
	#  for receiving a SYN, and sending a SYN+ACK to a spoofed/unroutable
	#  address, never getting a response, tying up resources until timeout.)
	#
	# See ipv4.s, the net_route_get check.


	# SYN Flooding protection
	# Several HTTP SYN floods have been detected over the last weeks,
	# causing system instability.
	# Here we check how many TCP connections a remote host has to
	# the current port, and reset the connection if it is unreasonable.

	call	net_tcp_count_peer_connections	# in: edx = ipv4 frame, esi = tcp frame; out: eax = num conns
	cmp	eax, 10	# let's be generous
	jae	92f

	.if NET_TCP_DEBUG
		printlnc TCP_DEBUG_COL, "tcp: ACCEPT SYN"
	.endif
	call	net_tcp_conn_newentry_from_packet	# in: edx=ip fr, esi=tcp fr, edi=handler; out: eax tcp conn idx
	jc	9f	# no more connections, send RST
	call	net_tcp_handle_syn$
	# update socket, call handler
	cmp	ebx, -1
	jz	1f
	mov	ecx, eax			# in: ecx = tcp conn idx
	mov	eax, ebx			# in: eax = local socket
	movzx	ebx, word ptr [esi + tcp_sport]	# in: ebx = peer port
	xchg	bl, bh
	mov	edx, [edx + ipv4_src]		# in: edx = peer ip
#	MUTEX_SPINLOCK TCP_CONN
	call	net_sock_deliver_accept		# out: edx = peer sock idx
	# the deliver may trigger an IRQ due to the socket user sending a
	# packet, however, the tcp_conn_sock field is only used on receiving
	# packets, which are queued.
#	mov	eax, [tcp_connections]
#	mov	[eax + ecx + tcp_conn_sock], edx
#	MUTEX_UNLOCK TCP_CONN

1:	ret

2:	#printc 4, "portscan detected: SYN+ACK"
	ret
3:	printc 4, "portscan detected: SYN and ACK!=0 from "
	push	eax
	mov	eax, [edx + ipv4_src]
	call	net_print_ipv4
	pop	eax
	call	newline
	ret

91:	# DROP
	.if 1#NET_TCP_DEBUG
		printc 0x8c, "tcp: DROP SYN: no route"
	.endif
	jmp	1f

92:	# DROP (1f) or REJECT (9f)
	.if 1
		printc 0x8c, "tcp: ";
		mov	eax, [edx + ipv4_src]
		call	net_print_ip
		printc 0x8c, ": DROP SYN: flood"

		.data
		.global tcp_synflood_dropcount
		.global tcp_synflood_lastdrop
		tcp_synflood_dropcount: .long 0
		tcp_synflood_lastdrop: .long 0
		.text32
		pushd	[clock]
		popd	[tcp_synflood_lastdrop]
		incd	[tcp_synflood_dropcount]
	.endif
	jmp	1f	# DROP

	#
8:	# unknown connection, not SYN
	.if NET_TCP_DEBUG
		TCP_DEBUG_REQUEST
		printc TCP_DEBUG_COL3, "tcp: unknown connection"
	.endif

.if NET_TCP_RESPOND_UNK_RST
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_RST
	jnz	1f
	jmp	2f
.else
	jmp	1f
.endif

9:

.if NET_TCP_RESPOND_UNK_RST
	.if 1#NET_TCP_DEBUG
		printc 0x8c, "tcp: REJECT SYN: no service"
	.endif

	mov	eax, -1	# nonexistent connection
2:	call	net_tcp_tx_rst$
.endif

1:;	.if NET_TCP_DEBUG
		call	net_print_ip_pair
		call	newline

		call	net_ipv4_tcp_print
	.endif
	ret


# in: edx = ipv4 frame
# in: esi = tcp frame
# out: eax = num conns
net_tcp_count_peer_connections:
	MUTEX_SPINLOCK TCP_CONN
	xor	eax, eax	# count
	push_	edi ebx ecx edx
	mov	ecx, [edx + ipv4_src]	# peer ip
	movzx	edx, word ptr [esi + tcp_dport]	# local port
	#xchg	dl, dh	# this must indeed NOT be done!

	.if 0
		DEBUG "CHECK peer conns for "
		push	eax
		mov	eax, ecx
		call	net_print_ipv4
		printchar_ ':'
		call	printdec32
		pop	eax
	.endif

	ARRAY_LOOP      [tcp_connections], TCP_CONN_STRUCT_SIZE, edi, ebx, 9f
	cmpd	[edi + ebx + tcp_conn_state], -1	# do not count reusable entries
	jz	1f
	cmp	ecx, [edi + ebx + tcp_conn_remote_addr]
	jnz	1f
	cmp	dx, [edi + ebx + tcp_conn_local_port]
	jnz	1f
	inc	eax
1:;	ARRAY_ENDL
9:      pop_	edx ecx ebx edi
	MUTEX_UNLOCK TCP_CONN
	.if 0
		DEBUG_DWORD eax, "#"
	.endif
	ret
	
# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
# (out: CF = undefined)
net_tcp_handle:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN
	.if NET_TCP_DEBUG
		printc	TCP_DEBUG_COL_RX, "<"
	.endif

### SYN
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	0f
	.if NET_TCP_DEBUG
		# this is false on locally initiated connections
		printc	TCP_DEBUG_COL_RX, "dup SYN"
	.endif
0:


### ACK
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "ACK "
	.endif
	push	eax
		push	edx
	call	net_tcp_conn_update_ack
		pop	edx
	cmp	eax, -1
	pop	eax
#	jz	9f	# received final ACK on FIN - connection closed.
0:

### RST
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_RST
	jz	0f
	# mark connection as free, for now
	DEBUG "TCP rx RST"; push eax; mov eax, [esi - IPV4_HEADER_SIZE + ipv4_src]; call net_print_ipv4; pop eax;
	MUTEX_SPINLOCK TCP_CONN
	push	eax
	add	eax, [tcp_connections]
	movb	[eax + tcp_conn_state], TCP_CONN_STATE_LINGER
	movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_CLOSED
	pop	eax
	MUTEX_UNLOCK TCP_CONN
	jmp	9f	# on RST, no other flags matter
0:

### FIN
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_FIN
	jz	0f

	# update connection state
	MUTEX_SPINLOCK TCP_CONN
	push	eax
	add	eax, [tcp_connections]

	test	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX
	.if NET_TCP_DEBUG
	jz	1f
		printc 11, "dup FIN "
	jmp	2f
	.else
	jnz	2f	# don't count the FIN again
	.endif

1:;	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "FIN "
	.endif
	# XXX TODO: inject FIN at proper window pos, i.e., verify all sequences received.
	#inc	dword ptr [eax + tcp_conn_remote_seq]
	#or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX

2:
	# byte not allowed - using word.
	bts	word ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_ACK_TX_SHIFT

		pushf
		jc	1f
		# we haven't sent a FIN
		# XXX TODO check official state 'ESTABLISHED'
		movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_CLOSE_WAIT

		jmp	2f
	1:	# we sent a FIN, so in FIN_WAIT_1;
		# if we also rx ACK on that fin, in FIN_WAIT_2;
		# we rx a FIN here,
		# so FIN_WAIT_1 -> CLOSING
		# and FIN_WAIT_2 ->TIME_WAIT
		# XXX TODO check official state 'FIN_WAIT_1'
		movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_CLOSING
	2:	popf


	pop	eax
	MUTEX_UNLOCK TCP_CONN

	.if NET_TCP_DEBUG
		call	newline
	.endif

	# indicate the connection is closed to the socket layer

		push_	eax edx
		mov	edx, IP_PROTOCOL_TCP << 16
		mov	dx, [eax + tcp_conn_remote_port]
		xchg	dl, dh
		mov	eax, [esi + ipv4_src]
		call	net_socket_find_remote
		jc	1f
		DEBUG_DWORD edx "TCP conn closed, notifying socket"
		call	net_socket_deliver_close
	1:	pop_	edx eax

	#ret # XXX might result in extra ACK
0:	
##
	# this is only meant for locally initiated connections,
	# on receiving a SYN+ACK to our SYN
	# since this method is not called unless the connection is known,
	# this test, which would match portscanners, would not be executed.
	push	edx
	mov	dl, [esi + tcp_flags + 1]
	and	dl, TCP_FLAG_SYN|TCP_FLAG_ACK
	cmp	dl, TCP_FLAG_SYN|TCP_FLAG_ACK
	pop	edx
	jnz	1f
	# got a SYN+ACK for a known connection: must be one we initiated.

	# update connection state (remote seq) for SYN flag
	MUTEX_SPINLOCK TCP_CONN
	push_	eax edx
	add	eax, [tcp_connections]

	mov	dl, [eax + tcp_conn_state]
	test	dl, TCP_CONN_STATE_SYN_RX
	jnz	2f	# already received a SYN
	mov	edx, [esi + tcp_seq]
	bswap	edx
	inc	edx
	.if NET_TCP_DEBUG > 1
		DEBUG_DWORD edx, "set remote_seq_base AGAIN"
	.endif
	mov	[eax + tcp_conn_remote_seq_base], edx	# XXX should be 1 less/ already set
	mov	[eax + tcp_conn_remote_seq], edx
2:	
	pop_	edx eax
	MUTEX_UNLOCK TCP_CONN

	.if NET_TCP_DEBUG
		printlnc	TCP_DEBUG_COL_RX, ">"
	.endif

1:
	call	net_tcp_handle_payload$

### PSH

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_PSH
	jz	0f
	.if NET_TCP_DEBUG
		printlnc TCP_DEBUG_COL_RX, "PSH >"
	.endif
	# flush the accumulated payload to the handler/socket
	call	net_tcp_handle_psh	# flushes buffer to socket
	#ret

###
0:
	# TODO: remove duplicate packets
	# TODO: check if there was data
	# TODO: re-send next packet in segment /RST if old ack

	# check if we need to send an ACK
	push	edx	# backup ipv4 frame
	mov	dl, [esi + tcp_flags + 1]
	test	dl, ~ TCP_FLAG_ACK	# check for SYN, PSH, FIN
	pop	edx
	jnz	1f			# need to send an ACK

	# check for payload:
	push	edx
	movzx	edx, byte ptr [esi + tcp_flags]	# headerlen
	shr	edx, 2
	and	dl, ~3
	neg	edx
	add	edx, ecx
	pop	edx
	jz	0f	# no payload
1:	call	net_tcp_send_ack
0:


9:
	.if NET_TCP_DEBUG
		printlnc	TCP_DEBUG_COL_RX, ">"
	.endif
	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# These two will point to the PSH data (accumulated)
# (out: CF = undefined)
## in: esi = tcp payload
## in: ecx = tcp payload len
tcp_rx_sock:
.if 1
	push	eax
	push	edx
	# in: eax = ip
	# in: edx = [proto] [port]
	# out: edx = socket
#	mov	eax, [edx + ipv4_dst]
#	movzx	edx, word ptr [esi + tcp_dport]
#	xchg	dl, dh
#printchar ':'
#call printdec32
	mov	edx, IP_PROTOCOL_TCP << 16
	MUTEX_SPINLOCK TCP_CONN
	add	eax, [tcp_connections]
	mov	dx, [eax + tcp_conn_remote_port]
	xchg	dl, dh
	mov	eax, [eax + tcp_conn_remote_addr]
	MUTEX_UNLOCK TCP_CONN
	call	net_socket_find_remote	# in: eax=ip, edx=proto/port; out: edx=socket idx
	jc	9f
#	DEBUG "Got socket"
	mov	eax, edx
	call	net_socket_write
0:	pop	edx
	pop	eax
	ret

9:	DEBUG "!! NO socket: ip=";
	call net_print_ip
	printchar ':'
	xchg	dl, dh	# XXX edx corrupted (PROTO/PORT)
	movzx	edx, dx
	call	printdec32
	call	newline;

	pop	edx	# ipv4 frame
	pop	eax	# tcp connection index
	pushad
	MUTEX_SPINLOCK TCP_CONN
	mov	esi, [tcp_connections]
	mov	ebx, eax	# conn idx
	call	net_tcp_conn_print$
	MUTEX_UNLOCK TCP_CONN
	popad	
	pushad
	mov	esi, edx	# ipv4 frame
	# in: esi = ipv4 frame
	# in: ecx = max frame len - we don't know anymore
	mov	ecx, 1536
	call	net_ipv4_print
	popad
	#DEBUG_DWORD edx,"proto|port"
	ret
.else

	MUTEX_SPINLOCK TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	add	eax, [tcp_connections]
	mov	eax, [eax + tcp_conn_sock]
	MUTEX_UNLOCK TCP_CONN
	call	net_socket_write
.endif
	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle_payload$:
	#check for oversized packets
	cmp	ecx, 1500
	jb	1f
	printc 4, "long tcp framelen: "
	push	ecx
	call	_s_printhex8
	printlnc 4, "; sending RST"
	call	net_ipv4_tcp_print
	# it's likely that the packet framelen is ok, 
	# as this is checked in the eth protocol handler.
	# todo: check if ip protocol handler checks payload length
	# if the packet is good, then there's a bug.
	jmp	net_tcp_tx_rst$
	# todo: buffer stuff, i.e., not acking
	# or closing connection

1:	push	ecx
	push	edx
	push	esi

	# get offset and length of payload
	movzx	edx, byte ptr [esi + tcp_flags]	# headerlen
	shr	edx, 2
	and	dl, ~3
	sub	ecx, edx
	jz	0f	# no payload
	add	esi, edx	# esi points to payload

	MUTEX_SPINLOCK TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	push	eax
	add	eax, [tcp_connections]
	add	[eax + tcp_conn_remote_seq], ecx

	.if NET_TCP_DEBUG > 2
		call newline
		DEBUG "rx payload",0xa0
		DEBUG_DWORD [eax+tcp_conn_recv_buf_start],"start",0xa0
		DEBUG_DWORD [eax+tcp_conn_recv_buf_len],"len",0xa0
	.endif
	push	esi
	push	edi
	push	ecx
	mov	edi, [eax + tcp_conn_recv_buf]
	add	edi, [eax + tcp_conn_recv_buf_start]
	add	edi, [eax + tcp_conn_recv_buf_len]
	rep	movsb
	pop	ecx
	pop	edi
	pop	esi
	add	[eax + tcp_conn_recv_buf_len], ecx
	.if NET_TCP_DEBUG > 2
		DEBUG_DWORD [eax+tcp_conn_recv_buf_len],"len",0xa0
		call newline
		push_ esi ecx
		11:	lodsb
			call	printchar
			loop	11b
			call	newline
		pop_ ecx esi
	.endif


	pop	eax
	MUTEX_UNLOCK TCP_CONN

0:	pop	esi
	pop	edx
	pop	ecx
	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# (out: CF = undefined)
net_tcp_handle_psh:
	push	ecx
	push	edx	# stackref
	push	esi
		# UNTESTED
		# in: eax = ip
		# in: edx = [proto] [port]
		# in: esi, ecx: packet
		#mov	dx, [esi + ipv4_protocol]
		#shl	edx, 16	# no port known yet
		#mov	eax, [esp + 4] # edx
		#mov	eax, [eax + ipv4_dst]
		#call	net_socket_deliver

	# call handler

	MUTEX_SPINLOCK TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	mov	edi, [tcp_connections]
	add	edi, eax
	mov	esi, [edi + tcp_conn_recv_buf]
	add	esi, [edi + tcp_conn_recv_buf_start]
	mov	ecx, [edi + tcp_conn_recv_buf_len]

	.if NET_TCP_DEBUG > 2
		call newline
		DEBUG "handle PSH", 0xb0
		DEBUG_DWORD [edi+tcp_conn_recv_buf_start],"start",0xb0
		DEBUG_DWORD [edi+tcp_conn_recv_buf_len],"len",0xb0
		call newline
	.endif

	mov	edi, [edi + tcp_conn_handler]
	MUTEX_UNLOCK TCP_CONN

or	edi, edi
jz	9f
cmp	edi, -1
jz	9f
	add	edi, [realsegflat]
	mov	edx, [esp + 4]	# edx: ipv4 frame
	pushad
	call	edi	# in: eax = tcp conn idx; edx=ipv4; esi=data; ecx=data len
	popad
	# the push has copied ALL data, so we clear the buffer.
	MUTEX_SPINLOCK TCP_CONN
	mov	edi, [tcp_connections]
	add	edi, eax
	sub	[edi + tcp_conn_recv_buf_len], ecx	# should be 0
	mov	[edi + tcp_conn_recv_buf_start], dword ptr 0
	MUTEX_UNLOCK TCP_CONN

0:	pop	esi
	pop	edx
	pop	ecx
	ret
9:	printlnc 4, "net_tcp_handle_psh: null handler"
	# eax = edi = 0; edx=tcp hlen=ok, ecx=0x75.
	pushad
	call	net_tcp_conn_list
	popad
	int	3
	jmp	0b

# in: eax = tcp connection index
# in: esi = tcp packet (with ACK flag set)
# out: eax = -1 if the ACK is for the FIN
# side-effect: send_buf freed.
# (out: CF = undefined)
net_tcp_conn_update_ack:
	MUTEX_SPINLOCK TCP_CONN
	push	edx
	push	eax	# STACKREF
	push	ebx
	add	eax, [tcp_connections]
	mov	ebx, [esi + tcp_ack_nr]
	bswap	ebx
	mov	[eax + tcp_conn_local_seq_ack], ebx	# XXX also done in net_tcp_conn_update

		# use the official states:
		pushad
		mov	bl, [eax + tcp_conn_state_official]
		movzx	esi, bl
		.if NET_TCP_DEBUG > 1
			DEBUG "update ACK"
			call	tcp_conn_print_state_official$
		.endif
		mov	esi, [esp + PUSHAD_ESI]
			# states:
			#TCP_CONN_STATE_LISTEN		= 1	# wait conn req from remote
			#TCP_CONN_STATE_SYN_SENT	= 2	# wait match conn req after tx conn req
			#TCP_CONN_STATE_SYN_RECEIVED	= 3	# wait conn req ack after rx/tx conn req
			#TCP_CONN_STATE_ESTABLISHED	= 4	# open connection, normal
			#TCP_CONN_STATE_FIN_WAIT_1	= 5	# wait rx (fin | ack for tx fin)
			#TCP_CONN_STATE_FIN_WAIT_2	= 6	# wait rx fin
			#TCP_CONN_STATE_CLOSE_WAIT	= 7	# wait local close command
			#TCP_CONN_STATE_CLOSING		= 8	# wait rx ack for tx fin
			#TCP_CONN_STATE_LAST_ACK	= 9	# wait rx ack for tx fin
			#TCP_CONN_STATE_TIME_WAIT	= 10	# delay ensure remote rx ack for rx fin
			#TCP_CONN_STATE_CLOSED		= 11	# fictional: no conn state
		cmp	bl, TCP_CONN_STATE_LISTEN
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_LISTEN todo"
		.endif
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_SYN_SENT	# client
		jnz	1f
		# fallthrough - identical (except server sends SYN+ACK, client only sends ACK this time)
	1:
		cmp	bl, TCP_CONN_STATE_SYN_RECEIVED	# server
		jnz	1f
		mov	edx, [esi + tcp_seq]
		bswap	edx
		sub	edx, [eax + tcp_conn_remote_seq_base]
		.if NET_TCP_DEBUG > 1
			printc 8, " remote seq "
			call	printdec32
			call	printspace
		.endif
		cmp	edx, 1
		jnz	2f
		# received ACK for rel seq 1, our SYN:
		movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_ESTABLISHED

	1:
		cmp	bl, TCP_CONN_STATE_ESTABLISHED
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_ESTABLISHED todo"
		.endif
		# either:
		# A) we send    a FIN: goto FIN_WAIT_1
		# B) we receive a FIN: goto CLOSE_WAIT
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_FIN_WAIT_1
		jnz	1f
		#DEBUG "CONN_STATE_CLOSE_FIN_WAIT_1 todo"
		# we sent a fin, but haven't received an ack or fin
		# so see if this ack is for our fin

		mov	edx, [esi + tcp_ack_nr]
		bswap	edx
		sub	edx, [eax + tcp_conn_local_seq_base]
		cmp	edx, [eax + tcp_conn_local_seq]	# once FIN sent, local seq won't change!
		jnz	3f
		.if NET_TCP_DEBUG > 1
			DEBUG "rx ACK for our FIN: FIN_WAIT_1->FIN_WAIT_2"
		.endif
		movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_FIN_WAIT_2
		jmp	2f
		3:
		# not ack for our TX fin;
		# if rx FIN then tx ACK and goto CLOSING
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_FIN_WAIT_2
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_CLOSE_FIN_WAIT_2 todo"
		.endif
		# this state only waits for rx FIN, then  tx ACK and -> TIME_WAIT -> CLOSED
		testb	[esi + tcp_flags + 1], TCP_FLAG_FIN
		jz	2f
		.if NET_TCP_DEBUG > 1
			DEBUG "FIN_WAIT_2 rx FIN/tx ACK(TODO)->TIME_WAIT"
		.endif
		movb	[esi + tcp_conn_state_official], TCP_CONN_STATE_TIME_WAIT
		jmp	2f

	1:
		cmp	bl, TCP_CONN_STATE_CLOSE_WAIT
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_CLOSE_WAIT todo"
		.endif
		# CLOSE_WAIT: we received a FIN (but haven't sent one)
		# Once we tx FIN goto LAST_ACK
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_CLOSING
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_CLOSING todo"
		.endif
		# we tx FIN but not rx ACK, and we rx FIN and tx ACK.
		# so we wait for ACK on our FIN:
		mov	edx, [esi + tcp_ack_nr]
		bswap	edx
		sub	edx, [eax + tcp_conn_local_seq_base]
		cmp	edx, [eax + tcp_conn_local_seq]	# once FIN sent, local seq won't change! guaranteed: FIN_WAIT_1 and later have tx FIN
		jnz	2f
		.if NET_TCP_DEBUG > 1
			DEBUG "rx ACK for our FIN: CLOSING->TIME_WAIT"
		.endif
		movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_TIME_WAIT
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_LAST_ACK
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_LAST_ACK todo"
		.endif
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_TIME_WAIT
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_TIME_WAIT todo"
		.endif
		jmp	2f
	1:
		cmp	bl, TCP_CONN_STATE_CLOSED
		jnz	1f
		.if NET_TCP_DEBUG > 1
			DEBUG "CONN_STATE_CLOSED todo"
		.endif
		jmp	2f
	1:
	2:	popad


	movzx	ebx, byte ptr [eax + tcp_conn_state]
	# see if ACK is for FIN
	test	bl, TCP_CONN_STATE_FIN_TX
	jz	1f
	.if NET_TCP_DEBUG > 1
		DEBUG "rx ACK; FIN sent;"
	.endif
	# see if we already received this ack
	test	bl, TCP_CONN_STATE_FIN_ACK_RX
	jnz	4f#1f
	mov	edx, [eax + tcp_conn_tx_fin_seq]
	bswap	edx
	cmp	edx, [esi + tcp_ack_nr]
	jnz	6f#1f	# ack is not for our tx fin
	.if NET_TCP_DEBUG > 1
		DEBUG "got ACK for FIN"
	.endif
	or	bh, TCP_CONN_STATE_FIN_ACK_RX
	# Connection closed now, free buffer:
	push	eax
	mov	eax, [eax + tcp_conn_send_buf]
	call	mfree
	pop	eax
	mov	[eax + tcp_conn_send_buf], dword ptr 0

	movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_CLOSED	# XXX

	test	bl, TCP_CONN_STATE_FIN_ACK_RX|TCP_CONN_STATE_FIN_ACK_TX
	jz	2f
	mov	[esp + 4], dword ptr -1	# return eax = -1
2:

1:	# ack is not for our tx fin since we didn't send a FIN
	jmp	5f;
4:	
	.if NET_TCP_DEBUG > 1
	DEBUG "dup ACK on FIN"
	.endif
	jmp	5f
6:	
	.if NET_TCP_DEBUG > 1
		DEBUG "ACK SEQ FIN mismatch"
	.endif
5:

########
	test	bl, TCP_CONN_STATE_SYN_TX
	jz	3f
	or	bh, TCP_CONN_STATE_SYN_ACK_RX
3:	or	[eax + tcp_conn_state], bh

	pop	ebx
	pop	eax
	pop	edx
	MUTEX_UNLOCK TCP_CONN
	ret


# in: eax = socket
net_tcp_send_ack:
	push_	edx ecx
	xor	dx, dx		# no flags (ACK automatic)
	xor	ecx, ecx	# no payload (esi doesn't need to be set)
	call	net_tcp_send
	pop_	ecx edx
	ret


# appends the data to the tcp connection's send buffer; on overflow,
# it flushes the buffer (sends it), and appends the remaining data.
# This is repeated until all the data has been transfered to the buffer.
# Upon return, the buffer may contain unsent data, which can be sent
# by calling net_tcp_sendbuf_flush.
#
# in: eax = tcp conn idx
# in: esi = data
# in: ecx = data len
# out: esi = start of data not put in buffer
# out: ecx = length of data not put in buffer
net_tcp_sendbuf:
	push	edi
	push	ebx
	push	edx
########
0:	MUTEX_SPINLOCK TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	mov	ebx, [tcp_connections]
	add	ebx, eax

	call	_append$	# out: esi,ecx updated.

	MUTEX_UNLOCK TCP_CONN
########
	clc
	jecxz	0f		# all data copied to buffer

	# data doesn't fit.
	mov	edx, ecx	# backup remaining data

	call	net_tcp_sendbuf_flush_partial$

	mov	ecx, edx
# due to jecxz above ecx can't be 0
#	or	ecx, ecx
#	jnz	0b	# go again
	jmp	0b

0:	pop	edx
	pop	ebx
	pop	edi
	ret

# PRECONDITION: TCP_CONN locked
# in: ebx = tcp_conn
# in: esi = data to append
# in: ecx = size of data to append
# out: ecx = remaining data to be appended
# out: esi = ptr to remaining data to be appended
_append$:
	# buf_start allows to put the eth/ip/tcp headers in the buffer to
	# avoid copying the data yet again.
	mov	edx, [ebx + tcp_conn_send_buf_start]
	add	edx, [ebx + tcp_conn_send_buf_len]
	# edx = offset where to append data.
	mov	edi, [ebx + tcp_conn_send_buf]
	add	edi, edx
#	sub	edx, [ebx + tcp_conn_send_buf_size]
##	sub	edx, 1536 - ETH_HEADER_SIZE-IPV4_HEADER_SIZE-TCP_HEADER_SIZE
	#sub	edx, ETH_HEADER_SIZE+IPV4_HEADER_SIZE+TCP_HEADER_SIZE

	# edi = end of data to send so far

	neg	edx
	add	edx, [ebx + tcp_conn_send_buf_size]
	# edx = remaining buffer length

	cmp	ecx, edx
	jb	1f	# it will fit; make edx(remaining)=0

	xchg	edx, ecx
	# ecx = data that can be copied
	# edx = total data
	sub	edx, ecx
	jmp	2f
	# edx = data that doesn't fit

1:	xor	edx, edx
	# ecx = data to copy into  buf
2:	# edx = data that won't fit in buf
	add	[ebx + tcp_conn_send_buf_len], ecx
	rep	movsb
	mov	ecx, edx
	ret

# uses tcp_conn_send_buf*
# in: eax = tcp conn idx
# effect: sends as much max-sized packets as are in the buffer,
# then compacts the buffer.
net_tcp_sendbuf_flush_partial$:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN

	push_	ebx ecx edx esi edi

0:	MUTEX_SPINLOCK TCP_CONN

	mov	ebx, [tcp_connections]
	add	ebx, eax

	mov	esi, [ebx + tcp_conn_send_buf]
	add	esi, [ebx + tcp_conn_send_buf_start]

	mov	edx, [ebx + tcp_conn_remote_mss]
	mov	ecx, [ebx + tcp_conn_send_buf_len]
	sub	ecx, edx
	js	1f	# packet shorter than mss
	mov	[ebx + tcp_conn_send_buf_len], ecx	# update remaining len
	mov	ecx, edx
	jz	3f	# packet equal to mss: 'rewind' buffer
	add	[ebx + tcp_conn_send_buf_start], ecx
	jmp	2f	# send the mss packet
3:	mov	[ebx + tcp_conn_send_buf_start], dword ptr 0
	jmp	2f	# send the mss packet


1:	# buf len < mss: compact buffer
	xor	ecx, ecx	# make sure ecx=0 in case we jz 2f
	xor	esi, esi
	xchg	esi, [ebx + tcp_conn_send_buf_start]
	or	esi, esi
	jz	2f	# buf already compacted
	mov	ecx, [ebx + tcp_conn_send_buf_len]
	mov	edi, [ebx + tcp_conn_send_buf]
	add	esi, edi
	mov	edx, ecx
	and	ecx, 3
	rep	movsb
	mov	ecx, edx
	shr	ecx, 2
	rep	movsd
2:	MUTEX_UNLOCK TCP_CONN

	jecxz	1f

	xor	dx, dx # no tcp flags
	call	net_tcp_send
	jmp	0b

1:	pop_	edi esi edx ecx ebx
	ret


# uses tcp_conn_send_buf*
# in: eax = tcp conn idx
net_tcp_sendbuf_flush:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN

	push	edx
	push	esi
	push	ecx
	push	ebx

0:	MUTEX_SPINLOCK TCP_CONN

	mov	ebx, [tcp_connections]
	add	ebx, eax

	mov	esi, [ebx + tcp_conn_send_buf]
	add	esi, [ebx + tcp_conn_send_buf_start]
	xor	ecx, ecx
	mov	edx, [ebx + tcp_conn_remote_mss]
	xchg	ecx, [ebx + tcp_conn_send_buf_len]
	cmp	ecx, edx
	jbe	1f
	sub	ecx, edx
	mov	[ebx + tcp_conn_send_buf_len], ecx
	mov	ecx, edx
	add	[ebx + tcp_conn_send_buf_start], ecx
	jmp	2f
1:	mov	[ebx + tcp_conn_send_buf_start], dword ptr 0
2:	MUTEX_UNLOCK TCP_CONN

	jecxz	1f
	mov	dx, TCP_FLAG_PSH # | 1 << 8	# nocopy
	call	net_tcp_send
	jmp	0b

1:	pop	ebx
	pop	ecx
	pop	esi
	pop	edx
	ret


# in: eax = tcp_conn_idx
net_tcp_fin:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN
	push	edx
	push	ecx
	xor	ecx, ecx
	mov	dx, TCP_FLAG_FIN
	call	net_tcp_send
	pop	ecx
	pop	edx
	ret


# in: eax = tcp_conn array index
# in: dl = TCP flags (FIN,PSH)
# in: dh = 0: use own buffer; 1: esi has room for header before it
# in: esi = payload
# in: ecx = payload len
# out; CF = 1: payload too large / can't get buffer / nic send fail
net_tcp_send:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN

	# XXX should use MSS
	cmp	ecx, 1536 - TCP_HEADER_SIZE - IPV4_HEADER_SIZE - ETH_HEADER_SIZE
	jb	0f
	printc	4, "tcp payload too large: "
	push	edx
	mov	edx, ecx
	call	printdec32
	printc	4, " caller: "
	mov	edx, [esp + 4]
	call	printhex8
	call	debug_printsymbol
	call	newline
	pop	edx
	stc
	ret
0:
	push	edi
	push	esi
	push	ebx
	push	eax
	push	ebp
	lea	ebp, [esp + 4]

	NET_BUFFER_GET
	jc	9f
	push	edi

	MUTEX_SPINLOCK TCP_CONN
	push	esi
	push	edx
	push	ecx
	push	eax
	add	eax, [tcp_connections]
	mov	eax, [eax + tcp_conn_remote_addr]
#	mov	eax, [edx + ipv4_src]
	mov	dx, IP_PROTOCOL_TCP
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	add	ecx, TCP_HEADER_SIZE
	call	net_ipv4_header_put # mod eax, esi, edi, ebx
	pop	eax
	pop	ecx
	pop	edx
	pop	esi

	# add tcp header
	push	edi
	push	ecx
	push	eax
	mov	ecx, (TCP_HEADER_SIZE) & 3
	xor	eax, eax
	rep	stosb
	mov	ecx, (TCP_HEADER_SIZE) >> 2
	rep	stosd
	pop	eax
	pop	ecx
	pop	edi

	# copy connection state
	add	eax, [tcp_connections]
	push	ebx

	mov	ebx, [eax + tcp_conn_local_port]
	mov	[edi + tcp_sport], ebx

	mov	ebx, [eax + tcp_conn_local_seq]
	bswap	ebx
	mov	[edi + tcp_seq], ebx
	add	[eax + tcp_conn_local_seq], ecx

	mov	ebx, [eax + tcp_conn_remote_seq]
	mov	[eax + tcp_conn_remote_seq_ack], ebx	# we ack their seq
	bswap	ebx
	mov	[edi + tcp_ack_nr], ebx # dword ptr 0	# maybe ack
	pop	ebx

	# update state if FIN
	test 	dl, TCP_FLAG_FIN
	jz	1f
	or	[eax + tcp_conn_state], byte ptr TCP_CONN_STATE_FIN_TX
	inc	dword ptr [eax + tcp_conn_local_seq]	# count FIN as octet in next seq
	push	ebx	# mark the FIN sequence
	mov	ebx, [eax + tcp_conn_local_seq]
	mov	[eax + tcp_conn_tx_fin_seq], ebx
	pop	ebx
1:

	mov	ax, ((TCP_HEADER_SIZE/4)<<12)
	or	al, dl	# additional flags
	test	al, TCP_FLAG_SYN
	jnz	1f
	or	al, TCP_FLAG_ACK
1:	xchg	al, ah
	mov	[edi + tcp_flags], ax

	.if NET_TCP_DEBUG
		mov	eax, [ebp]	# tcp conn idx
		TCP_DEBUG_RESPONSE
		call	newline

		#pushcolor TCP_DEBUG_COL_TX
		#print "[Tx "
		#xchg	al, ah
		#TCP_DEBUG_FLAGS ax
		#print "]"
		#popcolor
	.endif

	movw	[edi + tcp_windowsize], ((TCP_CONN_BUFFER_SIZE&0xff)<<8)|(TCP_CONN_BUFFER_SIZE>>8) # word ptr 0x20

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0

	push	edx

	# copy payload, if any
	jecxz	0f
	push	esi
	push	edi
	push	ecx
	add	edi, TCP_HEADER_SIZE
	mov	edx, ecx
	and	ecx, 3
	rep	movsb
	mov	ecx, edx
	shr	ecx, 2
	rep	movsd
	pop	ecx
	pop	edi
	pop	esi
0:
	# calculate checksum

	mov	edx, [ebp]		# in: edx = ipv4 src, dst ptr
	add	edx, [tcp_connections]
	add	edx, offset tcp_conn_local_addr
	mov	esi, edi		# in: esi = tcp frame pointer
	add	ecx, TCP_HEADER_SIZE	# in: ecx = tcp frame len
	call	net_tcp_checksum

	pop	edx

	# packet is ready to be sent. Update tcp_conn first, since the
	# send-packet call is asynchronous, and it's response may be
	# handled before the connection state would be updated.

########
	# update flags
	mov	eax, [ebp]	# tcp_conn_idx
	add	eax, [tcp_connections]
	mov	dh, [eax + tcp_conn_state]

	# XXX should move
	cmp	dl, TCP_FLAG_SYN	# 
	jnz	1f
	or	dh, TCP_CONN_STATE_SYN_TX

		# record the SYN as 1 payload
		inc	dword ptr [eax + tcp_conn_local_seq]
		or	dh, TCP_CONN_STATE_SYN_TX
1:

	test	dl, TCP_FLAG_FIN
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_TX
1:	test	dh, TCP_CONN_STATE_FIN_RX
	jz	1f
	test	dl, TCP_FLAG_ACK
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_ACK_TX
1:	or	[eax + tcp_conn_state], dh
	MUTEX_UNLOCK TCP_CONN
########
	# send packet

	pop	esi
	add	ecx, edi	# add->mov ?
	sub	ecx, esi
	call	[ebx + nic_api_send]
	jc	9f
9:	pop	ebp
	pop	eax
	pop	ebx
	pop	esi
	pop	edi
	ret

# Sends a reset packet. Called when a packet is received that refers
# to a nonexistent connection.
#
# in: eax = tcp_conn array index, or -1 for nonexistent connection
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_tx_rst$:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	push	ebp
	push	eax
	mov	ebp, esp	# [ebp] = tcp_conn idx
	push	ecx
	push	edx
	push	esi
	push	edi

	NET_BUFFER_GET
	jc	9f
	push	edi	# remember packet start

	mov	eax, [edx + ipv4_src]
	mov	ecx, TCP_HEADER_SIZE
	push	edx
	push	esi
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	mov	dx, IP_PROTOCOL_TCP
	call	net_ipv4_header_put # mod eax, esi, edi
	pop	esi
	pop	edx
	jc	8f

	# add tcp header
	push	edi
	push	ecx
	xor	al, al
	rep	stosb
	pop	ecx
	pop	edi

	mov	eax, [esi + tcp_sport]
	rol	eax, 16
	mov	[edi + tcp_sport], eax

	# Calculate sequence number tcp_seq:
	# check connection state:
	cmp	dword ptr [ebp], -1
	jnz	3f

######### CLOSED:
	# from rfc793, added () logical interpretation:
	#
	# "(If the incoming segment has an ACK field, the reset takes its
	# sequence number from the ACK field of the segment, otherwise the
	# reset has sequence number zero) and the ACK field is set to the sum
	# of the sequence number and segment length of the incoming segment.
	# The connection remains in the CLOSED state."
	#
	# without the (), the ACK field response is not specified for an
	# incoming SEG with an ACK field.

	# SEG.ACK ? seq = SEG.ack_nr, ack_nr = <unspecified>
	#         : seq = 0,          ack_nr = SEG.SEQ + SEG.LEN
	#
	# Interpretation:
	#
	# seq    = SEG.ACK ? SEG.ack_nr : 0
	# ack_nr = SEG.SEQ + SEG.LEN

	# calculate tcp_seq:
	xor	eax, eax		# seq if there is no ACK flag
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	1f
	mov	eax, [esi + tcp_ack_nr]	# ACK present
1:	mov	[edi + tcp_seq], eax

	# calculate ack_nr: (standard)
	mov	eax, [esi + tcp_seq]
	bswap	eax
	# add segment len
	# temporary: assume SYN sent:
	inc	eax
	bswap	eax
	mov	[edi + tcp_ack_nr], eax
########
#	jmp	4f
3:	# TODO: connection exists: so far no valid reason to RST found;
	# if sequence numbers mismatch, an ACK with proper sequence numbers
	# is to be sent - in another method preferrably.
########
4:	mov	ax, TCP_FLAG_RST | TCP_FLAG_ACK | ((TCP_HEADER_SIZE/4)<<12)
	xchg	al, ah
	mov	[edi + tcp_flags], ax

	mov	[edi + tcp_windowsize], word ptr 0 # RST: no receive window
	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0

	# calculate checksum
	mov	esi, edi		# in: esi = tcp frame pointer
	mov	ecx, TCP_HEADER_SIZE	# in: ecx = tcp frame len
	add	edx, offset ipv4_src	# in: edx = ipv4 src,dst

	.if NET_TCP_DEBUG
		push eax
		DEBUG "RST<"
		mov eax, [edx]
		call net_print_ip
		call printspace
		mov eax, [edx+4]
		call net_print_ip
		DEBUG ">"
		pop eax
	.endif

	call	net_tcp_checksum

	add	edi, TCP_HEADER_SIZE
	# send packet

	pop	esi
	NET_BUFFER_SEND

9:	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	pop	ebp
	ret
# error between NET_BUFFER_GET/push edi and pop esi/NET_BUFFER_SEND
8:	pop	edi
	jmp	9b



# precondition: the tcp_connection is new (i.e. TCP_CONN_STATE_LISTEN);
# this is not checked due to code flow enforcing it.
#
# in: eax = tcp_conn array index
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
# (out: CF = undefined)
net_tcp_handle_syn$:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN
	pushad
	push	ebp
	mov	ebp, esp
	push	eax			# [ebp - 4] = tcp conn idx
	pushd	NET_TCP_DEFAULT_MSS	# [ebp - 8] = remote MSS
	pushd	0			# [ebp -12] = remote WS ; unused.

# parse TCP options and set remote MSS
# in: esi, ecx = TCP frame
# out: [ebp - 8] = TCP MSS
	#call	net_tcp_parse_options$	# in: esi, ecx; out: 
	push_	esi ecx eax
	movzx	ecx, byte ptr [esi + tcp_flags]
	shr	cl, 4	# cl = hlen
	shl	cl, 2	# * dwords
	sub	ecx, offset tcp_options
	jz	1f	# no options
	lea	esi, [esi + tcp_options]
	xor	eax, eax
0:	lodsb
	cmp	al, TCP_OPT_END	# end of options (no len/data)
	jz	0f
	cmp	al, TCP_OPT_NOP
	jz	1f
	cmp	al, TCP_OPT_MSS
	jz	2f
	cmp	al, TCP_OPT_WS  #.byte 2, 4; .word winscale
	jz	3f
	cmp	al, TCP_OPT_SACKP
	jz	4f
	cmp	al, TCP_OPT_TSECHO
	jz	8f


	DEBUG_BYTE al, "TCP: unimplemented option"
	# unimplemented option: at least 2 bytes:opcode,len
	jecxz	0f	# TODO: warn: short option (require len field)
	lodsb	# load len
	sub	ecx, eax	# includes option code and len field
	jz	0f	# reached the end, done.
	jl	0f	# TODO: warn: short option
	lea	esi, [esi + eax - 2]	# len includes option+len fields
	jmp	1f	# continue parsing options

# options
8:	# TCP_OPT_TSECHO
	sub	ecx, 10
	jl	0f	# TODO: warn
	lodsb
	cmp	al, 10
	jnz	0f	# TODO: warn
	lodsd
	lodsd
	jmp	1f

4:	#TCP_OPT_SACKP
	sub	ecx, 2	# opcode, len field
	jl	0f	# TODO: warn
	lodsb
	cmp	al, 2	# len must be 2
	jnz	0f	# TODO: warn
	# TODO: set SACKP flag on connection
	jmp	1f


3:	#TCP_OPT_WS	= 3	# 3,3,b  [SYN]	window scale
	sub	ecx, 2	# account for opt code and len field
	jle	0f	# TODO: jl warn
	lodsb		# load length
	sub	al, 2
	jle	0f	# TODO: warn: jz: empty value; jl: invalid len
	cmp	al, 1	# we only support window scale of 1 byte length:
	jnz	0f	# TODO: warn (abort scanning - sync error)
	dec	ecx	# we should have at least 1 more byte in the header
	jz	0f	# TODO: warn: short header
	lodsb		# safe to read option value
	mov	[ebp - 12], eax
	jmp	1f	# continue parsing options

2:	#TCP_OPT_MSS	= 2	# 2,4,w  [SYN]	max seg size
	sub	ecx, 2	# account for the opt code and the len field
	jle	0f	# TODO: warn
	lodsb		# safe to load len
	sub	al, 2	# we don't want to overflow into eax
	js	0f	# TODO: warn
	# we only support word-sized MSS values
	cmp	al, 2
	jnz	0f	# TODO: warn: unsupported data length
	sub	ecx, 2	# 
	jl	0f	# TODO: warn
	lodsw		# load the MSS value
	xchg	al, ah
	mov	[ebp - 8], eax
	xor	ah, ah	# make sure high 3 byte sof eax are clear
	jecxz	0f
	# fallthrough to the loop

1:	#TCP_OPT_NOP	= 1	# 1		padding; (no len/data)
	dec ecx; jnz 0b;#loop	0b
0:	pop_	eax ecx esi


#### accept tcp connection

	# send a response

	_TCP_OPTS = 12	# mss (4), ws (3), nop(1), sackp(2), nop(2)
	_TCP_HLEN = (TCP_HEADER_SIZE + _TCP_OPTS)

	NET_BUFFER_GET
	jc	91f
	push	edi

	mov	eax, [edx + ipv4_src]
	push	edx
	mov	dx, IP_PROTOCOL_TCP
	push	esi
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	mov	ecx, _TCP_HLEN
	call	net_ipv4_header_put # mod eax, esi, edi, ebx
	pop	esi
	pop	edx
	jc	92f

	# add tcp header
	push	edi
	push	ecx
	mov	ecx, _TCP_HLEN & 3
	xor	eax, eax
	rep	stosb
	mov	ecx, _TCP_HLEN >> 2
	rep	stosd
	pop	ecx
	pop	edi

	mov	eax, [esi + tcp_sport]
	rol	eax, 16
	mov	[edi + tcp_sport], eax

	mov	eax, [esi + tcp_seq]
	bswap	eax
	MUTEX_SPINLOCK TCP_CONN
		push	edx
		mov	edx, [ebp - 4]
		add	edx, [tcp_connections]
		.if NET_TCP_DEBUG > 1
			DEBUG_DWORD eax, "set remote_seq_base"
		.endif
		mov	[edx + tcp_conn_remote_seq_base], eax
	inc	eax
		mov	[edx + tcp_conn_remote_seq_ack], eax
		orb	[edx + tcp_conn_state], TCP_CONN_STATE_SYN_RX
		movb	[edx + tcp_conn_state_official], TCP_CONN_STATE_SYN_RECEIVED
	bswap	eax
	mov	[edi + tcp_ack_nr], eax

mov eax, [ebp - 8]
cmp eax, TCP_MTU
jb 10f
DEBUG_DWORD eax, "TCP: Reducing remote MSS"
mov eax, TCP_MTU
10:
mov [edx + tcp_conn_remote_mss], eax

		# calculate a seq of our own
		mov	eax, [edx + tcp_conn_local_seq]
		bswap	eax
		# SYN counts as one seq
		inc	dword ptr [edx + tcp_conn_local_seq]
		pop	edx

	mov	[edi + tcp_seq], eax

	mov	ax, TCP_FLAG_SYN | TCP_FLAG_ACK | ((_TCP_HLEN/4)<<12)
	xchg	al, ah
	mov	[edi + tcp_flags], ax
	.if NET_TCP_DEBUG
		push	eax
		mov	eax, [ebp - 4]
		TCP_DEBUG_RESPONSE
		pop	eax
		#printc TCP_DEBUG_COL_TX, "tcp: Tx SYN ACK"
		call	newline
	.endif


	#mov	ax, [esi + tcp_windowsize]
	#mov	[edi + tcp_windowsize], ax
	movw	[edi + tcp_windowsize], ((TCP_CONN_BUFFER_SIZE&0xff)<<8)|(TCP_CONN_BUFFER_SIZE>>8) # word ptr 0x20

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0


	# tcp options

	# in: esi = source tcp frame
	# in: edi = target tcp frame
	.if 1
	add	esi, TCP_HEADER_SIZE
	mov	esi, edi
	add	edi, TCP_HEADER_SIZE
	mov	eax, TCP_OPT_MSS | (4<<8) | ((TCP_MTU & 0xff) << 24) | ((TCP_MTU>>8) << 16)
	stosd
	mov	eax, 0x01010101	# 'nop'
	stosd
	stosd
	.else
	call	net_tcp_copyoptions
	.endif

	# calculate checksum		# in: esi = tcp frame pointer
	add	edx, offset ipv4_src	# in: edx = ipv4 src,dst
	mov	ecx, _TCP_HLEN		# in: ecx = tcp frame len
	call	net_tcp_checksum
	sub	edx, offset ipv4_src

	# send packet

	pop	esi
	NET_BUFFER_SEND
	jc	91f

	mov	eax, [ebp - 4]
	add	eax, [tcp_connections]
	orb	[eax + tcp_conn_state], TCP_CONN_STATE_SYN_ACK_TX | TCP_CONN_STATE_SYN_TX
	movb	[eax + tcp_conn_state_official], TCP_CONN_STATE_SYN_RECEIVED
	MUTEX_UNLOCK TCP_CONN

0:	mov	esp, ebp
	pop	ebp
	popad
	ret

# these errors occur while TCP_CONN is locked
93:	# net buffer send fail
	jmp	1b
# these errors occur before TCP_CONN is locked
92:	# ipv4 header put fail (arp lookup failure etc)
	pop	edi
91:	# net buffer get fail
	jmp	0b

# in: esi = source tcp frame
# in: edi = target tcp frame
# out: edi = end of tcp header
# out: esi = target tcp frame
net_tcp_copyoptions:
	push	ecx
	push	edx
	push	eax
	push	ebx

	# scan incoming options

	# get the source options length
	movzx	ecx, byte ptr [esi + tcp_flags]
	shr	cl, 4
	shl	cl, 2
	sub	cl, 20

	.if NET_TCP_OPT_DEBUG > 1
		DEBUG_WORD cx
	.endif


	xor	edx, edx	# contains MSS and WS

	add	esi, TCP_HEADER_SIZE
0:
	.if NET_TCP_OPT_DEBUG > 1
		call newline
		DEBUG_DWORD ecx
	.endif

	dec	ecx
	jle	0f
	#jz	0f
	#jc	0f
	lodsb

	.if NET_TCP_OPT_DEBUG > 1
		printc 14, "OPT "
		DEBUG_BYTE al
	.endif

	or	al, al	# TCP_OPT_END
	jz	0f
	cmp	al, TCP_OPT_NOP
	jz	0b
	cmp	al, TCP_OPT_MSS
	jnz	1f
		sub	ecx, 3
		jb	0f
		lodsb
		sub	al, 4
		jnz	0f
		lodsw
		mov	dx, ax

	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "MSS"
		DEBUG_WORD dx
		DEBUG_WORD cx
	.endif

	jmp	0b
1:
	cmp	al, TCP_OPT_WS
	jnz	1f
		sub	ecx, 2
		jb	0f
		lodsb
		sub	al, 3
		jnz	0f
		lodsb
		rol	edx, 8
		mov	dl, al
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "WS"
		DEBUG_BYTE dl
	.endif
		ror	edx, 8
	jmp	0b
1:
	cmp	al, TCP_OPT_SACKP
	jnz	1f
		dec	ecx
		jb	0f
		lodsb
		rol	edx, 16
		mov	dl, al
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "SACKP"
		DEBUG_BYTE dl
	.endif
		ror	edx, 16
	jmp	0b

1:
	cmp	al, TCP_OPT_SACK
	jz	2f
	cmp	al, TCP_OPT_TSECHO
	jz	2f
	cmp	al, TCP_OPT_ACR
	jz	2f
	cmp	al, TCP_OPT_ACD
	jz	2f
	jmp	0b

2:
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "skip-opt"
		DEBUG_BYTE al
	.endif

	dec	ecx
	jz	0f
	lodsb
	sub	al, 2
	jz	0b
	sub	cl, al
	ja	0b
0:
	.if NET_TCP_OPT_DEBUG > 1
		DEBUG "opts done"
		DEBUG_DWORD ecx
		call	newline
	.endif

	# set the options:  edx = [8:WS][8:00][16:MSS]

	mov	esi, edi	# return value

	add	edi, TCP_HEADER_SIZE

	push	edi
	mov	al, TCP_OPT_NOP
	mov	ecx, _TCP_OPTS
	rep	stosb
	pop	edi

	or	dx, dx
	jz	1f

	# MSS
	mov	[edi], byte ptr TCP_OPT_MSS
	mov	[edi + 1], byte ptr 2+2
	mov	[edi + 2], word ptr 0xb405
1:
	add	edi, 4
	rol	edx, 8
	or	dl, dl
	jz	1f
	# WS
	mov	[edi], byte ptr TCP_OPT_WS
	mov	[edi + 1], byte ptr 2 + 1
	mov	[edi + 2], dl # byte ptr 7	# * 128
	# nop
	mov	[edi + 3], byte ptr TCP_OPT_NOP
1:
	add	edi, 4

	rol	edx, 8
	or	dl, dl
	jz	1f
	mov	[edi], byte ptr TCP_OPT_SACKP
	mov	[edi + 1], dl
	mov	[edi + 2], byte ptr TCP_OPT_NOP
	mov	[edi + 3], byte ptr TCP_OPT_NOP
1:
	add	edi, 4


	pop	ebx
	pop	eax
	pop	edx
	pop	ecx
	ret

# in: edx = ptr to ipv4 src, dst
# in: esi = tcp frame pointer
# in: ecx = tcp frame len (header and data)
net_tcp_checksum:
	push	esi
	push	edi
	push	edx
	push	ecx
	push	eax

	# calculate tcp pseudo header:
	# dd ipv4_src
	# dd ipv4_src
	# db 0, protocol	# dw 0x0600 # protocol
	# dw headerlen+datalen
	push	esi
	mov	esi, edx
	xor	edx, edx
	xor	eax, eax
	# ipv4 src, ipv4 dst
	.rept 4
	lodsw
	add	edx, eax
	.endr
	add	edx, 0x0600	# tcp protocol + zeroes

	#xchg	cl, ch		# headerlen + datalen
	shl	ecx, 8	# hmmm
	add	edx, ecx
	shr	ecx, 8
	pop	esi

	# esi = start of tcp frame (saved above)
	mov	edi, offset tcp_checksum
	call	protocol_checksum_	# in: ecx=len, esi=start, esi+edi=cksum

	pop	eax
	pop	ecx
	pop	edx
	pop	edi
	pop	esi
	ret

net_tcp_cleanup:
	push_	eax esi ebx edi

	call	get_time_ms
	mov	edi, eax
	sub	edi, TCP_CONN_CLEAN_TIMEOUT
	js	10f

	MUTEX_SPINLOCK TCP_CONN
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, esi, ebx, 9f

	cmp	byte ptr [esi + ebx + tcp_conn_state], -1
	jz	1f

	cmp	[esi + ebx + tcp_conn_timestamp], edi
	ja	1f
	.if NET_TCP_DEBUG
		DEBUG_DWORD ebx, "freeing TCP buffers for connection "
	.endif
	xor	eax, eax
	xchg	eax, [esi + ebx + tcp_conn_recv_buf]
	or	eax, eax
	jz	2f
	call	mfree

2:	xor	eax, eax
	xchg	eax, [esi + ebx + tcp_conn_send_buf]
	or	eax, eax
	jz	2f
	call	mfree

2:	mov	byte ptr [esi + ebx + tcp_conn_state], -1

1:	ARRAY_ENDL
9:	MUTEX_UNLOCK TCP_CONN
10:	pop_	edi ebx esi eax
	ret
# tcp code size: 3607 bytes
