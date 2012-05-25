.intel_syntax noprefix

.data 2
MAX_CMDLINE_LEN = 1024
cmdlinelen: .long 0
cmdline: .space MAX_CMDLINE_LEN
cmdline_tokens_end: .long 0
cmdline_tokens: .space MAX_CMDLINE_LEN * 8 / 2	 # assume 2-char min token avg

MAX_CMDLINE_ARGS = 256
cmdline_argdata: .space MAX_CMDLINE_LEN + MAX_CMDLINE_ARGS
cmdline_args:	.space MAX_CMDLINE_ARGS * 4
insertmode: .byte 1
cursorpos: .long 0
.text
.code32

shell:	push	ds
	pop	es
	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"


	# TODO: malloc the buffers


	mov	[cwd$], word ptr '/'
	mov	[insertmode], byte ptr 1

start$:
	mov	esi, offset cwd$
	call	print
	printc 15, "> "

	mov	dword ptr [cursorpos], 0
	mov	dword ptr [cmdlinelen], 0

0:
	call	print_cmdline$

	mov	edi, offset cmdline
	add	edi, [cursorpos]

	xor	ax, ax
	call	keyboard
	.if 0
	pushcolor 10
	push	ax
	mov	dx, ax
	call	printhex4
	mov	al, ' '
	call	printchar
	mov	al, dl
	call	printchar
	mov	al, ' '
	call	printchar
	pop	ax
	popcolor
	.endif

	cmp	ax, K_ESC
	jz	clear$

	cmp	ax, K_ENTER
	jz	enter$

	cmp	ax, K_BACKSPACE
	jz	bs$

	cmp	ax, K_LEFT
	jz	left$
	cmp	ax, K_RIGHT
	jz	right$

	cmp	ax, K_INSERT
	jz	toggleinsert$

	cmp	al, 127
	jae	0b	# ignore
	cmp	al, 32
	jb	0b	# ignore
	
1:	#cmp	byte ptr [insertmode], 0
	#jz	insert$
	# overwrite
#insert$:
	# overwrite
	cmp	[cmdlinelen], dword ptr 1024-1	# check insert
	# beep
	jb	1f	
	# beep
	jmp	0b
1:	
	cmp	byte ptr [insertmode], 0
	jz	1f
	# insert
	push	edi
	mov	edi, [cursorpos]
	mov	ecx, [cmdlinelen]
	sub	ecx, edi
	add	edi, offset cmdline
	mov	esi, edi
	inc	edi
	rep movsb
	pop	edi
1:	# overwrite
	stosb
	inc	dword ptr [cursorpos]
	inc	dword ptr [cmdlinelen]

	jmp	0b

enter$:	
	PRINT_START
	add	edi, [cursorpos]
	add	edi, [cursorpos]
	xor	es:[edi + 1], byte ptr 0xff
	PRINT_END
	call	newline

	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$

	DEBUG_TOKENS = 0

	.if DEBUG_TOKENS
	PRINTc 9, "CMDLINE: \""
	mov	esi, offset cmdline
	call	nprint
	PRINTLNc 9, "\""
	mov	edx, ecx
	call	printhex8
	call	newline
	.endif

	push	ecx
	mov	edi, offset cmdline_tokens
	mov	esi, offset cmdline
	#mov	ecx, [cmdlinelen]
	call	tokenize
	mov	[cmdline_tokens_end], edi
	.if DEBUG_TOKENS
	mov	ebx, edi
	mov	esi, offset cmdline_tokens
	call	printtokens
	.endif
	pop	ecx


	# create an argument list:
	mov	ebx, offset cmdline_args
	mov	edi, offset cmdline_argdata
	mov	edx, offset cmdline_tokens
	mov	ecx, [cmdline_tokens_end]	# unused
	call	tokens_merge

	########################

	# debug the arguments:
	.if DEBUG_TOKENS
	printc 10, "ARGS: "
	mov	edx, ebx
	sub	edx, offset cmdline_args
	shr	edx, 2
	call	printdec32
	mov	ebx, offset cmdline_args
0:	
	mov	esi, [ebx]
	or	esi, esi
	jz	0f
	printcharc 10, '<'
	call	print
	printcharc 10, '>'
	add	ebx, 4
	jmp	0b
0:	call	newline
	.endif


	mov	esi, offset cmdline_args

	.macro IS_COMMAND str
		.data
		9: .ascii "\str\0"
		8: 
		.text
		push	esi
		mov	esi, [cmdline_args + 0]
		or	esi, esi
		jz	9f
		mov	ecx, 8b - 9b
		mov	edi, offset 9b
		repz	cmpsb
	9:	pop	esi
	.endm

	IS_COMMAND "ls"
	jnz	1f
	printlnc 11, "Directory Listing."
	xor	eax, eax
	call	ls$
	jmp	start$
