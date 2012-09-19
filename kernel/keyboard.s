##############################################################################
# i8042 Keyboard Controller - PS/2
#
# References:
#  http://www.computer-engineering.org/ps2keyboard/
#  http://osdever.net/documents/kbd.php?the_id=14 [RBIL PORTS.A]
.intel_syntax noprefix

# Keyboard registers:
# * one byte input buffer	: R 0x60
# * one byte output buffer	: W 0x60
# * one byte status register	: R 0x64
# * one byte control register	: W 0x64, 0x60 (MODE_WRITE)
# 0x60: read = input, write = output
# 0x64: read = status, write = command (use MODE_WRITE to access control reg)
KB_IO_DATA	= 0x60	# R: input buffer, W: output buffer
KB_IO_CMD	= 0x64	# W: 7 control flags; parameter on port 0x60
KB_IO_STATUS	= 0x64	# R: 8 status flags

KB_IO_CONTROL	= 0x61	# pc speaker / direct access to control register (see KB_MODE)
# control register layout:
# bit 0: pc speaker
# bit 7: character has been read.

# Keyboard status: port 0x60
# PS/2:
KB_STATUS_OBF	= 0b00000001	# Output buffer full
KB_STATUS_IBF	= 0b00000010	# Input buffer full
KB_STATUS_SYS	= 0b00000100	# POST: 0: power-on reset; 1: BAT code, powered
KB_STATUS_A2	= 0b00001000	# address line A2; last written: 0=0x60, 1=0x64
KB_STATUS_INH	= 0b00010000	# Communication inhibited: 0=yes 
KB_STATUS_MOBF	= 0b00100000	# PS2: OBF for mouse; AT: TxTO (timeout)
KB_STATUS_TO	= 0b01000000	# PS2: general (TX/RX) Timeout; AT: RxTO
KB_STATUS_PERR	= 0b10000000	# Parity Error
# AT:
KB_STATUS_TXTO	= 0b00100000	# transmit timeout
KB_STATUS_RXTO	= 0b01000000	# receive timeout

########################################################################
# i8254 Keyboard Controller Commands - port 0x64 (KB_IO_CMD)
#
# The keyboard controller (i8254) has 3 ports: in, out and test.
#
KB_C_CMD_MODE_READ	= 0x20	# read command byte (see KB_MODE_*)
	# 0x20-0x2f/3f: read byte at address (low 5 bits). addr0=command byte
KB_C_CMD_MODE_WRITE	= 0x60	# write command byte (see KB_MODE_*)
	# 0x60-0x7f: write byte at address (low 5 bits).
KB_C_CMD_WRITE_OUTPUT	= 0x90	# 0x90-0x9f: write low nybble to output port
KB_C_CMD_FIRMWARE_VERSION=0xa1
KB_C_CMD_PASSWORD_GET	= 0xa4	# 0xfa = password exists, 0xf1 = no password
KB_C_CMD_PASSWORD_SET	= 0xa5	# send password as zero-terminated scancodes
KB_C_CMD_PASSWORD_CHECK	= 0xa6	# compares keyboard input with password
KB_C_CMD_MOUSE_DISABLE	= 0xa7	# disable PS/2 mouse interface
KB_C_CMD_MOUSE_ENABLE	= 0xa8	# disable PS/2 mouse interface
KB_C_CMD_MOUSE_TEST	= 0xa9	# 0=ok; stuck lo/hi: 1/2=clock; 3/4=data
KB_C_CMD_SELF_TEST	= 0xaa	# controller self test: 0x55 = ok
KB_C_CMD_KBI_TEST	= 0xab	# keyboard interface test
KB_C_CMD_KBI_DISABLE	= 0xad	# keyboard interface enable
KB_C_CMD_KBI_ENABLE	= 0xae	# keyboard interface disable
KB_C_CMD_VERSION_GET	= 0xaf	# get version
KB_C_CMD_INPORT_READ	= 0xc0	# read input port
KB_C_CMD_INPORT_CPY_LSN	= 0xc1	# copy input port low nybble to status reg
KB_C_CMD_INPORT_CPY_MSN	= 0xc2	# copy input port high nybble to status reg
KB_C_CMD_OUTPORT_READ	= 0xd0
KB_C_CMD_OUTPORT_WRITE	= 0xd1
KB_C_CMD_KBUF_WRITE	= 0xd2	# write keyboard buffer
KB_C_CMD_MBUF_WRITE	= 0xd3	# write mouse buffer
KB_C_CMD_MDEV_WRITE	= 0xd4	# write mouse device
KB_C_CMD_TPORT_READ	= 0xe0	# read test port
KB_C_CMD_OPORT_PULSE	= 0xf0	# 0xf0-0xf9: pulses lo nybble onto output port

###############
# Keyboard command/mode bits: KB_C_CMD_MODE_(READ|WRITE) (0x20, 0x60)
#
# AT:	x | XLAT |  PC | EN | OVR | SYS |  x   | INT
# PS/2:	x | XLAT | EN2 | EN |  x  | SYS | INT2 | INT
KB_MODE_INT		= 0b00000001	# irq 1 (input buffer full) enable
KB_MODE_MOUSE_INT	= 0b00000010	# irq 12 (mouse) enable
KB_MODE_SYS		= 0b00000100	# 0: perform POST self test; 1: BAT rx
#
KB_MODE_DISABLE_KBD	= 0b00010000	# 0 = enabled, 1 = disable kb interface
KB_MODE_DISABLE_MOUSE	= 0b00100000
KB_MODE_XLAT		= 0b01000000	# 1 = enable translation to set 1
#
#KB_MODE_NO_KEYLOCK	= 0b00001000
#KB_MODE_KCC		= 0b01000000
#KB_MODE_RFU		= 0b10000000


#########################################
# keyboard commands: port 0x60
KB_CMD_RESET			= 0xff
KB_CMD_RESEND			= 0xfe
KB_CMD_SET_KEY_MAKE		= 0xfd	# disable brk/repeat for specific keys
KB_CMD_SET_KEY_MAKE_BREAK	= 0xfc	# disables typematic repeat
KB_CMD_SET_KEY_MAKE_REPT	= 0xfb	# disables break codes
KB_CMD_SET_ALL_MAKE_BREAK_REPT	= 0xfa	# sets all keys to default (mk/brk/rept)
KB_CMD_SET_ALL_MAKE		= 0xf9	# sets all keys to default (mk/brk/rept)
KB_CMD_SET_ALL_MAKE_BREAK	= 0xf8	# sets all keys to default (mk/brk/rept)
KB_CMD_SET_ALL_REPT		= 0xf7	# sets all keys to default (mk/brk/rept)
KB_CMD_SET_DEFAULT		= 0xf6	# rate (10.9/500), mk/brk/rept, set 2
KB_CMD_DISABLE			= 0xf5	# stop scan, set_default
KB_CMD_ENABLE			= 0xf4	# re-enable after disable
KB_CMD_SET_RATE_DELAY		= 0xf3	# set rate[4:0]/delay[6:5]
# Rate: 0x00..0x1f:
# 30.0 26.7 24.0 21.8 20.7 18.5 17.1 16.0 15.0 13.3 12.0 10.9 10.0 9.2 8.6 8.0
#  7.5  6.7  6.0  5.5  5.0  4.6  4.3  4.0  3.7  3.3  3.0  2.7  2.5 2.3 2.1 2.0
# Delay: 0b00..0b11: .25 .50 .75 1.0
KB_CMD_READ_ID			= 0xf2	# response: ACK, id [i.e.0xab 0x83]
# 0xf1 ?
KB_CMD_SET_SCAN_CODE_SET	= 0xf0	# rx ACK; tx 1..3: rx ACK; tx 0: rx cur.
	# 0: request current scancode set
	# 1, 2, 3: set scancode set
KB_CMD_ECHO			= 0xee	# ECHO or RESEND
KB_CMD_SET_LEDS			= 0xed	# arg: 0b111: caps,num,scroll lock

KB_LED_SCROLL_LOCK	= 0b001
KB_LED_NUM_LOCK		= 0b010
KB_LED_CAPS_LOCK	= 0b100


KB_RESPONSE_IBO_ERR	= 0x00	# key detection error / internal buffer overrun
KB_RESPONSE_PU		= 0xaa	# self-test passed / keyboard power up
KB_RESPONSE_ECHO	= 0xee	# response to ECHO
KB_RESPONSE_ACK		= 0xfa
KB_RESPONSE_FAIL1	= 0xfc	# self test failed after power up/RESET
KB_RESPONSE_FAIL2	= 0xfd	# self test failed after power up/RESET
KB_RESPONSE_RESEND	= 0xfe	# keyboard asks controller to repeat last cmd
KB_RESPONSE_IBO_ERR2	= 0xff	# key detection error /internal buffer overrun

# control keys
CK_LEFT_SHIFT		= 0b000001
CK_LEFT_ALT		= 0b000010
CK_LEFT_CTRL		= 0b000100
CK_RIGHT_SHIFT		= 0b001000
CK_RIGHT_ALT		= 0b010000
CK_RIGHT_CTRL		= 0b100000

.include "keycodes.s"

.data # XXX .text32 to keep in realmode access
old_kb_isr: .word 0, 0
.text32
scr_o: .word 7 * 160
.text32
.code32
isr_keyboard:
	push	ds
	push	es
	push	edi
	push	eax
	push	edx

	mov	ax, SEL_compatDS
	mov	ds, ax

	call	buf_avail
	jle	2f

	# debug
	mov	ax, SEL_vid_txt
	mov	es, ax
	xor	edi, edi
	mov	di, [scr_o]

	mov	ah, 0x90
#0:	in	al, 0x64
#	and	al, 1
#	jz	0b

	in	al, KB_IO_DATA

	######################################################################
	# check for protocol scancodes (set 2)
	#
	# 0xe0: extended key
	# 0xf0: break code
	# otherwise, 0x80 indicates break

0:	cmp	al, 0xe0	# escape code
	jne	0f

	# signal ready to read next byte without sending EOI
	# NOTE: this code is obsolete, for old (AT) systems.
	in	al, KB_IO_CONTROL
	or	al, 0x80
	out	KB_IO_CONTROL, al
	and	al, 0x7f
	out	KB_IO_CONTROL, al

	# read next byte

	in	al, KB_IO_DATA

	############################################################
	cmp	al, 0xf0	# some break codes are e0 f0 MAKE
	jne	0f
	# signal ready to read next byte without sending EOI
	in	al, KB_IO_CONTROL
	or	al, 0x80
	out	KB_IO_CONTROL, al
	and	al, 0x7f
	out	KB_IO_CONTROL, al

	# read next byte

	in	al, KB_IO_DATA
	or	al, 0x80	# turn it into a regular break code
	############################################################

0:	cmp	al, 0xe1	# key make/break on make, nothing on break
	jne	0f
0:	cmp	al, 0xe2	# logitech integrated mouse
	jne	0f
0:	cmp	al, 0x00	# keyboard error
	jne	0f
0:	cmp	al, 0xaa	# BAT (basic assurance test) OK
	jne	0f
0:	cmp	al, 0xee	# echo result
	jne	0f
0:	cmp	al, 0xf1	# reply to 0xa4 - password not isntalled
	jne	0f
0:	cmp	al, 0xfa	# ACK
	jne	0f
0:	cmp	al, 0xfc	# BAT error / mouse error
	jne	0f
0:	cmp	al, 0xfd	# internal failure
	jne	0f
0:	cmp	al, 0xfe	# keyboard ACK fail, resend
	jne	0f
0:	cmp	al, 0xff	# keyboard error
	jne	0f
0:
	######################################################################

	# split make/break code
	mov	ah, al	# invert break code (0x80) to 1 on make
	not	ah
	shr	ah, 7

	and	al, 0x7f	# al = key

	.data SECTION_DATA_BSS
		keys_pressed: .space 128
		kb_shift: .byte 0
		kb_caps: .byte 0
	.data
		keymap:
		.byte 0, 0 	# 00: error code
		.byte 0x1b, 1;	# 01: escape	BIOS: 0x011b

		.byte '1', '!' 	# 02
		.byte '2', '@'	# 03
		.byte '3', '#'	# 04
		.byte '4', '$'	# 05
		.byte '5', '%'	# 06
		.byte '6', '^'	# 07
		.byte '7', '&'	# 08
		.byte '8', '*'	# 09
		.byte '9', '('	# 0a
		.byte '0', ')'	# 0b
		.byte '-', '_'	# 0c
		.byte '=', '+'	# 0d
		.byte 8, 8	# 0e backspace

		.byte '\t','\t' # 0f tab
		.byte 'q', 'Q'	# 10
		.byte 'w', 'W'	#
		.byte 'e', 'E'	#
		.byte 'r', 'R'	#
		.byte 't', 'T'	#
		.byte 'y', 'Y'	#
		.byte 'u', 'U'	#
		.byte 'i', 'I'	#
		.byte 'o', 'O'	#
		.byte 'p', 'P'	#
		.byte '[', '{'	#
		.byte ']', '}'	# 1b
		.byte 0x0d, 0x0d# 1c enter

		.byte 0, 0	# 1d Left Control
		.byte 'a', 'A'	# 1e
		.byte 's', 'S'	#
		.byte 'd', 'D'	#
		.byte 'f', 'F'	#
		.byte 'g', 'G'	#
		.byte 'h', 'H'	#
		.byte 'j', 'J'	#
		.byte 'k', 'K'	#
		.byte 'l', 'L'	#
		.byte ';', ':'	#
		.byte '\'', '"'	# 28

		.byte '`', '~'	# 29

		.byte 0, 0	# 2a Left Shift
		.byte '\\', '|'	# 2b
		.byte 'z', 'Z'	# 2c
		.byte 'x', 'X'	#
		.byte 'c', 'C'	#
		.byte 'v', 'V'	#
		.byte 'b', 'B'	#
		.byte 'n', 'N'	#
		.byte 'm', 'M'	#
		.byte ',', '<'	#
		.byte '.', '>'	#

				# preceeded by e0: grey ...
		.byte '/', '?'	# 35
		.byte 0, 0	# 36 Right Shift

		.byte '*', 0	# 37 Keypad * / PrtScrn
		.byte 0, 0	# 38 Left Alt
		.byte ' ', ' '	# 39 Space Bar
		.byte 0, 0	# 3a Caps Lock

		.byte 0,0	# 3b F1
		.byte 0,0	# 3c F2
		.byte 0,0	# 3d F3
		.byte 0,0	# 3e F4
		.byte 0,0	# 3f F5
		.byte 0,0	# 40 F6
		.byte 0,0	# 41 F7
		.byte 0,0	# 42 F8
		.byte 0,0	# 43 F9
		.byte 0,0	# 44 F10

		.byte 0,0	# 45 Num Lock
		.byte 0,0	# 46 Scroll Lock
		.byte 0,0	# 47 Keypad 7 / Home
		.byte 0,0	# 48 Keypad 8 / Up
		.byte 0,0	# 49 Keypad 9 / PgUp
		.byte 0,0	# 4a Keypad -
		.byte 0,0	# 4b Keypad 4 / Left
		.byte 0,0	# 4c Keypad 5
		.byte 0,0	# 4d Keypad 6 / Right
		.byte 0,0	# 4e Keypad +
		.byte 0,0	# 4f Keypad 1 / End
		.byte 0,0	# 50 Keypad 2 / Down
		.byte 0,0	# 51 Keypad 3 / PgDn
		.byte 0,0	# 52 Keypad 0 / Ins
		.byte 0,0	# 53 Keypad Del

		.byte 0,0	# 54 Alt-SysRq
		.byte 0,0	# 55 less common: F11/F12/PF1/FN
		.byte 0,0	# 56 unlabeled key left/right of left alt

		.byte 0,0	# 57 F11
		.byte 0,0	# 58 F12

				# preceeded by e0:
		.byte 0,0	# 59
		.byte 0,0	# 5a
		.byte 0,0	# 5b MS: left window
		.byte 0,0	# 5c MS: right window
		.byte 0,0	# 5d MS: menu
				# set 1 make/break
		.byte 0,0	# 5e MS: power
		.byte 0,0	# 5f MS: sleep
		.byte 0,0	# 60
		.byte 0,0	# 61
		.byte 0,0	# 62
		.byte 0,0	# 63 MS: wake


		# turbo mode scan codes: 
		# (lCtrl-lAlt-grey+)  1d  38  4a  ce  b8  9d
		#                    ML^ ML@ MG- BG+ BL@ BL^
		# (lCtrl-lAlt-grey-)  1d  38  4e  ce  b8  9d
		#                    ML^ ML@ MG+ BG+ BL@ BL^
		# Mxx = Make xx
		# Bxx = Break xx
		# xLx = left
		# xRx = right
		# xGx = grey
		# xx^ = control
		# xx@ = alt

		# Power saving:
		#	 set 1		| set 2
		# power: e0 5e / e0 de	| e0 37 / e0 f0 37
		# power: e0 5f / e0 df	| e0 37 / e0 f0 3f
		# power: e0 63 / e0 e3	| e0 37 / e0 f0 5e

	.text32

	mov	dx, ax
.if DEBUG > 3
	push	ax
	mov	ah, 0x40
	call	printhex
	pop	ax
.endif
	and	edx, 0xff
	mov	[keys_pressed + edx], ah

	# Check for shift key

	cmp	al, 0x2a	# left shift
	je	1f
	cmp	al, 0x36	# right shift
	jne	0f
1:	# have shift!
	mov	[kb_shift], ah
	jmp	4f

0:	cmp	al, 0x3a	# caps lock
	jne	4f
	xor	[kb_caps], ah	# ah=1=press,0=depress/ TODO: need to find init state

4:	or	ah, ah
	jz	2f	# only store keys that are pressed

	# translate 
	mov	dx, ax
	and	edx, 0x7f
	shl	dx, 1
	add	dl, [kb_shift]
	xor	dl, [kb_caps]
	shl	ax, 8 # preserve scancode
	mov	al, [keymap + edx]

.if DEBUG > 3
	#### debug print
	push	ax
	mov	ah, 0x3f
	stosw
	call	printhex
	pop	ax
	####
.endif

3:	#################
	call	buf_putw
.if DEBUG > 3
	#### debug print
	mov	dx, ax
	push	ax
	mov	ah, 0xf1
	mov	al, '!'
	stosw
	call	printhex
	mov	ah, 0xf2
	stosw
	pop	ax
	add	di, 2
	#####
.endif

2:	mov	[scr_o], di

	PIC_SEND_EOI IRQ_KEYBOARD
	pop	edx
	pop	eax
	pop	edi
	pop	es
	pop	ds
	iret

# Hook Keyboard ISR
keyboard_hook_isr:
	pushf

	call	keyboard_init

	cli

	mov	al, 0x20 # [pic_ivt_offset]
	add	al, IRQ_KEYBOARD
	mov	cx, SEL_compatCS
	mov	ebx, offset isr_keyboard
	call	hook_isr
	
	PIC_ENABLE_IRQ IRQ_KEYBOARD

	popf
	ret

.macro KBC_CMD v
	mov	al, KB_C_CMD_\v
	out	KB_IO_CMD, al
.endm

.macro KB_WRITE v=al
	.if \v != al
	mov	al, \v
	.endif
	out	KB_IO_DATA, al
.endm

.macro KB_CMD v
	KB_WRITE KB_CMD_\v
.endm

.macro KB_READ
	in	al, KB_IO_DATA
.endm

.macro KB_WAIT_DATA
88:	in	al, KB_IO_STATUS
	test	al, KB_STATUS_OBF
	jz	88b
.endm

.macro KB_EXPECT response, errlabel
	KB_WAIT_DATA
	KB_READ
	cmp	al, KB_RESPONSE_\response
	jnz	\errlabel
.endm



###############################################################
# Initialize Keyboard
keyboard_init:
	.if DEBUG
		I	"Keyboard "
#################################################

		I2	"reset "
	.endif

	KB_CMD	RESET
	KB_EXPECT ACK 9f
	KB_EXPECT PU 9f

	.if DEBUG
		printc	2, "ok "

#################################################

		I2 "disable INT "
	.endif

	KBC_CMD	MODE_READ
	KB_WAIT_DATA
	KB_READ
	mov	dl, al

	KBC_CMD	MODE_WRITE
	and	dl, ~KB_MODE_INT
	mov	al, dl
	KB_WRITE

	KBC_CMD MODE_READ
	KB_WAIT_DATA
	KB_READ
	cmp	al, dl
	jnz	9f

	.if DEBUG
		printc	2, "ok "

#################################################

		I2 "echo test "
	.endif

	KB_CMD	ECHO
	KB_EXPECT ECHO, 9f

	.if DEBUG
		printc	2, "ok "

#################################################
	# this seems to reboot
	#mov	al, KB_CMD_ENABLE # KB_C_CMD_INPORT_READ
	#out	KB_IO_CMD, al
#################################################

	I2	"rate "
	.endif

	KB_CMD	SET_RATE_DELAY
	KB_EXPECT ACK, 9f
	KB_WRITE 0	# fastest
	KB_EXPECT ACK, 9f

	.if DEBUG
		printc	2, "ok "

#################################################

	I2 "enable INT "
	.endif

	KBC_CMD MODE_READ
	KB_WAIT_DATA
	KB_READ

	or	dl, KB_MODE_INT
	KBC_CMD MODE_WRITE
	KB_WRITE dl

	KBC_CMD MODE_READ
	KB_WAIT_DATA
	KB_READ
	cmp	al, dl
	jnz	9f

	.if DEBUG
		printc	2, "ok "

		OK
	.endif

	call	newline
	call	newline
	call	newline
	call	newline
	sub	[screen_pos], dword ptr 4 * 160
	ret

9:	printc	12, ": not ack: 0x"
	mov	dl, al
	call	printhex2
	call	newline
	ret


