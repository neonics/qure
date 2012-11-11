.intel_syntax noprefix

CMDLINE_DEBUG = 1	# 1: include cmdline_print_args$;
			# 2: 
SHELL_DEBUG_FS = 0

MAX_CMDLINE_LEN = 1024

MAX_PATH_LEN = 1024

.struct 0
cmdline_buf:		.space MAX_CMDLINE_LEN
cmdline_len:		.long 0
cmdline_cursorpos:	.long 0
cmdline_insertmode:	.byte 0
cmdline_prompt_len:	.long 0 # "the_prefix> ".length
cmdline_cwd:		.space MAX_PATH_LEN
cmdline_cwd_handle:	.long 0
cmdline_cd_cwd:	.space MAX_PATH_LEN

cmdline_history:	.long 0	# list/array/linked list.
cmdline_history_current:.long 0 # the current array item offset (up/down keys)

MAX_CMDLINE_ARGS = 256
cmdline_argdata:	.space MAX_CMDLINE_LEN + MAX_CMDLINE_ARGS
cmdline_args:		.space MAX_CMDLINE_ARGS * 4

cmdline_tokens_end:	.long 0
cmdline_tokens:	.space MAX_CMDLINE_LEN * 8 / 2	 # assume 2-char min token avg

CMDLINE_STRUCT_SIZE = .

############################################################################
.struct 0
shell_command_code: .long 0
shell_command_string: .long 0
shell_command_length: .word 0
SHELL_COMMAND_STRUCT_SIZE = .
.data SECTION_DATA_SHELL_CMDS

.macro SHELL_COMMAND string, addr
	.data SECTION_DATA_STRINGS
		9: .asciz "\string"
		8:
	.data SECTION_DATA_SHELL_CMDS
		.long \addr
		.long 9b
		.word 8b - 9b
	.text32
.endm

############################################################################
### Shell Command list
.align 4
SHELL_COMMANDS:
SHELL_COMMAND "cls",		cls
# filesystem
SHELL_COMMAND "ls",		cmd_ls$
SHELL_COMMAND "cd",		cmd_cd$
SHELL_COMMAND "pwd",		cmd_pwd$
SHELL_COMMAND "disks",		cmd_disks_print$
SHELL_COMMAND "listdrives",	ata_list_drives
SHELL_COMMAND "fdisk",		cmd_fdisk
SHELL_COMMAND "mkfs",		cmd_sfs_format
SHELL_COMMAND "partinfo",	cmd_partinfo$
SHELL_COMMAND "mount",		cmd_mount$
SHELL_COMMAND "umount",		cmd_umount$
SHELL_COMMAND "listfs"		fs_list_filesystems
SHELL_COMMAND "lsof",		fs_list_openfiles
SHELL_COMMAND "fat_handles"	cmd_fat_handles
# memory
SHELL_COMMAND "mtest",		malloc_test$
SHELL_COMMAND "mem",		cmd_mem$
# shell
SHELL_COMMAND "quit",		cmd_quit$
SHELL_COMMAND "exit",		cmd_quit$
SHELL_COMMAND "help",		cmd_help$
SHELL_COMMAND "hist",		cmdline_history_print

SHELL_COMMAND "set"		cmd_set
SHELL_COMMAND "unset"		cmd_unset

SHELL_COMMAND "strlen",		cmd_strlen$
SHELL_COMMAND "echo",		cmd_echo$
SHELL_COMMAND "cat",		cmd_cat$
# hardware
SHELL_COMMAND "dev"		cmd_dev
SHELL_COMMAND "lspci",		pci_list_devices
SHELL_COMMAND "ints",		cmd_int_count
# network
# nonstandard
SHELL_COMMAND "nics", 		cmd_nic_list
SHELL_COMMAND "nicdrivers",	cmd_list_nic_drivers
SHELL_COMMAND "netdump"		cmd_netdump
SHELL_COMMAND "zconf"		nic_zeroconf
# standard
SHELL_COMMAND "ifconfig"	cmd_ifconfig
SHELL_COMMAND "ifup"		cmd_ifup
SHELL_COMMAND "ifdown"		cmd_ifdown
SHELL_COMMAND "route"		cmd_route
SHELL_COMMAND "dhcp"		cmd_dhcp
SHELL_COMMAND "ping"		cmd_ping
SHELL_COMMAND "arp"		cmd_arp
SHELL_COMMAND "icmp"		net_icmp_list
SHELL_COMMAND "host"		cmd_host
SHELL_COMMAND "netstat"		cmd_netstat
# utils
SHELL_COMMAND "hs",		cmd_human_readable_size$
#SHELL_COMMAND "regexp",		regexp_parse
SHELL_COMMAND "obj"		pci_list_obj_counters

SHELL_COMMAND "gdt"		cmd_print_gdt
SHELL_COMMAND "p"		cmd_ping_gateway
SHELL_COMMAND "gfx"		cmd_gfx

SHELL_COMMAND "gpf"		cmd_gpf
SHELL_COMMAND "colors"		cmd_colors

SHELL_COMMAND "debug"		cmd_debug
SHELL_COMMAND "breakpoint"	cmd_breakpoint
SHELL_COMMAND "pic"		cmd_pic

