.data

alert_flags:	.long 0
alert_messages:	.long 0
alert_screen_update:	.long 0

alert_debug_counter: .long 0

DECLARE_CLASS_BEGIN message, OBJ
# field: .long 0
DECLARE_CLASS_METHOD message_api_append, msg_append_impl$
DECLARE_CLASS_END message
.text


beep:	# TODO: use RTC/speaker (see old dos code) or play wav
	ret

setfeedback$:
	print "setfeedback: "
	call	println
	ret

clearfeedback$:
	ret

drawbuffer$:
	pushad

	pushd	[screen_update]
	mov	[screen_update], dword ptr 0

	PUSH_SCREENPOS 0

	# clear top bar
	PRINT_START
	mov	ax, 0xf020
	mov	ecx, 80
	rep	stosw
	PRINT_END

	POP_SCREENPOS
	PUSH_SCREENPOS 0

	pushcolor 0xf0

	print "alert test! "
	incd	[alert_debug_counter]
	mov	edx, [alert_debug_counter]
	call	printdec32

	# TCP synflood printing:
	cmpd	[tcp_synflood_dropcount], 0
	jz	1f
	mov	edx, [clock]
	sub	edx, [tcp_synflood_lastdrop]
	cmp	edx, 1000 * 10	# last 10 seconds
	jae	1f
	color 0x4f
	print " SYNFLOOD: "
	mov	edx, [tcp_synflood_dropcount]
	call	printdec32
1:

	popcolor
	POP_SCREENPOS

	popd	[screen_update]

	popad
	ret

flushbuffer$:
	ret

msg_append_impl$:
	println "msg_append"
	ret

# BEGIN

#[note|https://github.com/neonics/qure/commit/4ee2deb]
alert_init: 
	cmpd	[alert_screen_update], 0; jnz 9f	# protect [screen_update]
	mov	eax, [screen_update]
	mov	[alert_screen_update], eax
	mov	[screen_update], dword ptr offset alert_show
9:	ret

alert_message:
	btd	[alert_flags], 1
	jnz	append$
	call	alert_takeover
append$:
	invokevirtual message append [alert_messages]
	jmp	alert_main

alert_show:
	pushad
	call	[alert_screen_update]	# original update handler
	call	drawbuffer$
	call	flushbuffer$
	popad
	ret


alert_release:
	mov	eax, [alert_screen_update]
	mov	[screen_update], eax
	ret

alert_beep:
	call	beep
	load_txt "press <ESC> to continue"
	call	setfeedback$

alert_main:
	call	alert_show
	mov	ah, KB_GET
	call	keyboard
	call	clearfeedback$
	cmp	ax, K_ESC
	jz	alert_beep

alert_takeover:
	println "alert_takeover"
	ret

alert_test:
	mov	eax, offset class_message
	call	class_newinstance
	mov	[alert_messages], eax
	call	alert_init
	DEBUG_DWORD eax
	println "instantiated messages"
	ret



