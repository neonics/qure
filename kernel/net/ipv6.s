###############################################################################
# Internet Protocol Version 6
.intel_syntax noprefix
.text32

# in: eax = ptr to ipv6 address
net_print_ipv6:
	push_	esi ecx edx eax
	mov	esi, eax
	mov	ecx, 16
	jmp	1f
0:	printchar_ ':'
1:	lodsb
	mov	dl, al
	call	printhex2
	loop	0b
	pop_	eax edx ecx esi
	ret

# prints the address with '::' for the largest sequence of 0
# in: eax = ptr to ipv6 address
net_print_ipv6_smart:
	push_	esi ecx edx eax
	mov	esi, eax
	mov	ecx, 16

	# find the largest sequence of 0's
	xor	edx, edx	# dl = count; dh=max
	mov	ah, -1		# no offset
0:	lodsb
	or	al, al
	jnz	1f	# record and reset
	inc	dl
2:	loop	0b

1:	cmp	dl, dh
	jbe	1f
	mov	dh, dl
	mov	ah, cl
1:	xor	dl, dl
	or	cl, cl	# fallthrough from loop also
	jnz	2b

	# dh = max squence of 0's
	# ah = cl on end of sequence
	# dh - ah = start offset of sequence.

	add	ah, dh	# ah is proper cx 'offset'

	mov	esi, [esp]
	mov	ecx, 16
	jmp	1f
0:	printchar_ ':'
1:	lodsb
	cmp	ah, cl
	jnz	1f	
	dec	dh
	jz	0b
	dec	ah
	jmp	2f

1:	mov	dl, al
	call	printhex2
2:	loop	0b
	pop_	eax edx ecx esi
	ret

############################
# in: ebx = nic
# in: esi = ipv6 frame
# in: ecx = frame size
net_ipv6_handle:
	DEBUG "IPv6"
	ret



ipv6_sollicit_router:
	ret

ICMP6_ROUTER_SOLLICITATION = 0x85


teredo_init:
	LOAD_TXT "teredo.ipv6.microsoft.com.nsatc.net"
	call	strlen_
	call	dns_resolve_name
	jc	91f
	call	net_print_ip
	call	newline
9:	ret

91:	printlnc 4, "teredo: dns lookup failed"
	jmp	9b
