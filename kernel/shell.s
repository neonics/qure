.intel_syntax noprefix
# include with DEFINE = 0 to declare macros and structures (optional)
# include with DEFINE = 1 to define code and data (and macros/structures if
# they are not declared yet).
# Since the shell references most of the kernel code and their constants,
# and since constants must be declared before they are properly referenced
# by the GNU assembler, this file is included with DEFINE=1 after those
# kernel components which' constants it references.
# Since most kernel subsystems (fs, net,...) define some commandline interfaces
# that use some macros from this file, this file is included before them
# with DEFINE=0.
# Thus, with DEFINE=0, this file acts like a C header file,
# and with DEFINE=1, acts like the source file.

###############################################################################
.ifndef SHELL_DECLARED	# begin declarations
SHELL_DECLARED = 1

CMDLINE_DEBUG = 1	# 1: include cmdline_print_args$;
			# 2: 
SHELL_DEBUG_FS = 0


############################################################################

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

.struct 0
shell_command_code: .long 0
shell_command_string: .long 0
shell_command_length: .word 0
SHELL_COMMAND_STRUCT_SIZE = .

.macro SHELL_COMMAND string, addr
	.data SECTION_DATA_STRINGS
		9: .asciz "\string"
		8:
	.section .shellcmd
		.long \addr
		.long 9b
		.word 8b - 9b
	.text32
.endm

.macro SHELL_COMMAND_CATEGORY string
	SHELL_COMMAND "\string",-1
.endm

.endif		# end declarations
############################################################################
.if DEFINE	# begin definitions (code, data)
MAX_CMDLINE_LEN = 1024
MAX_CMDLINE_ARGS = 256

DECLARE_CLASS_BEGIN cmdline
cmdline_buf:		.space MAX_CMDLINE_LEN
cmdline_len:		.long 0
cmdline_cursorpos:	.long 0
cmdline_insertmode:	.byte 0
cmdline_prompt_len:	.long 0 # "the_prefix> ".length
cmdline_history:	.long 0	# list/array/linked list.
cmdline_history_current:.long 0 # the current array item offset (up/down keys)
DECLARE_CLASS_METHOD cmdline_constructor, cmdline_init
DECLARE_CLASS_METHOD cmdline_api_print_prompt, cmdline_print_prompt$
DECLARE_CLASS_METHOD cmdline_api_execute, cmdline_execute$
DECLARE_CLASS_END cmdline
############################################################################
DECLARE_CLASS_BEGIN shell, cmdline
shell_cwd:		.space MAX_PATH_LEN
shell_cwd_handle:	.long 0
shell_cd_cwd:		.space MAX_PATH_LEN

cmdline_argdata:	.space MAX_CMDLINE_LEN + MAX_CMDLINE_ARGS
cmdline_args:		.space MAX_CMDLINE_ARGS * 4

cmdline_tokens_end:	.long 0
cmdline_tokens:	.space MAX_CMDLINE_LEN * 8 / 2	 # assume 2-char min token avg

DECLARE_CLASS_METHOD cmdline_api_print_prompt, shell_print_prompt$, OVERRIDE
DECLARE_CLASS_METHOD cmdline_api_execute, shell_execute$, OVERRIDE
DECLARE_CLASS_END shell
############################################################################

############################################################################
### Shell Command list
.section .shellcmd
SHELL_COMMANDS:
SHELL_COMMAND_CATEGORY "console"
SHELL_COMMAND "cls",		cls
SHELL_COMMAND "colors"		cmd_colors
SHELL_COMMAND "ascii"		cmd_ascii
# shell
SHELL_COMMAND_CATEGORY "shell"
SHELL_COMMAND "shell"		cmd_shell
SHELL_COMMAND "quit",		cmd_quit$
SHELL_COMMAND "exit",		cmd_quit$
SHELL_COMMAND "help",		cmd_help$
SHELL_COMMAND "hist",		cmdline_history_print

SHELL_COMMAND "set"		cmd_set
SHELL_COMMAND "unset"		cmd_unset

SHELL_COMMAND "strlen",		cmd_strlen$
SHELL_COMMAND "echo",		cmd_echo$
# filesystem
SHELL_COMMAND_CATEGORY "filesystem"
SHELL_COMMAND "ls",		cmd_ls$
SHELL_COMMAND "cd",		cmd_cd$
SHELL_COMMAND "pwd",		cmd_pwd$
SHELL_COMMAND "cat",		cmd_cat$
SHELL_COMMAND "touch",		cmd_touch$
SHELL_COMMAND "mkdir",		cmd_mkdir$
#
SHELL_COMMAND "disks",		cmd_disks_print$
SHELL_COMMAND "listdrives",	ata_list_drives
SHELL_COMMAND "fdisk",		cmd_fdisk
SHELL_COMMAND "partinfo",	cmd_partinfo$
SHELL_COMMAND "mkfs",		cmd_mkfs
#
SHELL_COMMAND "mount",		cmd_mount$
SHELL_COMMAND "umount",		cmd_umount$
#
SHELL_COMMAND "listfs"		fs_list_filesystems
SHELL_COMMAND "lsof",		fs_list_openfiles
SHELL_COMMAND "fat_handles"	cmd_fat_handles
SHELL_COMMAND "oofs"		cmd_oofs
# memory
SHELL_COMMAND_CATEGORY "memory"
SHELL_COMMAND "mem",		cmd_mem$	# aka 'free'
SHELL_COMMAND "mtest",		malloc_test$
# hardware
SHELL_COMMAND_CATEGORY "hardware"
SHELL_COMMAND "dev"		cmd_dev
SHELL_COMMAND "lspci",		pci_list_devices
SHELL_COMMAND "pcibus",		pci_print_bus_architecture
SHELL_COMMAND "drivers",	cmd_list_drivers
# network
SHELL_COMMAND_CATEGORY "network"
# nonstandard
SHELL_COMMAND "nics", 		cmd_nic_list	# aka 'ifconfig'
SHELL_COMMAND "netdump"		cmd_netdump
SHELL_COMMAND "zconf"		nic_zeroconf
# standard
SHELL_COMMAND "ifconfig"	cmd_ifconfig
SHELL_COMMAND "ifup"		cmd_ifup
SHELL_COMMAND "ifdown"		cmd_ifdown
SHELL_COMMAND "route"		cmd_route
SHELL_COMMAND "dhcp"		cmd_dhcp
SHELL_COMMAND "ping"		cmd_ping
SHELL_COMMAND "p"		cmd_ping_gateway
SHELL_COMMAND "host"		cmd_host
SHELL_COMMAND "traceroute"	cmd_traceroute
SHELL_COMMAND "netstat"		cmd_netstat
SHELL_COMMAND "arp"		cmd_arp
SHELL_COMMAND "icmp"		net_icmp_list
# utils
SHELL_COMMAND_CATEGORY "misc"
SHELL_COMMAND "hostname"	cmd_hostname
SHELL_COMMAND "hs",		cmd_human_readable_size$
#SHELL_COMMAND "regexp",		regexp_parse
SHELL_COMMAND "obj"		pci_list_obj_counters
SHELL_COMMAND "gfx"		cmd_gfx
SHELL_COMMAND "stats"		cmd_stats
# tasks / processes
SHELL_COMMAND_CATEGORY "tasks"
SHELL_COMMAND "exe"		cmd_exe
SHELL_COMMAND "init"		cmd_init
SHELL_COMMAND "fork"		cmd_fork
SHELL_COMMAND "top"		cmd_top
SHELL_COMMAND "ps"		cmd_tasks
SHELL_COMMAND "kill"		cmd_kill
SHELL_COMMAND "bg"		cmd_suspend
SHELL_COMMAND "fg"		cmd_resume
# Debugger:
SHELL_COMMAND_CATEGORY "debugging"
SHELL_COMMAND "breakpoint"	cmd_breakpoint
SHELL_COMMAND "gpf"		cmd_gpf
SHELL_COMMAND "debug"		cmd_debug
SHELL_COMMAND "pic"		cmd_pic
SHELL_COMMAND "ints",		cmd_int_count
SHELL_COMMAND "int",		cmd_int
SHELL_COMMAND "gdt"		cmd_print_gdt
SHELL_COMMAND "idt"		cmd_print_idt
SHELL_COMMAND "irq"		print_irq_handlers
SHELL_COMMAND "cr",		cmd_cr
SHELL_COMMAND "sline",		cmd_sline
SHELL_COMMAND "sym",		cmd_sym
SHELL_COMMAND "paging"		cmd_paging
SHELL_COMMAND "vmcheck"		cmd_vmcheck
SHELL_COMMAND "vmx"		cmd_vmx
SHELL_COMMAND "ramdisk"		cmd_ramdisk
SHELL_COMMAND "inspect_str"	cmd_inspect_str
SHELL_COMMAND "keycode"		cmd_keycode
.if VIRTUAL_CONSOLES
SHELL_COMMAND "consoles"	cmd_consoles
.endif
SHELL_COMMAND "sha1"		cmd_sha1
SHELL_COMMAND "base64"		cmd_base64
SHELL_COMMAND "classes"		cmd_classes
SHELL_COMMAND "objects"		cmd_objects
SHELL_COMMAND "ph"		cmd_ping_host
SHELL_COMMAND_CATEGORY "experimental"
SHELL_COMMAND "svga"		cmd_svga
SHELL_COMMAND "xml"		cmd_xml
SHELL_COMMAND "play"		cmd_play
SHELL_COMMAND "kapi"		cmd_kapi
SHELL_COMMAND "kapi_test"	cmd_kapi_test
SHELL_COMMAND "uptime"		cmd_uptime
SHELL_COMMAND "date"		cmos_print_date
SHELL_COMMAND "shutdown"	cmd_shutdown
SHELL_COMMAND "reboot"		cmd_reboot
# NOTE: linker must terminate list with LONG(0);
### End of Shell Command list
############################################################################

.text32	
cmdline_init:
	push	ebx
	mov	ebx, eax
	mov	[ebx + cmdline_insertmode], byte ptr 1
	call	cmdline_history_new
	pop	ebx
	jc	9f
	ret

9:	printlnc 4, "cmdline: out of memory"
	stc
	ret

########################################################
# do not call: call shell.
shell_init$:
	mov	eax, offset class_shell
	call	class_newinstance
	jc	9f

	call	[eax + cmdline_constructor]
	mov	[eax + shell_cwd], word ptr '/'
	ret

9:	printlnc 4, "shell: out of memory"
	add	esp, 4
	stc
	ret

########################################################

shell:	push	ds
	pop	es

	call	shell_init$	# out: eax = shell instance
	mov	ebx, eax	# calling convention for shell

	push	ebp
	push	ebx
	mov	ebp, esp

	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

	#

	lea	eax, [ebx + shell_cwd]
	KAPI_CALL fs_opendir
	mov	[ebx + shell_cwd_handle], eax

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
	call	[ebx + cmdline_api_execute]
	
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

# in: edi = prompt buffer
cmdline_print_prompt$:
	ret


shell_print_prompt$:
	mov	ah, 7
	lea	esi, [ebx + shell_cwd]
	call	__print

	mov	ax, 15 << 8 | ':'
	stosw

	mov	edx, [ebx + cmdline_history_current]
	shr	edx, 2
	mov	ah, 7
	call	__printdec32
	mov	ax, 15 << 8 | ':'
	stosw
	mov	edx, [ebx + cmdline_cursorpos]
	mov	ah, 7
	call	__printdec32
	mov	al, ' '
	stosw

.if VIRTUAL_CONSOLES
	mov	ax, 7 << 8 | ' '
	movzx	edx, byte ptr [console_cur]
	call	__printdec32
	stosw

	mov	esi, [tls]
	mov	esi, [esi + tls_console_cur_ptr]
	mov	edx, [esi + console_pid]
	LOAD_TXT "?"
	mov	eax, edx
	push_	ebx ecx
	call	task_get_by_pid
		jnc 1f
		printc 0xf4, "TASK_GET_BY_PID FAIL"
	1:
	jc	1f
	mov	esi, [ebx + ecx + task_label]
	1:
	mov	ah, 9
	pop_	ecx ebx
	call	__print
.endif
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

	push	edi

	call	[ebx + cmdline_api_print_prompt]

	mov	eax, (15<<8|'>') | ((7<<8|' ')<<16)
	stosd

	pop	edx	# old edi

	sub	edx, edi
	neg	edx
	shr	edx, 1

	mov	[ebx + cmdline_prompt_len], edx

	# print the line editor contents

	mov	edx, edi

	mov	ah, 7

	mov	ecx, [ebx + cmdline_len]
	jecxz	2f
	lea	esi, [ebx + cmdline_buf]

1:	lodsb
	stosw
	loop	1b

2:	mov	al, ' '
	stosw
	stosw

	add	edx, [ebx + cmdline_cursorpos]
	add	edx, [ebx + cmdline_cursorpos]
	mov	al, [ebx + cmdline_insertmode]
	xor	al, 1
	shl	al, 4
	not	al
	xor	es:[edx + 1], al # byte ptr 0xff

	PRINT_END_
	call	screen_get_scroll_lines
	pop	edx	# screen scroll lines
	sub	eax, edx
	mov	edx, 160
	imul	eax, edx
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

# parses the commandline
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

	ret

# parses the commandline and executes the command(s)
# in: ebx = cmdline / shell instance
# in: esi = pointer to commandline (zero terminated)
# in: ecx = cmdlinelen
shell_execute$:
	call	cmdline_execute$

	# Find the command.

	mov	edi, [ebx + cmdline_args + 0]
	or	edi, edi
	jz	2f

	mov	edx, offset SHELL_COMMANDS
0:	cmp	[edx + shell_command_code], dword ptr 0 # EOL
	jz	2f
	cmp	[edx + shell_command_code], dword ptr -1 # category
	jz	3f

	mov	esi, [edx + shell_command_string]
	or	esi, esi
	jz	2f
	movzx	ecx, word ptr [edx + shell_command_length]
	# TODO: compare lengths to avoid prefix match
	push	edi
	repz	cmpsb
	pop	edi
	jz	1f

3:	add	edx, SHELL_COMMAND_STRUCT_SIZE
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
	push	eax
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
	pop	eax
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

	mov	eax, [ebx + shell_cwd_handle]
	KAPI_CALL fs_close

	mov	eax, ebx
	call	mfree

	pop	ebp
	ret

cmd_pwd$:
	lea	esi, [ebx + shell_cwd]
	call	println
	ret

.data SECTION_DATA_STRINGS
cmd_help_intro$:
.ascii "For usage, run a command with -? or --help; -h works too except for"
.asciz "commands\nfor which it is a valid argument.\n"
.text32

cmd_help$:
	# calculate shell command category name maxlen
	mov	ebx, offset SHELL_COMMANDS

	xor	edx, edx
0:	cmp	[ebx + shell_command_code], dword ptr 0	# EOL
	jz	0f
	cmp	[ebx + shell_command_code], dword ptr -1 # cat label
	jnz	1f
	mov	ax, [ebx + shell_command_length]
	cmp	ax, dx
	jb	1f
	mov	dx, ax
1:	add	ebx, SHELL_COMMAND_STRUCT_SIZE
	jmp	0b
0:

	push	dword ptr offset cmd_help_intro$
	call	printf
	add	esp, 4

	#
	mov	ebx, offset SHELL_COMMANDS
0:	cmp	[ebx + shell_command_code], dword ptr 0 # EOL
	jz	0f
	mov	esi, [ebx + shell_command_string]
	or	esi, esi
	jz	0f
	cmp	[ebx + shell_command_code], dword ptr -1 # cat label
	jnz	1f	# not cat
	call	newline	# prints newline for first cat too - after help intro.
	mov	ah, 15
	call	printc
	# pad
	call	strlen_
	neg	ecx
	add	ecx, edx
	add	ecx, 2
3:	call	printspace
	loop	3b
	jmp	2f
1:	# word-wrap
	GET_SCREENPOS eax
	shr	eax, 1
	push	edx
	xor	dx, dx
	mov	cx, 80
	div	cx
	add	dx, word ptr [ebx + shell_command_length]
	cmp	dx, 80
	pop	edx
	jb	1f
	call	newline
	# pad
	mov	ecx, edx
	add	ecx, 2
3:	call	printspace
	loop	3b
	#
1:	call	print
	mov	al, ' '
	call	printchar
2:	add	ebx, SHELL_COMMAND_STRUCT_SIZE
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
	lea	esi, [ebx + shell_cwd]
	lea	edi, [ebx + shell_cd_cwd]
	mov	ecx, MAX_PATH_LEN
	rep	movsb
	pop	esi
	lea	edi, [ebx + shell_cd_cwd]
	call	fs_update_path
##############################################################################
		cmp	byte ptr [esp], 0
		jz	1f
		printc 10, "chdir "
		lea	esi, [ebx + shell_cd_cwd]
		call	println
	1:

	mov	eax, [ebx + shell_cwd_handle]
	KAPI_CALL fs_close

	lea	eax, [ebx + shell_cd_cwd]
	KAPI_CALL fs_opendir
	jc	6f
	mov	[ebx + shell_cwd_handle], eax

	.if SHELL_DEBUG_FS
	KAPI_CALL fs_handle_printinfo
	call	newline
	.endif

	# copy path:
	mov	ecx, edi
	lea	esi, [ebx + shell_cd_cwd]
	sub	ecx, esi
	lea	edi, [ebx + shell_cwd]
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

	lea	esi, [ebx + shell_cwd]
	lea	edi, [ebx + shell_cd_cwd]
	mov	ecx, MAX_PATH_LEN
	rep	movsb

	or	eax, eax
	jz	0f
	mov	esi, eax
	lea	edi, [ebx + shell_cd_cwd]
	call	fs_update_path
0:
	lea	eax, [ebx + shell_cd_cwd]
	mov	esi, eax	# for print (twice) below

	.if SHELL_DEBUG_FS
		printc	11, "ls "
		call	println
	.endif
	KAPI_CALL fs_opendir	# out: eax
	jc	9f

	printc 11, "Directory Listing for "
	pushcolor 13
	call	print
	popcolor
	printcharc 11, ':'
	call	newline

0:	KAPI_CALL fs_nextentry	# in: eax; out: esi
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

######## print attributes/permissions
	mov	eax, [esi + fs_dirent_posix_perm]
	or	eax, eax
	jz	1f

	call	fs_posix_perm_print
	call	printspace
	mov	edx, [esi + fs_dirent_posix_uid]
	call	printdec32
	call	printspace
	mov	edx, [esi + fs_dirent_posix_gid]
	call	printdec32

	# print mtime
	call	printspace
	pushcolor 8
	push	esi
	lea	esi, [esi + fs_dirent_posix_mtime]
	cmp	dword ptr [esi], 0
	jz	2f
	call	fs_posix_time_print
	jmp	3f
2:	print "                 "
3:	pop	esi
	popcolor

	# ls --color
	# ls -F: "/@|=>*" [dir link pipe socket door executable]
	mov	ebx, eax
	mov	edx, eax
	mov	ax, 9 << 8 | '/'
	and	edx, POSIX_TYPE_MASK
	cmp	edx, POSIX_TYPE_DIR
	jz	3f
	mov	ax, 11 << 8 | '@'
	cmp	edx, POSIX_TYPE_LINK
	jz	3f
	mov	al, '|'
	cmp	edx, POSIX_TYPE_FIFO
	jz	3f
	mov	al, '='
	cmp	edx, POSIX_TYPE_SOCK
	jz	3f
	# '>': door (sun/solaris)
	mov	ax, 10 << 8 | '*'
	test	ebx, POSIX_PERM_X | POSIX_PERM_X << 3 | POSIX_PERM_X << 6
	jnz	3f
	mov	ax, 7 << 8 | ' '
	jmp	3f
########
1:	mov	dl, [esi + fs_dirent_attr]
	pushcolor 8
	call	printhex2
	call	printspace
	popcolor
	LOAD_TXT "RHSVDA78", ebx
	mov	ecx, 8
1:	mov	al, ' '
	shr	dl, 1
	jnc	2f
	mov	al, [ebx]
2:	call	printchar
	inc	ebx
	loop	1b

	mov	ax, 7 << 8
	test	byte ptr [esi + fs_dirent_attr], 0x10 # dir
	jz	3f
	mov	ax, 9 << 8 | '/'
