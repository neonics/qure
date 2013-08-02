.intel_syntax noprefix
PE_DEBUG = 1	# 0..2

###########################################################################

.data
pe_base:	.long 0
pe_img_size:	.long 0
coff_base:	.long 0

#####################################################
# COFF Header
.struct 0
coff_h_machine:		.word 0	# 0x14c = i386
coff_h_sections:	.word 0
coff_h_timestamp:	.long 0
coff_h_symtab:		.long 0
coff_h_symcount:	.long 0
coff_h_opthdrsize:	.word 0
coff_h_characteristics:	.word 0
	# image-file flags:
	COFF_IF_RELOCS_STRIPPED	= 0x0001
	COFF_IF_EXECUTABLE	= 0x0002
	COFF_IF_LINE_NUMS_STRIPPED = 0x0004
	COFF_IF_RELOCS_STRIPPED	= 0x0008
	COFF_IF_LOCAL_SYM_STRIPPED= 0x0010
	COFF_IF_OBSOLETE	= 0x0020	# agressive trim
	COFF_IF_LARGE_ADDR_AWARE= 0x0040	# > 2Gb addresses
	COFF_IF_LITTLE_ENDIAN	= 0x0080
	COFF_IF_32BIT		= 0x0100
	# 0x0200 debug stripped
	# 0x0400 removable_run_on_swap
	# 0x0800 net_run_from_swap
	# 0x1000 system file, not user program
	# 0x2000 dll
	COFF_IF_DLL		= 0x2000
	# 0x4000 uniprocessor only
	# 0x8000 BIG_ENDIAN
COFF_H_STRUCT_SIZE = .
# optional header:
#coff_oh_sig:	.word 0	# 0x010b = PE32; 0x020b = PE32+, 0x0107=ROM


.text32
# in: esi, ecx: PE image
exe_pe:
	# note: singleton access (for now)
	mov	[pe_base], esi
	mov	[pe_img_size], ecx
	mov	ebx, esi

	.if ELF_DEBUG
		println "MZ"
		DEBUG_DWORD esi
		DEBUG_DWORD ecx
	.endif

	cmp	word ptr [esi], 'M'|'Z'<<8
	jnz	91f

	mov	eax, [esi + 0x3c]	# PE offset
	cmp	eax, ecx
	jae	92f

	add	esi, eax

	cmp	dword ptr [esi], 'P'|'E'<<8
	jnz	93f
	add	esi, 4
	mov	[coff_base], esi


	cmp	[esi + coff_h_machine], word ptr 0x14c	# i386+
	jnz	94f
	mov	ax, [esi + coff_h_characteristics]
	test	ax, COFF_IF_DLL
	jnz	96f
	and	ax, COFF_IF_EXECUTABLE | COFF_IF_32BIT
	cmp	ax, COFF_IF_EXECUTABLE | COFF_IF_32BIT
	jnz	95f

	call	coff_print_header$
	mov	ebx, esi
	call	coff_calc$
	call	coff_sections_print$

	DEBUG "sections printed"

	call	coff_calc$
	call	coff_sections_map$

	DEBUG "executing"
	mov	esi, [pe_base]
	add	esi, 0x400
	DEBUG_DWORD [esi], "opcodes"
	call more
	DEBUG "not executing..."#call	esi

	ret
91:	printlnc 4, "not MZ"
	ret
92:	printlnc 4, "PE pointer outside image"
	ret
93:	printlnc 4, "not PE"
	ret
94:	printlnc 4, "Machine not supported"
	ret
96:	print "dll: "
95:	printlnc 4, "not executable"
	ret
97:	printlnc 4, "malloc_page_phys fail"
	ret


coff_relocate:
	
	ret

coff_print_header$:
	DEBUG_WORD [esi+0], "Machine"
	DEBUG_WORD [esi+2], "#Sections"
	DEBUG_DWORD [esi+4], "TimeStamp"
	DEBUG_DWORD [esi+8], "SymTab"
	DEBUG_DWORD [esi+12], "#Symbols"
	DEBUG_WORD [esi+16], "OptHdrSize"
	DEBUG_WORD [esi+18], "Characteristics"
	call	newline

	# optional header: required for image files, not for obj
	# (image file = exe or dll, I assume)

	cmp	word ptr [esi + coff_h_opthdrsize], 0
	jz	9f

	DEBUG "Optional Header: "
	mov	ax, [esi + COFF_H_STRUCT_SIZE]
	DEBUG_WORD ax,"OptHdrSig"
	cmp	ax, 0x010b
	jz	coff_oh_pe32$
	cmp	ax, 0x020b
	jz	coff_oh_pe32p$
	printlnc 4, "invalid signature"

9:	ret


.struct 0	# common for all COFF versions
coff_oh_magic:		.word 0
coff_oh_linker_version:	.word 0	# lo major, hi minor
coff_oh_text_size:	.long 0
coff_oh_data_size:	.long 0
coff_oh_bss_size:	.long 0
coff_oh_entrypoint:	.long 0
coff_oh_text_base:	.long 0

