.intel_syntax noprefix

KERNEL_MIN_STACK_SIZE	= 0x1000	# needs to be power of 2!

KERNEL_SPLIT_RINGS = __KERNEL_SPLIT_RINGS # compiler argument --defsym __K...=1

.if KERNEL_SPLIT_RINGS
.print "Kernel: multiple object files"
.else
.print "Kernel: single object file"
.endif

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
kernel_data_start:
data_0_start:
.data SECTION_DATA_SEMAPHORES
data_sem_start:
.data SECTION_DATA_TLS
data_tls_start:
.data SECTION_DATA_CONCAT
data_concat_start:
.data SECTION_DATA_STRINGS
data_str_start:
.if KERNEL_SPLIT_RINGS
.else
.data SECTION_DATA_PCI_DRIVERINFO
data_pci_driverinfo_start:
# .word vendorId, deviceId
# .long driver_constructor
# .long name
# .long 0	# alignment - total size: 16 bytes
.endif
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
###################################
DEFINE = 1

DEFINE=0
.include "debugger/export.s"
.include "mutex.s"
.include "print.s"
DEFINE=1
.include "mutex.s"
include "print.s", print
include "debugger/export.s", debug
include "pmode.s", pmode
include "paging.s", paging
include "kapi/kapi.s", kapi
include "pit.s", pit
include "keyboard.s", keyboard
include "console.s", console

include "lib/hash.s", hash
include "lib/mem.s", mem
include "lib/buffer.s", buffer
include "lib/string.s", string

include "schedule.s", scheduler

include "lib/token.s", tokenizer
include "oo.s", oo
DEFINE = 0
include "fs.s"
include "shell.s"
include "ata.s"
DEFINE = 1


#include "dev.s", dev
#include "pci.s", pci
include "bios.s", bios
include "cmos.s", cmos
include "dma.s", dma
#include "ata.s", ata
#include "debugger.s", debugger
#include "partition.s", partition
include "fs.s", fs
include "fs/fat.s", fat
include "fs/sfs.s", sfs
include "fs/fs_oofs.s", oofs
include "fs/iso9660.s", iso9660


.if KERNEL_SPLIT_RINGS
	.print "<< SPLIT RINGS >>"

	.global pci_get_device_subclass_info


	# idt
	.global add_irq_handler
	.global IRQ_BASE
	# pic
	.global IRQ_PRIM_ATA
	.global IRQ_SEC_ATA
	.global IRQ_RTC
	.global IRQ_KEYBOARD
	.global hook_isr

	# print
	.global nprint
	.global nprint_
	.global nprintln
	.global nprintln_
	.global print
	.global print_
	.global print_flags16
	.global print_size
	.global sprint_size
	.global print_time_ms_40_24
	.global sprint_time_ms_40_24
	.global printc
	.global printchar
	.global printcharc
	.global printdec32
	.global sprintdec32
	.global printhex
	.global printhex1
	.global printhex2
	.global printhex4
	.global printhex8
	.global sprinthex8
	.global println
	.global println_
	.global printspace
	.global _s_print
	.global _s_printc
	.global _s_println
	.global _s_printlnc
	.global _s_setcolor
	.global _s_pushcolor
	.global printbin8
	.global printbin16
	.global newline

	.global screen_update

	.global __print
	.global __scroll

	# string
	.global strlen
	.global strlen_
	.global atoi
	.global atoi_
	.global htoi
	.global strncmp
	.global strcmp

	# hash
	.global ptr_array_new
	.global ptr_array_newentry
	.global array_new
	.global array_newentry
	.global array_free
		# struct fields:
	.global array_index
	.global array_capacity
	.global buf_index

	# buffer
	.global buffer_put_byte
	.global buffer_put_word
	.global buffer_put_dword
	.global buffer_write

	.global buffer_new
	.global buffer_free
	.global buffer_index
	.global buffer_start


	.global realsegflat

	# keyboard
	.global keyboard
	.global KB_GETCHAR

	# pit
	.global sleep
	.global udelay
	.global pit_timer_frequency
	.global pit_timer_period
	.global clock
	.global clock_ms
	.global get_time_ms
	.global get_time_ms_40_24

	# scheduler
	.global task_wait_io

	# pic
	.global pic_enable_irq_line32

	# paging
	.global page_directory_phys
	.global page_directory_phys
	.global paging_idmap_memrange

	# gfx / vmware/svga2
	.global vidw; .extern vidw
	.global vidh; .extern vidh
	.global vidb; .extern vidb
	.global vidbpp; .extern vidbpp
	.global vidfbuf; .extern vidfbuf
	.global curfont
	.global fonts4k
	.global fontwidth
	.global fontheight
	.global gfx_printchar_ptr
	.global gfx_printchar_8x16

	.global gfx_txt_screen_update
	.global default_screen_update	# from print.s

	# gdt
	.global GDT

	# mutex
	.global mutex
	.global mutex_owner

	# mem
	.global malloc
	.global malloc_aligned
	.global mallocz
	.global mallocz_aligned
	.global mrealloc
	.global mreallocz
	.global mfree
	.global mdup
	.global mem_heap_size
	.global mem_get_used
	.global mem_get_reserved
	.global mem_get_free

	# dev/pci
	.global class_nulldev
	# pci

	.global pci_list_devices
#	.global pci_device_class_names
	.global pci_read_config
	.global pci_write_config
	.global pci_busmaster_enable
	.global pci_get_bar
	.global pci_get_bar_addr
	.global DEV_PCI_CLASS_NIC_ETH
	.global DEV_PCI_CLASS_VID_VGA
	.global DEV_PCI_CLASS_SERIAL_USB
	.global DEV_PCI_CLASS_SERIAL_USB_EHCI
	.global DEV_PCI_CLASS_SERIAL_USB_OHCI
	.global DEV_PCI_CLASS_BRIDGE
	.global DEV_PCI_CLASS_BRIDGE_ISA
	.global DEV_PCI_CLASS_BRIDGE_PCI2PCI
	.global DEV_PCI_CLASS_BRIDGE_PCI2PCI_STS
	.global DEV_PCI_CLASS_STORAGE_IDE

	# ata
	.global ata_print_capacity
	#disks
	.global cmd_disks_print$


	# shell
	.global cmdline_print_args$
	.global getopt
	.global cmdline_execute$
	.global cmdline_init
	.global cmdline_print_prompt$
	.global shell_print_prompt$
	.global shell_execute$
	.global shell_variable_get

	# debug
	.global more
	.global debug_printvalue
	.global debug_assert_array_index

	# debugger
	.global debug_printsymbol

	# fs
	.global fs_update_path
	.global FS_DIRENT_ATTR_DIR
	.global fs_fat_partinfo


	## ../lib ##
	# sha1
	.global sha1
	.global sha1_init
	.global sha1_next
	.global sha1_finish


	# kernel labels
	.global data_0_start
	.global kernel_end

	# console / print
	.global console_get
	.global console_screen_pos
	.global console_screen_color
	.global console_screen_buf
	.global console_screen_buf_pos
	.global screen_buf_flush	# print.s

	# realmode/pmode stuff
	.global boot_drive

	#partition.s
	.global disk_print_label

	# dma
	.global dma_buffersize
	.global dma_transfer
	.global dma_getpos
	.global dma_stop
	.global dma_buffer_abs


	##########
.else
	.print "<< ring2 included >>"
	RING2_INCLUDED=1
	.include "ring2.s"
.endif

include "gfx.s", gfx
include "vmware/vmware.s", vmware
#include "vbox/vbga.s", vbox
#code_sound_start:
#include "sound/es1371.s", es1371
#include "sound/sb.s", sb
#code_sound_end:
include "shell.s", shell

include "debugger/debugger.s", debugger
include "debugger/hwdebug.s", hwdebug
###################################

