##############################################################################
# Telnet
#

TELNETD_MAX_CLIENTS	= 1

.intel_syntax noprefix
.data SECTION_DATA_BSS
telnet_num_clients:	.word 0
.text32

.global cmd_telnetd
cmd_telnetd:
	I "Starting Telnet Daemon"
	PUSH_TXT "telnetd"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset net_service_telnetd_main
	KAPI_CALL schedule_task
	jc	9f
	OK
9:	ret

net_service_telnetd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 23
	mov	ebx, SOCK_LISTEN
	KAPI_CALL socket_open
	jc	9f
	printc 11, "Telnet Daemon listening on "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	KAPI_CALL socket_accept
	jc	0b
	push	eax
	mov	eax, edx
	call	telnetd_handle_client
	pop	eax
	jmp	0b
	
	ret
9:	printlnc 4, "telnetd: failed to open socket"
	ret


telnetd_handle_client:
	LOAD_TXT "421 Too many clients, try again later\r\n"
	cmp	word ptr [telnet_num_clients], TELNETD_MAX_CLIENTS
	jae	telnet_close

	PUSH_TXT "telnetd-c"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset 1f
	KAPI_CALL schedule_task
	ret

1:	lock inc word ptr [telnet_num_clients]
	enter 0,0
	push	eax	# [ebp - 4]: socket

	printc 11, "Telnet connection: "
	KAPI_CALL socket_print
	call	newline

	LOAD_TXT "220 cloud.neonics.com QuRe Assembly OS telnetd\r\n"
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush

0:	mov	ecx, 20000
	mov	eax, [ebp - 4]
	KAPI_CALL socket_read
	jc	9f
	call	telnet_parse
	jnc	0b
	LOAD_TXT "221 Check back later!\r\n"

1:	call	telnet_close

	leave
	lock dec word ptr [telnet_num_clients]
	ret

9:	printlnc 4, "Telnet timeout, terminating connection"
	LOAD_TXT "221 Timeout, bye!\r\n"
	jmp	1b

# in: eax = sock
# in: esi = asciz message
telnet_close:
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret

telnet_parse:
	printc 11, "Telnet Input: ";
	call	nprint_
	clc
	ret
