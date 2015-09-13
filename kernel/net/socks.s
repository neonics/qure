##############################################################################
# SOCKS Proxy service
#
# rfc1928 SOCKS Protocol Version 5

SOCKS_MAX_CLIENTS	= 1

.intel_syntax noprefix
.data SECTION_DATA_BSS
socks_num_clients:	.word 0
.text32


.global cmd_socksd
cmd_socksd:
	I "Starting SOCKS Daemon"
	PUSH_TXT "socksd"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset net_service_socksd_main
	KAPI_CALL schedule_task
	jc	9f
	OK
9:	ret

net_service_socksd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 1080
	mov	ebx, SOCK_LISTEN
	KAPI_CALL socket_open
	jc	9f
	printc 11, "SOCKS Daemon listening on "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	KAPI_CALL socket_accept
	jc	0b
	push	eax
	mov	eax, edx
	call	socksd_handle_client
	pop	eax
	jmp	0b
	
	ret
9:	printlnc 4, "socksd: failed to open socket"
	ret


socksd_handle_client:
	cmp	word ptr [socks_num_clients], SMTPD_MAX_CLIENTS
	jae	socks_close_deny

	PUSH_TXT "socksd-c"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset 1f
	KAPI_CALL schedule_task
	ret

1:	lock inc word ptr [socks_num_clients]
	enter 0,0
	pushd	eax	# [ebp - 4]: socket
	pushd	0	# [ebp - 8]: state

	printc 11, "SOCKS connection: "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	mov	eax, [ebp - 4]	# socket
	KAPI_CALL socket_read
	jc	9f
	call	socks_parse
	jnc	0b

1:	call	socks_close
	leave
	lock dec word ptr [socks_num_clients]
	ret

9:	printlnc 4, "SOCKS timeout, terminating connection"
	jmp	1b

# XXX concurrency
.data
_socks_method_reply$: .byte 1, 255	# VER 1, METHOD "no acceptable methods"
# Methods:
# 0: no auth required
# 1: GSSAPI
# 2: user/pass
# 3..254 reserved
# 255: no acceptable methods
.text32

# server pre client schedule
socks_close_deny:
	mov	esi, offset _socks_method_reply$
	movb	[esi + 1], 255
	mov	ecx, 2
	DEBUG_DWORD eax,"socks_close_deny socket_write"
	DEBUG_DWORD esi
	DEBUG_DWORD ecx
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret

###
# client task:

socks_close:
	mov	eax, [ebp - 4]
	DEBUG_DWORD eax,"socks_close socket_flush"
	DEBUG_DWORD ebp
	KAPI_CALL socket_flush
	DEBUG "about to socket_close:"
	DEBUG_DWORD ebp
	DEBUG_DWORD eax
	mov	eax, [ebp - 4]
	DEBUG_DWORD eax,"socks_close socket_close"
	KAPI_CALL socket_close
	ret


socks_parse:
	mov	eax, [ebp - 8]	# state
	dec	eax
	js	socks_parse_method$
	jz	socks_parse_request$

	printlnc 4, "SOCKS: unknown state, aborting"
	stc
	ret

socks_parse_method$:
	cmp	ecx, 3
	jb	91f

	movzx	edx, byte ptr [esi]
	print "VER: ";
	call	printhex2

	movzx	edx, byte ptr [esi+1]
	print "NMETHODS: "
	call	printhex2

	sub	ecx, 2
	jle	91f
	cmp	ecx, edx
	jnz	91f

	print "METHODS: "
	add	esi, 2
	mov	ah, [esi]	# get first method
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	loop	0b
	call	newline
	print "Using first method: "
	mov	dl, ah
	call	printhex2
	call	newline

	mov	[_socks_method_reply$ + 1], ah
	mov	ecx, 2
	mov	eax, [ebp - 4]
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	movb	[ebp - 8], 1	# state 1
	clc

9:	ret	# preserve CF


# .byte VER, CMD, 0, ATYP
# .space 4 | 16 | domainname.length
# .word 0
socks_parse_request$:
	printc 11, "SOCKS request: "
	cmp	ecx, 1+1+1+1+4+2	
	jbe	91f
	lodsb	# ignore version
	lodsb	# CMD
	print "command: (1=CONNECT,2=BIND,3=UDP)"
	mov	dl, al
	call	printhex2
	call	printspace

	inc	esi	# reserved

	lodsb		# address type
	sub	ecx, 6	# maximum length of address in packet
	jle	91f

	cmp	al, 1
	jz	11f
	cmp	al, 3
	jz	13f
	cmp	al, 4
	jz	14f
	jmp	92f	# unsupported

11:	# ipv4
	print "IPv4: "
	sub	ecx, 4
	jle	91f
	lodsd
	call	net_print_ipv4
	jmp	1f

13:	# domain name
	print "Domain: "
	xor	eax, eax
	lodsb		# string length
	sub	ecx, eax
	jle	91f
	mov	ecx, eax
	call	nprint_	# esi += ecx, ecx =0
	jmp	1f

14:	# ipv6
	print "IPv6: "
	mov	eax, esi
	call	net_print_ipv6
	add	esi, 16
	#jmp	1f

1:	lodsw	# port in NBO
	mov	dh, al	
	mov	dl, ah
	printchar ':'
	call	printdec32
	call	newline

	stc
	ret



91:	DEBUG_DWORD ecx
	DEBUG_BYTE dl
	printlnc 4, "SOCKS: packet length mismatch"
	mov	[_socks_method_reply$ + 1], byte ptr 255
	mov	ecx, 2
	mov	eax, [ebp - 4]
	KAPI_CALL socket_write
	stc
	ret


.data
_socks_command_reply$:
.byte 1	# version
.byte 1	# general failure
.byte 0	# reserved
.byte 1	# atyp (ipv4)
.long 0	# ipv4 addr
.word 0	# port
.text32
92:	printc 4, "SOCKS: unsupported command: "
	mov	dl, al
	call	printhex2
	call	newline

	mov	esi, offset _socks_command_reply$
	mov	ecx, 1+1+1+1+4+2
	mov	eax, [ebp - 4]
	KAPI_CALL socket_write
	stc
	ret



