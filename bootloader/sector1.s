# included in bootloader.s
.intel_syntax noprefix

DEBUG_BOOTLOADER = 0	# 0: no keypress. 1: keypress; 2: print ramdisk/kernel bytes.

MULTISECTOR_LOADING = 1	# 0: 1 sector, 1: 128 sectors(64kb) at a time
KERNEL_ALIGN_PAGE = 1	# load kernel at page boundary

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

	mov	si, bp
	mov	di, offset bootloader_registers
	mov	cx, 32 / 4
	rep	movsd

	pop	cx
	pop	si
	pop	di
	pop	ds
	pop	es

	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	println

	mov	dx, 0x1337
	call	printhex

#	call	printregisters

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

#	call	waitkey
#	call	test_unreal
#	mov	ax, 0x0f00
#	call	cls


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

#	mov	ebx, [si + ramdisk_entry_load_end]
mov ebx, [ramdisk_buffer]
	add	si, 16		# ignore entry count and check size
	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	print "Loading symbol table: "
	call	load_ramdisk_entry_hi
	# compact:
	mov	eax, [si + ramdisk_entry_size]
	neg	eax
	and	eax, 0x1ff
	sub	[image_high], eax
1:

	mov	ebx, [si + ramdisk_entry_load_end]
mov ebx, [ramdisk_buffer]
	add	si, 16		# ignore entry count and check size
	cmp	[si + ramdisk_entry_size], dword ptr 0
	jz	1f
	#jmp	1f
	print "Loading stabs: "
	call	load_ramdisk_entry_hi
1:

##############################################
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

	mov	dh, [si+1]	# head
	call	printhex
	mov	cx, [si+2]	# [7:6][15:8] cylinder, [0:5] = sector
	and	cx, 0b111111
	add	cx, SECTORS + 1	# skip bootloader sectors

	movzx	ebx, cx		# calculate memory offset
	shl	ebx, 9
	.data
		ramdisk_address: .long 0
	.text
	mov	[ramdisk_address], ebx
	PRINT	"RAMDISK Memory Address: "
	push	edx
	mov	edx, ebx
	call	printhex8
	push	eax
	mov	eax, ds
	shl	eax, 4
	add	edx, eax
	pop	eax
	print "flat: "
	call	printhex8

	pop	edx
	call	newline

	PRINT	"Reading sector..."

	push	es
	mov	ax, ds
	mov	es, ax
	mov	ax, 0x0201	# read 1 sector
	int	0x13	# in: es:bx
	pop	es
	jc	fail
	mov	ah, 0xf5
	PRINT	"Ok "
	inc	ah

####### Verify RAMDISK Signature

	# this is the 'fat', the sector after sector1.

####### dump signature
	print "SIG:"
	mov	si, [ramdisk_address]
	mov	cx, 8
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

######### first entry: kernel
######### second entry: symbol table
######### third entry: source line numbers

load_ramdisk_kernel:
	print "Loading kernel: "
#####	# prepare load address
	movzx	ebx, word ptr [ramdisk_address]
.if KERNEL_ALIGN_PAGE
	add	ebx, 4095	# page align
	and	ebx, ~4095
.else
	add	bx, 0x200
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
print "copy done"

	.if DEBUG_BOOTLOADER
		mov ah, 0xf0
		call waitkey
		mov ax, 0xf020
		call cls
	.endif

	ret


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
	# if the ramdisk image is loaded consecutively:
	mov	edx, eax
	inc	edx	# account for FAT sector
	add	edx, ecx
	shl	edx, 9

	mov	eax, ds
	shl	eax, 4
	add	edx, eax
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
	call	newline
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

	call	get_boot_drive	# dl = drive
	call	lba_to_chs	# dh = head, cx = cyl/sect

	.if PRINT_LOAD_SECTORS
		push	dx
		mov	ah, 0xf7
		call	printhex
		mov	dx, cx
		call	printhex
		pop	dx
	.endif

	push	es
	mov	eax, ebx	# convert flat ebx to es:bx
	ror	eax, 4
	mov	es, ax
	rol	eax, 4
	and	eax, 0xf
	push	ebx
	mov	bx, ax
	mov	ah, 2		# read sector
	mov	al, [bp]	# nr sectors
	int	0x13
	pop	ebx
	pop	es
TRACE '>'

	jc	fail
	cmp	ax, [bp]
	jne	fail
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

	print	"Entry: Sectors: "
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


