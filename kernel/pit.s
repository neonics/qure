######################################
# PIT - Programmable Interrupt Timer 
######################################
.intel_syntax noprefix


.data
clock: .long 0
.text
.code32

pit_hook_isr:
	mov	cx, SEL_compatCS
	movzx	eax, byte ptr [pic_ivt_offset]
	# add eax, IRQ_TIMER
	mov	ebx, offset pit_isr
	call	hook_isr
pit_enable:
	PIC_ENABLE_IRQ IRQ_TIMER
	ret

pit_disable:
	PIC_DISABLE_IRQ IRQ_TIMER
	ret

pit_isr:
	push	es
	push	ds
	push	ax
	push	dx
	# TODO: interface with PIT port 0x43 (func 0x73 = read channel 0)

	mov	ah, 0x73

	xor	al, al		# read channel 0 (bits 6,7 = channel)
	out	0x43, al	# PIT port

	mov	dx, SEL_compatDS	# required for PRINT_START, PRINT
	mov	ds, dx

	in	al, 0x40
	mov	dl, al
	in	al, 0x40
	mov	dh, al

.if 1
	cli

	PRINT_START 8
	mov	ax, (8<<8) | '('
	stosw

	push	esi
	LOAD_TXT "TIMER "
	mov	ah, 10
	call	__print
	pop	esi
	call	__printhex4

	mov	ax, (8<<8)|','
	stosw

	inc	dword ptr [clock]
	mov	dx, [clock]
	call	__printhex4

	mov	al, ')'
	stosw
	PRINT_END 1

	sti
.endif
	
	mov	al, 0x20
	out	0x20, al
	pop	dx
	pop	ax
	pop	ds
	pop	es
	iret

