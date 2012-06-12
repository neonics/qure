# The BootSector
#
# Includes sector1, determines size, and loads it using the MBR data.
.intel_syntax noprefix

# Layout:
# 0000-0200: sector 0. Only .text used. subsections/.data prohibited.
# 0200-....: all allowed.

.equ RELOCATE, 1
.equ BLACK_PRINT_REGISTERS, 0

.equ WHITE, 1
.equ WHITE_PRINT_HELLO, 0
.equ WHITE_PRESSKEY, 0
.equ WHITE_PRINTREGISTERS_PRINT_FLAGS, 0


.equ INCLUDE_SECTOR1, 1
#######################################################

.text
.code16
black:	
###################################################################
relocate$:
.if RELOCATE
LOAD_ADDR = 0x10000
LOAD_SEG =  (LOAD_ADDR >> 4 )
LOAD_OFFS= 0 # the base address (16 bit offset) for which the binary is coded

	mov	di, LOAD_SEG
	mov	es, di
	#mov	ds, di
	mov	di, LOAD_OFFS
	call	0f
0:	pop	si
	sub	si, 0b - black
	mov	cx, 512
	rep	movsb
	jmp	LOAD_SEG, (offset 0f) + LOAD_OFFS
0:
.endif
###################################################################


# ss:sp points to the end of the first sector.
	# backup sp
	#mov	sp, 512	# make it so, regardless of bios
	mov	cs:[sp_bkp$], sp
	#mov	cs:[ss_bkp$], ss
	.if 1
	# have the stack before cs:0000
	mov	sp, cs
	sub	sp, 65536 >> 4
	mov	ss, sp
	mov	sp, 0xfffe	# word alignment
	.else
	# set up stack at cs:0xF000
	mov	sp, cs
	mov	ss, sp
	mov	sp, 512	# use the 0xaa55 signature
	call	0f
0:	pop	sp
	and	sp, ~0xff
	add	sp, 0xF000 + (CODE_SIZE - black) & ~ 0xff
	.endif
	call	1f
0:
halt:	hlt
	jmp	halt

sp_bkp$:.word 0
ss_bkp$:.word 0

regnames$:
.ascii "cs"	# 0
.ascii "ds"	# 2
.ascii "es"	# 4
.ascii "fs"	# 6
.ascii "gs"	# 8
.ascii "ss"	# 10

.ascii "fl"	# 12

.ascii "di"	# 14
.ascii "si"	# 16
.ascii "bp"	# 18
.ascii "sp"	# 20
.ascii "bx"	# 22
.ascii "dx"	# 24
.ascii "cx"	# 26
.ascii "ax"	# 28
.ascii "ip"	# 30

.ascii "c.p.a.zstidoppn."

1:
# result:
# 1337
# FA11
# cs:0000 ds:0000 fs:0000 gs:0000 ss:0000 fl:0206
# di:7BE0 si:000E bp:0000 sp:7BFE bx:00E0 dx:00E0 cx:0100 ax:AA55 ip:7C03

# cs:ip = 0:7C03
# ds = (ip - 3 ) >> 4
# sp runs into the code, end of segment
# 
	# use the value on stack as ip register
	pusha
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# set up ds for lodsb, do not assume loaded at 0x7c00
	mov	bp, sp 
	mov	bx, ss:[bp + 30]	# load ip
	sub	bx, 0b - black		# adjust start
DBG0 = 0

.if DBG0
	mov	dx, bx
.endif
	mov	ss:[bp + 30], bx	# restore
	shr	bx, 4			# convert to segment
	mov	ax, cs
	add	bx, ax
	mov	ds, bx
	# now, offsets are relative to the code. This requires that no base
	# address (or 0) is specified when creating the binary.

	# restore sig$ as it is used as stack for the first call
	mov	word ptr [sig$], 0xaa55
	mov	ax, [sp_bkp$]
	mov	[bp + 20], ax

	# assume nothing
	push	0xb800		# set up screen
	pop	es
	xor	di, di
	mov	ah, 0x0f