SHELL_COMMAND "vmcheck"		cmd_vmcheck
SHELL_COMMAND "ramdisk"		cmd_ramdisk

SHELL_COMMAND "exe"		cmd_exe
SHELL_COMMAND "init"		cmd_init
SHELL_COMMAND "fork"		cmd_fork
SHELL_COMMAND "traceroute"	cmd_traceroute
SHELL_COMMAND "top"		cmd_top
SHELL_COMMAND "ps"		cmd_tasks
SHELL_COMMAND "kill"		cmd_kill
SHELL_COMMAND "shell"		cmd_shell
.if VIRTUAL_CONSOLES
SHELL_COMMAND "consoles"	cmd_consoles
.endif
# Debugger:
SHELL_COMMAND "sline",		cmd_sline
SHELL_COMMAND "sym",		cmd_sym
.data SECTION_DATA_SHELL_CMDS
.space SHELL_COMMAND_STRUCT_SIZE
### End of Shell Command list
############################################################################

.text32	
.code32

########################################################
# do not call: call shell.
shell_init$:
	mov	eax, CMDLINE_STRUCT_SIZE
	call	mallocz
	jc	9f
	mov	ebx, eax
	mov	[ebx + cmdline_insertmode], byte ptr 1
	mov	[ebx + cmdline_cwd], word ptr '/'

	call	cmdline_history_new
	jc	9f

	ret

9:	printlnc 4, "shell: out of memory"
	add	esp, 4
	ret

########################################################

shell:	push	ds
	pop	es

	call	shell_init$	# out: ebx

	push	ebp
	push	ebx
	mov	ebp, esp

	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

	#

	lea	eax, [ebx + cmdline_cwd]
	call	fs_opendir
	mov	[ebx + cmdline_cwd_handle], eax

start$:
	call	newline_if

	print "!"
	PUSH_SCREENPOS
	sub	dword ptr [esp], 2
	POP_SCREENPOS

	mov	ebx, [ebp]

	mov	dword ptr [ebx + cmdline_cursorpos], 0
	mov	dword ptr [ebx + cmdline_len], 0

start1$:
	call	cmdline_print$

	mov	ebx, [ebp] # shell_instance

	lea	edi, [ebx + cmdline_buf]
	add	edi, [ebx + cmdline_cursorpos]

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

	cmp	ax, K_PGUP
	jz	key_pgup
	cmp	ax, K_PGDN
	jz	key_pgdown

	cmp	ax, K_INSERT
	jz	key_insert$

	cmp	al, 127
	jae	start1$	# ignore
	cmp	al, 32
	jb	start1$	# ignore

	test	eax, K_KEY_CONTROL | K_KEY_ALT
	jnz	start1$	# ignore control/alt + common keys.

	# inject character into commandline:

	# overwrite
	cmp	[ebx + cmdline_len], dword ptr MAX_CMDLINE_LEN-1 # check insert
	# beep
	jb	1f	
	# beep
	jmp	start1$
1:	
	cmp	byte ptr [ebx + cmdline_insertmode], 0
	jz	1f
	# insert
	mov	esi, [ebx + cmdline_len]
	mov	ecx, esi
	sub	ecx, [ebx + cmdline_cursorpos]
	lea	edx, [ebx + cmdline_buf]
	add	esi, edx
	mov	edi, esi
	dec	esi
	std
	rep	movsb
	cld
1:	# overwrite
	stosb
	inc	dword ptr [ebx + cmdline_cursorpos]
	inc	dword ptr [ebx + cmdline_len]

	jmp	start1$


# in: ebx = shell_instance
cursor_toggle$:
	PUSH_SCREENPOS	# flush: save pos; updated to trigger flush
	PRINT_START
	mov	ecx, [ebx + cmdline_cursorpos]
	add	ecx, [ebx + cmdline_prompt_len]
	mov	al, [ebx + cmdline_insertmode]
	xor	al, 1
	shl	al, 4
	not	al
	xor	es:[edi + ecx * 2 + 1], al # byte ptr 0xff
	lea	edi, [edi + ecx * 2 + 2] # flush: update pos for flush if buf
	PRINT_END
	POP_SCREENPOS	# flush: restore pos
	ret

##########################################################################
## Keyboard handler for the shell
#
# in: ebx = cmdline / shell instance
	
# Shell and History key handler
key_enter$:	
	call	cursor_toggle$
#		0:MUTEX_LOCK SCREEN 0b
		PUSH_SCREENPOS
		mov	eax, [ebx + cmdline_prompt_len]
		add	eax, [ebx + cmdline_len]
		add	eax, eax
		add	[esp], eax
		POP_SCREENPOS
#		MUTEX_UNLOCK SCREEN
	call	newline

	call	cmdline_history_add
	mov	eax, [ebx + cmdline_history]
	mov	edx, [eax + buf_index]
	mov	[ebx + cmdline_history_current], edx

	xor	ecx, ecx
	mov	[ebx + cmdline_cursorpos], ecx
	xchg	ecx, [ebx + cmdline_len]
	or	ecx, ecx
	jz	start$

	lea	esi, [ebx + cmdline_buf]
	call	cmdline_execute$
	
	jmp	start$
	
############################################
## Line Editor key handlers

# in: edi = cmdline + cursorpos
key_delete$:
	mov	edi, [ebx + cmdline_cursorpos]
	mov	ecx, [ebx + cmdline_len]
	sub	ecx, edi
	jle	start1$
	lea	edx, [ebx + cmdline_buf]
	add	edi, edx
	lea	esi, [edi + 1]
	rep	movsb
	dec	dword ptr [ebx + cmdline_len]
	jmp	start1$

key_backspace$:	
	mov	edi, [ebx + cmdline_cursorpos]
	cmp	edi, 0
	jbe	start1$
	cmp	edi, [ebx + cmdline_len]
	jz	1f
	mov	esi, edi
	dec	edi
	mov	ecx, MAX_CMDLINE_LEN
	sub	ecx, esi
	jz	1f
	lea	edx, [ebx + cmdline_buf]
	add	esi, edx
	add	edi, edx
	rep	movsb

1:	dec	dword ptr [ebx + cmdline_cursorpos]
	jns	1f
	printc 4, "Error: cursorpos < 0"
1:
	dec	dword ptr [ebx + cmdline_len]
	jns	1f
	PRINTlnc 4, "Error: cmdlinelen < 0"
1:	jmp	start1$

key_left$:
	dec	dword ptr [ebx + cmdline_cursorpos]
	jns	start1$
	inc	dword ptr [ebx + cmdline_cursorpos]
	jmp	start1$

key_right$:
	mov	eax, [ebx + cmdline_cursorpos]
	cmp	eax, [ebx + cmdline_len]
	jae	start1$
	inc	dword ptr [ebx + cmdline_cursorpos]
	jmp	start1$

key_insert$:
	xor	byte ptr [eax + cmdline_insertmode], 1
	jmp	start1$

key_escape$:
	call	cmdline_clear$
	jmp	start1$

#########################################
## Screen buffer key handlers
# Handled by keyboard.s

key_pgup:
	jmp	start1$
key_pgdown:
	jmp	start1$

#########################################
## History key handlers

key_up$:
	mov	eax, [ebx + cmdline_history]
	cmp	[eax + buf_index], dword ptr 0
	jz	start1$
	mov	edx, [ebx + cmdline_history_current]
	sub	edx, 4
	jns	0f
	xor	edx, edx
	jmp	0f

key_down$:
	mov	eax, [ebx + cmdline_history]
	mov	edx, [ebx + cmdline_history_current]
	add	edx, 4
	cmp	edx, [eax + buf_index]
	jb	0f
	mov	edx, [eax + buf_index]
	sub	edx, 4
	js	start1$	# empty

0:	mov	[ebx + cmdline_history_current], edx

	call	cursor_toggle$

	call	cmdline_clear$

	# copy history entry to commandline buffer

	mov	esi, [eax + edx]
	lea	edx, [ebx + cmdline_buf]
	mov	edi, edx
0:	lodsb
	stosb
	or	al, al
	jnz	0b
	sub	edi, edx #offset cmdline
	dec	edi
	mov	[ebx + cmdline_cursorpos], edi
	mov	[ebx + cmdline_len], edi

	jmp	start1$


##########################################################################
# commandline utility functions

# in: ebx = shell_instance
cmdline_clear$:
	push	eax
	push	ecx
	mov	ax,(7<<8)| ' '
	xor	ecx, ecx
	mov	[ebx + cmdline_cursorpos], ecx
	xchg	ecx, [ebx + cmdline_len]
	add	ecx, [ebx + cmdline_prompt_len]
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

	PUSH_SCREENPOS
	call	screen_get_scroll_lines
	push	eax
	PRINT_START_

	# print the prompt

	mov	ebx, edi

	mov	ah, 7
	mov	esi, [ebp] # shell_instance
	lea	esi, [esi + cmdline_cwd]
	call	__print

	mov	ah, 15
	mov	al, ':'
	stosw

	mov	esi, [ebp] # shell_instance
	mov	edx, [esi + cmdline_history_current]
	shr	edx, 2
	mov	ah, 7
	call	__printdec32
	mov	ah, 15
	stosw
	mov	edx, [esi + cmdline_cursorpos]
	mov	ah, 7
	call	__printdec32

	.if VIRTUAL_CONSOLES
	mov	al, ' '
	stosw
	movzx edx, byte ptr [console_cur]
	call __printdec32
	stosw

	mov	esi, [tls]
	mov	esi, [esi + tls_console_cur_ptr]
	mov	edx, [esi + console_pid]
	LOAD_TXT "?"
	mov eax, edx
	push ebx
	push ecx
	call task_get_by_pid
	jc 1f
	mov esi, [ebx + ecx + task_label]
	1:
	mov ah, 9
	pop ecx
	pop ebx
	call __print
	.endif

	mov	ax, 15<<8|'>'
	stosw
	mov	ax, 7<<8|' '
	stosw

	sub	ebx, edi
	neg	ebx
	shr	ebx, 1
	mov	edx, [ebp] # shell_instance
	mov	[edx + cmdline_prompt_len], ebx

	# print the line editor contents

	mov	ebx, edi

	mov	ecx, [edx + cmdline_len]
	jecxz	2f
	lea	esi, [edx + cmdline_buf]

1:	lodsb
	stosw
	loop	1b

2:	mov	al, ' '
	stosw
	stosw

	add	ebx, [edx + cmdline_cursorpos]
	add	ebx, [edx + cmdline_cursorpos]
	mov	al, [edx + cmdline_insertmode]
	xor	al, 1
	shl	al, 4
	not	al
	xor	es:[ebx + 1], al # byte ptr 0xff

	PRINT_END_
	call	screen_get_scroll_lines
	pop	ebx	# screen scroll lines
	sub	eax, ebx
	mov	ebx, 160
	imul	eax, ebx
	sub	[esp], eax
	POP_SCREENPOS

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


newline_if:
	push	eax
	push	edx
	push	ecx
	xor	edx, edx
	call	screen_get_pos
	mov	ecx, 160
	div	ecx
	or	edx, edx
	jz	1f
	call	newline
1:	pop	ecx
	pop	edx
	pop	eax
	ret


###################################################
## Commandline execution

# parses the commandline and executes the command(s)
# in: ebx = cmdline / shell instance
# in: esi = pointer to commandline (zero terminated)
# in: ecx = cmdlinelen
cmdline_execute$:

	DEBUG_TOKENS = 0

	.if DEBUG_TOKENS
		PRINTc 9, "CMDLINE: \""
		#mov	esi, offset cmdline
		call	nprint
		PRINTLNc 9, "\""
		mov	edx, ecx
		call	printhex8
		call	newline
	.endif

	lea	edi, [ebx + cmdline_tokens]
	#mov	esi, offset cmdline
	##mov	ecx, [cmdlinelen]
	push	ebx
	call	tokenize
	pop	ebx
	mov	[ebx + cmdline_tokens_end], edi
	.if DEBUG_TOKENS
		push	ebx
		mov	ebx, edi
		lea	esi, [eax + cmdline_tokens]
		call	printtokens
		pop	ebx
	.endif

	# create an argument list:
	push	ebx
	mov	eax, ebx
	lea	ebx, [eax + cmdline_args]
	lea	edi, [eax + cmdline_argdata]
	lea	edx, [eax + cmdline_tokens]
	lea	ecx, [eax + cmdline_tokens_end]	# unused
	call	tokens_merge
	pop	ebx

	########################

	# debug the arguments:
	.if DEBUG_TOKENS && CMDLINE_DEBUG
		lea	esi, [ebx + cmdline_args]
		call	cmdline_print_args$
	.endif

	# Find the command.

	mov	edi, [ebx + cmdline_args + 0]
	or	edi, edi
	jz	2f

	mov	edx, offset SHELL_COMMANDS
0:	cmp	[edx + shell_command_code], dword ptr 0
	jz	2f

	mov	esi, [edx + shell_command_string]
	or	esi, esi
	jz	2f
	movzx	ecx, word ptr [edx + shell_command_length]
	# TODO: compare lengths to avoid prefix match
	push	edi
	repz	cmpsb
	pop	edi
	jz	1f

	add	edx, SHELL_COMMAND_STRUCT_SIZE
	jmp	0b

2:	PRINTLNc 4, "Unknown command"
	jmp	shell_exec_return$

	# call the command

1:	mov	edx, [edx + shell_command_code]
	lea	esi, [ebx + cmdline_args]

	add	edx, [realsegflat]
	jz	9f
	call	edx	# in: esi = args, ebx = shell instance
shell_exec_return$:	# debug symbol

	ret
9:	printlnc 12, "Error: command null."
	int	1
	ret


##############################################################################
# Commandline History
#
# uses buf_*
#
CMDLINE_HISTORY_MAX_ITEMS = 16
CMDLINE_HISTORY_SHARE = 1	# 0 = singleton

# in: ebx = shell instance
cmdline_history_new:	
	mov	eax, [ebx + cmdline_history]
	or	eax, eax
	.if CMDLINE_HISTORY_SHARE
	jnz	1f
	.else
	call	buf_free
	.endif
	mov	eax, CMDLINE_HISTORY_MAX_ITEMS * 4
	call	buf_new
	mov	[ebx + cmdline_history], eax
1:	mov	[ebx + cmdline_history_current], dword ptr 0
	ret

# in: ebx = shell instance
cmdline_history_delete:
	ARRAY_LOOP [ebx + cmdline_history], 4, ecx, edx, 9f
	mov	eax, [ecx + edx]
	or	eax, eax
	jz	1f
	call	mfree
1:	ARRAY_ENDL
9:	xor	eax, eax
	xchg	eax, [ebx + cmdline_history]
	call	buf_free
	ret

# in: ebx = cmdline / shell instance
# out: edx = current index (if !CF)
# out: CF: not added
cmdline_history_add:
	# check whether this history item is the same as the previous
	mov	ecx, [ebx + cmdline_len]
	jecxz	2f
	mov	eax, [ebx + cmdline_history]
	mov	esi, [eax + buf_index]
	sub	esi, 4
	js	1f	# hist empty

	# check whether this history item already exists
	xor	edx, edx
0:	cmp	edx, [eax + buf_index]
	jae	1f
	mov	esi, [eax + edx]
	add	edx, 4
	lea	edi, [ebx + cmdline_buf]
	call	strlen_
	cmp	ecx, [ebx + cmdline_len]
	jnz	0b
	repz	cmpsb
	jnz	0b
2:	stc
	ret
1:	################################

	# append a pointer to the appended data to the array

	mov	edi, [ebx + cmdline_history]
	mov	esi, [edi + buf_index]
	cmp	esi, [edi + buf_capacity]
	jae	0f	# if below, assume 4 bytes available

	add	[edi + buf_index], dword ptr 4

1:	mov	eax, [ebx + cmdline_len]
	mov	[ebx + cmdline_buf + eax], byte ptr 0
	lea	eax, [ebx + cmdline_buf]
	call	strdup
	mov	[edi + esi], eax

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
	mov	eax, [ebx + cmdline_history]
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
	or	eax, eax
	jz	1f
	cmp	byte ptr [eax], '-'
	jnz	1f
	add	esi, 4
	clc
0:	ret
1:	stc
	ret


#############################################################################
## Builtin Shell commands
#
# meant to be called from the shell: ebx = shell instance

cmd_quit$:
	printlnc 12, "Terminating shell."

	# [esp] = shell_exec_return
	# [esp+4] = return of cmdline_execute call
	add	esp, 8 # skip returning to the shell loop and return from it.

	pop	ebx	# shell instance
	call	cmdline_history_delete

	mov	eax, [ebx + cmdline_cwd_handle]
	call	fs_close

	mov	eax, ebx
	call	mfree

	pop	ebp
	ret

cmd_pwd$:
	lea	esi, [ebx + cmdline_cwd]
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


# end of core commands: < 2kb code
##############################################



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

cmd_cd$:
	push	ebp
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
	.text32
	mov	esi, offset 9b
0:
	# new code
	cmp	byte ptr [ebp], 0
	jz	1f
	print "chdir "
	call	println
1:

	push	esi
	lea	esi, [ebx + cmdline_cwd]
	lea	edi, [ebx + cmdline_cd_cwd]
	mov	ecx, MAX_PATH_LEN
	rep	movsb
	pop	esi
	lea	edi, [ebx + cmdline_cd_cwd]
	call	fs_update_path
##############################################################################
		cmp	byte ptr [esp], 0
		jz	1f
		printc 10, "chdir "
		lea	esi, [ebx + cmdline_cd_cwd]
		call	println
	1:

	mov	eax, [ebx + cmdline_cwd_handle]
	call	fs_close

	lea	eax, [ebx + cmdline_cd_cwd]
	call	fs_opendir
	jc	6f
	mov	[ebx + cmdline_cwd_handle], eax

	.if SHELL_DEBUG_FS
	call	fs_handle_printinfo
	call	newline
	.endif

	# copy path:
	mov	ecx, edi
	lea	esi, [ebx + cmdline_cd_cwd]
	sub	ecx, esi
	lea	edi, [ebx + cmdline_cwd]
	rep	movsb

	# make sure path ends with /, and also make sure it's zero terminated
	cmp	byte ptr [edi-1], 0
	jnz	1f
	dec	edi
1:	xor	ax, ax
	cmp	byte ptr [edi-1], '/'
	jz	1f
	mov	al, '/'
1:	stosw

6:	add	esp, 4
	pop	ebp
	ret

5:	printlnc 10, "usage: cd [<directory>]"

	add	esp, 4
	pop	ebp
	ret


###############################################################################
###############################################################################
###############################################################################

.data SECTION_DATA_BSS
tmp_buf$: .space 2 * 512
.text32

cmd_ls$:
	lodsd
	lodsd

	lea	esi, [ebx + cmdline_cwd]
	lea	edi, [ebx + cmdline_cd_cwd]
	mov	ecx, MAX_PATH_LEN
	rep	movsb

	or	eax, eax
	jz	0f
	mov	esi, eax
	lea	edi, [ebx + cmdline_cd_cwd]
	call	fs_update_path
0:
	lea	eax, [ebx + cmdline_cd_cwd]
	mov	esi, eax	# for print (twice) below

	.if SHELL_DEBUG_FS
		printc	11, "ls "
		call	println
	.endif
	call	fs_opendir	# out: eax
	jc	9f

	printc 11, "Directory Listing for "
	pushcolor 13
	call	print
	popcolor
	printcharc 11, ':'
	call	newline

0:	call	fs_nextentry	# in: eax; out: esi
	jc	0f
	push	eax

	DIRENT_SIZE_ALIGN = 10
	.data
	55: .space DIRENT_SIZE_ALIGN
	.text32

	mov	edx, [esi + fs_dirent_size]
	mov	edi, offset 55b
	call	sprintdec32
	sub	edi, offset 55b
	mov	ecx, DIRENT_SIZE_ALIGN
	sub	ecx, edi
	mov	al, ' '
4:	call	printchar
	loop	4b
	push	esi
	mov	esi, offset 55b
	call	print
	pop	esi
	call	printspace

	# print attr
	pushcolor 8
	mov	dl, [esi + fs_dirent_attr]
	call	printhex2
	popcolor
	call	printspace
	LOAD_TXT "RHSVDA78", ebx
	mov	ecx, 8
1:	mov	al, ' '
	shr	dl, 1
	jnc	2f
	mov	al, [ebx]
2:	call	printchar
	inc	ebx
	loop	1b

	call	printspace
	call	print



	call	newline
	pop	eax
	jmp	0b

0:	call	fs_close	# in: eax
9:	ret

########################################################################

