# included in bootloader.s
.intel_syntax noprefix
.text
. = 512

.data
msg_sector1$: .asciz "Transcended sector limitation!"
msg_entering_pmode$: .asciz "Entering Protected Mode"
.text
	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	println

	mov	dx, 0x1337
	call	printhex

	call	waitkey

.if 0
	mov	ah, 0xf2
listdrives$:

	mov	dx, 0
0:	call	print_drive_info
	inc	dl
	cmp	dl, 4
	jl	0b

	mov	dl, 0x80
0:	call	print_drive_info
	inc	dl
	cmp	dl, 0x84
	jl	0b

	#call	writebootsector
.endif

###################################################

#.include "floppy.s"

###################################################
	mov	ax, 0x0f00
	call	cls
	mov	dx, 0x1337
	call	printhex

.equ INSPECT_SECTOR, 0
.if INSPECT_SECTOR
.data
msg_inspect$: .asciz "Inspect sector "
sector_number$: .byte 1
sector_offset$: .word 0
sector_data$: .space 1024

.text

# scan keycodes...
#0:	call	waitkey
#	jmp	0b

#	call	inspectmem


inspectsector:
	xor	di, di
	mov	ax, 0x0a00

	mov	si, offset msg_inspect$
	call	print

	mov	dl, [sector_number$]
	inc	ah
	call	printhex2


	mov	dx, 0x80
	xor	ch, ch
	mov	cl, [sector_number$]
	mov	ax, 0x0202
	push	es
	push	bx
	mov	bx, ds
	mov	es, bx
	mov	bx, offset sector_data$
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


	mov	bx, offset sector_data$ # print rel addr
	mov	si, [sector_offset$]
	mov	cx, 0x1010 # rows <<8 | columns
	mov	ah, 0x0f

	call	hexdump

mov	ah, 0xf4
mov	dx, 0xfa11
call	printhex
	call	waitkey

.macro K_S k s
	cmp	ax, offset \k
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
	cmp	ax, offset K_ESCAPE	#0x011b
	jz	2f

	cmp	al, 'r'
	jne	0f
	mov	[sector_offset$], word ptr 0
	mov	[sector_number$], byte ptr 1
	jmp	1f

0:	cmp	ax, offset K_LEFT
	jne	0f
	dec	byte ptr [sector_number$]
	jmp	1f

0:	cmp	ax, offset K_RIGHT
	jne	0f
	inc	byte ptr [sector_number$]
	jmp	1f
0:	

	# fallthough
	# no change but check anyway
1: #end of switch
.macro DEBUG_SEC_OFFS
	push	ax	# print current values (debug)
	push	dx
	push	si
	mov	ah, 7
	.data
	9: .asciz "DEBUG: offset/sector "
	.text
	mov	si, offset 9b
	mov	dx, [sector_offset$]
	call	printhex
	mov	dx, [sector_number$]
	call	printhex2
	call	newline
	pop	si
	pop	dx
	pop	ax
.endm
	DEBUG_SEC_OFFS

	# [sector_offset] is adjusted; adjust other vars
	mov	ax, [sector_offset$]
	mov	dl, [sector_number$]

	cmp	ax, 0	# if wrap back
	jge	0f
	add	ax, 512	# then advance ptr,
	dec	dl	# but seek previous sector
	jmp	0f
0:	
	cmp	ax, 1024 - 0x10*0x10*2 # *2 to be safe
	jle	0f
	# offset nearing end
	sub	ax, 512
	inc	dl
0:	mov	[sector_offset$], ax
	mov	[sector_number$], dl

	DEBUG_SEC_OFFS

	jmp 	inspectsector
	
2:

.endif
	#call	inspectmem


###################################################
	call	waitkey

	mov	si, offset msg_entering_pmode$
	call	println


	#call	gfxmode
	call	protected_mode
	#call	real_to_prot
.data
msg_realmode$: .asciz "back in real mode"
.text
.code16
	mov	ah, 0xf2
	mov	di, 160
	mov	si, offset msg_realmode$
	call	print

	jmp	halt

#####################################################

.code16
.include "print32.s"
.include "pmode.s"
.include "gfxmode.s"

.code16

msg_press_key: .asciz "Press a key to continue..."
.include "keycodes.s"
waitkey:
	push	si
	push	dx

	mov	si, offset msg_press_key
	call	print
	xor	ah, ah
	int	0x16
	stosw
	push	ax
	mov	dx, ax
	#add	di, 2
	call	printhex
	call	newline
	pop	ax

	pop	dx
	pop	si
	ret


debug_str: # expect si, ah # destroy dx, al, si # update di
	mov	dx, si
	call	printhex
.if 0
0:	lodsb
	or	al, al
	jz	0f
	stosw
	mov	dl, al
	call	printhex2
	jmp 	0b
0:	call	newline
	ret
.endif


msg_disk_error$: .asciz "DiskERR "
print_drive_info:
	push	bp
	push	dx	
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
			# dh: heads dl: harddisks
0:	call	printhex
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
	
	call	newline
	pop	dx
	pop	bp
	ret

txt_drive$:	.asciz "Drive "
printbootdrive$:
	mov	si, offset txt_drive$;
	call	print

	mov	al, gs:[r_dx]
	test	al, 0x80
	jz	0f
	and	al, 0x7f
	add	al, 'C'
	jmp	1f
0:	add	al, 'A'
1:	stosw
	call	newline
	ret


.data
msg_bootsect_written$: .asciz "Bootsector Written"
.text
writebootsector:

	/*
.bss
	diskformat_buf$: .space 512
.text c1
	mov	di, offset diskformat_buf$
	mov	cx, 512
	xor	ax, ax
	rep	stosw
	// call int 13h format sector

	jmp 1f
fmt_buf: .space 512
1:
	push	es
	mov	bx, ds
	mov	es, bx

	push di
	mov	cx, 256
	xor	ax, ax
0:	stosw
	inc	ah
	loop	0b
	pop di

	mov	dx, 0x80
	xor	cx, cx
	mov	ax, 0x0500	# format
	mov	bx, offset fmt_buf
	int	0x13
	pop	es
	jc fail


	*/



	mov	dx, 0x0080	# dl = first HDD
	mov	cx, 1		# cylinder=0, sector = 1
	mov	ax, (3<<8) + 1 #SECTORS +1 # ah = 3 write al sectors
	push	es
	mov	bx, ds
	mov	es, bx

	mov	bx, ss:[bp + 30 ]
	int	0x13
	pop	es
	jc	fail

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
	jc	fail

	mov	dx, ax
	mov	ah, 0xf0
	call	printhex 



	mov	si, offset msg_bootsect_written$
	call	print
	ret


# todo: scrolling in newline
# todo: replace cls, print*, newline with functions preserving es:di


# menu uses in textmode:
# - list vesa video modes
# - list drives to install
# - browse ramdisk
# expect es:di at line start
menu:	ret


# in: 
# ah: color
# bx: relative offset: 0: display absolute (si); other: display relative to bx
# cx: ch = lines, cl = columns; cl*ch = total bytes dumped
# dx: bottom limit: 0 for no limit
# ds:si data to dump
hexdump:
.data
	msg_dump$: .asciz "Dump: "
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

	mov	ah, 0x07
	push	si
	mov	si, offset msg_dump$
	call	print
	pop	si

	inc	ah
	
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
	mov	byte ptr [di-2],':'

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


.data
msg_inspectmem$: .asciz "Inspect memory "
inspect_offset$: .word 0
.text
inspectmem:
	mov	bx, ss:[bp + 30]
	mov	[inspect_offset$], bx
inspect$:
	xor	di, di
	mov	ax, 0x0800

	mov	si, offset msg_inspectmem$
	call	print
	mov	si, [inspect_offset$]
	mov	dx, si
	call	printhex
	push	ds
	push	word ptr 0
	pop	ds
	mov	cx, 0x1010
	xor	bx, bx # print abs addr
	xor	dx, dx # nolimit
	call	hexdump
	pop	ds

	call	waitkey

.macro KEY_SCROLL key scroll
	cmp	ax, \key
	jne	0f
	add	[inspect_offset$], word ptr \scroll
	jmp	1f
0:
.endm

	KEY_SCROLL 0x4800, -16		# up
	KEY_SCROLL 0x5000,  16		# down
	KEY_SCROLL 0x4900, -16*8	# page up
	KEY_SCROLL 0x5100,  16*8	# page down

1:	cmp	ax, 0x011b # escape
	jz	0f
	cmp	ax, 0x1071 # 'q'
	jz	0f
	mov	ah, 0x0f
	jmp	inspect$
0:
	ret


