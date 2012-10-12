.intel_syntax noprefix

KERNEL_MIN_STACK_SIZE	= 0x1000	# needs to be power of 2!

# .data layout
SECTION_DATA		= 0
SECTION_DATA_CONCAT	= 1
SECTION_DATA_STRINGS	= 2
SECTION_DATA_PCI_NIC	= 3
SECTION_DATA_BSS	= 10
SECTION_DATA_SIGNATURE	= SECTION_DATA_BSS -1

# .text layout
SECTION_CODE_TEXT16	= 0
SECTION_CODE_DATA16	= 1	# keep within 64k
SECTION_CODE_TEXT16_END	= 2
SECTION_CODE_TEXT32	= 3

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
.data SECTION_DATA_CONCAT
data_concat_start:
.data SECTION_DATA_STRINGS
data_str_start:
.data SECTION_DATA_PCI_NIC
data_pci_nic_start:
data_pci_nic:
# .word vendorId, deviceId
# .long driver_constructor
# .long name
# .long 0	# alignment - total size: 16 bytes
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
.include "debug.s"
.include "print.s"
.include "pmode.s"
.include "debugger.s"
.include "pit.s"
.include "keyboard.s"

.include "mem.s"
.include "hash.s"
.include "string.s"

.include "schedule.s"

.include "token.s"
.include "shell.s"

.include "dev.s"
.include "pci.s"
.include "bios.s"
.include "cmos.s"
.include "ata.s"

.include "fs.s"
.include "partition.s"
.include "fat.s"
.include "sfs.s"

.include "iso9660.s"

.include "nic.s"
.include "rtl8139.s"
.include "i8254.s"
.include "am79c971.s"
.include "net.s"

.include "gfx.s"
.include "hwdebug.s"
.include "vmware.s"
###################################

.text32
.code32
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
	mov	ecx, [screen_pos] # 160 * 25
	add	ecx, 160
	mov	esi, SEL_vid_txt
	mov	ds, esi
	xor	esi, esi
	mov	edi, offset screen_buf + SCREEN_BUF_SIZE
	sub	edi, ecx
	rep	movsb
	pop	edi
	pop	esi
	pop	ecx
	mov	ds, ax
	.endif

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

	#MORE
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
	mov	dword ptr [schedule_sem], 0
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
kernel_code_end:
# initialize section end labels
.text32
kernel_pm_code_end:
.text16
kernel_rm_code_end:
.data16
data16_end:
.data SECTION_DATA_CONCAT
data_concat_end:
.data SECTION_DATA_STRINGS - 1
data_0_end:
.data SECTION_DATA_STRINGS
.byte 0
data_str_end:
.data SECTION_DATA_PCI_NIC
data_pci_nic_end:
.data SECTION_DATA_SIGNATURE # SECTION_DATA_BSS - 1
#kernel_signature:.long 0x1337c0de # when bss is no longer stored in .data, enable this
data_signature_end:
.data SECTION_DATA_BSS
kernel_signature:.long 0x1337c0de # enabled this to check bootloader ramdisk overwrite
data_bss_end:
.data 99
kernel_end:
