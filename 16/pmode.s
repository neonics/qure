.print "* 16/pmode.s"
.data16
backup_gdt_ptr: .word 0; .long 0
backup_idt_ptr: .word 0; .long 0

gdt_ptr:.word gdt_end - gdt -1
	.long gdt
gdt:	.long 0,0
	#.byte 0xff,0xff, 0,0,0, 0b10011010, 0b10001111, 0	# code
	#.byte 0xff,0xff, 0,0,0, 0b10010010, 0b11001111, 0	# data
s_code:	DEFGDT 0, 0xffffff, ACCESS_CODE, FLAGS_16#(FLAGS_16|FL_GR4kb)
s_data:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_16#32
s_stack:DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_16#32
s_flat:	DEFGDT 0, 0xffffff, ACCESS_DATA, FLAGS_32
s_vid:  DEFGDT 0xb8000, 0xffff, ACCESS_DATA, FLAGS_16
gdt_end:

SEL_code = 8
SEL_data = 16
SEL_stack= 24
SEL_flat = 32
SEL_vid = 40

#########
idt_ptr: .word idt_end - idt - 1
	.long idt

idt:
.rept 256
	.word 0	# lo 16 bits of offset
	.word 8
	.byte 0
	.byte 0b10000110 # ACC_PR(1<<7)| IDT_ACC_GATE_INT16(0b0110)
	.word 0	# high 16 bits of offset
.endr
idt_end:

.text16
pm_idt_table:
_I=0
.rept 256
	push	word ptr _I
	jmp	pm_isr
	_I = _I+1
.endr

pm_isr:
	push	ebp
	lea	ebp, [esp + 4]
	push	ds
	push	es
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi
	mov	eax, SEL_vid
	mov	es, eax
	mov	eax, SEL_data
	mov	ds, eax

	mov	edi, 160*5

	mov	ah, 0x0f
	print "interrupt "

	mov	dx, [ebp]
	call	printhex2

	print "stack "
	mov	dx, ss
	call	printhex
	mov	al, ':'
	mov	es:[edi-2],ax
	mov	edx, ebp
	call	printhex8
	call	newline

	mov	ecx, 8
	mov	esi, ebp
0:	mov	edx, esi
	call	printhex8
	mov	edx, ss:[esi]
	add	esi, 2
	call	printhex
	call	newline
	loop	0b

	movzx	eax, word ptr [ebp]
	mov	edx, 0b00100111110100000000
	bt	edx, eax
	mov	ah, 0x0f
	jnc	1f

	print	"ErrCode "
	mov	edx, [ebp+2]
	add	ebp, 4
	call	printhex8

1:
	print "cs "
	mov	edx, [ebp + 2]
	call	printhex8
	print "eip "
	mov	edx, [ebp + 2+4]
	call	printhex8
	print "flags "
	mov	edx, [ebp + 2+8]
	call	printhex8

	0: hlt; jmp 0b

	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	pop	es
	pop	ds
	pop	ebp
	add	sp, 2
	iret

.data16
backup_ds: .word 0
backup_es: .word 0
backup_ss: .word 0
.text16

enter_pmode:
	push	eax
	push	ecx
	push	edx
	push	esi
	###############################
	# enable A20 line
	in	al, 0x92 # a20
	test	al, 2
	jnz	1f
	or	al, 2
	out	0x92, al
1:

	cli
	# mask NMI
	in	al, 0x70
	or	al, 0x80
	out	0x70, al
	in	al, 0x71

	# mask all PIC signals
#	mov al, ~(1<<2) # IRQ_CASCADE
#	out 0x20+1, al
#	mov al, -1
#	out 0xa0+1, al
	###############################

	mov	[backup_ds], ds	# 0x1000
	mov	[backup_es], es	# 0x1000
	mov	[backup_ss], ss	# 0, at current

	sgdt	[backup_gdt_ptr]
	sidt	[backup_idt_ptr]

	mov	eax, cs
	shl	eax, 4
	GDT_STORE_SEG s_code

	mov	eax, ds
	shl	eax, 4
	GDT_STORE_SEG s_data

.ifdef BOOTLOADER
	add	eax, offset gdt
.else
mov ah,0xf1; print_16 "gdt offset:"
xor eax,eax
mov ax, offset gdt
add eax, offset .text
mov edx,eax;
call printhex8_16;
#0:hlt;jmp 0b
print_16 " sel"
mov dx, ds
call printhex_16
.endif
	mov	[gdt_ptr+2], eax
_MEH:
	lgdt	[gdt_ptr]

	# initialize the idt
	mov	eax, cs
	shl	eax, 4
	add	eax, offset pm_idt_table#pm_isr
	mov	si, offset idt
	mov	cx, 256
	mov	edx, eax
	shr	edx, 16
0:	mov	[si + 0], ax
	mov	[si + 8-2], dx
	add	ax, 5
	adc	dx, 0
	add	si, 8
	loop	0b

.ifdef BOOTLOADER
	mov	eax, ds
	shl	eax, 4
	add	eax, offset idt
.else
_HEY:
	xor	eax, eax
	mov	eax, offset idt
.endif
	mov	[idt_ptr+2], eax


	lidt	[idt_ptr]

	mov	ax, SEL_data
	mov	ds, ax
	mov	es, ax
	xor	ax, ax
	mov	fs, ax
	mov	gs, ax

	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

	jmp 1f
1:	# 16bit pmode

	.if 1
		push	edi
		mov ax, SEL_flat
		mov es, ax

		mov edi, 0xb8000
		mov ah, 0xf
		mov al, 'P'
		mov es:[edi], ax
		pop	edi
	.endif

	# set the descriptor cache limit to 4Gb
	mov	eax, SEL_data
	mov	ds, eax
	mov	es, eax

	mov	ax, SEL_stack
	mov	ss, ax

	# set vid
	mov	ax, SEL_vid
	mov	es, ax
#mov ah, 0xd0
#print_16 "PMode"
		.ifndef BOOTLOADER
		.print "BREAKPOINT"
		#0:hlt;jmp 0b
		.else
		.print "skip bp"
		.endif


	pop	esi
	pop	edx
	pop	ecx
	pop	eax
	ret


enter_realmode:
	push	eax
	mov	eax, cr0
	and	al, ~1
	mov	cr0, eax
	jmp 1f
	1:	

	mov	ds, cs:[backup_ds]
	mov	es, [backup_es]
	mov	ss, [backup_ss]
	xor	ax, ax
	mov	fs, ax
	mov	gs, ax

	lgdt	[backup_gdt_ptr]
	lidt	[backup_idt_ptr]

	in al, 0x80
	and al, 0xfe
	out 0x70, al
	in al, 0x71

mov ah, 0xd0
print_16 "Realmode"
	pop	eax
	sti
	ret

unreal_mode:
	push	eax
	push	ecx
	push	edx
	push	esi
	push	edi

	call	enter_pmode
mov edx, edi
xor edi,edi
call printhex8
	mov	ah, 0xe0
	print "in protected mode"

	call	enter_realmode
	mov ah, 0xe0
	print "in realmode"

	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	eax

	ret

# writes an 'U' using 0000:000b8000
test_unreal:
	push	edi
	push	eax
	push	es

	xor	dx, dx
	mov	es, dx
	mov	edi, 0xb8000
	mov	ax, 11<<8 | 'U'
	mov	es:[edi], ax

	pop	es
	pop	eax
	pop	edi
	call	waitkey	# this also prints
	ret
