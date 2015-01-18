##############################################################################
# SSH - Secure Shell Transport Layer Protocol
#
# rfc 4253
.intel_syntax noprefix

SSHD_MAX_CLIENTS	= 1

.data SECTION_DATA_BSS
sshd_num_clients:	.word 0
.text32

cmd_sshd:
	I "Starting SSH Daemon"
	PUSH_TXT "sshd"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset net_service_sshd_main
	KAPI_CALL schedule_task		# out: eax = pid
	jc	9f

	OK
9:	ret

net_service_sshd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 22
	mov	ebx, SOCK_LISTEN
	KAPI_CALL socket_open
	jc	9f
	printc 11, "SSH Daemon listening on "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	KAPI_CALL socket_accept
	jc	0b
	push	eax
	mov	eax, edx
	call	sshd_handle_client
	pop	eax
	jmp	0b

	ret
9:	printlnc 4, "sshd: failed to open socket"
	ret


sshd_handle_client:
	LOAD_TXT "421 Too many clients, try again later\r\n"
	cmp	word ptr [sshd_num_clients], SSHD_MAX_CLIENTS
	jae	sshd_close

	PUSH_TXT "sshd-c"
	push	dword ptr TASK_FLAG_TASK	# context switch
	push	cs
	push	dword ptr offset sshd_client
	KAPI_CALL schedule_task
	ret

.data
SSH_STATE_CLIENT_PROTOCOL= 0;
SSH_STATE_KEX_INIT	 = 1;
SSH_STATE_KEXDH_INIT	 = 2;
sshc_state: .byte 0;
.text32

sshd_client:
	lock inc word ptr [sshd_num_clients]

	mov	byte ptr [sshc_state], SSH_STATE_CLIENT_PROTOCOL

	printc 11, "SSH connection: "
	KAPI_CALL socket_print
	call	newline


	LOAD_TXT "SSH-2.0-QuRe_SSHD_0.1\r\n"
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush

0:	mov	ecx, 10000
	KAPI_CALL socket_read
	jc	9f
	jecxz	1f
	pushad
	mov	ebp, esp
	DEBUG_DWORD eax, "client socket"
	call	sshd_parse
	popad
	jnc	0b

1:	call	sshd_close

	lock dec word ptr [sshd_num_clients]
	ret

9:	printlnc 4, "SSH timeout, terminating connection"
	jmp	1b

# in: eax = sock
# in: esi = asciz message
sshd_close:
	#call	strlen_
	#KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret

sshd_parse:
	printc 10, "SSHD RX "
	DEBUG_DWORD ecx
	DEBUG_BYTE [esi + ssh_packet_payload], "msg"
	push_	ecx esi eax
0:	lodsb
	call	printchar
	loop	0b
	call	newline
	pop_	eax esi ecx

	# special care:
	cmpb	[esi + ssh_packet_payload], 1	# SSH_MSG_DISCONNECT (defined below)
	jz	sshd_parse_msg_disconnect

	cmp	byte ptr [sshc_state], SSH_STATE_CLIENT_PROTOCOL
	jz	sshd_parse_client_protocol
	cmp	byte ptr [sshc_state], SSH_STATE_KEX_INIT
	jz	sshd_parse_kex_init
	cmp	byte ptr [sshc_state], SSH_STATE_KEXDH_INIT
	jz	sshd_parse_kexdh_init

	printlnc 12, "sshd: unimplemented state, ignoring"
	stc
	ret

# packet:
#  .long 0x2c	# packet entire length: 0x30 (example)
#  .byte 7	# padlen
#  .byte 1	# SSH_MSG_DISCONNECT
#  .long 2	# unknown - code?
#  .long 0x17	# 23
#  .space 23	# "Packet integrity error"
#  .long 0	# maybe detail message len?
#  .space 7	# padding
sshd_parse_msg_disconnect:
	printc 12, "SSH peer DISCONNECT: "
	DEBUG_DWORD [esi + ssh_packet_payload + 1], "code" # assumption
	mov	ecx, [esi + ssh_packet_payload + 1+4]
	bswap	ecx
	lea	esi, [esi + ssh_packet_payload + 1 + 4 + 4]
	call	nprintln
	stc
	ret

#############################
# Server Protocol:
# - server identification handshake
# - key exchange handshake (KEX)
# - new keys handshake
# - server user auth handshake

# handshake base class:
# - initiate
# - accept

#############################
# packet
#

# Transport layer: generic
SSH_MSG_DISCONNECT = 1;
SSH_MSG_IGNORE = 2;
SSH_MSG_UNIMPLEMENTED = 3;
SSH_MSG_DEBUG = 4;
SSH_MSG_SERVICE_REQUEST = 5;
SSH_MSG_SERVICE_ACCEPT = 6;

# Transport layer: algorithm negotiation
SSH_MSG_KEXINIT = 20;
SSH_MSG_NEWKEYS = 21;

# Transport layer: kex specific messages, reusable
SSH_MSG_KEXDH_INIT = 30;		# C->S: mpint e		# assumed by diffie-hellman-group1-sha1 providing g,p; e=g^x mod p
SSH_MSG_KEXDH_REPLY = 31;		# S->C: string pub hostkey, f, signature(H)

# dh-group-exchange
SSH_MSG_KEX_DH_GEX_REQUEST_OLD = 30;	# v1 C->S: .long min(1024), preferred, max(8192) group size in bits
SSH_MSG_KEX_DH_GEX_GROUP = 31;		# v1 S->C: mpint safe prime p, mpint generator g
SSH_MSG_KEX_DH_GEX_INIT = 32;		# v1 C->S: mpint e (replaced by SSH_MSG_KEXDH_INIT)
SSH_MSG_KEX_DH_GEX_REPLY = 33;		# v2 S->C: string K_S; mpint f; signature of H
SSH_MSG_KEX_DH_GEX_REQUEST = 34;

# User authentication: generic
SSH_MSG_USERAUTH_REQUEST = 50;
SSH_MSG_USERAUTH_FAILURE = 51;
SSH_MSG_USERAUTH_SUCCESS = 52;
SSH_MSG_USERAUTH_BANNER = 53;

# User authentication: method specific, reusable
SSH_MSG_USERAUTH_INFO_REQUEST = 60;
SSH_MSG_USERAUTH_INFO_RESPONSE = 61;
SSH_MSG_USERAUTH_PK_OK = 60;

# Connection protocol: generic

SSH_MSG_GLOBAL_REQUEST = 80;
SSH_MSG_REQUEST_SUCCESS = 81;
SSH_MSG_REQUEST_FAILURE = 82;

# Channel related

SSH_MSG_CHANNEL_OPEN = 90;
SSH_MSG_CHANNEL_OPEN_CONFIRMATION = 91;
SSH_MSG_CHANNEL_OPEN_FAILURE = 92;
SSH_MSG_CHANNEL_WINDOW_ADJUST = 93;
SSH_MSG_CHANNEL_DATA = 94;
SSH_MSG_CHANNEL_EXTENDED_DATA = 95;
SSH_MSG_CHANNEL_EOF = 96;
SSH_MSG_CHANNEL_CLOSE = 97;
SSH_MSG_CHANNEL_REQUEST = 98;
SSH_MSG_CHANNEL_SUCCESS = 99;
SSH_MSG_CHANNEL_FAILURE = 100;

.struct 0
ssh_packet_len:	.long 0		# packet length without: packetlen dword, mac (msg auth code)
ssh_packet_padlen: .byte 0
ssh_packet_payload: 

.data
ssh_packet_out: 
# dword packet len	  value = 1 (padlen byte) + payload + padding
# byte padding len	length(packetlen||padlen||payload||padding) is multiple of max(8, cipher_block_size)
# (packetlen-paddinglen-1) payload
# padding		see above. MIN pad len = 4
# MAC
	.space 1024	# XXX
.text32



sshd_parse_client_protocol:	# state 0: client protocol
	printlnc 10, "SSH Client protocol received";
	inc	byte ptr [sshc_state]
	clc
	ret

sshd_parse_kex_init:	# state 1: KEX INIT (key exchange)
	cmpb	[esi + ssh_packet_payload], SSH_MSG_KEXINIT
	jz	1f
	printc 12, "SSH error - expect KEXINIT, got "
	push edx; movzx edx, byte ptr [esi + ssh_packet_payload]; call printhex2; pop edx
	call	newline
	stc
	ret
1:
	# Binary Packet:
	# dword packet len, excluding mac and packet len field, so, size of:
	#   byte padding len
	#   byte[] payload; len=packet len - padding len - 1 [compressed]
	#   byte[] random padding; len=padding len

	# byte[] mac (msg auth code); len = mac_len (unspecified as yet)

	# padding_len chosen so that
	# packet_len || padding_len || payload || padding
	# is a multiple of largest(8,cipher block size)

	# packet len is encrypted too; incporates compressed payload
	# encryption applies to:
	#  packet len
	#  padding len
	#  payload
	#  padding
	#
	# cipher support: (all end with -cbc)
	# required: 3des
	#    3key triple-des (enc-dec-enc):
	#	first 8 bytes of key for first enc,
	#	second 8 for dec,
	#	third 8 for final enc.
	#	24 bytes=160+32=192 bits, 168 actually used)
	# recommended (to support): aes128
	# optional: blowfish, twofish(,256,192,128), aes(128,192,256),
	# 		serpent(128,192,256), arcfour(NON-cbc! 128),
	#		idea, cast128
	# 

	# min packet size (entire packet) is 16 + mac.
	# SHOULD decrypt packet_len when largest(8,cipher block size)
	# bytes are received.

	# mac computed from compressed payload.(first compr, then encr)
	# [shared secret, packet seq nr, packet contents]
	# during KEX mac len = 0
	# mac = MAC(key, seqnr || unencrypted_packet)
	#
	# mac algorithms:
	# required: hmac-sha1	(20 bytes)
	# recommended: hmac-sha1-96 (96 bits=12 bytes of sha1)
	# optional: hmac-md5, hmac-md5-96, none

	# compression: none, zlib (LZ77, RFC1950,1951)
	# initialized after each KEX.


	DEBUG_DWORD ecx, "Data avail"
	lodsd
	bswap	eax
	DEBUG_DWORD eax, "Packet length"
	lodsb
	movzx	ebx, al
	DEBUG_BYTE al, "Padding"
	lodsb
	DEBUG_BYTE al, "MSG code (expect 0x14 KEX INIT)"
	call	newline
	sub	ecx, 4 + 1 + 1

	DEBUG_DWORD ecx
	printc 10, "COOKIE: "
	push	ecx
	mov	ecx, 16
