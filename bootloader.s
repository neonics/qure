.intel_syntax noprefix

# Layout:
# 0000-0200: sector 0. Only .text/.bss used. subsections/.data prohibited.
# 0200-....: all allowed.

.bss
.equ BSS_START, .
# appended at end; at current references are not relocated, so segment
# register gs is holding an address.
# Even forward referencing the END_CODE here is not supported by gas,
# and so a constant is required here.
# First: implement using gs: for bss. Use stack, to be safe, as it is
# supposed to be BEFORE the start:.
.text
.code16
black:	# ss:sp points to the end of the first sector.
	# backup sp
	#mov	sp, 512	# make it so, regardless of bios
	call	0f
0:	pop	sp
	and	sp, ~15
	add	sp, 0x2000
	call	1f
0:	hlt
	jmp	0b

regnames$:
.ascii "cs"	# 0
.ascii "ds"	# 2
.ascii "es"	# 4
.ascii "fs"	# 6
.ascii "gs"	# 8
.ascii "ss"	# 10

.ascii "fl"	# 12

.ascii "di"	# 14
.ascii "si"	# 16
.ascii "bp"	# 18
.ascii "sp"	# 20
.ascii "bx"	# 22
.ascii "dx"	# 24
.ascii "cx"	# 26
.ascii "ax"	# 28
.ascii "ip"	# 30

.ascii "c.p.a.zstidoppn."

1:
# result:
# 1337
# FA11
# cs:0000 ds:0000 fs:0000 gs:0000 ss:0000 fl:0206
# di:7BE0 si:000E bp:0000 sp:7BFE bx:00E0 dx:00E0 cx:0100 ax:AA55 ip:7C03

# cs:ip = 0:7C03
# ds = (ip - 3 ) >> 4
# sp runs into the code, end of segment
# 
	# use the value on stack as ip register
	pusha
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# set up ds for lodsb, do not assume loaded at 0x7c00
	mov	bp, sp 
	mov	bx, ss:[bp + 30]	# load ip
	sub	bx, 0b - black		# adjust start
	mov	ss:[bp + 30], bx	# restore
	shr	bx, 4			# convert to segment
	mov	ds, bx
	# now, offsets are relative to the code. This requires that no base
	# address (or 0) is specified when creating the binary.

	# restore startaddress:
	mov	word ptr [startaddress], 0x55aa  # TODO: CHECK

	# assume nothing
	push	0xb800		# set up screen
	pop	es
	xor	di, di
	mov	ah, 0x0f
	mov	dx, 0x1337	# test screen
	call	printhex

	call	newline
	mov	bx, sp
	inc	ah
	sar	ah, 1 	# color

	mov	si, offset regnames$
	mov	cx, 16	# 6 seg 9 gu 1 flags 1 ip

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
1: 	loopnz	0b

	call	newline

.if 1	
	jmp	white	# keep registers on stack
.else
	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popa
	ret
.endif

printregisters:
	pusha
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# assume es:di is valid

	call	newline
	mov	bx, sp

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
.if 0
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
.endif

	call	newline

1: 	loopnz	0b

	call	newline

	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popf
.if 0
	mov	[tmp_di$], di
	popa
	mov	di, [tmp_di$]
	ret
tmp_di$: .word 0
.else
	pop	ax	# manual pop to preserve di
	pop	si
	pop	bp
	pop	ax	# ignore sp
	pop	bx
	pop	dx
	pop	cx
	pop	ax
	ret
.endif

# stack setup at 0:0x9c00
# sp is 32 bytes below that, pointing to the registers starting
# with ip, the return address of the 1337 loader, which then simply
# halts.
white: 	
	cli

	# bp = sp = saved registers ( 9BE0; top: 9C00 = 7C00 + 2000 )

	mov	ax, 0xf000
	call	cls	# side effect: set up es:di to b800:0000

      printhello$:
	inc	ah
	mov	si, offset hello$
	call	print

.if 0
	mov	ah, 0xf4

	mov	dx, sp
	call	printhex
	mov	dx, bp
	call	printhex

	mov	dx, offset CODE_SIZE	# 268h
	call	printhex
	mov	dx, BSS_SIZE		# E8
	call	printhex

     rainbow$:
	call	newline
	mov	ax, 0x00 << 8 | 254
	mov	cx, 4
1:	push	cx
	mov	cx, 256 / 4
0:	stosw
	inc	ah
	loop	0b
	pop	cx
	call	newline
	loop	1b
.endif

	mov	ah, 0xf8
	
	mov	dx, 0x1337
	call	printhex

	call	printregisters

	mov	dx, [bp+24]	# load dx - boot drive
	#call	printhex

preparereadsector$:
	# reset drive, retry loop
	mov	cx, 3
0:	xor	ah, ah
	int	0x13
	jnc	0f
	loop	0b
0:

	# setup es:bx
	push	es

	push	ds
	pop	es	
	mov	bx, 512	

	# calculate nr of sectors to load
.equ LOADBYTES, CODE_SIZE - sector1
.equ PARTIALSECTOR, (LOADBYTES & 0x1ff > 0) * -1	
.equ SECTORS, (LOADBYTES >> 9) + PARTIALSECTOR
loadsectors$:
	mov	ax, (2 << 8) + SECTORS	# ah = 02 read sectors al = # sectors
	mov	cx, 0x0002	# cyl 0, sector 2! offset 200h in img
	xor	dh, dh		# head 0
	int	0x13		# load sector to es:bx

	pop	es

	jc	fail

	mov	dx, ax
	mov	ah, 0xf6
	call	printhex

.if 0	# dump sector 1
	inc	ah
	mov	si, offset sector1
	mov	cx, 8
0:	mov	dx, ds:[si]
	call	printhex
	add	si, 2
	loop	0b
.endif

	jmp 	sector1

halt:	hlt
	jmp	halt

fail:	mov	bx, ax		# save bios int result code
	mov	ah, 0xf4
	mov	dx, 0xfa11
	call	printhex
	mov	ah, 0xf2
	mov	dx, bx
	call	printhex
	call	printregisters

.include "print.s"







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
startaddress:	.byte 0x55, 0xaa	# the value is required during boot,
					# and with VirtualBox the first push
					# will overwrite this value.
					# ax contains aa55 already,
					# so restore to make writebootsect
					# work.
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

.data
msg_sector1$: .asciz "Exceeded sector limitation!"
.text
sector1:
	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	print
	call	newline


## XXX not called as yet!
	# set up gs for .bss
	sub	sp, offset BSS_SIZE # not an offset but otherwise [..]
	mov	ax, sp
	shr	ax, 4
	mov	gs, ax	# gs:.bss: (un)allocated uninitialized (zeroed) space


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

#	call	writebootsector

	jmp	halt


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

.endif



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

.equ CODE_SIZE, .
.bss
.equ BSS_SIZE, .
