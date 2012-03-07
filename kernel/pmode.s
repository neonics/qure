.intel_syntax noprefix
.text # tmp here to mark for vi

IRQ_BASE = 0x20	# base number for PIC hardware interrupts
DEBUG = 3 # debug is b0rk3d!

########################## 16 bit macros
.macro rmD a b
	PRINT_START_16
	mov	ax, (\a << 8 ) + \b
	stosw
	PRINT_END_16
.endm

.macro rmW
	D 0x2f '?'
	push	ax
	xor	ah, ah
	int	0x16
	pop	ax
.endm

.macro rmH
	D 0x4f 'H'
9:	hlt
	jmp 9b
.endm

.macro rmPC c m
	rmCOLOR \c
	PRINT_16 "\m"
.endm

.macro rmI m
	rmD 0x09 '>'
	rmPC 0x07 " \m"
.endm

.macro rmI2 m
	rmPC 0x08 "\m"
.endm

.macro rmOK
	rmCOLOR 0x0a
	PRINTLN_16 " Ok"
.endm

############################# 32 bit macros 
.macro OK
	COLOR 0x0a
	PRINTLN " Ok"
.endm


.include "pic.s"
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

.macro NMI_OFF
	in	al, 0x70
	or	al, 0x80
	out	0x70, al
	in	al, 0x71
.endm

.macro NMI_ON
	in	al, 0x70
	and	al, 0xfe
	out	0x70, al
	in	al, 0x71
.endm

.macro INTERRUPTS_ON
	NMI_ON
	sti
.endm

.macro INTERRUPTS_OFF
	cli
	NMI_OFF
.endm


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

rmI "Initialize GDT"

	call	init_gdt_16

	mov	[screen_sel], word ptr SEL_vid_txt
rmOK

	# enable A20

	in	al, 0x92	# system control port a, a20 line
	test	al, 2
	jnz	0f
	or	al, 2		# 0(w):1=fast reset/realmode
	out	0x92, al
0:

	INTERRUPTS_OFF

rmI "Remapping PIC"
	.if DEBUG > 2
		call newline_16
	.endif

	mov	ax, 0x2820
	call	pic_init16

rmOK


	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.

	# prepare the far jump instruction

	.if DEBUG > 1
		rmI "Preparing Entry Point: "
	.endif

	mov	eax, offset pmode_entry$
	mov	cx, SEL_compatCS

	or	bl, bl
	jnz	0f
	add	eax, [realsegflat]
	mov	cx, SEL_flatCS

	.if DEBUG > 1
		rmPC 0x02 "Flat "
		jmp 1f
	0:	
		rmPC 0x03 "Realmode Compatible"
	1:
		rmI2 " Address mode"
		rmOK
	.else
0:	
	.endif

	mov	[pm_entry + 4], cx # word ptr SEL_flatCS
	mov	[pm_entry], eax

	.if DEBUG > 2
		rmI2 "  - Address: "

		rmCOLOR 0x01
		mov	dx, cx
		call	printhex_16
		mov	edx, eax
		call	printhex8_16

		rmI2 " flat segment offset: "
		rmCOLOR 0x0a
		mov	edx, [realsegflat]
		call	printhex8_16
		call	newline_16
	.endif

	.if DEBUG > 0
		rmI "Entering "
		mov	edi, [screen_pos]
	.endif

	.if 0
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	fs, ax
	mov	gs, ax
	mov	ss, ax
	.endif

	# init pmode
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

	# unreal mode: load some segment selectors, and switch to realmode

	# switch out the cs register.
	# A jump (near or far) must be done IMMEDIATELY after a mode switch,
	# to clear out the prefetch queue.

	# DATA32 ljmp	SEL_flatCS, offset pmode_entry$ + RELOCATION
	.byte 0x66, 0xea
	pm_entry:.long 0
	.word SEL_flatCS
.code32
.p2align 2
pmode_entry$:

	# print Pmode
	mov	ax, SEL_vid_txt
	mov	es, ax
	mov	ax, (0x0c<<8)|'P'
	stosw
	mov	ax, (0x09<<8)|'m'
	stosw
	mov	al, 'o'
	stosw
	mov	al, 'd'
	stosw
	mov	al, 'e'
	stosw

	# adjust return address 
	xor	edx, edx
	pop	dx	# real mode return address
	# this offset is based on the realmode segment we were called with.
	# If we return in flat CS mode, we'll need to adjust it:
	# setup

	test	bl, bl
	jz	0f
	mov	ax, SEL_compatDS # realmodeDS
	mov	ds, ax
	mov	ax, SEL_compatSS # realmodeSS
	mov	ss, ax
	mov	ax, SEL_realmodeES
	mov	es, ax
	mov	ax, SEL_realmodeFS
	mov	fs, ax
	mov	ax, SEL_realmodeGS
	mov	gs, ax
	jmp	1f
