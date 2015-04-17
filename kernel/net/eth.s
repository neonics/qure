##############################################################################
# IEEE 802.3 Ethernet / Ethernet II Frame:
ETH_MAX_PACKET_SIZE = 1518	# or 1522 incl IEEE802.1Q 'VLAN taggging'
#
# The ETH maximum packet size must be implemented to be including VLAN.
#
# Size:
#
# preamble: 			7 bytes	alternating bits (1,0,1,0...)
# start frame deliaiterm (SFD):	1 byte  alternating bits with last bit 1 instead of 0.
# dest MAC:			6 bytes
# src MAC:			6 bytes		(20)
# type/size:			2 bytes		(22)
# payload:			(0..)"42/46-1500"
# CRC/FCS:			4 bytes		(26)
# inter frame gap (IFG):	12 bytes	(38)
# ---------------------------------------
#				38	(38+42 = 80 bytes, 16 too many: CRC+IFG).
#
#
# LAYER 1 PACKET: 1530 bytes
# LAYER 2 FRAME:  1522 bytes (=1530 - 8; 8 = preamble/frame start). This excludes CRC/IFG
#
# Both contain 12 bytes MAC, 2 byte type/len (possibly vlan tag),
# and both end with 32 bit CRC, totalling 12+2+4 = 18 bytes (18+4=22 for VLAN tag).
# 1522 - MACs - type/len - CRC = 1522 - 12 - 2 - 4 = 1522-18=1504.
#
# Minimum payload: 42 bytes with VLAN tag, 46 without.
# VLAN:		22 bytes + min 42, max 1500  (min 64, max 1522)
# normal:	18 bytes + min 46, max 1500  (min 64, max 1522)
#
# Min frame size = 64 bytes; for non-VLAN: 22 byte header (up to type/size) + 42 bytes = 64 bytes,
# followed by CRC/FCS and the inter-frame gap.
#
#
.struct 0
# preamble and SFD(start frame delimiter): 8 bytes: 13 nibbles 0xa, 1 nibble 0xb
# eth_packet_preamble:	.space 7, 0b10101010	# 0xaa; 170; on wire: 0x55 (85)
# eth_packet_sfd:	.space 1, 0x10101011	# 0xab; 171; on wire: 0xd5 (213)
eth_header:
eth_dst: .space 6
eth_src: .space 6

eth_len:	# when <= 1500 it is len, when 1536+ (otherwise) it is type
eth_type: .word 0	# 0x0008	# ipv4 (network byte order MSB)
	# 0x0800 ipv4
	ETH_PROTO_IPV4 = 0x0800
	# 0x0806 ARP
	ETH_PROTO_ARP = 0x0806
	# 0x0842 wake-on-lan
	# 0x1337 SYN3 heartbeat
	# 0x8035 RARP
	# 0x8100 VLAN tagged frame
		# next comes the VLAN TAG:
		#
		# .word 0bAAABCCCCCCCCCCCC
		# A: 3 bit; priority code point, see IEEE 802.1p.
		#    priority level:
		#	1 = background,
		#	0 = best effort,
		#	2 = excellent effort,
		#	3 = critical application,
		#	....
		#	7 = network control
		# B: 1 bit; drop eligible indicator: packet may be dropped
		# C: 12 bit; VLAN ID; 0x000,0xfff reserved.
		#
		# This is followed by another eth_len/type.
		# In effect, the vlan tagged frame identifier (0x8100) and
		# the vlan tag (the .word bove) is injected between
		# eth_src and eth_len/type.
	# 0x8137 novell IPX
	# 0x814c SNMP
	# 0x86dd IPV6
	ETH_PROTO_IPV6 = 0x86dd
	# 0x8809 slow protoocls - IEEE 802.3
	# 0x8847 MPLS unicast
	# 0x8848 MPLS multicast
	# 0x8863 PPoE discovery
	# 0x8864 PPoE session
	# 0x886f Microsoft NLB heartbeat
	# 0x8892 profinet (profibus)
	# 0x88a2 ATA over ethernet
	# 0x88a8 provider bridging IEE 801.1ad
	# 0x88e5 mac security IEE 802.1AE
	# 0x88d9 microsoft point2point,p2multipoint,p2broadcast; discovery
	# 0x88f7 precision time protocol IEE 1588
	# 0x8906 fibre channel over ethernet
	# 0x9000 configuration test protocol (loop)
	# 0xcafe veritas low latency transport (LLT)
ETH_HEADER_SIZE = .
# eth_frame_crc:	.long 0
# 'frame check sequence':
# CRC over entire frame and CRC must yield 0xC704DD7B.
# (polynomial:  4C11DB7)
#
# It appears that the CRC calculation begins after the frame start delimiter,
# and as soon as it equals the magic constant, the end of frame is assumed.
# This might mean that some packets may produce such a CRC prematurely.
#
# eth_frame_gap: .space 12

.if DEFINE

.data
mac_bcast: .byte -1, -1, -1, -1, -1, -1
.text32
# in: ebx = nic object
# in: edi = packet buffer
# in: dx = protocol
# in: esi = pointer to destination mac
# out: edi = updated packet pointer
net_eth_header_put:
	push	esi

	# eth_dst: destination mac
	movsd
	movsw

	# eth_src: source mac
	lea	esi, [ebx + nic_mac]
	movsd
	movsw

	pop	esi

	# eth_type: embedded protocol
	xchg	dh, dl
	mov	[edi], dx
	add	edi, 2

	ret


# in: esi = ethernet frame (len 6+6+2 = 14)
# out: esi + 14
net_eth_print:
	pushcolor COLOR_PROTO_DATA
	printc	COLOR_PROTO, "Ethernet "

	printc	COLOR_PROTO_LOC, "DST "
	call	net_print_mac
	add	esi, 6

	printc	COLOR_PROTO_LOC, " SRC "
	call	net_print_mac
	add	esi, 6

	printc	COLOR_PROTO_LOC, " PROTO "
	movzx	edx, word ptr [esi]
	xchg	dl, dh
	add	esi, 2
	call	printhex4

	printc COLOR_PROTO_LOC, " LEN "
	mov	edx, ecx
	call	printhex4

	call	printspace
	popcolor
	ret


.data
DECL_PROTO_STRUCT_START eth
DECL_PROTO_STRUCT_W 0,             "LLC",  net_llc_handle, net_llc_print,  PROTO_PRINT_LLC
DECL_PROTO_STRUCT_W 0x88d9,        "LLC",  net_llc_handle, net_llc_print,  PROTO_PRINT_LLC
DECL_PROTO_STRUCT_W ETH_PROTO_IPV4,"IPv4", net_ipv4_handle, net_ipv4_print, PROTO_PRINT_IPv4
DECL_PROTO_STRUCT_W ETH_PROTO_ARP, "ARP",  net_arp_handle, net_arp_print,  PROTO_PRINT_ARP
DECL_PROTO_STRUCT_W ETH_PROTO_IPV6,"IPv6", net_ipv6_handle, net_ipv6_print, PROTO_PRINT_IPv6
DECL_PROTO_STRUCT_END eth, ETHERNET
.text32

# in: edi = index (0, 1, 2)
# out: edi = protocol structure offset (0, 9, 18, ..)
proto_struct_idx2offs:
	# multiply by the protocol structure size
	push	eax
	mov	eax, PROTO_STRUCT_SIZE
	imul	edi, eax
	pop	eax
	ret

# in: ax = protocol word
# out: edi = protocol index:
#   [proto$ + edi * 2]: protocol word (ax)
#   [eth_proto_handlers$ + edi*4] = unrelocated offset to protocol handler
#   [proto_names$ + edi * 4 ] = pointer to protocol name string
net_eth_protocol_get_handler$:
	# test if the protocol word is smaller than the maximum packet size
	xchg	al, ah
	cmp	ax, 1500
	ja	1f
	# it is, so, it is a packet length, not a protocol identifier.
	xor	edi, edi	# LLC protocol
	ret

1:	push	ecx
	mov	edi, offset eth_proto$
	mov	ecx, ETHERNET_PROTO_LIST_SIZE
	repne	scasw
	pop	ecx
	stc
	jnz	1f

	# calculate the index
	# scas always points just after the match
	sub	edi, offset eth_proto$ + 2
	shr	edi, 1
	call	proto_struct_idx2offs

	clc	# redundant
1:	ret


.endif
