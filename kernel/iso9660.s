##############################################################################
# ISO 9660 File System
#
# DOC/Specs/ATAPI-INF-8020.pdf
# DOC/Specs/ATAPI-INF-8090.pdf
# DOC/Specs/Rockridge.pdf
# DOC/Specs/Systems Use P1281.pfg
# DOC/Specs/bootcdrom.pdf
.intel_syntax noprefix

ISO9660_DEBUG = 0

ISO9660_CACHE_ROOT_DIR = 0

##############################################################################
# Volume descriptor ID's:
ISO9660_VOLDESC_BOOT		= 0
ISO9660_VOLDESC_PRIMARY		= 1	# iso9660_pvd_
ISO9660_VOLDESC_ENHANCED	= 2
ISO9660_VOLDESC_PARTITION	= 3

##############################################################################
# ISO9660 Primary Volume Descriptor structure
.struct 0
iso9660_pvd_id:				.byte 0		# 0	id 1
iso9660_pvd_standard_id:		.space 5	# 1	'CD001'
iso9660_pvd_version:			.byte 0		# 6	version 1
					.byte 0		# 7	unused
iso9660_pvd_system_id: 			.space 32	# 8..39
iso9660_pvd_volume_id: 			.space 32	# 40..71
					.space 8	# 72..79 unused
iso9660_pvd_volume_space_size:		.long 0,0	# 80..87 lsb, msb
					.space 32	# 88..119 unused
iso9660_pvd_volume_set_size:		.word 0,0	# 120..123 lsb, msb
iso9660_pvd_volume_seq_nr:		.word 0,0	# 124..127 lsb, msb
iso9660_pvd_logical_block_size:		.word 0,0	# 128..131 lsb, msb
iso9660_pvd_path_table_size:		.long 0,0	# 132..139 lsb, msb
iso9660_pvd_path_table_location_lsb:	.long 0		# 140..143
iso9660_pvd_path_table_opt_location_lsb:.long 0		# 144..147
iso9660_pvd_path_table_location_msb:	.long 0		# 148..151
iso9660_pvd_path_table_opt_location_msb:.long 0		# 152..155
iso9660_pvd_root_dir_record:		.space 34	# 156..189

##############################################################################
# ISO9660 Path Table Record (applies to both lsb/msb versions)
.struct 0
iso9660_ptr_dir_name_len:	.byte 0
iso9660_ptr_ext_attr_len:	.byte 0
iso9660_ptr_extent_location:	.long 0
iso9660_ptr_parent_dir_nr:	.word 0
iso9660_ptr_dir_name:
# struct length: word_align( 8 + [iso9660_ptr_dir_name_len] )

##############################################################################
# ISO9660 Directory Record (lsb and msb fields; msb fields are ", 0")
.struct 0
iso9660_dr_record_len:		.byte 0		#0
iso9660_dr_ext_attr_len:	.byte 0		#1
iso9660_dr_extent_location:	.long 0, 0	#2..9 lsb, msb
iso9660_dr_data_len:		.long 0, 0	#10..17 lsb, msb
iso9660_dr_rec_datetime:	.space 7	#18..24
iso9660_dr_file_flags:		.byte 0		#25
  DR_FLAG_NON_FINAL_RECORD = 128
  DR_FLAG_PROTECTION = 16
  DR_FLAG_RECORD = 8
  DR_FLAG_ASSOCIATED = 4
  DR_FLAG_DIRECTORY = 2
  DR_FLAG_HIDDEN = 1
iso9660_dr_file_unit_size:	.byte 0		#26
iso9660_dr_interleave_gap_size:	.byte 0		#27
iso9660_dr_volume_seq_nr:	.word 0, 0	#28..31 lsb, msb
iso9660_dr_dir_name_len:	.byte 0		#32
iso9660_dr_dir_name:
# struct length: word_align( 32 + [iso9660_dr_dir_name_len] )

##############################################################################
.data
fs_iso9660_class:
STRINGPTR "iso9660"
.long fs_iso9660_mount
.long fs_iso9660_umount
.long fs_iso9660_open
.long fs_iso9660_close
.long fs_iso9660_nextentry
.long fs_iso9660_read

##############################################################################
.struct FS_OBJ_STRUCT_SIZE
iso_prim_vol_desc:	.long 0
iso_path_table:		.long 0
iso_path_table_size:	.long 0
.if ISO9660_CACHE_ROOT_DIR
iso_root_dir:		.long 0
iso_root_dir_size:	.long 0
.endif
ISO9660_STRUCT_SIZE = .

##############################################################################
.text32

# in: ax = disk(al)/partition(ah)
# in: esi = partition info - ignored
# out: edi = pointer to filesystem structure
fs_iso9660_mount:
	movzx	edx, al
	cmp	byte ptr [ata_drive_types + edx], TYPE_ATAPI
	jnz	1f

	push	eax
	mov	eax, ISO9660_STRUCT_SIZE
	call	mallocz
	mov	edi, eax
	pop	eax
	jc	9f

	mov	[edi + fs_obj_disk], ax
	mov	[edi + fs_obj_class], dword ptr offset fs_iso9660_class

	call	atapi_read_capacity # in: al; out: edx:eax, ecx=blocklen, ebx=lba
	jc	9f

	mov	[edi + fs_obj_p_end_lba], ebx
	mov	[edi + fs_obj_p_size_sectors], ebx
	mov	[edi + fs_obj_sector_size], ecx

	# Read Primary Volume Descriptor
	mov	eax, ecx # block len
	call	mallocz
	jc	8f
	mov	[edi + iso_prim_vol_desc], eax

	push	edi
	mov	ebx, 16	# LBA
	mov	ecx, 1 	# sectors
	mov	al, [edi + fs_obj_disk]
	mov	edi, [edi + iso_prim_vol_desc]
	call	atapi_read12$
	pop	edi
	jc	7f

	call	iso9660_verify$
	jc	7f

	# load path table
	mov	eax, [esi + iso9660_pvd_path_table_size]
	mov	[edi + iso_path_table_size], eax
	movzx	ecx, word ptr [esi + iso9660_pvd_logical_block_size]
	dec	ecx	# assume its a power of 2 for easy bitmasking
	add	eax, ecx
	not	ecx
	and	eax, ecx
	add	eax, 2	# add extra bytes for end of buffer check (ptr_dir_name_len)
	call	mallocz
	jc	7f
	mov	[edi + iso_path_table], eax

	mov	ebx, [esi + iso9660_pvd_path_table_location_lsb]
	mov	al, [edi + fs_obj_disk]
	push	edi
	mov	edi, [edi + iso_path_table]
	push	esi
	call	atapi_read12$
	pop	esi
	pop	edi
	jc	6f

.if ISO9660_CACHE_ROOT_DIR
	lea	edx, [esi + iso9660_pvd_root_dir_record]
	mov	eax, [edx + iso9660_dr_data_len]
	mov	[edi + iso_root_dir_size], eax
	mov	eax, edi		# fs struct, preserve for return
	call	iso9660_load_dir$	# in: eax, ebx; out: ebx
	jc	6f
	mov	[eax + iso_root_dir], ebx
.endif
9:	ret

# error: deallocate buffers
# in: edi = fs_struct
6:	mov	eax, [edi + iso_path_table]
	call	mfree
7:	mov	eax, [edi + iso_prim_vol_desc]
	call	mfree
8:	mov	eax, edi
	call	mfree
	printlnc 4, "iso9660_mount: read error"
	stc
	ret

1:	printlnc 12, "iso9660_mount: only ATAPI supported at this time"
	stc
	ret



######################################################
fs_iso9660_umount:
	printlnc 12, "iso9660_umount: not implemented"
	stc
	ret


######################################################
# in: eax = pointer to fs_instance structure
# in: ebx = parent directory handle (-1 for root)
# in: esi = asciz directory name
# in: edi = fs dir entry struct (to be filled in)
# out: ebx = directory/file handle
fs_iso9660_open:
	.if ISO9660_DEBUG
		printc 12, "iso9660_open"
		call	print
		DEBUG_DWORD ebx
		call	newline
	.endif
##################################################################
	cmp	ebx, -1
	jnz	1f
	cmp	word ptr [esi], '/'
.if ISO9660_CACHE_ROOT_DIR
	mov	ebx, [eax + iso_root_dir]
	jz	9f
.else
	mov	edx, [eax + iso_prim_vol_desc]
	lea	edx, [edx + iso9660_pvd_root_dir_record]
	jz	2f
.endif

1:
	call	iso9660_find_entry$	# in: eax, esi, ebx; out: ebx
	jc	9f

	mov	edx, ebx
	call	iso9660_make_fs_entry$
	test	byte ptr [edx + iso9660_dr_file_flags], DR_FLAG_DIRECTORY
	jnz	2f
	mov	ebx, [edx + iso9660_dr_extent_location]
	jmp	9f

2:	call	iso9660_load_dir$
9:	ret


######################################################
# in: ebx = filehandle
# in: edi = fs dir struct entry
fs_iso9660_close:
	cmp	ebx, -1
	jz	9f
	test	byte ptr [edi + fs_dirent_attr], FS_DIRENT_ATTR_DIR
	jz	9f	# it's an extent (lba sector)
.if ISO9660_CACHE_ROOT_DIR
	cmp	ebx, [eax + iso_root_dir]
	jz	9f
.endif
	push	eax
	mov	eax, ebx
	call	mfree
	pop	eax
9:	ret



######################################################
# in: eax = fs info
# in: ebx = dir handle
# in: ecx = cur entry
# in: edi = fs dir entry struct
# out: ecx = next entry (-1 for none)
# out: edx = directory name
fs_iso9660_nextentry:
	cmp	ecx, -1
	jnz	1f
	inc	ecx
1:

	#mov	edx, [eax + iso_root_dir]
.if ISO9660_CACHE_ROOT_DIR
	cmp	ebx, -1
	jnz	0f
	cmp	ecx, [eax + iso_root_dir_size]
	jae	1f
	mov	ebx, [eax + iso_root_dir]
.endif
0:	lea	edx, [ebx + ecx]
	cmp	byte ptr [edx + iso9660_dr_record_len], 0
	jz	1f

	.if ISO9660_DEBUG > 1
		push esi
		debug "offset"
		debug_dword ecx
		push ecx
		movzx ecx, byte ptr [edx + iso9660_dr_dir_name_len]
		debug "dirnamelen"
		DEBUG_DWORD ecx
		lea esi, [edx + iso9660_dr_dir_name]
		call nprint
		mov ecx, [edx + iso9660_dr_data_len]
		debug "datalen"
		debug_dword ecx
		debug "ext"
		mov ecx, [edx + iso9660_dr_extent_location]
		debug_dword ecx
		call newline
		call more
		pop ecx
		pop esi
	.endif
	call	iso9660_make_fs_entry$

		.if 0
		push	esi
		movzx	esi, byte ptr [edx + iso9660_dr_dir_name_len]
		add	esi, offset iso9660_dr_dir_name
		add	ecx, esi
		inc	ecx
		and	cl, ~1
		# start of system use.
		# end of system use: see iso9660_dr_record_len
		# TODO: rockridge extensions
		pop	esi
		.endif

	movzx	esi, byte ptr [edx + iso9660_dr_record_len]
	add	ecx, esi

	clc
	ret

1:	mov	ecx, -1
	stc
	ret


######################################################
# in: eax = fs info
# in: ebx = filehandle
# in: edi = buf
# in: ecx = buf size
fs_iso9660_read:
	push	eax
	push	ebx
	push	ecx
	push	edx
	mov	edx, ecx
0:	mov	ecx, edx
	push	eax
	mov	al, [eax + fs_obj_disk]
	call	atapi_read12$	# mod: eax, ecx, esi
	pop	eax
	jc	9f
	inc	ebx
	add	edi, ecx
	sub	edx, ecx
	ja	0b
	clc
9:	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret


##############################################################################
# Utility Methods

# used in fs_iso9660_mount
iso9660_verify$:
	cmp	[esi], byte ptr 1	# expect primary volume descriptor
	jnz	9f
	# check the standard-idenfitier 'CD001':
	cmp	dword ptr [esi + 1], ('C')|('D'<<8)|('0'<<16)|('0'<<24)
	jnz	9f
	cmp	byte ptr [esi + 5], '1'
	jnz	9f
	cmp	byte ptr [esi + 6], 1 # volume descriptor version
	jnz	9f

	clc
	ret

9:	printc 12, "iso9660_verify: malformed header: "
	pushcolor 8
	push	esi
	mov	ecx, 7
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	color	7
	call	printchar
	call	printspace
	color	8
	loop	0b
	pop	esi
	call	newline
	popcolor
	stc
	ret

######################################################
# in: esi = file/dir name
# in: ebx = directory extent buffer / dir handle
# out: ebx = ptr to dir record
iso9660_find_entry$:
	push	eax
	push	ecx
	push	edi
	call	strlen_ # in esi, out ecx

0:	cmp	byte ptr [ebx], 0 # rec len
	stc
	jz	9f

	# TODO: scan rockridge extensions for long filenames

######## find length of filename - strip trailing ;1 etc.
	push	ecx
	movzx	ecx, byte ptr [ebx + iso9660_dr_dir_name_len]
	mov	al, ';'
	lea	edi, [ebx + iso9660_dr_dir_name]
	repnz	scasb
	jnz	1f
	inc	ecx
1:	movzx	eax, byte ptr [ebx + iso9660_dr_dir_name_len]
	sub	eax, ecx
	pop	ecx
########
	cmp	eax, ecx	# filename len mismatch
	jnz	1f

	lea	edi, [ebx + iso9660_dr_dir_name]
	push	esi
	push	ecx
	repz	cmpsb
	pop	ecx
	pop	esi
	jz	9f	# found it

1:	movzx	eax, byte ptr [ebx]
	add	ebx, eax
	# TODO: check buffer len overflow
	jmp	0b

9:	pop	edi
	pop	ecx
	pop	eax
	ret


######################################################
# in: eax = fs struct
# in: edx = directory entry
# out: ebx = buffer / directory handle
iso9660_load_dir$:
	push	eax
	push	ecx
	push	edi
	mov	cl, [eax + fs_obj_disk]

	mov	eax, [edx + iso9660_dr_data_len]
	add	eax, 2		# add extra byte (+align) for end of buf check (reclen)
	call	mallocz
	jc	9f
	mov	edi, eax	# todo: keep track somewhere
	mov	al, cl
	mov	ecx, 1
	mov	ebx, [edx + iso9660_dr_extent_location]
	push	esi
	call	atapi_read12$
	pop	esi
	jc	1f
	mov	ebx, edi

9:	pop	edi
	pop	ecx
	pop	eax
	ret

1:	mov	eax, edi
	call	mfree
	stc
	jmp	9b



######################################################
# in: edi = fs dir entry struct (out)
# in: edx = iso dir entry
iso9660_make_fs_entry$:
	push	ecx

	push	eax
	push	esi
	push	edi

	lea	esi, [edx + iso9660_dr_dir_name]
	lea	edi, [edi + fs_dirent_name]
	movzx	ecx, byte ptr [edx + iso9660_dr_dir_name_len]
0:	lodsb
	cmp	al, ';'
	jz	0f
	stosb
	loop	0b
0:	xor	al,al
	stosb

	pop	edi
	pop	esi
	pop	eax

	mov	cl, [edx + iso9660_dr_file_flags]
#  DR_FLAG_NON_FINAL_RECORD = 128
#  DR_FLAG_PROTECTION = 16
#  DR_FLAG_RECORD = 8
#  DR_FLAG_ASSOCIATED = 4
#  DR_FLAG_DIRECTORY = 2
#  DR_FLAG_HIDDEN = 1

  # conver to flags:
#  RO	=1
#  H	=2	DR_FLAG_HIDDEN
#  SYS	=4
#  VOL	=8
#  DIR	=16	DR_FLAG_DIRECTORY
#  A	=32

	mov	ch, cl
	and	ch, DR_FLAG_DIRECTORY # 2 -> 16
	shl	ch, 3
	and	cl, DR_FLAG_HIDDEN # 1 -> 2
	shl	cl, 1
	or	cl, ch

	mov	[edi + fs_dirent_attr], cl
	mov	ecx, [edx + iso9660_dr_data_len]
	mov	[edi + fs_dirent_size], ecx
	mov	[edi + fs_dirent_size + 4], dword ptr 0
	pop	ecx
	ret