cmd_cat$:
	lodsd
	lodsd
	or	eax, eax
	jz	9f

	# make path

	.if 0
	.data
	88: .asciz "/b/FDOS/SOURCE/KERNEL/CLEAN.BAT/"
	.text32
	.else
	# works:
	.data
	88: .space MAX_PATH_LEN
	.text32
	push	esi
	lea	esi, [ebx + cmdline_cwd]
	mov	edi, offset 88b
	mov	ecx, MAX_PATH_LEN
	rep	movsb
	pop	esi

	mov	edi, offset 88b
	mov	esi, eax
	call	fs_update_path
	jc	9f
	.endif

	.if SHELL_DEBUG_FS
	printc 8, "PATH: "
	mov	esi, offset 88b
	call	print
	call	newline
	.endif

	mov	eax, offset 88b
	call	fs_openfile	# out: eax = file handle
	jc	3f
	call	fs_handle_read # in: eax = handle; out: esi, ecx
	jc	6f

	push	eax
0:	lodsb
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
	call	newline
	jmp	1f
2:	call	printchar
1:	loop	0b
	call	newline_if
	pop	eax

6:	call	fs_close
3:	ret

9:	printlnc 12, "usage: cat <filename>"
	stc
	ret

#####################################
cmd_int_count:
	mov	esi, offset int_count
	mov	ecx, 256
	xor	edx, edx
0:	lodsd
	or	eax, eax
	jz	1f
	call	printhex2
	print ": "
	xchg	edx, eax
	call	printdec32
	call	printspace
	mov	edx, eax

1:	inc	edx
	loop	0b
	call	newline
	ret
#####################################################################
# Shell Environment variables
.struct 0
env_var_label:	.long 0
env_var_value:	.long 0
env_var_handler:.long 0
ENV_VAR_STRUCT_SIZE = .
.data SECTION_DATA_BSS
shell_variables: .long 0
.text32

cmd_set:
	lea	eax, [esi + 4]
	mov	esi, [eax]
	or	esi, esi
	jz	shell_variables_list

	mov	ebx, esi
	printc 11, "SET "
	call	print

	add	eax, 4
	mov	esi, [eax]
	cmp	word ptr [esi], '='
	jnz	1f
	printc 11, " = "

	add	eax, 4
	mov	esi, [eax]
	or	esi, esi
	jz	1f
	call	println

	mov	edi, esi
	mov	esi, ebx
	xor	eax, eax
	call	shell_variable_set

	ret
1:	printlnc 12, "Usage: set name = value"
	stc
	ret


shell_variables_list:
0:	mov	eax, [shell_variables]
	or	eax, eax
	jz	1f
	mov	ecx, [eax + array_index]
	shr	ecx, 3
	jz	1f
0:	mov	esi, [eax + env_var_label]
	call	print
	print_ " = "
	mov	esi, [eax + env_var_value]
	call	println
	add	eax, ENV_VAR_STRUCT_SIZE
	loop	0b
1:	ret


# in: esi = varname
# out: eax + edx = var ptr: [+0] = name ptr [+4] = value ptr
# out: CF = 1: not found
shell_variable_get:
	push	edi
	push	ecx

	mov	eax, [shell_variables]
	or	eax, eax
	stc
	jz	1f

	push	eax
	mov	eax, esi
	call	strlen
	inc	eax
	mov	ecx, eax
	pop	eax

	mov	edx, [eax + array_index]

0:	sub	edx, ENV_VAR_STRUCT_SIZE
	jc	1f
	mov	edi, [eax + edx + env_var_label]
	push	esi
	repz	cmpsb
	pop	esi
	jnz	0b
	clc
1:	pop	ecx
	pop	edi
	ret

cmd_unset:
	add	esi, 4
0:	lodsd
	or	eax, eax
	jz	0f
	push	esi
	mov	esi, eax
	call	shell_variable_unset
	pop	esi
	jmp	0b
0:	ret

# in: esi = varname
shell_variable_unset:
	push	eax
	push	ebx
	push	ecx
	push	edx
	call	shell_variable_get
	jc	0f
	mov	ebx, eax
	mov	eax, [ebx + edx + env_var_label]
	call	mfree
	mov	eax, [ebx + edx + env_var_value]
	call	mfree
	mov	eax, ebx
	mov	ecx, ENV_VAR_STRUCT_SIZE
	call	array_remove
9:	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret
0:	printc	4, "unset: variable not found: "
	call	println
	stc
	jmp	9b

# TODO: locking
# in: esi = varname
# in: edi = value
# in: eax = handler (or 0)
# out: eax = var struct: .long name, value
shell_variable_set:
	push	ebx
	mov	ebx, eax
	call	shell_variable_get
	jc	1f
	# found
	xchg	eax, edi
	call	strdup
	# free string value
	xchg	eax, [edi + env_var_value]
	call	mfree
	mov	eax, edi
	mov	ebx, [edi + env_var_handler]
	jmp	0f
	
1:	# add
	mov	eax, [shell_variables]
	or	eax, eax
	mov	ecx, ENV_VAR_STRUCT_SIZE
	jnz	1f	
	inc	eax	
	call	array_new
1:	call	array_newentry
	mov	[shell_variables], eax
	add	eax, edx
	xchg	eax, esi
	call	strdup
	mov	[esi + env_var_label], eax
	mov	eax, edi
	call	strdup
	mov	[esi + env_var_value], eax
	mov	[esi + env_var_handler], ebx
	mov	eax, esi
0:	or	ebx, ebx
	jz	1f
	call	ebx
1:	pop	ebx
	ret

#####################################
cmd_netdump:
	#call	nic_zeroconf
	#jc	9f

	LOAD_TXT "ethdump"
	push	esi
	mov	edi, esi
	xor	eax, eax
	call	shell_variable_set
	printlnc 11, "Capturing Ethernet packets - press enter to quit."
0:	xor	ax, ax
	call	keyboard
	cmp	ax, K_ENTER
	jnz	0b
	pop	esi
	call	shell_variable_unset
	printlnc 11, "capture complete."
9:	ret
#####################################

.macro CMD_ISARG str
	.data SECTION_DATA_STRINGS
	79: .asciz "\str"
	78: 
	.text32
	push	esi
	mov	esi, offset 79b
	push	ecx
	mov	ecx, 78b - 79b
	push	edi
	mov	edi, eax
	repz	cmpsb
	pop	edi
	pop	ecx
	pop	esi
.endm

.macro CMD_EXPECTARG noarglabel
	lodsd
	or	eax, eax
	jz	\noarglabel
.endm

cmd_print_gdt:

	.macro PRINT_GDT seg
		printc	11, "\seg: "
		mov	edx, \seg
		call	printhex8
		GDT_GET_BASE edx, \seg
		printc	15, " base "
		call	printhex8
		GDT_GET_LIMIT edx, \seg
		printc	15, " limit "
		call	printhex8
		call	newline
	.endm

	PRINT_GDT cs
	PRINT_GDT ds
	PRINT_GDT es
	PRINT_GDT ss
	ret

cmd_ping_gateway:
	.data
	0:
	STRINGPTR "ping"
	STRINGPTR "192.168.1.1"
	STRINGNULL
	.text32
	mov	eax, offset 0b
	mov	esi, eax
	call	cmd_ping
	ret

cmd_gpf:
	printc 0xcf, "Generating GPF"
	mov edx, esp
	call printhex8
	call newline
#	int	0x0d
	#mov	eax, [0xffffffff]
#	mov	ds, eax	# just in case...

#	pushad
	push	ebp

	mov	eax, -1
	mov	ebx, 0xbbbbbbbb
	mov	ecx, 0xcccccccc
	mov	edx, 0xdddddddd
	mov	esi, 0x0e510e51
	mov	edi, 0x0ed10ed1
	mov	ebp, 0x0eb90eb9
	int	0x0d

	pop	ebp
	ret

cmd_colors:
	xor	al, al
0:	COLOR	al
	mov	dl, al
	call	printhex2
	inc	al
	jz	0f
	test	al, 0xf
	jnz	0b
	call	newline
	jmp	0b

0:

	call	newline
	color	7
	ret



.data
.align 4
debugtrap: .long 0
.text32
cmd_debug:
	println "debugging test"

	mov eax, offset debugtrap
#	DEBUG_DWORD eax

#	mov	edx, dr7
#	DEBUG_DWORD edx
#	and	edx, 0x400	# the only predefined 1 flag..
#	mov	ebx, 0xffff27ff # the mask to preserve all bits (and reset resv)
#	DEBUG_DWORD ebx

	call	breakpoint_enable_memwrite_dword

.if 0
	GDT_GET_BASE ebx, ds
	add	eax, ebx
	mov	dr0, eax

	mov	eax, dr7
	and	eax, 0x400	# reset all to 0, keep the 1 flag..
	or	eax, 3	# enable dr0 global and local
	or	eax, (0b11 << 2 | 0b01) << 16	# 4 byte | write only
	mov	dr7, eax
.endif
	call	newline
	DEBUG_DWORD dr0
	DEBUG_DWORD dr1
	DEBUG_DWORD dr2
	DEBUG_DWORD dr3
	DEBUG_DWORD dr7
	call	newline

	print "triggering"
	mov	[debugtrap], dword ptr 1
	println "trigger done."

	ret

cmd_breakpoint:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	mov	eax, [eax]
	mov	bl, 1
	cmp	ax, 'b'
	jz	1f
	add	bl, bl
	cmp	ax, 'w'
	jz	1f
	add	bl, bl
	cmp	ax, 'd'
	jz	1f
	xor	bl, bl
	cmp	ax, 'c'
	jnz	9f
1:	lodsd
	or	eax, eax
	jz	9f
	call	htoi
	jc	9f
	or	bl, bl
	jz	1f
	call	breakpoint_set_memwrite
	ret
1:	call	breakpoint_set_code
	ret
9:	printlnc 12, "usage: breakpoint [b|w|d|c] <hex address>"
	printlnc 12, "  sets mem write breakpoint for b (byte) w (word) d (dword)"
	printlnc 12, "  sets code exec breakpoint for c (code)"
	ret

cmd_pic:
	call	pic_get_mask32
	mov	dx, ax
	call	printbin16
	call	newline
	ret

