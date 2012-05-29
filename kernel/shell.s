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

cmdline_prompt_label_length: .long 0 # "the_prefix> ".length

############################################################################
.struct 0
shell_command_code: .long 0
shell_command_string: .long 0
shell_command_length: .word 0
SHELL_COMMAND_STRUCT_SIZE: 
.text

.macro SHELL_COMMAND string, addr
	.data 1
		9: .asciz "\string"
		8:
	.data
		.long \addr
		.long 9b
		.word 8b - 9b
	.text
.endm

.data
### Shell Command list
.align 4
SHELL_COMMANDS:

SHELL_COMMAND "ls",		cmd_ls$
SHELL_COMMAND "cluster",	cmd_cluster$
SHELL_COMMAND "cd",		cmd_cd$
SHELL_COMMAND "cls",		cls
SHELL_COMMAND "pwd",		cmd_pwd$
SHELL_COMMAND "disks",		disks_print$
SHELL_COMMAND "fdisk",		cmd_fdisk$
SHELL_COMMAND "partinfo",	cmd_partinfo$
SHELL_COMMAND "mount",		cmd_mount$
SHELL_COMMAND "umount",		cmd_umount$
SHELL_COMMAND "mtest",		malloc_test$
SHELL_COMMAND "mem",		print_handles$
SHELL_COMMAND "quit",		cmd_quit$
SHELL_COMMAND "exit",		cmd_quit$
SHELL_COMMAND "help",		cmd_help$
SHELL_COMMAND "hist",		cmdline_history_print
SHELL_COMMAND "lspci",		pci_list_devices
SHELL_COMMAND "strlen",		cmd_strlen$
.data
.space SHELL_COMMAND_STRUCT_SIZE
### End of Shell Command list


.text	
.code32

shell:	push	ds
	pop	es
	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

	call	cmdline_history_new

	#

	mov	[cwd$], word ptr '/'
	mov	[insertmode], byte ptr 1

start$:
	print "!"
	PUSH_SCREENPOS
	sub	dword ptr [esp], 2
	POP_SCREENPOS

	mov	dword ptr [cursorpos], 0
	mov	dword ptr [cmdlinelen], 0

start0$:
	.if 0
	#PUSH_SCREENPOS
	mov	esi, offset cwd$
	call	print
	printcharc 15, ':'

	mov	edx, [cmdline_history_index]
	call	printdec32
	printc 15, "> "
	#POP_SCREENPOS
	.endif



start1$:
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

	cmp	ax, K_DELETE
	jz	del$

	cmp	ax, K_LEFT
	jz	key_left$
	cmp	ax, K_RIGHT
	jz	key_right$
	cmp	ax, K_UP
	jz	key_up$
	cmp	ax, K_DOWN
	jz	key_down$

	cmp	ax, K_INSERT
	jz	toggleinsert$

	cmp	al, 127
	jae	start1$	# ignore
	cmp	al, 32
	jb	start1$	# ignore
	
1:	#cmp	byte ptr [insertmode], 0
	#jz	insert$
	# overwrite
#insert$:
	# overwrite
	cmp	[cmdlinelen], dword ptr 1024-1	# check insert
	# beep
	jb	1f	
	# beep
	jmp	start1$
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

	jmp	start1$

cursor_toggle$:
	PRINT_START
	mov	ecx, [cursorpos]
	add	ecx, [cmdline_prompt_label_length]
	xor	es:[edi + ecx * 2 + 1], byte ptr 0xff
	PRINT_END
	ret
	
enter$:	
	call	cursor_toggle$
	call	newline

	call	cmdline_history_add
	jc	1f
	mov	eax, [cmdline_history]
	mov	edx, [eax + buf_index]
1:	mov	[cmdline_history_index], edx

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

	# Find the command.

	mov	edi, [cmdline_args + 0]
	or	edi, edi
	jz	0f

	mov	ebx, offset SHELL_COMMANDS
