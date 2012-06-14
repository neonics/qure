.intel_syntax noprefix

CMDLINE_DEBUG = 1	# 1: include cmdline_print_args$;
			# 2: 

MAX_CMDLINE_LEN = 1024

.data
insertmode: .byte 1
.data 2
cursorpos: .long 0

cmdlinelen: .long 0
cmdline: .space MAX_CMDLINE_LEN
cmdline_tokens_end: .long 0
cmdline_tokens: .space MAX_CMDLINE_LEN * 8 / 2	 # assume 2-char min token avg

MAX_CMDLINE_ARGS = 256
cmdline_argdata: .space MAX_CMDLINE_LEN + MAX_CMDLINE_ARGS
cmdline_args:	.space MAX_CMDLINE_ARGS * 4

cmdline_prompt_label_length: .long 0 # "the_prefix> ".length

MAX_PATH_LEN = 1024

cwd$:	.space MAX_PATH_LEN
cd_cwd$:	.space MAX_PATH_LEN
cwd_handle$: .long 0


############################################################################
.struct 0
shell_command_code: .long 0
shell_command_string: .long 0
shell_command_length: .word 0
SHELL_COMMAND_STRUCT_SIZE: 
.data

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

### Shell Command list
.align 4
SHELL_COMMANDS:

SHELL_COMMAND "ls",		cmd_ls$
SHELL_COMMAND "cluster",	cmd_cluster$
SHELL_COMMAND "cd",		cmd_cd$
SHELL_COMMAND "cls",		cls
SHELL_COMMAND "pwd",		cmd_pwd$
SHELL_COMMAND "disks",		cmd_disks_print$
SHELL_COMMAND "fdisk",		cmd_fdisk$
SHELL_COMMAND "partinfo",	cmd_partinfo$
SHELL_COMMAND "mount",		cmd_mount$
SHELL_COMMAND "umount",		cmd_umount$
SHELL_COMMAND "mtest",		malloc_test$
SHELL_COMMAND "mem",		cmd_mem$
SHELL_COMMAND "quit",		cmd_quit$
SHELL_COMMAND "exit",		cmd_quit$
SHELL_COMMAND "help",		cmd_help$
SHELL_COMMAND "hist",		cmdline_history_print
SHELL_COMMAND "lspci",		pci_list_devices
SHELL_COMMAND "strlen",		cmd_strlen$
SHELL_COMMAND "echo",		cmd_echo$
SHELL_COMMAND "listdrives",	ata_list_drives
SHELL_COMMAND "fs_tree",	fs_printtree
SHELL_COMMAND "hs",		cmd_human_readable_size$
SHELL_COMMAND "cat",		cmd_cat$
SHELL_COMMAND "lsof",		fs_list_openfiles
#SHELL_COMMAND "regexp",		regexp_parse
.data
.space SHELL_COMMAND_STRUCT_SIZE
### End of Shell Command list
############################################################################

.text	
.code32

shell:	push	ds
	pop	es
	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

	call	cmdline_history_new

	#

	mov	[cwd$], word ptr '/'
	mov	[insertmode], byte ptr 1

	.data
	9: .asciz "mount"
	8: .asciz "hdb0"
	7: .asciz "/b"
	6: .long 9b, 8b, 7b, 0
	.text

	mov	esi, offset 6b
	call	cmd_mount$

	mov	eax, offset cwd$
	call	fs_opendir
	mov	[cwd_handle$], eax

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

	mov	edx, [cmdline_history_current]
	call	printdec32
	printc 15, "> "
	#POP_SCREENPOS
	.endif



start1$:
	call	cmdline_print$

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
	jz	key_escape$

	cmp	ax, K_ENTER
	jz	key_enter$

	cmp	ax, K_BACKSPACE
	jz	key_backspace$

	cmp	ax, K_DELETE
	jz	key_delete$

	cmp	ax, K_LEFT
	jz	key_left$
	cmp	ax, K_RIGHT
	jz	key_right$
	cmp	ax, K_UP
	jz	key_up$
	cmp	ax, K_DOWN
	jz	key_down$

	cmp	ax, K_INSERT
	jz	key_insert$

	cmp	al, 127
	jae	start1$	# ignore
	cmp	al, 32
	jb	start1$	# ignore
	
1:	#cmp	byte ptr [insertmode], 0
	#jz	insert$
	# overwrite
#insert$:
	# overwrite
	cmp	[cmdlinelen], dword ptr MAX_CMDLINE_LEN-1	# check insert
	# beep
	jb	1f	
	# beep
	jmp	start1$
1:	
	cmp	byte ptr [insertmode], 0
	jz	1f
	# insert
	mov	esi, [cmdlinelen]
	mov	ecx, esi
	sub	ecx, [cursorpos]
	add	esi, offset cmdline
	mov	edi, esi
	dec	esi
	std
	rep	movsb
	cld
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

##########################################################################
## Keyboard handler for the shell
	
# Shell and History key handler
key_enter$:	
	call	cursor_toggle$
	call	newline

	call	cmdline_history_add
	jc	1f
	mov	eax, [cmdline_history]
	mov	edx, [eax + buf_index]
1:	mov	[cmdline_history_current], edx

	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$

	call	cmdline_execute$
	
	jmp	start$
	
############################################
## Line Editor key handlers

key_delete$:	
	mov	ecx, [cmdlinelen]
	sub	ecx, edi
	add	ecx, offset cmdline
	jle	start1$
	mov	esi, edi
	inc	esi
	rep	movsb
	dec	dword ptr [cmdlinelen]
	jmp	start1$

key_backspace$:	
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

key_insert$:
	xor	byte ptr [insertmode], 1
	jmp	start$

key_escape$:
	call	cmdline_clear$
	jmp	start1$

#########################################
## History key handlers

key_up$:
	mov	eax, [cmdline_history]
	mov	ebx, [cmdline_history_current]
	sub	ebx, 4
	jns	0f
	xor	ebx, ebx
	jmp	0f

key_down$:
	mov	eax, [cmdline_history]
	mov	ebx, [cmdline_history_current]
	add	ebx, 4
	cmp	ebx, [eax + buf_index]
	jb	0f
	mov	ebx, [eax + buf_index]
	sub	ebx, 4
	js	start0$	# empty

0:	mov	[cmdline_history_current], ebx

	call	cursor_toggle$

	call	cmdline_clear$

	# copy history entry to commandline buffer

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

	jmp	start0$


##########################################################################
# commandline utility functions

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

cmdline_print$:
	push	esi
	push	ecx
	push	ebx

	PRINT_START
	push	edi

	# print the prompt

	mov	ebx, edi

	mov	ah, 7
	mov	esi, offset cwd$
	call	__print

	mov	ah, 15
	mov	al, ':'
	stosw

	mov	ah, 7
	mov	edx, [cmdline_history_current]
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

	# print the line editor contents

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

.if CMDLINE_DEBUG

cmdline_print_args$:
	pushcolor 8
	print	"ARGS: "
	push	esi
	push	edx
0:	mov	edx, [esi]
	or	edx, edx
	jz	0f
	printcharc 10, '<'
	push	esi
	mov	esi, edx
	color 7
	call	print
	printcharc 10, '>'
	call	printspace
	pop	esi
	add	esi, 4
	jmp	0b
0:
	call	newline
	pop	edx
	pop	esi
	popcolor
	ret

.endif


###################################################
## Commandline execution

# parses the commandline and executes the command(s)
cmdline_execute$:

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
	.if DEBUG_TOKENS && CMDLINE_DEBUG
		call	cmdline_print_args$
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

	ret


##############################################################################
# Commandline History
#
# uses buf_*
#
# singleton

.data
CMDLINE_HISTORY_MAX_ITEMS = 16
CMDLINE_HISTORY_SHARE = 1
cmdline_history: .long 0	# list/array/linked list.

cmdline_history_current: .long 0 # the current array item offset (up/down keys)
.text

# static constructor
cmdline_history_new:	
	mov	eax, [cmdline_history]
	or	eax, eax
	.if CMDLINE_HISTORY_SHARE
	jnz	1f
	.else
	call	buf_free
	.endif
	mov	eax, CMDLINE_HISTORY_MAX_ITEMS * 4
	call	buf_new
	mov	[cmdline_history], eax
1:	ret

# static destructor
cmdline_history_delete:
	xor	eax, eax
	xchg	eax, [cmdline_history]
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


#############################################################################
## Public shell functions

## Commandline Arguments:
#
# The commandline calls the 'main' function with esi pointing to a zero
# terminated array of string pointers, the first of which is the name
# under which the command was called.
# C: byte * args[] = { "cmd", ["arg1", ["arg2", [...] ] ], 0 };

# in: esi = array address of current argument pointer
# out: eax = pointer to cur
getopt:
	mov	eax, [esi]
	cmp	byte ptr [eax], '-'
	stc
	jnz	0f
	add	esi, 4
	clc
0:	ret