coff_oh_pe32p_image_base:#	.long 0, 0 - overlap with data/img base
coff_oh_pe32_data_base:	.long 0	# PE32; absent in PE32+
coff_oh_pe32_image_base:.long 0
coff_oh_section_alignment:.long 0	# from here (offs 32), PE32/PE32+ align
coff_oh_file_alignment:	.long 0
coff_oh_os_version:	.word 0, 0	# maj, min
coff_oh_img_version:	.word 0, 0	# maj, min
coff_oh_subsys_version:	.word 0, 0	# maj, min
coff_oh_w32ver_RESERVED:.long 0
coff_oh_img_size:	.long 0
coff_oh_hdr_size:	.long 0	# stub, PE, section hdrs rounded to file_alignment
coff_oh_checksum:	.long 0
coff_oh_subsystem:	.word 0
coff_oh_dll_char:	.word 0	# DLL characteristics
coff_oh_DIVERGE:	# offset 72: here they diverge:
.struct coff_oh_DIVERGE
coff_oh_pe32p_stack_reserve:	.long 0,0
coff_oh_pe32p_stack_commit:	.long 0,0
coff_oh_pe32p_heap_reserve:	.long 0,0
coff_oh_pe32p_heap_commit:	.long 0,0
coff_oh_pe32p_loader_flags:	.long 0
coff_oh_pe32p_rva_count:	.long 0	# nr of data directory entries
coff_oh_pe32p_dd:	# offset 112
.struct coff_oh_DIVERGE
coff_oh_pe32_stack_reserve:	.long 0
coff_oh_pe32_stack_commit:	.long 0
coff_oh_pe32_heap_reserve:	.long 0
coff_oh_pe32_heap_commit:	.long 0
coff_oh_pe32_loader_flags:	.long 0
coff_oh_pe32_rva_count:		.long 0	# nr of data directory entries
coff_oh_pe32_dd:	# offset 96


.struct 0	# data directory
coff_oh_dd_edata:	.long 0,0	# export table; 6.3
coff_oh_dd_idata:	.long 0,0	# import table; 6.4
coff_oh_dd_rsrc:	.long 0,0	# resource table; 6.9
coff_oh_dd_pdata:	.long 0,0	# exception table; 6.5
coff_oh_dd_cert:	.long 0,0	# certificate table; 5.7
coff_oh_dd_reloc:	.long 0,0	# relocation table; 6.6
coff_oh_dd_debug:	.long 0,0	# debug table; 6.1
coff_oh_dd_arch:	.long 0,0	# reserved
coff_oh_dd_global_ptr:	.long 0,0	# size must be 0
coff_oh_dd_tls:		.long 0,0	# thread local storage table; 6.7
coff_oh_dd_loadcfg:	.long 0,0	# load config table; 6.8
coff_oh_dd_bound_import:.long 0,0	# bound import table
coff_oh_dd_iat:		.long 0,0	# import address table; 6.4.4
coff_oh_dd_dis:		.long 0,0	# delay import descriptor table; 5.8
coff_oh_dd_cormeta:	.long 0,0	# CLR runtime header; 6.10
coff_oh_dd_reserved:	.long 0,0

#.struct 0
#coff_oh_pe32_std:	.space 28
#coff_oh_pe32_win:	.space 68
#coff_oh_pe32p_dd:	# variable

#.struct 0
#coff_oh_pe32p_std:	.space 24
#coff_oh_pe32p_win:	.space 88
#coff_oh_pe32p_dd:	# variable


.text32
coff_oh_pe32$:
	mov	ebx, esi	# coff_base
	push	esi
	add	esi, COFF_H_STRUCT_SIZE
	mov	dx, [esi+coff_oh_linker_version + 0]
	print "Linker Version: "
	call	printhex2
	printchar '.'
	shr	dx, 8
	call	printhex2
	call	newline
	DEBUG ".text"
	DEBUG_DWORD [esi + coff_oh_text_size], "size"
	DEBUG_DWORD [esi + coff_oh_text_base], "base"
	DEBUG_DWORD [esi + coff_oh_entrypoint], "entrypoint"
	call	newline
	DEBUG ".data"
	DEBUG_DWORD [esi + coff_oh_data_size], "size"
	call	newline
	DEBUG ".bss"
	DEBUG_DWORD [esi + coff_oh_bss_size], "size"
	call	newline

	DEBUG_DWORD [esi + coff_oh_pe32_data_base], "data_base"
	DEBUG_DWORD [esi + coff_oh_pe32_image_base], "image_base"
	DEBUG_DWORD [esi + coff_oh_section_alignment], "section_alignment"
	DEBUG_DWORD [esi + coff_oh_file_alignment], "file_alignment"
	call	newline
	DEBUG_DWORD [esi + coff_oh_os_version], "OSver"
	DEBUG_DWORD [esi + coff_oh_img_version], "IMGver"
	DEBUG_DWORD [esi + coff_oh_subsys_version], "SubSysVer"
	DEBUG_DWORD [esi + coff_oh_w32ver_RESERVED], "RSVD"
	DEBUG_DWORD [esi + coff_oh_img_size], "IMG size"
	DEBUG_DWORD [esi + coff_oh_hdr_size], "HDR size"
	DEBUG_DWORD [esi + coff_oh_checksum], "CKSUM"
	DEBUG_WORD [esi + coff_oh_subsystem], "SubSys"
	DEBUG_WORD [esi + coff_oh_dll_char], "DLLchar"
	call	newline
	DEBUG "Stack"
	DEBUG_DWORD [esi + coff_oh_pe32_stack_reserve], "reserve"
	DEBUG_DWORD [esi + coff_oh_pe32_stack_commit], "commit"
	DEBUG "heap"
	DEBUG_DWORD [esi + coff_oh_pe32_heap_reserve], "reserve"
	DEBUG_DWORD [esi + coff_oh_pe32_heap_commit], "commit"
	DEBUG_DWORD [esi + coff_oh_pe32_loader_flags], "loaderFlags"
	DEBUG_DWORD [esi + coff_oh_pe32_rva_count], "DD count"
	call	newline

	push	esi
	mov	ecx, [esi + coff_oh_pe32_rva_count]
	lea	esi, [esi + coff_oh_pe32_dd]
	println "RVA / Data Dir:"

	.macro PE_DD_PRINT name
		dec	ecx
		jz	1f
		print "\name"
		call	2f
	.endm
inc ecx
	PE_DD_PRINT ".edata"	# export table; 6.3
	PE_DD_PRINT ".idata"	# import table; 6.4
	PE_DD_PRINT ".rsrc"	# resource table; 6.9
	PE_DD_PRINT ".pdata"	# exception table; 6.5
	PE_DD_PRINT ".cert"	# certificate table; 5.7
	PE_DD_PRINT ".reloc"	# relocation table; 6.6
	PE_DD_PRINT ".debug"	# debug table; 6.1
	PE_DD_PRINT "arch (0,0)"# reserved
	PE_DD_PRINT "<global ptr>" # size must be 0
	PE_DD_PRINT ".tls"	# thread local storage table; 6.7
	PE_DD_PRINT "<load>"	# load config table; 6.8
	PE_DD_PRINT "<bound import"	# bound import table
	PE_DD_PRINT "<IAT>"	# import address table; 6.4.4
	PE_DD_PRINT "<DIS>"	# delay import descriptor table; 5.8
	PE_DD_PRINT ".cormeta"	# CLR runtime header; 6.10
	PE_DD_PRINT "<reserved>"
	.purgem PE_DD_PRINT

	jecxz	1f

0:	call	2f
	loop	0b
1:
	pop	esi

	push	esi
	mov	ecx, [esi + coff_oh_pe32_dd + coff_oh_dd_idata + 4]
	mov	eax, [esi + coff_oh_pe32_dd + coff_oh_dd_idata]
	DEBUG_DWORD eax, "IDATA PTR"
	DEBUG_DWORD ecx, "IDATA SIZE"
	pop	esi

	push	esi
	mov	ecx, [esi + coff_oh_pe32_dd + coff_oh_dd_iat + 4]
	mov	esi, [esi + coff_oh_pe32_dd + coff_oh_dd_iat]
	DEBUG_DWORD esi, "IAT PTR"
	DEBUG_DWORD ecx, "IAT SIZE"
	pop	esi
	call	newline

	# section table follows the data directory
	call	coff_calc$
call more
#	mov	eax, [coff_base]
#	sub	eax, [pe_base]
#	DEBUG_DWORD eax, "coff_base-pe_base"
#call more

	call	coff_sections_print$
	call	newline

	# print IDATA:
	push	esi
	mov	esi, [coff_sect_idata]
	mov	edx, [esi + coff_sect_vaddr]
	mov	ecx, [esi + coff_sect_vsize]
	mov	esi, [esi + coff_sect_diskoffs]
	DEBUG_DWORD esi,".idata DiskOffs"
	DEBUG_DWORD ecx,".idata Size" # 0, should not be!
	DEBUG_DWORD edx, "vaddr"
	sub	edx, esi
	call	more
	add	esi, [pe_base]
	call	coff_idata_print$
	pop	esi


	DEBUG "Symbol Table:",0xf0
	call	coff_print_symtab$

	pop	esi
	ret

2:	lodsd; DEBUG_DWORD eax, "vaddr"
	lodsd; DEBUG_DWORD eax, "size"
	call	newline
	ret

# section table follows the data directory
# in: ebx = coff_base
# out: esi = section ptr
# out: ecx = nr sections
# out: edi = stringtable ptr
# destroys: edx, eax
coff_calc$:
	lea	esi, [ebx + COFF_H_STRUCT_SIZE]
	mov	eax, [esi + coff_oh_pe32_rva_count]
	shl	eax, 3
	DEBUG_DWORD eax
	add	eax, offset coff_oh_pe32_dd
	DEBUG_DWORD eax
	DEBUG_DWORD [esi + coff_oh_hdr_size], "oh hdr size"
	DEBUG_WORD [ebx + coff_h_opthdrsize], "opthdr size"

	add	esi, eax	# or: add esi, coff_h_opthdrsize

	movzx	ecx, word ptr [ebx + coff_h_sections]
	DEBUG_DWORD ecx, "nr sections"


	# string table follows symbol table.
	# symbol table entry size: 18 bytes
	mov	eax, [ebx + coff_h_symcount]
	DEBUG_DWORD eax,"symcount"
	mov	edx, 18
	mul	edx
	mov	edi, eax
	DEBUG_DWORD eax, "symcount size"
	DEBUG_DWORD [ebx + coff_h_symtab]
	add	edi, [ebx + coff_h_symtab]
	DEBUG_DWORD edi, "symtab end"
	add	edi, [pe_base]
	ret



