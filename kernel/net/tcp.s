################################################################################
# TCP
#
NET_TCP_RESPOND_UNK_RST = 0	# whether to respond with RST packet for unknown
				# connections or non-listening ports.

NET_TCP_DEBUG		= 0#2
NET_TCP_CONN_DEBUG	= 0
NET_TCP_OPT_DEBUG	= 0

.struct 0
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
	TCP_OPT_SACKP	= 4	# 4,2	 [SYN]	selectice ack permitted
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
#
TCP_CONN_REUSE_TIMEOUT	= 30 * 1000	# 30 seconds
TCP_CONN_BUFFER_SIZE	= 2048
.struct 0
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

tcp_conn_timestamp:	.long 0	# [clock_ms]

tcp_conn_local_addr:	.long 0	# NEEDS to be adjacent to tcp_conn_remote_addr
tcp_conn_remote_addr:	.long 0	# ipv4 addr
tcp_conn_local_port:	.word 0
tcp_conn_remote_port:	.word 0
tcp_conn_local_seq:	.long 0
tcp_conn_remote_seq:	.long 0
tcp_conn_local_seq_ack:	.long 0
tcp_conn_remote_seq_ack:.long 0
tcp_conn_sock:		.long 0	# -1 = no socket; peer socket
tcp_conn_handler:	.long 0	# -1 or 0 = no handler
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

# rfc793:
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
TCP_CONN_STRUCT_SIZE = .
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
#	.data
#	tcp_conn_states$:
#	STRINGPTR "<unknown>"
#	STRINGPTR "LISTEN"
#	STRINGPTR "SYN_RECEIVED"
#	STRINGPTR "ESTABLISHED"
#	STRINGPTR "FIN_WAIT_1"
#	STRINGPTR "FIN_WAIT_2"
#	STRINGPTR "CLOSE_WAIT"
#	STRINGPTR "LAST_ACK"
#	STRINGPTR "TIME_WAIT"
#	STRINGPTR "CLOSED"
#	.text32
#	cmp	esi, TCP_CONN_STATE_CLOSED + 1
#	jl	0f
#	xor	esi, esi
#0:	mov	esi, [tcp_conn_states$ + esi * 4]
#	call	print
#	ret


# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# out: eax = tcp_conn array index (add volatile [tcp_connections])
net_tcp_conn_get:
	MUTEX_SPINLOCK_ TCP_CONN
	push	ecx
	push	edx
	mov	ecx, [esi + tcp_sport]
	rol	ecx, 16
	ARRAY_LOOP [tcp_connections], TCP_CONN_STRUCT_SIZE, edx, eax, 9f
	cmp	ecx, [edx + eax + tcp_conn_local_port]
	jz	0f
	ARRAY_ENDL
9:	stc
0:	MUTEX_UNLOCK_ TCP_CONN
	pop	edx
	pop	ecx
	ret


# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: ecx = tcp frame len
# in: ebx = socket (or -1)
# in: edi = handler [unrelocated]
# out: eax = tcp_conn array index
# out: CF = 1: out of memory
net_tcp_conn_newentry:
	MUTEX_SPINLOCK_ TCP_CONN
	push	ecx
	push	edx

	mov	ecx, edx	# ip frame
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "(tcp NewConn)"
	.endif

	push	edi
	mov	edi, [clock_ms]
	sub	edi, TCP_CONN_REUSE_TIMEOUT

	# find free entry (use status flag)
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, eax, edx, 9f
	cmp	byte ptr [eax + edx + tcp_conn_state], -1
	jz	1f
	cmp	byte ptr [eax + edx + tcp_conn_state], 0b11011111
	jnz	2f
	cmp	edi, [eax + edx + tcp_conn_timestamp]
	jnb	1f
2:	ARRAY_ENDL
9:
	push	ecx	# remember ip frame
	ARRAY_NEWENTRY [tcp_connections], TCP_CONN_STRUCT_SIZE, 4, 9f
	jmp	2f
9:	pop	ecx

	pop	edi
	pop	edx
	pop	ecx
	MUTEX_UNLOCK_ TCP_CONN
	ret

## newly allocated
2:	pop	ecx	# ip frame