#############################################################################
## Builtin Shell commands

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

cmd_strlen$:
	mov	eax, [esi+4]
	call	strlen
	mov	edx, eax
	call	printdec32
	call	newline
	ret


cmd_human_readable_size$:


.if 1
	add	esi, 4
	mov	eax, [esi]
	or	eax, eax
	jz	0f

	call	htoid	# out: edx:eax
	jc	1f
.else
	mov	edx, 1
	mov	eax, 0x80000000
.endif
	call	printhex8
	call	printspace
	push	edx
	mov	edx, eax
	call	printhex8
	call	printspace
	pop	edx

	call	print_fixedpoint_32_32


	.if 0
	call	atoi
	mov	edx, eax
	call	printdec32
	print ": "
	xor	edx, edx
	call	print_size_kb
	.endif
	call	newline
0:	ret
1:	printlnc 4, "syntax error"
	stc
	jmp	0b

cmd_echo$:
	xor	ah, ah
	mov	ebx, esi
0:	add	ebx, 4
	mov	esi, [ebx]
	or	esi, esi
	jz	2f

	cmp	byte ptr [esi], '-'
	jz	1f

	call	print
	mov	al, ' '
	call	printchar
	jmp	0b
	ret
	###
1:	
	lodsw
	cmp	ax, ('n'<<8 ) | '-'
	jnz	3f
	lodsb
	or	al, al
	jnz	3f
	inc	ah

	jmp	0b

########
3:	# other option
	printlnc 12, "Unknown option: "
	mov	esi, [ebx]
	call	println
	jmp	0f
########

1:	dec	esi
	call	print
	mov	al, ' '
	call	printchar

	jmp	1b
	###

2:	or	ah, ah
	jnz	0f
	call	newline
0:	ret



######################################################

_tmp_init$:
	.data
	8: .asciz "hdb0"
	9: .long 0, 8b
	tmp_drv$: .long 1
	.text
	.text
	mov	esi, offset 9b
	call	cmd_partinfo$
	ret

######################################

cmd_cd$:	
	push	dword ptr 0
	mov	ebp, esp

	# check parameters
	cmp	[esi + 8], dword ptr 0
	jz	0f
	printc 13, "parsing options: "

	mov	eax, [esi + 4]
	push	esi
	mov	esi, eax
	call	print
	pop	esi

	cmp	word ptr [eax], ('d'<<8)|'-'
	jnz	5f
	cmp	byte ptr [eax + 2], 0
	jnz	5f

	inc	dword ptr [ebp]

	add	esi, 4

	printc 13, " arg1: "
	push	esi
	mov	esi, [esi + 4]
	call	println
	pop	esi

0:	mov	esi, [esi + 4]
	or	esi, esi
	jnz	0f

	# no path given, change to home directory
	.data
	9: .asciz "/"
	.text
	mov	esi, offset 9b
0:
	# new code
	cmp	byte ptr [ebp], 0
	jz	1f
	print "chdir "
	call	println
1:

#	call	cd_apply$
#	print " -> "
#	call	println

	push	esi
	mov	esi, offset cwd$
	mov	edi, offset cd_cwd$
	mov	ecx, MAX_PATH_LEN
	rep	movsb
	pop	esi

	mov	edi, offset cd_cwd$

	call	fs_update_path
##############################################################################
		cmp	byte ptr [esp], 0
		jz	1f
		printc 10, "chdir "
		mov	esi, offset cd_cwd$
		call	println
	1:

	mov	eax, [cwd_handle$]
	call	fs_close

	mov	eax, offset cd_cwd$
	call	fs_opendir
	jc	6f
	mov	[cwd_handle$], eax

	call	fs_handle_printinfo

	# copy path:
	mov	ecx, edi
	mov	edi, offset cwd$
	mov	esi, offset cd_cwd$
	sub	ecx, edi
	rep	movsb

6:	pop	eax
	ret

5:	printlnc 10, "usage: cd [<directory>]"

	pop	eax
	ret


###############################################################################
###############################################################################
###############################################################################

.data 2
tmp_buf$: .space 2 * 512
.text

cmd_ls$:
	mov	eax, offset cwd$
	printc	11, "ls "
	mov	esi, eax
	call	println
DEBUG_REGSTORE
	call	fs_opendir
DEBUG_REGDIFF
	ret



################################
cmd_ls_old$:
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


############################

read_error$:
	PRINTLNc 10, "ATA Read ERROR"
	stc
	ret


##############################################################################

cmd_cat$:
	

	ret

#####################################

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
