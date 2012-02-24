/**
 * The Famous PMODE.ASM converted to GNU AS
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
 */
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
GDT_realmodeCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 9a 00 00
GDT_realmodeDS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeSS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeES: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeFS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
GDT_realmodeGS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00

GDT_compatCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a 00 00
pm_gdtr:.word . - GDT -1
	.long GDT
rm_gdtr:.word 0
	.long 0

	.equ SEL_flatCS,	8 * 1
	.equ SEL_flatDS, 	8 * 2
	.equ SEL_tss,		8 * 3
	.equ SEL_vid_txt, 	8 * 4
	.equ SEL_vid_gfx, 	8 * 5
	.equ SEL_realmodeCS, 	8 * 6
	.equ SEL_realmodeDS,	8 * 7
	.equ SEL_realmodeSS,	8 * 8
	.equ SEL_realmodeES, 	8 * 9
	.equ SEL_realmodeFS, 	8 * 10
	.equ SEL_realmodeGS, 	8 * 11
	.equ SEL_compatCS, 	8 * 12 # same as realmodeCS except 32 bit

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


#########################################################
# IDT: Interrupt Descriptor Table.
#
# The structure is the same as the GDT, except:
# - limit is the offset into a selector
# - base is 16 bits segment selector
# - access lower 4 bits determine gate type
# - in the GDT, the last word starts with the low nybble of the 3rd byte
#   of limit. In the IDT, the last word is the high word of the limit.
#
# ACC_PR: 0 means unused interrupt, or Paging.
# ACC_NRM(1), ACC_SYS(0): SYS for interrupt gates.
#
# The low nybble of the access byte desribes the gate type.
# For a TASK Gate, the entire context is switched using TSS.
# For an INT Gate, cli/sti is automatic; it isn't for a TRAP gate.
#
.equ IDT_ACC_GATE_TASK32, 0b0101 # TASK Gate. selector:offset = TSS:0.
.equ IDT_ACC_GATE_INT16,  0b0110
.equ IDT_ACC_GATE_TRAP16, 0b0111
.equ IDT_ACC_GATE_INT32,  0b1110
.equ IDT_ACC_GATE_TRAP32, 0b1111


.macro DEFIDT offset, selector, access
# DPL field of selector must be 0
.word (\offset) & 0xffff
.word \selector
.byte 0
.byte \access
.word (\offset) >> 16
.endm


IDT:
.rept 256
#.space 8
DEFIDT 0, SEL_flatCS, ACC_PR+ACC_RING0+ACC_SYS+IDT_ACC_GATE_INT32
.endr
pm_idtr:.word . - IDT - 1
	.long IDT

# Real Mode IDT (IVT)
rm_idtr:.word 256 * 4
	.long 0

#######################

realsegflat:.long 0
codeoffset: .long 0
bkp_reg_cs: .word 0
bkp_reg_ds: .word 0
bkp_reg_es: .word 0
bkp_reg_ss: .word 0
bkp_reg_sp: .word 0
bkp_reg_fs: .word 0
bkp_reg_gs: .word 0


##########################
.align 4
# in the syntax below, the second word of '.word 0,0' is always reserved,
# as the entry is a 32 bit aligned 16 bit value.
TSS: # in the syntax below, the second word of '.word 0,0' is always reserved
tss_LINK:	.word 0, 0
tss_ESP0:	.long 0
tss_SS0:	.word 0, 0
tss_SS1:	.word 0, 0
tss_SS2:	.word 0, 0
tss_CR3:	.long 0
tss_EIP:	.long 0
tss_EFLAGS:	.long 0
tss_EAX:	.long 0
tss_ECX:	.long 0
tss_EDX:	.long 0
tss_EBX:	.long 0
tss_ESP:	.long 0
tss_EBP:	.long 0
tss_ESI:	.long 0
tss_EDI:	.long 0
tss_ES:		.word 0, 0
tss_CS:		.word 0, 0
tss_SS:		.word 0, 0
tss_DS:		.word 0, 0
tss_FS:		.word 0, 0
tss_GS:		.word 0, 0
tss_LDTR:	.word 0, 0
		.word 0 # low word at offset 64 is reserved, hi=IOBP offset
tss_IOPB:	.word 0 # io bitmask base pointer, 104 + ...
##########################

# little print macro
.macro PH8 m, r
	push	edx
	.if \r != edx
	mov	edx, \r
	.endif
	push	ax
	mov	ah, 0xf0
	PRINT "\m" 
	call	printhex8
	add	di, 2
	pop	ax
	pop	edx
.endm

.macro DBGSO16 msg, seg, offs
	mov	ah, 0xf0
	PRINT	"\msg"
	mov	dx, \seg
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	dx, \offs
	call	printhex
.endm

.macro DBGSTACK16 msg, offs
	PRINT	"\msg"
	mov	bp, sp
	mov	dx, [bp + offs]
	call	printhex
.endm



.text
.code16
# in: ax: Flags
# bit0:	0 = flat mode (flatCS, flatDS for all registers)
#	1 = compatibility mode (compatCS, realmodeDS/ES/FS/GS/SS)
# SEL_realmodeCS is 16 bit, based on the value of cs when this method is called.
# SEL_compatCS is the 32 bit version of realmodeCS
# SEL_flatCS is 32 bit based zero.
#
# realmodeCS is used in the real_mode method to return to real mode.
#
# THis method assumes that CS is the base pointer for the code,
# and will use the area before it as the TSS stack.

# for now this constant will serve as ax:
PMODE_COMPATCS = 1 #this uses compatCS, use 0 for flatCS
protected_mode:
	mov	[bkp_reg_cs], cs
	mov	[bkp_reg_ds], ds
	mov	[bkp_reg_es], es
	mov	[bkp_reg_ss], ss
	mov	[bkp_reg_sp], sp
	mov	[bkp_reg_fs], fs
	mov	[bkp_reg_gs], gs

DEBUG = 1

	.if DEBUG
		DBGSO16 "RealMode SS:IP: ", ss, sp
		DBGSTACK16 "Return IP: ", 0

		call	newline

		PRINTLN "Enabling A20"
	.endif


	# enable A20
	in	al, 0x92	# system control port a, a20 line
	test	al, 2
	jnz	0f
	or	al, 2		# 0(w):1=fast reset/realmode
	out	0x92, al
0:

	# Calulate segments and addresses

	# determine cs:ip since we do not assume to be loaded at any address
	xor	eax, eax # in case cs != 0
	mov	ax, cs
	shl	eax, 4

	mov	[realsegflat], eax
	mov	ebx, eax

	.if DEBUG
		PH8	"Code Base: " eax
	.endif






	GDT_STORE_SEG GDT_realmodeCS
	mov	eax, ebx
	GDT_STORE_SEG GDT_compatCS

	xor	eax, eax
	call	0f	# determine possible relocation
0:	pop	ax
	sub	ax, offset 0b

	mov	[codeoffset], eax

	.if DEBUG
		PH8 "CodeOffset: " eax
	.endif


	# Set up DS

	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	mov	ebx, eax

	PH8 "Data base: " eax

	GDT_STORE_SEG GDT_realmodeDS

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

	mov	[tss_SS0], word ptr SEL_flatDS
	mov	eax, [realsegflat] # 0....stack|0x10000|code
	mov	[tss_ESP0], eax

	mov	eax, 104
	#add	eax, IOBP size
	mov	[tss_IOBP], ax

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

	call	newline
	mov	ah, 0xf0
	PRINTLN "Loading Global Descriptor Table"

	DATA32 ADDR32 lgdt	pm_gdtr

	cli
	# set NMI off
	in	al, 0x70
	or	al, 0x80 # XXX nmi on?
	out	0x70, al
	in	al, 0x71

	mov	ah, 0xf5
	PRINTLN "Entering Protected-Mode"
	call	waitkey
	# init pmode
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

	push	dword ptr 0x1337c0de


	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.

.if 0 # bug:
	.if PMODE_COMPATCS
	push	word ptr SEL_compatCS
	push	dword ptr offset pmode_entry$
	.else
	push	word ptr SEL_flatCS
	mov	eax, [codeoffset]
	add	eax, offset pmode_entry$
	push	eax
	.endif
	# switch out the cs register
	ADDR32 DATA32 retf
.else


	mov	eax, offset pmode_entry$

	.if PMODE_COMPATCS
	mov	[pm_entry + 4], word ptr SEL_compatCS
	.else
	mov	[pm_entry + 4], word ptr SEL_flatCS
	add	eax, [realsegflat]
	.endif
	mov	[pm_entry], eax
	
	PH8 "PM Entry: " eax

	jmp	0f	# clear prefetch queue
	0:	

	# switch out the cs register
	#DATA32 ljmp	SEL_flatCS, offset pmode_entry$ + RELOCATION
	.byte 0x66, 0xea
	pm_entry:.long 0
	.word SEL_flatCS

.endif
# pmode data
.data
msg$: .byte 'P', 0xf4, 'm', 0xf1, 'o', 0xf1, 'd', 0xf1, 'e', 0xf1
.equ msgl$, . - msg$
.equ rest_scr$, 80*25


.text
.code32
pmode_entry$:
	# setup
	.if PMODE_COMPATCS
	mov	ax, SEL_realmodeDS
	mov	ds, ax
	mov	ax, SEL_realmodeSS
	mov	ss, ax
	mov	ax, SEL_realmodeES
	mov	es, ax
	mov	ax, SEL_realmodeFS
	mov	fs, ax
	mov	ax, SEL_realmodeGS
	mov	gs, ax
	.else
	mov	ss, ax
	mov	ax, SEL_flatDS
	mov	es, ax
	mov	ss, ax
	.endif

	# payload ( to test exit pmode )
	mov	ebx, edi # print it to see if preserved

	.macro SCREEN_OFFS x, y
		o =  2 * ( \x + 80 * \y )
		.if PMODE_COMPATCS
		.if o == 0
		xor	edi, edi
		.else
		mov	edi, o
		.endif
		.else
		mov	edi, 0xb8000 + o
		.endif
	.endm

	/*
	SCREEN_OFFS 0, 0
	mov	ecx, rest_scr$ #cls
	mov	ax, 0x5f << 8 | '.'
	rep	stosw
	*/

	SCREEN_OFFS 37, 12
	mov	esi, offset msg$ # print
	mov	ecx, msgl$
	rep	movsb

	SCREEN_OFFS 0, 14
	mov	ah, 0x3f
	mov	edx, [codeoffset]
	call	printhex8_32
	add	edi, 2

	# pop 1337c0de
	pop	edx		
	call	printhex8_32

	SCREEN_OFFS 0, 15
	# test self modifying code
	mov	ds:[ smc$ + 1], word ptr 0x1337
	jmp	smc$ # clear prefetch queue
smc$:
	mov	edx, 0xfa11
	call	printhex8_32
	
	SCREEN_OFFS 0, 16
	mov	ah, 0xf5
	mov	edx, ebx
	call	printhex8_32
	SCREEN_OFFS 0, 17


	xor	edx, edx
	pop	dx	# real mode return address
	# this offset is based on the realmode segment we were called with.
	# If we return in flat CS mode, we'll need to adjust it:
	.if PMODE_COMPATCS
	.else
	add	edx, [realsegflat]
	.endif
	push	edx

	.if DEBUG
	mov	ah, 0xf7
	call	printhex8_32
	.endif

	ret
	# see if this call works in pmode...
	#xor	ah, ah
	#int	0x16
	# nope:
#0:	in	al, 0x64
#	stosw
#	sub	di, 2
#	test	al, 2
#	jz	0b
#	in	al, 0x60
#	stosw

# call this from protected mode!
.code32
real_mode:
	cli
	# set NMI off
	in	al, 0x70
	or	al, 0x80 # XXX nmi on?
	out	0x70, al
	in	al, 0x71


	# ljmp SEL_realmodeCS, offset 0f
	# 0x66 0xea [long return address] [word sel_16bitcs]
	# doesnt work due to non-relocated addresses;
	# requires self modifying code,
	# or:
	push	SEL_realmodeCS
	push	dword ptr offset 0f
	retf
.code16
0:	# pmode 16 bit realmode code selector

	# enter realmode
	mov	eax, cr0
	and	al, 0xfe
	mov	cr0, eax

	# restore realmode cs 
	push	[bkp_reg_cs]
	mov	ax, [codeoffset]
	add	ax, offset 0f
	push	ax
	retf
0:
	# restore ds, es, ss
	mov	ds, [bkp_reg_ds]
	mov	es, [bkp_reg_es]
	mov	ss, [bkp_reg_ss]


	# restore IDT

	lidt	rm_idtr

	# NMI off
	in	al, 0x70
	and	al, 0x7f
	out	0x70, al
	in	al, 0x71

	#sti

.if 0 # DEBUG
	# restore segment registers

	push	0xb800
	pop	es
	mov	di, 160 * 18
	mov	ah, 0x4f
	mov	dx, 0x1337
	call	printhex

	PRINT "cs: "
	mov	dx, cs
	call	printhex
	PRINT "ds: "
	mov	dx, ds
	call	printhex
	PRINT "ss: "
	mov	dx, ss
	call	printhex

	PRINT "Backed up RM cs: "
	mov	dx, [bkp_reg_cs]
	call	printhex
	PRINT "ds: "
	mov	dx, [bkp_reg_ds]
	call	printhex
	PRINT "ss: "
	mov	dx, [bkp_reg_ss]
	call	printhex
	call	newline

	PRINT "Restored Realmode CS: "
	#mov	sp, [bkp_reg_sp]
	mov	dx, cs
	call	printhex

	PRINT "SS:SP: "
	mov	dx, ss
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	dx, sp
	call	printhex
.endif
	PRINT "Return address: "

	pop	edx
	push	dx

	mov	bp, sp
	mov	dx, [bp]
	call	printhex

	call	waitkey

	ret
#####################################################################

.code32
int_count: .long 0
gate_int32:
	push	ax
	push	ds
	
	mov	ax, SEL_flatDS
	mov	ds, ax
	mov	[0xb8000], byte ptr '!'

	pop	ds
	pop	ax
	iret

	cli
	push	es
	push	edi
	push	edx
	push	ax

#	mov	di, SEL_vid_txt
#	mov	es, di
	inc	byte ptr es:[0]
	/*
	xor	edi, edi
	mov	ax, 0xf2<<8 + '!'
	stosw
	mov	edx, [int_count]
	call	printhex8_32
	inc	dword ptr [int_count]
	*/

	pop	ax
	pop	edx
	pop	edi
	pop	es
	#sti
	iret



.code16
test_protected_mode:
	mov	ax, 0x7000
	call	cls
	mov	bp, sp
	PRINT "TEST PM called from: "
	mov	dx, [bp]
	call	printhex
	call	newline
	
	# QEMU: GDT limit 37 base FCD80  IDT limit  3ff base 0
	# VBOX: GDT limit 30 base FC7F3  IDT limit ffff base 1
.macro PRINT_DT msg, gdt, idt
# Realmode GDT:
	PRINT	"\msg"
	PRINT	" GDT: limit="
	mov	dx, [\gdt]
	call	printhex
	PRINT "base="
	mov	edx, [\gdt+2]
	call	printhex8
# Realmode IDT:
	PRINT "  IDT: limit="
	mov	dx, [\idt]
	call	printhex
	PRINT "base="
	mov	edx, [\idt+2]
	call	printhex8
.endm
	sgdt	[rm_gdtr]	# limit=30 base=000FC7F3
	sidt	[rm_idtr]	# limit=FFFF base=00000000
	PRINT_DT "Realmode" rm_gdtr rm_idtr
	PRINT_DT "PMode   " pm_gdtr pm_idtr

	call	newline

	xor	ax, ax	# pmode argument: flat code XXX for now not dynamic
	call	protected_mode
.code32
pmode:

	#SCREEN_OFFS 0, 20
	mov	ah, 0x3f
	mov	edx, 0x1337c0de
	call	printhex8_32
	mov	edx, offset 0f
	call	printhex8_32

# add a delay so the already printed output gets rendered by the VM before it
# crashes..
	mov	ecx, 100000
	mov	ah, 0x41
0:	nop
	#mov	edx, ecx
	#xor	edi, edi # assume es=vid_txt
	#call	printhex8_32
	loop 0b


#################################################

	PRINTLN_32 "Loading IDT"

	cli

	push	es
	push	edi

	mov	edi, offset IDT
	mov	ax, SEL_realmodeDS
	mov	es, ax
	mov	ecx, 256
#	xor	eax, eax
#	rep	stosb
	mov	eax, offset gate_int32
	#add	eax, [realsegflat]
0:	mov	[edi + 0], ax
	mov	[edi + 2], word ptr SEL_compatCS
	mov	[edi + 4], word ptr 0x8e00
	ror	eax, 16
	mov	[edi + 6], ax
	ror	eax, 16
	add	edi, 8
	loop	0b

	pop	edi
	pop	es

	mov	eax, [realsegflat]
	add	eax, dword ptr offset IDT
	mov	[pm_idtr+2], eax # dword ptr offset IDT
	lidt	pm_idtr

	int	55

.if 0

	# Initialize IDT
	mov	esi, offset IDT
	mov	ecx, 256
	mov	eax, offset gate_int32
	push	eax
	mov	edx, eax
	mov	ah, 0x7f
	call	printhex8_32
	pop	eax

	mov	ecx, 100000
0:	nop
	loop 0b
	#sti
.endif
#################################################


	call	real_mode
.code16
	ret

