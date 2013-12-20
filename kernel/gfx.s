##############################################################################
# Graphics API
.intel_syntax noprefix

.global vidfbuf
.global vidw
.global vidh
.global vidbpp
.global vidb
.global vidsize

.global gfx_set_geometry
.global gfx_cls

.global fonts4k
.global curfont
.global fontwidth
.global fontheight
.global gfx_printchar_ptr
.global gfx_printchar_8x16
.global gfx_txt_screen_update

########################################

GFX_VBE = 0	# include realmode VESA support - defunct

########################################
.if GFX_VBE
.data16
.else
.data SECTION_DATA_BSS	# if gfx_vbe is used, make this .data16
.endif
vidfbuf:.long 0
vidw:	.long 0
vidh:	.long 0
vidbpp: .long 0	# bits per pixel
vidb:	.long 0	# bytes per pixel
vidsize:.long 0	# in pixels

#######################################################################
.text32
# in: [esp+0] = width
# in: [esp+4] = height
# in: [esp+8] = bpp
# callee clears stack
gfx_set_geometry:
	push_	eax edx
	mov	eax, [esp + 12]
	mov	[vidw], eax
	mov	edx, [esp + 16]
	mov	[vidh], edx
	imul	edx
	mov	[vidsize], eax
	mov	eax, [esp + 20]
	mov	[vidbpp], eax
	shr	eax, 3
	mov	[vidb], eax
	pop_	edx eax
	ret	3*4


# in: eax = color
gfx_cls:
	push_	es edi ecx
	mov	edi, SEL_flatDS
	mov	es, edi
	mov	edi, [vidfbuf]
	mov	ecx, [vidsize]
	rep	stosd
	pop_	ecx edi es
	ret


.data
gfx_palette_16:
.long 0x000000, 0x0000aa, 0x00aa00, 0x00aaaa, 0xaa0000, 0xaa00aa, 0xaa5500, 0xaaaaaa
.long 0x555555, 0x5555ff, 0x55ff55, 0x55ffff, 0xff5555, 0xff55ff, 0xffffff, 0xffffff

.data SECTION_DATA_BSS
gfx_last_scroll_lines$: .long 0
.text32
# event handler: called from PRINT_END macro through [screen_update]
gfx_txt_screen_update:
push eax; mov eax, cr3; push eax; mov eax, [page_directory_phys]; mov cr3, eax
	push	gs
	push	es
	push	ecx
	push	esi
	push	edi
	push	eax
	push	edx
	push	ebx

.if VIRTUAL_CONSOLES
	call	console_get
	mov	ebx, eax

#	xor	edx, edx
#	mov	eax, [ebx + console_screen_pos]
#	sub	eax, 160*25
#	jns	1f
#	xor	eax, eax
#1:

	mov	eax, SCREEN_BUF_SIZE - 160*25
	mov	esi, [ebx + console_screen_buf]

	# a little scroll check.
	cmp	byte ptr [scrolling$], 0
	jz	1f
	mov	eax, [scroll_pos$]
1:
	#mov	ecx, 25
	#div	ecx
	# eax = lines
	# edx = rest
	add	esi, eax	# +screen_buf_size -160*25
	mov	edi, SEL_flatDS
	mov	es, edi
	mov	edi, [vidfbuf]
.else
	mov	esi, SEL_flatDS
	mov	es, esi
	mov	edi, [vidfbuf]
	mov	esi, [screen_sel]
	mov	gs, esi
	xor	esi, esi
.endif

	mov	ecx, 25
0:	push	ecx
########
	push	edi
	mov	ecx, 80
		xor	ebx, ebx
1:
.if VIRTUAL_CONSOLES
	lodsw
.else
	mov	ax, gs:[esi]
	add	esi, 2
.endif
	movzx	ebx, ah
	shr	bl, 4
	mov	ebx, [gfx_palette_16 + ebx * 4]

	movzx	edx, ah
	and	dl, 0x0f	# only fg color for now
	mov	edx, [gfx_palette_16 + edx * 4]
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
pop eax; mov cr3, eax; pop eax
	ret



# event handler: called from PRINT_END macro through [screen_update]
# this one only copies what's already on the screen, doesnt use te buffer.
gfx_txt_screen_update_OLD:
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
		xor	ebx, ebx
1:	mov	ax, gs:[esi]
	add	esi, 2

	movzx	ebx, ah
	shr	bl, 4
	mov	ebx, [gfx_palette_16 + ebx * 4]

	movzx	edx, ah
	and	dl, 0x0f	# only fg color for now
	mov	edx, [gfx_palette_16 + edx * 4]
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

.if GFX_VBE	# splash called from gfx_vbe.s
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
	xor	eax, eax
	call	gfx_cls
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
.endif


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
.text32

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
# in: ebx = bg color
# in: es:edi = vid mem position
.data SECTION_DATA_BSS
curfont: .long 0
fontwidth: .long 0
fontheight: .long 0
.text32
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

	push	ebx
	mov	ebx, [esp + 12]	# bg color
	.rept 8 # 8 bits per scanline
	add	ah, ah
	jnc	1f
	mov	es:[edi], edx
	jmp	3f
1:	#cmp	edx, 0x01000000
	#jb	3f
	# some alpha thing
	mov	dword ptr es:[edi], ebx
3:
	add	edi, 4	# 32 bpp

	.endr
	pop	ebx

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


.if GFX_VBE	# called from gfx_vbe.s

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
.endif



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

#############################################################################
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

.text32
vesa_scan_pmid:
	printc 11, "VESA check: "
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


	print "entry "
	mov	dx, es:[di + pmib_entry]
	call	printhex
	print "init "
	mov	dx, es:[di + pmib_pminit]
	call	printhex
	jmp	9f


	print "BIOS PMID: "
	mov	dx, di
	call	printhex
	jmp	9f
1:	print "checksum error"


9:	pop	es
	ret

.data SECTION_DATA_FONTS
fonts4k:
.incbin "../fonts/4k/standard.fnt"
.if 0
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

.if GFX_VBE
font_courier56:
#.include "../courier56.s"
.incbin "../fonts/courier56.bin"
.include "gfx_vbe.s"
.endif

.text32