########
# in: al = trailer char ('/' for dir, '@' for link, ' ' for file, '=' for chr?)
# in: ah = color
3:	call	printspace
	call	printc
	call	printchar

1:	call	newline
	pop	eax
	jmp	0b

0:	KAPI_CALL fs_close	# in: eax
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
	lea	esi, [ebx + shell_cwd]
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
	KAPI_CALL fs_openfile
#	KAPI_CALL fs_openfile	# out: eax = file handle
	jc	3f
	KAPI_CALL fs_handle_read # in: eax = handle; out: esi, ecx
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

6:	KAPI_CALL fs_close
3:	ret

9:	printlnc 12, "usage: cat <filename>"
	stc
	ret


.data
umask:	.long 0755
.text32
cmd_mkdir$:
	mov	edx, POSIX_TYPE_DIR | 0777
	printc 11, "mkdir "
	jmp	1f
cmd_touch$:
	mov	edx, POSIX_TYPE_FILE | 0777
	printc 11, "touch "
1:	mov	eax, [umask]
	or	eax, ~0777
	and	edx, eax

	mov	eax, edx
	call	fs_posix_perm_print
	call	printspace

	or	esi, esi
	jz	9f
	lodsd
	lodsd
	or	eax, eax
	jz	9f

	push	ebp
	mov	ebp, esp
	sub	esp, MAX_PATH_LEN
########
	mov	edi, esp
	push	esi
	lea	esi, [ebx + shell_cwd]
	mov	ecx, MAX_PATH_LEN
	rep	movsb
	pop	esi
	mov	esi, eax
	mov	edi, esp
	call	fs_update_path
	jc	8f

	mov	eax, esp
	KAPI_CALL fs_create	# in: eax=name, edx=POSIX flags
########
8:	mov	esp, ebp
	pop	ebp
	ret
9:	printlnc 4, "usage: touch <filename>"
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

cmd_print_gdt:
	PRINT_GDT cs
	PRINT_GDT ds
	PRINT_GDT es
	PRINT_GDT ss

	xor	edx, edx
0:	call	debug_print_gdt_descriptor; call newline
	add	edx, 8
	cmp	edx, SEL_MAX
	jb	0b
	ret

cmd_print_idt:
	xor	eax, eax
	mov	ecx, IRQ_BASE + 16
0:	mov	edx, eax
	shr	edx, 3
	print "INT "
	call	printhex2
	print " Address: "
	DT_GET_SEL edx, eax, IDT
	call	printhex4
	print ":"
	DT_GET_OFFSET edx, eax, IDT
	call	printhex8
	call	newline
	add	eax, 8
	dec	ecx
	jnz	0b
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

cmd_ping_host:
	.data
	0:
	STRINGPTR "ping"
	STRINGPTR "-n"
	STRINGPTR "1"
	STRINGPTR "192.168.1.10"
	STRINGNULL
	.text32
	mov	eax, offset 0b
	mov	esi, eax
	call	cmd_ping
	ret

cmd_int:
	lodsd
	lodsd
	call	htoi
	jc	9f
	cmp	eax, 0xff
	ja	9f
	mov	[1f], al
	DEBUG_WORD cs
	DEBUG_DWORD (offset 3f), "eip"
	DEBUG_WORD ss
	DEBUG_DWORD esp
	call	newline
	mov	dl, al
	print "Generating int 0x"
	call	printhex2
	call	newline
	jmp	2f
2:	jmp	2f
2:
		.byte 	0xcd
	1:	.byte 0
3:
	ret
9:	printlnc 4, "usage: int <int_nr_hex_max_ff>"
	ret

cmd_gpf:
	printc 0xcf, "Generating GPF"
	mov edx, esp
	call printhex8
	call newline

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
0:	call	newline
	color	7
	ret

cmd_ascii:
	xor	al, al
	mov	ah, 16
1:	mov	ecx, 16
0:	call	printchar
	inc	al
	loop	0b
	call	newline
	dec	ah
	jnz	1b
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
	mov	edx, dr0; DEBUG_DWORD edx, "dr0"
	mov	edx, dr1; DEBUG_DWORD edx, "dr1"
	mov	edx, dr2; DEBUG_DWORD edx, "dr2"
	mov	edx, dr3; DEBUG_DWORD edx, "dr3"
	mov	edx, dr7; DEBUG_DWORD edx, "dr7"
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
	mov	ax, cs
	test	al, 3
	jz	1f
	call	SEL_kernelCall, 0
1:	call	pic_get_mask32
	mov	dx, ax
	call	printbin16
	call	newline
	.data SECTION_DATA_STRINGS
	1: .asciz "TIMR","KEYB","CASC","COM2","COM1","LPT2","FPLY","LPT1"
	.asciz "RTC\0", "FRE1", "FRE2","FRE3","PS2M","FPU\0", "ATA0","ATA1"
	.text32
	mov	edx, IRQ_BASE
	mov	esi, offset 1b
0:	shr	ax, 1
	jc	1f	# carry means masked/disabled
	call	printhex2
	call	printspace
	call	print
	call	printspace
	.if IRQ_PROXIES
	push	edx
	shl	edx, 4
	mov	edx, [irq_proxies + edx + 2]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	pop	edx
	call	newline
	.endif
