.intel_syntax noprefix

IRQ_BASE = 0x20	# base number for PIC hardware interrupts
DEBUG = 0 # debug is b0rk3d!

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
# the code after this method uses a different relocation scheme. Similarly
# for non-relative code references.
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
	GDT_GET_BASE bx
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
#################################################
.include "keyboard.s"
#################################################

gate_task32:
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

bios_proxy:
	# dl = the interrupt.
	# call the realmode handler, staying in pmode
	push	ebp
	mov	ebp, esp
	push	eax
	push	edx
	push	edi
	# mov edi, current_screen_pos

	mov	ax, SEL_flatDS
	mov	ds, ax
	and	edx, 0xff
	shl	edx, 2
	mov	edx, [edx]	# load INT handler ptr
	mov	ah, 0xf6
	call	printhex_32
	mov	al, ':'
	stosw
	ror	edx, 16
	call	printhex_32
	ror	edx, 16

	cmp	dx, 0xf000
	LOAD_TXT "Not BIOS call"
	je	0f

	# now, we need to restore the registers, and push the BIOS call
	# address on the stack.
	# We'll just duplicate the call stack, assuming that BIOS
	# functions do not use stack arguments except the flags.
	#(which they dont AFAIK).

	# set up fake call stack for bios function
	mov	ax, [ebp + 4 + 4 + 2]	# low word flags
	push	ax
	push	cs
	push	offset 2f # assumes non-0-based (flat) cs
	# now, in 16 bit code, iret will return us at label 2

	# prepare call structure to jump to 16 bit bios using 32 bit iret:
	mov	eax, [ebp + 4 + 4 + 2]  # flags
	push	eax	
	push	word ptr SEL_biosCS	# selector/ 'segment'
	shr	edx, 16			# offset of function
	push	edx	# offset

	# restore registers:

	mov	edx, [ebp - 20]
	mov	edi, [ebp - 16]
	mov	ax,  [ebp - 12] # ds
	mov	ds, ax
	mov	ax,  [ebp - 10] # es
	mov	es, ax
	mov	esi, [ebp - 8]
	mov	eax, [ebp - 4]
	mov	ebp, [ebp]

	# now use iret to conveniently jump
	iret
.code16
2:	# BIOS should return here in 16 bit CS selector
	# return to 32 bit CS
	push	SEL_compatCS # should be same as in IDT
	push	offset 2f
	retf
.code32
2:	# back in 32 bit, show message:
	mov	ax, SEL_vid_txt
	mov	edi, 2 * ( 1*80 + 0 )
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	ah, 0xf1
	PRINT "Return from BIOS call"

	pop	edi
	pop	edx
	pop	eax
	pop	ebp
	ret # or iret, depending on how this is called.



.code16
test_protected_mode:
	mov	ax, 0x0800
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

	/*
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
	*/

	call	init_idt

	int	55


	call	hook_keyboard_isr32

	# NMI on
	in	al, 0x70
	and	al, 0x7f
	out	0x70, al
	in	al, 0x71

	sti # jic
	
	mov	ax, 0 # 0xfffd
	call	pic_set_mask

#######################################
	push	edi
	mov	ecx, 10000000
	xor	ebx, ebx
0:	SCREEN_OFFS 0, 1
	mov	ah, 0xf9

	mov	edx, ecx	# countdown
	call	printhex8_32
	add	edi, 2

	mov	edx, ebx	# nr of keystrokes
	call	printhex8_32
	add	di, 2


	push	ax
	mov	ah, 1
	call	keyboard
	mov	dx, ax
	pop	ax

	jz	1f
	call	printhex_32
	inc	edx
	jmp	2f

1:	PRINT_32 "No Key"
2:	

	test	ecx, 0xfffff
	jnz	1f
	int	0x55
1:

	loop	0b
	pop	edi

#######################################
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

mov	ax, unknown_symbol
	ret

.include "pic.s"
