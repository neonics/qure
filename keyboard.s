.intel_syntax noprefix

.text

# Remember, IRQ is hardware interrupt, and is mapped to INT by the PIC.
IRQ_KEYBOARD = 1


.code16
hook_keyboard_isr16:
	cli
	push	0
	pop	fs
	mov	fs:[ 9 * 4], word ptr offset isr_keyboard
	mov	fs:[ 9 * 4 + 2], cs
	sti
	ret

.code32
hook_keyboard_isr32:
	mov	al, [pic_ivt_offset]
	add	al, IRQ_KEYBOARD
	mov	cx, SEL_compatCS
	mov	ebx, offset isr_keyboard
	call	hook_isr
	ret


.data
KB_BUF_SIZE = 32
# circular buffer, hardware-software thread safe due to separate read/write
# variables. The read offset is however not software-software thread safe.
keyboard_buffer:	.space KB_BUF_SIZE
keyboard_buffer_ro:	.long 0	# write offset
keyboard_buffer_wo:	.long 0 # read offset
kb_count$: .long 0
.text

isr_keyboard:	# assume CLI
	push	ax
	push	es
	push	edx
	push	edi

	SCREEN_INIT
	SCREEN_OFFS 0, 3
	push	ds
	mov	ax, SEL_compatDS
	mov	ds, ax
	inc	dword ptr [kb_count$]
	mov	edx, [kb_count$]
	mov	ah, 0xfa
	call	printhex8_32
	pop	ds


	mov	di, SEL_compatDS
	mov	es, di
	mov	edi, [keyboard_buffer_wo]

######## calculate max offset - either KB_BUF_SIZE or ro-1
	mov	edx, [keyboard_buffer_ro]
	dec	edx
	jnl	1f
	add	edx, KB_BUF_SIZE

1:	cmp	edx, edi
	jl	0f
	mov	edx, KB_BUF_SIZE

######## read the data
0:	in	al, 0x64
	test	al, 2	# IBF - input buffer full
	jz	0f	# no data

	in	al, 0x60
	stosb

	in	al, 0x61	# disable/enable keyboard at PPI
	or	al, 0x80
	out	0x61, al
	and	al, 0x7f
	out	0x61, al
######## handle buffer full/wraparound/
	cmp	edi, edx
	jb	0b
	cmp	edx, KB_BUF_SIZE -1
	jz	0f
	xor	edi, edi
	jmp	1b	# loop back

0: 	mov	[keyboard_buffer_wo], edi
########
	mov	al, IRQ_KEYBOARD
	call	pic_send_eoi
	# out 0x20, 0x20
	pop	edi
	pop	es
	pop	edx
	pop	eax
	iret


##########################################################################
### Public API 
##########################################################################

# Potential multitasking problems:
# Writing to IO port. The last port written/read needs to be synchronous,
# so when an IRQ occurs, or when another task reads/writes from the
# IO port, this corrupts communication.
# IRQ's can be disabled by cli; for port access, this needs to be protected
# using CPL0 and a taskgate that only runs on one CPU at a time. Trusting
# on the task switching's recursion preventing should then provide a means
# to have only one task that deals with a specific IO port.
keyboard:
	push	ds
	push	esi
	mov	si, SEL_compatDS
	mov	ds, si

	or	ah, ah
	jz	k_get$
	cmp	ah, 1
	jz	k_peek$
	cmp	ah, 2
	jz	k_getshift$
	cmp	ah, 3
	jz	k_setspeed$
0:	pop	esi
	pop	ds
	ret

#Int 16/AH=09h - KEYBOARD - GET KEYBOARD FUNCTIONALITY
#Int 16/AH=0Ah - KEYBOARD - GET KEYBOARD ID
#Int 16/AH=10h - KEYBOARD - GET ENHANCED KEYSTROKE (enhanced kbd support only)
#Int 16/AH=11h - KEYBOARD - CHECK FOR ENHANCED KEYSTROKE (enh kbd support only)
#Int 16/AH=12h - KEYBOARD - GET EXTENDED SHIFT STATES (enh kbd support only)

k_get$:	
	mov	esi, [keyboard_buffer_ro]
1:	cmp	esi, [keyboard_buffer_wo]
	jnz	1f
	hlt		# wait for interrupt
	jmp	1b	# check again
1:	mov	ax, [keyboard_buffer + esi]
	add	esi, 2
	cmp	esi, KB_BUF_SIZE
	jl	1f
	sub	esi, KB_BUF_SIZE
1:	mov	[keyboard_buffer_ro], esi
	jmp	0b
k_peek$:
	mov	esi, [keyboard_buffer_ro]
	cmp	esi, [keyboard_buffer_wo]
	jz	0b
	mov	ax, [keyboard_buffer + esi]
	jmp	0b
k_getshift$:
	jmp	0b
k_setspeed$:
	jmp	0b


KB_GET		= 0
KB_PEEK		= 1
KB_GETSHIFT	= 2
KB_SETSPEED	= 3
int32_16h_keyboard:
	call	keyboard

	push	ebp		# update flags
	mov	ebp, esp
	push	eax
	pushfd
	pop	eax
	mov	[ebp + 6], eax
	pop	eax
	pop	ebp

	iret