# in: dl = drive, eax = absolute sector number (LBA-1)
# out:  cx = [7:6][15:8] cyl [5:0] sector,  dh=head, dl=drive
lba_to_chs:
	push	ax
	push	bx
	push	dx	# backup drive number

	push	ax	
	mov	ah, 8	# load CX, DX with drive parameters
	push	es
	push	di
	xor	di, di
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
	ror	bx, 8	# bx now okay
	and	cl, 0b0011111
	mov	ch, dh

	# ch = max head
	# cl = max sector
	# bx = max cyl/track
	.if 0
	push ax
	push dx
	mov ah, 0xf9
	mov dx, bx
	call printhex
	mov dx, cx
	call printhex
	pop dx
	pop ax
	.endif

	# increment them for division
	#inc	cl	# this should not be incremented...
	inc	ch	# heads should be incremented (maxhead=1=2 heads)
	#inc	bx

	# dx:ax = lba
	ror	eax, 16
	mov	dx, ax
	ror	eax, 16

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

	pop	dx	# dl = drive
	mov	dh, bh	# dh = H
	pop	bx
	pop	ax
	ret

###########
lba_to_chs_debug:
	push	dx	# backup drive number
.if 1
	push	ax
	mov	bl, dl
	mov	edx, eax
	mov ah, 0xf0
	print "LBA: "
	call	printhex#8
	.if 0
	mov	dl, bl
	print "Drive: "
	call	printhex2
	.endif
	pop	ax

	pop	dx
	push	dx
.endif
	push	eax	# load CX, DX with drive parameters
	mov	ah, 8
	push	es
	push	di
	xor	di, di
	mov	es, di
	int	0x13
	pop	di
	pop	es
	jc	fail	# stack not empty!
	pop	eax
	# CX = max cyl/sector
	# DH = max head
	# dl = number of drives

	push	ax
##
	mov	ah, 0xf0
	PRINT	"Drive Params: DX: "
	call	printhex
	xchg	dx, cx
	PRINT	"CX: "
	call	printhex
	xchg	dx, cx

	# shuffle and cleanup
	# spt = sectors per track = bl[0:5]
	# hpc = heads per cylinder= bh
	mov	bx, cx
	shr	bl, 6	# high 2 bits of cyl
	ror	bx, 8	# bx now okay
	and	cl, 0b0011111
	mov	ch, dh

	# ch = max head
	# cl = max sector
	# bx = max cyl/track

	# increment them for division
	inc	cl
	inc	ch
	inc	bx

	print "C/H/S: "
	inc	ah
	mov	dx, bx
	call	printhex
	sub	di, 2
	mov	al, '/'
	stosw
	mov	dl, ch
	call	printhex2
	sub	di, 2
	stosw
	mov	dl, cl
	call	printhex2
##	
	pop	ax
	# dx:ax = lba
	ror	eax, 16
	mov	dx, ax
	ror	eax, 16

	# calculate sectors
	push	cx
	xor	ch, ch
	div	cx
	pop	cx
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
.if 1
	mov	ah, 0xf3
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
	ret


###################################################

.include "../kernel/keycodes.s"

waitkey:
	.data
	msg_press_key$: .asciz "Press a key to continue..."
	.text
	push	si
	push	dx

	mov	si, offset msg_press_key$
	call	print

	push	ax
	xor	ah, ah
	int	0x16
	pop	dx
	xchg	ax, dx	# restore ah
	call	printhex
	call	newline
	mov	ax, dx
	pop	dx
	pop	si
	ret

get_boot_drive:
	mov	dl, [bootloader_registers + 24]
#	push	bx
#	mov	bx, [bootloader_registers_base]
#	mov	dl, [bx + 24]	# load drive
#	pop	bx
	ret


.include "../16/gdt.s"	# macros and constants

.data
backup_gdt_ptr: .word 0; .long 0
backup_idt_ptr: .word 0; .long 0

gdt_ptr:.word gdt_end - gdt -1
	.long gdt
gdt:	.long 0,0
	#.byte 0xff,0xff, 0,0,0, 0b10011010, 0b10001111, 0	# code
	#.byte 0xff,0xff, 0,0,0, 0b10010010, 0b11001111, 0	# data
s_code:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_16#(FLAGS_16|FL_GR4kb)
s_data:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_16#32
s_flat:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32
s_vid:  DEFGDT 0xb8000, 0xffff, ACCESS_DATA, FLAGS_16
gdt_end:

SEL_code = 8
SEL_data = 16
SEL_flat = 24
SEL_vid = 32

#########
idt_ptr: .word idt_end - idt - 1
	.long idt

idt:
.rept 256
	.word 0	# lo 16 bits of offset
	.word 8
	.byte 0
	.byte 0b10000110 # ACC_PR(1<<7)| IDT_ACC_GATE_INT16(0b0110)
	.word 0	# high 16 bits of offset
.endr
idt_end:

backup_ds: .word 0
backup_es: .word 0
.text

enter_pmode:
	push	eax
	push	ecx
	push	edx
	push	esi
	###############################
	# enable A20 line
	in	al, 0x92 # a20
	test	al, 2
	jnz	1f
	or	al, 2
	out	0x92, al
1:

	cli
	# mask NMI
	in	al, 0x70
	or	al, 0x80
	out	0x70, al
	in	al, 0x71

	# mask all PIC signals
#	mov al, ~(1<<2) # IRQ_CASCADE
#	out 0x20+1, al
#	mov al, -1
#	out 0xa0+1, al
	###############################

	mov	[backup_ds], ds
	mov	[backup_es], es

	sgdt	[backup_gdt_ptr]
	sidt	[backup_idt_ptr]

	mov	eax, cs
	shl	eax, 4
	GDT_STORE_SEG s_code

	mov	eax, ds
	shl	eax, 4
	GDT_STORE_SEG s_data

	add	eax, offset gdt
	mov	[gdt_ptr+2], eax

	lgdt	[gdt_ptr]

	# initialize the idt
	mov	eax, cs
	shl	eax, 4
	add	eax, offset pm_idt_table#pm_isr
	mov	si, offset idt
	mov	cx, 256
	mov	edx, eax
	shr	edx, 16
0:	mov	[si + 0], ax
	mov	[si + 8-2], dx
	add	ax, 5
	adc	dx, 0
	add	si, 8
	loop	0b

	mov	eax, ds
	shl	eax, 4
	add	eax, offset idt
	mov	[idt_ptr+2], eax

	lidt	[idt_ptr]

	mov	ax, SEL_data
	mov	ds, ax
	mov	es, ax

	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

	jmp 1f
1:	# 16bit pmode

	.if 1
		push	edi
		mov ax, SEL_flat
		mov es, ax

		mov edi, 0xb8000
		mov ah, 0xf
		mov al, 'P'
		mov es:[edi], ax
		pop	edi
	.endif

	# set the descriptor cache limit to 4Gb
	mov	eax, SEL_data
	mov	ds, eax
	mov	es, eax

	# set vid
	mov	ax, SEL_vid
	mov	es, ax
mov ah, 0xd0
print "PMode"
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret


enter_realmode:
	push	eax
	mov	eax, cr0
	and	al, ~1
	mov	cr0, eax
	jmp 1f
	1:	

	mov	ds, cs:[backup_ds]
	mov	es, [backup_es]

	lgdt	[backup_gdt_ptr]
	lidt	[backup_idt_ptr]

	in al, 0x80
	and al, 0xfe
	out 0x70, al
	in al, 0x71

mov ah, 0xd0
print "Realmode"
	pop	eax
	sti
	ret

unreal_mode:
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi

	call	enter_pmode
mov edx, edi
xor edi,edi
call printhex8
	mov	ah, 0xe0
	print "in protected mode"

	call	enter_realmode
	mov ah, 0xe0
	print "in realmode"

	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax

	ret


# writes an 'U' using 0000:000b8000
test_unreal:
	push	edi
	push	eax
	push	es

	xor	dx, dx
	mov	es, dx
	mov	edi, 0xb8000
	mov	ax, 11<<8 | 'U'
	mov	es:[edi], ax

	pop	es
	pop	eax
	pop	edi
	call	waitkey	# this also prints
	ret


pm_idt_table:
_I=0
.rept 256
	push	word ptr _I
	jmp	pm_isr
	_I = _I+1
.endr

pm_isr:
	push	ebp
	lea	ebp, [esp + 4]
	push	ds
	push	es
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi
	mov	eax, SEL_vid
	mov	es, eax
	mov	eax, SEL_data
	mov	ds, eax

	mov	edi, 160*5

	mov	ah, 0x0f
	print "interrupt "

	mov	dx, [ebp]
	call	printhex2

	print "stack "
	mov	dx, ss
	call	printhex
	mov	al, ':'
	mov	es:[edi-2],ax
	mov	edx, ebp
	call	printhex8
	call	newline

	mov	ecx, 8
	mov	esi, ebp
0:	mov	edx, esi
	call	printhex8
	mov	edx, ss:[esi]
	add	esi, 2
	call	printhex
	call	newline
	loop	0b

	movzx	eax, word ptr [ebp]
	mov	edx, 0b00100111110100000000
	bt	edx, eax
	mov	ah, 0x0f
	jnc	1f

	print	"ErrCode "
	mov	edx, [ebp+2]
	add	ebp, 4
	call	printhex8

1:
	print "cs "
	mov	edx, [ebp + 2]
	call	printhex8
	print "eip "
	mov	edx, [ebp + 2+4]
	call	printhex8
	print "flags "
	mov	edx, [ebp + 2+8]
	call	printhex8

	0: hlt; jmp 0b

	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	pop	es
	pop	ds
	pop	ebp
	add	sp, 2
	iret
