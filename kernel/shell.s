.intel_syntax noprefix

.data 2
cmdlinelen: .long 0
cmdline: .space 1024
cmdline_tokens_end: .long 0
cmdline_tokens: .space 4096
insertmode: .byte 1
cursorpos: .long 0
.text
.code32

shell:	push	ds
	pop	es
	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

	mov	[cwd$], word ptr '/'
	mov	[insertmode], byte ptr 1

start$:
	mov	esi, offset cwd$
	call	print
	printc 15, "> "

	mov	dword ptr [cursorpos], 0
	mov	dword ptr [cmdlinelen], 0

0:
	call	print_cmdline$

	mov	edi, offset cmdline
	add	edi, [cursorpos]

	xor	ax, ax
	call	keyboard
	.if 0
	pushcolor 10
	push	ax
	mov	dx, ax
	call	printhex4
	mov	al, ' '
	call	printchar
	mov	al, dl
	call	printchar
	mov	al, ' '
	call	printchar
	pop	ax
	popcolor
	.endif

	cmp	ax, K_ESC
	jz	clear$

	cmp	ax, K_ENTER
	jz	enter$

	cmp	ax, K_BACKSPACE
	jz	bs$

	cmp	ax, K_LEFT
	jz	left$
	cmp	ax, K_RIGHT
	jz	right$

	cmp	ax, K_INSERT
	jz	toggleinsert$

	cmp	al, 127
	jae	0b	# ignore
	cmp	al, 32
	jb	0b	# ignore
	
1:	#cmp	byte ptr [insertmode], 0
	#jz	insert$
	# overwrite
#insert$:
	# overwrite
	cmp	[cmdlinelen], dword ptr 1024-1	# check insert
	# beep
	jb	1f	
	# beep
	jmp	0b
1:	
	cmp	byte ptr [insertmode], 0
	jz	1f
	# insert
	push	edi
	mov	edi, [cursorpos]
	mov	ecx, [cmdlinelen]
	sub	ecx, edi
	add	edi, offset cmdline
	mov	esi, edi
	inc	edi
	rep movsb
	pop	edi
1:	# overwrite
	stosb
	inc	dword ptr [cursorpos]
	inc	dword ptr [cmdlinelen]

	jmp	0b

enter$:	
	PRINT_START
	add	edi, [cursorpos]
	add	edi, [cursorpos]
	xor	es:[edi + 1], byte ptr 0xff
	PRINT_END
	call	newline

	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$
DEBUG_TOKENS = 0
	.if DEBUG_TOKENS
	PRINTc 9, "CMDLINE: \""
	mov	esi, offset cmdline
	call	nprint
	PRINTLNc 9, "\""
	mov	edx, ecx
	call	printhex8
	call	newline
	.endif

	push	ecx
	mov	edi, offset cmdline_tokens
	mov	esi, offset cmdline
	#mov	ecx, [cmdlinelen]
	call	tokenize
	mov	[cmdline_tokens_end], edi
	.if DEBUG_TOKENS
	mov	ebx, edi
	mov	esi, offset cmdline_tokens
	call	printtokens
	.endif
	pop	ecx

	#call	process_tokens

	.macro GET_TOKEN nr
		lea	esi, [cmdline_tokens +16 +  8 * \nr ]

		cmp	[cmdline_tokens_end], esi
		jb	9f	# jb = jc
		sub	esi, 16
		.if DEBUG_TOKENS
		jmp	8f
	9:	PRINTc 4, "No such token \nr - max tokens: "
		mov	edx, [cmdline_tokens_end]
		sub	edx, offset cmdline_tokens
		shr	edx, 3
		call	printhex
		call	newline
		stc
	8:	
		.else
	9:	
		.endif
	.endm



	.macro GET_TOKEN_STRING nr
		mov	esi, offset cmdline_tokens  + 8 * \nr + 16

		cmp	[cmdline_tokens_end], esi
		jb	9f	# jb = jc
		sub	esi, 12
		mov	ecx, [esi + 8]
		mov	esi, [esi]
		sub	ecx, esi
		.if DEBUG_TOKENS
		jmp	8f
	9:	PRINTc 4, "No such token \nr - max tokens: "
		mov	edx, [cmdline_tokens_end]
		sub	edx, offset cmdline_tokens
		shr	edx, 3
		call	printhex
		call	newline
		stc
	8:	
		.else
	9:	
		.endif
	.endm

	.macro IS_TOKEN tok
		.data
		9: .ascii "\tok"
		8: 
		.text

		mov	esi, offset cmdline_tokens + 4
		mov	ecx, [esi+8]
		mov	esi, [esi]
		sub	ecx, esi
		cmp	ecx, 8b - 9b
		jne	1f
		mov	edi, offset 9b
		repz	cmpsb
		1:
	.endm

	IS_TOKEN "ls"
	jnz	1f
	printlnc 11, "Directory Listing."
	xor	eax, eax
	call	ls$
	jmp	start$
