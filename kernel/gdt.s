# GDT Format:
# .word limit[15:0]	(limit: 20 bits total)
# .word base[15:0]	(base:  32 bits total)
# .byte base[23:16]
# .byte access		(access: 1 byte: [Pr Privl:Privl 1 Ex DC RW Ac])
#			Pr: Present Bit - 1 for valid sectors (enable)
#			Privl: ring level (0 hi, 3 lo)
#			Ex: Executable bit (1=code, 0=data)
#			DC: Direction (data)/Conforming(code)
#			  Direction/data: 0 grow up,
#			  	1 grow down (offset with seg > limit)
#			  Conforming/code: use of Privl/Ring
#				1 can exec equal/lower ring
#				0 can exec only equal ring
#			RW: readable/writeable
#			  code: readable bit (write always prohibited)
#			  data: writable (read access always)
#			Ac: access bit, set by CPU on access and for TSS
#			
# .nybble(hi) flags[4]	(flags: 4 bits: Gr Sz 0 0)
#			Gr: granularity.
#			  0: limit in 1kb blocks "byte granularity"
#			  1: limit in 4kb blocks "page granularity"
#			Sz: size: 0 if 16 bit pmode, 1 32 bit pmode
# .nybble(lo) limit[19:16]
# .byte base[31:24]
.intel_syntax noprefix
.equ ACC_PR,	1 << 7	# 0b10000000 Present
.equ ACC_RING0,	0 << 5	# 0b01100000 DPL
.equ ACC_RING1,	1 << 5
.equ ACC_RING2,	2 << 5
.equ ACC_RING3,	3 << 5
.equ ACC_NRM,	1 << 4	# 0b00010000 S
.equ ACC_SYS,	0 << 4

.equ ACC_CODE,	1 << 3
.equ ACC_DATA,	0 << 3
.equ ACC_DC,	1 << 2
.equ ACC_RW,	1 << 1
.equ ACC_AC,	1 << 0

.equ FL_GR1kb,	0 << 3
.equ FL_GR4kb,	1 << 3
.equ FL_16,	0 << 2
.equ FL_32,	1 << 2

##
.equ ACCESS_CODE, (ACC_PR|ACC_RING0|ACC_NRM|ACC_CODE|ACC_RW) # 0x9a
.equ ACCESS_DATA, (ACC_PR|ACC_RING0|ACC_NRM|ACC_DATA|ACC_RW) # 0x92
.equ ACCESS_TSS,  (ACC_PR|ACC_RING0|ACC_CODE|ACC_AC) # 0x89
.equ FLAGS_32, (FL_GR4kb|FL_32) # 0x0c
.equ FLAGS_16, (FL_GR1kb|FL_16) # 0x00
.equ FLAGS_TSS, FL_32

.macro DEFGDT base limit access flags
.word \limit & 0xffff
.word \base & 0xffff
.byte \base >> 16 & 0xff
.byte \access
.byte \flags << 4 | (\limit >> 16 & 0xf)
.byte \base >> 24
.endm


.align 4
.data
.space 4 # DEBUG: align in file for hexdump

GDT: 	.space 8	# null descriptor
GDT_flatCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a cf 00
GDT_flatDS:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 92 ca 00
GDT_tss:	DEFGDT 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00
GDT_vid_txt:	DEFGDT 0xb8000, 0x00ffff, ACCESS_DATA, FLAGS_16
GDT_vid_gfx:	DEFGDT 0xa00000, 0x00ffff, ACCESS_DATA, FLAGS_16

GDT_compatCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a 00 00
GDT_compatSS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00
GDT_compatDS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00

GDT_realmodeCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 9a 00 00
GDT_realmodeDS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeSS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeES: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeFS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeGS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00

GDT_biosCS:	DEFGDT 0xf0000, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 92 00 00

pm_gdtr:.word . - GDT -1
	.long GDT
rm_gdtr:.word 0
	.long 0

.equ SEL_flatCS,	8 * 1
.equ SEL_flatDS, 	8 * 2
.equ SEL_tss,		8 * 3
.equ SEL_vid_txt, 	8 * 4
.equ SEL_vid_gfx, 	8 * 5

.equ SEL_compatCS, 	8 * 6 # same as realmodeCS except 32 bit
.equ SEL_compatSS, 	8 * 7 # same as realmodeSS except 32 bit
.equ SEL_compatDS, 	8 * 8 # same as realmodeDS except 32 bit

.equ SEL_realmodeCS, 	8 * 9
.equ SEL_realmodeDS,	8 * 10
.equ SEL_realmodeSS,	8 * 11
.equ SEL_realmodeES, 	8 * 12
.equ SEL_realmodeFS, 	8 * 13
.equ SEL_realmodeGS, 	8 * 14
.equ SEL_biosCS,	8 * 15	# origin F000:0000