.struct 0
coff_sect_name: .space 8
coff_sect_vsize: .long 0
coff_sect_vaddr: .long 0
coff_sect_disksize: .long 0
coff_sect_diskoffs: .long 0
coff_sect_relocptr: .long 0
coff_sect_lineptr: .long 0
coff_sect_reloccnt: .word 0
coff_sect_linecnt: .word 0
coff_sect_flags: .long 0 #'characteristics'
	COFF_SECT_FLAG_NO_PAD	= 0x08	# deprecated - use ALIGN_1BYTES
	# Content:
	COFF_SECT_FLAG_CNT_CODE	= 0x20
	COFF_SECT_FLAG_CNT_DATA	= 0x40
	COFF_SECT_FLAG_CNT_BSS	= 0x80
	# object file flags:
	COFF_SECT_FLAG_LNK_INFO	= 0x200	# .drective (obj files)
	COFF_SECT_FLAG_LNK_REMOVE=0x800
	COFF_SECT_FLAG_LNK_COMDAT=0x1000
	#
	COFF_SECT_FLAG_GPREL	= 0x8000	# global pointer data
	# object files: (all powers of 2 represented up to 4096)
	COFF_SECT_FLAG_ALIGN_MASK= 0x00f00000
	COFF_SECT_FLAG_ALIGN_SHIFT=20
	COFF_SECT_FLAG_ALIGN1	= 0x00100000
	COFF_SECT_FLAG_ALIGN1024= 0x00b00000
	COFF_SECT_FLAG_ALIGN8192= 0x00e00000
	# align = 1 << ( (x & ALIGN_MASK) >> ALIGN_SHIFT - 1), 0xf (16k) undef!
	COFF_SECT_FLAG_NRELOC_OVFL=0x01000000 # extended relocations
	COFF_SECT_FLAG_MEM_DISCARD=0x02000000 # section can be discarded if needed
	COFF_SECT_FLAG_MEM_NOCACHE=0x04000000	# cannot be cached
	COFF_SECT_FLAG_MEM_NOPAGE=0x08000000	# not pageable
	COFF_SECT_FLAG_MEM_SHARED=0x10000000	# can be shared
	COFF_SECT_FLAG_MEM_EXEC = 0x20000000	# can be executed
	COFF_SECT_FLAG_MEM_READ = 0x40000000
	COFF_SECT_FLAG_MEM_WRITE =0x80000000
.text32
# call coff_calc$ with ebx = [coff_base] first
coff_sections_print$:
	call	newline
	println "vsize... vaddr... disksize diskoffs relocptr #rel charactr algn mode stp label"
	# 40 bytes / entry
0:	# section name: max 8 bytes asciz; or "/<decimal>" -> stringtable ptr

	add	esi, 8
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "vsize"
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "vaddr"
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "disksize"
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "diskoffs"
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "relocptr"
	lodsd;#mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "lineptr"
	lodsw;mov edx,eax;call printhex4;call printspace # DEBUG_WORD ax, "#relocs"
	lodsw;#mov edx,eax;call printhex4;call printspace # DEBUG_WORD ax, "#lines"
	lodsd;mov edx,eax;call printhex8;call printspace # DEBUG_DWORD eax, "characteristics"
	sub	esi, 40

	mov	eax, [esi + coff_sect_flags]
	# print align:
	push	ecx
	mov	ecx, eax
	and	ecx, COFF_SECT_FLAG_ALIGN_MASK#= 0x00f00000
	shr	ecx, COFF_SECT_FLAG_ALIGN_SHIFT#=20
	dec	ecx
	mov	edx, 1
	shl	edx, cl
	cmp	edx, 1000
	ja	1f
	call	printspace
	cmp	dl, 100
	ja	1f
	call	printspace
	cmp	dl, 10
	ja	1f
	call	printspace
1:	call	printdec32
	pop	ecx
	call	printspace

	# print mode
	PRINTFLAG eax, COFF_SECT_FLAG_MEM_SHARED, "S", " "
	PRINTFLAG eax, COFF_SECT_FLAG_MEM_EXEC, "x", "-"
	PRINTFLAG eax, COFF_SECT_FLAG_MEM_READ, "r", "-"
	PRINTFLAG eax, COFF_SECT_FLAG_MEM_WRITE, "w", "-"

	call	printspace
	# print section type
	PRINTFLAG ax, COFF_SECT_FLAG_CNT_CODE, "C", " "
	PRINTFLAG ax, COFF_SECT_FLAG_CNT_DATA, "D", " "
	PRINTFLAG ax, COFF_SECT_FLAG_CNT_BSS, "B", " "
	call	printspace


	call	coff_print_sect_name$	# out: eax = section name

	####### check for import data
	push	ecx
	LOAD_TXT ".idata", edx
	mov	ecx, 6
	call	strcmp
	pop	ecx
	jnz	1f
	.data; coff_sect_idata:.long 0;.text32
	mov	[coff_sect_idata], esi
1:	########

	add	esi, 40
#	add	esi, 40-8-4*8
	call	newline
#	loop	0b
	dec	ecx
	jnz	0b
	ret


# call coff_calc$ with ebx = [coff_base] first
# in: ebx = coff_base
# in: esi = section ptr
# in: ecx = nr sections
# in: edi = stringtable ptr
coff_sections_map$:
	DEBUG_DWORD esp
	KAPI_CALL coff_sections_map_
	DEBUG "returned from KAPI call"
	DEBUG_DWORD esp
	ret


KAPI_DECLARE coff_sections_map_

	PUSH_TXT "COFF_exe"
	push	dword ptr TASK_FLAG_TASK|TASK_FLAG_SUSPENDED|TASK_FLAG_FLATSEG
	pushd	cs
	mov	eax, [ebx + COFF_H_STRUCT_SIZE + coff_oh_pe32_image_base]
	DEBUG_DWORD [ebx + COFF_H_STRUCT_SIZE + coff_oh_pe32_image_base], "img base",0xf0
	add	eax, [ebx + COFF_H_STRUCT_SIZE + coff_oh_entrypoint]
	DEBUG_DWORD [ebx + COFF_H_STRUCT_SIZE + coff_oh_entrypoint], "entry",0xf0
	DEBUG_DWORD eax,"entrypoint"

	push	eax
	call	schedule_task # out: eax=pid

	DEBUG "task scheduled";call  newline

	mov	edx, eax	# pid

	push	ebp
	mov	ebp, esp
	push	edi # stringtable

#coff_sect_name: .space 8
#coff_sect_vsize: .long 0
#coff_sect_vaddr: .long 0
#coff_sect_disksize: .long 0
#coff_sect_diskoffs: .long 0
#coff_sect_relocptr: .long 0
#coff_sect_lineptr: .long 0
#coff_sect_reloccnt: .word 0
#coff_sect_linecnt: .word 0
#coff_sect_flags: .long 0 #'characteristics'

	push	esi
	mov	esi, [page_directory_phys]#cr3
	call	paging_alloc_page_idmap
	pop	esi
	jc	9f

	mov	edi, eax	# PTE

	push_	ebx ecx
	mov	eax, edx
	mov	edx, [ebx + COFF_H_STRUCT_SIZE + coff_oh_pe32_image_base]
	DEBUG_DWORD edx, "img base"
	call	task_get_by_pid # in: eax; out: ebx + ecx
	DEBUG_DWORD ecx, "TASK IDX", 0xf0
	add	ebx, ecx

	# edx=image bage
	# eax=pid
	# ebx=task
	# edi=page
	mov	eax, edi
	DEBUG_DWORD edx, "img base"
	or	ax, PDE_FLAG_U|PDE_FLAG_P|PDE_FLAG_RW
	call	task_map_pde # in: eax=page, edx=tgt addr|flags
	
	pop_	ecx ebx

	DEBUG_DWORD edi, "PTE"

		# map the page in the task struct


	GDT_GET_BASE eax, ds
	sub	edi, eax

0:	mov	eax, [esi + coff_sect_flags]
	test	eax, COFF_SECT_FLAG_MEM_DISCARD
	jnz	1f
	print "mapping "
	push edi
	mov edi,[ebp-4] # stringtable
	call	coff_print_sect_name$	# out: eax = section name
	pop edi
	DEBUG_DWORD [esi + coff_sect_vaddr],"vaddr"

mov eax, cr3
push eax
cli
	push	esi
	mov	esi, cr3

mov eax, [page_directory_phys]
mov cr3, eax
	DEBUG_DWORD esi,"CR3"
mov esi,eax
	call	paging_alloc_page_idmap
	pop	esi
	jc	9f
	mov	edx, eax

	mov	eax, [esi + coff_sect_vaddr]
	shr	eax, 12
	or	dx, PTE_FLAG_U|PTE_FLAG_RW|PTE_FLAG_P

push edx
GDT_GET_BASE edx, ds
add edx, edi
print "PTE";call printhex8
lea edx, [edx + eax*4]
print " ptr ";call printhex8
pop edx
DEBUG_DWORD edx,"page"

	mov	[edi + eax*4], edx


	and	edx, ~((1<<12)-1) # mask out flags
	# copy the page:
	push_	edi esi ecx
	mov	edi, edx
	DEBUG_DWORD edi, "flat tgt"
GDT_GET_BASE edx, ds
sub edi, edx
DEBUG_DWORD edi, "dsrel"

#pushad;
#mov esi, cr3
#call paging_show_struct
#call more
#popad;
	mov	esi, [esi + coff_sect_diskoffs]
	DEBUG_DWORD esi, "disoffs"
	add esi, [pe_base]

	mov	ecx, 1024
	rep	movsd
#	mov	[edi - 4096], byte ptr 0xcc
DEBUG "DST:", 0xf0
sub edi, 4096
mov ecx, 40
mov esi, edi
10: lodsb; mov dl, al; call printhex2; call printspace; loop 10b
	pop_	ecx esi edi

pop eax
mov cr3, eax
sti

