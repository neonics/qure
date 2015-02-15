##############################################################################
# TFTP (rfc1350 (obsoletes rfc783))
#
# Trivial implementation of Trivial File Transfer Protocol
# - Only 1 session at a time
.intel_syntax noprefix

TFTP_DEBUG = 0

# packet types.
# protocol:
#
# OPEN:	 [CLIENT:ctid](READ|WRITE)	-> [SERVER:69]
# 	 [SERVER:stid](ACK|DATA|ERROR)	-> [CLIENT:ctid]
#
# (port: basically, client allocates local UDP port (ctid), TX to port 69;
#  server responds to client on it's port, using a new server port.)
#
# So:
#
# CLIENT:rtid -> SERVER:69
# SERVER:ltid -> CLIENT:rtid
# CLIENT:rtid -> SERVER:rtid
#
# server:
#	IF ERROR abort
#	IF READ RETURN DATA
#	IF WRITE RETURN ACK
#	RETURN ERROR
#
# client:
#	IF READ return { expect DATA }
#	IF WRITE return DATA
#
# expect:
#	if ERROR abort
#	if $1 return ACK
#	return ERROR
#
# server:
#	client = ( clients{ udp.ports } || clients[] = { udp.ports, NEW } )
#
# client:
#	client = { udp.ports, status: NEW, block: 0 }
#
#	read:

.struct 0
/*
.space ETH_HEADER_SIZE
# Overlay the UDP header:
tftp_ltid:	.word 0		# udp_sport
tftp_rtid:	.word 0		# udp_dport
tftp_len:	.word 0		# udp_len
tftp_checksum:	.word 0		# udp_checksum
.space IPV4_HEADER_SIZE	# no fancy options
*/
tftp_opcode:	.word 0
	TFTP_PT_READ	= 1	# .word 1; .asciz filename; .asciz "octet","netascii","mail" (c/i) 
	TFTP_PT_WRITE	= 2	# .word 2; idem
	TFTP_PT_DATA	= 3 	# .word 3, blocknr; .space 512 data (shorter = EOF)
	TFTP_PT_ACK	= 4	# .word 4, blocknr
	TFTP_PT_ERROR	= 5	# .word 5, errcode; .asciz msg
tftp_error:
		TFTP_ERROR_UNDEFINED		= 0	# see error message
		TFTP_ERROR_FILE_NOT_FOUND	= 1
		TFTP_ERROR_ACCESS_DENIED	= 2
		TFTP_ERROR_NO_SPACE		= 3	# disk full or allocation exceeded
		TFTP_ERROR_ILLEGAL_OPERATION	= 4
		TFTP_ERROR_UNKNOWN_TID		= 5	# transfer id
		TFTP_ERROR_FILE_ALREADY_EXISTS	= 6	# (noclobber)
		TFTP_ERROR_NO_SUCH_USER		= 7
tftp_block:	.word 0		# also: errorcode, filename etc
tftp_data:	.space 512	# for now we don't support blksize option
TFTP_FRAME_SIZE = .


.struct 0
tftp_conn_rtid:		.word 0		# remote UDP port
tftp_conn_ltid:		.word 0		# local UDP port
tftp_conn_raddr:	.long 0		# remote IPv4 addr
tftp_conn_laddr:	.long 0		# local IPv4 addr
tftp_conn_timestamp:	.long 0		# to timeout stale (service blocking) connections.
tftp_conn_blksize:	.long 0		# default 512; blksize opt (usually 1456: 1500 - IP(18) - UDP(8)=1500-26=1476....?)
tftp_conn_block:	.word 0		# current block being processed

#tftp_fhandle:	.long 0			# file handle 
tftp_conn_fbuf:	.long 0			# file contents
tftp_conn_bufsize:			# using fs_handle_read with internal buffer (at current 2k for ISO9660)
tftp_conn_fsize:	.long 0		# file size
tftp_conn_bufpos:	.long 0		# pos in small buffer, increments by sectors until fsize
tftp_conn_resendprotect:.long 0		# infinite loop protection for resending packets