1:	pop	edi
	push	edx	# retval eax

	mov	eax, [tcp_connections]

	add	eax, edx

	# eax = tcp_conn ptr
	# ecx = ip frame
	# edi = handler
	# edx = free

	mov	[eax + tcp_conn_state], byte ptr 0
	mov	[eax + tcp_conn_sock], dword ptr -1
	mov	[eax + tcp_conn_handler], edi

	mov	edx, [ecx + ipv4_src]
	mov	[eax + tcp_conn_remote_addr], edx
			.if NET_TCP_CONN_DEBUG > 1
			DEBUG "remote"
				push	eax
				mov	eax, edx
				call	net_print_ip
				pop	eax
			.endif

	mov	edx, [ecx + ipv4_dst]
	mov	[eax + tcp_conn_local_addr], edx
			.if NET_TCP_CONN_DEBUG > 1
				DEBUG "local"
				push	eax
				mov	eax, edx
				call	net_print_ip
				pop	eax
			.endif
	mov	edx, [esi + tcp_sport]
	ror	edx, 16
	mov	[eax + tcp_conn_local_port], edx
			.if NET_TCP_CONN_DEBUG > 1
				DEBUG "local port"
				DEBUG_DWORD edx
			.endif


	mov	[eax + tcp_conn_local_seq], dword ptr 0
	mov	[eax + tcp_conn_remote_seq], dword ptr 0
	mov	[eax + tcp_conn_local_seq_ack], dword ptr 0
	mov	[eax + tcp_conn_remote_seq_ack], dword ptr 0

	# allocate buffers
	xchg	edx, eax
	cmp	dword ptr [edx + tcp_conn_send_buf], 0
	jnz	1f
	mov	eax, TCP_CONN_BUFFER_SIZE
	call	mallocz
	jc	9f
cmp eax,0x00400000
jb 2f
int 3
2:
clc
	mov	[edx + tcp_conn_send_buf], eax
	mov	[edx + tcp_conn_send_buf_size], dword ptr TCP_CONN_BUFFER_SIZE
1:	mov	[edx + tcp_conn_send_buf_start], dword ptr 0
	mov	[edx + tcp_conn_send_buf_len], dword ptr 0

	# allocate receive buffer
	cmp	dword ptr [edx + tcp_conn_recv_buf], 0
	jnz	1f
	mov	eax, TCP_CONN_BUFFER_SIZE
	call	mallocz
	jc	9f
cmp eax, 0x00400000
jb 2f
int 3
2:
clc

	mov	[edx + tcp_conn_recv_buf], eax
	mov	[edx + tcp_conn_recv_buf_size], dword ptr TCP_CONN_BUFFER_SIZE
1:	mov	[edx + tcp_conn_recv_buf_start], dword ptr 0
	mov	[edx + tcp_conn_recv_buf_len], dword ptr 0


0:	MUTEX_UNLOCK_ TCP_CONN

	pop	eax
	pop	edx
	pop	ecx
	jnc	net_tcp_conn_update
	# eax = tcp_conn array index, rest unmodified
	ret

9:	printlnc 4, "tcp: out of memory"
	jmp	0b

# in: eax = tcp_conn array index
# in: edx = ip frame pointer
# in: esi = tcp frame pointer
# in: ecx = tcp frame len (incl header)
net_tcp_conn_update:
	MUTEX_SPINLOCK_ TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	.if NET_TCP_CONN_DEBUG > 1
		DEBUG "tcp_conn update"
	.endif

	push	eax
	push	edx
	push	ebx

	add	eax, [tcp_connections]

	mov	ebx, [clock_ms]
	mov	[eax + tcp_conn_timestamp], ebx

	mov	ebx, [esi + tcp_seq]
	bswap	ebx
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
0:	clc	# net_tcp_conn_newentry ends up here
	pop	ebx
	pop	edx
	pop	eax
	MUTEX_UNLOCK_ TCP_CONN
	ret


net_tcp_conn_list:
	MUTEX_SPINLOCK_ TCP_CONN
	ARRAY_LOOP	[tcp_connections], TCP_CONN_STRUCT_SIZE, esi, ebx, 9f
	printc	11, "tcp/ip "


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
	pop	esi

	print	" last comm: "
	mov	edx, [clock_ms]
	sub	edx, [esi + ebx + tcp_conn_timestamp]
	call	printdec32
	print	" ms ago"

	cmp	[esi + ebx + tcp_conn_send_buf], dword ptr 0
	jz	1f
	printc 12, " B"
