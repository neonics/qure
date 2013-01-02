##############################################################################
# SMTP - Simple Mail Transfer Protocol
#
# rfc 821

SMTPD_MAX_CLIENTS	= 1

.intel_syntax noprefix
.data SECTION_DATA_BSS
smtp_num_clients:	.word 0
.text32

.macro LOAD_STR_CONST32 reg, a, b, c, d
	mov	\reg, (\a)|(\b<<8)|(\c<<16)|(\d<<24)
.endm


cmd_smtpd:
	I "Starting SMTP Daemon"
	PUSH_TXT "smtpd"
	push	dword ptr 2	# context switch task
	push	cs
	push	dword ptr offset net_service_smtpd_main
	call	schedule_task
	jc	9f
	OK
9:	ret

net_service_smtpd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 25
	mov	ebx, SOCK_LISTEN
	call	socket_open
	jc	9f

0:	mov	ecx, 10000
	call	socket_accept
	jc	0b
	push	eax
	mov	eax, edx
	call	smtpd_handle_client
	pop	eax
	jmp	0b
	
	ret
9:	printlnc 4, "smtpd: failed to open socket"
	ret


smtpd_handle_client:
	LOAD_TXT "421 Too many clients, try again later\r\n"
	cmp	word ptr [smtp_num_clients], SMTPD_MAX_CLIENTS
	jae	smtp_close

	PUSH_TXT "smtpd-c"
	push	dword ptr 2	# context switch
	push	cs
	push	dword ptr offset 1f
	call	schedule_task
	ret

1:	lock inc word ptr [smtp_num_clients]

	printc 11, "SMTP connection: "
	call	socket_print
	call	newline

	LOAD_TXT "220 cloud.neonics.com QuRe Assembly OS smtpd\r\n"
	call	strlen_
	call	socket_write
	call	socket_flush

0:	mov	ecx, 10000
	call	socket_read
	jc	9f
	call	smtp_parse
	jnc	0b
	LOAD_TXT "221 Check back later!\r\n"

1:	call	smtp_close

	lock dec word ptr [smtp_num_clients]
	ret

9:	printlnc 4, "SMTP timeout, terminating connection"
	LOAD_TXT "221 Timeout, bye!\r\n"
	jmp	1b

# in: eax = sock
# in: esi = asciz message
smtp_close:
	call	strlen_
	call	socket_write
	call	socket_flush
	call	socket_close
	ret

# Handle SMTP data
# in: eax = tcp conn idx
# in: esi = data
# in: ecx = data len
net_service_tcp_smtp:
	printc 11, " SMTP: "
	call	socket_print
	call	smtp_parse
	ret


.data
smtp_commands:
.ascii "HELO","MAIL","RCPT","DATA","RSET","SEND","SOML","SAML","VRFY","EXPN"
.ascii "HELP","NOOP","QUIT","TURN"
smtp_command_handlers:
.long 11f,12f,13f,14f,15f,16f,17f,18f,19f,20f,21f,22f,23f,24f
smtp_state0:	# initially acceptable commands
.word 1<<0|1<<10|1<<13
smtp_states:	# acceptable commands in each state; -1 means no state transition
#       XYTQNHEVSSSRDRMH
.word 0b0011111111100010	# HELO
.word 0b0001111100010100	# MAIL
.word 0b0001111100011100	# RCPT 503 out of order
.word 0b0100000000000000	# DATA 503 out of order
.word 0b1000000000000000	# RSET 503 out of order
.word 0b0001111100010100	# SEND
.word 0b0001111100010100	# SOML
.word 0b0001111100010100	# SAML
.word 0b1100000000000000	# VRFY
.word 0b1100000000000000	# EXPN
.word 0b1100000000000000	# HELP
.word 0b1100000000000000	# NOOP
.word 0	# QUIT
.word 0
.text32
11:	LOAD_TXT "250 Hello!\r\n"	# HELO
	jmp	2f
12:	LOAD_TXT " FROM:<", edi		# MAIL
	call	smtp_parse_path
	jnz	501f

13:	jmp	502f			# RCPT
14:	jmp	502f			# DATA
15:	jmp	502f			# RSET
16:	jmp	502f			# SEND
17:	jmp	502f			# SOML
18:	jmp	502f			# SAML
19:	jmp	502f			# VRFY
20:	jmp	502f			# EXPN
21:	jmp	502f			# HELP
22:	jmp	502f			# NOOP
23:	stc; jmp 221f			# QUIT
24:	jmp	502f			# TURN

# in: esi = str
# in: edi = expected
smtp_expect_param:
	xchg	esi, edi
	call	strlen_
	xchg	esi, edi
	repz	cmpsb
	ret

smtp_parse_path:
	call	smtp_expect_param
	jnz	0f
	mov	edi, esi
	mov	al, '>'
	call	strlen_
	repnz	scasb
	jnz	0f
	# TODO: parse email address between esi, edi
	mov	ecx, edi
	sub	ecx, esi
	dec	ecx
	print "email: <"
	call	nprint
	println ">"
	xor	al, al	# clear zero
0:	ret


# in: esi = data
# in: ecx = data len
smtp_parse:
	push	eax
	push	edi
	push	ecx
	mov	edi, esi
0:	mov	al, '\n'
	repnz	scasb
	jnz	500f
	# be tolerant about CR(\r) LF(\n):
	cmp	[edi-2], byte ptr '\r'
	jnz	1f
	dec	edi
1:	mov	byte ptr [edi-1], 0
	# ignore rest - expect one packet per line
	printc 11, "SMTP rx: "
	call	println

	lodsd
	and	eax, ~0x20202020	# to uppercase
	mov	edi, offset smtp_commands
	mov	ecx, 14
	repnz	scasd
	jnz	502f
	mov	al, [esi]
	or	al, al
	jz	1f
	cmp	al, ' '
	jnz	500f

1:	jmp	[edi + 13*4]
	
502:	LOAD_TXT "502 Not implemented\r\n"
2:	call	strlen_
	mov	eax, [esp + 8]	# socket
	call	socket_write
	call	socket_flush
	clc

221:	pop	ecx
	pop	edi
	pop	eax
	ret

500:	LOAD_TXT "500 Syntax error\r\n"
	jmp	2b

501:	LOAD_TXT "501 Syntax error in paramters\r\n"
	jmp	2b
