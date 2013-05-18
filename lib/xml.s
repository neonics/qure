.intel_syntax noprefix
.text32
XML_DEBUG = 1

XML_T_OPEN	= 1
XML_T_CLOSE	= 2
XML_T_SINGULAR	= 4
XML_T_PI	= 8
XML_T_COMMENT	= 16
XML_T_ATTR	= 64

# in: esi, ecx
# out: edi = parsed buf (mfree)
# out: ecx = parsed buf size
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
DEBUG_DWORD ecx;
.if XML_DEBUG > 1
	DEBUG_DWORD esi; DEBUG_DWORD edi
.endif
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
##	# check for xml-processing-instruction
	cmp	[edx], byte ptr '?'
	jnz	2f
	cmp	[esi], byte ptr '?'
	jnz	93f
	inc	edx	# tag start
#	dec	esi	# tag end
#	dec	edx
#	inc	esi
	sub	ecx, 2	# not sure about this..
	dec	edi	# another dec is done @ 1f
#	sub	edi, 2	# still used for attrs
	.if XML_DEBUG > 1
		push_ ecx esi
		mov	ecx, esi
		sub	ecx, edx
		DEBUG_DWORD ecx
		mov	esi, edx
		pushcolor 0xa0
		call nprint;
		popcolor
		pop_ esi ecx
	.endif
	mov	ah, XML_T_PI
	jmp	1f
2:
##	# check for comment
	cmp	[edx-1], dword ptr ('<')|('!'<<8)|('-'<<16)|('-'<<24)
	jnz	2f
	# now, the end tag may not be proper if the comment encloses tags.
	# find the end of the comment:
	# scan for '--', it must not occur unless followed by '>'.
	lea	edi, [edx + 4]	# 3?
	DEBUG_DWORD ecx
	push	ecx
	mov	al, '-'
44:	repnz	scasb
	jnz	4f
	DEBUG_DWORD ecx, "Match"
	PRINTCHAR [edi-2]
	PRINTCHAR [edi-1]
	PRINTCHAR [edi]
	PRINTCHAR [edi+1]
	PRINTCHAR [edi+2]
	scasb
	jnz	44b
	cmp	byte ptr [edi], '>'
	jnz	44b
4:	pop	ecx
	jnz	94f
	DEBUG "found comment close"

	inc	edi		# end of comment tag
	lea	esi, [edi -3]	# end of comment content
	add	edx, 3		# start of comment content
	mov	ah, XML_T_COMMENT
	.if XML_DEBUG > 1
		push_ esi ecx
		mov	ecx, esi
		sub	ecx, edx
		mov	esi, edx
		pushcolor 9
		call nprint
		popcolor
		pop_ ecx esi
	.endif
	jmp	3f	# no attrs

2:
##

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
		dec	edi
	push	ecx
	push	edi
	mov	ecx, esi#edi
	sub	ecx, edx
	mov	edi, edx
	.if XML_DEBUG > 1
		DEBUG_DWORD ecx,"WHITE";DEBUG_DWORD esi;DEBUG_DWORD edx
		push esi; mov esi, edi; pushcolor 0xf0;call nprint;popcolor;pop esi
	.endif
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
	PRINTFLAG ah, XML_T_PI, "PI"
	PRINTFLAG ah, XML_T_COMMENT, "COMMENT"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"

	.if XML_DEBUG > 1
		push_ esi ecx;
		mov	ecx, edi
		sub	ecx, edx
		mov	esi, edx
		DEBUG_DWORD ecx,"PURPLE";DEBUG_DWORD edi;DEBUG_DWORD edx
		pushcolor 0xd0;call nprint;popcolor;
		pop_ ecx esi
	.endif

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
0:	mov	edx, ebx
	mov	edi, [ebp - 4] # start of outbuf
	sub	edx, edi
	mov	esp, ebp
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

93:	printc 4, "xml_parse: malformed xml-processing-instruction"
	jmp	1b

94:	printc 4, "xml_parse: malformed comment"
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
test ah, XML_T_COMMENT
jz 1f

	mov	ecx, esi
	sub	ecx, edx
	mov	edi, ebx
	# comment tag format: byte type, dword len, data
	mov	al, ah
	stosb
	mov	eax, ecx
	stosd
	mov	esi, edx
	rep	movsb
	jmp	10f

1:
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
10:	mov	ebx, edi
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
# in: esi = end of tag name / start of attribute area (whitespace,...)
# in: edx = start of tag name
# in: ebx = out ptr
# out: ebx = new out ptr
xml_process_attrs$:
	push_	ecx edx esi
	.if XML_DEBUG > 1
		#dec edi
		call newline
		DEBUG "@"
		DEBUG_DWORD edi,"edi/end"
		DEBUG_DWORD esi
		mov al, [edi]
		call printcharc
	.endif
	mov	ecx, edi
	sub	ecx, esi