1:

	call	newline

	.if 1
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf],"tx buf"
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf_start],"start"
		DEBUG_DWORD [esi+ebx+tcp_conn_send_buf_len],"len"
		call	newline
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
	printc 8, " seq "
	mov	edx, [esi + ebx + tcp_conn_remote_seq]
	call	printhex8
	printc 8, " ack "
	mov	edx, [esi + ebx + tcp_conn_remote_seq_ack]
	call	printhex8

	printc 14, " hndlr "
	mov	edx, [esi + ebx + tcp_conn_handler]
	call	printhex8

	#call	newline	# already at eol

	ARRAY_ENDL
9:	MUTEX_UNLOCK TCP_CONN
	ret

# out: ax
net_tcp_port_get:
	.data
	TCP_FIRST_PORT = 48000
	tcp_port_counter: .word TCP_FIRST_PORT
	.text32
	mov	ax, [tcp_port_counter]
	push	eax
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
	push	edx
	pushcolor TCP_DEBUG_COL
	print	"tcp["
	mov	edx, eax
	call	printdec32
	print	"] "
	popcolor
	pop	edx
	pop	eax
.endm

.macro TCP_DEBUG_REQUEST
	pushcolor TCP_DEBUG_COL_RX
	print "tcp["
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
.endm

# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_ipv4_tcp_handle:
	# firewall
	call	net_tcp_conn_get
	jc	0f

	.if NET_TCP_DEBUG
		TCP_DEBUG_CONN
		TCP_DEBUG_REQUEST
	.endif

	# known connection
	call	net_tcp_conn_update
	call	net_tcp_handle	# in: eax=tcp_conn idx, ebx=ip, esi=tcp,ecx=len
	ret


0:	# firewall: new connection
	.if NET_TCP_DEBUG
		TCP_DEBUG_REQUEST
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	8f # its not a new or known connection

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jnz	1f # ACK must not be set on initial SYN.

	.if NET_TCP_DEBUG
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

	# firewall / services:
	mov	eax, [edx + ipv4_dst]
	push	edx
	movzx	edx, word ptr [esi + tcp_dport]
	xchg	dl, dh
	or	edx, IP_PROTOCOL_TCP << 16
	call	net_socket_find
	mov	ebx, edx
	pop	edx
	jc	9f
	mov	edi, offset tcp_rx_sock

	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL, "tcp: ACCEPT SYN"
	.endif
	call	net_tcp_conn_newentry	# in: edx=ip fr, esi=tcp fr, edi=handler
	jc	9f	# no more connections, send RST
	call	net_tcp_handle_syn$
	.if NET_TCP_DEBUG
		call	newline
	.endif
	# update socket, call handler
	cmp	ebx, -1
	jz	1f
	mov	ecx, eax			# in: ecx = tcp conn idx
	mov	eax, ebx			# in: eax = local socket
	movzx	ebx, word ptr [esi + tcp_sport]	# in: ebx = peer port
	xchg	bl, bh
	mov	edx, [edx + ipv4_src]		# in: edx = peer ip
#	MUTEX_SPINLOCK_ TCP_CONN
	call	net_sock_deliver_accept		# out: edx = peer sock idx
	# the deliver may trigger an IRQ due to the socket user sending a
	# packet, however, the tcp_conn_sock field is only used on receiving
	# packets, which are queued.
#	mov	eax, [tcp_connections]
#	mov	[eax + ecx + tcp_conn_sock], edx
#	MUTEX_UNLOCK_ TCP_CONN

1:	ret

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
		printc 0x8c, "tcp: REJECT SYN: "
	.endif

	mov	eax, -1	# nonexistent connection
2:	call	net_tcp_tx_rst$
.endif

1:	.if NET_TCP_DEBUG
		call	net_print_ip_pair
		call	newline

		call	net_ipv4_tcp_print
	.endif
	ret

# in: eax = tcp_conn array index
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN
	.if NET_TCP_DEBUG
		printc	TCP_DEBUG_COL_RX, "<"
	.endif

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_SYN
	jz	0f
	.if NET_TCP_DEBUG
		printc	TCP_DEBUG_COL_RX, "dup SYN"
	.endif
0:
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_ACK
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "ACK "
	.endif
	push	eax
	call	net_tcp_conn_update_ack
	cmp	eax, -1
	pop	eax
#	jz	9f	# received final ACK on FIN - connection closed.
0:

########
	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_FIN
	jz	0f

	# FIN
	MUTEX_SPINLOCK_ TCP_CONN
	push	eax
	add	eax, [tcp_connections]

	test	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX
	.if NET_TCP_DEBUG
	jz	1f
		printc 11, "dup FIN "
	jmp	2f
	.else
	jnz	2f
	.endif

1:;	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "FIN "
	.endif
	inc	dword ptr [eax + tcp_conn_remote_seq]
	or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_RX
2:
	# byte not allowed - using word.
	bts	word ptr [eax + tcp_conn_state], TCP_CONN_STATE_FIN_ACK_TX_SHIFT
	pop	eax
	MUTEX_UNLOCK_ TCP_CONN
	jc	9f	# don't ack: already sent FIN
	# havent sent fin, rx'd fin: tx fin ack

	push	edx
	push	ecx
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_TX, "tcp: Tx ACK[FIN] "
	.endif
	mov	dl, TCP_FLAG_ACK
	xor	ecx, ecx
	# send ACK [FIN]
	xor	dh, dh
	call	net_tcp_send
	pop	ecx
	pop	edx
	.if NET_TCP_DEBUG
		call	newline
	.endif
	#ret
########
0:	call	net_tcp_handle_payload$

	test	[esi + tcp_flags + 1], byte ptr TCP_FLAG_PSH
	jz	0f
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_RX, "PSH "
	.endif
	# flush the accumulated payload to the handler/socket
	call	net_tcp_handle_psh
0:
	.if NET_TCP_DEBUG
		printlnc	TCP_DEBUG_COL_RX, ">"
	.endif
9:	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# These two will point to the PSH data (accumulated)
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
	MUTEX_SPINLOCK_ TCP_CONN
	add	eax, [tcp_connections]
	mov	dx, [eax + tcp_conn_remote_port]
	xchg	dl, dh
	mov	eax, [eax + tcp_conn_remote_addr]
	MUTEX_UNLOCK_ TCP_CONN
	call	net_socket_find
	jc	9f
#	DEBUG "Got socket"
	mov	eax, edx
	call	net_socket_write
0:	pop	edx
	pop	eax
	ret
9: DEBUG "!! NO socket: ip=";call net_print_ip;DEBUG_DWORD edx,"proto|port"
jmp 0b
	.else

	MUTEX_SPINLOCK_ TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	add	eax, [tcp_connections]
	mov	eax, [eax + tcp_conn_sock]
	MUTEX_UNLOCK_ TCP_CONN
	call	net_socket_write
	.endif
	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle_payload$:
	push	ecx
	push	edx
	push	esi

	# get offset and length of payload
	movzx	edx, byte ptr [esi + tcp_flags]	# headerlen
	shr	edx, 2
	and	dl, ~3
	sub	ecx, edx
	jz	0f	# no payload
	add	esi, edx	# esi points to payload

	MUTEX_SPINLOCK_ TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	push	eax
	add	eax, [tcp_connections]
	add	[eax + tcp_conn_remote_seq], ecx

	call newline
	.if NET_TCP_DEBUG > 1
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
	.if NET_TCP_DEBUG > 1
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
	MUTEX_UNLOCK_ TCP_CONN
	# send ack
	push	eax
	call	net_tcp_conn_send_ack
	pop	eax

0:	pop	esi
	pop	edx
	pop	ecx
	ret

# in: eax = tcp_conn array index
# in: edx = ipv4 frame
net_tcp_handle_psh:
	push	ecx
	push	edx
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

	MUTEX_SPINLOCK_ TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	mov	edi, [tcp_connections]
	add	edi, eax
	mov	esi, [edi + tcp_conn_recv_buf]
	add	esi, [edi + tcp_conn_recv_buf_start]
	mov	ecx, [edi + tcp_conn_recv_buf_len]

	.if NET_TCP_DEBUG > 1
		call newline
		DEBUG "handle PSH", 0xb0
		DEBUG_DWORD [edi+tcp_conn_recv_buf_start],"start",0xb0
		DEBUG_DWORD [edi+tcp_conn_recv_buf_len],"len",0xb0
		call newline
	.endif

	mov	edi, [edi + tcp_conn_handler]
	MUTEX_UNLOCK_ TCP_CONN

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
	MUTEX_SPINLOCK_ TCP_CONN
	mov	edi, [tcp_connections]
	add	edi, eax
	sub	[edi + tcp_conn_recv_buf_len], ecx	# should be 0
	mov	[edi + tcp_conn_recv_buf_start], dword ptr 0
	MUTEX_UNLOCK_ TCP_CONN

0:	pop	esi
	pop	edx
	pop	ecx
	ret
9:	printlnc 4, "net_tcp_handle_psh: null handler"
	# eax = edi = 0; edx=tcp hlen=ok, ecx=0x75.
	pushad
	call	net_tcp_conn_list
	popad
	int	1
	jmp	0b

# in: eax = tcp connection index
# out: eax = -1 if the ACK is for the FIN
# side-effect: send_buf free'd.
net_tcp_conn_update_ack:
	MUTEX_SPINLOCK_ TCP_CONN
	push	edx
	push	eax
	push	ebx
	add	eax, [tcp_connections]
	mov	ebx, [esi + tcp_ack_nr]
	mov	[eax + tcp_conn_local_seq_ack], ebx
	movzx	ebx, byte ptr [eax + tcp_conn_state]
	# see if ACK is for FIN
	test	bl, TCP_CONN_STATE_FIN_TX
	jz	1f
	mov	edx, [eax + tcp_conn_tx_fin_seq]
	bswap	edx
	cmp	edx, [esi + tcp_ack_nr]
	jnz	1f
	# Connection closed now, free buffer:
	push	eax
	mov	eax, [eax + tcp_conn_send_buf]
	call	mfree
	pop	eax
	mov	[eax + tcp_conn_send_buf], dword ptr 0
	test	bl, TCP_CONN_STATE_FIN_ACK_RX|TCP_CONN_STATE_FIN_ACK_TX
	jz	1f
	mov	[esp + 4], dword ptr -1	# return eax = -1
1:
	#
	or	bh, TCP_CONN_STATE_FIN_ACK_RX
1:	test	bl, TCP_CONN_STATE_SYN_TX
	jz	1f
	or	bh, TCP_CONN_STATE_SYN_ACK_RX
1:	or	[eax + tcp_conn_state], bh
	pop	ebx
	pop	eax
	pop	edx
	MUTEX_UNLOCK_ TCP_CONN
	ret


net_tcp_conn_send_ack:
	push	edx
	push	ecx
	xor	dx, dx
	xor	ecx, ecx
	call	net_tcp_send
	pop	ecx
	pop	edx
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
0:	MUTEX_SPINLOCK_ TCP_CONN
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	mov	ebx, [tcp_connections]
	add	ebx, eax

	# buf_start allows to put the eth/ip/tcp headers in the buffer to
	# avoid copying the data yet again.

#DEBUG_DWORD [ebx+tcp_conn_send_buf]
#DEBUG_DWORD [ebx+tcp_conn_send_buf_start]
#DEBUG_DWORD [ebx+tcp_conn_send_buf_len]
	mov	edi, [ebx + tcp_conn_send_buf]
cmp edi, 0x00300000
jb 1f
pushad
MUTEX_UNLOCK_ TCP_CONN
call net_tcp_conn_list
MUTEX_SPINLOCK_ TCP_CONN
call mem_print_handles
popad
pushad
DEBUG_DWORD [tcp_connections],"[conn]"
DEBUG_DWORD eax,"idx"
DEBUG_DWORD ebx
DEBUG_DWORD edi,"buf"
lea eax, [ebx + tcp_conn_send_buf]
DEBUG_DWORD eax,"!!!"
call newline

mov edx, [esp + 32 + 12]
DEBUG_DWORD edx;  call debug_printsymbol;call newline # callgate

mov	eax, [tcp_connections]
sub	eax, 8
call	mem_find_handle$	# out: edx = handle nr; ebx = handle struct ptr
jc	11f
call	mem_print_handle_$;
jmp	12f

11:	DEBUG "handle not found"
12:

int 3
popad
1:
	mov	edx, [ebx + tcp_conn_send_buf_start]
	add	edx, [ebx + tcp_conn_send_buf_len]
	add	edi, edx
#	sub	edx, [ebx + tcp_conn_send_buf_size]
	sub	edx, 1536 - ETH_HEADER_SIZE-IPV4_HEADER_SIZE-TCP_HEADER_SIZE
	# edi = end of data to send so far
	# edx = remaining buffer length

	cmp	ecx, edx
	mov	edx, 0	# don't modify CF
	jb	1f	# it will fit
	sub	ecx, edx
	xchg	edx, ecx	# ecx = remaining buf len, edx=data not in buf
1:	# ecx = data to copy into  buf
	# edx = data that won't fit in buf

	add	[ebx + tcp_conn_send_buf_len], ecx
	rep	movsb	# BUG: tcp_conn_sendbuf page fault

	mov	ecx, [ebx + tcp_conn_send_buf_len]
	MUTEX_UNLOCK TCP_CONN
########
	cmp	ecx, 1024	# search TCP_MAX_PAYLOAD_SIZE MTU PACKET_SIZE
	mov	ecx, edx
	jb	1f		# still room in buffer, dont send yet.
	# enough data to send.
	call	net_tcp_sendbuf_flush
	# buf empty (as it is exactly one packet size)
	or	ecx, ecx
	jnz	0b	# go again

1:	pop	edx
	pop	ebx
	pop	edi
	ret


# uses tcp_conn_send_buf*
# in: eax = tcp conn idx
net_tcp_sendbuf_flush:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN

	push	edx
	push	esi
	push	ecx
	push	ebx

0:	MUTEX_SPINLOCK_ TCP_CONN

	mov	ebx, [tcp_connections]
	add	ebx, eax

	mov	esi, [ebx + tcp_conn_send_buf]
	add	esi, [ebx + tcp_conn_send_buf_start]
	xor	ecx, ecx
	xchg	ecx, [ebx + tcp_conn_send_buf_len]
	cmp	ecx, 1420
	jbe	1f
	sub	ecx, 1420
	mov	[ebx + tcp_conn_send_buf_len], ecx
	mov	ecx, 1420
	add	[ebx + tcp_conn_send_buf_start], ecx
1:	MUTEX_UNLOCK_ TCP_CONN

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
net_tcp_send:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE, TCP_CONN
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

	MUTEX_SPINLOCK_ TCP_CONN
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
	mov	ecx, TCP_HEADER_SIZE
	xor	eax, eax
	rep	stosb
	pop	eax
	pop	ecx
	pop	edi

	# copy connection state
	push	ebx
	add	eax, [tcp_connections]

	mov	ebx, [eax + tcp_conn_local_port]
	mov	[edi + tcp_sport], ebx

	mov	ebx, [eax + tcp_conn_local_seq]
	bswap	ebx
	mov	[edi + tcp_seq], ebx
	add	[eax + tcp_conn_local_seq], ecx

	mov	ebx, [eax + tcp_conn_remote_seq]
	mov	[eax + tcp_conn_remote_seq_ack], ebx
	bswap	ebx
	mov	[edi + tcp_ack_nr], ebx # dword ptr 0	# maybe ack
	pop	ebx

	# update state if FIN
	test 	dl, TCP_FLAG_FIN
	jz	1f
	or	[eax + tcp_conn_state], byte ptr TCP_CONN_STATE_FIN_TX
	inc	dword ptr [eax + tcp_conn_local_seq]	# count FIN as octet
	push	ebx	# mark the sequence
	mov	ebx, [eax + tcp_conn_local_seq]
	mov	[eax + tcp_conn_tx_fin_seq], ebx
	pop	ebx