0:	lodsb
	mov	dl, al
	call	printhex2
	loop	0b
	pop	ecx
	sub	ecx, 16
	jle	99f
	call	newline

	.macro SSH_PRINT_ALGS label
		DEBUG_DWORD ecx
		lodsd
		bswap	eax
		DEBUG_DWORD eax, "\label"
		sub	ecx, eax
		sub	ecx, 4
		jle	99f
		# sanity check:
		cmp	ecx, 4096
		jae	98f
		push	ecx
		mov	ecx, eax
		call	nprintln_
		pop	ecx
	.endm

	SSH_PRINT_ALGS "kex_algorithms"
	SSH_PRINT_ALGS "server_host_key_algorithms"
	SSH_PRINT_ALGS "encryption_algorithms_c2s"
	SSH_PRINT_ALGS "encryption_algorithms_s2c"
	SSH_PRINT_ALGS "mac_algorithms_c2s"
	SSH_PRINT_ALGS "mac_algorithms_s2c"
	SSH_PRINT_ALGS "compression_algorithms_c2s"
	SSH_PRINT_ALGS "compression_algorithms_s2c"
	SSH_PRINT_ALGS "languages_c2s"
	SSH_PRINT_ALGS "languages_s2c"

	DEBUG_DWORD ecx
	lodsb
	DEBUG_BYTE al, "KEX first packet follows"
	call	newline
	dec	ecx
	jle	99f

	DEBUG_DWORD ecx
	lodsd
	DEBUG_DWORD eax, "Reserved"
	call	newline
	sub	ecx, 4
	jl	99f

	DEBUG_DWORD ecx
	DEBUG_DWORD ebx, "Expect reserved"
	sub	ecx, ebx
	jl	99f
	jz	1f
	printc 4, "trailing bytes"
	jmp	9f
1:
	# padding MUST be at least 4 bytes.
	# padding is multiple of largest(8, cipher block size)
	mov	ecx, ebx
0:	lodsb
	mov	dl, al
	call	printhex2
	loop	0b
	call	newline

	printlnc 10, "SSH KEX Init";

	call	ssh_kex_init_send

	inc	byte ptr [sshc_state]
9:	clc
	ret
98:	printlnc 5, "ssh: algorithm list too large";
	jmp 1f
99:	printlnc 4, "ssh: negative size"
1:	stc
	ret


# called when kex_init is received
# all registers free.
# [esp] = return to within sshd_parse
# [esp + 4] = return to sshd_client
# [esp + 8...] = pushad
ssh_kex_init_send:
	call	ssh_kex_init_makepacket
	#jmp	ssh_send_packet
# fallthrough

# in: esi = ssh_packet_payload
# in: ecx = payload len
# in: edi = end of payload
ssh_send_packet:
	DEBUG_DWORD ecx,"payload len"

	# set up packet header:
	sub	esi, offset ssh_packet_payload	# rewind to beginning
	#add	ecx, offset ssh_packet_payload	# correct for header

	# calc padding: 
	mov	edx, 8	# block size (or: encrypter.IVsize)
	# pad = (-packetlen) & (blocksize -1)

	lea	eax, [ecx + ssh_packet_payload]	# header + payload
	neg	eax
	# & (blocksize-1)
	dec	edx
	and	eax, edx
	inc	edx
	DEBUG_DWORD eax, "prelim padding"
	# pad += blocksize if pad < blocksize (XXX is always the case I think!)
	cmp	eax, 4 # edx # min padlen = 4 # XXX spec says multiple of (max(8,cipher_block_size) which is > 4 always..?
	jae	1f
	add	eax, edx
1:	mov	edx, eax
	DEBUG_DWORD edx,"payload padding"
	mov	[esi + ssh_packet_padlen], dl

	# add random bytes in padding
	push_	ecx eax
	#lea	edi, [esi + ssh_packet_payload + ecx] # unchanged.
	mov	ecx, edx
0:	call	random
	stosb
	loop	0b
	pop_	eax ecx

	# now calculate the packetlen field value:
	# packetlen := len+ pad -4
	lea	eax, [ecx + edx + 1]	# payloadlen + padding + padlen field (XXX removed -4 fix)
	DEBUG_DWORD eax, "payload+padding+padlenfld"
	bswap	eax
	mov	[esi + ssh_packet_len], eax

	call newline
	DEBUG_DWORD ecx
	DEBUG_DWORD edx
	lea	ecx, [ecx + edx + ssh_packet_payload]
	DEBUG_DWORD ecx, "NET PACKET LEN"
	mov	ecx, edi
	sub	ecx, esi
	DEBUG_DWORD ecx, "AGAIN"

	#mov	eax, [esp + 8 + 28]	# get socket from pushad,call,call
	mov	eax, [ebp + 28]		# get socket from pushad @ ebp (eax = top dword)
	DEBUG_DWORD eax, "sending using socket"
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	ret

#
# out: esi, ecx = packet to send
ssh_kex_init_makepacket:
	lea	edi, [ssh_packet_out + ssh_packet_payload]
	mov	al, SSH_MSG_KEXINIT
	stosb

	# add cookie: 16 random bytes
	.rept 4
	call	random	# TODO: defined in dhcp.s - move to lib
	stosd
	.endr

	# send kex algorithms
	# - diffie-hellman-group1-sha1	REQUIRED
	# - diffie-hellman-group14-sha1 REQUIRED
	LOAD_TXT "diffie-hellman-group1-sha1", esi, eax, 1
	mov	ecx, eax
	bswap	eax
	stosd
	rep	movsb

	# send server hostkey algorithms
	# - ssh-dss REQUIRED
	# - ssh-rsa RECOMMMENDED
	#LOAD_TXT "ssh-rsa,ssh-dss", esi, eax, 1
	LOAD_TXT "ssh-rsa", esi, eax, 1
	mov	ecx, eax
	bswap	eax
	stosd
	rep	movsb

	# send client to server cipher
	# 3des-cbc REQUIRED
	# aes-128-cbc RECOMMENDED
	#LOAD_TXT "aes128-ctr,aes192-ctr,aes256-ctr,arcfour256,arcfour128,aes128-cbc,3des-cbc,blowfish-cbc,aes192-cbc,aes256-cbc,arcfour", esi, eax, 1
	LOAD_TXT "aes128-cbc", esi, eax, 1
	mov	ecx, eax
	bswap	eax
	push_	ecx esi
	stosd
	rep	movsb
	pop_	esi ecx
	# send server to client cipher
	stosd
	rep	movsb

	# send client to server mac algorithms
	#LOAD_TXT "hmac-md5,hmac-sha1,hmac-sha2-512,hmac-sha1-96,hmac-md5-96", esi, eax, 1
	LOAD_TXT "hmac-sha1", esi, eax, 1
	mov	ecx, eax
	bswap	eax
	push_	ecx esi
	stosd
	rep	movsb
	pop_	esi ecx
	# send server to client mac algorithms
	stosd
	rep	movsb

	# send client to server compression
	#LOAD_TXT "none,zlib", esi, eax, 1 #TODO: when enabled, add 'rep' below!
	LOAD_TXT "none", esi, eax, 1
	bswap	eax
	stosd
	movsd
	# send server to client compression
	stosd
	sub	esi, 4
	movsd

	# send client to server lang
	xor	eax, eax
	stosd
	# send server to client lang
	stosd

	# reserved trailing bytes:
	xor	eax, eax
	stosb	# kex first packet follows
	stosd	# reserved

	mov	ecx, edi
	mov	esi, offset ssh_packet_out + ssh_packet_payload
	sub	ecx, esi
	ret




sshd_parse_kexdh_init:	# state 2: KEXDH_INIT
	mov	dl, [esi + ssh_packet_payload]
	cmp	dl, SSH_MSG_KEXDH_INIT
	jz	1f
	printc 12, "SSH error: expect KEXDH_INIT, got "
	call	printhex2
	call	newline
	stc
	ret

