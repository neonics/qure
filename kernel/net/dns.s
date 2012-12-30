###############################################################################
# DNS
#
# RFC 1035
#
.intel_syntax noprefix

NET_DNS_DEBUG = 0	# 1 = log requests; 2 = more extensive debug

DNS_MAX_NAME_LEN = 80

# Messages over UDP follow the below format.
# Messages over TCP are prefixed with a word indicating the message length,
# not counting the word.
.struct 0	# max UDP payload len: 512 bytes
dns_tid:	.word 0	# transaction id
dns_flags:	.word 0	# 0001 = standard query (0100)
	DNS_FLAG_QR		= (1 << 15)	# 0=query, 1=response
	DNS_OPCODE_SHIFT	= 11
	DNS_OPCODE_MASK 	= (0b1111 << DNS_OPCODE_SHIFT)
	DNS_OPCODE_STDQ		= (0 << DNS_OPCODE_SHIFT)	# std query
	DNS_OPCODE_IQUERY	= (1 << DNS_OPCODE_SHIFT)	# inverse query
	DNS_OPCODE_STATUS	= (2 << DNS_OPCODE_SHIFT)	# server status request
	DNS_FLAG_AA		= (1 << 10)	# (R) authoritative answer
	DNS_FLAG_TC		= (1 << 9)	# (Q,R) truncation
	DNS_FLAG_RD		= (1 << 8)	# (Q->R) recursion desired
	DNS_FLAG_RA		= (1 << 7)	# (A) recursion avail
	DNS_FLAG_Z		= (0b110 << 4)	# reserved
	DNS_FLAG_NO_AUTH_ACCEPT	= (1 << 4) # non-authenticated data: 0=unacceptbl
	DNS_RCODE_SHIFT		= 0
	DNS_RCODE_MASK		= 0b1111	# (R)
	DNS_RCODE_OK		= 0		# no error
	DNS_RCODE_FORMAT_ERR	= 1		# server unable to interpret
	DNS_RCODE_SERVER_FAIL	= 2		# problem with name server
	DNS_RCODE_NAME_ERR	= 3		# (auth ns): name doesn't exist
	DNS_RCODE_NOT_IMPL	= 4		# query kind not implemented
	DNS_RCODE_REFUSED	= 5		# policy restriction


dns_questions:	.word 0	# nr of questions
dns_answer_rr:	.word 0	# answer RRs
dns_auth_rr:	.word 0	# authorit RRs
dns_add_rr:	.word 0	# additional RRs
dns_queries:	# questions, answers, ...

# Question format:
# QNAME: seq of labels (pascal style), zero label term
# QTYPE: word; QCLASS: word
#
# Example: format for 'foo.nl' IN A request:
# .byte 3 'foo' 2 'nl' 0
# .word type	# 0001 = A
# .word class	# 0001 = IN

# RR (resource record) format: answer, authority, additional:
# NAME: domain name to which this record pertains
# TYPE: word: DNS_TYPE_..
# CLASS: word: DNS_CLASS_..
# TTL: dword: seconds
# RDLEN: word: length in bytes of RDATA
# RDATA: resource data depending on TYPE and CLASS; for IN A, 4 byte IPv4 addr.
#
# Compression: word [11 | OFFSET ]
# domain name labels can be compressed: a word, high 2 bits 1,
# refers to a prior occurrence.
# Since labels must be < 64 len, 01xxxxxx/10xxxxxxxx (reserved), 11xxxxxx
# indicates reference.
# The offset is relative to the DNS payload frame (i.e. offset 0 is first
# byte of dns_tid).
# Valid names:
# - sequence of labels, zero octet terminated (root: no labels, zero octet)
# - a pointer
# - sequence of labels ending with pointer

DNS_TYPE_A	= 1	# host address
DNS_TYPE_NS	= 2	# authoritative name server
# MD=3, mail destination; MF = 4, mail forwarder: both obsolete, use MX
DNS_TYPE_CNAME	= 5	# canonical name for alias
DNS_TYPE_SOA	= 6	# start of zone of authority
# experimental: MB=7, mailbox domain
# experimental: MG=8, mail group member
# experimental: MR=9, mail rename domain
# experimental: NULL = 10 - null RR
DNS_TYPE_WKS	= 11	# well-known service description
DNS_TYPE_PTR	= 12	# domain name pointer
DNS_TYPE_HINFO	= 13	# host information
DNS_TYPE_MINFO	= 14	# mailbox or mail list information
DNS_TYPE_MX	= 15	# mail exchange
DNS_TYPE_TXT	= 16	# text strings
DNS_TYPE_AAAA	= 28	# 1c: ipv6 address
DNS_TYPE_OPT	= 41	# RFC 2671

# Reverse dns lookup: <ip>.in-addr.arpa, PTR (TODO: check ip reversed?)

# QTYPE is superset of TYPE: query type, in question part of query:
DNS_QTYPE_AXFR	= 252	# request for transfer of entire zone
DNS_QTYPE_MAILB	= 253	# request for mailbox related records (MB, MG, MR)
DNS_QTYPE_MAILA	= 254	# request for mail agent RRs (obsolete, use MX)
DNS_QTYPE_ALL	= 255	# request for all records

# resource record class identifiers:
DNS_CLASS_IN	= 1	# internet
DNS_CLASS_CS	= 2	# CSNET class - obsolete
DNS_CLASS_CH	= 3	# CHAOS class
DNS_CLASS_HS	= 4	# Hesiod

# QCLASS, superset of CLASS: appear in question section of query
DNS_QCLASS_ALL	= 255	# any QCLASS

DNS_HEADER_SIZE = .

####################################################################
# construct a compact stringtable:
# .data SECTION_DATA_STRINGS contains zero terminated strings
# .data contains offsets relative to the start of of the stringtable
# NOTE: the number of strings (max idx) is not recorded!
.macro STRINGREF8_INIT label
	.data SECTION_DATA_STRINGS
	\label\()_str$:
		STRINGREF8_STR_BASE = .

	.data
	\label\()_idx$:
		STRINGREF8_IDX_BASE = .
.endm

.macro STRINGREF8 string
	.data SECTION_DATA_STRINGS
		STRINGREF8_STR_OFFS = . - STRINGREF8_STR_BASE
		.if STRINGREF8_STR_OFFS > 255
			.error "STRINGREF8: exceed byte limit"
		.endif
		.asciz "\string"
	.data
		.byte STRINGREF8_STR_OFFS
.endm

.macro STRINGREF8_FILL to
	.data
	.fill (\to - (. - STRINGREF8_IDX_BASE))
.endm

STRINGREF8_INIT dns_type_label
STRINGREF8 "<none>"	# 0
STRINGREF8 "A"		# 1
STRINGREF8 "NS"		# 2
STRINGREF8 "MD"		# 3
STRINGREF8 "MF"		# 4
STRINGREF8 "CNAME"	# 5
STRINGREF8 "SOA"	# 6
STRINGREF8 "MB"		# 7
STRINGREF8 "MG"		# 8
STRINGREF8 "MR"		# 9
STRINGREF8 "NULL"	# 10
STRINGREF8 "WKS"	# 11
STRINGREF8 "PTR"	# 12
STRINGREF8 "HINFO"	# 13
STRINGREF8 "MINFO"	# 14
STRINGREF8 "MX"		# 15
STRINGREF8 "TXT"	# 16
STRINGREF8_FILL to=DNS_TYPE_AAAA
STRINGREF8 "AAAA"	# 28
STRINGREF8_FILL to=DNS_TYPE_OPT
STRINGREF8 "OPT"	# 41

DNS_TYPE_LABEL_MAX = . - STRINGREF8_IDX_BASE

.data SECTION_DATA_STRINGS
dns_type_label_str_end$: 
.data
dns_type_label_idx_end$:

.purgem STRINGREF8
.purgem STRINGREF8_INIT
.purgem STRINGREF8_FILL
####################################################################

.text32
# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (udp frame)
# in: ecx = payload len
net_dns_print:
	push	edi
	push	esi
	push	edx
	push	ecx
	push	eax

#	test	byte ptr [esi + dns_flags], 0x80
#	jz	1f
#	DEBUG "Response"
#	# check pending requests

6:
	printc COLOR_PROTO, "   DNS "
	printc COLOR_PROTO_LOC, "tid "
	mov	dx, [esi + dns_tid]
	call	printhex4
	printc COLOR_PROTO_LOC, " flags "
	mov	dx, [esi + dns_flags]
	xchg	dl, dh
	call	printhex4
	call	printspace
	PRINTFLAG dx, DNS_FLAG_QR, "Q", "R"
	PRINTFLAG dx, DNS_FLAG_TC, "T", " "
	PRINTFLAG dx, DNS_FLAG_RD, "r", " "
	PRINTFLAG dx, DNS_FLAG_NO_AUTH_ACCEPT, "A", "U"
	and	dx, DNS_OPCODE_MASK
	shr	dx, DNS_OPCODE_SHIFT
	printc COLOR_PROTO_LOC, " op "
	call	printhex2

	printc COLOR_PROTO_LOC, " #Q "
	movzx	edx, word ptr [esi + dns_questions]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Ans RR "
	mov	dx, [esi + dns_answer_rr]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Auth RR "
	mov	dx, [esi + dns_auth_rr]
	xchg	dl, dh
	call	printdec32

	printc COLOR_PROTO_LOC, " #Addt RR "
	mov	dx, [esi + dns_add_rr]
	xchg	dl, dh
	call	printdec32
	call	newline


	mov	edi, esi	# remember dns frame
	add	esi, DNS_HEADER_SIZE

	mov	eax, ecx
	add	eax, edi
	push	eax	# end of packet
########
	movzx	ecx, word ptr [edi + dns_questions]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	printc COLOR_PROTO_LOC, "    Question:  "
	call	dns_print_question$
	pop	ecx
	jmp	0b
1:
########
	movzx	ecx, word ptr [edi + dns_answer_rr]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	printc COLOR_PROTO_LOC, "    Answer     "
	call	dns_print_answer$
	pop	ecx
	jmp	0b
1:
########
	movzx	ecx, word ptr [edi + dns_auth_rr]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	printc COLOR_PROTO_LOC, "    Auth       "
	call	dns_print_answer$
	pop	ecx
	jmp	0b
1:
########
	movzx	ecx, word ptr [edi + dns_add_rr]
	xchg	cl, ch

0:	cmp	esi, [esp]	# sanity check
	jae	1f
	dec	ecx
	jl	1f
	push	ecx
	call	dns_print_addit$
	pop	ecx
	jmp	0b
1:
	pop	eax	# end of packet
########
	pop	eax
	pop	ecx
	pop	edx
	pop	esi
	pop	edi
	ret

# in: edi = dns frame
# in: esi = question start
dns_print_question$:
	call	dns_print_name$
	print " type "
	call	dns_print_type_$
	print " class "
	call	dns_print_class_$
	call	newline
	ret

# in: esi = points to network byte order type
# destroys: ax, dx
# out: esi += 2
dns_print_class_$:
	lodsw
	xchg	al, ah
# in: ax = class number
# destroys: ax, dx
dns_print_class$:
	cmp	ax, 1
	jnz	1f
	print	"IN"
	ret

1:	mov	dx, ax
	call	printhex4
	ret

# in: esi = points to network byte order type
# destroys: eax, dx
# out: esi += 2
dns_print_type_$:
	lodsw
	xchg	al, ah
# in: ax = type number
# destroys: eax, dx
dns_print_type$:
	cmp	ax, DNS_TYPE_LABEL_MAX	# by definition < 255
	jae	1f

	movzx	eax, ax
	push	esi
	movzx	esi, byte ptr [dns_type_label_idx$ + eax]
	add	esi, offset dns_type_label_str$
	call	print
	pop	esi
	ret

1:	mov	dx, ax
	call	printhex4
	ret


# in: edi = dns frame
# in: esi = answer start
dns_print_answer$:
	call	dns_print_name$

	print " type "
	lodsw
	mov	dx, ax
	xchg	dl, dh
	call	printhex4

	print " class "
	lodsw
	mov	dx, ax
	xchg	dl, dh
	call	printhex4

	print " ttl "
	lodsd
	bswap	eax
	mov	edx, eax
	call	printdec32

	print " len "
	xor	eax, eax
	lodsw
	xchg	al, ah
	cmp	ax, 4	# ipv4
	jnz	1f
	lodsd
	call	net_print_ip
	call	newline
	ret

1:	mov	ecx, eax
0:	lodsb
	movzx	edx, al
	call	printdec32
	mov	al, ':'
	call	printchar
	loop	0b
	call	newline
	ret

# in: edi = dns frame
# in: esi = additional RR start
dns_print_addit$:
	#printc COLOR_PROTO_LOC, "    Additional "
	# TODO
	ret

# in: ebx = dns frame
# in: esi = name start
dns_print_name$:
	xor	eax, eax
	lodsb	# length of text segment (domain name part)
1:	cmp	al, 0b11000000
	jb	2f
	# handle ref
	mov	ah, al
	and	ah, 0b00111111
	lodsb
	push	esi
	lea	esi, [ebx + eax]
	call	dns_print_name$
	pop	esi
3:	ret	# name ref is always last element in name

2:	movzx	ecx, al
	jecxz	3b
0:	lodsb
	call	printchar
	loop	0b
	printchar_ '.'

	lodsb
	or	al, al
	jnz	1b
	ret


# in: ebx = dns frame (for name references)
# in: esi = RR ptr in DNS message - label
# in: edi = ptr to buffer to contain domain name
# in: ebp = end of buffer (convenience: edi -> stack)
# in: ecx = dns frame remaining size
# out: esi = end of RR label
# out: edi = end of name or edi & 0xff == DNS_RCODE_*
# out: CF = 0: ok; CF = 1: error: edi = error code
dns_parse_name$:
	push	eax
	push	edx
	push	ecx
	mov	edx, ecx	# remaining frame len

0:	lodsb
	cmp	al, 0b1100000
	jae	2f

	movzx	ecx, al
	jecxz	1f

	dec	edx
	mov	al, DNS_RCODE_FORMAT_ERR
	jz	91f

	# source frame verify:
	cmp	ecx, edx	# jb=ok, je = ok, ja = err
	ja	91f
	sub	edx, ecx	# incorporate rep movsb effect

	# stack verify:
	lea	eax, [ecx + edi]
	cmp	eax, ebp
	mov	al, DNS_RCODE_SERVER_FAIL
	jae	91f

	rep	movsb
	mov	al, '.'
	stosb
	jmp	0b

1:	stosb
8:	clc
9:	pop	ecx
	pop	edx
	pop	eax
	ret
91:	stc
	mov	edi, eax	# error code
	jmp	9b

# handle ref
2:	sub	edx, 2
	jl	91b
	and	eax, 0b00111111
	mov	ah, al
	lodsb
	cmp	eax, 511	# sanity check: frame len per spec
	mov	al, DNS_RCODE_FORMAT_ERR
	jae	91b		# ref beyond packet size
	push	esi
	push	ecx
	mov	ecx, edx
	lea	esi, [ebx + eax]
	call	dns_parse_name$
	pop	ecx
	pop	esi
	jc	91b
	jmp	9b		# ref is last, so, done

#############################################################################
# in: ebx = nic
# in: edx = ipv4 frame
# in: eax = udp frame
# in: esi = payload: dns frame
# in: ecx = payload len
net_dns_service:
	cmp	ecx, DNS_HEADER_SIZE
	jb	10f	# short packet
	test	[esi + dns_flags], byte ptr DNS_FLAG_QR >> 8
	jnz	10f	# no query: no response.

	.if NET_DNS_DEBUG
		PRINT "Servicing DNS request from "
		push	eax
		mov	eax, [edx + ipv4_src]
		call	net_print_ip
		pop	eax
		call	newline
		call	net_dns_print
	.endif

	NET_BUFFER_GET	# out: edi
	push	edi	# response packet start

	add	edi, ETH_HEADER_SIZE + IPV4_HEADER_SIZE + UDP_HEADER_SIZE
	mov	ebx, edi	# remember payload start
	call	dns_put_response
	mov	ecx, edi
	sub	ecx, ebx	# response payload size

	push	edi	# [esp + 0]: payload end
	mov	edi, [esp + 4]	# packet start

	xchg	eax, edx
	mov	eax, [eax + ipv4_src]
	mov	edx, [edx + udp_sport]
	call	net_put_eth_ipv4_udp_headers	# restores ebx
	# assert edi == [esp + 4]
	pop	edi	# payload end
	jc	9f
	pop	esi	# packet start
	NET_BUFFER_SEND	# in: ebx=nic,edi=packet end,esi=packet start
	ret

9:	pop	edi	# packet start
	printlnc 4, "error constructing response packet"
	# TODO: net_buffer_release
10:	ret


# in: edi = dns response frame start
# in: esi = dns request frame (DNS_FLAG_QR is already verified to be 0)
# in: ecx = dns request frame length
# out: edi = end of response packet
# out: CF = 0: all ok
dns_put_response:
	push	eax
	push	ebx
	push	edx

	mov	edx, edi	# remember dns response frame start
	mov	ebx, esi	# remember dns request frame start
	call	dns_process_header$
	jc	9f	# no dns payload beyond header
	# questions are present
	sub	ecx, DNS_HEADER_SIZE
	jz	91f	# too short to contain questions
	##################
	# challenge #
	#
	# the questions in the request may or may not be followed
	# by authRR/addRR.
	#
	# Processing questions:
	# 1) copy questions to response packet
	# 2) append answers to response packet
	#
	# assuming there is more than 1 question, the offset of the answer
	# is not yet known.
	#
	# Solution 1: copy entire question packet, and append at end,
	#  and then remove all data between questions and answers (auth/addRR)
	#   con: requires 3 passes (movsb, parse, movsb)
	#
	# Solution 2: scan questions first to get their size.
	#   con: requires two parsing methods
	#   con: requires two parses
	#   pro: generalize parsing method: iterator and parameterized handler
	#   pro: exact length known
	#   con: exact len not needed when auth/add RR entries will end up
	#
	# Solution 3: have two target pointers, receiving q and a.
	#   pro: single-pass if all request payload ends up in response
	#   con: requires memory move to clear the gap between q end/a start.
	#
	# Request packet restrictions and possibilities:
	#   condition: questions > 0
	#	up to here, request payload = response payload
	#   condition: answers = 0
	#	response payload injects data: overwrites auth/addt.
	#   possibility: auth rr > 0
	#	
	#   possibility: addt rr > 0
	#
	# hybrid solution:
	#   auth/add = 0: solution 3 (no con)
	#   
	##################

	
	# process questions
	movzx	eax, word ptr [ebx + dns_questions]
	xchg	al, ah
	jmp	1f
0:	push	eax
	call	dns_process_question$
	jc	92f
	pop	eax

1:	dec	eax
	jnl	0b
	clc

9:	pop	edx
	pop	ebx
	pop	eax
	ret

91:	mov	[edx + dns_flags + 1], byte ptr DNS_RCODE_FORMAT_ERR
	jmp	9b
92:	# process question fail
	mov	[edx + dns_flags + 1], al
	pop	eax
	jmp	9b

# verifies request header and constructs response header
# in: edx = response dns frame
# in: ebx = request dns frame
# out: edi = end of response header
# out: esi = end of request header or (esi-2) = error in header
# out: CF = 1: header response only
dns_process_header$:
	# verify dns frame len

	movsw	# dns_tid
# 2,2
	# process in network-byte-order (flags defined in native order)
	# optimized no jumps for correct packets
	lodsw	# dns_flags
	
	and	ax, (DNS_FLAG_QR | DNS_OPCODE_MASK) >> 8 # no other flags supp.
# 4,4
	or	al, al	# check opcode type: only DNS_OPCODE_STDQ impl
	jnz	91f	# not impl
	or	al, DNS_FLAG_QR >> 8	# was guaranteed to be 0
	stosw

	# dns_questions
	lodsw
# 6,4
	or	ax, ax	# verify questions not empty
	jz	92f
	xor	ax, ax	# store 0 questions - update as we go
	stosw
# 6,6
	# dns answers
	lodsw
# 8,6
	or	ax, ax	# verity answers empty
	jnz	93f
	stosw
# 8,8
	# dns_auth_rr, dns_add_rr
	add	esi, 4	# ignore auth/additional (not implemented)
	xor	eax, eax
	stosd	# dns_auth_rr, dns_add_rr
# 12,12
	clc
	ret

#########################
91:	# invalid opcode; 4,4
DEBUG_BYTE al, "invalid opcode"
	xor	eax, eax	# zero out the rest of the header
	stosd	# 4,8
	stosd	# 4,12
	mov	al, DNS_RCODE_NOT_IMPL
9:	mov	[edx + dns_flags + 1], al
	stc	# dont process beyond header
	ret

92:	# no questions; ax=0; 6,4
DEBUG "no questions"
	stosw	# 6,6 [93: 8,6]
1:	stosw	# 6,8
	mov	al, DNS_RCODE_FORMAT_ERR
	jmp	9b

93:	# answers != 0; ax>0; 8,6
DEBUG "answers !=0"
	xor	ax, ax
	jmp	1b

# This method will parse/verify/copy the question, resolve it,
# and append the respons to the output packet's end as per the size
# of the input packet.
# In the case of 1 question:
#  invariant:
#  - esi + ecx points to end of request packet
#  - edi + ecx points to end of response packet
#  - edi + ecx points to the start of the answers
#  precondition:
#  - edi = edx + DNS_HEADER_SIZE (+question offset)
#  - esi = ebx + DNS_HEADER_SIZE (+question offset)
#  - ecx = request packet len - DNS_HEADER_SIZE (-question offset)
#  postcondition:
#  - esi will point to the end of the questions
#  - edi will point to the end of the questions
#  - ecx -= question size (in case of 1 question and no other RR's, ecx=0)
#
# in: edi = response dns payload
# in: edx = response dns frame
# in: esi = request dns payload (question)
# in: ebx = request dns frame
# in: ecx = payload size ( >0 )
# out: eax = end of response packet, or al = DNS_RCODE_*
# out: CF = 1: short packet
dns_process_question$:
	push	edx
	push	ebx

	mov	ebx, edi	# start of answer, if any
	sub	ebx, edx	# make relative offset for answer reference

	# dns_parse_name$: (* means updated)
	# in: ebx = dns frame (for name references)
	# in: esi*= RR ptr in DNS message - label
	# in: edi*= ptr to buffer to contain domain name
	# in: ebp = end of buffer (convenience: edi -> stack)
	push	esi
	push	ebp
	mov	ebp, esp
	sub	esp, DNS_MAX_NAME_LEN	

	push	edi
	lea	edi, [esp + 4]
	call	dns_parse_name$
	pop	edi	# ignore result edi, as string is 0 terminated
	jc	91f	# parse error/name to long

	# name parsed ok, copy to output packet:
	push	ecx
	mov	ecx, esi
	mov	esi, [ebp + 4]	# start of name
	sub	ecx, esi
	sub	[esp], ecx	# reduce packet len
	rep	movsb		# assert esi == [ebp + 4]
	mov	cx, [edx + dns_questions]
	add	ch, 1
	adc	cl, 0
	mov	[edx + dns_questions], cx
	pop	ecx

	.if NET_DNS_DEBUG > 1
		push	esi
		push	ecx
		print_ "name: "
		lea	esi, [esp + 8]
		mov	ecx, DNS_MAX_NAME_LEN
		call	nprint
		call	printspace
		pop	ecx
		pop	esi
	.endif

	# parse rest of question RR:
	lodsd	# type, class
	stosd
	bswap	eax	# ax=class, eax.h = type
	cmp	ax, DNS_CLASS_IN
	jnz	91f	# class not IN: no answer for this one.

	ror	eax, 16
	.if NET_DNS_DEBUG > 1
		push	eax
		push	edx
		print	"IN "
		call	dns_print_type$
		pop	edx
		pop	eax
	.endif

	# handle request:
	# ax = type
	push	esi
	lea	esi, [esp + 4]	# plain name
	call	dns_answer_question$	# in: eax, esi, edi, edx, ebx; out: edi
	pop	esi
	jc	91f

	mov	esp, ebp
	pop	ebp
	add	esp, 4	# pop esi - start of name
	clc

0:	pop	ebx
	pop	edx
	ret

91:	# name error: al is DNS_RCODE
	mov	esp, ebp
	pop	ebp
	add	esp, 4
	stc
	jmp	0b


# in: eax = DNS_CLASS_IN << 16 | DNS_TYPE_*
# in: esi = name
# in: edi = where to put answer
# in: edx = dns response frame
# in: ebx = dns response question RR relative offset
# out: CF = 0: answer appended to edi; CF = 1: no change, al = DNS_RCODE_
# out: edi = updated to end of answer
# destroys: eax, bx
dns_answer_question$:

	# verify name
	push	ecx
	push	esi
	push	edi
	call	strlen_
	inc	ecx
	LOAD_TXT "cloud.neonics.com.", edi
	repz	cmpsb
	pop	edi
	pop	esi
	pop	ecx
	jnz	91f

	cmp	ax, DNS_TYPE_AAAA
	jz	9f	# no answer
	cmp	ax, DNS_TYPE_MX
	jz	1f
	cmp	ax, DNS_TYPE_A
	jnz	9f	# no answer
