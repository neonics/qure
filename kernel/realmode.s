##############################################################################
# Realmode Kernel Entry
#
# Performs last-minute realmode tasks before entering protected mode.
.intel_syntax noprefix

DEBUG_KERNEL_REALMODE = 0	# 1: require keystrokes at certain points


RM_PRINT_HIGH_MEMMAP = 0
# When the protected-mode part of the kernel returns to realmode,
# it will transfer control back to it's caller, which is tpically
# the bootloader. Setting this to 1 will cause the transfer to the caller
# to be indirect. It will insert a realmode-code address in the return stack.
CHAIN_RETURN_RM_KERNEL = 1
#########################################################

.data16 1
data16_strings:
.data16
screen_pos_16: .long 0
screen_color_16: .word 0
___fooo:
.text16


.macro PRINT_START_16 col=-1
	push	es
	push	di
	push	ax
	mov	di, 0xb800
	mov	es, di
	mov	di, [screen_pos_16]
	.ifc \col,-1
	mov	ah, [screen_color_16]
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
	mov	[screen_pos_16], di
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

.macro LOAD_TXT_16 m, reg16=si
	.data16 1
	999: .asciz "\m"
	.text16
	mov	\reg16, offset 999b
.endm

.macro PRINT_16 m
	.ifc si,\m
	call	print_16
	.else
	push	si
	LOAD_TXT_16 "\m"
	call	print_16
	pop	si
	.endif
.endm

.macro PRINTc_16 c, m
	push	word ptr [screen_color_16]
	mov	[screen_color_16], byte ptr \c
	PRINT_16 "\m"
	pop	word ptr [screen_color_16]
.endm


.macro PRINTLN_16 m
	PRINT_16 "\m"
	call	newline_16
.endm

.macro PRINTLNc_16 c, m
	PRINTc_16 \c, "\m"
	call	newline_16
.endm

.macro PH8_16 x, m="\x"
	PRINT_16 "\m"
	.ifnc edx,\x
	push	edx
	mov	edx, \x
	call	printhex8_16
	pop	edx
	.else
	call	printhex8_16
	.endif
.endm


.macro COLOR_16 c
	mov	[screen_color_16], byte ptr \c
.endm

.macro PUSHCOLOR_16 c
	push	word ptr [screen_color_16]
	mov	[screen_color_16], byte ptr \c
.endm

.macro POPCOLOR_16
	pop	word ptr [screen_color_16]
.endm

.macro rmI m
	PRINTCHARc_16 0x09, '>'
	PRINTc_16 0x0f, " \m"
	COLOR_16 7
.endm


.macro rmI2 m
	.ifc si,\m
	PRINTc_16 0x03, si
	.else
	PRINTc_16 0x03, "\m"
	.endif
.endm


.macro rmOK
	PRINTLNc_16 0x0a, " Ok"
.endm

# in: edx = flat addr
# out: edx = dword at flat addr
.macro GETFLAT
	push ebx
	push fs
	ror edx, 4
	mov fs, dx
	rol edx, 4
	mov bx, dx
	and bx, 15
	mov edx, fs:[bx]
	pop fs
	pop ebx
.endm


#########################################################
.text16

# in: es = 0xb800
# in: dl = boot drive, dh = boot partition
# in: ds:si = mbr partition info (offset 446 in MBR in memory)
# in: ds:cx = ramdisk address
# in: 0:ebx = kernel load end
realmode_kernel_entry:
#mov eax, offset .text16
	int3		# trigger debugger from pmode - when eip=0
	push	cx
	mov	ax, 0x0f00
	xor	di, di
	mov	cx, 80*25
	rep	stosw
	pop	cx
	xor	di, di
	mov	ax, 0xf0<<8|'!'
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

	push	eax
	.if REALMODE_SEP	# .text16,.data16,.text,.data
	mov	eax, offset .text16
	.else			# .text[text16,data16,text32],.data
	mov	eax, offset .text
	.endif
	mov	[reloc$], eax



	# determine cs:ip since we do not assume to be loaded at any address
	mov	eax, cs
	shl	eax, 4
	mov	[kernelbase], eax
	sub	eax, [reloc$]
	mov	[codebase], eax
	xor	eax, eax
	mov	[realsegflat], eax	# always 0 due to reloc

	mov	eax, ds
	shl	eax, 4
	sub	eax, [reloc$]
	mov	[database], eax

# reloc$	00013000	00000000	# memory reference relocation
# realsegflat	00000000	00000000	
# kernelbase	00013000	00013000	# abs load addr
# codebase	00000000	00013000
# database	00000000	00013000

call newline_16
push edx
mov edx, [reloc$];	PH8_16 edx, "reloc$:      ";	call newline_16
mov edx, [realsegflat]; PH8_16 edx, "realsegflat: ";	call newline_16
mov edx, [kernelbase];	PH8_16 edx, "kernelbase:  ";	call newline_16
mov edx, [codebase];	PH8_16 edx, "codebase:    ";	call newline_16
mov edx, [database];	PH8_16 edx, "database:    ";	call newline_16
pop edx

	.if DEBUG > 2
		printc_16 0x5f, "*"
		xor ax,ax; int 0x16
	.endif

	pop	eax


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
		printc_16 8, "relocation: "
		mov	edx, [reloc$]
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

	rmI	"Kernel "

	.if DEBUG
	mov eax, offset KERNEL_START
	PH8_16 eax,"KERNEL_START "
	mov eax, offset kernel_end
	PH8_16 eax,"KERNEL_END "
	mov eax, offset KERNEL_SIZE
	PH8_16 eax,"KERNEL_SIZE "
	.endif

	rmI2	" size: "
	mov	edx, offset KERNEL_SIZE	# linker
	call	printhex8_16

	rmI2	"Signature: "
	mov	edx, cs
	shl	edx, 4
	add	edx, offset kernel_signature	# relocation
	sub	edx, [reloc$]
	GETFLAT
	COLOR_16 0x0b
	call	printhex8_16

	cmp	edx, 0x1337c0de
	jnz	1f
	rmOK
	jmp	2f

1:	PRINTc_16 0x4f, "Invalid signature - press key"
	xor	ax, ax
	int	0x16
	call	newline_16

2:	COLOR_16 0x0f

	###############################################
	# verify ramdisk, calculate kernel images end

	rmI "Ramdisk: "

	push	fs
	mov	fs, [bootloader_ds]
	mov	bx, [ramdisk]
	cmp     dword ptr fs:[bx + 0], 'R'|('A'<<8)|('M'<<16)|('D'<<24)
	jnz     1f
	cmp     dword ptr fs:[bx + 4], 'I'|('S'<<8)|('K'<<16)|('0'<<24)
	jz	2f

1:	PRINTc_16 12, "Invalid signature"
	jmp	3f

2:	printc_16 10, "Ok"
	mov	eax, cs	# calculate minimum load end
	shl	eax, 4
	# text.16
	#add	eax, offset kernel_end - TEXT16 # prevent relocation
	add	eax, offset kernel_end  # prevent relocation
	#sub	eax, TEXT16

	mov	ecx, fs:[bx + 8]	# num entries
	or	ecx, ecx
	jz	9f

	xor	di, di	# ramdisk entry index counter for label printing

0:	add	bx, 16
	mov	edx, fs:[bx + 4]	# load start
	or	edx, edx
	jz	1f			# not loaded
	mov	esi, fs:[bx + 12]	# load end
##
	# print entry name
	push	si
	cmp	di, 0
	jnz	3f
	mov	[kernel_load_start_flat], edx
	mov	[kernel_load_end_flat], esi
	LOAD_TXT_16 " Kernel   "
	jmp	4f
3:	cmp	di, 1
	jnz	3f
	mov	[reloc_load_start_flat], edx
	mov	[reloc_load_end_flat], esi
	LOAD_TXT_16 " Reloctab "
	jmp	4f
3:	cmp	di, 2
	jnz	3f
	mov	[symtab_load_start_flat], edx
	mov	[symtab_load_end_flat], esi
	LOAD_TXT_16 " Symtab   "
	jmp	4f
3:	cmp	di, 3
	jnz	3f
	mov	[stabs_load_start_flat], edx
	mov	[stabs_load_end_flat], esi
	LOAD_TXT_16 " Stabs    "
	jmp	4f
3:	LOAD_TXT_16 " ? "
4:	call newline_16; rmI2	si
	pop	si
##
	# print load start/end
	call	printhex8_16
	PRINT_16 "- "
	mov	edx, fs:[bx + 12]	# load end
	call	printhex8_16

	cmp	edx, eax	# check if loaded higher
	jb	1f
	mov	eax, edx
1:	inc	di
	dec	ecx
	jnz	0b
