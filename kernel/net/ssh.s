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
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_RING_SERVICE	# context switch task
	push	cs
	push	dword ptr offset net_service_sshd_main
	call	schedule_task
	jc	9f
	OK
9:	ret

net_service_sshd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 22
	mov	ebx, SOCK_LISTEN
	call	socket_open
	jc	9f
	printc 11, "SSH Daemon listening on "
	call	socket_print
	call	newline

0:	mov	ecx, 10000
	call	socket_accept
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
	push	dword ptr offset 1f
	call	schedule_task
	ret

.data
SSH_STATE_CLIENT_PROTOCOL= 0;
SSH_STATE_KEX_INIT	 = 1;
sshc_state: .byte 0;
.text32

1:	lock inc word ptr [sshd_num_clients]

	mov	byte ptr [sshc_state], SSH_STATE_CLIENT_PROTOCOL

	printc 11, "SSH connection: "
	call	socket_print
	call	newline


	LOAD_TXT "SSH-2.0-QuRe_SSHD_0.1\r\n"
	call	strlen_
	call	socket_write
	call	socket_flush

0:	mov	ecx, 10000
	call	socket_read
	jc	9f
	pushad
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
	#call	socket_write
	call	socket_flush
	call	socket_close
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
	inc	byte ptr [sshc_state]
	jmp	9f


9:	clc
	ret

99:	printlnc 4, "ssh: negative size"
	stc
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
