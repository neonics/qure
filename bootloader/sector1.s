# included in bootloader.s
.intel_syntax noprefix

DEBUG_BOOTLOADER = 0	# 0: no keypress. 1: keypress; 2: print ramdisk/kernel bytes.
CHS_DEBUG = 0
RELOC_DEBUG = 0		# 0: no debug; 1: debug; 2: keypress

MULTISECTOR_LOADING = 1	# 0: 1 sector, 1: 128 sectors(64kb) at a time
KERNEL_ALIGN_PAGE = 1	# load kernel at page boundary
KERNEL_RELOCATION = 1

TRACE_RELOC_ADDR = 0	# trace zero-based kernel image offset; 0 = no trace

KERNEL_IMG_PARTITION = 0 # 1: first bootable partition; 0: img follows bootloader

.text
.code16
. = 512
.data
bootloader_registers: .space 32

msg_sector1$: .asciz "Transcended sector limitation!"
.text
	# copy bootloader registers
	push	es
	push	ds
	push	di
	push	si
	push	cx

	push	ds
	pop	es

	push	ss	# copy from stack
	pop	ds

	mov	si, bp
	mov	di, offset bootloader_registers
	mov	cx, 32 / 4
	rep	movsd

	pop	cx
	pop	si
	pop	di
	pop	ds
	pop	es

	mov	ax, 0xf320
	mov	si, offset msg_sector1$
	call	print
	stosw
	mov	edx, [bootloader_sig]
	call	printhex8
	call	newline

	# disable cursor

	mov	cx, 0x2000	# 0x2607 - underline rows 6 and 7
	mov	ah, 1
	int	0x10

	jmp	main

BOOTSECTOR=0
SECTOR1=1
.include "../16/print.s"
.text
main:
	#call	menu
	push	es
	push	di
	call	unreal_mode
	pop	di
	pop	es

	mov	ah, 0xf1

	# Find boot partition

	mov	si, offset mbr
	mov	cx, 4
0:	test	[si], byte ptr 0x80
	jnz	1f
	add	si, 16
	loop	0b

	PRINT	"No bootable partition in MBR"
	jmp	fail

1:	mov	[partition], si

	.data
		partition: .word 0
	.text
##################################################
.if 1
	mov	ah, 0xf0
	PRINT "Partition "
	mov	dx, 4
	sub	dx, cx
	call	printhex
	PRINT "Mem offset: "
	mov	dx, si
	call	printhex

	mov	al, 'H'
	stosw
	mov	dl, [si + 1]
	call	printhex2

	mov	al, 'S'
	stosw
	mov	dl, [si + 2]
	call	printhex2

	mov	al, 'C'
	stosw
	mov	dl, [si + 3]
	call	printhex2

	PRINT	"partinfo@"
	mov	dx, si
	call	printhex
.endif

	call	get_memory_map
	mov	edx, [hi_mem_start]
	mov	[image_high], edx
	mov	ah, 0xf0

	call	load_ramdisk_fat
	call	load_ramdisk_kernel

mov ebx, [ramdisk_buffer]
	add	si, 16		# ignore entry count and check size
	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	mov	ah, 0xf3
	print "Loading relocation table: "
	call	load_ramdisk_entry_hi
	# compact:
	mov	eax, [si + ramdisk_entry_size]
	neg	eax
	and	eax, 0x1ff
	sub	[image_high], eax
	mov	eax, [si + ramdisk_entry_load_start]
	mov	[reloctab], eax
1:

#	mov	ebx, [si + ramdisk_entry_load_end]
mov ebx, [ramdisk_buffer]
	add	si, 16		# ignore entry count and check size
	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	mov	ah, 0xf3
	print "Loading symbol table: "
	call	load_ramdisk_entry_hi
	# compact:
	mov	eax, [si + ramdisk_entry_size]
	neg	eax
	and	eax, 0x1ff
	sub	[image_high], eax
	mov	eax, [si + ramdisk_entry_load_start]
	mov	[symtab], eax
1:

	mov	ebx, [si + ramdisk_entry_load_end]
mov ebx, [ramdisk_buffer]
	add	si, 16		# ignore entry count and check size
	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	mov	ah, 0xf3
	print "Loading stabs: "
	call	load_ramdisk_entry_hi
1:

##############################################
.if KERNEL_RELOCATION
	call	relocate_kernel
.endif

	mov	ah, 0xf0
	print "Chaining to next: "
	mov	edx, [chain_addr_flat]
	call	printhex8

	.data
		chain_addr_seg: .long 0
		chain_addr_offs: .long 0
	.text
.if 1
	# the address is sector aligned so this is safe:
	xor	esi, esi
	shr	edx, 4
	cmp	edx, 0xffff
	jbe	1f
	mov	esi, 0xffff
	sub	esi, edx
	#jns	1f	# segment is ok
	add	edx, esi
	neg	esi
		push edx; mov edx, esi; inc ah;call printhex8;dec ah; pop edx
	shl	esi, 4
1:	mov	[chain_addr_seg], edx
	mov	[chain_addr_offs], esi

	call	printhex8
	mov	es:[edi-2], byte ptr ':'
	mov	edx, esi
	call	printhex8
	call	newline

	# verify the offset is within 16-bit range:
	cmp	edx, 0xffff
	jbe	1f
	printc 0xf4, "segment too high: "
	call	printhex8
	jmp	fail
1:
	mov	edx, [chain_addr_offs]
	cmp	edx, 0x00010000
	jb	1f
	printc 0xf4, "offset too high: "
	call	printhex8
	jmp	fail
1:
.endif

	# set up some args:
	mov	si, [partition]	# pointer to MBR partition info
	mov	dx, si
	sub	dx, offset mbr	# 16 bytes/entry
	shl	dx, 9		# ah = partition index
	call	get_boot_drive	# dl = drive
	mov	cx, [ramdisk_address]
				# bx = end of kernel

	push	dx
	PRINT	"dl: boot drive: "
	call	printhex2
	PRINT	"partition: "
	mov	dl, dh
	call	printhex2
	call	newline

	PRINT	"cx: ramdisk address: "
	mov	dx, cx
	call	printhex
	call	newline

	PRINT	"si: MBR address: "
	mov	dx, si
	call	printhex
	call	newline

	PRINT	"bx: kernel end: "
	mov	edx, ebx
	call	printhex8
	pop	dx

	# simulate a far call:
	push	cs
	push	word ptr offset bootloader_ret

	.if DEBUG_BOOTLOADER
		push	dx
		push	bp
		PRINT	"ss:sp: "
		mov	dx, ss
		call	printhex
		mov	dx, sp
		add	dx, 2
		call	printhex

		PRINT	"ret cs:ip: "
		mov	bp, sp
		mov	dx, [bp + 4]
		call	printhex
		mov	dx, [bp + 2]
		call	printhex
		pop	bp
		pop	dx

	.endif

	call	newline

	# far jump:
.if 1
	push	word ptr [chain_addr_seg]
	push	word ptr [chain_addr_offs]

.else
	mov	eax, [chain_addr_flat]
	ror	eax, 4
	push	ax
	rol	eax, 4
	and	ax, 0xf
	push	ax

.endif

	.if DEBUG_BOOTLOADER

		push fs
		push bp
		mov ah, 0x1f
		mov bp, sp
		add bp, 4
		push dx
		mov dx, [bp+2]
		mov fs, dx
		call printhex
		mov dx, [bp+0]
		call printhex
		push bx
		mov bx, dx
		mov edx, fs:[bx]
		call printhex8
		mov edx, fs:[bx+4]
		call printhex8
		pop bx
		pop dx
		pop bp
		pop fs

		call	waitkey
	.endif
	retf


bootloader_ret:
0:	mov	ax, 0xb800
	mov	es, ax
	push	cs
	pop	ds
	.if 0
	xor	di, di
	mov	ax, 0xf000
	mov	cx, 80*25
	rep	stosw
	xor	di, di
	.endif
	PRINTln "Back in bootloader."
	PRINT "Press 'q' or ESC to halt system; 'w' for warm, 'c' for cold reboot, 's' for shutdown."
	call	newline
0:	xor	ah, ah
	int	0x16
	cmp	ax, K_ESC
	jz	0f
	cmp	al, 'q'
	jz	0f
	cmp	al, 'w'
	jz	warm_reboot
	cmp	al, 'c'
	jz	cold_reboot
	cmp	al, 's'
	jz	shutdown
	jmp	0b

0:	PRINTc	0xf3, "System halt."
	jmp	halt

warm_reboot:
	mov	ax, 0x1234
	jmp	1f
cold_reboot:
	xor	ax, ax
1:	xor	di, di
	mov	fs, di
	mov	fs:[0x0472], ax
	ljmp	0xf000, 0xfff0

shutdown:
	mov	ax, 0x5307	# APM Set Power State
	mov	cx, 3 	#BIOS_APM_SYSTEM_STATE_OFF
	mov	bx, 1	#BIOS_APM_DEVICE_ID_ALL
	int	0x15		# APM 1.0+
	printc	14, "Shutdown."
	jmp	halt

##################################################

.struct 0
mm_base:	.long 0, 0
mm_size:	.long 0, 0
mm_type:	.long 0
.data
lo_mem_end:	.long 0
hi_mem_start:	.long 0
hi_mem_end:	.long 0
memory_map_entry: .space 20
.text

get_memory_map:
	call	newline
	mov	ah, 0xf3
	print	"BIOS Memory Map: "
	xor	ebx, ebx	# continuation / iteration val
0:	mov	ecx, 20		# max entry size
	push	es
	push	di
	mov	cx, ds
	mov	es, cx
	mov	di, offset memory_map_entry
	mov	edx, 0x534d4150	# "SMAP"
	mov	eax, 0xe820
	int	0x15
	pop	di
	pop	es
	jc	9f
	cmp	eax, 0x534d4150
	jnz	9f
	or	ebx, ebx
	jz	0f # done

	cmp	dword ptr [memory_map_entry + mm_type], 1
	jnz	1f
	# found free mem
	cmp	dword ptr [memory_map_entry + mm_size + 4], 0
	jnz	3f

	cmp	dword ptr [memory_map_entry + mm_base], 0
	jnz	2f
	cmp	dword ptr [memory_map_entry + mm_base + 4], 0
	jnz	2f
	# found low mem
	mov	edx, [memory_map_entry + mm_size]
	mov	[lo_mem_end], edx
	mov	ah, 0xf0
	print "Low mem end: "
	call	printhex8
	jmp	0b
3:	printc 0xf4, "skip mem entry: base/len > 32 bit"
	jmp	0b

2:	# mem doesn't start at 0
	cmp	dword ptr [hi_mem_start], 0
	jnz	0b	# already have
	mov	edx, [memory_map_entry + mm_base]
	mov	[hi_mem_start], edx
	mov	ah, 0xf0
	print "Hi mem start: "
	call	printhex8
	add	edx, [memory_map_entry + mm_size]
	mov	[hi_mem_end], edx
	print "end: "
	call	printhex8
1:
	jmp	0b


9:	printc 0x4f, "get_memory_map error"

0:	# done

	cmp	dword ptr [lo_mem_end], 0
	jnz	1f
	# get low mem size in another way:
	xor	ax, ax
	int	0x12
	jc	2f
	or	ax, ax
	jz	2f
	movzx	edx, ax
	shl	edx, 10	# ax is in Kb
	jmp	3f

2:	printc 0x4f, "get lo mem fail"
	mov	edx, 0x9f000

