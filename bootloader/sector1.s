# included in bootloader.s
.intel_syntax noprefix

DEBUG_BOOTLOADER = 0	# 0: no keypress. 1: keypress; 2: print ramdisk/kernel bytes.

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

####### Read RAMDISK sector

	call	get_boot_drive

	mov	dh, [si+1]	# head
	call	printhex
	mov	cx, [si+2]	# [7:6][15:8] cylinder, [0:5] = sector
	add	cx, SECTORS + 1	# skip sectors

	mov	bx, cx		# calculate memory offset
	shl	bx, 9
	.data
		ramdisk_address: .word 0
	.text
	mov	[ramdisk_address], bx
	call	newline
	PRINT	"RAMDISK Memory Address: "
	push	dx
	mov	dx, bx
	call	printhex
	pop	dx
	call	newline

	PRINT	"Reading sector..."

	mov	ax, 0x0201	# read 1 sector
	push	es
	push	ds
	pop	es
	int	0x13
	pop	es
	jc	fail
	mov	ah, 0xf5
	PRINT	"Ok. "
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
	PRINT	"Ramdisk detected"
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
#	mov	si, ]
	push ecx
	push eax
	push edx
	mov	cx, 16
0:	lodsd
	mov	edx, eax
	mov	ah, 0xf9
	call	printhex8
	loop	0b
	pop edx
	pop eax
	pop ecx
	pop	si
.endif	

######### first entry: kernel
	print "Loading kernel: "
#####	# prepare load address
	xor	ebx, ebx
	mov	bx, [ramdisk_address]
	add	bx, 0x200

	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	add	ebx, eax
	.data
		chain_addr_flat: .long 0 # load offset = ds<<4+bx
	.text
	mov	[chain_addr_flat], ebx
#####	# ebx = flat start address
push ax
push dx
mov ah, 0xf0
mov dx, si
call printhex
pop dx
pop ax

	call	load_ramdisk_entry

push ax
push dx
mov ah, 0xf0
mov dx, si
call printhex
pop dx
pop ax
print "<<<<"

.if DEBUG_BOOTLOADER > 1	# dump head of kernel
	push	si
	#mov	si, [ramdisk_address]	# still so
	mov	cx, 8
0:
	lodsd
	mov	edx, eax
	mov	ah, 0xf9
	call	printhex8
	loop	0b
	pop	si
.endif

.if DEBUG_BOOTLOADER > 1	# dump head of kernel
	push	si
	# dump head of kernel
#	add	si, 0x200 - 16*4
	mov si, [ramdisk_address]
	add si, 0x200
	mov	cx, 4
0:
	lodsd
	mov	edx, eax
	mov	ah, 0xf8
	call	printhex8
	loop	0b
	pop	si
.endif	

######### second entry: symbol table
	add	si, 16		# ignore entry count and check size
	mov	ecx, [si + 8]
	mov ah, 0xf3
	mov edx, ecx
	call printhex8
	jcxz	0f
	mov	ebx, [si - 4]	# get the load end address of the previous segment
	mov edx, ebx
	mov ah, 0x0b
	call printhex8
	call	load_ramdisk_entry
0:


	mov	ah, 0xf0
	print "Chaining to next: "
	mov	edx, [chain_addr_flat]
	call	printhex8
	shr	edx, 4
	call	printhex
	sub	di, 2
	println ":0000"

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

		call	waitkey
	.endif

	call	newline

	# far jump:
	mov	eax, [chain_addr_flat]
	ror	eax, 4
	push	ax
	rol	eax, 4
	and	ax, 0xf
	push	ax
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

# in: ebx = memory pointer where image will be loaded.
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
	mov	[si + 12], edx	# image end address (start+count)*512+ds*16

	mov	ah, 0xf2
	print	"image load end: "
	call	printhex8
	call	newline
##
	pop	eax
	# edx = image load end (flat address + count sectors * 512)
	call	print_ramdisk_entry_info$

.if 0
	push es
	push ax
	push cx
	call cls
	pop cx
	pop ax
	pop es
.endif
push ax
mov ah, 0xf2
mov dx, ds
call printhex
mov es:[di-2], byte ptr ':'
mov edx, ebx
call printhex8
call newline
pop ax

	inc	ecx
################################# load loop
0:	push	ecx		# remember sectors to load
	push	eax		# remember offset

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
	.if 0
		call	debug_13_es_bx$
	.endif
	mov	ax, 0x0201 	# read 1 sector (dont trust multitrack)
	int	0x13
	pop	ebx
	pop	es
TRACE '>'

	jc	fail
	cmp	ax, 1
	jne	fail

TRACE 'c'

	add	ebx, 0x200

	mov	dx, ax
	mov	ax, 0xf2<<8|'.'
	stosw

	.if !PRINT_LOAD_SECTORS
	#add	di, 2
	.else
	call	newline
	.endif

	pop	eax
	pop	ecx
	inc	eax
TRACE 'd'
	.if 0
	push ax
	mov dx, ax
	mov ah, 0xf8
	call printhex
	mov dx, cx
	call printhex
	pop	ax
	.endif

	loop	0b
TRACE '*'
	# bx points to end of loaded data (kernel)
################################# end load loop
	mov	ah, 0xf6
	print	"Success!"
	mov	edx, ebx
	call	printhex8
	call	newline

	ret

# eax = sector on disk
# ebx = load offset  [chain_addr_flat] = ds<<4+bx
# ecx = sectors to load
print_ramdisk_entry_info$:
	push	eax
	mov	edx, eax
	mov	ah, 0xf1

	print	"Entry 1: Start(S): "
	call	printhex8

	print	"Count (S): "
	mov	edx, ecx
	call	printhex8

	print	"Flat addr: "
	mov	edx, [chain_addr_flat]
	call	printhex8

	push	edx
	shr	edx, 4
	call	printhex
	mov	es:[di - 2], byte ptr ':'
	pop	edx
	and	dx, 0xf
	mov	ah, 0xf1
	call	printhex
	call	newline

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

.if 0 #disabled since stack is before kernel
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

	mov	ah, 0x2f
	print	"Load region: "
	mov	edx, ebx
	call	printhex8
	push	edx
	xor	edx, edx
	mov	eax, 0x200
	mul	ecx
	mov	edx, eax
	add	edx, ebx
	mov	ah, 0x2f
	call	printhex8
	pop	edx

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


.if 0
	call	init_bios_extensions
	.data
	dap:		.word 0x10 # size of packet - 0x18 for 64 bit address
	dap_numblocks:	.word 0	# max 7f
	dap_buffer:	.long 0
	dap_blocknr:	.quad 0 # 8 bytes, 4 words, 
	#dap_qaddr: .quad 0 # 64 bit flat addr if dword dap_buffer=-1
	.text
	mov	ax, si
	add	ax, 512
	mov	[dap_buffer], ax
	mov	[dap_buffer+2], ds


	lodsd
	mov	[dap_blocknr], eax
	lodsd
	mov	[dap_blocknr + 4], eax
	lodsd
	mov	[dap_blocknr], ax

	mov	si, offset dap
	mov	ah, 0x42	# extended read
	int	0x13
	jc	fail
.endif
init_bios_extensions:
	PRINT	"BIOS int 13h Extensions "

	call	get_boot_drive

	mov	ah, 0x41	# check IBM/MS extensions (LBA)
	mov	bx, 0x55aa
	int	0x13
	jne	0f
	cmp	bx, 0xaa55
	jne	0f

	mov	dl, ah
	mov	ah, 0xf3
	PRINT	"Installed: "

	call	printhex2
	mov	dl, dh
	call	printhex2
	shr	cl, 1
	jnc	1f
	print	"ExtDisk "
1:	shr	cl, 1
	jnc	1f
	print	"Removable "
1:	shr	cl, 1
	jnc	1f
	print	"EDD"
1:	call	newline
	ret

0: 	#### no ext bios, use CHS
	mov	ah, 0xf4
	PRINTLN "Not installed, emulating"
	stc
	ret