1:	inc	dx
	add	esi, 5
	cmp	dx, IRQ_BASE + 0xf
	jbe	0b
9:	call	newline
	ret

cmd_ramdisk:
	movzx	eax, word ptr [bootloader_ds]
	movzx	ebx, word ptr [ramdisk]
	shl	eax, 4
	add	eax, ebx
mov bx, cs
cmp bx, SEL_compatCS
jz 1f
mov bx, ds
add bx, SEL_ring0DSf - SEL_ring0DS
jmp 2f
1:
	mov	bx, SEL_flatDS
2:
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
	RD " size", ebx+8
	call	printspace
	add	edx, 511
	shr	edx, 9
	call	printhex4
	RD "S mem start", ebx+4
	RD " end", ebx+12
	call	newline
	add	ebx, 16
	dec	ecx
	jnz	0b
#	loop	0b


	ret


cmd_exe:
	#LOAD_TXT "/a/a.elf", eax
	#LOAD_TXT "/a/test.elf", eax
	LOAD_TXT "/a/a.exe", eax
	mov	bl, [boot_drive]
	add	bl, 'a'
	mov	[eax + 1], bl
	KAPI_CALL fs_openfile
	jc	91f
	push	eax
	mov	eax, ecx
	call	mallocz
	mov	edi, eax
	pop	eax
	jc	92f
	KAPI_CALL fs_read	# in: eax, edi, ecx
	jc	93f
	mov	esi, edi
########
	push_	edi esi eax
	cmp	[esi], word ptr 'M' | 'Z' << 8
	jz	1f

	cmp	[esi], dword ptr 0x7f | 'E' <<8 | 'L' <<16 | 'F' << 24
	jz	2f

	printlnc 4, "unknown file format"
	jmp	11f

######## EXE
1:	call	exe_pe
	jmp	11f
######## ELF
2:	call	exe_elf
########
11:	pop_	eax esi edi

	push	eax
	mov	eax, edi
	call	mfree
	pop	eax
10:	KAPI_CALL fs_close
	jc	9f
9:	ret

91:	printlnc 4, "file not found"
	ret
92:	printlnc 4, "malloc fail"
	jmp	10b
93:	printlnc 4, "read error"
	jmp	11b


.include "exe/elf.s"
.include "exe/pe.s"
.include "exe/libc.s"


cmd_init:
	LOAD_TXT "/a/ETC/INIT.RC"
	mov	al, [boot_drive]
	add	al, 'a'
	mov	[esi + 1], al

	I "Init: "

	mov	eax, esi
	KAPI_CALL fs_openfile
	jc	9f

	I2 "executing "
	call	print
	call	printspace

	KAPI_CALL fs_handle_read	# out: esi, ecx
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

8:	KAPI_CALL fs_close
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

	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	mov	eax, offset clock_task
	add	eax, [realsegflat]
	push	eax
	mov	eax, [fork_counter$]
	inc	dword ptr [fork_counter$]
	KAPI_CALL schedule_task
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
	YIELD
dbg_clk_0:	# debug label
	mov	dl, '1'
	call	0f
	YIELD
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
	mov	esi, eax

	call	htoi
	jc	1f
	mov	edx, eax
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	ret
1:	# not hex, so assume symbol name
	call	print
	print ": "
	mov	edx, esi
	call	debug_findsymboladdr
	jc	1f
	call	printhex8
	call	newline
	ret

1:	printlnc 4, "not found"
	ret

9:	printlnc 4, "usage: sym hex_address"
	ret

cmd_cr:
	printc 11, "cr0: "
	mov	edx, cr0
	call	printhex8
	call	newline

	# cr1 N/A

	printc 11, "cr2: "
	mov	edx, cr2
	call	printhex8
	call	newline

	printc 11, "cr3: "
	mov	edx, cr3
	call	printhex8
	call	newline

	printc 11, "cr4: "
	mov	edx, cr4
	call	printhex8
	call	newline

	# cr5, cr6, cr7 N/A

	# cr8 and further wrap to 0 etc
	ret

cmd_vmx:
	mov	eax, 1
	cpuid
	test	ecx, 1 << 5
	jz	1f
	println "VMX supported"
	ret
1:	printlnc 4, "No VMX support"
	ret

.include "../lib/sha.s"
cmd_sha1:
	push	ebp
	mov	ebp, esp
	sub	esp, 512
	LOAD_TXT "abc"
	call	strlen_
	mov	edi, esp
	push	ecx
	rep	movsb
	pop	ecx
	mov	esi, esp
#xor ecx,ecx
	call	sha1
	mov	esi, edi
	mov	ecx, 20
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	loop	0b
	call	newline
	mov	esp, ebp
	pop	ebp
	ret

.include "../lib/base64.s"
cmd_base64:
	lodsd
	lodsd
	or	eax, eax
	jz	9f
	mov	ebx, esi	# remember for decode
	mov	esi, eax
	call	strlen
	mov	ecx, eax
	xor	edi, edi
	call	base64_encode
	mov	esi, edi
	print "ENCODED: "
	push	ecx
	call	nprintln_
	pop	ecx

	mov	esi, edi
	mov	edi, ebx
	mov	byte ptr [edi], 0
	call	base64_decode	# esi,ecx, edi

	print "DECODED: "
	mov	esi, ebx
	call	println

