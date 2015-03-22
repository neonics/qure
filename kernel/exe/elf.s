.intel_syntax noprefix
ELF_DEBUG = 1	# 0..2

######## ELF
.struct 0
elf_ident:		.long 0 # 7f E L F
elf_fileclass:		.byte 0
elf_dataencoding:	.byte 0
elf_fileversion:	.byte 0
.space 16-7
elf_type:		.word 0
elf_machine:		.word 0
elf_version:		.long 0
elf_entry:		.long 0
elf_phoff:		.long 0
elf_shoff:		.long 0
elf_flags:		.long 0
elf_ehsize:		.word 0
elf_phentsize:		.word 0
elf_phnum:		.word 0
elf_shentsize:		.word 0
elf_shnum:		.word 0
elf_shstrndx:		.word 0
.struct 0 # elf_shdr
elf_sh_name:		.long 0
elf_sh_type:		.long 0
	ELF_SHT_NULL	= 0
	ELF_SHT_PROGBITS= 1
	ELF_SHT_SYMTAB	= 2
	ELF_SHT_STRTAB	= 3
	ELF_SHT_RELA	= 4
	ELF_SHT_HASH	= 5
	ELF_SHT_DYNAMIC	= 6
	ELF_SHT_NOTE	= 7
	ELF_SHT_NOBITS	= 8
	ELF_SHT_REL	= 9	# related symbol table
	ELF_SHT_SHLIB	= 10
	ELF_SHT_DYNSYM	= 11
	ELF_SHT_LOPROC	= 0x70000000
	ELF_SHT_HIPROC	= 0x7fffffff
	ELF_SHT_LOUSER	= 0x80000000
	ELF_SHT_HIUSER	= 0xffffffff
elf_sh_flags:		.long 0
	ELF_SHF_WRITE	= 1
	ELF_SHF_ALLOC	= 2
	ELF_SHF_EXEC	= 4
	ELF_SHF_MASKPROC= 0xf0000000
elf_sh_addr:		.long 0
elf_sh_offset:		.long 0
elf_sh_size:		.long 0
elf_sh_link:		.long 0	# string table section header index
	# ELF_SHT: DYNAMIC,HASH,REL,RELA,SYMTAB,DYNSYM
elf_sh_info:		.long 0
	# ELF_SHT: REL, RELA, SYMTAB, DYNSYM
elf_sh_addralign:	.long 0
elf_sh_entsize: 	.long 0
.struct 0 # elf_phdr
elf_ph_type:	.long 0 #.word 0
elf_ph_offset:	.long 0
elf_ph_vaddr:	.long 0
elf_ph_paddr:	.long 0
elf_ph_filesz:	.long 0 #.word 0
elf_ph_memsz:	.long 0 #.word 0
elf_ph_flags:	.long 0 #.word 0
elf_ph_align:	.long 0 #.word 0
.struct 0 # elf_symtab 0
elf_symtab_name:		.long 0
elf_symtab_value:		.long 0
elf_symtab_size:		.long 0
elf_symtab_info:		.byte 0
elf_symtab_other: 		.byte 0
elf_symtab_shndx: 		.word 0
.data SECTION_DATA_BSS 	# NOTE: singleton!
elf_base:	.long 0
elf_vaddr_base:	.long 0	# virtual load address: phent[0].vaddr-phent[0].offset
elf_img_size:	.long 0
elf_stack_top:	.long 0
elf_main:	.long 0
elf_pd:		.long 0
elf_pt:		.long 0
# image layout:
# [elf_base] code/data start
# [elf_base]+[elf_img_size] code/data end, stack start
# ([eld_base]+[elf_img_size]+ELF_STACK_SIZE)&~0xf = [elf_stack_top]
ELF_STACK_SIZE = 4096

##########################################################################

# in: ebx=base
# out: esi = program header
# out: ecx = phnum - I
# out: edi = phentsize 
.macro ELF_FOR table base=ebx, entptr=esi, delta=edi, loop=1
	_ELF_FOR_entptr=\entptr
	_ELF_FOR_delta=\delta
	mov	\entptr, \base
	add	\entptr, [\base + elf_\table\()off]
	movzx	ecx, word ptr [\base + elf_\table\()num]
	movzx	\delta, word ptr [\base + elf_\table\()entsize]
	.if \loop
		jecxz	96f
	.else
		or	ecx, ecx
		jz	96f
	.endif
.endm

.macro ELF_DO
69:
.endm

.macro ELF_LOOP table base=ebx entptr=esi delta=edi, loop=1
	ELF_FOR \table \base \entptr \delta loop=\loop
	ELF_DO
.endm

# in: esi, edi, ecx as per _LOOP
.macro ELF_ENDL loop=1
	add	_ELF_FOR_entptr, _ELF_FOR_delta
	# unfortunately .if . - 69b < 128 doesn't compile..
	.if \loop
	loop	69b
	.else
	dec	ecx
	jnz	69b
	.endif
96:
.endm

###########################################################################
.text32
# in: esi, ecx: elf image
exe_elf:
	push	eax

	# note: singleton access (for now)
	mov	[elf_main], dword ptr -1
	mov	[elf_vaddr_base], dword ptr 0
	mov	[elf_base], esi
	mov	[elf_img_size], ecx
	mov	ebx, esi

	.if ELF_DEBUG
		println "ELF"
		DEBUG_DWORD esi
		DEBUG_DWORD ecx
		DEBUG_DWORD [ebx+elf_entry]
	.endif


	call	malloc_page_phys
	mov	[elf_pt], eax

	.if ELF_DEBUG# > 1
		call	elf_ph_print
		call	elf_sh_print
	.endif

	# iterate sections
	push	ebp
	push	esi
	push	ecx

.if 1 # realloc & move - not needed with paging
	call	elf_ph_process
	mov	[elf_base], ebx
	mov	[elf_img_size], ecx
.endif

	call	elf_sh_process
	jc	9f	# symbol not found etc..

	# image is done.
	# get the entry point address:
	cmp	dword ptr [elf_main], -1
	jz	8f

	.if 1#ELF_DEBUG
		call	newline
		DEBUG "About to execute"
		call	newline
		DEBUG_DWORD [elf_main],"main"
		DEBUG_DWORD [elf_base],"base"
		DEBUG_DWORD [elf_vaddr_base],"vaddr"
		DEBUG_DWORD [elf_img_size],"size"
		call	newline
		DEBUG_DWORD ebx
		mov	eax, ebx
		add	eax, [elf_main]
		DEBUG_DWORD eax,"main abs"
		mov	eax, [eax]
		DEBUG_DWORD eax, "first opc"
		call	more
	.endif


		# ALTERNATIVE: using scheduler
		.if 1
			PUSH_TXT "a.elf"
			push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
			pushd	cs
			add	ebx, [elf_main]
			pushd	ebx
#			mov [esp], dword ptr offset 999f
			KAPI_CALL schedule_task
			#call	more
			990: yield; jmp 990b
			999: printlnc 11, "ELF TASK!"
			990: yield; jmp 990b
		.endif


ELF_REL_KERNEL = 1

.if 1
	GDT_GET_BASE eax, ds
.if ELF_REL_KERNEL
.else
	add	eax, [elf_base]
.endif
	GDT_SET_BASE SEL_taskCS, eax
	GDT_SET_LIMIT SEL_taskCS, 0x001fffff
	GDT_SET_BASE SEL_taskDS, eax
	GDT_SET_LIMIT SEL_taskDS, 0x001fffff

	mov	edx, [elf_main]

		mov	eax, SEL_taskDS
		mov	gs, eax
.if ELF_REL_KERNEL
mov ecx, [elf_base]
.else
xor ecx, ecx
.endif
	.if ELF_DEBUG
		DEBUG_DWORD edx,"main"
		DEBUG_DWORD gs:[ecx + edx],"first opc"
		call newline
		DEBUG_DWORD gs:[ecx+0x115f],"call"
		DEBUG_DWORD gs:[ecx+0x1160],"proxy"
		DEBUG_DWORD gs:[ecx+0x1e76],"maddr"
		DEBUG_DWORD gs:[ecx+0x6050],"ref"
		call	newline
		call	more
		DEBUG_DWORD esp, "PRE CALL ESP"
	.endif
	add edx, ecx
.endif
	push	ds
	push	es
	mov	ebp, esp

	mov	eax, SEL_taskDS | 3
	mov	ds, eax
	mov	es, eax

	.data
	proc_args$:
	STRINGPTR "a.elf"
	.text32

	mov	edi, [elf_stack_top]
	.if ELF_DEBUG
		DEBUG_DWORD edi,"elf_stack_top"
	.endif
	# push the args on the new stack:
	sub	edi, 12
	mov	[edi + 8], dword ptr offset proc_args$	# argv
	mov	[edi + 4], dword ptr 1			# argc
	mov	[edi + 0], dword ptr offset 1f		# ret

	# the ss:esp are used when there is privilege level change
	push	eax	# ss
	push	edi	# dword ptr [elf_stack_top] - 12
	push	dword ptr SEL_taskCS | 2
	push	edx
	retf

1:
	ENTER_CPL0

	mov	esp, ebp
	pop	es
	pop	ds
	mov	edx, eax
	printc 11, "exit code "
	call	printdec32

	.if ELF_DEBUG
		mov	dx, cs
		DEBUG_WORD dx, "cs"
		DEBUG_DWORD esp, "POST CALL ESP"
	.endif

	clc
10:	pushf
	mov	eax, [elf_base]
	call	mfree
	popf
	pop	ecx
	pop	esi
	pop	ebp
	pop	eax
	ret
9:	printlnc 4, "can't resolve symbols"
	stc
	jmp	10b
8:	printlnc 4, "can't find _main"
	stc
	jmp	10b


# processes the relocation and import sections.
elf_sh_process:
	call	elf_calc_shstrtab	# out: edi=shstrtab base ptr

	ELF_LOOP sh delta=edx loop=0
	push	esi
	push	edx
	push	ecx
#######
	mov	eax, [esi + elf_sh_name]
	call	elf_getstring

	LOAD_TXT ".reloc", edx
	call	strcmp	# eax, edx
	jnz	1f
	call	elf_relocation
	clc
	jmp	2f
1:
	LOAD_TXT ".idata", edx
	call	strcmp
	jnz	1f
	call	elf_import	# out: CF
	jmp	2f

1:	LOAD_TXT ".symtab", edx
	call	strcmp
	jnz	1f
	call	elf_symtab_process
	jmp	2f

1:	clc
#######
2:	pop	ecx
	pop	edx
	pop	esi
	jc	9f
	ELF_ENDL loop=0 # esi, edx
9:	ret



# in: ebx = base
# in: esi = strtab section pointer
elf_symtab_process:
	DEBUG_DWORD esi,"processing symbol table"
	push	esi

	call	elf_calc_strtab	# out: edi=linked strtab base ptr
	mov	ecx, [esi + elf_sh_size]
	mov	edx, [esi + elf_sh_entsize]
	mov	esi, [esi + elf_sh_offset]
	add	esi, ebx
	mov	[elf_main], dword ptr -1
0:	# relocate address
	mov	eax, [esi + elf_symtab_value]
	sub	eax, [elf_vaddr_base]
	js	1f	# simple check to see if proper section
	mov	[esi + elf_symtab_value], eax
1:
	# find '_main'
	mov	eax, [esi + elf_symtab_name]

	call	elf_getstring
	.if 0
		push	eax
		call	_s_print
		call	printspace
		push edx; mov edx, [esi + elf_symtab_value]; call printhex8; call newline; pop edx
	.endif

	cmp	dword ptr [eax], '_'|'m'<<8|'a'<<16|'i'<<24
	jnz	1f
	cmp	word ptr [eax + 4], 'n'
	jnz	1f

	mov	eax, [esi + elf_symtab_value]
	mov	[elf_main], eax
	.if ELF_DEBUG
		printc	11, "_main found at: "
		push	edx
		mov	edx, eax
		call	printhex8
		pop	edx
		call	newline
	.endif

1:

	add	esi, edx
	sub	ecx, edx
	jg	0b

	pop	esi

	.if ELF_DEBUG > 1
	call	elf_symtab_print
	.endif

	clc
	ret


elf_symtab_print:
	call	elf_calc_strtab	# out: edi=linked strtab base ptr
#elf_symtab_name:		.long 0
#elf_symtab_value:		.long 0
#elf_symtab_size:		.long 0
#elf_symtab_info:		.byte 0
#elf_symtab_other: 		.byte 0
#elf_symtab_shndx: 		.word 0
	mov	ecx, [esi + elf_sh_size]
	mov	edx, [esi + elf_sh_entsize]
	mov	esi, [esi + elf_sh_offset]
	add	esi, ebx
	println "name.... value... size.... info shndx"
0:	push	edx
	mov	edx, [esi + elf_symtab_name]
	call	printhex8
	call	printspace
	mov	edx, [esi + elf_symtab_value]
	call	printhex8
	call	printspace
	mov	edx, [esi + elf_symtab_size]
	call	printhex8
	call	printspace
	mov	dl, [esi + elf_symtab_info]
	call	printhex2
	call	printspace
	call	printspace
	call	printspace
	mov	dx, [esi + elf_symtab_shndx]
	call	printhex4
	call	printspace
	# 0: undef
	# 0xff00 loreserve
	# 0xff00 loproc
	# 0xff1f hiproc
	# 0xfff1 ABS
	# 0xfff2 COMMON
	# 0xffff hireserve
	push	esi
	push	edi
	push	ecx
	mov	ecx, 8	# text alignment
	call	elf_calc_shstrtab
	LOAD_TXT "UNDEF", eax
	or	dx, dx
	jz	2f
	cmp	dx, 0xff00
	jb	1f
	LOAD_TXT "PROC", eax
	cmp	dx, 0xff1f
	jb	2f
	LOAD_TXT "ABS", eax
	cmp	dx, 0xfff1
	jz	2f
	LOAD_TXT "COMMON", eax
	cmp	dx, 0xfff2
	jz	2f
	LOAD_TXT "?", eax
	jmp	2f

1:	movzx	eax, dx	# section number
	call	elf_get_section_name

2:	mov	esi, eax
	call	print
	call	strlen
	sub	ecx, eax
	jle	2f
	mov	al, ' '
1:	call	printchar
	loop	1b
2:
	pop	ecx
	pop	edi
	pop	esi

	push	esi
	mov	eax, [esi + elf_symtab_name]
	call	elf_getstring
	mov	esi, eax
	call	println
	pop	esi

	pop	edx
	add	esi, edx
	sub	ecx, edx
	jg	0b

	ret


elf_sh_print:
	pushad
	call	elf_calc_shstrtab	# out: edi=shstrtab base ptr
#	mov	esi, [ebx + elf_shoff]
#	add	esi, ebx
#	movzx	ecx, word ptr [ebx + elf_shnum]
#XXXXXXX
#elf_sh_name:		.long 0
#elf_sh_type:		.long 0
#elf_sh_flags:		.long 0
#elf_sh_addr:		.long 0
#elf_sh_offset:		.long 0
#elf_sh_size:		.long 0
#elf_sh_link:		.long 0
#elf_sh_info:		.long 0
#elf_sh_addralign:	.long 0
#elf_sh_entsize: 	.long 0
call newline
println "S  type flg addr.... offset.. size.... link.... info.... align... name"
	ELF_LOOP sh delta=edx, loop=0
########
0:	push	esi
	push	edx
	push	ecx
#######
	movzx	edx, word ptr [ebx + elf_shnum]
	sub	edx, ecx
	call	printhex2
	call	printspace
	mov	edx, [esi + elf_sh_type]; call printhex4;call printspace
	mov	edx, [esi + elf_sh_flags];
		PRINTFLAG dl, ELF_SHF_EXEC, "x", "."
		PRINTFLAG dl, ELF_SHF_ALLOC, "a", "."
		PRINTFLAG dl, ELF_SHF_WRITE, "w", "."
		#call printhex4
		call printspace
	mov	edx, [esi + elf_sh_addr]; call printhex8;call printspace
	mov	edx, [esi + elf_sh_offset]; call printhex8;call printspace
	mov	edx, [esi + elf_sh_size]; call printhex8;call printspace
	mov	edx, [esi + elf_sh_link]; call printhex8;call printspace
	mov	edx, [esi + elf_sh_info]; call printhex8;call printspace
	mov	edx, [esi + elf_sh_addralign]; call printhex8;call printspace

	mov	eax, [esi + elf_sh_name]
	call	elf_getstring
	push	esi
	mov	esi, eax
	call	println
	mov	eax, esi
	pop	esi

	clc
#######
	pop	ecx
	pop	edx
	pop	esi
	#add	esi, edx
	#dec	ecx
	#jnz	0b
	ELF_ENDL loop=0
#	loop	0b
########
	popad
	ret

# in: eax = section number
# out: eax = section name
elf_get_section_name:
	push	edx
	movzx	edx, word ptr [ebx + elf_shentsize]
	imul	eax, edx
	pop	edx
	add	eax, [ebx + elf_shoff]
	add	eax, ebx
	movzx	eax, word ptr [eax + elf_sh_name]
	call	elf_getstring
	ret

# in: ebx = base
# in: esi = section eader
elf_calc_strtab:
	movzx	eax, word ptr [esi + elf_sh_link]
	jmp	1f
# in: ebx = elf image base pointer
# out: edi = pointer to shstrtab section
elf_calc_shstrtab:
	.if ELF_DEBUG > 1
		call	newline
		DEBUG	"shstrtab"
	.endif
	# calculate ptr to string table header
	movzx	eax, word ptr [ebx + elf_shstrndx] # strtab section nr
1:	cmp	ax, word ptr [ebx + elf_shnum]
	jae	9f
	push	edx
	movzx	edx, word ptr [ebx + elf_shentsize]
	imul	eax, edx
	pop	edx
	.if ELF_DEBUG > 2
		DEBUG_DWORD eax
	.endif

	mov	edi, [ebx + elf_shoff]
	add	edi, ebx
	add	edi, eax		# offset into sh array
	.if ELF_DEBUG > 1
		DEBUG_DWORD edi
		DEBUG_DWORD [edi+elf_sh_size]
		DEBUG_DWORD [edi+elf_sh_addr]
		DEBUG_DWORD [edi+elf_sh_offset]
		call	newline
	.endif
	ret

9:	printlnc 4, "Invalid string table"
	stc
	ret


# in: eax = string offset/index
# in: edi = shstrtab pointer
# in: ebx = elf image base
# out: eax = string pointer
elf_getstring:
	cmp	eax, [edi + elf_sh_size]
	jae	8f
	lea	eax, [ebx + eax]
	add	eax, [edi + elf_sh_offset]
	ret
8:	DEBUG_DWORD eax
	DEBUG_DWORD [edi+elf_sh_size]
	LOAD_TXT "String index out of range", eax
	ret



elf_ph_print:
	pushad
	println "type.... offs.... vaddr... paddr... filesize memsize. flags... align..."
	ELF_LOOP ph
	push	esi
	.rept 8
	lodsd; mov edx, eax; call printhex8; call printspace
	.endr
	pop	esi
#	DEBUG_DWORD [esi + elf_ph_vaddr]
#	DEBUG_DWORD [esi + elf_ph_paddr]
#elf_ph_type:	.long 0 #.word 0
#elf_ph_offset:	.long 0
#elf_ph_vaddr:	.long 0
#elf_ph_paddr:	.long 0
#elf_ph_filesz:	.long 0 #.word 0
#elf_ph_memsz:	.long 0 #.word 0
#elf_ph_flags:	.long 0 #.word 0
#elf_ph_align:	.long 0 #.word 0
#	call	malloc_page_phys
	call	newline
	ELF_ENDL
	popad
	ret

elf_ph_print_old$:
	push	edx
	push	edi
	push	esi
	push	ecx
########
	ELF_FOR ph loop=0
	mov	esi, [ebx + elf_phoff]
	add	esi, ebx
	movzx	ecx, word ptr [ebx + elf_phnum]

	print "Program header: "
	.if ELF_DEBUG
		DEBUG_DWORD esi
		DEBUG_DWORD ecx
	.endif
	call	newline
	println	"type offset.. vaddr... paddr... fsz. mmsz flags align"

	ELF_DO

	mov	dx, [esi + elf_ph_type]
	call	printhex4
	call	printspace
	mov	edx, [esi + elf_ph_offset]
	call	printhex8
	call	printspace
	mov	edx, [esi + elf_ph_vaddr]
	call	printhex8
	call	printspace
	mov	edx, [esi + elf_ph_paddr]
	call	printhex8
	call	printspace
	mov	dx, [esi + elf_ph_filesz]
	call	printhex4
	call	printspace
	mov	dx, [esi + elf_ph_memsz]
	call	printhex4
	call	printspace
	mov	dx, [esi + elf_ph_flags]
	call	printhex4
	call	printspace
	call	printspace
	mov	dx, [esi + elf_ph_align]
	call	printhex4
	call	newline

	ELF_ENDL 0
########
	pop	ecx
	pop	esi
	pop	edi
	pop	edx
	ret


# transformation: vaddr += phent[0].offset - phent[0].vaddr
# transformation: paddr =  offset
elf_ph_calc_addr:
	push	edi
	push	edx
	push	edi
	push	esi
	push	ecx
########
	ELF_FOR ph
	mov	eax, [esi + elf_ph_vaddr]
	sub	eax, [esi + elf_ph_offset]
	# use the first entry as the base: TODO: check to see if there's
	# a global load start address..
	mov	edx, [esi + elf_ph_vaddr]
	sub	edx, [esi + elf_ph_offset]
	mov	[elf_vaddr_base], edx
	sub	[ebx + elf_entry], edx

	.if ELF_DEBUG
	DEBUG_DWORD [elf_vaddr_base]
	.endif

	ELF_DO
	mov	edx, [esi + elf_ph_offset]
	mov	[esi + elf_ph_paddr], edx
	sub	[esi + elf_ph_vaddr], eax
	ELF_ENDL
########
	pop	ecx

	pop	esi
	pop	edi
	pop	edx
	pop	edi
	ret

# check if the data follows implemented constraints/assumptions
# in: elf_ph_vaddr: virtual address relative to phent[0]
# out: FLAGS: sum(vaddr) - sum(paddr)
# out: eax = total discrepancy
elf_ph_verify:
	# calculate discrepancy
	xor	eax, eax
	ELF_LOOP ph
	mov	edx, [esi + elf_ph_vaddr]
	sub	edx, eax	# dont propagate
	sub	edx, [esi + elf_ph_paddr]
	js	9f	# make sure total sum doesnt end up 0 even with paddr!=vaddr
	add	eax, edx
	ELF_ENDL
	.if ELF_DEBUG
		DEBUG "discrepancy"
		DEBUG_DWORD eax
	.endif
	or	eax, eax # total sum indicates non-stored space between load's
	js	9f
	ret

9:	printlnc 4, "vaddr < paddr: negative growth/overlap"
	stc
	ret

elf_ph_process:
ret
# loops through the program header, and checks whether:
# - filesize equals memsize
# - specified relative virtual load address matches actual
# Typically a BSS section may be larger in memory than on disk,
# and thus the offsets specified in other headers to not match
# the actual offsets into the buffer, as they refer to the desired
# load addresses.
# This method, when it finds such a discrepancy, allocates a new image
# and shifts the data accordingly.
# in: ecx = elf image size
# in: ebx = elf image base
# out: ebx = new elf image base (if needed)
# out: ecx = new elf image size (if needed)
elf_ph_process_$_make_mem_ok:
	.if ELF_DEBUG
		call	elf_ph_print
		DEBUG "calc"
	.endif

	call	elf_ph_calc_addr

	.if ELF_DEBUG
		DEBUG_DWORD eax
		call	elf_ph_print
		DEBUG "verify"
	.endif

	call	elf_ph_verify
	jc	9f
	add	[elf_img_size], eax

	.if ELF_DEBUG
		DEBUG "alloc"
		DEBUG_DWORD edx
		DEBUG_DWORD [elf_img_size]
	.endif


	mov	edx, [elf_img_size]
	add	edx, ELF_STACK_SIZE + 16	# align
	mov	eax, [elf_base]
	call	mrealloc	# expand: double copy optimization
	jc	9f
	mov	[elf_base], eax
	mov	ebx, eax

	add	eax, [elf_img_size]
	add	eax, ELF_STACK_SIZE + 16
	and	eax, ~0xf
	mov	[elf_stack_top], eax


	.if ELF_DEBUG
		DEBUG "MREALLOC:"
		DEBUG_DWORD ebx
		call	elf_ph_print
		pushad
		call	elf_sh_print
		popad
		DEBUG "move:"
	.endif

	call	elf_ph_move

	.if ELF_DEBUG
		call	elf_ph_print
		call	elf_sh_print
	.endif
9:	ret


elf_ph_move:
DEBUG_DWORD [ebx + 0x5000],"ILT",0xa0
DEBUG_DWORD [ebx + 0x4000],"ILT",0xa0
	push	ebp	# reserve variable pointer
	ELF_LOOP ph base=ebx entptr=esi delta=edi # ecx 
	mov	eax, [esi + elf_ph_vaddr]
	mov	edx, [esi + elf_ph_paddr]
	cmp	eax, edx
	push	ecx
	mov	ebp, esp	# [+0] and [-4]
	push	edi	# delta (sh ent size)
	push	esi	# entry ptr
	jnz	1f
0:	pop	esi
	pop	edi
	pop	ecx
	jc	9f
	ELF_ENDL
9:	pop	ebp
DEBUG "moved.", 0xa0
DEBUG_DWORD [ebx + 0x5000],"ILT",0xa0
DEBUG_DWORD [ebx + 0x4000],"ILT",0xa0
	clc
	ret

# move paddr to vaddr
# in: eax = vaddr
# in: edx = paddr
# in: esi = phent
# in: FLAGS: cmp vaddr, paddr
# in: [esp] = total discrepancy (growth)
1:	jb	1f	# should not happen due to verify
DEBUG "moving", 0xa0; DEBUG_DWORD edx,"from", 0xa0; DEBUG_DWORD eax, "to", 0xa0
DEBUG_DWORD [ebx + 0x5000],"ILT",0xa0
DEBUG_DWORD [ebx + 0x4000],"ILT",0xa0
	mov	edi, eax
	sub	edi, edx	# edi = vaddr - paddr delta
2:
DEBUG_DWORD [ebx + 0x5000],"ILT",0xa0
DEBUG_DWORD [ebx + 0x4000],"ILT",0xa0
	add	[esi + elf_ph_offset], edi	# update addresses
	add	[esi + elf_ph_paddr], edi
	add	esi, [ebp-4]
	loop	2b

DEBUG_DWORD [ebx + 0x5000],"ILT",0xa0
DEBUG_DWORD [ebx + 0x4000],"ILT",0xa0
	.if ELF_DEBUG > 1
		call	newline
		DEBUG "update sh"
	.endif

	# update the section header pointers: esi + elf_sh_offset
	push	edi
	push	eax
	mov	eax, edi	# vaddr - paddr: mem shift

	.if ELF_DEBUG > 1
		DEBUG_DWORD edx
		DEBUG_DWORD eax
		call newline
	.endif

	ELF_LOOP sh	# esi, edi, ecx
	.if ELF_DEBUG > 1
		push	edx
		mov	edx, [esi+elf_sh_offset]
		call	printhex8
		pop	edx
	.endif
	cmp	[esi + elf_sh_offset], edx
	jb	2f
	add	[esi + elf_sh_offset], eax
	.if ELF_DEBUG > 1
		push edx
		mov edx, [esi+elf_sh_offset]
		call printspace
		call printhex8
		pop edx
	.endif
2:	.if ELF_DEBUG > 1
		call	newline
	.endif
	ELF_ENDL
	pop	eax
	pop	edi


	# update the section headers pointer: ebx + elf_shoff
	cmp	[ebx + elf_shoff], edx
	jb	2f

	.if ELF_DEBUG > 1
		DEBUG_DWORD [ebx+elf_shoff]
		DEBUG "->"
	.endif
	add	[ebx + elf_shoff], edi
	.if ELF_DEBUG > 1
		DEBUG_DWORD [ebx+elf_shoff]
	.endif
2:

	# move the data

	mov	ecx, [elf_img_size]
	sub	ecx, edx	# vaddr..end or paddr..(end - ecx)
DEBUG_DWORD edx, "movs from", 0xb0
DEBUG_DWORD eax, "movs to", 0xb0
DEBUG_DWORD [ebx + 0x5000]
DEBUG_DWORD [ebx + 0x5004]
DEBUG_DWORD [ebx + 0x4000]
DEBUG_DWORD [ebx + 0x4004]
	lea	esi, [ebx + edx]	# paddr
	lea	edi, [ebx + eax]	# vaddr

	.if ELF_DEBUG > 1
		call	newline
		DEBUG "move"
		DEBUG_DWORD edx
		DEBUG "->"
		DEBUG_DWORD eax
		DEBUG_DWORD ecx
		call newline
		DEBUG_DWORD ebx
		DEBUG_DWORD esi
		DEBUG "..."
		push esi
		add esi, ecx
		DEBUG_DWORD esi
		pop esi
		DEBUG "->"
		DEBUG_DWORD edi
		DEBUG "..."
		push edi
		add edi, ecx
		DEBUG_DWORD edi
		pop edi


		call newline
		call elf_ph_print
	.endif
DEBUG_DWORD ecx
	std
	add	esi, ecx
	add	edi, ecx
	rep	movsb
	cld

DEBUG_DWORD [ebx + 0x5000]
DEBUG_DWORD [ebx + 0x5004]
DEBUG_DWORD [ebx + 0x4000]
DEBUG_DWORD [ebx + 0x4004]
	clc
	jmp	0b

1:	printc 4, "vaddr < paddr"
	stc
	jmp	0b
###################################


elf_relocation:
	.if ELF_DEBUG
		print "relocation table:"
	.endif
	mov	ecx, [esi + elf_sh_size]
	mov	esi, [esi + elf_sh_offset]
	add	esi, ebx

	# take first entry as base
	mov	edx, [esi]
	mov	eax, edx
	.if ELF_DEBUG
		print " base: "
		call	printhex8
	.endif
	mov	edx, [esi + 4]
	mov	ecx, edx
	.if ELF_DEBUG
		print " blocksize: "
		call	printhex8
		call	newline
	.endif
	sub	ecx, 8	# dont count header
	add	esi, 8	# idem
	shr	ecx, 1

0:	movzx	edx, word ptr [esi]
	.if ELF_DEBUG
		call	printhex4
		call	printspace
	.endif
	or	edx, edx
	jz	1f
	call	elf_relocate_ptr
1:
	.if ELF_DEBUG
		call	newline
	.endif

	add	esi, 2
	loop	0b

	clc
	ret



# in: eax = prog base
# in: dx = reloc entry
elf_relocate_ptr:
	pushad
	and	dh, 15	# low 12 bits only
	add	edx, eax
	.if ELF_DEBUG > 2
		call	printhex8
	.endif

	# edx = offset in image

	push	edi
	# eax = base
	# find program header section
	push	edx
	push	esi
	push	ecx
	mov	esi, [ebx + elf_phoff]
	add	esi, ebx
	movzx	ecx, word ptr [ebx + elf_phnum]
#	DEBUG_DWORD ecx
	or	ecx, ecx
	jz	5f
#	jecxz	5f
	movzx	edx, word ptr [ebx + elf_phentsize]
#	DEBUG_DWORD eax
3:	#DEBUG_DWORD [esi + elf_ph_offset]
	cmp	eax, [esi + elf_ph_offset]
	mov	edi, [esi + elf_ph_vaddr]	# or paddr?
	jz	4f
	add	esi, edx
	loop	3b
5:	printlnc 4, "can't find program header for relocation"
	xor	edi, edi
	stc
4:	pop	ecx
	pop	esi
	pop	edx
	# edi = vaddr
	.if ELF_DEBUG > 2
		DEBUG_DWORD edi
	.endif

	# high 4 bits = type (0=abs/meaningless,3=hilo)
#	test	dh, 3<<4
#	jnz	3f
#	print	"HILO "
#3:
	.if ELF_DEBUG
		print " ["
	.endif
	push	eax
	push	ecx
	mov	ecx, edx
	mov	edx, [ebx + ecx]	# get original value
	.if ELF_DEBUG
		call	printhex8
		call	printspace
	.endif
	sub	edx, edi	# - ph_vaddr
	.if ELF_DEBUG
		DEBUG_DWORD edx
	.endif
		sub	edx, [elf_vaddr_base]
# comment out to use separate cs; leave here to have app cs relative
	.if ELF_REL_KERNEL
	add	edx, [elf_base]
	.endif
		add	edx, eax # prog base
	.if ELF_DEBUG
		call	printhex8
	.endif
	mov	[ebx + ecx], edx
	pop	ecx
	pop	eax
	.if ELF_DEBUG
		print "]"
	.endif
	pop	edi
	popad
	ret



# .idata: see gnu-binutils/src/binutils/dlltool.c
.struct 0
# .idata consists of .idata$[2-7]. Each dll's .idata$2 (etc) are concatenated
# .idata$2: import directory table: array of IMAGE_IMPORT_DESCRIPTOR
elf_idata_idt_ilt:	.long 0	# ptr to import lookup table (idata 4
elf_idata_idt_tds:	.long 0 # timedate stamp (0)
elf_idata_idt_fwdc:	.long 0 # forwarder chain (0)
elf_idata_idt_name:	.long 0 # ptr to lib name (idata 6)
elf_idata_idt_ft:	.long 0 # PIMAGE_THUNK_DATA first thunk: ptr to .idata$5
ELF_IDATA_IDT_STRUCT_SIZE = .
#.idata$3: null terminating entry for idata 2
#.idata$4: import lookup table: array of array of poitners to hint name table
# array for each lib being imported from. Each set terminated with NULL.
#
#.idata$5: import address table: array of arra of p....(same as idata$4, but
#	   loader overwrites with address of function)
#.idata$6: hint name table: {ordinal:.short; fname: .asciz}
#.idata$7: dll name.
.text32
elf_import: # destroys: eax,ecx,edx,esi
#	enter	16
	push	ebp
	sub	esp, 16
	mov	ebp, esp
	push	edi

	mov	ecx, [esi + elf_sh_size]

	.if ELF_DEBUG
		print ".idata IMPORT table:"
		DEBUG_DWORD esi;sub esi, ebx; DEBUG_DWORD esi; add esi, ebx
		DEBUG_DWORD ecx, "size"
		DEBUG_DWORD [esi + elf_sh_offset], "offset"
		call	newline
	.endif

	mov	esi, [esi + elf_sh_offset]
	add	esi, ebx

0:
	.if ELF_DEBUG
		DEBUG_DWORD [esi+elf_idata_idt_ilt], "ILT"
		DEBUG_DWORD [esi+elf_idata_idt_name], "NAME"
		DEBUG_DWORD [esi+elf_idata_idt_ft], "FT"
	.endif

	push	esi
	call	elf_idata_process_lib$	# mod: eax, ecx, edx, esi, edi
	pop	esi
	add	esi, ELF_IDATA_IDT_STRUCT_SIZE
	# check for null entry (size 20 probably)
	cmp	dword ptr [esi], 0
	jnz	0b

	pop	edi
	add	esp, 16
	pop	ebp
	ret

elf_idata_print_idt$:
	call	newline
	LOAD_TXT ".idata", edx
	call	elf_get_section$
	jc	9f

DEBUG "===================", 0xf0
DEBUG_DWORD esi,"idata sh ptr"
		sub esi, ebx; DEBUG_DWORD esi; add esi, ebx
	mov	esi, [esi + elf_sh_offset]
DEBUG_DWORD esi,"idata section"
call newline
	add	esi, ebx

0:
	.if ELF_DEBUG
		sub	esi, ebx
		DEBUG_DWORD esi
		add	esi, ebx
		DEBUG_DWORD [esi+elf_idata_idt_ilt], "ILT"
		DEBUG_DWORD [esi+elf_idata_idt_name], "NAME"
		DEBUG_DWORD [esi+elf_idata_idt_ft], "FT"
		call	newline
		print " ILT: "
		push	esi
		mov	esi, [esi + elf_idata_idt_ilt]
		add	esi, ebx
		push	ecx
		mov	ecx, 10
	1:	lodsw; DEBUG_WORD ax
		or	ax, ax
		jz	1f
		loop	1b
	1:	pop	ecx
		pop	esi
		call	newline

		push	esi
		mov	esi, [esi + elf_idata_idt_ft]
		add	esi, ebx
		push	ecx
		mov	ecx, 10
	1:	lodsw; DEBUG_WORD ax
		or	eax, eax
		jz	1f
		loop	1b
	1:	pop	ecx
		pop	esi
		call	newline


	.endif

	add	esi, ELF_IDATA_IDT_STRUCT_SIZE
	cmp	dword ptr [esi], 0
	jnz	0b

	ret
9:	printc 4, "can't find .idata section"
	ret


# in: esi = ptr to elf_idata_idt structure
elf_idata_process_lib$:
	.if ELF_DEBUG
		push	esi
		mov	esi, [esi + elf_idata_idt_name]
		add	esi, ebx
		print "library name: "
		call	println
		pop	esi

	.endif

	sub esi, ebx; DEBUG_DWORD esi; add esi, ebx
	mov	edx, [esi + elf_idata_idt_ilt]
	DEBUG_DWORD edx, "ILT"

#############################
	mov	edi, esi

	.if ELF_DEBUG
		println "import lookup table: "
	.endif

	push	dword ptr 0	# unresolved symbol counter (so can print all)
	DEBUG_DWORD esi, "idt ptr"
	mov	esi, [esi + elf_idata_idt_ilt]
	DEBUG_DWORD esi, "ilt ptr"
	add	esi, ebx


		push esi
		mov ecx, 10
		0: lodsd; DEBUG_DWORD eax; loop 0b
		pop esi

		pushad; call elf_idata_print_idt$;popad

	xor	ecx, ecx

0:	sub esi, ebx; DEBUG_DWORD esi,"LOADING", 0xb0; add esi, ebx
	lodsd; DEBUG_DWORD eax; DEBUG_DWORD [esi]
	or	eax, eax
	jz	2f
1:
	.if ELF_DEBUG
		mov	edx, eax
		call	printhex8
			# lookup in hint table
		print " ["
	.endif

	push	esi
	lea	esi, [ebx + eax]
	DEBUG_DWORD eax
	DEBUG_DWORD esi
call more
	lodsw
	mov	dx, ax
	DEBUG_WORD dx

	.if ELF_DEBUG
		call	printhex4
		call	printspace
		call	print
	.endif

	# find symbol
	push	edi
	mov	edi, [edi + elf_idata_idt_name]
	add	edi, ebx
	call	find_symbol # in: esi=sym, edi=lib
	pop	edi
	pop	esi
	jnc	4f
	inc	dword ptr [esp]	# # symbols not found
	jmp	3f	# don't update for unfound symbols
4:
	# update symbol
	push	esi
	mov	esi, [edi + elf_idata_idt_ft]
	.if ELF_DEBUG > 1
		DEBUG_DWORD ecx
		DEBUG_DWORD eax
		DEBUG_DWORD esi
	.endif
	add	esi, ebx
	mov	[esi + ecx * 4], eax
	pop	esi
3:
	.if ELF_DEBUG
		println "] "
	.endif
	inc	ecx
	jmp	0b


2: # repeated for each lib, so we need to know the libcount.
DEBUG "end"
#	lodsd
#	or	eax, eax
#	jnz	1b

	pop	eax	# pop unresolved symbol count
	or	eax, eax
	stc
	jnz	9f	# symbol not found

	# same table, but gets overwritten with real pointers...
	# the 'ft' (first thunk) points here.
	# the values i nhere point to the lookup table initally, but
	# are overwritten with the real addresses.

.if ELF_DEBUG
	call	elf_idata_print_iat
	# arrived at hint table:
	call	elf_idata_print_hints
.endif

	clc
9:	ret


.if ELF_DEBUG
elf_idata_print_iat:
	print "import address table:"
	mov eax, esi
	sub eax, ebx
	DEBUG_DWORD eax
0:	lodsd
	or	eax, eax
	jz	1f
2:	mov	edx, eax
	call	printhex8
	call	printspace
	# its the same as  the import lookup table..
	jmp	0b
1:
# if more libs:
#	lodsd
#	or	eax, eax
#	jnz	2b

	call	newline
	ret

elf_idata_print_hints:
	print "hint table: "
	mov ecx, 10
0:
	lodsw			# ordinal
	mov	dx, ax
	call	printhex4
	call	printspace
#cmp	byte ptr [esi], 0
#jz	0f
	call	print_
	print "; "
#	jmp	0b
	loop 0b
0:
	call	newline
	ret
.endif



# in: edx = section name
# out: esi = section pointer
# out: CF
elf_get_section$:
	push_	ecx edi edx
	DEBUG_DWORD edx; DEBUGS edx
	call	elf_calc_shstrtab	# out: edi=shstrtab base ptr

	ELF_LOOP sh delta=edx
	push	esi
	push	edx
	push	ecx
#######
	mov	eax, [esi + elf_sh_name]
	call	elf_getstring	# out: eax = stringptr
	DEBUGS eax
	xchg	edx, [esp + 12]
	call	strcmp	# eax, edx
	xchg	edx, [esp + 12]
	clc
	jz	2f
	stc
#######
2:	pop	ecx
	pop	edx
	pop	esi
	jnc	9f
	ELF_ENDL # esi, edx
9:	pop_	edx edi ecx
	ret




# in: edi = libname
# in: esi = symbol name
# out: eax = symbol address
find_symbol:
	push	ebp
	mov	ebp, esp
	push	dword ptr 0

	.if ELF_DEBUG
		pushcolor 0xf0
		print "finding symbol "
		xchg	edi, esi
		call	print
		printchar '/'
		xchg	esi, edi
		call	print
		print ": "
	.endif

	# (hack) calculate symbol prefix:
	.if 0 # use prefix always
	cmp	[edi], dword ptr 'l' | 'i'<<8 |'b'<<16|'c'<<24
	jnz	1f
	cmp	[edi+4], byte ptr '.'
	jnz	1f
	.endif
	# use prefix:
	mov	[ebp -4], dword ptr 3
1:

	push	ecx
	push	esi
	push	edi
	push	edx
	push	ebx

	call	strlen_
	mov	edx, ecx	# edx = strlen of symbol
	add	edx, [ebp-4]	# prefix len
	mov	edi, esi	# edi = symbol to find

	mov	esi, [kernel_symtab]
	or	esi, esi
	jz	4f	# no symbol table..
	mov	ecx, [esi]
	mov	eax, ecx

	lea	ebx, [esi + eax*4 + 4]	# ebx points to offsets

0:	push	ecx
	push	esi
######
	# esi = base
	push	edx	# calculate string offset
	mov	edx, [ebx]	# str offs
	add	ebx, 4
	lea	edx, [edx + eax * 8]
	lea	esi, [esi + edx + 4]
	pop	edx

	call	strlen_
	cmp	ecx, edx
	jnz	1f

	push	edi
		# (hack) scan prefix
		cmp	dword ptr [ebp-4], 3
		jnz	3f
		push	ecx
		push	eax
		mov	eax, [esi]
		and	eax, 0x00ffffff
		cmp	eax, '_'|'c'<<8|'_'<<16
		pop	eax
		pop	ecx
		jnz	2f
		sub	ecx, [ebp-4]
		add	esi, [ebp-4]
3:	repz	cmpsb
2:	pop	edi
######
1:	pop	esi
	pop	ecx
	jz	1f
	#loop	0b
	dec	ecx
	jnz	0b
	#dec ecx
	#jnz	0b

4:	printc 0xf4, "SYMBOL NOT FOUND: "
	mov	esi, edi
	call	println
	mov	eax, -1
	stc
	jmp	2f

1:
	.if ELF_DEBUG
		printc 0xf3, "FOUND SYMBOL"
	.endif
	# ebx points to str offs
	sub	ebx, esi
	sub	ebx, 4
	shl	eax, 2
	sub	ebx, eax
	mov	eax, [ebx + esi]
	.if ELF_DEBUG
		DEBUG_DWORD ebx
		DEBUG_DWORD eax
	.endif
	clc

2:	pop	ebx
	pop	edx
	pop	edi
	pop	esi
	pop	ecx
	.if ELF_DEBUG
		popcolor
	.endif
	mov	esp, ebp
	pop	ebp
	ret
