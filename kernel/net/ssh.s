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
	KAPI_CALL schedule_task
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
	push_	ecx esi eax
0:	lodsb
	call	printchar
	loop	0b
	call	newline
	pop_	eax esi ecx

	cmp	byte ptr [sshc_state], SSH_STATE_CLIENT_PROTOCOL
	jz	0f
	cmp	byte ptr [sshc_state], SSH_STATE_KEX_INIT
	jz	1f
	cmp	byte ptr [sshc_state], SSH_STATE_KEXDH_INIT
	jz	2f

	printlnc 12, "sshd: unimplemented state, ignoring"
	jmp	9f

0:	# state 0: client protocol
	printlnc 10, "SSH Client protocol received";
	inc	byte ptr [sshc_state]
	jmp	9f

1:	# state 1: KEX INIT (key exchange)

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
	jmp	9f

####################
2:	# state 2: KEXDH_INIT
	printlnc 11, "ssh: todo: KEXDH_INIT"
	jmp	9f




9:	clc
	ret

98:	printlnc 5, "ssh: algorithm list too large";
	jmp 1f
99:	printlnc 4, "ssh: negative size"
1:	stc
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
SSH_MSG_KEXDH_INIT = 30;
SSH_MSG_KEXDH_REPLY = 31;

# dh-group-exchange
SSH_MSG_KEX_DH_GEX_REQUEST_OLD = 30;
SSH_MSG_KEX_DH_GEX_GROUP = 31;
SSH_MSG_KEX_DH_GEX_INIT = 32;
SSH_MSG_KEX_DH_GEX_REPLY = 33;
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
	.space 1024
.text32

# called when kex_init is received
# all registers free.
# [esp] = return to within sshd_parse
# [esp + 4] = return to sshd_client
# [esp + 8...] = pushad
ssh_kex_init_send:
	call	ssh_kex_init_makepacket
	# esi = ssh_packet_payload
	# ecx = payload len
	# edi = end of payload

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

	mov	eax, [esp + 8 + 28]	# get socket from pushad,call,call
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
	LOAD_TXT "ssh-rsa,ssh-dss", esi, eax, 1
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
