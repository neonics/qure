.intel_syntax noprefix

KERNEL_MIN_STACK_SIZE	= 0x1000	# needs to be power of 2!

.include "defines.s"
.include "macros.s"

SHOWOFF = 0

# Level 0: minimal
# Level 1: informational (hook ints etc)
# Level 2: same detail 
# Level 3: full
# Level 4: full + key presses
DEBUG = 0

# initialize section start labels:
.text
kernel_code_start:
.text16
kernel_rm_code_start:
.data16
data16_start:
.data
data_0_start:
.data SECTION_DATA_SEMAPHORES
data_sem_start:
.data SECTION_DATA_TLS
data_tls_start:
.data SECTION_DATA_CONCAT
data_concat_start:
.data SECTION_DATA_STRINGS
data_str_start:
.data SECTION_DATA_SHELL_CMDS
data_shell_cmds_start:
.data SECTION_DATA_PCI_NIC
data_pci_nic_start:
data_pci_nic:
# .word vendorId, deviceId
# .long driver_constructor
# .long name
# .long 0	# alignment - total size: 16 bytes
.data SECTION_DATA_FONTS
data_fonts_start:
.data SECTION_DATA_SIGNATURE # SECTION_DATA_BSS - 1
data_signature_start:
.data SECTION_DATA_BSS
data_bss_start:
.text32

.include "realmode.s"

.text32
#.org REALMODE_KERNEL_SIZE
kernel_pm_code_start:
kernel_start:
###################################
DEFINE = 1

.macro INCLUDE file, name=0
.ifnc 0,\name
.text32
code_\name\()_start:
.endif
.include "\file"
.ifnc 0,\name
.text32
code_\name\()_end:
.endif
.endm

.include "debug.s"
.include "mutex.s"
include "print.s", print
include "pmode.s", pmode
include "paging.s", paging
include "debugger.s", debugger
include "pit.s", pit
include "keyboard.s", keyboard
include "console.s", console

include "mem.s", mem
include "hash.s", hash
include "string.s", string

include "schedule.s", scheduler

include "token.s", tokenizer
DEFINE = 0
include "fs.s"
include "shell.s"
DEFINE = 1

include "dev.s", dev
include "pci.s", pci
include "bios.s", bios
include "cmos.s", cmos
include "ata.s", ata

include "fs.s", fs
include "partition.s", partition
include "fat.s", fat
include "sfs.s", sfs
include "iso9660.s", iso9660

include "shell.s", shell

code_nic_start:
include "nic.s"
include "rtl8139.s"
include "i8254.s"
include "am79c971.s"
code_nic_end:
include "net.s", net

include "gfx.s", gfx
include "hwdebug.s", hwdebug
include "vmware.s", vmware
###################################

.text32
.code32
code_kernel_start:
kmain:

	# we're in flat mode, so set ds so we can use our data..
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	es, ax

	PRINTLNc 11 "Protected mode initialized."
	COLOR 7

	.if SCREEN_BUFFER
	# copy the screen to the screenbuffer
	push	ecx
	push	esi
	push	edi
	mov	edi, [screen_buf]
	mov	ecx, [screen_pos] # 160 * 25
	add	ecx, 160 * 10	# FIXME: find out why 10 lines mismatch!
	mov	esi, SEL_vid_txt
	mov	ds, esi
	xor	esi, esi
	add	edi, SCREEN_BUF_SIZE
	sub	edi, ecx
	rep	movsb
	pop	edi
	pop	esi
	pop	ecx
	mov	ds, ax
	xor	eax, eax
	.if VIRTUAL_CONSOLES
	call	console_set
	call	tls_get
	mov	[eax + tls_console_kb_cur_ptr], dword ptr offset consoles_kb
	.endif
	.endif

	call	paging_init


	call	debug_load_symboltable	# a simple reference check and pointer calculation.

	# Flush keyboard buffer
0:	mov	ah, KB_PEEK
	call	keyboard
	jz	0f
	xor	ah, ah
	call	keyboard
	jmp	0b
0:	# keyboard buffer flushed

.if SHOWOFF
	mov	[pit_print_timer$], byte ptr 1
	PRINT	"Press key to stop timer."
	mov	ah, 0
	call	keyboard
	mov	[pit_print_timer$], byte ptr 0
.endif
	#call	pit_disable

	call	newline

# debug scroll:
#	PRINT "This is a filler line to have the next line not start at a line bounary."
#	PRINT "this text is meant to be longer than a line to see whether or not this gets scrolled properly, or whether a part is missing at the end, or whether the source index gets offset besides a line bounary."

.if 0	###################################################################
	PRINT "Press a key for int 0x0d"
	xor	ah, ah
	call	keyboard

	int 0x0d
.endif

.if 0	###################################################################
	PRINT	"Press a key to switch to kernel task."
	call	keyboard

	mov	[tss_EIP], dword ptr offset kernel_task
	call	task_switch

	PRINTLNc 0x0c "Back from task"
	jmp	halt
.endif


.if 0	# generate GPF ####################################################
	mov	ax, 1024
	mov	ds, ax

.endif


	###################################################################
	.macro WAITSCREEN
	PRINTc 15 "Press a key to continue."
	mov	ah, 0
	call	keyboard
	call	cls
	.endm

	###################################################################
	I "Memory Map: "

	mov	edx, ds
	call	printhex4
	PRINTCHAR ':'
	
	mov	edx, offset memory_map
	call	printhex8

	call	newline

	call	mem_init
.if SHOWOFF
	MORE
.endif
	###################################################################

	I "BDA:"

	call	bios_list_bda

.if SHOWOFF
	MORE
.endif
	###################################################################

	I "CMOS:"
	call	newline

	call	cmos_list

.if SHOWOFF
	MORE