#	dec	ecx
	jle	9f
	.if XML_DEBUG > 1
		push esi
		pushcolor 0xe0
		DEBUG_DWORD ecx
		call nprint
		popcolor
		pop esi
	.endif

	#lea	edi, [esi + 1]
0:	# skip whitespace
	lodsb
	.if XML_DEBUG > 1
		DEBUG_DWORD ecx,"WS"

		mov ah, 0x4f
		call printcharc
		push edx; mov dl, al; call printhex2;pop edx
	.endif
	cmp	al, ' '
	jz	1f
	cmp	al, '\t'
	jz	1f
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
1:	
	#loop	0b
	dec ecx; jnz 0b
	jmp	9f
2:	dec	esi
	mov	edi, esi
	mov	edx, esi	# start of attr

	# expect '='
	mov	al, '='
	repnz	scasb
	jnz	91f
	.if XML_DEBUG
		mov	esi, edx
		push	ecx
		mov	ecx, edi
		sub	ecx, edx
		dec	ecx
		# TODO: check: ZF = attr name len = 0
		pushcolor 0xf0
		call	nprint
		popcolor
		call	printspace
		pop	ecx
	.endif
	
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

	.if XML_DEBUG
		push	ecx
		mov	esi, edx
		mov	ecx, edi
		sub	ecx, edx
		dec	ecx
		pushcolor 0xf1
		call	nprint
		popcolor
		call	printspace
		pop	ecx
	.endif

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
xml_print_indent$:
	push	ecx
	lea	ecx, [ebx *2]
	jecxz	9f
0:	call	printspace
	loop	0b
9:	pop	ecx
	ret

xml_handle_parsed$:
	mov	esi, edi
	xor	ebx, ebx	# depth
0:	
	DEBUG_WORD dx
	dec	edx
	js	9f
	lodsb
	mov	ah, al

########
	# todo: shift, adc/sbb optimize
	test	ah, XML_T_CLOSE
	jz	1f
	dec	ebx
	js	92f
1:
	call	xml_print_indent$

	test	ah, XML_T_OPEN
	jz	1f
	inc	ebx
1:	

########
########

	PRINTFLAG ah, XML_T_OPEN, "OPEN"
	PRINTFLAG ah, XML_T_CLOSE, "CLOSE"
	PRINTFLAG ah, XML_T_SINGULAR, "SING"
	PRINTFLAG ah, XML_T_PI, "PI"
	PRINTFLAG ah, XML_T_COMMENT, "COMMENT"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"

	test	ah, XML_T_COMMENT
	jz	1f
	sub	edx, 4
	jl	91f
	lodsd
	mov	ecx, eax
	sub	edx, eax
	jl	91f
	call	nprintln_
	jmp	0b

1:	

	dec	edx
	jle	91f
	lodsb
	movzx	ecx, al
	sub	edx, ecx
	jl	91f

#########
	test	ah, XML_T_OPEN | XML_T_CLOSE
	jz	1f
	printcharc 14, '<'
	test	ah, XML_T_CLOSE
	jz	1f
	printcharc 14, '/'
1:
#########
	pushcolor 15
	call	nprint_
	popcolor
########
	test	ah, XML_T_OPEN | XML_T_CLOSE
	jz	1f
	printcharc 14, '>'
1:
########


	call	newline
	jmp	0b


9:	ret

91:	printc 4, "xml parsed buffer malformed"
	call	printhex8
	call	newline
	ret
92:	printlnc 4, "xml: more close than open"
	ret
############################

cmd_xml:
	.if 0
LOAD_TXT "OEUIEICMOEIRCTMORIEUTOIEOIRTJDMLKDSLKDSFLKJDFSJLKDSFJLKDSFJLKDSFJLKDSFLJKSDFJLKDsflkdsfljkdsflkjdsfjlkdsflkdsfjlkdsfjlkdsfjlkdflkdfjlklkdsfkfjldkdjldsfjklfdsjlkDFSJLKDFSJLKDFSJLKDFJLKDSFJLKFDSJLKFDJLKDFSJLKDFJLKDFJLKDFKJLDFJLKDFJKLDFSKJLDSFjlkdfsjlkdfsjlk END"
call strlen_
call nprint
ret
	.endif
	lodsd
	lodsd
	or	eax, eax
	.if 0
	jz	10f
	.else
	jnz 1f
	LOAD_TXT "/a/www/www.neonics.com/content/index.xml", eax
	mov	dl, [boot_drive]
	add	[eax+1], dl	# won't work for 2nd invocation
1:
	.endif

	call	fs_openfile
	jc	9f
	call	fs_handle_read
	jc	8f
	push	eax
	call	xml_parse
	printlnc 11, "parsed:"
	call	xml_handle_parsed$
	pop	eax
8:	call	fs_close
9:	ret
10:	printlnc 12, "usage:  xml <filename>"
	ret

