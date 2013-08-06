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
.equ ACC_RING_SHIFT, 5
.equ ACC_NRM,	1 << 4	# code/data segment
.equ ACC_SYS,	0 << 4	# gate / tss

# this applies for ACC_SYS: for other gates, see idt.s
.equ ACC_T_RESERVED16,	ACC_SYS | 0b0000
.equ ACC_T_TSS16,	ACC_SYS | 0b0001
.equ ACC_T_LDT,		ACC_SYS | 0b0010
.equ ACC_T_TSS16b,	ACC_SYS | 0b0011
.equ ACC_T_GATE_CALL16,	ACC_SYS | 0b0100
.equ ACC_T_GATE_TASK32,	ACC_SYS | 0b0101 # TASK Gate. selector:offset = TSS:0.
.equ ACC_T_GATE_INT16,	ACC_SYS | 0b0110
.equ ACC_T_GATE_TRAP16,	ACC_SYS | 0b0111

.equ ACC_T_RESERVED32,	ACC_SYS | 0b1000
.equ ACC_T_TSS32,	ACC_SYS | 0b1001
.equ ACC_T_RESERVED32_2,ACC_SYS | 0b1010
.equ ACC_T_TSS32b,	ACC_SYS | 0b1011
.equ ACC_T_GATE_CALL32,	ACC_SYS | 0b1100
.equ ACC_T_GATE_INT32,	ACC_SYS | 0b1110 # 0xe
.equ ACC_T_GATE_TRAP32,	ACC_SYS | 0b1111


.equ ACC_CODE,	1 << 3
.equ ACC_DATA,	0 << 3
.equ ACC_DC,	1 << 2	# Direction (data) / Conforming (code) (can exec CPL>0)
.equ ACC_RW,	1 << 1
.equ ACC_AC,	1 << 0	# access bit (set by CPU)

.equ FL_GR1b,	0 << 3
.equ FL_GR4kb,	1 << 3
.equ FL_16,	0 << 2
.equ FL_32,	1 << 2

##
.equ ACCESS_CODE, (ACC_PR|ACC_RING0|ACC_NRM|ACC_CODE|ACC_RW) # 0x9a
.equ ACCESS_DATA, (ACC_PR|ACC_RING0|ACC_NRM|ACC_DATA|ACC_RW) # 0x92
#.equ ACCESS_TSS,  (ACC_PR|ACC_RING0|ACC_SYS|ACC_CODE|ACC_AC) # 0x89
.equ ACCESS_TSS,  (ACC_PR|ACC_RING3|ACC_SYS|ACC_CODE|ACC_AC) # 0x89
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

.macro DEFTSS base limit access flags
.word \limit & 0xffff
.word \base & 0xffff
.byte \base >> 16 & 0xff
.byte \access	# type: [P DPL:2 0] [1 0 B 1] (B: busy)
.byte \flags << 4 | (\limit >> 16 & 0xf) # flags: [G 0 0 available]
.byte \base >> 24
.endm


.data16	# real-mode access, keep within 64k
.space 4 # DEBUG: align in file for hexdump

GDT: 	.space 8	# null descriptor
GDT_flatCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a cf 00
GDT_flatDS:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 92 ca 00
GDT_tss:	DEFTSS 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00
GDT_vid_txt:	DEFGDT 0xb8000, 0x00ffff, ACCESS_DATA|ACC_RING3, FLAGS_16
GDT_vid_gfx:	DEFGDT 0xa0000, 0x00ffff, ACCESS_DATA|ACC_RING3, FLAGS_16

GDT_compatCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, (FL_32|FL_GR1b) #FLAGS_TSS #ffff 0000 00 9a 00 00
GDT_compatDS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00
GDT_compatSS:	DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 9a 00 00

GDT_realmodeCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 9a 00 00
GDT_realmodeDS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeSS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeES: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeFS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeGS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00

GDT_biosCS:	DEFGDT 0xf0000, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 92 00 00

GDT_taskCS:	DEFGDT 0, 0x000000, ACCESS_CODE|ACC_RING3, (FL_32|FL_GR1b)
GDT_taskDS:	DEFGDT 0, 0x000000, ACCESS_DATA|ACC_RING3, (FL_32|FL_GR1b)

GDT_ring0CS:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING0, (FL_32|FL_GR1b)
GDT_ring0DS:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING0, (FL_32|FL_GR4kb)
GDT_ring1CS:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING1, (FL_32|FL_GR1b)
GDT_ring1DS:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING1, (FL_32|FL_GR4kb)
GDT_ring2CS:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING2, (FL_32|FL_GR1b)
GDT_ring2DS:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING2, (FL_32|FL_GR4kb)
GDT_ring3CS:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING3, (FL_32|FL_GR1b)
GDT_ring3DS:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING3, (FL_32|FL_GR4kb)

.macro DEFCALLGATE sel, offs, dpl, pc
# DPL field of selector must be 0
.word \offs & 0xffff
.word \sel
.byte \pc & 0b11111	# param count, upper 3 bits must be 0
.byte ACC_PR | ((\dpl & 3) << 5) | ACC_T_GATE_CALL32
.word \offs >> 16
.endm

GDT_kernelCall:	DEFCALLGATE SEL_compatCS, (kernel_callgate  -.text), 3, 0
GDT_kernelMode:	DEFCALLGATE SEL_compatCS, (kernel_callgate_2-.text), 3, 0
GDT_kernelGate:	DEFCALLGATE SEL_compatCS, (kernel_callgate_3-.text), 3, 2 # stackargs: argcnt, method

GDT_tss_pf:	DEFTSS 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00
GDT_tss_df:	DEFTSS 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00
GDT_tss_np:	DEFTSS 0, 0xffffff, ACCESS_TSS, FLAGS_TSS #ffff 0000 00 89 40 00

# ACC_RING1 works when caller is RING1.
GDT_kapi:	DEFGDT 0, 4095, ACCESS_CODE|ACC_RING0|ACC_DC, (FL_32|FL_GR1b)
GDT_ldt:	DEFGDT 0, 0, ACC_PR|ACC_T_LDT, 0

# sysenter/exit: flat 4Gb segments.
GDT_sysCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, (FL_32|FL_GR4kb)
GDT_sysSS:	DEFGDT 0, 0xffffff, ACCESS_DATA, (FL_32|FL_GR4kb)
GDT_usrCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, (FL_32|FL_GR4kb)
GDT_usrSS:	DEFGDT 0, 0xffffff, ACCESS_DATA, (FL_32|FL_GR4kb)


GDT_ring0CSf:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING0, (FL_32|FL_GR4kb)
GDT_ring0DSf:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING0, (FL_32|FL_GR4kb)
GDT_ring1CSf:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING1, (FL_32|FL_GR4kb)
GDT_ring1DSf:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING1, (FL_32|FL_GR4kb)
GDT_ring2CSf:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING2, (FL_32|FL_GR4kb)
GDT_ring2DSf:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING2, (FL_32|FL_GR4kb)
GDT_ring3CSf:	DEFGDT 0, 0xffffff, ACCESS_CODE|ACC_RING3, (FL_32|FL_GR4kb)
GDT_ring3DSf:	DEFGDT 0, 0xffffff, ACCESS_DATA|ACC_RING3, (FL_32|FL_GR4kb)


#.align 2
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
.equ SEL_compatDS, 	8 * 7	# 38 same as realmodeDS except 32 bit
.equ SEL_compatSS, 	8 * 8	# 40 same as realmodeSS except 32 bit

.equ SEL_realmodeCS, 	8 * 9	# 48
.equ SEL_realmodeDS,	8 * 10	# 50
.equ SEL_realmodeSS,	8 * 11	# 58
.equ SEL_realmodeES, 	8 * 12	# 60
.equ SEL_realmodeFS, 	8 * 13	# 68
.equ SEL_realmodeGS, 	8 * 14	# 70
.equ SEL_biosCS,	8 * 15	# 78 # origin F000:0000
.equ SEL_taskCS,	8 * 16	# 80
.equ SEL_taskDS,	8 * 17	# 88

.equ SEL_ring0CS,	8 * 18	# 90
.equ SEL_ring0DS,	8 * 19	# 98
.equ SEL_ring1CS,	8 * 20	# a0
.equ SEL_ring1DS,	8 * 21	# a8
.equ SEL_ring2CS,	8 * 22	# b0
.equ SEL_ring2DS,	8 * 23	# b8
.equ SEL_ring3CS,	8 * 24	# c0
.equ SEL_ring3DS,	8 * 25	# c8

.equ SEL_kernelCall,	8 * 26	# d0
.equ SEL_kernelMode,	8 * 27	# d8
.equ SEL_kernelGate,	8 * 28	# e0
.equ SEL_tss_pf,	8 * 29	# e8
.equ SEL_tss_df,	8 * 30	# f0
.equ SEL_tss_np,	8 * 31	# f8
.equ SEL_kapi,		8 * 32	# 100
.equ SEL_ldt,		8 * 33	# 108

.equ SEL_sysCS,		8 * 34
.equ SEL_sysSS,		8 * 35
.equ SEL_usrCS,		8 * 36
.equ SEL_usrSS,		8 * 37

.equ SEL_ring0CSf,	8 * 38
.equ SEL_ring0DSf,	8 * 39
.equ SEL_ring1CSf,	8 * 40
.equ SEL_ring1DSf,	8 * 41
.equ SEL_ring2CSf,	8 * 42
.equ SEL_ring2DSf,	8 * 43
.equ SEL_ring3CSf,	8 * 44
.equ SEL_ring3DSf,	8 * 45

.equ SEL_MAX, SEL_ring3DSf + 0b11	# ring level 3



.macro GDT_STORE_LIMIT GDT
	mov	[\GDT + 0], ax
	shr	eax, 16
	mov	ah, [\GDT + 6] # preserve high nybble
	and	ax, 0xf00f
	or	al, ah
	mov	[\GDT + 6], al
	# ignore ah as realmode addresses are 20 bits
.endm

.macro GDT_GET_FLAGS target, sel, table=GDT
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
	and	_R, ~7
	mov	\target, byte ptr [\table + _R + 6]
	shr	\target, 4
	pop	_R
	.else
	mov	\target, byte ptr [\table + \sel + 6]
	shr	\target, 4
	.endif
.endm

.macro GDT_GET_ACCESS target, sel, table=GDT
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
	and	_R, ~7
	mov	\target, byte ptr [\table + _R + 5]
	pop	_R
	.else
	push	\sel
	and	\sel, ~7
	mov	\target, byte ptr [\table + \sel + 5]
	pop	\sel
	.endif
.endm

.macro GDT_GET_BASE target, sel, table=GDT
	IS_REG32 _, \sel	# [e]si is safe as target must be [e][abcd]x.
	.if _
		_O = esi
		_R=1
	.else
		IS_REG16 _, \sel
		.if _
			_O = si
			_R=1
		.else
			_O=(\sel&~7)
			_R=0
		.endif
	.endif

	.if _R
	push	_O
	mov	_O, \sel
	and	_O, ~7
	.endif

	_R32 = \target
	_R16 = -1
	R16 \target
	R8H \target
	R8L \target

	mov	_R8H, byte ptr [\table + _O + 7]
	mov	_R8L, byte ptr [\table + _O + 4]
	shl	_R32, 16
	mov	_R16, word ptr [\table + _O + 2]

	.if _R
	pop	_O
	.endif
.endm

# Safe to use in 16/32 bit mode (set 'sel' to 16/32 bit register/constant)
.macro GDT_SET_BASE sel, reg
	IS_REG32 _, \reg
	.if _
	R16 \reg
	R8L \reg
	R8H \reg
	mov	[GDT + \sel + 2], _R16
	ror	\reg, 16
	mov	[GDT + \sel + 4], _R8L
	mov	[GDT + \sel + 7], _R8H
	ror	\reg, 16
	.else
	mov	[GDT + \sel + 2], word ptr (\reg)&0xffff
	mov	[GDT + \sel + 4], byte ptr (\reg >> 16)&0xff
	mov	[GDT + \sel + 7], byte ptr (\reg >> 24)&0xff
	.endif