1:
	IS_COMMAND "cluster"
	jnz	1f
	mov	eax, 2
	call	ls$
	jmp	start$
1:
	IS_COMMAND "cd"
	jnz	1f
	call	cd$
	jmp	start$
1:
	IS_COMMAND "pwd"
	jnz	1f
	mov	esi, offset cwd$
	call	println
	jmp	start$
1:
	IS_COMMAND "cls"
	jnz	1f
	call	cls
	jmp	start$
1:
	IS_COMMAND "disks"
	jnz	1f
	call	disks_print$
	jmp	start$
1:
	IS_COMMAND "fdisk"
	jnz	1f
	call	cmd_fdisk$
	jmp	start$
1:
	IS_COMMAND "partinfo"
	jnz	1f
	call	cmd_partinfo$
	jmp	start$
1:
	IS_COMMAND "mtest"
	jnz	1f
	call	malloc_test$
	jmp	start$
1:
	IS_COMMAND "mem"
	jnz	1f
	call	print_handles$
	jmp	start$
1:
	IS_COMMAND "quit"
	jnz	1f
	printlnc 12, "Terminating shell."

	mov	edx, esp
	call	printhex8

	xor	eax, eax
	call	keyboard
	ret

1:	PRINTLNc 4, "Unknown command"
	jmp	start$

bs$:	
	push	edi
	cmp	edi, offset cmdline 
	jbe	0b
	cmp	edi, [cmdlinelen]
	jz	1f
	mov	esi, edi
	dec	edi
	mov	ecx, 1024 + offset cmdline
	sub	ecx, esi
	jz	2f
	rep	movsb
2:	pop	edi


1:	dec	dword ptr [cursorpos]
	jns	1f
	printc 4, "Error: cursorpos < 0"
1:
	dec	dword ptr [cmdlinelen]
	jns	1f
	PRINTlnc 4, "Error: cmdlinelen < 0"
1:	jmp	0b

left$:	dec	dword ptr [cursorpos]
	jns	start$
	inc	dword ptr [cursorpos]
	jmp	start$

right$:	mov	eax, [cursorpos]
	cmp	eax, [cmdlinelen]
	jae	start$
	inc	dword ptr [cursorpos]
	jmp	start$

clear$:	mov	ax,(7<<8)| ' '
	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$
	PRINT_START
	push	edi
	inc	ecx
1:	stosw	#call	printchar
	loop	1b
	pop	edi
	PRINT_END
	jmp	0b # start$

toggleinsert$:
	xor	byte ptr [insertmode], 1
	jmp	start$

# destroys: ecx, esi, ebx
print_cmdline$:
	push	esi
	push	ecx
	push	ebx

	PRINT_START
	push	edi

	mov	ebx, edi
	mov	ecx, [cmdlinelen]
	jecxz	2f
	mov	esi, offset cmdline

1:	lodsb
	stosw
	loop	1b

2:	mov	al, ' '
	stosw
	stosw

	add	ebx, [cursorpos]
	add	ebx, [cursorpos]
	xor	es:[ebx+1], byte ptr 0xff

	pop	edi
	PRINT_END

	pop	ebx
	pop	ecx
	pop	esi

	ret

.data
cmdline_identifier: .byte ALPHA, DIGIT, '_', '.'
cmdline_id_size = . - cmdline_identifier
CMDTOK_ID = 1
CMDTOK_PATH = 2
.text

# merge tokens
process_tokens:
	mov	esi, offset cmdline_tokens
	xor	edx, edx
0:	lodsd
	cmp	eax, -1
	jz	1f

	# check for identifier tokens
	mov	edi, offset cmdline_identifier
	mov	ecx, cmdline_id_size
	repne	scasb
	jnz	2f

id$:	shl	dx, 8
	mov	dl, CMDTOK_ID
	println "Identifier"

	cmp	dl, dh
	jz	0b
	PRINT "End token: "
	ror	dx, 8
	call	printhex2
	ror	dx, 8
	jmp	3f

2:	cmp	al, '\\'
	jnz	2f
2:

3:	lodsd
	jmp	0b

1:
	ret

_tmp_init$:
	.data
	8: .asciz "0"
	9: .long 0, 8b
	.text
	mov	esi, offset 9b
	call	cmd_partinfo$
	ret

######################################
cd$:	
	mov	ebx, [fat_root_lba$]
	or	ebx, ebx
	jnz	0f

	call	_tmp_init$
