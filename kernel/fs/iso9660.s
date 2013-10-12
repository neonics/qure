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
ISO9660_RR_DEBUG = 0	# rockridge, 'SUSP/RRIP'

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
DECLARE_CLASS_BEGIN fs_iso9660, fs
iso_prim_vol_desc:	.long 0
iso_path_table:		.long 0
iso_path_table_size:	.long 0
.if ISO9660_CACHE_ROOT_DIR
iso_root_dir:		.long 0
iso_root_dir_size:	.long 0
.endif

DECLARE_CLASS_METHOD fs_api_mount,	fs_iso9660_mount, OVERRIDE
DECLARE_CLASS_METHOD fs_api_umount,	fs_iso9660_umount, OVERRIDE
DECLARE_CLASS_METHOD fs_api_open,	fs_iso9660_open, OVERRIDE
DECLARE_CLASS_METHOD fs_api_close,	fs_iso9660_close, OVERRIDE
DECLARE_CLASS_METHOD fs_api_nextentry,	fs_iso9660_nextentry, OVERRIDE
DECLARE_CLASS_METHOD fs_api_read,	fs_iso9660_read, OVERRIDE
DECLARE_CLASS_METHOD fs_api_create,	fs_iso9660_create, OVERRIDE
DECLARE_CLASS_METHOD fs_api_write,	fs_iso9660_write, OVERRIDE
DECLARE_CLASS_METHOD fs_api_delete,	fs_iso9660_delete, OVERRIDE
DECLARE_CLASS_METHOD fs_api_move,	fs_iso9660_move, OVERRIDE

DECLARE_CLASS_END fs_iso9660

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
	mov	eax, offset class_fs_iso9660
	call	class_newinstance
	mov	edi, eax
	pop	eax
	jc	91f

	mov	[edi + fs_obj_disk], ax

	call	atapi_read_capacity # in: al; out: edx:eax, ecx=blocklen, ebx=lba
	jc	92f

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
	#printlnc 0xf0, "iso9660_mount: ok"
	clc
	ret
91:	printlnc 4, "iso9660_mount: malloc fail"
	stc
	ret
92:	printlnc 4, "iso9660_mount: get capacity fail"
	stc
	ret

# error: deallocate buffers
# in: edi = fs_struct
6:	printlnc 4, "iso9660_mount: read path table/load dir fail"
	mov	eax, [edi + iso_path_table]
	call	mfree
7:	mov	eax, [edi + iso_prim_vol_desc]
	call	mfree
8:	mov	eax, edi
	call	mfree
	printlnc 4, "iso9660_mount: read error"
	stc
	ret

1:	#printlnc 12, "iso9660_mount: only ATAPI supported at this time"
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

1:	call	iso9660_find_entry$	# in: eax, esi, ebx; out: ebx
	jc	9f

	mov	edx, ebx
	call	iso9660_make_fs_entry$	# in: edx=iso dirent, edi=fs dirent

	# parse RockRidge Extensions, and update the fs dirent info in edi
	push	esi
	push	ecx
	call	iso9660_dr_get_susp	# in: edx; out: esi, ecx
	call	iso9660_parse_rockridge	# in: esi,ecx=SUSP area; in: edi=dirent
	pop	ecx
	pop	esi

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

.if ISO9660_CACHE_ROOT_DIR
	cmp	ebx, [eax + iso_root_dir]
	jz	9f
.endif

.if 0
	# if closing a directory, this will be the current 'nextentry' value, and thus
	# useless.
	test	byte ptr [edi + fs_dirent_attr], FS_DIRENT_ATTR_DIR
	jz	9f	# it's an extent (lba sector)
.else
	push_	ecx edx
	call	iso9660_delete_bufref$
	pop_	edx ecx
	jnc	1f
	clc
	jmp	9f
1:	
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
.if ISO9660_CACHE_ROOT_DIR
	cmp	ebx, -1
	jnz	0f
	cmp	ecx, [eax + iso_root_dir_size]
	jae	1f
	mov	ebx, [eax + iso_root_dir]
.endif
0:	lea	edx, [ebx + ecx]
	cmp	byte ptr [edx + iso9660_dr_record_len], 0
	jz	2f

	.if ISO9660_DEBUG > 1
		push esi
		debug_dword ecx, "offset"
		push ecx
		movzx ecx, byte ptr [edx + iso9660_dr_dir_name_len]
		DEBUG_DWORD ecx, "dirnamelen"
		lea esi, [edx + iso9660_dr_dir_name]
		call nprint
		DEBUG_DWORD [edx+iso9660_dr_data_len],"datalen"
		DEBUG_DWORD [edx+iso9660_dr_extent_location],"ext"
		DEBUG_BYTE [edx+iso9660_dr_ext_attr_len],"extattr"
		call newline
		DEBUG_BYTE [edx+iso9660_dr_record_len],"recordlen"
		add	esi, ecx
		sub	esi, edx
		DEBUG_DWORD esi,"std reclen"
		movzx	ecx, byte ptr [edx + iso9660_dr_record_len]
		sub	ecx, esi
		DEBUG_DWORD ecx, "system use len"
		call newline
		pop ecx
		pop esi
	.endif

	call	iso9660_make_fs_entry$	# in: edx=iso dirent, edi=fs dirent

	# parse RockRidge Extensions, and update the fs dirent info in edi
	push	esi
	push	ecx
	call	iso9660_dr_get_susp	# in: edx; out: esi, ecx
	call	iso9660_parse_rockridge	# in: esi,ecx=SUSP area; in: edi=dirent
	pop	ecx
	pop	esi

	movzx	esi, byte ptr [edx + iso9660_dr_record_len]
	add	ecx, esi

	clc
	ret

2:	# record entry len 0
	# ebx = bufstart
	# ecx = offset in buf
	push	edi
	mov	edi, [iso9660_buffers$]
	push	eax
	push	ecx
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	# assume ok
	mov	eax, ebx
	repnz	scasd
	pop	ecx
	# assume ok
	sub	edi, 4
	sub	edi, [iso9660_buffers$]
	or	ecx, 2047
	inc	ecx
	mov	eax, [iso9660_bufsizes$]
	mov	eax, [eax + edi]
	cmp	ecx, eax
	pop	eax
	pop	edi
	jb	0b

1:	mov	ecx, -1
	stc
	ret

# in: edi = fs dirent structure ptr
# in: esi = points to directory entry system use area
# in: ecx = system use area size
iso9660_parse_rockridge:
	push	eax
	push	ecx
	push	edx

	.if ISO9660_RR_DEBUG > 1
		push	esi
		push	ecx
	0:	lodsb
		mov	dl, al
		call	printhex2
		call	printspace
		loop	0b
		call	newline
		pop	ecx
		pop	esi
	.endif

	xor	eax, eax
########
0:	cmp	byte ptr [esi + 2], 4
	jb	99f
	push	ecx
###
	lodsb	# first char of signature word
	.if ISO9660_RR_DEBUG
		call	printchar
	.endif
	lodsb	# second char of signature word
	.if ISO9660_RR_DEBUG
		call	printchar
		call	printspace
	.endif
	lodsb	# 'record' length
	movzx	ecx, al
	sub	ecx, 4
	lodsb	# version
	.if ISO9660_RR_DEBUG
		movzx	edx, al
		printchar_ 'v'
		mov	al, dl
		call	printdec32
		call	printspace
		mov	edx, ecx
		call	printdec32
		call	printspace
	.endif
	push	ecx
	push	esi
	cmp	al, 1	# check version
	jnz	1f
##	# esi,ecx = payload
	mov	ax, [esi - 4]	# signature word

	# * marks TODO:
	#
	# SUSP fields:
	#
	#*CE: continuation area: when system use field len - rec len exceeds 255
	#*PD: padding field
	#*SP: system use sharing protocol indicator
	#*ST: system use sharing protocol terminator
	#*ER: extensions reference
	#*ES: extension selector
	#*AA: apple extension, preferred
	#*AB: apple extension, OLD
	#*AS: amiga file properties
	#
	# RRIP (POSIX SUSP tags):
	#
	# RR: rockridge extensions in-use indicator (deprecated)
	# PX: posix file attributes
	# PN: posix device numbers
	#*SL: symbolic link
	# NM: alernate name
	# (due to dir structure being max 8 levels deep:)
	#*CL: child link: LBA of relocated/child dir.
	#*PL: parent link: LBA of original parent of relocated dir
	#*RE: relocated: its presence indicates it is a relocated vers of orig.
	# TF: timestamps
	#*SF: sparse file data

	cmp	ax, 'R' | 'R'<<8	# undocumented?
	jz	2f
	cmp	ax, 'N' | 'M'<<8
	jz	3f
	cmp	ax, 'P' | 'X'<<8
	jz	4f
	cmp	ax, 'T' | 'F'<<8
	jz	5f
	cmp	ax, 'S' | 'P'<<8
	jz	6f
	cmp	ax, 'P' | 'N'<<8
	jz	7f
	cmp	ax, 'S' | 'P'<<8
	jz	8f
	cmp	ax, 'S' | 'T'<<8
	jz	9f
	.if ISO9660_RR_DEBUG
		printc 6, "Unknown"
	.endif
1:
	.if ISO9660_RR_DEBUG
		call	newline
	.endif
##
	pop	esi
	pop	ecx
	add	esi, ecx
	mov	edx, ecx
###
	pop	ecx
	sub	ecx, edx
	jg	0b
########
99:
	pop	edx
	pop	ecx
	pop	eax
	ret


#################################
# RR: SUSP extension: declare rockridge (deprecated, can't find doc)
2:	cmp	ecx, 1
	jnz	22f
	lodsb	# generally 0x89 or 0x81.. flags?
	.if ISO9660_RR_DEBUG
		mov	dl, al
		call	printhex2
	.endif
	jmp	1b
22:	printc 6, "warning: 'RR' is not len 1: "
	mov	edx, ecx
	call	printdec32
	jmp	1b
#################################
# SP: 'SUSP' system use sharing protocol indicator
8:	or	ecx, ecx
	jz	1b
80:	lodsb
	.if ISO9660_RR_DEBUG
		mov	dl, al
		call	printhex2
		call	printspace
	.endif
	loop	80b
	jmp	1b
#################################
# ST: 'SUSP' system use sharing protocol terminator
9:	jmp	8b
#################################
# NM: name
# format: 'N', 'M', len, 1, flags, ascii name (not zero terminated!)
# flag bits:
#   0 = continue: 1=concatenate more NM records; 0=last nm
#   1 = current: 1=the name refers to the current directory.
#   2 = parent: name refers to parent dir.
# other bits reserved; bit 5 legacy meaning: network node name.
# restriction: only one of the first 3 bits may be set.
3:	lodsb	# flags
	or	al, al
	jnz	33f
	dec	ecx
	jle	1b
	.if ISO9660_RR_DEBUG
		mov	al, '\''
		call	printchar
		call	nprint
		call	printchar
	.endif

	# copy new filename to dir handle.
	# Safety quaranteed: fs_dirent_name is 256 bytes; SUSP field is
	# max 255-31 and thus NM aswell.
	push	edi
	add	edi, offset fs_dirent_name
	rep	movsb
	xor	al, al
	stosb
	pop	edi

	jmp	1b
33:	printc	6, "warning: 'NM' flag unsupported: "
	mov	dl, al
	call	printhex2
	jmp	1b
#################################
# PX: POSIX permissions, type
# perm:	dd LSB, MSB
# link:	dd LSB, MSB
# uid:	dd LSB, MSB
# gid:	dd LSB, MSB: total record len is 32 bytes. If longer:
# ino:	dd LSB, MSB: file serial nr, st_ino; dir records with same ino=same file
4:	lodsd	# permissions
	add	esi, 4	# skip msb
	.if ISO9660_RR_DEBUG
		mov	edx, eax
		printc	15, " perm "
		call	printoct6
		call	printspace
		call	fs_posix_perm_print	# in: eax
	.endif

	mov	[edi + fs_dirent_posix_perm], eax

	lodsd	# link
	add	esi, 4	# skip msb
	.if ISO9660_RR_DEBUG
		printc	15, " link "
		mov	edx, eax
		call	printhex8
	.endif

	lodsd	# uid
	add	esi, 4	# skip msb

	mov	[edi + fs_dirent_posix_uid], eax

	.if ISO9660_RR_DEBUG
		printc	15, " uid "
		mov	edx, eax
		call	printdec32
	.endif

	lodsd	# gid
	add	esi, 4	# skip msb

	mov	[edi + fs_dirent_posix_gid], eax

	.if ISO9660_RR_DEBUG
		printc	15, " gid "
		mov	edx, eax
		call	printdec32
	.endif

	sub	ecx, 32
	jle	1b

	lodsd
	add	esi, 4
	.if ISO9660_RR_DEBUG
		printc	15, " inode "
		mov	edx, eax
		call	printhex8
	.endif

	jmp	1b
#################################
# PN: device number
# mandatory when PN specifies char/block device; ignore otherwise.
7:	# len: 20 (-4) for version 1
	lodsd
	add	esi, 4	# skip msb
	mov	edx, eax
	call	printdec32
	printchar_ ','
	lodsd
	add	esi, 4	# skip msb
	mov	edx, eax
	call	printdec32
	jmp	1b
#################################
# TF: time stamps
# payload: flags, time data recorded according to flags.
RR_TF_FLAG_CREATION	= 1 << 0
RR_TF_FLAG_MODIFY	= 1 << 1
RR_TF_FLAG_ACCESS	= 1 << 2
RR_TF_FLAG_ATTRIBUTES	= 1 << 3
RR_TF_FLAG_BACKUP	= 1 << 4
RR_TF_FLAG_EXPIRATION	= 1 << 5
RR_TF_FLAG_EFFECTIVE	= 1 << 6
RR_TF_FLAG_LONG_FORM	= 1 << 7 # fmt:1=(l=17)9660:8.4.26.1; 0=(l=7)9660:9.1.5
5:	lodsb
	mov	ah, al
	test	ah, RR_TF_FLAG_LONG_FORM
	jz	51f
	# long form
	.if ISO9660_RR_DEBUG > 1
		printcharc 12, 'L'
		.irp l,ctime,mtime,atime,attrtime,btime,exptime,efftime
		shr	ah, 1
		jnc	59f
		call	iso9660_time_long_specified
		jc	59f
		printc	15, " \l "
		call	iso9660_time_long_print
	59:;	.endr
	.endif
	# jmp 1b ?

51:	# short form
	.if ISO9660_RR_DEBUG > 1
		printcharc 12, 'S'
	.endif
		.irp l,ctime,mtime,atime,attrtime,btime,exptime,efftime
		shr	ah, 1
		jnc	59f
		call	iso9660_time_short_specified
		jc	59f

		.ifc \l,mtime
		mov	edx, [esi]
		mov	[edi + fs_dirent_posix_mtime], edx
		mov	edx, [esi+4]
		and	edx, 0x00ffffff
		mov	[edi + fs_dirent_posix_mtime+4], edx
		.endif

	.if ISO9660_RR_DEBUG > 1
		printc	15, " \l "
		call	iso9660_time_short_print
	.else
		add	esi, 7
	.endif
	59:;	.endr
	jmp	1b
#################################
# SP
6:
	jmp	1b
#################################

# in: esi: offset to iso9660:8.4.26.1 long format time
# out: CF = 1: time not specified (zero); 0: specified
# out: esi: CF=1: advanced beyond time (+17); CF=0: unmodified
iso9660_time_long_specified:
	push	eax
	push	edx
	# if all digits are '0' and the timezone is 0, the record is not
	# specified (even though flag may indicate it is stored).
	mov	eax, [esi]
	sub	eax, '0'|'0'<<8|'0'<<16|'0'<<24
	add	eax, [esi + 4]
	sub	eax, '0'|'0'<<8|'0'<<16|'0'<<24
	add	eax, [esi + 8]
	sub	eax, '0'|'0'<<8|'0'<<16|'0'<<24
	add	eax, [esi + 12]
	sub	eax, '0'|'0'<<8|'0'<<16|'0'<<24
	movzx	edx, byte ptr [esi + 16]
	add	eax, edx
	clc
	jnz	9f
	add	esi, 17
	stc
9:	pop	edx
	pop	eax
	ret

iso9660_time_long_print:
	# date:
	.rept 4
	lodsb
	call	printchar
	.endr
	.rept 2
	printchar_ '-'
	lodsb
	call	printchar
	lodsb
	call	printchar
	.endr
	call	printspace
	# time
	lodsb
	call	printchar
	lodsb
	call	printchar
	.rept 2
	printchar_ ':'
	lodsb
	call	printchar
	lodsb
	call	printchar
	.endr
	printchar '.'
	lodsb
	call	printchar
	lodsb
	call	printchar
	call	printspace
	# timezone (GMT offset)
	lodsb	# 15 minute intervals
	call	iso9660_print_tz
9:	ret

# in: esi: offset to iso9660:9.1.5 short format time
# out: CF = 1: time not specified (zero); 0: specified
# out: esi: CF=1: advanced beyond time (+17); CF=0: unmodified
iso9660_time_short_specified:
	push	eax
	# if all 7 values are 0, the record is not stored (even though
	# flag may say so).
	mov	eax, [esi + 4]
	and	eax, 0x00ffffff
	add	eax, [esi]
	clc
	jnz	9f
	add	esi, 7
	stc
9:	pop	eax
	ret

iso9660_time_short_print:
	push	eax
	# date
	lodsb
	movzx	edx, al
	add	edx, 1900
	call	printdec32
	.rept 2
	printchar_ '-'
	lodsb
	movzx	edx, al
	call	printdec32
	.endr
	call	printspace
	# time
	lodsb
	mov	dl, al
	call	printdec32
	.rept 2
	printchar_ ':'
	lodsb
	mov	dl, al
	call	printdec32
	.endr
	# timezone
	lodsb
	call	iso9660_print_tz
9:	pop	eax
	ret

iso9660_print_tz:
	movsx	edx, al
	mov	al, '+'
	or	edx, edx
	jns	1f
	mov	al, '-'
	neg	edx
1:	call	printchar
	# 4 -> 60 minutes -> 100
	# so take 25 'minutes' per quarter
	mov	eax, 25
	imul	edx, eax
	cmp	edx, 1000
	jae	1f
	printchar_ '0'
1:	call	printdec32
	ret

# in: edx = directory record pointer
# out: esi = start of system use area in directory record
# out: ecx = length of system use area
iso9660_dr_get_susp:
	movzx	ecx, byte ptr [edx + iso9660_dr_record_len]
	sub	ecx, offset iso9660_dr_dir_name
	movzx	esi, byte ptr [edx + iso9660_dr_dir_name_len]
	sub	ecx, esi	# ecx is now system use len

	add	esi, offset iso9660_dr_dir_name
	# word align: use relative offset
	bt	esi, 0
	sbb	cl, 0
	bt	esi, 0
	adc	esi, 0

	add	esi, edx	# start of sysuse
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

fs_iso9660_write:
fs_iso9660_create:
fs_iso9660_delete:
fs_iso9660_move:
	printlnc 4, "create/write/delete/move not supported for iso9660"
	stc
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

0:	
#DEBUG_BYTE [ebx],"<<RECLEN>>"
	cmp	byte ptr [ebx], 0 # rec len
	jnz	1f

#DEBUG "<EOR>"
	push_	ecx edx
	call	iso9660_get_bufsize$	# out: ecx = bufsize; edx = bufstart
	jc	2f
#DEBUG_DWORD ecx, "ctd", 0xf0
	cmp	ecx, 2048
	stc
	jz	4f
	sub	ebx, edx	# ebx = offset
	or	ebx, 2047
	inc	ebx
	#call more
	cmp	ebx, ecx
	jae	3f	# buf exceed
	# continue to next 2k block
	add	ebx, edx
	clc
	jmp	4f
2:	DEBUG "iso9660: unknown buffer"
3:	stc
4:	pop_	edx ecx
	jnc	1f
#	DEBUG "<NOT FOUND>", 0x4f
	stc
	jmp	9f
1:

######## find length of filename - strip trailing ;1 etc.
	call	iso9660_dr_get_name	# out: edi, eax
########
	cmp	eax, ecx	# filename len mismatch
	jnz	1f

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

# in: ebx: directory entry
# out: edi = dir name
# out: eax = dir name len (strips trailing ';1' etc..)
iso9660_dr_get_name:
	# check rockridge:
	push	ecx
	push	esi

	push	edx
	mov	edx, ebx
	call	iso9660_dr_get_susp	# out: esi, ecx
	pop	edx
	or ecx,ecx; jz 9f #jecxz	1f
0:	cmp	byte ptr [esi + 3], 1	# check version
#DEBUG_DWORD esi
	jnz	2f
	cmp	[esi], word ptr ('N'|'M'<<8)	# check signature word
	jnz	2f
	movzx	eax, byte ptr [esi + 2]	# verify record len
	cmp	eax, ecx
	ja	2f		# would exceed susp area
	# found a name.
	sub	eax, 4+1	# subtract susp record fixed len + NM flag
	jle	2f
	mov	ecx, eax
	lea	edi, [esi + 5]
#DEBUGS edi
	jmp	9f		# return rockridge name

2:	
	movzx	eax, byte ptr [esi + 2]
	or	eax, eax
	jz	1f
	add	esi, eax
	sub	ecx, eax
	jg	0b
#		DEBUG "<<quit>>"
#	1: DEBUG "end of record"

1:	movzx	ecx, byte ptr [ebx + iso9660_dr_dir_name_len]
	mov	al, ';'
	lea	edi, [ebx + iso9660_dr_dir_name]
	repnz	scasb
	jnz	1f
	inc	ecx
1:	movzx	eax, byte ptr [ebx + iso9660_dr_dir_name_len]
	sub	eax, ecx
	lea	edi, [ebx + iso9660_dr_dir_name]

9:	pop	esi
	pop	ecx
	ret

.data SECTION_DATA_BSS
iso9660_buffers$: .long 0
iso9660_bufsizes$: .long 0
.text32
# in: ebx = directory entry ptr
# out: ecx = size of buffer
# out: edx = buf start
iso9660_get_bufsize$:
	push_	eax edi
	mov	edi, [iso9660_bufsizes$]
	ARRAY_LOOP [iso9660_buffers$], 4, eax, edx, 9f

	cmp	ebx, [eax + edx]
	jb	1f

	mov	ecx, [edi + edx]	# bufsize
	add	ecx, [eax + edx]	# bufstart: ecx=bufend
	cmp	ebx, ecx
	jae	1f

	# found the buf
	mov	ecx, [edi + edx]
	mov	edx, [eax + edx]
	clc
	jmp	9f

1:	ARRAY_ENDL
	stc	# not found
9:	pop_	edi eax
	ret


# in: ebx = buffer
iso9660_delete_bufref$:
	push_	eax ebx esi edi
	mov	eax, ebx
	mov	edi, [iso9660_buffers$]
	mov	ebx, edi
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	repnz	scasd
	stc
	jnz	9f

	subd	[ebx + array_index], 4

	sub	ebx, edi
	neg	ebx
	mov	eax, ecx

	mov	esi, edi
	sub	edi, 4
	rep	movsd

	mov	ecx, eax

	mov	edi, [iso9660_bufsizes$]
	subd	[edi + array_index], 4
	add	edi, ebx
	mov	esi, edi
	sub	edi, 4
	rep	movsd
	clc

9:	pop_	edi esi ebx eax
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
push	eax
	jc	9f

push_ eax edx ebx ecx
mov ebx, eax
mov ecx, [edx + iso9660_dr_data_len]
PTR_ARRAY_NEWENTRY [iso9660_buffers$], 4, 91f
mov [eax + edx], ebx
PTR_ARRAY_NEWENTRY [iso9660_bufsizes$], 4, 91f
mov [eax + edx], ecx
91:pop_ ecx ebx edx eax
jc 9f

	mov	edi, eax	# todo: keep track somewhere
	mov	al, cl
	mov	ebx, [edx + iso9660_dr_extent_location]
mov	edx, [edx + iso9660_dr_data_len]
0:	
	push_	esi eax
	mov	ecx, 1
	call	atapi_read12$	# mod: eax, esi, ecx (->0x800)
	pop_	eax esi
	jc	1f
inc	ebx
add	edi, 2048
sub	edx, 2048
ja	0b

	mov	ebx, [esp]#edi

9:	
pop edi
	pop	edi
	pop	ecx
	pop	eax
	ret

1:	mov	eax, [esp]#edi
	call	mfree
	stc
	jmp	9b



######################################################
# in: edi = fs dir entry struct (out)
# in: edx = iso dir entry
# [in: ebx = directory handle (mem ptr)]
# [in: ecx = offset in directory handle]
iso9660_make_fs_entry$:
	push	ecx

	push	eax
	# root directory records:
	# first:  root dir, id 0
	# second: root dir, id 1
	# other directory records:
	# first:  self,   id 0
	# second: parent, id 1

	# check if first entry: ecx == 0, or ebx==edx (as edx=ebx+ecx)
	mov	eax, '.'
	or	ecx, ecx	# or: cmp ebx, edx
	jz	2f
	# check if second entry: ebx + [ebx+dr_rec_len] == edx
	mov	al, [ebx + iso9660_dr_record_len]
	add	eax, ebx
	cmp	eax, edx
	mov	eax, '.'|'.'<<8
	jnz	1f
2:	mov	[edi + fs_dirent_name], eax
	jmp	3f

1:	push	esi
	push	edi

	lea	esi, [edx + iso9660_dr_dir_name]
	lea	edi, [edi + fs_dirent_name]
	# ecx is free
	mov	ecx, 254	# fs_dirent_name size
0:	lodsb
	cmp	al, ';'
	jz	0f
	stosb
	loop	0b
0:	xor	al,al
	stosb

	pop	edi
	pop	esi
3:	pop	eax

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
