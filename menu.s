.intel_syntax noprefix


# menu uses in textmode:
# - list vesa video modes
# - list drives to install
# - browse ramdisk
# expect es:di at line start


.struct 0
menu_title: .space 32
menu_code:  .long 0
menu_item_size: 
.macro MENUITEM code, title
	s = .
	. = s + menu_title
	.asciz "\title"
	. = s + menu_code
	.long \code
.endm

.data
menusel: .byte 0
menuitems:
MENUITEM printregisters2	"Print boot registers"
MENUITEM printregisters		"Print Registers"
MENUITEM gfxmode		"Graphics Mode"
MENUITEM bootcdemulationinfo	"Bootable CD Emulation info"
MENUITEM list_drives		"List Drives"
MENUITEM list_floppies		"List Floppies"
MENUITEM writebootsector	"Write Bootsector"
MENUITEM inspectmem		"InspectMem"
MENUITEM inspectdrive		"Inspect Drive"
MENUITEM inspectbootsector	"Inspect Bootsector"
MENUITEM protected_mode		"Protected Mode"
MENUITEM test_protected_mode	"Enter/Exit Protected Mode"
MENUITEM test_keyboard16	"Test Keyboard handler bit"
MENUITEM acpi_poweroff		"ACPI Poweroff"
menuitemcount:.byte ( . - menuitems ) / menu_item_size
.text
menu:	mov	ax, 0x0f00
	call	cls

drawmenu$:
	mov	dh, [menuitemcount]

	movsx	ax, byte ptr [menusel]
	or	ax, ax
	jns	0f
	add	al, dh
	adc	ah, 0
0:	div	dh
	mov	[menusel], ah

	mov	di, 160 * 1
	xor	dl, dl
0:	mov	ax, 0xf000 #mov	si, offset menu_color
	cmp	dl, [menusel]
	jnz	1f
	xor	ah, 0x20
1:	add	di, 20
	push	di
	mov	cx, menu_code # MUST be after menu_title!
	rep	stosw
	pop	di

	push	ax
	mov	ax, menu_item_size
	mul	dl
	mov	si, ax
	push	dx
	mov	dx, ax
	mov	ah, 0xf1
	call	printhex
	pop	dx
	pop	ax
	add	si, offset menuitems
	push	si
	add	si, menu_title
	call	println
	pop	si

	inc	dl
	cmp	dl, dh  
	jb	0b

	push	di
	mov	di, 2*67
	xor	ah, ah
	int	0x16
	mov	dx, ax
	mov	ah, 0xf4
	PRINT	"KeyCode: "
	call	printhex

	mov	di, 160 + 2 * 49
	mov	ah, 0xf3

	PRINT	"MenuItemOffset: "
	mov	ah, [menusel]
	mov	al, menu_item_size
	mul	ah
	mov	si, offset menuitems
	add	si, ax
	push	dx
	mov	dx, ax
	mov	ah, 0xf3
	call	printhex
	PRINT	"Code: "
	mov	dx, [si + menu_code]
	call	printhex
	pop	dx

	pop	di
	call	newline


	cmp	dx, K_DOWN
	jne	1f
	inc	byte ptr [menusel]
	jmp	drawmenu$
1:
	cmp	dx, K_UP
	jne	1f
	dec	byte ptr [menusel]
	jmp	drawmenu$
1:
	cmp	dx, K_ENTER
	jne	1f

	#relocate offset
	mov	ax, ds
	shl	ax, 4
	add	ax, [si + menu_code]
	call	ax

	call	waitkey
	jmp	drawmenu$
1:
	cmp	dx, K_ESC
	je	2f
	cmp	dl, 'q'
	jz	2f

	mov	ah, 0xfb
	.data
	9: .asciz "Unknown key: "
	.text
	mov	si, 9b
	call	println
	
	call	printhex
	mov	ah, 0xf4
	stosw
	jmp	drawmenu$

2:	ret


.include "floppy.s"


# assume es:di is valid
printregisters2:
	call	newline
	mov	bx, [bootloader_registers_base]

	mov	dx, bx
	call	printhex


	call	newline

	mov	si, offset regnames$
	mov	cx, 16	# 6 seg 9 gu 1 flags 1 ip