0:	cmp	[ebx + shell_command_code], dword ptr 0
	jz	0f

	mov	esi, [ebx + shell_command_string]
	or	esi, esi
	jz	0f
	movzx	ecx, word ptr [ebx + shell_command_length]
	push	edi
	repz	cmpsb
	pop	edi
	jz	1f

	add	ebx, SHELL_COMMAND_STRUCT_SIZE
	jmp	0b

0:	PRINTLNc 4, "Unknown command"
	jmp	start$

	# call the command

1:	mov	edx, [ebx + shell_command_code]
	mov	esi, offset cmdline_args

	add	edx, [realsegflat]
	call	edx

	jmp	start$
	
#######
###################################################################

cmd_quit$:
	printlnc 12, "Terminating shell."
	add	esp, 4	# skip returning to the shell loop and return from it.
	ret


cmd_pwd$:
	mov	esi, offset cwd$
	call	println
	ret

cmd_help$:
	mov	ebx, offset SHELL_COMMANDS
0:	mov	esi, [ebx + shell_command_string]
	or	esi, esi
	jz	0f
	cmp	[ebx + shell_command_code], dword ptr 0
	jz	0f
	call	print
	mov	al, ' '
	call	printchar
	add	ebx, SHELL_COMMAND_STRUCT_SIZE
	jmp	0b
0:	call	newline
	ret

## Keyboard handler for the shell

del$:	
	mov	ecx, [cmdlinelen]
	sub	ecx, edi
	add	ecx, offset cmdline
	jle	start1$
	mov	esi, edi
	inc	esi
	rep	movsb
	dec	dword ptr [cmdlinelen]
	jmp	start1$

bs$:	
	cmp	edi, offset cmdline 
	jbe	start1$
	cmp	edi, [cmdlinelen]
	jz	1f
	mov	esi, edi
	dec	edi
	mov	ecx, 1024 + offset cmdline
	sub	ecx, esi
	jz	1f
	rep	movsb

1:	dec	dword ptr [cursorpos]
	jns	1f
	printc 4, "Error: cursorpos < 0"
1:
	dec	dword ptr [cmdlinelen]
	jns	1f
	PRINTlnc 4, "Error: cmdlinelen < 0"
1:	jmp	start1$

key_left$:
	dec	dword ptr [cursorpos]
	jns	start1$
	inc	dword ptr [cursorpos]
	jmp	start1$

key_right$:
	mov	eax, [cursorpos]
	cmp	eax, [cmdlinelen]
	jae	start1$
	inc	dword ptr [cursorpos]
	jmp	start1$

key_up$:
	mov	eax, [cmdline_history]
	mov	ebx, [cmdline_history_index]
	sub	ebx, 4
	jns	0f
#	printlnc 10, "hist first"
#	jmp	start$
	xor	ebx, ebx
	jmp	0f

key_down$:
	mov	eax, [cmdline_history]
	mov	ebx, [cmdline_history_index]
	add	ebx, 4
	cmp	ebx, [eax + buf_index]
	jb	0f
#	printlnc 10, "hist last"
#	jmp	start$
	mov	ebx, [eax + buf_index]
	sub	ebx, 4
	js	start0$	# empty

0:	mov	[cmdline_history_index], ebx

#mov	edx, ebx
#call	printhex8
#printchar ' '
#mov	esi, [eax+ebx]
#call	println

	call	cursor_toggle$

	call	cmdline_clear$

	# copy history entry to commandline buffer
.if 1
	mov	edi, offset cmdline
	mov	esi, [eax+ebx]
0:	lodsb
	stosb
	or	al, al
	jnz	0b
	sub	edi, offset cmdline
	dec	edi
	mov	[cursorpos], edi
	mov	[cmdlinelen], edi

.endif
	jmp	start0$


clear$:	
	call	cmdline_clear$
	jmp	start1$

cmdline_clear$:
	push	eax
	push	ecx
	mov	ax,(7<<8)| ' '
	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	add	ecx, [cmdline_prompt_label_length]
	jecxz	2f	# used to jump to start$
	PRINT_START
	push	edi
	inc	ecx
1:	stosw	#call	printchar
	loop	1b
	pop	edi
	PRINT_END
2:	pop	ecx
	pop	eax
	ret



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

	#############
	mov	ebx, edi

	mov	ah, 7
	mov	esi, offset cwd$
	call	__print

	mov	ah, 15
	mov	al, ':'
	stosw

	mov	ah, 7
	mov	edx, [cmdline_history_index]
	shr	edx, 2
	call	__printdec32
	stosw
	mov	edx, [cursorpos]
	call	__printdec32

	mov	ah, 15
	mov	al, '>'
	stosw
	mov	al, ' '
	stosw

	mov	ah, 7

	sub	ebx, edi
	neg	ebx
	shr	ebx, 1
	mov	[cmdline_prompt_label_length], ebx

	#############
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
	xor	es:[ebx + 1], byte ptr 0xff

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
cmd_cd$:	
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
	.data
	tmp_drv$: .long 0
	.text
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

cmd_ls$:
	xor	eax, eax
	jmp	ls$

cmd_cluster$:
	mov	eax, 2
	jmp	ls$


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




##############################################################################
# Commandline History
#
# This is a 'static class', a singleton, as it uses a hardcoded memory
# address to store the pointers to the two objects it uses: a stringbuffer,
# and an array.

.data
CMDLINE_HISTORY_MAX_ITEMS = 16
cmdline_history: .long 0	# list/array/linked list.

cmdline_history_index: .long 0	# the current array item offset (up/down keys)
.text

# static constructor
cmdline_history_new:	
	mov	eax, CMDLINE_HISTORY_MAX_ITEMS * 4
	call	buf_new
	mov	[cmdline_history], eax
	ret

# static destructor
cmdline_history_delete:
	mov	eax, [cmdline_history]
	call	buf_free
	ret


cmdline_history_add:
	# check whether this history item is the same as the previous
	mov	ecx, [cmdlinelen]
	jecxz	2f
	mov	eax, [cmdline_history]
	mov	esi, [eax + buf_index]
	sub	esi, 4
	js	1f	# hist empty

	# check whether this history item already exists
	xor	edx, edx
0:	cmp	edx, [eax + buf_index]
	jae	1f
	mov	esi, [eax + edx]
	add	edx, 4
	mov	edi, offset cmdline
	mov	ecx, [cmdlinelen]
	repz	cmpsb
	jnz	0b
2:	stc
	ret
1:	################################

	# append a pointer to the appended data to the array

	mov	edi, [cmdline_history]
	mov	esi, [edi + buf_index]
	cmp	esi, [edi + buf_capacity]
	jae	0f	# if below, assume 4 bytes available

	add	[edi + buf_index], dword ptr 4
1:	mov	eax, [cmdlinelen]
	mov	[cmdline + eax], byte ptr 0
	inc	eax
	mov	ecx, eax
	call	malloc
	mov	[edi + esi], eax

	mov	edi, eax
	mov	esi, offset cmdline
	rep	movsb
	clc
	ret

0:	###################
	# buffer is full. TODO: circular buffer.
	# move the data, create an empty spot at the end:
	
	# delete the first item in the list
	mov	eax, [edi]
	call	mfree
	mov	eax, edi

	mov	esi, edi
	add	esi, 4
	mov	ecx, [edi + buf_capacity]
	sub	ecx, 4
	shr	ecx, 2
	rep	movsd

	# eax = &buf[0]
	mov	edi, eax
	mov	esi, [edi + buf_index]
	sub	esi, 4

	jmp	1b

#######################################################################

cmdline_history_print:
	mov	eax, [cmdline_history]
	mov	ecx, [eax + buf_index]
	shr	ecx, 2
	jz	1f
	xor	edx, edx
0:	call	printdec32
	print ": "
	mov	esi, [eax + edx * 4]
	call	println
	inc	edx
	loop	0b
1:	ret

##############################################################################

cmd_strlen$:
	mov	eax, [esi+4]
	call	strlen
	mov	edx, eax
	call	printdec32
	call	newline
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