1:	
	call	newline
	add	esi, 40
	dec ecx;jnz 0b#loop	0b
	clc

0:	pop edi;#mov	esp, ebp
	pop	ebp
	call	more
	ret

9:	printlnc 4, "can't alloc page"
	stc
	jmp	0b




.struct 0	# idata directory table
coff_idata_dt_ilt_rva:	.long 0
coff_idata_dt_timstamp:	.long 0
coff_idata_dt_fwdchain:	.long 0
coff_idata_dt_name_rva:	.long 0
coff_idata_dt_iat_rva:	.long 0
.text32

# PREREQUISITE: coff_sections_print sets up [coff_sect_idata]!!
# in: esi = ptr to idata section
# in: ecx = idata size
# in: edx = vaddr-addr adjustment: vaddr-diskoffs (sub!)
coff_idata_print$:
	#format: 
	#  directory table
	#  null directory entry
	#  (-note- the code only works with the above; the data described
	#   below are the ILT and IAT, referenced from the dir table)
	#.rept
	#  DLL import lookup table
	#  null
	#.endr
	# hint-name table
	println "ILT..... TimeStmp FwdChain NameRVA. IAT....."
0:	push	ebx
	xor	ebx, ebx
	push	edx
	lodsd; add ebx, eax; mov edx, eax; call printhex8; call printspace
	lodsd; add ebx, eax; mov edx, eax; call printhex8; call printspace
	lodsd; add ebx, eax; mov edx, eax; call printhex8; call printspace
	lodsd; add ebx, eax; mov edx, eax; call printhex8; call printspace
	lodsd; add ebx, eax; mov edx, eax; call printhex8; call printspace
	pop	edx
	or	ebx, ebx
	pop	ebx
	jz	1f

	mov	eax, [esi - 8]	# nameRVA
	sub	eax, edx	# correct vaddr to image rel
	DEBUG_DWORD eax
	add	eax, [pe_base]
	DEBUG_DWORD eax
	push	eax
	call	_s_print
	call	newline

	# print the table.
	push	esi
	lea	eax, [esi - 20]
	mov	esi, [esi - 20] # ILT
	sub	esi, edx	# vaddr correct
	add	esi, [pe_base]
	push	edx
	call	coff_idata_print_ilt$
	pop	edx
	pop	esi
	jmp	0b
1:
	ret

# in: esi = ilt ptr
# in: eax = dll directory table. iat ptr
coff_idata_print_ilt$:	# PE32
	push_	ebx edi
		
		# get libname ptr
		mov	ebx, [eax + coff_idata_dt_name_rva]
		sub	ebx, edx
		add	ebx, [pe_base]
	push	ebx	# libname

		mov	eax, [eax + coff_idata_dt_iat_rva]
		sub	eax, edx
		add	eax, [pe_base]
		mov	ebx, eax
		mov	edi, eax
		sub	edi, [pe_base]
		sub	edi, 4
		add	edi, edx
		sub	ebx, 4

0:	lodsd
		add	ebx, 4
		add	edi, 4
	or	eax, eax
	jz	9f
	test	eax, 0x80000000
	jz	1f
	print "ORD  "
	push	edx
	mov	dx, ax
	call	printhex4
	pop	edx
	call	newline
	jmp	0b

1:	print "NAME "
	and	eax, 0x7fffffff
	push	edx
	mov	edx, eax
	call	printhex8
	pop	edx
	call	printspace
	sub	eax, edx
	add	eax, [pe_base]
	# eax point to the hint/name table
	push_	esi edx
	mov	esi, eax
	lodsw	# hint
	mov	dx, ax
		mov	eax, esi
	call	printhex2
	call	printspace
	call	print	#name
	pop_	edx esi

		DEBUG_DWORD edi	# target (ptr storage)
		DEBUG_DWORD [ebx]
		# resolve symbol
		push_	edi esi eax
		mov	edi, [esp + 12]	# get libname
		mov	esi, eax
		call	find_symbol #in: esi=sym, edi=lib; out: eax
		jc	1f
		printc 0xf0, "Found symbol: "
		push edx; mov edx, eax
		call	printhex8
		pop edx
		call	printspace
			mov	edi, [esp + 8] # get edi=target
			DEBUG_DWORD edi
			sub edi, edx; 
			DEBUG_DWORD edi
			DEBUG_DWORD [pe_base]
			add edi, [pe_base]
			DEBUG_DWORD edi
			# adjust for flat
			push edx
			GDT_GET_BASE edx, ds
			add	eax, edx
			DEBUG_DWORD eax
			pop edx
			stosd

		jmp	2f
	1:	printc 0xf4, "symbol not found"
	2:
		pop_	eax esi edi


		
	call	newline
	jmp	0b

9:	pop_	edi edi ebx
	ret

# in: esi = section table entry
# in: edi = string table
# out: eax = ptr to string
coff_print_sect_name$:
	cmp	byte ptr [esi], '/'
	jnz	1f
	lea	eax, [esi + 1]
	call	atoi
	jc	4f
	add	eax, edi
	push	eax
	call	_s_print
	ret

4:	printc 4, "invalid name:"

1:	push_	esi ecx
	mov	ecx, 8
