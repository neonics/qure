#######################################################################
# HTTP Server
#
.intel_syntax noprefix

.data SECTION_DATA_STATS
.global stats_httpd_requests
stats_httpd_requests: .long 0
.text32

NET_HTTP_DEBUG = 1		# 1: log requests; 2: more verbose
WWW_EXPR_DEBUG = 0

HTTPD_CHECK_HOST_HEADER = 1	# 1: 404 all 'Host:' headers (even public IP) but our domain and LAN IP


cmd_httpd:
	I "Starting HTTP Daemon"
	PUSH_TXT "httpd"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset net_service_httpd_main
	KAPI_CALL schedule_task
	jc	9f
	OK
9:	ret

net_service_httpd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 80
	mov	ebx, SOCK_LISTEN
	KAPI_CALL socket_open
	jc	9f
	printc 11, "HTTP listening on "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	KAPI_CALL socket_accept
	jc	0b

	incd	[stats_httpd_requests]

	push	eax
	mov	eax, edx
	.if NET_HTTP_DEBUG
		printc 11, "HTTP "
		KAPI_CALL socket_print
		call	printspace
	.endif

	.if 1
	call	httpd_sched_client # some es problem
	.else
	call	httpd_handle_client
	.endif
	pop	eax
	jmp	0b

	ret
9:	printlnc 4, "httpd: failed to open socket"
	ret

httpd_sched_client:
	PUSH_TXT "httpc-"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset httpd_handle_client
	KAPI_CALL schedule_task
	ret

# in: eax = socket
# postcondition: socket closed.
httpd_handle_client:
	mov	edx, 6	# minimum request size: "GET /\n"
0:	mov	ecx, 10000
	KAPI_CALL socket_peek
	jc	9f

	jecxz	22f	# connection closed

	# XXX had kernel error due to ecx being negatice
	# at http_check_request_complete rep scas.
	cmp	ecx, 4096
	ja	5f

	lea	edx, [ecx + 1]	# new minimum request size

	push	eax
	push	edx
	call	http_check_request_complete
	pop	edx
	pop	eax
	jc	4f	# invalid request
	jnz	0b	# incomplete

	call	net_service_tcp_http	# takes care of socket_close
	ret

	22: DEBUG "socket closed while reading"
	jmp 2f

9:	printlnc 4, "httpd: timeout, closing connection"
	LOAD_TXT "HTTP/1.1 408 Request timeout\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write
1:	KAPI_CALL socket_flush
2:	KAPI_CALL socket_close
0:	ret

5:	printlnc 4, "httpd: negative packet length (socket buffer corrupt?), closing with 400"

4:	LOAD_TXT "HTTP/1.1 400 Bad request\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write
	jmp	1b

# out: CF = 1: invalid request (request might be incomplete but complete enough
#  to determine the error, i.e., first line received)
# out: [CF=0] ZF = 1: have a complete request; 0: request incomplete
# out: edi: end of request
http_check_request_complete:
	push	ecx
	mov	edi, esi
0:	mov	al, '\n'
	repnz	scasb
	jnz	91f	# incomplete
########
	# Check for simple request (GET uri \n):
	mov	ecx, [esp]
	mov	edi, esi
	mov	al, ' '
	repnz	scasb	# scan method uri separator
	jnz	99f	# no space: invalid request (request complete)
	repnz	scasb	# check for second space
	jnz	90f	# no second space, thus simple (one-line) request
	# have second space, check for HTTP
	cmp	ecx, 8	# check if sizeof("HTTP/x.x") is at least present
	jb	99f	# invalid (complete) request

	cmp	dword ptr [edi], 'H'|'T'<<8|'T'<<16|'P'<<24
	jnz	99f	# invalid (complete) request
	cmp	byte ptr [edi + 4], '/'
	jnz	99f	# invalid (complete) request
	# check version
	add	edi, 5
	sub	ecx, 5

	call	10f	# expect at least 1 digit:
	jc	99f
	inc	edi
	dec	ecx	# 6
	# check for '.' or digit
4:	cmp	[edi], byte ptr '.'
	jz	3f
	call	10f
	jc	99f
	inc	edi
	loop	4b
	jmp	99f

3:	inc	edi	# got '.'
	dec	ecx
	jz	99f
	call	10f	# check minor version
	jc	99f
	dec	ecx
	jz	99f	# invalid
	# so far we've matched "HTTP/\d+\.\d"
	# now, expect \r|\n|\d
3:	inc	edi
	cmp	[edi], byte ptr '\r'
	jz	1f
	cmp	[edi], byte ptr '\n'
	jz	2f
	call	10f
	jc	99f
	loop	3b
	jmp	99f	# invalid

	# full request line complete
	# check for \n\n (or \r\n\r\n)

2:	# char trailing HTTP version is '\n', so check if next char is also \n.
	cmp	ecx, 2
	jb	91f	# incomplete: no room
	cmp	byte ptr [edi+1], '\n'
	jz	90f	# complete
	add	edi, 2
	sub	ecx, 2
	jle	91f	# incomplete
	# check for a double \n:
	mov	al, '\n'
2:	repnz	scasb
	jnz	91f	# incomplete
	scasb
	jz	90f
	dec	ecx
	jnle	2b
	jmp	91f	# incomplete


