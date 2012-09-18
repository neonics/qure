.intel_syntax noprefix
.code32
.text


cmd_gfx:
	call	cls	# some scroll bug in realmode causes kernel reboot

	mov	eax, [esi+ 4]
	or	eax, eax
	jz	0f
	call	htoi
	#jmp	1f

0:	println "video modes:"
	push	dword ptr offset vesa_list_fb_modes
	call	call_realmode
	call	keybuf_clear
	mov	dx, [vesa_video_mode]
	or	dx, dx
	jnz	0f
	println "No suitable video mode found"
	ret

0:	print "Found video mode: "
	call	printhex4
	call	newline

###################################
	push	dword ptr offset gfx_realmode
	call	call_realmode
	call	keybuf_clear	# todo
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

1:
mov ecx, 256
mov al, 0
0: call printchar
inc al
loop 0b
printchar '!'	# tests the screen update thing
call	newline
xor ax, ax
call keyboard
cmp	ax, K_ENTER
jnz	1b

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
	push	dword ptr offset gfx_textmode
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

.data
gfx_palette_16:
.long 0x000000, 0xaa0000, 0x00aa00, 0xaa5500, 0x0000aa, 0xaa00aa, 0x00aaaa, 0xaaaaaa
.long 0x555555, 0xff5555, 0x55ff55, 0xffff55, 0x5555ff, 0xff55ff, 0x55ffff, 0xffffff

.text

# event handler: called from PRINT_END macro through [screen_update]
gfx_txt_screen_update:
	push	gs
	push	es
	push	ecx
	push	esi
	push	edi
	push	eax
	push	edx
	push	ebx

	mov	esi, SEL_flatDS
	mov	es, esi
	mov	edi, [vidfbuf]
	mov	esi, [screen_sel]
	mov	gs, esi
	xor	esi, esi
	mov	ecx, 25
0:	push	ecx
########
	push	edi
	mov	ecx, 80
1:	mov	ax, gs:[esi]
	add	esi, 2
	movzx	edx, ah
	and	dl, 0x0f	# only fg color for now
	mov	edx, [gfx_palette_16 + edx]
	call	gfx_printchar_8x16 # gfx_printchar
	loop	1b
	pop	edi
	mov	eax, 16#[fontheight]
	mul	dword ptr [vidw]
	mul	dword ptr [vidb]
	add	edi, eax
########
	pop	ecx
	loop	0b

	pop	ebx
	pop	edx
	pop	eax
	pop	edi
	pop	esi
	pop	ecx
	pop	es
	pop	gs
	ret

######################################
# in: es = SEL_flatDS
# in: vidfbuf, vidw, vidh, vidbpp, vidb
gfx_splash:
	mov	[curfont], dword ptr offset font_courier56
	mov	[fontwidth], dword ptr 32
	mov	[fontheight], dword ptr 50
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_32x50
	load_txt "Graphix Mode"
	call	gfx_calcstringcenter
	call	gfx_fadestring_center
###############################
# in: esi = string

	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16
	mov	[curfont], dword ptr offset font
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16

#######	left/right switch font
0:	xor	ax, ax
	call	keyboard
	cmp	ax, K_RIGHT
	jz	rf$
	cmp	ax, K_LEFT
	jnz	0f

	mov	eax, [curfont]
	sub	eax, 4096
	cmp	eax, offset fonts4k
	ja	3f
	jmp	0b

rf$:	mov	eax, [curfont]
	add	eax, 4096
	cmp	eax, offset fonts4k_end
	jae	0b

3:	mov	[curfont], eax
#######
	xor	edx, edx
	call	gfx_clear32
	mov	edx, -1
	call	gfx_calcstringcenter
	call	gfx_printstring
	jmp	0b

0:
######################################
	call	gfx_fill_bg32

	mov	ecx, [vidw]
	imul	ecx, dword ptr [vidh]
1:
	xor	ax, ax
	call	keyboard
	cmp	ax, K_ESC
	jz	1f

	mov	edi, [vidfbuf]
	push	edi
	push	ecx
0:	stosw
	stosw	# 32bpp
	loop	0b
	pop	ecx
	pop	edi

	jmp	1b
1:
	ret


# in: edx = color
gfx_clear32:
	push	edi
	mov	edi, [vidfbuf]
	push	edx
	mov	ecx, [vidw]
	imul	ecx, dword ptr [vidh]
	pop	edx
	mov	eax, edx
	rep	stosd
	pop	edi
	ret