keyboard_print_status:
	printc	14, " status: "
	in	al, KB_IO_STATUS
	push	edx
	mov	dl, al
	pushcolor 8
	call	printhex2
	call	printspace
	call	printbin8
	call	printspace
	popcolor
	push	esi
	LOAD_TXT "PERR\0TO\0MOBF\0INH\0A2\0SYS\0IBF\0OBF"
	call	print_flags8
	pop	esi
	pop	edx
	ret

keyboard_print_command_reg:
	push	edx
	printc 14, " mode: "

	KBC_CMD MODE_READ
	KB_WAIT_DATA
	KB_READ
	mov	dl, al
	pushcolor 8
	call	printhex2
	call	printspace
	call	printbin8
	call	printspace
	popcolor
	pop	edx
	ret

.data
KB_BUF_SIZE = 32
# circular buffer, hardware-software thread safe due to separate read/write
# variables. The read offset is however not software-software thread safe.
keyboard_buffer:	.space KB_BUF_SIZE
keyboard_buffer_ro:	.long 0	# write offset
keyboard_buffer_wo:	.long 0 # read offset
kb_count$: .long 0
.text32

buf_err$:
	pushf
	push	es
	push	edi
	push	edx
	mov	edx, eax
	mov	ah, 0xf4
	SCREEN_INIT
	PRINT "Buffer Assertion Error: avail: "
	call	printhex8
	PRINT " R="
	mov	edx, [keyboard_buffer_ro]
	call	printhex
	PRINT " W="
	mov	edx, [keyboard_buffer_wo]
	call	printhex
	pop	edx
	pop	edi
	pop	es
	popf
	ret

buf_avail:
	# shift view: wo = origin.
	mov	eax, [keyboard_buffer_ro]
	sub	eax, [keyboard_buffer_wo]
	dec	eax
	jge	0f
	# wo < 0, so ad KB_BUF_SIZE
	add	eax, KB_BUF_SIZE
	js	buf_err$ # shouldnt happen..
0:	ret

buf_putw:
	push	ebx
	mov	ebx, [keyboard_buffer_wo]
	mov	[keyboard_buffer + ebx], ax
	add	ebx, 2
	jmp	buf_put_$

buf_putb:
	push	ebx
	mov	ebx, [keyboard_buffer_wo]
	mov	[keyboard_buffer + ebx], al
	inc	ebx
	jmp	buf_put_$

buf_put_$:
	cmp	ebx, KB_BUF_SIZE-1
	jb	0f
	xor	ebx, ebx
0:	mov	[keyboard_buffer_wo], ebx
	pop	ebx
	ret


##########################################################################
### Public API 
##########################################################################

#Int 16/AH=09h - KEYBOARD - GET KEYBOARD FUNCTIONALITY
#Int 16/AH=0Ah - KEYBOARD - GET KEYBOARD ID
#Int 16/AH=10h - KEYBOARD - GET ENHANCED KEYSTROKE (enhanced kbd support only)
#Int 16/AH=11h - KEYBOARD - CHECK FOR ENHANCED KEYSTROKE (enh kbd support only)
#Int 16/AH=12h - KEYBOARD - GET EXTENDED SHIFT STATES (enh kbd support only)

KB_GET		= 0
KB_PEEK		= 1
KB_GETSHIFT	= 2
KB_SETSPEED	= 3
KB_GETCHAR	= 10

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
	cmp	ah, KB_PEEK
	jz	k_peek$
	cmp	ah, KB_GETSHIFT
	jz	k_getshift$
	cmp	ah, KB_SETSPEED
	jz	k_setspeed$
	cmp	ah, KB_GETCHAR
	jz	k_getchar$
0:	pop	esi
	pop	ds
	ret

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
	or	ax, ax # ZF = 1
	jmp	0b
k_getshift$:
	jmp	0b
k_setspeed$:
	jmp	0b

k_getchar$:
1:	xor	ah, ah
	call	keyboard
	cmp	ax, K_LEFT_SHIFT
	jz	1b
	cmp	ax, K_LEFT_CONTROL
	jz	1b
	cmp	ax, K_LEFT_ALT
	jz	1b
	cmp	ax, K_RIGHT_SHIFT
	jz	1b
	cmp	ax, K_RIGHT_CONTROL
	jz	1b
	cmp	ax, K_RIGHT_ALT
	jz	1b
	cmp	ax, K_CAPS
	jz	1b
	jmp	0b



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