1:	# char trailing HTTP version is \r, check for (\r)\n\r\n:
	cmp	ecx, 4
	jb	91f	# incomplete: no room for two CRLF's
	mov	eax, '\r'|'\n'<<8|'\r'<<16|'\n'<<24
	cmp	[edi], eax
	jz	90f	# complete!
	inc	edi
	dec	ecx
	jle	91f

1:	repnz	scasb
	jnz	91f
	cmp	[edi -1], eax
	jz	90f
	jecxz	91f
	jmp	1b

	# incomplete
########
91:	or	edi, edi	# ZF = 0, CF = 0: incomplete
	pop	ecx
	ret

99:	stc			# ZF = ?, CF = 1: invalid request
	pop	ecx
	ret

90:	xor	cl, cl		# ZF = 1, CF = 0: complete
	pop	ecx
	ret

# check for digit
10:	mov	al, [edi]
	cmp	al, '0'
	jb	9f
	cmp	al, '9'
	ja	9f
	clc
	ret
9:	stc
	ret


DEBUG_EXPR = 0

# in: eax = socket index
# in: esi = request data (complete)
# in: ecx = request data len
net_service_tcp_http:
	push	ebp
	mov	ebp, esp

	#sub	esp, 16 # reserve some space for header pointers.
	pushd	0;	HTTP_STACK_HOSTIP	= 36	# IP value when Host header is IP
	pushd	0;	HTTP_STACK_FNAME	= 32	# file name buffer
	pushd	eax;	HTTP_STACK_SOCK		= 28	# net socket
	pushd	0;	HTTP_STACK_FHANDLE	= 24	# file handle
	pushd	0;	HTTP_STACK_FBUF		= 20	# file buffer
	pushd	0;	HTTP_STACK_FSIZE	= 16	# file size
	pushd	0;	HTTP_STACK_HDR_INM	= 12	# If-None-Match
	pushd	0;	HTTP_STACK_HDR_REFERER	= 8	# Referer
	pushd	0;	HTTP_STACK_HDR_HOST	= 4
	pushd	0;	HTTP_STACK_HDR_RESOURCE	= 0
	HTTP_STACKARGS = 40

	call	http_parse_header	# in: esi,ecx; out: edx=uri, ebx=host

	mov	esi, offset www_code_400$
	jc	www_err_response

	# Send a response
	cmp	edx, -1	# no GET / found in headers
	jz	www_err_response

	.if NET_HTTP_DEBUG
		pushcolor 13
		cmp	ebx, -1
		jz	1f
		mov	esi, ebx
		call	print
		call	printspace

	1:	color	14
		mov	esi, edx
		call	print
		call	printspace
		popcolor
	.endif

	cmp	word ptr [edx], '/' | 'C'<<8
	jnz	1f

	call	www_send_screen

100:	mov	esp, ebp
	pop	ebp
	ret

1:	cmpw	[edx], '/' | 'D' << 8	# gzip test
	jnz	1f
	cmpb	[edx + 2], 0	# avoid prefix matches
	jnz	1f

	call	www_gzip_test

	jmp	100b

###################################################

1:	# serve custom file:
	sub	esp, ~3&(MAX_PATH_LEN+3)
	mov	[ebp - HTTP_STACKARGS + HTTP_STACK_FNAME], esp

	.section .strings
	www_docroot$: .asciz "/c/www/"
	WWW_DOCROOT_STR_LEN = . - www_docroot$
	.data SECTION_DATA_BSS
	#www_content$: .long 0
	#www_file$: .space MAX_PATH_LEN
	.text32
	movzx	eax, byte ptr [boot_drive]
	add	al, 'a'
	mov	[www_docroot$ + 1], al

	xor	ecx, ecx
.if HTTPD_CHECK_HOST_HEADER
	cmp	ebx, -1
	#jz	1f	# no host
	jz	404f
	mov	esi, ebx

		pushad
		mov	eax, esi
		xor	bl, bl # dont print errors
		call	net_parse_ip_
		jc	2f	# not an ip
		mov	[ebp - HTTP_STACKARGS + HTTP_STACK_HOSTIP], eax
		cmp	eax, [internet_ip]
		jnz	2f
		stc
		jmp	3f
	2:	clc
	3:	popad
	# CF=1: Host header is internet ip
	4:	jc	404f

	# the Host header is not an ip, check for our domain:
		pushad
			call	strlen_	# in: esi out: ecx
			LOAD_TXT ".neonics.com", edi, edx, 1
			cmp	ecx, edx
			jbe	2f		# too short to be our domain
			add	esi, ecx	# go to end of string
			sub	esi, edx	# rewind to domain
			mov	ecx, edx
			repz	cmpsb
			jz	3f	# same!
		2:	stc
		3:
		popad
		jnc	4f	# it's our domain, proceed

		# check if it is our LAN IP:
		push_	eax ebx
			mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_HOSTIP]
			or	eax, eax
			stc
			jz	2f	# request was not for host ip
			call	nic_get_by_ipv4	# eax -> ebx | CF
			# no CF = our nic, proceed
		2:
		pop_	ebx eax
		jc	404f	# not our host ip
		4:
.endif
	call	strlen_
	inc	ecx
