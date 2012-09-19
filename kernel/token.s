.intel_syntax noprefix

.data
	src: .ascii "string 123 ;"
		.byte '\n'
	src_len = . - src
.data 2
	tokens: .space src_len * 8 + 8

.text32
# in: esi = src, edi = target
compile:
	mov	eax, ds
	mov	es, eax

	mov	edi, offset tokens
	mov	esi, offset src
	mov	ecx, src_len
	call	tokenize

	mov	ebx, edi
	mov	esi, offset tokens
	call	printtokens

	ret



printtokens:

0:	# load and print type
	lodsd
	mov	dl, al
	call	printhex2
	PRINTCHAR ' '

	inc	eax
	jz	eof

	# load source offset
	lodsd
	# calculate length
	mov	ecx, [esi + 4]
	sub	ecx, eax
	jz	eof

	mov	edx, ecx	# print length
	call	printhex8
	.if 0
	printchar ' '
	mov	edx, esi	# print token offset
	sub	edx, 8
	call	printhex8
	printchar ' '
	mov	edx, eax	# print string offset
	call	printhex8
	.endif
.if 1
	# print token
	push	esi
	mov	esi, eax
	mov	al, ' '
	call	printchar
	mov	al, '\''
	call	printchar
1:	lodsb
	call	printchar
	loop	1b
	pop	esi
	mov	al, '\''
	call	printchar
.endif
	call	newline
	cmp	esi, ebx
	jb	0b

	println "Missing EOF token"


eof:	mov	edx, [esi + 8]
	sub	edx, [esi]
	call	printhex8
	.if 0
	printchar ' '
	mov	edx, esi
	call	printhex8
	printchar ' '
	mov	edx, [esi]
	call	printhex8
	.endif
	PRINTln	" EOF"
	ret


.data
ascii:	
	.byte 0, 1, 2, 3, 4, 5, 6, 7, 8, '\t', '\n', 11, 12, '\r', 14, 15, 16
	.byte 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, ' '
	#.byte 33
     
	.byte '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-'
	.byte  '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
	.byte ':', ';', '<', '=', '>', '?', '@'
	.byte 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M'
	.byte 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
	.byte '[', '\\', ']', '^', '_', '`'
	.byte 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm'
	.byte 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
	.byte '{', '|', '}', '~', 127

	.byte 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140
	.byte 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153
	.byte 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166
	.byte 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179
	.byte 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192
	.byte 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205
	.byte 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218
	.byte 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231
	.byte 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244
	.byte 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255

ALPHA = 1
DIGIT = 2
SPACE = 3
EOL = 4

charclass:
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte SPACE # '\t'
	.byte EOL # '\n'
	.byte 0, 0
	.byte SPACE # '\r' (13)
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte SPACE # ' ' (32)
	#.byte 0 # 33

	.byte '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-'
	.byte  '.', '/'
	.byte DIGIT, DIGIT, DIGIT, DIGIT, DIGIT
	.byte DIGIT, DIGIT, DIGIT, DIGIT, DIGIT 
	.byte ':', ';', '<', '=', '>', '?', '@'
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte '[', '\\', ']', '^', '_', '`'
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA, ALPHA
	.byte '{', '|', '}', '~', 0 # (127)

	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0

cchandler:
	.long cc_unknown	
	.long cc_ascii
	.long cc_digit
	.long cc_space


.text32
# in: esi = source, ecx = source len, edi = out token array,
# out: edi = points to token after last token
# destroyed: ecx, eax, esi, ebx, dl
#
# TOKEN:
# dd type
# dd src_offset

tokenize:
	jecxz	2f

	mov	ebx, offset charclass

	# first token setup
	lodsb	
	xlatb
	jmp	1f

0:	lodsb
	xlatb
	cmp	al, dl
	jnz	1f
	loop	0b

	jmp	2f

1:	stosd			# store type
	mov	dl, al
	mov	eax, esi
	dec	eax
	stosd			# store start offset
	xor	eax, eax

	loop	0b

2:	inc	esi

	mov	eax, -1
	stosd
	mov	[edi + 4], eax
	mov	eax, esi
	dec	eax
	stosd
	mov	[edi + 4], eax

	ret

##############################################################################
## tokens_merge
#
# This method merges all non-space separated tokens into an array of strings.
# The array consists of ebx pointing to an array of pointers, the last one
# zero, and edi, a buffer to hold the (concatenated) zero terminated strings.
# All space tokens are removed, yielding only the non-space characters.
# The tokenizer splits on character class boundaries, so that "a/b c"
# will be tokenized as ["a", "/", "b", " ", "c"].
# The resulting output will be ["a/b", "c"]
#
# in: edx = pointer to tokens produced by tokenize
# in: ecx = pointer to the end of the tokens (for buffer overflow checks)
# in: ebx = pointer to an array able to hold pointers into stringdata
# in: edi = pointer to stringdata able to hold the token string (asciz)
# destroys: esi, eax
# out: ebx = pointer to last string + 1 ([ebx] = 0)
# out: edi = pointer to end of string buffer
# out: esi = pointer to last token's end of string.
tokens_merge:
	mov	[ebx], dword ptr 0
	jmp	0f
