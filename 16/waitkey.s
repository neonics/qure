.include "../kernel/keycodes.s"

waitkey:
	.data
	msg_press_key$: .asciz "Press a key to continue..."
	.text
	push	si
	push	dx

	mov	si, offset msg_press_key$
	call	print_16

	push	ax
	xor	ah, ah
	int	0x16
	pop	dx
	xchg	ax, dx	# restore ah
	call	printhex_16
	call	newline_16
	mov	ax, dx
	pop	dx
	pop	si
	ret

