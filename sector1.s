# included in bootloader.s
.intel_syntax noprefix
.text
. = 512
.data
bootloader_registers_base: .word 0
msg_sector1$: .asciz "Transcended sector limitation!"
msg_entering_pmode$: .asciz "Entering Protected Mode"
.text
	mov	[bootloader_registers_base], bp

	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	println

	mov	dx, 0x1337
	call	printhex

	call	printregisters

	call	waitkey

	call	menu

	call	cls
	PRINT "System Halt."
	jmp	halt

###################################################

.include "print2.s"
.include "keycodes.s"
.include "pmode.s"
.code16
.include "gfxmode.s"
.include "acpi.s"

waitkey:
	.data
	msg_press_key$: .asciz "Press a key to continue..."
	.text
	push	si
	push	dx

	mov	si, offset msg_press_key$
	call	print

	push	ax
	xor	ah, ah
	int	0x16
	pop	dx
	xchg	ax, dx	# restore ah
	call	printhex
	call	newline
	mov	ax, dx
	pop	dx
	pop	si
	ret


.data
drive_numbers: .long -1, -1  # support 8 drives...
.text
list_drives:
	mov	ax, 0xf200
	call	cls

	mov	bx, offset drive_numbers
	xor	dx, dx
0:	call	print_drive_info
	jc	1f
	mov	[bx], dl
	inc	bx
1:	inc	dl
	cmp	dl, 4
	jl	0b

	mov	dl, 0x80
0:	call	print_drive_info
	jc	1f
	mov	[bx], dl
	inc	bx
1:	inc	dl
	cmp	dl, 0x84
	jl	0b

	call	newline
print_drive_numbers:
	mov	ah, 0x3f
	print	"Drive numbers: "
	mov	si, offset drive_numbers
	mov	cx, 8
0:	lodsb
	mov	dl, al
	call	printhex2
	loop	0b
	ret



print_drive_info:
	.data
	msg_disk_error$: .asciz "DiskERR "
	.text
	push	bp
	push	dx	
	push	bx
	call	printhex2 # dl: drive number

	push	ax
	push	es
	push	di
	mov	ah, 8
	xor	bh, bh
	xor	di,di
	mov	es,di
	int	0x13
	jnc 	0f
	inc	bh	# es:di, ax, dx, bx
0:	mov	bp, es
	mov	fs, bp
	mov	bp, di
	pop	di
	pop	es
	mov	gs, ax
	pop	ax	# fs:bp, gs, dx

	or	bh, bh
	jz 	0f
	mov	si, offset msg_disk_error$
	inc	ah
	call	print
	dec	ah
	jmp	1f

0:	
	call	printhex# dh: heads dl: harddisks
	mov	dx, gs	# ah: retcode al:?
	call	printhex
	mov	dx, bx	# bl: floppy drive type
	call	printhex2
	mov	dx, cx	# cx[7:6]cx[15:8]: last cylinder, cx[5:0] sectors/track
	call	printhex
	mov	dx, fs
	call	printhex
	mov	byte ptr es:[di-2],':'
	mov	dx, bp
	call	printhex
1:	mov	dl, bh
	dec	ah
	call	printhex2
	inc	ah

	call	newline
	sar	bh, 1
	pop	bx
	pop	dx
	pop	bp
	ret

printbootdrive$:
	.data
	txt_drive$: .asciz "Drive "
	.text
	mov	si, offset txt_drive$;
	call	print

	mov	si, [bootloader_registers_base]
	mov	al, [si + 24]
	test	al, 0x80
	jz	0f
	and	al, 0x7f
	add	al, 'C'
	jmp	1f
0:	add	al, 'A'
1:	stosw
	call	newline
	ret


writebootsector:
	.data
	msg_bootsect_written$: .asciz "Bootsector Written"
	msg_bootsect_fail$: .asciz "Bootsector write failure"
	.text
	push	bp
	mov	bp, [bootloader_registers_base]

	call	newline
	mov	ah, 0xf0
	PRINT	"Write bootsector @ "
	mov	dx, [bp + 0]
	call	printhex
	mov	es:[di - 2], byte ptr ':'
	mov	dx, [bp + 30]
	call	printhex
	call	newline

	push	es
	# ds:0000 should equal the bootsector:
	#mov	bx, ds
	#mov	es, bx
	#xor	bx, bx
	# however, take the original cs:ip values to be consistent:
	mov	es, ss:[bp + 0]
	mov	bx, ss:[bp + 30]

	mov	dx, 0x0080	# dl = first HDD
	mov	cx, 1		# cylinder=0, sector = 1
	mov	ax, (3<<8) + 1	+ SECTORS # ah = 3 write al sectors

	int	0x13
	pop	es
	jc	2f

	mov	dx, ax
	mov	ah, 0xf0
	call	printhex 


# verify
	mov	dx, 0x80
	mov	cx, 1
	mov	ax, (0x04 << 8) + 1 # SECTORS + 1
	push	es
	mov	bx, ds
	mov	es, bx
	mov	bx, ss:[bp+30]
	int	0x13
	pop	es
	jc	2f

	mov	dx, ax
	mov	ah, 0xf0
	call	printhex 

	mov	si, offset msg_bootsect_written$
	call	print

0:	pop	bp
	ret
2:	mov	dx, ax
	mov	ah, 0xf2
	call	printhex
	mov	si, offset msg_bootsect_fail$
	call	print
	jmp	0b

# todo: scrolling in newline
# todo: replace cls, print*, newline with functions preserving es:di


.include "menu.s"


# in: 
# ah: color
# bx: relative offset: 0: display absolute (si); other: display relative to bx
# cx: ch = lines, cl = columns; cl*ch = total bytes dumped
# dx: bottom limit: 0 for no limit
# ds:si data to dump
hexdump:
.text
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	bp

	mov	bp, sp

.equ hexdump_cols$, bp + 6
.equ hexdump_lines$, bp + 7

	mov	ah, 0x08
	
	or	bx, bx	# if a base is specced, dont use seg:offs
	jnz	0f
	mov	dx, ds
	call	printhex
	mov	byte ptr es:[di-2], ':'
	0:

	mov	dx, si
	call	printhex
	mov	al, '('
	stosw
	mov	dx, bx
	call	printhex
	mov	es:[di-2], byte ptr ')'

	inc	ah

	xor	ch, ch
	mov	cl, [hexdump_lines$]

####
1:	push	cx
	push	bp

	call	newline
	mov	dx, si
	call	printhex
	mov	byte ptr es:[di-2],':'

	xor	ch, ch
	mov	cl, [hexdump_cols$]

	mov	bp, di
	add	bp, 2*(16 * 3)
	mov	byte ptr es:[bp], '|'
##
0:	mov	al, ds:[si+bx]
	add	si, 1
	mov	dl, al
	add	bp, 2
	mov	es:[bp], al
	call	printhex2
	loopnz	0b
##
	add	bp, 2
	mov	byte ptr es:[bp], '|'

	pop	bp
	pop	cx

	loop	1b
####
	call	newline

	pop	bp
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret


inspectmem:
	.data
	msg_inspectmem$: .asciz "Inspect memory "
	inspect_offset$: .word 0
	inspect_segment$: .word 0
	.text

	mov	bx, ss:[bp + 30]
	mov	[inspect_offset$], bx
inspect$:
	mov	ax, 0x0800
	call	cls

	mov	si, offset msg_inspectmem$
	call	print
	mov	si, [inspect_offset$]
	mov	dx, si
	call	printhex
	push	ds
	mov	cx, word ptr [inspect_segment$]
	mov	ds, cx
	mov	cx, 0x1010
	xor	bx, bx # print abs addr
	xor	dx, dx # nolimit
	call	hexdump
	pop	ds

	call	waitkey

.macro KEY_SCROLL key what scroll
	cmp	ax, \key
	jne	0f
	add	[\what], word ptr \scroll
	jmp	1f
0:
.endm

	KEY_SCROLL K_UP, inspect_offset$ -16
	KEY_SCROLL K_DOWN inspect_offset$   16
	KEY_SCROLL K_PGUP inspect_offset$  -16*8
	KEY_SCROLL K_PGDN inspect_offset$   16*8
	KEY_SCROLL K_LEFT inspect_segment$ -0x100
	KEY_SCROLL K_RIGHT inspect_segment$ 0x100

	cmp	al, 'r'
	jne	0f
	xor	ax, ax
	mov	[inspect_segment$], ax
	mov	[inspect_offset$], ax
	jmp	1f

0:	cmp	ax, 0x011b # escape
	jz	0f
	cmp	ax, 0x1071 # 'q'
	jz	0f
1:	mov	ah, 0x0f
	jmp	inspect$
0:	ret



.data
inspect_disksector_data$:	.space 1024
.text


inspectdrive:
	.data
	msg_inspect_drive$: .asciz "Inspect drive "
	msg_inspect_sector$: .asciz " sector "
	drive_index$: .byte 0
	sector_number$: .byte 1
	sector_offset$: .word 0
	.text
#	cmp	byte ptr [drive_numbers+1], 0
#	jnz	0f
	call	list_drives
0:
	mov	ax, 0x0a00
	call	cls
	call	print_drive_numbers
	call	newline

	mov	si, offset msg_inspect_drive$
	call	print

	xor	dh, dh

	xor	bh, bh
	mov	bl, [drive_index$]
	mov	dl, bl
	call	printhex2

	mov	dl, [drive_numbers + bx]

	call	printhex2

	mov	si, offset msg_inspect_sector$
	call	print


	push	dx
	mov	dl, [sector_number$]
	inc	ah
	call	printhex2
	pop	dx

	xor	ch, ch
	mov	cl, [sector_number$]
	mov	ax, 0x0202
	push	es
	push	bx
	mov	bx, ds
	mov	es, bx
	mov	bx, offset inspect_disksector_data$
	int	0x13
	pop	bx
	pop	es

	pushf
	mov	dx, ax
	mov	ah, 0x0f
	call	printhex
	mov	ah, 0x02
	xor	dx, dx
	popf

	jnc	0f
	inc	ah
	mov	dx, 0xfa11
0:	call	printhex


	mov	bx, offset inspect_disksector_data$ # print rel addr
	mov	si, [sector_offset$]
	mov	cx, 0x1010 # rows <<8 | columns
	mov	ah, 0x0f

#call	printregisters
	call	hexdump
#call	printregisters
.macro DEBUG_SEC_OFFS
	push	ax	# print current values (debug)
	push	dx
	push	si
	mov	ah, 0xf2
	.data
	9: .asciz "DEBUG: offset/sector "
	.text
	mov	si, offset 9b
	call	print
	mov	dx, [sector_offset$]
	call	printhex
	mov	dl, [sector_number$]
	call	printhex2
	call	newline
	pop	si
	pop	dx
	pop	ax
.endm

	call	waitkey

	DEBUG_SEC_OFFS

.macro K_S k s
	cmp	ax, \k
	jne	0f
	add	[sector_offset$], word ptr \s
	jmp	1f	# there is a change
0:
.endm

  # switch
	K_S	K_UP, -16	# up
	K_S	K_DOWN,  16	# down
	K_S	K_PGUP, -16*8	# page up
	K_S	K_PGDN,  16*8	# page down
	cmp	ax, K_ESC	#0x011b
	jz	2f
	cmp	al, 'q'
	jz	2f

	cmp	al, 'r'
	jne	0f
	mov	[sector_offset$], word ptr 0
	mov	[sector_number$], byte ptr 1
	jmp	1f

0:	cmp	ax, K_LEFT
	jne	0f
	dec	byte ptr [sector_number$]
	jmp	1f

0:	cmp	ax, K_RIGHT
	jne	0f
	inc	byte ptr [sector_number$]
	jmp	1f
0:	

1: #end of switch
	call	newline
	DEBUG_SEC_OFFS

	# [sector_offset] is adjusted; adjust other vars

	mov	ah, 0xf7
	mov	dx, [sector_offset$]
	call	printhex
	cmp	dx, 0
	jge	0f
	mov	dl, 1
	inc	ah
	jmp	1f
0:	mov	dl, -1
	dec	ah
1: 	call	printhex2




	mov	ax, [sector_offset$]
	mov	dl, [sector_number$]


	cmp	ax, 0	# if wrap back
	jge	0f
	add	ax, 512	# then advance ptr,
	dec	dl	# but seek previous sector
0:	
	cmp	ax, 1024 - 0x10*0x10 # *2 to be safe
	jbe	0f

	# offset nearing end
	sub	ax, 512
	inc	dl
0:	
	mov	[sector_offset$], ax
	mov	[sector_number$], dl

	DEBUG_SEC_OFFS

	jmp 	inspectdrive
	
2:	ret



inspectbootsector:
	mov	ah, 0xf0
	call	cls

	mov	dx, 0x0080	# dl = first HDD
	mov	cx, 1		# cylinder=0, sector = 1
	mov	ax, (2<<8) + 1	# ah = 2 read al sectors
	push	es
	mov	bx, ds
	mov	es, bx
	mov	bx, offset inspect_disksector_data$
	int	0x13
	pop	es
	jc	fail$
	mov	dx, ax
	mov	ah, 0xf0
	call	printhex 
	call	newline

	mov	si, offset inspect_disksector_data$
	mov	ah, 0xf3
	PRINT	"Sector Signature: "
	mov	dx, [si + 0x1fe]
	call	printhex

	#cmp	[si + 0x1fe], 0x55aa


	ret

fail$:	mov	dx, ax
	mov	ah, 0xf2
	PRINTLN	"Error reading bootsector: "
	call	printhex2
	ret

.data
	.rept 1024
	.asciz "Padding Data"
	.endr
.text
