# included in bootloader.s
.intel_syntax noprefix

.text
.code16
. = 512
.data
bootloader_registers_base: .word 0
msg_sector1$: .asciz "Transcended sector limitation!"
.text
	mov	[bootloader_registers_base], bp

	mov	ah, 0xf3
	mov	si, offset msg_sector1$
	call	println

	mov	dx, 0x1337
	call	printhex

	call	printregisters

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

	call	newline
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
	jb	0f
	mov	ah, 0xf4
	print "More than 31 entries!"
0:
	cmp	dx, 1
	je	0f
	print "MULTIPLE ENTRIES - Choosing first"
0:
	call	newline

#####	prepare load address
	xor	ebx, ebx
	mov	bx, [ramdisk_address]
	add	bx, 0x200

	push	bx
	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	add	ebx, eax
	.data
		chain_addr_flat: .long 0
	.text
	mov	[chain_addr_flat], ebx
	pop	bx
#####

	# si:
	# 0: start low dword, start high dword
	# 8: count low dword, count high dword

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
	jmp	fail
0:	shr	eax, 9		# convert to sectors
	add	eax, SECTORS + 1


	#call	cls

	# ds:bx = load offset  [chain_addr_flat] = ds<<4+bx
	# ecx = sectors to load
	# eax = sector on disk

	push	ax
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
	mov	dx, ds
	call	printhex
	sub	di, 2
	mov	al, ':'
	stosw
	mov	dx, bx
	call	printhex
	call	newline
	pop	ax

####
	push	eax
	mov	edx, eax
	add	edx, ecx
	shl	edx, 9
	mov	ah, 0xf2
	call	printhex8

	push	edx
	xor	edx, edx
	mov	dx, sp
	call	printhex8
	mov	eax, edx
	pop	edx

	sub	eax, edx
	mov	edx, eax
	jge	0f
	mov	ah, 0x4f
	print "WARNING: Loaded image runs into stack!"
	call	printhex8

0:	mov	ah, 0x3f
	print	"Room after image before stack: "
	call	printhex8
	pop	eax

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
mov dx, bx
call printhex
call newline
pop ax
	inc	ecx
################################# load loop
0:	push	ecx		# remember sectors to load
	push	eax		# remember offset

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

	mov	ax, 0x0201 	# read 1 sector (dont trust multitrack)
	push	es
	push	ds
	pop	es
	int	0x13
	pop	es

	jc	fail
	cmp	ax, 1
	jne	fail

	add	bx, 0x200
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

	# bx points to end of loaded data (kernel)
################################# end load loop
	mov	ah, 0xf6
	println	"Success!"


.if 0
	mov	si, [ramdisk_address]
	add	si, 0x200
	mov	cx, 10
0:
	lodsd
	mov	edx, eax
	mov	ah, 0xf9
	call	printhex8
	loop	0b
.endif	

	mov	ah, 0xf0
	print "Chaining to next: "
	mov	edx, [chain_addr_flat]
	shr	edx, 4
	call	printhex
	println ":0000"

	# set up some args:
	call	get_boot_drive	# dl = drive
	mov	si, [partition]	# pointer to MBR partition info
	mov	cx, [ramdisk_address]
				# bx = end of kernel

	push	dx
	PRINT	"dl: boot drive: "
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
	mov	dx, bx
	call	printhex
	call	newline

	pop	dx

	call	waitkey

	mov	eax, [chain_addr_flat]
	shr	eax, 4
	push	ax
	push	word ptr 0
	retf

.if 0 ###########################
0:	#call	cls
	call	waitkey
	cmp	ax, K_ESC
	je	1f
	cmp	al, 'q'
	jne	0b	
1:	PRINT "System Halt."
	jmp	halt
.endif ##############################

#############################################################################


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
	push	bx
	mov	bx, [bootloader_registers_base]
	mov	dl, [bx + 24]	# load drive
	pop	bx
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

	mov	bx, [bootloader_registers_base]
	mov	dl, [bx + 24]	# load drive

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