cmd_ramdisk:
	movzx	eax, word ptr [bootloader_ds]
	movzx	ebx, word ptr [ramdisk]
	shl	eax, 4
	add	eax, ebx
	mov	bx, SEL_flatDS
	mov	fs, bx
	DEBUG "ramdisk address:"
	DEBUG_DWORD eax
	call	newline

	.macro RD label, offs
		printc_ 15, "\label: "
		mov	edx, fs:[eax + \offs]
		call	printhex8
	.endm

	printc_ 11, "entry #0: "
	printc_ 15, "signature: "
	push	dword ptr fs:[eax+4]
	push	dword ptr fs:[eax]
	mov	ecx, 8
	mov	esi, esp
	call	nprint
	add	esp, 8
	RD  " entries", 8
	mov	ecx, edx
	call	newline
	
	mov	ebx, 16
0:	printc_	11, "entry #"
	mov	edx, ebx
	shr	edx, 4
	call	printdec32
	RD ": lba", ebx
	RD " sectors ", ebx+8
	RD " mem start", ebx+4
	RD " end", ebx+12
	call	newline
	add	ebx, 16
	dec	ecx
	jnz	0b
#	loop	0b


	ret


cmd_exe:
	#LOAD_TXT "/c/A.EXE", eax
	LOAD_TXT "/c/A.ELF", eax
	call	fs_openfile
	jc	9f
	call	fs_handle_read
	jc	10f
########
	cmp	[esi], word ptr 'M' | 'Z' << 8
	jz	1f

	cmp	[esi], dword ptr 0x7f | 'E' <<8 | 'L' <<16 | 'F' << 24
	jz	exe_elf

	printlnc 4, "unknown file format"
	jmp	10f

######## EXE
1:	println "EXE/PE32 not supported yet"
	jmp	10f
########
10:	call	fs_close
	jc	9f
9:	ret


.include "elf.s"
.include "libc.s"


cmd_init:
	LOAD_TXT "/a/ETC/INIT.RC"
	mov	al, [boot_drive]
	add	al, 'a'
	mov	[esi + 1], al

	I "Init: "

	mov	eax, esi
	call	fs_openfile
	jc	9f

	I2 "executing "
	call	print
	call	printspace

	call	fs_handle_read	# out: esi, ecx
	jc	7f

	printc 10, "load OK"
	println ", executing"

	jecxz	8f

	push	eax
0:	mov	al, '\n'
	push	ecx
	mov	edi, esi
	repnz	scasb
	pop	ecx
	dec	edi

	push	ecx
	mov	ecx, edi
	sub	ecx, esi

	mov	[esi + ecx], byte ptr 0

	call	trim	# in: esi, ecx; out: esi, ecx, [esi+ecx]=0
	or	ecx, ecx
	mov	eax, ecx
	jle	1f

	cmp	[esi], byte ptr '#'
	jz	1f

	push	ecx
	push	edi
	call	cmdline_execute$
	pop	edi
	pop	ecx
	mov	eax, ecx
1:	pop	ecx
2:
	mov	esi, edi
	inc	esi
	dec	ecx
	sub	ecx, eax
	jg	0b

	pop	eax

8:	call	fs_close
9:	ret
7:	printlnc 4, ": read error"
	jmp	8b


.data SECTION_DATA_BSS
fork_counter$: .long 0
.text32

cmd_fork:
	LOAD_TXT "clock    ", eax
	call	strdup
	push	eax
	lea	edi, [eax + 5]
	mov	edx, [fork_counter$]
	call	sprintdec32

	push	dword ptr 2	# context switch task
	push	cs
	mov	eax, offset clock_task
	add	eax, [realsegflat]
	push	eax
	mov	eax, [fork_counter$]
	inc	dword ptr [fork_counter$]
	call	schedule_task
	ret


clock_task:
	mov	ebx, eax	# calculate screen offset
	add	ebx, 11
	# * 160
	mov	ecx, ebx
	shl	ebx, 2
	add	ebx, ecx
	shl	ebx, 5

	xor	ecx, ecx

	# do it twice so 'top' shows EIP changing
0:	mov	dl, '0'
	call	0f
	hlt
dbg_clk_0:	# debug label
	mov	dl, '1'
	call	0f
	hlt
dbg_clk_1:	# debug label
	jmp	0b

0:	PUSH_SCREENPOS ebx
	pushcolor 0xa0
	print "CLK "
	push	edx
	mov	edx, eax
	call	printhex2
	call	printspace
	mov	edx, [clock]
	call	printhex8
	call	printspace
	mov	edx, ecx
	call	printhex8
	inc	ecx
	pop	edx
	push	eax
	mov	ah, 0xa8
	mov	al, dl
	call	printcharc
	pop	eax
	popcolor
	POP_SCREENPOS
	ret


cmd_shell:
	call	shell
	printlnc 11, "returned from nested shell."
	ret

# Debugger commands:
cmd_sline:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	call	htoi
	jc	9f
	mov	edx, eax
	call	printhex8
	call	printspace

	call	debug_getsource
	jc	1f
	call	print
	mov	edx, eax
	printchar_ ':'
	call	printdec32
	call	newline
	ret

1:	printlnc 12, "no source line found"
	ret

9:	printlnc 4, "usage: sline hex_address"
	ret

cmd_sym:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	call	htoi
	jc	9f
	mov	edx, eax
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	ret
9:	printlnc 4, "usage: sym hex_address"
	ret
