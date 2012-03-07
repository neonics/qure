.intel_syntax noprefix

# PS/2:
KB_FLAG_OBF	= 0b00000001	# Output buffer full
KB_FLAG_IBF	= 0b00000010	# Output buffer full
KB_FLAG_SYS	= 0b00000100	# POST: 0: power-on reset; 1: BAT code, powered
KB_FLAG_A2	= 0b00001000	#

KB_FLAG_INH	= 0b00010000	# Communication inhibited
KB_FLAG_MOBF	= 0b00100000	# PS2: OBF for mouse; AT: TxTO (timeout)
KB_FLAG_TO	= 0b01000000	# PS2: Timeout; AT: RxTO
KB_FLAG_PERR	= 0b10000000	# Parity Error


.data
old_kb_isr: .word 0, 0
.text
.code16
hook_keyboard_isr16:
	push	fs
	push	eax
	cli
	push	0
	pop	fs
	mov	eax, fs:[9 * 4]
	mov	[old_kb_isr], eax
	mov	fs:[ 9 * 4], word ptr offset isr_keyboard16
	mov	fs:[ 9 * 4 + 2], cs
	pop	eax
	pop	fs
	sti
	ret

restore_keyboard_isr16:
	cli
	push	fs
	push	eax
	push	0
	pop	fs
	mov	eax, [old_kb_isr]
	mov	fs:[ 9 * 4], eax
	pop	eax
	pop	fs
	sti
	ret

.data
scr_o: .word 7 * 160
last_key: .word 0
.text
.code16
isr_keyboard16:
	push	es
	push	di
	push	ax

	push	0xb800
	pop	es
	mov	di, [scr_o]
	mov	ah, 0x90
0:	in	al, 0x64
	and	al, 1
	jz	0b

	in	al, 0x60

	mov	dl, al
	call	printhex2
	mov	[scr_o], di

	shl	dx, 8
	mov	[last_key], dx

	mov	al, 0x20 # send EOI
	out	0x20, al
	pop	ax
	pop	di
	pop	es

	iret