1:


	mov	ax, TCP_FLAG_ACK| ((TCP_HEADER_SIZE/4)<<12)
	or	al, dl	# additional flags
	xchg	al, ah
	mov	[edi + tcp_flags], ax

	.if NET_TCP_DEBUG
		pushcolor TCP_DEBUG_COL_TX
		print "[Tx "
		xchg	al, ah
		TCP_DEBUG_FLAGS ax
		print "]"
		popcolor
	.endif

	mov	[edi + tcp_windowsize], word ptr 0x20

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0

	jecxz	0f
	push	esi
	push	edi
	push	ecx
	add	edi, TCP_HEADER_SIZE
	rep	movsb
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
	MUTEX_UNLOCK_ TCP_CONN

	# send packet

	pop	esi
	add	ecx, edi	# add->mov ?
	sub	ecx, esi
	call	[ebx + nic_api_send]
	jc	9f

	# update flags
	MUTEX_SPINLOCK_ TCP_CONN
	mov	eax, [ebp]	# tcp_conn_idx
	add	eax, [tcp_connections]
	mov	dh, [eax + tcp_conn_state]

	test	dl, TCP_FLAG_FIN
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_TX
1:	test	dh, TCP_CONN_STATE_FIN_RX
	jz	1f
	test	dl, TCP_FLAG_ACK
	jz	1f
	or	dh, TCP_CONN_STATE_FIN_ACK_TX
1:	or	[eax + tcp_conn_state], dh
	MUTEX_UNLOCK_ TCP_CONN

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



# in: eax = tcp_conn array index
# in: edx = ip frame
# in: esi = tcp frame
# in: ecx = tcp frame len
net_tcp_handle_syn$:
	ASSERT_ARRAY_IDX eax, [tcp_connections], TCP_CONN_STRUCT_SIZE
	pushad
	push	ebp
	mov	ebp, esp
	push	eax

#### accept tcp connection

	# send a response

	_TCP_OPTS = 12	# mss (4), ws (3), nop(1), sackp(2), nop(2)
	_TCP_HLEN = (TCP_HEADER_SIZE + _TCP_OPTS)

	NET_BUFFER_GET
	jc	9f
	push	edi

	mov	eax, [edx + ipv4_src]
	push	edx
	mov	dx, IP_PROTOCOL_TCP
	push	esi
	lea	esi, [edx - ETH_HEADER_SIZE + eth_src] # optional
	mov	ecx, _TCP_HLEN
	call	net_ipv4_header_put # mod eax, esi, edi
	pop	esi
	pop	edx
	jc	8f

	# add tcp header
	push	edi
	push	ecx
	mov	ecx, _TCP_HLEN
	xor	al, al
	rep	stosb
	pop	ecx
	pop	edi

	mov	eax, [esi + tcp_sport]
	rol	eax, 16
	mov	[edi + tcp_sport], eax

	mov	eax, [esi + tcp_seq]
	bswap	eax
	inc	eax
	MUTEX_SPINLOCK_ TCP_CONN
		push	edx
		mov	edx, [ebp - 4]
		add	edx, [tcp_connections]
		mov	[edx + tcp_conn_remote_seq_ack], eax
		or	[edx + tcp_conn_state], byte ptr TCP_CONN_STATE_SYN_RX
	bswap	eax
	mov	[edi + tcp_ack_nr], eax

		# calculate a seq of our own
		mov	eax, [edx + tcp_conn_local_seq]
		bswap	eax
		# SYN counts as one seq
		inc	dword ptr [edx + tcp_conn_local_seq]
		pop	edx

	mov	[edi + tcp_seq], eax

	mov	ax, TCP_FLAG_SYN | TCP_FLAG_ACK | ((_TCP_HLEN/4)<<12)
	.if NET_TCP_DEBUG
		printc TCP_DEBUG_COL_TX, "tcp: Tx SYN ACK"
	.endif
	xchg	al, ah
	mov	[edi + tcp_flags], ax

	mov	ax, [esi + tcp_windowsize]
	mov	[edi + tcp_windowsize], ax

	mov	[edi + tcp_checksum], word ptr 0
	mov	[edi + tcp_urgent_ptr], word ptr 0


	# tcp options

	# in: esi = source tcp frame
	# in: edi = target tcp frame
	.if 1
	add	esi, TCP_HEADER_SIZE
	mov	esi, edi
	add	edi, TCP_HEADER_SIZE
	mov	eax, 0x01010101	# 'nop'
	stosd
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

9:	pop	eax
	jc	1f
	add	eax, [tcp_connections]
	or	byte ptr [eax + tcp_conn_state], TCP_CONN_STATE_SYN_ACK_TX | TCP_CONN_STATE_SYN_TX
1:	MUTEX_UNLOCK_ TCP_CONN
	pop	ebp
	popad
	ret
8:	pop	edi
	jmp	9b

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