.endif
	###################################################################

	I "Listing PCI devices:"
	call	newline

	call	pci_list_devices

.if SHOWOFF
	MORE
.endif


	I "ATA:"
	call	ata_list_drives

.if SHOWOFF
	WAITSCREEN
.endif

#	I "CD-ROM ISO9660 Test: "
#	call	newline
#	call	iso9660_test

	##################################################################

.if 0
	I "Hash test"
	call	newline
	call	hash_test
.endif


	I "Relocation: "
	call	0f
0:	pop	edx
	sub	edx, offset 0b
	COLOR 8
	call	printhex8
	I2 " Kernel Load Address: "
	GDT_GET_BASE edx, cs
	call	printhex8
	I2 " Boot Drive: "
	mov	ax, [boot_drive]
	call	disk_print_label
	call	newline
	COLOR 7

	I "Enabling scheduler"
	call	scheduler_init; dbg_kernel_init$:	# debug symbol
	OK


	I "Mounting root filesystem: "
	call	mount_init$

	.data
	0:
	STRINGPTR "mount"
	1:
	STRINGPTR "hdb0\0\0"
	3:
	STRINGPTR "/b"
	STRINGNULL
	.text32
	# overwrite with boot drive
	mov	ax, [boot_drive]
	add	al, 'a'
	mov	edi, [3b]
	inc	edi
	stosb
	mov	edi, [1b]
	add	edi, 2
	stosb
	cmp	ah, -1
	jnz	2f
	xor	al, al
	stosb
	jmp	3f
2:	movzx	edx, ah
	call	sprintdec32
3:	mov	esi, offset 0b
	call	cmd_mount$


	I "Enabling networking"
	call	newline
	call	nic_zeroconf


OPEN_SHELL_DEFAULT = 0


	.if !OPEN_SHELL_DEFAULT
		printc 11, "Press enter to open shell"
	.endif

	.if DEBUG_KERNEL_REALMODE
		printc	8, " ss:sp "
		mov	dx, ss
		call	printhex4
		printchar ':'
		mov	edx, esp
		call	printhex8
		printc	8, ": "
		mov	dx, [esp]
		call	printhex4
	.endif

	.if !OPEN_SHELL_DEFAULT
	1:	xor	ah, ah
		call	keyboard
		cmp	ax, K_ENTER
		jnz	1b
	.endif

1:	call	newline
	I "Shell"
	call	newline

	call	shell
kernel_shell_return$:	# debug symbol
	##################################################################

	call	newline
	PRINTLNc 15, "Press 'q' or ESC to system halt, enter to open shell, 'r' to return to realmode."
	.if DEBUG_KERNEL_REALMODE
		printc	8, "ss:sp "
		mov	dx, ss
		call	printhex4
		printchar ':'
		mov	edx, esp
		call	printhex8
		printc	8, ": "
		mov	edx, [esp]
		call	printhex8
		call	newline
	.endif

0:	
	mov	ah, 0
	call	keyboard
	mov	dx, ax
	PRINT_START 3
	call	__printhex4
	mov	al, dl
	stosw
	mov	al, ' '
	stosw
	PRINT_END
	
	cmp	ax, K_ENTER
	jz	1b
	cmp	ax, K_ESC
	je	1f
	cmp	al, 'r'
	jz	2f
	cmp	al, 'q'
	jne	0b
1:

halt:	call	newline
	PRINTc	0xb, "System Halt."
0:	hlt
	jmp	0b

	# Allocate some console space for realmode printing, which at current
	# does not support scolling properly.
	RESERVE_RM_CONSOLE_LINES = 12
2:	mov	ecx, RESERVE_RM_CONSOLE_LINES
22:	call	newline
	loop	22b
	sub	dword ptr [screen_pos], 160 * RESERVE_RM_CONSOLE_LINES

	# if the pm/rm stack is the same, the rm return addr will be
	# on the stack. Otherwise the rm addr will be on the rm stack.
	jmp	return_realmode


kernel_task:
	PRINTLNc 0x0b "Kernel Task"
	retf

#############################################################################
# TLS initialisation

tls_get:
	mov	eax, [tls]
	or	eax, eax
	jnz	1f
	cmp	[task_queue_sem], dword ptr -1
	jz	0f
	mov	eax, _TLS_SIZE
	call	mallocz
	jnc	2f
	printlnc 4, "error allocating tls"
	ret
	mov	[tls], eax
1:	ret
0:	mov	eax, offset tls_default
2:	mov	[tls], eax
	.if VIRTUAL_CONSOLES
	push	edx
	mov	edx, [console_cur_ptr]
	mov	[eax + tls_console_cur_ptr], edx
	mov	edx, [console_kb_cur]
	mov	[eax + tls_console_kb_cur_ptr], edx
	pop	edx
	.endif
	ret

#############################################################################

kernel_code_end:
code_kernel_end:
# initialize section end labels
.text32
kernel_pm_code_end:
.text16
kernel_rm_code_end:
.data16
data16_end:
.data
data_0_end:
.data SECTION_DATA_SEMAPHORES
data_sem_end:
.data SECTION_DATA_TLS
tls_default:
.space _TLS_SIZE
tls_size: .long _TLS_SIZE
data_tls_end:
.data SECTION_DATA_CONCAT
data_concat_end:
.data SECTION_DATA_STRINGS
data_str_end:
.data SECTION_DATA_SHELL_CMDS
data_shell_cmds_end:
.data SECTION_DATA_PCI_NIC
data_pci_nic_end:
.data SECTION_DATA_FONTS
data_fonts_end:
.data SECTION_DATA_BSS
data_bss_end:
.data SECTION_DATA_SIGNATURE # SECTION_DATA_BSS - 1
kernel_signature:.long 0x1337c0de
data_signature_end:
.data 99
kernel_end:
