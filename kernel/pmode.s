.intel_syntax noprefix

IRQ_BASE = 0x20	# base number for PIC hardware interrupts

DEBUG_PM = 3	# max 3

###########################

.include "../16/gdt.s"
.include "../16/pmode.s"
.purgem DEFGDT
##########################

.include "pic.s"
.include "gdt.s"
.include "idt.s"
.include "tss.s"

###########################

.data16	# realmode access, keep within 64k

realsegflat:.long 0
reloc$: .long 0
codeoffset: .long 0	# realmode ip offset (if not loaded at 16-byte cs alignment)
kernelbase: .long 0	# abs load addr
codebase: .long 0
database: .long 0
kernel_tss0_stack_top: .long 0
kernel_sysenter_stack: .long 0
kernel_stack_top: .long 0
kernel_stack_bottom: .long 0	# either kernel_load_end or ramdisk_load_end
bkp_reg_cs: .word 0
bkp_reg_ds: .word 0
bkp_reg_es: .word 0
bkp_reg_ss: .word 0
bkp_reg_sp: .word 0
bkp_reg_fs: .word 0
bkp_reg_gs: .word 0


bkp_pm_mode: .word 0
bkp_pm_ss:   .word 0
bkp_pm_esp:  .long 0
bkp_pm_cr0:  .long 0


##########################

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


.text16

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
#
# Stack: dword pmode continuation, dword realmode (offs,seg) return address
protected_mode:
	mov	[bkp_reg_cs], cs
	mov	[bkp_reg_ds], ds
	mov	[bkp_reg_es], es
	mov	[bkp_reg_ss], ss
	mov	[bkp_reg_sp], sp
	add	[bkp_reg_sp], word ptr 4 # ignore the pmode cont arg
	mov	[bkp_reg_fs], fs
	mov	[bkp_reg_gs], gs
	mov	[bkp_pm_mode], ax
/*
call cls_16
print_16 "entering pmode"
push ax
call waitkey
pop ax
print_16 "..."
_ONE:
call enter_pmode		# 195d  / 1f6d9
#print_16 "!!!"
_TWO:
call enter_realmode
_THREE:
print_16 "entered realmode"
*/

	.if DEBUG_PM > 1
		mov	dx, cs
		print_16 "cs "
		call	printhex_16

		mov	dx, ds
		print_16 "ds "
		call	printhex_16

		mov	dx, ss
		print_16 "ss:sp "
		call	printhex_16
		mov	dx, sp
		call	printhex_16
		print_16 ": "
		push	bp
		mov	bp, sp
		add	bp, 2
	0:	mov	dx, ss:[bp]
		call	printhex_16
		add	bp, 2
		jnz	0b
		pop	bp
		call	newline_16
	.endif

	.if DEBUG_PM
		rmI "Initialize GDT"
	.endif

	call	init_gdt_16

	.if DEBUG_PM
		rmOK
	.endif

	# enable A20

	in	al, 0x92	# system control port a, a20 line
	test	al, 2
	jnz	0f
	or	al, 2		# 0(w):1=fast reset/realmode
	out	0x92, al
0:

	INTERRUPTS_OFF

	.if DEBUG_PM
		rmI "Remapping PIC"
	.endif

	mov	ax, (( IRQ_BASE + 8 )<<8) | IRQ_BASE	# 0x2820
	call	pic_init16

	.if DEBUG_PM
		rmOK
	.endif


	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.

	# prepare the far jump instruction
	mov	eax, offset pmode_entry$	# relocation

	.if DEBUG_PM > 1
		rmI "Preparing Entry Point: "
		push	edx
		mov	edx, eax
		call	printhex8_16
		GETFLAT
		PH8_16	edx, "opcodes: "
		pop	edx
	.endif

	mov	cx, SEL_compatCS
	cmp	[bkp_pm_mode], word ptr 0
	jnz	0f
	mov	cx, SEL_flatCS

	.if DEBUG_PM > 1
		PRINTc_16 0x01, "Flat"
		jmp	1f
	0:	PRINTc_16 0x03, "Realmode Compatible"
	1:	rmI2	" Address mode"
		rmOK
	.else
