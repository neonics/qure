.intel_syntax noprefix

.data
#.align 2, 0x90, 1
data:

.data 
regnames$: .asciz "csipdsesfsgsssaxbxcxdxsidibpsp"

.bss
#.offset -0x10
. = 512
registers$:
r_cs: .word 0
r_ip: .word 0
r_ds: .word 0
r_es: .word 0
r_fs: .word 0
r_gs: .word 0
r_ss: .word 0

r_ax: .word 0
r_bx: .word 0
r_cx: .word 0
r_dx: .word 0
r_si: .word 0
r_di: .word 0
r_bp: .word 0
r_sp: .word 0
bss_end$:

/*
r_cs: .word 0
r_ip: .word 0
r_ds: .word 0
r_es: .word 0
r_fs: .word 0
r_gs: .word 0
r_ss: .word 0

r_ax: .word 0
r_bx: .word 0
r_cx: .word 0
r_dx: .word 0
r_si: .word 0
r_di: .word 0
r_bp: .word 0
r_sp: .word 0
*/
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

.if 0
savecursor$:
.bss
	cursor: .word 0
	cursor_form: .word 0
.text
	mov	ah, 3
	mov	bh, 0
	int	0x10
	mov	[cursor_form], cx
	# hide cursor
	mov	ah, 1
	mov	cx, 0x2706
	int	0x10
.endif
	mov	ax, 0xf000
	call	cls


printhello$:
.data
	hello$: .asciz "Hello!"
.text
	inc	ah
	mov	si, offset hello$
	call	print

	inc	ah
	call	printregisters
	inc	ah


.equ LIST_DRIVES, 1
.if LIST_DRIVES
	call	listdrives$
.endif

# detect boot medium


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


writebootsector:
.data
msg_bootsect_written: .asciz "Bootsect Written"
.text
	push	ax
	mov	ax, 0x0301	# func 3, 1 sectors
	xor	cx, cx 		# cylinder=0, sector = 0
	mov	dx, 0x0080	# dl = first HDD
	push	es
	mov	bx, ds
	mov	es, bx
	mov	bx, [r_ip]
	int	0x13
	pop	es
	mov	dx, ax
	pop	ax
	call	printhex 
	#mov	si, offset msg_disk_error
	jc	0f
	#inc	ah
	#mov	si, offset msg_bootsect_written
0:	#inc	ah
	#call	print

halt:	hlt
	jmp	halt


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

print_drive_info:
.data
msg_disk_error: .asciz "DiskERR "
.text
	push	dx
	call	printhex2
	push	ax
	push	es
	push	di
	mov	ah, 8
	xor	bh, bh
	xor	di,di
	mov	es,di
	int	0x13
	jnc 	0f
	inc	bh
0:	mov	bp, es
	mov	fs, bp
	mov	bp, di
	pop	di
	pop	es
	mov	gs, ax
	pop	ax

	or	bh, bh
	jz 	0f
	mov	si, offset msg_disk_error
	inc	ah
	call	print
	dec	ah
0:	call	printhex # dx
	mov	dx, gs # ax
	call	printhex
	mov	dx, bx
	call	printhex2
	mov	dx, cx
	call	printhex
	mov	dx, fs
	call	printhex
	mov	byte ptr es:[di-2],':'
	mov	dx, bp
	call	printhex
	
	call	newline
	pop	dx
	ret
.endif


# arg: es:di screen ptr
# arg: ax: number
# uses: ax, dx, di

# arg: dx
printhex2:
	push	cx
	push	dx
	mov	cx, 2
	shl	dx, 8
	jmp	0f
printhex:
	push	cx
	push	dx
	mov	cx, 4
0:	rol	dx, 4
	mov	al, dl
	and	al, 0xf
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b

	add	di, 2
	pop	dx
	pop	cx
	ret
	
newline:
	push	ax
	push	dx
	mov	ax, di
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	di, ax
	pop	dx
	pop	ax
	ret


print:
	lodsb
0:	stosw
	lodsb
	test	al, al
	jnz	0b
	ret


printregisters:
	mov	si, offset regnames$
	mov	bx, offset registers$
1:	call	newline
0:
	lodsb
	or	al, al
	jz	0f
	stosw
	lodsb
	stosw
	mov	al, ':'
	stosw
	mov	dx, [bx]
	add	bx, 2
	call	printhex

	cmp	bx, offset r_ss
	jz	1b

	jmp	0b
0:	call	newline
	ret

cls:
	mov	di, 0xb800
	mov	es, di
	xor	di, di
	mov	cx, 80 * 25 # 7f0
	rep	stosw
	xor	di, di
	ret

# if include: todo: check if link-order for multiple .s files can be specified in as
#.include "print.s"

.data 1
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
end:
