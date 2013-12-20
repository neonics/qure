##############################################################################
# VBE (VESA) Realmode Support

.text32
# protected mode commandline interface
cmd_gfx_VBE:
	call	cls	# some scroll bug in realmode causes kernel reboot

	mov	eax, [esi+ 4]
	or	eax, eax
	jz	0f
	call	htoi
	#jmp	1f

0:	println "video modes:"
	push	dword ptr offset vesa_list_fb_modes
	call	call_realmode
	call	keyboard_flush
	mov	dx, [vesa_video_mode]
	or	dx, dx
	jnz	0f
	println "No suitable video mode found"
	ret

0:	print "Found video mode: "
	call	printhex4
	call	newline

###################################
	push	dword ptr offset realmode_gfx_mode$
	call	call_realmode
	call	keyboard_flush
	call	pit_enable

#######
	push	dword ptr [screen_update]
	mov	[screen_update], dword ptr offset gfx_txt_screen_update

	.if 1
	mov	[curfont], dword ptr offset font_4k_courier #_courier56
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16
	.else
	mov	[curfont], dword ptr offset font_courier56
	mov	[fontwidth], dword ptr 32
	mov	[fontheight], dword ptr 50
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_32x50
	.endif

printchar '!'	# tests the screen update thing
call	newline

	push	es
	mov	eax, SEL_flatDS
	mov	es, eax
	mov	edi, [vidfbuf]
#########
	call	gfx_splash
#########
	pop	es
	pop	dword ptr [screen_update]
#######
	push	dword ptr offset realmode_txt_mode$
	call	call_realmode
###################################
	movzx	edx, word ptr [vidw]
	call	printdec32
	printchar 'x'
	movzx	edx, word ptr [vidh]
	call	printdec32
	printchar 'x'
	movzx	edx, byte ptr [vidbpp]
	call	printdec32
	call	printspace
	mov	edx, [vidfbuf]
	call	printhex8
	call	newline
	ret


###########################################################
# 16 bit code
.text16
realmode_gfx_mode$:
	println_16 "GFX realmode"

# VID MODES:
# 0x11f	1600x1200x24
# 0x11b 1280x1024
# 0x118 1024x768
# 0x115 800x600
# 0x112 640x480
# 0x123 640x400 No go

#VID_MODE = (0x011b | (1<<14))	# 1280x1024x24 | (enable fb)
#VID_MODE = (0x0112| (1<<14))	# 1280x1024x24 | (enable fb)

	push	es
	push	bp
	# reserve buffer
	mov	bp, sp
	sub	sp, 512
	mov	di, sp
	mov	ax, ss
	mov	es, ax
	xor	ax, ax
	mov	cx, 256
	rep	stosw
	mov	di, sp
	#mov 	ax, 0x4fxx
	#mov	cx, mmode
	mov	ax, 0x4f01 # get mode info
	mov	cx, cs:[vesa_video_mode] # VID_MODE
	or	cx, 1 << 14	# enable linear framebuffer
	int	0x10

	mov	edx, es:[di + vmi_PhysBasePtr]
	mov	cs:[vidfbuf], edx

	print_16 "vid mem base ptr: "
	call	printhex8_16
	mov	dx, es:[di+vmi_XResolution]
	mov	cs:[vidw], dx
	call	printdec_16
	printchar_16 'x'
	mov	dx, es:[di+vmi_YResolution]
	mov	cs:[vidh], dx
	call	printdec_16
	movzx	dx, byte ptr es:[di+vmi_BitsPerPixel]
	mov	cs:[vidbpp], dl
	printchar_16 'x'
	call	printdec_16
	shr	dx, 3
	mov	cs:[vidb], dx


	mov	sp, bp	# info volatile
	pop	bp
	pop	es


	mov	ax, 0x4f02
	mov	bx, cs:[vesa_video_mode] # VID_MODE
	or	bx, (1 << 14) #| (1<<15) # 14=linear fb, 15=clear mem
	push	es
	mov	di, ss
	mov	es, di
	sub	sp, 512
	mov	di, sp
	int	0x10
	add	sp, 512
	pop	es

	ret


#############################################################################
.text16
realmode_txt_mode$:
	mov	ax, 0x4f02
	mov	bx, 3 # 80x25 640x400 text mode
	push	es
	mov	di, ss
	mov	es, di
	sub	sp, 512
	mov	di, sp
	int	0x10

	# hide cursor
	mov	cx, 0x2000	# 0x2607 - underline rows 6 and 7
	mov	ah, 1
	int	0x10

	add	sp, 512
	pop	es
	ret

#############################################################################
.struct 0	# VbeInfoBlock
vi_vbeSignature:	.space 4	# 'VESA' or 'VBE2'
vi_vbeVersion:		.word 0		# 0x0300
vi_oemStringPtr:	.long 0		# VbeFarPtr
vi_capabilities:	.space 4
vi_videoModePtr:	.long 0		# vbeFarPtr to vidmode list
vi_totalMemory:		.word 0		# in 64k blocks (2.0+)
vi_oemSoftwareRev:	.word 0
vi_oemVendorNamePtr:	.long 0		# VbeFarPtr
vi_oemProductNamePtr:	.long 0		# VbeFarPtr
vi_oemProductRevPtr:	.long 0		# VbeFarPtr
vi_reserved:		.space 222
vi_oemData:		.space 256
VBE_INFO_BLOCK_SIZE = .


.text16

vesa_video_mode: .word 0

vesa_list_fb_modes:
print_16 "realmode!"

print_16 "ss:"; mov dx, ss; call printhex_16
print_16 "sp:"; mov dx, sp; call printhex_16
print_16 "ds:"; mov dx, ds; call printhex_16
print_16 "es:"; mov dx, es; call printhex_16
print_16 "cs:"; mov dx, cs; call printhex_16

	mov	cs:[vesa_video_mode], word ptr 0

	push	bp
	push	es
	mov	bp, sp
	sub	sp, VBE_INFO_BLOCK_SIZE	# VBE 1.0: 256 bytes, 2+: 512 b
	###############
print_16 "A"
	mov	di, ss
	mov	es, di
	mov	di, sp
	# clear buf
	mov	cx, 512/2
	xor	ax, ax
	rep	stosw
	mov	di, sp

print_16 "es:"; mov dx, es; call printhex_16
print_16 "di:"; mov dx, di; call printhex_16
	# set 'VBE2' to get VBE 3.0 info
	# mov	es:[di + vi_vbeSignature], 'VBE2' # 'VESA'

print_16 "B"
xor ax,ax; int 0x16
#call newline_16
#call rm_dump_int_10

#call rm_trap_isr_register
#push bp
#pushf
#mov bp, sp
#or word ptr [bp], 0x100	# trap flag
#popf

	mov	ax, 0x4f00	# get vbe controller information
	int	0x10

#	pushf
#	push	cs
#	push	word ptr offset 1f
#	push	word ptr ss:[0x6d * 4 + 2]	# ss is 0
#	push	word ptr ss:[0x6d * 4 + 0]	# ss is 0
#	retf
#1:
#	#DATA32 lcall	0:[0x6d * 4]


#pushf
#and word ptr [bp], ~0x100
#popf
#pop bp

#push es
#mov ax, cs
#mov es, ax
#mov ds, ax
#print_16 "C"
#pop es
	# print "VESA 2.0"

	mov	al, es:[di + vi_vbeSignature +0]
	call	printchar_16
	mov	al, es:[di + vi_vbeSignature +1]
	call	printchar_16
	mov	al, es:[di + vi_vbeSignature +2]
	call	printchar_16
	mov	al, es:[di + vi_vbeSignature +3]
	call	printchar_16
	mov	al, ' '
	call	printchar_16
	movzx	dx, byte ptr es:[di + vi_vbeVersion + 1]
	call	printdec_16
	mov	al, '.'
	call	printchar_16
	mov	dl, byte ptr es:[di + vi_vbeVersion]
	call	printdec_16
	mov	al, ' '
	call	printchar_16

	print_16 " Video memory: "
	mov	dx, es:[di + vi_totalMemory]
	.if 0
	shl	dx, 6
	call	printdec_16
	print_16 "kb"
	.else
	shr	dx, 4
	call	printdec_16
	print_16 "Mb"
	.endif


	#print_16 " ModePtr: "
	#mov	edx, es:[di + vi_videoModePtr]
	#call	printhex8_16
	#call	newline_16
	#mov	si, dx
	#shr	edx, 16
	#mov	es, dx
	call	newline_16

	les	si, es:[di + vi_videoModePtr]
0:	mov	dx, es:[si]
	cmp	dx, -1
	jz	0f
	#call	printhex_16
	add	si, 2

	mov	cx, dx
	call	vesa_print_mode

	jmp	0b
0:	call	newline_16

	###############
#	mov	sp, bp
	add	sp, VBE_INFO_BLOCK_SIZE
	pop	es
	pop	bp
print_16 "returning from realmode: "
pop dx
push dx
call printhex_16
call newline_16
	ret
#############################################################################
.struct 0 # vesa mode info block
vmi_ModeAttributes: .word 0
vmi_WinAAttributes: .byte 0
vmi_WinBAttributes: .byte 0
vmi_WinGranularity: .word 0
vmi_WinSize: .word 0
vmi_WinASegment: .word 0
vmi_WinBSegment: .word 0
vmi_WinFuncPtr: .long 0
vmi_BytesPerScanLine: .word 0
vmi_XResolution: .word 0
vmi_YResolution: .word 0
vmi_XCharSize: .byte 0
vmi_YCharSize: .byte 0
vmi_NumberOfPlanes: .byte 0
vmi_BitsPerPixel: .byte 0
vmi_NumberOfBanks: .byte 0
vmi_MemoryModel: .byte 0
vmi_BankSize: .byte 0
vmi_NumberOfImagePages: .byte 0
vmi_Reserved_page: .byte 0
vmi_RedMaskSize: .byte 0
vmi_RedMaskPos: .byte 0
vmi_GreenMaskSize: .byte 0
vmi_GreenMaskPos: .byte 0
vmi_BlueMaskSize: .byte 0
vmi_BlueMaskPos: .byte 0
vmi_ReservedMaskSize: .byte 0
vmi_ReservedMaskPos: .byte 0
vmi_DirectColorModeInfo: .byte 0
vmi_PhysBasePtr: .long 0
vmi_OffScreenMemOffset: .long 0
vmi_OffScreenMemSize: .word 0
.space 206
.space 256
VESA_MODE_INFO_BLOCK_LENGTH = .  # 512 for v2, v3

.text16
# in: cx = mode nr
vesa_print_mode:
	push	bp
	push	es
	push	di
	push	dx
	mov	bp, sp
	sub	sp, VESA_MODE_INFO_BLOCK_LENGTH

	mov	di, ss
	mov	es, di
	mov	di, sp
	mov	ax, 0x4f01
	int	0x10

#	.macro PF_16 bit, c, d=' '
#		test	dx, 1 << \bit
#		mov	al, \d
#		jz	99f
#		mov	al, \c
#	99:	call	printchar_16
#	.endm


#	PF_16 0, 'H'	# hardware
#	PF_16 2, 'B'	# tty bios output
#	PF_16 3, 'C', 'M' # color, monochrome
#	PF_16 4, 'G', 'T'	# text/gfx
#	PF_16 5, 'V'	# vga compatible
#	PF_16 6, 'W'	# vga compatible windowed mode
#	PF_16 7, 'F'	# linear framebuffer
#	PF_16 8, 'D'	# double scan available
#	PF_16 9, 'I'	# interlaced available
#	PF_16 10,'T'	# hardware triple buffering
#	PF_16 11,'S'	# hardware stereoscopic display
#	PF_16 12,'D'	# dual display start address

	pushcolor_16 15

	mov	edx, es:[di + vmi_PhysBasePtr]
	or	edx, edx
	jz	0f

	mov	dx, es:[di + vmi_ModeAttributes]
	test	dx, 1 << 7	# hardware framebuffer
	jz	0f

	mov	dl, es:[di + vmi_BitsPerPixel]
	cmp	dl, 24
	jb	0f

	mov	dx, cx
	call	printhex_16
	pushcolor_16 9
	mov	dx, es:[di + vmi_XResolution]
	call	printdec_16
	printchar_16 'x'
	mov	dx, es:[di + vmi_YResolution]
	call	printdec_16
	printchar_16 'x'
	movzx	dx, byte ptr es:[di + vmi_BitsPerPixel]
	call	printdec_16
	printchar_16 ' '
	popcolor_16

	# find video mode
	cmp	word ptr es:[di + vmi_XResolution], 1280
	jne	0f
	cmp	word ptr es:[di + vmi_YResolution], 960
	jne	0f
	cmp	byte ptr es:[di + vmi_BitsPerPixel], 32
	jne	0f

	print_16 "(16) vidmode: "
	mov	dx, cx
	call	printhex_16
	mov	cs:[vesa_video_mode], cx

0:

	popcolor_16
	mov	sp, bp
	pop	dx
	pop	di
	pop	es
	pop	bp
	ret


#############################################################################
# RealMode Debug Tracing

rm_trap_isr_register:
	push	es
	xor	ax, ax
	mov	es, ax

	mov	ax, offset rm_trap_isr
	mov	es:[0x1 * 4 + 0 ], ax
	mov	es:[0x1 * 4 + 2 ], cs
	pop	es
	ret

mycount: .word 0
rm_trap_isr:
	push	bp
	mov	bp, sp
	push	ds
	push	ax
	push	dx

	mov	ax, cs
	mov	ds, ax

	mov	dx, [bp + 4]
	call	printhex_16
	sub	word ptr [screen_pos_16], 2
	mov	al, ':'
	call	printchar_16
	mov	dx, [bp + 2]
	call	printhex_16

	cmp	dx, 0x5b48
	jz	3f
	cmp	dx, 0x5b47
	jnz	1f
3:
		push	es
		push	bx
		mov	dx, [bp + 4]
		mov	es, dx
		mov	bx, [bp + 2]
		mov	dx, es:[bx]
		print_16 "opcode="
		call	printhex_16
		pop	bx
		pop	es

		print_16 "ss:sp="
		mov	dx, ss
		call	printhex_16
		sub	[screen_pos_16], word ptr 2
		mov	dx, sp
		call	printhex_16

		print_16 "bp="
		mov	dx, bp
		call	printhex_16

		print_16 "[bp]="
		mov	dx, [bp]
		call	printhex_16

		jmp 2f

1:

	inc 	word ptr [mycount]
	cmp	word ptr [mycount], 8 * 20
	jb	1f
2:	xor	ax, ax
	int	0x16
	mov	word ptr [mycount], 0
1:

	pop	dx
	pop	ax
	pop	ds
	pop	bp
	iret


rm_dump_int_10:
	push es
	xor	si, si
	mov	es, si
	les	si, es:[0x6d * 4]

mov si, 0x5b40

	mov cx, 10
1:	mov dx, es
	call printhex_16
	sub [screen_pos_16], word ptr 2
	mov al, ':'
	call printchar_16
	mov dx, si
	call printhex_16
	sub [screen_pos_16], word ptr 2
	call printchar_16
	mov al, ' '
	call printchar_16

	push cx
	mov cx, 16
0:	mov dl, es:[si]
	inc si
	call printhex2_16
	mov al, ' '
	call printchar_16
	loop 0b
	call newline_16
	pop cx

	loop 1b

	xor ax,ax
	int 0x16

	pop es
	ret
