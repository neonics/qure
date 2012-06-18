.intel_syntax noprefix
.code32

.data 2
net_packet$: .space 2048
.text

##############################################################################
# Ethernet Frame:
.struct 0
eth_header:
eth_dst: .space 6
eth_src: .space 6
eth_len:	# when <= 1500 it is len, otherwise it is type
eth_type: .word 0	# 0x0008	# ipv4 (network byte order MSB)
# 0x0800 ipv4
# 0x0806 ARP
# 0x0842 wake-on-lan
# 0x1337 SYN3 heartbeat
# 0x8035 RARP
# 0x8100 VLAN tagged frame
# 0x8137 novell IPX
# 0x814c SNMP
# 0x86dd IPV6
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
# 0x88f7 precision time protocol IEE 1588
# 0x8906 fibre channel over ethernet
# 0x9000 configuration test protocol (loop)
# 0xcafe veritas low latency transport (LLT)
ETH_HEADER_SIZE = .

.text
# in: dx = protocol
# in: ebx = nic object
# in: edi = packet buffer
# out: edi = updated packet pointer
# destroys: eax
protocol_ethernet2:

	# eth_dst: destination mac
	xor	eax, eax
	dec	eax	# broadcast
	stosd
	stosw

.if 0
		mov	[edi -6],  byte ptr 0x02
		mov	[edi -5],  byte ptr 0xff
		mov	[edi -4],  byte ptr 0xbe
		mov	[edi -3],  byte ptr 0x7f
		mov	[edi -2],  byte ptr 0x23
		mov	[edi -1],  byte ptr 0xf9
.endif

	# eth_src: source mac
	push	esi
	lea	esi, [ebx + nic_mac]
	movsd
	movsw
	pop	esi

	# eth_type: embedded protocol
	mov	ah, dl
	mov	al, dh
	stosw

	ret

##############################################################################
# IPv4
.struct 0	# offset 14 in ethernet frame
ipv4_header:
ipv4_v_hlen: .byte 0 # .byte (4<<4) | 5
# lo = header len (32 bit units), hi = version
ipv4_dscp: .byte 0
# TOS - type of service/dscp differentiated services code point
# DSCP: 76 = ECN - explicit congestion notification
#       5..0: DSCP - tos
ipv4_totlen: .word 0 # 0 interpreted as 1522  1536
ipv4_id: .word 0	# datagram fragment id
ipv4_fragment: .word 0 # high 3 bits = flags(0,DF,MF), low 13 bits fragment offset
# DF = dont fragment, MF = more fragments
ipv4_ttl: .byte 0	# .byte 128
ipv4_protocol: .byte 0	# .byte 1	# icmp
# 0x00	ipv6 hopopt
#*0x01 ICMP internet control message
# 0x02 IGMP internet group management
# 0x03 GGP gateway-to-gateway
# 0x04 ipv4 encapsulation
# 0x05 ST stream protocol
#*0x06 TCP
# 0x07 CBT core based trees
# 0x08 EGP exterior gateway
# 0x09 IGP interior gateway
# 0x0a BBN RCC monitoring
# 0x0b NVP-II network voice
# 0x10 CHAOS
#*0x11 UDP
# 0x1b RDP - reliable datagram protocol
# 0x29 ipv6 encapsulation
# 0x2b ipv6-route
# 0x2c ipv6-frag
# 0x2e rsvp - resource reservaion
# 0x2f GRE - generic routing encapsulation
# 0x3a ipv6-icmp
# 0x3b ipv6-nonext header
# 0x3c ipv6-opts destination options
# 0x3d any host internal protocol (undefined?)
# 0x3e cftp
# 0x3f any local network
# 0x44 any distributed file system
# 0x46 VISA protocol
# 0x47 IPCV internet packet core uility
ipv4_checksum: .word 0
ipv4_src: .long 0	# .byte 10,0,2,33
ipv4_dst: .long 0	# .byte 10,0,2,1
# if headerlen > 5:
ipv4_options:
IPV4_HEADER_SIZE = .
.text

# in: dl = protocol
# in: ebx = nic object
# in: esi = payload
# in: ecx = payload len
# out: esi = packet buffer
# out: ecx = packet len
protocol_ipv4:
	push	dx
	mov	dx, 0x0800	# ipv4
	call	protocol_ethernet2
	pop	dx
	
	# out: edi points to end of ethernet frame, start of embedded protocol

	mov	[edi + ipv4_v_hlen], byte ptr 0x45 # 4=version, 5*32b=hlen
	mov	[edi + ipv4_ttl], byte ptr 128
	mov	[edi + ipv4_protocol], dl

	mov	[edi + ipv4_dst+0], byte ptr 192
	mov	[edi + ipv4_dst+1], byte ptr 168
	mov	[edi + ipv4_dst+2], byte ptr 1
	mov	[edi + ipv4_dst+3], byte ptr 1

	mov	[edi + ipv4_src+0], byte ptr 192
	mov	[edi + ipv4_src+1], byte ptr 168
	mov	[edi + ipv4_src+2], byte ptr 1
	mov	[edi + ipv4_src+3], byte ptr 9

	push	esi
	push	edi
	push	ecx
	mov	esi, edi
	mov	edi, offset ipv4_checksum
	mov	ecx, IPV4_HEADER_SIZE / 2
	call	protocol_checksum
	pop	ecx
	pop	edi
	pop	esi

	add	edi, IPV4_HEADER_SIZE

	ret


#############################################################################
# ICMP 
.struct 0	# 14 + 20
icmp_header:
icmp_type: .byte 0 # .byte 8
	# type  
	# 0	echo (ping)
	# 1,2	reserved
	# 3	destination unreachable
	# 4	source quench
	# 5	redirect message
	# 6	alternate host address
	# 7	reserved
	# 8	echo request (ping)
	# 9	router advertisement
	# 10	router sollicitation
	# 11	time exceeded
	# 12	parameter problem: bad ip header
	# 13	timestamp
	# 14	timestamp reply
	# 15	information request
	# 16	information reply
	# 17	address mask request
	# 18	address mask reqply
	# 19	reserved for security
	# 20-29	reserved for robustness experiment
	# 30	traceroute
	# 31	datagram conversion error
	# 32	mobile host redirect
	# 33	where are you (ipv6)
	# 34	here i am (ipv6)
	# 35	mobile registration request
	# 36	mobile registration reply
	# 37	domain name request
	# 38	domain name reply
	# 39	SKIP (simple key management for IP) discovery protocol
	# 40	photuris security failures
	# 41	ICMP for experimental mobile protocols
	# 42-255 reserved

icmp_code: .byte 0
icmp_checksum: .word 0 
icmp_id: .word 0
icmp_seq: .word 0
ICMP_HEADER_SIZE = .


.text

protocol_icmp:
	mov	edi, offset net_packet$
DEBUG "Payload: "
debug_dword esi
debug_dword ecx
DEBUG "Packet"
debug_dword edi
call	newline

	mov	dl, 1	# ICMP
	call	protocol_ipv4

#	push	edi
#	add	edi, IPV4_HEADER_SIZE
#	rep	movsb
#	pop	edi

	mov	[edi + icmp_type], byte ptr 8	# ping request

	push	esi
.if 0
	xor	edx, edx
	xor	eax, eax
	mov	[edi + icmp_checksum], ax
	.rept 4
	lodsw
	add	edx, eax
	.endr
	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	not	ax
	mov	[edi + icmp_checksum], ax
.else
	push	ecx
	push	edi
	mov	ecx, 4
	mov	esi, edi
	mov	edi, offset icmp_checksum
	call	protocol_checksum
	pop	edi
	pop	ecx
.endif
	pop	esi

	add	edi, ICMP_HEADER_SIZE

	rep	movsb

	mov	ecx, edi
	mov	esi, offset net_packet$
	sub	ecx, esi
	ret

#############################################################################

# in: esi = pointer to header to checksum
# in: edi = offset relative to esi to receive checksum
# in: ecx = length of header in 16 bit words
# destroys: eax, ecx, esi
protocol_checksum:
	push	edx
	push	eax

	xor	edx, edx
	xor	eax, eax
	mov	[esi + edi], ax

	push	esi
0:	lodsw
	add	edx, eax
	loop	0b
	pop	esi

	mov	ax, dx
	shr	edx, 16
	add	ax, dx
	not	ax
	mov	[esi + edi], ax

	pop	eax
	pop	edx
	ret

