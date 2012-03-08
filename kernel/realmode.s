.intel_syntax noprefix

.text
.code16

realmode_kernel_entry:
	mov	ax, 0x0f00
	xor	di, di
	mov	cx, 160*25
	rep	stosd
	xor	di, di
	mov	al, '!'
	stosw

	mov	ax, cs
	mov	ds, ax

####### print hello

	println_16 "Kernel booting"

	print_16 "CS:IP "
	mov	dx, ax
	mov	ah, 0xf2
	call	printhex_16
	call	0f
0:	pop	dx
	sub	dx, offset 0b
	call	printhex_16

	print_16 "Kernel Size: "
	mov	edx, KERNEL_SIZE - kmain
	call	printhex8_16

	# print signature
	print_16 "Signature: "
	mov	edx, [sig] # [KERNEL_SIZE - 4]
	rmCOLOR	0x0b
	call	printhex8_16
	rmCOLOR	0x0f
	call	newline_16

.if 0
	mov	cx, 21
	mov	bx, offset kmain
0:	mov	dx, bx
	rmCOLOR	0x07
	call	printhex_16
	rmCOLOR	0x08
	mov	edx, [bx]
	call	printhex8_16
	call	newline_16
	add	bx, 0x200
	loop	0b
.endif

####### enter protected mode

	println_16 "Entering protected mode"
	mov	ax, 0

	# make it return elsewhere
	push	word ptr offset kmain
	jmp	protected_mode



################################
#### Console/Print #############
################################
#### 16 bit debug functions ####
printhex_16:
	push	ecx
	mov	ecx, 4
	rol	edx, 16
	jmp	1f
printhex2_16:
	push	ecx
	mov	ecx, 2
	rol	edx, 24
	jmp	1f
printhex8_16:
	push	ecx
	mov	ecx, 8
1:	PRINT_START_16
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	add	di, 2
	PRINT_END_16
	pop	ecx
	ret

newline_16:
	push	ax
	push	dx
	mov	ax, [screen_pos]
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	[screen_pos], ax
	pop	dx
	pop	ax
	ret

print_16:
	PRINT_START_16
0:	lodsb
	or	al, al
	jz	1f
	stosw
	jmp	0b
1:	PRINT_END_16
	ret