.text32
.code32
code_kernel_start:
kmain:
	# we're in flat mode, so set ds so we can use our data..
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	es, ax
	mov	byte ptr [0], 0xcc	# trigger int 3 when executing offset 0

	PRINTLNc 11 "Protected mode initialized."
	COLOR 7

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

	.if 0 # Use this when mem overwrite is detected
		println "Enabling Breakpoint"
		DEBUG_DWORD esp
		mov	eax, 0x000111b8
		mov	bl, 1
		call	breakpoint_set_memwrite
	.endif

	.if 0	# debugger test
		_DBG_BP_ENABLED=0
		BREAKPOINT "1 - ERROR"
		_DBG_BP_ENABLED=1
		BREAKPOINT "2 - expected"

		DEBUGGER BP DISABLE
		BREAKPOINT "3 - ERROR"
		DEBUGGER BP ENABLE
		BREAKPOINT "4 - expected"

		DEBUGGER BP DISABLE	# so far so good - enabled later.
	.endif

# debug scroll:
#	PRINT "This is a filler line to have the next line not start at a line bounary."
#	PRINT "this text is meant to be longer than a line to see whether or not this gets scrolled properly, or whether a part is missing at the end, or whether the source index gets offset besides a line bounary."

.if 0	###################################################################
	PRINT "Press a key for int 0x0d"
	xor	ah, ah
	call	keyboard

	int 0x0d
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

	call	paging_init

	call	kapi_init	# initialize the kernel api (uses paging)

MEM_TEST = 0
SCHEDULE_EARLY = 0

.if MEM_TEST
	SCHEDULE_EARLY = 1
	I "Enabling scheduler"
	call	scheduler_init; dbg_kernel_init$:	# debug symbol
	OK

	call	mem_test$
.endif

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

	call	cmos_get_date
	.data SECTION_DATA_BSS
	.global kernel_boot_time
	kernel_boot_time: .long 0
	.text32
	mov	[kernel_boot_time], edx

	COLOR 7

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

	COLOR 7

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

	I "Boot Drive: "
	mov	ax, [boot_drive]
	call	disk_print_label
	call	newline

	###################################################################
	# when this is placed right after mem_init, NIC doesn't work
.if !SCHEDULE_EARLY
	I "Enabling scheduler"
	call	scheduler_init; dbg_kernel_init$:	# debug symbol
	OK
.endif
	###################################################################


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

	call	cmd_dnsd
	call	cmd_httpd
	call	cmd_smtpd
	call	cmd_sshd
	call	cmd_sipd
	call	cmd_cloudnetd
	YIELD	# give scheduler a chance to run daemons

OPEN_SHELL_DEFAULT = 1	# see .if 1 below - kcons also prints the message


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

.if 0	# 0 = CPL0 shell
	PUSH_TXT "kcons"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset console_shell # or shell
	# task args:
	mov	eax, [console_cur_ptr]
	mov	ebx, [console_kb_cur]
	mov	esi, [esp + 12]
	call	schedule_task
	mov	ebx, [console_cur_ptr]
	mov	[ebx + console_pid], eax
	println "Kernel idle loop"
	xor	eax, eax
	call	task_suspend
0:	hlt
kernel_idle$:	# debug symbol
	jmp	0b
.else
	call	shell
.endif
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
0:	mov	eax, offset tls_default
2:	mov	[tls], eax
	push	edx

	mov	edx, [scheduler_current_task_idx]
	mov	[eax + tls_task_idx], edx

	.if VIRTUAL_CONSOLES
	mov	edx, [console_cur_ptr]
	mov	[eax + tls_console_cur_ptr], edx
	mov	edx, [console_kb_cur]
	mov	[eax + tls_console_kb_cur_ptr], edx
	.endif
	pop	edx
1:	ret

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
.if !KERNEL_SPLIT_RINGS
.data SECTION_DATA_PCI_DRIVERINFO
data_pci_driverinfo_end:
.endif
.data SECTION_DATA_FONTS
data_fonts_end:
.data SECTION_DATA_BSS
data_bss_end:
.data 99