0:	
	.endif

	mov	[pm_entry + 4], cx
	mov	[pm_entry], eax

	.if DEBUG_PM > 1
		rmI2 "  - Address: "

		COLOR_16 0x09
		mov	dx, cx
		call	printhex_16
		mov	edx, eax
		call	printhex8_16
		mov	bx, cx
		GDT_PRINT_ENTRY_16 bx
		call	newline_16

		rmI2 " kernelbase: "
		COLOR_16 0x0a
		mov	edx, [kernelbase]
		call	printhex8_16

		rmI2 " realsegflat: "
		COLOR_16 0x0a
		mov	edx, [realsegflat]
		call	printhex8_16

		rmI2 " reloc: "
		COLOR_16 0x0a
		mov	edx, [reloc$]
		call	printhex8_16

		rmI2 "Stack: "
		mov	dx, ss
		call	printhex_16
		mov	edx, esp
		call	printhex8_16
	.endif

	.if DEBUG_PM
		rmI "Entering "
		mov edi, [pm_entry]
		PH8_16 edi, "PM ENTRY stored:"
_HAK:
		#mov edi, offset pmode_entry$
		xor edi,edi
		mov di, offset pmode_entry$	# unrelocated (due to 16bit)
		PH8_16 edi, "PM ENTRY relocated:"
	.endif

# delay loop
.if 0 # <<4: for vmware; <<1 or << 2 for qemu
mov ax, 0x0800#<<2
0:
mov cx, -1; 1: nop; loop 1b
dec ax
jnz 0b
.endif

	mov	edi, [screen_pos_16]

	.if 0	# 0='unreal mode'
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
pmjump$:
	.byte 0x66, 0xea
	pm_entry:.long 0
	.word SEL_flatCS
.text32
pmode_entry$:
	# print Pmode
	mov	ax, SEL_vid_txt
	mov	es, ax

	.if DEBUG_PM
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
	.endif

#0:hlt;jmp 0b
	# adjust return address
	xor	edx, edx # (was meant for pop dx)
	pop	edx	# real mode return address
	# this offset is based on the realmode segment we were called with.
	# If we return in flat CS mode, we'll need to adjust it:
	# setup

	xor	ax, ax
	mov	fs, ax
	mov	gs, ax

	cmp	[bkp_pm_mode], word ptr 0
	jz	0f

	mov ax, '1' | (13<<8)
	stosw

	mov	ax, SEL_compatDS # realmodeDS
	mov	ds, ax
	mov	es, ax
	.if 0
	mov	ax, SEL_compatSS # realmodeSS
	mov	ss, ax
	.else
	# stack is 'clean', so alloc a new one:
	mov	ss, ax
	mov	esp, [kernel_stack_top]
	.endif
	jmp	1f
0:

	mov ax, '0' | (13<<8)
	stosw

	add	edx, [reloc$]	# flat cs, so adjust return addr
	xor	eax, eax
	mov	ax, ss	# adjust ss:sp
	shl	eax, 4
	add	esp, eax
	mov	ax, SEL_flatDS
	mov	ss, ax
	mov	es, ax
	mov	ax, SEL_compatDS
	mov	ds, ax
1:

	push es
	mov	ax, SEL_vid_txt
	mov	es, ax
	mov ax, '2' | (13<<8)
	stosw
	pop es

	push	edx

#xor edi,edi
	mov	[screen_pos], edi
	mov	[screen_sel], word ptr SEL_vid_txt
	mov	[screen_color], byte ptr 7

	push es
	mov	ax, SEL_vid_txt
	mov	es, ax
	mov ax, '3' | (13<<8)
	stosw
	pop es


	call	screen_buf_init
	call newline

	.if DEBUG_PM
		OK
		I "Loading IDT"
	.endif
	call	init_idt

	.if DEBUG_PM
		OK
	.endif

	PIC_SET_MASK 0xffff & ~(1<<IRQ_CASCADE)
	call	keyboard_hook_isr
	call	pit_hook_isr

	# load Task Register

	.if DEBUG_PM > 2
		PRINTc 8 "  Load Task Register"
	.endif
	mov	ax, SEL_tss
	ltr	ax

	.if DEBUG_PM > 2
		OK
	.endif

	########################
	COLOR 13; PRINT "TEST!";
#	999:hlt; jmp 999b # so we can read the irq stuff
	########################
	INTERRUPTS_ON
	# possible crash: timer interrupt [ IRQ_BASE(0x20) + 0]

	.if DEBUG_PM > 2
		COLOR 8
		PRINT	"  Return address: "
		mov	edx, [esp]
		call	printhex8
		call	newline
	.endif

	# if flat mode is requested, set ds to flat. Data references,
	# unless relocated to reflect the memory address, wont work.
	cmp	[bkp_pm_mode], word ptr 0
	jnz	0f
	mov	ax, SEL_flatDS
	mov	ds, ax
0:
	.if DEBUG_PM > 2
		call	cmd_print_gdt
		mov	edx, esp
		call	printhex8
		call	printspace
		mov	edx, [esp]
		call	printhex8
	.endif

	call	update_memory_map$

	# NOTE: at current, there is a linker issue, which causes a failure here
	# when there is a specific number of instructions causing some section
	# overflow.
	#
	# Hence the check:
	mov	edx, [esp]
	cmp	edx, offset KERNEL_CODE32_END
	jae	9f
	sub	edx, [reloc$]
	js	9f

	ret	# at this point interrupts are on, standard handlers installed.

9:
	printc 0xf4, "WARNING: kernel entry point corrupt: "
	mov	eax, edx
	mov	edx, [esp]
	call	printhex8
	print ", kernel_base + "
	mov	edx, eax
	call	printhex8
	call	newline
	printc 0xf0, "kernel code32 end: "
	mov	edx, offset KERNEL_CODE32_END
	call	printhex8
	call	newline
	call	more
	mov	[esp], dword ptr offset kmain
	ret



###################
update_memory_map$:
	push_	edi edx ebx

	# register the kernel
	mov	edx, [kernel_load_start_flat]
	mov	ebx, [kernel_load_end_flat]
	sub	ebx, edx
	mov	edi, MEMORY_MAP_TYPE_KERNEL
	call	memory_map_update_region

	# register the memory region after the kernel as setup by realmode.s.
	# stack_top - kernel_end + database:
	mov	edx, [kernel_load_end_flat]
	mov	ebx, [kernel_stack_top]
	sub	ebx, edx
	mov	edi, MEMORY_MAP_TYPE_STACK
	call	memory_map_update_region

	pop_	ebx edx edi
	ret




##############################################################################
.text32
# Restores the realmode stack and uses the realmode return address on it.
# The pmode stack is discarded.
return_realmode:
	printc	11, "Returning to real-mode"

	INTERRUPTS_OFF

	ljmp	SEL_realmodeCS, offset 0f
.text16
#.code16
0:	# pmode 16 bit realmode-compatible code selector

	# prepare return address
	pushw	[bkp_reg_cs]
	mov	ax, [codeoffset]
	add	ax, offset rm_ret_entry$
	push	ax

	# enter realmode
	mov	eax, cr0
	and	eax, ~0x80000001 # 8: paging; 1: pmode
	mov	cr0, eax

	# PLACE NO CODE HERE - serialize CPU to reload code segment

	retf
.text16
rm_ret_entry$:

	# restore ds, es, ss
	mov	ds, [bkp_reg_ds]
	mov	es, [bkp_reg_es]
	mov	ss, [bkp_reg_ss]
	movzx	esp, word ptr [bkp_reg_sp]

	.if DEBUG_PM > 1
		rmI "Back in realmode"
	.endif

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
#		println_16 " - Press a key"
#		xor	ah, ah
#		int	0x16
	.endif

	mov	di, [screen_pos_16]

	retf









##############################################################################
.text32
# bp cannot be used as a parameter for the realmode function.
#
# usage:
# .code32
# push dword ptr offset realmode_function # unrelocated
# call call_realmode
call_realmode:
	# save the pm stack for reenter_protected_mode
	mov	[bkp_pm_ss], ss
	mov	[bkp_pm_esp], esp

	mov	eax, cr0
	mov	[bkp_pm_cr0], eax

	call	pic_save_mask32

	mov	dx, [esp + 4]


	# allocate stackspace for the argument:
	sub	word ptr [bkp_reg_sp], 4

	movzx	eax, word ptr [bkp_reg_ss]
	shl	eax, 4
	movzx	ecx, word ptr [bkp_reg_sp]
	add	eax, ecx	# eax is realmode stack address (flat).
	mov	cx, SEL_flatDS
	push	ds
	mov	ds, cx
	mov	[eax], dx
	pop	ds

	# reserve realmode stack space for the realmode return 0f
	sub	word ptr [bkp_reg_sp], 4

	.if 0
		print "PM: calling realmode function @ "
		call	printhex4
	.endif

	# using push here, as the 16 bit print macros don't
	# operate well in a .text32 .code16 section, due to the swapping
	# out to a data segment for string storage.
	push	dword ptr offset 0f
	jmp	real_mode_pm
.text16
0:
	push	bp
	mov	bp, sp
	call	[bp + 2]
	pop	bp

	push	word ptr offset 0f
	jmp	reenter_protected_mode_rm
.text32
0:
	# restore the realmode stack pointer
	add	word ptr [bkp_reg_sp], 8
	push	ds
	pop	es

	call	pic_restore_mask32
	mov	eax, [bkp_pm_cr0]
	mov	cr0, eax	# restore paging flag
	ret	4


#######################################################
.text32
# This section will work when this method is called from pmode,
# having a pmode return address on the stack which will be converted to
# realmode address.


