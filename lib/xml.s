.intel_syntax noprefix
.text32
XML_DEBUG = 1

XML_IMPL_STRINGTABLE = 1

#######################################
# Binary XML output format:
#
# byte		flags	# only one flag used at a time
# byte/dword	len	# DWORD for COMMENT, TEXT
# len		data	# tag/attr/pi name, comment, text
# dword		len	# only present for ATTR
# len		data	# only present for ATTR
#
# XML:
#
# <abc>hello<a xmlns="http://"/></abc>
#
# Parsed:
#
# .byte XML_T_OPEN
# .byte 3
# .ascii "abc"
#
# .byte XML_T_TEXT
# .long 5
# .ascii "hello"
#
# .byte XML_T_SINGULAR
# .byte 1
# .ascii "a"
#
# .byte XML_T_ATTR
# .byte 5
# .ascii "xmlns"
# .long 7
# .ascii "http://"
#
# .byte XML_T_CLOSE
# .byte 3
# .ascii "abc"
XML_T_OPEN	= 1
XML_T_CLOSE	= 2
XML_T_SINGULAR	= 4
XML_T_PI	= 8
XML_T_COMMENT	= 16
XML_T_TEXT	= 32
XML_T_ATTR	= 64

########################################
# new idea:
#
# 2 buffers, the first containing a compact structure.
# the second containing the strings.
#
# FIRST BUFFER
#
# Each entry will be similar to the idea before, except that
# instead of a string length followed by a string, this will be
# a string pointer into the second buffer.
#
# SECOND BUFFER
#
# This buffer contains entries: a dword indicating the length
# followed by the (asciz) string with that length. The length does
# not include the trailing zero, which is there for easy printing.
#
# 
# TRANSITION
#
# The first step in the transition is to store tagnames
# in the stringtable. In this first step, no effort is exerted to remove
# duplicates, as this can only be done efficiently using a sorted hash.
#
#

# in: esi, ecx
# out: edi = parsed buf (mfree)
# out: ecx = parsed buf size
xml_parse:
	push	ebp
	mov	ebp, esp

	SV_XMLIN	= -4
	SV_XMLINLEN	= -8
	SV_OUTBUF	= -12
	SV_OUTSTRING	= -16
	SV_OUTSTRING_CUR= -20

	push	esi		# [ebp - 4] = xml in start
	mov	edi, esi
	push	ecx		# [ebp - 8] = xml in len


	mov	eax, ecx
	call	mallocz
	jc	90f
	push	eax		# [ebp - 12] = out buffer
	mov	ebx, eax	# ebx = outbuf

	mov	eax, ecx
	call	mallocz
	jc	95f
	push	eax		# [ebp - 16] = out stringtab
	push	eax		# [ebp - 20] = out stringtab cur pos


0:	mov	al, '<'	
DEBUG_DWORD ecx;
.if XML_DEBUG > 1
	DEBUG_DWORD esi; DEBUG_DWORD edi
.endif

	mov	esi, edi	# remember start
	.if XML_DEBUG > 1
		push ecx
		cmp ecx, 20
		jb 1f
		mov ecx, 20
		1:
		call nprint
		pop ecx
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
# esi = end of prev tag

	# store text:
	push_	ecx edi
	mov	ecx, edx
	dec	ecx
	sub	ecx, esi
	jz	1f
	mov	edi, ebx
	mov	al, XML_T_TEXT
	stosb
	mov	eax, ecx
	stosd
	rep	movsb
	mov	ebx, edi
1:	pop_	edi ecx



# eax	ah=flags
# ebx	out
# ecx	
# edx	tag start (after initial <), will become tag content start
# esi	tag content end
# edi	tag end - parser position
# ebp	stack

	lea	esi, [edi - 2]	# tagname end
##	# check for xml-processing-instruction
	cmp	[edx], byte ptr '?'
	jnz	2f
	cmp	[esi], byte ptr '?'
	jnz	93f
	inc	edx	# tag start

	# edx = tag content start
	# esi = tag content end
	# edi = tag end

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
	# edx tag content start
	# esi tag content end
	# edi parser pos

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
	mov	ecx, esi
	sub	ecx, edx
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
	inc	edx
	mov	ah, XML_T_CLOSE
	# no attributes allowed
	mov	ecx, esi
	sub	ecx, edx
	jmp	3f

1:	call	xml_check_for_attrs$
3:
	PRINTFLAG ah, XML_T_OPEN, "OPEN"
	PRINTFLAG ah, XML_T_CLOSE, "CLOSE"
	PRINTFLAG ah, XML_T_SINGULAR, "SING"
	PRINTFLAG ah, XML_T_PI, "PI"
	PRINTFLAG ah, XML_T_TEXT, "TEXT"
	PRINTFLAG ah, XML_T_COMMENT, "COMMENT"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"

	.if 1#XML_DEBUG > 1
		DEBUG "{"
		push_ esi ecx;
#		mov	ecx, esi
#		sub	ecx, edx
		mov	esi, edx
		pushcolor 0xd0;call nprint;popcolor; # pink
		DEBUG "}"
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
		add	edx, ecx
		call xml_process_attrs$	# modifies eax, ebx
		jc	2f
1:
		call	newline
		DEBUG_DWORD ebx
	
	mov	ecx, [ebp + SV_XMLINLEN]	# in buf len
	add	ecx, [ebp + SV_XMLIN]	# in buf start
	sub	ecx, edi
	jg	0b

############

2:	mov	edx, ebx
	DEBUG "done"
	mov	edi, [ebp + SV_OUTBUF] # start of outbuf
	sub	edx, edi

0:	mov	esp, ebp
	pop	ebp
	ret

1:	mov	eax, [ebp + SV_OUTBUF]
	call	mfree
	mov	eax, [ebp + SV_OUTSTRING]
	call	mfree
	stc
	jmp	0b


95:	# 2nd alloc fail, free first:
	mov	eax, [ebp + SV_OUTBUF]
	call	mfree
	# fallthrough

90:	printlnc 4, "xml_parse: out of memory"
	stc
	jmp	0b
91:	printlnc 4, "no tags"
	jmp	2b

92:	printc 4, "xml_parse: format error: malformed tag at byte "
	sub	edx, [ebp + SV_XMLIN]
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
# in: ecx = tagname len
# in: ebp = SV_ basepointer
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
	#mov	ecx, esi #edi
	#sub	ecx, edx
	##dec	ecx
	DEBUG_DWORD ecx,"TAG"
	#jle	91f

	mov	edi, ebx
	mov	esi, edx

.if XML_IMPL_STRINGTABLE
	mov	al, ah
	stosb
	mov	eax, [ebp + SV_OUTSTRING_CUR]
	stosd
	mov	ebx, edi
	mov	edi, eax
	mov	eax, ecx
	stosd
.else
	cmp	ecx, 255
	ja	92f

	mov	al, cl
	xchg	al, ah
	stosw		# flags, tagname len
.endif
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
10:	
.if XML_IMPL_STRINGTABLE
	xor	al, al
	stosb
	mov	[ebp + SV_OUTSTRING_CUR], edi
.else
	mov	ebx, edi
.endif
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


# in: edx = tag content start
# in: esi = tag content end
# out: ecx = len of tagname (1..(esi-edx))
xml_check_for_attrs$:
	# attributes allowed:
	#	dec	edi
	push_	edi edx
	mov	ecx, esi
	sub	ecx, edx	# ecx = tag content len
	mov	edi, edx
	mov	edx, ecx
	.if 1#XML_DEBUG > 1
		DEBUG_DWORD ecx,"WHITE";DEBUG_DWORD esi;DEBUG_DWORD edx
		printchar [esi]
		push esi; mov esi, edi; pushcolor 0xf0;call nprint;popcolor;pop esi
	.endif
	mov	al, ' '
	repnz	scasb	# edi = end or space.
	jnz	2f
	or	ah, XML_T_ATTR
	dec	edx
	
2:	neg	ecx
	add	ecx, edx
	pop_	edx edi
	ret



# in: edx = start of attribute data (possibly whitespace)
# in: ah = XML_T_*
# in: edi = end of tag (ignore)
# in: esi = end of tag content
# in: ebx = out ptr
# out: ebx = new out ptr
xml_process_attrs$:
	push_	edi ecx edx esi
	.if XML_DEBUG > 1
		#dec edi
		call newline
		DEBUG "@"
		DEBUG_DWORD edx
		DEBUG_DWORD esi
		mov al, [edi]
		call printcharc
	.endif
	mov	ecx, esi
	sub	ecx, edx
	jle	9f
	mov	esi, edx

	.if XML_DEBUG > 1
		push esi
		pushcolor 0xe0
		DEBUG_DWORD ecx
		call nprint
		popcolor
		pop esi
	.endif

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

######	# store the tag name
	push_	edi ecx
	mov	esi, edx
	mov	ecx, edi
	sub	ecx, edx
	dec	ecx
	cmp	ecx, 255
	stc
	ja	1f
	mov	al, XML_T_ATTR
	mov	ah, cl
	mov	edi, ebx
	stosw
	rep	movsb
	xor	eax, eax
	stosd	# the length of the value
	clc	# unsure if needed
	mov	ebx, edi
1:	pop_	ecx edi
	jc	94f
######
	
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

######## # store the value
	push_	edi ecx
	mov	esi, edx
	mov	ecx, edi
	sub	ecx, edx
	dec	ecx
	lea	edi, [ebx - 4]	# overwrite the len
	mov	eax, ecx
	stosd
	rep	movsb
	mov	ebx, edi
	pop_	ecx edi
########

	mov	esi, edi
	or	ecx, ecx
	jg	0b

	clc
9:	pop_	esi edx ecx edi
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

94:	printlnc 4, "tag name too long (>255)"
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
#	DEBUG_DWORD esi; DEBUG_WORD dx
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
#	jns	1f
#	xor ebx, ebx
1:
	call	xml_print_indent$

	test	ah, XML_T_OPEN
	jz	1f
	inc	ebx
1:	

########
########
.if XML_DEBUG > 1
	DEBUG_BYTE ah

	PRINTFLAG ah, XML_T_OPEN, "OPEN"
	PRINTFLAG ah, XML_T_CLOSE, "CLOSE"
	PRINTFLAG ah, XML_T_SINGULAR, "SING"
	PRINTFLAG ah, XML_T_PI, "PI"
	PRINTFLAG ah, XML_T_TEXT, "TEXT"
	PRINTFLAG ah, XML_T_COMMENT, "COMMENT"
	PRINTFLAG ah, XML_T_ATTR, "ATTR"
.endif

##
	test	ah, XML_T_COMMENT | XML_T_TEXT
	jz	1f
	sub	edx, 4
	jl	91f
	lodsd
	mov	ecx, eax
	sub	edx, eax
	jl	91f
	call	nprintln_
	jmp	0b

##
1:	test	ah, XML_T_ATTR
	jz	1f

	dec	edx
	jl	91f
	lodsb
	movzx	ecx, al
	sub	edx, ecx
	jl	91f
	pushcolor 10
	call	nprint_
	popcolor
	printc 14, "=\""

	sub	edx, 4
	jl	91f
	lodsd
	mov	ecx, eax
	sub	edx, eax
	jl	91f
	call	nprint_
	printcharc 14, '"'
	call	newline
	jmp	0b

##
1:	test	ah, XML_T_OPEN | XML_T_CLOSE | XML_T_PI
	jz	1f

	#########
		printcharc 14, '<'
		test	ah, XML_T_CLOSE
		jz	2f
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
#	DEBUG_DWORD eax,"STRINGPTR"

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
	printc 14, "=\""

	sub	edx, 4
	jl	11f
	lodsd
	mov	ecx, eax
	sub	edx, eax
	jl	11f
	call	nprint_
	printcharc 14, '"'
	jmp	10b

11:	pop_	eax
	js	91f


	########
	2:	test	ah, XML_T_PI
		jz	2f
		printcharc 14, '?'
	2:
		test	ah, XML_T_OPEN | XML_T_CLOSE | XML_T_PI
		jz	2f
		printcharc 14, '>'
	2:
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
	add	dl, 'a'
	mov	[eax+1], dl
1:
	.endif

	call	fs_openfile
	jc	9f
	call	fs_handle_read
	jc	8f
	push	eax
	call	xml_parse
	jc	1f
	printlnc 11, "parsed:"
	push	edi
	call	xml_handle_parsed$
	pop	eax
	call	mfree
1:	pop	eax
8:	call	fs_close
9:	ret
10:	printlnc 12, "usage:  xml <filename>"
	ret