3:	printc 0x4f, "lo mem end defaulting to "
	mov	ah, 0xf0
	call	printhex8
	mov	[lo_mem_end], edx

############################
1:	# check hi mem start
	mov	ah, 0xf0
	cmp	dword ptr [hi_mem_start], 0
	jnz	1f
	mov	edx, 0x00100000
	printc 0x4f, "hi mem start defaulting to "
	call	printhex8
	mov	[hi_mem_start], edx

##########################
1:	# check hi mem end
	cmp	dword ptr [hi_mem_end], 0
	jnz	1f

	mov	ah, 0x88	# get extended mem size (1mb+)
	int	0x15
	jnc	2f
	or	ax, ax
	jnz	2f
	printc 0xf4, "Error getting extended mem"
2:
	printc 0x4f, "hi mem size defaulting to "
	movzx	edx, ax
	shl	edx, 10	# ax in Kb, max 64mb.
	call	printhex8
	add	edx, 0x00100000	# the bios func reports 1Mb+
	mov	[hi_mem_end], edx
########
1:	call	newline
	ret

####### Read RAMDISK sector
.struct 0	# first ramdisk entry is the header:
ramdisk_sig:		.long 0,0	# "RAMDISK0"
ramdisk_entries:	.long 0
ramdisk_reserved:	.long 0
.struct 0	# the other entries follow this pattern:
ramdisk_entry_lba:	.long 0
ramdisk_entry_load_start:.long 0
ramdisk_entry_size:	.long 0	# bytes
ramdisk_entry_load_end:	.long 0
.text

load_ramdisk_fat:
	call	get_boot_drive

.if KERNEL_IMG_PARTITION
	mov	dh, [si+1]	# head
	mov	cx, [si+2]	# [7:6][15:8] cylinder, [0:5] = sector
	call	chs_to_lba	# out: eax = LBA = partition start
.else
	xor	eax, eax
.endif
	add	eax, SECTORS + 1	# skip bootloader sectors
	mov	ebx, eax	# calculate memory offset
	mov	ecx, eax
	shl	ebx, 9
	mov	ah, 0xf0
	.data
		ramdisk_address: .long 0
		ramdisk_address_flat: .long 0
	.text
	mov	[ramdisk_address], ebx
	PRINT	"RAMDISK Memory Address: "
	push	edx
	mov	edx, ebx
	call	printhex8
	push	ax
	mov	eax, ds
	shl	eax, 4
	add	edx, eax
	mov	[ramdisk_address_flat], edx
	pop	ax
	print "flat: "
	call	printhex8

	pop	edx
	call	newline

	PRINT	"Reading sector..."
	movzx	eax, cx			# sector
	mov	ebx, [ramdisk_address_flat]
	mov	ecx, 1			# count
	call	load_sector		# does LBA conversion

	mov	ah, 0xf2
	PRINT	"Ok "
	inc	ah

####### Verify RAMDISK Signature

	# this is the 'fat', the sector after sector1.

####### dump signature
	print "SIG:"
	mov	si, [ramdisk_address]
	mov	cx, 8
0:	lodsb
	mov	dl, al
	call	printhex2
	loop	0b
	mov	cx, 8
	sub	si, 8
0:	lodsb
	stosw
	loop	0b
	add	di, 2
#######

	mov	si, [ramdisk_address]
####### Check signature
	lodsd
	cmp	eax, ('D'<<24)+('M'<<16)+('A'<<8)+'R'
	jnz	1f
	lodsd
	cmp	eax, ('0'<<24)+('K'<<16)+('S'<<8)+'I'
	jz	0f
1:	mov	ah, 0xf4
	PRINT	"Ramdisk signature failure"
	jmp	fail

0:	mov	ah, 0xf2
	PRINT	"Ok"
#######

	inc	ah
	print	" Entries: "
	lodsd
	mov	edx, eax
	lodsd	# skip  second dword (64 bit address)
	mov	ah, 0xf0
	call	printhex8

	cmp	edx, 31
	jbe	0f
	mov	ah, 0xf4
	print "More than 31 entries!"
0:
	cmp	dx, 1
	je	0f
	print "MULTIPLE ENTRIES - Choosing first" 
0:	call	newline

	.if DEBUG_BOOTLOADER > 1	# ramdisk fat
		push	si
		push	ecx
		push	eax
		push	edx
		mov	bx, dx	# nr of ramdisk entries
	0:	mov	cx, 4
	1:	lodsd
		mov	edx, eax
		mov	ah, 0xf9
		call	printhex8
		loop	1b
		call	newline
		dec	bx
		jnz	0b
		pop	edx
		pop	eax
		pop	ecx
		pop	si
	.endif
	ret

.if 0	# was used in debugging
ramdisk_print:
	push	ax
	push	si
	push	edx
	mov	ah, 0xf0
	mov	si, [ramdisk_address]
	add	si, 16
0:	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	mov	edx, [si + ramdisk_entry_load_start]
	call	printhex8
	print "-"
	mov	edx, [si + ramdisk_entry_load_end]
	call	printhex8
	add	si, 16
	jmp	0b
1:
	pop	edx
	pop	si
	pop	ax
	ret
.endif

######### first entry: kernel
######### second entry: symbol table
######### third entry: source line numbers

load_ramdisk_kernel:
	print "Loading kernel: "
#####	# prepare load address
	movzx	ebx, word ptr [ramdisk_address]
	add	bx, 0x200
.if KERNEL_ALIGN_PAGE
	add	ebx, 4095	# page align
	and	ebx, ~4095
