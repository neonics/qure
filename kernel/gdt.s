# GDT Format:
# .word limit[15:0]	(limit: 20 bits total)
# .word base[15:0]	(base:  32 bits total)
# .byte base[23:16]
# .byte access		(access: 1 byte: [P DPL[2] S Ex DC RW Ac])
#			P: Present Bit - 1 for valid sectors (enable)
#			Privl: DPL - ring level (0 hi, 3 lo)
#			S: 0=system 1 = code or data
#			Type: 4 bits:
#			  For S = 1 (code or data) type means:
#				Ex: Executable bit (1=code, 0=data)
#				DC: Direction (data)/Conforming(code)
#				  data: Direction:
#					0 grow up,
#				  	1 grow down (offset with seg > limit)
#				  code: Conforming: use of Privl/Ring
#					1 can exec equal/lower ring
#					0 can exec only equal ring
#				RW: readable/writeable
#				  code: readable bit (write always prohibited)
#				  data: writable (read access always)
#				Ac: access bit, set by CPU on access and for TSS
#			  For S = 0 (system), type means:
#				0000 reserved
#				0001 16 bit TSS (available)
#				0010 LDT
#				0011 16 bit TSS (busy)
#				0100 16 bit Call Gate
#				0101 Task Gate
#				0110 16 bit Interrupt Gate
#				0111 16 bit Trap Gate
#				1000 reserved
#				1001 32 bit TSS (available)
#				1010 reserved
#				1011 32 bit TSS (busy)
#				1100 32 bit Call Gate
#				1101 reserved
#				1110 32 bit Interrupt Gate
#				1111 32 bit Trap Gate
#
#			   Reordered: [S G TT]
#				S	Size: 0 = 16 bit, 1 = 32 bit
#				G	Gate: 1 = gate, 0 = LDT/TSS
#				TT	G=1:	00 = Call Gate
#						01 = Task Gate (32 bit only)
#						10 = Interrupt Gate
#						11 = Trap Gate
#					G=0:	10 = LDT (32 bit only)
#						x1 = TSS (x: 1=Busy,0=Avail)
#			
# .nybble(hi) flags[4]	(flags: 4 bits: G D/B L AVL)
#			G: granularity: 0=limit * 1 byte, 1 = limit * 4kb
#			  0: limit in 1 byte blocks "byte granularity" (max 1Mb)
#			  1: limit in 4kb blocks "page granularity" (max 4Gb)
#			D/B: default operation size/stack ptr size/upper bound
#				0 = 16 bit, 1 = 32 bit
#				- exec code segment: D (default operation size)
#				- stack segment: B (big) (esp/sp)
#				- expand down data segment: B: upper bound,
#				  1 = upper bound = 4Gb, 0 = upper bound = 64kb
#			L: Long mode - in IA-32e mode: (when set, D must be 0)
#			    1 = 64 bit code segment; 0 = 32 bit compat mode
#			AVL: available for use by system software.
#			    
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

# this applies for ACC_SYS: for other gates, see idt.s
.equ ACC_GATE_CALL, ACC_SYS | 0b1100

.equ ACC_CODE,	1 << 3
.equ ACC_DATA,	0 << 3
.equ ACC_DC,	1 << 2
.equ ACC_RW,	1 << 1
.equ ACC_AC,	1 << 0

.equ FL_GR1b,	0 << 3
.equ FL_GR4kb,	1 << 3
.equ FL_16,	0 << 2
.equ FL_32,	1 << 2

##
.equ ACCESS_CODE, (ACC_PR|ACC_RING0|ACC_NRM|ACC_CODE|ACC_RW) # 0x9a
.equ ACCESS_DATA, (ACC_PR|ACC_RING0|ACC_NRM|ACC_DATA|ACC_RW) # 0x92
.equ ACCESS_TSS,  (ACC_PR|ACC_RING0|ACC_CODE|ACC_AC) # 0x89
.equ FLAGS_32, (FL_GR4kb|FL_32) # 0x0c
.equ FLAGS_16, (FL_GR1b|FL_16) # 0x00
.equ FLAGS_TSS, FL_32

.macro DEFGDT base limit access flags
.word \limit & 0xffff
.word \base & 0xffff
.byte \base >> 16 & 0xff
.byte \access
.byte \flags << 4 | (\limit >> 16 & 0xf)
.byte \base >> 24
.endm

.data16	# real-mode access, keep within 64k
.space 4 # DEBUG: align in file for hexdump

GDT: 	.space 8	# null descriptor
GDT_flatCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a cf 00
GDT_flatDS:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 92 ca 00
GDT_tss:	DEFGDT 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00
GDT_vid_txt:	DEFGDT 0xb8000, 0x00ffff, ACCESS_DATA, FLAGS_16
GDT_vid_gfx:	DEFGDT 0xa0000, 0x00ffff, ACCESS_DATA, FLAGS_16

GDT_compatCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, (FL_32|FL_GR1b) #FLAGS_TSS #ffff 0000 00 9a 00 00
GDT_compatSS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00
GDT_compatDS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00

GDT_realmodeCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 9a 00 00
GDT_realmodeDS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeSS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeES: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeFS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeGS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00

GDT_biosCS:	DEFGDT 0xf0000, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 92 00 00

GDT_taskCS:	DEFGDT 0, 0x000000, ACCESS_CODE|ACC_RING3, FLAGS_32
GDT_taskDS:	DEFGDT 0, 0x000000, ACCESS_DATA|ACC_RING3, FLAGS_32


.macro DEFCALLGATE sel, offs, dpl, pc
# DPL field of selector must be 0
.word \offs & 0xffff
.word \sel
.byte \pc & 0b11111	# param count, upper 3 bits must be 0
.byte ACC_PR | ((\dpl & 3) << 5) | ACC_GATE_CALL
.word \offs >> 16
.endm

# the first 0 is the offset, but can't do math due to GAS limitations
GDT_kernelCall:	DEFCALLGATE SEL_compatCS, 0, 3, 0

pm_gdtr:.word . - GDT -1
	.long GDT
rm_gdtr:.word 0
	.long 0

# Segment selector format:
# [15:3] descriptor index (0..8191). Offset in descriptor table: & ~7
# [2]: Local/Global: 1 = LDT, 0 = GDT
# [1:0]: RPL - requested privilege level (0..3)

.equ SEL_flatCS,	8 * 1	# 08
.equ SEL_flatDS, 	8 * 2	# 10
.equ SEL_tss,		8 * 3	# 18
.equ SEL_vid_txt, 	8 * 4	# 20
.equ SEL_vid_gfx, 	8 * 5	# 28

.equ SEL_compatCS, 	8 * 6	# 30 # same as realmodeCS except 32 bit
.equ SEL_compatSS, 	8 * 7	# 38 same as realmodeSS except 32 bit
.equ SEL_compatDS, 	8 * 8	# 40 same as realmodeDS except 32 bit

.equ SEL_realmodeCS, 	8 * 9	# 48
.equ SEL_realmodeDS,	8 * 10	# 50
.equ SEL_realmodeSS,	8 * 11	# 58
.equ SEL_realmodeES, 	8 * 12	# 60
.equ SEL_realmodeFS, 	8 * 13	# 68
.equ SEL_realmodeGS, 	8 * 14	# 70
.equ SEL_biosCS,	8 * 15	# 78 # origin F000:0000
.equ SEL_taskCS,	8 * 16	# 80
.equ SEL_taskDS,	8 * 17	# 88
.equ SEL_kernelCall,	8 * 18	# 90
.equ SEL_MAX, SEL_kernelCall + 0b11	# ring level 3


.macro GDT_STORE_SEG seg
	mov	[\seg + 2], ax
	shr	eax, 16
	mov	[\seg + 4], al
	# ignore ah as realmode addresses are 20 bits
.endm


.macro GDT_STORE_LIMIT GDT
	mov	[\GDT + 0], ax
	shr	eax, 16
	mov	ah, [\GDT + 6] # preserve high nybble
	and	ax, 0xf00f
	or	al, ah
	mov	[\GDT + 6], al
	# ignore ah as realmode addresses are 20 bits
.endm

.macro GDT_GET_FLAGS target, sel
	IS_REG8 _, \target
	.if !_
	.error "\target must be 8 bit register"
	.endif

	IS_SEGREG _, \sel
	.if _
	GET_REG32 _R32, \target