1:
	IS_TOKEN "cluster"
	jnz	1f
	mov	eax, 2
	call	ls$
	jmp	start$
1:
	IS_TOKEN "cd"
	jnz	1f
	call	cd$
	jmp	start$
1:
	IS_TOKEN "pwd"
	jnz	1f
	mov	esi, offset cwd$
	call	println
	jmp	start$
1:
	IS_TOKEN "cls"
	jnz	1f
	call	cls
	jmp	start$
1:
	IS_TOKEN "fdisk"
	jnz	1f
	call	fdisk$
	jmp	start$
1:
	IS_TOKEN "partinfo"
	jnz	1f
	call	partinfo$
	jmp	start$
1:
	IS_TOKEN "quit"
	jnz	1f
	printlnc 12, "Terminating shell."

	mov	edx, esp
	call	printhex8

	xor	eax, eax
	call	keyboard
	ret

1:	PRINTLNc 4, "Unknown command"
	jmp	start$

bs$:	
	push	edi
	cmp	edi, offset cmdline 
	jbe	0b
	cmp	edi, [cmdlinelen]
	jz	1f
	mov	esi, edi
	dec	edi
	mov	ecx, 1024 + offset cmdline
	sub	ecx, esi
	jz	2f
	rep	movsb
2:	pop	edi


1:	dec	dword ptr [cursorpos]
	jns	1f
	printc 4, "Error: cursorpos < 0"
1:
	dec	dword ptr [cmdlinelen]
	jns	1f
	PRINTlnc 4, "Error: cmdlinelen < 0"
1:	jmp	0b

left$:	dec	dword ptr [cursorpos]
	jns	start$
	inc	dword ptr [cursorpos]
	jmp	start$

right$:	mov	eax, [cursorpos]
	cmp	eax, [cmdlinelen]
	jae	start$
	inc	dword ptr [cursorpos]
	jmp	start$

clear$:	mov	ax,(7<<8)| ' '
	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$
	PRINT_START
	push	edi
	inc	ecx
1:	stosw	#call	printchar
	loop	1b
	pop	edi
	PRINT_END
	jmp	0b # start$

toggleinsert$:
	xor	byte ptr [insertmode], 1
	jmp	start$

# destroys: ecx, esi, ebx
print_cmdline$:
	push	esi
	push	ecx
	push	ebx

	PRINT_START
	push	edi

	mov	ebx, edi
	mov	ecx, [cmdlinelen]
	jecxz	2f
	mov	esi, offset cmdline

1:	lodsb
	stosw
	loop	1b

2:	mov	al, ' '
	stosw
	stosw

	add	ebx, [cursorpos]
	add	ebx, [cursorpos]
	xor	es:[ebx+1], byte ptr 0xff

	pop	edi
	PRINT_END

	pop	ebx
	pop	ecx
	pop	esi

	ret

.data
cmdline_identifier: .byte ALPHA, DIGIT, '_', '.'
cmdline_id_size = . - cmdline_identifier
CMDTOK_ID = 1
CMDTOK_PATH = 2
.text

# merge tokens
process_tokens:
	mov	esi, offset cmdline_tokens
	xor	edx, edx
0:	lodsd
	cmp	eax, -1
	jz	1f

	# check for identifier tokens
	mov	edi, offset cmdline_identifier
	mov	ecx, cmdline_id_size
	repne	scasb
	jnz	2f

