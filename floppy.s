.intel_syntax noprefix

.text
#.code32 # pmode

.equ FLOPPY_CONTROLLER_BASE, 0x3f0
.equ FLOPPY_CONTROLLER_IRQ, 6
.equ FLOPPY_CONTROLLER_DMA_CHANNEL, 2

.equ FLOPPY_REGISTER_DOR, 2	# digital output
.equ FLOPPY_REGISTER_MSR, 4	# master status (ro)
.equ FLOPPY_REGISTER_FIFO, 5	# data fifo dma
.equ FLOPPY_REGISTER_CCR, 7	# configuration control (w)

.equ FLOPPY_COMMAND_SPECIFY, 3
.equ FLOPPY_COMMAND_WRITE_DATA, 5
.equ FLOPPY_COMMAND_READ_DATA, 6
.equ FLOPPY_COMMAND_RECALIBRATE, 7
.equ FLOPPY_COMMAND_SENSE_INTERRUPT, 8
.equ FLOPPY_COMMAND_SEEK, 15


.data
msg_floppy$:	.asciz "Floppy "
msg_floppies$:	.asciz "none   "
		.asciz "360kb  "
		.asciz "1.2Mb  "
		.asciz "720kb  "
		.asciz "1.44Mb "
		.asciz "2.88Mb "
		.asciz "unknown"
0:		.asciz "unknown"
.equ floppy_entry_size$, . - 0b

.text

list_floppies:
	push	si
	push	bx
	push	di
	push	dx

	mov	al, 0x10 # get installed floppies
	out	0x70, al
	in	al, 0x71	# at current returns 0x00 - no floppies
	and	al, 0x77	# mask out > 7
	xor	bh, bh
	mov	bl, al
	ror	bx, 4

	mov	dl, al
	call	printhex2

	mov	ch, ah	# backup color
	mov	cl, '0'
0:
	mov	si, offset msg_floppy$
	call	print
	mov	al, cl
	stosw
	mov	dl, bl
	call	printhex2

	mov	al, floppy_entry_size$
	mul	bl
	mov	si, offset msg_floppies$
	add	si, ax
	mov	ah, ch
	call	print
	call	newline

	rol	bx, 4
	and	bl, 15

#	inc	cl
#	cmp	cl, '1'
#	jle	0b

	mov	ah, 0xf0

	pop	dx
	pop	di
	pop	bx
	pop	si
	ret