.endm

.macro DT_GET_SEL dest, sel, table=GDT
	IS_REG32 _, \dest
	.if _
	movzx	\dest, word ptr [\table + \sel + 2]
	.else
	mov	\dest, word ptr [\table + \sel + 2]
	.endif
.endm


.macro DT_GET_OFFSET dest, sel, table=GDT
	IS_REG32 _, \dest
	.if _
	R16 \dest
	movw	_R16, [\table + \sel + 6]	# hi
	shl	\dest, 16
	movw	_R16, [\table + \sel + 0]	# lo
	.else
	.error "DT_GET_OFFSET: dest must be reg32"
	.endif
.endm


.macro DT_SET_OFFSET sel, val, table=GDT
	IS_REG32 _, \val
	.if _
	R16 \val
	movw	[\table + \sel + 0], _R16	# lo
	ror	\val, 16
	movw	[\table + \sel + 6], _R16	# hi
	ror	\val, 16
	.else
	.error "DT_SET_OFFSET: val must be reg32"
	.endif
.endm



.macro GDT_SET_LIMIT sel, reg, table=GDT
	IS_REG32 _, \reg
	and	byte ptr [\table + \sel + 6], ((~(FL_GR4kb<<4)) & 0xf0)

	.if _
	R16 \reg
	R8H \reg
	R8L \reg
	push	\reg
	test	\reg, 0xfff00000
	jz	100f
	add	\reg, 4095
	shr	\reg, 12
	mov	[\table + \sel + 0], _R16
	shr	\reg, 16
	or	_R8L, FL_GR4kb
	or	[\table + \sel + 6], _R8L
	jmp	101f

100:	mov	[\table + \sel + 0], _R16
	shr	\reg, 16
	or	[\table + \sel + 6], _R8L
101:	pop	\reg

	.else

	.if \reg > 0x000fffff
	_TMP = (\reg + 0xfff) >> 12
	mov	[\table + \sel + 0], word ptr (_TMP & 0xffff)
	or	[\table + \sel + 6], byte ptr ((_TMP >> 16) & 0x0f)|(FL_GR4kb<<4)
	.else
	mov	[\table + \sel + 0], word ptr \reg & 0xffff
	or	[\table + \sel + 6], byte ptr (\reg >> 16) & 0x0f
	.endif

	.endif
.endm

.macro GDT_GET_LIMIT target, sel, table=GDT
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
		GDT_READ_LIMIT_b \target, \sel, \table
	.endif
.endm


# Reads the segment limit from the GDT, adjusted to byte granularity
.macro GDT_READ_LIMIT_b target, sel, table=GDT
	push	esi
	mov	esi, \sel
	and	esi, ~7
	_R32 = \target
	R16 \target
	R8H \target
	R8L \target
	xor	_R8H, _R8H
	mov	_R8L, [\table + esi + 6]
	and	_R8L, 0xf
	shl	_R32, 16
	mov	_R16, [\table + esi + 0]
	test	[\table + esi + 6], byte ptr FL_GR4kb << 4
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


.macro PRINT_GDT seg, debug=0
	push	edx

	printc	11, "\seg: "
	mov	edx, \seg
	call	printhex8
	GDT_GET_BASE edx, \seg
	printc	15, " base "
	call	printhex8
	GDT_GET_LIMIT edx, \seg
	printc	15, " limit "
	call	printhex8
	printc 15, " fl "
	GDT_GET_FLAGS dl, \seg
	call	printhex1
	printc 15, " xs "
	GDT_GET_ACCESS dl, \seg
	call	printhex2

	.ifnc 0,\debug
	printc 8, " ["
	# w w b b n n b
	mov	edx, \seg
	add	edx, offset GDT
	push	edx
	mov	edx, [edx]
	call	printhex4	# w
	call	printspace
	shr	edx, 16
	call	printhex4	# w
	call	printspace
	pop	edx
	mov	edx, [edx+4]
	call	printhex2	# b
	call	printspace
	shr	edx, 8
	call	printhex2	# b
	call	printspace
	shr	edx, 8
	call	printhex1	# n
	call	printspace
	shr	edx, 4
	call	printhex1	# n
	call	printspace
	shr	edx, 4
	call	printhex2	# b
	printc 8, "]"
	.endif
	call	newline
	pop	edx
.endm

.text16

# Calulate segments and addresses
init_gdt_16:

	sgdt	[rm_gdtr]	# limit=30 base=000FC7F3
	sidt	[rm_idtr]	# limit=FFFF base=00000000

	push_	eax ebx ecx

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

#if KERNEL_RELOCATION
	mov	ecx, offset .text	# relocation
	jecxz	1f
	mov	[reloc$], eax
	xor	eax,eax
1:
#endif
	mov	[realsegflat], eax
	mov	ebx, eax

	GDT_SET_BASE SEL_realmodeCS, eax
	GDT_SET_BASE SEL_compatCS, eax
	GDT_SET_BASE SEL_ring0CS, eax
	GDT_SET_BASE SEL_ring1CS, eax
	GDT_SET_BASE SEL_ring2CS, eax
	GDT_SET_BASE SEL_ring3CS, eax

	# find len
	mov	eax, kernel_code_end - kernel_code_start
#if KERNEL_RELOCATION
	add	eax, offset .text	# relocation
#endif
	mov	edx, eax
	#mov	eax, (offset kernel_code_end - offset kernel_code_start + 4095)>> 12
	#mov eax, 0xffff
	GDT_STORE_LIMIT GDT_compatCS
	mov	eax, edx
	GDT_STORE_LIMIT GDT_ring0CS
	mov	eax, edx
	GDT_STORE_LIMIT GDT_ring1CS
	mov	eax, edx
	GDT_STORE_LIMIT GDT_ring2CS
	mov	eax, edx
	GDT_STORE_LIMIT GDT_ring3CS

	xor	eax, eax
	call	0f	# determine possible relocation
0:	pop	ax
	sub	ax, offset 0b

	mov	[codeoffset], eax

	.if DEBUG > 1
		PH8_16 ebx, "  Code Base: "
		PH8_16 eax, "  Code Offset: "
	.endif

	# Set up DS

	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	mov	ebx, eax

	GDT_SET_BASE SEL_realmodeDS, eax
#if KERNEL_RELOCATION
	jecxz	1f
	xor	eax,eax
	xor	ebx,ebx
1:
#.endif
	mov	[database], eax

	.if DEBUG > 2
		PH8_16 eax, "  Data base: "
		call	newline_16
	.endif

	GDT_SET_BASE SEL_compatDS, eax
	GDT_SET_BASE SEL_ring0DS, eax
	GDT_SET_BASE SEL_ring1DS, eax
	GDT_SET_BASE SEL_ring2DS, eax
	GDT_SET_BASE SEL_ring3DS, eax

	# store proper linear (base 0) GDT/IDT address in pointer structure
	mov	eax, offset GDT	# relocation
	add	eax, ebx
	mov	[pm_gdtr+2], eax
	mov	eax, offset IDT	# relocation
	add	eax, ebx
	mov	[pm_idtr+2], eax


	# Set up SS

	xor	eax, eax
	mov	ax, ss
	shl	eax, 4

	GDT_SET_BASE SEL_realmodeSS, eax

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
	add	edx, 8*KERNEL_MIN_STACK_SIZE + 4095
	and	edx, ~4095
	.if DEBUG
		print_16 "stack top physical: "
		call printhex8_16
	.endif
	sub	edx, [database]
print_16 "tss0 stack top: "; call printhex8_16
	mov	[kernel_tss0_stack_top], edx
	push edx;sub edx, [ramdisk_load_end]; print_16 "size: "; call printhex8_16;pop edx
	add	edx, KERNEL_MIN_STACK_SIZE