0:	lodsb
	or	al, al
	jz	1f
	call	printchar
	loop	0b
1:	pop_	ecx esi
	mov	eax, esi
3:	ret



coff_oh_pe32p$:
	println "PE32+ not implemented"
	ret

.struct 0
coff_symtab_name:	.space 8	# asciz or stringtab_idx<<16 (lo dword=0)
coff_symtab_value:	.long 0		# meaning depends sectNr and storagecl
coff_symtab_section:	.word 0		# 5.4.2; signed int, 1based idx sectbl
			# -2: DEBUG symbol
			# -1: ABSOLUTE - non-relocatable, not an address
			# 0: UNDEFINED - symbol record not yet assigned a section
			# 1+: common symbol; size is field's value
coff_symtab_type:	.word 0		# 0x20=func, 0x00=not func; 5.4.3
	# LSB: simple/base data type: int, float, ...:
	# IMAGE_SYM_TYPE*
	#	0: NULL
	#	1: void
	#	2: char (signed byte)
	#	3: short (2 byte signed word)
	#	4: int (natural integer, usually dword)
	#	5: long (4 byte signed dword)
	#	6: float
	#	7: double
	#	8: struct
	#	9: union
	#	10: enum
	#	11: MOE (member of enum - specific value)
	#	12: byte (unsigned 1 byte)
	#	13: word (unsigned 2 byte)
	#	14: unsigned natural-sized int (usually 4 bytes)
	#	15: dword (unsigned 4-byte int)
	# MSB: complex type, if any: none, ptr, function, array
	# IMAGE_SYM_DTYPE_*
	#	0: NULL - no derived type/simple scalar
	#	1: base-type pointer
	#	2: function returning base type
	#	3: array of base type
coff_symtab_sc:		.byte 0		# storage class; 5.4.4
	# IMAGE_SYM_CLASS_*
	#	-1: end of function (debugging)
	#	0: NULL (no assigned storage class)
	#	1: automatic (stack) variable. value field: stack frame offs
	#	2: external symbol. value field: sc==UNDEF?size:offset in sect
	#	3: static; value:==0?section name:offs in section
	#	4: register variable; value= reg nr
	#	5: externally defined symbol
	#	6: code label; value=offs in sect
	#	7: undefined code label
	#	8: structure member; value=nth member
	#	9: argument: nth formal function parameter
	#	10: structure-tag name entry
	#	11: nth union member field
	#	12: union tag-name entry
	#	13: typedef entry
	#	14: undefined static (static data decl)
	#	15: enum type tagname entry
	#	16: nth member of enum 
	#	17: register parameter
	#	18: bit field reference: nth bit
	#	100: .bb/.eb (begin/end of block).value=reloc addr of code
	#	101: .bf/.ef[funcsize] (begin/end func), .lf [#srclines in func]
	#	102: end of structure
	#	103: source-file; followed by aux records naming the file
	#	104: section definition (MS uses static storage class instead)
	#	105: weak external; 5.5.3
	#	107: CLR token - name=asciz hex token value; 5.5.7
coff_symtab_nx:		.byte 0		# nr aux entries following

.text32


coff_print_symtab$:
	mov	esi, [ebx + coff_h_symtab]
	DEBUG_DWORD esi
	mov	ecx, [ebx + coff_h_symcount]
#	add	esi, ebx
	add esi, [pe_base]	# or coff_base?
	call more

	println "value... sect type storcls nx name"

0:	add	esi, 8	# skip name
	lodsd;	mov edx, eax; call printhex8; call printspace # value
	lodsw;	mov dx, ax; call printhex4; call printspace # section table index ptr
	lodsw;	mov dx, ax; call printhex4; call printspace # type
	lodsb;	call coff_symtab_print_sc$
		#mov dl, al; call printhex2;
		call printspace # sc: storage class
	lodsb;	mov dl, al; call printhex2; call printspace # nx: nr aux sym
	sub	esi, 18
	call	coff_symtab_print_name$
	add	esi, 18-8
	call	coff_symtab_print_aux$
	call	newline
	test	cl, 15
	jnz	1f
	call	more
1:
#	loop	0b
dec ecx;jnz 0b
	ret

# in: esi = ptr to symtab name entry
# in: edi = ptr to string table
coff_symtab_print_name$:
	# symname - 5.4.1
	cmp	dword ptr [esi], 0
	jnz	1f
	mov	eax, [esi + 4]
	add	esi, 8
	add	eax, edi
	push	eax
	call	_s_print
	ret

1:	push	ecx
	mov	ecx, 8
0:	lodsb
	call	printchar
	loop	0b
	pop	ecx
	ret

# in: al = storage class
coff_symtab_print_sc$:
	push	esi
	movzx	eax, al
	mov	dl, al
	LOAD_TXT "EOFN"
	cmp	al, -1
	jz	2f
	cmp	al, 107
	ja	9f
	cmp	al, 100
	jb	1f
	# 100..107:
	sub	al, 100
	LOAD_TXT "BLCK\0FUNC\0EOS \0SRCF\0SECT\0WEXT\0????\0CLRT"
	add	esi, eax
	lea	esi, [esi + eax*4]
	jmp	2f

1:	cmp	al, 18
	ja	9f
	.data SECTION_DATA_STRINGS
	99: .asciz "NULL", "STCK", "EXT ", "STAT", "REG ","EXTD", "CODE","UNDF"
	.asciz "SMEM", "ARG ", "STAG", "UMEM", "UTAG", "TDEF", "STTD", "ETAG"
	.asciz "EMEM", "REGP", "BITF"
	.text32
	mov	esi, offset 99b
	add	esi, eax
	lea	esi, [esi + eax * 4]
	#jmp	2f
	
	#	-1: end of function (debugging)
	#	0: NULL (no assigned storage class)
	#	1: automatic (stack) variable. value field: stack frame offs
	#	2: external symbol. value field: sc==UNDEF?size:offset in sect
	#	3: static; value:==0?section name:offs in section
	#	4: register variable; value= reg nr
	#	5: externally defined symbol
	#	6: code label; value=offs in sect
	#	7: undefined code label
	#	8: structure member; value=nth member
	#	9: argument: nth formal function parameter
	#	10: structure-tag name entry
	#	11: nth union member field
	#	12: union tag-name entry
	#	13: typedef entry
	#	14: undefined static (static data decl)
	#	15: enum type tagname entry
	#	16: nth member of enum 
	#	17: register parameter
	#	18: bit field reference: nth bit
	#	100: .bb/.eb (begin/end of block).value=reloc addr of code
	#	101: .bf/.ef[funcsize] (begin/end func), .lf [#srclines in func]
	#	102: end of structure
	#	103: source-file; followed by aux records naming the file
	#	104: section definition (MS uses static storage class instead)
	#	105: weak external; 5.5.3
	#	107: CLR token - name=asciz hex token value; 5.5.7
2:	call	printhex2
	call	printspace
	call	print
0:	pop	esi
	ret
9:	call	printhex2
	call	printspace
	call	printspace
	call	printspace
	call	printspace
	call	printspace
	jmp	0b


# in: esi = ptr to aux entry - to be checked!
coff_symtab_print_aux$:
	DEBUG_BYTE [esi-18+coff_symtab_nx], "NX"
	cmp	[esi - 18 + coff_symtab_nx], byte ptr 0
	jz	9f

	mov	eax, [esi - 18 + coff_symtab_type]
	# eax = [lo byte sect][byte sc][word type]
	and	eax, 0x00ffffff

# aux format 1: function definition:
	#cmp	eax, 0x020020	# [0x02 = sc ext] [0x0020=type FUNC]
	#jnz	1f
#	cmp	word ptr [esi - 18 + coff_symtab_section], 0
#	jbe	1f	# or jg	# section nr must be >0
	cmp	byte ptr [esi - 18 + coff_symtab_sc], 2 # ext
	jnz	1f
	.struct 0	# Function def AUX format:
	coff_symtab_aux_fn_tagidx:	.long 0	# symtab idx for .bf sym rec
	coff_symtab_aux_fn_totsize:	.long 0
	coff_symtab_aux_fn_linenrptr:	.long 0
	coff_symtab_aux_fn_nextfnptr:	.long 0
		.word 0	# unused
	.text32
	call	newline
	print " AUX1: tagidx="
	lodsd; mov edx, eax; call printhex8
	print " totsize="
	lodsd; mov edx, eax; call printhex8
	print " linenrptr="
	lodsd; mov edx, eax; call printhex8
	print " nextfnptr="
	lodsd; mov edx, eax; call printhex8
	add	esi, 18	-16# skip entry
	dec	ecx
	ret

# AUX format
1:	cmp	byte ptr [esi - 18 + coff_symtab_sc], 103	# .file
	jnz	1f
	# name should be .file:
	cmp	dword ptr [esi - 18], ('.')|('f'<<8)|('i'<<16)|('l'<<24)
	jnz	1f
	cmp	word ptr [esi - 18+4], ('e')
	jnz	1f
	push_	esi ecx
	mov	ecx, 18
	call	nprint
	pop_	ecx esi
	add	esi, 18
	dec	ecx
	ret


# AUX format
1:	cmp	byte ptr [esi - 18 + coff_symtab_sc], 3	# static
	jnz	1f
	.if 0
	# check if name is section name
	mov	edx, [esi - 18]
	or	edx, edx
	jnz	2f
	mov	edx, [esi -18 + 4]
	add	edx, edi
	mov	dl, [edx]
2:	cmp	dl, '.'	# section name check
	jnz	1f
	.endif

	call	newline
	print " AUX5: len="
	lodsd;	mov edx, eax; call printhex8
	print " #relocs="
	lodsw;	mov dx, ax; call printhex4
	print " #linenrs="
	lodsw;	mov dx, ax; call printhex4
	print " #cksum="
	lodsd;	mov edx, eax; call printhex8
	print " nr="
	lodsw;	mov dx, ax; call printhex4
	print " sel="	# COMDAT selection:
	# 1=nodups,2=any,3=samesize,4=exactmatch,5=associative,6=largest
	lodsb;	mov dl, al; call printhex2
	add	esi, 3	# unused
	dec	ecx
	ret

1:	printc 4, "AUX unknown"
9:	ret
