##############################################################################
# Realmode Kernel Entry
#
# Performs last-minute realmode tasks before entering protected mode.
.intel_syntax noprefix

DEBUG_KERNEL_REALMODE = 0	# 1: require keystrokes at certain points


# When the protected-mode part of the kernel returns to realmode,
# it will transfer control back to it's caller, which is tpically
# the bootloader. Setting this to 1 will cause the transfer to the caller
# to be indirect. It will insert a realmode-code address in the return stack.
CHAIN_RETURN_RM_KERNEL = 1
#########################################################

.macro PRINT_START_16
	push	es
	push	di
	push	ax
	mov	di, 0xb800
	mov	es, di
	mov	di, [screen_pos]
	mov	ah, [screen_color]
.endm

.macro PRINT_END_16
	mov	[screen_pos], di
	pop	ax
	pop	di
	pop	es	
.endm


.macro PRINT_16 m
	# need to declare realmode strings in .text as kernel .text shifts
	# data beyond 64kb reach.
	jmp	98f
	99:.asciz "\m"
	98:
	push	si
	mov	si, offset 99b
	call	print_16
	pop	si
.endm

.macro PRINTc_16 c, m
	push	word ptr [screen_color]
	mov	[screen_color], byte ptr \c
	PRINT_16 "\m"
	pop	word ptr [screen_color]
.endm


.macro PRINTLN_16 m
	PRINT_16 "\m"
	call	newline_16
.endm

.macro PRINTLNc_16 c, m
	PRINTc_16 \c, "\m"
	call	newline_16
.endm

.macro PH8_16 m x
	PRINT_16 "\m"
	.if \x != edx
	push	edx
	mov	edx, \x
	call	printhex8_16
	pop	edx
	.else
	call	printhex8_16
	.endif
.endm


.macro rmCOLOR c
	mov	[screen_color], byte ptr \c
.endm


.macro rmD a b
	PRINT_START_16
	mov	ax, (\a << 8 ) + \b
	stosw
	PRINT_END_16
.endm


.macro rmPC c m
	PRINTc_16 \c, "\m"
.endm


.macro rmI m
	rmD 0x09 '>'
	rmPC 0x0f " \m"
	rmCOLOR 7
.endm


.macro rmI2 m
	rmPC 0x03 "\m"
.endm


.macro rmOK
	PRINTLNc_16 0x0a, " Ok"
.endm


#########################################################
.text
.code16

# in: es = 0xb800
# in: dl = boot drive
# in: ds:si = mbr partition info (offset 446 in MBR in memory)
# in: ds:cx = ramdisk address
# in: 0:ebx = kernel load end
realmode_kernel_entry:
	push	cx
	mov	ax, 0x0f00
	xor	di, di
	mov	cx, 160*25
	rep	stosw
	pop	cx
	xor	di, di
	mov	al, '!'
	stosw

	mov	eax, ds

	push	cs
	pop	ds

	.if DEBUG_KERNEL_REALMODE
		push	dx
		mov	dx, cs
		call	printhex_16

		call	0f
	0:	pop	dx
		sub	dx, offset 0b
		call	printhex_16
		pop	dx
	.endif

####### print hello

	rmCOLOR	14
	println_16 "Kernel booting"
	rmCOLOR 7

	.if DEBUG
		PRINTc_16 8, " boot drive: "
		call	printhex2_16
		mov	edx, eax
		shl	edx, 4
		printc_16 8, "MBR.partition: "
		push	edx
		movzx	esi, si
		add	edx, esi
		call	printhex8_16
		pop	edx
		printc_16 8, "Ramdisk address: "
		movzx	ecx, cx
		add	edx, ecx
		call	printhex8_16
		call	newline_16

		printc_16 8, " Kernel loaded @ "
		add	edx, 0x200
		call	printhex8_16
		printc_16 8, "size: "
		neg	edx
		add	edx, ebx
		call	printhex8_16
		printc_16 8, "end: "
		mov	edx, ebx
		call	printhex8_16
		call	newline_16
	.endif

	.if DEBUG
		rmI "Registers "
		rmI2 "CS:IP "
		mov	dx, cs
		call	printhex_16
		call	0f
	0:	pop	dx
		sub	dx, offset 0b
		call	printhex_16
		rmI2 "rm DS "
		mov	dx, ax
		call	printhex_16
		rmI2 "DS "
		mov	dx, ds
		call	printhex_16
		rmI2 "SS:SP "
		mov	dx, ss
		call	printhex_16
		mov	dx, sp
		call	printhex_16
		call	newline_16
		rmI "Stack "
		mov	bp, sp
	0:	mov	dx, ss:[bp]
		call	printhex_16
		add	bp, 2
		jnc	0b
		call	newline_16
	.endif

	rmI	"Kernel"

	rmI2	" size: "
	mov	edx, offset kernel_end
	call	printhex8_16

	rmI2	"Signature: "
	mov	edx, cs
	shl	edx, 4
	add	edx, offset kernel_signature

	movzx	bx, dl
	and	bl, 0xf
	shr	edx, 4
	push	ds
	mov	ds, dx
	mov	edx, [bx]
	pop	ds

	rmCOLOR	0x0b
	call	printhex8_16
	rmCOLOR	0x0f

	call	newline_16

	##############################################
	# some last-minute realmode data gathering

	rmI	"Memory: "

	rmI2	"Low mem size: "
	xor	ax, ax
	int	0x12	# get low memory size
	jc	1f
	or	ax, ax
	jnz	0f
1:	printc_16 4, "Can't get lo-mem size"
	call	newline_16
	jmp	1f
0:	mov	[low_memory_size], ax
	xor	edx, edx
	mov	dx, ax
	call	printdec_16
	print_16 "kb "
1:

	.if DEBUG 
		rmI2 " Memory-map address: "
		mov	edx, ds
		shl	edx, 4
		add	edx, offset memory_map
		call	printhex8_16
		call	newline_16
	.endif

	printc_16 15, "High memory Map:"
	call	newline_16

	rmCOLOR 7
	print_16 "Base:              | Length:             | Region Type| Attributes"
	call	newline_16
	rmCOLOR 8

	mov	di, offset memory_map
	xor	ebx, ebx
0:	mov	edx, 0x534d4150
	mov	eax, 0xe820
	mov	cx, ds
	mov	es, cx
	mov	ecx, 24
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


	.if 1
	rmI "Terminating CDROM disk emulation: "
	mov	ax, 0x4b00
	mov	dl, 0x7f	# terminate all
	push	es
	push	ds
	pop	es
	mov	si, offset cdrom_spec_packet
	int	0x13
	pop	es
	mov	dx, ax
	call	printhex_16
	rmOK
	.endif

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

	call	newline_16
	printc_16 11, "Entering protected mode"
	call	newline_16



.if CHAIN_RETURN_RM_KERNEL
	push	cs
	push	word ptr offset 0f
.endif

	.if DEBUG_KERNEL_REALMODE

		printc_16 8, "ss:sp: "
		mov	dx, ss
		call	printhex_16
		mov	dx, sp
		call	printhex_16

		printc_16 8, "ret cs:ip: "
		mov	bp, sp
		mov	dx, ss:[bp + 2]
		call	printhex_16
		mov	dx, ss:[bp]
		call	printhex_16

		printc_16 14, "Press a key to continue.."
		xor	ah,ah
		int	0x16
		call	newline_16
	.endif

	# make it return elsewhere
	push	dword ptr offset kmain
	mov	ax, 0
	jmp	protected_mode
	# when pmode returns it will return to the caller of the current scope

.if CHAIN_RETURN_RM_KERNEL

0:	rmI	"Back in realmode kernel"
	printc_16 8, " ss:sp: "
	mov	dx, ss
	call	printhex_16
	mov	dx, sp
	call	printhex_16
	printc_16 8, "ret cs:ip: "
	mov	bx, dx
	mov	dx, ss:[bx+2]
	call	printhex_16
	mov	dx, ss:[bx]
	call	printhex_16
	call	newline_16

	.if DEBUG_KERNEL_REALMODE
		println_16 " - Press a key to continue"
		xor	ah, ah
		int	0x16
	.endif
	mov	di, [screen_pos]
	retf
.endif


#########################################################
.struct 0
memory_map_base:	.long 0, 0
memory_map_length: 	.long 0, 0
memory_map_region_type:	.long 0
memory_map_attributes:	.long 0 	# ACPI compliancy
memory_map_struct_size: 

.text # keep near beginning due to realmode 64k limit
low_memory_size: .word 0 # in kb
memory_map:	.space 24 * 10	# 10 lines (qemu has 5)
cdrom_spec_packet: .space 0x13


################################
#### Console/Print #############
################################
#### 16 bit debug functions ####
printhex1_16:
	push	ecx
	mov	ecx, 1
	rol	edx, 28
	jmp	1f
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

printchar_16:
	PRINT_START_16
	stosw
	PRINT_END_16
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

# in: dx
printdec_16:
	mov	ax, dx
	mov	cx, 10
	push	word ptr -1
0:	xor	dx, dx
	div	cx
	push	dx
	or	ax, ax
	jnz	0b

0:	pop	ax
	cmp	ax, -1
	jz	0f
	add	al, '0'
	call	printchar_16
	jmp	0b
0:	ret


realmode_kernel_end:
