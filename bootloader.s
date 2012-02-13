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
start:	# assume ss:sp has 32 free bytes
	call	printregisters
0:	jmp	halt

printregisters:
# result:
# 1337
# FA11 cs:0000 ds:0000 fs:0000 gs:0000 ss:0000 ax:7BE0
# cx:000E dx:0000 bx:7BFC sp:00E0 bp:00E0 si:0100 di:AA55 fl:0206 ip:7C03

# cs:ip = 0:7C03
# ds = (ip - 3 ) >> 4
# 
	# use the value on stack as ip register
	pushf
	pusha
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# assume nothing
	push	0xb800		# set up screen
	pop	es
	xor	di, di
	mov	ah, 0x0f
	mov	dx, 0x1337	# test screen
	call	printhex

	# set up ds for lodsb
	mov	bp, sp 
	mov	bx, ss:[bp + 30]	# load ip
	sub	bx, 0b - start		# adjust start
	shr	bx, 4			# convert to segment
	mov	ds, bx

	call	newline
	mov	dx, 0xfa11
	call	printhex

	call	newline
	mov	bx, sp
	mov	ax, 0x0800 # ah color, al = 0: pop stack

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

	cmp	cx, 11
	jne	1f
	call	newline
1: 	loopnz	0b

	call	newline

	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popa
	popf
0:	ret



	cli

	# start state:
	# all segment registers are zero.
	# stack pointer is 100h. seems wrong.
	

	# set up ds, es, ss
	push	sp	# strange loop
	push	dx
	push	ax
	push	ds
	call	1f	#
1:	pop	ax	#
	push	ax
	# stack: ip@start ds ax dx sp

	sub	ax, 1b - start
	shr	ax, 4	# ds used for data references due to nonrelocation support; require use of 'lodsb' (no locsb? check register encoding in opcode)
	mov	ds, ax

	sub	sp, BSS_SIZE
	mov	ax, sp
	shr	ax, 4
	mov	gs, ax	# gs:.bss: (un)allocated uninitialized (zeroed) space

	mov	gs:[r_cs], cs
	pop	gs:[r_ip]	# check ip@start
	pop	gs:[r_ds]	# check ds
	mov	gs:[r_es], es
	mov	gs:[r_fs], fs
	mov	gs:[r_gs], gs
	mov	gs:[r_ss], ss

	pop	gs:[r_ax]	# check ax
	mov	gs:[r_bx], bx
	mov	gs:[r_cx], cx
	pop	gs:[r_dx]	# check dx
	mov	gs:[r_si], si
	mov	gs:[r_di], di
	mov	gs:[r_bp], bp
	pop	gs:[r_sp] 	# strange loop mirror


	mov	ax, 0xf000
	call	cls	# side effect: set up es:di to b800:0000

      printhello$:
	inc	ah
	mov	si, offset hello$
	call	print
	mov	dx, ds
	call	printhex
	mov	dx, ss
	mov	dx, BSS_SIZE
	call	printhex

	mov	dx, gs
	call	printhex
	mov	dx, offset r_cx
	call	printhex
	mov	dx, offset CODE_SIZE
	call	printhex

	inc	ah
	call	printregisters


.equ LIST_DRIVES, 0
.if LIST_DRIVES
	inc	ah
	call	listdrives$
	call	printbootdrive$
.endif

	mov	dx, 0xf001
	call	printhex

	push	es

	push	ds
	pop	es	

	mov	bx, 512	
/*
loadsector:
	mov	ax, 0x0201	# ah = 02 read sectors al = 1 sector
	xor	dh, dh		# head 0
	int	0x13		# load sector to es:bx
	mov	dx, ax		# save result; cf=1 err; ah=11:cl=burst,
	pop	ax


	pop	es
	call	printhex
*/

	#xor	ax, ax
	#mov	ss, ax
/*
	mov	dx, 0xf0f0
	call	printhex
	call	writebootsector
	mov	dx, 0x0f0f
	call	printhex
*/
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
	mov	bx, gs:[r_ip]
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


.equ CODE_SIZE, .
.bss
.equ BSS_SIZE, .