# stack contains relocated (runtime) protected mode offset of realmode code.
#
# Example usage:
#
# .code32
# call	real_mode_pm
# .code16
# ..next instruction
.code32
real_mode_pm:
	# convert 16 bit offset to pmode offset
	pop	edx
	GDT_GET_BASE eax, cs
	add	edx, eax
	sub	edx, [realsegflat]
	GDT_GET_BASE eax, SEL_compatCS
	sub	edx, eax
	shr	eax, 4
	push	ax
	push	dx	# assert edx >> 16 == 0
	jmp	0f

# stack contains [realsegflat] relative pmode offset for realmode function.
# (this means 'push offset realmode_function', which doesnt take into account
# runtime relocation).
#
# Example usage:
#
# .code32
# push	dword ptr offset 0f
# jmp	real_mode_pm
# .code16
# 0:
.code32
real_mode_pm_unr:
	mov	bx, SEL_compatDS
	mov	ds, bx

	pop	edx	# convert stack return address
	GDT_GET_BASE eax, cs	# add base of current selector to stack
	add	edx, eax
	GDT_GET_BASE eax, SEL_compatCS
	shr	eax, 4

	push	ax
	push	dx

0:
	# compat mode - realmode/pmode stacks differ. real_mode_rm will use the address on the
	# realmode stack, so we need to store it there.

	pop	edx

	movzx	eax, word ptr [bkp_reg_ss]
	shl	eax, 4
	movzx	ecx, word ptr [bkp_reg_sp]
	add	eax, ecx	# eax is realmode stack address (flat).
	mov	cx, SEL_flatDS
	push	ds
	mov	ds, cx
	mov	[eax], edx
	pop	ds

0:

	.if DEBUG_PM > 2
		print " rm ret: "
		ror	edx, 16
		call	printhex4
		ror	edx, 16
		printchar ':'
		call	printhex4
		call printspace
	.endif

	.if DEBUG_KERNEL_REALMODE
		print " ss:sp "
		GDT_GET_BASE edx, ss
		call	printhex8
		printchar_ ':'
		mov	edx, esp
		call	printhex8
		call	newline
	.endif

# This will return to real-mode, assuming the stack points to a real-mode
# address, possibly the address from which protected_mode was called.
# UPDATE: it will restore the realmode stack (as the pmode stack is different with ax=1),
# and use the realmode return address from the old realmode stack. The pmode stack is discarded.
#.code32
.text32
real_mode_rm:

	INTERRUPTS_OFF

	ljmp	SEL_realmodeCS, offset 0f
#.code16
.text16
0:	# pmode 16 bit realmode-compatible code selector

	.if DEBUG_PM > 2
		mov ax, SEL_vid_txt
		mov es, ax
		xor di, di
		mov ax, (0xf4<<8)|'!'
		stosw
	.endif

	# prepare return address
	pushw	[bkp_reg_cs]
	mov	ax, [codeoffset]
	add	ax, offset rm_entry
	push	ax

	# enter realmode
	mov	eax, cr0
	and	eax, 0x7ffffffe	# no paging, no pmode
	mov	cr0, eax

	# PLACE NO CODE HERE - serialize CPU to reload code segment

	retf

.text16
rm_entry:
	mov	ax, cs
	mov	ds, ax

	.if DEBUG_PM > 1
		rmI "Back in realmode!"
	.endif

	# restore ds, es, ss
	mov	ds, [bkp_reg_ds]
	mov	es, [bkp_reg_es]
	mov	ss, [bkp_reg_ss]
	movzx	esp, word ptr [bkp_reg_sp]

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
		print_16 "("
		mov dx, [bkp_reg_sp]
		call printhex_16
		print_16 ")"

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
		println_16 " - Press a key"
		xor	ah, ah
		int	0x16
	.endif

	.if DEBUG_PM
		call	newline_16
	.endif

	mov	di, [screen_pos_16]

	retf



#############################################################
.text16
# stack contains 16 bit realmode address of protected mode continuation code.
reenter_protected_mode_rm:
	push	cs
	pop	ds

	xor	edx, edx
	pop	dx
	# assuming realmode cs is pmode cs sel base, edx is now unrelocated
	# pmode address, which is what code below expects.
	# proper code would:
	#	xor	eax, eax
	#	mov	ax, cs
	#	shl	eax, 4
	#	add	edx, eax	# edx is flat linear address
	#	GDT_GET_BASE eax, SEL_...
	#	sub	edx, eax
	push	edx


	.if DEBUG_PM > 2
		printc_16 11, "Re Entering Protected Mode"