1:
	#################################################
		.data SECTION_DATA_BSS
		internet_ip: .long 0
		.text32
		cmp	dword ptr [internet_ip], 0
		jnz	1f
		push	eax
		push	esi
		LOAD_TXT "cloudns.neonics.com"
		call	dns_resolve_name
		pop	esi
		or	eax, eax
		mov	[internet_ip], eax
		pop	eax
		jz	92f
	1:
	#################################################
	# eax = ip
	# esi = name
	# edx = response frame base
	# ebx = offset to label in response frame
	or	bh, 0b11000000
	xchg	bl, bh
	mov	[edi], bx	# name ref
	add	edi, 2

	push	eax
	ror	eax, 16
	bswap	eax
	stosd	# class, type
	mov	eax, 60	<<24 # 1 minute network byte order
	stosd	# ttl
	pop	eax

	cmp	ax, DNS_TYPE_MX
	mov	ax, 4 << 8
	jz	1f

	stosw	# data len
	mov	eax, [internet_ip]
	stosd	# ip
	
	# update nr of answers
0:	mov	ax, [edx + dns_answer_rr]
	add	ah, 1
	adc	al, 0
	mov	[edx + dns_answer_rr], ax
9:	clc
	ret

1:	# MX
	stosw	# data len: 4 (prio=2, nameref=2)
	mov	ax, 10 << 8
	stosw	# preference
	# refer to same name
	mov	ax, bx
	stosw
	jmp	0b


91:	.if NET_DNS_DEBUG > 1
	printlnc 4, "dns: unknown name"
	.endif
	mov	al, DNS_RCODE_NAME_ERR
	stc
	ret

92:;	.if NET_DNS_DEBUG > 1
		printlnc 4, "dns: cannot resolve"
	.endif
	mov	al, DNS_RCODE_SERVER_FAIL
	stc
	ret


# in: esi = domain name
# out: eax = ipv4 address
dns_resolve_name:
	# receives all dns packets....
	push	edx
	push	ebx
	mov	edx, IP_PROTOCOL_UDP << 16
	call	net_udp_port_get
	mov	dx, ax
	xor	eax, eax	# ip
	xor	ebx, ebx	# flags
	call	socket_open
	pop	ebx
	pop	edx
	jc	9f

	push	edi
	push	edx
	push	ecx
	push	ebx
	mov	edi, esi

	call	strlen_
	mov	edx, ecx
	call	net_dns_request

	mov	ecx, 2 * 1000
	call	socket_read	# in: eax, ecx; out: esi, ecx
	jc	8f

#	printlnc 11, "socket UDP read:"
	push	eax
#	call	net_dns_print

		add	esi, UDP_HEADER_SIZE
		sub	ecx, UDP_HEADER_SIZE

	#	push	esi

		# verify flag
		mov	ax, [esi + dns_flags]
		xchg	al, ah
		and	ax, DNS_FLAG_QR | DNS_RCODE_MASK
		cmp	ax, DNS_FLAG_QR
		jnz	1f
		# verify question/answer:
		cmp	dword ptr [esi + dns_questions], 0x01000100
		jnz	1f

		mov	ebx, esi	# in: ebx = dns frame (for name refs)
		add	esi, DNS_HEADER_SIZE # in: esi = RR ptr in DNS message
		push	ecx	# response data len (eth/ip/udp/dns frames)
		# in: ecx = dns frame remaining size
		sub	ecx, DNS_HEADER_SIZE
		push	edx	# len of name being looked up

		mov	edx, esi	# dns frame ptr

		# validate question
		push	edi
		push	ebp
		mov	ebp, esp # in: ebp = end of buffer
		sub	esp, DNS_MAX_NAME_LEN
		mov	edi, esp # in: edi = ptr to buffer to contain name

		push	edi
		call	dns_parse_name$	# in: edi, ebp; in: esi
		pop	edi
		jc	2f

		push	esi
		mov	esi, [ebp + 4]	# edi on stack=orig esi: name
		mov	ecx, [ebp + 8]	# edx on stack=orig ecx: name len
		repz	cmpsb
		pop	esi
		stc
		jnz	2f
		cmp	word ptr [edi], '.'
		stc
		jnz	2f
		clc

	2:	mov	esp, ebp
		pop	ebp
		pop	edi
		pop	ecx	# pop edx: orig name len; keep edx=question rr
		pop	ecx
		jc	1f
		lodsd	# load type/class
		cmp	eax, 0x01000100
		jnz	1f
		# parse answer

	######## compare answer rr name, type, class
		xor	eax, eax
		lodsb
		cmp	al, 0b11000000
		jb	2f
		# check if reference matches
		mov	ah, al
		and	ah, 0b00111111
		lodsb
		add	eax, ebx
		cmp	eax, edx	# question rr
		jnz	1f
		lodsd
		cmp	eax, 0x01000100	# type, class
		jnz	1f
		jmp	3f
	2:	# noncompressed name: compare RR with question RR
		push	edi
		push	ecx
		dec	esi	# unread byte
		mov	ecx, esi
		sub	ecx, edx	# start of question rr
		mov	edi, edx
		repz	cmpsb
		pop	ecx
		pop	edi
		jnz	1f
	3:
	########
		lodsd	# ttl - ignore
		lodsw	# addr len
		cmp	ax, 0x0400
		jnz	1f
		lodsd	# ip
		mov	edx, eax

		jmp	7f
	1:	printlnc 4, "DNS error: wrong response"
		xor	edx, edx
7:
	pop	eax

0:	call	socket_close
	mov	eax, edx
	.if NET_DNS_DEBUG > 1
		DEBUG_DWORD eax, "resolve: ip"
	.endif
	pop	ebx
	pop	ecx
	pop	edx
	pop	edi
	ret

8:	printlnc 4, "socket read timeout"
	xor	edx, edx
	jmp	0b

9:	printlnc 4, "failed to open UDP socket"
	xor	eax, eax
	ret

# in: eax = socket
# in: esi = name to resolve
# in: ecx = length of name
net_dns_request:
	.data
	dns_server_ip: .byte 192, 168, 1, 1
	.text32
	push	edi
	push	esi
	push	eax
	push	ebx
	push	ecx
	push	edx

	NET_BUFFER_GET
	push	edi

	# 6:
	# 1 byte trailing zero for domain name
	# 1 byte leading zero for first name-part
	# (the '.' in the domain names are used for lengths)
	# 2 bytes for the Type
	# 2 bytes for the Class
	add	ecx, DNS_HEADER_SIZE + 6
	#mov	ecx, 27

	push	ecx
	push	eax
	# in: cx = payload length (without ethernet/ip frame)
	add	ecx, UDP_HEADER_SIZE
	# in: eax = destination ip
	mov	eax, [dns_server_ip]
	# in: edi = out packet
	# in: ebx = nic object (for src mac & ip (ip currently static))
	# in: dl = ipv4 sub-protocol
	mov	dx, IP_PROTOCOL_UDP
	push	esi
	call	net_ipv4_header_put
	pop	esi
	pop	eax
	pop	ecx
	jc	9f

#	call	net_udp_port_get
	call	socket_get_lport	# in: eax; out: edx=dx
	mov	ax, dx
	shl	eax, 16
	mov	ax, 0x35 	# DNS port 53
	call	net_udp_header_put

	# put the DNS header:
	mov	[edi + dns_tid], dword ptr 0x0000
	mov	[edi + dns_flags], word ptr 1
	mov	[edi + dns_questions], word ptr 1 << 8
	mov	[edi + dns_answer_rr], word ptr 0
	mov	[edi + dns_auth_rr], word ptr 0
	mov	[edi + dns_add_rr], word ptr 0
	add	edi, DNS_HEADER_SIZE


2:	mov	edx, edi	# remember offs
	inc	edi
	xor	ah, ah
0:	lodsb
	cmp	al, '.'
	jnz	1f
	# have dot. fill preceeding length
	mov	[edx], ah
	jmp	2b
1:	stosb
	inc	ah
	or	al, al
	jnz	0b
	dec	ah
	mov	[edx], ah

#	mov	al, 6
#	stosb
#	LOAD_TXT "google"
#	movsd
#	movsw
#	mov	al, 2
#	stosb
#	LOAD_TXT "nl"
#	movsw
#	mov	al, 0
#	stosb

	mov	ax, 1 << 8	# Type A
	stosw
	mov	ax, 1 << 8	# Class IN
	stosw

	pop	esi
	NET_BUFFER_SEND

9:
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	pop	esi
	pop	edi
	ret