9:	ret

cmd_list_drivers:
	lodsd
	lodsd
	mov	bl, -1	# list all drivers
	or	eax, eax
	jz	1f
	call	htoi
	jc	9f
	mov	ebx, eax
1:	call	pci_list_drivers	# in: bl=-1 or bx=PCI class
	ret
9:	printc 4, "usage: "
	mov	esi, [esi - 8]
	call	print
	printlnc 4, " [hex_pci_class]"
	mov	esi, offset pci_device_class_names
	mov	ecx, PCI_MAX_KNOWN_DEVICE_CLASS
	xor	dl, dl
	PUSHCOLOR 7
0:	COLOR 7
	call	printhex2
	inc	dl
	call	printspace
	push	dword ptr [esi]
	COLOR 11
	call	_s_println
	add	esi, 8
	loop	0b
	POPCOLOR

	ret

########################################################################
.data SECTION_DATA_BSS
sound_dev: .long 0
sb_play_fhandle: .long 0
.text32
get_sound_dev:
	mov	ebx, [es1371_isr_dev$]
	mov	[sound_dev], ebx

	mov	ebx, [sound_dev]
	or	ebx, ebx
	jnz	9f

	mov	eax, offset class_sb
	call	class_newinstance
	jc	9f

	mov	[sound_dev], eax
	mov	ebx, eax

	push	ebx
	call	[ebx + dev_api_constructor]
	pop	ebx
9:	ret


cmd_play:
	push	ebp
	mov	ebp, esp
	push	dword ptr 0	# ebp -4 : fs handle

	call	get_sound_dev
	jc	9f

#	mov word ptr [sb_addr], -1
#	mov byte ptr [sb_irq], -1
#	mov byte ptr [SB_DMA], -1
#cmp word ptr [sb_addr], -1
#jnz 1f
#	mov	[SB_SampleRate], word ptr 44100
#	mov	[SB_Bits_Sample], byte ptr 16
#	mov	byte ptr [SB_Stereo], -1
#	call	sb_detect
#	jc	9f
1:
	.if 1
	mov	eax, 44100
	call	[ebx + sound_set_samplerate]
	mov	al, 0b11	# 16 bit stereo
	call	[ebx + sound_set_format]
	.else

	mov	[SB_SampleRate], word ptr 44100
	mov	[SB_Bits_Sample], byte ptr 16
	mov	[SB_Stereo], byte ptr -1
	mov	al, [sb_dma16]
	mov	[SB_DMA], al
	.endif
	mov	[dma_buffersize], dword ptr 0x10000
	call	dma_allocbuffer

	#####
	lodsd
	lodsd
	or	eax, eax
	jnz	1f
	LOAD_TXT "/c/test.wav", eax
	mov	dl, 'a'
	add	dl, [boot_drive]
	mov	[eax + 1], dl
	mov	ebx, eax	# backup to print error
1:	xor	edx, edx
	KAPI_CALL fs_open
	jc	91f
	mov	[ebp - 4], eax
	mov	[sb_play_fhandle], eax
	#################################
	#################################
	mov	edi, [dma_buffer]
	mov	ecx, [dma_buffersize]
	mov	eax, [ebp -4]
	KAPI_CALL fs_read
	jc	92f

	######################################
	# Parse the 12 byte RIFF header
	mov	edi, [dma_buffer]
	# "RIFF", 	'$', 16, a7, 3	"WAVE", 		"fmt "
	# 10, 0, 0, 0, 	1, 0, 2, 0		44, ac, 0, 0	10, b1, 02, 00
	# 4, 0, 10, 0, 	"data", 		0, 16, a7, 03	0, 0, 0, 0
	cmp	dword ptr [edi], 'R'|'I'<<8|'F'<<16|'F'<<24
	jnz	93f
	mov	edx, [edi+4]
	sub	edx, 0x24	# riff header
#	print	"RIFF_Blocksize: "
#	call	printdec32

	cmp	dword ptr [edi+8], 'W'|'A'<<8|'V'<<16|'E'<<24
	jnz	93f
	add	edi, 12

0:	cmp	dword ptr [edi], 'f'|'m'<<8|'t'<<16|' '<<24
	jz	$riff_fmt
	cmp	dword ptr [edi], 'l'|'o'<<8|'o'<<16|'p'<<24
	jz	$riff_loop
	cmp	dword ptr [edi], 'd'|'a'<<8|'t'<<16|'a'<<24
	jnz	93f

$riff_data:
	add	edi, 4
	jmp	1f
$riff_loop:
	add	edi, 4 + 8	# 8  bytes loop info
	jmp	0b
$riff_fmt:
	# 20 bytes wave_blocksize
	mov	edx, [edi + 4]	# wave_blocksize
	sub	edx, 20	# fmt header
	add	edi, 4 + 20	# 4: skip prev sig
	# fmt block:
	# wave_blocksize dd 16
	# format tag: .word 0
	# channels: .word 0
	# samplerate: .long
	# bytes per sec: .long 0 # chans*smprate
	# blockalign: .word 0
	# bitspersample: .word 8
	jmp	0b