9:	pop	fs

	mov	[ramdisk_load_end_flat], eax
	rmI2	"End: "
	mov	edx, eax
	call	printhex8_16
	# need to use offset for ABSOLUTE linker constant,
	# otherwise the assembler takes it as a memory reference
	# instead of a constant.
	print_16 "KERNEL_SIZE:"
	mov	edx, offset KERNEL_SIZE #- .text16
	call	printhex8_16
	call	newline_16

	##############################################
	# calculate stack

	# calculate kernel load end
	mov	edx, [kernel_load_start_flat]
	add	edx, offset KERNEL_SIZE
	sub	edx, [codebase]
	mov	[kernel_load_end], edx

	# use kernel load end as stack bottom
	#
	# NOTE! this assumes that memory space is available
	# after the kernel. This will NOT be the case if
	# the kernel is loaded high. This case is
	# currently unimplemented since the kernel has a realmode
	# part which requires to be run at low memory
	# (unless the first 4kb of the 1mb region is realmode
	# addressable).
	mov	[kernel_stack_bottom], edx
	# TODO: .bss

	# align the stack top with 4kb physical page:
	add	edx, [database]
	add	edx, 4095
	and	edx, ~4095
	sub	edx, [database]
	# edx = first page boundary after kernel_stack_bottom.

	# reserve stack for TSS
	add	edx, 8*KERNEL_MIN_STACK_SIZE
	mov	[kernel_tss0_stack_top], edx

	# reserve stack for kernel
	add	edx, KERNEL_MIN_STACK_SIZE
	mov	[kernel_stack_top], edx

	.if DEBUG
		print_16 "Kernel Stack: "
		PH8_16 [kernel_stack_bottom]
		print_16 "-"
		PH8_16 [kernel_stack_top]
	.endif

	##############################################

	.if DEBUG > 2
		printc_16 0x4f, "*"
		xor	ax,ax
		int	0x16
	.endif

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

	.if RM_PRINT_HIGH_MEMMAP
		printc_16 15, "High memory Map:"
		call	newline_16

		COLOR_16 7
		print_16 "Base:              | Length:             | Region Type| Attributes"
		COLOR_16 8
	.endif
	call	newline_16

	mov	di, offset memory_map
	xor	ebx, ebx
0:	mov	edx, 0x534d4150	# "SMAP"
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
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex8_16
	.endif
	mov	edx, es:[di]
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex8_16
	.endif
	add	di, 8
	.if RM_PRINT_HIGH_MEMMAP
		COLOR_16 1
		print_16 " |  "
		COLOR_16 8
	.endif
	# qword length
	mov	edx, es:[di+4]
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex8_16
	.endif
	mov	edx, es:[di]
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex8_16
	.endif
	add	di, 8
	.if RM_PRINT_HIGH_MEMMAP
		COLOR_16 1
		print_16 " |  "
		COLOR_16 8
	.endif
	# dword region type
	# 1 = usable ram
	# 2 = reserved
	# 3 = acpi reclaimable
	# 4 = acpi nvs 
	# 5 = bad memory
	mov	edx, es:[di]
	add	di, 4
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex8_16
		COLOR_16 1
		print_16 " |  "
		COLOR_16 8
	.endif
	# dword ACPI 3.0 attributes
	mov	edx, es:[di]
	add	di, 4
	.if RM_PRINT_HIGH_MEMMAP
		call	printhex2_16
		call	newline_16
	.endif

	jmp	0b
#	jmp	1f

0:	COLOR_16 12
	print_16 "int 0x15 error: eax="
	COLOR_16 4
	PH8_16 eax
1:	COLOR_16 7

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
	rmOK
	jmp	2f
1:	printlnc_16 4, "Error (no emulation?)"
2:

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

	.if DEBUG > 3
		printc_16 0x4f, "*"
		xor	ax,ax
		int	0x16
	.endif

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
	mov	di, [screen_pos_16]
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
ramdisk_load_end_flat:	.long 0	# flat address of last ramdisk entry
ramdisk_load_end:	.long 0	# realmode-cs-adjusted address
kernel_load_start_flat:	.long 0	# ramdisk info
kernel_load_end_flat:	.long 0
kernel_load_end:	.long 0
reloc_load_start_flat:	.long 0
reloc_load_end_flat:	.long 0
symtab_load_start_flat:	.long 0
symtab_load_end_flat:	.long 0
stabs_load_start_flat:	.long 0
stabs_load_end_flat:	.long 0
# bios:
low_memory_size:	.word 0 # in kb
RM_MEMORY_MAP_MAX_SIZE = 20	# 20 lines (qemu: 5, vmware: 10)
memory_map:		.space 24 * RM_MEMORY_MAP_MAX_SIZE
memory_map_end:
	MEMORY_MAP_TYPE_KERNEL	= 0x10
	MEMORY_MAP_TYPE_STACK	= 0x11
	MEMORY_MAP_TYPE_RELOC	= 0x12
	MEMORY_MAP_TYPE_SYMTAB	= 0x13
	MEMORY_MAP_TYPE_SRCTAB	= 0x14
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
	mov	ax, [screen_pos_16]
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	[screen_pos_16], ax
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