#		xor	ax, ax
#		int	0x16
	.endif

	INTERRUPTS_OFF

	.if DEBUG_PM > 1
		rmI "Remapping PIC"
	.endif

	mov	ax, (( IRQ_BASE + 8 )<<8) | IRQ_BASE	# 0x2820
	call	pic_init16

	.if DEBUG_PM > 1
		rmOK
	.endif


	# flush prefetch queue, replace cs.
	# since the object is not relocated to a specific address,
	# we need to correct. We don't prefer to use a static value like 7c00.
	# Either self-modifing code - needs extra jumps to clear prefetch queue
	# - or use a register.

	# prepare the far jump instruction

	.if DEBUG_PM > 1
		rmI "Preparing Entry Point: "
	.endif

	mov	eax, offset pmode_entry2$ # relocation
	mov	cx, SEL_compatCS

	cmp	[bkp_pm_mode], word ptr 0
	jnz	0f
	add	eax, [reloc$]
	mov	cx, SEL_flatCS

	.if DEBUG_PM > 1
		PRINTc_16 0x01, "Flat"
		jmp	1f
	0:	PRINTc_16 0x03, "Realmode Compatible"
	1:	rmI2	" Address mode"
		rmOK
	.else
0:
	.endif

	mov	[pm_entry2 + 4], cx # word ptr SEL_flatCS
	mov	[pm_entry2], eax

	.if DEBUG_PM > 2
		rmI2 "  - Address: "

		COLOR_16 0x09
		mov	dx, cx
		call	printhex_16
		mov	edx, eax
		call	printhex8_16

		rmI2 " flat segment offset: "
		COLOR_16 0x0a
		mov	edx, [realsegflat]
		call	printhex8_16
		call	newline_16
	.endif

	.if DEBUG_PM > 1
		rmI "Entering "
	.endif
	mov	edi, [screen_pos_16]

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
	pm_entry2:.long 0
	.word SEL_flatCS
.text32
pmode_entry2$:

	# print Pmode
	mov	ax, SEL_vid_txt
	mov	es, ax
	.if DEBUG_PM > 1
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
	.endif

	# adjust return address
	pop	edx	# unrelocated pmode return address
	xor	ax, ax
	mov	fs, ax
	mov	gs, ax

	cmp	[bkp_pm_mode], word ptr 0
	jz	0f
	mov	ax, SEL_compatDS # realmodeDS
	mov	ds, ax
	mov	es, ax
	.if 0
	mov	ax, SEL_compatSS # realmodeSS
	mov	ss, ax
	.else
	mov	ss, [bkp_pm_ss]
	mov	esp, [bkp_pm_esp]
	.endif
	jmp	1f
0:
	# XXX
	add	edx, [reloc$]	# flat cs, so adjust return addr
	xor	eax, eax
	mov	ax, ss	# adjust ss:sp
	shl	eax, 4
	add	esp, eax
	mov	ax, SEL_flatDS
	mov	ss, ax
	mov	ax, SEL_compatDS 
	mov	ds, ax
	mov	es, ax
1:

	push	edx

	mov	[screen_pos], edi

	.if DEBUG_PM > 1
		OK
		I "Loading IDT"
	.endif

	#call	init_idt
	lidt	[pm_idtr]

	.if DEBUG_PM > 1
		OK
	.endif

	PIC_SET_MASK 0xffff & ~(1<<IRQ_CASCADE)

	call	keyboard_hook_isr
	call	pit_hook_isr

	INTERRUPTS_ON

	# load Task Register

	.if DEBUG_PM > 2
		PRINTc 8 "  Load Task Register"
	.endif

	#mov	ax, SEL_tss
	#ltr	ax


	.if DEBUG_PM > 2
		OK
		PRINTc 8, "  Return Address(again): "
		mov	edx, [esp]
		call	printhex8
		call	newline
	.endif


	# if flat mode is requested, set ds to flat. Data references,
	# unless relocated to reflect the memory address, wont work.
	cmp	[bkp_pm_mode], word ptr 0
	jnz	0f
	mov	ax, SEL_flatDS
	mov	ds, ax

0:

	.if DEBUG_PM > 3
		call	cmd_print_gdt
		print "stack pre-return: "
		mov	edx, esp
		call	printhex8
		print " offs "
		mov	edx, [esp]
		call	printhex8
#		print " sel "
#		mov	dx, [esp+4]
#		call	printhex4
#		print " base "
#		mov	eax, [esp + 4]
#		GDT_GET_BASE edx, eax
#		call	printhex8

		xor	ax, ax
		call	keyboard
	.endif

	ret	# at this point interrupts are on, standard handlers installed.

