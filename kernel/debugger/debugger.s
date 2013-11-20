######################################################################
.intel_syntax noprefix

.data SECTION_DATA_BSS
kernel_reloc:		.long 0
kernel_reloc_size:	.long 0
kernel_symtab:		.long 0
kernel_symtab_size:	.long 0
kernel_stabs:		.long 0
kernel_stabs_size:	.long 0

.text32
debug_load_symboltable:	# bootloader/ramdisk preloaded
DEBUG_RAMDISK_DIY=0
	.if DEBUG_RAMDISK_DIY
	movzx	eax, word ptr [bootloader_ds]
	movzx	ebx, word ptr [ramdisk]
	shl	eax, 4
	add	eax, ebx
	mov	bx, SEL_flatDS
	mov	fs, bx
	cmp	dword ptr fs:[eax + 0], 'R'|('A'<<8)|('M'<<16)|('D'<<24)
	jnz	9f
	cmp	dword ptr fs:[eax + 4], 'I'|('S'<<8)|('K'<<16)|('0'<<24)
	jnz	9f
	mov	ecx, fs:[eax + 8]
	cmp	ecx, 2
	jb	9f
	add	eax, 32
	.endif


	GDT_GET_BASE ecx, ds

	.macro DEBUG_LOAD_TABLE name, label, mmaptype, isreloc=0

	.if DEBUG_RAMDISK_DIY
	mov	edx, fs:[eax + 4]	# load start
	mov	ebx, fs:[eax + 12]	# load end
	.else
	# this depends on realmode.s initializing these
	mov	edx, [\name\()_load_start_flat]
	mov	ebx, [\name\()_load_end_flat]
	.endif
	mov	edi, MEMORY_MAP_TYPE_\mmaptype
	call	ramdisk_load_image	# updates memory map
	I "\label: "
	sub	edx, ecx
	js	8f
	mov	[kernel_\name\()], edx	# load_start ds-relative
	mov	ebx, edx
	call	printhex8
	.if DEBUG_RAMDISK_DIY
	mov	edx, fs:[eax + 12]	# load end
	add	eax, 32
	.else
	mov	edx, [\name\()_load_end_flat]
	sub	edx, ecx
	.endif
	printchar '-'
	call	printhex8
	I2 " size "
	sub	edx, ebx
	call	printhex8
	mov	[kernel_\name\()_size], edx
	mov	edx, [ebx]
	.if \isreloc
	I2 " addr16: "
	call	printdec32
	lea	edx, [ebx + edx * 2 + 4]
	mov	edx, [edx]
	I2 " addr32: "
	call	printdec32
	call	newline
	.else
	I2 " symbols "
	call	printdec32
	print " ("
	call	printhex8
	println ")"
	.endif
	.endm

	DEBUG_LOAD_TABLE reloc, "relocation table", RELOC, 1
	DEBUG_LOAD_TABLE symtab, "symbol table", SYMTAB
	DEBUG_LOAD_TABLE stabs, "source line table", SRCTAB
	ret

8:	printlnc 12, "error: symboltable before kernel: "
	call	printhex8
	printc 12, "data base: "
	mov	eax, edx
	call	printhex8
9:	debug "error"
	ret

# in: edx = load start
# in: ebx = load end
# in: edi = MEMORY_MAP_TYPE_*
# Format:
#   .long lba, mem_start, sectors, mem_end
ramdisk_load_image:
	or	edx, edx
	jnz	1f
	printlnc 5, "image not loaded"
	ret

1:	sub	ebx, edx	# ebx = load size
	call	memory_map_update_region	# in: edx, ebx, edi
	ret

# Idea:
# Specify another table, containing argument definitions.
# This table could be of equal length to the symbol table, containing relative
# offsets to the area after the string table.
# This table could be variable length (specified in symboltable), and would
# be needed to be rep-scasd't.
# An example of such a method is 'schedule', which is known to be an ISR-style method.
# The first argument on the stack - the next higher dword - is eax.
# The second argument is eip, the third cs, the fourth eflags.
# The table entry could then be a symbol reference table, where these symbols
# are merged in the main symbol table, or, a separate symbol table, to avoid scanning
# these special symbols in general scans.
#
# Approach 1:
# A second parameter ebp is used to check the symbol at a fixed distance
# in the stack to see if there is an argument that matches the distance.
# This could be encoded in a fixed-size array of words, one for each symbol,
# encoding the relative start/end offsets (min/max distance to the symbol).
# A second word could be an index into the argument list, capping the symbols to 65k.
#
# Approach 2:
# Or, when a symbol is found, it's argument data is looked-up
# and remembered in another register. Since the stack is traversed in an orderly
# fashion, anytime a new symbol is found - of a certain type - it replaces the current
# symbol. A register then is shared between the getsymbol method and the stack loop,
# containing a pointer to the argument definitions for the current symbol.
# Special care needs to be taken to avoid taking an argument as a return address.

# in: edx
# out: esi
# out: CF
debug_getsymbol:
	mov	esi, [kernel_symtab]
	or	esi, esi
	stc
	jz	9f

	push	ecx
	push	edi
	push	eax
	mov	eax, edx
	mov	ecx, [esi]
	lea	edi, [esi + 4]
	repnz	scasd
	stc
	jnz	1f

	mov	ecx, [esi]
	mov	edi, [edi - 4 + ecx * 4]
	lea	esi, [esi + 4 + ecx * 8]
	lea	esi, [esi + edi]
	clc
1:	pop	eax
	pop	edi
	pop	ecx
9:	ret


# in: edx = symbol name string ptr
# out: edx = symbol address
# out: CF
debug_findsymboladdr:
	mov	esi, [kernel_symtab]
	or	esi, esi
	stc
	jz	9f

	push_	eax ecx ebx edi
	mov	edi, edx	# backup
	mov	eax, edx	# arg sym name
	call	strlen
	mov	edx, eax	# edx = strlen of sym to find

	##

	lodsd	# first dword: nr of hex addresses, and symbols.
	lea	ebx, [esi + eax * 8]	# start of string table

	lea	esi, [esi + eax * 4]	# start of string ptr
	mov	ecx, eax

########
	# the ecx dwords found at esi are relative to ebx
0:	lodsd
	push_	esi ecx
	mov	ecx, [esi]	# next ptr
	sub	ecx, eax	# cur ptr
	dec	ecx		# it includes the 0 delim

	cmp	ecx, edx	# compare string lengths
	jnz	1f

	lea	esi, [ebx + eax]	# point to string

	push	edi
	repz	cmpsb
	pop	edi

1:	pop_	ecx esi
	jz	1f
	loop	0b
	stc
########
0:	pop_	edi ebx ecx eax
9:	ret

1:	mov	ebx, [kernel_symtab]
	mov	edx, [ebx]	# nr of entries
	sub	edx, ecx
	lea	edx, [ebx + 4 + edx * 4]
	mov	edx, [edx]
	jmp	0b

# Expects symboltable sorted by address.
#
# in: edx
# out: eax = preceeding symbol address
# out: esi = preceeding symbol label
# out: ebx = succeeding symbol address
# out: edi = succeeding symbol label
# out: CF
debug_get_preceeding_symbol:
	mov	esi, [kernel_symtab]
	or	esi, esi
	stc
	jz	9f

	push	ecx

	mov	ecx, [esi]

	cmp	edx, [esi + ecx * 4]
	cmc
	jb	8f	# dont yield results for out-of-range

	# O(log2(ecx))
	xor	eax, eax
0:	shr	ecx, 1
	jz	1f
2:	add	eax, ecx	# [....eax....]
	cmp	edx, [esi + 4 + eax * 4]
	jz	0f	# exact match
	ja	0b		# [....|<eax....>]
	sub	eax, ecx	# [<eax....>|....]
	jmp	0b
# odd
1:	jnc	0f	# even
3:	cmp	edx, [esi + 8 + eax * 4]
	jb	0f
	inc	eax
	cmp	eax, [esi]
	jb	3b 	# should not loop > 1, but 5 times is seen..

0:	mov	ecx, [esi]

	push	dword ptr [esi + 4 + eax * 4]	# preceeding symbol address
	push	dword ptr [esi + 8 + eax * 4]	# succeeding symbol address
	lea	ebx, [esi + 4 + ecx * 4]	#ebx->str offset array
	mov	edi, [ebx + eax * 4 + 4]# edi->str offset
	mov	eax, [ebx + eax * 4]	# eax->str offset
	lea	eax, [ebx + eax]	# eax = str ptr - ecx * 4
	lea	esi, [eax + ecx * 4]	# preceeding symbol label
	lea	edi, [ebx + edi]
	lea	edi, [edi + ecx * 4]# succeeding symbol label
	pop	ebx
	pop	eax

	clc
8:	pop	ecx

9:	ret


# The stabs format used here is generated by util/stabs.pl.
#
# The first dword is the number of line/addr entries, speciying the length
# of two arrays that follow it: first, an array of addresses, followed
# by an array of dwords with file and line encoded.
# Then follows a stringtable, where the first part is dword offsets
# relative to this stringtable, followed by the strings. The symboltable
# above uses a different approach as the length of the string array is
# equal to the other arrays, and thus the offset is relative to the start
# of the strings themselves.
#
# Example format, for 3 source lines spread over 2 source files:
# size: .long 3	# 3 addresses
# addr: .rept 3; .long 0xsomething; .endr
# data: .rept 3; .word line, sfidx; .endr
# strtb: .long s1 - strtb; .long s2 - strtb;
# s1: .asciz "foo";
# s2: .asciz "bar";
#
# For the symbol table used above, the strtb part would look like this:
# strtb: .long s1 - strings; .long s2 - strings;
# strings:
#  s1: .asciz "foo";
#  s2: .asciz "bar";

####################
# COMPRESSION UPDATE
#
# The stabs address table is stored in a 2 level hash.
# First there is an array (preceeded by a word count) listing the
# high 16 bits of all addresses uniquely. At current the kernel's
# highest address is 0x0002...., so the array consists of 0, 1, 2:
#
# .word 3
# .word 0, 1, 2	# addresses 0x0000<<16, 0x0001<<16, 0x0002<<16
#
# Next follow 3 arrays in the same format, one per high-16 bit address.
#
# .word <65536
# .word[] # lo 16 bit values for addresses with high 16 bit 0x0000
# .word <65536
# .word[] # lo 16 bit values for addresses with high 16 bit 0x0001
# .word <65536
# .word[] # lo 16 bit values for addresses with high 16 bit 0x0002
#
#
# in: edx = memory address
# out: esi = source filename
# out: eax = source line number
# out: CF
.data SECTION_DATA_BSS
stabs_data: .long 0
stabs_sfile:.long 0
.text32
0:	# init
	# we calculate the offset to the data array:
	mov	esi, [kernel_stabs]
	or	esi, esi
	jz	9f
	lodsd

	xor	eax, eax
	lodsw
	lea	esi, [esi + eax * 2]
	push	ecx
	mov	ecx, eax
1:	lodsw
	lea	esi, [esi + eax * 2]
	loop	1b
	pop	ecx
	mov	[stabs_data], esi

	mov	eax, [kernel_stabs]
	mov	eax, [eax]
	and	eax, 0x3fffffff
	lea	esi, [esi + eax * 4]
	mov	[stabs_sfile], esi
	jmp	0f

debug_getsource_compressed:
	cmp	dword ptr [stabs_data], 0
	jz	0b
0:

	push_	edi ecx ebx
	mov	esi, [kernel_stabs]
	or	esi, esi
	jz	9f

	mov	eax, edx
	shr	eax, 16
	movzx	ecx, word ptr [esi + 4]
	mov	ebx, ecx
	lea	edi, [esi+4+2]
	repnz	scasw
	jnz	9f
	neg	cx
	dec	cx
	add	cx, bx

	lea	edi, [esi + 4 + 2 + ebx * 2]
	# edi points to first lo-16 array
	xor	ebx, ebx

	# ecx is now index.
	jecxz	1f
0:	movzx	eax, word ptr [edi]
	add	ebx, eax			# sline cuml count
	lea	edi, [edi + 2 + eax * 2]	# next array
	loop	0b
1:
	# edi points to the subarray
	# ebx contains the skipped source line data elements,
	# i.e. the offset into the data table for the current
	# address table.

	movzx	ecx, word ptr [edi]
	add	edi, 2
	mov	esi, ecx
	mov	ax, dx
	repnz	scasw
	jnz	9f

	neg	cx
	dec	cx
	add	cx, si

	add	ebx, ecx
	# ebx is now index into the data array.

	mov	eax, [stabs_data]
	mov	eax, [eax + ebx * 4]

	mov	ebx, eax
	and	eax, 0xffff
	mov	esi, [stabs_sfile]
	shr	ebx, 16
	add	esi, [esi + ebx * 4]

0:	pop_	ebx ecx edi
	ret

9:	stc
	jmp	0b

# in: edx = memory address
# out: esi = source filename
# out: eax = source line number
# out: CF
debug_getsource:
	mov	esi, [kernel_stabs]
	or	esi, esi
	stc
	jz	9f
	test	dword ptr [esi], 0x40000000
	jnz	debug_getsource_compressed

	push	ecx
	push	edi
	mov	eax, edx
	mov	ecx, [esi]	# nr of lines/addresses
	lea	edi, [esi + 4]	# address array
	repnz	scasd
	stc
	jnz	1f
	mov	ecx, [esi]
	mov	edi, [edi - 4 + ecx * 4]	# [file<<16|line] array
	movzx	eax, di				# line
	shr	edi, 16				# source file index
	lea	esi, [esi + 4 + ecx * 8]	# source file offsets
	mov	edi, [esi + edi * 4]		# source file offset
	lea	esi, [esi + edi]		# source filename
	clc
1:	pop	edi
	pop	ecx
9:	ret



# in: edx = address
debug_printsymbol:
	push_	eax esi edx

	sub	edx, [reloc$] 		# relocation; stabs 0-based.
	jb	9f			# symbol preceeds kernel

	call	debug_getsource
	jc	1f

	push	edx
	add	edx, [reloc$]
	mov	edx, eax
	mov	ah, 11
	call	printc
	printcharc_ 7, ':'
	call	printdec32
	call	printspace
	pop	edx

1:
	add	edx, [reloc$]
	call	debug_getsymbol
	jc	1f
	pushcolor 14
	call	print
	popcolor
	jmp	9f

1:	push	edi
	push	ebx
	call	debug_get_preceeding_symbol
	jc	8f

	pushcolor 13
	call	print
	print	" + "
	sub	edx, eax
	call	printhex4

	printc 7, " | "
	add	edx, eax
	sub	edx, ebx
	neg	edx
	call	printhex4
	print	" - "
	mov	esi, edi
	call	print
	popcolor

8:	pop	ebx
	pop	edi

9:	pop_	edx esi eax
	ret




.section .strings
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

.text32
printregisters:
	pushad
	pushf
	push	ss
	push	gs
	push	fs
	push	es
	push	ds
	push	cs


	call	newline_if
	mov	ebx, esp

	mov	esi, offset regnames$
	mov	ecx, 16	# 6 seg 9 gu 1 flags 1 ip

	PUSHCOLOR 0xf0

	mov	ah, 0b111111	# 6 bits indicating print as word

0:	COLOR	0xf0
	cmp	cl, 16-7
	ja	1f
	printchar_ 'e'
1:	lodsb
	call	printchar
	lodsb
	call	printchar

	COLOR 0xf8
	printchar_ ':'

	COLOR	0xf1
	mov	edx, [ebx]
	add	ebx, 4
	shr	ah, 1
	jc	1f
	call	printhex8
	jmp	2f
1:	call	printhex4
2:	call	printspace

	cmp	ecx, 5
	je	2f
	cmp	ecx, 10
	jne	1f

	# print flag characters
	push	ebx
	push	esi
	push	ecx

	call	printflags$

	pop	ecx
	pop	esi
	pop	ebx

2:	call	newline

1: 	loopnz	0b

	call	newline

	POPCOLOR
	pop	eax # cs
	pop	ds
	pop	es
	pop	fs
	pop	gs
	pop	ss
	popf
	popad
	ret

printflags$:
	mov	esi, offset regnames$ + 32 # flags
	mov	ecx, 16
2:	lodsb
	shr	edx, 1
	setc	bl
	jc	3f
	add	al, 'A' - 'a'
3:	shl	bl, 1
	add	ah, bl
	call	printcharc
	sub	ah, bl
	loop	2b
	ret

#####################################################################
# Printing mutexes
.data SECTION_DATA_BSS
debugger_mutex_col_width$:	.byte 0
.text32
debugger_printcalc_mutex$:
	# calculate mutex name width
	xor	edx, edx
	mov	eax, NUM_MUTEXES
	mov	esi, offset mutex_names
0:	call	strlen_
	cmp	ecx, edx
	jb	1f
	mov	edx, ecx
	stc
1:	adc	esi, ecx
	dec	eax
	jnz	0b
	inc	edx
	mov	[debugger_mutex_col_width$], dl
	ret

debugger_print_mutex$:
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi

	cmp	byte ptr [debugger_mutex_col_width$], 0
	jnz	1f
	call	debugger_printcalc_mutex$
1:

	printc_ 11, "mutex: "
	mov	edx, [mutex]
	call	printbin8
	call	newline

	mov	ecx, NUM_MUTEXES
	mov	esi, offset mutex_owner
	mov	edi, offset mutex_names
########
0:	mov	edx, NUM_MUTEXES
	sub	edx, ecx
	call	printdec32
	printchar_ ':'

	xchg	esi, edi
	push	ecx
	movzx	ecx, byte ptr [debugger_mutex_col_width$]
	add	ecx, esi
	call	print_
	sub	ecx, esi
	jbe	1f
2:	call	printspace
	loop	2b
1:	pop	ecx
	xchg	esi, edi

	printchar_ '='
	lodsd
	mov	edx, eax
	call	printhex8
	or	edx, edx
	jz	1f
	call	printspace
	call	debug_printsymbol
1:	call	newline
	loop	0b
########
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret

DEBUGGER_SWAP_CR3 = 0

.data SECTION_DATA_BSS
debugger_stack_print_lines$:	.long 0
debugger_cmdline_pos$:		.long 0
.text32
# task
debugger:
	push_	ds es
	push	ebp
	PIC_GET_MASK
	push	eax
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax
	#push	dword ptr [mutex]
	push	dword ptr [task_queue_sem]
	push	edx
	push	dword ptr 0	# local storage
	push	esi	# orig stack offset
	push	edi	# stack offset
	mov	ebp, esp
	push	ebx	# stack segment
.if DEBUGGER_SWAP_CR3
	mov	eax, cr3
	push	eax
	mov	eax, [page_directory_phys]
	mov	cr3, eax
.endif

	call	screen_get_scroll_lines
	mov	[debugger_stack_print_lines$], eax

	# enabling timer allows keyboard job: page up etc.
	#call	scheduler_suspend
	#DEBUG_DWORD [mutex]

	#mov	dword ptr [mutex], MUTEX_SCHEDULER # 0#~MUTEX_SCREEN # -1
	mov	dword ptr [task_queue_sem], -1

	PIC_SET_MASK ~(1<<IRQ_KEYBOARD)# | 1<<IRQ_TIMER)
	sti	# for keyboard. Todo: mask other interrupts.
	pushad	# just in case
	mov	al, IRQ_KEYBOARD + IRQ_BASE
	mov	ebx, offset isr_keyboard
	mov	cx, cs
	call	hook_isr
	popad



1:	printlnc_ 0xb8, "Debugger: h=help c=continue p=printregisters s=sched m=mutex"

0:	printcharc_ 0xb0, ' '	# force scroll
	call	screen_get_pos
	mov	[debugger_cmdline_pos$], eax

4:	mov	eax, [debugger_cmdline_pos$]
	call	screen_set_pos

	mov	al, [ebp + 8]
	and	al, 7
	LOAD_TXT "stack"
	jz	2f
	LOAD_TXT "sched"
	cmp	al, 1
	jz	2f
	LOAD_TXT "?????"
2:	printc 0xb8, "(mode:"
	movzx	edx, al
	call	printdec32
	mov	ah, 0xb0
	call	printc
	printc_ 0xb8, ") > "

6:	xor	ax, ax
	call	keyboard

	# use offset as symbols arent defined yet - gas bug
	.if SCREEN_BUFFER
	cmp	[scrolling$], byte ptr 0
	jnz	66f
	cmp	ax, offset K_PGUP
	jz	66f
7:	# continue checking keys if not scroll key
	.endif
	cmp	ax, offset K_UP
	jz	56f
	cmp	ax, offset K_DOWN
	jz	59f
	cmp	ax, offset K_ESC
	jz	10f
	test	eax, K_KEY_CONTROL | K_KEY_ALT
	jnz	6b
	cmp	ax, offset K_TAB
	jz	13f	# mode
	cmp	al, 'c'	# continue
	jz	9f
	cmp	al, 't'	# trap
	jz	22f
	# the rest of the keys/commands has print output, so do newline:
	call	newline
	cmp	al, 'p'	# print registers
	jz	2f
	cmp	al, 'h'	# help
	jz	1b
	cmp	al, 's'	# scheduler (tasks)
	jz	55f
	cmp	al, 'm'	# mutex
	jz	69f
	cmp	al, 'u'	# memory
	jz	3f
	cmp	al, 'e' # cmdline
	jz	33f
	jmp	6b

22:	# toggle trap flag
	# 36: local stack.
	# : 2 + 4*9 + 2 + 8(see idt.s)
	DEBUG_DWORD [ebp + 36 + 2+4*9+2+8+8]
	xor	[ebp + 36 + 2+4*9+2+8+8], dword ptr 1 << 8
	jmp	6b

10:	mov	edi, [ebp]
	jmp	62f
59:	add	edi, 4
	jmp	62f
56:	sub	edi, 4
62:	mov	esi, [ebp + 4]
		# calculate where stack is printed on screen
		call	screen_get_scroll_lines
		sub	eax, [debugger_stack_print_lines$]
		add	[debugger_stack_print_lines$], eax
		mov	edx, 160
		imul	eax, edx
		mov	edx, [stack_print_pos$]
		sub	edx, eax
		jns	1f
		call	debug_print_stack$
		call	screen_get_scroll_lines
		mov	[debugger_stack_print_lines$], eax
		jmp	0b
		1:
	PUSH_SCREENPOS edx
	call	debug_print_stack$
	POP_SCREENPOS
#		mov	eax, [stack_print_lines$]
#		mov	[debugger_stack_print_lines$], eax
	jmp	6b

.if SCREEN_BUFFER
66:	call	scroll	# doesn't flush last line
	jc	7b	# key not handled (not scroll key)
	jmp	4b
.endif

55:	push	esi
	PUSHSTRING "ps"
	mov	esi, esp
	call	cmd_tasks
	add	esp, 4
	pop	esi
	jmp	0b

69:	call	debugger_print_mutex$
	jmp	0b

# mode
13:	mov	al, [ebp + 8]	# update low 3 bits (8 modes max)
	mov	dl, al
	and	al, 0xf8
	inc	dl
	and	dl, 7
	or	al, dl
	mov	[ebp + 8], al
	jmp	4b

9:
.if DEBUGGER_SWAP_CR3
	pop	eax
	mov	cr3, eax
.endif
	call	scheduler_resume
	pop	ebx
	pop	edi
	pop	esi
	add	esp, 4	# local storage
	pop	edx
	pop	dword ptr [task_queue_sem]
	#pop	dword ptr [mutex]
	pop	eax
	PIC_SET_MASK
	pop	ebp
	pop_	es ds
	ret

2:	call	debug_print_exception_registers$# printregisters
	jmp	0b

3:	call	mem_print_handles
	jmp	0b

33:	call	debugger_handle_cmdline$
	jmp	0b


#######################################
DECLARE_CLASS_BEGIN debugger_cmdline, cmdline
DECLARE_CLASS_METHOD cmdline_api_print_prompt, debugger_print_prompt$, OVERRIDE
DECLARE_CLASS_METHOD cmdline_api_execute, debugger_execute$, OVERRIDE
DECLARE_CLASS_END debugger_cmdline
.data SECTION_DATA_BSS
debugger_cmdline$:	.long 0
.text32

debugger_cmdline_init$:
	mov	eax, [debugger_cmdline$]
	or	eax, eax
	jnz	1f
	mov	eax, offset class_debugger_cmdline
	call	class_newinstance
	jc	9f
	mov	[debugger_cmdline$], eax
	call	[eax + cmdline_constructor]
1:	ret

9:	printlnc 4, "debugger: failed to instantiate cmdline"
	stc
	ret

debugger_print_prompt$:
	LOAD_TXT "debugger"
	mov	ecx, 8
	mov	ah, 12
0:	lodsb
	stosw
	loop	0b
	ret

# in: ebx
debugger_execute$:
	call	cmdline_execute$	# tokenize
	.if 0
		push	ebx
		lea	esi, [ebx + cmdline_tokens]
		mov	ebx, [ebx + cmdline_tokens_end]
		call	printtokens
		pop	ebx
	.endif

	lea	esi, [ebx + cmdline_args]
	lodsd
	or	eax, eax
	jz	9f
	cmp	dword ptr [eax], 'e'|('x'<<8)|('i'<<16)|('t'<<24)
	jnz	9f
	cmp	byte ptr [eax+4], 0
	jnz	9f
	call	cmd_quit$

9:	ret

#############################################################

debugger_handle_cmdline$:
	call	debugger_cmdline_init$
	jc	9f

	mov	ebx, eax
	push	ebp
	push	ebx
	mov	ebp, esp	# shell expects [ebp] = ebx

	jmp	start$		# cmd_quit takes care of popping.
9:	printc 4, "debugger cmdline init error"
	ret




################################################################
# Simple Single Step Trace Debugger
#
#  NOTE: cannot handle CPL!=0
#
# Usage:
#	call	init_trace_isr	# call once
#
#    set trap flag: pushfd; ord [esp], 1<<8; popfd;
#
#    or issue int 1.
#
# Keys:
#
#  t	toggle single step tracing
#  r	run until next return at current call depth.
#  \n	step/continue (depending on EFLAGS.TF).
#
# Variables:
#

init_trace_isr:
	mov	eax, offset trace_isr	# relocatable
	DT_SET_OFFSET 1*8, eax, IDT
	ret


.data
.global trace_isr_flags
trace_isr_flags: .byte 0
	TRACE_ISR_RET = 1
trace_call_depth: .long 0	# is reset when 'r' is pressed.

.text32
trace_isr:
	pushad
	lea	ebp, [esp]
	push	ds
	push	es
	mov	eax, SEL_compatDS
	mov	ds, eax

	# write to screen directly: top banner
	mov	eax, SEL_vid_txt
	mov	es, eax
	xor	edi, edi

.if 0	# use this to detect memory writes - software 'drX'.

	# TRAP_ADDR = 0x45dd
	# TRAP_VAL = 0x6601e1c1

	mov	edx, [TRAP_ADDR]
	cmp	edx, TRAP_VAL
	jz	1f
	LOAD_TXT "code modified: "
	mov	ax, 0x4f20
	call	__print
	call	__printhex8
	stosw
	jmp	0f
1:
.endif

	#######################
	# continue-until-return

	test	byte ptr [trace_isr_flags], TRACE_ISR_RET
	jz	2f

	mov	edx, [ebp + 32]	# get eip
	mov	edx, [edx]	# get opcode

	cmp	dl, 0xe8	# call
	jnz	1f
	inc	dword ptr [trace_call_depth]
	jmp	9f
1:

	cmp	dl, 0xc3	# ret
	jnz	9f
	dec	dword ptr [trace_call_depth]
	jns	9f
	and	byte ptr [trace_isr_flags], ~TRACE_ISR_RET
1:

	#######################
	# print information

0:	LOAD_TXT "TRACE"
	mov	ah, 0x4f
	call	__print
	mov	ax, 0x4720
	stosw
	mov	edx, [ebp + 32 + 4]	# cs
	call	__printhex4
	stosw
	mov	edx, [ebp + 32 + 0]	# eip
	sub	edx, [reloc$]		# undo relocation to match disassembly
	call	__printhex8
	stosw
	mov	edx, [ebp + 32 + 8]	# eflags
	call	__printhex8
	stosw
	lea	edx, [ebp+32]	# esp
	call	__printhex8
	stosw
	mov	ah, 0x4e
	mov	edx, [ebp + 32] #[edx]
	mov	edx, [edx]
	call	__printhex8	# opcode

	mov	edi, 160	# newline
	mov	esi, ebp

	# print GPR (general purpose registers) ordered and labelled

	.struct 0
	stack_reg_edi:	.long 0
	stack_reg_esi:	.long 0
	stack_reg_ebp:	.long 0
	stack_reg_esp:	.long 0
	stack_reg_ebx:	.long 0
	stack_reg_edx:	.long 0
	stack_reg_ecx:	.long 0
	stack_reg_eax:	.long 0
	stack_reg_eip:	.long 0
	.text32
	.macro PSR reg
		mov	ah, 0x4b
		LOAD_TXT "\reg:"
		call	__print
		mov	ah, 0x47
		mov	edx, [ebp + stack_reg_\reg]
		call	__printhex8
		stosw
	.endm
	PSR eax
	PSR ebx
	PSR ecx
	PSR edx
	PSR esi
	PSR edi
	mov	edi, 160*2
	PSR ebp
	PSR esp
	.purgem PSR

	# done printing

	mov	eax, ds
	mov	es, eax

	########################
	# await decision

	PIC_SAVE_MASK
	PIC_DISABLE_IRQ IRQ_TIMER

	sti

0:	xor	eax,eax
	call	keyboard
	cmp	al, 't'
	jz	2f
	cmp	al, 'r'
	jz	3f
	cmp	ax, offset K_ENTER
	jnz	0b

	PIC_RESTORE_MASK

	###########
	# return

9:	pop	es
	pop	ds
	popad
	iret

	####################
	# decision handlers

2:	andd	[ebp + 32 + 8], ~(1<<8)	# toggle trace flag
	jmp	9b

3:	xorb	[trace_isr_flags], TRACE_ISR_RET
	mov	dword ptr [trace_call_depth], 0
	jmp	9b