1:
	# we'll just play the riff headers for now..

	#################################
	mov	ebx, [sound_dev]

	mov	eax, offset sb_play_wave_file$
	call	[ebx + sound_playback_init]
#	call	sb_playback_init
	#mov	[sb_playback_buffer_handler], dword ptr offset sb_play_wave_file$

	call	[ebx + sound_playback_start]
#	call	sb_dma_transfer
	#################################
	println "Playing..."
	call	more
	call	[ebx + sound_playback_stop]
	#call	SB_ExitTransfer
	#################################

1:	mov	eax, [sb_play_fhandle]
	or	eax, eax
	jz	9f
	KAPI_CALL fs_close

9:	mov	esp, ebp
	pop	ebp
	ret

91:	printc 4, "file not found: "
	push	ebx
	call	_s_println
	jmp	9b
92:	printlnc 4, "read error"
	jmp	1b
93:	printlnc 4, "invalid file format"
	jmp	1b

sb_play_wave_file$:
        mov     edi, [dma_buffer]
        mov     ecx, [dma_buffersize]
	shr	ecx, 1

	xor	[sb_dma_buf_half], byte ptr 1
	jnz	1f
	add	edi, ecx
1:
	mov     eax, [sb_play_fhandle]
	or	eax, eax
	jz	8f

	pushfd
	sti
	KAPI_CALL fs_read
	jnc	1f
	printc 4, "fs_read error"

	KAPI_CALL fs_close
	mov	dword ptr [sb_play_fhandle], 0
	mov	[SB_StopPlay], byte ptr 1
1:
	popfd
	ret

8:	mov	eax, 0x80008000	# assume 16 bit
	shr	ecx, 2
	rep	stosd
	mov	ebx, [sound_dev]
	call	[ebx + sound_playback_stop]
	ret


cmd_paging:
	mov	eax, cs
	and	al, 3
	jz	1f
	call	SEL_kernelCall:0
1:
	cli	# don't allow task switching as it will trash cr3

	mov	eax, cr3
	push	eax

	mov	eax, [page_directory_phys]
	mov	cr3, eax

	mov	edx, [scheduler_current_task_idx]
	add	edx, [task_queue]
	mov	edx, [edx + task_page_dir]
	and	edx, 0xfffff000

	xor	edi, edi	# task label
	lodsd
	lodsd
	or	eax, eax
	jnz	1f
	call	paging_show_struct
	jmp	0f
1:
################################
	CMD_ISARG "-p"
	jnz	1f

	lodsd
	call	htoi
	jc	9f
	call	task_get_by_pid	# out: ebx + ecx
	jc	91f

	mov	edx, [ebx + ecx + task_page_dir]
	mov	edi, [ebx + ecx + task_label]

	lodsd
	mov	ebx, offset paging_show_struct_
	or	eax, eax
	jz	2f
1:	
###############################
# edx = page dir
# edi = task label, or 0
	mov	ebx, offset paging_show_struct_

	CMD_ISARG "usage"
	jnz	9f
	mov	ebx, offset paging_show_usage_

2:	or	edi, edi
	jz	1f
	mov	esi, edi
	print "Paging structure for task: "
	call	println

1:	mov	esi, edx
	call	ebx	# in: esi

0:	pop	eax
	mov	cr3, eax
	sti
	ret

9:	printlnc 4, "usage: paging [-p <hex pid>] [usage]"
	jmp	0b
91:	printc 4, "unknown task: "
	mov	edx, eax
	call	printdec32
	call	newline
	jmp	0b

cmd_uptime:
	print "Uptime: "
	call	get_time_ms_40_24
	call	print_time_ms_40_24
	call printspace
	call get_time_ms
	mov edx, eax
	call printdec32
	print "ms"
	call	newline

		sub esp, 40
		mov edi, esp
		call get_time_ms_40_24
		call sprint_time_ms_40_24
		mov esi, esp
		mov ecx, edi
		sub ecx, esi
		call nprintln
		add esp, 40
	ret

.include "../lib/xml.s"
.include "acpi.s"

cmd_shutdown:
	call	acpi_shutdown
	ret

cmd_reboot:
	cli
	pushd	0
	pushw	0
	lidt [esp]
	int 3

cmd_stats:
	printc 15, "Task Switches: "
	mov	edx, [stats_task_switches]
	call	printdec32
	call	newline
	ret

cmd_inspect_str:
	lodsd
	lodsd
	or	eax, eax
	jz	91f
	call	htoi
	jc	9f
	mov	edx, eax
	lodsd
	or	eax, eax
	jz	91f
	call	htoi
	jc	9f
	mov	ecx, eax
	mov	esi, edx
	call	nprintln
9:	ret
91:	printlnc 4, "usage: t <hex_addr> <hex_len>"
	ret

cmd_keycode:
	printlnc 15, "Press any key; ESC to quit"
0:	xor	ah, ah
	call	keyboard
	mov	edx, eax
	call	printhex8
	call	printspace
	call	printchar
	call	newline
	cmp	ax, K_ESC
	jnz	0b
	ret

cmd_hostname:
	mov	esi, offset hostname
	cmp	byte ptr [esi], 0
	jz	9f
	call	println
9:	ret
.endif
