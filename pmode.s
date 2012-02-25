.intel_syntax noprefix

IRQ_BASE = 0x20	# base number for PIC hardware interrupts
DEBUG = 0

.include "gdt.s"
.include "idt.s"
.include "tss.s"

#######################

.data

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
.text
.code16
# in: ax: Flags
# bit0:	0 = flat mode (flatCS, flatDS for all registers; esp updated)
#	1 = compatibility mode (compatCS, realmodeDS/ES/FS/GS/SS)
# SEL_realmodeCS is 16 bit, based on the value of cs when this method is called.
# SEL_compatCS is the 32 bit version of realmodeCS
# SEL_flatCS is 32 bit based zero.
#
# realmodeCS is used in the real_mode method to return to real mode.
#
# BEWARE when specifying 0 in ax when calling this function: ds will be
# flat, and thus most likely data references will not work, unless
# the code after this method uses a different relocation scheme.
#
# This method assumes that CS is the base pointer for the code,
# and will use the area before it as the TSS stack.

# for now this constant will serve as ax:
protected_mode:
	mov	[bkp_reg_cs], cs
	mov	[bkp_reg_ds], ds
	mov	[bkp_reg_es], es
	mov	[bkp_reg_ss], ss
	mov	[bkp_reg_sp], sp
	mov	[bkp_reg_fs], fs
	mov	[bkp_reg_gs], gs

	mov	bx, ax	# save arg

	.if DEBUG
		DBGSO16 "RealMode SS:IP: ", ss, sp
		DBGSTACK16 "Return IP: ", 0
		call	newline
	.endif


	call	init_gdt


	# enable A20

	in	al, 0x92	# system control port a, a20 line
	test	al, 2
	jnz	0f
	or	al, 2		# 0(w):1=fast reset/realmode
	out	0x92, al
0:

	# Interrupts off

	cli

	in	al, 0x70	# NMI off
	or	al, 0x80
	out	0x70, al
	in	al, 0x71

	mov	ax, (IRQ_BASE + 8) << 8 | IRQ_BASE
	call	pic_init

	.if DEBUG
		mov	ah, 0xf5
		PRINTLN "Entering Protected-Mode"
		call	waitkey
	.endif

	# init pmode
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax


	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.

	mov	eax, offset pmode_entry$
	mov	cx, SEL_compatCS

	or	bl, bl
	jnz	0f
	add	eax, [realsegflat]
	mov	cx, SEL_flatCS

0:	mov	[pm_entry + 4], word ptr SEL_flatCS
	mov	[pm_entry], eax

	.if DEBUG
		PH8 "PM Entry: " eax
	.endif

	jmp	0f	# clear prefetch queue
	0:	

	# switch out the cs register
	#DATA32 ljmp	SEL_flatCS, offset pmode_entry$ + RELOCATION
	.byte 0x66, 0xea
	pm_entry:.long 0
	.word SEL_flatCS
.code32
pmode_entry$:
	xor	edx, edx
	pop	dx	# real mode return address
	# this offset is based on the realmode segment we were called with.
	# If we return in flat CS mode, we'll need to adjust it:
	# setup
	test	bl, bl
	jz	0f
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
	jmp	1f
0:
	add	edx, [realsegflat]
	xor	eax, eax	# adjust ss:sp
	mov	ax, ss
	shl	eax, 4
	add	esp, eax
	mov	ax, SEL_flatDS
	mov	ds, ax
	mov	ss, ax
	mov	es, ax
	mov	fs, ax
	mov	gs, ax
1:
	push	edx

	.if DEBUG
		SCREEN_INIT
		SCREEN_OFFS 15, 0
		mov	ah, 0xf4
		call	printhex8_32
		mov	ecx, 100000000
	0:	mov	edx, ecx
		loop	0b
	.endif

	ret


#######################################################

# call this from protected mode!
.code32
real_mode:
	pop	edx	# convert stack return address

	mov	bx, cs	# add base of current selector to stack
	xor	ax, ax
	mov	al, [GDT+bx + 7]
	shl	eax, 16
	mov	ax, [GDT+bx + 2]
	add	edx, eax

	push	dx

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

	mov	ax, 0x7008
	call	pic_init

	# NMI on
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





.code16
test_protected_mode:
	mov	ax, 0x7000
	call	cls
	mov	bp, sp
	PRINT "TEST PM called from: "
	mov	dx, [bp]
	call	printhex
	call	newline
	

	xor	ax, ax	# pmode argument: flat code XXX for now not dynamic
	mov	al, 0
	call	protected_mode
.code32
pmode:

	.data
	msg$: .byte 'P', 0xf4, 'm', 0xf1, 'o', 0xf1, 'd', 0xf1, 'e', 0xf1
	.equ msgl$, . - msg$
	.equ rest_scr$, 80*25
	.text

	SCREEN_INIT

	mov	ax, SEL_realmodeDS
	mov	ds, ax

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

	SCREEN_OFFS 0, 15
	# test self modifying code
	mov	ds:[ smc$ + 1], word ptr 0x1337
	jmp	smc$ # clear prefetch queue
smc$:
	mov	edx, 0xfa11
	call	printhex8_32
	
	SCREEN_OFFS 0, 16


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

.include "pic.s"