xor	_R32, _R32
xor \target,\target
	.if eax==_R32
	_R = ebx
	.else
	_R = eax
	.endif
	push	_R
	mov	_R, \sel
	mov	\target, byte ptr [GDT + _R + 6]
	shr	\target, 4
	pop	_R
	.else
	mov	\target, byte ptr [GDT + \sel + 6]
	shr	\target, 4
	.endif
.endm

.macro GDT_GET_BASE target, sel
	push	esi
	mov	esi, \sel
	_R32 = \target
	R16 \target
	R8H \target
	R8L \target

	mov	_R8H, [GDT + esi + 7]
	mov	_R8L, [GDT + esi + 4]
	shl	_R32, 16
	mov	_R16, [GDT + esi + 2]
	pop	esi
.endm

.macro GDT_SET_BASE sel, reg
	R16 \reg
	R8L \reg
	R8H \reg
	mov	[GDT + \sel + 2], _R16
	ror	\reg, 16
	mov	[GDT + \sel + 4], _R8L
	mov	[GDT + \sel + 7], _R8H
	ror	\reg, 16
.endm

.macro GDT_SET_LIMIT sel, reg
	IS_REG32 _, \reg
	and	byte ptr [GDT + \sel + 6], ((~(FL_GR4kb<<4)) & 0xf0)

	.if _
	R16 \reg
	R8H \reg
	R8L \reg
	push	\reg
	test	\reg, 0xfff00000
	jz	100f
	add	\reg, 4095
	shr	\reg, 12
	mov	[GDT + \sel + 0], _R16
	shr	\reg, 16
	or	_R8L, FL_GR4kb
	or	[GDT + \sel + 6], _R8L
	jmp	101f

100:	mov	[GDT + \sel + 0], _R16
	shr	\reg, 16
	or	[GDT + \sel + 6], _R8L
101:	pop	\reg

	.else

	.if \reg > 0x000fffff
	_TMP = (\reg + 0xfff) >> 12
	mov	[GDT + \sel + 0], word ptr (_TMP & 0xffff)
	or	[GDT + \sel + 6], byte ptr ((_TMP >> 16) & 0x0f)|(FL_GR4kb<<4)
	.else
	mov	[GDT + \sel + 0], word ptr \reg & 0xffff
	or	[GDT + \sel + 6], byte ptr (\reg >> 16) & 0x0f
	.endif

	.endif
.endm

.macro GDT_GET_LIMIT target, sel
	.if 0
		# The lsl instruction does not work for segment registers
		IS_SEGREG _, \sel
		.if _
			REG_GET_FREE _TMP_REG, \target, \sel

			push	_TMP_REG
			mov	_TMP_REG, \sel
			lsl	\target, _TMP_REG
			pop	_TMP_REG
		.else
			lsl	\target, \sel
		.endif
	.else
		GDT_READ_LIMIT_b \target, \sel
	.endif
.endm


# Reads the segment limit from the GDT, adjusted to byte granularity
.macro GDT_READ_LIMIT_b target, sel
	push	esi
	mov	esi, \sel
	and	esi, ~7
	_R32 = \target
	R16 \target
	R8H \target
	R8L \target
	xor	_R8H, _R8H
	mov	_R8L, [GDT + esi + 6]
	and	_R8L, 0xf
	shl	_R32, 16
	mov	_R16, [GDT + esi + 0]
	test	[GDT + esi + 6], byte ptr FL_GR4kb << 4
	pop	esi
	jz	99f
	shl	\target, 12
99:
.endm

# Reads the segment limit as stored in the GDT in its original granularity.
.macro GDT_READ_LIMIT target, sel
	push	esi
	mov	esi, \sel
	_R32 = \target
	R16 \target
	R8H \target
	R8L \target
	xor	_R8H, _R8H
	mov	_R8L, [GDT + esi + 6]
	and	_R8L, 0xf
	shl	_R32, 16
	mov	_R16, [GDT + esi + 0]
	pop	esi
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

.text16

# Calulate segments and addresses
init_gdt_16:

	sgdt	[rm_gdtr]	# limit=30 base=000FC7F3
	sidt	[rm_idtr]	# limit=FFFF base=00000000

	push	eax
	push	ebx

	.if DEBUG > 2
		call	newline_16
		COLOR_16 8
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

	# find len
	mov	eax, kernel_code_end - kernel_code_start
	#mov	eax, (offset kernel_code_end - offset kernel_code_start + 4095)>> 12
	#mov eax, 0xffff
	GDT_STORE_LIMIT GDT_compatCS

	xor	eax, eax
	call	0f	# determine possible relocation
0:	pop	ax
	sub	ax, offset 0b

	mov	[codeoffset], eax

	.if DEBUG > 1
		PH8_16 "  Code Base: " ebx
		PH8_16 "  Code Offset: " eax
	.endif

	# Set up DS

	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	mov	ebx, eax
	mov	[database], eax

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

	# calculate stack top
	mov	edx, [ramdisk_load_end]	# offset kernel_end

	.if DEBUG
		print_16 "  Ramdisk load end: "
		call	printhex8_16
	.endif

	# align the stack top with 4kb physical page:
	add	edx, [database]
	add	edx, KERNEL_MIN_STACK_SIZE + 4095
	and	edx, ~4095
	.if DEBUG
		print_16 "stack top physical: "
		call printhex8_16
	.endif
	sub	edx, [database]
	mov	[kernel_stack_top], edx

	.if DEBUG
		print_16 "Stack top: "
		call	printhex8_16
		sub	edx, [ramdisk_load_end]
		print_16 "size: "
		call	printhex8_16
		call	newline_16
	.endif

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

	# set the call gate
	mov	eax, offset kernel_callgate
	mov	[GDT_kernelCall + 0], ax
	shr	eax, 16
	mov	[GDT_kernelCall + 6], ax

	# Load GDT

	.if DEBUG > 2
		PRINTLN_16 "  Loading Global Descriptor Table: "
		PRINT_DT_16 "    PMode   " pm_gdtr pm_idtr
	.endif

	DATA32 ADDR32 lgdt	pm_gdtr

	pop	ebx
	pop	eax
	ret

.text32
# This method at current can be called from anywhere, using:
# 	call SEL_kernelCall:whatever
# and it will return with cs in kernel mode. The stack will be modified
# so that a ret will return to this method which then exits back to CPL3
# (or whatever CPL it was called from).
kernel_callgate:
# This method is implemented as a minor context-switch.
# Once here, the ss:esp is according to the TSS, and cs is
# according to the call gate descriptor.
.if 0
	printc 11, "KERNEL CALLGATE: cs="
	push	edx
	mov	edx, cs
	call	printhex4
	printc 11, " ss:esp="
	mov	edx, ss
	call	printhex8
	printchar ':'
	mov	edx, esp
	call	printhex8
	printc 11, " ret: "
	mov	edx, [esp + 8]
	call	printhex4
	printchar ':'
	mov	edx, [esp + 12]
	call	printhex8

	printc 11, " usermode ret: "
	mov	edx, [edx]
	call	printhex8
	call	newline
	pop	edx
.endif

## a CPL3 user function:
# user_app:
# 	call lib	
# user_ret:
#
# lib:
## user esp = [user_ret][...
#	call SEL_kernelCall:0
# 1:
## kernel esp = [1][user cs][user esp][user ss]
#
.data SECTION_DATA_BSS
_callgate_stack: .long 0
_callgate_cont: .long 0
.text32
.if 0
	push	ebp
## esp = [ebp][1][user cs][user esp][user ss]
	mov	ebp, [esp + 4 + 8]	# orig stack ptr
## ebp = [user ret]
	push	[esp+4]
## esp = [1][ebp][1][user cs][user esp][user ss]
	xchg	ebp, esp		# remember new stack, load orig stack
## ebp = [1][ebp][1][user cs][user esp][user ss]
## esp = [user_ret][...
	pop	[ebp + 8]	# remove caller ret and replace our retf eip
## esp = [...
## ebp = [1][ebp][user_ret][user cs][user esp][user ss]
	call	[ebp]
	lea	esp, [ebp + 4]
	pop	ebp
.else
	push	ebp
	mov	ebp, [esp + 4 + 8]	# orig stack ptr
	mov	[_callgate_stack], ebp
	mov	ebp, [ebp]	# user ret
	xchg	ebp, [esp + 4] # replace retf eip
	mov	[_callgate_cont], ebp
	pop	ebp
	xchg	esp, [_callgate_stack]
	add	esp, 4

	call	[_callgate_cont]

	mov	esp, [_callgate_stack]
.endif
	retf
