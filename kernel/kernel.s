.intel_syntax noprefix

SHOWOFF = 0

DEBUG = 3
.include "debug.s"
.include "realmode.s"
.text
kernel_start:
###################################
DEFINE = 1
.include "print.s"
.include "debugger.s"
.include "pmode.s"
.include "pit.s"
.include "keyboard.s"

.include "mem.s"
.include "hash.s"
.include "string.s"

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

.include "iso9660.s"

.include "nic.s"
.include "rtl8139.s"
.include "net.s"
###################################

.text
.code32
kmain:

	# we're in flat mode, so set ds so we can use our data..
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	es, ax

	PRINTLNc 11 "Protected mode initialized."
	COLOR 0xf
.if SHOWOFF
	PRINT	"Press key to stop timer."
	mov	ah, 0
	call	keyboard
.endif
	call	pit_disable

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

	I "Mounting root filesystem"
	call	mount_init$
	call	newline

	#MORE
.if SHOWOFF
	WAITSCREEN
.endif

#	I "CD-ROM ISO9660 Test: "
#	call	newline
#	call	iso9660_test

	##################################################################

	I "Hash test"
	call	newline
	call	hash_test


	I "Shell"
	call	newline

	call	shell

	##################################################################

	call	newline
	PRINTc 15, "Press 'q' or ESC to system halt."

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
	
	cmp	al, 'q'
	je	1f
	cmp	ax, K_ESC
	jne	0b
1:

halt:	call	newline
	PRINTc	0xb, "System Halt."
0:	hlt
	jmp	0b


kernel_task:
	PRINTLNc 0x0b "Kernel Task"
	retf



.data
sig:.long 0x1337c0de
kernel_end:
