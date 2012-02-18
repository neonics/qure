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
 #			Ac: access bit, set by CPU on access
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

	# when this works, check IDT 


.equ ACC_PR,	1 << 7
.equ ACC_RING0,	0 << 5
.equ ACC_RING1,	1 << 5
.equ ACC_RING2,	2 << 5
.equ ACC_RING3,	3 << 5
.equ ACC_NRM,	1 << 4
.equ ACC_SYS,	0 << 4
.equ ACC_CODE,	1 << 3
.equ ACC_DATA,	0 << 3
.equ ACC_DC,	1 << 2
.equ ACC_RW,	1 << 1

.equ FL_GR1kb,	0 << 3
.equ FL_GR4kb,	1 << 3
.equ FL_16,	0 << 2
.equ FL_32,	1 << 2

.equ ACCESS_CODE, (ACC_PR|ACC_RING0|ACC_NRM|ACC_CODE|ACC_RW) # 0x9a
.equ ACCESS_DATA, (ACC_PR|ACC_RING0|ACC_NRM|ACC_DATA|ACC_RW) # 0x92
.equ FLAGS_32, (FL_GR4kb|FL_32) # 0x0c
.equ FLAGS_16, (FL_GR1kb|FL_16) # 0x00

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
GDT: 	.space 8	# null descriptor
GDT_flatCS:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_32 #ffff 0000 00 9a cf 00
GDT_flatDS:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32 #ffff 0000 00 92 ca 00
GDT_realmodeCS:	DEFGDT 0, 0x00ffff, ACCESS_CODE, FLAGS_16 #ffff 0000 00 9a 00 00
GDT_realmodeDS: DEFGDT 0, 0x00ffff, ACCESS_DATA, FLAGS_16 #ffff 0000 00 92 00 00
gdtr:	.word . - GDT -1
	.long GDT

	.equ SEL_flatCS, 8
	.equ SEL_flatDS, 16
	.equ SEL_realmodeCS, 24
	.equ SEL_realmodeDS, 32

codeoffset: .long 0
bkp_reg_cs: .word 0
bkp_reg_ds: .word 0
bkp_reg_es: .word 0
bkp_reg_ss: .word 0
bkp_reg_sp: .word 0

.text
.code16
protected_mode:
	mov	[bkp_reg_cs], cs
	mov	[bkp_reg_ds], ds
	mov	[bkp_reg_es], es
	mov	[bkp_reg_ss], ss
	mov	[bkp_reg_sp], sp
	mov	dx, ss
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	dx, sp
	call	printhex

	PRINTLN "Enabling A20"
	# enable A20
	in	al, 0x92	# system control port a, a20 line
	test	al, 2
	jnz	0f
	or	al, 2		# 0(w):1=fast reset/realmode
	out	0x92, al
0:

	# Calulate segments and addresses

	# determine cs:ip since we do not assume to be loaded at any address
	xor	ebx, ebx # in case cs != 0
	mov	bx, cs
	shl	ebx, 4
	mov	word ptr GDT_realmodeCS+2, bx
	shr	eax, 16
	mov	byte ptr GDT_realmodeCS+4, bl

	xor	eax, eax
	call	0f	# determine absolute address
0:	pop	ax
	sub	ax, offset 0b

	add	ebx, eax
	mov	[codeoffset], ebx

	# dynamically calculate cs/ds and store in GDT realmode descriptors
	xor	eax, eax
	mov	ax, ds
	shl	eax, 4
	push	eax	# ds << 4
	mov	word ptr GDT_realmodeDS+2, ax
	shr	eax, 16
	mov	byte ptr GDT_realmodeDS+4, al
	# ignore ah as lgdt ignores it when called from 16 bit mode

	# configure gdt (residing in data segment)
	pop	eax	# ds << 4
	add	eax, offset GDT
	mov	dword ptr gdtr+2, eax


	PRINTLN "Loading Global Descriptor Table"

	DATA32 ADDR32 lgdt	gdtr

	cli
	# set NMI off
	in	al, 0x70
	or	al, 0x80 # XXX nmi on?
	out	0x70, al
	in	al, 0x71

	PRINTLN "Entering Protected-Mode"
	# init pmode
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.
	mov	eax, [codeoffset]
	add	eax, offset PM_entry
	mov	[pm_entry], eax

	jmp	0f	# clear prefetch queue
0:	

	# switch out the cs register
	#DATA32 ljmp	SEL_flatCS, offset PM_entry + RELOCATION
	.byte 0x66, 0xea
pm_entry:.long 0
	.word SEL_flatCS

# pmode data
.data
	message: .byte 'P', 0xf4, 'm', 0xf1, 'o', 0xf1, 'd', 0xf1, 'e', 0xf1
	.equ message_1, .-message
	.equ rest_scr, 80*25

.text
.code32
PM_entry:
	# setup
	mov	ax, SEL_realmodeDS
	mov	ds, ax
	mov	ss, ax
	mov	ax, SEL_flatDS
	mov	es, ax

	# payload ( to test exit pmode )
	mov	edi, 0xB8000
	mov	ecx, rest_scr #cls
	mov	ax, 0x0720
	rep	stosw


	mov	edi, 0xB8000 + 2*(37 + 12*80)
	mov	esi, offset message # print

# message doesnt always print... so check offset
#mov	edx, esi
#call	printhex8

	mov	ecx, message_1
	rep	movsb

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
real_mode:
	# ljmp SEL_realmodeCS, offset 0f
	# 0x66 0xea [long return address] [word sel_16bitcs]
	# doesnt work due to non-relocated addresses;
	# requires self modifying code,
	# or:
	push	SEL_realmodeCS
	mov	eax, [codeoffset]
	add	eax, offset 0f
	push	eax
	retf
.code16
0:	# back in realmode code segment (within Pmode)

	# enter realmode
	mov	eax, cr0
	and	al, 0xfe
	mov	cr0, eax

	# NMI off
	in	al, 0x70
	and	al, 0x7f
	out	0x70, al
	in	al, 0x71

	push	0xb800
	pop	es
	xor	di, di
	mov	ah, 0x4f
	mov	dx, 0x1337
	call	printhex
#hlt
	mov	di, 160
	mov	dx, cs
	call	printhex
	mov	dx, ds
	call	printhex
	mov	dx, ss
	call	printhex

	mov	di, 160 * 2
	mov	dx, [bkp_reg_cs]
	call	printhex
	mov	dx, [bkp_reg_ds]
	call	printhex
	mov	dx, [bkp_reg_ss]
	call	printhex


	# restore ds, es, ss
	mov	ds, [bkp_reg_ds]
	mov	es, [bkp_reg_es]
	mov	ss, [bkp_reg_ss]

	# restore cs 
	push	[bkp_reg_cs]
	mov	ax, [codeoffset]
	add	ax, offset 0f
	push	ax
	retf
0:
	mov	ah, 0x0f
	mov	dx, 0xc001
	call	printhex
	mov	dx, ds
	call	printhex

	#mov	sp, [bkp_reg_sp]
	mov	dx, cs
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	bp, sp
	mov	dx, [bp]
	call	printhex

	call	waitkey

	ret