1:	printlnc 11, "SSH rx KEXDH_INIT"

	# network packet len: 144 bytes
	# payload len: 140 bytes
	# padding: 5
	# Therefore:
	#
	# packet: .space 144
	#   header:     .space 5
	#   .long 140	# payload len (139) + padlen byte (1)
	#   .byte 5	# padlen
	#   payload:  	.space 134 (139-5)
	#     msgid:      .byte KEXDH_INIT
	#     mpint e:    .space 133   (.long len; .space len; see mpint encoding below)
	#   padding:    .space 5
	#
	# mpint encoding:
	#
	# IF mpint[0] & 0x80 == 0
	#  .long bytes
	#  .space bytes
	# ELSE
	#  .long bytes+1
	#  .byte 0
	#  .space bytes
	# ENDIF
	#
	# In case high bit of mpint value is set it is prefixed with 5 bytes,
	# otherwise 4 bytes. For 1024 bits (128 bytes) this results in either
	# a padding of 5 bytes (for the 5 byte prefix) or 6 bytes (when mpint
	# is 4 + 128 bytes).


	mov	edx, ecx
	print "NET packet len: "
	call	printdec32;	pushcolor 8; call printhex8; popcolor

	mov	edx, [esi + ssh_packet_len]
	print "packet len: "
	bswap	edx
	call	printdec32; pushcolor 8; call printhex8; popcolor
	print "padding len: "
	movzx	edx, byte ptr [esi + ssh_packet_padlen]
	call	printdec32
	call	newline


	mov	edi, esi	# backup esi (packet start)
	mov	ecx, [esi + ssh_packet_len]
	bswap	ecx
	DEBUG_DWORD ecx	# 0x8c (140)
	dec	ecx		# -1 (padlen byte)
	sub	ecx, edx	# -padlen
	DEBUG_DWORD ecx	# 0x85 (133)

	add	esi, offset ssh_packet_payload
	mov	dl, [esi]
	inc	esi
	DEBUG_BYTE dl, "msgtype(1e?)"

	lodsd	# get mpint size
	bswap	eax
	DEBUG_DWORD eax, "mpintsize"

	sub	ecx, 1 + 4	# message id (1) + mpintsize (4)
	cmp	ecx, eax
	jnz	91f

	call	newline
	printc 13, "client DH mpint e: "

0:	mov	dl, [esi]
	inc	esi
	call	printhex2
	loop	0b
	call	newline

	# RESPONSE

	# KEX DH:
	#
	# 1) C generates random number x (1<x<q)
	#    and computes  e = g^x mod p
	#    and sends e to S.
	# This is the packet parsed above.
	#
	# 2) S generates random number y (0<y<q)
	call	ssh_gen_rand	# XXX q = order of subgroup=?? (for now: q=2048 bits)
	#    and computes  f = g^y mod p.
	call	ssh_calc_f	# TODO: 
	#    S receives e (see above).
	#    S computes:
	#       K = e^y mod p
	#       H = HASH( V_C || V_S || I_C || K_S || e || f || K )
	#       signature s on H with private host key.
	#    S sends ( K_S || f || s ) to C.
	#
	# 3) C verifies K_S is for S (local database)
	#    C computes
	#        K = f^x mod p
	#        H = HASH( V_C || ... (same as S))
	#        and verifies signature s on H.
	#
	# LEGEND:
	#   C:   client
	#   S:   server
	#   p:   large safe prime
	#   g:   generator for subgroup GF(p)
	#   q:   order of the subgroup
	#   V_S: S's identification string
	#   V_C: C's identification string
	#   K_S: S's public host key
	#   I_C: C's SSH_MSG_KEXINIT message
	#   I_S: S's SSH_MSG_KEXINIT message

	#
	# a) generate random number y between 0 and q.
	#

	# Now we must send KEXDH_REPLY.
	#
	# Format:
	#


	call	ssh_kexdh_reply_makepacket
	call	ssh_send_packet
	clc
	ret

91:	printlnc 14, "SSH error: KEXDH mpint size exceeds packet len!"
	stc
	ret

# generate random number y 
.data
ssh_dh_y: .space 256	# rsa 2048 bit
ssh_dh_f: .space 256
.text32
ssh_gen_rand:
	mov	edi, offset ssh_dh_y
	mov	ecx, 256/4
0:	call	random
	stosd
	loop	0b
	ret

# calculate f = g^y mod p
ssh_calc_f:
	mov	esi, offset ssh_dh_y
	mov	edi, offset ssh_dh_f
	mov	ecx, 256/4

	ret

# ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-rsa -c aes128-cbc -m hmac-sha1 HOST
#
# server KEXDH_REPLY:
#
# packet len: 0x700
# padding len: 8
# msg_code: 0x31 (DH KEX DH REPLY)
# dh mod (p):	# server host key K_S
#   mp_int_len: .long 279  # 4+7 + 4+3 + 4+1+256
#   .long 7; .ascii "ssh-rsa"
#   .long 3; .byte 1,0,1
#   .long 0x101; .byte 0; .space 256 (2048 bits)
# dh base (g):	# public f (g^y mod p)
#   mp_int_len: .long 128; .space 128
# signature:
#   .long 0x10f (256 + 15)
#     .long 7; .ascii "ssh-rsa"
#     .long 0x100; .space 256

.data
#ssh_server_host_key:
#ssh_server_host_key_name_len:	.long 7 << 24	# network byte order (nbo)
#ssh_server_host_key_name:	.ascii "ssh-rsa"# server host key algorithm
#ssh_server_host_key_b_len:	.long 3 << 24	#
#ssh_server_host_key_b_data:	.byte 1,0,1	# unsure
#ssh_server_host_key_key_len:	.long 256	# XXX bswap! also see XXX next line
#ssh_server_host_key_key_data:	.space 256	# XXX might be 1 more if high bit is 1
#ssh_server_host_key_end:

# ssh rsa signature:
# .long 0x100 + 15
# .long 7; .ascii "ssh-rsa"
# .space 0x100

ssh_server_host_key_rsa:	.space 256	# 2048 bit key

ssh_server_f:		.space 128	# TODO: threadlocal
ssh_server_f_end:	

ssh_server_H_sig:	.space 256	# XXX during DH KEX reply this is RSA signature; HMAC-SHA1 (sha1 = 20 bytes = 160 bits)
ssh_server_H_sig_end:
.text32

# out: esi, ecx = packet to send
ssh_kexdh_reply_makepacket:
	lea	edi, [ssh_packet_out + ssh_packet_payload]
	mov	al, SSH_MSG_KEXDH_REPLY
	stosb

# string K_S (server public host key and certificates)  (DH modulus (P))
	mov	ebx, edi	# backup block start (size field)
	add	edi, 4		# skip block len, fill in later
	# server host key algorithm
	LOAD_TXT "ssh-rsa", esi, eax, 1	
	mov	ecx, eax
	bswap	eax
	stosd
	rep	movsb
	# ssh-rsa data:
	# first the .long 3; .byte 1,0,1 (flags?)
	mov	eax, 3
	bswap	eax
	stosd
	mov	al, 1
	stosb
	dec	al
	stosb
	inc	al
	stosb
	# rsa key (length: 256 bytes/2048 bits)
	mov	esi, offset ssh_server_host_key_rsa
	mov	eax, 256
	call	ssh_packet_put_key

	# now we must update [ebx] with the length of the appended data
	lea	eax, [edi-4]	# -4 is to subtract the length of the block size field
	sub	eax, ebx
	bswap	eax
	mov	[ebx], eax

# mpint f (DH base (G))
	mov	esi, offset ssh_server_f
	mov	eax, ssh_server_f_end - ssh_server_f
	call	ssh_packet_put_key

# signature of H
	# again, rsa signature of 256 bytes/2048 bits
	mov	ebx, edi
	stosd	# skip for later
	LOAD_TXT "ssh-rsa", esi, eax, 1
	mov	ecx, eax
	bswap	eax
	stosd
	rep	movsb
	mov	esi, offset ssh_server_H_sig
	mov	eax, ssh_server_H_sig_end - ssh_server_H_sig
	call	ssh_packet_put_key	# .long 256; .space 256 (with 0x80 adjust)
	# update signature length field
	lea	eax, [edi -4] # -4 = correction for length field
	sub	eax, ebx
	bswap	eax
	mov	[ebx], eax

	mov	ecx, edi
	mov	esi, offset ssh_packet_out + ssh_packet_payload
	sub	ecx, esi
	ret


