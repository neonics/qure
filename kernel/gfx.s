.intel_syntax noprefix
.code32
.text

cmd_gfx:
	call	cls	# some scroll bug in realmode
	print	"GFX "

	call	0f
0:	pop	ebx
	sub	ebx, offset 0b
		mov	edx, ebx
		print "IPB "
		call	printhex8

		print " esp: "
		mov	edx, esp
		call	printhex8

		print "PM return: "
		mov	edx, cs
	push	edx
		call	printhex4
		printchar ':'

	mov	edx, offset 0f
	push	edx
		call	printhex8
		add	edx, ebx
		call	printspace
		call	printhex8

		mov	edx, esp
		print " RM stack check: "
		call	printhex8
		
	# push address to realmode function: rm seg, unrelocated offs

	.if 0
		print	" RM addr: "
	GDT_GET_BASE edx, SEL_compatCS
	shr	edx, 4
		call	printhex4
		printchar ':'
	push	dx# xxx 
	mov	edx, offset gfx_realmode
	push	dx
		call	printhex8
		call	newline

	jmp	real_mode
	.else

	mov	edx, offset gfx_realmode
		print "  RM addr: "
		call	printhex8
		call	newline

	push	dword ptr offset gfx_realmode
	jmp	enter_real_mode
	.endif

0:
	println "GFX returned to pmode"
	call	pit_disable
	push	ds
	pop	es
	print "esp: "
	mov	edx, esp
	call	printhex8
	xor	ax, ax
	call	keyboard

	call	newline
	ret

.code16

gfx_realmode:
	println_16 "GFX realmode"
		print_16 "cs: "
		mov	dx, cs
		call	printhex_16

		print_16 " rm stack check: "
		mov	edx, esp
		call	printhex8_16

		print_16 "re-entering pmode: return addr: "
		push	bp
		mov	bp, sp
		add	bp, 2
		mov	dx, [bp + 4]
		call	printhex_16
		mov	al, ':'
		stosw
		mov	edx, [bp]
		pop	bp
		call	printhex8_16
		xor	ax, ax
		int	0x16
		call	newline_16

	xor	ax, ax
	jmp	reenter_protected_mode


reenter_protected_mode2:
	print_16 "foo!"
	ret
.code32
