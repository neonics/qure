###############################################################################
#### CMOS #####################################################################
################# http://bochs.sourceforge.net/techspec/CMOS-reference.txt ####
###############################################################################
.intel_syntax noprefix

.text32
.code32

cmos_list:
	COLOR	8

	.macro CMOS_READ a
		mov	al, \a
		out	0x70, al
		in	al, 0x71
	.endm

	.macro CMOS_PRINTDEC a
		CMOS_READ \a
	.if 1
		# BCD byte
		mov	ah, al
		shr	al, 4
		add	al, '0'
		PRINTCHAR al
		shr	ax, 8
		and	al, 0xf
		add	al, '0'
		PRINTCHAR al
	.else
		# HEX byte
		movzx	edx, al
		call	printdec32
	.endif
	.endm

	.macro PRINTBITS8 reg, firstbit, width, msg
		PRINTc	7, "\msg"
		mov	dl, \reg
		shr	dl, \firstbit
		and	dl, (1 << \width) - 1
		call	printhex2
	.endm

	.macro PRINTIF reg, val, msg
		cmp	\reg, \val
		jne	9f
		PRINT	"\msg"
	9:
	.endm


0:	mov	edi, [screen_pos]

	# 0x0a: Read/Write
	PRINTc	9, "Status A: "
	CMOS_READ 0x0a
	mov	dl, al
	call	printhex2
	PRINTFLAG dl, 1<<7, " | Update Cycle in progress"
	PRINTBITS8 al, 0, 4, " | Rate Selection: "	# 6
	PRINTIF	dl, 0b0000, " None"
	PRINTIF	dl, 0b0011, " 122 microsec (minimum) (8197 Hz)"
	PRINTIF	dl, 0b1111, " 500 millisec (2 Hz)/500 microsec (2000 Hz)"
	PRINTIF	dl, 0b0110, " 976.562 microsec (1024 Hz)"
	PRINTBITS8 al, 4, 3, " | 22 Stage divider: "	# 2
	PRINTIF dl, 2, " 32768 Hz time base"
	call	newline

	# 0x0b: Read/Write
	PRINTc	9, "Status B: "
	CMOS_READ 0x0b
	mov	dl, al
	call	printhex2
	PRINTFLAG dl, 1<<7, " | Cycle Update"
	PRINTFLAG dl, 1<<6, " | Periodic INT"
	PRINTFLAG dl, 1<<5, " | Alarm INT"
	PRINTFLAG dl, 1<<4, " | Update-Ended INT"
	PRINTFLAG dl, 1<<3, " | Square wave"
	PRINTFLAG dl, 1<<2, " | Binary", " | BCD"
	PRINTFLAG dl, 1<<1, " | 24 hour", " | 12 hour"
	PRINTFLAG dl, 1<<0, " | Daylight Savings"
	call	newline

	# 0x0c: Readonly
	PRINTc	9, "Status C: "
	CMOS_READ 0x0c
	mov	dl, al
	call	printhex2
	PRINTFLAG dl, 1<<7, " | IRQ8"
	PRINTFLAG dl, 1<<6, " | Periodic INT"
	PRINTFLAG dl, 1<<5, " | Alarm INT"
	PRINTFLAG dl, 1<<4, " | Update ended INT"
	call	newline

	# 0x0d: Readonly
	PRINTc	9, "Status D: "
	CMOS_READ 0x0d
	mov	dl, al
	call	printhex2
	PRINTFLAG dl, 1<<7, " Battery good", " Disconnected / Battery empty"
	call	newline


	# Nonstandard. IBM PS/2:

	# 0x0e: Readonly
	PRINTc	9, "Status E: Diagnostics: "
	CMOS_READ 0x0d
	mov	dl, al
	call	printhex2
	PRINTFLAG dl, 1<<7, " | Clock lost power"
	PRINTFLAG dl, 1<<6, " | Incorrect Checksum"
	PRINTFLAG dl, 1<<5, " | Incorrect Equipment configuration"
	PRINTFLAG dl, 1<<4, " | Memory size error"
	PRINTFLAG dl, 1<<3, " | Controller/Disk failed initialization"
	PRINTFLAG dl, 1<<2, " | Time invalid"
	PRINTFLAG dl, 1<<1, " | Installed adaptors configuration mismatch"
	PRINTFLAG dl, 1<<0, " | Timeout reading adapter ID"
	call	newline

	# 0x0f: Readonly
	PRINTc	9, "Status F: Reset Code: "
	CMOS_READ 0x0d
	mov	dl, al
	call	printhex2
	PRINTCHAR ' '
	PRINTIF	dl, 0x00, "Software/unexpected reset"
	PRINTIF	dl, 0x01, "Reset after memory size check in real/virtual mode"
	# or:
	PRINTIF	dl, 0x01, "Chipset init for real/virtual mode reentry"
	PRINTIF	dl, 0x02, "Reset after successful memory test in real/virtual mode"
	PRINTIF	dl, 0x03, "Reset after failed memory test in real/virtual mode"
	PRINTIF	dl, 0x04, "INT 19h reboot"
	PRINTIF	dl, 0x05, "Flush keyboard (EOI) and jump via 40:0067"
	PRINTIF	dl, 0x06, "Skip EOI and jump via 40:0067"
	# or:
	PRINTIF	dl, 0x06, "reset (after successful test in virtual mode)"
	PRINTIF	dl, 0x07, "reset (after failed test in virtual mode)"
	PRINTIF	dl, 0x08, "Return to POST (used by POST during PMODE RAM test)"
	PRINTIF	dl, 0x09, "Used for IN 15/87h (block move) support"
	PRINTIF	dl, 0x0a, "Resume execution: jump via 40:0067"
	PRINTIF	dl, 0x0b, "Resume execution: iret via 40:0067"
	PRINTIF	dl, 0x0c, "Resume execution: retf via 40:0067"
	cmp	dl, 0x0d
	jb	9f
	PRINT	"Perform Power-On Reset"
9:
	call	newline


	# x00-x0E (14 bytes) MC146818 chip: clock
	# 10 rw data, 2 rw status registers, 2 ro status registers

	PRINTc	7, " Clock: "

	CMOS_PRINTDEC 6	# day of week (1=sunday)
	PRINTCHAR ' '
	xor	eax, eax
	CMOS_READ 6
	.data SECTION_DATA_STRINGS
	day_of_week$: .ascii "Sun\0Mon\0Tue\0Wed\0Thu\0Fri\0Sat\0"
	.text32
	lea	esi, [day_of_week$ + eax*4 - 4]
	call	print
	PRINTCHAR ' '


	CMOS_PRINTDEC 9	# year
	PRINTCHAR '/'
	CMOS_PRINTDEC 8	# month
	PRINTCHAR '/'
	CMOS_PRINTDEC 7	# date 
	PRINTCHAR ' '
	CMOS_PRINTDEC 4	# hours
	PRINTCHAR ':'
	CMOS_PRINTDEC 2	# minutes
	PRINTCHAR ':'
	CMOS_PRINTDEC 0	# seconds

	PRINTc	7, " Alarm: "
	CMOS_PRINTDEC 5	# hour alarm
	PRINTCHAR ':'
	CMOS_PRINTDEC 3	# minutes alarm
	PRINTCHAR ':'
	CMOS_PRINTDEC 1	# seconds alarm
	call	newline

.if 0
	PRINTc 11, "Press 'q' or ESC to continue, any other key to redraw"
	xor	ah, ah
	call	keyboard
	cmp	al, 'q'
	jz	0f
	cmp	ax, K_ESC
	je	0f

	mov	ecx, [screen_pos]
	sub	ecx, edi
	shr	ecx, 1
	mov	[screen_pos], edi
	PRINT_START -1
	mov	ax, 0x0f00
	rep	stosw
	PRINT_END ignorepos=1

	jmp	0b
0:	call	newline
.endif
	ret
