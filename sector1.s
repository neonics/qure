# included in bootloader.s
.intel_syntax noprefix
.text
. = 512

.data
msg_sector1$: .asciz "Transcended sector limitation!"
.text
	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	println

	mov	dx, 0x1337
	call	printhex

	# set up gs for .bss
	#sub	sp, offset BSS_SIZE # not an offset but otherwise [..]
	#mov	ax, sp
	#shr	ax, 4
	#mov	gs, ax	# gs:.bss: (un)allocated uninitialized (zeroed) space

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
.endif


#	call	writebootsector
	call	waitkey

	#call	gfxmode
	call	protected_mode
	#call	real_to_prot
.code32
	mov	edi, 0xb8000
	mov	ax, 0x0820
	mov	cx, 80*25
	rep	stosw

	jmp	halt

.code16
.include "realmode.S"
.intel_syntax noprefix
.code16

msg_press_key: .asciz "Press a key to continue..."
.byte 0
waitkey:
	mov	si, offset msg_press_key

	call	print
	xor	ah, ah
	int	0x16
	stosw
	call	newline
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
	push	es
	mov	bx, ds
	mov	es, bx

	/*
.bss
	diskformat_buf$: .space 512
.text c1
	mov	di, offset diskformat_buf$
	mov	cx, 512
	xor	ax, ax
	rep	stosw
	// call int 13h format sector
	*/

	#mov	ax, 0x0500	# format

	mov	dx, 0x0080	# dl = first HDD
	mov	cx, 1		# cylinder=0, sector = 1
	mov	ax, (3<<8) + SECTORS +1 # ah = 3 write al sectors
	mov	bx, ss:[bp + 30 ]
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

.include "pmode.s"
.include "gfxmode.s"