.endif

	xor	edx, edx
	mov	dx, ds
	shl	edx, 4
	add	ebx, edx
	.data
		ramdisk_buffer: .long 0
		image_high:	.long 0
		chain_addr_flat: .long 0 # load offset = ds<<4+bx
	.text
	mov	[chain_addr_flat], ebx
	call	load_ramdisk_entry	# in: si=rd entry, ebx=flat load addr

	mov	ebx, [si + ramdisk_entry_size]
	add	ebx, 511
	and	ebx, ~511
	add	ebx, [chain_addr_flat]
	mov	[ramdisk_buffer], ebx

	.if 0
	# verify signature
	push	edx
	push	ebx
	push	fs
	mov	ebx, [chain_addr_flat]
	add	ebx, [si + ramdisk_entry_size]
	sub	ebx, 4
	ror	ebx, 4
	mov	fs, bx
	shr	ebx, 28
	mov	edx, fs:[bx]
	print	"Signature: "
	call	printhex8
	pop	fs
	pop	ebx
	pop	edx
	call waitkey
	.endif

.if 0 # copies the kernel to 1mb
	push	ds
	pushad
	mov	ecx, [si + ramdisk_entry_size]
	mov	esi, [ramdisk_buffer]
	mov	edi, 0x00100000	# 1mb
	mov	[chain_addr_flat], edi
#	mov	eax, ds
#	shl	eax, 4
#	add	esi, eax
	xor	ax, ax
	mov	ds, ax
	add	ecx, 3
	shr	ecx, 2
0:	mov	eax, [esi]
	mov	[edi], eax
	add	esi, 4
	add	edi, 4
	dec	ecx
	jnz	0b
	popad
	pop	ds
.endif
	ret


load_ramdisk_entry_hi:
	call	load_ramdisk_entry
	call	copy_high
	ret

copy_high:
# unreal mode doesnt seem to work in vmware...
#call unreal_mode
print "copy high"
call enter_pmode
	push	ds
	push	es
	pushad

	mov	ecx, [si + ramdisk_entry_size]
	mov	edx, ecx
	add	edx, 511
	and	edx, ~511
	mov	edi, [image_high]
	add	[image_high], edx	# for the next

	mov	[si + ramdisk_entry_load_start], edi
	mov	[si + ramdisk_entry_load_end], edi
	add	[si + ramdisk_entry_load_end], ecx
	mov	esi, [ramdisk_buffer]
	mov	ax, offset SEL_flat
	mov	ds, ax
	mov	es, ax
	add	ecx, 3
	shr	ecx, 2
	ADDR32 rep	movsd	# esi/edi implies ecx
	popad
	pop	es
	pop	ds
call enter_realmode
mov ah, 0xf0
print "copy done"
push edx
mov edx, [si+ramdisk_entry_load_start]
call printhex8
mov edx, [si+ramdisk_entry_load_end]
call printhex8
pop edx
call newline

	.if DEBUG_BOOTLOADER
		mov ah, 0xf0
		call waitkey
		mov ax, 0xf020
		call cls
	.endif

	ret


##################################################
.data
reloctab: .long 0
symtab:	  .long 0
.text
.if KERNEL_RELOCATION
relocate_kernel:
	print_16 "Relocating kernel"

	call	enter_pmode
	push	eax
	push	ecx
	push	edx
	push	esi
	mov	eax, offset SEL_flat
	mov	fs, eax


	mov	esi, [reloctab]
	xor	edx, edx	# 16 bit reloc
.rept 2	# .text, .addr16
	# addr16
	mov	ecx, fs:[esi]
	add	esi, 4
.if 0 # 1: don't reloc 16 bit
	lea	esi, [esi + ecx*2 + 2]	# 2: .data16 reloc val
.else
	jecxz	1f
	mov ah, 0xf3
	mov	dx, fs:[esi]	# .data16 reloc
	#call printhex
	add	esi, 2

0:	xor	eax, eax
	mov	ax, fs:[esi]
	add	esi, 2
	add	eax, [chain_addr_flat]
	add	fs:[eax], dx
	ADDR32 loop 0b
1:
.endif
.endr

	mov	edx, [chain_addr_flat]

	# addr32
	call	reloc32_setup$
	and	ecx, ~0xc0000000
	jz	1f
	push	ebp
	xor	ebp, ebp	# delta counter, if compressed
0:	call	[reloc_di]	# out: eax = offset in image

.if TRACE_RELOC_ADDR
cmp eax, TRACE_RELOC_ADDR 	#0x7fd5
jnz 10f
push ax
mov ah, 0xf4
print_16 "MATCH"
pop ax
push ax
push edx
mov edx, fs:[edx + eax]
mov ah, 0xf1
call printhex8
pop edx
pop ax
10:
.endif

	add	fs:[edx + eax], edx	# relocation value
.if TRACE_RELOC_ADDR
cmp eax, TRACE_RELOC_ADDR
jnz 10f
push ax
mov ah, 0xf4
print_16 "MATCH"
pop ax
push ax
push edx
mov edx, fs:[edx + eax]
mov ah, 0xf1
call printhex8
pop edx
pop ax
10:
.endif



	ADDR32 loop 0b
	.if RELOC_DEBUG
		push	edx
		mov edx, eax
		mov ah, 0x4f
		print_16 "LAST ADDR: "; call printhex8
		mov edx, ebp
		call printhex8
		pop	edx
	.endif
	pop	ebp

	# relocate the symbol table
	mov	esi, [symtab]
	mov	ecx, fs:[esi]
	add	esi, 4
0:	add	fs:[esi], edx
	add	esi, 4
	loop	0b

1:
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	call	enter_realmode
	.if RELOC_DEBUG > 1
		mov	ah, 0xf0
		print_16 "done relocating"
		call	waitkey
	.endif
	ret


