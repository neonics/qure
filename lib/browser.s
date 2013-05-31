.intel_syntax noprefix
.text32

cmd_browse:
	lodsd
	lodsd
	or	eax, eax
	jnz	1f
	LOAD_TXT "http://www.google.com", eax
1:	mov	esi, eax

	call	url_parse
	jc	9f

	mov	esi, edx
	mov	ecx, ebx
	sub	ecx, edx
	print "hostname: "
	call	nprint
	call	printspace

	call	dns_resolve_name
	call	net_print_ip
	call	newline

#mov	eax, (192)|(168<<8)|(1<<16)|(10<<24)

	xor	ebx, ebx	#flags
	mov	edx, (IP_PROTOCOL_TCP<<16) | 80
	call	socket_open
	jc	91f
	DEBUG_DWORD eax,"socket"
	call	newline

	LOAD_TXT "GET /\n"
	call	strlen_
	DEBUG "write"
	call	socket_write
	DEBUG "flush"
	call	socket_flush
	#jc	92f

	DEBUG "read"
	call	newline

	mov	ecx, 10000
	call	socket_read
	jc	93f

	call	nprintln

	push	eax

		call	xml_parse

		push	edi
		#call	xml_handle_parsed$
		call	display_html
		pop	eax
		call	mfree

	pop	eax


0:	call	socket_close
9:	ret

93:	printlnc 4, "socket read error"
	jmp	0b

92:	call	91f
	jmp	0b
91:	printlnc 4, "socket error"
	ret


# in: esi = url
# out: edx = start of hostname
# out: ebx = end of hostname / start of uri
# out: ecx = len of uri
url_parse:
	print "URL: "
	call	println

	call	strlen_
	mov	edi, esi
	mov	al, ':'
	repnz	scasb
	jnz	91f
	mov	ax, '/'|('/'<<8)
	scasw
	jnz	91f

	mov	edx, edi
	repnz	scasb
	mov	ebx, edi
	clc
	ret

91:	printlnc 4, "malformed url: no protocol"
	stc
	ret


# in: edi = parsed SGML (xml.s)
# in: edx = length of parsed data
display_html:
	#call	enter_gfx_mode
	call	sgml_handle_parsed$
	ret



sgml_handle_parsed$:
	mov	esi, edi
	xor	ebx, ebx	# depth
0:	
#	DEBUG_DWORD esi; DEBUG_WORD dx
	dec	edx
	js	9f
	lodsb
	DEBUG_BYTE al
	mov	ah, al

########
	# todo: shift, adc/sbb optimize
	cmp	ah, XML_T_CLOSE
	jnz	1f
	dec	ebx
	js	92f
#	jns	1f
#	xor ebx, ebx
1:
	call	xml_print_indent$

	cmp	ah, XML_T_OPEN
	jnz	1f
	inc	ebx
1:	

########
########
.if XML_DEBUG > 1
	DEBUG_BYTE ah

	PRINTFLAG ah, XML_T_OPEN, "OPEN"
	PRINTFLAG ah, XML_T_CLOSE, "CLOSE"
	PRINTFLAG ah, XML_T_PI, "PI"
	PRINTFLAG ah, XML_T_TEXT, "TEXT"
	PRINTFLAG ah, XML_T_COMMENT, "COMMENT"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"
.endif

##
	test	ah, XML_T_TEXT
	jz	1f
	sub	edx, 4
	jl	91f
	lodsd
.if XML_IMPL_STRINGTABLE
	push	esi
	mov	esi, eax
	lodsd
	mov	ecx, eax
	call	nprintln_
	pop	esi
.else
	mov	ecx, eax
	sub	edx, eax
	jl	91f
	call	nprintln_
.endif
	jmp	0b


##
1:	
	test	ah, XML_T_COMMENT
	jz	1f
	sub	edx, 4
	jl	91f
	lodsd
	printc 14, "<!--"
.if XML_IMPL_STRINGTABLE
	push	esi
	mov	esi, eax
	lodsd
	mov	ecx, eax
	call	nprint_
	pop	esi
.else
	mov	ecx, eax
	sub	edx, eax
	jl	91f
	call	nprint_
.endif
	printlnc 14, "-->"
	jmp	0b

##
1:	test	ah, XML_T_OPEN | XML_T_CLOSE | XML_T_PI
	jz	1f

	#########
		printcharc 14, '<'
		cmp	ah, XML_T_CLOSE
		jnz	2f
		printcharc 14, '/'
	2:	test	ah, XML_T_PI
		jz	2f
		printcharc 14, '?'
	2:
	#########

.if XML_IMPL_STRINGTABLE
	sub	edx, 4
	jl	91f
	push	eax
	lodsd	# string ptr
		push_	esi
		mov	esi, eax
		lodsd
		mov	ecx, eax
		pushcolor 15
		call	nprint
		popcolor
		pop_	esi
	pop	eax

.else
	dec	edx
	jl	91f
	lodsb
	movzx	ecx, al
	sub	edx, ecx
	jl	91f

		pushcolor 15
		call	nprint_
		popcolor
.endif


	# nested handle of attributes
	push_	eax
10:	test	byte ptr [esi], XML_T_ATTR
	jz	11f
	dec	edx
	js	11f
	lodsb
	mov	ah, al

	dec	edx
	jl	11f
	lodsb
	movzx	ecx, al
	sub	edx, ecx
	jl	11f
		pushcolor 10
		call	printspace
		call	nprint_
		popcolor
		printcharc 14, '='
	sub	edx, 4
	jl	11f
	push	eax
	lodsd
	mov	ecx, eax
	sub	edx, eax
	pop	eax
	jl	11f

	test	ah, XML_T_ATTR_DQ
	mov	ax, '\'' | (14<<8)
	jz	12f
	mov	al, '"'
12:	call	printcharc


	call	nprint_
	call	printcharc
	jmp	10b

11:	pop_	eax
	js	91f


	########
	2:	test	ah, XML_T_PI
		jz	2f
		printcharc 14, '?'
	2:
		cmp	ah, XML_T_OPEN | XML_T_CLOSE
		jnz	2f
		printcharc 14, '/'
	2:
		printcharc 14, '>'
	########

	call	newline
	jmp	0b
##
1:	printc 4, "unknown xml item: "
	mov	dl, ah
	call	printhex2
	call	newline

9:	ret

91:	printc 4, "xml parsed buffer malformed"
	call	printhex8
	call	newline
	ret
92:	printlnc 4, "xml: more close than open"
	ret
############################



enter_gfx_mode:
	test	byte ptr [gfx_mode$], 1
	jnz	1f
	pushad
	call	cmd_gfx
	popad
1:	ret