1:
	mov	esi, edx	# uri
	push	ecx
	call	strlen_
		# strip query
		push_	edi ecx
		mov	edi, edx
		mov	al, '?'
		repnz	scasb
		jnz	1f
		mov	byte ptr [edi-1], 0
		# todo: store query ptr edi somewhere
		mov	ecx, edi
		sub	ecx, edx
		# dec ecx?
		1:
		pop_	ecx edi
	add	ecx, [esp]
	add	esp, 4
	cmp	ecx, MAX_PATH_LEN - WWW_DOCROOT_STR_LEN -1
	mov	esi, offset www_code_414$
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	jae	www_err_response

	# calculate path
0:	mov	edi, esp#offset www_file$
	mov	esi, offset www_docroot$
	mov	ecx, WWW_DOCROOT_STR_LEN
	rep	movsb

	# append hostname, if any
	cmp	ebx, -1
	jz	1f
	mov	edi, esp#offset www_file$
	mov	esi, ebx
	call	fs_update_path
	mov	word ptr [edi - 1], '/'
	push	eax
	#mov	eax, offset www_file$
	lea	eax, [esp+4]
	KAPI_CALL fs_stat
	pop	eax
	jnc	1f
	# unknown host
	mov	ebx, -1
	jmp	0b
1:

FS_DIRENT_ATTR_DIR=0x10

	mov	edi, esp	# filename stack buf
	mov	esi, edx	# uri
	inc	esi		# skip leading /
	call	fs_update_path	# in: edi=base/output, esi=rel; out: [edi+*]

	# check whether path is still in docroot:
	mov	esi, offset www_docroot$
	mov	edi, esp#offset www_file$
	mov	ecx, WWW_DOCROOT_STR_LEN - 1 # skip null terminator
	repz	cmpsb
	jnz	404f

	# now, if it is a directory, append index.html
	lea	eax, [esp]	# file name pointer
	KAPI_CALL fs_stat	# in: eax=path; out:ecx=fsize,al=flags,CF
				# XXX ecx = 0x800, not fsize!
	jc	404f
	test	al, offset FS_DIRENT_ATTR_DIR
	jz	1f		# not a directory

	mov	edi, esp	# filename buffer
	LOAD_TXT "./index.html"
	call	fs_update_path
	# no need to check escape from docroot.
1:
	.if NET_HTTP_DEBUG > 1
		printc 13, "Serving file: '"
		mov	esi, esp	# filename buffer
		call	print
		printc 13, "' "
	.endif

	lea	eax, [esp]	# filename
	xor	edx, edx	# fs_open flags argument
	KAPI_CALL fs_open	# out: eax=handle, ecx=filesize
	jc	404f
	mov	[ebp - HTTP_STACKARGS + HTTP_STACK_FSIZE], ecx
	mov	[ebp - HTTP_STACKARGS + HTTP_STACK_FHANDLE], eax
#####################################
# [esp]=socket
# eax = file handle
	call	fs_handle_get_mtime	# out: esi -> 8 bytes
	jc	1f	# error getting mtime, skip ETag check

	# check ETag / If-None-Match
	cmp	dword ptr [ebp - HTTP_STACKARGS + HTTP_STACK_HDR_INM], 0
	stc
	jz	1f	# not present
#	DEBUG "have INM:" ; DEBUGS [ebp-HTTP_STACKARGS + HTTP_STACK_HDR_INM]
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_HDR_INM]
	# format: "YYMMDDhhmmss00-00000000"  (last dword=kernel rev)
	cmp	byte ptr [eax + 16], '-'
	stc
	jnz	91f
	mov	byte ptr [eax + 16], 0	# for htoid
	call	htoid	# out: edx:eax
	jc	91f	# wrong format
	cmp	edx, [esi]
	jnz	91f
	cmp	eax, [esi + 4]
	jnz	91f
	# check kernel revision
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_HDR_INM]
	add	eax, 16+1	# skip mtime and '-'
	call	htoi
	jc	91f
	cmp	eax, KERNEL_REVISION
91:
	jc	1f
	jnz	1f
##################
	# ETag matches
	mov	dword ptr [ebp - HTTP_STACKARGS + HTTP_STACK_HDR_INM], -2
	# send '304 Not Modified'
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_FHANDLE]
	KAPI_CALL fs_close

	LOAD_TXT "HTTP/1.1 304 Not Modified\r\nConnection: close\r\n\r\n", esi, ecx, 1
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	printlnc 10, "304"
	jmp	90f
1:
#####################################
# esi = -> 2 dwords mtime

# malloc file buffer
#	mov	eax, ecx
#	add	eax, 2047
#	and	eax, ~2047
#	add	eax, 8	# for time

	# allocate 2kb disk buffer and 128 bytes expression buffer
	mov	eax, 2048 + 128	# tested: 200kb buffer doesn't improve speed
	call	mallocz
	mov	edi, eax
	mov	[ebp - HTTP_STACKARGS + HTTP_STACK_FBUF], eax
	jnc 1f; printc 4, "mallocz error"; 1:
#TODO:	jc

	# now that we have the file open and the buffer allocated,
	# we can send a 200 OK

	# get the mime
	push	esi		# preserve mtime
	lea	esi, [esp + 4]	# filename
	call	http_get_mime	# out: esi
	mov	ebx, esi	# remember mime
	pop	esi		# mtime ptr

	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	call	_www_send_200$	# in: eax=tcp_conn,esi=mtime, ebx=mime

	# send file contents
10:	push	ecx
	cmp	ecx, 2048
	jb	11f
	mov	ecx, 2048
11:	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_FHANDLE]
	mov	edi, [ebp - HTTP_STACKARGS + HTTP_STACK_FBUF]
	KAPI_CALL fs_read	# in: edi,ecx,eax
	jnc 1f; printc 4, "fs_read error"; 1:
#TODO:	jc
	sub	[esp], ecx	# subtract the bytes read

	# evaluate expressions, only if mime is html
	cmp	ebx, offset _mime_text_html$
	jnz	5f		# not proper mime, do not parse
########

	push	ebx
	push	ecx		# source buf len remaining

	# edi = buf start
	# ecx = buf len
1:	mov	ecx, [esp]	# remaining buflen
	mov	ebx, edi	# start of unsent data
	call	www_findexpr	# in: edi,ecx; out: edi,ecx
	jc	3f		# not found at all
	# expression found - check if it's partial
# for now skip partial expressions
#	jz	4f		# potential expression found crossing buffer boundary

	# edi, ecx = expression
	lea	edx, [edi - 2]	# start of expression string
	sub	edx, ebx	# len of unsent data
	jz	2f		# expression at buffer start
	mov	esi, ebx	# start of unsent data
	lea	ebx, [edi + ecx + 1]	# end of expr = new start of unsent data
	sub	[esp], edx	# update remaining source len

	push	ecx
	mov	ecx, edx
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]

	KAPI_CALL socket_write

	pop	ecx
2:
		# assert: esi + edx = edi = start of expr
# use edi,ecx
	lea	edx, [ecx + 3]
	sub	[esp], edx	# update remaining source len

	# set up www_expr_handle args:
	# in: edi = expression
	# in: ecx = expression len
	# in: eax = socket
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]

	pushad
	push	ebp
	mov	ebp, [ebp - HTTP_STACKARGS + HTTP_STACK_FNAME]
	call	www_expr_handle
	pop	ebp
	popad

	lea	edi, [ebx];#[ebx + ecx]	# advance edi to end of expression

	jmp	1b	# see if there's more in this buffer
4:	# a potential expression has been found that crosses the
	# buffer boundary. A few cases:
	# 1) the last byte of the buffer is $
	# 2) the last 2 bytes of the buffer are ${
	# 3) the last 2+X bytes of the buffer are ${...
	# in the 4th case, ${....} the entire expression was found at 1b.
	# for now just skip.
3:	mov	edi, ebx # edi is trashed, restore
	pop	ecx		# restore remaining buffer len
	pop	ebx		# restore mime pointer
	jmp	6f	# preserve edi's position
########
	# send
5:	# complete skip of expr parsing, set edi properly
	mov	edi, [ebp - HTTP_STACKARGS + HTTP_STACK_FBUF]
6:	# send partial buffer
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	mov	esi, edi	# buffer
	KAPI_CALL socket_write
#TODO:	jc

	pop	ecx		# ecx is bytes remaining
	or	ecx, ecx
	jnz	10b

	# done.
	# free buffer:
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_FBUF]
	call	mfree
	jnc 1f; DEBUG "ERROR freeing buffer";1:

	# close file
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_FHANDLE]
	KAPI_CALL fs_close
	jnc 1f; DEBUG "ERROR closing file";1:

	# DONE!
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	jmp	90f

404:	mov	esi, offset www_code_404$
	mov	eax, [ebp - HTTP_STACKARGS + HTTP_STACK_SOCK]
	jmp	www_err_response

##################################
90:	mov	esp, ebp
	pop	ebp
	ret


# send http headers for a 200 OK.
#
# in: eax = tcp_conn
# in: esi: ptr to 8 bytes of file mtime
# in: ebx = mime
_www_send_200$:
	.if NET_HTTP_DEBUG
		printlnc 10, "200 "
	.endif
	push	ecx
	push	ebp
	mov	ebp, esp
	push	eax	# [ebp - 4]  tcp conn
	push	esi	# [ebp - 8]  mtime ptr

	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: ", esi, ecx, 1
	KAPI_CALL socket_write

	mov	esi, ebx	# mime
	call	strlen_
	KAPI_CALL socket_write

	push_	edi eax
	LOAD_TXT "\r\nETag: \"YYMMDDhhmmsszz00-KERNELRV\"", esi, ecx, 1
	lea	edi, [esi + 9]	# start of date
	mov	eax, [ebp - 8]	# mtime ptr
	mov	edx, [eax + 0]	# mtime in file buf
	call	sprinthex8
	mov	edx, [eax + 4]	# mtime 2nd dword
	call	sprinthex8
	inc	edi		# skip '-'
	mov	edx, KERNEL_REVISION
	call	sprinthex8
	pop_	eax edi
	KAPI_CALL socket_write

	LOAD_TXT "\r\nConnection: close\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush

	mov	esp, ebp	# restore
	pop	ebp
	pop	ecx
	ret


.section .strings
_mime_text_xml$:	.asciz "text/xml"
_mime_text_html$:	.asciz "text/html"
_mime_text_css$:	.asciz "text/css"
_mime_text_javascript$:	.asciz "text/javascript"
_mime_image_jpeg$:	.asciz "image/jpeg"
_mime_image_png$:	.asciz "image/png"
_mime_image_gif$:	.asciz "image/gif"
_mime_text_plain$:	.asciz "text/plain"
#_mime_text_x_asm$:	.asciz "text/x-asm"
_mime_text_x_java_source$:  .asciz "text/x-java-source"
_mime_application_unknown$: .asciz "application/unknown"

.data
mime_table:
	STRINGPTR "xml";	.long _mime_text_xml$
	STRINGPTR "xsl";	.long _mime_text_xml$
	STRINGPTR "html";	.long _mime_text_html$
	STRINGPTR "css";	.long _mime_text_css$
	STRINGPTR "js";		.long _mime_text_javascript$
	STRINGPTR "png";	.long _mime_image_png$
	STRINGPTR "jpg";	.long _mime_image_jpeg$
	STRINGPTR "jpeg";	.long _mime_image_jpeg$
	STRINGPTR "gif";	.long _mime_image_gif$
#	STRINGPTR "s";		.long _mime_text_x_asm$
	STRINGPTR "java";	.long _mime_text_plain$ #_mime_text_x_java_source$	# or text/plain
	.long 0;		.long _mime_application_unknown$
.text32

# in: esi
# out: esi
http_get_mime:
	push_	edi eax ecx edx
	call	strlen_
	mov	edx, ecx

	lea	edi, [esi + ecx]
	mov	al, '.'
	std
	repnz	scasb
	cld
	jnz	9f

	add	edi, 2
	add	ecx, 2

	mov	esi, edi
	sub	edx, ecx	# edx = len of filename extension

	mov	eax, offset mime_table
0:	mov	esi, [eax]
	or	esi, esi
	jz	9f
	push	edi
	mov	ecx, edx
	repz	cmpsb
	pop	edi
	jz	1f
	add	eax, 8
	jmp	0b
1:	mov	esi, [eax + 4]

0:	pop_	edx ecx eax edi
	ret
9:	mov	esi, offset _mime_application_unknown$
	jmp	0b

# in: esi = header
# in: ecx = header len
# in: esp+4 = space for header value pointers (above the ret)
# out: ebx = host ptr (in header), if any
# out: edx = -1 or resource name (GET /x -> /x)
http_parse_header:
	push	ebp
	lea	ebp, [esp + 8]
	push	eax
	push	edi
	mov	edx, -1		# the file to serve
	mov	ebx, -1		# the hostname
	mov	edi, esi	# mark beginning
0:	lodsb
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
	.if NET_HTTP_DEBUG > 1
		call	newline
	.endif
	call	http_parse_header_line$	# update edx if GET /..., ebx if Host:..
	mov	edi, esi	# mark new line beginning
	jc	9f
	jmp	1f

2:;	.if NET_HTTP_DEBUG > 1
		call	printchar
	.endif

1:	loop	0b
	.if NET_HTTP_DEBUG > 1
		call	newline
		clc
	.endif

9:	pop	edi
	pop	eax
	pop	ebp
	ret


# Parses the header, and zero-terminates the lines if there is a match
# for a GET / or Host: header.
# in: edi = start of header line
# in: esi = end of header line
# in: edx = known value (-1) to compare against
# in: ebp = ptr to array to store header value pointers
# out: edx = resource identifier (if request match): 0 for root, etc.
http_parse_header_line$:
	push_	edi esi ecx
	mov	ecx, esi
	sub	ecx, edi
	mov	esi, edi

	.if NET_HTTP_DEBUG > 1#2
		pushcolor 15
		push esi
		push ecx
		printchar '<'
		call nprint
		printchar '>'
		pop ecx
		pop esi
		popcolor
	.endif

	push_	ecx esi
	LOAD_TXT "GET /", edi, ecx, 1
	repz	cmpsb
	pop_	esi ecx
		mov	edi, esi	# for debug print
	jz	1f

	push_	ecx esi
	LOAD_TXT "Host: ", edi, ecx, 1
	repz	cmpsb
	pop_	esi ecx
	jz	2f

	push_	ecx esi
	LOAD_TXT "Referer: ", edi, ecx, 1
	repz	cmpsb
	pop_	esi ecx
	jz	3f

	push_	ecx esi
	LOAD_TXT "If-None-Match: ", edi, ecx, 1
	repz	cmpsb
	pop_	esi ecx
	jz	4f

	clc
	jmp	9f

################################################
4:	# found If-None-Match header
	add	esi, 15
	sub	ecx, 15
	push_	ecx eax esi
	mov	al, '\n'
	mov	edi, esi
	repnz	scasb
	stc
	jnz	91f
	cmp	byte ptr [edi-2], '\r'
	jnz	92f
	dec	edi
92:	mov	byte ptr [edi-1], 0
	.if NET_HTTP_DEBUG > 1
		printc 15, "If-None-Match: "
		call	print
	.endif
	# strip
	cmp	byte ptr [esi], '"'
	jnz	91f
	cmp	byte ptr [edi-2], '"'
	jnz	91f
	inc	esi
	mov	byte ptr [edi-2], 0
	mov	[ebp + HTTP_STACK_HDR_INM], esi

91:	pop_	esi eax ecx
	jmp	9f

3:	# found referer header:
	add	esi, 9
	sub	ecx, 9
	.if 1
		push_	ecx eax esi
		mov	edi, esi
		mov	al, '\n'
		repnz	scasb
		jnz	3f
		cmp	byte ptr [edi-2], '\r'
		jnz	5f
		dec	edi
	5:	printc 14, "Referer: "
		mov	byte ptr [edi - 1], 0
		mov	[ebp + HTTP_STACK_HDR_REFERER], esi
		mov	ecx, edi
		sub	ecx, esi
		call	nprint
		call	printspace
		jmp	4f
	3:	printc 4, "referer: no eol"
	4:	pop_	esi eax ecx
	.endif
	jmp	0f


2:	# found Host header line
	cmp	ebx, -1
	jz	2f
	printc 4, "Duplicate 'Host:' header: "
	call	nprintln
	stc
	jmp	9f
2:	add	esi, 6		# skip "Host: "
	sub	ecx, 6
	mov	ebx, esi	# start of hostname

	mov	[ebp + HTTP_STACK_HDR_HOST], esi

	.if NET_HTTP_DEBUG > 1
		mov	edi, esi
		printc 9, "Host: <"
	.endif

	jmp	0f

1:	# found GET header line
	add	esi, 4		# preserve the leading /
	sub	ecx, 4
	jle	9f
	mov	edx, esi	# start of resource
	.if NET_HTTP_DEBUG > 1
		printc 9, "GET: <"
		mov	edi, esi
	.endif

0:	lodsb
	cmp	al, ' '
	jz	0f
	cmp	al, '\n'
	jz	0f
	cmp	al, '\r'
	jz	0f
	loop	0b
	# hmmm

	.if NET_HTTP_DEBUG > 1
		printc 9, "Resource: <"
	.endif


0:	mov	[esi - 1], byte ptr 0

	mov	[ebp + HTTP_STACK_HDR_RESOURCE], edi	# store resource

	.if NET_HTTP_DEBUG > 1
		# mov ecx, esi; sub ecx, ebx; mov esi, ebx; call nprint
		mov	esi, edi
		call	print
		printlnc 9, ">"
	.endif
	clc

9:	pop_	ecx esi edi
	ret



# in: edi = data to scan
# in: ecx = data len
# out: edx = argument offset (say, ${include foo}, edx->foo)
# out: edi, ecx: expression string
www_findexpr:
	push	esi
	push	eax
	xor	edx, edx

	mov	al, '$'
	repnz	scasb
	jnz	1f	# no expressions
	cmp	[edi], byte ptr '{'
	jnz	1f
	inc	edi

	# parse expression
	mov	esi, edi	# start of expr

	#mov	al, '}'
	#repnz	scasb
	#jnz	1f

0:	dec	ecx
	jle	1f
	lodsb
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

kernel_get_uptime:
	push	edi
	call	get_time_ms_40_24
	call	sprint_time_ms_40_24
	mov	ecx, edi
	pop	edi
	sub	ecx, edi
	ret
.data
www_expr:

# first byte: handler type:
WWW_EXPR_H_CONST= 1
WWW_EXPR_H_MEM	= 2
WWW_EXPR_H_CALL	= 3
# Second byte: data type:
WWW_EXPR_T_NONE	= 0 # 0 = none - handler outputs to socket directly (maybe)
WWW_EXPR_T_SIZE	= 1 # 1 = size   (out: edx:eax)
WWW_EXPR_T_STRING=2 # 2 = string (in: esi,ecx)
WWW_EXPR_T_DEC32= 3 # 3 = decimal32 (out: edx)
WWW_EXPR_T_HEX8	= 4 # 4 = hex8

.long (99f - .)/10	# number of expressions
STRINGPTR "kernel.revision";	.byte 1,3;.long KERNEL_REVISION
STRINGPTR "kernel.uptime";	.byte 3,2;.long kernel_get_uptime
STRINGPTR "kernel.stats.ts";	.byte 2,3;.long stats_task_switches
STRINGPTR "kernel.stats.kc";	.byte 2,3;.long stats_kernel_calls
STRINGPTR "httpd.stats.rq";	.byte 2,3;.long stats_httpd_requests
STRINGPTR "include";		.byte 3,0;.long expr_include
.if 1
STRINGPTR "kernel.size";	.byte 3,1;.long expr_krnl_get_size
STRINGPTR "kernel.code.size";	.byte 3,1;.long expr_krnl_get_code_size
STRINGPTR "kernel.data.size";	.byte 3,1;.long expr_krnl_get_data_size
STRINGPTR "mem.heap.size";	.byte 2,1;.long mem_heap_size
.else
STRINGPTR "kernel.size";	.byte 1,1;#.long kernel_end - kernel_start
	.long kernel_code_end - kernel_code_start + kernel_end - data_0_start
STRINGPTR "kernel.code.size";	.byte 1,1;.long kernel_code_end - kernel_code_start
STRINGPTR "kernel.data.size";	.byte 1,1;.long kernel_end - data_0_start
STRINGPTR "mem.heap.size";	.byte 2,1;.long mem_heap_size
.endif
STRINGPTR "mem.heap.allocated";	.byte 3,1;.long mem_get_used
STRINGPTR "mem.heap.reserved";	.byte 3,1;.long mem_get_reserved
STRINGPTR "mem.heap.free";	.byte 3,1;.long mem_get_free
STRINGPTR "cluster.kernel.revision";	.byte 3,2;.long cluster_get_kernel_revision
STRINGPTR "cluster.status";	.byte 3,0;.long cluster_stream_cluster_status
STRINGPTR "cluster.nodes.list";	.byte 3,0;.long cluster_stream_nodes_list
STRINGPTR "cluster.nodes.table";.byte 3,0;.long cluster_stream_nodes_table
99:
www_expr_handlers:
	.long expr_h_unknown
	.long expr_h_const
	.long expr_h_mem
	.long expr_h_call
NUM_EXPR_HANDLERS = (.-www_expr_handlers)/4
.text32
expr_krnl_get_size:
	xor	edx, edx
	mov	eax, offset KERNEL_SIZE
#	mov	eax, offset kernel_code_end
#	sub	eax, offset kernel_code_start
#	add	eax, offset kernel_end
#	sub	eax, offset data_0_start
	ret
expr_krnl_get_code_size:
	xor	edx, edx
	mov	eax, offset KERNEL_CODE32_SIZE
	add	eax, offset KERNEL_CODE16_SIZE
	ret
expr_krnl_get_data_size:
	xor	edx, edx
	mov	eax, offset KERNEL_DATA_SIZE
	ret

# in: ebx = expression argument string: expect filename
# in: [ebp] = socket
# in: [ebp+4] = www_file (the file containing the expression)
#[in: edi,ecx=1kb expr buffer]
expr_include:
	#	DEBUG "include"
	#	DEBUGS ebx
	pushad

	# use static www_file$

	mov	esi, [ebp + 4]#offset www_file$
	call	strlen_
	lea	edi, [esi + ecx]
0:	cmpb	[edi], '/'
	jz	1f
	dec	edi
	loop	0b
	jmp	91f

1:
#	mov	al, '/'
#	std
#	repnz	scasd
#	cld
	#jnz	91f
	inc	edi
	movb	[edi], 0

	mov	edi, [ebp + 4]#offset www_file$
	mov	esi, ebx
	call	fs_update_path

	# check whether path is still in docroot:
	mov	esi, offset www_docroot$
	mov	edi, [ebp + 4]#offset www_file$
	mov	ecx, WWW_DOCROOT_STR_LEN - 1 # skip null terminator
	repz	cmpsb
	mov	esi, offset www_code_404$
	jnz	92f

		mov	eax, [ebp + 4] #offset www_file$
		xor	edx, edx	# fs_open flags argument
		KAPI_CALL fs_open
		jc	93f
		mov	ebx, eax

		mov	eax, ecx
		add	eax, 2047
		and	eax, ~2047
		call	mallocz
		mov	edi, eax
		mov	esi, eax

		mov	eax, ebx
		KAPI_CALL fs_read	# in: edi,ecx,eax
		#jc

		KAPI_CALL fs_close
		#jc

		mov	eax, [ebp]
		KAPI_CALL socket_write	# eax, esi, ecx; out: esi, ecx

		mov	eax, edi
		call	mfree

9:	popad
	ret
91:	printc 4, "illegal www_file$: no /: "
0:	call	println
	stc
	jmp	9b
92:	printc 4, "include path exceeds docroot: "
1:	mov	esi, [ebp + 4] # offset www_file$
	jmp	0b
93:	printc 4, "include file not found: "
	jmp	1b

# in: eax = socket
# in: edi = expression
# in: ecx = expression len
# in: ebp = www_file buffer pointer (stack,len=1024)
# free to use: edx, esi
www_expr_handle:
	.if WWW_EXPR_DEBUG
		DEBUG "EXPR"
		mov esi, edi
		call nprint

		pushad
		LOAD_TXT "<!-- begin expr ", esi, ecx
		KAPI_CALL socket_write
		popad
		pushad
		KAPI_CALL socket_write # write the expr
		LOAD_TXT "-->", esi, ecx
		KAPI_CALL socket_write
		popad
	.endif
	xor	esi,esi
	push	esi
	push	ebx
	push	ecx	# expr len
	push	edi	# expr
	#lea	esi, [ebp + 4]
	mov	esi, ebp
	push	esi
	xor	esi, esi
	push	eax

	mov	byte ptr [edi + ecx], 0	# '}' -> 0
	inc	ecx	# include 0 terminator for rep cmpsb
	push	edi
	push	eax
	mov	al, ' '
	repnz	scasb
	pop	eax
	jnz	1f
	neg	ecx
	add	ecx, [esp + 4*4]	# trunc
	mov	[esp + 6*4], edi
	mov	[esp + 4*4], ecx	# update expr len
1:	pop	edi
	mov	ecx, [esp + 3*4]

	.if 0
		DEBUG "www_expr_handle:"
		push	esi
		mov	esi, edi
		call	nprint
		pop	esi
		call	newline
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
		DEBUG "no matches for expr:"
		mov esi, edi
		call nprint
	# not found
	jmp	9f

######################################################
# ebx = www_expr structure ptr
1:	movzx	edx, byte ptr [ebx + 4]	# handler index
	and	dl, 0x7f
	cmp	dl, NUM_EXPR_HANDLERS
	jae	9f

######## call handler
	# check for types that need a buffer
	#cmp	byte ptr [ebx + 5], WWW_EXPR_T_STRING	# buffer arg
	#jnz	1f
	call	expr_get_buffer$	# out: edi, ecx
	#DEBUG "BUF"
#1:
	movzx	eax, dl
	mov	edx, [ebx + 6]		# arg2

	push	ebx
	mov	ebx, [esp + 6*4]	# filename ptr
	push	ebp
	lea	ebp, [esp + 8]		# [ebp] = socket
	call	www_expr_handlers[eax * 4]
	pop	ebp
	pop	ebx
########
	mov	edi, offset _tmp_fmt$

	mov	bl, [ebx + 5]	# data type / format
	cmp	bl, WWW_EXPR_T_STRING
	jnz	1f
	# verify buffer
	mov	esi, offset _tmp_expr_buf$
	cmp	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)
	jb	2f	# flush
	mov	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)-1
	jmp	2f	# flush

1:	or	bl, bl	# WWW_EXPR_T_NONE
	jz	9f	# handler took care of sending stuff

	cmp	bl, WWW_EXPR_T_DEC32
	jnz	1f
	mov	edx, eax
	call	sprintdec32
	jmp	3f

1:	cmp	bl, WWW_EXPR_T_HEX8
	jnz	1f
	mov	edx, eax
	call	sprinthex8
	jmp	3f

1:	cmp	bl, WWW_EXPR_T_SIZE
	jnz	9f	# unknown type
	# data type: size: edx:eax
	# todo: format
	.data SECTION_DATA_BSS
	_tmp_fmt$: .space 32
	_tmp_expr_buf$: .space 1024
	_tmp_expr_buf_end$:
	.text32
	call	sprint_size
########
3:	mov	ecx, edi
	mov	esi, offset _tmp_fmt$
	sub	ecx, esi

2:
	.if WWW_EXPR_DEBUG
		DEBUG "EXPR VAL:"
		call nprint
		call newline
	.endif

	mov	eax, [esp]
	KAPI_CALL socket_write
9:
	.if WWW_EXPR_DEBUG
		mov eax, [esp]
		LOAD_TXT "<!-- end of expr -->", esi, ecx
		KAPI_CALL socket_write
	.endif

	pop	eax
	pop	esi	# www_file
	pop	edi
	pop	ecx
	pop	ebx
	pop	esi
	ret


# out: edi, ecx
expr_get_buffer$:
	push	eax
	mov	edi, offset _tmp_expr_buf$
	mov	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)/4
	xor	eax, eax
	rep	stosd
	mov	edi, offset _tmp_expr_buf$
	mov	ecx, offset _tmp_expr_buf_end$-_tmp_expr_buf$
	pop	eax
	ret


.section .strings
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

# JUMP target: do not call!
# in: ebp = stack pointer: replaces esp with ebp and pops ebp
www_err_response:
	mov	esp, ebp		# for convenience jumping
	pop	ebp

	.if NET_HTTP_DEBUG
		mov	ecx, 4
		pushcolor 12
		call	nprintln
		popcolor
	.endif

	mov	edx, esi

	mov	esi, offset www_h$
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, edx
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_h2$
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_content1$
	call	strlen_
	KAPI_CALL socket_write

	lea	esi, [edx + 4]
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_content2$
	call	strlen_
	KAPI_CALL socket_write

	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret

# in: eax = tcp conn
www_gzip_test:
	push_	eax ebx ecx edx edi
	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: application/x-gzip\r\n\r\n", esi, ecx, 1
	KAPI_CALL socket_write

	mov	eax, 1024
	call	mallocz
	jc	91f
	mov	ebx, eax

		mov	edi, eax
		mov	ecx, 1024
		call	gzip

		DEBUG_DWORD [ebx]

		mov	ecx, edi
		mov	esi, ebx
		sub	ecx, ebx
		DEBUG_DWORD ecx, "compressed size"
		mov	eax, [esp + 4*4]
		KAPI_CALL socket_write

	mov	eax, ebx
	call	mfree

	mov	eax, [esp + 4*4]
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	pop_	edi edx ecx ebx eax
	ret

91:	pop_	edi edx ecx ebx eax
	add	esp, 4
	mov	esi, offset www_code_500$
	jmp	www_err_response


# in: eax = tcp conn
www_send_screen:
	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n", esi, ecx, 1
	KAPI_CALL socket_write

.section .strings
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
	KAPI_CALL socket_write

SEND_BUFFER = 1
	push	fs
.if SEND_BUFFER
	mov	ebx, ds
	mov	fs, ebx
	push	eax
	call	console_get
	mov	ebx, [eax + console_screen_buf]
	pop	eax
	mov	ecx, 25 * SCREEN_BUF_PAGES
.else
	mov	ebx, SEL_vid_txt
	mov	fs, ebx
	xor	ebx, ebx
	mov	ecx, 25
.endif
0:	push	ecx
#######
	mov	ecx, 80
	.data SECTION_DATA_BSS
	_www_scr$: .space 80 * 32 # 13
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
	# close the span; TODO FIXME: check whether one is open!
	# (however better than now where EOL's are not closed!)
	mov	[edi], dword ptr ('<'|'/'<<8|'s'<<16|'p'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'n'<<8|'>'<<16)
	add	edi, 3

	mov	[edi], byte ptr '\n'
	inc	edi
	pop	eax
#######
	mov	esi, offset _www_scr$
	mov	ecx, edi
	sub	ecx, esi
	KAPI_CALL socket_write
	pop	ecx
	dec	ecx
	jnz	0b

	pop	fs

	LOAD_TXT "</pre></body></html>\n"
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret

.include "../lib/gzip.s"