gfx_fill_bg32:
	movzx	eax, word ptr [vidw]
	movzx	ecx, word ptr [vidh]
	mul	ecx
	mov	ecx, eax

	xor	edx, edx
	mov	eax, 0xff0000
	movzx	ebx, word ptr [vidw]
	div	ebx
	mov	ebx, eax	# ebx = 16.16 w inc

	xor	edx, edx
	mov	eax, 0xff0000
	movzx	ecx, word ptr [vidh]
	div	ecx
	mov	edx, eax
	
	push	edi
	mov	edi, [vidfbuf]
	##
	movzx	ecx, word ptr [vidh]
	xor	esi, esi
1:	push	ecx
	#
	movzx	ecx, word ptr [vidw]
	xor	eax, eax
0:	stosb
	push ax
	mov ax, si
	stosb
	pop ax
	push	edx
	push	eax
	add	ax, si
	shr	ax, 1
	stosw	# 32 bpp
	pop	eax
	pop	edx

	ror	eax, 16
	add	eax, ebx#@0x4000
	ror	eax, 16

	loop	0b
	#
	ror	esi, 16
	add	esi, edx
	ror	esi, 16
	pop	ecx
	loop	1b
	##
	pop	edi
	ret

# in: esi = string
# in: [fontwidth], [fontheight], [vidw], [vidh], [vidb], [vidfbuf]
# out: edi = pointer to video memory to render string centered on screen
gfx_calcstringcenter:
	push	edx
	push	eax

	mov	eax, [vidh]
	sub	eax, [fontheight]
	shr	eax, 1
	mul	dword ptr [vidw]

	push	eax
	mov	eax, esi
	call	strlen
	mul	dword ptr [fontwidth]
	movzx	edx, word ptr [vidw]
	sub	edx, eax
	shr	edx, 1
	pop	eax

	add	eax, edx
	mul	dword ptr [vidb]

	mov	edi, [vidfbuf]
	add	edi, eax

	pop	eax
	pop	edx
	ret


gfx_fadestring_center:
	mov	ebx, [clock]
	mov	edx, 0
1:	push	edx
	push	ebx
	call	gfx_printstring
	pop	ebx
	pop	edx
0:	cmp	ebx, [clock]
	jne	0f
	hlt		# BEWARE! pit must be enabled!
	jmp	0b
0:	mov	ebx, [clock]
	add	edx, 0x010101 * 8
	cmp	edx, 0xffffff
	jb	1b
	ret


.data
gfx_printchar_ptr: .long gfx_printchar_8x16
.text

# in: edx = fg color (bg transparent)
# in: esi = string
gfx_printstring:
######################
	push	edi
	push	esi
0:	lodsb
	or	al, al
	jz	0f
	call	gfx_printchar
	jmp	0b
0:	pop	esi
	pop	edi
######################
	ret
	
gfx_printchar:
	push	ebx
	mov	ebx, [gfx_printchar_ptr]
	add	ebx, [realsegflat]
	call	ebx
	pop	ebx
	ret

#######################################################################
# in: al = char
# in: edx = fg color
.data
curfont: .long 0
fontwidth: .long 0
fontheight: .long 0
.text
gfx_printchar_8x16:
	push	ebx
	push	eax
	push	edx
	movzx	eax, byte ptr [vidbpp]
	shr	eax, 3
	movzx	ebx, word ptr [vidw]	# screen width in pixels
	mul	ebx
	mov	ebx, eax
	movzx	eax, byte ptr [vidbpp]
	# for 32 bpp: 8*4=32
	# for 24 bpp: 8*3=24
	sub	ebx, eax
	pop	edx
	pop	eax
#	lea	ebx, [ebx + ebx*2 - 24]	# in bytes, subtract 3*8 bytes for char

	push	esi		# convert char to font offset
	movzx	esi, al
	shl	esi, 4		# 16 bytes per char
	add	esi, [curfont]

	push	ecx
	mov	ecx, 16	# 16 lines
2:	lodsb
	mov	ah, al
	.rept 8 # 8 bits per scanline
	add	ah, ah
	jnc	1f
	mov	es:[edi], edx
	jmp	3f
1:	cmp	edx, 0x01000000
	jb	3f
	# some alpha thing
3:
add	edi, 4	# 32 bpp
	
	.endr
	add	edi, ebx
	dec	ecx
	jnz	2b
	pop	ecx

	add	ebx, [vidbpp]
	shl	ebx, 4
	sub	ebx, [vidbpp]
	sub	edi, ebx

	pop	esi
	pop	ebx
	ret




# in: edx = color
# in: al = char nr
# in: es:edi topleft coordinate in video mem
gfx_printchar_32x50:
	push	ebx
	push	eax
	push	edx
	movzx	eax, word ptr [vidw]
	movzx	ebx, byte ptr [vidb]	# screen width in pixels
	mul	ebx
	shl	ebx, 5	# 4 bytes * 8 pixels per char-width
	#mov	ebx, 4 * 8 # 32
	sub	ebx, eax
	neg	ebx
	pop	edx
	pop	eax

	push	esi		# convert char to font offset
	push edx
	movzx	eax, al
	mov 	edx, 50 * 4 # 32/8
	mul	edx
	pop edx
	mov	esi, eax
	add	esi, offset font_courier56
#mov	esi, (offset font_courier56) + 50*4 * 33

	push	edi
	push	ecx
	mov	ecx, 50	# lines
2:
	lodsd
	.rept 32 # 8 bits per scanline
	add	eax, eax
	jnc	1f
	mov	es:[edi], edx
1:	add	edi, 4
	.endr
	add	edi, ebx
	dec	ecx
	jnz	2b
	pop	ecx
	pop	edi

	movzx	ebx, byte ptr [vidb]
	shl	ebx, 5
	add	edi, ebx

	pop	esi
	pop	ebx
	ret










keybuf_clear:
###################################
0:	mov	ah, KB_PEEK
	call	keyboard
	jz	0f
	mov	ah, KB_GET
	call	keyboard
	jmp	0b
0:	ret

#############################################################################
# 16 bit code
.text
.code16
gfx_textmode:
	mov	ax, 0x4f02
	mov	bx, 3 # 80x25 640x400 text mode
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
.text
.code16
vesa_video_mode: .word 0
vesa_list_fb_modes:
	mov	cs:[vesa_video_mode], word ptr 0

	push	bp
	push	es
	mov	bp, sp
	sub	sp, 512	# VBE 1.0: 256 bytes, 2+: 512 b
	###############

	mov	di, ss
	mov	es, di
	mov	di, sp
	# clear buf
	mov	cx, 512/2
	xor	ax, ax
	rep	stosw
	mov	di, sp
	# set 'VBE2' to get VBE 3.0 info
	# mov	es:[di + vi_vbeSignature], 'VBE2' # 'VESA'

	mov	ax, 0x4f00	# get vbe controller information
	int	0x10

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
	mov	sp, bp
	pop	es
	pop	bp
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
.text
.code16
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




########################################
vidfbuf: .long 0
vidw: .long 0
vidh: .long 0
vidbpp: .long 0
vidb:	.long 0
gfx_realmode:
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


.code32


.struct 0
#CRTCInfoBlock_HorizontalTotal: .word 0
crtci_h:	.word 0	# horizontal total pixels
crtci_hss:	.word 0	# horizontal sync start
crtci_hse:	.word 0 # .. .. end
crtci_v:	.word 0	# vertical total pixels
crtci_vss:	.word 0	# vertical sync start
crtci_vse:	.word 0 # .. .. end
crtci_flags:	.byte 0
crtci_pclock:	.long 0 # pixel clock Hz
crtci_rate:	.word 0 # refresh rate in .01 Hz
# reserve space rest of modeinfoblock (256 bytes total)



.text

.intel_syntax noprefix
.code32

.struct 0
pmib_sig: .long 0
pmib_entry: .word 0
pmib_pminit: .word 0
pmib_bios_ds: .word 0	# 0
pmib_a0000sel:	.word 0
pmib_b0000sel:	.word 0
pmib_b8000sel:	.word 0
pmib_cs:	.word 0
pmib_inpm:	.byte 0
pmib_checksum:	.byte 0
PMINFOBLOCK_STRUCT_SIZE = .


vesa_test:
	printc 11, "VESA check: "


ret

vesa_scan_pmid:
	# scan video bios 0xc000:0000 (first 32k) for PM InfoBlock structure
	push	es
	mov	ax, SEL_flatDS
	mov	es, ax
	mov	edi, 3
	mov	ecx, 128<<20 # 0xffffffff #32768 / 4
1:	mov	eax, ('P') | ('M'<<8) | ('I'<<16) | ('D'<<24)
	DEBUG_DWORD ecx
	repnz	scasd
	jz	0f
	DEBUG_DWORD ecx
	DEBUG_DWORD edi
	printlnc 12, "no vesa PMID block found"
	jmp	9f

0:	
	sub	edi, 4
	println "PMID block found"
	DEBUG_DWORD ecx
	DEBUG_WORD es
	DEBUG_DWORD edi
	mov	eax, es:[edi]
	add	edi, 4
	.rept 4
	call	printchar
	shr	eax, 8
	.endr


	# checksum
	#push	ds
	#mov	ax, SEL_flatCS
	#mov	ds, ax
	push	ecx
	mov	esi, edi
	sub	esi, 4
	xor	eax, eax
	mov	ecx, PMINFOBLOCK_STRUCT_SIZE
0:	#lodsb
	#add	ah, al
	mov	al, es:[esi]
	mov	dl, al
	call	printhex8
	add	ah, es:[esi]
	inc	esi
	loop	0b
	pop	ecx
	#pop	ds

	or	ah, ah
	jz	0f

	printc 12, "checksum error"
	jmp	1b
0:	printc 14, "checksum okay"
	jmp	9f



	print_16 "okay"
	call	newline_16
	print_16 "entry "
	mov	dx, es:[di + pmib_entry]
	call	printhex_16
	print_16 "init "
	mov	dx, es:[di + pmib_pminit]
	call	printhex_16
	jmp	9f


	print_16 "BIOS PMID: "
	mov	dx, di
	call	printhex_16
	jmp	9f
1:	print_16 "checksum error"


9:	pop	es
	ret

.code32
.data
fonts4k:
.if 0
.incbin "../fonts/4k/standard.fnt"
.incbin "../fonts/4k/8x10.fnt"
.incbin "../fonts/4k/8x11snsf.fnt"
.incbin "../fonts/4k/8x14.fnt"
.incbin "../fonts/4k/8x8.fnt"
.incbin "../fonts/4k/antique.fnt"
.incbin "../fonts/4k/archon.fnt"
.incbin "../fonts/4k/backward.fnt"
.incbin "../fonts/4k/bigserif.fnt"
.incbin "../fonts/4k/blcksnsf.fnt"
.incbin "../fonts/4k/block.fnt"
.incbin "../fonts/4k/bold.fnt"
.incbin "../fonts/4k/breeze.fnt"
.incbin "../fonts/4k/broadway.fnt"
.endif
font:
.incbin "../fonts/4k/computer.fnt"
font_4k_courier:
.incbin "../fonts/4k/courier.fnt"
.if 0
.incbin "../fonts/4k/cyrillic.fnt"
.incbin "../fonts/4k/deco.fnt"
.incbin "../fonts/4k/empty.fnt"
.incbin "../fonts/4k/eurotype.fnt"
.incbin "../fonts/4k/fat.fnt"
.incbin "../fonts/4k/finnish.fnt"
.incbin "../fonts/4k/flat.fnt"
.incbin "../fonts/4k/france.fnt"
.incbin "../fonts/4k/fresno.fnt"
.incbin "../fonts/4k/futura-1.fnt"
.incbin "../fonts/4k/futura-2.fnt"
.incbin "../fonts/4k/greek.fnt"
.incbin "../fonts/4k/hearst.fnt"
.incbin "../fonts/4k/hebrew.fnt"
.incbin "../fonts/4k/hylas.fnt"
.incbin "../fonts/4k/inverted.fnt"
.incbin "../fonts/4k/italics.fnt"
.incbin "../fonts/4k/kids-1.fnt"
.incbin "../fonts/4k/kids-2.fnt"
.incbin "../fonts/4k/lcd.fnt"
.incbin "../fonts/4k/medieval.fnt"
.incbin "../fonts/4k/modern-1.fnt"
.incbin "../fonts/4k/modern-2.fnt"
.incbin "../fonts/4k/norway.fnt"
.incbin "../fonts/4k/rev8x8.fnt"
.incbin "../fonts/4k/reverse.fnt"
.incbin "../fonts/4k/roman-1.fnt"
.incbin "../fonts/4k/roman-2.fnt"
.incbin "../fonts/4k/sanserif.fnt"
.incbin "../fonts/4k/sansurf.fnt"
.incbin "../fonts/4k/scott.fnt"
.incbin "../fonts/4k/script.fnt"
.incbin "../fonts/4k/silver.fnt"
.incbin "../fonts/4k/standard.fnt"
.incbin "../fonts/4k/stretch.fnt"
.incbin "../fonts/4k/super.fnt"
.incbin "../fonts/4k/surreal.fnt"
.incbin "../fonts/4k/swiss-1.fnt"
.incbin "../fonts/4k/swiss-2.fnt"
.endif
#
.incbin "../fonts/4k/swiss-3.fnt"
.if 0
.incbin "../fonts/4k/tekton.fnt"
.incbin "../fonts/4k/thai.fnt"
.incbin "../fonts/4k/thin.fnt"
.endif
fonts4k_end:

font_courier56:
#.include "../courier56.s"
.incbin "../fonts/courier56.bin"
