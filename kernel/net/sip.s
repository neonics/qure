##############################################################################
# SIP - Session Initiation Protocol
#
# rfc 3261
.intel_syntax noprefix
.text32

cmd_sipd:
	I "Starting SIP Daemon"
	PUSH_TXT "sipd"
	push	dword ptr 2	# context switch task
	push	cs
	push	dword ptr offset net_service_sipd_main
	call	schedule_task
	jc	9f
	OK
9:	ret

net_service_sipd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_UDP<<16 | 5060
	mov	ebx, SOCK_LISTEN
	call	socket_open
	jc	9f

0:	mov	ecx, 10000
	call	socket_read
	jc	0b
	push	eax
	call	sipd_handle_packet
	pop	eax
	jmp	0b
	ret

9:	printlnc 4, "sipd: failed to open socket"
	ret


sipd_handle_packet:
	printc 11, "SIP connection: "
	call	socket_print
	call	newline
	LOAD_TXT "SIP/2.0/UDP 501 Not implemented\r\n"
# in: eax = sock
# in: esi = asciz message
sipd_close:	# NOTE: identical to smtp_close
	call	strlen_
	call	socket_write
	call	socket_flush
	call	socket_close
	ret