.if DBG0
	call	printhex
	mov	dx, bx
	call	printhex
.endif
	mov	dx, 0x1337	# test screen
	call	printhex

	call	newline
.if BLACK_PRINT_REGISTERS
	mov	bx, sp
	inc	ah
	sar	ah, 1 	# color

	mov	si, offset regnames$
	mov	cx, 16	# 6 seg 9 gu 1 flags 1 ip

0:	lodsb
	stosw
	lodsb
	stosw
	mov	al, ':'
	stosw

	mov	dx, ss:[bx]
	add	bx, 2
	call	printhex

	cmp	cx, 10
	jne	1f
	call	newline
1: 	loopnz	0b
	call	newline
.endif


.if WHITE
	jmp	white	# keep registers on stack
.else
	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popa
	ret
.endif

############################################################################

.if WHITE

printregisters:
	pusha
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs

	# assume es:di is valid

	call	newline
	mov	bx, sp

	mov	si, offset regnames$
	mov	cx, 16	# 6 seg 9 gu 1 flags 1 ip

0:	mov	ah, 0xf0
	lodsb
	stosw
	lodsb
	stosw

	mov	ah, 0xf8
	mov	al, ':'
	stosw

	mov	ah, 0xf1
	mov	dx, ss:[bx]
	add	bx, 2

	call	printhex

	cmp	cx, 10
	jne	1f

.if WHITE_PRINTREGISTERS_PRINT_FLAGS
	# print flag characters
	push	bx
	push	si
	push	cx

	mov	si, offset regnames$ + 32 # flags
	mov	cx, 16
2:	lodsb
	mov	bl, dl
	and	bl, 1
	jz	3f
	add	al, 'A' - 'a'
3:	shl	bl, 1
	add	ah, bl
	stosw
	sub	ah, bl
	shr	dx, 1
	loop	2b
	
	pop	cx
	pop	si
	pop	bx
.endif

	call	newline

1: 	loopnz	0b

	call	newline

	pop	ax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popf
.if 0
	mov	[tmp_di$], di
	popa
	mov	di, [tmp_di$]
	ret
tmp_di$: .word 0
.else
	pop	ax	# manual pop to preserve di
	pop	si
	pop	bp
	pop	ax	# ignore sp
	pop	bx
	pop	dx
	pop	cx
	pop	ax
	ret
.endif

.if WHITE_PRESSKEY
msg_presskey$: .asciz "Press Key"
.endif
# stack setup at 0:0x9c00
# sp is 32 bytes below that, pointing to the registers starting
# with ip, the return address of the 1337 loader, which then simply
# halts.
white: 	
	#cli
.if WHITE_PRESSKEY
	mov	si, offset msg_presskey$
	call	print
	xor	ah, ah
	int	0x16
.endif
	# bp = sp = saved registers ( 9BE0; top: 9C00 = 7C00 + 2000 )

	mov	ax, 0xf000
	call	cls	# side effect: set up es:di to b800:0000

.if WHITE_PRINT_HELLO
      printhello$:
	inc	ah
	mov	si, offset hello$
	call	print
	
.endif
.if 0
	mov	ah, 0xf4

	mov	dx, sp
	call	printhex
	mov	dx, bp
	call	printhex

	mov	dx, offset CODE_SIZE	# 268h
	call	printhex

     rainbow$:
	call	newline
	mov	ax, 0x00 << 8 | 254
	mov	cx, 4
1:	push	cx
	mov	cx, 256 / 4
0:	stosw
	inc	ah
	loop	0b
	pop	cx
	call	newline
	loop	1b
.endif

	mov	ah, 0xf8
	call	printregisters

	mov	dx, [bp+24]	# load dx - boot drive
	call	printhex

preparereadsector$:
	# reset drive, retry loop
	mov	cx, 3
0:	xor	ah, ah
	int	0x13
	jnc	0f
	loop	0b
0:


	# calculate nr of sectors to load
