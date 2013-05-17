.intel_syntax noprefix
.text32

XML_T_OPEN	= 1
XML_T_CLOSE	= 2
XML_T_SINGULAR	= 4
XML_T_ATTR	= 8

# in: esi, ecx
xml_parse:
	push	ebp
	mov	ebp, esp

	mov	eax, ecx
	call	buf_new
	jc	90f
	push	eax		# [ebp - 4] = out buffer
	mov	ebx, eax	# ebx = outbuf
	push	esi		# [ebp - 8] = xml in start
	mov	edi, esi

0:	mov	al, '<'	
DEBUG_DWORD ecx
	repnz	scasb
	jnz	91f
	DEBUG "<"

	mov	edx, edi	# start of tag

	push	ecx
	mov	al, '>'
	repnz	scasb
	pop	ecx
	jnz	92f

	DEBUG ">"

############
# edi = end of tag
# edx = start of tag


# eax	ah=flags
# ebx	out
# ecx	remaining
# edx	tag start
# esi	tagname end
# edi	tag end
# ebp	stack

	lea	esi, [edi - 2]	# tagname end

	mov	ah, XML_T_SINGULAR
	cmp	byte ptr [edi -1], '/'
	jz	1f
	inc	esi

	mov	ah, XML_T_OPEN
	cmp	byte ptr [edx], '/'
	jnz	1f

	mov	ah, XML_T_CLOSE
	inc	edx
	dec	ecx
	# no attributes allowed
	jmp	3f

1:	# attributes allowed:
	push	ecx
	push	edi
	mov	ecx, esi#edi
	sub	ecx, edx
	mov	edi, edx
	mov	al, ' '
	repnz	scasb	# edi = end or space.
	jnz	2f
	or	ah, XML_T_ATTR
	lea	esi, [edi - 1]	# tagname end
2:	
	pop	edi
	pop	ecx

3:
	PRINTFLAG ah, XML_T_OPEN, "OPEN"
	PRINTFLAG ah, XML_T_CLOSE, "CLOSE"
	PRINTFLAG ah, XML_T_SINGULAR, "SING"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"

	push	eax
	and	ah, ~XML_T_ATTR	# don't pass the ATTR flag - local use
	call	xml_store_tagname$
	pop	eax
	jc	92f
	test	ah, XML_T_ATTR
	jz	1f
		DEBUG "attrs"
		call xml_process_attrs$
		jc	0f
1:
		call	newline
	or	ecx, ecx
	jg	0b

############

	DEBUG "done"
0:	mov	esp, ebp
	pop	ebp
	ret

1:	mov	eax, [ebp - 4]
	call	buf_free
	stc
	jmp	0b

90:	printlnc 4, "xml_parse: out of memory"
	stc
	jmp	0b

91:	printlnc 4, "no tags"
	jmp	1b

92:	printc 4, "xml_parse: format error: malformed tag at byte "
	sub	edx, [ebp - 8]
	call	printdec32
	jmp	1b

# in: ah = XML_T_*
# in: edi = end of tag
# in: esi = end of tag name
# in: edx = start of tag name
# in: ebx = out ptr
# out: ebx = new out ptr
xml_store_tagname$:
	push	eax
	push	ecx
	push	esi
	push	edi

	mov	ecx, esi #edi
	sub	ecx, edx
	#dec	ecx
	DEBUG_DWORD ecx
	jle	91f
	cmp	ecx, 255
	ja	92f

	mov	edi, ebx
	mov	al, cl
	xchg	al, ah
	stosw		# flags, tagname len
	mov	esi, edx
	# tag name:
	# invalid characters: <, >, /,  , ', ", &, ;
0:	lodsb
		mov	ah, 2
		call	printcharc
	cmp	al, '<'
	jz	9f
	cmp	al, '>'
	jz	9f
	cmp	al, '/'
	jz	9f
	cmp	al, ' '
	jz	9f
	cmp	al, '\''
	jz	9f
	cmp	al, '"'
	jz	9f
	cmp	al, '&'
	jz	9f
	cmp	al, ';'
	jz	9f
	stosb
	loop	0b
	mov	ebx, edi
	clc

0:	pop	edi
	pop	esi
	pop	ecx
	pop	eax
	ret

9:	stc
	jmp	0b
91:	printc 4, "len(tagname)<=0"
	stc
	jmp	0b
92:	printc 4, "len(tagname)>255"
	stc
	jmp	0b


# in: ah = XML_T_*
# in: edi = end of tag
# in: esi = end of tag name
# in: edx = start of tag name
# in: ebx = out ptr
# out: ebx = new out ptr
xml_process_attrs$:
	push_	ecx edx esi
		#dec edi
		DEBUG "@"
		mov al, [edi]
		call printcharc
	mov	ecx, edi
	sub	ecx, esi
	dec	ecx
	jle	9f

	#lea	edi, [esi + 1]
0:	# skip whitespace
DEBUG_DWORD ecx,"WS"
	lodsb
call printcharc
	cmp	al, ' '
	jz	1f
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
1:	loop	0b
	jmp	9f
2:	dec	esi
	mov	edi, esi
	mov	edx, esi	# start of attr

	# expect '='
	mov	al, '='
	repnz	scasb
	jnz	91f
		mov	esi, edx
		push	ecx
		mov	ecx, edi
		sub	ecx, edx
		dec	ecx
		# TODO: check: ZF = attr name len = 0
		call	nprint
		call	printspace
		pop	ecx
	
	mov	al, [edi]
	cmp	al, '"'
	jz	1f
	cmp	al, '\''
	jnz	92f
1:	
	# scan for string delimiter
	inc	edi
	dec	ecx
	mov	edx, edi
	repnz	scasb
	jnz	91f

		push	ecx
		mov	esi, edx
		mov	ecx, edi
		sub	ecx, edx
		dec	ecx
		call	nprint
		call	printspace
		pop	ecx

	mov	esi, edi
	or	ecx, ecx
	jg	0b

	clc
9:	pop_	esi edx ecx
	ret

91:	printc 4, "malformed attribute"
	stc
	jmp	9b
92:	printc 4, "invalid attribute-value string delimiter: "
	call	printchar
	call	newline
	stc
	jmp	9b
93:	printc 4, "invalid character, expect whitespace: "
	call	printchar
	call	newline
	stc
	jmp	9b

############################

cmd_xml:
	lodsd
	lodsd
	or	eax, eax
	.if 0
	jz	10f
	.else
	jnz 1f
	LOAD_TXT "/d/www/index.html", eax
1:
	.endif

	call	fs_openfile
	jc	9f
	call	fs_handle_read
	jc	8f
	push	eax
	call	xml_parse
	pop	eax
8:	call	fs_close
9:	ret
10:	printlnc 12, "usage:  xml <filename>"
	ret