0:	
	#########

	call	cd_apply$
	jc	0f

	inc	ecx

	mov	ebp, ecx	# remember len
	mov	ebx, esi

	# attempt to change the directory
	# parse it again, this time just using path separators:

	mov	edi, esi
	mov	al, '/'

1:	repne	scasb
	jnz	1f
	mov	edx, ecx
	call	printhex8
	printchar ' '

	push	ecx
	mov	ecx, edi
	sub	ecx, esi
	call	nprint
	call	newline

#########################
	push	edi
	push	ebx
	push	ebp

	push	esi
	push	ecx

	# now find what lba to load.
	
	cmp	ecx, 1
	jnz	2f
	mov	ebx, [fat_root_lba$]
	jmp	3f
2:	
	# find the directory entry
	dec	ecx
	call	fat_find_dir	# esi ecx
	# returns ebx = cluster



3:	mov	edi, offset tmp_buf$
	mov	ecx, 1
	mov	al, [tmp_drv$]
	call	ata_read	# ebx=lba
	jc	2f

	##



	##


	clc
2:	pop	ecx
	pop	esi

	pop	ebp
	pop	ebx
	pop	edi
#########################
	pop	ecx
	jc	0f
	mov	esi, edi



	jmp	1b
1:


	mov	ecx, ebp
	mov	esi, ebx

	mov	edi, offset cwd$
	rep	movsb
	xor	al, al
	stosb

0:	ret

# in: cwd$, cmdline_tokens as prepared by tokenize
# out: carry flag = syntax error
# out: cd_cwd$ is new commandline
# out: ecx length of commandline (when CF is clear) (minus trailing /)
# out: esi offset of commandline (cd_cwd$) (when CF is clear)
# destroys: eax ebx ecx edx esi edi
cd_apply$:
	push	dword ptr -1	# alloc state
	# copy cwd
	.data 2
	cd_cwd$: .space 1024
	.text
	mov	esi, offset cwd$
	mov	edi, offset cd_cwd$
	mov	ecx, 1024
	rep	movsb

	# scan for end of string
	mov	edi, offset cd_cwd$
	xor	al, al
	mov	ecx, 1024
	repne scasb
	dec	edi

	mov	ebx, 2
0:	mov	[edi], byte ptr 0
	inc	dword ptr [esp]


	.if 0
		pushcolor 10
		mov	edx, 1024
		sub	edx, ecx
		call	printdec32
		mov	al, ' '
		call	printchar
		mov	edx, edi
		mov	esi, offset cd_cwd$
		sub	edx, esi
		call	printdec32
		call	println
		popcolor
	.endif

#	GET_TOKEN ebx
#	jc	0f

	lea	esi, [cmdline_tokens + 8 * ebx ]
	cmp	[cmdline_tokens_end], esi
	jbe	0f
	inc	ebx

	lodsd	# al = type
	mov	ecx, [esi + 8]
	mov	esi, [esi]
	sub	ecx, esi 
	jbe	0f

	.if 0
		pushcolor 3
		mov	edx, ebx
		call	printdec32
		printchar ':'
		mov	edx, ecx
		call	printdec32
		printchar ' '
		mov	edx, esi
		call	printhex8
		printchar ' '
		call	nprint
		call	newline
		popcolor
	.endif

	# Check whether it is a valid path-element token
	.data
	num_path_tokens$: .long path_token_handler_idx$ - path_tokens$
	path_tokens$: .byte ALPHA, DIGIT, '-', '_', '.', '/'
	path_token_handler_idx$: .byte 0, 0, 0, 0, 1, 2
	# NOTE: there is no symbol relocation so code offsets need
	# to be adjusted by [realsegflat]
	path_token_handlers$: .long cd_a$, cd_dot$, cd_slash$
	.text

	mov	edx, offset num_path_tokens$
	call	get_token_handler
	jnz	cd_syntax_error$
	jmp	edx


cd_syntax_error$:
	PRINTc 4, "Syntax error at token "
	call	nprint
	call	newline
	mov	al, -1
	jmp	9f

cd_a$:	rep	movsb	# append / overwrite
	jmp	0b

cd_dot$:dec	ecx	# use nr of '.' as levels up
	jz	0b
	# scan backward for /
	dec	edi
	std
2:	mov	al, '/'
	dec	edi
	push	ecx
	mov	ecx, edi
	sub	ecx, offset cd_cwd$
	jbe	3f
	repne	scasb
	inc	edi
3:	pop	ecx
	loop	2b
	cld
	jmp	0b

