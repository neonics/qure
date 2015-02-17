###########################################################################
# IGMP / multicast
#
# [RFC 1112] IGMP v1
# [RFC 2236] IGMP v2
# [RFC 3376] IGMP v3
#
# Class D IP addresses: 224.0.0.0/3 (224.0.0.0-239.255.255.255)
#
# MAC: ETH mcast 01:00:5e:00:00:00 | host_group_ip & ((1<<23)-1)
# or, the low 23 bits of a host group are placed in network byte order
# in the last 23 bits the eth mcast mac:
#
#   01:00:5e:[0 bbbbbbb]:[cccccccc]:[dddddddd] for IPv4 a.b.c.d

IGMP_LOG = 1	# 1: print dropped packets
IGMP_VERBOSE = 0# 1: print incoming IGMP packets

.struct 0
# http://www.iana.org/assignments/igmp-type-numbers/igmp-type-numbers.xhtml
#  TYPE	 	NAME                    REF
#  ----------|-----------------------|----------
#  0x00		reserved
#  0x01-0x08	obsolete		[RFC  988] (create group etc)
#  0x09-0x10	unassigned
#
# *0x11		membership query	[RFC 1112]
# *0x12		V1 membership report	[RFC 1112]
#
#  0x13		DVMRP
#  0x14		PIM v1
#  0x15		Cisco trace msgs
#
# *0x16		V2 membership report	[RFC 2236]
# *0x17		V2 leave group		[RFC 2236]
#
#  0x1e		mcast traceroute response
#  0x1f		mcast traceroute
#
# *0x22		V3 membership report	[RFC 3376] (source filtering)
#
#  0x30		mcast router advertise	[RFC 4286]
#  0x31		mcast router sollicit 	[RFC 4286]
#  0x31		mcast router terminate 	[RFC 4286]
#  0xf0-0xff	reserver for experiments[RFC 3228|BCP57]
igmp_type:	.byte 0	# lo 4 bits = version; hi 4 bits = type
	IGMP_TYPE_QUERY		= 0x11
	IGMP_TYPE_REPORTv1	= 0x12
	IGMP_TYPE_REPORTv2	= 0x16
	IGMP_TYPE_LEAVEv2	= 0x17
	IGMP_TYPE_REPORTv3	= 0x22
igmp_max_resp:.byte 0 # bit7=0: val * 1/10 s; 1: [1 | exp:3 | mant:4 ]: (mant | 0x10) << (exp + 3)
igmp_checksum:	.word 0
# up to here is the common header for all IGMP packets

# IGMPv1, v2, and v3 Query:
igmp_addr:	.long 0	# group address
IGMP_HEADER_SIZE = .	# minimum header size

# IGMPv3 Query:
igmpv3_s_qrv:	.byte 0	# [RESV:4 | S:1 | QRV:3 ]; S=suppress router processing;QRV:querier robustness val
igmpv3_qqic:	.byte 0	# querier query interval code; same semantics as max_resp except in seconds
igmpv3_numsrc:	.word 0	# nr of source ipv4 addr to follow


# IGMP Query (0x11):
# v1: frame len 8 octets and max_resp = 0
# v2: frame len 8 octets and max_resp != 0
# v3: frame len >= 12 octets


.struct 4	# IGMPv3 Membership Report
		.word 0	# reserved
igmpv3_num_gr:	.word 0	# number of group records
igmpv3_grs:	# array of group records


.struct 0	# IGMPv3 Group Record
igmpv3_gr_type:	.byte 0
	# Current-State-Record: response to query
	IGMP_GR_MODE_IS_INCLUDE		= 1	# leave
	IGMP_GR_MODE_IS_EXCLUDE		= 2	# join
	# Filter-Mode-Change-Record: notification of local filter change
	IGMP_GR_MODE_CHANGE_INCLUDE	= 3
	IGMP_GR_MODE_CHANGE_EXCLUDE	= 4
	# Source-List-Change-Record:
	IGMP_GR_MODE_ALLOW_NEW_SOURCES	= 5
	IGMP_GR_MODE_BLOCK_OLD_SOURCES	= 6
igmpv3_gr_auxlen:.byte 0
igmpv3_gr_numsrc:.word 0
igmpv3_gr_addr:	.long 0	# multicast address
igmpv3_gr_srcs:	# array of unicast IPv4 source addresses
# after this, auxlen bytes.

