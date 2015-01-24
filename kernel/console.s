#############################################################################
# (Virtual) Console


.if VIRTUAL_CONSOLES
.struct 0
console_kb_buf:		.space KB_BUF_SIZE
console_kb_buf_ro:	.long 0
console_kb_buf_wo:	.long 0
console_kb_sem:		.long 0 # indicates whether data is available
CONSOLE_KB_STRUCT_SIZE = .
.data SECTION_DATA
console_kb_cur:.long consoles_kb	# initialize with first entry
.data SECTION_DATA_BSS
consoles_kb:	.space 10 * CONSOLE_KB_STRUCT_SIZE
.tdata
tls_console_kb_cur_ptr:	.long 0
.tdata_end
.text32
# in: eax
console_kb_set:
	push	edx
	mov	edx, CONSOLE_KB_STRUCT_SIZE
	imul	edx, eax
	add	edx, offset consoles_kb
	mov	[console_kb_cur], edx
	pop	edx
	ret

# out: ebx
console_kb_get:
	push	eax
	call	tls_get
	mov	ebx, [eax + tls_console_kb_cur_ptr]
	pop	eax
	ret
.endif


# 'root override' if you will...
kb_task:
# printing disabled due to unknown tls.
# so lets use default tls:
mov ebx, offset tls_default
mov [tls], ebx
	cmp	eax, K_KEY_CONTROL | K_KEY_ALT | K_DELETE
	jz	99f
	mov	ebx, eax
	xor	bh, bh
.if SCREEN_BUFFER
	cmp	byte ptr [scrolling$], 0
	jz	1f
	# in scroll mode:
	call	scroll
	jc	0f	# encountered non-scroll key, process
	ret	# key processed

	# not scrolling: check for scroll activation key:
1:	cmp	eax, K_PGUP
	jz	scroll	# ignore CF as we're sure this is a scroll key
0:
.endif
	cmp	ebx, K_KEY_CONTROL | 'c'
	jz	2f
.if VIRTUAL_CONSOLES
	# check alt-[digit]
	test	ebx, K_KEY_CONTROL | K_KEY_SHIFT
	jnz	0f
	test	ebx, K_KEY_ALT
	jz	0f
	sub	bl, '0'
	js	0f
	cmp	bl, 9
	jbe	3f
0:
.endif
9:	call	buf_putkey
	ret


99:	PRINTc 0xe2, "Ctrl-Alt-Delete"
	jmp	cmd_reboot

2:	PRINTc 0xe2, "^C"
	printlnc 0xb8, " Stack dump: (nothing's broken! - press enter)"
	call	debug_printstack$
	ret

.if VIRTUAL_CONSOLES
3:	# switch console
	dec	bl
	jns	1f
	mov	bl, 9
1:
	mov	edx, [console_cur_ptr]
	mov	edx, [edx + console_pid]
	mov	eax, edx
#	call	suspend_task
	#jnc 1f; DEBUG "suspend_task error"; 1:

	movzx	eax, bl
	call	console_set
	call	console_kb_set

	mov	eax, [console_cur_ptr]
	mov	eax, [eax + console_pid]
	cmp	eax, -1
	jz	2f

0:	ret

# schedule console task
2:	LOAD_TXT "console0", eax
	call	strdup
	add	[eax + 7], bl
	push	eax
	push	dword ptr offset TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset console_shell

	# task args:
	mov	eax, [console_cur_ptr]
	mov	ebx, [console_kb_cur]
	mov	esi, [esp + 12]
	KAPI_CALL schedule_task	# callee stack cleanup
	jc	9f

	mov	ebx, [console_cur_ptr]
	mov	dword ptr [ebx + console_pid], eax
	jmp	0b

9:	printc 4, "error scheduling "
	call	println
	jmp	0b

# in: eax = console ptr
# in: ebx = console_kb ptr
# in: esi = task label
console_shell:
	mov	edx, eax
	call	tls_get
	mov	[eax + tls_console_cur_ptr], edx
	mov	[eax + tls_console_kb_cur_ptr], ebx
	
	printc_ 9

	printlnc 11, " - Press enter to open shell"
0:	xor	ax, ax
	call	keyboard
	cmp	ax, K_ENTER
	jnz	0b
	jmp	shell
.endif


.if SCREEN_BUFFER
.data SECTION_DATA_BSS
scrolling$: .byte 0
scroll_pos$: .long 0
.text32
# This method will check the keystroke given in eax.
# If it is a scroll-key (page up/down, arrow up/down), scroll mode is enabled
# and the screen buffer is scrolled accordingly.
# When scrolling reaches the bottom of the buffer, scroll mode is disengaged.
# If it is a non-scroll key, scrolling is disabled, and the screen is restored.
#
# in: eax = key
# out: CF = 1: key not processed (not scroll key); 0: key processed.
scroll:
	push	eax
	push	ecx
	push	esi
	push	edi

	SCROLL_DISPLAY_LINES = 25
	SCREENBUF_DISPLAY_END = SCREEN_BUF_SIZE - SCROLL_DISPLAY_LINES * 160

	# check if we were already in scroll mode
	cmp	byte ptr [scrolling$], 0
	jnz	1f	# yes: get scroll pos
	# no: initialize scroll pos; the trigger key is PGUP, which will
	# adjust the offset
	mov	dword ptr [scroll_pos$], SCREENBUF_DISPLAY_END
	mov	byte ptr [scrolling$], 1

1:	mov	esi, [scroll_pos$] # SCREENBUF_DISPLAY_END - SCROLL_DISPLAY_LINES * 160

	cmp	ax, K_UP
	jz	2f
	cmp	ax, K_DOWN
	jz	3f
	cmp	ax, K_ENTER
	jz	3f
	cmp	al, ' ' #K_SPACE
	jz	4f
	cmp	ax, K_PGDN
	jz	4f
	cmp	ax, K_PGUP
	jz	5f
	# don't fall out of scroll mode when these are pressed:
	cmp	ax, K_LEFT_CONTROL	# same as right
	jz	6f
	cmp	ax, K_LEFT_ALT	# same as right
	jz	6f
	cmp	ax, K_LEFT_SHIFT
	jz	6f

	# not a scroll key: 
	# trigger full redraw/buffer flush:
	.if SCREEN_BUFFER_FIRST
	.if VIRTUAL_CONSOLES
	mov	eax, [console_cur_ptr]
	mov	[eax + console_screen_buf_pos], dword ptr -2
	.else
	mov	dword ptr [screen_buf_pos], -2
	.endif
	call	screen_buf_flush
	.endif
	mov	byte ptr [scrolling$], 0
6:	stc	# mark key as not processed
	jmp	9f

3: # down 1 line
	add	esi, 160

19:	# check end
	cmp	esi, SCREENBUF_DISPLAY_END
	jb	0f
	mov	esi, SCREENBUF_DISPLAY_END
	jmp	0f
2: # up
	sub	esi, 160
11:	# check start
	jns	0f
	xor	esi, esi
	jmp	0f
4: # page down
	add	esi, 160 * (SCROLL_DISPLAY_LINES - 4)
	jmp	19b
5: # page up
	sub	esi, 160 * (SCROLL_DISPLAY_LINES - 4)
	jmp	11b

0:
	#PRINTc 0xe2, "^"

	mov	[scroll_pos$], esi

0:	#push	dword ptr [tls]
	#mov	byte ptr [tls], -1
	mov	ecx, 160 * SCROLL_DISPLAY_LINES
	push	es
	mov	ax, SEL_vid_txt
	mov	es, ax
	push	esi
	.if VIRTUAL_CONSOLES
	mov	edi, [console_cur_ptr]
	add	esi, [edi + console_screen_buf]
	.else
	add	esi, [screen_buf]
	.endif
	xor	edi, edi
	rep	movsb
	pop	esi
	pop	es
	pushad
	mov	edi, [screen_update]
	add	edi, [realsegflat]
	call	edi
	popad
	#pop	dword ptr [tls]

	cmp	esi, SCREENBUF_DISPLAY_END
	jb	1f
	# 'fall out' of scroll mode:
	mov	byte ptr [scrolling$], 0
1:	clc	# key was proper, mark as processed
9:	pop	edi
	pop	esi
	pop	ecx
	pop	eax
	ret
.endif



.if VIRTUAL_CONSOLES
cmd_consoles:
	print "tls: "
	mov	edx, [tls]
	call	printhex8
	print " current console: "
	movzx	edx, byte ptr [console_cur]
	call	printdec32
	call	newline

	printlnc 15, "c pid..... buf..... pos..... ..x.. kb ro... kb wo... tls....."

	xor	ecx, ecx
	mov	esi, offset consoles
	mov	edi, offset consoles_kb
0:	mov	edx, ecx
	call	printdec32	# console nr
	call	printspace
	mov	edx, [esi + console_pid]
	call	printhex8
	call	printspace
	mov	edx, [esi + console_screen_buf]
	call	printhex8
	call	printspace
	mov	edx, [esi + console_screen_pos]
	call	printhex8
	call	printspace
	shr	edx, 1
	mov	eax, edx
	xor	edx, edx
	mov	ebx, 80
	div	ebx
	# calc space
	cmp	edx, 10
	jae	1f
	call	printspace
1:
	call	printdec32
	printchar 'x'
	mov	edx, eax
	call	printdec32
	cmp	edx, 10
	jae	1f
	call	printspace
1:	call	printspace

	mov	edx, [edi + console_kb_buf_ro]
	call	printhex8
	call	printspace
	mov	edx, [edi + console_kb_buf_wo]
	call	printhex8
	call	printspace

	mov	eax, [esi + console_pid]
	jecxz	1f
	or	eax, eax
	jz	2f
1:
	push	ecx
	call	task_get_by_pid
	mov	edx, [ebx + ecx + task_tls]
	pop	ecx
	call	printhex8

2:	DEBUG_DWORD esi;DEBUG_DWORD edi

	add	edi, CONSOLE_KB_STRUCT_SIZE
	add	esi, CONSOLE_STRUCT_SIZE

	call	newline
	inc	ecx
	cmp	ecx, 9
	jbe	0b
	ret
.endif


# Console Hardware:
.data
crt_io: .word 0x3b4	# better to call console_vga_init
.text32
console_vga_init:
	mov	dx, 0x3cc
	in	al, dx
	test	al, 1
	mov	dx, 0x3b4
	jz	1f
	add	dx, 0x020	# 3d4
1:
	mov	[crt_io], dx

	ret

VGA_CRTC_REG_CURSOR_LOC_LO = 0x0f
VGA_CRTC_REG_CURSOR_LOC_HI = 0x0e

console_set_cursor:
	push_	dx eax
	mov	dx, [crt_io]
	mov	al, VGA_CRTC_REG_CURSOR_LOC_LO
	out	dx, al
	inc	dx
	GET_SCREENPOS eax
	out	dx, al
	dec	dx
	mov	al, byte ptr VGA_CRTC_REG_CURSOR_LOC_HI
	out	dx, al
	shr	ax, 8
	inc	dx
	out	dx, al

	pop_	eax dx
	ret