1:	add	edx, 8
0:	#cmp	edx, ecx		# safety check
	#jae	0f
	cmp	byte ptr [edx], -1
	je	0f
	cmp	byte ptr [edx], SPACE	# skip spaces
	je	1b

	mov	[ebx], edi
	add	ebx, 4
	mov	[ebx], dword ptr 0

1:	mov	esi, [edx + 4]
	mov	ecx, [edx + 4 + 8]
	add	edx, 8
	sub	ecx, esi
	jbe	1f	# jbe(cf=1|zf=1)  jle(cf=1|sf!=of)

	rep	movsb

	# check if the next token is space
	mov	al, [edx]
	cmp	al, SPACE
	jne	1b

	# it's a space, so terminate the argv entry
1:	xor	al, al
	stosb
	jmp	0b
0:	#mov	[ebx + 4], dword ptr 0	# case no strings and [ebx+4] expected
	ret


###############################################################################



cc_unknown:
	ret
cc_ascii:
	ret
cc_digit:
	ret
cc_space:
	ret

	


# in: eax (al )= token type 
# in: edx = pointer to struct:
#   .long num_tokens
#   .rept num_tokens               .byte token_type           .endr
#   .rept num_tokens               .byte token_handler_index  .endr
#   .rept max(token_handler_index) .long offset token_handler .endr
# out: edx = offset token_handler
#
# Example usage:
#
# .data
#	token_handler_data: .long token_handler_indices - token_types
#	token_types:		.byte a, b, c, d # these two must be
#	token_handler_indices:	.byte 0, 0, 1, 2 # of equal length
#	token_handlers:		.long handler0, handler1, handler2
# .text32
# mov	al, ALPHA
# mov	edx, offset token_handler_data
# call	get_token_handler
# jnz	no_match
# jmp	edx
#
# Why both an index array and a handler-pointer array? Why not:
#   .long num_tokens
#   .rept num_tokens  .byte token_type           .endr
#   .rept num_tokens  .long offset token_handler .endr
#
# This is due to space considerations, as often multiple token types
# use the same handler, and token type indices are 1 byte whereas offsets
# are 4 bytes.
# Space considerations then:
# When each token type has a unique handler, the space taken is:
# First: 6 bytes per token+handler
# Second: 5 bytes per token+handler
# When different token types share the same handler, compression is
# as follows:
# # same token handler	first		second
# 1 			1 + 1 + 4 = 6	1 + 4 = 5
# 2			2 + 2 + 4 = 8	2 + 8 = 10
# 3			3 + 3 + 4 = 10	3 + 12= 15
# 10			10+10 + 4 = 24	10+40 = 50
get_token_handler:
	push	edi
	push	ecx
	mov	ecx, [edx]
	mov	edi, edx
	add	edi, 4
	repne	scasb
	jnz	0f
	# edi -1 points to the matched token type 
	# [edx] - ecx - 1 = index of token type in array
	# adding then [edx] -1 to edi makes edi point to the token handler type
	add	edi, [edx]	# edi points to token_handler_type +1
	movzx	edi, byte ptr [edi-1]	# index to token_handler_type
	# now add the offset to the token handler list to it.
	mov	ecx, [edx]	# num token types
	shl	ecx, 1		# two arrays
	add	ecx, edx	# add base offset
	add	ecx, 4		# add size of num token types mem addr
	# ecx should now point to path_token_handlers$

	mov	edx, [ecx + edi*4]
	add	edx, [realsegflat]

	xor	ecx, ecx	# set zero flag
0:	pop	ecx
	pop	edi
	ret



	.macro GET_TOKEN nr
		lea	esi, [cmdline_tokens +16 +  8 * \nr ]

		cmp	[cmdline_tokens_end], esi
		jb	9f	# jb = jc
		sub	esi, 16
		.if DEBUG_TOKENS
		jmp	8f
	9:	PRINTc 4, "No such token \nr - max tokens: "
		mov	edx, [cmdline_tokens_end]
		sub	edx, offset cmdline_tokens
		shr	edx, 3
		call	printhex
		call	newline
		stc
	8:	
		.else
	9:	
		.endif
	.endm



	.macro GET_TOKEN_STRING nr
		mov	esi, offset cmdline_tokens  + 8 * \nr + 16

		cmp	[cmdline_tokens_end], esi
		jb	9f	# jb = jc
		sub	esi, 12
		mov	ecx, [esi + 8]
		mov	esi, [esi]
		sub	ecx, esi
		.if DEBUG_TOKENS
		jmp	8f
	9:	PRINTc 4, "No such token \nr - max tokens: "
		mov	edx, [cmdline_tokens_end]
		sub	edx, offset cmdline_tokens
		shr	edx, 3
		call	printhex
		call	newline
		stc
	8:	
		.else
	9:	
		.endif
	.endm

	.macro IS_TOKEN tok
		.data
		9: .ascii "\tok"
		8: 
		.text32
		push	esi
		mov	esi, offset cmdline_tokens + 4
		mov	ecx, [esi+8]
		mov	esi, [esi]
		sub	ecx, esi
		cmp	ecx, 8b - 9b
		jne	9f
		mov	edi, offset 9b
		repz	cmpsb
	9:	pop	esi
	.endm