print_16 "kernel stack top: "; call printhex8_16
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

	GDT_SET_BASE SEL_realmodeES, eax


	# Set up FS

	xor	eax, eax
	mov	ax, es
	shl	eax, 4

	GDT_SET_BASE SEL_realmodeFS, eax

	# Set up GS

	xor	eax, eax
	mov	ax, gs
	shl	eax, 4

	GDT_SET_BASE SEL_realmodeGS, eax


	# Set up TSS (must be done after kernel_stack_top)

	call	init_tss_16

	mov	eax, offset TSS	# relocation
	add	eax, ebx
	GDT_SET_BASE SEL_tss, eax
	mov	eax, 108 #value doesnt really matter here it seems
	GDT_STORE_LIMIT GDT_tss

	mov	eax, offset TSS_PF	# relocation
	add	eax, ebx
	GDT_SET_BASE SEL_tss_pf, eax
	mov	eax, 108
	GDT_STORE_LIMIT GDT_tss_pf

	mov	eax, offset TSS_DF	# relocation
	add	eax, ebx
	GDT_SET_BASE SEL_tss_df, eax
	mov	eax, 108
	GDT_STORE_LIMIT GDT_tss_df

	mov	eax, offset TSS_NP	# relocation
	add	eax, ebx
	GDT_SET_BASE SEL_tss_np, eax
	mov	eax, 108
	GDT_STORE_LIMIT GDT_tss_np


#if KERNEL_RELOCATION
	or	ecx, ecx
	jz	1f
	# handle relocation
	mov	edx, offset .text
	PH8_16 edx,"relocation "

	DT_GET_OFFSET eax, SEL_kernelCall	# kernel_callgate
	add	eax, edx
	DT_SET_OFFSET SEL_kernelCall, eax

	DT_GET_OFFSET eax, SEL_kernelMode	# kernel_callgate_2
	add	eax, edx
	DT_SET_OFFSET SEL_kernelMode, eax

	DT_GET_OFFSET eax, SEL_kernelGate	# kernel_callgate_3
	add	eax, edx
	DT_SET_OFFSET SEL_kernelGate, eax
1:
#endif

	# Load GDT

	.if DEBUG > 2
		PRINTLN_16 "  Loading Global Descriptor Table: "
		PRINT_DT_16 "    PMode   " pm_gdtr pm_idtr
	.endif

#if KERNEL_RELOCATION
	jecxz	1f
	push	ds		# use 0-based offset as pm_gdtr is relocatable.
	xor	ax,ax
	mov	ds, ax
	DATA32 ADDR32 lgdt	pm_gdtr	# relocation
	pop	ds
	jmp	2f
1:
#else
	DATA32 ADDR32 lgdt	pm_gdtr	# relocation
2:
#endif

	pop_	ecx ebx eax
	ret

.text32
# This method at current can be called from anywhere, using:
# 	call SEL_kernelCall:whatever
# and it will return with cs in kernel mode. The stack will be modified
# so that a ret will return to this method which then exits back to CPL3
# (or whatever CPL it was called from).
#
# NOTE: this call will change ss:esp. If using stackargs, load ebp first.
#  (the new ss will be aligned with the old one).
# NOTE: the first 'ret' instruction the caller makes
# MUST NOT pop extra arguments off the stack (i.e., must be 'ret 0').
kernel_callgate:
# This method is implemented as a minor context-switch.
# Once here, the ss:esp is according to the TSS, and cs is
# according to the call gate descriptor.
.if 0
	push	ebp
	lea	ebp, [esp + 4]
	push	ecx
	push	edx

	printc 11, "KERNEL CALLGATE: cs="
	mov	edx, cs
	call	printhex4

	printc 11, " ds="
	mov	edx, ds
	call	printhex4
	printc 11, " es="
	mov	edx, es
	call	printhex4


	printc 11, " ss:esp="
	mov	edx, ss
	call	printhex8
	printchar ':'
	mov	edx, ebp
	call	printhex8
	call newline

	printc 11, "stack:";
	call	newline
	xor	ecx, ecx
0:	lea	edx, [ecx * 4]
	call	printhex2
	call	printspace
	lea	edx, [ebp + ecx * 4]
	call	printhex8
	print ": "
	mov	edx, [ebp + ecx * 4]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	inc	ecx
	cmp	ecx, 4
	jb	0b

	printc 11, "usermode stack:";
	mov	edx, [ebp + 12]
	call	printhex4
	printchar ':'
	mov	edx, [ebp + 8]
	call	printhex8
	call	newline

	push	ebp
	mov	ebp, [ebp + 8]
	xor	ecx, ecx
0:	mov	edx, ecx
	call	printhex2
	call	printspace
	lea	edx, [ebp + ecx * 4]
	call	printhex8
	print ": "
	mov	edx, [ebp + ecx * 4]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline
	inc	ecx
	cmp	ecx, 4
	jb	0b
	pop	ebp

	printc 11, " ret: "
	mov	edx, [ebp + 12]
	call	printhex4
	printchar ':'
	mov	edx, [ebp + 8]
	call	printhex8
	call	printspace
	call	debug_printsymbol

	call	newline
	printc 11, " usermode ret: "
	mov	edx, [ebp + 8]
	mov	edx, [edx + 4]
	call	printhex8
	printchar ':'
	mov	edx, [ebp + 12]
	mov	edx, [edx]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	call	newline

	pop	edx
	pop	ecx
	pop	ebp
.endif

	push	ds
	push	es

	push	edx
	mov	edx, SEL_compatDS
	mov	ds, edx
	mov	es, edx
	pop	edx
	call	[esp + 8]

	###################
	push	ebp
	lea	ebp, [esp + 12]
	pushf
	# the called method had expected to return the original caller, but
	# it ends up here. So now we return to the original caller:
	# we replace [ebp] (the return address of this method)
	# with the original return address, adjust the original caller's
	# stack, and then simply return:
	push	edx
	mov	edx, [ebp + 8]	# caller stack
	mov	edx, [edx]	# caller return
	mov	[ebp], edx	# change our return address
	add	[ebp + 8], dword ptr 4	# simulate the ret
	pop	edx
	popf
	pop	ebp
	####################

	pop	ds
	pop	es
.if 0
	pushf
lea ebp, [esp + 4]; call newline
DEBUG_DWORD [ebp+4],"cs";
DEBUG_DWORD [ebp],"eip"; push edx;mov edx, [ebp];call debug_printsymbol;pop edx;call newline
DEBUG_DWORD [ebp+8],"esp"; call newline
DEBUG_DWORD [ebp+12],"ss"; call newline
	popf
.endif
	retf

# This is the SEL_kernelMode: it switches to CPL0, but doesn't do the return
# trickery. It is used to switch to kernel mode for a task switch.
kernel_callgate_2:
	# we're now on the TSS_SS0:TSS_ESP0 stack.
	# [esp+0]  = caller eip
	# [esp+4]  = caller cs
	# [esp+8]  = caller esp
	# [esp+12] = caller ss

	# we should continue at the caller's address, with the current cs.
	ret
	# now, on return, the stack is:
	# [esp] = caller cs, esp, ss


kernel_callgate_3: # unreferenced
	printlnc 0xf0, "kernel callgate 3"
	DEBUG_WORD cs
	DEBUG_WORD ds
	DEBUG_WORD ss
	DEBUG_DWORD esp
	push	ebp
	lea	ebp, [esp + 4]
	call newline
	DEBUG_DWORD [ebp], "caller eip"
	DEBUG_DWORD [ebp+4], "cs"
	DEBUG_DWORD [ebp+8], "esp"
	DEBUG_DWORD [ebp+12], "ss"
	call	newline
	push_	edx eax
	xor	edx, edx
	str	dx
	DEBUG_WORD dx, "TR"
	GDT_GET_BASE eax, edx
	GDT_GET_BASE edx, ds
	sub	eax, edx
	DEBUG_DWORD [eax + tss_LINK]
	DEBUG_DWORD [eax + tss_ESP]
	DEBUG_DWORD [eax + tss_EIP]
	DEBUG_DWORD [eax + tss_SS0]
	DEBUG_DWORD [eax + tss_ESP0]


	pop_	eax edx
	pop	ebp

0: hlt; jmp 0b
	ret