0:
	add	edx, [realsegflat]	# flat cs, so adjust return addr
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

mov	ax, SEL_compatDS 
mov	ds, ax
mov [screen_pos], edi
OK

	# load Task Register

	.if DEBUG > 2
		COLOR 8
		PH8 "  Return address: ", edx
		call	newline
		PRINTc 8 "  Load Task Register"
	.endif

	mov	ax, SEL_tss
	ltr	ax

	.if DEBUG > 2
		OK
	.endif
test bl, bl
jnz 0f
mov ax, SEL_flatDS
mov ds, ax
0:
	ret	# at this point all interrupts are off.


#######################################################

# call this from protected mode!
.code32
real_mode:
	pop	edx	# convert stack return address

	mov	bx, cs	# add base of current selector to stack
	GDT_GET_BASE bx
	add	edx, eax

	push	dx

	INTERRUPTS_OFF

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
	jmp	0f	# 'serialize cpu': flush internal cache
0:

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
	call	pic_init16

	INTERRUPTS_ON

	mov	bp, sp
	mov	dx, [bp]

	ret

#################################################
#################################################

.code16
test_protected_mode:
	mov	ax, 0x0800
	call	cls
	mov	bp, sp
	PRINT	"TEST PM called from: "
	mov	dx, [bp]
	call	printhex
	call	newline

	# wait until input buffer is read 
0:	in	al, 0x64
	test	al, 2
	jnz	0b


	xor	ax, ax	# pmode argument: flat code XXX for now not dynamic
	mov	al, 0
	call	protected_mode
.code32
pmode:	#label for disassembly code alignment

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
	call	printhex8
	add	edi, 2

	SCREEN_OFFS 0, 15
	# test self modifying code
	mov	ds:[ smc$ + 1], word ptr 0x1337
	jmp	smc$ # clear prefetch queue
smc$:
	mov	edx, 0xfa11
	call	printhex8
	
	SCREEN_OFFS 0, 16


	#SCREEN_OFFS 0, 20
	mov	ah, 0x3f
	mov	edx, 0x1337c0de
	call	printhex8
	mov	edx, offset 0f
	call	printhex8

# add a delay so the already printed output gets rendered by the VM before it
# crashes..
	mov	ecx, 100000
	mov	ah, 0x41
0:	nop
	#mov	edx, ecx
	#xor	edi, edi # assume es=vid_txt
	#call	printhex8
	loop 0b


#################################################

	PRINTLN "Loading IDT"

	call	init_idt
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


	int	0x55		# software interrupt

FOO:
	PIC_SET_MASK 0xfffe #0xfffc

	call	hook_keyboard_isr
.if 1
	mov	cx, SEL_compatCS
	mov	eax, 0x20
	mov	ebx, offset isr_timer
	call	hook_isr
.endif

	INTERRUPTS_ON


	# This works!:
	#call	task_switch


#######################################
.data 
k_scr_o:.long 160 * 6 + 20
.text
	push	edi
	mov	ecx, 10000000
	xor	ebx, ebx
0:	SCREEN_OFFS 0, 5
	mov	ah, 0xf9

	mov	edx, ecx	# countdown
	call	printhex8

	SCREEN_OFFS 0, 6
	add	edi, 2

	mov	edx, ebx	# nr of keystrokes
	call	printhex8
	add	edi, 2

#######################################

	push	ax
	mov	ah, 0
	call	keyboard
	mov	dx, ax
	pop	ax

	mov	edi, [k_scr_o]

	jz	1f
	mov	al, '*'
	stosw
	call	printhex

	cmp	dl, 'q'
	je	3f
	cmp	dx, K_ESC
	je	3f

	inc	ebx
	add	edi, 2
	jmp	2f

1:	# PRINT "No Key"
2:	
	mov	[k_scr_o], edi
######################################

	test	ecx, 0xfffff
	jnz	1f
	int	0x55
1:
	sti
	hlt
	loop	0b
3:	pop	edi

################################################

	call	real_mode
.code16
	ret

.code32