id$:	shl	dx, 8
	mov	dl, CMDTOK_ID
	println "Identifier"

	cmp	dl, dh
	jz	0b
	PRINT "End token: "
	ror	dx, 8
	call	printhex2
	ror	dx, 8
	jmp	3f

2:	cmp	al, '\\'
	jnz	2f
2:

3:	lodsd
	jmp	0b

1:
	ret


######################################
cd$:	
	mov	ebx, [fat_root_lba$]
	or	ebx, ebx
	jnz	0f
	call	partinfo$
0:	
	#########

	call	cd_apply$
	jc	0f

	inc	ecx

	mov	ebp, ecx	# remember len
	mov	ebx, esi

	# attempt to change the directory
	# parse it again, this time just using path separators:

	mov	edi, esi
	mov	al, '/'

1:	repne	scasb
	jnz	1f
	mov	edx, ecx
	call	printhex8
	printchar ' '

	push	ecx
	mov	ecx, edi
	sub	ecx, esi
	call	nprint
	call	newline

#########################
	push	edi
	push	ebx
	push	ebp

	push	esi
	push	ecx

	# now find what lba to load.
	
	cmp	ecx, 1
	jnz	2f
	mov	ebx, [fat_root_lba$]
	jmp	3f
2:	
	# find the directory entry
	dec	ecx
	call	fat_find_dir	# esi ecx
	# returns ebx = cluster



3:	mov	edi, offset tmp_buf$
	mov	ecx, 1
	mov	al, [tmp_drv$]
	call	ata_read	# ebx=lba
	jc	2f

	##



	##


	clc
2:	pop	ecx
	pop	esi

	pop	ebp
	pop	ebx
	pop	edi
#########################
	pop	ecx
	jc	0f
	mov	esi, edi



	jmp	1b
1:


	mov	ecx, ebp
	mov	esi, ebx

	mov	edi, offset cwd$
	rep	movsb
	xor	al, al
	stosb

0:	ret

# in: cwd$, cmdline_tokens as prepared by tokenize
# out: carry flag = syntax error
# out: cd_cwd$ is new commandline
# out: ecx length of commandline (when CF is clear) (minus trailing /)
# out: esi offset of commandline (cd_cwd$) (when CF is clear)
# destroys: eax ebx ecx edx esi edi
cd_apply$:
	push	dword ptr -1	# alloc state
	# copy cwd
	.data 2
	cd_cwd$: .space 1024
	.text
	mov	esi, offset cwd$
	mov	edi, offset cd_cwd$
	mov	ecx, 1024
	rep	movsb

	# scan for end of string
	mov	edi, offset cd_cwd$
	xor	al, al
	mov	ecx, 1024
	repne scasb
	dec	edi

	mov	ebx, 2
0:	mov	[edi], byte ptr 0
	inc	dword ptr [esp]


	.if 0
		pushcolor 10
		mov	edx, 1024
		sub	edx, ecx
		call	printdec32
		mov	al, ' '
		call	printchar
		mov	edx, edi
		mov	esi, offset cd_cwd$
		sub	edx, esi
		call	printdec32
		call	println
		popcolor
	.endif

#	GET_TOKEN ebx
#	jc	0f

	lea	esi, [cmdline_tokens + 8 * ebx ]
	cmp	[cmdline_tokens_end], esi
	jbe	0f
	inc	ebx

	lodsd	# al = type
	mov	ecx, [esi + 8]
	mov	esi, [esi]
	sub	ecx, esi 
	jbe	0f

	.if 0
		pushcolor 3
		mov	edx, ebx
		call	printdec32
		printchar ':'
		mov	edx, ecx
		call	printdec32
		printchar ' '
		mov	edx, esi
		call	printhex8
		printchar ' '
		call	nprint
		call	newline
		popcolor
	.endif

	# Check whether it is a valid path-element token
	.data
	num_path_tokens$: .long path_token_handler_idx$ - path_tokens$
	path_tokens$: .byte ALPHA, DIGIT, '-', '_', '.', '/'
	path_token_handler_idx$: .byte 0, 0, 0, 0, 1, 2
	# NOTE: there is no symbol relocation so code offsets need
	# to be adjusted by [realsegflat]
	path_token_handlers$: .long cd_a$, cd_dot$, cd_slash$
	.text

	mov	edx, offset num_path_tokens$
	call	get_token_handler
	jnz	cd_syntax_error$
	jmp	edx


cd_syntax_error$:
	PRINTc 4, "Syntax error at token "
	call	nprint
	call	newline
	mov	al, -1
	jmp	9f

cd_a$:	rep	movsb	# append / overwrite
	jmp	0b

cd_dot$:dec	ecx	# use nr of '.' as levels up
	jz	0b
	# scan backward for /
	dec	edi
	std
2:	mov	al, '/'
	dec	edi
	push	ecx
	mov	ecx, edi
	sub	ecx, offset cd_cwd$
	jbe	3f
	repne	scasb
	inc	edi
3:	pop	ecx
	loop	2b
	cld
	jmp	0b

cd_slash$:
	cmp	dword ptr [esp], 0
	jnz	1f
	mov	edi, offset cd_cwd$
1:	stosb
	jmp	0b


0:	cmp	edi, offset cd_cwd$ + 1
	je	0f
	mov	[edi], word ptr '/'
0:	mov	esi, offset cd_cwd$	# return offset

	.if 0
	call	println
	.endif

	mov	ecx, edi
	sub	ecx, esi

	xor	al, al

9:	add	esp, 4
	shl	al, 1	# al -1 on error, sets carry
	ret	


#############
	.data 2
	tmp_drv$: .byte 0
	tmp_buf$: .space 512 * 2
	.text
partinfo$:
	mov	al, TYPE_ATA
	call	ata_find_first_drive
	jns	1f

 	PRINTLNc 10, "No ATA drive found"
	ret
1:
	mov	[tmp_drv$], al

	# load bootsector/MBR

	mov	edi, offset tmp_buf$
	mov	ecx, 2
	mov	ebx, 0
	call	ata_read
	jc	read_error$

	# find partition

	mov	esi, offset tmp_buf$ + 446
	mov	ecx, 4

0:	cmp	[esi + 0xc], dword ptr 0	# num sectors
	jz	1f
	# ok, check if partition type supported:

	mov	al, [esi + 4]	# partition type
	cmp	al, 6		# FAT16B
	jz	ls_fat16b$



1:	add	esi, 16
	loop	0b
	PRINTLNc 4, "No recognizable partitions found (run fdisk)"
	ret

# Partition Table
.struct 0
PT_STATUS: .byte 0
PT_CHS_START: .byte 0,0,0
PT_TYPE: .byte 0
PT_CHS_END: .byte 0,0,0
PT_LBA_START: .long 0
PT_SECTORS: .long 0

.data 2
tmp_part$: .long 0
fat$: .space 512
.text
ls_fat16b$:
	mov	[tmp_part$], esi	# save partition table ptr
	mov	eax, [esi + 8]	# LBA start
	mov	ebx, eax
	mov	ecx, 1
	mov	al, [tmp_drv$]
	mov	edi, offset fat$
	call	ata_read
	jc	read_error$

	# VBR - Volume Boot Record

	# Print BIOS Parameter Block - BPB

	mov	esi, offset fat$ + 3
	PRINTc 15, "OEM Identifier: "
	mov	ecx, 8
	call	nprint
	call	newline

	mov	esi, offset fat$ + 11

	.macro BPB_B label
		PRINTc 15, "\label: 0x"
		lodsb
		mov	dl, al
		call	printhex2
		call	newline
	.endm

	.macro BPB_W label
		PRINTc 15, "\label: 0x"
		lodsw
		mov	dx, ax
		call	printhex4
		call	newline
	.endm

	.macro BPB_D label
		PRINTc 15, "\label: 0x"
		lodsd
		mov	edx, eax
		call	printhex8
		call	newline
	.endm

	BPB_W "Bytes/Sector"
	BPB_B "Sectors/Cluster"
	BPB_W "Reserved sectors" # includes boot record
	BPB_B "FATs" 
	BPB_W "Directory Entries"
	BPB_W "Total Sectors"	 # max 64k, 0 for > 64k
	BPB_B "Media Descriptor Type"
	BPB_W "Sectors/FAT" # Fat12/16 only
	BPB_W "Sectors/Track"
	BPB_W "Heads"
	BPB_D "Hidden Sectors / LBA start"
	BPB_D "Total Sectors (large)"
	println "EBPB:" # for fat12 and fat16; fat32 is different
	BPB_B "Drive Number"
	BPB_B "NT Flags"	# bit 0 = run chkdsk, bit 1 = run surface scan
	BPB_B "Signature (0x28 or 0x29)"
	BPB_D "Volume ID Serial"
	PRINTc 15, "Volume Label: "
	push esi
	mov	ecx, 11
	call	nprint
	pop esi
	add esi, 11
	call	newline

	PRINTc 15, "System Identifier: "
	push esi
	mov	ecx, 8
	call	nprint
	pop esi
	# check whether fat16/fat12
	lodsd
	cmp	eax, ('F'<<24) | ('A'<<16) | ('T'<< 8) | '1'
	lodsd
	jnz	0f
	cmp	eax, (0x20202000)|'6'
	jz	0f
