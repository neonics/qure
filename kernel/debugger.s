######################################################################
.intel_syntax noprefix

.data SECTION_DATA_BSS
debug_registers$:	.space 4 * 32
kernel_symtab:		.long 0
kernel_symtab_size:	.long 0
.text32

debug_regstore$:
	mov	[debug_registers$ + 4 * 0], eax
	mov	[debug_registers$ + 4 * 1], ebx
	mov	[debug_registers$ + 4 * 2], ecx
	mov	[debug_registers$ + 4 * 3], edx
	mov	[debug_registers$ + 4 * 4], esi
	mov	[debug_registers$ + 4 * 5], edi
	mov	[debug_registers$ + 4 * 6], ebp
	mov	[debug_registers$ + 4 * 7], esp
	sub	[debug_registers$ + 4 * 7], dword ptr 6	# pushf/pushcolor adjust
	mov	[debug_registers$ + 4 * 8], cs
	mov	[debug_registers$ + 4 * 9], ds
	mov	[debug_registers$ + 4 * 10], es
	mov	[debug_registers$ + 4 * 11], ss
	ret


.macro DEBUG_REGDIFF0 nr, reg
	cmp	[debug_registers$ + 4 * \nr], \reg
	jz	88f
	print	"\reg: "
	push	edx
	mov	edx, [debug_registers$ + 4 * \nr]
	call	printhex8
	print	" -> "
	pop	edx
	push	edx
	mov	edx, \reg
	.if \reg == esp
	add	edx, 6
	.endif
	call	printhex8
	pop	edx
	call	newline
88:
.endm

.macro DEBUG_REGDIFF1 nr, reg
	push	eax
	mov	eax, \reg
	DEBUG_REGDIFF0 \nr, eax
	pop	eax
.endm


debug_regdiff$:
	pushf
	pushcolor 0xf4
	DEBUG_REGDIFF0 0, eax
	DEBUG_REGDIFF0 1, ebx
	DEBUG_REGDIFF0 2, ecx
	DEBUG_REGDIFF0 3, edx
	DEBUG_REGDIFF0 4, esi
	DEBUG_REGDIFF0 5, edi
	DEBUG_REGDIFF0 6, ebp
	DEBUG_REGDIFF0 7, esp
	DEBUG_REGDIFF1 8, cs
	DEBUG_REGDIFF1 9, ds
	DEBUG_REGDIFF1 10, es
	DEBUG_REGDIFF1 11, ss
	popcolor
	popf
	ret


.macro DEBUG_REGSTORE name=""
	DEBUG "\name"
	call	debug_regstore$
.endm
.macro DEBUG_REGDIFF
	call	debug_regdiff$
.endm


.macro BREAKPOINT label
	pushf
	push 	eax
	PRINTC 0xf0, "\label"
	xor	eax, eax
	call	keyboard
	pop	eax
	popf
.endm



.text32
debug_load_symboltable:
.if 0 # if ISO9660 implements multiple sector reading,
	LOAD_TXT "/a/BOOT/KERNEL.SYM", eax
	mov	cl, [boot_drive]
	add	cl, 'a'
	mov	[eax + 1], cl
	call	fs_openfile	# out: eax = file handle
	jc	1f
	call	fs_handle_read # in: eax = handle; out: esi, ecx
	jc	1f

	# copy buffer
	mov	eax, ecx
	call	malloc
	mov	[kernel_symtab], eax
	mov	[kernel_symtab_size], ecx
	mov	edi, eax
	rep	movsb
1:	call	fs_close
	ret
.elseif 1 # OR if bootloader also loads the symbol table.

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
	.endif

	.if DEBUG_RAMDISK_DIY
	mov	edx, fs:[eax + 32 + 4]	# load start
	.else
	mov	edx, [symtab_load_start_flat]
	.endif
	or	edx, edx
	jz	9f
	I "Found symboltable: "
	GDT_GET_BASE eax, ds
	cmp	eax, edx
	ja	8f
	sub	edx, eax
	mov	[kernel_symtab], edx
	mov	ebx, edx
	call	printhex8
	.if DEBUG_RAMDISK_DIY
	mov	edx, fs:[eax + 32 + 12]	# load end
	.else
	mov	edx, [symtab_load_end_flat]
	sub	edx, eax
	.endif
	printchar '-'
	call	printhex8
	I2 " size "
	sub	edx, ebx
	call	printhex8
	mov	[kernel_symtab_size], edx
	I2 " symbols "
	mov	edx, [ebx]
	call	printdec32
	print " ("
	call	printhex8
	println ")"
	ret

8:	printlnc 12, "error: symboltable before kernel: "
	call	printhex8
	printc 12, "data base: "
	mov	eax, edx
	call	printhex8
9:	ret
.else # lame - require 2 builds due to the inclusion of output generated
	# after compilation.
	.data SECTION_DATA_STRINGS # not pure asciiz...
	ksym: .incbin "../root/boot/kernel.sym"
	0:
	.text32
	mov	[kernel_symtab], dword ptr offset ksym
	mov	[kernel_symtab_size], dword ptr (offset 0b - offset ksym)
	ret
.endif

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
	ret
9:	ret



# in: eax = address
debug_printsymbol:
	push	esi
	call	debug_getsymbol
	jc	1f
	pushcolor 14
	call	print
	popcolor
1:	pop	esi
	ret


.data SECTION_DATA_STRINGS
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


# task
debugger:
	PIC_GET_MASK
	push	eax
	PIC_SET_MASK ~(1<<IRQ_KEYBOARD | 1<<IRQ_TIMER)
	sti	# for keyboard. Todo: mask other interrupts.

1:	printc_ 0xb8, "Debugger: h=help c=continue p=printregisters"

0:	printc_ 0xb8, "> "
	xor	ax, ax
	call	keyboard
	call	newline
	cmp	al, 'c'
	jz	9f
	cmp	al, 'p'
	jz	2f
	cmp	al, 'h'
	jz	1b
	jmp	0b


9:	pop	eax
	PIC_SET_MASK
	ret

2:	call	printregisters
	jmp	0b
