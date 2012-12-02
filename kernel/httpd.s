#######################################################################
# HTTP Server
#
.intel_syntax noprefix
.text32

NET_HTTP_DEBUG = 1


# in: eax = tcp_conn array index
# in: esi = request data
# in: ecx = request data len
net_service_tcp_http:
	.if NET_HTTP_DEBUG
		printc 11, "TCP HTTP "
		push	eax
		add	eax, [tcp_connections]
		movzx	edx, word ptr [eax + tcp_conn_remote_port]
		xchg	dl, dh
		mov	eax, [eax + tcp_conn_remote_addr]
		call	net_print_ip
		printchar_ ':'
		call	printdec32
		call	printspace
		pop	eax
	.endif

	call	http_parse_header

	# Send a response
	cmp	edx, -1	# no GET / found in headers
	mov	esi, offset www_code_400$
	jz	www_err_response

	.if NET_HTTP_DEBUG
		pushcolor 14
		mov	esi, edx
		call	print
		call	printspace
		popcolor
	.endif

	cmp	word ptr [edx], '/' | 'C'<<8
	jnz	1f
		call	www_send_screen
		ret
###################################################

1:	cmp	word ptr [edx], '/'
	jnz	1f
	LOAD_TXT "/index.html", edx

1:
	# serve custom file:
	.data SECTION_DATA_STRINGS
	www_docroot$: .asciz "/c/www/"
	WWW_DOCROOT_STR_LEN = . - www_docroot$
	.data SECTION_DATA_BSS
	www_content$: .long 0
	www_file$: .space MAX_PATH_LEN
	.text32
	push	eax
	movzx	eax, byte ptr [boot_drive]
	add	al, 'a'
	mov	[www_docroot$ + 1], al
	pop	eax

	mov	esi, edx
	call	strlen_
	cmp	ecx, MAX_PATH_LEN - WWW_DOCROOT_STR_LEN -1
	mov	esi, offset www_code_414$
	jae	www_err_response
	mov	esi, edx

	# calculate path
	mov	edi, offset www_file$
	mov	esi, offset www_docroot$
	mov	ecx, WWW_DOCROOT_STR_LEN
	rep	movsb

	mov	edi, offset www_file$
	mov	esi, edx
	inc	esi	# skip leading /
	call	fs_update_path	# edi=base/output, esi=rel
	# strip last char
	mov	byte ptr [edi-1], 0

	# check whether path is still in docroot:
	mov	esi, offset www_docroot$
	mov	edi, offset www_file$
	mov	ecx, WWW_DOCROOT_STR_LEN - 1 # skip null terminator
	repz	cmpsb
	mov	esi, offset www_code_404$
	jnz	www_err_response

	.if NET_HTTP_DEBUG > 1
		printc 13, "Serving file: '"
		mov	esi, offset www_file$
		call	print
		printlnc 13, "'"
	.endif

	push	eax	# preserve net_tcp_conn_index
	mov	eax, offset www_file$
	call	fs_openfile
	jc	2f
	call	fs_handle_read	# out: esi, ecx

	push	edx
	push	eax
	call	fs_validate_handle	# out: edx + eax
	mov	[eax + edx + fs_handle_buf], dword ptr 0
	pop	eax
	pop	edx

	pushf
	call	fs_close
	popf
	pop	eax
	jnc	1f

	push	eax
	mov	eax, esi
	call	mfree
2:	pop	eax
	mov	esi, offset www_code_404$
	jmp	www_err_response

########
1:	# esi, ecx = file contents
	.if NET_HTTP_DEBUG
		print "200 "
	.endif
	push	ebp
	mov	ebp, esp
	push	eax	# [ebp - 4]  tcp conn
	push	esi	# [ebp - 8]  orig buf
	push	ecx	# [ebp - 12] orig buflen

	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
	call	strlen_
	call	net_tcp_sendbuf

	mov	ebx, [ebp - 8]	# buf

1:	mov	edi, ebx
	mov	ecx, [ebp - 12]	# buflen
	call	www_findexpr	# in: edi, ecx; out: edi,ecx
	jc	1f
# preserve edi,ecx
	# edi, ecx = expression
	lea	edx, [edi - 2]	# start of expression string
	sub	edx, ebx	# len of unsent data
	jz	2f
	mov	esi, ebx	# start of unsent data
	lea	ebx, [edi + ecx + 1]	# end of expr = new start of unsent data
	sub	[ebp - 12], edx	# update remaining source len

	push	ecx
	mov	ecx, edx
	call	net_tcp_sendbuf
	pop	ecx
2:
# use edi,ecx
	lea	edx, [ecx + 3]
	sub	[ebp - 12], edx	# update remaining source len

	call	www_expr_handle

	jmp	1b
##################################

1:	mov	ecx, [ebp - 12]
	mov	esi, ebx
	call	net_tcp_sendbuf	# in: eax=tcpconn, esi=data, ecx=len
	call	net_tcp_sendbuf_flush
	call	net_tcp_fin

	mov	eax, [ebp - 8]
	call	mfree
########
9:	mov	esp, ebp
	pop	ebp
	ret


# in: esi = header
# in: ecx = header len
# out: edx = -1 or resource name (GET /x -> /x)
http_parse_header:
	push	eax
	mov	edx, -1		# the file to serve
	mov	edi, esi	# mark beginning
0:	lodsb
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
	.if NET_HTTP_DEBUG > 1
		call	newline
	.endif
	call	http_parse_header_line$	# update edx if GET /...
	mov	edi, esi	# mark new line beginning
	jmp	1f

2:	.if NET_HTTP_DEBUG > 1
		call	printchar
	.endif

1:	loop	0b
	.if NET_HTTP_DEBUG > 1
		call	newline
	.endif
	pop	eax
	ret



# in: edi = start of header line
# in: esi = end of header line
# in: edx = known value (-1) to compare against
# out: edx = resource identifier (if request match): 0 for root, etc.
http_parse_header_line$:
	push	esi
	push	ecx
	mov	ecx, esi
	sub	ecx, edi
	mov	esi, edi

	.if NET_HTTP_DEBUG > 2
		push esi
		push ecx
		printchar '<'
		call nprint
		printchar '>'
		pop ecx
		pop esi
	.endif

	LOAD_TXT "GET /", edi
	push	ecx
	push	esi
	mov	ecx, 5
	repz	cmpsb
	pop	esi
	pop	ecx
	jnz	9f

	add	esi, 4		# preserve the leading /
	sub	ecx, 4
	mov	edx, esi	# start of resource
0:	lodsb
	cmp	al, ' '
	jz	0f
	cmp	al, '\n'
	jz	0f
	cmp	al, '\r'
	jz	0f
	loop	0b
	# hmmm
0:	mov	[esi - 1], byte ptr 0
	mov	esi, edx

	.if NET_HTTP_DEBUG > 1
	print "Resource: <"
	call	print
	println ">"
	.endif

9:	pop	ecx
	pop	esi
	ret



# in: edi = data to scan
# in: ecx = data len
# out: edi, ecx: expression string
www_findexpr:
	push	esi
	push	eax

	mov	al, '$'
	repnz	scasb
	jnz	1f	# no expressions
	cmp	[edi], byte ptr '{'
	jnz	1f
	inc	edi

	# parse expression
	mov	esi, edi	# start of expr
0:	dec	ecx
	jle	1f
	lodsb
	cmp	al, ' '
	jz	1f
	cmp	al, '\n'
	jz	1f
	cmp	al, '}'
	jnz	0b

	mov	ecx, esi
	dec	ecx	# dont count closing '}'
	sub	ecx, edi
	clc

9:	pop	eax
	pop	esi
	ret
1:	stc
	jmp	9b


expr_h_unknown:
	ret
expr_h_const:
	mov	eax, edx
	xor	edx, edx
	ret
expr_h_mem:
	mov	eax, [edx]
	xor	edx, edx
	ret
expr_h_call:
	call	edx
	ret

.data
www_expr:
.long (99f - .)/10
STRINGPTR "kernel.size";	.byte 1,1;.long kernel_end - kernel_start
STRINGPTR "kernel.code.size";	.byte 1,1;.long kernel_code_end - kernel_code_start
STRINGPTR "kernel.data.size";	.byte 1,1;.long kernel_end - data_0_start
STRINGPTR "mem.heap.size";	.byte 2,1;.long mem_heap_size
STRINGPTR "mem.heap.allocated";	.byte 3,1;.long mem_get_used
STRINGPTR "mem.heap.reserved";	.byte 3,1;.long mem_get_reserved
STRINGPTR "mem.heap.free";	.byte 3,1;.long mem_get_free
99:
www_expr_handlers:
	.long expr_h_unknown
	.long expr_h_const
	.long expr_h_mem
	.long expr_h_call
NUM_EXPR_HANDLERS = (.-www_expr_handlers)/4
.text32
# in: eax = tcp conn
# in: edi = expressoin
# in: ecx = expression len
# free to use: edx, esi
www_expr_handle:
	push	ebx
	push	ecx
	push	edi
	push	eax

	mov	byte ptr [edi + ecx], 0	# '}' -> 0
	inc	ecx	# include 0 terminator for rep cmpsb

	.if 0
		mov	esi, edi
		call	nprint
	.endif

	# find expression info
	mov	edx, [www_expr]
	mov	ebx, offset www_expr + 4
0:	mov	esi, [ebx]
	push	ecx
	push	edi
	repz	cmpsb
	pop	edi
	pop	ecx
	jz	1f	# found

	add	ebx, 10	# struct size
	dec	edx
	jg	0b
		DEBUG "no matches"
	# not found
	jmp	9f

1:	movzx	edi, byte ptr [ebx + 4]	# type
	mov	edx, [ebx + 6]		# arg2
		cmp	edi, NUM_EXPR_HANDLERS
		jae	9f
	call	www_expr_handlers[edi * 4]

	# todo: format
	.data SECTION_DATA_BSS
	_tmp_fmt$: .space 32
	.text32
	mov	edi, offset _tmp_fmt$
	call	sprint_size
	mov	ecx, edi
	mov	esi, offset _tmp_fmt$
	sub	ecx, esi

	.if 0
		DEBUG "EXPR VAL:"
		call nprint
		call newline
	.endif

	mov	eax, [esp]
	call	net_tcp_sendbuf

9:
	pop	eax
	pop	edi
	pop	ecx
	pop	ebx
	ret

.data SECTION_DATA_STRINGS
www_h$:		.asciz "HTTP/1.1 "
www_h2$:	.ascii "\r\nContent-Type: text/html; charset=UTF-8\r\n"
		.asciz "Connection: Close\r\n\r\n"
www_code_400$:	.asciz "400 Bad Request"
www_code_404$:	.asciz "404 Not Found"
www_code_414$:	.asciz "414 Request URI too long"
www_code_500$:	.asciz "500 Internal Server Error"
www_content1$:	.asciz "<html><body>"
www_content2$:	.asciz "</body></html>\r\n"
.text32
www_err_response:
	.if NET_HTTP_DEBUG
		mov	ecx, 4
		call	nprint
	.endif

	mov	edx, esi

	mov	esi, offset www_h$
	call	strlen_
	call	net_tcp_sendbuf

	mov	esi, edx
	call	strlen_
	call	net_tcp_sendbuf

	mov	esi, offset www_h2$
	call	strlen_
	call	net_tcp_sendbuf

	mov	esi, offset www_content1$
	call	strlen_
	call	net_tcp_sendbuf

	lea	esi, [edx + 4]
	call	strlen_
	call	net_tcp_sendbuf

	mov	esi, offset www_content2$
	call	strlen_
	call	net_tcp_sendbuf

	call	net_tcp_sendbuf_flush
	call	net_tcp_fin
	ret


# in: eax = tcp conn
www_send_screen:
	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
	call	strlen_
	call	net_tcp_sendbuf

.data SECTION_DATA_STRINGS
_color_css$:
.ascii "<html><head><style type='text/css'>"
.ascii "pre {background-color: black}\n"
.ascii ".a{color:black}\n.ba{background-color:black}\n"
.ascii ".b{color:darkblue}\n.bb{background-color:darkblue}\n"
.ascii ".c{color:green}\n.bc{background-color:green}\n"
.ascii ".d{color:darkcyan}\n.bd{background-color:cyan}\n"
.ascii ".e{color:darkred}\n.be{background-color:darkred}\n"
.ascii ".f{color:darkmagenta}\n.bf{background-color:darkmagenta}\n"
.ascii ".g{color:brown}\n.bg{background-color:brown}\n"
.ascii ".h{color:lightgray}\n.bh{background-color:lightgray}\n"
.ascii ".i{color:darkgray}\n.bi{background-color:darkgray}\n"
.ascii ".j{color:#0000ff}\n.bj{background-color:blue}\n"
.ascii ".k{color:lime}\n.bk{background-color:lime}\n"
.ascii ".l{color:cyan}\n.bl{background-color:cyan}\n"
.ascii ".m{color:red}\n.bm{background-color:red}\n"
.ascii ".n{color:magenta}\n.bn{background-color:magenta}\n"
.ascii ".o{color:yellow}\n.bo{background-color:yellow}\n"
.ascii ".p{color:white}\n.bp{background-color:white}\n"
.asciz "</style></head><body><pre>\n"
.text32

	mov	esi, offset _color_css$
	call	strlen_
	call	net_tcp_sendbuf

	push	fs
	mov	ebx, SEL_vid_txt
	mov	fs, ebx
	xor	ebx, ebx

	mov	ecx, 25
0:	push	ecx
#######
	mov	ecx, 80
	.data SECTION_DATA_BSS
	_www_scr$: .space 80 * 13
	.text32
	mov	edi, offset _www_scr$
	push	eax
	xor	dl, dl	# cur color
1:	mov	ax, fs:[ebx]
	cmp	dl, ah
	jz	2f
	or	dl, dl
	jz	3f
	mov	[edi], dword ptr ('<'|'/'<<8|'s'<<16|'p'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'n'<<8|'>'<<16)
	add	edi, 3

3:
	mov	[edi], dword ptr ('<'|'s'<<8|'p'<<16|'a'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('n'|' '<<8|'c'<<16|'l'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'s'<<8|'s'<<16|'='<<24)
	add	edi, 4
	mov	[edi], byte ptr '\''
	inc	edi

	mov	dl, ah

	and	ah, 0x0f
	add	ah, 'a'
	mov	[edi], ah
	inc	edi

	mov	[edi], word ptr ' '|'b'<<8
	add	edi, 2
	mov	ah, dl
	shr	ah, 4
	add	ah, 'a'
	mov	[edi], ah
	inc	edi

	mov	[edi], word ptr '\'' | '>' << 8
	add	edi, 2

2:	stosb
	add	ebx, 2
	loop	1b
	mov	[edi], byte ptr '\n'
	inc	edi
	pop	eax
#######
	mov	esi, offset _www_scr$
	mov	ecx, edi
	sub	ecx, esi
	call	net_tcp_sendbuf
	pop	ecx
	dec	ecx
	jnz	0b

	pop	fs

	LOAD_TXT "</pre></body></html>\n"
	call	strlen_
	call	net_tcp_sendbuf
	call	net_tcp_sendbuf_flush
	call	net_tcp_fin
	ret