1:	PRINTLNc 4, "Warning: System identifier unknown (not FAT16)"
0:
	#add	esi, 8
	call	newline

.struct 11
BPB_BYTES_PER_SECTOR: .word 0
BPB_SECTORS_PER_CLUSTER: .byte 0	# power of 2, max 128 (2^7)
BPB_RESERVED_SECTORS: .word 0
BPB_FATS: .byte 0
BPB_ROOT_ENTRIES: .word 0
BPB_SMALL_SECTORS: .word 0	# 0 for > 64k, see LARGE_SECTORS
BPB_MEDIA_DESCRIPTOR: .byte 0
BPB_SECTORS_PER_FAT: .word 0
BPB_SECTORS_PER_TRACK: .word 0
BPB_HEADS: .word 0
BPB_HIDDEN_SECTORS: .long 0
BPB_LARGE_SECTORS: .long 0
.text
	# verify
	mov	esi, offset fat$
	mov	ebx, [tmp_part$]

	mov	eax, [ebx + PT_LBA_START]
	cmp	eax, [esi + BPB_HIDDEN_SECTORS]
	jz	0f
	PRINTLNc 4, "Error: Partition Table LBA start != BPB Hidden sectors"
0:	
	movzx	eax, word ptr [esi + BPB_SMALL_SECTORS]
	or	eax, eax
	jnz	1f
	mov	eax, [esi + BPB_LARGE_SECTORS]
1:	cmp	eax, [ebx + PT_SECTORS]
	jz	0f
	PRINTLNc 4, "Error: Partition table numsectors != BPB num sectors"
0:

	mov	dl, [esi + BPB_FATS]
	or	dl, dl
	jnz	0f
	PRINTLNc 4, "Error: Number of FATS in BPB is zero"
0:	cmp	dl, 2
	jbe	0f
	PRINTc 4, "WARNING: more than 2 fats: 0x"
	call	printhex2
	call	newline
0:

	.data
	fat_lba$: .long 0
	fat_clustersize$: .long 0	# sectors per cluster
	fat_sectorsize$: .long 0	# 0x200
	fat_sectors$: .long 0		# sectors per fat
	fat_root_lba$: .long 0
	fat_user_lba$: .long 0
	.text
	## Calculate start of first FAT
	movzx	eax, word ptr [esi + BPB_RESERVED_SECTORS]
	add	eax, [esi + BPB_HIDDEN_SECTORS]	# LBA start
	# this should point to the first sector after the partition boot record

	mov	[fat_lba$], eax

	# now we add sectors per fat:
	movzx	edx, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[fat_sectors$], edx
	movzx	ecx, byte ptr [esi + BPB_FATS]
0:	add	eax, edx
	loop	0b
	# movzx eax, [esi+BPB_SECTORS_PER_FAT]
	# movzx edx, byte ptr [esi+BPB_FATS]
	# mul edx
	# add eax, [fat_lba$]

	# now eax points just after the fat, which is where
	# the root directory begins.
	mov	[fat_root_lba$], eax

	# now we add the size of the root directory to it.
	movzx	edx, word ptr [esi + BPB_ROOT_ENTRIES]
	# and we multiply it by the size of directory entries: 32 bytes.
	shl	edx, 5
	add	eax, edx
	mov	[fat_user_lba$], eax

	movzx	eax, byte ptr [esi + BPB_SECTORS_PER_CLUSTER]
	mov	[fat_clustersize$], eax
	movzx	eax, word ptr [esi + BPB_SECTORS_PER_FAT]
	mov	[fat_sectorsize$], eax


	PRINTc 10, "FAT LBA: "
	mov	edx, [fat_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Root Directory: "
	mov	edx, [fat_root_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline

	PRINTc 10, "FAT Userdata LBA: "
	mov	edx, [fat_user_lba$]
	call	printhex8
	PRINTc 10, "  Offset: "
	shl	edx, 9
	call	printhex8
	call	newline
	ret

.struct 0
FAT_DIR_NAME: .space 11	# 8 + 3
FAT_DIR_ATTRIB: .byte 0 # RO=1 H=2 SYS=4 VOL=8 DIR=10 A=20  (0F=long fname)
	.byte 0 # reserved by NT
	# creation time
FAT_DIR_CTIME_DECISECOND: .byte 0 # tenths of a second
FAT_DIR_CTIME: .word 0	# Hour: 5 bits, minuts 6 bits, seconds 5 bits
FAT_DIR_CDATE: .word 0 # year 7 bits, month 4 bits, day 5 bits
FAT_DIR_ADATE: .word 0 # last accessed date
FAT_DIR_HI_CLUSTER: .word 0 # 0 for fat12/fat16
FAT_DIR_MTIME: .word 0 # modification time
FAT_DIR_MDATE: .word 0
FAT_DIR_CLUSTER: .word 0
FAT_DIR_SIZE: .long 0	# filesize in bytes

.struct 0 # Long file name entries are placed immediately before the 8.3 entry
FAT_DIR_LONG_SEQ: .byte 0 # sequence nr; 0x40 bit means it is last also
FAT_DIR_LONG_NAME1: .space 10	# 5 2-byte chars
FAT_DIR_LONG_ATTRIB: .byte 0 # 0xf for long filenames
FAT_DIR_LONG_TYPE: .byte 0	# 0 for name entires
FAT_DIR_LONG_CKSUM: .byte 0
FAT_DIR_LONG_NAME2: .space 12 # 6 2-byte characteres
	.word 0 # always 0
FAT_DIR_NAME3: .space 4	# final 2 2-byte characters (total: 5+6+2=13)



fat_find_dir:
	ret

.data 2
cwd$:	.space 1024
.text

ls$:	mov	ebx, [fat_root_lba$]
	or	ebx, ebx
	jnz	lsdir$
	call	partinfo$
	mov	ebx, [fat_root_lba$]
lsdir$:	mov	edi, offset tmp_buf$
	mov	ecx, 1
	mov	al, [tmp_drv$]
	call	ata_read
	jc	read_error$

	mov	esi, offset tmp_buf$
0:	
	cmp	byte ptr [esi], 0
	jz	0f
	PRINT	"Name: "
	mov	ecx, 11
	call	nprint

	PRINT	" Attr "
	mov	dl, [esi + FAT_DIR_ATTRIB]
	call	printhex2
	.data
		9: .ascii "RHSVDA78"
	.text
	mov	ebx, offset 9b
	mov	ecx, 8
1:	mov	al, ' '
	shr	dl, 1
	jnc	2f
	mov	al, [ebx]
2:	call	printchar
	inc	ebx
	loop	1b
	

	PRINT	" Cluster "
	mov	dx, [esi + FAT_DIR_CLUSTER]
	call	printhex4

	PRINT	" Size: "
	mov	edx, [esi + FAT_DIR_SIZE]
	call	printdec32
	call	newline

	add	esi, 32
	cmp	esi, 512 + offset tmp_buf$	# overflow check
	jb	0b
0:
mov	esi, -1
mov	edi, esi
mov	ebx, esi
mov	edx, esi
	ret


#######################
write_boo:
	mov	al, TYPE_ATA
	call	ata_find_first_drive
	jns	1f

 	PRINTLNc 10, "No ATA drive found"
	ret
1:
	PRINTc	10, "Writing bootsector to ATA drive: "
	mov	dl, al
	call	printhex2
	call	newline

# Read data:

	mov	[tmp_drv$], al

	mov	edi, offset tmp_buf$
	mov	ecx, 2
	mov	ebx, 0
	call	ata_read
	jnc	0f
	PRINTLNc 4, "ATA read error"
	ret
0:	PRINTLN "ATA read OKAY"
	
	mov	esi, offset tmp_buf$ + 512
	mov	ecx, 10
0:	lodsb
	call	printchar
	mov	dl, al
	mov	al, ' '
	call	printchar
	call	printhex2
	mov	al, ' '
	call	printchar
	loop	0b

	call	newline

####
.if 0
	.data 2
	tmp_buf2$: .asciz "Hello World! First ATA sector written!"
	.space 512 - (.-tmp_buf2$)
	.asciz "second sector"
	.space 512
	.text
	PRINTln "ATA WRITE"
	mov	al, [tmp_drv$]
	mov	dl, al
	call	printhex2
	call	newline

	mov	esi, offset tmp_buf2$
	mov	ecx, 2
	mov	ebx, 0
	call	ata_write
.endif
	ret


############################

fdisk$:	mov	al, TYPE_ATA
	call	ata_find_first_drive
	jns	1f
 	PRINTLNc 10, "No ATA drive found"
	ret

1:	
	PRINTc  9, "Listing drive "
	mov	dl, al
	call	printhex2
	call	newline

	mov	edi, offset tmp_buf$
	mov	ecx, 1
	mov	ebx, 0
	call	ata_read
	jc	read_error$

fdisk_check_parttable$:
	# check for bootsector
	mov	dx, [tmp_buf$ + 512 - 2]
	cmp	dx, 0xaa55
	je	1f
	PRINTLNc 10, "No Partition Table"
	ret

1:	mov	esi, offset tmp_buf$ + 446	# MBR offset
	COLOR 7
	xor	cl, cl

	PRINTLN	"Part | Stat | C/H/S Start | C/H/S End | Type | LBA Start | LBA End | Sectors  |"
	COLOR 8
0:	
	xor	edx, edx
	PRINT " "
	mov	dl, cl		# partition number
	call	printhex1
	PRINTc  7, "   | "

	lodsb			# Status
	mov	dl, al
	call	printhex2
	PRINTc	7, "   | "

DEBUG_CHS = 0
	.macro PRINT_CHS
	.if DEBUG_CHS
		mov dl, [esi]
		call printhex2
		mov al, '-'
		call printchar
		mov dl, [esi+1]
		call printhex2
		mov al, '-'
		call printchar
		mov dl, [esi+2]
		call printhex2
		mov al, ' '
		call printchar
	.endif

	mov	dl, [esi + 1]	# 2 bits of cyl, 6 bits sector
	shl	edx, 2
	mov	dl, [esi + 2]	# 8 bits of cyl
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex4
		popcolor
	.endif
	mov	al, '/'
	call	printchar

	xor	dh, dh
	lodsb			# head
	mov	dl, al
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex2
		popcolor
	.endif
	mov	al, '/'
	call	printchar

	lodsb
	inc	esi
	mov	dl, al
	and	dl, 0b111111
	call	printdec32
	.if DEBUG_CHS
		pushcolor 15
		call printhex2
		popcolor
	.endif

	.endm

	PRINT_CHS		# CHS start
	PRINTc	7, "     | "

	lodsb		# partition type
	mov	ah, al
	
	PRINT_CHS		# CHS end
	PRINTc	7, "  | "

	mov	dl, ah		# Type
	call	printhex2
	PRINTc	7, "   | "

	lodsd			# LBA start
	mov	edx, eax
	call	printhex8
	PRINTc	7, "  | "

	mov	eax, [esi - 16 + 5 + 4]	# LBA end
	and	eax, 0xffffff
	call	chs_to_lba
	mov	edx, eax
	call	printhex8
	PRINTc	7, "| "

	lodsd			# Num Sectors
	mov	edx, eax
	call	printhex8
	PRINTLNc 7, " |"



	# verify LBA start
	mov	eax, [esi - 16 + 1]
	and	eax, 0xffffff
	mov	edx, eax
	call	chs_to_lba
	mov	edx, eax
	mov	eax, [esi - 16 + 8]
	cmp	edx, eax
	jz	1f
	PRINTc 4, "ERROR: CHS/LBA start mismatch: expect "
	call	printdec32
	PRINTc 4, ", got "
	mov	edx, eax
	call	printdec32
	call	newline
1:
	# if sectorcount zero, dont perform check
	cmp	dword ptr [esi - 4], 0
	jz	1f

	# verify num sectors:
	mov	eax, [esi - 16 + 5] # chs end
	and	eax, 0xffffff
	call	chs_to_lba
	inc	eax

	# subtract LBA start
	sub	edx, eax	# lba start - lba end
	neg	edx
	mov	eax, [esi - 16 + 0xc] # load num sectors
	cmp	eax, edx
	jz	1f
	PRINTc 4, "ERROR: CHS/LBA numsectors mismatch: expect "
	#call	printdec32
	call	printhex8
	PRINTc 4, ", got "
	mov	edx, eax
	#call	printdec32
	call	printhex8
	call	newline
1:

	inc	cl
	cmp	cl, 4
	jb	0b

####
	# CHS start 1/1/0
	# CHS end 0f/ff/f6 -> H = 0f  CS = fff6 -> C = 3ff S = 6
	ret

# in: eax = [00] [Cyl[2] Sect[6]] [Cyl] [head]
# this format is for ease of loading from a partition table
chs_to_lba:
	# LBA = ( cyl * maxheads + head ) * maxsectors + ( sectors - 1 )
	# cyl: 1024
	# head: 16
	# sect: 64
	.if DEBUG_CHS
		pushcolor 5
	.endif
	and	eax, 0xffffff
	jnz	0f	# when CHS = 0, also return LBA 0 (as CHS 0 is invalid)
	ret
0:

	push	edx
	push	ebx

			# 0 CS C H
	ror	eax, 8	# H 0 CS C
	xchg	al, ah	# H 0 C CS

	mov	edx, eax
	.if DEBUG_CHS
		pushcolor 11
		call printhex8
		popcolor
	.endif

	xor	edx, edx
	mov	dx, ax
	shr	dh, 6		# dx = cyl
	.if DEBUG_CHS
		PRINTCHAR 'C'
		call	printhex8
	.endif

	shl	edx, 4	# * maxheads (16)
	.if DEBUG_CHS
		pushcolor 3
		call printhex4
		popcolor
	.endif
	mov	ebx, eax
	shr	ebx, 24	# ebx = bl = head
	add	edx, ebx
	.if DEBUG_CHS
		PRINT " H"
		push edx
		mov	edx, ebx
		call	printhex8
		pop edx
	.endif

	mov	ebx, edx	# * 63:
	shl	edx, 6	# * max sectors (64)
	sub	edx, ebx
	.if DEBUG_CHS
		pushcolor 3
		call printhex4
		popcolor
	.endif

	mov	bl, ah
	and	ebx, 0b111111
	add	edx, ebx
	.if DEBUG_CHS
		PRINT " S"
		push edx
		mov	edx, ebx
		call	printhex8
		pop edx
		PRINTCHAR ' '
	.endif

	dec	edx
	mov	eax, edx

	pop	ebx
	pop	edx
	.if DEBUG_CHS
		popcolor
	.endif
	
	ret

read_error$:
	PRINTLNc 10, "ATA Read ERROR"
	stc
	ret

	.if 0 # works...
		movzx	edx, word ptr [esi + FAT_DIR_CLUSTER]
		push	edx
		movzx	edx, byte ptr [esi + FAT_DIR_ATTRIB]
		push	edx
		push	dword ptr 2
		push	esi
		push	dword ptr 11
		PUSH_TXT "Name: %.*s  Attr: %*x  Cluster: %x\n"
		call	printf
		add	esp, 4 * 6
	.endif

			.if 0 # doesnt seem to work
			push	esi
			push dword ptr [cmdline_tokens_end]
			push	dword ptr offset cmdline_tokens
			PUSH_TXT "Token offset start: %x  end %x token \nr calc: %x\n"
			call	printf
			add	esp, 3 * 4
			.endif


			.if 0 # works

			mov	al, '<'
			pushcolor 3
			mov	edx, offset cmdline_tokens
			call	printhex8
			call	printchar
			mov	edx, esi
			call	printhex8
			call	printchar
			mov	edx, [cmdline_tokens_end]
			call	printhex8
			popcolor

			.endif