cd_slash$:
	cmp	dword ptr [esp], 0
	jnz	1f
	mov	edi, offset cd_cwd$
1:	stosb
	jmp	0b


0:	cmp	edi, offset cd_cwd$ + 1
	je	0f
	mov	[edi], word ptr '/'
0:	mov	esi, offset cd_cwd$	# return offset

	.if 0
	call	println
	.endif

	mov	ecx, edi
	sub	ecx, esi

	xor	al, al

9:	add	esp, 4
	shl	al, 1	# al -1 on error, sets carry
	ret	


.data 2
cwd$:	.space 1024
tmp_buf$: .space 2 * 512
.text

ls$:	mov	ebx, [fat_root_lba$]
	or	ebx, ebx
	jnz	lsdir$
	call	_tmp_init$
	mov	ebx, [fat_root_lba$]
lsdir$:	mov	edi, offset tmp_buf$
	mov	ecx, 1
	mov	al, [tmp_drv$]
	call	ata_read
	jc	read_error$

	mov	esi, offset tmp_buf$
0:	
	cmp	byte ptr [esi], 0
	jz	0f
	PRINT	"Name: "
	mov	ecx, 11
	call	nprint

	PRINT	" Attr "
	mov	dl, [esi + FAT_DIR_ATTRIB]
	call	printhex2
	.data
		9: .ascii "RHSVDA78"
	.text
	mov	ebx, offset 9b
	mov	ecx, 8
1:	mov	al, ' '
	shr	dl, 1
	jnc	2f
	mov	al, [ebx]
2:	call	printchar
	inc	ebx
	loop	1b
	

	PRINT	" Cluster "
	mov	dx, [esi + FAT_DIR_CLUSTER]
	call	printhex4

	PRINT	" Size: "
	mov	edx, [esi + FAT_DIR_SIZE]
	call	printdec32
	call	newline

	add	esi, 32
	cmp	esi, 512 + offset tmp_buf$	# overflow check
	jb	0b
0:
mov	esi, -1
mov	edi, esi
mov	ebx, esi
mov	edx, esi
	ret


#######################
write_boo:
	mov	al, TYPE_ATA
	call	ata_find_first_drive
	jns	1f

 	PRINTLNc 10, "No ATA drive found"
	ret
1:
	PRINTc	10, "Writing bootsector to ATA drive: "
	mov	dl, al
	call	printhex2
	call	newline

# Read data:

	mov	[tmp_drv$], al

	mov	edi, offset tmp_buf$
	mov	ecx, 2
	mov	ebx, 0
	call	ata_read
	jnc	0f
	PRINTLNc 4, "ATA read error"
	ret
0:	PRINTLN "ATA read OKAY"
	
	mov	esi, offset tmp_buf$ + 512
	mov	ecx, 10
0:	lodsb
	call	printchar
	mov	dl, al
	mov	al, ' '
	call	printchar
	call	printhex2
	mov	al, ' '
	call	printchar
	loop	0b

	call	newline

####
.if 0
	.data 2
	tmp_buf2$: .asciz "Hello World! First ATA sector written!"
	.space 512 - (.-tmp_buf2$)
	.asciz "second sector"
	.space 512
	.text
	PRINTln "ATA WRITE"
	mov	al, [tmp_drv$]
	mov	dl, al
	call	printhex2
	call	newline

	mov	esi, offset tmp_buf2$
	mov	ecx, 2
	mov	ebx, 0
	call	ata_write
.endif
	ret


############################

read_error$:
	PRINTLNc 10, "ATA Read ERROR"
	stc
	ret






	.if 0 # works...
		movzx	edx, word ptr [esi + FAT_DIR_CLUSTER]
		push	edx
		movzx	edx, byte ptr [esi + FAT_DIR_ATTRIB]
		push	edx
		push	dword ptr 2
		push	esi
		push	dword ptr 11
		PUSH_TXT "Name: %.*s  Attr: %*x  Cluster: %x\n"
		call	printf
		add	esp, 4 * 6
	.endif

			.if 0 # doesnt seem to work
			push	esi
			push dword ptr [cmdline_tokens_end]
			push	dword ptr offset cmdline_tokens
			PUSH_TXT "Token offset start: %x  end %x token \nr calc: %x\n"
			call	printf
			add	esp, 3 * 4
			.endif


			.if 0 # works

			mov	al, '<'
			pushcolor 3
			mov	edx, offset cmdline_tokens
			call	printhex8
			call	printchar
			mov	edx, esi
			call	printhex8
			call	printchar
			mov	edx, [cmdline_tokens_end]
			call	printhex8
			popcolor

			.endif