TFTP_CONN_STRUCT_SIZE = .

.text32
tftp_code_start:
# Called from udp.s on incoming packets to dport 69
#
# We don't use the typical server-task and client-handler tasks approach here.
# On an incoming UDP packet in the NIC, an IRQ is triggered, which relays
# the packet to the netq handler, freeing up the NIC packet buffer.
# The netq handler, a separate task, does protocol analysis and delegates
# the various protocol frames (ETH/IP/UDP) to the appropriate handler,
# in this case the UDP handler ph_ipv4_udp. This handler detects the service
# port (udp_dport 69) and delegates the packet here.
#
# We then open a new socket and schedule a task to handle the connection.
# This way no resources are taken up by a daemon thread/task.
#
#
# in: ebx = nic
# in: edx = ipv4 frame
# in: eax = udp frame
# in: esi = payload
# in: ecx = payload len
ph_ipv4_udp_tftp:
	cmpw	[eax + udp_dport], 69 << 8	# we should be called only with this dport
	jnz	91f
	# This dport is only used to establish new connections.
	# On an incoming connection, a new UDP port
	# is allocated for further communication (even the connect
	# response).
	#
	# The only way right now is to allocate a socket,
	# which requires threads/tasks. This means that we
	# either have to do our initial setup in the netq thread,
	# or copy data. Since a socket with READPEER is used for
	# subsequent requests, we modify the initial request
	# to fit in such a buffer, containing the IP addresses,
	# UDP ports, and the TFTP payload:
	mov	edi, eax	# backup udp frame
	lea	eax, [ecx + 12]	# payload len + READPEER header
	call	malloc		# no need for mallocz
	jc	92f
	push_	edi ecx		# copy payload
	lea	edi, [eax + 12]
	rep	movsb	
	pop_	ecx edi
	mov	esi, eax	# allocated
	add	ecx, 12
	# now esi,ecx are a READPEER socket packet. Fill the header:
	mov	eax, [edx + ipv4_src]
	mov	[esi + 0], eax	# peer IP
	mov	ax, [edi + udp_sport]
	mov	[esi + 4], ax	# peer port (RTID)

	mov	eax, [edx + ipv4_dst]
	mov	[esi + 6], eax		# local ip
	call	net_udp_port_get	# out: ax; allocate LTID
	xchg	al, ah			# convert to NBO
	mov	[esi + 10], ax	# local port (LTID)

	push_	ebx edx
	mov	eax, [edx + ipv4_dst]	# listening ipv4 addr
	mov	edx, IP_PROTOCOL_UDP << 16
	mov	dx, [esi + 10]		# local port	XXX bswap?
	xchg	dl, dh			# nbo -> little endian
	mov     ebx, SOCK_READPEER	# so we can verify
	call	socket_open	# KAPI_CALL socket_open - no need, we're in CPL0 interrupt handler
	pop_	edx ebx
	jc      93f
	# eax = UDP socket.

	# let's start a handler task to poll the socket
	# We pass on the socket in eax, and the fake READPEER
	# socket packet in esi,ecx.

	# in: eax = UDP socket with READPEER
	# in: ebx = NIC
	# in: esi = READPEER socket packet
	# in: ecx = READPEER socket packet size
        PUSH_TXT "tftpd"
        push    dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
        push    cs
        push    dword ptr offset tftp_socket_server_task
        KAPI_CALL schedule_task         # out: eax = pid
        jc      94f
	ret

90:	_pushcolor 4
	call	_s_printlnc
	ret

91:	PUSH_TXT "dport not 69"		; jmp 90b
92:	PUSH_TXT "malloc error"		; jmp 90b
93:	PUSH_TXT "error opening socket"	; jmp 90b
94:	PUSH_TXT "error scheduling task"; jmp 90b

