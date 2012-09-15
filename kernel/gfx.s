.intel_syntax noprefix
.code32
.text


cmd_gfx:
	call	cls	# some scroll bug in realmode causes kernel reboot

#	call	vesa_test

	push	dword ptr offset gfx_realmode
	call	call_realmode

	call	keybuf_clear	# todo


	push	es
	mov	eax, SEL_flatDS
	mov	es, eax
	mov	edi, [vidfbuf]

	movzx	eax, word ptr [vidw]
	movzx	ecx, word ptr [vidh]
	mul	ecx
	mov	ecx, eax

	xor	edx, edx
	xor	eax, eax
	xor	ebx, ebx

# bgr
	push	edi
	push	ecx
0:	
	mov	al, dl
	stosb
	add	al, bh
	stosb
	mov	al, bl
	stosb
	inc	ebx
#	add	edx, ebx

	loop	0b
	pop	ecx
	pop	edi


1:
xor	ax, ax
call	keyboard
cmp	ax, K_ESC
jz	1f

	push	edi
	push	ecx
0:	stosw
	stosb
	loop	0b
	pop	ecx
	pop	edi



jmp	1b
1:


	pop	es

###################################

	push	dword ptr offset gfx_textmode
	call	call_realmode
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
VESA_MODE_INFO_BLOCK_LENGTH = .  # 512 for v2, v3
.text




.code16
vidfbuf: .long 0
vidw: .word 0
vidh: .word 0
gfx_realmode:
	println_16 "GFX realmode"

# VID MODES:
# 0x11f	1600x1200x24
# 0x11b 1280x1024
# 0x118 1024x768
# 0x115 800x600
# 0x112 640x480

#VID_MODE = (0x011b | (1<<14))	# 1280x1024x24 | (enable fb)
VID_MODE = (0x011f | (1<<14))	# 1280x1024x24 | (enable fb)

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
	mov	ax ,0x4f01 # get mode info
	mov	cx, VID_MODE
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

	mov	sp, bp	# info volatile
	pop	bp
	pop	es
	
	mov	ax, 0x4f02
	mov	bx, VID_MODE
	push	es
	mov	di, ss
	mov	es, di
	sub	sp, 512
	mov	di, sp
	int	0x10
	add	sp, 512
	pop	es
	ret

	mov	ax, 0xa000
	mov	es, ax
	xor	di, di
	xor	eax, eax
	.rept 12
	mov	cx, 1280
0:	inc	eax
	stosw
	stosb
	loop	0b
	.endr

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