###########################################################################
# ssh packet utility functions

# in: esi = key
# in: eax = key len
# in: edi = pointer in packet
# destroys: ecx, eax
# out: esi += eax
# out: edi += eax + 4 + 1?
ssh_packet_put_key:
	mov	ecx, eax
	testb	[esi], 0x80
	jz	1f
	inc	eax
	bswap	eax
	stosd
	xor	al, al
	stosb
	jmp	2f	# TODO: compare opcode len  'jmp 2f' against 'rep movsb;ret'

1:	bswap	eax
	stosd
2:	mov	al, cl
	shr	ecx, 2
	rep	movsd
	# this probably never occurs with keylengths power of 2
	mov	cl, al
	and	cl, 3
	rep	movsb
	ret


###########################################################################
# CRYPTO: HMAC
#
# RFC2104
#
#   H(K XOR opad, H(K XOR ipad, text))
#
# where
#	H = cryptographic hash function
#	opad = 0x5c repeated B times
#	ipad = 0x36 repeated B times
#		B = block len (64 bytes)
#	K = secret key, max len B, min (recomm) len = L
#		if K.len > b then K = H(K) (len=L)
#	L = hash length (MD5: 16; SHA1: 20)
#
# algorithm: (each step's outcome is used in the next step as
#             the missing argument/operand)
#
# 1) zero-pad K to len B -> Kpad
# 2) Kpad XOR ipad
# 3) append text
# 4) apply H -> H1
# 5) Kpad XOR opad
# 6) append H1
# 7) apply H
#
#   H(K XOR opad, H(K XOR ipad, text))
#
# So basically: , means concat, or, use as initial value for hash;
# and K is zero-padded to B.

# in: esi = data
# in: ecx = data len
# in: eax = key pointer
# in: edi = output hash pointer
hmac_sha1:
	mov	edx, offset sha1
	add	edx, [realsegflat]
	# fallthrough

# in: esi = data
# in: ecx = data len
# in: eax = key pointer [blocklen len: 64 bytes]
# in: ebx = key len
# in: edx = hash code pointer
# in: edi = output hash pointer (must be hashlen L, say 20 bytes)
# hardcoded: blocklen = 64 bytes.
hmac:
	push_	ebp ecx edi eax esi
	mov	ebp, esp

	# 1) pad key
	push_	ecx eax
	mov	ecx, 64
	sub	ecx, ebx
	mov	edi, eax
	xor	eax, eax
	rep	stosb	# todo: optimize
	pop_	eax ecx

	# 2), 5) calc ipad, opad keys
	sub	esp, 64 + 64
	mov	edi, esp	# ipad (and +64 = opad)
	mov	ecx, 64
	mov	esi, eax	# key
0:	lodsb
	mov	ah, al
	xor	al, 0x36	# ipad
	xor	ah, 0x5c	# opad
	mov	[edi + 64], ah
	stosb
	loop	0b

#   H(K XOR opad,   H(K XOR ipad,   text))
#   H(esp[64..127], H(esp[0..63], [ebp]..[ebp+[ebp+16]]))

	# 3), 4) calc hash over Kipad, text
	sub	esp, 360	# alloc sha1 state buffer
	mov	ebx, esp	# scratch buffer, sha state
	call	sha1_init	# process first block; out: ebx buffer updated.
	mov	esi, esp	# ipadded key
	mov	ecx, 64
	call	sha1_next
	mov	esi, [ebp]
	mov	ecx, [ebp + 16]
	call	sha1_next	# updates [ebx]
	call	sha1_finish	# stores hash in [edi]

	mov	esp, ebp
	pop_	esi eax edi ecx ebp
	ret

#######################
# CRYPTO: DHG1 diffie-hellman-group1-sha1 (TODO)

.include "../lib/aes.s"