# in: eax = socket with READPEER enabled
# in: ebx = nic
# in: esi = socket connection packet with READPEER
# in: ecx = idem len.
tftp_socket_server_task:
	.if TFTP_DEBUG
		printlnc 0xf0, "tftp server INIT"
	.endif
	# when we're started, we have just received a
	# connection request on udp_dport 69, and we
	# need to answer that using the socket
	# (since it contains the 'ltid' local UDP port).

	# we could try to allocate our stuff on the stack since the
	# scheduler has allocated it using high memory pages, which is
	# at least 4kb - more than we need.
	enter	TFTP_CONN_STRUCT_SIZE + ETH_MAX_PACKET_SIZE, 0 # esp = stack bottom = start of eth packet.
	pushad	# esp + 32 = tx packet buffer
	mov	ebp, esp
		SV_NIC		= PUSHAD_EBX
		SV_SOCK		= PUSHAD_EAX
		SV_CONN		= 32 	# skip the pushad
		SV_PKT		= 32 + TFTP_CONN_STRUCT_SIZE
		SV_FRAME_ETH	= SV_PKT
		SV_FRAME_IP	= SV_FRAME_ETH +  ETH_HEADER_SIZE
		SV_FRAME_UDP	= SV_FRAME_IP  + IPV4_HEADER_SIZE
		SV_FRAME_TFTP	= SV_FRAME_UDP +  UDP_HEADER_SIZE

		# we copy the buffer so we can release the malloc:
		# (note: schedule_task needs to be expanded to allow to
		# set up stack contents).

		mov	eax, esi
		mov	[ebp + SV_PKT], ecx	# use first dword for size (once)
		lea	edi, [ebp + SV_PKT + 4]	# use rest for packet
		add	ecx, 3
		shr	ecx, 2
		rep	movsd

		call	mfree
		jnc 1f; printlnc 12, "ERROR: TFTP_SOCKET_SERVER_THREAD: mfree"; 1:	# pointer check

	call	tftp_server

9:	popad
	leave
	ret

	
tftp_server:
	call	tftp_new_connection
	jc	9f	# done; probably sent error

0:	mov	eax, [ebp + SV_SOCK]
	mov	ecx, 5000	# 5s delay
	KAPI_CALL socket_read
	jc	92f

	call	tftp_check_connection
	jc	0b	# got a stray packet, it's handled

	# in: esi = tftp payload
	# in: ecx = payload len
	call	tftp_handle_established_connection
	jnc	0b	# on carry, terminate (not necessarily an error)
	
9:	mov	eax, [ebp + SV_SOCK]
	.if TFTP_DEBUG
		DEBUG "TFTP: Closing socket, terminating."
	.endif
	KAPI_CALL socket_close
	ret

92:	printlnc 12, "TFTP: timeout"
	jmp	9b



#
#
tftp_new_connection:
	.if TFTP_DEBUG
		DEBUG "TFTP_NEW_CONNECTION"
	.endif

	# clear the tftp_conn struct:
	xor	eax, eax
	lea	edi, [ebp + SV_CONN]
	mov	ecx, TFTP_CONN_STRUCT_SIZE >> 2	# should be aligned!
	rep	stosd

	# retrieve the info on the connect packet:
	lea	esi, [ebp + SV_PKT]
	# nonstandard readpeer: payload size
	lodsd
	mov	ecx, eax

	# READPEER data: peer ip:port, local ip:port
	lodsd
	mov	[ebp + SV_CONN + tftp_conn_raddr], eax
	.if TFTP_DEBUG
		print "peer: "; call net_print_ipv4
	.endif
	lodsw
	xchg	al, ah	# XXX READPEER doesn't use nbo for port
	mov	[ebp + SV_CONN + tftp_conn_rtid], ax
	.if TFTP_DEBUG
		printchar ':'; mov dx, ax; call printhex4
	.endif

	lodsd
	mov	[ebp + SV_CONN + tftp_conn_laddr], eax
	.if TFTP_DEBUG
		print "local: "; call net_print_ipv4
	.endif
	lodsw
	xchg	al, ah	# XXX READPEER doesn't use nbo for port
	mov	[ebp + SV_CONN + tftp_conn_ltid], ax
	.if TFTP_DEBUG
		printchar ':'; mov dx, ax; call printhex4
	.endif

	call	get_time_ms
	mov	[ebp + SV_CONN + tftp_conn_timestamp], eax

	sub	ecx, 12

	.if TFTP_DEBUG
		call	newline
	.endif
	

	# payload checking:
	.if TFTP_DEBUG
		print "payload:"
		pushcolor 0xf0
		push_ esi ecx
		0: lodsb; call printchar; loop 0b
		call newline
		pop_ ecx esi
		popcolor
	.endif

	# check operation:

	mov	di, [esi + tftp_opcode]
	.if TFTP_DEBUG
		DEBUG_WORD di, "check op WRITE"
	.endif
	mov	al, TFTP_ERROR_ACCESS_DENIED
	cmp	di, TFTP_PT_WRITE << 8
	jz	tftp_send_error_packet

	.if TFTP_DEBUG
		DEBUG_WORD di, "check op READ"
	.endif
	mov	al, TFTP_ERROR_ILLEGAL_OPERATION
	cmp	di, TFTP_PT_READ << 8
	jnz	tftp_send_error_packet

	.if TFTP_DEBUG
		DEBUG "READ ok."
	.endif

	mov	[ebp + SV_CONN + tftp_conn_blksize], dword ptr 512	# TODO: blksize opt

	.if TFTP_DEBUG
		OK
	.endif

		lea	eax, [esi + tftp_block]	# offset of .asciz filename; we ignore mode and other options
		.if TFTP_DEBUG
			print "File: "; push eax; call _s_println
		.endif
		# Should be /boot.img, a virtual filename
		# TODO: check if the request is for the proper file.
		# We don't want to send /c/pxeboot.img as this would allow
		# to read any file on the system.

		LOAD_TXT "/a/boot/pxeboot.img", eax
		mov     bl, [boot_drive]
		add     bl, 'a'
		mov     [eax + 1], bl
		KAPI_CALL fs_openfile
		jc	tftp_file_not_found
		.if TFTP_DEBUG
			print "File opened."
			DEBUG_DWORD ecx, "filesize"
		.endif
		mov	[ebp + SV_CONN + tftp_conn_fsize], ecx
		#mov	eax, [edi + tftp_fhandle]
		KAPI_CALL fs_handle_read # in: eax = handle; out: esi, ecx (entire file)
		jc	tftp_file_not_found
		mov	[ebp + SV_CONN + tftp_conn_fbuf], esi
		mov	[ebp + SV_CONN + tftp_conn_bufpos], dword ptr 0
		mov	[ebp + SV_CONN + tftp_conn_bufsize], ecx	# same as tftp_fsize

		KAPI_CALL fs_close
		jnc 1f; printlnc 12, "error closing file";1:

		# set a max repeat count for resending packets (globally).
		mov	[ebp + SV_CONN + tftp_conn_resendprotect], dword ptr 10

	# now that we've extracted the network addresses from
	# the payload, we can now prepare the response
	# packet. The only changes would be the TFTP frame data.
	# Also note that the packet lengths and checksums must
	# be updated before sending a packet.

	pushad	
		# ETH, IPV4, UDP headers

		lea	edi, [ebp + SV_FRAME_ETH]

		mov	eax, [ebp + SV_CONN + tftp_conn_raddr]
		mov	esi, offset mac_bcast
		mov	dx, IP_PROTOCOL_UDP
		mov	ecx, UDP_HEADER_SIZE + TFTP_FRAME_SIZE
		mov	ebx, [ebp + SV_NIC]
		call	net_ipv4_header_put	# NOTE: update checksum and size!
		# edi == lea [ebp + SV_FRAME_UDP]

		mov	eax, [ebp + SV_CONN + tftp_conn_rtid]	# remote, local ports
		mov	esi, edi	# remember udp frame ptr for checksum
		mov	ecx, DHCP_HEADER_SIZE
		call	net_udp_header_put
		# edi == lea [ebp + SV_FRAME_TFTP]

	popad



	jmp	tftp_handle_read



