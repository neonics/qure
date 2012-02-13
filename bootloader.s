.intel_syntax noprefix

# Layout:
# 0000-0200: sector 0. Only .text/.bss used. subsections/.data prohibited.
# 0200-....: all allowed.

.text
.code16
.global start
start:
	cli

	# set up ds, es, ss
	push	dx
	push	ax
	push	ds
	call	1f
1:	pop	ax
	sub	ax, 1b - start
	push	ax
	shr	ax, 4
	mov	ds, ax

	mov	[r_cs], cs
	pop	[r_ip]
	pop	[r_ds]
	mov	[r_es], es
	mov	[r_fs], fs
	mov	[r_gs], gs
	mov	[r_ss], ss

	pop	[r_ax]
	mov	[r_bx], bx
	mov	[r_cx], cx
	pop	[r_dx]
	mov	[r_si], si
	mov	[r_di], di
	mov	[r_bp], bp
	mov	[r_sp], sp


	mov	ax, 0xf000
	call	cls	# side effect: set up es:di to b800:0000

      printhello$:
	inc	ah
	mov	si, offset hello$
	call	print
	mov	dx, ds
	call	print

	inc	ah
	call	printregisters


.equ LIST_DRIVES, 1
.if LIST_DRIVES
	inc	ah
	call	listdrives$
	call	printbootdrive$
.endif


/*
loadsector:
	push	ax
	push	es
	mov	ax, 0x0201
	mov	cx, 0x0001
	mov	dx, [r_dx]
	mov	bx, ds
	mov	es, bx
	mov	bx, [r_ip]
	add	bx, 512


	pop	es
	pop	ax


	#xor	ax, ax
	#mov	ss, ax
*/

	mov	dx, 0xf0f0
	call	printhex
	call	writebootsector
	mov	dx, 0x0f0f
	call	printhex

halt:	hlt
	jmp	halt

.include "print.s"


.if LIST_DRIVES
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
	ret

msg_disk_error$: .asciz "DiskERR "
print_drive_info:

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
	ret

txt_drive$:	.asciz "Drive "
printbootdrive$:
	mov	si, offset txt_drive$;
	call	print

	mov	al, [r_dx]
	test	al, 0x80
	jz	0f
	and	al, 0x7f
	add	al, 'C'
	jmp	1f
0:	add	al, 'A'
1:	stosw
	call	newline

.endif

.EQU bs_code_end, .

data:
	hello$: .asciz "Hello!"

. = 440
	.ascii "MBR$"
. = 446
	mbr:
	status$:	.byte 0x80	# bootable
	chs_start$:	.byte 0, 1, 0	# head, sector, cylinder
	part_type$:	.byte 0		# partition type
	chs_end$:	.byte 0, 1, 0
	lba_first$:	.byte 0, 0, 0, 0
	numsec$:	.byte 0,0,0,0
. = 512 - 2
	.byte 0x55, 0xaa
#end:


#############################################################################
# .text d0 is offset 512
# .code is before that, and should not be used from this point on.
#
#############################################################################
# Problem: .text is contiguous, .text d0 follows it.
# need to reset .text segment to start at 512, and .text d0 to follow that.
# use other name for text segment. 

.text
. = 512

.equ BIG_BOOTSECT, 1
.if BIG_BOOTSECT


msg_bootsect_written$: .asciz "Bootsector Written"
writebootsector:
	mov	dx, 0xa0a0
	mov	ah, 0xf0
	call	printhex
	#ignored.. and yet without it it doesnt work..
	#ret
	nop


	mov	dx, 0x0080	# dl = first HDD
	call	printhex
	xor	ah, ah		# reset
	int	0x13
	jnc	0f
	mov	si, offset msg_disk_error$
	call	print
0:	mov	dl, ah
	mov	ah, 0xf7
	call	printhex2


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
	xor	cx, cx 		# cylinder=0, sector = 0
	mov	ax, 0x0301	# write 1 sector
	mov	bx, [r_ip]
	int	0x13
	pop	es
	pushf
	pusha
	call	printregisters2;
	popa
	mov	dx, ax
	mov	ah, 0xf0
	call	printhex 
	popf
	mov	si, offset msg_disk_error$
	jc	0f
	inc	ah
	mov	si, offset msg_bootsect_written$
0:	inc	ah
	call	print

	ret


.endif





printregisters2:
	pushf
	pusha
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	call	newline


	mov	si, offset regnames$
	mov	bx, sp
	mov	ah, 0xf3
	mov	cx, 17
	mov	dx, cx
	call	printhex

0:	lodsb
	stosw
	lodsb
	stosw

	mov	al, ':'
	stosw

	mov	dx, ss:[bx]
	add	bx, 2
	call	printhex
	cmp	cx, 10
	jne	1f
	call	newline
1:

	loopnz	0b

	call	newline

	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popa
	popf
	ret
