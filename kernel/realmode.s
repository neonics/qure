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

.macro PRINT_START_16 col=-1
	push	es
	push	di
	push	ax
	mov	di, 0xb800
	mov	es, di
	mov	di, [screen_pos]
	.ifc \col,-1
	mov	ah, [screen_color]
	.else
	.ifc ah,\col
	.else
	mov	ah, \col
	.endif
	.endif
.endm

.macro PRINT_END_16
	.if 1
	cmp	di, 160 * 25 + 2
	jb	99f
	call	__scroll_16
99:
	.endif
	mov	[screen_pos], di
	pop	ax
	pop	di
	pop	es	
.endm

.macro PRINTCHAR_16 char
	push	ax
	mov	al, \char
	call	printchar_16
	pop	ax
.endm

.macro PRINTCHARc_16 col, char
	push	ax
	mov	ax, (\col << 8) | \char
	call	printcharc_16
	pop	ax
.endm

.macro PRINT_16 m
	# need to declare realmode strings in .text as kernel .text shifts
	# data beyond 64kb reach.
.if 0
	jmp	98f
	99:.asciz "\m"
	98:
.else
	.data16
	99: .asciz "\m"
	.previous
.endif
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
	.ifc edx,\x
	push	edx
	mov	edx, \x
	call	printhex8_16
	pop	edx
	.else
	call	printhex8_16
	.endif
.endm


.macro COLOR_16 c
	mov	[screen_color], byte ptr \c
.endm

.macro PUSHCOLOR_16 c
	push	word ptr [screen_color]
	mov	[screen_color], byte ptr \c
.endm

.macro POPCOLOR_16
	pop	word ptr [screen_color]
.endm

.macro rmI m
	PRINTCHARc_16 0x09, '>'
	PRINTc_16 0x0f, " \m"
	COLOR_16 7
.endm


.macro rmI2 m
	PRINTc_16 0x03, "\m"
.endm


.macro rmOK
	PRINTLNc_16 0x0a, " Ok"
.endm


#########################################################
.text16

# in: es = 0xb800
# in: dl = boot drive, dh = boot partition
# in: ds:si = mbr partition info (offset 446 in MBR in memory)
# in: ds:cx = ramdisk address
# in: 0:ebx = kernel load end
realmode_kernel_entry:
	int	1	# trigger debugger from pmode - when eip=0
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

	COLOR_16 14
	println_16 "Kernel booting"
	COLOR_16 7

	mov	[bootloader_ds], ax
	mov	[boot_drive], dx
	mov	[ramdisk], cx
	mov	[mbr], si

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

	COLOR_16 0x0b
	call	printhex8_16
	COLOR_16 0x0f

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

	COLOR_16 7
	print_16 "Base:              | Length:             | Region Type| Attributes"
	call	newline_16
	COLOR_16 8

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
	COLOR_16 1
	print_16 " |  "
	COLOR_16 8
	# qword length
	mov	edx, es:[di+4]
	call	printhex8_16
	mov	edx, es:[di]
	call	printhex8_16
	add	di, 8
	COLOR_16 1
	print_16 " |  "
	COLOR_16 8
	# dword region type
	# 1 = usable ram
	# 2 = reserved
	# 3 = acpi reclaimable
	# 4 = acpi nvs 
	# 5 = bad memory
	mov	edx, es:[di]
	add	di, 4
	call	printhex8_16
	COLOR_16 1
	print_16 " |  "
	COLOR_16 8
	# dword ACPI 3.0 attributes
	mov	edx, es:[di]
	add	di, 4
	call	printhex2_16
	call	newline_16

	jmp	0b
#	jmp	1f

0:	COLOR_16 12
	print_16 "int 0x15 error: eax="
	mov	edx, eax
	COLOR_16 4
	call	printhex8_16
1:	COLOR_16 7


	.if 1
	rmI "Terminating CDROM disk emulation: "
	mov	ax, 0x4b00
	mov	dl, [boot_drive] # 0x7f	# terminate all
	mov	si, offset cdrom_spec_packet
	int	0x13
	pushf
	mov	dx, ax
	call	printhex_16
	popf
	jc	1f
	# so there was boot emulation: get the real boot drive:
	rmI2 "Drive: "
	mov	dh, [cdrom_spec_packet + cdrom_spec_device]
	and	dh, 1
	mov	dl, [cdrom_spec_packet + cdrom_spec_controller_nr]
	shl	dl, 1
	or	dl, dh
	mov	dh, -1
	mov	[boot_drive], dx
	call	printhex2_16
1:	call newline_16
	rmOK
	.endif

	###############################
.if 0
	mov	cx, 21
	mov	bx, offset kmain
0:	mov	dx, bx
	COLOR_16 0x07
	call	printhex_16
	COLOR_16 0x08
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
	mov	ax, 1
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

.data16
boot_drive:		.byte 0	# bootloader, bios
boot_partition:		.byte 0	# bootloader
bootloader_ds:		.word 0
ramdisk:		.word 0	# [bootloader_ds]:[ramdisk]
mbr:			.word 0	# [bootloader_ds]:[ramdisk]
# bios:
low_memory_size:	.word 0 # in kb
memory_map:		.space 24 * (10+1) # 11 lines (qemu: 5, vmware: 10)
cdrom_spec_packet:	.space 0x13
####################################
.struct 0
cdrom_spec_size:	.byte 0		# size of packet
cdrom_spec_boot_media_type: .byte 0 #3:0: 0=no emul;1=1.2;2=1.44;3=2.88;4=hdd
				# 6: image has atapi driver; 7: has scsi driver.
cdrom_spec_drive_number:.byte 0 # 00=floppy image, 80=hdd,81+=nonboot/no emul.
cdrom_spec_controller_nr: .byte 0
cdrom_spec_image_lba:	.long 0
cdrom_spec_device:	.word 0 # [15:8: bus nr] [7:0 SCSI LUN+PUN] [0:slave]
cdrom_spec_buffer_seg:	.word 0	# segment of 3k buffer
cdrom_spec_load_seg:	.word 0	# boot image initial load segment (0: 0x07c0)
cdrom_spec_num_virt_sect:.word 0 # nr of 512 byte virtual sectors
cdrom_spec_cyl_lo:	.byte 0
cdrom_spec_sect_cyl_hi:	.byte 0
cdrom_spec_head:	.byte 0


.text16
################################
#### Console/Print #############
################################
#### 16 bit debug functions ####
printhex1_16:
	push	ecx
	mov	ecx, 1
	rol	edx, 28
	jmp	1f
printhex4_16:
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

printcharc_16:
	PRINT_START_16 ah
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
	push	ax
	push	cx
	push	dx

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
0:	pop	dx
	pop	cx
	pop	ax
	ret

__scroll_16:
	push	ds
	push	cx
	push	si

	mov	si, es
	mov	ds, si
	mov	cx, di
	mov	si, 160
	xor	di, di
	sub	cx, si
	jle	99f
	push	cx
	rep	movsw
	pop	di
99:
	pop	si
	pop	cx
	pop	ds
	ret


.text16end
realmode_kernel_end:
REALMODE_KERNEL_SIZE = realmode_kernel_end - realmode_kernel_entry