# in: fs:esi = start of 32-bit address relocation table
# out: ecx = nr of addresses | .. << 30 (i.e., mask high 2 bits!)
reloc32_setup$:
	mov	ecx, fs:[esi]
	add	esi, 4

	push	ecx
	push	edx

	# handle compression
	test	ecx, 0x40000000	# compression flag
	mov	eax, 0		# alphabet size
	mov	cx, 0		# alpha/delta size 0
	jz	1f		# no compression
	# ecx: .word alphabetsize; .byte alphawidth; .byte deltawidth.
	mov	ecx, fs:[esi]	# cl=alphawidth; ch = deltawidth
	add	esi, 4
		mov ah, 0x1f
		mov edx, ecx
		call printhex8
	movzx	eax, cx		# eax = alphabet size/count
	shr	ecx, 16
	mov	ebx, esi	# ebx = alphabet table, ecx = size
#############
# in: cl = alpha width in bits
# in: ch = delta width in bits

	# verify 8,16,32 limit of alphawidth
	mov	dx, cx
	and	cx, 0x7f7f;
	cmp	ch, 8
	jnz	91f		# check alpha = byte
	cmp	cl, 8		# experimental
	jz	2f
	cmp	cl, 16
	jnz	91f
2:
	# handle RLE
	test	dh, 0x80
	jz	1f	# SECONDARY USE OF 1f!! main use: see above.
	call	reloc32_setup_rle$
1:
	shr	cx, 3		# bits to bytes (i.e. 16->2)

	movzx	edx, cl		# method index
	mov	dx, [reloc_am + edx * 2 - 2]
	mov	[reloc_ai], dx

	.if RELOC_DEBUG
		push ax; mov ah, 0xf; print "reloc_ai"; call printhex; pop ax;
	.endif
	# 1 byte: -> shl 0
	# 2 bytes: shl 1
	# 4 byte: shl 2
	shr	cl, 1
	shl	eax, cl		# alphasize << bits >> 3

	lea	esi, [esi + eax]# skip alphabet table: esi = rle or delta table

	##### RLE final fixup:
	mov	edx, [reloc_rle_table_size]
	or	edx, edx
	jz	1f
	# we have rle table:
	mov	[reloc_rle_table], esi
	add	esi, edx
	#####

1:

	movzx	edx, ch
	mov	dx, [reloc_dm + edx * 2]
	mov	[reloc_di], dx

	.if RELOC_DEBUG
		push ax; mov ah, 0xf; print "reloc_di"; call printhex; pop ax;
	.endif
#############
	pop	edx
	pop	ecx
	ret

91:	mov	ah, 0x4f
	print	"relocation table format unsupported: "
	mov	dx, cx
	call	printhex
	jmp	halt


##########################################
# RLE
.data
reloc_rle_table_size:	.long 0
reloc_rle_table:	.long 0
reloc_rle_token:	.long -1
.text

# parses the RLE block header:
#  .word repeat_table_element_count
#  .byte repeat_table_element_width_in_bits
#  .byte repeat_index_value_width_in_bits
# The last byte specifies the size of repeat-index values in the delta table,
# which may differ from delta-index values.
reloc32_setup_rle$:
	push	ax
	# there is RLE compression. Read the info:
	mov	ax, fs:[esi]	# al=RLE tab width; ah=RLE-idx width
	.if RELOC_DEBUG
		push ax; mov dx, ax; mov ah, 0xe; call printhex; pop ax
	.endif
	# verify RLE table entry width
	cmp	al, 0; jz 1f	# 0 is allowed: no lookup table
	cmp	al, 8; jz 1f;
	cmp	al, 16; jz 1f;
	cmp	al, 32; jnz 2f;
1:	cmp	ah, 8; jz 1f;
	cmp	ah, 16; jz 1f;
	cmp	ah, 32; jz 1f;

2:	mov	dx, ax
	mov	ah, 0x4f
	print	"relocation table RLE format unsupported: "
	call	printhex
	jmp	halt

1:
	# set up lookup table method
	movzx	edx, al
	shr	edx, 3
	mov	dx, [reloc_rlm + edx * 2]
	mov	[reloc_rl], dx

	.if RELOC_DEBUG
		push ax; mov ah, 0xf; print "reloc_rl"; call printhex; pop ax
	.endif

	# set up count/index read method for reading from delta table
	movzx	edx, ah	# RLE-idx width/repeat count width
	shr	edx, 3+1	# 8->0, 16->1, 32->2
	mov	dx, [reloc_rim + edx * 2]
	mov	[reloc_ri], dx
	.if RELOC_DEBUG
		push ax; mov ah, 0xf; print "reloc_ri"; call printhex; pop ax;
	.endif

	# calculate rle table size in bytes
	push	cx
	mov	cl, al	# RLE table entry width in bits
	shr	cl, 4	# 0, 1, 2 bytes
	movzx	edx, word ptr fs:[esi+2]	# read RLE table count
	.if RELOC_DEBUG
		push ax; mov ah, 0xf; print "RLE tab"; call printhex; pop ax;
	.endif
	shl	edx, cl
	mov	[reloc_rle_table_size], edx

	# calculate the RLE token
	mov	edx, 1
	mov	cl, ch	# delta width in bits
	shl	edx, cl
	dec	edx
	mov	[reloc_rle_token], edx		# 8 bits: 255, etc..
	.if RELOC_DEBUG
		push ax; mov ah, 0x5f; print "RLE"; call printhex8; pop ax;
	.endif
	pop	cx

	# there is a word following, indicating how many of the delta table
	# entries are repeat instructions. A repeat instructions is constituted
	# by the RLE prefix opcode and the repeat count or index.
	# Thus,
	#	d1, d2, ff, 300, d3
	# means [d1] [d2] [300x] [d3]. This relocation table will
	# have size 4: 3 delta's and one repeat instruction.
	# Addr32count will be 0x40000000 | 4, and
	# the rle_occurrence will be 1.
	# The table size follows by:
	#
	# delta_width * addr32count + rle_occurrence * (delta_width + rle_idx_w).
	#
	# pure (non-repeated) deltas: (addr32_count - rle_occ) * delta_width
	# rle size: rle_occ * (2 * delta_width + rle_idx_width).
	# (one delta for the RLE opcode, one for the value).


	add	esi, 6 # esi now points to alpha table.
	add	ebx, 6 # update ebx, delta table offset, aswell
	pop	ax
	ret




.data
reloc_am: .word reloc32_ab, reloc32_aw, reloc32_ad# methods
reloc_ai: .word 0					# index method
reloc_dm: .word reloc32_d, reloc32_db, reloc32_dw, reloc32_dd
reloc_di: .word 0
reloc_rim:.word reloc32_rib, reloc32_riw, reloc32_rid # RLE index method
reloc_ri: .word 0	# RLE read index
reloc_rlm:.word reloc32_rl, reloc32_rlb, reloc32_rlw, reloc32_rld # RLE lookup method
reloc_rl: .word 0	# RLE read lookup
reloc_rle_rep: .long 0
.text
.code16
# reloc32_aX: in: fs:ebx = alpha table start; ebp=delta counter

reloc32_ab:
	movzx	eax, byte ptr fs:[ebx + eax]
	jmp	1f

reloc32_aw:
	movzx	eax, word ptr fs:[ebx + eax * 2]
	jmp	1f

reloc32_ad:
	mov	eax, fs:[ebx + eax * 4]
1:	add	ebp, eax	# update total delta
	mov	eax, ebp	# current address
	ret


# default delta method when no delta compression
reloc32_d:
	mov	eax, fs:[esi]
	add	esi, 4
	ret

reloc32_db:
4:	movzx	eax, byte ptr fs:[esi]
		cmp	dword ptr [reloc_rle_rep], 0
		jz	1f
		dec	dword ptr [reloc_rle_rep]
		jnz	2f
1:	inc	esi
		call	reloc32_rle
		jc	reloc32_db
2:	jmp	[reloc_ai]

reloc32_dw:
	movzx	eax, word ptr fs:[esi]
		cmp	dword ptr [reloc_rle_rep], 0
		jz	1f
		dec	dword ptr [reloc_rle_rep]
		jnz	2f
1:	add	esi, 2
		call	reloc32_rle
		jc	reloc32_dw
2:	jmp	[reloc_ai]

reloc32_dd:
	mov	eax,  fs:[esi]
		cmp	dword ptr [reloc_rle_rep], 0
		jz	1f
		dec	dword ptr [reloc_rle_rep]
		jnz	2f
1:	add	esi, 4
		call	reloc32_rle
		jc	reloc32_dd
2:	jmp	[reloc_ai]


# in: eax = current delta token
# in: esi = next delta token
# out: CF = 1: repeat detected
reloc32_rle:
	# this check MAY fail under the following condition, causing a delta to
	# be interpreted as an RLE prefix:
	#  the delta-index table has 256/65536/.. entries and RLE is unused.
	mov	dword ptr [reloc_rle_rep], 0
	cmp	eax, [reloc_rle_token]
	clc
	jnz	1f
	# it is an RLE prefix. read the repeat-index number:
	call	[reloc_ri]	# out: eax=repeat index.
	inc	eax
	mov	[reloc_rle_rep], eax	# repeat prefix configured.
	stc

1:	ret


# repeat-index to repeat-count lookup table access methods

# dummy method: no lookup table.
reloc32_rl:
	ret

# [reloc_ri] points to one of these. Reads repeat index.
# in: eax = repeat index
reloc32_rlb:
	add	eax, [reloc_rle_table]
	movzx	eax, byte ptr fs:[eax]
	ret

reloc32_rlw:
	add	eax, eax
	add	eax, [reloc_rle_table]
	movzx	eax, word ptr fs:[eax]
	ret

reloc32_rld:
	shl	eax, 2
	add	eax, [reloc_rle_table]
	mov	eax, fs:[eax]
	ret

# RLE index reading: reads from delta table, like reloc32_dX,
# and continues to lookup.
reloc32_rib:
	movzx	eax, byte ptr fs:[esi]
	inc	esi
	jmp	[reloc_rl]
reloc32_riw:
	movzx	eax, word ptr fs:[esi]
	add	esi, 2
	jmp	[reloc_rl]
reloc32_rid:
	mov	eax, fs:[esi]
	add	esi, 4
	jmp	[reloc_rl]

.endif
##################################################

debug_print_addr$:
	push	es
	push	di
	push	dx
	push	ax

	mov	dx, es

	mov	di, 0xb800
	mov	es, di
	mov	di, 23 * 160
	mov	ah, 0xfd

	call	printhex
	mov	es:[di -2], byte ptr ':'
	mov	dx, bx
	call	printhex

	pop	ax
	pop	dx
	pop	di
	pop	es
	ret

debug_13_es_bx$:
	push	es
	push	di
	push	dx
	mov	dx, es
	mov	ax, 0xb800
	mov	es, ax
	mov	di, 160	+ 40
	mov	ah, 0x2f
	call	printhex
	mov	al, ':'
	stosw
	mov	dx, bx
	call	printhex

	mov	di, 160	- 2
	mov	al, ' '
	stosw
	pop	dx
	pop	di
	pop	es
	ret

debug_print_load_address$:
	push	di
	push	edx
	push	eax
	push	ecx
	#mov	di, 22*160
	xor	di, di
	mov	ah, 0xfc

	print	"load offs "
	mov	edx, ebx
	call	printhex8

	print	"flat "
	xor	edx, edx
	mov	dx, ds
	shl	edx, 4
	add	edx, ebx
	call	printhex8

	print	"s:o "
	ror	edx, 4
	call	printhex
	mov	es:[di - 2], byte ptr ':'

	rol	edx, 4
	and	edx, 0xf
	call	printhex

	print	"count left "
	pop	ecx
	push	ecx
	mov	edx, ecx
	call	printhex8

	#cmp	ecx, 5
	#ja	0f
.if DEBUG_BOOTLOADER > 3
	call	newline
	call	printregisters
	mov	byte ptr es:[di], '?'
	xor	ah, ah
	int	0x16
.endif
0:
	pop	ecx

	pop	eax
	pop	edx
	pop	di

	ret

#############################################################################

.macro TRACE_INIT
	.data
	trace$: .word 0
	.text
	push	di
	push	cx
	push	ax
	mov	di, 160 * 24
	mov	[trace$], di
	mov	cx, 80
	mov	ax, (0x3f<<8)
	rep	stosw
	pop	ax
	pop	cx
	pop	di
.endm

.macro TRACE l
	push	word ptr \l
	call	trace
.endm

# in: stackarg: word: byte=character
# out: clears the argument from the stack
trace:
	push	bp
	mov	bp, sp
	pushf

	push	es
	push	di
	push	ax

	mov	al, [bp + 4]
	mov	ah, 0x3f

	mov	di, 0xb800
	mov	es, di
	mov	di, [trace$]
	stosw
	mov	[trace$], di

	pop	ax
	pop	di
	pop	es

	popf
	pop	bp
	ret	2

# in: ebx = flat memory pointer where image will be loaded.
# in: si: points to entry in ramdisk FAT.
# in: [si + 0]: dword start sector, LSB
# in: [si + 8]: dword count, LSB
# out: [si + 4], image load start
# out: [si + 12], image load end
# NOTE: overwrites high 32 bit of count and address. This will only matter when
# a ramdisk entry exceeds 4Gb in size.
load_ramdisk_entry:
	mov	[si + 4], ebx	# image base memory address

	mov	ecx, [si + 8]	# load bytes

lea edx, [ebx + ecx]
cmp edx, [lo_mem_end]
jb 1f
printc 0x4f, "Warning: ramdisk entry will overwrite BIOS"
1:

	test	cx, 0x1ff
	jz	0f
	add	ecx, 0x200
0:	shr	ecx, 9		# convert to sectors

	mov	eax, [si]	# load start offset
	test	eax, 0x1ff
	jz	0f
	mov	ah, 0xf4
	PRINT	"Start offset not sector aligned!"
	mov	edx, eax
	call	printhex8
	jmp	fail
0:	shr	eax, 9		# convert to sectors
	add	eax, SECTORS + 1

####
	# eax = start sector on disk
	# ecx = count sectors
	# ebx = flat address
	push	eax
##
.if 1
	mov	edx, ecx
	shl	edx, 9
	add	edx, ebx
.else
	# if the ramdisk image is loaded consecutively:
	mov	edx, eax
	inc	edx	# account for FAT sector
	add	edx, ecx
	shl	edx, 9

	mov	eax, ds
	shl	eax, 4
	add	edx, eax
.endif
	# probably need +ebx
	mov	[si + 12], edx	# image end address (start+count)*512+ds*16
##
	pop	eax
	# edx = image load end (flat address + count sectors * 512)
	call	print_ramdisk_entry_info$

	inc	ecx
################################# load loop
0:	push	ecx		# remember sectors to load
	push	eax		# remember offset
	call	load_sector
	pop	eax
	add	eax, ecx
	sub	[esp], ecx
	pop	ecx
	jg	0b

.if 1
	mov ah, 0xf1
	mov edx,ecx; call printhex8
	mov edx, ebx; call printhex8
.endif

TRACE '*'
	# bx points to end of loaded data (kernel)
################################# end load loop
	mov	ah, 0xf6
	print	"Success!"
	mov	edx, ebx	# 0005f400 OK   00038e00 ERR
	call	printhex8
	ret


# in: eax = sector
# in: ebx = flat mem address to load to
# in: ecx = number of sectors remaining to be loaded
# out: ecx = nr sectors loaded
# out: ebx = updated
load_sector:
.if MULTISECTOR_LOADING
	cmp	ecx, 0x10000/512 # 128, load max 64kb
	jbe	1f
	mov	ecx, 128
1:
.else
	mov	ecx, 1
.endif
	push	ecx
	push	bp
	mov	bp, sp
	add	bp, 2	# have bp point to ecx

	.if 0	# use this to debug when loading fails
		call	debug_print_load_address$
	.endif

TRACE_INIT
TRACE '!'

PRINT_LOAD_SECTORS = 0
	.if PRINT_LOAD_SECTORS
		mov	edx, eax
		mov	ah, 0xf5
		call	printhex8
		mov	edx, ecx
		call	printhex8
		mov	dx, bx
		inc ah
		call	printhex
		inc ah
		sub	dx, 0x0e00
		call	printhex
		inc ah
		mov	edx, [bx]
		call	printhex8
		pop	eax
		push	eax
	.endif

	call	get_boot_drive	# out: dl = drive
	call	lba_to_chs	# out: dh = head, cx = cyl/sect

	.if PRINT_LOAD_SECTORS
		push	dx
		mov	ah, 0xf1
		print "H,D:"
		call	printhex
		print "C,S:"
		mov	dx, cx
		call	printhex
		print "N"
		mov	dl, [bp]	# nsect
		call	printhex2
		pop	dx
	.endif

	push	es
	mov	eax, ebx	# convert flat ebx to es:bx
	ror	eax, 4
	mov	es, ax
	shr	eax, 28
	push	ebx
	mov	bx, ax
	mov	ah, 2		# read sector
	mov	al, [bp]	# nr sectors
	int	0x13
	pop	ebx
	pop	es
TRACE '>'

	jc	fail
# vmware hdd boot: ax=0x0050 (al should be 1);
# according to ralph brown's list, al only valid if CF set
# on some BIOS.
# So, we don't check.
#	cmp	ax, [bp]	# al?
#	jne	fail
	or	ah, ah
	jnz	fail
TRACE 'c'

	mov	dx, ax
	mov	ax, 0xf2<<8|'.'
	stosw

	.if !PRINT_LOAD_SECTORS
	#add	di, 2
	.else
	call	newline
	.endif

	pop	bp
	pop	ecx
	shl	ecx, 9
	add	ebx, ecx #0x200 * nr sectors
	shr	ecx, 9	# return nr sectors loaded
	ret



# eax = sector on disk
# ebx = load offset  [chain_addr_flat] = ds<<4+bx
# ecx = sectors to load
print_ramdisk_entry_info$:
	push	eax
	mov	edx, eax
	mov	ah, 0xf1

	print	"Sectors: "
	call	printhex8
	mov	al, '+'
	mov	es:[di-2], ax
	mov	edx, ecx
	call	printhex8

	print	"Flat Mem: "
	mov	edx, ebx
	call	printhex8
	mov	es:[di-2], byte ptr '-'
	mov	edx, ecx
	shl	edx, 9
	add	edx, ebx
	call	printhex8

#	push	edx
#	shr	edx, 4
#	call	printhex
#	mov	es:[di - 2], byte ptr ':'
#	pop	edx
#	and	dx, 0xf
#	mov	ah, 0xf1
#	call	printhex

.if 0 #disabled since stack is before kernel
	print "Stack: "
	push	edx
	push	ecx
	xor	edx, edx
	mov	dx, ss
	mov	ecx, edx
	call	printhex
	sub	di, 2
	mov	al, ':'
	stosw
	mov	dx, sp
	call	printhex8
	shl	ecx, 4
	add	ecx, edx

	mov	edx, ecx
	call	printhex8

	mov	eax, ecx
	pop	ecx
	pop	edx

	sub	eax, edx
	mov	edx, eax
	jge	0f
	mov	ah, 0x4f
	println "WARNING: Loaded image runs into stack!"
	call	printhex8

0:	mov	ah, 0x3f
	print	"Room after image before stack: "
	call	printhex8
.endif
	pop	eax
	ret

############################################################################


# in: dh = head, dl=drive
# in: cx = cyl=[7:6][15:8] sect=[0:5]
chs_to_lba:
	mov	eax, 0	# TODO
	ret

# in: dl = drive, eax = absolute sector number (LBA-1)
# out:  cx = [7:6][15:8] cyl [5:0] sector,  dh=head, dl=drive
lba_to_chs:
	push	ax
	push	bx
	push	dx	# backup drive number
.if CHS_DEBUG
	push	edx
	push	ax

	.if 1
	#mov	dl, bl
	push ax; mov ah, 0xf0
	print "Drive: "
	call	printhex2
	pop ax
	.endif

	mov	edx, eax
	mov	ah, 0xf0
	print "LBA: "
	call	printhex#8
	print "Sector: "
	inc	edx
	call	printhex#8

	pop	ax
	pop	edx
.endif

	push	ax
	mov	ah, 8	# load CX, DX with drive parameters
	push	es
	push	di
	xor	di, di	# set es:di to 0000:0000 (advised)
	mov	es, di
	int	0x13
	pop	di
	pop	es
	pop	ax
	jc	fail	# stack not empty
	# cx = max cyl/sector
	# dh = max head
	# dl = number of drives

	# shuffle and cleanup
	# spt = sectors per track = bl[0:5]
	# hpc = heads per cylinder= bh
	mov	bx, cx
	shr	bl, 6	# high 2 bits of cyl
	ror	bx, 8	# bx now okay: 000000cc CCCCCCCC
	and	cl, 0b111111
	mov	ch, dh

	# ch = max head
	# cl = max sector
	# bx = max cyl/track
.if CHS_DEBUG
	push ax
	push dx
	mov ah, 0xf9
	print ">>"
	mov dx, bx
	print "C "
	call printhex
	mov dl, ch
	print "H "
	call printhex2
	mov dl, cl
	print "S "
	call printhex2
	pop dx
	pop ax
.endif

	# increment them for division
	#inc	cl	# S: this should not be incremented...
	inc	ch	# H: heads should be incremented (maxhead=1=2 heads)
	#inc	bx

	# dx:ax = lba
	mov	edx, eax
	shr	edx, 16

	# calculate sectors
	push	cx
	xor	ch, ch
	div	cx
	pop	cx
	inc	dx
	# dx = LBA % maxsect + 1 = S
	# ax = LBA / maxsect

	# calculate heads
	# ax (lba / maxsect)  %  ch (maxheads)
	div	ch	# ax / ch -> ah = mod, al = div
	# al = (LBA / maxsect) / maxheads = C
	# ah = (LBA / maxsect) % maxheads = H

	mov	ch, al	# C
	mov	cl, dl	# S
	mov	bh, ah	# H

.if CHS_DEBUG
	mov	ah, 0xf3
	print ">>>"
	print "S "
	call	printhex2

	print "C "
	mov	dl, ch
	call	printhex2

	print "H "
	mov	dl, bh
	call	printhex2
	call	newline
.endif

	pop	dx	# dl = drive
	mov	dh, bh	# dh = H
	pop	bx
	pop	ax
	ret

###################################################
.include "../16/waitkey.s"


get_boot_drive:
	mov	dl, [bootloader_registers + 24]
#	push	bx
#	mov	bx, [bootloader_registers_base]
#	mov	dl, [bx + 24]	# load drive
#	pop	bx
	ret


.include "../16/gdt.s"	# macros and constants
.macro .data16; .data; .endm
.macro .text16; .text; .endm
BOOTLOADER=1
.include "../16/pmode.s"

.data
bootloader_sig: .long 0x1337c0de