0:	mov	ah, 0xf0
	lodsb
	stosw
	lodsb
	stosw

	mov	ah, 0xf8
	mov	al, ':'
	stosw

	mov	ah, 0xf1
	mov	dx, ss:[bx]
	add	bx, 2

	call	printhex

	cmp	cx, 10
	jne	1f

##
	# print flag characters
	push	bx
	push	si
	push	cx

	mov	si, offset regnames$ + 32 # flags
	mov	cx, 16
2:	lodsb
	mov	bl, dl
	and	bl, 1
	jz	3f
	add	al, 'A' - 'a'
3:	shl	bl, 1
	add	ah, bl
	stosw
	sub	ah, bl
	shr	dx, 1
	loop	2b
	
	pop	cx
	pop	si
	pop	bx
##

	call	newline

1: 	loopnz	0b

	call	newline

	ret


test_keyboard16:
	#mov	al, 0xff
	#out	IO_PIC1 + 1, al
	call	hook_keyboard_isr16


	#mov	al, 0
	#out	IO_PIC1 + 1, al

	mov	cx, 0xffff
1:
	push	cx

	mov	cx, 0xffff
	mov	ah, 0xf4
0:	mov	di, 160
	mov	dx, cx
	call	printhex
	loopnz	0b

	pop	cx
	loopnz	1b

	call	restore_keyboard_isr16
	ret

.struct 0
cd_p_size:		.byte 0
cd_p_boot_media_type:	.byte 0
cd_p_drive:		.byte 0 # 00=floppy 80=hdd 81-ff noboot/noemul
cd_p_controller:	.byte 0
cd_p_lba:		.long 0
cd_p_spec:		.word 0
# spec:
# IDE: bit 0 : master/slave
# SCSI: bits 7-0 LUN and PUN
# bits 15-8: bus number
cd_p_buf:		.word 0 # 3k read cache
cd_p_seg:		.word 0 # load segment for initial boot image (if 0:7c0)
cd_p_load_sectors:	.word 0 # nr of 512 byte sectors to load (ah=4C)
				# int 13/ah=08 arguments:
cd_p_cyl_lo:		.byte 0 # low byte of cylinder count
cd_p_sector:		.byte 0 # sector count, high bits cyl count
cd_p_head:		.byte 0 # head number

# 3 more bytes...
.data
cd_spec_packet: .space 0x13
.text
bootcdemulationinfo:
	mov	si, [bootloader_registers_base]
	mov	dl, [si + 24] # dx boot register -> boot drive
	mov	ah, 0xf0
	PRINT "Boot Drive: "
	call	printhex2

	mov	si, offset cd_spec_packet
	mov	ax, 0x4b01
	int	0x13
	mov	dx, ax
	jc	0f
	mov	ah, 0xf0
	print "INT 13h result: "
	call	printhex
	call	newline

	PRINT	"Packet Size:       "
	mov	dl, [si + cd_p_size]
	call	printhex2
	call	newline

	PRINT	"Boot Media Type:   "
	mov	dl, [si + cd_p_boot_media_type]
	call	printhex2

	PRINT	"CDROM controller:  "
	mov	dl, [si + cd_p_controller]
	call	printhex2

	PRINT	"Device Specification: "
	mov	dx, [si + cd_p_spec]
	call	printhex
	call	newline

	PRINT	"LBA of boot image: "
	mov	edx, [si + cd_p_lba]
	call	printhex8
	call	newline


	PRINT	"Read Cache Buffer:    "
	mov	dx, [si + cd_p_buf]
	call	printhex

	PRINT	"Boot Image segment:   "
	mov	dx, [si + cd_p_seg]
	call	printhex
	call	newline


	PRINT	"Drive number:      "
	mov	dl, [si + cd_p_drive]
	call	printhex2

	PRINT	"Load sectors:         "
	mov	dx, [si + cd_p_load_sectors]
	call	printhex

	PRINT	"C/S/H:         "
	mov	dl, [si + cd_p_cyl_lo]
	call	printhex2
	mov	dl, [si + cd_p_sector]
	call	printhex2
	mov	dl, [si + cd_p_head]
	call	printhex2

	ret

0:	mov	ah, 0x4f
	PRINT "Error: "
	call	printhex
	ret
