##################################################################
# ISO 3309 / ITU-T V.42
.intel_syntax noprefix

.data
crc32_table$:	.space 1024	# 256 dwords

.text32
crc32_calctable:
	push	ebx
	mov	ebx, 0xedb88320 # standard: 0xedb88320; ethernet: 0x104C11DB7 (magic const: 0xC704DD7B)
	call	crc32_calctable_
	pop	ebx
	ret

# in: ebx = polynomial
crc32_calctable_:
	push_	eax ecx edx
	xor	ecx, ecx
	xor	al, al
0:	mov	edx, ecx
	mov	ah, 8
1:	shr	edx, 1
	jnc	2f
	xor	edx, ebx
2:	dec	ah
	jnz	1b
3:
	mov	[crc32_table$ + ecx * 4], edx

	inc	cl
	jnz	0b

	pop_	edx ecx eax
	ret

# in: esi = data
# in: ecx = datalen
# out: eax = crc32
crc32:
	xor	eax, eax
# KEEP-WITH-NEXT fallthrough

# in: eax = crc
# in: esi = data
# in: ecx = datalen
# out: eax = crc
update_crc32:
	push_	ecx edx esi 
	mov	edx, -1
	xor	edx, eax
	cmpb	[crc32_table$ + 4], 0
	jz	61f
16:
	xor	eax, eax
	lodsb	# buf[n] & 0xff
	xor	al, dl	# c ^
	mov	eax, [crc32_table$ + eax * 4]
	shr	edx, 8
	xor	edx, eax
	loop	16b

	mov	eax, -1
	xor	eax, edx
	pop_	esi edx ecx
	ret

61:	call	crc32_calctable
	jmp	16b




cmd_crc32:
	lodsd
	lodsd
	mov	esi, eax
	call	strlen_
1:	call	crc32
	push	eax
	call	_s_printhex8
	call	newline
	ret



.if 0	# tested, works


cmd_crc32_test:
	call	_test0
	call	_test1
	call	_test2
	ret

_test2:
	mov	eax, [clock_ms]
	DEBUG_DWORD eax, "in:"
	push	eax
	mov	esi, esp
	mov	ecx, 4
	call	update_crc32	# NOTE! we have crc=in=eax!
	DEBUG_DWORD eax, "crc"
	not eax
	bswap eax;call bit_reverse
	DEBUG_DWORD eax, "eth"

	call	newline

	mov	eax, [clock_ms]
	mov	[esp], eax
	mov	esi, esp
	mov	ecx, 4
	call	crc32
	DEBUG_DWORD eax, "CRC"
		mov	edx, eax
#	not	eax
	bswap	eax
	call	bit_reverse
	DEBUG_DWORD eax, "~CRC"

	mov	[esp], eax
		mov	eax, edx
	call	update_crc32
	DEBUG_DWORD eax, "FIN"
	bswap eax
	call bit_reverse
	DEBUG_DWORD eax, "2"
	not	eax
	DEBUG_DWORD eax, "3"

	add	esp, 4
	ret

_test1:
	pushd	3
	mov	esi, esp
	mov	ecx, 1
	call	crc32
#mov eax, 1235
	DEBUG_DWORD eax, "CRC"
		mov	ebx, eax	# backup

	call	bit_reverse
	mov	[esp], eax
	mov	esi, esp
	mov	ecx, 4
		mov	eax, ebx	# restore 
	call	update_crc32
	DEBUG_DWORD eax, "TOT"
	bswap	eax
	call	bit_reverse
	not	eax
	DEBUG_DWORD eax, "MAGIC"
	call	newline

	add	esp, 4
	ret


_test0:
	#LOAD_TXT "Test magic const for CRC32", esi, ecx, 1
	pushd	0x3	# test
	mov	esi, esp
	mov	ecx, 1

	call	crc32
	push	eax
	call	_s_printhex8	# 0x02362d8f  ok
	call	printspace

	call	bit_reverse	# eax -> eax
	print " rev: "
	push eax; call _s_printhex8

#		bswap eax;
#		print " MSB ";
#		push eax; call _s_printhex8

	push	eax
	mov	esi, esp
	mov	ecx, 4
	call	update_crc32
	print " CRC total:"
	mov	[esp], eax
	call	_s_printhex8	# 21 44 df c1
	# eth expect: 0xC704DD7B
.if 0
pushad
	call	bit_reverse
print " rev: "
push eax
call _s_printhex8
print " ! "
not eax
push eax
call _s_printhex8

popad
.endif

	print " ETH: "
	bswap eax
	not eax
	call bit_reverse
	push eax
	call _s_printhex8

	call	newline


	add	esp, 4	# see pushd 0 above
	ret

# in: eax
# out: eax
bit_reverse:
	push_	esi ecx eax
	mov	esi, esp
	mov	ecx, 4
0:	lodsb
	xor	ah, ah
	.rept 8
	shl	al, 1
	rcr	ah, 1
	.endr
	mov	[esi -1], ah
	loop	0b
	pop_	eax ecx esi
	ret

SHELL_COMMAND "testcrc"		cmd_crc32_test

.endif