.data
igmp_gr_mode_labels:	# printable text for IGMP_GR_MODE_*
.ascii "00", "LV", "JN", "CI", "CE", "AN", "BO"

.text32

# in: edi = igmp frame pointer
# in: dl = message type
# in: eax = group address (igmp_addr)
net_igmp_header_put:
	push	edx

	movzx	edx, dl
	mov	[edi], dx	# type, unused

	# calc checksum: 
	add	dx, ax
	adc	dx, 0
	ror	eax, 16
	add	dx, ax
	adc	dx, 0
	ror	eax, 16
	not	dx
	mov	[edi + 2], dx
	add	edi, 4

	stosd			# addr

	pop	edx
	ret

# in: esi = igmp frame pointer
# in: ecx = igmp frame len
net_igmp_checksum$:
	push_	edi
	mov	edi, offset igmp_checksum
	call	protocol_checksum
	pop_	edi
	ret

###########################################
# IGMPv1:
# - Query  v1 0x11 max_response_time = 0
# - Report v1 0x12
# - Packet len 8 (_MIGHT_ be longer?)
# - checksum over 8 bytes ALWAYS.
#
# IGMPv2:
# - Query  v1 0x11 v2=max_response_time > 0: 1/10s
# - Report v1 0x11 for backwards compat
# - Report v2 0x16
# - Leave  v2 0x17
# - Packet len 8 bytes minimum, data beyond 8 bytes ignored
# - checksum over ENTIRE IP payload.
#
# IGMPv3:
# - Query  v1 0x11 v3=+8 + source addrs; max_resp_tm: <128=1/10;>=floating pt
# - Report v3 0x22
# - Report v1 0x12
# - Report v2 0x16
# - Leave  v2 0x17
# - IP TTL 1
# - IP ToS 0xc0 (IP precedence of internetwork control)
# - IP router alert option (RFC 2113)
#
# NOTES
#
# The above refers to the IGMP _IMPLEMENTATION_ version (1,2 or 3).
# Therefore, since this code attempts to be up to date, it will be v3,
# and thus treat the messages as such.
# 
# The max_response_time field is treated differently by all IGMP versions;
# v1: must be 0 on tx, ignored on rx.
# v2: deciseconds
# v3: < 128: deciseconds; >=128: (mant|0x10)<<(exp+3) as per:
#    |1|exp|mant|	# NOTE!!! RFC numbers bits in reverse! ('1'=bit 0)
# example code:
#
# decode_time:
#	movzx	ax, byte ptr [esi + igmp_max_resp_time]
#	test	al, 128
#	jz	1f
#	mov	cl, al
#	shr	cl, 4	# cl = |0000|1|exp|
#	and	cl, 3	# cl = |0000|0|exp|
#	add	cl, 3	# cl = exp+3, max  value = 10
#	and	al, 15	# al = mant
#	or	al, 0x10# al = |0001|mant|
#	shl	ax, cl	# max: 5 bits + 10 bits
# 1:	ret	# ax = deciseconds
#
# in: ax = deciseconds
# encode_time:
#	cmp	ax, 128
#	jb	1f	# bsr must succeed (ZF=0) since ax>=128
#	bsr	cx, ax	# cx = most significant set bit index
#	sub	cl, 4	# leave 4 bits
#	jns	2f
#	xor	cl, cl	# exp = 0
# 2:	shr	ax, cl	# al = |0000|mant|
#	shl	cl, 4
#	mov	ah, cl
#	or	ah, 128
# 1:	ret
###########################################

# in: esi = igmp frame
# in: ecx = igmp frame len
# in: edx = ipv4 frame
net_ipv4_igmp_print:
	push_	eax edx edi

	printc 11, "IGMPv"
	mov	ah, [esi + igmp_type]
	mov	al, '1' # v1
	cmp	ah, IGMP_TYPE_QUERY
	jz	10f
	cmp	ah, IGMP_TYPE_REPORTv1
	jz	11f
	inc	al # v2
	cmp	ah, IGMP_TYPE_REPORTv2
	jz	11f
	cmp	ah, IGMP_TYPE_LEAVEv2
	jz	12f
	inc	al # v3
	cmp	ah, IGMP_TYPE_REPORTv3
	jz	11f

	printc 4, "? unknown type: "
	mov	dl, ah
	call	printhex2
	call	newline
	jmp	9f

# Leave
12:	pushstring "Leave "
	jmp	4f
# Report
11:	pushstring "Report"
	jmp	4f
# Query
10:	pushstring "Query "
	#jmp	4f

########
4:
	cmp	ecx, 12
	jb	1f
	cmp	al, '2'
	jz	1f	# don't update for v2
	mov	al, '3'	# version 3
1:

	call	printchar
	call	printspace
	call	_s_print
	push	eax
	print " ("
	mov	eax, [edx + ipv4_src]
	call	net_print_ipv4
	print "->"
	mov	eax, [edx + ipv4_dst]
	call	net_print_ipv4
	print ") "
	pop	eax

	# for query, if v2+, print max resp
	cmp	ah, IGMP_TYPE_QUERY
	jnz	3f
## Query
	cmp	al, '1'
	jz	2f
	print " maxresp "
	movzx	edx, byte ptr [esi + igmp_max_resp]
	call	printhex2
	call	printspace

	# check QUERY v3: igmp frame >= 12 bytes
	sub	ecx, 12
	jl	2f	# not v3
	shr	ecx, 3
	# ecx = num dwords 

	cmp	cx, [esi + igmpv3_numsrc]
	jnz	92f
4:	print " #"
	push	ecx
	call	_s_printdec32
	or	ecx, ecx
	jz	1f
	mov	edx, 12
0:	mov	eax, [esi + edx]
	call	printspace
	call	net_print_ip
	add	edx, 4
	loop	0b
	jmp	1f

# report v3
3:	cmpb	[esi + igmp_type], IGMP_TYPE_REPORTv3
	jnz	1f	# unknown v3 message

	# Report v3 has different layout: the 2nd dword is not
	# the group address, but reserved word followed by
	# number of group records.
	sub	ecx, 8	# the standard dword header + the reportv3 numgrp
	jl	91f	# short packet

	shr	ecx, 1	# group record count is at least 8 bytes per entry
	jz	1f	# no group records.
	mov	ax, [esi + igmpv3_num_gr]
	xchg	al, ah
	cmp	cx, ax
	jb	91f	# short packet
	# note: might still be short packet if there are source addresses
	# in one of the entries.

###########
	movzx	ecx, ax	# num group records
	mov	edi, ecx # backup for newline printing
	print	" numgrp="
	push	ecx
	call	_s_printdec32
	call	printspace
	or	ecx, ecx
	jz	1f	# no group records, done.

################################
	push_	ebx esi
	add	esi, 8	# offset of groups
	lea	ebx, [esi + ecx * 8]	# igmp frame end
0:
	cmp	edi, 1	# for numgrp > 1 use multiline format
	jz	5f
	call	newline
5:

	cmp	esi, ebx
	jae	4f	# short packet
	lodsd

	movzx	edx, al	# record type
	cmp	al, 6
	jb	5f	# for record types 0..6 we have text labels
	print " t="	# otherwise print the hex number
	call	printhex2
	jmp	6f
	# text labels are 2 chars each, compact
5:	mov	al, [igmp_gr_mode_labels + edx * 2 + 0]
	call	printchar
	mov	al, [igmp_gr_mode_labels + edx * 2 + 1]
	call	printchar
6:
	movzx	edx, ah	# aux data len
	shr	eax, 16
	print " numsrc="
	push	eax
	call	_s_printdec32
	# skip source addresses:
	shl	eax, 2	# *4
	add	edx, eax
	lodsd	# mcast addr
	call	printspace
	call	net_print_ipv4
	add	esi, edx	# add aux group data + src

	loop	0b
	pop_	esi ebx
	jmp	1f

# grp: short packet
4:	DEBUG_DWORD esi
	DEBUG_DWORD ebx
	pop_	esi ebx
	jmp	91f
################################

# v1,2
2:	mov	eax, [esi + igmp_addr]
	call	net_print_ipv4

1:
	#print	" checksum "
	#mov	dx, [esi + igmp_checksum]
	#call	printhex4

	call	newline

9:	pop_	edi edx eax
	ret
####################################################################

91:	printc 4, "IGMP: short packet: "
	push	ecx
	call	_s_printdec32
	call	newline
	jmp	9b
92:	movzx	eax, word ptr [esi + igmpv3_numsrc]
	push	eax
	push	ecx
	PUSHSTRING "numsrc (%d)*8 + 12 != pktlen (%d)"
	pushcolor 12
	call	printfc
	popcolor
	add	esp, 12
	jmp	9b

# in: ebx = nic
# in: edx = ipv4 frame
# in: esi = payload (igmp frame)
# in: ecx = payload len (8 minimum)
ph_ipv4_igmp:
	cmp	ecx, IGMP_HEADER_SIZE
	jb	91f
	# verify checksum
	call	protocol_checksum_verify
	jc	92f
62:
	push_	eax edx

	# filter: allow destination addresses to be
	# broadcast, multicast, and the NIC IP.
	mov	eax, [edx + ipv4_dst]
	cmp	eax, -1	# broadcast
	jz	1f
	# check multicast
	rol	eax, 4
	and	al, 0b1111
	cmp	al, 0b1110
	jz	1f	# 244.0.0.0/4 match
	mov	eax, [edx + ipv4_dst]	# not multicast

	call	nic_get_by_ipv4	# in: eax = ip; out: ebx = nic (ignored)
	jc	93f	# ret: no match

1:	# done with ipv4 frame (edx available)

.if IGMP_VERBOSE
	call	net_ipv4_igmp_print
.endif

	mov	dl, [esi + igmp_type]
	mov	dh, 1 # v1
	cmp	dl, IGMP_TYPE_QUERY
	jz	1f
	cmp	dl, IGMP_TYPE_REPORTv1
	jz	1f
	inc	dh # v2
	cmp	dl, IGMP_TYPE_REPORTv2
	jz	1f
	cmp	dl, IGMP_TYPE_LEAVEv2
	jz	1f
	inc	dh # v3
	cmp	dl, IGMP_TYPE_REPORTv3
	jz	1f

.if IGMP_LOG
	printc 4, "IGMP: unknown type: "
	call	printhex2
	call	newline
	call	net_ipv4_igmp_print
.endif
	jmp	9f


1:	# one of the supported messages.
	# TODO: handle.

9:	pop_	edx eax
	ret
91:	printlnc 4, "IGMP: short packet"
	ret
92:	printlnc 4, "IGMP: checksum error"
	jmp 62b	# continue anyway
	ret
93:	printc 4, "IGMP: no nic for "
	call	net_print_ipv4
	call	newline
	jmp	9b


# in: dl = IGMP_TYPE
# in: dh = IGMP version
# in: ebx = nic
# in: eax = dest ip
net_igmp_send:
	push_	edi esi ecx
	NET_BUFFER_GET	# XXX verify that packet is zeroed
	jc	91f
	push	eax	# stackref
	push	edx	# stack referenced below
	push	edi	# packet start

	mov	ecx, IGMP_HEADER_SIZE
	cmp	dh, 3	# version 3 has 12 octet minimum frame size
	jnz	1f
	add	ecx, 4
	cmp	dl, IGMP_TYPE_REPORTv3
	jnz	1f
	# have v3 report. Fornow, only 1 group record/mcast addr:
	# 8 bytes header + 8 bytes for group record:
	# 16 - 12 = 4
	add	ecx, 4
1:

	# in: edi = out packet
	# in: eax = destination ip
	# in: ecx = payload length (without ethernet/ip frame)
	# in: edx = [ 00 ] [ ttl ] [flags(1<<1=ttl)] [ipv4 sub-protocol]
	mov	edx, IP_PROTOCOL_IGMP | 1<<9 | 1 << 16

	# in: ebx = nic - ONLY if eax = -1!
	# out: edi = points to end of ethernet+ipv4 frames in packet
	# out: ebx = nic object (for src mac & ip) [calculated from eax]
	# out: esi = destination mac [calculated from eax]
	call	net_ipv4_header_put
	mov	esi, edi	# start of igmp frame for IGMPv3 Report

	mov	dx, [esp + 4] # IGMP_TYPE | version << 8
	cmp	dl, IGMP_TYPE_QUERY
	jnz	1f
	xor	eax, eax	# zero igmp_addr for query
1:

	call	net_igmp_header_put

	cmp	dl, IGMP_TYPE_REPORTv3
	jnz	1f
	# overwrite group address with number of group records:
	mov	dword ptr [edi - 4], (1<<8) << 16
	# add the group record
	# |b: record type |b: aux data len |w: num src|
	mov	eax, IGMP_GR_MODE_IS_EXCLUDE # join
	stosd
	mov	eax, [esp + 8]	# group IP
	stosd
	# no sources.
1:

	mov	ecx, edi
	sub	ecx, esi
	jle	93f
	call	net_igmp_checksum$	# in: esi, ecx

	pop	esi
	NET_BUFFER_SEND
	pop	edx
	pop	eax
	jc	92f
9:	pop_	edi esi ecx
	ret
91:	printlnc 4, "net_buffer_get error"
	stc
	jmp	9b
92:	printlnc 4, "net_buffer_send error"
	stc
	jmp	9b
93:	printlnc 4, "edi < esi"
	int 3
	jmp	1b




# in: ebx = NIC
net_igmp_print:
	push_	esi eax edx
	lea	esi, [ebx + dev_name]
	mov	ah, 15
	call	printc
	printc 11, " MCAST groups: "
	xor	edx, edx
	mov	esi, [ebx + nic_mcast_list]
	or	esi, esi
	jz	1f
	mov	edx, [esi + array_index]
	shr	edx, 2
1:	call	printdec32
	call	newline
	or	edx, edx
	jz	9f

0:	lodsd
	call	printspace
	call	net_print_ipv4
	call	newline
	dec	edx
	jnz	0b

9:	pop_	edx eax esi
	ret

# in: ebx = NIC
# in: eax = IP
net_igmp_join:
	push_	ecx edx

	# verify that the IP is not in the list
	call	net_igmp_ismember
	jz	92f	# already added to list

	mov	ecx, eax	# backup ip
	PTR_ARRAY_NEWENTRY [ebx + nic_mcast_list], 1, 91f
	mov	[eax + edx], ecx
	mov	eax, ecx

62:	# report
	# TODO: timer, repeat
	mov	dx, IGMP_TYPE_REPORTv3 | 3 << 8
	call	net_igmp_send	# in: eax, ebx, dl
	mov	dx, IGMP_TYPE_REPORTv2 | 2 << 8
	call	net_igmp_send	# in: eax, ebx, dl
	#mov	dl, IGMP_TYPE_REPORTv1 | 1 << 8
	#call	net_igmp_send	# in: eax, ebx, dl

0:	pop_	edx ecx
	ret
91:	printc 4, "net_igmp_join: malloc error"
	jmp	0b
92:	printc 4, "net_igmp_join: already member of "
	call	net_print_ipv4
	call	newline
	jmp	62b

# in: ebx = NIC
# in: eax = IP
net_igmp_leave:
	call	net_igmp_ismember
	jnz	91f
	push	edx
	mov	dx, IGMP_TYPE_LEAVEv2 | 2 << 8
	call	net_igmp_send
	pop	edx

	# remove entry from nic_mcast_list
	# we know it's a member - rescan:
	push_	edi ecx
	mov	edi, [ebx + nic_mcast_list]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd
	# edi-4
	jecxz	1f	# last entry
	# not last entry: copy rest.
	push	esi
	mov	esi, edi
	sub	edi, 4
	rep	movsd
	pop	esi
1:	# last entry
	mov	edi, [ebx + nic_mcast_list]
	subd	[edi + array_index], 4
0:	pop_	ecx edi

	ret

91:	printc 4, "net_igmp_leave: not member of "
	call	net_print_ipv4
	call	newline
	ret

# in: eax = IP
# in: ebx = NIC
# out: ZF
net_igmp_ismember:
	cmp	eax, 224|1<<24	# all-hosts address
	jz	9f
	push	edi
	mov	edi, [ebx + nic_mcast_list]
	or	edi, edi
	jz	1f
	push	ecx
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	jz	2f
	repnz	scasd		# ZF = 1 = member
	pop	ecx
	pop	edi
9:	ret

2:	pop	ecx
1:	pop	edi
	or	esp, esp	# ZF = 0
	ret
