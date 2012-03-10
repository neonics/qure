.intel_syntax noprefix


.data
low_memory_size: .word 0 # in kb
memory_map:	.space 24
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

	rmI "CS:IP "
	mov	dx, ax
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

	##############################################
	# some last-minute realmode data gathering

	call	newline_16
	print_16 "Low mem size: "
	xor	ax, ax
	int	0x12	# get low memory size
	jc	1f
	or	ax, ax
	jnz	0f
1:	rmCOLOR 4
	print_16 "Can't get lo-mem size"
	rmCOLOR 7
	jmp	1f
0:	mov	[low_memory_size], ax
	xor	edx, edx
	mov	dx, ax
	call	printhex_16
	print_16 "kb / 0x"
	shl	edx, 10
	call	printhex8_16
1:
	call	newline_16

	print_16 "High memory Map:"
	call	newline_16

	rmCOLOR 7
	print_16 "Base:              | Length:             | Region Type| Attributes"
	call	newline_16
	rmCOLOR 8

	xor	ebx, ebx
0:	mov	edx, 0x534d4150
	mov	eax, 0xe820
	mov	ecx, 24
	mov	di, ds
	mov	es, di
	mov	di, offset memory_map
	int	0x15
	jc	0f
	cmp	eax, 0x534d4150
	jne	0f
	or	ebx, ebx
	jz	1f
	cmp	cl, 24
	jae	2f
	mov	es:[di+20], dword ptr 1	# ACPI compliant
2:
	# qword base
	mov	edx, es:[di + 4]
	call	printhex8_16
	mov	edx, es:[di]
	call	printhex8_16
	add	di, 8
	rmCOLOR 1
	print_16 " |  "
	rmCOLOR 8
	# qword length
	mov	edx, es:[di+4]
	call	printhex8_16
	mov	edx, es:[di]
	call	printhex8_16
	add	di, 8
	rmCOLOR 1
	print_16 " |  "
	rmCOLOR 8
	# dword region type
	# 1 = usable ram
	# 2 = reserved
	# 3 = acpi reclaimable
	# 4 = acpi nvs 
	# 5 = bad memory
	mov	edx, es:[di]
	add	di, 4
	call	printhex8_16
	rmCOLOR 1
	print_16 " |  "
	rmCOLOR 8
	# dword ACPI 3.0 attributes
	mov	edx, es:[di]
	add	di, 4
	call	printhex2_16
	call	newline_16

	jmp	0b
#	jmp	1f

0:	rmCOLOR 12
	print_16 "int 0x15 error: eax="
	mov	edx, eax
	rmCOLOR 4
	call	printhex8_16
1:	rmCOLOR 7


	print_16 "Press a key to continue.."
	xor	ah,ah
	int	0x16
	call	newline_16

	###############################
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

	rmCOLOR	11
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

