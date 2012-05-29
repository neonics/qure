.intel_syntax noprefix
.code32

FS_DEBUG = 0

.struct 0
mtab_mountpoint:	.long 0
mtab_flags:		.word 0
mtab_disk:		.byte 0
mtab_partition:		.byte 0
mtab_partition_info:	.long 0
MTAB_FLAG_PARTITION = 1
.data
MTAB_ENTRY_SIZE = 16
MTAB_INITIAL_ENTRIES = 1
mtab: .long 0
.text

mount_init$:
	mov	ebx, [mtab]
	or	ebx, ebx
	jz	0f
	ret
0:	mov	eax, MTAB_ENTRY_SIZE * MTAB_INITIAL_ENTRIES
	call	buf_new
	mov	[mtab], eax
	mov	ebx, eax


	# add root entry
	call	mtab_entry_alloc$

	mov	eax, 2
	call	mallocz
	mov	[eax], word ptr '/'
	mov	[ebx + edx], eax

.if 0
	call	mtab_entry_alloc$

	mov	eax, 10
	call	malloc
	mov	[ebx + edx + mtab_mountpoint], eax
	mov	[eax], byte ptr '/'
	mov	[eax+1], byte ptr 'a'
	mov	[eax+2], byte ptr 0

	mov	[ebx + edx + mtab_flags], dword ptr 1
.endif
	ret


# in: ebx = mtab base ptr
# out: edx = index guaranteed to hold one mtab entry
# side-effect: index increased to point to next.
mtab_entry_alloc$:
	mov	edx, [ebx + buf_index]
	cmp	edx, [ebx + buf_capacity]
	jb	0f
	.if FS_DEBUG
		printc 10, "mtab grow "
		call	printhex8
		push	edx
		mov	edx, ebx
		call	printhex8
		call	newline
		pop	edx
	.endif
	
	push	eax
	mov	eax, ebx
	add	edx, MTAB_ENTRY_SIZE
	call	buf_resize
	mov	[mtab], eax
	mov	ebx, eax
	pop	eax
	mov	edx, [ebx + buf_index]
0:	add	[ebx + buf_index], dword ptr MTAB_ENTRY_SIZE
	.if FS_DEBUG
		printc 10, "mtab_entry_alloc "
		call	printdec32
		printchar ' '
		push	edx
		mov	edx, ebx
		call	printhex8
		pop	edx
		call	newline
	.endif
	ret

# in: ebx = base ptr
# in: edx = entry to release
mtab_entry_free$:
	mov	eax, [ebx + edx]
	call	mfree
	# delete the entry from the list
	add	edx, MTAB_ENTRY_SIZE
	cmp	edx, [ebx + buf_capacity]
	jae	0f
	mov	esi, edx
	mov	edi, edx
	sub	edi, MTAB_ENTRY_SIZE
	add	esi, ebx
	add	edi, ebx
	mov	ecx, MTAB_ENTRY_SIZE
	rep	movsb
0:	sub	[ebx + buf_index], dword ptr MTAB_ENTRY_SIZE
	ret


cmd_mount$:
	call	mount_init$

	# check cmd arguments
	lodsd
	lodsd
	or	eax, eax
	jz	mtab_print$

	# if second argument missing, print usage
	cmp	dword ptr [esi], 0
	jz	5f

	# if more than 2 arguments, print usage
	cmp	dword ptr [esi + 4], 0
	jz	5f

	# parse first argument
	call	mtab_parse_partition_label$
	jc	6f

	# load the partition table for the disk
	call	disk_get_partition	# eax = pointer to partition info
	jc	4f

	call	mtab_entry_alloc$
	mov	[ebx + edx + mtab_partition_info], eax

	push	edx
	printc 10, "LBA start: "
	mov	edx, [eax + PT_LBA_START]
	call	printhex8
	printc 10, " sectors: "
	mov	edx, [eax + PT_SECTORS]
	call	printhex8
	printc 10, " LBA end: "
	add	edx, [eax + PT_LBA_START]
	dec	edx
	call	printhex8
	printc 10, " Type: "
	mov	dl, [eax + PT_TYPE]
	call	printhex2
	call	newline
	pop	edx

	mov	eax, [esi]
	call	strdup
	mov	[ebx + edx + mtab_mountpoint], eax
	mov	[ebx + edx + mtab_flags], word ptr 1
	
	ret

4:	printlnc 12, "invalid disk/partition"
6:	ret

5:	pushcolor 12
	println  "usage: mount [<partition> <mountpoint>]"
	println  "  partition:  hda1, hdb4, .... "
	println  "  mountpoint: /path"
	popcolor
	ret

# in: eax = pointer to 'hda0' type string
# out: al = drive, ah = partition
mtab_parse_partition_label$:
	push	edx
	push	esi
	push	eax	# for error message

	mov	esi, eax
	lodsw
	cmp	ax, ('d'<<8)|'h'
	jnz	2f

	lodsb
	sub	al, 'a'
	js	3f
	cmp	al, 25
	ja	3f
	mov	dl, al
	
	# now, parse the partition. might be two decimals (extended etc..)
	mov	eax, esi
	call	atoi
	jc	4f
	cmp	eax, 255
	ja	1f
	shl	eax, 8
	mov	al, dl

	print "disk "
	movzx	edx, al
	call	printdec32
	print " partition "
	movzx	edx, ah
	call	printdec32
	call	newline

	clc
0:	pop	esi	# for error message
	pop	esi
	pop	edx
	ret
4:	LOAD_TXT "partition string not number"
	jmp	5f
3:	LOAD_TXT "drive number not lowercase alpha"
	jmp	5f
2:	LOAD_TXT "not starting with 'hd'"
	jmp	5f
1:	LOAD_TXT "invalid partition number"
5:	pushcolor 12
	print	"parse error: '"
	push	esi
	mov	esi, [esp + 4 + 2]
	call	print
	pop	esi
	print	"': "
	call	println
	popcolor
	stc
	jmp	0b

mtab_print$:
	xor	ecx, ecx
0:	cmp	ecx, [ebx + buf_index]
	jae	0f
	test	word ptr [ebx + ecx + mtab_flags], MTAB_FLAG_PARTITION
	jz	1f
	print	"hd"
	mov	al, [ebx + ecx + mtab_disk]
	add	al, 'a'
	call	printchar
	movzx	edx, byte ptr [ebx + ecx + mtab_partition]
	call	printdec32
	jmp	2f
1:	print	"none"
2:	print " on "
	mov	esi, [ebx + ecx + mtab_mountpoint]
	call	print
	call	newline

	add	ecx, MTAB_ENTRY_SIZE
	jmp	0b
0:	ret


cmd_umount$:
	printlnc 4, "umount: not implemented"
	ret

fs_mount:
	ret

fs_unmount:
	ret