.macro GDT_STORE_SEG seg
	mov	[\seg + 2], ax
	shr	eax, 16
	mov	[\seg + 4], al
	# ignore ah as realmode addresses are 20 bits
.endm

.macro GDT_STORE_LIMIT lim
	mov	[\lim + 0], ax
	shr	eax, 16
	mov	ah, [\lim + 6] # preserve high nybble
	and	ax, 0xf00f
	or	al, ah
	mov	[\lim + 6], al
	# ignore ah as realmode addresses are 20 bits
.endm


.macro GDT_GET_BASE target, sel
	xor	\target, \target
	mov	al, [GDT + \sel + 7]
	shl	\target, 16
	mov	ax, [GDT + \sel + 2]
.endm

	# QEMU: GDT limit 37 base FCD80  IDT limit  3ff base 0
	# VBOX: GDT limit 30 base FC7F3  IDT limit ffff base 1
.macro PRINT_DT_16 msg, gdt, idt
# Realmode GDT:
	PRINT_16	"\msg"
	PRINT_16	" GDT: limit="
	mov		dx, [\gdt]
	call		printhex_16
	PRINT_16	"base="
	mov		edx, [\gdt+2]
	call		printhex8_16
# Realmode IDT:
	PRINT_16 	"  IDT: limit="
	mov		dx, [\idt]
	call		printhex_16
	PRINT_16	"base="
	mov		edx, [\idt+2]
	call		printhex8_16
	call		newline_16
.endm


.text
.code16

# Calulate segments and addresses
init_gdt_16:

	sgdt	[rm_gdtr]	# limit=30 base=000FC7F3
	sidt	[rm_idtr]	# limit=FFFF base=00000000

	push	eax
	push	ebx

	.if DEBUG > 2
		call	newline_16
		rmCOLOR 8
		PRINTLN_16 "  Original: "
		PRINT_DT_16 "    Realmode" rm_gdtr rm_idtr
		PRINT_DT_16 "    PMode   " pm_gdtr pm_idtr
	.endif

	# determine cs:ip since we do not assume to be loaded at any address
	xor	eax, eax # in case cs != 0
	mov	ax, cs
	shl	eax, 4

	mov	[realsegflat], eax
	mov	ebx, eax

	GDT_STORE_SEG GDT_realmodeCS
	mov	eax, ebx
	GDT_STORE_SEG GDT_compatCS

	xor	eax, eax
	call	0f	# determine possible relocation
0:	pop	ax
	sub	ax, offset 0b

	mov	[codeoffset], eax

	.if DEBUG > 2
		PH8_16 "  Code Base: " ebx
		PH8_16 "  Code Offset: " eax
	.endif

	# Set up DS

	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	mov	ebx, eax

	.if DEBUG > 2
		PH8_16 "  Data base: " eax
		call	newline_16
	.endif

	push	eax
	GDT_STORE_SEG GDT_realmodeDS
	pop	eax
	GDT_STORE_SEG GDT_compatDS


	# store proper linear (base 0) GDT/IDT address in pointer structure
	mov	eax, offset GDT
	add	eax, ebx
	mov	[pm_gdtr+2], eax
	mov	eax, offset IDT
	add	eax, ebx
	mov	[pm_idtr+2], eax


	# Set up TSS

	mov	eax, offset TSS
	add	eax, ebx

	GDT_STORE_SEG GDT_tss

	call	init_tss_16

	GDT_STORE_LIMIT GDT_tss


	# Set up SS

	xor	eax, eax
	mov	ax, ss
	shl	eax, 4

	GDT_STORE_SEG GDT_realmodeSS

	# make sure the top word of esp is zero
	xor	eax, eax
	mov	ax, sp
	mov	esp, eax


	# Set up ES

	xor	eax, eax
	mov	ax, es
	shl	eax, 4

	GDT_STORE_SEG GDT_realmodeES


	# Set up FS

	xor	eax, eax
	mov	ax, es
	shl	eax, 4

	GDT_STORE_SEG GDT_realmodeFS

	# Set up GS

	xor	eax, eax
	mov	ax, gs
	shl	eax, 4

	GDT_STORE_SEG GDT_realmodeGS


	# Load GDT

	.if DEBUG > 2
		PRINTLN_16 "  Loading Global Descriptor Table: "
		PRINT_DT_16 "    PMode   " pm_gdtr pm_idtr
	.endif

	DATA32 ADDR32 lgdt	pm_gdtr

	pop	ebx
	pop	eax
	ret