.equ LOADBYTES, CODE_SIZE - sector1$
.equ PARTIALSECTOR, (LOADBYTES & 0x1ff > 0) * -1	
.global SECTORS
.equ SECTORS, (LOADBYTES >> 9) + PARTIALSECTOR
loadsectors$:
##############
#	push	dx
#	mov	ah, 0xf4
#	mov	dx, 0x10ad
#	call	printhex
#	mov	dx, SECTORS
#	call	printhex
#	pop	dx
###############

.if 0
	mov	cx, 0x0002	# cyl 0, sector 2! offset 200h in img
	xor	dh, dh		# head 0
.else

# find bootable partition
	mov	si, offset mbr
	mov	cx, 4
0:	test	[si], byte ptr 0x80
	jnz	1f
	add	si, 16 # partition table size - 1
	loop	0b
	jmp	fail
1:
	mov	dh, [si + 1] # [chs_start$]
	mov	cx, [si + 2] # [chs_start$+1]
	mov	bx, 512	
	mov	ax, (2 << 8) + 1# ah = 02 read sectors al = # sectors
	test	byte ptr [si], 1
	jz	0f
	mov	al, SECTORS	
	inc	cl	# skip bootsector itself
0:
	call	printregisters
.endif
	push	es	# set up es:bs
	push	ds
	pop	es	
	int	0x13		# load sector to es:bx
	pop	es

	jc	fail

	mov	dx, ax
	mov	ah, 0xf6
	call	printhex

.if 0	# dump sector 1
	inc	ah
	mov	si, offset sector1$
	mov	cx, 8
0:	mov	dx, ds:[si]
	call	printhex
	add	si, 2
	loop	0b
.endif
	#mov	dx, 0xcafe
	#call	printhex

.if INCLUDE_SECTOR1
	jmp 	sector1$
.else
	jmp	halt
.endif

fail:	push	ax
	push	dx
	push	ax		# save bios result code
	mov	ah, 0xf4
	mov	dx, 0xfa11
	call	printhex
	mov	ah, 0xf2
	pop	dx		# restore bios result code
	call	printhex
	pop	dx
	pop	ax

	call	printregisters
	jmp	halt

.endif # WHITE


BOOTSECTOR=1
.include "../16/print.s"
############################################################################

.EQU bs_code_end, .

data:
	hello$: .asciz "Hello!"

#. = 440
#	.ascii "MBR$"
. = 446	# 0x1be
mbr:

# CHS2LBA( C, H, S ) = (MaxHeadPerCyl * C + H) * MaxSectPerTrack + S - 1

# LBA2CHS( LBA ) = {	C = LBA / ( MaxSectPerTrack * MaxHeadsPerCyl ),
#			H = ( LBA / MaxSectPerTrack )  % MaxHeadsPerCyl ),
#			S = ( LBA % MaxSectPerTrack ) + 1

	# 4 entries, int 13 call format:
			# 81 is invalid, bit 1 is used to mark partition
			# table bootsector (not MBR). When bit 1 = 0,
			# chainloading occurs. (untested)
	status$:	.byte 0x81	# 80 bootable, 00 not bootable
	chs_start$:	.byte 0, 1, 0	# [dh, cl, ch]: head, sector, cylinder
	part_type$:	.byte 6		# partition type
	chs_end$:	.byte 0x0e,0xbe,0x94	# [dh, cl, ch]
	lba_first$:	.long 0x3e	# 
	numsec$:	.byte 0x0c, 0x61, 0x09, 0x00

	# the other 3 partition table entries are zeroed
. = 512 - 2
sig$:	.byte 0x55, 0xaa	# the value is required during boot,
					# and with VirtualBox the first push
					# will overwrite this value.
					# ax contains aa55 already,
					# so restore to make writebootsect
					# work.

#############################################################################
. = 512
BOOTSECTOR = 0

.if INCLUDE_SECTOR1

sector1$:

.include "sector1.s"

.endif

.data	# we need the entire size, including data! .data after .code..
.equ CODE_SIZE, .
