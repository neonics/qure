.intel_syntax noprefix
.text # tmp here to mark for vi

IRQ_BASE = 0x20	# base number for PIC hardware interrupts

###########################

.include "pic.s"
.include "gdt.s"
.include "idt.s"
.include "tss.s"

###########################

.text	# realmode access, keep within 64k

realsegflat:.long 0
codeoffset: .long 0
database: .long 0
kernel_location: .long 0
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
	# Configuration/RTC (CMOS): AT and PS/2. PC uses 0xA0.
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
# TODO: in: edi: relocation base (flat offset). 0 means no relocation.
#
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

protected_mode:
	mov	[bkp_reg_cs], cs
	mov	[bkp_reg_ds], ds
	mov	[bkp_reg_es], es
	mov	[bkp_reg_ss], ss
	mov	[bkp_reg_sp], sp
	mov	[bkp_reg_fs], fs
	mov	[bkp_reg_gs], gs
	mov	[kernel_location], edi

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

	mov	ax, (( IRQ_BASE + 8 )<<8) | IRQ_BASE	# 0x2820
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
		rmPC 0x01 "Flat"
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

	# DO NOT PLACE CODE HERE -
	#
	# A jump (near or far) must be done IMMEDIATELY after a mode switch,
	# to clear out the prefetch queue.

	# unreal mode: load some segment selectors, and switch to realmode

	# switch out the cs register.
	# DATA32 ljmp	SEL_flatCS, offset pmode_entry$ + RELOCATION
	.byte 0x66, 0xea
	pm_entry:.long 0
	.word SEL_flatCS
.code32
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
	pop	edx	# real mode return address
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
	xor	eax, eax
	mov	ax, ss	# adjust ss:sp
	shl	eax, 4
	add	esp, eax
	mov	ax, SEL_flatDS
	mov	ss, ax
	mov	es, ax
	mov	fs, ax
	mov	gs, ax
	mov	ax, SEL_compatDS 
	mov	ds, ax

	.if 0
	# RELOCATION CODE GOES HERE
	# adjust edx
	
	push	es
	push	edi
	mov	edi, [kernel_location]
	or	edi, edi
	jz	0f
	mov	si, SEL_flatDS
	mov	es, si
	mov	esi, offset realmode_kernel_entry
		mov	eax, edi
		sub	eax, esi
		sub	eax, [codeoffset]
		
	mov	ecx, offset kernel_end
	rep	movsb
0:
	pop	edi
	pop	es
	.endif

1:

	push	edx

mov [screen_pos], edi
OK


	I "Loading IDT"

	call	init_idt

	OK

	PIC_SET_MASK 0xffff & ~(1<<IRQ_CASCADE)

	call	keyboard_hook_isr
	call	pit_hook_isr

	INTERRUPTS_ON

	# load Task Register

	.if DEBUG > 2
		PRINTc 8 "  Load Task Register"
	.endif

	mov	ax, SEL_tss
	ltr	ax

	.if DEBUG > 2
		OK
		COLOR 8
		PH8 "  Return address: ", edx
		call	newline
	.endif


	# if flat mode is requested, set ds to flat. Data references,
	# unless relocated to reflect the memory address, wont work.
	test	bl, bl
	jnz	0f
	mov	ax, SEL_flatDS
	mov	ds, ax

0:	ret	# at this point interrupts are on, standard handlers installed.


#######################################################

# call this from protected mode!
.code32
# This section will work when this method is called from pmode,
# having a pmode return address on the stack which will be converted to
# realmode address.
enter_real_mode:
	mov	bx, SEL_compatDS
	mov	ds, bx

	pop	edx	# convert stack return address
	GDT_GET_BASE eax, cs	# add base of current selector to stack
	add	edx, eax
	push	dx

# This will return to real-mode, assuming the stack points to a real-mode
# address, possibly the address from which protected_mode was called.
real_mode:

	INTERRUPTS_OFF

	ljmp	SEL_realmodeCS, offset 0f
.code16
0:	# pmode 16 bit realmode-compatible code selector

	# prepare return address
	push	[bkp_reg_cs]
	mov	ax, [codeoffset]
	add	ax, offset rm_entry
	push	ax

	# enter realmode
	mov	eax, cr0
	and	al, 0xfe
	mov	cr0, eax

	# PLACE NO CODE HERE - serialize CPU to reload code segment

	retf

rm_entry:
	mov	ax, 0xb800
	mov	es, ax

	rmI "Back in realmode"

	# restore ds, es, ss
	mov	ds, [bkp_reg_ds]
	mov	es, [bkp_reg_es]
	mov	ss, [bkp_reg_ss]
#	mov	sp, [bkp_reg_sp]


	# restore IDT

	lidt	rm_idtr

	# remap PIC

	mov	ax, 0x7008
	call	pic_init16

	PIC_SET_MASK 0xffff & ~( (1<<IRQ_CASCADE) | (1<<IRQ_KEYBOARD) )

	INTERRUPTS_ON

	.if DEBUG_KERNEL_REALMODE
		printc_16 8, " cs:"
		mov	dx, cs
		call	printhex_16
		printc_16 8, "ds:"
		mov	dx, ds
		call	printhex_16
		printc_16 8, "ss:sp: "
		mov	dx, ss
		call	printhex_16
		mov	dx, sp
		call	printhex_16

		printc_16 8, "ret cs:ip: "
		mov	bp, sp
		mov	dx, [bp + 2]
		mov	fs, dx
		call	printhex_16
		mov	dx, [bp]
		call	printhex_16
		mov	bx, dx
		call	newline_16

		printc_16 8, "Target Code: "
		mov	cx, 8
	0:	mov	dl, fs:[bx]
		call	printhex2_16
		inc	bx
		loop	0b
		print_16 " - Press a key"
		xor	ah, ah
		int	0x16
	.endif
	call	newline_16

	mov	di, [screen_pos]

	retf