# in: esi = payload with READPEER header
# in: ecx = payload len (incl READPEER size: 12 bytes)
tftp_check_connection:
	# READPEER handling: source ip:port, dest ip:port
	.if TFTP_DEBUG
		print "RX peer="
	.endif
	lodsd
	.if TFTP_DEBUG
		call net_print_ipv4
		printchar ':'
	.endif
	lodsw
	mov	dx, ax
	.if TFTP_DEBUG
		call printhex4
	.endif
	lodsd
	shl	edx, 16	# pipelining
	.if TFTP_DEBUG
		print " this="
		call net_print_ipv4
		printchar ':'
	.endif
	lodsw
	mov	dx, ax
	.if TFTP_DEBUG
		call printhex4
		call newline
	.endif
	sub	ecx, 12
	.if TFTP_DEBUG
		DEBUG_DWORD ecx, "payload len"
		DEBUG_WORD [ebp + SV_CONN + tftp_conn_ltid], "LTID"
		DEBUG_WORD [ebp + SV_CONN + tftp_conn_rtid], "RTID"
	.endif

	# check LTID/RTID (UDP sport/dport)
	bswap	edx
	mov	al, TFTP_ERROR_UNKNOWN_TID
	cmp	edx, [ebp + SV_CONN + tftp_conn_rtid]	# check rtid and ltid
	jnz	tftp_send_error_packet
	# check peer IP
	mov	edx, [ebp + SV_CONN + tftp_conn_raddr]
	cmp	edx, [esi - 12]
	jnz	tftp_send_error_packet

	clc
	ret


# in: esi = tftp payload
# in: ecx = payload len
# out: CF = 1: terminate.
tftp_handle_established_connection:
	mov	ax, [esi + tftp_opcode]
	.if TFTP_DEBUG
		DEBUG_WORD ax, "TFTP: rx opcode"
	.endif
	cmp	ax, TFTP_PT_ERROR << 8
	jz	91f

	cmp	ax, TFTP_PT_ACK  << 8
	mov	al, TFTP_ERROR_ILLEGAL_OPERATION
	jnz	tftp_send_error_packet

	mov	ax, [esi + tftp_block]
	xchg	al, ah
	sub	ax, [ebp + SV_CONN + tftp_conn_block]
	jz	1f
	dec	ax	# TFTP is lock-step: one packet delay
	jz	tftp_resend
	mov	al, TFTP_ERROR_UNDEFINED	# sync error
	mov	[ebp + SV_FRAME_TFTP + tftp_data], dword ptr ('S')|('Y'<<8)|('N'<<16)|('C'<<24)
	jmp	tftp_send_error_packet

1:	
	# got proper ACK, continue:
	call	tftp_get_next_size	# out: ecx
	jecxz	1f	# no more data, we're done.
	add	[ebp + SV_CONN + tftp_conn_bufpos], ecx
	jmp	tftp_handle_read
91:
	printlnc 12, "TFTP: received ERROR, abort"
tftp_done$:
1:	stc	# terminate task
	ret


tftp_get_next_size:
	# last sector check
	mov	ecx, [ebp + SV_CONN + tftp_conn_bufsize]
	sub	ecx, [ebp + SV_CONN + tftp_conn_bufpos]
	cmp	ecx, [ebp + SV_CONN + tftp_conn_blksize]
	jbe	1f
	mov	ecx, [ebp + SV_CONN + tftp_conn_blksize]
1:	ret


tftp_resend:
	.if TFTP_DEBUG
		DEBUG "TFTP: resend"
	.endif
	decd	[ebp + SV_CONN + tftp_conn_resendprotect]
	mov	al, TFTP_ERROR_UNDEFINED
	mov	[ebp + SV_FRAME_TFTP + tftp_data], dword ptr ('2')|('M'<<8)|('N'<<16)|('E'<<24)
	jz	tftp_send_error_packet
	jmp	tftp_resend_$


tftp_handle_read:
	incw	[ebp + SV_CONN + tftp_conn_block]
tftp_resend_$:

	call	tftp_get_next_size	# out: ecx
	jecxz	tftp_done$

	lea	edi, [ebp + SV_FRAME_TFTP]
	mov	ax, TFTP_PT_DATA << 8
	stosw
	mov	ax, [ebp + SV_CONN + tftp_conn_block]
	.if TFTP_DEBUG
		DEBUG_WORD ax, "BLOCK"
	.endif
	xchg	al, ah
	stosw	# [ebp + SV_FRAME_TFTP + tftp_block]
	movw	[edi + tftp_opcode], TFTP_PT_DATA << 8

	.if TFTP_DEBUG
		DEBUG_DWORD ecx, "nextsize"
	.endif
	
		# copy from file buffer
		mov	esi, [ebp + SV_CONN + tftp_conn_fbuf]
		add	esi, [ebp + SV_CONN + tftp_conn_bufpos]

		test	cl, 3
		jz	1f
		mov	eax, ecx
		and	ecx, 3
		rep	movsb
		mov	ecx, eax
	1:	shr	ecx, 2
		rep	movsd

	jmp	tftp_send_packet	# in: edi = packet end

tftp_send_ack_packet:
	lea	edi, [ebp + SV_FRAME_TFTP]
	movw	[edi + tftp_opcode], TFTP_PT_ACK << 8
	mov	esi, edi
	incd	[edi + tftp_block]
	add	edi, 4	# no trailing data
	jmp	tftp_send_packet




tftp_file_not_found:
	mov	al, TFTP_ERROR_FILE_NOT_FOUND

tftp_send_error_packet:
	.if TFTP_DEBUG
		DEBUG_BYTE al,"Send TFTP ERROR"
	.endif
	lea	edi, [ebp + SV_FRAME_TFTP]
	movw	[edi + tftp_opcode], TFTP_PT_ERROR << 8
	mov	[edi + tftp_error + 1],  al	# error code (nbo); tftp_block
	movb	[edi + tftp_data], 0
	lea	edi, [edi + tftp_data + 1]	# error code requires .asciz

# in: edi = packet end, somewhere in
#     [ebp + SV_FRAME_TFTP]..[ebp + SV_PKT + ETH_MAX_PACKET_SIZE].
tftp_send_packet:
	push	edi

		mov	ecx, edi
		lea	esi, [ebp + SV_FRAME_TFTP]
		sub	ecx, esi	# in: ecx = udp payload len (ex header)
		lea	edx, [ebp + SV_FRAME_IP] # in: edx = IP frame pointer
		lea	esi, [ebp + SV_FRAME_UDP] # in: esi = udp frame pointer
		call    net_udp_set_size	# out: ecx += UDP_HEADER_SIZE

		lea	esi, [ebp + SV_FRAME_IP] # in: esi, ecx=payload size
		call	net_ip_set_size	# out: ecx = IP frame size (header+payload)

		add	ecx, ETH_HEADER_SIZE

	pop	edi		# in: edi = packet end
	
	lea	esi, [ebp + SV_PKT]
	mov	ebx, [ebp + SV_NIC]
	lea	esi, [ebp + SV_PKT]	# in: esi = packet start
	.if TFTP_DEBUG > 1
		pushad
		printlnc 0xf0, "tftp_send"
		call	net_packet_print
		popad
	.endif
	NET_BUFFER_SEND	# TODO: check code path for buffer release
	ret

tftp_code_end:
